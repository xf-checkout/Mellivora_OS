; blackjack.asm - Blackjack (21) for Mellivora OS - VBE Graphics
; Player=You (keyboard H/S or mouse), Dealer=AI.
; Casino rules: dealer hits on 16 or below. Aces count as 11 or 1.

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

;=======================================================================
; Layout  (1024 x 768)
;=======================================================================
MAX_HAND        equ 12

COL_FELT        equ 0x00155A15
COL_FELT_DARK   equ 0x000E3D0E
COL_GOLD        equ 0x00FFD700
COL_WHITE       equ 0x00FFFFFF
COL_RED         equ 0x00CC2222
COL_GRAY        equ 0x00AAAAAA
COL_DARKGRAY    equ 0x00555555
COL_PANEL       equ 0x00111E11
COL_BTN_HIT     equ 0x001A6B1A
COL_BTN_STAND   equ 0x006B1A1A
COL_WIN_MSG     equ 0x00FFEE44
COL_LOSE_MSG    equ 0x00FF4444
COL_PUSH_MSG    equ 0x0044AAFF
COL_CARD_BG     equ 0x00F8F4E8
COL_CARD_BORDER equ 0x00777777

CARD_W          equ 80
CARD_H          equ 110
CARD_STEP       equ 90

DEALER_Y        equ 160
DEALER_CARD_X   equ 80
PLAYER_Y        equ 450
PLAYER_CARD_X   equ 80

PANEL_X         equ 800
PANEL_Y         equ 60
PANEL_W         equ 200
PANEL_H         equ 340

BTN_Y           equ 620
BTN_HIT_X       equ 300
BTN_STAND_X     equ 500
BTN_W           equ 150
BTN_H           equ 48

RESULT_Y        equ 340

STATE_PLAYER    equ 0
STATE_RESULT    equ 1

start:
        VBE_GAME_INIT
        mov  dword [p_wins], 0
        mov  dword [d_wins], 0
        mov  dword [ties],   0
        ; Load persistent total wins from /scores/blackjack
        mov  esi, hs_name_bj
        call hs_load
        mov  [total_wins], eax

.new_round:
        call shuffle_deck
        call deal_initial
        mov  byte [game_state], STATE_PLAYER
        mov  byte [dealer_revealed], 0

        ; Check player natural 21
        mov  esi, p_hand
        mov  ecx, [p_count]
        call hand_total
        cmp  eax, 21
        jne  .main_loop
        mov  byte [dealer_revealed], 1
        call dealer_turn
        call resolve_round
        jmp  .result_wait

.main_loop:
        call render_scene
        VBE_GAME_PRESENT

        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .ml_mouse

        cmp  eax, KEY_ESC
        je   .quit
        cmp  eax, KEY_Q
        je   .quit
        cmp  eax, 'Q'
        je   .quit

        cmp  byte [game_state], STATE_PLAYER
        jne  .main_loop

        cmp  eax, 'h'
        je   .do_hit
        cmp  eax, 'H'
        je   .do_hit
        cmp  eax, 's'
        je   .do_stand
        cmp  eax, 'S'
        je   .do_stand
        jmp  .main_loop

.ml_mouse:
        cmp  byte [game_state], STATE_PLAYER
        jne  .main_loop
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz   .main_loop
        call wait_mouse_up_bj
        ; Hit button?
        cmp  eax, BTN_HIT_X
        jl   .ml_stand
        cmp  eax, BTN_HIT_X + BTN_W
        jg   .ml_stand
        cmp  ebx, BTN_Y
        jl   .ml_stand
        cmp  ebx, BTN_Y + BTN_H
        jg   .ml_stand
        jmp  .do_hit
.ml_stand:
        cmp  eax, BTN_STAND_X
        jl   .main_loop
        cmp  eax, BTN_STAND_X + BTN_W
        jg   .main_loop
        cmp  ebx, BTN_Y
        jl   .main_loop
        cmp  ebx, BTN_Y + BTN_H
        jg   .main_loop
        jmp  .do_stand

