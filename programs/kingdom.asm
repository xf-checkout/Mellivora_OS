;=======================================================================
; OUTPOST - A Space Colony Simulation (VBE Version)
; VBE 1024x768. Manage colonists, food, energy, territory over 10 years.
;=======================================================================

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

;-----------------------------------------------------------------------
; VBE Colors
;-----------------------------------------------------------------------
; Row Y coordinates for VBE layout (line height = 20px)
ROW0    equ 30
ROW1    equ 55
ROW2    equ 80
ROW3    equ 105
ROW4    equ 130
ROW5    equ 155
ROW6    equ 180
ROW7    equ 205
ROW8    equ 230
ROW9    equ 255
ROW10   equ 280
ROW11   equ 305
ROW12   equ 330
ROW13   equ 355
ROW14   equ 380
ROW15   equ 405
ROW16   equ 430
ROW17   equ 455
ROW18   equ 480
ROW19   equ 505
ROW20   equ 530
ROW21   equ 555
ROW22   equ 580
ROWMSG  equ 720
LX      equ 60      ; left margin X

COL_WHITE   equ 0x00EEEEEE
COL_YELLOW  equ 0x00FFDD44
COL_CYAN    equ 0x0044DDFF
COL_GREEN   equ 0x0044FF88
COL_RED     equ 0x00FF4444
COL_GRAY    equ 0x00AAAAAA
COL_LGRAY   equ 0x00CCCCCC
COL_DGRAY   equ 0x00666666
COL_MAGENTA equ 0x00FF44FF
COL_BG      equ 0x00111118

; Game parameters
START_POP       equ 100
START_FOOD      equ 2800
START_LAND      equ 1000
START_ENERGY    equ 500
MAX_YEARS       equ 10
FOOD_PER_PERSON equ 20          ; units of food per colonist per year
SEED_PER_HECTARE equ 2          ; food units needed to seed 1 hectare
HECTARES_PER_COLONIST equ 10    ; max hectares one colonist can farm
INPUT_MAX       equ 12

; Event IDs
EVT_NONE        equ 0
EVT_DUST_STORM  equ 1
EVT_PLAGUE      equ 2
EVT_SOLAR_FLARE equ 3
EVT_ARTIFACT    equ 4
EVT_BOUNTIFUL   equ 5
EVT_SUPPLY_SHIP equ 6
EVT_PESTS       equ 7
EVT_DISCOVERY   equ 8

;=======================================================================
; ENTRY POINT
;=======================================================================
start:
        VBE_GAME_INIT
        ; Seed PRNG from system time
        mov eax, SYS_GETTIME
        int 0x80
        mov [rand_seed], eax

        call show_title

.title_loop:
        mov eax, SYS_READ_KEY
        int 0x80
        cmp al, '1'
        je .start_game
        cmp al, '2'
        je .show_how
        cmp al, '3'
        je .quit
        cmp al, 27
        je .quit
        cmp al, 'q'
        je .quit
        cmp al, 'Q'
        je .quit
        jmp .title_loop

.show_how:
        call show_howto
        call show_title
        jmp .title_loop

.start_game:
        call init_game
        call show_intro
        jmp year_loop

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;=======================================================================
; TITLE SCREEN
;=======================================================================
show_title:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        mov ebx, 280
        mov ecx, 100
        mov edx, str_title1
        mov esi, COL_CYAN
        mov eax, 3
        call vbe_draw_str

        mov ebx, 240
        mov ecx, 160
        mov edx, str_title2
        mov esi, COL_LGRAY
        mov eax, 2
        call vbe_draw_str

        mov ebx, LX
        mov ecx, 250
        mov edx, str_menu1
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str

        mov ebx, LX
        mov ecx, 280
        mov edx, str_menu2
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str

        mov ebx, LX
        mov ecx, 310
        mov edx, str_menu3
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str

        mov ebx, LX
        mov ecx, 700
        mov edx, str_footer
        mov esi, COL_DGRAY
        mov eax, 1
        call vbe_draw_str

        mov eax, SYS_BEEP
        mov ebx, 330
        mov ecx, 3
        int 0x80
        mov eax, SYS_BEEP
        mov ebx, 440
        mov ecx, 3
        int 0x80
        mov eax, SYS_BEEP
        mov ebx, 554
        mov ecx, 5
        int 0x80

        VBE_GAME_PRESENT
        popad
        ret

;=======================================================================
; HOW TO PLAY
;=======================================================================
show_howto:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        mov ebx, 350
        mov ecx, ROW0
        mov edx, str_howto_title
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW2
        mov edx, ht1
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW3
        mov edx, ht2
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW4
        mov edx, ht4
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW5
        mov edx, ht6
        mov esi, COL_CYAN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW6
        mov edx, ht7
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW7
        mov edx, ht9
        mov esi, COL_CYAN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW8
        mov edx, ht10
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW9
        mov edx, ht12
        mov esi, COL_CYAN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW10
        mov edx, ht13
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW11
        mov edx, ht14
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW13
        mov edx, ht16
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW14
        mov edx, ht17
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROWMSG
        mov edx, str_press_key
        mov esi, COL_DGRAY
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT

        mov eax, SYS_READ_KEY
        int 0x80

        popad
        ret

;=======================================================================
; INTRO
;=======================================================================
show_intro:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        mov ebx, LX
        mov ecx, ROW1
        mov edx, intro2
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW3
        mov edx, intro4
        mov esi, COL_CYAN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW4
        mov edx, intro5
        mov esi, COL_CYAN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW5
        mov edx, intro6
        mov esi, COL_CYAN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW7
        mov edx, intro8
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW8
        mov edx, intro9
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW10
        mov edx, intro11
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW11
        mov edx, intro12
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        mov eax, SYS_BEEP
        mov ebx, 440
        mov ecx, 5
        int 0x80

        mov ebx, LX
        mov ecx, ROWMSG
        mov edx, str_press_begin
        mov esi, COL_YELLOW
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT
        mov eax, SYS_READ_KEY
        int 0x80

        popad
        ret

