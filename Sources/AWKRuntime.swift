// AWKRuntime.swift
// Runtime value type and global environment for the AWK interpreter.
// Corresponds to tran.c, the Cell/Array infrastructure from awk.h,
// and the I/O management from run.c.

import Foundation

// MARK: - Errors and Signals

struct AWKRuntimeError: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { description = msg }
}

/// Swift equivalent of the C setjmp/longjmp control-flow mechanism.
/// Each case is thrown and caught by the appropriate executor level.
enum AWKSignal: Error {
    case break_
    case continue_
    case next
    case nextFile
    case return_(AWKCell)
    case exit_(Int32)
}

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

    static func number(_ n: Double) -> AWKCell {
        let c = AWKCell(); c.numVal = n + 0; c.hasNum = true; return c
    }
    static func string(_ s: String) -> AWKCell {
        let c = AWKCell(); c.strVal = s; c.hasStr = true; return c
    }
    static func both(_ n: Double, _ s: String) -> AWKCell {
        let c = AWKCell()
        c.numVal = n + 0; c.strVal = s; c.hasNum = true; c.hasStr = true
        return c
    }
    static func newArray() -> AWKCell {
        let c = AWKCell(); c.array = [:]; return c
    }

    // Get numeric value; lazily parses string if no numeric value is cached.
    func getNum() -> Double {
        if hasNum { return numVal }
        if hasStr { return AWKRuntime.parseNum(strVal) }
        return 0.0
    }

    // Get string value using the supplied format (CONVFMT or OFMT).
    func getStr(fmt: String = "%.6g") -> String {
        if hasStr { return strVal }
        if hasNum { return AWKRuntime.numToStr(numVal, fmt: fmt) }
        return ""
    }

    // Assign a numeric value (invalidates the cached string).
    func setNum(_ n: Double) {
        numVal = n + 0   // normalize -0 → +0
        hasNum = true
        hasStr = false
        strVal = ""
    }

    // Assign a string value (invalidates the cached numeric value).
    func setStr(_ s: String) {
        strVal = s
        hasStr = true
        hasNum = false
        numVal = 0.0
    }

    // Assign both numeric and string simultaneously (e.g. after a getline).
    func setBoth(_ n: Double, _ s: String) {
        numVal = n + 0; strVal = s; hasNum = true; hasStr = true
    }

    // Copy scalar state from another cell (does NOT deep-copy arrays).
    func copyScalarFrom(_ other: AWKCell) {
        numVal = other.numVal; strVal = other.strVal
        hasNum = other.hasNum; hasStr = other.hasStr
    }

    /// AWK truth: non-zero number, or non-empty string that isn't "0".
    var isTrue: Bool {
        if isArray { return true }
        if hasNum  { return numVal != 0.0 }
        if hasStr  { return !strVal.isEmpty && strVal != "0" }
        return false
    }
}

// MARK: - AWK Runtime Utilities

enum AWKRuntime {

    // MARK: Number parsing — mirrors C's atof with leading-junk-stop behaviour.
    static func parseNum(_ s: String) -> Double {
        var s = s
        while let c = s.first, c == " " || c == "\t" || c == "\n" || c == "\r" { s.removeFirst() }
        if s.isEmpty { return 0.0 }
        // Fast path
        if let d = Double(s) { return d }
        // Longest valid numeric prefix
        var i = s.startIndex
        if s[i] == "+" || s[i] == "-" { s.formIndex(after: &i) }
        var hasDot = false, hasExp = false, hasDigit = false
        while i < s.endIndex {
            let c = s[i]
            if c >= "0" && c <= "9" { hasDigit = true; s.formIndex(after: &i) }
            else if c == "." && !hasDot && !hasExp { hasDot = true; s.formIndex(after: &i) }
            else if (c == "e" || c == "E") && !hasExp && hasDigit {
                hasExp = true
                s.formIndex(after: &i)
                if i < s.endIndex && (s[i] == "+" || s[i] == "-") { s.formIndex(after: &i) }
            } else { break }
        }
        return Double(String(s[s.startIndex..<i])) ?? 0.0
    }

