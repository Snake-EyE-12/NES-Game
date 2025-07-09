.include "nes.inc"
.include "macros.inc"

SPRITE_0_ADDR = oam + 0
SPRITE_1_ADDR = oam + 4
SPRITE_2_ADDR = oam + 8
SPRITE_3_ADDR = oam + 12

;*****************************************************************
; Define NES cartridge Header
;*****************************************************************
; NES ROM Header - tells emulator/hardware about the ROM
.segment "HEADER"
.byte 'N', 'E', 'S', $1a      ; "NES" followed by MS-DOS EOF marker
.byte $02                     ; 2 x 16KB PRG-ROM banks
.byte $01                     ; 1 x 8KB CHR-ROM bank
.byte $00, $00                ; Mapper 0, no special features

;*****************************************************************
; Define NES interrupt vectors
;*****************************************************************
; Interrupt vectors - tells CPU where to jump for each interrupt
.segment "VECTORS"
.addr nmi_handler         ; NMI vector ($FFFA-$FFFB)
.addr reset_handler       ; Reset vector ($FFFC-$FFFD)
.addr irq_handler         ; IRQ vector ($FFFE-$FFFF)

;*****************************************************************
; 6502 Zero Page Memory ($0000–$00FF)
;*****************************************************************
; Fast RAM accessible with 1-byte instructions (faster, smaller)
; Use this for variables accessed frequently (like gamepad, game variables, pointers)
.segment "ZEROPAGE"
; Zero Page Memory Map
; $00-$0F: General purpose variables and pointers
temp_var:       .res 1    ; General purpose temp variable
temp_var2:      .res 1    ; Second temp variable
temp_ptr_low:   .res 1    ; 16-bit pointer (2 bytes)
temp_ptr_high:  .res 1    ; 16-bit pointer (2 bytes)

; Reserve remaining space in this section if needed
                .res 10   ; Pad to $10 (optional - depends on your needs)

; $10-$1F: Controller input
controller_1:       .res 1    ; Current frame controller 1 state
controller_2:       .res 1    ; Current frame controller 2 state
controller_1_prev:  .res 1    ; Previous frame state for edge detection
controller_2_prev:  .res 1    ; Previous frame state for edge detection

; Reserve remaining space in this section if needed
                    .res 12   ; Pad to $20 (optional)

; $20-$2F: Game state variables
game_state:     .res 1    ; Current game state
player_x:       .res 1    ; Player X position
player_y:       .res 1    ; Player Y position
player_vel_x:   .res 1    ; Player X velocity
player_vel_y:   .res 1    ; Player Y velocity
score:          .res 1    ; Score low byte

; Reserve remaining space in this section if needed
                .res 10   ; Pad to $30 (optional)

;*****************************************************************
; OAM (Object Attribute Memory) ($0200–$02FF)
;*****************************************************************
; This 256-byte buffer holds sprite data to be copied to the PPU's
; internal OAM via DMA ($4014). Each sprite uses 4 bytes:
;   Byte 0: Y position
;   Byte 1: Tile index
;   Byte 2: Attributes (palette, flipping, priority)
;   Byte 3: X position
.segment "OAM"
oam: .res 256	; sprite OAM data

;*****************************************************************
; Code Segment (ROM)
;*****************************************************************
; Main program code section
.segment "CODE"

