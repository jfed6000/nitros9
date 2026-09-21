********************************************************************
* bmtest - exercise the bitmap calls that nothing else reaches
*
* joust, jstview, drawtest, shellbg, shellbgoff, pixview, view and
* BASIC09's paint all go through SS.AScrn / SS.FScrn / SS.Palet, so the
* compatibility path is well covered.  NOTHING exercises the new calls.
* This does, and it is built around the four questions they raise:
*
*   1. SS.GfxAlloc  - can a program get graphics memory of its own?
*   2. SS.BmDef     - is the OFFSET honoured?  The bitmap is deliberately
*                     put $1000 into the slab, not at a block boundary.
*                     If the driver dropped the offset the picture would
*                     start 4,096 bytes - 12.8 rows - further on, so the
*                     WHITE BAR WOULD NOT BE AT THE TOP of the screen.
*                     That is the whole test: look at the top of it.
*   3. SS.BmCfg     - can a bitmap be hidden and brought back with its
*                     PIXELS INTACT?  Nothing could do that before.
*   4. the two ownership rules - SS.BmKill must NOT free memory the
*                     program owns, and SS.GfxFree must REFUSE a range
*                     overlapping a bitmap the driver allocated.
*
* Keys:  H hide bitmap 0            S show it again
*        B report both bitmaps (SS.BmBlk)
*        K SS.BmKill bitmap 0 - program-owned, so the slab must SURVIVE
*        G SS.GfxFree bitmap 1's blocks - must be REFUSED, error 214
*        Q quit and clean up
*
* Bitmap 0 is the program's, at an offset inside an SS.GfxAlloc slab.
* Bitmap 1 is the DRIVER's, from SS.BmAlloc, and exists only so that G
* has something to aim at; it is never given a layer, so it never shows.
*
* Every SS call that passes R$U saves and restores U around it, because U
* is this program's data area for the whole run.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*  1       2026/09/20  Claude Opus 5 / John Federico
* Written the same day as the calls it tests.  CONFIRMED ON K2 HARDWARE
* the same day: the white bar came out flush with the top of the screen,
* so SS.BmDef's offset is genuinely honoured; H and S hid and restored the
* picture; SS.BmBlk reported bitmap 1 as control $00, defined but not
* enabled; SS.GfxFree refused the driver's blocks; and the slab freed
* afterwards, so SS.BmKill had left it alone.

                    nam       bmtest
                    ttl       new bitmap call test

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
BARROWS             equ       8         rows per colour bar
BLKSIZE             equ       $2000
NLINES              equ       16        L: the fan from the centre
NFLOOD              equ       255       F: the batch that must run the FIFO short
FANCX               equ       160       the centre the fan radiates from
FANCY               equ       120
CLRVAL              equ       15        C: white, so a missed byte shows
CLRWAIT             equ       10        C: frames to wait before calling it dead

                    mod       eom,name,tylg,atrv,start,size

slabblk             rmb       1         first block of the SS.GfxAlloc slab
drvblk              rmb       1         first block of the driver's bitmap 1
gotslab             rmb       1         non-zero once the slab is ours
gotdrv              rmb       1         non-zero once bitmap 1 exists
defined             rmb       1         non-zero while bitmap 0 is defined
mcrlo               rmb       1         the display mode to put back
mcrhi               rmb       1
curblk              rmb       1         fill: the block mapped now
winaddr             rmb       2         fill: where that block is mapped
bmptr               rmb       2         fill: the write pointer
blkleft             rmb       2         fill: bytes left in this block
rowleft             rmb       2         fill: bytes left in this row
rowsleft            rmb       2         fill: rows left
runlen              rmb       2         fill: bytes in this run
barleft             rmb       1         fill: rows left in this bar
colour              rmb       1         fill: the colour being laid down
hires               rmb       1         non-zero = bitmap 0 is in 640x240 4bpp
clrtck              rmb       1         C: frames waited for the fill to finish
lnleft              rmb       1         L/F: records still to build
lndrawn             rmb       2         L/F: records the driver says it drew
lnbuf               rmb       NFLOOD*8  the line records, 8 bytes each
keybuf              rmb       1
linebuf             rmb       80
                    rmb       300       stack
size                equ       .

name                fcs       /bmtest/
                    fcb       edition

