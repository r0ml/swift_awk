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

let version = "version 20260816"

let RECSIZE : UInt = (8 * 1024)  // sets limit on records, fields, etc., etc.

@main struct awk : ShellCommand {
  //  uint32_t val;
  //  int ch, fd, rval;
  //  off_t len;
  //  char *fn, *p;
  //  int (*cfncn)(int, uint32_t *, off_t *);
  //  void (*pfncn)(char *, uint32_t, off_t);

  struct CommandOptions {
    var safe : Bool = false
    var pfile : [String] = []
    var fs : String = ""
    var dbg : Int = 0
    var lexprog : String? = nil
    var args : [String] = []
  }

  var options : CommandOptions!

  class RuntimeVars {
    var curpfile = 0
    var symtab : [String : Cell] = [:]
    var fldtab : [Cell] = []
    var record : String?  /* points to $0 */
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

  var runtime = RuntimeVars()




  /*
   if ((p = strrchr(argv[0], '/')) == NULL)
   p = argv[0];
   else
   ++p;
   */

    func parseOptions() throws(CmdErr) -> CommandOptions {

//    setlocale(LC_CTYPE, "");
//    setlocale(LC_COLLATE, "");
//    setlocale(LC_NUMERIC, "C"); /* for parsing cmdline & prog */
//    cmdname = argv[0];


    // FIXME: split the command
/*    if (!strcmp(p, "sum")) {
     cfncn = csum1;
     pfncn = psum1;
     ++argv;
     } else {
     */
    var options = CommandOptions()
    let go = BSDGetopt("s::f:F:v:d::")
  loop:
    while let (k,v) = try go.getopt() {
      switch k {
      case "-":
        break loop
      case "V":
        print("awk \(version)")
        exit(0)
      case "s":
        if v == "afe" {
          options.safe = true
        }

      case "f":  // next argument is program filename
          do {
            options.lexprog = try readFileAsString(at: v)
          } catch(let e) {
            throw CmdErr(1, "unable to read program file \(v): \(e.localizedDescription)")
          }

      case "F":  /* set field separator */
        options.fs = v

      case "v":  /* -v a=1 to be done NOW.  one -v for each */
        let vn = v
        if (isclvar(vn)) {
          setclvar(vn)
        }
        else {
          FATAL("invalid -v option argument: \(vn)")
        }

      case "d":
        options.dbg = Int(v) ?? 1
        print("awk \(version)")
      default:
        throw CmdErr(1)
      }

    }

    options.args = go.remaining

      // FIXME: why was this here?
      /*
    if options.args.count == 0 {
      throw CmdErr(1)
    }
*/

    //    Unix2003_compat = COMPAT_MODE("bin/awk", "unix2003")

      var sa = sigaction.init()
      sa.__sigaction_u.__sa_sigaction = fpecatch;
      sa.sa_flags = SA_SIGINFO;
      sigemptyset(&sa.sa_mask);
      sigaction(SIGFPE, &sa, nil)


    /*signal(SIGSEGV, segvcatch); experiment */

    /* Set and keep track of the random seed */
 //   srand_seed = 1;
    srandom(runtime.srand_seed)

 //   runtime.yyin = nil
 //   symtab = makesymtab(NSYMTAB/NSYMTAB);

    if options.lexprog == nil {  // no -f; first argument is program
      if (options.args.count <= 1) {
        if options.dbg != 0 {
          exit(0);
        }
        FATAL("no program given")
      }
      let vv = options.args.removeFirst()
      DPRINTF("program = |\(vv)|\n")
      options.lexprog = vv;
    }

      return options
  }


  func runCommand() async throws(CmdErr) {
    recinit(RECSIZE)
    syminit()


    //    compile_time = COMPILING;
    // argv[0] = cmdname;  /* put prog name at front of arglist */
    // DPRINTF("argc=%d, argv[0]=%s\n", argc, argv[0]);


    // FIXME: do arginit:  put me back
    // arginit(argc, argv);

    // FIXME: do envinit: put me back
    // if (!options.safe) {
 //     envinit(environ)
//    }

    do {

      // Step 1: Lex
      var lexer = AWKLexer(options.lexprog ?? "")
      let tokens = try lexer.tokenize()          // → [AWKToken]

      // Step 2: Parse
      let ast = try AWKParser.parse(tokens)      // → AWKProgram


      //    yyparse();
      setlocale(LC_NUMERIC, ""); /* back to whatever it is locally */

      // FIXME: put me back
      /*
       if (fs) {
       *FS = qstring(fs, "\0");
       }
       DPRINTF("errorflag=%d\n", errorflag);
       if (errorflag == 0) {
       compile_time = RUNNING;





       run(winner);
*/

        // Step 3: Execute
        // From files:
      try run(ast, inputPaths: options.args)
        // From stdin (no inputPaths):
//        try run(ast, inputPaths: [], programArgs: ["awk"])


      // FIXME: put me back
/*
       } else {
       bracecheck();
       }
       return(errorflag);
       */
    } catch(let e) {
      throw CmdErr(2, "\(e.localizedDescription)")
    }
  }

