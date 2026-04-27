; 2048.asm - 2048 VBE graphics game for Mellivora OS
; Slide tiles on a 4x4 board.  Merge matching tiles.  Reach 2048!

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/highscore.inc"
%include "lib/audio.inc"

BOARD_SZ    equ 4
CELL_SZ     equ 90
CELL_GAP    equ 8
BOARD_X     equ 120    ; (640 - 4*90 - 3*8) / 2 = 120? ~ok
BOARD_Y     equ 58
BOARD_W     equ (BOARD_SZ * CELL_SZ + (BOARD_SZ - 1) * CELL_GAP)    ; 390
BOARD_H     equ BOARD_W

COL_BG      equ 0x00FAF8EF
COL_BOARD   equ 0x00BBADA0
COL_EMPTY   equ 0x00CDC1B4
COL_SCORE_BG equ 0x00BBADA0
COL_TEXT_DK  equ 0x00776E65
COL_TEXT_LT  equ 0x00F9F6F2

; Tile colours by power of 2 (index 0 = empty, 1 = 2, 2 = 4, ... 11 = 2048)
; stored as 12 dwords
tile_colours:
        dd 0x00CDC1B4   ; 0 empty
        dd 0x00EEE4DA   ; 2
        dd 0x00EDE0C8   ; 4
        dd 0x00F2B179   ; 8
        dd 0x00F59563   ; 16
        dd 0x00F67C5F   ; 32
        dd 0x00F65E3B   ; 64
        dd 0x00EDCF72   ; 128
        dd 0x00EDCC61   ; 256
        dd 0x00EDC850   ; 512
        dd 0x00EDC53F   ; 1024
        dd 0x0000AA00   ; 2048 (green!)

start:
        VBE_GAME_INIT
        call init_game

.main_loop:
        call draw_scene
        VBE_GAME_PRESENT

        cmp byte [game_over], 1
        je  .poll_over
        cmp byte [game_won], 1
        je  .poll_over

.poll_play:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .main_loop
        cmp  eax, KEY_ESC
        je   .quit
        cmp  eax, KEY_Q
        je   .quit
        cmp  eax, 'Q'
        je   .quit
        cmp  eax, KEY_R
        je   .restart
        cmp  eax, KEY_UP
        je   .do_up
        cmp  eax, KEY_W
        je   .do_up
        cmp  eax, KEY_DOWN
        je   .do_down
        cmp  eax, KEY_S
        je   .do_down
        cmp  eax, KEY_LEFT
        je   .do_left
        cmp  eax, KEY_A
        je   .do_left
        cmp  eax, KEY_RIGHT
        je   .do_right
        cmp  eax, KEY_D
        je   .do_right
        jmp  .main_loop

.do_up:
        call slide_up
        jmp  .after_slide
.do_down:
        call slide_down
        jmp  .after_slide
.do_left:
        call slide_left
        jmp  .after_slide
.do_right:
        call slide_right
        jmp  .after_slide

.after_slide:
        ; only add tile if board changed
        cmp  byte [moved], 1
        jne  .main_loop
        call add_random_tile
        call check_win
        call check_game_over
        jmp  .main_loop

.poll_over:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je  .main_loop
        cmp eax, KEY_ESC
        je  .quit
        cmp eax, KEY_Q
        je  .quit
        cmp eax, 'Q'
        je  .quit
.restart:
        call init_game
        jmp  .main_loop

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        mov eax, SYS_EXIT
        xor ebx, ebx
        int 0x80

;-----------------------------------------------------------
init_game:
        pushad
        mov  edi, board
        mov  ecx, BOARD_SZ * BOARD_SZ
        xor  eax, eax
        rep  stosd
        mov  dword [score], 0
        mov  byte [game_over], 0
        mov  byte [game_won], 0
        mov  byte [go_played], 0
        ; load high score
        mov  esi, hs_name_2048
        call hs_load
        mov  [hi_score], eax
        ; seed rng
        mov  eax, SYS_GETTIME
        int  0x80
        mov  [rng], eax
        ; add two initial tiles
        call add_random_tile
        call add_random_tile
        popad
        ret

