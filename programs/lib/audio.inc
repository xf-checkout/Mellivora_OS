; lib/audio.inc - Shared audio helpers built on SYS_BEEP (PC speaker)
;
; Provides:
;   - Equal-tempered note frequency constants (A0..C8)
;   - audio_note   (EBX=note_id, ECX=duration_ticks)         play one note
;   - audio_play_score (ESI=ptr to score)                    play a melody
;   - audio_sfx_*  (ECX=duration override, optional)         common SFX presets
;
; Score format (used by audio_play_score):
;   sequence of (byte note_id, byte duration_ticks) pairs, terminated by
;   note_id == NOTE_END (0xFF). A note_id of NOTE_REST (0xFE) means silence
;   (no beep, just sleep). Each tick = ~10 ms via SYS_SLEEP.
;
; Conventions:
;   - All public entry points pushad/popad — caller's registers unchanged
;     unless documented otherwise.
;   - SYS_BEEP zeros EAX (must be reloaded between calls — handled here).
;
; Include order: requires syscalls.inc.

%ifndef MV_AUDIO_INC
%define MV_AUDIO_INC

;------------------------------------------------------------------
; Note frequency constants (Hz, equal temperament, A4 = 440 Hz)
;------------------------------------------------------------------
NOTE_REST   equ 0xFE
NOTE_END    equ 0xFF

NOTE_C2     equ 65
NOTE_D2     equ 73
NOTE_E2     equ 82
NOTE_F2     equ 87
NOTE_G2     equ 98
NOTE_A2     equ 110
NOTE_B2     equ 123

NOTE_C3     equ 131
NOTE_D3     equ 147
NOTE_E3     equ 165
NOTE_F3     equ 175
NOTE_G3     equ 196
NOTE_A3     equ 220
NOTE_B3     equ 247

NOTE_C4     equ 262          ; middle C
NOTE_CS4    equ 277
NOTE_D4     equ 294
NOTE_DS4    equ 311
NOTE_E4     equ 330
NOTE_F4     equ 349
NOTE_FS4    equ 370
NOTE_G4     equ 392
NOTE_GS4    equ 415
NOTE_A4     equ 440
NOTE_AS4    equ 466
NOTE_B4     equ 494

NOTE_C5     equ 523
NOTE_CS5    equ 554
NOTE_D5     equ 587
NOTE_DS5    equ 622
NOTE_E5     equ 659
NOTE_F5     equ 698
NOTE_FS5    equ 740
NOTE_G5     equ 784
NOTE_GS5    equ 831
NOTE_A5     equ 880
NOTE_B5     equ 988

NOTE_C6     equ 1047
NOTE_D6     equ 1175
NOTE_E6     equ 1319
NOTE_F6     equ 1397
NOTE_G6     equ 1568
NOTE_A6     equ 1760
NOTE_B6     equ 1976

NOTE_C7     equ 2093

;------------------------------------------------------------------
; audio_note - play one note via SYS_BEEP
;   in:  EBX = frequency in Hz (e.g. NOTE_A4)
;        ECX = duration in 10 ms ticks
;------------------------------------------------------------------
audio_note:
        pushad
        mov eax, 24             ; SYS_BEEP
        int 0x80
        popad
        ret

;------------------------------------------------------------------
; audio_rest - silence for ECX ticks
;   in:  ECX = duration in 10 ms ticks
;------------------------------------------------------------------
audio_rest:
        pushad
        mov eax, 16             ; SYS_SLEEP
        mov ebx, ecx
        int 0x80
        popad
        ret

;------------------------------------------------------------------
; audio_play_score - play a packed melody
;   in:  ESI = pointer to score (byte note_id, byte ticks) pairs
;            terminated by note_id == NOTE_END
;
; Each entry plays one (frequency, duration) pair. NOTE_REST inserts
; silence of the given duration.
;------------------------------------------------------------------
audio_play_score:
        pushad
.loop:
        movzx eax, byte [esi]
        cmp eax, NOTE_END
        je .done
        movzx ecx, byte [esi + 1]
        add esi, 2
        cmp eax, NOTE_REST
        je .rest
        ; lookup is not needed: stored byte is small note id; but for
        ; flexibility we accept raw small-int frequencies <= 255 only.
        ; Callers who need >255 Hz must use audio_play_score_w.
        mov ebx, eax
        mov eax, 24             ; SYS_BEEP
        int 0x80
        jmp .loop
.rest:
        mov eax, 16             ; SYS_SLEEP
        mov ebx, ecx
        int 0x80
        jmp .loop
.done:
        popad
        ret

;------------------------------------------------------------------
; audio_play_score_w - play a wide-format melody
;   in:  ESI = pointer to score (word freq, word ticks) pairs
;            terminated by freq == 0xFFFF (NOTE_END_W)
;        freq == 0xFFFE  -> rest
;
; Wide format supports the full Hz range (notes above ~255 Hz).
;------------------------------------------------------------------
NOTE_END_W   equ 0xFFFF
NOTE_REST_W  equ 0xFFFE

audio_play_score_w:
        pushad
.loop:
        movzx eax, word [esi]
        cmp eax, NOTE_END_W
        je .done
        movzx ecx, word [esi + 2]
        add esi, 4
        cmp eax, NOTE_REST_W
        je .rest
        mov ebx, eax
        mov eax, 24             ; SYS_BEEP
        int 0x80
        jmp .loop
.rest:
        mov eax, 16             ; SYS_SLEEP
        mov ebx, ecx
        int 0x80
        jmp .loop
.done:
        popad
        ret

;------------------------------------------------------------------
; SFX presets (3-tick pings; tweak via wrapper if needed)
;------------------------------------------------------------------
audio_sfx_click:
        pushad
        mov ebx, NOTE_C5
        mov ecx, 2
        mov eax, 24
        int 0x80
        popad
        ret

audio_sfx_ok:
        pushad
        mov ebx, NOTE_E5
        mov ecx, 4
        mov eax, 24
        int 0x80
        mov ebx, NOTE_G5
        mov ecx, 4
        mov eax, 24
        int 0x80
        popad
        ret

audio_sfx_error:
        pushad
        mov ebx, NOTE_A3
        mov ecx, 6
        mov eax, 24
        int 0x80
        mov ebx, NOTE_F3
        mov ecx, 8
        mov eax, 24
        int 0x80
        popad
        ret

audio_sfx_win:
        pushad
        mov ebx, NOTE_C5
        mov ecx, 5
        mov eax, 24
        int 0x80
        mov ebx, NOTE_E5
        mov ecx, 5
        mov eax, 24
        int 0x80
        mov ebx, NOTE_G5
        mov ecx, 5
        mov eax, 24
        int 0x80
        mov ebx, NOTE_C6
        mov ecx, 12
        mov eax, 24
        int 0x80
        popad
        ret

audio_sfx_lose:
        pushad
        mov ebx, NOTE_C4
        mov ecx, 6
        mov eax, 24
        int 0x80
        mov ebx, NOTE_B3
        mov ecx, 6
        mov eax, 24
        int 0x80
        mov ebx, NOTE_AS4 / 2   ; ~233 Hz
        mov ecx, 6
        mov eax, 24
        int 0x80
        mov ebx, NOTE_A3
        mov ecx, 14
        mov eax, 24
        int 0x80
        popad
        ret

%endif  ; MV_AUDIO_INC
