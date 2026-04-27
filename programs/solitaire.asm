; solitaire.asm - Klondike Solitaire for Mellivora OS (VBE graphics)
; Mouse-driven: click stock to draw, click cards to auto-move.

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

; Card dimensions
CARD_W          equ 58
CARD_H          equ 75
CARD_GAP        equ 8
CARD_OVERLAP    equ 16
CARD_OVERLAP_UP equ 20

; Layout
STOCK_X         equ 10
STOCK_Y         equ 10
WASTE_X         equ 78
WASTE_Y         equ 10
FOUND_X         equ 228
FOUND_Y         equ 10
TAB_X           equ 10
TAB_Y           equ 100
TAB_SPACING     equ 90

; Card encoding: (suit << 4) | rank
; rank: 1=A .. 13=K
; suit: 0=Hearts, 1=Diamonds, 2=Clubs, 3=Spades
NUM_CARDS       equ 52
NUM_SUITS       equ 4
NUM_RANKS       equ 13
NUM_TABLEAU     equ 7
NUM_FOUNDATIONS equ 4
SUIT_HEARTS     equ 0
SUIT_DIAMONDS   equ 1
SUIT_CLUBS      equ 2
SUIT_SPADES     equ 3

; Colours
COL_FELT        equ 0x00206020
COL_CARD_FACE   equ 0x00FFFFFF
COL_CARD_BACK   equ 0x000044AA
COL_CARD_BRD    equ 0x00333333
COL_RED         equ 0x00CC0000
COL_BLACK_C     equ 0x00111111
COL_EMPTY_SLOT  equ 0x00306830
COL_GOLD        equ 0x00FFD700

start:
        VBE_GAME_INIT
        call game_init

.main_loop:
        call render_game
        VBE_GAME_PRESENT

        cmp  byte [game_won], 1
        je   .poll_win

        ; keyboard
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        jne  .check_key

        ; mouse
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz   .main_loop
        call wait_mouse_up_sol
        ; EAX=x, EBX=y
        mov  ecx, ebx
        mov  ebx, eax
        call handle_click
        jmp  .main_loop

.check_key:
        cmp  eax, KEY_ESC
        je   .quit
        cmp  eax, KEY_Q
        je   .quit
        cmp  eax, 'Q'
        je   .quit
        cmp  eax, KEY_R
        je   .new_game
        jmp  .main_loop

.poll_win:
        call render_game
        VBE_GAME_PRESENT
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .poll_win
        cmp  eax, KEY_ESC
        je   .quit
        cmp  eax, KEY_Q
        je   .quit
        cmp  eax, 'Q'
        je   .quit
.new_game:
        call game_init
        jmp  .main_loop

.quit:
        mov  eax, SYS_FRAMEBUF
        mov  ebx, 2
        int  0x80
        mov  eax, SYS_EXIT
        xor  ebx, ebx
        int  0x80

;----------------------------------------------------
wait_mouse_up_sol:
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

;====================================================
; GAME INITIALIZATION
;====================================================
game_init:
        pushad
        mov  eax, SYS_GETTIME
        int  0x80
        mov  [rng_state], eax
        mov  byte [game_won], 0
        mov  dword [selected_pile], -1
        mov  dword [selected_idx],  -1
        mov  dword [moves], 0
        ; First-call: load persistent total wins from /scores/solitaire
        cmp  byte [hs_loaded], 0
        jne  .gi_loaded
        mov  byte [hs_loaded], 1
        mov  esi, hs_name_st
        call hs_load
        mov  [total_wins], eax
.gi_loaded:

        ; Build deck
        xor  ecx, ecx
        xor  edx, edx
.build_suit:
        cmp  edx, NUM_SUITS
        jge  .shuffle
        mov  ebx, 1
.build_rank:
        cmp  ebx, NUM_RANKS + 1
        jge  .next_suit
        mov  al, dl
        shl  al, 4
        or   al, bl
        mov  [deck + ecx], al
        inc  ecx
        inc  ebx
        jmp  .build_rank
.next_suit:
        inc  edx
        jmp  .build_suit

.shuffle:
        mov  ecx, NUM_CARDS - 1
.shuf_loop:
        cmp  ecx, 0
        jle  .deal
        call rng_next
        xor  edx, edx
        mov  ebx, ecx
        inc  ebx
        div  ebx
        movzx eax, byte [deck + ecx]
        movzx ebx, byte [deck + edx]
        mov  [deck + ecx], bl
        mov  [deck + edx], al
        dec  ecx
        jmp  .shuf_loop

