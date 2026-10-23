# 文档地图

> **同一个问题只在一处有答案**，其余位置只放指针 —— 这是本仓库文档的唯一硬规则。
> 校验：`powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-docs.ps1`
> （链接是否存在 / 编码换行 / 版本号一致性）。

---

## 一、按问题找

| 你脑中的问题 | 唯一归属 | 其他位置只能写 |
| --- | --- | --- |
| 这是什么、值得用吗 | [`../README.md`](../README.md) | 指针 |
| 现在做到哪、还欠什么 | [`PROJECT-OVERVIEW.md`](PROJECT-OVERVIEW.md) | 指针 |
| 这个效果靠什么技术 | 当前看 [`PROJECT-OVERVIEW.md`](PROJECT-OVERVIEW.md) 的「架构」节 | 指针 |
| 平台能力收什么、不许做什么 | [`CAPABILITIES.md`](CAPABILITIES.md) | 指针 |
| 重构往哪走、模块怎么归属 | [`../.clinerules/02-architecture.md`](../.clinerules/02-architecture.md) | 指针 |
| vX.Y 改了什么 | [`CHANGELOG.md`](CHANGELOG.md) | 指针 |
| 为什么这么选、放弃过什么 | [`DEVLOG.md`](DEVLOG.md) | 指针 |
| 背景图主题怎么烘 | [`THEME-IMAGES.md`](THEME-IMAGES.md) | 指针 |
| 新加外部窗口怎么接 | [`LAUNCHER-GUIDE.md`](LAUNCHER-GUIDE.md) | 指针 |
| **不能**怎么做（给 AI） | [`../.clinerules/`](../.clinerules/) | 指针 |
| 半年前的判断（考古） | [`devlog/`](devlog/) | 只增不改 |

## 二、按读者找

| 读者 | 读什么 | 目的 |
| --- | --- | --- |
| 第一次听说这个项目 | `README.md` → `PROJECT-OVERVIEW.md` | 5 分钟决定用不用 |
| 要改代码的人 | `PROJECT-OVERVIEW.md` → `CAPABILITIES.md` → `.clinerules/02` | 先知道边界在哪 |
| 要加功能 / 加模块的人 | `.clinerules/02` 的「加新模块 / 加新功能的标准步骤」+ 对应专题指南 | 只改两处 |
| **新的 AI 会话** | `DEVLOG.md` 顶部三区（当前状态 / 待办 / 已放弃方案）→ `.clinerules/` 全部规则 | 不重复踩坑 |
| 想知道历史 | `CHANGELOG.md` → `DEVLOG.md` → `devlog/` | 考古 |

## 三、维护规则（改文档前先看这五条）

1. **新增内容先定位归属**：查上表；不属于任何一格，说明表要加一行 —— 别先写再想。
2. **同一事实不得出现在两处**：代码头注释里只留「为什么 + 指针」，版本流水账只在 `CHANGELOG.md`。
3. **数字必须带口径**：写「57 个类」必须同时能回答「哪天的 57」；易变数字（行数）宁可不写。
4. **移动 / 删除后反查引用**：
   `Select-String -Path README.md,docs\*.md,.clinerules\*.md -Pattern '旧章节名'`
5. **改完跑一次** `tools\check-docs.ps1`：链接失效、编码跑偏、版本号不一致会当场报出来。

## 四、体量约定

| 触发 | 动作 |
| --- | --- |
| 单文件 > 600 行 | 提示归档，不要自行归档（`.clinerules/06`） |
| README 某一节 > 一屏 | 拆成 `docs/` 专题，正文只留「一句话版本 + 指针」 |
| `DEVLOG.md` 跨天 | 主文件只留最近一天，其余进 `devlog/<年>-Q<n>-<主题>.md` |
| 同一坑出现第 3 次 | 进 `.clinerules/03` 的坑表（症状 → 对策），而不是再写一遍叙事 |
