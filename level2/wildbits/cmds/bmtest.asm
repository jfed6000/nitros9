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
* C's fill colour.  NOT white: white is also the pattern's top bar, and
* more importantly the overlaid text is white, so a white fill would hide
* the very readout the test exists to produce.  Blue is in none of the
* bars near the bottom, so "the screen went blue except the bottom bar"
* is unambiguous, and white-on-blue reads cleanly.
CLRVAL              equ       9         C: blue - see the note above
CLRWAIT             equ       10        C: frames to wait before calling it dead
* What FillBm writes into the four bytes past the end of the bitmap, so
* that C's "next" reading is a measurement and not whatever the slab
* happened to hold.  Any value but CLRVAL would do.
SENTVAL             equ       $AA

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
wide                rmb       1         non-zero = ask for 16-bit transfers
clrtck              rmb       1         C: frames waited for the fill to finish
scanrow             rmb       2         C: scan - the row being checked
scancol             rmb       2         C: scan - the column being checked
scanbad             rmb       1         C: scan - non-zero once the fill has begun
scansr              rmb       2         C: scan - the row the fill starts on
scansc              rmb       2         C: scan - the column it starts at
scaner              rmb       2         C: scan - the row the LAST filled byte is on
scanec              rmb       2         C: scan - its column
dcval               rmb       2         AppDc16: what is left to print
dcdig               rmb       1         AppDc16: the digit being built
dcsup               rmb       1         AppDc16: non-zero once a digit has gone out
clrrows             rmb       2         C: rows to fill, creeping up one per press
clrnow              rmb       2         C: what THIS press asked for
befbsy              rmb       1         C: the busy bit BEFORE this press armed
cofrow              rmb       1         ClrOne: the first row passed
corows              rmb       1         ClrOne: the row count passed
coerr               rmb       1         ClrOne: the GetStat's REAL error code
cobusy              rmb       2         ClrOne: 0 idle, 1 still outstanding
codsth              rmb       1         ClrOne: the engine's dst, high byte
codstl              rmb       2         ClrOne: ... and its mid and low
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
* C starts at the TOP OF THE RED BOTTOM BAR and adds one row per press,
* so the first fill is known to be well inside one vertical-blanking
* window and the count creeps up to the first size that does not fit.
                    ldd       #BMROWS-BARROWS
                    std       clrrows,u
                    clr       gotdrv,u
                    clr       defined,u
                    clr       hires,u
                    clr       wide,u              8-bit until W says otherwise

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

* TEXT OVERLAY ON.  Without FX_TXT+FX_OVR the bitmap covers the whole
* screen and every message this program prints goes to a text screen
* that is not being displayed - which is why the SS.BmClear readout
* never reached the operator on the first hardware run.
*
* FT_FOVR MUST BE 0 HERE, and setting it is what blanked the bitmap on
* the second run.  GraphicOutputMixer.v:230 is explicit: with overlay on
* and Show_BG_in_Overlay set, the case 4'b110x - background index NOT
* zero, EITHER font pixel - outputs the FONT colour for the whole cell.
* The text screen is 80x60 and covers the entire display, so every cell
* whose background attribute is non-zero paints solid over the graphics
* and the bitmap disappears.  With the bit clear, case 4'b10x0 sends the
* graphics through wherever a font pixel is background, which is exactly
* the transparent overlay this test wants: glyph pixels only.
                    ldx       #FX_GRF+FX_BM+FX_TXT+FX_OVR
                    ldy       #0                  60 Hz, 320x240, TRANSPARENT overlay
                    lda       #BMPATH
                    ldb       #SS.MCR
                    os9       I$SetStt
                    lbcs      Failed

                    leax      RdyTxt,pcr
                    lbsr      PutLine
                    leax      KeyTxt,pcr
                    lbsr      PutLine
                    leax      KeyTx2,pcr
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
                    cmpa      #'2
                    lbeq      DoHalves
                    cmpa      #'3
                    lbeq      DoFull
                    anda      #$5F                letters fold to upper case
                    cmpa      #'W
                    lbeq      DoWide
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
* Advance the bar colour and STEP OVER CLRVAL.  The scan's whole argument
* is that no byte of the drawn picture can be mistaken for a filled one,
* and a bar in the fill colour would break it - colour 9 used to land on
* rows 72-79 and 184-191, which is exactly where a badly short fill would
* be read.
fbcl@               inc       colour,u
                    lda       colour,u
                    cmpa      #15
                    blo       fbc2@
                    lda       #1
                    sta       colour,u
