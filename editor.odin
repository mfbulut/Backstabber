package main

import "core:fmt"
import "core:mem"
import "core:math"
import k2 "karl2d"

EDITOR_WIDTH :: 400
EDITOR_HEIGHT :: 200

editor_map: [EDITOR_HEIGHT][EDITOR_WIDTH]u8
brushes := []u8{'#', '^', 'P', 'X', 'O', 'o', '1', '2', '3', '4', '5', '6', '7', '8', '9'}
editor_brush: u8 = '#'
editor_camera: k2.Camera
editor_target_zoom: f32 = 1.0

editor_init :: proc() {
    if !editor_load_map() {
        for r in 0..<EDITOR_HEIGHT {
            for c in 0..<EDITOR_WIDTH {
                editor_map[r][c] = ' '
            }
        }

        for c in 0..<EDITOR_WIDTH {
            editor_map[EDITOR_HEIGHT/2][c] = '#'
        }
        editor_map[EDITOR_HEIGHT/2 - 1][10] = 'P'
    }

    editor_camera = k2.Camera{zoom = 1.0}
    editor_target_zoom = 1.0
    sw := f32(k2.get_screen_size().x)
    sh := f32(k2.get_screen_size().y)
    editor_camera.target = k2.Vec2{10 * TILE_SIZE - sw / 2, (EDITOR_HEIGHT/2) * TILE_SIZE - sh / 2}
}

step_editor :: proc(dt: f32) {
    sw := f32(k2.get_screen_size().x)
    sh := f32(k2.get_screen_size().y)

    if k2.mouse_button_is_held(.Middle) {
        md := k2.get_mouse_delta()
        editor_camera.target -= md / editor_camera.zoom
    }

    scroll := k2.get_mouse_wheel_delta()
    if scroll != 0 {
        if scroll > 0 {
            editor_target_zoom *= 1.2
        } else if scroll < 0 {
            editor_target_zoom /= 1.2
        }
        editor_target_zoom = clamp(editor_target_zoom, 0.2, 5.0)
    }

    if abs(editor_camera.zoom - editor_target_zoom) > 0.0001 {
        mouse_pos := k2.get_mouse_position()
        world_before := editor_camera.target + mouse_pos / editor_camera.zoom

        editor_camera.zoom = math.lerp(editor_camera.zoom, editor_target_zoom, dt * 50.0)

        editor_camera.target = world_before - mouse_pos / editor_camera.zoom
    }

    draw_parallax(k2.Color{100, 100, 100, 255})

    k2.set_camera(editor_camera)
    draw_editor_map()

    handle_editor_input()

    k2.set_camera(ui_camera())
    draw_editor_ui()
}

handle_editor_input :: proc() {
    mouse_pos := k2.get_mouse_position()
    sw := f32(k2.get_screen_size().x)
    sh := f32(k2.get_screen_size().y)

    cam := ui_camera()
    if mouse_pos.y > sh - 80.0 * cam.zoom {
        return
    }

    world_pos := editor_camera.target + mouse_pos / editor_camera.zoom
    col := int(math.floor(world_pos.x / TILE_SIZE))
    row := int(math.floor(world_pos.y / TILE_SIZE))

    if col >= 0 && col < EDITOR_WIDTH && row >= 0 && row < EDITOR_HEIGHT {
        if k2.key_is_held(.Left_Control) && k2.mouse_button_is_held(.Left) {
            editor_brush = editor_map[row][col]
        } else if k2.mouse_button_is_held(.Left) {
            editor_map[row][col] = editor_brush
            editor_save_map()
        } else if k2.mouse_button_is_held(.Right) {
            editor_map[row][col] = ' '
            editor_save_map()
        }
    }

    if k2.key_went_down(.N1) do editor_brush = brushes[0]
    if k2.key_went_down(.N2) do editor_brush = brushes[1]
    if k2.key_went_down(.N3) do editor_brush = brushes[2]
    if k2.key_went_down(.N4) do editor_brush = brushes[3]
    if k2.key_went_down(.N5) do editor_brush = brushes[4]
    if k2.key_went_down(.N6) do editor_brush = brushes[5]
    if k2.key_went_down(.N7) do editor_brush = brushes[6]
    if k2.key_went_down(.N8) do editor_brush = brushes[7]
    if k2.key_went_down(.N9) do editor_brush = brushes[8]

    if  k2.key_went_down(.NP_1) do editor_brush = '1'
    if  k2.key_went_down(.NP_2) do editor_brush = '2'
    if  k2.key_went_down(.NP_3) do editor_brush = '3'
    if  k2.key_went_down(.NP_4) do editor_brush = '4'
    if  k2.key_went_down(.NP_5) do editor_brush = '5'
    if  k2.key_went_down(.NP_6) do editor_brush = '6'
    if  k2.key_went_down(.NP_7) do editor_brush = '7'
    if  k2.key_went_down(.NP_8) do editor_brush = '8'
    if  k2.key_went_down(.NP_9) do editor_brush = '9'
}

