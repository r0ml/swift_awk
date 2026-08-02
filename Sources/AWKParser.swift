// AWKParser.swift
// AWK grammar expressed as parser combinators + a Pratt parser for expressions.
// Direct translation of awkgram.y (one-true-awk).
//
// Grammar rules appear as private functions returning Parser<T>.
// Expression parsing uses Pratt / top-down operator precedence, which handles
// AWK's rich precedence table without left-recursion issues.

// MARK: - Entry point

enum AWKParser {
    // C: yyparse() — awkgram.y
    static func parse(_ tokens: [AWKToken]) throws -> AWKProgram {
        try program().run(on: tokens)
    }
}

// MARK: - Whitespace / separator helpers
// These correspond to: pst opt_pst nl opt_nl st lbrace rbrace rparen comma

// C: pst / opt_pst — awkgram.y
private func skipSep() -> Parser<Void> {
    oneOf(token(.newline), token(.semicolon)).many.map { _ in () }
}

// Statement terminator: nl | ';' opt_nl
// C: st — awkgram.y
private func stEnd() -> Parser<Void> {
    oneOf(
        token(.newline).many1.map { _ in () },
        token(.semicolon).then(token(.newline).many.map { _ in () })
    )
}

// Tokens that allow optional trailing newlines per the grammar
// C: lbrace — awkgram.y
private func lbrace() -> Parser<Void> {
    token(.lbrace).then(token(.newline).many.map { _ in () })
}
// C: rbrace — awkgram.y
private func rbrace() -> Parser<Void> {
    token(.rbrace).then(token(.newline).many.map { _ in () })
}
// C: rparen — awkgram.y
private func rparen_() -> Parser<Void> {
    token(.rparen).then(token(.newline).many.map { _ in () })
}
// C: comma — awkgram.y
private func comma_() -> Parser<Void> {
    token(.comma).then(token(.newline).many.map { _ in () })
}
// C: opt_nl — awkgram.y
private func skipNL() -> Parser<Void> {
    token(.newline).many.map { _ in () }
}

// C: statement-terminator detection — awkgram.y
private func isStEnd(_ tok: AWKToken?) -> Bool {
    switch tok {
    case .newline, .semicolon, .rbrace, .eof, nil: return true
    default: return false
    }
}

// MARK: - Top-level program
// program: pas   where  pas: opt_pst (pa_stat (opt_pst pa_stat)* opt_pst)?

// C: program rule — awkgram.y
private func program() -> Parser<AWKProgram> {
    Parser { stream in
        try skipSep().parse(&stream)

        var beginRules: [[Statement]] = []
        var rules:      [PatternAction] = []
        var endRules:   [[Statement]] = []
        var functions:  [FunctionDefinition] = []

        while let next = stream.first, next != .eof {
            let saved = stream
            do {
                if let rule = try paStat(
                    &stream,
                    beginRules: &beginRules,
                    endRules:   &endRules,
                    functions:  &functions
                ) {
                    rules.append(rule)
                }
                try skipSep().parse(&stream)
            } catch {
                stream = saved
                break
            }
        }

        return AWKProgram(
            beginRules: beginRules,
            rules:      rules,
            endRules:   endRules,
            functions:  functions
        )
    }
}

// MARK: - Pattern-action rules

// C: pa_stat — awkgram.y
private func paStat(
    _ stream: inout TokenStream,
    beginRules: inout [[Statement]],
    endRules:   inout [[Statement]],
    functions:  inout [FunctionDefinition]
) throws -> PatternAction? {
    switch stream.first {

    case .xbegin:
        stream = stream.dropFirst()
        let body = try stmtBlock().parse(&stream)
        beginRules.append(body)
        return nil

    case .xend:
        stream = stream.dropFirst()
        let body = try stmtBlock().parse(&stream)
        endRules.append(body)
        return nil

    case .funcKeyword:
        stream = stream.dropFirst()
        let fn = try parseFunctionDef().parse(&stream)
        functions.append(fn)
        return nil

    case .lbrace:
        // Always block — no pattern
        let body = try stmtBlock().parse(&stream)
        return PatternAction(pattern: .always, body: body)

    default:
        // Pattern, possibly followed by ',' pattern (range), possibly followed by block
        let pat = try paPat().parse(&stream)
        if stream.first == .comma {
            stream = stream.dropFirst()
            try skipNL().parse(&stream)
            let pat2 = try paPat().parse(&stream)
            let body = (stream.first == .lbrace) ? try stmtBlock().parse(&stream) : []
            return PatternAction(pattern: .range(pat, pat2), body: body)
        }
        let body = (stream.first == .lbrace) ? try stmtBlock().parse(&stream) : []
        return PatternAction(pattern: .expression(pat), body: body)
    }
}

