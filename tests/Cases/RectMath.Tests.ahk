; ─── RectMath：几何、边界与失败码 ───
; 这些数字都不是随手写的：方案一 / 方案二的高度是把注释里的公式手算一遍得来的，
; 改公式时这里必须先红。
RectMath_Tests() {
    T_Group("RectMath.Physical")
    n := {x: 100, y: 200, w: 500, h: 400, frame: {l: 8, t: 31, r: 8, b: 8}}
    p := RectMath.Physical(n)
    T_Eq(p.x, 108, "可见 x + 左边框")
    T_Eq(p.y, 231, "可见 y + 上边框")
    T_Eq(p.w, 500, "左右边框互相抵消")
    T_Eq(p.h, 377, "400 + 下边框 8 - 上边框 31")

    T_Group("RectMath.Overlaps")
    a := {x: 0, y: 0, w: 10, h: 10}
    T_Ok(!RectMath.Overlaps(a, {x: 10, y: 0, w: 10, h: 10}), "横向贴边不算重叠")
    T_Ok(RectMath.Overlaps(a, {x: 9, y: 0, w: 10, h: 10}), "压住 1px 算重叠")
    T_Ok(!RectMath.Overlaps(a, {x: 5, y: 10, w: 10, h: 10}), "纵向贴边不算重叠")
    T_Ok(RectMath.Overlaps(a, {x: 0, y: 0, w: 10, h: 10}), "完全重合算重叠")

    wa := {x: 0, y: 0, w: 1920, h: 1040}

    T_Group("RectMath.CornerRect")
    c := RectMath.CornerRect(wa, 400, 300, 15, 10)
    T_Eq(c.x, 1505, "贴右下：右边距 15")
    T_Eq(c.y, 730, "贴右下：底边距 10")
    c2 := RectMath.CornerRect(wa, 2000, 300)
    T_Eq(c2.x, 10, "比工作区还宽时退到左缘 +10")
    T_Same(RectMath.CornerRect("", 400, 300), "", "非矩形入参返回空串")
    T_Same(RectMath.CornerRect(wa, 0, 300), "", "宽为 0 返回空串")

    T_Group("RectMath.TopRightRect")
    t := RectMath.TopRightRect(wa, 400, 300, 15, 120)
    T_Eq(t.x, 1505, "右上：右边距 15")
    T_Eq(t.y, 120, "右上：顶边距 120")
    t2 := RectMath.TopRightRect(wa, 400, 300, 15, -50)
    T_Eq(t2.y, 10, "负的顶边距收回到 +10")

    ; ─── PlanStack ───
    ; 帧：上 31（标题栏），其余 8
    nf := {l: 8, t: 31, r: 8, b: 8}
    opts := {gap: 12, margin: 0, minW: 400, minH: 200}

    T_Group("RectMath.PlanStack 方案一（伙伴在下）")
    ; peer {1000,600,400,500} → 可见 {992, 569, 1392, 1092}
    r := RectMath.PlanStack({x: 1000, y: 600, w: 400, h: 500}, wa, nf, nf, opts)
    T_Ok(r.ok, "空间够时应当成功")
    T_Eq(r.note.x, 992, "与伙伴可见左缘对齐")
    T_Eq(r.note.w, 400, "与伙伴同宽")
    T_Eq(r.note.h, 557, "顶到工作区顶，底边离伙伴可见顶 12px")
    T_Same(r.peer, "", "方案一不移动伙伴")
    T_Ok(!RectMath.Overlaps(r.noteRect, r.peerRect), "结果不得与伙伴重叠")

    T_Group("RectMath.PlanStack 方案二（伙伴贴顶）")
    ; peer 顶到 40 → 可见顶 9，方案一只剩 -3 高 → 退到方案二
    r2 := RectMath.PlanStack({x: 1000, y: 40, w: 400, h: 500}, wa, nf, nf, opts)
    T_Ok(r2.ok, "伙伴贴顶时仍能排开")
    T_Eq(r2.peer.y, 548, "伙伴下移：可见顶算到 517，加帧上边 31")
    T_Eq(r2.note.h, 505, "笔记高度按新位置重算")
    T_Ok(!RectMath.Overlaps(r2.noteRect, r2.peerRect), "下移后仍不重叠")

    T_Group("RectMath.PlanStack 失败与非法入参")
    r3 := RectMath.PlanStack({x: 1000, y: 600, w: 400, h: 500}, wa, nf, nf
        , {gap: 12, margin: 0, minW: 400, minH: 9999})
    T_Ok(!r3.ok, "最小高度放不下时失败")
    T_Same(r3.reason, "no-fit", "失败原因为 no-fit")

    T_Same(RectMath.PlanStack("", wa, nf, nf, opts).reason, "bad-peer-rect", "伙伴矩形非法")
    T_Same(RectMath.PlanStack({x: 0, y: 0, w: 10, h: 10}, "", nf, nf, opts).reason, "bad-work-area", "工作区非法")
    T_Same(RectMath.PlanStack({x: 0, y: 0, w: 10, h: 10}, wa, nf, nf, {gap: 1}).reason, "bad-opts", "opts 缺字段")
}
