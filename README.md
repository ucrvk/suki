# Suki

Suki 是一个基于 Flutter 的女仆预约应用，提供预约、排班查询和社区内容，支持 Web、Android 和桌面端。

## 功能

- 浏览、搜索和收藏女仆，查看可预约状态并选择时段预约。
- 查看每日排班与个人预约，取消已有预约。
- 查看女仆介绍、评价、照片墙和留言板。
- 登录和管理个人账户；可在设置中启用排队页面。
- 支持浅色和深色主题，以及预约数据和图片清单的本地缓存。

## 开发与运行

需要安装 Flutter SDK 和相应平台的开发工具；项目要求 Dart SDK `^3.11.1`。在项目根目录执行：

```bash
flutter pub get
flutter run -d chrome
```

也可以使用 `flutter devices` 查看可用设备，再通过 `flutter run -d <设备ID>` 启动。构建 Web 版本或 Android ARM64 APK：

```bash
flutter build web --release
flutter build apk --release --target-platform android-arm64
```

运行静态检查和测试：

```bash
flutter analyze
flutter test
```

## 服务配置

应用使用 Supabase 处理账户、预约和社区数据，连接配置位于 `lib/services/supabase_service.dart`。图片清单、图片和排队相关接口使用自托管后端，默认地址配置在 `lib/services/backend_config.dart`；可在运行或构建时通过 `--dart-define` 覆盖：

```bash
flutter run -d chrome --dart-define=SYSBOOKING_BASE_URL=https://example.com/suki
```

更换后端环境时，还需要确保对应的 Supabase 数据表、RPC、权限策略和后端接口已配置。`lib/pages/` 存放页面，`lib/services/` 存放数据访问和缓存服务，`lib/widgets/` 存放复用组件。

## 已知问题

- Web 端图片在滚动或重绘后可能出现黑块。当前项目中，规避 Flutter 静态 AVIF 解码问题（[flutter/flutter#160600](https://github.com/flutter/flutter/issues/160600)）和图片重绘问题（[flutter/flutter#192347](https://github.com/flutter/flutter/issues/192347)，关联 [#192516](https://github.com/flutter/flutter/issues/192516)）的方案存在冲突：`HtmlImage` 可以显示静态 AVIF，但可能出现黑块；`HttpGet` 可规避黑块，却可能导致 Chrome 无法解码 AVIF。目前选择保留 `HtmlImage`，暂时无法同时解决两个问题，待上游修复后重新验证。