draw_editor_map :: proc() {
    view_min := editor_camera.target
    screen := k2.get_screen_size()
    view_max := editor_camera.target + screen / editor_camera.zoom

    col_min := max(0, int(math.floor(view_min.x / TILE_SIZE)))
    col_max := min(EDITOR_WIDTH-1, int(math.floor(view_max.x / TILE_SIZE)))
    row_min := max(0, int(math.floor(view_min.y / TILE_SIZE)))
    row_max := min(EDITOR_HEIGHT-1, int(math.floor(view_max.y / TILE_SIZE)))

    for row in row_min..=row_max {
        for col in col_min..=col_max {
            ch := editor_map[row][col]
            if ch == ' ' do continue
            x := f32(col) * TILE_SIZE
            y := f32(row) * TILE_SIZE
            draw_editor_item(ch, row, col, x, y, 1.0)
        }
    }

    mouse_pos := k2.get_mouse_position()
    sw := f32(k2.get_screen_size().x)
    sh := f32(k2.get_screen_size().y)

    cam := ui_camera()
    if mouse_pos.y <= sh - 80.0 * cam.zoom {
        world_pos := editor_camera.target + mouse_pos / editor_camera.zoom
        col := int(math.floor(world_pos.x / TILE_SIZE))
        row := int(math.floor(world_pos.y / TILE_SIZE))
        if col >= 0 && col < EDITOR_WIDTH && row >= 0 && row < EDITOR_HEIGHT {
            old_ch := editor_map[row][col]
            if old_ch != editor_brush {
                editor_map[row][col] = editor_brush
                draw_editor_item(editor_brush, row, col, f32(col)*TILE_SIZE, f32(row)*TILE_SIZE, 0.5)
                editor_map[row][col] = old_ch
            }
        }
    }
}

