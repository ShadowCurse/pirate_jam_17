const gpu = @import("gpu.zig");
const math = @import("math.zig");
const cimgui = @import("bindings/cimgui.zig");

const Renderer = @import("renderer.zig");
const Assests = @import("assets.zig");

pub var state: State = .Game;
pub var volume_icon_position: math.Vec2 = .{
    .x = -0.43,
    .y = -0.633,
};
pub var volume_icon: Texture = .{ .size = 0.15 };
pub var volume_slider_position: math.Vec2 = .{ .y = -0.5 };
pub var volume_slider: Shape = .{
    .size = 0.5,
    .radius = 0.02,
    .width = 0.5,
};
pub var volume_knob_position: math.Vec2 = .{ .y = -0.5 };
pub var volume_knob: Shape = .{
    .size = 0.5,
    .radius = 0.05,
    .width = 0.0,
};
pub var cursor_position: math.Vec2 = .{};
pub var cursor: Shape = .{
    .size = 0.05,
    .radius = 0.15,
    .width = 0.0,
};

pub const State = enum {
    Game,
    Pause,
};

pub const Shape = struct {
    size: f32,
    radius: f32,
    width: f32,
};

pub const Texture = struct {
    texture: *const gpu.Texture = undefined,
    size: f32,
};

const CURSOR_MAX_RADIUS = 0.15;
const CURSOR_MIN_RADIUS = 0.0;

pub fn init() void {
    volume_icon.texture = Assests.gpu_textures.getPtr(.SpeakerIcon);
}

pub fn animate_cursor(visible: bool, dt: f32) void {
    if (visible)
        cursor.radius = math.exp_decay(
            cursor.radius,
            CURSOR_MAX_RADIUS,
            18.0,
            dt,
        )
    else
        cursor.radius = math.exp_decay(
            cursor.radius,
            CURSOR_MIN_RADIUS,
            18.0,
            dt,
        );
}

pub fn draw() void {
    switch (state) {
        .Game => Renderer.draw_ui(.{ .Shape = cursor }, cursor_position),
        .Pause => {
            Renderer.draw_ui(.{ .Shape = volume_slider }, volume_slider_position);
            Renderer.draw_ui(.{ .Shape = volume_knob }, volume_knob_position);
            Renderer.draw_ui(.{ .Texture = volume_icon }, volume_icon_position);
        },
    }
}

pub fn imgui_ui() void {
    const T = struct {
        state: *State = &state,
        volume_icon_position: *math.Vec2 = &volume_icon_position,
        volume_icon: *Texture = &volume_icon,
        volume_slider_position: *math.Vec2 = &volume_slider_position,
        volume_slider: *Shape = &volume_slider,
        volume_knob_position: *math.Vec2 = &volume_knob_position,
        volume_knob: *Shape = &volume_knob,
        cursor_position: *math.Vec2 = &cursor_position,
        cursor: *Shape = &cursor,
    };
    var t: T = .{};
    cimgui.format("Ui", &t);
}
