package main

import "core:math"
import "core:math/rand"
import "core:math/linalg"
import k2 "karl2d"

Anim_State :: enum { Idle, IdleRun, Run, Jump, Fall, JumpFall }

Anim_Def :: struct { fps, frames: int }
ANIM_DEFS := [Anim_State]Anim_Def{
    .Idle     = {8,  6},
    .IdleRun  = {12, 1},
    .Run      = {12, 6},
    .Jump     = {10, 2},
    .Fall     = {10, 1},
    .JumpFall = {12, 2},
}

Player :: struct {
    pos: k2.Vec2,
    vel: k2.Vec2,
    size: k2.Vec2,
    on_ground: bool,
    was_on_ground: bool,
    face_dir: f32,
    squash_x: f32,
    squash_y: f32,
    squash_timer: f32,
    anim_state: Anim_State,
    anim_frame: int,
    anim_timer: f32,
    coyote_timer: f32,
    jump_buffer: f32,
    is_dead: bool,
    on_wall_left: bool,
    on_wall_right: bool,
    wall_coyote_dir: f32,
    wall_coyote_timer: f32,
    lock_timer: f32,
}

History_Frame :: struct {
    time:       f32,
    pos:        k2.Vec2,
    anim_state: Anim_State,
    anim_frame: int,
    face_dir:   f32,
    squash_x:   f32,
    squash_y:   f32,
}

player: Player
player_history: [dynamic]History_Frame
evil_twin_active: bool = false

MOVE_SPEED :: f32(250)
ACCELERATION :: f32(1200)
FRICTION :: f32(2200)
AIR_FRICTION :: f32(400)
GRAVITY :: f32(1200)
JUMP_FORCE :: f32(-600)
MAX_FALL_SPEED :: f32(600)
WALL_JUMP_FORCE_X :: f32(380)
WALL_JUMP_FORCE_Y :: f32(-460)
WALL_SLIDE_MAX_SPEED :: f32(240)
WALL_COYOTE_TIME :: f32(0.3)
JUMP_BUFFER_TIME :: f32(0.12)
COYOTE_TIME :: f32(0.1)

player_init :: proc() {
    spawn: k2.Vec2
    for row in 0..<len(level_map) {
        for col in 0..<len(level_map[row]) {
            if level_map[row][col] == 'P' {
                spawn = {f32(col) * TILE_SIZE + TILE_SIZE/2, f32(row) * TILE_SIZE + TILE_SIZE/2}
            }
        }
    }
    player = Player{
        pos = spawn + {0, 6},
        size = {24, 44},
        face_dir = 1,
        squash_x = 1,
        squash_y = 1,
        is_dead = false,
    }
    clear(&player_history)
    evil_twin_active = false
}

