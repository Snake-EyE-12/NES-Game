;===============================================================================
; NES PONG GAME - Educational Version
;===============================================================================
; This is a complete Pong game for the Nintendo Entertainment System (NES)
; Written in 6502 assembly language for educational purposes
;
; GAME FEATURES:
; - Two player paddles controlled by gamepads
; - Ball bounces off walls and paddles
; - Score tracking for both players
; - Simple collision detection
;
; CONTROLS:
; - Player 1: D-pad Up/Down to move left paddle
; - Player 2: D-pad Up/Down to move right paddle
; - Start button: Reset ball position
;===============================================================================

; Include NES hardware definitions and useful macros
.include "nes.inc"    ; NES hardware register definitions
.include "macros.inc" ; Useful assembly macros

; Define sprite memory locations for easy access
SPRITE_PLAYER0_ADDR = oam + 0      ; Player 1 paddle sprite data starts here
SPRITE_PLAYER1_ADDR = oam + $10    ; Player 2 paddle sprite data starts here
SPRITE_BALL_ADDR    = oam + $20    ; Ball sprite data starts here

;===============================================================================
; NES CARTRIDGE HEADER
;===============================================================================
; This header tells the NES (or emulator) important information about the ROM
.segment "HEADER"
.byte 'N', 'E', 'S', $1a      ; "NES" signature followed by MS-DOS EOF marker
.byte $02                     ; 2 x 16KB PRG-ROM banks (32KB total program space)
.byte $01                     ; 1 x 8KB CHR-ROM bank (graphics data)
.byte $01, $00                ; Mapper 0 (NROM), no special features

;===============================================================================
; INTERRUPT VECTORS
;===============================================================================
; These tell the CPU where to jump when specific events occur
.segment "VECTORS"
.addr nmi_handler         ; NMI (Non-Maskable Interrupt) - called 60 times per second
.addr reset_handler       ; RESET - called when system starts up
.addr irq_handler         ; IRQ (Interrupt Request) - not used in this game

;===============================================================================
; ZERO PAGE MEMORY ($0000–$00FF)
;===============================================================================
; Zero page is the fastest memory on the NES - instructions using it are
; smaller and faster than regular RAM. Use it for frequently accessed variables.
.segment "ZEROPAGE"

;--- General Purpose Variables ($00-$0F) ---
temp_var:               .res 1    ; Temporary variable for calculations
temp_var2:              .res 1    ; Second temporary variable
temp_ptr_low:           .res 1    ; Low byte of 16-bit pointer
temp_ptr_high:          .res 1    ; High byte of 16-bit pointer
random_num:             .res 1    ; Current random number for ball direction
nmi_ready:              .res 1    ; Flag: 1=update PPU, 2=turn off rendering
ppu_ctl0:               .res 1    ; PPU Control Register value
ppu_ctl1:               .res 1    ; PPU Mask Register value
                        .res 11   ; Reserved space

;--- Controller Input ($10-$1F) ---
controller_1:           .res 1    ; Current frame controller 1 button states
controller_1_prev:      .res 1    ; Previous frame controller 1 states
controller_1_pressed:   .res 1    ; Buttons pressed this frame (edge detection)
controller_1_released:  .res 1    ; Buttons released this frame

controller_2:           .res 1    ; Current frame controller 2 button states
controller_2_prev:      .res 1    ; Previous frame controller 2 states
controller_2_pressed:   .res 1    ; Buttons pressed this frame
controller_2_released:  .res 1    ; Buttons released this frame
                        .res 8    ; Reserved space

;--- Game State Variables ($20-$2F) ---
game_state:             .res 1    ; Current game state (not used in this version)
player1_score:          .res 1    ; Player 1's current score
player2_score:          .res 1    ; Player 2's current score
ball_dx:                .res 1    ; Ball's X velocity (-1 = left, +1 = right)
ball_dy:                .res 1    ; Ball's Y velocity (-1 = up, +1 = down)
scroll:                 .res 1    ; Screen scrolling position (not used)
time:                   .res 1    ; Frame counter incremented each NMI
prev_time:              .res 1    ; Previous frame's time value
frame_counter:          .res 1    ; Counts frames for seconds timer
seconds:                .res 1    ; Seconds elapsed (not displayed)
                        .res 6    ; Reserved space

;--- Collision Detection Variables ($30-$3F) ---
; These variables store the position and size of objects for collision testing
cx1:                    .res 1    ; Object 1 X position
cy1:                    .res 1    ; Object 1 Y position
cw1:                    .res 1    ; Object 1 width
ch1:                    .res 1    ; Object 1 height

