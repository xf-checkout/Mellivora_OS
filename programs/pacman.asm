; pacman.asm - Pac-Man-style maze chase for Mellivora OS
; VBE 1024x768x32bpp.
;   Arrow keys = move        R = restart maze       ESC / Q = quit
;
; Eat all dots to win the level. Touching a ghost ends the game.
; Eating a power pellet (4 corners) lets you eat ghosts for ~6 sec.
; Persistent high score saved to /scores/pacman.
;-----------------------------------------------------------------------------

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

;-----------------------------------------------------------------------------
; Constants
;-----------------------------------------------------------------------------
MAZE_W          equ 21
MAZE_H          equ 21
TILE            equ 28
ORIGIN_X        equ 220
ORIGIN_Y        equ 100
NUM_GHOSTS      equ 4
FRIGHT_FRAMES   equ 200             ; ~6s at ~30fps

; Tile codes (in maze[])
T_EMPTY         equ 0
T_WALL          equ 1
T_DOT           equ 2
T_PELLET        equ 3

; Direction codes
D_NONE          equ 0
D_UP            equ 1
D_DOWN          equ 2
D_LEFT          equ 3
D_RIGHT         equ 4

; Colours
COL_BG          equ 0x00000000
COL_WALL        equ 0x002233CC
COL_WALL_HI     equ 0x004466FF
COL_DOT         equ 0x00FFCC88
COL_PELLET      equ 0x00FFEE40
COL_PAC         equ 0x00FFE020
COL_GHOST_R     equ 0x00FF4040
COL_GHOST_P     equ 0x00FFA0E0
COL_GHOST_C     equ 0x0040E0FF
COL_GHOST_O     equ 0x00FFA040
COL_GHOST_F     equ 0x004060FF       ; frightened
COL_TEXT        equ 0x00FFFFFF
COL_SCORE       equ 0x00FFEE40
COL_DEAD        equ 0x00FF6060
COL_WIN         equ 0x0044EE66

;-----------------------------------------------------------------------------
; start
;-----------------------------------------------------------------------------
start:
        VBE_GAME_INIT
        ; Load high score from /scores/pacman
        mov esi, hs_name_pm
        call hs_load
        mov [hi_score], eax
        call new_game
        call draw_all

.main_loop:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je .no_key

        cmp al, KEY_ESC
        je .quit
        cmp al, 'q'
        je .quit
        cmp al, 'Q'
        je .quit
        cmp al, 'r'
        je .restart
        cmp al, 'R'
        je .restart

        cmp dword [game_state], 0   ; 0 = playing
        jne .no_key

        cmp al, KEY_UP
        jne .ck_dn
        mov dword [pac_want], D_UP
        jmp .no_key
.ck_dn:
        cmp al, KEY_DOWN
        jne .ck_lf
        mov dword [pac_want], D_DOWN
        jmp .no_key
.ck_lf:
        cmp al, KEY_LEFT
        jne .ck_rt
        mov dword [pac_want], D_LEFT
        jmp .no_key
.ck_rt:
        cmp al, KEY_RIGHT
        jne .no_key
        mov dword [pac_want], D_RIGHT

.no_key:
        ; If game over, just sleep and wait for R/Q
        cmp dword [game_state], 0
        jne .sleep_long

        ; Tick game every 4 polls (~80ms) for slower pace
        inc dword [tick_div]
        cmp dword [tick_div], 4
        jl .draw_only
        mov dword [tick_div], 0

        call step_pac
        call step_ghosts
        call check_collisions
        cmp dword [game_state], 0
        jne .draw_only
        cmp dword [dot_count], 0
        jne .ck_fright
        ; Win!
        mov dword [game_state], 2
        ; persist high score
        mov esi, hs_name_pm
        mov ebx, [score]
        call hs_update
        mov [hi_score], eax
        call audio_sfx_win
        jmp .draw_only

.ck_fright:
        cmp dword [fright_timer], 0
        jle .draw_only
        dec dword [fright_timer]

.draw_only:
        call draw_all
        mov eax, SYS_SLEEP
        mov ebx, 2
        int 0x80
        jmp .main_loop

