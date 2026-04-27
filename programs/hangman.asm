; hangman.asm - Hangman VBE graphics game for Mellivora OS
; Guess the hidden word one letter at a time.  6 wrong guesses = game over.

%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/highscore.inc"
%include "lib/audio.inc"

WORD_COUNT  equ 40
MAX_WORD    equ 20
MAX_WRONG   equ 6

COL_BG      equ 0x00101820
COL_GALLOWS equ 0x00CCAA66
COL_HEAD    equ 0x00FFCC88
COL_BODY    equ 0x00FFCC88
COL_TEXT    equ 0x00DDDDFF
COL_BLANK   equ 0x00AAAACC
COL_FOUND   equ 0x0088FFAA
COL_WRONG   equ 0x00FF6655
COL_WIN     equ 0x0044FF88
COL_LOSE    equ 0x00FF4444

; Gallows pixel anchors
GALL_BASE_X1 equ 60
GALL_BASE_X2 equ 260
GALL_BASE_Y  equ 420
GALL_POST_X  equ 120
GALL_ARM_Y   equ 80
GALL_ARM_X2  equ 220
GALL_HEAD_X  equ 220
GALL_HEAD_Y  equ 120
GALL_HEAD_R  equ 22
GALL_BODY_Y1 equ 142
GALL_BODY_Y2 equ 240
GALL_LARL_X  equ 220
GALL_LARM_X  equ 185
GALL_RARM_X  equ 255
GALL_ARM_Y2  equ 200
GALL_LLEGL_X equ 220
GALL_LLEG_X  equ 190
GALL_RLEG_X  equ 250
GALL_LEG_Y   equ 310

; Word area
WORD_X      equ 305
WORD_Y      equ 180
WORD_STEP   equ 28
ALPHA_X     equ 305
ALPHA_Y     equ 300

start:
        VBE_GAME_INIT
        ; Load total wins from disk
        push esi
        mov esi, hs_name_hm
        call hs_load
        mov [total_wins], eax
        pop esi
        call pick_word

.main_loop:
        call draw_scene
        VBE_GAME_PRESENT

        cmp byte [won], 1
        je  .end_check
        cmp byte [lost], 1
        je  .end_check
        jmp .poll_key
.end_check:
        ; Persist + SFX once per game-over transition
        cmp byte [result_played], 0
        jne .poll_end
        mov byte [result_played], 1
        cmp byte [won], 1
        jne .ec_lose
        inc dword [total_wins]
        push esi
        mov esi, hs_name_hm
        mov ebx, [total_wins]
        call hs_save
        pop esi
        call audio_sfx_win
        jmp .poll_end
.ec_lose:
        call audio_sfx_lose
        jmp .poll_end
.poll_key:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .main_loop
        cmp  eax, KEY_ESC
        je   .quit
        cmp  eax, KEY_Q
        je   .quit
        cmp  eax, 'Q'
        je   .quit
        ; map scancode → A-Z index (0-25)
        call scancode_to_letter     ; EAX=scancode → EAX=0-25 or -1
        cmp  eax, -1
        je   .main_loop
        ; check not already guessed
        cmp  byte [guessed + eax], 1
        je   .main_loop
        mov  byte [guessed + eax], 1
        call check_guess            ; EAX=letter index
        call check_win
        call check_lose
        jmp  .main_loop

.poll_end:
        VBE_GAME_POLL_KEY
        cmp  eax, -1
        je   .main_loop
        cmp  eax, KEY_ESC
        je   .quit
        cmp  eax, KEY_Q
        je   .quit
        cmp  eax, 'Q'
        je   .quit
        call pick_word
        jmp  .main_loop

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        mov eax, SYS_EXIT
        xor ebx, ebx
        int 0x80

;-----------------------------------------------------------
pick_word:
        pushad
        ; clear state
        mov  edi, guessed
        mov  ecx, 26
        xor  al,  al
        rep  stosb
        mov  edi, reveal
        mov  ecx, MAX_WORD
        xor  al,  al
        rep  stosb
        mov  byte [won],  0
        mov  byte [lost], 0
        mov  byte [wrong_count], 0
        mov  byte [result_played], 0
        ; pick word
        mov  eax, SYS_GETTIME
        int  0x80
        xor  edx, edx
        mov  ecx, WORD_COUNT
        div  ecx            ; edx = index
        imul edx, MAX_WORD
        add  edx, word_list
        mov  esi, edx
        mov  edi, cur_word
        mov  ecx, MAX_WORD
        rep  movsb
        ; compute word length (find first space or NUL)
        xor  ecx, ecx