;-----------------------------------------------------------
; rng_next: EAX = next pseudo-random 32-bit value
rng_next:
        mov  eax, [rng]
        imul eax, 1103515245
        add  eax, 12345
        mov  [rng], eax
        ret

;-----------------------------------------------------------
add_random_tile:
        pushad
        ; count empties
        xor  ecx, ecx
        xor  ebx, ebx
.art_cnt:
        cmp  ecx, BOARD_SZ * BOARD_SZ
        jge  .art_pick
        cmp  dword [board + ecx * 4], 0
        jne  .art_cnt_n
        inc  ebx
.art_cnt_n:
        inc  ecx
        jmp  .art_cnt
.art_pick:
        test ebx, ebx
        jz   .art_done
        call rng_next
        xor  edx, edx
        div  ebx                ; eax = quotient, edx = index of empty cell
        ; find that empty cell
        xor  ecx, ecx
        xor  esi, esi           ; empty counter
.art_find:
        cmp  ecx, BOARD_SZ * BOARD_SZ
        jge  .art_done
        cmp  dword [board + ecx * 4], 0
        jne  .art_fn
        cmp  esi, edx
        je   .art_place
        inc  esi
.art_fn:
        inc  ecx
        jmp  .art_find
.art_place:
        call rng_next
        xor  edx, edx
        mov  ebx, 10
        div  ebx
        cmp  edx, 0             ; 10% chance of 4
        jne  .art_two
        mov  dword [board + ecx * 4], 4
        jmp  .art_done
.art_two:
        mov  dword [board + ecx * 4], 2
.art_done:
        popad
        ret

;-----------------------------------------------------------
; slide helpers: operate on a 4-element line
; Input: ESI = pointer to 4 dwords (the line), direction left
; Returns: byte [moved] = 1 if anything changed
slide_line_left:
        pushad
        ; compress (remove zeros, shift left)
        mov  [.sll_ptr], esi
        xor  ecx, ecx           ; write pos
        xor  ebx, ebx           ; read pos
.sll_pack:
        cmp  ebx, BOARD_SZ
        jge  .sll_merge
        mov  eax, [esi + ebx * 4]
        test eax, eax
        jz   .sll_pack_skip
        mov  [esi + ecx * 4], eax
        inc  ecx
.sll_pack_skip:
        inc  ebx
        jmp  .sll_pack
.sll_fill:
        cmp  ecx, BOARD_SZ
        jge  .sll_merge
        mov  dword [esi + ecx * 4], 0
        inc  ecx
        jmp  .sll_fill
.sll_merge:
        ; merge adjacent equal pairs left-to-right
        xor  ebx, ebx
.sll_m:
        cmp  ebx, BOARD_SZ - 1
        jge  .sll_repack
        mov  eax, [esi + ebx * 4]
        test eax, eax
        jz   .sll_mn
        cmp  eax, [esi + (ebx + 1) * 4]
        jne  .sll_mn
        ; merge
        shl  eax, 1
        mov  [esi + ebx * 4], eax
        mov  dword [esi + (ebx + 1) * 4], 0
        add  [score], eax
        mov  byte [moved], 1
        inc  ebx               ; skip merged cell
.sll_mn:
        inc  ebx
        jmp  .sll_m
.sll_repack:
        ; pack again
        xor  ecx, ecx
        xor  ebx, ebx
.sll_rp:
        cmp  ebx, BOARD_SZ
        jge  .sll_rfill
        mov  eax, [esi + ebx * 4]
        test eax, eax
        jz   .sll_rp_skip
        mov  [esi + ecx * 4], eax
        inc  ecx
.sll_rp_skip:
        inc  ebx
        jmp  .sll_rp
.sll_rfill:
        cmp  ecx, BOARD_SZ
        jge  .sll_done
        mov  dword [esi + ecx * 4], 0
        inc  ecx
        jmp  .sll_rfill
.sll_done:
        popad
        ret
.sll_ptr: dd 0

;-----------------------------------------------------------
; copy_board_to_temp / compare_board_with_temp
; to detect movement
copy_board:
        pushad
        mov  esi, board
        mov  edi, board_tmp
        mov  ecx, BOARD_SZ * BOARD_SZ
        rep  movsd
        popad
        ret

