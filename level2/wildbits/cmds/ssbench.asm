********************************************************************
* ssbench - time the system calls Joust makes every frame
*
* Each test repeats one call in batches of 16 for four whole seconds of
* the clock (F$Time, read once per batch) and prints how many calls it
* managed per second.  The first test makes no call at all, so it
* measures the loop and the F$Time reads; subtract its time per batch
* from the others to get the cost of the call alone:
*
*   cycles per call = (MHz * 10^6 / rate - MHz * 10^6 / null rate)
*
* where rate is the printed calls/s, one sixteenth of a batch each.
*
* Run it on the live terminal and leave it there: a background terminal
* takes other paths (SS.LiveKeys and SS.Joy return zeros at once, and
* SS.SprPush does nothing at all).
* SS.LiveKeys empties the input buffer, so keys typed during the run are
* dropped.  The sprite lines push zero records - every sprite off - to
* records 0-79 and 127, so run it from the shell, not over a game.  The
* calls go to path 2, which is the terminal even when stdout is
* redirected to a file.  The last line, SS.SprPush with N=200, must end
* "error 187": it proves that errors come back, so a silent line above
* really did succeed.
*
* The sprite calls need a registered table (SS.SprReg): the driver keeps
* no copy of the records, so start-up registers one and the exit gives it
* back.  That registration is itself the "did the new driver load" check -
* it fails on any grfdrv256 that predates the sprite work.
*
* Start-up registers BOTH ways, which is also the only test either form
* has: first `recs`, in our own map, the automatic way (R$Y = 0); then the
* F$AllRAM block, zeroed and then UNMAPPED, by naming the block outright.
* The timing runs use that second one, so every sprite line below is also
* proof that the driver reads a registered table out of memory the program
* does not have mapped - which is the whole reason the manual form
* exists.  Either registration failing is fatal and says which.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*  1       2026/09/19  Claude Opus 5 / John Federico
* Written for the driver work (joust docs/driver-work.md, goal 1).

                    nam       ssbench
                    ttl       Per-call timing of the frame's system calls

                    ifp1
                    use       defsfile
                    endc

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

BATCH               equ       16        calls per F$Time read
SECS                equ       4         seconds per test (calls/s = batches * 16 / 4)
UNKCODE             equ       $FE       a spare SetStat code: the whole table is searched
*                               ($D1 was this until it became SS.SprPush, and
*                                the line then reported E$IllArg, not E$UnkSvc)
TPATH               equ       2         stderr: still the terminal when stdout is redirected,
*                                         and unlike stdin when run from a script

                    mod       eom,name,tylg,atrv,start,size

tbuf                rmb       6         F$Time: Y M D H M S
tsec0               rmb       1         the second the window opened on
count               rmb       4         batches in the window (32 bits, big-endian)
errcode             rmb       1         the first error a test returned, 0 = none
blk                 rmb       2         F$AllRAM's block, for the F$MapBlk test
tstptr              rmb       2         the current test's routine
linebuf             rmb       80        the line being built
padbuf              rmb       8         SS.Joy mode 6's four words
tmrec               rmb       12        a tile map record, ZEROED AT START (see below) so
*                             CTRL 0 keeps map 2 disabled and block 0 means
*                             address 0: timing SS.TmSet changes nothing a text
*                             terminal shows.  It must stay directly before recs
recs                rmb       1024      128 zero sprite records, registered with the driver
                    rmb       300       stack
size                equ       .

name                fcs       /ssbench/
                    fcb       edition

* The data area arrives with GARBAGE, not zeroes - which is why the
* records are cleared here.  tmrec sits immediately before them and is
* cleared by the same loop: a random offset in it is rejected by
* SS.TmSet's own range check (E$IllArg), which is how this was found.
start               leax      tmrec,u             zero tmrec and the records
                    ldd       #12+1024
clr@                clr       ,x+
                    subd      #1
                    bne       clr@

