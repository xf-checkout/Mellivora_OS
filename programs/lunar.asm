; lunar.asm - Lunar Lander simulation for Mellivora OS
; VBE 1024x768x32bpp. Land the module safely (speed <= 5 m/s).
; Type thrust value + Enter each second. Q to quit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

; Physics constants (fixed-point, scaled by 1000)
GRAVITY_FP      equ 1620        ; 1.62 m/s² × 1000
THRUST_FP       equ 10000       ; 10 m/s² per unit × 1000
SAFE_SPEED      equ 5

COL_BG          equ 0x00080C14
COL_PANEL       equ 0x00101828
COL_WHITE       equ 0x00FFFFFF
COL_YELLOW      equ 0x00FFE040
COL_GREEN       equ 0x0033DD44
COL_RED         equ 0x00FF4444
COL_CYAN        equ 0x0044CCEE
COL_GRAY        equ 0x00888888
COL_GROUND      equ 0x00446633
COL_LANDER      equ 0x00AAAACC
COL_FLAME       equ 0x00FF8800

PANEL_X         equ 50
PANEL_Y         equ 50
PANEL_W         equ 500
PANEL_H         equ 550

LANDER_X        equ 700         ; lander graphic centre x
GROUND_Y        equ 680

start:
        VBE_GAME_INIT
        ; Load persistent safe-landings counter from /scores/lunar
        mov esi, hs_name_ln
        call hs_load
        mov [total_landings], eax
        call init_state
        call draw_all

.game_loop:
        ; Get line of input (blocking, reads digits + Enter)
        call read_thrust_input
        cmp dword [quit_flag], 1
        je .quit

        call update_physics

        ; Check landed?
        cmp dword [altitude], 0
        jle .landed

        call draw_all
        jmp .game_loop

.landed:
        ; Clamp altitude to 0
        mov dword [altitude], 0
        call draw_all
        call draw_result
.wait_exit:
        mov eax, SYS_READ_KEY
        int 0x80
        test eax, eax
        jz .wait_exit
        cmp al, 'q'
        je .quit
        ; New game
        call init_state
        call draw_all
        jmp .game_loop

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;--------------------------------------
init_state:
        mov dword [altitude],    10000
        mov dword [velocity_fp], 0
        mov dword [fuel],        5000
        mov dword [thrust],      0
        mov dword [time_elapsed],0
        mov dword [quit_flag],   0
        mov dword [input_val],   0
        mov dword [input_len],   0
        ret

;--------------------------------------
; read_thrust_input: blocking read of digits + Enter
; stores result in [thrust], sets quit_flag on Q
;--------------------------------------
read_thrust_input:
        mov dword [input_val], 0
        mov dword [input_len], 0
        call draw_all           ; refresh display (shows empty input)
.ri_loop:
        mov eax, SYS_READ_KEY
        int 0x80
        test eax, eax
        jz .ri_loop

        cmp al, 'q'
        je .ri_quit
        cmp al, 'Q'
        je .ri_quit
        cmp al, KEY_ESC
        je .ri_quit
        cmp al, 0x0D
        je .ri_done
        cmp al, 0x08
        je .ri_back
        cmp al, '0'
        jl .ri_loop
        cmp al, '9'
        jg .ri_loop
        cmp dword [input_len], 4
        jge .ri_loop

        sub al, '0'
        movzx eax, al
        push eax
        mov eax, [input_val]
        imul eax, 10
        pop ecx
        add eax, ecx
        mov [input_val], eax
        inc dword [input_len]
        call draw_all
        jmp .ri_loop

.ri_back:
        cmp dword [input_len], 0
        je .ri_loop
        xor edx, edx
        mov eax, [input_val]
        mov ebx, 10
        div ebx
        mov [input_val], eax
        dec dword [input_len]
        call draw_all
        jmp .ri_loop

.ri_done:
        ; Clamp thrust to available fuel
        mov eax, [input_val]
        cmp eax, [fuel]
        jle .ri_ok
        mov eax, [fuel]
.ri_ok:
        mov [thrust], eax
        ret

.ri_quit:
        mov dword [quit_flag], 1
        ret

