# AI 圖片記帳支援「從剪貼簿貼上」

## 背景

AI 圖片記帳（拍照/截圖識別帳單）過去只能透過系統相簿選圖。使用者在其他 App
截圖或複製一張帳單圖片後，仍需先存到相簿才能拿來記帳，多一道手續。

## 變更內容

- [lib/utils/image_billing_helper.dart](../../lib/utils/image_billing_helper.dart)：
  `pickImageForBilling` 呼叫時先用 `super_clipboard` 探測系統剪貼簿是否持有
  圖片（`Formats.png/jpeg/webp/heic/heif`，僅探測不讀取）。
  - 有圖片：彈出 bottom sheet 讓使用者二選一——「從剪貼簿貼上」/「從相簿選擇」
    （沿用 `attachment_picker.dart` 的 `showModalBottomSheet` + `ListTile` 樣式）。
  - 沒有圖片：行為不變，直接開相簿。
  - 選「從剪貼簿」時，讀出的 bytes 會寫入暫存檔，副檔名依實際格式而定
    （`.png`/`.jpg`/`.webp`/`.heic`/`.heif`），因為
    `lib/ai/providers/ai_provider_factory.dart` 的 `_visionGemini` 是用副檔名
    猜 MIME type，副檔名對不上實際內容會導致 Gemini 視覺辨識失敗。
  - `_processImageBilling` 新增可選的 `pickedImage` 參數，跳過
    `ImagePicker().pickImage(...)` 直接沿用既有的 loading/vision 兜底/
    `AiBookkeeper.fromImage` 流程；剪貼簿來源沿用 `TagSeedService.billingTypeImage`
    標籤（語意上仍是「圖片記帳」，只是來源不同），沒有新增獨立的 billing type。
  - 相機拍照（`openCameraForBilling`）流程不受影響。

- [pubspec.yaml](../../pubspec.yaml)：新增 `super_clipboard: ^0.9.1` 依賴，
  用來跨平台（含 Android/iOS）讀取剪貼簿圖片。

- [android/app/src/main/AndroidManifest.xml](../../android/app/src/main/AndroidManifest.xml)：
  依 `super_clipboard` 官方文件要求，新增
  `com.superlist.super_native_extensions.DataProvider` 的 `<provider>` 宣告
  （authorities 用 `${applicationId}.SuperClipboardDataProvider`），要求的
  minSdk 23 本專案已滿足（`record_android` 已要求）。

- [lib/l10n/app_en.arb](../../lib/l10n/app_en.arb) /
  [lib/l10n/app_zh_TW.arb](../../lib/l10n/app_zh_TW.arb)：新增
  `imageBillingPasteFromClipboard` 一個 key；「從相簿選擇」沿用既有
  `attachmentChooseFromGallery`，沒有重複造字串。

## 刻意不做的事

- 沒有新增獨立的 `billingTypeClipboard` 標籤類型——剪貼簿只是圖片的另一個
  來源，額外的標籤/種子資料/圖示映射對這個小功能是不必要的複雜度。
- 沒有處理 gif/bmp/tiff 等剪貼簿圖片格式——`_visionGemini` 對這些格式會
  誤判成 `image/jpeg`，且剪貼簿圖片實務上幾乎都是 PNG/JPEG/(iOS) HEIC，
  故只支援這幾種有明確 MIME 映射的格式；不支援的格式會被當作「剪貼簿沒有
  圖片」處理，直接落回開相簿的既有行為。
- 只更新了 `app_en.arb`/`app_zh_TW.arb`（依專案既定 l10n 政策，`app_zh.arb`/
  `app_ko.arb` 不再維護）。