;=======================================================================
; GAME INITIALIZATION
;=======================================================================
init_game:
        pushad
        mov dword [population], START_POP
        mov dword [food], START_FOOD
        mov dword [land], START_LAND
        mov dword [energy], START_ENERGY
        mov dword [year], 1
        mov dword [total_starved], 0
        mov dword [total_immigrants], 0
        mov dword [max_starved_pct], 0
        mov dword [land_price], 20
        mov dword [harvest_yield], 3
        mov dword [plague_flag], 0
        popad
        ret

;=======================================================================
; MAIN YEAR LOOP
;=======================================================================
year_loop:
        ; Check if game is over
        mov eax, [year]
        cmp eax, MAX_YEARS + 1
        jg game_over_good

        ; Check if colony collapsed
        cmp dword [population], 0
        jle game_over_dead

        ; Generate new land price (17-28 food per hectare)
        call random
        xor edx, edx
        mov ebx, 12
        div ebx
        add edx, 17
        mov [land_price], edx

        ; Show status report
        call show_status

        ; --- Decision Phase ---
        ; 1. Buy/Sell land
        call phase_land

        ; 2. Feed colonists
        call phase_feed

        ; 3. Plant crops
        call phase_plant

        ; --- Simulation Phase ---
        call simulate_year

        ; Advance year
        inc dword [year]
        jmp year_loop

;=======================================================================
; STATUS REPORT
;=======================================================================
show_status:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Header bar
        mov ebx, 0
        mov ecx, 0
        mov edx, 1024
        mov esi, 22
        mov edi, 0x00224466
        call vbe_fill_rect

        mov ebx, 10
        mov ecx, 4
        mov edx, str_outpost
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_str

        mov ebx, 700
        mov ecx, 4
        mov edx, str_year_lbl
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        mov ebx, 730
        mov ecx, 4
        mov edx, [year]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        mov ebx, 742
        mov ecx, 4
        mov edx, str_of_ten
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        ; Section header
        mov ebx, LX
        mov ecx, ROW0
        mov edx, str_status_hdr
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str

        ; Population
        mov ebx, LX
        mov ecx, ROW2
        mov edx, str_pop_lbl
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 130
        mov ecx, ROW2
        mov edx, [population]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        ; Food
        mov ebx, LX
        mov ecx, ROW3
        mov edx, str_food_lbl
        mov esi, COL_YELLOW
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 130
        mov ecx, ROW3
        mov edx, [food]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        ; Land
        mov ebx, LX
        mov ecx, ROW4
        mov edx, str_land_lbl
        mov esi, 0x00AA8844
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 130
        mov ecx, ROW4
        mov edx, [land]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        ; Energy
        mov ebx, LX
        mov ecx, ROW5
        mov edx, str_energy_lbl
        mov esi, COL_CYAN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 130
        mov ecx, ROW5
        mov edx, [energy]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        ; Land price
        mov ebx, LX
        mov ecx, ROW7
        mov edx, str_price_lbl
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 130
        mov ecx, ROW7
        mov edx, [land_price]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 160
        mov ecx, ROW7
        mov edx, str_food_per_ha
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str

        ; Last event message
        cmp dword [last_event], EVT_NONE
        je .no_event_msg
        mov eax, [last_event]
        imul eax, 4
        mov edx, [event_msg_table + eax]
        cmp edx, 0
        je .no_event_msg
        mov ebx, LX
        mov ecx, ROW9
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
.no_event_msg:

        ; Starvation/immigration from last year
        cmp dword [year], 1
        je .skip_last_year
        cmp dword [last_starved], 0
        je .no_starved_msg
        mov ebx, LX
        mov ecx, ROW11
        mov edx, str_starved_pre
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 80
        mov ecx, ROW11
        mov edx, [last_starved]
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 110
        mov ecx, ROW11
        mov edx, str_starved_suf
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
.no_starved_msg:
        cmp dword [last_immigrants], 0
        je .no_immig_msg
        mov ebx, LX
        mov ecx, ROW12
        mov edx, str_immig_pre
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 50
        mov ecx, ROW12
        mov edx, [last_immigrants]
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 80
        mov ecx, ROW12
        mov edx, str_immig_suf
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_str
.no_immig_msg:
.skip_last_year:

        mov ebx, LX
        mov ecx, ROWMSG
        mov edx, str_press_key
        mov esi, COL_DGRAY
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT
        mov eax, SYS_READ_KEY
        int 0x80

        popad
        ret

;---------------------------------------
; draw_mini_bar - not used in VBE (kept as stub)
;---------------------------------------
draw_mini_bar:
        ret


; PHASE 1: BUY/SELL LAND
;=======================================================================
phase_land:
        pushad

.pl_render:
        mov edx, COL_BG
        call vbe_clear_screen

        call draw_phase_header

        mov ebx, LX
        mov ecx, ROW0
        mov edx, str_phase_land
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW2
        mov edx, str_you_have
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 60
        mov ecx, ROW2
        mov edx, [land]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 95
        mov ecx, ROW2
        mov edx, str_hectares_and
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 220
        mov ecx, ROW2
        mov edx, [food]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 260
        mov ecx, ROW2
        mov edx, str_food_stored
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW3
        mov edx, str_land_costs
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 75
        mov ecx, ROW3
        mov edx, [land_price]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 100
        mov ecx, ROW3
        mov edx, str_food_per_ha2
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW5
        mov edx, str_buy_land
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT

        mov dword [rn_py], ROW5
        call read_number
        mov [tmp_val], eax

        cmp eax, 0
        je .pl_ask_sell

        mov ebx, [land_price]
        imul eax, ebx
        cmp eax, [food]
        jle .pl_buy_ok

        ; Error: can't afford
        mov dword [.pl_err], 1
        mov ebx, LX
        mov ecx, ROW7
        mov edx, str_cant_afford
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
        VBE_GAME_PRESENT
        mov eax, SYS_BEEP
        mov ebx, 200
        mov ecx, 2
        int 0x80
        jmp .pl_render

.pl_buy_ok:
        mov eax, [tmp_val]
        add [land], eax
        mov ebx, [land_price]
        imul eax, ebx
        sub [food], eax
        mov eax, SYS_BEEP
        mov ebx, 800
        mov ecx, 2
        int 0x80
        jmp .land_done

