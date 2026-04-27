;=======================================================================
; OUTBREAK SHIELD - VBE Graphics Edition
; A Vaccination Simulation Game for Mellivora OS
; Inspired by The Oregon Trail and dedicated to Robin
;
; Lead Dr. Pryor through 12 months of Ratel Fever. Manage vaccines,
; treat the sick, run supplies, and research infrastructure.
;
; Controls: 1-6 for actions, Mouse for buttons, ESC to quit
;=======================================================================

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

;=======================================================================
; Game constants
;=======================================================================
COMMUNITY_SIZE  equ 200
MAX_MONTHS      equ 12
MAX_VACCINES    equ 999
MAX_SUPPLIES    equ 999
MAX_MORALE      equ 100
MAX_PREPAREDNESS equ 100
MAX_THREAT      equ 5

OUTBREAK_BASE   equ 8
VACCINE_EFFECT  equ 3

; Sound frequencies
SND_GOOD        equ 1200
SND_BAD         equ 200
SND_ALARM       equ 400
SND_VICTORY     equ 1600
SND_DEATH       equ 100
SND_VACCINE     equ 1000

; Decay rates per month by difficulty
DECAY_VAX_EASY  equ 1
DECAY_VAX_NORM  equ 3
DECAY_VAX_HARD  equ 5
DECAY_SUP_EASY  equ 1
DECAY_SUP_NORM  equ 3
DECAY_SUP_HARD  equ 5
DECAY_MOR_EASY  equ 0
DECAY_MOR_NORM  equ 2
DECAY_MOR_HARD  equ 4

DEF_VACCINES    equ 35
DEF_SUPPLIES    equ 30
DEF_MORALE      equ 60
DEF_MONTHS      equ 12
DEF_DIFF        equ 1

;=======================================================================
; Layout constants (1024x768)
;=======================================================================
SCR_W           equ 1024
SCR_H           equ 768

; Colour palette
COL_BG          equ 0x00060A0E   ; near-black deep navy
COL_BG2         equ 0x000D1820   ; panel background
COL_TOPBAR      equ 0x00102030   ; header bar
COL_GOLD        equ 0x00FFD700
COL_WHITE       equ 0x00FFFFFF
COL_RED         equ 0x00FF3333
COL_RED_DIM     equ 0x00991111
COL_GREEN       equ 0x0033DD44
COL_GREEN_DIM   equ 0x00116622
COL_CYAN        equ 0x0044CCEE
COL_YELLOW      equ 0x00FFEE44
COL_ORANGE      equ 0x00FF8822
COL_GRAY        equ 0x00AAAAAA
COL_DARKGRAY    equ 0x00444444
COL_PANEL_BORDER equ 0x00224466
COL_HEALTHY     equ 0x0033EE44
COL_VACCINATED  equ 0x004499FF
COL_INFECTED    equ 0x00FF4422
COL_RECOVERED   equ 0x0088AAFF
COL_DEAD        equ 0x00666666
COL_MORALE_HI   equ 0x00FFEE44
COL_MORALE_LO   equ 0x00FF4422
COL_THREAT_1    equ 0x0033EE44
COL_THREAT_2    equ 0x00AAEE22
COL_THREAT_3    equ 0x00FFEE22
COL_THREAT_4    equ 0x00FF8822
COL_THREAT_5    equ 0x00FF3333

; Main screen panels
HEADER_H        equ 52
SIDE_X          equ 720
SIDE_W          equ 304
POP_PANEL_Y     equ HEADER_H + 8
POP_PANEL_H     equ 200
STAT_PANEL_Y    equ POP_PANEL_Y + POP_PANEL_H + 8
STAT_PANEL_H    equ 240
THREAT_PANEL_Y  equ STAT_PANEL_Y + STAT_PANEL_H + 8
THREAT_PANEL_H  equ 100
MAIN_X          equ 8
MAIN_Y          equ HEADER_H + 8
MAIN_W          equ SIDE_X - 16
MAIN_H          equ SCR_H - HEADER_H - 8 - 8
BTN_AREA_Y      equ 560
BTN_H           equ 42
BTN_W           equ 162
BTN_GAP         equ 8
BTN_ROW1_Y      equ BTN_AREA_Y
BTN_ROW2_Y      equ BTN_AREA_Y + BTN_H + BTN_GAP
BTN1_X          equ MAIN_X
BTN2_X          equ MAIN_X + BTN_W + BTN_GAP
BTN3_X          equ MAIN_X + (BTN_W + BTN_GAP) * 2
LOG_Y           equ MAIN_Y + 8
LOG_H           equ 500

; Button colours
COL_BTN_1       equ 0x00124A12   ; vaccinate green
COL_BTN_2       equ 0x004A1212   ; treat red
COL_BTN_3       equ 0x004A3A10   ; supply yellow
COL_BTN_4       equ 0x00103A4A   ; research cyan
COL_BTN_5       equ 0x00381048   ; awareness purple
COL_BTN_6       equ 0x00304030   ; rest dark-green
COL_BTN_HOVER   equ 0x00335577
COL_BTN_BORDER  equ 0x00446688
COL_BTN_END     equ 0x004A2000   ; end month orange
COL_HEADER      equ 0x00102030
COL_BORDER      equ 0x00224466
COL_DIM         equ 0x00222222

LOG_LINES       equ 30
BTN_COL1        equ MAIN_X
BTN_COL2        equ MAIN_X + BTN_W + BTN_GAP
BTN_COL3        equ MAIN_X + (BTN_W + BTN_GAP) * 2

DECAY_VAX_NRM   equ 3
DECAY_SUP_NRM   equ 3
DECAY_MOR_NRM   equ 2

;=======================================================================
; Animation / particle state
;=======================================================================
NUM_PARTICLES   equ 20

;=======================================================================
; start
;=======================================================================
start:
        VBE_GAME_INIT

        ; Seed PRNG from system time
        mov eax, SYS_GETTIME
        int 0x80
        mov [rand_seed], eax

        ; Init settings
        mov dword [set_vaccines], DEF_VACCINES
        mov dword [set_supplies], DEF_SUPPLIES
        mov dword [set_morale], DEF_MORALE
        mov dword [set_months], DEF_MONTHS
        mov dword [set_diff], DEF_DIFF

        ; Init particles to offscreen
        mov ecx, NUM_PARTICLES
        mov edi, particle_x
.init_p:
        mov dword [edi], -1
        add edi, 4
        loop .init_p

        call title_screen

;=======================================================================
; TITLE SCREEN
;=======================================================================
title_screen:
        call play_title_melody

        call draw_title_screen
        mov byte [title_anim_frame], 0

.title_loop:
        call render_title_anim
        VBE_GAME_PRESENT

        VBE_GAME_POLL_KEY
        cmp eax, -1
        je  .title_mouse

        cmp eax, '1'
        je  .title_play
        cmp eax, '2'
        je  .title_howto
        cmp eax, '3'
        je  .title_settings
        cmp eax, '4'
        je  exit_game
        cmp eax, KEY_ESC
        je  exit_game
        cmp eax, 'q'
        je  exit_game
        cmp eax, 'Q'
        je  exit_game
        jmp .title_loop

.title_mouse:
        mov eax, SYS_MOUSE
        int 0x80
        test ecx, 1
        jz  .title_loop
        call wait_up
        ; Check buttons: y=530..572
        ; btn1=[150,250], btn2=[350,450], btn3=[550,650], btn4=[750,820]
        cmp ebx, 530
        jl  .title_loop
        cmp ebx, 574
        jg  .title_loop
        cmp eax, 150
        jl  .title_loop
        cmp eax, 874
        jg  .title_loop
        ; which button?
        cmp eax, 320
        jl  .title_play
        cmp eax, 490
        jl  .title_howto
        cmp eax, 660
        jl  .title_settings
        ; else exit
        jmp exit_game

.title_play:
        jmp new_game
.title_howto:
        call show_howto
        jmp title_screen
.title_settings:
        call show_settings
        jmp title_screen

;=======================================================================
; draw_title_screen - static layout for title
;=======================================================================
draw_title_screen:
        pushad
        ; BG gradient-ish: dark top to darker bottom
        mov  edx, COL_BG
        call vbe_clear_screen

        ; === Animated bio-hazard circle (static version here) ===
        ; Large outer ring
        mov  ebx, 512
        mov  ecx, 240
        mov  edx, 190
        mov  esi, 0x00661100
        call vbe_draw_circle
        mov  edx, 188
        call vbe_draw_circle
        ; Biohazard spokes (3 circles offset)
        mov  ebx, 512
        mov  ecx, 140
        mov  edx, 55
        mov  esi, 0x00991100
        call vbe_fill_circle
        mov  ebx, 430
        mov  ecx, 290
        call vbe_fill_circle
        mov  ebx, 594
        mov  ecx, 290
        call vbe_fill_circle
        ; centre
        mov  ebx, 512
        mov  ecx, 240
        mov  edx, 50
        mov  esi, COL_BG
        call vbe_fill_circle
        mov  edx, 20
        mov  esi, 0x00BB1100
        call vbe_fill_circle

        ; === OUTBREAK SHIELD title ===
        mov  ebx, 200
        mov  ecx, 56
        mov  edx, str_title_l1
        mov  esi, 0x00FF3311
        mov  eax, 5
        call vbe_draw_str

        mov  ebx, 210
        mov  ecx, 116
        mov  edx, str_title_l2
        mov  esi, COL_WHITE
        mov  eax, 3
        call vbe_draw_str

        ; Tagline
        mov  ebx, 270
        mov  ecx, 165
        mov  edx, str_subtitle
        mov  esi, COL_CYAN
        mov  eax, 1
        call vbe_draw_str

        ; Horizontal rule
        mov  ebx, 100
        mov  ecx, 195
        mov  edx, 824
        mov  esi, COL_PANEL_BORDER
        call vbe_draw_hline

        ; Story box
        mov  ebx, 100
        mov  ecx, 210
        mov  edx, 824
        mov  esi, 160
        mov  edi, COL_BG2
        call vbe_fill_rect

        mov  ebx, 116
        mov  ecx, 222
        mov  edx, str_story1
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str
        mov  ecx, 236
        mov  edx, str_story2
        call vbe_draw_str
        mov  ecx, 250
        mov  edx, str_story3
        call vbe_draw_str

        ; Menu buttons row
        ; [1] Play  [2] How to Play  [3] Settings  [4] Quit
        mov  ebx, 150
        mov  ecx, 530
        mov  edx, 160
        mov  esi, 44
        mov  edi, COL_BTN_1
        call vbe_fill_rect
        mov  ebx, 160
        mov  ecx, 546
        mov  edx, str_mbtn_play
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        mov  ebx, 350
        mov  ecx, 530
        mov  edx, 160
        mov  esi, 44
        mov  edi, COL_BTN_4
        call vbe_fill_rect
        mov  ebx, 360
        mov  ecx, 546
        mov  edx, str_mbtn_howto
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        mov  ebx, 550
        mov  ecx, 530
        mov  edx, 160
        mov  esi, 44
        mov  edi, COL_BTN_6
        call vbe_fill_rect
        mov  ebx, 555
        mov  ecx, 546
        mov  edx, str_mbtn_settings
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        mov  ebx, 750
        mov  ecx, 530
        mov  edx, 120
        mov  esi, 44
        mov  edi, COL_RED_DIM
        call vbe_fill_rect
        mov  ebx, 767
        mov  ecx, 546
        mov  edx, str_mbtn_quit
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        ; Footer
        mov  ebx, 280
        mov  ecx, 720
        mov  edx, str_footer
        mov  esi, COL_DARKGRAY
        mov  eax, 1
        call vbe_draw_str

        popad
        ret

