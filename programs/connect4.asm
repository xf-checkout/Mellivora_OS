; connect4.asm - Connect 4 VBE graphics game for Mellivora OS
; Player=Yellow vs CPU=Red.  Drop discs to connect 4 in a row.

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

COLS        equ 7
ROWS        equ 6
CELL        equ 64
DISC_R      equ 26
BOARD_X     equ 96
BOARD_Y     equ 73
EMPTY       equ 0
PLAYER      equ 1
COMP        equ 2

COL_BG      equ 0x00111122
COL_BOARD   equ 0x001444AA
COL_EMPTY   equ 0x00081028
COL_PLAYER  equ 0x00FFEE22
COL_COMP    equ 0x00FF3333
COL_ARROW   equ 0x00CCCCCC
COL_TEXT    equ 0x00FFFFFF

; States
ST_PLAY     equ 0
ST_CPU      equ 1
ST_WIN      equ 2
ST_LOSE     equ 3
ST_DRAW     equ 4

start:
        VBE_GAME_INIT
        ; Load persistent wins from /scores/connect4 into score_w (clamp 0..255)
        mov esi, hs_name_c4
        call hs_load
        cmp eax, 255
        jbe .hs_ok
        mov eax, 255
.hs_ok:
        mov [score_w], al
        call init_game

.main_loop:
        call draw_scene
        VBE_GAME_PRESENT

        cmp byte [gstate], ST_CPU
        jne .check_over_state

        ; Short delay then CPU moves
        mov eax, SYS_SLEEP
        mov ebx, 30
        int 0x80
        call cpu_move
        call check_game_over
        cmp byte [gstate], ST_CPU
        jne .main_loop
        mov byte [gstate], ST_PLAY
        jmp .main_loop

.check_over_state:
        cmp byte [gstate], ST_WIN
        je  .poll_restart
        cmp byte [gstate], ST_LOSE
        je  .poll_restart
        cmp byte [gstate], ST_DRAW
        je  .poll_restart

.poll_key:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je  .main_loop
        cmp eax, KEY_ESC
        je  .quit
        cmp eax, KEY_Q
        je  .quit
        cmp eax, 'Q'
        je  .quit
        cmp eax, KEY_LEFT
        je  .move_left
        cmp eax, KEY_RIGHT
        je  .move_right
        cmp eax, KEY_ENTER
        je  .drop
        cmp eax, KEY_SPACE
        je  .drop
        ; number keys 1-7 (ASCII '1'-'7')
        cmp eax, '1'
        jl  .poll_key
        cmp eax, '7'
        jg  .poll_key
        sub eax, '1'            ; 0-based column
        mov [cursor_col], al
        call do_drop
        jmp .main_loop

.move_left:
        cmp byte [cursor_col], 0
        je  .main_loop
        dec byte [cursor_col]
        jmp .main_loop
.move_right:
        cmp byte [cursor_col], COLS - 1
        je  .main_loop
        inc byte [cursor_col]
        jmp .main_loop
.drop:
        call do_drop
        jmp .main_loop

.poll_restart:
        VBE_GAME_POLL_KEY
        cmp eax, -1
        je  .main_loop
        cmp eax, KEY_ESC
        je  .quit
        cmp eax, KEY_Q
        je  .quit
        cmp eax, 'Q'
        je  .quit
        call init_game
        jmp .main_loop

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
        ; zero board
        mov  edi, board
        mov  ecx, COLS * ROWS
        xor  eax, eax
        rep  stosb
        mov  byte [gstate], ST_PLAY
        mov  byte [cursor_col], 3
        popad
        ret

;-----------------------------------------------------------
; do_drop - drop player disc in cursor_col
do_drop:
        pushad
        cmp byte [gstate], ST_PLAY
        jne .dd_done
        movzx eax, byte [cursor_col]
        call drop_disc      ; EAX=col, EBX=PLAYER
        ; returns row in EAX, -1 if full
        cmp eax, -1
        je  .dd_done
        call check_game_over
        cmp byte [gstate], ST_PLAY
        jne .dd_done
        mov byte [gstate], ST_CPU
