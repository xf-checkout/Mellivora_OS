; rogue.asm - ASCII Roguelike Dungeon Crawler for Mellivora OS
; VBE 1024x768. Arrow keys/hjkl to move, q=quit, ?=help.
%include "syscalls.inc"
%include "lib/vbe_game.inc"
%include "lib/font.inc"
%include "lib/audio.inc"
%include "lib/highscore.inc"

; VBE tile rendering
CELL_SZ         equ 11
MAP_DRAW_X      equ 72
MAP_DRAW_Y      equ 20
STAT_Y          equ 280
MSG_Y           equ 300

; Tile colors (0x00RRGGBB)
COL_VOID        equ 0x00111111
COL_WALL        equ 0x00556655
COL_FLOOR       equ 0x00333333
COL_DOOR        equ 0x00AA7733
COL_STAIRS      equ 0x00FFEE00
COL_PLAYER      equ 0x0000FFAA
COL_MON_DEF     equ 0x00FF4444
COL_MON_GRN     equ 0x0044FF44
COL_MON_BLU     equ 0x004444FF
COL_MON_PUR     equ 0x00CC44CC
COL_MON_YEL     equ 0x00FFCC00
COL_ITEM_POT    equ 0x00FF44FF
COL_ITEM_GOLD   equ 0x00FFEE00
COL_ITEM_SWD    equ 0x00FFFFFF
COL_ITEM_ARM    equ 0x0044CCFF
COL_STAT        equ 0x00CCCCCC
COL_MSG         equ 0x00FFDD44
COL_BG          equ 0x00111111

; Map constants
MAP_W           equ 80
MAP_H           equ 23          ; Rows 0-22 for map, 23 for stats, 24 for messages
MAX_ROOMS       equ 9
MAX_MONSTERS    equ 20
MAX_ITEMS       equ 12
ROOM_MIN_W      equ 5
ROOM_MAX_W      equ 14
ROOM_MIN_H      equ 3
ROOM_MAX_H      equ 7

; Tile types
TILE_VOID       equ 0
TILE_WALL       equ 1
TILE_FLOOR      equ 2
TILE_DOOR       equ 3
TILE_CORRIDOR   equ 4
TILE_STAIRS     equ 5

; Monster types
MON_NONE        equ 0
MON_RAT         equ 1
MON_BAT         equ 2
MON_SNAKE       equ 3
MON_GOBLIN      equ 4
MON_ORC         equ 5
MON_TROLL       equ 6

; Item types
ITEM_NONE       equ 0
ITEM_POTION     equ 1
ITEM_GOLD       equ 2
ITEM_SWORD      equ 3
ITEM_ARMOR      equ 4

start:
        VBE_GAME_INIT
        ; Seed random
        mov eax, SYS_GETTIME
        int 0x80
        mov [rand_state], eax

        ; Init player
        mov dword [player_hp], 20
        mov dword [player_max_hp], 20
        mov dword [player_atk], 3
        mov dword [player_def], 1
        mov dword [player_gold], 0
        mov dword [player_level], 1
        mov dword [player_xp], 0
        mov dword [depth], 1

        call generate_dungeon
        call full_redraw

;=== Main game loop ===
.game_loop:
        mov eax, SYS_READ_KEY
        int 0x80
        test eax, eax
        jz .idle

        cmp al, 'q'
        je .quit
        cmp al, 'Q'
        je .quit
        cmp al, 27
        je .quit

        ; Movement
        cmp al, KEY_UP
        je .move_up
        cmp al, KEY_DOWN
        je .move_down
        cmp al, KEY_LEFT
        je .move_left
        cmp al, KEY_RIGHT
        je .move_right
        cmp al, 'k'
        je .move_up
        cmp al, 'j'
        je .move_down
        cmp al, 'h'
        je .move_left
        cmp al, 'l'
        je .move_right

        ; Stairs
        cmp al, '>'
        je .try_descend
        cmp al, '?'
        je .show_help

        jmp .idle

.move_up:
        xor ebx, ebx
        mov ecx, -1
        jmp .do_move
.move_down:
        xor ebx, ebx
        mov ecx, 1
        jmp .do_move
.move_left:
        mov ebx, -1
        xor ecx, ecx
        jmp .do_move
.move_right:
        mov ebx, 1
        xor ecx, ecx
        ; fall through
.do_move:
        ; EBX=dx, ECX=dy
        mov eax, [player_x]
        add eax, ebx
        mov edx, [player_y]
        add edx, ecx

        ; Bounds check
        cmp eax, 0
        jl .idle
        cmp eax, MAP_W
        jge .idle
        cmp edx, 0
        jl .idle
        cmp edx, MAP_H
        jge .idle

        ; Check for monster at (eax,edx)
        push eax
        push edx
        call find_monster_at    ; EAX=idx or -1
        cmp eax, -1
        jne .combat
        pop edx
        pop eax

        ; Check tile walkability
        push eax
        push edx
        imul edx, MAP_W
        add edx, eax
        movzx eax, byte [map + edx]
        cmp al, TILE_WALL
        je .blocked
        cmp al, TILE_VOID
        je .blocked

        pop edx
        pop eax
        mov [player_x], eax
        mov [player_y], edx

        ; Check for items at new position
        call pickup_item

        call full_redraw
        jmp .idle

