
********************************************************************
* SOLdrv
* Foenix Start of Line Driver
*
* by John Federico
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*  1       2025/01/02  John Federico
*  Initial version
*

		    nam       SOLdrv
               	    ttl       Foenix Start of Line Driver

               	    ifp1
               	    use       defsfile
               	    endc

tylg		    set       Drivr+Objct
atrv          	    set       ReEnt+rev
rev           	    set       $00
edition        	    set       1

               	    mod       eom,name,tylg,atrv,start,size

		    org       V.SCF
* Start of Line Interrupt Handling
V.SOLOnOff          RMB	      1
V.SOLCurr  	    RMB	      1
V.SOLMax   	    RMB	      1
V.SOLTable 	    RMB	      32
		    RMB       128

size           	    equ       .
                    fcb       UPDAT.+SHARE.
name           	    fcs       /SOLdrv/
               	    fcb       edition

start               lbra      Init       |SCF jump table
                    lbra      Read       |
                    lbra      Write      |
                    lbra      GetSta     |
                    lbra      SetSta     |start
		    lbra      Term

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
* Initialize driver to off.  We don't need to set up an SOL or IRQ
* until a user requests to set up one.
Init	            clr	      V.SOLOnOff,u	 Initialize Driver to Off
		    clrb
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
* Nothing to read, just return
Read	     	    clra
		    ldb	  #E$EOF
		    rts


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
* Nothing to write, just return
Write		    clrb
          		    rts


* Term
*
* Entry:
*    U  = address of device memory area
*
* Exit:
*    CC = carry set on error
*    B  = error code
*
Term                clrb
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
* There are no getstat calls, just return
GetSta	            clrb
		    rts


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
SetSta	            cmpa	#SS.SOLIRQ
		    lbeq	SSOLIRQ
		    comb
		    rts

;;; SS.SOLIRQ
;;;
;;; Start of Line Interrupt
;;;
;;; Add Start of Line Interrupt (max of 8) that will send a signal
;;; to a process at the start of a line on the screen
;;;
;;; Entry: R$Y = Value for signal should be greater than 128
;;;        R$X = Line # that triggers Interrupt (0-479 for 60hz)
;;;
;;; Exit:  B = non-zero error code
;;;       CC = carry flag clear to indicate success
SSOLIRQ       	    ldy	      R$Y,x
		    lbeq      SOLremoveval	  if signal is 0, then remove from list
		    lda       V.SOLOnOff,u
		    lbeq      SOL_TurnOn	  first SOL? need to init and turn on IRQ
		    ldb	      V.SOLMax,u          load max table index
		    cmpb      #7		  max table is 8 entries
		    bne	      cont@		  continue if < 7
		    ldb	      #204		  else: Device Table Full error
		    orcc      #1
		    lbra      ErrExit@
cont@		    lslb
		    lslb
		    ldy	      R$X,x
		    pshs      x
		    pshs      y
		    leay      V.SOLTable,u
		    leay      b,y	          last entry in table
		    ldb	      V.SOLMax,u
		    inc       V.SOLMax,u
* Search through list and insert in order from greatest to least line
* Interrupt will start at the end of the list and work backwards to
* set the next line for the  interrupt.  This part of the routine
* just sets up the list.  The lines are handled in SOL_IRQSvc.
search@		    ldx	      ,y
		    stx	      4,y
		    ldx	      2,y
		    stx	      6,y
		    cmpx      ,s
		    ble	      next@               table value > new value
		    leay      4,y		  Insert into higher row
		    bra	      insertval@
next@		    decb
		    blt	      insertval@	  insert into existing row
		    leay      -4,y
		    bra	      search@
insertval@	    bsr	      SOLinsertval
		    puls      y
		    puls      x
		    andcc     #$FE
		    rts
SOL_TurnOn	    pshs      cc
		    orcc      #IntMasks
		    ldy	      R$X,x
		    pshs      x
		    pshs      y
                    leay      V.SOLTable,u
		    bsr	      SOLinsertval
		    puls      y
		    std	      ,y
		    clr	      V.SOLMax,u
		    clr	      V.SOLCurr,u
		    inc	      V.SOLOnOff,u
		    ldd       #INT_PENDING_0      get the pending interrupt pending address
                    leax      SOL_Pckt,pcr        point to the IRQ packet
                    leay      SOL_IRQSvc,pcr         and the service routine
                    os9       F$IRQ               install the interrupt handler
                    bcc       irqsuccess@         branch if success
		    os9	      F$PErr