.dd_done:
        popad
        ret

;-----------------------------------------------------------
; drop_disc: EAX=col → place PLAYER disc, return row in EAX (-1 if full)
drop_disc:
        pushad
        mov  [.dc_col], eax
        ; find lowest empty row
        mov  ecx, ROWS - 1
.dc_loop:
        cmp  ecx, 0
        jl   .dc_full
        ; offset = row*COLS + col
        mov  eax, ecx
        imul eax, COLS
        add  eax, [.dc_col]
        cmp  byte [board + eax], EMPTY
        jne  .dc_next
        ; place PLAYER
        mov  byte [board + eax], PLAYER
        mov  [esp + 28], ecx    ; return row in EAX slot of pushad
        popad
        ret
.dc_next:
        dec ecx
        jmp .dc_loop
.dc_full:
        mov dword [esp + 28], -1
        popad
        ret
.dc_col: dd 0

;-----------------------------------------------------------
; drop_for_cpu: EAX=col, piece=COMP → returns row in EAX
drop_for_cpu:
        pushad
        mov  [.dfc_col], eax
        mov  ecx, ROWS - 1
.dfc_loop:
        cmp  ecx, 0
        jl   .dfc_full
        mov  eax, ecx
        imul eax, COLS
        add  eax, [.dfc_col]
        cmp  byte [board + eax], EMPTY
        jne  .dfc_next
        mov  byte [board + eax], COMP
        mov  [esp + 28], ecx
        popad
        ret
.dfc_next:
        dec  ecx
        jmp  .dfc_loop
.dfc_full:
        mov  dword [esp + 28], -1
        popad
        ret
.dfc_col: dd 0

;-----------------------------------------------------------
; undo_disc: EAX=col → remove topmost non-empty disc
undo_disc:
        pushad
        mov  [.ud_col], eax
        xor  ecx, ecx
.ud_loop:
        cmp  ecx, ROWS
        jge  .ud_done
        mov  eax, ecx
        imul eax, COLS
        add  eax, [.ud_col]
        cmp  byte [board + eax], EMPTY
        je   .ud_next
        mov  byte [board + eax], EMPTY
        jmp  .ud_done
.ud_next:
        inc  ecx
        jmp  .ud_loop
.ud_done:
        popad
        ret
.ud_col: dd 0

;-----------------------------------------------------------
; check_win_for: EBX=piece → sets EAX=1 if piece has 4 in a row
check_win_for:
        pushad
        mov  [.cwf_piece], ebx
        ; Horizontal
        xor  ecx, ecx       ; row
.cwf_hr:
        cmp  ecx, ROWS
        jge  .cwf_vr
        xor  edx, edx       ; col
.cwf_hc:
        cmp  edx, COLS - 3
        jg   .cwf_hr_next
        ; check 4 consecutive
        mov  eax, ecx
        imul eax, COLS
        add  eax, edx
        mov  bl, [.cwf_piece]
        cmp  [board + eax],     bl
        jne  .cwf_hc_next
        cmp  [board + eax + 1], bl
        jne  .cwf_hc_next
        cmp  [board + eax + 2], bl
        jne  .cwf_hc_next
        cmp  [board + eax + 3], bl
        jne  .cwf_hc_next
        mov  dword [esp + 28], 1
        popad
        ret
.cwf_hc_next:
        inc  edx
        jmp  .cwf_hc
.cwf_hr_next:
        inc  ecx
        jmp  .cwf_hr
        ; Vertical
.cwf_vr:
        xor  ecx, ecx
.cwf_vc_c:
        cmp  ecx, COLS
        jge  .cwf_dr
        xor  edx, edx
.cwf_vc_r:
        cmp  edx, ROWS - 3
        jg   .cwf_vc_cn
        mov  eax, edx
        imul eax, COLS
        add  eax, ecx
        mov  bl, [.cwf_piece]
        cmp  [board + eax],            bl
        jne  .cwf_vc_rn
        cmp  [board + eax + COLS],     bl
        jne  .cwf_vc_rn
        cmp  [board + eax + COLS*2],   bl
        jne  .cwf_vc_rn
        cmp  [board + eax + COLS*3],   bl
        jne  .cwf_vc_rn
        mov  dword [esp + 28], 1
        popad
        ret