.deal:
        ; Clear piles
        mov  edi, tab_data
        xor  eax, eax
        mov  ecx, 7 * 20
        rep  stosb
        mov  edi, tab_count
        mov  ecx, 7
        rep  stosb
        mov  edi, tab_faceup
        mov  ecx, 7
        rep  stosb
        mov  edi, found_data
        mov  ecx, 4 * 14
        rep  stosb
        mov  edi, found_count
        mov  ecx, 4
        rep  stosb
        mov  edi, stock_data
        mov  ecx, 24
        rep  stosb
        mov  edi, waste_data
        mov  ecx, 24
        rep  stosb
        mov  dword [stock_count], 0
        mov  dword [waste_count], 0

        ; Deal tableau
        xor  esi, esi
        xor  edi, edi
.deal_col:
        cmp  edi, NUM_TABLEAU
        jge  .deal_stock
        xor  ecx, ecx
.deal_card:
        lea  eax, [edi + 1]
        cmp  ecx, eax
        jge  .deal_col_done
        movzx eax, byte [deck + esi]
        imul ebx, edi, 20
        add  ebx, ecx
        mov  [tab_data + ebx], al
        inc  ecx
        inc  esi
        jmp  .deal_card
.deal_col_done:
        mov  [tab_count + edi], cl
        dec  cl
        mov  [tab_faceup + edi], cl
        inc  edi
        jmp  .deal_col

.deal_stock:
        xor  ecx, ecx
.stock_fill:
        cmp  esi, NUM_CARDS
        jge  .deal_done
        movzx eax, byte [deck + esi]
        mov  [stock_data + ecx], al
        inc  ecx
        inc  esi
        jmp  .stock_fill
.deal_done:
        mov  [stock_count], ecx
        popad
        ret

;====================================================
; RENDERING
;====================================================
render_game:
        pushad
        ; Green felt background
        mov  edx, COL_FELT
        call vbe_clear_screen

        ; Title
        mov  ebx, 565
        mov  ecx, 12
        mov  edx, str_title
        mov  esi, 0x00AACCAA
        mov  eax, 1
        call vbe_draw_str

        ; Stock
        cmp  dword [stock_count], 0
        je   .rg_empty_stock
        mov  ebx, STOCK_X
        mov  ecx, STOCK_Y
        call draw_card_back
        jmp  .rg_waste
.rg_empty_stock:
        mov  ebx, STOCK_X
        mov  ecx, STOCK_Y
        call draw_empty_slot

.rg_waste:
        mov  eax, [waste_count]
        cmp  eax, 0
        je   .rg_empty_waste
        dec  eax
        movzx edx, byte [waste_data + eax]
        mov  ebx, WASTE_X
        mov  ecx, WASTE_Y
        call draw_card_face
        jmp  .rg_foundations
.rg_empty_waste:
        mov  ebx, WASTE_X
        mov  ecx, WASTE_Y
        call draw_empty_slot

.rg_foundations:
        xor  esi, esi
.rg_fnd:
        cmp  esi, NUM_FOUNDATIONS
        jge  .rg_tableau
        imul ebx, esi, (CARD_W + CARD_GAP)
        add  ebx, FOUND_X
        movzx eax, byte [found_count + esi]
        cmp  eax, 0
        je   .rg_fnd_empty
        dec  eax
        imul ecx, esi, 14
        movzx edx, byte [found_data + ecx + eax]
        mov  ecx, FOUND_Y
        call draw_card_face
        jmp  .rg_fnd_next
.rg_fnd_empty:
        mov  ecx, FOUND_Y
        call draw_empty_slot
.rg_fnd_next:
        inc  esi
        jmp  .rg_fnd

.rg_tableau:
        xor  esi, esi           ; column 0..NUM_TABLEAU-1
.rg_tab_col:
        cmp  esi, NUM_TABLEAU
        jge  .rg_status
        movzx eax, byte [tab_count + esi]
        test eax, eax
        jz   .rg_tab_empty_col

        ; col_x = TAB_X + col * TAB_SPACING
        imul ebx, esi, TAB_SPACING
        add  ebx, TAB_X
        mov  [.rg_col_x], ebx

        movzx eax, byte [tab_faceup + esi]
        mov  [.rg_faceup], eax

        xor  ecx, ecx           ; card_idx = 0
