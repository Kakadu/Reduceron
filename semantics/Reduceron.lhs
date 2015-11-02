> module Main where
> import Data.List
> import Data.Bits ((.&.))
6> import Data.Array
6> import System.Environment (getArgs)

[[This is based on text extracted from

  reduceron-report.pdf
  The Reduceron Reconfigured
  Matthew Naylor Colin Runciman
  University of York, UK {mfn,colin}@cs.york.ac.uk

This defines the basic Reduceron machine.

The source uses a style inspired by

        Implementing functional languages
        ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        Simon Peyton Jones and David Lester
        Prentice Hall 1992

to include multiple variants in a single source.  The Bird marks (> )
can be prefixed with the variant(s) in which it should be included
(options being N, N-, -M, or N-M).  Currently only single digit
variant numbers are supported.

I tried to make as few as possible changes to the text, but to
ultimately enable the use of flite compiled sources, I did conceed the
change of "PTR" to "VAR" to match the Reduceron implementation (I
liked PTR better though).]]



2.7 Template Code

We are now very close to the template code that can be executed by the
Reduceron. We shall define template code as a Haskell data type, paving
the way for an executable semantics to be defined in the next
section. To highlight the semantics, each semantic definition is
prefixed with a '>' symbol.

In template code, a program is defined to be a list of templates.

> type Prog = [Template]

A template represents a function definition. It contains an arity, a
spine application and a list of nested applications.

-3> type Template = (Arity, App, [App])
> type Arity = Int

The spine application holds the let-body of a definition's expression
graph and the nested applications hold the let-bindings. Applications
are flat and are represented as a list of atoms.

-5> type App = [Atom]

An atom is a small, tagged piece of non-recursive data, defined in
Figure 2. The following paragraphs define how programs are translated
to template code.

Functions: Given a list of function definitions

   f0 x0 = e0 , . . . , fn xn = en

each function identifier fi occurring in e0 ... en is translated to an
atom FUN #f i where #f is the arity of function f.

Arguments: In each definition f x0 . . . xn = e, each variable xi
occurring in e is translated to an atom ARG i.

Let-Bound Variables: In each expression graph

  let { x0 = e0 ; . . . ; xn = en } in e

each xi occurring in e, e0 . . . en is translated to an atom
VAR i.

Integers, Primitives, and Constructors:  An integer literal n, a
primitive p, and a constructor Ci are translated to atoms INT n, PRI
p, and CON #Ci i respectively.

Case Tables: Given a list of function definitions

  f0 x0 = e0 , . . . , fn xn = en

each case table <fi , . . . fj > occurring in e0 . . . en is
translated to an atom TAB i. We assume that the functions in each case
table are defined contiguously in the program.

Example: The template code for the program

  main = tri 5
  tri n = let x = n (<=) in 1 x <falseCase, trueCase> n
  falseCase t n =
     let {x0 = tri x1 (+); x1 = 1 x2; x2 = n (-)} in n x0
  trueCase t n = 1

is as follows.

> tri5 :: Prog
1> tri5 = [ (0, [FUN 1 1, INT 5], [])
1>        , (1, [INT 1, VAR 0, TAB 2, ARG 0],
1>              [[ARG 0, PRI "(<=)"]])
1>        , (2, [ARG 1, VAR 0],
1>              [[FUN 1 1, VAR 1, PRI "(+)"],
1>               [INT 1, VAR 2],
1>               [ARG 1, PRI "(-)"]])
1>        , (2, [INT 1], []) ]


Figure 2. Syntax of atoms in template code.

1> data Atom
1>   = FUN Arity Int
1>   | ARG Int
1>   | VAR Int
1>   | CON Arity Int
1>   | INT Int
1>   | PRI String
1>   | TAB Int
1>   deriving Show



3. Operational Semantics

This section defines a small-step operational semantics for the
Reduceron. There are two main reasons for presenting a semantics: (1)
to define precisely how the Reduceron works; and (2) to highlight the
low-level parallelism present in graph reduction that is exploited by
the Reduceron. We have found it very useful to encode the semantics
directly in Haskell. Before we commit to a low-level implementation,
we can assess the complexity and performance of different design
decisions and optimisations.

At the heart of the semantic definition is the small-step state
transition function

> step :: State -> State

where the state is a 4-tuple comprising a program, a heap, a reduction
stack, and an update stack.

-5> type State = (Prog, Heap, Stack, UStack)

The heap is modelled as a list of applications, and can be indexed by a heap-address.

> type Heap = [App]
> type HeapAddr = Int

An element on the heap can be modified using the update function.

> update :: HeapAddr -> App -> Heap -> Heap
> update i a as = take i as ++ [a] ++ drop (i+1) as

The reduction stack is also modelled as a list of nodes, with the top
stack element coming first and the bottom element coming last.