.sleep_long:
        call draw_all
        mov eax, SYS_SLEEP
        mov ebx, 4
        int 0x80
        jmp .main_loop

.restart:
        call new_game
        jmp .draw_only

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;-----------------------------------------------------------------------------
; new_game - copy maze template, reset state
;-----------------------------------------------------------------------------
new_game:
        pushad
        mov dword [game_state], 0
        mov dword [score], 0
        mov dword [tick_div], 0
        mov dword [fright_timer], 0
        mov dword [pac_want], D_LEFT
        mov dword [pac_dir], D_LEFT

        ; Copy template into maze[]
        mov esi, maze_template
        mov edi, maze
        mov ecx, MAZE_W * MAZE_H
        rep movsb

        ; Count dots
        xor ecx, ecx
        xor ebx, ebx
.cd_loop:
        cmp ecx, MAZE_W * MAZE_H
        jge .cd_done
        movzx eax, byte [maze + ecx]
        cmp eax, T_DOT
        je .cd_inc
        cmp eax, T_PELLET
        je .cd_inc
        jmp .cd_next
.cd_inc:
        inc ebx
.cd_next:
        inc ecx
        jmp .cd_loop
.cd_done:
        mov [dot_count], ebx

        ; Pac-Man start: middle col, near bottom (row 18 col 8 is a dot)
        mov dword [pac_x], 8
        mov dword [pac_y], 18

        ; Ghosts: 4 corners (just inside walls)
        mov dword [g_x + 0*4], 1
        mov dword [g_y + 0*4], 1
        mov dword [g_dir + 0*4], D_RIGHT
        mov dword [g_x + 1*4], 19
        mov dword [g_y + 1*4], 1
        mov dword [g_dir + 1*4], D_LEFT
        mov dword [g_x + 2*4], 1
        mov dword [g_y + 2*4], 19
        mov dword [g_dir + 2*4], D_RIGHT
        mov dword [g_x + 3*4], 19
        mov dword [g_y + 3*4], 19
        mov dword [g_dir + 3*4], D_LEFT
        popad
        ret

;-----------------------------------------------------------------------------
; can_move  EAX=tx, EBX=ty -> EAX=1 if walkable, else 0
;-----------------------------------------------------------------------------
can_move:
        push ecx
        push edx
        ; bounds
        cmp eax, 0
        jl .cm_no
        cmp eax, MAZE_W
        jge .cm_no
        cmp ebx, 0
        jl .cm_no
        cmp ebx, MAZE_H
        jge .cm_no
        mov ecx, ebx
        imul ecx, MAZE_W
        add ecx, eax
        movzx edx, byte [maze + ecx]
        cmp edx, T_WALL
        je .cm_no
        mov eax, 1
        pop edx
        pop ecx
        ret
.cm_no:
        xor eax, eax
        pop edx
        pop ecx
        ret

;-----------------------------------------------------------------------------
; try_step  EBX=dir, ECX=*x, EDX=*y -> step *x,*y by dir if walkable.
; Returns EAX=1 if moved else 0.
;-----------------------------------------------------------------------------
try_step:
        push esi
        push edi
        mov esi, [ecx]              ; current x
        mov edi, [edx]              ; current y
        cmp ebx, D_UP
        jne .ts_dn
        dec edi
        jmp .ts_chk
.ts_dn:
        cmp ebx, D_DOWN
        jne .ts_lf
        inc edi
        jmp .ts_chk
.ts_lf:
        cmp ebx, D_LEFT
        jne .ts_rt
        dec esi
        jmp .ts_chk
.ts_rt:
        cmp ebx, D_RIGHT
        jne .ts_no
        inc esi
.ts_chk:
        push eax
        push ebx
        mov eax, esi
        mov ebx, edi
        call can_move
        mov ebp, eax                ; flag
        pop ebx
        pop eax
        test ebp, ebp
        jz .ts_no
        mov [ecx], esi
        mov [edx], edi
        mov eax, 1
        pop edi
        pop esi
        ret
.ts_no:
        xor eax, eax
        pop edi
        pop esi
        ret

