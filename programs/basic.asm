; basic.asm - Mellivora BASIC v3.0
; GW-BASIC-inspired interpreter for Mellivora OS
%include "syscalls.inc"

MAX_LINES               equ 600
MAX_LINE_LEN            equ 128
PROG_ENTRY_SIZE         equ 4 + MAX_LINE_LEN
PROG_SIZE               equ MAX_LINES * PROG_ENTRY_SIZE
INPUT_BUF_LEN           equ 255
STR_MAX_LEN             equ 255
TEMP_STR_COUNT          equ 8
GOSUB_DEPTH             equ 32
FOR_DEPTH               equ 16
WHILE_DEPTH             equ 16
ARRAY_COUNT             equ 26
ARRAY_MAX_SIZE          equ 256
DATA_ITEM_MAX           equ 512
DATA_POOL_SIZE          equ 16384
FILE_BUFFER_SIZE        equ 65536

ERR_NONE                equ 0
ERR_SYNTAX              equ 1
ERR_DIV0                equ 2
ERR_LINE                equ 3
ERR_GOSUB               equ 4
ERR_RETURN              equ 5
ERR_FOR                 equ 6
ERR_MEM                 equ 7
ERR_FILE                equ 8
ERR_READ                equ 9
ERR_WEND                equ 10
ERR_WHILE               equ 11
ERR_TYPE                equ 12

VAR_KIND_NUM            equ 0
VAR_KIND_ARR            equ 1
VAR_KIND_STR            equ 2

start:
	mov eax, SYS_SETCOLOR
	mov ebx, 0x0E
	int 0x80
	mov eax, SYS_PRINT
	mov ebx, msg_banner
	int 0x80
	mov eax, SYS_SETCOLOR
	mov ebx, 0x07
	int 0x80

	call reset_runtime_state

	mov eax, SYS_GETARGS
	mov ebx, input_buf
	int 0x80
	cmp eax, 0
	je .repl
	call cmd_load_from_args

.repl:
	mov eax, SYS_PRINT
	mov ebx, msg_ready
	int 0x80

.prompt:
	mov eax, SYS_PRINT
	mov ebx, msg_prompt
	int 0x80
	call read_line
	cmp byte [input_buf], 0
	je .prompt

	mov esi, input_buf
	call skip_spc
	mov al, [esi]
	cmp al, '0'
	jl .immediate
	cmp al, '9'
	jg .immediate
	call parse_linenum
	call store_line
	cmp byte [run_error], 0
	je .prompt
	call print_error
	mov byte [run_error], 0
	jmp .prompt

.immediate:
	mov esi, input_buf
	call exec_statement_sequence
	cmp byte [run_error], 0
	je .prompt
	call print_error
	mov byte [run_error], 0
	jmp .prompt

read_line:
	pushad
	mov edi, input_buf
	xor ecx, ecx
.rl_loop:
	mov eax, SYS_GETCHAR
	int 0x80
	cmp al, 0x0D
	je .rl_done
	cmp al, 0x0A
	je .rl_done
	cmp al, 27
	je .rl_cancel
	cmp al, 0x08
	je .rl_bs
	cmp al, 0x7F
	je .rl_bs
	cmp ecx, INPUT_BUF_LEN - 1
	jge .rl_loop
	mov [edi + ecx], al
	inc ecx
	push ecx
	movzx ebx, al
	mov eax, SYS_PUTCHAR
	int 0x80
	pop ecx
	jmp .rl_loop
.rl_bs:
	cmp ecx, 0
	je .rl_loop
	dec ecx
	push ecx
	mov eax, SYS_PUTCHAR
	mov ebx, 0x08
	int 0x80
	mov eax, SYS_PUTCHAR
	mov ebx, ' '
	int 0x80
	mov eax, SYS_PUTCHAR
	mov ebx, 0x08
	int 0x80
	pop ecx
	jmp .rl_loop
.rl_cancel:
	xor ecx, ecx
.rl_done:
	mov byte [edi + ecx], 0
	mov eax, SYS_PUTCHAR
	mov ebx, 0x0A
	int 0x80
	popad
	ret

read_raw_line:
	pushad
	mov edi, input_buf
	xor ecx, ecx
.rrl_loop:
	mov eax, SYS_GETCHAR
	int 0x80
	cmp al, 0x0D
	je .rrl_done
	cmp al, 0x0A
	je .rrl_done
	cmp al, 0x08
	je .rrl_bs
	cmp al, 0x7F
	je .rrl_bs
	cmp ecx, INPUT_BUF_LEN - 1
	jge .rrl_loop
	mov [edi + ecx], al
	inc ecx
	push ecx
	movzx ebx, al
	mov eax, SYS_PUTCHAR
	int 0x80
	pop ecx
	jmp .rrl_loop
.rrl_bs:
	cmp ecx, 0
	je .rrl_loop
	dec ecx
	push ecx
	mov eax, SYS_PUTCHAR
	mov ebx, 0x08
	int 0x80
	mov eax, SYS_PUTCHAR
	mov ebx, ' '
	int 0x80
	mov eax, SYS_PUTCHAR
	mov ebx, 0x08
	int 0x80
	pop ecx
	jmp .rrl_loop
.rrl_done:
	mov byte [edi + ecx], 0
	mov eax, SYS_PUTCHAR
	mov ebx, 0x0A
	int 0x80
	popad
	ret

parse_linenum:
	xor eax, eax
	xor edx, edx
.pl_loop:
	movzx edx, byte [esi]
	cmp dl, '0'
	jl .pl_done
	cmp dl, '9'
	jg .pl_done
	imul eax, 10
	sub dl, '0'
	add eax, edx
	inc esi
	jmp .pl_loop
.pl_done:
	call skip_spc
	ret

store_line:
	pushad
	mov edx, eax
	call rtrim_inplace
	cmp byte [esi], 0
	je .delete_line

	mov edi, program_area
	mov ecx, [line_count]
	xor ebx, ebx
.sl_find:
	cmp ebx, ecx
	jge .sl_insert_here
	cmp edx, [edi]
	je .sl_replace
	jl .sl_insert_here
	add edi, PROG_ENTRY_SIZE
	inc ebx
	jmp .sl_find

.sl_replace:
	add edi, 4
	mov ecx, MAX_LINE_LEN - 1
	call copy_str_n
	popad
	ret

.sl_insert_here:
	mov eax, [line_count]
	cmp eax, MAX_LINES
	jge .sl_full
	push esi
	push edx
	mov ecx, [line_count]
	sub ecx, ebx
	jz .sl_no_shift
	mov esi, program_area
	mov eax, [line_count]
	dec eax
	imul eax, PROG_ENTRY_SIZE
	add esi, eax
	lea edi, [esi + PROG_ENTRY_SIZE]
.sl_shift:
	push ecx
	push esi
	push edi
	mov ecx, PROG_ENTRY_SIZE
	std
	add esi, ecx
	dec esi
	add edi, ecx
	dec edi
	rep movsb
	cld
	pop edi
	pop esi
	sub esi, PROG_ENTRY_SIZE
	sub edi, PROG_ENTRY_SIZE
	pop ecx
	dec ecx
	jnz .sl_shift
.sl_no_shift:
	mov edi, program_area
	mov eax, ebx
	imul eax, PROG_ENTRY_SIZE
	add edi, eax
	pop edx
	mov [edi], edx
	add edi, 4
	pop esi
	mov ecx, MAX_LINE_LEN - 1
	call copy_str_n
	inc dword [line_count]
	popad
	ret

.delete_line:
	mov edi, program_area
	mov ecx, [line_count]
	xor ebx, ebx
.dl_find:
	cmp ebx, ecx
	jge .sl_done
	cmp edx, [edi]
	je .dl_found
	add edi, PROG_ENTRY_SIZE
	inc ebx
	jmp .dl_find
.dl_found:
	mov eax, [line_count]
	dec eax
	mov [line_count], eax
	sub eax, ebx
	jz .sl_done
	mov esi, edi
	add esi, PROG_ENTRY_SIZE
	mov ecx, eax
	imul ecx, PROG_ENTRY_SIZE
	rep movsb
.sl_done:
	popad
	ret

.sl_full:
	mov byte [run_error], ERR_MEM
	popad
	ret

copy_str_n:
	push eax
.csn_loop:
	lodsb
	cmp al, 0
	je .csn_pad
	stosb
	dec ecx
	jnz .csn_loop
	mov byte [edi - 1], 0
	pop eax
	ret
.csn_pad:
	mov byte [edi], 0
	pop eax
	ret

exec_statement_sequence:
	pushad
	mov [seq_base_ptr], esi
.ess_loop:
	call skip_spc
	mov [seq_cur_ptr], esi
	cmp byte [esi], 0
	je .ess_done
	call exec_single_statement
	cmp byte [run_error], 0
	jne .ess_done
	cmp byte [end_flag], 0
	jne .ess_done
	cmp byte [goto_flag], 0
	jne .ess_done
	cmp byte [resume_flag], 0
	jne .ess_done
	call skip_spc
	cmp byte [esi], ':'
	jne .ess_done
	inc esi
	jmp .ess_loop
.ess_done:
	mov [seq_end_ptr], esi
	popad
	ret

exec_single_statement:
	call skip_spc
	cmp byte [esi], 0
	je .ok
	call try_cmd_run
	jc .ok
	call try_cmd_list
	jc .ok
	call try_cmd_new
	jc .ok
	call try_cmd_load
	jc .ok
	call try_cmd_save
	jc .ok
	call try_cmd_system
	jc .ok
	call try_help
	jc .ok
	call try_rem
	jc .ok
	call try_print
	jc .ok
	call try_line_input
	jc .ok
	call try_input
	jc .ok
	call try_if
	jc .ok
	call try_on
	jc .ok
	call try_goto
	jc .ok
	call try_gosub
	jc .ok
	call try_return
	jc .ok
	call try_for
	jc .ok
	call try_next
	jc .ok
	call try_while
	jc .ok
	call try_wend
	jc .ok
	call try_end
	jc .ok
	call try_cls
	jc .ok
	call try_color
	jc .ok
	call try_beep_stmt
	jc .ok
	call try_poke
	jc .ok
	call try_sleep
	jc .ok
	call try_dim
	jc .ok
	call try_read
	jc .ok
	call try_restore
	jc .ok
	call try_swap
	jc .ok
	call try_locate
	jc .ok
	call try_data
	jc .ok
	call try_tron
	jc .ok
	call try_troff
	jc .ok
	call try_stop
	jc .ok
	call try_cont
	jc .ok
	call try_let
	jc .ok
	call try_implicit_let
	jc .ok
	mov byte [run_error], ERR_SYNTAX
.ok:
	ret

skip_spc:
	cmp byte [esi], ' '
	jne .ss_ret
	inc esi
	jmp skip_spc
.ss_ret:
	ret

to_upper:
	cmp al, 'a'
	jl .tu_ret
	cmp al, 'z'
	jg .tu_ret
	sub al, 32
.tu_ret:
	ret

match_kw:
	push eax
	push edi
	push esi
.mk_loop:
	mov al, [edi]
	cmp al, 0
	je .mk_match
	mov ah, [esi]
	cmp ah, 0
	je .mk_fail
	cmp ah, 'a'
	jl .mk_cmp
	cmp ah, 'z'
	jg .mk_cmp
	sub ah, 32
.mk_cmp:
	cmp ah, al
	jne .mk_fail
	inc esi
	inc edi
	jmp .mk_loop
.mk_match:
	mov al, [esi]
	cmp al, 0
	je .mk_ok
	cmp al, ' '
	je .mk_ok
	cmp al, ':'
	je .mk_ok
	cmp al, ','
	je .mk_ok
	cmp al, ';'
	je .mk_ok
	cmp al, '('
	je .mk_ok
	cmp al, '='
	je .mk_ok
	cmp al, '$'
	je .mk_ok
	jmp .mk_fail
.mk_ok:
	add esp, 4
	pop edi
	pop eax
	call skip_spc
	stc
	ret
.mk_fail:
	pop esi
	pop edi
	pop eax
	clc
	ret

find_statement_end:
	push esi
	xor edx, edx
.fse_loop:
	mov al, [esi]
	cmp al, 0
	je .fse_done
	cmp al, '"'
	jne .fse_check
	xor dl, 1
	inc esi
	jmp .fse_loop
.fse_check:
	cmp dl, 0
	jne .fse_next
	cmp al, ':'
	je .fse_done
.fse_next:
	inc esi
	jmp .fse_loop
.fse_done:
	mov eax, esi
	pop esi
	ret

get_line_ptr:
	push edx
	mov edx, eax
	imul edx, PROG_ENTRY_SIZE
	lea eax, [program_area + edx]
	mov [line_entry_ptr], eax
	lea eax, [eax + 4]
	mov [line_text_ptr], eax
	pop edx
	ret

find_next_stmt_position:
	push esi
	push ebx
	mov ebx, [current_line_idx]
	mov eax, ebx
	call get_line_ptr
	mov esi, [line_text_ptr]
	add esi, [current_stmt_offset]
	call find_statement_end
	mov esi, eax
	cmp byte [esi], ':'
	jne .fnp_next_line
	inc esi
	call skip_spc
	mov eax, ebx
	mov edx, esi
	sub edx, [line_text_ptr]
	jmp .fnp_done