.pw_len:
        cmp  ecx, MAX_WORD
        jge  .pw_ldone
        movzx eax, byte [cur_word + ecx]
        cmp  al, 0
        je   .pw_ldone
        cmp  al, ' '
        je   .pw_ldone
        inc  ecx
        jmp  .pw_len
.pw_ldone:
        mov  byte [word_len], cl
        popad
        ret

;-----------------------------------------------------------
; check_guess: EAX = letter index (0-25)
check_guess:
        pushad
        mov  [.cg_idx], eax
        add  eax, 'A'
        mov  [.cg_char], al
        ; scan word
        xor  ecx, ecx
        mov  bl, 0          ; found flag
.cg_scan:
        cmp  cl, [word_len]
        jge  .cg_done
        mov  al, [cur_word + ecx]
        cmp  al, [.cg_char]
        jne  .cg_next
        mov  byte [reveal + ecx], 1
        mov  bl, 1
.cg_next:
        inc  ecx
        jmp  .cg_scan
.cg_done:
        test bl, bl
        jnz  .cg_exit
        inc  byte [wrong_count]
.cg_exit:
        popad
        ret
.cg_idx:  db 0
.cg_char: db 0

;-----------------------------------------------------------
check_win:
        pushad
        xor  ecx, ecx
.cw_loop:
        cmp  cl, [word_len]
        jge  .cw_all
        cmp  byte [reveal + ecx], 0
        je   .cw_no
        inc  ecx
        jmp  .cw_loop
.cw_all:
        mov  byte [won], 1
        popad
        ret
.cw_no:
        popad
        ret

;-----------------------------------------------------------
check_lose:
        cmp  byte [wrong_count], MAX_WRONG
        jl   .cl_no
        mov  byte [lost], 1
.cl_no: ret

;-----------------------------------------------------------
; ascii_to_letter: EAX=ASCII key → EAX=0-25 (A-Z index) or -1
; SYS_READ_KEY returns lowercase ASCII for letter keys.
scancode_to_letter:
        cmp  eax, 'a'
        jl   .stl_none
        cmp  eax, 'z'
        jg   .stl_none
        sub  eax, 'a'           ; 0=A, 1=B, ..., 25=Z
        ret
.stl_none:
        mov  eax, -1
        ret

;-----------------------------------------------------------
draw_scene:
        pushad
        mov  edx, COL_BG
        call vbe_clear_screen

        ; Title
        mov  ebx, 220
        mov  ecx, 16
        mov  edx, str_title
        mov  esi, 0x00EEEEFF
        mov  eax, 2
        call vbe_draw_str

        ; Gallows frame (static)
        ; Base
        mov  ebx, GALL_BASE_X1
        mov  ecx, GALL_BASE_Y
        mov  edx, GALL_BASE_X2
        mov  esi, GALL_BASE_Y
        mov  edi, COL_GALLOWS
        call vbe_draw_line
        ; Post
        mov  ebx, GALL_POST_X
        mov  ecx, GALL_BASE_Y
        mov  edx, GALL_POST_X
        mov  esi, GALL_ARM_Y
        mov  edi, COL_GALLOWS
        call vbe_draw_line
        ; Arm
        mov  ebx, GALL_POST_X
        mov  ecx, GALL_ARM_Y
        mov  edx, GALL_ARM_X2
        mov  esi, GALL_ARM_Y
        mov  edi, COL_GALLOWS
        call vbe_draw_line
        ; Rope
        mov  ebx, GALL_ARM_X2
        mov  ecx, GALL_ARM_Y
        mov  edx, GALL_ARM_X2
        mov  esi, GALL_HEAD_Y - GALL_HEAD_R
        mov  edi, COL_GALLOWS
        call vbe_draw_line

        ; Body parts by wrong_count
        movzx eax, byte [wrong_count]
        cmp  eax, 0
        je   .ds_no_body

        ; 1 = head
        mov  ebx, GALL_HEAD_X
        mov  ecx, GALL_HEAD_Y
        mov  edx, GALL_HEAD_R
        mov  esi, COL_HEAD
        call vbe_draw_circle
        cmp  eax, 1
        je   .ds_no_body

        ; 2 = body
        mov  ebx, GALL_HEAD_X
        mov  ecx, GALL_BODY_Y1
        mov  edx, GALL_HEAD_X
        mov  esi, GALL_BODY_Y2
        mov  edi, COL_BODY
        call vbe_draw_line
        cmp  eax, 2
        je   .ds_no_body

        ; 3 = left arm
        mov  ebx, GALL_HEAD_X
        mov  ecx, GALL_BODY_Y1 + 20
        mov  edx, GALL_LARM_X
        mov  esi, GALL_ARM_Y2
        mov  edi, COL_BODY
        call vbe_draw_line
        cmp  eax, 3
        je   .ds_no_body

        ; 4 = right arm
        mov  ebx, GALL_HEAD_X
        mov  ecx, GALL_BODY_Y1 + 20
        mov  edx, GALL_RARM_X
        mov  esi, GALL_ARM_Y2
        mov  edi, COL_BODY
        call vbe_draw_line
        cmp  eax, 4
        je   .ds_no_body

        ; 5 = left leg
        mov  ebx, GALL_HEAD_X
        mov  ecx, GALL_BODY_Y2
        mov  edx, GALL_LLEG_X
        mov  esi, GALL_LEG_Y
        mov  edi, COL_BODY
        call vbe_draw_line
        cmp  eax, 5
        je   .ds_no_body

        ; 6 = right leg
        mov  ebx, GALL_HEAD_X
        mov  ecx, GALL_BODY_Y2
        mov  edx, GALL_RLEG_X
        mov  esi, GALL_LEG_Y
        mov  edi, COL_BODY
        call vbe_draw_line

