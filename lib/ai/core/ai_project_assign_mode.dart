/// AI 記帳「專案指定」模式(design 2026-09-11,
/// docs/superpowers/specs/2026-09-11-ai-billing-project-assignment-design.md)。
///
/// - [none]:維持現狀,AI 記帳建立的交易不帶專案。
/// - [ask]:比照帳戶詢問邏輯,新增交易時跳出專案選擇器讓使用者選(可選「不
///   指定專案」)。
/// - [aiDecide]:AI 依帳單描述自動從目前有效的專案中挑選最合適的一個;沒填
///   或配對不到時退回 [ask] 的行為。
enum AiProjectAssignMode { none, ask, aiDecide }

/// [AiProjectAssignMode] 的 SharedPreferences 鍵名。Layer 1
/// (`AiExtractionContext.forLedger`)與應用層(`smart_billing_providers.dart`/
/// `BillCreationService`)共用同一份鍵名常量,避免各自硬編碼字串產生漂移。
const String kAiProjectAssignModeKey = 'smartBillingProjectAssignMode';
