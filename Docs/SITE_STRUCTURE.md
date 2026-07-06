# 站点结构记录

本文档记录 2026-07-05 查证到的 `https://e-hentai.org/` 搜索、详情和阅读相关结构，并在 2026-07-06 复核公开搜索表单字段。解析层只依赖这些公开页面结构，不在仓库保存真实站点内容。

## 搜索页

- 请求入口：`https://e-hentai.org/`
- 热门入口：`https://e-hentai.org/popular`
- 关注入口：`https://e-hentai.org/watched`
- 收藏入口：`https://e-hentai.org/favorites.php`；请求全部线上收藏分类时附加 `favcat=all`
- 关键词参数：`f_search`
- 分类隐藏字段：`f_cats`
- 下一页游标：`next`
- 上一页游标：`prev`
- 高级搜索标记：`advsearch=1`
- 浏览已清退图库：`f_sh`
- 只看有种子图库：`f_sto`
- 页数范围：`f_spf` 到 `f_spt`
- 最低评分：`f_srdd`
- 禁用自定义过滤：`f_sfl`、`f_sfu`、`f_sft`

搜索结果列表：

- 结果表：`table.itg.gltc`
- 分类：`.glcat .cn`
- 封面缩略图：`.glthumb img[src]`、`.glthumb img[data-src]` 或行内 CSS `url(...)`
- 详情链接：`.glname a[href^="https://e-hentai.org/g/"]`
- 标题：`.glink`
- 标签：`.gt[title]`
- 上传者和页数：`.glhide`
- 翻页链接：`#unext`、`#dnext`、`#uprev`、`#dprev`

## 图库详情页

- 标题：`#gn`
- 日文标题：`#gj`
- 分类：`#gdc .cn`
- 封面：`#gd1` 的背景图样式
- 上传者：`#gdn a`
- 元信息表：`#gdd .gdt1` 与 `.gdt2`
- 评分文案：`#rating_label`
- 评分数量：`#rating_count`
- 标签：`#taglist a[id^="ta_"]`
- 标签搜索：使用标签命名空间和值回填 `f_search`
- 缩略图阅读入口：`#gdt a[href^="https://e-hentai.org/s/"]`
- 页面缩略图：阅读入口内的 `img[src]`、`img[data-src]` 或当前入口父级/自身行内 CSS `url(...)`
- 页面缩略图裁剪：部分图库使用 CSS sprite，优先解析父级/自身 CSS background，读取 `width`、`height`、`background-position`、`background-position-x/y` 或 `background: url(...) -xpx -ypx`
- 缩略图分页：`.ptt a[href*="?p="]`、`.ptb a[href*="?p="]`
- 网站收藏弹窗：`gallerypopups.php?gid=<gid>&t=<token>&act=addfav`
- 网站收藏表单：保留 `input`/`textarea` 字段，使用 `favcat` 表示收藏分类，`favnote` 表示备注，提交时沿用表单 `action`
- 取消网站收藏：同一弹窗表单提交 `favcat=-1`

## 图片阅读页

- 图片：`#img[src]`
- 上一页：`#prev`
- 下一页：`#next`
- 回到图库：`#i5 a[href^="https://e-hentai.org/g/"]`
- 原图入口：`#i6 a[href^="https://e-hentai.org/fullimg/"]`
- 当前页码：阅读页 URL 末尾的 `<gid>-<page>`