;=======================================================================
; render_title_anim - Spin a ring of dots around the biohazard
;=======================================================================
render_title_anim:
        pushad

        ; Re-draw static parts only once (using title_anim counter)
        ; Erase previous dot ring
        mov  eax, [title_anim_frame]
        cmp  eax, 0
        jne  .rta_erase

        ; First frame: draw static background
        call draw_title_screen
        jmp  .rta_draw

.rta_erase:
        ; Erase old dot (draw BG colour over it)
        mov  eax, [title_anim_frame]
        dec  eax
        and  eax, 31            ; 32-step rotation

        ; Compute angle: approx sin/cos via table
        ; Use simple parametric: x = cx + r*cos, y = cy + r*sin
        ; We approximate with precomputed offsets in a lookup table
        mov  ebx, eax
        imul ebx, 8             ; 8 bytes per entry (dx, dy)
        movsx ecx, word [dot_offsets + ebx]
        movsx edx, word [dot_offsets + ebx + 2]
        add  ecx, 512           ; cx
        add  edx, 240           ; cy
        ; draw small filled circle to erase
        mov  ebx, ecx
        mov  ecx, edx
        mov  edx, 5
        mov  esi, COL_BG
        call vbe_fill_circle

.rta_draw:
        ; Draw new dot
        mov  eax, [title_anim_frame]
        and  eax, 31
        mov  ebx, eax
        imul ebx, 8
        movsx ecx, word [dot_offsets + ebx]
        movsx edx, word [dot_offsets + ebx + 2]
        add  ecx, 512
        add  edx, 240
        mov  ebx, ecx
        mov  ecx, edx
        mov  edx, 5
        mov  esi, COL_YELLOW
        call vbe_fill_circle

        ; Advance frame
        inc  dword [title_anim_frame]

        popad
        ret

;=======================================================================
; HOW TO PLAY
;=======================================================================
show_howto:
        pushad
        call ob_clear
        call draw_panel_title
        mov  ebx, 30
        mov  ecx, MAIN_Y + 16
        mov  edx, str_howto_title
        mov  esi, COL_GOLD
        mov  eax, 2
        call vbe_draw_str

        ; Draw text lines (null-terminated table)
        mov  edi, howto_lines
        mov  ebx, 30
        mov  edx, MAIN_Y + 50
.ht_line:
        mov  eax, [edi]
        cmp  eax, 0
        je   .ht_done
        push edx
        push edi
        mov  ecx, edx
        mov  edx, eax
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str
        pop  edi
        pop  edx
        add  edx, 16
        add  edi, 4
        jmp  .ht_line
.ht_done:

        ; "Press any key" button
        mov  ebx, 350
        mov  ecx, 720
        mov  edx, 280
        mov  esi, 36
        mov  edi, COL_BTN_4
        call vbe_fill_rect
        mov  ebx, 360
        mov  ecx, 730
        mov  edx, str_press_any
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT
.howto_wait:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je  .howto_mouse
        popad
        ret
.howto_mouse:
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz  .howto_wait
        call wait_up
        popad
        ret

;=======================================================================
; SETTINGS (simplified — just preset selection)
;=======================================================================
show_settings:
        pushad
        call ob_clear
        call draw_panel_title
        mov  ebx, 30
        mov  ecx, MAIN_Y + 16
        mov  edx, str_settings_title
        mov  esi, COL_GOLD
        mov  eax, 2
        call vbe_draw_str

        ; Preset buttons
        mov  ebx, 30
        mov  ecx, MAIN_Y + 80
        mov  edx, 320
        mov  esi, 50
        mov  edi, COL_BTN_1
        call vbe_fill_rect
        mov  ebx, 42
        mov  ecx, MAIN_Y + 100
        mov  edx, str_preset_easy
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        mov  ecx, MAIN_Y + 145
        mov  edx, 320
        mov  esi, 50
        mov  edi, COL_BTN_3
        call vbe_fill_rect
        mov  ebx, 42
        mov  ecx, MAIN_Y + 165
        mov  edx, str_preset_normal
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        mov  ebx, 30
        mov  ecx, MAIN_Y + 210
        mov  edx, 320
        mov  esi, 50
        mov  edi, COL_BTN_2
        call vbe_fill_rect
        mov  ebx, 42
        mov  ecx, MAIN_Y + 230
        mov  edx, str_preset_hard
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        ; Current diff shown
        mov  ebx, 30
        mov  ecx, MAIN_Y + 300
        mov  edx, str_set_diff
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 120
        mov  ecx, MAIN_Y + 300
        mov  eax, [set_diff]
        imul eax, 4
        add  eax, diff_names
        mov  edx, [eax]
        mov  esi, COL_YELLOW
        mov  eax, 1
        call vbe_draw_str

        mov  ebx, 30
        mov  ecx, MAIN_Y + 320
        mov  edx, str_set_vaccines
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 200
        mov  ecx, MAIN_Y + 320
        mov  edx, [set_vaccines]
        mov  esi, COL_CYAN
        mov  eax, 1
        call vbe_draw_num

        ; Press 1/2/3 to choose preset, ESC to return
        mov  ebx, 30
        mov  ecx, MAIN_Y + 370
        mov  edx, str_set_footer
        mov  esi, COL_DARKGRAY
        mov  eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT

.sett_wait:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je  .sett_mouse
        cmp  eax, KEY_ESC
        je  .sett_done
        cmp  eax, '1'
        je  .sett_easy
        cmp  eax, '2'
        je  .sett_normal
        cmp  eax, '3'
        je  .sett_hard
        jmp .sett_wait

.sett_mouse:
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz  .sett_wait
        call wait_up
        ; Easy: y=MAIN_Y+80..130, Normal: +145..195, Hard: +210..260
        cmp  ebx, MAIN_Y + 80
        jl  .sett_wait
        cmp  ebx, MAIN_Y + 260
        jg  .sett_done
        cmp  ebx, MAIN_Y + 130
        jle .sett_easy
        cmp  ebx, MAIN_Y + 195
        jle .sett_normal
        jmp .sett_hard

.sett_easy:
        mov  dword [set_vaccines], 60
        mov  dword [set_supplies], 50
        mov  dword [set_morale],   80
        mov  dword [set_diff],     0
        jmp  .sett_done
.sett_normal:
        mov  dword [set_vaccines], DEF_VACCINES
        mov  dword [set_supplies], DEF_SUPPLIES
        mov  dword [set_morale],   DEF_MORALE
        mov  dword [set_diff],     1
        jmp  .sett_done
.sett_hard:
        mov  dword [set_vaccines], 15
        mov  dword [set_supplies], 15
        mov  dword [set_morale],   40
        mov  dword [set_diff],     2
.sett_done:
        popad
        ret

;=======================================================================
; new_game - Initialise all game state
;=======================================================================
new_game:
        ; Startup sound
        mov  eax, SYS_BEEP
        mov  ebx, SND_GOOD
        mov  ecx, 3
        int  0x80

        mov  dword [month], 1
        mov  dword [population], COMMUNITY_SIZE
        mov  dword [healthy], COMMUNITY_SIZE
        mov  dword [vaccinated], 0
        mov  dword [infected], 0
        mov  dword [recovered], 0
        mov  dword [dead], 0
        mov  eax, [set_vaccines]
        mov  [vaccines], eax
        mov  eax, [set_supplies]
        mov  [supplies], eax
        mov  eax, [set_morale]
        mov  [morale], eax
        mov  dword [research], 0
        mov  dword [actions_left], 2
        mov  dword [total_vaccinated], 0
        mov  dword [total_treated], 0
        mov  dword [outbreaks_survived], 0
        mov  byte  [hospital_built], 0
        mov  byte  [lab_built], 0
        mov  dword [difficulty], 0
        mov  dword [threat_level], 1
        ; preparedness from morale+supplies
        mov  eax, [set_morale]
        shr  eax, 1
        add  eax, 15
        mov  ebx, [set_supplies]
        shr  ebx, 1
        add  eax, ebx
        cmp  eax, MAX_PREPAREDNESS
        jle  .prep_ok
        mov  eax, MAX_PREPAREDNESS
.prep_ok:
        mov  [preparedness], eax
        mov  dword [event_type], 0
        ; Clear log lines
        mov  ecx, LOG_LINES
        mov  edi, log_line_buf
        xor  eax, eax
.clog:  mov  dword [edi], 0
        add  edi, 4
        loop .clog
        mov  dword [log_head], 0
        ; Clear message
        mov  byte [msg_buf], 0
        mov  dword [msg_colour], COL_WHITE

        ; Fall through to game_month

;=======================================================================
; GAME MONTH - main loop
;=======================================================================
game_month:
        ; Check time up
        mov  eax, [set_months]
        inc  eax
        cmp  [month], eax
        jge  .check_final

        cmp  dword [population], 0
        jle  game_over

        ; Collapse: 50%+ dead
        mov  eax, [dead]
        shl  eax, 1
        cmp  eax, COMMUNITY_SIZE
        jge  game_collapse

        jmp  .month_go

.check_final:
        mov  eax, [population]
        cmp  eax, 0
        jle  game_over
        ; Need > 25% alive
        imul eax, 100
        xor  edx, edx
        mov  ecx, COMMUNITY_SIZE
        div  ecx
        cmp  eax, 25
        jle  game_over
        ; Need < 10% infected
        mov  eax, [infected]
        imul eax, 100
        xor  edx, edx
        mov  ecx, [population]
        div  ecx
        cmp  eax, 10
        jge  game_failed
        jmp  game_win

.month_go:
        mov  dword [actions_left], 2
        call calc_difficulty
        call monthly_decay
        call draw_game_screen

;=======================================================================
; action_loop
;=======================================================================
action_loop:
        cmp  dword [actions_left], 0
        jle  month_end

        call draw_action_btns

.al_wait:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je  .al_mouse

        cmp  eax, KEY_ESC
        je  confirm_quit
        cmp  eax, 'q'
        je  confirm_quit
        cmp  eax, 'Q'
        je  confirm_quit
        cmp  eax, '1'
        je  action_vaccinate
        cmp  eax, '2'
        je  action_treat
        cmp  eax, '3'
        je  action_supply_run
        cmp  eax, '4'
        je  action_research
        cmp  eax, '5'
        je  action_awareness
        cmp  eax, '6'
        je  action_rest
        jmp .al_wait

.al_mouse:
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz  .al_wait
        ; save mouse coords
        mov  [tmp_mx], eax
        mov  [tmp_my], ebx
        call wait_up
        ; Check button regions
        ; Row 1: y=BTN_ROW1_Y..BTN_ROW1_Y+BTN_H
        ; Row 2: y=BTN_ROW2_Y..BTN_ROW2_Y+BTN_H
        ; BTN1_X, BTN2_X, BTN3_X (each BTN_W wide)
        mov  ebx, [tmp_my]
        cmp  ebx, BTN_ROW1_Y
        jl  .al_wait
        cmp  ebx, BTN_ROW2_Y + BTN_H
        jg  .al_wait
        mov  eax, [tmp_mx]
        cmp  eax, BTN1_X
        jl  .al_wait
        ; Which column?
        cmp  eax, BTN1_X + BTN_W
        jg  .al_col2
        ; col1: buttons 1 or 4
        cmp  ebx, BTN_ROW2_Y
        jge  action_research
        jmp  action_vaccinate
.al_col2:
        cmp  eax, BTN2_X
        jl  .al_wait
        cmp  eax, BTN2_X + BTN_W
        jg  .al_col3
        cmp  ebx, BTN_ROW2_Y
        jge  action_awareness
        jmp  action_treat