.do_hit:
        call draw_card_from_deck
        mov  ecx, [p_count]
        cmp  ecx, MAX_HAND
        jge  .do_stand
        mov  [p_hand + ecx], al
        inc  dword [p_count]
        mov  esi, p_hand
        mov  ecx, [p_count]
        call hand_total
        cmp  eax, 21
        jg   .player_bust
        je   .do_stand
        jmp  .main_loop

.player_bust:
        mov  byte [player_busted], 1
        mov  byte [dealer_revealed], 1
        call resolve_round
        jmp  .result_wait

.do_stand:
        mov  byte [dealer_revealed], 1
        call dealer_turn
        call resolve_round

.result_wait:
        call render_scene
        VBE_GAME_PRESENT

.rw_loop:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .rw_mouse
        cmp  eax, KEY_ESC
        je   .quit
        cmp  eax, KEY_Q
        je   .quit
        cmp  eax, 'Q'
        je   .quit
        cmp  eax, -1
        je   .rw_loop
        jmp  .new_round

.rw_mouse:
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz   .rw_loop
        call wait_mouse_up_bj
        jmp  .new_round

.quit:
        mov  eax, SYS_FRAMEBUF
        mov  ebx, 2
        int  0x80
        mov  eax, SYS_EXIT
        xor  ebx, ebx
        int  0x80

;=======================================================================
wait_mouse_up_bj:
        push eax
        push ebx
        push ecx
.wmu:   mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jnz  .wmu
        pop  ecx
        pop  ebx
        pop  eax
        ret

;=======================================================================
shuffle_deck:
        pushad
        xor  ecx, ecx
.sd_init:
        cmp  ecx, 52
        jge  .sd_shuf
        mov  [deck + ecx], cl
        inc  ecx
        jmp  .sd_init
.sd_shuf:
        mov  eax, SYS_GETTIME
        int  0x80
        imul eax, eax, 1103515245
        add  eax, 12345
        mov  [rng_state], eax
        mov  ecx, 51
.sd_loop:
        cmp  ecx, 0
        jle  .sd_done
        mov  eax, [rng_state]
        imul eax, eax, 1103515245
        add  eax, 12345
        mov  [rng_state], eax
        xor  edx, edx
        inc  ecx
        div  ecx
        dec  ecx
        movzx eax, byte [deck + ecx]
        movzx ebx, byte [deck + edx]
        mov  [deck + ecx], bl
        mov  [deck + edx], al
        dec  ecx
        jmp  .sd_loop
.sd_done:
        mov  dword [deck_pos], 0
        popad
        ret

draw_card_from_deck:
        mov  eax, [deck_pos]
        movzx eax, byte [deck + eax]
        inc  dword [deck_pos]
        ret

card_value:
        pushad
        movzx eax, al
        xor  edx, edx
        mov  ecx, 13
        div  ecx
        cmp  edx, 0
        je   .cv_ace
        cmp  edx, 9
        jle  .cv_pip
        mov  dword [esp+28], 10
        popad
        ret
.cv_pip:
        inc  edx
        mov  [esp+28], edx
        popad
        ret
.cv_ace:
        mov  dword [esp+28], 11
        popad
        ret

hand_total:
        pushad
        xor  edi, edi
        xor  ebp, ebp
        xor  ebx, ebx
.ht_loop:
        cmp  ebx, ecx
        jge  .ht_adj
        push ecx
        movzx eax, byte [esi + ebx]
        call card_value
        add  edi, eax
        movzx eax, byte [esi + ebx]
        xor  edx, edx
        mov  ecx, 13
        div  ecx
        cmp  edx, 0
        jne  .ht_na
        inc  ebp
.ht_na:
        pop  ecx
        inc  ebx
        jmp  .ht_loop
.ht_adj:
.ht_al:
        cmp  edi, 21
        jle  .ht_done
        cmp  ebp, 0
        je   .ht_done
        sub  edi, 10
        dec  ebp
        jmp  .ht_al
.ht_done:
        mov  [esp+28], edi
        popad
        ret

deal_initial:
        pushad
        mov  byte [player_busted], 0
        mov  dword [p_count], 0
        mov  dword [d_count], 0
        call draw_card_from_deck
        mov  [p_hand], al
        mov  dword [p_count], 1
        call draw_card_from_deck
        mov  [d_hand], al
        mov  dword [d_count], 1
        call draw_card_from_deck
        mov  ecx, [p_count]
        mov  [p_hand + ecx], al
        inc  dword [p_count]
        call draw_card_from_deck
        mov  ecx, [d_count]
        mov  [d_hand + ecx], al
        inc  dword [d_count]
        popad
        ret