.rg_card_loop:
        movzx eax, byte [tab_count + esi]
        cmp  ecx, eax
        jge  .rg_col_done

        mov  [.rg_cidx], ecx

        ; Compute pixel_y
        mov  edx, [.rg_faceup]
        cmp  ecx, edx
        jb   .rg_y_hidden
        ; face-up: y = TAB_Y + faceup*CARD_OVERLAP + (idx-faceup)*CARD_OVERLAP_UP
        imul eax, edx, CARD_OVERLAP
        mov  ebx, ecx
        sub  ebx, edx
        imul ebx, CARD_OVERLAP_UP
        add  eax, ebx
        add  eax, TAB_Y
        mov  [.rg_pix_y], eax
        jmp  .rg_y_done
.rg_y_hidden:
        ; face-down: y = TAB_Y + idx * CARD_OVERLAP
        imul eax, ecx, CARD_OVERLAP
        add  eax, TAB_Y
        mov  [.rg_pix_y], eax
.rg_y_done:
        ; draw card: EBX=col_x, ECX=pixel_y
        mov  ebx, [.rg_col_x]
        mov  ecx, [.rg_pix_y]
        mov  eax, [.rg_cidx]
        cmp  eax, [.rg_faceup]
        jb   .rg_face_down
        ; face up: card = tab_data[col*20 + card_idx]
        imul edx, esi, 20
        add  edx, eax
        movzx edx, byte [tab_data + edx]
        call draw_card_face
        jmp  .rg_card_next
.rg_face_down:
        call draw_card_back
.rg_card_next:
        mov  ecx, [.rg_cidx]
        inc  ecx
        jmp  .rg_card_loop

.rg_col_done:
        inc  esi
        jmp  .rg_tab_col

.rg_tab_empty_col:
        imul ebx, esi, TAB_SPACING
        add  ebx, TAB_X
        mov  ecx, TAB_Y
        call draw_empty_slot
        inc  esi
        jmp  .rg_tab_col

.rg_status:
        ; Status bar
        mov  ebx, 10
        mov  ecx, 460
        mov  edx, str_status
        mov  esi, 0x00AACCAA
        mov  eax, 1
        call vbe_draw_str

        cmp  byte [game_won], 1
        jne  .rg_done
        mov  ebx, 200
        mov  ecx, 200
        mov  edx, str_win
        mov  esi, COL_GOLD
        mov  eax, 3
        call vbe_draw_str

.rg_done:
        popad
        ret

.rg_cidx:   dd 0
.rg_col_x:  dd 0
.rg_faceup: dd 0
.rg_pix_y:  dd 0

;----------------------------------------------------
; draw_card_face: EBX=x, ECX=y, EDX=card
draw_card_face:
        pushad
        mov  [.cf_card], dl
        mov  [.cf_x],    ebx
        mov  [.cf_y],    ecx

        ; White bg
        mov  edx, CARD_W
        mov  esi, CARD_H
        mov  edi, COL_CARD_FACE
        call vbe_fill_rect

        ; Border
        mov  ebx, [.cf_x]
        mov  ecx, [.cf_y]
        mov  edx, CARD_W
        mov  esi, COL_CARD_BRD
        call vbe_draw_hline
        mov  ecx, [.cf_y]
        add  ecx, CARD_H - 1
        call vbe_draw_hline
        mov  ecx, [.cf_y]
        mov  edx, CARD_H
        call vbe_draw_vline
        mov  ebx, [.cf_x]
        add  ebx, CARD_W - 1
        call vbe_draw_vline

        ; Suit and colour
        movzx eax, byte [.cf_card]
        shr  al, 4
        ; suit: 0=H,1=D,2=C,3=S
        cmp  al, 2
        jl   .cf_red
        mov  dword [.cf_color], COL_BLACK_C
        jmp  .cf_rank
.cf_red:
        mov  dword [.cf_color], COL_RED

