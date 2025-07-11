.include "nes.inc"
.include "macros.inc"

SPRITE_0_ADDR = oam + 0
SPRITE_1_ADDR = oam + 4
SPRITE_2_ADDR = oam + 8
SPRITE_3_ADDR = oam + 12
SPRITE_Ball_ADDR = oam + 16
SPRITE_Bullet1_ADDR = oam + 20
SPRITE_Bullet2_ADDR = oam + 24
SPRITE_Bullet3_ADDR = oam + 28
SPRITE_Bounce_ADDR = oam + 32

;*****************************************************************
; Define NES cartridge Header
;*****************************************************************
; NES ROM Header - tells emulator/hardware about the ROM
.segment "HEADER"
.byte 'N', 'E', 'S', $1a      ; "NES" followed by MS-DOS EOF marker
.byte $02                     ; 2 x 16KB PRG-ROM banks
.byte $01                     ; 1 x 8KB CHR-ROM bank
.byte $01, $00                ; Mapper 0, no special features

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
temp_var:               .res 1    ; General purpose temp variable
temp_var2:              .res 1    ; Second temp variable
temp_ptr_low:           .res 1    ; 16-bit pointer (2 bytes)
temp_ptr_high:          .res 1    ; 16-bit pointer (2 bytes)
random_num:             .res 1    ; Random number generator value

; Reserve remaining space in this section if needed
                        .res 11   ; Pad to $10 (optional - depends on your needs)

; $10-$1F: Controller input
controller_1:           .res 1    ; Current frame controller 1 state
controller_2:           .res 1    ; Current frame controller 2 state
controller_1_prev:      .res 1    ; Previous frame state for edge detection
controller_2_prev:      .res 1    ; Previous frame state for edge detection
controller_1_pressed:   .res 1    ; Check if pressed
controller_1_released:  .res 1    ; Check if released

; Reserve remaining space in this section if needed
                        .res 10   ; Pad to $20 (optional)

; $20-$2F: Game state variables
game_state:             .res 1    ; Current game state
player_x:               .res 1    ; Player X position
player_y:               .res 1    ; Player Y position
player_vel:             .res 1    ; Player Y velocity
score:                  .res 1    ; Score low byte
scroll:                 .res 1    ; Scroll screen
time:                   .res 1    ; Time (60hz = 60 FPS)
seconds:                .res 1    ; Seconds
scene:                  .res 1
start_text_drawn:       .res 1
con_bounce:             .res 1
show_bounce_sprite:     .res 1
;
ball_pos_x:             .res 1
ball_pos_y:             .res 1
ball_vel_x:             .res 1
ball_vel_y:             .res 1
ball_acc_x:             .res 1
ball_acc_y:             .res 1
gravity:                .res 1
frame_counter:          .res 1
ball_max_speed:         .res 1
ball_min_speed:         .res 1
;
bullet_speed:           .res 1
bullet_max_distance:    .res 1
b1_x:                   .res 1
b1_y:                   .res 1
b1_d:                   .res 1
b2_x:                   .res 1
b2_y:                   .res 1
b2_d:                   .res 1
b3_x:                   .res 1
b3_y:                   .res 1
b3_d:                   .res 1
; Reserve remaining space in this section if needed
                        .res 07   ; Pad to $30 (optional)

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
PHA
TXA
PHA
TYA
PHA

INC time
LDA time
CMP #60
BNE skip
INC seconds
LDA #0
STA time

skip:

PLA
TAY
PLA
TAX
PLA

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

  ; set text location
 	LDA PPU_STATUS ; reset address latch
 	LDA #$20 ; set PPU address to $208A (Row = 4, Column = 10)
 	STA PPU_ADDRESS
 	LDA #$8A
 	STA PPU_ADDRESS

  ; Reset scroll registers to 0,0 (needed after VRAM access)
  LDA #$00
  STA PPU_SCROLL                         ; Write horizontal scroll
  STA PPU_SCROLL                         ; Write vertical scroll

  RTS                                    ; Done

.endproc

  ; print text
  ; draw some text on the screen