* Register them the automatic way: SS.SprPush sends a range of THIS
* table, so there is nothing to time without a registration.
                    leax      recs,u
                    pshs      u
                    ldy       #0                  R$Y = 0: our own map
                    ldu       #128
                    lda       #TPATH
                    ldb       #SS.SprReg
                    os9       I$SetStt
                    puls      u
                    lbcs      Fatal

                    ldb       #1                  one block for the F$MapBlk test
                    os9       F$AllRAM
                    lbcs      Fatal
                    std       blk,u

* Now the other form, on that block: map it, zero a table's worth, let the
* window go again, and register the BLOCK ITSELF.  Every sprite line below
* then reads a table out of memory this program has no window on, which is
* the whole reason the manual form exists.
                    pshs      u                   our data area
                    ldx       blk,u
                    ldb       #1
                    os9       F$MapBlk            U = where it landed
                    bcs       mfail@
                    tfr       u,x
                    ldd       #1024
mclr@               clr       ,x+
                    subd      #1
                    bne       mclr@
                    ldb       #1
                    os9       F$ClrBlk            and the window goes away again
                    puls      u
                    ldx       #0                  offset 0 within that block
                    ldb       blk+1,u             the block number
                    tfr       b,a
                    clrb                          1K at offset 0 cannot span
                    tfr       d,y                 R$Y <> 0: name the blocks outright
                    pshs      u
                    ldu       #128
                    lda       #TPATH
                    ldb       #SS.SprReg
                    os9       I$SetStt
                    puls      u
                    lbcs      Fatal
                    bra       reg@
mfail@              puls      u
                    lbra      Fatal
reg@                equ       *

                    leax      BanTxt,pcr
                    lbsr      PutLine

                    leay      TestTbl,pcr
tloop@              ldd       ,y                  offset of the routine, 0 ends
                    beq       done@
                    leax      d,y
                    stx       tstptr,u
                    pshs      y
                    lbsr      RunTest
                    puls      y
                    leay      4,y
                    bra       tloop@
done@               pshs      u                   the table goes back before we do
                    ldu       #0                  a count of 0 gives it up
                    lda       #TPATH
                    ldb       #SS.SprReg
                    os9       I$SetStt
                    puls      u
                    ldx       blk,u
                    ldb       #1
                    os9       F$DelRAM
                    clrb
                    os9       F$Exit

Fatal               pshs      b
                    leay      linebuf,u
                    leax      ErrTxt,pcr
                    lbsr      AppStr
                    lda       ,s
                    lbsr      AppDec
                    lbsr      EndLine
                    puls      b
                    os9       F$Exit

********************************************************************
* The tests.  Each entry: the routine, then its name, both as offsets
* from the entry itself.  A routine makes one call and returns its carry
* and B; U is the data area on entry and must be on exit.
********************************************************************
TestTbl             fdb       TNull-*,NNull-*
                    fdb       TID-*,NID-*
                    fdb       TReady-*,NReady-*
                    fdb       TKeys-*,NKeys-*
                    fdb       TJoy-*,NJoy-*
                    fdb       TJoy2-*,NJoy2-*
                    fdb       TJoy4-*,NJoy4-*
                    fdb       TJoy6-*,NJoy6-*
                    fdb       TUnk-*,NUnk-*
                    fdb       TSpr1-*,NSpr1-*
                    fdb       TSpr80-*,NSpr80-*
                    fdb       TTmSet-*,NTmSet-*
                    fdb       TTmScrl-*,NTmScrl-*
                    fdb       TMap-*,NMap-*
                    fdb       TBad-*,NBad-*
                    fdb       0

TNull               clrb
                    rts

TID                 os9       F$ID
                    rts

TReady              lda       #TPATH              IOMan, SCF, vtio, no grfdrv
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcc       ex@
                    cmpb      #E$NotRdy           no key waiting is the normal answer
                    bne       ex@
                    clrb
ex@                 rts

TKeys               pshs      u                   R$U comes back in U
                    lda       #TPATH
                    ldb       #SS.LiveKeys
                    os9       I$GetStt
                    puls      u,pc

TJoy                ldx       #JOY.Stick0         compatibility, one stick
JoyCall             lda       #TPATH
                    ldb       #SS.Joy
                    os9       I$GetStt
                    rts