> type Stack = [Atom]
> type StackAddr = Int

There is also an update stack.

> type UStack = [Update]
> type Update = (StackAddr, HeapAddr)

The meaning of a program p is defined by run p where

> run :: Prog -> Int
-4> run p = eval initialState
-4>   where initialState = (p, [], [FUN 0 0], [])

-5> eval (p, h, [INT i], u) = i
-5> eval s = eval (step s)

The initial state of the evaluator comprises a program, an empty heap,
a singleton stack containing a call to main, and an empty update
stack. The main template has arity 0 and is assumed to be the template
at address 0. To illustrate, run tri5 yields 15. In the following
sections, the central step function is defined.


3.1 Primitive Reduction

The prim function applies a primitive function to two arguments
supplied as fully-evaluated integers.

-2> prim :: String -> Atom -> Atom -> Atom
-2> prim "(+)" (INT n) (INT m) = INT (n+m)
-2> prim "(-)" (INT n) (INT m) = INT (n-m)
-2> prim "(<=)" (INT n) (INT m) = bool (n<=m)

The comparison primitive returns a boolean value. Both boolean
constructors have arity 0; False has index 0 and True has index 1.

> bool :: Bool -> Atom
> bool False = CON 0 0
> bool True = CON 0 1


3.2 Normal Forms

The number of arguments demanded by an atom on top of the reduction
stack is defined by the arity function.

> arity :: Atom -> Arity
-4> arity (FUN n i) = n
-4> arity (INT i) = 1
-4> arity (CON n i) = n+1
-4> arity (PRI p) = 2

To reduce an integer, the evaluator demands one argument as shown in
rewrite rule (2). And to reduce a constructor of arity n, the
evaluator requires n + 1 arguments (the constructor's arguments and
the case table) as shown in rewrite rule (3).

The arity of an atom is only used to detect when a normal form is
reached. A normal form is an application of length n whose first atom
has arity >= n.

Some functions, such as case-alternative functions, are statically
known never to be partially-applied, so they cannot occur as the first
atom of a normal form. Such a function, say with address n, can be
represented by the atom FUN 0 n.


3.3 Step-by-Step Reduction

There is one reduction rule for each possible type of atom that can
appear on top of the reduction stack.

Unwinding: If the top of the reduction stack is a pointer x to an
application on the heap, evaluation proceeds by unwinding: copying the
application from the heap to the reduction stack where it can be
reduced. We must also ensure that when evaluation of the application
is complete, the location x on the heap can be updated with the
result. So we push onto the update stack the heap address x and the
current size of the reduction stack.

1> step (p, h, VAR x:s, u) = (p, h, h!!x ++ s, upd:u)
1>   where upd = (1+length s, x)

Updating: Evaluation of an application is known to be complete when an
argument is demanded whose index is larger than n, the difference
between the current size of the reduction stack and the stack address
of the top update. If this condition is met, then a normal form of
arity n is on top of the reduction stack and must be written to the
heap.