fbc2@               cmpa      #CLRVAL
                    beq       fbcl@
fnxt@               ldd       rowsleft,u
                    subd      #1
                    std       rowsleft,u
                    lbne      frow@
* A SENTINEL PAST THE END, so that "next" means something.  That byte is
* the off-by-one check, and it lives in the UNINITIALISED part of the
* slab: one hardware run read it as $09 - the fill value itself - and
* another read $E8 at the same offset, so it was leftover and not
* evidence either way.  With this, "next $AA" is a fill that stopped
* where it should and "next $09" is one that ran past the end.  bmptr is
* already sitting on it, because the walk ends inside the tenth block
* with $400 to spare.
                    ldx       bmptr,u
                    lda       #SENTVAL
                    sta       ,x+
                    sta       ,x+
                    sta       ,x+
                    sta       ,x
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
* ShowErrAt - X = a prefix string, B = the error code.  ShowErr is the
* same thing with the generic prefix.
ShowErr             leax      ErrTxt,pcr
ShowErrAt           pshs      b
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
* increment that share a clock.  At the FULL 240 rows, "last 09, next AA"
* is right: "last" not the fill value means it came up one byte short,
* and "next" not SENTVAL means it ran one byte past.  Below 240 rows
* "last" is simply the bar colour that row was drawn in.
*
* THE SCAN IS THE BETTER INSTRUMENT AND IT ANSWERS THE SAME QUESTION: a
* fill one byte short reads "SHORT, mid-row" at 239,319.  This pair is
* kept because it is a direct read of the two bytes in question.
*
* BMOFF + 76,800 - 1 = $13BFF, which is offset $1BFF of the TENTH block
* of the slab - so the byte after it, at $1C00, is still inside the slab
* and safe to read.
********************************************************************
* Say what is about to be attempted BEFORE attempting it, so a row count
* that kills the machine is on the screen when it does.
* THE ROW COUNT ADVANCES ON EVERY PRESS, ERROR OR NOT, and that matters
* more than it looks.  It used to be bumped at the very END of DoClear,
* so any error path jumped back to Loop before reaching it and the count
* FROZE.  Once SS.BmClear started failing, every later press reprinted
* the same number - and "it stops at 236" then means "the engine wedged",
* which is a completely different fault from "the fill came up short at
* row 236".  Two hardware runs were reported as the second when they may
* well have been the first.  An instrument that can freeze its own
* counter cannot tell those apart, so it does not freeze any more:
* clrnow is what THIS press asks for, and clrrows has already moved on.
DoClear             ldd       clrrows,u
                    std       clrnow,u
                    cmpd      #BMROWS
                    bhs       dcmax@
                    addd      #1
                    std       clrrows,u
dcmax@              equ       *
* AND ASK WHETHER THE ENGINE WAS ALREADY BUSY, before touching anything.
* A 1 here means the PREVIOUS press left a transfer outstanding and never
* got it back - which is the stuck-engine case, visible one press earlier
* than the error it eventually causes.
                    pshs      u
                    lda       #BMPATH
                    ldb       #SS.BmClear
                    os9       I$GetStt
                    tfr       x,d
                    puls      u
                    stb       befbsy,u
                    leax      RowTxt,pcr
                    lbsr      StartLine
                    ldd       clrnow,u
                    lbsr      AppDc16
                    leax      BefTxt,pcr
                    lbsr      AppStr
                    lda       befbsy,u
                    lbsr      AppHex
                    lbsr      EndLine
