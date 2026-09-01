# 關於頁面精簡

## 背景

發行版本改指向獨立分支/倉庫（`asdfgh282812/BeeCount-main`），原「關於」頁上與上游專案相關的推廣性內容（官方社群連結、贊助、相關產品導流、內嵌更新日誌/隱私政策頁）不再適用，予以移除，只保留使用者實際需要的兩個入口：回報問題、查看本機日誌。

## 變更內容（`lib/pages/settings/about_page.dart`）

- 社群圖示列：移除官方網站／Telegram／小紅書／抖音，只保留 GitHub，連結改為 `https://github.com/asdfgh282812/BeeCount-main`。
- 功能卡：移除「檢查更新」（連帶移除 `UpdateService`/`checkUpdateLoadingProvider`/`updateProgressProvider` 相關 UI 邏輯）與「支持開發」，只保留「問題回饋」與「日誌中心」。
- 「問題回饋」的行為由開啟 GitHub issues 頁面改為開啟 `mailto:andy91011000@gmail.com`。
- 移除「更多產品」推廣區塊（`_buildProductPromos`，蜜蜂家當/BeeDNS）。
- 移除底部「更新日誌 · 隱私政策」文字連結與備案號（連帶移除 `_footerLink`/`_hex` 兩個僅供該區塊使用的輔助方法）。
- 保留頁首圖示／App 名稱／版本號（純識別資訊，非功能入口）。

## 附帶修正

`_tryOpenUrl` 原本先用 `canLaunchUrl` 判斷再 `launchUrl`；`mailto:` 在 Android 上 `canLaunchUrl` 常誤報 `false`（package visibility 限制），會導致新加的信箱回饋入口實際點不開。改用專案裡 `lib/widgets/biz/product_promo_card.dart` 已驗證過的模式：不預先判斷，依序直接嘗試多種 `LaunchMode`。

## 出的範圍決定

- 未清掉 `app_*.arb` 裡對應的舊字串鍵（`aboutWebsite`/`aboutTelegram`/`aboutSupportDevelopment`/`aboutRelatedProducts`/`aboutChangelog`/`aboutPrivacyPolicy` 等）；它們目前無其他呼叫點但保留字串本身不影響建置，且部分頁面可能日後重新啟用相同文案。
- `HelpCenterPage`／`PrivacyPolicyPage` 頁面本身未刪除，僅移除本頁到它們的入口，因為這兩個頁面可能仍被其他設定頁引用。
