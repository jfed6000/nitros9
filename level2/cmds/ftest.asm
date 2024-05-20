********************************************************************
* ftest - basic graphics test
*
* $Id$
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------


                    nam       ftest
                    ttl       basic f256 graphics test

* Disassembled 98/09/11 12:07:32 by Disasm v1.6 (C) 1988 by RML

                    ifp1
                    use       defsfile
                    endc

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       3

MAPSLOT             equ       MMU_SLOT_1
MAPSLOT2            equ       MMU_SLOT_2
MAPADDR             equ       (MAPSLOT-MMU_SLOT_0)*$2000
MAPADDR2            equ       (MAPSLOT2-MMU_SLOT_0)*$2000

                    mod       eom,name,tylg,atrv,start,size

freeblks            rmb       2
mapsiz              rmb       2
* pages per block (ie, MS byte of block size)
ppblk               rmb       1
* 0: print number with leading spaces. 1: print number with leading 0.
leadzero            rmb       1
* u0006,7,8 store a 24-bit block begin/end address.
u0006               rmb       1
u0007               rmb       1
u0008               rmb       1
bufstrt             rmb       2
bufcur              rmb       2
linebuf             rmb       80
bitmapinfo	    rmb	      12
MMUORIG		    rmb	      1
MMUEDIT		    rmb	      1
MMUACTIVE	    rmb	      1

size                equ       .

name                fcs       /ftest/
                    fcb       edition

Hdr                 fcs       "F256 Registers"
                    fcs       " --- ------ ------ ---- ------"
Ftr                 fcs       "                   ==== ======"
                    fcs       "            Total: "


*  Set up Bitmap at address 06C000 = 
start               pshs      cc
		    orcc      #IntMasks           mask interrupts
		    lda	      MMU_MEM_CTRL
		    sta	      MMUORIG,U
		    anda      #%00000011
		    sta	      MMUACTIVE
		    lsla
		    lsla
		    lsla
		    lsla
		    anda      #%00110000
		    adda      MMUORIG,U
		    sta	      MMUEDIT,U
		    sta	      MMU_MEM_CTRL		    
		    lda	      MAPSLOT
		    pshs      a
	            lda       #$C0                Get the MMU Block for bitmap addresses
                    sta       MAPSLOT             store it in the MMU slot to map it in
		    lda	      MMUACTIVE,u
		    sta	      MMU_MEM_CTRL
		    ldd	      #MAPADDR
		    addd      #$1000
		    tfr	      d,x
		    lda	      #$01
		    sta	      ,x+
		    lda	      #$00
		    sta	      ,x+
		    lda	      #$C0
		    sta	      ,x+
		    lda	      #$06
		    sta	      ,x
		    lda	      #$00
		    sta	      $3008
		    sta	      $3009
		    sta	      $300A
		    sta	      $300B
		    lda	      #$0
		    sta	      $3010
		    sta	      $3011
		    sta	      $3012
		    sta	      $3013
		    lda	      MMUEDIT,u
		    sta	      MMU_MEM_CTRL
		    puls      a
		    sta	      MAPSLOT
		    lda	      MMUORIG,u
		    sta	      MMU_MEM_CTRL
		    puls      cc
		    lbsr      Default_CLUT
		    lbsr      StartGrfDisplay
		    lbsr      createpixels
                    clrb
                    os9       F$Exit

createpixels	    pshs      cc
		    orcc      #IntMasks           mask interrupts
		    lda	      MAPSLOT
		    pshs      a
		    lda	      MMUEDIT,u
		    sta	      MMU_MEM_CTRL
	            lda       #$36               Get the MMU Block for bitmap addresses
                    sta       MAPSLOT
		    lda	      MMUACTIVE,u
		    sta	      MMU_MEM_CTRL
		    ldx	      #$37C0
		    ldb	      #$FF
pixeloop	    stb	      ,x+
		    decb
		    bne	      pixeloop
		    lda	      MMUEDIT,u
		    sta	      MMU_MEM_CTRL
		    puls      a
		    sta	      MAPSLOT
		    lda	      MMUORIG,u
		    sta	      MMU_MEM_CTRL
		    puls      cc
		    rts
		    


StartGrfDisplay	    pshs      a,b,x                  save it on the stack
		    lda	      #1
*		    sta	      V.ST,u		  0=Term, 1=Gfx
*                    lda       #Mstr_Ctrl_Graph_Mode_En
		    lda	      #12
		    clrb
        	    sta       $FFC0
		    stb	      $FFC1
		    lda	      #$40
		    sta	      $FFC2
		    lda	      #$01
		    sta	      $FFC3
		    puls      b,a,x
		    rts


Default_CLUT	    pshs      cc,a,b,x,y
		    orcc      #IntMasks           mask interrupts
		    lda	      MAPSLOT
		    pshs      a
		    lda	      MMUEDIT,u
		    sta	      MMU_MEM_CTRL		    
	            lda       #$C1                Get the MMU Block for CLUT control
                    sta       MAPSLOT             Map into MMU_SLOT_1=$2000-$3FFF
		    lda	      MMUACTIVE,u
		    sta	      MMU_MEM_CTRL
*                   ** Loop to write rrrgggbb values to CLUT
*                   ** b goes from 0-255, then wrap around to 0
	            ldx	      #$2800              CLUT#0 is Blk $C1 at $800+$2000 for Map
	            ldb	      #0		  starting color byte
loop@               bsr	      write_bgra
	            incb
	            bne	      loop@
		    lda	      MMUEDIT,u
		    sta	      MMU_MEM_CTRL		    
		    puls      a
		    sta	      MAPSLOT
		    lda	      MMUORIG,u
		    sta	      MMU_MEM_CTRL
	            puls      y,x,b,a,cc,pc          pull registers and return
*                   ** Default_Clut END	

write_bgra          pshs      b			  push rrrgggbb value
	            pshs      b			  push red (red is high 3 bits)
	            aslb      			  shift to high 3 bits green
	            aslb      
	            aslb      
	            tfr       b,a                 copy green to a
	            asla                   	  shift to high 3 bits blue
	            asla      
	            asla      
	            anda      #%11100000           blue - mask low 5 bits
	            andb      #%11100000           green - mask low 5 bits
	            std       ,x++		  write blue,green : inc x to r,a
	            puls      a                   pull red into a
	            anda      #%11100000            red - mask low 5 bits
	            clrb                          alpha is unused, just make zero
	            std	      ,x++                write red,alpha
	            puls      b,pc                pull rrrgggbb and return
*		    ** write_bgra END	        


                    emod
eom                 equ       *
                    end