1> step (p, h, top:s, (sa,ha):u)
1>   | arity top > n = (p, h', top:s, u)
1>   where
1>     n = 1+length s - sa
1>     h' = update ha (top:take n s) h

Integers and Primitives: Integer literals and primitive functions are
reduced as described in Section 2.3.

1> step (p, h, INT n:x:s, u) = (p, h, x:INT n:s, u)
1> step (p, h, PRI f:x:y:s, u) = (p, h, prim f x y:s, u)

Constructors: Constructors are reduced by indexing a case table, as
described in Section 2.4.

1> step (p, h, CON n j:s, u) = (p, h, FUN 0 (i + j):s,u)
1>   where TAB i = s !! n

There is insufficient information available to compute the arity of the
case-alternative function at address i+j. However, an arity of zero
can be used because a case-alternative function is statically known
not to be partially applied (Section 3.2).

Function Application: To apply a function f of arity n, n + 1 elements
are popped off the reduction stack, the spine application of the body
of f is instantiated and pushed onto the reduction stack, and the
remaining applications are instantiated and appended to the heap.

1> step (p, h, FUN n f:s, u) = (p, h', s', u)
1>   where
1>     (pop, spine, apps) = p !! f
1>     h' = h ++ map (instApp s h) apps
1>     s' = instApp s h spine ++ drop pop s

Instantiating a function body involves replacing the formal parameters
with arguments from the reduction stack and turning relative pointers
into absolute ones.

-3> instApp :: Stack -> Heap -> App -> App
-3> instApp s h = map (inst s (length h))

-3> inst :: Stack -> HeapAddr -> Atom -> Atom
1> inst s base (VAR p) = VAR (base + p)
1> inst s base (ARG i) = s !! i
1> inst s base a = a


5. Optimisations

This section presents several optimisations, defined by a series of
progressive modifications to the semantics defined in Section 3. A
theme of this section is the use of cheap dynamic analyses to improve
performance.

5.1 Update Avoidance

Recall that when evaluation of an application on the heap is complete,
the heap is updated with the result to prevent repeated evaluation.
There are two cases in which such an update is unnecessary: (1) the
application is already evaluated, and (2) the application is not
shared so its result will never be needed again.

We identify non-shared applications at run-time, by dynamic analysis.
Argument and pointer atoms are extended to contain an extra boolean
field.

2-3> data Atom
2-3>   = FUN Arity Int
2-3>   | ARG Bool Int   -- changed
2-3>   | VAR Bool Int   -- changed
2-3>   | CON Arity Int
2-3>   | INT Int
2-3>   | PRI String
2-3>   | TAB Int
2-3>   deriving Show

An argument is tagged with True exactly if it is referenced more than
once in the body of a function. A pointer is tagged with False exactly
if it is a unique pointer; that is, it points to an application that
is not pointed to directly by any other atom on the heap or reduction
stack. There may be multiple pointers to an application containing a
unique pointer, so the fact that a pointer is unique is, on its own,
not enough to infer that it points to a non-shared application. To
identify non-shared applications, we maintain the invariant:

  Invariant 3: A unique pointer occurring on the reduction stack
  points to a non-shared application.

A pointer that is not unique is referred to as possibly-shared.

Unwinding: The reduction rule for unwinding becomes

2> step (p, h, VAR sh x:s, u) = (p, h, app++s, upd++u)
2>   where
2>     app = map (dashIf sh) (h !! x)
2>     upd = [(1 + length s, x) | sh && red (h !! x)]

Updating: When an update occurs, the normal-form on the stack is
written to the heap. The normal-form may contain a unique pointer, but
the process of writing it to the heap will duplicate it. Hence the
normal-form on the stack is dashed.

[[The paper and report has a bug here: the update application wasn't
dashed.]]

2> step (p, h, top:s, (sa,ha):u)
2>   | arity top > n = (p, h', top:dashN n s, u)
2>   where
2>     n = 1 + length s - sa
2>     h' = update ha (top:dashN n (take n s)) h

The rest is the same but has to be repeated as function definitions
have to be continous.

2> step (p, h, INT n:x:s, u) = (p, h, x:INT n:s, u)
2> step (p, h, PRI f:x:y:s, u) = (p, h, prim f x y:s, u)
2> step (p, h, CON n j:s, u) = (p, h, FUN 0 (i + j):s,u)
2>   where TAB i = s !! n
2> step (p, h, FUN n f:s, u) = (p, h', s', u)
2>   where
2>     (pop, spine, apps) = p !! f
2>     h' = h ++ map (instApp s h) apps
2>     s' = instApp s h spine ++ drop pop s

If the pointer on top of the stack is possibly-shared, then the
application is dashed before being copied onto the stack by marking
each atom it contains as possibly-shared. This has the effect of
propagating sharing information through an application.

2-> dashIf sh a = if sh then dash a else a
2-> dash (VAR sh s) = VAR True s
2-> dash a = a

If the pointer on top of the stack is unique, the application it
points to must be non-shared according to Invariant 3. An update is
only pushed onto the update stack if the pointer is possibly-shared
and the application is reducible. An application is reducible if it is
saturated or its first atom is a pointer.

2-5> red :: App -> Bool
2-5> red (VAR sh i:xs) = True
2-5> red (x:xs) = arity x <= length xs

2-> dashN n s = map dash (take n s) ++ drop n s

It is unnecessary to dash the normal-form that is written to the heap,
but there is no harm in doing so: the application being updated is
possibly-shared, and a possibly-shared application will anyway be
dashed when it is unwound onto the stack.

Function Application: When instantiating a function body, shared
arguments must be dashed as they are fetched from the stack.

2-3> inst s base (ARG sh i) = dashIf sh (s !! i)
2-3> inst s base (VAR sh p) = VAR sh (base + p)
2-3> inst s base a = a

Performance: Table 3 shows that, overall, update avoidance offers a
significant run-time improvement. On average, 88% of all updates are
avoided across the 16 benchmark programs. Just over half of these are
avoided due to non-reducible applications, and just under half of them
are avoided due to non-shared reducible applications. The average
maximum update-stack usage drops from 406 to 11.

2> tri5 = [ (0, [FUN 1 1, INT 5], [])
2>        , (1, [INT 1, VAR False 0, TAB 2, ARG True 0],
2>              [[ARG True 0, PRI "(<=)"]])
2>        , (2, [ARG True 1, VAR False 0],
2>              [[FUN 1 1, VAR False 1, PRI "(+)"],
2>               [INT 1, VAR False 2],
2>               [ARG True 1, PRI "(-)"]])
2>        , (2, [INT 1], []) ]


5.2 Infix Primitive Applications

[[Silently changing prim to take primitive integers]]

3-> prim :: String -> Int -> Int -> Atom

For every binary primitive function p, we introduce a new primitive
*p, a version of p that expects its arguments flipped.

3-> prim ('*':p) n m = prim p m n
3-> prim ('s':'w':'a':'p':':':p) n m = prim p m n
3-> prim "(+)" n m = INT (n+m)
3-> prim "(-)" n m = INT (n-m)
3-> prim "(<=)" n m = bool (n<=m)
3-> prim "(==)" n m = bool (n==m)
3-> prim "(/=)" n m = bool (n/=m)
3-> prim "(.&.)" n m = INT (n .&. m)
3-> prim s n m = error ("Unsupported primitive " ++ show s)

Any primitive function p can be flipped.

3-> flipPrim ('*':p) = p
3-> flipPrim p = '*':p

Now we translate binary primitive applications by the rule

                            p m n -> m p n             (4)

3> step (p, h, VAR sh x:s, u) = (p, h, app++s, upd++u)
3>   where
3>     app = map (dashIf sh) (h !! x)
3>     upd = [(1 + length s, x) | sh && red (h !! x)]
3> step (p, h, top:s, (sa,ha):u)
3>   | arity top > n = (p, h', top:dashN n s, u)
3>   where
3>     n = 1 + length s - sa
3>     h' = update ha (top:dashN n (take n s)) h
3> step (p, h, CON n j:s, u) = (p, h, FUN 0 (i + j):s,u)
3>   where TAB i = s !! n
3> step (p, h, FUN n f:s, u) = (p, h', s', u)
3>   where
3>     (pop, spine, apps) = p !! f
3>     h' = h ++ map (instApp s h) apps
3>     s' = instApp s h spine ++ drop pop s

In place of the existing reduction rules for primitives and integers,
we define:

3> step (p, h, INT m:PRI f:INT n:s, u) =
3>   (p, h, prim f m n:s, u)
3> step (p, h, INT m:PRI f:x:s, u) =
3>   (p, h, x:PRI (flipPrim f):INT m:s, u)



[[We'll have to recompile tri5]]

Underlying source

  main = tri 5
  tri n = case n <= 1 of
            False -> n + tri (n - 1)
            True -> 1

3> tri5 = [ (0, [FUN 1 1, INT 5], [])
3>        , (1, [ARG sh 0, PRI "(<=)", INT 1, TAB 2, ARG sh 0], [])
3>        , (2, [FUN 1 1, VAR False 0, PRI "(+)", ARG sh 1],
3>              [[ARG sh 1, PRI "(-)", INT 1]])
3>        , (2, [INT 1], []) ]
3>   where sh = True


5.3 Speculative Evaluation of Primitive Redexes

Consider evaluation of the expression tri 5. Application of tri yields
the expression

  case (<=) 5 1 of
    { False -> (+) (tri ((-) 5 1)) 5 ; True -> 1 }

which contains two primitive redexes: (<=) 5 1 and (-) 5 1. This
section introduces a technique called primitive-redex speculation
(PRS) in which such redexes are evaluated during function body
instantiation. For example, application of tri instead yields

  case False of { False -> (+) (tri 4) 5 ; True -> 1 }

The benefit is that primitive redexes need not be constructed in
memory, nor fetched again when needed.  Even if the result of a
primitive redex is not needed, reducing it is no more costly than
constructing it. We identify primitive redexes at run-time, by dynamic
analysis.

Register File: To support PRS, we introduce a register file to the
reduction machine, for storing the results of speculative reductions.

4-5> type RegFile = [Atom]
4-5> accessRF rf i = rf !! i
4-5> rf0 = []

The body of a function may refer to these results as required.

4> data Atom
4>   = FUN Arity Int
4>   | ARG Bool Int
4>   | VAR Bool Int
4>   | CON Arity Int
4>   | INT Int
4>   | PRI String
4>   | TAB Int
4>   | REG Bool Int   -- new
4>   deriving Show

An atom of the form REG b i contains a reference i to a register, and
a boolean field b that is true exactly if there is more than one
reference to the register in the body of the function.

The instantiation functions inst and instApp are modified to take the
register file r as an argument, and the following equation is added to
the definition of inst.

4-> inst :: Stack -> RegFile -> HeapAddr -> Atom -> Atom
4-> inst s r base (REG sh i) = dashIf sh (accessRF r i)
4-> inst s r base (VAR sh p) = VAR sh (base + p)
4-> inst s r base (ARG sh i) = dashIf sh (s !! i)
4-> inst s r base a = a

4-5> instApp :: Stack -> RegFile -> Heap -> [Atom] -> [Atom]
4-5> instApp s r h = map (inst s r (length h))


Waves: The primitive redexes in a function body are evaluated in a
series of waves. To illustrate, consider (+) 1 ((+) 2 3). In the first
wave of speculative evaluation, (+) 2 3 would be reduced to 5; in the
second wave, (+) 1 5 would be reduced to 6.

More specifically, a wave is a list of independent primitive redex
candidates. A primitive redex candidate is an application which may
turn out at run-time to be a primitive redex. Specifically, it is an
application of the form [a0 , PRI p, a1 ] where a0 and a1 are INT, ARG
or REG atoms.

4-> type Wave = [App]

Templates are extended to contain a list of waves in which no
application in a wave depends on the result of an application in the
same or a later wave.

4-5> type Template = (Arity, App, [App], [Wave])

Given the reduction stack, the heap, and a series of waves, PRS
produces a possibly-modified heap, and one result for each application
in each wave.

4-5> prs :: Stack -> Heap -> [Wave] -> (Heap, RegFile)
4-5> prs s h = foldl (wave s) (h, rf0)

4-5> wave s (h,r) = foldl spec (h,r) . map (instApp s r h)

If a primitive redex candidate turns out to be a primitive redex at
run-time, it is reduced, and its result is appended to the register
file. Otherwise, the candidate application is constructed on the heap,
and a pointer to this application is appended to the register file.

4> spec (h,r) [INT m,PRI p,INT n] = (h, r ++ [prim p m n])
4> spec (h,r) app = (h ++ [app], r ++ [VAR False (length h)])

Function Application: Since applications in a function body may refer
to the results in the PRS register file, PRS is performed before
instantiation of the body.

4> step (p, h, VAR sh x:s, u) = (p, h, app++s, upd++u)
4>   where
4>     app = map (dashIf sh) (h !! x)
4>     upd = [(1 + length s, x) | sh && red (h !! x)]
4> step (p, h, top:s, (sa,ha):u)
4>   | arity top > n = (p, h', top:dashN n s, u)
4>   where
4>     n = 1 + length s - sa
4>     h' = update ha (top:dashN n (take n s)) h
4> step (p, h, CON n j:s, u) = (p, h, FUN 0 (i + j):s,u)
4>   where TAB i = s !! n
4> step (p, h, INT m:PRI f:INT n:s, u) =
4>   (p, h, prim f m n:s, u)
4> step (p, h, INT m:PRI f:x:s, u) =
4>   (p, h, x:PRI (flipPrim f):INT m:s, u)

The new rule is:

4> step (p, h, FUN n f:s, u) = (p, h'', s', u)
4>   where
4>     (pop, spine, apps, waves) = p !! f
4>     (h', r) = prs s h waves
4>     s' = instApp s r h' spine ++ drop pop s
4>     h'' = h' ++ map (instApp s r h') apps

The template splitting technique outlined in Section 4.2 is modified
to deal with waves of primitive redex candidates. Each wave is split
into a separate template. If a wave contains more than MaxAppsPerBody
applications, it is further split in order to satisfy the constraint.

Strictness Analysis: PRS works well when recursive call sites sustain
unboxed arguments^2.  For example, if a call to tri is passed an
unboxed integer then, thanks to PRS, so too is the recursive call.
However, if the initial call is passed a boxed expression, primitive
redexes never arise, e.g. the outer call in tri (tri 5) is passed a
pointer to an application, inhibiting PRS.

A basic strictness analyser in combination with the workerwrapper
transformation [Gill and Hutton 2009] alleviates this problem.  Each
initial call to a recursive function is replaced with a call to a
wrapper function.  The wrapper applies a special primitive to force
evaluation of any strict integer arguments before passing them on to
the recursive worker.

Performance: Table 3 shows how PRS cuts run-time and heapusage over
the range of benchmark programs.  On average, the maximum stack usage
drops from 811 to 104, and 85% of primitive redex candidates turn out
to be primitive redexes.


We retranslate tri5 again:

  main = tri 5
  tri n = case n <= 1 of
            False -> tri (n - 1) + n
            True -> 1

4> tri5 = [ (0, [FUN 1 1, INT 5], [], [])
4>        , (1, [ARG sh 0, PRI "(<=)", INT 1, TAB 2, ARG sh 0], [], [])
4>        , (2, [FUN 1 1, REG unsh 0, PRI "(+)", ARG sh 1],
4>              [], [[[ARG sh 1, PRI "(-)", INT 1]]])
4>        , (2, [INT 1], [], []) ]
4>   where sh = True; unsh = False

[[End of Reduceron Reconfigured]]

While the variant 4 Reduceron is conceptually what has built, it's
different enough that we cannot execute the output of Flite.

Using the Tri.hs example again

{main = tri 5;
 tri n = case  (<=) n 1 of {
          False -> (+) tri ((-) n 1) n;
          True -> 1;};}

the default output from Flite is

$ ../fl -r Tri.hs
("main",0,[],[FUN True 1 1,INT 5],[])
("tri",1,[2],[ARG True 0,PRI 2 "(<=)",INT 1,ARG True 0],[])

("tri#1",1,[],[FUN True 1 1,PRI 2 "(+)",VAR False 0,ARG True 0],
              [APP False [ARG True 0,PRI 2 "(-)",INT 1]])
("tri#2",1,[],[INT 1],[])

With maxed out parameters

$ ../fl -r99:99:99:99:99 Tri.hs
("main",0,[],[FUN True 1 1,INT 5],[])
("tri",1,[2],[ARG True 0,PRI 2 "(<=)",INT 1,ARG True 0],[])

("tri#1",0,[],[FUN False 0 4],[PRIM 0 [ARG True 0,PRI 2 "(-)",INT 1]])
("tri#2",1,[],[INT 1],[])
("tri#1",1,[],[FUN True 1 1,PRI 2 "(+)",REG False 0,ARG True 0],[])

The data type differences from the trivial to the significant are:

-1. PTR got renamed to VAR (but we already took care of that).

0. Templates include the function name

1. PRI are redundantly annotated with arity (although currently the
   implementation only supports binary primitives).

2. FUN Atoms are annotated with whether they are 'original' flag on
   funtions; if true, function was originally defined, and if false,
   function was introduced in Reduceron compilation process.

   Long application are broken into parts, only the last of which is
   considered original.  Note, what *actually* matters here is that
   non-"original" functions may refer back to allocations performed by
   the preceeding functions in the chain, thus constraining the
   garbage collection.  For this reason, the FUN introduced by the CON
   step will be marked "original".

3. Template Apps now take a normal-form boolean - while redundant,
   having this immediately available can improve cycle-time.

4. The TAB Atom is gone - this is now part of the LUT list and the
   CASE App.

5. The Template is quite changed - the waves aren't separated but now
   appears as PRIM apps intermingled with applications and the case
   table is given as a separate lookup-table list.

NB: There is both a CASE LUT and a LUT list in the template.  The LUT
list is for the spine and the CASE is for suspended applications.

Rather than making all these changes in one big step, we'll proceed in
incremental steps (preliminary plan):

- Variant 5 with changes -1, 0, 1, 2, and 3.


Variant 5:

New Atom definition:

5-> type Orig = Bool
5-> data Atom
5->   = FUN Orig Arity Int        -- Original = no back referencing VARs
5->   | ARG Bool Int
5->   | VAR Bool Int              -- Renamed from VAR
5->   | CON Arity Int
5->   | INT Int
5->   | PRI Arity String          -- The arity is now included
5>   | TAB Int
5->   | REG Bool Int
5->   deriving (Show, Read)

The App gained a WHNF summary boolean, we'll use App5 for this

5> data App5 = APP { whnf :: Bool, appSpine :: App } deriving Show

The program template added a name

5> type Wave5 = [App5]
5> type Template5 = (String, Arity, App, [App5], [Wave5])
5> type Prog5 = [Template5]
5> fromProg5 :: Prog5 -> Prog
5> fromProg5 = map fromTemplate5 where
5>    fromTemplate5 (name, arity, app, spine, wave) =
5>       (arity, app, map appSpine spine, map (map appSpine) wave)

5-> arity (FUN o n i) = n
5-> arity (INT i)     = 1
5-> arity (CON n i)   = n+1
5-> arity (PRI n p)   = 2

5> spec (h,r) [INT m,PRI _ p,INT n] = (h, r ++ [prim p m n])
5> spec (h,r) app = (h ++ [app], r ++ [VAR False (length h)]) -- unchanged

The first two step cases as before.

5> step (p, h, VAR sh x:s, u) = (p, h, app++s, upd++u)
5>   where
5>     app = map (dashIf sh) (h !! x)
5>     upd = [(1 + length s, x) | sh && red (h !! x)]
5> step (p, h, top:s, (sa,ha):u)
5>   | arity top > n = (p, h', top:dashN n s, u)
5>   where
5>     n = 1 + length s - sa
5>     h' = update ha (top:dashN n (take n s)) h

The constructor step changed

5> step (p, h, CON n j:s, u) = (p, h, FUN True 0 (i + j):s,u) -- See discussion above
5>   where TAB i = s !! n

Primitives gained an arity

5> step (p, h, INT m:PRI _ f:INT n:s, u) =
5>   (p, h, prim f m n:s, u)
5> step (p, h, INT m:PRI n f:x:s, u) =
5>   (p, h, x:PRI n (flipPrim f):INT m:s, u)

And functions gained a boolean

5> step (p, h, FUN o n f:s, u) = (p, h'', s', u)
5>   where
5>     (pop, spine, apps, waves) = p !! f
5>     (h', r) = prs s h waves
5>     s' = instApp s r h' spine ++ drop pop s
5>     h'' = h' ++ map (instApp s r h') apps

5> run p = eval initialState
5>   where initialState = (p, [], [FUN True 0 0], [])

5> tri5 = fromProg5
5>        [ ("main",  0, [FUN True 1 1, INT 5], [], [])
5>        , ("tri",   1, [ARG sh 0, PRI 2 "(<=)", INT 1, TAB 2, ARG sh 0], [], [])
5>        , ("tri#1", 2, [FUN True 1 1, REG unsh 0, PRI 2 "(+)", ARG sh 1],
5>                       [], [[APP False [ARG sh 1, PRI 2 "(-)", INT 1]]])
5>        , ("tri#2", 2, [INT 1], [], []) ]
5>   where sh = True; unsh = False



Variant 6: we can finally accept full Flite programs.

Alas, much of the elegance of Variant 4 will go, but conceptually it's
still the same.

The Template is quite changed - the waves aren't separated, but now
appears as PRIM apps intermingled with applications.

6-> type RegId = Int
6-> type Normal = Bool
6-> type Spine = [Atom]
6-> data App
6->  = APP Normal Spine
6->  | CASE CaseTable Spine
6->  | PRIM RegId Spine
6->  deriving (Show, Read)

6-> type Template = (String, Arity, [CaseTable], Spine, [App])

The case table stack is in the state as is the Register file.  This is
necessary to fully handle split functions which can refer back to
results calculated earlier.

6-> type RegFile = Array Int Atom
6-> accessRF rf i = rf ! i
6-> updateRF :: Int -> Atom -> RegFile -> RegFile
6-> updateRF i a as = as // [(i, a)]
6-> rf0 = listArray (0,7) (repeat (INT 0))

6-> type CaseTable = Int
6-> type State = (Prog, Heap, Stack, RegFile, UStack, [CaseTable])

The TAB Atom is no longer part of the Atom but the case table is
exacted as part of applying a function, in parallel.

Most function have to be trivially adjusted to account for the new
types:

6-> step (p, h, VAR sh x:s, r, u, c) = (p, h, app++s, r, upd++u, t++c)
6->   where
6->     (app,t) = dashAppIf sh (h !! x)
6->     upd = [(1 + length s, x) | sh && red (h !! x)]

6-> step (p, h, top:s, r, (sa,ha):u, c)
6->   | arity top > n = (p, h', top:dashN n s, r, u, c)
6->   where
6->     n = 1 + length s - sa
6->     app = top : dashN n (take n s)
6->     h' = update ha (mkAPP app) h

6-> step (p, h, CON n j:s, r, u, i:c) = (p, h, FUN False 0 (i + j):s, r, u, c)

6-> step (p, h, INT m:PRI 2 f:INT n:s, r, u, c) =
6->   (p, h, prim f m n:s, r, u, c)

6-> step (p, h, INT m:PRI 2 f:x:s, r, u, c) =
6->   (p, h, x:PRI 2 (flipPrim f):INT m:s, r, u, c)

6-> step (p, h, FUN orig n f:s, r, u, c) = (p, h'', s', r', u, lut ++ c) where
6->   (name, pop, lut, spine, appsWaves) = p !! f
6->   (apps, prsApps) = partition isApp appsWaves
6->   (h', r') = prs s (h, r) prsApps -- XXX Fun True should start with empty RF
6->   s' = instSpine s r' h' spine ++ drop pop s
6->   h'' = h' ++ map (instApp s r h') apps

6-> prs :: Stack -> (Heap, RegFile) -> Wave -> (Heap, RegFile)
6-> prs s = foldr prs1 where
6->   prs1 (PRIM regid spine) (h,r) = spec h r regid (instSpine s r h spine)

6-> spec h r regid [INT m,PRI a p,INT n] = (h, updateRF regid (prim p m n) r)
6-> spec h r regid app = (h ++ [APP False app], updateRF regid (VAR False (length h)) r)

6-> instApp s r h (APP nf app) = APP nf (map (inst s r (length h)) app)
6-> instApp s r h (CASE lut app) = CASE lut (map (inst s r (length h)) app)

6-> instSpine :: Stack -> RegFile -> Heap -> Spine -> Spine
6-> instSpine s r h = map (inst s r (length h))

6-> dashAppIf :: Bool -> App -> (Spine, [CaseTable])
6-> dashAppIf False (APP nf app) = (app, [])
6-> dashAppIf True  (APP nf app) = (map dash app, [])
6-> dashAppIf False (CASE lut app) = (app, [lut])
6-> dashAppIf True  (CASE lut app) = (map dash app, [lut])

6-> mkAPP spine = APP (isNormal spine) spine

6-> isNormal (x:xs) = arity x > length xs

6-> isApp (PRIM regid app) = False
6-> isApp _                = True

6-> red :: App -> Bool
6-> red (APP nf as) = not nf
6-> red _           = True

6-> eval (p, h, [INT i], u, _, _) = i
6-> eval s = eval (step s)

6-> run p = eval initialState
6->   where initialState = (p, [], [FUN True 0 0], rf0, [], [])

6-> tri5 = [ ("main",  0, [],  [FUN True 1 1, INT 5], [])
6->        , ("tri",   1, [2], [ARG True 0, PRI 2 "(<=)", INT 1, ARG True 0], [])
6->        , ("tri#1", 1, [],  [FUN True 1 1, REG False 0, PRI 2 "(+)", ARG True 0],
6->                            [PRIM 0 [ARG True 0, PRI 2 "(-)", INT 1]])
6->        , ("tri#2", 1, [],  [INT 1], []) ]










[[Adding a bit of code to play with this]]

> runT :: Prog -> IO ()
> runT p = evalT 0 initialState
-4>   where initialState = (p, [], [FUN 0 0], [])
5>    where initialState = (p, [], [FUN True 0 0], [])
6->   where initialState = (p, [], [FUN True 0 0], rf0, [], [])

> evalT :: Int -> State -> IO ()
-5> evalT n (p, h, [INT i], u) =
6-> evalT n (p, h, [INT i], u, _, _) =
>   putStrLn ("Result: "++show i)
>
> evalT n s = do
>   putStrLn (show n ++ ":")
>   showState s
>   evalT (n+1) (step s)


> showState :: State -> IO ()
-5> showState (p, h, s, u) = do
6-> showState (p, h, s, r, u, c) = do
>   putStrLn ("Heap  : " ++ showList showHeapApp (zip [0..] h))
>   putStrLn ("Stack : " ++ showList showAtom s)
>   putStrLn ("UStack: " ++ showList showUStack u)
6->   putStrLn ("Regs  : " ++ showList showAtom (elems r))
6->   putStrLn ("LStack: " ++ showList show c)
>   putStrLn ""
>   where
>   showList show l = intercalate " " $ map show l
>   showHeapApp (a,app) = show a ++ "(" ++ showApp app ++ ")"
-5>   showApp app = show app
6>   showApp app = case app of
6>     APP nf spine     -> showSpine spine
6>     CASE ct spine    -> "CASE F"++show ct ++ " " ++ showSpine spine
6>     PRIM regid spine -> "r" ++ show regid ++ "=" ++ showSpine spine
6>   showSpine spine = showList showAtom spine
>   showAtom :: Atom -> String
>   showAtom a = case a of
-4>      FUN a 0 -> "Fmain"
-4>      FUN a i -> "F" ++ show i
5>      FUN _ a 0 -> "Fmain"
5>      FUN _ a i -> "F" ++ show i
6->      FUN _ a i -> case p !! i of (name, _, _, _, _) -> name
-1>      ARG i -> "a" ++ show i
-1>      VAR i -> "h" ++ show i
2->      ARG True  i -> "a" ++ show i ++ "*"
2->      ARG False i -> "a" ++ show i
2->      VAR True  i -> "h" ++ show i ++ "*"
2->      VAR False i -> "h" ++ show i
>      CON a i-> "C" ++ show i ++ replicate a '_'
>      INT i -> show i
-4>      PRI p -> p
5->      PRI _ p -> p
-5>      TAB i -> "T" ++ show i
>   showUStack (sp,haddr) = show sp ++ "-h" ++ show haddr

> main2 = putStrLn (show (run tri5))
-5> main = runT tri5

6> runP :: String -> IO ()
6> runP fn = do s <- readFile fn
6>              runT (map read (lines s) :: [Template])

Note, it probably will run out of memory while computing Parts or
anything beyond that.

6> testAll dir = mapM_ doOne programs
6>   where
6>   doOne p = do putStrLn $ p ++ ":"
6>                runP $ dir ++ p
6>   programs = ["Example.red", "SmallFib.red", "Fib.red", "Parts.red",
6>               "KnuthBendix.red", "CountDown.red", "Adjoxo.red",
6>               "Cichelli.red", "Taut.red", "While.red", "Braun.red",
6>               "MSS.red", "Clausify.red", "OrdList.red", "Queens.red",
6>               "Queens2.red", "PermSort.red", "SumPuz.red", "Mate2.red",
6>               "Mate.red"]

6> main = do args <- getArgs
6>           let (opts, files) = partition (\(c:_) -> c == '-') args
6>           if "-a" `elem` opts
6>           then testAll "../programs/gold/compiled/" -- (head files)
6>           else mapM_ (\p -> putStrLn (p ++ ":") >> runP p) files