.cf_rank:
        movzx eax, byte [.cf_card]
        and  al, 0x0F
        dec  al
        cmp  al, 13
        jge  .cf_done
        ; Rank char
        movzx edx, byte [rank_chars_s + eax]
        mov  ebx, [.cf_x]
        add  ebx, 4
        mov  ecx, [.cf_y]
        add  ecx, 4
        mov  esi, [.cf_color]
        mov  eax, 2
        call vbe_draw_char

        ; Suit char
        movzx eax, byte [.cf_card]
        shr  al, 4
        movzx edx, byte [suit_chars_s + eax]
        mov  ebx, [.cf_x]
        add  ebx, 4
        mov  ecx, [.cf_y]
        add  ecx, 20
        mov  esi, [.cf_color]
        mov  eax, 2
        call vbe_draw_char
.cf_done:
        popad
        ret

.cf_card:  db 0
.cf_x:     dd 0
.cf_y:     dd 0
.cf_color: dd 0

;----------------------------------------------------
; draw_card_back: EBX=x, ECX=y
draw_card_back:
        pushad
        mov  [.cb_x], ebx
        mov  [.cb_y], ecx
        ; Blue back
        mov  edx, CARD_W
        mov  esi, CARD_H
        mov  edi, COL_CARD_BACK
        call vbe_fill_rect
        ; Border
        mov  edx, CARD_W
        mov  esi, COL_CARD_BRD
        call vbe_draw_hline
        mov  ecx, [.cb_y]
        add  ecx, CARD_H - 1
        call vbe_draw_hline
        mov  ecx, [.cb_y]
        mov  edx, CARD_H
        call vbe_draw_vline
        mov  ebx, [.cb_x]
        add  ebx, CARD_W - 1
        mov  ecx, [.cb_y]
        call vbe_draw_vline
        ; Inner lighter rect
        mov  ebx, [.cb_x]
        add  ebx, 5
        mov  ecx, [.cb_y]
        add  ecx, 5
        mov  edx, CARD_W - 10
        mov  esi, CARD_H - 10
        mov  edi, 0x000066CC
        call vbe_fill_rect
        popad
        ret
.cb_x: dd 0
.cb_y: dd 0

;----------------------------------------------------
; draw_empty_slot: EBX=x, ECX=y
draw_empty_slot:
        pushad
        mov  edx, CARD_W
        mov  esi, CARD_H
        mov  edi, COL_EMPTY_SLOT
        call vbe_fill_rect
        popad
        ret

;====================================================
; INPUT HANDLING  (unchanged logic, win_id removed)
;====================================================
handle_click:
        pushad
        mov  [.hc_x], ebx
        mov  [.hc_y], ecx

        cmp  byte [game_won], 1
        je   .hc_done

        ; Stock
        cmp  dword [.hc_x], STOCK_X
        jl   .hc_waste
        cmp  dword [.hc_x], STOCK_X + CARD_W
        jg   .hc_waste
        cmp  dword [.hc_y], STOCK_Y
        jl   .hc_waste
        cmp  dword [.hc_y], STOCK_Y + CARD_H
        jg   .hc_waste
        call stock_click
        jmp  .hc_done

.hc_waste:
        cmp  dword [.hc_x], WASTE_X
        jl   .hc_found
        cmp  dword [.hc_x], WASTE_X + CARD_W
        jg   .hc_found
        cmp  dword [.hc_y], WASTE_Y
        jl   .hc_found
        cmp  dword [.hc_y], WASTE_Y + CARD_H
        jg   .hc_found
        call waste_click
        jmp  .hc_done

.hc_found:
        xor  esi, esi
.hc_found_loop:
        cmp  esi, NUM_FOUNDATIONS
        jge  .hc_tab
        imul eax, esi, (CARD_W + CARD_GAP)
        add  eax, FOUND_X
        cmp  dword [.hc_x], eax
        jl   .hc_found_next
        add  eax, CARD_W
        cmp  dword [.hc_x], eax
        jg   .hc_found_next
        cmp  dword [.hc_y], FOUND_Y
        jl   .hc_found_next
        mov  eax, FOUND_Y + CARD_H
        cmp  dword [.hc_y], eax
        jg   .hc_found_next
        jmp  .hc_done
.hc_found_next:
        inc  esi
        jmp  .hc_found_loop

.hc_tab:
        xor  esi, esi
