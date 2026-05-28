package main

import "core:math"
import "core:math/rand"
import "core:math/linalg"
import k2 "karl2d"

PORTAL_RADIUS        :: f32(130)
SLINGSHOT_RADIUS     :: f32(120)
SLINGSHOT_SPEED      :: k2.Vec2{600 * 1, 600 * 1.3}
PORTAL_SPIRAL_SPEED  :: f32(1.2)
PORTAL_PULL_DURATION :: f32(0.3)
PORTAL_EXIT_SPEED    :: f32(650)
CLICK_BUFFER_TIME    :: f32(0.12)

PORTAL_COLORS := [9]k2.Color{
    {100, 180, 255, 255}, // 1 sky blue
    {120, 255, 120, 255}, // 2 lime
    {255, 120, 220, 255}, // 3 pink
    {180, 100, 255, 255}, // 5 purple
    { 60, 220, 220, 255}, // 6 cyan
    {255, 140,  60, 255}, // 7 orange
    {200, 255, 100, 255}, // 8 yellow-green
    {255,  80,  80, 255}, // 9 red
    {255, 200,  60, 255}, // 4 gold
}

SLINGSHOT_COLOR_NORMAL   :: k2.Color{255, 220, 60, 255}
SLINGSHOT_COLOR_BREAK    :: k2.Color{60, 220, 255, 255}

Portal :: struct {
    world_pos: k2.Vec2,
    digit:     int,
    partner_index: int,
}

Slingshot :: struct {
    world_pos: k2.Vec2,
    breakable: bool,
    broken:    bool,
}

Interactable_State :: struct {
    aiming:          bool,
    is_portal:       bool,
    target_index:    int,
    spiraling:       bool,
    click_buffer:    f32,

    timer:         f32,
    spiral_angle:  f32,
    start_dist:    f32,
    target_pos:    k2.Vec2,
    exit_dir:      k2.Vec2,
}

portals:     [dynamic]Portal
slingshots:  [dynamic]Slingshot
inter_state: Interactable_State

interactables_init :: proc() {
    clear(&portals)
    clear(&slingshots)
    inter_state = {}

    h := len(level_map)
    w := len(level_map[0]) if h > 0 else 0

    for row in 0..<h {
        for col in 0..<w {
            ch := level_map[row][col]
            wx := f32(col)*TILE_SIZE + TILE_SIZE/2
            wy := f32(row)*TILE_SIZE + TILE_SIZE/2

            if ch >= '1' && ch <= '9' {
                append(&portals, Portal{
                    world_pos = {wx, wy},
                    digit     = int(ch - '0'),
                    partner_index = -1,
                })
            } else if ch == 'O' || ch == 'o' {
                append(&slingshots, Slingshot{
                    world_pos = {wx, wy},
                    breakable = (ch == 'o'),
                    broken    = false,
                })
            }
        }
    }

    for i in 0..<len(portals) {
        for j in 0..<len(portals) {
            if i != j && portals[i].digit == portals[j].digit {
                portals[i].partner_index = j
                break
            }
        }
    }
}

find_nearest_interactable :: proc(world_pos: k2.Vec2) -> (is_portal: bool, index: int, dist: f32) {
    best_dist := f32(9999.0)
    best_is_portal := false
    best_index := -1

    for p, i in portals {
        d := linalg.length(p.world_pos - world_pos)
        if d < best_dist && d <= PORTAL_RADIUS {
            best_dist = d
            best_is_portal = true
            best_index = i
        }
    }

    for s, i in slingshots {
        if s.broken { continue }
        d := linalg.length(s.world_pos - world_pos)
        if d < best_dist && d <= SLINGSHOT_RADIUS {
            best_dist = d
            best_is_portal = false
            best_index = i
        }
    }

    return best_is_portal, best_index, best_dist
}

portal_color :: proc(digit: int) -> k2.Color {
    if digit >= 1 && digit <= 9 { return PORTAL_COLORS[digit-1] }
    return k2.WHITE
}

