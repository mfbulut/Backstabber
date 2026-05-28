package main

import "core:math"
import "core:math/rand"
import k2 "karl2d"

RAIN_DROP_COUNT   :: 1000
RAIN_SPEED_MIN    :: f32(600)
RAIN_SPEED_MAX    :: f32(900)
RAIN_ANGLE        :: f32(0.18)
RAIN_DROP_W       :: f32(2)
RAIN_DROP_H_MIN   :: f32(6)
RAIN_DROP_H_MAX   :: f32(14)
RAIN_COLOR        :: k2.Color{120, 160, 220, 140}
RAIN_COLOR_LIGHT  :: k2.Color{180, 210, 255, 80}

SPLASH_MAX        :: 200
SPLASH_SPEED      :: f32(120)
SPLASH_LIFE       :: f32(0.32)
SPLASH_PIXEL_SIZE :: f32(2)

Rain_Drop :: struct {
    pos:     k2.Vec2,
    vel:     k2.Vec2,
    length:  f32,
    alpha:   u8,
    active:  bool,
}

Splash_Particle :: struct {
    pos:      k2.Vec2,
    vel:      k2.Vec2,
    life:     f32,
    max_life: f32,
    active:   bool,
}

rain_drops:       [RAIN_DROP_COUNT]Rain_Drop
splash_particles: [SPLASH_MAX]Splash_Particle

rain_init :: proc() {
    for i in 0..<RAIN_DROP_COUNT {
        rain_spawn_drop(&rain_drops[i], true)
    }
}

rain_spawn_drop :: proc(d: ^Rain_Drop, anywhere: bool) {
    speed  := RAIN_SPEED_MIN + rand.float32() * (RAIN_SPEED_MAX - RAIN_SPEED_MIN)
    d.vel  = {math.sin(RAIN_ANGLE) * speed, math.cos(RAIN_ANGLE) * speed}
    d.length = RAIN_DROP_H_MIN + rand.float32() * (RAIN_DROP_H_MAX - RAIN_DROP_H_MIN)
    d.alpha  = 100 + u8(rand.float32() * 100)
    d.active = true

    h := len(level_map)
    w := len(level_map[0]) if h > 0 else 0
    map_w := f32(w) * TILE_SIZE
    map_h := f32(h) * TILE_SIZE

    padding := f32(50) * TILE_SIZE
    min_x   := -padding
    max_x   := map_w + padding

    wind_offset := (map_h + padding) * math.sin(RAIN_ANGLE)
    d.pos.x = min_x + rand.float32() * (max_x - min_x + math.abs(wind_offset)) - math.max(0, wind_offset)

    spawn_height := f32(1000)

    if anywhere {
        d.pos.y = -spawn_height + rand.float32() * (map_h + 800 + spawn_height)
    } else {
        d.pos.y = -spawn_height - rand.float32() * 500
    }
}

rain_spawn_splash :: proc(pos: k2.Vec2) {
    count := 3 + int(rand.float32() * 3)
    spawned := 0
    for i in 0..<SPLASH_MAX {
        if !splash_particles[i].active {
            angle := -math.PI + rand.float32() * math.PI
            speed := SPLASH_SPEED * (0.4 + rand.float32() * 0.6)
            splash_particles[i] = Splash_Particle{
                pos      = pos,
                vel      = {math.cos(angle) * speed, -math.abs(math.sin(angle)) * speed},
                life     = SPLASH_LIFE * (0.7 + rand.float32() * 0.3),
                max_life = SPLASH_LIFE,
                active   = true,
            }
            spawned += 1
            if spawned >= count { break }
        }
    }
}

rain_update :: proc(dt: f32) {
    dx := math.sin(RAIN_ANGLE)
    dy := math.cos(RAIN_ANGLE)

    h := len(level_map)
    w := len(level_map[0]) if h > 0 else 0
    map_w := f32(w) * TILE_SIZE
    map_h := f32(h) * TILE_SIZE

    padding := f32(50) * TILE_SIZE
    min_x   := -padding
    max_x   := map_w + padding

    for i in 0..<RAIN_DROP_COUNT {
        d := &rain_drops[i]
        if !d.active { continue }

        d.pos += d.vel * dt

        lead_world := k2.Vec2{
            d.pos.x + dx * d.length,
            d.pos.y + dy * d.length,
        }

        tile_x := int(math.floor(lead_world.x / TILE_SIZE))
        tile_y := int(math.floor(lead_world.y / TILE_SIZE))

        hit_solid := tile_is_solid(tile_x, tile_y)

        if hit_solid {
            rain_spawn_splash(lead_world)
            rain_spawn_drop(d, false)
        } else if d.pos.y > map_h + 800 || d.pos.x < min_x - 400 || d.pos.x > max_x + 400 {
            rain_spawn_drop(d, false)
        }
    }

    for i in 0..<SPLASH_MAX {
        s := &splash_particles[i]
        if !s.active { continue }

        s.pos   += s.vel * dt
        s.vel.y += 300 * dt
        s.life  -= dt
        if s.life <= 0 { s.active = false }
    }
}

rain_draw :: proc() {
    screen := k2.get_screen_size()
    view_min := camera.target
    view_max := camera.target + screen / camera.zoom

    dx := math.sin(RAIN_ANGLE)
    dy := math.cos(RAIN_ANGLE)

    // Max bounding box expansion from drop length — no per-drop trig needed
    max_extent := RAIN_DROP_H_MAX

    for i in 0..<RAIN_DROP_COUNT {
        d := &rain_drops[i]
        if !d.active { continue }

        if d.pos.x + max_extent < view_min.x || d.pos.x > view_max.x ||
           d.pos.y + max_extent < view_min.y || d.pos.y > view_max.y {
            continue
        }

        seg_count := int(d.length / RAIN_DROP_W)

        for s in 0..<seg_count {
            px := d.pos.x + f32(s) * dx * RAIN_DROP_W
            py := d.pos.y + f32(s) * dy * RAIN_DROP_W

            col: k2.Color
            if s % 2 == 0 {
                col = {RAIN_COLOR.r, RAIN_COLOR.g, RAIN_COLOR.b, d.alpha}
            } else {
                col = {RAIN_COLOR_LIGHT.r, RAIN_COLOR_LIGHT.g, RAIN_COLOR_LIGHT.b, u8(f32(d.alpha) * 0.55)}
            }

            k2.draw_rect(k2.Rect{px, py, RAIN_DROP_W, RAIN_DROP_W}, col)
        }
    }

    for i in 0..<SPLASH_MAX {
        s := &splash_particles[i]
        if !s.active { continue }

        if s.pos.x < view_min.x || s.pos.x > view_max.x ||
           s.pos.y < view_min.y || s.pos.y > view_max.y {
            continue
        }

        t   := s.life / s.max_life
        alpha := u8(f32(180) * t)

        k2.draw_rect(
            k2.Rect{s.pos.x, s.pos.y, SPLASH_PIXEL_SIZE, SPLASH_PIXEL_SIZE},
            k2.Color{160, 200, 255, alpha},
        )

        k2.draw_rect(
            k2.Rect{s.pos.x - SPLASH_PIXEL_SIZE, s.pos.y - SPLASH_PIXEL_SIZE, SPLASH_PIXEL_SIZE, SPLASH_PIXEL_SIZE},
            k2.Color{220, 240, 255, u8(f32(alpha) * 0.5)},
        )
    }
}