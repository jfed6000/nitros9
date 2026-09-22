********************************************************************
* dmafilltest - the rc16 VDMA fill soak, written to be handed to the
*   FPGA core developer with docs/rc16-dma-report.md.
*
* IT ASKS THE READER NOTHING.  It says on screen what it is about to do,
* what a pass looks like and what a failure looks like, runs, and prints
* a table that can be pasted back verbatim.  Everything we know about
* this engine was measured through bmtest, which has fifteen keys and
* assumes you wrote it; this does not.
*
* WHAT IT DOES.  It arms a 76,800-byte 1D fill on the VDMA and keeps the
* CPU occupied in one of ten different ways while the engine takes the
* bus, then reads the bitmap back and says whether the whole of it was
* written.  EVERY ATTEMPT IN EVERY CASE FILLS THE WHOLE BITMAP - first
* row 0, row count 0, which SS.BmClear turns into all 240 rows.  No
* bands and no half-fills: the only thing that changes from case to case
* is what the CPU is doing, so the numbers line up with the table in the
* report, which was also measured on the whole bitmap.
*
* THE TWO FAILURES ARE DIFFERENT AND THE TABLE KEEPS THEM APART.
*
*   A WEDGE is the one the report is about.  The engine halts the CPU to
*   take the bus and waits for BA & BS with no timeout; if the CPU is
*   executing when that lands the handshake can fail, the status sticks
*   at $80 and the machine is dead until it is power-cycled.  A wedge is
*   never printed - the machine is gone.  It is read off the LAST LINE
*   IN THE LOG, which names the case that was running.
*
*   A SHORT FILL is the other one, and it is not a wedge.  A whole 8-bit
*   fill needs 24.2 of the vertical-blanking window's 43 lines, so it has
*   to be armed by about line 19; armed later it runs out of window and
*   reports success having written only part.  At a free-running arming
*   phase that is about 4.4% of attempts IN EVERY CASE, INCLUDING THE
*   ONES THAT NEVER WEDGE.  A few percent in the "short" column is
*   expected and is not the bug this exists to show.
*
* THE ATTEMPT CAP IS IN ATTEMPTS AND NOT IN SECONDS on purpose.  Every
* attempt is one complete arm-to-completion cycle whatever the case is
* doing, so the cap is the honest unit: the cases that park the CPU run
* ~300 of them in about five seconds, and the three delay-loop cases run
* 100, which take longer each because the loop itself is sized to span
* the wait.  "arms" is printed, so the rate can always be recovered.
*
* NO BYTE OF THE BITMAP IS EVER READ AS THE WRONG ATTEMPT'S.  The fill
* value ALTERNATES between FILLA and FILLB, so a byte holding this
* attempt's value can only have been written by this attempt.  bmtest
* needed a full CPU redraw between fills for the same reason and paid
* 82 ms for it; this pays nothing.  The bitmap is cleared to 0 once at
* start-up so that the very first attempt has the same guarantee.
*
* VERIFICATION READS ONE BYTE PER ROW, NOT ALL 76,800.  A DMA fill is
* linear, so a short fill is a prefix and one sample per row finds the
* row it stopped on exactly.  A full byte-for-byte sweep costs ~60-80 ms
* - four frames - and would cut the attempt rate fivefold for no extra
* information.  Four sentinel bytes past the end of the bitmap catch the
* runaway pointer, and they are rewritten after every attempt so that
* each attempt is judged on its own.
*
* Keys: SPACE all ten cases   1-9 that case alone   0 case 10
*       L list the cases and what a K2 does with each   S skip
*       P sweep the arming line 0-63   W 8/16-bit   ESC or Q quit
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*  1       2026/09/21  Claude Opus 5 / John Federico
* Written to go with docs/rc16-dma-report.md.  Case 8 - polling $FEC1
* while a transfer is live, which is the worst row in the report's own
* table - needs a driver wait mode that does not exist yet and prints
* that it is unavailable rather than quietly testing something else.

                    nam       dmafilltest
                    ttl       rc16 VDMA fill soak

                    ifp1
                    use       defsfile
                    endc

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

BMPATH              equ       1         stdout - the terminal we draw on
NBLKS               equ       12        slab: ten for the bitmap plus slack
BMOFF               equ       $1000     the bitmap's offset INSIDE that slab
BMROWS              equ       240
BMCOLS              equ       320
BLKSIZE             equ       $2000
BMBYTES             equ       BMROWS*BMCOLS
* The two fill values, alternated so that no attempt can read the
* previous attempt's bytes as its own.  Both are dark, because the text
* overlay prints white over the whole screen and the readout matters
* more than the picture does.
FILLA               equ       1         dark blue
FILLB               equ       2         dark green
PREVAL              equ       0         what the bitmap holds before the first attempt
SENTVAL             equ       $AA       the four guard bytes past the end
NGUARD              equ       4
NCASES              equ       10
CAPFAST             equ       300       attempts for the parked and caller cases
CAPSLOW             equ       300       the loop cases get as many as the rest
CLRWAIT             equ       10        frames before a fill is called HUNG
POLLMAX             equ       2000      case 9: GetStat polls before giving up
RAMSPIN             equ       6000      case 10: passes of the user-state RAM loop
NOTBLT              equ       $FF       a case flag meaning "not built yet"
PHMAX               equ       63        P: the last arming line swept
PROGN               equ       16        attempts between progress lines in the log
PHADV               equ       8         arming lines advanced per attempt (see PhTick)
* The case table's shape.  Fixed-width names because they are also the
* screen's second column.
CE.FLAG             equ       0         the driver wait flags for SS.BmClear
CE.CALL             equ       1         0 sleep, 1 poll, 2 user-state RAM loop
CE.STAT             equ       2         0 user state, 1 system state
CE.EXP              equ       3         what a K2 does with it - an ExpTab index
CE.CAP              equ       4         attempts, 2 bytes
CE.NAME             equ       6
CNAMEW              equ       26
ENTSZ               equ       CE.NAME+CNAMEW
* THE EXPECTATIONS LIVE IN THE CASE TABLE, one code per case, so that
* what `L` promises and what the sweep runs cannot drift apart.  A
* separate list of "what to expect" is a list that goes stale.
EXPW                equ       28        fixed width, because it is a column
X.Never             equ       0
X.Robust            equ       1
X.Best              equ       2
X.Many              equ       3
X.Few               equ       4
X.First             equ       5
X.New               equ       6
* The columns of the result line, so the header and the rows cannot
* drift apart.
COLNAME             equ       5
COLSTAT             equ       33
COLARMS             equ       39
COLOK               equ       45
COLSHRT             equ       52
COLERR              equ       59
COLHUNG             equ       66
COLEXP              equ       38        L: where the expectation starts
COLPHOU             equ       22        P: where the outcome starts
COLNOTE             equ       72
* The outcome of one attempt.
O.OK                equ       0
O.SHORT             equ       1
O.OVER              equ       2
O.ERR               equ       3
O.HUNG              equ       4

                    mod       eom,name,tylg,atrv,start,size

slabblk             rmb       1         first block of the SS.GfxAlloc slab
gotslab             rmb       1         non-zero once the slab is ours
defined             rmb       1         non-zero while bitmap 0 is defined
mcrlo               rmb       1         the display mode to put back
mcrhi               rmb       1
curblk              rmb       1         the block mapped now
winaddr             rmb       2         where that block is mapped
runlen              rmb       2         PreFill: bytes of this row still to write
blkoff              rmb       2         the offset inside the current block
rowsleft            rmb       2         rows still to walk
wide                rmb       1         non-zero = ask for 16-bit transfers
fillv               rmb       1         the value THIS attempt writes
case                rmb       1         the case being run, 1-NCASES
sweep               rmb       1         non-zero while SPACE's sweep is running
abort               rmb       1         non-zero once ESC has been seen
arms                rmb       2         attempts made in this case
nok                 rmb       2         ... that filled the whole bitmap
nshort              rmb       2         ... that came up short
nerr                rmb       2         ... that returned an error
nhung               rmb       2         ... whose status never cleared
lasterr             rmb       1         the last error code seen in this case
tmperr              rmb       1         the GetStat's B, kept until its carry is read
armline             rmb       1         P: the line to arm on, 0 = free-running
gotline             rmb       1         ... and the line the driver says it got
badrow              rmb       2         the first short row seen in this case
gotbad              rmb       1         non-zero once badrow means something
capleft             rmb       2         attempts still to make
outcome             rmb       1         O.* for the attempt just made
stoprow             rmb       2         the row this attempt stopped on
cobusy              rmb       2         GetStat: 0 idle, 1 still outstanding
clrtck              rmb       1         frames waited for the fill to finish
dcval               rmb       2         AppDc16: what is left to print
dcdig               rmb       1         AppDc16: the digit being built
dcsup               rmb       1         AppDc16: non-zero once a digit has gone out
logpath             rmb       1         $FF = no log
logposh             rmb       2         bytes written, high half - a long session passes 64K
logposl             rmb       2         ... and low, so a reopen can seek to the end
progcnt             rmb       1         attempts since the last progress line
phstep              rmb       1         non-zero = step the arming line every attempt
keybuf              rmb       1
linebuf             rmb       100
                    rmb       300       stack
