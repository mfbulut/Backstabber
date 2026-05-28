#+build !js

package main

import "core:os"
import "core:mem"

import k2 "karl2d"

Save_Data :: struct {
    sfx_volume: f32,
    music_volume: f32,
    is_fullscreen: bool,
    is_speedruning: bool,
    level_best_times: [len(level_defs)]f32,
}

save_settings :: proc() {
    data: Save_Data
    data.sfx_volume = sfx_volume
    data.music_volume = music_volume
    data.is_fullscreen = is_fullscreen
    data.is_speedruning = is_speedruning
    data.level_best_times = level_best_times

    bytes := mem.byte_slice(&data, size_of(Save_Data))
    _ = os.write_entire_file("settings.dat", bytes)
}

load_settings :: proc() {
    bytes, err := os.read_entire_file_from_path("settings.dat", context.temp_allocator)
    if err != nil do return

    data := (^Save_Data)(raw_data(bytes))^
    sfx_volume = data.sfx_volume
    music_volume = data.music_volume
    is_fullscreen = data.is_fullscreen
    is_speedruning = data.is_speedruning
    level_best_times = data.level_best_times

    if is_fullscreen {
        k2.set_window_mode(.Borderless_Fullscreen)
    } else {
        k2.set_window_mode(.Windowed_Resizable)
    }

    k2.set_audio_stream_volume(music, music_volume * music_volume * music_volume)
}

editor_save_map :: proc() {
    data := mem.byte_slice(&editor_map, size_of(editor_map))
    _ = os.write_entire_file("custom_level.txt", data)
}

editor_load_map :: proc() -> bool {
    data, err := os.read_entire_file_from_path("custom_level.txt", context.temp_allocator)
    if err != nil do return false
    if len(data) != size_of(editor_map) do return false
    mem.copy(&editor_map, raw_data(data), size_of(editor_map))
    return true
}