.cwf_vc_rn:
        inc  edx
        jmp  .cwf_vc_r
.cwf_vc_cn:
        inc  ecx
        jmp  .cwf_vc_c
        ; Diagonal right
.cwf_dr:
        xor  ecx, ecx
.cwf_drr:
        cmp  ecx, ROWS - 3
        jg   .cwf_dl
        xor  edx, edx
.cwf_drc:
        cmp  edx, COLS - 3
        jg   .cwf_drr_n
        mov  eax, ecx
        imul eax, COLS
        add  eax, edx
        mov  bl, [.cwf_piece]
        cmp  [board + eax],            bl
        jne  .cwf_drc_n
        cmp  [board + eax + COLS+1],   bl
        jne  .cwf_drc_n
        cmp  [board + eax + COLS*2+2], bl
        jne  .cwf_drc_n
        cmp  [board + eax + COLS*3+3], bl
        jne  .cwf_drc_n
        mov  dword [esp + 28], 1
        popad
        ret
.cwf_drc_n:
        inc  edx
        jmp  .cwf_drc
.cwf_drr_n:
        inc  ecx
        jmp  .cwf_drr
        ; Diagonal left
.cwf_dl:
        xor  ecx, ecx
.cwf_dlr:
        cmp  ecx, ROWS - 3
        jg   .cwf_end
        mov  edx, 3
.cwf_dlc:
        cmp  edx, COLS
        jge  .cwf_dlr_n
        mov  eax, ecx
        imul eax, COLS
        add  eax, edx
        mov  bl, [.cwf_piece]
        cmp  [board + eax],            bl
        jne  .cwf_dlc_n
        cmp  [board + eax + COLS-1],   bl
        jne  .cwf_dlc_n
        cmp  [board + eax + COLS*2-2], bl
        jne  .cwf_dlc_n
        cmp  [board + eax + COLS*3-3], bl
        jne  .cwf_dlc_n
        mov  dword [esp + 28], 1
        popad
        ret
.cwf_dlc_n:
        inc  edx
        jmp  .cwf_dlc
.cwf_dlr_n:
        inc  ecx
        jmp  .cwf_dlr
.cwf_end:
        mov  dword [esp + 28], 0
        popad
        ret
.cwf_piece: dd 0

;-----------------------------------------------------------
check_game_over:
        pushad
        mov  ebx, PLAYER
        call check_win_for
        cmp  eax, 1
        jne  .cgo_comp
        mov  byte [gstate], ST_WIN
        inc  byte [score_w]
        ; persist + win SFX
        movzx ebx, byte [score_w]
        mov  esi, hs_name_c4
        call hs_save
        call audio_sfx_win
        popad
        ret
.cgo_comp:
        mov  ebx, COMP
        call check_win_for
        cmp  eax, 1
        jne  .cgo_full
        mov  byte [gstate], ST_LOSE
        inc  byte [score_l]
        call audio_sfx_lose
        popad
        ret
.cgo_full:
        ; check if board full
        xor  ecx, ecx
.cgo_fl:
        cmp  ecx, COLS * ROWS
        jge  .cgo_draw
        cmp  byte [board + ecx], EMPTY
        je   .cgo_none
        inc  ecx
        jmp  .cgo_fl
.cgo_draw:
        mov  byte [gstate], ST_DRAW
        inc  byte [score_d]
        call audio_sfx_click
        popad
        ret
.cgo_none:
        popad
        ret

;-----------------------------------------------------------
cpu_move:
        pushad
        ; 1. Try to win
        xor  ecx, ecx
.cm_win:
        cmp  ecx, COLS
        jge  .cm_block
        mov  eax, ecx
        call drop_for_cpu
        cmp  eax, -1
        je   .cm_win_next
        push eax
        push ecx
        mov  ebx, COMP
        call check_win_for
        mov  [imul_tmp], eax    ; save win result before pops clobber EAX
        pop  ecx
        pop  eax
        cmp  dword [imul_tmp], 1
        je   .cm_done
        ; undo
        mov  eax, ecx
        call undo_disc