.al_col3:
        cmp  eax, BTN3_X
        jl  .al_wait
        cmp  eax, BTN3_X + BTN_W
        jg  .al_right_panel
        cmp  ebx, BTN_ROW2_Y
        jge  action_rest
        jmp  action_supply_run

.al_right_panel:
        ; Check END MONTH button (x=724..1014, y=660..700)
        cmp  eax, 724
        jl  .al_wait
        cmp  ebx, 660
        jl  .al_wait
        cmp  ebx, 700
        jg  .al_quit_btn
        jmp  month_end

.al_quit_btn:
        ; Check QUIT button (x=724..1014, y=712..752)
        cmp  ebx, 712
        jl  .al_wait
        cmp  ebx, 752
        jg  .al_wait
        jmp  confirm_quit

;=======================================================================
; ACTION 1: Vaccination Drive
;=======================================================================
action_vaccinate:
        cmp  dword [vaccines], 0
        jle  .no_vax

        ; Capacity by difficulty
        mov  eax, [set_diff]
        cmp  eax, 0
        je   .vax_easy
        cmp  eax, 2
        je   .vax_hard
        mov  eax, 8
        jmp  .vax_set
.vax_easy:  mov eax, 12
        jmp .vax_set
.vax_hard:  mov eax, 5
.vax_set:
        cmp  byte [lab_built], 1
        jne  .vax_lb
        add  eax, 3
.vax_lb:
        cmp  byte [hospital_built], 1
        jne  .vax_hb
        add  eax, 2
.vax_hb:
        cmp  eax, 18
        jle  .vax_cap_ok
        mov  eax, 18
.vax_cap_ok:
        mov  ebx, [vaccines]
        cmp  eax, ebx
        jle  .vax_stk
        mov  eax, ebx
.vax_stk:
        mov  ebx, [healthy]
        cmp  eax, ebx
        jle  .vax_ok
        mov  eax, ebx
.vax_ok:
        cmp  eax, 0
        jle  .vax_no_targets

        mov  [temp_val], eax
        sub  [vaccines], eax
        sub  [healthy], eax
        add  [vaccinated], eax
        add  [total_vaccinated], eax
        add  dword [morale], 2
        add  dword [preparedness], 2
        cmp  byte [lab_built], 1
        jne  .vax_done_prep
        add  dword [preparedness], 1
.vax_done_prep:
        call clamp_morale
        call clamp_preparedness

        ; Syringe particle burst
        call spawn_vaccine_particles

        ; Sound
        mov  eax, SYS_BEEP
        mov  ebx, SND_VACCINE
        mov  ecx, 3
        int  0x80
        mov  eax, SYS_BEEP
        mov  ebx, 1200
        mov  ecx, 2
        int  0x80

        ; Log message
        mov  ebx, str_vax_success
        mov  ecx, COL_GREEN
        call log_msg_str
        mov  eax, [temp_val]
        mov  ecx, COL_WHITE
        call log_msg_num

        dec  dword [actions_left]
        call draw_game_screen
        jmp  action_loop

.no_vax:
        mov  ebx, str_no_vaccines
        mov  ecx, COL_RED
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_BAD
        mov  ecx, 3
        int  0x80
        call draw_game_screen
        jmp  action_loop

.vax_no_targets:
        cmp  dword [infected], 0
        jg   .vax_nt_sick
        mov  ebx, str_all_vaxxed
        mov  ecx, COL_GREEN
        call log_msg_str
        call draw_game_screen
        jmp  action_loop
.vax_nt_sick:
        mov  ebx, str_no_healthy
        mov  ecx, COL_YELLOW
        call log_msg_str
        call draw_game_screen
        jmp  action_loop

;=======================================================================
; ACTION 2: Treat the Sick
;=======================================================================
action_treat:
        cmp  dword [infected], 0
        jle  .no_sick
        cmp  dword [supplies], 0
        jle  .no_supplies

        mov  eax, [set_diff]
        cmp  eax, 0
        je   .tr_easy
        cmp  eax, 2
        je   .tr_hard
        mov  eax, 7
        jmp  .tr_set
.tr_easy:  mov eax, 10
        jmp .tr_set
.tr_hard:  mov eax, 4
.tr_set:
        cmp  byte [hospital_built], 1
        jne  .tr_hb
        add  eax, 3
.tr_hb:
        cmp  byte [lab_built], 1
        jne  .tr_lb
        add  eax, 2
.tr_lb:
        cmp  dword [morale], 35
        jge  .tr_cap
        sub  eax, 2
.tr_cap:
        cmp  eax, 3
        jge  .tr_cap_ok
        mov  eax, 3
.tr_cap_ok:
        mov  ebx, [supplies]
        cmp  eax, ebx
        jle  .tr_stk
        mov  eax, ebx
.tr_stk:
        mov  ebx, [infected]
        cmp  eax, ebx
        jle  .tr_ok
        mov  eax, ebx
.tr_ok:
        mov  [temp_val], eax
        sub  [supplies], eax
        sub  [infected], eax
        add  [recovered], eax
        add  [total_treated], eax

        ; Hospital bonus
        cmp  byte [hospital_built], 1
        jne  .tr_no_bonus
        mov  eax, [infected]
        mov  ecx, [set_diff]
        cmp  ecx, 2
        jne  .tr_bonus_norm
        cmp  eax, 1
        jle  .tr_hcap
        mov  eax, 1
        jmp  .tr_hcap
.tr_bonus_norm:
        cmp  eax, 2
        jle  .tr_hcap
        mov  eax, 2
.tr_hcap:
        sub  [infected], eax
        add  [recovered], eax
        add  [total_treated], eax
        add  [temp_val], eax
.tr_no_bonus:

        add  dword [morale], 1
        add  dword [preparedness], 2
        call clamp_morale
        call clamp_preparedness

        ; Red cross particles
        call spawn_treat_particles

        mov  eax, SYS_BEEP
        mov  ebx, SND_GOOD
        mov  ecx, 2
        int  0x80

        mov  ebx, str_treated
        mov  ecx, COL_CYAN
        call log_msg_str
        mov  eax, [temp_val]
        mov  ecx, COL_WHITE
        call log_msg_num

        dec  dword [actions_left]
        call draw_game_screen
        jmp  action_loop

.no_sick:
        mov  ebx, str_no_sick
        mov  ecx, COL_GREEN
        call log_msg_str
        call draw_game_screen
        jmp  action_loop
.no_supplies:
        mov  ebx, str_no_supplies
        mov  ecx, COL_RED
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_BAD
        mov  ecx, 3
        int  0x80
        call draw_game_screen
        jmp  action_loop

;=======================================================================
; ACTION 3: Supply Run
;=======================================================================
action_supply_run:
        call random
        xor  edx, edx
        mov  ebx, 8
        div  ebx
        add  edx, 3
        mov  eax, [threat_level]
        add  edx, eax
        mov  eax, [preparedness]
        shr  eax, 4
        add  edx, eax
        mov  [temp_val], edx
        add  [vaccines], edx

        call random
        xor  edx, edx
        mov  ebx, 6
        div  ebx
        add  edx, 2
        mov  eax, [threat_level]
        add  edx, eax
        mov  [temp_val2], edx
        add  [supplies], edx

        cmp  dword [vaccines], MAX_VACCINES
        jle  .sv_vc
        mov  dword [vaccines], MAX_VACCINES
.sv_vc:
        cmp  dword [supplies], MAX_SUPPLIES
        jle  .sv_sc
        mov  dword [supplies], MAX_SUPPLIES
.sv_sc:

        ; Risk check
        call random
        xor  edx, edx
        mov  ebx, 100
        div  ebx
        mov  eax, 22
        mov  ecx, [threat_level]
        imul ecx, 8
        add  eax, ecx
        cmp  dword [preparedness], 70
        jl   .sv_risk_ready
        sub  eax, 8
.sv_risk_ready:
        cmp  edx, eax
        jge  .sv_safe

        ; Risk: 3 workers infected
        cmp  dword [healthy], 3
        jl   .sv_safe
        sub  dword [healthy], 3
        add  dword [infected], 3
        sub  dword [morale], 5
        sub  dword [preparedness], 6
        call clamp_morale
        call clamp_preparedness

        mov  ebx, str_supply_risk
        mov  ecx, COL_YELLOW
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_ALARM
        mov  ecx, 4
        int  0x80
        dec  dword [actions_left]
        call draw_game_screen
        jmp  action_loop

.sv_safe:
        add  dword [preparedness], 2
        call clamp_preparedness
        mov  ebx, str_supply_ok
        mov  ecx, COL_GREEN
        call log_msg_str
        mov  eax, [temp_val]
        mov  ecx, COL_WHITE
        call log_msg_num
        mov  ebx, str_vax_and
        mov  ecx, COL_GRAY
        call log_msg_str
        mov  eax, [temp_val2]
        mov  ecx, COL_WHITE
        call log_msg_num
        mov  ebx, str_med_supplies
        mov  ecx, COL_GRAY
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_GOOD
        mov  ecx, 2
        int  0x80
        dec  dword [actions_left]
        call draw_game_screen
        jmp  action_loop

;=======================================================================
; ACTION 4: Research
;=======================================================================
action_research:
        call random
        xor  edx, edx
        mov  ebx, 10
        div  ebx
        add  edx, 3
        cmp  byte [lab_built], 1
        jne  .ar_no_lab
        add  edx, 3
.ar_no_lab:
        add  [research], edx
        mov  [temp_val], edx
        add  dword [preparedness], 3
        cmp  byte [lab_built], 1
        jne  .ar_prep_done
        add  dword [preparedness], 2
.ar_prep_done:
        call clamp_preparedness

        ; Build hospital at research >= 30
        cmp  byte [hospital_built], 0
        je   .ar_check_hosp
        jmp  .ar_check_lab
.ar_check_hosp:
        cmp  dword [research], 30
        jl   .ar_check_lab
        mov  byte [hospital_built], 1
        mov  ebx, str_hospital_built
        mov  ecx, COL_GOLD
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_VICTORY
        mov  ecx, 5
        int  0x80
        jmp  .ar_done

.ar_check_lab:
        cmp  byte [lab_built], 0
        je   .ar_check_lab2
        jmp  .ar_done
.ar_check_lab2:
        cmp  dword [research], 70
        jl   .ar_done
        mov  byte [lab_built], 1
        mov  ebx, str_lab_built
        mov  ecx, COL_GOLD
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_VICTORY
        mov  ecx, 5
        int  0x80

.ar_done:
        mov  ebx, str_research_pts
        mov  ecx, COL_CYAN
        call log_msg_str
        mov  eax, [temp_val]
        mov  ecx, COL_WHITE
        call log_msg_num

        mov  eax, SYS_BEEP
        mov  ebx, 800
        mov  ecx, 2
        int  0x80
        dec  dword [actions_left]
        call draw_game_screen
        jmp  action_loop
;=======================================================================
; ACTION 5: Awareness
;=======================================================================
action_awareness:
        add  dword [morale], 4
        add  dword [preparedness], 3
        call clamp_morale
        call clamp_preparedness

        call random
        xor  edx, edx
        mov  ebx, 100
        div  ebx
        cmp  edx, 30
        jge  .aw_morale_only

        mov  eax, 2
        add  eax, [threat_level]
        cmp  byte [lab_built], 1
        jne  .aw_size_ok
        add  eax, 2
.aw_size_ok:
        mov  [temp_val], eax
        mov  ecx, [healthy]
        cmp  ecx, eax
        jl  .aw_morale_only
        mov  ecx, [vaccines]
        cmp  ecx, eax
        jl  .aw_morale_only

        sub  [healthy], eax
        add  [vaccinated], eax
        sub  [vaccines], eax
        add  [total_vaccinated], eax
        mov  ebx, str_awareness_vax
        mov  ecx, COL_GREEN
        call log_msg_str
        mov  eax, [temp_val]
        mov  ecx, COL_WHITE
        call log_msg_num
        jmp  .aw_done
