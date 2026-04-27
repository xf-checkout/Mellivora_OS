; frogger.asm - Frogger-style road-and-river crossing for Mellivora OS
; VBE 1024x768x32bpp.
;   Arrow keys = hop  (one cell per press)
;   R          = restart
;   ESC / Q    = quit
;
; Reach the top row 5 times to win the level. Avoid cars on the road,
; ride logs/turtles across the river, don't fall in the water.
; Persistent high score (lives*lvl + frogs home) to /scores/frogger.
;-----------------------------------------------------------------------------

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

;-----------------------------------------------------------------------------
; Constants
;-----------------------------------------------------------------------------
GRID_W          equ 13
GRID_H          equ 13              ; rows 0..12 (0=goal, 12=start)
TILE            equ 48
ORIGIN_X        equ 80
ORIGIN_Y        equ 60
NUM_LANES       equ 11              ; rows 1..11 are lanes; 0 goal, 12 start
MAX_OBJ         equ 6               ; objects per lane
START_LIVES     equ 3
HOMES           equ 5               ; goal slots
WIN_FROGS       equ 5

; Tile / lane kinds
LK_NONE         equ 0
LK_CAR          equ 1
LK_TRUCK        equ 2
LK_LOG          equ 3
LK_TURTLE       equ 4

; Colours
COL_BG          equ 0x00101820
COL_GRASS       equ 0x00204020
COL_GRASS_HI    equ 0x00306030
COL_ROAD        equ 0x00181818
COL_ROAD_LINE   equ 0x00FFFF40
COL_RIVER       equ 0x001050C0
COL_GOAL_BAR    equ 0x00204050
COL_HOME_EMPTY  equ 0x00404040
COL_HOME_FROG   equ 0x0040E040
COL_FROG        equ 0x0050FF60
COL_FROG_DEAD   equ 0x00FF4040
COL_CAR1        equ 0x00FF4040
COL_CAR2        equ 0x00FFB040
COL_CAR3        equ 0x004080FF
COL_TRUCK       equ 0x00C0C0FF
COL_LOG         equ 0x00805020
COL_LOG_HI      equ 0x00B07040
COL_TURTLE      equ 0x0030C080
COL_TEXT        equ 0x00FFFFFF
COL_SCORE       equ 0x00FFEE40
COL_DEAD        equ 0x00FF6060
COL_WIN         equ 0x0044EE66

;-----------------------------------------------------------------------------
; start
;-----------------------------------------------------------------------------
start:
        VBE_GAME_INIT
        mov esi, hs_name_fg
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

        cmp dword [game_state], 0
        jne .no_key

        cmp al, KEY_UP
        jne .ck_dn
        cmp dword [frog_y], 0
        jle .no_key
        dec dword [frog_y]
        add dword [score], 10
        call audio_sfx_click
        call check_frog
        jmp .no_key
.ck_dn:
        cmp al, KEY_DOWN
        jne .ck_lf
        mov eax, [frog_y]
        cmp eax, GRID_H - 1
        jge .no_key
        inc dword [frog_y]
        call audio_sfx_click
        call check_frog
        jmp .no_key
.ck_lf:
        cmp al, KEY_LEFT
        jne .ck_rt
        cmp dword [frog_x], 0
        jle .no_key
        dec dword [frog_x]
        call audio_sfx_click
        call check_frog
        jmp .no_key
.ck_rt:
        cmp al, KEY_RIGHT
        jne .no_key
        mov eax, [frog_x]
        cmp eax, GRID_W - 1
        jge .no_key
        inc dword [frog_x]
        call audio_sfx_click
        call check_frog

.no_key:
        cmp dword [game_state], 0
        jne .sleep_long

        ; Step world every 3 polls
        inc dword [tick_div]
        cmp dword [tick_div], 3
        jl .draw_only
        mov dword [tick_div], 0

        call step_lanes
        call check_frog

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
; new_game - reset frog, lives, score, lanes, homes
;-----------------------------------------------------------------------------
new_game:
        pushad
        mov dword [game_state], 0
        mov dword [score], 0
        mov dword [lives], START_LIVES
        mov dword [frogs_home], 0
        mov dword [tick_div], 0
        ; clear homes
        xor ecx, ecx
