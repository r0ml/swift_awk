/****************************************************************
Copyright (C) Lucent Technologies 1997
All Rights Reserved

Permission to use, copy, modify, and distribute this software and
its documentation for any purpose and without fee is hereby
granted, provided that the above copyright notice appear in all
copies and that both that the copyright notice and this
permission notice and warranty disclaimer appear in supporting
documentation, and that the name Lucent Technologies or any of
its entities not be used in advertising or publicity pertaining
to distribution of the software without specific, written prior
permission.

LUCENT DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS.
IN NO EVENT SHALL LUCENT OR ANY OF ITS ENTITIES BE LIABLE FOR ANY
SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER
IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
THIS SOFTWARE.
****************************************************************/

import CMigration
import Darwin

extension awk {
  
  /*
   char	EMPTY[] = { '\0' };
   FILE	*infile	= NULL;
   bool	innew;		/* true = infile has not been read by readrec */
   char	*file	= EMPTY;
   char	*record;
   int	recsize	= RECSIZE;
   char	*fields;
   int	fieldssize = RECSIZE;
   
   Cell	**fldtab;	/* pointers to Cells */
   static size_t	len_inputFS = 0;
   static char	*inputFS = NULL; /* FS at time of input, for field splitting */
   
   #define	MAXFLD	2
   int	nfields	= MAXFLD;	/* last allocated slot for $i */
   
   bool	donefld;	/* true = implies rec broken into fields */
   bool	donerec;	/* true = record is valid (no flds have changed) */
   
   int	lastfld	= 0;	/* last used field */
   int	argno	= 1;	/* current input argument number */
   extern	Awkfloat *ARGC;
   
   static Cell dollar0 = { OCELL, CFLD, NULL, EMPTY, 0.0, REC|STR|DONTFREE, NULL, NULL };
   static Cell dollar1 = { OCELL, CFLD, NULL, EMPTY, 0.0, FLD|STR|DONTFREE, NULL, NULL };
   */
  
  
  
  

