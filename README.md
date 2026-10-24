# SevenWork

> 🤖 给 AI / 新会话的入口是 [`AGENTS.md`](AGENTS.md) —— 本文只讲「是什么、怎么跑」。

**一个面向个人 Windows 工作流的本地工作台。** 用统一的热键和面板，把速记、提示词、文件操作、
外部程序和输入辅助收在一处 —— 不用先找窗口、找软件。

后台是 AutoHotkey v2（管窗口、热键、磁盘、进程），前台是 WebView2 里的 Vue + Milkdown。
**记下来的东西都是普通文件**：笔记就是 `.md`，直接落在你自己的 Obsidian 库里。

![version](https://img.shields.io/badge/version-2.14-blue)
![platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20x64-lightgrey)
![language](https://img.shields.io/badge/language-AutoHotkey%20v2-green)
![license](https://img.shields.io/badge/license-MIT-orange)

> ⚠ **开发期项目，不是稳定发行版。** 分发包、WebView2 运行时打包、跨机器首次运行都**还没验收**。
> 日常自用可以，给别人装机之前先读「已知限制」。

## 它解决什么问题

| 痛点 | 做法 |
| --- | --- |
| 打开笔记软件要几秒，灵感等不起 | `Alt+Z` 呼出即写，收起自动存 |
| 常用动作散在好几个软件里 | 一个面板 + 一套热键：提示词、文件夹、终端、网页、转换 |
| 记下来的东西被某个软件锁死 | 落盘就是标准 Markdown，任何编辑器都能开 |
| 并排用时窗口手动摆两次 | 呼出伙伴窗口时，笔记窗口让位并对齐（只首次） |

## 现在有什么

| 模块 | 干什么 | 入口 |
| --- | --- | --- |
| 笔记 | 每日 `.md`，标签写在文件名里，图片收进 `_assets/日期/` | `Alt+Z` |
| 提示词库 | `<Vault>\_prompts\` 下的普通 Markdown | `Alt+P` |
| 文件夹槽位 | 三个常用目录随叫随到 | `Alt+1/2/3` |
| 外部程序 | PowerShell 终端、DeepSeek 网页，自动与笔记对齐 | `Alt+C` / `Alt+X` |
| 输入辅助 | CapsLock → `H/J/K/L` 方向键 | `Alt+Shift+C` |
| 外观 | 当前主题（整套观感由主题自己定义） | `Alt+S` 里的面板 |

退出程序用 `Alt+Shift+S`：笔记 / 提示词 / 面板里还有没保存的内容时会先拦下，不会直接丢。
笔记正文的字体与字号：`Alt+Shift+T` 换字体、`Alt+=` / `Alt+-` 调大小（笔记窗口在前台时才生效，避免抢别的程序的键）。

**完整热键表不用查文档**：按 `Alt+S` 打开工作台面板，「全部热键」一页列全、按模块分组。

## 跑起来

1. 装 **AutoHotkey v2**（64 位）
2. 确认有 **WebView2 Runtime**（Win11 自带；Win10 多数随 Edge 装好）
3. 双击仓库根目录的 `SevenWork.ahk` —— 它只是启动器，实际入口在 `src\SevenWork.ahk`
4. 首次运行选择笔记目录
5. 按 `Alt+Z`

改前端（`web\src\`）之后要在 `web\` 下 `npm run build`，产物 `web\dist\` 已入库、AHK 从这里加载。

## 数据与安全

```text
<你选的笔记目录>\             ← 只需备份这个
├─ 2026-09-20.md              每天的笔记
├─ 2026-09-20-机器学习.md      带标签的版本
├─ _assets\2026-09-20\        当天粘贴的图片
└─ _prompts\                  提示词库

%AppData%\SevenWork\           _config.ini、_error.log
```

实际做到的是这些（**不要当成更强的承诺**）：

- 写入走「同目录临时文件 → 写完替换」，避免直接截断原文件；
- 内容没变不写盘；空笔记不落盘；
- 收起窗口、保存退出前都会先确认保存成功，存不住就留在原地并给出提示。

**没做到**：断电 / 崩溃瞬间的强一致保证，外部修改检测，多端同步。

## 已知限制

| 限制 | 说明 |
| --- | --- |
| **外部修改可能被覆盖** | 没有文件监听。在 Obsidian 里改完再回来保存，以编辑器内容为准 |
| 同日多文件只认第一个 | `日期.md` 与 `日期-标签.md` 并存时，按日期只匹配第一个 |
| 标签单字段 | 每个日期一个标签 |
| 仅 Windows | AHK v2 的平台限制 |
| 改配置要重启 | `_config.ini` 在进程内被缓存 |
| DOCX 编号只验过样本 | 标题编号固化只对一份 23MB 课件验证过，`lvlOverride` / 罗马数字未处理 |

## 开发

```powershell
# 纯逻辑回归（不建窗口、不读配置、不碰真实笔记）：AHK 71 条 + 前端 17 条
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-tests.ps1

# 文档与编码体检：链接 / LF / CRLF / 版本号 / 代码围栏
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-docs.ps1
```

AHK 用例在 `tests\Cases\`，入口 `tests\RunTests.ahk`；前端纯函数用例在 `web\tests\`
（`node:test`，如 Markdown 清洁与代码区保护）。新增用例后要**故意改坏一次**，确认它会红。
语法预检、真机启动、探针的完整做法见 [`.clinerules/04-workflow.md`](.clinerules/04-workflow.md)。

| 想了解 | 看 |
| --- | --- |
| 这个项目要成为什么、不做什么 | [`docs/INTENT.md`](docs/INTENT.md) |
| 现在停在哪、下一步做什么 | [`docs/STATE.md`](docs/STATE.md) |
| 下次怎么少踩坑、哪些方向算过账 | [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md) |
| 改代码的硬约束 | [`.clinerules/`](.clinerules/) |
| 接一个新的外部窗口 | [`docs/LAUNCHER-GUIDE.md`](docs/LAUNCHER-GUIDE.md) |

历史看 `git log`；原始对话在仓库外的私人档案，不进 Git。

## License

MIT — 见 [LICENSE](LICENSE)。
