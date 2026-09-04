# 帳戶總覽頁滑動快捷操作

日期：2026-09-04

設計依據：`docs/superpowers/specs/2026-09-04-account-swipe-actions-design.md`(本機
scratch 檔案，不隨 commit 一起走，細節不重複貼在這裡）。

## 做了什麼

`lib/pages/account/accounts_page.dart` 的帳戶列表新增左右滑動快捷操作：向右滑
露出「調整餘額」、向左滑露出「新增交易」（自動代入當前帳戶），方向與動作可在
齒輪選單裡自訂，兩個方向都設「無」即等同關閉。

- `lib/providers/account_swipe_action_providers.dart`（新檔案）：`AccountSwipeAction`
  枚舉 + `AccountSwipeSettings`(leftAction/rightAction) + 比照
  `reminder_providers.dart` 寫法的 `AccountSwipeSettingsNotifier`，SharedPreferences
  key 為 `account_swipe_left_action`/`account_swipe_right_action`，存 `enum.name`。
  刻意不接 `sync_engine_profile.dart` 的外觀同步管線——純本機 UI 手勢偏好，跨裝置
  不共用。已加進 `lib/providers/all_providers.dart` 的 export 清單。
- `lib/utils/account_quick_actions.dart`（新檔案）：把
  `account_detail_page.dart` 原本的私有方法 `_showBalanceAdjustmentDialog`
  抽成頂層函式 `showBalanceAdjustmentDialog(context, ref, account, l10n)`，滑動
  操作跟帳戶詳情頁的「調整餘額」按鈕共用同一份邏輯。因為需要在成功後 invalidate
  `accountTransactionsPaginatedProvider`（定義在 `account_detail_page.dart` 內），
  這個工具檔案反向 import 該頁面（`show` 限定只拿這一個 provider）——兩個檔案因此
  互相 import，Dart 允許這種循環（没有循環的 part-of 关系），已跑過
  `flutter analyze` 確認沒有問題。
- `account_detail_page.dart`：刪除原本的私有方法本體，「調整餘額」IconButton
  改呼叫新的頂層函式。
- `accounts_page.dart`：
  - 新增檔案層級私有 `_openSwipedAccountIdProvider`（`StateProvider<int?>`）記錄
    「目前展開的是哪一列」，暫態 UI 狀態、不持久化，展開新列自動收合舊列。
  - 新增私有 `_SwipeActionRow`（`ConsumerStatefulWidget` + `AnimationController`
    做開合緩動）：純水平拖曳、開合門檻（拖曳超過露出寬度 40% 或拋擲速度超過
    600px/s 即 snap 到全開）、露出區塊是整條實心色塊（調整餘額用 primaryColor，
    新增交易用收入綠，編輯帳戶用中性灰）、展開時點主體區域只收合不觸發原本
    onTap。兩個方向都是 `none`，或帳戶本身是主帳戶（`type == 'account_group'`）
    時直接回傳原始 child，不包裝任何手勢元件（零額外開銷）。
  - 只在三處「真正的葉節點 `_AccountCard`」呼叫點（`childCount == null` 的獨立
    帳戶/子帳戶/孤兒子卡）跟所有 `_ChildAccountRow`、`_HiddenAccountsSection`
    裡的 `_AccountCard` 包上 `_SwipeActionRow`；主帳戶（`childCount != null`）
    那個 `_AccountCard` 呼叫點維持原樣，不包裝。
  - `_handleSwipeAction` dispatcher（`_AccountsPageState` 實例方法）：調整餘額
    呼叫 `showBalanceAdjustmentDialog`；新增交易 `Navigator.push` 到
    `TransactionEditorPage(initialKind: 'expense', initialAccountId: account.id)`；
    編輯帳戶呼叫既有 `_editAccount`（跟長按同一入口）。

## 設定入口改放「個性化設定」頁（非原設計文件的帳戶總覽頁齒輪選單）

原設計把左滑/右滑動作選擇器放在帳戶總覽頁的齒輪選單（`_showSettingsSheet`）
裡；使用者當面看過畫面後，改要求放到「個性化設定」頁（`appearance_settings_page.dart`，
即「主題、字體、語言、應用鎖等」那個入口），理由是這類全域 UI 手勢偏好跟同頁
其它「金額顯示格式／備注顯示方式／收支顏色方案」等展示偏好放在一起更好找，
不需要為了改一個滑動方向去帳戶總覽頁翻齒輪選單。

- 從 `accounts_page.dart` 移除 `_showSettingsSheet` 裡的「滑動快捷操作」區塊跟
  對應的私有 widget `_SwipeActionSettingRow`；`_swipeActionLabel` 私有函式升級
  成 `lib/providers/account_swipe_action_providers.dart` 的公開頂層函式
  `accountSwipeActionLabel(l10n, action)`，供 `accounts_page.dart`（滑動按鈕
  文字）跟 `appearance_settings_page.dart`（選項清單）共用，避免兩處各刻一份
  對照表。
- `appearance_settings_page.dart` 新增一個 `SectionCard`（放在既有「多币种」
  卡片之前），兩個 `AppListTile`（右滑操作／左滑操作，`subtitle` 顯示目前選中
  動作），點擊彈出 `AlertDialog` 單選清單——寫法完全比照本頁既有的
  `_showThemeModeDialog`/`_buildModeOption` 等一系列 `_show...Dialog` +
  `_build...Option` 慣例，不引入新的 UI 模式。
- `_openSwipedAccountIdProvider`、`_SwipeActionRow`、`_SwipeActionButton` 等
  帳戶總覽頁列表本身的滑動手勢實作不受影響，只是「改哪個動作」的入口搬家。

## l10n

只動 `app_en.arb` + `app_zh_TW.arb`（[[feedback_l10n_policy_change]]）：新增
`accountSwipeSectionTitle`/`accountSwipeLeftLabel`/`accountSwipeRightLabel`/
`accountSwipeActionNone`/`accountSwipeActionAddTransaction`；順帶修正
`app_zh_TW.arb` 的 `balanceAdjustmentAction`（原本「調整總額」跟英文 "Adjust
Balance" 不一致，改成「調整餘額」，滑動按鈕文字沿用此 key）。`balanceAdjustmentDialogTitle`
維持「調整總額」不動（對話框標題語境不同，設計文件沒有要求連動修改）。

## 範圍外（刻意不做）

- 不同步此偏好設定到雲端 profile。
- 不影響帳戶選擇器 / 轉帳表單等其他列出帳戶的地方，只動帳戶總覽頁本身的列表。
- 不新增「總開關」，兩個方向都設「無」自然等於關閉。

## 修正:關閉狀態下背景按鈕透出

第一版有個真機才會現形的 bug——`_AccountCard`/`_ChildAccountRow` 本身沒有畫自己
的背景色，原本直接排在清單的 `Container(color: BeeTokens.surfaceElevated(...))`
裡，靠外層容器統一鋪底色；包上 `_SwipeActionRow` 後，前景內容變成疊在
`_buildBackground` 那層實心動作色塊上面，關閉狀態下（`offset == 0`）沒有自己的
不透明底色去蓋住背景，文字/圖示之間的透明縫隙直接透出底下橘/綠色塊跟按鈕文字，
造成「沒滑動也看得到兩個按鈕跟帳戶名稱疊在一起」。修法：前景的
`Transform.translate` 內層包一層 `ColoredBox(color: BeeTokens.surfaceElevated(context))`
再放 `widget.child`，確保關閉狀態完全遮住背景，只有實際拖出去才露出動作色塊。

## 測試

- `flutter analyze` / `dart format .`：無新增警告（既有的
  `use_build_context_synchronously` info 和 `SwitchListTile.activeColor`
  deprecation 是既有程式碼，跟本次改動無關）。
- 新增 `test/providers/account_swipe_action_providers_test.dart`：
  `AccountSwipeSettingsNotifier` 預設值、更新後立即反映在 state 上並持久化到
  `SharedPreferences`、重建後讀回變更後的設定。測試裡發現一個既有模式共有的
  時序細節——`StateNotifier` 建構子裡 fire-and-forget 的 `_loadSettings()`
  若晚於呼叫端的第一次 update 才 resolve，會把剛寫入的值蓋回預設值；測試改成
  先讀一次 `.notifier` 觸發建構並 `pumpEventQueue()` 等初始載入跑完，再進行
  update。這是 `reminder_providers.dart` 既有模式共有的限制，不是本次新增的
  回歸，這裡沒有動生產程式碼去修它。
- 手動驗證受限於本機環境沒有已選定的 Xcode（`xcode-select` 指向非 Xcode 路徑，
  需要 sudo 才能修正，本 session 無法自行執行），未能在 iOS 模擬器裡實機跑一輪
  §測試計畫列的手動驗證項目；改為發布一個可互動的 HTML 介面參考（拖曳體驗滑動
  開合），供設計走查用，不能取代真機/模擬器上的手勢驗證。
