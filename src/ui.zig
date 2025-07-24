const gpu = @import("gpu.zig");
const math = @import("math.zig");
const cimgui = @import("bindings/cimgui.zig");

const Animations = @import("animations.zig");
const Platform = @import("platform.zig");
const Renderer = @import("renderer.zig");
const Assests = @import("assets.zig");
const Audio = @import("audio.zig");
const Input = @import("input.zig");

pub var state: State = .Game;
pub var blur_strength: f32 = 0.0;
pub var volume_icon_position: math.Vec2 = .{
    .x = -0.43,
    .y = -0.633,
};
pub var volume_icon: Texture = .{ .size = 0.15 };
pub var volume_slider_position: math.Vec2 = .{ .y = -0.5 };
pub var volume_slider: Shape = .{
    .size = 0.5,
    .radius = 0.017,
    .width = 0.5,
};
pub var volume_knob_position: math.Vec2 = .{
    .x = 0.25,
    .y = -0.5,
};
pub var volume_knob: Shape = .{
    .size = 0.5,
    .radius = KNOB_MIN_RADIUS,
    .width = 0.0,
};
pub var cursor_position: math.Vec2 = .{};
pub var cursor: Shape = .{
    .size = 0.05,
    .radius = CURSOR_MIN_RADIUS,
    .width = 0.0,
};

var knob_is_dragged: bool = false;

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

const BLUR_CHANGE_DURATION = 0.3;
const BLUR_MAX = 1.0;
const BLUR_MIN = 0.0;
const CURSOR_MAX_RADIUS = 0.15;
const CURSOR_MIN_RADIUS = 0.0;
const KNOB_MAX_RADIUS = 0.06;
const KNOB_MID_RADIUS = 0.05;
const KNOB_MIN_RADIUS = 0.04;

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

fn set_state_game(_: *anyopaque, _: *anyopaque) void {
    state = .Game;
}

pub fn state_game() void {
    Animations.add(
        .{
            .object = .{ .Float = &blur_strength },
            .action = .{ .move_f32 = .{
                .start = blur_strength,
                .end = BLUR_MIN,
            } },
            .duration = BLUR_CHANGE_DURATION,
            .callback = @ptrCast(&set_state_game),
        },
    );
}

pub fn state_pause() void {
    state = .Pause;
    Animations.add(
        .{
            .object = .{ .Float = &blur_strength },
            .action = .{ .move_f32 = .{
                .start = blur_strength,
                .end = BLUR_MAX,
            } },
            .duration = BLUR_CHANGE_DURATION,
        },
    );
}

pub fn animate_blur(dt: f32) void {
    if (state == .Game)
        blur_strength = math.exp_decay(
            blur_strength,
            BLUR_MIN,
            14.0,
            dt,
        )
    else
        blur_strength = math.exp_decay(
            blur_strength,
            BLUR_MAX,
            14.0,
            dt,
        );
}

pub fn interract(dt: f32) void {
    const mouse_clip = Platform.mouse_clip();

    const to_knob_len = volume_knob_position.sub(mouse_clip).len();
    if (to_knob_len < volume_knob.radius) {
        volume_knob.radius = math.exp_decay(
            volume_knob.radius,
            KNOB_MID_RADIUS,
            18.0,
            dt,
        );

        if (Input.was_pressed(.LMB)) {
            knob_is_dragged = true;
        }
    }

    if (Input.was_released(.LMB)) {
        knob_is_dragged = false;
    }

    if (knob_is_dragged) {
        volume_knob.radius = math.exp_decay(
            volume_knob.radius,
            KNOB_MAX_RADIUS,
            18.0,
            dt,
        );

        volume_knob_position.x = math.exp_decay(
            volume_knob_position.x,
            mouse_clip.x,
            18.0,
            dt,
        );
        volume_knob_position.x =
            @min(
                @max(
                    volume_knob_position.x,
                    -volume_slider.width / 2.0,
                ),
                volume_slider.width / 2.0,
            );

        const volume = volume_knob_position.x / volume_slider.width + 0.5;
        Audio.global_volume = volume;
    } else {
        volume_knob.radius = math.exp_decay(
            volume_knob.radius,
            KNOB_MIN_RADIUS,
            18.0,
            dt,
        );
    }
}

pub fn draw() void {
    switch (state) {
        .Game => Renderer.draw_ui(.{ .Shape = cursor }, cursor_position, 1.0 - blur_strength),
        .Pause => {
            Renderer.draw_ui(.{ .Shape = cursor }, cursor_position, 1.0 - blur_strength);
            Renderer.draw_ui(.{ .Shape = volume_slider }, volume_slider_position, blur_strength);
            Renderer.draw_ui(.{ .Shape = volume_knob }, volume_knob_position, blur_strength);
            Renderer.draw_ui(.{ .Texture = volume_icon }, volume_icon_position, blur_strength);
        },
    }
}

pub fn imgui_ui() void {
    const T = struct {
        state: *State = &state,
        blur_strength: *f32 = &blur_strength,
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