// pa_pat: pattern wrapped in notnull
// C: pa_pat — awkgram.y
private func paPat() -> Parser<Expression> {
    pattern().map { $0.notnull() }
}

// MARK: - Function definitions

// C: funcdef — awkgram.y
private func parseFunctionDef() -> Parser<FunctionDefinition> {
    Parser { stream in
        let name: String
        switch stream.first {
        case .variable(let n): name = n; stream = stream.dropFirst()
        case .callRef(let n):  name = n; stream = stream.dropFirst()
        default: throw ParseError("Expected function name after 'func'")
        }
        guard stream.first == .lparen else { throw ParseError("Expected '(' in function definition") }
        stream = stream.dropFirst()
        let params = try varList().parse(&stream)
        try rparen_().parse(&stream)
        let body = try stmtBlock().parse(&stream)
        // Check for duplicate parameter names (corresponds to checkdup in awkgram.y)
        var seen = Set<String>()
        for p in params {
            guard seen.insert(p).inserted else {
                throw ParseError("Duplicate parameter '\(p)' in function '\(name)'")
            }
        }
        return FunctionDefinition(name: name, params: params, body: body)
    }
}

// varlist: (nothing) | VAR (',' VAR)*
// C: var_list — awkgram.y
private func varList() -> Parser<[String]> {
    Parser { stream in
        var params: [String] = []
        while case .variable(let n) = stream.first {
            params.append(n)
            stream = stream.dropFirst()
            if stream.first == .comma {
                stream = stream.dropFirst()
                try skipNL().parse(&stream)
            } else {
                break
            }
        }
        return params
    }
}

// A block: lbrace stmtlist rbrace
// C: action — awkgram.y
private func stmtBlock() -> Parser<[Statement]> {
    between(lbrace(), stmtList(), rbrace())
}

// MARK: - Statements

// stmtlist: stmt*  (left-recursive in yacc → iterative here)
// C: stmtlist — awkgram.y
private func stmtList() -> Parser<[Statement]> {
    lazy(stmt()).many.map { stmts in stmts.filter { if case .empty = $0 { return false }; return true } }
}

// C: stmt — awkgram.y
private func stmt() -> Parser<Statement> {
    Parser { stream in
        try skipSep().parse(&stream)
        switch stream.first {
        case .kwBreak:
            stream = stream.dropFirst(); try stEnd().parse(&stream); return .break_
        case .kwContinue:
            stream = stream.dropFirst(); try stEnd().parse(&stream); return .continue_
        case .kwNext:
            stream = stream.dropFirst(); try stEnd().parse(&stream); return .next
        case .kwNextfile:
            stream = stream.dropFirst(); try stEnd().parse(&stream); return .nextFile
        case .kwDo:
            return try parseDoWhile().parse(&stream)
        case .kwExit:
            return try parseExit().parse(&stream)
        case .kwFor:
            return try parseFor().parse(&stream)
        case .kwIf:
            return try parseIf().parse(&stream)
        case .lbrace:
            return .block(try stmtBlock().parse(&stream))
        case .kwReturn:
            return try parseReturn().parse(&stream)
        case .kwWhile:
            return try parseWhile().parse(&stream)
        case .semicolon:
            stream = stream.dropFirst(); try skipNL().parse(&stream); return .empty
        default:
            let s = try simpleStmt().parse(&stream)
            try stEnd().parse(&stream)
            return s
        }
    }
}

// MARK: - Control-flow statements

// C: do-while case in stmt — awkgram.y
private func parseDoWhile() -> Parser<Statement> {
    Parser { stream in
        guard stream.first == .kwDo else { throw ParseError("Expected 'do'") }
        stream = stream.dropFirst()
        try skipNL().parse(&stream)
        let body = try lazy(stmt()).parse(&stream)
        guard stream.first == .kwWhile else { throw ParseError("Expected 'while' after do-body") }
        stream = stream.dropFirst()
        guard stream.first == .lparen else { throw ParseError("Expected '(' after 'while'") }
        stream = stream.dropFirst()
        let cond = try pattern().parse(&stream)
        try rparen_().parse(&stream)
        try stEnd().parse(&stream)
        return .doWhile(body, cond.notnull())
    }
}

// C: exit case in stmt — awkgram.y
private func parseExit() -> Parser<Statement> {
    Parser { stream in
        guard stream.first == .kwExit else { throw ParseError("Expected 'exit'") }
        stream = stream.dropFirst()
        let expr: Expression? = isStEnd(stream.first) ? nil : try pattern().parse(&stream)
        try stEnd().parse(&stream)
        return .exit_(expr)
    }
}

