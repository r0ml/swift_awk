// AWKExecutor.swift
// AST-walking interpreter for AWK.
// Corresponds to run.c from one-true-awk, but operates on the Swift AST
// (AWKProgram / Statement / Expression) rather than the C Node* tree.

import Foundation

// MARK: - Call frame

private struct CallFrame {
    let funcName: String
    let paramNames: [String]   // formal parameter names
    var cells: [AWKCell]       // one cell per parameter + extra locals
    var retval: AWKCell = AWKCell()
}

// MARK: - AWK Executor

final class AWKExecutor {
    let env: AWKEnvironment
    private var callStack: [CallFrame] = []
    private var inEndBlock = false   // disables donefld update in END

    init(env: AWKEnvironment = AWKEnvironment()) {
        self.env = env
    }

    // MARK: - Main entry point

    /// Run a parsed AWK program over the provided input files (or stdin if empty).
    func run(_ program: AWKProgram, inputPaths: [String] = [], programArgs: [String] = []) throws {
        // Populate function table
        for fn in program.functions { env.functions[fn.name] = fn }

        // Set up ARGV / ARGC
        env.argv = programArgs
        let argc = programArgs.count
        let argvCell = AWKCell.newArray()
        for (i, a) in programArgs.enumerated() {
            let key = String(i)
            let cell = AWKRuntime.isNumber(a)
                ? AWKCell.both(AWKRuntime.parseNum(a), a)
                : AWKCell.string(a)
            argvCell.array![key] = cell
        }
        env.globals["ARGV"] = argvCell
        env.globals["ARGC"] = AWKCell.number(Double(argc))

        // ENVIRON
        let envCell = AWKCell.newArray()
        for (k, v) in env.environ { envCell.array![k] = AWKCell.string(v) }
        env.globals["ENVIRON"] = envCell

        // Range-pattern pairstack
        env.pairstack = Array(repeating: false, count: program.rules.count)

        // --- BEGIN blocks ---
        do {
            for stmts in program.beginRules {
                try execBlock(stmts)
            }
        } catch AWKSignal.exit_(let code) {
            env.exitCode = code
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
                env.FILENAME = path
                env.FNR = 0

                while let rec = file.readRecord(rs: env.RS) {
                    env.NR += 1; env.FNR += 1
                    env.record = rec; env.fieldsDirty = true; env.recordDirty = false

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
                            env.exitCode = code
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

    private func runEndBlocks(_ program: AWKProgram) throws {
        inEndBlock = true
        do {
            for stmts in program.endRules {
                try execBlock(stmts)
            }
        } catch AWKSignal.exit_(let code) {
            env.exitCode = code
        }
        inEndBlock = false
        env.closeAll()
    }

    // MARK: - Pattern matching

    private func matchesPattern(_ pattern: PatternKind, ruleIndex: Int) throws -> Bool {
        switch pattern {
        case .always:
            return true
        case .expression(let e):
            return try eval(e).isTrue
        case .range(let p1, let p2):
            if env.pairstack[ruleIndex] {
                let done = try eval(p2).isTrue
                if done { env.pairstack[ruleIndex] = false }
                return true
            } else {
                let start = try eval(p1).isTrue
                if start { env.pairstack[ruleIndex] = true }
                return start
            }
        }
    }

    // MARK: - Statement execution

    func execBlock(_ stmts: [Statement]) throws {
        for stmt in stmts { try exec(stmt) }
    }

    func exec(_ stmt: Statement) throws {
        switch stmt {
        case .empty: break

        case .expression(let e):
            _ = try eval(e)

        case .block(let stmts):
            try execBlock(stmts)

        case .print_(let kind, let args, let dest):
            try execPrint(kind: kind, args: args, dest: dest)

        case .delete_(let lv):
            try execDelete(lv)

        case .if_(let cond, let then, let else_):
            if try eval(cond).isTrue {
                try exec(then)
            } else if let e = else_ {
                try exec(e)
            }

        case .while_(let cond, let body):
            while try eval(cond).isTrue {
                do { try exec(body) }
                catch AWKSignal.break_ { return }
                catch AWKSignal.continue_ { /* next iteration */ }
            }

        case .doWhile(let body, let cond):
            repeat {
                do { try exec(body) }
                catch AWKSignal.break_ { return }
                catch AWKSignal.continue_ { /* next iteration */ }
            } while try eval(cond).isTrue

        case .for_(let init_, let cond, let incr, let body):
            if let i = init_ { try exec(i) }
            while true {
                if let c = cond, !(try eval(c).isTrue) { break }
                do { try exec(body) }
                catch AWKSignal.break_ { return }
                catch AWKSignal.continue_ { /* fall through to increment */ }
                if let inc = incr { try exec(inc) }
            }

        case .forIn(let varName, let arrName, let body):
            let arrCell = resolveVar(arrName)
            guard let arr = arrCell.array else { return }
            // Snapshot keys to allow modification during iteration
            let keys = Array(arr.keys)
            for key in keys {
                guard arrCell.array?[key] != nil else { continue }
                resolveVar(varName).setStr(key)
                do { try exec(body) }
                catch AWKSignal.break_ { return }
                catch AWKSignal.continue_ { /* next key */ }
            }

        case .next:
            throw AWKSignal.next

        case .nextFile:
            throw AWKSignal.nextFile

        case .exit_(let e):
            if let e {
                let code = try eval(e).getNum()
                throw AWKSignal.exit_(Int32(code))
            }
            throw AWKSignal.exit_(env.exitCode)

        case .return_(let e):
            let cell = e != nil ? (try eval(e!)) : AWKCell()
            throw AWKSignal.return_(cell)

        case .break_:
            throw AWKSignal.break_

        case .continue_:
            throw AWKSignal.continue_
        }
    }

    // MARK: - Expression evaluation

    func eval(_ expr: Expression) throws -> AWKCell {
        switch expr {

        // --- Literals ---
        case .number(let n):
            return AWKCell.number(n)

        case .string(let s):
            return AWKCell.string(s)

        case .regexMatch(let pat):
            // Bare /re/ → match against $0
            let s = env.getField(0)
            let matched = (try? AWKRuntime.match(pattern: pat, in: s)) != nil
            return AWKCell.number(matched ? 1 : 0)

        // --- Variables ---
        case .variable(let name):
            return resolveVar(name)

        case .argument(let i):
            if let frame = callStack.last, i < frame.cells.count { return frame.cells[i] }
            throw AWKRuntimeError("function argument \(i) out of range")

        case .varnf:
            env.ensureFields()
            return AWKCell.number(Double(env.NF))

        case .field(let e):
            let n = Int(try eval(e).getNum())
            let s = env.getField(n)
            let c = AWKCell.string(s)
            if AWKRuntime.isNumber(s) { c.numVal = AWKRuntime.parseNum(s); c.hasNum = true }
            return c

        case .element(let name, let keys):
            return try resolveElement(name: name, keys: keys)

        // --- Assignment ---
        case .assign(let op, let lv, let rhs):
            return try execAssign(op: op, lv: lv, rhs: rhs)

        // --- Ternary ---
        case .ternary(let cond, let then, let else_):
            return try eval(cond).isTrue ? eval(then) : eval(else_)

        // --- Logical (short-circuit) ---
        case .logicalOr(let a, let b):
            return AWKCell.number((try eval(a).isTrue || eval(b).isTrue) ? 1 : 0)

        case .logicalAnd(let a, let b):
            return AWKCell.number((try eval(a).isTrue && eval(b).isTrue) ? 1 : 0)

        // --- Comparison ---
        case .equal(let a, let b):
            let x = try eval(a), y = try eval(b)
            return AWKCell.number(AWKRuntime.compare(x, y, convfmt: env.CONVFMT) == 0 ? 1 : 0)

        case .notEqual(let a, let b):
            let x = try eval(a), y = try eval(b)
            return AWKCell.number(AWKRuntime.compare(x, y, convfmt: env.CONVFMT) != 0 ? 1 : 0)

        case .lessThan(let a, let b):
            let x = try eval(a), y = try eval(b)
            return AWKCell.number(AWKRuntime.compare(x, y, convfmt: env.CONVFMT) < 0 ? 1 : 0)

        case .lessEqual(let a, let b):
            let x = try eval(a), y = try eval(b)
            return AWKCell.number(AWKRuntime.compare(x, y, convfmt: env.CONVFMT) <= 0 ? 1 : 0)

        case .greaterThan(let a, let b):
            let x = try eval(a), y = try eval(b)
            return AWKCell.number(AWKRuntime.compare(x, y, convfmt: env.CONVFMT) > 0 ? 1 : 0)

        case .greaterEqual(let a, let b):
            let x = try eval(a), y = try eval(b)
            return AWKCell.number(AWKRuntime.compare(x, y, convfmt: env.CONVFMT) >= 0 ? 1 : 0)

        case .patternMatch(let e, let re):
            let s = try eval(e).getStr(fmt: env.CONVFMT)
            let pat = try regexPattern(re)
            let matched = (try? AWKRuntime.match(pattern: pat, in: s)) != nil
            return AWKCell.number(matched ? 1 : 0)

        case .patternNotMatch(let e, let re):
            let s = try eval(e).getStr(fmt: env.CONVFMT)
            let pat = try regexPattern(re)
            let matched = (try? AWKRuntime.match(pattern: pat, in: s)) != nil
            return AWKCell.number(matched ? 0 : 1)

        case .inArray(let e, let arrName):
            let key = try eval(e).getStr(fmt: env.CONVFMT)
            let arr = resolveVar(arrName)
            return AWKCell.number(arr.array?[key] != nil ? 1 : 0)

        case .inArrayTuple(let exprs, let arrName):
            let parts = try exprs.map { try eval($0).getStr(fmt: env.CONVFMT) }
            let key = env.subscriptKey(parts)
            let arr = resolveVar(arrName)
            return AWKCell.number(arr.array?[key] != nil ? 1 : 0)

        // --- Getline ---
        case .getline(let lv):
            return try execGetline(lv: lv)

        case .getlineFrom(let lv, let src):
            let path = try eval(src).getStr(fmt: env.CONVFMT)
            let file = try env.fileFor(name: path, mode: .read)
            return try readLineInto(lv: lv, from: file, updates0: true)

        case .getlinePipe(let lv, let cmd):
            let cmdStr = try eval(cmd).getStr(fmt: env.CONVFMT)
            let file = try env.fileFor(name: cmdStr, mode: .inputPipe)
            return try readLineInto(lv: lv, from: file, updates0: false)

        // --- Arithmetic ---
        case .concat(let a, let b):
            let sa = try eval(a).getStr(fmt: env.CONVFMT)
            let sb = try eval(b).getStr(fmt: env.CONVFMT)
            return AWKCell.string(sa + sb)

        case .add(let a, let b):
            return AWKCell.number(try eval(a).getNum() + eval(b).getNum())

        case .subtract(let a, let b):
            return AWKCell.number(try eval(a).getNum() - eval(b).getNum())

        case .multiply(let a, let b):
            return AWKCell.number(try eval(a).getNum() * eval(b).getNum())

        case .divide(let a, let b):
            let denom = try eval(b).getNum()
            if denom == 0 { throw AWKRuntimeError("division by zero") }
            return AWKCell.number(try eval(a).getNum() / denom)

        case .modulo(let a, let b):
            let denom = try eval(b).getNum()
            if denom == 0 { throw AWKRuntimeError("division by zero in mod") }
            let num = try eval(a).getNum()
            var intPart = 0.0; modf(num / denom, &intPart)
            return AWKCell.number(num - denom * intPart)

        case .power(let a, let b):
            let base = try eval(a).getNum()
            let exp  = try eval(b).getNum()
            return AWKCell.number(ipow(base, exp))

        case .negate(let e):
            return AWKCell.number(-(try eval(e).getNum()))

        case .unaryPlus(let e):
            return AWKCell.number(try eval(e).getNum())

        case .logicalNot(let e):
            return AWKCell.number(try eval(e).isTrue ? 0 : 1)

        // --- Increment / decrement ---
        case .preIncrement(let lv):
            let c = try evalLValue(lv); c.setNum(c.getNum() + 1); return c

        case .preDecrement(let lv):
            let c = try evalLValue(lv); c.setNum(c.getNum() - 1); return c

        case .postIncrement(let lv):
            let c = try evalLValue(lv)
            let old = c.getNum(); c.setNum(old + 1)
            return AWKCell.number(old)

        case .postDecrement(let lv):
            let c = try evalLValue(lv)
            let old = c.getNum(); c.setNum(old - 1)
            return AWKCell.number(old)

        // --- User-defined function call ---
        case .userCall(let name, let args):
            return try execUserCall(name: name, argExprs: args)

        // --- Builtin function call ---
        case .builtinCall(let id, let args):
            return try execBuiltin(id: id, args: args)

        // --- String operations ---
        case .sprintfExpr(let args):
            guard !args.isEmpty else { return AWKCell.string("") }
            let fmtStr = try eval(args[0]).getStr(fmt: env.CONVFMT)
            return AWKCell.string(try format(fmtStr, args: Array(args.dropFirst())))

        case .subExpr(let kind, let reExpr, let replExpr, let target):
            return try execSub(kind: kind, reExpr: reExpr, replExpr: replExpr, target: target)

        case .substrExpr(let str, let start, let len):
            return try execSubstr(str: str, start: start, len: len)

        case .splitExpr(let str, let arrName, let sep):
            return try execSplit(str: str, arrName: arrName, sep: sep)

        case .indexExpr(let hay, let needle):
            let h = try eval(hay).getStr(fmt: env.CONVFMT)
            let n = try eval(needle).getStr(fmt: env.CONVFMT)
            if n.isEmpty { return AWKCell.number(0) }
            if let r = h.range(of: n) {
                let off = h.distance(from: h.startIndex, to: r.lowerBound)
                return AWKCell.number(Double(off + 1))   // 1-based
            }
            return AWKCell.number(0)

        case .matchFuncExpr(let str, let reExpr):
            let s = try eval(str).getStr(fmt: env.CONVFMT)
            let pat = try regexPattern(reExpr)
            if let (_, nsRange) = try AWKRuntime.pmatch(pattern: pat, in: s) {
                let start = Double(nsRange.location + 1)
                let len   = Double(nsRange.length)
                env.RSTART  = start
                env.RLENGTH = len
                env.globals["RSTART"]?.setNum(start)  ?? { env.globals["RSTART"]  = AWKCell.number(start) }()
                env.globals["RLENGTH"]?.setNum(len)   ?? { env.globals["RLENGTH"] = AWKCell.number(len) }()
                return AWKCell.number(start)
            }
            env.RSTART = 0; env.RLENGTH = -1
            env.globals["RSTART"]  = AWKCell.number(0)
            env.globals["RLENGTH"] = AWKCell.number(-1)
            return AWKCell.number(0)

        case .closeExpr(let e):
            let name = try eval(e).getStr(fmt: env.CONVFMT)
            env.closeFile(name: name)
            return AWKCell.number(0)

        case .indirect(let e):
            // @expr or $$n — treat as field
            let n = Int(try eval(e).getNum())
            let s = env.getField(n)
            return AWKCell.string(s)
        }
    }

    // MARK: - LValue resolution (returns the cell itself for mutation)

    func evalLValue(_ lv: LValue) throws -> AWKCell {
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
            let c = AWKCell.number(Double(env.NF)); c.hasNum = true; return c

        case .field(let e):
            // Field lvalue — we can't return a reference to an element of env.fields.
            // Instead, return a proxy: a cell whose value changes are applied via setField.
            // We wrap this in a FieldProxy approach: return a cell and post-assign it.
            // This is handled per-case in execAssign and incr/decr.
            // For the incr/decr case, we need the actual stored cell; use a field cell.
            let n = Int(try eval(e).getNum())
            return makeFieldCell(n)

        case .element(let name, let keys):
            return try resolveElement(name: name, keys: keys)

        case .indirect(let e):
            let n = Int(try eval(e).getNum())
            return makeFieldCell(n)
        }
    }

    // MARK: - Variable / element resolution

    private func resolveVar(_ name: String) -> AWKCell {
        // Check built-in variables first
        switch name {
        case "FS":       return syncedBuiltin(name, get: { AWKCell.string(self.env.FS) })
        case "RS":       return syncedBuiltin(name, get: { AWKCell.string(self.env.RS) })
        case "OFS":      return syncedBuiltin(name, get: { AWKCell.string(self.env.OFS) })
        case "ORS":      return syncedBuiltin(name, get: { AWKCell.string(self.env.ORS) })
        case "OFMT":     return syncedBuiltin(name, get: { AWKCell.string(self.env.OFMT) })
        case "CONVFMT":  return syncedBuiltin(name, get: { AWKCell.string(self.env.CONVFMT) })
        case "NR":       return AWKCell.number(env.NR)
        case "FNR":      return AWKCell.number(env.FNR)
        case "NF":       env.ensureFields(); return AWKCell.number(Double(env.NF))
        case "FILENAME": return AWKCell.string(env.FILENAME)
        case "SUBSEP":   return AWKCell.string(env.SUBSEP)
        case "RSTART":   return AWKCell.number(env.RSTART)
        case "RLENGTH":  return AWKCell.number(env.RLENGTH)
        default: break
        }
        // Check current call frame
        if let frame = callStack.last {
            if let i = frame.paramNames.firstIndex(of: name) {
                return frame.cells[i]
            }
        }
        return env.global(name)
    }

    private func syncedBuiltin(_ name: String,
                               get: () -> AWKCell) -> AWKCell {
        if let c = env.globals[name] { return c }
        let c = get(); env.globals[name] = c; return c
    }

    private func resolveElement(name: String, keys: [Expression]) throws -> AWKCell {
        let parts = try keys.map { try eval($0).getStr(fmt: env.CONVFMT) }
        let key = env.subscriptKey(parts)
        let arr = resolveVar(name)
        if arr.array == nil { arr.array = [:] }
        if let existing = arr.array![key] { return existing }
        let c = AWKCell()
        arr.array![key] = c
        return c
    }

    // MARK: - Field proxy cells

    /// A pseudo-cell backed by field slot n.  Changes are written back via setField.
    private var fieldCells: [Int: AWKCell] = [:]

    private func makeFieldCell(_ n: Int) -> AWKCell {
        if let existing = fieldCells[n] { return existing }
        let s = env.getField(n)
        let c = AWKCell.string(s)
        if AWKRuntime.isNumber(s) { c.numVal = AWKRuntime.parseNum(s); c.hasNum = true }
        fieldCells[n] = c
        return c
    }

    private func flushFieldCells() {
        for (n, c) in fieldCells {
            env.setField(n, c.getStr(fmt: env.CONVFMT))
        }
        fieldCells = [:]
    }

    // MARK: - Assignment

    private func execAssign(op: AssignOp, lv: LValue, rhs: Expression) throws -> AWKCell {
        let rhsVal = try eval(rhs)

        // NF assignment requires special handling
        if case .varnf = lv {
            let n = Int(rhsVal.getNum())
            env.setNF(n)
            return AWKCell.number(Double(n))
        }

        // Field assignment writes through to env.fields / env.record
        if case .field(let fe) = lv {
            let n = Int(try eval(fe).getNum())
            let cur = AWKCell.number(Double(env.getField(n) == "" ? 0 : 0))
            let curStr = env.getField(n)
            let curNum = AWKRuntime.parseNum(curStr)
            let newVal = applyOp(op, lhsNum: curNum, lhsStr: curStr, rhs: rhsVal)
            env.setField(n, newVal.getStr(fmt: env.CONVFMT))
            if n == 0 { env.fieldsDirty = true }
            _ = cur  // suppress warning
            return newVal
        }

        let target = try evalLValue(lv)
        let result = applyOp(op, lhsNum: target.getNum(), lhsStr: target.getStr(fmt: env.CONVFMT), rhs: rhsVal)

        // Write back to built-in variables
        if case .variable(let name) = lv { writeback(name: name, cell: result) }

        target.copyScalarFrom(result)
        return target
    }

    private func applyOp(_ op: AssignOp, lhsNum: Double, lhsStr: String, rhs: AWKCell) -> AWKCell {
        switch op {
        case .set:    return rhs
        case .addSet: return AWKCell.number(lhsNum + rhs.getNum())
        case .subSet: return AWKCell.number(lhsNum - rhs.getNum())
        case .mulSet: return AWKCell.number(lhsNum * rhs.getNum())
        case .divSet:
            let d = rhs.getNum()
            return AWKCell.number(d == 0 ? 0 : lhsNum / d)   // real code throws
        case .modSet:
            let d = rhs.getNum()
            var i = 0.0; modf(lhsNum / d, &i)
            return AWKCell.number(lhsNum - d * i)
        case .powSet:
            return AWKCell.number(ipow(lhsNum, rhs.getNum()))
        }
    }

    private func writeback(name: String, cell: AWKCell) {
        let s = cell.getStr(fmt: env.CONVFMT)
        let n = cell.getNum()
        switch name {
        case "FS":      env.FS = s
        case "RS":      env.RS = s
        case "OFS":     env.OFS = s
        case "ORS":     env.ORS = s
        case "OFMT":    env.OFMT = s
        case "CONVFMT": env.CONVFMT = s
        case "NR":      env.NR = n
        case "FNR":     env.FNR = n
        case "NF":      env.setNF(Int(n))
        case "FILENAME":env.FILENAME = s
        case "SUBSEP":  env.SUBSEP = s
        default: break
        }
        env.globals[name] = cell
    }

    // MARK: - Power helper (matches C ipow for integer exponents)

    private func ipow(_ x: Double, _ exp: Double) -> Double {
        var intPart = 0.0
        if exp >= 0 && modf(exp, &intPart) == 0.0 {
            var result = 1.0; var n = Int(exp); var base = x
            while n > 0 { if n & 1 == 1 { result *= base }; base *= base; n >>= 1 }
            return result
        }
        return pow(x, exp)
    }

    // MARK: - Regex helper (extracts pattern string from an expression)

    private func regexPattern(_ e: Expression) throws -> String {
        if case .regexMatch(let s) = e { return s }
        return try eval(e).getStr(fmt: env.CONVFMT)
    }

    // MARK: - Print statement

    private func execPrint(kind: PrintKind, args: [Expression], dest: PrintDest?) throws {
        let output: AWKFile
        switch dest {
        case .none:
            output = AWKFile(name: "/dev/stdout", mode: .write, handle: .standardOutput)
        case .redirect(let e):
            let path = try eval(e).getStr(fmt: env.CONVFMT)
            output = try env.fileFor(name: path, mode: .write)
        case .append(let e):
            let path = try eval(e).getStr(fmt: env.CONVFMT)
            output = try env.fileFor(name: path, mode: .append)
        case .pipe(let e):
            let cmd = try eval(e).getStr(fmt: env.CONVFMT)
            output = try env.fileFor(name: cmd, mode: .outputPipe)
        }

        switch kind {
        case .print:
            try print_(args, dest: dest, to: output)
        case .printf:
            guard !args.isEmpty else { return }
            let fmtStr = try eval(args[0]).getStr(fmt: env.CONVFMT)
            let result = try format(fmtStr, args: Array(args.dropFirst()))
            try output.write(result)
        }
    }

    private func print_(_ args: [Expression], dest: PrintDest?, to output: AWKFile? = nil) throws {
        let out = output ?? AWKFile(name: "/dev/stdout", mode: .write, handle: .standardOutput)
        if args.isEmpty {
            env.ensureRecord()
            try out.write(env.record + env.ORS)
            return
        }
        var first = true
        for arg in args {
            if !first { try out.write(env.OFS) }
            let val = try eval(arg)
            try out.write(val.getStr(fmt: env.OFMT))
            first = false
        }
        try out.write(env.ORS)
    }

    // MARK: - Delete statement

    private func execDelete(_ lv: LValue) throws {
        switch lv {
        case .variable(let name):
            let c = resolveVar(name)
            c.array = nil; c.hasNum = false; c.hasStr = false; c.strVal = ""; c.numVal = 0
        case .element(let name, let keys):
            let parts = try keys.map { try eval($0).getStr(fmt: env.CONVFMT) }
            let key = env.subscriptKey(parts)
            resolveVar(name).array?.removeValue(forKey: key)
        default:
            throw AWKRuntimeError("delete requires a variable or array element")
        }
    }

    // MARK: - User-defined function call

    private func execUserCall(name: String, argExprs: [Expression]) throws -> AWKCell {
        guard let fn = env.functions[name] else {
            throw AWKRuntimeError("calling undefined function '\(name)'")
        }
        // Evaluate actual arguments
        var cells: [AWKCell] = []
        for argExpr in argExprs {
            let c = try eval(argExpr)
            if c.isArray {
                cells.append(c)   // arrays: pass by reference
            } else {
                let copy = AWKCell(); copy.copyScalarFrom(c); cells.append(copy)
            }
        }
        // Pad with empty cells for any unspecified parameters
        while cells.count < fn.params.count { cells.append(AWKCell()) }
        // Extra locals beyond defined params
        // (one-true-awk uses extra params as local variables)

        let frame = CallFrame(funcName: name, paramNames: fn.params, cells: cells)
        callStack.append(frame)
        defer { callStack.removeLast() }

        do {
            try execBlock(fn.body)
        } catch AWKSignal.return_(let val) {
            return val
        }
        return callStack.last?.retval ?? AWKCell()
    }

    // MARK: - Builtin function call

    private func execBuiltin(id: AWKBuiltinID, args: [Expression]) throws -> AWKCell {
        switch id {
        case .length:
            if args.isEmpty {
                env.ensureFields()
                return AWKCell.number(Double(env.record.count))
            }
            let c = try eval(args[0])
            if let arr = c.array { return AWKCell.number(Double(arr.count)) }
            return AWKCell.number(Double(c.getStr(fmt: env.CONVFMT).count))

        case .sqrt:
            return AWKCell.number(sqrt(try eval(args[0]).getNum()))

        case .exp:
            return AWKCell.number(Foundation.exp(try eval(args[0]).getNum()))

        case .log:
            let v = try eval(args[0]).getNum()
            if v <= 0 { throw AWKRuntimeError("log: argument must be positive") }
            return AWKCell.number(Foundation.log(v))

        case .int_:
            var intPart = 0.0; modf(try eval(args[0]).getNum(), &intPart)
            return AWKCell.number(intPart)

        case .system:
            let cmd = try eval(args[0]).getStr(fmt: env.CONVFMT)
            fflush(stdout)
            let status = Foundation.system(cmd)
            var code: Int32 = status
            if status != -1 {
                if WIFEXITED(status) { code = WEXITSTATUS(status) }
                else if WIFSIGNALED(status) { code = WTERMSIG(status) + 256 }
                else { code = 0 }
            }
            return AWKCell.number(Double(code))

        case .rand:
            return AWKCell.number(Double(arc4random()) / Double(UInt32.max) + 1)

        case .srand:
            let old = env.srandSeed
            let seed: Double
            if args.isEmpty { seed = Double(Date().timeIntervalSince1970) }
            else            { seed = try eval(args[0]).getNum() }
            env.srandSeed = seed
            srand48(Int(seed))
            return AWKCell.number(old)

        case .sin:
            return AWKCell.number(Foundation.sin(try eval(args[0]).getNum()))

        case .cos:
            return AWKCell.number(Foundation.cos(try eval(args[0]).getNum()))

        case .atan2:
            let y = try eval(args[0]).getNum()
            let x = args.count > 1 ? try eval(args[1]).getNum() : 1.0
            return AWKCell.number(Foundation.atan2(y, x))

        case .toupper:
            return AWKCell.string(try eval(args[0]).getStr(fmt: env.CONVFMT).uppercased())

        case .tolower:
            return AWKCell.string(try eval(args[0]).getStr(fmt: env.CONVFMT).lowercased())

        case .fflush:
            if args.isEmpty {
                env.flushAll()
            } else {
                let name = try eval(args[0]).getStr(fmt: env.CONVFMT)
                if name.isEmpty { env.flushAll() }
                else if let f = env.openFiles.first(where: { $0.name == name }) {
                    try? f.handle.synchronize()
                }
            }
            return AWKCell.number(0)
        }
    }

    // MARK: - Getline

    private func execGetline(lv: LValue?) throws -> AWKCell {
        // Bare getline — read next record from current input (stdin)
        // For simplicity, read from stdin
        guard let line = readln(from: .standardInput) else {
            return AWKCell.number(-1)
        }
        if let lv {
            let c = try evalLValue(lv)
            c.setStr(line)
            if AWKRuntime.isNumber(line) { c.setBoth(AWKRuntime.parseNum(line), line) }
        } else {
            env.NR += 1; env.FNR += 1
            env.record = line; env.fieldsDirty = true
        }
        return AWKCell.number(1)
    }

    private func readLineInto(lv: LValue?, from file: AWKFile, updates0: Bool) throws -> AWKCell {
        guard let line = file.readRecord(rs: env.RS) else { return AWKCell.number(0) }
        if let lv {
            let c = try evalLValue(lv)
            c.setStr(line)
            if AWKRuntime.isNumber(line) { c.setBoth(AWKRuntime.parseNum(line), line) }
        } else if updates0 {
            env.record = line; env.fieldsDirty = true
        }
        return AWKCell.number(1)
    }

    private func readln(from fh: FileHandle) -> String? {
        // Inefficient but simple: read byte-by-byte until RS
        var line = ""
        let sep: UInt8 = env.RS.first.map { $0.asciiValue ?? 10 } ?? 10
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

    private func execSub(kind: SubKind, reExpr: Expression, replExpr: Expression, target: LValue) throws -> AWKCell {
        let pat = try regexPattern(reExpr)
        let repl = try eval(replExpr).getStr(fmt: env.CONVFMT)
        let targetCell = try evalLValue(target)
        let str = targetCell.getStr(fmt: env.CONVFMT)

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
                targetCell.setStr(result)
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
            targetCell.setStr(result)
        }

        // Write back if this is a field lvalue
        if case .field(let fe) = target {
            let n = Int(try eval(fe).getNum())
            env.setField(n, targetCell.getStr(fmt: env.CONVFMT))
        }

        return AWKCell.number(Double(count))
    }

    private func execSubstr(str: Expression, start: Expression, len: Expression?) throws -> AWKCell {
        let s = try eval(str).getStr(fmt: env.CONVFMT)
        let k = s.count
        if k == 0 { return AWKCell.string("") }

        var m = Int(try eval(start).getNum())
        if m <= 0 { m = 1 }
        else if m > k + 1 { return AWKCell.string("") }

        let n: Int
        if let lenExpr = len {
            n = max(0, min(Int(try eval(lenExpr).getNum()), k - m + 1))
        } else {
            n = k - m + 1
        }

        let startIdx = s.index(s.startIndex, offsetBy: m - 1, limitedBy: s.endIndex) ?? s.endIndex
        let endIdx   = s.index(startIdx, offsetBy: n, limitedBy: s.endIndex) ?? s.endIndex
        return AWKCell.string(String(s[startIdx..<endIdx]))
    }

    private func execSplit(str: Expression, arrName: String, sep: Expression?) throws -> AWKCell {
        let s = try eval(str).getStr(fmt: env.CONVFMT)
        let arr = resolveVar(arrName)
        arr.array = [:]

        let fs: String
        if let sepExpr = sep {
            if case .regexMatch(let pat) = sepExpr { fs = pat }
            else { fs = try eval(sepExpr).getStr(fmt: env.CONVFMT) }
        } else {
            fs = env.FS
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
            guard let re = try? NSRegularExpression(pattern: fs) else { return AWKCell.number(0) }
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
        }

        for (i, p) in parts.enumerated() {
            let key = String(i + 1)
            let c = AWKRuntime.isNumber(p)
                ? AWKCell.both(AWKRuntime.parseNum(p), p)
                : AWKCell.string(p)
            arr.array![key] = c
        }
        return AWKCell.number(Double(parts.count))
    }

    // MARK: - Printf formatting

    func format(_ fmt: String, args: [Expression]) throws -> String {
        var result = ""
        var argIdx = 0
        var i = fmt.startIndex

        while i < fmt.endIndex {
            let c = fmt[i]
            guard c == "%" else { result.append(c); fmt.formIndex(after: &i); continue }
            fmt.formIndex(after: &i)
            guard i < fmt.endIndex else { result.append("%"); break }
            if fmt[i] == "%" { result.append("%"); fmt.formIndex(after: &i); continue }

            var spec = "%"
            // flags
            while i < fmt.endIndex && "-+0 #".contains(fmt[i]) {
                spec.append(fmt[i]); fmt.formIndex(after: &i)
            }
            // width (* or digits)
            if i < fmt.endIndex && fmt[i] == "*" {
                if argIdx < args.count { spec += String(Int(try eval(args[argIdx]).getNum())); argIdx += 1 }
                fmt.formIndex(after: &i)
            } else { while i < fmt.endIndex && fmt[i] >= "0" && fmt[i] <= "9" { spec.append(fmt[i]); fmt.formIndex(after: &i) } }
            // precision
            if i < fmt.endIndex && fmt[i] == "." {
                spec.append("."); fmt.formIndex(after: &i)
                if i < fmt.endIndex && fmt[i] == "*" {
                    if argIdx < args.count { spec += String(Int(try eval(args[argIdx]).getNum())); argIdx += 1 }
                    fmt.formIndex(after: &i)
                } else { while i < fmt.endIndex && fmt[i] >= "0" && fmt[i] <= "9" { spec.append(fmt[i]); fmt.formIndex(after: &i) } }
            }
            // skip size modifiers
            while i < fmt.endIndex && "hjLlqtz".contains(fmt[i]) { fmt.formIndex(after: &i) }
            guard i < fmt.endIndex else { break }
            let type = fmt[i]; fmt.formIndex(after: &i)

            let arg: AWKCell = argIdx < args.count ? (try eval(args[argIdx])) : AWKCell()
            argIdx += 1

            switch type {
            case "d", "i":
                result += String(format: spec + "d", Int64(bitPattern: UInt64(arg.getNum())))
            case "o": result += String(format: spec + "o", UInt64(arg.getNum()))
            case "x": result += String(format: spec + "x", UInt64(arg.getNum()))
            case "X": result += String(format: spec + "X", UInt64(arg.getNum()))
            case "u": result += String(format: spec + "u", UInt64(arg.getNum()))
            case "e": result += String(format: spec + "e", arg.getNum())
            case "E": result += String(format: spec + "E", arg.getNum())
            case "f": result += String(format: spec + "f", arg.getNum())
            case "g": result += String(format: spec + "g", arg.getNum())
            case "G": result += String(format: spec + "G", arg.getNum())
            case "a": result += String(format: spec + "a", arg.getNum())
            case "A": result += String(format: spec + "A", arg.getNum())
            case "s": result += String(format: spec + "s", arg.getStr(fmt: env.OFMT))
            case "c":
                if arg.hasNum {
                    let n = Int(arg.getNum()) & 0xFF
                    if n != 0 { result += String(format: spec + "c", n) }
                } else {
                    let s = arg.getStr(fmt: env.CONVFMT)
                    result += String(format: spec + "c", s.first.flatMap { $0.asciiValue }.map(Int.init) ?? 0)
                }
            default: result.append(type)
            }
        }
        return result
    }
}
