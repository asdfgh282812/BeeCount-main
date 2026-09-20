# 信用卡帳單彙總視圖:交易列拿掉帳本標籤,卡片名+專案名改成靠右 pill

## 問題

信用卡「主帳戶(群組)」聚合視圖(`account_detail_page.dart` 的「交易明細」
tab,`繳款記錄`/`一般記錄` 兩個區塊)裡,每筆交易的標題列同時擠了:分類/
備註標題、帳本名稱標籤、子卡卡片名稱標籤(`accountTagName`,例如「遠東快樂
卡」)。這一列的可用寬度本來就被圖示+標題+金額瓜分,使用者反饋想在卡片名前
面加上專案名稱(例如「遠東信用卡 遠東快樂卡」)方便一眼看出這筆消費歸在哪個
信用卡專案下,但直接塞進標題列的標籤只會讓本已擁擠的版面更容易被擠爆
(`Row` 裡標籤不是 `Flexible`,沒有折行/省略號兜底)。

同時,合併帳單分組視圖本來就只會顯示同一個帳本底下的交易,標題列的帳本標籤
在這個視圖裡是多餘資訊。

## 修法

`TransactionTile`(`lib/pages/account/account_detail_page.dart`):

- 新增 `showLedgerBadge`(預設 `true`,不影響既有呼叫端)。信用卡帳單彙總
  視圖(`_buildBillingRecordsSection` 的呼叫點)傳 `false`,不再顯示帳本
  標籤;`general_account_period_view.dart`(一般帳戶明細頁,可能混雜多帳本
  交易)維持不傳、保留原本行為。
- 拿掉標題列裡 `accountTagName` 的獨立標籤 `Container`,時間文字維持原樣
  純顯示時間,不再混入卡片名。
- 改成在金額下方新增一排靠右對齊的 pill(`_buildTagChip`,比照使用者提供
  的 moze 截圖:實心邊框、依歸屬類型各自一個顏色,跟標題列裡帳本/延後入帳
  那種淺底標籤刻意做出區隔):有關聯專案時顯示「專案名」(`primaryColor`
  邊框,跟既有 `transaction_list_item.dart` 的 `_buildProjectChip` 用同一個
  主題色,一致），一定會顯示「卡片名」(`BeeTokens.info` 邊框,跟專案 pill
  用不同色相區分)。專案名透過 `projectsStreamProvider` 依
  `transaction.projectSyncId` 對回 `Project.syncId` 取得。這排 pill 放在
  金額下方的 `Column(crossAxisAlignment: end)` 裡,天然靠右;每個 pill 有
  `maxWidth: 120` + `maxLines: 1` + 省略號兜底,不會把版面擠爆。

## 刻意不動的部分

- 一般帳戶明細頁(`general_account_period_view.dart`)沒有傳
  `accountTagName`,行為不受影響,帳本標籤照舊顯示在標題列。
- `projectsStreamProvider` 是依「目前帳本」查詢(跟記帳表單選專案同一份),
  沒有另外處理跨帳本查專案的情況——信用卡帳單彙總視圖本來就只聚合同一帳本
  底下的交易,這裡不構成問題。
