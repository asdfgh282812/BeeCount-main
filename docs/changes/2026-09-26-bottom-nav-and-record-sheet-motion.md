# 底部導覽列滑動指示器／拖曳選分頁 + 記帳頁由下滑入／下滑關閉

## 入口

- 滑動指示器:App 主畫面底部懸浮導覽列(資產/專案/明細⇄記帳/報表/我的),點任一分頁即可看到。
- 拖曳選分頁:在同一條導覽列上按住往左右拖,放開就切到手指所在的分頁(仿 iOS 26 分頁列,不含玻璃材質)。
- 滑入轉場:切到「明細」分頁後,點底部中間的「＋ 記帳」按鈕。
- 下滑關閉:記帳頁開著時,從標題列/空白處往下拖;捲動區則要內容已在頂端時再往下拉。

## 改了什麼、為什麼

### `lib/widgets/ui/bee_tab_drag_scope.dart` — `BeeTabDragScope`(新檔)

膠囊本體 + 拖曳手勢都在這裡。`_BeeBottomBar` 維持 StatelessWidget,只透過 builder 拿到「此刻該亮哪一格」(`activeIndex`)和定位好的膠囊層。拆成獨立檔案是為了能單獨寫 widget test,因為 `app.dart` 的私有 widget 依賴整套 provider。

- 拖曳一開始膠囊「浮起」:放大 1.0→1.12(easeOutBack),底色 alpha 0.12→0.2。之後膠囊中心跟著手指走,限制在第一格和最後一格的置中位置之間。
- 跟隨方式是**短時長隱式動畫反覆重定目標**:每次 drag update 都讓 AnimatedPositioned 用 90ms easeOutCubic 從目前位置補間到新手指位置,效果等於一階平滑。從別的分頁起拖時,膠囊會快速滑過去而不是瞬移;正常拖曳時幾乎貼手。
- 手指下的分頁即時亮起;每跨一格呼叫一次 `HapticFeedback.selectionClick()`,起點那格不震。
- 放開時吸附到手指所在分頁,用 softSpring 300ms 並縮回原尺寸,再呼叫 `onSelected`。`_settlingIndex` 會在父層 currentIndex 更新前先頂住目標,否則中間那一幀膠囊會先往舊分頁彈再折返。
- **拖曳選頁走 `onTabDragSelect`,不走 `_handleTabTap`**:拖曳落點不該觸發「同分頁 300ms 內點兩下 = 捲到頂」的判斷;落在「記帳」態的中間按鈕也只是停留,不會開新增頁。
- 手勢競技場:外層是 HorizontalDrag,分頁本身是 Tap。手指移動超過 slop 才判給拖曳,所以一般點按不受影響。「記帳」態的中間按鈕另有 LongPress(快速記帳扇形選單):在那顆按鈕上按住不動 500ms,仍是扇形選單先勝出;先移動才是拖曳。其他分頁「按住一陣子再拖」也可以,因為 Tap 沒有逾時。

### `lib/app.dart` — `_BeeBottomBar`

- **舊做法**:每個分頁各自用 `AnimatedContainer` 切換底色,舊分頁淡出、新分頁淡入,看不出高亮從哪移到哪。
- **新做法**:改用 `BeeTabDragScope` 提供的一顆共用膠囊,放在 Stack 中「皮膚裝飾層」和「圖示 Row」之間,用 `AnimatedPositioned` 隱式補間 `left`(即 translateX)。
  - 時長 300ms,曲線是新的 `BeeMotion.softSpring`(微阻尼彈簧,見下)。
  - 膠囊寬度改成**固定寬**(`min(槽位寬 − 8, 64)`)。原本寬度隨 label 長短變化,滑動時會忽寬忽窄。高 46 則沿用舊版的視覺量。
  - 拖曳經過中間按鈕時只借用選中色;圖示和文字的明細⇄記帳仍以實際所在分頁為準,因為放開前還沒真的切過去。
