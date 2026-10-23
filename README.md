# SevenWork

Windows 本地工作台：一个随叫随到的速记窗口，加上几个日常小工具。全部跑在 AutoHotkey v2 上，
界面是 WebView2 里的 Vue + Milkdown，**笔记直接读写 `.md`**。

![version](https://img.shields.io/badge/version-2.14-blue)
![platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20x64-lightgrey)
![language](https://img.shields.io/badge/language-AutoHotkey%20v2-green)
![license](https://img.shields.io/badge/license-MIT-orange)

> ⚠ **这是开发期仓库，不是稳定发行版。** 功能、数据结构、界面都还在改；
> 分发包、WebView2 运行时打包、跨机器首次运行**尚未验收**。要拿去日用请先读「已知风险」。

## 它是什么

```text
平台层   AHK 负责窗口、全局热键、文件读写、外部程序
界面层   WebView2 里的 Vue + Milkdown，负责编辑与面板
数据层   笔记就是 .md，直接落在你自己的 Obsidian 库里
```

六个模块：笔记（`Alt+Z`）、提示词库（`Alt+P`）、文件夹槽位（`Alt+1/2/3`）、
外部程序（`Alt+C` / `Alt+X`）、键位映射（`Alt+Shift+C`）、外观参数（`Alt+S` 里的设置页）。

## 快速开始

1. 装 **AutoHotkey v2**（64 位）—— 源码运行必需
2. 确认有 **WebView2 Runtime**（Win11 自带，Win10 多数随 Edge 装好）
3. 双击仓库根目录的 `SevenWork.ahk`（它只是启动器，实际入口在 `src\SevenWork.ahk`）
4. 首次运行会让你选笔记目录
5. 按 `Alt+Z` 呼出笔记窗口

**查热键不用翻文档**：按 `Alt+S` 打开工作台面板，「全部热键」一页列全、按模块分组。

## 数据在哪

```text
<你选的笔记目录>\             ← 只需备份这个
├─ 2026-09-20.md              每天的笔记
├─ 2026-09-20-机器学习.md      带标签的版本（标签写在文件名里）
├─ _assets\2026-09-20\        当天粘贴的图片
└─ _prompts\                  提示词库（普通目录 + 普通 .md）

%AppData%\SevenWork\           _config.ini、_error.log
```

- 写入走「同目录临时文件 → 写完替换」，中途失败不会留下半个文件；
- **内容没变就不写盘**；空笔记不落盘；
- 出问题先看 `%AppData%\SevenWork\_error.log`。

## 已知风险

| 风险 | 说明 |
| --- | --- |
| **外部修改可能被覆盖** | 没有文件监听。在 Obsidian 里改完再回来保存，以编辑器内容为准 |
| 同日多文件只认第一个 | 同一天同时有 `日期.md` 与 `日期-标签.md` 时，按日期只匹配第一个 |
| 收起前要能存住 | 工具栏 `×` 与 `Alt+Z` 都会先存盘；存不住就不收起（正文仍留在编辑器里） |
| 标签单字段 | 每个日期一个标签 |
| 仅 Windows | AHK v2 的平台限制 |
| 改配置要重启 | `_config.ini` 在进程内被缓存 |

## 开发

```powershell
# 文档与编码体检：链接 / LF / CRLF / 版本号 / 代码围栏
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-docs.ps1
```

语法预检与真机启动的正确做法见 [`.clinerules/04-workflow.md`](.clinerules/04-workflow.md)。

| 想了解 | 看 |
| --- | --- |
| 下次怎么少踩坑、哪里不能碰 | [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md) |
| 为什么长成今天这样、放弃过什么 | [`docs/HISTORY.md`](docs/HISTORY.md) |
| 改代码的硬约束与验证流程 | [`.clinerules/`](.clinerules/) |
| 接一个新的外部窗口 | [`docs/LAUNCHER-GUIDE.md`](docs/LAUNCHER-GUIDE.md) |

**进度与当前状态不写在文档里** —— 写下的那一刻就开始过期。直接问 AI，或者看代码 / `git log`。

## License

MIT — 见 [LICENSE](LICENSE)。
