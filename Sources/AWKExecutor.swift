// AWKExecutor.swift
// AST-walking interpreter for AWK.
// Corresponds to run.c from one-true-awk, but operates on the Swift AST
// (AWKProgram / Statement / Expression) rather than the C Node* tree.

import CMigration
import Darwin
import Foundation

// MARK: - Call frame

// MARK: - AWK Executor

extension RuntimeState {


  // MARK: - Main entry point

  /// Run a parsed AWK program over the provided input files (or stdin if empty).
  // C: run() + getrec() loop — run.c / lib.c
  func run(_ program: AWKProgram, inputPaths: [String] = []) throws {
    // Populate function table
    for fn in program.functions { functions[fn.name] = fn }

    // Set up ARGV / ARGC
    let argc = self.options.args.count + 1
    var argv : [Cell] = [Cell(string: CommandLine.arguments[0])]
    for (_, a) in options.args.enumerated() {
      argv.append(Cell(string: a))
    }
    symtab["ARGV"] = Cell(array: argv, named: "ARGV")
    symtab["ARGC"] = Cell(number: argc, named: "ARGC")


    // Range-pattern pairstack
    pairstack = Array(repeating: false, count: program.rules.count)

    // --- BEGIN blocks ---
    do {
      for stmts in program.beginRules {
        try execBlock(stmts)
      }
    } catch AWKSignal.exit_(let code) {
      exitCode = code
      try runEndBlocks(program)
      return
    }

    // --- Per-record body ---
    if !program.rules.isEmpty || !program.endRules.isEmpty {
      let paths = inputPaths.isEmpty ? ["-"] : inputPaths
      outer: for path in paths {
        let file: AWKFile
        if path == "-" {
          file = AWKFile(name: "-", mode: .read, handle: .standardInput)
        } else {
          guard let fh = FileHandle(forReadingAtPath: path) else {
            fputs("awk: can't open \(path)\n", stderr)
            continue
          }
          file = AWKFile(name: path, mode: .read, handle: fh)
        }
        FILENAME = path
        FNR = 0

        while let rec = file.readRecord(rs: RS) {
          NR += 1; FNR += 1
          record = rec

          for (idx, rule) in program.rules.enumerated() {
            do {
              if try matchesPattern(rule.pattern, ruleIndex: idx) {
                if rule.body.isEmpty {
                  // no body → print $0
                  try print_([.field(.number(0))], dest: nil)
                } else {
                  try execBlock(rule.body)
                }
              }
            } catch AWKSignal.next { continue outer }
            catch AWKSignal.nextFile { break }
            catch AWKSignal.exit_(let code) {
              exitCode = code
              file.close()
              try runEndBlocks(program)
              return
            }
          }
        }
        file.close()
      }
    }

    // --- END blocks ---
    try runEndBlocks(program)
  }

  // C: program() END-block handling — run.c
  func runEndBlocks(_ program: AWKProgram) throws {
    inEndBlock = true
    do {
      for stmts in program.endRules {
        try execBlock(stmts)
      }
    } catch AWKSignal.exit_(let code) {
      exitCode = code
    }
    inEndBlock = false
    closeAll()
  }

  // MARK: - Pattern matching

  // C: pastat() + dopa2() — run.c
  func matchesPattern(_ pattern: PatternKind, ruleIndex: Int) throws -> Bool {
    switch pattern {
      case .always:
        return true
      case .expression(let e):
        return try eval(e).isTrue
      case .range(let p1, let p2):
        if pairstack[ruleIndex] {
          let done = try eval(p2).isTrue
          if done { pairstack[ruleIndex] = false }
          return true
        } else {
          let start = try eval(p1).isTrue
          if start { pairstack[ruleIndex] = true }
          return start
        }
    }
  }




  // MARK: - LValue resolution (returns the cell itself for mutation)

  // C: field() / array() / indirect() — run.c
  func evalLValue(_ lv: LValue) throws -> Cell {
    switch lv {
      case .variable(let name):
        return resolveVar(name)

      case .argument(let i):
        guard let frame = callStack.last, i < frame.cells.count else {
          throw AWKRuntimeError("function argument \(i) out of range")
        }
        return frame.cells[i]

      case .varnf:
        // Assign to NF specially through a proxy cell that triggers setNF on write.
        // For simplicity, we handle NF assignment in execAssign.
        let c = symtab["NF"]!; return c

      case .field(let e):
        // Field lvalue — we can't return a reference to an element of env.fields.
        // Instead, return a proxy: a cell whose value changes are applied via setField.
        // We wrap this in a FieldProxy approach: return a cell and post-assign it.
        // This is handled per-case in execAssign and incr/decr.
        // For the incr/decr case, we need the actual stored cell; use a field cell.
        let n = Int(try eval(e).getfval())
        return makeFieldCell(n)

      case .element(let name, let keys):
        return try resolveElement(name: name, keys: keys)

      case .indirect(let e):
        let n = Int(try eval(e).getfval())
        return makeFieldCell(n)
    }
  }

