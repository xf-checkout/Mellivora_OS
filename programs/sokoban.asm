; sokoban.asm - Sokoban puzzle game
; VBE 1024x768x32bpp. Arrows/WASD=move, R=restart, ESC=quit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

; Tile types (bitfield)
TILE_EMPTY      equ 0x00
TILE_SPOT       equ 0x01
TILE_BRICK      equ 0x02
TILE_BRICK_SPOT equ 0x03
TILE_WALL       equ 0x04
TILE_PLAYER     equ 0x08
TILE_PLAYER_SPOT equ 0x09

CELL_SZ         equ 60

COL_BG          equ 0x00101010
COL_EMPTY       equ 0x00181818
COL_WALL        equ 0x004466AA
COL_BRICK       equ 0x00CC8833
COL_BSPT        equ 0x0033BB44
COL_SPOT_DOT    equ 0x00886644
COL_PLAYER      equ 0x00FFEE44
COL_PLSPT       equ 0x00FFCC44
COL_WHITE       equ 0x00FFFFFF
COL_DIM         equ 0x00888888
COL_GREEN       equ 0x0033CC44
COL_YELLOW      equ 0x00FFE040

; Level data format: width, height, player_x, player_y, then tiles (compressed: 2 tiles per byte)
; Level 1 (14x10) - from original sokoban
level1:
        db 14, 10               ; width, height
        dw 63                   ; player position (linear index)
        db 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x00
        db 0x41, 0x10, 0x04, 0x00, 0x00, 0x04, 0x44
        db 0x41, 0x10, 0x04, 0x02, 0x00, 0x20, 0x04
        db 0x41, 0x10, 0x04, 0x24, 0x44, 0x40, 0x04
        db 0x41, 0x10, 0x00, 0x08, 0x04, 0x40, 0x04
        db 0x41, 0x10, 0x04, 0x04, 0x00, 0x20, 0x44
        db 0x44, 0x44, 0x44, 0x04, 0x42, 0x02, 0x04
        db 0x00, 0x40, 0x20, 0x02, 0x02, 0x02, 0x04
        db 0x00, 0x40, 0x00, 0x04, 0x00, 0x00, 0x04
        db 0x00, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44

; Level 2 (9x7) - simple level
level2:
        db 9, 7                 ; width, height
        dw 32                   ; player position
        db 0x44, 0x44, 0x40, 0x00, 0x04   ; row 0 (9 tiles = 5 bytes, last byte has 1 tile + padding)
        db 0x40, 0x00, 0x40, 0x00, 0x04
        db 0x40, 0x02, 0x04, 0x40, 0x04
        db 0x40, 0x24, 0x19, 0x44, 0x04   ; note: contains player (8) at pos 32
        db 0x44, 0x00, 0x31, 0x20, 0x04
        db 0x04, 0x00, 0x00, 0x00, 0x04
        db 0x04, 0x44, 0x44, 0x44, 0x04

; Level 3 (8x6) - easier level
level3:
        db 8, 6
        dw 9                    ; player position
        db 0x44, 0x44, 0x44, 0x44         ; row 0
        db 0x48, 0x00, 0x00, 0x04         ; row 1 (player at pos 9 -> col1)
        db 0x40, 0x20, 0x10, 0x04         ; row 2
        db 0x40, 0x04, 0x20, 0x04         ; row 3
        db 0x40, 0x01, 0x00, 0x04         ; row 4
        db 0x44, 0x44, 0x44, 0x44         ; row 5

; Level table
level_table:
        dd level3               ; Level 1 (easiest)
        dd level2               ; Level 2
        dd level1               ; Level 3 (hardest)
NUM_LEVELS      equ 3

start:
        VBE_GAME_INIT
        mov dword [current_level], 0
        ; Load persistent levels-cleared count from /scores/sokoban
        mov esi, hs_name_sk
        call hs_load
        mov [total_cleared], eax
        call load_level_init

main_loop:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je .nk
        cmp al, KEY_ESC
        je .quit
        cmp al, 'q'
        je .quit
        cmp al, 'Q'
        je .quit

        cmp dword [game_state], 0
        jne .any_key

        cmp al, 'r'
        je .restart
        cmp al, 'R'
        je .restart

        cmp al, KEY_UP
        je .try_up
        cmp al, 'w'
        je .try_up
        cmp al, KEY_DOWN
        je .try_down
        cmp al, 's'
        je .try_down
        cmp al, KEY_LEFT
        je .try_left
        cmp al, 'a'
        je .try_left
        cmp al, KEY_RIGHT
        je .try_right
        cmp al, 'd'
        je .try_right
        jmp .nk

.try_up:
        mov eax, [level_w]
        neg eax
        jmp .do_move
.try_down:
        mov eax, [level_w]
        jmp .do_move
.try_left:
        mov eax, -1
        jmp .do_move
.try_right:
        mov eax, 1
.do_move:
        call try_move
        call check_win
        cmp eax, 1
        je .level_done
        call draw_all
        jmp .nk