dealer_turn:
        pushad
.dt_loop:
        mov  esi, d_hand
        mov  ecx, [d_count]
        call hand_total
        cmp  eax, 17
        jge  .dt_done
        call draw_card_from_deck
        mov  ecx, [d_count]
        cmp  ecx, MAX_HAND
        jge  .dt_done
        mov  [d_hand + ecx], al
        inc  dword [d_count]
        jmp  .dt_loop
.dt_done:
        popad
        ret

resolve_round:
        pushad
        mov  esi, p_hand
        mov  ecx, [p_count]
        call hand_total
        mov  [p_total_save], eax
        mov  esi, d_hand
        mov  ecx, [d_count]
        call hand_total
        mov  [d_total_save], eax

        cmp  byte [player_busted], 1
        je   .rr_lose
        mov  eax, [d_total_save]
        cmp  eax, 21
        jg   .rr_win
        mov  eax, [p_total_save]
        cmp  eax, [d_total_save]
        jg   .rr_win
        jl   .rr_lose
        inc  dword [ties]
        mov  byte [round_result], 2
        jmp  .rr_done
.rr_win:
        inc  dword [p_wins]
        mov  byte [round_result], 1
        ; Bump persistent wins, save, win SFX
        mov  eax, [total_wins]
        inc  eax
        mov  [total_wins], eax
        mov  ebx, [total_wins]
        mov  esi, hs_name_bj
        call hs_save
        call audio_sfx_win
        jmp  .rr_done
.rr_lose:
        inc  dword [d_wins]
        mov  byte [round_result], 0
        call audio_sfx_lose
.rr_done:
        mov  byte [game_state], STATE_RESULT
        popad
        ret

;=======================================================================
; render_scene
;=======================================================================
render_scene:
        pushad

        ; Background
        mov  edx, COL_FELT_DARK
        call vbe_clear_screen

        ; Green felt area
        mov  ebx, 20
        mov  ecx, 60
        mov  edx, 984
        mov  esi, 630
        mov  edi, COL_FELT
        call vbe_fill_rect

        ; Title bar
        mov  ebx, 0
        mov  ecx, 0
        mov  edx, 1024
        mov  esi, 55
        mov  edi, 0x00222222
        call vbe_fill_rect

        ; Title
        mov  ebx, 370
        mov  ecx, 8
        mov  edx, str_title
        mov  esi, COL_GOLD
        mov  eax, 3
        call vbe_draw_str

        ; Score panel
        mov  ebx, PANEL_X
        mov  ecx, PANEL_Y
        mov  edx, PANEL_W
        mov  esi, PANEL_H
        mov  edi, COL_PANEL
        call vbe_fill_rect

        mov  ebx, PANEL_X
        mov  ecx, PANEL_Y
        mov  edx, PANEL_W
        mov  esi, 2
        mov  edi, COL_GOLD
        call vbe_fill_rect
        mov  ebx, PANEL_X
        mov  ecx, PANEL_Y + PANEL_H - 2
        mov  edx, PANEL_W
        mov  esi, 2
        mov  edi, COL_GOLD
        call vbe_fill_rect

        ; You score
        mov  ebx, PANEL_X + 16
        mov  ecx, PANEL_Y + 16
        mov  edx, str_you_lbl
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, PANEL_X + 16
        mov  ecx, PANEL_Y + 30
        mov  edx, [p_wins]
        mov  esi, 0x0066FF66
        mov  eax, 3
        call vbe_draw_num

        ; Dealer score
        mov  ebx, PANEL_X + 16
        mov  ecx, PANEL_Y + 90
        mov  edx, str_dealer_lbl
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, PANEL_X + 16
        mov  ecx, PANEL_Y + 104
        mov  edx, [d_wins]
        mov  esi, COL_RED
        mov  eax, 3
        call vbe_draw_num

        ; Ties
        mov  ebx, PANEL_X + 16
        mov  ecx, PANEL_Y + 164
        mov  edx, str_ties
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, PANEL_X + 16
        mov  ecx, PANEL_Y + 178
        mov  edx, [ties]
        mov  esi, COL_PUSH_MSG
        mov  eax, 3
        call vbe_draw_num

        ; Key hint
        mov  ebx, PANEL_X + 10
        mov  ecx, PANEL_Y + 250
        mov  edx, str_hint
        mov  esi, COL_DARKGRAY
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, PANEL_X + 10
        mov  ecx, PANEL_Y + 264
        mov  edx, str_hint2
        mov  esi, COL_DARKGRAY
        mov  eax, 1
        call vbe_draw_str

        ; Section labels
        mov  ebx, 80
        mov  ecx, 130
        mov  edx, str_dealer_hand
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str

        mov  ebx, 80
        mov  ecx, 420
        mov  edx, str_your_hand
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str

        ; ---- Dealer cards ----
        mov  ecx, [d_count]
        xor  ebx, ebx