cx2:                    .res 1    ; Object 2 X position
cy2:                    .res 1    ; Object 2 Y position
cw2:                    .res 1    ; Object 2 width
ch2:                    .res 1    ; Object 2 height

;===============================================================================
; SPRITE DATA (OAM - Object Attribute Memory)
;===============================================================================
; This 256-byte buffer holds sprite data that gets copied to the PPU each frame
; Each sprite uses 4 bytes: Y position, Tile index, Attributes, X position
.segment "OAM"
oam: .res 256             ; Buffer for all sprite data (64 sprites max)

;===============================================================================
; MAIN PROGRAM CODE
;===============================================================================
.segment "CODE"

;-------------------------------------------------------------------------------
; IRQ Handler - Interrupt Request Handler
;-------------------------------------------------------------------------------
; Called when an IRQ interrupt occurs (we don't use IRQ interrupts in this game)
.proc irq_handler
  RTI                     ; Return from interrupt immediately
.endproc

;-------------------------------------------------------------------------------
; NMI Handler - Non-Maskable Interrupt Handler
;-------------------------------------------------------------------------------
; This is called automatically 60 times per second during VBlank
; VBlank is the only safe time to update graphics on the NES
.proc nmi_handler
  ; Save all CPU registers on the stack (good practice in interrupt handlers)
  PHA                     ; Push Accumulator onto stack
  TXA                     ; Transfer X to Accumulator
  PHA                     ; Push X (via A) onto stack
  TYA                     ; Transfer Y to Accumulator
  PHA                     ; Push Y (via A) onto stack

  ; Update game timing
  INC time                ; Increment frame counter each NMI (60 Hz)

  ; Update seconds timer (60 frames = 1 second)
  INC frame_counter       ; Increment frame counter
  LDA frame_counter       ; Load current frame count
  CMP #60                 ; Compare with 60 (1 second at 60 FPS)
  BNE skip_second_update  ; If not 60, skip second update
    INC seconds           ; Increment seconds counter
    LDA #0                ; Reset frame counter to 0
    STA frame_counter
  skip_second_update:

  ; Transfer sprite data to PPU using DMA (Direct Memory Access)
  ; This is much faster than copying sprites individually
  BIT PPU_STATUS          ; Read PPU status to reset address latch
  LDA #>oam               ; Load high byte of OAM buffer address
  STA SPRITE_DMA          ; Trigger DMA transfer ($4014)
                          ; Hardware automatically copies 256 bytes from $0200-$02FF

  ; Restore CPU registers from stack (in reverse order)
  PLA                     ; Pull Y from stack
  TAY                     ; Transfer A to Y
  PLA                     ; Pull X from stack
  TAX                     ; Transfer A to X
  PLA                     ; Pull original A from stack

  RTI                     ; Return from interrupt
.endproc

;-------------------------------------------------------------------------------
; Reset Handler - System Initialization
;-------------------------------------------------------------------------------
; This code runs when the NES is turned on or reset
; It initializes all hardware and prepares the system for the game
.proc reset_handler
  ;=== CPU Initialization ===
  SEI                                 ; Set Interrupt Disable flag (ignore IRQ)
  CLD                                 ; Clear Decimal mode (NES doesn't use BCD math)

  ;=== APU (Audio Processing Unit) Initialization ===
  LDX #$40                            ; Load X with $40
  STX $4017                           ; Write to APU Frame Counter register
                                      ; This disables APU frame interrupts

  ;=== Stack Pointer Initialization ===
  LDX #$FF                            ; Load X with $FF (top of stack)
  TXS                                 ; Transfer X to Stack pointer
                                      ; Stack now points to $01FF

  ;=== PPU (Picture Processing Unit) Initialization ===
  LDA #$00                            ; Load A with 0
  STA PPU_CONTROL                     ; PPUCTRL = 0 (disable NMI, rendering off)
  STA PPU_MASK                        ; PPUMASK = 0 (disable all rendering)
  STA APU_DM_CONTROL                  ; Disable DMC (Delta Modulation Channel) IRQ

  ;=== Wait for PPU to stabilize ===
  ; The PPU needs time to warm up after power-on
  ; We must wait for 2 VBlank periods before using it

  ; First VBlank wait
wait_first_vblank:
  BIT PPU_STATUS                      ; Read PPU status register
  BPL wait_first_vblank               ; Branch if Plus (bit 7 = 0, no VBlank yet)
                                      ; Loop until VBlank flag is set

  ;=== Clear RAM ===
  ; Clear the OAM (sprite) buffer to ensure clean startup
  clear_oam oam                       ; Macro to clear sprite memory

  ; Second VBlank wait (ensures PPU is fully ready)
wait_second_vblank:
  BIT PPU_STATUS                      ; Read PPU status register again
  BPL wait_second_vblank              ; Branch if Plus (bit 7 = 0, no VBlank yet)
                                      ; Loop until second VBlank occurs

  ;=== Initialize Game Graphics ===
  JSR set_palette                     ; Load color palette into PPU
  JSR set_nametable                   ; Load background tiles into PPU
  JSR init_sprites                    ; Set up initial sprite positions

  ;=== Start Game ===
  JMP main                            ; Jump to main game loop
.endproc

;-------------------------------------------------------------------------------
; Set Palette - Load 32 color values into PPU palette memory
;-------------------------------------------------------------------------------
; The NES can display 64 different colors, but only 32 at a time
; Palette memory starts at $3F00 and holds 32 bytes
.proc set_palette
    ; Set PPU VRAM address to palette memory start ($3F00)
    vram_set_address PALETTE_ADDRESS  ; Macro to set VRAM address

    LDX #$00                          ; Start with first color (index 0)

palette_loop:
    LDA palette_data, X               ; Load color value from ROM data
    STA PPU_VRAM_IO                   ; Write color to PPU palette memory
    INX                               ; Move to next color
    CPX #$20                          ; Have we written all 32 colors?
    BNE palette_loop                  ; If not, continue loop

    RTS                               ; Return to caller
.endproc

;-------------------------------------------------------------------------------
; Set Nametable - Load background tile data into PPU nametable memory
;-------------------------------------------------------------------------------
; The nametable defines which tiles appear where on the background
; Each screen is 32x30 tiles = 960 bytes total
.proc set_nametable
  wait_for_vblank                     ; Wait for VBlank (safe time to write PPU)

  ; Set PPU VRAM address to nametable 0 start ($2000)
  vram_set_address NAME_TABLE_0_ADDRESS

  ; Set up 16-bit pointer to nametable data in ROM
  LDA #<nametable_data                ; Load low byte of nametable_data address
  STA temp_ptr_low                    ; Store in zero page pointer
  LDA #>nametable_data                ; Load high byte of nametable_data address
  STA temp_ptr_high                   ; Store in zero page pointer

  ; Copy 960 bytes of nametable data to PPU
  ; We need to copy 3 full pages (768 bytes) + 192 remaining bytes
  LDY #$00                            ; Y = offset within current page
  LDX #$03                            ; X = number of full pages to copy

copy_full_pages:
  LDA (temp_ptr_low),Y                ; Load byte from ROM using indirect addressing
  STA PPU_VRAM_IO                     ; Write byte to PPU VRAM
  INY                                 ; Move to next byte in page
  BNE copy_full_pages                 ; Continue until Y wraps to 0 (256 bytes copied)

  INC temp_ptr_high                   ; Move pointer to next page
  DEX                                 ; Decrement page counter
  BNE copy_full_pages                 ; Continue if more pages to copy

  ; Copy remaining 192 bytes (960 - 768 = 192)
  LDY #$00                            ; Reset Y to 0
copy_remaining:
  LDA (temp_ptr_low),Y                ; Load byte from ROM
  STA PPU_VRAM_IO                     ; Write to PPU
  INY                                 ; Next byte
  CPY #192                            ; Have we copied all remaining bytes?
  BNE copy_remaining                  ; If not, continue

  ; Reset PPU scroll to (0,0) - required after VRAM writes
  LDA #$00
  STA PPU_SCROLL                      ; Set horizontal scroll to 0
  STA PPU_SCROLL                      ; Set vertical scroll to 0

  RTS                                 ; Return to caller
.endproc

;-------------------------------------------------------------------------------
; Update Score Display - Draw current scores on screen
;-------------------------------------------------------------------------------
; This writes the score digits directly to the nametable during VBlank
.proc update_score
  ; Draw Player 1 score (left side of screen)
  LDA PPU_STATUS                      ; Reset PPU address latch
  LDA #$20                            ; High byte of nametable address
  STA PPU_ADDRESS                     ; Set high byte
  LDA #$25                            ; Low byte (specific tile position)
  STA PPU_ADDRESS                     ; Set low byte

  ; Convert score number to ASCII character
  LDA #'0'                            ; ASCII value of '0'
  CLC                                 ; Clear carry flag
  ADC player1_score                   ; Add player 1 score (0-9)
  STA PPU_VRAM_IO                     ; Write character to screen

  ; Draw Player 2 score (right side of screen)
  LDA PPU_STATUS                      ; Reset PPU address latch
  LDA #$20                            ; High byte of nametable address
  STA PPU_ADDRESS
  LDA #$39                            ; Low byte (different tile position)
  STA PPU_ADDRESS

  ; Convert score number to ASCII character
  LDA #'0'                            ; ASCII value of '0'
  CLC                                 ; Clear carry flag
  ADC player2_score                   ; Add player 2 score (0-9)
  STA PPU_VRAM_IO                     ; Write character to screen

  ; Reset scroll after VRAM writes
  LDA #$00
  STA PPU_SCROLL                      ; Horizontal scroll = 0
  STA PPU_SCROLL                      ; Vertical scroll = 0

  RTS                                 ; Return to caller
.endproc

;-------------------------------------------------------------------------------
; Initialize Sprites - Copy initial sprite data to OAM buffer
;-------------------------------------------------------------------------------
; This sets up the starting positions and graphics for all sprites
.proc init_sprites
  LDX #0                              ; Start with first sprite byte

copy_sprite_data:
    LDA sprite_data, X                ; Load byte from ROM sprite data
    STA oam, X                        ; Store in OAM buffer
    INX                               ; Move to next byte
    CPX #$24                          ; Have we copied all sprite data?
                                      ; ($24 = 36 bytes = 9 sprites * 4 bytes each)
    BNE copy_sprite_data              ; If not, continue copying

  RTS                                 ; Return to caller
.endproc

;-------------------------------------------------------------------------------
; Initialize Game - Set starting scores and game state
;-------------------------------------------------------------------------------
.proc init_game
  ; Reset starting scores
  LDA #0
  STA player1_score
  STA player2_score

  RTS                                 ; Return to caller
.endproc

;-------------------------------------------------------------------------------
; Start Round - Reset ball position and set random direction
;-------------------------------------------------------------------------------
; Called at game start and after each point is scored
.proc start_round
  ; Reset ball to center of screen
  LDA #116                            ; Y position (middle of screen)
  STA SPRITE_BALL_ADDR                ; Set ball Y position
  LDA #120                            ; X position (middle of screen)
  STA SPRITE_BALL_ADDR + SPRITE_OFFSET_X ; Set ball X position

  JSR update_random                   ; Update random number generation
  ; Set random ball direction based on random number
  ; Use bit 0 to determine X direction (left or right)
  LDA random_num                      ; Load random number
  AND #%00000001                      ; Mask to get only bit 0
  BNE ball_goes_left                  ; If bit 0 = 1, ball goes left
    LDA #$01                          ; Bit 0 = 0: ball goes right (+1)
    STA ball_dx                       ; Set X velocity
    JMP check_y_direction             ; Skip left direction code
  ball_goes_left:
    LDA #$FF                          ; Bit 0 = 1: ball goes left (-1)
    STA ball_dx                       ; Set X velocity
  check_y_direction:

  ; Use bit 1 to determine Y direction (up or down)
  LDA random_num                      ; Load random number again
  AND #%00000010                      ; Mask to get only bit 1
  BNE ball_goes_up                    ; If bit 1 = 1, ball goes up
    LDA #$01                          ; Bit 1 = 0: ball goes down (+1)
    STA ball_dy                       ; Set Y velocity
    JMP direction_set                 ; Skip up direction code
  ball_goes_up:
    LDA #$FF                          ; Bit 1 = 1: ball goes up (-1)
    STA ball_dy                       ; Set Y velocity
  direction_set:

  RTS                                 ; Return to caller
.endproc

;-------------------------------------------------------------------------------
; Update Player 1 - Handle input and collision for left paddle
;-------------------------------------------------------------------------------
.proc update_player_1
  ; Handle UP button input
  LDA controller_1                    ; Load current controller state
  AND #PAD_U                          ; Check if UP button is pressed
  BEQ check_down                      ; If not pressed, check DOWN button
    ; UP button is pressed - move paddle up
    LDA SPRITE_PLAYER0_ADDR           ; Load current Y position
    SEC                               ; Set carry flag for subtraction
    SBC #$03                          ; Subtract 1 (move up)
    CMP #0                            ; Check if we hit top of screen
    BEQ check_down                    ; If at top, don't move
    STA SPRITE_PLAYER0_ADDR           ; Store new Y position
  check_down:

  ; Handle DOWN button input
  LDA controller_1                    ; Load current controller state
  AND #PAD_D                          ; Check if DOWN button is pressed
  BEQ check_collision                 ; If not pressed, check collision
    ; DOWN button is pressed - move paddle down
    LDA SPRITE_PLAYER0_ADDR           ; Load current Y position
    CLC                               ; Clear carry flag for addition
    ADC #$03                          ; Add 1 (move down)
    CMP #200                          ; Check if we hit bottom of screen
    BEQ check_collision               ; If at bottom, don't move
    STA SPRITE_PLAYER0_ADDR           ; Store new Y position
  check_collision:

  ; Set up collision detection between paddle and ball
  ; Player 1 paddle collision box
  LDA SPRITE_PLAYER0_ADDR + SPRITE_OFFSET_X ; Load paddle X position
  STA cx1                             ; Store as collision object 1 X
  LDA SPRITE_PLAYER0_ADDR + SPRITE_OFFSET_Y ; Load paddle Y position
  STA cy1                             ; Store as collision object 1 Y
  LDA #$08                            ; Paddle width = 8 pixels
  STA cw1                             ; Store as collision object 1 width
  LDA #$18                            ; Paddle height = 24 pixels (3 sprites * 8)
  STA ch1                             ; Store as collision object 1 height

  ; Ball collision box
  LDA SPRITE_BALL_ADDR + SPRITE_OFFSET_X ; Load ball X position
  STA cx2                             ; Store as collision object 2 X
  LDA SPRITE_BALL_ADDR + SPRITE_OFFSET_Y ; Load ball Y position
  STA cy2                             ; Store as collision object 2 Y
  LDA #$08                            ; Ball width = 8 pixels
  STA cw2                             ; Store as collision object 2 width
  STA ch2                             ; Ball height = 8 pixels (same as width)

  ; Test for collision
  JSR collision_test                  ; Call collision detection subroutine
  BCC no_ball_collision               ; If carry clear, no collision
    ; Collision detected - bounce ball to the right
    LDA #$03                          ; Set ball X velocity to +1 (right)
    STA ball_dx
  no_ball_collision:

  ; Update multi-sprite paddle positions
  ; Player 1 paddle consists of 4 sprites stacked vertically
  LDA SPRITE_PLAYER0_ADDR             ; Load main paddle Y position
  CLC                                 ; Clear carry for addition
  ADC #8                              ; Add 8 pixels (one sprite height)
  STA SPRITE_PLAYER0_ADDR + 4         ; Set second sprite Y position
  CLC                                 ; Clear carry
  ADC #8                              ; Add another 8 pixels
  STA SPRITE_PLAYER0_ADDR + 8         ; Set third sprite Y position
  CLC                                 ; Clear carry
  ADC #8                              ; Add another 8 pixels
  STA SPRITE_PLAYER0_ADDR + 12        ; Set fourth sprite Y position

  RTS                                 ; Return to caller
.endproc

;-------------------------------------------------------------------------------
; Update Player 2 - Handle input and collision for right paddle
;-------------------------------------------------------------------------------
.proc update_player_2
  ; Handle UP button input (same logic as Player 1)
  LDA controller_2                    ; Load current controller 2 state
  AND #PAD_U                          ; Check if UP button is pressed
  BEQ check_down                      ; If not pressed, check DOWN button
    ; UP button is pressed - move paddle up
    LDA SPRITE_PLAYER1_ADDR           ; Load current Y position
    SEC                               ; Set carry flag for subtraction
    SBC #$03                          ; Subtract 1 (move up)
    CMP #0                            ; Check if we hit top of screen
    BEQ check_down                    ; If at top, don't move
    STA SPRITE_PLAYER1_ADDR           ; Store new Y position
  check_down:

  ; Handle DOWN button input (same logic as Player 1)
  LDA controller_2                    ; Load current controller 2 state
  AND #PAD_D                          ; Check if DOWN button is pressed
  BEQ check_collision                 ; If not pressed, check collision
    ; DOWN button is pressed - move paddle down
    LDA SPRITE_PLAYER1_ADDR           ; Load current Y position
    CLC                               ; Clear carry flag for addition
    ADC #$03                          ; Add 1 (move down)
    CMP #200                          ; Check if we hit bottom of screen
    BEQ check_collision               ; If at bottom, don't move
    STA SPRITE_PLAYER1_ADDR           ; Store new Y position
  check_collision:

  ; Set up collision detection between paddle and ball
  ; Player 2 paddle collision box
  LDA SPRITE_PLAYER1_ADDR + SPRITE_OFFSET_X ; Load paddle X position
  STA cx1                             ; Store as collision object 1 X
  LDA SPRITE_PLAYER1_ADDR + SPRITE_OFFSET_Y ; Load paddle Y position
  STA cy1                             ; Store as collision object 1 Y
  LDA #$08                            ; Paddle width = 8 pixels
  STA cw1                             ; Store as collision object 1 width
  LDA #$18                            ; Paddle height = 24 pixels
  STA ch1                             ; Store as collision object 1 height

  ; Ball collision box (same as Player 1)
  LDA SPRITE_BALL_ADDR + SPRITE_OFFSET_X ; Load ball X position
  STA cx2                             ; Store as collision object 2 X
  LDA SPRITE_BALL_ADDR + SPRITE_OFFSET_Y ; Load ball Y position
  STA cy2                             ; Store as collision object 2 Y
  LDA #$08                            ; Ball width = 8 pixels
  STA cw2                             ; Store as collision object 2 width
  STA ch2                             ; Ball height = 8 pixels

  ; Test for collision
  JSR collision_test                  ; Call collision detection subroutine
  BCC no_ball_collision               ; If carry clear, no collision
    ; Collision detected - bounce ball to the left
    LDA #$FD                          ; Set ball X velocity to -1 (left)
    STA ball_dx
  no_ball_collision:

  ; Update multi-sprite paddle positions (same as Player 1)
  LDA SPRITE_PLAYER1_ADDR             ; Load main paddle Y position
  CLC                                 ; Clear carry for addition
  ADC #8                              ; Add 8 pixels
  STA SPRITE_PLAYER1_ADDR + 4         ; Set second sprite Y position
  CLC                                 ; Clear carry
  ADC #8                              ; Add another 8 pixels
  STA SPRITE_PLAYER1_ADDR + 8         ; Set third sprite Y position
  CLC                                 ; Clear carry
  ADC #8                              ; Add another 8 pixels
  STA SPRITE_PLAYER1_ADDR + 12        ; Set fourth sprite Y position

  RTS                                 ; Return to caller
.endproc

;-------------------------------------------------------------------------------
; Update Ball - Move ball and handle wall/goal collisions
;-------------------------------------------------------------------------------
.proc update_ball
  ; Move ball vertically
  LDA SPRITE_BALL_ADDR                ; Load current ball Y position
  CLC                                 ; Clear carry for addition
  ADC ball_dy                         ; Add Y velocity (can be positive or negative)
  STA SPRITE_BALL_ADDR                ; Store new Y position

  ; Check collision with top wall
  CMP #0                              ; Did ball hit top of screen?
  BNE check_bottom_wall               ; If not, check bottom wall
    LDA #1                            ; Ball hit top - reverse Y direction
    STA ball_dy                       ; Set Y velocity to +1 (down)
  check_bottom_wall:

  ; Check collision with bottom wall
  LDA SPRITE_BALL_ADDR                ; Load current ball Y position
  CMP #210                            ; Did ball hit bottom of screen?
  BNE move_horizontally               ; If not, continue with horizontal movement
    LDA #$FF                          ; Ball hit bottom - reverse Y direction
    STA ball_dy                       ; Set Y velocity to -1 (up)
  move_horizontally:

  ; Move ball horizontally
  LDA SPRITE_BALL_ADDR + SPRITE_OFFSET_X ; Load current ball X position
  CLC                                 ; Clear carry for addition
  ADC ball_dx                         ; Add X velocity
  STA SPRITE_BALL_ADDR + SPRITE_OFFSET_X ; Store new X position

  ; Check collision with left wall (Player 2 scores)
  CMP #0                              ; Did ball hit left side of screen?
  BNE check_right_wall                ; If not, check right wall
    INC player2_score                 ; Player 2 scores a point
    JSR start_round                   ; Reset ball for next round
  check_right_wall:

  ; Check collision with right wall (Player 1 scores)
  LDA SPRITE_BALL_ADDR + SPRITE_OFFSET_X ; Load current ball X position
  CMP #248                            ; Did ball hit right side of screen?
  BNE ball_update_done                ; If not, ball update is complete
    INC player1_score                 ; Player 1 scores a point
    JSR start_round                   ; Reset ball for next round
  ball_update_done:

  RTS                                 ; Return to caller
.endproc

;-------------------------------------------------------------------------------
; Main Game Loop - Initialize game and run main loop
;-------------------------------------------------------------------------------
.proc main
    ; Initialize random number generator with a seed
    LDA #$78                          ; Use $78 as initial random seed
    STA random_num

    ; Configure PPU Control Register ($2000)
    ; Enable NMI interrupt and set background pattern table
    LDA #(PPUCTRL_ENABLE_NMI | PPUCTRL_BG_TABLE_1000)
    STA PPU_CONTROL

    ; Configure PPU Mask Register ($2001)
    ; Enable background and sprite rendering
    LDA #(PPUMASK_SHOW_BG | PPUMASK_SHOW_SPRITES | PPUMASK_SHOW_BG_LEFT | PPUMASK_SHOW_SPRITES_LEFT)
    STA PPU_MASK

    ; Initialize game state
    JSR init_game                     ; Set initial scores
    JSR start_round                   ; Set initial ball position/direction

main_game_loop:
  ; Wait for frame to change (synchronize with 60Hz refresh)
  LDA time                            ; Load current frame counter
  CMP prev_time                       ; Compare with previous frame
  BEQ main_game_loop                  ; If same, keep waiting
  ; Time has changed - update game for this frame
  STA prev_time                       ; Store current time as previous

  ; Update game logic
  JSR read_controllers                ; Read controller input
  JSR update_ball                     ; Update ball position and collisions
  JSR update_player_1                 ; Update player 1 paddle
  JSR update_player_2                 ; Update player 2 paddle
  JSR update_score                    ; Update score display

  ; Check for game reset
  LDA controller_1_pressed            ; Check if any buttons were pressed this frame
  AND #PAD_START                      ; Check specifically for START button
  BEQ continue_game                   ; If START not pressed, continue normally
    JSR start_round                   ; START pressed - reset ball position
  continue_game:

  JMP main_game_loop                  ; Loop forever
.endproc

;-------------------------------------------------------------------------------
; Read Controllers - Read input from both game controllers
;-------------------------------------------------------------------------------
.proc read_controllers
  ; Save previous controller states for edge detection
  LDA controller_1                    ; Load current controller 1 state
  STA controller_1_prev               ; Store as previous state

  LDA controller_2                    ; Load current controller 2 state
  STA controller_2_prev               ; Store as previous state

  ; Strobe controllers to latch current button states
  LDA #$01                            ; Load 1 into accumulator
  STA JOYPAD1                         ; Write 1 to controller port (strobe high)
  LDA #$00                            ; Load 0 into accumulator
  STA JOYPAD1                         ; Write 0 to controller port (strobe low)
                                      ; This latches the current button states

  ; Read 8 buttons from Controller 1
  ; Buttons are read in order: A, B, SELECT, START, UP, DOWN, LEFT, RIGHT
  LDX #$08                            ; Loop counter for 8 buttons
read_controller_1_loop:
  LDA JOYPAD1                         ; Read one bit from controller 1
  LSR A                               ; Shift right - button state goes to carry flag
  ROL controller_1                    ; Rotate carry flag into controller_1 variable
  DEX                                 ; Decrement loop counter
  BNE read_controller_1_loop          ; Continue until all 8 buttons read

  ; Read 8 buttons from Controller 2 (same process)
  LDX #$08                            ; Loop counter for 8 buttons
read_controller_2_loop:
  LDA JOYPAD2                         ; Read one bit from controller 2
  LSR A                               ; Shift right - button state goes to carry flag
  ROL controller_2                    ; Rotate carry flag into controller_2 variable
  DEX                                 ; Decrement loop counter
  BNE read_controller_2_loop          ; Continue until all 8 buttons read

  ; Calculate which buttons were pressed this frame (edge detection)
  ; Formula: pressed = (~previous) & current
  LDA controller_1_prev               ; Load previous controller 1 state
  EOR #%11111111                      ; Invert all bits (NOT operation)
  AND controller_1                    ; AND with current state
  STA controller_1_pressed            ; Store buttons pressed this frame

  LDA controller_2_prev               ; Load previous controller 2 state
  EOR #%11111111                      ; Invert all bits (NOT operation)
  AND controller_2                    ; AND with current state
  STA controller_2_pressed            ; Store buttons pressed this frame

  RTS                                 ; Return to caller

.endproc

;-------------------------------------------------------------------------------
; Collision Test - Check if two rectangular objects overlap
;-------------------------------------------------------------------------------
; This implements Axis-Aligned Bounding Box (AABB) collision detection
; Input: cx1,cy1,cw1,ch1 = object 1 position and size
;        cx2,cy2,cw2,ch2 = object 2 position and size
; Output: Carry flag SET if collision detected, CLEAR if no collision
.proc collision_test
	CLC                               ; Clear carry flag (assume no collision)

	; Test 1: Is object 1 completely to the left of object 2?
	LDA cx1                           ; Load object 1 X position
	ADC cw1                           ; Add object 1 width (right edge of object 1)
	CMP cx2                           ; Compare with object 2 left edge
	BCC no_collision                  ; If obj1_right < obj2_left, no collision

	; Test 2: Is object 1 completely to the right of object 2?
	CLC                               ; Clear carry flag
	LDA cx2                           ; Load object 2 X position
	ADC cw2                           ; Add object 2 width (right edge of object 2)
	CMP cx1                           ; Compare with object 1 left edge
	BCC no_collision                  ; If obj2_right < obj1_left, no collision

	; Test 3: Is object 1 completely above object 2?
	LDA cy1                           ; Load object 1 Y position
	ADC ch1                           ; Add object 1 height (bottom edge of object 1)
	CMP cy2                           ; Compare with object 2 top edge
	BCC no_collision                  ; If obj1_bottom < obj2_top, no collision

	; Test 4: Is object 1 completely below object 2?
	CLC                               ; Clear carry flag
	LDA cy2                           ; Load object 2 Y position
	ADC ch2                           ; Add object 2 height (bottom edge of object 2)
	CMP cy1                           ; Compare with object 1 top edge
	BCC no_collision                  ; If obj2_bottom < obj1_top, no collision

	; If we reach here, all tests failed, meaning objects DO overlap
	SEC                               ; Set carry flag to indicate collision
	RTS                               ; Return with collision detected

no_collision:
	CLC                               ; Clear carry flag to indicate no collision
	RTS                               ; Return with no collision
.endproc

;-------------------------------------------------------------------------------
; Update Random Number - Generate pseudo-random numbers using LFSR
;-------------------------------------------------------------------------------
; This implements a Linear Feedback Shift Register for generating random numbers
; The algorithm uses bit shifting and XOR operations to create a sequence
; that appears random and has a long period before repeating
.proc update_random
    LDA random_num                    ; Load current random value

    ; Check if we need to apply feedback (based on bit 7)
    ASL                               ; Shift left: bit 7 -> Carry, bit 0 <- 0
    BCC no_feedback                   ; If carry clear (bit 7 was 0), skip XOR

    ; Apply feedback polynomial: XOR with $39 (binary: 00111001)
    ; This represents polynomial taps that ensure good randomness
    EOR #$39                          ; XOR with feedback pattern

no_feedback:
    STA random_num                    ; Store new random value
    RTS                               ; Return with new random number in A
.endproc

;===============================================================================
; GRAPHICS DATA (CHR-ROM)
;===============================================================================
; This section contains the tile graphics stored in Character ROM
.segment "CHARS"
; Load tile graphics from external file
; Each tile is 8x8 pixels with 2 bits per pixel (4 colors per tile)
.incbin "assets/pong/tiles.chr"       ; Binary file containing sprite/tile graphics

;===============================================================================
; GAME DATA (ROM)
;===============================================================================
.segment "RODATA"

;--- Color Palette Data ---
; 32 bytes defining the colors used in the game
; First 16 bytes = background palettes, Last 16 bytes = sprite palettes
palette_data:
  .incbin "assets/pong/palette.pal"        ; Binary file containing palette colors

;--- Background Screen Data ---
; 960 bytes defining which tiles appear where on the background screen
; Arranged as 32 columns × 30 rows = 960 tiles total
nametable_data:
  .incbin "assets/pong/screen.nam"         ; Binary file containing screen layout

;--- Initial Sprite Data ---
; This defines the starting positions and graphics for all sprites
; Each sprite uses 4 bytes: Y position, Tile index, Attributes, X position
sprite_data:
; Player 1 paddle (4 sprites stacked vertically)
.byte 100, 8, 0, 20                   ; Top sprite: Y=100, Tile=8, Attr=0, X=20
.byte 108, 9, 0, 20                   ; Second sprite: Y=108, Tile=9, Attr=0, X=20
.byte 116, 9, 0, 20                   ; Third sprite: Y=116, Tile=9, Attr=0, X=20
.byte 124, 10, 0, 20                  ; Bottom sprite: Y=124, Tile=10, Attr=0, X=20

; Player 2 paddle (4 sprites stacked vertically)
.byte 100, 8, 0, 220                  ; Top sprite: Y=100, Tile=8, Attr=0, X=220
.byte 108, 9, 0, 220                  ; Second sprite: Y=108, Tile=9, Attr=0, X=220
.byte 116, 9, 0, 220                  ; Third sprite: Y=116, Tile=9, Attr=0, X=220
.byte 124, 10, 0, 220                 ; Bottom sprite: Y=124, Tile=10, Attr=0, X=220

; Ball sprite
.byte 116, 7, 0, 120                  ; Ball: Y=116, Tile=7, Attr=0, X=120

;--- Text Data (not used in this version) ---
hello_txt:
.byte 'H','E','L','L','O',' ','W','O','R','L','D', 0  ; Null-terminated string