********************************************************************
* start
********************************************************************
start               clr       gotslab,u
                    clr       gotdrv,u
                    clr       defined,u
                    clr       hires,u

                    leax      BanTxt,pcr
                    lbsr      PutLine

* Remember the display mode, as joust does, so Q can put it back.
                    lda       #BMPATH
                    ldb       #SS.DScrn
                    os9       I$GetStt
                    bcs       NoMode
                    tfr       x,d
                    stb       mcrlo,u
                    tfr       y,d
                    stb       mcrhi,u
                    bra       Step1
NoMode              lda       #FX_TXT
                    sta       mcrlo,u
                    lda       #FT_OMIT
                    sta       mcrhi,u

********************************************************************
* 1 - SS.GfxAlloc: blocks the PROGRAM owns.
********************************************************************
Step1               ldx       #NBLKS
                    lda       #BMPATH
                    ldb       #SS.GfxAlloc
                    os9       I$SetStt
                    lbcs      Failed
                    tfr       x,d
                    stb       slabblk,u
                    inc       gotslab,u
                    leax      SlabTxt,pcr
                    lbsr      StartLine
                    lda       slabblk,u
                    lbsr      AppHex
                    leax      SlabTx2,pcr
                    lbsr      AppStr
                    lda       #NBLKS
                    lbsr      AppDec
                    lbsr      EndLine

********************************************************************
* 2 - SS.BmAlloc bitmap 1, purely so that G has a driver-owned range to
*     aim at.  It never goes on a layer, so it is never seen.
********************************************************************
                    ldy       #1
                    ldx       #0                  screen type: accepted, ignored
                    lda       #BMPATH
                    ldb       #SS.BmAlloc
                    os9       I$SetStt
                    lbcs      Failed
                    tfr       x,d
                    stb       drvblk,u
                    inc       gotdrv,u
                    leax      DrvTxt,pcr
                    lbsr      StartLine
                    lda       drvblk,u
                    lbsr      AppHex
                    lbsr      EndLine

********************************************************************
* 3 - SS.BmDef bitmap 0 at a NON-ZERO OFFSET inside our own slab.
********************************************************************
                    lbsr      DefBm
                    lbcs      Failed
                    inc       defined,u

********************************************************************
* 4 - draw the bars, 5 - the CLUT, 6 - enable, 7 - layer, 8 - mode.
********************************************************************
                    lbsr      FillBm
                    lbcs      Failed
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

                    ldx       #FX_GRF+FX_BM
                    ldy       #0                  60 Hz, 320x240
                    lda       #BMPATH
                    ldb       #SS.MCR
                    os9       I$SetStt
                    lbcs      Failed

                    leax      RdyTxt,pcr
                    lbsr      PutLine
                    leax      KeyTxt,pcr
                    lbsr      PutLine

********************************************************************
* The key loop
********************************************************************
Loop                leax      keybuf,u
                    ldy       #1
                    clra                          path 0 - stdin
                    os9       I$Read
                    lbcs      Quit                EOF or a signal: get out
                    lda       keybuf,u
* The DIGITS are tested BEFORE the case fold, because the fold is for
* letters only and destroys them: '4' is $34 and $34 & $5F is $14, so a
* cmpa #'4 after it can never match.  That cost one hardware run - every
* letter key worked and only 4 and 8 did nothing at all.
                    cmpa      #'4
                    lbeq      DoHi
                    cmpa      #'8
                    lbeq      DoLo
                    anda      #$5F                letters fold to upper case
                    cmpa      #'Q
                    lbeq      Quit
                    cmpa      #'H
                    beq       DoHide
                    cmpa      #'S
                    beq       DoShow
                    cmpa      #'B
                    beq       DoBlk
                    cmpa      #'K
                    beq       DoKill
                    cmpa      #'G
                    lbeq      DoGuard
                    cmpa      #'R
                    lbeq      DoRedraw
                    cmpa      #'C
                    lbeq      DoClear
                    cmpa      #'L
                    lbeq      DoLines
                    cmpa      #'F
                    lbeq      DoFlood
                    lbra      Loop

