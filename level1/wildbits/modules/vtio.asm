*******************************************************************
* VTIO - NitrOS-9 video terminal I/O driver for the Wildbits 6809
*
* https://wiki.osdev.org/PS2_Keyboard
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*  1       2013/08/20  Boisy G. Pitre
* Started.
*
*  2       2013/12/-6  Boisy G. Pitre
* Added SS.Joy support.
*
* 3        2025-10-08  John Federico
* Changed behavior of line wrap to not erase line

                    use       defsfile
                    use       wildbits_vtio.d

tylg                set       Drivr+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       2

PSG.Base            equ       PSGM.Base

                    ifeq      Level-2
* For Level 2, we use D.Boot (unused in Wildbits kernel) for keyboard statics
D.KbdSta            equ       D.Boot
                    endc

* We can use a different MMU slot if we want.
                    ifeq     Level-1
* For Level 1, we need to use the high slot -- or else we crash (1-July-2024).                    
MAPSLOT             equ       MMU_SLOT_7
                    else
MAPSLOT             equ       MMU_SLOT_2
                    endc
MAPADDR             equ       (MAPSLOT-MMU_SLOT_0)*$2000
G.ScrStart          equ       MAPADDR

                    mod       eom,name,tylg,atrv,start,size

size                equ       V.Last

                    fcb       UPDAT.+EXEC.

name                fcs       /vtio/
                    fcb       edition

start               lbra      Init
                    lbra      Read
                    lbra      Write
                    lbra      GetStat
                    lbra      SetStat
                    lbra      Term

* Font and palette data are stored in data modules.
* These are the module names.
fontmod             fcs       /font/
palettemod          fcs       /palette/
keydrvmod           fcs       /keydrv/
msdrvmod            fcs       /mousedrv/             mouse driver module
llpath              fcc       "/dd/CMDS/"
llnam               fcs       "grfdrv256"
		    fcb	      $0D


*
* VTIO Alternate IRQ routine - Entered from Clock every 1/60th of a second
*
* The interrupt service routine is responsible for:
*   - handling the K keyboard (if available)
*   - decrementing the tone counter
*   - select the new active window if needed (when that time comes)
*   - updating graphics cursors if needed (when that time comes)
*   - checking for mouse update (when that time comes)

AltISR              
                    ldu       D.KbdSta
* Handle keyboard (if available)
                    ldx       V.KeyDrvEPtr,u
                    cmpx      #$0000
                    ifgt      Level-1
                    beq       HandleMSTimer
                    else
                    beq       HandleSound
                    endc
                    lda       V.LastCh,u                 if LastCh=0, skip keyrepeat handling
                    beq       HandleKeyboard@            
                    dec       V.KRTimer,u                decrement repeat timer
                    bne       HandleKeyboard@            if not 0, then don't repeat yet
                    ldx       V.KeyDrvEPtr,u             
                    jsr       9,x                        else jmp to keyrepeat routine
HandleKeyboard@     ldx       V.KeyDrvEPtr,u                
                    jsr       6,x                        call AltIRQ routine in keydrv
                    ifgt      Level-1
* Handle Mouse Timer. When timer wraps to zero, turn it off
* Mouse does not hide correctly, so park it at right side of screen
* Check if mouse is already off, if it is, then skip timer code
* Mouse timer reset is in mousedrv_ps2.asm interrupt procedure
* Mouse timer resets on every mouse interrupt
* This should hide the mouse after 4 to 5 seconds of inactivity
HandleMSTimer       tst       MS_MEN             check if mouse cursor already off
                    beq       HandleSound        if cursor already off, skip timer code
                    inc       V.MSTimer,u                increment mouse auto-hide timer
                    bne       HandleSound        if it is not zero, then skip
                    clr       MS_MEN             if timer flips to 0, turn off mouse cursor
                    ldd       #640               park mouse at right border
                    sta       MS_XH              turning off cursor doesn't work
                    stb       MS_XL              correctly at the moment
                    endc
* Handle sound.
HandleSound
                    tst       D.TnCnt            get the tone counter
                    beq       ex@                branch if zero
                    dec       D.TnCnt            else decrement the counter
                    bne       ex@                branch not zero; leave the sound on
sndoff              pshs      cc                 save the condition code register
                    orcc      #IntMasks          mask interrupts
                    ldb       MAPSLOT            get the MMU slot we'll map to
                    lda       #$C4               get the sound MMU block
                    sta       MAPSLOT            store it in the MMU slot to map it in
* Turn off PSG channel 0
                    lda       #%10011111         set attenuation for channel 0
                    sta       MAPADDR+PSG.Base
                    stb       MAPSLOT            restore it in the MMU slot
* Wake up process that started sound, if any
                    lda       D.SndPrcID
                    beq       g@                    
                    ldb       #S$Wake
                    os9       F$Send
                    clr       D.SndPrcID
g@                  puls      cc
ex@                 jmp       [D.OrgAlt]         branch to the original alternate IRQ routine


*******************************************************************
* Bell ($07) (called via Bell vector D.Bell):
*
Bell                ldd       #$0F1F              A = start volume (15), B = duration counter
                    ldy       #%0000000100000011              bell frequency

* Common SS.Tone and Bell routine
*
* Entry: A = Volume byte (0-15).
*        B = Cycle repeats (1 means use D.TnCnt as countdown).
*        Y = Frequency.
BellTone            tst       D.SndPrcID
                    bne       exit
                    stb       D.TnCnt             store the duration counter in the global
                    pshs      cc,a
                    lda       #$C4                get the sound MMU block
                    orcc      #IntMasks           mask interrupts
                    ldb       MAPSLOT             get the MMU slot we'll map to
                    sta       MAPSLOT             store it in the MMU slot to map it in
* Turn off attenuation for tones 2, 3, and noise channel.
                    lda       #%10111111          set tone 2 attenuation to 0
                    ldx       #MAPADDR+PSG.Base
                    sta       ,x
                    lda       #%11011111          set tone 3 attenuation to 0
                    sta       ,x
                    lda       #%11111111          set noise attenuation to 0
                    sta       ,x
* Turn on PSG.
                    lda       1,s                 get the volume byte from the stack
                    coma                          complement since attenuation is inverted on the PSG
                    anda      #%00001111          turn off all but attenuation bits for tone 1
                    ora       #%10010000          set latch bit and attenuation control bit for tone 1
                    sta       ,x                  store in PSG hardware

* Set frequency of tone
                    pshs      b                   save original MAP slot value                    
                    tfr       y,d                 transfer frequency over
                    coma
                    comb
                    pshs      d                   only 10 bits are significant
                    andb      #%00001111          clear all but bits 0-3
                    orb       #%10000000          set the latch to 1 for tone 1         
                    stb       ,x                  send it to the hardware
                    puls      d                   obtain the value again
                    lsrb                          shift the...
                    lsrb                          first four...
                    lsrb                          bits out...
                    lsrb                          of the way...
                    lsla                          shift bits...
                    lsla                          9-8...
                    lsla                          up to...
                    lsla                          the upper nibble
                    anda      #%00110000          clear all other bits
                    pshs      a                   save on the stack
                    orb       ,s+                 OR in with bits 7-4
                    stb       ,x
                    puls      b                   get the original MAP slot value
                    stb       MAPSLOT             restore it to the hardware
                    lda       V.BUSY,u            get active process ID
                    sta       D.SndPrcID
                    ldx       #$0000
                    os9       F$Sleep
                    puls      cc
                    clrb
                    puls      a,pc return
exit 
                    rts

*******************************************************************
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

* Initialize the sound hardware.
InitSound           clr       D.SndPrcID          clear the process ID of the current sound emitter (none)
                    lda       SYS1                get the byte at SYS1
*                    anda      #^SYS_PSG_ST clear the stereo flag
                    ora       #SYS_PSG_ST|SYS_SID_ST
                    sta       SYS1                and save it back

InitPSG             pshs      cc                save the condition code register
                    lda       #$C4                get the sound MMU block
                    orcc      #IntMasks           mask interrupts
                    ldb       MAPSLOT             get the MMU slot we'll map to
                    sta       MAPSLOT             store it in the MMU slot to map it in

* Silence the PSG's four channels.
                    lda       #%10011111                            set volume of channel to 0
                    sta       MAPADDR+PSG.Base
                    lda       #%10111111                            set volume of channel to 1
                    sta       MAPADDR+PSG.Base
                    lda       #%11011111                            set volume of channel to 2
                    sta       MAPADDR+PSG.Base
                    lda       #%11111111                            set volume of channel to 3
                    sta       MAPADDR+PSG.Base

                    stb       MAPSLOT            restore it in the MMU slot
                    puls      cc                 restore interrupts

