# 週期性交易第三輪實機修正(編輯彈窗選完不導航、Tab 同步時機錯誤)

延續 [2026-08-17-recurring-edit-entry-and-tab-sync-fixes.md](2026-08-17-recurring-edit-entry-and-tab-sync-fixes.md)
——上一版修完後使用者再次實機測試,發現該版修法本身各自帶了一個新的計時
(timing)類 bug(都不是回歸,是新修法沒考慮到的邊界情況)。

## 1. 交易明細卡點編輯 → 選完「此記錄/連同未來週期」後沒有導航進編輯頁

**現象**:點編輯圖示,彈出「修改此記錄 / 修改連同未來週期」選擇彈窗(這部分
正常);點任一選項後,彈窗關閉,但畫面停在原本的明細頁(或它下面的列表
頁),沒有 push 進 `TransactionEditorPage`。

**根因**:`TransactionDetailCard._handleEdit`(以及 `_handleCopy`、
`_handleRefund`)的既有寫法是:

```dart
Navigator.of(context).pop();       // 先关掉这张明细卡
if (!hostContext.mounted) return;
await TransactionEditUtils.editTransaction(hostContext, ref, ...);
```

這裡的 `ref` 是 `TransactionDetailCard` 自己的 `ConsumerState.ref`——pop
之後這個 State 就進入退場動畫,動畫跑完就會被 dispose,`ref` 隨之失效。
上一版修法把「修改此記錄/連同未來週期」的詢問挪到 `editTransaction`
內部、`push` 編輯頁**之前**:

```dart
recurringScope = await showRecurringEditChoiceSheet(context);
if (recurringScope == null || !context.mounted) return;
final refs = await _resolveRefs(ref, transaction);  // ref.read(...) 在这里
```

`showRecurringEditChoiceSheet` 要等**使用者真的點一下選項**才會 resolve
——這段等待的時間(使用者要看清楚彈窗、伸手點擊)幾乎必然超過明細卡退場
動畫的長度(Material bottom sheet 預設 ~250ms)。等使用者選完,明細卡的
`ref` 早就因為 dispose 失效,`_resolveRefs` 裡的 `ref.read(repositoryProvider)`
直接丟 Riverpod 的「used after dispose」例外。整條 `await` 鏈上沒有
`try/catch`,例外變成 unhandled Future error——不會讓 App 崩潰,但也不會
执行到後面的 `Navigator.push`,體感上就是「選完彈窗選項後什麼都沒發生」。

（這個 bug 平時難以用肉眼從程式碼審查抓到:上一版加的其他兩個地方
——`_handleCopy`/`_handleRefund` 走的 `copyTransaction`/`refundTransaction`
——也是同一個「pop 後用自己的 ref」寫法,但它們後面只等一段很快的純
DB 查詢,幾乎每次都能在 dispose 完成前跑完,所以沒有被實機測出來。）

**修法**:`showTransactionDetailCard(context, ref, transaction, category)`
其實從一開始就收了一個「呼叫端(明細卡開啟之前那個頁面)的 `ref`」當參數
——但舊code只用它來 `showModalBottomSheet`,從沒傳給 `TransactionDetailCard`
本身,卡片內部一直都是用自己那份、生命週期跟卡片一樣短的 `ref`。這次幫
`TransactionDetailCard` 新增一個必填欄位 `hostRef`,`showTransactionDetailCard`
把呼叫端傳進來的 `ref` 存進去;`_handleEdit`/`_handleCopy`/`_handleRefund`
以及 `_jumpToTransactionBySyncId`(跳轉去看退款關聯的原始交易,重新打開
另一张明细卡时同样會把 `ref` 传下去)全部改用 `widget.hostRef`,不再用
`ref`(State 自己的)。呼叫端(`TransactionList`、`account_detail_page.dart`
等)的 `ref` 綁定在頁面本身的生命週期上,遠比一張彈出式卡片長,不會有這
個 race。

`_handleDelete` 沒改——它是先把所有要用 `ref` 的操作做完、最後才
`Navigator.pop()`,`ref` 全程都在自己的 dispose 之前用完,不受影響。

測試:新增 `test/widgets/transaction_detail_card_edit_navigation_test.dart`
——刻意在「選擇彈窗跳出來」跟「使用者點選項」之間插入幾百毫秒的 `pump`
(模擬真實使用者的反應時間,讓卡片的退場動畫真的跑完、State 真的
dispose),藉此重現修復前只在真實裝置上、不在「彈窗一跳出來就立刻點」的
單元測試步調下才會出現的 race。

## 2. 切 Tab 時金額同步沒生效(仍顯示 0)

**現象**:上一版加的「切 tab 時同步共用欄位」機制(見上一份 changes 文件
第 3 項)沒有實際生效——支出輸入 600 後切收入,收入 tab 金額還是 0。

