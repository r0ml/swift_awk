// AWKLexer.swift
// Tokenizes an AWK program string into [AWKToken].
// Corresponds to lex.c in one-true-awk.

struct LexError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
    init(_ msg: String) { message = msg }
}

struct AWKLexer {
    private let source: [Character]
    private var pos: Int = 0
    private(set) var line: Int = 1
    // Bracket-depth counters for mismatch detection
    private var braceCnt: Int = 0
    private var brackCnt: Int = 0
    private var parenCnt: Int = 0

    init(_ program: String) { source = Array(program) }

    // MARK: - Public entry point

    mutating func tokenize() throws -> [AWKToken] {
        var result: [AWKToken] = []
        var last: AWKToken? = nil

        while !atEnd {
            guard let tok = try scan(regexOK: isRegexContext(last)) else { continue }
            // Replicate the C lexer's } behaviour: always inject ';' before '}'
            // so that `{ print }` parses as `{ print ; }`.
            if case .rbrace = tok, !isTerminator(last) {
                result.append(.semicolon)
            }
            result.append(tok)
            last = tok
        }
        result.append(.eof)
        return result
    }

    // MARK: - Input primitives

    private var atEnd: Bool { pos >= source.count }
    private func cur() -> Character? { atEnd ? nil : source[pos] }
    private func peek(_ n: Int = 1) -> Character? {
        let i = pos + n; return i < source.count ? source[i] : nil
    }

    @discardableResult
    private mutating func eat() -> Character? {
        guard !atEnd else { return nil }
        let c = source[pos]; pos += 1
        if c == "\n" { line += 1 }
        return c
    }

    // MARK: - Context helpers

    /// Returns true when '/' should start a regex rather than divide.
    /// After a value-producing token (number, identifier, ')', ']', '++', '--')
    /// '/' is division; everywhere else it starts a regex literal.
    private func isRegexContext(_ last: AWKToken?) -> Bool {
        guard let last else { return true }
        switch last {
        case .number, .string, .regexLiteral,
             .variable, .callRef, .varnf, .bltin,
             .rparen, .rbracket, .incrOp, .decrOp:
            return false
        default:
            return true
        }
    }

    private func isTerminator(_ tok: AWKToken?) -> Bool {
        guard let tok else { return true }
        switch tok { case .semicolon, .newline: return true; default: return false }
    }

    // MARK: - Main scanner

    private mutating func scan(regexOK: Bool) throws -> AWKToken? {
        while let c = cur() {
            switch c {
            case " ", "\t", "\r":
                eat()

            case "\n":
                eat()
                return .newline

            case "#":
                // Strip comment to end of line; don't consume the \n itself.
                while let ch = cur(), ch != "\n" { eat() }

            case "\\":
                // Line continuation: \ followed by \n (or \r\n) — skip both.
                if peek() == "\n" { eat(); eat() }
                else if peek() == "\r" && peek(2) == "\n" { eat(); eat(); eat() }
                else {
                    eat()
                    throw LexError("bare '\\' at line \(line)")
                }

            case "\"":
                eat()
                return try scanString()

            case "/":
                eat()
                if regexOK { return try scanRegex() }
                if cur() == "=" { eat(); return .divEqOp }
                return .slash

            default:
                if isDigit(c) || (c == "." && isDigit(peek() ?? " ")) {
                    return try scanNumber()
                }
                if isLetter(c) { return scanWord() }
                return try scanSymbol()
            }
        }
        return nil
    }

    // MARK: - Numbers
    // Handles integers, decimals, and scientific notation (e.g. 1.5e+3).

