const std = @import("std");
const Allocator = std.mem.Allocator;

const cimgui = @import("bindings/cimgui.zig");

const log = @import("log.zig");
const math = @import("math.zig");
const physics = @import("physics.zig");

const Camera = @import("root").Camera;
const PLAYER_CIRCLE = @import("root").PLAYER_CIRCLE;
const Platform = @import("platform.zig");
const Renderer = @import("renderer.zig");
const Input = @import("input.zig");
const Assets = @import("assets.zig");

const DEFAULT_LEVEL_DIR_PATH = "resources/levels";

pub const Tag = enum {
    @"0-1",
    @"0-2",
    @"1-1",
    @"1-2",
};

pub const Levels = std.EnumArray(Tag, Level);

var scratch: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
pub var levels: Levels = .initFill(.empty());

pub fn init() void {
    _ = scratch.reset(.retain_capacity);

    const scratch_alloc = scratch.allocator();
    inline for (0..Levels.len) |i| {
        const tag = Levels.Indexer.keyForIndex(i);
        const path = std.fmt.allocPrint(
            scratch_alloc,
            "{s}/{s}.json",
            .{ DEFAULT_LEVEL_DIR_PATH, @tagName(tag) },
        ) catch unreachable;

        const level = levels.getPtr(tag);
        level.reset();
        level.load(scratch_alloc, path) catch |e| {
            log.err(@src(), "Error loading level from path: {s}: {}", .{ path, e });
        };
    }
}

