package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import k2 "karl2d"

TILE_SIZE :: f32(25)

Game_State :: enum { MainMenu, LevelSelect, Settings, Editor, Playing }
game_state: Game_State = .MainMenu

sfx_volume       := f32(0.5)
music_volume     := f32(0.3)
is_fullscreen    := false
is_speedruning   := false
is_editor_play   := false
level_best_times : [len(level_defs)]f32

menu_slide_x:   f32
target_slide_x: f32
level_timer:    f32
game_time:      f32

music:         k2.Audio_Stream
player_sprite: k2.Texture
evil_sprite:   k2.Texture
tilemap:       k2.Texture
end_sprite:    k2.Texture
camera:        k2.Camera
parallax:      [5]k2.Texture

main :: proc() {
	init()
	for step() {}
}

init :: proc() {
    k2.init(1280, 720, "Backstabber", {anti_alias = true, window_mode = .Windowed_Resizable})

    player_sprite = k2.load_texture_from_bytes(#load("assets/player.png"))
    evil_sprite   = k2.load_texture_from_bytes(#load("assets/evil.png"))
    tilemap       = k2.load_texture_from_bytes(#load("assets/tilemap.png"))
    end_sprite    = k2.load_texture_from_bytes(#load("assets/exit.png"))
    parallax = {
        k2.load_texture_from_bytes(#load("assets/background/1.png")),
        k2.load_texture_from_bytes(#load("assets/background/2.png")),
        k2.load_texture_from_bytes(#load("assets/background/3.png")),
        k2.load_texture_from_bytes(#load("assets/background/4.png")),
        k2.load_texture_from_bytes(#load("assets/background/5.png")),
    }

    music = k2.load_audio_stream_from_bytes(#load("assets/music.ogg"))
    k2.set_audio_stream_volume(music, music_volume * music_volume * music_volume)
    k2.play_audio_stream(music)
    k2.set_audio_stream_loop(music, true)

    load_settings()
    level_load(0)
}

step :: proc() -> bool {
	if !k2.update() do return false

    dt := k2.get_frame_time()
    if dt > 1.0/10.0 { dt = 1.0/10.0 }
    menu_slide_x += (target_slide_x - menu_slide_x) * 10.0 * dt

    k2.clear(k2.Color{0, 0, 0, 255})

    if k2.key_went_down(.F11) {
        is_fullscreen = !is_fullscreen
        if is_fullscreen {
            k2.set_window_mode(.Borderless_Fullscreen)
        } else {
            k2.set_window_mode(.Windowed_Resizable)
        }
        save_settings()
    }

    if game_state == .MainMenu || game_state == .LevelSelect || game_state == .Settings {
        camera.target.x += 30.0 * dt
        draw_parallax(k2.Color{100, 100, 100, 255})
    }

    switch game_state {
    case .MainMenu:
        k2.set_camera(ui_camera())
        if step_main_menu(dt) do return false
    case .LevelSelect:
        k2.set_camera(ui_camera())
        step_level_select(dt)
    case .Settings:
        k2.set_camera(ui_camera())
        step_settings(dt)
    case .Editor:
        step_editor(dt)
    case .Playing:
        if k2.key_went_down(.Escape) {
            if is_editor_play {
                game_state = .Editor
            } else {
                target_slide_x = -1280.0
                game_state = .LevelSelect
            }
        }
        if k2.key_went_down(.R) {
            if is_speedruning {
                game_time = 0.0
                current_level_index = 0
                start_transition(proc() {
                    level_load(0)
                })
            } else {
                die()
            }
        }

        ts := dt
        if inter_state.aiming {
            ts *= 0.15
        }

        if transition_state != .FadeOut {
            if !player.is_dead {
                player_update(ts)
                interactables_update(dt)
                level_timer += ts
                game_time += ts
            }
            check_hazards()
        }

        update_particles(ts)
        rain_update(ts)

        sw := k2.get_screen_size().x
        sh := k2.get_screen_size().y
        camera.zoom = min(sw / 1280.0, sh / 720.0) * 0.8

        offset := k2.get_screen_size() / (2.0 * camera.zoom)
        target_cam := player.pos - offset
        camera.target = linalg.lerp(camera.target, target_cam, 1 - math.pow(0.001, dt))

        draw_parallax(k2.Color{180, 180, 180, 255})

        k2.set_camera(camera)
        draw_level()
        if !player.is_dead {
            player_draw()
        }

        evil_twin_update(ts)
        interactables_draw()
        draw_particles()
        rain_draw()

        k2.set_camera(ui_camera())

        time_str := fmt.tprintf("%.2f", level_timer)
        k2.draw_text(time_str, {10, 10} + 1, 32, k2.BLACK)
        k2.draw_text(time_str, {10, 10}, 32, k2.WHITE)

        if level_best_times[current_level_index] != 0 {
            best_str := fmt.tprintf("Best: %.2f", level_best_times[current_level_index])
            k2.draw_text(best_str, {10, 40} + 1, 20, k2.Color{100, 50, 0, 255})
            k2.draw_text(best_str, {10, 40}, 20, k2.Color{255, 200, 100, 255})
        }

        if is_speedruning {
            sw := f32(1280.0)
            sr_str := fmt.tprintf("%.2f", game_time)
            sr_w := k2.measure_text(sr_str, 36, k2.FONT_DEFAULT).x
            k2.draw_text(sr_str, {sw/2.0 - sr_w/2.0, 10}+1, 36, k2.BLACK)
            k2.draw_text(sr_str, {sw/2.0 - sr_w/2.0, 10}, 36, k2.WHITE)
        }
    }

    update_transition(dt)

    k2.set_camera(nil)
    draw_transition()
    k2.update_audio_stream(music)
    k2.present()

    return true
}

draw_button :: proc(label: string, rect: k2.Rect, font_size: f32 = 24) -> bool {
    m := k2.screen_to_world(k2.get_mouse_position(), ui_camera())
    hover := k2.point_in_rect(m, rect)

    bg := hover ? k2.Color{70, 70, 130, 255} : k2.Color{40, 40, 70, 255}
    border := hover ? k2.Color{180, 180, 255, 255} : k2.Color{100, 100, 180, 255}

    if hover && k2.mouse_button_is_held(.Left) {
        bg = k2.Color{30, 30, 60, 255}
    }

    k2.draw_rect(rect, bg)
    k2.draw_rect_outline(rect, 2, border)

    text_w := k2.measure_text(label, font_size, k2.FONT_DEFAULT).x
    text_x := rect.x + (rect.w - text_w) / 2.0
    text_y := rect.y + (rect.h - font_size) / 2.0

    k2.draw_text(label, {text_x, text_y}, font_size, k2.WHITE)

    return hover && k2.mouse_button_went_up(.Left)
}

draw_slider :: proc(label: string, value: ^f32, x, y, w, h: f32) {
    m := k2.screen_to_world(k2.get_mouse_position(), ui_camera())
    mx := m.x
    my := m.y

    k2.draw_text(label, {x, y - 24}, 20, k2.WHITE)
    k2.draw_rect(k2.Rect{x, y, w, h}, k2.Color{40, 40, 70, 255})
    fill_w := w * value^
    k2.draw_rect(k2.Rect{x, y, fill_w, h}, k2.Color{100, 100, 200, 255})
    k2.draw_rect_outline(k2.Rect{x, y, w, h}, 2, k2.Color{100, 100, 180, 255})

    hover := mx >= x - 20 && mx <= x + w + 20 && my >= y - 10 && my <= y + h + 10
    if hover && k2.mouse_button_is_held(.Left) {
        t := (mx - x) / w
        value^ = clamp(t, 0.0, 1.0)
    }
}

step_main_menu :: proc(dt: f32) -> bool {
    cx := f32(1280) / 2.0
    cy := f32(720) / 2.0

    title_text := "BACKSTABBER"
    title_w := k2.measure_text(title_text, 80, k2.FONT_DEFAULT).x
    k2.draw_text(title_text, {cx - title_w/2.0 + menu_slide_x, cy - 200}, 80, k2.WHITE)

    bw, bh: f32 = 280, 50
    bx := cx - bw/2.0 + menu_slide_x
    by := cy - 50

    if draw_button("PLAY", {bx, by, bw, bh}) {
        target_slide_x = -1280.0
        game_state = .LevelSelect
    }
    if draw_button("EDITOR", {bx, by + 60, bw, bh}) {
        target_slide_x = 0.0
        game_state = .Editor
        editor_init()
    }
    if draw_button("SETTINGS", {bx, by + 120, bw, bh}) {
        target_slide_x = 1280.0
        game_state = .Settings
    }

    when ODIN_OS != .JS {
        if draw_button("EXIT", {bx, by + (bh+10) * 3, bw, bh}) { return true }
    }

    return false
}

step_settings :: proc(dt: f32) {
    cx := f32(1280) / 2.0
    cy := f32(720) / 2.0

    base_x := menu_slide_x - 1280.0

    title_text := "SETTINGS"
    title_w := k2.measure_text(title_text, 48, k2.FONT_DEFAULT).x
    k2.draw_text(title_text, {cx - title_w/2.0 + base_x, cy - 240}, 48, k2.WHITE)

    draw_slider("MUSIC VOLUME", &music_volume, cx - 200 + base_x, cy - 140, 400, 30)
    k2.set_audio_stream_volume(music, music_volume * music_volume * music_volume)

    draw_slider("SFX VOLUME", &sfx_volume, cx - 200 + base_x, cy - 50, 400, 30)

    fs_label := is_fullscreen ? "FULLSCREEN: ON" : "FULLSCREEN: OFF"
    if draw_button(fs_label, {cx - 210 + base_x, cy + 40, 200, 50}) {
        is_fullscreen = !is_fullscreen
        if is_fullscreen {
            k2.set_window_mode(.Borderless_Fullscreen)
        } else {
            k2.set_window_mode(.Windowed_Resizable)
        }
        save_settings()
    }

    sr_label := is_speedruning ? "SPEEDRUN: ON" : "SPEEDRUN: OFF"
    if draw_button(sr_label, {cx + 10 + base_x, cy + 40, 200, 50}) {
        is_speedruning = !is_speedruning
        save_settings()
    }

    if k2.mouse_button_went_up(.Left) {
        save_settings()
    }

    if draw_button("BACK", {cx - 70 + base_x, cy + 240, 140, 44}) {
        target_slide_x = 0.0
        game_state = .MainMenu
        save_settings()
    }
}

step_level_select :: proc(dt: f32) {
    cx := f32(1280) / 2.0
    cy := f32(720) / 2.0

    title_text := "SELECT LEVEL"
    title_w := k2.measure_text(title_text, 48, k2.FONT_DEFAULT).x
    k2.draw_text(title_text, {cx - title_w/2.0 + menu_slide_x + 1280.0, cy - 240}, 48, k2.WHITE)

    cols := 5
    bw, bh: f32 = 120, 100
    gap: f32 = 20
    start_x := cx - f32(cols)*(bw+gap)/2.0 + menu_slide_x + 1280.0
    start_y := cy - 120

    for i in 0..<len(level_defs) {
        row := i / cols
        col := i % cols
        bx := start_x + f32(col)*(bw+gap)
        by := start_y + f32(row)*(bh+gap)

        label := fmt.tprintf("Level %d", i+1)
        if draw_button(label, {bx, by, bw, bh}) {
            current_level_index = i
            if is_speedruning && i != 0 {
                is_speedruning = false
                save_settings()
            }
            if i == 0 {
                game_time = 0.0
            }
            game_state = .Playing
            level_load(current_level_index)
        }

        if level_best_times[i] != 0 {
            time_str := fmt.tprintf("%.2fs", level_best_times[i])
            tw := k2.measure_text(time_str, 16, k2.FONT_DEFAULT).x
            k2.draw_text(time_str, {bx + bw/2.0 - tw/2.0, by + bh - 28}, 16, k2.LIGHT_GRAY)
        }
    }

    if draw_button("BACK", {cx - 70 + menu_slide_x + 1280.0, cy + 240, 140, 44}) {
        target_slide_x = 0.0
        game_state = .MainMenu
    }
}

ui_camera :: proc() -> k2.Camera {
    sw := k2.get_screen_size().x
    sh := k2.get_screen_size().y
    zoom := min(sw / 1280.0, sh / 720.0)

    return k2.Camera{
        zoom = zoom,
        target = {-(sw/zoom - 1280.0)/2.0, -(sh/zoom - 720.0)/2.0},
    }
}
