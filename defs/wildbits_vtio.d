                  IFNE    WILDBITS_VTIO.D-1
WILDBITS_VTIO.D     SET       1

********************************************************************
* vtio definitions for the Wildbits 6809
*
* Everything that the vtio driver needs is defined here, including
* static memory definitions.

* Constant definitions.
KBufSz              EQU       8         the circular buffer size

* Driver static memory.
                    ORG       V.SCF
V.CurRow            RMB       1         current row where the next character goes
V.CurCol            RMB       1         current column where the next character goes
V.CurPos	    RMB	      2		offset position of cursor in textmap
V.CapsLck           RMB       1         CAPS LOCK key up/down flag ($00 = up)
V.KySns             RMB       1         key sense flags
V.LastCh            RMB       1         Last character for key repeat
V.CurLastCh         RMB       1
V.KRTimer           RMB       1         Key Repeat Timer
V.LEDStates         RMB       1         PS/2 LED flags (bit 2 = CAPS Lock, bit 1 = NUM Lock, bit 0 = Scroll Lock)
V.WriteState        RMB       1         state of write
V.EscCount	    RMB	      1		escape code + paramters captured so far
V.EscNeed	    RMB	      1		escape code characters still needed
V.EscHandler	    RMB	      2		handler for escape code
V.Reverse           RMB       1         reverse video flag ($00 = off, $FF = on)
V.IBufH             RMB       1         input buffer head pointer
V.IBufT             RMB       1         input buffer tail pointer
V.SSigID            RMB       1         data ready process ID
V.SSigSg            RMB       1         data ready signal code
V.ScTyp             RMB       1         screen type
V.WWidth            RMB       1         window width
V.WHeight           RMB       1         window height
V.ScreenSize	    RMB	      2		Number of bytes to scroll screen
V.FBCol             RMB       1         currently selected foreground and background color
V.BordCol           RMB       1         currently selected border color
V.KeyDrvMPtr        RMB       2         keydrv module address
V.KeyDrvEPtr        RMB       2         keydrv entry point address
                  IFGT    Level-1
V.MSDrvMPtr         RMB       2         mouse module address
V.MSDrvEPtr         RMB       2         mouse entry point address
V.MouseVect         RMB       2
V.MSButtons         RMB       1         keeps the buttons for the SetStat call
V.MSTimer           RMB       1         this hides the cursor if inactive for more than 4 seconds
V.MEMP              RMB       1         Code to check PS2_STAT for empty buffer (channel 1 or 2)
V.MS_IN             RMB       2         Address of Channel 1 or 2
V.M_WR              RMB       1         PS2 Control Write Channel
V.MCLR              RMB       1         PS2 Clear FIFO Channel 1 or 2
V.INT_PS2_MOUSE     RMB       1         Interrupt Flag for Channel 1 or 2
V.MSByte0           RMB       1         mouse packet byte 1
V.MSByte1           RMB       1         mouse packet byte 2
V.MSByte2           RMB       1         mouse packet byte 3
V.MSByteCnt         RMB       1         mouse packet byte counter
V.TermID            RMB       1
V.TermLive          RMB       1		1=live term,0=shadow term
V.TermBufBlk        RMB       1
                  ENDC
V.KeyDrvStat        equ       .
                    RMB       8

V.EscParms          RMB       20
* DWSet Parameters
V.DWType            set       V.EscParms+0
V.DWStartX          set       V.EscParms+1
V.DWStartY          set       V.EscParms+2
V.DWWidth           set       V.EscParms+3
V.DWHeight          set       V.EscParms+4
V.DWFore            set       V.EscParms+5
V.DWBack            set       V.EscParms+6
V.DWBorder          set       V.EscParms+7



                  IFGT    Level-1


********************************************************************
* vtio graphics definitions - 53 bytes +
********************************************************************

V.ST                RMB       1         screen type 0=Term 1=Gfx

