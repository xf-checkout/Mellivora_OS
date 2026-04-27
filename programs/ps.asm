; ps.asm - Process Status Listing
; Shows all active tasks from the Mellivora scheduler.
; v6.5: 128-slot scan, expanded TCB (48 bytes), name + priority columns,
;       colored state, summary by state.
;
; Usage: ps

%include "syscalls.inc"

MAX_TASKS       equ 128

start:
        ; Header
        mov eax, SYS_SETCOLOR
        mov ebx, 0x0B           ; cyan
        int 0x80

        mov eax, SYS_PRINT
        mov ebx, hdr_line
        int 0x80

        mov eax, SYS_SETCOLOR
        mov ebx, 0x07           ; light grey
        int 0x80

        ; Reset counters
        mov dword [n_active],  0
        mov dword [n_ready],   0
        mov dword [n_running], 0
        mov dword [n_blocked], 0
        mov dword [n_stopped], 0
        mov dword [n_zombie],  0

        ; Iterate scheduler slots
        xor ebp, ebp            ; slot index

.loop:
        cmp ebp, MAX_TASKS
        jge .done

        mov eax, SYS_PROCLIST
        mov ebx, ebp
        mov ecx, task_info
        int 0x80

        cmp eax, -1
        je .next

        ; Skip free slots
        mov eax, [task_info]
        cmp eax, 0              ; TASK_FREE
        je .next

        inc dword [n_active]
        ; Bump per-state counter
        cmp eax, 1
        je .ct_ready
        cmp eax, 2
        je .ct_running
        cmp eax, 3
        je .ct_blocked
        cmp eax, 4
        je .ct_stopped
        cmp eax, 5
        je .ct_zombie
        jmp .ct_done
.ct_ready:    inc dword [n_ready]
              jmp .ct_done
.ct_running:  inc dword [n_running]
              jmp .ct_done
.ct_blocked:  inc dword [n_blocked]
              jmp .ct_done
.ct_stopped:  inc dword [n_stopped]
              jmp .ct_done
.ct_zombie:   inc dword [n_zombie]
.ct_done:

        ; SLOT (3-wide)
        mov eax, SYS_SETCOLOR
        mov ebx, 0x08
        int 0x80
        mov eax, ebp
        mov ecx, 3
        call print_padded_num

        ; PID (5-wide)
        mov eax, SYS_SETCOLOR
        mov ebx, 0x0F
        int 0x80
        mov eax, [task_info + 4]
        mov ecx, 5
        call print_padded_num

        ; PRIO (4-wide)
        mov eax, SYS_SETCOLOR
        mov ebx, 0x07
        int 0x80
        mov eax, [task_info + 16]
        mov ecx, 4
        call print_padded_num

        ; STATE (colored)
        call print_spaces2
        mov eax, [task_info]
        cmp eax, 1
        je .st_ready
        cmp eax, 2
        je .st_run
        cmp eax, 3
        je .st_blocked
        cmp eax, 4
        je .st_stopped
        cmp eax, 5
        je .st_zombie
        mov ebx, st_other
        mov ecx, 0x0E           ; yellow
        jmp .st_print
.st_ready:
        mov ebx, st_ready
        mov ecx, 0x0A
        jmp .st_print
.st_run:
        mov ebx, st_running
        mov ecx, 0x0F
        jmp .st_print
.st_blocked:
        mov ebx, st_blocked
        mov ecx, 0x09
        jmp .st_print
.st_stopped:
        mov ebx, st_stopped
        mov ecx, 0x0D
        jmp .st_print
.st_zombie:
        mov ebx, st_zombie
        mov ecx, 0x0C
.st_print:
        push ebx
        mov eax, SYS_SETCOLOR
        mov ebx, ecx
        int 0x80
        pop ebx
        mov eax, SYS_PRINT
        int 0x80

        ; ENTRY hex
        call print_spaces2
        mov eax, SYS_SETCOLOR
        mov ebx, 0x08
        int 0x80
        mov eax, [task_info + 8]
        call print_hex

        ; ESP hex
        call print_spaces2
        mov eax, [task_info + 12]
        call print_hex

        ; NAME (16 bytes at offset 32, NUL-terminated within)
        call print_spaces2
        mov eax, SYS_SETCOLOR
        mov ebx, 0x0E           ; yellow
        int 0x80
        mov eax, SYS_PRINT
        mov ebx, task_info + 32
        int 0x80

        ; Newline
        mov eax, SYS_PUTCHAR
        mov ebx, 10
        int 0x80