TJoy2               ldx       #JOY.Sticks         both sticks as bits
                    bra       JoyCall
TJoy4               ldx       #JOY.SNES2          two SNES pads in registers
                    bra       JoyCall
TJoy6               ldx       #JOY.SNES4          four SNES pads into a buffer
                    leay      padbuf,u            not recs: they must stay zero
                    bra       JoyCall

TUnk                lda       #TPATH
                    ldb       #UNKCODE
                    os9       I$SetStt
                    bcc       ex@
                    cmpb      #E$UnkSvc           the expected answer
                    bne       ex@
                    clrb
ex@                 rts

TSpr1               pshs      u
                    ldy       #127
                    ldu       #1
                    bra       SprCall
TSpr80              pshs      u
                    ldy       #0
                    ldu       #80
SprCall             lda       #TPATH
                    ldb       #SS.SprPush
                    os9       I$SetStt
                    puls      u,pc

* The two tile calls, on tile map 2.  They are here to answer one
* question: how much of SS.TmSet's cost is the 12-byte caller buffer
* that SS.TmScrl does not have?  Both pay the same grfdrv round trip,
* so the difference between these two lines IS the buffer mapping plus
* eight bytes of copy - and it is the only honest way to say what
* implementing SS.TmScrl bought.
TTmSet              leax      tmrec,u             twelve zero bytes
                    ldy       #2                  tile map 2
                    lda       #TPATH
                    ldb       #SS.TmSet
                    os9       I$SetStt
                    rts

TTmScrl             pshs      u
                    ldx       #0                  X scroll
                    ldy       #2                  tile map 2
                    ldu       #0                  Y scroll
                    lda       #TPATH
                    ldb       #SS.TmScrl
                    os9       I$SetStt
                    puls      u,pc

* TBad is the check that errors come back: it must print error 187.
TBad                pshs      u
                    ldy       #0
                    ldu       #200
                    bra       SprCall
TMap                pshs      u
                    ldx       blk,u
                    ldb       #1
                    os9       F$MapBlk            U = where it landed
                    bcs       ex@
                    ldb       #1
                    os9       F$ClrBlk
ex@                 puls      u,pc

NNull               fcc       /no call (loop + F$Time)/
                    fcb       0
NID                 fcc       /F$ID                    /
                    fcb       0
NReady              fcc       /GetStt SS.Ready (vtio)  /
                    fcb       0
NKeys               fcc       /GetStt SS.LiveKeys      /
                    fcb       0
NJoy                fcc       /GetStt SS.Joy mode 0    /
                    fcb       0
NJoy2               fcc       /SS.Joy 2 (both sticks)  /
                    fcb       0
NJoy4               fcc       /SS.Joy 4 (2 SNES pads)  /
                    fcb       0
NJoy6               fcc       /SS.Joy 6 (4 SNES, buf)  /
                    fcb       0
NUnk                fcc       /SetStt unknown $FE      /
                    fcb       0
NSpr1               fcc       /SetStt SS.SprPush N=1   /
                    fcb       0
NSpr80              fcc       /SetStt SS.SprPush N=80  /
                    fcb       0
NTmSet              fcc       /SetStt SS.TmSet record  /
                    fcb       0
NTmScrl             fcc       /SetStt SS.TmScrl        /
                    fcb       0
NBad                fcc       /SprPush N=200 (err 187) /
                    fcb       0
NMap                fcc       /F$MapBlk + F$ClrBlk     /
                    fcb       0

********************************************************************
* RunTest - time the routine at tstptr and print its line.
* Entry: X = the routine, Y = its TestTbl entry
********************************************************************
RunTest             ldd       2,y                 the name
                    leax      d,y
                    pshs      x
                    clr       errcode,u
                    clra
                    clrb
                    std       count,u
                    std       count+2,u

* Open the window on a second boundary, so it is SECS whole seconds.
                    leax      tbuf,u
                    os9       F$Time
                    lda       tbuf+5,u
                    sta       tsec0,u