.blocked:
        pop edx
        pop eax
        jmp .idle

.combat:
        ; EAX = monster index
        pop edx                 ; discard
        pop edx
        call attack_monster
        call full_redraw

        ; Check if player died
        cmp dword [player_hp], 0
        jle .death
        jmp .idle

.try_descend:
        ; Check if on stairs
        mov eax, [player_y]
        imul eax, MAP_W
        add eax, [player_x]
        movzx eax, byte [map + eax]
        cmp al, TILE_STAIRS
        jne .idle
        inc dword [depth]
        call generate_dungeon
        call set_message
        db "You descend deeper...", 0
        call full_redraw
        jmp .idle

.show_help:
        call draw_help
        ; Wait for key
.help_wait:
        mov eax, SYS_READ_KEY
        int 0x80
        test eax, eax
        jz .help_wait
        call full_redraw
        jmp .idle

.death:
        call draw_death
.death_wait:
        mov eax, SYS_READ_KEY
        int 0x80
        test eax, eax
        jz .death_wait
        jmp .quit

.idle:
        mov eax, SYS_SLEEP
        mov ebx, 5
        int 0x80
        jmp .game_loop

.quit:
        mov eax, SYS_FRAMEBUF
        mov ebx, 2
        int 0x80
        xor eax, eax
        int 0x80

;=======================================
; Generate dungeon level
;=======================================
generate_dungeon:
        pushad

        ; Clear map to void
        mov edi, map
        mov ecx, MAP_W * MAP_H
        xor al, al
        rep stosb

        ; Clear monsters
        mov edi, mon_type
        mov ecx, MAX_MONSTERS
        xor al, al
        rep stosb

        ; Clear items
        mov edi, item_type
        mov ecx, MAX_ITEMS
        xor al, al
        rep stosb

        mov dword [room_count], 0
        mov dword [msg_buf], 0

        ; Generate rooms
        xor esi, esi            ; attempts
.gen_rooms:
        cmp dword [room_count], MAX_ROOMS
        jge .gen_corridors
        cmp esi, 50
        jge .gen_corridors
        inc esi

        ; Random room dimensions
        call rand
        xor edx, edx
        mov ecx, ROOM_MAX_W - ROOM_MIN_W + 1
        div ecx
        add edx, ROOM_MIN_W
        mov [tmp_w], edx

        call rand
        xor edx, edx
        mov ecx, ROOM_MAX_H - ROOM_MIN_H + 1
        div ecx
        add edx, ROOM_MIN_H
        mov [tmp_h], edx

        ; Random position
        call rand
        xor edx, edx
        mov ecx, MAP_W
        sub ecx, [tmp_w]
        sub ecx, 2
        cmp ecx, 1
        jle .gen_rooms
        div ecx
        inc edx
        mov [tmp_x], edx

        call rand
        xor edx, edx
        mov ecx, MAP_H
        sub ecx, [tmp_h]
        sub ecx, 2
        cmp ecx, 1
        jle .gen_rooms
        div ecx
        inc edx
        mov [tmp_y], edx

        ; Check overlap
        call check_room_overlap
        test eax, eax
        jnz .gen_rooms

        ; Place room
        call place_room
        jmp .gen_rooms

.gen_corridors:
        ; Connect rooms with corridors
        cmp dword [room_count], 2
        jl .gen_populate

        mov esi, 1              ; start from room 1
.corridor_loop:
        cmp esi, [room_count]
        jge .gen_populate

        ; Connect room[esi-1] to room[esi]
        mov eax, esi
        dec eax
        call get_room_center    ; returns (EAX, EDX) = center of room eax
        mov [tmp_x], eax
        mov [tmp_y], edx

        mov eax, esi
        call get_room_center
        mov [tmp_w], eax        ; reuse as x2
        mov [tmp_h], edx        ; reuse as y2

        ; Dig L-shaped corridor
        call dig_corridor

        inc esi
        jmp .corridor_loop

.gen_populate:
        ; Place player in first room
        mov eax, 0
        call get_room_center
        mov [player_x], eax
        mov [player_y], edx

        ; Place stairs in last room
        mov eax, [room_count]
        dec eax
        cmp eax, 0
        jl .skip_stairs
        call get_room_center
        imul edx, MAP_W
        add edx, eax
        mov byte [map + edx], TILE_STAIRS
.skip_stairs:

        ; Place monsters
        call populate_monsters

        ; Place items
        call populate_items

        popad
        ret