.cm_win_next:
        inc  ecx
        jmp  .cm_win
        ; 2. Block player
.cm_block:
        xor  ecx, ecx
.cm_bl:
        cmp  ecx, COLS
        jge  .cm_centre
        ; pretend player drops here
        mov  [.cpu_col], ecx
        ; drop PLAYER piece temporarily
        mov  ecx, ROWS - 1
        mov  edx, [.cpu_col]
.cm_bl_r:
        cmp  ecx, 0
        jl   .cm_bl_next
        mov  eax, ecx
        imul eax, COLS
        add  eax, edx
        cmp  byte [board + eax], EMPTY
        jne  .cm_bl_rn
        mov  byte [board + eax], PLAYER
        push ecx
        push edx
        mov  ebx, PLAYER
        call check_win_for
        pop  edx
        pop  ecx
        mov  [imul_tmp], eax
        ; undo
        mov  eax, ecx
        imul eax, COLS
        add  eax, edx
        mov  byte [board + eax], EMPTY
        cmp  dword [imul_tmp], 1
        jne  .cm_bl_next
        ; player would win → block
        mov  eax, edx
        call drop_for_cpu
        jmp  .cm_done
.cm_bl_rn:
        dec  ecx
        jmp  .cm_bl_r
.cm_bl_next:
        inc  dword [.cpu_col]
        mov  ecx, [.cpu_col]
        jmp  .cm_bl

.cm_centre:
        ; 3. Prefer centre columns (3, 2, 4, 1, 5, 0, 6)
        mov  eax, 3
        call drop_for_cpu
        cmp  eax, -1
        jne  .cm_done
        mov  eax, 2
        call drop_for_cpu
        cmp  eax, -1
        jne  .cm_done
        mov  eax, 4
        call drop_for_cpu
        cmp  eax, -1
        jne  .cm_done
        mov  eax, 1
        call drop_for_cpu
        cmp  eax, -1
        jne  .cm_done
        mov  eax, 5
        call drop_for_cpu
        cmp  eax, -1
        jne  .cm_done
        mov  eax, 0
        call drop_for_cpu
        cmp  eax, -1
        jne  .cm_done
        mov  eax, 6
        call drop_for_cpu
.cm_done:
        popad
        ret
.cpu_col: dd 0

;-----------------------------------------------------------
draw_scene:
        pushad
        mov  edx, COL_BG
        call vbe_clear_screen

        ; Board background rect
        mov  ebx, BOARD_X - 4
        mov  ecx, BOARD_Y - 4
        mov  edx, COLS * CELL + 8
        mov  esi, ROWS * CELL + 8
        mov  edi, COL_BOARD
        call vbe_fill_rect

        ; Draw cells
        xor  ebx, ebx       ; row
.ds_r:
        cmp  ebx, ROWS
        jge  .ds_end_r
        xor  ecx, ecx       ; col
.ds_c:
        cmp  ecx, COLS
        jge  .ds_next_r
        ; cell pixel coords
        push ebx
        push ecx
        imul edi, ecx, CELL
        add  edi, BOARD_X + CELL/2
        imul esi, ebx, CELL
        add  esi, BOARD_Y + CELL/2
        ; disc colour
        mov  eax, ebx
        imul eax, COLS
        add  eax, ecx
        movzx eax, byte [board + eax]
        cmp  eax, PLAYER
        je   .ds_player
        cmp  eax, COMP
        je   .ds_comp
        mov  edx, COL_EMPTY
        jmp  .ds_draw_disc
.ds_player:
        mov  edx, COL_PLAYER
        jmp  .ds_draw_disc
.ds_comp:
        mov  edx, COL_COMP
.ds_draw_disc:
        ; vbe_fill_circle: EBX=cx, ECX=cy, EDX=r, ESI=colour
        mov  [.disc_x], edi
        mov  [.disc_y], esi
        mov  [.disc_col], edx
        mov  ebx, [.disc_x]
        mov  ecx, [.disc_y]
        mov  edx, DISC_R
        mov  esi, [.disc_col]
        call vbe_fill_circle

        pop  ecx
        pop  ebx
        inc  ecx
        jmp  .ds_c