; Interrupt Request Handler - called when IRQ interrupt occurs
.proc irq_handler
  RTI                     ; Return from interrupt (we don't use IRQ)
.endproc

; Non-Maskable Interrupt Handler - called during VBlank
.proc nmi_handler
  RTI                     ; Return from interrupt (not using NMI yet)
.endproc

;******************************************************************************
; Procedure: set_palette
;------------------------------------------------------------------------------
; Writes 32 bytes of color data from palette_data into the PPU's palette memory
; at $3F00. This fills all 4 background palettes and all 4 sprite palettes.
;
; Assumes:
;   - palette_data is a 32-byte table in ROM.
;   - Rendering is off or you're in VBlank (writes to $2007 are safe).
;******************************************************************************
.proc set_palette

    vram_set_address PALETTE_ADDRESS  ; Set PPU VRAM pointer to $3F00 (palette memory start)

    LDX #$00                          ; Start index at 0

@loop:
    LDA palette_data, X              ; Load color byte from palette_data table
    STA PPU_VRAM_IO                  ; Write to PPU at $3F00 + X
    INX                              ; Move to next color
    CPX #$20                         ; Have we written all 32 bytes?
    BNE @loop                        ; Loop until done

    RTS                              ; Return from procedure

.endproc

;******************************************************************************
; Procedure: set_nametable
;------------------------------------------------------------------------------
; Transfers 960 bytes of tile data from `nametable_data` to the PPU's nametable 0
; at $2000. This fills the entire 32×30 background tilemap.
;
; Assumes:
;   - PPU is ready (called during or before VBlank)
;   - nametable_data is a 960-byte table in ROM
;   - $00/$01 are available as temporary zero-page pointer
;******************************************************************************
.proc set_nametable

    wait_for_vblank                        ; Wait for VBlank to safely write to PPU

    vram_set_address NAME_TABLE_0_ADDRESS  ; Set VRAM address to start of nametable ($2000)

    ; Set up 16-bit pointer to nametable_data
    LDA #<nametable_data
    STA temp_ptr_low                       ; Store low byte of address in $00
    LDA #>nametable_data
    STA temp_ptr_high                      ; Store high byte in $01

    ; Begin loading 960 bytes (32×30 tiles)
    LDY #$00                               ; Offset within current page
    LDX #$03                               ; 3 full 256-byte pages (768 bytes total)

load_page:
    LDA (temp_ptr_low),Y                            ; Load byte from nametable_data + Y
    STA PPU_VRAM_IO                        ; Write to PPU VRAM ($2007)
    INY
    BNE load_page                          ; Loop through 256-byte page

    INC temp_ptr_high                      ; Move to next page (high byte of pointer)
    DEX
    BNE load_page                           ; After 3 pages (768 bytes), handle the remaining 192

check_remaining:
    LDY #$00                               ; Reset Y to load remaining 192 bytes
remaining_loop:
    LDA (temp_ptr_low),Y
    STA PPU_VRAM_IO
    INY
    CPY #192                               ; Stop after 192 bytes (960 - 768)
    BNE remaining_loop

    ; Reset scroll registers to 0,0 (needed after VRAM access)
    LDA #$00
    STA PPU_SCROLL                         ; Write horizontal scroll
    STA PPU_SCROLL                         ; Write vertical scroll

    RTS                                    ; Done

.endproc

.proc init_sprites
  LDA #4
  STA SPRITE_0_ADDR + SPRITE_OFFSET_TILE
  LDA #5
  STA SPRITE_1_ADDR + SPRITE_OFFSET_TILE
  LDA #$14
  STA SPRITE_2_ADDR + SPRITE_OFFSET_TILE
  LDA #$15
  STA SPRITE_3_ADDR + SPRITE_OFFSET_TILE

  LDA #20
  STA player_y

  STA SPRITE_0_ADDR + SPRITE_OFFSET_Y
  STA SPRITE_1_ADDR + SPRITE_OFFSET_Y
  STA SPRITE_2_ADDR + SPRITE_OFFSET_Y
  STA SPRITE_3_ADDR + SPRITE_OFFSET_Y

  CLC
  ADC #8
  STA SPRITE_2_ADDR + SPRITE_OFFSET_Y
  STA SPRITE_3_ADDR + SPRITE_OFFSET_Y

  LDA #30
  STA player_x

  STA SPRITE_0_ADDR + SPRITE_OFFSET_X
  STA SPRITE_2_ADDR + SPRITE_OFFSET_X

  CLC
  ADC #8
  STA SPRITE_1_ADDR + SPRITE_OFFSET_X
  STA SPRITE_3_ADDR + SPRITE_OFFSET_X



  RTS
.endproc

;******************************************************************************
; Procedure: update_sprites
;------------------------------------------------------------------------------
; Transfers 256 bytes of sprite data from the OAM buffer in CPU RAM
; to the PPU's internal Object Attribute Memory (OAM) using DMA.
;
; Assumes:
;   - OAM sprite data is stored at a page-aligned label `oam` (e.g., $0200)
;   - This is called during VBlank or with rendering disabled
;******************************************************************************

.proc update_sprites
  ; Update OAM values
  LDA player_x
  STA SPRITE_0_ADDR + SPRITE_OFFSET_X
  STA SPRITE_2_ADDR + SPRITE_OFFSET_X

  CLC
  ADC #8
  STA SPRITE_1_ADDR + SPRITE_OFFSET_X
  STA SPRITE_3_ADDR + SPRITE_OFFSET_X


  LDA player_y
  STA SPRITE_0_ADDR + SPRITE_OFFSET_Y
  STA SPRITE_1_ADDR + SPRITE_OFFSET_Y

  CLC
  ADC #8
  STA SPRITE_2_ADDR + SPRITE_OFFSET_Y
  STA SPRITE_3_ADDR + SPRITE_OFFSET_Y


  ; Set OAM address to 0 — required before DMA or manual OAM writes
  LDA #$00
  STA PPU_SPRRAM_ADDRESS    ; $2003 — OAM address register

  ; Start OAM DMA transfer (copies 256 bytes from oam → PPU OAM)
  ; Write the high byte of the source address (e.g., $02 for $0200)
  LDA #>oam
  STA SPRITE_DMA            ; $4014 — triggers OAM DMA (513–514 cycles, CPU stalled)

  RTS

.endproc

.proc update_player
  LDA controller_1
  AND #PAD_L
  BEQ not_left
    LDX player_x
    DEX
    STX player_x

not_left:
  LDA controller_1
  AND #PAD_R
  BEQ not_right
    LDX player_x
    INX
    STX player_x

not_right:
  LDA controller_1
  AND #PAD_U
  BEQ not_up
    LDX player_y
    DEX
    STX player_y

not_up:
  LDA controller_1
  AND #PAD_D
  BEQ not_down
    LDX player_y
    INX
    STX player_y

not_down:
    RTS                       ; Return to caller
.endproc

;******************************************************************************
; Procedure: main
;------------------------------------------------------------------------------
; Main entry point for the game loop.
; Initializes PPU control settings, enables rendering, and enters
; an infinite loop where it waits for VBlank and updates sprite data.
;******************************************************************************
.proc main

    ;--------------------------------------------------------------------------
    ; Configure PPU Control Register ($2000)
    ; - Enable NMI on VBlank (bit 7 = 1)
    ; - Use pattern table 1 ($1000) for background tiles (bit 4 = 1)
    ;--------------------------------------------------------------------------
    LDA #(PPUCTRL_ENABLE_NMI | PPUCTRL_BG_TABLE_1000)
    STA PPU_CONTROL

    ;--------------------------------------------------------------------------
    ; Configure PPU Mask Register ($2001)
    ; - Show background and sprites (bits 3 & 4 = 1)
    ; - Show background and sprites in leftmost 8 pixels (bits 1 & 2 = 1)
    ;--------------------------------------------------------------------------
    LDA #(PPUMASK_SHOW_BG | PPUMASK_SHOW_SPRITES | PPUMASK_SHOW_BG_LEFT | PPUMASK_SHOW_SPRITES_LEFT)
    STA PPU_MASK

forever:
    ; Wait for vertical blank before doing game logic and rendering updates
    wait_for_vblank

    ; Read controller
    JSR read_controller
    JSR update_player

    ; Update sprite data (DMA transfer to PPU OAM)
    JSR update_sprites

    ; Infinite loop — keep running frame logic
    JMP forever

.endproc

; ------------------------------------------------------------------------------
; Procedure: read_controller
; Purpose:   Reads the current state of NES Controller 1 and stores the button
;            states as a bitfield in the `controller_1` variable.
;
;            The routine strobes the controller to latch the current button
;            state, then reads each of the 8 button states (A, B, Select, Start,
;            Up, Down, Left, Right) serially from the controller port at $4016.
;            The result is built bit-by-bit into the `controller_1` variable
;            using ROL to construct the byte from right to left.
;
; Notes:     The final layout of bits in `controller_1` will be:
;            Bit 0 = A, Bit 1 = B, Bit 2 = Select, Bit 3 = Start,
;            Bit 4 = Up, Bit 5 = Down, Bit 6 = Left, Bit 7 = Right
; ------------------------------------------------------------------------------
.proc read_controller

  ; save current controller state into previous controller state
  LDA controller_1
  STA controller_1_prev

  ; Read controller state
  ; Controller 1 is at $4016 (controller 2 at $4017)
  LDA #$01
  STA JOYPAD1       ; Strobe joypad - write 1 to latch current button state
                    ; This tells the controller to capture the current button presses
  LDA #$00
  STA JOYPAD1       ; End strobe - write 0 to begin serial data output
                    ; Controller is now ready to send button data one bit at a time
                    ; Next 8 reads from JOYPAD1 will return buttons in sequence

  LDX #$08          ; Set loop counter to 8 (read 8 buttons)

read_loop:
   LDA JOYPAD1       ; Read one bit from joypad ($4016)
                     ; Returns $00 (not pressed) or $01 (pressed)
   LSR A             ; Shift accumulator right - bit 0 goes to carry flag
                     ; If button pressed: carry = 1, if not: carry = 0
   ROL controller_1  ; Rotate controller_1 left through carry
                     ; Shifts previous bits left, adds new bit from carry to bit 0
                     ; Building result byte from right to left
   DEX               ; Decrement loop counter (started at 8)
   BNE read_loop     ; Branch if X != 0 (still have bits to read)
                     ; Loop reads: A, B, Select, Start, Up, Down, Left, Right
                     ; Final controller_1 format: RLDUTSBA
                     ; (R=Right, L=Left, D=Down, U=Up, T=sTart, S=Select, B=B, A=A)

    ; Now controller_1 contains the button state
    ; Bit 0 = A, Bit 1 = B, Bit 2 = Select, etc.

    RTS

.endproc


;*****************************************************************
; Character ROM data (graphics patterns)
;*****************************************************************
.segment "CHARS"
; Load CHR data
  .incbin "assets/tiles.chr"

;*****************************************************************
; Character ROM data (graphics patterns)
;*****************************************************************
.segment "RODATA"
; Load palette data
palette_data:
  .incbin "assets/palette.pal"
; Load nametable data
nametable_data:
  .incbin "assets/screen.nam"

; Startup segment
.segment "STARTUP"

; Reset Handler - called when system starts up or resets
.proc reset_handler
  ; === CPU Initialization ===
  SEI                     ; Set interrupt disable flag (ignore IRQ)
  CLD                     ; Clear decimal mode flag (NES doesn't support BCD)

  ; === APU Initialization ===
  LDX #$40                ; Load X with $40
  STX $4017               ; Write to APU Frame Counter register
                          ; Disables APU frame IRQ

  ; === Stack Initialization ===
  LDX #$FF                ; Load X with $FF (top of stack page)
  TXS                     ; Transfer X to Stack pointer ($01FF)

  ; === PPU Initialization ===
  LDA #$00                ; Set A = $00
  STA PPU_CONTROL         ; PPUCTRL = 0 (disable NMI, sprites, background)
  STA PPU_MASK            ; PPUMASK = 0 (disable rendering)
  STA APU_DM_CONTROL      ; disable DMC IRQ

  ; First VBlank wait - PPU needs time to stabilize
:                         ; Anonymous label (used to branch to in BPL command)
  BIT PPU_STATUS          ; Read PPUSTATUS register
  BPL :-                  ; Branch if Plus (bit 7 = 0, no VBlank)
                          ; Loop until VBlank flag is set

  ;clear_ram
  clear_oam oam

  ; Second VBlank wait - ensures PPU is fully ready
:                         ; Anonymous label (used to branch to in BPL command)
  BIT PPU_STATUS          ; Read PPUSTATUS register again
  BPL :-                  ; Branch if Plus (bit 7 = 0, no VBlank)
                          ; Loop until second VBlank occurs

  JSR set_palette         ; Set palette colors
  JSR set_nametable       ; Set nametable tiles
  JSR init_sprites        ; Initialize sprites

  JMP main                ; Jump to main program
.endproc
