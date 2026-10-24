#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  ZoneMath 纯几何用例
; ═══════════════════════════════════════════════════════════════════════════
;  只测数字：不建窗口、不读配置、不查屏幕。
;  期望值按「辅助区贴右下、记录区在其正上方、工作区是左侧剩余」手算，
;  任何一条算错都会让「区域之间有缝 / 重叠 / 越界」露出来。

ZoneMath_Tests() {
    ; ─── 标准屏：2560x1600，辅助区 772x1020 ───
    T_Group("ZoneMath 标准屏")
    work := {x: 0, y: 0, w: 2560, h: 1600}
    opts := {right: 15, gap: 6, margin: 10
        , minWorkW: 320, minRecordH: 450, minAuxW: 120, minAuxH: 80}
    r := ZoneMath.FromAux(work, 772, 1020, opts)
    T_Ok(r.ok, "标准屏应当成功")
    if r.ok {
        T_Eq(r.aux.x, 1773, "辅助区 x = 2560 - 772 - 15")
        T_Eq(r.aux.y, 580, "辅助区 y = 1600 - 1020（底边贴工作区底）")
        T_Eq(r.aux.w, 772, "辅助区宽保持请求值")
        T_Eq(r.aux.h, 1020, "辅助区高保持请求值")
        T_Eq(r.record.x, 1773, "记录区与辅助区同 x")
        T_Eq(r.record.y, 10, "记录区顶边留 margin")
        T_Eq(r.record.w, 772, "记录区与辅助区同宽")
        T_Eq(r.record.h, 564, "记录区高 = 580 - 6 - 10")
        T_Eq(r.work.x, 10, "工作区左边留 margin")
        T_Eq(r.work.y, 10, "工作区顶边留 margin")
        T_Eq(r.work.w, 1757, "工作区宽 = 1773 - 6 - 10")
        T_Eq(r.work.h, 1590, "工作区高 = 1600 - 10")
        T_Eq(r.record.y + r.record.h + opts.gap, r.aux.y, "记录区与辅助区之间恰好留 gap")
        T_Eq(r.work.x + r.work.w + opts.gap, r.aux.x, "工作区与右列之间恰好留 gap")
    }

    ; ─── 小屏：高度放不下，缩辅助区、保记录区 ───
    T_Group("ZoneMath 小屏高度收缩")
    work2 := {x: 0, y: 0, w: 1920, h: 1040}
    r2 := ZoneMath.FromAux(work2, 772, 1020, opts)
    T_Ok(r2.ok, "小屏仍应成功")
    if r2.ok {
        T_Eq(r2.aux.h, 574, "辅助区缩到 1040 - 10 - 6 - 450")
        T_Eq(r2.aux.y, 466, "辅助区底边仍贴工作区底")
        T_Eq(r2.record.h, 450, "记录区保住最小高")
        T_Eq(r2.aux.x, 1133, "辅助区 x = 1920 - 772 - 15")
        T_Eq(r2.work.w, 1117, "工作区宽 = 1133 - 6 - 10")
        T_Eq(r2.work.h, 1030, "工作区高 = 1040 - 10")
    }

    ; ─── 宽度放不下，缩辅助区、保工作区 ───
    T_Group("ZoneMath 宽度收缩")
    work3 := {x: 0, y: 0, w: 1280, h: 1600}
    r3 := ZoneMath.FromAux(work3, 1000, 1020, opts)
    T_Ok(r3.ok, "窄屏仍应成功")
    if r3.ok {
        T_Eq(r3.aux.w, 929, "辅助区缩到 1280 - 10 - 15 - 6 - 320")
        T_Eq(r3.aux.x, 336, "辅助区 x = 1280 - 929 - 15")
        T_Eq(r3.work.w, 320, "工作区保住最小宽")
        T_Eq(r3.aux.h, 1020, "高度足够时不缩")
    }

    ; ─── 副屏：坐标带偏移，不能写死 0 ───
    T_Group("ZoneMath 副屏偏移")
    work4 := {x: 1920, y: -200, w: 2560, h: 1600}
    r4 := ZoneMath.FromAux(work4, 772, 1020, opts)
    T_Ok(r4.ok, "副屏应当成功")
    if r4.ok {
        T_Eq(r4.aux.x, 3693, "辅助区 x 叠加工作区偏移")
        T_Eq(r4.aux.y, 380, "辅助区 y 叠加工作区偏移")
        T_Eq(r4.record.y, -190, "记录区 y = -200 + 10")
        T_Eq(r4.record.h, 564, "副屏上记录区高度不变")
        T_Eq(r4.work.x, 1930, "工作区 x = 1920 + 10")
        T_Eq(r4.work.w, 1757, "副屏上工作区宽度不变")
    }

    ; ─── margin / right 改了，几何要跟着走 ───
    T_Group("ZoneMath 边距参数")
    opts20 := {right: 15, gap: 6, margin: 20
        , minWorkW: 320, minRecordH: 450, minAuxW: 120, minAuxH: 80}
    r5 := ZoneMath.FromAux(work, 772, 1020, opts20)
    T_Ok(r5.ok, "margin=20 应当成功")
    if r5.ok {
        T_Eq(r5.record.y, 20, "记录区顶边跟 margin")
        T_Eq(r5.record.h, 554, "记录区高 = 580 - 6 - 20")
        T_Eq(r5.work.x, 20, "工作区左边跟 margin")
        T_Eq(r5.work.w, 1747, "工作区宽 = 1773 - 6 - 20")
        T_Eq(r5.work.h, 1580, "工作区高 = 1600 - 20")
    }
    opts0 := {right: 0, gap: 6, margin: 10
        , minWorkW: 320, minRecordH: 450, minAuxW: 120, minAuxH: 80}
    r6 := ZoneMath.FromAux(work, 772, 1020, opts0)
    T_Ok(r6.ok, "right=0 应当成功")
    if r6.ok {
        T_Eq(r6.aux.x, 1788, "right=0 时辅助区贴工作区右缘")
        T_Eq(r6.work.w, 1772, "工作区宽 = 1788 - 6 - 10")
    }

    ; ─── 放不下：必须明确失败，不能返回负数尺寸 ───
    T_Group("ZoneMath 放不下")
    r7 := ZoneMath.FromAux({x: 0, y: 0, w: 800, h: 500}, 772, 1020, opts)
    T_Ok(r7.ok == false, "高度不足应当失败")
    T_Same(r7.reason, "no-fit", "失败原因为 no-fit")

    ; ─── 非法入参 ───
    T_Group("ZoneMath 非法入参")
    T_Same(ZoneMath.FromAux({x: 0, y: 0, w: 0, h: 1600}, 772, 1020, opts).reason
        , "bad-work-area", "工作区宽为 0")
    T_Same(ZoneMath.FromAux(work, 0, 1020, opts).reason
        , "bad-aux-size", "辅助区宽为 0")
    T_Same(ZoneMath.FromAux(work, 772, 0, opts).reason
        , "bad-aux-size", "辅助区高为 0")
    T_Same(ZoneMath.FromAux(work, 772, 1020
        , {right: 15, gap: 6, margin: 10, minWorkW: 320, minAuxW: 120, minAuxH: 80}).reason
        , "bad-opts", "缺 minRecordH")
    T_Same(ZoneMath.FromAux(work, 772, 1020
        , {right: 15, gap: 6, margin: -1, minWorkW: 320, minRecordH: 450, minAuxW: 120, minAuxH: 80}).reason
        , "bad-opts", "margin 为负数")
}
