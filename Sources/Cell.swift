// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

import CMigration

/* Cell:  all information about a variable or constant */

extension awk {

enum Ctype {
  case OCELL
  case OBOOL
  case OJUMP
}

enum Subtype {
  // Cell subtypes: csub
  case CFREE
  case CCOPY
  case CCON
  case CTEMP
  case CNAME
  case CVAR
  case CFLD
  case CUNK

  // bool subtypes
  case BTRUE
  case BFALSE

  // jump subtypes
  case JEXIT
  case JNEXT
  case JBREAK
  case JCONT
  case JRET
  case JNEXTFILE
}

struct Tval : OptionSet {
  let rawValue : UInt

  static let NUM = Tval(rawValue: 1)  // number value is valid
  static let STR = Tval(rawValue: 2)  // string value is valid
  static let DONTFREE = Tval(rawValue: 4)  // string space is not freeable
  static let CON = Tval(rawValue: 8)  // this is a constant
  static let ARR = Tval(rawValue: 16) // this is an array
  static let FCN = Tval(rawValue: 32) // this is a function name
  static let FLD = Tval(rawValue: 64) // this is a field $1, $2, ...
  static let REC = Tval(rawValue: 128) // this is $0
  static let CONVC = Tval(rawValue: 256) // string was converted from number via CONVFMT
  static let CONVO = Tval(rawValue: 512) // string was converted from number via OFMT
}

  enum CellValue {
    case sval(String)
    case fval(Awkfloat)
    case arr([Cell])
    case dict([String:Cell])
    case rec(String)
    case fld(String, Int)
    case fcn([Node])
    case builtinString(()->String, (String)->())
    case builtinNumber(()->Double, (Double)->())
  }

  enum NodeValue {
    case op([Node])
    case const(Cell)
  }

  struct Node {
    var ntype : Int
    var lineno : Int
    var nobj : Int
    var narg : NodeValue
  }

  struct Cell {
//    var ctype : Ctype    // OCELL, OBOOL, OJUMP, etc.
//    var csub : Subtype    // CCON, CTEMP, CFLD, etc.
    var nval : String?   // name, for variables only
    var val : CellValue

    //    var sval : String = ""   // string value
    //    var fval : Awkfloat = 0 // value as number
    //    var tval : Tval   // type info: STR|NUM|ARR|FCN|FLD|CON|DONTFREE|CONVC|CONVO
    var fmt : String?  // CONVFMT/OFMT value used to convert from number

    var isarr : Bool { return if case .arr = val { true } else { false } }
    var isrec : Bool { return if case .rec = val { true } else { false } }
    var isfld : Bool { return if case .fld = val { true } else { false } }
    var isnum : Bool { return if case .fval = val { true } else { false } }
    var isstr : Bool { return if case .sval = val { true } else if case .rec = val { true } else if case .fld = val { true } else { false } }
    var isfcn : Bool { return if case .fcn = val { true } else { false } }
    var iddict : Bool { return if case .dict = val { true } else { false } }

    /*

     // MARK: - AWK Cell (runtime value)

     /// Mutable AWK value — corresponds to Cell in awk.h.
     /// Reference type so that arrays are shared and function arguments can be
     /// passed by reference (arrays) vs. by value (scalars, which are copied on call).
     final class AWKCell {
     var numVal: Double = 0.0
     var strVal: String = ""
     var hasNum: Bool = false
     var hasStr: Bool = false
     var isConst: Bool = false
     var array: [String: AWKCell]? = nil

     var isArray: Bool { array != nil }
     */

    // C: gettemp() + setfval() — run.c / tran.c
    init(number: Double, named: String? = nil) {
      self.val = .fval(number)
      if let named { self.nval = named }
    }

    init(number: Int, named: String? = nil) {
      self.val = .fval(Double(number))
      if let named { self.nval = named }
    }

    // C: gettemp() + setsval() — run.c / tran.c
    init(string: String, named: String? = nil) {
      self.val = .sval(string)
      if let named { self.nval = named }
    }

    init(field: String, at: Int) {
      self.val = .fld(field, at)
    }
    // C: (no direct equivalent; used when both numeric and string values are already known)
/*    static func both(_ n: Double, _ s: String) -> AWKCell {
      let c = AWKCell()
      c.numVal = n + 0; c.strVal = s; c.hasNum = true; c.hasStr = true
      return c
  }
 */
    // C: (no direct equivalent; array cell allocation in tran.c)
    init(array: [Cell], named: String? = nil) {
      val = .arr(array)
      if let named { self.nval = named }
    }