.aw_morale_only:
        mov  ebx, str_awareness_ok
        mov  ecx, COL_CYAN
        call log_msg_str
.aw_done:
        mov  eax, SYS_BEEP
        mov  ebx, SND_GOOD
        mov  ecx, 2
        int  0x80
        dec  dword [actions_left]
        call draw_game_screen
        jmp  action_loop

;=======================================================================
; ACTION 6: Rest
;=======================================================================
action_rest:
        add  dword [morale], 2
        add  dword [preparedness], 2
        cmp  dword [supplies], 95
        jge  .rest_ok
        add  dword [supplies], 1
.rest_ok:
        call clamp_morale
        call clamp_preparedness
        dec  dword [actions_left]
        mov  ebx, str_rest
        mov  ecx, COL_GRAY
        call log_msg_str
        call draw_game_screen
        jmp  action_loop

;=======================================================================
; confirm_quit
;=======================================================================
confirm_quit:
        ; Show confirm dialog
        pushad
        ; Draw modal box
        mov  ebx, 250
        mov  ecx, 330
        mov  edx, 500
        mov  esi, 100
        mov  edi, COL_BG2
        call vbe_fill_rect
        ; border
        mov  ebx, 250
        mov  ecx, 330
        mov  edx, 500
        mov  esi, 2
        mov  edi, COL_RED
        call vbe_fill_rect
        mov  ecx, 428
        call vbe_fill_rect
        mov  ebx, 260
        mov  ecx, 355
        mov  edx, str_confirm_quit
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str
        ; Y / N buttons
        mov  ebx, 310
        mov  ecx, 388
        mov  edx, 80
        mov  esi, 32
        mov  edi, COL_BTN_1
        call vbe_fill_rect
        mov  ebx, 325
        mov  ecx, 396
        mov  edx, str_yes
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 600
        mov  ecx, 388
        mov  edx, 80
        mov  esi, 32
        mov  edi, COL_BTN_2
        call vbe_fill_rect
        mov  ebx, 617
        mov  ecx, 396
        mov  edx, str_no
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str
        VBE_GAME_PRESENT
.cq_wait:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .cq_mouse
        cmp  eax, 'y'
        je   .cq_yes
        cmp  eax, 'Y'
        je   .cq_yes
        cmp  eax, 'n'
        je   .cq_no
        cmp  eax, 'N'
        je   .cq_no
        cmp  eax, KEY_ESC
        je   .cq_no
        jmp  .cq_wait
.cq_mouse:
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz   .cq_wait
        call wait_up
        cmp  ebx, 388
        jl   .cq_wait
        cmp  ebx, 420
        jg   .cq_wait
        cmp  eax, 310
        jl   .cq_wait
        cmp  eax, 680
        jg   .cq_wait
        cmp  eax, 460
        jl   .cq_yes
        jmp  .cq_no
.cq_yes:
        popad
        jmp  exit_game
.cq_no:
        popad
        call draw_game_screen
        jmp  action_loop

;=======================================================================
; month_end - Disease spreads, deaths, recovery, events
;=======================================================================
month_end:
        ; Infection phase
        call calc_infection_rate
        mov  [temp_val], eax
        mov  ebx, [healthy]
        cmp  eax, ebx
        jle  .inf_ok
        mov  eax, ebx
        mov  [temp_val], eax
.inf_ok:
        sub  [healthy], eax
        add  [infected], eax

        ; Death phase
        mov  eax, [infected]
        cmp  eax, 0
        jle  .no_deaths
        mov  ebx, [set_diff]
        cmp  ebx, 0
        je   .d_easy
        cmp  ebx, 2
        je   .d_hard
        mov  ebx, 14
        jmp  .d_set
.d_easy: mov ebx, 8
        jmp .d_set
.d_hard: mov ebx, 20
.d_set:
        cmp  dword [morale], 30
        jge  .d_mor_ok
        add  ebx, 8
.d_mor_ok:
        mov  ecx, [threat_level]
        cmp  ecx, 3
        jl   .d_thr_done
        sub  ecx, 2
        add  ebx, ecx
.d_thr_done:
        cmp  byte [hospital_built], 1
        jne  .d_no_hosp
        sub  ebx, 3
        cmp  ebx, 4
        jge  .d_no_hosp
        mov  ebx, 4
.d_no_hosp:
        imul eax, ebx
        xor  edx, edx
        mov  ebx, 100
        div  ebx
        cmp  eax, 0
        jg   .has_deaths
        cmp  dword [infected], 5
        jl   .no_deaths
        mov  eax, 1
.has_deaths:
        mov  [temp_val2], eax
        sub  [infected], eax
        add  [dead], eax
        sub  [population], eax
        mov  ebx, eax
        cmp  ebx, 0
        jle  .no_deaths
        sub  [morale], ebx
        call clamp_morale

        ; Death sound
        mov  ecx, [temp_val2]
        cmp  ecx, 5
        jl   .d_snd_done
        mov  eax, SYS_BEEP
        mov  ebx, SND_DEATH
        mov  ecx, 4
        int  0x80
.d_snd_done:
        jmp  .deaths_done
.no_deaths:
        mov  dword [temp_val2], 0
.deaths_done:

        ; Natural recovery
        mov  eax, [infected]
        mov  ebx, [set_diff]
        cmp  ebx, 0
        je   .rec_easy
        cmp  ebx, 2
        je   .rec_hard
        mov  ebx, 4
        jmp  .rec_set
.rec_easy: mov ebx, 12
        jmp .rec_set
.rec_hard: xor ebx, ebx
.rec_set:
        imul eax, ebx
        xor  edx, edx
        mov  ecx, 100
        div  ecx
        cmp  eax, 0
        jle  .no_rec
        mov  ebx, [infected]
        cmp  eax, ebx
        jle  .rec_ok
        mov  eax, ebx
.rec_ok:
        sub  [infected], eax
        add  [recovered], eax
.no_rec:

        ; Morale decay from active infection
        cmp  dword [infected], 8
        jl   .no_mor_dec
        sub  dword [morale], 3
        call clamp_morale
.no_mor_dec:

        ; Draw month summary screen
        call draw_month_summary

        ; Random event check
        call random
        xor  edx, edx
        mov  ebx, 100
        div  ebx
        mov  eax, 22
        mov  ecx, [threat_level]
        imul ecx, 8
        add  eax, ecx
        cmp  dword [preparedness], 70
        jl   .evt_prep_ok
        sub  eax, 10
.evt_prep_ok:
        cmp  dword [morale], 35
        jge  .evt_roll
        add  eax, 6
.evt_roll:
        cmp  eax, 12
        jge  .evt_floor_ok
        mov  eax, 12
.evt_floor_ok:
        cmp  edx, eax
        jl   .has_event
        jmp  .no_event
.has_event:
        call trigger_random_event
.no_event:

        ; Advance month
        inc  dword [month]
        inc  dword [outbreaks_survived]

        ; Wait for key/click to continue
        mov  eax, SYS_BEEP
        mov  ebx, 440
        mov  ecx, 2
        int  0x80

.me_wait:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .me_mouse
        jmp  game_month
.me_mouse:
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz   .me_wait
        call wait_up
        jmp  game_month

;=======================================================================
; RANDOM EVENTS
;=======================================================================
trigger_random_event:
        call random
        xor  edx, edx
        mov  ebx, 8
        div  ebx
        cmp  edx, 0
        je   event_donation
        cmp  edx, 1
        je   event_antivax_rally
        cmp  edx, 2
        je   event_volunteer
        cmp  edx, 3
        je   event_mutation
        cmp  edx, 4
        je   event_supply_theft
        cmp  edx, 5
        je   event_medical_team
        cmp  edx, 6
        je   event_quarantine_break
        jmp  event_good_news

event_donation:
        add  dword [vaccines], 12
        cmp  dword [vaccines], MAX_VACCINES
        jle  .don1
        mov  dword [vaccines], MAX_VACCINES
.don1:  add  dword [supplies], 8
        cmp  dword [supplies], MAX_SUPPLIES
        jle  .don2
        mov  dword [supplies], MAX_SUPPLIES
.don2:  add  dword [morale], 5
        call clamp_morale
        mov  ebx, str_evt_donation
        mov  ecx, COL_GREEN
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_GOOD
        mov  ecx, 4
        int  0x80
        ret

event_antivax_rally:
        sub  dword [morale], 15
        call clamp_morale
        cmp  dword [vaccines], 15
        jl   .av1
        sub  dword [vaccines], 15
.av1:   mov  ebx, str_evt_antivax
        mov  ecx, COL_RED
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_BAD
        mov  ecx, 5
        int  0x80
        ret

event_volunteer:
        add  dword [morale], 5
        add  dword [supplies], 6
        call clamp_morale
        mov  ebx, str_evt_volunteer
        mov  ecx, COL_CYAN
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_GOOD
        mov  ecx, 3
        int  0x80
        ret

event_mutation:
        mov  eax, [vaccinated]
        shr  eax, 2
        cmp  eax, 0
        jle  .mut1
        sub  [vaccinated], eax
        add  [healthy], eax
.mut1:  sub  dword [morale], 8
        call clamp_morale
        mov  ebx, str_evt_mutation
        mov  ecx, COL_ORANGE
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_ALARM
        mov  ecx, 6
        int  0x80
        ret

event_supply_theft:
        mov  eax, [vaccines]
        xor  edx, edx
        mov  ecx, 3
        div  ecx
        sub  [vaccines], eax
        mov  eax, [supplies]
        xor  edx, edx
        mov  ecx, 3
        div  ecx
        sub  [supplies], eax
        sub  dword [morale], 8
        call clamp_morale
        mov  ebx, str_evt_theft
        mov  ecx, COL_RED
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_BAD
        mov  ecx, 4
        int  0x80
        ret

event_medical_team:
        mov  eax, [infected]
        cmp  eax, 5
        jle  .mt1
        mov  eax, 5
.mt1:   sub  [infected], eax
        add  [recovered], eax
        add  [total_treated], eax
        add  dword [morale], 6
        call clamp_morale
        mov  ebx, str_evt_medteam
        mov  ecx, COL_CYAN
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_GOOD
        mov  ecx, 4
        int  0x80
        ret

event_quarantine_break:
        mov  eax, [infected]
        xor  edx, edx
        mov  ecx, 3
        div  ecx
        mov  ebx, [healthy]
        cmp  eax, ebx
        jle  .qb1
        mov  eax, ebx
.qb1:   sub  [healthy], eax
        add  [infected], eax
        sub  dword [morale], 5
        call clamp_morale
        mov  ebx, str_evt_quarantine
        mov  ecx, COL_ORANGE
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_ALARM
        mov  ecx, 5
        int  0x80
        ret

event_good_news:
        add  dword [morale], 5
        call clamp_morale
        mov  ebx, str_evt_goodnews
        mov  ecx, COL_GREEN
        call log_msg_str
        mov  eax, SYS_BEEP
        mov  ebx, SND_GOOD
        mov  ecx, 3
        int  0x80
        ret

;=======================================================================
; GAME WIN
;=======================================================================
game_win:
        ; Persist best vaccination total (only if higher) + win SFX
        mov esi, hs_name_ob
        mov ebx, [total_vaccinated]
        call hs_update
        call audio_sfx_win
        call play_victory_melody
        call draw_endscreen_win
