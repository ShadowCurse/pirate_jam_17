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
const Input = @import("input.zig");

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
    near: f32 = 0.1,
    far: f32 = 10000.0,

    velocity: math.Vec3 = .{},
    speed: f32 = 5.0,
    sensitivity: f32 = 1.0,

    active: bool = false,

    // make Z point up and X/Y to be a ground plane
    pub const ORIENTATION = math.Quat.from_rotation_axis(.X, .NEG_Z, .Y);
    const Self = @This();

    fn move(self: *Camera, dt: f32) void {
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
        const forward = world_near_world.sub(self.position).normalize();
        return .{
            .origin = self.position,
            .direction = forward,
        };
    }
};

const Level = struct {
    arena: std.heap.ArenaAllocator = undefined,
    save_path: [128:0]u8 = .{0} ** 128,

    selected_object: ?u32 = null,
    selected_object_t: f32 = 0.0,

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

    pub fn select_object(self: *Self, ray: *const math.Ray) void {
        self.selected_object = null;
        self.selected_object_t = 0.0;
        var closest_t: f32 = std.math.floatMax(f32);
        for (self.objects.items, 0..) |*object, i| {
            const m = Assets.meshes.getPtrConst(object.model);
            const t = object.transform();
            if (m.ray_intersection(&t, ray)) |r| {
                if (r.t < closest_t) {
                    closest_t = r.t;
                    self.selected_object = @intCast(i);
                }
            }
        }
    }

    pub fn draw(self: *Self, dt: f32) void {
        self.selected_object_t += dt;
        for (self.objects.items, 0..) |*object, i| {
            var material = Assets.materials.get(object.model);
            if (self.selected_object) |so| {
                if (so == i) {
                    material.albedo =
                        material.albedo.lerp(.TEAL, @abs(@sin(self.selected_object_t)));
                }
            }
            Renderer.draw_mesh(
                Assets.gpu_meshes.getPtr(object.model),
                object.transform(),
                material,
            );
        }
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

            cimgui.format("Environment", &self.environment);

            _ = cimgui.igSeparatorText("Add");
            for (std.enums.values(Assets.ModelType)) |v| {
                const n = std.fmt.allocPrintZ(scratch_alloc, "Add {}", .{v}) catch unreachable;
                if (cimgui.igButton(n, .{})) {
                    self.objects.append(
                        self.arena.allocator(),
                        .{ .model = v },
                    ) catch unreachable;
                }
            }
        }

        if (self.selected_object) |so| {
            _ = cimgui.igBegin("Selecte object", &open, 0);
            defer cimgui.igEnd();

            const object = &self.objects.items[so];
            cimgui.format(null, object);
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

        self.free_camera.move(dt);
        const mouse_clip = Platform.mouse_clip();
        const camera_ray = self.free_camera.mouse_to_ray(mouse_clip);

        if (Input.was_pressed(.LMB))
            self.level.select_object(&camera_ray);
        if (Input.was_pressed(.RMB))
            self.level.selected_object = null;

        Renderer.reset();
        self.level.draw(dt);
        Renderer.render(&self.free_camera, &self.level.environment);

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
                    cimgui.format("Free camera", &self.free_camera);
                }

                self.level.imgui_ui(self.frame_arena.allocator());
                Input.imgui_ui();
            }
        }
    }
};