.fnp_next_line:
	mov eax, ebx
	inc eax
	xor edx, edx
.fnp_done:
	pop ebx
	pop esi
	ret

looks_like_string_expr:
	push esi
	call skip_spc
	mov al, [esi]
	cmp al, '"'
	je .yes
	cmp al, 'A'
	jl .func
	cmp al, 'Z'
	jle .letter
	cmp al, 'a'
	jl .func
	cmp al, 'z'
	jg .func
.letter:
	cmp byte [esi + 1], '$'
	je .yes
.func:
	mov edi, kw_lefts
	call match_kw
	jc .yes2
	pop esi
	push esi
	mov edi, kw_rights
	call match_kw
	jc .yes2
	pop esi
	push esi
	mov edi, kw_mids
	call match_kw
	jc .yes2
	pop esi
	push esi
	mov edi, kw_chrs
	call match_kw
	jc .yes2
	pop esi
	push esi
	mov edi, kw_strs
	call match_kw
	jc .yes2
	pop esi
	push esi
	mov edi, kw_ltrims
	call match_kw
	jc .yes2
	pop esi
	push esi
	mov edi, kw_rtrims
	call match_kw
	jc .yes2
	pop esi
	push esi
	mov edi, kw_inkeys
	call match_kw
	jc .yes2
	pop esi
	push esi
	mov edi, kw_hexs
	call match_kw
	jc .yes2
	pop esi
	push esi
	mov edi, kw_octs
	call match_kw
	jc .yes2
	pop esi
	xor al, al
	ret
.yes2:
	add esp, 4
.yes:
	mov al, 1
	ret

try_print:
	push esi
	mov edi, kw_print
	call match_kw
	jnc .tp_fail
	mov byte [print_need_newline], 1
.tp_item:
	call skip_spc
	cmp byte [esi], 0
	je .tp_newline
	cmp byte [esi], ':'
	je .tp_newline
	push esi
	call try_print_control
	jc .tp_after_ctl
	pop esi
	call looks_like_string_expr
	cmp al, 0
	je .tp_num
	call eval_string_expr
	cmp byte [run_error], 0
	jne .tp_done
	mov ebx, eax
	mov eax, SYS_PRINT
	int 0x80
	jmp .tp_sep
.tp_num:
	call eval_expr
	cmp byte [run_error], 0
	jne .tp_done
	call print_signed
.tp_sep:
	call skip_spc
	cmp byte [esi], ';'
	je .tp_semi
	cmp byte [esi], ','
	je .tp_comma
	jmp .tp_newline
.tp_after_ctl:
	call skip_spc
	cmp byte [esi], ';'
	je .tp_semi
	cmp byte [esi], ','
	je .tp_comma
	jmp .tp_newline
.tp_semi:
	mov byte [print_need_newline], 0
	inc esi
	jmp .tp_item
.tp_comma:
	mov byte [print_need_newline], 0
	inc esi
	mov eax, SYS_PUTCHAR
	mov ebx, 0x09
	int 0x80
	jmp .tp_item
.tp_newline:
	cmp byte [print_need_newline], 0
	je .tp_done
	mov eax, SYS_PUTCHAR
	mov ebx, 0x0A
	int 0x80
.tp_done:
	add esp, 4
	stc
	ret
.tp_fail:
	pop esi
	clc
	ret

try_print_control:
	push esi
	mov edi, kw_tab
	call match_kw
	jc .tpc_tab
	pop esi
	push esi
	mov edi, kw_spc
	call match_kw
	jnc .tpc_fail
.tpc_spc:
	cmp byte [esi], '('
	jne .tpc_err
	inc esi
	call eval_expr
	cmp byte [esi], ')'
	jne .tpc_err
	inc esi
	cmp eax, 0
	jle .tpc_ok
	mov ecx, eax
.tpc_spc_loop:
	mov eax, SYS_PUTCHAR
	mov ebx, ' '
	int 0x80
	dec ecx
	jnz .tpc_spc_loop
.tpc_ok:
	add esp, 4
	stc
	ret
.tpc_tab:
	cmp byte [esi], '('
	jne .tpc_err
	inc esi
	call eval_expr
	cmp byte [esi], ')'
	jne .tpc_err
	inc esi
	cmp eax, 0
	jle .tpc_ok
	mov ecx, eax
.tpc_tab_loop:
	mov eax, SYS_PUTCHAR
	mov ebx, ' '
	int 0x80
	dec ecx
	jnz .tpc_tab_loop
	jmp .tpc_ok
.tpc_err:
	mov byte [run_error], ERR_SYNTAX
	add esp, 4
	stc
	ret
.tpc_fail:
	pop esi
	clc
	ret

try_input:
	push esi
	mov edi, kw_input
	call match_kw
	jnc .ti_fail
	call input_common
	add esp, 4
	stc
	ret
.ti_fail:
	pop esi
	clc
	ret

try_line_input:
	push esi
	mov edi, kw_line
	call match_kw
	jnc .tli_fail
	mov edi, kw_input
	call match_kw
	jnc .tli_err
	call line_input_common
	add esp, 4
	stc
	ret
.tli_err:
	mov byte [run_error], ERR_SYNTAX
	add esp, 4
	stc
	ret
.tli_fail:
	pop esi
	clc
	ret

input_common:
	call skip_spc
	cmp byte [esi], '"'
	jne .ic_default
	inc esi
.ic_prompt:
	mov al, [esi]
	cmp al, 0
	je .ic_after_quote
	cmp al, '"'
	je .ic_after_quote
	push eax
	movzx ebx, al
	mov eax, SYS_PUTCHAR
	int 0x80
	pop eax
	inc esi
	jmp .ic_prompt
.ic_after_quote:
	cmp byte [esi], '"'
	jne .ic_get_var
	inc esi
	call skip_spc
	cmp byte [esi], ';'
	je .ic_sep
	cmp byte [esi], ','
	jne .ic_get_var
.ic_sep:
	inc esi
	call skip_spc
	jmp .ic_get_var
.ic_default:
	mov eax, SYS_PRINT
	mov ebx, msg_input_prompt
	int 0x80
.ic_get_var:
	call parse_var_ref
	cmp byte [run_error], 0
	jne .ic_ret
	cmp byte [var_ref_kind], VAR_KIND_STR
	je .ic_string
	call read_raw_line
	mov esi, input_buf
	call parse_int_simple
	cmp byte [run_error], 0
	jne .ic_ret
	call store_numeric_ref
	ret
.ic_string:
	call read_raw_line
	mov esi, input_buf
	mov edi, [var_ref_ptr]
	mov ecx, STR_MAX_LEN
	call copy_str_n
.ic_ret:
	ret

line_input_common:
	call skip_spc
	cmp byte [esi], '"'
	jne .lic_default
	inc esi
.lic_prompt:
	mov al, [esi]
	cmp al, 0
	je .lic_after_quote
	cmp al, '"'
	je .lic_after_quote
	push eax
	movzx ebx, al
	mov eax, SYS_PUTCHAR
	int 0x80
	pop eax
	inc esi
	jmp .lic_prompt
.lic_after_quote:
	cmp byte [esi], '"'
	jne .lic_get_var
	inc esi
	call skip_spc
	cmp byte [esi], ';'
	je .lic_sep
	cmp byte [esi], ','
	jne .lic_get_var
.lic_sep:
	inc esi
	call skip_spc
	jmp .lic_get_var
.lic_default:
	mov eax, SYS_PRINT
	mov ebx, msg_input_prompt
	int 0x80
.lic_get_var:
	call parse_var_ref
	cmp byte [run_error], 0
	jne .lic_ret
	cmp byte [var_ref_kind], VAR_KIND_STR
	je .lic_ok
	mov byte [run_error], ERR_TYPE
	ret
.lic_ok:
	call read_raw_line
	mov esi, input_buf
	mov edi, [var_ref_ptr]
	mov ecx, STR_MAX_LEN
	call copy_str_n
.lic_ret:
	ret

try_let:
	push esi
	mov edi, kw_let
	call match_kw
	jnc .tl_fail
	call do_assignment
	add esp, 4
	stc
	ret
.tl_fail:
	pop esi
	clc
	ret

try_implicit_let:
	push esi
	mov al, [esi]
	call to_upper
	cmp al, 'A'
	jl .til_fail
	cmp al, 'Z'
	jg .til_fail
	mov al, [esi + 1]
	cmp al, '$'
	je .til_ok
	cmp al, '('
	je .til_ok
	cmp al, '='
	je .til_ok
	cmp al, ' '
	jne .til_fail
	mov al, [esi + 2]
	cmp al, '$'
	je .til_ok
	cmp al, '='
	je .til_ok
	cmp al, '('
	jne .til_fail
.til_ok:
	call do_assignment
	add esp, 4
	stc
	ret
.til_fail:
	pop esi
	clc
	ret

do_assignment:
	call parse_var_ref
	cmp byte [run_error], 0
	jne .da_ret
	call skip_spc
	cmp byte [esi], '='
	jne .da_err
	inc esi
	call skip_spc
	cmp byte [var_ref_kind], VAR_KIND_STR
	je .da_string
	call eval_expr
	cmp byte [run_error], 0
	jne .da_ret
	call store_numeric_ref
	ret
.da_string:
	call eval_string_expr
	cmp byte [run_error], 0
	jne .da_ret
	mov esi, eax
	mov edi, [var_ref_ptr]
	mov ecx, STR_MAX_LEN
	call copy_str_n
	ret
.da_err:
	mov byte [run_error], ERR_SYNTAX
.da_ret:
	ret

parse_var_ref:
	call skip_spc
	mov al, [esi]
	call to_upper
	cmp al, 'A'
	jl .pvr_err
	cmp al, 'Z'
	jg .pvr_err
	sub al, 'A'
	movzx edx, al
	mov [var_ref_index], edx
	inc esi
	cmp byte [esi], '$'
	je .pvr_str
	cmp byte [esi], '('
	je .pvr_arr
	mov byte [var_ref_kind], VAR_KIND_NUM
	lea eax, [variables + edx * 4]
	mov [var_ref_ptr], eax
	ret
.pvr_str:
	inc esi
	mov byte [var_ref_kind], VAR_KIND_STR
	mov eax, edx
	imul eax, STR_MAX_LEN + 1
	lea eax, [string_vars + eax]
	mov [var_ref_ptr], eax
	ret
.pvr_arr:
	inc esi
	call eval_expr
	cmp byte [run_error], 0
	jne .pvr_ret
	cmp byte [esi], ')'
	jne .pvr_err
	inc esi
	mov edx, [var_ref_index]
	cmp dword [array_sizes + edx * 4], 0
	jle .pvr_err
	cmp eax, 0
	jl .pvr_err
	cmp eax, [array_sizes + edx * 4]
	jge .pvr_err
	mov ecx, edx
	imul ecx, ARRAY_MAX_SIZE * 4
	lea ecx, [numeric_arrays + ecx + eax * 4]
	mov [var_ref_ptr], ecx
	mov byte [var_ref_kind], VAR_KIND_ARR
	ret
.pvr_err:
	mov byte [run_error], ERR_SYNTAX
.pvr_ret:
	ret

store_numeric_ref:
	mov ebx, [var_ref_ptr]
	mov [ebx], eax
	ret

try_if:
	push esi
	mov edi, kw_if
	call match_kw
	jnc .tif_fail
	call eval_expr
	cmp byte [run_error], 0
	jne .tif_done
	mov [if_condition_value], eax
	call skip_spc
	cmp byte [esi], '='
	je .tif_rel
	cmp byte [esi], '<'
	je .tif_rel
	cmp byte [esi], '>'
	je .tif_rel
	jmp .tif_need_then
.tif_rel:
	push eax
	call parse_relop
	mov [relop_code], al
	cmp byte [run_error], 0
	jne .tif_rel_fail
	call eval_expr
	mov ecx, eax
	pop ebx
	mov al, [relop_code]
	call compare_relop
	mov [if_condition_value], eax
	jmp .tif_need_then
.tif_rel_fail:
	add esp, 4
	jmp .tif_done
.tif_need_then:
	call skip_spc
	mov edi, kw_then
	call match_kw
	jnc .tif_err
	mov [if_then_ptr], esi
	call find_else_ptr
	mov [if_else_ptr], eax
	cmp dword [if_else_ptr], 0
	je .tif_dispatch
	mov edi, [if_else_ptr]
	mov byte [edi], 0
.tif_dispatch:
	cmp dword [if_condition_value], 0
	je .tif_false
	mov esi, [if_then_ptr]
	call exec_statement_sequence
	jmp .tif_restore
.tif_false:
	cmp dword [if_else_ptr], 0
	je .tif_restore
	mov esi, [if_else_ptr]
	add esi, 4
	call skip_spc
	call exec_statement_sequence
.tif_restore:
	cmp dword [if_else_ptr], 0
	je .tif_ok
	mov edi, [if_else_ptr]
	mov byte [edi], 'E'
