********************************************************************
* CoDV - CoCoDV 80x30 text console co-module for VTIO (Level 2)
*
* The CoCoDV digital video board watches the VDG pins and, in its tile
* graphics mode, shows an 80x30 text screen using its own character RAM.
* This is a Level 2 port of John Federico's Level 1 CoDV driver (a copy of
* CoVDG changed for the CoCoDV), for the CoCo 1/2 with an i-MMU-nity MMU.
*
* The module is named CoVDG so that the CoCo 3 VTIO, which links its VDG
* co-module by that name, uses it unchanged: a COCODV=1 build has CoDV in
* place of CoVDG. The entry table and the VD.xxxx statics are CoVDG's.
* There are no graphics display codes ($0F-$1F are ignored).
*
* Screen memory: the CoCoDV tile mode needs a 6K PMODE 4 ("6R") screen:
* 2400 character bytes (80x30) at the start, colour bytes from 4000. The
* VDG only displays motherboard RAM, so each screen is a block from the
* VDG pool (motherboard blocks $38-$3D, marked NotRAM by krn; a free one is
* exactly NotRAM, claimed by setting RAMinUse): up to 5 screens.
*
* The screens are not kept in system address space. Like GrfDrv with its
* windows, CoDV maps the screen it is working on in when needed: slot 1 of
* the system map ($2000-$3FFF) normally holds Bt.Block (krn reserves its
* pages), and CoDV puts its screen's block there on entry (Init, Write and
* the cursor X,Y callback) and Bt.Block back on exit. So every screen is
* at $2000. Showing a screen needs no mapping: the SAM is pointed at the
* block's motherboard address.
*
* CoCoDV setup, done once by the first CoDV screen's Init, the way the
* manual's BASIC examples (SUBS.BAS) do it: the data is placed at the start
* of the displayed screen, the unlock code is sent on the VDG mode pins
* ($FF22), and $FF22 = 0 locks it in again:
*   1. registers 1-7, with REG02 bit 3 = open the first 128 tiles
*   2. the 1K font from /DD/FONT/CODVFONT (codvfont.asm) into those tiles;
*      it is read first, with IRQs on, into the colour area. Without the
*      file this step is skipped.
*   3. registers 1-15: monochrome, 80x30 tile text mode (REG03 = $F7)
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   1      2023/02/18  John Federico
* Level 1 CoDV, from CoVDG.
*   1      2026/09/30
* Level 2 version for the i-MMU-nity port.

                    nam       CoDV
                    ttl       CoCoDV 80x30 text console for VTIO

                  IFP1
                    use       defsfile
                    use       cocovtio.d
                    use       vdgdefs
                  ENDC

tylg                set       Systm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

Cols                equ       80
Rows                equ       30
ScrSize             equ       Cols*Rows character bytes
VidSize             equ       6144      whole 6R screen (characters + colours)
VSpace              equ       $60       VDG code for a space
FontBuf             equ       4096      font file buffer: the colour area
ScrBase             equ       $2000     screens are mapped in system slot 1
ScrSlot             equ       1
MMUSlot             equ       $FFA0+ScrSlot system task (task 0) MMU register
PIA1B               equ       $FF22     VDG mode pins

                    mod       eom,name,tylg,atrv,start,size

u0000               rmb       0
size                equ       .

                    fcb       $07

name                fcs       /CoVDG/           VTIO links CoVDG
                    fcb       edition

* Entry table (the same offsets as CoVDG)
start               lbra      Init
                    lbra      Write
                    lbra      GetStat
                    lbra      SetStat
                    lbra      Term
* CoWinSpc special processing entry (called from VTIO)
* Entry: A = 0: select this screen (set the display), 1: update mouse packet
                    tsta
                    bne       Spc1
                    tst       >WGlobal+G.CrDvFl ; are we the displayed device?
                    beq       NoOp
                    lbra      SetVid
Spc1                deca
                    bne       NoOp
                    ldx       <D.CCMem  ; copy actual mouse X,Y to window relative
                    leax      <G.Mouse+Pt.AcX,x
                    ldd       ,x
                    std       Pt.WRX-Pt.AcX,x
                    ldd       Pt.AcY-Pt.AcX,x
                    std       Pt.WRY-Pt.AcX,x