.hc_tab_loop:
        cmp  esi, NUM_TABLEAU
        jge  .hc_done
        imul eax, esi, TAB_SPACING
        add  eax, TAB_X
        cmp  dword [.hc_x], eax
        jl   .hc_tab_next
        add  eax, CARD_W
        cmp  dword [.hc_x], eax
        jg   .hc_tab_next

        movzx eax, byte [tab_count + esi]
        cmp  eax, 0
        je   .hc_tab_next

        mov  eax, [.hc_y]
        sub  eax, TAB_Y
        cmp  eax, 0
        jl   .hc_tab_next

        movzx ebx, byte [tab_count + esi]
        movzx edi, byte [tab_faceup + esi]
        call tab_find_card_at_y

        cmp  eax, -1
        je   .hc_tab_next

        cmp  eax, edi
        jb   .hc_tab_flip

        push esi
        push eax
        call try_auto_move
        pop  eax
        pop  esi
        jmp  .hc_done

.hc_tab_flip:
        movzx ecx, byte [tab_count + esi]
        dec  ecx
        cmp  eax, ecx
        jne  .hc_tab_next
        mov  [tab_faceup + esi], al
        jmp  .hc_done

.hc_tab_next:
        inc  esi
        jmp  .hc_tab_loop

.hc_done:
        call check_win
        popad
        ret

.hc_x: dd 0
.hc_y: dd 0

;----------------------------------------------------
tab_find_card_at_y:
        push ecx
        push edx
        mov  ecx, ebx
        dec  ecx
.tfcy:
        cmp  ecx, -1
        je   .tfcy_none
        push eax
        cmp  ecx, edi
        jb   .tfcy_hidden
        mov  edx, ecx
        sub  edx, edi
        imul edx, CARD_OVERLAP_UP
        push ecx
        imul ecx, edi, CARD_OVERLAP
        add  edx, ecx
        pop  ecx
        jmp  .tfcy_chk
.tfcy_hidden:
        imul edx, ecx, CARD_OVERLAP
.tfcy_chk:
        pop  eax
        cmp  eax, edx
        jge  .tfcy_found
        dec  ecx
        jmp  .tfcy
.tfcy_found:
        mov  eax, ecx
        pop  edx
        pop  ecx
        ret
.tfcy_none:
        mov  eax, -1
        pop  edx
        pop  ecx
        ret

;====================================================
; GAME LOGIC (identical to original, win_id removed)
;====================================================
stock_click:
        pushad
        cmp  dword [stock_count], 0
        je   .sc_recycle
        mov  eax, [stock_count]
        dec  eax
        movzx ebx, byte [stock_data + eax]
        mov  [stock_count], eax
        mov  ecx, [waste_count]
        mov  [waste_data + ecx], bl
        inc  dword [waste_count]
        inc  dword [moves]
        popad
        ret
.sc_recycle:
        mov  ecx, [waste_count]
        cmp  ecx, 0
        je   .sc_done
        xor  edx, edx
.sc_rev:
        dec  ecx
        movzx eax, byte [waste_data + ecx]
        mov  [stock_data + edx], al
        inc  edx
        cmp  ecx, 0
        jg   .sc_rev
        movzx eax, byte [waste_data]
        mov  [stock_data + edx], al
        inc  edx
        mov  [stock_count], edx
        mov  dword [waste_count], 0
        inc  dword [moves]
.sc_done:
        popad
        ret

waste_click:
        pushad
        mov  eax, [waste_count]
        cmp  eax, 0
        je   .wc_done
        dec  eax
        movzx edx, byte [waste_data + eax]
        call try_move_to_foundation
        cmp  eax, 1
        je   .wc_moved
        mov  eax, [waste_count]
        dec  eax
        movzx edx, byte [waste_data + eax]
        call try_move_to_tableau
        cmp  eax, 1
        je   .wc_moved
        jmp  .wc_done
.wc_moved:
        dec  dword [waste_count]
        inc  dword [moves]
.wc_done:
        popad
        ret

try_auto_move:
        pushad
        mov  edi, esi
        mov  ecx, eax
        imul eax, edi, 20
        add  eax, ecx
        movzx edx, byte [tab_data + eax]
        movzx ebx, byte [tab_count + edi]
        dec  ebx
        cmp  ecx, ebx
        jne  .tam_try_tab
        push edx
        push ecx
        push edi
        call try_move_to_foundation
        pop  edi
        pop  ecx
        pop  edx
        cmp  eax, 1
        je   .tam_from_tab
.tam_try_tab:
        imul eax, edi, 20
        add  eax, ecx
        movzx edx, byte [tab_data + eax]
        push ecx
        push edi
        call try_move_stack_to_tableau
        pop  edi
        pop  ecx
        cmp  eax, 1
        je   .tam_stack_moved
        jmp  .tam_done