.tif_ok:
	add esp, 4
	stc
	ret
.tif_err:
	mov byte [run_error], ERR_SYNTAX
.tif_done:
	add esp, 4
	stc
	ret
.tif_fail:
	pop esi
	clc
	ret

find_else_ptr:
	push esi
	xor edx, edx
.fep_loop:
	mov al, [esi]
	cmp al, 0
	je .fep_none
	cmp al, ':'
	je .fep_none
	cmp al, '"'
	jne .fep_check
	xor dl, 1
	inc esi
	jmp .fep_loop
.fep_check:
	cmp dl, 0
	jne .fep_next
	push esi
	mov edi, kw_else
	call match_kw
	jc .fep_found
	pop esi
.fep_next:
	inc esi
	jmp .fep_loop
.fep_found:
	add esp, 4
	mov eax, esi
	sub eax, 4
	jmp .fep_done
.fep_none:
	xor eax, eax
.fep_done:
	pop esi
	ret

parse_relop:
	mov al, [esi]
	cmp al, '='
	je .pro_eq
	cmp al, '<'
	je .pro_lt
	cmp al, '>'
	je .pro_gt
	mov byte [run_error], ERR_SYNTAX
	xor eax, eax
	ret
.pro_eq:
	mov al, 1
	inc esi
	ret
.pro_lt:
	inc esi
	cmp byte [esi], '='
	je .pro_le
	cmp byte [esi], '>'
	je .pro_ne
	mov al, 2
	ret
.pro_gt:
	inc esi
	cmp byte [esi], '='
	je .pro_ge
	mov al, 3
	ret
.pro_le:
	inc esi
	mov al, 4
	ret
.pro_ne:
	inc esi
	mov al, 5
	ret
.pro_ge:
	inc esi
	mov al, 6
	ret

compare_relop:
	cmp al, 1
	je .cr_eq
	cmp al, 2
	je .cr_lt
	cmp al, 3
	je .cr_gt
	cmp al, 4
	je .cr_le
	cmp al, 5
	je .cr_ne
	cmp al, 6
	je .cr_ge
	xor eax, eax
	ret
.cr_eq:
	cmp ebx, ecx
	sete al
	movzx eax, al
	ret
.cr_lt:
	cmp ebx, ecx
	setl al
	movzx eax, al
	ret
.cr_gt:
	cmp ebx, ecx
	setg al
	movzx eax, al
	ret
.cr_le:
	cmp ebx, ecx
	setle al
	movzx eax, al
	ret
.cr_ne:
	cmp ebx, ecx
	setne al
	movzx eax, al
	ret
.cr_ge:
	cmp ebx, ecx
	setge al
	movzx eax, al
	ret

try_on:
	push esi
	mov edi, kw_on
	call match_kw
	jnc .ton_fail
	call eval_expr
	cmp byte [run_error], 0
	jne .ton_done
	mov [on_index], eax
	call skip_spc
	push esi
	mov edi, kw_goto
	call match_kw
	jc .ton_goto
	pop esi
	push esi
	mov edi, kw_gosub
	call match_kw
	jc .ton_gosub
	pop esi
	mov byte [run_error], ERR_SYNTAX
	jmp .ton_done
.ton_goto:
	add esp, 4
	mov byte [on_mode], 0
	jmp .ton_select
.ton_gosub:
	add esp, 4
	mov byte [on_mode], 1
.ton_select:
	mov eax, [on_index]
	cmp eax, 1
	jl .ton_ok
	xor ecx, ecx
.ton_loop:
	call eval_expr
	cmp byte [run_error], 0
	jne .ton_done
	inc ecx
	cmp ecx, [on_index]
	je .ton_hit
	call skip_spc
	cmp byte [esi], ','
	jne .ton_ok
	inc esi
	call skip_spc
	jmp .ton_loop
.ton_hit:
	cmp byte [on_mode], 0
	je .ton_jump
	call push_return_target
	cmp byte [run_error], 0
	jne .ton_done
.ton_jump:
	mov [goto_target], eax
	mov byte [goto_flag], 1
.ton_ok:
	add esp, 4
	stc
	ret
.ton_done:
	add esp, 4
	stc
	ret
.ton_fail:
	pop esi
	clc
	ret

try_goto:
	push esi
	mov edi, kw_goto
	call match_kw
	jnc .tg_fail
	call eval_expr
	mov [goto_target], eax
	mov byte [goto_flag], 1
	add esp, 4
	stc
	ret
.tg_fail:
	pop esi
	clc
	ret

try_gosub:
	push esi
	mov edi, kw_gosub
	call match_kw
	jnc .tgs_fail
	call push_return_target
	cmp byte [run_error], 0
	jne .tgs_done
	call eval_expr
	mov [goto_target], eax
	mov byte [goto_flag], 1
.tgs_done:
	add esp, 4
	stc
	ret
.tgs_fail:
	pop esi
	clc
	ret

push_return_target:
	mov eax, [gosub_sp]
	cmp eax, GOSUB_DEPTH
	jge .prt_err
	mov ebx, eax
	shl ebx, 3
	call find_next_stmt_position
	mov [gosub_stack + ebx], eax
	mov [gosub_stack + ebx + 4], edx
	inc dword [gosub_sp]
	ret
.prt_err:
	mov byte [run_error], ERR_GOSUB
	ret

try_return:
	push esi
	mov edi, kw_return
	call match_kw
	jnc .tr_fail
	mov eax, [gosub_sp]
	cmp eax, 0
	je .tr_underflow
	dec eax
	mov [gosub_sp], eax
	mov ebx, eax
	shl ebx, 3
	mov eax, [gosub_stack + ebx]
	mov [resume_line_idx], eax
	mov eax, [gosub_stack + ebx + 4]
	mov [resume_stmt_offset], eax
	mov byte [resume_flag], 1
	add esp, 4
	stc
	ret
.tr_underflow:
	mov byte [run_error], ERR_RETURN
	add esp, 4
	stc
	ret
.tr_fail:
	pop esi
	clc
	ret

try_for:
	push esi
	mov edi, kw_for
	call match_kw
	jnc .tf_fail
	mov al, [esi]
	call to_upper
	cmp al, 'A'
	jl .tf_err
	cmp al, 'Z'
	jg .tf_err
	sub al, 'A'
	movzx edx, al
	inc esi
	call skip_spc
	cmp byte [esi], '='
	jne .tf_err
	inc esi
	call skip_spc
	call eval_expr
	cmp byte [run_error], 0
	jne .tf_done
	mov [variables + edx * 4], eax
	call skip_spc
	mov edi, kw_to
	call match_kw
	jnc .tf_err
	call eval_expr
	cmp byte [run_error], 0
	jne .tf_done
	mov [for_tmp_end], eax
	mov dword [for_tmp_step], 1
	push esi
	mov edi, kw_step
	call match_kw
	jnc .tf_no_step
	call eval_expr
	mov [for_tmp_step], eax
	jmp .tf_have_step
.tf_no_step:
	pop esi
.tf_have_step:
	call push_for_frame
	cmp byte [run_error], 0
	jne .tf_done
	add esp, 4
	stc
	ret
.tf_err:
	mov byte [run_error], ERR_SYNTAX
.tf_done:
	add esp, 4
	stc
	ret
.tf_fail:
	pop esi
	clc
	ret

push_for_frame:
	mov eax, [for_sp]
	cmp eax, FOR_DEPTH
	jge .pff_err
	mov ebx, eax
	imul ebx, 20
	mov [for_stack + ebx], edx
	mov eax, [for_tmp_end]
	mov [for_stack + ebx + 4], eax
	call find_next_stmt_position
	mov [for_stack + ebx + 8], eax
	mov [for_stack + ebx + 12], edx
	mov eax, [for_tmp_step]
	mov [for_stack + ebx + 16], eax
	inc dword [for_sp]
	ret
.pff_err:
	mov byte [run_error], ERR_FOR
	ret

try_next:
	push esi
	mov edi, kw_next
	call match_kw
	jnc .tn_fail
	mov eax, [for_sp]
	cmp eax, 0
	je .tn_err
	dec eax
	mov ebx, eax
	imul ebx, 20
	mov ecx, [for_stack + ebx]
	call skip_spc
	mov al, [esi]
	call to_upper
	cmp al, 'A'
	jl .tn_use_top
	cmp al, 'Z'
	jg .tn_use_top
	sub al, 'A'
	movzx edx, al
	cmp edx, ecx
	jne .tn_err
.tn_use_top:
	mov eax, [for_stack + ebx + 16]
	add [variables + ecx * 4], eax
	mov eax, [variables + ecx * 4]
	mov edx, [for_stack + ebx + 4]
	mov esi, [for_stack + ebx + 16]
	cmp esi, 0
	jl .tn_neg
	cmp eax, edx
	jg .tn_pop
	jmp .tn_loop
.tn_neg:
	cmp eax, edx
	jl .tn_pop
.tn_loop:
	mov eax, [for_stack + ebx + 8]
	mov [resume_line_idx], eax
	mov eax, [for_stack + ebx + 12]
	mov [resume_stmt_offset], eax
	mov byte [resume_flag], 1
	add esp, 4
	stc
	ret
.tn_pop:
	dec dword [for_sp]
	add esp, 4
	stc
	ret
.tn_err:
	mov byte [run_error], ERR_FOR
	add esp, 4
	stc
	ret
.tn_fail:
	pop esi
	clc
	ret

try_while:
	push esi
	mov edi, kw_while
	call match_kw
	jnc .twh_fail
	call eval_expr
	cmp byte [run_error], 0
	jne .twh_done
	cmp eax, 0
	jne .twh_true
	call skip_to_matching_wend
	add esp, 4
	stc
	ret
.twh_true:
	call ensure_while_frame
.twh_done:
	add esp, 4
	stc
	ret
.twh_fail:
	pop esi
	clc
	ret

ensure_while_frame:
	mov eax, [while_sp]
	cmp eax, 0
	je .ewf_push
	dec eax
	mov ebx, eax
	shl ebx, 3
	mov eax, [while_stack + ebx]
	cmp eax, [current_line_idx]
	jne .ewf_push
	mov eax, [while_stack + ebx + 4]
	cmp eax, [current_stmt_offset]
	je .ewf_ret
.ewf_push:
	mov eax, [while_sp]
	cmp eax, WHILE_DEPTH
	jge .ewf_err
	mov ebx, eax
	shl ebx, 3
	mov eax, [current_line_idx]
	mov [while_stack + ebx], eax
	mov eax, [current_stmt_offset]
	mov [while_stack + ebx + 4], eax
	inc dword [while_sp]
.ewf_ret:
	ret
.ewf_err:
	mov byte [run_error], ERR_WHILE
	ret

try_wend:
	push esi
	mov edi, kw_wend
	call match_kw
	jnc .twend_fail
	mov eax, [while_sp]
	cmp eax, 0
	je .twend_err
	dec eax
	mov ebx, eax
	shl ebx, 3
	mov eax, [while_stack + ebx]
	mov [resume_line_idx], eax
	mov eax, [while_stack + ebx + 4]
	mov [resume_stmt_offset], eax
	mov byte [resume_flag], 1
	add esp, 4
	stc
	ret
.twend_err:
	mov byte [run_error], ERR_WEND
	add esp, 4
	stc
	ret
.twend_fail:
	pop esi
	clc
	ret

skip_to_matching_wend:
	pushad
	mov byte [scan_found_end], 0
	mov dword [scan_nesting], 0
	mov eax, [current_line_idx]
	mov [scan_line_idx], eax
	mov eax, [current_stmt_offset]
	mov [scan_stmt_offset], eax
.stw_loop:
	call scan_advance_statement
	cmp byte [scan_found_end], 1
	je .stw_err
	mov eax, [scan_line_idx]
	call get_line_ptr
	mov esi, [line_text_ptr]
	add esi, [scan_stmt_offset]
	call skip_spc
	push esi
	mov edi, kw_while
	call match_kw
	jc .stw_while
	pop esi
	push esi
	mov edi, kw_wend
	call match_kw
	jc .stw_wend
	pop esi
	jmp .stw_loop
.stw_while:
	add esp, 4
	inc dword [scan_nesting]
	jmp .stw_loop
.stw_wend:
	add esp, 4
	cmp dword [scan_nesting], 0
	je .stw_target
	dec dword [scan_nesting]
	jmp .stw_loop
.stw_target:
	call scan_position_after_current
	mov eax, [scan_line_idx]
	mov [resume_line_idx], eax
	mov eax, [scan_stmt_offset]
	mov [resume_stmt_offset], eax
	mov byte [resume_flag], 1
	mov eax, [while_sp]
	cmp eax, 0
	je .stw_done
	dec eax
	mov ebx, eax
	shl ebx, 3
	mov ecx, [while_stack + ebx]
	cmp ecx, [current_line_idx]
	jne .stw_done
	mov ecx, [while_stack + ebx + 4]
	cmp ecx, [current_stmt_offset]
	jne .stw_done
	dec dword [while_sp]
	jmp .stw_done
.stw_err:
	mov byte [run_error], ERR_WEND