;-----------------------------------------------------------------------------
; step_pac
;-----------------------------------------------------------------------------
step_pac:
        pushad
        ; Try desired dir first
        mov ebx, [pac_want]
        mov ecx, pac_x
        mov edx, pac_y
        call try_step
        test eax, eax
        jz .sp_keep
        mov eax, [pac_want]
        mov [pac_dir], eax
        jmp .sp_eat
.sp_keep:
        mov ebx, [pac_dir]
        mov ecx, pac_x
        mov edx, pac_y
        call try_step
.sp_eat:
        ; Eat tile under pac
        mov eax, [pac_y]
        imul eax, MAZE_W
        add eax, [pac_x]
        movzx ebx, byte [maze + eax]
        cmp ebx, T_DOT
        je .sp_dot
        cmp ebx, T_PELLET
        je .sp_pellet
        jmp .sp_done
.sp_dot:
        mov byte [maze + eax], T_EMPTY
        add dword [score], 10
        dec dword [dot_count]
        call audio_sfx_click
        jmp .sp_done
.sp_pellet:
        mov byte [maze + eax], T_EMPTY
        add dword [score], 50
        dec dword [dot_count]
        mov dword [fright_timer], FRIGHT_FRAMES
        call audio_sfx_ok
.sp_done:
        popad
        ret

;-----------------------------------------------------------------------------
; ghost_choose_dir  EBX=ghost index -> updates g_dir[ebx]
; Pick direction toward Pac (or away if frightened), avoiding walls and
; immediate reverse if other moves available.
;-----------------------------------------------------------------------------
ghost_choose_dir:
        pushad
        mov esi, ebx                ; esi = ghost index

        ; Try each of 4 dirs, score each by manhattan distance to pac
        ; Sign: smaller is better (chase) or larger is better (frightened).
        mov dword [.best_score], -1
        mov dword [.best_dir], 0
        xor edi, edi                ; dir index 1..4
.gcd_loop:
        inc edi
        cmp edi, 4
        jg .gcd_done

        ; Skip exact reverse if at least one other dir worked
        ; (simple: only forbid reverse always; if stuck, can_move test fails)
        mov eax, [g_dir + esi*4]
        ; reverse(D_UP)=D_DOWN, etc
        cmp eax, D_UP
        jne .gcd_no_rv1
        cmp edi, D_DOWN
        je .gcd_skip
.gcd_no_rv1:
        cmp eax, D_DOWN
        jne .gcd_no_rv2
        cmp edi, D_UP
        je .gcd_skip
.gcd_no_rv2:
        cmp eax, D_LEFT
        jne .gcd_no_rv3
        cmp edi, D_RIGHT
        je .gcd_skip
.gcd_no_rv3:
        cmp eax, D_RIGHT
        jne .gcd_no_rv4
        cmp edi, D_LEFT
        je .gcd_skip
.gcd_no_rv4:

        ; Compute candidate (nx,ny)
        mov eax, [g_x + esi*4]
        mov ebx, [g_y + esi*4]
        cmp edi, D_UP
        jne .gcd_d2
        dec ebx
        jmp .gcd_have
.gcd_d2:
        cmp edi, D_DOWN
        jne .gcd_d3
        inc ebx
        jmp .gcd_have
.gcd_d3:
        cmp edi, D_LEFT
        jne .gcd_d4
        dec eax
        jmp .gcd_have
.gcd_d4:
        inc eax
.gcd_have:
        push eax
        push ebx
        call can_move
        mov ebp, eax
        pop ebx
        pop eax
        test ebp, ebp
        jz .gcd_skip

        ; |nx - pac_x| + |ny - pac_y|
        push eax
        push ebx
        sub eax, [pac_x]
        jns .gcd_ax
        neg eax
.gcd_ax:
        sub ebx, [pac_y]
        jns .gcd_bx
        neg ebx
.gcd_bx:
        add eax, ebx
        mov ecx, eax                ; ecx = score
        pop ebx
        pop eax

        ; If frightened, invert (prefer larger distance => use -score)
        cmp dword [fright_timer], 0
        jle .gcd_chase
        neg ecx                     ; smaller is better still
.gcd_chase:
        ; Compare to best_score (treat -1 as "unset" => take first)
        cmp dword [.best_score], -1
        je .gcd_take
        mov edx, [.best_score]
        cmp ecx, edx
        jge .gcd_skip