player_update :: proc(dt: f32) {
    input_x: f32
    if k2.key_is_held(.A) { input_x -= 1 }
    if k2.key_is_held(.D) { input_x += 1 }

    if input_x != 0 {
        player.face_dir = input_x
        evil_twin_active = true
    }

    jump_pressed := k2.key_went_down(.Space) || k2.key_went_down(.W)

    if jump_pressed {
        player.jump_buffer = JUMP_BUFFER_TIME
        evil_twin_active = true
    } else {
        player.jump_buffer -= dt
    }

    player.was_on_ground = player.on_ground

    // Wall coyote
    on_any_wall := player.on_wall_left || player.on_wall_right
    if on_any_wall {
        player.wall_coyote_dir   = -1 if player.on_wall_left else 1
        player.wall_coyote_timer = WALL_COYOTE_TIME
    } else {
        player.wall_coyote_timer -= dt
        if player.wall_coyote_timer <= 0 { player.wall_coyote_dir = 0 }
    }

    if player.on_ground {
        player.coyote_timer = COYOTE_TIME
        player.lock_timer   = 0
    } else {
        player.coyote_timer -= dt
    }

    if player.lock_timer > 0 { player.lock_timer -= dt }

    // Wall slide
    on_wall_in_air := !player.on_ground && on_any_wall
    if on_wall_in_air && player.vel.y > 0 {
        if player.vel.y > WALL_SLIDE_MAX_SPEED {
            player.vel.y = WALL_SLIDE_MAX_SPEED
        }
        if rand.float32() < 0.25 {
            wall_x := player.pos.x - player.size.x/2.0 if player.on_wall_left else player.pos.x + player.size.x/2.0
            spawn_particles({wall_x, player.pos.y}, 1, k2.Color{200, 200, 200, 150}, 50, 0.3, 3)
        }
    }

    friction := FRICTION if player.on_ground else AIR_FRICTION
    if input_x == 0 && player.lock_timer <= 0 {
        if      player.vel.x > 0 { player.vel.x = max(player.vel.x - friction * dt, 0) }
        else if player.vel.x < 0 { player.vel.x = min(player.vel.x + friction * dt, 0) }
    } else if player.lock_timer <= 0 {
        target := input_x * MOVE_SPEED
        if abs(player.vel.x) < abs(target) || sign(player.vel.x) != sign(target) {
            player.vel.x += input_x * ACCELERATION * dt
        }
    }

    // Regular jump
    did_jump := false
    if player.jump_buffer > 0 && player.coyote_timer > 0 {
        player.vel.y              = JUMP_FORCE
        player.jump_buffer        = 0
        player.coyote_timer       = 0
        player.squash_y           = 1.4
        player.squash_x           = 0.7
        player.squash_timer       = 0.15
        spawn_particles(player.pos, 15, k2.Color{200, 200, 200, 200}, 150, 0.4, 4)
        did_jump = true
    }

    // Wall jump
    if !did_jump && player.jump_buffer > 0 && !player.on_ground && player.wall_coyote_dir != 0 {
        wall_dir := player.wall_coyote_dir
        player.vel.x              = -wall_dir * WALL_JUMP_FORCE_X
        player.vel.y              = WALL_JUMP_FORCE_Y
        player.jump_buffer        = 0
        player.wall_coyote_dir    = 0
        player.wall_coyote_timer  = 0
        player.face_dir           = -wall_dir
        player.squash_y           = 1.35
        player.squash_x           = 0.72
        player.squash_timer       = 0.15
        player.lock_timer         = 0.25
        spawn_particles(player.pos - {0, player.size.y/2}, 20, k2.Color{200, 220, 255, 200}, 200, 0.4, 4)
    }

    player.vel.y += GRAVITY * dt
    if player.vel.y > MAX_FALL_SPEED { player.vel.y = MAX_FALL_SPEED }

    player.on_ground = false
    player.on_wall_left = false
    player.on_wall_right = false
    move_and_collide(dt)

    if player.on_ground && !player.was_on_ground && player.vel.y > 200 {
        player.squash_y     = 0.65
        player.squash_x     = 1.35
        player.squash_timer = 0.12
        spawn_particles({player.pos.x, player.pos.y}, 15, k2.Color{150, 150, 150, 150}, 100.0, 0.4, 5.0)
    }

    if player.squash_timer > 0 {
        player.squash_timer -= dt
        t := 1 - clamp(player.squash_timer / 0.15, 0, 1)
        player.squash_y = math.lerp(player.squash_y, 1.0, t * 8 * dt + 0.2)
        player.squash_x = math.lerp(player.squash_x, 1.0, t * 8 * dt + 0.2)
    } else {
        player.squash_y = 1
        player.squash_x = 1
    }

    if player.on_ground {
        #partial switch player.anim_state {
        case .JumpFall: set_anim(.Fall)
        case .Fall:
        case .Jump: set_anim(.Fall)
        case:
            if abs(player.vel.x) > 10 {
                if player.anim_state != .Run && player.anim_state != .IdleRun { set_anim(.IdleRun) }
            } else {
                if player.anim_state != .Idle { set_anim(.Idle) }
            }
        }
    } else {
        if player.vel.y < 0 {
            if player.anim_state != .Jump { set_anim(.Jump) }
        } else {
            if player.anim_state == .Jump { set_anim(.JumpFall) }
            else if player.anim_state != .JumpFall && player.anim_state != .Fall { set_anim(.Fall) }
        }
    }

    if evil_twin_active {
        append(&player_history, History_Frame{
            time       = level_timer,
            pos        = player.pos,
            anim_state = player.anim_state,
            anim_frame = player.anim_frame,
            face_dir   = player.face_dir,
            squash_x   = player.squash_x,
            squash_y   = player.squash_y,
        })
    }

    for len(player_history) > 0 && level_timer - player_history[0].time > 2.0 {
        ordered_remove(&player_history, 0)
    }

    player_update_anim(dt)
}

