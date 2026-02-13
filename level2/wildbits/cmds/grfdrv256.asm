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

*Where did this come from, and then where is the stack for GrfDrv?
* Coco GrfDrv does not move stack from D.Flip1, which is set to
* D.CCStk in vtio CallGrfDrv which is supposed to be $2000 and set in krn.asm
*                   lds       >GrfMem+gr.Stack
* Dispatch to function
                    leay      FuncTbl,pcr
                    aslb                ; B*2 for word table
                    jmp       [b,y]

*******************************************************************
* Function Dispatch Table
*******************************************************************
FuncTbl
                    fdb       GrfMod+Init $00
                    fdb       GrfMod+Term $02
                    fdb       GrfMod+GSMouse $04
                    fdb       GrfMod+GSDScrn $06
                    fdb       GrfMod+GSFntChar $08
                    fdb       GrfMod+SSFntLoadF $0A
                    fdb       GrfMod+SSFntChar $0C
                    fdb       GrfMod+SSDScrn $0E


* Add more functions as needed

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
                    lda       #$99
                    sta       $1230
                    ldx       >D.Tasks
                    stx       $1232
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
GSMouse             ldx       #GrfMem+gr.PDRGS load x with PDREGS to get shadow stack regs
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
                    clr       GrfMem+gr.DATImg+4
                    sta       GrfMem+gr.DATImg+5
                    ldx       #GrfMem+gr.PDRGS load x with PDREGS to get shadow stack regs
                    ldx       R$X,x     setfont: source is x
                    ldy       #GrfMem+gr.PDAT
                    stx       $1190
                    sty       $1192
                    lbsr      GMapAddr2Blk
                    lda       #1
                    sta       MMU_MEM_CTRL
*		    ldy	      #$0104
*		    sty	      MMU_SLOT_3
                    stx       $12C0
                    ldx       #GrfMem+gr.PDRGS
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

;;; SS.FntLoadF
;;;
;;; Load a font from a file.  File should be full path.
;;; Don't load module into memory, just read directly from file.
;;;
;;; Entry: R$X = pointer to font name
;;;        R$Y = font set 0 or 1
;;;
;;; Exit:  B = non-zero error code
;;;       CC = carry flag clear to indicate success

SSFntLoadF          lbra      quit@
                    ldx       >GrfMem+gr.PDRGS
                    ldy       R$Y,x
                    beq       font0@
font1@              ldy       #$800     FONT_1_OFFSET   $0800
                    bra       storeaddr@
font0@              ldy       #FONT_0_OFFSET $0000
storeaddr@          pshs      y         store font offset on stack [O]
                    leas      -2,s      reserve 2 bytes on stack for mapped addr [MO]
* s= ADDR|OFFSET|
*                   ****      map block into user dat and store address on stack
                    pshs      x,u       preserve x,u
                    ldx       #FONT_BLK map in $C1
                    ldb       #$01      map 1 block at address x (x set on entry)
                    os9       F$MapBlk
                    bcc       mapgood@  if success, then continue
                    puls      x,u       else: error
                    lbra      error@
mapgood@            stu       4,s       store mapped address on stack [XUMO]
                    puls      x,u       restore x,u [MO]
*                   ****      open file to read
endcopy@            ldx       R$X,x     pointer to file name in caller memory
                    lda       #READ.    READ access mode
                    os9       I$Open
                    bcc       modulecheck@
                    bra       errormap@
* Verify that file is module.
* Load file's first two bytes onto the stack to verify and check for $87DC
modulecheck@        leas      -2,s      add space to stack to store 2 bytes [DMO]
                    leax      ,s        load x with stack address
                    lbsr      Rd2B2Mem
                    puls      x         load x with the data [MO]
                    cmpx      #$87CD    check if module
                    bcc       getstart@ if module, get start of data
                    ldb       #3
                    bra       errorclose@ else, error
