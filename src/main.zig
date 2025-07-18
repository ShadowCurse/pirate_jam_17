const std = @import("std");
const builtin = @import("builtin");

const gl = @import("bindings/gl.zig");
const sdl = @import("bindings/sdl.zig");
const cimgui = @import("bindings/cimgui.zig");

const log = @import("log.zig");
const gpu = @import("gpu.zig");
const mesh = @import("mesh.zig");
const math = @import("math.zig");

const Platform = @import("platform.zig");
const Renderer = @import("renderer.zig");

pub const log_options = log.Options{
    .level = .Info,
    .colors = builtin.target.os.tag != .emscripten,
};

pub fn main() void {
    Platform.init();
    Renderer.init();

    var game: Game = .init();

    var t = std.time.nanoTimestamp();
    while (!Platform.stop) {
        const new_t = std.time.nanoTimestamp();
        const dt = @as(f32, @floatFromInt(new_t - t)) / std.time.ns_per_s;
        t = new_t;

        Platform.get_events();
        Platform.get_mouse_pos();
        Platform.process_events();

        game.update(dt);

        Platform.present();
    }
}

pub const Camera = struct {
    position: math.Vec3 = .{},
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,

    fovy: f32 = math.PI / 2.0,
    near: f32 = 0.1,
    far: f32 = 10000.0,

    velocity: math.Vec3 = .{},
    speed: f32 = 5.0,
    sensitivity: f32 = 1.0,

    const ORIENTATION = math.Quat.from_rotation_axis(.X, .NEG_Z, .Y);
    const Self = @This();

    fn process_events(self: *Camera, dt: f32) void {
        for (Platform.sdl_events) |*e| {
            switch (e.type) {
                sdl.SDL_EVENT_KEY_DOWN => {
                    switch (e.key.scancode) {
                        sdl.SDL_SCANCODE_A => self.velocity.x = -1.0,
                        sdl.SDL_SCANCODE_D => self.velocity.x = 1.0,
                        sdl.SDL_SCANCODE_W => self.velocity.z = 1.0,
                        sdl.SDL_SCANCODE_S => self.velocity.z = -1.0,
                        sdl.SDL_SCANCODE_LCTRL => self.velocity.y = 1.0,
                        sdl.SDL_SCANCODE_SPACE => self.velocity.y = -1.0,
                        else => {},
                    }
                },
                sdl.SDL_EVENT_KEY_UP => {
                    switch (e.key.scancode) {
                        sdl.SDL_SCANCODE_A => self.velocity.x = 0.0,
                        sdl.SDL_SCANCODE_D => self.velocity.x = 0.0,
                        sdl.SDL_SCANCODE_W => self.velocity.z = 0.0,
                        sdl.SDL_SCANCODE_S => self.velocity.z = 0.0,
                        sdl.SDL_SCANCODE_LCTRL => self.velocity.y = 0.0,
                        sdl.SDL_SCANCODE_SPACE => self.velocity.y = 0.0,
                        else => {},
                    }
                },
                sdl.SDL_EVENT_MOUSE_MOTION => {
                    self.yaw -= e.motion.xrel * self.sensitivity * dt;
                    self.pitch -= e.motion.yrel * self.sensitivity * dt;
                    if (math.PI / 2.0 < self.pitch) {
                        self.pitch = math.PI / 2.0;
                    }
                    if (self.pitch < -math.PI / 2.0) {
                        self.pitch = -math.PI / 2.0;
                    }
                },
                else => {},
            }
        }
    }

    pub fn move(self: *Self, dt: f32) void {
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
};

const Game = struct {
    free_camera: Camera = .{},
    cube_mesh: gpu.Mesh = undefined,
    environment: Renderer.Environment = undefined,

    const Self = @This();

    pub fn init() Self {
        const camera: Camera = .{
            .position = .{ .y = -5.0, .z = 5.0 },
        };
        const cube_mesh = gpu.Mesh.from_mesh(&mesh.Cube);
        const environment: Renderer.Environment = .{
            .lights_position = .{
                .{ .x = 1.0, .y = 1.0, .z = 1.0 },
                .{ .x = -1.0, .y = 1.0, .z = 1.0 },
                .{ .x = 1.0, .y = -1.0, .z = 1.0 },
                .{ .x = -1.0, .y = -1.0, .z = 1.0 },
            },
            .lights_color = .{
                .{ .r = 1.0 },
                .{ .g = 1.0 },
                .{ .b = 1.0 },
                .{ .r = 1.0, .g = 1.0, .b = 1.0 },
            },
            .direct_light_direction = .{ .x = 1.0, .y = 1.0, .z = -2.0 },
            .direct_light_color = .{ .r = 1.0, .g = 1.0, .b = 1.0 },
        };

        return .{
            .free_camera = camera,
            .cube_mesh = cube_mesh,
            .environment = environment,
        };
    }

    pub fn update(self: *Self, dt: f32) void {
        self.free_camera.process_events(dt);
        self.free_camera.move(dt);

        Renderer.reset();
        Renderer.draw_mesh(
            &self.cube_mesh,
            .IDENDITY,
            .{ .albedo = .RED, .metallic = 0.5, .roughness = 0.5 },
        );
        Renderer.render(&self.free_camera, &self.environment);

        {
            cimgui.prepare_frame();
            defer cimgui.render_frame();

            var a: bool = true;
            _ = cimgui.igShowDemoWindow(&a);

            cimgui.format("Free camera", &self.free_camera);
        }
    }
};
