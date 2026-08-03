// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

import CMigration
import Foundation

// MARK: - AWK Environment

/// All mutable global state for one AWK execution: variables, fields, I/O.
/// Corresponds to the global variables in tran.c and the file-table in run.c.
extension awk.RuntimeVars {

    // MARK: Record and fields
/*    var record: String = ""      // $0
    var fields: [String] = []    // $1, $2, ... (0-based internally: fields[0] = $1)
    var fieldsDirty = false      // need to re-split $0 into fields
    var recordDirty = false      // need to rebuild $0 from fields

    // MARK: Range-pattern state
    var pairstack: [Bool] = []

    // MARK: I/O
    var openFiles: [AWKFile] = []
    var inputFiles: [AWKFile] = []   // queue of input files/stdin

    // MARK: Misc runtime state
    var srandSeed: Double = 1.0
    var exitCode: Int32 = 0
*/
  
    // MARK: - Field management

    // C: getfval(fldtab[n]) — tran.c
    func getField(_ n: Int) -> String {
        ensureFields()
      if n == 0 { ensureRecord(); return record! }
        guard n >= 1 && n <= fldtab.count else { return "" }
      return fldtab[n - 1].getsval()
    }

    // C: setsval(fldtab[n]) — tran.c
    func setField(_ n: Int, _ val: String) {
        if n == 0 {
            record = val; fieldsDirty = true; recordDirty = false; return
        }
        ensureFields()
        while fldtab.count < n { fldtab.append("") }
        fldtab[n - 1] = val
      if Double(n) > NF { NF = Double(n) }
        recordDirty = true
    }

    // C: setlastfld() + cleanfld() — lib.c
    func setNF(_ n: Int) {
        ensureFields()
        if n < fldtab.count { fldtab = Array(fldtab.prefix(n)) }
        while fldtab.count < n { fldtab.append("") }
        NF = n
        recordDirty = true
    }

    // C: recbld() — lib.c
    func ensureRecord() {
        if recordDirty { record = fldtab.joined(separator: OFS); recordDirty = false }
    }

    // C: fldbld() trigger — lib.c
    func ensureFields() {
        if fieldsDirty { splitRecord(); fieldsDirty = false }
    }

    // C: fldbld() body — lib.c
    private func splitRecord() {
        let s = record
        if FS == " " {
            fldtab = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        } else if FS.count == 1 {
            let sep = Character(FS)
            fldtab = s.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
        } else if FS.isEmpty {
            fldtab = s.map { String($0) }
        } else {
            guard let re = try? NSRegularExpression(pattern: FS) else { fldtab = [s]; NF = 1; return }
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            var parts: [String] = []
            var last = 0
            for m in re.matches(in: s, range: range) {
                parts.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
                last = m.range.location + m.range.length
            }
            parts.append(ns.substring(from: last))
            fldtab = parts
        }
        NF = fldtab.count
    }

    // MARK: - I/O management

    // C: openfile() / redirect() — run.c
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

    // C: fclose() / pclose() inline — run.c
    func closeFile(name: String) {
        if let i = openFiles.firstIndex(where: { $0.name == name }) {
            openFiles[i].close(); openFiles.remove(at: i)
        }
    }

    // C: closeall() — run.c
    func closeAll() {
        for f in openFiles { f.close() }
        openFiles = []
    }

    // C: flush_all() — run.c
    func flushAll() {
        for f in openFiles where f.mode == .write || f.mode == .append || f.mode == .outputPipe {
            try? f.handle.synchronize()
        }
        try? FileHandle.standardOutput.synchronize()
    }

    // MARK: - Subscript key building (SUBSEP-joined multi-dimensional key)
    // C: SUBSEP-join in array() — run.c
    func subscriptKey(_ exprs: [String]) -> String {
        exprs.joined(separator: SUBSEP)
    }
}
