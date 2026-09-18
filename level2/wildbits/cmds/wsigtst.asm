********************************************************************
* wsigtst - exercise SS.WSig ($E1), the terminal visibility signal
*
* Registers for both transitions, then reports every signal it is sent.
* Switch away with Alt+Left/Alt+Right and back again: each switch should
* print one line, and the counts at the end should match the number of
* switches.  Output written while this terminal is a shadow goes to its
* switch buffer, so the BACKGROUND line is already on screen when you
* come back - that is the point of the test, not a glitch.
*
* Q quits.  CTRL+C and BREAK quit too (the intercept sees them).
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*  1       2026/09/18  Claude Opus 5 / John Federico
* Written with SS.WSig itself; never run on hardware at the time of
* writing.

                    nam       wsigtst
                    ttl       SS.WSig test

                    ifp1
                    use       defsfile
                    endc

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

* Both are above $80, where driver-defined signals belong: the system owns
* $00-$80, and $05 in particular is S$Alarm.  Anything >= S$Window ($04)
* also leaves a process blocked in a read alone rather than aborting it.
BGCODE              equ       S$WinBg             $81 - this terminal went background
FGCODE              equ       S$WinFg             $82 - it came forward

                    mod       eom,name,tylg,atrv,start,size

sigcode             rmb       1         the last code the intercept saw
sigcnt              rmb       1         non-zero = a signal is waiting to be reported
quitflg             rmb       1         set by Q, CTRL+C or BREAK
bgcnt               rmb       1         background transitions seen
fgcnt               rmb       1         foreground transitions seen
othcnt              rmb       1         signals that were neither
keybuf              rmb       1         one character for the Q test
linebuf             rmb       64        the line being built
                    rmb       300       stack
size                equ       .

name                fcs       /wsigtst/
                    fcb       edition

********************************************************************
* The intercept.  Entered with B = the signal code and U = our data
* area, asynchronously, so it does the least it can: record the code and
* count it.  Anything below S$Window is a real abort and ends the run.
********************************************************************
IcptRtn             stb       sigcode,u
                    inc       sigcnt,u
                    cmpb      #S$Window           abort or interrupt?
                    bhs       ex@                 no, an ordinary notification
                    inc       quitflg,u           yes, stop the loop
ex@                 rti

start               clr       sigcode,u
                    clr       sigcnt,u
                    clr       quitflg,u
                    clr       bgcnt,u
                    clr       fgcnt,u
                    clr       othcnt,u

                    leax      BanTxt,pcr
                    lbsr      PutLine

* The intercept has to be in place BEFORE the registration: an
* unintercepted S$Window would kill this process rather than report it.
                    leax      IcptRtn,pcr
                    os9       F$Icpt
                    lbcs      Fatal

                    clra                          path 0
                    ldb       #SS.WSig
                    ldx       #BGCODE*256+FGCODE
                    os9       I$SetStt
                    lbcs      Fatal

                    leax      RdyTxt,pcr
                    lbsr      PutLine

********************************************************************
* The loop.  A signal cuts the sleep short, so the report is prompt;
* the half second is only how often Q is noticed.
********************************************************************
Loop                ldx       #30
                    os9       F$Sleep

                    lda       sigcnt,u            anything to report?
                    beq       ckkey@
                    clr       sigcnt,u
                    lbsr      Report
ckkey@              lbsr      CkQuit
                    tst       quitflg,u
                    beq       Loop

* Deregister before leaving, so the driver is not left holding a process
* number that is about to become somebody else's.
                    clra                          path 0
                    ldb       #SS.WSig
                    ldx       #0                  both codes 0 = deregister
                    os9       I$SetStt

                    leay      linebuf,u
                    leax      SumTxt,pcr
                    lbsr      AppStr
                    lda       bgcnt,u
                    lbsr      AppDec
                    leax      SumTx2,pcr
                    lbsr      AppStr
                    lda       fgcnt,u
                    lbsr      AppDec
                    leax      SumTx3,pcr
                    lbsr      AppStr
                    lda       othcnt,u
                    lbsr      AppDec
                    lbsr      EndLine
                    clrb
                    os9       F$Exit

