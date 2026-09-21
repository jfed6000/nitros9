                  IFNE    WILDBITS.D-1
WILDBITS.D              set       1

********************************************************************
* WildbitsDefs - NitrOS-9 System Definitions for the Wildbits 6809
*
* This is a high level view of the memory map as setup by
* NitrOS-9.
*
*     $0000----> ==================================
*               |                                  |
*               |      NitrOS-9 Globals/Stack      |
*               |                                  |
*     $0500---->|==================================|
*               |                                  |
*                 . . . . . . . . . . . . . . . . .
*               |                                  |
*               |   RAM available for allocation   |
*               |       by NitrOS-9 and Apps       |
*               |                                  |
*                 . . . . . . . . . . . . . . . . .
*               |                                  |
*     $FD00---->|==================================|
*               |    Constant RAM (for Level 2)    |
*     $FE00---->|==================================|
*               |                I/O               |
*               |            &  Vectors            |
*                ==================================
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*          2023/02/07  Boisy G. Pitre
* Started.
*
*          2023/08/16  Boisy G. Pitre
* Modified to address new memory map that Stefany created.

********************************************************************
* Ticks per second.
*
TkPerSec            set       60

                  IFEQ    Level-1

********************************************************************
*
* NitrOS-9 Level 1 Section
*
********************************************************************

********************************************************************
* Boot definitions for NitrOS-9 Level 1
*
* These definitions are not strictly for 'Boot', but are for booting the
* system.
*
HW.Page             set       $FF       device descriptor hardware page

                  ELSE

HW.Page             set       $07       device descriptor hardware page
Bt.Start            set       $EE00     start address of where KRN is in memory

*************************************************
*
* NitrOS-9 Level 2 Section
*
*************************************************

****************************************
* Dynamic Address Translator Definitions
*
DAT.BlCt            EQU       8         DAT blocks/address space
DAT.BlSz            EQU       (256/DAT.BlCt)*256 DAT block size
DAT.ImSz            EQU       DAT.BlCt*2 DAT image size
DAT.Addr            EQU       -(DAT.BlSz/256) DAT MSB address bits
DAT.Task            EQU       $FFA0     task register address
DAT.TkCt            EQU       32        number of DAT tasks
DAT.Regs            EQU       $FFA8     DAT block registers base address
DAT.Free            EQU       $333E     free block number
DAT.BlMx            EQU       $3F       maximum block number
DAT.BMSz            EQU       $40       memory block map size
DAT.WrPr            EQU       0         no write protect
DAT.WrEn            EQU       0         no write enable
SysTask             EQU       0         CoCo system task number
IOBlock             EQU       $3F
ROMBlock            EQU       $3F
IOAddr              EQU       $7F
ROMCount            EQU       1         number of blocks of ROM (high RAM block)
RAMCount            EQU       1         initial blocks of RAM
MoveBlks            EQU       DAT.BlCt-ROMCount-2 block numbers used for copies
BlockTyp            EQU       1         check only first bytes of RAM block
ByteType            EQU       2         check entire block of RAM
Limited             EQU       1         check only upper memory for ROM modules
UnLimitd            EQU       2         check all NotRAM for modules
* NOTE: this check assumes any NotRAM with a module will
*       always start with $87CD in first two bytes of block
RAMCheck            EQU       BlockTyp  check only beg bytes of block
ROMCheck            EQU       Limited   check only upper few blocks for ROM
LastRAM             EQU       IOBlock   maximum RAM block number

HW.Page             SET       $7        device descriptor hardware page

* KrnBlk defines the block number of the 8K RAM block that is mapped to
* the top of CPU address space ($E000-$FFFF) for the system process, and
* which holds the Kernel. The top 3 pages of this CPU address space ($FD00-
* $FFFF) have two special properties. First, $FE00-$FFFF contains the I/O space.
* Second, $FD00-$FDFFF isn't affected by the DAT mappings but, instead,
* remains constant regardless of what block is mapped in at slot 7.
* When a user process is mapped in, and requests enough memory, it will end up
* with its own block assigned for CPU address space $E000-
* $FFFF but $FD00-$FFFF is unusable by the user process.
KrnBlk              SET       $7

                  ENDC

********************************************************************
* Custom SetStats
*
		    org	      $C0
SS.FntLoadM	    rmb	      1
SS.FntLoadF         rmb	      1
SS.FntChar	    rmb	      1
SS.SOLIRQ	    rmb	      1
SS.SOLMUTE	    rmb	      1
SS.TermSel          rmb       1                   $C5 R$X = terminal id: show it (vtio/grfdrv)
SS.LiveKeys         equ       $C6                 GetStat: R$A = live key sense bits, R$X/R$Y/R$U = keys held now; empties the input buffer
* SS.Joy ($13) modes, in R$X on entry (joust docs/grfdrv256-api.md)
JOY.Stick0          equ       0                   stick 0, compatibility: R$X/R$Y = 0/128/255, R$A = buttons
JOY.Stick1          equ       1                   stick 1, compatibility
JOY.Sticks          equ       2                   R$X = stick 0, R$Y = stick 1, as JY bits
JOY.NES2            equ       3                   R$X, R$Y = NES pads 0 and 1
JOY.SNES2           equ       4                   R$X, R$Y = SNES pads 0 and 1
JOY.NES4            equ       5                   R$Y = 8-byte buffer: NES pads 0-3
JOY.SNES4           equ       6                   R$Y = 8-byte buffer: SNES pads 0-3
* The SS.Joy word, 1 = pressed.  The low byte alone is stick-compatible.
JY.Up               equ       %00000001
JY.Down             equ       %00000010
JY.Left             equ       %00000100
JY.Right            equ       %00001000
JY.Btn0             equ       %00010000           stick button 0; NES A; SNES B
JY.Btn1             equ       %00100000           stick button 1; NES B; SNES Y
JY.Btn2             equ       %01000000           stick button 2; SNES A
JY.X                equ       %10000000           SNES X
JY.Select           equ       %00000001           high byte
JY.Start            equ       %00000010           high byte
JY.L                equ       %00000100           high byte, SNES
JY.R                equ       %00001000           high byte, SNES
SS.WSig             equ       $E1                 SetStat: signal me when this terminal goes background/forward

* Aliases: two codes adopted from the CoCo whose os9.d names describe
* nothing they do on this hardware.  SS.PScrn is "Polymorph Screen into
* different screen type" there and sets which source feeds one display
* layer here; SS.DScrn is "Display a screen allocated by SS.AScrn" there
* and is the VICKY master control register here, Get and Set.  The
* originals stay valid and stay in use - level2/coco3 uses both codes
* with their CoCo meanings - but new Wildbits code should use these.
* Defined here rather than in os9.d for exactly that reason: coco3
* modules do not include this file.
SS.Layer            equ       SS.PScrn            R$X = layer 0-2, R$Y = source: 0-2 bitmap, 4-6 tile map
SS.MCR              equ       SS.DScrn            R$X = MCR low byte, R$Y = MCR high byte (FX_OMIT/FT_OMIT)

