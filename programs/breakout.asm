; breakout.asm - Breakout / Arkanoid
; VBE 1024x768x32bpp. Left/Right=paddle, P=pause, Space=restart, ESC=quit.

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/highscore.inc"
%include "lib/audio.inc"

PLAY_X          equ 50
PLAY_Y          equ 80
PLAY_W          equ 924
PLAY_H          equ 640

PAD_W           equ 120
PAD_H           equ 15
PAD_Y           equ (PLAY_Y + PLAY_H - PAD_H - 10)
PAD_SPEED       equ 12

BALL_SIZE       equ 14
BALL_INIT_DX    equ 3
BALL_INIT_DY    equ -4

BRICK_ROWS      equ 6
BRICK_COLS      equ 10
BRICK_W         equ 86
BRICK_H         equ 24
BRICK_GAP       equ 4
BRICK_X_OFS     equ (PLAY_X + 14)
BRICK_Y_OFS     equ (PLAY_Y + 30)
MAX_BRICKS      equ (BRICK_ROWS * BRICK_COLS)

STATE_MENU      equ 0
STATE_PLAY      equ 1
STATE_PAUSED    equ 2
STATE_GAMEOVER  equ 3
STATE_WIN       equ 4

COL_BG          equ 0x00101010
COL_PADDLE      equ 0x00CCCCCC
COL_BALL        equ 0x00FFFFFF
COL_HUD_BG      equ 0x00222222
COL_HUD_TEXT    equ 0x0000CC44
COL_GAME_OVER   equ 0x00FF4444
COL_WIN         equ 0x0044FF44

start:
        VBE_GAME_INIT
        call game_init

.main_loop:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je .no_key

        cmp dword [game_state], STATE_PLAY
        jne .menu_key

        cmp al, KEY_LEFT
        je .move_left
        cmp al, KEY_RIGHT
        je .move_right
        cmp al, 'P'
        je .pause_game
        cmp al, KEY_ESC
        je .exit_game
        cmp al, 'q'
        je .exit_game
        cmp al, 'Q'
        je .exit_game
        jmp .no_key

.menu_key:
        cmp dword [game_state], STATE_PAUSED
        jne .check_restart
        cmp al, 'P'
        je .unpause
        cmp al, KEY_ESC
        je .exit_game
        cmp al, 'q'
        je .exit_game
        cmp al, 'Q'
        je .exit_game
        jmp .no_key
.check_restart:
        cmp al, KEY_SPACE
        je .restart
        cmp al, KEY_ESC
        je .exit_game
        cmp al, 'q'
        je .exit_game
        cmp al, 'Q'
        je .exit_game
        jmp .no_key

.move_left:
        mov eax, [pad_x]
        sub eax, PAD_SPEED
        cmp eax, PLAY_X
        jge .ml_ok
        mov eax, PLAY_X
.ml_ok:
        mov [pad_x], eax
        jmp .no_key

.move_right:
        mov eax, [pad_x]
        add eax, PAD_SPEED
        mov ecx, PLAY_X + PLAY_W - PAD_W
        cmp eax, ecx
        jle .mr_ok
        mov eax, ecx
.mr_ok:
        mov [pad_x], eax
        jmp .no_key

.pause_game:
        mov dword [game_state], STATE_PAUSED
        jmp .no_key

.unpause:
        mov dword [game_state], STATE_PLAY
        jmp .no_key

.restart:
        call game_init
        jmp .no_key

.no_key:
        cmp dword [game_state], STATE_PLAY
        jne .skip_update
        call game_update
.skip_update:
        call game_render
        mov eax, SYS_SLEEP
        mov ebx, 1
        int 0x80
        jmp .main_loop

.exit_game:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;=======================================================================
; GAME INIT
;=======================================================================

game_init:
        pushad
        ; Reset state
        mov dword [game_state], STATE_PLAY
        mov dword [score], 0
        mov dword [lives], 3
        mov dword [level], 1
        mov dword [bricks_left], MAX_BRICKS
        mov byte  [go_played], 0
        ; Load persistent high score
        mov esi, hs_name_breakout
        call hs_load
        mov [hi_score], eax

        ; Paddle center
        mov dword [pad_x], (PLAY_X + PLAY_W/2 - PAD_W/2)

        ; Ball on paddle
        call reset_ball

        ; Init bricks
        call init_bricks

        popad
        ret