.next:
        inc ebp
        jmp .loop

.done:
        ; Restore color, summary
        mov eax, SYS_SETCOLOR
        mov ebx, 0x07
        int 0x80
        mov eax, SYS_PUTCHAR
        mov ebx, 10
        int 0x80

        mov eax, SYS_PRINT
        mov ebx, lbl_total
        int 0x80
        mov eax, [n_active]
        call print_decimal
        mov eax, SYS_PRINT
        mov ebx, lbl_running
        int 0x80
        mov eax, [n_running]
        call print_decimal
        mov eax, SYS_PRINT
        mov ebx, lbl_ready
        int 0x80
        mov eax, [n_ready]
        call print_decimal
        mov eax, SYS_PRINT
        mov ebx, lbl_blocked
        int 0x80
        mov eax, [n_blocked]
        call print_decimal
        mov eax, SYS_PRINT
        mov ebx, lbl_stopped
        int 0x80
        mov eax, [n_stopped]
        call print_decimal
        mov eax, SYS_PRINT
        mov ebx, lbl_zombie
        int 0x80
        mov eax, [n_zombie]
        call print_decimal
        mov eax, SYS_PUTCHAR
        mov ebx, 10
        int 0x80

        mov eax, SYS_EXIT
        xor ebx, ebx
        int 0x80

;---------------------------------------
print_spaces2:
        pushad
        mov eax, SYS_PRINT
        mov ebx, str_spaces
        int 0x80
        popad
        ret

;---------------------------------------
; print_padded_num - EAX value, ECX target width
;---------------------------------------
print_padded_num:
        pushad
        push ecx                ; save width
        mov ecx, 0
        push eax
        cmp eax, 0
        jne .ppn_count
        mov ecx, 1
        jmp .ppn_pad
.ppn_count:
        cmp eax, 0
        je .ppn_pad
        xor edx, edx
        mov ebx, 10
        div ebx
        inc ecx
        jmp .ppn_count
.ppn_pad:
        pop eax
        pop edx                 ; width
        sub edx, ecx
        jle .ppn_print
.ppn_sp:
        push eax
        push edx
        mov eax, SYS_PUTCHAR
        mov ebx, ' '
        int 0x80
        pop edx
        pop eax
        dec edx
        jg .ppn_sp
.ppn_print:
        call print_decimal
        popad
        ret

;---------------------------------------
print_decimal:
        pushad
        cmp eax, 0
        jne .pd_nz
        mov eax, SYS_PUTCHAR
        mov ebx, '0'
        int 0x80
        popad
        ret
.pd_nz:
        xor ecx, ecx
        mov ebx, 10
.pd_div:
        xor edx, edx
        div ebx
        push edx
        inc ecx
        cmp eax, 0
        jne .pd_div
.pd_out:
        pop ebx
        add ebx, '0'
        mov eax, SYS_PUTCHAR
        int 0x80
        dec ecx
        jnz .pd_out
        popad
        ret

;---------------------------------------
print_hex:
        pushad
        mov ecx, 8
        mov edx, eax
.ph_loop:
        rol edx, 4
        mov eax, edx
        and eax, 0x0F
        cmp eax, 10
        jl .ph_digit
        add eax, 'A' - 10
        jmp .ph_out
.ph_digit:
        add eax, '0'
.ph_out:
        push ecx
        push edx
        mov ebx, eax
        mov eax, SYS_PUTCHAR
        int 0x80
        pop edx
        pop ecx
        dec ecx
        jnz .ph_loop
        popad
        ret

;=======================================
hdr_line:       db "SLT   PID PRI  STATE     ENTRY     ESP       NAME", 10
                db "--- ----- ---  -------   --------  --------  ----", 10, 0
st_ready:       db "READY  ", 0
st_running:     db "RUNNING", 0
st_blocked:     db "BLOCKED", 0
st_stopped:     db "STOPPED", 0
st_zombie:      db "ZOMBIE ", 0
st_other:       db "OTHER  ", 0
str_spaces:     db "  ", 0

lbl_total:      db "Active: ", 0
lbl_running:    db "  Running: ", 0
lbl_ready:      db "  Ready: ", 0
lbl_blocked:    db "  Blocked: ", 0
lbl_stopped:    db "  Stopped: ", 0
lbl_zombie:     db "  Zombie: ", 0

task_info:      times 48 db 0
n_active:       dd 0
n_ready:        dd 0
n_running:      dd 0
n_blocked:      dd 0
n_stopped:      dd 0
n_zombie:       dd 0