;---------------------------------------
; place_room - Carve walls+floor into map
;---------------------------------------
place_room:
        pushad
        mov eax, [room_count]
        shl eax, 4             ; *16 for room record
        lea edi, [rooms + eax]
        mov eax, [tmp_x]
        mov [edi], eax          ; rx
        mov eax, [tmp_y]
        mov [edi + 4], eax      ; ry
        mov eax, [tmp_w]
        mov [edi + 8], eax      ; rw
        mov eax, [tmp_h]
        mov [edi + 12], eax     ; rh
        inc dword [room_count]

        ; Carve floor
        mov ecx, [tmp_y]
.pr_row:
        mov edx, [tmp_y]
        add edx, [tmp_h]
        cmp ecx, edx
        jge .pr_done
        mov ebx, [tmp_x]
.pr_col:
        mov edx, [tmp_x]
        add edx, [tmp_w]
        cmp ebx, edx
        jge .pr_next_row

        ; Edge = wall, interior = floor
        push edx
        mov eax, ecx
        cmp eax, [tmp_y]
        je .pr_wall
        mov edx, [tmp_y]
        add edx, [tmp_h]
        dec edx
        cmp eax, edx
        je .pr_wall
        cmp ebx, [tmp_x]
        je .pr_wall
        mov edx, [tmp_x]
        add edx, [tmp_w]
        dec edx
        cmp ebx, edx
        je .pr_wall

        ; Interior - floor
        mov eax, ecx
        imul eax, MAP_W
        add eax, ebx
        mov byte [map + eax], TILE_FLOOR
        pop edx
        jmp .pr_next_col
.pr_wall:
        mov eax, ecx
        imul eax, MAP_W
        add eax, ebx
        cmp byte [map + eax], TILE_FLOOR
        je .pr_skip_wall        ; Don't overwrite floor
        cmp byte [map + eax], TILE_CORRIDOR
        je .pr_skip_wall
        mov byte [map + eax], TILE_WALL
.pr_skip_wall:
        pop edx
.pr_next_col:
        inc ebx
        jmp .pr_col
.pr_next_row:
        inc ecx
        jmp .pr_row
.pr_done:
        popad
        ret

;---------------------------------------
; check_room_overlap - returns EAX=1 if overlapping
;---------------------------------------
check_room_overlap:
        push ebx
        push ecx
        push edx
        push esi

        xor esi, esi
.co_loop:
        cmp esi, [room_count]
        jge .co_ok

        mov eax, esi
        shl eax, 4
        lea ebx, [rooms + eax]

        ; Check X overlap (with 1 cell margin)
        mov eax, [tmp_x]
        dec eax
        mov ecx, [ebx + 8]     ; existing rw
        add ecx, [ebx]         ; existing rx + rw
        inc ecx
        cmp eax, ecx
        jge .co_next

        mov eax, [tmp_x]
        add eax, [tmp_w]
        inc eax
        cmp eax, [ebx]
        jle .co_next

        ; Check Y overlap
        mov eax, [tmp_y]
        dec eax
        mov ecx, [ebx + 12]
        add ecx, [ebx + 4]
        inc ecx
        cmp eax, ecx
        jge .co_next

        mov eax, [tmp_y]
        add eax, [tmp_h]
        inc eax
        cmp eax, [ebx + 4]
        jle .co_next

        ; Overlapping
        mov eax, 1
        jmp .co_ret

.co_next:
        inc esi
        jmp .co_loop
.co_ok:
        xor eax, eax
.co_ret:
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

;---------------------------------------
; get_room_center: EAX=room_index -> EAX=cx, EDX=cy
;---------------------------------------
get_room_center:
        push ebx
        shl eax, 4
        lea ebx, [rooms + eax]
        mov eax, [ebx]          ; rx
        mov edx, [ebx + 8]      ; rw
        shr edx, 1
        add eax, edx
        mov edx, [ebx + 4]      ; ry
        push eax
        mov eax, [ebx + 12]     ; rh
        shr eax, 1
        add edx, eax
        pop eax
        pop ebx
        ret

;---------------------------------------
; dig_corridor: connects (tmp_x,tmp_y) to (tmp_w,tmp_h)
;---------------------------------------
dig_corridor:
        pushad
        ; Horizontal first, then vertical
        mov ebx, [tmp_x]
        mov ecx, [tmp_y]
.dc_hloop:
        cmp ebx, [tmp_w]
        je .dc_vert
        ; Dig
        mov eax, ecx
        imul eax, MAP_W
        add eax, ebx
        cmp byte [map + eax], TILE_VOID
        jne .dc_hskip
        mov byte [map + eax], TILE_CORRIDOR
.dc_hskip:
        cmp byte [map + eax], TILE_WALL
        jne .dc_hskip2
        mov byte [map + eax], TILE_DOOR