.ng_homes:
        cmp ecx, HOMES
        jge .ng_homes_done
        mov dword [home_filled + ecx*4], 0
        inc ecx
        jmp .ng_homes
.ng_homes_done:
        call reset_frog
        call init_lanes
        popad
        ret

reset_frog:
        mov dword [frog_x], GRID_W / 2
        mov dword [frog_y], GRID_H - 1
        mov dword [frog_carry_dx10], 0
        ret

;-----------------------------------------------------------------------------
; init_lanes - hard-code lane kinds, speeds, and seed objects
;
; Layout (row -> lane index 0..10):
;   row 1 .. 5  : river  (logs / turtles / logs / turtles / logs)
;   row 6       : safe median (grass)
;   row 7 .. 11 : road  (cars/trucks)
;-----------------------------------------------------------------------------
init_lanes:
        pushad
        ; Lane kinds for rows 1..11 (index 0..10 in lane_kind[])
        ;  row 1 = log   (right)
        ;  row 2 = turtle (left)
        ;  row 3 = log   (left)
        ;  row 4 = turtle (right)
        ;  row 5 = log   (right)
        ;  row 6 = none  (median)
        ;  row 7 = car   (left)
        ;  row 8 = truck (right)
        ;  row 9 = car   (left)
        ;  row 10= car   (right)
        ;  row 11= car   (left)
        mov byte [lane_kind + 0], LK_LOG
        mov byte [lane_kind + 1], LK_TURTLE
        mov byte [lane_kind + 2], LK_LOG
        mov byte [lane_kind + 3], LK_TURTLE
        mov byte [lane_kind + 4], LK_LOG
        mov byte [lane_kind + 5], LK_NONE
        mov byte [lane_kind + 6], LK_CAR
        mov byte [lane_kind + 7], LK_TRUCK
        mov byte [lane_kind + 8], LK_CAR
        mov byte [lane_kind + 9], LK_CAR
        mov byte [lane_kind + 10], LK_CAR

        ; Direction (1=right, -1=left) and speeds (1/10 cell per tick)
        ; We store sub-cell pos as deci-cells (x*10).
        mov dword [lane_dir + 0*4],  1
        mov dword [lane_dir + 1*4], -1
        mov dword [lane_dir + 2*4], -1
        mov dword [lane_dir + 3*4],  1
        mov dword [lane_dir + 4*4],  1
        mov dword [lane_dir + 5*4],  0
        mov dword [lane_dir + 6*4], -1
        mov dword [lane_dir + 7*4],  1
        mov dword [lane_dir + 8*4], -1
        mov dword [lane_dir + 9*4],  1
        mov dword [lane_dir + 10*4], -1

        mov dword [lane_speed + 0*4], 2     ; deci-cells/tick
        mov dword [lane_speed + 1*4], 3
        mov dword [lane_speed + 2*4], 2
        mov dword [lane_speed + 3*4], 4
        mov dword [lane_speed + 4*4], 3
        mov dword [lane_speed + 5*4], 0
        mov dword [lane_speed + 6*4], 3
        mov dword [lane_speed + 7*4], 2
        mov dword [lane_speed + 8*4], 4
        mov dword [lane_speed + 9*4], 3
        mov dword [lane_speed + 10*4], 5

        ; Object lengths (cells)
        mov dword [lane_len + 0*4], 3
        mov dword [lane_len + 1*4], 2
        mov dword [lane_len + 2*4], 4
        mov dword [lane_len + 3*4], 2
        mov dword [lane_len + 4*4], 3
        mov dword [lane_len + 5*4], 0
        mov dword [lane_len + 6*4], 1
        mov dword [lane_len + 7*4], 3
        mov dword [lane_len + 8*4], 1
        mov dword [lane_len + 9*4], 1
        mov dword [lane_len + 10*4], 2

        ; Spacing (cells between starts of consecutive objects)
        mov dword [lane_gap + 0*4], 6
        mov dword [lane_gap + 1*4], 5
        mov dword [lane_gap + 2*4], 7
        mov dword [lane_gap + 3*4], 5
        mov dword [lane_gap + 4*4], 6
        mov dword [lane_gap + 5*4], 0
        mov dword [lane_gap + 6*4], 4
        mov dword [lane_gap + 7*4], 7
        mov dword [lane_gap + 8*4], 5
        mov dword [lane_gap + 9*4], 4
        mov dword [lane_gap + 10*4], 5

        ; Seed object positions (deci-cells)
        ; For each lane, place MAX_OBJ objects at x = i*gap*10 (mod world*10)
        xor ecx, ecx                ; lane index
