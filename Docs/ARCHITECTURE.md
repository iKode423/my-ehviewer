# 架构说明

## 分层

MyEHViewer 会按以下边界逐步建设：

- `App`：应用入口、根导航和通用文案。
- `Features/Search`：搜索输入、结果列表、高级搜索入口。
- `Features/Gallery`：图库详情、标签和元信息展示。
- `Features/Reader`：阅读器、图片页导航和阅读状态。
- `Networking`：HTTP 请求、Cookie header、请求头和响应错误。
- `Parsing`：HTML 到领域模型的解析。
- `Persistence`：历史、收藏和设置。

## 当前状态

当前仓库包含工程骨架、领域模型、HTTP 客户端、基础解析层、搜索界面闭环、图库详情页、基础阅读器和本地书架。解析层已覆盖搜索列表、图库详情和阅读图片页的核心结构，并使用中性 HTML fixture 测试。

搜索界面由 `SearchViewModel` 负责浏览来源、筛选状态、请求、解析、分页、初始关键词搜索、最近搜索、失败重试 URL 和错误状态，`SearchView` 只负责 SwiftUI 展示与用户输入，并可在根页面或详情页导航栈内复用。首页、热门、关注和站点收藏来源都通过 `EHSearchRequest` 生成 URL，再复用同一解析流程。

图库详情页由 `GalleryDetailViewModel` 负责详情请求、解析和缩略图分页合并，`GalleryDetailView` 展示封面、元信息、可继续搜索的标签、带缩略图的阅读页入口和失败重试操作。

阅读器由 `ReaderViewModel` 负责图片页请求、解析、翻页、已知页码范围、已知页面入口跳转状态和图片资源重载 token，`ReaderView` 展示当前图片、页码、上一页、下一页、缩略图目录、页码输入跳转、图片加载失败重试、缩放控制、显示偏好和原图入口。

本地书架由 `LibraryStore` 通过 `UserDefaults` 保存历史、收藏和最近阅读页。`LibraryView` 可从记录打开图库详情，也可从带进度的记录直接进入阅读器。它只保存图库 URL、标题、缩略图 URL 和页码等轻量元数据，不保存远端 HTML、图片或用户凭据。

设置页通过共享的 `LibraryStore` 展示本地数据数量，并提供清空历史、收藏和阅读进度的确认操作。阅读显示偏好和缩放倍率通过 `AppStorage` 在设置页和阅读器工具栏之间共享。

站点访问 Cookie 由 `SiteCookieStore` 保存到本机 Keychain。`URLSessionEHHTTPClient` 在请求公开站点页面时读取该 Cookie header 并注入请求，不在仓库内保存任何真实凭据。

## 约束

- App 不内置、缓存或提交站点上的内容资源。
- 用户凭据不写入仓库。
- 解析逻辑需要通过固定 HTML 样例测试，避免页面结构变动时静默失败。
- 真实页面结构变化时，先更新 `Docs/SITE_STRUCTURE.md`，再更新解析器和测试。