.pl_ask_sell:
        ; Re-render with sell prompt
        mov edx, COL_BG
        call vbe_clear_screen
        call draw_phase_header
        mov ebx, LX
        mov ecx, ROW0
        mov edx, str_phase_land
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str
        mov ebx, LX
        mov ecx, ROW2
        mov edx, str_sell_land
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_str
        VBE_GAME_PRESENT

        mov dword [rn_py], ROW2
        call read_number
        cmp eax, 0
        je .land_done

        mov ebx, [land]
        dec ebx
        cmp eax, ebx
        jle .pl_sell_ok

        mov ebx, LX
        mov ecx, ROW4
        mov edx, str_not_enough_land
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
        VBE_GAME_PRESENT
        mov eax, SYS_BEEP
        mov ebx, 200
        mov ecx, 2
        int 0x80
        jmp .pl_ask_sell

.pl_sell_ok:
        sub [land], eax
        mov ebx, [land_price]
        imul eax, ebx
        add [food], eax
        mov eax, SYS_BEEP
        mov ebx, 800
        mov ecx, 2
        int 0x80

.land_done:
        popad
        ret

.pl_err: dd 0

;=======================================================================
; PHASE 2: FEED COLONISTS
;=======================================================================
phase_feed:
        pushad

.pf_render:
        mov edx, COL_BG
        call vbe_clear_screen
        call draw_phase_header

        mov ebx, LX
        mov ecx, ROW0
        mov edx, str_phase_feed
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW2
        mov edx, str_pop_is
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 80
        mov ecx, ROW2
        mov edx, [population]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 115
        mov ecx, ROW2
        mov edx, str_need
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        ; min food needed
        mov eax, [population]
        imul eax, FOOD_PER_PERSON
        mov ebx, LX + 220
        mov ecx, ROW2
        mov edx, eax
        mov esi, COL_YELLOW
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 260
        mov ecx, ROW2
        mov edx, str_food_min
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW3
        mov edx, str_food_avail
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 105
        mov ecx, ROW3
        mov edx, [food]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        mov ebx, LX
        mov ecx, ROW5
        mov edx, str_feed_how
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT

        mov dword [rn_py], ROW5
        call read_number
        mov [food_fed], eax

        cmp eax, [food]
        jle .pf_ok

        mov ebx, LX
        mov ecx, ROW7
        mov edx, str_not_enough_food
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
        VBE_GAME_PRESENT
        mov eax, SYS_BEEP
        mov ebx, 200
        mov ecx, 2
        int 0x80
        jmp .pf_render

.pf_ok:
        mov eax, [food_fed]
        sub [food], eax
        mov eax, SYS_BEEP
        mov ebx, 600
        mov ecx, 2
        int 0x80

        popad
        ret

;=======================================================================
; PHASE 3: PLANT CROPS
;=======================================================================
phase_plant:
        pushad

.pp_render:
        mov edx, COL_BG
        call vbe_clear_screen
        call draw_phase_header

        mov ebx, LX
        mov ecx, ROW0
        mov edx, str_phase_plant
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str

        ; Max by food
        mov eax, [food]
        xor edx, edx
        mov ebx, SEED_PER_HECTARE
        div ebx
        mov [tmp_val], eax

        ; Max by labor
        mov eax, [population]
        imul eax, HECTARES_PER_COLONIST
        cmp eax, [tmp_val]
        jge .pp_food_limit
        mov [tmp_val], eax
.pp_food_limit:
        ; Max by land
        mov eax, [land]
        cmp eax, [tmp_val]
        jge .pp_show
        mov [tmp_val], eax
.pp_show:

        mov ebx, LX
        mov ecx, ROW2
        mov edx, str_land_avail
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 110
        mov ecx, ROW2
        mov edx, [land]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        mov ebx, LX
        mov ecx, ROW3
        mov edx, str_seed_avail
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov eax, [food]
        xor edx, edx
        mov ebx, SEED_PER_HECTARE
        div ebx
        mov ebx, LX + 110
        mov ecx, ROW3
        mov edx, eax
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        mov ebx, LX
        mov ecx, ROW4
        mov edx, str_labor_avail
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov eax, [population]
        imul eax, HECTARES_PER_COLONIST
        mov ebx, LX + 110
        mov ecx, ROW4
        mov edx, eax
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        mov ebx, LX
        mov ecx, ROW5
        mov edx, str_max_plant
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 120
        mov ecx, ROW5
        mov edx, [tmp_val]
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_num

        mov ebx, LX
        mov ecx, ROW7
        mov edx, str_plant_how
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT

        mov dword [rn_py], ROW7
        call read_number
        mov [acres_planted], eax

        cmp eax, [tmp_val]
        jle .pp_ok

        mov ebx, LX
        mov ecx, ROW9
        mov edx, str_too_many_plant
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
        VBE_GAME_PRESENT
        mov eax, SYS_BEEP
        mov ebx, 200
        mov ecx, 2
        int 0x80
        jmp .pp_render

.pp_ok:
        mov eax, [acres_planted]
        imul eax, SEED_PER_HECTARE
        sub [food], eax
        mov eax, SYS_BEEP
        mov ebx, 700
        mov ecx, 2
        int 0x80

        popad
        ret

;=======================================================================
; SIMULATE YEAR
;=======================================================================
;=======================================================================
simulate_year:
        pushad

        ; --- Harvest ---
        ; Yield = 1-6 food per hectare planted
        call random
        xor edx, edx
        mov ebx, 6
        div ebx
        inc edx                 ; 1-6
        mov [harvest_yield], edx

        mov eax, [acres_planted]
        imul eax, edx
        mov [harvest_amount], eax
        add [food], eax

        ; --- Random Event ---
        call random_event

        ; --- Calculate starvation ---
        ; People fed = food_fed / FOOD_PER_PERSON
        mov eax, [food_fed]
        xor edx, edx
        mov ebx, FOOD_PER_PERSON
        div ebx                 ; eax = people fully fed
        mov ecx, eax

        ; Starved = population - people_fed (if negative, = 0)
        mov eax, [population]
        sub eax, ecx
        cmp eax, 0
        jg .some_starved
        xor eax, eax