    // Number → string using printf format.  Integers use %.30g for exact output.
    static func numToStr(_ n: Double, fmt: String) -> String {
        guard n.isFinite else {
            return n.isNaN ? "nan" : (n > 0 ? "inf" : "-inf")
        }
        var intPart = 0.0
        if modf(n, &intPart) == 0.0 {
            return String(format: "%.30g", n)
        }
        return String(format: fmt, n)
    }

    // Returns true when the string is entirely numeric (per POSIX is_number).
    static func isNumber(_ s: String) -> Bool {
        var s = s.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return false }
        if s.first == "+" || s.first == "-" { s.removeFirst() }
        var hasDot = false, hasDigit = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c >= "0" && c <= "9" { hasDigit = true }
            else if c == "." && !hasDot { hasDot = true }
            else if (c == "e" || c == "E") && hasDigit {
                s.formIndex(after: &i)
                if i < s.endIndex && (s[i] == "+" || s[i] == "-") { s.formIndex(after: &i) }
                var hasExpDigit = false
                while i < s.endIndex, s[i] >= "0" && s[i] <= "9" {
                    hasExpDigit = true; s.formIndex(after: &i)
                }
                return hasExpDigit && i == s.endIndex
            } else { return false }
            s.formIndex(after: &i)
        }
        return hasDigit
    }

    // Compare two cells: negative / zero / positive.
    // Numeric comparison when both have numeric values; string comparison otherwise.
    static func compare(_ x: AWKCell, _ y: AWKCell, convfmt: String = "%.6g") -> Int {
        if x.hasNum && y.hasNum {
            let d = x.numVal - y.numVal
            return d < 0 ? -1 : (d > 0 ? 1 : 0)
        }
        let xs = x.getStr(fmt: convfmt), ys = y.getStr(fmt: convfmt)
        return xs < ys ? -1 : (xs > ys ? 1 : 0)
    }

    // Compile an AWK regex and match against a string. Returns match range or nil.
    static func match(pattern: String, in str: String) throws -> Range<String.Index>? {
        let re = try makeRegex(pattern)
        return re.firstMatch(in: str, range: NSRange(str.startIndex..., in: str))
            .flatMap { Range($0.range, in: str) }
    }

    // Like match() but returns the range of the full match (for RSTART/RLENGTH).
    static func pmatch(pattern: String, in str: String) throws
        -> (range: Range<String.Index>, nsRange: NSRange)?
    {
        let re = try makeRegex(pattern)
        let ns = str as NSString
        let nsRange = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: str, range: nsRange) else { return nil }
        guard let r = Range(m.range, in: str) else { return nil }
        return (r, m.range)
    }

    static func makeRegex(_ pattern: String) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            throw AWKRuntimeError("invalid regex /\(pattern)/: \(error.localizedDescription)")
        }
    }

    // Apply the AWK sub/gsub replacement string (& = matched text, \& = literal &, etc.)
    static func applyReplacement(_ repl: String, matched: Substring) -> String {
        var result = ""
        var i = repl.startIndex
        while i < repl.endIndex {
            let c = repl[i]
            if c == "\\" {
                let next = repl.index(after: i)
                if next >= repl.endIndex { result.append("\\"); break }
                switch repl[next] {
                case "&":
                    result.append("&")
                    i = repl.index(after: next)
                case "\\":
                    let next2 = repl.index(after: next)
                    if next2 < repl.endIndex && repl[next2] == "\\" {
                        let next3 = repl.index(after: next2)
                        if next3 < repl.endIndex && repl[next3] == "&" {
                            // \\\& → \&
                            result += "\\&"
                            i = repl.index(after: next3)
                        } else {
                            result += "\\\\"
                            i = next2
                        }
                    } else if next2 < repl.endIndex && repl[next2] == "&" {
                        // \\& → \ + matched
                        result.append("\\")
                        result += matched
                        i = repl.index(after: next2)
                    } else {
                        result += "\\\\"
                        i = next2
                    }
                default:
                    result.append("\\")
                    result.append(repl[next])
                    i = repl.index(after: next)
                }
            } else if c == "&" {
                result += matched
                i = repl.index(after: i)
            } else {
                result.append(c)
                i = repl.index(after: i)
            }
        }
        return result
    }
}

