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

typealias Awkfloat = Double

extension awk {





  /*

   #define	FULLTAB	2	/* rehash when table gets this x full */
   #define	GROWTAB 4	/* grow table by this factor */

   Array	*symtab;	/* main symbol table */

   char	**FS;		/* initial field sep */
   char	**RS;		/* initial record sep */
   char	**OFS;		/* output field sep */
   char	**ORS;		/* output record sep */
   char	**OFMT;		/* output format for numbers */
   char	**CONVFMT;	/* format for conversions in getsval */
   Awkfloat *NF;		/* number of fields in current record */
   Awkfloat *NR;		/* number of current record */
   Awkfloat *FNR;		/* number of current record in current file */
   char	**FILENAME;	/* current filename argument */
   Awkfloat *ARGC;		/* number of arguments from command line */
   char	**SUBSEP;	/* subscript separator for a[i,j,k]; default \034 */
   Awkfloat *RSTART;	/* start of re matched with ~; origin 1 (!) */
   Awkfloat *RLENGTH;	/* length of same */

   Cell	*fsloc;		/* FS */
   Cell	*nrloc;		/* NR */
   Cell	*nfloc;		/* NF */
   Cell	*fnrloc;	/* FNR */
   Cell	*ofsloc;	/* OFS */
   Cell	*orsloc;	/* ORS */
   Cell	*rsloc;		/* RS */
   Cell	*rstartloc;	/* RSTART */
   Cell	*rlengthloc;	/* RLENGTH */
   Cell	*subseploc;	/* SUBSEP */
   Cell	*symtabloc;	/* SYMTAB */

   Cell	*nullloc;	/* a guaranteed empty cell */
   Node	*nullnode;	/* zero&null, converted into a node for comparisons */
   Cell	*literal0;

   extern Cell **fldtab;

   static void
   setfree(Cell *vp)
   {
   if (&vp->sval == FS || &vp->sval == RS ||
   &vp->sval == OFS || &vp->sval == ORS ||
   &vp->sval == OFMT || &vp->sval == CONVFMT ||
   &vp->sval == FILENAME || &vp->sval == SUBSEP)
   vp->tval |= DONTFREE;
   else
   vp->tval &= ~DONTFREE;
   }
*/

  /*
   void arginit(int ac, char **av)	/* set up ARGV and ARGC */
   {
   Cell *cp;
   int i;
   char temp[50];

   ARGC = &setsymtab("ARGC", "", (Awkfloat) ac, NUM, symtab)->fval;
   cp = setsymtab("ARGV", "", 0.0, ARR, symtab);
   ARGVtab = makesymtab(NSYMTAB);	/* could be (int) ARGC as well */
   free(cp->sval);
   cp->sval = (char *) ARGVtab;
   for (i = 0; i < ac; i++) {
   sprintf(temp, "%d", i);
   if (is_number(*av))
   setsymtab(temp, *av, atof(*av), STR|NUM, ARGVtab);
   else
   setsymtab(temp, *av, 0.0, STR, ARGVtab);
   av++;
   }
   }
*/

  func envinit() { // set up ENVIRON variable
    var aa = [String:Cell]()
    for (k, v) in Environment.getenv() { aa[k]=Cell(string: v, named: k) }
    runtime.symtab["ENVIRON"] = Cell(dict: aa, named: "ENVIRON")
   }

  /*
   Array *makesymtab(int n)	/* make a new symbol table */
   {
   Array *ap;
   Cell **tp;

   ap = malloc(sizeof(*ap));
   tp = calloc(n, sizeof(*tp));
   if (ap == NULL || tp == NULL)
   FATAL("out of space in makesymtab");
   ap->nelem = 0;
   ap->size = n;
   ap->tab = tp;
   return(ap);
   }

   int insymtab(Cell *ap, Cell *needle)	/* Determines if needle is in the symbol table */
   {
   Cell *cp;
   Array *tp;
   int i;

   DPRINTF("insymtab %p: n=%s s=\"%s\" f=%g t=%o\n",
   (void*)ap, ap->nval, ap->sval, ap->fval, ap->tval);

   if (!isarr(ap))
   return 0;

   tp = (Array *) ap->sval;
   if (tp == NULL)
   return 0;

   for (i = 0; i < tp->size; i++) {
   for (cp = tp->tab[i]; cp != NULL; cp = cp->cnext) {
   if (cp == needle) {
   return 1;
   }
   }
   }
   return 0;
   }

