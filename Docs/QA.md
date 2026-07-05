# 验证记录

## 2026-07-06

### 自动化测试

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。覆盖搜索解析与分页、首页/热门/关注/收藏来源 URL、搜索筛选重置、保留筛选参数的搜索重试、初始关键词搜索、图库详情、标签继续搜索、带缩略图的阅读入口、缩略图分页、阅读器翻页、缩略图目录与页码输入跳转、阅读器已知页码范围、阅读器图片重试 token、阅读器缩放偏好、本地书架持久化、最近搜索、站点 Cookie 存储和中文文案。

### 构建验证

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

结果：通过。

### 模拟器冒烟

```sh
xcrun simctl bootstatus 'iPhone 17 Pro' -b
xcrun simctl install booted /Users/ikode/Library/Developer/Xcode/DerivedData/MyEHViewer-asduoirgkvnkeocmxnxbvjnwfqad/Build/Products/Debug-iphonesimulator/MyEHViewer.app
xcrun simctl launch booted com.ikode.MyEHViewer
xcrun simctl io booted screenshot /tmp/my-ehviewer-smoke.png
```

结果：应用成功启动，首屏搜索页、筛选入口和底部 Tab 正常显示。

### 最终模拟器冒烟

```sh
xcrun simctl bootstatus 'iPhone 17 Pro' -b
xcrun simctl install booted /Users/ikode/Library/Developer/Xcode/DerivedData/MyEHViewer-asduoirgkvnkeocmxnxbvjnwfqad/Build/Products/Debug-iphonesimulator/MyEHViewer.app
xcrun simctl launch booted com.ikode.MyEHViewer
xcrun simctl io booted screenshot /tmp/my-ehviewer-final-smoke.png
```

结果：通过。应用成功安装并启动，首屏搜索页展示首页、热门、关注、收藏四个来源，中文搜索入口、筛选入口和底部 Tab 未见明显遮挡或错位。
