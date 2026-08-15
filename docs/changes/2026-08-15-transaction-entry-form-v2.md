# 新增交易頁 / 轉帳頁 二次修正(v2)

日期:2026-08-15
背景:上一輪已經把「新增交易」頁改成單頁式表單(`TransactionEntryForm`,比照
Moze 參考圖)。使用者實測後回報六個問題,本次全部處理。

## 1. 鍵盤卡住/需要往下滑

**改了什麼**:`lib/widgets/biz/transaction_entry_form.dart`
`build()` 從單一 `SingleChildScrollView` 改成 `Column(Expanded(SingleChildScrollView(...)) + 底部固定 AmountCalculatorKeypad)`。新增
`_nameFocus`/`_merchantFocus` 兩個 `FocusNode`,任一欄位聚焦時
(`_textFieldFocused`)底部小算盤換成 `SizedBox.shrink()`,讓出空間給系統
鍵盤;點金額顯示區的 `GestureDetector` 會 `FocusScope.of(context).unfocus()`
收起系統鍵盤,小算盤重新出現。`lib/widgets/transaction/transfer_form.dart`
(v2 單頁式轉帳,見第 4 項)套用同一套寫法。

**為什麼**:原本整頁包在一個 `SingleChildScrollView` 裡,`AmountCalculatorKeypad`
在捲動內容最底部;名稱欄位聚焦時系統鍵盤跟自訂小算盤同時佔用畫面,必須往
下滑才看得到送出鍵。拆成「內容可捲動 + 鍵盤固定貼底、跟系統鍵盤互斥」解決
兩層鍵盤搶版面的問題。

## 2. 帳戶選擇器把「合併帳單分組」容器帳戶當成可選項目

**改了什麼**:`lib/widgets/biz/account_card_picker.dart` 的 `_load()` 篩選
條件加一條 `a.type != 'account_group'`。

**為什麼**:v32 已經有「主帳戶(合併帳單分組)」機制——`Account.type ==
'account_group'` 是純管理容器(`accounts_page.dart` 的 `_resolveDisplayType`
有完整說明),本身不是可入帳的真實帳戶。但 `account_card_picker.dart` 原本
只用 `isTradableType(a.type)` 過濾,沒排除 `account_group`,導致容器本身
混進候選清單、自己形成一個型別標籤是原始字串 `"account_group"` 的分組。它
底下的子帳戶各自有真實 `type`,本來就會正常出現在對應分組裡——濾掉容器
本身即可,子帳戶不受影響。

## 3. TWD 顯示中國國旗

**改了什麼**:`lib/utils/currencies.dart` 拿掉 `'TWD': 'CN'` 這條覆寫,讓
TWD 走下面預設的 `code.substring(0,2)` 派生邏輯,自然得到 `'TW'`(中華民國
國旗)。

**為什麼/風險權衡**:原本的覆寫註解寫明是「中國大陸市場合規要求」——如果
這個 App 仍會透過大陸管道(國內應用商店、馬甲包)發布,改成台灣國旗可能有
上架合規風險。這次是使用者在確認過這個顧慮後明確要求全域改掉的(不需要再
顧慮大陸合規)。日後如果重新需要對大陸通路做特例,參考 `EUR: 'EU'` 的寫法,
在 `_currencyCountryOverride` 加一條依 build flavor 判斷的覆寫即可。

## 4. 轉帳頁沒有跟進單頁化

**改了什麼**:`lib/widgets/transaction/transfer_form.dart` 整頁重寫。舊版是
「先選轉出/轉入帳戶方格 grid → 兩個都選了自動彈出 `AmountEditorSheet` modal
填金額」的兩步流程;新版比照參考圖跟這次新版 `TransactionEntryForm`,單頁
呈現:兩張帳戶卡片並排(可點卡片開 `AccountCardPicker` modal 換帳戶、中間
交換方向鍵互換轉出/轉入)、金額(單一金額——見下方「未做的事」)、名稱、
商家、標籤/附件、日期、底部固定小算盤。存檔 orchestration(synthetic 帳戶
反查、跨幣別守衛、`addTransaction`/`updateTransaction`/tag/attachment/
`TxAuthorService`/`PostProcessor.sync`)照搬舊版邏輯,行為不變,只是觸發
時機從「modal 送出」改成「頁面小算盤送出鍵」。

連帶清理:`lib/widgets/biz/amount_editor_sheet.dart` 整個刪除。全 repo 搜尋
`AmountEditorSheet(` 原本只有 `transfer_form.dart` 一處在用,新版不再需要
這個 modal,1500+ 行的 widget class 變成死碼直接刪掉。裡面的
`AmountEditorResult` record 型別(`TransactionEntryForm` 跟
`transaction_editor_page.dart` 之間還在用)搬到 `transaction_entry_form.dart`
裡。`account_card_picker.dart` 新增 `excludeAccountId` 參數(轉帳頁排除對
側已選帳戶用,避免同一個帳戶同時是轉出又是轉入)。

**未做的事**:參考圖上有「轉出金額/轉入金額 + 匯率」的雙金額欄位(暗示支援
跨幣別轉帳,雙邊各自輸入金額、按匯率換算)。這次**沒有**做這個——現有
`_checkSameCurrency` 守衛明確禁止跨幣別轉帳(`.docs/multi-currency-ledger`
01 §4.4 的既有設計),這次只沿用參考圖的**視覺排版**(兩張帳戶卡片並排),
金額維持單一欄位、兩側金額必然相同。如果之後真的要支援跨幣別轉帳換算,
那是一個獨立的、需要重新設計餘額計算/同步邏輯的新功能,不在這次範圍內。