  // MARK: - Variable / element resolution

  // C: setsymtab() + lookup() — tran.c
  func resolveVar(_ name: String) -> Cell {
    // Check built-in variables first
    // Check current call frame
    if let frame = callStack.last {
      if let i = frame.paramNames.firstIndex(of: name) {
        return frame.cells[i]
      }
    }
    // FIXME: does this give an error if the name is not found?
    return symtab[name] ?? Cell()
  }

  // C: (no direct equivalent; lazy sync of built-in variable Cell mirrors)
  func syncedBuiltin(_ name: String,
                     get: () -> Cell) -> Cell {
    if let c = symtab[name] { return c }
    let c = get(); symtab[name] = c; return c
  }

  // C: array() — run.c
  func resolveElement(name: String, keys: [Expression]) throws -> Cell {
    let parts = try keys.map { try eval($0).getsval(fmt: CONVFMT) }
    let key = subscriptKey(parts)
    var arr = resolveVar(name)
    if case .dict = arr.val {}
    else { arr.val = .dict([:]) }
    if case .dict(var ee) = arr.val {
      if let existing = ee[key] { return existing }
      let c = Cell()
      ee[key] = c
      arr.val = .dict(ee)
      return c
    }
    // should never happen
    return Cell()
  }

    // MARK: - Field proxy cells

    /// A pseudo-cell backed by field slot n.  Changes are written back via setField.
//    var fieldCells: [Int: Cell] = [:]

    // C: fieldadr() — lib.c
    func makeFieldCell(_ n: Int) -> Cell {
//        if let existing = fieldCells[n] { return existing }
        let s = getField(n)
      let c = Cell(field: s, at: n)
      // FIXME: cache the num-equivalent value if a num
//        if AWKRuntime.isNumber(s) { c.numVal = AWKRuntime.parseNum(s); c.hasNum = true }
//        fieldCells[n] = c
        return c
    }

  /*
    // C: (no direct equivalent; field proxy write-back)
    func flushFieldCells() {
        for (n, c) in fieldCells {
            setField(n, c.getsval(fmt: CONVFMT))
        }
        fieldCells = [:]
    }
*/

    // MARK: - Assignment

    // C: assign() — run.c
    func execAssign(op: AssignOp, lv: LValue, rhs: Expression) throws -> Cell {
        let rhsVal = try eval(rhs)

        // NF assignment requires special handling
      if case .varnf = lv {
        let n = Int(rhsVal.getfval())
        setNF(n)
        
        return Cell(number: n)
      }

        // Field assignment writes through to env.fields / env.record
        if case .field(let fe) = lv {
            let n = Int(try eval(fe).getfval())
          let cur = Cell(number: getField(n) == "" ? 0 : 0)
            let curStr = getField(n)
            let curNum = AWKRuntime.parseNum(curStr)
            let newVal = applyOp(op, lhsNum: curNum, lhsStr: curStr, rhs: rhsVal)
            setField(n, newVal.getsval(fmt: CONVFMT))
          // FIXME: why the reference to donefld here?
          if n == 0 { donefld = false }
            _ = cur  // suppress warning
            return newVal
        }

        var target = try evalLValue(lv)
        let result = applyOp(op, lhsNum: target.getfval(), lhsStr: target.getsval(fmt: CONVFMT), rhs: rhsVal)

        // Write back to built-in variables
       // if case .variable(let name) = lv { writeback(name: name, cell: result) }

        // target.copyScalarFrom(result)
      // FIXME: if Cell becomes a class, need to make a copy
      target = result
        return target
    }

