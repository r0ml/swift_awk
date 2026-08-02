// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026



// MARK: - AWK Cell (runtime value)

/// Mutable AWK value — corresponds to Cell in awk.h.
/// Reference type so that arrays are shared and function arguments can be
/// passed by reference (arrays) vs. by value (scalars, which are copied on call).
final class AWKCell {
    var numVal: Double = 0.0
    var strVal: String = ""
    var hasNum: Bool = false
    var hasStr: Bool = false
    var isConst: Bool = false
    var array: [String: AWKCell]? = nil

    var isArray: Bool { array != nil }

    // C: gettemp() + setfval() — run.c / tran.c
    static func number(_ n: Double) -> AWKCell {
        let c = AWKCell(); c.numVal = n + 0; c.hasNum = true; return c
    }
    // C: gettemp() + setsval() — run.c / tran.c
    static func string(_ s: String) -> AWKCell {
        let c = AWKCell(); c.strVal = s; c.hasStr = true; return c
    }
    // C: (no direct equivalent; used when both numeric and string values are already known)
    static func both(_ n: Double, _ s: String) -> AWKCell {
        let c = AWKCell()
        c.numVal = n + 0; c.strVal = s; c.hasNum = true; c.hasStr = true
        return c
    }
    // C: (no direct equivalent; array cell allocation in tran.c)
    static func newArray() -> AWKCell {
        let c = AWKCell(); c.array = [:]; return c
    }

    // Get numeric value; lazily parses string if no numeric value is cached.
    // C: getfval() — tran.c
    func getNum() -> Double {
        if hasNum { return numVal }
        if hasStr { return AWKRuntime.parseNum(strVal) }
        return 0.0
    }

    // Get string value using the supplied format (CONVFMT or OFMT).
    // C: getsval() — tran.c
    func getStr(fmt: String = "%.6g") -> String {
        if hasStr { return strVal }
        if hasNum { return AWKRuntime.numToStr(numVal, fmt: fmt) }
        return ""
    }

    // Assign a numeric value (invalidates the cached string).
    // C: setfval() — tran.c
    func setNum(_ n: Double) {
        numVal = n + 0   // normalize -0 → +0
        hasNum = true
        hasStr = false
        strVal = ""
    }

    // Assign a string value (invalidates the cached numeric value).
    // C: setsval() — tran.c
    func setStr(_ s: String) {
        strVal = s
        hasStr = true
        hasNum = false
        numVal = 0.0
    }

    // Assign both numeric and string simultaneously (e.g. after a getline).
    // C: setsval() + setfval() combined — tran.c
    func setBoth(_ n: Double, _ s: String) {
        numVal = n + 0; strVal = s; hasNum = true; hasStr = true
    }

    // Copy scalar state from another cell (does NOT deep-copy arrays).
    // C: copycell() — run.c
    func copyScalarFrom(_ other: AWKCell) {
        numVal = other.numVal; strVal = other.strVal
        hasNum = other.hasNum; hasStr = other.hasStr
    }

    /// AWK truth: non-zero number, or non-empty string that isn't "0".
    // C: truth-value test in boolop() / relop() — run.c
    var isTrue: Bool {
        if isArray { return true }
        if hasNum  { return numVal != 0.0 }
        if hasStr  { return !strVal.isEmpty && strVal != "0" }
        return false
    }
}