.il_lane:
        cmp ecx, NUM_LANES
        jge .il_done
        movzx eax, byte [lane_kind + ecx]
        cmp eax, LK_NONE
        je .il_lane_next
        xor edx, edx                ; obj index
.il_obj:
        cmp edx, MAX_OBJ
        jge .il_lane_next
        mov eax, edx
        imul eax, [lane_gap + ecx*4]
        imul eax, 10
        ; lane_objs[lane*MAX_OBJ + obj] = eax
        mov esi, ecx
        imul esi, MAX_OBJ
        add esi, edx
        mov [lane_objs + esi*4], eax
        inc edx
        jmp .il_obj
.il_lane_next:
        inc ecx
        jmp .il_lane
.il_done:
        popad
        ret

;-----------------------------------------------------------------------------
; step_lanes - advance every object by lane_speed * lane_dir
;-----------------------------------------------------------------------------
step_lanes:
        pushad
        xor ecx, ecx                ; lane idx
.sl_lane:
        cmp ecx, NUM_LANES
        jge .sl_done
        mov eax, [lane_speed + ecx*4]
        test eax, eax
        jz .sl_lane_next
        mov ebx, [lane_dir + ecx*4]
        imul eax, ebx               ; signed step
        ; world width in deci-cells
        mov edi, GRID_W
        imul edi, 10                ; mod base
        ; for each obj: pos = (pos + step + base) mod base
        xor edx, edx
.sl_obj:
        cmp edx, MAX_OBJ
        jge .sl_lane_next
        mov esi, ecx
        imul esi, MAX_OBJ
        add esi, edx
        mov ebx, [lane_objs + esi*4]
        add ebx, eax
.sl_norm:
        cmp ebx, 0
        jge .sl_norm_hi
        add ebx, edi
        jmp .sl_norm
.sl_norm_hi:
        cmp ebx, edi
        jl .sl_store
        sub ebx, edi
        jmp .sl_norm_hi
.sl_store:
        mov [lane_objs + esi*4], ebx
        inc edx
        jmp .sl_obj
.sl_lane_next:
        inc ecx
        jmp .sl_lane
.sl_done:
        ; Carry frog if on a log/turtle
        mov eax, [frog_y]
        cmp eax, 1
        jl .sl_nocarry
        cmp eax, 5
        jg .sl_nocarry
        ; lane idx = frog_y - 1
        dec eax
        mov ebx, [lane_speed + eax*4]
        mov ecx, [lane_dir + eax*4]
        imul ebx, ecx               ; deci-cell step per tick
        add [frog_carry_dx10], ebx
        ; convert to whole cells
        mov eax, [frog_carry_dx10]
.sl_carry_pos:
        cmp eax, 10
        jl .sl_carry_neg
        sub eax, 10
        inc dword [frog_x]
        jmp .sl_carry_pos
.sl_carry_neg:
        cmp eax, -10
        jg .sl_carry_done
        add eax, 10
        dec dword [frog_x]
        jmp .sl_carry_neg
