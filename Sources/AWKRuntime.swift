// AWKRuntime.swift
// Runtime value type and global environment for the AWK interpreter.
// Corresponds to tran.c, the Cell/Array infrastructure from awk.h,
// and the I/O management from run.c.

import Foundation

extension awk {
  
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
    case `return` (Cell)
    case exit_(Int32)
  }
  
  
  // MARK: - AWK Runtime Utilities
  
  enum AWKRuntime {
    
    // MARK: Number parsing — mirrors C's atof with leading-junk-stop behaviour.
    // C: strtod() / atof() pattern used in getfval() — tran.c
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
    // C: get_str_val() — tran.c (the CONVFMT/OFMT formatting path)
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
    // C: is_number() — lib.c
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
    // C: comparison logic in relop() — run.c
    static func compare(_ x: Cell, _ y: Cell, convfmt: String = "%.6g") -> Int {
      if x.hasNum && y.hasNum {
        let d = x.getfval() - y.getfval()
        return d < 0 ? -1 : (d > 0 ? 1 : 0)
      }
      let xs = x.getsval(fmt: convfmt), ys = y.getsval(fmt: convfmt)
      return xs < ys ? -1 : (xs > ys ? 1 : 0)
    }
    
    // Compile an AWK regex and match against a string. Returns match range or nil.
    // C: matchop() — run.c  (regex execution via pmatch() — b.c)
    static func match(pattern: String, in str: String) throws -> Range<String.Index>? {
      let re = try makeRegex(pattern)
      return re.firstMatch(in: str, range: NSRange(str.startIndex..., in: str))
        .flatMap { Range($0.range, in: str) }
    }
    
    // Like match() but returns the range of the full match (for RSTART/RLENGTH).
    // C: pmatch() — b.c
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
    
    // C: makedfa() — b.c
    static func makeRegex(_ pattern: String) throws -> NSRegularExpression {
      do {
        return try NSRegularExpression(pattern: pattern, options: [])
      } catch {
        throw AWKRuntimeError("invalid regex /\(pattern)/: \(error.localizedDescription)")
      }
    }
    
    // Apply the AWK sub/gsub replacement string (& = matched text, \& = literal &, etc.)
    // C: backsub() — run.c
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
  
}