draw_editor_item :: proc(ch: u8, row: int, col: int, x: f32, y: f32, alpha: f32) {
    rect := k2.Rect{x, y, TILE_SIZE, TILE_SIZE}

    has_N := row > 0   && editor_map[row-1][col] == '#'
    has_E := col < EDITOR_WIDTH-1 && editor_map[row][col+1] == '#'
    has_S := row < EDITOR_HEIGHT-1 && editor_map[row+1][col] == '#'
    has_W := col > 0   && editor_map[row][col-1] == '#'
    has_NW := row > 0 && col > 0     && editor_map[row-1][col-1] == '#' && has_N && has_W
    has_NE := row > 0 && col < EDITOR_WIDTH-1   && editor_map[row-1][col+1] == '#' && has_N && has_E
    has_SE := row < EDITOR_HEIGHT-1 && col < EDITOR_WIDTH-1 && editor_map[row+1][col+1] == '#' && has_S && has_E
    has_SW := row < EDITOR_HEIGHT-1 && col > 0   && editor_map[row+1][col-1] == '#' && has_S && has_W

    if ch == '#' {
        mask: Tile_Mask
        if has_N  do mask += {.N}
        if has_NE do mask += {.NE}
        if has_E  do mask += {.E}
        if has_SE do mask += {.SE}
        if has_S  do mask += {.S}
        if has_SW do mask += {.SW}
        if has_W  do mask += {.W}
        if has_NW do mask += {.NW}

        tile_grid := TILEMAP_TEXCOORD[transmute(u8)mask]
        TILE_SRC_SIZE : f32 = 16.0

        source := k2.Rect{
            x = f32(tile_grid.x) * TILE_SRC_SIZE,
            y = f32(tile_grid.y) * TILE_SRC_SIZE,
            w = TILE_SRC_SIZE,
            h = TILE_SRC_SIZE,
        }
        k2.draw_texture_fit(tilemap, source, rect, {}, 0, k2.Color{255, 255, 255, u8(255.0 * alpha)})
    } else if ch == '^' {
        spike_color := k2.Color{200, 50, 50, u8(255.0 * alpha)}

        if has_S {
            k2.draw_triangle([3]k2.Vec2{{x, y + TILE_SIZE}, {x + TILE_SIZE, y + TILE_SIZE}, {x + TILE_SIZE/2, y}}, spike_color)
        } else if has_N {
            k2.draw_triangle([3]k2.Vec2{{x, y}, {x + TILE_SIZE, y}, {x + TILE_SIZE/2, y + TILE_SIZE}}, spike_color)
        } else if has_E {
            k2.draw_triangle([3]k2.Vec2{{x + TILE_SIZE, y}, {x + TILE_SIZE, y + TILE_SIZE}, {x, y + TILE_SIZE/2}}, spike_color)
        } else if has_W {
            k2.draw_triangle([3]k2.Vec2{{x, y}, {x, y + TILE_SIZE}, {x + TILE_SIZE, y + TILE_SIZE/2}}, spike_color)
        } else {
            cx := x + TILE_SIZE/2.0
            cy := y + TILE_SIZE/2.0
            r  := TILE_SIZE/2.2
            ir := TILE_SIZE/6.0
            k2.draw_triangle([3]k2.Vec2{{cx, cy - r}, {cx - ir, cy}, {cx + ir, cy}}, spike_color)
            k2.draw_triangle([3]k2.Vec2{{cx, cy + r}, {cx + ir, cy}, {cx - ir, cy}}, spike_color)
            k2.draw_triangle([3]k2.Vec2{{cx - r, cy}, {cx, cy + ir}, {cx, cy - ir}}, spike_color)
            k2.draw_triangle([3]k2.Vec2{{cx + r, cy}, {cx, cy - ir}, {cx, cy + ir}}, spike_color)
        }
    } else if ch == 'P' {
        src := player_sprite_rect(.Idle, 0)
        p_rect := k2.Rect{x - 1 * TILE_SIZE, y - 1.8 * TILE_SIZE, 3 * TILE_SIZE, 3 * TILE_SIZE}
        k2.draw_texture_fit(player_sprite, src, p_rect, {}, 0, k2.Color{255, 255, 255, u8(255.0 * alpha)})
    } else if ch == 'X' {
        src := k2.Rect{0, 0, f32(end_sprite.width), f32(end_sprite.height)}
        k2.draw_texture_fit(end_sprite, src, rect, {}, 0, k2.Color{255, 255, 255, u8(255.0 * alpha)})
    } else {
        cx := x + TILE_SIZE/2
        cy := y + TILE_SIZE/2
        switch ch {
        case 'O':
            col := SLINGSHOT_COLOR_NORMAL
            col.a = u8(255.0 * alpha)
            k2.draw_rect_outline(k2.Rect{x+2, y+2, TILE_SIZE-4, TILE_SIZE-4}, 2.0, col)
        case 'o':
            col := SLINGSHOT_COLOR_BREAK
            col.a = u8(255.0 * alpha)
            k2.draw_rect_outline(k2.Rect{x+2, y+2, TILE_SIZE-4, TILE_SIZE-4}, 2.0, col)
        case '1', '2', '3', '4', '5', '6', '7', '8', '9':
            col := portal_color(int(ch - '0'))
            col.a = u8(255.0 * alpha)
            k2.draw_circle_outline({cx, cy}, TILE_SIZE * 0.45, 2.0, col, 24)
            k2.draw_circle({cx, cy}, TILE_SIZE * 0.2, col, 16)
        }
    }
}

