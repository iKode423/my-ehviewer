# MyEHViewer

MyEHViewer 是一个 iOS 阅读应用项目，目标是支持浏览 `https://e-hentai.org/` 上与搜索、图库详情和阅读相关的主要功能。

## 当前阶段

- 已初始化 SwiftUI iOS 工程骨架。
- App 内可见文案使用中文。
- 已建立基础搜索页、阅读器页和设置页占位。
- 已建立项目文档目录 `Docs/`。
- 已查证搜索页、图库详情页和图片阅读页的公开 HTML 结构。
- 已建立领域模型、HTTP 客户端、搜索/详情/阅读页解析器和中性 fixture 测试。
- 已实现公开搜索页闭环：关键词搜索、隐藏分类、高级搜索参数、缩略图列表和上下页。
- 已实现图库详情页：从搜索进入详情，展示封面、标题、分类、上传者、元信息、评分、标签和页面入口。

## 技术选择

- SwiftUI
- Swift Concurrency
- URLSession
- XCTest
- 最低系统版本：iOS 17.0

## 验证

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## 开发约定

- 每完成一个明确阶段，先验证，再请求确认提交。
- 所有面向用户的 App 文案默认使用中文。
- 不在仓库内保存站点内容、用户凭据或抓取到的图片资源。