.level_done:
        ; Bump persistent levels-cleared, save, win SFX
        pushad
        mov eax, [total_cleared]
        inc eax
        mov [total_cleared], eax
        mov ebx, [total_cleared]
        mov esi, hs_name_sk
        call hs_save
        call audio_sfx_win
        popad
        inc dword [current_level]
        cmp dword [current_level], NUM_LEVELS
        jge .all_done
        mov dword [game_state], 1
        call draw_all
        jmp .nk
.all_done:
        mov dword [game_state], 2
        call draw_all
        jmp .nk

.any_key:
        cmp dword [game_state], 1
        jne .all_key
        mov dword [game_state], 0
        call load_level_init
        call draw_all
        jmp .nk
.all_key:
        ; game_state=2: any key exits
        jmp .quit

.restart:
        call load_level_init
        call draw_all
        jmp .nk

.nk:
        mov eax, SYS_SLEEP
        mov ebx, 1
        int 0x80
        jmp main_loop

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;--------------------------------------
load_level_init:
        pushad
        ; Get level pointer
        mov eax, [current_level]
        mov esi, [level_table + eax*4]

        ; Read width, height
        movzx eax, byte [esi]
        mov [level_w], eax
        movzx eax, byte [esi + 1]
        mov [level_h], eax
        movzx eax, word [esi + 2]
        mov [player_pos], eax
        add esi, 4

        ; Calculate level size
        mov eax, [level_w]
        imul eax, [level_h]
        mov [level_size], eax

        ; Decompress level into current_map
        mov edi, current_map
        mov ecx, eax
.decompress:
        cmp ecx, 0
        jle .decompress_done
        movzx eax, byte [esi]

        ; High nibble first
        mov edx, eax
        shr edx, 4
        mov [edi], dl
        inc edi
        dec ecx
        cmp ecx, 0
        jle .decompress_next

        ; Low nibble
        and eax, 0x0F
        mov [edi], al
        inc edi
        dec ecx
.decompress_next:
        inc esi
        jmp .decompress
.decompress_done:
        mov dword [moves], 0
        mov dword [game_state], 0
        popad
        call draw_all
        ret

try_move:
        pushad
        mov [move_offset], eax

        ; Calculate destination position
        mov ebx, [player_pos]
        add ebx, eax            ; dest = player + offset

        ; Bounds check
        cmp ebx, 0
        jl .cant_move
        cmp ebx, [level_size]
        jge .cant_move

        ; Get tile at destination
        movzx ecx, byte [current_map + ebx]

        ; Wall?
        cmp ecx, TILE_WALL
        je .cant_move

        ; Brick?
        test ecx, TILE_BRICK
        jz .just_move           ; no brick, just move

        ; Try pushing brick
        mov edx, ebx
        add edx, [move_offset] ; position beyond brick

        ; Bounds check for push destination
        cmp edx, 0
        jl .cant_move
        cmp edx, [level_size]
        jge .cant_move

        ; Check push destination tile
        movzx ecx, byte [current_map + edx]
        test ecx, 0x0E         ; wall (4) or brick (2) or player (8)?
        jnz .cant_move          ; can't push there

        ; Push the brick!
        ; Add brick bit at push destination
        or byte [current_map + edx], TILE_BRICK

        ; Remove brick bit at brick's old position (where player moves to)
        and byte [current_map + ebx], ~TILE_BRICK  ; 0xFD

.just_move:
        ; Remove player bit from old position
        mov ecx, [player_pos]
        and byte [current_map + ecx], ~TILE_PLAYER ; 0xF7

        ; Add player bit at new position
        or byte [current_map + ebx], TILE_PLAYER

        ; Update player position
        mov [player_pos], ebx
        inc dword [moves]

.cant_move:
        popad
        ret

;=== Check win: return EAX=1 if all bricks are on spots ===
check_win:
        push ebx
        push ecx
        xor ebx, ebx           ; count of bricks NOT on spots
        xor ecx, ecx
.loop:
        cmp ecx, [level_size]
        jge .done
        cmp byte [current_map + ecx], TILE_BRICK
        jne .next
        inc ebx                ; found a brick not on a spot
.next:
        inc ecx
        jmp .loop
.done:
        xor eax, eax
        test ebx, ebx
        jnz .not_won
        mov eax, 1
.not_won:
        pop ecx
        pop ebx
        ret