* VICKY MASTER CONTROL REGISTER to enable graphics and capabilities
* | 7 |   6   |    5   |   4  |    3   |   2   |   1   |   0  |
* | X | GAMMA | SPRITE | TILE | BITMAP | GRAPH | OVRLY | TEXT |
* |   -----   | FON_SET|FON_OV| MON_SLP| DBL_Y | DBL_X | CLK70|
* $FFC0 MASTER_CTRL_REG_L, MASTER_CTRL_REG_H
* See constants below for settings used with SS.DSCrn in vtio

V.V_MCR             RMB       2         2 bytes for Vicky Control Register

* VICKY LAYER CONTROL REGISTER to set bitmaps and/or tile maps for display
* | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
* | - |   LAYER1  | - |  LAYER 0  |
* |       ------      |  LAYER 2  |
* 000=BM0 001=BM1 010=BM2 100=TM0 101=TM1 110=TM2
* $FFC2 VKY_RESERVED_00, VKY_RESERVED_01
* See SS.PScrn in vtio

V.V_LayerCTL        RMB       2
V.BordBack          RMB       12
* BITMAPS
* Store starting page for bitmaps, and CLUT# and bitmap enable bits.  Must be in first 512K RAM.
* $01_0000-$07_FFFF (OS9 Memory Blocks $01-$3F)
* Byte 1 of Bitmap register is CLUT(4 CLUTS:0-3)/Enable
* | 7 | 6 | 5 | 4 | 3 | 2 | 1 |   0    |
* |       -----       |  CLUT | ENABLE |
* Next 3 bytes in register used for physical 19 bit address for bitmap
* Max address is 07FFFF (must be in 1st 512K), which is 19 bits
* Store block# and then convert to 19 bit address in driver

V.BM0Cl_En          RMB       1         bitmap0 |clut|enable|
V.BM0Blk            RMB       1         bitmap0 block
V.BM1Cl_En          RMB       1         bitmap1 |clut|enable|
V.BM1Blk            RMB       1         bitmap1 block
V.BM2Cl_En          RMB       1         bitmap2 |clut|enable|
V.BM2Blk            RMB       1         bitmap2 block


* CLUT - need to store mirror of CLUT data so switching windows will work
* Store block# where high 4k is CLUT mirror.  Could store in last 4k of BM blocks.

V.CLUTBlk           RMB       1         block where high 4k mirrored CLUT data,0=Default CLUT
V.CLUT              RMB       1         which CLUTs are active 00001111

* TILE MAPS - 3 tile maps.  Registers are 12 bytes, 2 are reserved and
* 3 are the plysical address for the Tile Set.  Use Blk# for address here.
* So only need 8 bytes per tile map.  In the Map each tile is 2 bytes
* byte0=Tile number, byte1=CLUT+Tile Set. So relationship between Tile Map
* and Tile Set is set in the actual tile map data, not here.
* A tile map could be 2.4K (40x30) to 132K (256x256)

V.TM0               RMB       1         bit4 is yile size (1=8x8,0=16x16) bit0 is enable
V.TM0AddrH          RMB       1
V.TM0AddrM          RMB       1
V.TM0AddrL          RMB       1
V.TM0MapX           RMB       1         map size X (max 255)
V.TM0RSRV1          RMB       1
V.TM0MapY           RMB       1         map size Y (max 255)
V.TM0RESRV2         RMB       1
V.TM0ScrlX          RMB       2         2 bytes for scroll X info
V.TM0ScrlY          RMB       2         2 bytes for scroll Y info

V.TM1               RMB       1         bit4 is yile size (1=8x8,0=16x16) bit0 is enable
V.TM1AddrH          RMB       1
V.TM1AddrM          RMB       1
V.TM1AddrL          RMB       1
V.TM1MapX           RMB       1         map size X (max 255)
V.TM1RSRV1          RMB       1
V.TM1MapY           RMB       1         map size Y (max 255)
V.TM1RESRV2         RMB       1
V.TM1ScrlX          RMB       2         2 bytes for scroll X info
V.TM1ScrlY          RMB       2         2 bytes for scroll Y info