.win_wait:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .win_mouse
        cmp  eax, 'y'
        je   title_screen
        cmp  eax, 'Y'
        je   title_screen
        cmp  eax, 'n'
        je   exit_game
        cmp  eax, 'N'
        je   exit_game
        cmp  eax, KEY_ESC
        je   exit_game
        jmp  .win_wait
.win_mouse:
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz   .win_wait
        call wait_up
        ; y button area ~y=680..720
        cmp  ebx, 680
        jl   .win_wait
        cmp  ebx, 724
        jg   .win_wait
        cmp  eax, 200
        jl   .win_wait
        cmp  eax, 600
        jl   title_screen
        jmp  exit_game

;=======================================================================
; GAME FAILED
;=======================================================================
game_failed:
        mov  eax, SYS_BEEP
        mov  ebx, SND_ALARM
        mov  ecx, 10
        int  0x80
        call draw_endscreen_fail
.fail_wait:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .fail_mouse
        cmp  eax, 'y'
        je   title_screen
        cmp  eax, 'Y'
        je   title_screen
        cmp  eax, 'n'
        je   exit_game
        cmp  eax, 'N'
        je   exit_game
        cmp  eax, KEY_ESC
        je   exit_game
        jmp  .fail_wait
.fail_mouse:
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz   .fail_wait
        call wait_up
        cmp  ebx, 680
        jl   .fail_wait
        cmp  ebx, 724
        jg   .fail_wait
        cmp  eax, 200
        jl   .fail_wait
        cmp  eax, 600
        jl   title_screen
        jmp  exit_game

;=======================================================================
; GAME COLLAPSE
;=======================================================================
game_collapse:
        mov  eax, SYS_BEEP
        mov  ebx, SND_DEATH
        mov  ecx, 15
        int  0x80
        call draw_endscreen_collapse
        jmp  game_over_wait
game_over:
        call audio_sfx_lose
        mov  eax, SYS_BEEP
        mov  ebx, SND_DEATH
        mov  ecx, 15
        int  0x80
        call draw_endscreen_over
game_over_wait:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .fo_mouse
        cmp  eax, 'y'
        je   title_screen
        cmp  eax, 'Y'
        je   title_screen
        cmp  eax, 'n'
        je   exit_game
        cmp  eax, 'N'
        je   exit_game
        cmp  eax, KEY_ESC
        je   exit_game
        jmp  game_over_wait
.fo_mouse:
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jz   game_over_wait
        call wait_up
        cmp  ebx, 680
        jl   game_over_wait
        cmp  eax, 200
        jl   game_over_wait
        cmp  eax, 600
        jl   title_screen
        jmp  exit_game

;=======================================================================
; exit_game
;=======================================================================
exit_game:
        mov  eax, SYS_FRAMEBUF
        mov  ebx, 2
        int  0x80
        mov  eax, SYS_EXIT
        xor  ebx, ebx
        int  0x80
;=======================================================================
; DRAW END SCREEN - WIN
;=======================================================================
draw_endscreen_win:
        pushad
        ; Full screen clear
        mov  edx, 0x000A1C00
        call vbe_clear_screen
        ; Trophy - golden circle + stem
        mov  ebx, 512
        mov  ecx, 200
        mov  edx, 100
        mov  esi, 0x00FFD700
        call vbe_fill_circle
        mov  ebx, 488
        mov  ecx, 300
        mov  edx, 48
        mov  esi, 60
        mov  edi, 0x00FFD700
        call vbe_fill_rect
        mov  ebx, 452
        mov  ecx, 356
        mov  edx, 120
        mov  esi, 20
        mov  edi, 0x00FFD700
        call vbe_fill_rect
        ; WIN text
        mov  ebx, 300
        mov  ecx, 440
        mov  edx, str_you_won
        mov  esi, 0x00FFD700
        mov  eax, 4
        call vbe_draw_str
        ; rating
        call .calc_rating
        mov  ebx, 350
        mov  ecx, 540
        mov  edx, str_rating
        mov  esi, COL_WHITE
        mov  eax, 2
        call vbe_draw_str
        ; draw actual rating value (str_rating = "RATING: " = 8 chars × scale2 = 96px)
        mov  ebx, 446
        mov  ecx, 540
        mov  edx, [rating_ptr]
        mov  esi, COL_GOLD
        mov  eax, 2
        call vbe_draw_str
        ; play again / quit
        mov  ebx, 200
        mov  ecx, 680
        mov  edx, 240
        mov  esi, 40
        mov  edi, COL_BTN_1
        call vbe_fill_rect
        mov  ebx, 215
        mov  ecx, 692
        mov  edx, str_play_again
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 580
        mov  ecx, 680
        mov  edx, 240
        mov  esi, 40
        mov  edi, COL_BTN_2
        call vbe_fill_rect
        mov  ebx, 620
        mov  ecx, 692
        mov  edx, str_quit
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str
        VBE_GAME_PRESENT
        popad
        ret
.calc_rating:
        ; score = dead/population pct under 5% = S, 10% = A, 20% = B, else C
        mov  eax, [dead]
        imul eax, 100
        xor  edx, edx
        mov  ecx, COMMUNITY_SIZE
        div  ecx
        cmp  eax, 5
        jle  .rating_s
        cmp  eax, 10
        jle  .rating_a
        cmp  eax, 20
        jle  .rating_b
        mov  dword [rating_ptr], str_rating_c
        ret
.rating_s:
        mov  dword [rating_ptr], str_rating_s
        ret
.rating_a:
        mov  dword [rating_ptr], str_rating_a
        ret
.rating_b:
        mov  dword [rating_ptr], str_rating_b
        ret

;=======================================================================
; DRAW END SCREEN - FAIL
;=======================================================================
draw_endscreen_fail:
        pushad
        mov  edx, 0x00100000
        call vbe_clear_screen
        ; Sad skull shape - circle
        mov  ebx, 512
        mov  ecx, 200
        mov  edx, 100
        mov  esi, COL_GRAY
        call vbe_fill_circle
        ; X eyes
        mov  ebx, 470
        mov  ecx, 190
        mov  edx, 554
        mov  esi, 210
        mov  edi, 0x00110000
        call vbe_draw_line
        mov  ebx, 470
        mov  ecx, 210
        mov  edx, 554
        mov  esi, 190
        mov  edi, 0x00110000
        call vbe_draw_line
        ; Game over text
        mov  ebx, 250
        mov  ecx, 420
        mov  edx, str_game_over_txt
        mov  esi, COL_RED
        mov  eax, 3
        call vbe_draw_str
        mov  ebx, 250
        mov  ecx, 510
        mov  edx, str_fail_msg
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str
        ; Buttons
        mov  ebx, 200
        mov  ecx, 680
        mov  edx, 240
        mov  esi, 40
        mov  edi, COL_BTN_1
        call vbe_fill_rect
        mov  ebx, 215
        mov  ecx, 692
        mov  edx, str_play_again
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 580
        mov  ecx, 680
        mov  edx, 240
        mov  esi, 40
        mov  edi, COL_BTN_2
        call vbe_fill_rect
        mov  ebx, 620
        mov  ecx, 692
        mov  edx, str_quit
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str
        VBE_GAME_PRESENT
        popad
        ret

;=======================================================================
; DRAW END SCREEN - COLLAPSE
;=======================================================================
draw_endscreen_collapse:
        pushad
        mov  edx, 0x00080000
        call vbe_clear_screen
        mov  ebx, 200
        mov  ecx, 360
        mov  edx, str_collapse_txt
        mov  esi, 0x00FF4400
        mov  eax, 3
        call vbe_draw_str
        mov  ebx, 200
        mov  ecx, 450
        mov  edx, str_collapse_msg
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 200
        mov  ecx, 680
        mov  edx, 240
        mov  esi, 40
        mov  edi, COL_BTN_1
        call vbe_fill_rect
        mov  ebx, 215
        mov  ecx, 692
        mov  edx, str_play_again
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 580
        mov  ecx, 680
        mov  edx, 240
        mov  esi, 40
        mov  edi, COL_BTN_2
        call vbe_fill_rect
        mov  ebx, 620
        mov  ecx, 692
        mov  edx, str_quit
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str
        VBE_GAME_PRESENT
        popad
        ret

draw_endscreen_over:
        jmp  draw_endscreen_collapse

;=======================================================================
; draw_game_screen - Full game UI render
;=======================================================================
draw_game_screen:
        pushad
        ; Background
        mov  edx, COL_BG
        call vbe_clear_screen

        ; Header bar
        mov  ebx, 0
        mov  ecx, 0
        mov  edx, 1024
        mov  esi, 48
        mov  edi, COL_HEADER
        call vbe_fill_rect
        ; Title
        mov  ebx, 20
        mov  ecx, 10
        mov  edx, str_title
        mov  esi, COL_WHITE
        mov  eax, 2
        call vbe_draw_str
        ; Month label
        mov  ebx, 380
        mov  ecx, 10
        mov  edx, str_month_lbl
        mov  esi, COL_GRAY
        mov  eax, 2
        call vbe_draw_str
        mov  ebx, 466
        mov  ecx, 10
        mov  edx, [month]
        mov  esi, COL_WHITE
        mov  eax, 2
        call vbe_draw_num
        ; Month name
        call print_month_name_hdr

        ; Threat label
        mov  ebx, 620
        mov  ecx, 10
        mov  edx, str_threat_lbl
        mov  esi, COL_GRAY
        mov  eax, 2
        call vbe_draw_str
        ; Draw threat bar (right in header)
        mov  ebx, 720
        mov  ecx, 14
        call draw_threat_bar_inline

        ; Separator
        mov  ebx, 0
        mov  ecx, 48
        mov  edx, 1024
        mov  esi, 2
        mov  edi, COL_BORDER
        call vbe_fill_rect

        ; Left panel log area (x=8, y=56, w=696, h=490)
        call draw_log_area

        ; Right panel (x=720, y=56, w=296, h=700)
        call draw_stat_panel

        ; Action buttons area
        call draw_action_btns

        ; Right panel separator line
        mov  ebx, 716
        mov  ecx, 50
        mov  edx, 2
        mov  esi, 696
        mov  edi, COL_BORDER
        call vbe_fill_rect

        VBE_GAME_PRESENT
        popad
        ret

;=======================================================================
; print_month_name_hdr - print month name in header
;=======================================================================
print_month_name_hdr:
        pushad
        mov  eax, [month]
        cmp  eax, 1
        jl   .mnh_clamp
        cmp  eax, 12
        jle  .mnh_ok
.mnh_clamp:
        mov  eax, 1
.mnh_ok:
        dec  eax
        imul eax, 4
        add  eax, month_name_ptrs
        mov  edx, [eax]
        mov  ebx, 510
        mov  ecx, 10
        mov  esi, COL_CYAN
        mov  eax, 2
        call vbe_draw_str
        popad
        ret

;=======================================================================
; draw_log_area - display log buffer entries
;=======================================================================
draw_log_area:
        pushad
        ; Semi-transparent log area bg
        mov  ebx, 8
        mov  ecx, 56
        mov  edx, 696
        mov  esi, 490
        mov  edi, COL_BG2
        call vbe_fill_rect

        ; Border
        mov  ebx, 8
        mov  ecx, 56
        mov  edx, 696
        mov  esi, 2
        mov  edi, COL_BORDER
        call vbe_fill_rect
        mov  ecx, 544
        call vbe_fill_rect
        mov  ebx, 8
        mov  ecx, 56
        mov  edx, 2
        mov  esi, 490
        mov  edi, COL_BORDER
        call vbe_fill_rect
        mov  ebx, 702
        call vbe_fill_rect

        ; LOG label
        mov  ebx, 16
        mov  ecx, 62
        mov  edx, str_log_lbl
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str

        ; Draw each log line
        xor  esi, esi
