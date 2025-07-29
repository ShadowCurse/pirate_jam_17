const std = @import("std");
const builtin = @import("builtin");

const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");
const cimgui = @import("bindings/cimgui.zig");
const math = @import("math.zig");
const Platform = @import("platform.zig");

var keys: KeyStates = .initFill(.{});
pub var mouse_motion: math.Vec2 = .{};
pub var mouse_sense: f32 = 1.0;

pub var gamepad_axis: GamepadAxisStates = .initFill(0.0);
var gamepad: ?*sdl.SDL_Gamepad = null;

pub const KeyState = packed struct(u8) {
    was_pressed: bool = false,
    was_released: bool = false,
    is_pressed: bool = false,
    _: u5 = 0,
};
pub const Key = enum {
    LMB,
    WHEEL,
    RMB,
    A,
    D,
    S,
    W,
    @"1",
    @"2",
    SPACE,
    LCTRL,
    GAMEPAD_A,
    GAMEPAD_START,

    pub fn to_key(scanecode: u32) ?Key {
        return switch (scanecode) {
            1 => .LMB,
            2 => .WHEEL,
            3 => .RMB,
            sdl.SDL_SCANCODE_A => .A,
            sdl.SDL_SCANCODE_D => .D,
            sdl.SDL_SCANCODE_S => .S,
            sdl.SDL_SCANCODE_W => .W,
            sdl.SDL_SCANCODE_1 => .@"1",
            sdl.SDL_SCANCODE_2 => .@"2",
            sdl.SDL_SCANCODE_SPACE => .SPACE,
            sdl.SDL_SCANCODE_LCTRL => .LCTRL,
            else => null,
        };
    }
    pub fn to_gamepad_key(button: u32) ?Key {
        return switch (button) {
            sdl.SDL_GAMEPAD_BUTTON_SOUTH => .GAMEPAD_A,
            sdl.SDL_GAMEPAD_BUTTON_START => .GAMEPAD_START,
            else => null,
        };
    }
};
pub const KeyStates = std.EnumArray(Key, KeyState);

pub const GamepadAxis = enum {
    LEFT_X,
    LEFT_Y,
    RIGHT_X,
    RIGHT_Y,

    pub fn to_axis(axis: u32) ?GamepadAxis {
        return switch (axis) {
            sdl.SDL_GAMEPAD_AXIS_LEFTX => .LEFT_X,
            sdl.SDL_GAMEPAD_AXIS_LEFTY => .LEFT_Y,
            sdl.SDL_GAMEPAD_AXIS_RIGHTX => .RIGHT_X,
            sdl.SDL_GAMEPAD_AXIS_RIGHTY => .RIGHT_Y,
            else => null,
        };
    }
};
pub const GamepadAxisStates = std.EnumArray(GamepadAxis, f32);

pub fn was_pressed(key: Key) bool {
    if (Platform.imgui_wants_to_handle_events())
        return false
    else
        return keys.get(key).was_pressed;
}

pub fn was_released(key: Key) bool {
    if (Platform.imgui_wants_to_handle_events())
        return false
    else
        return keys.get(key).was_released;
}

pub fn is_pressed(key: Key) bool {
    if (Platform.imgui_wants_to_handle_events())
        return false
    else
        return keys.get(key).is_pressed;
}

pub fn update() void {
    for (std.enums.values(Key)) |k| {
        const key = keys.getPtr(k);
        key.was_pressed = false;
        key.was_released = false;
    }
    mouse_motion = .{};
    for (Platform.sdl_events) |*e| {
        switch (e.type) {
            sdl.SDL_EVENT_KEY_DOWN => {
                if (Key.to_key(e.key.scancode)) |k| {
                    keys.getPtr(k).* = .{
                        .was_pressed = true,
                        .is_pressed = true,
                    };
                }
            },
            sdl.SDL_EVENT_KEY_UP => {
                if (Key.to_key(e.key.scancode)) |k| {
                    keys.getPtr(k).* = .{
                        .is_pressed = false,
                        .was_released = true,
                    };
                }
            },
            sdl.SDL_EVENT_MOUSE_MOTION => {
                mouse_motion.x += e.motion.xrel;
                mouse_motion.y += e.motion.yrel;
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                if (Key.to_key(e.button.button)) |k| {
                    keys.getPtr(k).* = .{
                        .was_pressed = true,
                        .is_pressed = true,
                    };
                }
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
                if (Key.to_key(e.button.button)) |k| {
                    keys.getPtr(k).* = .{
                        .is_pressed = false,
                        .was_released = true,
                    };
                }
            },
            sdl.SDL_EVENT_GAMEPAD_ADDED => {
                if (gamepad) |g|
                    sdl.SDL_CloseGamepad(g);
                gamepad = sdl.SDL_OpenGamepad(e.gdevice.which);
            },
            sdl.SDL_EVENT_GAMEPAD_AXIS_MOTION => {
                if (GamepadAxis.to_axis(e.gaxis.axis)) |a| {
                    const DEADZONE = 0.2;
                    const v: f32 = @floatFromInt(e.gaxis.value);
                    const vv = v / sdl.SDL_JOYSTICK_AXIS_MAX;
                    if (@abs(vv) < DEADZONE)
                        gamepad_axis.getPtr(a).* = 0.0
                    else
                        gamepad_axis.getPtr(a).* = vv;
                }
            },
            sdl.SDL_EVENT_GAMEPAD_BUTTON_DOWN => {
                if (Key.to_gamepad_key(e.gbutton.button)) |k| {
                    keys.getPtr(k).* = .{
                        .was_pressed = true,
                        .is_pressed = true,
                    };
                }
            },
            sdl.SDL_EVENT_GAMEPAD_BUTTON_UP => {
                if (Key.to_gamepad_key(e.gbutton.button)) |k| {
                    keys.getPtr(k).* = .{
                        .is_pressed = false,
                        .was_released = true,
                    };
                }
            },
            else => {},
        }
    }
}

pub fn imgui_ui() void {
    var open: bool = true;
    if (cimgui.igCollapsingHeader_BoolPtr(
        "Input",
        &open,
        0,
    )) {
        cimgui.format("Keys", &keys);
        cimgui.format("Mouse motion", &mouse_motion);
        cimgui.format("Gamepad axis", &gamepad_axis);
    }
}