* Module header byte $09-0A = Execution Offset.
* This is the start of the data in a data module
getstart@           pshs      u         seek to data start address in file [UMO]
                    ldx       #$00      set high byte addr
                    ldu       #$09      set low byte
                    os9       I$Seek
                    bcc       readaddr@ if success, read font
                    puls      u         else error  [MO]
                    ldb       #4
                    bra       errorclose@
* s= u|addr|offset
readaddr@           leas      -2,s      add 2 bytes stack storage [DUMO]
                    leax      ,s        use the 2 bytes in stack to store addr
                    lbsr      Rd2B2Mem  read 2 bytes from file
                    bcc       seekaddr@ if success, seek to data address
                    leas      4,s       else: clean stack and error [MO]
                    bra       errorclose@
* s= addr|u|addr|offset
seekaddr@           puls      u         load u with low byte addr [UMO]
* s= u|addr|offset
                    ldx       #0        load x high byte
                    os9       I$Seek
                    puls      u         restore u [MO]
* s=addr|offset
*                   ldx       ,s                   ldx with mapblock address
                    pshs      a         store path# on stack [AMO]
                    ldd       1,s       put offset in d
                    addd      3,s
                    tfr       d,x
*                   leax      d,x                  add offset to x
                    puls      a         restore path# [MO]
                    ldy       #$800     read 2K of font data into it
                    os9       I$Read    a=path x=addr y=#bytes
errorclose@         pshs      b         [BMO]
                    os9       I$Close   close the file
                    puls      b         [MO]
errormap@           ldu       ,s
                    pshs      b
                    ldb       #$01
                    os9       F$ClrBlk  Clear block from user space
                    puls      b
error@              leas      4,s       clear stack
                    tstb
                    beq       quit@
                    coma
quit@               jmp       >GrfMod+SysRet



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
GSDScrn             ldx       #GrfMem+gr.PDRGS
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
SSDScrn             ldx       #GrfMem+gr.PDRGS
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



*******************************************************************
* SysRet - Return to System
* Call this instead of jmp [>D.Flip0]
*******************************************************************
SysRet
                    tfr       cc,a      ; Save CC status
                    orcc      #IntMasks ; Disable interrupts
                    ldx       >GrfMem+gr.Stack ; Get saved system stack
                    clr       >GrfMem+gr.Busy ; Clear busy flag

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

;;; Rd2B2Mem
;;; Read 2 bytes to addr
;;;
;;; Entry:  A = path #
;;;         X = memory address to read to
;;;
;;; Exit:   B = a non-zero error code (F$MapBlk)
;;;        CC = carry flag clear=success set=error
;;;
;;; I$Read reads data into the current process in D.Proc
;;; To use I$Read for the system, assign system to D.Proc
;;; Call I$Read, then change the processes back
;;; Make sure to mask interrupts so processes don't switch while
;;; the change is happening
;;;
Rd2B2Mem            pshs      cc        push cc and mask interrupts
                    orcc      #IntMasks
                    ldy       <D.Proc   ldy with current process descriptor
                    pshs      y         store current proc descriptor on stack
                    ldy       <D.SysPrc copy system proc descriptor to current
                    sty       <D.Proc
                    ldy       #$02      read 2 bytes from file
                    os9       I$Read
                    puls      y         pull current proc descriptor from stack
                    sty       <D.Proc   and save it back
                    bcs       errnomap@ if I$Read error, then handle error
                    puls      cc,pc     if no error, pull cc and return
errnomap@           puls      cc        if error, pull cc
                    coma                set carry bit
                    rts                 and return

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
                    sta       $1194
                    sty       $1196
                    lda       a,y
                    sta       MMU_SLOT_1
                    clr       GrfMem+gr.DATImg+2
                    sta       GrfMem+gr.DATImg+3
                    sta       $1198
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
                    ldx       >GrfMem+gr.PDRGS load x with PDREGS to get shadow stack regs
                    rts

MMURestore          lda       #1
                    sta       MMU_MEM_CTRL
                    rts



                    emod
eom                 equ       *
                    end