.ds_no_body:

        ; Word blanks / letters
        movzx ecx, byte [word_len]
        xor   ebx, ebx
.ds_word:
        cmp   ebx, ecx
        jge   .ds_word_done
        ; x = WORD_X + ebx * WORD_STEP
        push  ebx
        push  ecx
        imul  eax, ebx, WORD_STEP
        add   eax, WORD_X
        ; Draw underscore at bottom of each slot
        push  eax
        add   eax, 2
        mov   [.ds_wx], eax
        mov   [.ds_wy], dword WORD_Y + 16
        mov   ebx, [.ds_wx]
        sub   ebx, 2
        mov   ecx, [.ds_wy]
        mov   edx, WORD_STEP - 6
        mov   esi, COL_BLANK
        call  vbe_draw_hline
        pop   eax
        mov   [.ds_wx], eax
        ; Check revealed
        pop   ecx
        pop   ebx
        push  ebx
        push  ecx
        cmp   byte [reveal + ebx], 0
        je    .ds_blank
        ; draw letter
        movzx edx, byte [cur_word + ebx]
        mov   ebx, [.ds_wx]
        mov   ecx, WORD_Y
        mov   esi, COL_FOUND
        mov   eax, 2
        call  vbe_draw_char
        jmp   .ds_wnext
.ds_blank:
        ; if lost, reveal
        cmp   byte [lost], 1
        jne   .ds_wnext
        movzx edx, byte [cur_word + ebx]
        mov   ebx, [.ds_wx]
        mov   ecx, WORD_Y
        mov   esi, COL_WRONG
        mov   eax, 2
        call  vbe_draw_char
.ds_wnext:
        pop   ecx
        pop   ebx
        inc   ebx
        jmp   .ds_word
.ds_word_done:

        ; Alphabet grid (2 rows: A-M, N-Z)
        xor   ecx, ecx          ; letter 0-25
.ds_alpha:
        cmp   ecx, 26
        jge   .ds_alpha_done
        push  ecx
        ; row 0 = letters 0-12, row 1 = 13-25
        mov   eax, ecx
        mov   edx, 0
        cmp   eax, 13
        jl    .ds_al_r0
        sub   eax, 13
        mov   edx, 1
.ds_al_r0:
        ; x = ALPHA_X + col * 22, y = ALPHA_Y + row * 26
        imul  eax, 22
        add   eax, ALPHA_X
        imul  edx, 26
        add   edx, ALPHA_Y
        mov   [.ds_ax], eax
        mov   [.ds_ay], edx
        pop   ecx
        push  ecx
        ; colour: guessed = dim, not guessed = bright
        cmp   byte [guessed + ecx], 1
        jne   .ds_al_bright
        mov   esi, 0x00444466
        jmp   .ds_al_draw