* Signal codes for SS.WSig.  The caller picks its own, but these are the
* project's defaults and what wsigtst uses.  They are above $80 because
* the system owns everything at or below it (os9.d: S$Kill $00 ... S$Alarm
* $05, S$FS2Sig $80; level1/wildbits/modules/SOLdrv.asm: "Signals should
* be > 128, system defines signals <= 128").  $05 is S$Alarm - the code
* F$Alarm sends - and must never be used for this.
S$WinBg             equ       $81                 this terminal went background
S$WinFg             equ       $82                 this terminal came forward

* Graphics Get/SetStats for bitmaps, CLUTs, sprites, tile sets and tile maps
* (grfdrv256).  Codes without a handler return E$UnkSvc.  The groups sit in
* the free holes: $C7-$CB are VRN (os9.d), $D2 is sc16550's SS.DvrID, $E2 is
* SS.Fuji (drivewire.d).
* Spare: $D0 (was SS.KyDwn), $D4-$E0 (the sprite codes the registered table
* made unnecessary) and $FE-$FF.  $E1 is SS.WSig, above.
* The sprite group is no longer contiguous, and that is the point: a code
* with no handler is a promise nobody made.  The rest of the groups are
* still reserved names awaiting the goal 2 trim (docs/driver-work.md).
* CLUTs
SS.ClutLoad         equ       $CC                 load a CLUT from a file
SS.ClutCopy         equ       $CD                 load a whole CLUT from caller memory
SS.ClutRead         equ       $CE                 GetStat: CLUT entries to a caller buffer
SS.ClutWrite        equ       $CF                 CLUT entries from a caller buffer
* Sprites
* A program that draws sprites REGISTERS its own 128-record table with
* SS.SprReg and then pushes ranges of it with SS.SprPush; the driver keeps
* no copy of the records at all and restores the screen from that table on
* a terminal switch (docs/sprite-registration-plan.md in the joust tree).
* SS.SprSet ($D3, records from a caller buffer) is GONE: it was a second
* writer the driver could not reproduce on a switch.
SS.SprPush          equ       $D1                 R$Y = first record, R$U = count: that range of the registered table to the screen
SS.SprReg           equ       $D3                 R$X = the table (auto: R$Y = 0), R$Y = blocks (manual), R$U = records 1-128, 0 = give it up
* $D4-$E0 were thirteen more sprite codes - SprAlloc, SprACfg, SprCfg,
* SprXY, SprOn, SprOff, SprLayer, SprClut, SprLoad, SprSave, SprSLoad,
* SprSSave, SprKill - reserved in 2026-03 for a per-sprite API that the
* registered table made unnecessary: a program moves, shows, hides and
* re-images a sprite by writing its own record and pushing the range.
* None of them ever had a handler.  They are free, except $D4/$D5 which the
* graphics allocator below now uses (user, 2026-09-20).
* Graphics memory.  NOT bitmap-specific: one allocator serves bitmaps, tile
* sets and tile maps alike, which is why it is here rather than in any of
* the three groups.  It exists at all because F$AlHRAM is registered
* F$AlHRAM+SysState in krnp2.asm's svctab, so an application cannot call it
* and the driver can - and the convention says graphics allocate from the
* top of the block map down.  The blocks it returns belong to the PROGRAM,
* which frees them with SS.GfxFree; contrast SS.BmAlloc below, whose blocks
* belong to the driver.  Blocks are physically consecutive, so an object may
* run past the end of one.
SS.GfxAlloc         equ       $D4                 R$X = block count; returns R$X = first block
SS.GfxFree          equ       $D5                 R$X = first block, R$U = count
* Bitmaps.  Two ways in, and the difference is who owns the memory:
*   SS.BmDef   - the program allocated the blocks (SS.GfxAlloc or F$AllRAM)
*                and says where the bitmap is.  The driver never frees them.
*   SS.BmAlloc - the driver allocates AND defines in one call, and owns the
*                blocks: SS.BmKill and a terminal close free them.  This is
*                what lets shellbg put up a wallpaper and exit.
* Whoever allocated, frees.  The driver records which it was, so no caller
* has to pass a flag.
* NEITHER ENABLES THE BITMAP.  Visibility needs three independent things -
* the enable bit (SS.BmCfg), a layer pointing at it (SS.Layer), and FX_BM in
* the MCR - and newly allocated blocks hold whatever was there before, so
* enabling on allocate means showing garbage.  SS.AScrn, the compatibility
* shim, supplies the enable to keep its old contract.
* SS.BmClear and SS.BmLine are BUILT (2026-09-20) and are the two calls
* that exist because only the driver can reach the hardware behind them:
* the DMA engine and the line engine both live at addresses outside a
* Level 2 process's address space.  SS.BmClear is ASYNCHRONOUS - its
* GetStat says when the fill has finished - and SS.BmLine takes a BATCH,
* because a line is 3.2 us of hardware behind a 474 us call.  Both are
* documented in docs/bitmap-api.md in the joust tree.
SS.BmAlloc          equ       $E3                 R$Y = bitmap #, R$X = screen type; returns R$X = first block
SS.BmBlk            equ       $E4                 GetStat: bitmap first block and control byte
SS.BmClear          equ       $E5                 R$Y = bitmap #, R$X low = fill value; GetStat: R$X = 1 while a fill is outstanding
SS.BmDef            equ       $E6                 R$Y = mode/bitmap #, R$X = block (0 = clear), R$U = offset
SS.BmLine           equ       $E7                 R$Y = bitmap #, R$X = 8-byte records, R$U = count in / drawn out; GetStat: R$X = pixels queued
SS.BmKill           equ       $EA                 R$Y = bitmap #: undefine, and free if the driver allocated
SS.BmCfg            equ       $ED                 R$Y = bitmap #, R$X = enable/CLUT, R$U = HIRES4/GROUP
* $E8, $E9, $EB and $EC are free (user, 2026-09-20).  They were SS.BmOn,
* SS.BmOff, SS.BmLoad and SS.BmSave, and none ever had a handler.  On and
* Off are two fields of SS.BmCfg, which can also leave every other field
* alone, so a hide is one call and costs no more than a dedicated one would.
* Load and Save the architecture forbids outright - "no file I/O in
* grfdrv256" - and a program does them with I$Open/I$Read into the blocks
* SS.BmBlk reports, which is what pixview and shellbg already do.
* $E6 was SS.BmLayer, a THIRD name for SS.PScrn/SS.Layer, and $E7 was
* SS.BmClut, a second name for SS.Palet's SetStat whose GetStat means
* something unrelated.  Both are now better served by SS.BmCfg and SS.Layer,
* so the numbers went to SS.BmDef and to the line engine.
* Tile sets and tile maps.  A program owns the tile pixels and the map
* cells, in its own F$AllRAM blocks, and the hardware reads them there:
* the address in the register record IS the registration, so there is
* nothing else to tell the driver.  What the driver keeps per terminal is
* only the register image (V.TMn, V.TSn), which PullBuf reprograms on a
* terminal switch.  See docs/tile-api.md in the joust tree for the
* interface and docs/tile-plan.md for why these are the only codes left.
* Tile sets
SS.TsSet            equ       $EE                 R$X = 4-byte record, R$Y = tile set #
SS.TsAlloc          equ       $F0                 allocate tile set memory (reserved, no handler)
SS.TsKill           equ       $F3                 clear a tile set and free its memory (reserved, no handler)
* Tile maps
SS.TmSet            equ       $F4                 R$X = 12-byte record, R$Y = tile map #
SS.TmAlloc          equ       $F6                 allocate a tile map (reserved, no handler)
SS.TmScrl           equ       $F8                 R$Y = tile map #, R$X = X scroll, R$U = Y scroll
SS.TmKill           equ       $FD                 clear a tile map and free its memory (reserved, no handler)
* $EF, $F1, $F2, $F5, $F7, $F9-$FC are FREE (user, 2026-09-20).  They were
* TsAddr, TsLoad, TsSave, TmAddr, TmCell, TmOn, TmOff, TmLoad and TmSave -
* nine codes reserved in 2026-03 that never had a handler and that nothing
* in either tree ever referenced.  A program does each of them without a
* call: it keeps the block and offset it registered rather than reading an
* address back; it loads and saves with ordinary I$Read/I$Write, because
* grfdrv256 does no file I/O; it maps the map block and stores the 2-byte
* cell itself, which is what Joust's gfx.a TmRemove/TmClrBr already do; and
* it turns a map on or off with bit 0 of the CTRL byte in a record it
* already holds.  The four Alloc/Kill codes above stay reserved because
* asset allocation is meant to move into the driver - only it can reach
* F$AlHRAM, which is registered F$AlHRAM+SysState.  SS.TmScrl is
* implemented (2026-09-20): scrolling is the one tile operation with no
* program-owned buffer behind it, because the scroll position lives only in
* these registers.
* The four tile maps in the rc16 registers are NOT four usable layers: the
* core enables tile maps 0-2 only, and there is no scan address for a
* fourth, so SS.TmSet's limit of 2 matches the hardware.

********************************************************************
* System control definitions
*
SYS0                equ       $FE00
SYS1                equ       $FE01
RST0                equ       $FE02
RST1                equ       $FE03

SYS_RESET           equ       %10000000
SYS_CAP_EN          equ       %00100000
SYS_BUZZ            equ       %00010000
SYS_L1              equ       %00001000
SYS_L0              equ       %00000100
SYS_SD_L            equ       %00000010
SYS_PWR_L           equ       %00000001

SYS_SD_WP           equ       %10000000
SYS_SD_CD           equ       %01000000
SYS_L1_RATE         equ       %11000000
SYS_L0_RATE         equ       %00110000
SYS_SID_ST          equ       %00001000
SYS_PSG_ST          equ       %00000100
SYS_L1_MN           equ       %00000010
SYS_L0_MN           equ       %00000001

********************************************************************
* MMU definitions
*
MMU_MEM_CTRL        equ       $FFA0
MMU_IO_CTRL         equ       $FFA1
MMU_SLOT_BASE       equ       $FFA8
MMU_SLOT_0          equ       MMU_SLOT_BASE+0 $0000-$1FFF
MMU_SLOT_1          equ       MMU_SLOT_BASE+1 $2000-$3FFF
MMU_SLOT_2          equ       MMU_SLOT_BASE+2 $4000-$5FFF
MMU_SLOT_3          equ       MMU_SLOT_BASE+3 $6000-$7FFF
MMU_SLOT_4          equ       MMU_SLOT_BASE+4 $8000-$9FFF
MMU_SLOT_5          equ       MMU_SLOT_BASE+5 $A000-$BFFF
MMU_SLOT_6          equ       MMU_SLOT_BASE+6 $C000-$DFFF
MMU_SLOT_7          equ       MMU_SLOT_BASE+7 $E000-$FFFF

* MMU_MEM_CTRL bits
EDIT_LUT            equ       %00110000
EDIT_LUT_0          equ       %00000000
EDIT_LUT_1          equ       %00010000
EDIT_LUT_2          equ       %00100000
EDIT_LUT_3          equ       %00110000
ACT_LUT             equ       %00000000
ACT_LUT_0           equ       %00000000
ACT_LUT_1           equ       %00000001
ACT_LUT_2           equ       %00000010
ACT_LUT_3           equ       %00000011

LUT_BANK_0          equ       $0008
LUT_BANK_1          equ       $0009
LUT_BANK_2          equ       $000A
LUT_BANK_3          equ       $000B
LUT_BANK_4          equ       $000C
LUT_BANK_5          equ       $000D
LUT_BANK_6          equ       $000E
LUT_BANK_7          equ       $000F

* MMU_IO_CTRL bits
* $FFA1 has 2 bits:
*    FFA1[0] =
*        1 = Enable internal RAM for segment $FD00-$FDFF.
*        0 = Disable; RAM/FLASH is accessible.
*
*    FFA1[1] =
*        1 = Enable internal RAM for segment $FFF0-$FFFF
*        0 = Disable; RAM/FLASH is accessible.
* When enabled, the areas supersede RAM/flash, but will be disabled by RESET. When the system resets,
* those regions revert to RAM/flash. Also at RESET, the contents of RAM retain the old values until the
* system powers off.

********************************************************************
* Interrupt definitions
*
* Interrupt addresses
INT_PENDING_0       equ       $FE20
INT_POLARITY_0      equ       $FE24
INT_EDGE_0          equ       $FE28
INT_MASK_0          equ       $FE2C

INT_PENDING_1       equ       $FE21
INT_POLARITY_1      equ       $FE25
INT_EDGE_1          equ       $FE29
INT_MASK_1          equ       $FE2D

INT_PENDING_2       equ       $FE22     not used
INT_POLARITY_2      equ       $FE26     not used
INT_EDGE_2          equ       $FE2A     not used
INT_MASK_2          equ       $FE2E     not used

INT_PENDING_3       equ       $FE23     not used
INT_POLARITY_3      equ       $FE27     not used
INT_EDGE_3          equ       $FE2B     not used
INT_MASK_3          equ       $FE2F     not used

* Interrupt group 0 flags
INT_VKY_SOF         equ       %00000001 TinyVicky start of frame interrupt
INT_VKY_SOL         equ       %00000010 TinyVicky start of line interrupt
INT_PS2_KBD         equ       %00000100 PS/2 keyboard event
INT_PS2_MOUSE       equ       %00001000 PS/2 mouse event
INT_TIMER_0         equ       %00010000 TIMER0 has reached its target value
INT_TIMER_1         equ       %00100000 TIMER1 has reached its target value
INT_CARTRIDGE       equ       %10000000 Interrupt asserted by the cartridge

* Interrupt group 1 flags
INT_UART            equ       %00000001 UART is ready to receive or send data
INT_RTC             equ       %00010000 event from the real time clock chip
INT_VIA0            equ       %00100000 event from the 65C22 VIA chip
INT_VIA1            equ       %01000000 K Only: local keyboard
INT_SDC_INS         equ       %01000000 user has inserted an SD card

* Interrupt group 2 flags
IEC_DATA_i          equ       %00000001 IEC data in
IEC_CLK_i           equ       %00000010 IEC clock in
IEC_ATN_i           equ       %00000100 IEC ATN in
IEC_SREQ_i          equ       %00001000 IEC SREQ in

* Interrupt group 3 flags
INT_WIZFI_RX        equ       %00000001 Rx FIFO went non-empty (edge, INT_PENDING_3)
INT_WIZFI_TX        equ       %00100000 Tx FIFO drained to empty (edge, INT_PENDING_3)
INT_WIZFI           equ       INT_WIZFI_RX+INT_WIZFI_TX


********************************************************************
* Keyboard definitions
*
PS2_CTRL            equ       $FE50
PS2_OUT             equ       $FE51
KBD_IN              equ       $FE52
MS_IN               equ       $FE53
PS2_STAT            equ       $FE54

MCLR                equ       %00100000
KCLR                equ       %00010000
M_WR                equ       %00001000
K_WR                equ       %00000010

K_AK                equ       %10000000
K_NK                equ       %01000000
M_AK                equ       %00100000
M_NK                equ       %00010000
MEMP                equ       %00000010
KEMP                equ       %00000001

********************************************************************
* Mouse definitions
* $FEA0-$FEAF
* Mouse Mode is bit 1 of MS_MEM (Mouse Mode-Enable)
* 0=System handles x/y  1=harware interprets PS/2 packets
* Enable is bit 0.  1=show mouse pointer 0 = hide mouse pointer
MS_MEN		    equ	      $FEA0     mouse mode-enable
MS_XH		    equ	      $FEA2	mouse x low byte
MS_XL		    equ	      $FEA3	mouse x high byte	    
MS_YH		    equ	      $FEA4	mouse y low byte
MS_YL		    equ	      $FEA5	mouse y high byte
MS_PS2B0	    equ	      $FEA6	mouse PS/2 Byte 0
MS_PS2B1	    equ	      $FEA7	mouse PS/2 Byte 1
MS_PS2B2	    equ	      $FEA8	mouse PS/2 Byte 2
MS_SRATE	    equ	      $28	mouse sample rate $A,$14,$28,$3C,$50,$64,$C8

********************************************************************
* K2 optical keyboard definitions
*
OKB.Base            equ       $FE10
                    org       0
OKB.Data            rmb       1         keyboard data
OKB.Stat            rmb       1         bit 7 = 1 (mechanical) or 0 (optical), bit 0 = 1 (FIFO empty) or 0 (FIFO full)
OKB.CntLo           rmb       1
OKB.CntHi           rmb       1

********************************************************************
* Timer definitions
*
* Timer addresses
T0_CTR              equ       $FE30     timer 0 counter (write)
T0_STAT             equ       $FE30     timer 0 status (read)
T0_VAL              equ       $FE31     timer 0 value (read/write)
T0_CMP_CTR          equ       $FE34     timer 0 compare counter (read/write)
T0_CMP              equ       $FE35     timer 0 compare value (read/write)
T1_CTR              equ       $FE38     timer 1 counter (write)
T1_STAT             equ       $FE38     timer 1 status (read)
T1_VAL              equ       $FE39     timer 1 value (read/write)
T1_CMP_CTR          equ       $FE3C     timer 1 compare counter (read/write)
T1_CMP              equ       $FE3D     timer 1 compare value (read/write)

********************************************************************
* VIA (W65C22S) definitions
*
* VIA addresses
VIA0.Base           equ       $FEB0
VIA1.Base           equ       $FFB0
                    org       0
VIA_ORB_IRB         rmb       1         port b data
VIA_ORA_IRA         rmb       1         port a data
VIA_DDRB            rmb       1         port b data direction register
VIA_DDRA            rmb       1         port a data direction register
VIA_T1CL            rmb       1         timer 1 counter low
VIA_T1CH            rmb       1         timer 1 counter high
VIA_T1LL            rmb       1         timer 1 latch low
VIA_T1LH            rmb       1         timer 1 latch high
VIA_T2CL            rmb       1         timer 2 counter low
VIA_T2CH            rmb       1         timer 2 counter high
VIA_SR              rmb       1         serial data register
VIA_ACR             rmb       1         auxiliary control register
VIA_PCR             rmb       1         peripheral control register
VIA_IFR             rmb       1         interrupt flag register
VIA_IER             rmb       1         interrupt enable register
VIA_ORA_IRA_AUX     rmb       1         port a data (no handshake)

* ACR control register values
T1_CTRL             equ       %11000000
T2_CTRL             equ       %00100000
SR_CTRL             equ       %00011100
PBL_EN              equ       %00000010
PAL_EN              equ       %00000001

* PCR control register values
CB2_CTRL            equ       %11100000
CB1_CTRL            equ       %00010000
CA2_CTRL            equ       %00001110
CA1_CTRL            equ       %00000001

* IFR control register values
IRQF                equ       %10000000
T1F                 equ       %01000000
T2F                 equ       %00100000
CB1F                equ       %00010000
CB2F                equ       %00001000
SRF                 equ       %00000100
CA1F                equ       %00000010
CA2F                equ       %00000001

* IER control register values
IERSET              equ       %10000000
T1E                 equ       %01000000
T2E                 equ       %00100000
CB1E                equ       %00010000
CB2E                equ       %00001000
SRE                 equ       %00000100
CA1E                equ       %00000010
CA2E                equ       %00000001

********************************************************************
* Real-time clock definitions
*
RTC.Base            equ       0xFE40
                    org       0
RTC_SEC             rmb       1         seconds register
RTC_SEC_ALARM       rmb       1         seconds alarm register
RTC_MIN             rmb       1         minutes register
RTC_MIN_ALARM       rmb       1         minutes alarm register
RTC_HRS             rmb       1         hours register
RTC_HRS_ALARM       rmb       1         hours alarm register
RTC_DAY             rmb       1         day register
RTC_DAY_ALARM       rmb       1         day alarm register
RTC_DOW             rmb       1         day of week register
RTC_MONTH           rmb       1         month register
RTC_YEAR            rmb       1         year register
RTC_RATES           rmb       1         rates register
RTC_ENABLE          rmb       1         enables register
RTC_FLAGS           rmb       1         flags register
RTC_CTRL            rmb       1         control register
RTC_CENTURY         rmb       1         century register

RTC_24HR            equ       $02       12/24 hour flag (1 = 24 Hr, 0 = 12 Hr)
RTC_STOP            equ       $04       0 = STOP when power off, 1 = run from battery when power off
RTC_UTI             equ       $08       update transfer inhibit

********************************************************************
* Joystick port definitions
*

* Port A (Joystick Port 1)
JOYA_UP             equ       0x01
JOYA_DWN            equ       0x02
JOYA_LFT            equ       0x04
JOTA_RGT            equ       0x08
JOTA_BUT0           equ       0x10
JOYA_BUT1           equ       0x20
JOYA_BUT2           equ       0x40

* Port B (Joystick Port 0)
JOYB_UP             equ       0x01
JOYB_DWN            equ       0x02
JOYB_LFT            equ       0x04
JOTB_RGT            equ       0x08
JOTB_BUT0           equ       0x10
JOYB_BUT1           equ       0x20
JOYB_BUT2           equ       0x40

********************************************************************
* UART definition
*
UART.Base           equ       0xFE60

********************************************************************
* CODEC definitions
*
CODEC.Base          equ       $FE70
                    org       0
CODECCmdLo          rmb       1
CODECCmdHi          rmb       1
CODECStat           rmb       1
CODECCtrl           equ       CODECStat


******************************************************************
* Bitmap definitions
*
GAMMA_BLK           equ       $C0

******************************************************************
* Text lookup definitions
*
TEXT_LUT_BLK	    equ	      $C0
TEXT_LUT_FG         equ       $1700
TEXT_LUT_BG         equ       $1740

********************************************************************
* Font definitions
*
FONT_BLK            equ	      $C1
FONT_0_OFFSET	    equ	      $0000
FONT_1_OFFSET	    equ	      $0800

********************************************************************
* SD card interface definitions
*
SDC0.Base           equ       $FE90
SDC1.Base           equ       $FF00
                    org       0
SDC_STAT            rmb       1
SDC_DATA            rmb       1

* SDC status bits
SPI_BUSY            equ       %10000000
SPI_CLK             equ       %00000010
CS_EN               equ       %00000001

********************************************************************
* Text screen definitions
*
TXT.Base            equ       $FFC0
VKY_LAYER_CTRL_0    equ	      $FFC2
VKY_LAYER_CTRL_1    equ       $FFC3
* The following are registers indicies based on TXT.Base
                    org       0
MASTER_CTRL_REG_L   rmb       1
MASTER_CTRL_REG_H   rmb       1
VKY_LAYER_CTRL_L    rmb       1
VKY_LAYER_CTRL_H    rmb       1
BORDER_CTRL_REG     rmb       1         bit[0] - enable (1 by default)  bit[4..6]: X scroll offset (will scroll left) (acceptable values: 0..7)
BORDER_COLOR_B      rmb       1
BORDER_COLOR_G      rmb       1
BORDER_COLOR_R      rmb       1
BORDER_X_SIZE       rmb       1         X values: 0 - 32 (default: 32)
BORDER_Y_SIZE       rmb       1         Y values: 0 - 32 (default: 32)
VKY_RESERVED_02     rmb       1         $FFCA - NOT reserved: see VKY_MCR2
VKY_RESERVED_03     rmb       1         $FFCB - GFX MODE: b0 global HIRES4,
*                                       b3:1 palette group.  Not exposed:
*                                       it forces ALL THREE bitmaps to 4bpp
*                                       with no per-plane way back out, so
*                                       SS.BmCfg does it per bitmap instead
VKY_RESERVED_04     rmb       1

* $FFCA is VICKY_MASTER_REG[10], "VKY Master Ctrl Reg 2", and its bit 0
* is the REAL enable for the line drawing engine
* (TinyVickyControl_Registers.v:93, 220-223, 251 -> Mstr_Ctrl_DrawLine_Enable).
* LD_CTRL's own bit 0 is dead.  With this bit clear the video master
* engine skips DrawingLine_Begin entirely and the pixel FIFO never
* drains; with it set it runs a drain window on odd visible lines.
* LEAVING IT ON COSTS NOTHING - both paths wait out the rest of the
* scanline either way.
* It is the seventh byte of V.BordBack, inside the 16-byte $FFC0-$FFCF
* block PullCore copies on every terminal switch, so the line-draw enable
* is already per-terminal state that survives a switch, for free.
VKY_MCR2            equ       VKY_RESERVED_02
VKY_MCR2_LineDraw   equ       %00000001
* Valid in graphics mode only
BACKGROUND_COLOR_B  rmb       1         when in graphic mode, if a pixel is "0" then the background pixel is chosen
BACKGROUND_COLOR_G  rmb       1
BACKGROUND_COLOR_R  rmb       1
* Cursor registers
VKY_TXT_CURSOR_CTRL_REG rmb       1         [0] Enable Text Mode
VKY_TXT_START_ADD_PTR rmb       1         this is an offset to change the starting address of the text mode Buffer (in X)
VKY_TXT_CURSOR_CHAR_REG rmb       1
VKY_TXT_CURSOR_COLR_REG rmb       1
VKY_TXT_CURSOR_X_REG_H rmb       1
VKY_TXT_CURSOR_X_REG_L rmb       1
VKY_TXT_CURSOR_Y_REG_H rmb       1
VKY_TXT_CURSOR_Y_REG_L rmb       1
; Line interrupt
VKY_LINE_IRQ_CTRL_REG rmb       1         [0] - enable line 0 - write only
VKY_LINE_CMP_VALUE_HI rmb       1         write only [7:0]
VKY_LINE_CMP_VALUE_LO rmb       1         write only [3:0]

VKY_PIXEL_X_POS_HI  equ       VKY_LINE_IRQ_CTRL_REG this is where on the video line is the pixel
VKY_PIXEL_X_POS_LO  equ       VKY_LINE_CMP_VALUE_LO or what pixel is being displayed when the register is read
VKY_LINE_Y_POS_HI   equ       VKY_LINE_CMP_VALUE_HI this is the line value of the raster
VKY_LINE_Y_POS_LO   rmb       1

* Text control bit definitions
Mstr_Ctrl_Text_Mode_En equ       $01       enable the text mode
Mstr_Ctrl_Text_Overlay equ       $02       enable the overlay of the text mode on top of graphic mode (the background color is ignored)
Mstr_Ctrl_Graph_Mode_En equ       $04       enable the graphic mode
Mstr_Ctrl_Bitmap_En equ       $08       enable the bitmap module in Vicky
Mstr_Ctrl_TileMap_En equ       $10       enable the tile module in Vicky
Mstr_Ctrl_Sprite_En equ       $20       enable the sprite module in Vicky
Mstr_Ctrl_GAMMA_En  equ       $40       this enables the gamma correction - the analog and DVI have different color values; the gamma is great to correct the difference
Mstr_Ctrl_Disable_Vid equ       $80       this will disable the scanning of the video hence giving 100% bandwidth to the CPU

* Cursor control bit definitions
Vky_Cursor_Enable   equ       $01
Vky_Cursor_Flash_Rate0 equ       $02
Vky_Cursor_Flash_Rate1 equ       $04
Vky_Cursor_Flash_Disable equ       $08

FON_SET             equ       %00100000
FON_OVLY            equ       %00010000
MON_SLP             equ       %00001000
DBL_Y               equ       %00000100
DBL_X               equ       %00000010
CLK_70              equ       %00000001

* Border control bit definitions
Border_Ctrl_Enable  equ       $01

BITMAP_BLK            equ	      $C0
; Bitmap
;BM0
TyVKY_BM0_CTRL_REG  equ       $F000
BM0_Ctrl            equ       $01       enable the BM0
BM0_LUT0            equ       $02       LUT0
BM0_LUT1            equ       $04       LUT1
TyVKY_BM0_START_ADDY_H equ       $F001
TyVKY_BM0_START_ADDY_M equ       $F002
TyVKY_BM0_START_ADDY_L equ       $F003
;BM1
TyVKY_BM1_CTRL_REG  equ       $F008
BM1_Ctrl            equ       $01       enable the BM0
BM1_LUT0            equ       $02       LUT0
BM1_LUT1            equ       $04       LUT1
TyVKY_BM1_START_ADDY_H equ       $F009
TyVKY_BM1_START_ADDY_M equ       $F00A
TyVKY_BM1_START_ADDY_L equ       $F00B
;BM2
TyVKY_BM2_CTRL_REG  equ       $F010
BM2_Ctrl            equ       $01       enable the BM0
BM2_LUT0            equ       $02       LUT0
BM2_LUT1            equ       $04       LUT1
BM2_LUT2            equ       $08       LUT2
TyVKY_BM2_START_ADDY_H equ       $F011
TyVKY_BM2_START_ADDY_M equ       $F012
TyVKY_BM2_START_ADDY_L equ       $F013

********************************************************************
* Line drawing engine (source/LineDraw.v)
*
* The registers live INSIDE the bitmap register block, selected by
* address bit 7, so they sit at the bitmap base + $80.  CS_VICKY_BITMAP
* covers $18_1000-$18_10FF, i.e. offset $1000 within block $C0, and only
* address bits 2:0 are decoded - so the eight bytes alias through the
* whole $x080-$x0FF half.  grfdrv256 maps $C0 into slot 3 and reaches
* them at $7080 ($6000 slot + $1000 page + $80).
*
* WRITE and READ are different registers at the same addresses, and the
* read side is not the write side reversed - see LD_FIFO_* below.
LD.Base             equ       $F080
LD_CTRL             equ       LD.Base+0           write: control
LD_COLOR            equ       LD.Base+1           write: colour (CLUT index)
LD_X0_H             equ       LD.Base+2
LD_X0_L             equ       LD.Base+3
LD_X1_H             equ       LD.Base+4
LD_X1_L             equ       LD.Base+5
LD_Y0               equ       LD.Base+6
LD_Y1               equ       LD.Base+7
* Read side.  LD_CTRL reads back as written except bit 7, which is
* COMPLETE.  X0 and Y0 cannot be read back at all; +4..+7 return X1 and
* Y1 with their bytes swapped, and the RTL's comments on the two Y reads
* contradict its own reset block.  Nothing should read them.
LD_FIFO_H           equ       LD.Base+2           read: pixels queued, bits 12:8
LD_FIFO_L           equ       LD.Base+3           read: pixels queued, bits 7:0
* These are offsets from LD.Base for code that has the block mapped
* somewhere of its own choosing.
LD.Ctrl             equ       0
LD.Color            equ       1
LD.X0H              equ       2
LD.X0L              equ       3
LD.X1H              equ       4
LD.X1L              equ       5
LD.Y0               equ       6
LD.Y1               equ       7
LD.FifoH            equ       2                   read
LD.FifoL            equ       3                   read
*
* Control bits.  BIT 0 IS DEAD: it reaches LineDrawingEnable_i, which
* LineDraw.v resynchronises into LineDrawingEnable_ReSync and then never
* reads.  The real enable is $FFCA bit 0 (VKY_MCR2_LineDraw below).
LD_CTRL_Go          equ       %00000010           a LEVEL, not a pulse
LD_CTRL_BM0         equ       %00000000           plane select, bits 3:2
LD_CTRL_BM1         equ       %00000100
LD_CTRL_BM2         equ       %00001000
LD_CTRL_Plane       equ       %00001100
LD_CTRL_RstFIFO     equ       %00010000           clears the FIFO AND the
*                                                 Bresenham machine - see below
LD_STAT_Complete    equ       %10000000           read-only, in LD_CTRL
*
* GO is a level.  The machine is IDLE -> RUN -> DONE, and it sits in DONE
* until GO returns to 0, so the sequence is: write the endpoints, raise
* GO in a store of its own (the endpoint registers are NOT resynchronised
* into the engine's 100 MHz domain), poll COMPLETE, lower GO.
*
* COMPLETE MEANS THE BRESENHAM WALK FINISHED, NOT THAT A PIXEL REACHED
* MEMORY.  Pixels go into a 4,096-entry FIFO (24-bit address + colour per
* entry) which the video engine drains on ODD VISIBLE LINES ONLY, and
* only on cycles the CPU is not using the SRAM.  The FIFO's full flag is
* NOT connected and its write enable is unconditional, so an overrun
* loses pixels silently: pace on LD_FIFO_H/L, which is the only defence.
LD.Depth            equ       4096                FIFO entries, i.e. pixels
LD.Room             equ       LD.Depth-320        stop enqueueing above this
LD.MaxX             equ       319                 an endpoint outside 0..319 /
LD.MaxY             equ       239                 0..239 means the engine NEVER
*                                                 starts and never completes
LD.Poll             equ       200                 COMPLETE poll limit: the walk
*                                                 takes ~3.2us, ~26 cycles at 8MHz
*
* RECOVERY FROM A POLL TIMEOUT IS TO LOWER GO, AND NOTHING ELSE.  A
* timeout means the machine is still in IDLE - the only way COMPLETE
* fails to arrive once GO is up, since RUN always terminates - and
* clearing GO returns it to IDLE cleanly.  LD_CTRL_RstFIFO must NOT be
* used for it: it clears the FIFO as well, discarding pixels that belong
* to lines already counted as drawn.

**  THESE ARE DUPLICATES, RECONCILE THIS LATER
********************************************************************
* vtio graphics constants
********************************************************************
* Constants used in SS.DScrn to set the display screen type

FX_GAM             equ       %01000000              Gamma Correction On
FX_SPR             equ       %00100000              Sprites On
FX_TIL             equ       %00010000              Tile Maps On
FX_BM              equ       %00001000              Bitmaps On
FX_GRF             equ       %00000100              Graphics Mode On
FX_OVR             equ       %00000010              Overlay Text on Graphics
FX_TXT             equ       %00000001              Text Mode On
FT_FSET            equ       %00100000              Font Set 1 On (0=Font Set 0)
FT_FOVR            equ       %00010000              FG and BG colors displayed when overlay text 0=transparent
FT_MON             equ       %00001000              Turn off monitor sync and sleep monitor
FT_DBX             equ       %00000100              Double-wide text mode characters
FT_DBY             equ       %00000010              Double-high text mode characters
FT_CLK70           equ       %00000001              70 Hz screen (640x400 txt,320x200 grf)
FX_OMIT            equ       %11111111              Setting for SS.DScrn don't change first byte in MCR
FT_OMIT            equ       %11111111              Setting for SS.DScrn don't change second byte in MCR

* FT_FOVR:  0=display only FG color, all others transparent
*           1=display FG & BG color, only BG color 0 is transparent
* CLK_70:   0=60 Hz screen (640x480 txt, 320x240 grf)
*           0=70 Hz screen (640x400 txt, 32
**  END OF DUPLICATE CONSTANTS

; Tile map
TyVKY_TL_CTRL0      equ       $F100
; Bit Field Definition for the Control Register
TILE_Enable         equ       $01
TILE_LUT0           equ       $02
TILE_LUT1           equ       $04
TILE_LUT2           equ       $08
TILE_SIZE           equ       $10       0 -> 16x16, 0 -> 8x8

;
;Tile map layer 0 registers
TL0_CONTROL_REG     equ       $F100     bit[0] - enable, bit[3:1] - LUT select
TL0_START_ADDY_L    equ       $F101     not used right now - starting address to where is the map
TL0_START_ADDY_M    equ       $F102
TL0_START_ADDY_H    equ       $F103
TL0_MAP_X_SIZE_L    equ       $F104     the size X of the map
TL0_MAP_X_SIZE_H    equ       $F105
TL0_MAP_Y_SIZE_L    equ       $F106     the size Y of the map
TL0_MAP_Y_SIZE_H    equ       $F107
TL0_MAP_X_POS_L     equ       $F108     the position X of the map
TL0_MAP_X_POS_H     equ       $F109
TL0_MAP_Y_POS_L     equ       $F10A     the position Y of the map
TL0_MAP_Y_POS_H     equ       $F10B
;Tile MAP Layer 1 Registers
TL1_CONTROL_REG     equ       $F10C     bit[0] - enable, bit[3:1] - LUT select
TL1_START_ADDY_L    equ       $F10D     not used right now - starting address to where is the map
TL1_START_ADDY_M    equ       $F10E
TL1_START_ADDY_H    equ       $F10F
TL1_MAP_X_SIZE_L    equ       $F110     the size X of the map
TL1_MAP_X_SIZE_H    equ       $F111
TL1_MAP_Y_SIZE_L    equ       $F112     the size Y of the map
TL1_MAP_Y_SIZE_H    equ       $F113
TL1_MAP_X_POS_L     equ       $F114     the position X of the map
TL1_MAP_X_POS_H     equ       $F115
TL1_MAP_Y_POS_L     equ       $F116     the position Y of the map
TL1_MAP_Y_POS_H     equ       $F117
;Tile MAP Layer 2 Registers
TL2_CONTROL_REG     equ       $F118     bit[0] - enable, bit[3:1] - LUT select,
TL2_START_ADDY_L    equ       $F119     not used right now - starting address to where is the map
TL2_START_ADDY_M    equ       $F11A
TL2_START_ADDY_H    equ       $F11B
TL2_MAP_X_SIZE_L    equ       $F11C     the size X of the map
TL2_MAP_X_SIZE_H    equ       $F11D
TL2_MAP_Y_SIZE_L    equ       $F11E     the size Y of the map
TL2_MAP_Y_SIZE_H    equ       $F11F
TL2_MAP_X_POS_L     equ       $F120     the position X of the map
TL2_MAP_X_POS_H     equ       $F121
TL2_MAP_Y_POS_L     equ       $F122     the position Y of the map
TL2_MAP_Y_POS_H     equ       $F123


TILE_MAP_ADDY0_L    equ       $F180
TILE_MAP_ADDY0_M    equ       $F181
TILE_MAP_ADDY0_H    equ       $F182
TILE_MAP_ADDY0_CFG  equ       $F183
TILE_MAP_ADDY1      equ       $F184
TILE_MAP_ADDY2      equ       $F188
TILE_MAP_ADDY3      equ       $F18C
TILE_MAP_ADDY4      equ       $F190
TILE_MAP_ADDY5      equ       $F194
TILE_MAP_ADDY6      equ       $F198
TILE_MAP_ADDY7      equ       $F19C


XYMATH_CTRL_REG     equ       $D300     reserved
XYMATH_ADDY_H       equ       $D301     w
XYMATH_ADDY_M       equ       $D302     w
XYMATH_ADDY_L       equ       $D303     w
XYMATH_ADDY_POSX_H  equ       $D304     r/w
XYMATH_ADDY_POSX_L  equ       $D305     r/w
XYMATH_ADDY_POSY_H  equ       $D306     r/w
XYMATH_ADDY_POSY_L  equ       $D307     r/w
XYMATH_BLOCK_OFF_H  equ       $D308     r only - low block offset
XYMATH_BLOCK_OFF_L  equ       $D309     r only - hi block offset
XYMATH_MMU_BLOCK    equ       $D30A     r only - which mmu block
XYMATH_ABS_ADDY_H   equ       $D30B     low absolute results
XYMATH_ABS_ADDY_M   equ       $D30C     mid absolute results
XYMATH_ABS_ADDY_L   equ       $D30D     hi absolute results

; Sprite block0
SPRITE_Ctrl_Enable  equ       $01
SPRITE_LUT0         equ       $02
SPRITE_LUT1         equ       $04
SPRITE_DEPTH0       equ       $08       00 = total front - 01 = in between l0 and l1, 10 = in between l1 and l2, 11 = total back
SPRITE_DEPTH1       equ       $10
SPRITE_SIZE0        equ       $20       00 = 32x32 - 01 = 24x24 - 10 = 16x16 - 11 = 8x8
SPRITE_SIZE1        equ       $40


* Sprite attribute records (128 total, 8 bytes each) live in VICKY page
* $C0 at page offsets $1300-$16FF (record n at $1300+8*n). The SPn_*
* equates below assume that page mapped in MMU slot 7 ($E000 window,
* the vtio/system-state convention) -> records at $F300+. Multi-byte
* fields are BIG-endian (6809 rework, rc7 silicon): +1 = address HIGH,
* +4 = X HIGH, +6 = Y HIGH - so a 16-bit STD at the _H offset stores
* X or Y correctly in one instruction. (Pre-rework cores and the
* official 65C02 documentation were little-endian; equates corrected
* 2026-08-31.) Generic per-record offsets for indexed access:
SPR_CTRL            equ       0         control byte (SPRITE_* bits above)
SPR_ADDY_H          equ       1         pixel data physical address 23:16
SPR_ADDY_M          equ       2         pixel data physical address 15:8
SPR_ADDY_L          equ       3         pixel data physical address 7:0
SPR_X_H             equ       4         X 15:8 (screen left = 32)
SPR_X_L             equ       5         X 7:0
SPR_Y_H             equ       6         Y 15:8 (screen top = 32)
SPR_Y_L             equ       7         Y 7:0
SPR_REC_SIZE        equ       8         bytes per sprite record

* Where the sprite machinery lives (map these VICKY pages via an MMU slot):
SPRITE_BLK          equ       $C0       VICKY page holding the 128 sprite records
SPRITE_REC_OFF      equ       $1300     page offset of record 0 (records at +n*SPR_REC_SIZE)
GRPH_LUT0_OFF       equ       $1000     graphics LUT0 offset within FONT_BLK ($C1); LUTn at +$400*n, 256 entries x B,G,R,A

SP0_Ctrl            equ       $F300
SP0_Addy_H          equ       $F301     pixel addr 23:16 (BIG-endian)
SP0_Addy_M          equ       $F302     pixel addr 15:8
SP0_Addy_L          equ       $F303     pixel addr 7:0
SP0_X_H             equ       $F304     X 15:8 - STD here writes X in one op
SP0_X_L             equ       $F305     X 7:0
SP0_Y_H             equ       $F306     Y 15:8 - STD here writes Y in one op
SP0_Y_L             equ       $F307     Y 7:0

SP1_Ctrl            equ       $F308
SP1_Addy_H          equ       $F309     pixel addr 23:16 (BIG-endian)
SP1_Addy_M          equ       $F30A     pixel addr 15:8
SP1_Addy_L          equ       $F30B     pixel addr 7:0
SP1_X_H             equ       $F30C     X 15:8 - STD here writes X in one op
SP1_X_L             equ       $F30D     X 7:0
SP1_Y_H             equ       $F30E     Y 15:8 - STD here writes Y in one op
SP1_Y_L             equ       $F30F     Y 7:0

SP2_Ctrl            equ       $F310
SP2_Addy_H          equ       $F311     pixel addr 23:16 (BIG-endian)
SP2_Addy_M          equ       $F312     pixel addr 15:8
SP2_Addy_L          equ       $F313     pixel addr 7:0
SP2_X_H             equ       $F314     X 15:8 - STD here writes X in one op
SP2_X_L             equ       $F315     X 7:0
SP2_Y_H             equ       $F316     Y 15:8 - STD here writes Y in one op
SP2_Y_L             equ       $F317     Y 7:0

SP3_Ctrl            equ       $F318
SP3_Addy_H          equ       $F319     pixel addr 23:16 (BIG-endian)
SP3_Addy_M          equ       $F31A     pixel addr 15:8
SP3_Addy_L          equ       $F31B     pixel addr 7:0
SP3_X_H             equ       $F31C     X 15:8 - STD here writes X in one op
SP3_X_L             equ       $F31D     X 7:0
SP3_Y_H             equ       $F31E     Y 15:8 - STD here writes Y in one op
SP3_Y_L             equ       $F31F     Y 7:0

SP4_Ctrl            equ       $F320
SP4_Addy_H          equ       $F321     pixel addr 23:16 (BIG-endian)
SP4_Addy_M          equ       $F322     pixel addr 15:8
SP4_Addy_L          equ       $F323     pixel addr 7:0
SP4_X_H             equ       $F324     X 15:8 - STD here writes X in one op
SP4_X_L             equ       $F325     X 7:0
SP4_Y_H             equ       $F326     Y 15:8 - STD here writes Y in one op
SP4_Y_L             equ       $F327     Y 7:0




; PAGE $C1
TyVKY_LUT0          equ       $E800     -$d000 - $d3ff
TyVKY_LUT1          equ       $EC00     -$d400 - $d7ff
TyVKY_LUT2          equ       $F000     -$d800 - $dbff
TyVKY_LUT3          equ       $F400     -$dc00 - $dfff


********************************************************************
* Sound definitions (MMU Page $C4)
*
SND.Base            equ       $0000
SIDL.Base           equ       SND.Base+$0000
SIDM.Base           equ       SND.Base+$0080
SIDR.Base           equ       SND.Base+$0100
PSGL.Base           equ       SND.Base+$0200
PSGM.Base           equ       SND.Base+$0208
PSGR.Base           equ       SND.Base+$0210

********************************************************************
* Direct Memory Access (DMA) definitions
*
* CORRECTED 2026-09-20 against the rc16 RTL (fpga-6809-cores-staging/source/
* TinyVKY_DMA_Reg_Block.v).  Everything from $FEC4 on was WRONG: the address
* fields were one byte low and there is no dedicated 1D size register at all.
* Nothing in the tree referenced these, so correcting them changes no built
* byte - which is exactly why it had to be done before anyone wrote code
* from them.  The RTL's write path is "VDMA_REG[Bus_A_i[4:0]] <= Bus_D_i"
* (:66) and CS_DMA covers $FEC0-$FEDF (TinyVKY2K2_IO_Page0_Devices.v:631),
* so the register index IS the offset from DMA.Base.
*
* READ BACK NOTHING EXCEPT $FEC1.  The read path (:73-100) reverses each
* group of four registers, so reading $FEC4 returns what was written to
* $FEC7.  The two halves of the RTL were written to different conventions
* and never reconciled; the write layout below is the one the engine uses.
*
DMA.Base            equ       $FEC0

                    org       0
DMA_CTRL_REG        rmb       1         fec0
DMA_STATUS_REG      rmb       1         fec1 read: bit 7 = busy
DMA_DATA_2_WRITE    equ       DMA_STATUS_REG write: the 8-bit fill byte
* 16-bit fill value, used when DMA_CTRL_16Bit is set.  Was RESERVED_0/1.
DMA_FILL_16_H       rmb       1         fec2
DMA_FILL_16_L       rmb       1         fec3
DMA_RESERVED_0      equ       DMA_FILL_16_H  old name, wrong meaning
DMA_RESERVED_1      equ       DMA_FILL_16_L  old name, wrong meaning
* Source address.  NOTE: $FEC4 is unused - the field starts at $FEC5.
DMA_UNUSED_0        rmb       1         fec4
DMA_SOURCE_ADDR_H   rmb       1         fec5
DMA_SOURCE_ADDR_M   rmb       1         fec6
DMA_SOURCE_ADDR_L   rmb       1         fec7
* Destination address.  $FEC8 is unused - the field starts at $FEC9.
DMA_UNUSED_1        rmb       1         fec8
DMA_DEST_ADDR_H     rmb       1         fec9
DMA_DEST_ADDR_M     rmb       1         feca
DMA_DEST_ADDR_L     rmb       1         fecb
* READING the destination back needs different addresses, because the
* register block's read map is a different permutation from its write
* map: writes at fec9/feca/fecb land in REG[9]/[10]/[11], but reads at
* feca/fec9/fec8 return REG[9]/[10]/[11].  So the byte written as H
* comes back at feca, M at fec9 and L at fec8.  Diagnostic only.
DMA_DEST_RD_H       equ       DMA_DEST_ADDR_M   feca returns what H was given
DMA_DEST_RD_M       equ       DMA_DEST_ADDR_H   fec9 returns what M was given
DMA_DEST_RD_L       equ       DMA_UNUSED_1      fec8 returns what L was given
* Size.  X and Y are the 2D block size; in 1D mode the SAME registers carry
* a 24-bit byte count, assembled by the core as
*     Count1D = { Y_Size[7:0], X_Size[15:0] }     (TinyVKY_DMA_Controller.v:210)
* so the 1D count's three bytes are NOT contiguous and NOT in address order.
* The DMA_SIZE_1D_* names below are kept, and now point at the right bytes.
DMA_SIZE_X_H        rmb       1         fecc
DMA_SIZE_X_L        rmb       1         fecd
DMA_SIZE_Y_H        rmb       1         fece
DMA_SIZE_Y_L        rmb       1         fecf
DMA_SIZE_1D_H       equ       DMA_SIZE_Y_L   count bits 23:16 -> fecf
DMA_SIZE_1D_M       equ       DMA_SIZE_X_H   count bits 15:8  -> fecc
DMA_SIZE_1D_L       equ       DMA_SIZE_X_L   count bits 7:0   -> fecd
* Y_Size high must be 0 in 1D mode: it is not part of Count1D, but in 2D
* mode the whole 16-bit Y_Size is compared against the stride counter.
* Stride in 2D mode.  Source and destination have independent strides.
DMA_SRC_STRIDE_H    rmb       1         fed0
DMA_SRC_STRIDE_L    rmb       1         fed1
DMA_DST_STRIDE_H    rmb       1         fed2
DMA_DST_STRIDE_L    rmb       1         fed3
DMA_SRC_STRIDE_X_H  equ       DMA_SRC_STRIDE_H  old name
DMA_SRC_STRIDE_X_L  equ       DMA_SRC_STRIDE_L  old name
DMA_DST_STRIDE_Y_H  equ       DMA_DST_STRIDE_H  old name
DMA_DST_STRIDE_Y_L  equ       DMA_DST_STRIDE_L  old name
* $FED4-$FED7 decode but are unused by the engine.
DMA_UNUSED_2        rmb       4         fed4-fed7
DMA_RESERVED_2      equ       DMA_UNUSED_2   old name, wrong position
DMA_RESERVED_3      equ       DMA_UNUSED_2+1 old name, wrong position
DMA_RESERVED_4      equ       DMA_UNUSED_2+2 old name, wrong position
* $FED8-$FEDF are decoded by CS_DMA but the register file is only 24 entries
* (VDMA_REG[0:23]), so writes there are discarded and reads return $FF.
DMA_RESERVED_5      rmb       1         fed8
DMA_RESERVED_6      rmb       1         fed9
DMA_RESERVED_7      rmb       1         feda
DMA_RESERVED_8      rmb       1         fedb

* DMA_CTRL_REG bit definitions
* Bits 4 and 5 are NOT spare.  The RTL's own comment calls them reserved and
* the RTL's own logic disagrees: VMDA_Data_Mask_o = VDMA_Control_Reg[5:4]
* (TinyVKY_DMA_Controller.v:261) drives the SRAM byte-lane enables through
* TinyVicky_MemoryManagementBlock.v:193-194.  Setting either one silently
* suppresses half of every transfer.  They must be written 0.
DMA_CTRL_Enable     equ       $01       required - without it start is ignored
DMA_CTRL_1D_2D      equ       $02       0 = 1D linear, 1 = 2D block
DMA_CTRL_Fill       equ       $04       0 = copy src->dst, 1 = fill dst
DMA_CTRL_Int_En     equ       $08       interrupt on completion
DMA_CTRL_MaskLSB    equ       $10       suppress even byte lane - keep 0
DMA_CTRL_MaskMSB    equ       $20       suppress odd byte lane - keep 0
DMA_CTRL_16Bit      equ       $40       16-bit transfer: twice the bytes a clock
DMA_CTRL_Start_Trf  equ       $80       rising edge starts; clear before the next
DMA_CTRL_NotUsed0   equ       DMA_CTRL_MaskLSB   old name, wrong meaning
DMA_CTRL_NotUsed1   equ       DMA_CTRL_MaskMSB   old name, wrong meaning
DMA_CTRL_NotUsed2   equ       DMA_CTRL_16Bit     old name, wrong meaning

* DMA_STATUS_REG bit definitions
DMA_STATUS_TRF_IP   equ       $80       transfer in progress


* MIDI Synth Chip
SAM2695.Base       equ        $FF30
                   org        $0
MIDI_STATUS        rmb        1                   Read: Bit[1] = Rx_empty, Bit[2] = Tx_empty
MIDI_FIFO_DATA     rmb        1                   Read and Write Data Port 
MIDI_RXD_COUNT_LOW rmb        1                   Rx FIFO Data Count LOW
MIDI_RXD_COUNT_HI  rmb        1                   Rx FIFO Data Count Hi - Only the 4 first bit are valid
MIDI_TXD_COUNT_LOW rmb        1                   Tx FIFO Data Count LOW 
MIDI_TXD_COUNT_HI  rmb        1                   Tx FIFO Data Count Hi - Only the 4 first bit are valid


* WizFi360 Registers, 2K x 2 FIFO
* Wifi_Control_Register:
* Bit[0] = 0 = 115,200K Mode, 1 = 921,600K Mode
* Bit[1] = 0 Default, 1 = Reset FIFO (you need to bring it back to 0) This is directly connected to reset line of the FIFO
* Bit[2] = RX FIFO Empty ( 1 = Empty, 0 = Data Available)
* Bit[3] = TX FIFO Empty ( 1 = Empty, 0 = Data Available)
WizFi.Base          equ       $FF20
WizFi.TxEmpty       equ       %00001000
WizFi.RxEmpty       equ       %00000100
WizFi.Reset         equ       %00000010
WizFi.Rate          equ       %00000001
                    org       $0
WizFi_CtrlReg       rmb       1
WizFi_DataReg       rmb       1
WizFi_RxD_RD_Cnt    rmb       2
WizFi_RxD_WR_Cnt    rmb       2
WizFi_TxD_RD_Cnt    rmb       2
WizFi_TxD_WR_Cnt    rmb       2

******************************************************************
* VS1053 (MP3/OGG/WAV decoder) SPI bridge definitions
*
* Fixed I/O, identical on the K2 and Jr2 (core block VS1053_SPI_Interface,
* CS $FF50-$FF5F; offsets 8-15 mirror 0-7 on read).  The bridge runs 32-bit
* SCI transactions over XCSn and streams a 2 KB byte FIFO to SDI over XDCSn
* as DREQ permits; the CPU never sees DREQ.  16-bit pairs are BIG-endian
* (high byte at the lower offset) since the 2026-09-05 core fix - cores
* built before it have VS_DATA and VS_FIFOCNT the other way round.
* SCI write: VS_SCIREG=reg, std VS_DATA, VS_CTRL=0, VS_CTRL=VS_START, wait !VS_BUSY
* SCI read:  VS_SCIREG=reg, VS_CTRL=0, VS_CTRL=VS_START+VS_READ, wait !VS_BUSY, ldd VS_DATA
* Stream:    while !(VS_FIFOSTAT & VS_FIFO_FULL) store bytes to VS_FIFO
VS1053.Base         equ       $FF50
                    org       0
VS_CTRL             rmb       1         bit0 START (0->1 edge starts an SCI transaction, does not self-clear), bit1 READ, bit2 FAST (rc12), bit3 RESET (rc12), bit7 BUSY (r/o)
VS_SCIREG           rmb       1         SCI register number in the low nibble (VS_MODE..VS_AICTRL3)
VS_DATA             equ       .         16-bit SCI data, big-endian: std to send, ldd for the last read result
VS_DATAHI           rmb       1         high byte
VS_DATALO           rmb       1         low byte
VS_FIFOSTAT         rmb       1         bit7 FIFO empty, bit6 FIFO full, bits 2-0 = count bits 10-8; reading it snapshots the count
VS_FIFOCNTL         rmb       1         count bits 7-0 from that snapshot (ldd VS_FIFOSTAT then anda #VS_FIFO_CNTHI = 11-bit count)
VS_FIFOCNT          equ       VS_FIFOSTAT 16-bit alias for the ldd
                    rmb       1         reads $00
VS_FIFO             rmb       1         SDI stream data write: each byte is sent to the chip as DREQ permits
* VS_CTRL bits
VS_START            equ       %00000001
VS_READ             equ       %00000010
VS_FAST             equ       %00000100 rc12+: SPI clock IO_Clk/4 = 6.29 MHz, legal only after CLOCKF is raised (SCI reads need CLKI >= 44 MHz);
*                                       0 (reset default) = IO_Clk/16 = 1.57 MHz, in spec at the chip's boot clock.  Pre-rc12 cores ignore the bit.
VS_RESET            equ       %00001000 rc12+: 1 = hold the chip's XRESET low (bit engine idle, SDI FIFO flushed) - the only way back
*                                       for a chip stuck with DREQ low, since every SCI command waits for DREQ.  Pre-rc12 cores ignore it.
VS_BUSY             equ       %10000000
* VS_FIFOSTAT bits
VS_FIFO_EMPTY       equ       %10000000
VS_FIFO_FULL        equ       %01000000
VS_FIFO_CNTHI       equ       %00000111
* VS1053 SCI register numbers (for VS_SCIREG)
VS_MODE             equ       $0        mode control
VS_STATUS           equ       $1        status
VS_BASS             equ       $2        bass/treble
VS_CLOCKF           equ       $3        clock frequency + multiplier
VS_DECODE_TIME      equ       $4        decode time in seconds
VS_AUDATA           equ       $5        misc. audio data (sample rate, channels)
VS_WRAM             equ       $6        RAM read/write
VS_WRAMADDR         equ       $7        RAM address
VS_HDAT0            equ       $8        stream header data 0 (read only)
VS_HDAT1            equ       $9        stream header data 1 (read only)
VS_AIADDR           equ       $A        application start address
VS_VOL              equ       $B        volume (left/right attenuation, 0.5dB steps)
VS_AICTRL0          equ       $C        application control 0
VS_AICTRL1          equ       $D        application control 1
VS_AICTRL2          equ       $E        application control 2
VS_AICTRL3          equ       $F        application control 3

******************************************************************
* NES/SNES pad port (the FNX4N4S connector; core block TinyVKY_NES_SNES,
* CPU fixed decode $FF80-$FF8F, identical on the K2 and Jr2).  Four pads,
* all NES or all SNES (one MODE bit for the port).  Write NES_TRIG to
* shift a reading in; NES_DONE is set when it is complete and cleared by
* the next trigger.  The pad registers shift in place, so read them only
* while NES_DONE is set.  Data reads 0 = pressed.  Pad n at NES_PAD0+2n:
* NES mode, the first byte = A B Select Start Up Down Left Right (bit 7
* first); SNES mode, the first byte = B Y Select Start Up Down Left Right
* and the second byte's low nibble = A X L R.
NES.Base            equ       $FF80
NES_CTRL            equ       0         write: EN, MODE, TRIG; read: the same with DONE in bit 6
NES_PAD0            equ       4
NES_EN              equ       %00000001 port on
NES_MODE            equ       %00000100 1 = SNES (12 bits), 0 = NES (8 bits)
NES_DONE            equ       %01000000 read only: a reading is complete
NES_TRIG            equ       %10000000 start a reading; the core clears it when it latches

* DIP Switches for Jr/Jr2/K2.. 
K2_DIP_SW.Base      equ       $FF90
SW_GAMMA_ON         equ       %10000000
SW_USER2            equ       %01000000
SW_USER1            equ       %00100000
SW_USER0            equ       %00010000
SW_BOOT_MODE3       equ       %00001000
SW_BOOT_MODE2       equ       %00000100
SW_BOOT_MODE1       equ       %00000010
SW_BOOT_MODE0       equ       %00000001

                    ENDC
