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
WriteCharLive	    pshs      a
		    lda	      #EDIT_LUT_1+ACT_LUT_1
		    sta	      MMU_MEM_CTRL
		    puls      a
		    ldx	      MMU_SLOT_1
		    cmpx      #$C2C3
		    beq	      goodmmu@
		    pshs      cc,a,b,y
                    orcc      #IntMasks
                    clra
                    ldx       #gr.DATImg+2
                    ldb       #$C2
                    stb       MMU_SLOT_1 $2000
                    std       ,x++
                    ldb       #$C3
                    stb       MMU_SLOT_2 $4000
                    std       ,x++
		    puls      cc,a,b,y
goodmmu@	    leax      $2000,y
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
*	a:   width
*	b:   height
*	y:   screen size in bytes  (V.ScreenSize = V.WWidth * V.WHeight)
*
* Writing text is so common, calls are direct for extra speed
* and to reduce overhead.  Being direct, they take their arguments in
* CPU registers and use none of the gr.b*/gr.d* parameter block.
*
*******************************************************************
ScrollLive	    pshs      a
		    lda	      #EDIT_LUT_1+ACT_LUT_1   select LUT 1 (direct call skips 'entry')
		    sta	      MMU_MEM_CTRL
		    puls      a
		    ldx	      MMU_SLOT_1
		    cmpx      #$C2C3
		    beq	      goodmmu@
		    pshs      cc,a,b,y
                    orcc      #IntMasks
                    clra
                    ldx       #gr.DATImg+2
                    ldb       #$C2
                    stb       MMU_SLOT_1 $2000
                    std       ,x++
                    ldb       #$C3
                    stb       MMU_SLOT_2 $4000
                    std       ,x++
		    puls      cc,a,b,y
goodmmu@	    pshs      d,y
		    ldx	      #$2000
		    leau      a,x	          source is start + 1 row
		    tfr	      y,d	          move size of copy to d
		    subb      ,s		  subtract 1 row from y
		    sbca      #0
		    ldy	      #$2000		  destination is start of screen
		    lbsr      CpyBlk
		    lda	      ,s
		    ldb	      #$20
loop@		    stb	      ,y+
		    deca
		    bne	      loop@
		    ldx	      #$4000
		    lda	      ,s
		    leau      a,x	          source is start + 1 row
		    ldd	      2,s		  move size of copy to d
		    subb      ,s
		    sbca      #0
		    ldy	      #$4000		  destination is start of screen
		    lbsr      CpyBlk
		    puls      d,y
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
		    pshs      d,y
		    ldx       #$6000		
		    leau      a,x		   source is start + 1 row
		    tfr	      y,d		   move size of copy to d
		    subb      ,s
		    sbca      #0
		    ldy	      #$6000		   destination is start of screen
		    lbsr      CpyBlk
		    lda	      ,s
		    ldb	      #$20
loop@		    stb	      ,y+
		    deca
		    bne	      loop@
		    ldy       #$6000+T.TXTCOLOR
		    lda	      ,s
		    leau      a,y		   source is start + 1 row
		    ldd	      2,s		   move size of copy to d
		    subb      ,s
		    sbca      #0
		    lbsr      CpyBlk
		    puls      d,y
         	    clrb
                    jmp       >GrfMod+SysRet

*******************************************************************
* Function Dispatch Table
*******************************************************************
FuncTbl
                    fdb       GrfMod+Init         ; B=0
                    fdb       GrfMod+Term         ; B=1
                    fdb       GrfMod+GSMouse      ; B=2
                    fdb       GrfMod+GSDScrn      ; B=3
                    fdb       GrfMod+GSFntChar    ; B=4
                    fdb       GrfMod+SSFntChar    ; B=5
                    fdb       GrfMod+SSDScrn      ; B=6
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


