;=======================================================================
; vbe_ui.inc - Mellivora OS shared VBE UI helpers
;
; Common UI widgets that were being re-implemented in every VBE program:
;   vbe_ui_header_bar    Top band with title + right-aligned subtitle
;   vbe_ui_status_bar    Bottom band with help / status text
;   vbe_ui_modal         Centered text overlay (game-over, help, dialogs)
;   vbe_ui_input_line    Decimal-number input widget (read-and-edit)
;
; All routines preserve registers via pushad/popad. They draw to the
; shadow buffer; the caller is responsible for VBE_GAME_PRESENT.
;
; Requires: lib/vbe.inc, lib/font.inc, lib/palette.inc, syscalls.inc
;=======================================================================

%ifndef MV_VBE_UI_INC
%define MV_VBE_UI_INC

%include "lib/palette.inc"

; -----------------------------------------------------------------------
; vbe_ui_header_bar - Draw a header band across the top of the screen.
;   EDX = pointer to title string (uppercase, NUL-terminated)
;   ESI = pointer to right-aligned subtitle (NUL-term, may be NULL)
; Band height: 22 px. Title at scale=2 left-aligned; subtitle scale=1.
; -----------------------------------------------------------------------
vbe_ui_header_bar:
        pushad
        mov  [.title], edx
        mov  [.sub],   esi

        ; Background band
        xor  ebx, ebx
        xor  ecx, ecx
        mov  edx, [fb_width]
        mov  esi, 22
        mov  edi, MV_BG_BAND
        call vbe_fill_rect

        ; Title (left, scale 2 -> 10x14 px chars)
        mov  ebx, 10
        mov  ecx, 4
        mov  edx, [.title]
        mov  esi, MV_HUD_FG
        mov  eax, 1
        call vbe_draw_str

        ; Subtitle right-aligned at scale 1 (5x7 px char + 1px gap = 6 px)
        cmp  dword [.sub], 0
        je   .vuh_done
        mov  esi, [.sub]
        xor  ecx, ecx           ; length counter
.vuh_lp:
        cmp  byte [esi + ecx], 0
        je   .vuh_lp_done
        inc  ecx
        jmp  .vuh_lp
.vuh_lp_done:
        imul ecx, 6              ; pixel width
        mov  ebx, [fb_width]
        sub  ebx, ecx
        sub  ebx, 10             ; right margin
        mov  ecx, 8
        mov  edx, [.sub]
        mov  esi, MV_HUD_FG_DIM
        mov  eax, 1
        call vbe_draw_str
.vuh_done:
        popad
        ret
.title: dd 0
.sub:   dd 0

; -----------------------------------------------------------------------
; vbe_ui_status_bar - Draw a status band across the bottom of the screen.
;   EDX = pointer to hint / status string (NUL-terminated)
; Band height: 18 px. Text scale=1, dim color.
; -----------------------------------------------------------------------
vbe_ui_status_bar:
        pushad
        mov  [.text], edx

        ; Background band at the bottom
        xor  ebx, ebx
        mov  ecx, [fb_height]
        sub  ecx, 18
        mov  edx, [fb_width]
        mov  esi, 18
        mov  edi, MV_BG_BAND_DIM
        call vbe_fill_rect

        ; Text
        mov  ebx, 10
        mov  ecx, [fb_height]
        sub  ecx, 13
        mov  edx, [.text]
        mov  esi, MV_FG_DIM
        mov  eax, 1
        call vbe_draw_str

        popad
        ret
.text: dd 0

; -----------------------------------------------------------------------
; vbe_ui_modal - Draw a centered modal dialog.
;   EDX = pointer to title (uppercase NUL-term)
;   ESI = pointer to body text (uppercase NUL-term, single line for now)
;   EDI = accent color for title (e.g. MV_STATUS_OK for win,
;         MV_STATUS_ERR for game over, MV_ACCENT_YELLOW for info)
; Renders an 8 px-padded box centered horizontally near the middle.
; -----------------------------------------------------------------------
vbe_ui_modal:
        pushad
        mov  [.title], edx
        mov  [.body],  esi
        mov  [.color], edi

        ; Compute widths (length * char-width)
        mov  esi, [.title]
        call .strlen
        imul eax, 12             ; title at scale 2 -> 10+2 px
        mov  [.tw], eax

        mov  esi, [.body]
        call .strlen
        imul eax, 6              ; body at scale 1 -> 5+1 px
        mov  [.bw], eax

        ; Box width = max(tw, bw) + 40 padding
        mov  eax, [.tw]
        cmp  eax, [.bw]
        jge  .vum_use_t
        mov  eax, [.bw]
.vum_use_t:
        add  eax, 40
        mov  [.boxw], eax

        ; Box height: 22 (title) + 14 (body) + 24 (padding) = 60
        mov  dword [.boxh], 60

        ; Box position (centered)
        mov  eax, [fb_width]
        sub  eax, [.boxw]
        shr  eax, 1
        mov  [.boxx], eax
        mov  eax, [fb_height]
        sub  eax, [.boxh]
        shr  eax, 1
        mov  [.boxy], eax

        ; Drop shadow (4 px offset, near-black)
        mov  ebx, [.boxx]
        add  ebx, 4
        mov  ecx, [.boxy]
        add  ecx, 4
        mov  edx, [.boxw]
        mov  esi, [.boxh]
        mov  edi, MV_BG_BLACK
        call vbe_fill_rect

        ; Modal background
        mov  ebx, [.boxx]
        mov  ecx, [.boxy]
        mov  edx, [.boxw]
        mov  esi, [.boxh]
        mov  edi, MV_BG_MODAL
        call vbe_fill_rect

        ; Top band inside modal
        mov  ebx, [.boxx]
        mov  ecx, [.boxy]
        mov  edx, [.boxw]
        mov  esi, 22
        mov  edi, MV_BG_BAND
        call vbe_fill_rect

        ; Title text (centered horizontally inside box)
        mov  eax, [.boxw]
        sub  eax, [.tw]
        shr  eax, 1
        add  eax, [.boxx]
        mov  ebx, eax
        mov  ecx, [.boxy]
        add  ecx, 4
        mov  edx, [.title]
        mov  esi, [.color]
        mov  eax, 2
        call vbe_draw_str

        ; Body text (centered)
        mov  eax, [.boxw]
        sub  eax, [.bw]
        shr  eax, 1
        add  eax, [.boxx]
        mov  ebx, eax
        mov  ecx, [.boxy]
        add  ecx, 32
        mov  edx, [.body]
        mov  esi, MV_FG_BRIGHT
        mov  eax, 1
        call vbe_draw_str

        popad
        ret