interactables_update :: proc(real_dt: f32) {
    if player.is_dead { inter_state.aiming = false; inter_state.spiraling = false; return }

    ps := &inter_state
    player_center := k2.Vec2{player.pos.x, player.pos.y - player.size.y/2}

    if k2.mouse_button_went_down(.Left) {
        ps.click_buffer = CLICK_BUFFER_TIME
    } else {
        ps.click_buffer -= real_dt
    }

    if !ps.spiraling {
        if ps.click_buffer > 0 {
            is_portal, index, dist := find_nearest_interactable(player_center)
            if index >= 0 {
                ps.aiming = true
                ps.is_portal = is_portal
                ps.target_index = index
                ps.click_buffer = 0
            }
        }

        if ps.aiming {
            target_pos: k2.Vec2
            if ps.is_portal {
                target_pos = portals[ps.target_index].world_pos
            } else {
                if slingshots[ps.target_index].broken { ps.aiming = false }
                else { target_pos = slingshots[ps.target_index].world_pos }
            }

            if ps.is_portal {
                if linalg.length(target_pos - player_center) > PORTAL_RADIUS * 1.2 { ps.aiming = false }
            } else {
                if linalg.length(target_pos - player_center) > SLINGSHOT_RADIUS * 1.2 { ps.aiming = false }
            }

            if k2.mouse_button_went_up(.Left) && ps.aiming {
                mouse_world  := k2.screen_to_world(k2.get_mouse_position(), camera)
                dir          := mouse_world - player_center
                dir_len      := linalg.length(dir)
                if dir_len < 0.001 { dir = {1, 0} } else { dir /= dir_len }

                if ps.is_portal {
                    dist := linalg.length(target_pos - player_center)
                    ps.spiraling    = true
                    ps.aiming       = false
                    ps.timer        = 0
                    ps.spiral_angle = math.atan2(player_center.y - target_pos.y, player_center.x - target_pos.x)
                    ps.start_dist   = max(dist, 8)
                    ps.target_pos   = target_pos
                    ps.exit_dir     = dir
                } else {
                    ps.aiming = false
                    player.vel = dir * SLINGSHOT_SPEED
                    player.lock_timer = 0.25

                    if slingshots[ps.target_index].breakable {
                        slingshots[ps.target_index].broken = true
                        spawn_particles(target_pos, 15, SLINGSHOT_COLOR_BREAK, 200, 0.4, 4)
                    } else {
                        spawn_particles(player_center, 30, k2.Color{255, 220, 80, 255}, 400, 0.6, 5)
                    }
                }
            } else if !k2.mouse_button_is_held(.Left) {
                ps.aiming = false
            }
        }
        return
    }

    ps.timer += real_dt / PORTAL_PULL_DURATION
    t    := clamp(ps.timer, 0, 1)
    ease := t * t * (3 - 2 * t)

    radius := ps.start_dist * (1.0 - ease)
    ps.spiral_angle += real_dt * PORTAL_SPIRAL_SPEED * (1.0 + ease)

    spiral_pos := ps.target_pos + k2.Vec2{math.cos(ps.spiral_angle), math.sin(ps.spiral_angle)} * radius
    player.pos = spiral_pos + {0, player.size.y/2}
    player.vel = {0, 0}

    col := k2.WHITE
    if ps.is_portal {
        col = portal_color(portals[ps.target_index].digit)
    } else {
        col = slingshots[ps.target_index].breakable ? SLINGSHOT_COLOR_BREAK : SLINGSHOT_COLOR_NORMAL
    }

    if int(ps.timer * 30) % 3 == 0 {
        trail := col; trail.a = 120
        spawn_particles(spiral_pos, 1, trail, 30, 0.6, 2)
    }

    if t >= 1.0 {
        exit_pos := ps.target_pos
        exit_col := col

        if ps.is_portal {
            partner := portals[ps.target_index].partner_index
            if partner >= 0 {
                exit_pos = portals[partner].world_pos
            }
        } else {
            if slingshots[ps.target_index].breakable {
                slingshots[ps.target_index].broken = true
                spawn_particles(exit_pos, 15, col, 200, 0.4, 4)
            }
        }

        player.pos = exit_pos + {0, player.size.y/2}
        player.vel = ps.exit_dir * PORTAL_EXIT_SPEED * {1, 1.3}

        spawn_particles(exit_pos, 30, exit_col, 420, 0.7, 5)
        spawn_particles(exit_pos, 12, k2.Color{255, 255, 255, 220}, 200, 0.45, 3)

        ps.spiraling = false
        player.lock_timer = 0.3
    }
}