.gcd_take:
        mov [.best_score], ecx
        mov [.best_dir], edi
.gcd_skip:
        jmp .gcd_loop

.gcd_done:
        ; If we found a dir, set it; otherwise keep current
        mov eax, [.best_dir]
        test eax, eax
        jz .gcd_keep
        mov [g_dir + esi*4], eax
.gcd_keep:
        popad
        ret

.best_score: dd 0
.best_dir:   dd 0

;-----------------------------------------------------------------------------
; step_ghosts
;-----------------------------------------------------------------------------
step_ghosts:
        pushad
        xor ebx, ebx
.sg_loop:
        cmp ebx, NUM_GHOSTS
        jge .sg_done
        push ebx
        call ghost_choose_dir
        pop ebx
        ; Now actually move
        push ebx
        mov ecx, ebx
        shl ecx, 2
        lea ecx, [g_x + ecx]
        mov edx, [esp]              ; ebx
        shl edx, 2
        lea edx, [g_y + edx]
        mov ebx, [g_dir + ebx*4]
        call try_step
        pop ebx
        inc ebx
        jmp .sg_loop
.sg_done:
        popad
        ret

;-----------------------------------------------------------------------------
; check_collisions - if pac shares cell with any ghost:
;   * frightened: eat ghost (+200, respawn ghost at corner)
;   * else: lose
;-----------------------------------------------------------------------------
check_collisions:
        pushad
        xor ebx, ebx
.cc_loop:
        cmp ebx, NUM_GHOSTS
        jge .cc_done
        mov eax, [g_x + ebx*4]
        cmp eax, [pac_x]
        jne .cc_next
        mov eax, [g_y + ebx*4]
        cmp eax, [pac_y]
        jne .cc_next
        ; Collision!
        cmp dword [fright_timer], 0
        jle .cc_dead
        ; Eat ghost: +200, respawn at top-left corner
        add dword [score], 200
        mov dword [g_x + ebx*4], 1
        mov dword [g_y + ebx*4], 1
        call audio_sfx_ok
        jmp .cc_next
.cc_dead:
        mov dword [game_state], 1
        ; Persist high score on death too
        mov esi, hs_name_pm
        mov edx, [score]
        push edx
        mov ebx, edx
        call hs_update
        pop edx
        mov [hi_score], eax
        call audio_sfx_lose
        jmp .cc_done
.cc_next:
        inc ebx
        jmp .cc_loop
.cc_done:
        popad
        ret

;-----------------------------------------------------------------------------
; draw_all
;-----------------------------------------------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Title
        mov ebx, 60
        mov ecx, 30
        mov edx, str_title
        mov esi, COL_PAC
        mov eax, 4
        call vbe_draw_str

        ; HUD - score + hi
        mov ebx, 750
        mov ecx, 60
        mov edx, str_score
        mov esi, COL_TEXT
        mov eax, 2
        call vbe_draw_str
        mov ebx, 750
        mov ecx, 90
        mov edx, [score]
        mov esi, COL_SCORE
        mov eax, 3
        call vbe_draw_num
        mov ebx, 750
        mov ecx, 150
        mov edx, str_hi
        mov esi, COL_TEXT
        mov eax, 2
        call vbe_draw_str
        mov ebx, 750
        mov ecx, 180
        mov edx, [hi_score]
        mov esi, COL_SCORE
        mov eax, 3
        call vbe_draw_num
        mov ebx, 750
        mov ecx, 240
        mov edx, str_dots
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str
        mov ebx, 750
        mov ecx, 264
        mov edx, [dot_count]
        mov esi, COL_DOT
        mov eax, 2
        call vbe_draw_num

        ; Help
        mov ebx, 750
        mov ecx, 540
        mov edx, str_h1
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str
        mov ebx, 750
        mov ecx, 564
        mov edx, str_h2
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str
        mov ebx, 750
        mov ecx, 588
        mov edx, str_h3
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str

        call draw_maze
        call draw_pac
        call draw_ghosts

        ; State banner
        cmp dword [game_state], 1
        jne .da_chk_win
        mov ebx, 280
        mov ecx, 700
        mov edx, str_dead
        mov esi, COL_DEAD
        mov eax, 3
        call vbe_draw_str
        jmp .da_done