.ds_next_r:
        inc  ebx
        jmp  .ds_r
.ds_end_r:

        ; Cursor arrow above board
        cmp  byte [gstate], ST_PLAY
        jne  .ds_no_arrow
        movzx eax, byte [cursor_col]
        imul  eax, CELL
        add   eax, BOARD_X + CELL/2
        sub   eax, 6
        mov   ebx, eax
        mov   ecx, BOARD_Y - 24
        mov   edx, 13
        mov   esi, 16
        mov   edi, COL_ARROW
        call  vbe_fill_rect
.ds_no_arrow:

        ; Title
        mov  ebx, 12
        mov  ecx, 12
        mov  edx, str_title
        mov  esi, 0x00EEDDFF
        mov  eax, 2
        call vbe_draw_str

        ; Score panel — right of board (x=548..638, full board height)
        mov  ebx, 548
        mov  ecx, 73
        mov  edx, 90
        mov  esi, 384
        mov  edi, 0x00181830
        call vbe_fill_rect

        ; WINS
        mov  ebx, 556
        mov  ecx, 86
        mov  edx, str_wins
        mov  esi, COL_PLAYER
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 556
        mov  ecx, 99
        movzx edx, byte [score_w]
        mov  esi, COL_PLAYER
        mov  eax, 3
        call vbe_draw_num

        ; LOSS
        mov  ebx, 556
        mov  ecx, 147
        mov  edx, str_loss
        mov  esi, COL_COMP
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 556
        mov  ecx, 160
        movzx edx, byte [score_l]
        mov  esi, COL_COMP
        mov  eax, 3
        call vbe_draw_num

        ; DRAW
        mov  ebx, 556
        mov  ecx, 208
        mov  edx, str_drws
        mov  esi, 0x00AAAAAA
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 556
        mov  ecx, 221
        movzx edx, byte [score_d]
        mov  esi, 0x00999999
        mov  eax, 3
        call vbe_draw_num

        ; CPU indicator
        cmp  byte [gstate], ST_CPU
        jne  .ds_s_end
        mov  ebx, 552
        mov  ecx, 294
        mov  edx, str_cpu
        mov  esi, 0x00FF8844
        mov  eax, 1
        call vbe_draw_str

.ds_s_end:
        ; Win/lose/draw — large centred message above the board
        cmp  byte [gstate], ST_WIN
        jne  .ds_s1
        mov  ebx, 248
        mov  ecx, 43
        mov  edx, str_win
        mov  esi, COL_PLAYER
        mov  eax, 3
        call vbe_draw_str
        jmp  .ds_sdone
.ds_s1: cmp  byte [gstate], ST_LOSE
        jne  .ds_s2
        mov  ebx, 232
        mov  ecx, 43
        mov  edx, str_lose
        mov  esi, COL_COMP
        mov  eax, 3
        call vbe_draw_str
        jmp  .ds_sdone
.ds_s2: cmp  byte [gstate], ST_DRAW
        jne  .ds_sdone
        mov  ebx, 280
        mov  ecx, 43
        mov  edx, str_draw
        mov  esi, 0x00CCCCCC
        mov  eax, 3
        call vbe_draw_str
.ds_sdone:
        popad
        ret

.disc_x:  dd 0
.disc_y:  dd 0
.disc_col: dd 0

;-----------------------------------------------------------
str_title: db "CONNECT 4", 0
str_win:   db "YOU WIN!", 0
str_lose:  db "YOU LOSE!", 0
str_draw:  db "DRAW!", 0
str_wins:  db "WINS", 0
str_loss:  db "LOSS", 0
str_drws:  db "DRAW", 0
str_cpu:   db "CPU...", 0

board:    times COLS * ROWS db 0
gstate:   db ST_PLAY
cursor_col: db 3
imul_tmp: dd 0
score_w:  db 0
score_l:  db 0
score_d:  db 0
hs_name_c4: db "connect4", 0