.dc_hskip2:
        cmp ebx, [tmp_w]
        jl .dc_hinc
        dec ebx
        jmp .dc_hloop
.dc_hinc:
        inc ebx
        jmp .dc_hloop

.dc_vert:
        mov ebx, [tmp_w]
.dc_vloop:
        cmp ecx, [tmp_h]
        je .dc_done
        mov eax, ecx
        imul eax, MAP_W
        add eax, ebx
        cmp byte [map + eax], TILE_VOID
        jne .dc_vskip
        mov byte [map + eax], TILE_CORRIDOR
.dc_vskip:
        cmp byte [map + eax], TILE_WALL
        jne .dc_vskip2
        mov byte [map + eax], TILE_DOOR
.dc_vskip2:
        cmp ecx, [tmp_h]
        jl .dc_vinc
        dec ecx
        jmp .dc_vloop
.dc_vinc:
        inc ecx
        jmp .dc_vloop
.dc_done:
        popad
        ret

;---------------------------------------
; populate_monsters
;---------------------------------------
populate_monsters:
        pushad
        xor esi, esi            ; monster slot
        mov edi, [depth]        ; difficulty scales with depth

        ; Place 3 + depth monsters (up to MAX)
        mov ecx, 3
        add ecx, edi
        cmp ecx, MAX_MONSTERS
        jle .pm_count_ok
        mov ecx, MAX_MONSTERS
.pm_count_ok:
        mov [tmp_x], ecx        ; count to place

.pm_loop:
        cmp dword [tmp_x], 0
        jle .pm_done
        cmp esi, MAX_MONSTERS
        jge .pm_done

        ; Random floor position
        call rand_floor_pos     ; EAX=x, EDX=y
        cmp eax, -1
        je .pm_done

        ; Don't place on player
        cmp eax, [player_x]
        jne .pm_place
        cmp edx, [player_y]
        je .pm_loop
.pm_place:
        mov [mon_x + esi*4], eax
        mov [mon_y + esi*4], edx

        ; Random monster type scaled by depth
        push esi
        call rand
        xor edx, edx
        mov ecx, edi            ; max type = depth (capped at 6)
        cmp ecx, 6
        jle .pm_type_ok
        mov ecx, 6
.pm_type_ok:
        inc ecx
        div ecx
        inc edx
        pop esi
        mov [mon_type + esi], dl

        ; HP = type * 3 + depth
        movzx eax, dl
        imul eax, 3
        add eax, edi
        mov [mon_hp + esi*4], eax

        inc esi
        dec dword [tmp_x]
        jmp .pm_loop
.pm_done:
        popad
        ret

;---------------------------------------
; populate_items
;---------------------------------------
populate_items:
        pushad
        xor esi, esi
        mov ecx, 5              ; 5 items per level
.pi_loop:
        cmp ecx, 0
        jle .pi_done
        cmp esi, MAX_ITEMS
        jge .pi_done

        call rand_floor_pos
        cmp eax, -1
        je .pi_done

        mov [item_x + esi*4], eax
        mov [item_y + esi*4], edx

        ; Random item type
        push ecx
        call rand
        xor edx, edx
        mov ecx, 4
        div ecx
        inc edx
        pop ecx
        mov [item_type + esi], dl

        inc esi
        dec ecx
        jmp .pi_loop
.pi_done:
        popad
        ret

;---------------------------------------
; rand_floor_pos: find random floor tile -> EAX=x, EDX=y (or EAX=-1 if fail)
;---------------------------------------
rand_floor_pos:
        push ecx
        push ebx
        mov ecx, 100            ; attempts
.rfp_loop:
        dec ecx
        js .rfp_fail

        call rand
        xor edx, edx
        push ecx
        mov ecx, MAP_W * MAP_H
        div ecx
        pop ecx
        ; EDX = offset
        movzx eax, byte [map + edx]
        cmp al, TILE_FLOOR
        jne .rfp_loop

        ; Convert offset to x,y
        mov eax, edx
        xor edx, edx
        push ecx
        mov ecx, MAP_W
        div ecx
        pop ecx
        ; EAX=y, EDX=x
        xchg eax, edx
        pop ebx
        pop ecx
        ret
.rfp_fail:
        mov eax, -1
        pop ebx
        pop ecx
        ret

;=======================================
; Combat
;=======================================
attack_monster:
        ; EAX = monster index
        pushad
        mov esi, eax

        ; Player attacks
        mov eax, [player_atk]
        call rand
        xor edx, edx
        mov ecx, 3
        div ecx                 ; 0-2 random bonus
        add eax, [player_atk]
        mov ebx, eax            ; damage

        sub [mon_hp + esi*4], ebx

        ; Set attack message
        call set_message
        db "You strike! ", 0

        cmp dword [mon_hp + esi*4], 0
        jg .mon_alive

        ; Monster killed - read type BEFORE clearing
        movzx eax, byte [mon_type + esi]
        mov byte [mon_type + esi], MON_NONE
        ; Give XP based on monster type
        add eax, 2
        imul eax, [depth]
        add [player_xp], eax
        ; Check level up (every 20 XP)
        mov eax, [player_xp]
        xor edx, edx
        mov ecx, 20
        div ecx
        test edx, edx
        jnz .am_done
        cmp eax, [player_level]
        jle .am_done
        inc dword [player_level]
        add dword [player_max_hp], 5
        mov eax, [player_max_hp]
        mov [player_hp], eax
        inc dword [player_atk]
        jmp .am_done