.stw_done:
	popad
	ret

scan_advance_statement:
	mov eax, [scan_line_idx]
	call get_line_ptr
	mov esi, [line_text_ptr]
	add esi, [scan_stmt_offset]
	call find_statement_end
	mov esi, eax
	cmp byte [esi], ':'
	jne .sas_next_line
	inc esi
	call skip_spc
	mov edx, esi
	sub edx, [line_text_ptr]
	mov [scan_stmt_offset], edx
	ret
.sas_next_line:
	inc dword [scan_line_idx]
	xor eax, eax
	mov [scan_stmt_offset], eax
	mov eax, [scan_line_idx]
	cmp eax, [line_count]
	jl .sas_ret
	mov byte [scan_found_end], 1
.sas_ret:
	ret

scan_position_after_current:
	mov eax, [scan_line_idx]
	call get_line_ptr
	mov esi, [line_text_ptr]
	add esi, [scan_stmt_offset]
	call find_statement_end
	mov esi, eax
	cmp byte [esi], ':'
	jne .spac_next_line
	inc esi
	call skip_spc
	mov eax, esi
	sub eax, [line_text_ptr]
	mov [scan_stmt_offset], eax
	ret
.spac_next_line:
	inc dword [scan_line_idx]
	xor eax, eax
	mov [scan_stmt_offset], eax
	ret

try_end:
	push esi
	mov edi, kw_end
	call match_kw
	jnc .te_fail
	mov byte [end_flag], 1
	add esp, 4
	stc
	ret
.te_fail:
	pop esi
	clc
	ret

try_rem:
	push esi
	mov edi, kw_rem
	call match_kw
	jnc .trem_fail
	call find_statement_end
	mov esi, eax
	add esp, 4
	stc
	ret
.trem_fail:
	pop esi
	clc
	ret

try_cls:
	push esi
	mov edi, kw_cls
	call match_kw
	jnc .tcls_fail
	mov eax, SYS_CLEAR
	int 0x80
	add esp, 4
	stc
	ret
.tcls_fail:
	pop esi
	clc
	ret

try_color:
	push esi
	mov edi, kw_color
	call match_kw
	jnc .tclr_fail
	call eval_expr
	mov ebx, eax
	mov eax, SYS_SETCOLOR
	int 0x80
	add esp, 4
	stc
	ret
.tclr_fail:
	pop esi
	clc
	ret

try_beep_stmt:
	push esi
	mov edi, kw_beep
	call match_kw
	jnc .tb_fail
	mov ebx, 1000
	mov ecx, 15
	call skip_spc
	cmp byte [esi], 0
	je .tb_do
	cmp byte [esi], ':'
	je .tb_do
	call eval_expr
	mov ebx, eax
	call skip_spc
	cmp byte [esi], ','
	jne .tb_do
	inc esi
	call skip_spc
	call eval_expr
	mov ecx, eax
.tb_do:
	mov eax, SYS_BEEP
	int 0x80
	add esp, 4
	stc
	ret
.tb_fail:
	pop esi
	clc
	ret

try_poke:
	push esi
	mov edi, kw_poke
	call match_kw
	jnc .tpk_fail
	call eval_expr
	mov edx, eax
	call skip_spc
	cmp byte [esi], ','
	jne .tpk_err
	inc esi
	call skip_spc
	call eval_expr
	mov [edx], al
	add esp, 4
	stc
	ret
.tpk_err:
	mov byte [run_error], ERR_SYNTAX
	add esp, 4
	stc
	ret
.tpk_fail:
	pop esi
	clc
	ret

try_sleep:
	push esi
	mov edi, kw_sleep
	call match_kw
	jnc .tsl_fail
	call eval_expr
	mov ebx, eax
	mov eax, SYS_SLEEP
	int 0x80
	add esp, 4
	stc
	ret
.tsl_fail:
	pop esi
	clc
	ret

try_dim:
	push esi
	mov edi, kw_dim
	call match_kw
	jnc .tdm_fail
.tdm_loop:
	call skip_spc
	mov al, [esi]
	call to_upper
	cmp al, 'A'
	jl .tdm_err
	cmp al, 'Z'
	jg .tdm_err
	sub al, 'A'
	movzx edx, al
	inc esi
	cmp byte [esi], '('
	jne .tdm_err
	inc esi
	call eval_expr
	cmp byte [esi], ')'
	jne .tdm_err
	inc esi
	cmp eax, 1
	jl .tdm_err
	cmp eax, ARRAY_MAX_SIZE
	jle .tdm_store
	mov eax, ARRAY_MAX_SIZE
.tdm_store:
	mov [array_sizes + edx * 4], eax
	mov edi, numeric_arrays
	mov ebx, edx
	imul ebx, ARRAY_MAX_SIZE * 4
	add edi, ebx
	push eax
	xor eax, eax
	mov ecx, ARRAY_MAX_SIZE
	rep stosd
	pop eax
	call skip_spc
	cmp byte [esi], ','
	jne .tdm_ok
	inc esi
	jmp .tdm_loop
.tdm_ok:
	add esp, 4
	stc
	ret
.tdm_err:
	mov byte [run_error], ERR_SYNTAX
	add esp, 4
	stc
	ret
.tdm_fail:
	pop esi
	clc
	ret

try_data:
	push esi
	mov edi, kw_data
	call match_kw
	jnc .tdat_fail
	call find_statement_end
	mov esi, eax
	add esp, 4
	stc
	ret
.tdat_fail:
	pop esi
	clc
	ret

try_read:
	push esi
	mov edi, kw_read
	call match_kw
	jnc .trd_fail
.trd_loop:
	push esi
	call parse_var_ref
	cmp byte [run_error], 0
	jne .trd_done
	push dword [var_ref_kind]
	push dword [var_ref_ptr]
	call read_next_data_item
	cmp byte [run_error], 0
	jne .trd_done_stack
	pop ebx
	pop ecx
	pop esi
	cmp ecx, VAR_KIND_STR
	je .trd_store_string
	mov esi, eax
	call parse_int_simple
	cmp byte [run_error], 0
	jne .trd_done
	mov [ebx], eax
	jmp .trd_next
.trd_store_string:
	mov esi, eax
	mov edi, ebx
	mov ecx, STR_MAX_LEN
	call copy_str_n
	jmp .trd_next
.trd_next:
	call skip_spc
	cmp byte [esi], ','
	jne .trd_ok
	inc esi
	call skip_spc
	jmp .trd_loop
.trd_ok:
	add esp, 4
	stc
	ret
.trd_done_stack:
	add esp, 8
.trd_done:
	add esp, 4
	stc
	ret
.trd_fail:
	pop esi
	clc
	ret

try_restore:
	push esi
	mov edi, kw_restore
	call match_kw
	jnc .tres_fail
	mov dword [data_read_idx], 0
	add esp, 4
	stc
	ret
.tres_fail:
	pop esi
	clc
	ret

try_swap:
	push esi
	mov edi, kw_swap
	call match_kw
	jnc .tsw_fail
	call parse_var_ref
	cmp byte [run_error], 0
	jne .tsw_done
	mov eax, [var_ref_kind]
	mov [swap_kind], eax
	mov eax, [var_ref_ptr]
	mov [swap_ptr_a], eax
	call skip_spc
	cmp byte [esi], ','
	jne .tsw_err
	inc esi
	call skip_spc
	call parse_var_ref
	cmp byte [run_error], 0
	jne .tsw_done
	mov eax, [var_ref_kind]
	cmp eax, [swap_kind]
	jne .tsw_type
	cmp eax, VAR_KIND_STR
	je .tsw_string
	mov eax, [swap_ptr_a]
	mov ebx, [var_ref_ptr]
	mov ecx, [eax]
	mov edx, [ebx]
	mov [eax], edx
	mov [ebx], ecx
	jmp .tsw_ok
.tsw_string:
	mov esi, [swap_ptr_a]
	mov edi, temp_string_copy
	mov ecx, STR_MAX_LEN
	call copy_str_n
	mov esi, [var_ref_ptr]
	mov edi, [swap_ptr_a]
	mov ecx, STR_MAX_LEN
	call copy_str_n
	mov esi, temp_string_copy
	mov edi, [var_ref_ptr]
	mov ecx, STR_MAX_LEN
	call copy_str_n
	jmp .tsw_ok
.tsw_type:
	mov byte [run_error], ERR_TYPE
	jmp .tsw_done
.tsw_err:
	mov byte [run_error], ERR_SYNTAX
	jmp .tsw_done
.tsw_ok:
	add esp, 4
	stc
	ret
.tsw_done:
	add esp, 4
	stc
	ret
.tsw_fail:
	pop esi
	clc
	ret

try_locate:
	push esi
	mov edi, kw_locate
	call match_kw
	jnc .tloc_fail
	call eval_expr
	mov ecx, eax
	call skip_spc
	cmp byte [esi], ','
	jne .tloc_err
	inc esi
	call skip_spc
	call eval_expr
	mov ebx, eax
	mov eax, SYS_SETCURSOR
	int 0x80
	add esp, 4
	stc
	ret
.tloc_err:
	mov byte [run_error], ERR_SYNTAX
	add esp, 4
	stc
	ret
.tloc_fail:
	pop esi
	clc
	ret

try_tron:
	push esi
	mov edi, kw_tron
	call match_kw
	jnc .ttron_fail
	mov byte [trace_mode], 1
	add esp, 4
	stc
	ret
.ttron_fail:
	pop esi
	clc
	ret

try_troff:
	push esi
	mov edi, kw_troff
	call match_kw
	jnc .ttroff_fail
	mov byte [trace_mode], 0
	add esp, 4
	stc
	ret
.ttroff_fail:
	pop esi
	clc
	ret

try_stop:
	push esi
	mov edi, kw_stop
	call match_kw
	jnc .tstop_fail
	; Save resume position (next statement after STOP)
	call find_next_stmt_position
	mov [stop_line_idx], eax
	mov [stop_stmt_off], edx
	mov byte [stop_flag], 1
	; Print "Break in line N"
	mov eax, SYS_SETCOLOR
	mov ebx, 0x0E
	int 0x80
	mov eax, SYS_PRINT
	mov ebx, msg_break
	int 0x80
	mov eax, [current_line_idx]
	cmp eax, [line_count]
	jge .tstop_no_linenum
	call get_line_ptr
	mov eax, [line_entry_ptr]
	mov eax, [eax]
	call print_dec
.tstop_no_linenum:
	mov eax, SYS_PUTCHAR
	mov ebx, 0x0A
	int 0x80
	mov eax, SYS_SETCOLOR
	mov ebx, 0x07
	int 0x80
	mov byte [end_flag], 1
	add esp, 4
	stc
	ret
.tstop_fail:
	pop esi
	clc
	ret

try_cont:
	push esi
	mov edi, kw_cont
	call match_kw
	jnc .tcont_fail
	cmp byte [stop_flag], 0
	je .tcont_no_stop
	mov byte [stop_flag], 0
	mov byte [end_flag], 0
	; Restore resume position
	mov eax, [stop_line_idx]
	mov [current_line_idx], eax
	mov eax, [stop_stmt_off]
	mov [current_stmt_offset], eax
	call cont_program
	add esp, 4
	stc
	ret
.tcont_no_stop:
	mov eax, SYS_PRINT
	mov ebx, msg_cant_cont
	int 0x80
	add esp, 4
	stc
	ret
.tcont_fail:
	pop esi
	clc
	ret

cont_program:
	pushad
	; Resume without resetting state
.cp_loop:
	cmp byte [end_flag], 0
	jne .cp_end
	cmp byte [goto_flag], 0
	jne .cp_goto
	cmp byte [resume_flag], 0
	jne .cp_resume
	mov eax, [current_line_idx]
	cmp eax, [line_count]
	jge .cp_end
	xor eax, eax
	mov [current_stmt_offset], eax
	jmp .cp_dispatch
.cp_resume:
	mov byte [resume_flag], 0
	mov eax, [resume_line_idx]
	mov [current_line_idx], eax
	mov eax, [resume_stmt_offset]
	mov [current_stmt_offset], eax
	mov eax, [line_count]
	cmp dword [current_line_idx], eax
	jge .cp_end
	jmp .cp_dispatch
.cp_goto:
	mov byte [goto_flag], 0
	mov edx, [goto_target]
	call find_line_index
	cmp eax, -1
	jne .cp_got_line
	mov byte [run_error], ERR_LINE
	jmp .cp_error
.cp_got_line:
	mov [current_line_idx], eax
	xor eax, eax
	mov [current_stmt_offset], eax
.cp_dispatch:
	mov eax, [current_line_idx]
	call get_line_ptr
	cmp byte [trace_mode], 0
	je .cp_no_trace
	mov eax, SYS_PUTCHAR
	mov ebx, '['
	int 0x80
	mov eax, [line_entry_ptr]
	mov eax, [eax]
	call print_dec
	mov eax, SYS_PUTCHAR
	mov ebx, ']'
	int 0x80