    init(dict: [String:Cell], named: String? = nil) {
      val = .dict(dict)
      if let named { self.nval = named }
    }

    init(builtinString: String, _ getter: @escaping ()->String, _ setter: @escaping (String)->() ) {
      val = .builtinString(getter, setter)
      self.nval = builtinString
    }

    init(builtinNumber: String, _ getter: @escaping ()->Double, _ setter: @escaping (Double)->() ) {
      val = .builtinNumber(getter, setter)
      self.nval = builtinNumber
    }

    var hasNum : Bool {
      switch val {
        case .fval: return true
        case .sval(let s): return Double(s.trimmed()) != nil
        case .builtinNumber: return true
        case .builtinString(let g, _): let s = g(); return Double(s.trimmed()) != nil
        case .fld(let s, _): return Double(s.trimmed()) != nil
        default: return false
      }
    }

    // Get numeric value; lazily parses string if no numeric value is cached.
    // C: getfval() — tran.c
    func getfval() -> Double {
      switch val {
        case .fval(let d): return d
        case .sval(let s): return Double(s.trimmed()) ?? 0
        case .builtinNumber(let g, _): return g()
        case .builtinString(let g, _):
          return Double(g().trimmed()) ?? 0
        case .fld(let s, _):
          return Double(s.trimmed()) ?? 0
        default: return 0
      }
    }

    // Get string value using the supplied format (CONVFMT or OFMT).
    // C: getsval() — tran.c
    func getsval(fmt: String = "%.6g") -> String {
      switch val {
        case .sval(let s): return s
        case .fval(let d): return cFormat(fmt, d)
        case .builtinString(let g,_): return g()
        case .builtinNumber(let g, _): return cFormat(fmt, g())
        case .fld(let s, _): return s
        default: return ""
      }
    }

    // Assign a numeric value (invalidates the cached string).
    // C: setfval() — tran.c
    mutating func setfval(_ n: Double) {
      val = .fval(n)
    }

    // Assign a string value (invalidates the cached numeric value).
    // C: setsval() — tran.c
    mutating func setsval(_ s: String) {
      val = .sval(s)
    }

    // Assign both numeric and string simultaneously (e.g. after a getline).
    // C: setsval() + setfval() combined — tran.c
/*    func setBoth(_ n: Double, _ s: String) {
      numVal = n + 0; strVal = s; hasNum = true; hasStr = true
    }
*/

    // Copy scalar state from another cell (does NOT deep-copy arrays).
    // C: copycell() — run.c
    mutating func copycell(_ other: Cell) {
      val = other.val
    }

    /// AWK truth: non-zero number, or non-empty string that isn't "0".
    // C: truth-value test in boolop() / relop() — run.c
    var isTrue: Bool {
      switch val {
        case .fval(let n): return n != 0
        case .sval(let s): return !s.isEmpty && s != "0"
        case .fld(let s, _):  return !s.isEmpty && s != "0"
        case .builtinString(let g, _): let s = g(); return !s.isEmpty && s != "0"
        case .builtinNumber(let g, _): let n = g(); return n != 0
        default: return false
      }
    }
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
    runtime.symtab["FS"]=Cell(builtinString: "FS", { runtime.FS }, { runtime.FS = $0 } )
    runtime.symtab["RS"]=Cell(builtinString: "RS", { runtime.RS }, { runtime.RS = $0 } )
    runtime.symtab["OFS"]=Cell(builtinString: "OFS", { runtime.OFS }, { runtime.OFS = $0 } )
    runtime.symtab["ORS"]=Cell(builtinString: "ORS", { runtime.ORS }, { runtime.ORS = $0 } )
    runtime.symtab["OFMT"]=Cell(builtinString: "OFMT", { runtime.OFMT }, { runtime.OFMT = $0 } )
    runtime.symtab["CONVFMT"]=Cell(builtinString: "CONVFMT", { runtime.CONVFMT }, { runtime.CONVFMT = $0 } )
    runtime.symtab["FILENAME"]=Cell(builtinString: "FILENAME", { runtime.FILENAME }, { runtime.FILENAME = $0 } )
    runtime.symtab["NF"]=Cell(builtinNumber: "NF", { runtime.NF }, { runtime.NF = $0 } )
    runtime.symtab["NR"]=Cell(builtinNumber: "NR", { runtime.NR }, { runtime.NR = $0 } )
    runtime.symtab["FNR"]=Cell(builtinNumber: "FNR", { runtime.FNR }, { runtime.FNR = $0 } )
    runtime.symtab["SUBSEP"]=Cell(builtinString: "SUBSEP", { runtime.SUBSEP }, { runtime.SUBSEP = $0 } )
    runtime.symtab["RSTART"]=Cell(builtinNumber: "RSTART", { runtime.RSTART }, { runtime.RSTART = $0 } )
    runtime.symtab["RLENGTH"]=Cell(builtinNumber: "RLENGTH", { runtime.RLENGTH }, { runtime.RLENGTH = $0 } )

