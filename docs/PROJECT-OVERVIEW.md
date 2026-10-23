# SevenWork 项目全景（一页纸）

> **用途**：一屏看完「这是什么 · 做到哪了 · 还欠什么」。
> 文档地图见 [`README.md`](README.md)；完整手册见 `../README.md`；人的决策记录见 `DEVLOG.md`；
> 工作台化路线见 `WORKBENCH-PLAN.md`（三张归属表 + Phase 0–6）。
> 口径：`2026-10-21`，版本 `v2.8`，`main` = 日用 / 稳定。

---

## 一句话

用 AutoHotkey v2 写的 **Windows 本地速记工具**：`Alt+Z` 一键唤出、富文本编辑、图文混排，
保存时同时产出 **RTF 母版 + Markdown 副本**，直接进 Obsidian 收件箱。

单文件发行 · 运行内存 ~10 MB · 启动 < 100 ms。

---

## 规模

| 项 | 数值 |
| --- | --- |
| 源码 | 根 `SevenWork.ahk` 启动器 + `src/` 下组合根、`WorkBench/` 平台层、`modules/SevenNote/` 笔记模块、`modules/Launcher/` 外部程序模块、`modules/KeysInput/` 键位模块 |
| 类 | 57 个 = Kernel 4 + Capability 7 + Coordinator 1 + 平台 4 + 模块 5 + StatusBar 1 + Service 10 + Feature 25 |
| 文档 | `README.md` 约 740 行（手册正文）；版本历史拆到 `docs/CHANGELOG.md`，开发日志在 `docs/DEVLOG.md` |
| 发行物 | 编译后约 250 MB（含内嵌 Pandoc 100+ MB） |

---

## 解决什么问题

| 痛点 | 做法 |
| --- | --- |
| 打开笔记软件 3~5 秒，灵感跑了 | 全局热键，100 ms 内呼出 / 隐藏 |
| 只有纯文本 | RichEdit：加粗 / 颜色 / 字体 / 内嵌图片 |
| 笔记散在时间线里找不回 | 每天一个文件，**标签写在文件名里**：`2026-09-20-机器学习.md` |
| 同步到 Obsidian 图片全丢 | 自动生成 `.md` + `_assets/日期/` |
| 忘记保存丢数据 | 定时 / 隐藏 / 切日期 / 粘贴后自动保存，空笔记不落盘 |

---

## 能力清单

**编辑**
- `Ctrl+V` 粘图（自动存 PNG + 生成 MD 链接）、`Ctrl+Shift+V` 粘贴纯文本
- `Ctrl+Y` 删行 / `Ctrl+D` 复制行 / `Ctrl+Shift+↑↓` 移行
- `Tab` / `Shift+Tab` 缩进**不丢字符格式**
- `Ctrl+H` 按编辑区宽度动态插入分隔线 / `Ctrl+Shift+H` 分段标题 / `Ctrl+T` 手动时间戳

**日期与标签**
- `Alt+↑↓` 前后一天 / `Alt+Home` 回今天 / 切日期自动定位到开头
- `Ctrl+Shift+T` 设标签，状态栏常驻 `🏷 标签`
- `Ctrl+G` 按日期 / 标签跳转 / `Ctrl+F` 文内搜索

**外观**
- 主题：**哑光灰**（`242424` 底 / `F2F2F2` 字）；护眼绿 / 纸白 / 星空 / 金克斯暂时下线
- `Alt+T` 循环切换（平台级热键，所有模块窗口一起跟）；只有一套时是空操作
- 标题栏、滚动条、状态栏一同跟主题染色；自动记忆，重启保留

**伙伴窗口**
- `Alt+C` PowerShell、`Alt+X` DeepSeek 网页 —— 笔记自动让位对齐成一列
- `Alt+Shift+C` CapsLock → `H/J/K/L` 方向键

---

## 数据怎么存

```
你的Vault/                          ← 只需备份这个目录
├── 2026-09-20.rtf                  富文本母版（936 代码页，给 WPS/Word）
├── 2026-09-20.md                   Markdown 译本（便携）
├── 2026-09-20-机器学习.rtf / .md    带标签的版本
├── _assets/2026-09-20/image1.png   ★ 图片统一收纳
└── _tmp/                           Pandoc 临时目录（自动清理）

%AppData%\SevenWork\                pandoc.exe（100+MB）、_config.ini、_error.log
```

**双格式归档**：同一次保存产出 RTF(936) + RTF(65001) + Markdown —— 三方对编码的要求互相冲突，
两份 RTF 各喂一方。

---

