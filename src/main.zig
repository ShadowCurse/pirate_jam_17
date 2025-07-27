const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");

const Allocator = std.mem.Allocator;

const gl = @import("bindings/gl.zig");
const cimgui = @import("bindings/cimgui.zig");

const log = @import("log.zig");
const gpu = @import("gpu.zig");
const mesh = @import("mesh.zig");
const math = @import("math.zig");
const physics = @import("physics.zig");

const Animations = @import("animations.zig");
const Platform = @import("platform.zig");
const Renderer = @import("renderer.zig");
const Assets = @import("assets.zig");
const Levels = @import("levels.zig");
const Input = @import("input.zig");
const Audio = @import("audio.zig");
const Ui = @import("ui.zig");

pub const log_options = log.Options{
    .level = .Info,
    .colors = builtin.target.os.tag != .emscripten,
};

pub const os = if (builtin.os.tag != .emscripten) std.os else struct {
    pub const heap = struct {
        pub const page_allocator = std.heap.c_allocator;
    };
};

/// For some reason emsdk does not have it, so raw dog it.
export fn _emscripten_memcpy_js(dest: [*]u8, src: [*]u8, len: usize) void {
    var d: []u8 = undefined;
    d.ptr = dest;
    d.len = len;
    var s: []u8 = undefined;
    s.ptr = src;
    s.len = len;
    @memcpy(d, s);
}

pub const PLAYER_RADIUS = 0.12;

pub fn main() void {
    Platform.init();

    if (!options.no_sound)
        Audio.init();

    Renderer.init();
    Assets.init();
    Levels.init();
    Ui.init();

    Audio.play(.Background, null);

    init();

    var t = std.time.nanoTimestamp();
    while (!Platform.stop) {
        const new_t = std.time.nanoTimestamp();
        const dt = @as(f32, @floatFromInt(new_t - t)) / std.time.ns_per_s;
        t = new_t;

        Platform.get_events();
        Platform.get_mouse_pos();
        Platform.process_events();
        Input.update();

        update(dt);

        Platform.present();
    }
}

pub const Camera = struct {
    position: math.Vec3 = .{},
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,

    fovy: f32 = math.PI / 2.0,
    near: f32 = 0.01,
    far: f32 = 10000.0,

    velocity: math.Vec3 = .{},
    acceleration: math.Vec3 = .{},
    friction: f32 = 0.1,
    speed: f32 = 5.0,

    active: bool = false,

    // make Z point up and X/Y to be a ground plane
    pub const ORIENTATION = math.Quat.from_rotation_axis(.X, .NEG_Z, .Y);

    const Self = @This();

    pub fn forward(self: *const Self) math.Vec3 {
        return self.rotation().rotate_vec3(.Z);
    }

    pub fn forward_xy(self: *const Self) math.Vec3 {
        const r_yaw = math.Quat.from_axis_angle(.Z, self.yaw);
        return r_yaw.mul(Self.ORIENTATION).rotate_vec3(.Z);
    }

    pub fn up(self: *const Self) math.Vec3 {
        return self.rotation().rotate_vec3(.NEG_Y);
    }

    pub fn transform(self: *const Self) math.Mat4 {
        return self.rotation_matrix().translate(self.position);
    }

    pub fn rotation(self: *const Self) math.Quat {
        const r_yaw = math.Quat.from_axis_angle(.Z, self.yaw);
        const r_pitch = math.Quat.from_axis_angle(.X, self.pitch);
        return r_yaw.mul(r_pitch).mul(Self.ORIENTATION);
    }

    pub fn rotation_matrix(self: *const Self) math.Mat4 {
        return self.rotation().to_mat4();
    }

    pub fn perspective(self: *const Self) math.Mat4 {
        var m = math.Mat4.perspective(
            self.fovy,
            @as(f32, @floatFromInt(Platform.WINDOW_WIDTH)) /
                @as(f32, @floatFromInt(Platform.WINDOW_HEIGHT)),
            self.near,
            self.far,
        );
        // flip Y for opengl
        m.j.y *= -1.0;
        return m;
    }

    pub fn mouse_to_ray(self: *const Self, mouse_pos: math.Vec2) math.Ray {
        const world_near = self.transform()
            .mul(self.perspective().inverse())
            .mul_vec4(.{ .x = mouse_pos.x, .y = mouse_pos.y, .z = 1.0, .w = 1.0 });
        const world_near_world =
            world_near.shrink().div_f32(world_near.w);
        const f = world_near_world.sub(self.position).normalize();
        return .{
            .origin = self.position,
            .direction = f,
        };
    }
};