.mon_alive:
        ; Monster counter-attacks
        movzx eax, byte [mon_type + esi]
        inc eax                 ; base damage
        add eax, [depth]
        sub eax, [player_def]
        cmp eax, 1
        jge .dam_ok
        mov eax, 1
.dam_ok:
        sub [player_hp], eax

.am_done:
        popad
        ret

;---------------------------------------
; find_monster_at: (EAX=x, EDX=y) -> EAX=index or -1
;---------------------------------------
find_monster_at:
        push ecx
        push ebx
        xor ecx, ecx
.fma_loop:
        cmp ecx, MAX_MONSTERS
        jge .fma_none
        cmp byte [mon_type + ecx], MON_NONE
        je .fma_next
        cmp [mon_x + ecx*4], eax
        jne .fma_next
        cmp [mon_y + ecx*4], edx
        jne .fma_next
        mov eax, ecx
        pop ebx
        pop ecx
        ret
.fma_next:
        inc ecx
        jmp .fma_loop
.fma_none:
        mov eax, -1
        pop ebx
        pop ecx
        ret

;---------------------------------------
; pickup_item
;---------------------------------------
pickup_item:
        pushad
        xor ecx, ecx
.pu_loop:
        cmp ecx, MAX_ITEMS
        jge .pu_done
        cmp byte [item_type + ecx], ITEM_NONE
        je .pu_next
        mov eax, [player_x]
        cmp [item_x + ecx*4], eax
        jne .pu_next
        mov eax, [player_y]
        cmp [item_y + ecx*4], eax
        jne .pu_next

        ; Found item
        movzx eax, byte [item_type + ecx]
        mov byte [item_type + ecx], ITEM_NONE

        cmp al, ITEM_POTION
        je .pu_potion
        cmp al, ITEM_GOLD
        je .pu_gold
        cmp al, ITEM_SWORD
        je .pu_sword
        cmp al, ITEM_ARMOR
        je .pu_armor
        jmp .pu_next

.pu_potion:
        add dword [player_hp], 8
        mov eax, [player_max_hp]
        cmp [player_hp], eax
        jle .pu_next
        mov [player_hp], eax
        jmp .pu_next
.pu_gold:
        add dword [player_gold], 10
        jmp .pu_next
.pu_sword:
        inc dword [player_atk]
        jmp .pu_next
.pu_armor:
        inc dword [player_def]
.pu_next:
        inc ecx
        jmp .pu_loop
.pu_done:
        popad
        ret

;=======================================
; Rendering
;=======================================
full_redraw:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        ; --- Draw map tiles ---
        mov dword [.dr], 0
.draw_row:
        cmp dword [.dr], MAP_H
        jge .draw_entities

        mov dword [.dc], 0
.draw_col:
        cmp dword [.dc], MAP_W
        jge .draw_next_row

        ; FOV check
        mov eax, [.dc]
        sub eax, [player_x]
        imul eax, eax
        mov edx, [.dr]
        sub edx, [player_y]
        imul edx, edx
        add eax, edx
        cmp eax, 100
        jg .draw_dark

        ; Get tile
        mov eax, [.dr]
        imul eax, MAP_W
        add eax, [.dc]
        movzx edx, byte [map + eax]
        cmp dl, TILE_WALL
        je .draw_wall
        cmp dl, TILE_FLOOR
        je .draw_floor
        cmp dl, TILE_DOOR
        je .draw_door
        cmp dl, TILE_CORRIDOR
        je .draw_floor
        cmp dl, TILE_STAIRS
        je .draw_stairs
        jmp .draw_dark

.draw_wall:
        mov dword [.tc], COL_WALL
        mov dword [.tchar], '#'
        jmp .draw_put
.draw_floor:
        mov dword [.tc], COL_FLOOR
        mov dword [.tchar], '.'
        jmp .draw_put
.draw_door:
        mov dword [.tc], COL_DOOR
        mov dword [.tchar], '+'
        jmp .draw_put
.draw_stairs:
        mov dword [.tc], COL_STAIRS
        mov dword [.tchar], '>'
        jmp .draw_put
.draw_dark:
        inc dword [.dc]
        jmp .draw_col
