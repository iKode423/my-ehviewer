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

### 阅读 Tab 会话回归

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
git diff --check
```

结果：通过。根 Tab selection、当前阅读会话、详情页阅读入口和书架继续阅读入口可编译；新增打开阅读会话会切换到阅读 Tab 的测试通过，未发现空白格式问题。

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

### 本轮最终模拟器冒烟

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcrun simctl bootstatus 'iPhone 17 Pro' -b
xcrun simctl install booted /Users/ikode/Library/Developer/Xcode/DerivedData/MyEHViewer-asduoirgkvnkeocmxnxbvjnwfqad/Build/Products/Debug-iphonesimulator/MyEHViewer.app
xcrun simctl launch booted com.ikode.MyEHViewer
xcrun simctl io booted screenshot /tmp/my-ehviewer-final-20260706.png
```

结果：通过。Debug 构建成功，应用成功安装并启动，启动 PID 为 `16278`；截图确认搜索首屏、筛选入口、底部 Tab 和 `#00a8ff` 强调色显示正常。

### 网站收藏与图库预览回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。覆盖阅读器跳页时自动补齐图库页面目录、书架网站收藏初始来源、详情页网站收藏弹窗表单解析与 POST 字段、搜索/图库 CSS 背景缩略图、GIF 静态预览、本地收藏/网站收藏中文文案和既有搜索、图库、阅读、缓存、Cookie、本地书架回归。真实网站收藏端到端同步未写入或使用真实 Cookie；需要完整登录 Cookie header 才能做线上验证。

### 图库下载、缓存管理与线上收藏回归

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。覆盖图库页面 CSS sprite 预览裁剪、图库总页数解析、阅读页总页数回传、离线时通过缓存索引恢复已缓存阅读页、缓存内容去重、按图库缓存进度统计、单图库缓存删除、阅读进度直接创建历史记录、线上收藏全部分类 URL、线上收藏取消提交字段，以及既有搜索、图库、阅读、Cookie、书架和中文文案回归。

### 缓存与线上收藏修复冒烟

```sh
xcrun simctl bootstatus 'iPhone 17 Pro' -b
xcrun simctl install booted /Users/ikode/Library/Developer/Xcode/DerivedData/MyEHViewer-asduoirgkvnkeocmxnxbvjnwfqad/Build/Products/Debug-iphonesimulator/MyEHViewer.app
xcrun simctl launch booted com.ikode.MyEHViewer
xcrun simctl io booted screenshot /tmp/my-ehviewer-cache-favorites-20260706.png
```

结果：通过。应用成功安装并启动，启动 PID 为 `45971`；首屏搜索页在深色模式下显示正常，底部 Tab、搜索入口、筛选入口和 `#00a8ff` 强调色未见明显遮挡或错位。

### 缓存优先阅读与子页面导航回归

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。覆盖已缓存阅读页打开和下一页切换不再请求阅读页 HTML、缓存页 URL 可用于图库/目录预览、二级图库/缓存页面隐藏底部 Tab 的编译回归，以及既有搜索、图库、阅读、缓存、Cookie、书架和中文文案回归。

### 缓存优先修复冒烟

```sh
xcrun simctl bootstatus 'iPhone 17 Pro' -b
xcrun simctl install booted /Users/ikode/Library/Developer/Xcode/DerivedData/MyEHViewer-asduoirgkvnkeocmxnxbvjnwfqad/Build/Products/Debug-iphonesimulator/MyEHViewer.app
xcrun simctl launch booted com.ikode.MyEHViewer
xcrun simctl io booted screenshot /tmp/my-ehviewer-cache-first-20260706.png
```

结果：通过。应用成功安装并启动，启动 PID 为 `60886`；首屏搜索页在深色模式下显示正常，底部 Tab、搜索入口和筛选入口未见明显遮挡或错位。

### 阅读器路由与下载跳过回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。覆盖阅读器从底部 Tab 移出并以全屏路由打开、返回上一级关闭阅读器且保留原 Tab、缓存页通过已知图库目录继续打开未缓存下一页、解析 HTML 下一页指向自身时仍可按已知目录继续下一页、整本下载遇到单页图片失败后跳过并继续缓存后续页，以及既有搜索、图库、阅读、缓存、Cookie、书架和中文文案回归。

### 书架固定控件与缓存进度回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。覆盖搜索结果行撑满宽度以修正首页和线上收藏列表错位、线上收藏使用固定关键词搜索和上一页/下一页控件、图库下载进度按真实图库缓存记录校准、清空图库缓存后进度不再显示旧已下载数、非图库图片缓存可单独清理且保留已下载图库页，以及设置页新增文案和既有搜索、图库、阅读、缓存、Cookie、书架回归。

### 书架与缓存修复冒烟

```sh
xcrun simctl bootstatus 'iPhone 17 Pro' -b
xcrun simctl install booted /Users/ikode/Library/Developer/Xcode/DerivedData/MyEHViewer-asduoirgkvnkeocmxnxbvjnwfqad/Build/Products/Debug-iphonesimulator/MyEHViewer.app
xcrun simctl terminate booted com.ikode.MyEHViewer
xcrun simctl launch booted com.ikode.MyEHViewer
xcrun simctl io booted screenshot /tmp/my-ehviewer-library-cache-20260706-retry.png
```

结果：通过。应用成功安装并启动，启动 PID 为 `23416`；搜索首屏、筛选入口、底部 Tab 和深色模式下的强调色显示正常，未见明显遮挡或错位。

### 主题色与设置顺序回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。覆盖默认主题色 `#00A8FF`、主题色十六进制存取、设置页新增“主题颜色”文案、非图库图片缓存清理按钮前置图标、缓存策略区域移动到本地数据上方、书架页恢复系统大标题，以及既有搜索、图库、阅读、缓存、Cookie、书架回归。
