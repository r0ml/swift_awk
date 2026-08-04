// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

import CMigration

extension RuntimeState {

  // MARK: - Statement execution

  // C: program() block loop — run.c
  func execBlock(_ stmts: [Statement]) throws {
      for stmt in stmts { try exec(stmt) }
  }

  // C: execute() — run.c  (ifstat / whilestat / dostat / forstat / instat / jump)
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
          guard case .dict(let aa) = arrCell.val else { return }
          // Snapshot keys to allow modification during iteration
          let keys = Array(aa.keys)
          for key in keys {
              guard aa[key] != nil else { continue }
              var v = resolveVar(varName)
              v.setsval(key)
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
              let code = try eval(e).getfval()
              throw AWKSignal.exit_(Int32(code))
          }
          throw AWKSignal.exit_(exitCode)

      case .return_(let e):
          let cell = e != nil ? (try eval(e!)) : Cell()
          throw AWKSignal.`return`(cell)

      case .break_:
          throw AWKSignal.break_

      case .continue_:
          throw AWKSignal.continue_
      }
  }

  // MARK: - Expression evaluation

  // C: execute() — run.c  (arith / relop / boolop / matchop / condexpr / cat / incrdecr / etc.)
  func eval(_ expr: Expression) throws -> Cell {
      switch expr {

      // --- Literals ---
      case .number(let n):
          return Cell(number: n)

      case .string(let s):
          return Cell(string: s)

      case .regexMatch(let pat):
          // Bare /re/ → match against $0
          let s = getField(0)
          let matched = (try? AWKRuntime.match(pattern: pat, in: s)) != nil
          return Cell(number: matched ? 1 : 0)

      // --- Variables ---
      case .variable(let name):
          return resolveVar(name)

      case .argument(let i):
          if let frame = callStack.last, i < frame.cells.count { return frame.cells[i] }
          throw AWKRuntimeError("function argument \(i) out of range")

      case .varnf:
          // should be  fldbld()
          ensureFields()
          return symtab["NF"]!

      case .field(let e):
          let n = Int(try eval(e).getfval())
          let s = getField(n)
          let c = Cell(field: s, at: n)
//          if AWKRuntime.isNumber(s) { c.numVal = AWKRuntime.parseNum(s); c.hasNum = true }
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
          return Cell(number: (try eval(a).isTrue || eval(b).isTrue) ? 1 : 0)

      case .logicalAnd(let a, let b):
          return Cell(number: (try eval(a).isTrue && eval(b).isTrue) ? 1 : 0)

      // --- Comparison ---
      case .equal(let a, let b):
          let x = try eval(a), y = try eval(b)
          return Cell(number: AWKRuntime.compare(x, y, convfmt: CONVFMT) == 0 ? 1 : 0)

      case .notEqual(let a, let b):
          let x = try eval(a), y = try eval(b)
          return Cell(number: AWKRuntime.compare(x, y, convfmt: CONVFMT) != 0 ? 1 : 0)

      case .lessThan(let a, let b):
          let x = try eval(a), y = try eval(b)
          return Cell(number: AWKRuntime.compare(x, y, convfmt: CONVFMT) < 0 ? 1 : 0)

      case .lessEqual(let a, let b):
          let x = try eval(a), y = try eval(b)
          return Cell(number: AWKRuntime.compare(x, y, convfmt: CONVFMT) <= 0 ? 1 : 0)

      case .greaterThan(let a, let b):
          let x = try eval(a), y = try eval(b)
          return Cell(number: AWKRuntime.compare(x, y, convfmt: CONVFMT) > 0 ? 1 : 0)

      case .greaterEqual(let a, let b):
          let x = try eval(a), y = try eval(b)
          return Cell(number: AWKRuntime.compare(x, y, convfmt: CONVFMT) >= 0 ? 1 : 0)

      case .patternMatch(let e, let re):
          let s = try eval(e).getsval(fmt: CONVFMT)
          let pat = try regexPattern(re)
          let matched = (try? AWKRuntime.match(pattern: pat, in: s)) != nil
          return Cell(number: matched ? 1 : 0)

      case .patternNotMatch(let e, let re):
          let s = try eval(e).getsval(fmt: CONVFMT)
          let pat = try regexPattern(re)
          let matched = (try? AWKRuntime.match(pattern: pat, in: s)) != nil
          return Cell(number: matched ? 0 : 1)

      case .inArray(let e, let arrName):
          fatalError("unimplmented inArray")
          /*
          let key = try eval(e).getsval(fmt: CONVFMT)
          let arr = resolveVar(arrName)
          return Cell(number: arr.array?[key] != nil ? 1 : 0)
           */

      case .inArrayTuple(let exprs, let arrName):
          fatalError("unimplmented inArrayTuple")
          /*
          let parts = try exprs.map { try eval($0).getsval(fmt: CONVFMT) }
          let key = subscriptKey(parts)
          let arr = resolveVar(arrName)
          return Cell(number: arr.array?[key] != nil ? 1 : 0)
*/

      // --- Getline ---
      case .getline(let lv):
          return try execGetline(lv: lv)

      case .getlineFrom(let lv, let src):
          let path = try eval(src).getsval(fmt: CONVFMT)
          let file = try fileFor(name: path, mode: .read)
          return try readLineInto(lv: lv, from: file, updates0: true)

      case .getlinePipe(let lv, let cmd):
          let cmdStr = try eval(cmd).getsval(fmt: CONVFMT)
          let file = try fileFor(name: cmdStr, mode: .inputPipe)
          return try readLineInto(lv: lv, from: file, updates0: false)

      // --- Arithmetic ---
      case .concat(let a, let b):
          let sa = try eval(a).getsval(fmt: CONVFMT)
          let sb = try eval(b).getsval(fmt: CONVFMT)
          return Cell(string: sa + sb)

      case .add(let a, let b):
          return Cell(number: try eval(a).getfval() + eval(b).getfval())

      case .subtract(let a, let b):
          return Cell(number: try eval(a).getfval() - eval(b).getfval())

      case .multiply(let a, let b):
          return Cell(number: try eval(a).getfval() * eval(b).getfval())

      case .divide(let a, let b):
          let denom = try eval(b).getfval()
          if denom == 0 { throw AWKRuntimeError("division by zero") }
          return Cell(number: try eval(a).getfval() / denom)

      case .modulo(let a, let b):
          let denom = try eval(b).getfval()
          if denom == 0 { throw AWKRuntimeError("division by zero in mod") }
          let num = try eval(a).getfval()
          var intPart = 0.0; modf(num / denom, &intPart)
          return Cell(number: num - denom * intPart)

      case .power(let a, let b):
          let base = try eval(a).getfval()
          let exp  = try eval(b).getfval()
          return Cell(number: ipow(base, exp))

      case .negate(let e):
          return Cell(number: -(try eval(e).getfval()))

      case .unaryPlus(let e):
          return Cell(number: try eval(e).getfval())

      case .logicalNot(let e):
          return Cell(number: try eval(e).isTrue ? 0 : 1)

      // --- Increment / decrement ---
      case .preIncrement(let lv):
          var c = try evalLValue(lv)
          c.setfval(c.getfval() + 1)
          setsym(c)
          return c

      case .preDecrement(let lv):
          var c = try evalLValue(lv)
          c.setfval(c.getfval() - 1)
          setsym(c)
          return c

      case .postIncrement(let lv):
          var c = try evalLValue(lv)
          let old = c.getfval()
          c.setfval(old + 1)
          setsym(c)
          return Cell(number: old)

      case .postDecrement(let lv):
          var c = try evalLValue(lv)
          let old = c.getfval()
          c.setfval(old - 1)
          setsym(c)
          return Cell(number: old)

      // --- User-defined function call ---
      case .userCall(let name, let args):
          return try execUserCall(name: name, argExprs: args)

      // --- Builtin function call ---
      case .builtinCall(let id, let args):
          return try execBuiltin(id: id, args: args)

      // --- String operations ---
      case .sprintfExpr(let args):
          guard !args.isEmpty else { return Cell() }
          let fmtStr = try eval(args[0]).getsval(fmt: CONVFMT)
          return Cell(string: try format(fmtStr, args: Array(args.dropFirst())))

      case .subExpr(let kind, let reExpr, let replExpr, let target):
          return try execSub(kind: kind, reExpr: reExpr, replExpr: replExpr, target: target)

      case .substrExpr(let str, let start, let len):
          return try execSubstr(str: str, start: start, len: len)

      case .splitExpr(let str, let arrName, let sep):
          return try execSplit(str: str, arrName: arrName, sep: sep)

      case .indexExpr(let hay, let needle):
          let h = try eval(hay).getsval(fmt: CONVFMT)
          let n = try eval(needle).getsval(fmt: CONVFMT)
          if n.isEmpty { return Cell(number: 0) }
          if let r = h.range(of: n) {
              let off = h.distance(from: h.startIndex, to: r.lowerBound)
            return Cell(number: Double(off + 1))   // 1-based
          }
          return Cell(number: 0)

      case .matchFuncExpr(let str, let reExpr):
          let s = try eval(str).getsval(fmt: CONVFMT)
          let pat = try regexPattern(reExpr)
          if let (_, nsRange) = try AWKRuntime.pmatch(pattern: pat, in: s) {
            let start = Double(nsRange.location + 1)
            let len   = Double(nsRange.length)
            RSTART  = start
            RLENGTH = len
            return Cell(number: start)
          }
          RSTART = 0
          RLENGTH = -1
          return Cell(number: 0)

      case .closeExpr(let e):
          let name = try eval(e).getsval(fmt: CONVFMT)
          closeFile(name: name)
          return Cell(number: 0)

      case .indirect(let e):
          // @expr or $$n — treat as field
          let n = Int(try eval(e).getfval())
          let s = getField(n)
          return Cell(string: s)
      }
  }

  // MARK: - Printf formatting

  // C: format() — run.c
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
              if argIdx < args.count { spec += String(Int(try eval(args[argIdx]).getfval())); argIdx += 1 }
              fmt.formIndex(after: &i)
          } else { while i < fmt.endIndex && fmt[i] >= "0" && fmt[i] <= "9" { spec.append(fmt[i]); fmt.formIndex(after: &i) } }
          // precision
          if i < fmt.endIndex && fmt[i] == "." {
              spec.append("."); fmt.formIndex(after: &i)
              if i < fmt.endIndex && fmt[i] == "*" {
                if argIdx < args.count { spec += String(Int(try eval(args[argIdx]).getfval())); argIdx += 1 }
                  fmt.formIndex(after: &i)
              } else { while i < fmt.endIndex && fmt[i] >= "0" && fmt[i] <= "9" { spec.append(fmt[i]); fmt.formIndex(after: &i) } }
          }
          // skip size modifiers
          while i < fmt.endIndex && "hjLlqtz".contains(fmt[i]) { fmt.formIndex(after: &i) }
          guard i < fmt.endIndex else { break }
          let type = fmt[i]; fmt.formIndex(after: &i)

        let arg: Cell = argIdx < args.count ? (try eval(args[argIdx])) : Cell()
          argIdx += 1

          switch type {
          case "d", "i":
              result += cFormat( spec + "d", Int64(bitPattern: UInt64(arg.getfval())))
          case "o": result += cFormat( spec + "o", UInt64(arg.getfval()))
          case "x": result += cFormat( spec + "x", UInt64(arg.getfval()))
          case "X": result += cFormat( spec + "X", UInt64(arg.getfval()))
          case "u": result += cFormat( spec + "u", UInt64(arg.getfval()))
          case "e": result += cFormat( spec + "e", arg.getfval())
          case "E": result += cFormat( spec + "E", arg.getfval())
          case "f": result += cFormat( spec + "f", arg.getfval())
          case "g": result += cFormat( spec + "g", arg.getfval())
          case "G": result += cFormat( spec + "G", arg.getfval())
          case "a": result += cFormat( spec + "a", arg.getfval())
          case "A": result += cFormat( spec + "A", arg.getfval())
          case "s": result += cFormat( spec + "s", arg.getsval(fmt: OFMT))
          case "c":
              if arg.hasNum {
                  let n = Int(arg.getfval()) & 0xFF
                  if n != 0 { result += cFormat(spec + "c", n) }
              } else {
                  let s = arg.getsval(fmt: CONVFMT)
                  result += cFormat(spec + "c", s.first.flatMap { $0.asciiValue }.map(Int.init) ?? 0)
              }
          default: result.append(type)
          }
      }
      return result
  }
}