.draw_put:
        ; Fill tile background
        mov ebx, [.dc]
        imul ebx, CELL_SZ
        add ebx, MAP_DRAW_X
        mov ecx, [.dr]
        imul ecx, CELL_SZ
        add ecx, MAP_DRAW_Y
        mov edx, CELL_SZ
        mov esi, CELL_SZ
        mov edi, COL_FLOOR
        cmp dword [.tc], COL_WALL
        je .fill_wall
        cmp dword [.tc], COL_DOOR
        je .fill_door
        cmp dword [.tc], COL_STAIRS
        je .fill_stairs
        jmp .do_fill
.fill_wall:
        mov edi, COL_WALL
        jmp .do_fill
.fill_door:
        mov edi, COL_DOOR
        jmp .do_fill
.fill_stairs:
        mov edi, COL_STAIRS
.do_fill:
        call vbe_fill_rect

        ; Draw tile char (scale=1, 5x7)
        mov ebx, [.dc]
        imul ebx, CELL_SZ
        add ebx, MAP_DRAW_X + 3
        mov ecx, [.dr]
        imul ecx, CELL_SZ
        add ecx, MAP_DRAW_Y + 2
        mov edx, [.tchar]
        mov esi, 0x00AAAAAA
        mov eax, 1
        call vbe_draw_char

        inc dword [.dc]
        jmp .draw_col

.draw_next_row:
        inc dword [.dr]
        jmp .draw_row

.draw_entities:
        ; --- Draw items ---
        mov dword [.ei], 0
.de_items:
        cmp dword [.ei], MAX_ITEMS
        jge .de_mons
        mov eax, [.ei]
        cmp byte [item_type + eax], ITEM_NONE
        je .de_inext

        ; FOV check
        mov eax, [.ei]
        mov ebx, [item_x + eax*4]
        sub ebx, [player_x]
        imul ebx, ebx
        mov eax, [.ei]
        mov ecx, [item_y + eax*4]
        sub ecx, [player_y]
        imul ecx, ecx
        add ebx, ecx
        cmp ebx, 100
        jg .de_inext

        mov eax, [.ei]
        movzx edx, byte [item_type + eax]
        cmp dl, ITEM_POTION
        je .item_pot
        cmp dl, ITEM_GOLD
        je .item_gold
        cmp dl, ITEM_SWORD
        je .item_swd
        jmp .item_arm
.item_pot:
        mov dword [.tc], COL_ITEM_POT
        mov dword [.tchar], '!'
        jmp .de_iput
.item_gold:
        mov dword [.tc], COL_ITEM_GOLD
        mov dword [.tchar], '$'
        jmp .de_iput
.item_swd:
        mov dword [.tc], COL_ITEM_SWD
        mov dword [.tchar], '/'
        jmp .de_iput
.item_arm:
        mov dword [.tc], COL_ITEM_ARM
        mov dword [.tchar], '['
.de_iput:
        mov eax, [.ei]
        mov ebx, [item_x + eax*4]
        imul ebx, CELL_SZ
        add ebx, MAP_DRAW_X + 3
        mov ecx, [item_y + eax*4]
        imul ecx, CELL_SZ
        add ecx, MAP_DRAW_Y + 2
        mov edx, [.tchar]
        mov esi, [.tc]
        mov eax, 1
        call vbe_draw_char
.de_inext:
        inc dword [.ei]
        jmp .de_items

.de_mons:
        ; --- Draw monsters ---
        mov dword [.mi], 0
.de_mloop:
        cmp dword [.mi], MAX_MONSTERS
        jge .de_player
        mov eax, [.mi]
        cmp byte [mon_type + eax], MON_NONE
        je .de_mnext

        ; FOV
        mov eax, [.mi]
        mov ebx, [mon_x + eax*4]
        sub ebx, [player_x]
        imul ebx, ebx
        mov eax, [.mi]
        mov ecx, [mon_y + eax*4]
        sub ecx, [player_y]
        imul ecx, ecx
        add ebx, ecx
        cmp ebx, 100
        jg .de_mnext

        mov eax, [.mi]
        movzx edx, byte [mon_type + eax]
        cmp dl, MON_RAT
        je .mon_rat
        cmp dl, MON_BAT
        je .mon_bat
        cmp dl, MON_SNAKE
        je .mon_snake
        cmp dl, MON_GOBLIN
        je .mon_gob
        cmp dl, MON_ORC
        je .mon_orc
.mon_troll:
        mov dword [.tc], COL_MON_DEF
        mov dword [.tchar], 'T'
        jmp .de_mput
.mon_rat:
        mov dword [.tc], COL_MON_YEL
        mov dword [.tchar], 'R'
        jmp .de_mput
.mon_bat:
        mov dword [.tc], COL_MON_PUR
        mov dword [.tchar], 'B'
        jmp .de_mput
.mon_snake:
        mov dword [.tc], COL_MON_GRN
        mov dword [.tchar], 'S'
        jmp .de_mput