.rs_dl:
        cmp  ebx, ecx
        jge  .rs_dl_done
        push ebx
        push ecx
        ; compute x = DEALER_CARD_X + ebx * CARD_STEP
        mov  eax, ebx
        imul eax, CARD_STEP
        add  eax, DEALER_CARD_X
        ; hide second card when not revealed
        cmp  ebx, 1
        jne  .rs_dl_face
        cmp  byte [dealer_revealed], 0
        je   .rs_dl_back
.rs_dl_face:
        mov  [.rs_tmp], ebx
        movzx edx, byte [d_hand + ebx]
        mov  ebx, DEALER_Y
        call draw_card_gfx       ; EAX=x, EBX=y, EDX=card
        mov  ebx, [.rs_tmp]
        jmp  .rs_dl_next
.rs_dl_back:
        mov  ebx, DEALER_Y
        call draw_card_back      ; EAX=x, EBX=y
.rs_dl_next:
        pop  ecx
        pop  ebx
        inc  ebx
        jmp  .rs_dl

.rs_dl_done:
        ; Dealer total (when revealed)
        cmp  byte [dealer_revealed], 0
        je   .rs_skip_dt
        mov  esi, d_hand
        mov  ecx, [d_count]
        call hand_total
        mov  ebx, 80
        mov  ecx, DEALER_Y + CARD_H + 10
        mov  edx, eax
        mov  esi, COL_WHITE
        mov  eax, 2
        call vbe_draw_num
.rs_skip_dt:

        ; ---- Player cards ----
        mov  ecx, [p_count]
        xor  ebx, ebx

.rs_pl:
        cmp  ebx, ecx
        jge  .rs_pl_done
        push ebx
        push ecx
        mov  eax, ebx
        imul eax, CARD_STEP
        add  eax, PLAYER_CARD_X
        mov  [.rs_tmp], ebx
        movzx edx, byte [p_hand + ebx]
        mov  ebx, PLAYER_Y
        call draw_card_gfx
        mov  ebx, [.rs_tmp]
        pop  ecx
        pop  ebx
        inc  ebx
        jmp  .rs_pl

.rs_pl_done:
        ; Player total
        mov  esi, p_hand
        mov  ecx, [p_count]
        call hand_total
        mov  [.rs_pt], eax
        mov  ebx, 80
        mov  ecx, PLAYER_Y + CARD_H + 10
        mov  edx, [.rs_pt]
        mov  esi, COL_WHITE
        cmp  dword [.rs_pt], 21
        jle  .rs_pt_ok
        mov  esi, COL_RED
.rs_pt_ok:
        mov  eax, 2
        call vbe_draw_num

        ; ---- Buttons ----
        cmp  byte [game_state], STATE_PLAYER
        jne  .rs_no_btns

        ; Hit
        mov  ebx, BTN_HIT_X
        mov  ecx, BTN_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_BTN_HIT
        call vbe_fill_rect
        mov  ebx, BTN_HIT_X + 14
        mov  ecx, BTN_Y + 12
        mov  edx, str_hit
        mov  esi, COL_WHITE
        mov  eax, 2
        call vbe_draw_str

        ; Stand
        mov  ebx, BTN_STAND_X
        mov  ecx, BTN_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_BTN_STAND
        call vbe_fill_rect
        mov  ebx, BTN_STAND_X + 8
        mov  ecx, BTN_Y + 12
        mov  edx, str_stand
        mov  esi, COL_WHITE
        mov  eax, 2
        call vbe_draw_str