compare_boards:
        ; sets [moved]=1 if different
        pushad
        mov  esi, board
        mov  edi, board_tmp
        mov  ecx, BOARD_SZ * BOARD_SZ
        repz cmpsd
        je   .cb_same
        mov  byte [moved], 1
        jmp  .cb_done
.cb_same:
        mov  byte [moved], 0
.cb_done:
        popad
        ret

;-----------------------------------------------------------
slide_left:
        pushad
        call copy_board
        xor  ecx, ecx
.sl_l:
        cmp  ecx, BOARD_SZ
        jge  .sl_done
        mov  esi, board
        imul eax, ecx, BOARD_SZ * 4
        add  esi, eax
        call slide_line_left
        inc  ecx
        jmp  .sl_l
.sl_done:
        call compare_boards
        popad
        ret

;-----------------------------------------------------------
slide_right:
        pushad
        call copy_board
        xor  ecx, ecx
.sr_l:
        cmp  ecx, BOARD_SZ
        jge  .sr_done
        ; reverse row, slide left, reverse back
        mov  esi, board
        imul eax, ecx, BOARD_SZ * 4
        add  esi, eax
        call reverse_line
        call slide_line_left
        call reverse_line
        inc  ecx
        jmp  .sr_l
.sr_done:
        call compare_boards
        popad
        ret

;-----------------------------------------------------------
reverse_line:
        pushad
        mov  eax, [esi]
        mov  ebx, [esi + 12]
        mov  [esi], ebx
        mov  [esi + 12], eax
        mov  eax, [esi + 4]
        mov  ebx, [esi + 8]
        mov  [esi + 4], ebx
        mov  [esi + 8], eax
        popad
        ret

;-----------------------------------------------------------
; transpose board in-place (swap rows/cols)
transpose_board:
        pushad
        mov  ecx, 0
.tb_r:
        cmp  ecx, BOARD_SZ
        jge  .tb_done
        mov  edx, ecx
        inc  edx
.tb_c:
        cmp  edx, BOARD_SZ
        jge  .tb_rn
        ; swap board[r][c] and board[c][r]
        mov  eax, ecx
        imul eax, BOARD_SZ
        add  eax, edx
        mov  ebx, edx
        imul ebx, BOARD_SZ
        add  ebx, ecx
        mov  esi, [board + eax * 4]
        mov  edi, [board + ebx * 4]
        mov  [board + eax * 4], edi
        mov  [board + ebx * 4], esi
        inc  edx
        jmp  .tb_c
.tb_rn:
        inc  ecx
        jmp  .tb_r
.tb_done:
        popad
        ret

;-----------------------------------------------------------
slide_up:
        pushad
        call copy_board
        call transpose_board
        xor  ecx, ecx
.su_l:
        cmp  ecx, BOARD_SZ
        jge  .su_done
        mov  esi, board
        imul eax, ecx, BOARD_SZ * 4
        add  esi, eax
        call slide_line_left
        inc  ecx
        jmp  .su_l
.su_done:
        call transpose_board
        call compare_boards
        popad
        ret

;-----------------------------------------------------------
slide_down:
        pushad
        call copy_board
        call transpose_board
        xor  ecx, ecx
.sd_l:
        cmp  ecx, BOARD_SZ
        jge  .sd_done
        mov  esi, board
        imul eax, ecx, BOARD_SZ * 4
        add  esi, eax
        call reverse_line
        call slide_line_left
        call reverse_line
        inc  ecx
        jmp  .sd_l
.sd_done:
        call transpose_board
        call compare_boards
        popad
        ret

;-----------------------------------------------------------
check_win:
        pushad
        mov  ecx, BOARD_SZ * BOARD_SZ - 1
.cw_loop:
        cmp  dword [board + ecx * 4], 2048
        jge  .cw_win
        dec  ecx
        cmp  ecx, -1
        jg   .cw_loop
        jmp  .cw_done
.cw_win:
        mov  byte [game_won], 1
.cw_done:
        popad
        ret

;-----------------------------------------------------------
check_game_over:
        pushad
        ; check any empty cell
        xor  ecx, ecx