* H - hide it.  Enable off; CLUT, HIRES4 and GROUP all left alone, and
* the pixels are untouched, so S must bring back exactly this picture.
DoHide              lda       #0
                    ldb       #$FF                leave the CLUT alone
                    lbsr      SetCfg
                    leax      HidTxt,pcr
                    bcc       hok@
                    lbsr      ShowErr
                    lbra      Loop
hok@                lbsr      PutLine
                    lbra      Loop

DoShow              lda       #1
                    ldb       #$FF
                    lbsr      SetCfg
                    leax      ShwTxt,pcr
                    bcc       sok@
                    lbsr      ShowErr
                    lbra      Loop
sok@                lbsr      PutLine
                    lbra      Loop

* B - what does the driver think it has?
DoBlk               clra
                    lbsr      RepBm
                    lda       #1
                    lbsr      RepBm
                    lbra      Loop

* K - SS.BmKill on the PROGRAM-owned bitmap.  It must undefine it and
* leave the slab alone, so the SS.GfxFree at the end must still succeed.
DoKill              ldy       #0
                    lda       #BMPATH
                    ldb       #SS.BmKill
                    os9       I$SetStt
                    bcc       kok@
                    lbsr      ShowErr
                    lbra      Loop
kok@                clr       defined,u
                    leax      KilTxt,pcr
                    lbsr      PutLine
                    lbra      Loop

Quit                lbra      Cleanup

* 4 and 8 - the 640x240 4bpp mode, on and off, WITHOUT touching the
* pixels.  One byte becomes two dots, high nibble on the left, and nibble
* 0 is transparent per dot - so the 8bpp bars, whose bytes are 1 to 15,
* reappear as half-width stripes of colour alternating with transparent.
* That is the whole demonstration.  R then redraws them solid.
*
* The mode costs no memory: the stride is a hard-wired 320 bytes and the
* line counter is halved, so 640x240 is the same 76,800 bytes as 320x240.
* Nothing is reallocated here, and nothing needs to be.
*
* Palette GROUP stays 0, which is why this CLUT needs no changing: the
* colour is entry (CLUT mod 4)*256 + GROUP*16 + nibble, so with GROUP 0
* nibble n is simply entry n - the same sixteen entries the bars use.
DoHi                lda       #1
                    sta       hires,u
                    lbsr      SetMode
                    leax      HiTxt,pcr
                    bra       ModeRep
DoLo                clr       hires,u
                    clra
                    lbsr      SetMode
                    leax      LoTxt,pcr
ModeRep             bcc       mrok@
                    lbsr      ShowErr
                    lbra      Loop
mrok@               lbsr      PutLine
                    lbra      Loop

* R - lay the bars down again to suit whichever mode is set now.
DoRedraw            lbsr      FillBm
                    bcs       rerr@
                    leax      RedrTxt,pcr
                    lbsr      PutLine
                    lbra      Loop
rerr@               lbsr      ShowErr
                    lbra      Loop

********************************************************************
* G - the ownership guard.  Ask SS.GfxFree to free bitmap 1's blocks,
* which the DRIVER allocated.  It must refuse with E$IllArg and free
* nothing; anything else is a failure, and a silent success here would
* mean a double free the moment the terminal closed.
********************************************************************
DoGuard             tst       gotdrv,u
                    lbeq      Loop
                    clra
                    ldb       drvblk,u
                    tfr       d,x                 X = bitmap 1's first block
                    pshs      u
                    ldu       #10                 the ten it was given
                    lda       #BMPATH
                    ldb       #SS.GfxFree
                    os9       I$SetStt
                    puls      u
                    bcc       gbad@               it let us: that is the bug
                    cmpb      #E$IllArg
                    bne       gwrong@
                    leax      GOkTxt,pcr
                    lbsr      PutLine
                    lbra      Loop
gwrong@             leax      GWrTxt,pcr
                    lbsr      StartLine
                    tfr       b,a
                    lbsr      AppDec
                    lbsr      EndLine
                    lbra      Loop
gbad@               leax      GBadTxt,pcr
                    lbsr      PutLine
                    lbra      Loop

********************************************************************
* Cleanup.  Order matters, and it is the lifetime rule: switch the
* bitmap off BEFORE the memory it points at goes away.
********************************************************************
Cleanup             tst       defined,u
                    beq       cl1@
                    lda       #0                  enable off
                    ldb       #$FF
                    lbsr      SetCfg
                    ldy       #0
                    lda       #BMPATH
                    ldb       #SS.BmKill          program-owned: undefine only
                    os9       I$SetStt