;--------------------------------------
; VBE draw
;--------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Title
        mov ebx, 10
        mov ecx, 15
        mov edx, msg_title
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str

        ; Level number
        mov ebx, 700
        mov ecx, 15
        mov edx, msg_level_lbl
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str
        mov ebx, 800
        mov ecx, 15
        mov edx, [current_level]
        inc edx
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_num

        ; Moves counter
        mov ebx, 700
        mov ecx, 38
        mov edx, msg_moves_lbl
        mov esi, COL_DIM
        mov eax, 1
        call vbe_draw_str
        mov ebx, 770
        mov ecx, 38
        mov edx, [moves]
        mov esi, COL_DIM
        mov eax, 1
        call vbe_draw_num

        ; Calculate centering
        mov eax, [level_w]
        imul eax, CELL_SZ
        mov ecx, 1024
        sub ecx, eax
        sar ecx, 1
        mov [.off_x], ecx

        mov eax, [level_h]
        imul eax, CELL_SZ
        mov ecx, 768
        sub ecx, eax
        sar ecx, 1
        add ecx, 20
        mov [.off_y], ecx

        ; Draw tiles
        mov dword [.ti], 0
.da_tile:
        mov esi, [.ti]
        cmp esi, [level_size]
        jge .da_status

        mov eax, esi
        xor edx, edx
        div dword [level_w]     ; EAX=row, EDX=col
        imul eax, CELL_SZ
        add eax, [.off_y]
        mov [.py], eax
        imul edx, CELL_SZ
        add edx, [.off_x]
        mov [.px], edx

        movzx ecx, byte [current_map + esi]
        mov [.tile], ecx

        ; Select fill color
        cmp ecx, TILE_WALL
        je .da_wall
        test ecx, TILE_PLAYER
        jnz .da_player
        test ecx, TILE_BRICK
        jnz .da_brick
        test ecx, TILE_SPOT
        jnz .da_spot
        mov edi, COL_EMPTY
        jmp .da_fill
.da_wall:
        mov edi, COL_WALL
        jmp .da_fill
.da_player:
        test ecx, TILE_SPOT
        jnz .da_plspt
        mov edi, COL_PLAYER
        jmp .da_fill
.da_plspt:
        mov edi, COL_PLSPT
        jmp .da_fill
.da_brick:
        test ecx, TILE_SPOT
        jnz .da_bspt
        mov edi, COL_BRICK
        jmp .da_fill
.da_bspt:
        mov edi, COL_BSPT
        jmp .da_fill
.da_spot:
        mov edi, COL_EMPTY
.da_fill:
        mov ebx, [.px]
        mov ecx, [.py]
        mov edx, CELL_SZ
        mov esi, CELL_SZ
        call vbe_fill_rect

        ; Draw symbol
        mov ecx, [.tile]
        cmp ecx, TILE_WALL
        je .da_next_t
        test ecx, TILE_PLAYER
        jz .da_sym_spot
        ; Player '@' centered, scale=2 → 10×14, offset (25,23)
        mov ebx, [.px]
        add ebx, 25
        mov ecx, [.py]
        add ecx, 23
        mov edx, '@'
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_char
        jmp .da_next_t
.da_sym_spot:
        ; Spot dot (no brick)
        mov ecx, [.tile]
        test ecx, TILE_BRICK
        jnz .da_next_t
        test ecx, TILE_SPOT
        jz .da_next_t
        mov ebx, [.px]
        add ebx, CELL_SZ/2
        mov ecx, [.py]
        add ecx, CELL_SZ/2
        mov edx, 8
        mov esi, COL_SPOT_DOT
        call vbe_fill_circle
.da_next_t:
        inc dword [.ti]
        jmp .da_tile

.da_status:
        ; Game state messages
        cmp dword [game_state], 1
        je .da_lc
        cmp dword [game_state], 2
        je .da_ac
        ; Hint
        mov ebx, 10
        mov ecx, 745
        mov edx, msg_hint
        mov esi, COL_DIM
        mov eax, 1
        call vbe_draw_str
        jmp .da_end
.da_lc:
        mov ebx, 350
        mov ecx, 360
        mov edx, msg_lc
        mov esi, COL_GREEN
        mov eax, 3
        call vbe_draw_str
        jmp .da_end
.da_ac:
        mov ebx, 300
        mov ecx, 340
        mov edx, msg_ac
        mov esi, COL_YELLOW
        mov eax, 3
        call vbe_draw_str
.da_end:
        VBE_GAME_PRESENT
        popad
        ret

.ti:    dd 0
.tile:  dd 0
.px:    dd 0
.py:    dd 0
.off_x: dd 0
.off_y: dd 0
;=== Data ===
msg_title:   db "SOKOBAN", 0
msg_level_lbl: db "LVL:", 0
msg_moves_lbl: db "MOVES:", 0
msg_hint:    db "ARROWS=MOVE  R=RESTART  ESC=QUIT", 0
msg_lc:      db "LEVEL COMPLETE", 0
msg_ac:      db "YOU WIN!", 0

;=== BSS ===
current_level:  dd 0
game_state:     dd 0
level_w:        dd 0
level_h:        dd 0
level_size:     dd 0
player_pos:     dd 0
moves:          dd 0
hs_name_sk:     db "sokoban", 0
total_cleared:  dd 0
move_offset:    dd 0
draw_off_x:     dd 0
draw_off_y:     dd 0
current_map:    times 256 db 0  ; max 256 tiles