.rs_no_btns:
        ; ---- Result overlay ----
        cmp  byte [game_state], STATE_RESULT
        jne  .rs_done

        ; Dark strip
        mov  ebx, 60
        mov  ecx, RESULT_Y
        mov  edx, 700
        mov  esi, 80
        mov  edi, 0x00111111
        call vbe_fill_rect

        ; Result text
        movzx eax, byte [round_result]
        cmp  eax, 1
        je   .rs_win
        cmp  eax, 2
        je   .rs_push
        ; lose/bust
        mov  edx, str_lose
        cmp  byte [player_busted], 1
        jne  .rs_show
        mov  edx, str_bust
        jmp  .rs_show
.rs_win:
        mov  edx, str_win
        jmp  .rs_show
.rs_push:
        mov  edx, str_push
.rs_show:
        mov  ebx, 80
        mov  ecx, RESULT_Y + 12
        movzx eax, byte [round_result]
        cmp  eax, 1
        je   .rs_col_win
        cmp  eax, 2
        je   .rs_col_push
        mov  esi, COL_LOSE_MSG
        jmp  .rs_drawmsg
.rs_col_win:
        mov  esi, COL_WIN_MSG
        jmp  .rs_drawmsg
.rs_col_push:
        mov  esi, COL_PUSH_MSG
.rs_drawmsg:
        mov  eax, 3
        call vbe_draw_str

        ; "Play again" prompt
        mov  ebx, 80
        mov  ecx, RESULT_Y + 55
        mov  edx, str_again
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str

.rs_done:
        popad
        ret

.rs_tmp:    dd 0
.rs_pt:     dd 0

;=======================================================================
; draw_card_gfx  EAX=x, EBX=y, EDX=card(0-51)
;=======================================================================
draw_card_gfx:
        pushad
        mov  [.x],    eax
        mov  [.y],    ebx
        mov  [.card], edx

        ; White card body
        mov  ebx, [.x]
        mov  ecx, [.y]
        mov  edx, CARD_W
        mov  esi, CARD_H
        mov  edi, COL_CARD_BG
        call vbe_fill_rect

        ; Border (2px all sides)
        mov  ebx, [.x]
        mov  ecx, [.y]
        mov  edx, CARD_W
        mov  esi, 2
        mov  edi, COL_CARD_BORDER
        call vbe_fill_rect
        mov  ebx, [.x]
        mov  ecx, [.y]
        add  ecx, CARD_H - 2
        mov  edx, CARD_W
        mov  esi, 2
        mov  edi, COL_CARD_BORDER
        call vbe_fill_rect
        mov  ebx, [.x]
        mov  ecx, [.y]
        mov  edx, 2
        mov  esi, CARD_H
        mov  edi, COL_CARD_BORDER
        call vbe_fill_rect
        mov  ebx, [.x]
        add  ebx, CARD_W - 2
        mov  ecx, [.y]
        mov  edx, 2
        mov  esi, CARD_H
        mov  edi, COL_CARD_BORDER
        call vbe_fill_rect

        ; Decode: suit = card/13, rank = card%13
        movzx eax, byte [.card]
        xor   edx, edx
        mov   ecx, 13
        div   ecx
        mov   [.suit], eax
        mov   [.rank], edx

        ; Colour: hearts(1)/diamonds(2) = red, spades(0)/clubs(3) = dark
        mov  esi, 0x00BB0000
        cmp  eax, 1
        je   .dcg_red
        cmp  eax, 2
        je   .dcg_red
        mov  esi, 0x00111111
.dcg_red:
        mov  [.col], esi

        ; Build rank string in rank_buf
        mov  edi, rank_buf
        mov  eax, [.rank]
        cmp  eax, 0
        je   .r_ace
        cmp  eax, 9
        je   .r_ten
        cmp  eax, 10
        je   .r_jack
        cmp  eax, 11
        je   .r_queen
        cmp  eax, 12
        je   .r_king
        ; numeric 2-9
        inc  eax
        add  al, '0'
        mov  [edi], al
        mov  byte [edi+1], 0
        jmp  .draw_rank
