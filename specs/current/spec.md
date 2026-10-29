# 文本库双库（提示词 / Skill）规格

> 状态：实现中　建立于 2026-10-28
> 命名定稿：`_prompts` / `_skills`（跟随笔记库，与 `_assets` 一致）

## 一、要做什么

1. 一个窗口两个 Tab。
2. Skill 独立目录：默认 笔记库\_skills，[Paths] SkillsDir 可覆盖。
3. 面板「文本」页加两个 folder 字段（PromptsDir / SkillsDir），留空 = 跟随笔记库。

## 二、不做什么

- 不新增热键（Alt+P 唯一入口）
- 不建第二个 WebView2 实例（dataDir 保持 prompts）
- 不做 skill 的元数据与执行器语义

## 三、验收

- 切 Tab 后列表/分类/搜索全部切换，选中清空。
- Skill 新建文件落在 _skills；编辑保存不串库。
- 退出守卫覆盖两库；面板改目录后重扫。
- run-tests 全绿、check-docs 0、日志无新增。
