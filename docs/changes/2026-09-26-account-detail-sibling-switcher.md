# 帳戶明細頁:標題置中 + 同群組子帳戶下拉切換

比照 MOZE 帳戶明細頁的做法。

## 改了什麼

- **`lib/widgets/ui/primary_header.dart`**
  - 新增 `centerTitle`(預設 false,其它頁面不受影響)和 `onTitleTap`。
  - 置中模式下,標題/副標題疊在按鈕列上方,左右各留 100 的空白,避開返回鍵和 actions。Padding 的留白區域不吃點擊,所以下層的按鈕照常可以按。
  - 原本的標題欄位抽成 `titleColumn`,置中和靠左兩種模式共用。
- **`lib/pages/account/account_detail_page.dart`**
  - 標題一律置中。
  - 帳戶掛在主帳戶(群組)底下、而且同群組有 2 個以上子帳戶時,標題旁顯示 ▼。只有 1 個子帳戶時清單沒有東西可以切換,所以不顯示。
  - 點標題列會展開面板,列出同群組的全部子帳戶(依 `sortOrder` 排序;隱藏的子帳戶不列,但目前這個帳戶即使是隱藏的也會列),目前帳戶打勾。群組本身不列在裡面。
  - 選另一個子帳戶時,用無動畫的 `pushReplacement` 換成那個帳戶的明細頁,返回鍵仍然回到原本的上一頁,不會一路疊明細頁。

## 刻意不用 PopupMenuButton / showMenu

下拉面板是頁面本身 `Stack` 裡的一個 widget,不是 popup route。選項用一般的 `InkWell.onTap` 觸發切換。

原因:在 macOS 版上,從 popup route 的 `onSelected` 直接 push 或開 dialog,會撞到 framework 的 Element/Navigator 斷言而整個當掉。延後一個 frame 也沒用,只是換成另一種斷言。背景見 `docs/changes/2026-08-28-balance-adjustment.md`,這頁「調整總額」改成獨立 IconButton 也是同一個原因。

## 入口

資產頁 → 點任一個有主帳戶的子帳戶(或展開群組後點子帳戶)→ 明細頁標題旁的 ▼。

## 測試

`test/widgets/account_detail_sibling_switcher_test.dart`:

- 子帳戶標題有箭頭,點開後清單只有同群組子帳戶,選另一個會切換頁面。
- 非子帳戶沒有箭頭。
