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

### 书架大标题遮挡回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。书架分段控件、线上收藏关键词搜索和翻页按钮改为滚动内容内的吸顶 header，不再通过顶层 `safeAreaInset` 覆盖系统大标题；既有搜索、图库、阅读、缓存、Cookie、书架回归测试通过。

### 设置主题色、书架间距与阅读器工具栏回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。非图库图片缓存清理按钮恢复标准图标标签；设置页显式应用自定义主题色到 tint 和 accent 控件；书架列表内容先包进稳定容器再添加外边距，避免列表项被异常撑开；阅读器顶部工具栏移除外部链接菜单；既有搜索、图库、阅读、缓存、Cookie、书架回归测试通过。

### 设置页确认弹窗与主题色即时刷新回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。非图库缓存清理入口文案缩短为“清空非图库缓存”，图标改用稳定可用的 `photo`；清理类确认弹窗改为挂在触发按钮自身；主题色变化时刷新设置列表并同步当前 UIKit window tint，让设置页控件无需重启即可更新颜色；既有搜索、图库、阅读、缓存、Cookie、书架回归测试通过。

### 图库 CSS Sprite 预览回归

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:MyEHViewerTests/EHParsingTests test
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。图库页缩略图解析改为优先使用父级/自身 CSS background sprite，并支持 `background-position-x/y` 与无 `px` 的 offset，避免无缓存时多页预览都退化成同一张 sprite 图；新增父级 CSS sprite + 内层占位图测试，既有搜索、图库、阅读、缓存、Cookie、书架回归测试通过。

### 本地签名配置回归

```sh
git diff --check
rg -n "<local Team ID and known site cookie tokens>" .
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -showBuildSettings | rg -n "DEVELOPMENT_TEAM|LOCAL_DEVELOPMENT_TEAM"
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。App target 的签名 Team ID 改为通过 `Config/Signing.xcconfig` 可选读取本机 `Config/Local.xcconfig`；真实本机配置已被 `.gitignore` 忽略，敏感扫描未在可提交文件中发现真实 Team ID 或站点 Cookie；完整测试通过。

### MIT 许可证文档验证

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/my-ehviewer-derived build
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/my-ehviewer-derived-ios CODE_SIGNING_ALLOWED=NO build
```

结果：`git diff --check` 通过。Xcode 测试和构建未完成，当前环境的 CoreSimulatorService 不可用，`xcodebuild test` 无法找到 `iPhone 17 Pro` 模拟器，generic 构建在 `actool` 编译资源时因无可用 Simulator runtime 失败。本轮仅新增 MIT 许可证和 README 说明。

### 缓存批量下载与重试回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:MyEHViewerTests/GalleryDownloadManagerTests test
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。设置页图片缓存区域移动到本地数据区域之前；缓存管理页新增继续未完成下载入口和下载进度/网速区域，只有有任务进行时显示；图库下载队列最多同时运行 5 个图库任务；单页图片下载失败会带随机短暂延迟重试，重试仍失败后跳过该页继续后续页面；新增重试成功和并发上限测试，完整回归测试通过。

### 搜索跳页、下载暂停与书架布局回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:MyEHViewerTests/SearchViewModelTests -only-testing:MyEHViewerTests/GalleryDownloadManagerTests -only-testing:MyEHViewerTests/EHParsingTests test
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。搜索结果分页区在上一页和下一页之间新增页码跳转；图库详情初始加载提示加入尊重减少动态效果的轻量旋转动画；缓存管理页有任务进行时将“继续未完成下载”切换为“暂停所有下载”，可取消运行任务并清空排队任务；书架页顶部控件不再固定，线上收藏翻页按钮移动到底部；新增搜索跳页 URL、下载暂停和文案回归测试，定向测试和完整回归测试通过。

### 搜索跳页参数、图库收藏状态与阅读保存回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:MyEHViewerTests/SearchViewModelTests -only-testing:MyEHViewerTests/GalleryDetailViewModelTests -only-testing:MyEHViewerTests/EHParsingTests -only-testing:MyEHViewerTests/MyEHViewerTests test
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。搜索页分页按钮改为图标按钮，页码跳转改用站点 zero-based `jump` 参数，因此第 1 页会请求 `jump=0`；图库标签区域改为默认折叠；图库详情会在有 Cookie 时读取线上收藏 popup，已收藏时在标题区显示线上收藏状态和分类；阅读页长按当前图片会先确认，再使用 Photos add-only 写入权限保存到系统相册；新增跳页参数、线上收藏状态读取/提交后状态、相册保存文案回归测试，定向测试和完整回归测试通过。

### 真机 Debug Dylib 启动回归

