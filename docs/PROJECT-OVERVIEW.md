# SevenWork 项目全景（一页纸）

> **用途**：一屏看完「这是什么 · 做到哪了 · 还欠什么」。
> 文档地图见 [`README.md`](README.md)；完整手册见 [`../README.md`](../README.md)；
> 人的决策记录见 [`DEVLOG.md`](DEVLOG.md)。
> 口径：`2026-10-23`，版本 `v2.14`。**本文数字是当日快照**，代码变了以 `src/` 为准。

---

## 一句话

用 AutoHotkey v2 写的 **Windows 本地速记工具**：`Alt+Z` 一键唤出，编辑区是 WebView2 里的
Milkdown，**保存就是写 `.md`** —— 没有中间格式，写完直接进 Obsidian 收件箱。

---

## 规模

| 项 | 数值（2026-10-23） |
| --- | --- |
| 源码 | 根 `SevenWork.ahk` 启动器 + `src/` 组合根 + `WorkBench/` 平台层 + 六个模块 + `web/src/` 前端 |
| 自有代码 | AHK 约 10,200 行（58 文件）、前端约 5,700 行，合计约 15,800 行（含注释，不含 `src/lib/` 第三方库） |
| 模块 | 6 个：笔记 / 文本 / 文件夹 / 外部程序 / 键位 / 外观 |
| 文档 | `README.md` 约 710 行；`docs/` 现状 5 份 + `archive/` 历史 3 份 + `devlog/` 归档 4 卷 |

---

## 解决什么问题

| 痛点 | 做法 |
| --- | --- |
| 打开笔记软件 3~5 秒，灵感跑了 | 全局热键呼出 / 隐藏，不用先找窗口 |
| 记完就找不回 | 每天一个文件，**标签写在文件名里**：`2026-09-20-机器学习.md` |
| 同步到 Obsidian 图片全丢 | 图片存 `_assets/日期/`，正文写相对路径 |
| 忘记保存丢数据 | 定时 / 隐藏 / 切日期自动保存；空笔记不落盘；写入走临时文件替换 |
| 格式锁死在某个软件里 | 落盘就是标准 Markdown，任何编辑器都能开 |

---

## 能力清单

**编辑**（Milkdown）
- `Ctrl+V` 粘图 → 自动存 `_assets/日期/` + 正文写相对路径
- `Tab` / `Shift+Tab` 列表升降层级、段落增删行首空格
- `Ctrl+T` 时间戳 / `Ctrl+H` 分隔线 / `Ctrl+Shift+H` 分段标题

**日期与标签**
- `Alt+↑↓` 前后一天 / `Alt+Home` 回今天
- `Ctrl+Shift+T` 设标签（写进文件名）
- `Ctrl+G` 按日期 / 标签跳转

**外观**
- 主题：**哑光灰**（`242424` 底 / `F2F2F2` 字），一套玻璃材质
- `Alt+T` 循环切换（平台级，所有窗口一起跟）；只有一套时是空操作
- `Alt+S` 面板里可调材质浓度 / 圆角 / 动效 / 密度

**其他模块**
- `Alt+P` 提示词库（`<Vault>\_prompts\`，普通 Markdown 文件）
- `Alt+1/2/3` 文件夹槽位；`Alt+M` 把选中的 docx / pptx 等转成 Markdown
- `Alt+C` PowerShell、`Alt+X` DeepSeek 网页 —— 笔记自动让位对齐成一列
- `Alt+Shift+C` CapsLock → `H/J/K/L` 方向键

---

## 数据怎么存

```
你的Vault/                          ← 只需备份这个目录
├── 2026-09-20.md                  每天的笔记
├── 2026-09-20-机器学习.md          带标签的版本（标签在文件名里）
├── _assets/2026-09-20/image1.png   ★ 图片统一收纳
└── _prompts/                       提示词库（普通目录 + 普通 md）

