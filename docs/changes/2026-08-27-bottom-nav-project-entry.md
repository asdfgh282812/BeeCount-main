# 底部導覽列改版：新增「專案」分頁 + 明細/記帳雙態中間按鈕

日期：2026-08-27

使用者反映記帳表單裡的專案入口不夠明顯（見 [project-feature-phase2-3.md](2026-08-27-project-feature-phase2-3.md)），並要求把「專案」納入底部主導覽，順便調整既有排版。這次改的是 `lib/app.dart` 的主殼底部導覽列，跟專案功能本身的資料/UI（Phase 1-3）是分開但相關的一次改動。

## 做了什麼

底部導覽列從「明細／洞察／〔記帳〕／資產／我的」5 個位置（明細、洞察、資產是三個分頁，中間是純動作按鈕，我的是頭像分頁）改成：

**帳戶／專案／〔明細⇄記帳〕／洞察／我的**

- 「帳戶」（原「資產」`AccountsPage`）搬到最左邊（index 0）。
- 「專案」（`ProjectOverviewPage`，新增 `asTab` 參數同 `AccountsPage.asTab` 隱藏返回箭頭）新增在 index 1。
- 中間按鈕不再是純動作按鈕，而是「明細」（`HomePage`，原本的 index 0）分頁跟「記帳」動作的雙態合體：
  - 目前**不在**明細分頁時：顯示「明細」圖示/文字，點擊切過去（`_handleTabTap`，含雙擊捲動置頂等原有語意）。
  - 目前**在**明細分頁時：顯示「記帳」圖示/文字，點擊開新增交易頁（維持原本行為），長按彈出相機/相簿/語音快速記帳選單（也維持原本行為，只是現在只在這個狀態下才會觸發，避免「明細」態被誤長按彈出跟情境不符的選單）。
- 「洞察」搬到 index 3，「我的」搬到 index 4。
- `_pages`（`IndexedStack` 的分頁陣列）順序跟著改成 `[AccountsPage, ProjectOverviewPage, HomePage, AnalyticsPage, MinePage]`，`_homeTabIndex = 2` 集中定義,避免多處寫死數字。

## 連帶更新的索引假設

底部導覽 index 的語意變了，以下原本寫死數字的地方一併更新：

- `lib/app.dart` 桌面 widget deep link（`page=detail` 落地頁）：`bottomTabIndexProvider` 設成 0 → 改設成 `_homeTabIndex`（2）。
- `lib/providers/ui_state_providers.dart`：`bottomTabIndexProvider` 預設值 0 → 2，維持「打開 app 先看到明細」的既有體驗（不然預設會落在新的「帳戶」分頁）。
- `lib/pages/auth/login_page.dart`：登入成功後切到「我的」分頁的兩處寫死 `state = 3` → `state = 4`。

## 刻意簡化

- 中間按鈕「明細」態時不會用 `primaryColor` 高亮（跟原本的記帳動作按鈕一樣，不參與一般分頁的「目前選中」視覺樣式）——這顆按鈕的語意本來就是雙態切換，不是單純的分頁選中指示器。
- 「專案」分頁沿用 `ProjectOverviewPage` 既有的內容（總預算長條 + 專案卡片列表），沒有為了當作根分頁而另外簡化或加首頁化的內容。

## 驗證

- `flutter analyze`：全專案 0 error。
- `flutter test`：全專案測試綠燈（858 個測試，見對應 commit）。
- **未做**：實機/模擬器上手動確認新排版的視覺（圖示間距、中間按鈕雙態切換的動畫/文字是否跑版）、長按快速記帳選單只在「記帳」態出現、雙擊明細置頂手勢仍正常。建議正式發版前補一次手動驗證。
