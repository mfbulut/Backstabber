package main

import "core:math"
import "core:math/rand"

import k2 "karl2d"

Particle :: struct {
    pos:      k2.Vec2,
    vel:      k2.Vec2,
    color:    k2.Color,
    life:     f32,
    max_life: f32,
    size:     f32,
}

particles: [dynamic]Particle

spawn_particles :: proc(pos: k2.Vec2, count: int, color: k2.Color, speed, life, size: f32) {
    for _ in 0..<count {
        angle := rand.float32() * math.PI * 2
        append(&particles, Particle{
            pos      = pos,
            vel      = k2.Vec2{math.cos(angle), math.sin(angle)} * rand.float32() * speed,
            color    = color,
            life     = life * (0.8 + 0.4 * rand.float32()),
            max_life = life,
            size     = size * (0.8 + 0.4 * rand.float32()),
        })
    }
}

update_particles :: proc(dt: f32) {
    for i := 0; i < len(particles); {
        p := &particles[i]
        p.life -= dt
        if p.life <= 0 {
            unordered_remove(&particles, i)
            continue
        }
        p.pos   += p.vel * dt
        p.vel.y += GRAVITY * 0.4 * dt
        i += 1
    }
}

draw_particles :: proc() {
    for p in particles {
        c := p.color
        c.a = min(u8(255.0 * (p.life / p.max_life)), p.color.a)
        k2.draw_rect(k2.Rect{p.pos.x - p.size/2, p.pos.y - p.size/2, p.size, p.size}, c)
    }
}

draw_parallax :: proc(tint: k2.Color) {
    parallax_factors := [5]f32{0.0, 0.05, 0.1, 0.15, 0.2}

    screen := k2.get_screen_size()
    k2.set_camera(nil)

    for layer, i in parallax {
        src_w := f32(layer.width)
        src_h := f32(layer.height)

        cx : f32 = 0  + camera.target.x * parallax_factors[i]
        cy : f32 = min(80 + camera.target.y * parallax_factors[i], 120)

        src := k2.Rect{cx, cy, src_w, src_h}
        dst := k2.Rect{0, 0, screen.x, screen.y}

        k2.draw_texture_fit(layer, src, dst, {}, 0, tint)
    }
}

Transition_State :: enum { None, FadeOut, FadeIn }
transition_state: Transition_State = .None
transition_timer: f32 = 0.0
transition_duration: f32 = 0.4
transition_callback: proc()

start_transition :: proc(cb: proc()) {
    if transition_state == .FadeOut { return }
    transition_state = .FadeOut
    transition_timer = 0.0
    transition_callback = cb
}

update_transition :: proc(dt: f32) {
    if transition_state == .None { return }

    transition_timer += dt

    if transition_state == .FadeOut {
        if transition_timer >= transition_duration {
            if transition_callback != nil { transition_callback() }
            transition_state = .FadeIn
            transition_timer = 0.0
        }
    } else if transition_state == .FadeIn {
        if transition_timer >= transition_duration {
            transition_state = .None
        }
    }
}

draw_transition :: proc() {
    if transition_state == .None { return }

    t := clamp(transition_timer / transition_duration, 0.0, 1.0)
    alpha: f32
    if transition_state == .FadeOut {
        alpha = t
    } else {
        alpha = 1.0 - t
    }

    screen := k2.get_screen_size()
    k2.draw_rect(k2.Rect{0, 0, screen.x, screen.y}, k2.Color{0, 0, 0, u8(alpha * 255.0)})
}