    // FIXME: is this really necessary?
    runtime.symtab["SYMTAB"]=Cell(dict: runtime.symtab, named: "SYMTAB")
//    setsymtab("SYMTAB", "", 0.0, [.ARR])
    // free(symtabloc->sval);
    // symtabloc->sval = (char *) symtab;
  }



/*
  func setsymtab(_ n : String, _ s : String, _ f : Awkfloat, _ t : Tval) {
    if let _ = runtime.symtab[n] {
      DPRINTF("setsymtab found: n=\(n) s=\"\(s)\" f=\(f) t=\(t)\n")
      return
//      return p
    }
    let p = Cell(ctype: .OCELL, csub: .CUNK, nval: n, sval: s, fval: f, tval: t )
    runtime.symtab[n]=p
    DPRINTF("setsymtab set: n=\(n) s=\"\(s)\" f=\(f) t=\(t)\n")
    return
//    return p
  }
*/
  
  /*
  func funnyvar(_ vp : Cell, _ rw : String) {
    if vp.isarr {
      FATAL("can't \(rw) \(vp.nval); it's an array name.")
    }
    if vp.tval.contains(.FCN) {
      FATAL("can't \(rw) \(vp.nval); it's a function.")
    }
    WARNING("funny variable: n=\(vp.nval) s=\"\(vp.sval)\" f=\(vp.fval) t=\(vp.tval)")
  }

  func setsval(_ vp : inout Cell, _ s : String) -> String {  // set string val of a Cell

    DPRINTF("starting setsval: \(vp.nval) = \"\(s)\", t=\(vp.tval), r,f=\(runtime.donerec),\(runtime.donefld)\n")
    if !vp.tval.containsAny(of: [.NUM , .STR] ) {
      funnyvar(vp, "assign to");
    }
    if vp.isfld {
      runtime.donerec = false;  /* mark $0 invalid */
      let fldno = Int(vp.nval)!
      if fldno > runtime.fldtab.count {
        newfld(fldno)
      }
      DPRINTF("setting field \(fldno) to \(s)\n")
    } else if vp.isrec {
      runtime.donefld = false;  /* mark $1... invalid */
      runtime.donerec = true;
      savefs();
    } else if vp.nval == "OFS" {
      if (!runtime.donerec) {
        recbld();
      }
    }
    let t = s
    // FIXME: does this need to be kept?
    /*
    if (freeable(vp)) {
      xfree(vp->sval);
    }
     */

    vp.tval.remove([.NUM, .CONVC, .CONVO])
    vp.tval.insert(.STR)
    vp.fmt = nil
 //   setfree(vp);
    DPRINTF("setsval: \(vp.nval) = \"\(t) (%p) \", t=\(vp.tval) r,f=\(runtime.donerec),\(runtime.donefld)\n")
    vp.sval = t
    if vp.nval == "NF" {
      runtime.donerec = false;  // mark $0 invalid
      let f = getfval(&vp)
      setlastfld(Int(f))
      DPRINTF("setting NF to \(f)\n")
    }

    return vp.sval
  }
   */

  /*
  func getfval(_ vp : inout Cell) -> Awkfloat { // get float val of a Cell 
    if !vp.tval.containsAny(of: [.NUM, .STR]) {
      funnyvar(vp, "read value of");
    }
    if vp.isfld && !runtime.donefld {
      fldbld();
    }
    else if vp.isrec && !runtime.donerec {
      recbld();
    }
    if !vp.isnum {  // not a number
      if let ff = Double(vp.sval), !vp.tval.contains(.CON) { // best guess
        vp.tval.insert(.NUM)  // make NUM only sparingly
        vp.fval = ff
      }
    }
    DPRINTF("getfval: \(vp.nval) = \(vp.fval), t=\(vp.tval)\n")
    return vp.fval
   }


  func update_str_val(_ vp : inout Cell) {
    let s = if vp.fval == vp.fval.rounded(.towardZero) { // it's integral
      String(Int(vp.fval))
    } else {
      // FIXME: what does fmtcheck do?
      String(vp.fval)
//      snprintf(s, sizeof (s), fmtcheck(*fmt, "%g"), vp->fval);
    }
    vp.sval = s
    vp.tval.subtract(.DONTFREE)
    vp.tval.insert(.STR)
  }
*/