// C: for case in stmt — awkgram.y
private func parseFor() -> Parser<Statement> {
    Parser { stream in
        guard stream.first == .kwFor else { throw ParseError("Expected 'for'") }
        stream = stream.dropFirst()
        guard stream.first == .lparen else { throw ParseError("Expected '(' after 'for'") }
        stream = stream.dropFirst()

        // Try for-in: VAR in ARRAY
        if case .variable(let vname) = stream.first {
            let peek2 = stream.dropFirst().first
            if peek2 == .kwIn {
                stream = stream.dropFirst()  // consume VAR
                stream = stream.dropFirst()  // consume in
                guard case .variable(let arrName) = stream.first else {
                    throw ParseError("Expected array name in for-in")
                }
                stream = stream.dropFirst()
                try rparen_().parse(&stream)
                try skipNL().parse(&stream)
                let body = try lazy(stmt()).parse(&stream)
                return .forIn(vname, arrName, body)
            }
        }

        // C-style: for (init; cond; incr)
        let init_: Statement? = stream.first == .semicolon
            ? nil : try simpleStmt().opt.parse(&stream)
        guard stream.first == .semicolon else { throw ParseError("Expected ';' in for") }
        stream = stream.dropFirst()
        try skipNL().parse(&stream)
        let cond: Expression? = stream.first == .semicolon
            ? nil : try pattern().opt.parse(&stream)
        guard stream.first == .semicolon else { throw ParseError("Expected ';' in for") }
        stream = stream.dropFirst()
        try skipNL().parse(&stream)
        let incr_: Statement? = stream.first == .rparen
            ? nil : try simpleStmt().opt.parse(&stream)
        try rparen_().parse(&stream)
        try skipNL().parse(&stream)
        let body = try lazy(stmt()).parse(&stream)
        return .for_(init_, cond?.notnull(), incr_, body)
    }
}

// C: if case in stmt — awkgram.y
private func parseIf() -> Parser<Statement> {
    Parser { stream in
        guard stream.first == .kwIf else { throw ParseError("Expected 'if'") }
        stream = stream.dropFirst()
        guard stream.first == .lparen else { throw ParseError("Expected '(' after 'if'") }
        stream = stream.dropFirst()
        let cond = try pattern().parse(&stream)
        try rparen_().parse(&stream)
        let then = try lazy(stmt()).parse(&stream)
        // optional else — must skip separators to find 'else'
        let saved = stream
        try skipSep().parse(&stream)
        if stream.first == .kwElse {
            stream = stream.dropFirst()
            try skipNL().parse(&stream)
            let else_ = try lazy(stmt()).parse(&stream)
            return .if_(cond.notnull(), then, else_)
        }
        stream = saved
        return .if_(cond.notnull(), then, nil)
    }
}

// C: return case in stmt — awkgram.y
private func parseReturn() -> Parser<Statement> {
    Parser { stream in
        guard stream.first == .kwReturn else { throw ParseError("Expected 'return'") }
        stream = stream.dropFirst()
        let expr: Expression? = isStEnd(stream.first) ? nil : try pattern().parse(&stream)
        try stEnd().parse(&stream)
        return .return_(expr)
    }
}

private func parseWhile() -> Parser<Statement> {
    Parser { stream in
        guard stream.first == .kwWhile else { throw ParseError("Expected 'while'") }
        stream = stream.dropFirst()
        guard stream.first == .lparen else { throw ParseError("Expected '(' after 'while'") }
        stream = stream.dropFirst()
        let cond = try pattern().parse(&stream)
        try rparen_().parse(&stream)
        try skipNL().parse(&stream)
        let body = try lazy(stmt()).parse(&stream)
        return .while_(cond.notnull(), body)
    }
}

// MARK: - Simple statements
// simple_stmt: print | delete | pattern-as-expression

private func simpleStmt() -> Parser<Statement> {
    Parser { stream in
        switch stream.first {
        case .kwPrint, .kwPrintf:
            return try parsePrintStmt().parse(&stream)
        case .kwDelete:
            stream = stream.dropFirst()
            return try parseDeleteStmt().parse(&stream)
        default:
            let expr = try pattern().parse(&stream)
            return .expression(expr)
        }
    }
}