.cgo_e:
        cmp  ecx, BOARD_SZ * BOARD_SZ
        jge  .cgo_adj
        cmp  dword [board + ecx * 4], 0
        je   .cgo_not_over
        inc  ecx
        jmp  .cgo_e
.cgo_adj:
        ; check adjacent merges
        xor  ecx, ecx
.cgo_r:
        cmp  ecx, BOARD_SZ
        jge  .cgo_over
        xor  edx, edx
.cgo_c:
        cmp  edx, BOARD_SZ
        jge  .cgo_rn
        mov  eax, ecx
        imul eax, BOARD_SZ
        add  eax, edx
        mov  ebx, [board + eax * 4]
        ; check right neighbour
        cmp  edx, BOARD_SZ - 1
        jge  .cgo_no_r
        cmp  ebx, [board + eax * 4 + 4]
        je   .cgo_not_over
.cgo_no_r:
        ; check bottom neighbour
        cmp  ecx, BOARD_SZ - 1
        jge  .cgo_no_b
        mov  esi, eax
        add  esi, BOARD_SZ
        cmp  ebx, [board + esi * 4]
        je   .cgo_not_over
.cgo_no_b:
        inc  edx
        jmp  .cgo_c
.cgo_rn:
        inc  ecx
        jmp  .cgo_r
.cgo_over:
        mov  byte [game_over], 1
        ; persist high score and play SFX once
        cmp  byte [go_played], 0
        jne  .cgo_done
        mov  byte [go_played], 1
        mov  esi, hs_name_2048
        mov  ebx, [score]
        call hs_update
        mov  [hi_score], eax
        call audio_sfx_lose
.cgo_done:
        popad
        ret
.cgo_not_over:
        popad
        ret

;-----------------------------------------------------------
; log2_tile: EAX = tile value → EAX = log2 index (0-11), 0=empty
log2_tile:
        test eax, eax
        jz   .lt_zero
        mov  ecx, eax
        xor  eax, eax
.lt_loop:
        shr  ecx, 1
        jz   .lt_done
        inc  eax
        jmp  .lt_loop
.lt_done:
        cmp  eax, 11
        jle  .lt_ok
        mov  eax, 11
.lt_ok:
        ret
.lt_zero:
        xor  eax, eax
        ret

;-----------------------------------------------------------
draw_scene:
        pushad
        ; Background
        mov  edx, COL_BG
        call vbe_clear_screen

        ; Board background
        mov  ebx, BOARD_X - 4
        mov  ecx, BOARD_Y - 4
        mov  edx, BOARD_W + 8
        mov  esi, BOARD_H + 8
        mov  edi, COL_BOARD
        call vbe_fill_rect

        ; Title & Score
        mov  ebx, 20
        mov  ecx, 14
        mov  edx, str_title
        mov  esi, 0x00776E65
        mov  eax, 3
        call vbe_draw_str

        ; Score box with label + scale-2 number
        mov  ebx, 422
        mov  ecx, 2
        mov  edx, 100
        mov  esi, 54
        mov  edi, COL_SCORE_BG
        call vbe_fill_rect
        mov  ebx, 430
        mov  ecx, 6
        mov  edx, str_score
        mov  esi, 0x00F9F6F2
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 430
        mov  ecx, 20
        mov  edx, [score]
        mov  esi, 0x00FFFFFF
        mov  eax, 2
        call vbe_draw_num

        ; High score box
        mov  ebx, 534
        mov  ecx, 2
        mov  edx, 100
        mov  esi, 54
        mov  edi, COL_SCORE_BG
        call vbe_fill_rect
        mov  ebx, 542
        mov  ecx, 6
        mov  edx, str_hi
        mov  esi, 0x00F9F6F2
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 542
        mov  ecx, 20
        mov  edx, [hi_score]
        mov  esi, 0x00FFFFFF
        mov  eax, 2
        call vbe_draw_num

        ; Draw cells
        xor  ecx, ecx           ; row
.ds_r:
        cmp  ecx, BOARD_SZ
        jge  .ds_done
        xor  edx, edx           ; col