.strlen:                          ; ESI=str -> EAX=length
        push esi
        xor  eax, eax
        cmp  esi, 0
        je   .sl_done
.sl_loop:
        cmp  byte [esi], 0
        je   .sl_done
        inc  eax
        inc  esi
        jmp  .sl_loop
.sl_done:
        pop  esi
        ret

.title: dd 0
.body:  dd 0
.color: dd 0
.tw:    dd 0
.bw:    dd 0
.boxw:  dd 0
.boxh:  dd 0
.boxx:  dd 0
.boxy:  dd 0

; -----------------------------------------------------------------------
; vbe_ui_input_line - Decimal-number input widget.
;
; Inputs (memory; set before call):
;   [vbe_ui_input_x]     Pixel X of input field
;   [vbe_ui_input_y]     Pixel Y of input field
;   [vbe_ui_input_max]   Maximum number of digits (1..10)
;
; Behavior:
;   * Loops on SYS_READ_KEY (blocking).
;   * Echos digits at (x,y), draws a thin cursor bar after them.
;   * BACKSPACE removes last digit. ENTER finishes input.
;   * Calls VBE_GAME_PRESENT internally on each redraw.
;
; Returns:
;   EAX = parsed unsigned integer (0 on Enter with empty input).
; Clobbers: nothing else (uses pushad/popad).
; -----------------------------------------------------------------------
vbe_ui_input_line:
        pushad
        ; Reset buffer
        xor  eax, eax
        mov  [vbe_ui_input_len], eax
        mov  byte [vbe_ui_input_buf], 0

.vil_redraw:
        ; Clear input area: max_digits * 6 px wide, 12 px tall
        mov  ebx, [vbe_ui_input_x]
        mov  ecx, [vbe_ui_input_y]
        mov  edx, [vbe_ui_input_max]
        imul edx, 6
        add  edx, 8                 ; cursor bar room
        mov  esi, 12
        mov  edi, MV_BG_DARK
        call vbe_fill_rect

        ; Draw current digits
        mov  ebx, [vbe_ui_input_x]
        mov  ecx, [vbe_ui_input_y]
        mov  edx, vbe_ui_input_buf
        mov  esi, MV_FG_WHITE
        mov  eax, 1
        call vbe_draw_str

        ; Cursor bar after digits
        mov  eax, [vbe_ui_input_len]
        imul eax, 6
        add  eax, [vbe_ui_input_x]
        mov  ebx, eax
        mov  ecx, [vbe_ui_input_y]
        mov  edx, 5
        mov  esi, 10
        mov  edi, MV_CURSOR
        call vbe_fill_rect

        VBE_GAME_PRESENT

        ; Wait for a key (blocking)
        mov  eax, 2                 ; SYS_GETCHAR (blocking)
        int  0x80

        cmp  al, 0x0D
        je   .vil_done
        cmp  al, 0x0A
        je   .vil_done
        cmp  al, 0x08
        je   .vil_bs
        cmp  al, 0x7F
        je   .vil_bs
        cmp  al, '0'
        jb   .vil_redraw
        cmp  al, '9'
        ja   .vil_redraw

        mov  ecx, [vbe_ui_input_len]
        cmp  ecx, [vbe_ui_input_max]
        jge  .vil_redraw
        mov  edi, vbe_ui_input_buf
        mov  [edi + ecx], al
        inc  ecx
        mov  byte [edi + ecx], 0
        mov  [vbe_ui_input_len], ecx
        jmp  .vil_redraw

.vil_bs:
        mov  ecx, [vbe_ui_input_len]
        test ecx, ecx
        jz   .vil_redraw
        dec  ecx
        mov  [vbe_ui_input_len], ecx
        mov  edi, vbe_ui_input_buf
        mov  byte [edi + ecx], 0
        jmp  .vil_redraw

.vil_done:
        ; Parse decimal
        mov  esi, vbe_ui_input_buf
        xor  eax, eax
.vil_p:
        movzx ebx, byte [esi]
        cmp  bl, 0
        je   .vil_pdone
        cmp  bl, '0'
        jb   .vil_pdone
        cmp  bl, '9'
        ja   .vil_pdone
        imul eax, 10
        sub  bl, '0'
        add  eax, ebx
        inc  esi
        jmp  .vil_p
.vil_pdone:
        mov  [vbe_ui_input_result], eax
        popad
        mov  eax, [vbe_ui_input_result]
        ret

; ---- Module data (flat-binary safe: dd 0 / times N db 0) --------------
vbe_ui_input_x:      dd 0
vbe_ui_input_y:      dd 0
vbe_ui_input_max:    dd 6
vbe_ui_input_len:    dd 0
vbe_ui_input_result: dd 0
vbe_ui_input_buf:    times 16 db 0

%endif ; MV_VBE_UI_INC