// print prarg (| >> > term)?
private func parsePrintStmt() -> Parser<Statement> {
    Parser { stream in
        let kind: PrintKind
        switch stream.first {
        case .kwPrint:  kind = .print;  stream = stream.dropFirst()
        case .kwPrintf: kind = .printf; stream = stream.dropFirst()
        default: throw ParseError("Expected 'print' or 'printf'")
        }

        // prarg: empty | pplist | '(' plist ')'
        let args: [Expression]
        if stream.first == .lparen {
            // Ambiguous — could be grouped args or redirect target.
            // Try (plist) as the full argument list first.
            let saved = stream
            stream = stream.dropFirst()
            do {
                let list = try sepBy1(lazy(ppattern()), sep: comma_()).parse(&stream)
                if stream.first == .rparen {
                    stream = stream.dropFirst()
                    // If followed by a redirect operator, treat parens as grouping the args
                    if isRedirectOp(stream.first) {
                        args = list
                    } else {
                        args = list
                    }
                } else {
                    throw ParseError("not a simple plist")
                }
            } catch {
                stream = saved
                args = try sepBy(lazy(ppattern()), sep: comma_()).parse(&stream)
            }
        } else {
            args = try sepBy(lazy(ppattern()), sep: comma_()).parse(&stream)
        }

        // Optional redirect
        let dest: PrintDest?
        switch stream.first {
        case .pipe:
            stream = stream.dropFirst()
            dest = .pipe(try term().parse(&stream))
        case .appendOp:
            stream = stream.dropFirst()
            dest = .append(try term().parse(&stream))
        case .gtOp:
            stream = stream.dropFirst()
            dest = .redirect(try term().parse(&stream))
        default:
            dest = nil
        }

        return .print_(kind, args, dest)
    }
}

private func isRedirectOp(_ tok: AWKToken?) -> Bool {
    switch tok {
    case .pipe, .appendOp, .gtOp: return true
    default: return false
    }
}

// delete varname [ '[' patlist ']' ]
private func parseDeleteStmt() -> Parser<Statement> {
    Parser { stream in
        guard case .variable(let name) = stream.first else {
            throw ParseError("Expected variable name after 'delete'")
        }
        stream = stream.dropFirst()
        if stream.first == .lbracket {
            stream = stream.dropFirst()
            let keys = try sepBy1(lazy(pattern()), sep: comma_()).parse(&stream)
            guard stream.first == .rbracket else { throw ParseError("Expected ']' after subscript") }
            stream = stream.dropFirst()
            return .delete_(.element(name, keys))
        }
        return .delete_(.variable(name))
    }
}

// MARK: - Variable / varname parsers

// varname: VAR | ARG | VARNF
private func varname() -> Parser<Expression> {
    Parser { stream in
        switch stream.first {
        case .variable(let n): stream = stream.dropFirst(); return .variable(n)
        case .arg(let i):      stream = stream.dropFirst(); return .argument(i)
        case .varnf:           stream = stream.dropFirst(); return .varnf
        default: throw ParseError("Expected variable name")
        }
    }
}

// var: varname | varname '[' patlist ']' | IVAR | '@' term
private func var_() -> Parser<Expression> {
    Parser { stream in
        switch stream.first {
        case .ivar(let name):
            stream = stream.dropFirst()
            return .indirect(.variable(name))
        case .atSign:
            stream = stream.dropFirst()
            let inner = try parseExpr(&stream, minBP: BP.postfix + 1, getlinePipe: true)
            return .indirect(inner)
        default:
            let base = try varname().parse(&stream)
            if stream.first == .lbracket {
                stream = stream.dropFirst()
                let keys = try sepBy1(lazy(pattern()), sep: comma_()).parse(&stream)
                guard stream.first == .rbracket else { throw ParseError("Expected ']'") }
                stream = stream.dropFirst()
                guard case .variable(let n) = base else {
                    throw ParseError("Array subscript requires a named variable")
                }
                return .element(n, keys)
            }
            return base
        }
    }
}

// MARK: - Expression parser (Pratt / top-down operator precedence)
//
// Covers pattern, ppattern, and term from the original grammar.
// `getlinePipe` controls whether `cmd | getline` is permitted (false in print args).
//
// Binding powers — higher number = tighter binding.
// Derived from the %left/%right/%nonassoc declarations in awkgram.y
// (declarations listed from lowest to highest precedence in yacc).

private enum BP {
    static let assignment  = 10  // right-associative: rbp = 9
    static let ternary     = 20  // right-associative: rbp = 19
    static let logicalOr   = 30
    static let logicalAnd  = 40
    static let getlinePipe = 55  // '|' followed by getline
    static let comparison  = 60  // ==, !=, <, <=, >, >=, ~, !~, in
    static let concat      = 100 // implicit concatenation
    static let addSub      = 110
    static let mulDiv      = 120
    static let power       = 140 // right-associative: rbp = 139
    static let postfix     = 160 // postfix ++ --
}

private func pattern() -> Parser<Expression> {
    Parser { s in try parseExpr(&s, minBP: 0, getlinePipe: true) }
}

private func ppattern() -> Parser<Expression> {
    Parser { s in try parseExpr(&s, minBP: 0, getlinePipe: false) }
}

private func term() -> Parser<Expression> { ppattern() }

// MARK: Pratt parser core

private func parseExpr(_ stream: inout TokenStream, minBP: Int, getlinePipe: Bool) throws -> Expression {
    var lhs = try parsePrefix(&stream, getlinePipe: getlinePipe)
    while true {
        guard let lbp = infixBP(stream.first, getlinePipe: getlinePipe), lbp >= minBP else { break }
        lhs = try parseInfix(&stream, lhs: lhs, lbp: lbp, getlinePipe: getlinePipe)
    }
    return lhs
}