.ds_c:
        cmp  edx, BOARD_SZ
        jge  .ds_rn
        ; cell pixel coords
        imul ebx, edx, (CELL_SZ + CELL_GAP)
        add  ebx, BOARD_X
        imul esi, ecx, (CELL_SZ + CELL_GAP)
        add  esi, BOARD_Y
        ; get tile value
        push ecx
        push edx
        mov  eax, ecx
        imul eax, BOARD_SZ
        add  eax, edx
        mov  eax, [board + eax * 4]
        ; get colour index
        call log2_tile          ; EAX = index 0-11
        mov  edi, [tile_colours + eax * 4]
        ; draw tile bg
        push ebx
        push esi
        mov  edx, CELL_SZ
        mov  [.cell_h], dword CELL_SZ
        call vbe_fill_rect      ; EBX=x, ECX=esi? No, need ECX=y
        ; vbe_fill_rect: EBX=x, ECX=y, EDX=w, ESI=h, EDI=colour
        ; currently: EBX=cell_x, esi=cell_y
        ; esi is in esi, ECX may have been clobbered
        ; Fix: save cell_y to ECX
        pop  esi                ; cell_y
        pop  ebx                ; cell_x
        push ebx
        push esi
        mov  ecx, esi
        mov  edx, CELL_SZ
        mov  esi, CELL_SZ
        call vbe_fill_rect
        pop  esi                ; cell_y
        pop  ebx                ; cell_x
        ; Draw number if non-zero
        pop  edx                ; col
        pop  ecx                ; row
        push ecx
        push edx
        mov  eax, ecx
        imul eax, BOARD_SZ
        add  eax, edx
        mov  eax, [board + eax * 4]
        test eax, eax
        jz   .ds_cn
        push eax
        ; centre text: use scale 2, glyph 6px wide * scale = 12px
        ; rough centre: add (CELL_SZ - 12) / 2 to x, (CELL_SZ - 14) / 2 to y
        add  ebx, 30
        add  esi, 34
        mov  ecx, esi
        mov  edx, [esp]
        pop  eax                ; tile value → edx
        mov  edx, eax
        ; pick text colour
        mov  eax, edx
        call log2_tile
        cmp  eax, 2
        jle  .ds_dark_txt
        mov  esi, COL_TEXT_LT
        jmp  .ds_txt_col
.ds_dark_txt:
        mov  esi, COL_TEXT_DK
.ds_txt_col:
        mov  eax, 2
        call vbe_draw_num
.ds_cn:
        pop  edx
        pop  ecx
        inc  edx
        jmp  .ds_c
.ds_rn:
        inc  ecx
        jmp  .ds_r
.ds_done:

        ; Game over / win overlay
        cmp  byte [game_won], 1
        jne  .ds_check_over
        mov  ebx, 180
        mov  ecx, 445
        mov  edx, str_won
        mov  esi, 0x0000AA00
        mov  eax, 2
        call vbe_draw_str
        jmp  .ds_end
.ds_check_over:
        cmp  byte [game_over], 1
        jne  .ds_end
        mov  ebx, 170
        mov  ecx, 445
        mov  edx, str_over
        mov  esi, 0x00FF4444
        mov  eax, 2
        call vbe_draw_str
.ds_end:
        ; hints
        mov  ebx, 20
        mov  ecx, 455
        mov  edx, str_hint
        mov  esi, 0x00999988
        mov  eax, 1
        call vbe_draw_str
        popad
        ret

.cell_h: dd CELL_SZ

;-----------------------------------------------------------
str_title: db "2048", 0
str_score: db "SCORE", 0
str_hi:    db "HIGH", 0
str_won:   db "YOU REACHED 2048!", 0
str_over:  db "GAME OVER!  R=RESTART", 0
str_hint:  db "ARROW KEYS OR WASD   R=RESTART  Q=QUIT", 0

board:     times BOARD_SZ * BOARD_SZ dd 0
board_tmp: times BOARD_SZ * BOARD_SZ dd 0
score:     dd 0
hi_score:  dd 0
game_over: db 0
game_won:  db 0
moved:     db 0
rng:       dd 0
go_played: db 0
hs_name_2048: db "2048", 0