.cp_no_trace:
	mov esi, [line_text_ptr]
	add esi, [current_stmt_offset]
	call exec_statement_sequence
	cmp byte [run_error], 0
	jne .cp_error
	cmp byte [goto_flag], 0
	jne .cp_loop
	cmp byte [resume_flag], 0
	jne .cp_loop
	cmp byte [end_flag], 0
	jne .cp_end
	inc dword [current_line_idx]
	xor eax, eax
	mov [current_stmt_offset], eax
	jmp .cp_loop
.cp_error:
	call print_error_with_line
.cp_end:
	mov byte [goto_flag], 0
	mov byte [resume_flag], 0
	popad
	ret

try_help:
	push esi
	mov edi, kw_help
	call match_kw
	jnc .th_fail
	mov eax, SYS_PRINT
	mov ebx, msg_help
	int 0x80
	add esp, 4
	stc
	ret
.th_fail:
	pop esi
	clc
	ret

try_cmd_run:
	push esi
	mov edi, kw_run
	call match_kw
	jnc .tcr_fail
	call run_program
	add esp, 4
	stc
	ret
.tcr_fail:
	pop esi
	clc
	ret

try_cmd_list:
	push esi
	mov edi, kw_list
	call match_kw
	jnc .tcl_fail
	call list_program
	add esp, 4
	stc
	ret
.tcl_fail:
	pop esi
	clc
	ret

try_cmd_new:
	push esi
	mov edi, kw_new
	call match_kw
	jnc .tcn_fail
	mov dword [line_count], 0
	add esp, 4
	stc
	ret
.tcn_fail:
	pop esi
	clc
	ret

try_cmd_load:
	push esi
	mov edi, kw_load
	call match_kw
	jnc .tclod_fail
	call cmd_load
	add esp, 4
	stc
	ret
.tclod_fail:
	pop esi
	clc
	ret

try_cmd_save:
	push esi
	mov edi, kw_save
	call match_kw
	jnc .tcsv_fail
	call cmd_save
	add esp, 4
	stc
	ret
.tcsv_fail:
	pop esi
	clc
	ret

try_cmd_system:
	push esi
	mov edi, kw_system
	call match_kw
	jnc .tcsys_fail
	add esp, 4
	xor eax, eax
	int 0x80
.tcsys_fail:
	pop esi
	clc
	ret

run_program:
	pushad
	call reset_runtime_state
	call collect_data_items
	cmp byte [run_error], 0
	jne .rp_end
	mov dword [current_line_idx], 0
	mov dword [current_stmt_offset], 0
.rp_loop:
	cmp byte [end_flag], 0
	jne .rp_end
	cmp byte [goto_flag], 0
	jne .rp_goto
	cmp byte [resume_flag], 0
	jne .rp_resume
	mov eax, [current_line_idx]
	cmp eax, [line_count]
	jge .rp_end
	xor eax, eax
	mov [current_stmt_offset], eax
	jmp .rp_dispatch
.rp_resume:
	mov byte [resume_flag], 0
	mov eax, [resume_line_idx]
	mov [current_line_idx], eax
	mov eax, [resume_stmt_offset]
	mov [current_stmt_offset], eax
	mov eax, [line_count]
	cmp dword [current_line_idx], eax
	jge .rp_end
	jmp .rp_dispatch
.rp_goto:
	mov byte [goto_flag], 0
	mov edx, [goto_target]
	call find_line_index
	cmp eax, -1
	jne .rp_got_line
	mov byte [run_error], ERR_LINE
	jmp .rp_error
.rp_got_line:
	mov [current_line_idx], eax
	xor eax, eax
	mov [current_stmt_offset], eax
.rp_dispatch:
	mov eax, [current_line_idx]
	call get_line_ptr
	; TRON trace: print [linenum] before executing
	cmp byte [trace_mode], 0
	je .rp_no_trace
	mov eax, SYS_PUTCHAR
	mov ebx, '['
	int 0x80
	mov eax, [line_entry_ptr]
	mov eax, [eax]
	call print_dec
	mov eax, SYS_PUTCHAR
	mov ebx, ']'
	int 0x80
.rp_no_trace:
	mov esi, [line_text_ptr]
	add esi, [current_stmt_offset]
	call exec_statement_sequence
	cmp byte [run_error], 0
	jne .rp_error
	cmp byte [goto_flag], 0
	jne .rp_loop
	cmp byte [resume_flag], 0
	jne .rp_loop
	cmp byte [end_flag], 0
	jne .rp_end
	inc dword [current_line_idx]
	xor eax, eax
	mov [current_stmt_offset], eax
	jmp .rp_loop
.rp_error:
	call print_error_with_line
.rp_end:
	mov byte [goto_flag], 0
	mov byte [resume_flag], 0
	popad
	ret

find_line_index:
	push ebx
	push ecx
	push edi
	mov ecx, [line_count]
	mov edi, program_area
	xor ebx, ebx
.fli_loop:
	cmp ebx, ecx
	jge .fli_nf
	cmp edx, [edi]
	je .fli_found
	add edi, PROG_ENTRY_SIZE
	inc ebx
	jmp .fli_loop
.fli_found:
	mov eax, ebx
	jmp .fli_done
.fli_nf:
	mov eax, -1
.fli_done:
	pop edi
	pop ecx
	pop ebx
	ret

list_program:
	pushad
	mov ecx, [line_count]
	xor ebx, ebx
.lp_loop:
	cmp ebx, ecx
	jge .lp_done
	mov eax, ebx
	call get_line_ptr
	mov eax, [line_entry_ptr]
	mov eax, [eax]
	call print_dec
	mov eax, SYS_PUTCHAR
	mov ebx, ' '
	int 0x80
	mov eax, SYS_PRINT
	mov ebx, [line_text_ptr]
	int 0x80
	mov eax, SYS_PUTCHAR
	mov ebx, 0x0A
	int 0x80
	inc ebx
	jmp .lp_loop
.lp_done:
	popad
	ret

eval_expr:
	call skip_spc
	call eval_add_sub
	ret

eval_add_sub:
	call eval_mul_div
	push eax
.eas_loop:
	call skip_spc
	cmp byte [esi], '+'
	je .eas_add
	cmp byte [esi], '-'
	je .eas_sub
	pop eax
	ret
.eas_add:
	inc esi
	call eval_mul_div
	pop ebx
	add eax, ebx
	push eax
	jmp .eas_loop
.eas_sub:
	inc esi
	call eval_mul_div
	pop ebx
	sub ebx, eax
	mov eax, ebx
	push eax
	jmp .eas_loop

eval_mul_div:
	call eval_unary
	push eax
.emd_loop:
	call skip_spc
	cmp byte [esi], '*'
	je .emd_mul
	cmp byte [esi], '/'
	je .emd_div
	cmp byte [esi], '%'
	je .emd_mod
	pop eax
	ret
.emd_mul:
	inc esi
	call eval_unary
	pop ebx
	imul eax, ebx
	push eax
	jmp .emd_loop
.emd_div:
	inc esi
	call eval_unary
	cmp eax, 0
	je .emd_div0
	mov ebx, eax
	pop eax
	cdq
	idiv ebx
	push eax
	jmp .emd_loop
.emd_mod:
	inc esi
	call eval_unary
	cmp eax, 0
	je .emd_div0
	mov ebx, eax
	pop eax
	cdq
	idiv ebx
	mov eax, edx
	push eax
	jmp .emd_loop
.emd_div0:
	mov byte [run_error], ERR_DIV0
	pop eax
	xor eax, eax
	ret

eval_unary:
	call skip_spc
	cmp byte [esi], '-'
	je .eu_neg
	cmp byte [esi], '('
	je .eu_paren
	jmp eval_atom
.eu_neg:
	inc esi
	call eval_unary
	neg eax
	ret
.eu_paren:
	inc esi
	call eval_expr
	call skip_spc
	cmp byte [esi], ')'
	jne .eu_no_close
	inc esi
	ret
.eu_no_close:
	mov byte [run_error], ERR_SYNTAX
	ret

eval_atom:
	call skip_spc
	movzx eax, byte [esi]
	cmp al, '0'
	jl .ea_var
	cmp al, '9'
	jg .ea_var
	jmp .ea_number
.ea_var:
	call to_upper
	cmp al, 'A'
	jl .ea_funcs
	cmp al, 'Z'
	jg .ea_funcs
	cmp byte [esi + 1], '$'
	je .ea_type
	cmp byte [esi + 1], '('
	je .ea_arr
	sub al, 'A'
	movzx eax, al
	mov eax, [variables + eax * 4]
	inc esi
	ret
.ea_arr:
	sub al, 'A'
	movzx edx, al
	add esi, 2
	call eval_expr
	cmp byte [esi], ')'
	jne .ea_err
	inc esi
	cmp dword [array_sizes + edx * 4], 0
	jle .ea_err
	cmp eax, 0
	jl .ea_err
	cmp eax, [array_sizes + edx * 4]
	jge .ea_err
	mov ecx, edx
	imul ecx, ARRAY_MAX_SIZE * 4
	mov eax, [numeric_arrays + ecx + eax * 4]
	ret
.ea_funcs:
	call eval_numeric_function
	ret
.ea_type:
	mov byte [run_error], ERR_TYPE
	xor eax, eax
	ret
.ea_err:
	mov byte [run_error], ERR_SYNTAX
	xor eax, eax
	ret
.ea_number:
	xor eax, eax
.ean_loop:
	movzx edx, byte [esi]
	cmp dl, '0'
	jl .ean_done
	cmp dl, '9'
	jg .ean_done
	imul eax, 10
	sub dl, '0'
	add eax, edx
	inc esi
	jmp .ean_loop
.ean_done:
	ret

eval_numeric_function:
	push esi
	mov edi, kw_rnd
	call match_kw
	jc .enf_rnd
	pop esi
	push esi
	mov edi, kw_peek
	call match_kw
	jc .enf_peek
	pop esi
	push esi
	mov edi, kw_abs
	call match_kw
	jc .enf_abs
	pop esi
	push esi
	mov edi, kw_int
	call match_kw
	jc .enf_int
	pop esi
	push esi
	mov edi, kw_sgn
	call match_kw
	jc .enf_sgn
	pop esi
	push esi
	mov edi, kw_sqr
	call match_kw
	jc .enf_sqr
	pop esi
	push esi
	mov edi, kw_sin
	call match_kw
	jc .enf_sin
	pop esi
	push esi
	mov edi, kw_cos
	call match_kw
	jc .enf_cos
	pop esi
	push esi
	mov edi, kw_tan
	call match_kw
	jc .enf_tan
	pop esi
	push esi
	mov edi, kw_atn
	call match_kw
	jc .enf_atn
	pop esi
	push esi
	mov edi, kw_log
	call match_kw
	jc .enf_log
	pop esi
	push esi
	mov edi, kw_exp
	call match_kw
	jc .enf_exp
	pop esi
	push esi
	mov edi, kw_time
	call match_kw
	jc .enf_time
	pop esi
	push esi
	mov edi, kw_asc
	call match_kw
	jc .enf_asc
	pop esi
	push esi
	mov edi, kw_len
	call match_kw
	jc .enf_len
	pop esi
	push esi
	mov edi, kw_val
	call match_kw
	jc .enf_val
	pop esi
	push esi
	mov edi, kw_instr
	call match_kw
	jc .enf_instr
	pop esi
	mov byte [run_error], ERR_SYNTAX
	xor eax, eax
	ret
.enf_rnd:
	add esp, 4
	cmp byte [esi], '('
	jne .enf_rnd_noarg
	inc esi
	call eval_expr
	cmp byte [esi], ')'
	jne .enf_err
	inc esi
	push eax
	call random
	pop ebx
	cmp ebx, 0
	jle .enf_ret
	xor edx, edx
	div ebx
	mov eax, edx
	inc eax
	ret
.enf_rnd_noarg:
	call random
	ret
.enf_peek:
	add esp, 4
	call expect_paren_expr
	cmp byte [run_error], 0
	jne .enf_ret
	movzx eax, byte [eax]
	ret
.enf_abs:
	add esp, 4
	call expect_paren_expr
	cmp eax, 0
	jge .enf_ret
	neg eax
	ret
.enf_int:
	add esp, 4
	call expect_paren_expr
	ret
.enf_sgn:
	add esp, 4
	call expect_paren_expr
	cmp eax, 0
	je .enf_zero
	jl .enf_neg
	mov eax, 1
	ret
.enf_neg:
	mov eax, -1
	ret
.enf_zero:
	xor eax, eax
	ret
.enf_sqr:
	add esp, 4
	call expect_paren_expr
	call int_sqrt
	ret
.enf_sin:
	add esp, 4
	call expect_paren_expr
	call math_sin
	ret
.enf_cos:
	add esp, 4
	call expect_paren_expr
	call math_cos
	ret
.enf_tan:
	add esp, 4
	call expect_paren_expr
	call math_tan
	ret
.enf_atn:
	add esp, 4
	call expect_paren_expr
	call math_atn
	ret
.enf_log:
	add esp, 4
	call expect_paren_expr
	call math_log
	ret
.enf_exp:
	add esp, 4
	call expect_paren_expr
	call math_exp
	ret
.enf_time:
	add esp, 4
	mov eax, SYS_GETTIME
	int 0x80
	ret