.tam_from_tab:
        dec  byte [tab_count + edi]
        movzx eax, byte [tab_count + edi]
        cmp  eax, 0
        je   .tam_fix_fu
        dec  eax
        movzx ebx, byte [tab_faceup + edi]
        cmp  ebx, eax
        jbe  .tam_moved
        mov  [tab_faceup + edi], al
        jmp  .tam_moved
.tam_fix_fu:
        mov  byte [tab_faceup + edi], 0
.tam_moved:
        inc  dword [moves]
        jmp  .tam_done
.tam_stack_moved:
        inc  dword [moves]
.tam_done:
        popad
        ret

try_move_to_foundation:
        push ebx
        push ecx
        push esi
        movzx eax, dl
        shr  al, 4
        mov  esi, eax
        movzx ecx, byte [found_count + esi]
        movzx ebx, dl
        and  ebx, 0x0F
        cmp  ecx, 0
        je   .tmf_ace
        dec  ecx
        imul eax, esi, 14
        movzx eax, byte [found_data + eax + ecx]
        and  eax, 0x0F
        inc  eax
        cmp  eax, ebx
        jne  .tmf_fail
        jmp  .tmf_place
.tmf_ace:
        cmp  ebx, 1
        jne  .tmf_fail
.tmf_place:
        movzx ecx, byte [found_count + esi]
        imul eax, esi, 14
        add  eax, ecx
        mov  [found_data + eax], dl
        inc  byte [found_count + esi]
        mov  eax, 1
        pop  esi
        pop  ecx
        pop  ebx
        ret
.tmf_fail:
        xor  eax, eax
        pop  esi
        pop  ecx
        pop  ebx
        ret

try_move_to_tableau:
        push ebx
        push ecx
        push esi
        push edi
        movzx ebx, dl
        and  ebx, 0x0F
        movzx ecx, dl
        shr  ecx, 4
        xor  edi, edi
        cmp  ecx, 2
        jb   .tmt_col_set
        mov  edi, 1
.tmt_col_set:
        xor  esi, esi
.tmt_loop:
        cmp  esi, NUM_TABLEAU
        jge  .tmt_fail
        movzx eax, byte [tab_count + esi]
        cmp  eax, 0
        je   .tmt_empty
        dec  eax
        push ebx
        imul ebx, esi, 20
        add  ebx, eax
        movzx eax, byte [tab_data + ebx]
        pop  ebx
        push edx
        movzx edx, al
        shr  edx, 4
        xor  ecx, ecx
        cmp  edx, 2
        jb   .tmt_top_red
        mov  ecx, 1
.tmt_top_red:
        pop  edx
        cmp  ecx, edi
        je   .tmt_next
        movzx ecx, al
        and  ecx, 0x0F
        dec  ecx
        cmp  ecx, ebx
        jne  .tmt_next
        movzx eax, byte [tab_count + esi]
        push ebx
        imul ebx, esi, 20
        add  ebx, eax
        mov  [tab_data + ebx], dl
        pop  ebx
        inc  byte [tab_count + esi]
        mov  eax, 1
        pop  edi
        pop  esi
        pop  ecx
        pop  ebx
        ret
.tmt_empty:
        cmp  ebx, 13
        jne  .tmt_next
        push ebx
        imul ebx, esi, 20
        mov  [tab_data + ebx], dl
        pop  ebx
        mov  byte [tab_count + esi], 1
        mov  byte [tab_faceup + esi], 0
        mov  eax, 1
        pop  edi
        pop  esi
        pop  ecx
        pop  ebx
        ret
.tmt_next:
        inc  esi
        jmp  .tmt_loop
.tmt_fail:
        xor  eax, eax
        pop  edi
        pop  esi
        pop  ecx
        pop  ebx
        ret

try_move_stack_to_tableau:
        pushad
        imul eax, edi, 20
        add  eax, ecx
        movzx edx, byte [tab_data + eax]
        mov  [.tms_card],    edx
        mov  [.tms_src_col], edi
        mov  [.tms_src_idx], ecx
        movzx ebx, dl
        and  ebx, 0x0F
        movzx eax, dl
        shr  al, 4
        xor  edi, edi
        cmp  al, 2
        jb   .tms_col_set
        mov  edi, 1
