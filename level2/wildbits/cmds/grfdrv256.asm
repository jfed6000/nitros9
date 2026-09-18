*******************************************************************
* GrfDrv256 - Graphics Driver for F256
*******************************************************************
                    nam       GrfDrv256
                    ttl       Wild 256 Graphics Driver

                    use       defsfile
                    use       wildbits_vtio.d


tylg                set       Systm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

                    mod       eom,name,tylg,atrv,entry,size
size                equ       .

name                fcs       /grfdrv256/
                    fcb       edition

*******************************************************************
* Main Entry Point
*
* Entry: B = Function code (from vtio via CallGrfDrv)
*        Other registers = function parameters
*        U = GrfMem pointer ($1100)
*        DP = $11 (set by caller)
*******************************************************************
entry               equ       *
* Set DP to GrfMem area
* CoCo3 version sets this to $11 so that can directly address gr. vars
* However, then you can't access global vars.
*                    pshs      a
*                    lda       #GrfMem/256 ; DP = $11
*                    tfr       a,dp
*                    puls      a
                    tfr       0,dp
                    lda       #EDIT_LUT_1+ACT_LUT_1 Make sure we can edit grfdrv LUT
                    sta       MMU_MEM_CTRL

*Where did this come from, and then where is the stack for GrfDrv?
* Coco GrfDrv does not move stack from D.Flip1, which is set to
* D.CCStk in vtio CallGrfDrv which is supposed to be $2000 and set in krn.asm
*                   lds       >gr.Stack
* Dispatch to function
                    leay      FuncTbl,pcr
                    aslb                ; B*2 for word table
                    jmp       [b,y]


******************************************************************
* WriteChar - outpout character to Live or Shadow Text Map
* THESE ARE DIRECT CALLS  and *NOI* in the function table
*
*	a:   character to output
*	b:   color for map
*	y:   offset in textmap
*
* Writing text is so common, calls are direct for extra speed
* and to reduce overhead.  Being direct, they take their arguments in
* CPU registers and use none of the gr.b*/gr.d* parameter block.
*
*******************************************************************
* Direct calls skip 'entry', so they must select LUT 1 for editing
* themselves - otherwise the stb MMU_SLOT_n below (and the fast-path
* check) hit LUT 0 and corrupt the SYSTEM task's memory map.
WriteCharLive       pshs      cc,d,y
                    orcc      #IntMasks           IRQ return clears EDIT_LUT: select, read and remap masked
                    lda       #EDIT_LUT_1+ACT_LUT_1
                    sta       MMU_MEM_CTRL
                    ldx       MMU_SLOT_1
                    cmpx      #$C2C3
                    beq       mapped@
                    clra
                    ldx       #gr.DATImg+2
                    ldb       #$C2
                    stb       MMU_SLOT_1 $2000
                    std       ,x++
                    ldb       #$C3
                    stb       MMU_SLOT_2 $4000
                    std       ,x++
mapped@             puls      cc,d,y
                    leax      $2000,y
		    sta	      ,x
		    leax      $4000,y
		    stb	      ,x
         	    clrb
                    jmp       >GrfMod+SysRet

WriteCharShadow	    pshs      cc,a,b,y
                    orcc      #IntMasks
                    lda	      #EDIT_LUT_1+ACT_LUT_1   select LUT 1 (direct call skips 'entry')
                    sta	      MMU_MEM_CTRL
                    clra
                    ldx       #gr.DATImg+6
                    ldb       >gr.TermBlk
                    stb       MMU_SLOT_3 $6000
                    std       ,x++
                    incb
                    stb       MMU_SLOT_4 $8000
                    std       ,x++
		    puls      cc,a,b,y
	    	    leax      $6000,y
		    sta	      ,x
		    leax      T.TXTCOLOR,x
		    stb	      ,x	    
         	    clrb
                    jmp       >GrfMod+SysRet

******************************************************************
* ScrollLive/Shadow - Scroll Live or Shadow Text Map
* THESE ARE DIRECT CALLS  and *NOI* in the function table
*
*	a:      width
*	gr.d1:  start offset - first cell of the row that goes away
*	gr.d2:  end offset   - V.ScreenSize (V.WWidth * V.WHeight)
*
* Every row from gr.d1+width up to gr.d2 moves up one row, on both
* planes, and the last row's glyphs are blanked (its colours are not).
* Scroll passes gr.d1 = 0; 1F 31 Delete Line passes CurRow * WWidth.
* B and Y are not inputs.  Count = d2 - d1 - width; gr.d1 must be at
* most the start of the last row, or the count goes negative.
*
* Writing text is so common, calls are direct for extra speed
* and to reduce overhead.  They skip the GF.* dispatch, but they do
* read gr.d1/gr.d2 - vtio calls them only from DoScroll, and both of
* DoScroll's callers load gr.d1 and gr.d2 immediately before.
*
*******************************************************************
ScrollLive          pshs      cc,a
                    orcc      #IntMasks           IRQ return clears EDIT_LUT: select, read and remap masked
                    lda       #EDIT_LUT_1+ACT_LUT_1
                    sta       MMU_MEM_CTRL
                    ldx       MMU_SLOT_1
                    cmpx      #$C2C3
                    beq       mapped@
                    clra
                    ldx       #gr.DATImg+2
                    ldb       #$C2
                    stb       MMU_SLOT_1 $2000
                    std       ,x++
                    ldb       #$C3
                    stb       MMU_SLOT_2 $4000
                    std       ,x++
mapped@             puls      cc,a
                    pshs      a                   ,s = width
                    ldd       >gr.d2              end offset
                    subd      >gr.d1              - start offset
                    subb      ,s                  - one row
                    sbca      #0
                    pshs      d                   ,s = count, 2,s = width
                    ldy       #$2000              text plane
                    bsr       ScrollPlane
                    lda       2,s                 Y = start of last row
                    ldb       #$20
loop@               stb       ,y+                 blank the last row's glyphs
                    deca
                    bne       loop@
                    ldy       #$4000              colour plane
                    bsr       ScrollPlane
                    leas      3,s
                    clrb
                    jmp       >GrfMod+SysRet




ScrollShadow	    pshs      cc,a,b,y
                    orcc      #IntMasks
                    lda	      #EDIT_LUT_1+ACT_LUT_1   select LUT 1 (direct call skips 'entry')
                    sta	      MMU_MEM_CTRL
                    clra
                    ldx       #gr.DATImg+6
                    ldb       >gr.TermBlk
                    stb       MMU_SLOT_3 $6000
                    std       ,x++
                    incb
                    stb       MMU_SLOT_4 $8000
                    std       ,x++
		    puls      cc,a,b,y
                    pshs      a                   ,s = width
                    ldd       >gr.d2              end offset
                    subd      >gr.d1              - start offset
                    subb      ,s                  - one row
                    sbca      #0
                    pshs      d                   ,s = count, 2,s = width
                    ldy       #$6000              text plane
                    bsr       ScrollPlane
                    lda       2,s                 Y = start of last row
                    ldb       #$20
loop@               stb       ,y+                 blank the last row's glyphs
                    deca
                    bne       loop@
                    ldy       #$6000+T.TXTCOLOR   colour plane
                    bsr       ScrollPlane
                    leas      3,s
                    clrb
                    jmp       >GrfMod+SysRet