.sl_carry_done:
        mov [frog_carry_dx10], eax
        ; clamp / off-screen = drown
        mov ebx, [frog_x]
        cmp ebx, 0
        jl .sl_off
        cmp ebx, GRID_W - 1
        jg .sl_off
        jmp .sl_okay
.sl_off:
        call frog_die
        jmp .sl_skip
.sl_nocarry:
        mov dword [frog_carry_dx10], 0
.sl_okay:
.sl_skip:
        popad
        ret

;-----------------------------------------------------------------------------
; check_frog - based on frog cell, determine death / home / safe
;-----------------------------------------------------------------------------
check_frog:
        pushad
        mov eax, [frog_y]
        ; row 0 = goal row with HOMES slots
        test eax, eax
        jnz .cf_not_goal
        ; map x -> home idx: GRID_W=13, HOMES=5; valid x = 1,3,5,7,9,11
        mov ebx, [frog_x]
        ; idx = (x-1)/2 if x odd and 1..11
        mov eax, ebx
        sub eax, 1
        test eax, 1
        jnz .cf_goalfail
        sar eax, 1
        cmp eax, 0
        jl .cf_goalfail
        cmp eax, HOMES
        jge .cf_goalfail
        cmp dword [home_filled + eax*4], 0
        jne .cf_goalfail            ; already filled
        mov dword [home_filled + eax*4], 1
        add dword [score], 100
        inc dword [frogs_home]
        call audio_sfx_ok
        cmp dword [frogs_home], WIN_FROGS
        jge .cf_win
        call reset_frog
        jmp .cf_out
.cf_goalfail:
        ; Hit grass/wall in goal row -> die
        call frog_die
        jmp .cf_out
.cf_not_goal:
        ; Row 6 = median (safe). Row 12 = start (safe).
        cmp eax, 6
        je .cf_out
        cmp eax, GRID_H - 1
        je .cf_out

        ; Rows 1..5 = river. Need to be on a log/turtle.
        cmp eax, 1
        jl .cf_road
        cmp eax, 5
        jg .cf_road
        ; lane idx = y - 1
        dec eax
        push eax
        mov ebx, [frog_x]
        call on_object
        pop edx
        test eax, eax
        jz .cf_drown
        jmp .cf_out
.cf_drown:
        call frog_die
        jmp .cf_out

.cf_road:
        ; Rows 7..11 = road. Die if on a car/truck.
        cmp eax, 7
        jl .cf_out
        cmp eax, 11
        jg .cf_out
        sub eax, 1                  ; lane idx (y-1)
        push eax
        mov ebx, [frog_x]
        call on_object
        pop edx
        test eax, eax
        jz .cf_out
        call frog_die
.cf_out:
        popad
        ret

.cf_win:
        mov dword [game_state], 2
        mov esi, hs_name_fg
        mov ebx, [score]
        call hs_update
        mov [hi_score], eax
        call audio_sfx_win
        jmp .cf_out

;-----------------------------------------------------------------------------
; on_object  EAX=lane idx, EBX=cell x -> EAX=1 if any object covers x
;-----------------------------------------------------------------------------
on_object:
        pushad
        mov [oo_lane], eax
        mov [oo_x],    ebx
        mov eax, [lane_len + eax*4]
        test eax, eax
        jz .oo_miss
        mov [oo_len], eax
        mov dword [oo_idx], 0
.oo_loop:
        mov eax, [oo_idx]
        cmp eax, MAX_OBJ
        jge .oo_miss
        ; pos = lane_objs[lane*MAX_OBJ + idx]
        mov ecx, [oo_lane]
        imul ecx, MAX_OBJ
        add ecx, eax
        mov eax, [lane_objs + ecx*4]
        ; cell_start = pos / 10
        xor edx, edx
        mov ecx, 10
        div ecx                         ; eax = cell start
        ; for k = 0 .. len-1: if (start+k) mod GRID_W == frog_x -> hit
        xor ecx, ecx
.oo_k:
        cmp ecx, [oo_len]
        jge .oo_next
        mov edx, eax
        add edx, ecx