// MARK: - I/O

enum AWKFileMode { case read, write, append, outputPipe, inputPipe }

final class AWKFile {
    let name: String
    let mode: AWKFileMode
    var handle: FileHandle
    var process: Process? = nil
    var buffer: String = ""     // unread input buffer for line-at-a-time reading

    init(name: String, mode: AWKFileMode, handle: FileHandle, process: Process? = nil) {
        self.name = name; self.mode = mode
        self.handle = handle; self.process = process
    }

    // Read the next record delimited by `rs`. Returns nil at EOF.
    func readRecord(rs: String) -> String? {
        // Refill buffer from handle
        func refill() {
            let data = handle.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            buffer += s
        }

        refill()
        if buffer.isEmpty { return nil }

        if rs.isEmpty {
            // RS="" → paragraph mode: split on blank lines
            while buffer.hasPrefix("\n") { buffer.removeFirst() }
            if buffer.isEmpty { return nil }
            if let range = buffer.range(of: "\n\n") {
                let record = String(buffer[buffer.startIndex..<range.lowerBound])
                buffer.removeSubrange(buffer.startIndex...range.upperBound)
                return record
            }
            let record = buffer; buffer = ""; return record
        }

        let sep: Character = rs.count == 1 ? Character(rs) : "\n"
        if let idx = buffer.firstIndex(of: sep) {
            let record = String(buffer[buffer.startIndex..<idx])
            buffer.removeSubrange(buffer.startIndex...idx)
            return record
        }
        // EOF: return remaining buffer
        let record = buffer; buffer = ""; return record
    }

    func write(_ s: String) throws {
        guard let data = s.data(using: .utf8) else { return }
        handle.write(data)
    }

    func close() {
        if let proc = process { proc.terminate(); proc.waitUntilExit() }
        if handle != .standardInput && handle != .standardOutput && handle != .standardError {
            try? handle.close()
        }
    }
}

// MARK: - AWK Environment

/// All mutable global state for one AWK execution: variables, fields, I/O.
/// Corresponds to the global variables in tran.c and the file-table in run.c.
final class AWKEnvironment {

    // MARK: Built-in variables
    var FS: String      = " "
    var RS: String      = "\n"
    var OFS: String     = " "
    var ORS: String     = "\n"
    var OFMT: String    = "%.6g"
    var CONVFMT: String = "%.6g"
    var NR: Double      = 0
    var FNR: Double     = 0
    var NF: Int         = 0
    var FILENAME: String = ""
    var SUBSEP: String  = "\u{1C}"   // ASCII 0x1C (\034)
    var RSTART: Double  = 0
    var RLENGTH: Double = -1

    // MARK: Record and fields
    var record: String = ""      // $0
    var fields: [String] = []    // $1, $2, ... (0-based internally: fields[0] = $1)
    var fieldsDirty = false      // need to re-split $0 into fields
    var recordDirty = false      // need to rebuild $0 from fields

    // MARK: Symbol tables
    var globals: [String: AWKCell] = [:]

    // MARK: Function registry (populated before execution)
    var functions: [String: FunctionDefinition] = [:]

    // MARK: Range-pattern state
    var pairstack: [Bool] = []

    // MARK: I/O
    var openFiles: [AWKFile] = []
    var inputFiles: [AWKFile] = []   // queue of input files/stdin

    // MARK: Misc runtime state
    var srandSeed: Double = 1.0
    var exitCode: Int32 = 0
    var environ: [String: String] = ProcessInfo.processInfo.environment
    var argv: [String] = []

    // MARK: - Symbol table

    func global(_ name: String) -> AWKCell {
        if let c = globals[name] { return c }
        let c = AWKCell(); globals[name] = c; return c
    }

    // MARK: - Field management