* REDRAW THE BARS FIRST, so each press measures only what THAT press did.
* The fill always covers a prefix of the bitmap and the row count creeps
* up by one per press, so without this the second press would find the
* first press's bytes still in place and read them as its own - a fill
* that did nothing at all would look like a pass.
                    lbsr      FillBm
                    bcc       dcdrawn@
                    lbsr      ShowErr
                    lbra      Loop
* C AND 2 NOW GO THROUGH THE SAME CODE, and finding out that they have to
* is what this session was actually about.  On K2 hardware 2 ran over and
* over without a fault while C wedged the machine on the first press, and
* the ONLY thing C did that 2 never did was read the busy bit back
* IMMEDIATELY after arming, with no sleep in between.  That read is a
* full I$GetStt - IOMan, SCF, vtio, grfdrv, about 474 us of system-state
* execution with interrupts masked - and it runs while the transfer is
* armed and waiting for the window to open.  When the window opens,
* Bus_RDY_o = Available & Progress halts the CPU wherever it happens to
* be; 2 is parked in F$Sleep at that moment and C is inside a driver.
* The line the machine died halfway through printing was that read's.
*
* The immediate read was added to tell "the start was accepted" from
* "there is no working DMA on this core".  The first of those is settled
* now - the engine takes the start edge - so the diagnostic has outlived
* its question, and it is gone rather than kept for one that is answered.
dcdrawn@            clra                          first row 0
                    ldb       clrnow+1,u          the rows to fill this time
                    lbsr      ClrOne
                    lbcs      Loop                ClrOne has already said why
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
                    leax      DstTxt,pcr
                    lbsr      AppStr
                    lda       codsth,u
                    lbsr      AppHex
                    lda       codstl,u
                    lbsr      AppHex
                    lda       codstl+1,u
                    lbsr      AppHex
* Give the window back.  Every other MapCur in this file is paired with
* an UnmapCur and this one was not, so each C leaked an 8K logical block
* until F$MapBlk ran the process out of its eight and started failing.
                    pshs      y
                    lbsr      UnmapCur
                    puls      y
ClrNoMap            lbsr      EndLine
* And now WHERE the fill reached.  Walk the bitmap for the first byte
* that is not the fill value and report it as a row and column.  This is
* the measurement that separates the two readings of a short fill: a
* COUNT bug stops partway through a row, a BASE mismatch between what the
* DMA writes and what VICKY reads loses whole rows and stops at column 0.
                    lbsr      ClrScan
* The row count moved on at the TOP of DoClear, so there is nothing to do
* here - see the note there for why it is not done at the end any more.
                    lbra      Loop

********************************************************************
* 2 - the same whole-bitmap clear in TWO HALVES, which is what the first
*     row parameter was added for: rows 0-119, then rows 120-239, each
*     its own SS.BmClear and each waited out before the next is armed.
*
* It asks two questions at once.  Whether splitting a fill changes
* anything - the reason it was wanted - and what CONSECUTIVE TRANSFERS
* do, which the RTL says is not obvious: the engine loads its write
* pointer only while Write_Strobe is LOW, at VALIDATE2, so a second
* transfer that arrives with it still high keeps the FIRST one's
* pointer and carries on from where that ended.  Nothing else in this
* program arms the engine twice in a row, so nothing else has ever
* exercised it.
*
* A pass is the same line C gives for 240 rows: fill 0,0 to 239,319
* COMPLETE.  If the second half lands anywhere but row 120, the pointer
* was stale and that is the finding.
********************************************************************
DoHalves            ldd       #BMROWS
                    std       clrnow,u            the verdict is for both halves
                    leax      HlfTxt,pcr
                    lbsr      PutLine
                    lbsr      FillBm
                    bcc       dh1@
                    lbsr      ShowErr
                    lbra      Loop
dh1@                clra                          first row 0
                    ldb       #BMROWS/2           120 rows
                    lbsr      ClrOne
                    bcc       dh2@
                    leax      Hlf1E,pcr
                    lbsr      ShowErrAt
                    lbra      Loop