.ds_al_bright:
        mov   esi, COL_TEXT
.ds_al_draw:
        mov   edx, ecx
        add   edx, 'A'
        mov   ebx, [.ds_ax]
        mov   ecx, [.ds_ay]
        mov   eax, 1
        call  vbe_draw_char
        pop   ecx
        inc   ecx
        jmp   .ds_alpha
.ds_alpha_done:

        ; Wrong count — scale 2
        ; "WRONG  " (7 chars × 12px = 84px) then digit then " OF 6"
        mov   ebx, 305
        mov   ecx, 373
        mov   edx, str_wrong
        mov   esi, COL_TEXT
        mov   eax, 2
        call  vbe_draw_str
        movzx edx, byte [wrong_count]
        mov   ebx, 389
        mov   ecx, 373
        mov   esi, COL_WRONG
        mov   eax, 2
        call  vbe_draw_num
        mov   ebx, 401
        mov   ecx, 373
        mov   edx, str_of6
        mov   esi, COL_TEXT
        mov   eax, 2
        call  vbe_draw_str

        ; Total wins counter
        mov   ebx, 580
        mov   ecx, 60
        mov   edx, str_wins
        mov   esi, 0x00FFAA44
        mov   eax, 2
        call  vbe_draw_str
        mov   ebx, 660
        mov   ecx, 60
        mov   edx, [total_wins]
        mov   esi, 0x00FFAA44
        mov   eax, 2
        call  vbe_draw_num

        ; Win/Lose overlay
        cmp   byte [won], 1
        jne   .ds_check_lose
        mov   ebx, 225
        mov   ecx, 440
        mov   edx, str_you_win
        mov   esi, COL_WIN
        mov   eax, 2
        call  vbe_draw_str
        jmp   .ds_end
.ds_check_lose:
        cmp   byte [lost], 1
        jne   .ds_end
        mov   ebx, 200
        mov   ecx, 440
        mov   edx, str_you_lose
        mov   esi, COL_LOSE
        mov   eax, 2
        call  vbe_draw_str
.ds_end:
        popad
        ret

.ds_wx: dd 0
.ds_wy: dd 0
.ds_ax: dd 0
.ds_ay: dd 0

;-----------------------------------------------------------
; (sc_table removed — keys are now matched as ASCII lowercase letters)

str_title:    db "HANGMAN", 0
str_wrong:    db "WRONG  ", 0
str_of6:      db " OF 6", 0
str_wins:     db "WINS:", 0
str_you_win:  db "YOU WIN!", 0
str_you_lose: db "GAME OVER!", 0
hs_name_hm:   db "hangman", 0

cur_word:    times MAX_WORD db 0
word_len:    db 0
guessed:     times 26 db 0
reveal:      times MAX_WORD db 0
wrong_count: db 0
won:         db 0
lost:        db 0
result_played: db 0
total_wins:  dd 0

word_list:
        db "ALGORITHM           "
        db "ASSEMBLY            "
        db "BOOTSTRAP           "
        db "COMPILER            "
        db "DATABASE            "
        db "DEBUGGER            "
        db "ENCRYPT             "
        db "FACTORIAL           "
        db "GATEWAY             "
        db "HARDWARE            "
        db "INTERRUPT           "
        db "KERNEL              "
        db "LIBRARY             "
        db "MEMORY              "
        db "NETWORK             "
        db "OPCODE              "
        db "PIPELINE            "
        db "QUANTUM             "
        db "REGISTER            "
        db "SCHEDULER           "
        db "TERMINAL            "
        db "UNICODE             "
        db "VARIABLE            "
        db "WRAPPER             "
        db "XORSHIFT            "
        db "YIELDING            "
        db "ZEROING             "
        db "POINTER             "
        db "FUNCTION            "
        db "SEGMENT             "
        db "PROTOCOL            "
        db "CHECKSUM            "
        db "BITFIELD            "
        db "OVERFLOW            "
        db "SOCKET              "
        db "THREAD              "
        db "PROCESS             "
        db "VIRTUAL             "
        db "ENDIAN              "
        db "SEMAPHORE           "