PPU_ADDR = $2006
PPU_DATA = $2007
.proc write_start_text
  ; Draw title_txt at $208A (row 4, col 10)
  LDA #$20          ; high byte for $208A
  STA $2006
  LDA #$8A          ; low byte
  STA $2006

  LDX #0
write_title_loop:
  LDA title_txt, X
  CMP #0
  BEQ write_start_line
  STA $2007
  INX
  JMP write_title_loop

write_start_line:
  ; Draw start_txt at $20C3 (row 6, col 11)
  LDA #$20          ; high byte for $20C3
  STA $2006
  LDA #$C3          ; low byte
  STA $2006

  LDX #0
write_start_loop:
  LDA start_txt, X
  CMP #0
  BEQ done
  STA $2007
  INX
  JMP write_start_loop

done:
  RTS
.endproc



.proc init_sprites

  LDX #0
  load_sprite:

    LDA sprite_data, X
    STA SPRITE_0_ADDR, X

    INX
    CPX #4
    BNE load_sprite


  ; set sprite tiles
  LDA #1
  STA SPRITE_0_ADDR + SPRITE_OFFSET_TILE
  LDA #2
  STA SPRITE_1_ADDR + SPRITE_OFFSET_TILE
  LDA #3
  STA SPRITE_2_ADDR + SPRITE_OFFSET_TILE
  LDA #4
  STA SPRITE_3_ADDR + SPRITE_OFFSET_TILE
  LDA #6
  STA SPRITE_Ball_ADDR + SPRITE_OFFSET_TILE
  LDA #5
  STA SPRITE_Bullet1_ADDR + SPRITE_OFFSET_TILE
  LDA #5
  STA SPRITE_Bullet2_ADDR + SPRITE_OFFSET_TILE
  LDA #5
  STA SPRITE_Bullet3_ADDR + SPRITE_OFFSET_TILE

  RTS
.endproc

.proc init_gamedata
  ;player
  LDA #124
  STA player_x

  LDA #190
  STA player_y

  LDA #3
  STA player_vel

  ;ball
  LDA #128
  STA ball_pos_x

  LDA #20
  STA ball_pos_y

  LDA #01
  STA gravity

  LDA #07
  STA ball_max_speed

  LDA #4
  STA bullet_speed

  LDA #40
  STA bullet_max_distance

  LDA bullet_max_distance
  STA b1_d
  STA b2_d
  STA b3_d

  ; calculate two's complement: ball_min_speed = -ball_max_speed

LDA ball_max_speed
EOR #$FF       ; invert bits
CLC
ADC #1         ; add 1 → two's complement
STA ball_min_speed



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

  LDA ball_pos_x
  STA SPRITE_Ball_ADDR + SPRITE_OFFSET_X

  LDA ball_pos_y
  STA SPRITE_Ball_ADDR + SPRITE_OFFSET_Y

  LDA #$00
  STA PPU_SCROLL                         ; Write horizontal scroll
  ;DEC scroll
  ;LDA scroll
  STA PPU_SCROLL                         ; Write vertical scroll

  ; ---- Bullet 1 ----
  LDA b1_d
  CMP bullet_max_distance
  BCS hide_b1_sprite    ; if expired, move offscreen

  ; Draw active sprite
  LDA b1_x
  STA SPRITE_Bullet1_ADDR + SPRITE_OFFSET_X

  LDA b1_y
  STA SPRITE_Bullet1_ADDR + SPRITE_OFFSET_Y
  JMP skip_b1_draw

hide_b1_sprite:
  LDA #240
  STA SPRITE_Bullet1_ADDR + SPRITE_OFFSET_Y  ; offscreen
skip_b1_draw:


  ; ---- Bullet 2 ----
  LDA b2_d
  CMP bullet_max_distance
  BCS hide_b2_sprite

  LDA b2_x
  STA SPRITE_Bullet2_ADDR + SPRITE_OFFSET_X

  LDA b2_y
  STA SPRITE_Bullet2_ADDR + SPRITE_OFFSET_Y
  JMP skip_b2_draw

hide_b2_sprite:
  LDA #240
  STA SPRITE_Bullet2_ADDR + SPRITE_OFFSET_Y