- **圖示/文字選取態**:新增 `_TabItemContent`,用單一 0→1 選取進度 `t`(`TweenAnimationBuilder`,easeOutCubic 250ms)同時驅動顏色插值、字重插值(w400→w600),以及圖示縮放(1.0→1.08)。空心⇄實心圖形用 `AnimatedSwitcher` 交叉淡入加縮放。`t` 故意不套回彈曲線,因為 `t>1` 會讓 `Color.lerp` 外插出界,回彈感只留給膠囊本身。
- **行為變更:中間按鈕在「記帳」態會被高亮**。記帳態代表目前就在明細分頁,如果膠囊不滑到中間,切到明細時就只能憑空消失,滑動的連續感就斷了。以前中間按鈕永遠是 inactive 色。
- 頭像分頁:外框改為一直存在、顏色透明度跟著 `t` 變化。舊版 inactive 時 `border: null`,切換瞬間頭像會跳 1.5px。
- FeatureDot 紅點掛在 `AnimatedSwitcher` 外層,切換圖形時紅點不會跟著閃。

### `lib/styles/tokens.dart` — `BeeMotion.softSpring` / `BeeSpringCurve`

- 既有的 `BeeMotion.spring`(easeOutBack)回彈量固定約為位移距離的 10%,膠囊跨 4 個分頁時會甩出快 30px。
- `BeeSpringCurve` 是欠阻尼彈簧的閉式解(ζ=0.8、ω=8),回彈約 1.5%。它寫成 `Curve`,可以直接塞進 `AnimatedPositioned` 這類隱式動畫,不必另外開 SpringSimulation 和 controller。

### `lib/widgets/ui/slide_up_page_route.dart` — `SlideUpPageRoute`(新檔)

- 頁面 translateY 100%→0%,300ms,easeOutCubic。反向播放用同一條曲線,效果是先慢後快的加速離場(Material 的 exit 慣例),進出場時長相同。
- 遮罩用 ModalRoute 內建的 `barrierColor`(black54),`barrierCurve` 也是 easeOutCubic,跟頁面同步淡入淡出。
- `fullscreenDialog: true`:底層的 MaterialPageRoute/Cupertino 路由 `canTransitionTo` 會回傳 false,底下頁面不做左移視差,只被壓暗。
- `opaque: true`:TransitionRoute 在動畫中本來就會把 overlay 暫時設為不透明度 false,所以轉場期間看得到底層頁面與遮罩;動畫結束後才轉為不透明,底層頁面被 offstage、Ticker 停掉,避免首頁動態皮膚在背後持續重繪(測試有斷言這點)。
- 減少動畫開啟時退化為淡入淡出。

**下滑關閉**(`_SheetDismissGesture` + `_SheetScrollPhysics`,同檔):
- 手勢直接操作 route 的 AnimationController(value 1 = 展開、0 = 收到底部外),流程比照 Flutter Cupertino 返回手勢(`_CupertinoBackGestureController`):開始時呼叫 `didStartUserGesture`,收尾動畫結束才呼叫 `didStopUserGesture`。拖曳中遮罩也跟著即時變淡。
- 拖曳中(含收尾)`buildTransitions` 改用**線性映射**。easeOutCubic 在 value≈1 附近幾乎是平的,沿用的話手指往下拉頁面幾乎不動。收尾用 `animateTo`/`animateBack` 自帶 easeOutCubic,時長依剩餘距離等比縮短。
- 放開時:往下甩(> 700 px/s)或拖過 35% 高度就關閉,否則彈回。
- **兩種來源**:
  1. 不會捲動的區域(標題列、空白處、小算盤):外層 GestureDetector 的垂直拖曳。會捲動的區域,Scrollable 的辨識器在競技場裡比較深、會先勝出,所以這裡自然只接到「沒人要」的拖曳。**只在第一段有方向的位移往下時才啟動**:往上拉是記帳表單既有的「拉到底送出」(`PullToSubmitScrollView`,走原始指標事件),不能被吃掉或誤觸關閉。第一個 update 常是 0 位移,要略過(曾因此讓甩動關閉失效,測試有抓到)。
  2. 會捲動的區域:頁面內的 Scrollable 透過 `ScrollConfiguration` 套上 `_SheetScrollPhysics`,**只影響垂直方向**:頂端不回彈(同 iOS 原生 sheet),往下拉過頂端改發 `OverscrollNotification`,由手勢接手。之後改由外層 `Listener` 讀原始指標位移來驅動頁面,同時凍結內容捲動,避免內容和頁面一起動。拖回原位後手指若繼續往上,就把手勢還給內容照常捲動。底端照舊回彈,「拉到底送出」不受影響。