* ScrollPlane - move one plane up a row, starting at gr.d1.
* Entry: Y = plane base.  2,s = count, 4,s = width (the caller's frame)
* Exit:  Y = base + d1 + count = start of the last row
ScrollPlane         tfr       y,d
                    addd      >gr.d1              dest = base + start
                    tfr       d,y
                    ldb       4,s                 width
                    clra
                    leau      d,y                 source = dest + one row
                    ldd       2,s                 count
                    lbra      CpyBlk              CpyBlk returns to our caller

*******************************************************************
* Function Dispatch Table
*******************************************************************
FuncTbl
                    fdb       GrfMod+Init         ; B=0
                    fdb       GrfMod+Term         ; B=1
                    fdb       GrfMod+StatUnk      ; B=2  was GSMouse (read back)
                    fdb       GrfMod+StatUnk      ; B=3  was GSDScrn (read back)
                    fdb       GrfMod+GSFntChar    ; B=4
                    fdb       GrfMod+SSFntChar    ; B=5
                    fdb       GrfMod+StatUnk      ; B=6  was SSDScrn (no mirror)
                    fdb       GrfMod+PushBuf      ; B=7
                    fdb       GrfMod+PullBuf      ; B=8
		    fdb	      GrfMod+EraseLine	  ; b=9
		    fdb	      GrfMod+ErEOLine	  ; b=10
		    fdb	      GrfMod+ErEOScrn	  ; b=11
		    fdb	      GrfMod+PSGInit	  ; b=12
		    fdb	      GrfMod+PSGBell      ; b=13
		    fdb	      GrfMod+PSGOff	  ; b=14
		    fdb	      GrfMod+GFCell	  ; b=15
		    fdb	      GrfMod+GFClrScrn	  ; b=16
		    fdb	      GrfMod+GFBlank	  ; b=17
		    fdb	      GrfMod+GFPal	  ; b=18
		    fdb	      GrfMod+GFBmEnable	  ; b=19
		    fdb	      GrfMod+GFBmFree	  ; b=20
		    fdb	      GrfMod+GFBmPalet	  ; b=21
                    fdb       GrfMod+GFInsLine    ; b=22
                    fdb       GrfMod+GFSwitch     ; b=23
                    fdb       GrfMod+GFTermGone   ; b=24
                    fdb       GrfMod+GFDfPal      ; b=25
                    fdb       GrfMod+GFAScrn      ; b=26
                    fdb       GrfMod+GFGetStt     ; b=27
                    fdb       GrfMod+GFSetStt     ; b=28
                    fdb       GrfMod+GFInitDisp   ; b=29
                    fdb       GrfMod+GFTermNew    ; b=30


*******************************************************************
* Init - Initialize graphics driver
*******************************************************************
Init
* Initialize F256 graphics hardware
* Setup default screen modes
* Initialize palettes
* etc.

* Example:
*   bsr   InitHardware
*   bsr   SetupDefaultScreen
*                    andcc	#^Carry
		    ldd  #GrfMod+WriteCharLive
                    std  gr.WriteCharLive
  		    ldd  #GrfMod+WriteCharShadow
  		    std  gr.WriteCharShadow
		    ldd	 #GrfMod+ScrollLive
		    std	 gr.ScrollLive
		    ldd  #GrfMod+ScrollShadow
		    std	 gr.ScrollShadow
                    clrb                ; No error
                    lbra      SysRet    ; Return to caller

*******************************************************************
* Term - Terminate graphics driver
*******************************************************************
Term
* Cleanup graphics hardware
* Reset to text mode
* etc.

                    clrb
                    lbra      SysRet


;;; GS.FntChar
;;;
;;; Copy a font character from font bank 0 or 1 to a user memory location
;;;
;;; Entry: R$A = font set 0 or 1
;;;        R$X = pointer to 8 byte memory
;;;        R$Y = font character to get (0-255)
;;;
;;; Exit:  B = non-zero error code
;;;       CC = carry flag clear to indicate success


;;; SS.FntChar
;;;
;;; Set a font character in font bank 0 or 1 from a user memory location
;;;
;;; Entry: R$A = font set 0 or 1
;;;        R$X = pointer to 8 byte memory
;;;        R$Y = font character to set (0-255)
;;;
;;; Exit:  B = non-zero error code
;;;       CC = carry flag clear to indicate success

;;; difference between get and set is just two lines specifying
;;; source and destination.  So procedures are combined.
GSFntChar           lda       #0
                    bra       DoFontGetSet
SSFntChar           lda       #1
DoFontGetSet        pshs      a         store get/set state on stack
                    pshs      cc
                    orcc      #IntMasks
                    lda       #EDIT_LUT_1+ACT_LUT_1
                    sta       MMU_MEM_CTRL
                    lda       #FONT_BLK map in font block
                    sta       MMU_SLOT_2
                    clr       gr.DATImg+4
                    sta       gr.DATImg+5
                    ldx       #gr.PDRGS load x with PDREGS to get shadow stack regs
                    ldx       R$X,x     setfont: source is x
                    ldy       #gr.PDAT
                    lbsr      GMapAddr2Blk
                    lda       #1
                    sta       MMU_MEM_CTRL
*		    ldy	      #$0104
*		    sty	      MMU_SLOT_3
                    ldx       #gr.PDRGS
                    ldd       R$Y,x     get the char# and mulitply by 8
                    lslb                because 8 bytes per character
                    rola
                    lslb
                    rola
                    lslb
                    rola                d now has the font character offset from 0
                    tfr       d,y       transfer result to y
*		    lbra      end@
                    lda       R$A,x     test for font bank 0 or 1
                    beq       font0@    and add appropriate offset
font1@              leay      FONT_1_OFFSET,y add offset for font 1
                    bra       cont@
font0@              leay      FONT_0_OFFSET,y add offset for font 0
cont@               leay      $4000,y
                    pshs      y         push character offset on stack
mapgood@            ldd       R$X,x
                    anda      #%00011111
                    tfr       d,x
                    tst       3,s
                    beq       getfont@
                    puls      y
                    leax      $2000,x   x=process memory
                    bra       contfont@
getfont@            leay      $2000,x
                    puls      x
contfont@           ldb       #4        copy 8 bytes
                    pshs      u
copy@               ldu       ,x++
                    stu       ,y++
                    decb
                    bne       copy@
end@                puls      u         pull blk addr and getset flag
                    puls      cc
                    puls      a
debugend@           jmp       >GrfMod+SysRet

;;; PushBuf
;;; Push Registers to Screen Backup Buffer
;;;
;;; Exit:  Nothing. This just copies values
;;;
PushBuf             lbsr      PushCore
                    jmp       >GrfMod+SysRet
* PushCore - GF.PushBuf's body, also called by GFSwitch.  Exit U = gr.U5.
PushCore            lbsr      SetBlkC2C3
                    pshs      y,u
                    ldy       #$6000+T.TXT copy text from $C2
                    ldu       #$2000
                    ldd       #4800
                    lbsr      CpyBlk
                    ldy       #$6000+T.TXTCOLOR copy color from $C3
                    ldu       #$4000
                    ldd       #4800
                    lbsr      CpyBlk
                    lbsr      SetBlkC0C1
* The four copies below READ Vicky memory back.  Each is gated on its own
* switch so they can be re-enabled one at a time on real hardware - see
* the TermSave* table in defs/wildbits_vtio.d.  SetBlkC0C1 maps $C0 at
* $2000 and $C1 at $4000.
                    ifne      TermSaveTextLUT
                    ldy       #$6000+T.FLUT   text LUT fg+bg, 2 x 64 bytes
                    ldu       #$2000+TEXT_LUT_FG  $C0+$1700, NOT $C1
                    ldd       #128
                    lbsr      CpyBlk
                    endc
                    ifne      TermSaveSprite0
                    ldy       #$6000+T.SPRITE0 sprite bank 0 only
                    ldu       #$2000+SPRITE_REC_OFF  $C0+$1300
                    ldd       #$100           bank 1 at $1400 deliberately not carried
                    lbsr      CpyBlk
                    endc
                    ifne      TermSaveFont0
                    ldy       #$6000+T.FONT0  font memory bank 0
                    ldu       #$4000+FONT_0_OFFSET   $C1+$0000
                    ldd       #$800
                    lbsr      CpyBlk
                    endc
* CLUTs 0-3 are GRPH_LUT0_OFF ($1000) within FONT_BLK ($C1), which
* SetBlkC0C1 maps at $4000 - so $5000, not $2800.  $2800 is $C0+$0800,
* and 4096 bytes from there runs to $C0+$17FF: on Revision E that is
* gamma R, the mouse graphics, the BITMAP and TILE control registers,
* the memtext registers, all four sprite banks and the text LUTs.  A
* push/pull round trip was self-consistent, which is why nothing showed,
* but PullBuf was programming the bitmap and tile registers with
* whatever had been captured.
                    ifne      TermSaveCLUT
                    ldy       #$6000+T.CLUT0  graphics LUT0-3, $400 each
                    ldu       #$4000+GRPH_LUT0_OFF   $C1+$1000
                    ldd       #$1000
                    lbsr      CpyBlk
                    endc
* The 16 main display registers ($FFC0-$FFCF) are NOT read back here any
* more.  V.V_MCR / V.V_LayerCTL / V.BordBack are seeded by vtio's
* GF.InitDisp, inherited by GF.TermNew and updated by every writer
* (SetWin, ChgFont, SSDScrn, SSPScrn), so the mirror is already correct
* and authoritative - while reading a Vicky register back is not
* something the hardware owes us.  PullBuf still programs them from the
* mirror; it is only the capture that is gone.
* The bitmap registers ($C0+$1000) and the tile map / tile set registers
* ($1100 / $1180) are NOT read back here any more either, for the same
* reason $FFC0-$FFCF no longer are.  This block used to capture all three
* bitmaps' control byte and physical address and hand them to PullBuf,
* and on real hardware it came back wrong: a background image loaded on
* /vt1 displayed correctly, survived being switched away from, and came
* back as pure static - PushBuf had overwritten V.BM2Blk with whatever
* reading $3011 produced and PullBuf pointed the display at it.  MAME
* models the whole $C0 page as plain RAM, so the round trip is perfect
* there and the failure never appears.
*
* vtio owns these values now: SS.AScrn and SS.Palet write V.BMxCl_En /
* V.BMxBlk, SS.FScrn clears them, GF.TermNew zeroes the whole
* bitmap+tile mirror for a new terminal, and PullBuf below programs the
* registers from it.  A program that poked $C0+$1000 behind the driver's
* back would no longer have its bitmap carried per terminal - nothing
* does; SS.AScrn is the only way in.
                    puls      y,u
end@                clrb
                    rts

; Take a block number in a (b = 0) and return the high and middle bytes of
; its physical address in d.  Addr2Blk, the inverse, went with PushBuf's
; register capture - nothing reads a bitmap address back any more.
Blk2Addr            lsra
                    rorb
                    lsra
                    rorb
                    lsra
                    rorb
                    rts
;;; Pulluf
;;; Push Registers to Screen Backup Buffer
;;;
;;; Exit:  Nothing. This just copies values
;;;
PullBuf             lbsr      PullCore
                    jmp       >GrfMod+SysRet
* PullCore - GF.PullBuf's body, also called by GFSwitch.  Exit U = gr.U5.
PullCore            lbsr      SetBlkC2C3
                    pshs      y,u
                    ldu       #$6000+T.TXT restore text to $C2
                    ldy       #$2000
                    ldd       #4800
                    lbsr      CpyBlk
                    ldu       #$6000+T.TXTCOLOR restore color to $C3
                    ldy       #$4000
                    ldd       #4800
                    lbsr      CpyBlk
                    lbsr      SetBlkC0C1
* The counterparts of PushBuf's four read-back copies, gated the same
* way.  Whatever is switched off is global state that a switch simply
* leaves alone.  This is the block that blacked the screen on real
* hardware with all four on - it programs whatever PushBuf managed to
* read out of Vicky.
                    ifne      TermSaveTextLUT
                    ldu       #$6000+T.FLUT   text LUT fg+bg
                    ldy       #$2000+TEXT_LUT_FG  $C0+$1700, NOT $C1
                    ldd       #128
                    lbsr      CpyBlk
                    endc
                    ifne      TermSaveSprite0
                    ldu       #$6000+T.SPRITE0 sprite bank 0 only
                    ldy       #$2000+SPRITE_REC_OFF  $C0+$1300
                    ldd       #$100
                    lbsr      CpyBlk
                    endc
                    ifne      TermSaveFont0
                    ldu       #$6000+T.FONT0  font memory bank 0
                    ldy       #$4000+FONT_0_OFFSET   $C1+$0000
                    ldd       #$800
                    lbsr      CpyBlk
                    endc
* Restore is gated separately from PushBuf's capture: with TermSaveCLUT 0
* and TermRestCLUT 1, T.CLUT0-3 is a write-only mirror that vtio's
* SS.DfPal maintains and nothing ever reads out of Vicky.
                    ifne      TermRestCLUT
                    ldu       #$6000+T.CLUT0  graphics LUT0-3
                    ldy       #$4000+GRPH_LUT0_OFF   $C1+$1000, not $2800
                    ldd       #$1000
                    lbsr      CpyBlk
                    endc
* restore display registers
                    ldu       >gr.U5
                    leau      V.V_MCR,u  copy VICKY_MCR Regs, Layer, Backgroun
                    ldy       #$FFC0
                    ldd       #16
                    lbsr      CpyBlk
                    ldu       >gr.U5
                    lda       V.BM0Cl_En,u
                    sta       $3000
                    lda       V.BM0Blk,u
                    clrb
                    lbsr      Blk2Addr
                    std       $3001
                    clr       $3003               address low byte
                    lda       V.BM1Cl_En,u
                    sta       $3008
                    lda       V.BM1Blk,u
                    clrb
                    lbsr      Blk2Addr
                    std       $3009
                    clr       $300B               address low byte
                    lda       V.BM2Cl_En,u
                    sta       $3010
                    lda       V.BM2Blk,u
                    clrb
                    lbsr      Blk2Addr
                    std       $3011
* GFBmEnable is the only other writer of the low byte, and it no longer
* runs for a terminal that sets its bitmap up while it is a shadow, so
* PullBuf has to clear it here.
                    clr       $3013               address low byte
                    ldy       #$3100
                    leau      V.TM0,u   Copy Tile Map Regs
                    ldd       #36
                    lbsr      CpyBlk
                    ldu       >gr.U5
                    leau      V.TS0AddrH,u
                    ldy       #$3180
                    ldd       #32
                    lbsr      CpyBlk
                    puls      y,u
end@                clrb
                    rts


EraseLine	    lbsr      SetBlkC2C3
	            clrb                          start erasing at column 0
                    lda       V.CurRow,u          of the current row
		    bsr       EraseLineCore
                    jmp       >GrfMod+SysRet
* Entry:  A = The row to erase.
*         B = The column to start erasing on.
EraseLineCore       pshs      u
		    pshs      b                   save the start column
                    ldb       V.WWidth,u
                    mul                           get the product
                    addb      ,s                  add the column to start erasing from
                    adca      #0                  consider the carry
                    tfr       d,x                 X = cell offset
                    lda       V.WWidth,u          get the number of columns
                    suba      ,s+                 A = cells to erase
                    tfr       a,b
                    clra
                    tfr       d,y                 Y = fill count
		    cmpy      #0
		    beq       elcexit
                    lda       #C$SPAC		  A=glyph, X=cell offset, Y=count
* b3 is scratch here, not a parameter: U is about to be reused as the
* colour-plane pointer, so V.FBCol has to be spilled somewhere first.
* Callers must not hold a live b3 across GF.EraseLine/ErEOLine/ErEOScrn.
		    ldb	      V.FBCol,u
		    stb	      >gr.b3               spill V.FBCol (colour attr)
                    ldb	      V.TermLive,u
		    beq	      EraseLineShadow
		    leau      $4000,x
		    leax      $2000,x
		    bra	      FillChars
EraseLineShadow	    leau      $6000+T.TXTCOLOR,x
		    leax      $6000,x
FillChars	    ldb	      >gr.b3               recover the colour attr
loop@		    sta	      ,x+
		    stb	      ,u+
		    leay      -1,y
		    bne	      loop@
elcexit		    puls      u
		    rts


ErEOLine	    lbsr      SetBlkC2C3
ErEOLine2           ldd       >V.CurRow,u         get the current row and column
                    bsr       EraseLineCore       go erase from that point to the end of line
                    jmp       >GrfMod+SysRet		    

ErEOScrn	    lbsr      SetBlkC2C3
		    ldd	      >V.CurRow,u
		    bsr	      EraseLineCore
                    lda       V.CurRow,u          get the current row
l@                  clrb                          clear the column
                    inca                          increment row
                    cmpa      V.WHeight,u         are we at the end?
                    bge       ex@                 branch if so
                    pshs      a                   save our row counter
                    bsr       EraseLineCore       go erase the line
                    puls      a                   recover our row counter
                    bra       l@                  go erase more
ex@                 jmp       >GrfMod+SysRet      return		    

*******************************************************************
* GF.InsLine (22) - 1F 30 Insert Line at V.CurRow.
* Rows CurRow..WHeight-2 move down one (the last row is lost), then
* row CurRow is erased to spaces in V.FBCol.  No parameters: reads the
* DSS through U like EraseLine.  vtio clamps V.CurRow below V.WHeight
* and refuses a zero width or height before calling.
*******************************************************************
GFInsLine           lbsr      SetBlkC2C3          U = this terminal's statics
                    lda       V.WHeight,u
                    deca
                    suba      V.CurRow,u          rows to move
                    ldb       V.WWidth,u
                    mul                           D = bytes to move per plane
                    beq       ilblank@            inserting at the last row
                    pshs      d,u                 count, statics
                    ldb       V.WWidth,u
                    clra
                    pshs      d                   ,s = width, 2,s = count, 4,s = statics
                    ldx       V.ScreenSize,u      X = dest end offset
                    tst       V.TermLive,u
                    beq       ilshad@
                    ldd       #$2000              live text plane
                    bsr       InsPlane
                    ldd       #$4000              live colour plane
                    bsr       InsPlane
                    bra       ildone@
ilshad@             ldd       #$6000              shadow text plane
                    bsr       InsPlane
                    ldd       #$6000+T.TXTCOLOR   shadow colour plane
                    bsr       InsPlane
ildone@             leas      4,s                 drop width, count
                    puls      u                   statics back
ilblank@            lda       V.CurRow,u
                    clrb                          from column 0
                    lbsr      EraseLineCore       row CurRow -> spaces, V.FBCol
                    jmp       >GrfMod+SysRet

* InsPlane - move one plane's rows down one row, copying end to start
* (CpyBlk copies upward, which would smear row CurRow down the screen).
* Entry: D = plane base, X = dest end offset (V.ScreenSize)
*        2,s = width, 4,s = count (the caller's frame)
* Preserves X.
InsPlane            pshs      x                   now 4,s = width, 6,s = count
                    leay      d,x                 Y = dest end
                    tfr       y,d
                    subd      4,s                 source end = dest end - one row
                    tfr       d,u
                    ldx       6,s                 count (never 0 - caller checks)
iplp@               lda       ,-u
                    sta       ,-y
                    leax      -1,x
                    bne       iplp@
                    puls      x,pc

*******************************************************************
* GFSwitch - GF.Switch (op 23): change the live terminal.
* Moved here from vtio's SwitchTerm to take it out of the bootfile;
* vtio's AltISR only checks gr.Busy and issues the op.
* gr.SwitchReq: SW.Next / SW.Prev walk the ids to the next T.Init
* entry, SW.Goto (1B 21) takes the id in gr.SwitchTerm.  The request is
* always cleared.  Everything touched is reachable from this map: gr.*
* and D.KbdSta in block 0, the cursor registers in the $FFxx I/O page,
* each terminal's statics through slot 5 (SetBlkC2C3).
* CC is saved and restored: SysRet hands grfdrv's CC back to the caller.
*******************************************************************
GFSwitch            pshs      cc
                    orcc      #IntMasks
                    lda       >gr.SwitchReq
                    lbeq      GSDone
                    lda       >gr.LiveTerm
                    cmpa      #$FF
                    lbeq      GSDone
                    ldb       >gr.SwitchReq
                    cmpb      #SW.Goto
                    beq       GSGoto
                    tfr       a,b
                    lslb
                    lslb
                    lslb                          B = ID * gr.TermSz
                    tst       >gr.SwitchReq
                    bmi       GSPrev
                    bra       GSNext
* SW.Goto: re-check T.Init - the terminal can have closed since DWSelect.
GSGoto              lda       >gr.SwitchTerm
                    cmpa      #G.TermMax
                    lbhs      GSDone
                    cmpa      >gr.LiveTerm
                    lbeq      GSDone
                    tfr       a,b
                    lslb
                    lslb
                    lslb
                    ldx       #gr.TermTbl
                    abx
                    pshs      a
                    lda       T.Flags,x
                    bita      #T.Init
                    puls      a
                    lbeq      GSDone
                    bra       GSFound
GSPrev              deca
                    subb      #gr.TermSz
                    bpl       GSChkPrev
                    lda       #G.TermMax-1
                    ldb       #(G.TermMax-1)*gr.TermSz
GSChkPrev           cmpa      >gr.LiveTerm
                    lbeq      GSDone
                    ldx       #gr.TermTbl
                    abx
                    pshs      a
                    lda       T.Flags,x
                    bita      #T.Init
                    puls      a
                    beq       GSPrev
                    bra       GSFound
GSNext              inca
                    addb      #gr.TermSz
                    cmpa      #G.TermMax
                    blo       GSChkNext
                    clra
                    clrb
GSChkNext           cmpa      >gr.LiveTerm
                    lbeq      GSDone
                    ldx       #gr.TermTbl
                    abx
                    pshs      a
                    lda       T.Flags,x
                    bita      #T.Init
                    puls      a
                    beq       GSNext
* A = new id, B = its table offset.  Save the live terminal first.
GSFound             pshs      d                   0,s = new id, 1,s = new offset
                    ldb       >gr.LiveTerm
                    lslb
                    lslb
                    lslb
                    ldx       #gr.TermTbl
                    abx                           X = old entry
                    lda       T.Flags,x
                    anda      #^T.Live
                    sta       T.Flags,x
                    lbsr      GSTermPtrs
                    lbsr      PushCore            exits U = old statics (slot 5)
                    clr       V.TermLive,u
* SS.WSig: stage "your terminal went background" for vtio's AltISR to send.
* D is already on the stack here, so A and B are scratch.
                    lda       V.WSigID,u
                    beq       wsbg@
                    ldb       V.WSigBg,u
                    beq       wsbg@
                    sta       >gr.SigBgID
                    stb       >gr.SigBgCode
wsbg@               puls      d
                    lbsr      GSEnter             then bring in the new one
GSDone              clr       >gr.SwitchReq
                    puls      cc
                    clrb
                    jmp       >GrfMod+SysRet
*******************************************************************
* GFTermGone - GF.TermGone (op 24): a terminal is closing (vtio TermTerm).
* Entry gr.b1 = its id, gr.d1 = the closing device's static (system
* address).  Nothing happens unless the entry has T.Init AND its T.StatPtr
* is that static: IOMan calls Term after a failed Init or /vt open, and a
* /vt factory static that never bound still has V.TermID 0 - /term's id.
* The flags are read once, THEN cleared - so the AltISR can no longer
* switch to this terminal - and the live decision uses the copy.  If it
* was live, the lowest open id takes over (the cleared entry fails the
* T.Init test, so the search skips it), else no terminal is live.  Then,
* with interrupts back on, the 16K buffer is freed, the rest of the entry
* cleared and gr.TermCnt counted down.
* gr.SwitchReq is left alone: a pending Alt+arrow still runs next tick.
*******************************************************************
GFTermGone          pshs      cc
                    orcc      #IntMasks
                    lda       >gr.b1
                    cmpa      #G.TermMax
                    bhs       GTDone
                    ldb       #gr.TermSz
                    mul
                    ldx       #gr.TermTbl
                    abx                           X = closing entry
                    ldd       T.StatPtr,x
                    cmpd      >gr.d1
                    bne       GTDone              not this static's terminal
                    ldb       T.Flags,x           B = its flags, read once
                    bitb      #T.Init
                    beq       GTDone              not open - nothing to do
                    clr       T.Flags,x           no switch can pick it now
                    pshs      x                   the closing entry, for the free
                    bitb      #T.Live
                    beq       GTFree              was not on screen
                    clra                          A = id, B = offset, from 0
                    clrb
GTFind              ldx       #gr.TermTbl
                    abx
                    pshs      a
                    lda       T.Flags,x
                    bita      #T.Init
                    puls      a
                    beq       GTSkip
                    lbsr      GSEnter
                    bra       GTFree
GTSkip              inca
                    addb      #gr.TermSz
                    cmpa      #G.TermMax
                    blo       GTFind
                    lda       #$FF                none left open
                    sta       >gr.LiveTerm
                    clra
                    clrb
                    std       >D.KbdSta
* Interrupts back on before the os9 call.  The entry has no T.Init, so no
* switch can pick it, and gr.Busy keeps the AltISR out of grfdrv anyway.
GTFree              puls      x
                    puls      cc
                    ldb       T.Block,x
                    beq       GTClear
                    pshs      x
                    clra
                    tfr       d,x                 X = first block of the 16K
                    ldb       #2
                    os9       F$DelRAM
                    puls      x
GTClear             clr       T.Block,x
                    clra
                    clrb
                    std       T.StatPtr,x
                    dec       >gr.TermCnt
                    clrb
                    jmp       >GrfMod+SysRet
GTDone              puls      cc
                    clrb
                    jmp       >GrfMod+SysRet
* GSEnter - make a terminal live: pull its buffer, point the keyboard and
* gr.* at it, put the hardware cursor where it was.  Shared by GFSwitch
* and GFTermGone.  Entry A = id, B = its table offset.  Exit U = its
* statics (slot 5).
GSEnter             pshs      a
                    ldx       #gr.TermTbl
                    abx                           X = new entry
                    lda       T.Flags,x
                    ora       #T.Live
                    sta       T.Flags,x
                    lbsr      GSTermPtrs
* D.KbdSta takes T.StatPtr, the system address - never U, which is this
* map's slot-5 alias (keys go nowhere).
                    ldd       T.StatPtr,x
                    std       >D.KbdSta
                    lbsr      PullCore            exits U = new statics (slot 5)
* Drop any key repeat this terminal was left holding.  Repeat state is per
* terminal but keydrv only services the live one, so a key pressed here
* and released after a switch away never cleared it, and it fired on the
* next switch back.
                    clr       V.LastCh,u
                    lda       #1
                    sta       V.TermLive,u
* SS.WSig: stage "your terminal came forward".  A is about to be pulled
* back off the stack; B is saved because GSCalcPos follows.
                    pshs      b
                    lda       V.WSigID,u
                    beq       wsfg@
                    ldb       V.WSigFg,u
                    beq       wsfg@
                    sta       >gr.SigFgID
                    stb       >gr.SigFgCode
wsfg@               puls      b
                    puls      a
                    sta       >gr.LiveTerm
* Clamp V.CurRow and resync V.CurPos (a DWSet can leave the row past the
* window), then put the hardware cursor there.
                    lbsr      GSCalcPos
                    ldx       #TXT.Base
                    lda       V.CurCol,u
                    sta       VKY_TXT_CURSOR_X_REG_L,x
                    lda       V.CurRow,u
                    sta       VKY_TXT_CURSOR_Y_REG_L,x
                    rts
* GSTermPtrs - vtio's SetTermGrfPtrs: aim gr.TermBlk/VStaStorU/VBlk/U5
* at one terminal.  Entry X = its gr.TermTbl entry.  Clobbers D.
GSTermPtrs          ldb       T.Block,x
                    stb       >gr.TermBlk
                    ldd       T.StatPtr,x
                    std       >gr.VStaStorU
                    lda       T.VBlk,x
                    sta       >gr.VBlk
                    ldd       T.grU5,x
                    std       >gr.U5
                    rts
* GSCalcPos - vtio's CalcCurPos: clamp V.CurRow to V.WHeight-1, then
* V.CurPos = V.CurRow * V.WWidth + V.CurCol.  Entry U = statics.
GSCalcPos           lda       V.WHeight,u
                    beq       GSCPZero            degenerate window - cell 0
                    cmpa      V.CurRow,u
                    bhi       GSCPRow
                    deca
                    sta       V.CurRow,u
GSCPRow             lda       V.CurRow,u
                    ldb       V.WWidth,u
                    mul
                    addb      V.CurCol,u
                    adca      #0
                    std       V.CurPos,u
                    rts
GSCPZero            clra
                    clrb
                    std       V.CurPos,u
                    rts


*******************************************************************
* GF.DfPal (b25) - SS.DfPal for this terminal.  vtio aims gr.TermBlk,
*   gr.VBlk and gr.U5 first and calls through CallGrfDrv, so gr.PDRGS
*   holds the caller's R$X = CLUT # 0-3 and R$Y = 1K of palette data,
*   and gr.PDAT the caller's DAT image.
* The 1K goes to T.CLUTn in the terminal's 16K switch buffer - offset
* $1000+n*$400 of the SECOND block of the pair, the same offsets the
* CLUTs have in $C1 - and, when the terminal is live or has no buffer
* yet, to the live CLUT in $C1.
*   slot 1  the caller's block holding R$Y (source $2000 + R$Y&$1FFF)
*   slot 2  the caller's next block, only when the 1K crosses into it
*   slot 3  $C1              slot 4  second buffer block (SetBlkC2C3)
* Exit: B = 0, or carry + E$IllArg (CLUT # above 3, or the 1K runs off
*   the top of the caller's map).
*******************************************************************
GFDfPal             ldd       >gr.PDRGS+R$X       CLUT #
                    cmpd      #3
                    lbhi      DfPalBad
                    lslb
                    lslb                          B = high byte of n*$400
                    pshs      b
                    lbsr      SetBlkC2C3          U = this terminal's statics
                    lda       V.TermLive,u
                    ldb       V.TermBufBlk,u
                    pshs      d                   ,s = live  1,s = buffer blk  2,s = n*4
                    ldd       >gr.PDRGS+R$Y       source address in the caller
                    anda      #$1F
                    addd      #$2000
                    tfr       d,u                 U = source as seen through slot 1
                    ldb       >gr.PDRGS+R$Y
                    lsrb
                    lsrb
                    lsrb
                    lsrb
                    lsrb                          B = caller slot 0-7
                    lslb
                    ldx       #gr.PDAT+1          low byte of each 2-byte entry
                    abx                           X -> caller's block for that slot
                    pshs      cc
                    orcc      #IntMasks
                    lda       #EDIT_LUT_1+ACT_LUT_1
                    sta       MMU_MEM_CTRL
                    clra
                    ldb       ,x
                    stb       MMU_SLOT_1 $2000
                    std       >gr.DATImg+2
                    cmpu      #$4000-$400         does the 1K end inside slot 1?
                    bls       DfPalMapped
                    cmpx      #gr.PDAT+15         slot 7 has no next block
                    beq       DfPalOff
                    ldb       2,x
                    stb       MMU_SLOT_2 $4000
                    std       >gr.DATImg+4
DfPalMapped         puls      cc
                    tst       1,s
                    beq       DfPalLive           no buffer yet: live CLUT only
                    lda       2,s
                    adda      #$90                $8000 + $1000 + n*$400
                    clrb
                    tfr       d,y
                    pshs      u
                    ldd       #$400
                    lbsr      CpyBlk
                    puls      u
                    tst       ,s                  live?
                    beq       DfPalDone           no - PullBuf programs it on the switch
DfPalLive           pshs      cc
                    orcc      #IntMasks
                    lda       #EDIT_LUT_1+ACT_LUT_1
                    sta       MMU_MEM_CTRL
                    clra
                    ldb       #$C1
                    stb       MMU_SLOT_3 $6000
                    std       >gr.DATImg+6
                    puls      cc
                    lda       2,s
                    adda      #$70                $6000 + $1000 + n*$400
                    clrb
                    tfr       d,y
                    ldd       #$400
                    lbsr      CpyBlk
DfPalDone           leas      3,s
                    clrb
                    jmp       >GrfMod+SysRet
DfPalOff            puls      cc
                    leas      3,s
DfPalBad            comb
                    ldb       #E$IllArg
                    jmp       >GrfMod+SysRet


*******************************************************************
* GF.AScrn (b26) - SS.AScrn for this terminal.  vtio aims gr.TermBlk,
*   gr.VBlk and gr.U5 and calls through CallGrfDrvRet, which copies
*   gr.PDRGS back to the caller's registers afterwards.
*   gr.PDRGS R$Y = bitmap # 0-2, R$X = screen type (0 = 320x240 needs
*   10 blocks, anything else 320x200, 8 blocks).
* Allocates the bitmap with F$AlHRAM, records it in the V.BMxCl_En /
* V.BMxBlk mirror pair PullBuf programs on every switch, and enables it
* now only if this terminal is live - a shadow terminal owns its mirror
* but not the registers.
* Exit: gr.PDRGS R$X = the bitmap's first block, also on E$WADef (the
*   bitmap already has one).  B = 0, or carry + E$IllArg / E$WADef /
*   E$MFull.
*******************************************************************
GFAScrn             ldd       >gr.PDRGS+R$Y       bitmap #
                    cmpd      #2
                    bhi       AScrnBad
                    lbsr      SetBlkC2C3          U = this terminal's statics
                    lslb
                    leax      V.BM0Cl_En,u
                    abx                           X -> V.BMxCl_En, V.BMxBlk at 1,x
                    ldb       1,x
                    beq       AScrnNew
                    clra
                    std       >gr.PDRGS+R$X       return the existing block
                    ldb       #E$WADef
                    bra       AScrnErr
