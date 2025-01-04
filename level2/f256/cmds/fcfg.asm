********************************************************************
* fcfg
* foenix configuration editor
*
* by John Federico
*
* Edt/Rev  2024/11/30  Modified by John Federico
* Comment
* ------------------------------------------------------------------
               nam       fcfg
               ttl       fcfg

               ifp1
               use       defsfile
               endc

tylg           set       Prgrm+Objct
atrv           set       ReEnt+rev
rev            set       $00
edition        set       1

               mod       eom,name,tylg,atrv,start,size

*        [Data Section - Variables and Data Structures Here]
solpath	       rmb       1
sstat	       rmb       1
oldbg	       rmb       1
oldfg	       rmb	 1
newfg	       rmb	 1
newbg	       rmb	 1
listbox	       equ       0
fgctrl	       equ	 1
bgctrl	       equ	 2
picctrl	       equ	 3
thmectrl       equ	 4
clutctrl       equ	 5
fntszhctrl     equ	 6
fntszvctrl     equ	 7
applyctrl      equ	 8
cancelctrl     equ	 9
listlen	       equ     	 8	       	        max length of listbox
dirpath	       rmb       1
dent	       rmb	 DIR.SZ			DIR.SZ defined in rbf.d as 29+3=32
drawchar       rmb	 1
bufstrt        rmb       2
bufcur         rmb       2
dbufcur	       rmb	 2
dbufcntH       rmb	 1
dbufcntL       rmb	 1
numfonts       rmb	 1			total number of font names loaded
listitem       rmb	 1			current item selected
liststart      rmb	 1			index for top of list
liststartmax   rmb	 1
listmax	       rmb	 1			max # of items displayed
ctrlselect     rmb	 1			store which control has focus
linebuf        rmb       80
popts	       rmb	 32
oldchars       rmb	 96
fntarray       rmb	 1550	                array of fonts, max 50 of 29+2 len each
drawbuf	       rmb	 256
	       rmb	 250
size           equ       .
name           fcs       /fcfg/
               fcb       edition

fontdir	       fcc 	 "/dd/sys/fonts"
	       fcb	 $0D
	       

start

*        [Program Section - Program Code Here]
	       clr       sstat,u
	       lda	 #0
	       ldb	 #SS.FBRgs
	       os9	 I$GetStt
	       pshs	 a
	       anda	 #$0F
	       sta	 <oldbg
	       sta	 <newbg
	       puls	 a
	       lsra
	       lsra
	       lsra
	       lsra
	       sta	 <oldfg
	       sta	 <newfg
	       clr	 numfonts
	       clr 	 listitem
	       clr	 liststart
	       clr	 ctrlselect
	       clr	 numfonts
	       lbsr	 installchars
	       lbsr	 getopts
	       lbsr	 keyechooff
               leax      linebuf,u           get line buffer address
               stx       <bufstrt            and store it away
               stx       <bufcur             current output position output buffer
	       leay	 header,pcr	     write out header
	       lbsr	 tobuf
	       lbsr	 wrbuf
	       andcc	 #$FE
	       bcs	 error@
	       leay      sigdone,pcr
	       lbsr	 tobuf
	       lbsr	 wrbuf
	       lbsr	 ldfontarr	     load font array with filenames from fontdir
	       leay	 lddone,pcr	     write out header
	       lbsr	 tobuf
	       lbsr	 wrbuf
*	       lbsr	 writearr	     TEST:write array
	       lbsr	 cursoroff
	       lbsr	 clearscreen
	       lbsr	 drawscreen
	       lbsr      writefgc
	       lbsr	 drawfg
	       lbsr	 writebgc
	       lbsr	 drawbg
	       lbsr	 writelist
	       lbsr	 wrtlabels
	       lbsr      printfont
	       lbsr	 InstallSignals
keyloop@       lbsr	 handlekeyboard
	       cmpa	 #113
	       beq	 exit@
	       cmpa 	 #$0D
	       beq	 setfont
	       cmpa	 #$75
	       beq	 update@
	       bra	 keyloop@
update@	       lbsr	 printfont
	       bra	 keyloop@