player_draw :: proc() {
    src := player_sprite_rect(player.anim_state, player.anim_frame)
    draw_player_spritesheet(player_sprite, src, player.pos, player.size, player.squash_x, player.squash_y, player.face_dir)
}

set_anim :: proc(state: Anim_State, force := false) {
    if !force && player.anim_state == state { return }
    player.anim_state = state
    player.anim_frame = 0
    player.anim_timer = 0
}

player_update_anim :: proc(dt: f32) {
    def := ANIM_DEFS[player.anim_state]

    player.anim_timer += dt
    if player.anim_timer >= 1.0 / f32(def.fps) {
        player.anim_timer -= 1.0 / f32(def.fps)
        player.anim_frame += 1

        if player.anim_frame >= def.frames {
            #partial switch player.anim_state {
            case .IdleRun:  set_anim(.Run)
            case .Fall:     set_anim(.Idle)
            case .Jump:     player.anim_frame = def.frames - 1
            case .JumpFall: player.anim_frame = 0
            case:           player.anim_frame = 0
            }
        }
    }
}

player_sprite_rect :: proc(state: Anim_State, frame: int) -> k2.Rect {
    row: int
    switch state {
    case .Idle:     row = 0
    case .IdleRun:  row = 1
    case .Run:      row = 2
    case .Jump:     row = 3
    case .Fall:     row = 4
    case .JumpFall: row = 5
    }
    return k2.Rect{f32(frame * 96), f32(row * 96), 96, 96}
}

draw_player_spritesheet :: proc(tex: k2.Texture, src: k2.Rect, pos, size: k2.Vec2, sx, sy, face_dir: f32, tint := k2.WHITE) {
    w := 96 * sx
    h := 96 * sy

    src_rect := src
    if face_dir < 0 {
        src_rect.x += src_rect.w
        src_rect.w = -src_rect.w
    }

    dest := k2.Rect{pos.x - w/2, pos.y - h + 10, w, h}
    k2.draw_texture_fit(tex, src_rect, dest, {0, 0}, 0, tint)
}

player_rect :: proc() -> k2.Rect {
    return {player.pos.x - player.size.x/2, player.pos.y - player.size.y, player.size.x, player.size.y}
}

tile_rect :: proc(tx, ty: int) -> k2.Rect {
    return {f32(tx) * TILE_SIZE, f32(ty) * TILE_SIZE, TILE_SIZE, TILE_SIZE}
}

tile_is_solid :: proc(tx, ty: int) -> bool {
    if ty < 0 || ty >= len(level_map) || tx < 0 || tx >= len(level_map[0]) { return false }
    return level_map[ty][tx] == '#'
}

sign :: proc(v: f32) -> f32 { return 1 if v > 0 else (-1 if v < 0 else 0) }

move_and_collide :: proc(dt: f32) {
    player.pos.x += player.vel.x * dt; resolve_x()
    player.pos.y += player.vel.y * dt; resolve_y()
}

resolve_x :: proc() {
    r := player_rect()
    r.y += 0.1
    r.h -= 0.2

    tx0 := int(math.floor(r.x / TILE_SIZE))
    tx1 := int(math.floor((r.x + r.w - 0.001) / TILE_SIZE))
    ty0 := int(math.floor(r.y / TILE_SIZE))
    ty1 := int(math.floor((r.y + r.h - 0.001) / TILE_SIZE))

    for ty in ty0..=ty1 {
        for tx in tx0..=tx1 {
            if !tile_is_solid(tx, ty) { continue }
            ox := rect_overlap_x(r, tile_rect(tx, ty))
            if ox == 0 { continue }

            if ox > 0 { player.on_wall_left  = true }
            if ox < 0 { player.on_wall_right = true }

            player.pos.x += ox
            player.vel.x = 0
            r = player_rect()
            r.y += 0.1
            r.h -= 0.2
        }
    }
}

resolve_y :: proc() {
    r := player_rect()
    r.x += 0.1
    r.w -= 0.2

    tx0 := int(math.floor(r.x / TILE_SIZE))
    tx1 := int(math.floor((r.x + r.w - 0.001) / TILE_SIZE))
    ty0 := int(math.floor(r.y / TILE_SIZE))
    ty1 := int(math.floor((r.y + r.h - 0.001) / TILE_SIZE))

    for ty in ty0..=ty1 {
        for tx in tx0..=tx1 {
            if !tile_is_solid(tx, ty) { continue }
            tr := tile_rect(tx, ty)
            oy := rect_overlap_y(r, tr)
            if oy == 0 { continue }

            player.pos.y += oy
            if oy < 0 {
                player.on_ground = true;
                if player.vel.y > 0 { player.vel.y = 0 }
            } else {
                if player.vel.y < 0 { player.vel.y = 0 }
            }
            r = player_rect()
            r.x += 0.1
            r.w -= 0.2
        }
    }
}