reset_ball:
        pushad
        mov eax, [pad_x]
        add eax, PAD_W / 2 - BALL_SIZE / 2
        mov [ball_x], eax
        mov dword [ball_y], PAD_Y - BALL_SIZE - 1
        mov dword [ball_dx], BALL_INIT_DX
        mov dword [ball_dy], BALL_INIT_DY
        popad
        ret

init_bricks:
        pushad
        mov dword [bricks_left], MAX_BRICKS
        mov edi, bricks
        xor ecx, ecx           ; Row
.ib_row:
        cmp ecx, BRICK_ROWS
        jge .ib_done
        xor edx, edx           ; Col
.ib_col:
        cmp edx, BRICK_COLS
        jge .ib_next_row
        mov byte [edi], 1      ; Brick alive
        inc edi
        inc edx
        jmp .ib_col
.ib_next_row:
        inc ecx
        jmp .ib_row
.ib_done:
        popad
        ret

;=======================================================================
; GAME UPDATE
;=======================================================================

game_update:
        pushad

        ; Move ball
        mov eax, [ball_dx]
        add [ball_x], eax
        mov eax, [ball_dy]
        add [ball_y], eax

        ; Wall collisions
        ; Left wall
        cmp dword [ball_x], PLAY_X
        jge .no_left_wall
        mov dword [ball_x], PLAY_X
        neg dword [ball_dx]
.no_left_wall:
        ; Right wall
        mov eax, [ball_x]
        add eax, BALL_SIZE
        cmp eax, PLAY_X + PLAY_W
        jle .no_right_wall
        mov eax, PLAY_X + PLAY_W - BALL_SIZE
        mov [ball_x], eax
        neg dword [ball_dx]
.no_right_wall:
        ; Ceiling
        cmp dword [ball_y], PLAY_Y
        jge .no_ceiling
        mov dword [ball_y], PLAY_Y
        neg dword [ball_dy]
.no_ceiling:

        ; Bottom — lose life
        mov eax, [ball_y]
        cmp eax, PLAY_Y + PLAY_H
        jl .no_bottom
        dec dword [lives]
        cmp dword [lives], 0
        jle .game_over
        call reset_ball
        jmp .gu_done
.game_over:
        mov dword [game_state], STATE_GAMEOVER
        ; Persist high score and play SFX once
        cmp byte [go_played], 0
        jne .gu_done
        mov byte [go_played], 1
        mov esi, hs_name_breakout
        mov ebx, [score]
        call hs_update
        mov [hi_score], eax
        call audio_sfx_lose
        jmp .gu_done
.no_bottom:

        ; Paddle collision
        ; Ball bottom edge touching paddle top
        mov eax, [ball_y]
        add eax, BALL_SIZE
        cmp eax, PAD_Y
        jl .no_pad
        cmp eax, PAD_Y + PAD_H
        jg .no_pad
        ; Check x overlap
        mov eax, [ball_x]
        add eax, BALL_SIZE
        cmp eax, [pad_x]
        jl .no_pad
        mov eax, [ball_x]
        mov ecx, [pad_x]
        add ecx, PAD_W
        cmp eax, ecx
        jg .no_pad
        ; Bounce
        neg dword [ball_dy]
        mov dword [ball_y], PAD_Y - BALL_SIZE - 1

        ; Adjust dx based on where ball hits paddle
        ; If left third: dx = -3, middle: keep, right third: dx = 3
        mov eax, [ball_x]
        add eax, BALL_SIZE / 2
        sub eax, [pad_x]        ; Offset from paddle left
        cmp eax, PAD_W / 3
        jl .pad_left
        cmp eax, (PAD_W * 2) / 3
        jl .pad_center
        ; Right third
        mov dword [ball_dx], 3
        jmp .no_pad
.pad_left:
        mov dword [ball_dx], -3
        jmp .no_pad
.pad_center:
        ; Keep current dx direction, set to 2
        cmp dword [ball_dx], 0
        jl .pad_neg
        mov dword [ball_dx], 2
        jmp .no_pad
.pad_neg:
        mov dword [ball_dx], -2
.no_pad:

        ; Brick collisions
        call check_brick_collision

        ; Check win
        cmp dword [bricks_left], 0
        jg .gu_done
        ; Advance level
        inc dword [level]
        cmp dword [level], 4
        jg .win_game
        call init_bricks
        call reset_ball
        jmp .gu_done