AScrnNew            ldb       >gr.PDRGS+R$X+1     screen type
                    beq       ten@
                    ldb       #8
                    bra       alloc@
ten@                ldb       #10
alloc@              pshs      x
                    os9       F$AlHRAM            D = first block
                    lbsr      SetBlkC2C3          remap slot 5 and reload U (keeps D, X, CC)
                    puls      x
                    bcc       got@
                    ldb       #E$MFull
                    bra       AScrnErr
got@                clra
                    std       >gr.PDRGS+R$X       return the block
                    stb       1,x                 V.BMxBlk
                    lda       #%00000001
                    sta       ,x                  V.BMxCl_En = enable, CLUT 0
                    tst       V.TermLive,u
                    beq       ok@                 shadow: PullBuf programs it on the switch
                    sta       >gr.b3              control byte (enable)
                    lda       >gr.PDRGS+R$Y+1
                    sta       >gr.b2              bitmap #
                    tfr       b,a
                    clrb
                    lbsr      Blk2Addr
                    std       >gr.d1              physical address
                    lbsr      BmEnCore
ok@                 clrb
                    jmp       >GrfMod+SysRet
AScrnBad            ldb       #E$IllArg
AScrnErr            coma
                    jmp       >GrfMod+SysRet


*******************************************************************
* GF.GetStt (b27) / GF.SetStt (b28) - every GetStat and SetStat code
*   vtio does not keep itself.  vtio puts the code in gr.b1, aims
*   gr.TermBlk, gr.VBlk and gr.U5, and calls through CallGrfDrvRet: on
*   entry gr.PDRGS holds the caller's registers, and whatever a handler
*   leaves there is copied back to the caller afterwards.
* Handlers run with U = this terminal's statics (SetBlkC2C3) and
*   X = gr.PDRGS, so R$ offsets read as vtio's did off PD.RGS, and end
*   with B/carry the result and jmp >GrfMod+SysRet.
* An unknown code is carry + E$UnkSvc.  SCF's CallComStatus tolerates
*   exactly that, and tmode/xmode depend on it.
*******************************************************************
GFGetStt            leay      GetSttTbl,pcr
                    bra       StatDisp