dh2@                lda       #BMROWS/2           first row 120
                    ldb       #BMROWS/2           120 rows
                    lbsr      ClrOne
                    bcc       dh3@
                    leax      Hlf2E,pcr
                    lbsr      ShowErrAt
                    lbra      Loop
dh3@                lbsr      ClrScan
                    lbra      Loop

********************************************************************
* 3 - THE WHOLE BITMAP IN ONE CALL, 240 rows, over and over.
*
* C creeps its row count up one per press and stops at 240, so it reaches
* a full-screen fill once and then repeats it; this is the same fill with
* nothing else moving, which is what hammering it wants.  Take it with W
* to compare the two transfer widths on identical work.
********************************************************************
DoFull              ldd       #BMROWS
                    std       clrnow,u            the scan's verdict is for 240
                    lbsr      FillBm
                    bcc       df1@
                    lbsr      ShowErr
                    lbra      Loop
df1@                clra                          first row 0
                    ldb       #BMROWS             all 240 rows
                    lbsr      ClrOne
                    lbcs      Loop
                    lbsr      ClrScan
                    lbra      Loop

********************************************************************
* W - 8-bit or 16-bit transfers, for C, 2 and 3 alike.
*
* 16-bit is twice the rate - 384 us against 768 for a whole bitmap - and
* it is a SEPARATE PATH THROUGH THE ENGINE, Double_Speed_DMA, with its
* own end comparison and its own byte-lane handling.  The driver shipped
* 16-bit-when-even for a while on the strength of the RTL alone and it
* was backed out to match the user's own working 2025 test, which is
* 8-bit.  So the default here is 8-bit and this key is how the other
* path finally gets run.
********************************************************************
DoWide              lda       wide,u
                    eora      #1
                    sta       wide,u
                    leax      W8Txt,pcr
                    tst       wide,u
                    beq       dw@
                    leax      W16Txt,pcr
dw@                 lbsr      PutLine
                    lbra      Loop

********************************************************************
* ClrOne - one SS.BmClear and wait for it.  A = first row, B = rows.
*   Returns the carry and B: clear means it finished, set means B is
*   the error - either the SetStat's own or E$NotRdy for a fill that
*   never came back.
*
* NEITHER TFR NOR PULS TOUCHES CC, which is what lets the call's carry
* survive all the way to the bcs below it.
********************************************************************
ClrOne              sta       cofrow,u
                    stb       corows,u
* SAY WHAT IS BEING PASSED, BEFORE PASSING IT.  Every register the call
* gets, in the order the driver reads them, so a rejected argument can be
* checked against the driver's own limits without guessing.
                    leax      OneTxt,pcr
                    lbsr      StartLine
                    lda       #CLRVAL
                    lbsr      AppDec
                    leax      OneRw,pcr
                    lbsr      AppStr
                    lda       cofrow,u
                    lbsr      AppDec
                    leax      OneCt,pcr
                    lbsr      AppStr
                    lda       corows,u
                    lbsr      AppDec
                    leax      OneW8,pcr
                    tst       wide,u
                    beq       cow@
                    leax      OneW16,pcr
cow@                lbsr      AppStr
                    lbsr      EndLine
* R$X = flags : fill value.  Bit 0 of the high byte asks for 16-bit.
* BUILT BEFORE "tfr d,u", because after that U is the row parameter and
* "wide,u" would be reading through it.
                    ldx       #CLRVAL
                    tst       wide,u
                    beq       cox@
                    ldx       #$0100+CLRVAL
cox@                lda       cofrow,u
                    ldb       corows,u
                    pshs      u
                    tfr       d,u                 R$U = first row : row count
                    ldy       #0                  bitmap 0
                    lda       #BMPATH
                    ldb       #SS.BmClear
                    os9       I$SetStt
                    puls      u                   PULS leaves CC and B alone
                    bcc       co0@
                    leax      OneSE,pcr
                    lbsr      ShowErrAt
                    comb
                    rts
co0@                clr       clrtck,u
co1@                ldx       #2                  one 60 Hz tick
                    pshs      u
                    os9       F$Sleep
                    puls      u
                    pshs      u
                    lda       #BMPATH
                    ldb       #SS.BmClear
                    os9       I$GetStt
