const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const gl = @import("bindings/gl.zig");
const sdl = @import("bindings/sdl.zig");
const cimgui = @import("bindings/cimgui.zig");

const log = @import("log.zig");
const gpu = @import("gpu.zig");
const mesh = @import("mesh.zig");
const math = @import("math.zig");

const Platform = @import("platform.zig");
const Renderer = @import("renderer.zig");
const Assets = @import("assets.zig");

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

pub fn main() void {
    Platform.init();
    Renderer.init();
    Assets.init();

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

    active: bool = false,

    // make Z point up and X/Y to be a ground plane
    pub const ORIENTATION = math.Quat.from_rotation_axis(.X, .NEG_Z, .Y);
    const Self = @This();

    fn process_events(self: *Camera, dt: f32) void {
        for (Platform.sdl_events) |*e| {
            switch (e.type) {
                sdl.SDL_EVENT_KEY_DOWN => {
                    if (!self.active) continue;

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
                    if (!self.active) continue;

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
                    if (!self.active) continue;

                    self.yaw -= e.motion.xrel * self.sensitivity * dt;
                    self.pitch -= e.motion.yrel * self.sensitivity * dt;
                    if (math.PI / 2.0 < self.pitch) {
                        self.pitch = math.PI / 2.0;
                    }
                    if (self.pitch < -math.PI / 2.0) {
                        self.pitch = -math.PI / 2.0;
                    }
                },
                sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    switch (e.button.button) {
                        // LMB
                        1 => self.active = true,
                        else => {},
                    }
                },
                sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
                    switch (e.button.button) {
                        // LMB
                        1 => self.active = false,
                        else => {},
                    }
                },
                else => {},
            }
        }
    }

    pub fn move(self: *Self, dt: f32) void {
        if (!self.active) return;

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

const Level = struct {
    arena: std.heap.ArenaAllocator = undefined,
    save_path: [128:0]u8 = .{0} ** 128,
    objects: std.ArrayListUnmanaged(Object) = .{},
    environment: Renderer.Environment = .{},

    const Object = struct {
        model: Assets.ModelType,
        position: math.Vec3 = .{},
        rotation_x: f32 = 0.0,
        rotation_y: f32 = 0.0,
        rotation_z: f32 = 0.0,
        scale: math.Vec3 = .ONE,

        fn transform(self: *const Object) math.Mat4 {
            const rotation = math.Quat.from_axis_angle(.X, self.rotation_x)
                .mul(math.Quat.from_axis_angle(.Y, self.rotation_y))
                .mul(math.Quat.from_axis_angle(.Z, self.rotation_z))
                .to_mat4();
            return math.Mat4.IDENDITY.translate(self.position).scale(self.scale).mul(rotation);
        }
    };

    const LEVEL_DIR = "resources/levels";
    const Self = @This();

    pub fn empty() Self {
        const arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        return .{
            .arena = arena,
        };
    }

    pub fn draw(self: *const Self) void {
        for (self.objects.items) |*object|
            Renderer.draw_mesh(
                Assets.gpu_meshes.getPtr(object.model),
                object.transform(),
                Assets.materials.get(object.model),
            );
    }

    const SaveState = struct {
        objects: []const Object,
        environment: *const Renderer.Environment,
    };

    pub fn save(self: *const Self, scratch_alloc: Allocator, path: []const u8) !void {
        const actual_path = try std.fmt.allocPrint(
            scratch_alloc,
            "{s}/{s}",
            .{ Self.LEVEL_DIR, path },
        );
        var file = try std.fs.cwd().createFile(actual_path, .{});
        defer file.close();

        const options = std.json.StringifyOptions{
            .whitespace = .indent_4,
        };
        const save_state = SaveState{
            .objects = self.objects.items,
            .environment = &self.environment,
        };
        try std.json.stringify(save_state, options, file.writer());
    }

    pub fn load(
        self: *Self,
        scratch_alloc: Allocator,
        path: []const u8,
    ) !void {
        _ = self.arena.reset(.retain_capacity);

        const actual_path = try std.fmt.allocPrint(
            scratch_alloc,
            "{s}/{s}",
            .{ Self.LEVEL_DIR, path },
        );
        const file_mem = try Platform.FileMem.init(actual_path);
        defer file_mem.deinit();

        const ss = try std.json.parseFromSlice(
            SaveState,
            scratch_alloc,
            file_mem.mem,
            .{},
        );

        const save_state = &ss.value;
        const arena_alloc = self.arena.allocator();
        self.objects = .fromOwnedSlice(try arena_alloc.dupe(Object, save_state.objects));
        self.environment = save_state.environment.*;
    }

    pub fn imgui_ui(
        self: *Self,
        scratch_alloc: Allocator,
    ) void {
        var cimgui_id: i32 = 128;
        var open: bool = true;
        if (cimgui.igCollapsingHeader_BoolPtr(
            "Level",
            &open,
            cimgui.ImGuiTreeNodeFlags_DefaultOpen,
        )) {
            _ = cimgui.igSeparatorText("Save/Load");
            _ = cimgui.igInputText(
                "File path",
                &self.save_path,
                self.save_path.len,
                0,
                null,
                null,
            );
            const path = std.mem.sliceTo(&self.save_path, 0);
            if (cimgui.igButton("Save level", .{})) {
                self.save(scratch_alloc, path) catch |e|
                    log.err(@src(), "Cannot save level to {s} due to {}", .{ path, e });
            }
            if (cimgui.igButton("Load level", .{})) {
                self.load(scratch_alloc, path) catch |e|
                    log.err(@src(), "Cannot load level from {s} due to {}", .{ path, e });
            }
            _ = cimgui.igSeparatorText("Add");
            for (std.enums.values(Assets.ModelType)) |v| {
                const n = std.fmt.allocPrintZ(scratch_alloc, "Add {}", .{v}) catch unreachable;
                if (cimgui.igButton(n, .{})) {
                    self.objects.append(self.arena.allocator(), .{ .model = v }) catch unreachable;
                }
            }
            if (cimgui.igCollapsingHeader_BoolPtr(
                "Objects",
                &open,
                cimgui.ImGuiTreeNodeFlags_DefaultOpen,
            )) {
                for (self.objects.items) |*object| {
                    cimgui.igPushID_Int(cimgui_id);
                    cimgui_id += 1;
                    defer cimgui.igPopID();

                    cimgui.format(null, object);
                }
            }
        }
    }
};

const Game = struct {
    frame_arena: std.heap.ArenaAllocator = undefined,

    level: Level = undefined,

    free_camera: Camera = .{},

    const Self = @This();

    pub fn init() Self {
        const frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

        var level: Level = .empty();
        const DEFAULT_LEVEL = "test.json";
        @memcpy(level.save_path[0..DEFAULT_LEVEL.len], DEFAULT_LEVEL);

        const camera: Camera = .{
            .position = .{ .y = -5.0, .z = 5.0 },
        };

        return .{
            .frame_arena = frame_arena,
            .level = level,
            .free_camera = camera,
        };
    }

    pub fn update(self: *Self, dt: f32) void {
        _ = self.frame_arena.reset(.retain_capacity);

        if (Platform.imgui_wants_to_handle_events())
            self.free_camera.active = false
        else
            self.free_camera.process_events(dt);

        self.free_camera.move(dt);

        Renderer.reset();
        self.level.draw();
        Renderer.render(&self.free_camera, &self.level.environment);

        {
            cimgui.prepare_frame();
            defer cimgui.render_frame();

            var a: bool = true;
            _ = cimgui.igShowDemoWindow(&a);

            cimgui.format("Free camera", &self.free_camera);
            cimgui.format("Environment", &self.level.environment);
            self.level.imgui_ui(self.frame_arena.allocator());
        }
    }
};