skip_b2_draw:


  ; ---- Bullet 3 ----
  LDA b3_d
  CMP bullet_max_distance
  BCS hide_b3_sprite

  LDA b3_x
  STA SPRITE_Bullet3_ADDR + SPRITE_OFFSET_X

  LDA b3_y
  STA SPRITE_Bullet3_ADDR + SPRITE_OFFSET_Y
  JMP skip_b3_draw

hide_b3_sprite:
  LDA #240
  STA SPRITE_Bullet3_ADDR + SPRITE_OFFSET_Y
skip_b3_draw:




LDA show_bounce_sprite
  BEQ skip_bounce_sprite

  ; leave sprite as-is this frame
  LDA #0
  STA show_bounce_sprite

  JMP done_bounce_sprite

skip_bounce_sprite:
  ; erase it by moving it offscreen
  LDA #240
  STA SPRITE_Bounce_ADDR + SPRITE_OFFSET_Y

done_bounce_sprite:


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
      LDA player_x
      ;DEX
      SEC
      SBC player_vel
      STA player_x
not_left:
    LDA controller_1
    AND #PAD_R
    BEQ not_right
      LDA player_x
      CLC
      ADC player_vel
      STA player_x
  not_right:
    LDA controller_1
    AND #PAD_U
    BEQ not_up
      LDA player_y
      SEC
      SBC player_vel
      STA player_y
  not_up:
    LDA controller_1
    AND #PAD_D
    BEQ not_down
      LDA player_y
      CLC
      ADC player_vel
      STA player_y
  not_down:
    RTS                       ; Return to caller
.endproc

.proc shoot_bullets

; Check if START is newly pressed
  LDA controller_1
  AND #PAD_START
  BEQ skip_fire_weapon        ; if not pressed now, skip

  LDA controller_1_prev
  AND #PAD_START
  BNE skip_fire_weapon        ; if it was already pressed last frame, skip

LDA b1_d
CMP bullet_max_distance
BCC skip_b1_active_shootable

    LDA #0
    STA b1_d
    LDA player_x
    CLC
    ADC #3
    STA b1_x
    LDA player_y
    STA b1_y

  JMP skip_fire_weapon

skip_b1_active_shootable:

LDA b2_d
CMP bullet_max_distance
BCC skip_b2_active_shootable

    LDA #0
    STA b2_d
    LDA player_x
    CLC
    ADC #3
    STA b2_x
    LDA player_y
    STA b2_y

  JMP skip_fire_weapon

skip_b2_active_shootable:

LDA b3_d
CMP bullet_max_distance
BCC skip_b3_active_shootable

    LDA #0
    STA b3_d
    LDA player_x
    CLC
    ADC #3
    STA b3_x
    LDA player_y
    STA b3_y

  JMP skip_fire_weapon

skip_b3_active_shootable:

shoot_blank:
; show blank image for a second

skip_fire_weapon:



  RTS
.endproc

.proc update_bullets

  JSR shoot_bullets

; ---------------------------
; BULLET 1
; ---------------------------

  LDA b1_d
  CMP bullet_max_distance
  BCS skip_b1_active_phys

  INC b1_d
  LDA b1_y
  SEC
  SBC bullet_speed
  STA b1_y

  ; --- AABB Collision: b1 <-> ball ---
  LDA b1_x
  CLC
  ADC #8
  CMP ball_pos_x
  BCC b1_no_collision

  LDA ball_pos_x
  CLC
  ADC #8
  CMP b1_x
  BCC b1_no_collision

  LDA b1_y
  CLC
  ADC #8
  CMP ball_pos_y
  BCC b1_no_collision

  LDA ball_pos_y
  CLC
  ADC #8
  CMP b1_y
  BCC b1_no_collision

  ; if we passed all checks:
  JSR punch_ball_upwards
  LDA bullet_max_distance
  STA b1_d

b1_no_collision:
skip_b1_active_phys:


; ---------------------------
; BULLET 2
; ---------------------------

  LDA b2_d
  CMP bullet_max_distance
  BCS skip_b2_active_phys

  INC b2_d
  LDA b2_y
  SEC
  SBC bullet_speed
  STA b2_y

  ; --- AABB Collision: b2 <-> ball ---
  LDA b2_x
  CLC
  ADC #8
  CMP ball_pos_x
  BCC b2_no_collision

  LDA ball_pos_x
  CLC
  ADC #8
  CMP b2_x
  BCC b2_no_collision

  LDA b2_y
  CLC
  ADC #8
  CMP ball_pos_y
  BCC b2_no_collision

  LDA ball_pos_y
  CLC
  ADC #8
  CMP b2_y
  BCC b2_no_collision

  ; collision!
  JSR punch_ball_upwards
  LDA bullet_max_distance
  STA b2_d

b2_no_collision:
skip_b2_active_phys:


; ---------------------------
; BULLET 3
; ---------------------------

  LDA b3_d
  CMP bullet_max_distance
  BCS skip_b3_active_phys

  INC b3_d
  LDA b3_y
  SEC
  SBC bullet_speed
  STA b3_y

  ; --- AABB Collision: b3 <-> ball ---
  LDA b3_x
  CLC
  ADC #8
  CMP ball_pos_x
  BCC b3_no_collision

  LDA ball_pos_x
  CLC
  ADC #8
  CMP b3_x
  BCC b3_no_collision

  LDA b3_y
  CLC
  ADC #8
  CMP ball_pos_y
  BCC b3_no_collision

  LDA ball_pos_y
  CLC
  ADC #8
  CMP b3_y
  BCC b3_no_collision

  ; collision!
  JSR punch_ball_upwards
  LDA bullet_max_distance
  STA b3_d

b3_no_collision:
skip_b3_active_phys:

  RTS
.endproc

.proc score_points
  INC con_bounce
  JSR show_bounce_score_sprite

  RTS
.endproc

.proc show_bounce_score_sprite
  LDA con_bounce       ; load current bounce count (0–9 for now)
  CLC
  ADC #'0'             ; convert to ASCII tile number (e.g., 0 → tile index for '0')
  STA SPRITE_Bounce_ADDR + SPRITE_OFFSET_TILE

  ; Optional: place it relative to ball
  LDA ball_pos_x
  CLC
  ADC #12              ; offset right
  STA SPRITE_Bounce_ADDR + SPRITE_OFFSET_X

  LDA ball_pos_y
  CLC
  ADC #12              ; offset down
  STA SPRITE_Bounce_ADDR + SPRITE_OFFSET_Y

  ; Optional: set palette and visibility
  LDA #%00000000       ; palette 0, no flipping
  STA SPRITE_Bounce_ADDR + SPRITE_OFFSET_ATTRIB

  RTS
.endproc



.proc punch_ball_upwards


  LDA bullet_speed
  EOR #$FF   ; bitwise NOT (invert)
  CLC
  ADC #1     ; +1 to complete two's complement = -bullet_speed
  STA ball_vel_y
  JSR score_points

  JSR nudge_ball_x


  RTS
.endproc

.proc nudge_ball_x
  JSR get_random        ; updates random_num
  LDA random_num
  AND #%00000011        ; mask to 0–3

  CMP #0
  BEQ set_neg_one

  CMP #1
  BEQ set_zero

  CMP #2
  BEQ set_pos_one

  ; If 3 → do nothing
  RTS

set_neg_one:
  LDA #$FF              ; -1 in two's complement
  STA ball_vel_x
  RTS

set_zero:
  LDA #0
  STA ball_vel_x
  RTS

set_pos_one:
  LDA #1
  STA ball_vel_x
  RTS

.endproc



.proc update_ball_gravity

; Increment frame counter
  LDA frame_counter
  CLC
  ADC #1
  CMP #4       ; Compare to 4
  BNE no_reset
  LDA #0       ; Reset counter to 0
no_reset:
  STA frame_counter

  ; Check if frame_counter == 0 (every 4th frame)
  LDA frame_counter
  BEQ apply_gravity
  JMP end_update

apply_gravity:
  ; Apply gravity
  LDA ball_acc_y
  CLC
  ADC gravity
  STA ball_acc_y