* WM8776 CODEC chip registers
* R00 = [0000000][U][Z][AAAAAAA]             Headphone attenuation: U=Update, Z=Zero Crossing Detection, A=bB 1111001 default for 0dB
* R10 = [0001010][XXX][DS][0][0][DF]         DS=DAC input size 16/20/24/32, DF=DAC Format  Right/Left/I2S/DSP
* R12 = [0001100][0][0][DAC][0][ADC]         DAC rate  ADC rate, both are custom 101 in original vtio
* R13 = [0001101][XX][1][XX][H][D][A][C]     Headphones/DAC/ADC/Chip 0=Enabled 1=Muted
* R22 = [0010110][MUX]                       MUX  Bypass,Aux,DAC (bits 2,1,0)
* R23 = Write anything to Reset WM8776

InitCODEC
                    ldx       #CODEC.Base

                    ldd       #%0010111000000000                    R23 - Reset chip
                    lbsr      SendToCODEC
                    ldd       #%0001010000000010                    R10 - DAC Interface Control 16-bit i2s
                    lbsr      SendToCODEC
                    ldd       #%0010001100000001                    R17 - ALC Control 2 
                    lbsr      SendToCODEC
                    ldd       #%0010101000000011                    R21 - ADC Mux Control   AIN
                    lbsr      SendToCODEC
                    ldd       #%0010110000000111                    R22 - Output Mux MX[2:0] = "111" 
                    lbsr      SendToCODEC
                    ldd       #%0001101000000000                    R13 - PWR Down Control, Everything on
                    lbsr      SendToCODEC
                    ldd       #%0000011111110000                    R03 - Left DAC Attenuation
                    lbsr      SendToCODEC
                    ldd       #%0000100111110000                    R04 - Right DAC Attenuation
                    lbsr      SendToCODEC
                    ldd       #%0000000101101100                    R00 - Left Headphone Attenuation Control
                    lbsr      SendToCODEC
                    ldd       #%0000001101101100                    R01 - Right Headphone Attenuation Control
                    lbsr      SendToCODEC
*                   ldd       #%0001011000000010                    R11 - ADC Interface Control 
*                   lbsr      SendToCODEC
*                   ldd       #%0001100111010101                    R12 - Master Mode Control
*                   lbsr      SendToCODEC

InitBELL            leax      Bell,pcr point to the bell emission code
                    stx       >D.Bell   save it in the system global's bell vector
                    rts
                    
*******************************************************************
* Initialize the display.
* Note: interrupts come in already masked.
InitDisplay         pshs      u                   save important registers
                    lda       MAPSLOT             get the MMU slot we'll map to
                    pshs      a                   save it on the stack

* Put graphics into text mode.
                    ldx       #TXT.Base
                    ldd       #80*256+60
                    std       V.WWidth,u
                    lda       #Mstr_Ctrl_Text_Mode_En enable text mode
                    sta       MASTER_CTRL_REG_L,x
                    clr       MASTER_CTRL_REG_H,x
                    clr       BORDER_CTRL_REG,x
                    clr       BORDER_COLOR_R,x
                    clr       BORDER_COLOR_G,x
                    clr       BORDER_COLOR_B,x
                    clr       VKY_TXT_CURSOR_CTRL_REG,x

* Initialize the gamma.
                    lda       #$C0                get the gamma MMU block
                    sta       MAPSLOT             store it in the MMU slot to map it in
                    ldd       #0                  get the clear value
l@                  tfr       d,x                 transfer it to X
                    stb       MAPADDR,x           store at $0000 off of X
                    stb       MAPADDR+$400,x      store at $0400 off of X
                    stb       MAPADDR+$800,x      store at $0800 off of X
                    incb                          increment the counter
                    bne       l@                  loop until complete

* Initialize the palette.
                    leax      palettemod,pcr      point to the palette module
                    lda       #Data               it's a data module
                    os9       F$Link              link to it
                    bcs       installfont         branch if the link failed
                    pshs      y                   save Y
                    tfr       y,x                 transfer it to X
                    lda       #TEXT_LUT_BLK       load text LUT block
                    sta       MAPSLOT
                    ldy       #MAPADDR
                    leay      TEXT_LUT_FG,y       load Y with the LUT foreground
                    bsr       copypal             copy the palette data for the foreground
                    puls      x                   restore Y into X
                    ldy       #MAPADDR
                    leay      TEXT_LUT_BG,y       load Y with the LUT background
                    bsr       copypal             copy the palette data for the background

* Install the font.
installfont         leax      fontmod,pcr         point to the font module
                    lda       #Data               it's a data module
                    os9       F$Link              link to it
                    bcs       initcursor          branch if the link failed
                    tfr       y,x                 transfer Y to X
                    lda       #$C1                get the font MMU block
                    sta       MAPSLOT             store it in the MMU slot to map it in
                    ldy       #MAPADDR            get the address to write to
l@                  ldd       ,x++                get two bytes of font data
                    std       ,y++                and store it
                    cmpy      #MAPADDR+2048       are we at the end?
                    bne       l@                  branch if not

* Initialize the cursor.
initcursor          ldx       #TXT.Base
                    lda       #Vky_Cursor_Enable|Vky_Cursor_Flash_Rate0|Vky_Cursor_Flash_Rate1
                    sta       VKY_TXT_CURSOR_CTRL_REG,x
                    clra
                    clrb
                    std       VKY_TXT_CURSOR_Y_REG_H,x
                    std       VKY_TXT_CURSOR_X_REG_H,x
                    lda       #'_
                    sta       VKY_TXT_CURSOR_CHAR_REG,x

* Set foreground/background character LUT values.
setforeback         lda       #$C3                get the foreground/background LUT MMU block
                    sta       MAPSLOT             store it in the MMU slot to map it in
                    ldd       #$10*256+$10        load D with the LUT values
                    bsr       clr                 call the clear routine

* Clear text screen.
                    lda       #$C2                get the text MMU block
                    sta       MAPSLOT             store it in the MMU slot to map it in
                    ldd       #$20*256+$20        load D with the space character
                    bsr       clr                 call the clear routine
                    puls      a                   restore the saved map slot value
                    sta       MAPSLOT             and restore the it in the MMU
                    puls      u,pc                restore the registers and return

* Copy palette bytes from X to Y.
copypal             ldu       #64                 use a loop counter of 64 times
l@                  ldd       ,x++                get two bytes from the source
                    std       ,y++                and save it to the destination
                    ldd       ,x++                get two more bytes from the source
                    std       ,y++                and save it to the destination
                    leau      -4,u                subtract 4 from the counter
                    cmpu      #0000               are we done?
                    bne       l@                  branch if not
                    rts                           return

* Clear memory at MAPADDR with the contents of D.
clr                 ldx       #MAPADDR
l@                  std       ,x++
                    cmpx      #MAPADDR+80*60     
                    bne       l@
                    rts

*******************************************************************
* Keyboard initialization  
* NOTE: If we fail to find the 'keydrv' module, carry is returned set, but
* the caller can chose to ignore the error condition.
InitKeyboard        clr       D.KySns
                    clr       V.KySns,u
                    clr       V.IBufH,u
                    clr       V.IBufT,u
                    clr       V.LastCh,u          clear LastCh so no keyrepeat
                    leax      keydrvmod,pcr       point to the keydrv module name
                    lda       #Systm+Objct        it's a system module
                    pshs      u                   save U on the stack
                    os9       F$Link              link to it
                    tfr       u,x                 move the module address to X
                    puls      u                   restore U from the stack
                    bcs       ex@                 branch if the link failed
                    stx       V.KeyDrvMPtr,u      save the module pointer
                    sty       V.KeyDrvEPtr,u      save the entry pointer
                    jsr       ,y                  call the subroutine's Init entry point
                    rts                           return to the caller
ex@                 ldd       #0                  set D to 0
                    std       V.KeyDrvMPtr,u      clear the module pointer
                    std       V.KeyDrvEPtr,u      clear the entry pointer
                    rts                           return to the caller

                    ifgt      Level-1
