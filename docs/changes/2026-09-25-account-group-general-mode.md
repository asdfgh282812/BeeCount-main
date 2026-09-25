# 主帳戶(群組)區分「信用卡合併帳單」與「一般群組」

## 背景

主帳戶(`Account.type == 'account_group'`,v32 起)當初是為信用卡合併帳單設計的。
銀行帳戶(例如「中信帳戶」底下掛台幣戶 + 日幣戶)也能用,但:

- 明細頁一律走信用卡帳單週期版面(新增花費/上期欠款/應繳金額、轉為分期、繳款記錄),對銀行群組沒有意義。
- 編輯頁一律顯示「主帳戶設定(合併帳單)」:信用額度、帳單日、還款日、自動扣繳,另外還有群組本來就沒有的「初始資金」。

## 做法:從子帳戶推出群組種類,不加欄位

群組種類**不存欄位**,規則集中在 `lib/utils/account_group_utils.dart`:

- 有子帳戶時看子帳戶類型:類型一致就跟著子帳戶,混合時只要有信用卡就算信用卡群組(跟資產頁原本的 `_resolveDisplayType`、web 端 `resolveAccountGroupDisplayType` 同一套規則)。
- 沒有子帳戶時看群組自己有沒有設帳單欄位(額度/帳單日/還款日/自動扣繳)。資產頁原本只看 `creditLimit`,這次改成看任一個帳單欄位。這是一個很小的行為變化:只設了帳單日、還沒掛子帳戶的群組,現在會歸到信用卡分組。

不加 schema 欄位,就不用改 Drift migration,也不用動 BeeCount Cloud 的同步契約(Cloud 也沒有這個欄位)。代價是群組種類是推出來的:「開了合併帳單開關,但帳單欄位全部留空、又還沒掛信用卡子帳戶」的群組,下次打開會被判成一般群組。這個情況刻意接受,因為它跟 Cloud/web 的判斷方式一致。

## 各檔案改動

- `lib/utils/account_group_utils.dart`(新):`accountGroupChildren`、`hasAccountGroupBillingFields`、`resolveAccountGroupDisplayType`、`isCreditCardAccountGroup`、`accountGroupHasCreditCardChild`。
- `lib/pages/account/accounts_page.dart`:`_resolveDisplayType` 改呼叫共用函式。
- `lib/pages/account/account_detail_page.dart`:
  - 「交易明細」tab:只有 `credit_card` 或信用卡群組才走帳單週期分支,一般群組改走 `GeneralAccountPeriodView`,並傳入 `groupChildren`。
  - 「帳戶資訊」tab:一般群組多一行子帳戶數量。
- `lib/pages/account/general_account_period_view.dart`:加上 `groupChildren` 參數,群組模式下:
  - 摘要與餘額趨勢改用新的 `accountGroupPeriodSummariesProvider` / `accountGroupBalanceTrendsProvider`,先取各成員的原幣數字,再在 widget 裡用 `convertBetweenCurrencies` 折算成群組幣種後加總(跟資產頁主帳戶合計同一套)。缺匯率的幣種會跳過,並顯示「XXX 缺少匯率，未納入合計」,不會當作 1.0 折算。趨勢只併入「納入總餘額」的子帳戶。
  - 多一張「子帳戶」卡:顯示合計餘額,每個子帳戶顯示原幣餘額,點擊可進入該子帳戶的明細頁。
  - 交易清單用 `extraIdsKey` 聚合子帳戶交易。每一列用該筆交易所屬子帳戶的幣種顯示金額,並判斷轉出/轉入方向,再標上子帳戶名稱。
  - 右上「+」新增交易時不預選帳戶,因為群組本身不能入帳。
  - 群組之間的內部轉帳(台幣戶→日幣戶)會同時算進轉出和轉入,總計淨額大致相互抵銷,沒有特別排除。
- `lib/providers/account_period_providers.dart`:新增上述兩個 group provider。
- `lib/pages/account/account_edit_page.dart`:
  - 群組設定卡改名「群組設定」,新增「信用卡合併帳單」開關。開啟後才會顯示額度/帳單日/還款日/自動扣繳。群組裡有信用卡子帳戶時,開關固定為開(停用)。
  - 存檔時如果開關是關的,會清空群組的帳單欄位,避免殘留欄位讓群組被誤判成信用卡群組。
  - 從信用卡類型切換成群組時,開關預設打開。
  - 群組不顯示「初始資金」,幣種欄位改成撐滿整列。例外:舊資料已經有非零初始資金時,仍保留這個欄位,讓使用者可以改回 0。
  - 從帳戶編輯頁「快速新增主帳戶」彈窗建立群組時,只有正在編輯的是信用卡才會顯示帳單欄位。
- l10n:在 `app_en.arb` / `app_zh_TW.arb` 新增 `accountGroupCardTitle`、`accountGroupCardHint`、`accountGroupMergedBilling*`、`accountGroupBalanceTotalLabel`、`accountGroupNoChildrenHint`、`accountGroupUnconvertedHint`。

## 入口

- 明細頁:資產頁 → 點主帳戶(群組)卡片。
- 開關:資產頁 → 長按/編輯主帳戶 → 「群組設定」卡 → 「信用卡合併帳單」。

## 測試

- `test/utils/account_group_utils_test.dart`:群組種類判斷規則。
- `test/widgets/account_group_period_view_test.dart`:群組模式的摘要聚合、外幣折算、缺匯率提示,以及子帳戶交易有聚合進清單。