    // C: assign() operator switch — run.c
    func applyOp(_ op: AssignOp, lhsNum: Double, lhsStr: String, rhs: Cell) -> Cell {
        switch op {
        case .set:    return rhs
          case .addSet: return Cell(number: lhsNum + rhs.getfval())
          case .subSet: return Cell(number: lhsNum - rhs.getfval())
          case .mulSet: return Cell(number: lhsNum * rhs.getfval())
        case .divSet:
            let d = rhs.getfval()
            return Cell(number: d == 0 ? 0 : lhsNum / d)   // real code throws
        case .modSet:
            let d = rhs.getfval()
            var i = 0.0; modf(lhsNum / d, &i)
            return Cell(number: lhsNum - d * i)
        case .powSet:
            return Cell(number: ipow(lhsNum, rhs.getfval()))
        }
    }

    // MARK: - Power helper (matches C ipow for integer exponents)

    // C: ipow() — run.c
    func ipow(_ x: Double, _ exp: Double) -> Double {
        var intPart = 0.0
        if exp >= 0 && modf(exp, &intPart) == 0.0 {
            var result = 1.0; var n = Int(exp); var base = x
            while n > 0 { if n & 1 == 1 { result *= base }; base *= base; n >>= 1 }
            return result
        }
        return pow(x, exp)
    }

    // MARK: - Regex helper (extracts pattern string from an expression)

    // C: (no direct equivalent; extracts pattern string from an expression node)
    func regexPattern(_ e: Expression) throws -> String {
        if case .regexMatch(let s) = e { return s }
        return try eval(e).getsval(fmt: CONVFMT)
    }

    // MARK: - Print statement

    // C: printstat() — run.c
    func execPrint(kind: PrintKind, args: [Expression], dest: PrintDest?) throws {
        let output: AWKFile
        switch dest {
        case .none:
            output = AWKFile(name: "/dev/stdout", mode: .write, handle: .standardOutput)
        case .redirect(let e):
            let path = try eval(e).getsval(fmt: CONVFMT)
            output = try fileFor(name: path, mode: .write)
        case .append(let e):
            let path = try eval(e).getsval(fmt: CONVFMT)
            output = try fileFor(name: path, mode: .append)
        case .pipe(let e):
            let cmd = try eval(e).getsval(fmt: CONVFMT)
            output = try fileFor(name: cmd, mode: .outputPipe)
        }

        switch kind {
        case .print:
            try print_(args, dest: dest, to: output)
        case .printf:
            guard !args.isEmpty else { return }
            let fmtStr = try eval(args[0]).getsval(fmt: CONVFMT)
            let result = try format(fmtStr, args: Array(args.dropFirst()))
            try output.write(result)
        }
    }

    // C: printstat() output loop — run.c
    func print_(_ args: [Expression], dest: PrintDest?, to output: AWKFile? = nil) throws {
        let out = output ?? AWKFile(name: "/dev/stdout", mode: .write, handle: .standardOutput)
        if args.isEmpty {
            ensureRecord()
            try out.write(record! + ORS)
            return
        }
        var first = true
        for arg in args {
            if !first { try out.write(OFS) }
            let val = try eval(arg)
            try out.write(val.getsval(fmt: OFMT))
            first = false
        }
        try out.write(ORS)
    }

    // MARK: - Delete statement

    // C: awkdelete() — run.c
    func execDelete(_ lv: LValue) throws {
        switch lv {
        case .variable(let name):
            var c = resolveVar(name)
            // FIXME: should be nil rather than .sval
            c.val = .sval("")
//            c.array = nil; c.hasNum = false; c.hasStr = false; c.strVal = ""; c.numVal = 0
        case .element(let name, let keys):
            let parts = try keys.map { try eval($0).getsval(fmt: CONVFMT) }
            let key = subscriptKey(parts)
            let ee = resolveVar(name)
            if case .dict(var aa) = ee.val {
              aa.removeValue(forKey: key)
              // FIXME: aa has to be stored back?
            }
        default:
            throw AWKRuntimeError("delete requires a variable or array element")
        }
    }

    // MARK: - User-defined function call

    // C: call() — run.c
    func execUserCall(name: String, argExprs: [Expression]) throws -> Cell {
        guard let fn = functions[name] else {
            throw AWKRuntimeError("calling undefined function '\(name)'")
        }
        // Evaluate actual arguments
        var cells: [Cell] = []
        for argExpr in argExprs {
            let c = try eval(argExpr)
          if case .arr(var cc) = c.val {
                cells.append(c)   // arrays: pass by reference
            } else {
              // FIXME: this works because Cells are structs, but if classes, need to be copied
              cells.append(c) // let copy = Cell(); copy.copyScalarFrom(c); cells.append(copy)
            }
        }
        // Pad with empty cells for any unspecified parameters
        while cells.count < fn.params.count { cells.append(Cell()) }
        // Extra locals beyond defined params
        // (one-true-awk uses extra params as local variables)

        let frame = CallFrame(funcName: name, paramNames: fn.params, cells: cells)
      callStack.append(frame)
      defer { callStack.removeLast() }

        do {
            try execBlock(fn.body)
        } catch AWKSignal.`return`(let val) {
            return val
        }
      return callStack.last?.retval ?? Cell()
    }