end_update:

RTS

.endproc

.proc update_ball

  ; Apply gravity
  JSR update_ball_gravity

  ; Apply input to ball_acc_x
  LDA controller_1
  AND #PAD_B
  BEQ skip_left
    LDA ball_acc_x
    SEC
    SBC #1
    STA ball_acc_x
skip_left:

  LDA controller_1
  AND #PAD_A
  BEQ skip_right
    LDA ball_acc_x
    CLC
    ADC #1
    STA ball_acc_x
skip_right:

  ; Update velocity X
  LDA ball_vel_x
  CLC
  ADC ball_acc_x
  STA ball_vel_x

  ; Clamp X velocity between -max and +max
  LDA ball_vel_x
  BMI clamp_x_low
  CMP ball_max_speed
  BCC skip_clamp_x
    LDA ball_max_speed
    STA ball_vel_x
    JMP skip_clamp_x

clamp_x_low:
  CMP ball_min_speed
  BCS skip_clamp_x
    LDA ball_min_speed
    STA ball_vel_x

skip_clamp_x:

  ; Update position X
  LDA ball_pos_x
  CLC
  ADC ball_vel_x
  STA ball_pos_x

  ; WALL COLLISION X
  CMP #0
  BNE check_right_wall
    LDA ball_vel_x
    EOR #$FF    ; flip sign
    CLC
    ADC #1
    STA ball_vel_x
check_right_wall:
  LDA ball_pos_x
  CMP #248
  BCC skip_wall_x
    LDA ball_vel_x
    EOR #$FF
    CLC
    ADC #1
    STA ball_vel_x
skip_wall_x:

  ; Update velocity Y
  LDA ball_vel_y
  CLC
  ADC ball_acc_y
  STA ball_vel_y

  ; Clamp Y velocity between -max and +max
  LDA ball_vel_y
  BMI clamp_y_low
  CMP ball_max_speed
  BCC skip_clamp_y
    LDA ball_max_speed
    STA ball_vel_y
    JMP skip_clamp_y

clamp_y_low:
  CMP ball_min_speed
  BCS skip_clamp_y
    LDA ball_min_speed
    STA ball_vel_y

skip_clamp_y:

  ; Update position Y
  LDA ball_pos_y
  CLC
  ADC ball_vel_y
  STA ball_pos_y

  ; WALL COLLISION Y
  CMP #0
  BNE check_bottom_wall
    LDA ball_vel_y
    EOR #$FF
    CLC
    ADC #1
    STA ball_vel_y
check_bottom_wall:
  LDA ball_pos_y
  CMP #210
  BCC skip_wall_y
    ; Instead of bouncing, call reach_bottom to reset position
    JSR reach_bottom
skip_wall_y:

  ; Reset acceleration
  LDA #0
  STA ball_acc_x
  STA ball_acc_y

  RTS
.endproc

.proc reach_bottom

  ; Reset position Y to top (0)
  LDA #0
  STA ball_pos_y

  ; Reset vertical velocity
  LDA #0
  STA ball_vel_y

  RTS

.endproc

.proc open_start_menu
  LDA start_text_drawn
  CMP #0
  BNE skip_draw

  ; Disable rendering before VRAM writes
  LDA #$00
  STA PPU_MASK

  JSR write_start_text

  ; Enable rendering again (background + sprites + left 8 pixels)
  LDA #(PPUMASK_SHOW_BG | PPUMASK_SHOW_SPRITES | PPUMASK_SHOW_BG_LEFT | PPUMASK_SHOW_SPRITES_LEFT)
  STA PPU_MASK

  LDA #1
  STA start_text_drawn

skip_draw:
  RTS
.endproc

.proc clear_start_text
  ; Clear title_txt line (11 chars) at $208A
  LDA #$20
  STA $2006
  LDA #$8A
  STA $2006

  LDX #11
clear_title_loop:
  LDA #$20
  STA $2007
  DEX
  BNE clear_title_loop

  ; Clear start_txt line (10 chars) at $20C3
  LDA #$20
  STA $2006
  LDA #$C3
  STA $2006

  LDX #10