V.TM2               RMB       1         bit4 is yile size (1=8x8,0=16x16) bit0 is enable
V.TM2AddrH          RMB       1
V.TM2AddrM          RMB       1
V.TM2AddrL          RMB       1
V.TM2MapX           RMB       1         map size X (max 255)
V.TM2RSRV1          RMB       1
V.TM2MapY           RMB       1         map size Y (max 255)
V.TM2RESRV2         RMB       1
V.TM2ScrlX          RMB       2         2 bytes for scroll X info
V.TM2ScrlY          RMB       2         2 bytes for scroll Y info

V.TM0Blk            RMB       1         starting block# of Tile Map
V.TM1Blk            RMB       1         starting block# of tile set
V.TM2Blk            RMB       1         starting block# of tile set
* TILE SETS - there are 8 tile sets.  Tile Set registers contain a physical address, and
* a Square bit to determine if Tile Set is LINEAR or SQUARE
* Tile Sets are either 16K (8x8) or 64K (16x16)


V.TS0AddrH          RMB       1
V.TS0AddrM          RMB       1
V.TS0AddrL          RMB       1
V.TS0SQR            RMB       1         square or linear (bit 3)

V.TS1AddrH          RMB       1
V.TS1AddrM          RMB       1
V.TS1AddrL          RMB       1
V.TS1SQR            RMB       1         square or linear (bit 3)

V.TS2AddrH          RMB       1
V.TS2AddrM          RMB       1
V.TS2AddrL          RMB       1
V.TS2SQR            RMB       1         square or linear (bit 3)

V.TS3AddrH          RMB       1
V.TS3AddrM          RMB       1
V.TS3AddrL          RMB       1
V.TS3SQR            RMB       1         square or linear (bit 3)

V.TS4AddrH          RMB       1
V.TS4AddrM          RMB       1
V.TS4AddrL          RMB       1
V.TS4SQR            RMB       1         square or linear (bit 3)

V.TS5AddrH          RMB       1
V.TS5AddrM          RMB       1
V.TS5AddrL          RMB       1
V.TS5SQR            RMB       1         square or linear (bit 3)

V.TS6AddrH          RMB       1
V.TS6AddrM          RMB       1
V.TS6AddrL          RMB       1
V.TS6SQR            RMB       1         square or linear (bit 3)

V.TS7AddrH          RMB       1
V.TS7AddrM          RMB       1
V.TS7AddrL          RMB       1
V.TS7SQR            RMB       1         square or linear (bit 3)


V.TS0Blk            RMB       1         starting block# of tile set
V.TS1Blk            RMB       1         starting block# of tile set
V.TS2Blk            RMB       1         starting block# of tile set
V.TS3Blk            RMB       1         starting block# of tile set
V.TS4Blk            RMB       1         starting block# of tile set
V.TS5Blk            RMB       1         starting block# of tile set
V.TS6Blk            RMB       1         starting block# of tile set
V.TS7Blk            RMB       1         starting block# of tile set
* GRAPHICS CURSORS,LINES, COLORS
V.GCX               RMB       2         graphics cursor X
V.GCY               RMB       1         graphics cursor Y
V.GCOLOR            RMB       1         graphics color
V.LX                RMB       2         line coordiate for X
V.LY                RMB       1         line coordinate for Y
V.GCADDR            RMB       3         address of cursor on screen
V.GCAD8K            RMB       2         address in 8K window
V.GMAPBLK           RMB       2         mapped in logical address of block

                  ENDC

V.InBuf             RMB       KBufSz    the input buffer
V.KSBuf             RMB       KBufSz
* grfdrv256 SetBlkC2C3 maps the DSS through ONE MMU slot (slot 5).
* Safe only while the whole area fits a single 256-byte page: F$SRqMem
* hands out page-aligned pages and 256 divides 8192, so <=256 bytes
* can never span two 8K blocks.  Past a page, slot 5 must become a
* 2-slot window.
                    ifgt      .-256
                    error     vtio device static > 256 bytes - fix grfdrv256 DSS mapping
                    endc

                    RMB       250-.