.log_loop:
        cmp  esi, LOG_LINES
        jge  .log_done
        mov  eax, esi
        imul eax, 4
        add  eax, log_ptrs
        mov  edx, [eax]
        cmp  edx, 0
        je   .log_next
        push esi
        mov  eax, esi
        imul eax, 4
        add  eax, log_cols
        mov  esi, [eax]

        ; Calc y position (saved esi on stack, peek at it)
        mov  ecx, [esp]
        imul ecx, 14
        add  ecx, 78

        mov  ebx, 18
        mov  eax, 1
        call vbe_draw_str
        pop  esi
.log_next:
        inc  esi
        jmp  .log_loop
.log_done:
        popad
        ret

;=======================================================================
; draw_stat_panel - Right panel stats
;=======================================================================
draw_stat_panel:
        pushad
        ; Panel bg
        mov  ebx, 718
        mov  ecx, 50
        mov  edx, 298
        mov  esi, 700
        mov  edi, COL_BG2
        call vbe_fill_rect

        ; Population title
        mov  ebx, 724
        mov  ecx, 56
        mov  edx, str_population
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str

        mov  ebx, 724
        mov  ecx, 68
        mov  edx, [population]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        ; Population bar at y=82
        call draw_population_bar

        ; Stats rows
        mov  ebx, 724
        mov  ecx, 150
        mov  edx, str_lbl_healthy
        mov  esi, COL_HEALTHY
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 874
        mov  ecx, 150
        mov  edx, [healthy]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 166
        mov  ebx, 724
        mov  edx, str_lbl_vaccinated
        mov  esi, COL_VACCINATED
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 874
        mov  edx, [vaccinated]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 182
        mov  ebx, 724
        mov  edx, str_lbl_infected
        mov  esi, COL_INFECTED
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 874
        mov  edx, [infected]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 198
        mov  ebx, 724
        mov  edx, str_lbl_recovered
        mov  esi, COL_RECOVERED
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 874
        mov  edx, [recovered]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 214
        mov  ebx, 724
        mov  edx, str_lbl_dead
        mov  esi, COL_DEAD
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 874
        mov  edx, [dead]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        ; Resources
        mov  ebx, 724
        mov  ecx, 238
        mov  edx, str_lbl_vax
        mov  esi, COL_CYAN
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 874
        mov  edx, [vaccines]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 254
        mov  ebx, 724
        mov  edx, str_lbl_sup
        mov  esi, COL_CYAN
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 874
        mov  edx, [supplies]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 270
        mov  ebx, 724
        mov  edx, str_lbl_morale
        mov  esi, COL_YELLOW
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 874
        mov  edx, [morale]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 286
        mov  ebx, 724
        mov  edx, str_lbl_research
        mov  esi, COL_YELLOW
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 874
        mov  edx, [research]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 302
        mov  ebx, 724
        mov  edx, str_lbl_prep
        mov  esi, COL_GREEN
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 874
        mov  edx, [preparedness]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        ; Hospital / Lab indicators
        mov  ebx, 724
        mov  ecx, 322
        cmp  byte [hospital_built], 1
        jne  .no_hosp_ind
        mov  edx, str_hosp_built
        mov  esi, COL_GREEN
        mov  eax, 1
        call vbe_draw_str
        add  ecx, 14
.no_hosp_ind:
        cmp  byte [lab_built], 1
        jne  .no_lab_ind
        mov  edx, str_lab_built
        mov  esi, COL_CYAN
        mov  eax, 1
        call vbe_draw_str
.no_lab_ind:

        ; Actions left
        mov  ebx, 724
        mov  ecx, 366
        mov  edx, str_actions_left
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 874
        mov  edx, [actions_left]
        mov  esi, COL_WHITE
        mov  eax, 2
        call vbe_draw_num

        popad
        ret

;=======================================================================
; draw_population_bar - segmented horizontal bar
;=======================================================================
draw_population_bar:
        pushad
        ; Bar base at y=90, height=24, total width=280
        mov  ebx, 724
        mov  ecx, 90
        mov  edx, 280
        mov  esi, 24
        mov  edi, COL_DEAD
        call vbe_fill_rect

        ; Calculate segment widths
        ; Total = COMMUNITY_SIZE, bar = 280px
        mov  ecx, [dead]
        imul ecx, 280
        xor  edx, edx
        mov  eax, ecx
        mov  ecx, COMMUNITY_SIZE
        div  ecx
        ; dead already grey, skip drawing
        ; Draw recovered
        add  ebx, eax
        push eax
        mov  eax, [recovered]
        imul eax, 280
        xor  edx, edx
        mov  ecx, COMMUNITY_SIZE
        div  ecx
        mov  edi, COL_RECOVERED
        push eax
        mov  edx, eax
        mov  esi, 24
        call vbe_fill_rect
        pop  eax
        add  ebx, eax
        ; Draw healthy
        mov  eax, [healthy]
        imul eax, 280
        xor  edx, edx
        mov  ecx, COMMUNITY_SIZE
        div  ecx
        mov  edi, COL_HEALTHY
        push eax
        mov  edx, eax
        mov  esi, 24
        call vbe_fill_rect
        pop  eax
        add  ebx, eax
        ; Draw vaccinated
        mov  eax, [vaccinated]
        imul eax, 280
        xor  edx, edx
        mov  ecx, COMMUNITY_SIZE
        div  ecx
        mov  edi, COL_VACCINATED
        push eax
        mov  edx, eax
        mov  esi, 24
        call vbe_fill_rect
        pop  eax
        add  ebx, eax
        ; Draw infected (on top)
        mov  eax, [infected]
        imul eax, 280
        xor  edx, edx
        mov  ecx, COMMUNITY_SIZE
        div  ecx
        mov  edi, COL_INFECTED
        mov  edx, eax
        mov  esi, 24
        call vbe_fill_rect
        ; bar border
        pop  eax
        ; top edge
        mov  ebx, 724
        mov  ecx, 90
        mov  edx, 280
        mov  esi, COL_BORDER
        call vbe_draw_hline
        ; bottom edge
        mov  ecx, 113
        call vbe_draw_hline
        ; left edge
        mov  ebx, 724
        mov  ecx, 90
        mov  edx, 24
        call vbe_draw_vline
        ; right edge
        mov  ebx, 1003
        call vbe_draw_vline
        popad
        ret

;=======================================================================
; draw_threat_bar_inline - small threat indicator in header
;=======================================================================
draw_threat_bar_inline:
        ; EBX=x, ECX=y on entry
        pushad
        mov  eax, [threat_level]
        cmp  eax, 0
        je   .thr_green
        cmp  eax, 1
        je   .thr_yellow
        cmp  eax, 2
        je   .thr_orange
        mov  esi, COL_RED
        jmp  .thr_draw
.thr_green:  mov esi, COL_GREEN
        jmp .thr_draw
.thr_yellow: mov esi, COL_YELLOW
        jmp .thr_draw
.thr_orange: mov esi, COL_ORANGE
.thr_draw:
        ; EBX=x, ECX=y from caller — intact after pushad
        mov  edi, esi           ; colour → EDI (correct vbe_fill_rect arg)
        mov  edx, 80            ; width
        mov  esi, 20            ; height (was wrongly placed in ECX before)
        call vbe_fill_rect
        ; threat level number
        mov  ebx, 808
        mov  ecx, 14
        mov  edx, [threat_level]
        mov  esi, COL_WHITE
        mov  eax, 2
        call vbe_draw_num
        popad
        ret

;=======================================================================
; draw_action_btns - 6 action buttons
;=======================================================================
draw_action_btns:
        pushad
        ; Row 1: y=560
        ; Row 2: y=610
        ; Cols: x=8, 178, 348, 518, 688 (5 cols would be too many, 3 cols is fine with width 162)
        ; Actually 6 buttons: row1: cols 8,178,348 ; row2: cols 8,178,348

        ; Determine if actions available
        mov  eax, [actions_left]
        cmp  eax, 0
        je   .btns_dim

        ; Active buttons
        ; Button 1: VACCINATE
        mov  ebx, BTN_COL1
        mov  ecx, BTN_ROW1_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_BTN_1
        call vbe_fill_rect
        mov  ebx, BTN_COL1 + 8
        mov  ecx, BTN_ROW1_Y + BTN_H/2 - 4
        mov  edx, str_act_vaccinate
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        ; Button 2: TREAT
        mov  ebx, BTN_COL2
        mov  ecx, BTN_ROW1_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_BTN_2
        call vbe_fill_rect
        mov  ebx, BTN_COL2 + 8
        mov  ecx, BTN_ROW1_Y + BTN_H/2 - 4
        mov  edx, str_act_treat
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        ; Button 3: SUPPLY RUN
        mov  ebx, BTN_COL3
        mov  ecx, BTN_ROW1_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_BTN_3
        call vbe_fill_rect
        mov  ebx, BTN_COL3 + 8
        mov  ecx, BTN_ROW1_Y + BTN_H/2 - 4
        mov  edx, str_act_supply
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        ; Button 4: RESEARCH
        mov  ebx, BTN_COL1
        mov  ecx, BTN_ROW2_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_BTN_4
        call vbe_fill_rect
        mov  ebx, BTN_COL1 + 8
        mov  ecx, BTN_ROW2_Y + BTN_H/2 - 4
        mov  edx, str_act_research
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        ; Button 5: AWARENESS
        mov  ebx, BTN_COL2
        mov  ecx, BTN_ROW2_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_BTN_5
        call vbe_fill_rect
        mov  ebx, BTN_COL2 + 8
        mov  ecx, BTN_ROW2_Y + BTN_H/2 - 4
        mov  edx, str_act_awareness
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        ; Button 6: REST
        mov  ebx, BTN_COL3
        mov  ecx, BTN_ROW2_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_BTN_6
        call vbe_fill_rect
        mov  ebx, BTN_COL3 + 8
        mov  ecx, BTN_ROW2_Y + BTN_H/2 - 4
        mov  edx, str_act_rest
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        jmp  .btns_done

.btns_dim:
        ; Draw all 6 buttons dim grey
        mov  ebx, BTN_COL1
        mov  ecx, BTN_ROW1_Y
        mov  edx, BTN_W
        mov  esi, BTN_H
        mov  edi, COL_DIM
        call vbe_fill_rect
        mov  ebx, BTN_COL2
        call vbe_fill_rect
        mov  ebx, BTN_COL3
        call vbe_fill_rect
        mov  ecx, BTN_ROW2_Y
        mov  ebx, BTN_COL1
        call vbe_fill_rect
        mov  ebx, BTN_COL2
        call vbe_fill_rect
        mov  ebx, BTN_COL3
        call vbe_fill_rect

        ; Labels still
        mov  ebx, BTN_COL1 + 8
        mov  ecx, BTN_ROW1_Y + BTN_H/2 - 4
        mov  edx, str_act_vaccinate
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, BTN_COL2 + 8
        mov  edx, str_act_treat
        call vbe_draw_str
        mov  ebx, BTN_COL3 + 8
        mov  edx, str_act_supply
        call vbe_draw_str
        mov  ebx, BTN_COL1 + 8
        mov  ecx, BTN_ROW2_Y + BTN_H/2 - 4
        mov  edx, str_act_research
        call vbe_draw_str
        mov  ebx, BTN_COL2 + 8
        mov  edx, str_act_awareness
        call vbe_draw_str
        mov  ebx, BTN_COL3 + 8
        mov  edx, str_act_rest
        call vbe_draw_str