size                equ       .

name                fcs       /dmafilltest/
                    fcb       edition

********************************************************************
* start
********************************************************************
start               clr       gotslab,u
                    clr       defined,u
                    clr       wide,u              8-bit until W says otherwise
                    clr       sweep,u
                    clr       abort,u
                    clr       armline,u
                    lda       #FILLB              so the first attempt uses FILLA
                    sta       fillv,u
                    lda       #$FF
                    sta       logpath,u
                    ldd       #0
                    std       logposh,u
                    std       logposl,u

                    leax      Ban1,pcr
                    lbsr      PutLine

* Remember the display mode, as bmtest and joust do, so Q can put it back.
                    lda       #BMPATH
                    ldb       #SS.DScrn
                    os9       I$GetStt
                    bcs       NoMode
                    tfr       x,d
                    stb       mcrlo,u
                    tfr       y,d
                    stb       mcrhi,u
                    bra       Setup
NoMode              lda       #FX_TXT
                    sta       mcrlo,u
                    lda       #FT_OMIT
                    sta       mcrhi,u

********************************************************************
* The bitmap this soak fills: our own blocks, at an offset inside them.
********************************************************************
Setup               ldx       #NBLKS
                    lda       #BMPATH
                    ldb       #SS.GfxAlloc
                    os9       I$SetStt
                    lbcs      Failed
                    tfr       x,d
                    stb       slabblk,u
                    inc       gotslab,u

                    lbsr      DefBm
                    lbcs      Failed
                    inc       defined,u
                    lbsr      SetClut
                    lbcs      Failed
                    lda       #1                  enable
                    ldb       #0                  CLUT 0
                    lbsr      SetCfg
                    lbcs      Failed

                    ldx       #0                  layer 0 (the front)
                    ldy       #0                  source 0 = bitmap 0
                    lda       #BMPATH
                    ldb       #SS.Layer
                    os9       I$SetStt
                    lbcs      Failed

* TEXT OVERLAY ON, AND FT_FOVR OFF.  Without FX_TXT+FX_OVR the bitmap
* covers the whole screen and every number this program prints goes to a
* text screen that is not being displayed.  With FT_FOVR SET the overlay
* paints solid over the graphics and the bitmap disappears instead.
* bmtest lost a hardware run to each of those in turn.
                    ldx       #FX_GRF+FX_BM+FX_TXT+FX_OVR
                    ldy       #0                  60 Hz, 320x240, TRANSPARENT overlay
                    lda       #BMPATH
                    ldb       #SS.MCR
                    os9       I$SetStt
                    lbcs      Failed

* The whole bitmap to PREVAL once, and the guard bytes behind it, so the
* first attempt is judged against known memory rather than against
* whatever the slab happened to hold.
                    lbsr      PreFill
                    lbcs      Failed

                    lbsr      LogOpen
                    lbsr      Explain
                    lbra      Loop

********************************************************************
* Explain - the screen and the log header.  Everything a reader needs in
*   order to know what a pass looks like before anything runs.
********************************************************************
Explain             leax      Ban2,pcr
                    lbsr      PutLine
                    lbsr      AddrLine
                    leax      Blank,pcr
                    lbsr      PutLine
                    leax      Exp1,pcr
                    lbsr      PutLine
                    leax      Exp2,pcr
                    lbsr      PutLine
                    leax      Exp3,pcr
                    lbsr      PutLine
                    leax      Exp4,pcr
                    lbsr      PutLine
                    leax      Exp5,pcr
                    lbsr      PutLine
                    leax      Exp6,pcr
                    lbsr      PutLine
                    leax      Blank,pcr
                    lbsr      PutLine
                    leax      Key1,pcr
                    lbsr      PutLine
                    leax      Key2,pcr
                    lbsr      PutLine
                    leax      Blank,pcr
                    lbsr      PutLine
                    lbsr      HeadLine
                    rts

********************************************************************
* AddrLine - where the bitmap actually is, in physical bytes, and how
*   wide the transfers are.  A pasted log has to say this: the whole
*   report turns on a 76,800-byte fill landing at one address.
********************************************************************
AddrLine            leax      AdrTx,pcr
                    lbsr      StartLine
* THE PHYSICAL ADDRESS, because that is the number the report quotes and
* the one the engine's own destination registers read back.  A block is
* $2000, so the slab's base is block << 13: bits 23:16 are block >> 3,
* bits 15:8 are (block & 7) << 5, and the bitmap's $1000 offset adds $10
* to the middle byte.  Block $E2 comes out $1C5000, which is exactly what
* the K2 has been reporting.
                    lda       slabblk,u
                    lsra
                    lsra
                    lsra
                    lbsr      AppHex
                    lda       slabblk,u
                    anda      #7
                    lsla
                    lsla
                    lsla
                    lsla
                    lsla
                    adda      #BMOFF/256
                    lbsr      AppHex
                    clra
                    lbsr      AppHex
                    leax      AdrTx2,pcr
                    lbsr      AppStr
                    leax      W8Tx,pcr
                    tst       wide,u
                    beq       adr1@
                    leax      W16Tx,pcr
adr1@               lbsr      AppStr
                    lbra      EndLine

********************************************************************
* HeadLine - the column header, built from the same COL* equs the rows
*   are, so the two cannot drift apart.
********************************************************************
HeadLine            leax      HdCase,pcr
                    lbsr      StartLine
                    lda       #COLNAME
                    lbsr      AppCol
                    leax      HdName,pcr
                    lbsr      AppStr
                    lda       #COLSTAT
                    lbsr      AppCol
                    leax      HdStat,pcr
                    lbsr      AppStr
                    lda       #COLARMS
                    lbsr      AppCol
                    leax      HdArms,pcr
                    lbsr      AppStr
                    lda       #COLOK
                    lbsr      AppCol
                    leax      HdOk,pcr
                    lbsr      AppStr
                    lda       #COLSHRT
                    lbsr      AppCol
                    leax      HdShrt,pcr
                    lbsr      AppStr
                    lda       #COLERR
                    lbsr      AppCol
                    leax      HdErr,pcr
                    lbsr      AppStr
                    lda       #COLHUNG
                    lbsr      AppCol
                    leax      HdHung,pcr
                    lbsr      AppStr
                    lbra      EndLine

********************************************************************
* The key loop
********************************************************************
Loop                leax      keybuf,u
                    ldy       #1
                    clra                          path 0 - stdin
                    os9       I$Read
                    lbcs      Quit                EOF or a signal: get out
                    lda       keybuf,u
* THE DIGITS AND THE TWO CONTROL KEYS ARE TESTED BEFORE THE CASE FOLD.
* "anda #$5F" is for letters and destroys everything else: '4' is $34 and
* $34 & $5F is $14, so a cmpa #'4 after it can never match.  That cost
* bmtest a hardware run - every letter key worked and only the digits did
* nothing at all.  Space is $20 and folds to $00; ESC is $1B and folds to
* $1B, which is harmless, but it is tested here with the rest for the
* same reason: the fold is not for them.
                    cmpa      #$20                SPACE - the whole sweep
                    lbeq      DoSweep
                    cmpa      #$1B                ESC
                    lbeq      Quit
                    cmpa      #'0
                    blo       kfold@
                    cmpa      #'9
                    bhi       kfold@
                    suba      #'0
                    bne       kone@
                    lda       #NCASES             '0' is case 10
kone@               sta       case,u
                    clr       sweep,u
                    lbsr      RunCase
                    bra       Loop
kfold@              anda      #$5F                letters fold to upper case
                    cmpa      #'Q
                    lbeq      Quit
                    cmpa      #'W
                    beq       DoWide
                    cmpa      #'P
                    beq       DoPhase
                    cmpa      #'L
                    lbeq      DoList
                    bra       Loop