cl1@                tst       gotdrv,u
                    beq       cl2@
                    ldy       #1
                    lda       #BMPATH
                    ldb       #SS.BmKill          driver-owned: this one frees
                    os9       I$SetStt
* Put layer 0 back to "nothing" - source 7 - which is what a terminal
* now starts with, rather than leaving it pointing at a dead bitmap.
cl2@                ldx       #0
                    ldy       #7
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
* The slab last, and it must succeed: K may have killed bitmap 0, but
* SS.BmKill must not have freed memory the program owns.
                    tst       gotslab,u
                    beq       cl3@
                    clra
                    ldb       slabblk,u
                    tfr       d,x
                    pshs      u
                    ldu       #NBLKS
                    lda       #BMPATH
                    ldb       #SS.GfxFree
                    os9       I$SetStt
                    puls      u
                    bcc       cl3@
                    leax      FreeTxt,pcr
                    lbsr      StartLine
                    tfr       b,a
                    lbsr      AppDec
                    lbsr      EndLine
                    bra       cl4@
cl3@                leax      DoneTxt,pcr
                    lbsr      PutLine
cl4@                clrb
                    os9       F$Exit

Failed              lbsr      ShowErr
                    lbra      Cleanup

********************************************************************
* DefBm - SS.BmDef bitmap 0 = slabblk, offset BMOFF, mode 0.
********************************************************************
DefBm               clra
                    ldb       slabblk,u
                    tfr       d,x                 block
                    ldy       #0                  mode 0, bitmap 0
                    pshs      u
                    ldu       #BMOFF              the offset that is the point
                    lda       #BMPATH
                    ldb       #SS.BmDef
                    os9       I$SetStt
                    puls      u
                    rts

********************************************************************
* SetCfg - SS.BmCfg on bitmap 0.  A = enable, B = CLUT, each 0-n or $FF
*   to leave alone.  HIRES4 and GROUP are always left alone.
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
* SetMode - SS.BmCfg on bitmap 0, the MODE fields only.  A = HIRES4
*   (0 or 1); palette GROUP is always 0.  Enable and CLUT are left alone,
*   which is the $FF convention doing exactly what it is for.
********************************************************************
SetMode             clrb                          GROUP 0
                    pshs      u
                    tfr       d,u                 R$U = HIRES4:GROUP
                    ldx       #$FFFF              enable and CLUT untouched
                    ldy       #0                  bitmap 0
                    lda       #BMPATH
                    ldb       #SS.BmCfg
                    os9       I$SetStt
                    puls      u
                    rts

********************************************************************
* RepBm - SS.BmBlk for bitmap A, reported.
********************************************************************
* THE CALL COMES FIRST.  StartLine puts the line pointer in Y, which is
* also where R$Y goes, so the GetStat has to be done and its answers put
* somewhere safe before any of the line is built.
RepBm               pshs      a                   ,s = bitmap #
                    tfr       a,b
                    clra                          R$Y = the bitmap #, not #*256
                    tfr       d,y
                    lda       #BMPATH
                    ldb       #SS.BmBlk
                    os9       I$GetStt            X = first block, A = control
                    bcc       rok@
                    leax      BmTxt,pcr
                    lbsr      StartLine
                    lda       ,s
                    lbsr      AppDec
                    leax      BmErr,pcr
                    lbsr      AppStr
                    lbsr      EndLine
                    puls      a,pc