    func getField(_ n: Int) -> String {
        ensureFields()
        if n == 0 { ensureRecord(); return record }
        guard n >= 1 && n <= fields.count else { return "" }
        return fields[n - 1]
    }

    func setField(_ n: Int, _ val: String) {
        if n == 0 {
            record = val; fieldsDirty = true; recordDirty = false; return
        }
        ensureFields()
        while fields.count < n { fields.append("") }
        fields[n - 1] = val
        if n > NF { NF = n }
        recordDirty = true
    }

    func setNF(_ n: Int) {
        ensureFields()
        if n < fields.count { fields = Array(fields.prefix(n)) }
        while fields.count < n { fields.append("") }
        NF = n
        recordDirty = true
    }

    func ensureRecord() {
        if recordDirty { record = fields.joined(separator: OFS); recordDirty = false }
    }

    func ensureFields() {
        if fieldsDirty { splitRecord(); fieldsDirty = false }
    }

    private func splitRecord() {
        let s = record
        if FS == " " {
            fields = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        } else if FS.count == 1 {
            let sep = Character(FS)
            fields = s.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
        } else if FS.isEmpty {
            fields = s.map { String($0) }
        } else {
            guard let re = try? NSRegularExpression(pattern: FS) else { fields = [s]; NF = 1; return }
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            var parts: [String] = []
            var last = 0
            for m in re.matches(in: s, range: range) {
                parts.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
                last = m.range.location + m.range.length
            }
            parts.append(ns.substring(from: last))
            fields = parts
        }
        NF = fields.count
    }

    // MARK: - I/O management

    func fileFor(name: String, mode: AWKFileMode) throws -> AWKFile {
        for f in openFiles where f.name == name &&
            (f.mode == mode || (mode == .write && f.mode == .append) ||
             (mode == .append && f.mode == .write)) { return f }

        let f: AWKFile
        switch mode {
        case .write:
            FileManager.default.createFile(atPath: name, contents: nil)
            guard let fh = FileHandle(forWritingAtPath: name) else {
                throw AWKRuntimeError("cannot open '\(name)' for writing")
            }
            try fh.truncate(atOffset: 0)
            f = AWKFile(name: name, mode: mode, handle: fh)
        case .append:
            if !FileManager.default.fileExists(atPath: name) {
                FileManager.default.createFile(atPath: name, contents: nil)
            }
            guard let fh = FileHandle(forWritingAtPath: name) else {
                throw AWKRuntimeError("cannot open '\(name)' for append")
            }
            fh.seekToEndOfFile()
            f = AWKFile(name: name, mode: mode, handle: fh)
        case .read:
            let fh = name == "-" ? FileHandle.standardInput
                : FileHandle(forReadingAtPath: name)
            guard let fh else { throw AWKRuntimeError("cannot open '\(name)' for reading") }
            f = AWKFile(name: name, mode: mode, handle: fh)
        case .outputPipe:
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = ["-c", name]
            let pipe = Pipe()
            proc.standardInput = pipe
            try proc.run()
            f = AWKFile(name: name, mode: mode, handle: pipe.fileHandleForWriting, process: proc)
        case .inputPipe:
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = ["-c", name]
            let pipe = Pipe()
            proc.standardOutput = pipe
            try proc.run()
            f = AWKFile(name: name, mode: mode, handle: pipe.fileHandleForReading, process: proc)
        }
        openFiles.append(f)
        return f
    }

    func closeFile(name: String) {
        if let i = openFiles.firstIndex(where: { $0.name == name }) {
            openFiles[i].close(); openFiles.remove(at: i)
        }
    }

    func closeAll() {
        for f in openFiles { f.close() }
        openFiles = []
    }

    func flushAll() {
        for f in openFiles where f.mode == .write || f.mode == .append || f.mode == .outputPipe {
            try? f.handle.synchronize()
        }
        try? FileHandle.standardOutput.synchronize()
    }

    // MARK: - Subscript key building (SUBSEP-joined multi-dimensional key)
    func subscriptKey(_ exprs: [String]) -> String {
        exprs.joined(separator: SUBSEP)
    }
}