.oo_mod:
        cmp edx, GRID_W
        jl .oo_cmp
        sub edx, GRID_W
        jmp .oo_mod
.oo_cmp:
        cmp edx, [oo_x]
        je .oo_hit
        inc ecx
        jmp .oo_k
.oo_next:
        inc dword [oo_idx]
        jmp .oo_loop
.oo_hit:
        popad
        mov eax, 1
        ret
.oo_miss:
        popad
        xor eax, eax
        ret

oo_lane: dd 0
oo_x:    dd 0
oo_len:  dd 0
oo_idx:  dd 0

;-----------------------------------------------------------------------------
; frog_die
;-----------------------------------------------------------------------------
frog_die:
        push eax
        dec dword [lives]
        call audio_sfx_lose
        cmp dword [lives], 0
        jg .fd_reset
        mov dword [game_state], 1
        mov esi, hs_name_fg
        mov ebx, [score]
        call hs_update
        mov [hi_score], eax
        pop eax
        ret
.fd_reset:
        call reset_frog
        pop eax
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
        mov ecx, 18
        mov edx, str_title
        mov esi, COL_FROG
        mov eax, 4
        call vbe_draw_str

        call draw_field

        ; HUD on right
        mov ebx, 770
        mov ecx, 80
        mov edx, str_score
        mov esi, COL_TEXT
        mov eax, 2
        call vbe_draw_str
        mov ebx, 770
        mov ecx, 110
        mov edx, [score]
        mov esi, COL_SCORE
        mov eax, 3
        call vbe_draw_num
        mov ebx, 770
        mov ecx, 170
        mov edx, str_hi
        mov esi, COL_TEXT
        mov eax, 2
        call vbe_draw_str
        mov ebx, 770
        mov ecx, 200
        mov edx, [hi_score]
        mov esi, COL_SCORE
        mov eax, 3
        call vbe_draw_num
        mov ebx, 770
        mov ecx, 260
        mov edx, str_lives
        mov esi, COL_TEXT
        mov eax, 2
        call vbe_draw_str
        mov ebx, 770
        mov ecx, 290
        mov edx, [lives]
        mov esi, COL_FROG
        mov eax, 3
        call vbe_draw_num
        mov ebx, 770
        mov ecx, 350
        mov edx, str_home
        mov esi, COL_TEXT
        mov eax, 2
        call vbe_draw_str
        mov ebx, 770
        mov ecx, 380
        mov edx, [frogs_home]
        mov esi, COL_HOME_FROG
        mov eax, 3
        call vbe_draw_num

        mov ebx, 770
        mov ecx, 560
        mov edx, str_h1
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str
        mov ebx, 770
        mov ecx, 584
        mov edx, str_h2
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str
        mov ebx, 770
        mov ecx, 608
        mov edx, str_h3
        mov esi, COL_TEXT
        mov eax, 1
        call vbe_draw_str

        cmp dword [game_state], 1
        jne .da_chk_win
        mov ebx, 220
        mov ecx, 700
        mov edx, str_dead
        mov esi, COL_DEAD
        mov eax, 3
        call vbe_draw_str
        jmp .da_done
.da_chk_win:
        cmp dword [game_state], 2
        jne .da_done
        mov ebx, 240
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
; draw_field - terrain + objects + homes + frog
;-----------------------------------------------------------------------------
draw_field:
        pushad
        ; Row backgrounds: 0=goal_bar, 1..5=river, 6=median, 7..11=road, 12=start
        xor ecx, ecx
.df_row:
        cmp ecx, GRID_H
        jge .df_done
        ; pick colour
        mov esi, COL_GRASS
        cmp ecx, 0
        je .df_paint
        cmp ecx, 6
        je .df_paint
        cmp ecx, GRID_H - 1
        je .df_paint
        cmp ecx, 1
        jl .df_paint
        cmp ecx, 5
        jg .df_check_road
        mov esi, COL_RIVER
        jmp .df_paint