- 指標事件的派送順序是 hit-test 路徑上的 RenderObject(含外層 Listener)先收到,最後才由 GestureBinding 轉給辨識器。所以:接手那一步的越界量要在通知裡補上;放開時要晚一個 microtask 才解凍,否則辨識器的 drag end 會拿這次甩動的速度讓內容慣性滑動。
- 啟動條件見 `_canStartDismissGesture`。它等同 `ModalRoute.popGestureEnabled`(頂層路由、有 PopScope 擋關閉、動畫未結束都不行),但不能直接呼叫:`PageRoute` 把它覆寫成「fullscreenDialog 一律 false」。也不覆寫 `popGestureEnabled` 本身,因為 Android 預測式返回也讀它。
- 拖到一半時,表單若自己關掉了頁面(例如送出成功),放開時不會再 pop 一次(`isCurrent` 檢查),否則會連底下的頁面一起關掉。

## 刻意沒做的

- **點遮罩關閉實際上只有轉場期間有效**:`TransactionEditorPage` 是全螢幕 Scaffold,開好後會蓋滿整個畫面,沒有露出的遮罩可以點。要常駐可點的遮罩,得把記帳頁改成非全高的 sheet,這是版面改動,不在這次範圍。
- **iOS 左緣右滑返回**:自訂路由拿不到 Cupertino 的返回手勢(原因見 `lib/styles/bee_page_transitions.dart` 開頭註解),以下滑關閉取代。
- **玻璃材質**:iOS 26 分頁列的液態玻璃是系統原生效果,依需求不做。
- **捲動區拖回原位後的交接**:往下拖頁面、再往上推回原位時,內容要等拖回原位後才恢復捲動。iOS 原生是無縫交接,這裡在交接點會有一幀的停頓感,可接受。
- **RTL**:膠囊位置和拖曳落點以 LTR 計算。目前支援的語系(en/zh/zh_TW/ko)都是 LTR。
- **只換了中間「記帳」按鈕這個入口**。其他開 `TransactionEditorPage` 的地方(編輯既有交易、帳戶頁、AI 對話、桌面小工具 deep link)維持原本轉場:編輯是「進入某筆資料」,不是「建立」,方向性語意不同。

## 測試

- `test/widgets/slide_up_page_route_test.dart`:
  - BeeSpringCurve 的端點、回彈上限與非線性。
  - SlideUpPageRoute 的滑入位置、遮罩透明度、反向收回,以及結束後底層頁面 offstage 且 Ticker 停止。
  - 下滑關閉:空白處拖過門檻關閉、小段彈回、快甩關閉、先往上不啟動、捲動區先捲內容再拖頁面、PopScope 擋關閉。
- `test/widgets/bee_tab_drag_scope_test.dart`:點按滑動、拖曳跟手與浮起、經過的分頁亮起、觸覺回饋、放開吸附切頁且不觸發點按、超出兩端夾住。
- `_BeeBottomBar` 本身(`app.dart` 私有、依賴整套 provider)沒有 widget test,只驗證了 analyzer。