V.Last              EQU       .

* Borrow DP after D.IRQTmp; stays below $20 so it does not hit Level 2 D.Tasks.
                    org       D.IRQTmp
D.Bell              rmb       2
D.TnCnt             rmb       1
D.OrgAlt            rmb       2
D.SndPrcID          rmb       1
D.KySns             rmb       1
                  IFGT    Level-1
* 2-byte pointer to the active vtio static. Do not alias 1-byte D.Boot.
* Placed after D.IRQTmp so it stays below $20 (Level 2 D.Tasks).
* Level 1 already has D.KbdSta at $6D in os9.d.
D.KbdSta            rmb       2
                  ENDC

* K-specific section
* Borrow 9 bytes from "CoCo" specific area of system globals for platform use.
                    org       D.WDAddr
D.RowState          RMB       9
D.WBKKyDn           RMB       1

*******************************************************************
* F256 Graphics Driver Global Memory
*
* This is SHARED between system and grfdrv (lives in Block 0)
*******************************************************************

GrfMem              equ       $1100     ; GrfDrv data area (256 bytes)
F256Gfx             equ       $1200     ; F256-specific graphics data (256 bytes)
GrfMod              equ       $C000     ; Logical location of module in task 1

*******************************************************************
* GrfMem Offsets - Corrected for 8-byte DAT
*******************************************************************
                    org       $1100