.df_check_road:
        cmp ecx, 7
        jl .df_paint
        cmp ecx, 11
        jg .df_paint
        mov esi, COL_ROAD
.df_paint:
        ; rect: x=ORIGIN_X, y=ORIGIN_Y+ecx*TILE, w=GRID_W*TILE, h=TILE
        push ecx
        mov ebx, ORIGIN_X
        mov eax, ecx
        imul eax, TILE
        add eax, ORIGIN_Y
        mov ecx, eax
        mov edx, GRID_W * TILE
        push esi                    ; colour
        mov esi, TILE
        pop edi                     ; col -> edi
        call vbe_fill_rect
        pop ecx
        inc ecx
        jmp .df_row
.df_done:

        ; Lane decorations: road dashed lines
        mov ecx, 7
.df_road_lines:
        cmp ecx, 11
        jg .df_road_done
        ; horizontal dashed line at y = ORIGIN_Y + ecx*TILE
        mov eax, ecx
        imul eax, TILE
        add eax, ORIGIN_Y
        mov edi, eax                ; y
        xor ebx, ebx                ; dash idx
.df_dash:
        cmp ebx, GRID_W
        jge .df_dash_done
        mov eax, ebx
        imul eax, TILE
        add eax, ORIGIN_X
        add eax, TILE/4
        push ecx
        push ebx
        push edi
        mov ebx, eax
        mov ecx, edi
        mov edx, TILE/2
        mov esi, COL_ROAD_LINE
        call vbe_draw_hline
        pop edi
        pop ebx
        pop ecx
        inc ebx
        jmp .df_dash
.df_dash_done:
        inc ecx
        jmp .df_road_lines
.df_road_done:

        ; Goal bar: 5 home slots at row 0
        xor ecx, ecx
.df_homes:
        cmp ecx, HOMES
        jge .df_homes_done
        ; cell x = 1 + ecx*2
        mov eax, ecx
        shl eax, 1
        inc eax                     ; cell x
        push ecx
        push eax
        ; rect
        imul eax, TILE
        add eax, ORIGIN_X + 4
        mov ebx, eax
        mov ecx, ORIGIN_Y + 4
        mov edx, TILE - 8
        mov esi, TILE - 8
        pop eax
        pop ecx
        push ecx
        cmp dword [home_filled + ecx*4], 0
        jne .df_home_full
        mov edi, COL_HOME_EMPTY
        jmp .df_home_paint
.df_home_full:
        mov edi, COL_HOME_FROG
.df_home_paint:
        call vbe_fill_rect
        pop ecx
        inc ecx
        jmp .df_homes
.df_homes_done:

        ; Lane objects (rows 1..11, lane idx 0..10)
        xor ecx, ecx                ; lane idx
.df_lanes:
        cmp ecx, NUM_LANES
        jge .df_lanes_done
        movzx eax, byte [lane_kind + ecx]
        cmp eax, LK_NONE
        je .df_lane_next
        ; row pixel y
        mov eax, ecx
        inc eax                     ; row = lane+1
        imul eax, TILE
        add eax, ORIGIN_Y + 4
        mov [.df_y], eax
        ; pick colour by kind
        mov [.df_kind], ecx
        movzx eax, byte [lane_kind + ecx]
        cmp eax, LK_CAR
        jne .df_ck_truck
        ; rotate car colours by lane: car1/car2/car3
        mov ebx, ecx
        and ebx, 3
        cmp ebx, 0
        jne .df_ck_c2
        mov edi, COL_CAR1
        jmp .df_col_set
.df_ck_c2:
        cmp ebx, 1
        jne .df_ck_c3
        mov edi, COL_CAR2
        jmp .df_col_set
.df_ck_c3:
        mov edi, COL_CAR3
        jmp .df_col_set
.df_ck_truck:
        cmp eax, LK_TRUCK
        jne .df_ck_log
        mov edi, COL_TRUCK
        jmp .df_col_set
.df_ck_log:
        cmp eax, LK_LOG
        jne .df_ck_turt
        mov edi, COL_LOG
        jmp .df_col_set
