********************************************************************
* fstatus - show f256 registers
*
* $Id$
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------


                    nam       fstatus
                    ttl       show status of f256 registers

* Disassembled 98/09/11 12:07:32 by Disasm v1.6 (C) 1988 by RML

                    ifp1
                    use       defsfile
		    use       f256vtio.d
                    endc

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       3

MAPSLOT             equ       MMU_SLOT_1
MAPADDR             equ       (MAPSLOT-MMU_SLOT_0)*$2000

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
clutdata	    rmb	      100
MMUORIG		    rmb	      1
MMUEDIT		    rmb	      1
MMUACTIVE	    rmb	      1
PDATA		    rmb	      5

size                equ       .

name                fcs       /fstatus/
                    fcb       edition

Hdr                 fcs       "F256 Registers"
                    fcs       " --- ------ ------ ---- ------"
Ftr                 fcs       "                   ==== ======"
                    fcs       "            Total: "


start               leax      linebuf,u           get line buffer address
                    stx       <bufstrt            and store it away
                    stx       <bufcur             current output position output buffer

                    lbsr      wrbuf               print CR
                    leay      <Hdr,pcr
                    lbsr      tobuf               1st line of header to output buffer
                    lbsr      wrbuf               ..print it
                    lbsr      tobuf               2nd line of header to output buffer
                    lbsr      wrbuf               ..print it
		    
* Map in CLUT 0 and Bitmap bank
		    pshs      cc
		    orcc      #IntMasks           mask interrupts
		    lda	      MAPSLOT
		    pshs      a
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
		    lda	      #$C1
		    sta	      MAPSLOT
		    lda	      MMUACTIVE,u
		    sta	      MMU_MEM_CTRL
		    ldb	      #20
		    ldx	      #$2800
		    leay      clutdata,u
clutloop	    lda	      ,x+
		    sta	      ,y+
		    decb
		    bne	      clutloop
		    ldb	      #20
		    ldx	      #$2BF0
clutloop2	    lda	      ,x+
		    sta	      ,y+
		    decb
		    bne	      clutloop2
* Read in Bitmap registers
		    lda	      MMUEDIT,u
		    sta	      MMU_MEM_CTRL
	            lda       #$C0                Get the MMU Block for bitmap addresses
                    sta       MAPSLOT             store it in the MMU slot to map it in
		    lda	      MMUACTIVE,u
		    sta	      MMU_MEM_CTRL
*		    ldd	      #MAPADDR
*		    addd      #$1000
*		    tfr	      d,x
		    ldx	      #$3000
		    leay      bitmapinfo,u
		    ldd	      ,x++
		    std	      ,y++
		    ldd	      ,x++
		    std	      ,y++
		    ldx	      #$3008
		    ldd	      ,x++
		    std	      ,y++
		    ldd	      ,x++
		    std	      ,y++
		    ldx	      #$3010
		    ldd	      ,x++
		    std	      ,y++
		    ldd	      ,x++
		    std	      ,y++
		    lda	      MMUEDIT,u
		    sta	      MMU_MEM_CTRL
		    lda	      #$36
		    sta	      MAPSLOT
		    ldb	      #5
		    ldx	      #$37C0
		    leay      PDATA,u
PDLOOP		    lda	      ,x+
		    sta	      ,y+
		    decb
		    bne	      PDLOOP
		    puls      a
		    sta	      MAPSLOT
		    lda	      MMUORIG,u
		    sta	      MMU_MEM_CTRL
		    puls      cc
		    ldd	      #MAPADDR
		    lbsr      buf4hex
		    lbsr      wrbuf
		    ldb	      #0
		    leax      bitmapinfo,u
outloop		    leay      bitmap0txt,pcr	   Bitmap0 enable/disable
		    lbsr      tobuf
		    tfr	      b,a
		    lbsr      L0145
		    lda	      ,x
		    leay      disabletxt,pcr
		    anda      #$01
		    beq	      contbm0
		    leay      enabletxt,pcr
contbm0		    lbsr      tobuf
		    lbsr      wrbuf
		    leay      cluttxt,pcr
		    lbsr      tobuf
		    lda	      ,x
		    anda      #%00000110
		    lsra
		    lbsr      L0145
		    lbsr      wrbuf
		    leay      addresstxt,pcr
		    lbsr      tobuf
		    lda	      3,x
		    lbsr      L0145
		    lda	      2,x
		    lbsr      L0145
		    lda	      1,x
		    lbsr      L0145
		    lbsr      wrbuf
		    leax      $04,x
		    incb
		    cmpb      #3
		    bne	      outloop
		    leay      addrFFC0,pcr
		    lbsr      tobuf
		    lda	      $FFC0
		    lbsr      L0145
		    lbsr      wrbuf
		    leay      addrFFC1,pcr
		    lbsr      tobuf
		    lda	      $FFC1
		    lbsr      L0145
		    lbsr      wrbuf
		    leay      addrFFC2,pcr
		    lbsr      tobuf
		    lda	      $FFC2
		    lbsr      L0145
		    lbsr      wrbuf
		    leay      addrFFC3,pcr
		    lbsr      tobuf
		    lda	      $FFC3
		    lbsr      L0145
		    lbsr      wrbuf

*write out CLUT data
		    leay      cluttxt,pcr
		    lbsr      tobuf
		    lbsr      wrbuf
		    leax      clutdata,u
		    ldb	      #20
