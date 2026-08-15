# 明細行事曆快速記帳聯動 + 新增交易日期/分類選擇器重構

日期:2026-08-16

## 1. 明細頁行事曆移除「+ 在該日記帳」橫條,改由底部 TabBar「記帳」聯動

**改了什麼**:`lib/pages/calendar/calendar_body.dart` 的 `_buildDateTransactionsList`
拿掉了上方「日期 + 在該日記帳」的頭部 Row(黃色按鈕),連帶刪除只被它呼叫
的 `_addTransactionForSelectedDate` 方法與 `TransactionEditorPage` import。
`lib/app.dart` 的 `_BeeBottomBar.onCenterTap`(底部 TabBar 中央「記帳 +」按
鈕)改成 `ref.read(calendarSelectedDateProvider)` 讀目前行事曆選中的日期,
非 null 時把「年月日」換到該日、「時分秒」沿用當下時間,組成
`TransactionEditorPage.initialDate` 傳入;選中日為 null(未選/不在明細 tab)
時退回原行為(不傳 `initialDate`,由表單內部用 `DateTime.now()`)。

**為什麼**:原本每個日期各自一顆「在該日記帳」按鈕,跟底部 TabBar 本來就有
的「記帳」按鈕功能重複,且底部按鈕永遠只能記今天。拿掉冗餘入口,讓兩者統
一由行事曆的選中狀態驅動——選哪天就從哪天記帳。`calendarSelectedDateProvider`
在 `CalendarBody._onDaySelected`/`jumpToToday`/`jumpToMonth` 裡本來就會同步
更新,這次不需要新增任何 provider,只是多一個讀者。

**測試**:`test/widgets/calendar_month_jump_test.dart` 原本用「在该日记账」
文案的存在與否斷言「當日列表是否收起」,改用空狀態文案「当天无交易」代替
(測試庫沒有任何交易,選中日必然落到空狀態分支)。

## 2. 新增交易表單:日期/時間拆成兩個獨立欄位 + 新版選擇器

**改了什麼**:新增 `lib/widgets/ui/entry_date_time_picker.dart`,提供
`showTransactionDatePicker`(月曆網格,`table_calendar` 套件,左上角鍵盤圖
示展開/收起 MMdd 4 位數字快速跳轉輸入框,右上角「今天」,下方取消/確定
pill 按鈕;預設下界 2000-01-01、上界 2100-12-31,不再像舊版 wheel 選擇器
那樣把上界鎖在 `DateTime.now()`——可以選未來日期)與
`showTransactionTimePicker`(HH:mm 雙欄 wheel,不含秒;同款鍵盤圖示切
HHmm 快速輸入,右上角「現在」)。`lib/widgets/biz/transaction_entry_form.dart`
與 `lib/widgets/transaction/transfer_form.dart`(轉帳表單是前者的複製改寫版,
見 v2 change doc)的 `_buildDateRow` 都改成回傳一個 `Row`:日期欄位固定顯示,
時間欄位只在使用者開啟「顯示交易時間」設定(`showTransactionTimeProvider`)
時才出現在旁邊;`_pickDate`/新增的 `_pickTime` 分別呼叫上面两个新函式,只更
新各自的年月日/時分,不影響另一半。舊版合併日期+時間兩步 wheel 流程
(`wheel_date_picker.dart` 的 `showWheelDateTimePicker`/`showWheelDatePicker`)
繼續留著給行事曆表頭年月跳轉等其它入口用,沒有刪除。

**為什麼**:原本日期/時間顯示在同一個可點區塊裡,一次只能靠兩步 wheel 選
完;新設計要求可以只改日期或只改時間、日期還要能選未來(例如預先登記下週
的訂閱扣款)。新增獨立檔案而不是直接改 `wheel_date_picker.dart`,是因為後
者的兩個函式仍有其它呼叫方(`calendar_body.dart` 月份跳轉、`home_page.dart`
年月選擇器等),改動範圍刻意只收在交易表單這一側。

**新增 l10n key**:`commonNow`(現在/Now/지금),四語 arb 都補了,並跑過
`flutter gen-l10n`。

## 3. 新增交易表單:分類網格固定 2 行 + 子分類改「切換」不再手風琴展開

**改了什麼**:`lib/widgets/category/category_selector.dart` 的
`CategorySelector` 新增 `compactGrid`(預設 `false`)參數。`false` 時完全
維持原本行為(4 欄不限行數、點有子分類的項目原地展開
`_SubcategorySelectorCard`)——分類管理/預算/搜尋/週期交易等其它 6 個呼叫
方都沒改。`true` 時改用新的 `_buildCompactGrid`:5 欄 × 固定 2 行高度
(`GridView` 自身滾動,超過兩行不會把外層撐到 3 行),點有子分類的項目直接
把整個網格換成該分類的子分類列表(不是原地插入),子分類列表的 index 0 固
定是新增的 `_CategoryBackItem`(返回箭頭 + 「返回」文字,點擊換回主分類列
表)。`_CategoryItem` 新增 `compact` 參數,壓小圖示(56/48 → 40/36)、字級
(12/11 → 10)與圖示-文字間距(8 → 4),避免 5 欄擠在一起。
`lib/widgets/biz/transaction_entry_form.dart` 的 `_buildCategorySection`
改傳 `compactGrid: true`,同時拿掉外層固定 `SizedBox(height: 300)`(網格改
成自己按 2 行定高,不用再靠外層撐死一個高度)。

**為什麼**:原本 4 欄手風琴模式在單頁式表單裡,選到有很多子分類的一級分類
時,原地展開的二級分類卡片會把後面的名稱/商家/帳戶等欄位一路往下推,要滑
很久才看得到金額輸入區。改成「整個網格區域切換」讓層級導覽不影響頁面其它
部分的位置。沒有直接改 `CategorySelector` 的預設行為,是因為它還被分類管
理頁等 6 個全頁面場景複用,那些場景本來就有足夠垂直空間、不手風琴展開反而
會讓「已展開的子分類」在使用者往下滑動瀏覽時憑空消失,體驗更差。

## 4. 新增交易表單:切換支出/收入/轉帳 tab 時系統鍵盤未收起,和自訂小算盤疊在一起

**改了什麼**:`lib/pages/transaction/transaction_editor_page.dart` 的
`_TransactionEditorPageState` 給 `TabController` 加一個 `_unfocusOnTabSwitch`
listener(`_tab.indexIsChanging` 為真時呼叫
`FocusManager.instance.primaryFocus?.unfocus()`),並補上原本沒有的
`dispose()`(移除 listener + `_tab.dispose()`)。

**為什麼**:`TabBarView` 底層是 `PageView`,三個子表單(兩個
`TransactionEntryForm` + 一個 `TransferForm`)全程保持掛載;切到別的 tab不
會讓舊 tab 裡聚焦的名稱/商家欄位自動失焦。如果不主動 unfocus,舊 tab 的系
統鍵盤會繼續停留在畫面上,跟新 tab 自己的自訂數字小算盤(只在沒有欄位聚焦
時才渲染,見 `TransactionEntryForm._textFieldFocused`)同時出現、彼此重疊。