interactables_draw :: proc() {
    t := f32(k2.get_time())
    player_center := k2.Vec2{player.pos.x, player.pos.y - player.size.y/2}
    ps := &inter_state

    if !ps.spiraling && ps.aiming {
        col: k2.Color
        target_pos: k2.Vec2
        if ps.is_portal {
            col = portal_color(portals[ps.target_index].digit)
            target_pos = portals[ps.target_index].world_pos
        } else {
            col = slingshots[ps.target_index].breakable ? SLINGSHOT_COLOR_BREAK : SLINGSHOT_COLOR_NORMAL
            target_pos = slingshots[ps.target_index].world_pos
        }

        pulse := 0.5 + 0.5 * math.sin(t * 3.0)

        max_radius := PORTAL_RADIUS if ps.is_portal else SLINGSHOT_RADIUS

        fill := col; fill.a = u8(10 + int(pulse * 8))
        k2.draw_circle(player_center, max_radius, fill, 36)

        ring := col; ring.a = u8(70 + int(pulse * 55))
        k2.draw_circle_outline(player_center, max_radius, 1.2, ring, 36)

        if ps.is_portal {
            mouse_world := k2.screen_to_world(k2.get_mouse_position(), camera)
            dir := mouse_world - player_center
            dist := linalg.length(dir)
            if dist > 0.001 {
                dir /= dist
            } else {
                dir = {1, 0}
            }

            end_pos := player_center + dir * min(dist, PORTAL_RADIUS)
            aim_line := col; aim_line.a = 220
            k2.draw_line(player_center, end_pos, 1.5, aim_line)
        } else {
            mouse_world := k2.screen_to_world(k2.get_mouse_position(), camera)
            dir := mouse_world - player_center
            dist := linalg.length(dir)
            if dist > 0.001 {
                dir /= dist
            } else {
                dir = {1, 0}
            }

            end_pos := player_center + dir * min(dist, SLINGSHOT_RADIUS)
            line := col; line.a = 220
            k2.draw_line(player_center, end_pos, 1.5, line)
            k2.draw_circle(end_pos, 4, k2.Color{255, 100, 50, 255})
        }
    }

    for p, i in portals {
        cx    := p.world_pos.x
        cy    := p.world_pos.y
        col   := portal_color(p.digit)
        dist  := linalg.length(p.world_pos - player_center)
        near  := dist <= PORTAL_RADIUS

        pulse: f32
        if near { pulse = 0.5 + 0.5 * math.sin(t * 4.0) }

        outer_r := TILE_SIZE * 0.60 + pulse * 3
        inner_r := TILE_SIZE * 0.30

        for arc in 0..<3 {
            ang := t * 0.7 + f32(arc) * (math.PI * 2.0 / 3.0)
            glow := col; glow.a = u8(55 + int(pulse * 45))
            k2.draw_circle({cx + math.cos(ang) * (outer_r * 0.65), cy + math.sin(ang) * (outer_r * 0.65)}, 2.0 + pulse * 0.5, glow, 8)
        }

        ring := col; ring.a = u8(145 + int(pulse * 75))
        k2.draw_circle_outline({cx, cy}, outer_r, 2.0, ring, 28)

        inner := col; inner.a = 170
        k2.draw_circle_outline({cx, cy}, inner_r, 1.2, inner, 16)

        core := col; core.a = u8(95 + int(pulse * 55))
        k2.draw_circle({cx, cy}, inner_r * 0.85, core, 18)
        k2.draw_circle({cx, cy}, inner_r * 0.3,  k2.Color{255, 255, 255, 200}, 12)

        if near {
            dot := col; dot.a = u8(180 + int(pulse * 60))
            k2.draw_circle({cx, cy - outer_r - 5}, 3, dot, 8)
        }

        is_partner := false
        exit_dir := k2.Vec2{}

        if ps.aiming && ps.is_portal && p.digit == portals[ps.target_index].digit && i != ps.target_index {
            mouse_world := k2.screen_to_world(k2.get_mouse_position(), camera)
            d := mouse_world - player_center
            dl := linalg.length(d)
            exit_dir = d/dl if dl > 0.001 else k2.Vec2{1, 0}
            is_partner = true
        } else if ps.spiraling && ps.is_portal && p.digit == portals[ps.target_index].digit && i != ps.target_index {
            exit_dir = ps.exit_dir
            is_partner = true
        }

        if is_partner {
            ae  := p.world_pos
            tip := ae + exit_dir * 90
            arr := col; arr.a = 230
            k2.draw_line(ae, tip, 2.0, arr)
            perp  := k2.Vec2{-exit_dir.y, exit_dir.x}
            k2.draw_line(tip, tip - exit_dir * 9 + perp * 9 * 0.42, 2.5, arr)
            k2.draw_line(tip, tip - exit_dir * 9 - perp * 9 * 0.42, 2.5, arr)
        }
    }

    for s, i in slingshots {
        if s.broken { continue }

        cx   := s.world_pos.x
        cy   := s.world_pos.y
        col  := s.breakable ? SLINGSHOT_COLOR_BREAK : SLINGSHOT_COLOR_NORMAL
        dist := linalg.length(s.world_pos - player_center)
        near := dist <= SLINGSHOT_RADIUS

        pulse: f32
        if near { pulse = 0.5 + 0.5 * math.sin(t * 4.0) }

        size := TILE_SIZE * 0.85 + pulse * 4
        half := size / 2

        rect_out := k2.Rect{cx - half, cy - half, size, size}

        outer := col; outer.a = u8(100 + int(pulse * 80))
        k2.draw_rect_outline(rect_out, 2.0, outer)

        inner := col; inner.a = 180
        rect_in := k2.Rect{cx - half*0.5, cy - half*0.5, size*0.5, size*0.5}
        k2.draw_rect_outline(rect_in, 1.5, inner)

        core := k2.Color{255, 255, 255, 200}
        rect_core := k2.Rect{cx - half*0.2, cy - half*0.2, size*0.2, size*0.2}
        k2.draw_rect(rect_core, core)
    }

    if ps.spiraling {
        col: k2.Color
        if ps.is_portal {
            col = portal_color(portals[ps.target_index].digit)
        } else {
            col = slingshots[ps.target_index].breakable ? SLINGSHOT_COLOR_BREAK : SLINGSHOT_COLOR_NORMAL
        }

        for ring in 0..<3 {
            phase  := math.mod(t * 1.8 + f32(ring) * 0.33, 1.0)
            r_size := TILE_SIZE * 0.5 * (1.0 - phase)
            rc     := col; rc.a = u8((1.0 - phase) * 120)

            if ps.is_portal {
                k2.draw_circle_outline(ps.target_pos, r_size, 1.2, rc, 20)
            } else {
                k2.draw_rect_outline(k2.Rect{ps.target_pos.x - r_size, ps.target_pos.y - r_size, r_size*2, r_size*2}, 1.2, rc)
            }
        }
    }
}
