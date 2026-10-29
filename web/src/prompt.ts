/* ═══════════════════════════════════════════════════════════════════════
   提示词库（Alt+P）—— 数据契约 + 调用

   与 src\modules\Text\HostBridge.ahk 的 PromptData.Json() 逐字对齐。
   ⚠ 改字段名必须两边同改：前端拿到 undefined 不报错，只会静默少一行 / 少一栏。

   · 列表**不含正文**：几百条 × 每条几百字过一次 COM 序列化要好几百毫秒，
     而列表只用标题 / 分类 / 摘要。复制与编辑都是回 AHK 做的（正文在那边）。
   · 返回值一律带前缀："ok" / "err:原因"。调用方取前缀，原因直接显示给用户。
   ═══════════════════════════════════════════════════════════════════════ */

import { ahkCall, isHosted } from './ahk'

export interface PromptItem {
  title: string
  /** 相对路径做分类；根目录下的条目是空串（`Code\代码审查` 这种多级分类也是它） */
  category: string
  /** 绝对路径 —— 复制 / 编辑用的键，也是「回到这一条」的定位依据 */
  path: string
  summary: string
  /** 文件修改时间 YYYYMMDDHH24MISS */
  mtime: string
}

export interface PromptData {
  /** 提示词根目录（状态栏尾部的说明用） */
  root: string
  /** 所有分类目录（含**空目录**：刚建好的分类不该「消失」） */
  categories: string[]
  items: PromptItem[]
  /** 编辑窗保存 / 删除后要定位的那一条；空串 = 不定位 */
  focus: string
}

/** 拉整份数据；浏览器预览里返回 null（调用方退回内置样本） */
export async function fetchPrompts(force = true): Promise<PromptData | null> {
  if (!isHosted()) return null
  const raw = await ahkCall<string>('data', force ? '1' : '0')
  return raw ? (JSON.parse(raw) as PromptData) : null
}

/** 复制正文到剪贴板。AHK 侧成功会自己在鼠标旁闪一下确认。返回 "ok" | "err:…" */
export async function copyPrompt(path: string): Promise<string> {
  return String(await ahkCall<string>('copy', path))
}

/** 打开编辑窗（**原生**窗口，本轮没搬）。path 为空 = 新建。返回 "ok" | "err:…" */
export async function editPrompt(path: string): Promise<string> {
  return String(await ahkCall<string>('edit', path))
}

/** 请求关窗（复制成功后由页面自己调 —— AHK 那边刻意不收窗，好让失败提示看得见） */
export async function closePrompt(): Promise<string> {
  return String(await ahkCall<string>('close'))
}

/** 只记失败，不记普通操作 */
export async function logPrompt(msg: string): Promise<void> {
  if (!isHosted()) return
  try {
    await ahkCall('log', msg)
  } catch {
    /* 日志本身失败就算了 —— 别再抛出去把调用点带崩 */
  }
}

/** Current lib: prompts | skills. */
export async function getLib(): Promise<string> {
  if (!isHosted()) return 'prompts'
  try {
    return String(await ahkCall<string>('getLib'))
  } catch {
    return 'prompts'
  }
}

/** Switch lib (Tab). Returns ok | err. */
export async function switchLib(lib: string): Promise<string> {
  return String(await ahkCall<string>('switchLib', lib))
}