*******************************************************************
* Mouse initialization  
* NOTE: If we fail to find the 'msdrv' module, carry is returned set, but
* the caller can chose to ignore the error condition.
InitMouse           leax      msdrvmod,pcr        point to the keydrv module name
                    lda       #Systm+Objct        it's a system module
                    pshs      u                   save U on the stack
                    os9       F$Link              link to it
                    tfr       u,x                 move the module address to X
                    puls      u                   restore U from the stack
                    bcs       ex@                 branch if the link failed
                    stx       V.MSDrvMPtr,u       save the module pointer
                    sty       V.MSDrvEPtr,u       save the entry pointer
                    jsr       ,y                  call the subroutine's Init entry point
                    rts                           return to the caller
ex@                 ldd       #0                  set D to 0
                    std       V.MSDrvMPtr,u       clear the module pointer
                    std       V.MSDrvEPtr,u       clear the entry pointer
                    rts                           return to the caller
                    endc


****************************************************************
******             Start GrfDrv Init Routines             ******
****************************************************************

                    ifgt      Level-1
****************************************************************
* Init GrfDrv
* This is a bit complicated.

InitGrfDrv	    pshs      u,y
		    ldd	      >GrfMem+gr.Entry	  check if grfdrv already loaded
		    lbne      InitDevice	  yes, already initialized
* Clear GrfMem area
                    ldx       #GrfMem             point to GrfMem
                    ldy       #256                Size
clrgrf@             clr       ,x+
                    leay      -1,y
                    bne       clrgrf@
		    lda	      #1	          **DEBUG**
		    sta	      $1200               **DEBUG**
* Link GrfDrv Module if in memory
linkgrfdrv          leas      -2,s                buffer for process swap
		    lbsr      tosysproc		  swap to system process
		    lda       #Systm+Objct        ; Module type
                    leax      llnam,pcr           ; "grfdrvf256"
                    os9       F$NMLink            ; Try to link
                    lbsr      toproc              ; Swap back
                    bcc       setupgrfdrv         ; Found it
		    tfr	      b,a
		    sta	      $1201		  **DEBUG**
                    cmpb      #E$MNF              ; Module not found?
                    lbne      initerr             ; Other error
* Load and Link GrfDrv if not linked
loadgrfdrv	    lbsr      tosysproc
                    lda       #Systm+Objct
                    leax      llpath,pcr          ; "/dd/CMDS/grfdrvf256"
                    ldu       <D.Proc
                    os9       F$NMLoad
                    lbsr      toproc
                    lbcs      initerr
		    pshs      a                   **DEBUG**
		    lda	      #2	          **DEBUG** 
		    sta	      $1201               **DEBUG**
		    puls      a                   **DEBUG**

* Setup grfdrv task
setupgrfdrv         leas      2,s	          clean process buffer
                    pshs      a
                    lda       #GrfMem/256
                    tfr       a,dp
                    puls      a
                    ldu       #GrfMem             Point to GRFDRV global mem	            
                    
*******************************************************************
* Build 16-byte DAT image at GrfMem+gr.DATImg
*******************************************************************
                    ldx       #GrfMem+gr.DATImg
		    stx	      $120A
                    
* Slot 0: Block 0 (shared)
                    clra
                    clrb
                    std       ,x++              ; [0, 0]
                    
* Slots 1-5: Free (40KB workspace)
                    ldd       #DAT.Free         ; Use system constant!
                    std       ,x++              ; Slot 1
                    std       ,x++              ; Slot 2
                    std       ,x++              ; Slot 3
                    std       ,x++              ; Slot 4
                    std       ,x++              ; Slot 5


		    
* Get module's blocks
                    pshs      x
                    lda       #Systm+Objct
                    leax      llnam,pcr
                    ldy       >D.SysPrc
                    leay      <P$DATImg,y
                    os9       F$FModul
                    puls      x
                    lbcs      initerr2
                    
                    ldy       MD$MPDAT,u
                    
* Slot 6: GrfDrv code block 1
                    clra                         ; First byte = 0
                    ldd       ,y                ; Physical block
                    std       ,x++
		    std	      $1206
                    
* Slot 7: GrfDrv code block 2 (if >8K)
                    ldd       2,y               ; Second physical block
                    bne       has2
                    ldd       #DAT.Free         ; Use system constant!
                    bra       store7
has2:
                    clra
store7:
		    clra
		    ldb	      #7
                    std       ,x++
		    std	      $1208		*DEBUG*
                    
*******************************************************************
* Register as Task 1
*******************************************************************
                    ldy       >D.TskIPt           ; Task image pointer table
                    ldx       #GrfMem+gr.DATImg   ; Our 8-byte DAT image
                    stx       2,y                 ; Task 1 (offset 2)
                    
*******************************************************************
* Setup stack and get entry point
*******************************************************************
* In the original CoWin, this really should be save to an "end of vars ptr" variable
* not really sure we need this at this point.
                    ldd       #$1CB0              ; Stack at top of workspace
                    std       >GrfMem+gr.Stack

 		    clra
                    tfr       a,dp                Set DP to 0 for Wind/CoGrf, which need it there
                    inc       MD$Link+1,u         ; Increment link count
                    
* Get execution offset
                    ldd       #0
                    ldx       #M$Exec
                    ldy       #GrfMem+gr.DATImg+12
                    os9       F$LDDDXY
		    std	      $1220
                    ora       #$C0
* end of new code
*                    std       GrfMem+gr.Entry   Save it
		    std	       $1114
		    std	      $1210
                    ldx	      #GrfMem+gr.Entry
		    stx	      $1212
*******************************************************************
* Initialize screen table (5 screens)
*******************************************************************
                    ldx       #GrfMem+gr.ScrTbl
                    ldb       #5

clrScr              pshs      b,x
                    ldb       #gr.ScrSz
clrLoop             clr       ,x+
                    decb
                    bne       clrLoop
                    puls      b,x
                    leax      gr.ScrSz,x
                    decb
                    bne       clrScr

*******************************************************************
* Call GrfDrv Init
*******************************************************************
                    ldb       #GF.Init            ; Init function
		    pshs      a                   **DEBUG**
		    lda	      #3	          **DEBUG** 
		    sta	      $1203               **DEBUG**
		    puls      a                   **DEBUG**
		    lbsr      CallGrfDrv
                    lbcs      initerr3
		    pshs      a                   **DEBUG**
		    lda	      #4	          **DEBUG** 
		    sta	      $1204               **DEBUG**
		    puls      a                   **DEBUG**
                    
                    clrb                          ; Success
                    puls      y,u,pc
                    
initerr2            leas      4,s
initerr             leas      2,s
initerr3            pshs      a                   **DEBUG**
		    lda	      #5	          **DEBUG** 
		    sta	      $1205               **DEBUG**
		    puls      a                   **DEBUG**coma
                    puls      y,u,pc		    

*******************************************************************
* Device-Specific Initialization
*******************************************************************
InitDevice
                    ldu       2,s                 ; Device static mem
                    ldy       ,s                  ; Path descriptor
                    
* Initialize device descriptor's static memory
* Store default screen #, mode, etc.
                    
* Example:
*   clr   V.CurScr,u        ; Current screen = 0
*   clr   V.CurMode,u       ; Default mode
                    
                    clrb                          ; No error
                    puls      y,u,pc
                    

*******************************************************************
* Process swap routines (your existing code is fine)
*******************************************************************
tosysproc
                    pshs      d
                    ldd       <D.Proc
                    std       4,s
                    ldd       <D.SysPrc
                    std       <D.Proc
                    puls      d,pc
                    
toproc
                    pshs      d
                    ldd       4,s
                    std       <D.Proc
                    puls      d,pc

*******************************************************************
* CallGrfDrv - Call grfdrv function via task flip
*
* Entry: B = Function code (see GF.* definitions)
*        A = Optional parameter (depends on function)
*        X,Y,U = Function-specific parameters
*
* Exit:  Return values in registers (function-specific)
*        Carry set on error, B = error code
*
* NOTE: ALL registers except SP may be modified by grfdrv
*******************************************************************
CallGrfDrv

* Get grfdrv entry point
                    ldx       >GrfMem+gr.Entry
		    stx	      $1260
		    orcc      #Entire
                    beq       nogrf               ; Not initialized
                    
* Check if already in grfdrv (prevent recursion)
*                   tst       >GrfMem+gr.Busy
*                   bne       gbusy               ; Already busy
		    pshs       d
		    tfr	      cc,a
		    sta	      >GrfMem+Gr.Temp
		    puls      d
		    
*******************************************************************
* Setup for Task Flip
*******************************************************************
                    orcc      #IntMasks               ; Set E bit, disable IRQ
                    
