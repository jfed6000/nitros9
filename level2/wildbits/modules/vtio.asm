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

* Level 2 VTIO. Level 1 is vtio_l1.asm (MAPSLOT 7, no grfdrv256).
* Do not alias 1-byte D.Boot. D.KbdSta is the 2-byte overlay at $18
* from wildbits_vtio.d.

* System LUT 0 slot 2 home is SRAM $03. Glyph/erase/scroll/blank,
* InitDisplay / text palettes, bitmap SetStat, PSG, and dbgwrite all
* go through GF.Write (LUT 1). Do not map system MAPSLOT.

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
                    fcb       $0D

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
                    beq       HandleKeySwtchTrm  mouse off: still check switch (glue #10)
                    inc       V.MSTimer,u                increment mouse auto-hide timer
                    bne       HandleKeySwtchTrm  timer not wrapped: still check switch
                    clr       MS_MEN             if timer flips to 0, turn off mouse cursor
                    ldd       #640               park mouse at right border
                    sta       MS_XH              turning off cursor doesn't work
                    stb       MS_XL              correctly at the moment
HandleKeySwtchTrm   lda       >gr.SwitchReq
                    beq       AltISRCont
                    sta       $12E4              last SwitchReq seen
                    tst       >gr.Busy
                    bne       AltISRCont
                    lda       #$AA
                    sta       $12E5              about to SwitchTerm
                    lbsr      SwitchTerm
                    lda       #$55
                    sta       $12E6              SwitchTerm returned
                    lda       >gr.LiveTerm
                    sta       $12E7
AltISRCont
                    endc
* Handle sound. PSG $C4 via GF.Write LUT 1. AltISR cannot F$Sleep, so
* skip Flip1 when gr.Busy and retry next tick (do not put WaitWrite
* inside CallGrfDrvNoPD).
HandleSound
                    tst       D.TnCnt            get the tone counter
                    beq       AltSndEx           branch if zero
                    dec       D.TnCnt            else decrement the counter
                    bne       AltSndEx           branch not zero; leave the sound on
sndoff              pshs      cc                 save the condition code register
                    orcc      #IntMasks          mask interrupts
                    tst       >gr.Busy
                    bne       AltSndBusy
                    lda       #WO.Psg
                    sta       >gr.WOp
                    lda       #WP.Off
                    sta       >gr.WDest
                    ldb       #GF.Write
                    lbsr      CallGrfDrvNoPD
                    lda       D.SndPrcID
                    beq       AltSndWake
                    ldb       #S$Wake
                    os9       F$Send
                    clr       D.SndPrcID
AltSndWake          puls      cc
                    jmp       [D.OrgAlt]
AltSndBusy          inc       D.TnCnt            Flip1 held; retry next 1/60s
                    puls      cc
AltSndEx            jmp       [D.OrgAlt]         branch to the original alternate IRQ routine

*******************************************************
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
                    bne       BellBusy
                    stb       D.TnCnt             store the duration counter in the global
                    pshs      cc,a
                    sta       >gr.WColor          volume 0-15; LUT 1 inverts
                    sty       >gr.WOff            frequency
                    lda       #WP.Bell
                    sta       >gr.WDest
                    lda       #WO.Psg
                    sta       >gr.WOp
                    lbsr      CallWrite
                    lda       V.BUSY,u            get active process ID
                    sta       D.SndPrcID
                    ldx       #$0000
                    os9       F$Sleep
                    puls      cc
                    clrb
                    andcc     #^Carry
                    puls      a,pc
BellBusy            rts
           
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
                    bra       InitCODEC           InitPSG needs grfdrv256 (after InitGrfDrv)

* Silence PSG via GF.Write. Call after InitGrfDrv. Never system MAPSLOT.
InitPSG             lda       #WP.Init
                    sta       >gr.WDest
                    lda       #WO.Psg
                    sta       >gr.WOp
                    lbra      CallWrite

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
                    
* Initialize the display I/O registers. No MAPSLOT.
* Gamma / font / text LUTs / $C2 $C3 fill run later in InitDisplayMem
* (after InitGrfDrv) via GF.Write WO.InitDisp in LUT 1.
InitDisplay         pshs      u
                    ldx       #TXT.Base
                    ldd       #80*256+60
                    std       V.WWidth,u
                    lda       #Mstr_Ctrl_Text_Mode_En
                    sta       MASTER_CTRL_REG_L,x
                    clr       MASTER_CTRL_REG_H,x
                    clr       BORDER_CTRL_REG,x
                    clr       BORDER_COLOR_R,x
                    clr       BORDER_COLOR_G,x
                    clr       BORDER_COLOR_B,x
                    lda       #Vky_Cursor_Enable|Vky_Cursor_Flash_Rate0|Vky_Cursor_Flash_Rate1
                    sta       VKY_TXT_CURSOR_CTRL_REG,x
                    clra
                    clrb
                    std       VKY_TXT_CURSOR_Y_REG_H,x
                    std       VKY_TXT_CURSOR_X_REG_H,x
                    lda       #'_
                    sta       VKY_TXT_CURSOR_CHAR_REG,x
                    puls      u,pc

*******************************************************************
* InitDisplayMem - F$Link palette/font in the system task, snapshot
* into gr.W* / gr.PalBuf, Flip1 GF.Write WO.InitDisp. After
* InitGrfDrv (GrfMem clear wipes PalBuf). Do not index U in LUT 1.
*******************************************************************
InitDisplayMem      pshs      x,y,u
                    clr       >gr.WGlyph
                    clr       >gr.WCount
                    clr       >gr.WCount+1
                    leax      palettemod,pcr
                    lda       #Data
                    os9       F$Link
                    bcs       IDFontLk
                    lda       #$FF
                    sta       >gr.WGlyph
                    tfr       y,x
                    ldy       #gr.PalBuf
                    ldb       #32
IDCpPal             ldu       ,x++
                    stu       ,y++
                    decb
                    bne       IDCpPal
IDFontLk            leax      fontmod,pcr
                    lda       #Data
                    os9       F$Link
                    bcs       IDCall
                    tfr       y,x
                    bsr       Log2Blk
                    sta       >gr.WDest
                    stx       >gr.WOff
                    tfr       y,d
                    cmpa      #$E0
                    bhs       IDSame
                    leax      $2000,y
                    bsr       Log2Blk
                    sta       >gr.WWidth
                    bra       IDCnt
IDSame              lda       >gr.WDest
                    sta       >gr.WWidth
IDCnt               ldd       #2048
                    std       >gr.WCount
IDCall              lda       #WO.InitDisp
                    sta       >gr.WOp
                    lbsr      CallWrite
                    puls      x,y,u,pc

* X = logical address in D.Proc. Exit: A = block, X = offset in 8K.
Log2Blk             pshs      y
                    ldy       >D.Proc
                    leay      P$DATImg,y
                    tfr       x,d
                    pshs      d
                    lsra
                    lsra
                    lsra
                    lsra
                    lsra
                    lsla
                    inca
                    lda       a,y
                    puls      x
                    pshs      a
                    tfr       x,d
                    anda      #$1F
                    tfr       d,x
                    puls      a
                    puls      y,pc

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

                  IFGT    Level-1
****************************************************************
* Init GrfDrv — from wildbits vtio. Module name is grfdrv256.
* Clears GrfMem ($1100, 512 bytes) so call before gr.KbdInit=$FF
* and before InitTerm. Task 1 / LUT 1; not system-task $6000.
****************************************************************
InitGrfDrv          pshs      u,y
                    ldx       #GrfMem   point to GrfMem
                    ldy       #512      Size
clrgrf              clr       ,x+
                    leay      -1,y
                    bne       clrgrf
                    lda       #1        **DEBUG**
                    sta       $1200     **DEBUG**
                    leas      -2,s      buffer for process swap
                    lbsr      tosysproc swap to system process
                    lda       #Systm+Objct
                    leax      llnam,pcr
                    os9       F$NMLink
                    lbsr      toproc
                    bcc       setupgrfdrv
                    tfr       b,a
                    sta       $1201     **DEBUG**
                    cmpb      #E$MNF
                    lbne      initerr
                    lbsr      tosysproc
                    lda       #Systm+Objct
                    leax      llpath,pcr
                    ldu       <D.Proc
                    os9       F$NMLoad
                    lbsr      toproc
                    lbcs      initerr
                    pshs      a         **DEBUG**
                    lda       #2        **DEBUG**
                    sta       $1201     **DEBUG**
                    puls      a         **DEBUG**
setupgrfdrv         leas      2,s       clean process buffer
                    pshs      a
                    lda       #GrfMem/256
                    tfr       a,dp
                    puls      a
                    ldu       #GrfMem
                    ldx       #gr.DATImg
                    stx       $120A
                    clra
                    clrb
                    std       ,x++
                    ldd       #DAT.Free
                    std       ,x++
                    std       ,x++
                    std       ,x++
                    std       ,x++
                    std       ,x++
                    pshs      x
                    lda       #Systm+Objct
                    leax      llnam,pcr
                    ldy       >D.SysPrc
                    leay      P$DATImg,y
                    os9       F$FModul
                    puls      x
                    lbcs      initerr2
                    ldy       MD$MPDAT,u
                    clra
                    ldd       ,y
                    std       ,x++
                    std       $1206
                    ldd       2,y
                    bne       has2
                    ldd       #DAT.Free
                    bra       store7
has2
                    clra
store7
                    std       ,x++
                    std       $1208
                    ldy       >D.TskIPt
                    ldx       #gr.DATImg
                    stx       2,y
                    ldd       #$1CB0
                    std       gr.Stack
                    clra
                    tfr       a,dp
                    inc       MD$Link+1,u
                    ldd       #0
                    ldx       #M$Exec
                    ldy       #gr.DATImg+12
                    os9       F$LDDDXY
                    std       $1220
                    ora       #$C0
                    std       gr.Entry
                    std       $1210
                    ldx       gr.Entry
                    stx       $1212
                    ldx       #gr.TermTbl
                    ldb       #G.TermMax
clrScr              pshs      b,x
                    ldb       #gr.TermSz
clrLoop             clr       ,x+
                    decb
                    bne       clrLoop
                    puls      b,x
                    leax      gr.TermSz,x
                    decb
                    bne       clrScr
                    lda       #$FF
                    sta       gr.LiveTerm
                    ldb       #GF.Init
                    pshs      a         **DEBUG**
                    lda       #3        **DEBUG**
                    sta       $1203     **DEBUG**
                    puls      a         **DEBUG**
                    lbsr      CallGrfDrv
                    lbcs      initerr3
                    pshs      a         **DEBUG**
                    lda       #4        **DEBUG**
                    sta       $1204     **DEBUG**
                    puls      a         **DEBUG**
                    clrb
                    puls      y,u,pc
initerr2            leas      4,s
initerr             leas      2,s
initerr3            pshs      a         **DEBUG**
                    lda       #5        **DEBUG**
                    sta       $1205     **DEBUG**
                    puls      a         **DEBUG**
                    coma
                    puls      y,u,pc

InitDevice          ldu       2,s
                    ldy       ,s
                    clrb
                    puls      y,u,pc

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
* CallGrfDrv - B = GF.*  Y = path descriptor (copies PD.RGS)
* CallGrfDrvNoPD - B = GF.*  no PD (ISR / switch)
*******************************************************************
CallWriteCharLive   ldx	     gr.WriteCharLive
		    bra	     CallGrfDrv2
CallWriteCharShadow ldx	     gr.WriteCharShadow
		    bra	     CallGrfDrv2
CallScrollLive      ldx	     gr.WriteCharLive
		    bra	     CallGrfDrv2
CallScrollShadow    ldx	     gr.WriteCharShadow
		    bra	     CallGrfDrv2
		    
CallGrfDrv
                    pshs      x,u,y,b
                    ldx       PD.RGS,y
                    stx       >gr.RGSADR
                    ldb       #R$Size/2
                    ldy       #gr.PDRGS
cpyloop             ldu       ,x++
                    stu       ,y++
                    decb
                    bne       cpyloop
                    ldx       >D.Proc
                    leax      P$DATImg,x
                    ldb       #8
                    ldy       #gr.PDAT
datcopy             ldu       ,x++
                    stu       ,y++
                    decb
                    bne       datcopy
                    puls      x,u,y,b
CallGrfDrvNoPD
                    ldx       gr.Entry
CallGrfDrv2         orcc      #Entire
                    pshs      d
                    tfr       cc,a
                    sta       gr.Temp
                    puls      d
                    orcc      #IntMasks
                    sts       gr.Stack
                    lds       <D.CCStk
                    pshs      dp,x,y,u,pc
                    pshs      cc,d
                    stx       R$PC,s
                    lda       gr.Temp
                    sta       R$CC,s
                    sta       gr.Busy
                    jmp       [>D.Flip1]
                    rts

nogrf               comb
                    ldb       #E$UnkSvc
                    rts

gbusy               comb
                    ldb       #E$NotRdy
                    rts

*******************************************************************
* SetTermGrfPtrs — copied from wildbits vtio. Do not rewrite.
* Entry: X = gr.TermTbl entry
* Sets gr.TermBlk, gr.VStaStorU, gr.VBlk from that entry
*******************************************************************
SetTermGrfPtrs      pshs      d,x,y,u
                    ldb       T.Block,x
                    stb       >gr.TermBlk
                    ldu       T.StatPtr,x
                    stu       >gr.VStaStorU
                    ldy       >D.SysPrc
                    leay      P$DATImg,y
                    tfr       u,d
                    lsra
                    lsra
                    lsra
                    lsra
                    lsra                A = MMU slot 0-7
                    lsla                A = slot * 2
                    inca                LSB of 2-byte DAT entry
                    lda       a,y       block number
                    sta       >gr.VBlk
                    puls      d,x,y,u,pc

*******************************************************************
* SwitchTerm — copied from wildbits vtio (unique labels: lwasm @
* locals die across a blank line; distant targets use lbeq/lbra).
* Called from AltISR via CallGrfDrvNoPD. GF.PushBuf=8 GF.PullBuf=9.
* SetTermGrfPtrs before each Push/Pull.
*******************************************************************
SwitchTerm
                    pshs      cc,d,x,y,u
                    orcc      #IntMasks
                    lda       >gr.SwitchReq
                    lbeq      SwDone
                    lda       >gr.LiveTerm
                    cmpa      #$FF
                    lbeq      SwDone
                    tfr       a,b
                    lslb
                    lslb                    B = ID * gr.TermSz
                    tst       >gr.SwitchReq
                    bmi       SwFindPrev
                    bra       SwFindNext
SwFindPrev
                    deca
                    subb      #gr.TermSz
                    bpl       SwChkPrev
                    lda       #G.TermMax-1
                    ldb       #(G.TermMax-1)*gr.TermSz
SwChkPrev
                    cmpa      >gr.LiveTerm
                    lbeq      SwDone
                    ldx       #gr.TermTbl
                    abx
                    pshs      a
                    lda       T.Flags,x
                    bita      #T.Init
                    puls      a
                    beq       SwFindPrev
                    bra       SwFound
SwFindNext
                    inca
                    addb      #gr.TermSz
                    cmpa      #G.TermMax
                    blo       SwChkNext
                    clra
                    clrb
SwChkNext
                    cmpa      >gr.LiveTerm
                    lbeq      SwDone
                    ldx       #gr.TermTbl
                    abx
                    pshs      a
                    lda       T.Flags,x
                    bita      #T.Init
                    puls      a
                    beq       SwFindNext
SwFound
                    pshs      d               A=new ID, B=new offset
                    lda       >gr.LiveTerm
                    tfr       a,b
                    lslb
                    lslb
                    ldx       #gr.TermTbl
                    abx
                    lbsr      SetTermGrfPtrs
                    ldb       #GF.PushBuf
                    lbsr      CallGrfDrvNoPD
                    bcs       SwFail
* Flip0 leaves U = LUT-1 VSta alias ($6000 -> $A000). Recompute
* table ptrs; never stu D.KbdSta from that alias (keys go nowhere).
                    lda       >gr.LiveTerm
                    tfr       a,b
                    lslb
                    lslb
                    ldx       #gr.TermTbl
                    abx
                    lda       T.Flags,x
                    anda      #^T.Live
                    sta       T.Flags,x
                    ldu       T.StatPtr,x
                    clr       V.TermLive,u
                    ldd       ,s              A=new ID, B=new offset
                    ldx       #gr.TermTbl
                    abx
                    lbsr      SetTermGrfPtrs
                    ldb       #GF.PullBuf
                    lbsr      CallGrfDrvNoPD
                    bcs       SwFail
                    ldd       ,s
                    ldx       #gr.TermTbl
                    abx
                    lda       T.Flags,x
                    ora       #T.Live
                    sta       T.Flags,x
                    ldd       T.StatPtr,x
                    std       >D.KbdSta
                    std       >gr.VStaStorU
                    ldu       >D.KbdSta
                    lda       #1
                    sta       V.TermLive,u
                    puls      d
                    sta       >gr.LiveTerm
                    lda       V.CurCol,u
                    ldx       #TXT.Base
                    sta       VKY_TXT_CURSOR_X_REG_L,x
                    lda       V.CurRow,u
                    cmpa      V.WHeight,u
                    blo       SwCurY
                    lda       V.WHeight,u
                    beq       SwCurY
                    deca
                    sta       V.CurRow,u
SwCurY              sta       VKY_TXT_CURSOR_Y_REG_L,x
                    lbra      SwDone
SwFail
                    puls      d
SwDone
                    clr       >gr.SwitchReq
                    puls      cc,d,x,y,u,pc

*******************************************************************
* TermTerm — copied from wildbits vtio. PullBuf uses CallGrfDrvNoPD
* (Term's Y is the device descriptor, not a path descriptor).
*******************************************************************
TermTerm
                    pshs      x,y,u
                    ldb       V.TermID,u
                    lda       #gr.TermSz
                    mul
                    ldx       #gr.TermTbl
                    leax      d,x
                    lda       T.Flags,x
                    bita      #T.Init
                    lbeq      TermNotInit
                    lda       T.Flags,x
                    bita      #T.Live
                    lbeq      TrmNotAct
                    ldb       V.TermID,u
                    pshs      b,x
                    clrb
FindNextTerm
                    cmpb      ,s
                    beq       SkipSelf
                    pshs      b
                    lda       #gr.TermSz
                    mul
                    ldx       #gr.TermTbl
                    leax      d,x
                    lda       T.Flags,x
                    bita      #T.Init
                    puls      b
                    bne       FoundNextTerm
SkipSelf
                    incb
                    cmpb      #G.TermMax
                    blo       FindNextTerm
                    lda       #$FF
                    sta       >gr.LiveTerm
                    ldd       #0
                    std       >D.KbdSta
                    puls      b,x
                    bra       FreeBuf
FoundNextTerm
                    pshs      b
                    lda       #gr.TermSz
                    mul
                    ldx       #gr.TermTbl
                    leax      d,x
                    lbsr      SetTermGrfPtrs
                    ldb       #GF.PullBuf
                    lbsr      CallGrfDrvNoPD
                    puls      b
                    pshs      b
                    lda       #gr.TermSz
                    mul
                    ldx       #gr.TermTbl
                    leax      d,x
                    lda       T.Flags,x
                    ora       #T.Live
                    sta       T.Flags,x
                    ldd       T.StatPtr,x
                    std       >D.KbdSta
                    std       >gr.VStaStorU
                    ldu       >D.KbdSta
                    lda       #1
                    sta       V.TermLive,u
                    puls      b
                    stb       >gr.LiveTerm
                    lda       V.CurCol,u
                    ldx       #TXT.Base
                    sta       VKY_TXT_CURSOR_X_REG_L,x
                    lda       V.CurRow,u
                    sta       VKY_TXT_CURSOR_Y_REG_L,x
                    puls      b,x
                    ldu       4,s
TrmNotAct
FreeBuf
                    ldb       T.Block,x
                    beq       ClearEntry
                    pshs      x
                    clra
                    tfr       d,x
                    ldb       #2
                    os9       F$DelRAM
                    puls      x
ClearEntry
                    clr       T.Flags,x
                    clr       T.Block,x
                    clra
                    clrb
                    std       T.StatPtr,x
                    dec       >gr.TermCnt
TermNotInit
                    clrb
                    puls      x,y,u,pc
                  ENDC

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
* First INIZ (/term): hardware + InitTerm (IT.WND=0). Old Write still owns $C2.
* Later named INIZ (/vtN): skip hardware, InitTerm only.
* Factory INIZ (/vt, IT.WND=$FF): skip hardware and InitTerm; SS.Open binds.
* Markers: $12FD='I' $12FE=$A5 $12FF=$5A entered
*          $12FC='P' InitDisplay returned
*          $12FB='Z' Init success rts
* InitTerm log $12F0-'T' $12F1=id $12F2=blk $12F3-4=X $12F5=active $12F6=cnt $12F7=K/E
Init
                    lda       #'I
                    sta       $12FD
                    lda       #$A5
                    sta       $12FE
                    lda       #$5A
                    sta       $12FF
                    pshs      y
                    lda       >gr.KbdInit
                    cmpa      #$FF
                    beq       SkipHw
                    lda       #'A
                    lbsr      dbgwrite
                    lda       #'B
                    lbsr      dbgwrite
                    stu       >D.KbdSta pointer to this device's static
                    leax      DefaultHandler,pcr get the default character processing routine
                    stx       V.EscVect,u store it in the vector
                    ldb       #$10      assume this foreground/background
                    stb       V.FBCol,u store it in our foreground/background color variable
                    clra                set D..
                    clrb                to $0000
                    std       V.CurRow,u set the current row and column
                    lda       #1
                    sta       V.TermLive,u first console writes Vicky $C2/$C3
                    clr       >gr.SwitchReq
                    lda       #'C
                    lbsr      dbgwrite
                    lbsr      InitDisplay initialize the display
                    lda       #'P
                    sta       $12FC
                    lbsr      InitSound initialize the sound
                    lbsr      InitKeyboard initialize the keyboad
                  IFGT    Level-1
                    lda       #'D
                    lbsr      dbgwrite
                    lbsr      InitMouse
                    lda       #'E
                    lbsr      dbgwrite
                    lbsr      InitGrfDrv
                    stu       >D.KbdSta
                    lbsr      InitPSG             $C4 silence in LUT 1
                    lbsr      InitDisplayMem gamma/font/pal/C2/C3 in LUT 1
                  ENDC
                    ldx       >D.AltIRQ get the current alternate IRQ vector
                    stx       >D.OrgAlt save it off in the original vector
                    leax      AltISR,pcr get our alternate interrupt service routine
                    stx       >D.AltIRQ and place it in the global vector
                    lbsr      ClearTermTbl
                    lda       #$FF
                    sta       gr.KbdInit
* InitGrfDrv cleared $1100-$12FF. Restore Init markers.
                    lda       #'I
                    sta       $12FD
                    lda       #$A5
                    sta       $12FE
                    lda       #$5A
                    sta       $12FF
                    lda       #'P
                    sta       $12FC
SkipHw
                    puls      y
                    lda       >gr.TermCnt
                    bne       HaveIdStart
                    lda       #'F
                    lbsr      dbgwrite
HaveIdStart
                    ldb       IT.WND,y  Y is the device descriptor (IOMAN Attach)
                    bpl       HaveId
* IT.WND=$FF is the /vt factory. Do not FindFreeTerm, do not InitTerm,
* never pass $FF into id*4. Slot is bound later by SS.Open.
                    bra       InitOk
HaveId
                    lbsr      InitTerm
                    bcs       InitFail
InitOk
                    lda       #'Z
                    sta       $12FB
                    clrb                clear the carry and error code
                    rts                 return to the caller
InitFail
                    rts                 carry and B already set

*******************************************************************
* ClearTermTbl - zero gr.TermTbl and counts. First INIZ only.
*******************************************************************
ClearTermTbl        pshs      d,x
                    ldx       #gr.TermTbl
                    ldb       #G.TermMax*gr.TermSz
ClrTT               clr       ,x+
                    decb
                    bne       ClrTT
                    clr       >gr.TermCnt
                    lda       #$FF
                    sta       >gr.LiveTerm
                    puls      d,x,pc

*******************************************************************
* FindFreeTerm - first table slot without T.Init. Returns B=id.
*******************************************************************
FindFreeTerm        clrb
FindFreeLp          cmpb      #G.TermMax
                    bhs       FindFreeFail
                    pshs      b
                    lda       #gr.TermSz
                    mul
                    ldx       #gr.TermTbl
                    leax      d,x
                    lda       T.Flags,x
                    bita      #T.Init
                    puls      b
                    beq       FindFreeOk
                    incb
                    bra       FindFreeLp
FindFreeOk          andcc     #^Carry
                    rts
FindFreeFail        comb
                    ldb       #E$MNF
                    rts

*******************************************************************
* InitTermStatic - per-terminal driver static that every INIZ needs
*******************************************************************
InitTermStatic      pshs      d,x,y
                    leax      DefaultHandler,pcr
                    stx       V.EscVect,u
                    ldb       #$10
                    stb       V.FBCol,u
                    ldd       #80*256+60
                    std       V.WWidth,u
                    clr       V.CurRow,u
                    clr       V.CurCol,u
                    clr       V.IBufH,u
                    clr       V.IBufT,u
                    clr       V.LastCh,u
                    clr       V.Reverse,u
                    clr       V.ST,u
                    ldx       >D.KbdSta
                    beq       InitTSDone
                    pshs      u
                    cmpx      ,s
                    puls      u
                    beq       InitTSDone
* Match the live console. InitDisplay starts 80x60; fcfg/DWSet often
* leaves /term at 80x30. Hardcoded 60 meant no scroll until row 60 and
* the last line sat below the DBL_Y visible area.
                    ldd       V.WWidth,x
                    std       V.WWidth,u
                    lda       V.FBCol,x
                    sta       V.FBCol,u
                    lda       V.ST,x
                    sta       V.ST,u
                    ldd       V.KeyDrvMPtr,x
                    std       V.KeyDrvMPtr,u
                    ldd       V.KeyDrvEPtr,x
                    std       V.KeyDrvEPtr,u
                    pshs      x
                    leax      V.KeyDrvStat,x
                    leay      V.KeyDrvStat,u
                    lda       #8
CopyKS              ldb       ,x+
                    stb       ,y+
                    deca
                    bne       CopyKS
                    puls      x
                  IFGT    Level-1
                    ldd       V.MSDrvMPtr,x
                    std       V.MSDrvMPtr,u
                    ldd       V.MSDrvEPtr,x
                    std       V.MSDrvEPtr,u
                  ENDC
InitTSDone          puls      d,x,y,pc

*******************************************************************
* BlankTermText - T.TXT spaces and T.TXTCOLOR = V.FBCol in the 16K.
* GF.Write WOp=WO.Blank in LUT 1. Never system MAPSLOT / MAPSLOT+1.
* Refuse V.TermBufBlk=0 (that aliases kernel block 0 at $4000).
* Probe $12EB-EF: 'B' blk txt0 fbcol 'K'
*******************************************************************
BlankTermText       pshs      cc,d,x,y
                    lda       V.TermBufBlk,u
                    beq       BTTSkip
                    sta       $12EC
                    sta       >gr.TermBlk
                    lda       #'B
                    sta       $12EB
                    lda       #C$SPAC
                    sta       >gr.WGlyph
                    sta       $12ED
                    lda       V.FBCol,u
                    sta       >gr.WColor
                    sta       $12EE
                    lda       #WO.Blank
                    sta       >gr.WOp
                    clr       >gr.WDest           WD.Buf
                    lbsr      CallWrite
                    lda       #'K
                    sta       $12EF
BTTSkip             puls      cc,d,x,y,pc

*******************************************************************
* InitTerm
* B = terminal id (0-8). Never $FF.
* First term: V.TermLive=1, no BlankTermText, no PushBuf.
* Later: V.TermLive=0, PushBuf live Vicky (MCR/font/CLUTs) into
* the new 16K, then BlankTermText. Without PushBuf, PullBuf restores
* uninitialized MCR and the display goes black after a one-frame flash.
*******************************************************************
InitTerm
                    pshs      x,y,u
                    lda       #'T
                    sta       $12F0
                    stb       $12F1
                    stb       V.TermID,u
                    lda       #gr.TermSz
                    mul
                    ldx       #gr.TermTbl
                    leax      d,x
                    lda       T.Flags,x
                    bita      #T.Init
                    bne       AlreadyOpen
                    pshs      x
                    ldd       #2
                    os9       F$AlHRAM
                    bcs       InitError
                    stx       $12F3
                    cmpx      #DAT.BlMx+1
                    bhs       AlHramD
                    tfr       x,d
AlHramD             puls      x
                    stb       $12F2
                    stb       T.Block,x
                    stb       V.TermBufBlk,u
                    lda       #T.Init
                    sta       T.Flags,x
                    stu       T.StatPtr,x
                    lbsr      InitTermStatic
                    lda       >gr.TermCnt
                    bne       NotFirst
                    lda       V.TermID,u
                    sta       >gr.LiveTerm
                    lda       #T.Init+T.Live
                    sta       T.Flags,x
                    lda       #1
                    sta       V.TermLive,u
                    bra       TermInited
NotFirst
                    clr       V.TermLive,u
                    lbsr      SetTermGrfPtrs
                    pshs      x,y,u
* CallGrfDrvNoPD does not wait if gr.Busy (gbusy unused). Overlapping
* factory I$Open PushBuf would Flip1 twice; spin would starve the holder.
*WaitPush            tst       >gr.Busy
*                    beq       PushGo
*                    ldx       #1
*                    os9       F$Sleep
*                    bra       WaitPush
PushGo              ldb       #GF.PushBuf
                    lbsr      CallGrfDrvNoPD
                    puls      x,y,u
                    lbsr      BlankTermText
TermInited
                    lda       V.TermLive,u
                    sta       $12F5
                    inc       >gr.TermCnt
                    lda       >gr.TermCnt
                    sta       $12F6
                    lda       #'K
                    sta       $12F7
                    clrb
                    andcc     #^Carry
                    puls      x,y,u,pc
AlreadyOpen
                    comb
                    ldb       #E$DevBsy
                    lda       #'E
                    sta       $12F7
                    stb       $12F8
                    puls      x,y,u,pc
InitError
                    puls      x
                    lda       #'E
                    sta       $12F7
                    stb       $12F8
                    puls      x,y,u,pc
 
* Term — glue #9: unlink keydrv/IRQ only when gr.TermCnt==0.
* Probe $12E0=remaining TermCnt $12E1='Q'
*
* Entry:
*    U  = address of device memory area
*
* Exit:
*    CC = carry set on error
*    B  = error code
*
Term
                  IFGT    Level-1
                    lbsr      TermTerm
                    lda       #'Q
                    sta       $12E1
                    lda       >gr.TermCnt
                    sta       $12E0
                    bne       TermEx
                  ENDC
                    ldx       >D.OrgAlt
                    stx       <D.AltIRQ
                    ldx       V.KeyDrvEPtr,u
                    cmpx      #0000
                    beq       NoUnlink
                    jsr       3,x
                    ldd       #0
                    std       V.KeyDrvEPtr,u
                    pshs      u
                    ldu       V.KeyDrvMPtr,u
                    os9       F$Unlink
                    puls      u
NoUnlink
                  IFGT    Level-1
                    ldx       V.MSDrvEPtr,u
                    cmpx      #0000
                    beq       NoMouse
                    ldd       #0
                    std       V.MSDrvEPtr,u
                    pshs      u
                    ldu       V.MSDrvMPtr,u
                    os9       F$Unlink
                    puls      u
                    ldd       #0
                    std       V.MSDrvMPtr,u
NoMouse
                    clr       >gr.KbdInit
                    ldd       #0
                    std       >D.KbdSta
                  ENDC
TermEx              clrb
                    rts

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
* SetWDest - WDest/TermBlk from V.TermLive / V.TermBufBlk.
* Snapshot into gr.W* before Flip1. Do not index U in LUT 1.
*******************************************************************
SetWDest            lda       V.TermLive,u
                    bne       SWVicky
                    lda       V.TermBufBlk,u
                    beq       SWVicky
                    sta       >gr.TermBlk
                    clr       >gr.WDest           WD.Buf
                    rts
SWVicky             lda       #WD.Vicky
                    sta       >gr.WDest
                    lda       V.TermBufBlk,u
                    beq       SWDestX
                    sta       >gr.TermBlk         keep SetBlkC2C3 off block 0
SWDestX             rts

* Snapshot is already in gr.W*. Wait then Flip1 GF.Write.
* Flip0 leaves U as the LUT-1 VSta alias ($6000 -> $A000). Restore
* the real static so RawWrite / scroll / EraseLine do not index $A000.
CallWrite           pshs      u
*                    lbsr      Waitwrite
                    ldb       #GF.Write
                    lbsr      CallGrfDrvNoPD
                    puls      u,pc

*******************************************************************
* BufCell - A=glyph, X=cell offset. Snapshot into GrfMem, Flip1
* GF.Write. Never maps system MAPSLOT. Dest: Vicky if TermActive
* or TermBufBlk=0, else 16K backup. Wait on gr.Busy like WaitPush;
* do not put the wait inside CallGrfDrvNoPD (AltISR cannot sleep).
*******************************************************************
BufCell             pshs      d,x,u
                    sta       >gr.WGlyph
                    stx       >gr.WOff
                    lda       V.FBCol,u
                    sta       >gr.WColor
                    clr       >gr.WOp             WO.Cell
                    bsr       SetWDest
                    bsr       CallWrite
                    puls      d,x,u,pc

* Same pattern as WaitPush. Saves X (cell offset).
WaitWrite           pshs      x
WWLp                tst       >gr.Busy
                    beq       WWGo
                    ldx       #1
                    os9       F$Sleep
                    bra       WWLp
WWGo                puls      x,pc

* FillCells - A=glyph, X=cell offset, Y=count. WO.Fill.
FillCells           pshs      d,x,y
                    sty       >gr.WCount
                    beq       FCSkip
                    sta       >gr.WGlyph
                    stx       >gr.WOff
                    lda       V.FBCol,u
                    sta       >gr.WColor
                    lda       #WO.Fill
                    sta       >gr.WOp
                    lbsr      SetWDest
                    lbsr      CallWrite
FCSkip              puls      d,x,y,pc

* Write — glyph paint is GF.Write (LUT 1). Cursor I/O stays here.
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
****************************  New Write Code ****************************
	            tst       V.WriteState,u		      
                    beq	      DefaultState
		    ldb	      V.EscCount,u
		    leax      V.EscParms,u
		    sta	      b,x
		    inc	      V.EscCount,u
		    dec	      V.EscNeed,u
		    beq	      EscCodeComplete
		    bra	      UpdateLiveCursor

DefaultState	    cmpa      #C$SPAC             is the character a space or greater?
                    lbcs      ChkESC              branch if not; go check for escape codes
		    ldy	      V.CurPos,u
		    ldb	      V.FBCol,u
		    tst	      V.TermLive,u
		    bne	      writelive
		    lbsr      CallWriteCharShadow
		    bra	      cont@
writelive	    lbsr      CallWriteCharLive
cont@		    inc	      V.CurPos,u            increment cursor poisition in text map
                    ldd       V.CurRow,u          get the current row and column (xy coordinates)
                    incb                          increment the column
                    cmpb      V.WWidth,u          compare it against the number of columns
                    blt       savecursor                  branch if we're less than
                    clrb                          else the column goes to 0
incrow              inca                          and we increment the row
                    cmpa      V.WHeight,u         compare it against the number of rows
                    blt       savecursor         branch if we're less than (don't clear the new line we're on)

* Always land on the last row of THIS term. CurRow can be 50 on a
* 80x30 after DWSet 80x60. Height 0 would decb to $FF and CpyBlk
* 80*255 bytes through LUT 1 $A000 (path table / DevTbl).
                    lda       V.WHeight,u
                    lbeq      CurHome
                    deca
                    clrb
                    pshs      d                   last row, column 0
                    ldd       V.WWidth,u
                    sta       >gr.WWidth
                    tstb
                    beq       noscroll
                    decb
                    beq       noscroll
		    ldd	      V.WWidth,u
		    ldy	      V.ScreenSize,u
 		    tst	      V.TermLive,u
		    bne	      scrolllive
		    lbsr      CallScrollShadow
		    bra	      noscroll
scrolllive	    lbsr      CallScrollLive
noscroll            puls      d

* clear line
clrline             std       V.CurRow,u          save the current row/column value
                    lbsr      EraseLine           erase the line
                    bra	      UpdateCursor        and return to the caller
savecursor          std       V.CurRow,u          save the current row/column value

UpdateLiveCursor    tst       V.TermLive,u
                    beq       WrNoCur
                    pshs      d
                    lda       V.CurCol,u
                    ldx       #TXT.Base
                    sta       VKY_TXT_CURSOR_X_REG_L,x
                    lda       V.CurRow,u
                    sta       VKY_TXT_CURSOR_Y_REG_L,x
                    puls      d
WrNoCur		    rts	      

****************************  End New Write Code ************************

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


**************************** OLD WRITE CODE BELOW ***********************
                    ldx       V.EscVect,u         get the escape vector address
                    jsr       ,x                  branch to it
                    tst       V.TermLive,u
                    beq       WrNoCur
                    pshs      d
                    lda       V.CurCol,u
                    ldx       #TXT.Base
                    sta       VKY_TXT_CURSOR_X_REG_L,x
                    lda       V.CurRow,u
                    sta       VKY_TXT_CURSOR_Y_REG_L,x
                    puls      d
* 6809 TST does not clear C. SCF Write does bcs after D$WRIT.
WrNoCur             andcc     #^Carry
                    rts

DefaultHandler      cmpa      #C$SPAC             is the character a space or greater?
                    lbcs      ChkESC              branch if not; go check for escape codes
RawWrite            pshs      a                   else save the character to write
                    lda       V.CurRow,u          get the current row
* DWSet 80x60 then 80x30 (or switch) can leave CurRow past WHeight.
                    cmpa      V.WHeight,u
                    blo       rwrowok
                    lda       V.WHeight,u
                    beq       rwrow0
                    deca
rwrow0              sta       V.CurRow,u
rwrowok             ldb       V.WWidth,u          and the number of columns
                    mul                           calculate the row we should be on
                    addb      V.CurCol,u          add in the column
                    adca      #0                  and add in 0 with carry in case of overflow
* Here, D has the location in the screen where the next character goes.
                    tfr       d,x                 X = cell offset
                    puls      a                   get the character to write
                    lbsr      BufCell             GF.Write in LUT 1
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
* Always land on the last row of THIS term. CurRow can be 50 on a
* 80x30 after DWSet 80x60. Height 0 would decb to $FF and CpyBlk
* 80*255 bytes through LUT 1 $A000 (path table / DevTbl).
                    lda       V.WHeight,u
                    lbeq      CurHome
                    deca
                    clrb
                    pshs      d                   last row, column 0
                    ldd       V.WWidth,u
                    sta       >gr.WWidth
                    tstb
                    beq       noscroll
                    decb
                    beq       noscroll
                    mul
                    cmpd      #4800
                    bls       scntok
                    ldd       #4800
scntok              std       >gr.WCount
                    lda       #WO.Scroll
                    sta       >gr.WOp
                    lbsr      SetWDest
                    lbsr      CallWrite
noscroll            puls      d
                    else
                    clra                          just clear the row (goes to top)
                    endc
* clear line
clrline             std       V.CurRow,u          save the current row/column value
                    lbsr      EraseLine           erase the line
                    rts                           and return to the caller
ok                  std       V.CurRow,u          save the current row/column value
ret                 rts                           and return to the caller


*************************  END OLD WRITE CODE **********************



;;; CurOn
;;;
;;; Turns the cursor on.
;;;
;;; Code: 05 21
CurOn               tst       V.TermLive,u
                    beq       CurOnX
                    ldx       #TXT.Base
                    lda       VKY_TXT_CURSOR_CTRL_REG,x
                    ora       #Vky_Cursor_Enable
                    sta       VKY_TXT_CURSOR_CTRL_REG,x
CurOnX              rts

;;; CurOff
;;;
;;; Turns the cursor off.
;;;
;;; Code: 05 20
CurOff              tst       V.TermLive,u
                    beq       CurOffX
                    ldx       #TXT.Base
                    ldb       VKY_TXT_CURSOR_CTRL_REG,x
                    andb      #~Vky_Cursor_Enable
                    stb       VKY_TXT_CURSOR_CTRL_REG,x
CurOffX             rts



;;; EraseLin
;;;
;;; Erase the current line.
;;;
;;; Code: 03
EraseLine           clrb                          start erasing at column 0
                    lda       V.CurRow,u          of the current row
* Entry:  A = The row to erase.
*         B = The column to start erasing on.
EraseLineCore       pshs      b                   save the start column
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
                    lda       #C$SPAC
                    lbsr      FillCells           GF.Write WOp=WO.Fill
                    rts

;;; ClrScrn
;;;
;;; Clears the entire screen and homes the cursor.
;;;
;;; Code: 0C
* One FillCells. Height 0 used to loop 256 EraseLine (row 255*80
* writes LUT 1 $A000). 80x60 was 60 Flip1s; that raced factory
* PushBuf on D.CCStk.
ClrScrn             lda       V.WHeight,u
                    beq       CurHome
                    ldb       V.WWidth,u
                    beq       CurHome
                    mul
                    cmpd      #4800
                    bls       CSFill
                    ldd       #4800
CSFill              tfr       d,y
                    ldx       #0
                    lda       #C$SPAC
                    lbsr      FillCells
                    bra       CurHome

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
                    lbra      EraseLineCore       go erase from that point to the end of line

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
                    tfr       d,x                 X = cell offset
                    ldy       #1
                    lda       #C$SPAC
                    lbsr      FillCells           GF.Write WOp=WO.Fill
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
* DBL_Y/X belong to THIS term. Do not poke live Vicky when inactive
* (that made /term 80x60, and the next PushBuf saved it into the
* active term's V.V_MCR). PullBuf restores V.V_MCR.
SetWin              stx       V.WWidth,u
                    pshs      b
                    ldx       #TXT.Base
                    lda       V.TermLive,u
                    beq       SetWinSt
                    ldb       MASTER_CTRL_REG_H,x
                    andb      #~(DBL_Y|DBL_X|CLK_70)
                    orb       ,s
                    stb       MASTER_CTRL_REG_H,x
                    stb       V.V_MCR+1,u
                    puls      b,pc
SetWinSt            ldb       V.V_MCR+1,u
                    andb      #~(DBL_Y|DBL_X|CLK_70)
                    orb       ,s
                    stb       V.V_MCR+1,u
                    puls      b,pc

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
ChgForePal          clrb
                    stb       V.EscParms+4,u
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

* Snapshot RGBA / PRN / FG-BG into gr.W*, then GF.Write WO.Pal.
* Keep V.EscVect. Do not map TEXT_LUT_BLK at system MAPSLOT.
Do1B60_Param4       pshs      d,x
                    sta       >gr.WCount+1        alpha
                    lda       V.EscParms+3,u      blue
                    sta       >gr.WOff
                    lda       V.EscParms+2,u      green
                    sta       >gr.WOff+1
                    lda       V.EscParms+1,u      red
                    sta       >gr.WCount
                    lda       V.EscParms+0,u      PRN
                    sta       >gr.WGlyph
                    lda       V.EscParms+4,u      0=FG 1=BG
                    sta       >gr.WWidth
                    lda       #WO.Pal
                    sta       >gr.WOp
                    lbsr      SetWDest
                    lbsr      CallWrite
                    puls      d,x
                    lbra      ResetHandler

;;; ChgBackPal
;;;
;;; Change a background palette register.
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
ChgBackPal          ldb       #1
                    stb       V.EscParms+4,u
                    leax      Do1B60_Param0,pcr
                    lbra      SetHandler

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
                    ifgt      Level-1
                    cmpa      #SS.Mouse
                    beq       GSMouse
                    cmpa      #SS.DScrn           SS.DScrn MCR to display text or graphics
                    lbeq      GSDScrn
                    cmpa      #SS.FntChar
                    lbeq      GSFntChar       
                    endc
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

                    ifgt      Level-1
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
GSMouse             lda       MS_XH
                    ldb       MS_XL
                    std       R$X,x
                    lda       MS_YH
                    ldb       MS_YL
                    std       R$Y,x
                    lda       V.MSButtons,u
                    sta       R$A,x
                    clrb                          clear carry
                    rts   
                    endc
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
                  IFGT    Level-1
                    cmpa      #SS.Open            path open (SCF); /vt factory here
                    lbeq      SSOpen
                  ENDC
                    cmpa      #SS.SSig            send signal on data ready?
                    lbeq      SSSig               yes, go process
                    cmpa      #SS.Relea           release signal on data ready?
                    lbeq      SSRelea             yes, go process
                    cmpa      #SS.DMAFill         DMA Fill?
                    lbeq      SSDMAFill
                    cmpa      #SS.Tone
                    lbeq      SSTone
                    ifgt Level-1                                            
                    cmpa      #SS.AScrn           SS.AScrn allocated bitmap
                    lbeq      SSAScrn
                    cmpa      #SS.DScrn           SS.DScrn MCR to display text or graphics
                    lbeq      SSDScrn
                    cmpa      #SS.FScrn           SS.FScrn frees bitmap memory
                    lbeq      SSFScrn
                    cmpa      #SS.PScrn           SS.PScrn to set up layers
                    lbeq      SSPScrn
                    cmpa      #SS.Palet
                    lbeq      SSPalet             SS.Palet assigns palette to bitmap
                    cmpa      #SS.DfPal
                    lbeq      SSDfPal             SS.DfPal defines and populates a CLUT
                    cmpa      #SS.FntLoadF
                    lbeq      SSFntLoadF
                    cmpa      #SS.FntChar
                    lbeq      SSFntChar
                    endc                                            
                    comb                          set the carry
                    ldb       #E$UnkSvc           load the "unknown service" error
                    rts                           return

                  IFGT    Level-1
* SS.Open — SCF calls this on every I$Open.
* Named (/term, /vt1../vt8): success (already InitTerm'd).
* Factory (/vt, IT.WND=$FF): F$SLink /vtN, InitTerm id 1-8, swap
* V$DESC, UnLink factory. Name at $12D8 (not $1200). Y = system
* DAT image; tosysproc so the module maps in system space.
* Never pass $FF into id*4. Slot 0 is /term; start at id 1.
* Probe $12DC='O' $12DD=IT.WND $12DE=V.TermID $12DF=TermCnt
* $12D5=id $12D6=T.Flags $12D7=link/InitTerm err $12D8-DA=vtN
SSOpen              ldx       PD.DEV,y
                    ldx       V$DESC,x
                    ldb       IT.WND,x
                    stb       $12DD
                    lda       #'O
                    sta       $12DC
                    tstb
                    lbpl      SSOpenNamed
                    pshs      x,y,u
                    ldb       #1
SSOpenFind          stb       $12D5
                    cmpb      #G.TermMax
                    bhs       SSOpenNone
                    pshs      b
                    lda       #gr.TermSz
                    mul
                    ldx       #gr.TermTbl
                    leax      d,x
                    lda       T.Flags,x
                    sta       $12D6
                    bita      #T.Init
                    puls      b
                    beq       SSOpenGot
                    incb
                    bra       SSOpenFind
SSOpenNone          ldb       #E$MNF
                    stb       $12D7
                    comb
                    puls      x,y,u,pc
SSOpenGot           lda       #'v
                    sta       $12D8
                    lda       #'t
                    sta       $12D9
                    tfr       b,a
                    adda      #$B0
                    sta       $12DA
                    pshs      b
                    leas      -2,s
                    lbsr      tosysproc
                    ldx       >D.SysPrc
                    leay      P$DATImg,x
                    ldx       #$12D8
                    lda       #Devic+Objct
                    os9       F$SLink
                    lbsr      toproc
                    leas      2,s
                    bcc       SSOpenLnk
                    stb       $12D7
                    puls      b
                    incb
                    lbra      SSOpenFind
SSOpenLnk           pshs      u
                    ldb       2,s
                    ldu       7,s
                    lbsr      InitTerm
                    bcs       SSOpenITFail
                    puls      u
                    ldy       3,s
                    ldx       PD.DEV,y
                    stu       V$DESC,x
                    ldu       1,s
                    os9       F$UnLink
                    ldu       5,s
                    lda       V.TermID,u
                    sta       $12DE
                    lda       >gr.TermCnt
                    sta       $12DF
                    leas      7,s
                    clrb
                    andcc     #^Carry
                    rts
SSOpenITFail        stb       $12D7
                    puls      u
                    pshs      cc,b
                    os9       F$UnLink
                    puls      cc,b
                    leas      1,s
                    puls      x,y,u,pc
SSOpenNamed         lda       V.TermID,u
                    sta       $12DE
                    lda       >gr.TermCnt
                    sta       $12DF
                    clrb
                    andcc     #^Carry
                    rts
                  ENDC

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

                    ifgt      Level-1
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
DoFontGetSet        pshs      a 
                    ldd       R$Y,x               get the char# and mulitply by 8
                    lslb
                    rola
                    lslb
                    rola
                    lslb
                    rola
                    tfr       d,y                 transfer result to y
                    lda       R$A,x               add offset for font bank 0 or 1
                    beq       font0@
font1@              leay      FONT_1_OFFSET,y
                    bra       cont@
font0@              leay      FONT_0_OFFSET,y
cont@               leas      -2,s                reserve 2 bytes for mapped address
                    pshs      x,u                 preserve x,u
                    ldx       #FONT_BLK           map in $C1
                    ldb       #$01                map 1 block at address x (x set on entry)
                    os9       F$MapBlk            map block into caller DAT
                    bcc       mapgood@            if success, then continue
                    puls      x,u                 else: error
                    puls      a,x,pc              clean stack and return if error
mapgood@            stu       4,s                 store mapped address on stack [XUMO]
                    ldd       4,s                 load into d and add to y
                    leay      d,y                 Y now contains address of font char
                    puls      x,u                 restore x,u [MO]
                    pshs      x,u
                    ldx       <D.Proc
                    lda       P$Task,x            copy data from caller to caller memory
                    ldb       P$Task,x
                    ldx       ,s
                    tst       6,s                 Get or Set?
                    beq       getfont@            0 = getfont
                    ldx       R$X,x               setfont: source is x
                    tfr       y,u                 destination is y
                    bra       contfont@
getfont@            ldu       R$X,x               getfont: destination is x
                    tfr       y,x                 source is y
contfont@           ldy       #8                  copy 8 bytes
                    os9       F$Move
                    puls      x,u                 error or not, clear block and return
                    puls      u                   pull blk addr and getset flag
                    puls      a
                    ldb       #$01
                    os9       F$ClrBlk
                    rts

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

SSFntLoadF          ldy       R$Y,x
                    beq       font0@
font1@              ldy       #$800               FONT_1_OFFSET   $0800
                    bra       storeaddr@
font0@              ldy       #FONT_0_OFFSET      $0000
storeaddr@          pshs      y                   store font offset on stack [O]      
                    leas      -2,s                reserve 2 bytes on stack for mapped addr [MO]
* s= ADDR|OFFSET|                   
*                   ****      map block into user dat and store address on stack
                    pshs      x,u                 preserve x,u
                    ldx       #FONT_BLK           map in $C1
                    ldb       #$01                map 1 block at address x (x set on entry)
                    os9       F$MapBlk
                    bcc       mapgood@            if success, then continue
                    puls      x,u                 else: error
                    lbra      error@
mapgood@            stu       4,s                 store mapped address on stack [XUMO]
                    puls      x,u                 restore x,u [MO]
*                   ****      open file to read             
endcopy@            ldx       R$X,x               pointer to file name in caller memory
                    lda       #READ.              READ access mode
                    os9       I$Open              
                    bcc       modulecheck@
                    bra       errormap@
* Verify that file is module.
* Load file's first two bytes onto the stack to verify and check for $87DC
modulecheck@        leas      -2,s                 add space to stack to store 2 bytes [DMO]
                    leax      ,s                   load x with stack address
                    lbsr      Rd2B2Mem
                    puls      x                    load x with the data [MO]
                    cmpx      #$87CD               check if module
                    bcc       getstart@            if module, get start of data
                    ldb       #3
                    bra       errorclose@          else, error
* Module header byte $09-0A = Execution Offset.
* This is the start of the data in a data module
getstart@           pshs      u                    seek to data start address in file [UMO]
                    ldx       #$00                 set high byte addr
                    ldu       #$09                 set low byte
                    os9       I$Seek
                    bcc       readaddr@            if success, read font
                    puls      u                    else error  [MO]
                    ldb       #4
                    bra       errorclose@
* s= u|addr|offset                  
readaddr@           leas      -2,s                 add 2 bytes stack storage [DUMO]
                    leax      ,s                   use the 2 bytes in stack to store addr
                    lbsr      Rd2B2Mem             read 2 bytes from file
                    bcc       seekaddr@            if success, seek to data address
                    leas      4,s                  else: clean stack and error [MO]
                    bra       errorclose@
* s= addr|u|addr|offset             
seekaddr@           puls      u                    load u with low byte addr [UMO]
* s= u|addr|offset
                    ldx       #0                   load x high byte
                    os9       I$Seek
                    puls      u                    restore u [MO]
* s=addr|offset             
*                   ldx       ,s                   ldx with mapblock address
                    pshs      a                    store path# on stack [AMO]
                    ldd       1,s                  put offset in d
                    addd      3,s
                    tfr       d,x
*                   leax      d,x                  add offset to x
                    puls      a                    restore path# [MO]
                    ldy       #$800                read 2K of font data into it
                    os9       I$Read               a=path x=addr y=#bytes
errorclose@         pshs      b                    [BMO]
                    os9       I$Close              close the file
                    puls      b                    [MO]
errormap@           ldu       ,s
                    pshs      b
                    ldb       #$01
                    os9       F$ClrBlk             Clear block from user space
                    puls      b
error@              leas      4,s                  clear stack
                    tstb
                    beq       quit@
                    coma
quit@               rts
                    

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
Rd2B2Mem            pshs      cc                  push cc and mask interrupts
                    orcc      #IntMasks
                    ldy       <D.Proc             ldy with current process descriptor
                    pshs      y                   store current proc descriptor on stack
                    ldy       <D.SysPrc           copy system proc descriptor to current
                    sty       <D.Proc
                    ldy       #$02                read 2 bytes from file 
                    os9       I$Read
                    puls      y                   pull current proc descriptor from stack
                    sty       <D.Proc             and save it back
                    bcs       errnomap@           if I$Read error, then handle error
                    puls      cc,pc               if no error, pull cc and return
errnomap@           puls      cc                  if error, pull cc
                    coma                          set carry bit
                    rts                           and return

                    
;;; SS.AScrn
;;;
;;; Allocate a bitmap screen
;;;
;;; Entry: R$Y = bitmap# (0-2)
;;;        R$X = screentype (0=320x240, 1=320x200)
;;;
;;; Exit:  B = A non-zero error code.
;;;       CC = Carry flag clear to indicate success
;;;        X = Starting Page# of bitmap address
SSAScrn             lda       R$Y+1,x             load the bitmap number
                    lsla                          multiply by 2
                    leay      V.BM0BLK,u
                    lda       a,y                 see if there is a current block number
                    beq       NewBitMap@          if zero, then no bitmap, make a new one
                    ldb       #E$WADef            error: bitmap already defined
                    sta       R$X+1,x             store the bitmap block# in X
                    clr       R$X,x
                    bra       error@
NewBitMap@          ldb       R$X+1,x             get the window type (0 or 1)
                    beq       tenblocks@          need 10 blocks for 320x240
eightblocks         ldb       #$08                need 8 blocks for 320x200
                    bra       GetMem@
tenblocks@          ldb       #10                 need 10 8k Blocks from highram
GetMem@             os9       F$AlHRAM            allocate ram, put starting block# in D
                    bcc       map@                check for error, continue if no error
                    ldb       #E$MFull            set error code to Memory Full error and return
                    bra       error@
*                   **** Store starting block# for bitmap in V.BMXBlk
map@                lda       R$Y+1,x             load bitmap@
                    lsla                          multiply by 2 to get correct index    
                    leay      V.BM0Blk,u          calc address for block storage BM0,BM1 or BM2
                    stb       a,y                 store block # in V.[BMX]Block where [BMX] is BM00, BM11 or BM2w
                    clra
                    std       R$X,x               store block # in X for return value
* Snapshot BM# / phys addr / enable; GF.Write WO.BmReg in LUT 1.
                    lda       R$Y+1,x
                    sta       >gr.WGlyph
                    lbsr      Blk2Addr
                    std       >gr.WOff
                    lda       #%00000001
                    sta       >gr.WColor
                    lda       #WB.AScrn
                    sta       >gr.WWidth
                    lda       #WO.BmReg
                    sta       >gr.WOp
                    lbsr      CallWrite
                    clrb
                    andcc     #^Carry
                    rts
error@              coma                          set carry bit on error
end@                rts             


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
GSDScrn             clr       R$X,x               load MCR low byte
                    clr       R$Y,x               load MCR high byte
                    ldy       #TXT.Base
mcrlbit@            lda       MASTER_CTRL_REG_L,y   store new MCR low byte
                    sta       R$X+1,x                 store copy in driver variables
mcrhbit@            ldb       MASTER_CTRL_REG_H,y   store new MCR High byte     
                    stb       R$Y+1,x           store copy in driver variables
end@                clrb
                    rts

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
SSDScrn             lda       R$X+1,x               load MCR low byte
                    ldb       R$Y+1,x               load MCR high byte
                    ldy       #TXT.Base
mcrlbit@            cmpa      #FX_OMIT              If omit, don't change
                    beq       mcrhbit@
                    sta       MASTER_CTRL_REG_L,y   store new MCR low byte
                    sta       V.V_MCR,u             store copy in driver variables
mcrhbit@            cmpb      #FT_OMIT              if omit, don't change
                    beq       end@
                    stb       MASTER_CTRL_REG_H,y   store new MCR High byte     
                    stb       V.V_MCR+1,u           store copy in driver variables
end@                clrb
                    rts

;;;  SS.PScrn
;;;  Position Screen Layers
;;;
;;;  Set layer to display a screen
;;;
;;; Entry: R$X = layer (0-2)
;;;        R$Y = bitmap# (0-2), tilemap (4-6)
;;;        
;;;
;;; Exit:  B = A non-zero error code.
;;;       CC = Carry flag clear to indicate success
;;;
SSPScrn             ldy       R$X,x                 x=layer
                    lda       VKY_LAYER_CTRL_0
sl0@                cmpy      #$00                  test for Screen layer 0
                    bne       sl1@                  if not, go to layer 1
                    anda      #%11110000            this is L0, clear L0 values
                    adda      R$Y+1,x
                    sta       VKY_LAYER_CTRL_0      store them
                    bra       end@
sl1@                cmpy      #$01                  test for layer 1
                    bne       sl2@                  if not, go to layer 2
                    anda      #%00001111            clear the Layer1 bits
                    sta       VKY_LAYER_CTRL_0
                    ldb       R$Y+1,x
                    lslb                            shift bitmap# 4 bits for layer 1
                    lslb
                    lslb
                    lslb
                    addb      VKY_LAYER_CTRL_0      add it
                    stb       VKY_LAYER_CTRL_0      store it
                    rts
sl2@                cmpy      #$02                  test for Layer2
                    bne       end@
                    ldb       R$Y+1,x
                    stb       VKY_LAYER_CTRL_1      store BM# or TM# in L2
                    clrb
end@                rts

;;; SS.FScrn
;;;
;;; Free a bitmap screen
;;;
;;; Entry: R$Y = bitmap# (0-2)
;;;
;;; Exit:  B = A non-zero error code.
;;;       CC = Carry flag clear to indicate success
SSFScrn             lda       R$Y+1,x              get the bitmap#
                    lsla                           multiply by 2
                    leay      V.BM0Blk,u
                    pshs      x
                    ldb       a,y                  load block# for bitmapX
                    bne       deallocate@          if not zero, continue
                    ldb       #E$WUndef            window undefined
                    coma
                    puls      x,pc
deallocate@         clra
                    tfr       d,x
                    ldy       #TXT.Base
                    lda       MASTER_CTRL_REG_H,y  load in Vicky_MCR
                    bita      #%00000001           Test for CLK_70
                    beq       CLK_60@
CLK_70@             ldb       #$08                 clk_70 only has 8 blocks
                    bra       cont@
CLK_60@             ldb       #$0A                 clk_60 is 10 blocks
cont@               os9       F$DelRAM             Free RAM from starting at blockX
                    puls      x                    recover x
                    lda       R$Y+1,x              get the bitmap#
                    lsla                           multiply by 2
clr_bmvar@          leay      V.BM0Blk,u           clear the bitmap storage
                    leay      a,y
                    clra
                    sta       ,y
                    lda       R$Y+1,x
                    sta       >gr.WGlyph
                    lda       #WB.FScrn
                    sta       >gr.WWidth
                    lda       #WO.BmReg
                    sta       >gr.WOp
                    lbsr      CallWrite
                    clrb
                    andcc     #^Carry
                    rts

;;; SS.Palet
;;; Assign Palette to Bitmap
;;;
;;; Assign CLUT# to Bitmap#
;;;
;;; Entry: R$Y = bitmap# (0-2)
;;;        R$X = CLUT (0-3)
;;;
;;; Exit:  B = A non-zero error code.
;;;       CC = Carry flag clear to indicate success
;;;
SSPalet             lda       R$Y+1,x
                    sta       >gr.WGlyph
                    ldd       R$X,x               d now has CLUT#
                    orcc      #Carry              set carry bit
                    rolb                          shift B, and rotate in enable it
                    stb       >gr.WColor
                    lda       #WB.Palet
                    sta       >gr.WWidth
                    lda       #WO.BmReg
                    sta       >gr.WOp
                    lbsr      CallWrite
                    clrb
                    andcc     #^Carry
                    rts



;;; SS.DfPal
;;; Define Palette and populate a CLUT from Memory Module
;;;
;;; Entry: R$X = CLUT # (0-3)
;;;        R$Y = pointer to location of data in caller process
;;;        (Caller must load data module)
;;;
;;; Exit:  B = A non-zero error code.
;;;       CC = Carry flag clear to indicate success
SSDfPal             pshs      a,x,y,u
*                   **** Map in $C1 for CLUT Registers
                    pshs      x
                    ldx       #$C1              
                    lbsr      mapblock
                    puls      x
                    bcs       end@                if error, end and return error code
*                   **** Calculate CLUT offset              
                    pshs      u                   push map logical addr
                    lda       R$X+1,x
                    lsla                          multiply by 2 so index works
                    pshs      x                   push pointer to caller Regs
                    leax      clutlookup,pcr
                    ldd       a,x
                    leau      d,u                 ldu with offset for CLUT
*                   **** Start F$Move (with U from above)
                    ldx       ,s                  load pointer to caller Regs
                    ldx       R$Y,x               x=Get pointer to caller data
                    ldy       <D.Proc             Get caller process
                    lda       P$Task,y            a=source Task# (Caller)
                    ldb       <D.SysTsk           b=dest Task# (System)
                    ldy       #$400               moving 1K
                    os9       F$Move              copy data
                    bcs       errormove@          return if error
*                   **** Exit Move
                    puls      x
noerror@            puls      u
                    bsr       clearblock
                    clrb                          no error code
                    bra       end@
errormove@          puls      x
                    puls      u                   come here on F$Move error
                    bsr       clearblock
                    coma                          set carry bit on error
end@                puls      u,y,x,a,pc

clutlookup          fdb       $1000,$1400,$1800,$1C00


;;; mapblock
;;; Map a block into the system process map
;;;
;;; Entry:  X = block to map (like $C1)
;;;
;;; Exit:   U = address of first block
;;;         B = a non-zero error code (F$MapBlk)
;;;        CC = carry flag clear=success set=error
;;;
;;; F$MapBlk only works to map for the current processin D.Proc
;;; To use F$MapBlk for the system, assign system to D.Proc
;;; Call F$MapBlk, then change the processes back
;;; Make sure to mask interrupts so processes don't switch while
;;; the change is happening
;;;
;;; Does not preserve a,b,x,y,u
mapblock            pshs      cc                  push cc and mask interrupts
                    orcc      #IntMasks
                    ldy       <D.Proc             ldy with current process descriptor
                    pshs      y                   store current proc descriptor on stack
                    ldy       <D.SysPrc           copy system proc descriptor to current
                    sty       <D.Proc
                    ldb       #$01                map 1 block at address x (x set on entry) 
                    os9       F$MapBlk
                    puls      y                   pull current proc descriptor from stack
                    sty       <D.Proc             and save it back
                    bcs       errnomap@           if F$MapBlok error, then handle error
                    puls      cc,pc               if no error, pull cc and return
errnomap@           puls      cc                  if error, pull cc
                    coma                          set carry bit
                    rts                           and return
;;; clearblock
;;; clear a mapped block from the system process map
;;;
;;; Entry:  U = address of first block to clear
;;;
;;; Exit:   Nothing
;;;
;;; F$ClrBlk only works with the current process, so assign
;;; system process to current process, clear the block
;;; then switch it back
;;;
;;; Does not preserve a,b

clearblock          pshs      cc
                    orcc      #IntMasks           u=logical address of block on entry
                    ldd       <D.Proc
                    pshs      d
                    ldd       <D.SysPrc
                    std       <D.Proc
                    ldb       #$01                only clearing 1 block
                    os9       F$ClrBlk            U=logical addr, B=# of blocks
                    puls      d
                    std       <D.Proc
                    puls      cc,pc

* Block to Address: Convert block# to high 16 bits in D
* b = block#, a = 0.  d = high 16 bits of address
* Try to replace with math coprocessor multiply in Vicky?
Blk2Addr            clra                          clear a, block # is in b
                    lslb                          multiply block# by $20 to get top 16 bits x2
                    rola                          of physical address (ex $3F*$20 = $07E0)
                    lslb                          x4
                    rola                          roll carry into a
                    lslb                          x8
                    rola                          roll carry into a
                    lslb                          x16
                    rola                          roll carry into a
                    lslb                          x32 ($20)
                    rola
                    rts
                    endc

* One glyph at $C2 cell 1 via GF.Write. No-op before InitGrfDrv
* (gr.Entry=0). Never system MAPSLOT. CallWrite clobbers Y; Init
* reads IT.WND,y after the first-INIZ 'F' breadcrumb.
dbgwrite
                    pshs      d,x,y,u
                    ldx       >gr.Entry
                    beq       dbgdn
                    sta       >gr.WGlyph
                    ldx       #1
                    stx       >gr.WOff
                    lda       #$10
                    sta       >gr.WColor
                    lda       #WD.Vicky
                    sta       >gr.WDest
                    clr       >gr.WOp
                    lbsr      CallWrite
dbgdn               puls      d,x,y,u,pc

                    emod
eom                 equ       *
                    end