.win_game:
        mov dword [game_state], STATE_WIN
.gu_done:
        popad
        ret

;---------------------------------------
; check_brick_collision
;---------------------------------------
check_brick_collision:
        pushad
        ; Check each alive brick
        xor ecx, ecx           ; Row
        mov esi, bricks
.cb_row:
        cmp ecx, BRICK_ROWS
        jge .cb_done
        xor edx, edx           ; Col
.cb_col:
        cmp edx, BRICK_COLS
        jge .cb_next_row

        ; Is brick alive?
        cmp byte [esi], 0
        je .cb_next

        ; Calculate brick position
        mov eax, edx
        imul eax, (BRICK_W + BRICK_GAP)
        add eax, BRICK_X_OFS   ; Brick left x
        mov [.cb_bx], eax

        mov eax, ecx
        imul eax, (BRICK_H + BRICK_GAP)
        add eax, BRICK_Y_OFS   ; Brick top y
        mov [.cb_by], eax

        ; AABB collision: ball vs brick
        ; Ball right < brick left? → no collision
        mov eax, [ball_x]
        add eax, BALL_SIZE
        cmp eax, [.cb_bx]
        jle .cb_next
        ; Ball left > brick right?
        mov eax, [ball_x]
        mov ebx, [.cb_bx]
        add ebx, BRICK_W
        cmp eax, ebx
        jge .cb_next
        ; Ball bottom < brick top?
        mov eax, [ball_y]
        add eax, BALL_SIZE
        cmp eax, [.cb_by]
        jle .cb_next
        ; Ball top > brick bottom?
        mov eax, [ball_y]
        mov ebx, [.cb_by]
        add ebx, BRICK_H
        cmp eax, ebx
        jge .cb_next

        ; Collision! Kill brick
        mov byte [esi], 0
        dec dword [bricks_left]
        add dword [score], 10 ; 10 points per brick
        neg dword [ball_dy]     ; Bounce vertically
        jmp .cb_done            ; Only one brick per frame

.cb_next:
        inc esi
        inc edx
        jmp .cb_col
.cb_next_row:
        inc ecx
        jmp .cb_row
.cb_done:
        popad
        ret

.cb_bx: dd 0
.cb_by: dd 0

;=======================================================================
; RENDERING
;=======================================================================

game_render:
        pushad

        ; Clear screen
        mov edx, COL_BG
        call vbe_clear_screen

        ; HUD background
        mov ebx, 0
        mov ecx, 0
        mov edx, 1024
        mov esi, PLAY_Y - 4
        mov edi, COL_HUD_BG
        call vbe_fill_rect

        ; SCORE:
        mov ebx, 40
        mov ecx, 28
        mov edx, str_score
        mov esi, COL_HUD_TEXT
        mov eax, 2
        call vbe_draw_str
        mov ebx, 170
        mov ecx, 28
        mov edx, [score]
        mov esi, COL_HUD_TEXT
        mov eax, 2
        call vbe_draw_num

        ; HIGH:
        mov ebx, 700
        mov ecx, 28
        mov edx, str_hi
        mov esi, COL_HUD_TEXT
        mov eax, 2
        call vbe_draw_str
        mov ebx, 800
        mov ecx, 28
        mov edx, [hi_score]
        mov esi, COL_HUD_TEXT
        mov eax, 2
        call vbe_draw_num

        ; LIVES:
        mov ebx, 390
        mov ecx, 28
        mov edx, str_lives
        mov esi, COL_HUD_TEXT
        mov eax, 2
        call vbe_draw_str
        mov ebx, 510
        mov ecx, 28
        mov edx, [lives]
        mov esi, COL_HUD_TEXT
        mov eax, 2
        call vbe_draw_num

        ; LEVEL:
        mov ebx, 730
        mov ecx, 28
        mov edx, str_level
        mov esi, COL_HUD_TEXT
        mov eax, 2
        call vbe_draw_str
        mov ebx, 850
        mov ecx, 28
        mov edx, [level]
        mov esi, COL_HUD_TEXT
        mov eax, 2
        call vbe_draw_num

        ; Draw bricks
        call draw_bricks

        ; Paddle
        mov ebx, [pad_x]
        mov ecx, PAD_Y
        mov edx, PAD_W
        mov esi, PAD_H
        mov edi, COL_PADDLE
        call vbe_fill_rect

        ; Ball
        mov ebx, [ball_x]
        mov ecx, [ball_y]
        mov edx, BALL_SIZE
        mov esi, BALL_SIZE
        mov edi, COL_BALL
        call vbe_fill_rect

        ; State overlays
        cmp dword [game_state], STATE_PAUSED
        je .rend_paused
        cmp dword [game_state], STATE_GAMEOVER
        je .rend_gameover
        cmp dword [game_state], STATE_WIN
        je .rend_win
        jmp .render_done