## 5. 新增「商家」欄位

**改了什麼**:
- `lib/data/db.dart`:`Transactions` 表加 `TextColumn get merchant`,
  `schemaVersion` 32→33,`onUpgrade` 加對應 migration(`ALTER TABLE
  transactions ADD COLUMN merchant TEXT`)。
- `lib/data/repositories/transaction_repository.dart` /
  `local/local_transaction_repository.dart` /
  `local/local_repository.dart`:`addTransaction`/`updateTransaction` 簽名
  加 `String? merchant`,寫法跟既有的 `note` 完全對齊(恒寫,`null` 會顯式
  清空)。
- `lib/widgets/biz/transaction_entry_form.dart` /
  `lib/widgets/transaction/transfer_form.dart`:各自加一個「商家」
  `TextField`(store 圖示),`AmountEditorResult` record 加 `merchant` 欄位。
- `lib/pages/transaction/transaction_editor_page.dart` /
  `lib/utils/transaction_edit_utils.dart` / `lib/pages/ai/ai_chat_page.dart`:
  `initialMerchant` 一路串到 `TransactionEditorPage` 建構式跟編輯回顯。
- `lib/cloud/sync/entity_serializer.dart`:push 序列化加
  `'merchant': tx.merchant`(寫法對齊 `note`,不是 `if (!=null)` 才發的
  v30 多幣別欄位那種寫法——`note`/`merchant` 這類自由文本欄位要能傳明確的
  `null` 讓 server 清空既有值)。
- `lib/cloud/sync/sync_engine_apply.dart`:pull path(`_applyTransactionChange`
  的 insert + update 兩處)加 `merchant` 讀取跟寫回,寫法對齊 `note`(無條件
  讀,不用 `containsKey` 保護——因為 push 端也是恒發這個鍵)。
- 四份 `.arb` 語系檔加 `transactionMerchantHint` key,跑過 `flutter gen-l10n`。

**為什麼**:記帳時常需要記錄「在哪裡花的」,跟備註(note)是兩件事,獨立
成一個欄位方便之後依商家做統計/搜尋。

**為什麼不用改 BeeCount Cloud 那個獨立 repo**:動工前已經查證
`/Users/andy/BeeCount-Cloud`(PostgreSQL)——`read_tx_projection.merchant`
欄位、`sync_applier.py` 的 `_LEDGER_MERGE_SPECS["transaction"]` 已經有
`("merchant", "merchant")` 這組 spec、web 的 POST/PATCH
`/write/ledgers/{id}/transactions` 也已經收這個欄位(`tests/test_tx_merchant.py`
可驗證,包含「PATCH 不帶 merchant 時保留舊值、顯式傳 `null` 才清空」的
partial-update 語意)。也就是說 Cloud 端這個欄位是**已經做好、只是這個 app
之前沒補上本地欄位跟同步接線**的狀態,這次把 app 端補齊、照 wire 契約用
同名鍵 `merchant` 推上去就會自動接上,不用去動那個有正式 `.env` 跟營運中
資料庫的獨立 repo。

**範圍外**:AI 記帳(`lib/services/billing/bill_creation_service.dart`)目前
把辨識到的商家名稱塞進 `note`,這次沒有把它接到新的 `merchant` 欄位——這是
手動輸入表單補欄位的需求,AI 自動填商家是後續獨立的任務。

## 6. 修改要留文件說明

這份文件本身就是這條規則的第一次實踐。規則本身寫進了 `CLAUDE.md`(見該檔案
「Change documentation」一節),要求之後每次非瑣碎修改都要在 `docs/changes/`
底下留一份對應說明。

## 驗證

- `dart run build_runner build --delete-conflicting-outputs`:schema v33 生成
  無誤。
- `flutter gen-l10n`:四語系 `transactionMerchantHint` 生成無誤。
- `flutter analyze`:專案原有程式碼(不含 `packages/`/`scripts/` 既有 lint
  雜訊)無新增錯誤。
- `flutter test`(全套 630+ 案例綠燈):更新/新增了
  `test/widgets/account_card_picker_test.dart`(補 `account_group` 排除案例)、
  `test/widgets/transfer_form_account_hidden_test.dart`(改配合單頁式重寫
  隱藏帳戶鉤住的斷言;另外补了 `transactionAttachmentsProvider` 的 Stream
  override——這個 provider 是真實 Drift `.watch()`,單頁式轉帳頁面現在會
  無條件渲染附件列,測試環境下真的訂閱這個 stream 會在 widget 樹 dispose
  後留一個未觸發的取消訂閱 Timer,觸發 flutter_test 的 `!timersPending`
  斷言失敗並拖累同檔案下一個 test 卡死到 10 分鐘 timeout;不 override 直接
  給空 stream 即可)、`test/widgets/amount_editor_currency_test.dart`(改成測
  `TransactionEntryForm` 而不是已刪除的 `AmountEditorSheet`)、新增
  `test/repositories/transaction_merchant_test.dart`(merchant 欄位 add/update
  往返 + `serializeTransaction` 恒帶 `merchant` 鍵)、修正
  `test/data/sync_pull_errors_schema_test.dart` 裡寫死的 `schemaVersion ==
  32` 斷言為 `33`。
- 手動驗證(見 `/Users/andy/.claude/plans/luminous-painting-pike.md` 的驗證
  清單):新增支出/收入鍵盤不卡、帳戶選擇器排除容器帳戶、TWD 國旗、轉帳頁
  單頁式操作、編輯回顯商家欄位。
