; lib/highscore.inc - Persistent high-score storage
;
; Each score is stored in /scores/<gamename> as a single 4-byte
; little-endian unsigned integer. The /scores directory is created
; on first write.
;
; Public entry points:
;   hs_load   (ESI=name) -> EAX=score (0 if file missing or unreadable)
;   hs_save   (ESI=name, EBX=score) -> EAX=0 ok / -1 err
;   hs_update (ESI=name, EBX=new) -> EAX=stored_high  (writes only if new > old)
;
; All routines preserve all caller registers via pushad/popad except
; the documented EAX return.
;
; Conventions:
;   - <name> must be a short alphanumeric string (e.g. "tetris"). Caller
;     supplies just the bare game name; the lib prefixes "/scores/".
;   - Path buffer is 64 bytes; names up to ~50 chars are safe.
;   - Requires syscalls.inc.

%ifndef MV_HIGHSCORE_INC
%define MV_HIGHSCORE_INC

HS_DIR_NAME     equ hs_dir_str

;-----------------------------------------------------------------------
; hs_load - load high score for a game
;   in:  ESI = bare game name (NUL-terminated)
;   out: EAX = stored score (0 if file missing or invalid)
;-----------------------------------------------------------------------
hs_load:
        push ebx
        push ecx
        push edx
        push esi
        push edi
        ; Build "/scores/<name>" into hs_path
        call hs_build_path
        ; Try to read 4 bytes via SYS_FREAD (reads whole file)
        mov dword [hs_value], 0
        mov eax, 30                     ; SYS_FREAD
        mov ebx, hs_path
        mov ecx, hs_value
        int 0x80
        cmp eax, 4
        jl .miss
        mov eax, [hs_value]
        jmp .done
.miss:
        xor eax, eax
.done:
        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

;-----------------------------------------------------------------------
; hs_save - unconditionally save a new high score
;   in:  ESI = name, EBX = score
;   out: EAX = 0 success / -1 failure
;-----------------------------------------------------------------------
hs_save:
        push ebx
        push ecx
        push edx
        push esi
        push edi
        push ebx                        ; preserve score (top of stack)
        ; Ensure /scores dir exists (best-effort, ignore EEXIST)
        mov eax, 12                     ; SYS_MKDIR
        mov ebx, hs_dir_str
        int 0x80
        ; Build path
        call hs_build_path
        ; Stage value
        pop ebx                         ; restore score
        mov [hs_value], ebx
        ; Write 4 bytes, type=0 (text/data)
        mov eax, 31                     ; SYS_FWRITE
        mov ebx, hs_path
        mov ecx, hs_value
        mov edx, 4
        xor esi, esi                    ; type=0
        int 0x80
        ; EAX is syscall return (0 / -1)
        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

;-----------------------------------------------------------------------
; hs_update - save only if new score > stored; return current high
;   in:  ESI = name, EBX = candidate score
;   out: EAX = stored high (after update)
;-----------------------------------------------------------------------
hs_update:
        push ebx
        push ecx
        push edx
        push esi
        push edi
        push ebx                        ; preserve candidate
        call hs_load                    ; EAX = old high
        pop ebx                         ; ebx = candidate
        cmp ebx, eax
        jbe .keep
        ; new > old: persist
        push eax
        call hs_save                    ; clobbers EAX (return code)
        pop eax
        mov eax, ebx                    ; reflect new high
        jmp .done
.keep:
        ; eax already has old high
.done:
        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

;-----------------------------------------------------------------------
; hs_build_path (internal) - build "/scores/<name>" into hs_path
;   in:  ESI = name (NUL-terminated)
;   trashes: EAX, EDI, ESI (caller pushed)
;-----------------------------------------------------------------------
hs_build_path:
        mov edi, hs_path
        ; Copy "/scores/" prefix (8 chars including slash)
        mov eax, '/sco'
        mov [edi], eax
        mov eax, 'res/'
        mov [edi + 4], eax
        add edi, 8
        ; Append name, capped at 48 chars
        mov ecx, 48
.copy:
        lodsb
        test al, al
        jz .term
        stosb
        loop .copy
.term:
        xor al, al
        stosb
        ret

; --- module-private storage (must be initialized so .bss is safe) ---
hs_dir_str:     db "/scores", 0
hs_path:        times 64 db 0
hs_value:       dd 0

%endif  ; MV_HIGHSCORE_INC