* W - 8-bit or 16-bit transfers.  16-bit is a separate path through the
* engine and it halves the exposure to the window problem, so which one
* is in force belongs on the screen and in the log, not in the operator's
* memory.  Four unlabelled toggles cost this project a run once.
DoWide              lda       wide,u
                    coma
                    sta       wide,u
                    lbsr      AddrLine
                    bra       Loop

* P - the arming-phase sweep.  It needs a driver that can be told which
* raster line to arm on, and $FFD8-$FFDB is inside $FD00-$FFFF, which a
* program cannot reach at any price.  Saying so is better than leaving a
* key that appears to do nothing.
********************************************************************
* P - THE ARMING-PHASE SWEEP, which is the one measurement that turns a
* rate into a mechanism.
*
* A whole 8-bit fill needs 24.2 of the vertical-blanking window's 43
* lines, so it has to be armed by about line 19.  Armed at a free-running
* phase - which is what every other key here does - that shows up as
* "about 4.4% of attempts came up short", and a percentage is a weak
* thing to hand anyone.  This arms ONE transfer on each raster line in
* turn and prints what happened, so the answer reads "complete through
* line 18, short from line 19" and the arithmetic can be checked against
* it.
*
* It runs the CONTROL case's wait - arm, return, sleep - because the
* window is what is being measured here, not the wedge.
*
* THE LINE ASKED FOR AND THE LINE IT GOT ARE BOTH PRINTED.  An interrupt
* during the driver's spin costs several lines, so they differ often
* enough that reporting only the request would quietly corrupt the map.
********************************************************************
DoPhase             leax      PhHdr,pcr
                    lbsr      PutLine
                    leax      PhHdr2,pcr
                    lbsr      PutLine
                    leax      PhHdr3,pcr
                    lbsr      PutLine
* IT STARTS AT LINE 1, NOT 0.  Zero is the arming line's free-running
* value - the one every shipping caller passes - so it cannot also mean
* "line 0", and a sweep that began there reported "line 00 armed 237",
* which is true and useless.  Line 1 is one line away from the ideal and
* costs the measurement nothing.
                    lda       #1
                    sta       armline,u
ph1@                lbsr      PhOne
                    lbsr      KeyChk
                    cmpa      #2
                    beq       ph2@
                    lda       armline,u
                    inca
                    sta       armline,u
                    cmpa      #PHMAX
                    lbls      ph1@
ph2@                clr       armline,u
                    leax      PhFoot,pcr
                    lbsr      PutLine
                    lbra      Loop

********************************************************************
* PhOne - one transfer at armline, reported.
********************************************************************
PhOne               lda       #1                  the control case
                    lbsr      CaseEnt
                    lbsr      Attempt
                    leax      PhLn,pcr
                    lbsr      StartLine
                    lda       armline,u
                    lbsr      AppDec
                    leax      PhGot,pcr
                    lbsr      AppStr
                    lda       gotline,u
                    lbsr      AppDec
                    lda       #COLPHOU
                    lbsr      AppCol
                    lbsr      AppOut
                    lbra      EndLine

********************************************************************
* AppOut - the attempt's outcome in words, with the number that goes
*   with it.  A bare "SHORT" is half a measurement.
********************************************************************
AppOut              lda       outcome,u
                    bne       ao1@
                    leax      OutOk,pcr
                    lbra      AppStr
ao1@                cmpa      #O.SHORT
                    bne       ao2@
                    leax      OutShrt,pcr
                    lbsr      AppStr
                    ldd       stoprow,u
                    lbra      AppDc16
ao2@                cmpa      #O.OVER
                    bne       ao3@
                    leax      OutOver,pcr
                    lbra      AppStr
ao3@                cmpa      #O.ERR
                    bne       ao4@
                    leax      OutErr,pcr
                    lbsr      AppStr
                    lda       lasterr,u
                    lbra      AppDec
ao4@                leax      OutHung,pcr
                    lbra      AppStr

********************************************************************
* L - the ten cases and what a K2 has done with each of them.
*
* This is the key someone presses BEFORE they press SPACE, and it exists
* because four of the ten cases kill the machine.  Finding that out by
* running them is a poor way to be told.  The text comes from the case
* table itself (CE.EXP), so a case and its expectation cannot drift
* apart, and it goes to the log like everything else - a pasted log then
* explains its own table without the reader having this document.
********************************************************************
DoList              leax      LstHdr,pcr
                    lbsr      PutLine
                    lda       #1
                    sta       case,u
dl1@                lda       case,u
                    lbsr      CaseEnt
                    pshs      x
                    leax      Space2,pcr
                    lbsr      StartLine
                    lda       case,u
                    lbsr      AppDec
                    lda       #COLNAME
                    lbsr      AppCol
                    ldx       ,s
                    leax      CE.NAME,x
                    ldb       #CNAMEW
                    lbsr      AppFix
                    lda       #COLSTAT
                    lbsr      AppCol
                    ldx       ,s
                    lda       CE.STAT,x
                    lbsr      AppState
                    lda       #COLEXP
                    lbsr      AppCol
                    ldx       ,s
                    lda       CE.EXP,x
                    lbsr      AppExp
                    lbsr      EndLine
                    puls      x
                    lda       case,u
                    inca
                    sta       case,u
                    cmpa      #NCASES
                    lbls      dl1@
                    leax      LstFt1,pcr
                    lbsr      PutLine
                    leax      LstFt2,pcr
                    lbsr      PutLine
                    lbra      Loop

********************************************************************
* AppExp - A = a CE.EXP code; appends its fixed-width line from ExpTab.
********************************************************************
AppExp              pshs      d,x
                    ldb       #EXPW
                    mul
                    leax      ExpTab,pcr
                    leax      d,x
                    ldb       #EXPW
                    lbsr      AppFix
                    puls      d,x,pc

* SPACE - every case in order.  ESC during a case stops the sweep; S
* skips to the next one.
DoSweep             clr       abort,u
                    lda       #1
                    sta       case,u
                    lda       #1
                    sta       sweep,u
sw1@                lbsr      RunCase
                    tst       abort,u
                    bne       sw2@
                    lda       case,u
                    inca
                    sta       case,u
                    cmpa      #NCASES
                    bls       sw1@
sw2@                clr       sweep,u
                    leax      SwDone,pcr
                    lbsr      PutLine
                    lbra      Loop

Quit                lbra      Cleanup

********************************************************************
* RunCase - one case, start to finish.  case,u says which.
*
* THE "BEGIN" LINE IS PRINTED AND FLUSHED BEFORE ANYTHING IS ARMED, and
* that is the whole design of this program.  A wedge takes the machine
* with it: nothing after it can be printed, written or read.  So the
* evidence has to be on the screen and on the card BEFORE the attempt
* that kills the machine, which means one flushed line per case, up
* front, naming the case.
********************************************************************
RunCase             lda       case,u
                    lbsr      CaseEnt             X -> the entry
                    pshs      x
                    ldd       #0
                    std       arms,u
                    std       nok,u
                    std       nshort,u
                    std       nerr,u
                    std       nhung,u
                    std       badrow,u
                    clr       gotbad,u
                    clr       lasterr,u
                    ldx       ,s
                    ldd       CE.CAP,x
                    std       capleft,u
                    clr       progcnt,u
* WHETHER THIS CASE STEPS THE ARMING LINE, and it is every case whose CPU
* sits in a loop - 5, 6, 7 and 8, which is CE.CALL 0 with a wait mode
* above SYNC.
*
* WHY IT HAS TO.  Every attempt here is deterministic: a fixed-iteration
* loop in the driver, an F$Sleep that resynchronises to the tick, then a
* fixed amount of verify.  So the cycle is very nearly a whole number of
* frames, and every attempt arms at THE SAME RASTER PHASE - which means a
* case was sampling one phase three hundred times rather than three
* hundred phases once.  That is why these cases sometimes survived a whole
* run and sometimes died at once: the phase they locked to was decided by
* when the case happened to start.  Stepping the arming line decorrelates
* it AND records it, so a wedge becomes "armed at line 27" instead of
* "died at attempt 41".
                    clr       phstep,u
                    lda       CE.CALL,x
                    bne       rcps@               a caller-side case: leave it alone
                    lda       CE.FLAG,x
                    lsra
                    lsra
                    lsra
                    lsra
                    anda      #DmaWt.Mask
                    cmpa      #DmaWt.Reg
                    blo       rcps@               modes 0-3 park; they have no loop
                    inc       phstep,u
                    lda       #1
                    sta       armline,u