Fatal               pshs      b
                    leax      ErrTxt,pcr
                    lbsr      PutLine
                    puls      b
                    os9       F$Exit

********************************************************************
* Report - name the signal in sigcode and count it
********************************************************************
Report              leay      linebuf,u
                    lda       sigcode,u
                    cmpa      #BGCODE
                    bne       fg@
                    inc       bgcnt,u
                    leax      BgTxt,pcr
                    bra       out@
fg@                 cmpa      #FGCODE
                    bne       oth@
                    inc       fgcnt,u
                    leax      FgTxt,pcr
                    bra       out@
oth@                inc       othcnt,u
                    leax      OthTxt,pcr
out@                lbsr      AppStr
                    lda       sigcode,u
                    lbsr      AppHex
                    lbra      EndLine

********************************************************************
* CkQuit - read a key if one is waiting, without blocking
********************************************************************
CkQuit              clra                          path 0
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcs       ex@                 nothing there (E$NotRdy)
                    leax      keybuf,u
                    ldy       #1
                    clra
                    os9       I$Read
                    bcs       ex@
                    lda       keybuf,u
                    anda      #$5F                fold to upper case
                    cmpa      #'Q
                    bne       ex@
                    inc       quitflg,u
ex@                 clrb
                    rts

********************************************************************
* Line building.  Y is the write pointer into linebuf throughout.
*   AppStr  X = a $00-terminated string
*   AppHex  A as two hex digits
*   AppDec  A as one to three digits
*   EndLine terminate with CR and write it
********************************************************************
AppStr              pshs      a
as@                 lda       ,x+
                    beq       ex@
                    sta       ,y+
                    bra       as@
ex@                 puls      a,pc

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
                    bls       ex@
                    adda      #7
ex@                 rts

AppDec              pshs      a,b
                    clrb
hun@                cmpa      #100
                    blo       hdone@
                    suba      #100
                    incb
                    bra       hun@
hdone@              tstb                          leading hundreds only if non-zero
                    beq       ten@
                    pshs      a
                    tfr       b,a
                    adda      #'0
                    sta       ,y+
                    puls      a
ten@                clrb
tn@                 cmpa      #10
                    blo       one@
                    suba      #10
                    incb
                    bra       tn@
one@                pshs      a
                    tfr       b,a
                    adda      #'0
                    sta       ,y+
                    puls      a
                    adda      #'0
                    sta       ,y+
                    puls      a,b,pc

EndLine             lda       #C$CR
                    sta       ,y
                    leax      linebuf,u
* fall through

********************************************************************
* PutLine - write the CR-terminated string at X to standard output
********************************************************************
PutLine             pshs      x,y,d
                    ldy       #64
                    lda       #1
                    os9       I$WritLn
                    puls      d,x,y,pc

BanTxt              fcc       /wsigtst - SS.WSig $E1, the terminal visibility signal/
                    fcb       C$CR
RdyTxt              fcc       /Registered.  Alt+Left or Alt+Right to switch away and back.  Q quits./
                    fcb       C$CR
BgTxt               fcc       /  BACKGROUND  signal $/
                    fcb       $00
FgTxt               fcc       /  FOREGROUND  signal $/
                    fcb       $00
OthTxt              fcc       /  other       signal $/
                    fcb       $00
SumTxt              fcc       /background /
                    fcb       $00
SumTx2              fcc       /  foreground /
                    fcb       $00
SumTx3              fcc       /  other /
                    fcb       $00
ErrTxt              fcc       /wsigtst: the driver refused it - no SS.WSig in this vtio?/
                    fcb       C$CR

                    emod
eom                 equ       *
                    end
