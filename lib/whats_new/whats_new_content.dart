import '../l10n/app_localizations.dart';

/// 一則「新功能」條目:標題+說明都是取 l10n 文字的函式,而不是預先算好的
/// String——維持跟 [AppLocalizations] 一樣「依當前 locale 現算」的語意,
/// 讓這份資料可以在 build 之外的地方被建構、拿到 context 時才決定語言。
class WhatsNewItem {
  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) description;
  const WhatsNewItem({required this.title, required this.description});
}

/// 版本 → 該版本新增功能清單。key 為 `pubspec.yaml` 的 version 號(不含
/// build number),例如 `3.3.0+1` 對應 key `'3.3.0'`。
///
/// 這是新增「新功能公告」時**唯一需要編輯的地方**:在對應版本 key 下加一筆
/// [WhatsNewItem],並在 `app_en.arb`/`app_zh_TW.arb` 補上對應的 l10n 文字
/// (key 命名規則:`whatsNew<版本去除點號>Item<N>Title`/`...Desc`)。沒有
/// 內容的版本,彈窗與「我的」頁面入口都不會出現——見
/// `lib/widgets/ui/whats_new_dialog.dart`。
///
/// 刻意用 `final` 而非 `const`:每個 [WhatsNewItem] 的 title/description 都是
/// 函式字面量(closure),Dart 的 const 表達式不允許閉包,套上 `const` 會直接
/// 編譯錯誤。
final Map<String, List<WhatsNewItem>> kWhatsNewContent = {
  '3.3.0': [
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew330AiProjectTitle,
      description: (l10n) => l10n.whatsNew330AiProjectDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew330FirstDayOfWeekTitle,
      description: (l10n) => l10n.whatsNew330FirstDayOfWeekDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew330ClipboardImageTitle,
      description: (l10n) => l10n.whatsNew330ClipboardImageDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew330CardExclusionHintTitle,
      description: (l10n) => l10n.whatsNew330CardExclusionHintDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew330TxListProjectTagsTitle,
      description: (l10n) => l10n.whatsNew330TxListProjectTagsDesc,
    ),
  ],
  '3.4.0': [
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew340CuteIconsTitle,
      description: (l10n) => l10n.whatsNew340CuteIconsDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew340AnalyticsPieChartTitle,
      description: (l10n) => l10n.whatsNew340AnalyticsPieChartDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew340HideAccountAmountTitle,
      description: (l10n) => l10n.whatsNew340HideAccountAmountDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew340CardNotificationTitle,
      description: (l10n) => l10n.whatsNew340CardNotificationDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew340TxCurrencyTitle,
      description: (l10n) => l10n.whatsNew340TxCurrencyDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew340AiCrossCurrencyTitle,
      description: (l10n) => l10n.whatsNew340AiCrossCurrencyDesc,
    ),
  ],
  '3.5.5': [
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew355AiMerchantRewardTitle,
      description: (l10n) => l10n.whatsNew355AiMerchantRewardDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew355TransferAccountDisplayTitle,
      description: (l10n) => l10n.whatsNew355TransferAccountDisplayDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew355CreditCardPaymentParityTitle,
      description: (l10n) => l10n.whatsNew355CreditCardPaymentParityDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew355AccountInitialBalanceTitle,
      description: (l10n) => l10n.whatsNew355AccountInitialBalanceDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew355CalendarWeekTodayTitle,
      description: (l10n) => l10n.whatsNew355CalendarWeekTodayDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew355AiFreeChatQueryTitle,
      description: (l10n) => l10n.whatsNew355AiFreeChatQueryDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew355AiChatMarkdownTitle,
      description: (l10n) => l10n.whatsNew355AiChatMarkdownDesc,
    ),
    WhatsNewItem(
      title: (l10n) => l10n.whatsNew355AiChatDebugLogTitle,
      description: (l10n) => l10n.whatsNew355AiChatDebugLogDesc,
    ),
  ],
};
