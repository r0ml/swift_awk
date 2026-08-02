// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

import CMigration

extension AWKExecutor {

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

  // C: execute() — run.c  (arith / relop / boolop / matchop / condexpr / cat / incrdecr / etc.)
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