rcps@               equ       *
* A case we have not built yet says so and is not silently skipped: an
* empty row in this table would read as "it passed".
                    lda       CE.FLAG,x
                    cmpa      #NOTBLT
                    bne       rc1@
                    leax      Space2,pcr
                    lbsr      StartLine
                    lda       case,u
                    lbsr      AppDec
                    lda       #COLNAME
                    lbsr      AppCol
                    leax      NoMode7,pcr
                    lbsr      AppStr
                    lbsr      EndLine
                    puls      x,pc
rc1@                lbsr      BegLine
* The attempt loop.  Everything that reads the keyboard happens HERE,
* after the verify and before the next arm - never between arming a
* transfer and its completion, because reading the keyboard is bus
* activity in user state and cases 1, 9 and 10 exist to measure exactly
* that.  An instrument that contaminates its own measurement is worse
* than no instrument.
rc2@                ldx       ,s
                    lbsr      Attempt
                    lbsr      Tally
                    lbsr      PgTick
                    lbsr      PhTick
                    ldd       capleft,u
                    subd      #1
                    std       capleft,u
                    beq       rc3@
                    lbsr      KeyChk              0 = carry on, 1 = skip, 2 = abort
                    tsta
                    beq       rc2@
                    cmpa      #2
                    bne       rc3@
                    inc       abort,u
rc3@                clr       armline,u           free-running again
                    clr       phstep,u
                    puls      x
                    lbra      ResLine

********************************************************************
* PgTick - every PROGN attempts, put a line in the LOG ONLY saying how
*   far the case has got and what arming line is in force.
*
* THIS IS THE ONLY THING THAT SURVIVES A WEDGE.  The result line is
* printed when a case finishes, and a case that kills the machine never
* finishes - so without this the log says which case died and nothing
* about how far in, which is the whole measurement once you know the
* failure is a rate.  Log only, because nineteen extra lines a case would
* scroll the table off the screen.
********************************************************************
PgTick              inc       progcnt,u
                    lda       progcnt,u
                    cmpa      #PROGN
                    blo       pgx@
                    clr       progcnt,u
                    leax      PgTx,pcr
                    lbsr      StartLine
                    lda       case,u
                    lbsr      AppDec
                    leax      PgArm,pcr
                    lbsr      AppStr
                    ldd       arms,u
                    lbsr      AppDc16
                    tst       phstep,u
                    beq       pgend@
                    leax      PgLine,pcr
                    lbsr      AppStr
                    lda       armline,u
                    lbsr      AppDec
pgend@              lbsr      EndLog
pgx@                rts

********************************************************************
* PhTick - advance the arming line, if this case steps it.
*
* THE STEP HAS TO BE COPRIME WITH THE RANGE, and the first one was not.
* PHADV was 7 against a range of 1-63; 7 divides 63, so it walked
* 1, 8, 15 ... 57 and back to 1 - NINE lines, and it never tested the
* other fifty-four.  A phase that is never sampled cannot be found, and
* finding the lethal region is the entire point.  8 and 63 share no
* factor, so this visits every line in the range, about five times each
* over a 300-attempt case.
********************************************************************
PhTick              tst       phstep,u
                    beq       phx@
                    lda       armline,u
                    adda      #PHADV
                    cmpa      #PHMAX
                    bls       phset@
                    suba      #PHMAX
phset@              sta       armline,u
phx@                rts

********************************************************************
* BegLine - "case n <name> <state> running" and FLUSH IT.  X -> entry.
********************************************************************
BegLine             pshs      x
                    leax      BegTx,pcr
                    lbsr      StartLine
                    lda       case,u
                    lbsr      AppDec
                    lda       #COLNAME
                    lbsr      AppCol
                    ldx       ,s
                    leax      CE.NAME,x
                    ldb       #CNAMEW
                    lbsr      AppFix
                    lda       #COLSTAT
                    lbsr      AppCol
                    ldx       ,s
                    lda       CE.STAT,x
                    lbsr      AppState
                    lda       #COLARMS
                    lbsr      AppCol
                    leax      RunTx,pcr
                    lbsr      AppStr
                    lbsr      EndLine
                    puls      x,pc

********************************************************************
* ResLine - the case's row in the table.  X -> entry.
********************************************************************
ResLine             pshs      x
                    leax      Space2,pcr
                    lbsr      StartLine
                    lda       case,u
                    lbsr      AppDec
                    lda       #COLNAME
                    lbsr      AppCol
                    ldx       ,s
                    leax      CE.NAME,x
                    ldb       #CNAMEW
                    lbsr      AppFix
                    lda       #COLSTAT
                    lbsr      AppCol
                    ldx       ,s
                    lda       CE.STAT,x
                    lbsr      AppState
                    lda       #COLARMS
                    lbsr      AppCol
                    ldd       arms,u
                    lbsr      AppDc16
                    lda       #COLOK
                    lbsr      AppCol
                    ldd       nok,u
                    lbsr      AppDc16
                    lda       #COLSHRT
                    lbsr      AppCol
                    ldd       nshort,u
                    lbsr      AppDc16
                    lda       #COLERR
                    lbsr      AppCol
                    ldd       nerr,u
                    lbsr      AppDc16
                    lda       #COLHUNG
                    lbsr      AppCol
                    ldd       nhung,u
                    lbsr      AppDc16
* The notes, and they are the difference between a number and a
* measurement: WHICH row a short fill stopped on, and WHICH error code
* came back.  Without them "4" in the short column is unactionable.
                    tst       gotbad,u
                    beq       rl1@
                    lda       #COLNOTE
                    lbsr      AppCol
                    leax      RowTx,pcr
                    lbsr      AppStr
                    ldd       badrow,u
                    lbsr      AppDc16
rl1@                lda       lasterr,u
                    beq       rl2@
                    leax      ErrTx,pcr
                    lbsr      AppStr
                    lda       lasterr,u
                    lbsr      AppDec
rl2@                lbsr      EndLine
                    puls      x,pc

********************************************************************
* AppState - A = 0 user, 1 system.
********************************************************************
AppState            tsta
                    bne       ap1@
                    leax      UserTx,pcr
                    lbra      AppStr
ap1@                leax      SysTx,pcr
                    lbra      AppStr

********************************************************************
* Tally - fold the attempt's outcome into the counters.
********************************************************************
Tally               ldd       arms,u
                    addd      #1
                    std       arms,u
                    lda       outcome,u
                    bne       ta1@
                    ldd       nok,u
                    addd      #1
                    std       nok,u
                    rts
ta1@                cmpa      #O.SHORT
                    bne       ta3@
                    ldd       nshort,u
                    addd      #1
                    std       nshort,u
* The FIRST short row of the case is kept, not the last: it is the
* earliest the engine ever stopped, which is the number the window
* arithmetic predicts.
                    tst       gotbad,u
                    bne       ta2@
                    ldd       stoprow,u
                    std       badrow,u
                    inc       gotbad,u
ta2@                rts
ta3@                cmpa      #O.OVER
                    bne       ta4@
                    ldd       nshort,u            an overrun is a fill fault too
                    addd      #1
                    std       nshort,u
                    rts
ta4@                cmpa      #O.ERR
                    bne       ta5@
                    ldd       nerr,u
                    addd      #1
                    std       nerr,u
                    rts
ta5@                ldd       nhung,u
                    addd      #1
                    std       nhung,u
                    rts

********************************************************************
* Attempt - arm one whole-bitmap fill, wait the way this case waits,
*   read the status, and verify.  X -> the case entry.
*   Leaves outcome,u set; stoprow,u meaningful when it is O.SHORT.
********************************************************************
Attempt             pshs      x
* Alternate the fill value.  This is what makes a one-pass verify sound:
* a byte holding THIS value cannot be left over from last time.
                    lda       fillv,u
                    cmpa      #FILLA
                    bne       at1@
                    lda       #FILLB
                    bra       at2@
at1@                lda       #FILLA
at2@                sta       fillv,u
* R$X = flags : fill value.  Bit 0 of the high byte asks for 16-bit; the
* rest are the case's wait mode.  R$U = first row 0 : row count 0, which
* the driver reads as the whole bitmap.
                    lda       CE.FLAG,x
                    tst       wide,u
                    beq       at3@
                    ora       #1