GFSetStt            leay      SetSttTbl,pcr
StatDisp            lbsr      SetBlkC2C3          U = this terminal's statics
                    ldx       #gr.PDRGS
                    lda       >gr.b1              status code
sdlp@               tst       ,y                  0 ends the table (SS.Opt is 0)
                    beq       StatUnk
                    cmpa      ,y+
                    beq       sdhit@
                    leay      2,y
                    bra       sdlp@
sdhit@              jmp       [,y]
* StatUnk also fills the retired FuncTbl slots 2, 3 and 6.
StatUnk             comb
                    ldb       #E$UnkSvc
                    jmp       >GrfMod+SysRet

* code, handler
GetSttTbl           fcb       SS.ScSiz
                    fdb       GrfMod+GSScSiz
                    fcb       SS.ScTyp
                    fdb       GrfMod+GSScTyp
                    fcb       SS.KySns
                    fdb       GrfMod+GSKySns
                    fcb       SS.KyLive
                    fdb       GrfMod+GSKyLive
                    fcb       SS.KyDwn
                    fdb       GrfMod+GSKyDwn
                    fcb       SS.Joy
                    fdb       GrfMod+GSJoy
                    fcb       SS.Mouse
                    fdb       GrfMod+GSMouse
                    fcb       SS.DScrn
                    fdb       GrfMod+GSDScrn
                    fcb       SS.FntChar
                    fdb       GrfMod+GSFntChar
                    fcb       SS.Palet
                    fdb       GrfMod+GSFBRgs
                    fcb       SS.FBRgs
                    fdb       GrfMod+GSFBRgs
                    fcb       SS.DfPal
                    fdb       GrfMod+StatOK
                    fcb       SS.BmBlk
                    fdb       GrfMod+GSBmBlk
                    fcb       0
SetSttTbl           fcb       SS.AScrn
                    fdb       GrfMod+GFAScrn
                    fcb       SS.DfPal
                    fdb       GrfMod+GFDfPal
                    fcb       SS.FntChar
                    fdb       GrfMod+SSFntChar
                    fcb       SS.DScrn
                    fdb       GrfMod+SSDScrn
                    fcb       SS.PScrn
                    fdb       GrfMod+SSPScrn
                    fcb       SS.Palet
                    fdb       GrfMod+SSPalet
                    fcb       SS.FScrn
                    fdb       GrfMod+SSFScrn
                    fcb       SS.TermSel
                    fdb       GrfMod+SSTermSel
                    fcb       SS.SprSet
                    fdb       GrfMod+SSSprSet
                    fcb       SS.TsSet
                    fdb       GrfMod+SSTsSet
                    fcb       SS.TmSet
                    fdb       GrfMod+SSTmSet
                    fcb       SS.ClutWrite
                    fdb       GrfMod+SSClutWrite
                    fcb       0

* GetStat SS.ScSiz - R$X = columns, R$Y = rows
GSScSiz             clra
                    ldb       V.WWidth,u
                    std       R$X,x
                    ldb       V.WHeight,u
                    std       R$Y,x
* GetStat SS.DfPal - nothing to return
StatOK              clrb
                    jmp       >GrfMod+SysRet

* GetStat SS.ScTyp - R$A = screen type
GSScTyp             lda       V.ScTyp,u
                    bra       RetA
* GetStat SS.KySns - R$A = key sense bits at the last character read
GSKySns             lda       V.KySns,u
RetA                sta       R$A,x
                    bra       StatOK

* GetStat SS.KyLive - R$A = the key sense bits as the keyboard driver
* holds them now (D.KySns: Shift, Ctrl, Alt, arrows, space), or 0 when
* this terminal is not live.  SS.KySns stays as it is: it is buffered
* with each character, and fm and hexed rely on that.
GSKyLive            clra
                    tst       V.TermLive,u
                    beq       RetA
                    lda       >D.KySns
                    bra       RetA

* GetStat SS.KyDwn - R$X/R$Y/R$U = the six gr.KeyLive slots: the unshifted
* codes of the ordinary keys held down right now, unordered, 0 = an empty
* slot.  All six read 0 when this terminal is not live, as SS.KyLive does.
* Modifiers and the arrows are NOT here - they stay in D.KySns (SS.KyLive).
* Y is free: StatDisp dispatched here with jmp [,y].
GSKyDwn             ldy       #gr.KeyLive
                    tst       V.TermLive,u
                    bne       kdlive@
                    clra                          not live: every slot reads empty
                    clrb
                    std       R$X,x
                    std       R$Y,x
                    std       R$U,x
                    bra       StatOK
kdlive@             ldd       ,y
                    std       R$X,x
                    ldd       2,y
                    std       R$Y,x
                    ldd       4,y
                    std       R$U,x
                    bra       StatOK

* GetStat SS.Palet, SS.FBRgs - R$A = foreground/background, R$X = 0 (border)
GSFBRgs             lda       V.FBCol,u
                    clr       R$X,x
                    clr       R$X+1,x
                    bra       RetA

* GetStat SS.DScrn - R$X = MCR low byte, R$Y = MCR high byte.  From the
* mirror, not the registers: they hold the LIVE terminal's state, which is
* not this caller's on a shadow terminal, and they do not read back.
GSDScrn             clra
                    ldb       V.V_MCR,u
                    std       R$X,x
                    ldb       V.V_MCR+1,u
                    std       R$Y,x
                    bra       StatOK

* GetStat SS.Mouse - R$X/R$Y = position, R$A = buttons
GSMouse             lda       MS_XH
                    ldb       MS_XL
                    std       R$X,x
                    lda       MS_YH
                    ldb       MS_YL
                    std       R$Y,x
                    lda       V.MSButtons,u
                    bra       RetA