%AppData%\SevenWork\                _config.ini、_error.log（pandoc.exe 仅 EXE 版）
```

**没有中间格式**：保存就是写 `.md`。RichEdit 时代「RTF 母版 + Markdown 副本」的双份归档
已在 v2.9 取消 —— 代价是丢掉 RTF 能表达的字符级格式，换来的是不会双份不同步。

---

## 架构

| 层 | 干什么 | 硬约束 |
| --- | --- | --- |
| FEATURE | 一个用户旅程一个类 | 可插拔 |
| SERVICE | 业务策略（可读 Config / State） | 不认识 Feature |
| KERNEL | Config / ConfigService / EventBus / State | 冻结，只加不改 |
| CAPABILITY | 只收 hwnd / 数字 / Rect | 不读 Config、不发事件、不认识 `modules/*` |
| 界面 | `web/src/`（Vue + Milkdown），窗口骨架 `WebWindow` | 只通过 hostObjects 与 AHK 通信 |

依赖方向：`Feature / Module → Service → Kernel → OS`，以及 `Feature / Module → Capability → OS`。

**加新功能三步**：加一个 Feature 类 → 在所属模块的 `GetHotkeys()` 加一行（注册与 `Alt+S`
面板共用同一份数据；平台热键归 `WorkBench.GetHotkeys()`）→ `EventBus.Emit` 通知结果。
完整步骤见 [`../.clinerules/02-architecture.md`](../.clinerules/02-architecture.md)。

**三个关键决策**
1. **Markdown 是唯一母版** —— 保存就是写 `.md`，不维护双份文件
2. **编辑器放在 WebView2 里** —— 原生 RichEdit 做不出现代排版，也留不住多窗口一致性
3. **通用格式转换交给 Pandoc** —— `Alt+M` 用，笔记保存链路不经过它

---

## 目前欠账与限制

**数据安全（优先级最高，尚未闭环）**
- `Alt+Shift+Z` 退出时不检查保存结果 —— 保存失败也会退出
- 收起窗口时不检查保存结果 —— 保存失败仍然隐藏
- 「无改动不写盘」比较的是序列化结果与磁盘文本，且用的是 `=`（不区分大小写）
- 没有真正的 dirty 基线，也没有外部修改检测
- 标签改名后会话路径不同步；同一天多个文件时只认第一个

**功能**
- 文内搜索 / 跨日期检索已下线（改用 Obsidian / VS Code）
- 背景图主题暂缓（机制在，主题表里没有带图的条目）
- 第二个伙伴不触发笔记重排

| 限制 | 说明 |
| --- | --- |
| 仅 Windows | AHK v2 的平台限制 |
| 改配置要重启 | `_config.ini` 在进程内被缓存（v2.4.2 起） |
| 标签单字段 | 每个日期一个标签 |

---

## 仓库结构

| 路径 | 用途 |
| --- | --- |
| `SevenWork.ahk` | 根目录启动器：把入口转给 `src/`，保持项目根为 `A_ScriptDir` |
| `src/SevenWork.ahk` | 组合根：装配 + 启动 |
| `src/WorkBench/` | 平台层：Kernel / 热键路由 / 模块登记 / `WebWindow` / 面板 / 伙伴协调 |
| `src/modules/SevenNote/` | 笔记模块：编辑器宿主 + 保存 / 自动保存 / 日期跳转 / 标签 |
| `src/modules/Text/` | 提示词库（`Alt+P`） |
| `src/modules/Folders/` | 文件夹槽位（`Alt+1/2/3`）+ 转 Markdown（`Alt+M`） |
| `src/modules/Launcher/` | 外部程序（`Alt+C` / `Alt+X`） |
| `src/modules/KeysInput/` | CapsLock 映射（`Alt+Shift+C`） |
| `src/modules/Theme/` | 外观参数设置页（不持有主题） |
| `web/src/` | 前端：笔记编辑器 / 面板 / 提示词库 / 主题 |
| `web/dist/` | 前端构建产物（入库，AHK 从这里加载） |
| `README.md` | 完整手册：特性 / 热键 / FAQ / 开发指南 |
| `docs/CHANGELOG.md` | 版本历史：每版的改动、踩坑与判据 |
| `docs/DEVLOG.md` | 决策日志：原话、判断、放弃方案、待办 |
| `docs/CAPABILITIES.md` | 平台能力契约 |
| `docs/THEME-IMAGES.md` | 背景图主题：参数与实测账（暂缓） |
| `docs/LAUNCHER-GUIDE.md` | 外部窗口适配：三事件契约、调参 |
| `docs/archive/` | 历史快照：RichEdit 时代技术清单 / 工作台化计划 / 主题计划 |
| `docs/devlog/` | 归档的开发日志（按主题分卷） |
| `.clinerules/` | 给 AI 的约定：语言 / 架构 / AHK v2 坑 / 验证 / 烘图 / 日志 |
| `tools/` | `pick-theme-colors.ps1`、`rebake-backdrop.ps1`、`check-docs.ps1` |
| `docs/screenshots/` | README 配图 |

---

## 取向

1. **不打断工作流** —— 秒级呼出、无感保存、空笔记不落盘
2. **宁可慢一点，也不能坏** —— 500 ms 兜底 vs 50 ms 轮询的取舍即例证
3. **诚实记录代价** —— 每项优化都写明"代价是……"，每个踩坑都留实测数据
4. **单人项目也讲工程边界** —— 四层架构、事件总线、探针验证、异常兜底、决策日志