* Save current stack
                    sts        >GrfMem+gr.Stack
* Switch to system call stack
                    lds       <D.CCStk
                    
*******************************************************************
* Build RTI Frame
*
* When D.Flip1 does RTI, it will:
* 1. Restore all registers from stack
* 2. Jump to address in PC slot (we put grfdrv entry there)
* 3. Now running in grfdrv's memory map
*******************************************************************
                    pshs      dp,x,y,u,pc         ; Save registers
                    pshs      cc,d             ; Save CC, A, B
                    
* Overwrite PC with grfdrv entry
                    stx       R$PC,s              ; X has entry address
                    
* Set E bit in stacked CC (tells RTI to restore all regs)
                    lda       >GrfMem+Gr.Temp
		    sta	      R$CC,s

                    
* Mark grfdrv as busy
                    sta       >GrfMem+gr.Busy
                    
*******************************************************************
* Flip to GrfDrv Task and Execute
*******************************************************************
                    jmp       [>D.Flip1]
                    
* <-- Execution continues here after grfdrv calls D.Flip0
* Only SP, PC, and CC are guaranteed preserved
* All other registers may contain return values
 
* Restore caller's CC
                    rts
                    
*******************************************************************
* Error Handlers
*******************************************************************
nogrf               comb                          ; Set carry
                    ldb       #E$UnkSvc           ; Unknown service
                    rts
                    
gbusy               comb
                    ldb       #E$NotRdy           ; Not ready (busy)
                    rts
		    endc


*******************************************************************
* Init              
*
* Entry:
*    Y  = address of device descriptor
*    U  = address of device memory area
*
* Exit:
*    CC = carry set on error
*    B  = error code
*
Init                stu       D.KbdSta
                    leax      DefaultHandler,pcr  get the default character processing routine
                    stx       V.EscVect,u         store it in the vector
                    ldb       #$10                assume this foreground/background
                    stb       V.FBCol,u           store it in our foreground/background color variable
                    clra                          set D..
                    clrb                          to $0000
                    std       V.CurRow,u          set the current row and column
                    
                    lbsr      InitDisplay         initialize the display
                    lbsr      InitSound           initialize the sound
                    lbsr      InitKeyboard        initialize the keyboad
                    ifgt      Level-1
                    lbsr      InitMouse
		    lbsr      InitGrfDrv
                    endc

                    ldx       >D.AltIRQ           get the current alternate IRQ vector
                    stx       >D.OrgAlt           save it off in the original vector
                    leax      AltISR,pcr          get our alternate interrupt service routine
                    stx       >D.AltIRQ           and place it in the global vector

                    clrb                          clear the carry and error code
                    rts                           return to the caller

*******************************************************************
* Term
*
* Entry:
*    U  = address of device memory area
*
* Exit:
*    CC = carry set on error
*    B  = error code
*
Term                ldx       >D.OrgAlt   get the original alternate IRQ vector
                    stx       <D.AltIRQ           save it back to the D.AltIRQ address              
                    ldx       V.KeyDrvEPtr,u
                    cmpx      #0000
                    beq       ex@
                    jsr       3,x               call Term entry point
                    ldd       #0
                    std       V.KeyDrvEPtr,u          and zero out the vector
                    pshs      u
                    ldu       V.KeyDrvMPtr,u
                    os9       F$Unlink
                    puls      u
                    ifgt      Level-1
                    std       V.MSDrvMPtr,u
                    ldd       #0
                    std       V.MSDrvEPtr,u          and zero out the vector
                    pshs      u
                    ldu       V.MSDrvMPtr,u
                    os9       F$Unlink
                    puls      u                    
                    std       V.MSDrvMPtr,u
                    endc
ex@                 clrb                          clear the carry
                    rts                           return to the caller

*******************************************************************
* Read
*
* Entry:
*    Y  = address of path descriptor
*    U  = address of device memory area
*
* Exit:
*    A  = character read
*    CC = carry set on error
*    B  = error code
*
Read
* Check to see if there is a signal-on-data-ready set for this path.
* If so, we return E$NotRdy.
read1               lda       <V.SSigID,u         data ready signal trap set up?
                    lbne      NotReady            yes, exit with not ready error
                    leax      V.InBuf,u           point X to the input buffer
                    ldb       V.IBufT,u           get the buffer tail pointer
                    orcc      #IRQMask            mask interrupts
                    cmpb      V.IBufH,u           is the tail pointer the same as the head pointer?
                    beq       nitenite@           if so, the buffer is empty, so put the reader to sleep
                    abx                           X now points to the current character to fetch from the buffer
                    lda       ,x                  get that character now
                    pshs      a,x                 store character
                    leax      V.KSBuf,u           update V.KySns
                    abx
                    lda       ,x
                    sta       V.KySns,u
                    puls      a,x
                    bsr       IncNCheck           check for tail wrap
                    stb       V.IBufT,u           store the updated tail
                    andcc     #^(IRQMask+Carry)   unmask interrupts
                    rts                           and return to the caller
* Here, the calling process gets put to sleep waiting for input.
nitenite@           lda       V.BUSY,u            get the calling process ID
                    sta       V.WAKE,u            store it in V.WAKE
                    andcc     #^IRQMask           clear interrupts
                    ldx       #$0000              we want to..
                    os9       F$Sleep             sleep forever (until we get a wakup signal)
                    clr       V.WAKE,u            we're awake... clear our process ID
                    ldx       <D.Proc             get the current process descriptor
                    ldb       <P$Signal,x         and the signal we received
                    beq       Read                branch if there was no signal
                    cmpb      #S$Window           was it the window signal?
                    bcc       Read                branch if that, or higher
                    coma                          set the carry
                    rts                           and return to the caller

* Check if we need to wrap around tail pointer to zero.
IncNCheck           incb                          increment the next character pointer
                    cmpb      #KBufSz-1           are we pointing to the end of the buffer?
                    bls       ex@                 branch if not
                    clrb                          else clear the pointer (wraps to head)
ex@                 rts                           return


*******************************************************************
* Write
*
* Entry:
*    A  = character to write
*    Y  = address of path descriptor
*    U  = address of device memory area
*
* Exit:
*    CC = carry set on error
*    B  = error code
*
Write
                    ldx       V.EscVect,u         get the escape vector address
                    jsr       ,x                  branch to it
                    pshs      d                   save D since we modify it here
                    lda       V.CurCol,u          get the current row in A
                    ldx       #TXT.Base
                    sta       VKY_TXT_CURSOR_X_REG_L,x
                    lda       V.CurRow,u          get the current row in A
                    sta       VKY_TXT_CURSOR_Y_REG_L,x
                    ldb       V.WWidth,u          and the current column in B
                    mul                           get the product
                    addb      V.CurCol,u          add it to the current column
                    adca      #0                  add in the carry in A
                    ldx       #G.ScrStart         point to the start of the screen
                    leax      d,x                 point X to the current position
                    puls      d,pc                restore register and return

DefaultHandler      cmpa      #C$SPAC             is the character a space or greater?
                    lbcs      ChkESC              branch if not; go check for escape codes
RawWrite            pshs      a                   else save the character to write
                    lda       V.CurRow,u          get the current row
                    ldb       V.WWidth,u          and the number of columns
                    mul                           calculate the row we should be on
                    addb      V.CurCol,u          add in the column
                    adca      #0                  and add in 0 with carry in case of overflow
* Here, D has the location in the screen where the next character goes.
                    ldx       #G.ScrStart         get the start of the screen in X
                    leax      d,x                 advance X to where the next character goes
                    puls      a                   get the character to write
                    pshs      cc                  save CC
                    orcc      #IntMasks           mask interrupts
                    ldb       MAPSLOT             get the MMU block number for the slot
                    pshs      b                   save it
                    ldb       #$C2                get the text MMU block number
                    stb       MAPSLOT             set the block number to text
                    sta       ,x                  save the character there
                    ldb       #$C3                get the text attributes MMU block number
                    stb       MAPSLOT             set the MMU block number to the text attributes block
                    lda       V.FBCol,u           get the current foreground/background color
                    sta       ,x                  save it at the same location in the text attributes
                    lda       ,s+                 recover the initial MMU slot value
                    sta       MAPSLOT             and restore it
                    puls      cc                  recover CC (this may unmask interrupts)
                    ldd       V.CurRow,u          get the current row and column
                    incb                          increment the column
                    cmpb      V.WWidth,u          compare it against the number of columns
                    blt       ok                  branch if we're less than
                    clrb                          else the column goes to 0
