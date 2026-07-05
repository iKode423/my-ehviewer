# 架构说明

## 分层

MyEHViewer 会按以下边界逐步建设：

- `App`：应用入口、根导航和通用文案。
- `Features/Search`：搜索输入、结果列表、高级搜索入口。
- `Features/Gallery`：图库详情、标签和元信息展示。
- `Features/Reader`：阅读器、图片页导航和阅读状态。
- `Networking`：HTTP 请求、Cookie、请求头和响应错误。
- `Parsing`：HTML 到领域模型的解析。
- `Persistence`：历史、收藏和设置。

## 当前状态

当前仓库包含工程骨架、领域模型、HTTP 客户端、基础解析层、搜索界面闭环、图库详情页、基础阅读器和本地书架。解析层已覆盖搜索列表、图库详情和阅读图片页的核心结构，并使用中性 HTML fixture 测试。

搜索界面由 `SearchViewModel` 负责请求、解析、分页、最近搜索和错误状态，`SearchView` 只负责 SwiftUI 展示与用户输入。

图库详情页由 `GalleryDetailViewModel` 负责详情请求、解析和缩略图分页合并，`GalleryDetailView` 展示封面、元信息、标签和阅读页入口。

阅读器由 `ReaderViewModel` 负责图片页请求、解析、翻页和已知页面入口跳转状态，`ReaderView` 展示当前图片、页码、上一页、下一页、跳页、显示偏好和原图入口。

本地书架由 `LibraryStore` 通过 `UserDefaults` 保存历史、收藏和最近阅读页。它只保存图库 URL、标题、缩略图 URL 和页码等轻量元数据，不保存远端 HTML、图片或用户凭据。

设置页通过共享的 `LibraryStore` 展示本地数据数量，并提供清空历史、收藏和阅读进度的确认操作。阅读显示偏好通过 `AppStorage` 在设置页和阅读器工具栏之间共享。

## 约束

- App 不内置、缓存或提交站点上的内容资源。
- 用户凭据不写入仓库。
- 解析逻辑需要通过固定 HTML 样例测试，避免页面结构变动时静默失败。
- 真实页面结构变化时，先更新 `Docs/SITE_STRUCTURE.md`，再更新解析器和测试。