;;; SS.Mouse
;;;
;;; Returns the mouse information.
;;;
;;; Entry:  B  = SS.Mouse
;;;
;;; Exit:   A = Button state.
;;;         X = Horizontal position (0 - 640).
;;;         Y = Vertical position (0 - 480).
;;;        CC = Carry flag clear to indicate success.
;;;
;;; Error:  B = A non-zero error code.
;;;        CC = Carry flag set to indicate error.
GSMouse             ldx       #gr.PDRGS load x with PDREGS to get shadow stack regs
                    lda       MS_XH
                    ldb       MS_XL
                    std       R$X,x
                    lda       MS_YH
                    ldb       MS_YL
                    std       R$Y,x
*                    lda       V.MSButtons,u
                    clra
                    sta       R$A,x
                    clrb                clear carry
                    jmp       >GrfMod+SysRet


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
*		    lbsr      MMUKrnVars
                    orcc      #IntMasks
                    lda       #%10010001
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
                    stx       $12C0
                    ldx       #gr.PDRGS
                    ldd       R$Y,x     get the char# and mulitply by 8
                    std       $12B0
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
                    stx       $11A0
                    tst       3,s
                    beq       getfont@
                    puls      y
                    leax      $2000,x   x=process memory
                    bra       contfont@
getfont@            leay      $2000,x
                    puls      x
                    stx       $11AC
                    sty       $11AE
contfont@           ldb       #4        copy 8 bytes
                    pshs      u
                    stx       $11B0
                    sty       $11B2
copy@               ldu       ,x++
                    stu       ,y++
                    decb
                    bne       copy@
end@                puls      u         pull blk addr and getset flag
                    puls      cc
                    puls      a
debugend@           jmp       >GrfMod+SysRet

;;;  GS.DScrn
;;;  Get Display Screen Settings
;;;
;;; Return MCR values
;;;
;;; Entry: Nothing.  This returns values only
;;;
;;; Exit:  R$X = Vicky_MCR Low Byte
;;;        R$Y = Vicky_MCR High Byte
;;;
GSDScrn             ldx       #gr.PDRGS
                    clr       R$X,x     load MCR low byte
                    clr       R$Y,x     load MCR high byte
                    ldy       #TXT.Base
mcrlbit@            lda       MASTER_CTRL_REG_L,y store new MCR low byte
                    sta       R$X+1,x   store copy in driver variables
mcrhbit@            ldb       MASTER_CTRL_REG_H,y store new MCR High byte
                    stb       R$Y+1,x   store copy in driver variables
end@                clrb
                    jmp       >GrfMod+SysRet

;;;  SS.DScrn
;;;  Display Screen Settings
;;;
;;; Set MCR to display text or graphics or both
;;;
;;; Entry: R$X = Vicky_MCR Low Byte
;;;        R$Y = Vicky_MCR High Byte
;;;
;;; Exit:  Nothing. This just sets the register and updates driver variables
;;;
SSDScrn             ldx       #gr.PDRGS
                    lda       R$X+1,x   load MCR low byte
                    ldb       R$Y+1,x   load MCR high byte
                    ldy       #TXT.Base
mcrlbit@            cmpa      #FX_OMIT  If omit, don't change
                    beq       mcrhbit@
                    sta       MASTER_CTRL_REG_L,y store new MCR low byte
*                    sta       V.V_MCR,u             store copy in driver variables
mcrhbit@            cmpb      #FT_OMIT  if omit, don't change
                    beq       end@
                    stb       MASTER_CTRL_REG_H,y store new MCR High byte
*                    stb       V.V_MCR+1,u           store copy in driver variables
end@                clrb
                    jmp       >GrfMod+SysRet

