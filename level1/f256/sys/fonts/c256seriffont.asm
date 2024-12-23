********************************************************************
* font - f256serif font
*
* Original by Micah at https://github.com/WartyMN/Foenix-Fonts
*
* $Id$
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   1      2024-09-28  Port from by John Federico
* Created.
*
               nam       c256seriffont
               ttl       c256serif font

               use       defsfile

tylg           set       Data
atrv           set       ReEnt+rev
rev            set       $01

               mod       eom,name,tylg,atrv,start,0

name           fcs       /c256seriffont/

start

*              fcb $1E,$32,$30,$78,$30,$70,$FE,$00
	       fcb $00,$00,$00,$00,$00,$00,$00,$00
	       fcb $00,$00,$00,$00,$00,$00,$FF,$FF
               fcb $00,$00,$00,$00,$00,$FF,$FF,$FF
               fcb $00,$00,$00,$00,$FF,$FF,$FF,$FF
               fcb $00,$00,$00,$FF,$FF,$FF,$FF,$FF
               fcb $00,$00,$FF,$FF,$FF,$FF,$FF,$FF
               fcb $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
               fcb $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
               fcb $FF,$FF,$FF,$FF,$FF,$FF,$FF,$00
               fcb $FF,$FF,$FF,$FF,$FF,$FF,$00,$00
               fcb $FF,$FF,$FF,$FF,$FF,$00,$00,$00
               fcb $FF,$FF,$FF,$FF,$00,$00,$00,$00
               fcb $FF,$FF,$FF,$00,$00,$00,$00,$00
               fcb $FF,$FF,$00,$00,$00,$00,$00,$00
               fcb $FF,$00,$00,$00,$00,$00,$00,$00
               fcb $08,$00,$22,$00,$08,$00,$02,$00
               fcb $88,$00,$22,$00,$88,$00,$22,$00
               fcb $8A,$00,$2A,$00,$8A,$00,$2A,$00
               fcb $AA,$00,$AA,$00,$AA,$00,$AA,$00
               fcb $AA,$05,$AA,$11,$AA,$05,$AA,$11
               fcb $AA,$5F,$AA,$77,$AA,$5F,$AA,$77
               fcb $AA,$FF,$AA,$FF,$AA,$FF,$AA,$FF
               fcb $AF,$FF,$BB,$FF,$AF,$FF,$BB,$FF
               fcb $77,$FF,$DD,$FF,$77,$FF,$DD,$FF
               fcb $7F,$FF,$DF,$FF,$77,$FF,$DF,$FF
               fcb $FF,$FF,$DF,$FF,$77,$FF,$DD,$FF
               fcb $BB,$FF,$EE,$FF,$AA,$FF,$AA,$FF
               fcb $AA,$FF,$AA,$77,$AA,$DD,$AA,$55
               fcb $AA,$55,$22,$55,$88,$55,$00,$55
               fcb $AA,$00,$AA,$00,$88,$00,$22,$00
               fcb $33,$99,$CC,$66,$33,$99,$CC,$66
               fcb $CC,$99,$33,$66,$CC,$99,$33,$66
               fcb $00,$00,$00,$00,$00,$00,$00,$00
               fcb $30,$30,$30,$30,$30,$00,$30,$00
               fcb $66,$66,$00,$00,$00,$00,$00,$00
               fcb $6C,$6C,$FE,$6C,$FE,$6C,$6C,$00
               fcb $10,$7C,$D2,$7C,$86,$7C,$10,$00
               fcb $F0,$96,$FC,$18,$3E,$72,$DE,$00
               fcb $30,$48,$30,$78,$CE,$CC,$78,$00
               fcb $0C,$0C,$18,$00,$00,$00,$00,$00
               fcb $10,$60,$C0,$C0,$C0,$60,$10,$00
               fcb $10,$0C,$06,$06,$06,$0C,$10,$00
               fcb $00,$54,$38,$FE,$38,$54,$00,$00
               fcb $00,$18,$18,$7E,$18,$18,$00,$00
               fcb $00,$00,$00,$00,$00,$00,$18,$70
               fcb $00,$00,$00,$7E,$00,$00,$00,$00
               fcb $00,$00,$00,$00,$00,$00,$18,$00
               fcb $02,$06,$0C,$18,$30,$60,$C0,$00
               fcb $7C,$CE,$DE,$F6,$E6,$E6,$7C,$00
               fcb $18,$38,$78,$18,$18,$18,$3C,$00
               fcb $7C,$C6,$06,$0C,$30,$60,$FE,$00
               fcb $7C,$C6,$06,$3C,$06,$C6,$7C,$00
               fcb $0E,$1E,$36,$66,$FE,$06,$06,$00
               fcb $FE,$C0,$C0,$FC,$06,$06,$FC,$00
               fcb $7C,$C6,$C0,$FC,$C6,$C6,$7C,$00
               fcb $FE,$06,$0C,$18,$30,$60,$60,$00
               fcb $7C,$C6,$C6,$7C,$C6,$C6,$7C,$00
               fcb $7C,$C6,$C6,$7E,$06,$C6,$7C,$00
               fcb $00,$30,$00,$00,$00,$30,$00,$00
               fcb $00,$30,$00,$00,$00,$30,$20,$00
               fcb $00,$1C,$30,$60,$30,$1C,$00,$00
               fcb $00,$00,$7E,$00,$7E,$00,$00,$00
               fcb $00,$70,$18,$0C,$18,$70,$00,$00
               fcb $7C,$C6,$0C,$18,$30,$00,$30,$00
               fcb $7C,$82,$9A,$AA,$AA,$9E,$7C,$00
               fcb $7C,$C6,$C6,$FE,$C6,$C6,$C6,$00
               fcb $FC,$66,$66,$7C,$66,$66,$FC,$00
               fcb $7C,$C6,$C0,$C0,$C0,$C6,$7C,$00
               fcb $FC,$66,$66,$66,$66,$66,$FC,$00
               fcb $FE,$62,$68,$78,$68,$62,$FE,$00
               fcb $FE,$62,$68,$78,$68,$60,$F0,$00
               fcb $7C,$C6,$C6,$C0,$DE,$C6,$7C,$00
               fcb $C6,$C6,$C6,$FE,$C6,$C6,$C6,$00
               fcb $3C,$18,$18,$18,$18,$18,$3C,$00
               fcb $1E,$0C,$0C,$0C,$0C,$CC,$78,$00
               fcb $C6,$CC,$D8,$F0,$D8,$CC,$C6,$00
               fcb $F0,$60,$60,$60,$60,$62,$FE,$00
               fcb $C6,$EE,$FE,$D6,$C6,$C6,$C6,$00
               fcb $C6,$E6,$F6,$DE,$CE,$C6,$C6,$00
               fcb $7C,$C6,$C6,$C6,$C6,$C6,$7C,$00
               fcb $FC,$66,$66,$7C,$60,$60,$F0,$00
               fcb $7C,$C6,$C6,$C6,$C6,$C6,$7C,$0C
               fcb $FC,$66,$66,$7C,$66,$66,$E6,$00
               fcb $7C,$C6,$C0,$7C,$06,$C6,$7C,$00
               fcb $7E,$5A,$18,$18,$18,$18,$3C,$00
               fcb $C6,$C6,$C6,$C6,$C6,$C6,$7C,$00
               fcb $C6,$C6,$C6,$C6,$C6,$6C,$38,$00
               fcb $C6,$C6,$C6,$C6,$D6,$EE,$C6,$00
               fcb $C6,$6C,$38,$38,$38,$6C,$C6,$00
               fcb $66,$66,$66,$3C,$18,$18,$3C,$00
               fcb $FE,$C6,$0C,$18,$30,$66,$FE,$00
               fcb $1C,$18,$18,$18,$18,$18,$1C,$00
               fcb $C0,$60,$30,$18,$0C,$06,$02,$00
               fcb $70,$30,$30,$30,$30,$30,$70,$00
               fcb $00,$00,$10,$38,$6C,$C6,$00,$00
               fcb $00,$00,$00,$00,$00,$00,$00,$FF
               fcb $30,$30,$18,$00,$00,$00,$00,$00
               fcb $00,$00,$7C,$06,$7E,$C6,$7E,$00
               fcb $C0,$C0,$FC,$C6,$C6,$C6,$FC,$00
               fcb $00,$00,$7C,$C6,$C0,$C6,$7C,$00
               fcb $06,$06,$7E,$C6,$C6,$C6,$7E,$00
               fcb $00,$00,$7C,$C6,$FE,$C0,$7C,$00
               fcb $3C,$66,$60,$F0,$60,$60,$60,$00
               fcb $00,$00,$7E,$C6,$C6,$7E,$06,$7C
               fcb $C0,$C0,$FC,$C6,$C6,$C6,$C6,$00
               fcb $18,$00,$38,$18,$18,$18,$3C,$00
               fcb $00,$0C,$00,$1C,$0C,$0C,$CC,$78
               fcb $C0,$C0,$C6,$D8,$F0,$D8,$C6,$00
               fcb $38,$18,$18,$18,$18,$18,$3C,$00
               fcb $00,$00,$EE,$FE,$D6,$C6,$C6,$00
               fcb $00,$00,$FC,$C6,$C6,$C6,$C6,$00
               fcb $00,$00,$7C,$C6,$C6,$C6,$7C,$00
               fcb $00,$00,$FC,$C6,$C6,$FC,$C0,$C0
               fcb $00,$00,$7E,$C6,$C6,$7E,$06,$06
               fcb $00,$00,$DE,$76,$60,$60,$60,$00
               fcb $00,$00,$7C,$C0,$7C,$06,$7C,$00
               fcb $18,$18,$7E,$18,$18,$18,$1E,$00
               fcb $00,$00,$C6,$C6,$C6,$C6,$7E,$00
               fcb $00,$00,$C6,$C6,$C6,$6C,$38,$00
               fcb $00,$00,$C6,$C6,$D6,$FE,$C6,$00
               fcb $00,$00,$C6,$6C,$38,$6C,$C6,$00
               fcb $00,$00,$C6,$C6,$C6,$7E,$06,$7C
               fcb $00,$00,$FE,$0C,$18,$60,$FE,$00
               fcb $0E,$18,$18,$70,$18,$18,$0E,$00
               fcb $18,$18,$18,$00,$18,$18,$18,$00
               fcb $E0,$30,$30,$1C,$30,$30,$E0,$00
               fcb $00,$00,$70,$9A,$0E,$00,$00,$00
               fcb $08,$04,$04,$0C,$18,$10,$18,$00
               fcb $02,$02,$02,$02,$02,$02,$02,$02
               fcb $04,$04,$04,$04,$04,$04,$04,$04
               fcb $08,$08,$08,$08,$08,$08,$08,$08
               fcb $10,$10,$10,$10,$10,$10,$10,$10
               fcb $20,$20,$20,$20,$20,$20,$20,$20
               fcb $40,$40,$40,$40,$40,$40,$40,$40
               fcb $80,$80,$80,$80,$80,$80,$80,$80
               fcb $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0
               fcb $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
               fcb $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
               fcb $F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8
               fcb $FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC
               fcb $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
               fcb $7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F
               fcb $3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F
               fcb $1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F
               fcb $0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F
               fcb $07,$07,$07,$07,$07,$07,$07,$07
               fcb $03,$03,$03,$03,$03,$03,$03,$03
               fcb $01,$01,$01,$01,$01,$01,$01,$01
               fcb $00,$00,$00,$00,$00,$00,$FF,$00
               fcb $00,$00,$00,$00,$00,$FF,$00,$00
               fcb $00,$00,$00,$00,$FF,$00,$00,$00
               fcb $00,$00,$00,$FF,$00,$00,$00,$00
               fcb $00,$00,$FF,$00,$00,$00,$00,$00
               fcb $00,$FF,$00,$00,$00,$00,$00,$00
               fcb $08,$08,$08,$08,$0F,$08,$08,$08
               fcb $00,$00,$00,$00,$FF,$08,$08,$08
               fcb $08,$08,$08,$08,$FF,$08,$08,$08
               fcb $08,$08,$08,$08,$FF,$00,$00,$00
               fcb $08,$08,$08,$08,$F8,$08,$08,$08
               fcb $81,$42,$24,$18,$18,$24,$42,$81
               fcb $00,$00,$00,$00,$0F,$08,$08,$08
               fcb $00,$00,$00,$00,$F8,$08,$08,$08
               fcb $08,$08,$08,$08,$0F,$00,$00,$00
               fcb $08,$08,$08,$08,$F8,$00,$00,$00
               fcb $18,$18,$18,$1F,$1F,$18,$18,$18
               fcb $00,$00,$00,$FF,$FF,$18,$18,$18
               fcb $18,$18,$18,$FF,$FF,$18,$18,$18
               fcb $18,$18,$18,$FF,$FF,$00,$00,$00
               fcb $18,$18,$18,$F8,$F8,$18,$18,$18
               fcb $00,$00,$00,$1F,$1F,$18,$18,$18
               fcb $00,$00,$00,$F8,$F8,$18,$18,$18
               fcb $18,$18,$18,$1F,$1F,$00,$00,$00
               fcb $18,$18,$18,$F8,$F8,$00,$00,$00
               fcb $00,$00,$00,$FF,$FF,$00,$00,$00
               fcb $18,$18,$18,$18,$18,$18,$18,$18
               fcb $00,$00,$00,$00,$03,$07,$0F,$0F
               fcb $00,$00,$00,$00,$C0,$E0,$F0,$F0
               fcb $0F,$0F,$07,$03,$00,$00,$00,$00
               fcb $F0,$F0,$E0,$C0,$00,$00,$00,$00
               fcb $00,$3C,$42,$42,$42,$42,$3C,$00
               fcb $00,$3C,$7E,$7E,$7E,$7E,$3C,$00
               fcb $00,$7E,$7E,$7E,$7E,$7E,$7E,$00
               fcb $00,$00,$00,$18,$18,$00,$00,$00
               fcb $00,$00,$00,$00,$08,$00,$00,$00
               fcb $FF,$7F,$3F,$1F,$0F,$07,$03,$01
               fcb $FF,$FE,$FC,$F8,$F0,$E0,$C0,$80
               fcb $80,$40,$20,$10,$08,$04,$02,$01
               fcb $01,$02,$04,$08,$10,$20,$40,$80
               fcb $00,$00,$00,$00,$03,$04,$08,$08
               fcb $00,$00,$00,$00,$E0,$10,$08,$08
               fcb $08,$08,$08,$04,$03,$00,$00,$00
               fcb $08,$08,$08,$10,$E0,$00,$00,$00
               fcb $00,$00,$00,$00,$00,$00,$00,$55
               fcb $00,$00,$00,$00,$00,$00,$AA,$55
               fcb $00,$00,$00,$00,$00,$55,$AA,$55
               fcb $00,$00,$00,$00,$AA,$55,$AA,$55
               fcb $00,$00,$00,$55,$AA,$55,$AA,$55
               fcb $00,$00,$AA,$55,$AA,$55,$AA,$55
               fcb $00,$55,$AA,$55,$AA,$55,$AA,$55
               fcb $AA,$55,$AA,$55,$AA,$55,$AA,$55
               fcb $AA,$55,$AA,$55,$AA,$55,$AA,$00
               fcb $AA,$55,$AA,$55,$AA,$55,$00,$00
               fcb $AA,$55,$AA,$55,$AA,$00,$00,$00
               fcb $AA,$55,$AA,$55,$00,$00,$00,$00
               fcb $AA,$55,$AA,$00,$00,$00,$00,$00
               fcb $AA,$55,$00,$00,$00,$00,$00,$00
               fcb $AA,$00,$00,$00,$00,$00,$00,$00
               fcb $80,$00,$80,$00,$80,$00,$80,$00
               fcb $80,$40,$80,$40,$80,$40,$80,$40
               fcb $A0,$40,$A0,$40,$A0,$40,$A0,$40
               fcb $A0,$50,$A0,$50,$A0,$50,$A0,$50
               fcb $A8,$50,$A8,$50,$A8,$50,$A8,$50
               fcb $A8,$54,$A8,$54,$A8,$54,$A8,$54
               fcb $AA,$54,$AA,$54,$AA,$54,$AA,$54
               fcb $2A,$55,$2A,$55,$2A,$55,$2A,$55
               fcb $7E,$81,$9D,$A1,$A1,$9D,$81,$7E
               fcb $2A,$15,$2A,$15,$2A,$15,$2A,$15
               fcb $0A,$15,$0A,$15,$0A,$15,$0A,$15
               fcb $0A,$05,$0A,$05,$0A,$05,$0A,$05
               fcb $02,$05,$02,$05,$02,$05,$02,$05
               fcb $02,$01,$02,$01,$02,$01,$02,$01
               fcb $00,$01,$00,$01,$00,$01,$00,$01
               fcb $00,$00,$03,$06,$6C,$38,$10,$00
               fcb $7E,$81,$BD,$A1,$B9,$A1,$A1,$7E
               fcb $00,$00,$3C,$3C,$3C,$3C,$00,$00
               fcb $00,$3C,$42,$5A,$5A,$42,$3C,$00
               fcb $00,$00,$18,$3C,$3C,$18,$00,$00
               fcb $FF,$81,$81,$81,$81,$81,$81,$FF
               fcb $01,$03,$07,$0F,$1F,$3F,$7F,$FF
               fcb $80,$C0,$E0,$F0,$F8,$FC,$FE,$FF
               fcb $3F,$1F,$0F,$07,$03,$01,$00,$00
               fcb $FC,$F8,$F0,$E0,$C0,$80,$00,$00
               fcb $00,$00,$01,$03,$07,$0F,$1F,$3F
               fcb $00,$00,$80,$C0,$E0,$F0,$F8,$FC
               fcb $0F,$07,$03,$01,$00,$00,$00,$00
               fcb $F0,$E0,$C0,$80,$00,$00,$00,$00
               fcb $00,$00,$00,$00,$01,$03,$07,$0F
               fcb $00,$00,$00,$00,$80,$C0,$E0,$F0
               fcb $03,$01,$00,$00,$00,$00,$00,$00
               fcb $C0,$80,$00,$00,$00,$00,$00,$00
               fcb $00,$00,$00,$00,$00,$00,$01,$03
               fcb $00,$00,$00,$00,$00,$00,$80,$C0
               fcb $00,$00,$00,$00,$0F,$0F,$0F,$0F
               fcb $00,$00,$00,$00,$F0,$F0,$F0,$F0
               fcb $0F,$0F,$0F,$0F,$00,$00,$00,$00
               fcb $F0,$F0,$F0,$F0,$00,$00,$00,$00
               fcb $F0,$F0,$F0,$F0,$0F,$0F,$0F,$0F
               fcb $0F,$0F,$0F,$0F,$F0,$F0,$F0,$F0
               fcb $00,$00,$00,$3E,$1C,$08,$00,$00
               fcb $00,$00,$08,$18,$38,$18,$08,$00
               fcb $00,$00,$10,$18,$1C,$18,$10,$00
               fcb $00,$00,$08,$1C,$3E,$00,$00,$00
               fcb $36,$7F,$7F,$7F,$3E,$1C,$08,$00
               fcb $08,$1C,$3E,$7F,$3E,$1C,$08,$00
               fcb $08,$1C,$3E,$7F,$7F,$1C,$3E,$00
               fcb $08,$1C,$2A,$77,$2A,$08,$1C,$00

               emod
eom            equ       *
               end