## 架构

```
FEATURE  功能层   25 项  →  Feature 之间零调用，靠 EventBus 通信，可插拔
SERVICE  服务层   10 项  →  纯能力，无业务 / 无时间 / 无理由
KERNEL   骨架层    4 项  →  Config / ConfigService / EventBus / State（冻结，只加不改）
CAPABILITY 能力层  7 项  →  只收 hwnd / 数字 / Rect，不读 Config / 不发事件
表示层：StatusBar       组合根：装配 + 启动
依赖方向：Feature → Service → Kernel → OS（严禁反向）
```

**加新功能三步**：加一个 Feature 类 → 在所属模块的 `GetHotkeys()` 加一行（注册与 `Alt+S`
帮助共用同一份数据；平台热键归 `WorkBench.GetHotkeys()`）→ `EventBus.Emit` 通知结果。

**三个关键决策**
1. `EM_STREAMOUT/EM_STREAMIN` 直读直写 RTF（不拿剪贴板当进程内私有通道）
2. Pandoc 转 Markdown（不自研解析器）
3. 双 RTF 输出（兼容 WPS/Word 与 Pandoc 两套编码口径）

---

## 目前欠账与限制

**有意识的欠账**
- 删掉末尾空行后视口不跟手 → 现用 **500 ms 兜底**修复（慢半拍）；想更快只能子类化 `WndProc`
- 50 ms 轮询版曾导致真机报错，原因未定位，已回退

**已知限制**

| 限制 | 说明 |
| --- | --- |
| 仅 Windows | AHK v2 的平台限制 |
| 不支持跨日期全文搜索 | 搜索只在当前笔记内 |
| 无云同步 | 靠 OneDrive / 坚果云 |
| 标签单字段 | 每个日期一个标签 |
| 改配置要重启 | `_config.ini` 在进程内被缓存（v2.4.2 起） |
| 第二个伙伴不触发重排 | 笔记窗口只对第一个呼出的伙伴让位 |

---

## 仓库结构

| 路径 | 用途 |
| --- | --- |
| `SevenWork.ahk` | 根目录启动器：把入口转给 `src/`，保持项目根为 `A_ScriptDir` |
| `src/SevenWork.ahk` | 组合根：装配 + 启动 |
| `src/WorkBench/` | 平台层：Kernel / 热键路由 / 模块登记 / 帮助 / 伙伴协调 |
| `src/modules/SevenNote/` | 笔记模块：6 个 Service + `StatusBar` + 18 个 Feature + 生命周期 |
| `src/modules/Launcher/` | 外部程序模块：`PeerLayoutService` + PowerShell / DeepSeek Feature + 生命周期 |
| `src/modules/KeysInput/` | 键位模块：`CapsLockFeature` + `Alt+Shift+C` 生命周期 |
| `README.md` | 完整手册：特性 / 热键 / FAQ / 开发指南 |
| `docs/CHANGELOG.md` | 版本历史：每版的改动、踩坑与判据 |
| `docs/THEME-IMAGES.md` | 背景图主题：参数、实测账、踩坑全文 |
| `docs/LAUNCHER-GUIDE.md` | 外部窗口适配：三事件契约、调参、实测账 |
| `docs/devlog/` | 归档的开发日志（2026-Q4 重构期 / 工作台化） |
| `docs/PROJECT-OVERVIEW.md` | 一页纸全景：定位 / 规模 / 欠账 / 限制 |
| `docs/PROJECT-IMPLEMENTATION.md` | 技术实现清单：15 个「用了什么手段 → 实现什么效果」 |
| `docs/DEVLOG.md` | 开发日志：人的原话、判断、放弃方案、待办 |
| `docs/WORKBENCH-PLAN.md` | 工作台化路线：三张归属表 + 模块接口 + Phase 0–6 |
| `.clinerules/` | 给 AI 的约定：语言 / 架构 / AHK v2 坑 / 验证流程 / 主题烘图 / 日志规则 |
| `tools/` | `pick-theme-colors.ps1`、`rebake-backdrop.ps1`、`check-docs.ps1`（文档体检） |
| `docs/screenshots/` | README 配图 |

---

## 取向

1. **不打断工作流** —— 秒级呼出、无感保存、空笔记不落盘
2. **宁可慢一点，也不能坏** —— 500 ms 兜底 vs 50 ms 轮询的取舍即例证
3. **诚实记录代价** —— 每项优化都写明"代价是……"，每个踩坑都留实测数据
4. **单人项目也讲工程边界** —— 四层架构、事件总线、探针验证、异常兜底、决策日志