;--------------------------------------
update_physics:
        ; velocity_fp += GRAVITY_FP
        mov eax, GRAVITY_FP
        add [velocity_fp], eax

        ; velocity_fp -= thrust * THRUST_FP / 1000
        mov eax, [thrust]
        imul eax, THRUST_FP
        mov ebx, 1000
        xor edx, edx
        div ebx
        sub [velocity_fp], eax

        ; Subtract fuel
        mov eax, [thrust]
        sub [fuel], eax
        jns .fuel_ok
        mov dword [fuel], 0
.fuel_ok:

        ; altitude -= velocity_fp / 1000
        mov eax, [velocity_fp]
        test eax, eax
        jns .v_pos
        neg eax
        xor edx, edx
        mov ebx, 1000
        div ebx
        neg eax
        jmp .v_done
.v_pos:
        xor edx, edx
        mov ebx, 1000
        div ebx
.v_done:
        sub [altitude], eax
        cmp dword [altitude], 0
        jge .alt_ok
        mov dword [altitude], 0
.alt_ok:

        inc dword [time_elapsed]
        ret

;--------------------------------------
draw_all:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; Panel background
        mov ebx, PANEL_X
        mov ecx, PANEL_Y
        mov edx, PANEL_W
        mov esi, PANEL_H
        mov edi, COL_PANEL
        call vbe_fill_rect

        ; Title
        mov ebx, PANEL_X + 130
        mov ecx, PANEL_Y + 20
        mov edx, msg_title
        mov esi, COL_YELLOW
        mov eax, 3
        call vbe_draw_str

        ; Stats
        mov ebx, PANEL_X + 20
        mov ecx, PANEL_Y + 80
        mov edx, msg_alt
        mov esi, COL_CYAN
        mov eax, 2
        call vbe_draw_str
        add ebx, 14 * 10
        mov edx, [altitude]
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_num

        mov ebx, PANEL_X + 20
        mov ecx, PANEL_Y + 120
        mov edx, msg_vel
        mov esi, COL_CYAN
        mov eax, 2
        call vbe_draw_str
        add ebx, 14 * 10
        mov eax, [velocity_fp]
        test eax, eax
        jns .vd_pos
        ; negative velocity → falling down, show red with "-"
        neg eax
        xor edx, edx
        mov ebx, 1000
        div ebx
        mov [.vtmp], eax
        mov ebx, PANEL_X + 20 + 14*10
        mov ecx, PANEL_Y + 120
        mov edx, msg_minus
        mov esi, COL_RED
        mov eax, 2
        call vbe_draw_str
        mov ebx, PANEL_X + 20 + 14*10 + 10
        mov edx, [.vtmp]
        mov esi, COL_RED
        mov eax, 2
        call vbe_draw_num
        jmp .vd_done
.vd_pos:
        xor edx, edx
        mov ebx, 1000
        div ebx
        mov [.vtmp], eax
        mov ebx, PANEL_X + 20 + 14*10
        mov edx, [.vtmp]
        mov esi, COL_GREEN
        mov eax, 2
        call vbe_draw_num
.vd_done:

        mov ebx, PANEL_X + 20
        mov ecx, PANEL_Y + 160
        mov edx, msg_fuel
        mov esi, COL_CYAN
        mov eax, 2
        call vbe_draw_str
        add ebx, 14 * 10
        mov edx, [fuel]
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_num

        mov ebx, PANEL_X + 20
        mov ecx, PANEL_Y + 200
        mov edx, msg_time
        mov esi, COL_CYAN
        mov eax, 2
        call vbe_draw_str
        add ebx, 14 * 10
        mov edx, [time_elapsed]
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_num

        ; Input field
        mov ebx, PANEL_X + 20
        mov ecx, PANEL_Y + 280
        mov edx, msg_thrust_lbl
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str

        mov ebx, PANEL_X + 20
        mov ecx, PANEL_Y + 320
        mov edx, 400
        mov esi, 50
        mov edi, 0x00223355
        call vbe_fill_rect

        cmp dword [input_len], 0
        jne .show_inp
        mov ebx, PANEL_X + 30
        mov ecx, PANEL_Y + 333
        mov edx, msg_zero
        mov esi, COL_GRAY
        mov eax, 2
        call vbe_draw_str
        jmp .after_inp