/// Left binding power of the current token when used as an infix operator.
/// Returns nil if the token is not an infix operator at the current context.
private func infixBP(_ tok: AWKToken?, getlinePipe: Bool) -> Int? {
    guard let tok else { return nil }
    switch tok {
    case .assignOp, .addEqOp, .subEqOp, .mulEqOp, .divEqOp, .modEqOp, .powEqOp:
        return BP.assignment
    case .question:
        return BP.ternary
    case .borOp:
        return BP.logicalOr
    case .andOp:
        return BP.logicalAnd
    case .pipe where getlinePipe:
        return BP.getlinePipe  // only if | getline is allowed
    case .eqOp, .neOp, .ltOp, .leOp, .gtOp, .geOp, .matchOp, .notMatchOp, .kwIn:
        return BP.comparison
    case .plus, .minus:
        return BP.addSub
    case .star, .percent:
        return BP.mulDiv
    case .slash:
        return BP.mulDiv        // division (vs. regex is resolved by the lexer)
    case .powerOp:
        return BP.power
    case .incrOp, .decrOp:
        return BP.postfix
    default:
        // Implicit concatenation: if this token can start a term, it "infix-concatenates"
        return canStartTerm(tok) ? BP.concat : nil
    }
}

private func parseInfix(
    _ stream: inout TokenStream,
    lhs: Expression,
    lbp: Int,
    getlinePipe: Bool
) throws -> Expression {
    let tok = stream.first!          // caller verified lbp is non-nil ∴ tok exists

    switch tok {
    // Assignment (right-associative)
    case .assignOp, .addEqOp, .subEqOp, .mulEqOp, .divEqOp, .modEqOp, .powEqOp:
        let op = assignOp(tok)!
        stream = stream.dropFirst()
        guard let lv = lhs.asLValue() else { throw ParseError("Left side of '\(op.rawValue)' must be assignable") }
        let rhs = try parseExpr(&stream, minBP: BP.assignment - 1, getlinePipe: true)
        return .assign(op, lv, rhs)

    // Ternary ?:
    case .question:
        stream = stream.dropFirst()
        let then = try parseExpr(&stream, minBP: 0, getlinePipe: true)
        guard stream.first == .colon else { throw ParseError("Expected ':' in ternary expression") }
        stream = stream.dropFirst()
        let else_ = try parseExpr(&stream, minBP: BP.ternary - 1, getlinePipe: true)
        return .ternary(lhs.notnull(), then, else_)

    // Logical OR
    case .borOp:
        stream = stream.dropFirst(); try skipNL().parse(&stream)
        let rhs = try parseExpr(&stream, minBP: BP.logicalOr + 1, getlinePipe: getlinePipe)
        return .logicalOr(lhs.notnull(), rhs.notnull())

    // Logical AND
    case .andOp:
        stream = stream.dropFirst(); try skipNL().parse(&stream)
        let rhs = try parseExpr(&stream, minBP: BP.logicalAnd + 1, getlinePipe: getlinePipe)
        return .logicalAnd(lhs.notnull(), rhs.notnull())

    // Pipe to getline: cmd | getline [var]
    case .pipe:
        guard stream.dropFirst().first == .kwGetline else {
            // '|' in this position with getlinePipe=true but not followed by getline
            // fall through to implicit concat (shouldn't happen in well-formed input)
            throw ParseError("'|' requires 'getline' in expression context")
        }
        stream = stream.dropFirst()  // consume '|'
        stream = stream.dropFirst()  // consume 'getline'
        let lval: LValue? = try var_().opt.parse(&stream).flatMap { $0.asLValue() }
        return .getlinePipe(lval, lhs)

    // Comparison operators (non-associative)
    case .eqOp:
        stream = stream.dropFirst()
        return .equal(lhs, try parseExpr(&stream, minBP: BP.comparison + 1, getlinePipe: getlinePipe))
    case .neOp:
        stream = stream.dropFirst()
        return .notEqual(lhs, try parseExpr(&stream, minBP: BP.comparison + 1, getlinePipe: getlinePipe))
    case .ltOp:
        stream = stream.dropFirst()
        return .lessThan(lhs, try parseExpr(&stream, minBP: BP.comparison + 1, getlinePipe: getlinePipe))
    case .leOp:
        stream = stream.dropFirst()
        return .lessEqual(lhs, try parseExpr(&stream, minBP: BP.comparison + 1, getlinePipe: getlinePipe))
    case .gtOp:
        stream = stream.dropFirst()
        return .greaterThan(lhs, try parseExpr(&stream, minBP: BP.comparison + 1, getlinePipe: getlinePipe))
    case .geOp:
        stream = stream.dropFirst()
        return .greaterEqual(lhs, try parseExpr(&stream, minBP: BP.comparison + 1, getlinePipe: getlinePipe))
    case .matchOp:
        stream = stream.dropFirst()
        return .patternMatch(lhs, try regexOrExpr(&stream, getlinePipe: getlinePipe))
    case .notMatchOp:
        stream = stream.dropFirst()
        return .patternNotMatch(lhs, try regexOrExpr(&stream, getlinePipe: getlinePipe))
    case .kwIn:
        stream = stream.dropFirst()
        guard case .variable(let arrName) = stream.first else {
            throw ParseError("Expected array name after 'in'")
        }
        stream = stream.dropFirst()
        return .inArray(lhs, arrName)

    // Arithmetic
    case .plus:
        stream = stream.dropFirst()
        return .add(lhs, try parseExpr(&stream, minBP: BP.addSub + 1, getlinePipe: getlinePipe))
    case .minus:
        stream = stream.dropFirst()
        return .subtract(lhs, try parseExpr(&stream, minBP: BP.addSub + 1, getlinePipe: getlinePipe))
    case .star:
        stream = stream.dropFirst()
        return .multiply(lhs, try parseExpr(&stream, minBP: BP.mulDiv + 1, getlinePipe: getlinePipe))
    case .slash:
        stream = stream.dropFirst()
        // Disambiguate /= (division-assign) from plain division
        if stream.first == .assignOp {
            stream = stream.dropFirst()
            guard let lv = lhs.asLValue() else { throw ParseError("Left side of '/=' must be assignable") }
            return .assign(.divSet, lv, try parseExpr(&stream, minBP: BP.assignment - 1, getlinePipe: true))
        }
        return .divide(lhs, try parseExpr(&stream, minBP: BP.mulDiv + 1, getlinePipe: getlinePipe))
    case .percent:
        stream = stream.dropFirst()
        return .modulo(lhs, try parseExpr(&stream, minBP: BP.mulDiv + 1, getlinePipe: getlinePipe))
    case .powerOp:
        stream = stream.dropFirst()
        return .power(lhs, try parseExpr(&stream, minBP: BP.power - 1, getlinePipe: getlinePipe)) // right-assoc

    // Postfix ++ / --
    case .incrOp:
        stream = stream.dropFirst()
        guard let lv = lhs.asLValue() else { throw ParseError("'++' requires assignable operand") }
        return .postIncrement(lv)
    case .decrOp:
        stream = stream.dropFirst()
        guard let lv = lhs.asLValue() else { throw ParseError("'--' requires assignable operand") }
        return .postDecrement(lv)

    default:
        // Implicit concatenation
        let rhs = try parseExpr(&stream, minBP: BP.concat + 1, getlinePipe: getlinePipe)
        return .concat(lhs, rhs)
    }
}