;;; PushBuf
;;; Push Registers to Screen Backup Buffer
;;;
;;; Exit:  Nothing. This just copies values
;;;
PushBuf             lbsr      SetBlkC2C3
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
* InitDisplay, inherited by InitTermStatic and updated by every writer
* (SetWin, ChgFont, SSDScrn, SSPScrn), so the mirror is already correct
* and authoritative - while reading a Vicky register back is not
* something the hardware owes us.  PullBuf still programs them from the
* mirror; it is only the capture that is gone.
                    ldu       >gr.U5
                    lda       $3000
                    sta       V.BM0Cl_En,u
                    ldd       $3001
                    lbsr      Addr2Blk
                    sta       V.BM0Blk,u
                    lda       $3008
                    sta       V.BM1Cl_En,u
                    ldd       $3009
                    lbsr      Addr2Blk
                    sta       V.BM1Blk,u
                    lda       $3010
                    sta       V.BM2Cl_En,u
                    ldd       $3011
                    lbsr      Addr2Blk
                    sta       V.BM2Blk,u
                    leay      V.TM0,u   Copy Tile Map Regs
                    ldu       #$3100
                    ldd       #36
                    lbsr      CpyBlk
                    ldu       >gr.U5
                    leay      V.TS0AddrH,u
                    ldu       #$3180
                    ldd       #32
                    lbsr      CpyBlk
                    puls      y,u
end@                clrb
                    jmp       >GrfMod+SysRet

; Take high and middle address byte in d and return block number in a
Addr2Blk            lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    rts

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
PullBuf             lbsr      SetBlkC2C3
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
                    ifne      TermSaveCLUT
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
                    lda       V.BM1Cl_En,u
                    sta       $3008
                    lda       V.BM1Blk,u
                    clrb
                    lbsr      Blk2Addr
                    std       $3009
                    lda       V.BM2Cl_En,u
                    sta       $3010
                    lda       V.BM2Blk,u
                    clrb
                    lbsr      Blk2Addr
                    std       $3011
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
                    jmp       >GrfMod+SysRet


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


PSGInit             lbsr      SetBlkC4
                    lda       #%10011111
                    sta       $2000+PSGM.Base
                    lda       #%10111111
                    sta       $2000+PSGM.Base
                    lda       #%11011111
                    sta       $2000+PSGM.Base
                    lda       #%11111111
                    sta       $2000+PSGM.Base
                    jmp       >GrfMod+SysRet


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
                    ldx       #$6000
                    ldy       #4800
                    lda       >gr.b2
GFBlkT              sta       ,x+
                    leay      -1,y
                    bne       GFBlkT
                    ldx       #$6000+T.TXTCOLOR
                    ldy       #4800
                    lda       >gr.b3
GFBlkC              sta       ,x+
                    leay      -1,y
                    bne       GFBlkC
                    jmp       >GrfMod+SysRet


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
GFBmEnable          bsr       GFBmX
                    lda       >gr.b3              control byte
                    sta       ,x
                    ldd       >gr.d1              physical address
                    std       1,x
                    clr       3,x
                    jmp       >GrfMod+SysRet
GFBmFree            bsr       GFBmX
                    clr       ,x
                    clr       1,x
                    clr       2,x
                    clr       3,x
                    jmp       >GrfMod+SysRet
GFBmPalet           bsr       GFBmX
                    lda       >gr.b3              CLUT# | enable
                    sta       ,x
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
GMapAddr2Blk        pshs      d,x       x=address in process;y=Process DAT
                    tfr       x,d
                    lsra
                    lsra
                    lsra
                    lsra
                    anda      #%0001110
                    inca
                    lda       a,y
		    ldb	      #EDIT_LUT_1+ACT_LUT_1
		    stb	      MMU_MEM_CTRL
                    sta       MMU_SLOT_1
                    clr       gr.DATImg+2
                    sta       gr.DATImg+3
                    puls      x,d,pc

;;; GetXYU - get R$XYU from calling process
;;; Put values into global variable for use in GrfDrv
;;; Caller's variable exist in Path Desciptor table in Task 0
;;; Map in correct block and copy data
GetABXYU


;;; PutABXYU - put R$ABXYU back into calling process
;;;
PutABXYU

MMUKrnVars          lda       #%10010001
                    sta       MMU_MEM_CTRL
                    ldy       #$0104
                    sty       MMU_SLOT_3
                    ldx       >gr.PDRGS load x with PDREGS to get shadow stack regs
                    rts

MMURestore          lda       #1
                    sta       MMU_MEM_CTRL
                    rts

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