.some_starved:
        mov [last_starved], eax
        add [total_starved], eax

        ; Calculate starvation percentage for catastrophe check
        cmp dword [population], 0
        je .skip_pct
        push eax
        imul eax, 100
        xor edx, edx
        mov ebx, [population]
        div ebx                 ; eax = pct starved
        cmp eax, [max_starved_pct]
        jle .pct_not_max
        mov [max_starved_pct], eax
.pct_not_max:
        pop eax

        ; If > 45% starve in one year, people revolt
        cmp eax, 0
        je .skip_pct
        push eax
        imul eax, 100
        xor edx, edx
        mov ebx, [population]
        div ebx
        pop eax                 ; restore starved count (not pct)
        cmp eax, 45
        jl .skip_pct
        ; Revolt! (handled later, just flag)
.skip_pct:

        ; Remove dead
        mov eax, [last_starved]
        sub [population], eax
        cmp dword [population], 0
        jge .pop_ok
        mov dword [population], 0
.pop_ok:

        ; --- Immigration ---
        ; Immigrants attracted by prosperity
        ; immigrants = (20 * land + food) / (100 * population + 1)
        ; Simplified: random 0-10 if well-fed, 0 if starving
        cmp dword [last_starved], 0
        jne .no_immigrants

        call random
        xor edx, edx
        mov ebx, 15
        div ebx
        inc edx                 ; 1-15
        ; Scale by land availability
        mov eax, edx
        cmp eax, 10
        jle .immig_ok
        mov eax, 10
.immig_ok:
        mov [last_immigrants], eax
        add [population], eax
        add [total_immigrants], eax
        jmp .immig_done

.no_immigrants:
        mov dword [last_immigrants], 0
.immig_done:

        ; --- Plague check (5% chance) ---
        mov dword [plague_flag], 0
        call random
        xor edx, edx
        mov ebx, 20
        div ebx
        cmp edx, 0
        jne .no_plague
        ; Plague: kill half the population
        mov eax, [population]
        shr eax, 1
        sub [population], eax
        mov dword [plague_flag], 1
        cmp dword [population], 0
        jge .no_plague
        mov dword [population], 0
.no_plague:

        ; --- Energy generation ---
        ; Energy from solar: gain 50-150 per year
        call random
        xor edx, edx
        mov ebx, 100
        div ebx
        add edx, 50
        add [energy], edx

        ; --- Show year results ---
        call show_year_results

        popad
        ret

;=======================================================================
; RANDOM EVENTS
;=======================================================================
random_event:
        pushad

        ; 40% chance of an event
        call random
        xor edx, edx
        mov ebx, 10
        div ebx
        cmp edx, 3             ; 0,1,2,3 = event (40%)
        jg .no_event

        ; Pick event type (1-8)
        call random
        xor edx, edx
        mov ebx, 8
        div ebx
        inc edx                 ; 1-8
        mov [last_event], edx

        ; Apply event effects
        cmp edx, EVT_DUST_STORM
        je .evt_dust
        cmp edx, EVT_PLAGUE
        je .evt_plague
        cmp edx, EVT_SOLAR_FLARE
        je .evt_flare
        cmp edx, EVT_ARTIFACT
        je .evt_artifact
        cmp edx, EVT_BOUNTIFUL
        je .evt_bountiful
        cmp edx, EVT_SUPPLY_SHIP
        je .evt_supply
        cmp edx, EVT_PESTS
        je .evt_pests
        cmp edx, EVT_DISCOVERY
        je .evt_discovery
        jmp .no_event

.evt_dust:
        ; Dust storm: destroy 10-30% of planted crops
        mov eax, [acres_planted]
        shr eax, 2             ; ~25%
        sub [acres_planted], eax
        cmp dword [acres_planted], 0
        jge .evt_done
        mov dword [acres_planted], 0
        jmp .evt_done

.evt_plague:
        ; Minor plague: lose 5-15% of food
        mov eax, [food]
        shr eax, 3             ; ~12.5%
        sub [food], eax
        cmp dword [food], 0
        jge .evt_done
        mov dword [food], 0
        jmp .evt_done

.evt_flare:
        ; Solar flare: lose 20% energy
        mov eax, [energy]
        shr eax, 2             ; 25%
        sub [energy], eax
        cmp dword [energy], 0
        jge .evt_done
        mov dword [energy], 0
        jmp .evt_done

.evt_artifact:
        ; Alien artifact: +200 energy
        add dword [energy], 200
        jmp .evt_done