    private mutating func scanNumber() throws -> AWKToken {
        let start = pos
        if cur() == "." {
            // leading-dot float: .5
            eat()
            while isDigit(cur() ?? " ") { eat() }
        } else {
            while isDigit(cur() ?? " ") { eat() }
            if cur() == "." {
                eat()
                while isDigit(cur() ?? " ") { eat() }
            }
        }
        // Optional exponent
        if cur() == "e" || cur() == "E" {
            let saved = pos
            eat()
            if cur() == "+" || cur() == "-" { eat() }
            if isDigit(cur() ?? " ") {
                while isDigit(cur() ?? " ") { eat() }
            } else {
                pos = saved   // not an exponent; back up
            }
        }
        let s = String(source[start..<pos])
        guard let d = Double(s) else { throw LexError("invalid number '\(s)' at line \(line)") }
        return .number(d)
    }

    // MARK: - String literals

    private mutating func scanString() throws -> AWKToken {
        var result = ""
        while let c = cur(), c != "\"" {
            eat()
            if c == "\n" || c == "\r" {
                throw LexError("unterminated string at line \(line)")
            }
            if c != "\\" {
                result.append(c)
                continue
            }
            // Escape sequence
            guard let esc = eat() else { throw LexError("unexpected end after '\\'") }
            switch esc {
            case "\n", "\r": break      // line continuation inside string — skip
            case "\"": result.append("\"")
            case "n":  result.append("\n")
            case "t":  result.append("\t")
            case "f":  result.append("\u{0C}")
            case "r":  result.append("\r")
            case "b":  result.append("\u{08}")
            case "v":  result.append("\u{0B}")
            case "a":  result.append("\u{07}")
            case "\\": result.append("\\")
            case "0","1","2","3","4","5","6","7":   // octal
                var n = esc.wholeNumberValue!
                if isOctal(cur() ?? " ") { n = 8 * n + eat()!.wholeNumberValue! }
                if isOctal(cur() ?? " ") { n = 8 * n + eat()!.wholeNumberValue! }
                result.append(Character(Unicode.Scalar(n & 0xFF)!))
            case "x":                               // hex
                var hexStr = ""
                while let h = cur(), h.isHexDigit { hexStr.append(h); eat() }
                if let n = UInt32(hexStr, radix: 16), let sc = Unicode.Scalar(n) {
                    result.append(Character(sc))
                }
            default:
                result.append(esc)
            }
        }
        guard cur() == "\"" else { throw LexError("unterminated string at line \(line)") }
        eat()   // consume closing "
        return .string(result)
    }

    // MARK: - Regex literals

    private mutating func scanRegex() throws -> AWKToken {
        var result = ""
        while let c = cur(), c != "/" {
            if c == "\n" { throw LexError("newline in regex at line \(line)") }
            eat()
            if c == "\\" {
                guard let next = eat() else { throw LexError("unexpected end in regex") }
                result.append("\\")
                result.append(next)
            } else {
                result.append(c)
            }
        }
        guard cur() == "/" else { throw LexError("unterminated regex at line \(line)") }
        eat()   // consume closing /
        return .regexLiteral(result)
    }

    // MARK: - Identifiers and keywords

    private mutating func scanWord() -> AWKToken {
        let start = pos
        while let c = cur(), isLetter(c) || isDigit(c) { eat() }
        let word = String(source[start..<pos])
        return resolveKeyword(word, nextIsLParen: cur() == "(")
    }