* GetStat SS.Joy - R$X = joystick 0 (header 0, VIA0 port B) or 1 (header 1,
* port A).  Exit: R$A = buttons 0-2 in bits 0-2 (1 = pressed), R$X = 0 left,
* 128 centered, 255 right, R$Y = 0 up, 128 centered, 255 down; all three
* always set.  The switches read 0 when closed (F256 manual, chapter 12:
* bit 0 up, 1 down, 2 left, 3 right, 4-6 buttons 0-2).  A terminal that is
* not live reads centered with no buttons.  Joystick above 1: E$IllArg.
GSJoy               ldd       R$X,x               joystick #
                    cmpd      #1
                    bhi       joyerr
                    lda       #$FF                not live: all switches open
                    tst       V.TermLive,u
                    beq       j1@
                    lda       VIA0.Base+VIA_ORB_IRB header 0
                    tstb
                    beq       j1@
                    lda       VIA0.Base+VIA_ORA_IRA header 1
j1@                 coma                          1 = closed
                    ldb       #128                vertical
                    bita      #%00000001
                    beq       j2@
                    clrb                          up
j2@                 bita      #%00000010
                    beq       j3@
                    ldb       #255                down
j3@                 clr       R$Y,x
                    stb       R$Y+1,x
                    ldb       #128                horizontal
                    bita      #%00000100
                    beq       j4@
                    clrb                          left
j4@                 bita      #%00001000
                    beq       j5@
                    ldb       #255                right
j5@                 clr       R$X,x
                    stb       R$X+1,x
                    lsra
                    lsra
                    lsra
                    lsra
                    anda      #%00000111          buttons 0-2
                    lbra      RetA
joyerr              comb
                    ldb       #E$IllArg
                    jmp       >GrfMod+SysRet

* SetStat SS.DScrn - R$X+1 = MCR low byte, R$Y+1 = MCR high byte;
* FX_OMIT/FT_OMIT leave that byte alone.  The mirror always, the register
* only for the live terminal: PullBuf programs $FFC0-$FFCF from V.V_MCR
* when a shadow terminal comes up.
SSDScrn             lda       R$X+1,x
                    ldb       R$Y+1,x
                    ldy       #TXT.Base
                    cmpa      #FX_OMIT
                    beq       hi@
                    sta       V.V_MCR,u
                    tst       V.TermLive,u
                    beq       hi@
                    sta       MASTER_CTRL_REG_L,y
hi@                 cmpb      #FT_OMIT
                    beq       ok@
                    stb       V.V_MCR+1,u
                    tst       V.TermLive,u
                    beq       ok@
                    stb       MASTER_CTRL_REG_H,y
ok@                 lbra      StatOK

* SetStat SS.PScrn - R$X = layer 0-2, R$Y+1 = bitmap # 0-2 or tile map 4-6.
* V.V_LayerCTL is both source and destination: the register never reads
* back, and it holds the live terminal's layers.  Written only when live.
SSPScrn             ldy       R$X,x
                    lda       V.V_LayerCTL,u
                    cmpy      #0
                    bne       l1@
                    anda      #%11110000          layer 0: low nibble
                    adda      R$Y+1,x
                    bra       st0@
l1@                 cmpy      #1
                    bne       l2@
                    anda      #%00001111          layer 1: high nibble
                    pshs      a
                    lda       R$Y+1,x
                    ldb       #16
                    mul
                    addb      ,s+
                    tfr       b,a
st0@                sta       V.V_LayerCTL,u
                    tst       V.TermLive,u
                    beq       ok@
                    sta       VKY_LAYER_CTRL_0
                    bra       ok@
l2@                 cmpy      #2
                    bne       ok@
                    ldb       R$Y+1,x
                    stb       V.V_LayerCTL+1,u
                    tst       V.TermLive,u
                    beq       ok@
                    stb       VKY_LAYER_CTRL_1
ok@                 lbra      StatOK

* SetStat SS.Palet - R$Y = bitmap # 0-2, R$X+1 = CLUT # 0-3.  GF.BmPalet
* rewrites the whole control byte, so the mirror takes the same value or
* the next PullBuf undoes the assignment (and, with the enable bit in that
* byte, turns the bitmap off).
SSPalet             ldd       R$Y,x
                    cmpd      #2
                    bhi       BmBad
                    stb       >gr.b2              bitmap # 0-2
                    lslb                          two mirror bytes per bitmap
                    leay      V.BM0Cl_En,u
                    leay      b,y
                    ldb       R$X+1,x             CLUT #
                    orcc      #Carry
                    rolb                          CLUT# | enable
                    stb       >gr.b3
                    stb       ,y                  V.BMxCl_En
                    tst       V.TermLive,u
                    lbne      GFBmPalet           live: program it now
                    lbra      StatOK
BmBad               comb
                    ldb       #E$IllArg
                    jmp       >GrfMod+SysRet

* SetStat SS.FScrn - R$Y = bitmap # 0-2.  Frees its blocks - 8 with CLK_70
* in V.V_MCR+1, else 10; the mirror, not the register - clears the
* V.BMxCl_En/V.BMxBlk pair, and zeroes the bitmap registers if live.
SSFScrn             ldd       R$Y,x
                    cmpd      #2
                    bhi       BmBad
                    stb       >gr.b2              bitmap # 0-2
                    lslb
                    leay      V.BM0Cl_En,u
                    leay      b,y                 Y -> V.BMxCl_En, V.BMxBlk at 1,y
                    ldb       1,y
                    bne       free@
                    ldb       #E$WUndef           no bitmap allocated
                    coma
                    jmp       >GrfMod+SysRet
free@               clra
                    tfr       d,x                 X = first block
                    lda       V.V_MCR+1,u
                    bita      #CLK_70
                    beq       ten@
                    ldb       #8
                    bra       del@
ten@                ldb       #10
del@                pshs      y
                    os9       F$DelRAM
                    lbsr      SetBlkC2C3          remap slot 5 and reload U
                    puls      y
                    clr       ,y                  both mirror bytes, or PullBuf
                    clr       1,y                 re-enables a freed bitmap
                    tst       V.TermLive,u
                    lbne      GFBmFree            live: zero the registers
                    lbra      StatOK

*******************************************************************
* GF.InitDisp (b29) - display setup for the first terminal, issued by
*   GF.TermNew's first-terminal branch.  (Not the GF.InitDisp deleted
*   earlier for writing the text LUTs to the wrong block; this one
*   touches no LUT.)
* V.V_MCR / V.V_LayerCTL / V.BordBack are the 16-byte mirror of
* $FFC0-$FFCF that PullBuf programs on a terminal switch.  Each DispRegs
* byte goes to the mirror and to its register together, so the two agree
* by construction and nothing has to read a Vicky register back - they
* are not guaranteed readable.  Every writer must keep the mirror in
* step; every reader must use the mirror.  Later terminals inherit the
* mirror from the live console in GF.TermNew.
* Then the text cursor: enabled, flashing, '_' at 0,0.
*******************************************************************
GFInitDisp          lbsr      SetBlkC2C3          U = this terminal's statics
                    leax      DispRegs,pcr
                    leay      V.V_MCR,u
                    ldu       #TXT.Base
                    ldb       #16
seed@               lda       ,x+
                    sta       ,y+                 mirror
                    sta       ,u+                 register
                    decb
                    bne       seed@
                    ldx       #TXT.Base
                    lda       #Vky_Cursor_Enable|Vky_Cursor_Flash_Rate0|Vky_Cursor_Flash_Rate1
                    sta       VKY_TXT_CURSOR_CTRL_REG,x
                    clra
                    clrb
                    std       VKY_TXT_CURSOR_Y_REG_H,x
                    std       VKY_TXT_CURSOR_X_REG_H,x
                    lda       #'_
                    sta       VKY_TXT_CURSOR_CHAR_REG,x
                    clrb
                    jmp       >GrfMod+SysRet

* The 16 bytes of $FFC0-$FFCF, in register order: MASTER_CTRL_REG_L/H,
* VKY_LAYER_CTRL_L/H, BORDER_CTRL_REG, BORDER_COLOR_B/G/R,
* BORDER_X_SIZE, BORDER_Y_SIZE, VKY_RESERVED_02/03/04,
* BACKGROUND_COLOR_B/G/R.  Text mode on, 80x60 (no DBL_X/DBL_Y), no
* layers, border off and sized 0, black background.
DispRegs            fcb       Mstr_Ctrl_Text_Mode_En,$00
                    fcb       $00,$00
                    fcb       $00,$00,$00,$00
                    fcb       $00,$00
                    fcb       $00,$00,$00
                    fcb       $00,$00,$00


*******************************************************************
* GF.TermNew (b30) - set up terminal gr.b1 for the device static at gr.d1
*   (its system address).  Issued by vtio's InitTerm - a named INIZ, or
*   the /vt factory's SS.Open - which has already stored V.TermID.
* The whole setup runs inside the op, so the AltISR (it declines while
* gr.Busy is set) cannot switch in the middle of it, and T.Init is the
* LAST thing written: until then GFSwitch and GFTermGone skip the entry.
* vtio used to set T.Init first, with interrupts on, before T.StatPtr,
* T.VBlk and T.grU5 were stored - an Alt+arrow in that window could make a
* half-built terminal live.
*   1. the id is in range and not open, else E$DevBsy;
*   2. F$AlHRAM the 16K switch buffer (2 blocks);
*   3. the entry: T.Block, T.StatPtr, T.grU5 (the $A0xx alias) and T.VBlk
*      from the system DAT image - D.SysPrc is $0600, so D.SysDAT is in
*      block 0;
*   4. the statics' defaults (what vtio's InitTermStatic did).  IOMan zeroes a new
*      static, so most of the clears are redundant; they are kept to be safe;
*   5. the first terminal (gr.TermCnt 0) goes live and gets GF.InitDisp's
*      body.  A later one inherits from the live terminal (InhRuns), then
*      PushCore puts the live font, sprite bank 0 and CLUTs in its buffer
*      (the TermSave* switches) and the buffer's text is blanked in V.FBCol.
* Log for the MAME dump: $12F5 = V.TermLive, $12F6 = gr.TermCnt,
*   $12F7 = 'K' or 'E', $12F8 = error, $12EC = a later terminal's buffer.
* Exit: B = 0, or carry + E$DevBsy / F$AlHRAM's error.
*******************************************************************
GFTermNew           lda       >gr.b1
                    cmpa      #G.TermMax
                    lbhs      TNBusy
                    ldb       #gr.TermSz
                    mul
                    ldx       #gr.TermTbl
                    abx                           X = this terminal's entry
                    lda       T.Flags,x
                    bita      #T.Init
                    lbne      TNBusy
                    pshs      x
                    ldd       #2
                    os9       F$AlHRAM            D = first block of the 16K buffer
                    puls      x
                    lbcs      TNErr
                    stb       T.Block,x
                    ldd       >gr.d1
                    std       T.StatPtr,x
                    anda      #$1F
                    ora       #$A0
                    std       T.grU5,x            the static through slot 5
                    lda       >gr.d1
                    lsra
                    lsra
                    lsra
                    lsra
                    lsra                          A = system slot (U >> 13)
                    lsla
                    inca                          -> block-number byte of that DAT entry
                    ldy       >D.SysDAT
                    lda       a,y
                    sta       T.VBlk,x            block holding the static
                    lbsr      GSTermPtrs          aim gr.TermBlk/VStaStorU/VBlk/U5 (keeps X)
                    lbsr      SetBlkC2C3          U = the new statics, slots 3/4 = its buffer
                    ldb       T.Block,x
                    stb       V.TermBufBlk,u
* Defaults.  80x60 is also what GF.InitDisp's DispRegs program.
                    clr       V.WriteState,u      escape collector idle
                    ldb       #$10
                    stb       V.FBCol,u
                    ldd       #80*256+60
                    std       V.WWidth,u
                    ldd       #80*60
                    std       V.ScreenSize,u      SetScreenSize's product
* V.CurPos is the cached V.CurRow*V.WWidth+V.CurCol that PutGlyph paints
* at; clearing row/col without it leaves a stale cell offset behind.
                    clr       V.CurRow,u
                    clr       V.CurCol,u
                    clr       V.CurPos,u
                    clr       V.CurPos+1,u
                    clr       V.IBufH,u
                    clr       V.IBufT,u
                    clr       V.LastCh,u
                    clr       V.Reverse,u
                    clr       V.ST,u
