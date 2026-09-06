/// 信用卡繳款(MOZE 對標,`doc.moze.app/credit-card/payment`)共用的純函式:
/// 群組分攤演算法 + 最早未繳清帳期掃描。不依賴 Drift/Riverpod,方便單元測試;
/// 呼叫端(`credit_card_billing_providers.dart`/`account_detail_page.dart`)
/// 負責把 repository 查詢接成這裡要的 callback 形狀。
library;

import 'card_reward_period.dart';

/// `asOf` cutoff 視為「含當天全部」——比照
/// `local_account_repository.dart::getAccountTransactions` 的 `endDate`
/// 慣例,`happenedAt <= 23:59:59` 才不會把當天發生的交易漏算。
DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

/// `asOf` cutoff 視為「不含當天」——用於算「上一期期末」(= 這一期第一天的
/// 前一刻)。
DateTime startOfDayExclusivePrior(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(const Duration(seconds: 1));

/// 鏡射 BeeCount Cloud `src/services/credit_card_billing.py::
/// compute_cycle_period_billing` 的 `max(charged - paid_total, 0)` watermark
/// 公式:[paidTotal] 是全部繳款的**終身加總**,不受 [charged] 的 asOf cutoff
/// 限制——不論繳款實際發生在哪個帳期,一律先套用在最早未清償的帳期上
/// (FIFO,見 `docs/changes/` 對應改動記錄的說明)。回傳值永遠 >= 0(欠款為
/// 正,已清償或溢繳一律回傳 0——溢繳結轉的顯示不是這個函式的職責)。
double creditCardDueAsOf({required double charged, required double paidTotal}) {
  final due = charged - paidTotal;
  return due > 0 ? due : 0.0;
}

/// 鏡射 BeeCount Cloud `src/services/credit_card_billing.py::
/// compute_card_payment_allocations` 的分攤規則(不是等比例打折):
/// 1. `amount` >= 全部子帳戶應繳總和:每個子帳戶各自拿到「完整付清」的金額,
///    剩下的溢繳另外記一筆在 [groupAccountId] 身上(結轉到未來各期的信用
///    額度)。
/// 2. `amount` < 應繳總和:按各子帳戶應繳金額比例分攤,最後一個子帳戶用
///    減法拿餘數,避免四捨五入加總對不上輸入金額。
///
/// [remainingDueByChild] 只放「目前仍欠款(> 0)」的子帳戶,金額 <= 0 的
/// 子帳戶不會出現在回傳結果裡。回傳金額都四捨五入到分(2 位小數)。
Map<int, double> allocateCardPayment({
  required Map<int, double> remainingDueByChild,
  required double amount,
  required int groupAccountId,
}) {
  double round2(double v) => (v * 100).round() / 100;

  final dueChildren = {
    for (final e in remainingDueByChild.entries)
      if (e.value > 0) e.key: e.value,
  };
  final totalDue = dueChildren.values.fold(0.0, (a, b) => a + b);

  final allocations = <int, double>{};
  if (totalDue <= 0) {
    if (amount > 0) {
      allocations[groupAccountId] = round2(amount);
    }
    return allocations;
  }

  if (amount >= totalDue) {
    for (final entry in dueChildren.entries) {
      allocations[entry.key] = round2(entry.value);
    }
    final leftover = round2(amount - totalDue);
    if (leftover > 0) {
      allocations[groupAccountId] =
          (allocations[groupAccountId] ?? 0.0) + leftover;
    }
    return allocations;
  }

  final entries = dueChildren.entries.toList();
  var allocatedSoFar = 0.0;
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final share = i == entries.length - 1
        ? round2(amount - allocatedSoFar)
        : round2(amount * (entry.value / totalDue));
    allocations[entry.key] = share;
    allocatedSoFar += share;
  }
  return allocations;
}

/// 「信用卡繳款」備註的固定前綴——鏡射 BeeCount Cloud
/// `src/services/credit_card_billing.py::CARD_PAYMENT_NOTE_PREFIX`。
/// [AccountRepository.getAccountStatementTransactions] 用這個前綴排除對帳
/// 清單裡的繳款轉帳(不論繳的是哪一期,見該方法文件註解),跟這裡的 note
/// 生成共用同一個字串常數,避免兩處各自硬編碼、其中一處改字漏改另一處。
const String cardPaymentNotePrefix = '信用卡繳款(帳單 ';

/// 繳款交易的備註文字——照抄 BeeCount Cloud
/// `src/routers/write/accounts.py::card_payment_ep` 的預設 note 生成:不是用
/// 使用者當下正在瀏覽的帳期(呼叫端可能是任何 offset),而是用「最近一次已
/// 結帳」的那一期([mostRecentlyClosedBillingOffset],鏡射 Cloud
/// `services/credit_card.py::most_recently_closed_cycle`)——這才是這筆錢
/// 實際在繳的那期帳單,不論使用者是在哪個帳期畫面點的「繳款」(2026-08-18
/// 使用者用「星展信用卡」實測反饋:在當期畫面繳款,備註卻寫成當期而非實際
/// 結清的上一期,見
/// `docs/changes/2026-08-18-credit-card-payment-note-server-parity.md`)。
/// 文字格式(含「信用卡繳款(帳單 ...)」中文字樣、`-`/`~` 分隔)逐字對齊
/// server 的 f-string,讓 App/Server 兩端寫出的繳款備註一致;
/// [isOverflowToGroup] 對齊 `card_payment_ep` 的
/// `tx_note = f"{note}(溢繳結轉)"`(繳款金額打到群組自己身上時加註後綴)。
String creditCardPaymentNote({
  required int? billingDay,
  bool isOverflowToGroup = false,
}) {
  String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  final offset = mostRecentlyClosedBillingOffset(billingDay);
  final period = billingCyclePeriod(billingDay, offset);
  final cycleStart = period.start.subtract(const Duration(days: 1));
  final cycleEnd = period.end;
  final base = '$cardPaymentNotePrefix${iso(cycleStart)}~${iso(cycleEnd)})';
  return isOverflowToGroup ? '$base(溢繳結轉)' : base;
}

