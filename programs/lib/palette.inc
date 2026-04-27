;=======================================================================
; palette.inc - Mellivora OS shared color palette (VBE 32-bpp 0x00RRGGBB)
;
; Single source of truth for app colors. Use these constants instead of
; hard-coding hex literals so visual consistency is maintained across
; the suite. Existing per-program COL_* aliases can keep their names by
; adding `equ MV_*` after including this file.
;
; Color naming:
;   MV_BG_*        Background tones (darkest -> lighter)
;   MV_FG_*        Foreground / text tones
;   MV_ACCENT_*    UI accents and highlights
;   MV_STATUS_*    Status / state colors (ok, warn, err, info)
;   MV_BOARD_*    Board / game-piece classics (chess, checkers, etc.)
;   MV_HUD_*       Header / status-bar band tones
;
; If a game has a strong thematic color (e.g. doomfire), keep it local;
; this palette only standardizes the *common* UI tones.
;=======================================================================

%ifndef MV_PALETTE_INC
%define MV_PALETTE_INC

; ---- Backgrounds ---------------------------------------------------------
MV_BG_BLACK        equ 0x00000000   ; pure black (rare)
MV_BG_DEEP         equ 0x00080808   ; near-black (intro screens, modals)
MV_BG_DARK         equ 0x00121212   ; STANDARD app background
MV_BG_PANEL        equ 0x001A1A1A   ; raised panel (one step lighter than BG)
MV_BG_BAND         equ 0x00224466   ; header / status band (steel blue)
MV_BG_BAND_DIM     equ 0x00112233   ; dim variant (status bar)
MV_BG_MODAL        equ 0x00181828   ; dialog / overlay background
MV_BG_BOARD        equ 0x00145228   ; classic green (chess/reversi/checkers)

; ---- Foregrounds (text) --------------------------------------------------
MV_FG_WHITE        equ 0x00FFFFFF   ; primary text
MV_FG_BRIGHT       equ 0x00EEEEEE   ; STANDARD text (slightly off-white)
MV_FG_NORMAL       equ 0x00CCCCCC   ; secondary text
MV_FG_DIM          equ 0x00888888   ; hint / footer text
MV_FG_DARK         equ 0x00444444   ; very-dim / disabled
MV_FG_GRID         equ 0x00224433   ; grid / cell border on dark BG

; ---- Accents -------------------------------------------------------------
MV_ACCENT_YELLOW   equ 0x00FFE040   ; primary accent (titles, cursor)
MV_ACCENT_AMBER    equ 0x00FFAA22   ; warm accent
MV_ACCENT_CYAN     equ 0x0044CCEE   ; cool accent (info, links)
MV_ACCENT_MAGENTA  equ 0x00CC44AA   ; secondary highlight
MV_ACCENT_LIME     equ 0x0088FF44   ; focus / selection halo

; ---- Status feedback -----------------------------------------------------
MV_STATUS_OK       equ 0x0033CC55   ; success / valid move
MV_STATUS_WARN     equ 0x00FFAA22   ; caution
MV_STATUS_ERR      equ 0x00FF4444   ; error / illegal move
MV_STATUS_INFO     equ 0x0044AAFF   ; informational

; ---- Cursor / selection --------------------------------------------------
MV_CURSOR          equ 0x00FFEE44   ; cursor outline
MV_CURSOR_FILL     equ 0x00665533   ; cursor inner fill (dim version)
MV_HINT            equ 0x003A8A3A   ; valid-move hint dot

; ---- Board / piece classics ---------------------------------------------
MV_PIECE_BLACK     equ 0x00111111   ; black piece (chess/reversi)
MV_PIECE_WHITE     equ 0x00EEEEEE   ; white piece
MV_BOARD_LIGHT     equ 0x00D4A96A   ; chess light square
MV_BOARD_DARK      equ 0x008B5A2B   ; chess dark square

; ---- HUD / band text colors --------------------------------------------
MV_HUD_FG          equ 0x00FFFFFF   ; text on header band (white)
MV_HUD_FG_DIM      equ 0x00BBCCDD   ; secondary text on header band

%endif ; MV_PALETTE_INC
