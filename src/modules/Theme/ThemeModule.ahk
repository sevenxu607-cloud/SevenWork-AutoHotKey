#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  ThemeModule —— 外观（主题参数的全局调节入口）
; ═══════════════════════════════════════════════════════════════════════════
; 它**不持有主题**：运行期的事实源仍是 WorkBench\Services\ThemeService，
; 所有窗口也都从那里取色板。本模块只提供「让用户改全局外观参数」的入口，
; 参数落到 [Appearance]，由 ThemeService 读色板时合并进去。
;
; 为什么这么拆（.clinerules/02 的依赖方向）：
;   · 主题是平台能力，不是某个业务模块的私产 —— **删掉本模块，所有窗口照样
;     上色**，只是少了一个调节入口；
;   · 反过来，如果让 ThemeService 去调本模块，就是 Service → Module 的反向依赖。
;
; 本页只放**全局**参数：改一次，所有窗口一起变。
; 窗口之间的差异（笔记正文更安静、提示词库更紧凑）属于「窗口类型」，
; 是主题自带的分型默认值，不交给用户逐窗调 —— 那是另一层，将来单独做。
;
; 没有热键：外观是从 Alt+S 面板里调的，不值得占一个全局键。
; ═══════════════════════════════════════════════════════════════════════════

class ThemeModule {
    static Id := "Theme"
    static Name := "外观"

    ; 不建窗口、不订阅事件 —— 参数怎么生效由 ThemeService 负责。
    static Init() {
    }

    static GetHotkeys() {
        return []
    }

    static GetMetadata() {
        ; order 5：排在「平台」(0) 之后、各业务模块之前 ——
        ; 外观是全局的，用户找它时通常先往上翻。
        return {name: this.Name, desc: "全局外观参数 · 在面板里调", order: 5, hotkeys: []}
    }

    ; ─── 设置页 ────────────────────────────────────────────────────────
    ; 平台只认 {label, kind, value}（外加可选的 options / min / max / step / unit），
    ; 不认识任何业务名词 —— 这里的「材质浓度」「界面密度」都是外观自己的词。
    static GetSettingsSpec() {
        ov := ThemeService.Overrides()
        return {
            title: "外观",
            hint: "这四项是全局的：改完所有窗口一起变，窗口停在哪一页、输入框里"
                . "已经敲的字都不受影响。"
                . "`n只有「笔记正文更安静」这类窗口差异不在这里调 —— 那是窗口类型的默认值。",
            fields: [
                {key: "Material", label: "材质浓度", kind: "select"
                    , value: ov.material, options: ["薄透", "适中", "浓郁"]}
                , {key: "Radius", label: "板面圆角", kind: "range"
                    , value: "" . ov.radius, min: "8", max: "20", step: "1", unit: "px"}
                , {key: "Motion", label: "动效", kind: "select"
                    , value: ov.motion, options: ["标准", "轻量", "关闭"]}
                , {key: "Density", label: "界面密度", kind: "select"
                    , value: ov.density, options: ["标准", "紧凑"]}
            ],
            apply: (values) => ThemeModule._Apply(values)
        }
    }

    ; 值按 fields 声明顺序送来（前端永远补满平台要求的槽位，多出来的忽略）。
    static _Apply(values) {
        if (values.Length < 4)
            return false

        ; ⚠ 一律当字符串写：ThemeService.Overrides() 读回时会再校验一次。
        ;   这里是唯一的写入口，校验放读侧就不必两边各写一份。
        ConfigService.Write("Appearance", "Material", values[1])
        ConfigService.Write("Appearance", "Radius", "" . values[2])
        ConfigService.Write("Appearance", "Motion", values[3])
        ConfigService.Write("Appearance", "Density", values[4])

        ; 立刻广播：各窗口按新色板重绘，**不重建**（窗口停在哪页、输入框里的字都在）。
        ; 主题本身没变、变的是外观 —— 复用 Theme.Changed 而不是新开一条：
        ;   订阅者要做的都是同一件事，「按当前 Palette 重刷一遍」。
        p := ThemeService.Palette()
        EventBus.Emit("Theme.Changed"
            , {name: p.name, idx: ThemeService.GetCurrent(), dark: p.dark})
        return true
    }
}