setfont	       lbsr	 RemoveSignals
	       lbsr	 changesettings
	       bcs	 error@
	       bra	 exit2@
exit@	       lbsr	 RemoveSignals
exit2@	       lbsr	 movecursor
	       lbsr	 keyechoon
*	       lbsr	 clearscreen
	       lbsr	 cursoron
	       clrb
error@	       ldy	 #2
	       lda	 #1
	       leax	 font0on,pcr
	       os9	 I$Write
	       os9       F$Exit


writeoldchars  ldb 	 #0
loop@	       leay	 oldchars,u
	       lda	 b,y
	       lbsr	 bufval
	       incb
	       cmpb	#8
	       bne	loop@
	       lbsr 	wrbuf
	       rts

 
handlekeyboard      lbsr      INKEY
                    cmpa      #$0C
                    beq       uparrow
                    cmpa      #$0A
                    beq       downarrow
		    cmpa      #$66
		    lbeq      movefg
		    cmpa      #$46
		    lbeq      backfg
		    cmpa      #$62
		    lbeq      movebg
		    cmpa      #$42
		    lbeq      backbg
                    rts

uparrow	       lda       <liststart
	       beq	 cont1@		   if liststart is 0, then don't need to do anything
	       cmpa	 <listitem	   
	       bne	 cont1@		   if list item is not at the start of the list don't move list
	       dec	 <liststart
cont1@	       lda	 <listitem
	       beq	 cont2@
	       dec	 <listitem
cont2@	       lbsr	 writelist
	       clra
	       rts


downarrow      lda	<liststart
	       cmpa	<liststartmax      if liststart is liststart max, don't adjust list
	       beq	cont1@
	       adda	#7
	       cmpa	<listitem
	       bne	cont1@
	       inc	<liststart
cont1@	       lda	<listitem
	       inca	
	       cmpa	<numfonts
	       bge	cont2@
	       inc	<listitem
cont2@	       lbsr	writelist
	       clra
	       rts

getopts        leax     >popts,u
               ldb      #SS.Opt
               clra
               os9      I$GetStt
               rts

keyechooff     leax     >popts,u
               clr      4,x
               clra
               ldb      #SS.Opt
               os9      I$SetStt
               rts

keyechoon      leax     >popts,u
               lda      #1
               sta      4,x
               clra
               ldb      #SS.Opt
               os9      I$SetStt
               rts

changesettings leay	drawbuf,u
	       leax	fontdir,pcr		load fontdir path
	       ldb	#13
fdirloop@      lda	,x+
	       sta	,y+
	       decb
	       bne	fdirloop@
	       lda	#$2F	                add extra slash
	       sta	,y+			
	       lda	<listitem		Get the list item
	       lbsr	arrayidx		Get the index
	       leax	1,x
	       ldb	,x+
fnameloop@     lda	,x+
	       sta	,y+
	       decb
	       bne	fnameloop@
	       lda	#$0D
	       sta	,y
	       lda	#0
	       leax	drawbuf,u
	       ldy	#40
	       os9	I$Write
	       leax	drawbuf,u
	       ldb      #SS.FntLoadF
	       lda	#0
	       os9	I$SetStt
	       bcs	error@
	       leax	drawbuf,u
	       ldy	#$1B32
	       sty	,x++
	       ldb	<newfg
	       stb	,x+
	       ldy	#$1B33
	       sty 	,x++
	       ldb	<newbg
	       stb	,x
	       leax	drawbuf,u
	       lda	#0
	       ldy	#6
	       os9	I$Write
error@	       rts


* load font arrary
ldfontarr
	       lbsr	 clrarray
	       bsr	 opendir
	       bsr	 seekdir
loop@	       bsr	 readdir
	       bcs	 exit@
	       leay	 dent,u
	       lda	 <numfonts
	       lbsr	 toarr
	       inc	 <numfonts
	       bra	 loop@
exit@	       cmpb	 #211
	       bne	 error@
	       clrb
error@	       pshs	 b 
	       ldb	 <numfonts
	       decb	 #listlen
	       lda	 #listlen
	       cmpa	 <numfonts
	       blt	 setlistlen@
	       lda	 <numfonts
	       clrb