* The bitmap / CLUT-block / tile mirror starts "everything off" and is
* never inherited: a new terminal has no bitmaps of its own, and pointing
* it at another terminal's is the bug the mirror exists to prevent.
                    leay      V.BM0Cl_En,u
                    ldb       #V.GCX-V.BM0Cl_En
tnclr@              clr       ,y+
                    decb
                    bne       tnclr@
                    tst       >gr.TermCnt
                    bne       TNInherit
* First terminal: live now, then GF.InitDisp's body seeds and programs the
* $FFC0-$FFCF mirror and the cursor, and returns for us.
                    lda       >gr.b1
                    sta       >gr.LiveTerm
                    lda       #1
                    sta       V.TermLive,u
                    lda       #T.Init+T.Live
                    sta       T.Flags,x
                    inc       >gr.TermCnt
                    lbsr      TNLog
                    lbra      GFInitDisp
* A later terminal matches the live one.  Its statics go in slot 1 (the
* $A0xx alias less $8000) beside the new ones in slot 5; one block in both
* slots is fine.  Interrupts stay masked through the copy, because the
* AltISR's keydrv call writes the live V.KeyDrvStat.
TNInherit           clr       V.TermLive,u
                    pshs      x
                    ldb       >gr.LiveTerm
                    cmpb      #G.TermMax
                    bhs       TNPush              no live terminal to copy from
                    lda       #gr.TermSz
                    mul
                    ldx       #gr.TermTbl
                    abx                           X = the live terminal's entry
                    ldb       T.VBlk,x
                    ldx       T.grU5,x
                    leax      -$8000,x            X = its statics through slot 1
                    pshs      cc
                    orcc      #IntMasks
                    lda       #EDIT_LUT_1+ACT_LUT_1
                    sta       MMU_MEM_CTRL
                    clra
                    stb       MMU_SLOT_1 $2000
                    std       >gr.DATImg+2
                    leay      InhRuns,pcr
inhrun@             ldb       ,y+                 field offset, 0 ends the table
                    beq       inhdone@
                    pshs      x,u
                    abx                           X -> the live field
                    clra
                    leau      d,u                 U -> the new field
                    lda       ,y+                 length
inhcp@              ldb       ,x+
                    stb       ,u+
                    deca
                    bne       inhcp@
                    puls      x,u
                    bra       inhrun@
inhdone@            puls      cc
* PushCore remaps slots 1/2 and exits U = gr.U5.  Its text and colour
* copies into the new buffer are blanked straight after.
TNPush              lbsr      PushCore
                    ldx       ,s
                    ldb       T.Block,x
                    stb       $12EC
                    lda       #C$SPAC             fill glyph
                    ldb       V.FBCol,u           fill colour, as inherited
                    lbsr      BlankCore
                    puls      x
                    lda       #T.Init
                    sta       T.Flags,x           open: switchable from here on
                    inc       >gr.TermCnt
                    bsr       TNLog
                    clrb
                    jmp       >GrfMod+SysRet
TNLog               lda       V.TermLive,u
                    sta       $12F5
                    lda       >gr.TermCnt
                    sta       $12F6
                    lda       #'K
                    sta       $12F7
                    rts
TNBusy              ldb       #E$DevBsy
TNErr               stb       $12F8
                    lda       #'E
                    sta       $12F7
                    coma                          carry: the error in B
                    jmp       >GrfMod+SysRet
* Runs inherited from the live terminal's statics: offset, length.
InhRuns             fcb       V.WWidth,V.MouseVect-V.WWidth   size, V.ScreenSize, colours, keydrv/mouse ptrs
                    fcb       V.KeyDrvStat,8                  keydrv state
                    fcb       V.ST,V.BordBack+12-V.ST         V.ST and the $FFC0-$FFCF mirror
                    fcb       0


*******************************************************************
* GF.PSGInit (b12) - sound hardware setup, once from vtio's Init.
*   Stereo bits in SYS1, the WM8776 CODEC, then silence the PSG at $C4.
*   SYS1 and CODEC.Base are in the fixed $FExx I/O page.
*******************************************************************
* WM8776 CODEC chip registers
* R00 = [0000000][U][Z][AAAAAAA]             Headphone attenuation: U=Update, Z=Zero Crossing Detection, A=bB 1111001 default for 0dB
* R10 = [0001010][XXX][DS][0][0][DF]         DS=DAC input size 16/20/24/32, DF=DAC Format  Right/Left/I2S/DSP
* R12 = [0001100][0][0][DAC][0][ADC]         DAC rate  ADC rate, both are custom 101 in original vtio
* R13 = [0001101][XX][1][XX][H][D][A][C]     Headphones/DAC/ADC/Chip 0=Enabled 1=Muted
* R22 = [0010110][MUX]                       MUX  Bypass,Aux,DAC (bits 2,1,0)
* R23 = Write anything to Reset WM8776

PSGInit             lda       SYS1                get the byte at SYS1
*                    anda      #^SYS_PSG_ST clear the stereo flag
                    ora       #SYS_PSG_ST|SYS_SID_ST
                    sta       SYS1                and save it back
                    ldx       #CODEC.Base

* The two boards wire the WM8776 differently: one independent register sequence per machine,
* never share or copy values.  Bits: [15:9] register, [8] update/zero-cross/LRBOTH, [7:0] value.
* The recipe builds for one machine (PLATFORM=jr2 or k2 -> -Djr2 / -Dk2).
* Tune by ear before touching this table: the wmset command writes any register live,
* usage  wmset R# V#  (both hex, e.g. wmset 0E E7 = R14 to $E7).  A wmset write lasts only
* until the next boot, when this runs again and rewrites every register below.
                    ifne      jr2
* ------------------- Jr2 InitCODEC -------------------
* This is the sequence that is KNOWN GOOD on the Jr2 (bell audible, keyboard fine), with one
* deliberate experiment in it: R21 (below).  History, all on Jr2 hardware 2026-09-18:
*   R21 $03, R22 $07  bell works, keyboard fine, VS1053 silent   <- the baseline restored here
*   R21 $1F, R22 $07  KEYBOARD DEAD, 99999999 until lockup       <- never do this
*   the user's own InitCODEC (R21 $C0 muted, R22 $01 DAC-only, R10 $0A, R11/R12 added,
*                             R13 dropped)  NO BELL, NO SOUND    <- kills the DAC path too,
*     so it is not describing this machine; the suspects there are R10 bit 3 or the missing
*     R13 "power down: everything on".  Do not re-apply it without splitting those apart.
* R Taylor (2026-09-18): on the Jr2 the VS1053 and SAM2695 DO reach the output through the
* codec's AIN analogue inputs (on the K2 they do not).  So the VS1053 needs its AMX bit set
* in R21 and the bypass kept in R22 ($07, MX bit 2).  AIN1+AIN2 are the SAM2695, leaving
* AIN3/AIN4/AIN5 - bits 2/3/4, values $07/$0B/$13 - and at least one of those three is what
* killed the keyboard at $1F, so they are tried ONE AT A TIME.
* NOW TRYING: R21 = $0B, AIN1+AIN2+AIN4.  AIN4 first because it is the K2's VS1053 pin.
* Knobs, tuned by ear 2026-08-29/30: DAC $FD (-1 dB), headphones $60 (-25 dB); this synth
* runs ~12 dB hotter than the K2 one, hence the deep cut.
                    ldd       #%0010111000000000                    R23 - Reset chip
                    lbsr      SendToCODEC
                    ldd       #%0001010000000010                    R10 - DAC Interface Control 16-bit i2s
                    lbsr      SendToCODEC
                    ldd       #%0010001100000001                    R17 - ALC Control 2
                    lbsr      SendToCODEC
                    ldd       #%0010101000001011                    R21 - ADC Mux Control   AIN1+AIN2+AIN4
                    lbsr      SendToCODEC
                    ldd       #%0010110000000111                    R22 - Output Mux MX[2:0] = "111"
                    lbsr      SendToCODEC
                    ldd       #%0001101000000000                    R13 - PWR Down Control, Everything on
                    lbsr      SendToCODEC
                    ldd       #%0000011111111101                    R03 - Left DAC Attenuation ($FD = -1.0dB)
                    lbsr      SendToCODEC
                    ldd       #%0000100111111101                    R04 - Right DAC Attenuation ($FD = -1.0dB)
                    lbsr      SendToCODEC
                    ldd       #%0000000101100000                    R00 - Left Headphone Attenuation ($60 = -25dB)
                    lbsr      SendToCODEC
                    ldd       #%0000001101100000                    R01 - Right Headphone Attenuation ($60 = -25dB)
                    lbsr      SendToCODEC

                    else
* -------------- K2: independently tunable InitCODEC --------------
* Knobs: DAC att R03/R04 = the .mus/SID path only; headphone att R00/R01 = headphone jack
* only; ADC gain R14/R15 ($CF = 0 dB, 0.5 dB/step, $FF = +24 dB) = every analogue input on
* BOTH jacks, because AINs reach VOUT (RCA) and the headphone PGA through the bypass (R22 MX
* bit 2).  Tuned by ear on the headphone jack 2026-09-05: DAC $D7 (-20 dB), headphones $79
* (0 dB); RCA not tuned.
* Analogue inputs (R21 AMX bit n = AIN n+1; extend as sources are identified):
*   AIN1, AIN2  SAM2695 MIDI synth (.lyr)      AIN4  VS1053 (wmset 15 08, 2026-09-07)
*   AIN3, AIN5  not identified yet
* R21 = $1F (all five in), the value the Level 1 deploy overlay codec_inputs writes: this tree
* has no overlay, and without AIN4 the VS1053 is silent.  R21 bit 8 = LRBOTH (R14 then serves
* both channels), bits 7/6 = mutes.
                    ldd       #%0010111000000000                    R23 - Reset chip
                    lbsr      SendToCODEC
                    ldd       #%0001010000000010                    R10 - DAC Interface Control 16-bit i2s
                    lbsr      SendToCODEC
                    ldd       #%0010001100000001                    R17 - ALC Control 2
                    lbsr      SendToCODEC
                    ldd       #%0010101000011111                    R21 - ADC Mux Control   AIN1-AIN5
                    lbsr      SendToCODEC
                    ldd       #%0010110000000111                    R22 - Output Mux MX[2:0] = "111"
                    lbsr      SendToCODEC
                    ldd       #%0001101000000000                    R13 - PWR Down Control, Everything on
                    lbsr      SendToCODEC
                    ldd       #%0000011111010111                    R03 - Left DAC Attenuation ($D7 = -20dB)
                    lbsr      SendToCODEC
                    ldd       #%0000100111010111                    R04 - Right DAC Attenuation ($D7 = -20dB)
                    lbsr      SendToCODEC
                    ldd       #%0000000101111001                    R00 - Left Headphone Attenuation ($79 = 0dB)
                    lbsr      SendToCODEC
                    ldd       #%0000001101111001                    R01 - Right Headphone Attenuation ($79 = 0dB)
                    lbsr      SendToCODEC
                    endc
*                   ldd       #%0001011000000010                    R11 - ADC Interface Control
*                   lbsr      SendToCODEC
*                   ldd       #%0001100111010101                    R12 - Master Mode Control
*                   lbsr      SendToCODEC

                    lbsr      SetBlkC4
                    lda       #%10011111
                    sta       $2000+PSGM.Base
                    lda       #%10111111
                    sta       $2000+PSGM.Base
                    lda       #%11011111
                    sta       $2000+PSGM.Base
                    lda       #%11111111
                    sta       $2000+PSGM.Base
                    jmp       >GrfMod+SysRet

* Send data to CODEC and await its digestion.
*
* Entry: D = Value to send to CODEC.
*        X = Base address of CODEC.
SendToCODEC         pshs      d
w@                  lda       CODECCtrl,x
                    lsra
                    bcs       w@
                    puls      d
                    sta       CODECCmdHi,x
                    stb       CODECCmdLo,x
                    lda       #$01
                    sta       CODECCtrl,x
                    rts