incrow              inca                          and we increment the row
                    cmpa      V.WHeight,u         compare it against the number of rows
                    blt       ok                  branch if we're less than (don't clear the new line we're on)
SCROLL              equ       1
                    ifne      SCROLL
                    deca                          set A to V.WHeight - 1
                    ldx       #G.ScrStart         get the start of the screen memory
                    pshs      d                   save D
                    ldd       V.WWidth,u          get screen width in A and height in B
                    decb                          decrement height by 1
                    mul                           get the product (bytes to copy)
                    tfr       d,y                 set Y to the size of the screen minus the last row
                    puls      d                   restore D
                    pshs      cc,d                save off the row/column and CC
                    orcc      #IntMasks           mask interrupts
                    lda       MAPSLOT             get the current MMU slot
                    pshs      a                   save it on the stack
scroll_loop1@       lda       #$C2                get the text block #
                    sta       MAPSLOT             and map it in
                    ldb       V.WWidth,u
                    ldd       b,x
                    std       ,x                  store on this row
                    lda       #$C3                get the text attributes block #
                    sta       MAPSLOT             and map it in
                    ldb       V.WWidth,u          get the bytes at the width
                    ldd       b,x
                    std       ,x++                and store it
                    leay      -2,y                decrement Y
                    bne       scroll_loop1@       branch if not 0
                    puls      a                   recover the original slot
                    sta       MAPSLOT             and restore it
                    puls      cc,d                recover CC and the row/column
                    else
                    clra                          just clear the row (goes to top)
                    endc
* clear line
clrline             std       V.CurRow,u          save the current row/column value
                    lbsr      EraseLine           erase the line
                    rts                           and return to the caller
ok                  std       V.CurRow,u          save the current row/column value
ret                 rts                           and return to the caller

;;; CurOn
;;;
;;; Turns the cursor on.
;;;
;;; Code: 05 21
CurOn               ldx       #TXT.Base
                    lda       VKY_TXT_CURSOR_CTRL_REG,x
                    ora       #Vky_Cursor_Enable
                    sta       VKY_TXT_CURSOR_CTRL_REG,x
                    rts

;;; CurOff
;;;
;;; Turns the cursor off.
;;;
;;; Code: 05 20
CurOff              ldx       #TXT.Base
                    ldb       VKY_TXT_CURSOR_CTRL_REG,x
                    andb      #~Vky_Cursor_Enable
                    stb       VKY_TXT_CURSOR_CTRL_REG,x
                    rts

ChkESC              cmpa      #$1B                is the character ESC?
                    lbeq      EscHandler          if so, handle it
                    cmpa      #$1C
                    lbeq      OneSeeHandler
                    cmpa      #$1F                is this the 1F handler?
                    lbeq      OneEffHandler       if so, handle it
                    cmpa      #C$CR               is it a carriage return?
                    bhi       ret                 branch if higher than that
                    leax      <DCodeTbl,pcr       else deal with screen codes
                    lsla                          adjust A for the table entry size
                    ldd       a,x                 get the address offset to handle the character in D
                    jmp       d,x                 and jump to routine

* Display functions dispatch table.
DCodeTbl            fdb       NoOp-DCodeTbl       $00:no-op (null)
                    fdb       CurHome-DCodeTbl    $01:HOME cursor
                    fdb       CurXY-DCodeTbl      $02:CURSOR XY
                    fdb       EraseLine-DCodeTbl  $03:ERASE LINE
                    fdb       ErEOLine-DCodeTbl   $04:CLEAR TO EOL
                    fdb       CurOnOff-DCodeTbl   $05:CURSOR CONTROL
                    fdb       CurRght-DCodeTbl    $06:CURSOR RIGHT
                    fdb       Bell-DCodeTbl       $07:Bell
                    fdb       CurLeft-DCodeTbl    $08:CURSOR LEFT
                    fdb       CurUp-DCodeTbl      $09:CURSOR UP
                    fdb       CurDown-DCodeTbl    $0A:CURSOR DOWN
                    fdb       ErEOScrn-DCodeTbl   $0B:ERASE TO EOS
                    fdb       ClrScrn-DCodeTbl    $0C:CLEAR SCREEN
                    fdb       Retrn-DCodeTbl      $0D:RETURN

;;; EraseLin
;;;
;;; Erase the current line.
;;;
;;; Code: 03
EraseLine           clrb                          start erasing at column 0
                    lda       V.CurRow,u          of the current row
* Entry:  A = The row to erase.
*         B = The column to start erasing on.
EraseLineCore       pshs      b                   save the number of columns
                    ldb       V.WWidth,u
                    mul                           get the product
                    addb      ,s                  add the column to start erasing from
                    adca      #0                  consider the carry
                    ldx       #G.ScrStart         get the screen base address
                    leax      d,x                 move X to the current row
                    lda       V.WWidth,u          get the number of columns
                    suba      ,s+                 subtract the column to start erasing from
                    pshs      cc                  save CC
                    orcc      #IntMasks           mask interrupts
                    ldb       MAPSLOT             get the MMU slot value
                    pshs      b                   save it
clrloop@            ldb       #$C2                get the text MMU block
                    stb       MAPSLOT             store it in the MMU slot
                    clr       ,x                  clear the value there
                    ldb       #$C3                get the text attributes MMU block
                    stb       MAPSLOT             store it in the MMU slot
                    ldb       V.FBCol,u           get the curent foreground/background color
                    stb       ,x+                 store it and increment the index register
                    deca                          decrement the loop value
                    bne       clrloop@            branch if not done
                    puls      b                   restore the MMU slot value
                    stb       MAPSLOT             into the hardware
                    puls      cc,pc               restore CC and return

;;; ClrScrn
;;;
;;; Clears the entire screen and homes the cursor.
;;;
;;; Code: 0C
ClrScrn             lda       V.WHeight,u         get the number of rows
                    deca                          minus 1
                    sta       V.CurRow,u          store it in the current row variable
clrloop@            bsr       EraseLine           go erase the line
                    dec       V.CurRow,u          decrement the current row variable
                    bpl       clrloop@            branch if >=0

;;; CurHome
;;;
;;; Moves the cursor to the home location.
;;;
;;; Code: 01
;;;
;;; The home location is column 0, row 0.
CurHome             clr       V.CurCol,u
                    clr       V.CurRow,u
                    rts

;;; CurUp
;;;
;;; Moves the cusor up one line.
;;;
;;; Code: 09
;;;
;;; If the cursor is at the top-most line, it stays at its current position.
CurUp               lda       V.CurRow,u
                    deca
                    bmi       ex@
                    sta       V.CurRow,u
ex@                 rts

;;; CurRght
;;;
;;; Moves the cursor to the right.
;;;
;;; Code: 06
;;;
;;; If the cursor is at the last column, it moves to the first column of the next line.
;;; If the cursor is at the last column of the last line, it stays there.
CurRght             ldd       V.CurRow,u
                    incb                          increment the column
                    cmpb      V.WWidth,u          is it >= the number of columns?
                    bgt       nextrow@
ex@                 std       V.CurRow,u
bye@                rts
nextrow@            ldb       V.WHeight,u
                    decb
                    pshs      b
                    cmpa      ,s+                 are we at the last row?
                    bge       bye@                yep, nothing to change.
                    clrb                          else clear the column
                    inca                          increment the row
                    bra       ex@                 save and return

;;; ErEOLine
;;;
;;; Erase from the current cursor position to the end of the line.
;;;
;;; Code: 04
ErEOLine            ldd       <V.CurRow,u         get the current row and column
                    bra       EraseLineCore       go erase from that point to the end of line

;;; ErEOScrn
;;;
;;; Erase from the current cursor position to the end of the screen.
;;;
;;; Code: 0B
ErEOScrn            bsr       ErEOLine            erase from the curent position to the end of line
                    lda       V.CurRow,u          get the current row
l@                  clrb                          clear the column
                    inca                          increment row
                    cmpa      V.WHeight,u         are we at the end?
                    bge       ex@                 branch if so
                    pshs      a                   save our row counter
                    lbsr      EraseLineCore       go erase the line
                    puls      a                   recover our row counter
                    bra       l@                  go erase more
ex@                 rts                           return

;;; CurXY
;;;
;;; Positions the cursor at the specified coordinates.
;;;
;;; Code: 02
;;;
;;; Parameter: LCX LCY
;;;
;;; LCX is the desired column position + 32.
;;; LCY is the desired row position + 32.
CurXY               leax      CurXYChar1,pcr
c@                  stx       V.EscVect,u
                    rts