.tms_col_set:
        xor  esi, esi
.tms_loop:
        cmp  esi, NUM_TABLEAU
        jge  .tms_fail
        cmp  esi, [.tms_src_col]
        je   .tms_next
        movzx eax, byte [tab_count + esi]
        cmp  eax, 0
        je   .tms_empty_chk
        dec  eax
        push ebx
        imul ebx, esi, 20
        movzx eax, byte [tab_data + ebx + eax]
        pop  ebx
        push edx
        movzx edx, al
        shr  dl, 4
        xor  ecx, ecx
        cmp  edx, 2
        jb   .tms_top_red
        mov  ecx, 1
.tms_top_red:
        pop  edx
        cmp  ecx, edi
        je   .tms_next
        movzx ecx, al
        and  ecx, 0x0F
        dec  ecx
        cmp  ecx, ebx
        jne  .tms_next
        jmp  .tms_do_move
.tms_empty_chk:
        cmp  ebx, 13
        jne  .tms_next
.tms_do_move:
        mov  ecx, [.tms_src_idx]
        mov  edi, [.tms_src_col]
.tms_copy:
        movzx eax, byte [tab_count + edi]
        cmp  ecx, eax
        jge  .tms_copy_done
        imul eax, edi, 20
        add  eax, ecx
        movzx edx, byte [tab_data + eax]
        movzx eax, byte [tab_count + esi]
        push ebx
        imul ebx, esi, 20
        add  ebx, eax
        mov  [tab_data + ebx], dl
        pop  ebx
        inc  byte [tab_count + esi]
        inc  ecx
        jmp  .tms_copy
.tms_copy_done:
        mov  ecx, [.tms_src_idx]
        mov  [tab_count + edi], cl
        cmp  cl, 0
        je   .tms_fix_fu
        dec  cl
        movzx eax, byte [tab_faceup + edi]
        cmp  eax, ecx
        jbe  .tms_done
        mov  [tab_faceup + edi], cl
        jmp  .tms_done
.tms_fix_fu:
        mov  byte [tab_faceup + edi], 0
.tms_done:
        popad
        mov  eax, 1
        ret
.tms_next:
        inc  esi
        jmp  .tms_loop
.tms_fail:
        popad
        xor  eax, eax
        ret
.tms_card:    dd 0
.tms_src_col: dd 0
.tms_src_idx: dd 0

check_win:
        pushad
        xor  esi, esi
        xor  eax, eax
.cw_l:
        cmp  esi, NUM_FOUNDATIONS
        jge  .cw_chk
        movzx ebx, byte [found_count + esi]
        add  eax, ebx
        inc  esi
        jmp  .cw_l
.cw_chk:
        cmp  eax, NUM_CARDS
        jne  .cw_no
        cmp  byte [game_won], 1
        je   .cw_no
        mov  byte [game_won], 1
        ; Bump persistent wins, save, win SFX
        mov  eax, [total_wins]
        inc  eax
        mov  [total_wins], eax
        mov  ebx, [total_wins]
        mov  esi, hs_name_st
        call hs_save
        call audio_sfx_win
.cw_no:
        popad
        ret

rng_next:
        push edx
        mov  eax, [rng_state]
        imul eax, 1103515245
        add  eax, 12345
        mov  [rng_state], eax
        shr  eax, 16
        pop  edx
        ret

;====================================================
; DATA
;====================================================
str_title:  db "SOLITAIRE", 0
str_status: db "CLICK CARDS  R=NEW GAME  Q=QUIT", 0
str_win:    db "YOU WIN!", 0

rank_chars_s: db 'A23456789TJQK'
suit_chars_s: db 'HDCS'

rng_state:    dd 0
game_won:     db 0
selected_pile: dd -1
selected_idx:  dd -1
moves:         dd 0

deck:         times NUM_CARDS db 0
stock_data:   times 24 db 0
stock_count:  dd 0
waste_data:   times 24 db 0
waste_count:  dd 0
tab_data:     times (NUM_TABLEAU * 20) db 0
tab_count:    times NUM_TABLEAU db 0
tab_faceup:   times NUM_TABLEAU db 0
found_data:   times (NUM_FOUNDATIONS * 14) db 0
found_count:  times NUM_FOUNDATIONS db 0
hs_name_st:   db "solitaire", 0
hs_loaded:    db 0
total_wins:   dd 0
