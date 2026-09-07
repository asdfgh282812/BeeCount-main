# 信用卡到期自動扣繳:App 端補上設定欄位(對齊 Cloud)

## 背景

Web/Cloud 端（`BeeCount-Cloud`）信用卡帳戶編輯表單已有「自動扣繳」開關 +
「扣款來源帳戶」選擇器（`Accounts.auto_pay_enabled` /
`auto_pay_from_account_id`，服務端排程 `services/credit_card_autopay.py`
在繳款截止日自動從指定帳戶轉帳繳清應繳金額）。App 端的帳戶編輯頁
（`account_edit_page.dart`）完全沒有這兩個欄位——`docs/changes/
2026-09-05-credit-card-billing-group-accounts.md` 與
`2026-08-18-credit-card-payment-moze-parity.md` 都明確記載這是當時刻意排除
的範圍外項目。使用者在 App 端看到主帳戶(群組)編輯頁缺少這個 Web 端已有的
設定,反映後在本次補上。

## 範圍決策(刻意縮小)

**只做「設定欄位」(UI + 儲存 + 跨裝置同步),不做「App 端到期本地執行扣款」**:

- App 是本地優先架構,Cloud 的自動扣繳是**伺服器排程**(Python 背景服務)
  跑的,App 離線時不會執行。若要讓 App 端也能在離線情況下真的產生扣款
  交易,需要另外設計一套本地到期偵測 + 轉帳交易產生邏輯(含餘額不足、
  離線多日累積到期、重複觸發等邊界情況),工作量與這次「補欄位對齊」不對等,
  留給未來需要時再做。
- 這次做完後:使用者在 App/Web 任一端設定的「自動扣繳開關 + 來源帳戶」會
  跨裝置同步顯示一致,但**實際扣款動作只有 Cloud 端排程會執行**(前提是
  該帳本有啟用雲端同步且伺服器排程有跑)。App 端本身不會、也不嘗試在本地
  產生這筆扣款交易。

## 改動

### 1. 資料庫 schema(`lib/data/db.dart`,v57 → v58)

`Accounts` 表新增兩欄:
- `autoPayEnabled`(bool,預設 `false`)
- `autoPayFromAccountId`(text,可空)—— 另一個帳戶的 `syncId`,跟
  `parentAccountId` 同款用 syncId 做跨裝置穩定引用

Migration 用既有 `_addColumnIfMissing` helper,無需回填(既有資料兩欄分別
落 `false`/`null`,語意上等同「未開自動扣繳」)。測試見
`test/data/migration_v58_test.dart`。

### 2. Repository 層

- `lib/data/repositories/account_repository.dart`:`createAccount`/
  `updateAccount` 介面新增 `autoPayEnabled`/`autoPayFromAccountId`/
  `clearAutoPayFromAccountId` 參數
- `lib/data/repositories/local/local_account_repository.dart`:實際寫入
  邏輯。`autoPayEnabled`/`autoPayFromAccountId` 跟著既有的
  `clearCreditCardFields` 一起清空(切換出信用卡/主帳戶類型時)—— 自動扣繳
  只在額度/帳單日/還款日還在時才有意義
- `lib/data/repositories/local/local_repository.dart`:單純透傳給
  `_accountRepo`,`changeTracker` 記錄邏輯不變(沿用既有的
  `recordUserGlobalChange`)

### 3. 同步(`lib/cloud/sync/`)

- `entity_serializer.dart`:`serializeAccount` 新增兩個 wire 欄位。
  `autoPayEnabled` 跟 `hidden` 同款無條件 bool 送出;
  `autoPayFromAccountId` 跟 `parentAccountId`/`swipesmartCardId` 同款
  「無條件送出 + 空字串清空」約定
- `sync_engine_apply.dart`:`_applyAccountChange` 新增 pull 端 apply 邏輯。
  `autoPayEnabled` 用 D6 缺鍵保留語義(跟 `hidden` 一致);
  `autoPayFromAccountId` 用 containsKey 缺鍵保護 + 空字串清空(跟
  `parentAccountId` 一致)
- **沒有**改 `sync_engine_realtime.dart` 的 `SharedLedgerAccounts` 鏡像
  表——那張表本來就不收 `parentAccountId`/`swipesmartCardId`/`hidden`/
  `includeInTotal` 這類 Owner 側個人狀態欄位,自動扣繳同理不需要
- 完整 wire-contract 細節見 `docs/CLOUD_SYNC_INTEGRATION.md` §1.4

### 4. UI(`lib/pages/account/account_edit_page.dart`)

新增 `_buildAutoPaySection`(開關 + 來源帳戶選擇器,對齊 Cloud web
`AccountsPanel.tsx` 同款佈局),插入到兩處既有的「額度/帳單日/還款日」區塊
之後:
- `isAccountGroup`(主帳戶/群組)區塊
- `isCreditCard` 且未掛靠任何主帳戶(獨立信用卡)區塊的 `else` 分支

掛靠主帳戶的子卡(`hasParentAccount == true`)**不顯示**這個區塊——子卡的
額度/帳單日/還款日本來就移交主帳戶管理,自動扣繳同理只在主帳戶/獨立卡
自己身上設定,跟 Cloud web 的 `isBillingRoot` 概念一致。

來源帳戶候選清單:排除 `account_group` 類型(純管理容器,沒有自己的餘額可
扣)與自己,對齊 Cloud web `AccountsPanel.tsx` 的
`r.account_type !== 'account_group' && r.id !== form.editingId` 過濾規則,
在既有的 `_loadParentCandidates`(重新命名為 `_loadAccountCandidates`)裡
跟主帳戶候選清單共用同一次 `getAllAccounts()` 查詢算出。

驗證:開關開著但沒選來源帳戶時擋下儲存並跳 toast(對齊 Cloud web
`AccountsPage.tsx` 的 `autoPaySourceRequired` 驗證)。切換帳戶類型離開
信用卡/主帳戶時,連同額度/帳單日/還款日一起重置。

**故意不做的部分**:「快速新增主帳戶」彈窗(`_QuickCreateGroupSheet`)沒有
加這個區塊——那個彈窗本來就是刻意精簡的建立流程(連頭像設定都沒有,靠
之後回編輯頁補),且它不會預先載入其它帳戶列表供來源帳戶選擇,建立後可以
再回編輯頁補設定,跟頭像走同一套「先建立、之後在編輯頁補」模式。

## 測試

- `test/data/migration_v58_test.dart` —— schema/migration
- `test/cloud/sync/entity_serializer_auto_pay_test.dart` —— push 序列化
- `test/sync/account_auto_pay_apply_test.dart` —— pull apply(缺鍵保留 /
  空字串清空 / 新增帳戶三種情境)

UI 部分(開關/選擇器互動、驗證 toast)未寫 widget test。這個環境的
`beecount-web` launch 設定編譯失敗(`sqlite3` 走 `dart:ffi`,與 Web target
不相容,跟這次改動無關的既有限制),iOS Simulator 則卡在
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` 未設定
(需要使用者手動跑一次),兩者都無法在這次改動裡實際跑起來人工點一遍——只
靠 `flutter analyze`(無錯誤)+ 上述自動化測試 + 沿用同一個檔案裡已經在用
的元件寫法(`InkWell`+`InputDecorator` picker、`Switch`、`SectionCard`)驗證,
沒有實機/模擬器截圖佐證。