   func recinit(_ n : UInt) {
     // FIXME: put me back
     /*
   if ( (record = malloc(n)) == NULL
   || (fields = malloc(n+1)) == NULL
   || (fldtab = calloc(nfields+2, sizeof(*fldtab))) == NULL
   || (fldtab[0] = malloc(sizeof(**fldtab))) == NULL) {
   FATAL("out of space for $0 and fields")
   }
   *record = '\0';
   *fldtab[0] = dollar0;
   fldtab[0]->sval = record;
   fldtab[0]->nval = tostring("0");
   makefields(1, nfields);
      */
   }

  
  /*
   func initgetrec() {
   for i in 1 ..< *ARGC {
   let p = getargv(i); /* find 1st real filename */
   if (p == NULL || *p == '\0') {  /* deleted or zapped */
   argno++;
   continue;
   }
   if !isclvar(p) {
   setsval(lookup("FILENAME", symtab), p)
   return
   }
   setclvar(p);	/* a commandline assignment before filename */
   argno++;
   }
   infile = stdin;		/* no filenames, so use stdin */
   innew = true;
   }

   */


   /*
    * POSIX specifies that fields are supposed to be evaluated as if they were
    * split using the value of FS at the time that the record's value ($0) was
    * read.
    *
    * Since field-splitting is done lazily, we save the current value of FS
    * whenever a new record is read in (implicitly or via getline), or when
    * a new value is assigned to $0.
    */
  func savefs() {
    runtime.inputFS = runtime.symtab["FS"]!.sval
  }

  /*
   var firsttime = true
   
   func getrec(char **pbuf, int *pbufsize, bool isrecord) -> Int { // get next input record
   // note: cares whether buf == record
   int c;
   char *buf = *pbuf;
   uschar saveb0;
   int bufsize = *pbufsize, savebufsize = bufsize;
   
   if (firsttime) {
   firsttime = false;
   initgetrec();
   }
   DPRINTF("RS=<%s>, FS=<%s>, ARGC=%g, FILENAME=%s\n",
   *RS, *FS, *ARGC, *FILENAME);
   if (isrecord) {
   donefld = false;
   donerec = true;
   }
   
   if (!donefld) {
   savefs();
   }
   
   saveb0 = buf[0];
   buf[0] = 0;
   while (argno < *ARGC || infile == stdin) {
   DPRINTF("argno=%d, file=|%s|\n", argno, file);
   if (infile == NULL) {	/* have to open a new file */
   file = getargv(argno);
   if (file == NULL || *file == '\0') {	/* deleted or zapped */
   argno++;
   continue;
   }
   if (isclvar(file)) {	/* a var=value arg */
   setclvar(file);
   argno++;
   continue;
   }
   *FILENAME = file;
   DPRINTF("opening file %s\n", file);
   if (*file == '-' && *(file+1) == '\0') {
   infile = stdin;
   }
   else if ((infile = fopen(file, "r")) == NULL) {
   FATAL("can't open file \(file)")
   }
   setfval(fnrloc, 0.0);
   }
   c = readrec(&buf, &bufsize, infile, innew);
   if (innew) {
   innew = false;
   }
   if (c != 0 || buf[0] != '\0') {	/* normal record */
   if (isrecord) {
   if (freeable(fldtab[0])) {
   xfree(fldtab[0]->sval);
   }
   fldtab[0]->sval = buf;	/* buf == record */
   fldtab[0]->tval = REC | STR | DONTFREE;
   if (is_number(fldtab[0]->sval)) {
   fldtab[0]->fval = atof(fldtab[0]->sval);
   fldtab[0]->tval |= NUM;
   }
   }
   setfval(nrloc, nrloc->fval+1);
   setfval(fnrloc, fnrloc->fval+1);
   if (donefld == 0) {
   fldbld();
   }
   *pbuf = buf;
   *pbufsize = bufsize;
   return 1;
   }
   /* EOF arrived on this file; set up next */
   if (infile != stdin) {
   fclose(infile);
   }
   infile = NULL;
   argno++;
   }
   buf[0] = saveb0;
   *pbuf = buf;
   *pbufsize = savebufsize;
   return 0;	/* true end of file */
   }
   
   func nextfile() {
   if (infile != NULL && infile != stdin) {
   fclose(infile);
   }
   infile = NULL;
   argno++;
   }
   
   func readrec(char **pbuf, int *pbufsize, FILE *inf, bool newflag)	{ // read one record into buf
   int sep, c, isrec;
   char *rr, *buf = *pbuf;
   int bufsize = *pbufsize;
   char *rs = getsval(rsloc);
   
   if (*rs && rs[1]) {
   bool found;
   
   fa *pfa = makedfa(rs, 1);
   if (newflag)
   found = fnematch(pfa, inf, &buf, &bufsize, recsize);
   else {
   int tempstat = pfa->initstat;
   pfa->initstat = 2;
   found = fnematch(pfa, inf, &buf, &bufsize, recsize);
   pfa->initstat = tempstat;
   }
   if (found) {
   setptr(patbeg, '\0');
   }
   isrec = *buf || !feof(inf);
   } else {
   if ((sep = *rs) == 0) {
   sep = '\n';
   while ((c=getc(inf)) == '\n' && c != EOF)	{ // skip leading \n's
   ;
   }
   if (c != EOF) {
   ungetc(c, inf);
   }
   }
   for (rr = buf; ; ) {
   for (; (c=getc(inf)) != sep && c != EOF; ) {
   if (rr-buf+1 > bufsize) {
   if (!adjbuf(&buf, &bufsize, 1+rr-buf,
   recsize, &rr, "readrec 1")) {
   FATAL("input record `%.30s...' too long", buf);
   }
   }
   *rr++ = c;
   }
   if (*rs == sep || c == EOF) {
   break;
   }
   if ((c = getc(inf)) == '\n' || c == EOF)	{ // 2 in a row
   break;
   }
   if (!adjbuf(&buf, &bufsize, 2+rr-buf, recsize, &rr,
   "readrec 2")) {
   FATAL("input record `%.30s...' too long", buf);
   }
   *rr++ = '\n';
   *rr++ = c;
   }
   if (!adjbuf(&buf, &bufsize, 1+rr-buf, recsize, &rr, "readrec 3")) {
   FATAL("input record `%.30s...' too long", buf);
   }
   *rr = 0;
   isrec = (c == EOF && rr == buf) ? 0 : 1;
   }
   *pbuf = buf;
   *pbufsize = bufsize;
   DPRINTF("readrec saw <%s>, returns %d\n", buf, isrec);
   return isrec;
   }
   
   func getargv(_ n : Int) -> String { // get ARGV[n]
   Cell *x;
   char *s, temp[50];
   extern Array *ARGVtab;
   
   snprintf(temp, sizeof(temp), "%d", n);
   if (lookup(temp, ARGVtab) == NULL) {
   return NULL;
   }
   x = setsymtab(temp, "", 0.0, STR, ARGVtab);
   s = getsval(x);
   DPRINTF("getargv(%d) returns |%s|\n", n, s);
   return s;
   }
   */

  func setclvar(_ ss : String) { // set var=value from s
    let k = ss.split(separator: "=")
    let p = String(k[1])
    let s = String(k[0])

    setsymtab(s, p, 0.0, .STR)
    // FIXME: this wont save the setting... need to combine with setsymtab
    runtime.symtab[s]?.sval = p
    if let gg = Double(p) {
      runtime.symtab[s]?.fval = gg
      runtime.symtab[s]?.tval.insert(.NUM)
    }
    DPRINTF("command line set \(s) to |\(p)|\n")
  }


  func cleanfld(_ n1 : Int, _ n2 : Int)	{ // clean out fields n1 .. n2 inclusive
                                          // nvals remain intact
    for i in n1 ..< n2 {
      var p = runtime.fldtab[i];
      p.sval = ""
      p.tval = [.FLD, .STR, .DONTFREE]
    }
  }

  func newfld(_ n : Int) { // add field n after end of existing lastfld
    while runtime.fldtab.count <= n {
      let k = Cell(ctype: .OCELL, csub: .CFLD, nval: String(runtime.fldtab.count), tval: [.FLD, .STR, .DONTFREE])
      runtime.fldtab.append(k)
    }
   }


  func setlastfld(_ n : Int)  { // set lastfld cleaning fldtab cells if necessary
    if (n < 0) {
      FATAL("cannot set NF to a negative value")
    }
    newfld(n)
    // FIXME: do I need to delete excess fields if there are any?
  }



  /*
   func fieldadr(_ n : Int) -> Cell {	// get nth field
   if (n < 0) {
   FATAL("trying to access out of range field %d", n);
   }
   if (n > nfields) { // fields after NF are empty
   growfldtab(n);	// but does not increase NF
   }
   return(fldtab[n]);
   }
   */


   func refldbld(_ rec : String, _ fs : String)	-> Int { // build fields from reg expr in FS
     fatalError("refldbld not yet implemented")
     /*
   /* this relies on having fields[] the same length as $0 */
   /* the fields are all stored in this one array with \0's */
   char *fr;
   int i, tempstat, n;
   fa *pfa;
   
   n = strlen(rec);
   if (n > fieldssize) {
   xfree(fields);
   if ((fields = malloc(n+1)) == NULL)
   FATAL("out of space for fields in refldbld %d", n);
   fieldssize = n;
   }
   fr = fields;
   *fr = '\0';
   if (*rec == '\0')
   return 0;
   pfa = makedfa(fs, 1);
   DPRINTF("into refldbld, rec = <%s>, pat = <%s>\n", rec, fs);
   tempstat = pfa->initstat;
   for (i = 1; ; i++) {
   if (i > nfields)
   growfldtab(i);
   if (freeable(fldtab[i]))
   xfree(fldtab[i]->sval);
   fldtab[i]->tval = FLD | STR | DONTFREE;
   fldtab[i]->sval = fr;
   DPRINTF("refldbld: i=%d\n", i);
   if (nematch(pfa, rec)) {
   pfa->initstat = 2;	/* horrible coupling to b.c */
   DPRINTF("match %s (%d chars)\n", patbeg, patlen);
   strncpy(fr, rec, patbeg-rec);
   fr += patbeg - rec + 1;
   *(fr-1) = '\0';
   rec = patbeg + patlen;
   } else {
   DPRINTF("no match %s\n", rec);
   strcpy(fr, rec);
   pfa->initstat = tempstat;
   break;
   }
   }
   return i;
      */
   }

  
  func recbld()	{ // create $0 from $1..$NF if necessary
    let sep = runtime.symtab["OFS"]!.sval

    if runtime.donerec {
      return;
    }
    var r = ""
    for i in 1 ..< runtime.fldtab.count {
      let p = getsval(&runtime.fldtab[i]);
//      if (!adjbuf(&record, &recsize, 1+strlen(p)+r-record, recsize, &r, "recbld 1")) {
//        FATAL("created $0 `%\(runtime.record.prefix(30))...' too long")
//      }
      r.append(p)
      if i < runtime.fldtab.count-1 {
//        if (!adjbuf(&record, &recsize, 2+strlen(sep)+r-record, recsize, &r, "recbld 2")) {
//          FATAL("created $0 `\(runtime.record.prefix(30))...' too long")
//        }
        r.append(sep)
      }
    }
//    if (!adjbuf(&record, &recsize, 2+r-record, recsize, &r, "recbld 3")) {
//      FATAL("built giant record `\(runtime.record.prefix(30))...'")
//    }
    DPRINTF("in recbld inputFS=\(runtime.inputFS)\n")

    runtime.record = r
    
    runtime.fldtab[0].tval = [.REC, .STR, .DONTFREE]
    runtime.fldtab[0].sval = r

    DPRINTF("in recbld inputFS=\(runtime.inputFS)\n")
    DPRINTF("recbld = |\(runtime.record)|\n")
    runtime.donerec = true;
  }

  /*
   var errorflag	= 0
   
   func yyerror(_ s : String) {
   SYNTAX("%s", s);
   }
   
   func SYNTAX(_ fmt : String, _ varg : Any...) {
   extern char *cmdname, *curfname;
   static int been_here = 0;
   va_list varg;
   
   if (been_here++ > 2) {
   return;
   }
   fprintf(stderr, "%s: ", cmdname);
   va_start(varg, fmt);
   vfprintf(stderr, fmt, varg);
   va_end(varg);
   fprintf(stderr, " at source line %d", lineno);
   if (curfname != NULL)
   fprintf(stderr, " in function %s", curfname);
   if (compile_time == COMPILING && cursource() != NULL)
   fprintf(stderr, " source file %s", cursource());
   fprintf(stderr, "\n");
   errorflag = 2;
   eprint();
   }
   
   // extern int bracecnt, brackcnt, parencnt;
   
   func bracecheck() {
   int c;
   static int beenhere = 0;
   
   if (beenhere++) {
   return;
   }
   while ((c = input()) != EOF && c != '\0') {
   bclass(c);
   }
   bcheck2(bracecnt, '{', '}');
   bcheck2(brackcnt, '[', ']');
   bcheck2(parencnt, '(', ')');
   }
   
   func bcheck2(_ n : Int, _ c1 : Int, _ c2 : Int) {
   if (n == 1) {
   fprintf(stderr, "\tmissing %c\n", c2);
   }
   else if (n > 1) {
   fprintf(stderr, "\t%d missing %c's\n", n, c2);
   }
   else if (n == -1) {
   fprintf(stderr, "\textra %c\n", c2);
   }
   else if (n < -1) {
   fprintf(stderr, "\t%d extra %c's\n", -n, c2);
   }
   }
   */
  
  func FATAL(_ fmt : String) {
    var se = FileDescriptor.standardError
    print("\(programName): \(fmt)", to: &se)
    error();
    if (options.dbg > 1)	{ // core dump if serious debugging on
      abort();
    }
    exit(2)
  }
  
  func WARNING(_ fmt : String) {
    var se = FileDescriptor.standardError
    print("\(programName): \(fmt)", to: &se)
    error();
  }
  
  func error() {
    /*   extern Node *curnode;
     
     var se = FileDesriptor.standardError
     print("", to: &se)
     if (compile_time != ERROR_PRINTING) {
     if (NR && *NR > 0) {
     fprintf(stderr, " input record number %d", (int) (*FNR));
     if (strcmp(*FILENAME, "-") != 0) {
     fprintf(stderr, ", file %s", *FILENAME);
     }
     fprintf(stderr, "\n");
     }
     if (curnode) {
     fprintf(stderr, " source line number %d", curnode->lineno);
     }
     else if (lineno) {
     fprintf(stderr, " source line number %d", lineno);
     }
     }
     
     if (compile_time == COMPILING && cursource() != NULL) {
     fprintf(stderr, " source file %s", cursource());
     }
     fprintf(stderr, "\n");
     eprint();
     */
  }
  
  /*
   func eprint() { // try to print context around error
   char *p, *q;
   int c;
   static int been_here = 0;
   extern char ebuf[], *ep;
   
   if (compile_time != COMPILING || been_here++ > 0 || ebuf == ep) {
   return;
   }
   if (ebuf == ep) {
   return;
   }
   p = ep - 1;
   if (p > ebuf && *p == '\n') {
   p--;
   }
   for ( ; p > ebuf && *p != '\n' && *p != '\0'; p--) {
   ;
   }
   while (*p == '\n') {
   p++;
   }
   fprintf(stderr, " context is\n\t");
   for (q=ep-1; q>=p && *q!=' ' && *q!='\t' && *q!='\n'; q--) {
   ;
   }
   for ( ; p < q; p++) {
   if (*p) {
   putc(*p, stderr);
   }
   }
   fprintf(stderr, " >>> ");
   for ( ; p < ep; p++) {
   if (*p) {
   putc(*p, stderr);
   }
   }
   fprintf(stderr, " <<< ");
   if (*ep) {
   while ((c = input()) != '\n' && c != '\0' && c != EOF) {
   putc(c, stderr);
   bclass(c);
   }
   }
   putc('\n', stderr);
   ep = ebuf;
   }
   
   func bclass(_ c : Character) {
   switch c {
   case "{": bracecnt++;
   case "}": bracecnt--;
   case "[": brackcnt++;
   case "]": brackcnt--;
   case "(": parencnt++;
   case ")": parencnt--;
   default: break
   }
   }
   
   func errcheck(_ x : Double, _ s : String) -> Double {
   if errno == EDOM {
   errno = 0;
   WARNING("\(s) argument out of domain")
   x = 1;
   } else if (errno == ERANGE) {
   errno = 0;
   WARNING("\(s) result out of range")
   x = 1;
   }
   return x;
   }
   */
  func isclvar(_ s : String) -> Bool { // is s of form var=something ?
    guard let sf = s.first else { return false }
    guard sf.isLetter || sf == "_" else { return false }
    let k = s.split(separator: "=")
    guard k.count == 2 else { return false }
    guard (k[0].allSatisfy { $0.isLetter || $0.isWholeNumber || $0 == "_" }) else { return false }
    return true
  }
  
  /* strtod is supposed to be a proper test of what's a valid number */
  /* appears to be broken in gcc on linux: thinks 0x123 is a valid FP number */
  /* wrong: violates 4.10.1.4 of ansi C standard */
  /* well, not quite. As of C99, hex floating point is allowed. so this is
   * a bit of a mess.
   */
  
  func is_number(_ s : String) -> Bool {
    guard let _ = Int(s) else { return false }
    return true
  }
  
  
}
