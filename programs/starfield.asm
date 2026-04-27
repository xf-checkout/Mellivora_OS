; starfield.asm - 3D Starfield Screensaver for Mellivora OS
; Classic flying-through-space effect with perspective projection.
; VBE 1024x768x32bpp. Press any key to exit.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"

NUM_STARS       equ 200
CENTER_X        equ 512
CENTER_Y        equ 384
SPEED           equ 4           ; Z decrease per frame
TICK_DELAY      equ 2           ; ~50fps
MAX_Z           equ 400
MIN_Z           equ 1

; colours
COL_BLACK       equ 0x00000000
COL_W0          equ 0x00FFFFFF   ; very close
COL_W1          equ 0x00CCCCCC   ; near
COL_W2          equ 0x00888888   ; mid
COL_W3          equ 0x00444444   ; far

start:
        VBE_GAME_INIT

        ; Seed random
        mov eax, SYS_GETTIME
        int 0x80
        mov [rand_state], eax

        ; Initialize stars
        xor esi, esi
.init_loop:
        cmp esi, NUM_STARS
        jge .init_done
        call init_star
        ; Also randomize initial Z for spread
        call rand
        xor edx, edx
        mov ecx, MAX_Z
        div ecx
        inc edx
        mov [star_z + esi*4], edx
        inc esi
        jmp .init_loop
.init_done:

;=== Main loop ===
.main_loop:
        ; Check for keypress
        VBE_GAME_POLL_KEY
        cmp eax, -1
        jne .exit

        ; Clear shadow buffer to black
        mov edx, COL_BLACK
        call vbe_clear_screen

        ; Update and draw each star
        xor esi, esi
.star_loop:
        cmp esi, NUM_STARS
        jge .star_frame_done

        ; Move star closer (decrease Z)
        mov eax, [star_z + esi*4]
        sub eax, SPEED
        cmp eax, MIN_Z
        jg .star_alive
        ; Respawn
        call init_star
        jmp .star_next

.star_alive:
        mov [star_z + esi*4], eax

        ; Project: screen_x = CENTER_X + (star_x * 512) / star_z
        mov eax, [star_x + esi*4]
        imul eax, 512
        cdq
        mov ecx, [star_z + esi*4]
        test ecx, ecx
        jz .star_next
        idiv ecx
        add eax, CENTER_X
        mov ebx, eax            ; ebx = screen_x

        ; Project: screen_y = CENTER_Y + (star_y * 512) / star_z
        mov eax, [star_y + esi*4]
        imul eax, 512
        cdq
        mov ecx, [star_z + esi*4]
        test ecx, ecx
        jz .star_next
        idiv ecx
        add eax, CENTER_Y
        mov ecx, eax            ; ecx = screen_y

        ; Bounds check (vbe_plot_pixel clips, but skip off-screen entirely)
        cmp ebx, 0
        jl .star_oob
        cmp ebx, 1023
        jg .star_oob
        cmp ecx, 0
        jl .star_oob
        cmp ecx, 767
        jg .star_oob

        ; Choose colour based on Z distance
        mov eax, [star_z + esi*4]
        cmp eax, 300
        jg .col_far
        cmp eax, 150
        jg .col_mid
        cmp eax, 60
        jg .col_near
        ; Very close — plot 2×2 block
        mov edx, COL_W0
        call vbe_plot_pixel
        push ebx
        push ecx
        inc ebx
        call vbe_plot_pixel
        pop ecx
        pop ebx
        push ecx
        inc ecx
        call vbe_plot_pixel
        inc ebx
        call vbe_plot_pixel
        pop ecx
        jmp .star_next
.col_near:
        mov edx, COL_W1
        call vbe_plot_pixel
        jmp .star_next
.col_mid:
        mov edx, COL_W2
        call vbe_plot_pixel
        jmp .star_next
.col_far:
        mov edx, COL_W3
        call vbe_plot_pixel
        jmp .star_next

.star_oob:
        call init_star

.star_next:
        inc esi
        jmp .star_loop

.star_frame_done:
        VBE_GAME_PRESENT
        ; Frame delay
        mov eax, SYS_SLEEP
        mov ebx, TICK_DELAY
        int 0x80
        jmp .main_loop

.exit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;---------------------------------------
; init_star - Initialize star[esi] with random position
;---------------------------------------
init_star:
        push eax
        push ecx
        push edx

        ; Random X: -400 to +400
        call rand
        xor edx, edx
        mov ecx, 801
        div ecx
        sub edx, 400
        mov [star_x + esi*4], edx

        ; Random Y: -300 to +300
        call rand
        xor edx, edx
        mov ecx, 601
        div ecx
        sub edx, 300
        mov [star_y + esi*4], edx

        ; Z starts at max
        mov dword [star_z + esi*4], MAX_Z

        pop edx
        pop ecx
        pop eax
        ret

;---------------------------------------
; rand - LCG PRNG -> EAX
;---------------------------------------
rand:
        mov eax, [rand_state]
        imul eax, 1103515245
        add eax, 12345
        mov [rand_state], eax
        shr eax, 16
        and eax, 0x7FFF
        ret

; === Data ===
rand_state:     dd 0
star_x:         times NUM_STARS dd 0
star_y:         times NUM_STARS dd 0
star_z:         times NUM_STARS dd 0