rok@                pshs      a                   ,s = control, 1,s = bitmap #
                    tfr       x,d
                    pshs      b                   ,s = block, 1,s = ctrl, 2,s = bm #
                    leax      BmTxt,pcr
                    lbsr      StartLine
                    lda       2,s
                    lbsr      AppDec
                    leax      BmTx2,pcr
                    lbsr      AppStr
                    lda       ,s
                    lbsr      AppHex              the first block
                    leax      BmTx3,pcr
                    lbsr      AppStr
                    lda       1,s
                    lbsr      AppHex              the control byte
                    lbsr      EndLine
                    leas      2,s                 drop the block and the control
                    puls      a,pc

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
* FillBm - horizontal colour bars over the whole bitmap, starting at
*   block slabblk offset BMOFF and running BMROWS x BMCOLS bytes.  The
*   first bar is white so the top of the picture is unmistakable: if the
*   offset were ignored the white would start 12.8 rows down.
*
*   Runs are bounded by whichever ends first, the row or the block, so a
*   row crossing a block boundary is written as two runs.
********************************************************************
FillBm              lda       slabblk,u
                    sta       curblk,u
                    lbsr      MapCur
                    lbcs      fex@
                    ldd       winaddr,u
                    addd      #BMOFF
                    std       bmptr,u
                    ldd       #BLKSIZE-BMOFF
                    std       blkleft,u
                    ldd       #BMROWS
                    std       rowsleft,u
                    lda       #15                 the white top bar
                    sta       colour,u
                    lda       #BARROWS
                    sta       barleft,u
frow@               ldd       #BMCOLS
                    std       rowleft,u
frun@               ldd       rowleft,u           run = min(rowleft, blkleft)
                    cmpd      blkleft,u
                    blo       fgot@
                    ldd       blkleft,u
fgot@               std       runlen,u
                    ldx       bmptr,u
                    tfr       d,y                 Y = the run length
                    lda       colour,u
* In 640x240 one byte is TWO dots, so a solid bar wants the colour in
* both nibbles.  Written as the plain colour it would come out as the
* left dot transparent and the right dot coloured - which is exactly what
* pressing 4 without redrawing shows, and is the proof of the split.
                    tst       hires,u
                    beq       fput@
                    pshs      a
                    lsla
                    lsla
                    lsla
                    lsla
                    ora       ,s+
fput@               sta       ,x+
                    leay      -1,y
                    bne       fput@
                    stx       bmptr,u
                    ldd       rowleft,u
                    subd      runlen,u
                    std       rowleft,u
                    ldd       blkleft,u
                    subd      runlen,u
                    std       blkleft,u
                    bne       frchk@              this block still has room
                    lbsr      NextBlk
                    bcs       fex@
frchk@              ldd       rowleft,u
                    bne       frun@               the row runs into the next block
                    dec       barleft,u
                    bne       fnxt@
                    lda       #BARROWS
                    sta       barleft,u
                    inc       colour,u
                    lda       colour,u
                    cmpa      #15
                    blo       fnxt@
                    lda       #1
                    sta       colour,u
fnxt@               ldd       rowsleft,u
                    subd      #1
                    std       rowsleft,u
                    lbne      frow@
                    lbsr      UnmapCur
                    andcc     #^Carry
                    rts
fex@                rts

* NextBlk - release the mapped block and map the next one.
NextBlk             lbsr      UnmapCur
                    inc       curblk,u
                    lbsr      MapCur
                    bcs       nex@
                    ldd       winaddr,u
                    std       bmptr,u
                    ldd       #BLKSIZE
                    std       blkleft,u
                    andcc     #^Carry
nex@                rts

* MapCur / UnmapCur - one block at a time.  A one-block window keeps the
* process well inside its eight logical blocks; joust learned that the
* hard way with E$MemFul 207.
* PULS does not touch CC, so the carry from the os9 call survives it.
MapCur              clra
                    ldb       curblk,u
                    tfr       d,x
                    pshs      u
                    ldb       #1
                    os9       F$MapBlk
                    tfr       u,d
                    puls      u
                    bcs       mex@
                    std       winaddr,u
mex@                rts

UnmapCur            ldx       winaddr,u
                    pshs      u
                    tfr       x,u
                    ldb       #1
                    os9       F$ClrBlk
                    puls      u
                    rts

********************************************************************
* ShowErr - "bmtest: error nnn" from B
********************************************************************
ShowErr             pshs      b
                    leax      ErrTxt,pcr
                    lbsr      StartLine
                    lda       ,s
                    lbsr      AppDec
                    lbsr      EndLine
                    puls      b,pc