sync@               leax      tbuf,u
                    os9       F$Time
                    lda       tbuf+5,u
                    cmpa      tsec0,u
                    beq       sync@
                    sta       tsec0,u

batch@              ldb       #BATCH
                    pshs      b
call@               jsr       [tstptr,u]
                    bcc       ok@
                    tst       errcode,u           keep the first error
                    bne       ok@
                    stb       errcode,u
ok@                 dec       ,s
                    bne       call@
                    leas      1,s
                    inc       count+3,u           count the batch
                    bne       cnt@
                    inc       count+2,u
                    bne       cnt@
                    inc       count+1,u
                    bne       cnt@
                    inc       count,u
cnt@                leax      tbuf,u
                    os9       F$Time
                    lda       tbuf+5,u
                    suba      tsec0,u             seconds elapsed, modulo 60
                    bpl       pos@
                    adda      #60
pos@                cmpa      #SECS
                    blo       batch@

* calls/s = batches * BATCH / SECS = batches * 4
                    lsl       count+3,u
                    rol       count+2,u
                    rol       count+1,u
                    rol       count,u
                    lsl       count+3,u
                    rol       count+2,u
                    rol       count+1,u
                    rol       count,u

                    leay      linebuf,u
                    puls      x
                    lbsr      AppStr
                    lbsr      AppU32
                    leax      PerTxt,pcr
                    lbsr      AppStr
                    lda       errcode,u
                    beq       end@
                    leax      ErrTx2,pcr
                    lbsr      AppStr
                    lda       errcode,u
                    lbsr      AppDec
end@                lbra      EndLine

********************************************************************
* Line building.  Y is the write pointer into linebuf throughout.
*   AppStr  X = a $00-terminated string
*   AppU32  count as a right-aligned 8-digit decimal
*   AppDec  A as one to three digits
*   EndLine terminate with CR and write it
********************************************************************
AppStr              pshs      a
as@                 lda       ,x+
                    beq       ex@
                    sta       ,y+
                    bra       as@
ex@                 puls      a,pc

* AppU32 - count (it is consumed) in decimal, leading zeros as spaces
AppU32              leax      Pow10,pcr
                    clr       ,-s                 ,s = a digit has been printed
dig@                ldb       #'0-1
sub@                incb
                    lda       count+3,u           count -= 10^n
                    suba      3,x
                    sta       count+3,u
                    lda       count+2,u
                    sbca      2,x
                    sta       count+2,u
                    lda       count+1,u
                    sbca      1,x
                    sta       count+1,u
                    lda       count,u
                    sbca      ,x
                    sta       count,u
                    bcc       sub@
                    lda       count+3,u           went below zero: add one back
                    adda      3,x
                    sta       count+3,u
                    lda       count+2,u
                    adca      2,x
                    sta       count+2,u
                    lda       count+1,u
                    adca      1,x
                    sta       count+1,u
                    lda       count,u
                    adca      ,x
                    sta       count,u
                    cmpb      #'0
                    bne       put@
                    tst       ,s                  a digit already printed?
                    bne       put@
                    lda       4,x                 the last digit always prints
                    cmpa      #$FF
                    beq       put@
                    ldb       #C$SPAC             a leading zero
                    stb       ,y+
                    bra       nxt@
put@                stb       ,y+
                    inc       ,s
nxt@                leax      4,x
                    lda       ,x
                    cmpa      #$FF
                    bne       dig@
                    leas      1,s
                    rts

Pow10               fqb       10000000
                    fqb       1000000
                    fqb       100000
                    fqb       10000
                    fqb       1000
                    fqb       100
                    fqb       10
                    fqb       1
                    fcb       $FF

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
                    ldy       #80
                    lda       #1
                    os9       I$WritLn
                    puls      d,x,y,pc

BanTxt              fcc       /ssbench - calls per second, 4 s each; stay on this terminal/
                    fcb       C$CR
PerTxt              fcc       " calls per s"
                    fcb       0
ErrTxt              fcc       /ssbench: error /
                    fcb       0
ErrTx2              fcc       /  error /
                    fcb       0

                    emod
eom                 equ       *
                    end