clear_start_loop:
  LDA #$20
  STA $2007
  DEX
  BNE clear_start_loop

  RTS
.endproc




;******************************************************************************
; Procedure: main
;------------------------------------------------------------------------------
; Main entry point for the game loop.
; Initializes PPU control settings, enables rendering, and enters
; an infinite loop where it waits for VBlank and updates sprite data.
;******************************************************************************
.proc main
    ; seed the random number
    LDA #$45
    STA random_num

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
    JSR get_random
    wait_for_vblank
    JSR read_controller

    ; Always update and draw player, ball, bullets (even in scene 0)
    JSR update_player
    JSR update_bullets
    JSR update_ball

    ; Update sprites in OAM (draw all sprites: player, ball, bullets)
    JSR update_sprites

    ; Handle scene logic
    LDA scene
    CMP #0
    BNE not_scene_0

      ; Scene 0 - start menu

      ; If not drawn yet, draw start text once
      LDA start_text_drawn
      CMP #0
      BNE skip_draw_start_text

      ; Disable rendering before VRAM writes
      LDA #$00
      STA PPU_MASK
      JSR write_start_text
      ; Enable rendering again
      LDA #(PPUMASK_SHOW_BG | PPUMASK_SHOW_SPRITES | PPUMASK_SHOW_BG_LEFT | PPUMASK_SHOW_SPRITES_LEFT)
      STA PPU_MASK

      LDA #1
      STA start_text_drawn

    skip_draw_start_text:

      ; Wait for START press to advance scene
      LDA controller_1
      AND #PAD_START
      BEQ not_scene_0  ; START not pressed, keep waiting

      ; START pressed, clear start text
      LDA #$00
      STA PPU_MASK
      JSR clear_start_text
      LDA #(PPUMASK_SHOW_BG | PPUMASK_SHOW_SPRITES | PPUMASK_SHOW_BG_LEFT | PPUMASK_SHOW_SPRITES_LEFT)
      STA PPU_MASK

      INC scene
      LDA #0
      STA start_text_drawn

    not_scene_0:

    ; Scene 1+ gameplay already updated by update_player etc.

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

; -----------------------------------------------------
; 8-bit Pseudo-Random Number Generator using LFSR-like bit mixing
; - Uses 'random_num' to hold and update the current pseudo-random value
; - 'temp' is used as a scratch byte
; - The routine generates a new random number in 'random_num' on each call
; -----------------------------------------------------
get_random:
    LDA random_num      ; Load current random value

    ; Test if we need to apply the feedback polynomial
    ; We check bit 7 (sign bit) - if set, we'll XOR with the tap pattern
    ASL                 ; Shift left, bit 7 -> Carry, bit 0 <- 0
    BCC no_feedback     ; If carry clear (original bit 7 was 0), skip XOR

    ; Apply feedback: XOR with $39 (binary: 00111001)
    ; This represents taps at positions 5,4,3,0 after the shift
    EOR #$39           ; XOR with tap pattern

no_feedback:
    STA random_num      ; Store new random value
    RTS                 ; Return with new random value in A

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

sprite_data:
.byte 30, 1, 0, 40
.byte 30, 2, 0, 48
.byte 38, 3, 0, 40
.byte 38, 4, 0, 48

start_txt:
.byte 'S', 'T', 'A', 'R', 'T' ,' ', 'G', 'A', 'M', 'E', 0

title_txt:
.byte 'R', 'O', 'C', 'K', 'E', 'T' ,'O', 'C', 'K', 'Y', '!', 0



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

  ; clear_ram
  clear_oam oam

  ; Second VBlank wait - ensures PPU is fully ready
:                         ; Anonymous label (used to branch to in BPL command)
  BIT PPU_STATUS          ; Read PPUSTATUS register again
  BPL :-                  ; Branch if Plus (bit 7 = 0, no VBlank)
                          ; Loop until second VBlank occurs

  JSR set_palette         ; Set palette colors
  JSR set_nametable       ; Set nametable tiles
  JSR init_sprites        ; Initialize sprites
  JSR init_gamedata

  JMP main                ; Jump to main program
.endproc