    // MARK: - Builtin function call

    // C: bltin() — run.c
    func execBuiltin(id: AWKBuiltinID, args: [Expression]) throws -> Cell {
        switch id {
        case .length:
            if args.isEmpty {
                ensureFields()
              return Cell(number: record!.count)
            }
            let c = try eval(args[0])
            if case .arr(let arr) = c.val { return Cell(number: arr.count) }
            return Cell(number: c.getsval(fmt: CONVFMT).count)

        case .sqrt:
            return Cell(number: sqrt(try eval(args[0]).getfval()))

        case .exp:
            return Cell(number: exp(try eval(args[0]).getfval()))

        case .log:
            let v = try eval(args[0]).getfval()
            if v <= 0 { throw AWKRuntimeError("log: argument must be positive") }
            return Cell(number: log(v))

        case .int_:
            var intPart = 0.0; modf(try eval(args[0]).getfval(), &intPart)
            return Cell(number: intPart)

        case .system:
            let cmd = try eval(args[0]).getsval(fmt: CONVFMT)
            fflush(stdout)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = ["-c", cmd]
            let code: Int
            do { try proc.run(); proc.waitUntilExit(); code = Int(proc.terminationStatus) }
            catch { code = -1 }
            return Cell(number: code)

        case .rand:
            return Cell(number: Double(arc4random()) / Double(UInt32.max) + 1)

        case .srand:
            let old = srand_seed
            let seed: Double
            if args.isEmpty { seed = Double(DateTime().timeInterval) }
            else            { seed = try eval(args[0]).getfval() }
            srand_seed = UInt32(seed)
            srand48(Int(seed))
            return Cell(number: Double(old))

        case .sin:
            return Cell(number: sin(try eval(args[0]).getfval()))

        case .cos:
            return Cell(number: cos(try eval(args[0]).getfval()))

        case .atan2:
            let y = try eval(args[0]).getfval()
            let x = args.count > 1 ? try eval(args[1]).getfval() : 1.0
            return Cell(number: atan2(y, x))

        case .toupper:
            return Cell(string: try eval(args[0]).getsval(fmt: CONVFMT).uppercased())

        case .tolower:
            return Cell(string: try eval(args[0]).getsval(fmt: CONVFMT).lowercased())

        case .fflush:
            if args.isEmpty {
                flushAll()
            } else {
                let name = try eval(args[0]).getsval(fmt: CONVFMT)
                if name.isEmpty { flushAll() }
                else if let f = openFiles.first(where: { $0.name == name }) {
                    try? f.handle.synchronize()
                }
            }
            return Cell(number: 0)
        }
    }

    // MARK: - Getline

    // C: awkgetline() — run.c
    func execGetline(lv: LValue?) throws -> Cell {
        // Bare getline — read next record from current input (stdin)
        // For simplicity, read from stdin
        guard let line = readln(from: .standardInput) else {
          return Cell(number: -1)
        }
        if let lv {
            var c = try evalLValue(lv)
            c.setsval(line)
          // FIXME: need to save c back?
           //  if AWKRuntime.isNumber(line) { c.setBoth(AWKRuntime.parseNum(line), line) }
        } else {
            NR += 1; FNR += 1
            record = line
        }
      return Cell(number: 1)
    }

    // C: awkgetline() file-variant — run.c
    func readLineInto(lv: LValue?, from file: AWKFile, updates0: Bool) throws -> Cell {
      guard let line = file.readRecord(rs: RS) else { return Cell(number: 0) }
        if let lv {
            var c = try evalLValue(lv)
            c.setsval(line)
          // FIXME: the setsval should cache the number if it is a number
//            if AWKRuntime.isNumber(line) { c.setBoth(AWKRuntime.parseNum(line), line) }
        } else if updates0 {
            record = line
        }
      return Cell(number: 1)
    }