at3@                ldb       fillv,u
                    tfr       d,x
* R$Y = the arming line : the bitmap #.  armline is 0 for everything but
* the P sweep, which is exactly what the ten cases want.
                    lda       armline,u
                    clrb                          bitmap 0
                    tfr       d,y
                    pshs      u
                    ldu       #0                  first row 0, all 240 rows
                    lda       #BMPATH
                    ldb       #SS.BmClear
                    os9       I$SetStt
                    puls      u                   PULS leaves CC and B alone
* R$A comes back as the line it ACTUALLY armed on.  STA touches N, Z and
* V but NOT the carry, so the call's own result still survives to the
* branch below.
                    sta       gotline,u
                    bcc       at4@
                    stb       lasterr,u
                    lda       #O.ERR
                    sta       outcome,u
                    puls      x,pc
* Armed.  How this case keeps the CPU busy while the engine takes the bus.
at4@                ldx       ,s
                    lda       CE.CALL,x
                    cmpa      #1
                    beq       at5@
                    cmpa      #2
                    beq       at6@
                    bra       at7@
at5@                lbsr      CallPoll
                    bra       at7@
at6@                lbsr      CallRam
* SLEEP, THEN READ THE STATUS - never the other way round, and nothing in
* between.  SS.BmClear arms and returns; F$Sleep gets the CPU into the
* kernel's idle CWAI, where it issues no valid bus cycles at all, and
* that is the one state that has never failed.
at7@                clr       clrtck,u
at8@                ldx       #2                  one 60 Hz tick
                    pshs      u
                    os9       F$Sleep
                    puls      u
                    pshs      u
                    lda       #BMPATH
                    ldb       #SS.BmClear
                    os9       I$GetStt
* KEEP THE CARRY AND THE ANSWERS BEFORE ANYTHING TOUCHES THEM.  A
* "tfr x,d" stood in this position in bmtest and overwrote B with X's low
* byte, so a failing call reported "err 187" - not an error code at all.
* That trap cost two hardware runs in one day.
                    pshs      cc,b,x              ,s=CC 1,s=B 2,s=X 4,s=data ptr
                    ldu       4,s
                    ldd       2,s                 R$X = 0 idle, 1 outstanding
                    std       cobusy,u
                    ldb       1,s
                    stb       tmperr,u
                    puls      cc,b,x
                    puls      u
                    bcc       at9@
* lasterr is only ever written on a real failure and is NEVER cleared
* here.  Clearing it on each good call would mean the row could only ever
* report an error from the very LAST attempt, and the one that matters is
* the first one that went wrong.
                    lda       tmperr,u
                    sta       lasterr,u
                    lda       #O.ERR
                    sta       outcome,u
                    puls      x,pc
at9@                ldd       cobusy,u
                    beq       ata@
                    inc       clrtck,u
                    lda       clrtck,u
                    cmpa      #CLRWAIT
                    blo       at8@
                    lda       #O.HUNG
                    sta       outcome,u
                    puls      x,pc
ata@                lbsr      Verify
                    puls      x,pc

********************************************************************
* CallPoll - case 9: the caller polls the status as hard as it can, in
*   USER STATE, through vtio and IOMan.  Every one of those calls is bus
*   activity, which is the point.  Bounded, because a wedged engine
*   never clears the bit.
********************************************************************
CallPoll            pshs      x,y
                    ldy       #POLLMAX
cp1@                pshs      u,y
                    lda       #BMPATH
                    ldb       #SS.BmClear
                    os9       I$GetStt
                    tfr       x,d
                    puls      u,y
                    bcs       cp2@
                    cmpd      #0
                    beq       cp2@
                    leay      -1,y
                    bne       cp1@
cp2@                puls      x,y,pc

********************************************************************
* CallRam - case 10: a plain RAM read loop in the caller's own address
*   space.  No system call, no MMU write, nothing but fetches and a data
*   read - the user-state counterpart of the driver's RAM loop.
********************************************************************
CallRam             pshs      x,y
                    leax      CallRam,pcr         our own code: readable, always mapped
                    ldy       #RAMSPIN
cr1@                lda       ,x
                    leay      -1,y
                    bne       cr1@
                    puls      x,y,pc

********************************************************************
* Verify - one byte per row against fillv, then the guard bytes.
*   Sets outcome,u and, when it is O.SHORT, stoprow,u.
*
* The walk carries a block number and an offset inside it rather than a
* flat address: the bitmap starts $1000 into the slab and runs 76,800
* bytes, so it spans ten blocks and a flat offset would not fit in 16
* bits.  A row is 320 bytes and a block is 8,192, so at most one block
* boundary falls in any one row - which is why the carry below is tested
* once and not in a loop.
********************************************************************
Verify              lda       slabblk,u
                    sta       curblk,u
                    lbsr      MapCur
                    lbcs      VerErr
                    ldd       #BMOFF
                    std       blkoff,u
                    ldd       #BMROWS
                    std       rowsleft,u
                    ldd       #0
                    std       stoprow,u
ve1@                ldd       blkoff,u
                    cmpd      #BLKSIZE
                    blo       ve2@
                    subd      #BLKSIZE
                    std       blkoff,u
                    lbsr      NextBlk
                    lbcs      VerErr
ve2@                ldd       winaddr,u
                    addd      blkoff,u
                    tfr       d,x
                    lda       ,x
                    cmpa      fillv,u
                    bne       ve4@                this row was never written
                    ldd       blkoff,u
                    addd      #BMCOLS
                    std       blkoff,u
                    ldd       stoprow,u
                    addd      #1
                    std       stoprow,u
                    ldd       rowsleft,u
                    subd      #1
                    std       rowsleft,u
                    bne       ve1@
* Every row's sample matched, so the fill reached the last row.  blkoff
* has already been stepped past it and now holds the offset of the guard
* bytes: BMOFF + 76,800 is $13C00, which is $1C00 inside the slab's tenth
* block, so it needs no further carry and the pointer is one add away.
                    ldd       winaddr,u
                    addd      blkoff,u
                    tfr       d,x
                    lbsr      Guard
                    tsta
                    bne       ve3@
                    lda       #O.OK
                    sta       outcome,u
                    lbra      VerEnd
ve3@                lda       #O.OVER
                    sta       outcome,u
                    lbra      VerEnd
ve4@                lda       #O.SHORT
                    sta       outcome,u
                    lbra      VerEnd

********************************************************************
* Guard - the NGUARD bytes past the end of the bitmap.  X points at them.
*   Returns A = 0 if they are all still SENTVAL, 1 if any was not, and
*   REWRITES THEM EITHER WAY so that the next attempt is judged on its
*   own rather than on this one's damage.
********************************************************************
Guard               pshs      b,x
                    clrb
                    ldy       #NGUARD
gu1@                lda       ,x
                    cmpa      #SENTVAL
                    beq       gu2@
                    ldb       #1
gu2@                lda       #SENTVAL
                    sta       ,x+
                    leay      -1,y
                    bne       gu1@
                    tfr       b,a
                    puls      b,x,pc

VerErr              lda       #O.ERR
                    sta       outcome,u
                    rts

VerEnd              lbsr      UnmapCur
                    rts

********************************************************************
* PreFill - the whole bitmap to PREVAL and the guard bytes to SENTVAL,
*   once, at start-up.  ~82 ms, paid a single time: after this every
*   attempt is protected by the alternating fill value instead.
********************************************************************
PreFill             lda       slabblk,u
                    sta       curblk,u
                    lbsr      MapCur
                    bcs       pfx@
                    ldd       #BMOFF
                    std       blkoff,u
                    ldd       #BMROWS
                    std       rowsleft,u
pf1@                ldd       #BMCOLS
                    std       runlen,u
* EVERY RUN IS BOUNDED BY WHICHEVER ENDS FIRST, THE ROW OR THE BLOCK.
* A row is 320 bytes and the window is one 8,192-byte block, so a row
* straddles a block boundary every twenty-sixth row - and the first
* version of this routine wrote all 320 regardless.  It put up to 319
* bytes past the end of the window, over whatever the kernel had mapped
* next, nine times a fill.  It landed on this program's own data area:
* the explanation came out as fragments of other lines, some of them the
* column header, and it took four MAME runs to stop blaming the terminal.
* bmtest's FillBm has always split its runs this way; this did not.
pf2@                ldd       #BLKSIZE
                    subd      blkoff,u            D = bytes left in this block
                    bne       pf3@
                    ldd       #0                  exactly on the boundary
                    std       blkoff,u
                    lbsr      NextBlk
                    bcs       pfx@
                    bra       pf2@
