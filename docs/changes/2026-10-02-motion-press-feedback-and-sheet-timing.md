# 動效與點擊回饋改善(三批)

日期:2026-10-02(分支 release/3.7.0)

來源是一次動效稽核(`/improve-animations`):找出高頻記帳流程中缺少按壓回饋、
轉場起步停滯、以及不必要的空等。本文記錄已完成的三批改動與刻意的取捨。
尚未做的項目見最後一節。

**入口點:** 這是既有畫面的手感調整,不是新功能,沒有新的入口。受影響的畫面是
底部導覽列、記一筆(新增交易)頁、轉帳分頁、PIN 輸入畫面(App 鎖 / PIN 設定)、
標籤選擇、帳本列表。

## 批次 1:記帳頁轉場與選擇器空等

### `lib/widgets/ui/slide_up_page_route.dart`
- 進場 300ms → 280ms(`BeeMotion.medium`),離場 → 210ms(`_exitDuration`)。
- 離場曲線改用 `BeeMotion.standard.flipped`。原本是 easeOutCubic 直接反向播放,
  前段位移極小(約 90ms 才動 3%),儲存後頁面「卡一下才走」。flipped 對時間是
  ease-out,按下就立即起步。
- 拖曳放開後的收尾 / 彈回,時長分別用 `_exitDuration` / `_enterDuration` 依剩餘
  距離等比縮短。拖曳期間仍是線性跟手,未改動。
- 測試 `test/widgets/slide_up_page_route_test.dart` 跟著更新:期望值直接用
  `BeeMotion.standard` 曲線計算,不再寫死 300ms 與 12.5%。

### `lib/widgets/biz/transaction_entry_form.dart`、`lib/widgets/transaction/transfer_form.dart`
- 開日期 / 時間選擇器前原本無條件 `await 100ms`(等鍵盤收起)。新增
  `_unfocusBeforePicker()`:先讀 `MediaQuery.viewInsetsOf(context).bottom`,
  再 `unfocus()`,**只在系統鍵盤實際開啟時**才等 100ms。
- 注意順序:必須在 `unfocus()` 之前讀 viewInsets。App 內建的計算機鍵盤不算系統
  鍵盤,不需等待。兩個檔案各自一份私有實作(未抽共用,避免為 5 行程式跨檔耦合)。

## 批次 2:BeePressable 擴充與高頻按壓回饋

### `lib/widgets/ui/bee_pressable.dart`
- 按下態改用 `Listener.onPointerDown` 立即觸發。Flutter 的 `onTapDown` 要等約
  100ms(`kPressTimeout`)才回呼,快速點擊時 down/up 同幀,縮放會被瞬間取消而完全
  看不到。還原交給 `onTapUp` / `onTapCancel`(拖曳、長按贏得手勢競技場時會
  cancel,自動復原)。
- 按下 100ms ease-out(`standard`),放開 150ms 彈回(`spring`),兩段時長都經
  `BeeMotion.durationOf`,遵守「減少動畫」。
- 新增參數:`key`、`onLongPress` / `onLongPressStart` / `onLongPressMoveUpdate` /
  `onLongPressEnd`、`pressedScale`(預設 0.96)、`behavior`。
- `product_promo_card.dart` 的 3 個既有呼叫點因此從 150ms 彈簧按下變成 100ms
  ease-out 按下,屬預期。

### 套用位置與縮放值
| 位置 | 檔案 | scale |
| --- | --- | --- |
| 底部導覽各 tab、頭像 tab | `lib/app.dart` | 0.92 |
| 中間記帳鍵(保留 `centerButtonKey` 與扇形選單三個長按回呼) | `lib/app.dart` | 0.92 |
| 記帳表單金額區(保留 `amountDisplayTap` key、`translucent`) | `transaction_entry_form.dart` | 0.98 |
| 推薦 chips | `transaction_entry_form.dart` | 0.96 |
| 分類摘要列 | `transaction_entry_form.dart` | 0.98 |

### 刻意不做 / 已接受的取捨
- 鍵盤上方行內手續費 / 折扣小文字格(`_buildKeypadAmountCell`)維持 `GestureDetector`,
  目標太小、縮放反而干擾。
- 金額區 0.98:點到內層幣別 / 匯率按鈕、按住超過約 100ms 時外層會跟著縮一下。
  已在真機驗證可接受。
- 推薦 chips 在橫向捲動時,手指一按下就先縮、開始捲動才還原。

## 批次 3:PIN 鍵盤、標籤 chip、帳本卡

### `lib/widgets/ui/bee_pressable.dart`
- 新增選用 `onPressedChanged(bool)`,供外層同步做底色等額外回饋。舊呼叫點不受影響。