/*
  func get_str_val(_ vp : inout Cell, _ fmt : Cell) -> String { // get string val of a Cell
    if !vp.tval.containsAny(of: [.NUM, .STR]) {
      funnyvar(vp, "read value of");
    }
    if vp.isfld && !runtime.donefld {
      fldbld()
    }
    else if vp.isrec && !runtime.donerec {
      recbld()
    }

    /*
     * ADR: This is complicated and more fragile than is desirable.
     * Retrieving a string value for a number associates the string
     * value with the scalar.  Previously, the string value was
     * sticky, meaning if converted via OFMT that became the value
     * (even though POSIX wants it to be via CONVFMT). Or if CONVFMT
     * changed after a string value was retrieved, the original value
     * was maintained and used.  Also not per POSIX.
     *
     * We work around this design by adding two additional flags,
     * CONVC and CONVO, indicating how the string value was
     * obtained (via CONVFMT or OFMT) and _also_ maintaining a copy
     * of the pointer to the xFMT format string used for the
     * conversion.  This pointer is only read, **never** dereferenced.
     * The next time we do a conversion, if it's coming from the same
     * xFMT as last time, and the pointer value is different, we
     * know that the xFMT format string changed, and we need to
     * redo the conversion. If it's the same, we don't have to.
     *
     * There are also several cases where we don't do a conversion,
     * such as for a field (see the checks below).
     */

    /* Don't duplicate the code for actually updating the value */

    if !vp.isstr {
      update_str_val(&vp)
      if fmt.nval == "OFMT" {
        vp.tval.subtract(.CONVC)
        vp.tval.insert(.CONVO)
      } else {
        /* CONVFMT */
        vp.tval.subtract(.CONVO)
        vp.tval.insert(.CONVC)
      }
      vp.fmt = fmt.sval;
    } else if vp.tval.contains(.DONTFREE) || !vp.isnum || vp.isfld {

//      goto done;
    } else if vp.isstr {
      if fmt.nval == "OFMT" {
        if (vp.tval.contains(.CONVC) || vp.tval.contains(.CONVO))
            && vp.fmt != fmt.sval {
              update_str_val(&vp)
              vp.tval.subtract(.CONVC)
              vp.tval.insert(.CONVO)
          vp.fmt = fmt.sval;
            }
      } else {
        // CONVFMT
        if (vp.tval.contains(.CONVO)
            || vp.tval.contains(.CONVC))
            && vp.fmt != fmt.sval {
              update_str_val(&vp)
              vp.tval.subtract(.CONVO)
              vp.tval.insert(.CONVC)
          vp.fmt = fmt.sval;
            }
      }
    }
// done:
    DPRINTF("getsval: \(vp.nval) = \"\(vp.val)\"\n")
    return vp.sval
  }
*/

  /*
  func getsval(_ vp : inout Cell) -> String { // get string val of a Cell
    return get_str_val(&vp, runtime.symtab["CONVFMT"]!)
  }
*/




  /*
   Awkfloat setfval(Cell *vp, Awkfloat f)  /* set float val of a Cell */
   {
   int fldno;

   f += 0.0;    /* normalise negative zero to positive zero */
   if ((vp->tval & (NUM | STR)) == 0)
   funnyvar(vp, "assign to");
   if (isfld(vp)) {
   donerec = false;  /* mark $0 invalid */
   fldno = atoi(vp->nval);
   if (fldno > *NF)
   newfld(fldno);
   DPRINTF("setting field %d to %g\n", fldno, f);
   } else if (&vp->fval == NF) {
   donerec = false;  /* mark $0 invalid */
   setlastfld(f);
   DPRINTF("setting NF to %g\n", f);
   } else if (isrec(vp)) {
   donefld = false;  /* mark $1... invalid */
   donerec = true;
   savefs();
   } else if (vp == ofsloc) {
   if (!donerec)
   recbld();
   }
   if (freeable(vp))
   xfree(vp->sval); /* free any previous string */
   vp->tval &= ~(STR|CONVC|CONVO); /* mark string invalid */
   vp->fmt = NULL;
   vp->tval |= NUM;  /* mark number ok */
   if (f == -0)  /* who would have thought this possible? */
   f = 0;
   DPRINTF("setfval %p: %s = %g, t=%o\n", (void*)vp, NN(vp->nval), f, vp->tval);
   return vp->fval = f;
   }
