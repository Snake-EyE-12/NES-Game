; NES ROM Header - tells emulator/hardware about the ROM
.segment "HEADER"
.byte 'N', 'E', 'S', $1a      ; "NES" followed by MS-DOS EOF marker
.byte $02                     ; 2 x 16KB PRG-ROM banks
.byte $01                     ; 1 x 8KB CHR-ROM bank
.byte $00, $00                ; Mapper 0, no special features

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
  INX                     ; Increment X (now $00)
  STX $2000               ; PPUCTRL = 0 (disable NMI, sprites, background)
  STX $2001               ; PPUMASK = 0 (disable rendering)
  STX $4010               ; DMC frequency register = 0 (disable DMC)

  ; === Wait for PPU to be ready ===
  BIT $2002               ; Read PPUSTATUS to clear VBlank flag

  ; First VBlank wait - PPU needs time to stabilize
vblankwait:
  BIT $2002               ; Read PPUSTATUS register
  BPL vblankwait          ; Branch if Plus (bit 7 = 0, no VBlank)
                          ; Loop until VBlank flag is set

  ; Second VBlank wait - ensures PPU is fully ready
vblankwait2:
  BIT $2002               ; Read PPUSTATUS register again
  BPL vblankwait2         ; Branch if Plus (bit 7 = 0, no VBlank)
                          ; Loop until second VBlank occurs

  JSR load_palette        ; Load palette colors
  JSR load_background     ; Load background tiles
  JMP main                ; Jump to main program
.endproc

; Load palette data
.proc load_palette
  ; Set PPU address to palette RAM
  LDA #$3F
  STA $2006
  LDA #$00
  STA $2006

  ; Load background palette (4 colors)
  LDA #$01                ; Dark blue background
  STA $2007
  LDA #$29                ; Green
  STA $2007
  LDA #$1A                ; Light blue
  STA $2007
  LDA #$15                ; Black
  STA $2007

  RTS
.endproc

; Load background tiles to nametable
.proc load_background
  ; Set PPU address to start of nametable 0 ($2000)
  LDA #$20
  STA $2006
  LDA #$00
  STA $2006

  ; Clear the screen first (fill with tile 0)
  LDX #$04                ; 4 pages (1024 bytes total)
  LDY #$00
  LDA #$00                ; Tile 0 (empty/background)
clear_loop:
  STA $2007
  INY
  BNE clear_loop
  DEX
  BNE clear_loop

  ; Now place a test tile at position $200A (row 0, column 10)
  LDA #$20
  STA $2006
  LDA #$0A
  STA $2006

  ; Write tile #$01 (should be visible tile from CHR data)
  LDA #$01
  STA $2007
  LDA #$01
  STA $2007
  LDA #$01
  STA $2007



.endproc

; Main program logic
.proc main
  ; === Enable Rendering ===
  LDA #%00001110          ; Enable background rendering properly
                          ; bit 3 = 1: Show background
                          ; bit 2 = 1: Show background in leftmost 8 pixels
                          ; bit 1 = 1: Show background everywhere
  STA $2001               ; Write to PPUMASK register

  ; === Main Loop ===
forever:
  JMP forever             ; Stay here
.endproc

; Interrupt vectors - tells CPU where to jump for each interrupt
.segment "VECTORS"
.addr nmi_handler         ; NMI vector ($FFFA-$FFFB)
.addr reset_handler       ; Reset vector ($FFFC-$FFFD)
.addr irq_handler         ; IRQ vector ($FFFE-$FFFF)

; Character ROM data (graphics patterns)
.segment "CHARS"

.incbin "assets/tiles.chr"

; Startup segment
.segment "STARTUP"
