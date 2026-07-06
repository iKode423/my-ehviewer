# 开发说明

## 环境

- Xcode 26.6
- Swift 6.3.3
- iOS Simulator 26.5
- 最低部署版本：iOS 17.0

## 常用命令

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## 本地签名配置

工程通过 `Config/Signing.xcconfig` 读取签名 Team ID。首次在本机运行前，复制 `Config/Local.xcconfig.example` 为 `Config/Local.xcconfig`，并把 `LOCAL_DEVELOPMENT_TEAM` 设置为自己的 Apple Developer Team ID。

`Config/Local.xcconfig` 已加入 `.gitignore`，只保留在本机，不提交真实 Team ID。

## 提交节奏

每个阶段完成后执行验证命令。当前目标已授权自动提交，因此验证结果明确后直接提交对应阶段代码。

## 敏感数据

- 不提交真实站点 HTML、图片、标题样本、用户凭据或 Cookie。
- 站点 Cookie 仅通过 App 设置页写入本机 Keychain。