********************************************************************
* C - SS.BmClear: the DMA fill.
*
* Clears bitmap 0 to white, waits for the GetStat to say it finished,
* and then reads the LAST byte of the bitmap and the byte just past it.
* That pair is the off-by-one check, and it is the one thing about this
* call that could not be settled by reading the RTL: the engine computes
* Dst_Stop = Dst + Count - 1 and loops while ptr < Stop, and whether that
* writes Count or Count-1 bytes depends on a write strobe and a pointer
* increment that share a clock.  "last 0F, next XX" is right; "last XX"
* means the fill is one byte short.
*
* BMOFF + 76,800 - 1 = $13BFF, which is offset $1BFF of the TENTH block
* of the slab - so the byte after it, at $1C00, is still inside the slab
* and safe to read.
********************************************************************
DoClear             ldy       #0                  bitmap 0
                    ldx       #CLRVAL             high byte 0 = reserved
                    pshs      u
                    lda       #BMPATH
                    ldb       #SS.BmClear
                    os9       I$SetStt
                    puls      u
                    bcc       ClrArm
                    lbsr      ShowErr
                    lbra      Loop
ClrArm              clr       clrtck,u
ClrTick             ldx       #2                  one 60 Hz tick
                    pshs      u
                    os9       F$Sleep
                    puls      u
                    pshs      u
                    lda       #BMPATH
                    ldb       #SS.BmClear
                    os9       I$GetStt
                    tfr       x,d                 0 idle, 1 still outstanding
                    puls      u                   PULS does not touch CC
                    bcc       ClrPoll
                    lbsr      ShowErr
                    lbra      Loop
ClrPoll             tstb
                    beq       ClrDone
                    inc       clrtck,u
                    lda       clrtck,u
                    cmpa      #CLRWAIT
                    blo       ClrTick
* It never finished.  This is what a core whose DMA halt is not wired to
* Drive_RDY looks like, and NOTHING WAS WRITTEN: the engine parks in
* CPU_STOPPED_ST0, which sits in front of its first write state.  So the
* bitmap is untouched and a CPU clear would have been safe.
                    leax      ClrHung,pcr
                    lbsr      PutLine
                    lbra      Loop
ClrDone             leax      ClrTxt,pcr
                    lbsr      StartLine
                    lda       clrtck,u
                    lbsr      AppDec
                    leax      ClrTx2,pcr
                    lbsr      AppStr
                    lda       slabblk,u
                    adda      #9                  the tenth block of the slab
                    sta       curblk,u
                    pshs      y                   MapCur goes through F$MapBlk
                    lbsr      MapCur
                    puls      y
                    bcs       ClrNoMap
                    ldx       winaddr,u
                    lda       $1BFF,x             the bitmap's LAST byte
                    lbsr      AppHex
                    leax      ClrTx3,pcr
                    lbsr      AppStr
                    ldx       winaddr,u
                    lda       $1C00,x             the byte just past it
                    lbsr      AppHex
ClrNoMap            lbsr      EndLine
                    lbsr      PutLine
                    lbra      Loop

********************************************************************
* L - SS.BmLine: a fan of NLINES lines from the centre to points all the
* way round the border, each a different colour.  The border points are
* chosen to put at least one line in every one of Bresenham's eight
* octants, so a sign or a swap that is wrong shows as a missing or
* mirrored spoke rather than as nothing at all.
*
* It also proves the two things the layout rests on: colour is per
* record and needs no flush between lines, and the driver returns the
* number it actually drew.
********************************************************************
DoLines             ldb       #NLINES
                    lbsr      BldFan
                    ldb       #NLINES
                    lbsr      SendLn
                    leax      LnTxt,pcr
                    lbra      LnRep

********************************************************************
* F - the same call with NFLOOD full-width lines, which is far more than
* the 4,096-entry FIFO can hold: 255 lines of 320 pixels is 81,600, and
* the engine enqueues about four times faster than the video engine
* drains it.  THE DRIVER MUST COME UP SHORT rather than lose pixels, so
* a drawn count BELOW 255 with no error is the PASS here - and 255 would
* mean the pacing check never fired.
********************************************************************
DoFlood             lbsr      BldFlood
                    ldb       #NFLOOD
                    lbsr      SendLn
                    leax      FldTxt,pcr
LnRep               pshs      cc,b
                    lbsr      StartLine
                    ldb       lndrawn+1,u
                    tfr       b,a
                    lbsr      AppDec
                    leax      LnTx2,pcr
                    lbsr      AppStr
                    puls      cc,b
                    bcc       lrok@
                    leax      LnTx3,pcr
                    lbsr      AppStr
                    tfr       b,a
                    lbsr      AppDec
