********************************************************************
* bitmapex - bitmap example converting EMWHITE example located at
* https://github.com/foenixrising/bitmap_ex/blob/main/bitmap_ex.asm
*
* $Id$
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------


                    nam       bitmapex
                    ttl       basic f256 graphics test

* Disassembled 98/09/11 12:07:32 by Disasm v1.6 (C) 1988 by RML

                    ifp1
                    use       defsfile
                    endc

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       3

*MMU_MEM_CTRL       equ       $FFA0             Already defined in defsfile     
*MMU_IO_CTRL        equ       $FFA1             Already defined in defsfile, but IO block (FE00-FF9F) is static on 6809

* On 6809 Vicky MCR is $FC00-$FFDF
VKY_MSTR_CTRL_0     equ       $FFC0             ; Vicky Master Control Register 0 (defsfile MASTER_CTRL_REG_L)
VKY_MSTR_CTRL_1     equ       $FFC1             ; Vicky Master Control Register 1 (defsfile MASTER_CTRL_REG_H)

VKY_LAYER_CTRL_0    equ       $FFC2             (defsfile VKY_RESERVED_00)
VKY_LAYER_CTRL_1    equ       $FFC3             (defsfile VKY_RESERVED_01)

*BORDER_CTRL_REG     equ       $FFC4            ; Already defined in defsfile

* 6809 bitmap controls are in page $C0 starting at $1000
* if we map $C0 to slot 1 ($2000), these values start at $3000
VKY_BM0_CTRL        equ       $3000             ; Bitmap #0 Control Register
VKY_BM0_ADDR_L      equ       $3001             ; Bitmap #0 Address bits 7..0
VKY_BM0_ADDR_M      equ       $3002             ; Bitmap #0 Address bits 15..8
VKY_BM0_ADDR_H      equ       $3003             ; Bitmap #0 Address bits 17..16

VKY_BM1_CTRL        equ       $3008

*Mstr_Ctrl_Text_Mode_En = $01 ; Enable Text Mode  ;Already defined in defs/f256.d

;App specific defines
*bitmap_base        equ       $06C000           Going to manually put this in below