setlistlen@    sta	 <listmax
	       stb	 <liststartmax
	       puls	 b
	       lda	 <dirpath
	       os9	 I$Close
	       rts

opendir	       lda	 #DIR.+READ.	   directory is just a file on the disk
	       leax	 fontdir,pcr
	       pshs	 x,a
	       os9	 I$Open
	       sta	 <dirpath
	       puls	 x,a
	       os9	 I$ChgDir
	       rts

seekdir	       lda       <dirpath
               ldx       #$0000
               pshs      u
               ldu       #DIR.SZ*2	   skip the first two entries
               os9       I$Seek		   which are . and ..	
               puls      u
	       rts

readdir	       ldy	 #DIR.SZ	   each dir entry is 32 bytes, filename is first 29
	       lda	 <dirpath          name is terminated with high bit set
	       leax	 dent,u
	       os9	 I$Read
	       rts


drawscreen     lda	#$F9		    DC
	       sta	<drawchar
	       ldb	#$23		    This is setting carry bit somehow.
	       ldx	#31
	       lda	#$24
	       lbsr	drawHL

	       lda	#$FA			df
	       sta	<drawchar
	       ldb	#$2C
	       ldx	#31
	       lda	#$24
	       lbsr	drawHL


	       lda	#$F7			DD
	       sta	<drawchar
	       ldb	#$24
	       ldx	#8
	       lda	#$24
	       lbsr	drawVL
	       
	       lda	#$F8			DE
	       sta	<drawchar
	       ldb	#$24
	       ldx	#8
	       lda	#$42
	       lbsr	drawVL

	       lda	#$F3
	       sta	<drawchar
	       ldb	#$23
	       ldx	#1
	       lda	#$24
	       lbsr	drawHL

	       lda	#$F4
	       sta	<drawchar
	       ldb	#$23
	       ldx	#1
	       lda	#$42
	       lbsr	drawHL

	       lda	#$F5
	       sta	<drawchar
	       ldb	#$2C
	       ldx	#1
	       lda	#$24
	       lbsr	drawHL

	       lda	#$F6
	       sta	<drawchar
	       ldb	#$2C
	       ldx	#1
	       lda	#$42
	       lbsr	drawHL
	       
	       rts
	       
clearscreen    lda	#$0C
	       leax	drawbuf,u
	       sta	,x
	       ldy	#1
	       lda	#1
	       os9	I$Write
	       rts

movecursor     leay	drawbuf,u
	       lda	#$02
	       sta	,y+
	       lda	#$30
	       sta	,y+
	       lda	#$34
	       sta	,y+
	       lda	#$01
	       leax	drawbuf,u
	       ldy	#$03
	       os9	I$Write
	       rts


cursoroff      leax	drawbuf,u
	       ldy	#$0520
	       sty	,x
	       ldy	#2
	       lda	#$01
	       os9	I$Write
	       rts

cursoron       leax	drawbuf,u
	       ldy	#$0521
	       sty	,x
	       ldy	#2
	       lda	#$01
	       os9	I$Write
	       rts

* write max 8 items from the array into the list
writelist      leas	-4,s		add to stack to store x,y coordinates
	       lda	#$02
	       sta	,s	        Cursor XY Command
	       lda	#$25
	       sta	1,s		x coordinate
	       lda	#$24
	       sta	2,s	        y coordinate
	       clr	3,s	        list counter
	       lda	<liststart		initialize array
loop@	       pshs	a
	       cmpa	<listitem
	       bne	norev@
	       bsr	writerevon
norev@	       lda	#1
	       leax	1,s
	       ldy	#3
	       os9	I$Write
	       puls	a
	       lbsr	arrayidx
	       ldy	#29
	       leax	2,x
	       pshs     a
	       lda	#1
	       os9	I$Write
	       puls     a
	       cmpa	<listitem
	       bne	norev2@
	       bsr	writerevoff
norev2@	       inc	2,s
	       inc	3,s
	       inca
	       ldb	3,s
	       cmpb	<listmax
	       bne	loop@
	       leas	4,s
	       rts

writerevon     pshs	a
	       lda	#1
	       leax	revvidon,pcr
	       ldy	#2
	       os9	I$Write
	       puls	a,pc

