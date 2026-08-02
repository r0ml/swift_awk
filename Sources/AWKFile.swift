// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

import CMigration
import Foundation

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
    // C: readrec() — lib.c
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

    // C: (direct fwrite/fputs via FILE* in printstat() / redirect() — run.c)
    func write(_ s: String) throws {
        guard let data = s.data(using: .utf8) else { return }
        handle.write(data)
    }

    // C: fclose() / pclose() — run.c
    func close() {
        if let proc = process { proc.terminate(); proc.waitUntilExit() }
        if handle != .standardInput && handle != .standardOutput && handle != .standardError {
            try? handle.close()
        }
    }
}