* KEEP THE CARRY, THE ERROR AND THE ANSWERS BEFORE ANYTHING TOUCHES
* THEM.  A "tfr x,d" stood here and overwrote B with X's low byte, so a
* failing call reported "err 187" - a number that is not an error code at
* all.  That is the SECOND time this exact trap has cost a hardware run
* in this file; docs/status.md records the first.
                    pshs      cc,b,x,y,u          ,s=CC 1,s=B 2,s=X 4,s=Y 6,s=U 8,s=data ptr
                    ldu       8,s
                    ldb       1,s
                    stb       coerr,u
                    ldd       2,s                 R$X = 0 idle, 1 outstanding
                    std       cobusy,u
                    ldd       4,s                 R$Y = the engine's dst, high byte
                    stb       codsth,u
                    ldd       6,s                 R$U = its mid and low
                    std       codstl,u
                    puls      cc,b,x,y,u
                    puls      u
                    bcc       co2@
                    leax      OneGE,pcr
                    lbsr      ShowErrAt           B is the REAL error here
                    comb
                    rts
co2@                ldd       cobusy,u
                    beq       co8@
                    inc       clrtck,u
                    lda       clrtck,u
                    cmpa      #CLRWAIT
                    blo       co1@
                    leax      OneNR,pcr
                    lbsr      PutLine
                    comb
                    ldb       #E$NotRdy           it never came back
                    rts
* Done.  Say where the ENGINE thinks it was writing, which is the one
* reading that does not depend on the driver being right.
co8@                leax      OneOk,pcr
                    lbsr      StartLine
                    lda       codsth,u
                    lbsr      AppHex
                    lda       codstl,u
                    lbsr      AppHex
                    lda       codstl+1,u
                    lbsr      AppHex
                    lbsr      EndLine
                    andcc     #^Carry
                    rts

********************************************************************
* ClrScan - walk BITMAP 0, not the slab, and say where the fill value
*   starts and where it stops, each as a row and a column.
*
* THE OLD SCAN ANSWERED THE WRONG QUESTION AND ANSWERED IT BADLY.  It
* swept all twelve blocks for a SINGLE byte equal to the fill value.  The
* $1000 of slab in front of the bitmap is uninitialised, so it reported
* garbage hits from memory the fill never touches - "blk $00 off $0145"
* in the last hardware run was one.  And "where did the fill land" is
* what GetStat's dma dst now answers exactly, from the engine's own
* registers, so the scan should be answering the question only the pixels
* can: DID IT FINISH, and if not, where did it stop?
*
* So this walks the bitmap's 76,800 bytes in row order and reports two
* positions: the first byte that IS the fill value, which catches a fill
* that started late, and the first one after it that is NOT, which is
* where it stopped.  A column of 0 there means it stopped ON A ROW
* BOUNDARY - the vertical-blanking window problem; any other column means
* it stopped MID-ROW - a count problem.  Separating those two is the
* whole reason the scan exists.
*
* It rests on FillBm leaving CLRVAL out of the bars, so no byte of the
* drawn picture can be mistaken for a filled one.
********************************************************************
ClrScan             clr       scanbad,u
                    ldx       #0
                    stx       scanrow,u
                    stx       scancol,u
                    lda       slabblk,u
                    sta       curblk,u
                    lbsr      MapCur
                    lbcs      ScErr
                    ldd       winaddr,u
                    addd      #BMOFF              the bitmap, not the slab
                    std       bmptr,u
                    ldd       #BLKSIZE-BMOFF
                    std       blkleft,u
                    ldd       #BMROWS
                    std       rowsleft,u
scrow@              ldx       #BMCOLS
                    stx       rowleft,u
scbyte@             ldx       blkleft,u
                    bne       scb2@
                    lbsr      NextBlk
                    lbcs      ScErr
scb2@               ldx       bmptr,u
                    lda       ,x+
                    stx       bmptr,u
                    cmpa      #CLRVAL
                    beq       scfill@