writerevoff    pshs	a
	       lda	#1
	       leax	revvidoff,pcr
	       ldy	#2
	       os9	I$Write
	       puls	a,pc
	       rts

writefgc       leax	drawbuf,u
	       lda	#$02
	       sta	,x+
	       lda	#$4A		x=40
	       sta	,x+
	       lda	#$25		y=5
	       sta	,x+
	       lda	#01
	       leax	drawbuf,u
	       ldy	#3
	       os9	I$Write
	       ldb	#0
fgloop@	       leax	drawbuf,u
	       ldy	#$1B32
	       sty	,x++
	       stb	,x+
	       lda	#$FB
	       sta	,x+
	       lda	#$20
	       sta	,x+
	       lda	#0
	       leax	drawbuf,u
	       ldy	#5
	       os9	I$Write
	       incb
	       cmpb	#$10
	       bne	fgloop@
	       leax	drawbuf,u
	       ldy	#$1B32
	       sty	,x
	       lda	<oldfg
	       sta	2,x
	       ldy	#3
	       lda	#0
	       os9	I$Write
	       rts

movefg	       inc	<newfg
	       lda	<newfg
	       cmpa	#$10
	       bne	drawfg
	       clr	<newfg
	       bra	drawfg
backfg	       dec	<newfg
	       lda	<newfg
	       cmpa	#$FF
	       bne	drawfg
	       lda	#$0F
	       sta	<newfg
drawfg	       leax	drawbuf,u
	       lda	#$02
	       sta	,x+
	       ldy	#$4A24
	       sty	,x++
	       ldb	#$0
loop@	       cmpb     <newfg
	       bne	space@
	       ldy	#$2B20
	       bra	store@
space@	       ldy	#$2020
store@	       sty	,x++
	       incb
	       cmpb	#$10
	       bne	loop@
	       lda	#0
	       leax	drawbuf,u
	       ldy	#35
	       os9	I$Write
	       clra
	       rts
	       

writebgc       ldb	<oldbg
	       pshs	b
	       leax	drawbuf,u
	       lda	#$02
	       sta	,x+
	       lda	#$4A		x=40
	       sta	,x+
	       lda	#$2A		y=5
	       sta	,x+
	       lda	#01
	       leax	drawbuf,u
	       ldy	#3
	       os9	I$Write
	       ldb	#0
bgloop@	       leax	drawbuf,u
	       ldy	#$1B33
	       sty	,x++
	       stb	,x+
	       lda	#$20
	       sta	,x+
	       sty	,x++
	       lda	,s
	       sta	,x+
	       lda	#$20
	       sta	,x+
	       lda	#0
	       leax	drawbuf,u
	       ldy	#8
	       os9	I$Write
	       incb
	       cmpb	#$10
	       bne	bgloop@
	       leas	1,s
	       clra
	       rts
	       
movebg	       inc	<newbg
	       lda	<newbg
	       cmpa	#$10
	       bne	drawbg
	       clr	<newbg
	       bra	drawbg
backbg	       dec	<newbg
	       lda	<newbg
	       cmpa	#$FF
	       bne	drawbg
	       lda      #$0F
	       sta	<newbg
drawbg	       leax	drawbuf,u
	       lda	#$02
	       sta	,x+
	       ldy	#$4A29
	       sty	,x++
	       ldb	#$0
loop@	       cmpb     <newbg
	       bne	space@
	       ldy	#$2B20
	       bra	store@
space@	       ldy	#$2020
store@	       sty	,x++
	       incb
	       cmpb	#$10
	       bne	loop@
	       lda	#0
	       leax	drawbuf,u
	       ldy	#35
	       os9	I$Write
	       rts


wrtlabels      leax	flabel,pcr
	       ldy	#20
	       lda	#0
	       os9	I$Write
	       

* convert value in A to ASCII hex (2 chars). Append to output buffer.
bufval              pshs      a                   preserve original value
                    lsra                          shift 4 bits
                    lsra                          to get high 4 bits
                    lsra
                    lsra
                    bsr       L014F               do high 4 bits then rts and do low 4
                    puls      a                   pull original value for low 4 bits