fn free_camera_move(camera: *Camera, dt: f32) void {
    camera.active = Input.is_pressed(.WHEEL);
    if (!camera.active) return;
    camera.velocity.x =
        -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.A)))) +
        1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.D))));
    camera.velocity.y =
        -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.SPACE)))) +
        1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.LCTRL))));
    camera.velocity.z =
        -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.S)))) +
        1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.W))));

    camera.yaw -= Input.mouse_motion.x * Input.mouse_sense * dt;
    camera.pitch -= Input.mouse_motion.y * Input.mouse_sense * dt;
    if (math.PI / 2.0 < camera.pitch) {
        camera.pitch = math.PI / 2.0;
    }
    if (camera.pitch < -math.PI / 2.0) {
        camera.pitch = -math.PI / 2.0;
    }

    const rotation = camera.rotation_matrix();
    const velocity = camera.velocity.mul_f32(camera.speed * dt).extend(1.0);
    const delta = rotation.mul_vec4(velocity);
    camera.position = camera.position.add(delta.shrink());
}

fn player_camera_move(camera: *Camera, dt: f32) void {
    camera.yaw -= Input.mouse_motion.x * Input.mouse_sense * dt;
    if (math.PI < camera.yaw) {
        camera.yaw -= math.PI * 2.0;
    }
    if (camera.yaw < -math.PI) {
        camera.yaw += math.PI * 2.0;
    }

    camera.pitch -= Input.mouse_motion.y * Input.mouse_sense * dt;
    if (math.PI / 2.0 < camera.pitch) {
        camera.pitch = math.PI / 2.0;
    }
    if (camera.pitch < -math.PI / 2.0) {
        camera.pitch = -math.PI / 2.0;
    }

    const rotation = math.Quat.from_axis_angle(.Z, camera.yaw).mul(Camera.ORIENTATION).to_mat4();
    const forward = rotation.mul_vec4(.Z).shrink();
    const right = rotation.mul_vec4(.X).shrink();

    const fa =
        -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.S)))) +
        1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.W))));
    const ra =
        -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.A)))) +
        1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.D))));
    camera.acceleration = forward.mul_f32(fa).add(right.mul_f32(ra));
    if (camera.acceleration.len_squared() != 0.0)
        camera.acceleration = camera.acceleration.normalize().mul_f32(camera.speed);

    camera.acceleration = camera.acceleration.sub(camera.velocity.mul_f32(camera.friction));
    camera.position = camera.acceleration.mul_f32(0.5 * dt * dt)
        .add(camera.velocity.mul_f32(dt))
        .add(camera.position);
    camera.velocity = camera.velocity.add(camera.acceleration.mul_f32(dt));
}

pub var frame_arena: std.heap.ArenaAllocator = undefined;

pub var current_level_tag: Levels.Tag = .@"0-1";
pub var player_level_start_offset: ?math.Vec3 = null;
pub var mode: Mode = .Edit;
pub var pause: bool = false;

pub var free_camera: Camera = .{};
pub var player_camera: Camera = .{};

// Footsteps
pub var random_footstep: std.Random.Xoroshiro128 = .init(0);
pub var player_move_time: f32 = 0.0;
pub var player_last_footstep_position: math.Vec2 = .{};

const Mode = enum {
    Game,
    Edit,
};

pub fn init() void {
    frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    free_camera = .{
        .position = .{ .y = -5.0, .z = 5.0 },
    };
    player_camera = .{
        .position = .{ .y = -1.0, .z = 1.0 },
        .friction = 12.0,
        .speed = 50.0,
    };
}

fn play_footstep(dt: f32) void {
    const NUM_FOOTSTEPS =
        @intFromEnum(Assets.SoundtrackType.Footstep4) -
        @intFromEnum(Assets.SoundtrackType.Footstep0);

    const random = random_footstep.random();
    if (0.3 < player_camera.velocity.len_squared()) {
        player_move_time += dt;
        if (0.6 < player_move_time) {
            const footstep_sound: Assets.SoundtrackType =
                @enumFromInt(
                    @intFromEnum(Assets.SoundtrackType.Footstep0) +
                        random.intRangeAtMost(u8, 0, NUM_FOOTSTEPS),
                );
            Audio.play(footstep_sound, null);
            player_move_time = 0.0;
            player_last_footstep_position = player_camera.position.xy();
        }
    }
    if (2.0 < (player_camera.position.xy()
        .sub(player_last_footstep_position)).len_squared())
    {
        const footstep_sound: Assets.SoundtrackType =
            @enumFromInt(
                @intFromEnum(Assets.SoundtrackType.Footstep0) +
                    random.intRangeAtMost(u8, 0, NUM_FOOTSTEPS),
            );
        Audio.play(footstep_sound, null);
        player_move_time = 0.0;
        player_last_footstep_position = player_camera.position.xy();
    }
}