* Not the fill value.  If the fill has already begun, this is where it
* stopped and the walk is over; scanrow and scancol are still this byte's
* own position, because they are stepped on afterwards.
                    tst       scanbad,u
                    bne       scstop@
                    bra       scnext@
scfill@             tst       scanbad,u
                    bne       scnext@
                    inc       scanbad,u           the first filled byte
                    ldx       scanrow,u
                    stx       scansr,u
                    ldx       scancol,u
                    stx       scansc,u
* LEAX and LEAY are used for the counters rather than ADDD/SUBD because A
* is carrying the byte just read all the way down to here.
scnext@             ldx       blkleft,u
                    leax      -1,x
                    stx       blkleft,u
                    ldx       scancol,u
                    leax      1,x
                    stx       scancol,u
                    ldx       rowleft,u
                    leax      -1,x
                    stx       rowleft,u
                    bne       scbyte@
                    ldx       #0
                    stx       scancol,u
                    ldx       scanrow,u
                    leax      1,x
                    stx       scanrow,u
                    ldx       rowsleft,u
                    leax      -1,x
                    stx       rowsleft,u
                    lbne      scrow@
* Off the end of the bitmap with nothing to stop us: either the fill ran
* all the way, and scanrow is BMROWS with scancol 0, or it never began.
                    lbsr      UnmapCur
                    tst       scanbad,u
                    bne       screp@
                    leax      ScNoneTx,pcr
                    lbra      PutLine
* REPORT THE LAST BYTE FILLED, NOT THE FIRST ONE THAT IS NOT.  The walk
* naturally stops on the first MISmatch, so scanrow:scancol is an
* EXCLUSIVE bound - and printed raw it said things like "fill 0,0 to
* 237,0", which reads as an inclusive end and then makes no sense,
* because a full-width fill cannot end at column 0.  It meant "rows 0-236
* are filled", i.e. a PASS for 237 rows, and it was read as a failure at
* row 237.  Backing up one byte says "fill 0,0 to 236,319", which is what
* it always meant and cannot be misread: a last column of 319 is a whole
* row, anything else stopped mid-row.
* Backing up across a row boundary is the only wrinkle, and the
* ran-to-the-end case (240,0) falls out of the same arithmetic as
* (239,319).
scstop@             lbsr      UnmapCur
screp@              ldd       scancol,u
                    bne       scdec@
                    ldd       #BMCOLS-1
                    std       scanec,u
                    ldd       scanrow,u
                    subd      #1
                    std       scaner,u
                    bra       scsay1@
scdec@              subd      #1
                    std       scanec,u
                    ldd       scanrow,u
                    std       scaner,u
scsay1@             leax      ScFrTx,pcr
                    lbsr      StartLine
                    ldd       scansr,u
                    lbsr      AppDc16
                    leax      ScComTx,pcr
                    lbsr      AppStr
                    ldd       scansc,u
                    lbsr      AppDc16
                    leax      ScToTx,pcr
                    lbsr      AppStr
                    ldd       scaner,u
                    lbsr      AppDc16
                    leax      ScComTx,pcr
                    lbsr      AppStr
                    ldd       scanec,u
                    lbsr      AppDc16
* The verdict, and it is the reason the two positions are measured rather
* than just printed: a late start, a short fill on a row boundary and a
* short fill inside a row are three different faults.  A pass is the last
* byte of the last row asked for: row clrnow-1, column 319.
                    ldd       scansr,u
                    bne       sclate@
                    ldd       scansc,u
                    bne       sclate@
                    ldd       clrnow,u
                    subd      #1
                    cmpd      scaner,u
                    blo       scover@             it went past the rows asked for
                    bhi       scshort@
                    ldd       scanec,u
                    cmpd      #BMCOLS-1
                    bne       scmid@              the last row is incomplete
                    leax      ScOkTx,pcr
                    bra       scsay@
scshort@            ldd       scanec,u
                    cmpd      #BMCOLS-1
                    bne       scmid@
                    leax      ScRowTx,pcr
                    bra       scsay@