    private func resolveKeyword(_ w: String, nextIsLParen: Bool) -> AWKToken {
        switch w {
        // Program structure
        case "BEGIN":               return .xbegin
        case "END":                 return .xend
        case "func", "function":    return .funcKeyword
        // Special variable
        case "NF":                  return .varnf
        // Control flow
        case "break":               return .kwBreak
        case "continue":            return .kwContinue
        case "delete":              return .kwDelete
        case "do":                  return .kwDo
        case "else":                return .kwElse
        case "exit":                return .kwExit
        case "for":                 return .kwFor
        case "if":                  return .kwIf
        case "in":                  return .kwIn
        case "next":                return .kwNext
        case "nextfile":            return .kwNextfile
        case "return":              return .kwReturn
        case "while":               return .kwWhile
        // I/O keywords
        case "getline":             return .kwGetline
        case "print":               return .kwPrint
        case "printf":              return .kwPrintf
        case "close":               return .kwClose
        // String functions (grammar-level keywords)
        case "gsub":                return .kwGsub
        case "index":               return .kwIndex
        case "match":               return .kwMatch
        case "split":               return .kwSplit
        case "sprintf":             return .kwSprintf
        case "sub":                 return .kwSub
        case "substr":              return .kwSubstr
        // Builtin functions
        case "atan2":               return .bltin(.atan2)
        case "cos":                 return .bltin(.cos)
        case "exp":                 return .bltin(.exp)
        case "fflush":              return .bltin(.fflush)
        case "int":                 return .bltin(.int_)
        case "length":              return .bltin(.length)
        case "log":                 return .bltin(.log)
        case "rand":                return .bltin(.rand)
        case "sin":                 return .bltin(.sin)
        case "sqrt":                return .bltin(.sqrt)
        case "srand":               return .bltin(.srand)
        case "system":              return .bltin(.system)
        case "tolower":             return .bltin(.tolower)
        case "toupper":             return .bltin(.toupper)
        // User-defined: CALL if followed by '(', otherwise VAR
        default:
            return nextIsLParen ? .callRef(w) : .variable(w)
        }
    }

    // MARK: - Operators and punctuation

    private mutating func scanSymbol() throws -> AWKToken {
        guard let c = eat() else { throw LexError("unexpected end of input") }
        switch c {
        case "&":
            guard cur() == "&" else { throw LexError("bare '&' is not valid AWK at line \(line)") }
            eat(); return .andOp
        case "|":
            if cur() == "|" { eat(); return .borOp }
            return .pipe
        case "!":
            if cur() == "=" { eat(); return .neOp }
            if cur() == "~" { eat(); return .notMatchOp }
            return .notOp
        case "~":
            return .matchOp
        case "<":
            if cur() == "=" { eat(); return .leOp }
            return .ltOp
        case "=":
            if cur() == "=" { eat(); return .eqOp }
            return .assignOp
        case ">":
            if cur() == "=" { eat(); return .geOp }
            if cur() == ">" { eat(); return .appendOp }
            return .gtOp
        case "+":
            if cur() == "+" { eat(); return .incrOp }
            if cur() == "=" { eat(); return .addEqOp }
            return .plus
        case "-":
            if cur() == "-" { eat(); return .decrOp }
            if cur() == "=" { eat(); return .subEqOp }
            return .minus
        case "*":
            if cur() == "=" { eat(); return .mulEqOp }
            if cur() == "*" {   // ** or **=
                eat()
                if cur() == "=" { eat(); return .powEqOp }
                return .powerOp
            }
            return .star
        case "%":
            if cur() == "=" { eat(); return .modEqOp }
            return .percent
        case "^":
            if cur() == "=" { eat(); return .powEqOp }
            return .powerOp
        case "$":
            return .dollar
        case ";":  return .semicolon
        case ",":  return .comma
        case "?":  return .question
        case ":":  return .colon
        case "@":  return .atSign
        case "{":
            braceCnt += 1
            return .lbrace
        case "}":
            braceCnt -= 1
            if braceCnt < 0 { throw LexError("extra '}' at line \(line)") }
            return .rbrace
        case "(":
            parenCnt += 1
            return .lparen
        case ")":
            parenCnt -= 1
            if parenCnt < 0 { throw LexError("extra ')' at line \(line)") }
            return .rparen
        case "[":
            brackCnt += 1
            return .lbracket
        case "]":
            brackCnt -= 1
            if brackCnt < 0 { throw LexError("extra ']' at line \(line)") }
            return .rbracket
        default:
            throw LexError("unexpected character '\(c)' at line \(line)")
        }
    }

    // MARK: - Character classification (ASCII-only, matching C isdigit/isalpha)

    private func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
    private func isOctal(_ c: Character) -> Bool { c >= "0" && c <= "7" }
    private func isLetter(_ c: Character) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_"
    }
}
