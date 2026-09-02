# SwipeSmart「一键记账」App 原生化（beecount://quick-add）

设计文档：[`docs/superpowers/specs/2026-09-02-swipesmart-quickadd-deeplink-design.md`](../superpowers/specs/2026-09-02-swipesmart-quickadd-deeplink-design.md)（本地 scratch，未纳入版本控制——具体背景/流程图/边界情况表见该文档）。

## 做了什么

手机上点 SwipeSmart「一键记账」时，若装了 BeeCount App，直接拉起 App 打开预填好的
新增交易表单；没装的话行为不变（fallback 回 BeeCount Cloud 网页版）。

### SwipeSmart（`/Users/andy/SwipeSmart`，独立 repo）

`src/CardStrategy.Api/wwwroot/index.html`：

- 新增 `buildBeecountQuickAddDeepLinkUrl(res)`：跟既有 `buildBeecountQuickAddUrl`
  组出相同语义的一组 query 参数（merchant/amount/category/cardId/bankName/
  cardName/reward/rate），只是换成 `beecount://quick-add?...`。
- `onQuickAddToBeecountClick` 改为接收 `(event, res)`（模板 anchor 的
  `@click.stop` 一并改传 `res`），新增手机 UA 侦测：手机才 `preventDefault`
  + 尝试 `window.location.href = deepLinkUrl`，用 `visibilitychange`/
  `pagehide` 侦测 App 是否接住，~1200ms 逾时仍可见则 `window.open` 回原本的
  https fallback（复用 anchor 自身 `href` 算出来的网址，不用重复拼一次）。
  桌面浏览器完全不变，维持 `<a href>` 默认行为。

### BeeCount App（本 repo）

- [`lib/services/platform/app_link_service.dart`](../../lib/services/platform/app_link_service.dart)：
  - `AppLinkAction` 新增 `quickAdd`；`parseAction` 新增 `quick-add` host。
  - `AddTransactionParams.amount` 从 `required double` 改成可空 `double?`——
    quick-add 的金额解析失败/缺失时要留空不挡流程，与 `add`/`newTransaction`
    共用同一个字段（原本 `newTransaction` 传 `amount: 0` 当占位符不受影响；
    `_handleAddTransaction` 内部两处 `.amount` 用法补上 `!`，因为那条路径
    构造前已经校验过非空正数）。新增 `merchant`/`accountId` 两个字段。
  - 新增 `_handleQuickAdd`：反查信用卡账户（`swipesmartCardId` 精确比对，
    仅 `credit_card` 类型 + 未隐藏）、反查分类（`_findCategoryIdFuzzy`，仅
    支出分类、名称正规化后互相包含模糊比对、刚好一笔命中才采用）、账户没
    对到时组装提示 note，然后通过 `onNavigate` 打开表单——**不**写入交易。
- [`lib/providers/ui_state_providers.dart`](../../lib/providers/ui_state_providers.dart)：
  新增 `pendingQuickAddParamsProvider`（`StateProvider<AddTransactionParams?>`），
  直接存整个参数对象而不是拆多个独立 provider（quick-add 字段较多，拆分容
  易漏字段）。
- [`lib/main.dart`](../../lib/main.dart)：`onNavigate` 回调新增 quickAdd 分支，
  写入上面的 provider。
- [`lib/app.dart`](../../lib/app.dart)：冷启动「重建可恢复」深链机制
  （`_persistPendingDeepLink`/`_executeDrain`/`_openDeepLink`）扩展支持
  quickAdd——持久化 JSON 里嵌套一个 `quickAdd` 子对象装
  amount/merchant/categoryId/accountId/note，`_executeDrain` 解析回来后
  统一传给 `_openDeepLink`，新增 `case AppLinkAction.quickAdd` 打开
  `TransactionEditorPage`（这几个字段编辑页本来就支持，不用改编辑页）。

## 未做 / 有意排除

- 不改 BeeCount Cloud 网页版（fallback 目的地不变）。
- 不做 Android App Links / iOS Universal Links（理由沿用
  `2026-08-30-swipesmart-integration-design.md` §5.2 第 3 点，设计文档 §4
  重述）。
- 不反向比对 App 既有的信用卡回馈规则（`card_reward_rule`）——两边是不同
  数据库，贸然猜配对容易配错，降级成 note 文字。
- Schema/同步：无变更，`accounts.swipesmartCardId` 是既有字段（v47），
  quick-add 纯本地解析，不涉及 `ChangeTracker`/`entity_serializer`。

## 测试

- 新增 [`test/services/app_link_service_quick_add_test.dart`](../../test/services/app_link_service_quick_add_test.dart)：
  账户反查（精确命中/hidden 不参与/非信用卡不参与/cardId 空字符串不查）、
  分类模糊比对（单一命中/零命中/多笔降级/大小写空白正规化/子分类）、note
  组装（账户对到不加/依序拼接子句/reward·rate 为 0 或非数字时子句不出现）、
  无 `currentLedger` 时 failure 且不 `onNavigate`、金额解析的宽容处理。
  用 `BeeDatabase.forTesting(NativeDatabase.memory())` + `repositoryProvider
  .overrideWithValue(...)`，不 mock repository 本身，跟仓库既有测试风格
  一致。
- 冷启动 JSON round-trip（`_persistPendingDeepLink` → `_executeDrain`）没有
  加自动化测试：这两个是 `_BeeAppState` 的私有方法，要测就得起一整棵
  `BeeApp` widget 树并驱动生命周期状态，投入产出比低；已用 `flutter
  analyze`/走读确认序列化字段跟解析字段一一对应。
- SwipeSmart 网页端按设计文档判断，手动测试（真机 iOS Safari + Android
  Chrome），未加自动化测试——`visibilitychange`/`pagehide` + scheme 拉起
  这类纯浏览器行为在现有测试框架下难以自动化模拟。