.df_ck_turt:
        mov edi, COL_TURTLE
.df_col_set:
        mov [.df_col], edi

        ; Draw each object
        xor edx, edx                ; obj idx
.df_obj:
        cmp edx, MAX_OBJ
        jge .df_lane_next
        mov esi, ecx
        imul esi, MAX_OBJ
        add esi, edx
        mov eax, [lane_objs + esi*4]
        ; cell start = eax / 10
        push edx
        xor edx, edx
        mov ebx, 10
        div ebx
        pop edx
        ; eax = cell start (0..GRID_W-1)
        mov esi, [lane_len + ecx*4]
        ; pixel x = ORIGIN_X + cell*TILE + 4
        push eax
        imul eax, TILE
        add eax, ORIGIN_X + 4
        mov ebx, eax
        mov ecx, [.df_y]
        ; width = len*TILE - 8
        push esi
        imul esi, TILE
        sub esi, 8
        ; if would overflow right edge, clamp width
        push edx
        mov edx, ORIGIN_X + GRID_W * TILE
        sub edx, ebx
        cmp esi, edx
        jle .df_w_ok
        mov esi, edx
        sub esi, 4
.df_w_ok:
        pop edx
        ; final args: ebx=x, ecx=y, edx=w, esi=h, edi=col
        push esi                    ; save width
        mov esi, TILE - 8           ; h
        mov edi, [.df_col]
        ; need w in edx
        pop edx                     ; was width into esi -> now restored as w via this path
        ; wait: stack order. We pushed esi (width) last, so pop gives width.
        call vbe_fill_rect
        pop esi                     ; (the earlier 'push esi' for len)
        pop eax                     ; cell start
        ; Restore lane idx (ecx) — clobbered by call
        mov ecx, [.df_kind]
        inc edx
        jmp .df_obj
.df_lane_next:
        mov ecx, [.df_kind]
        inc ecx
        jmp .df_lanes
.df_lanes_done:

        ; Frog
        mov eax, [frog_x]
        imul eax, TILE
        add eax, ORIGIN_X + TILE/2
        mov ebx, eax
        mov eax, [frog_y]
        imul eax, TILE
        add eax, ORIGIN_Y + TILE/2
        mov ecx, eax
        mov edx, TILE/2 - 4
        cmp dword [game_state], 1
        jne .df_frog_alive
        mov esi, COL_FROG_DEAD
        jmp .df_frog_paint
.df_frog_alive:
        mov esi, COL_FROG
.df_frog_paint:
        call vbe_fill_circle
        popad
        ret

.df_y:    dd 0
.df_kind: dd 0
.df_col:  dd 0

;-----------------------------------------------------------------------------
; Strings
;-----------------------------------------------------------------------------
str_title       db "FROGGER", 0
str_score       db "SCORE", 0
str_hi          db "HIGH", 0
str_lives       db "LIVES", 0
str_home        db "HOME", 0
str_dead        db "GAME OVER  -  R = RESTART", 0
str_won         db "ALL FROGS HOME!  -  R = NEW", 0
str_h1          db "ARROWS: HOP", 0
str_h2          db "R: RESTART  ESC: QUIT", 0
str_h3          db "FILL ALL 5 HOMES TO WIN", 0

hs_name_fg      db "frogger", 0

; --- Mutable state ---
frog_x:         dd 6
frog_y:         dd 12
frog_carry_dx10: dd 0
score:          dd 0
hi_score:       dd 0
lives:          dd 3
frogs_home:     dd 0
tick_div:       dd 0
game_state:     dd 0    ; 0=play, 1=dead, 2=won

home_filled:    times HOMES dd 0
lane_kind:      times NUM_LANES db 0
lane_dir:       times NUM_LANES dd 0
lane_speed:     times NUM_LANES dd 0
lane_len:       times NUM_LANES dd 0
lane_gap:       times NUM_LANES dd 0
lane_objs:      times NUM_LANES * MAX_OBJ dd 0
