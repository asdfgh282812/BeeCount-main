# 移除資產管理頁的「蜜蜂家當 BeeAssets」入口

## 變更內容

- [lib/pages/account/accounts_page.dart](../../lib/pages/account/accounts_page.dart) — 移除 `PrimaryHeader.actions` 中夾在「新增帳戶」與「設定」之間的 `_BeeAssetsHeaderEntry` 圖示按鈕（點擊會跳出介紹彈窗，導向 App Store / 官網 / 內測申請）。連同該 private widget class 定義一起刪除。
- 移除了因此不再使用的 import：`services/marketing/product_promos.dart`、`widgets/biz/product_promo_card.dart`。

## 未變動的部分（刻意）

- `lib/services/marketing/product_promos.dart` 中的 `beeAssetsPromo()` 函式，以及對應的 l10n 字串（`aboutBeeAssets` 等）**未刪除** — 這些是純資料/函式，其他推廣入口（如 `beeDnsPromo`）仍共用同一套 `ProductPromoLauncher` / `buildPromoTexts` 機制，未牽動共用檔案。
- `ProductPromoLauncher`、`ProductPromoCard` 等共用元件不變。

## 原因

使用者反饋資產管理頁不需要這個推廣入口。
