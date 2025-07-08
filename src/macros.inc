.ifndef __MACROS_INC__
__MACROS_INC__ = 1

;**************************************************************
; Macro: wait_for_vblank
;--------------------------------------------------------------
; Waits for the start of vertical blank (VBlank) by polling
; the PPU status register ($2002).
;
; Operation:
;   - BIT $2002 sets the Negative flag (N) based on bit 7,
;     which is the VBlank flag.
;   - If bit 7 is clear (still drawing), BPL loops back.
;   - Once bit 7 is set (VBlank started), branch is skipped.
;
; Usage:
;   wait_for_vblank
;**************************************************************

.macro wait_for_vblank
@loop:
    BIT $2002          ; Check PPU status (bit 7 = VBlank)
    BPL @loop          ; If still drawing, loop until VBlank
.endmacro

;******************************************************************************
; Macro: vram_set_address
;------------------------------------------------------------------------------
; Sets the VRAM address pointer to a specific address in PPU memory space.
;
; Parameters:
;   new_address — A 16-bit label or constant representing a VRAM address
;                (e.g., $2000 for nametable 0, $23C0 for attribute table, etc.)
;
; Behavior:
;   - Reads PPU_STATUS to reset the internal VRAM address latch
;   - Writes the high byte (>) of newAddress to $2006
;   - Writes the low byte (<) of newAddress to $2006
;
; Notes:
;   - Required before writing to $2007 (VRAM data port)
;   - PPU requires two writes to $2006: first high, then low
;******************************************************************************
.macro vram_set_address new_address

    LDA PPU_STATUS          ; Reset VRAM address latch (required before writing $2006)
    LDA #>new_address       ; High byte of address (e.g., $23 from $23C0)
    STA PPU_ADDRESS         ; Write high byte to $2006
    LDA #<new_address       ; Low byte of address (e.g., $C0 from $23C0)
    STA PPU_ADDRESS         ; Write low byte to $2006

.endmacro

;*****************************************************************
; Macro: clear_oam
;---------------------------------------
; Purpose:
;   Hides all 64 sprites by writing Y = $FF (offscreen) to each
;   sprite entry in the specified OAM buffer.
;
; Parameters:
;   oam_buffer - label pointing to the 256-byte sprite buffer
;
; Notes:
; - Each sprite occupies 4 bytes in OAM:
;     Byte 0: Y position      ← written with $FF
;     Byte 1: Tile index      ← skipped
;     Byte 2: Attributes      ← skipped
;     Byte 3: X position      ← skipped
; - The @loop label is local to the macro to prevent naming conflicts.
;*****************************************************************

.macro clear_oam oam_buffer
    LDA #$FF         ; Value $FF = offscreen Y position
    LDX #$00         ; Start at beginning of the OAM buffer

@loop:
    STA oam_buffer, X   ; Set Y position of current sprite to $FF
    INX                  ; Move to tile index byte
    INX                  ; Skip tile index
    INX                  ; Skip attributes
    INX                  ; Skip X position (next sprite’s Y)
    BNE @loop            ; Repeat until X wraps to 0 (done with 256 bytes)

.endmacro

;******************************************************************************
; Macro: set_sprite
;------------------------------------------------------------------------------
; Sets the properties of a single sprite in the OAM buffer.
;
; Parameters:
;   oam_buffer   — Base label for the OAM buffer (typically at $0200)
;   sprite_num   — Index (0–63) of the sprite to update
;   y_pos        — Y position of the sprite on screen
;   tile_num     — Tile index in pattern table
;   attributes   — Attribute byte (palette, flip, priority)
;   x_pos        — X position of the sprite on screen
;
; Notes:
;   - Each sprite occupies 4 bytes in OAM:
;     Byte 0: Y position
;     Byte 1: Tile index
;     Byte 2: Attributes
;     Byte 3: X position
;   - This macro calculates the offset as (sprite_num * 4) automatically.
;******************************************************************************
.macro set_sprite oam_buffer, sprite_num, y_pos, tile_num, attributes, x_pos
    LDA #y_pos
    STA oam_buffer + (sprite_num * 4) + 0

    LDA #tile_num
    STA oam_buffer + (sprite_num * 4) + 1

    LDA #attributes
    STA oam_buffer + (sprite_num * 4) + 2

    LDA #x_pos
    STA oam_buffer + (sprite_num * 4) + 3

.endmacro


.endif