*******************************************************************
* GF.PSGBell (b14) - fire-and-forget tone on the PSG at $C4.
*   b3 = volume 0-15 (inverted below)   d1 = frequency
*******************************************************************
PSGBell		    lbsr      SetBlkC4
		    ldx       #$2000+PSGM.Base
                    lda       #%10111111
                    sta       ,x
                    lda       #%11011111
                    sta       ,x
                    lda       #%11111111
                    sta       ,x
                    lda       >gr.b3              volume 0-15
                    coma
                    anda      #%00001111
                    ora       #%10010000
                    sta       ,x
                    ldd       >gr.d1              frequency
                    coma
                    comb
                    pshs      d
                    andb      #%00001111
                    orb       #%10000000
                    stb       ,x
                    puls      d
                    lsrb
                    lsrb
                    lsrb
                    lsrb
                    lsla
                    lsla
                    lsla
                    lsla
                    anda      #%00110000
                    pshs      a
                    orb       ,s+
                    stb       ,x
                    jmp       >GrfMod+SysRet

PSGOff		    lbsr      SetBlkC4
		    lda       #%10011111
                    sta       $2000+PSGM.Base
                    jmp       >GrfMod+SysRet

*******************************************************************
* GF.Cell (b16) - write one cell.
*   b2 = glyph          b3 = colour attr        d1 = cell offset
*   b4 = WD.Buf (16K terminal buffer) / WD.Vicky (live $C2/$C3)
*******************************************************************
GFCell              lbsr      SetBlkC2C3
                    ldx       >gr.d1              cell offset
                    tst       >gr.b4              live or 16K buffer?
                    beq       GFCellBuf
                    lda       >gr.b2              glyph
                    sta       $2000,x
                    lda       >gr.b3              colour attr
                    sta       $4000,x
                    bra       GWRet
GFCellBuf           lda       >gr.b2              glyph
                    sta       $6000,x            T.TXT origin 0
                    leax      T.TXTCOLOR,x
                    lda       >gr.b3              colour attr
                    sta       $6000,x
GWRet               clrb
                    jmp       >GrfMod+SysRet

*******************************************************************
* GF.ClrScrn (b17) - fill the whole screen with spaces + V.FBCol.
* Dimensions / colour / live-flag read from the DSS (slot 5).
*******************************************************************
GFClrScrn           lbsr      SetBlkC2C3
                    lda       V.WHeight,u
                    beq       GWRet
                    ldb       V.WWidth,u
                    beq       GWRet
                    mul
                    cmpd      #4800
                    bls       GFCSok
                    ldd       #4800
GFCSok              tfr       d,y               Y = cell count
* b3 is scratch here, not a parameter - same spill as EraseLineCore.
                    lda       V.FBCol,u         grab colour before U is reused
                    sta       >gr.b3            spill V.FBCol (colour attr)
                    ldb       V.TermLive,u
                    beq       GFCSbuf
                    ldx       #$2000
                    ldu       #$4000
                    bra       GFCSgo
GFCSbuf             ldx       #$6000
                    ldu       #$6000+T.TXTCOLOR
GFCSgo              lda       #C$SPAC
                    ldb       >gr.b3            recover the colour attr
GFCSlp              sta       ,x+
                    stb       ,u+
                    leay      -1,y
                    bne       GFCSlp
                    jmp       >GrfMod+SysRet

*******************************************************************
* GF.Blank (b18) - blank the 16K terminal buffer.
*   b2 = fill glyph -> T.TXT     b3 = fill colour -> T.TXTCOLOR
*******************************************************************
GFBlank             lbsr      SetBlkC2C3
                    lda       >gr.b2
                    ldb       >gr.b3
                    bsr       BlankCore
                    jmp       >GrfMod+SysRet
* BlankCore - GF.Blank's body, also called by GFTermNew.  A = fill glyph,
* B = fill colour, the buffer mapped at slots 3/4.  Clobbers X and Y.
BlankCore           ldx       #$6000
                    ldy       #4800
GFBlkT              sta       ,x+
                    leay      -1,y
                    bne       GFBlkT
                    ldx       #$6000+T.TXTCOLOR
                    ldy       #4800
GFBlkC              stb       ,x+
                    leay      -1,y
                    bne       GFBlkC
                    rts


*******************************************************************
* GF.Pal (b19) - one 4-byte text-LUT entry.
*   b2 = palette register # (0-15)
*   b4 = WD.Vicky -> live $C1 / WD.Buf -> 16K T.FLUT/T.BLUT
*   b5 = 0 foreground LUT, 1 background LUT
*   d1 = LUT bytes 0-1 (blue, green)   d2 = LUT bytes 2-3 (red, alpha)
*******************************************************************
GFPal               tst       >gr.b4              live $C1 or 16K buffer?
                    beq       GFPalBuf
                    lbsr      SetBlkC0C1
                    ldx       #$2000+TEXT_LUT_FG  $C0, not $C1
                    tst       >gr.b5              0 = FG LUT, 1 = BG LUT
                    beq       GFPalIdx
                    ldx       #$2000+TEXT_LUT_BG  $C0, not $C1
                    bra       GFPalIdx
GFPalBuf            lbsr      SetBlkC2C3
                    ldx       #$6000+T.FLUT
                    tst       >gr.b5              0 = FG LUT, 1 = BG LUT
                    beq       GFPalIdx
                    ldx       #$6000+T.BLUT
GFPalIdx            ldb       >gr.b2              palette register #
                    lslb                          4 bytes per entry
                    lslb
                    abx
                    lda       >gr.d1              blue
                    sta       ,x
                    lda       >gr.d1+1            green
                    sta       1,x
                    lda       >gr.d2              red
                    sta       2,x
                    lda       >gr.d2+1            alpha
                    sta       3,x
                    jmp       >GrfMod+SysRet

*******************************************************************
* GF.BmEnable (b20) / GF.BmFree (b21) / GF.BmPalet (b22)
* Poke the bitmap registers at $3000 + b2*8 on $C0.  b2 = bitmap # (0-2).
*   Enable: b3 = control byte -> ctrl, d1 = phys addr -> 1,x, clr 3,x
*   Free  : zero all four bytes
*   Palet : b3 = CLUT# rolled with the enable bit -> ctrl
*******************************************************************
GFBmEnable          bsr       BmEnCore
                    jmp       >GrfMod+SysRet
* BmEnCore - GF.BmEnable's body, also called by GFAScrn.
BmEnCore            bsr       GFBmX
                    lda       >gr.b3              control byte
                    sta       ,x
                    ldd       >gr.d1              physical address
                    std       1,x
                    clr       3,x
                    rts
GFBmFree            bsr       GFBmX
                    clr       ,x
                    clr       1,x
                    clr       2,x
                    clr       3,x
                    clrb
                    jmp       >GrfMod+SysRet
GFBmPalet           bsr       GFBmX
                    lda       >gr.b3              CLUT# | enable
                    sta       ,x
                    clrb
                    jmp       >GrfMod+SysRet
