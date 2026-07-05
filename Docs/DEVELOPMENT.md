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

## 提交节奏

每个阶段完成后执行验证命令。当前目标已授权自动提交，因此验证结果明确后直接提交对应阶段代码。