gr.DATImg           RMB       16        ; GrfDrv DAT image (16 BYTES)
gr.Stack            RMB       2         ; GrfDrv Stack pointer (2 bytes)
gr.SysStk           RMB       2         ; Saved System Stack (during flip)
gr.Entry            RMB       2         ; GrfDrv entry point (2 bytes)
gr.WriteCharLive    RMB	      2		; WriteCharLive entry point (2 bytes)
gr.WriteCharShadow  RMB	      2		; WriteCharShadow entry point (2 bytes)
gr.ScrollLive	    RMB	      2		; ScrollLive entry point (2 bytes)
gr.ScrollShadow	    RMB	      2		; ScrollShadow entry point (2 bytes)
gr.Busy             RMB       1         ; Busy flag (1 byte)
gr.CurScr           RMB       1         ; Current screen (1 byte)
gr.Error            RMB       1         ; Error code (1 byte)
gr.Flags            RMB       1         ; Flags (1 byte)
gr.Temp             RMB       1         ; Temp Variable
gr.RGSADR           RMB       2         ; Address of PD.RGS
gr.PDRGS            RMB       R$Size    ; GrfDrv copy of PD.RGS
gr.PDAT             RMB       16
gr.PTask            RMB       1         ; Virtual Task Number
gr.FirstInitDone    RMB       1         ; Keyboard Init
gr.TermCnt          RMB       1         ; number of open terminals
gr.TermBlk          RMB       1         ; Current Terminal Block for Buffer Operations
gr.VStaStorU        rmb       2         ; Static Storage
gr.VBlk             rmb       1         ; block # containing static storage
gr.U5		    rmb	      2		; Static storage in grfdrv for slot 5
gr.SwitchTerm	    rmb	      1		; $00=None, $FE=pref, $FF=Next
gr.SwitchReq	    rmb	      1
SW.None		    equ	      $00
SW.Prev		    equ	      $FF
SW.Next		    equ	      $01
* Screen table (9 screens × 4 bytes = 36 bytes)
gr.LiveTerm         rmb       1         ; this is the active terminal
gr.TermSz           equ       8         ; Size per entry (8 bytes to make idx math easier)
gr.TermTbl          RMB       72        ; Screen table base
*******************************************************************
* GrfDrv parameter registers.
*
* vtio reaches grfdrv through a register-bank flip (CallGrfDrv2 ->
* jmp [D.Flip1]) and so cannot pass arguments in CPU registers.  It
* snapshots them into this block first, in the system task, before
* Flip1.  Do not index U after LUT 1 has stolen slots.
*
* Named by size and number, not by meaning: bN = 1 byte, dN = 2 bytes
* ("double").  Each register carries something different per GF.* op,
* so a descriptive name would be a lie at most call sites.  This table
* is the ABI; every store/load site also names its value inline.
*
*   op                   b2          b3           b4     b5     d1         d2
*   -------------------- ----------- ------------ ------ ------ ---------- ---------
*   GF.PSGBell  (14)     -           volume 0-15  -      -      frequency  -
*   GF.Cell     (16)     glyph       colour attr  dest   -      cell off   -
*   GF.Blank    (18)     fill glyph  fill colour  -      -      -          -
*   GF.Pal      (19)     pal reg #   -            dest   0=FG   LUT byte   LUT byte
*                                                        1=BG   0-1 (B,G)  2-3 (R,A)
*   GF.BmEnable (20)     bitmap #    ctrl byte    -      -      phys addr  -
*   GF.BmFree   (21)     bitmap #    -            -      -      -          -
*   GF.BmPalet  (22)     bitmap #    CLUT#|enable -      -      -          -
*
* b1 is unassigned - a free parameter byte.  (It was the GF.Write
*   sub-op selector before that dispatch layer was removed.)
* b4 "dest" is set by vtio's SetWDest: WD.Buf = the 16K terminal backup
*   buffer at LUT1 $6000, WD.Vicky = the live $C2/$C3 planes.
* d1/d2 halves are addressed gr.d1 / gr.d1+1 the way D splits into A/B.
* The direct-call entries (WriteCharLive/Shadow, ScrollLive/Shadow)
*   bypass this block entirely - they take everything in A/B/Y.
*
* HAZARD: GF.ClrScrn (17) and the erase family (GF.EraseLine 10 /
*   GF.ErEOLine 11 / GF.ErEOScrn 12) take no parameters here, but both
*   CLOBBER b3 - they spill V.FBCol into it because U gets reused as the
*   colour-plane pointer.  Nothing may hold a live b3 across those calls.
*
* The physical order below (b1 b2 d1 d2 b3 b4 b5) is historical, not
* meaningful; it is kept so GrfMem offsets did not move in the rename.
*******************************************************************
gr.b1               rmb       1         ; unassigned - free parameter byte
gr.b2               rmb       1         ; glyph / palette reg # / bitmap #
gr.d1               rmb       2         ; cell offset / PSG freq / BM addr / LUT b0-1
gr.d2               rmb       2         ; GF.Pal LUT bytes 2-3 only
gr.b3               rmb       1         ; colour attr / PSG volume / BM ctrl byte
gr.b4               rmb       1         ; WD.Buf (16K backup) / WD.Vicky ($C2/$C3)
gr.b5               rmb       1         ; GF.Pal 0=FG 1=BG LUT select
                    org       0
T.Flags             rmb       1         ; Acrive Flag - only one screen should be active
T.Block             rmb       1
T.StatPtr           rmb       2         ; Pointer to Static Vars (V. vars ) for screen
T.VBlk		    rmb	      1		; block containing static vars
T.grU5		    rmb	      2         ; U in grfdrv if in mmu slot 5
T.Unused	    rmb	      1		; Unused
* Term table row is 8 bytes to make the math easier for indexing.
* can use lsr to compute index instead of multiplying by 5
* Plus we have 1 unused byte for future use without breaking anything else
* Note:  Driver Static Storage will never span 2 blocks because of 256 byte pages
* Driver Static Storage will always be 256 bytes on a 256 byte boundary