**根因**:`_syncSharedFieldsOnTabChange` 是掛在 `TabController`(`_tab`)
上的 listener,在 `_TransactionEditorPageState.initState()` 就註冊了。
`TabBarView` 自己也會訂閱同一個 `_tab` 當 listener——但它是在 `build()`
第一次執行、`TabBarView` 這個 widget 被建出來時才訂閱,時間點晚於
`initState()`。`ChangeNotifier`(`TabController` 底層)呼叫 listener 是
按照**註冊順序**同步呼叫的,所以使用者點 tab、`_tab.index` 改變的那一刻:

1. 我們自己的 `_syncSharedFieldsOnTabChange` 先被呼叫——這時候
   `TabBarView` 根本還沒反應過來、還沒觸發 rebuild,新切到的那個分頁
   （例如收入)的 widget **還沒被 build 出來**,`_incomeFormKey.currentState`
   是 `null`,`applySharedFields` 整個 no-op(靜默失敗,`?.` 吞掉了)。
2. 接著 `TabBarView` 自己的 listener 才被呼叫,呼叫 `setState()` 排定下一
   幀重建,這一幀才真的把收入分頁 build 出來——但這時候已經沒有人再呼叫
   一次 `applySharedFields` 了,收入分頁就停留在自己剛 `initState` 時的
   預設值(金額 0)。

**修法(第一版,不夠)**:一開始把「套用」改成透過
`WidgetsBinding.instance.addPostFrameCallback` 延後到「下一幀 build 完」
才執行,想法是 `TabBarView` 的 `setState()` 跟我們的 postFrameCallback是
同一輪同步呼叫裡分別觸發、搭的是同一個即將排定的下一幀。寫完之後補一個
widget test 才發現這個假設是錯的:`TabBarView` 底層是 `PageView`,換頁是
`_tab.animateTo(...)` 驅動、跨越 `kTabScrollDuration`(300ms、約 18 幀)
的動畫,`PageView` 的 cache 視窗要等動畫推進到一定進度、目標分頁真的進入
cache 範圍才會被 build 出來,不是換頁那一刻的下一幀就已經 mount 完成——
延後「一幀」還是太早,`GlobalKey.currentState` 常常仍是 `null`,套用又
一次靜默 no-op。

**修法(最終版)**:`_applySharedFields` 改成回傳 `bool`(是否真的套用成
功,即目標分頁的 `GlobalKey.currentState` 是否已經 mount);
`_applySharedFieldsWhenReady` 每一幀都用 `addPostFrameCallback` 檢查一次,
沒成功就排下一幀繼續重試,最多重試 30 幀(約 500ms,超過切頁動畫本身的
300ms),直到套用成功或放棄為止。這樣不管 `PageView` 實際上要幾幀才把鄰
近分頁 build 出來,都能在它真的 mount 之後補上這次套用,不用去猜測/依賴
`TabBarView` 內部確切的動畫—build 時序。

測試:新增 `test/widgets/transaction_editor_page_tab_sync_test.dart`——用
真的 `TransactionEditorPage`(不是直接建構 `TransactionEntryForm`),透過
`GlobalKey`/`State` 直接呼叫 `exportSharedFields`/`applySharedFields`(跟
正式程式碼機制完全一致)設值/驗證,不透過金額鍵盤 UI 打字——鍵盤數字鍵跟
金額顯示常常同時在畫面上出現相同文字(例如「0」),`find.text` 容易撞到不
只一個 widget,且鄰近分頁的 `AmountCalculatorKeypad` 何時被 `PageView`
build 出來這件事本身跟這個 bug 無關,不該讓測試因為這個時機而變 flaky。
真的透過 `TabBar` 點擊觸發 `_tab.index` 改變、`pumpAndSettle()` 讓切頁動
畫跑完,再讀取新分頁 State 的 `exportSharedFields()` 驗證欄位值——第一版
「延後一幀」的修法在這個測試下会直接失敗(`amountStr` 還是 `'0'`),換成
重試版才穩定通過,這個測試本身也因此成為第一版修法不夠的直接證據。

## 為什麼上一版的驗證沒抓到這兩個問題

上一版的 `flutter test` 全過、`flutter analyze` 乾淨,但沒有覆蓋到這兩個
問題,原因跟這次的根因直接對應:

- 第 1 項是純粹的執行時序 race,需要在「彈窗出現」跟「使用者選擇」之間
  插入真實時間流逝才會重現——上一版沒有寫涵蓋「明細卡 → 編輯彈窗 → 導航
  進編輯頁」這整條路徑的整合測試,`transfer_form_recurring_edit_test.dart`
  是直接建構 `TransferForm`,略過了明細卡跟它的 `pop()`。
- 第 2 項也是 listener 呼叫順序的時序問題,上一版沒有寫「真的透過
  `TransactionEditorPage` 切 tab、檢查另一個分頁欄位值」的測試,只驗證了
  `exportSharedFields`/`applySharedFields` 這兩個方法本身的存在跟型別,
  沒驗證它們在真實的 `TabController` 事件時序下真的會被呼叫。

沙盒環境依然沒有可用的 iOS 模擬器(`xcode-select` 未指向 Xcode.app,修正
需要使用者 sudo 密碼),這次改用會真正還原時序的 widget test 補上,而不是
單純的程式碼審查。