/// 「繳款記錄」清單顯示用:一筆繳款金額橫跨多個帳期時,判斷它主要算哪一期
/// 「繳的」——回傳「這筆繳款最後沖銷到的那一期」,不是它開始沖銷的那一期,
/// 也不是它交易日期落在哪個日期窗口(那是 [cycleStart]/[cycleEnd] 純日期
/// 過濾的職責,見 `AccountRepository.getAccountStatementTransactions`,對帳
/// 模式/`get_account_statement` 用這套,不受這個函式影響)。
///
/// **這不是鏡射 Cloud 的邏輯**——直接查證 BeeCount Cloud 正式資料庫確認過,
/// `get_account_statement` 完全沒有這種「歸屬」概念,單純的日期窗口查詢。
/// 這是使用者明確要求的 App 端專屬行為(2026-08-18:使用者反饋「雖然是在
/// 8/11–9/11 這期繳費,但我繳的是上一期的費用,所以繳款記錄應該放到
/// 7/11–8/11」),範圍刻意收窄成只有帳戶詳情頁的「繳款記錄」小節顯示用,
/// 不影響「對帳模式」(`AccountReconciliationPage`/`AccountReconciliationSection`)
/// 或帳單彙總卡片的任何數字——那些數字全部繼續用 watermark 公式或純日期窗口,
/// 不受這裡影響。見 `docs/changes/2026-08-18-credit-card-payment-record-attribution-restore.md`。
///
/// [periods]:由舊到新排序,每個帳期帶自己的淨新增花費([periodId] 用
/// `billingCyclePeriod` 的 offset,越舊越小)。[payments]:由舊到新排序的
/// 繳款交易(`paymentId`/`amount`)。模擬「目前最舊還有欠款的帳期」指標依序
/// 被每筆繳款沖銷(沖完一期移到下一期,一筆繳款可能沖掉好幾期),每沖到一期
/// 就把指標更新成那一期——不像「開始沖銷的那期」只在第一次賦值,這裡持續
/// 更新到最後一次,所以回傳的一定是這筆繳款實際造成影響的**最新**那一期。
/// 這個目標一定不會是「這筆繳款開始處理前就已經欠款歸零」的歷史舊帳期
/// (指標只會往還有欠款的期別走)。同一筆交易不拆成兩半分別顯示在兩個帳期
/// ——UI 不用處理金額被切開顯示的複雜度,也符合使用者直覺「這筆錢主要是
/// 拿去繳哪期帳單」。純函式,不依賴 Drift/Riverpod。
Map<int, int> attributePaymentsToPeriods({
  required List<({int periodId, double newSpend})> periods,
  required List<({int paymentId, double amount})> payments,
}) {
  final home = <int, int>{};
  if (periods.isEmpty) return home;

  var periodIndex = 0;
  var remainingInPeriod = periods[periodIndex].newSpend;

  void advanceToNextUnpaidPeriod() {
    while (remainingInPeriod <= 0 && periodIndex < periods.length - 1) {
      periodIndex += 1;
      remainingInPeriod = periods[periodIndex].newSpend;
    }
  }

  for (final payment in payments) {
    advanceToNextUnpaidPeriod();
    var amountLeft = payment.amount;
    int? lastTarget;
    while (amountLeft > 0 && periodIndex < periods.length) {
      if (remainingInPeriod > 0) {
        final applied =
            amountLeft < remainingInPeriod ? amountLeft : remainingInPeriod;
        remainingInPeriod -= applied;
        amountLeft -= applied;
        lastTarget = periods[periodIndex].periodId;
      }
      if (amountLeft <= 0) break;
      if (periodIndex >= periods.length - 1) break;
      periodIndex += 1;
      remainingInPeriod = periods[periodIndex].newSpend;
    }
    home[payment.paymentId] = lastTarget ?? periods.last.periodId;
  }

  return home;
}

/// 規則一(MOZE 信用卡繳款文件):進入信用卡帳戶「交易明細」tab 時,預設
/// 停留在「尚未繳清的最早歷史帳期」,全部繳清才停在當期(offset 0)。
///
/// 從 offset=0 往回走,呼叫 [balanceOwedAsOf] 算每期期末的「仍欠款」金額
/// (正值=欠款,已透過呼叫端把終身跑動餘額轉正負號);一旦欠款歸零(已清償
/// 邊界),就停止往回掃,回傳「這個已清償邊界之後、最舊那一期」的 offset。
/// 若 offset=0(當期)本身就已清償,直接回傳 0。全部歷史都未清償時,回傳
/// [maxLookback] 對應的最舊 offset(避免永遠沒繳清的卡無限往回掃)。
Future<int> findEarliestUnpaidPeriodOffset({
  required Future<double> Function(int offset) balanceOwedAsOf,
  int maxLookback = 60,
}) async {
  var offset = 0;
  var earliestUnpaidOffset = 0;
  var foundUnpaid = false;

  while (offset > -maxLookback) {
    final owed = await balanceOwedAsOf(offset);
    if (owed > 0.005) {
      foundUnpaid = true;
      earliestUnpaidOffset = offset;
      offset -= 1;
    } else {
      break;
    }
  }

  return foundUnpaid ? earliestUnpaidOffset : 0;
}
