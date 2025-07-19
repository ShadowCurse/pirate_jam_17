const std = @import("std");
const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");
const cimgui = @import("bindings/cimgui.zig");
const math = @import("math.zig");
const Platform = @import("platform.zig");

pub const KeyState = packed struct(u8) {
    was_pressed: bool = false,
    was_released: bool = false,
    is_pressed: bool = false,
    _: u5 = 0,
};

pub const Keys = enum(u32) {
    UNKNOWN = 0,
    LMB = 1,
    WHEEL = 2,
    RMB = 3,
    A = 4,
    B = 5,
    C = 6,
    D = 7,
    E = 8,
    F = 9,
    G = 10,
    H = 11,
    I = 12,
    J = 13,
    K = 14,
    L = 15,
    M = 16,
    N = 17,
    O = 18,
    P = 19,
    Q = 20,
    R = 21,
    S = 22,
    T = 23,
    U = 24,
    V = 25,
    W = 26,
    X = 27,
    Y = 28,
    Z = 29,
    @"1" = 30,
    @"2" = 31,
    @"3" = 32,
    @"4" = 33,
    @"5" = 34,
    @"6" = 35,
    @"7" = 36,
    @"8" = 37,
    @"9" = 38,
    @"0" = 39,
    RETURN = 40,
    ESCAPE = 41,
    BACKSPACE = 42,
    TAB = 43,
    SPACE = 44,
    MINUS = 45,
    EQUALS = 46,
    LEFTBRACKET = 47,
    RIGHTBRACKET = 48,
    BACKSLASH = 49,
    NONUSHASH = 50,
    SEMICOLON = 51,
    APOSTROPHE = 52,
    GRAVE = 53,
    COMMA = 54,
    PERIOD = 55,
    SLASH = 56,
    CAPSLOCK = 57,
    F1 = 58,
    F2 = 59,
    F3 = 60,
    F4 = 61,
    F5 = 62,
    F6 = 63,
    F7 = 64,
    F8 = 65,
    F9 = 66,
    F10 = 67,
    F11 = 68,
    F12 = 69,
    PRINTSCREEN = 70,
    SCROLLLOCK = 71,
    PAUSE = 72,
    INSERT = 73,
    HOME = 74,
    PAGEUP = 75,
    DELETE = 76,
    END = 77,
    PAGEDOWN = 78,
    RIGHT = 79,
    LEFT = 80,
    DOWN = 81,
    UP = 82,
};

pub const KeyStates = std.EnumArray(Keys, KeyState);

pub var keys: KeyStates = .initFill(.{});
pub var mouse_motion: math.Vec2 = .{};

pub fn update() void {
    for (std.enums.values(Keys)) |k| {
        const key = keys.getPtr(k);
        key.was_pressed = false;
        key.was_released = false;
    }
    mouse_motion = .{};
    for (Platform.sdl_events) |*e| {
        switch (e.type) {
            sdl.SDL_EVENT_KEY_DOWN => {
                if (std.meta.intToEnum(Keys, e.key.scancode)) |k|
                    keys.getPtr(k).* = .{
                        .was_pressed = true,
                        .is_pressed = true,
                    }
                else |_| {}
            },
            sdl.SDL_EVENT_KEY_UP => {
                if (std.meta.intToEnum(Keys, e.key.scancode)) |k| {
                    keys.getPtr(k).* = .{
                        .is_pressed = false,
                        .was_released = true,
                    };
                } else |_| {}
            },
            sdl.SDL_EVENT_MOUSE_MOTION => {
                mouse_motion = .{ .x = e.motion.xrel, .y = e.motion.yrel };
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                if (std.meta.intToEnum(Keys, e.button.button)) |k| {
                    keys.getPtr(k).* = .{
                        .was_pressed = true,
                        .is_pressed = true,
                    };
                } else |_| {}
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
                if (std.meta.intToEnum(Keys, e.button.button)) |k|
                    keys.getPtr(k).* = .{
                        .is_pressed = false,
                        .was_released = true,
                    }
                else |_| {}
            },
            else => {},
        }
    }
}

pub fn imgui_ui() void {
    cimgui.format("Input", &keys);
}
