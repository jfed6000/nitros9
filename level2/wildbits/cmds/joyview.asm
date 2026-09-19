********************************************************************
* joyview - show what SS.Joy returns: both sticks and four pads
*
* Every 6 ticks it reads SS.Joy mode 2 (both sticks) and mode 5 or 6
* (four NES or SNES pads, through the buffer), and prints a line when
* anything changed:
*
*   sticks 00 00  SNES 0000 0000 0000 0000
*
* in hex, 1 = pressed (wildbits.d JY.* bits: low byte = up, down, left,
* right, button 0, 1, 2 / SNES X; high byte = Select, Start, L, R).
* N selects NES pads, S selects SNES pads (the default); Q quits.  The
* first reading after a change of type is all zeros.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*  1       2026/09/19  Claude Opus 5 / John Federico
* Written with the SS.Joy modes; never run on hardware at the time of
* writing.

                    nam       joyview
                    ttl       SS.Joy viewer

                    ifp1
                    use       defsfile
                    endc

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

TPATH               equ       2         the terminal, even with stdout redirected

                    mod       eom,name,tylg,atrv,start,size

mode                rmb       2         JOY.NES4 or JOY.SNES4
cur                 rmb       10        sticks (2) then the four pad words (8)
last                rmb       10        what was printed last
keybuf              rmb       1
linebuf             rmb       64
                    rmb       250       stack
size                equ       .

name                fcs       /joyview/
                    fcb       edition

start               ldd       #JOY.SNES4
                    std       mode,u
                    ldd       #$FFFF              force the first line
                    std       last,u
                    leax      BanTxt,pcr
                    lbsr      PutLine

loop@               ldx       #6
                    os9       F$Sleep
                    lda       #TPATH              both sticks
                    ldb       #SS.Joy
                    ldx       #JOY.Sticks
                    os9       I$GetStt
                    lbcs      Fatal
                    tfr       x,d
                    stb       cur,u
                    tfr       y,d
                    stb       cur+1,u
                    lda       #TPATH              four pads
                    ldb       #SS.Joy
                    ldx       mode,u
                    leay      cur+2,u
                    os9       I$GetStt
                    lbcs      Fatal
                    leax      cur,u               changed?
                    leay      last,u
                    ldb       #10
cmp@                lda       ,x+
                    cmpa      ,y+
                    bne       show@
                    decb
                    bne       cmp@
                    bra       key@
show@               lbsr      Show
key@                lbsr      CkKey
                    bcc       loop@
                    clrb
                    os9       F$Exit

Fatal               pshs      b
                    leay      linebuf,u
                    leax      ErrTxt,pcr
                    lbsr      AppStr
                    lda       ,s
                    lbsr      AppHex
                    lbsr      EndLine
                    puls      b
                    os9       F$Exit

********************************************************************
* Show - print cur and copy it to last
********************************************************************
Show                leax      cur,u
                    leay      last,u
                    ldb       #10
cp@                 lda       ,x+
                    sta       ,y+
                    decb
                    bne       cp@
                    leay      linebuf,u
                    leax      StkTxt,pcr
                    lbsr      AppStr
                    lda       cur,u
                    lbsr      AppHex
                    lda       #C$SPAC
                    sta       ,y+
                    lda       cur+1,u
                    lbsr      AppHex
                    leax      NesTxt,pcr
                    ldd       mode,u
                    cmpd      #JOY.NES4
                    beq       nm@
                    leax      SnesTxt,pcr
nm@                 lbsr      AppStr
                    leax      cur+2,u
                    ldb       #4
pd@                 lda       #C$SPAC
                    sta       ,y+
                    lda       ,x+
                    lbsr      AppHex
                    lda       ,x+
                    lbsr      AppHex
                    decb
                    bne       pd@
                    lbra      EndLine

********************************************************************
* CkKey - N, S or Q if one is waiting.  Carry set = quit.
********************************************************************
CkKey               lda       #TPATH
                    ldb       #SS.Ready
                    os9       I$GetStt
                    bcs       no@                 nothing there (E$NotRdy)
                    leax      keybuf,u
                    ldy       #1
                    lda       #TPATH
                    os9       I$Read
                    bcs       no@
                    lda       keybuf,u
                    anda      #$5F                upper case
                    cmpa      #'Q
                    beq       quit@
                    ldx       #JOY.NES4
                    cmpa      #'N
                    beq       set@
                    ldx       #JOY.SNES4
                    cmpa      #'S
                    bne       no@
set@                stx       mode,u
                    ldd       #$FFFF              print the next reading
                    std       last,u
no@                 andcc     #^Carry
                    rts
quit@               orcc      #Carry
                    rts

********************************************************************
* Line building.  Y is the write pointer into linebuf throughout.
********************************************************************
AppStr              pshs      a
as@                 lda       ,x+
                    beq       ex@
                    sta       ,y+
                    bra       as@
ex@                 puls      a,pc

AppHex              pshs      a
                    lsra
                    lsra
                    lsra
                    lsra
                    bsr       Nyb
                    sta       ,y+
                    lda       ,s
                    bsr       Nyb
                    sta       ,y+
                    puls      a,pc
Nyb                 anda      #$0F
                    adda      #'0
                    cmpa      #'9
                    bls       ex@
                    adda      #7
ex@                 rts

EndLine             lda       #C$CR
                    sta       ,y
                    leax      linebuf,u
* fall through
PutLine             pshs      x,y,d
                    ldy       #100
                    lda       #1
                    os9       I$WritLn
                    puls      d,x,y,pc

BanTxt              fcc       /joyview - SS.Joy sticks and pads, 1 = pressed.  N = NES, S = SNES, Q quits/
                    fcb       C$CR
StkTxt              fcc       /sticks /
                    fcb       0
NesTxt              fcc       /  NES /
                    fcb       0
SnesTxt             fcc       /  SNES/
                    fcb       0
ErrTxt              fcc       /joyview: SS.Joy error $/
                    fcb       0

                    emod
eom                 equ       *
                    end