pub const Level = struct {
    arena: std.heap.ArenaAllocator = undefined,

    // Edit
    selected_object: ?u32 = null,
    selected_object_t: f32 = 0.0,

    // Player
    holding_object: ?u32 = null,
    put_down_object: ?u32 = null,
    box_on_the_platform: bool = false,
    in_the_door: bool = false,

    // Cursor
    looking_at_pickable_object: bool = false,

    // Door
    door_animation_progress: f32 = 0.0,

    objects: std.ArrayListUnmanaged(Object) = .{},
    environment: Renderer.Environment = .{},

    const Object = struct {
        model: Assets.ModelType,
        position: math.Vec3 = .{},
        rotation_x: f32 = 0.0,
        rotation_y: f32 = 0.0,
        rotation_z: f32 = 0.0,
        // used for doors animation
        target_rotation_z: ?f32 = null,
        scale: math.Vec3 = .ONE,

        fn transform(self: *const Object) math.Mat4 {
            const rotation = math.Quat.from_axis_angle(.X, self.rotation_x)
                .mul(math.Quat.from_axis_angle(.Y, self.rotation_y))
                .mul(math.Quat.from_axis_angle(.Z, self.rotation_z))
                .to_mat4();
            return math.Mat4.IDENDITY.translate(self.position).scale(self.scale).mul(rotation);
        }
    };

    const DOOR_OPEN_ANIMATION_TIME = 0.5;
    const PICKUP_DISTANCE: f32 = 1.5;
    const Self = @This();

    pub fn reset(self: *Self) void {
        var arena = self.arena;
        _ = arena.reset(.retain_capacity);
        self.* = .{};
        self.arena = arena;
    }

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

    pub fn cursor_animate(self: *Self, dt: f32) void {
        const MAX_SIZE = 0.05;
        const MIN_SIZE = 0.0;
        if (self.looking_at_pickable_object)
            self.environment.cursor_size = math.exp_decay(
                self.environment.cursor_size,
                MAX_SIZE,
                18.0,
                dt,
            )
        else
            self.environment.cursor_size = math.exp_decay(
                self.environment.cursor_size,
                MIN_SIZE,
                18.0,
                dt,
            );
    }

    pub fn door_animate(self: *Self, dt: f32) void {
        if (DOOR_OPEN_ANIMATION_TIME < self.door_animation_progress) return;
        if (!self.box_on_the_platform and !self.in_the_door) return;

        self.door_animation_progress += dt;
        for (self.objects.items) |*object| {
            if (object.model != .DoorDoor) continue;
            if (object.target_rotation_z) |rtz| {
                object.rotation_z = math.exp_decay(object.rotation_z, rtz, 16.0, dt);
                if (DOOR_OPEN_ANIMATION_TIME < self.door_animation_progress) {
                    object.target_rotation_z = null;
                }
            } else {
                if (self.box_on_the_platform)
                    object.target_rotation_z = object.rotation_z + std.math.pi / 2.0;
                if (self.in_the_door)
                    object.target_rotation_z = object.rotation_z - std.math.pi / 2.0;
            }
        }
    }

    pub fn player_in_the_door(self: *Self, camera: *const Camera) void {
        for (self.objects.items) |*object| {
            if (object.model != .DoorFrame) continue;
            const distance_to_object = camera.position.xy()
                .sub(object.position.xy()).len();
            if (distance_to_object < 0.26) {
                self.in_the_door = true;
                self.door_animation_progress = 0.0;
            }
        }
    }

    pub fn player_pick_up_object(self: *Self, ray: *const math.Ray) void {
        self.looking_at_pickable_object = false;
        if (self.holding_object != null) return;

        var closest_t: f32 = std.math.floatMax(f32);
        for (self.objects.items, 0..) |*object, i| {
            if (object.model != .Box) continue;
            const m = Assets.meshes.getPtrConst(object.model);

            if (Self.PICKUP_DISTANCE < object.position.sub(ray.origin).len())
                continue;

            const t = object.transform();
            if (m.ray_intersection(&t, ray)) |r| {
                self.looking_at_pickable_object = true;
                if (r.t < closest_t) {
                    closest_t = r.t;
                    if (Input.was_pressed(.LMB))
                        self.holding_object = @intCast(i);
                }
            }
        }
    }

    pub fn player_put_down_object(self: *Self) void {
        if (self.holding_object) |ho| {
            if (self.is_box_on_the_box())
                return;

            if (self.put_down_object) |pdo| {
                const object = &self.objects.items[pdo];
                object.position.z = 0.0;
                self.is_box_on_the_platform();
            }
            self.put_down_object = ho;
        }
        self.holding_object = null;
    }

    pub fn player_move_object(self: *Self, camera: *const Camera, dt: f32) void {
        if (self.holding_object) |ho| {
            const object = &self.objects.items[ho];
            const new_position =
                camera.position
                    .add(camera.forward().mul_f32(1.0))
                    .add(.{ .z = -0.5 });
            object.position = object.position.exp_decay(new_position, 14.0, dt);
            object.rotation_z = math.exp_decay(object.rotation_z, camera.yaw, 14.0, dt);
        }
    }

    pub fn settle_put_down_object(self: *Self, dt: f32) void {
        if (self.put_down_object) |pdo| {
            const object = &self.objects.items[pdo];
            object.position.z = math.exp_decay(object.position.z, 0.0, 20, dt);
            if (object.position.z < 0.01) {
                self.is_box_on_the_platform();

                object.position.z = 0.0;
                self.put_down_object = null;
            }
        }
    }

    pub fn player_collide(self: *Self, camera: *Camera) void {
        // Constants for the door cirlec ring collision.
        const DELTA_DEGREES: f32 = 40.0;
        const DELTA_RADIANS: f32 = std.math.degreesToRadians(DELTA_DEGREES);
        const DELTA_RADIANS_HALF: f32 = std.math.degreesToRadians(DELTA_DEGREES / 2);
        const RING_RADIUS = 0.37;
        const RING_PROBE_RADIUS: f32 = 0.01;

        for (self.objects.items, 0..) |*object, i| {
            if (object.model == .Box) {
                if (self.holding_object) |ho| {
                    if (ho == i)
                        continue;
                }
            }

            switch (object.model) {
                .Wall, .Box => {
                    var wall_rectangle = Assets.aabbs.get(object.model);
                    wall_rectangle.rotation = object.rotation_z;
                    const wall_position = object.position.xy();

                    if (physics.circle_rectangle_collision(
                        PLAYER_CIRCLE,
                        camera.position.xy(),
                        wall_rectangle,
                        wall_position,
                    )) |collision| {
                        camera.position = collision.position
                            .add(collision.normal.mul_f32(PLAYER_CIRCLE.radius))
                            .extend(1.0);
                    }
                },
                .DoorDoor => {
                    const distance_to_object = camera.position.xy()
                        .sub(object.position.xy()).len();
                    if (RING_RADIUS * 2.0 < distance_to_object) continue;

                    const NNN: u32 = @floor((180.0 - 2 * DELTA_DEGREES) / (DELTA_DEGREES / 2));
                    const position = object.position;
                    const starting_rotation = object.rotation_z + DELTA_RADIANS;
                    for (0..NNN) |n| {
                        const rotation = math.Quat.from_axis_angle(
                            .Z,
                            starting_rotation - DELTA_RADIANS_HALF * @as(f32, @floatFromInt(n)),
                        );
                        const forward = rotation.rotate_vec3(.NEG_X);
                        const circle_position = position.add(forward.mul_f32(RING_RADIUS));
                        const R: f32 = 0.01;
                        const circle: physics.Circle = .{ .radius = R };

                        // const t = math.Mat4.IDENDITY
                        //     .translate(circle_position.add(.{ .z = 1.0 }))
                        //     .scale(.{ .x = R, .y = R, .z = R });
                        // Renderer.draw_mesh(
                        //     Assets.gpu_meshes.getPtr(.Sphere),
                        //     t,
                        //     Assets.materials.get(.Sphere),
                        // );

                        if (physics.circle_circle_collision(
                            PLAYER_CIRCLE,
                            camera.position.xy(),
                            circle,
                            circle_position.xy(),
                        )) |collision| {
                            camera.position = collision.position
                                .add(collision.normal.mul_f32(PLAYER_CIRCLE.radius))
                                .extend(1.0);
                        }
                    }
                },
                .DoorFrame => {
                    const distance_to_object = camera.position.xy()
                        .sub(object.position.xy()).len();
                    if (RING_RADIUS * 2.0 < distance_to_object) continue;

                    const NNN: u32 = @floor((180.0 - 2 * DELTA_DEGREES) / (DELTA_DEGREES / 2)) + 1;
                    const position = object.position;
                    var starting_rotation = object.rotation_z + DELTA_RADIANS;
                    for (0..NNN) |n| {
                        const rotation = math.Quat.from_axis_angle(
                            .Z,
                            starting_rotation + DELTA_RADIANS_HALF * @as(f32, @floatFromInt(n)),
                        );
                        const forward = rotation.rotate_vec3(.NEG_X);
                        const circle_position = position.add(forward.mul_f32(RING_RADIUS));
                        const circle: physics.Circle = .{ .radius = RING_PROBE_RADIUS };

                        // const t = math.Mat4.IDENDITY
                        //     .translate(circle_position.add(.{ .z = 1.0 }))
                        //     .scale(.{
                        //     .x = RING_PROBE_RADIUS,
                        //     .y = RING_PROBE_RADIUS,
                        //     .z = RING_PROBE_RADIUS,
                        // });
                        // Renderer.draw_mesh(
                        //     Assets.gpu_meshes.getPtr(.Sphere),
                        //     t,
                        //     Assets.materials.get(.Sphere),
                        // );

                        if (physics.circle_circle_collision(
                            PLAYER_CIRCLE,
                            camera.position.xy(),
                            circle,
                            circle_position.xy(),
                        )) |collision| {
                            camera.position = collision.position
                                .add(collision.normal.mul_f32(PLAYER_CIRCLE.radius))
                                .extend(1.0);
                        }
                    }

                    starting_rotation = object.rotation_z - DELTA_RADIANS;
                    for (0..NNN) |n| {
                        const rotation = math.Quat.from_axis_angle(
                            .Z,
                            starting_rotation - DELTA_RADIANS_HALF * @as(f32, @floatFromInt(n)),
                        );
                        const forward = rotation.rotate_vec3(.NEG_X);
                        const circle_position = position.add(forward.mul_f32(RING_RADIUS));
                        const circle: physics.Circle = .{ .radius = RING_PROBE_RADIUS };

                        // const t = math.Mat4.IDENDITY
                        //     .translate(circle_position.add(.{ .z = 1.0 }))
                        //     .scale(.{
                        //     .x = RING_PROBE_RADIUS,
                        //     .y = RING_PROBE_RADIUS,
                        //     .z = RING_PROBE_RADIUS,
                        // });
                        // Renderer.draw_mesh(
                        //     Assets.gpu_meshes.getPtr(.Sphere),
                        //     t,
                        //     Assets.materials.get(.Sphere),
                        // );

                        if (physics.circle_circle_collision(
                            PLAYER_CIRCLE,
                            camera.position.xy(),
                            circle,
                            circle_position.xy(),
                        )) |collision| {
                            camera.position = collision.position
                                .add(collision.normal.mul_f32(PLAYER_CIRCLE.radius))
                                .extend(1.0);
                        }
                    }
                },
                else => {},
            }
        }
    }

    fn is_box_on_the_platform(self: *Self) void {
        if (self.put_down_object) |pdo| {
            const object = &self.objects.items[pdo];

            var r1 = Assets.aabbs.get(object.model);
            r1.rotation = object.rotation_z;
            const r1_position = object.position.xy();

            for (self.objects.items) |*o| {
                if (o.model != .Platform) continue;

                const r2 = Assets.aabbs.get(o.model);
                const r2_position = o.position.xy();
                if (physics.rectangle_rectangle_intersection(
                    r1,
                    r1_position,
                    r2,
                    r2_position,
                ) == .Full) {
                    self.box_on_the_platform = true;
                    self.door_animation_progress = 0.0;
                }
            }
        }
    }

    fn is_box_on_the_box(self: *Self) bool {
        var intersects: bool = false;
        if (self.holding_object) |ho| {
            const object = &self.objects.items[ho];

            var r1 = Assets.aabbs.get(object.model);
            r1.rotation = object.rotation_z;
            const r1_position = object.position.xy();

            for (self.objects.items, 0..) |*o, i| {
                if (o.model != .Box or i == ho) continue;

                const r2 = Assets.aabbs.get(o.model);
                const r2_position = o.position.xy();
                const result = physics.rectangle_rectangle_intersection(
                    r1,
                    r1_position,
                    r2,
                    r2_position,
                );
                intersects = intersects or result == .Partial;
            }
        }
        return intersects;
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
            if ((object.model == .Platform or
                object.model == .DoorOuterLight or
                object.model == .DoorInnerLight) and
                self.box_on_the_platform)
                material.albedo = .GREEN;

            if ((object.model == .DoorOuterLight or
                object.model == .DoorInnerLight) and
                !self.box_on_the_platform)
                material.albedo = .RED;

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

    pub fn save(self: *const Self, path: []const u8) !void {
        var file = try std.fs.cwd().createFile(path, .{});
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

        const file_mem = try Platform.FileMem.init(path);
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
        tag: Tag,
    ) void {
        var open: bool = true;
        if (cimgui.igCollapsingHeader_BoolPtr(
            "Level",
            &open,
            cimgui.ImGuiTreeNodeFlags_DefaultOpen,
        )) {
            _ = cimgui.igSeparatorText("Save/Load");
            const path = std.fmt.allocPrintZ(
                scratch_alloc,
                "{s}/{s}.json",
                .{ DEFAULT_LEVEL_DIR_PATH, @tagName(tag) },
            ) catch unreachable;
            if (cimgui.igButton("Save level", .{})) {
                self.save(path) catch |e|
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