.enf_asc:
	add esp, 4
	call expect_paren_string_expr
	movzx eax, byte [eax]
	ret
.enf_len:
	add esp, 4
	call expect_paren_string_expr
	mov esi, eax
	call strlen
	mov eax, ecx
	ret
.enf_val:
	add esp, 4
	call expect_paren_string_expr
	mov esi, eax
	call parse_int_simple
	ret
.enf_instr:
	add esp, 4
	cmp byte [esi], '('
	jne .enf_err
	inc esi
	call eval_string_expr
	mov [instr_hay_ptr], eax
	call skip_spc
	cmp byte [esi], ','
	jne .enf_err
	inc esi
	call skip_spc
	call eval_string_expr
	mov ebx, eax
	cmp byte [esi], ')'
	jne .enf_err
	inc esi
	mov esi, [instr_hay_ptr]
	call instr_search
	ret
.enf_err:
	mov byte [run_error], ERR_SYNTAX
	xor eax, eax
.enf_ret:
	ret

expect_paren_expr:
	cmp byte [esi], '('
	jne .epe_err
	inc esi
	call eval_expr
	cmp byte [esi], ')'
	jne .epe_err
	inc esi
	ret
.epe_err:
	mov byte [run_error], ERR_SYNTAX
	xor eax, eax
	ret

expect_paren_string_expr:
	cmp byte [esi], '('
	jne .epse_err
	inc esi
	call eval_string_expr
	cmp byte [esi], ')'
	jne .epse_err
	inc esi
	ret
.epse_err:
	mov byte [run_error], ERR_SYNTAX
	xor eax, eax
	ret

eval_string_expr:
	call eval_string_term
	mov ebx, eax
	call alloc_temp_string
	mov edi, eax
	mov esi, ebx
	mov ecx, STR_MAX_LEN
	call copy_str_n
	mov [str_expr_result], eax
.ese_loop:
	call skip_spc
	cmp byte [esi], '+'
	jne .ese_done
	inc esi
	call skip_spc
	call eval_string_term
	cmp byte [run_error], 0
	jne .ese_ret
	mov ebx, eax
	mov edi, [str_expr_result]
	mov esi, ebx
	call strcat_limit
	jmp .ese_loop
.ese_done:
	mov eax, [str_expr_result]
.ese_ret:
	ret

eval_string_term:
	call skip_spc
	cmp byte [esi], '"'
	je .est_lit
	mov al, [esi]
	call to_upper
	cmp al, 'A'
	jl .est_funcs
	cmp al, 'Z'
	jg .est_funcs
	cmp byte [esi + 1], '$'
	jne .est_funcs
	sub al, 'A'
	movzx eax, al
	imul eax, STR_MAX_LEN + 1
	lea eax, [string_vars + eax]
	add esi, 2
	ret
.est_lit:
	inc esi
	call alloc_temp_string
	mov edi, eax
.est_lit_loop:
	mov al, [esi]
	cmp al, 0
	je .est_lit_done
	cmp al, '"'
	je .est_lit_done
	stosb
	inc esi
	jmp .est_lit_loop
.est_lit_done:
	mov byte [edi], 0
	cmp byte [esi], '"'
	jne .est_retbuf
	inc esi
.est_retbuf:
	mov eax, [last_temp_string]
	ret
.est_funcs:
	push esi
	mov edi, kw_lefts
	call match_kw
	jc .est_left
	pop esi
	push esi
	mov edi, kw_rights
	call match_kw
	jc .est_right
	pop esi
	push esi
	mov edi, kw_mids
	call match_kw
	jc .est_mid
	pop esi
	push esi
	mov edi, kw_chrs
	call match_kw
	jc .est_chr
	pop esi
	push esi
	mov edi, kw_strs
	call match_kw
	jc .est_str
	pop esi
	push esi
	mov edi, kw_ltrims
	call match_kw
	jc .est_ltrim
	pop esi
	push esi
	mov edi, kw_rtrims
	call match_kw
	jc .est_rtrim
	pop esi
	push esi
	mov edi, kw_inkeys
	call match_kw
	jc .est_inkey
	pop esi
	push esi
	mov edi, kw_hexs
	call match_kw
	jc .est_hex
	pop esi
	push esi
	mov edi, kw_octs
	call match_kw
	jc .est_oct
	pop esi
	mov byte [run_error], ERR_TYPE
	xor eax, eax
	ret
.est_left:
	add esp, 4
	call string_func_left
	ret
.est_right:
	add esp, 4
	call string_func_right
	ret
.est_mid:
	add esp, 4
	call string_func_mid
	ret
.est_chr:
	add esp, 4
	call string_func_chr
	ret
.est_str:
	add esp, 4
	call string_func_str
	ret
.est_ltrim:
	add esp, 4
	call string_func_ltrim
	ret
.est_rtrim:
	add esp, 4
	call string_func_rtrim
	ret
.est_inkey:
	add esp, 4
	call string_func_inkey
	ret
.est_hex:
	add esp, 4
	call string_func_hex
	ret
.est_oct:
	add esp, 4
	call string_func_oct
	ret

string_func_left:
	cmp byte [esi], '('
	jne .sfl_err
	inc esi
	call eval_string_expr
	mov [func_str_ptr], eax
	call skip_spc
	cmp byte [esi], ','
	jne .sfl_err
	inc esi
	call skip_spc
	call eval_expr
	mov [func_num_a], eax
	cmp byte [esi], ')'
	jne .sfl_err
	inc esi
	call alloc_temp_string
	mov edi, eax
	mov esi, [func_str_ptr]
	mov ecx, [func_num_a]
	cmp ecx, 0
	jge .sfl_oklen
	xor ecx, ecx
.sfl_oklen:
	cmp ecx, STR_MAX_LEN
	jle .sfl_loop
	mov ecx, STR_MAX_LEN
.sfl_loop:
	cmp ecx, 0
	je .sfl_done
	lodsb
	cmp al, 0
	je .sfl_done
	stosb
	dec ecx
	jmp .sfl_loop
.sfl_done:
	mov byte [edi], 0
	mov eax, [last_temp_string]
	ret
.sfl_err:
	mov byte [run_error], ERR_SYNTAX
	xor eax, eax
	ret

string_func_right:
	cmp byte [esi], '('
	jne .sfr_err
	inc esi
	call eval_string_expr
	mov [func_str_ptr], eax
	call skip_spc
	cmp byte [esi], ','
	jne .sfr_err
	inc esi
	call skip_spc
	call eval_expr
	mov [func_num_a], eax
	cmp byte [esi], ')'
	jne .sfr_err
	inc esi
	mov esi, [func_str_ptr]
	call strlen
	mov eax, ecx
	sub eax, [func_num_a]
	jns .sfr_start
	xor eax, eax
.sfr_start:
	add esi, eax
	call alloc_temp_string
	mov edi, eax
	mov ecx, STR_MAX_LEN
	call copy_str_n
	mov eax, [last_temp_string]
	ret
.sfr_err:
	mov byte [run_error], ERR_SYNTAX
	xor eax, eax
	ret

string_func_mid:
	cmp byte [esi], '('
	jne .sfm_err
	inc esi
	call eval_string_expr
	mov [func_str_ptr], eax
	call skip_spc
	cmp byte [esi], ','
	jne .sfm_err
	inc esi
	call skip_spc
	call eval_expr
	mov [func_num_a], eax
	mov dword [func_num_b], STR_MAX_LEN
	call skip_spc
	cmp byte [esi], ','
	jne .sfm_close
	inc esi
	call skip_spc
	call eval_expr
	mov [func_num_b], eax
.sfm_close:
	cmp byte [esi], ')'
	jne .sfm_err
	inc esi
	mov esi, [func_str_ptr]
	mov eax, [func_num_a]
	dec eax
	jns .sfm_pos
	xor eax, eax
.sfm_pos:
	add esi, eax
	call alloc_temp_string
	mov edi, eax
	mov ecx, [func_num_b]
	cmp ecx, 0
	jge .sfm_loop
	xor ecx, ecx
.sfm_loop:
	cmp ecx, 0
	je .sfm_done
	lodsb
	cmp al, 0
	je .sfm_done
	stosb
	dec ecx
	jmp .sfm_loop
.sfm_done:
	mov byte [edi], 0
	mov eax, [last_temp_string]
	ret
.sfm_err:
	mov byte [run_error], ERR_SYNTAX
	xor eax, eax
	ret

string_func_chr:
	call expect_paren_expr
	cmp byte [run_error], 0
	jne .sfc_ret
	call alloc_temp_string
	mov edi, eax
	mov [edi], al
	mov byte [edi + 1], 0
	mov eax, [last_temp_string]
.sfc_ret:
	ret

string_func_str:
	call expect_paren_expr
	cmp byte [run_error], 0
	jne .sfs_ret
	mov [tmp_num_value], eax
	call alloc_temp_string
	mov edi, eax
	call write_signed_to_string
	mov eax, [last_temp_string]
.sfs_ret:
	ret

string_func_ltrim:
	call expect_paren_string_expr
	cmp byte [run_error], 0
	jne .sflt_ret
	mov esi, eax
.sflt_skip:
	cmp byte [esi], ' '
	jne .sflt_copy
	inc esi
	jmp .sflt_skip
.sflt_copy:
	call alloc_temp_string
	mov edi, eax
	mov ecx, STR_MAX_LEN
	call copy_str_n
	mov eax, [last_temp_string]
.sflt_ret:
	ret

string_func_rtrim:
	call expect_paren_string_expr
	cmp byte [run_error], 0
	jne .sfrt_ret
	mov esi, eax
	call alloc_temp_string
	mov edi, eax
	mov ecx, STR_MAX_LEN
	call copy_str_n
	mov esi, [last_temp_string]
	call rtrim_buffer
	mov eax, [last_temp_string]
.sfrt_ret:
	ret

string_func_inkey:
	cmp byte [esi], '('
	jne .sfik_fetch
	inc esi
	cmp byte [esi], ')'
	jne .sfik_err
	inc esi
.sfik_fetch:
	call alloc_temp_string
	mov edi, eax
	mov eax, SYS_READ_KEY
	int 0x80
	cmp eax, 0
	jne .sfik_char
	mov byte [edi], 0
	mov eax, [last_temp_string]
	ret
.sfik_char:
	mov [edi], al
	mov byte [edi + 1], 0
	mov eax, [last_temp_string]
	ret
.sfik_err:
	mov byte [run_error], ERR_SYNTAX
	xor eax, eax
	ret

string_func_hex:
	; HEX$(n) - returns uppercase hex string of n
	call expect_paren_expr
	cmp byte [run_error], 0
	jne .sfhex_ret
	mov [tmp_num_value], eax
	; Build hex string in num_write_buf
	mov edi, num_write_buf
	; Check for zero
	cmp dword [tmp_num_value], 0
	jne .sfhex_nonzero
	mov byte [edi], '0'
	mov byte [edi + 1], 0
	jmp .sfhex_copy
.sfhex_nonzero:
	; Build backwards using temp area
	push edi
	add edi, 10             ; point to end
	mov byte [edi], 0
	mov eax, [tmp_num_value]
.sfhex_loop:
	cmp eax, 0
	je .sfhex_done
	mov edx, eax
	and edx, 0x0F
	cmp dl, 10
	jl .sfhex_digit
	add dl, 'A' - 10
	jmp .sfhex_store
.sfhex_digit:
	add dl, '0'
.sfhex_store:
	dec edi
	mov [edi], dl
	shr eax, 4
	jmp .sfhex_loop
.sfhex_done:
	; edi points to start of hex digits; copy to front of num_write_buf
	mov esi, edi
	pop edi
.sfhex_cpy:
	mov al, [esi]
	mov [edi], al
	inc esi
	inc edi
	cmp al, 0
	jne .sfhex_cpy
.sfhex_copy:
	call alloc_temp_string
	mov edi, eax
	lea esi, [num_write_buf]
	mov ecx, STR_MAX_LEN
	call copy_str_n
	mov eax, [last_temp_string]
	ret
.sfhex_err:
	mov byte [run_error], ERR_SYNTAX
.sfhex_ret:
	xor eax, eax
	ret

string_func_oct:
	; OCT$(n) - returns octal string of n
	call expect_paren_expr
	cmp byte [run_error], 0
	jne .sfoct_ret
	mov [tmp_num_value], eax
	mov edi, num_write_buf
	cmp dword [tmp_num_value], 0
	jne .sfoct_nonzero
	mov byte [edi], '0'
	mov byte [edi + 1], 0
	jmp .sfoct_copy
.sfoct_nonzero:
	push edi
	add edi, 12
	mov byte [edi], 0
	mov eax, [tmp_num_value]
.sfoct_loop:
	cmp eax, 0
	je .sfoct_done
	mov edx, eax
	and edx, 7
	add dl, '0'
	dec edi
	mov [edi], dl
	shr eax, 3
	jmp .sfoct_loop
.sfoct_done:
	mov esi, edi
	pop edi
.sfoct_cpy:
	mov al, [esi]
	mov [edi], al
	inc esi
	inc edi
	cmp al, 0
	jne .sfoct_cpy