pub fn current_camera() *const Camera {
    switch (mode) {
        .Game => {
            return &player_camera;
        },
        .Edit => {
            return &free_camera;
        },
    }
}

pub fn move_to_next_level() void {
    var current_level = Levels.levels.getPtr(current_level_tag);
    player_level_start_offset = current_level.player_offset_in_exit_door(&player_camera);
    current_level_tag = if (current_level.correct)
        current_level_tag.next()
    else
        current_level_tag.prev();
    current_level = Levels.levels.getPtr(current_level_tag);
    current_level.reset();
}

pub fn update(dt: f32) void {
    _ = frame_arena.reset(.retain_capacity);
    Renderer.reset();

    if (Input.was_pressed(.@"1")) {
        mode = .Game;
        Platform.hide_mouse(true);
    }
    if (Input.was_pressed(.@"2")) {
        mode = .Edit;
        Platform.hide_mouse(false);
    }

    const current_level = Levels.levels.getPtr(current_level_tag);

    const camera_in_use = switch (mode) {
        .Game => blk: {
            if (!current_level.started) {
                current_level.start_level(&player_camera, player_level_start_offset);
            }

            Animations.play(dt);

            if (Input.was_pressed(.SPACE)) {
                pause = !pause;
                Platform.hide_mouse(!pause);
                if (pause)
                    Ui.state_pause()
                else
                    Ui.state_game();
            }

            if (pause) {
                Ui.interract(dt);
            } else if (current_level.started) {
                player_camera_move(&player_camera, dt);
                play_footstep(dt);

                const camera_ray = player_camera.mouse_to_ray(.{});

                if (current_level.holding_object == null)
                    current_level.player_look_at_object(&camera_ray, Input.was_pressed(.LMB))
                else if (Input.was_pressed(.LMB))
                    current_level.player_put_down_object();

                current_level.player_move_object(&player_camera, dt);
                current_level.player_collide(&player_camera);
                current_level.player_in_the_door(&player_camera);

                Ui.animate_cursor(current_level.looking_at_pickable_object, dt);
                if (current_level.finished)
                    move_to_next_level();
            }
            Ui.animate_blur(dt);

            break :blk &player_camera;
        },
        .Edit => blk: {
            free_camera_move(&free_camera, dt);

            const mouse_clip = Platform.mouse_clip();
            const camera_ray = free_camera.mouse_to_ray(mouse_clip);

            if (Input.was_pressed(.LMB))
                current_level.select(&camera_ray);
            if (Input.was_pressed(.RMB)) {
                current_level.selected_object = null;
                current_level.selected_light = null;
            }

            break :blk &free_camera;
        },
    };

    current_level.draw(dt);
    Ui.draw();
    Renderer.render(camera_in_use, &current_level.environment);

    if (mode == .Edit) {
        cimgui.prepare_frame();
        defer cimgui.render_frame();

        // _ = cimgui.igShowDemoWindow(&a);

        {
            var open: bool = true;
            _ = cimgui.igBegin("Options", &open, 0);
            defer cimgui.igEnd();

            if (cimgui.igCollapsingHeader_BoolPtr(
                "General",
                &open,
                0,
            )) {
                _ = cimgui.igSeparatorText("Cameras");
                cimgui.format("Player camera", &player_camera);
                cimgui.format("Free camera", &free_camera);
                _ = cimgui.igSeparatorText("Levels selection");
                cimgui.format("Current level", &current_level_tag);

                if (cimgui.igButton("Restart level", .{})) {
                    Levels.levels.getPtr(current_level_tag).started = false;
                }

                if (cimgui.igButton("Reload levels", .{})) {
                    Levels.init();
                }
            }

            current_level.imgui_ui(frame_arena.allocator(), current_level_tag);
            Renderer.imgui_ui();
            Ui.imgui_ui();
            Audio.imgui_ui();
            Input.imgui_ui();
        }
    }
}
