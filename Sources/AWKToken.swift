// AWKToken.swift
// Token types produced by the AWK lexer.
// Corresponds to the %token declarations in awkgram.y and the keyword table in lex.c.

// MARK: - Builtin function identifiers (FXXX constants from awk.h)

enum AWKBuiltinID: Int, Equatable {
    case length  = 1
    case sqrt    = 2
    case exp     = 3
    case log     = 4
    case int_    = 5
    case system  = 6
    case rand    = 7
    case srand   = 8
    case sin     = 9
    case cos     = 10
    case atan2   = 11
    case toupper = 12
    case tolower = 13
    case fflush  = 14
}

// MARK: - Token

enum AWKToken: Equatable {
    // --- Literal values ---
    case number(Double)           // NUMBER
    case string(String)           // STRING  (escape-processed)
    case regexLiteral(String)     // REGEXPR (contents of /.../

    // --- Named entities resolved by the lexer ---
    case variable(String)         // VAR   — plain variable reference
    case ivar(String)             // IVAR  — indirect variable ($$n form)
    case varnf                    // VARNF — special $NF reference
    case callRef(String)          // CALL  — function name in call position
    case arg(Int)                 // ARG   — formal parameter (0-based index)
    case bltin(AWKBuiltinID)      // BLTIN — builtin function identifier

    // --- Program structure ---
    case xbegin                   // XBEGIN  (BEGIN)
    case xend                     // XEND    (END)
    case funcKeyword              // FUNC / function

    // --- Control-flow keywords ---
    case kwIf                     // IF
    case kwElse                   // ELSE
    case kwWhile                  // WHILE
    case kwFor                    // FOR
    case kwDo                     // DO
    case kwBreak                  // BREAK
    case kwContinue               // CONTINUE
    case kwNext                   // NEXT
    case kwNextfile               // NEXTFILE
    case kwReturn                 // RETURN
    case kwExit                   // EXIT
    case kwDelete                 // DELETE
    case kwIn                     // IN

    // --- I/O keywords ---
    case kwPrint                  // PRINT
    case kwPrintf                 // PRINTF
    case kwGetline                // GETLINE

    // --- String-function keywords ---
    case kwSprintf                // SPRINTF
    case kwSub                    // SUB
    case kwGsub                   // GSUB
    case kwIndex                  // INDEX
    case kwSplit                  // SPLIT
    case kwSubstr                 // SUBSTR
    case kwMatch                  // MATCHFCN
    case kwClose                  // CLOSE

    // --- Operators ---
    case andOp                    // AND   (&&)
    case borOp                    // BOR   (||)
    case appendOp                 // APPEND (>>)
    case matchOp                  // MATCHOP  (~)
    case notMatchOp               // MATCHOP  (!~)
    case eqOp                     // EQ   (==)
    case neOp                     // NE   (!=)
    case ltOp                     // LT   (<)
    case leOp                     // LE   (<=)
    case gtOp                     // GT   (>)
    case geOp                     // GE   (>=)
    case assignOp                 // ASSIGN (=)
    case addEqOp                  // ADDEQ  (+=)
    case subEqOp                  // SUBEQ  (-=)
    case mulEqOp                  // MULTEQ (*=)
    case divEqOp                  // DIVEQ  (/=)
    case modEqOp                  // MODEQ  (%=)
    case powEqOp                  // POWEQ  (^=)
    case powerOp                  // POWER  (^ or **)
    case incrOp                   // INCR   (++)
    case decrOp                   // DECR   (--)

    // --- Punctuation ---
    case newline                  // NL   (\n significant in AWK)
    case semicolon                // ';'
    case comma                    // ','
    case lbrace                   // '{'
    case rbrace                   // '}'
    case lparen                   // '('
    case rparen                   // ')'
    case lbracket                 // '['
    case rbracket                 // ']'
    case pipe                     // '|'
    case slash                    // '/'  (division; regex literals → .regexLiteral)
    case question                 // '?'
    case colon                    // ':'
    case dollar                   // '$'
    case plus                     // '+'
    case minus                    // '-'
    case star                     // '*'
    case percent                  // '%'
    case notOp                    // '!'  (NOT / logical-not)
    case atSign                   // '@'  (INDIRECT — gawk/one-true-awk extension)

    case eof
}