draw_editor_ui :: proc() {
    cam := ui_camera()
    sw := f32(k2.get_screen_size().x)
    sh := f32(k2.get_screen_size().y)
    log_x := cam.target.x
    log_y := cam.target.y
    log_w := sw / cam.zoom
    log_h := sh / cam.zoom

    ui_rect := k2.Rect{log_x, log_y + log_h - 80.0, log_w, 80.0}
    k2.draw_rect(ui_rect, k2.Color{30, 30, 30, 255})

    bx := log_x + 20.0
    by := log_y + log_h - 60.0
    bw := f32(40.0)

    for b in brushes {
        rect := k2.Rect{bx, by, bw, bw}

        if editor_brush == b {
            k2.draw_rect_outline(k2.Rect{bx-5, by-5, bw+10, bw+10}, 2, k2.Color{200, 200, 50, 255})
        }

        switch b {
        case '#':
            source := k2.Rect{48, 48, 16, 16}
            k2.draw_texture_fit(tilemap, source, rect)
        case '^': k2.draw_triangle([3]k2.Vec2{{bx, by+bw}, {bx+bw, by+bw}, {bx+bw/2, by}}, k2.Color{200, 50, 50, 255})
        case 'P':
            src := player_sprite_rect(.Idle, 0)
            p_rect := k2.Rect{bx - bw / 4, by - bw / 3, bw * 1.5, bw * 1.5}
            k2.draw_texture_fit(player_sprite, src, p_rect)
        case 'X':
            src := k2.Rect{0, 0, f32(end_sprite.width), f32(end_sprite.height)}
            k2.draw_texture_fit(end_sprite, src, rect)
        case 'O': k2.draw_rect_outline(k2.Rect{bx+4, by+4, bw-8, bw-8}, 2.0, SLINGSHOT_COLOR_NORMAL)
        case 'o': k2.draw_rect_outline(k2.Rect{bx+4, by+4, bw-8, bw-8}, 2.0, SLINGSHOT_COLOR_BREAK)
        case '1', '2', '3', '4', '5', '6', '7', '8', '9':
            col := portal_color(int(b - '0'))
            cx := bx + bw/2
            cy := by + bw/2
            k2.draw_circle_outline({cx, cy}, bw * 0.45, 2.0, col, 24)
            k2.draw_circle({cx, cy}, bw * 0.2, col, 16)
        }

        if k2.mouse_button_went_down(.Left) {
            mp := k2.get_mouse_position()
            logical_mp := cam.target + mp / cam.zoom
            if logical_mp.x >= bx && logical_mp.x <= bx + bw && logical_mp.y >= by && logical_mp.y <= by + bw {
                editor_brush = b
            }
        }

        bx += bw + 10.0
    }

    if draw_button("BACK", {log_x + log_w - 280, by, 120, 40}) || k2.key_went_down(.Escape) {
        editor_save_map()
        target_slide_x = 0.0
        is_editor_play = false
        game_state = .MainMenu
    }

    if draw_button("PLAY", {log_x + log_w - 140, by, 120, 40}) || k2.key_went_down(.F5) {
        editor_play_test()
    }
}

editor_play_test :: proc() {
    min_row, max_row := EDITOR_HEIGHT, 0
    min_col, max_col := EDITOR_WIDTH, 0

    for r in 0..<EDITOR_HEIGHT {
        for c in 0..<EDITOR_WIDTH {
            if editor_map[r][c] != ' ' {
                if r < min_row do min_row = r
                if r > max_row do max_row = r
                if c < min_col do min_col = c
                if c > max_col do max_col = c
            }
        }
    }

    if min_row > max_row {
        return
    }

    min_row = max(0, min_row - 2)
    max_row = min(EDITOR_HEIGHT - 1, max_row + 2)
    min_col = max(0, min_col - 2)
    max_col = min(EDITOR_WIDTH - 1, max_col + 2)

    new_map := make([]string, max_row - min_row + 1)
    for r in min_row..=max_row {
        row_bytes := make([]u8, max_col - min_col + 1)
        for c in min_col..=max_col {
            row_bytes[c - min_col] = editor_map[r][c]
        }
        new_map[r - min_row] = string(row_bytes)
    }

    level_map = new_map
    level_timer = 0
    player_init()
    rain_init()
    interactables_init()

    sw := f32(k2.get_screen_size().x)
    sh := f32(k2.get_screen_size().y)
    zoom := min(sw / 1280.0, sh / 720.0)
    if zoom <= 0 do zoom = 1.0
    camera.target = player.pos - {sw / (2.0 * zoom), sh / (2.0 * zoom)}

    is_editor_play = true
    game_state = .Playing
}