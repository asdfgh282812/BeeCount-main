# App 版本號更新 + Server 端裝置版本補報

日期:2026-09-08

## 1. App 版本號 1.0.0 → 3.1.0

**改了什麼**:[pubspec.yaml](../../pubspec.yaml) 的 `version: 1.0.0+1` 改成
`version: 3.1.0+1`。iOS 的 `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`
在 Runner target 是吃 `$(FLUTTER_BUILD_NAME)`/`$(FLUTTER_BUILD_NUMBER)`
(`ios/Flutter/Generated.xcconfig`),不需要另外改 Xcode 專案設定,跑一次
`flutter build ios --config-only`(或任何 `flutter build`/`flutter run`)
就会重新产生。

**為什麼没写成 `3.1`**:Flutter 用 `pub_semver` 的 `Version.parse` 解析
pubspec 的 version 字串,要求嚴格 `x.y.z` 三段式;寫 `3.1+1` 會解析失敗、
印警告後整個 fallback 成 null(等同没设置版本)。所以用 `3.1.0+1`,
Xcode 显示 `3.1.0 (1)`。

## 2. Server 端补上「App 升级后 devices.app_version 会卡在旧版本」的缺口

**背景**:App 早就有把 `app_version`(`"<version>+<buildNumber>"`)当装置
metadata 送给 server 的机制——但只有 `/auth/login`、`/auth/register`、
`/auth/sso/callback`、`/2fa/verify` 这几个端点的 handler 会
upsert 到 `devices.app_version`(见 BeeCount-Cloud 的 `_upsert_device()`,
`src/routers/auth.py`)。App 冷启动时若 access token 还没过期,完全不打
任何 API;就算过期触发 `/auth/refresh`,那条路径的 handler 只更新
`last_seen_at`,不碰 `app_version`。使用者靠 refresh token 续 session 可能
几个月不会重新走登入流程——这段期间升级 app,server 数据库看到的版本
会一直停在上次登入时的旧版本。

**改了什麼(App 端,本仓库)**:
- [packages/flutter_cloud_sync/lib/src/providers/beecount_cloud_provider.dart](../../packages/flutter_cloud_sync/lib/src/providers/beecount_cloud_provider.dart)
  新增 `BeeCountCloudProvider.reportAppVersion({required appVersion})`
  (委托给 `BeeCountCloudStorageService.reportAppVersion`,跟既有的
  `listDevices`/`revokeDevice` 同一套 `_authedRequest` 写法),呼叫
  `POST /devices/{deviceId}/report-version`。
- [lib/providers/sync_providers.dart](../../lib/providers/sync_providers.dart)
  新增 `reportAppVersionIfChanged(BeeCountCloudProvider)`:用 `PackageInfo`
  取得目前跑的版本,跟本地 `SharedPreferences` 存的
  `last_reported_app_version` 比对,不一样才呼叫上面的方法补推,成功后把
  新值写回本地。在 `syncServiceProvider` 里 `engine.startListeningRealtime()`
  之后 fire-and-forget 呼叫一次(non-blocking,失败只 log warning,不重试)。

**为什么存本地而不是每次都读 server 现在的值再比对**:少一次网络往返;
网络失败时也不该被视为「已上报」而卡住重试循环——下次 SyncEngine 重建
(冷启动/切帐本等)会自然再比对一次。

**为什么用 SharedPreferences 而不是新增 Drift 表**:这只是单一个标记值,
没有关联式资料需求,跟仓库既有惯例一致(`lib/services/update/update_cache.dart`
存 `cached_apk_version` 也是同样做法)。

**Server 端改动(BeeCount-Cloud,独立 repo)**:新增
`POST /devices/{device_id}/report-version` 端点(`src/routers/devices.py`),
沿用既有的 `_DEVICE_SCOPE_DEP`(`SCOPE_APP_WRITE`/`SCOPE_OPS_WRITE`)+
`get_current_user` 鉴权,校验 `device_id` 属于目前登入的 user 之后直接
更新 `devices.app_version` + `last_seen_at`。不需要 schema migration
(`app_version` 栏位已存在)。测试见 `tests/test_device_report_version.py`。

**刻意不做的事**:没有把 `app_version` 加进 `/auth/refresh` 或
`/sync/pull`、`/sync/push`(这几个端点呼叫频率高很多,每次都多送一个
栏位/多一次 DB write 不划算);也没有做成周期性 heartbeat 端点——现有的
「启动时比对,变了才推」已经足够覆盖「升级后过一阵子才被 server 看到」
这个问题,不需要更高频的机制。