.evt_bountiful:
        ; Bountiful season: +50% harvest (boost current year's already-computed harvest)
        mov eax, [harvest_amount]
        shr eax, 1
        add [food], eax
        add [harvest_amount], eax
        jmp .evt_done

.evt_supply:
        ; Supply ship arrives: +500 food, +10 people
        add dword [food], 500
        add dword [population], 10
        jmp .evt_done

.evt_pests:
        ; Alien pests eat food stores: lose 10%
        mov eax, [food]
        xor edx, edx
        mov ebx, 10
        div ebx
        sub [food], eax
        cmp dword [food], 0
        jge .evt_done
        mov dword [food], 0
        jmp .evt_done

.evt_discovery:
        ; Scientific discovery: +100 food from new technique
        add dword [food], 100
        jmp .evt_done

.no_event:
        mov dword [last_event], EVT_NONE
.evt_done:
        popad
        ret

;=======================================================================
; YEAR RESULTS SCREEN
;=======================================================================
show_year_results:
        pushad

        mov edx, COL_BG
        call vbe_clear_screen
        call draw_phase_header

        mov ebx, LX
        mov ecx, ROW0
        mov edx, str_results_hdr
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str

        ; Harvest row
        mov ebx, LX
        mov ecx, ROW2
        mov edx, str_harvested
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 80
        mov ecx, ROW2
        mov edx, [harvest_amount]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 115
        mov ecx, ROW2
        mov edx, str_food_from
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 190
        mov ecx, ROW2
        mov edx, [acres_planted]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 220
        mov ecx, ROW2
        mov edx, str_ha_at
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 255
        mov ecx, ROW2
        mov edx, [harvest_yield]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 275
        mov ecx, ROW2
        mov edx, str_per_ha
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        ; Event
        cmp dword [last_event], EVT_NONE
        je .res_no_event
        mov eax, [last_event]
        imul eax, 4
        mov edx, [event_msg_table + eax]
        test edx, edx
        jz .res_no_event
        mov ebx, LX
        mov ecx, ROW4
        mov esi, COL_MAGENTA
        mov eax, 1
        call vbe_draw_str
.res_no_event:

        ; Starvation
        mov dword [.row_y], ROW5
        cmp dword [last_starved], 0
        je .res_no_starve
        mov ebx, LX
        mov ecx, [.row_y]
        mov edx, str_starved_res
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 80
        mov ecx, [.row_y]
        mov edx, [last_starved]
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 110
        mov ecx, [.row_y]
        mov edx, str_colonists
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
        add dword [.row_y], 20
.res_no_starve:

        ; Immigration
        cmp dword [last_immigrants], 0
        je .res_no_immig
        mov ebx, LX
        mov ecx, [.row_y]
        mov edx, str_immig_res
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 50
        mov ecx, [.row_y]
        mov edx, [last_immigrants]
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 80
        mov ecx, [.row_y]
        mov edx, str_new_col
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_str
        add dword [.row_y], 20
.res_no_immig:

        ; Plague
        cmp dword [plague_flag], 0
        je .res_no_plague
        mov ebx, LX
        mov ecx, [.row_y]
        mov edx, str_plague_msg
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
        add dword [.row_y], 20
        mov eax, SYS_BEEP
        mov ebx, 150
        mov ecx, 5
        int 0x80
.res_no_plague:

        ; End stats
        add dword [.row_y], 10
        mov ecx, [.row_y]
        mov ebx, LX
        mov edx, str_end_pop
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 100
        mov edx, [population]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        add dword [.row_y], 20
        mov ecx, [.row_y]
        mov ebx, LX
        mov edx, str_end_food
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 100
        mov edx, [food]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        add dword [.row_y], 20
        mov ecx, [.row_y]
        mov ebx, LX
        mov edx, str_end_land
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 100
        mov edx, [land]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        add dword [.row_y], 20
        mov ecx, [.row_y]
        mov ebx, LX
        mov edx, str_end_energy
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 100
        mov edx, [energy]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        mov eax, SYS_BEEP
        mov ebx, 440
        mov ecx, 2
        int 0x80

        mov ebx, LX
        mov ecx, ROWMSG
        mov edx, str_press_key
        mov esi, COL_DGRAY
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT
        mov eax, SYS_READ_KEY
        int 0x80

        popad
        ret

.row_y: dd 0

;=======================================================================
; GAME OVER SCREENS
;=======================================================================
game_over_dead:
        call audio_sfx_lose
        mov edx, COL_BG
        call vbe_clear_screen

        mov eax, SYS_BEEP
        mov ebx, 200
        mov ecx, 4
        int 0x80
        mov eax, SYS_BEEP
        mov ebx, 150
        mov ecx, 4
        int 0x80
        mov eax, SYS_BEEP
        mov ebx, 100
        mov ecx, 8
        int 0x80

        mov ebx, LX
        mov ecx, ROW2
        mov edx, str_dead_title
        mov esi, COL_RED
        mov eax, 2
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW4
        mov edx, str_dead_text1
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW5
        mov edx, str_dead_text2
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW6
        mov edx, str_dead_text3
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW8
        mov edx, str_lasted
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_str
        mov eax, [year]
        dec eax
        mov ebx, LX + 90
        mov ecx, ROW8
        mov edx, eax
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num
        mov ebx, LX + 120
        mov ecx, ROW8
        mov edx, str_years
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW9
        mov edx, str_total_lost
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 120
        mov ecx, ROW9
        mov edx, [total_starved]
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_num

        jmp game_exit

game_over_good:
        ; Calculate score
        mov eax, [population]
        imul eax, 3
        mov [score], eax

        mov eax, [food]
        xor edx, edx
        mov ebx, 10
        div ebx
        add [score], eax

        mov eax, [land]
        xor edx, edx
        mov ebx, 10
        div ebx
        add [score], eax

        mov eax, [energy]
        xor edx, edx
        mov ebx, 5
        div ebx
        add [score], eax

        mov eax, [total_starved]
        imul eax, 5
        sub [score], eax
        cmp dword [score], 0
        jge .score_ok
        mov dword [score], 0
.score_ok:
        ; Persist best score (only if higher) + win SFX
        mov esi, hs_name_kd
        mov ebx, [score]
        call hs_update
        call audio_sfx_win

        ; Victory fanfare
        mov eax, SYS_BEEP
        mov ebx, 523
        mov ecx, 3
        int 0x80
        mov eax, SYS_BEEP
        mov ebx, 659
        mov ecx, 3
        int 0x80
        mov eax, SYS_BEEP
        mov ebx, 784
        mov ecx, 4
        int 0x80
        mov eax, SYS_BEEP
        mov ebx, 1047
        mov ecx, 6
        int 0x80

        mov edx, COL_BG
        call vbe_clear_screen

        mov ebx, LX
        mov ecx, ROW0
        mov edx, str_win_title
        mov esi, COL_GREEN
        mov eax, 2
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW3
        mov edx, str_win_text1
        mov esi, COL_CYAN
        mov eax, 1
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW4
        mov edx, str_win_text2
        mov esi, COL_CYAN
        mov eax, 1
        call vbe_draw_str

        mov ebx, LX
        mov ecx, ROW6
        mov edx, str_fin_pop
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 120
        mov ecx, ROW6
        mov edx, [population]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        mov ebx, LX
        mov ecx, ROW7
        mov edx, str_fin_food
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 120
        mov ecx, ROW7
        mov edx, [food]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        mov ebx, LX
        mov ecx, ROW8
        mov edx, str_fin_land
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 120
        mov ecx, ROW8
        mov edx, [land]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        mov ebx, LX
        mov ecx, ROW9
        mov edx, str_fin_energy
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 120
        mov ecx, ROW9
        mov edx, [energy]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        mov ebx, LX
        mov ecx, ROW10
        mov edx, str_fin_starved
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 120
        mov ecx, ROW10
        mov edx, [total_starved]
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_num

        mov ebx, LX
        mov ecx, ROW11
        mov edx, str_fin_immig
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_str
        mov ebx, LX + 120
        mov ecx, ROW11
        mov edx, [total_immigrants]
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_num

        mov ebx, LX
        mov ecx, ROW13
        mov edx, str_score_lbl
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_str
        mov ebx, LX + 70
        mov ecx, ROW13
        mov edx, [score]
        mov esi, COL_YELLOW
        mov eax, 2
        call vbe_draw_num

        ; Rating
        mov eax, [score]
        cmp eax, 800
        jge .r_legend
        cmp eax, 500
        jge .r_great
        cmp eax, 300
        jge .r_good
        cmp eax, 100
        jge .r_poor
        mov ebx, LX
        mov ecx, ROW15
        mov edx, str_rate_terrible
        mov esi, COL_RED
        mov eax, 1
        call vbe_draw_str
        jmp .r_done
.r_poor:
        mov ebx, LX
        mov ecx, ROW15
        mov edx, str_rate_poor
        mov esi, 0x00AA6622
        mov eax, 1
        call vbe_draw_str
        jmp .r_done
.r_good:
        mov ebx, LX
        mov ecx, ROW15
        mov edx, str_rate_good
        mov esi, COL_CYAN
        mov eax, 1
        call vbe_draw_str
        jmp .r_done
.r_great:
        mov ebx, LX
        mov ecx, ROW15
        mov edx, str_rate_great
        mov esi, COL_GREEN
        mov eax, 1
        call vbe_draw_str
        jmp .r_done
.r_legend:
        mov ebx, LX
        mov ecx, ROW15
        mov edx, str_rate_legend
        mov esi, COL_YELLOW
        mov eax, 1
        call vbe_draw_str
.r_done:

game_exit:
        mov ebx, LX
        mov ecx, ROWMSG
        mov edx, str_press_key
        mov esi, COL_DGRAY
        mov eax, 1
        call vbe_draw_str
        VBE_GAME_PRESENT
        mov eax, SYS_READ_KEY
        int 0x80

        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;=======================================================================
; UTILITY FUNCTIONS
;=======================================================================

;---------------------------------------
; UTILITY FUNCTIONS
;=======================================================================

;---------------------------------------
; draw_phase_header - Blue status band
;---------------------------------------
draw_phase_header:
        pushad
        ; Draw header band
        mov ebx, 0
        mov ecx, 0
        mov edx, 1024
        mov esi, 22
        mov edi, 0x00224466
        call vbe_fill_rect

        mov ebx, 10
        mov ecx, 4
        mov edx, str_outpost
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_str

        mov ebx, 700
        mov ecx, 4
        mov edx, str_year_lbl
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        mov ebx, 730
        mov ecx, 4
        mov edx, [year]
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_num

        mov ebx, 750
        mov ecx, 4
        mov edx, str_of_ten
        mov esi, COL_LGRAY
        mov eax, 1
        call vbe_draw_str

        popad
        ret

;---------------------------------------
; read_number - VBE input; return in EAX
; Draws typed digits at (rn_px, rn_py)
;---------------------------------------
read_number:
        pushad
        mov edi, input_buf
        xor ecx, ecx
        ; Clear input area
.rn_redraw:
        mov ebx, [rn_px]
        mov ecx, [rn_py]
        mov edx, 120
        mov esi, 12
        mov edi, COL_BG
        call vbe_fill_rect
        ; Draw current digits
        mov ebx, [rn_px]
        mov ecx, [rn_py]
        mov edx, input_buf
        mov esi, COL_WHITE
        mov eax, 1
        call vbe_draw_str
        ; Cursor bar
        mov eax, [rn_len]
        imul eax, 6
        add eax, [rn_px]
        mov ebx, eax
        mov ecx, [rn_py]
        mov edx, 5
        mov esi, 10
        mov edi, COL_WHITE
        call vbe_fill_rect
        VBE_GAME_PRESENT
        mov edi, input_buf

        mov eax, SYS_READ_KEY
        int 0x80

        cmp al, 0x0D
        je .rn_done
        cmp al, 0x0A
        je .rn_done
        cmp al, 0x08
        je .rn_bs
        cmp al, 0x7F
        je .rn_bs

        cmp al, '0'
        jb .rn_redraw
        cmp al, '9'
        ja .rn_redraw

        mov ecx, [rn_len]
        cmp ecx, INPUT_MAX - 1
        jge .rn_redraw

        mov [edi + ecx], al
        inc ecx
        mov byte [edi + ecx], 0
        mov [rn_len], ecx
        jmp .rn_redraw

.rn_bs:
        mov ecx, [rn_len]
        cmp ecx, 0
        je .rn_redraw
        dec ecx
        mov [rn_len], ecx
        mov byte [edi + ecx], 0
        jmp .rn_redraw

.rn_done:
        ; Parse input_buf to integer
        mov esi, input_buf
        xor eax, eax
        xor ebx, ebx
.rn_conv:
        movzx ebx, byte [esi]
        cmp bl, 0
        je .rn_conv_done
        cmp bl, '0'
        jb .rn_conv_done
        cmp bl, '9'
        ja .rn_conv_done
        imul eax, 10
        sub bl, '0'
        add eax, ebx
        inc esi
        jmp .rn_conv
.rn_conv_done:
        mov [tmp_result], eax
        ; Reset input
        xor ecx, ecx
        mov [rn_len], ecx
        mov byte [input_buf], 0
        popad
        mov eax, [tmp_result]
        ret

random:
        push ebx
        push edx
        mov eax, [rand_seed]
        imul eax, 1103515245
        add eax, 12345
        mov [rand_seed], eax
        shr eax, 16
        and eax, 0x7FFF
        pop edx
        pop ebx
        ret

;=======================================================================
; DATA SECTION
;=======================================================================

; === Title ===
str_border:     db "======================================================================", 0
str_title1:     db "O U T P O S T  :  K E P L E R", 0
str_title2:     db "A SPACE COLONY SIMULATION FOR MELLIVORA OS", 0
str_footer:     db "INSPIRED BY KINGDOM (1968)  |  A MELLIVORA PRODUCTION", 0

str_menu1:      db "[1] LAUNCH COLONY", 0
str_menu2:      db "[2] HOW TO PLAY", 0
str_menu3:      db "[3] ABORT MISSION", 0

; Planet art
p_art1: db "       .  *  .", 0
p_art2: db "    .  * (   ) *  .", 0
p_art3: db "   * ( KEPLER-442B )", 0
p_art4: db "    *  (       )  *", 0
p_art5: db "       '  *  '", 0
p_art6: db "      *       *", 0
p_art7: db "         * *", 0

planet_art: dd p_art1, p_art2, p_art3, p_art4, p_art5, p_art6, p_art7

; === How to Play ===
str_howto_title: db "=== HOW TO PLAY ===", 0

ht1:  db "YOU ARE THE COMMANDER OF HUMANITY'S FIRST COLONY ON KEPLER-442B.", 0
ht2:  db "YOUR MISSION: KEEP THE COLONY ALIVE FOR 10 YEARS.", 0
ht3:  db " ", 0
ht4:  db "EACH YEAR YOU MAKE THREE CRITICAL DECISIONS:", 0
ht5:  db " ", 0
ht6:  db "  1. LAND - BUY OR SELL COLONY TERRITORY (HECTARES).", 0
ht7:  db "     LAND PRICES FLUCTUATE EACH YEAR (17-28 FOOD/HECTARE).", 0
ht8:  db " ", 0
ht9:  db "  2. FOOD - FEED YOUR COLONISTS. EACH NEEDS 20 UNITS/YEAR.", 0
ht10: db "     IF YOU DON'T FEED ENOUGH, COLONISTS STARVE AND DIE.", 0
ht11: db " ", 0
ht12: db "  3. PLANT - ASSIGN HECTARES TO CROP PRODUCTION.", 0
ht13: db "     PLANTING COSTS 2 FOOD/HECTARE AS SEED. EACH COLONIST", 0
ht14: db "     CAN TEND UP TO 10 HECTARES. YIELD VARIES: 1-6 FOOD/HA.", 0
ht15: db " ", 0
ht16: db "RANDOM EVENTS -- DUST STORMS, PLAGUES, SUPPLY SHIPS, ALIEN", 0
ht17: db "ARTIFACTS -- WILL TEST YOUR LEADERSHIP. GOOD LUCK, COMMANDER.", 0
ht18: db " ", 0

howto_lines: dd ht1, ht2, ht3, ht4, ht5, ht6, ht7, ht8, ht9
             dd ht10, ht11, ht12, ht13, ht14, ht15, ht16, ht17, ht18

; === Intro ===
intro1:  db " ", 0
intro2:  db "MISSION LOG - KEPLER COLONY INITIATIVE", 0
intro3:  db " ", 0
intro4:  db "AFTER 87 YEARS IN CRYO-SLEEP, THE COLONY SHIP PERSEVERANCE", 0
intro5:  db "HAS REACHED KEPLER-442B -- A ROCKY WORLD WITH A BREATHABLE", 0
intro6:  db "ATMOSPHERE ORBITING A DISTANT ORANGE STAR.", 0
intro7:  db " ", 0
intro8:  db "YOU HAVE 100 COLONISTS, 2,800 UNITS OF FOOD,", 0
intro9:  db "1,000 HECTARES OF ARABLE LAND, AND 500 ENERGY CELLS.", 0
intro10: db " ", 0
intro11: db "THE COLONY MUST SURVIVE 10 YEARS UNTIL THE NEXT SUPPLY", 0
intro12: db "FLEET CAN REACH YOU. EVERY DECISION MATTERS, COMMANDER.", 0

intro_lines: dd intro1, intro2, intro3, intro4, intro5, intro6
             dd intro7, intro8, intro9, intro10, intro11, intro12

str_press_begin: db "PRESS ANY KEY TO BEGIN YEAR 1...", 0
str_press_key:   db "PRESS ANY KEY TO CONTINUE...", 0

; === Status Screen ===
str_outpost:    db "OUTPOST: KEPLER", 0
str_year_lbl:   db "YEAR ", 0
str_of_ten:     db "/10", 0
str_status_hdr: db "=== COLONY STATUS REPORT ===", 0
str_separator:  db "----------------------------------------------", 0

str_pop_lbl:    db "COLONISTS:  ", 0
str_food_lbl:   db "FOOD:       ", 0
str_land_lbl:   db "TERRITORY:  ", 0
str_energy_lbl: db "ENERGY:     ", 0
str_colonists:  db " COLONISTS", 0
str_units:      db " UNITS", 0
str_hectares:   db " HECTARES", 0
str_cells:      db " CELLS", 0
str_price_lbl:  db "LAND PRICE: ", 0
str_food_per_ha: db " FOOD PER HECTARE", 0

str_starved_pre: db "LAST YEAR, ", 0
str_starved_suf: db " COLONISTS STARVED.", 0
str_immig_pre:   db "  ", 0
str_immig_suf:   db " NEW COLONISTS ARRIVED FROM CRYO-PODS.", 0

; === Phase Prompts ===
str_phase_land:  db "=== PHASE 1: LAND MANAGEMENT ===", 0
str_phase_feed:  db "=== PHASE 2: FOOD DISTRIBUTION ===", 0
str_phase_plant: db "=== PHASE 3: CROP PLANTING ===", 0

str_you_have:       db "YOU HAVE ", 0
str_hectares_and:   db " HECTARES AND ", 0
str_food_stored:    db " UNITS OF FOOD IN STORAGE.", 0
str_land_costs:     db "LAND COSTS ", 0
str_food_per_ha2:   db " FOOD PER HECTARE THIS YEAR.", 0

str_buy_land:       db "HOW MANY HECTARES TO BUY? (0 = NONE): ", 0
str_sell_land:      db "HOW MANY HECTARES TO SELL? (0 = NONE): ", 0
str_cant_afford:    db "YOU CAN'T AFFORD THAT MUCH LAND!", 0
str_not_enough_land: db "YOU DON'T HAVE THAT MUCH LAND TO SELL!", 0

str_pop_is:         db "POPULATION: ", 0
str_need:           db ". THEY NEED AT LEAST ", 0
str_food_min:       db " FOOD UNITS.", 0
str_food_avail:     db "FOOD AVAILABLE: ", 0
str_feed_how:       db "HOW MANY FOOD UNITS TO DISTRIBUTE? ", 0
str_not_enough_food: db "YOU DON'T HAVE THAT MUCH FOOD!", 0

str_land_avail:     db "COLONY TERRITORY: ", 0
str_ha:             db " HA", 0
str_seed_avail:     db "SEED AVAILABLE FOR: ", 0
str_labor_avail:    db "LABOR CAPACITY: ", 0
str_max_plant:      db "MAXIMUM PLANTABLE: ", 0
str_plant_how:      db "HOW MANY HECTARES TO PLANT? ", 0
str_too_many_plant: db "YOU DON'T HAVE THE RESOURCES TO PLANT THAT MUCH!", 0

str_clear_line: db "                                                                  ", 0

; === Year Results ===
str_results_hdr: db "=== YEAR-END REPORT ===", 0
str_harvested:   db "HARVEST: ", 0
str_food_from:   db " FOOD FROM ", 0
str_ha_at:       db " HA (YIELD: ", 0
str_per_ha:      db "/HA)", 0
str_event_lbl:   db "EVENT: ", 0
str_starved_res: db "STARVATION: ", 0
str_immig_res:   db "IMMIGRATION: ", 0
str_new_col:     db " NEW COLONISTS ARRIVED.", 0
str_plague_msg:  db "A PLAGUE SWEPT THROUGH THE COLONY! HALF THE POPULATION WAS LOST.", 0

str_end_pop:     db "POPULATION: ", 0
str_end_food:    db "FOOD STORES: ", 0
str_end_land:    db "TERRITORY:   ", 0
str_end_energy:  db "ENERGY:      ", 0

; === Events ===
evt_msg_none:   db 0
evt_msg_dust:   db "A VIOLENT DUST STORM RAVAGED THE CROPLANDS!", 0
evt_msg_plague: db "A MYSTERIOUS ILLNESS SPREAD THROUGH THE FOOD STORES.", 0
evt_msg_flare:  db "A SOLAR FLARE DAMAGED THE COLONY'S POWER GRID!", 0
evt_msg_artifact: db "COLONISTS UNEARTHED AN ALIEN ENERGY ARTIFACT!", 0
evt_msg_bount:  db "IDEAL WEATHER CONDITIONS -- A BOUNTIFUL GROWING SEASON!", 0
evt_msg_supply: db "A SUPPLY SHIP ARRIVED WITH FOOD AND COLONISTS!", 0
evt_msg_pests:  db "ALIEN PESTS INFESTED THE FOOD STORAGE SILOS!", 0
evt_msg_disc:   db "SCIENTISTS DISCOVERED A NEW CROP CULTIVATION TECHNIQUE!", 0

event_msg_table:
        dd evt_msg_none, evt_msg_dust, evt_msg_plague, evt_msg_flare
        dd evt_msg_artifact, evt_msg_bount, evt_msg_supply, evt_msg_pests
        dd evt_msg_disc

; === Game Over ===
str_dead_title: db "*** COLONY LOST ***", 0
str_dead_text1: db "THE LAST COLONIST HAS PERISHED. THE DOMES STAND SILENT ON", 0
str_dead_text2: db "THE ALIEN PLAIN, SLOWLY BEING RECLAIMED BY KEPLER'S DUST.", 0
str_dead_text3: db "HUMANITY'S FIRST COLONY... HAS FAILED.", 0
str_lasted:     db "COLONY LASTED: ", 0
str_years:      db " YEARS.", 0
str_total_lost: db "TOTAL LIVES LOST: ", 0

str_win_title:  db "*** COLONY SURVIVED -- 10 YEARS COMPLETE ***", 0
str_win_text1:  db "THE SUPPLY FLEET'S SIGNAL CUTS THROUGH THE STATIC. YOU'VE DONE IT.", 0
str_win_text2:  db "KEPLER COLONY WILL ENDURE. HUMANITY HAS A NEW HOME AMONG THE STARS.", 0

str_fin_pop:     db "FINAL POPULATION:  ", 0
str_fin_food:    db "FOOD RESERVES:     ", 0
str_fin_land:    db "TERRITORY HELD:    ", 0
str_fin_energy:  db "ENERGY RESERVES:   ", 0
str_fin_starved: db "TOTAL LIVES LOST:  ", 0
str_fin_immig:   db "TOTAL IMMIGRANTS:  ", 0

str_score_lbl:   db "COLONY SCORE: ", 0
str_rate_terrible: db "RATING: FAILED STATE - THE COLONY BARELY SURVIVED.", 0
str_rate_poor:   db "RATING: STRUGGLING  - MANY SUFFERED UNDER YOUR COMMAND.", 0
str_rate_good:   db "RATING: ESTABLISHED - A SOLID FOUNDATION FOR THE FUTURE.", 0
str_rate_great:  db "RATING: THRIVING    - AN INSPIRING COLONY! WELL LED.", 0
str_rate_legend: db "RATING: LEGENDARY   - THEY WILL NAME CITIES AFTER YOU!", 0

;=======================================================================
; DATA (runtime variables - flat binary, no .bss)
;=======================================================================

rand_seed:          dd 0
population:         dd 0
food:               dd 0
land:               dd 0
energy:             dd 0
year:               dd 0
land_price:         dd 0
harvest_yield:      dd 0
harvest_amount:     dd 0
food_fed:           dd 0
acres_planted:      dd 0
last_starved:       dd 0
last_immigrants:    dd 0
last_event:         dd 0
total_starved:      dd 0
total_immigrants:   dd 0
max_starved_pct:    dd 0
plague_flag:        dd 0
score:              dd 0
hs_name_kd:         db "kingdom", 0
tmp_val:            dd 0
tmp_result:         dd 0
rn_px:              dd LX + 200
rn_py:              dd 0
rn_len:             dd 0
input_buf:          times INPUT_MAX db 0