irqsuccess@         lda       INT_MASK_0          else get the interrupt mask byte
                    anda      #^INT_VKY_SOL        set the SOL interrupt
                    sta       INT_MASK_0          and save it back
		    puls      x
SOL_ON		    ldd	      R$X,x
		    exg	      a,b
		    std	      $FFD9
		    lda	      #1
		    sta	      $FFD8
		    puls      cc
ErrExit@	    rts

SOLinsertval	    ldx	      2,s	          get line#
		    stx	      2,y		  store in line #
		    ldx	      4,s		  restore x pointer
		    ldd	      R$Y,x		    
		    pshs      y			  
		    ldy	      >D.Proc		  put ProcId in a
		    lda	      P$ID,y
		    puls      y
		    std	      ,y
		    rts

SOLremoveval	    pshs      cc
		    orcc      #IntMasks
		    clrb
		    pshs      x
		    ldy	      R$X,x
		    pshs      y
		    leay      V.SOLTable,u
remsearch@	    ldx	      2,y
		    cmpx      ,s
		    beq	      remove@
		    leay      4,y
		    incb
		    cmpb      V.SOLMax,u
		    ble	      remsearch@
notfound@	    leas      4,s	
		    bra	      end@
remove@		    ldx	      4,y
		    stx	      ,y
		    ldx	      6,y
		    stx	      2,y
		    incb
		    cmpb      V.SOLMax,u
		    beq	      remdone@
		    leay      4,y
		    bra	      remove@
remdone@	    puls      y
		    puls      x
*		    lda	      #INT_VKY_SOL
*		    sta	      INT_PENDING_0
		    dec	      V.SOLMax,u
		    lda	      V.SOLMax,u
		    sta       V.SOLCurr,u
		    bge	      end@
*if V.SOLMax < 0 then remove IRQ
                    lda       INT_MASK_0          else get the interrupt mask byte
                    ora       #INT_VKY_SOL        remove the SOL interrupt
                    sta       INT_MASK_0          and save it back
		    ldd       #INT_PENDING_0      get the pending interrupt pending address
                    ldx	      #0                  Removing irq, set x=0
                    leay      SOL_IRQSvc,pcr      and the service routine
                    os9       F$IRQ               remove the interrupt handler
		    bcc	      irqsuccess@
		    os9	      F$Perr
irqsuccess@	    clr	      V.SOLMax,u
                    clr	      V.SOLOnOff,u
		    clr	      V.SOLCurr,u
		    clr	      $FFD8               disable line interrupt
end@		    puls      cc
		    rts
		    



SOL_IRQSvc	    lda	      #INT_VKY_SOL
		    sta	      INT_PENDING_0
		    lda	      V.SOLOnOff,u
		    beq	      end@
		    ldb	      V.SOLCurr,u         Get current SOL index
		    lslb      			  mult x4 bytes/row    
		    lslb
		    leay      V.SOLTable,u	  get the table
		    ldd	      b,y		  load the current entry
		    os9	      F$Send		  Send it to the process
		    bcc	      nosenderr@
		    os9	      F$PErr
nosenderr@          dec	      V.SOLCurr,u	  decrement the current index
		    bge	      cont@		  if >=0 cont
		    ldb	      V.SOLMax,u	  else: reset to Max
		    stb	      V.SOLCurr,u
cont@		    ldb	      V.SOLCurr,u         load new current index 
		    lslb      			  mult x4 bytes/rowX
		    lslb
		    leay      b,y	          load next line value
		    lda	      3,y
		    ldb	      2,y
		    std	      $FFD9              write to SOL register
end@		    rts

***********************************************************************************
* SS.SOLIRQ F$IRQ packet.
SOL_Pckt            equ       *
SOLPkt.Flip         fcb       %00000000           the flip byte
SOLPkt.Mask         fcb       INT_VKY_SOL         the mask byte
                    fcb       $F1                 the priority byte


		    emod
eom            	    equ *
               	    end