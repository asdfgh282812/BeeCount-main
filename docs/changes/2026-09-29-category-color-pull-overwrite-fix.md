# 修正：分类颜色被同步 pull 冲成白色/中性灰

## 问题

App 端「cute 图标」主题下,一级分类图标下方的手绘颜色底线（`CategoryColorUnderline`,
`lib/widgets/cute_icons/pencil_underline_painter.dart`）在实际使用中全部退化成中性灰
兜底色，肉眼看起来像「白色」，而 BeeCount Cloud 网页端同一批分类仍然正常带色。

## 根因

`lib/cloud/sync/sync_engine_apply.dart` 的 `_applyCategoryChange`（pull 应用路径）在
更新/插入本地 `Categories` 行时，无条件用 `payload['color'] as String?` 写入
`color` 列：

```dart
color: d.Value(payload['color'] as String?),
```

`Categories.color`（v55，见 `lib/data/db.dart:169-171`）是 App 单方面加的字段，
BeeCount Cloud 服务端还没把它接进自己的 projection / wire contract（见
`docs/CLOUD_SYNC_INTEGRATION.md` 与 CLAUDE.md 里「Category color: Cloud deferred」
的记录）。也就是说 server 回传的分类 payload 里通常**没有** `color` 这个 key，
`payload['color']` 因此恒为 `null`。

`entity_serializer.dart` 的 `serializeCategory` 推送时也是「本地有值才带这个
key」（`if (category.color != null) 'color': category.color`），从不显式推
`'color': null`。所以"没有这个 key"从来不代表使用者清空了颜色——但旧代码把
"没这个 key"和"被清空"等同处理，每次 pull（包括自己 push 之后的回声 pull、
每次开 app 的例行同步）都会把本机刚指派好的颜色（新建一级分类时从
`kCategoryColorPalette` 循环取色，或 v55 迁移时的回填）冲成 `null`，UI 端
`CategoryUtils.parseColor(category?.color) ?? BeeTokens.iconCategory(context)`
只能落到中性灰兜底色。

## 修正

`_applyCategoryChange` 改为区分「payload 没带 `color` key」与「payload 显式带
`color: null`」：

```dart
final resolvedColor = payload.containsKey('color')
    ? payload['color'] as String?
    : existing?.color;
```

没带 key 时保留既有本地值，不再用 `null` 覆盖。等 Cloud 端把 `color` 真正接进
projection 之后，清空颜色需要 server 显式发送 `'color': null`（届时会走
`resolvedColor = null` 分支，行为仍然正确）。

## 影响范围 / 不在本次修改范围内

- 只改了 App 侧的 pull-apply 防御逻辑，没有改 Cloud 端。颜色**跨设备同步**仍然
  不可靠（这是既有的已知限制，见 [Category color: Cloud deferred] 记忆），本次
  只解决「同一台设备上颜色会被自己的例行同步冲掉」这个更严重的问题。
- 网页端的颜色点不经过这个字段（Cloud 后端另有自己的显示逻辑），所以之前才会
  出现「网页正常、App 变白」的不对称现象。