  var usage : String { "usage: \(programName) [-F fs] [-v var=value] [-f progfile | 'prog'] [file ...]" }


/*

int	dbg	= 0;
Awkfloat	srand_seed = 1;
char	*cmdname;	// gets argv[0] for error messages
extern	FILE	*yyin;	// lex input file
char	*lexprog;	// points to program argument if it exists
extern	int errorflag;	// non-zero if any syntax errors; set by yyerror
enum compile_states	compile_time = ERROR_PRINTING;

static size_t	curpfile;	// current filename

bool	safe = false;	// true => "safe" mode
int	Unix2003_compat;
*/



  /*
func setfs(_ p : String) -> String? {
	/* wart: t=>\t */
  if (p[0] == "t" && p[1] == "\0") {
    return "\t";
  }
  else if (p[0] != "\0") {
    return p;
  }
	return nil
}
*/


/*
func getarg(int *argc, char ***argv, const char *msg)
{
	if ((*argv)[1][2] != '\0') {	// arg is -fsomething
		return &(*argv)[1][2];
	} else {			// arg is -f something
		(*argc)--; (*argv)++;
		if (*argc <= 1)
			FATAL("%s", msg);
		return (*argv)[1];
	}
}
*/


  /*
func pgetc() -> Character { // get 1 character from awk program
  while true {
		if (yyin == NULL) {
      if (curpfile >= npfile) {
        return EOF;
      }
      if (strcmp(pfile[curpfile], "-") == 0) {
        yyin = stdin;
      }
      else if ((yyin = fopen(pfile[curpfile], "r")) == NULL) {
        FATAL("can't open file %s", pfile[curpfile]);
      }
			lineno = 1;
		}
    if ((c = getc(yyin)) != EOF) {
      return c;
    }
    if (yyin != stdin) {
      fclose(yyin);
    }
		yyin = NULL;
		curpfile++;
	}
}
*/

func cursource()	-> String? { // current source file name
  if (options.pfile.count > 0) {
    return options.pfile[runtime.curpfile < options.pfile.count ? runtime.curpfile : runtime.curpfile - 1]
  }
  else {
    return nil
  }
}

  func DPRINTF(_ s : String) {
    if options.dbg > 0 {
      print(s)
    }
  }
}



// May return now, if kill(2)-delivered in conformance mode.
  func fpecatch(_ n : Int32, _ six : UnsafeMutablePointer<siginfo_t>?, _ uc : UnsafeMutableRawPointer?) {


let si = six!

  let emsg = [
    0 : "Unknown error",
    FPE_INTDIV : "Integer divide by zero",
    FPE_INTOVF : "Integer overflow",
    FPE_FLTDIV : "Floating point divide by zero",
    FPE_FLTOVF : "Floating point overflow",
    FPE_FLTUND : "Floating point underflow",
    FPE_FLTRES : "Floating point inexact result",
    FPE_FLTINV : "Invalid Floating point operation",
    FPE_FLTSUB : "Subscript out of range",
  ]



  if (si.pointee.si_code == 0) {

     // 0 == FPE_NOOP, used when delivered by kill(2).  We just
     // reset the disposition and re-deliver SIGFPE for conformance
     // purposes.

    signal(SIGFPE, SIG_DFL);
    raise(SIGFPE);
    return;
  }


let fx = si.pointee.si_code < emsg.count && emsg[si.pointee.si_code] != nil
    ? emsg[si.pointee.si_code] : emsg[0]
    // was FATAL(...)
    var se = FileDescriptor.standardError
    print("floating point exception: \(fx ?? "??")", to: &se)
    exit(2)
}

