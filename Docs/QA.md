# 验证记录

## 2026-07-06

### 自动化测试

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。覆盖搜索解析与分页、首页/热门/关注/收藏来源 URL、搜索筛选重置、保留筛选参数的搜索重试、初始关键词搜索、图库详情、标签继续搜索、站点链接文案、带缩略图的阅读入口、缩略图分页、阅读器翻页、缩略图目录与页码输入跳转、阅读器已知页码范围、阅读器图片重试 token、阅读器缩放偏好、本地书架持久化和继续阅读文案、最近搜索、站点 Cookie 存储和中文文案。

### 外观与搜索滚动回归

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
git diff --check
```

结果：通过。主题模式枚举、设置页外观入口、浅色强调色和搜索页单一纵向滚动结构可编译，筛选区展开后不再脱离滚动区域；未发现空白格式问题。

### 图片缓存与 GIF 回归

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
git diff --check
```

结果：通过。图片二进制请求、磁盘缓存、缓存统计/清理、GIF 数据渲染桥接和现有图片入口可编译；新增图片缓存存取清理测试通过，未发现空白格式问题。

### 阅读器交互回归

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
git diff --check
```

结果：通过。阅读器沉浸模式、点击分区翻页/显示控件、双指缩放、手动横竖屏切换、页码上限修正和现有阅读器流程可编译；新增当前页不低于已知上限测试通过，未发现空白格式问题。

### 构建验证

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

结果：通过。2026-07-06 复测普通 Debug 构建成功。

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
xcrun simctl io booted screenshot /tmp/my-ehviewer-20260706-smoke.png
```

结果：通过。应用成功安装并启动，首屏搜索页展示首页、热门、关注、收藏四个来源，中文搜索入口、筛选入口和底部 Tab 未见明显遮挡或错位。
