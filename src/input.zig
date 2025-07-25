const std = @import("std");
const builtin = @import("builtin");

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
    NUMLOCKCLEAR = 83,
    KP_DIVIDE = 84,
    KP_MULTIPLY = 85,
    KP_MINUS = 86,
    KP_PLUS = 87,
    KP_ENTER = 88,
    KP_1 = 89,
    KP_2 = 90,
    KP_3 = 91,
    KP_4 = 92,
    KP_5 = 93,
    KP_6 = 94,
    KP_7 = 95,
    KP_8 = 96,
    KP_9 = 97,
    KP_0 = 98,
    KP_PERIOD = 99,
    NONUSBACKSLASH = 100,
    APPLICATION = 101,
    POWER = 102,
    KP_EQUALS = 103,
    F13 = 104,
    F14 = 105,
    F15 = 106,
    F16 = 107,
    F17 = 108,
    F18 = 109,
    F19 = 110,
    F20 = 111,
    F21 = 112,
    F22 = 113,
    F23 = 114,
    F24 = 115,
    EXECUTE = 116,
    HELP = 117,
    MENU = 118,
    SELECT = 119,
    STOP = 120,
    AGAIN = 121,
    UNDO = 122,
    CUT = 123,
    COPY = 124,
    PASTE = 125,
    FIND = 126,
    MUTE = 127,
    VOLUMEUP = 128,
    VOLUMEDOWN = 129,
    _dummy_1 = 130,
    _dummy_2 = 131,
    _dummy_3 = 132,
    KP_COMMA = 133,
    KP_EQUALSAS400 = 134,
    INTERNATIONAL1 = 135,
    INTERNATIONAL2 = 136,
    INTERNATIONAL3 = 137,
    INTERNATIONAL4 = 138,
    INTERNATIONAL5 = 139,
    INTERNATIONAL6 = 140,
    INTERNATIONAL7 = 141,
    INTERNATIONAL8 = 142,
    INTERNATIONAL9 = 143,
    LANG1 = 144,
    LANG2 = 145,
    LANG3 = 146,
    LANG4 = 147,
    LANG5 = 148,
    LANG6 = 149,
    LANG7 = 150,
    LANG8 = 151,
    LANG9 = 152,
    ALTERASE = 153,
    SYSREQ = 154,
    CANCEL = 155,
    CLEAR = 156,
    PRIOR = 157,
    RETURN2 = 158,
    SEPARATOR = 159,
    OUT = 160,
    OPER = 161,
    CLEARAGAIN = 162,
    CRSEL = 163,
    EXSEL = 164,
    _dummy_4 = 165,
    _dummy_5 = 166,
    _dummy_6 = 167,
    _dummy_7 = 168,
    _dummy_8 = 169,
    _dummy_9 = 170,
    _dummy_10 = 171,
    _dummy_11 = 172,
    _dummy_12 = 173,
    _dummy_13 = 174,
    _dummy_14 = 175,
    KP_00 = 176,
    KP_000 = 177,
    THOUSANDSSEPARATOR = 178,
    DECIMALSEPARATOR = 179,
    CURRENCYUNIT = 180,
    CURRENCYSUBUNIT = 181,
    KP_LEFTPAREN = 182,
    KP_RIGHTPAREN = 183,
    KP_LEFTBRACE = 184,
    KP_RIGHTBRACE = 185,
    KP_TAB = 186,
    KP_BACKSPACE = 187,
    KP_A = 188,
    KP_B = 189,
    KP_C = 190,
    KP_D = 191,
    KP_E = 192,
    KP_F = 193,
    KP_XOR = 194,
    KP_POWER = 195,
    KP_PERCENT = 196,
    KP_LESS = 197,
    KP_GREATER = 198,
    KP_AMPERSAND = 199,
    KP_DBLAMPERSAND = 200,
    KP_VERTICALBAR = 201,
    KP_DBLVERTICALBAR = 202,
    KP_COLON = 203,
    KP_HASH = 204,
    KP_SPACE = 205,
    KP_AT = 206,
    KP_EXCLAM = 207,
    KP_MEMSTORE = 208,
    KP_MEMRECALL = 209,
    KP_MEMCLEAR = 210,
    KP_MEMADD = 211,
    KP_MEMSUBTRACT = 212,
    KP_MEMMULTIPLY = 213,
    KP_MEMDIVIDE = 214,
    KP_PLUSMINUS = 215,
    KP_CLEAR = 216,
    KP_CLEARENTRY = 217,
    KP_BINARY = 218,
    KP_OCTAL = 219,
    KP_DECIMAL = 220,
    KP_HEXADECIMAL = 221,
    _dummy_15 = 222,
    _dummy_16 = 223,
    LCTRL = 224,
    LSHIFT = 225,
    LALT = 226,
    LGUI = 227,
    RCTRL = 228,
    RSHIFT = 229,
};

pub const KeyStates = std.EnumArray(Keys, KeyState);

var keys: KeyStates = .initFill(.{});
pub var mouse_motion: math.Vec2 = .{};
pub var mouse_sense: f32 = 1.0;

pub fn was_pressed(key: Keys) bool {
    if (Platform.imgui_wants_to_handle_events())
        return false
    else
        return keys.get(key).was_pressed;
}

pub fn was_released(key: Keys) bool {
    if (Platform.imgui_wants_to_handle_events())
        return false
    else
        return keys.get(key).was_released;
}

pub fn is_pressed(key: Keys) bool {
    if (Platform.imgui_wants_to_handle_events())
        return false
    else
        return keys.get(key).is_pressed;
}

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
                mouse_motion.x += e.motion.xrel;
                mouse_motion.y += e.motion.yrel;
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
    var open: bool = true;
    if (cimgui.igCollapsingHeader_BoolPtr(
        "Input",
        &open,
        0,
    )) {
        cimgui.format("Input", &keys);
    }
}