CurXYChar1          suba      #$20
                    cmpa      V.WWidth,u
                    blt       s1@
                    lda       V.WWidth,u
                    deca
s1@                 sta       V.CurCol,u
                    leax      CurXYChar2,pcr
                    bra       c@
CurXYChar2          suba      #$20
                    cmpa      V.WHeight,u
                    blt       s2@
                    lda       V.WHeight,u
                    deca
s2@                 sta       V.CurRow,u
                    lbra      ResetHandler

CurOnOff            leax      Do05XX,pcr
c@                  stx       V.EscVect,u
                    rts
Do05XX              cmpa      #$20
                    beq       hide@
                    cmpa      #$21
                    beq       show@
                    cmpa      #$22
                    beq       cchar@
                    cmpa      #$23
                    beq       crate@
                    bra       ResetHandler
crate@              leax      CurRate,pcr
                    bra       c@
cchar@              leax      CurChar,pcr
                    bra       c@
                    bne       ResetHandler
hide@               lbsr      CurOff
                    bra       ResetHandler
show@               lbsr      CurOn
                    bra       ResetHandler

;;; CurRate
;;;
;;; Change the cursor flashing rate.
;;;
;;; Code: 05 23
;;;
;;; Parameter: BYT
;;;
;;;   XXXXX1XX = cursor flashing disabled
;;;   XXXXX000 = 1 second flash interval
;;;   XXXXX001 = .5 second flash interval
;;;   XXXXX010 = .25 second flash interval
;;;   XXXXX011 = .2 second flash interval
CurRate             ldx       #TXT.Base
                    ldb       VKY_TXT_CURSOR_CTRL_REG,x
                    andb      #$01                preserve the cursor enable bit
                    lsla                          shift bits to the left
                    pshs      a                   save the value to OR in on the stack
                    orb       ,s+                 OR it in with the contents of the register
                    stb       VKY_TXT_CURSOR_CTRL_REG,x save it to the hardware
                    bra       ResetHandler        reset the handler

;;; CurChar
;;;
;;; Change the cursor character.
;;;
;;; Code: 05 22
;;;
;;; Parameter: CHR
;;;
;;; CHR can be any character from 0 - 255.
CurChar             ldx       #TXT.Base
                    sta       VKY_TXT_CURSOR_CHAR_REG,x
                    bra       ResetHandler

NoOp
                    rts

;;; CurLeft
;;;
;;; Moves the cursor to the left.
;;;
;;; Code: 09
;;;
;;; If the cursor is at the first column, it moves to the last column of the previous line.
CurLeft             ldd       V.CurRow,u          get the current row and column values
                    beq       leave               branch if they're zero
                    decb                          decrement the column value
                    bpl       EraseChar           erase the character
                    ldb       V.WWidth,u          get the number of columns
                    decb                          minus 1
                    deca                          decrement the counter
                    bpl       EraseChar           branch until done
                    clra                          clear A

* Entry:  A = The row of the character to erase.
*         B = The column of the character to erase.
EraseChar           std       V.CurRow,u          save D to the current row and column
                    ldb       V.WWidth,u          get the number of columns
                    mul                           calculate the product
                    addb      V.CurCol,u          add in the current column
                    adca      #0                  add in the carry bit
                    ldx       #G.ScrStart         point to the start of the screen
                    leax      d,x                 advance to the calculated osition
                    clr       1,x                 erase the character
leave               rts                           return

CurDown             ldd       V.CurRow,u          get the current row and column
                    lbra      incrow              increment the row

Retrn               clr       V.CurCol,u          clear the current column
                    rts                           return

* We don't do anything with $1F codes currently.
OneEffHandler       leax      OneEffHandler2,pcr  point to the 1F handler to the 2nd character
                    stx       V.EscVect,u         store it in the vector
                    rts                           return

* 1F 20 Turns on reverse video
* 1F 21 Turns off reverse video
* 1F 22 Turns on underlining.
* 1F 23 Turns off underlining.
* 1F 24 Turns on blinking.
* 1F 25 Turns off blinking.
* 1F 30 Inserts a line at the current cursor position.
* 1F 31 Deletes the current line.
OneEffHandler2
                    cmpa      #$20
                    beq       revon
                    cmpa      #$21
                    beq       revoff
ResetHandler        leax      DefaultHandler,pcr
                    bra       SetHandler
revoff              tst       V.Reverse,u         is reverse already off?
                    beq       SetHandler          branch if so
                    com       V.Reverse,u
                    bra       DoReverse
revon               tst       V.Reverse,u         is reverse already on?
                    bne       SetHandler          branch if so
                    com       V.Reverse,u
DoReverse
* swap foreground and background color bits
                    lda       V.FBCol,u           else get the fore/background color
                    lsra                          shift all...
                    lsra                          of the foreground..
                    lsra                          color bits into the...
                    lsra                          lower nibble
                    pshs      a
                    lda       V.FBCol,u
                    lsla                          shift all...
                    lsla                          of the background...
                    lsla                          color bits into the...
                    lsla                          upper nibble
                    ora       ,s+
                    sta       V.FBCol,u
                    bra       ResetHandler

EscHandler          leax      Do1B,pcr            point to the handler to the 2nd character
SetHandler          stx       V.EscVect,u         store it in the vector
                    rts                           return

* Window mode handler
Do1B20              sta       V.DWType,u
                    leax      Do1B20TT,pcr
                    bra       SetHandler

Do1B20TT            sta       V.DWStartX,u
                    leax      Do1B20TTXX,pcr
                    bra       SetHandler

Do1B20TTXX          sta       V.DWStartY,u
                    leax      Do1B20TTXXYY,pcr
                    bra       SetHandler

Do1B20TTXXYY        sta       V.DWWidth,u
                    leax      Do1B20TTXXYYWW,pcr
                    bra       SetHandler

Do1B20TTXXYYWW      sta       V.DWHeight,u
                    leax      Do1B20TTXXYYWWHH,pcr
                    bra       SetHandler

Do1B20TTXXYYWWHH    sta       V.DWFore,u
                    leax      Do1B20TTXXYYWWHHFF,pcr
                    bra       SetHandler

Do1B20TTXXYYWWHHFF  sta       V.DWBack,u
                    leax      Do1B20TTXXYYWWHHFFBB,pcr
                    bra       SetHandler

Do1B20TTXXYYWWHHFFBB
                    sta       V.DWBorder,u

;;; DWSet
;;;
;;; Set a device window.
;;;
;;; Code: 1B 20
;;;
;;; Parameters: STY CPX CPY SZX SZY PRN1 PRN2 PRN3
;;;
;;; STY = screen type: $01 = 40x30, $02 = 80x30, $03 = 40x60, $04 = 80x60.
;;; CPX = starting position X.
;;; CPY = starting position Y.
;;; SZX = width starting at X.
;;; SZY = height starting at Y.
;;; PRN1 = foreground color.
;;; PRN2 = background color.
;;; PRN3 = border color.
DWSet               lda       V.DWType,u
                    sta       V.ScTyp,u
                    cmpa      #$01                40x30?
                    bne       IsIt80x30
                    bsr       SetWin40x30
                    bra       setcols@
IsIt80x30           cmpa      #$02
                    bne       IsIt40x60
                    bsr       SetWin80x30
                    bra       setcols@
IsIt40x60           cmpa      #$03
                    bne       IsIt80x60
                    bsr       SetWin40x60
                    bra       setcols@
IsIt80x60           bsr       SetWin80x60                    
setcols@            lda       V.DWFore,u
                    lbsr      SetForeColor
                    lda       V.DWBack,u
                    lbsr      SetBackColor
                    lda       V.DWBorder,u
                    lbsr      SetBorderColor
                    lbsr      ClrScrn
                    lbra      ResetHandler

SetWin40x30         ldb       #DBL_Y|DBL_X
                    ldx       #40*256+30
SetWin              stx       V.WWidth,u
                    pshs      b
                    ldx       #TXT.Base
                    ldb       MASTER_CTRL_REG_H,x
                    andb      #~(DBL_Y|DBL_X|CLK_70)
                    orb       ,s+
                    stb       MASTER_CTRL_REG_H,x
                    rts

SetWin40x60         ldb       #DBL_X
                    ldx       #40*256+60
                    bra       SetWin