// MARK: Prefix (nud) parser

private func parsePrefix(_ stream: inout TokenStream, getlinePipe: Bool) throws -> Expression {
    guard let tok = stream.first else { throw ParseError("Unexpected end of input") }
    switch tok {

    // Literals
    case .number(let n):
        stream = stream.dropFirst()
        return .number(n)

    case .string(let s):
        stream = stream.dropFirst()
        // Adjacent STRING tokens are concatenated at parse time (string rule in grammar)
        var result = s
        while case .string(let s2) = stream.first { result += s2; stream = stream.dropFirst() }
        return .string(result)

    case .regexLiteral(let s):
        stream = stream.dropFirst()
        return .regexMatch(s)    // bare /re/ matches against $0

    // Variables
    case .varnf:
        stream = stream.dropFirst(); return .varnf
    case .variable, .arg, .ivar, .atSign:
        return try var_().parse(&stream)

    // Function call: CALL '(' args ')'
    case .callRef(let name):
        stream = stream.dropFirst()
        guard stream.first == .lparen else { throw ParseError("Expected '(' after function '\(name)'") }
        stream = stream.dropFirst()
        let args: [Expression] = stream.first == .rparen
            ? [] : try sepBy1(lazy(pattern()), sep: comma_()).parse(&stream)
        guard stream.first == .rparen else { throw ParseError("Expected ')' in call to '\(name)'") }
        stream = stream.dropFirst()
        return .userCall(name, args)

    // Field access: $expr  — use postfix+1 so $a++ parses as ($a)++ not $(a++)
    case .dollar:
        stream = stream.dropFirst()
        let inner = try parseExpr(&stream, minBP: BP.postfix + 1, getlinePipe: getlinePipe)
        return .field(inner)

    // Grouping or (plist) in array
    case .lparen:
        stream = stream.dropFirst()
        let first = try parseExpr(&stream, minBP: 0, getlinePipe: true)
        if stream.first == .comma {
            // Collect a comma-separated list — only valid before 'in'
            var items = [first]
            while stream.first == .comma {
                stream = stream.dropFirst(); try skipNL().parse(&stream)
                items.append(try parseExpr(&stream, minBP: 0, getlinePipe: true))
            }
            guard stream.first == .rparen else { throw ParseError("Expected ')' closing tuple") }
            stream = stream.dropFirst()
            guard stream.first == .kwIn else { throw ParseError("'(list)' must be followed by 'in'") }
            stream = stream.dropFirst()
            guard case .variable(let arrName) = stream.first else {
                throw ParseError("Expected array name after 'in'")
            }
            stream = stream.dropFirst()
            return .inArrayTuple(items, arrName)
        }
        guard stream.first == .rparen else { throw ParseError("Expected ')' in grouped expression") }
        stream = stream.dropFirst()
        return first

    // Unary operators
    case .minus:
        stream = stream.dropFirst()
        return .negate(try parseExpr(&stream, minBP: BP.mulDiv, getlinePipe: getlinePipe))
    case .plus:
        stream = stream.dropFirst()
        return .unaryPlus(try parseExpr(&stream, minBP: BP.mulDiv, getlinePipe: getlinePipe))
    case .notOp:
        stream = stream.dropFirst()
        if case .regexLiteral(let s) = stream.first {
            stream = stream.dropFirst()
            return .logicalNot(.regexMatch(s))
        }
        let operand = try parseExpr(&stream, minBP: BP.mulDiv, getlinePipe: getlinePipe)
        return .logicalNot(operand.notnull())

    // Prefix ++ / --
    case .incrOp:
        stream = stream.dropFirst()
        let lv = try parseLValue(&stream, getlinePipe: getlinePipe)
        return .preIncrement(lv)
    case .decrOp:
        stream = stream.dropFirst()
        let lv = try parseLValue(&stream, getlinePipe: getlinePipe)
        return .preDecrement(lv)

    // Getline
    case .kwGetline:
        return try parseGetline(&stream)

    // Builtin functions (BLTIN token)
    case .bltin(let id):
        stream = stream.dropFirst()
        if stream.first == .lparen {
            stream = stream.dropFirst()
            let args: [Expression] = stream.first == .rparen
                ? [] : try sepBy1(lazy(pattern()), sep: comma_()).parse(&stream)
            guard stream.first == .rparen else { throw ParseError("Expected ')' in builtin call") }
            stream = stream.dropFirst()
            return .builtinCall(id, args)
        }
        // Builtin with no parens: takes $0 implicitly
        return .builtinCall(id, [.field(.number(0))])

    // Named builtin keywords
    case .kwClose:
        stream = stream.dropFirst()
        let target = try parseExpr(&stream, minBP: BP.postfix, getlinePipe: false)
        return .closeExpr(target)

    case .kwIndex:
        stream = stream.dropFirst()
        guard stream.first == .lparen else { throw ParseError("Expected '(' after index") }
        stream = stream.dropFirst()
        let haystack = try parseExpr(&stream, minBP: 0, getlinePipe: false)
        try comma_().parse(&stream)
        let needle = try parseExpr(&stream, minBP: 0, getlinePipe: false)
        guard stream.first == .rparen else { throw ParseError("Expected ')' in index()") }
        stream = stream.dropFirst()
        return .indexExpr(haystack, needle)

    case .kwMatch:
        stream = stream.dropFirst()
        guard stream.first == .lparen else { throw ParseError("Expected '(' after match") }
        stream = stream.dropFirst()
        let str = try parseExpr(&stream, minBP: 0, getlinePipe: false)
        try comma_().parse(&stream)
        let re = try regexOrExpr(&stream, getlinePipe: false)
        guard stream.first == .rparen else { throw ParseError("Expected ')' in match()") }
        stream = stream.dropFirst()
        return .matchFuncExpr(str, re)

    case .kwSplit:
        stream = stream.dropFirst()
        guard stream.first == .lparen else { throw ParseError("Expected '(' after split") }
        stream = stream.dropFirst()
        let str = try parseExpr(&stream, minBP: 0, getlinePipe: false)
        try comma_().parse(&stream)
        guard case .variable(let arrName) = stream.first else {
            throw ParseError("Expected array variable in split()")
        }
        stream = stream.dropFirst()
        let sep: Expression?
        if stream.first == .comma {
            stream = stream.dropFirst(); try skipNL().parse(&stream)
            sep = try regexOrExpr(&stream, getlinePipe: false)
        } else { sep = nil }
        guard stream.first == .rparen else { throw ParseError("Expected ')' in split()") }
        stream = stream.dropFirst()
        return .splitExpr(str, arrName, sep)

    case .kwSprintf:
        stream = stream.dropFirst()
        guard stream.first == .lparen else { throw ParseError("Expected '(' after sprintf") }
        stream = stream.dropFirst()
        let args = try sepBy1(lazy(pattern()), sep: comma_()).parse(&stream)
        guard stream.first == .rparen else { throw ParseError("Expected ')' in sprintf()") }
        stream = stream.dropFirst()
        return .sprintfExpr(args)

    case .kwSub, .kwGsub:
        let kind: SubKind = (tok == .kwSub) ? .sub : .gsub
        stream = stream.dropFirst()
        guard stream.first == .lparen else { throw ParseError("Expected '(' after sub/gsub") }
        stream = stream.dropFirst()
        let re = try regexOrExpr(&stream, getlinePipe: false)
        try comma_().parse(&stream)
        let repl = try parseExpr(&stream, minBP: 0, getlinePipe: false)
        let target: LValue
        if stream.first == .comma {
            stream = stream.dropFirst(); try skipNL().parse(&stream)
            let tExpr = try var_().parse(&stream)
            guard let lv = tExpr.asLValue() else { throw ParseError("sub/gsub target must be an lvalue") }
            target = lv
        } else {
            target = .field(.number(0))   // default target is $0
        }
        guard stream.first == .rparen else { throw ParseError("Expected ')' in sub/gsub()") }
        stream = stream.dropFirst()
        return .subExpr(kind, re, repl, target)

    case .kwSubstr:
        stream = stream.dropFirst()
        guard stream.first == .lparen else { throw ParseError("Expected '(' after substr") }
        stream = stream.dropFirst()
        let str = try parseExpr(&stream, minBP: 0, getlinePipe: false)
        try comma_().parse(&stream)
        let start = try parseExpr(&stream, minBP: 0, getlinePipe: false)
        let len: Expression?
        if stream.first == .comma {
            stream = stream.dropFirst(); try skipNL().parse(&stream)
            len = try parseExpr(&stream, minBP: 0, getlinePipe: false)
        } else { len = nil }
        guard stream.first == .rparen else { throw ParseError("Expected ')' in substr()") }
        stream = stream.dropFirst()
        return .substrExpr(str, start, len)

    default:
        throw ParseError("Unexpected token in expression: \(tok)")
    }
}