    // C: readrec() — lib.c
    func readln(from fh: FileHandle) -> String? {
        // Inefficient but simple: read byte-by-byte until RS
        var line = ""
        let sep: UInt8 = RS.first.map { $0.asciiValue ?? 10 } ?? 10
        while true {
            let data = fh.availableData
            guard !data.isEmpty else { return line.isEmpty ? nil : line }
            for byte in data {
                if byte == sep { return line }
                line.append(Character(Unicode.Scalar(byte)))
            }
        }
    }

    // MARK: - String operations

    // C: sub() — run.c
    func execSub(kind: SubKind, reExpr: Expression, replExpr: Expression, target: LValue) throws -> Cell {
      fatalError("not implemneted")
      // FIXME: put me back
      /*
        let pat = try regexPattern(reExpr)
        let repl = try eval(replExpr).getsval(fmt: CONVFMT)
        let targetCell = try evalLValue(target)
        let str = targetCell.getsval(fmt: CONVFMT)

        let re = try AWKRuntime.makeRegex(pat)
        let ns = str as NSString
        let range = NSRange(location: 0, length: ns.length)
        var count = 0

        switch kind {
        case .sub:
            if let m = re.firstMatch(in: str, range: range) {
                let matched = ns.substring(with: m.range)
                let replacement = AWKRuntime.applyReplacement(repl, matched: Substring(matched))
                let result = ns.replacingCharacters(in: m.range, with: replacement)
                targetCell.setsval(result)
                count = 1
            }
        case .gsub:
            var result = ""
            var lastEnd = str.startIndex
            for m in re.matches(in: str, range: range) {
                guard let r = Range(m.range, in: str) else { continue }
                result += str[lastEnd..<r.lowerBound]
                let matched = str[r]
                result += AWKRuntime.applyReplacement(repl, matched: matched)
                lastEnd = r.upperBound
                count += 1
            }
            result += str[lastEnd...]
            targetCell.setsval(result)
        }

        // Write back if this is a field lvalue
        if case .field(let fe) = target {
            let n = Int(try eval(fe).getfval())
            setField(n, targetCell.setsval(fmt: CONVFMT))
        }

      return Cell(number: count)
       */
    }

    // C: substr() — run.c
    func execSubstr(str: Expression, start: Expression, len: Expression?) throws -> Cell {
        let s = try eval(str).getsval(fmt: CONVFMT)
        let k = s.count
      if k == 0 { return Cell(string: "") }

        var m = Int(try eval(start).getfval())
        if m <= 0 { m = 1 }
      else if m > k + 1 { return Cell() }

        let n: Int
        if let lenExpr = len {
            n = max(0, min(Int(try eval(lenExpr).getfval()), k - m + 1))
        } else {
            n = k - m + 1
        }

        let startIdx = s.index(s.startIndex, offsetBy: m - 1, limitedBy: s.endIndex) ?? s.endIndex
        let endIdx   = s.index(startIdx, offsetBy: n, limitedBy: s.endIndex) ?? s.endIndex
      return Cell(string: String(s[startIdx..<endIdx]))
    }

    // C: split() — run.c
    func execSplit(str: Expression, arrName: String, sep: Expression?) throws -> Cell {
        let s = try eval(str).getsval(fmt: CONVFMT)
        var arr = resolveVar(arrName)

      var ee = [String:Cell]()

        let fs: String
        if let sepExpr = sep {
            if case .regexMatch(let pat) = sepExpr { fs = pat }
            else { fs = try eval(sepExpr).getsval(fmt: CONVFMT) }
        } else {
            fs = FS
        }

        let parts: [String]
        if fs == " " {
            parts = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        } else if fs.count == 1 && fs != "" {
            let sep = Character(fs)
            parts = s.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
        } else if fs.isEmpty {
            parts = s.map { String($0) }
        } else {
          fatalError("not implemented")
          // FIXME: put me back
          /*
          guard let re = try? NSRegularExpression(pattern: fs) else { return Cell(number: 0) }
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            var result: [String] = []
            var last = 0
            for m in re.matches(in: s, range: range) {
                result.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
                last = m.range.location + m.range.length
            }
            result.append(ns.substring(from: last))
            parts = result
          */
        }

        for (i, p) in parts.enumerated() {
            let key = String(i + 1)
          // FIXME: can cache the convertability of strings to numbers for performance
          let c = Cell(string: p)
            ee[key] = c
        }

      // FIXME: does this need to reset whatever the "resolved" value is?
      arr.val = .dict(ee)

      return Cell(number: parts.count)
    }

}