lrok@               lbsr      EndLine
                    lbsr      PutLine
                    lbra      Loop

********************************************************************
* SendLn - B records from lnbuf to bitmap 0.  Sets lndrawn from the
*   driver's answer, and returns the call's carry and B.
*   U is this program's data pointer AND the call's record count, so it
*   goes on the stack across the call.
********************************************************************
SendLn              clra
                    pshs      d                   ,s = the count, as a word
                    ldy       #0                  bitmap 0
                    leax      lnbuf,u
                    pshs      u                   the data pointer
                    ldu       2,s                 U = the record count
                    lda       #BMPATH
                    ldb       #SS.BmLine
                    os9       I$SetStt
                    tfr       u,y                 Y = the records actually drawn
                    puls      u                   neither TFR nor PULS touches CC
                    sty       lndrawn,u           nor does STY touch the carry
                    leas      2,s
                    rts

********************************************************************
* BldFan - B records: the centre to each of the FanPts border points,
*   cycling colours 1-15.  Colour 0 is transparent and would draw
*   nothing at all, which would look exactly like a broken engine.
********************************************************************
BldFan              stb       lnleft,u
                    leax      lnbuf,u
                    leay      FanPts,pcr
                    lda       #1
                    sta       colour,u
bf@                 ldd       #FANCX
                    std       ,x                  X0
                    lda       ,y+
                    sta       2,x                 X1 high
                    lda       ,y+
                    sta       3,x                 X1 low
                    lda       #FANCY
                    sta       4,x                 Y0
                    lda       ,y+
                    sta       5,x                 Y1
                    bsr       NextClr
                    sta       6,x
                    clr       7,x                 reserved, write 0
                    leax      8,x
                    dec       lnleft,u
                    bne       bf@
                    rts

********************************************************************
* BldFlood - NFLOOD full-width horizontal lines, wrapping down the
*   screen, so the batch is as expensive as the engine can be asked for.
********************************************************************
BldFlood            lda       #NFLOOD
                    sta       lnleft,u
                    leax      lnbuf,u
                    lda       #1
                    sta       colour,u
                    clrb                          B = the row
bl@                 clr       ,x                  X0 = 0
                    clr       1,x
                    lda       #BMCOLS/256
                    sta       2,x                 X1 = 319
                    lda       #(BMCOLS-1)&255
                    sta       3,x
                    stb       4,x                 Y0 = Y1 = this row
                    stb       5,x
                    pshs      b
                    bsr       NextClr
                    sta       6,x
                    clr       7,x
                    puls      b
                    incb
                    cmpb      #BMROWS
                    blo       blr@
                    clrb                          wrap: 255 lines, 240 rows
blr@                leax      8,x
                    dec       lnleft,u
                    bne       bl@
                    rts

********************************************************************
* NextClr - A = the next colour, 1-15, advancing the cycle.
********************************************************************
NextClr             lda       colour,u
                    pshs      a
                    inca
                    cmpa      #15
                    bls       nc@
                    lda       #1
nc@                 sta       colour,u
                    puls      a,pc

********************************************************************
* The fan's border points: X high, X low, Y.  Right round the frame, so
* every octant gets a line.
********************************************************************
FanPts              fcb       0,0,0               top left
                    fcb       0,80,0
                    fcb       0,160,0             top centre
                    fcb       0,240,0
                    fcb       1,63,0              top right (319,0)
                    fcb       1,63,60
                    fcb       1,63,120            right centre
                    fcb       1,63,180
                    fcb       1,63,239            bottom right
                    fcb       0,240,239
                    fcb       0,160,239           bottom centre
                    fcb       0,80,239
                    fcb       0,0,239             bottom left
                    fcb       0,0,180
                    fcb       0,0,120             left centre
                    fcb       0,0,60

********************************************************************
* Line building.  Y is the write pointer into linebuf throughout.
********************************************************************
StartLine           leay      linebuf,u
                    bra       AppStr

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
hdone@              tstb
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

PutLine             pshs      x,y,d
                    ldy       #80
                    lda       #1
                    os9       I$WritLn
                    puls      d,x,y,pc