L014F               anda      #$0F                mask high bit and process low 4 bits

* FALL THROUGH
* Convert digit to ASCII with leading spaces, add to output buffer
* A is a 0-9 or A-F or $F0.
* Add $30 converts 0-9 to ASCII "0" - "9"), $F0 to ASCII "SPACE"
* leaves A-F >$3A so a further 7 is added so $3A->$41 etc. (ASCII "A" - "F")
L015C               adda      #$30
                    cmpa      #$3A
                    bcs       bufchr
                    adda      #$07

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

* write out linebuffer with length of y
wrbuflen	    pshs      y,x,a
		    lda	      #$01
		    ldx	      <bufstrt
		    stx	      <bufcur
		    os9	      I$Write
		    puls      pc,y,x,a

* Append string at Y to output buffer. String is terminated by MSB=1
tobuf               pshs      a
bufloop             lda       ,y
                    anda      #$7F
                    bsr       bufchr
                    tst       ,y+
                    bpl       bufloop
                    puls      a
                    rts

clrarray	    pshs      u,x,y
		    leax      fntarray,u
		    ldu	      #$2020
		    ldy	      #1550
loop@		    stu	      ,x++
		    leay      -2,y
		    bne	      loop@
		    puls      u,x,y,pc

* Puts string at y into font arrray at index a
* store string length in first two byts of array item
toarr               pshs      a,x
                    bsr       arrayidx             put array index a addr in x
		    pshs      x			   store start address on stack
		    leas      -2,s		   add stack space for string count
		    clr	      ,s		   clear it to 0
		    clr	      1,s
		    leax      2,x		   reserve place in array string for length
arrloop@            lda       ,y		   load char from string
		    anda      #$7F		   strip terminating high bit, if there
                    sta       ,x+		   put into array
		    inc	      1,s		   increment string count
                    tst       ,y+                  test for the high bit, but don't overwrite
                    bpl       arrloop@             need the high bit on output
		    puls      x,y		   pull length and string start
		    stx	      ,y		   store string length in two byte of array item
                    puls      a,x,pc

* calc array item address in x from index a
* multiply 29*index (0-49) to get offset using math co-processor
* destroys x
arrayidx            pshs      d,cc
		    orcc      #IntMasks            mask interrups to avoid copro collisions
                    sta       $FEE0		   low bit in math copro
                    clr       $FEE1		   high bit in math copro
                    lda       #31		   multiple by 29, len of row
                    sta       $FEE2		   low bit in math copro
                    clr       $FEE3		   high bit in math copro
                    ldb       $FEF0		   load answer low bit into b
                    lda       $FEF1		   load answer high bit into a
                    leax      fntarray,u	   load address of array
                    leax      d,x		   add offset
                    puls      d,cc,pc		   return

* TEST routine to check array contents
writearr	    lda	      #0	           initiate loop index counter
loop@		    bsr	      arrayidx		   get addr of item		   
		    ldy	      ,x++		   get length, and advance memory
		    pshs      a			   store a to use a for I$Write
		    lda	      #1
		    os9	      I$Write
		    puls      a			   retrieve a loop index counter
		    inca      			   increment counter
		    cmpa      <numfonts		   are we done?
		    blt	      loop@		   no - then loop
		    rts


*draw horizontal line with drawchar, a=x1, b=y1, x=length
drawHL		    pshs      d,x,y
		    clr	      <dbufcntH
		    clr	      <dbufcntL
		    leay      drawbuf,u
		    lda	      #$02
		    sta	      ,y+
		    inc	      <dbufcntL
		    lda       ,s
		    sta	      ,y+
		    inc	      <dbufcntL
		    stb	      ,y+
		    inc	      <dbufcntL
		    lda	      <drawchar
loop@		    sta	      ,y+
		    inc	      <dbufcntL
		    leax      -1,x
		    bne	      loop@
		    lda	      #$01
		    leax      drawbuf,u
		    ldy	      <dbufcntH
		    os9	      I$Write
		    puls      pc,d,x,y


* draw vertical line with drawchar, a=x1, b=y1, x=length
drawVL		    pshs      d,x,y
		    clr	      <dbufcntH
		    clr	      <dbufcntL
		    leay      drawbuf,u