.da_chk_win:
        cmp dword [game_state], 2
        jne .da_done
        mov ebx, 300
        mov ecx, 700
        mov edx, str_won
        mov esi, COL_WIN
        mov eax, 3
        call vbe_draw_str
.da_done:
        VBE_GAME_PRESENT
        popad
        ret

;-----------------------------------------------------------------------------
; draw_maze - simple, register-safe loop
;-----------------------------------------------------------------------------
draw_maze:
        pushad
        mov dword [dm_row], 0
.dm_r:
        mov eax, [dm_row]
        cmp eax, MAZE_H
        jge .dm_done
        mov dword [dm_col], 0
.dm_c:
        mov eax, [dm_col]
        cmp eax, MAZE_W
        jge .dm_r_n

        ; Compute tile = maze[row*MAZE_W + col]
        mov eax, [dm_row]
        imul eax, MAZE_W
        add eax, [dm_col]
        movzx eax, byte [maze + eax]
        mov [dm_tile], eax

        ; Pixel x = ORIGIN_X + col*TILE
        mov eax, [dm_col]
        imul eax, TILE
        add eax, ORIGIN_X
        mov [dm_px], eax
        ; Pixel y = ORIGIN_Y + row*TILE
        mov eax, [dm_row]
        imul eax, TILE
        add eax, ORIGIN_Y
        mov [dm_py], eax

        cmp dword [dm_tile], T_WALL
        je .dm_wall
        cmp dword [dm_tile], T_DOT
        je .dm_dot
        cmp dword [dm_tile], T_PELLET
        je .dm_pellet
        jmp .dm_step

.dm_wall:
        mov ebx, [dm_px]
        mov ecx, [dm_py]
        mov edx, TILE
        mov esi, TILE
        mov edi, COL_WALL
        call vbe_fill_rect
        mov ebx, [dm_px]
        mov ecx, [dm_py]
        mov edx, TILE
        mov esi, COL_WALL_HI
        call vbe_draw_hline
        mov ebx, [dm_px]
        mov ecx, [dm_py]
        mov edx, TILE
        mov esi, COL_WALL_HI
        call vbe_draw_vline
        jmp .dm_step

.dm_dot:
        mov ebx, [dm_px]
        add ebx, TILE/2 - 2
        mov ecx, [dm_py]
        add ecx, TILE/2 - 2
        mov edx, 4
        mov esi, 4
        mov edi, COL_DOT
        call vbe_fill_rect
        jmp .dm_step

.dm_pellet:
        mov ebx, [dm_px]
        add ebx, TILE/2 - 4
        mov ecx, [dm_py]
        add ecx, TILE/2 - 4
        mov edx, 8
        mov esi, 8
        mov edi, COL_PELLET
        call vbe_fill_rect

.dm_step:
        inc dword [dm_col]
        jmp .dm_c
.dm_r_n:
        inc dword [dm_row]
        jmp .dm_r
.dm_done:
        popad
        ret

dm_row:  dd 0
dm_col:  dd 0
dm_tile: dd 0
dm_px:   dd 0
dm_py:   dd 0

;-----------------------------------------------------------------------------
; draw_pac
;-----------------------------------------------------------------------------
draw_pac:
        pushad
        mov eax, [pac_x]
        imul eax, TILE
        add eax, ORIGIN_X + TILE/2
        mov ebx, eax
        mov eax, [pac_y]
        imul eax, TILE
        add eax, ORIGIN_Y + TILE/2
        mov ecx, eax
        mov edx, TILE/2 - 2
        mov esi, COL_PAC
        call vbe_fill_circle
        popad
        ret

;-----------------------------------------------------------------------------
; draw_ghosts
;-----------------------------------------------------------------------------
draw_ghosts:
        pushad
        xor edi, edi                ; ghost index