.btns_done:
        ; "END MONTH" button (right area below stats)
        mov  ebx, 724
        mov  ecx, 660
        mov  edx, 290
        mov  esi, 40
        mov  edi, COL_BTN_END
        call vbe_fill_rect
        mov  ebx, 760
        mov  ecx, 672
        mov  edx, str_end_month
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_str

        ; QUIT button
        mov  ebx, 724
        mov  ecx, 712
        mov  edx, 290
        mov  esi, 40
        mov  edi, COL_DIM
        call vbe_fill_rect
        mov  ebx, 800
        mov  ecx, 724
        mov  edx, str_quit
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str

        popad
        ret

;=======================================================================
; draw_month_summary - modal overlay after each month
;=======================================================================
draw_month_summary:
        pushad
        ; Semi-opaque overlay
        mov  ebx, 150
        mov  ecx, 180
        mov  edx, 720
        mov  esi, 400
        mov  edi, 0x00040812
        call vbe_fill_rect
        ; Border
        mov  ebx, 150
        mov  ecx, 180
        mov  edx, 720
        mov  esi, 2
        mov  edi, COL_BORDER
        call vbe_fill_rect
        mov  ecx, 578
        call vbe_fill_rect
        mov  ebx, 150
        mov  ecx, 182
        mov  edx, 2
        mov  esi, 398
        mov  edi, COL_BORDER
        call vbe_fill_rect
        mov  ebx, 868
        call vbe_fill_rect

        ; Title
        mov  ebx, 300
        mov  ecx, 196
        mov  edx, str_month_summary
        mov  esi, COL_WHITE
        mov  eax, 2
        call vbe_draw_str

        ; Stats
        mov  ebx, 180
        mov  ecx, 240
        mov  edx, str_lbl_infected
        mov  esi, COL_INFECTED
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 400
        mov  edx, [infected]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 258
        mov  ebx, 180
        mov  edx, str_lbl_dead
        mov  esi, COL_DEAD
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 400
        mov  edx, [dead]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 276
        mov  ebx, 180
        mov  edx, str_lbl_vaccinated
        mov  esi, COL_VACCINATED
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 400
        mov  edx, [vaccinated]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 294
        mov  ebx, 180
        mov  edx, str_total_vaxd
        mov  esi, COL_GREEN
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 400
        mov  edx, [total_vaccinated]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        mov  ecx, 312
        mov  ebx, 180
        mov  edx, str_lbl_morale
        mov  esi, COL_YELLOW
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 400
        mov  edx, [morale]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        ; New infections this month
        mov  ecx, 330
        mov  ebx, 180
        mov  edx, str_new_infections
        mov  esi, COL_ORANGE
        mov  eax, 1
        call vbe_draw_str
        mov  ebx, 400
        mov  edx, [temp_val]
        mov  esi, COL_WHITE
        mov  eax, 1
        call vbe_draw_num

        ; "PRESS ANY KEY" prompt
        mov  ebx, 300
        mov  ecx, 530
        mov  edx, str_press_key
        mov  esi, COL_GRAY
        mov  eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT
        popad
        ret

;=======================================================================
; UTILITY FUNCTIONS
;=======================================================================

; random - LCG RNG, returns EAX
random:
        pushad
        mov  eax, [rand_seed]
        imul eax, 1664525
        add  eax, 1013904223
        mov  [rand_seed], eax
        and  eax, 0x7FFFFFFF
        mov  [esp+28], eax
        popad
        ret

; calc_difficulty - set decay constants by difficulty
calc_difficulty:
        pushad
        mov  eax, [set_diff]
        cmp  eax, 0
        je   .easy
        cmp  eax, 2
        je   .hard
        ; normal
        mov  dword [_decay_vax], DECAY_VAX_NRM
        mov  dword [_decay_sup], DECAY_SUP_NRM
        mov  dword [_decay_mor], DECAY_MOR_NRM
        jmp  .done
.easy:
        mov  dword [_decay_vax], DECAY_VAX_EASY
        mov  dword [_decay_sup], DECAY_SUP_EASY
        mov  dword [_decay_mor], DECAY_MOR_EASY
        jmp  .done
.hard:
        mov  dword [_decay_vax], DECAY_VAX_HARD
        mov  dword [_decay_sup], DECAY_SUP_HARD
        mov  dword [_decay_mor], DECAY_MOR_HARD
.done:
        popad
        ret

; monthly_decay - apply resource decay each month
monthly_decay:
        pushad
        mov  eax, [vaccines]
        sub  eax, [_decay_vax]
        cmp  eax, 0
        jge  .vax_ok
        xor  eax, eax
.vax_ok:
        mov  [vaccines], eax

        mov  eax, [supplies]
        sub  eax, [_decay_sup]
        cmp  eax, 0
        jge  .sup_ok
        xor  eax, eax
.sup_ok:
        mov  [supplies], eax

        mov  eax, [morale]
        sub  eax, [_decay_mor]
        mov  [morale], eax
        call clamp_morale
        popad
        ret

; calc_infection_rate - returns new infections in EAX
calc_infection_rate:
        pushad
        mov  eax, [infected]
        cmp  eax, 0
        jle  .no_inf
        ; base rate by difficulty
        mov  ebx, [set_diff]
        cmp  ebx, 0
        je   .inf_easy
        cmp  ebx, 2
        je   .inf_hard
        mov  ecx, 12
        jmp  .inf_rate_set
.inf_easy: mov ecx, 7
        jmp .inf_rate_set
.inf_hard: mov ecx, 18
.inf_rate_set:
        ; Modify by threat
        mov  ebx, [threat_level]
        imul ebx, 4
        add  ecx, ebx
        ; Reduce by vaccines/preparedness
        mov  ebx, [vaccinated]
        imul ebx, VACCINE_EFFECT
        xor  edx, edx
        mov  eax, ebx
        mov  ebx, [population]
        cmp  ebx, 0
        jle  .no_inf
        div  ebx
        cmp  ecx, eax
        jle  .no_inf
        sub  ecx, eax
        ; preparedness reduction
        mov  eax, [preparedness]
        shr  eax, 3
        cmp  ecx, eax
        jle  .no_inf
        sub  ecx, eax
        ; supplies reduction
        cmp  dword [supplies], 50
        jl   .low_sup
        sub  ecx, 2
        jmp  .sup_done
.low_sup:
        add  ecx, 3
.sup_done:
        cmp  ecx, 0
        jle  .no_inf
        ; multiply by susceptible pop
        mov  eax, [healthy]
        imul eax, ecx
        xor  edx, edx
        mov  ebx, 100
        div  ebx
        ; add base outbreak
        add  eax, OUTBREAK_BASE
        ; hospital reduces
        cmp  byte [hospital_built], 1
        jne  .no_hosp_rdc
        sub  eax, 3
        cmp  eax, OUTBREAK_BASE
        jge  .no_hosp_rdc
        mov  eax, OUTBREAK_BASE
.no_hosp_rdc:
        cmp  eax, [healthy]
        jle  .inf_ok
        mov  eax, [healthy]
.inf_ok:
        mov  [esp+28], eax
        popad
        ret
.no_inf:
        xor  eax, eax
        mov  [esp+28], eax
        popad
        ret

; clamp_morale - keep morale 0..100
clamp_morale:
        pushad
        cmp  dword [morale], 0
        jge  .cm_top
        mov  dword [morale], 0
        jmp  .cm_done
.cm_top:
        cmp  dword [morale], 100
        jle  .cm_done
        mov  dword [morale], 100
.cm_done:
        popad
        ret

; clamp_preparedness - keep 0..100
clamp_preparedness:
        pushad
        cmp  dword [preparedness], 0
        jge  .cp_top
        mov  dword [preparedness], 0
        jmp  .cp_done
.cp_top:
        cmp  dword [preparedness], 100
        jle  .cp_done
        mov  dword [preparedness], 100
.cp_done:
        popad
        ret

; log_msg_str - append string pointer EBX to log, colour ECX
log_msg_str:
        pushad
        mov  eax, [log_head]
        imul eax, 4
        add  eax, log_ptrs
        mov  [eax], ebx
        mov  eax, [log_head]
        imul eax, 4
        add  eax, log_cols
        mov  [eax], ecx
        inc  dword [log_head]
        cmp  dword [log_head], LOG_LINES
        jl   .lm_done
        mov  dword [log_head], 0
.lm_done:
        popad
        ret

; log_msg_num - append number EAX to log, colour ECX
log_msg_num:
        pushad
        ; Convert number to decimal string in msg_buf
        push eax
        push ecx
        mov  edi, msg_buf
        call .itoa
        pop  ecx
        pop  eax
        mov  ebx, msg_buf
        call log_msg_str
        popad
        ret
.itoa:
        ; eax=value, edi=buf pointer
        push eax
        push ebx
        push ecx
        push edx
        push edi
        mov  ebx, 10
        xor  ecx, ecx
.it1:
        xor  edx, edx
        div  ebx
        add  edx, '0'
        push edx
        inc  ecx
        cmp  eax, 0
        jne  .it1
        mov  edi, [esp + ecx*4]
.it2:
        pop  eax
        mov  [edi], al
        inc  edi
        loop .it2
        mov  byte [edi], 0
        pop  edi
        pop  edx
        pop  ecx
        pop  ebx
        pop  eax
        ret

; wait_up - wait for mouse button release
wait_up:
        pushad
.wu_loop:
        mov  eax, SYS_MOUSE
        int  0x80
        test ecx, 1
        jnz  .wu_loop
        popad
        ret

;=======================================================================
; MELODIES
;=======================================================================
play_title_melody:
        pushad
        mov  eax, SYS_BEEP
        mov  ebx, 523
        mov  ecx, 6
        int  0x80
        mov  eax, SYS_BEEP
        mov  ebx, 659
        mov  ecx, 6
        int  0x80
        mov  eax, SYS_BEEP
        mov  ebx, 784
        mov  ecx, 6
        int  0x80
        mov  eax, SYS_BEEP
        mov  ebx, 1047
        mov  ecx, 8
        int  0x80
        popad
        ret

play_victory_melody:
        pushad
        mov  eax, SYS_BEEP
        mov  ebx, 523
        mov  ecx, 4
        int  0x80
        mov  eax, SYS_BEEP
        mov  ebx, 659
        mov  ecx, 4
        int  0x80
        mov  eax, SYS_BEEP
        mov  ebx, 784
        mov  ecx, 4
        int  0x80
        mov  eax, SYS_BEEP
        mov  ebx, 1047
        mov  ecx, 4
        int  0x80
        mov  eax, SYS_BEEP
        mov  ebx, 784
        mov  ecx, 4
        int  0x80
        mov  eax, SYS_BEEP
        mov  ebx, 1047
        mov  ecx, 4
        int  0x80
        mov  eax, SYS_BEEP
        mov  ebx, 1319
        mov  ecx, 10
        int  0x80
        popad
        ret

;=======================================================================
; ob_clear - fill screen with COL_BG
;=======================================================================
ob_clear:
        pushad
        mov  edx, COL_BG
        call vbe_clear_screen
        popad
        ret

;=======================================================================
; draw_panel_title - draw common header banner
;=======================================================================
draw_panel_title:
        pushad
        mov  ebx, 0
        mov  ecx, 0
        mov  edx, 1024
        mov  esi, 48
        mov  edi, COL_HEADER
        call vbe_fill_rect
        mov  ebx, 20
        mov  ecx, 10
        mov  edx, str_title
        mov  esi, COL_WHITE
        mov  eax, 2
        call vbe_draw_str
        popad
        ret

;=======================================================================
; spawn_vaccine_particles - particle effect for vaccination
;=======================================================================
spawn_vaccine_particles:
        ret

;=======================================================================
; spawn_treat_particles - particle effect for treatment
;=======================================================================
spawn_treat_particles:
        ret