loop@		    lda	      #$02
		    sta	      ,y+
		    inc	      <dbufcntL
		    lda       ,s
		    sta	      ,y+
		    inc	      <dbufcntL
		    stb	      ,y+
		    inc	      <dbufcntL
		    lda	      <drawchar
		    sta	      ,y+
		    inc	      <dbufcntL
		    incb
		    leax      -1,x
		    bne	      loop@
		    lda	      #$01
		    leax      drawbuf,u
		    ldy	      <dbufcntH
		    os9	      I$Write
		    puls      pc,d,x,y

installchars	    ldb	      #12
		    pshs      b
		    leax      oldchars,u
		    ldy	      #243
loop@		    lda	      #0
		    ldb	      #SS.FntChar
		    os9       I$GetStt
		    bcs	      exit@
		    leax      8,x
		    leay      1,y
		    dec	      ,s
		    bne	      loop@
		    ldb	      #12
		    stb	      ,s
		    leax      ccorner1,pcr
		    ldy	      #243
loop2@		    lda	      #0
		    ldb	      #SS.FntChar
		    os9	      I$SetStt
		    bcs	      exit@
		    leax      8,x
		    leay      1,y
		    dec	      ,s
		    bne       loop2@
exit@		    puls      b,pc


restorchars	    ldb	      #12
		    stb	      ,s
		    leax      oldchars,u
		    ldy	      #243
loop@		    lda	      #0
		    ldb	      #SS.FntChar
		    os9	      I$SetStt
		    bcs	      exit@
		    leax      8,x
		    leay      1,y
		    dec	      ,s
		    bne       loop@
exit@		    puls      b,pc		    
		    

INKEY               clra                          std in
                    ldb       #SS.Ready
                    os9       I$GetStt            see if key ready
                    bcc       getit
                    cmpb      #E$NotRdy           no keys ready=no error
                    bne       exit@               other error, report it
                    clra                          no error
                    bra       exit@
getit               lbsr      FGETC               go get the key
                    tsta
exit@               rts

FGETC               pshs      a,x,y
                    ldy       #1                  number of char to print
                    tfr       s,x                 point x at 1 char buffer
                    os9       I$Read
                    puls      a,x,y,pc

printfont	    leax      frow1,pcr
		    ldy	      #3
		    lda	      #1
		    os9	      I$Write
		    ldb	      #0
		    leax      drawbuf,u
		    lda	      sstat,u	          DEBUG
		    beq	      good@		  DEBUG
		    lda	      #$58		  DEBUG
		    bra       loop1@		  DEBUG
good@		    lda	      #$30		  DEBUG  
*		    lda       #32		  DEBUG  
loop1@		    sta	      ,x+
		    lda	      #32
		    incb
		    cmpb      #32
		    bne	      loop1@
loop2@		    stb	      ,x+
		    incb
		    cmpb      #64
		    bne	      loop2@
		    ldy	      #64
		    leax      drawbuf,u
		    lda	      #1
		    os9	      I$Write
		    leax      frow2,pcr
		    ldy	      #3
		    os9	      I$Write
		    ldb	      #64
		    leax      drawbuf,u
loop3@		    stb	      ,x+
		    incb
		    cmpb      #128
		    bne	      loop3@
		    ldy	      #64
		    leax      drawbuf,u
		    lda	      #1
		    os9	      I$Write
		    leax      frow3,pcr
		    ldy	      #3
		    os9	      I$Write
		    ldb	      #128
		    leax      drawbuf,u
loop4@		    stb	      ,x+
		    incb
		    cmpb      #192
		    bne	      loop4@
		    ldy	      #64
		    leax      drawbuf,u
		    lda	      #1
		    os9	      I$Write
		    leax      frow4,pcr
		    ldy	      #3
		    os9	      I$Write
		    ldb	      #192
		    leax      drawbuf,u
loop5@		    stb	      ,x+
		    incb
		    cmpb      #0
		    bne	      loop5@
		    leax      drawbuf,u
		    ldy	      #64
		    lda	      #1
		    os9	      I$Write
		    rts

