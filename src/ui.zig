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
pub var mouse_sense_slider: Slider = .{
    .icon_position = .{
        .x = -0.43,
        .y = -0.333,
    },
    .icon = .{ .size = 0.15 },
    .slider_position = .{ .y = -0.2 },
    .slider = .{
        .size = 0.5,
        .radius = 0.017,
        .width = 0.5,
    },
    .knob_position = .{
        .x = 0.25,
        .y = -0.2,
    },
    .knob = .{
        .size = 0.5,
        .radius = KNOB_MIN_RADIUS,
        .width = 0.0,
    },
};
pub var volume_slider: Slider = .{
    .icon_position = .{
        .x = -0.43,
        .y = -0.633,
    },
    .icon = .{ .size = 0.15 },
    .slider_position = .{ .y = -0.5 },
    .slider = .{
        .size = 0.5,
        .radius = 0.017,
        .width = 0.5,
    },
    .knob_position = .{
        .x = 0.25,
        .y = -0.5,
    },
    .knob = .{
        .size = 0.5,
        .radius = KNOB_MIN_RADIUS,
        .width = 0.0,
    },
};

pub var cursor_position: math.Vec2 = .{};
pub var cursor: Shape = .{
    .size = 0.05,
    .radius = CURSOR_MIN_RADIUS,
    .width = 0.0,
};

pub const Slider = struct {
    icon_position: math.Vec2,
    icon: Texture,
    slider_position: math.Vec2,
    slider: Shape,
    knob_position: math.Vec2,
    knob: Shape,
    is_dragged: bool = false,

    fn interract(self: *Slider, mouse_clip: math.Vec2, dt: f32) void {
        const to_knob_len = self.knob_position.sub(mouse_clip).len();
        if (to_knob_len < self.knob.radius) {
            self.knob.radius = math.exp_decay(
                self.knob.radius,
                KNOB_MID_RADIUS,
                18.0,
                dt,
            );

            if (Input.was_pressed(.LMB)) {
                self.is_dragged = true;
            }
        }

        if (Input.was_released(.LMB)) {
            self.is_dragged = false;
        }

        if (self.is_dragged) {
            self.knob.radius = math.exp_decay(
                self.knob.radius,
                KNOB_MAX_RADIUS,
                18.0,
                dt,
            );

            self.knob_position.x = math.exp_decay(
                self.knob_position.x,
                mouse_clip.x,
                18.0,
                dt,
            );
            self.knob_position.x =
                @min(
                    @max(
                        self.knob_position.x,
                        -self.slider.width / 2.0,
                    ),
                    self.slider.width / 2.0,
                );
        } else {
            self.knob.radius = math.exp_decay(
                self.knob.radius,
                KNOB_MIN_RADIUS,
                18.0,
                dt,
            );
        }
    }

    fn value(self: *const Slider) f32 {
        return self.knob_position.x / self.slider.width + 0.5;
    }

    fn draw(self: *const Slider) void {
        Renderer.draw_ui(.{ .Shape = self.slider }, self.slider_position, blur_strength);
        Renderer.draw_ui(.{ .Shape = self.knob }, self.knob_position, blur_strength);
        Renderer.draw_ui(.{ .Texture = self.icon }, self.icon_position, blur_strength);
    }
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

const BLUR_CHANGE_DURATION = 0.3;
const BLUR_MAX = 1.0;
const BLUR_MIN = 0.0;
const CURSOR_MAX_RADIUS = 0.15;
const CURSOR_MIN_RADIUS = 0.0;
const KNOB_MAX_RADIUS = 0.06;
const KNOB_MID_RADIUS = 0.05;
const KNOB_MIN_RADIUS = 0.04;

pub fn init() void {
    mouse_sense_slider.icon.texture = Assests.gpu_textures.getPtr(.MouseIcon);
    volume_slider.icon.texture = Assests.gpu_textures.getPtr(.SpeakerIcon);
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
    mouse_sense_slider.is_dragged = false;
    volume_slider.is_dragged = false;
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

    mouse_sense_slider.interract(mouse_clip, dt);
    if (mouse_sense_slider.is_dragged)
        Input.mouse_sense = mouse_sense_slider.value();

    volume_slider.interract(mouse_clip, dt);
    if (volume_slider.is_dragged)
        Audio.global_volume = volume_slider.value();
}

pub fn draw() void {
    switch (state) {
        .Game => Renderer.draw_ui(.{ .Shape = cursor }, cursor_position, 1.0 - blur_strength),
        .Pause => {
            Renderer.draw_ui(.{ .Shape = cursor }, cursor_position, 1.0 - blur_strength);

            mouse_sense_slider.draw();
            volume_slider.draw();
        },
    }
}

pub fn imgui_ui() void {
    const T = struct {
        state: *State = &state,
        blur_strength: *f32 = &blur_strength,
        mouse_sense_slider: *Slider = &mouse_sense_slider,
        volume_slider: *Slider = &volume_slider,
        cursor_position: *math.Vec2 = &cursor_position,
        cursor: *Shape = &cursor,
    };
    var t: T = .{};

    var open: bool = true;
    if (cimgui.igCollapsingHeader_BoolPtr(
        "Ui",
        &open,
        0,
    )) {
        cimgui.format("Ui", &t);
    }
}