NoOp                clrb
                    rts

**************************************************
* Init: get a screen, set up the CoCoDV, clear the screen
Init                pshs      u,y,x
                    lda       #$AF      ; blue block cursor, as CoVDG
                    sta       <VD.CColr,u
                    lbsr      GetBlk    ; b = VDG pool block
                    lbcs      InitRts
                    stb       <VD.GBuff,u
                    lbsr      MapScr
                    ldx       #ScrBase
                    stx       <VD.ScrnA,u
                    stx       <VD.CrsrA,u
                    leax      ScrSize,x
                    stx       <VD.ScrnE,u
                    lda       #VSpace
                    sta       <VD.CChar,u
                    sta       <VD.Chr1,u
                    ldd       #Cols*256+Rows
                    std       <VD.Col,u
                    clr       <VD.CFlag,u ; the font needs the plain VDG mapping
                    leax      <VD.NChar,u ; where VTIO puts parameter bytes
                    stx       <VD.EPlt1,u
                    stx       <VD.EPlt2,u
                    inc       <VD.Start,u
                    lbsr      ClrVid
* The CoCoDV settings and font are global: only the first CoDV screen sets
* them up (VTIO's "VDG co-module found" flag is set at the end of Init)
                    ldx       <D.CCMem
                    lda       <G.BCFFlg,x
                    bita      #$02
                    bne       InitClr
                    lbsr      ReadFont  ; carry set: no font file
                    lbsr      DVSetup   ; program the CoCoDV
InitClr             lbsr      ClrScrn
                    ldx       <D.CCMem
                    ldb       <G.BCFFlg,x
                    orb       #$02      ; vdg co-module found
                    stb       <G.BCFFlg,x
                    clrb
                    lbsr      UnMap
InitRts             puls      pc,u,y,x

**************************************************
* Term: give the screen back
Term                pshs      u,y,x
                    clr       <VD.Start,u
                    lbsr      FreeBlk   ; give the screen block back to the pool
                    ldb       #$E1      ; clear the VDG statics
                    leax      <VD.Strt1,u
TermLp              clr       ,x+
                    decb
                    bne       TermLp
                    clrb
                    puls      pc,u,y,x

**************************************************
* Write
* Entry: A = char to write, Y = path descriptor, U = device statics
Write               lbsr      MapScr
                    bsr       WriteIn
                    lbra      UnMap

WriteIn             cmpa      #$0E
                    bls       Dispatch
                    cmpa      #$1B      ; escape
                    lbeq      Escape
                    cmpa      #$1F      ; graphics codes: ignore
                    lbls      NoOp
                    tsta
                    bmi       PutChr    ; high bit chars go straight through
                    cmpa      #'|
                    bne       Wr1
                    lda       #$21
                    bra       PutChr
Wr1                 cmpa      #'~
                    bne       Wr2
                    lda       #$2D
                    bra       PutChr
Wr2                 cmpa      #$60      ; lower case: $00-$1F
                    blo       Wr3
                    suba      #$60
                    bra       PutChr
Wr3                 cmpa      #$40      ; upper case: $40-$5F
                    blo       Wr4
                    suba      #$40
Wr4                 eora      #$40      ; punctuation/digits: $60-$7F
PutChr              ldx       <VD.CrsrA,u
                    sta       ,x+
                    stx       <VD.CrsrA,u
                    cmpx      <VD.ScrnE,u
                    blo       PutShow
                    lbsr      SScrl
PutShow             lbra      ShowCrsr

Dispatch            leax      <DCodeTbl,pcr
                    lsla
                    ldd       a,x
                    jmp       d,x

DCodeTbl            fdb       NoOp-DCodeTbl $00 no-op
                    fdb       CurHome-DCodeTbl $01 home cursor
                    fdb       CurXY-DCodeTbl $02 cursor X,Y
                    fdb       DelLine-DCodeTbl $03 erase line
                    fdb       ErEOLine-DCodeTbl $04 erase to end of line
                    fdb       CrsrSw-DCodeTbl $05 cursor on/off/colour (byte from VTIO)
                    fdb       CurRght-DCodeTbl $06 cursor right
                    fdb       NoOp-DCodeTbl $07 bell (VTIO)
                    fdb       CurLeft-DCodeTbl $08 cursor left
                    fdb       CurUp-DCodeTbl $09 cursor up
                    fdb       CurDown-DCodeTbl $0A cursor down
                    fdb       ErEOScrn-DCodeTbl $0B erase to end of screen
                    fdb       ClrScrn-DCodeTbl $0C clear screen
                    fdb       Retrn-DCodeTbl $0D carriage return
                    fdb       Do0E-DCodeTbl $0E alpha display

* $1B xx: VTIO has collected xx. $1B $31 rr cc (palette) takes 2 more
* bytes; swallow them. Everything else is ignored.
Escape              lda       <VD.NChar,u
                    cmpa      #$31
                    bne       NoOp1
                    ldb       #2
                    leax      <NoOp1,pcr
                    stb       <VD.NGChr,u
                    stx       <VD.RTAdd,u
NoOp1               clrb
                    rts

* $0E - show this screen
Do0E                tst       >WGlobal+G.CrDvFl
                    beq       NoOp1
                    lbra      SetVid

* Scroll the screen up one line; cursor to the start of the last line
SScrl               ldx       <VD.ScrnA,u
                    leax      Cols,x
SScrlLp             ldd       ,x++
                    std       -Cols-2,x
                    cmpx      <VD.ScrnE,u
                    blo       SScrlLp
                    leax      -Cols,x
                    stx       <VD.CrsrA,u
                    lda       #Cols
                    ldb       #VSpace
SScrlCl             stb       ,x+
                    deca
                    bne       SScrlCl
                    rts

* Row and column of a screen address
* Entry: X = screen address
* Exit:  A = row, B = column (X preserved)
RowCol              tfr       x,d
                    subd      <VD.ScrnA,u
                    clr       ,-s
RowColLp            cmpd      #Cols
                    blo       RowColOk
                    subd      #Cols
                    inc       ,s
                    bra       RowColLp
RowColOk            puls      a,pc

* $0D - carriage return
Retrn               bsr       HideCrsr
                    bsr       RowCol
                    clra
                    pshs      d
                    tfr       x,d
                    subd      ,s++
                    std       <VD.CrsrA,u
ShowCrsr            ldx       <VD.CrsrA,u
                    lda       ,x
                    sta       <VD.CChar,u
                    lda       <VD.CColr,u
                    beq       RtsOk
PutCrsr             sta       ,x
RtsOk               clrb
                    rts

* $0A - cursor down (scrolls at the bottom)
CurDown             bsr       HideCrsr
                    leax      Cols,x
                    cmpx      <VD.ScrnE,u
                    blo       CurDn1
                    leax      -Cols,x
                    pshs      x
                    bsr       SScrl
                    puls      x
CurDn1              stx       <VD.CrsrA,u
                    bra       ShowCrsr

* $08 - cursor left
CurLeft             bsr       HideCrsr
                    cmpx      <VD.ScrnA,u
                    bls       ShowCrsr
                    leax      -1,x
                    stx       <VD.CrsrA,u
                    bra       ShowCrsr

* $06 - cursor right
CurRght             bsr       HideCrsr
                    leax      1,x
                    cmpx      <VD.ScrnE,u
                    bhs       ShowCrsr
                    stx       <VD.CrsrA,u
                    bra       ShowCrsr

* $09 - cursor up
CurUp               bsr       HideCrsr
                    leax      -Cols,x
                    cmpx      <VD.ScrnA,u
                    blo       ShowCrsr
                    stx       <VD.CrsrA,u
                    bra       ShowCrsr

* $0B - erase to end of screen
ErEOScrn            bsr       HideCrsr
                    bra       ClrFrom
* $0C - clear screen and home the cursor
ClrScrn             bsr       CurHome
ClrFrom             lda       #VSpace
ClrLp               sta       ,x+
                    cmpx      <VD.ScrnE,u
                    blo       ClrLp
                    bra       ShowCrsr

* $01 - home cursor
CurHome             bsr       HideCrsr
                    ldx       <VD.ScrnA,u
                    stx       <VD.CrsrA,u
                    bra       ShowCrsr

* Take the cursor off the screen
* Exit: X = cursor address
HideCrsr            ldx       <VD.CrsrA,u
                    lda       <VD.CChar,u
                    sta       ,x
                    clrb
                    rts

* $05 xx - cursor off (xx=$20), default ($21), black ($22), colour
CrsrSw              lda       <VD.NChar,u
                    suba      #C$SPAC
                    bne       CrsrSw1
                    sta       <VD.CColr,u
                    bra       HideCrsr
CrsrSw1             cmpa      #$0B
                    bge       RtsOk
                    cmpa      #$01
                    bgt       CrsrSw2
                    lda       #$AF
                    bra       CrsrSw4
CrsrSw2             cmpa      #$02
                    bgt       CrsrSw3
                    lda       #$A0
                    bra       CrsrSw4
CrsrSw3             suba      #$03
                    lsla
                    lsla
                    lsla
                    lsla
                    ora       #$8F
CrsrSw4             sta       <VD.CColr,u
                    ldx       <VD.CrsrA,u
                    lbra      PutCrsr

* $02 xx yy - cursor to column xx-32, row yy-32
CurXY               ldb       #2
                    leax      <DoCurXYM,pcr
                    stb       <VD.NGChr,u
                    stx       <VD.RTAdd,u
                    clrb
                    rts

* Called by VTIO when it has the two bytes, so map the screen here too
DoCurXYM            lbsr      MapScr
                    bsr       DoCurXY
                    lbra      UnMap

DoCurXY             bsr       HideCrsr
                    lda       <VD.NChar,u
                    suba      #C$SPAC
                    cmpa      #Cols
                    bhs       CurXYX
                    ldb       <VD.NChr2,u
                    subb      #C$SPAC
                    lda       #Cols
                    mul
                    addb      <VD.NChar,u
                    adca      #0
                    subd      #C$SPAC
                    addd      <VD.ScrnA,u
                    cmpd      <VD.ScrnE,u
                    bhs       CurXYX
                    std       <VD.CrsrA,u
CurXYX              lbra      ShowCrsr

* $04 - erase to end of line
ErEOLine            bsr       HideCrsr
                    lbsr      RowCol
                    negb
                    addb      #Cols     ; b = chars left on the line
                    bra       ErLine

* $03 - erase the line the cursor is on
DelLine             lbsr      Retrn
                    ldb       #Cols
ErLine              lda       #VSpace
                    ldx       <VD.CrsrA,u
ErLineLp            sta       ,x+
                    decb
                    bne       ErLineLp
                    lbra      ShowCrsr

**************************************************
* GetStat
GetStat             ldx       PD.RGS,y
                    cmpa      #SS.ScSiz
                    beq       Rt.ScSiz
                    cmpa      #SS.Cursr
                    beq       Rt.Cursr
                    comb
                    ldb       #E$UnkSvc
                    rts

* Exit: X = columns, Y = rows
Rt.ScSiz            ldd       #Cols
                    std       R$X,x
                    ldd       #Rows
                    std       R$Y,x
                    clrb
                    rts

* Exit: X = column+$20, Y = row+$20, A = ASCII char under the cursor
Rt.Cursr            pshs      x
                    ldx       <VD.CrsrA,u
                    lbsr      RowCol
                    puls      x
                    addd      #$2020
                    pshs      a
                    clra
                    std       R$X,x
                    puls      b
                    std       R$Y,x
                    lda       <VD.CChar,u ; back from VDG code to ASCII
                    bmi       CursrA
                    cmpa      #$20
                    blo       CursrLo
                    cmpa      #$40
                    blo       CursrPD
                    cmpa      #$60
                    blo       CursrUp
                    eora      #$40      ; $60-$7F: punctuation/digits
                    bra       CursrA
CursrLo             adda      #$60      ; $00-$1F: lower case
                    bra       CursrA
CursrUp             bra       CursrA    ; $40-$5F: upper case
CursrPD             adda      #$40      ; $20-$3F: inverse punctuation
                    cmpa      #$61
                    bne       CursrP1
                    lda       #'|
                    bra       CursrA
CursrP1             cmpa      #$6D
                    bne       CursrA
                    lda       #'~
CursrA              sta       R$A,x
                    clrb
                    rts

**************************************************
* SetStat: SS.ComSt (true lower case) is accepted and ignored
SetStat             cmpa      #SS.ComSt
                    lbeq      NoOp
                    comb
                    ldb       #E$UnkSvc
                    rts

**************************************************
* Screen memory

* Get a VDG pool block (skips Bt.Block, which holds the boot/text screens,
* and $3E, where DAT.Free maps unused slots)
* Exit: B = block number, or carry set and B = error
GetBlk              ldx       <D.BlkMap
                    ldb       #$38
GetBlkLp            cmpb      #Bt.Block
                    beq       GetBlkNx
                    lda       b,x
                    cmpa      #NotRAM
                    beq       GetBlkOk
GetBlkNx            incb
                    cmpb      #$3E
                    blo       GetBlkLp
                    comb
                    ldb       #E$NoRAM
                    rts
GetBlkOk            lda       #NotRAM+RAMinUse
                    sta       b,x
                    clra                ; d = block number, carry clear
                    rts

* Return the pool block
FreeBlk             clra
                    ldb       <VD.GBuff,u
                    beq       FreeBlkX
                    tfr       d,x
                    ldb       #1
                    os9       F$DelRAM
                    clr       <VD.GBuff,u
FreeBlkX            rts

* Put this screen's block in system slot 1 ($2000-$3FFF): the DAT image
* entry and the task 0 MMU register. All registers are kept.
MapScr              pshs      x,b
                    ldb       <VD.GBuff,u
MapSlot             ldx       <D.SysDAT
                    stb       ScrSlot*2+1,x
                    stb       >MMUSlot
                    puls      x,b,pc

* Put Bt.Block back in slot 1. CC and B (the error status) are kept.
UnMap               pshs      x,b,cc
                    ldb       #Bt.Block
                    ldx       <D.SysDAT
                    stb       ScrSlot*2+1,x
                    stb       >MMUSlot
                    puls      cc,b,x,pc

**************************************************
* Display hardware

* Show this screen: SAM mode 6R (V=110) at the block's motherboard
* address, VDG G/A=1 GM=111 ($FF22 = $F0), which the CoCoDV takes over.
SetVid              lda       >PIA1B
                    anda      #%00000111
                    ora       #$F0
                    sta       >PIA1B
                    sta       >$FFC0    ; v0 = 0
                    sta       >$FFC3    ; v1 = 1
                    sta       >$FFC5    ; v2 = 1
                    lda       <VD.GBuff,u ; motherboard block: address/$200 = (blk&7)*16
                    anda      #$07
                    lsla
                    lsla
                    lsla
                    lsla
                    ldx       #$FFC6    ; f0
                    ldb       #7
SetVidLp            lsra
                    bcc       SetVidCl
                    sta       1,x       ; odd address sets the bit
                    bra       SetVidNx
SetVidCl            sta       ,x        ; even address clears it
SetVidNx            leax      2,x
                    decb
                    bne       SetVidLp
                    clrb
                    rts

* Read the font file into the colour area of the screen (FontBuf)
* Exit: carry set if there is no font
ReadFont            ldd       <D.Proc   ; file I/O for the system, not the caller
                    pshs      d
                    ldd       <D.SysPrc
                    std       <D.Proc
                    leax      FontPath,pcr
                    lda       #READ.
                    os9       I$Open
                    bcs       ReadFnX
                    ldx       <VD.ScrnA,u
                    leax      FontBuf,x
                    ldy       #1024
                    pshs      a
                    os9       I$Read
                    puls      a
                    pshs      cc,b
                    os9       I$Close
                    puls      cc,b
ReadFnX             puls      x         ; (keeps the carry)
                    stx       <D.Proc
                    rts

FontPath            fcc       "/DD/FONT/CODVFONT"
                    fcb       C$CR

* Program the CoCoDV, the way the manual's BASIC examples do it (they work
* on the i-MMU-nity machine; the Level 1 driver's faster sequence did not)
* Entry: carry set to skip the font
DVSetup             pshs      cc        ; carry = no font
                    orcc      #IntMasks
                    lbsr      SetVid
* 1. registers 1-7, REG02 bit 3 opens character RAM (Init has cleared the
*    screen and read the font into FontBuf; don't clear it again)
                    leax      DVFontR,pcr
                    ldb       #DVFontRL
                    bsr       CopyVid
                    lda       #$08      ; css = 1: configuration registers
                    bsr       Config
* 2. the font into character RAM
                    lda       ,s
                    bita      #Carry    ; no font file?
                    bne       DVNoFont
                    ldx       <VD.ScrnA,u
                    leay      ,x
                    leax      FontBuf,x
DVFontLp            ldd       ,x++
                    std       ,y++
                    ldd       ,x++
                    std       ,y++
                    pshs      y
                    ldd       <VD.ScrnA,u
                    addd      #1024
                    cmpd      ,s++
                    bhi       DVFontLp
                    clra                ; css = 0: character/sprite RAM
                    bsr       Config
DVNoFont            equ       *
* 3. 80x30 tile text mode
                    bsr       ClrVid
                    leax      DVSetR,pcr
                    ldb       #DVSetRL
                    bsr       CopyVid
                    lda       #$08
                    bsr       Config
                    bsr       ClrVid    ; characters and colours (colour 0)
                    lbsr      SetVid
                    puls      cc,pc

* One CoCoDV transfer from the start of the screen (as SUBS.BAS does it)
* Entry: A = $08 for configuration registers, 0 for character RAM
Config              pshs      a
                    ora       #$F0      ; pmode 4, CSS as for the unlock
                    sta       >PIA1B
                    bsr       Delay
                    lda       ,s
                    bsr       Unlock
                    bsr       Delay     ; let it read the screen
                    tst       ,s        ; registers: REG00 = 0 locks them
                    beq       Config1
                    ldx       <VD.ScrnA,u
                    clr       ,x
                    bsr       Delay
Config1             clr       >PIA1B    ; lock
                    bsr       Delay
                    puls      a,pc

* About four frames (7500 x 8 cycles at 0.89MHz), not tied to the PIA
Delay               ldx       #7500
DelayLp             leax      -1,x
                    bne       DelayLp
                    rts

* Clear the whole 6K screen to 0
ClrVid              ldx       <VD.ScrnA,u
                    leay      VidSize,x
                    pshs      y
                    clra
                    clrb
ClrVidLp            std       ,x++
                    cmpx      ,s
                    blo       ClrVidLp
                    puls      y,pc

* Copy B bytes from X to the start of the screen
CopyVid             ldy       <VD.ScrnA,u
CopyVidL            lda       ,x+
                    sta       ,y+
                    decb
                    bne       CopyVidL
                    rts

* Unlock sequence on the VDG mode pins: $90 $D0 $C0 $E0 $F0, plus A
* (A = $08 for configuration registers, 0 for character/sprite RAM)
* Each value is held about 1.3ms, like BASIC's POKEs (which work)
Unlock              ora       #$90
                    bsr       UnlkPut
                    eora      #%01000000
                    bsr       UnlkPut
                    eora      #%00010000
                    bsr       UnlkPut
                    eora      #%00100000
                    bsr       UnlkPut
                    eora      #%00010000
UnlkPut             sta       >PIA1B
                    ldx       #150      ; 150 x 8 cycles
UnlkDly             leax      -1,x
                    bne       UnlkDly
                    rts

* Registers 1-7 for the font load
DVFontR             fcb       $01       REG00: update registers 1-7
                    fcb       $00       REG01
                    fcb       $08       REG02: unlock character RAM
                    fcb       $00       REG03: no tile mode
                    fcb       $00,$00,$00 REG04-06
                    fcb       $00       REG07: no colour overrides
DVFontRL            equ       *-DVFontR

* Registers 1-15 for 80x30 text
DVSetR              fcb       $03       REG00: update registers 1-15
                    fcb       $20       REG01: monochrome (no artifacts)
                    fcb       $01       REG02
                    fcb       $F7       REG03: tile mode, 80 wide in memory and on screen, 30 rows
                    fcb       $00,$00,$00 REG04-06
                    fcb       $00       REG07: no colour overrides
                    fdb       $0000     REG08-09: border colour
                    fdb       $0000     REG10-11: background colour 0
                    fdb       $0000     REG12-13: foreground colour
DVSetRL             equ       *-DVSetR

                    emod
eom                 equ       *
                    end
