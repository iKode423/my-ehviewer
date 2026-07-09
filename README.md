# MyEHViewer

MyEHViewer 是一个 SwiftUI iOS 阅读应用，当前主要覆盖 E-Hentai 与 Hitomi 的搜索、图库详情、阅读、缓存、本地书架和统计分析流程。项目面向本地自用和持续迭代，不内置站点内容，也不会把 Cookie、图片缓存或抓取页面写入仓库。

## 当前状态

项目已经进入可日常试用的本地开发阶段：

- E-Hentai：支持首页、热门、关注、线上收藏、关键词搜索、隐藏分类、高级筛选、分页和跳页。
- Hitomi：支持首页列表、关键词搜索、图库详情、`group` 信息、关联图库、AVIF 图片和当前图片域名规则。
- 图库详情：展示封面、标题、分类、上传者/作者、信息、评分、标签、页面预览和关联图库；作者与大标题支持长按复制；标签和 Hitomi `group` 可直接发起搜索。
- 图库预览：Hitomi 初始最多显示 20 张预览，可继续加载更多；已缓存页面会优先使用本地图片作为预览。
- 阅读器：支持沉浸式阅读、点击左右区域翻页、左滑/右滑翻页、目录、跳页、缩放、横竖屏切换、背景模式、长按保存图片、失败重试和上次阅读恢复。
- 本地书架：记录历史、本地收藏和阅读进度；可从书架或缓存管理继续阅读到上次页码。
- 图片缓存：阅读过或下载过的图片会进入本机缓存；支持整本后台下载、暂停、继续未完成下载、单图库缓存管理、非图库缓存清理和 404 图库跳过。
- 设置：支持站点 Cookie、主题模式、主题色、阅读偏好、本地数据清理、缓存管理和本地统计分析。
- 统计分析：根据本地历史、收藏、最近搜索、缓存图库、缓存页数、作者、标签和分类生成概览与排行图表。
- 测试：解析、搜索、图库详情、阅读器、缓存、下载队列、书架、Cookie、Hitomi 图片规则等关键路径都有 XCTest 覆盖。

## 安装运行

1. 准备一台安装了 Xcode 的 Mac。
2. 克隆仓库并打开 `MyEHViewer.xcodeproj`。
3. 如需真机运行，按 `Config/Local.xcconfig.example` 创建本地签名配置 `Config/Local.xcconfig`，填入自己的开发团队 ID。
4. 选择模拟器或通过数据线连接的 iPhone。
5. 在 Xcode 中 Build/Run，或使用命令行：

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## 站点 Cookie

关注、线上收藏和部分需要登录态的 E-Hentai 页面需要 Cookie：

1. 在浏览器中登录并访问 `https://e-hentai.org/`。
2. 打开开发者工具，在网络请求中找到 `e-hentai.org` 的请求。
3. 在 `Request Headers` 中复制 `cookie` 的完整值。
4. 打开 App 设置页，在站点访问区域保存 Cookie。

Cookie 只保存在本机 Keychain，不会进入仓库。

## 数据与隐私

- 仓库不提交真实 Cookie、账号信息、站点 HTML、图片缓存或下载内容。
- 阅读图片仅作为本机缓存保存，可在设置页清理。
- 本地书架只保存轻量元数据，例如标题、URL、缩略图 URL、页码、标签和阅读进度。
- 统计分析只基于本机数据生成，不上传任何数据。

## 技术栈

- SwiftUI
- Swift Concurrency
- URLSession
- ImageIO / UIKit 图片渲染桥接
- Charts
- XCTest
- 最低系统版本：iOS 17.0

## 验证

常用完整回归命令：

```sh
xcodebuild test -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/MyEHViewerDerived
```

格式检查：

```sh
git diff --check
```

更多验证记录见 `Docs/QA.md`。

## 项目文档

- `Docs/ARCHITECTURE.md`：架构与主要模块说明。
- `Docs/ROADMAP.md`：阶段路线图和当前进度。
- `Docs/SITE_STRUCTURE.md`：站点结构调研记录。
- `Docs/QA.md`：验证记录。
- `Docs/DEVELOPMENT.md`：开发环境与本地签名说明。

## 开发约定

- 面向用户的 App 文案默认使用中文，集中维护在 `AppCopy`。
- 解析逻辑需要配套固定样例测试，避免站点结构变化时静默失败。
- 完成明确改动后先验证，再按 `type: 简短描述` 格式提交。
- 本地提交可直接进行；远程推送需要明确确认。

## 许可证

本项目使用 MIT 许可证，详见 `LICENSE`。
