                    IFNE      F256VTIO.D-1
F256VTIO.D          SET       1

********************************************************************
* vtio definitions for the F256
*
* Everything that the vtio driver needs is defined here, including
* static memory definitions.

* Constant definitions.
KBufSz              EQU       8                   the circular buffer size

* Driver static memory.
                    ORG       V.SCF
V.CurRow            RMB       1                   the current row where the next character goes
V.CurCol            RMB       1                   the current column where the next character goes
V.CurChr            RMB       1                   the character under the cursor
V.CapsLck           RMB       1                   the CAPS LOCK key up/down flag ($00 = up)
V.SHIFT             RMB       1                   the SHIFT key up/down flag ($00 = up)
V.CTRL              RMB       1                   the CTRL key up/down flag ($00 = up)
V.ALT               RMB       1                   the ALT key up/down flag ($00 = up)
V.KySns             RMB       1                   the key sense flags
V.EscCh1            RMB       2                   the escape vector handler for the first character after the escape code
V.EscVect           RMB       2                   the escape vector handle
V.Reverse           RMB       1                   the reverse video flag ($00 = off, $FF = on)
V.FBCol             RMB       1                   the currently selected foreground and background color
V.BordCol           RMB       1                   the currently selected border color
V.KCVect            RMB       2                   the PS/2 key code handler
V.IBufH             RMB       1                   the input buffer head pointer
V.IBufT             RMB       1                   the input buffer tail pointer

V.WWidth            RMB       1                   the window width
V.WHeight           RMB       1                   the window heightx

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

********************************************************************
* vtio Graphics definitions for the F256
********************************************************************

V.ST		    RMB	      1			   Screen type 0=Term 1=Gfx

* VICKY MASTER CONTROL REGISTER to enable graphics and capabilities
* | 7 |   6   |    5   |   4  |    3   |   2   |   1   |   0  |
* | X | GAMMA | SPRITE | TILE | BITMAP | GRAPH | OVRLY | TEXT |
* |   -----   | FON_SET|FON_OV| MON_SLP| DBL_Y | DBL_X | CLK70|
* $FFC0 MASTER_CTRL_REG_L, MASTER_CTRL_REG_H

V.V_MCR		    RMB	      2			  2 bytes for Vicky Control Register

* VICKY LAYER CONTROL REGISTER to set bitmaps and/or tile maps for display
* | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
* | - |   LAYER1  | - |  LAYER 0  |
* |       ------      |  LAYER 2  |
* 000=BM0 001=BM1 010=BM2 100=TM0 101=TM1 110=TM2
* $FFC2 VKY_RESERVED_00, VKY_RESERVED_01

V.V_LayerCTL	   RMB	      2

* BITMAPS
* Store starting page for bitmaps, and CLUT# and bitmap enable bits.  Must be in first 512K RAM.
* $01_0000-$07_FFFF (OS9 Memory Blocks $01-$3F)
* Byte 1 of Bitmap register is CLUT(4 CLUTS:0-3)/Enable
* | 7 | 6 | 5 | 4 | 3 | 2 | 1 |   0    |
* |       -----       |  CLUT | ENABLE |
* Next 3 bytes in register used for physical 19 bit address for bitmap
* Max address is 07FFFF (must be in 1st 512K), which is 19 bits
* Store block# and then convert to 19 bit address in driver

V.BM0Blk	    RMB	      1			  bitmap0 block
V.BM0Cl_En	    RMB	      1			  bitmap0 |clut|enable|
V.BM1Blk	    RMB	      1			  bitmap1 block
V.BM1Cl_En	    RMB	      1			  bitmap1 |clut|enable|
V.BM2Blk	    RMB	      1			  bitmap2 block
V.BM2Cl_En	    RMB	      1			  bitmap2 |clut|enable|

* CLUT - need to store mirror of CLUT data so switching windows will work
* Store block# where high 4k is CLUT mirror.  Could store in last 4k of BM blocks.