clutoutloop	    lda	      ,x+
		    lbsr      L0145
		    lda	      #C$SPAC
		    lbsr      bufchr
		    decb
		    bne	      clutoutloop
		    lbsr      wrbuf
		    ldb	      #20
clutoutloop2	    lda	      ,x+
		    lbsr      L0145
		    lda	      #C$SPAC
		    lbsr      bufchr
		    decb
		    bne	      clutoutloop2
		    lbsr      wrbuf
		    leax      PDATA,u
		    ldb	      #5
PDOUTLOOP	    lda	      ,x+
		    lbsr      L0145
		    decb
		    bne	      PDOUTLOOP

* All of the entries have been printed. Print the trailer and totals.
alldone             leay      >Ftr,pcr
                    lbsr       tobuf               1st line of footer to output buffer
                    lbsr       wrbuf               ..print it
                    lbsr       tobuf               2nd line of footer to output buffer
* Successful exit
                    clrb
                    os9       F$Exit

bitmap0txt	    fcs	      "Bitmap "
bitmap1txt	    fcs	      "Bitmap 1 ("
bitmap2txt	    fcs	      "Bitmap 2 ("
cluttxt	    	    fcs	      "CLUT: "
enabletxt	    fcs	      " (Enabled)"
disabletxt	    fcs	      " (Disabled)"
addresstxt	    fcs	      "Address: "
addrFFC0	    fcs	      "FFC0: "
addrFFC1	    fcs	      "FFC1: "
addrFFC2	    fcs	      "FFC2: "
addrFFC3	    fcs	      "FFC3: "

* convert value in D to ASCII hex (4 chars). Append to output buffer, then append "SPACE" to output buffer
buf4hex             pshs      b,a
                    clr       <leadzero
                    bsr       L0145
                    tfr       b,a
                    bsr       L0145
                    lda       #C$SPAC             append a space
                    bsr       bufchr
                    puls      pc,b,a

* convert value in u0006,7,8 to ASCII hex (6 chars). Append to output buffer, then append "SPACE" to output buffer
buf6hex             clr       <leadzero
                    lda       <u0006
                    bsr       L0145
                    lda       <u0007
                    bsr       L0145
                    lda       <u0008
                    bsr       L0145
                    lda       #C$SPAC             append a space
                    bra       bufchr

* convert value in A to ASCII hex (2 chars). Append to output buffer.
L0145               pshs      a
                    lsra
                    lsra
                    lsra
                    lsra
                    bsr       L014F
                    puls      a
L014F               anda      #$0F
                    tsta
                    beq       L0156
                    sta       <leadzero
L0156               tst       <leadzero
                    bne       L015C
                    lda       #$F0

* FALL THROUGH
* Convert digit to ASCII with leading spaces, add to output buffer
* A is a 0-9 or A-F or $F0.
* Add $30 converts 0-9 to ASCII "0" - "9"), $F0 to ASCII "SPACE"
* leaves A-F >$3A so a further 7 is added so $3A->$41 etc. (ASCII "A" - "F")
L015C               adda      #$30
                    cmpa      #$3A
                    bcs       bufchr
                    adda      #$07

* FALL THROUGH
* Store A at next position in output buffer.
bufchr              pshs      x
                    ldx       <bufcur
                    sta       ,x+
                    stx       <bufcur
                    puls      pc,x

* Append CR to the output buffer then print the output buffer
wrbuf               pshs      y,x,a
                    lda       #C$CR
                    bsr       bufchr
                    ldx       <bufstrt            address of data to write
                    stx       <bufcur             reset output buffer pointer, ready for next line.
                    ldy       #80                 maximum # of bytes - otherwise, stop at CR
                    lda       #$01                to STDOUT
                    os9       I$WritLn
                    puls      pc,y,x,a

* Append string at Y to output buffer. String is terminated by MSB=1
tobuf               lda       ,y
                    anda      #$7F
                    bsr       bufchr
                    tst       ,y+
                    bpl       tobuf
                    rts

DecTbl              fdb       10000,1000,100,10,1
                    fcb       $FF

* value in ?? is a number of blocks. Convert to bytes by multiplying by the page size.
* Convert to ASCII decimal, append to output buffer, append "k" to output buffer
L0199               pshs      y,x,b,a
                    lda       <ppblk
                    pshs      a
                    lda       $01,s
                    lsr       ,s
                    lsr       ,s
                    bra       L01A9

L01A7               lslb
                    rola
L01A9               lsr       ,s
                    bne       L01A7
                    leas      1,s
                    leax      <DecTbl,pcr
                    ldy       #$2F20
L01B6               leay      >256,y
                    subd      ,x
                    bcc       L01B6
                    addd      ,x++
                    pshs      b,a
                    tfr       y,d
                    tst       ,x
                    bmi       L01DE
                    ldy       #$2F30
                    cmpd      #'0*256+C$SPAC
                    bne       L01D8
                    ldy       #$2F20
                    lda       #C$SPAC
L01D8               bsr       bufchr
                    puls      b,a
                    bra       L01B6

L01DE               bsr       bufchr
                    lda       #'k
                    bsr       bufchr
                    leas      $02,s
                    puls      pc,y,x,b,a

                    emod
eom                 equ       *
                    end