SetWin80x30         ldb       #DBL_Y
                    ldx       #80*256+30
                    bra       SetWin

SetWin80x60         clrb
                    ldx       #80*256+60
                    bra       SetWin

;;; ChgForePal
;;;
;;; Change a foreground palette register.
;;;
;;; Code: 1B 60
;;;
;;; Parameters: PRN RVA GVA BVA AVA
;;;
;;; PRN = foreground palette register number (0-15).
;;; RVA = red component.
;;; GVA = green component.
;;; BVA = blue component.
;;; AVA = alpha component.
ChgForePal          ldx       #MAPADDR  
                    leax      TEXT_LUT_FG,x
ChgPal              stx       V.EscParms+4,u
                    leax      Do1B60_Param0,pcr
                    lbra      SetHandler
                    
Do1B60_Param0
                    sta       V.EscParms+0,u
                    leax      Do1B60_Param1,pcr
                    lbra      SetHandler

Do1B60_Param1
                    sta       V.EscParms+1,u
                    leax      Do1B60_Param2,pcr
                    lbra      SetHandler

Do1B60_Param2
                    sta       V.EscParms+2,u
                    leax      Do1B60_Param3,pcr
                    lbra      SetHandler

Do1B60_Param3
                    sta       V.EscParms+3,u
                    leax      Do1B60_Param4,pcr
                    lbra      SetHandler

Do1B60_Param4       pshs      cc
                    orcc      #IntMasks
                    ldb       MAPSLOT
                    pshs      b
                    ldb       #TEXT_LUT_BLK
                    stb       MAPSLOT
                    ldx       V.EscParms+4,u
                    ldb       V.EscParms+0,u
                    lslb
                    lslb
                    abx       
                    sta       3,x
                    lda       V.EscParms+3,u get blue component
                    sta       0,x
                    lda       V.EscParms+2,u get green component
                    sta       1,x
                    lda       V.EscParms+1,u get red component
                    sta       2,x
                    puls      b
                    stb       MAPSLOT
                    puls      cc
                    lbra      ResetHandler

;;; ChgBackPal
;;;
;;; Change a foreground palette register.
;;;
;;; Code: 1B 61
;;;
;;; Parameters: PRN RVA GVA BVA AVA
;;;
;;; PRN = background palette register number (0-15).
;;; RVA = red component.
;;; GVA = green component.
;;; BVA = blue component.
;;; AVA = alpha component.
ChgBackPal          ldx       #MAPADDR
                    leax      TEXT_LUT_BG,x
                    bra       ChgPal

* These do nothing for now.
DefColr
DWSelect
DWEnd               lbra      ResetHandler

Do1B                cmpa      #$20                is it the window mode?
                    bne       IsIt21              branch if not
                    leax      Do1B20,pcr          else point to the vector
                    lbra      SetHandler          and set the handler
IsIt21              cmpa      #$21                is it DWSelect?
                    bne       IsIt24              branch if not
                    lbra      DWSelect
IsIt24              cmpa      #$24                is it DWEnd?
                    bne       IsIt30              branch if not
                    lbra      DWEnd
IsIt30              cmpa      #$30                is it DefColr?
                    bne       IsIt60              branch if not
                    lbra      DefColr
IsIt60              cmpa      #$60                is it ChgForePal?
                    bne       IsIt61              branch if not
                    lbra      ChgForePal
IsIt61              cmpa      #$61                is it ChgBackPal?
                    bne       IsIt62              branch if not
                    lbra      ChgBackPal
IsIt62              cmpa      #$62                Change to Font0
                    bne       IsIt63
                    lbra      ChgFont0
IsIt63              cmpa      #$63                Change to Font1
                    bne       IsIt32
                    lbra      ChgFont1              
IsIt32              cmpa      #$32                is it the foreground color code?
                    bne       IsIt33              branch if not
                    leax      FColor,pcr          else point to the vector
                    lbra      SetHandler          and set the handler
IsIt33              cmpa      #$33                is it the background color code?
                    bne       IsIt34              branch if not
                    leax      BColor,pcr          else point to the vector
                    lbra      SetHandler          and set the handler
IsIt34              cmpa      #$34                is it the foreground color code?
                    lbne      IsIt3D
                    leax      Border,pcr          else point to the vector
                    lbra      SetHandler          and set the handler
IsIt3D              cmpa      #$3D                is it the foreground color code?
                    lbne      ResetHandler        if not, reset the handler
                    leax      BoldSw,pcr          else point to the vector
                    lbra      SetHandler          and set the handler

* Foreground/background/border color handlers
FColor              bsr       SetForeColor
                    lbra      ResetHandler        reset the handler
BColor              bsr       SetBackColor
                    lbra      ResetHandler        reset the handler
Border              bsr       SetBorderColor
                    lbra      ResetHandler        reset the handler

* Change to FontSet0
ChgFont0            ldx       #TXT.Base
                    ldb       MASTER_CTRL_REG_H,x
                    andb      #~(FT_FSET)
                    stb       MASTER_CTRL_REG_H,X
                    lbra      ResetHandler

* Change to FontSet1
ChgFont1            ldx       #TXT.Base
                    ldb       MASTER_CTRL_REG_H,x
                    orb       #FT_FSET
                    stb       MASTER_CTRL_REG_H,X
                    lbra      ResetHandler


* BoldSw - do nothing.
BoldSw              lbra      ResetHandler        reset the handler

SetForeColor        lsla                          A = A / 2
                    lsla                          A = A / 2
                    lsla                          A = A / 2
                    lsla                          A = A / 2
                    pshs      a                   save the register
                    ldb       V.FBCol,u           load the foreground/background color
                    andb      #$0F                mask out the upper 4 bits
doout@              orb       ,s+                 OR in the foreground color bits
                    stb       V.FBCol,u           save the updated color
SetBorderColor      rts                           return
SetBackColor        anda      #$0F                mask out the upper 4 bits
                    pshs      a                   save the register
                    ldb       V.FBCol,u           load the foreground/background color
                    andb      #$F0                mask out the lower 4 bits
                    bra       doout@              and do the OR

OneSeeHandler       leax      Do1C,pcr
                    lbra      SetHandler

Do1C                lbsr      RawWrite
                    lbra      ResetHandler

* Return special key status
GSKySns 
*            ldy       <D.CCMem            get ptr to CC mem
                    clrb                          clear key code
*                    cmpu      <G.CurDev,y         are we the active device?
*                    bne       actv@               branch if not
                    ldb       V.KySns,u          get key codes
actv@               stb       R$A,x               save to caller reg
                    clrb                          return w/o error
                    rts

* GetStat
*
* Entry:
*    A  = function code
*    Y  = address of path descriptor
*    U  = address of device memory area
*
* Exit:
*    CC = carry set on error
*    B  = error code
*
****************************
* Get status entry point
* Entry: A=Function call #
GetStat             cmpa      #SS.EOF             is this the EOF call?
                    beq       SSEOF               yes, exit without error
                    ldx       PD.RGS,y            else get the pointer to caller's registers (all other calls require this)
                    cmpa      #SS.Ready           is this the data ready call? (keyboard buffer)
                    beq       SSReady             branch if so
                    cmpa      #SS.ScSiz           get screen size?
                    beq       SSScSiz             branch if so
                    cmpa      #SS.ScTyp           get screen type?
                    beq       SSScTyp             branch if so
                    cmpa      #SS.KySns           get key sense info?
                    lbeq      GSKySns             branch if so
                    cmpa      #SS.Joy             get joystick position?
                    beq       SSJoy               branch if so
                    cmpa      #SS.Palet           get palettes?
                    beq       GSPalet             yes, go process
                    cmpa      #SS.FBRgs           get colors?
                    lbeq      SSFBRgs             yes, go process
                    cmpa      #SS.DfPal           get default colors?
                    beq       GSDfPal             yes, go process
                    comb                          set the carry
                    ldb       #E$UnkSvc           load the "unknown service" error
                    rts                           return

;;; SS.ScTyp
;;;
;;; Returns information about the current video screen.
;;;
;;; Entry:  A = The path number.
;;;         B = SS.ScTyp ($93)
;;;
;;; Exit:   A = The screen type.
;;;              1 = 40x30 text screen
;;;              2 = 80x30 text screen
;;;              3 = 40x60 text screen
;;;              4 = 80x60 text screen
;;;        CC = Carry flag clear to indicate success.
;;;
;;; Error:  B = A non-zero error code.
;;;        CC = Carry flag set to indicate error.
SSScTyp             lda       V.ScTyp,u            get the screen type
                    sta       R$A,x
                    rts