*/




  /*
   char *getpssval(Cell *vp)     /* get string val of a Cell for print */
   {
   return get_str_val(vp, OFMT);
   }


   char *tostring(const char *s)  /* make a copy of string s */
   {
   char *p = strdup(s);
   if (p == NULL)
   FATAL("out of space in tostring on %s", s);
   return(p);
   }

   wchar_t towc(int* outlen, const char *s, int slen) {
   wchar_t wc = L'\0';
   if (*s) {
   if ((*outlen = mbtowc(&wc, s, slen)) > 0) {
   if (wc > UCHAR_MAX) {
   DPRINTF("pmatch: converted wchar_t is out of uchar range: %s -> %d\n", s, wc);
   }
   } else {
   FATAL("towc: multibyte conversion failure on: '%s'\n", s);
   }
   } else {
   /* Technically wrong */
   *outlen = 1;
   }
   return wc;
   }

   char *tostringN(const char *s, size_t n)  /* make a copy of string s */
   {
   char *p;

   p = malloc(n);
   if (p == NULL)
   FATAL("out of space in tostring on %s", s);
   strcpy(p, s);
   return(p);
   }

   Cell *catstr(Cell *a, Cell *b) /* concatenate a and b */
   {
   Cell *c;
   char *p;
   char *sa = getsval(a);
   char *sb = getsval(b);
   size_t l = strlen(sa) + strlen(sb) + 1;
   p = malloc(l);
   if (p == NULL)
   FATAL("out of space concatenating %s and %s", sa, sb);
   snprintf(p, l, "%s%s", sa, sb);

   l++;  // add room for ' '
   char *newbuf = malloc(l);
   if (newbuf == NULL)
   FATAL("out of space concatenating %s and %s", sa, sb);
   // See string() in lex.c; a string "xx" is stored in the symbol
   // table as "xx ".
   snprintf(newbuf, l, "%s ", p);
   c = setsymtab(newbuf, p, 0.0, CON|STR|DONTFREE, symtab);
   free(p);
   free(newbuf);
   return c;
   }
*/


  func fldbld() { //  create fields from current record
    /* this relies on having fields[] the same length as $0 */
    /* the fields are all stored in this one array with \0's */
    /* possibly with a final trailing \0 not associated with any field */

    if runtime.donefld {
      return;
    }

    var r = Substring(runtime.fldtab[0].getsval())
    let n = r.count

//    fr = fields;

    var i = 0;  /* number of fields accumulated here */
//    if runtime.inputFS == nil { // make sure we have a copy of FS
      savefs()
//    }
    if runtime.inputFS.count > 1 {  /* it's a regular expression */
      let i = refldbld(String(r), runtime.inputFS)
    } else {
      let sep = runtime.inputFS.first
      if sep == " " {  // default whitespace
        var i = 0
        while true {
          r = r.drop(while: { $0.isWhitespace })
          if r.isEmpty {
            break;
          }
          i+=1
          if (i >= runtime.fldtab.count ) {
            // FIXME: is newfld the same as growfldtab?
            newfld(i)
            // growfldtab(i);
          }
          let fr = r.prefix {c in let k = String(c); return k != " " && k != "\t" && k != "\n" && k != "\0" }
          runtime.fldtab[i] = Cell(field: String(fr), at: i)
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
         let lenrs = runtime.symtab["RS"]!.getsval().count
        let rtest =
        if lenrs > 0 {
          "\0"
        } else {
          "\n" // normal case
        }
         while !r.isEmpty {
           i += 1
           if (i >= runtime.fldtab.count) {
             // FIXME: is newfld the same as growfld?
             newfld(i)
//             growfldtab(i);
           }

           let fr = r.prefix {c in c != sep && c != rtest.first && c != "\0" }
           runtime.fldtab[i].val = .fld(String(fr), i)
           r = r.dropFirst(fr.count)
           //        while (*r != sep && *r != rtest && *r != '\0')  { // \n is always a separator
           //          *fr++ = *r++;
           //        }
           //        *fr++ = 0;
         }
      }
    }
    if (i >= runtime.fldtab.count) {
      FATAL("record `%\(r.prefix(30))...' has too many fields; can't happen")
    }
    runtime.fldtab = Array(runtime.fldtab[0..<i])
    runtime.donefld = true;

    runtime.symtab["NF"]?.setfval(Awkfloat(runtime.fldtab.count))
    runtime.donerec = true; /* restore */
    if options.dbg > 0 {
      for (j, p) in runtime.fldtab.enumerated() {
        if j == 0 { continue }
        print("field \(j) (\(p.nval)): |\(p.getsval())|")
      }
    }
  }
}


extension String {
  func trimmed() -> String {
    String(drop(while: \.isWhitespace)
      .reversed()
      .drop(while: \.isWhitespace)
      .reversed())
  }
}