.r_ace:
        mov  byte [edi], 'A'
        mov  byte [edi+1], 0
        jmp  .draw_rank
.r_ten:
        mov  byte [edi],   '1'
        mov  byte [edi+1], '0'
        mov  byte [edi+2], 0
        jmp  .draw_rank
.r_jack:
        mov  byte [edi], 'J'
        mov  byte [edi+1], 0
        jmp  .draw_rank
.r_queen:
        mov  byte [edi], 'Q'
        mov  byte [edi+1], 0
        jmp  .draw_rank
.r_king:
        mov  byte [edi], 'K'
        mov  byte [edi+1], 0

.draw_rank:
        ; Rank top-left (scale 2)
        mov  ebx, [.x]
        add  ebx, 6
        mov  ecx, [.y]
        add  ecx, 6
        mov  edx, rank_buf
        mov  esi, [.col]
        mov  eax, 2
        call vbe_draw_str

        ; Suit letter centred (scale 3)
        mov  eax, [.suit]
        cmp  eax, 0
        je   .s_spade
        cmp  eax, 1
        je   .s_heart
        cmp  eax, 2
        je   .s_diamond
        mov  edx, 'C'
        jmp  .draw_suit
.s_spade:
        mov  edx, 'S'
        jmp  .draw_suit
.s_heart:
        mov  edx, 'H'
        jmp  .draw_suit
.s_diamond:
        mov  edx, 'D'
.draw_suit:
        mov  ebx, [.x]
        add  ebx, 24
        mov  ecx, [.y]
        add  ecx, 42
        mov  esi, [.col]
        mov  eax, 3
        call vbe_draw_char

        popad
        ret

.x:    dd 0
.y:    dd 0
.card: dd 0
.suit: dd 0
.rank: dd 0
.col:  dd 0

;=======================================================================
; draw_card_back  EAX=x, EBX=y
;=======================================================================
draw_card_back:
        pushad
        mov  [.x], eax
        mov  [.y], ebx

        mov  ebx, [.x]
        mov  ecx, [.y]
        mov  edx, CARD_W
        mov  esi, CARD_H
        mov  edi, 0x00183060
        call vbe_fill_rect

        mov  ebx, [.x]
        add  ebx, 6
        mov  ecx, [.y]
        add  ecx, 6
        mov  edx, CARD_W - 12
        mov  esi, CARD_H - 12
        mov  edi, 0x00224488
        call vbe_fill_rect

        mov  ebx, [.x]
        add  ebx, 26
        mov  ecx, [.y]
        add  ecx, 38
        mov  edx, '?'
        mov  esi, 0x00AACCFF
        mov  eax, 3
        call vbe_draw_char

        popad
        ret

.x: dd 0
.y: dd 0

;=======================================================================
; Data
;=======================================================================
str_title:      db "BLACKJACK", 0
str_you_lbl:    db "YOU", 0
str_dealer_lbl: db "DEALER", 0
str_ties:       db "TIES", 0
str_dealer_hand: db "DEALER", 0
str_your_hand:  db "YOU", 0
str_hit:        db "HIT  H", 0
str_stand:      db "STAND  S", 0
str_win:        db "YOU WIN!", 0
str_bust:       db "BUST!  DEALER WINS", 0
str_lose:       db "DEALER WINS", 0
str_push:       db "PUSH", 0
str_again:      db "Click or any key for next round   Q=Quit", 0
str_hint:       db "H=Hit  S=Stand", 0
str_hint2:      db "Q=Quit", 0

deck:           times 52 db 0
deck_pos:       dd 0
rng_state:      dd 0
p_hand:         times MAX_HAND db 0
d_hand:         times MAX_HAND db 0
p_count:        dd 0
d_count:        dd 0
p_wins:         dd 0
d_wins:         dd 0
ties:           dd 0
hs_name_bj:     db "blackjack", 0
total_wins:     dd 0
player_busted:  db 0
dealer_revealed: db 0
game_state:     db 0
round_result:   db 0
p_total_save:   dd 0
d_total_save:   dd 0

rank_buf: times 4 db 0
