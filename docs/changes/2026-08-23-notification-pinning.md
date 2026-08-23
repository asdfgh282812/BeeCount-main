# 欠款到期提醒通知釘選 + 一鍵跳轉還款頁

日期:2026-08-23
背景:使用者反饋欠款到期提醒的通知會被之後新建立的其他通知洗到列表下
方,看不到、也不會去處理還款,希望這類通知能釘選在最上面,並支援點擊直
接跳轉到還款頁。跟 `2026-08-23-debt-category-and-origin-link.md` 是同一
天的兩個獨立需求,分開記錄。

## 調查發現:「一直出現」不是重複建立,是被洗到看不見

在動手之前先查證了使用者「欠款通知一直出現」的說法。BeeCount Cloud
(`/Users/andy/BeeCount-Cloud`)`src/services/debt_reminders.py` 的去重邏
輯(`_already_reminded_debt_ids`)本來就是查「這筆債務有沒有任何一筆
`category='reminder'` 且 `payload.debtId` 相符的通知」來去重,不管
已讀/未讀,一旦已經有過一條就不會再建立第二條——所以並不存在「每 15 分
鐘重複產生新通知」的 bug。使用者感覺到的「一直出現」,根本原因是同一則
通知被之後新建立的其他(不相關)通知擠到列表下方,而 App 端目前完全沒有
辨識這則通知並跳轉的邏輯,點了也沒反應,兩個因素疊加起來給人「陰魂不散
又沒用」的印象。所以這次的修正範圍是:①讓通知留在最上面 ②讓點擊真的能
跳轉,而不是去消除本來就不存在的重複。

## Server 端(`/Users/andy/BeeCount-Cloud`)

- Alembic migration `0048_notification_pinned.py`:`notifications` 表加
  `pinned BOOLEAN NOT NULL DEFAULT false`——用 `sa.Boolean()` +
  `server_default=sa.false()`(不是 `sa.text("0")`,這個 repo 同時跑
  SQLite 跟 Postgres,`sa.false()`/`sa.true()` 才是兩邊都吃的可移植寫
  法,對照 `src/models.py` 既有其他 boolean 欄位的宣告方式)。這是這個
  repo 第一個「非 null + server_default」的 column add(既有的
  0025/0026/0045/0046 都是 nullable add),但因為有 `server_default`,
  既有資料列會在 ALTER 當下自動回填成 `false`,不需要額外的 backfill
  UPDATE。
- `src/models.py`:`Notification` 加 `pinned: Mapped[bool]`。
- `src/routers/notifications.py`:`NotificationItem`/`_to_item` 帶出這
  欄;`list_notifications` 的排序改成
  `order_by(Notification.pinned.desc(), Notification.created_at.desc(),
  Notification.id.desc())`——釘選的永遠排最前面,同樣是釘選的之間再按時
  間新到舊排。
- `src/services/notifications.py::create_notification`:新增
  `pinned: bool = False` 參數。
- `src/services/debt_reminders.py`:欠款到期提醒的 `create_notification`
  呼叫加 `pinned=True`。**沒有動**其他建立 `category="reminder"` 通知的
  地方(`installment_plans.py`、`recurring_materializer.py`)——只有欠款
  提醒需要釘選,其他 reminder 來源維持原樣,避免一次性把所有 reminder
  都變成釘選、擠爆列表最上面那一小塊空間。
- 已知的次要 UX 缺口(這次刻意不處理):目前沒有機制在債務結清後把舊的
  提醒通知自動標記失效或取消釘選——如果使用者已經還完錢,那則提醒通知會
  一直釘在最上面直到手動標已讀。等之後有使用者實際反饋這個情況再處理,
  這次先解決「看不到」的主要問題。

## App 端

`lib/pages/notifications/notification_center_page.dart`:

- `NotificationJumpTarget` 新增 `debt`(`DebtWithStatus?`)欄位 +
  `NotificationJumpTarget.debt(...)` factory。
- `resolveNotificationJumpTarget`:初始的 null-guard 加上
  `payload['debtId']`;解析順序固定為 accountId → recurringRuleId →
  debtId(三者理論上不會同時出現在同一則通知的 payload 裡,但解析順序要
  固定,照抄 web 端 `NotificationBell.tsx handleJumpToDetail` 的既有優先
  序邏輯,只是多加一層)。debtId 分支:`repo.getDebtBySyncId(debtId)` →
  `repo.getDebtWithStatus(debt.id)`,拿到 `DebtWithStatus`(順便帶出
  `DebtRepaymentPage` 需要的 `remainingAmount`,不用另外算)。
- `_handleTap`:新增 `target.debt != null` 分支,`Navigator.push` 到
  `DebtRepaymentPage(debt: ..., suggestedAmount: ...)`。

**沒有做的事**(範圍決策):`packages/flutter_cloud_sync` 裡的
`BeeCountCloudNotificationItem` 目前沒有 `pinned` 欄位——這不影響排序本
身(排序是 server 端決定好順序後回傳,App 只是照給的順序渲染),只有
「App 端要不要顯示一個釘選圖示」這個額外的視覺提示才需要這個欄位。這次
沒有加,純粹排序生效已經解決使用者反饋的核心問題。

## 相容性

`pinned` 欄位對舊版 App 完全透明——App 從來不需要讀寫這個欄位,排序邏輯
全部發生在 server 端回傳列表之前,舊版 App 拿到的就是已經排好序的列表。
新版 App 的 debtId 跳轉分支對舊版 server(還沒回傳釘選排序、但已經有
`debtId` payload)一樣能正常運作,兩者互相獨立。

## 測試

`test/data/notification_jump_target_test.dart` 新增案例(跟
`2026-08-23-debt-category-and-origin-link.md` 共用 fixture 裡新增的
debt 資料列):
- `debtId` 可解析 → 回傳 debt target,附即時算出的 `remainingAmount`。
- `debtId` 找不到本機實體 → `notFound`。
- `recurringRuleId` 與 `debtId` 同時出現時,`recurringRuleId` 優先(驗證
  解析順序)。
- `ledgerId` 指向跟目前不同的帳本時,debt 分支一樣會先切帳本再回傳
  target。

Server 端 migration 的 SQL 語法已對照既有成功案例驗證(`ast.parse` +
在 repo 自帶的 `.venv` 裡 import 相關模組),`pytest tests/test_debts.py
tests/test_notifications.py` 全數通過;沒有在任何真實/共用資料庫上實際
執行過 `alembic upgrade`,套用時機留給使用者自行決定。