pf3@                cmpd      runlen,u
                    blo       pf4@
                    ldd       runlen,u            what is left of the row fits
pf4@                pshs      d                   ,s = this run's length
                    ldd       winaddr,u
                    addd      blkoff,u
                    tfr       d,x
                    ldy       ,s
                    lda       #PREVAL
pf5@                sta       ,x+
                    leay      -1,y
                    bne       pf5@
                    ldd       blkoff,u
                    addd      ,s
                    std       blkoff,u
                    ldd       runlen,u
                    subd      ,s++                PULS and ,s++ leave CC alone
                    std       runlen,u
                    bne       pf2@                the row crossed a boundary
                    ldd       rowsleft,u
                    subd      #1
                    std       rowsleft,u
                    bne       pf1@
* blkoff now holds BMOFF + 76,800 reduced by the nine crossings, which is
* $1C00 of the slab's tenth block - the guard bytes, one add away.
                    ldd       winaddr,u
                    addd      blkoff,u
                    tfr       d,x
                    lbsr      Guard
                    lbsr      UnmapCur
                    andcc     #^Carry
                    rts
pfx@                rts

********************************************************************
* KeyChk - is a key waiting?  Returns A = 0 carry on, 1 skip this case,
*   2 abort the sweep.  Called only between attempts.
********************************************************************
KeyChk              pshs      b,x,y
                    pshs      u
                    clra                          path 0 - stdin
                    ldb       #SS.Ready
                    os9       I$GetStt
                    puls      u                   PULS leaves the carry alone
                    bcs       kc0@                E$NotRdy: nothing waiting
                    leax      keybuf,u
                    ldy       #1
                    clra
                    os9       I$Read
                    bcs       kc0@
                    lda       keybuf,u
                    cmpa      #$1B                ESC
                    beq       kc2@
                    anda      #$5F
                    cmpa      #'S
                    beq       kc1@
kc0@                clra
                    puls      b,x,y,pc
kc1@                lda       #1
                    puls      b,x,y,pc
kc2@                lda       #2
                    puls      b,x,y,pc

********************************************************************
* CaseEnt - A = case 1-NCASES; returns X -> its table entry.
********************************************************************
CaseEnt             pshs      d
                    deca
                    ldb       #ENTSZ
                    mul
                    leax      CaseTab,pcr
                    leax      d,x
                    puls      d,pc

********************************************************************
* DefBm - SS.BmDef bitmap 0 = slabblk, offset BMOFF, mode 0.
********************************************************************
DefBm               clra
                    ldb       slabblk,u
                    tfr       d,x                 block
                    ldy       #0                  mode 0, bitmap 0
                    pshs      u
                    ldu       #BMOFF
                    lda       #BMPATH
                    ldb       #SS.BmDef
                    os9       I$SetStt
                    puls      u
                    rts

********************************************************************
* SetCfg - SS.BmCfg on bitmap 0.  A = enable, B = CLUT, $FF = leave.
********************************************************************
SetCfg              tfr       d,x                 X = enable:CLUT
                    ldy       #0                  bitmap 0
                    pshs      u
                    ldu       #$FFFF              mode fields untouched
                    lda       #BMPATH
                    ldb       #SS.BmCfg
                    os9       I$SetStt
                    puls      u
                    rts

********************************************************************
* SetClut - CLUT 0 entries 0-15 from ClutDat.
********************************************************************
SetClut             leax      ClutDat,pcr
                    ldy       #$0000              CLUT 0, first entry 0
                    pshs      u
                    ldu       #16
                    lda       #BMPATH
                    ldb       #SS.ClutWrite
                    os9       I$SetStt
                    puls      u
                    rts

********************************************************************
* MapCur / NextBlk / UnmapCur - a ONE-BLOCK window over the slab.  Any
*   more than one and the process runs out of its eight logical blocks;
*   joust learned that as E$MemFul 207.
*   PULS does not touch CC, so the carry from the os9 call survives it.
********************************************************************
MapCur              clra
                    ldb       curblk,u
                    tfr       d,x
                    pshs      u
                    ldb       #1
                    os9       F$MapBlk
                    tfr       u,d
                    puls      u
                    bcs       mcx@
                    std       winaddr,u
mcx@                rts

NextBlk             lbsr      UnmapCur
                    inc       curblk,u
                    lbsr      MapCur
                    rts

UnmapCur            ldx       winaddr,u
                    pshs      u
                    tfr       x,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u
                    rts

********************************************************************
* Cleanup - put the terminal back the way it was found.
********************************************************************
Cleanup             lbsr      LogClose
                    tst       defined,u
                    beq       cl1@
                    lda       #0                  enable off
                    ldb       #$FF
                    lbsr      SetCfg
                    ldy       #0
                    lda       #BMPATH
                    ldb       #SS.BmKill          program-owned: undefine only
                    os9       I$SetStt
cl1@                ldx       #0
                    ldy       #7                  layer 0 back to "nothing"
                    lda       #BMPATH
                    ldb       #SS.Layer
                    os9       I$SetStt
                    clra
                    ldb       mcrlo,u
                    tfr       d,x
                    clra
                    ldb       mcrhi,u
                    tfr       d,y
                    lda       #BMPATH
                    ldb       #SS.MCR
                    os9       I$SetStt
                    tst       gotslab,u
                    beq       cl2@
                    clra
                    ldb       slabblk,u
                    tfr       d,x
                    pshs      u
                    ldu       #NBLKS
                    lda       #BMPATH
                    ldb       #SS.GfxFree
                    os9       I$SetStt
                    puls      u
cl2@                leax      DoneTx,pcr
                    lbsr      PutLine
                    clrb
                    os9       F$Exit

Failed              lbsr      ShowErr
                    lbra      Cleanup

********************************************************************
* ShowErr - "dmafilltest: error nnn" from B
********************************************************************
ShowErr             pshs      b
                    leax      FailTx,pcr
                    lbsr      StartLine
                    lda       ,s
                    lbsr      AppDec
                    lbsr      EndLine
                    puls      b,pc

********************************************************************
* The log.  DMATEST.LOG in the execution directory.
*
* IT IS CLOSED AND REOPENED AFTER EVERY LINE, which is the one thing
* that matters about it.  A held-open path lets RBF buffer a sector, and
* a sector that is still in memory when the machine wedges is a sector
* nobody will ever read - and the case that wedged the machine is
* precisely the line we most need.  Ten to seventy lines a run: the cost
* of closing is nothing.
********************************************************************
* EVERY ONE OF THESE CALLS IS BRACKETED BY pshs u / puls u.  U is this
* program's data area for the whole run, and the file calls do not
* promise to leave it alone - trace.a, which this log is built from,
* reloaded U from scratch after every one rather than trust them.  A
* clobbered U here does not fail loudly: it writes the path number into
* whatever U happens to point at.
* IT APPENDS, AND THE EARLIER VERSION DELETED.  That was a trap of the
* worst kind on a card that starts this program at boot: the machine
* wedges, you power-cycle to go and read the log, and the boot wipes the
* log of the wedge before you can reach it.  Nothing about it looked
* wrong - the file was always there, always readable, and always missing
* the one run that mattered.
*
* Appending also makes the rate accumulate across the power cycles that a
* wedge forces on you, which is the only way to measure something that
* kills the machine it is being measured on.
LogOpen             pshs      u
                    leax      LogName,pcr
                    lda       #UPDAT.
                    os9       I$Open
                    puls      u                   PULS leaves the carry alone
                    bcs       locre@              no file yet: make one
                    sta       logpath,u
                    ldb       #SS.Size
                    pshs      u
                    os9       I$GetStt            X = size high, U = size low
                    tfr       u,d
                    puls      u                   D and X survive the PULS
                    bcs       lozer@
                    std       logposl,u
                    tfr       x,d
                    std       logposh,u
                    lbsr      LogSeek
                    rts
lozer@              ldd       #0
                    std       logposh,u
                    std       logposl,u
                    rts
locre@              pshs      u
                    leax      LogName,pcr
                    lda       #WRITE.
                    ldb       #PREAD.+PWRIT.+READ.+WRITE.
                    os9       I$Create
                    puls      u
                    bcs       lobad@              no log: the soak still runs
                    sta       logpath,u
                    ldd       #0
                    std       logposh,u
                    std       logposl,u
                    rts