// MARK: Helper parsers used in the Pratt parser

// Regex literal or arbitrary expression (used after ~ and !~, and in sub/match args)
private func regexOrExpr(_ stream: inout TokenStream, getlinePipe: Bool) throws -> Expression {
    if case .regexLiteral(let s) = stream.first {
        stream = stream.dropFirst()
        return .regexMatch(s)
    }
    return try parseExpr(&stream, minBP: BP.comparison + 1, getlinePipe: getlinePipe)
}

// getline: GETLINE [var] [< file]
private func parseGetline(_ stream: inout TokenStream) throws -> Expression {
    guard stream.first == .kwGetline else { throw ParseError("Expected 'getline'") }
    stream = stream.dropFirst()
    let lval: LValue? = try var_().opt.parse(&stream).flatMap { $0.asLValue() }
    if stream.first == .ltOp {
        stream = stream.dropFirst()
        let src = try parseExpr(&stream, minBP: BP.comparison + 1, getlinePipe: false)
        return .getlineFrom(lval, src)
    }
    return .getline(lval)
}

private func parseLValue(_ stream: inout TokenStream, getlinePipe: Bool) throws -> LValue {
    // Use postfix+1 so that ++$a grabs $a as the lvalue, not ($a)++
    let expr = try parseExpr(&stream, minBP: BP.postfix + 1, getlinePipe: getlinePipe)
    guard let lv = expr.asLValue() else { throw ParseError("Expected an assignable location") }
    return lv
}

// Map a token to its AssignOp
private func assignOp(_ tok: AWKToken) -> AssignOp? {
    switch tok {
    case .assignOp: return .set
    case .addEqOp:  return .addSet
    case .subEqOp:  return .subSet
    case .mulEqOp:  return .mulSet
    case .divEqOp:  return .divSet
    case .modEqOp:  return .modSet
    case .powEqOp:  return .powSet
    default:        return nil
    }
}

// Returns true if this token can begin a prefix expression (term), enabling implicit concat.
private func canStartTerm(_ tok: AWKToken) -> Bool {
    switch tok {
    case .number, .string, .regexLiteral,
         .variable, .ivar, .varnf, .arg, .callRef, .bltin,
         .lparen, .dollar, .minus, .plus, .notOp, .incrOp, .decrOp,
         .kwGetline, .kwClose, .kwIndex, .kwMatch, .kwSplit,
         .kwSprintf, .kwSub, .kwGsub, .kwSubstr, .atSign:
        return true
    default:
        return false
    }
}