   void freesymtab(Cell *ap)	/* free a symbol table */
   {
   Cell *cp, *temp;
   Array *tp;
   int i;

   if (!isarr(ap))
   return;
   tp = (Array *) ap->sval;
   if (tp == NULL)
   return;
   for (i = 0; i < tp->size; i++) {
   for (cp = tp->tab[i]; cp != NULL; cp = temp) {
   xfree(cp->nval);
   if (freeable(cp))
   xfree(cp->sval);
   temp = cp->cnext;	/* avoids freeing then using */
   free(cp);
   tp->nelem--;
   }
   tp->tab[i] = NULL;
   }
   if (tp->nelem != 0)
   WARNING("can't happen: inconsistent element count freeing %s", ap->nval);
   free(tp->tab);
   free(tp);
   }

   void freeelem(Cell *ap, const char *s)	/* free elem s from ap (i.e., ap["s"] */
   {
   Array *tp;
   Cell *p, *prev = NULL;
   int h;

   tp = (Array *) ap->sval;
   h = hash(s, tp->size);
   for (p = tp->tab[h]; p != NULL; prev = p, p = p->cnext)
   if (strcmp(s, p->nval) == 0) {
   if (prev == NULL)	/* 1st one */
   tp->tab[h] = p->cnext;
   else			/* middle somewhere */
   prev->cnext = p->cnext;
   if (freeable(p))
   xfree(p->sval);
   free(p->nval);
   free(p);
   tp->nelem--;
   return;
   }
   }
   */


  /*
   int hash(const char *s, int n)	/* form hash value for string s */
   {
   unsigned hashval;

   for (hashval = 0; *s != '\0'; s++)
   hashval = (*s + 31 * hashval);
   return hashval % n;
   }

   void rehash(Array *tp)	/* rehash items in small table into big one */
   {
   int i, nh, nsz;
   Cell *cp, *op, **np;

   nsz = GROWTAB * tp->size;
   np = calloc(nsz, sizeof(*np));
   if (np == NULL)		/* can't do it, but can keep running. */
   return;		/* someone else will run out later. */
   for (i = 0; i < tp->size; i++) {
   for (cp = tp->tab[i]; cp; cp = op) {
   op = cp->cnext;
   nh = hash(cp->nval, nsz);
   cp->cnext = np[nh];
   np[nh] = cp;
   }
   }
   free(tp->tab);
   tp->tab = np;
   tp->size = nsz;
   }
*/

/*
   char *qstring(const char *is, int delim)	/* collect string up to next delim */
   {
   const char *os = is;
   int c, n;
   const uschar *s = (const uschar *) is;
   uschar *buf, *bp;

   if ((buf = malloc(strlen(is)+3)) == NULL)
   FATAL( "out of space in qstring(%s)", s);
   for (bp = buf; (c = *s) != delim; s++) {
   if (c == '\n')
   SYNTAX( "newline in string %.20s...", os );
   else if (c != '\\')
   *bp++ = c;
   else {	/* \something */
   c = *++s;
   if (c == 0) {	/* \ at end */
   *bp++ = '\\';
   break;	/* for loop */
   }
   switch (c) {
   case '\\':	*bp++ = '\\'; break;
   case 'n':	*bp++ = '\n'; break;
   case 't':	*bp++ = '\t'; break;
   case 'b':	*bp++ = '\b'; break;
   case 'f':	*bp++ = '\f'; break;
   case 'r':	*bp++ = '\r'; break;
   case 'v':	*bp++ = '\v'; break;
   case 'a':	*bp++ = '\a'; break;
   default:
   if (!isdigit(c)) {
   *bp++ = c;
   break;
   }
   n = c - '0';
   if (isdigit(s[1])) {
   n = 8 * n + *++s - '0';
   if (isdigit(s[1]))
   n = 8 * n + *++s - '0';
   }
   *bp++ = n;
   break;
   }
   }
   }
   *bp++ = 0;
   return (char *) buf;
   }

   const char *flags2str(int flags)
   {
   static const struct ftab {
   const char *name;
   int value;
   } flagtab[] = {
   { "NUM", NUM },
   { "STR", STR },
   { "DONTFREE", DONTFREE },
   { "CON", CON },
   { "ARR", ARR },
   { "FCN", FCN },
   { "FLD", FLD },
   { "REC", REC },
   { "CONVC", CONVC },
   { "CONVO", CONVO },
   { NULL, 0 }
   };
   static char buf[100];
   int i;
   char *cp = buf;

   for (i = 0; flagtab[i].name != NULL; i++) {
   if ((flags & flagtab[i].value) != 0) {
   if (cp > buf)
   *cp++ = '|';
   strcpy(cp, flagtab[i].name);
   cp += strlen(cp);
   }
   }

   return buf;
   }
   */
}