rect_overlap_x :: proc(a, b: k2.Rect) -> f32 {
    if a.x+a.w <= b.x || a.x >= b.x+b.w || a.y+a.h <= b.y || a.y >= b.y+b.h { return 0 }
    right := b.x + b.w - a.x
    left  := a.x + a.w - b.x
    return right if right < left else -left
}

rect_overlap_y :: proc(a, b: k2.Rect) -> f32 {
    if a.x+a.w <= b.x || a.x >= b.x+b.w || a.y+a.h <= b.y || a.y >= b.y+b.h { return 0 }
    down := b.y + b.h - a.y
    up   := a.y + a.h - b.y
    return down if down < up else -up
}

check_hazards :: proc() {
    if transition_state == .FadeOut { return }

    pr := player_rect()
    pr.y += 4.0
    pr.h -= 8.0
    pr.x += 4.0
    pr.w -= 8.0

    for row in 0..<len(level_map) {
        for col in 0..<len(level_map[row]) {
            ch := level_map[row][col]
            if ch == '^' {
                tr := tile_rect(col, row)
                tr.y += TILE_SIZE * 0.4
                tr.h -= TILE_SIZE * 0.4
                if rect_overlap_x(pr, tr) != 0 && rect_overlap_y(pr, tr) != 0 {
                    die()
                    return
                }
            } else if ch == 'X' {
                tr := tile_rect(col, row)
                if rect_overlap_x(pr, tr) != 0 && rect_overlap_y(pr, tr) != 0 {
                    win()
                    return
                }
            }
        }
    }

    if player.pos.y > f32(len(level_map)) * TILE_SIZE + 500 {
        die()
    }
}

die :: proc() {
    if transition_state == .FadeOut { return }
    player.is_dead = true
    spawn_particles({player.pos.x, player.pos.y - 20}, 30, k2.Color{255, 50, 50, 255}, 150.0, 0.5, 6.0)
    start_transition(proc() {
        if is_editor_play {
            editor_play_test()
        } else {
            level_load(current_level_index)
        }
    })
}

win :: proc() {
    if transition_state == .FadeOut { return }

    if !is_editor_play && (level_timer < level_best_times[current_level_index] || level_best_times[current_level_index] == 0) {
        level_best_times[current_level_index] = level_timer
        save_settings()
    }

    start_transition(proc() {
        if is_editor_play {
            game_state = .Editor
        } else {
            if current_level_index + 1 < len(level_defs) {
                current_level_index += 1
                level_load(current_level_index)
            } else {
                game_state = .MainMenu
                target_slide_x = 0
                menu_slide_x = -1280
            }
        }
    })
}

evil_twin_update :: proc(dt: f32) {
    if !evil_twin_active { return }
    if len(player_history) < 2 { return }

    target_time := level_timer - 1.2
    if target_time <= player_history[0].time { return }

    f0_idx := -1
    for i in 0..<len(player_history) {
        if player_history[i].time > target_time {
            break
        }
        f0_idx = i
    }

    if f0_idx == -1 || f0_idx >= len(player_history) - 1 { return }

    f0 := player_history[f0_idx]
    f1 := player_history[f0_idx + 1]

    t := (target_time - f0.time) / (f1.time - f0.time)

    interp_pos := linalg.lerp(f0.pos, f1.pos, t)
    interp_sq_x := math.lerp(f0.squash_x, f1.squash_x, t)
    interp_sq_y := math.lerp(f0.squash_y, f1.squash_y, t)

    p_rect := player_rect()
    twin_rect := k2.Rect{
        interp_pos.x - player.size.x / 2,
        interp_pos.y - player.size.y,
        player.size.x,
        player.size.y,
    }

    if k2.rect_overlapping(p_rect, twin_rect) {
        die()
    }

    src := player_sprite_rect(f0.anim_state, f0.anim_frame)
    draw_player_spritesheet(evil_sprite, src, interp_pos, player.size, interp_sq_x, interp_sq_y, f0.face_dir, k2.WHITE)
}
