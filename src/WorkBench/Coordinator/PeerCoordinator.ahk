#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PeerCoordinator —— 伙伴窗口布局协调（Phase 5b）
; ═══════════════════════════════════════════════════════════════════════════
; 平台层只算几何，不搬窗口：
;   · 提供 PlanStack() 给 WindowFeature 计算「笔记在上、伙伴在下」的堆叠落点；
;   · 真实布局发生时广播 SevenNote.Move / Launcher.Move ——
;     WindowFeature 搬笔记窗口，LauncherModule 搬伙伴窗口，平台不跨模块 WinMove。
; 旧的 Peer.* 桥接已在 Phase 5b 移除：伙伴生命周期统一走 Launcher.Preparing /
; Launcher.Opened / Launcher.Failed，执行路径统一走上面两个 Move 事件。
; ⚠ v2.16 删掉「记录双方最近一次落位」那半截（_lastNote / _lastPeer + GetLast*）：
;   一个调用方都没有，而 PlanStack 只认传进来的矩形 —— 留着就得订阅两个事件、
;   维护一份随时可能与真实窗口不同步的副本。

class PeerCoordinator {

    ; ─── 几何：协调器只读业务上下文，算式交给平台能力 RectMath ───
    ; 返回：
    ;   {ok: false, reason}
    ;   {ok: true, note: {x,y,w,h,frame}, noteRect: {x,y,w,h},
    ;    peer: "" 或 {hwnd,x,y}, peerRect: {hwnd,x,y,w,h}}
    ; note 是「可见边界」，noteRect 是 WinMove 认的物理外框；peer 非空表示
    ; 伙伴需要下移（方案二），peerRect 是下移后的矩形。
    static PlanStack(noteHwnd, peerRect, publish := false) {
        if !noteHwnd || !IsObject(peerRect)
            return {ok: false, reason: "bad-input"}
        if !(peerRect.HasProp("x") && peerRect.HasProp("y")
            && peerRect.HasProp("w") && peerRect.HasProp("h"))
            return {ok: false, reason: "bad-peer-rect"}
        if !(IsNumber(peerRect.x) && IsNumber(peerRect.y)
            && IsNumber(peerRect.w) && IsNumber(peerRect.h))
            return {ok: false, reason: "bad-peer-rect"}
        if (peerRect.w <= 0 || peerRect.h <= 0)
            return {ok: false, reason: "bad-peer-rect"}

        pr := {hwnd: peerRect.HasProp("hwnd") ? peerRect.hwnd : 0
            , x: peerRect.x, y: peerRect.y, w: peerRect.w, h: peerRect.h}

        ; 工作区取伴生窗口所在的那块显示器 —— 它可能被放到副屏上
        workArea := WindowProbe.WorkAreaFor(pr)
        if !IsObject(workArea)
            return {ok: false, reason: "no-work-area"}

        ; 最小尺寸：Config 里是逻辑单位，乘 DPI 比才是 WinMove 认的物理像素
        ; （+MinSize450x300 → 本机 150% 缩放下的 675x450）
        opts := {gap: Config.DockGap, margin: Config.DockMargin
            , minW: 450 * A_ScreenDPI // 96
            , minH: 300 * A_ScreenDPI // 96}

        plan := RectMath.PlanStack(pr, workArea
            , WindowProbe.InvisibleFrame(noteHwnd)
            , WindowProbe.InvisibleFrame(pr.hwnd)
            , opts)
        if (plan.ok && publish)
            this._PublishMoves(noteHwnd, plan)
        return plan
    }

    ; 真实布局发生时广播 —— Phase 5b 起这就是执行路径，而不是状态预演。
    ; 载荷一律是**物理外框**（WinMove / WinGetPos 的单位）：
    ;   · SevenNote.Move → WindowFeature._OnNoteMove() 搬笔记窗口；
    ;   · Launcher.Move  → LauncherModule._OnMove()   搬终端 / 浏览器窗口。
    ; 先发伙伴再发笔记，保持旧实现「先把伙伴挪下去、再摆笔记」的实际顺序。
    static _PublishMoves(noteHwnd, plan) {
        if IsObject(plan.peer)
            EventBus.Emit("Launcher.Move", {hwnd: plan.peer.hwnd
                , x: plan.peer.x, y: plan.peer.y
                , w: plan.peerRect.w, h: plan.peerRect.h})
        EventBus.Emit("SevenNote.Move", {hwnd: noteHwnd
            , x: plan.noteRect.x, y: plan.noteRect.y
            , w: plan.noteRect.w, h: plan.noteRect.h})
    }
}
