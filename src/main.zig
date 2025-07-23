const std = @import("std");
const builtin = @import("builtin");

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

pub const PLAYER_CIRCLE: physics.Circle = .{ .radius = 0.12 };

pub fn main() void {
    Platform.init();
    Audio.init();
    Renderer.init();
    Assets.init();
    Levels.init();

    var game: Game = .init();

    var t = std.time.nanoTimestamp();
    while (!Platform.stop) {
        const new_t = std.time.nanoTimestamp();
        const dt = @as(f32, @floatFromInt(new_t - t)) / std.time.ns_per_s;
        t = new_t;

        Platform.get_events();
        Platform.get_mouse_pos();
        Platform.process_events();
        Input.update();

        game.update(dt);

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
    sensitivity: f32 = 1.0,

    active: bool = false,

    // make Z point up and X/Y to be a ground plane
    pub const ORIENTATION = math.Quat.from_rotation_axis(.X, .NEG_Z, .Y);

    const Self = @This();

    pub fn forward(self: *const Self) math.Vec3 {
        const rotation = math.Quat.from_axis_angle(.Z, self.yaw).mul(Camera.ORIENTATION).to_mat4();
        return rotation.mul_vec4(.Z).shrink();
    }

    pub fn move(self: *Camera, dt: f32) void {
        self.active = Input.is_pressed(.WHEEL);
        if (!self.active) return;
        self.velocity.x =
            -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.A)))) +
            1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.D))));
        self.velocity.y =
            -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.SPACE)))) +
            1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.LCTRL))));
        self.velocity.z =
            -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.S)))) +
            1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.W))));

        self.yaw -= Input.mouse_motion.x * self.sensitivity * dt;
        self.pitch -= Input.mouse_motion.y * self.sensitivity * dt;
        if (math.PI / 2.0 < self.pitch) {
            self.pitch = math.PI / 2.0;
        }
        if (self.pitch < -math.PI / 2.0) {
            self.pitch = -math.PI / 2.0;
        }

        const rotation = self.rotation_matrix();
        const velocity = self.velocity.mul_f32(self.speed * dt).extend(1.0);
        const delta = rotation.mul_vec4(velocity);
        self.position = self.position.add(delta.shrink());
    }

    pub fn transform(self: *const Self) math.Mat4 {
        return self.rotation_matrix().translate(self.position);
    }

    pub fn rotation_matrix(self: *const Self) math.Mat4 {
        const r_yaw = math.Quat.from_axis_angle(.Z, self.yaw);
        const r_pitch = math.Quat.from_axis_angle(.X, self.pitch);
        return r_yaw.mul(r_pitch).mul(Self.ORIENTATION).to_mat4();
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

fn free_camera_move(self: *Camera, dt: f32) void {
    self.active = Input.is_pressed(.WHEEL);
    if (!self.active) return;
    self.velocity.x =
        -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.A)))) +
        1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.D))));
    self.velocity.y =
        -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.SPACE)))) +
        1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.LCTRL))));
    self.velocity.z =
        -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.S)))) +
        1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.W))));

    self.yaw -= Input.mouse_motion.x * self.sensitivity * dt;
    self.pitch -= Input.mouse_motion.y * self.sensitivity * dt;
    if (math.PI / 2.0 < self.pitch) {
        self.pitch = math.PI / 2.0;
    }
    if (self.pitch < -math.PI / 2.0) {
        self.pitch = -math.PI / 2.0;
    }

    const rotation = self.rotation_matrix();
    const velocity = self.velocity.mul_f32(self.speed * dt).extend(1.0);
    const delta = rotation.mul_vec4(velocity);
    self.position = self.position.add(delta.shrink());
}

fn player_camera_move(self: *Camera, dt: f32) void {
    self.yaw -= Input.mouse_motion.x * self.sensitivity * dt;
    self.pitch -= Input.mouse_motion.y * self.sensitivity * dt;
    if (math.PI / 2.0 < self.pitch) {
        self.pitch = math.PI / 2.0;
    }
    if (self.pitch < -math.PI / 2.0) {
        self.pitch = -math.PI / 2.0;
    }

    const rotation = math.Quat.from_axis_angle(.Z, self.yaw).mul(Camera.ORIENTATION).to_mat4();
    const forward = rotation.mul_vec4(.Z).shrink();
    const right = rotation.mul_vec4(.X).shrink();

    const fa =
        -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.S)))) +
        1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.W))));
    const ra =
        -1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.A)))) +
        1.0 * @as(f32, @floatFromInt(@intFromBool(Input.is_pressed(.D))));
    self.acceleration = forward.mul_f32(fa).add(right.mul_f32(ra)).mul_f32(self.speed);

    self.acceleration = self.acceleration.sub(self.velocity.mul_f32(self.friction));
    self.position = self.acceleration.mul_f32(0.5 * dt * dt)
        .add(self.velocity.mul_f32(dt))
        .add(self.position);
    self.velocity = self.velocity.add(self.acceleration.mul_f32(dt));
}

