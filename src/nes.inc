.ifndef ::NES_INC
NES_INC = 1

;*****************************************************************
; NES PPU, APU, and controller register addresses and constants
;*****************************************************************
; Define PPU (PICTURE PROCESSING UNIT) Registers
PPU_CONTROL         = $2000 ; PPU Control Register 1 (Write)
PPU_MASK            = $2001 ; PPU Control Register 2 (Write)
PPU_STATUS          = $2002 ; PPU Status Register (Read)
PPU_SPRRAM_ADDRESS  = $2003 ; PPU SPR-RAM Address Register (Write)
PPU_SPRRAM_IO       = $2004 ; PPU SPR-RAM I/O Register (Write)
PPU_SCROLL          = $2005 ; PPU_SCROLL
PPU_ADDRESS         = $2006 ; PPU VRAM Address Register
PPU_VRAM_IO         = $2007 ; VRAM I/O Register (Read/Write)
SPRITE_DMA          = $4014 ; Sprite DMA Register

; Define APU Registers (AUDIO PROCESSING UNIT)
APU_DM_CONTROL      = $4010 ; APU Delta Modulation Control Register (Write)
APU_CLOCK           = $4015 ; APU Sound/Vertical Clock Signal Register (Read/Write)

; Joystick/Controller values
JOYPAD1             = $4016 ; Joypad 1 (Read/Write)
JOYPAD2             = $4017 ; Joypad 2 (Read/Write)

; Gamepad bit values
PAD_A               = $80
PAD_B               = $40
PAD_SELECT          = $20
PAD_START           = $10
PAD_U               = $08
PAD_D               = $04
PAD_L               = $02
PAD_R               = $01

; Useful PPU memory addresses
NAME_TABLE_0_ADDRESS		  = $2000
ATTRIBUTE_TABLE_0_ADDRESS	= $23C0
NAME_TABLE_1_ADDRESS		  = $2400
ATTRIBUTE_TABLE_1_ADDRESS	= $27C0
PALETTE_ADDRESS           = $3f00

; OAM Sprite Byte Offset
SPRITE_OFFSET_Y       = 0
SPRITE_OFFSET_TILE    = 1
SPRITE_OFFSET_ATTRIB  = 2
SPRITE_OFFSET_X       = 3

; OAM Sprite Attributes
SPRITE_PALETTE_0 = %00000000
SPRITE_PALETTE_1 = %00000001
SPRITE_PALETTE_2 = %00000010
SPRITE_PALETTE_3 = %00000011
SPRITE_BEHIND_BG = %00100000
SPRITE_FLIP_H    = %01000000
SPRITE_FLIP_V    = %10000000

; PPU Masks
PPUMASK_GRAYSCALE           = %00000001
PPUMASK_SHOW_BG             = %00000010
PPUMASK_SHOW_SPRITES        = %00000100
PPUMASK_SHOW_BG_LEFT        = %00001000
PPUMASK_SHOW_SPRITES_LEFT   = %00010000
PPUMASK_EMPHASIZE_RED       = %00100000
PPUMASK_EMPHASIZE_GREEN     = %01000000
PPUMASK_EMPHASIZE_BLUE      = %10000000

; PPU Control
PPUCTRL_NAMETABLE_1        = %00000001
PPUCTRL_VRAM_INCREMENT_32  = %00000100
PPUCTRL_SPR_TABLE_1000     = %00001000
PPUCTRL_BG_TABLE_1000      = %00010000
PPUCTRL_SPRITE_SIZE_8x16   = %00100000
PPUCTRL_ENABLE_NMI         = %10000000



.endif