;=======================================================================
; DATA SECTION
;=======================================================================
str_title        db 'OUTBREAK SHIELD', 0
str_month_lbl    db 'MONTH:', 0
str_threat_lbl   db 'THREAT:', 0
str_log_lbl      db 'LOG', 0
str_population   db 'POPULATION', 0
str_lbl_healthy  db 'HEALTHY:', 0
str_lbl_vaccinated db 'VACCINATED:', 0
str_lbl_infected db 'INFECTED:', 0
str_lbl_recovered db 'RECOVERED:', 0
str_lbl_dead     db 'DEAD:', 0
str_lbl_vax      db 'VACCINES:', 0
str_lbl_sup      db 'SUPPLIES:', 0
str_lbl_morale   db 'MORALE:', 0
str_lbl_research db 'RESEARCH:', 0
str_lbl_prep     db 'PREPAREDNESS:', 0
str_actions_left db 'ACTIONS:', 0
str_end_month    db 'END MONTH', 0
str_quit         db 'QUIT', 0
str_hosp_built   db '[HOSPITAL ACTIVE]', 0
str_lab_built    db '[LAB ACTIVE]', 0
str_month_summary db 'MONTH SUMMARY', 0
str_new_infections db 'NEW INFECTIONS:', 0
str_total_vaxd   db 'TOTAL VACCINATED:', 0
str_press_key    db 'PRESS ANY KEY TO CONTINUE', 0
str_confirm_quit db 'QUIT THE GAME?', 0
str_yes          db 'YES', 0
str_no           db 'NO', 0
str_you_won      db 'VICTORY!', 0
str_game_over_txt db 'GAME OVER', 0
str_fail_msg     db 'THE OUTBREAK COULD NOT BE CONTAINED.', 0
str_collapse_txt db 'COLLAPSE!', 0
str_collapse_msg db 'TOO MANY LIVES WERE LOST.', 0
str_play_again   db 'PLAY AGAIN?', 0
str_rating       db 'RATING: ', 0
str_rating_s     db 'S - OUTSTANDING', 0
str_rating_a     db 'A - EXCELLENT', 0
str_rating_b     db 'B - GOOD', 0
str_rating_c     db 'C - POOR', 0
str_act_vaccinate db '1. VACCINATE', 0
str_act_treat    db '2. TREAT', 0
str_act_supply   db '3. SUPPLY RUN', 0
str_act_research db '4. RESEARCH', 0
str_act_awareness db '5. AWARENESS', 0
str_act_rest     db '6. REST', 0
str_awareness_vax db 'AWARENESS CAMPAIGN VACCINATED: ', 0
str_awareness_ok db 'AWARENESS CAMPAIGN BOOSTED MORALE.', 0
str_rest         db 'TEAM RESTED. MORALE+2 PREP+2.', 0
str_vax_ok       db 'VACCINATION DRIVE COMPLETE.', 0
str_vax_low_res  db 'NOT ENOUGH VACCINES OR SUPPLIES.', 0
str_treat_ok     db 'TREATMENT ADMINISTERED.', 0
str_treat_low    db 'NO INFECTED TO TREAT.', 0
str_supply_ok    db 'SUPPLY RUN SUCCESSFUL.', 0
str_research_ok  db 'RESEARCH ADVANCED.', 0
str_hospital_unlocked db 'HOSPITAL UNLOCKED!', 0
str_lab_unlocked db 'RESEARCH LAB UNLOCKED!', 0
str_evt_donation db '[EVENT] DONATION: VACCINES+12 SUPPLIES+8.', 0
str_evt_antivax  db '[EVENT] ANTI-VAX RALLY: MORALE-15 VAX-15.', 0
str_evt_volunteer db '[EVENT] VOLUNTEERS ARRIVED: MORALE+5.', 0
str_evt_mutation db '[EVENT] MUTATION: SOME IMMUNITY LOST!', 0
str_evt_theft    db '[EVENT] SUPPLY THEFT! RESOURCES STOLEN.', 0
str_evt_medteam  db '[EVENT] MEDICAL TEAM: 5 TREATED FREE.', 0
str_evt_quarantine db '[EVENT] QUARANTINE BREAK! NEW INFECTIONS.', 0
str_evt_goodnews db '[EVENT] GOOD NEWS: MORALE+5.', 0
str_howto1       db 'PROTECT YOUR COMMUNITY FOR 12 MONTHS.', 0
str_howto2       db 'EACH MONTH YOU HAVE 2 ACTIONS.', 0
str_howto3       db '1. VACCINATE - USE VACCINES ON HEALTHY', 0
str_howto4       db '2. TREAT - CARE FOR THE INFECTED', 0
str_howto5       db '3. SUPPLY RUN - RESTOCK VACCINES+SUPPLIES', 0
str_howto6       db '4. RESEARCH - UNLOCK HOSPITAL AND LAB', 0
str_howto7       db '5. AWARENESS - BOOST MORALE AND PREP', 0
str_howto8       db '6. REST - RECOVER MORALE AND PREPAREDNESS', 0
str_howto9       db 'WIN: < 10% INFECTED AND > 25% ALIVE', 0
str_howto10      db 'LOSE: MORALE=0 OR MONTH 12 ENDS BADLY', 0
str_howto11      db 'COLLAPSE: 50%+ DEAD', 0
str_howto_press  db 'PRESS ANY KEY TO RETURN', 0
str_settings_hdr db 'DIFFICULTY SETTINGS', 0
str_diff_easy    db '1. EASY   (60 VAX, 50 SUPPLY, 80 MORALE)', 0
str_diff_normal  db '2. NORMAL (35 VAX, 30 SUPPLY, 60 MORALE)', 0
str_diff_hard    db '3. HARD   (15 VAX, 15 SUPPLY, 40 MORALE)', 0
str_game_started db 'GAME STARTED. GOOD LUCK.', 0

; Title screen strings
str_title_l1     db 'OUTBREAK', 0
str_title_l2     db 'SHIELD', 0
str_subtitle     db 'A VACCINATION SIMULATION', 0
str_story1       db 'RATEL FEVER HAS BROKEN OUT IN YOUR COMMUNITY.', 0
str_story2       db 'AS CHIEF MEDICAL OFFICER YOU MUST MANAGE', 0
str_story3       db 'VACCINES, SUPPLIES AND MORALE FOR 12 MONTHS.', 0
str_footer       db 'MOUSE OR 1-4 TO SELECT', 0
str_mbtn_play    db '1. PLAY', 0
str_mbtn_howto   db '2. HOW TO PLAY', 0
str_mbtn_settings db '3. SETTINGS', 0
str_mbtn_quit    db '4. QUIT', 0

; Howto screen
str_howto_title  db 'HOW TO PLAY', 0
str_press_any    db 'PRESS ANY KEY TO RETURN', 0
howto_lines:
        dd str_howto1, str_howto2, str_howto3, str_howto4
        dd str_howto5, str_howto6, str_howto7, str_howto8
        dd str_howto9, str_howto10, str_howto11, 0

; Settings screen
str_settings_title db 'SETTINGS', 0
str_preset_easy  db '1. EASY', 0
str_preset_normal db '2. NORMAL', 0
str_preset_hard  db '3. HARD', 0
str_set_diff     db 'DIFFICULTY: ', 0
str_set_vaccines db 'STARTING VACCINES/SUPPLIES/MORALE ABOVE.', 0
str_set_footer   db 'PRESS 1/2/3 TO CHOOSE  ESC TO RETURN', 0
diff_names:
        dd str_diff_easy, str_diff_normal, str_diff_hard

; Title animation dot offsets (32 pairs: dx,dy as signed words at r~215)
dot_offsets:
        dw  215,   0,  200,  75,  161, 144,  107, 194
        dw   45, 211,  -21, 214,  -86, 197, -144, 161
        dw -194, 107, -214,  45, -211, -21, -197, -86
        dw -161,-144, -107,-194,  -45,-211,   21,-214
        dw   86,-197,  144,-161,  194,-107,  214, -45
        dw  211,  21,  197,  86,  161, 144,  107, 194
        dw   45, 211,  -21, 214,  -86, 197, -144, 161
        dw -194, 107, -214,  45,  -45,-211,   21,-214

; Variables for action_loop mouse tracking
tmp_mx  dd 0
tmp_my  dd 0

; msg_colour for log system
msg_colour dd 0

; Log line byte buffer for itoa
log_line_buf times LOG_LINES * 4 dd 0

; Particle arrays
particle_x times NUM_PARTICLES dd 0
particle_y times NUM_PARTICLES dd 0

; Title animation state
title_anim_frame dd 0

; Missing action strings
str_vax_success  db 'VACCINATION DRIVE COMPLETE.', 0
str_no_vaccines  db 'NOT ENOUGH VACCINES.', 0
str_all_vaxxed   db 'ALL HEALTHY ARE ALREADY VACCINATED.', 0
str_no_healthy   db 'NO HEALTHY PEOPLE TO VACCINATE.', 0
str_treated      db 'TREATMENT ADMINISTERED.', 0
str_no_sick      db 'NO INFECTED TO TREAT.', 0
str_no_supplies  db 'NOT ENOUGH SUPPLIES.', 0
str_supply_risk  db 'SUPPLY RUN - RISK OF EXPOSURE.', 0
str_vax_and      db 'VACCINES +', 0
str_med_supplies db 'MEDICAL SUPPLIES RESTOCKED.', 0
str_hospital_built db 'HOSPITAL BUILT! REDUCES DEATHS.', 0
str_research_pts db 'RESEARCH ADVANCED.', 0

; Month names
str_month_jan db 'JANUARY', 0
str_month_feb db 'FEBRUARY', 0
str_month_mar db 'MARCH', 0
str_month_apr db 'APRIL', 0
str_month_may db 'MAY', 0
str_month_jun db 'JUNE', 0
str_month_jul db 'JULY', 0
str_month_aug db 'AUGUST', 0
str_month_sep db 'SEPTEMBER', 0
str_month_oct db 'OCTOBER', 0
str_month_nov db 'NOVEMBER', 0
str_month_dec db 'DECEMBER', 0

month_name_ptrs:
        dd str_month_jan, str_month_feb, str_month_mar, str_month_apr
        dd str_month_may, str_month_jun, str_month_jul, str_month_aug
        dd str_month_sep, str_month_oct, str_month_nov, str_month_dec

; Rating pointer (set at runtime)
rating_ptr dd 0

; Log buffer
log_head  dd 0
log_ptrs  times LOG_LINES dd 0
log_cols  times LOG_LINES dd 0

; Temp vars
msg_buf   times 16 db 0
_tmp_esi_save dd 0

; Decay constants (written by calc_difficulty)
_decay_vax dd 0
_decay_sup dd 0
_decay_mor dd 0

; Title animation frame counter
title_frame dd 0

;=======================================================================
; BSS (uninitialised)
;=======================================================================
rand_seed       dd 0
month           dd 0
population      dd 0
healthy         dd 0
vaccinated      dd 0
infected        dd 0
recovered       dd 0
dead            dd 0
vaccines        dd 0
supplies        dd 0
morale          dd 0
research        dd 0
actions_left    dd 0
difficulty      dd 0
total_vaccinated dd 0
total_treated   dd 0
outbreaks_survived dd 0
hs_name_ob       db "outbreak", 0
hospital_built  db 0
lab_built       db 0
preparedness    dd 0
threat_level    dd 0
event_type      dd 0
temp_val        dd 0
temp_val2       dd 0
stats_base_row  dd 0
set_vaccines    dd 0
set_supplies    dd 0
set_morale      dd 0
set_months      dd 0
set_diff        dd 0