********************************************************************
* CLUT 0 entries 0-15: blue, green, red, alpha.  Entry 0 is black and is
* transparent anyway; 15 is white, and it is the top bar.
********************************************************************
ClutDat             fcb       $00,$00,$00,$FF     0  black
                    fcb       $00,$00,$FF,$FF     1  red
                    fcb       $00,$80,$FF,$FF     2  orange
                    fcb       $00,$FF,$FF,$FF     3  yellow
                    fcb       $00,$FF,$80,$FF     4  yellow-green
                    fcb       $00,$FF,$00,$FF     5  green
                    fcb       $80,$FF,$00,$FF     6  spring
                    fcb       $FF,$FF,$00,$FF     7  cyan
                    fcb       $FF,$80,$00,$FF     8  azure
                    fcb       $FF,$00,$00,$FF     9  blue
                    fcb       $FF,$00,$80,$FF     10 violet
                    fcb       $FF,$00,$FF,$FF     11 magenta
                    fcb       $80,$00,$FF,$FF     12 rose
                    fcb       $40,$40,$40,$FF     13 dark grey
                    fcb       $A0,$A0,$A0,$FF     14 light grey
                    fcb       $FF,$FF,$FF,$FF     15 white

BanTxt              fcc       /bmtest - SS.GfxAlloc, SS.BmDef, SS.BmCfg, SS.BmKill, SS.GfxFree/
                    fcb       C$CR
SlabTxt             fcc       /SS.GfxAlloc gave block $/
                    fcb       $00
SlabTx2             fcc       / for /
                    fcb       $00
DrvTxt              fcc       /SS.BmAlloc gave bitmap 1 block $/
                    fcb       $00
RdyTxt              fcc       /Bitmap 0 is at offset $1000 in that slab.  THE TOP BAR MUST BE WHITE./
                    fcb       C$CR
KeyTxt              fcc       /H hide S show B blocks 4 hires 8 normal R redraw C clear L lines F flood K kill G guard Q quit/
                    fcb       C$CR
HiTxt               fcc       /  640x240 4bpp on - bars should halve into colour and clear stripes/
                    fcb       C$CR
LoTxt               fcc       /  back to 320x240 8bpp/
                    fcb       C$CR
RedrTxt             fcc       /  redrawn for the mode that is set now/
                    fcb       C$CR
HidTxt              fcc       /  hidden - the pixels are still there/
                    fcb       C$CR
ShwTxt              fcc       /  shown - it must look exactly as it did/
                    fcb       C$CR
KilTxt              fcc       /  bitmap 0 killed; the slab is the program's and must survive/
                    fcb       C$CR
BmTxt               fcc       /  bitmap /
                    fcb       $00
BmTx2               fcc       /: block $/
                    fcb       $00
BmTx3               fcc       /  control $/
                    fcb       $00
BmErr               fcc       /unreadable/
                    fcb       $00
GOkTxt              fcc       /  PASS - SS.GfxFree refused the driver's blocks/
                    fcb       C$CR
GWrTxt              fcc       /  refused, but with the wrong error: /
                    fcb       $00
GBadTxt             fcc       /  FAIL - SS.GfxFree freed a bitmap the driver owns/
                    fcb       C$CR
FreeTxt             fcc       /bmtest: the slab would not free, error /
                    fcb       $00
DoneTxt             fcc       /bmtest done - the slab was freed, so SS.BmKill left it alone/
                    fcb       C$CR
ClrTxt              fcc       /  SS.BmClear done after /
                    fcb       $00
ClrTx2              fcc       / frame(s); last byte $/
                    fcb       $00
ClrTx3              fcc       /, next $/
                    fcb       $00
ClrHung             fcc       /  SS.BmClear NEVER FINISHED - this core's DMA halt is not wired; nothing was written/
                    fcb       C$CR
LnTxt               fcc       /  SS.BmLine fan: drew /
                    fcb       $00
FldTxt              fcc       /  SS.BmLine flood: drew /
                    fcb       $00
LnTx2               fcc       / of them/
                    fcb       $00
LnTx3               fcc       /, then stopped with error /
                    fcb       $00
ErrTxt              fcc       /bmtest: error /
                    fcb       $00

                    emod
eom                 equ       *
                    end