scmid@              leax      ScMidTx,pcr
                    bra       scsay@
scover@             leax      ScOverTx,pcr
                    bra       scsay@
sclate@             leax      ScLateTx,pcr
scsay@              lbsr      AppStr
                    lbra      EndLine
ScErr               leax      ScErrTx,pcr
                    lbra      PutLine

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

********************************************************************
* AppDc16 - D as decimal, 0-65535, with no leading zeros.  AppDec only
*   takes a byte and a column runs to 319, so the scan needs this one.
*   Y is the line pointer, as everywhere else here.
********************************************************************
AppDc16             pshs      a,b,x
                    std       dcval,u
                    clr       dcsup,u
                    leax      DcTab,pcr
dc1@                ldd       ,x                  10000, 1000, 100, 10, then 0
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

* EndLine FALLS THROUGH INTO PutLine, so it terminates the line AND
* prints it.  Calling PutLine after it prints the line twice, which is
* exactly what the C, L and F keys did on their first MAME run.
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
HlfTxt              fcc       /  2 - clearing in two halves: rows 0-119, then rows 120-239/
                    fcb       C$CR
OneTxt              fcc       /  clear bm 0 val /
                    fcb       $00
OneRw               fcc       / row /
                    fcb       $00
OneCt               fcc       / rows /
                    fcb       $00
OneOk               fcc       /   -> done, engine dst $/
                    fcb       $00
OneSE               fcc       /  SetStt err /
                    fcb       $00
OneGE               fcc       /  GetStt err /
                    fcb       $00
OneNR               fcc       /  it never came back/
                    fcb       C$CR
OneW8               fcc       / 8-bit/
                    fcb       $00
OneW16              fcc       / 16-bit/
                    fcb       $00
W8Txt               fcc       /  W - transfers are 8-BIT now (768 us a bitmap)/
                    fcb       C$CR
W16Txt              fcc       /  W - transfers are 16-BIT now (384 us a bitmap, the untried path)/
                    fcb       C$CR
Hlf1E               fcc       /  2 first half err /
                    fcb       $00
Hlf2E               fcc       /  2 second half err /
                    fcb       $00
* The key line was one string of 97 characters and I$WritLn is given 80,
* so "G guard Q quit" never reached the screen.  Two lines now.
KeyTx2              fcc       /C clear  2 halves  3 full  W width  L lines  F flood  K kill  G guard/
                    fcb       C$CR
KeyTxt              fcc       /H hide  S show  B blocks  4 hires  8 normal  R redraw  Q quit/
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
LnTxt               fcc       /  SS.BmLine fan: drew /
                    fcb       $00
FldTxt              fcc       /  SS.BmLine flood: drew /
                    fcb       $00
LnTx2               fcc       / of them/
                    fcb       $00
LnTx3               fcc       /, then stopped with error /
                    fcb       $00
RowTxt              fcc       /  C rows /
                    fcb       $00
BefTxt              fcc       /, busy before $/
                    fcb       $00
DstTxt              fcc       / dma dst $/
                    fcb       $00
ScNoneTx            fcc       /  C scan: NOT ONE BYTE of the bitmap holds the fill value/
                    fcb       C$CR
ScFrTx              fcc       /  C scan: fill /
                    fcb       $00
ScComTx             fcc       /,/
                    fcb       $00
ScToTx              fcc       / to /
                    fcb       $00
ScOkTx              fcc       / COMPLETE/
                    fcb       $00
ScRowTx             fcc       / SHORT, on a row boundary/
                    fcb       $00
ScMidTx             fcc       / SHORT, mid-row/
                    fcb       $00
ScOverTx            fcc       / PAST THE ROWS ASKED FOR/
                    fcb       $00
ScLateTx            fcc       / LATE START/
                    fcb       $00
ScErrTx             fcc       /  C scan: could not map the bitmap/
                    fcb       C$CR
ErrTxt              fcc       /bmtest: error /
                    fcb       $00

                    emod
eom                 equ       *
                    end