.dg_loop:
        cmp edi, NUM_GHOSTS
        jge .dg_done
        ; centre x,y
        mov eax, [g_x + edi*4]
        imul eax, TILE
        add eax, ORIGIN_X + TILE/2
        mov ebx, eax
        mov eax, [g_y + edi*4]
        imul eax, TILE
        add eax, ORIGIN_Y + TILE/2
        mov ecx, eax
        mov edx, TILE/2 - 3
        ; pick colour
        cmp dword [fright_timer], 0
        jle .dg_normal
        mov esi, COL_GHOST_F
        jmp .dg_paint
.dg_normal:
        mov esi, [ghost_cols + edi*4]
.dg_paint:
        call vbe_fill_circle
        inc edi
        jmp .dg_loop
.dg_done:
        popad
        ret

;-----------------------------------------------------------------------------
; Data
;-----------------------------------------------------------------------------

ghost_cols:
        dd COL_GHOST_R, COL_GHOST_P, COL_GHOST_C, COL_GHOST_O

str_title       db "PAC-MAN", 0
str_score       db "SCORE", 0
str_hi          db "HIGH", 0
str_dots        db "DOTS LEFT", 0
str_dead        db "GAME OVER  -  R = RESTART", 0
str_won         db "YOU WIN!  -  R = NEW GAME", 0
str_h1          db "ARROWS: MOVE", 0
str_h2          db "R: RESTART  ESC: QUIT", 0
str_h3          db "DOT=10  PELLET=50  GHOST=200", 0

hs_name_pm      db "pacman", 0

; Maze template: 21x21
;   1 = wall, 2 = dot, 3 = power pellet, 0 = empty
maze_template:
        db 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
        db 1,3,2,2,2,2,2,2,2,2,1,2,2,2,2,2,2,2,2,3,1
        db 1,2,1,1,2,1,1,1,2,2,2,2,2,1,1,1,2,1,1,2,1
        db 1,2,2,2,2,2,2,1,2,1,1,1,2,1,2,2,2,2,2,2,1
        db 1,1,1,1,1,2,2,1,2,2,2,2,2,1,2,2,1,1,1,1,1
        db 1,2,2,2,2,2,2,1,1,1,1,1,1,1,2,2,2,2,2,2,1
        db 1,2,1,1,2,1,2,2,2,2,2,2,2,2,2,1,2,1,1,2,1
        db 1,2,1,1,2,1,2,1,1,1,1,1,1,1,2,1,2,1,1,2,1
        db 1,2,2,2,2,2,2,1,2,2,2,2,2,1,2,2,2,2,2,2,1
        db 1,1,1,2,1,1,2,1,2,1,1,1,2,1,2,1,1,2,1,1,1
        db 1,2,2,2,2,2,2,2,2,1,0,1,2,2,2,2,2,2,2,2,1
        db 1,1,1,2,1,1,2,1,2,1,1,1,2,1,2,1,1,2,1,1,1
        db 1,2,2,2,2,2,2,1,2,2,2,2,2,1,2,2,2,2,2,2,1
        db 1,2,1,1,2,1,2,1,1,1,1,1,1,1,2,1,2,1,1,2,1
        db 1,2,1,1,2,1,2,2,2,2,2,2,2,2,2,1,2,1,1,2,1
        db 1,2,2,2,2,2,2,1,1,1,1,1,1,1,2,2,2,2,2,2,1
        db 1,1,1,1,1,2,2,1,2,2,2,2,2,1,2,2,1,1,1,1,1
        db 1,2,2,2,2,2,2,1,2,1,1,1,2,1,2,2,2,2,2,2,1
        db 1,2,1,1,2,1,1,1,2,2,2,2,2,1,1,1,2,1,1,2,1
        db 1,3,2,2,2,2,2,2,2,2,1,2,2,2,2,2,2,2,2,3,1
        db 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

; --- Mutable state ---
maze:           times MAZE_W * MAZE_H db 0
pac_x:          dd 8
pac_y:          dd 18
pac_dir:        dd D_LEFT
pac_want:       dd D_LEFT
g_x:            times NUM_GHOSTS dd 0
g_y:            times NUM_GHOSTS dd 0
g_dir:          times NUM_GHOSTS dd D_RIGHT
score:          dd 0
hi_score:       dd 0
dot_count:      dd 0
fright_timer:   dd 0
tick_div:       dd 0
game_state:     dd 0    ; 0=play, 1=dead, 2=won