* GFBmX - map $C0/$C1, return X = $3000 + b2*8 (b2 = bitmap #).
GFBmX               lbsr      SetBlkC0C1
                    ldb       >gr.b2              bitmap # 0-2
                    lda       #8
                    mul
                    addd      #$3000
                    tfr       d,x
                    rts

SetBlkC0C1          pshs      cc
                    orcc      #IntMasks
		    lda	      #EDIT_LUT_1+ACT_LUT_1
		    sta	      MMU_MEM_CTRL
                    clra
                    ldx       #gr.DATImg+2
                    ldb       #$C0
                    stb       MMU_SLOT_1 $2000
                    std       ,x++
                    ldb       #$C1
                    stb       MMU_SLOT_2 $4000
                    std       ,x
                    puls      cc,pc

SetBlkC2C3          pshs      cc,d,x
                    orcc      #IntMasks
		    lda	      #EDIT_LUT_1+ACT_LUT_1
		    sta	      MMU_MEM_CTRL
                    clra
                    ldx       #gr.DATImg+2
                    ldb       #$C2
                    stb       MMU_SLOT_1 $2000
                    std       ,x++
                    ldb       #$C3
                    stb       MMU_SLOT_2 $4000
                    std       ,x++
                    ldb       >gr.TermBlk
                    stb       MMU_SLOT_3 $6000
                    std       ,x++
                    incb
                    stb       MMU_SLOT_4 $8000
                    std       ,x++
                    ldb       >gr.VBlk
                    stb       MMU_SLOT_5 $A000
                    std       ,x
		    ldu	      >gr.U5
                    puls      cc,d,x,pc




SetBlkC4            pshs      cc
                    orcc      #IntMasks
		    lda	      #EDIT_LUT_1+ACT_LUT_1
		    sta	      MMU_MEM_CTRL
                    clra
                    ldx       #gr.DATImg+2
                    ldb       #$C4
                    stb       MMU_SLOT_1 $2000
                    std       ,x
                    puls      cc,pc


* SetStat SS.TermSel - R$X = terminal id 0-8: show that terminal on the
*   AltISR's next tick, as 1B 21 does, without any I/O on the target.  SCF
*   queues a write, SetStat, open or close to a device behind the process
*   that holds it busy while reading (BASIC09 at its prompt does), so vt
*   sends this on its own path.  Not open or out of range = E$IllArg; the
*   live terminal = nothing to do.  Target first, then the request.
SSTermSel           ldd       R$X,x
                    cmpd      #G.TermMax
                    bhs       bad@
                    pshs      b                   the id
                    lda       #gr.TermSz
                    mul
                    ldx       #gr.TermTbl
                    abx                           X = its entry
                    puls      b
                    lda       T.Flags,x
                    bita      #T.Init
                    beq       bad@
                    cmpb      >gr.LiveTerm        already on screen?
                    beq       ok@
                    stb       >gr.SwitchTerm
                    lda       #SW.Goto
                    sta       >gr.SwitchReq
ok@                 clrb
                    jmp       >GrfMod+SysRet
bad@                comb
                    ldb       #E$IllArg
                    jmp       >GrfMod+SysRet

*******************************************************************
* SetStat SS.SprSet - write N sprite records from the caller's buffer.
*   R$X = records, 8 bytes each: CTRL, ADDR hi/mid/lo, X hi/lo, Y hi/lo
*   R$Y = first sprite # 0-127     R$U = N 1-128, first+N <= 128
* Live terminal: the records go to $C0 $1300+8*first, with $C0 in slot 3.
* Background terminal: only the shadowed records 0-31 may be written, into
*   T.SPRITE0 of its switch buffer (slots 3-4), which PullBuf restores on
*   the switch.  A record past 31, or no buffer yet, is E$IllArg with
*   nothing written: only the live terminal writes unshadowed sprites.
*******************************************************************
SSSprSet            ldd       R$Y,x               first sprite #
                    cmpd      #127
                    bhi       SprBad
                    ldd       R$U,x               N
                    beq       SprBad
                    cmpd      #128
                    bhi       SprBad
                    addd      R$Y,x               first + N
                    cmpd      #128
                    bhi       SprBad
                    tst       V.TermLive,u
                    bne       SprLive
                    tst       V.TermBufBlk,u      background: switch buffer only
                    beq       SprBad
                    cmpd      #32                 past the shadowed records 0-31?
                    bhi       SprBad
                    ldd       #$6000+T.SPRITE0    records in the 16K buffer
                    bra       SprCopy
SprLive             pshs      cc
                    orcc      #IntMasks
                    lda       #EDIT_LUT_1+ACT_LUT_1
                    sta       MMU_MEM_CTRL
                    clra
                    ldb       #$C0
                    stb       MMU_SLOT_3          $C0 at $6000
                    std       >gr.DATImg+6
                    puls      cc
                    ldd       #$6000+SPRITE_REC_OFF
SprCopy             pshs      d                   destination base
                    ldd       R$Y,x
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola                          D = 8*first
                    addd      ,s
                    std       ,s                  ,s = destination
                    ldd       R$U,x
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola                          D = 8*N
                    pshs      d                   ,s = length  2,s = destination
                    tfr       d,y                 Y = length
                    ldd       R$X,x               records in the caller's map
                    lbsr      MapCallBuf          U = records through slot 1
                    bcs       SprOff
                    puls      d                   D = length
                    puls      y                   Y = destination
                    lbsr      CpyBlk
                    clrb
                    jmp       >GrfMod+SysRet
SprOff              leas      4,s
SprBad              comb
                    ldb       #E$IllArg
                    jmp       >GrfMod+SysRet

*******************************************************************
* SetStat SS.TsSet - define tile set R$Y (0-7) from the caller's 4-byte
*   record at R$X, in register order: CFG (bit 7 SQUARE), ADDR hi, ADDR mid,
*   ADDR lo.  The V.TSn mirror bytes hold this register order (the
*   AddrH/AddrM/AddrL/SQR field names predate it).
* The mirror (V.TSn and V.TSnBlk = address / $2000) always; the registers
*   at $C0 $1180+4*n only when live.  PullBuf reprograms the tile set
*   registers from the mirror on a switch.
*******************************************************************
SSTsSet             ldd       R$Y,x               tile set #
                    cmpd      #7
                    bhi       TsBad
                    lslb
                    lslb                          B = 4*n
                    pshs      b                   ,s = 4*n
                    ldd       R$X,x
                    ldy       #4
                    lbsr      MapCallBuf          U = record through slot 1
                    bcs       TsOff
                    ldy       >gr.U5              this terminal's statics (slot 5)
                    leay      V.TS0AddrH,y
                    ldb       ,s
                    leay      b,y                 Y -> V.TSnAddrH
                    ldb       #4
loop@               lda       ,u+
                    sta       ,y+
                    decb
                    bne       loop@
                    lda       -3,y                ADDR hi
                    ldb       -2,y                ADDR mid
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola                          A = first block
                    ldy       >gr.U5
                    leay      V.TS0Blk,y
                    ldb       ,s
                    lsrb
                    lsrb                          B = n
                    sta       b,y
                    ldu       >gr.U5
                    tst       V.TermLive,u
                    beq       done@
                    lbsr      SetBlkC0C1          $C0 at $2000
                    ldu       >gr.U5
                    leau      V.TS0AddrH,u
                    ldb       ,s
                    leau      b,u
                    ldy       #$3180
                    leay      b,y
                    ldd       #4
                    lbsr      CpyBlk
done@               leas      1,s
                    clrb
                    jmp       >GrfMod+SysRet
TsOff               leas      1,s
TsBad               comb
                    ldb       #E$IllArg
                    jmp       >GrfMod+SysRet

*******************************************************************
* SetStat SS.TmSet - define tile map R$Y (0-2) from the caller's 12-byte
*   record at R$X, in register order: CTRL (bit 0 enable, bit 4 TILE_SIZE
*   1=8x8), ADDR hi/mid/lo, SIZE_X (2), SIZE_Y (2), X position (2), Y
*   position (2); the 16-bit fields are high byte first.  The V.TMn mirror
*   holds this order (its MapX/RSRV/MapY/RESRV field names predate it).
* The mirror (V.TMn, same order, and V.TMnBlk = address / $2000) always;
*   the registers at $C0 $1100+12*n only when live.  PullBuf reprograms the
*   tile map registers from the mirror on a switch.
*******************************************************************
SSTmSet             ldd       R$Y,x               tile map #
                    cmpd      #2
                    bhi       TmBad
                    pshs      b                   ,s = n
                    ldd       R$X,x
                    ldy       #12
                    lbsr      MapCallBuf          U = record through slot 1
                    bcs       TmOff
                    ldy       >gr.U5              this terminal's statics (slot 5)
                    leay      V.TM0,y
                    lda       #12
                    ldb       ,s
                    mul                           B = 12*n
                    leay      b,y                 Y -> V.TMn
                    ldb       #12
loop@               lda       ,u+
                    sta       ,y+
                    decb
                    bne       loop@
                    lda       -11,y               ADDR hi
                    ldb       -10,y               ADDR mid
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola                          A = first block
                    ldy       >gr.U5
                    leay      V.TM0Blk,y
                    ldb       ,s
                    sta       b,y
                    ldu       >gr.U5
                    tst       V.TermLive,u
                    beq       done@
                    lbsr      SetBlkC0C1          $C0 at $2000
                    lda       #12
                    ldb       ,s
                    mul                           B = 12*n
                    ldu       >gr.U5
                    leau      V.TM0,u
                    leau      b,u
                    ldy       #$3100
                    leay      b,y
                    ldd       #12
                    lbsr      CpyBlk
done@               leas      1,s
                    clrb
                    jmp       >GrfMod+SysRet
TmOff               leas      1,s
TmBad               comb
                    ldb       #E$IllArg
                    jmp       >GrfMod+SysRet

*******************************************************************
* SetStat SS.ClutWrite - write CLUT entries from the caller's buffer.
*   R$X = count x 4 bytes: blue, green, red, alpha
*   R$Y = CLUT # 0-3 (high byte), first entry 0-255 (low byte)
*   R$U = count 1-256, first+count <= 256
* The SS.DfPal targets: T.CLUTn in the terminal's 16K switch buffer
*   (slot 4, which PullBuf restores on a switch) when it has one, and the
*   live CLUT at $C1 $1000+$400*n (in slot 3) when the terminal is live or
*   has no buffer yet.  The entries come in through slots 1-2 (MapCallBuf).
*******************************************************************
SSClutWrite         lda       R$Y,x               CLUT #
                    cmpa      #3
                    lbhi      ClutBad
                    ldd       R$U,x               count
                    lbeq      ClutBad
                    cmpd      #256
                    lbhi      ClutBad
                    addb      R$Y+1,x
                    adca      #0                  D = first + count
                    cmpd      #256
                    lbhi      ClutBad
                    ldd       R$U,x
                    lslb
                    rola
                    lslb
                    rola                          D = 4*count
                    pshs      d                   ,s = length
                    lda       R$Y,x
                    lsla
                    lsla                          A = high byte of n*$400
                    pshs      a
                    clra
                    ldb       R$Y+1,x
                    lslb
                    rola
                    lslb
                    rola                          D = 4*first
                    adda      ,s+                 D = n*$400 + 4*first
                    pshs      d                   ,s = entry offset  2,s = length
                    lda       V.TermLive,u
                    ldb       V.TermBufBlk,u
                    pshs      d                   ,s = live  1,s = buffer blk  2,s = offset  4,s = length
                    ldd       R$X,x               entries in the caller's map
                    ldy       4,s
                    lbsr      MapCallBuf          U = entries through slot 1
                    bcs       ClutOff
                    tst       1,s
                    beq       ClutLive            no buffer yet: live CLUT only
                    ldd       2,s
                    addd      #$6000+T.CLUT0      T.CLUTn entry in the buffer
                    tfr       d,y
                    pshs      u
                    ldd       6,s                 length
                    lbsr      CpyBlk
                    puls      u
                    tst       ,s                  live?
                    beq       ClutDone            no - PullBuf programs it on the switch
ClutLive            pshs      cc
                    orcc      #IntMasks
                    lda       #EDIT_LUT_1+ACT_LUT_1
                    sta       MMU_MEM_CTRL
                    clra
                    ldb       #$C1
                    stb       MMU_SLOT_3          $C1 at $6000
                    std       >gr.DATImg+6
                    puls      cc
                    ldd       2,s
                    addd      #$6000+GRPH_LUT0_OFF
                    tfr       d,y
                    ldd       4,s                 length
                    lbsr      CpyBlk
ClutDone            leas      6,s
                    clrb
                    jmp       >GrfMod+SysRet
ClutOff             leas      6,s
ClutBad             comb
                    ldb       #E$IllArg
                    jmp       >GrfMod+SysRet

*******************************************************************
* GetStat SS.BmBlk - bitmap R$Y (0-2): R$X = first block (0 = not
*   allocated), R$A = control byte (bits 2:1 CLUT, bit 0 enable).
* From the V.BMxCl_En / V.BMxBlk mirror, so it answers for a background
*   terminal too.
*******************************************************************
GSBmBlk             ldd       R$Y,x               bitmap #
                    cmpd      #2
                    lbhi      BmBad
                    lslb                          two mirror bytes per bitmap
                    leay      V.BM0Cl_En,u
                    leay      b,y                 Y -> V.BMxCl_En, V.BMxBlk at 1,y
                    lda       ,y
                    sta       R$A,x
                    clra
                    ldb       1,y
                    std       R$X,x
                    lbra      StatOK


*******************************************************************
* SysRet - Return to System
* Call this instead of jmp [>D.Flip0]
*******************************************************************
SysRet
                    tfr       cc,a      ; Save CC status
                    orcc      #IntMasks ; Disable interrupts
                    ldx       >gr.Stack ; Get saved system stack
                    clr       >gr.Busy  ; Clear busy flag

* Reset DP to 0 for system
                    pshs      a
                    clra
                    tfr       a,dp
                    puls      a

                    jmp       [>D.Flip0] ; Return to system


*******************************************************************
* Helper Routines
*******************************************************************

* Add your F256-specific helper routines here

;;; y=DAT Image Address
;;; x=logical address in process
;;; find the block where x is and map it into Slot 1
GMapAddr2Blk        pshs      cc,d,x    x=address in process;y=Process DAT
                    tfr       x,d
                    lsra
                    lsra
                    lsra
                    lsra
                    anda      #%0001110
                    inca
                    lda       a,y
                    orcc      #IntMasks IRQ return clears EDIT_LUT: select and write masked
                    ldb       #EDIT_LUT_1+ACT_LUT_1
                    stb       MMU_MEM_CTRL
                    sta       MMU_SLOT_1
                    clr       gr.DATImg+2
                    sta       gr.DATImg+3
                    puls      cc,d,x,pc


*******************************************************************
* MapCallBuf - map a caller buffer into slot 1 ($2000), plus the caller's
*   next block into slot 2 ($4000) when the buffer runs into it.  The
*   SS.DfPal mapping, for any length up to $2000.
* Entry: D = buffer address in the caller's map, Y = length (1-$2000)
*        gr.PDAT = the caller's DAT image (vtio's CallGrfDrv)
* Exit:  U = buffer address as seen through slot 1
*        carry set = the buffer runs off the top of the caller's map
*******************************************************************
MapCallBuf          pshs      d,x
                    anda      #$1F
                    addd      #$2000
                    tfr       d,u                 U = buffer through slot 1
                    ldb       ,s                  caller address high byte
                    lsrb
                    lsrb
                    lsrb
                    lsrb
                    lsrb                          B = caller slot 0-7
                    lslb
                    ldx       #gr.PDAT+1          low byte of each 2-byte entry
                    abx                           X -> caller's block for that slot
                    pshs      cc
                    orcc      #IntMasks
                    lda       #EDIT_LUT_1+ACT_LUT_1
                    sta       MMU_MEM_CTRL
                    clra
                    ldb       ,x
                    stb       MMU_SLOT_1          $2000
                    std       >gr.DATImg+2
                    tfr       y,d                 D = length
                    pshs      u
                    addd      ,s++                D = end of buffer + 1
                    cmpd      #$4000
                    bls       mapped@             ends inside slot 1
                    cmpx      #gr.PDAT+15         slot 7 has no next block
                    beq       off@
                    clra
                    ldb       2,x
                    stb       MMU_SLOT_2          $4000
                    std       >gr.DATImg+4
mapped@             puls      cc
                    andcc     #^Carry
                    puls      d,x,pc
off@                puls      cc
                    orcc      #Carry
                    puls      d,x,pc


* This is from L1 Coco vtio
* CpyBlk - Copy contiguous block of memory with a byte value (for screen scrolling, insert/delete line,etc.)
* New, more optimized version (I hope) as of March 12, 2018
* Entry: D=size of copy
*        Y=ptr to destination of copy
*        U=ptr to source of copy (PULU from here on 6809 version)
*  Exit: U=Ptr to end of source copy+1
*        Y=Ptr to end of dest copy+1
*        D=NOTE: NEW CODE WILL HAVE D AS END ADDRESS OF SOURCE OF COPY
CpyBlk              leax      d,u       Calculate source end address
                    pshs      x         Save on stack to compare with so we know when to stop
                    andb      #$03      Check if we have odd bytes leftover (1-3)
                    beq       CpyLpSt   No, skip to check if copy is done, and stack blast 4 byte chunks if yes
CpyLp2              lda       ,u+       (6) Copy extra 1-3 bytes
                    sta       ,y+       (6)
                    decb                (2)
                    bne       CpyLp2    (3)
                    bra       CpyLpSt   Start with cmpu to end of copy (if copy was only 1-3 bytes, we are done already)

* Now, copy all 4 byte chunks. End address remains the same, so we can eliminate some stuff we had before
CpyLp               pulu      d,x       Get 4 bytes from source (ascending order)
                    std       ,y++      Copy to destination
                    stx       ,y++
CpyLpSt             cmpu      ,s        Done 4 byte blast copy?
                    blo       CpyLp     No, keep doing until done
                    puls      pc,d      Get end address of source copy and return


                    emod
eom                 equ       *
                    end