const Game = struct {
    frame_arena: std.heap.ArenaAllocator = undefined,

    current_level_tag: Levels.Tag = .@"0-1",
    mode: Mode = .Edit,

    free_camera: Camera = .{},
    player_camera: Camera = .{},
    // Footsteps
    random_footstep: std.Random.Xoroshiro128 = .init(0),
    player_move_time: f32 = 0.0,
    player_last_footstep_position: math.Vec2 = .{},

    const Mode = enum {
        Game,
        Edit,
    };

    const Self = @This();

    pub fn init() Self {
        const frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

        const free_camera: Camera = .{
            .position = .{ .y = -5.0, .z = 5.0 },
        };
        const player_camera: Camera = .{
            .position = .{ .y = -2.0, .z = 1.0 },
            .friction = 12.0,
            .speed = 50.0,
        };

        return .{
            .frame_arena = frame_arena,
            .free_camera = free_camera,
            .player_camera = player_camera,
        };
    }

    fn play_footstep(self: *Self, dt: f32) void {
        const NUM_FOOTSTEPS =
            @intFromEnum(Assets.SoundtrackType.Footstep4) -
            @intFromEnum(Assets.SoundtrackType.Footstep0);

        const random = self.random_footstep.random();
        if (0.3 < self.player_camera.velocity.len_squared()) {
            self.player_move_time += dt;
            if (0.6 < self.player_move_time) {
                const footstep_sound: Assets.SoundtrackType =
                    @enumFromInt(
                        @intFromEnum(Assets.SoundtrackType.Footstep0) +
                            random.intRangeAtMost(u8, 0, NUM_FOOTSTEPS),
                    );
                Audio.play(footstep_sound);
                self.player_move_time = 0.0;
                self.player_last_footstep_position = self.player_camera.position.xy();
            }
        }
        if (2.0 < (self.player_camera.position.xy()
            .sub(self.player_last_footstep_position)).len_squared())
        {
            const footstep_sound: Assets.SoundtrackType =
                @enumFromInt(
                    @intFromEnum(Assets.SoundtrackType.Footstep0) +
                        random.intRangeAtMost(u8, 0, NUM_FOOTSTEPS),
                );
            Audio.play(footstep_sound);
            self.player_move_time = 0.0;
            self.player_last_footstep_position = self.player_camera.position.xy();
        }
    }

    pub fn update(self: *Self, dt: f32) void {
        _ = self.frame_arena.reset(.retain_capacity);
        Renderer.reset();

        if (Input.was_pressed(.@"1")) {
            self.mode = .Game;
            Platform.hide_mouse(true);
        }
        if (Input.was_pressed(.@"2")) {
            self.mode = .Edit;
            Platform.hide_mouse(false);
        }

        const current_level = Levels.levels.getPtr(self.current_level_tag);

        const camera_in_use = switch (self.mode) {
            .Game => blk: {
                Platform.reset_mouse();
                Animations.play(dt);

                player_camera_move(&self.player_camera, dt);
                self.play_footstep(dt);

                const camera_ray = self.player_camera.mouse_to_ray(.{});

                current_level.player_pick_up_object(&camera_ray);
                if (Input.was_pressed(.RMB))
                    current_level.player_put_down_object();

                current_level.player_move_object(&self.player_camera, dt);
                current_level.player_collide(&self.player_camera);
                current_level.player_in_the_door(&self.player_camera);

                current_level.cursor_animate(dt);

                break :blk &self.player_camera;
            },
            .Edit => blk: {
                free_camera_move(&self.free_camera, dt);

                const mouse_clip = Platform.mouse_clip();
                const camera_ray = self.free_camera.mouse_to_ray(mouse_clip);

                if (Input.was_pressed(.LMB))
                    current_level.select(&camera_ray);
                if (Input.was_pressed(.RMB)) {
                    current_level.selected_object = null;
                    current_level.selected_light = null;
                }

                break :blk &self.free_camera;
            },
        };

        current_level.draw(dt);
        Renderer.render(camera_in_use, &current_level.environment);

        {
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
                    cimgui.ImGuiTreeNodeFlags_DefaultOpen,
                )) {
                    _ = cimgui.igSeparatorText("Cameras");
                    cimgui.format("Player camera", &self.player_camera);
                    cimgui.format("Free camera", &self.free_camera);
                    _ = cimgui.igSeparatorText("Levels selection");
                    cimgui.format("Current level", &self.current_level_tag);

                    if (cimgui.igButton("Reload levels", .{})) {
                        Levels.init();
                    }
                }

                current_level.imgui_ui(self.frame_arena.allocator(), self.current_level_tag);
                Audio.imgui_ui();
                Input.imgui_ui();
            }
        }
    }
};
