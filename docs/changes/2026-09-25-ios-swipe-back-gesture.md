# iOS 恢復「從左緣右滑返回」手勢

## 症狀

iOS 上所有頁面都無法從螢幕左緣右滑返回上一頁，只能點左上角返回鍵。修好
iOS 27 開機閃退（UIScene 遷移）後才被發現，看起來像是 Scene 修正造成的，
其實無關。

## 根因

`135f5de`（2026-09-05，已包含在 3.5.6）把全站頁面轉場換成自訂的
`BeePageTransitionsBuilder`，iOS 也一起套用。Flutter 的 iOS 返回手勢
（`_CupertinoBackGestureDetector`，框架私有類別）只有經過
`CupertinoRouteTransitionMixin.buildPageTransitions` 才會掛上去，也就是只有
`CupertinoPageTransitionsBuilder` 才有；自訂 builder 只做了 `SlideTransition`，
所以 iOS 整個失去右滑返回。

3.5.6 在 iOS 27 上一開就閃退，所以修好閃退之後的這一版，才是第一次在真機上
實際用到這個自訂轉場。

## 改動

- `lib/styles/bee_page_transitions.dart`：新增 `kBeePageTransitionsTheme`，
  亮色/暗色主題共用；iOS 用 `CupertinoPageTransitionsBuilder`，其它平台維持
  `BeePageTransitionsBuilder`。
- `lib/main.dart`：兩份主題原本各自寫一份平台對照表，改成共用上面的常數。
- `test/styles/bee_page_transitions_test.dart`：新增回歸測試，在 iOS 平台從
  左緣拖曳，確認會回到上一頁（改動前這個測試會失敗）。

## 取捨

- iOS 上改成原生 Cupertino 轉場，不再是自訂的曲線/淡入效果。自訂轉場本來
  就是「仿 iOS」，在 iOS 上直接用原生的反而最貼近，而且拖曳過程中動畫會跟著
  手指線性移動（`popGestureInProgress`），自訂 builder 做不到這點。
- iOS 上「減少動畫」（App 內開關或系統「減少動態效果」）不再退化成淡入淡出，
  改成保留原生滑動轉場。這跟 iOS 系統本身的行為一致（開啟減少動態效果後，
  系統的 push/pop 仍然是滑動，也仍然可以右滑返回）。如果改成在減少動畫時
  維持淡入淡出，手勢就又會消失，因為手勢偵測器沒辦法單獨拿出來用。
- 沒有自己重寫一份返回手勢：那需要存取 `TransitionRoute.controller`
  （`@protected`），等於要複製一大段框架內部邏輯，還得跟著 Flutter 升級同步
  維護，不划算。
- macOS 維持自訂轉場，不在這次範圍內。