.show_inp:
        mov ebx, PANEL_X + 30
        mov ecx, PANEL_Y + 333
        mov edx, [input_val]
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_num
.after_inp:

        ; Hint
        mov ebx, PANEL_X + 20
        mov ecx, PANEL_Y + 390
        mov edx, msg_hint
        mov esi, COL_GRAY
        mov eax, 1
        call vbe_draw_str

        ; === Lander graphic (right side) ===
        ; Ground
        mov ebx, 600
        mov ecx, GROUND_Y
        mov edx, 424
        mov esi, 88
        mov edi, COL_GROUND
        call vbe_fill_rect

        ; Compute lander Y based on altitude (map 10000→100, 0→680)
        ; lander_py = GROUND_Y - 60 - altitude * 540 / 10000
        mov eax, [altitude]
        cmp eax, 10000
        jle .alt_clamp
        mov eax, 10000
.alt_clamp:
        imul eax, 540
        mov ebx, 10000
        xor edx, edx
        div ebx
        mov ecx, GROUND_Y - 60
        sub ecx, eax            ; lander top-left y

        ; Lander body
        mov ebx, LANDER_X - 20
        mov edx, 40
        mov esi, 30
        mov edi, COL_LANDER
        call vbe_fill_rect

        ; Flame if thrusting
        cmp dword [thrust], 0
        je .no_flame
        mov ebx, LANDER_X - 8
        mov ecx, ecx            ; ecx still = lander_y
        add ecx, 30
        mov edx, 16
        mov esi, 20
        mov edi, COL_FLAME
        call vbe_fill_rect
.no_flame:

        VBE_GAME_PRESENT
        popad
        ret

.vtmp: dd 0

;--------------------------------------
draw_result:
        pushad
        ; Compute final speed = |velocity_fp| / 1000
        mov eax, [velocity_fp]
        test eax, eax
        jns .r_pos
        neg eax
.r_pos:
        xor edx, edx
        mov ebx, 1000
        div ebx
        mov [final_speed], eax

        cmp eax, SAFE_SPEED
        jg .r_crash

        ; Safe landing — bump persistent landings, save, win SFX
        pushad
        mov eax, [total_landings]
        inc eax
        mov [total_landings], eax
        mov ebx, [total_landings]
        mov esi, hs_name_ln
        call hs_save
        call audio_sfx_win
        popad
        mov ebx, PANEL_X + 30
        mov ecx, PANEL_Y + 460
        mov edx, msg_safe
        mov esi, COL_GREEN
        mov eax, 3
        call vbe_draw_str
        jmp .r_show_speed

.r_crash:
        call audio_sfx_lose
        mov ebx, PANEL_X + 30
        mov ecx, PANEL_Y + 460
        mov edx, msg_crash
        mov esi, COL_RED
        mov eax, 3
        call vbe_draw_str

.r_show_speed:
        mov ebx, PANEL_X + 30
        mov ecx, PANEL_Y + 510
        mov edx, msg_impact
        mov esi, COL_WHITE
        mov eax, 2
        call vbe_draw_str
        add ebx, 15 * 10
        mov edx, [final_speed]
        call vbe_draw_num

        VBE_GAME_PRESENT
        popad
        ret

;=== Data ===
msg_title:      db "LUNAR LANDER", 0
msg_alt:        db "ALTITUDE (M):", 0
msg_vel:        db "VELOCITY M/S:", 0
msg_fuel:       db "FUEL UNITS:", 0
msg_time:       db "TIME SEC:", 0
msg_thrust_lbl: db "THRUST 0-100 THEN ENTER:", 0
msg_hint:       db "Q TO QUIT", 0
msg_zero:       db "0", 0
msg_minus:      db "-", 0
msg_safe:       db "SAFE LANDING!", 0
msg_crash:      db "CRASH!", 0
msg_impact:     db "IMPACT SPEED:", 0

altitude:       dd 10000
velocity_fp:    dd 0
fuel:           dd 5000
thrust:         dd 0
time_elapsed:   dd 0
final_speed:    dd 0
quit_flag:      dd 0
input_val:      dd 0
input_len:      dd 0
hs_name_ln:     db "lunar", 0
total_landings: dd 0
