// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

import CMigration
import Foundation

struct CallFrame {
    let funcName: String
    let paramNames: [String]   // formal parameter names
    var cells: [Cell]       // one cell per parameter + extra locals
  var retval: Cell = EmptyCell()
}

actor RuntimeState {
  static let shared = RuntimeState()

  var curpfile = 0
  var symtab : [String : Cell] = [:]

  var options = awk.CommandOptions()

  // FIXME: perhaps I should only store one or the other (fields or record) and the other one is
  // calculated upon get; and regenerates upon set
  var fldtab : [String] = [] {
    didSet {
      donerec = false
    }
  }

  var record : String?  /* points to $0 */ {
    didSet {
      donefld = false
      donerec = true
    }
  }

  var dbg = 0
  
  var yyin : FileDescriptor?
  var srand_seed : UInt32 = 1
  var inputFS : String = " "
  var lineno : Int = 0    // line number in awk program
  var errorflag = false  // 1 if error has occurred
  var donefld = false  // true if record broken into fields
  var donerec = true  // true if record is valid (no fld has changed
  var ARGVtab : [Cell] = [] // symbol table containing ARGV[...]
  var ENVtab : [String : Cell] = [:] // symbol table containing ENVIRON[...]
  var callStack: [CallFrame] = []
  var inEndBlock = false   // disables donefld update in END


  // MARK: Function registry (populated before execution)
  var functions: [String: FunctionDefinition] = [:]

  // MARK: I/O
  var openFiles: [AWKFile] = []
  var inputFiles: [AWKFile] = []   // queue of input files/stdin

  // MARK: Range-pattern state
  var pairstack: [Bool] = []


  var FS : String = " "
  var RS : String = "\n"
  var OFS : String = " "
  var ORS : String = "\n"
  var OFMT : String = "%.6g"
  var CONVFMT : String = "%.6g"
  var FILENAME : String = ""
  var NF : Double = 0.0
  var NR : Double = 0.0
  var FNR : Double = 0
  var SUBSEP : String = "\u{1C}"
  var RSTART : Double = 0
  var RLENGTH : Double = 0

  var exitCode: Int32 = 0
}

extension RuntimeState {

    // MARK: Record and fields
/*    var record: String = ""      // $0
    var fields: [String] = []    // $1, $2, ... (0-based internally: fields[0] = $1)
    var fieldsDirty = false      // need to re-split $0 into fields
    var recordDirty = false      // need to rebuild $0 from fields



    // MARK: Misc runtime state
    var srandSeed: Double = 1.0
    var exitCode: Int32 = 0
*/

  func setOptions(_ o : awk.CommandOptions) {
    self.options = o
  }

  func setsym(_ n : String, _ s : Cell) {
    if let k = symtab[n] {
      if k is BuiltInString {
        (k as! BuiltInString).setter(s.asString())
        return
      } else if k is BuiltInNumber {
        (k as! BuiltInNumber).setter(s.getNumber())
        return
      }
    }
    symtab[n] = s
  }


  func syminit() { // initialize symbol table with builtin vars

    // literal0 =
//    setsymtab("0", "0", 0.0, [.NUM, .STR, .CON, .DONTFREE])
    /* this is used for if(x)... tests: */
    // nullloc =
//    setsymtab("$zero&null", "", 0.0, [.NUM, .STR, .CON, .DONTFREE])

    // FIXME: need to set nullnode at some point
    // nullnode = celltonode(nullloc, CCON);

    // fsloc =
    setsym("FS", BuiltInString( { self.FS }, { self.FS = $0 } ) )
    setsym("RS", BuiltInString( { self.RS }, { self.RS = $0 } ))
    setsym("OFS", BuiltInString( { self.OFS }, { self.OFS = $0 } ))
    setsym("ORS", BuiltInString( { self.ORS }, { self.ORS = $0 } ))
    setsym("OFMT", BuiltInString( { self.OFMT }, { self.OFMT = $0 } ))
    setsym("CONVFMT", BuiltInString( { self.CONVFMT }, { self.CONVFMT = $0; GlobalCONVFMT = $0 } ))
    setsym("FILENAME", BuiltInString( { self.FILENAME }, { self.FILENAME = $0 } ))
    setsym("NF", BuiltInNumber( { self.NF }, { self.NF = $0 } ))
    setsym("NR", BuiltInNumber( { self.NR }, { self.NR = $0 } ))
    setsym("FNR", BuiltInNumber( { self.FNR }, { self.FNR = $0 } ))
    setsym("SUBSEP", BuiltInString( { self.SUBSEP }, { self.SUBSEP = $0 } ))
    setsym("RSTART", BuiltInNumber( { self.RSTART }, { self.RSTART = $0 } ))
    setsym("RLENGTH", BuiltInNumber( { self.RLENGTH }, { self.RLENGTH = $0 } ))

    // FIXME: is this really necessary?
    setsym("SYMTAB", Dictionary(dict: symtab))
//    setsymtab("SYMTAB", "", 0.0, [.ARR])
    // free(symtabloc->sval);
    // symtabloc->sval = (char *) symtab;
  }

    // MARK: - Field management