.sfoct_copy:
	call alloc_temp_string
	mov edi, eax
	lea esi, [num_write_buf]
	mov ecx, STR_MAX_LEN
	call copy_str_n
	mov eax, [last_temp_string]
	ret
.sfoct_err:
	mov byte [run_error], ERR_SYNTAX
.sfoct_ret:
	xor eax, eax
	ret

alloc_temp_string:
	mov eax, [temp_str_index]
	inc dword [temp_str_index]
	cmp dword [temp_str_index], TEMP_STR_COUNT
	jl .ats_ok
	mov dword [temp_str_index], 0
.ats_ok:
	imul eax, STR_MAX_LEN + 1
	lea eax, [temp_strings + eax]
	mov [last_temp_string], eax
	mov byte [eax], 0
	ret

strcat_limit:
	push eax
	push ebx
	push ecx
	push edx
	mov ebx, edi
	mov esi, edi
	call strlen
	lea edi, [ebx + ecx]
	mov edx, STR_MAX_LEN
	sub edx, ecx
	jle .scl_done
.scl_loop:
	lodsb
	cmp al, 0
	je .scl_zero
	mov [edi], al
	inc edi
	dec edx
	jnz .scl_loop
.scl_zero:
	mov byte [edi], 0
.scl_done:
	pop edx
	pop ecx
	pop ebx
	pop eax
	ret

collect_data_items:
	pushad
	mov dword [data_item_count], 0
	mov dword [data_pool_used], 0
	mov dword [data_read_idx], 0
	xor ebx, ebx
.cdi_line:
	cmp ebx, [line_count]
	jge .cdi_done
	mov eax, ebx
	call get_line_ptr
	mov esi, [line_text_ptr]
.cdi_stmt:
	call skip_spc
	cmp byte [esi], 0
	je .cdi_next_line
	push esi
	mov edi, kw_data
	call match_kw
	jc .cdi_collect
	pop esi
	call find_statement_end
	mov esi, eax
	cmp byte [esi], ':'
	jne .cdi_next_line
	inc esi
	jmp .cdi_stmt
.cdi_collect:
	add esp, 4
	call collect_data_statement_items
	cmp byte [run_error], 0
	jne .cdi_done
	call find_statement_end
	mov esi, eax
	cmp byte [esi], ':'
	jne .cdi_next_line
	inc esi
	jmp .cdi_stmt
.cdi_next_line:
	inc ebx
	jmp .cdi_line
.cdi_done:
	popad
	ret

collect_data_statement_items:
	call skip_spc
.cds_item:
	cmp byte [esi], 0
	je .cds_done
	cmp byte [esi], ':'
	je .cds_done
	cmp dword [data_item_count], DATA_ITEM_MAX
	jge .cds_mem
	cmp byte [esi], '"'
	je .cds_string
	mov edi, token_buf
.cds_num:
	mov al, [esi]
	cmp al, 0
	je .cds_num_done
	cmp al, ':'
	je .cds_num_done
	cmp al, ','
	je .cds_num_done
	mov [edi], al
	inc edi
	inc esi
	cmp edi, token_buf + STR_MAX_LEN
	jl .cds_num
.cds_num_done:
	mov byte [edi], 0
	mov esi, token_buf
	call rtrim_inplace
	mov eax, token_buf
	mov bl, 0
	call add_data_item
	cmp byte [run_error], 0
	jne .cds_done
	jmp .cds_cont
.cds_string:
	inc esi
	mov edi, token_buf
.cds_str:
	mov al, [esi]
	cmp al, 0
	je .cds_mem
	cmp al, '"'
	je .cds_str_done
	mov [edi], al
	inc edi
	inc esi
	cmp edi, token_buf + STR_MAX_LEN
	jl .cds_str
.cds_str_done:
	mov byte [edi], 0
	inc esi
	mov eax, token_buf
	mov bl, 1
	call add_data_item
	cmp byte [run_error], 0
	jne .cds_done
.cds_cont:
	call skip_spc
	cmp byte [esi], ','
	jne .cds_done
	inc esi
	call skip_spc
	jmp .cds_item
.cds_mem:
	mov byte [run_error], ERR_MEM
.cds_done:
	ret

add_data_item:
	pushad
	mov ecx, [data_item_count]
	mov [data_item_types + ecx], bl
	mov edx, [data_pool_used]
	mov [data_item_offsets + ecx * 4], edx
	lea edi, [data_pool + edx]
	mov esi, eax
.adi_copy:
	lodsb
	stosb
	inc edx
	cmp al, 0
	jne .adi_copy
	cmp edx, DATA_POOL_SIZE
	jg .adi_mem
	mov [data_pool_used], edx
	inc dword [data_item_count]
	popad
	ret
.adi_mem:
	popad
	mov byte [run_error], ERR_MEM
	ret

read_next_data_item:
	mov eax, [data_read_idx]
	cmp eax, [data_item_count]
	jge .rnd_err
	mov ecx, [data_item_offsets + eax * 4]
	lea eax, [data_pool + ecx]
	inc dword [data_read_idx]
	ret
.rnd_err:
	mov byte [run_error], ERR_READ
	xor eax, eax
	ret

cmd_load:
	pushad
	call parse_filename_arg
	cmp byte [run_error], 0
	jne .cl_done
	mov dword [line_count], 0
	mov eax, SYS_FREAD
	mov ebx, filename_tmp
	mov ecx, file_buffer
	int 0x80
	cmp eax, 0
	jle .cl_err
	mov esi, file_buffer
.cl_parse:
	cmp byte [esi], 0
	je .cl_ok
	mov edi, input_buf
	xor ecx, ecx
.cl_line:
	lodsb
	cmp al, 0
	je .cl_line_done
	cmp al, 0x0A
	je .cl_line_done
	cmp al, 0x0D
	je .cl_line
	mov [edi], al
	inc edi
	inc ecx
	cmp ecx, INPUT_BUF_LEN - 1
	jl .cl_line
.cl_line_done:
	mov byte [edi], 0
	cmp ecx, 0
	je .cl_parse
	push esi
	mov esi, input_buf
	mov al, [esi]
	cmp al, '0'
	jl .cl_skip
	cmp al, '9'
	jg .cl_skip
	call parse_linenum
	call store_line
.cl_skip:
	pop esi
	cmp byte [run_error], 0
	jne .cl_done
	jmp .cl_parse
.cl_ok:
	mov eax, SYS_PRINT
	mov ebx, msg_loaded
	int 0x80
	jmp .cl_done
.cl_err:
	mov byte [run_error], ERR_FILE
.cl_done:
	popad
	ret

cmd_load_from_args:
	pushad
	mov esi, input_buf
	call skip_spc
	mov edi, filename_tmp
	mov ecx, 63
	call copy_str_n
	popad
	jmp cmd_load

cmd_save:
	pushad
	call parse_filename_arg
	cmp byte [run_error], 0
	jne .cs_done
	mov edi, file_buffer
	xor edx, edx
	xor ebx, ebx
.cs_loop:
	cmp ebx, [line_count]
	jge .cs_write
	mov eax, ebx
	call get_line_ptr
	mov eax, [line_entry_ptr]
	mov eax, [eax]
	mov [tmp_num_value], eax
	call write_dec_to_buf
	mov esi, num_write_buf
.cs_num:
	lodsb
	cmp al, 0
	je .cs_space
	mov [edi], al
	inc edi
	inc edx
	jmp .cs_num
.cs_space:
	mov byte [edi], ' '
	inc edi
	inc edx
	mov esi, [line_text_ptr]
.cs_txt:
	lodsb
	cmp al, 0
	je .cs_nl
	mov [edi], al
	inc edi
	inc edx
	jmp .cs_txt
.cs_nl:
	mov byte [edi], 0x0A
	inc edi
	inc edx
	inc ebx
	jmp .cs_loop
.cs_write:
	mov eax, SYS_FWRITE
	mov ebx, filename_tmp
	mov ecx, file_buffer
	int 0x80
	cmp eax, 0
	jl .cs_err
	mov eax, SYS_PRINT
	mov ebx, msg_saved_file
	int 0x80
	jmp .cs_done
.cs_err:
	mov byte [run_error], ERR_FILE
.cs_done:
	popad
	ret

parse_filename_arg:
	call skip_spc
	cmp byte [esi], '"'
	jne .pfa_plain
	inc esi
	mov edi, filename_tmp
.pfa_q:
	lodsb
	cmp al, 0
	je .pfa_done
	cmp al, '"'
	je .pfa_done
	stosb
	jmp .pfa_q
.pfa_plain:
	mov edi, filename_tmp
.pfa_p:
	lodsb
	cmp al, 0
	je .pfa_done
	cmp al, ' '
	je .pfa_done
	stosb
	jmp .pfa_p
.pfa_done:
	mov byte [edi], 0
	cmp byte [filename_tmp], 0
	jne .pfa_ret
	mov byte [run_error], ERR_FILE
.pfa_ret:
	ret

parse_int_simple:
	call skip_spc
	xor ebx, ebx
	cmp byte [esi], '-'
	jne .pis_digits
	mov bl, 1
	inc esi
.pis_digits:
	xor eax, eax
	xor edx, edx
	cmp byte [esi], '0'
	jl .pis_err
	cmp byte [esi], '9'
	jg .pis_err
.pis_loop:
	movzx edx, byte [esi]
	cmp dl, '0'
	jl .pis_done
	cmp dl, '9'
	jg .pis_done
	imul eax, 10
	sub dl, '0'
	add eax, edx
	inc esi
	jmp .pis_loop
.pis_done:
	cmp bl, 0
	je .pis_ret
	neg eax
.pis_ret:
	ret
.pis_err:
	mov byte [run_error], ERR_SYNTAX
	xor eax, eax
	ret

strlen:
	xor ecx, ecx
.strl_loop:
	cmp byte [esi + ecx], 0
	je .strl_done
	inc ecx
	jmp .strl_loop
.strl_done:
	ret

rtrim_inplace:
	push eax
	push ecx
	push edi
	mov edi, esi
	call strlen
	cmp ecx, 0
	je .rti_done
	lea edi, [esi + ecx - 1]
.rti_loop:
	cmp edi, esi
	jb .rti_done
	cmp byte [edi], ' '
	jne .rti_done
	mov byte [edi], 0
	dec edi
	jmp .rti_loop
.rti_done:
	pop edi
	pop ecx
	pop eax
	ret

rtrim_buffer:
	push eax
	push ecx
	push edi
	mov edi, esi
	call strlen
	cmp ecx, 0
	je .rtb_done
	lea edi, [esi + ecx - 1]
.rtb_loop:
	cmp edi, esi
	jb .rtb_done
	cmp byte [edi], ' '
	jne .rtb_done
	mov byte [edi], 0
	dec edi
	jmp .rtb_loop
.rtb_done:
	pop edi
	pop ecx
	pop eax
	ret

write_signed_to_string:
	pushad
	mov edi, [last_temp_string]
	mov eax, [tmp_num_value]
	test eax, eax
	jns .wsts_pos
	mov byte [edi], '-'
	inc edi
	neg eax
.wsts_pos:
	mov [tmp_num_value], eax
	call write_dec_to_buf
	mov esi, num_write_buf
	mov ecx, STR_MAX_LEN
	call copy_str_n
	popad
	ret

write_dec_to_buf:
	pushad
	mov edi, num_write_buf
	mov eax, [tmp_num_value]
	xor ecx, ecx
	mov ebx, 10
	test eax, eax
	jnz .wdb_push
	mov byte [edi], '0'
	mov byte [edi + 1], 0
	popad
	ret
.wdb_push:
	xor edx, edx
	div ebx
	push edx
	inc ecx
	test eax, eax
	jnz .wdb_push
.wdb_pop:
	pop eax
	add al, '0'
	stosb
	dec ecx
	jnz .wdb_pop
	mov byte [edi], 0
	popad
	ret

print_signed:
	pushad
	test eax, eax
	jns .ps_pos
	push eax
	mov eax, SYS_PUTCHAR
	mov ebx, '-'
	int 0x80
	pop eax
	neg eax
.ps_pos:
	call print_dec
	popad
	ret

print_error:
	pushad
	mov eax, SYS_SETCOLOR
	mov ebx, 0x0C
	int 0x80
	movzx eax, byte [run_error]
	cmp eax, ERR_SYNTAX
	je .pe_syntax
	cmp eax, ERR_DIV0
	je .pe_div0
	cmp eax, ERR_LINE
	je .pe_line
	cmp eax, ERR_GOSUB
	je .pe_gosub
	cmp eax, ERR_RETURN
	je .pe_return
	cmp eax, ERR_FOR
	je .pe_for
	cmp eax, ERR_MEM
	je .pe_mem
	cmp eax, ERR_FILE
	je .pe_file
	cmp eax, ERR_READ
	je .pe_read
	cmp eax, ERR_WEND
	je .pe_wend
	cmp eax, ERR_WHILE
	je .pe_while
	cmp eax, ERR_TYPE
	je .pe_type
	mov ebx, err_generic_msg
	jmp .pe_print
