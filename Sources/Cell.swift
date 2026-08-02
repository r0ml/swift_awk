// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026


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


  struct Cell {
    var ctype : Ctype    // OCELL, OBOOL, OJUMP, etc.
    var csub : Subtype    // CCON, CTEMP, CFLD, etc.
    var nval : String   // name, for variables only
    var sval : String = ""   // string value
    var fval : Awkfloat = 0 // value as number
    var tval : Tval   // type info: STR|NUM|ARR|FCN|FLD|CON|DONTFREE|CONVC|CONVO
    var fmt : String?  // CONVFMT/OFMT value used to convert from number

    var isarr : Bool { return tval.contains(.ARR) }
    var isrec : Bool { return tval.contains(.REC) }
    var isfld : Bool { return tval.contains(.FLD) }
    var isnum : Bool { return tval.contains(.NUM) }
    var isstr : Bool { return tval.contains(.STR) }
  }

  func syminit() { // initialize symbol table with builtin vars

    // literal0 =
    setsymtab("0", "0", 0.0, [.NUM, .STR, .CON, .DONTFREE])
    /* this is used for if(x)... tests: */
    // nullloc =
    setsymtab("$zero&null", "", 0.0, [.NUM, .STR, .CON, .DONTFREE])

    // FIXME: need to set nullnode at some point
    // nullnode = celltonode(nullloc, CCON);

    // fsloc =
    setsymtab("FS", " ", 0.0, [.STR, .DONTFREE])
    // FS = &fsloc->sval;
    // rsloc =
    setsymtab("RS", "\n", 0.0, [.STR, .DONTFREE])
    // RS = &rsloc->sval;
    // ofsloc =
    setsymtab("OFS", " ", 0.0, [.STR, .DONTFREE])
    // OFS = &ofsloc->sval;
    // orsloc =
    setsymtab("ORS", "\n", 0.0, [.STR, .DONTFREE])
    //   ORS = &orsloc->sval;
    // OFMT = &
    setsymtab("OFMT", "%.6g", 0.0, [.STR, .DONTFREE])
    // ->sval;
    // CONVFMT = &
    setsymtab("CONVFMT", "%.6g", 0.0, [.STR, .DONTFREE]) // ->sval;
    // FILENAME = &
    setsymtab("FILENAME", "", 0.0, [.STR, .DONTFREE]) // ->sval;
    // nfloc =
    setsymtab("NF", "", 0.0, .NUM)
    // NF = &nfloc->fval;
    // nrloc =
    setsymtab("NR", "", 0.0, .NUM)
    // NR = &nrloc->fval;
    // fnrloc =
    setsymtab("FNR", "", 0.0, [.NUM])
    // FNR = &fnrloc->fval;
    // subseploc =
    setsymtab("SUBSEP", "\034", 0.0, [.STR, .DONTFREE])
    // SUBSEP = &subseploc->sval;
    // rstartloc =
    setsymtab("RSTART", "", 0.0, [.NUM])
    // RSTART = &rstartloc->fval;
    // rlengthloc =
    setsymtab("RLENGTH", "", 0.0, [.NUM])
    // RLENGTH = &rlengthloc->fval;
    // symtabloc =
    // FIXME: is this really necessary?
    setsymtab("SYMTAB", "", 0.0, [.ARR])
    // free(symtabloc->sval);
    // symtabloc->sval = (char *) symtab;
  }




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

  func getfval(_ vp : inout Cell) -> Awkfloat { // get float val of a Cell */
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
    DPRINTF("getsval: \(vp.nval) = \"\(vp.sval)\", t=\(vp.tval)\n")
    return vp.sval
  }

  func getsval(_ vp : inout Cell) -> String { // get string val of a Cell */
    return get_str_val(&vp, runtime.symtab["CONVFMT"]!)
  }





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
    // FIXME: this looks like it alters the fldtab Cell
    if runtime.fldtab[0].isstr {
      getsval(&runtime.fldtab[0]);
    }

    var r = Substring(runtime.fldtab[0].sval)
    let n = r.count

//    fr = fields;

    var i = 0;  /* number of fields accumulated here */
    if runtime.inputFS == nil { // make sure we have a copy of FS
      savefs()
    }
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
          runtime.fldtab[i].tval = [.FLD, .STR, .DONTFREE]
          let fr = r.prefix { $0 != " " && $0 != "\t" && $0 != "\n" && $0 != "\0" }
          runtime.fldtab[i].sval = String(fr)
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
         let lenrs = runtime.symtab["RS"]!.sval.count
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
           runtime.fldtab[i].tval = [.FLD, .STR, .DONTFREE]

           let fr = r.prefix {c in c != sep && c != rtest.first && c != "\0" }
           runtime.fldtab[i].sval = String(fr)
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
    for var (j, p) in runtime.fldtab.enumerated() {
      if j == 0 { continue }
      if let n = Double(p.sval) {
        p.fval = n
        p.tval.insert(.NUM)
      }
    }
    runtime.symtab["NF"]?.fval = Awkfloat(runtime.fldtab.count)
    runtime.donerec = true; /* restore */
    if options.dbg > 0 {
      for (j, p) in runtime.fldtab.enumerated() {
        if j == 0 { continue }
        print("field \(j) (\(p.nval)): |\(p.sval)|")
      }
    }
  }
}
