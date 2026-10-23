#Requires AutoHotkey v2.0
; WorkBench/Kernel/ConfigService.ahk
; Moved from SevenNote.ahk (Phase 1). Implementation unchanged.

class ConfigService {
    static _path := ""
    static _defaults := Map()
    ; 读缓存：section|key → 值。IniRead **没有内部缓存**，每次 Read 都是一次磁盘命中，
    ; 而 GetVault() 在保存链路上会被反复调用（FindMd / DefaultMdPath / AssetsDir 各一次）。
    ; 缓存只在进程内有效：Write 时同步、Init 时清空。
    static _cache := Map()

    static Init(path) {
        this._path := path
        this._cache := Map()   ; 换配置路径后旧值一律作废
    }

    static SetDefault(section, key, value) {
        this._defaults[section . "|" . key] := value
    }

    static Read(section, key) {
        if !this._path
            return ""
        ck := section . "|" . key
        if this._cache.Has(ck)
            return this._cache[ck]
        try {
            val := IniRead(this._path, section, key, "")
        } catch {
            val := ""
        }
        if (val = "") {
            if this._defaults.Has(ck)
                val := this._defaults[ck]
        }
        ; 空串同样入缓存：缺键也走默认值，没必要每次都问一遍磁盘。
        ; ⚠ 代价是**运行期手改 _config.ini 不再被读到** —— 改配置请重启程序。
        this._cache[ck] := val
        return val
    }

    static ReadInt(section, key, default := 0) {
        v := this.Read(section, key)
        if (v = "")
            return default
        try return Integer(v)
        catch
            return default
    }

    static Write(section, key, value) {
        if !this._path
            return false
        try {
            IniWrite(value, this._path, section, key)
            this._cache[section . "|" . key] := "" . value   ; 写后同步，免得紧接着读到旧值
            return true
        } catch {
            return false
        }
    }
}