.rend_paused:
        mov ebx, 352
        mov ecx, 350
        mov edx, str_paused
        mov esi, COL_HUD_TEXT
        mov eax, 2
        call vbe_draw_str
        jmp .render_done

.rend_gameover:
        mov ebx, 392
        mov ecx, 340
        mov edx, str_gameover
        mov esi, COL_GAME_OVER
        mov eax, 3
        call vbe_draw_str
        mov ebx, 377
        mov ecx, 390
        mov edx, str_restart
        mov esi, COL_HUD_TEXT
        mov eax, 2
        call vbe_draw_str
        jmp .render_done

.rend_win:
        mov ebx, 422
        mov ecx, 340
        mov edx, str_you_win
        mov esi, COL_WIN
        mov eax, 3
        call vbe_draw_str
        mov ebx, 377
        mov ecx, 390
        mov edx, str_restart
        mov esi, COL_HUD_TEXT
        mov eax, 2
        call vbe_draw_str

.render_done:
        VBE_GAME_PRESENT
        popad
        ret

;---------------------------------------
; draw_bricks
;---------------------------------------
draw_bricks:
        pushad
        xor ecx, ecx           ; Row
.db_row:
        cmp ecx, BRICK_ROWS
        jge .db_done
        xor edx, edx           ; Col
.db_col:
        cmp edx, BRICK_COLS
        jge .db_next_row

        ; Is brick alive? index = row*BRICK_COLS + col
        push ecx
        push edx
        mov eax, ecx
        imul eax, BRICK_COLS
        add eax, edx
        cmp byte [bricks + eax], 0
        pop edx
        pop ecx
        je .db_next

        push ecx
        push edx

        ; Brick x
        mov eax, edx
        imul eax, (BRICK_W + BRICK_GAP)
        add eax, BRICK_X_OFS
        mov [.db_bx], eax

        ; Brick y
        mov eax, ecx
        imul eax, (BRICK_H + BRICK_GAP)
        add eax, BRICK_Y_OFS
        mov [.db_by], eax

        ; Color based on row
        mov eax, ecx
        cmp eax, 6
        jl .db_color_ok
        mov eax, 5
.db_color_ok:
        mov edi, [brick_colors + eax*4]
        mov ebx, [.db_bx]
        mov ecx, [.db_by]
        mov edx, BRICK_W
        mov esi, BRICK_H
        call vbe_fill_rect

        pop edx
        pop ecx

.db_next:
        inc edx
        jmp .db_col
.db_next_row:
        inc ecx
        jmp .db_row
.db_done:
        popad
        ret

.db_bx: dd 0
.db_by: dd 0

;=======================================================================
; DATA
;=======================================================================

str_score:    db "SCORE:", 0
str_hi:       db "HIGH:", 0
str_lives:    db "LIVES:", 0
str_level:    db "LEVEL:", 0
str_paused:   db "PAUSED  P=RESUME", 0
str_gameover: db "GAME OVER", 0
str_you_win:  db "YOU WIN", 0
str_restart:  db "SPACE=RESTART", 0

; Brick colors per row (6 rows)
brick_colors:
        dd 0x00FF2222          ; Red
        dd 0x00FF8822          ; Orange
        dd 0x00DDDD22          ; Yellow
        dd 0x0022CC22          ; Green
        dd 0x002288FF          ; Blue
        dd 0x00AA22FF          ; Purple

;=======================================================================
; BSS
;=======================================================================
align 4
game_state:     dd 0
score:          dd 0
hi_score:       dd 0
go_played:      db 0
hs_name_breakout: db "breakout", 0
lives:          dd 0
level:          dd 0
pad_x:          dd 0
ball_x:         dd 0
ball_y:         dd 0
ball_dx:        dd 0
ball_dy:        dd 0
bricks_left:    dd 0
bricks:         times MAX_BRICKS db 0