### `lib/widgets/biz/pin_entry_pad.dart`
- 可點的鍵改為 `_PinKey`:縮放 0.92,按下時底色以
  `Color.alphaBlend(textPrimary 8%, surfaceSecondary)` 加深,100ms 過渡(同樣
  走 `durationOf`)。用 alphaBlend 是為了深淺色主題都適用,不寫死顏色。
- 觸覺回饋 `HapticFeedback.lightImpact()` 維持在放開(`onTap`)時、先於回呼觸發,
  時機與改動前相同。未改成按下觸發。
- 沒開生物辨識的佔位鍵(`onTap == null`)維持不可點、不縮放。

### `lib/widgets/biz/tag_chip.dart`
- 僅 `onTap != null` 時改用 `BeePressable`(0.96)。純顯示的 chip 不變,避免
  出現假的可點感。`TagChipList` 的「+N」按鈕不在範圍,未動。
- 另:跑 `dart format` 時該檔 `TagChipList` 幾行長三元被折行,純格式變動。

### `lib/widgets/biz/ledger_card.dart`
- `onTap != null` 時用 `BeePressable`(0.98)並保留 `onLongPress`;`onTap` 為
  null 時退回 `GestureDetector(onLongPress)`。長按贏得手勢時會 cancel,縮放還原。
- 右下「⋯」按鈕在卡片內,按它時卡片會先縮到 0.98 再還原(同金額區的取捨)。
- 整段因多包一層而縮排改變,diff 看起來比實際邏輯改動大。

## 批次 4:彈窗與 Bottom Sheet 封裝(#6)

### 新增 `lib/widgets/ui/bee_overlays.dart`(已從 `ui.dart` 匯出)
- 背景:Flutter 內建 sheet 是 250/200ms + `legacyDecelerate`,dialog 是 150ms 純淡入,
  兩者都不看「減少動畫」,且離場的減速 `reverseCurve` 會有起步偏慢的問題。時長本身
  與 280/210 差距很小,主要收益是減少動畫、離場起步、單一控制點。
- `showBeeBottomSheet`:進場 `BeeMotion.medium`(280ms)+ `standard`,離場 210ms +
  `standard.flipped`,無 overshoot(貼底 sheet 不能用 spring,會露出接縫)。
  `animationStyle` 可逐欄位覆寫;時長經 `BeeMotion.durationOf`。
- `showBeeDialog`:淡入 + 縮放 0.96→1,進場 180ms / 離場 120ms。內建 `showDialog`
  的 `AnimationStyle` 只有單一 `duration`(離場同長),無法分開設定,所以改用
  `DialogRoute` 子類覆寫 `reverseTransitionDuration` 與 `buildTransitions`;主題捕獲、
  SafeArea 等包裝仍由 `DialogRoute` 負責。

### 遷移的 8 個呼叫點
`account_picker.dart`(`AccountPicker.show`)、`category_selector_dialog.dart`
(`showCategorySelector`,共用函式,7 個檔案的呼叫端一併套用,含低頻頁,屬刻意)、
`transaction_entry_form.dart` 的拆分選單 ×2、附件選擇、匯率確認、選項開關,
以及 `transfer_form.dart` 的附件選擇。

### 刻意不做
- `account_card_picker`、`project_picker`、`wheel_picker` / `wheel_time_picker` 等其他
  Picker 本次不動;`AppDialog`(114 處引用,多為低頻確認框)不動。
- 往下拖曳關閉 sheet 時,內建把拖動量對應到動畫控制值,換離場曲線後的跟手感需真機確認。

測試:`test/widgets/bee_overlays_test.dart`(無 overshoot、進離場時長、flipped 起步、
dialog 縮放、減少動畫、`animationStyle` 覆寫、點遮罩關閉)。

## 測試
- 新增 `test/widgets/bee_pressable_test.dart`:按下立即縮放且 `onTap` 照常、拖走後
  還原不觸發 `onTap`、長按三回呼透傳、`onPressedChanged` 依序回呼。
- 新增 `test/widgets/pin_entry_pad_test.dart`:點擊觸發 `onNumberTap` 與 lightImpact、
  按下 0.92 並還原、佔位鍵不可按壓。
- 已知與本次無關的失敗:`calendar_month_jump_test`(「滾輪選到 2000-01」),
  還原所有改動後同樣失敗。

## 尚未處理(稽核清單剩餘)
- #8 計算機鍵盤漣漪在真機上的確認;#9 `category_rank_row` 取消 splash。
- 缺漏的動效:儲存後新列進場動畫、選取模式 checkbox 的 `AnimatedSwitcher`。