T.Init              equ       %00000001 ; Terminal is initialized/open
T.Live              equ       %00000010 ; Terminal is currently active (optional redundancy


* Rest available for F256-specific data
gr.UserData         equ       $60       ; User area (~160 bytes to $FF

E$Param             equ       $05

*******************************************************************
* Terminal Management Constants
*******************************************************************
G.TermMax           equ       9         ; Maximum terminals (0-8)

*******************************************************************
* GrfDrv Function Codes
* These are sequential indexes; CallGrfDrv does ASLB before dispatch.
*******************************************************************
GF.Init             equ       0         ; Initialize
GF.Term             equ       1         ; Terminate
GF.GSMouse          equ       2         ; GetStat mouse
GF.GSDScrn          equ       3         ; GetStat display screen
GF.GSFntChar        equ       4         ; GetStat font char
* 5 was GF.SSFntLoadF - load a font from a file inside grfdrv.  Deleted: it
* was never reachable (vtio's SSFntLoadF does the whole job itself and never
* dispatched here), and the body was already dead-ended by a 'bra errorclose@'
* placed before its I$Open.  grfdrv cannot do file I/O anyway - it is entered
* through a register-bank flip onto one shared D.CCStk with gr.Stack holding a
* single caller's S, and nothing gates the foreground path, so a blocking read
* would let a second entrant overwrite the sleeper rather than serialise.
* Ops above it renumbered down one.
GF.SSFntChar        equ       5         ; SetStat font char
GF.SSDScrn          equ       6         ; SetStat display screen
GF.PushBuf          equ       7         ; Push Vicky state to term buffer
GF.PullBuf          equ       8         ; Pull term buffer to Vicky
GF.EraseLine	    equ	      9
GF.ErEOLine	    equ	      10
GF.ErEOScrn         equ       11        ; Erase End of Screen
GF.PSGInit	    equ	      12
GF.PSGBell	    equ	      13
GF.PSGOff	    equ	      14
GF.Cell             equ       15        ; one cell: b2 glyph, b3 colour, d1 offset
GF.ClrScrn          equ       16        ; clear whole screen (dims read from DSS)
GF.Blank            equ       17        ; blank the 16K term buffer
* 18 was GF.InitDisp - gamma ramp, font + text-LUT install, $C2/$C3 fill.
* Deleted: the FPGA (and MAME's device_reset) preload the font and the text
* palettes, vtio never sets Mstr_Ctrl_GAMMA_En so the gamma LUT is unused,
* and the $C2/$C3 fill is GF.ClrScrn's job.  Its vtio caller InitDisplayMem
* was already gone.  Ops above it renumbered down one.
GF.Pal              equ       18        ; one text-LUT entry (1B 60 / 1B 61)
GF.BmEnable         equ       19        ; bitmap: enable + phys addr
GF.BmFree           equ       20        ; bitmap: zero the four registers
GF.BmPalet          equ       21        ; bitmap: assign CLUT
WD.Buf              equ       0         ; 16K TermBlk at LUT1 $6000
WD.Vicky            equ       1         ; live $C2/$C3 at LUT1 $2000/$4000

*******************************************************************
* 16K termainal storage for switching screens = excactly 16384
*******************************************************************
                    org       0
T.TXT               rmb       4800      ; 80x60 text screen
T.TXTCOLOR          rmb       4800      ; 80x60 color matrix
T.FLUT              rmb       64        ; foreground LUT
T.BLUT              rmb       64        ; background LUT
T.SPRITE0           rmb       512       ; Sprite Register Copy
T.FONT0             rmb       2048
T.CLUT0             rmb       1024      ; CLUT 0 Copy
T.CLUT1             rmb       1024      ; CLUT 1 Copy
T.CLUT2             rmb       1024      ; CLUT 2 Copy
T.CLUT3             rmb       1024      ; CLUT 3 Copy

* SS.KySns bit locations
SHIFTBIT            equ       %00000001
CTRLBIT             equ       %00000010
ALTBIT              equ       %00000100
UPBIT               equ       %00001000
DOWNBIT             equ       %00010000
LEFTBIT             equ       %00100000
RIGHTBIT            equ       %01000000
SPACEBIT            equ       %10000000
KEYDELAY            equ       5
KEYDELAY1           equ       30

                  ENDC