;;; SS.Ready
;;;
;;; Tests for data available on SCF-supported devices.
;;;
;;; Entry:  A = The path number.
;;;         B = SS.Ready ($01)
;;;
;;; Exit:   B = The number of characters ready to read.
;;;        CC = Carry flag clear to indicate success.
;;;
;;; Error:  B = E$NotRdy if there are no bytes ready to read.
;;;        CC = Carry flag set to indicate error.
SSReady             lda       V.IBufH,u           else get get the buffer tail ptr
                    suba      V.IBufT,u           A = the number of characters ready to read
                    sta       R$B,x               save in the caller's B
                    beq       NotReady            if there's no data in keyboard buffer, return the "not ready" error
SSEOF               clrb                          clear the error code and carry
                    rts                           return
NotReady            comb                          set the carry
                    ldb       #E$NotRdy           load the "not ready" error
                    rts                           return

;;; SS.ScSiz
;;;
;;; Return the screen size.
;;;
;;; Entry:  A = The path number.
;;;         B = SS.ScSiz ($26)
;;;
;;; Exit:   X = The number of columns on the screen.
;;;         Y = The number of rows on the screen.
;;;        CC = Carry flag clear to indicate success.
;;;
;;; Error:  B = A non-zero error code.
;;;        CC = Carry flag set to indicate error.
;;;
;;; Use this call to determine the size of a the screen. The returnedvalues depend on the device in use.
;;; For non-VTIO devices, the call returns the values following the XON/XOFF bytes in the device descriptor.
;;; For VTIO devices, the call returns the size of the window or screen in use by the specified device.
;;; For window devices, the call returns the size of the current working area of the window.
SSScSiz             clra                          clear the upper 8 bits of D
                    ldb       V.WWidth,u          get the column count
                    std       R$X,x               save it in X
                    ldb       V.WHeight,u         get the row count
                    std       R$Y,x               save it in Y
;;; SS.Joy
;;;
;;; Returns the joystick information.
;;;
;;; Entry:  X = Joystick to read.
;;;         B = SS.Joy ($13)
;;;
;;; Exit:   A = Button state.
;;;         X = Horizontal position (0 = left, 255 = right).
;;;         Y = Vertical position (0 = top, 255 = bottom).
;;;        CC = Carry flag clear to indicate success.
;;;
;;; Error:  B = A non-zero error code.
;;;        CC = Carry flag set to indicate error.
SSJoy               lda       VIA0.Base+VIA_ORA_IRA get the joystick value
                    ldx       #0                  initialize left/top value in X
                    ldy       #255                initialize right/bottom value in Y
                    lsra                          shift out UP
                    bcc       s1@                 branch if carry clear
                    stx       R$Y,u               else store left value in caller's Y
s1@                 lsra                          shift out DOWN
                    bcc       s2@                 branch if carry clear
                    sty       R$Y,u               else store right value in caller's Y
s2@                 lsra                          shift out LEFT
                    bcc       s3@                 branch if carry clear
                    stx       R$X,u               else store up value in caller's X
s3@                 lsra                          shift out RIGHT
                    bcc       s4@                 branch if carry clear
                    sty       R$X,u               else store right value in caller's X
* A now contains (BUTTON 2 | BUTTON 1 | BUTTON 0) in lower 3 bits
s4@                 sta       R$A,u               store buttons in caller's A
                    clrb                          clear carry
                    rts                           return


;;; SS.Palet
;;;
;;; Return palette information.
GSPalet

;;; SS.FBRGs
;;;
;;; Returns the foreground, background, and border palette registers for a window.
;;;
;;; Entry:  A = The path number.
;;;         B = SS.FBRgs ($96)
;;;
;;; Exit:   A = The foreground/background palette register numbers.
;;;         X = The least significant byte of the border palette register number.
;;;        CC = Carry flag clear to indicate success.
;;;
;;; Error:  B = A non-zero error code.
;;;        CC = Carry flag set to indicate error.
SSFBRGs             lda                 V.FBCol,u
                    sta                 R$A,x
                    ldd                 #0
                    std                 R$X,x
                    rts

;;; SS.DfPal
;;;
;;; Returns the foreground, background, and border palette registers for a window.
;;;
;;; Entry:  A = The path number.
;;;         B = SS.DfPal ($97)
;;;         X = A pointer to user-provided 16-byte palette data.
;;;
;;; Exit:   X = The default palette data moved to user space.
;;;        CC = Carry flag clear to indicate success.
;;;
;;; Error:  B = A non-zero error code.
;;;
;;; Use this call to find the values of the default palette registers when a new screen is allocated.
;;; The corresponding SetStat alters the default registers. This is for system configuration utilities
;;; and shouldn't be used by general applications.
GSDfPal

                    clrb                          no error
                    rts                           return

*
* SetStat
*
* Entry:
*    A  = function code
*    Y  = address of path descriptor
*    U  = address of device memory area
*
* Exit:
*    CC = carry set on error
*    B  = error code
*
SS.DMAFill          equ       $B0
SetStat             ldx       PD.RGS,y            get caller's registers in X
                    cmpa      #SS.SSig            send signal on data ready?
                    lbeq      SSSig               yes, go process
                    cmpa      #SS.Relea           release signal on data ready?
                    lbeq      SSRelea             yes, go process
                    cmpa      #SS.DMAFill         DMA Fill?
                    beq       SSDMAFill
                    cmpa      #SS.Tone
                    beq       SSTone
                    comb                          set the carry
                    ldb       #E$UnkSvc           load the "unknown service" error
                    rts                           return

SSTone              ldy       R$Y,x               check for 0-1023 range
                    cmpy      #1023
                    bgt       BadArgs
                    ldd       R$X,x               get vol, duration
                    cmpa      #15
                    bgt       BadArgs
                    lbra      BellTone            do it
 
BadArgs             comb                          Exit with Illegal Argument error
                    ldb       #E$IllArg
                    rts

* SS.DMAFill - fill memory
DMF$DstAddrHi       equ       0
DMF$DstAddrMid      equ       1
DMF$DstAddrLow      equ       2
DMF$DstSizeHi       equ       3
DMF$DstSizeMid      equ       4
DMF$DstSizeLow      equ       5
DMF$FillValue       equ       6

SSDMAFill           ldy       #DMA.Base
                    lda       #DMA_CTRL_Fill|DMA_CTRL_Start_Trf
                    sta       DMA_CTRL_REG,y
                    ldx       R$X,x               get pointer to the DMA control block
                    ldd       DMF$DstAddrHi,x
                    sta       DMA_DEST_ADDR_H,y
                    stb       DMA_DEST_ADDR_M,y
                    lda       DMF$DstAddrLow,x
                    stb       DMA_DEST_ADDR_L,y
                    ldd       DMF$DstSizeHi,x
                    sta       DMA_SIZE_1D_H,y
                    stb       DMA_SIZE_1D_M,y
                    ldd       DMF$DstSizeLow,x
                    sta       DMA_SIZE_1D_L,y
                    stb       DMA_DATA_2_WRITE
                    lda       DMA_CTRL_REG,y
                    ora       #DMA_CTRL_Start_Trf
                    sta       DMA_CTRL_REG,y
* The CPU halts here until the transfer is complete.
                    rts

* SS.SSig - send signal on data ready
SSSig               pshs      cc                  save interrupt status
                    lda       V.IBufH,u           get get the buffer tail ptr
                    suba      V.IBufT,u           A = the number of characters ready to read
                    pshs      a                   save it temporarily
                    bsr       GetCPR              get current process ID
                    tst       ,s+                 anything in buffer?
                    bne       SendSig             yes, go send the signal
                    std       <V.SSigID,u         save process ID & signal
                    puls      pc,cc               restore interrupts & return

GetCPR              orcc      #IntMasks           disable interrupts
                    lda       PD.CPR,y            get curr proc #
                    ldb       R$X+1,x             get user signal code
                    rts                           return

SendSig             puls      cc                  restore interrupts
                    os9       F$Send              send the signal
                    rts                           return

* SS.Relea - release a path from SS.SSig
SSRelea             lda       PD.CPR,y            get the current process ID
                    cmpa      <V.SSigID,u         is it the same as the keyboard?
                    bne       ex@                 branch if not
                    clr       <V.SSigID,u         else clear process the ID
ex@                 rts


                    emod
eom                 equ       *
                    end