V.CLUTBlk	    RMB	      1			  Block where high 4k mirrored CLUT data,0=Default CLUT
V.CLUT              RMB       1			  Which CLUTs are active 00001111

* TILE MAPS - 3 tile maps.  Registers are 12 bytes, 2 are reserved and
* 3 are the plysical address for the Tile Set.  Use Blk# for address here.
* So only need 8 bytes per tile map.  In the Map each tile is 2 bytes
* byte0=Tile number, byte1=CLUT+Tile Set. So relationship between Tile Map
* and Tile Set is set in the actual tile map data, not here.
* A tile map could be 2.4K (40x30) to 132K (256x256)

V.TM0	    	    RMB	     1	     	  	  Bit4 is Tile Size (1=8x8,0=16x16) Bit0 is enable
V.TM0Blk	    RMB	     1			  Starting Block# of Tile Map
V.TM0MapX	    RMB	     1			  Map Size X (max 255)
V.TM0MapY	    RMB	     1			  Map Size Y (max 255)
V.TM0ScrlX          RMB      2			  2 bytes for scroll X info
V.TM0ScrlY          RMB      2			  2 bytes for scroll Y info		    
V.TM1	    	    RMB	     1	     	  	  Bit4 is Tile Size (1=8x8,0=16x16) Bit0 is enable
V.TM1Blk	    RMB	     1			  Starting Block# of Tile Set
V.TM1MapX	    RMB	     1			  Map Size X (max 255)
V.TM1MapY	    RMB	     1			  Map Size Y (max 255)
V.TM1ScrlX          RMB      2			  2 bytes for scroll X info
V.TM1ScrlY          RMB      2			  2 bytes for scroll Y info
V.TM2	    	    RMB	     1	     	  	  Bit4 is Tile Size (1=8x8,0=16x16) Bit0 is enable
V.TM2Blk	    RMB	     1			  Starting Block# of Tile Set
V.TM2MapX	    RMB	     1			  Map Size X (max 255)
V.TM2MapY	    RMB	     1			  Map Size Y (max 255)
V.TM2ScrlX          RMB      2			  2 bytes for scroll X info
V.TM2ScrlY          RMB      2			  2 bytes for scroll Y info

* TILE SETS - there are 8 tile sets.  Tile Set registers contain a physical address, and
* a Square bit to determine if Tile Set is LINEAR or SQUARE
* Tile Sets are either 16K (8x8) or 64K (16x16)

V.TS0Blk	    RMB	     1 	    	   	  Starting Block# of Tile Set
V.TS0SQR	    RMB	     1			  Square or linear (bit 3)
V.TS1Blk	    RMB	     1 	    	   	  Starting Block# of Tile Set
V.TS1SQR	    RMB	     1			  Square or linear (bit 3)
V.TS2Blk	    RMB	     1 	    	   	  Starting Block# of Tile Set
V.TS2SQR	    RMB	     1			  Square or linear (bit 3)
V.TS3Blk	    RMB	     1 	    	   	  Starting Block# of Tile Set
V.TS3SQR	    RMB	     1			  Square or linear (bit 3)
V.TS4Blk	    RMB	     1 	    	   	  Starting Block# of Tile Set
V.TS4SQR	    RMB	     1			  Square or linear (bit 3)
V.TS5Blk	    RMB	     1 	    	   	  Starting Block# of Tile Set
V.TS5SQR	    RMB	     1			  Square or linear (bit 3)
V.TS6Blk	    RMB	     1 	    	   	  Starting Block# of Tile Set
V.TS6SQR	    RMB	     1			  Square or linear (bit 3)
V.TS7Blk	    RMB	     1 	    	   	  Starting Block# of Tile Set
V.TS7SQR	    RMB	     1			  Square or linear (bit 3)

* SCREEN TABLE - Global screen table
STblMax	            EQU	     5
STblBse		    EQU	     $1A80
		    ORG	     0
St.Sty		    RMB	     1			  Screen Type 0=txt;1=gfx


V.InBuf             RMB       KBufSz              the input buffer
                    RMB       250-.
V.Last              EQU       .

                    ENDC