.mon_gob:
        mov dword [.tc], COL_MON_GRN
        mov dword [.tchar], 'G'
        jmp .de_mput
.mon_orc:
        mov dword [.tc], COL_MON_DEF
        mov dword [.tchar], 'O'
.de_mput:
        mov eax, [.mi]
        mov ebx, [mon_x + eax*4]
        imul ebx, CELL_SZ
        add ebx, MAP_DRAW_X + 3
        mov ecx, [mon_y + eax*4]
        imul ecx, CELL_SZ
        add ecx, MAP_DRAW_Y + 2
        mov edx, [.tchar]
        mov esi, [.tc]
        mov eax, 1
        call vbe_draw_char
.de_mnext:
        inc dword [.mi]
        jmp .de_mloop

.de_player:
        ; --- Draw player '@' ---
        mov ebx, [player_x]
        imul ebx, CELL_SZ
        add ebx, MAP_DRAW_X + 3
        mov ecx, [player_y]
        imul ecx, CELL_SZ
        add ecx, MAP_DRAW_Y + 2
        mov edx, '@'
        mov esi, COL_PLAYER
        mov eax, 1
        call vbe_draw_char

        ; --- Status bar ---
        ; "HP:xx/xx  ATK:x  DEF:x  AU:x  LV:x  DEPTH:x"
        mov ebx, 72
        mov ecx, STAT_Y
        mov edx, str_hp
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_str

        mov ebx, 96
        mov ecx, STAT_Y
        mov edx, [player_hp]
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_num

        mov ebx, 116
        mov ecx, STAT_Y
        mov edx, str_slash
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_str

        mov ebx, 122
        mov ecx, STAT_Y
        mov edx, [player_max_hp]
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_num

        mov ebx, 160
        mov ecx, STAT_Y
        mov edx, str_atk
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_str

        mov ebx, 184
        mov ecx, STAT_Y
        mov edx, [player_atk]
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_num

        mov ebx, 210
        mov ecx, STAT_Y
        mov edx, str_def
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_str

        mov ebx, 234
        mov ecx, STAT_Y
        mov edx, [player_def]
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_num

        mov ebx, 260
        mov ecx, STAT_Y
        mov edx, str_gold
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_str

        mov ebx, 278
        mov ecx, STAT_Y
        mov edx, [player_gold]
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_num

        mov ebx, 320
        mov ecx, STAT_Y
        mov edx, str_level
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_str

        mov ebx, 338
        mov ecx, STAT_Y
        mov edx, [player_level]
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_num

        mov ebx, 360
        mov ecx, STAT_Y
        mov edx, str_depth
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_str

        mov ebx, 402
        mov ecx, STAT_Y
        mov edx, [depth]
        mov esi, COL_STAT
        mov eax, 1
        call vbe_draw_num

        ; --- Message line ---
        cmp byte [msg_buf], 0
        je .no_msg
        mov ebx, 72
        mov ecx, MSG_Y
        mov edx, msg_buf
        mov esi, COL_MSG
        mov eax, 1
        call vbe_draw_str
.no_msg:
        VBE_GAME_PRESENT
        popad
        ret

.dr: dd 0
.dc: dd 0
.ei: dd 0
.mi: dd 0
.tc: dd 0
.tchar: dd 0

;---------------------------------------
; draw_help
;---------------------------------------
draw_help:
        pushad
        mov edx, COL_BG
        call vbe_clear_screen

        mov ebx, 350
        mov ecx, 80
        mov edx, help_title
        mov esi, 0x00FFFFFF
        mov eax, 2
        call vbe_draw_str

        ; Help lines
        mov ebx, 280
        mov ecx, 130
        mov edx, help_l1
        mov esi, 0x0088CCFF
        mov eax, 1
        call vbe_draw_str
        mov ebx, 280
        mov ecx, 145
        mov edx, help_l2
        mov esi, 0x0088CCFF
        mov eax, 1
        call vbe_draw_str
        mov ebx, 280
        mov ecx, 160
        mov edx, help_l3
        mov esi, 0x0088CCFF
        mov eax, 1
        call vbe_draw_str
        mov ebx, 280
        mov ecx, 175
        mov edx, help_l4
        mov esi, 0x0088CCFF
        mov eax, 1
        call vbe_draw_str
        mov ebx, 280
        mov ecx, 200
        mov edx, help_s1
        mov esi, 0x00AAAAAA
        mov eax, 1
        call vbe_draw_str
        mov ebx, 280
        mov ecx, 215
        mov edx, help_s2
        mov esi, 0x00AAAAAA
        mov eax, 1
        call vbe_draw_str
        mov ebx, 280
        mov ecx, 230
        mov edx, help_s3
        mov esi, 0x00AAAAAA
        mov eax, 1
        call vbe_draw_str
        mov ebx, 280
        mov ecx, 245
        mov edx, help_s4
        mov esi, 0x00AAAAAA
        mov eax, 1
        call vbe_draw_str
        mov ebx, 280
        mov ecx, 260
        mov edx, help_s5
        mov esi, 0x00AAAAAA
        mov eax, 1
        call vbe_draw_str

        mov ebx, 350
        mov ecx, 310
        mov edx, help_press
        mov esi, 0x00888888
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT
        popad
        ret