InstallSignals	    leax      cfIcptRtn,pcr
		    os9	      F$Icpt
		    lda	      #UPDAT.+SHARE.
		    leax      fsol,pcr
		    os9	      I$Open
		    bcc	      storesol@
		    os9	      F$PErr
		    tfr	      a,b
		    os9	      F$PErr
storesol@	    sta	      <solpath
		    lda	      <solpath
		    ldx	      #260
		    ldy	      #$A0
		    ldb	      #SS.SOLIRQ
		    os9	      I$SetStt
		    os9	      F$PErr
		    lda	      <solpath
		    ldx	      #400
		    ldy	      #$A1
		    ldb	      #SS.SOLIRQ
		    os9	      I$SetStt
		    rts

fsol		    fcc	      \/fSOL\
		    fcb	      $0D

cfIcptRtn	    cmpb      #$A0
		    beq	      changefont1@
		    cmpb      #$A1
		    beq	      changefont0@
		    bra	      exit@
changefont1@	    lda	      #$0
		    ldb	      #SS.DScrn
		    os9	      I$GetStt	         DEBUG
		    tfr	      y,d
		    orb       #FT_FSET
		    tfr	      d,y
		    bra	      writeit@
changefont0@	    lda	      #$0
		    ldb	      #SS.DScrn
		    os9	      I$GetStt	         DEBUG
		    tfr	      y,d
		    andb      #~(FT_FSET)
		    tfr	      d,y
writeit@	    lda	      #1
		    ldb	      #SS.DScrn
		    os9	      I$SetStt           DEBUG
exit@               rti

RemoveSignals	    lda	      <solpath
		    ldx	      #260
		    ldy	      #0
		    ldb	      #SS.SOLIRQ
		    os9	      I$SetStt
		    lda	      <solpath
		    ldx	      #400
		    ldy	      #0
		    ldb	      #SS.SOLIRQ
		    os9	      I$SetStt
		    lda	      <solpath
		    os9	      I$Close
		    rts
		    
header		    fcs	      /Configure A/
writing		    fcs	      /Loading/
lddone		    fcs	      /Load Done/
sigdone		    fcs	      /Load Signal/
icptdone	    fcs	      /ICPT Done/
font0on		    fcb	      $1B,$62
flabel		    fcb	      $02,$58,$27
	            fcb	      $46,$2F,$66
blabel		    fcb	      $02,$58,$2C		    
		    fcb	      $42,$2F,$62
arrowlabel	    fcb	      $02,$22,$26,$FC
		    fcb	      $02,$22,$28,$FD
revvidon	    fcb	      $1F,$20
revvidoff	    fcb	      $1F,$21
frow1		    fcb	      $02,$28,$34
frow2		    fcb	      $02,$28,$35
frow3		    fcb	      $02,$28,$36
frow4		    fcb	      $02,$28,$37
* Custom font characters for box
ccorner1	    fcb       $0F,$1F,$3F,$7C,$F8,$F1,$E3,$E6	   *243  F3
ccorner2	    fcb	      $F0,$F8,$FC,$3E,$1F,$8F,$C7,$67	   *244  F4
ccorner3	    fcb	      $E6,$E3,$F1,$F8,$7C,$3F,$1F,$0F	   *245  F5
ccorner4	    fcb	      $67,$C7,$8F,$1F,$3E,$FC,$F8,$F0	   *246  F6
cleftside	    fcb	      $E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6	   *247  F7
crightside	    fcb	      $67,$67,$67,$67,$67,$67,$67,$67	   *248  F8
ctop		    fcb	      $FF,$FF,$FF,$00,$00,$FF,$FF,$00	   *249  F9
cbottom		    fcb	      $00,$FF,$FF,$00,$00,$FF,$FF,$FF	   *250  FA
cblock		    fcb	      $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF	   *251  FB
cuparrow	    fcb	      $10,$38,$54,$92,$10,$10,$10,$10	   *252  FC
cdownarrow	    fcb	      $10,$10,$10,$10,$92,$54,$38,$10	   *253  FD
ccaret		    fcb	      $00,$00,$00,$00,$81,$42,$24,$18	   *254  FE


		    
                    emod
eom            	    equ *
               	    end