* SAY WHY THERE IS NO LOG.  A silent failure here costs the whole run:
* the table would still appear on screen, the card would carry nothing,
* and the reason would be a guess.
lobad@              pshs      b
                    leax      LogBad,pcr
                    lbsr      StartLine
                    lda       ,s+
                    lbsr      AppDec
                    lbsr      EndLine
                    rts

LogClose            lda       logpath,u
                    cmpa      #$FF
                    beq       lcx@
                    pshs      u
                    os9       I$Close
                    puls      u
                    lda       #$FF
                    sta       logpath,u
lcx@                rts

* LogWrite - X = the bytes, Y = how many.  Writes, then closes and
* reopens at the position we have been counting, so the card is current
* before the next attempt is armed.
LogWrite            pshs      d,x,y
                    lda       logpath,u
                    cmpa      #$FF
                    beq       lwx@
                    pshs      u
                    os9       I$Write
                    puls      u
                    bcs       lwbad@
* PSHS lays D, X and Y down in that order from S upward, so the count
* this routine was handed is at 4,s and NOT at 2,s, which is X.
                    ldd       logposl,u
                    addd      4,s                 the count we were handed
                    std       logposl,u
                    ldd       logposh,u           LDD leaves the carry alone
                    adcb      #0
                    adca      #0
                    std       logposh,u
                    lbsr      LogFlush
lwx@                puls      d,x,y,pc
lwbad@              lda       #$FF                a broken log stops being used
                    sta       logpath,u
                    puls      d,x,y,pc

LogFlush            lda       logpath,u
                    cmpa      #$FF
                    beq       lfx@
                    pshs      u
                    os9       I$Close
                    leax      LogName,pcr
                    lda       #UPDAT.
                    os9       I$Open
                    puls      u
                    bcs       lfbad@
                    sta       logpath,u
                    lbsr      LogSeek
lfx@                rts
lfbad@              lda       #$FF
                    sta       logpath,u
                    rts

********************************************************************
* LogSeek - put the path at logposh:logposl.
*
* I$Seek takes the position in X:U, and U is this program's data area for
* the whole run - so everything is read out of it BEFORE the swap and the
* path number is picked up off the stack afterwards.
********************************************************************
* THE PATH IS PUSHED BEFORE THE POSITION IS LOADED, and that ordering is
* the whole routine.  The first version read the path into A and THEN did
* "ldd logposl,u", which overwrites A - so I$Seek was handed the
* position's high byte as its path number, the seek never took, and every
* line in the log was written at offset 0 on top of the last one.  The
* file stayed the size of its longest line and looked like several runs
* shredded together.
LogSeek             lda       logpath,u
                    pshs      a                   the path, BEFORE D is reused
                    ldx       logposh,u
                    ldd       logposl,u
                    pshs      u                   the data pointer
                    tfr       d,u
                    lda       2,s
                    os9       I$Seek
                    puls      u
                    puls      a
                    rts

********************************************************************
* The line builder.  Y is the line pointer throughout, as in bmtest.
********************************************************************
StartLine           leay      linebuf,u
                    bra       AppStr

AppStr              pshs      a
as1@                lda       ,x+
                    beq       as2@
                    sta       ,y+
                    bra       as1@
as2@                puls      a,pc

* AppFix - B characters from X, exactly, spaces and all.  The case names
* are fixed width because they are also a column.
AppFix              pshs      a,b,x
af1@                lda       ,x+
                    sta       ,y+
                    decb
                    bne       af1@
                    puls      a,b,x,pc

* AppCol - pad with spaces out to column A of the line.
AppCol              pshs      d,x
                    clrb
                    exg       a,b                 D = the target column
                    leax      linebuf,u
                    leax      d,x
ac1@                pshs      x
                    cmpy      ,s++
                    bhs       ac2@
                    lda       #$20
                    sta       ,y+
                    bra       ac1@
ac2@                puls      d,x,pc

AppHex              pshs      a
                    lsra
                    lsra
                    lsra
                    lsra
                    bsr       Nyb
                    sta       ,y+
                    lda       ,s
                    bsr       Nyb
                    sta       ,y+
                    puls      a,pc

Nyb                 anda      #$0F
                    adda      #'0
                    cmpa      #'9
                    bls       ny1@
                    adda      #7
ny1@                rts

AppDec              pshs      a,b
                    clrb
ad1@                cmpa      #100
                    blo       ad2@
                    suba      #100
                    incb
                    bra       ad1@
ad2@                tstb
                    beq       ad3@
                    pshs      a
                    tfr       b,a
                    adda      #'0
                    sta       ,y+
                    puls      a
ad3@                clrb
ad4@                cmpa      #10
                    blo       ad5@
                    suba      #10
                    incb
                    bra       ad4@
ad5@                pshs      a
                    tfr       b,a
                    adda      #'0
                    sta       ,y+
                    puls      a
                    adda      #'0
                    sta       ,y+
                    puls      a,b,pc

********************************************************************
* AppDc16 - D as decimal, 0-65535, no leading zeros.
********************************************************************
AppDc16             pshs      a,b,x
                    std       dcval,u
                    clr       dcsup,u
                    leax      DcTab,pcr
dc1@                ldd       ,x
                    beq       dc4@
                    clr       dcdig,u
dc2@                ldd       dcval,u
                    cmpd      ,x
                    blo       dc3@
                    subd      ,x
                    std       dcval,u
                    inc       dcdig,u
                    bra       dc2@
dc3@                lda       dcdig,u
                    bne       dc3b@
                    tst       dcsup,u
                    beq       dc3c@               a leading zero: drop it
dc3b@               adda      #'0
                    sta       ,y+
                    ldb       #1
                    stb       dcsup,u
dc3c@               leax      2,x
                    bra       dc1@
dc4@                ldb       dcval+1,u           the units, always printed
                    addb      #'0
                    stb       ,y+
                    puls      a,b,x,pc
DcTab               fdb       10000,1000,100,10,0

* EndLine terminates the line, prints it AND logs it.  One buffer, two
* destinations: the screen a reader is watching and the file the card
* carries away.  They cannot disagree.
EndLine             lda       #C$CR
                    sta       ,y
                    leay      1,y
                    leax      linebuf,u
                    pshs      x
                    tfr       y,d
                    subd      ,s++                D = bytes in the line
                    tfr       d,y
                    leax      linebuf,u
                    pshs      x,y
* THE SCREEN GETS I$WritLn AND THE LOG GETS I$Write, and the pair is not
* interchangeable.  I$Write puts bytes on the terminal RAW: it does not
* act on the CR, so the cursor never leaves the row and every line
* overwrites the one before it.  A whole run of this program once came out
* as a single line - the last one - with everything else written
* underneath it and lost.  I$WritLn does the line-end processing, which is
* what a terminal needs; a file wants the bytes exactly as built, which is
* what I$Write gives it.
                    lda       #1
                    pshs      u
                    os9       I$WritLn
                    puls      u
                    puls      x,y
                    lbsr      LogWrite
                    rts

********************************************************************
* PutLine - a CR-terminated string from X, to the screen AND to the log.
*
* IT COPIES THE STRING INTO linebuf AND LETS EndLine SEND IT, rather than
* handing the module's own constant data to I$Write.  Two earlier versions
* of this routine each lost a line of the screen and one MAME run apiece:
* I$WritLn with a count of 80 SILENTLY DROPPED every line longer than about
* forty characters, and I$Write pointed straight at the string printed
* nothing at all - while the 72-character column header, built in linebuf
* and sent by EndLine, came out perfectly in both runs.  That is the
* difference this routine now stops fighting: everything on this screen is
* built in one buffer and sent by one call.
*
* It logs as well as prints, because the explanation belongs in the file
* the developer pastes back: a table of numbers with no statement of what
* was measured is the instrument that cannot say what it measured.
********************************************************************
PutLine             pshs      d,x,y
                    lbsr      StartLine
                    lbsr      EndLine
                    puls      d,x,y,pc

********************************************************************
* EndLog - EndLine's other half: terminate the line and send it to the
*   LOG ONLY, leaving the screen alone.
********************************************************************
EndLog              lda       #C$CR
                    sta       ,y
                    leay      1,y
                    leax      linebuf,u
                    pshs      x
                    tfr       y,d
                    subd      ,s++                D = bytes in the line
                    tfr       d,y
                    leax      linebuf,u
                    lbsr      LogWrite
                    rts

