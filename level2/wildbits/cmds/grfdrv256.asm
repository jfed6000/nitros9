*******************************************************************
* GrfDrv256 - Graphics Driver for F256
*******************************************************************
                    nam       GrfDrv256
                    ttl       Wild 256 Graphics Driver
                    
                    use       defsfile
		    use	      wildbits_vtio.d
                    
                    
tylg        set   Systm+Objct
atrv        set   ReEnt+rev
rev         set   $00
edition     set   1
             
            mod   eom,name,tylg,atrv,entry,size
size        equ   .       
                    
name        fcs   /grfdrv256/
            fcb   edition
            
*******************************************************************
* Main Entry Point
*
* Entry: B = Function code (from vtio via CallGrfDrv)
*        Other registers = function parameters
*        U = GrfMem pointer ($1100)
*        DP = $11 (set by caller)
*******************************************************************
entry	            equ	      *
* Set DP to GrfMem area
                    pshs      a
                    lda       #GrfMem/256         ; DP = $11
                    tfr       a,dp
                    puls      a

		    lds	      >GrfMem+gr.Stack
                    tstb
		    bra	      Init
* Dispatch to function
                    leax       FuncTbl,pcr
                    aslb                          ; B*2 for word table
                    jmp       [b,x]
                    
*******************************************************************
* Function Dispatch Table
*******************************************************************
FuncTbl
                    fdb       Init        ; $00
                    fdb       Term        ; $02
                    fdb       SetScr      ; $04
*                    fdb       GetScr      ; $06
                    fdb       Write       ; $08
                    fdb       Read        ; $0A
                    fdb       GetStat     ; $0C
                    fdb       SetStat     ; $0E
                    fdb       SetMode     ; $10
                    fdb       SetPal      ; $12
                    fdb       Blit        ; $14
                    fdb       Fill        ; $16
                    fdb       Line        ; $18
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
		    lda		#$99
		    sta		$1230
                    clrb                          ; No error
                    bra SysRet          ; Return to caller
                    
*******************************************************************
* Term - Terminate graphics driver
*******************************************************************
Term
* Cleanup graphics hardware
* Reset to text mode
* etc.
                    
                    clrb
                    bra SysRet
                    
*******************************************************************
* SetScr - Set screen mode
*
* Entry: A = Screen number (0-4)
*        X = Mode/parameters
*******************************************************************
SetScr
* Validate screen number
                    cmpa      #5
                    bhs       screrr
                    
* Set screen mode
* ... F256-specific code ...
                    
                    clrb
                    bra SysRet
                    
screrr
                    ldb       #E$Param
                    coma                          ; Set carry
                    bra SysRet
                    
*******************************************************************
* Write - Write character/data to screen
*
* Entry: A = Character/data
*        B = Attributes (optional)
*        X = Position (optional)
*******************************************************************
Write
* Write to current screen
* ... F256-specific code ...
                    
                    clrb
                   bra SysRet 
                    
*******************************************************************
* Read - Read character/data from screen
*******************************************************************
Read
* Read from current screen
* ... F256-specific code ...
                    
                    clrb
                    bra SysRet 
                    
*******************************************************************
* GetStat - Get status
*******************************************************************
GetStat
* Return status info
                    clrb
                    bra SysRet 
                    
*******************************************************************
* SetStat - Set status
*******************************************************************
SetStat
* Set status/configuration
                    clrb
                    bra SysRet 
                    
*******************************************************************
* F256-Specific Functions
*******************************************************************
SetMode
* Set video mode
                    clrb
                    bra SysRet 
                    
SetPal
* Set palette
                    clrb
                    bra SysRet 
                    
Blit
* Bitmap blit
                    clrb
                    bra SysRet 
                    
Fill
* Fill rectangle
                    clrb
                    bra SysRet 
                    
Line
* Draw line
                    clrb
                    bra SysRet 

*******************************************************************
* SysRet - Return to System
* Call this instead of jmp [>D.Flip0]
*******************************************************************
SysRet
                    tfr       cc,a                ; Save CC status
                    orcc      #IntMasks           ; Disable interrupts
                    ldx       >GrfMem+gr.Stack    ; Get saved system stack
                    clr       >GrfMem+gr.Busy     ; Clear busy flag
                    
* Reset DP to 0 for system
                    pshs      a
                    clra
                    tfr       a,dp
                    puls      a
                    
                    jmp       [>D.Flip0]          ; Return to system

                    
*******************************************************************
* Helper Routines
*******************************************************************

* Add your F256-specific helper routines here

                    emod
eom                 equ       *
                    end