    // C: getfval(fldtab[n]) — tran.c
    func getField(_ n: Int) -> String {
        ensureFields()
      if n == 0 { ensureRecord(); return record! }
        guard n >= 1 && n <= fldtab.count else { return "" }
      return fldtab[n - 1]
    }

    // C: setsval(fldtab[n]) — tran.c
  func setField(_ n: Int, _ val: String) {
    if n == 0 {
      record = val; return
    }
    ensureFields()
    while fldtab.count < n { fldtab.append("") }
    fldtab[n - 1] = val
    if Double(n) > NF { NF = Double(n) }
    // FIXME: in theory, the assignment into fldtab set this with didSet
//    donerec = false
  }

    // C: setlastfld() + cleanfld() — lib.c
    func setNF(_ n: Int) {
        ensureFields()
        if n < fldtab.count { fldtab = Array(fldtab.prefix(n)) }
      while fldtab.count < n { fldtab.append("") }
        NF = Double(n)
      // FIXME: in theory, the assignment into fldtab set this with didSet
//        donerec = false
    }

  // FIXME: perhaps I should only store one or the other (fields or record) and the other one is
  // calculated upon get; and regenerates upon set
    // C: recbld() — lib.c
    func ensureRecord() {
      // donefld is reset by the record assignment -- but since it was built from the fields, they are done
      if !donerec { record = fldtab.joined(separator: OFS); donefld=true }
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


  func savefs() {
    inputFS = symtab["FS"]!.asString()
  }



  func fldbld() { //  create fields from current record
    /* this relies on having fields[] the same length as $0 */
    /* the fields are all stored in this one array with \0's */
    /* possibly with a final trailing \0 not associated with any field */

    if donefld {
      return;
    }

    var r = Substring(fldtab[0])
    let n = r.count

//    fr = fields;

    var i = 0;  /* number of fields accumulated here */
//    if runtime.inputFS == nil { // make sure we have a copy of FS
      savefs()
//    }
    if inputFS.count > 1 {  /* it's a regular expression */
      let i = refldbld(String(r), inputFS)
    } else {
      let sep = inputFS.first
      if sep == " " {  // default whitespace
        var i = 0
        while true {
          r = r.drop(while: { $0.isWhitespace })
          if r.isEmpty {
            break;
          }
          i+=1
          if (i >= fldtab.count ) {
            // FIXME: is newfld the same as growfldtab?
            newfld(i)
            // growfldtab(i);
          }
          let fr = r.prefix {c in let k = String(c); return k != " " && k != "\t" && k != "\n" && k != "\0" }
          fldtab[i] = String(fr)
          r = r.dropFirst(fr.count)
        }
      }
      else if sep == nil || sep == "\0" {    /* new: FS="" => 1 char/field */
        // FIXME: I lost the thread
        fatalError("I lost the thread")
        /*
          for (i = 0; *r != '\0'; r += n) {
            char buf[MB_LEN_MAX + 1];

            i++;
            if (i > nfields) {
              growfldtab(i);
            }
            n = mblen(r, MB_LEN_MAX);
            if (n < 0) {
              n = 1;
            }
            memcpy(buf, r, n);
            buf[n] = '\0';
            fldtab[i].sval = buf
            fldtab[i].tval = [.FLD, .STR]
          }
          *fr = 0;
         */
        }
      else if r.isEmpty {  /* if 0, it's a null field */
        /* subtlecase : if length(FS) == 1 && length(RS > 0)
         * \n is NOT a field separator (cf awk book 61,84).
         * this variable is tested in the inner while loop.
         */
         let lenrs = symtab["RS"]!.asString().count
        let rtest =
        if lenrs > 0 {
          "\0"
        } else {
          "\n" // normal case
        }
         while !r.isEmpty {
           i += 1
           if (i >= fldtab.count) {
             // FIXME: is newfld the same as growfld?
             newfld(i)
//             growfldtab(i);
           }

           let fr = r.prefix {c in c != sep && c != rtest.first && c != "\0" }
           fldtab[i] = String(fr)
           r = r.dropFirst(fr.count)
           //        while (*r != sep && *r != rtest && *r != '\0')  { // \n is always a separator
           //          *fr++ = *r++;
           //        }
           //        *fr++ = 0;
         }
      }
    }
    if (i >= fldtab.count) {
      FATAL("record `%\(r.prefix(30))...' has too many fields; can't happen")
    }
    fldtab = Array(fldtab[0..<i])
    donefld = true;

    setsym("NF", ValueCell(number: fldtab.count))
    donerec = true; /* restore */
    if options.dbg > 0 {
      for (j, p) in fldtab.enumerated() {
        if j == 0 { continue }
        print("field \(j): \(p)")
      }
    }
  }



  // C: fldbld() trigger — lib.c
  func ensureFields() {
    if !donefld { splitRecord(); donefld = true; donerec = true }
  }

  // C: fldbld() body — lib.c
  private func splitRecord() {
      let s = record ?? ""
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
      NF = Double(fldtab.count)
  }


  // FIXME: Duplicate from awk:

  func DPRINTF(_ s : String) {
    if options.dbg > 0 {
      print(s)
    }
  }

  func setDebug(_ d : Int) {
    dbg = d
  }
}
