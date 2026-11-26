.SEGMENT "ZORA_F2_ITEM_LINE_HOP_B6"

; Bank 5's ItemLineEnter lands here ($BDAE) when its SwitchBank returns.
    JMP ItemLine

.SEGMENT "ZORA_F2_ITEM_LINE"

; ZORA Show Item Pickups: the status bar's top row says what Link just took.
;
; The seed's table (asm/rom_space.toml site "item-line-names"; zora/rom/item_line.py):
;   ITEM_CODES low bytes, then ITEM_CODES high bytes: each item code's text, or a high byte of 0 for no line;
;   a text: its length N (1-28), then N font tiles, "GOT " and the item's name.
ItemLineNames := $B220
ITEM_CODES = $24

ItemLineLatch := $F0                ; TakeItem's last item code, 0 once shown (bombs, code 0, show nothing)
ItemLineTimer := $F1                ; every other frame one less while the line shows; at 0 the row is blanked
ItemLineAttrReq := $F2              ; 1 after a line is written: the next NMI makes the top row palette 0 (white)
SHOW_TIME = 180                     ; 180 x 2 frames: 6 seconds

ROW_ADDRESS_HIGH = $20              ; PPU $2022: the status bar's blank top row
ROW_ADDRESS_LOW = $22
ROW_TILES = 28
RECORD_END = 3 + ROW_TILES          ; the record's $FF, and DynTileBufLen
TILE_BLANK = $24
TRANSFER_END = $FF
WCR_SLOT_INDEX = $27                ; World_ChangeRupees' LDY #$27, which the hook comes after

; Scratch: World_ChangeRupees and its caller are done with it (asm/flags2/item-counter).
Text := $00                         ; and $01
TilesLeft := $02

; Entered by JMP from the hop, with the hook's return (into World_ChangeRupees) on top of the stack. Writes the
; line for a new item, or the blank once the timer runs out, and then returns past World_ChangeRupees to its
; caller (the row's record has to be alone this frame: the status bar text and the Item Counter both write from
; DynTileBuf+0). Otherwise returns to the hook with Y as it was. Both ways go back through SwitchBank to bank 5's
; ItemLineTail.
;
ItemLine:
    LDX ItemLineLatch
    BEQ @Timer
    LDA #$00
    STA ItemLineLatch
    CPX #ITEM_CODES
    BCS @Timer                      ; not an item code
    LDA ItemLineNames+ITEM_CODES, X
    BEQ @Timer                      ; an item with no line
    STA Text+1
    LDA ItemLineNames, X
    STA Text
    JSR BlankRecord

    ; The text centered: its first tile at column (28 - N) / 2.
    LDY #$00
    LDA (Text), Y
    STA TilesLeft
    LDA #ROW_TILES
    SEC
    SBC TilesLeft
    LSR
    CLC
    ADC #3
    TAX
:
    INY
    LDA (Text), Y
    STA DynTileBuf, X
    INX
    DEC TilesLeft
    BNE :-
    LDA #SHOW_TIME
    STA ItemLineTimer
    LDA #$01
    STA ItemLineAttrReq             ; the NMI makes the top row's colours white
    BNE @Written

@Timer:
    LDA ItemLineTimer
    BEQ @Back
    LDA FrameCounter
    LSR
    BCC @Back
    DEC ItemLineTimer
    BNE @Back
    JSR BlankRecord

@Written:
    PLA                             ; the hook's return: ItemLineTail's RTS goes to World_ChangeRupees' caller
    PLA

@Back:
    LDY #WCR_SLOT_INDEX
    LDA #>(ItemLineTail-1)
    PHA
    LDA #<(ItemLineTail-1)
    PHA
    LDA #$05
    JMP SwitchBank

; Called from TransferCurTileBuf in the NMI, after its transfer (bank 6 is in). The row is PPU $2022, columns 2-29:
; attribute bytes $23C0-$23C7. Each byte's low nibble is the top two quadrants (the row's colours); the read-modify-
; write keeps the high nibble (the bottom quadrants, the life meter's). Ends as TransferCurTileBuf did: buffer empty.
ItemLineAttr:
    LDA ItemLineAttrReq
    BEQ @Done
    LDA #$00
    STA ItemLineAttrReq
    LDX #$00
@Quadrant:
    LDA #$23
    STA PpuAddr_2006
    TXA
    CLC
    ADC #$C0
    STA PpuAddr_2006
    LDA PpuData_2007                ; the first read after a $2006 write is stale
    LDA PpuData_2007
    AND #$F0                        ; the low nibble to palette 0
    STA Text
    LDA #$23
    STA PpuAddr_2006
    TXA
    CLC
    ADC #$C0
    STA PpuAddr_2006
    LDA Text
    STA PpuData_2007
    INX
    CPX #$08
    BNE @Quadrant
@Done:
    LDX #$FF
    STX DynTileBuf
    RTS

; The row's record, all blank, alone in the dynamic buffer.
;
BlankRecord:
    LDA #ROW_ADDRESS_HIGH
    STA DynTileBuf
    LDA #ROW_ADDRESS_LOW
    STA DynTileBuf+1
    LDA #ROW_TILES
    STA DynTileBuf+2
    LDA #TRANSFER_END
    STA DynTileBuf+RECORD_END
    LDA #RECORD_END                 ; records the game adds this frame go after it
    STA DynTileBufLen
    LDX #ROW_TILES-1
    LDA #TILE_BLANK
:
    STA DynTileBuf+3, X
    DEX
    BPL :-
    RTS