********************************************************************
* The cases.  flags : caller : state : cap : name.
*
* The flags are SS.BmClear's R$X high byte: the wait mode is a NUMBER in
* bits 6:4 (DmaWt.* in wildbits.d), which is why each entry multiplies by
* 16.  It was a highest-bit-first bitmask until 2026-09-21, and case 8 -
* polling $FEC1 while a transfer is live, the worst row in the report's
* own table - is the reason it stopped being one: there was no bit left
* to ask for it with.
*
* Case 8 gets CAPSLOW because it is expected to wedge the K2 on the FIRST
* attempt; there is no point asking for three hundred.
********************************************************************
CaseTab
                    fcb       DmaWt.None*16,0,0,X.Never
                    fdb       CAPFAST
                    fcc       /arm, return, caller sleeps/
                    fcb       DmaWt.Cwai*16,0,1,X.Robust
                    fdb       CAPFAST
                    fcc       /CWAI in driver            /
                    fcb       DmaWt.CwChk*16,0,1,X.Best
                    fdb       CAPFAST
                    fcc       /CWAI + re-check in driver /
                    fcb       DmaWt.Sync*16,0,1,X.Robust
                    fdb       CAPFAST
                    fcc       /SYNC in driver            /
                    fcb       DmaWt.Reg*16,0,1,X.Many
                    fdb       CAPSLOW
                    fcc       /register loop in driver   /
                    fcb       DmaWt.Io*16,0,1,X.Few
                    fdb       CAPSLOW
                    fcc       /IO read loop at $FE20     /
                    fcb       DmaWt.Ram*16,0,1,X.Few
                    fdb       CAPSLOW
                    fcc       /RAM read loop in driver   /
                    fcb       DmaWt.Poll*16,0,1,X.First
                    fdb       CAPSLOW
                    fcc       /DMA status poll at $FEC1  /
                    fcb       DmaWt.None*16,1,0,X.New
                    fdb       CAPFAST
                    fcc       /caller polls GetStat      /
                    fcb       DmaWt.None*16,2,0,X.New
                    fdb       CAPFAST
                    fcc       /caller RAM loop, sleeps   /

********************************************************************
* ExpTab - what a K2 has done with each case, indexed by CE.EXP.  These
* are OBSERVATIONS from the runs behind docs/rc16-dma-report.md, not
* predictions, and `L` prints them so nobody has to press SPACE to find
* out that four of the ten kill the machine.
********************************************************************
ExpTab              fcc       /never failed in extended use/
                    fcc       /far more robust, still fails/
                    fcc       /the best - and still fails  /
                    fcc       /WEDGES, after many attempts /
                    fcc       /WEDGES, in three or four    /
                    fcc       /WEDGES on the FIRST attempt /
                    fcc       /never run - this one is new/
                    fcb       $20

********************************************************************
* CLUT 0.  Entry 0 is black; 1 and 2 are the two fill values and are
* DARK on purpose - the text overlay prints white across the whole
* screen and the readout matters more than the picture.  The screen
* alternating between them is the liveness signal.
********************************************************************
ClutDat             fcb       $00,$00,$00,$FF     0  black
                    fcb       $60,$20,$20,$FF     1  dark blue
                    fcb       $20,$60,$20,$FF     2  dark green
                    fcb       $00,$00,$FF,$FF     3  red
                    fcb       $00,$FF,$FF,$FF     4  yellow
                    fcb       $00,$FF,$00,$FF     5  green
                    fcb       $FF,$FF,$00,$FF     6  cyan
                    fcb       $FF,$00,$00,$FF     7  blue
                    fcb       $FF,$00,$FF,$FF     8  magenta
                    fcb       $40,$40,$40,$FF     9  dark grey
                    fcb       $A0,$A0,$A0,$FF     10 light grey
                    fcb       $FF,$FF,$FF,$FF     11 white
                    fcb       $FF,$FF,$FF,$FF     12 white
                    fcb       $FF,$FF,$FF,$FF     13 white
                    fcb       $FF,$FF,$FF,$FF     14 white
                    fcb       $FF,$FF,$FF,$FF     15 white

LogName             fcc       /DMATEST.LOG/
                    fcb       C$CR

Ban1                fcc       /rc16 VDMA fill soak - dmafilltest 1.0/
                    fcb       $00
Ban2                fcc       /Run this, then send back DMATEST.LOG from the card./
                    fcb       $00
Blank                                  fcb       $00
AdrTx               fcc       /bitmap 0: 320x240x8 at $/
                    fcb       $00
AdrTx2              fcc       /, 76800 bytes a fill, /
                    fcb       $00
W8Tx                fcc       /8-bit transfers/
                    fcb       $00
W16Tx               fcc       /16-bit transfers/
                    fcb       $00
Exp1                fcc       /Each case arms a 76,800-byte fill on the VDMA and keeps the CPU busy/
                    fcb       $00
Exp2                fcc       /a different way while the engine takes the bus, then reads the bitmap/
                    fcb       $00
Exp3                fcc       /back.  A few percent in the "short" column is the vertical-blanking/
                    fcb       $00
Exp4                fcc       /window running out and is EXPECTED in every case.  A WEDGE is the bug:/
                    fcb       $00
Exp5                fcc       /the screen stops, the keyboard dies, only a power cycle recovers it./
                    fcb       $00
Exp6                fcc       /Nothing is lost when that happens - the case is already in the log./
                    fcb       $00
Key1                fcc       /SPACE all ten cases   1-9 that case alone   0 case 10/
                    fcb       $00
Key2                fcc       /S skip   W 8 or 16-bit   L list the cases   ESC or Q quit/
                    fcb       $00
LstHdr              fcc       /The ten cases, and what a K2 has done with each of them:/
                    fcb       $00
LstFt1              fcc       /Four of them kill the machine on purpose.  That is the bug, not a fault/
                    fcb       $00
LstFt2              fcc       /in the test - and the log has the case that was running when it happens./
                    fcb       $00
HdCase              fcc       /  #/
                    fcb       $00
HdName              fcc       /wait strategy/
                    fcb       $00
HdStat              fcc       /state/
                    fcb       $00
HdArms              fcc       /arms/
                    fcb       $00
HdOk                fcc       /ok/
                    fcb       $00
HdShrt              fcc       /short/
                    fcb       $00
HdErr               fcc       /err/
                    fcb       $00
HdHung              fcc       /hung/
                    fcb       $00
BegTx               fcc       /  /
                    fcb       $00
Space2              fcc       /  /
                    fcb       $00
UserTx              fcc       /user/
                    fcb       $00
SysTx               fcc       /sys /
                    fcb       $00
RowTx               fcc       /row /
                    fcb       $00
ErrTx               fcc       / err /
                    fcb       $00
RunTx               fcc       /running/
                    fcb       $00
NoMode7             fcc       /not built yet - the driver has no wait mode for it/
                    fcb       $00
PhHdr               fcc       /Arming one fill on each raster line, 1 to 63.  A whole 8-bit fill needs/
                    fcb       $00
PhHdr2              fcc       /24.2 of the window's 43 lines, so it should go short partway down./
                    fcb       $00
PhHdr3              fcc       /Line 0 cannot be asked for - 0 means free-running - and 1 is next to it./
                    fcb       $00
PhFoot              fcc       /The line it got is what counts - an interrupt can cost the spin a few./
                    fcb       $00
PhLn                fcc       /  line /
                    fcb       $00
PgTx                fcc       /  .. case /
                    fcb       $00
PgArm               fcc       / reached arm /
                    fcb       $00
PgLine              fcc       /, arming line /
                    fcb       $00
PhGot               fcc       / armed /
                    fcb       $00
OutOk               fcc       /filled/
                    fcb       $00
OutShrt             fcc       /SHORT, stopped at row /
                    fcb       $00
OutOver             fcc       /OVERRAN the bitmap/
                    fcb       $00
OutErr              fcc       /error /
                    fcb       $00
OutHung             fcc       /HUNG - the status never cleared/
                    fcb       $00
SwDone              fcc       /Sweep finished.  DMATEST.LOG has the same table./
                    fcb       $00
DoneTx              fcc       /dmafilltest done./
                    fcb       $00
FailTx              fcc       /dmafilltest: error /
                    fcb       $00
LogBad              fcc       /NO LOG - DMATEST.LOG could not be created, error /
                    fcb       $00

                    emod
eom                 equ       *
                    end
