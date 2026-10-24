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

    T_Group("RectMath.TopRightRect")
    wa := {x: 0, y: 0, w: 1920, h: 1040}
    t := RectMath.TopRightRect(wa, 400, 300, 15, 120)
    T_Eq(t.x, 1505, "右上：右边距 15")
    T_Eq(t.y, 120, "右上：顶边距 120")
    t2 := RectMath.TopRightRect(wa, 400, 300, 15, -50)
    T_Eq(t2.y, 10, "负的顶边距收回到 +10")
}