COLUMNS             equ       256               ; Number of columns/bytes per row (a friendly # which is 32 : 256 : 32 = 320 pixel screen)
COLOR1              equ       $FF       ; FOENIX Purple color aka #106 #13 #173 aka $6A0DAD, instanciated below as collor 255

*Changing location from original - OS9 highram is unused
MMU_MEM_BANK_0      equ       $FFA8
MMU_MEM_BANK_1      equ       $FFA9
MMU_MEM_BANK_2      equ       $FFAA
MMU_MEM_BANK_3      equ       $FFAB
MMU_MEM_BANK_4      equ       $FFAC
MMU_MEM_BANK_5      equ       $FFAD
MMU_MEM_BANK_6      equ       $FFAE
MMU_MEM_BANK_7      equ       $FFAF

MAPSLOT             equ       MMU_SLOT_1
MAPSLOT2            equ       MMU_SLOT_2
MAPADDR             equ       (MAPSLOT-MMU_SLOT_0)*$2000
MAPADDR2            equ       (MAPSLOT2-MMU_SLOT_0)*$2000

                    mod       eom,name,tylg,atrv,start,size

*pointer            rmb       2         Don't need this on 6809, x,y are 16 bits, use y for pointer
defcolor            rmb       1
pencolor            rmb       1
line                rmb       1
bm_bank             rmb       1
*column             rmb       1        Use x register for this
gbase_lo            rmb       1
gbase_hi            rmb       1
temp                rmb       1

* Extra variables I added to get make MMU handling easier
MMUORIG             rmb       1
MMUEDIT             rmb       1
MMUACTIVE           rmb       1

size                equ       .

name                fcs       /bitmapex/
                    fcb       edition




start
*                   clr       MMU_IO_CTRL               Don't need this.  IO static on 6809.
                    lda       #Mstr_Ctrl_Text_Mode_En   ; text mode (for now)
                    sta       VKY_MSTR_CTRL_0
                    clr       BORDER_CTRL_REG           ; zero disables the border

******  Don't need this section.  CLUT0 is in page $C1 at $800 ($18_2800 $C1 starts at $18_2000) 
*                   lda       #$01                      ; switch to feature bank 1 of I/O for palette manipulation
*                   sta       MMU_IO_CTRL
*                   lda       #<VKY_MSTR_CTRL_0         ; initalize 'pointer' to $d000; note that this is the same base
*                   sta       pointer                   ;   address as the VICKY Master Control Register but we are in bank 1 now !!                           
*                   lda       #>VKY_MSTR_CTRL_0         ;   IT IS EASY TO GET CONFUSED !!

*                   sta       pointer+1
******

* MMU shenanigans:  Get the current MLUT and make sure we enable editing, set mmu slot to $C1
                    pshs      cc
                    orcc      #IntMasks           mask interrupts
                    lda       MMU_MEM_CTRL        Get the MMU_MEM_CTRL Value
                    sta       MMUORIG,u           Store it for posteity
                    anda      #%00000011          Get the MLUT#
                    sta       MMUACTIVE,u         Store it
                    lsla                          Shift it to Edit position 
                    lsla
                    lsla
                    lsla
                    ora       MMUACTIVE,u         Add MLUT# back to active bits
                    sta       MMUEDIT,u           Store this for later use
                    sta       MMU_MEM_CTRL                  
                    lda       MMU_MEM_BANK_1              Get current MMU Slot value        
                    pshs      a                   Store on stack
                    lda       #$C1                load MMU block $C1 for CLUT
                    sta       MMU_MEM_BANK_1             store it in the MMU slot to map it in

                    ldb       #$00                Counter for loops
                    ldy       #$2800              location of CLUT0 in Bank 1 (pointer)
                    
lut_loop
*                   ldy       #$00
                    tfr       b,a
                    eora      #$ff
                    sta       ,y+
                    lda       #$E0  ; green
                    sta       ,y+
                    tfr       b,a
                    eora      #$ff
                    inca
                    sta       ,y++
                    incb
                    beq       lut_done
* Not Needed        lda       pointer
*                   adc       #$04
*                   sta       pointer
*                   lda       pointer+1
*                   adc       #$00
*                   sta       pointer+1
                    bra       lut_loop
lut_done
                    lda       #173            ; this is our customer purple color aka $6A0DAD
                    sta       $2Bfc
                    lda       #13
                    sta       $2Bfd
                    lda       #106
                    sta       $2Bfe
                    puls      a               restore the MMU_SLOT1 to original value
                    sta       MMU_MEM_BANK_1
                    puls      cc              turn interrupts back on

; layer setup

* Not needed        clr       MMU_IO_CTRL     ; back in feature bank 0 of I/O aka, most of the graphics registers
                    lda       #$40            ; config for a simple tile map 0 @ layer 1 (not used); bitmap 0 at layer 0 (used)
                    sta       VKY_LAYER_CTRL_0
                    lda       #$01            ; config for bitmap 1 at layer 2 (not used)
                    sta       VKY_LAYER_CTRL_1

* Bitmap registers are in $C0 at $1000, so $3000 when mapped into slot 1
                    pshs      cc
                    orcc      #IntMasks
                    lda       MMU_MEM_BANK_1
                    pshs      a
                    lda       MMUEDIT,u
                    sta       MMU_MEM_CTRL
                    lda       $C0
                    sta       MMU_MEM_BANK_1
                    
; instantiate graphic mode
                    lda       #$2C            ;2 (bit 5) turns sprites on; C (bits 3 and 2) turn bitmap and graphics on
                    sta       VKY_MSTR_CTRL_0 ; Save that to VICKY master control register 0

                    lda       #$01            ;1 (bit 0) enables CLK_70 mode which is 70 Hz. (640x400 text and 320 x 200 graphics)            
                    sta       VKY_MSTR_CTRL_1 ; Make sure we’re just in 320x200 mode (VICKY master control register 1)

                    lda       #$00            ; Set the low byte of the bitmap’s address
                    sta       VKY_BM0_ADDR_L
                    lda       #$C0            ; Set the middle byte of the bitmap’s address
                    sta       VKY_BM0_ADDR_M
                    lda       #$06            ; Set the upper two bits of the bitmap’s address
* Not needed        and       #$03
                    sta       VKY_BM0_ADDR_H  ; The and #$03 is not necessary; this is from Peter's example; this is the $1:xxxx addr

                    puls      a               restore MMU Slot value
                    sta       MMU_MEM_BANK_1
                    puls      cc

; Set the line number to 0
;
                    clr       line,u    ; store 0 in 'line' which is the starting color for the gradient hires screen
                    inc       line,u    ; advance it 4 colors in order to skip 000 (transparent)
                    inc       line,u    ; skip 001 (we use for our ligher purple color of sprites)
                    inc       line,u    ; skip 002 (we use for our dark purple sprite shadow)
                    inc       line,u    ; skip 003 (for good measure; we may use this later)


; Calculate the bank number for the bitmap
*                   lda #($10000 >>13)  ; bit shift 13x aka answer = 8
*                   sta bm_bank
                    lda       $36       ; lazy, just hard code this for now
                    sta       bm_bank,u

bank_loop
****** Not needed
*                   stz pointer         ; Set the pointer to start of the current bank
*                   lda #$20            ; starting at $2000 (page 1)
*                   sta pointer+1
******
                    ldy       #$2000    ; Use y for pointer
                    ldx       #$00      ; Use x for column
*                   clr       column,u
*                   clr       column+1,u



; Alter the LUT entries for $2000 -> $bfff
                    pshs      cc
                    orcc      #IntMasks
                    lda       MMU_MEM_BANK_1
                    pshs      a
                    lda       MMUEDIT,u            ; Turn on editing of MMU LUT #0, and work off #0
                    sta       MMU_MEM_CTRL
                    lda       bm_bank
                    sta       MMU_MEM_BANK_1
* Not needed        stz       MMU_MEM_CTRL
*                   ldx       #$00  ;new
                    ldb       #$00

loop2
                    lda       line,u        ; The line number is the color of the line
                    sta       ,y

inc_column          leax      1,x
*                   inc       column,u      ; Increment the column number
*                   bne       chk_col
*                   inc       column+1,u

chk_col        
*                   lda       column,u      ; Check to see if we have finished the row
*                   cmpa      #<320
*                   bne       inc_point
*                   lda       column+1,u
*                   cmpa      #>320
*                   bne       inc_point
                    cmpx      #320
                    bne       inc_point
                    
                    lda       line,u         
                    incb             
                    cmpb      #$02
                    bne       ckk_bra
                    ldb       #$00
                    inca                        ; If so, increment the line number

ckk_bra
                    sta       line,u
                    cmpa      #200        ; If line = 200, we’re done
                    beq       done
                    ldx       #0
*                   clr       column,u      ; Set the column to 0
*                   clr       column+1,u

inc_point
*                   inc       pointer,u     ; Increment pointer
*                   bne       loop2       ; If < $4000, keep looping
*                   inc       pointer+1
*                   lda       pointer+1
                    leay      1,y
                    cmpy      #$4000
                    bne       loop2
                    inc       bm_bank,u     ; Move to the next bank
                    bra       bank_loop   ; And start filling it


done
                    bsr       frame
                    puls      a
                    sta       MAPSLOT
                    puls      cc
                    os9       F$Exit
*loop               nop             ; Lock up here
*                   bra       loop


;----------------------------------------------
            
; Fetch bank routine
; given a scan line (in x register), fetch the appropriate 8K bank to $2000

ftchbnk             lda       MMUEDIT,u            ; Turn on editing of MMU LUT #0, and work off #0
                    sta       MMU_MEM_CTRL
                    lda       bank,x          ; load value from bank table indexed by x register
                    adda      #$36            ; add 8; therefore, 0 = 8th bank of 8192 or the 65,536th byte of memory
                    sta       MMU_MEM_BANK_1
                    adda      #$01            ; importantly, we also grab the subsequent bank into $4000; this is necessary
                    sta       MMU_MEM_BANK_2  ;   to solve the jagged edge scenario (see FR issue #F5, page 4 and 6 for a
                    rts                       ;   detailed account of why this is necessary)

; Draw the boundary
;
; A key tenet of this scheme; column 0 is actaully the 32nd column otherwise known as address $2020
; when banked in (or bank 8 which normally lives at $1:0000 also known as the top of the screen,
; synomonous with the bottom of bitmap memory)
;
; The table is offset by hex $20 so that draws of objects in the full 'balls' demo can be accomplished
; without any CLC; ADC; operations.  This optimization is preferred but limits the scheme since it cannot
; 'print' pixels in positions 0..31 (and to maintain symmetry) or 192 to 319.
; 
frame               lda       #COLOR1         ; constant that refers to the Purple color for the frame
                    ldy       #$01
                    bsr       hline           ; line on the top row
                
                    ldy       #191
                    bsr       hline             ; line on the bottom row   
            
                    lda       #COLOR1
                    ldy       #0
                    bsr       vline             ; line on the left column
                
                    lda       #COLOR1
                    ldy       #COLUMNS-1
                    bsr       vline             ; line on the right column
                    rts


; Draw a horizontal line on all but the topmost and bottommost rows
; A = byte (colored pixel) to write in each position
; Y = scan line to draw on
;
; Uses zero page addresses gbase_lo, gbase_hi, COLOR1 is passed in via (a)ccumulator

hline               pshs      a
                    ldd       table_hilo,y
                    tfr       d,y
                    tfr       a,b
                    clra
                    tfr       d,x
                    bsr       ftchbnk
                    ldy       #COLUMNS-1            ; width of screen in bytes
                    puls      a
looph@              sta       ,y
                    leay      -1,y
                    bne       looph@
                    rts

; Draw a vertical line on all but the topmost and bottommost rows
; A = byte (colored pixel) to write in each position
; Y = column
;
; Uses zero page addresses gbase_lo, gbase_hi, COLOR1 is passed in via (a)ccumulator

vline               sta       temp,u
                    ldx       #191                   ; start at second-to-last row
                    tfr       y,d
                    clra      
loopv@              ldy       table_hilo,x
                    jsr       ftchbnk               ; call to ftchbnk
                    lda       temp,u
                    sta       b,y                   ; write the color byte
                    leax      -1,x                  ; previous row
                    bne       loopv@
                    rts



; Tables containing high and low bytes for 200 scan lines.  They assist in targeting precise bitmap memory locations
;
; example: if we were looking to write to the 3rd scan line of the screen, we would load an index
; register with 2, then grab or LDA table_hi,index and place it into a zero page address as the high byte
; and then grab table_lo,index and place it into the adjacent (prior) zero page address (65xx CPUs are little endian).
;
; a write to (zeropageaddress),x will address the x'th pixel of the indexed line

table_hilo
                    fdb  $2020,$2160,$22a0,$23e0,$2520,$2660,$27a0,$28e0,$2a20,$2b60,$2ca0,$2de0,$2f20,$3060,$31a0,$32e0
                    fdb  $3420,$3560,$36a0,$37e0,$3920,$3a60,$3ba0,$3ce0,$3e20,$3f60,$20a0,$21e0,$2320,$2460,$25a0,$26e0
                    fdb  $2820,$2960,$2aa0,$2be0,$2d20,$2e60,$2fa0,$30e0,$3220,$3360,$34a0,$35e0,$3720,$3860,$39a0,$3ae0
                    fdb  $3c20,$3d60,$3ea0,$3fe0,$2120,$2260,$23a0,$24e0,$2620,$2760,$28a0,$29e0,$2b20,$2c60,$2da0,$2ee0
                    fdb  $3020,$3160,$32a0,$33e0,$3520,$3660,$37a0,$38e0,$3a20,$3b60,$3ca0,$3de0,$3f20,$2060,$21a0,$22e0
                    fdb  $2420,$2560,$26a0,$27e0,$2920,$2a60,$2ba0,$2ce0,$2e20,$2f60,$30a0,$31e0,$3320,$3460,$35a0,$36e0
                    fdb  $3820,$3960,$3aa0,$3be0,$3d20,$3e60,$3fa0,$20e0,$2220,$2360,$24a0,$25e0,$2720,$2860,$29a0,$2ae0
                    fdb  $2c20,$2d60,$2ea0,$2fe0,$3120,$3260,$33a0,$34e0,$3620,$3760,$38a0,$39e0,$3b20,$3c60,$3da0,$3ee0
                    fdb  $2020,$2160,$22a0,$23e0,$2520,$2660,$27a0,$28e0,$2a20,$2b60,$2ca0,$2de0,$2f20,$3060,$31a0,$32e0
                    fdb  $3420,$3560,$36a0,$37e0,$3920,$3a60,$3ba0,$3ce0,$3e20,$3f60,$20a0,$21e0,$2320,$2460,$25a0,$26e0
                    fdb  $2820,$2960,$2aa0,$2be0,$2d20,$2e60,$2fa0,$30e0,$3220,$3360,$34a0,$35e0,$3720,$3860,$39a0,$3ae0
                    fdb  $3c20,$3d60,$3ea0,$3fe0,$2120,$2260,$23a0,$24e0,$2620,$2760,$28a0,$29e0,$2b20,$2c60,$2da0,$2ee0
                    fdb  $3020,$3160,$32a0,$33e0,$3520,$3660,$37a0,$38e0



; The bank table is likewise a map of scan lines to memory banks.  As above, it trades memory (400 bytes)
; for performance.  This table is used by the bankftch routine.

bank
                    fcb $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
                    fcb $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01
                    fcb $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
                    fcb $01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
                    fcb $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03,$03
                    fcb $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
                    fcb $03,$03,$03,$03,$03,$03,$03,$04,$04,$04,$04,$04,$04,$04,$04,$04
                    fcb $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
                    fcb $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
                    fcb $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$06,$06,$06,$06,$06,$06
                    fcb $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
                    fcb $06,$06,$06,$06,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07
                    fcb $07,$07,$07,$07,$07,$07,$07,$07,$07


                    emod
eom                 equ       *
                    end