```sh
xcrun devicectl device info lockState --device iKode
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS,name=iKode' build
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS,name=iKode' -showBuildSettings | rg -n "ENABLE_DEBUG_DYLIB|MACH_O_TYPE|EXECUTABLE_NAME|LD_RUNPATH_SEARCH_PATHS"
otool -l ~/Library/Developer/Xcode/DerivedData/MyEHViewer-asduoirgkvnkeocmxnxbvjnwfqad/Build/Products/Debug-iphoneos/MyEHViewer.app/MyEHViewer | rg -n "__debug_dylib|debug_entry|MyEHViewer.debug|LC_MAIN|entryoff|LC_LOAD_DYLIB|LC_RPATH|path" -A2 -B1
xcrun devicectl device install app --device iKode ~/Library/Developer/Xcode/DerivedData/MyEHViewer-asduoirgkvnkeocmxnxbvjnwfqad/Build/Products/Debug-iphoneos/MyEHViewer.app
xcrun devicectl device process launch --device iKode com.ikode.MyEHViewer
xcrun devicectl device info processes --device iKode --filter "executablePath CONTAINS 'MyEHViewer'" --columns '*'
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。真机 Debug 构建显式关闭 `ENABLE_DEBUG_DYLIB`，避免 Xcode 使用 stub 可执行文件加载 `MyEHViewer.debug.dylib` 时在真机调试启动阶段停到 `0x00000000`；重新构建后包内不再包含 `MyEHViewer.debug.dylib` 或 `__preview.dylib`，Mach-O 不再包含 `__debug_dylib` 和 debug dylib 加载项。设备锁屏时 `devicectl` 会被 SpringBoard 拒绝启动，需要先解锁真机再运行；解锁后安装、启动成功，设备进程列表可见 `MyEHViewer.app/MyEHViewer`；完整模拟器回归测试通过。

### 搜索筛选、阅读长按与线上收藏误判回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:MyEHViewerTests/EHParsingTests -only-testing:MyEHViewerTests/GalleryDetailViewModelTests test
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

结果：通过。首页搜索和重置筛选按钮改为仅显示图标并保留无障碍标签；隐藏分类选中后改为灰色弱化状态；高级搜索区域改为不会把右侧控件挤出屏幕的宽度约束和菜单式评分选择；阅读页长按保存手势提高优先级，避免被翻页点击区吞掉；线上收藏状态改为必须同时解析到已选收藏分类和移除选项才显示已收藏，避免默认 `Favorites 0` 让所有图库都显示线上收藏；`.serena/` 已加入 `.gitignore`，本地工具状态不会进入提交列表。

### 搜索筛选紧凑布局与线上收藏状态回归

```sh
git diff --check
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:MyEHViewerTests/EHParsingTests -only-testing:MyEHViewerTests/GalleryDetailViewModelTests test
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcrun simctl boot 'iPhone 17 Pro'
xcrun simctl bootstatus 'iPhone 17 Pro' -b
xcrun simctl install booted /Users/ikode/Library/Developer/Xcode/DerivedData/MyEHViewer-asduoirgkvnkeocmxnxbvjnwfqad/Build/Products/Debug-iphonesimulator/MyEHViewer.app
xcrun simctl launch booted com.ikode.MyEHViewer
xcrun simctl io booted screenshot /tmp/my-ehviewer-compact-search-20260707c.png
```

结果：通过。首页搜索按钮改为 32pt 自绘圆形图标，重置图标按钮改为 28pt 圆形描边，最近搜索和隐藏分类按钮改为小芯片；高级搜索里的二元筛选改为左侧勾选行，不再使用右侧系统 Switch，避免窄屏溢出；线上收藏状态同时兼容移除分类、删除收藏按钮和修改/移除收藏文案，修复已收藏图库不显示状态的问题，同时保留默认 `Favorites 0` 未收藏保护。

### App 图标验证

```sh
xcodebuild -project MyEHViewer.xcodeproj -scheme MyEHViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
sips -g pixelWidth -g pixelHeight -g hasAlpha MyEHViewer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png MyEHViewer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-iphone-60x60@3x.png
plutil -p /Users/ikode/Library/Developer/Xcode/DerivedData/MyEHViewer-asduoirgkvnkeocmxnxbvjnwfqad/Build/Products/Debug-iphonesimulator/MyEHViewer.app/Info.plist | rg -n "CFBundleIcon|AppIcon|CFBundlePrimaryIcon" -C 2
xcrun simctl uninstall booted com.ikode.MyEHViewer
xcrun simctl install booted /Users/ikode/Library/Developer/Xcode/DerivedData/MyEHViewer-asduoirgkvnkeocmxnxbvjnwfqad/Build/Products/Debug-iphonesimulator/MyEHViewer.app
xcrun simctl io booted screenshot /tmp/my-ehviewer-appicon-home-final.png
```

结果：通过。AppIcon 由参考图提取像素风 `eh` 与书本图形，绿色替换为默认主题色 `#00A8FF`，黑底无透明通道；生成 iPhone/iPad/marketing 所需尺寸，并在工程 Debug/Release 配置中声明 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。构建产物 Info.plist 已生成 `CFBundleIconName = AppIcon`，模拟器卸载重装后主屏显示新图标。