;---------------------------------------
; draw_death
;---------------------------------------
draw_death:
        pushad
        ; Persist best XP (only if higher) + lose SFX
        mov esi, hs_name_rg
        mov ebx, [player_xp]
        call hs_update
        call audio_sfx_lose
        mov edx, 0x00330000
        call vbe_clear_screen

        mov ebx, 350
        mov ecx, 300
        mov edx, death_str1
        mov esi, 0x00FF4444
        mov eax, 3
        call vbe_draw_str

        mov ebx, 280
        mov ecx, 360
        mov edx, death_str2
        mov esi, 0x00FFAA44
        mov eax, 2
        call vbe_draw_str

        mov ebx, 280
        mov ecx, 420
        mov edx, death_str3
        mov esi, 0x00FFEE44
        mov eax, 1
        call vbe_draw_str

        mov ebx, 430
        mov ecx, 420
        mov edx, [depth]
        mov esi, 0x00FFEE44
        mov eax, 1
        call vbe_draw_num

        mov ebx, 460
        mov ecx, 420
        mov edx, death_str4
        mov esi, 0x00FFEE44
        mov eax, 1
        call vbe_draw_str

        mov ebx, 520
        mov ecx, 420
        mov edx, [player_gold]
        mov esi, 0x00FFEE44
        mov eax, 1
        call vbe_draw_num

        mov ebx, 280
        mov ecx, 440
        mov edx, death_str5
        mov esi, 0x00888888
        mov eax, 1
        call vbe_draw_str

        VBE_GAME_PRESENT
        popad
        ret

;---------------------------------------
; set_message - inline string after CALL
;---------------------------------------
set_message:
        pop esi                 ; return addr = string ptr
        mov edi, msg_buf
.sm_copy:
        lodsb
        stosb
        test al, al
        jnz .sm_copy
        push esi                ; fixup return to after string
        ret

;---------------------------------------
; rand - LFSR PRNG -> EAX
;---------------------------------------
rand:
        mov eax, [rand_state]
        imul eax, 1103515245
        add eax, 12345
        mov [rand_state], eax
        shr eax, 16
        and eax, 0x7FFF
        ret

; === Strings ===
str_hp:     db "HP:", 0
str_slash:  db "/", 0
str_atk:    db "ATK:", 0
str_def:    db "DEF:", 0
str_gold:   db "AU:", 0
str_level:  db "LV:", 0
str_depth:  db "DEPTH:", 0

help_title: db "ROGUE - HELP", 0
help_l1:    db "ARROW KEYS/HJKL  MOVE", 0
help_l2:    db ">   DESCEND STAIRS", 0
help_l3:    db "?   HELP", 0
help_l4:    db "Q   QUIT", 0
help_s1:    db "SYMBOLS: @ YOU   # WALL   > STAIRS", 0
help_s2:    db "  + DOOR   ! POTION   $ GOLD", 0
help_s3:    db "  / SWORD   [ ARMOR", 0
help_s4:    db "  R RAT  B BAT  S SNAKE", 0
help_s5:    db "  G GOBLIN  O ORC  T TROLL", 0
help_press: db "PRESS ANY KEY", 0

death_str1: db "YOU HAVE DIED", 0
death_str2: db "THE DUNGEON CLAIMS ANOTHER SOUL", 0
death_str3: db "REACHED DEPTH", 0
death_str4: db "WITH", 0
death_str5: db "GOLD - PRESS ANY KEY", 0

; === BSS ===
msg_buf:        times 80 db 0
rand_state:     dd 0
player_x:       dd 0
player_y:       dd 0
player_hp:      dd 0
player_max_hp:  dd 0
player_atk:     dd 0
player_def:     dd 0
player_gold:    dd 0
player_level:   dd 0
player_xp:      dd 0
hs_name_rg:     db "rogue", 0
depth:          dd 0
room_count:     dd 0
rooms:          times MAX_ROOMS * 16 db 0  ; 4 dwords per room: x,y,w,h
tmp_x:          dd 0
tmp_y:          dd 0
tmp_w:          dd 0
tmp_h:          dd 0
total_secs:     dd 0
map:            times MAP_W * MAP_H db 0
mon_type:       times MAX_MONSTERS db 0
mon_x:          times MAX_MONSTERS dd 0
mon_y:          times MAX_MONSTERS dd 0
mon_hp:         times MAX_MONSTERS dd 0
item_type:      times MAX_ITEMS db 0
item_x:         times MAX_ITEMS dd 0
item_y:         times MAX_ITEMS dd 0