.pe_syntax:
	mov ebx, err_syntax_msg
	jmp .pe_print
.pe_div0:
	mov ebx, err_div0_msg
	jmp .pe_print
.pe_line:
	mov ebx, err_line_msg
	jmp .pe_print
.pe_gosub:
	mov ebx, err_gosub_msg
	jmp .pe_print
.pe_return:
	mov ebx, err_return_msg
	jmp .pe_print
.pe_for:
	mov ebx, err_for_msg
	jmp .pe_print
.pe_mem:
	mov ebx, err_mem_msg
	jmp .pe_print
.pe_file:
	mov ebx, err_file_msg
	jmp .pe_print
.pe_read:
	mov ebx, err_read_msg
	jmp .pe_print
.pe_wend:
	mov ebx, err_wend_msg
	jmp .pe_print
.pe_while:
	mov ebx, err_while_msg
	jmp .pe_print
.pe_type:
	mov ebx, err_type_msg
.pe_print:
	mov eax, SYS_PRINT
	int 0x80
	mov eax, SYS_SETCOLOR
	mov ebx, 0x07
	int 0x80
	popad
	ret

print_error_with_line:
	pushad
	call print_error
	mov eax, [current_line_idx]
	cmp eax, [line_count]
	jge .pewl_done
	call get_line_ptr
	mov eax, [line_entry_ptr]
	mov eax, [eax]
	push eax
	mov eax, SYS_PRINT
	mov ebx, msg_at_line
	int 0x80
	pop eax
	call print_dec
	mov eax, SYS_PUTCHAR
	mov ebx, 0x0A
	int 0x80
.pewl_done:
	popad
	ret

reset_runtime_state:
	mov byte [run_error], 0
	mov byte [goto_flag], 0
	mov byte [resume_flag], 0
	mov byte [end_flag], 0
	mov dword [gosub_sp], 0
	mov dword [for_sp], 0
	mov dword [while_sp], 0
	mov dword [data_read_idx], 0
	mov dword [temp_str_index], 0
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

int_sqrt:
	cmp eax, 0
	jge .is_go
	xor eax, eax
	ret
.is_go:
	mov ebx, 0
	mov ecx, eax
	mov edx, 1 << 30
.is_align:
	cmp edx, ecx
	jle .is_loop
	shr edx, 2
	jmp .is_align
.is_loop:
	cmp edx, 0
	je .is_done
	mov eax, ebx
	add eax, edx
	cmp ecx, eax
	jl .is_skip
	sub ecx, eax
	shr ebx, 1
	add ebx, edx
	jmp .is_next
.is_skip:
	shr ebx, 1
.is_next:
	shr edx, 2
	jmp .is_loop
.is_done:
	mov eax, ebx
	ret

math_sin:
	push eax
	fild dword [esp]
	fsin
	fimul dword [math_scale]
	fistp dword [math_result]
	pop eax
	mov eax, [math_result]
	ret

math_cos:
	push eax
	fild dword [esp]
	fcos
	fimul dword [math_scale]
	fistp dword [math_result]
	pop eax
	mov eax, [math_result]
	ret

math_tan:
	push eax
	fild dword [esp]
	fptan
	fstp st0
	fimul dword [math_scale]
	fistp dword [math_result]
	pop eax
	mov eax, [math_result]
	ret

math_atn:
	push eax
	fld1
	fild dword [esp]
	fpatan
	fimul dword [math_scale]
	fistp dword [math_result]
	pop eax
	mov eax, [math_result]
	ret

math_log:
	cmp eax, 0
	jg .ml_go
	xor eax, eax
	ret
.ml_go:
	push eax
	fldln2
	fild dword [esp]
	fyl2x
	fimul dword [math_scale]
	fistp dword [math_result]
	pop eax
	mov eax, [math_result]
	ret

math_exp:
	cmp eax, 0
	jge .me_go
	xor eax, eax
	ret
.me_go:
	push eax
	fild dword [esp]
	fidiv dword [math_scale]
	fldl2e
	fmulp st1, st0
	fld st0
	frndint
	fsub st1, st0
	fxch st1
	f2xm1
	fld1
	faddp st1, st0
	fscale
	fstp st1
	fimul dword [math_scale]
	fistp dword [math_result]
	pop eax
	mov eax, [math_result]
	ret

instr_search:
	push edi
	push ecx
	mov edi, ebx
	mov esi, ebx
	call strlen
	mov edx, ecx
	mov esi, [instr_hay_ptr]
	mov ecx, 1
.is_outer:
	cmp byte [esi], 0
	je .is_nf
	push esi
	push edi
	mov ebx, edx
.is_inner:
	cmp ebx, 0
	je .is_found
	mov al, [esi]
	mov ah, [edi]
	cmp ah, 0
	je .is_found
	cmp al, ah
	jne .is_mismatch
	inc esi
	inc edi
	dec ebx
	jmp .is_inner
.is_mismatch:
	pop edi
	pop esi
	inc esi
	inc ecx
	jmp .is_outer
.is_found:
	pop edi
	pop esi
	mov eax, ecx
	jmp .is_done
.is_nf:
	xor eax, eax
.is_done:
	pop ecx
	pop edi
	ret

kw_print:       db "PRINT", 0
kw_input:       db "INPUT", 0
kw_line:        db "LINE", 0
kw_let:         db "LET", 0
kw_if:          db "IF", 0
kw_then:        db "THEN", 0
kw_else:        db "ELSE", 0
kw_on:          db "ON", 0
kw_goto:        db "GOTO", 0
kw_gosub:       db "GOSUB", 0
kw_return:      db "RETURN", 0
kw_for:         db "FOR", 0
kw_to:          db "TO", 0
kw_step:        db "STEP", 0
kw_next:        db "NEXT", 0
kw_while:       db "WHILE", 0
kw_wend:        db "WEND", 0
kw_end:         db "END", 0
kw_rem:         db "REM", 0
kw_cls:         db "CLS", 0
kw_color:       db "COLOR", 0
kw_beep:        db "BEEP", 0
kw_poke:        db "POKE", 0
kw_sleep:       db "SLEEP", 0
kw_dim:         db "DIM", 0
kw_data:        db "DATA", 0
kw_read:        db "READ", 0
kw_restore:     db "RESTORE", 0
kw_swap:        db "SWAP", 0
kw_locate:      db "LOCATE", 0
kw_help:        db "HELP", 0
kw_run:         db "RUN", 0
kw_list:        db "LIST", 0
kw_new:         db "NEW", 0
kw_load:        db "LOAD", 0
kw_save:        db "SAVE", 0
kw_system:      db "SYSTEM", 0
kw_rnd:         db "RND", 0
kw_peek:        db "PEEK", 0
kw_abs:         db "ABS", 0
kw_int:         db "INT", 0
kw_sgn:         db "SGN", 0
kw_sqr:         db "SQR", 0
kw_sin:         db "SIN", 0
kw_cos:         db "COS", 0
kw_tan:         db "TAN", 0
kw_atn:         db "ATN", 0
kw_log:         db "LOG", 0
kw_exp:         db "EXP", 0
kw_time:        db "TIME", 0
kw_asc:         db "ASC", 0
kw_len:         db "LEN", 0
kw_val:         db "VAL", 0
kw_instr:       db "INSTR", 0
kw_lefts:       db "LEFT$", 0
kw_rights:      db "RIGHT$", 0
kw_mids:        db "MID$", 0
kw_chrs:        db "CHR$", 0
kw_strs:        db "STR$", 0
kw_ltrims:      db "LTRIM$", 0
kw_rtrims:      db "RTRIM$", 0
kw_inkeys:      db "INKEY$", 0
kw_tab:         db "TAB", 0
kw_spc:         db "SPC", 0
kw_tron:        db "TRON", 0
kw_troff:       db "TROFF", 0
kw_stop:        db "STOP", 0
kw_cont:        db "CONT", 0
kw_hexs:        db "HEX$", 0
kw_octs:        db "OCT$", 0

msg_banner:     db "Mellivora BASIC v3.1 (GW-BASIC compatible)", 0x0A
		db "=========================================", 0x0A
		db "Type HELP for commands", 0x0A, 0
msg_ready:      db "Ready.", 0x0A, 0
msg_prompt:     db "] ", 0
msg_input_prompt: db "? ", 0
msg_at_line:    db " at line ", 0
msg_loaded:     db "Loaded.", 0x0A, 0
msg_saved_file: db "Saved.", 0x0A, 0
msg_help:       db "Commands: PRINT, INPUT, LINE INPUT, LET, IF/THEN/ELSE, GOTO, GOSUB, RETURN, FOR/NEXT, WHILE/WEND, ON GOTO/GOSUB, DATA/READ/RESTORE, DIM, SWAP, LOCATE, CLS, COLOR, BEEP, POKE, SLEEP, STOP, CONT, TRON, TROFF, RUN, LIST, NEW, LOAD, SAVE, SYSTEM", 0x0A
		db "Functions: RND, ABS, INT, SGN, SQR, SIN, COS, TAN, ATN, LOG, EXP, ASC, LEN, VAL, PEEK, TIME, INSTR, LEFT$, RIGHT$, MID$, CHR$, STR$, HEX$, OCT$, LTRIM$, RTRIM$, INKEY$", 0x0A, 0

err_syntax_msg: db "?SYNTAX ERROR", 0x0A, 0
err_div0_msg:   db "?DIVISION BY ZERO", 0x0A, 0
err_line_msg:   db "?UNDEFINED LINE", 0x0A, 0
err_gosub_msg:  db "?GOSUB STACK OVERFLOW", 0x0A, 0
err_return_msg: db "?RETURN WITHOUT GOSUB", 0x0A, 0
err_for_msg:    db "?FOR/NEXT ERROR", 0x0A, 0
err_mem_msg:    db "?OUT OF MEMORY", 0x0A, 0
err_file_msg:   db "?FILE ERROR", 0x0A, 0
err_read_msg:   db "?OUT OF DATA", 0x0A, 0
err_wend_msg:   db "?WEND ERROR", 0x0A, 0
err_while_msg:  db "?WHILE ERROR", 0x0A, 0
err_type_msg:   db "?TYPE MISMATCH", 0x0A, 0
err_generic_msg: db "?ERROR", 0x0A, 0

msg_break:      db "Break in line ", 0
msg_cant_cont:  db "?Can't continue", 0x0A, 0

variables:      times 26 dd 0
string_vars:    times 26 * (STR_MAX_LEN + 1) db 0
array_sizes:    times ARRAY_COUNT dd 0
numeric_arrays: times ARRAY_COUNT * ARRAY_MAX_SIZE dd 0
trace_mode:     db 0
stop_flag:      db 0
stop_line_idx:  dd 0
stop_stmt_off:  dd 0
rand_seed:      dd 12345
line_count:     dd 0
current_line_idx: dd 0
current_stmt_offset: dd 0
goto_target:    dd 0
goto_flag:      db 0
resume_flag:    db 0
end_flag:       db 0
run_error:      db 0
resume_line_idx: dd 0
resume_stmt_offset: dd 0
gosub_sp:       dd 0
gosub_stack:    times GOSUB_DEPTH * 2 dd 0
for_sp:         dd 0
for_stack:      times FOR_DEPTH * 5 dd 0
while_sp:       dd 0
while_stack:    times WHILE_DEPTH * 2 dd 0
data_item_count: dd 0
data_read_idx:  dd 0
data_pool_used: dd 0
data_item_offsets: times DATA_ITEM_MAX dd 0
data_item_types: times DATA_ITEM_MAX db 0
data_pool:      times DATA_POOL_SIZE db 0
input_buf:      times INPUT_BUF_LEN + 1 db 0
filename_tmp:   times 64 db 0
program_area:   times PROG_SIZE db 0
file_buffer:    times FILE_BUFFER_SIZE db 0
temp_strings:   times TEMP_STR_COUNT * (STR_MAX_LEN + 1) db 0
temp_str_index: dd 0
last_temp_string: dd 0
temp_string_copy: times STR_MAX_LEN + 1 db 0
token_buf:      times STR_MAX_LEN + 1 db 0
num_write_buf:  times 32 db 0
var_ref_kind:   dd 0
var_ref_ptr:    dd 0
var_ref_index:  dd 0
seq_base_ptr:   dd 0
seq_cur_ptr:    dd 0
seq_end_ptr:    dd 0
line_entry_ptr: dd 0
line_text_ptr:  dd 0
print_need_newline: db 0
relop_code:     db 0
on_mode:        db 0
scan_found_end: db 0
if_condition_value: dd 0
if_then_ptr:    dd 0
if_else_ptr:    dd 0
on_index:       dd 0
for_tmp_end:    dd 0
for_tmp_step:   dd 0
swap_kind:      dd 0
swap_ptr_a:     dd 0
func_str_ptr:   dd 0
func_num_a:     dd 0
func_num_b:     dd 0
str_expr_result: dd 0
instr_hay_ptr:  dd 0
scan_nesting:   dd 0
scan_line_idx:  dd 0
scan_stmt_offset: dd 0
tmp_num_value:  dd 0
math_scale:     dd 1000
math_result:    dd 0
