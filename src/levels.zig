const std = @import("std");
const Allocator = std.mem.Allocator;

const cimgui = @import("bindings/cimgui.zig");

const log = @import("log.zig");
const math = @import("math.zig");
const physics = @import("physics.zig");

const Game = @import("root");
const Camera = Game.Camera;
const PLAYER_CIRCLE = Game.PLAYER_CIRCLE;

const Animations = @import("animations.zig");
const Platform = @import("platform.zig");
const Renderer = @import("renderer.zig");
const Input = @import("input.zig");
const Assets = @import("assets.zig");
const Audio = @import("audio.zig");
const Mesh = @import("mesh.zig");
const Ui = @import("ui.zig");

const DEFAULT_LEVEL_DIR_PATH = "resources/levels";

pub const Tag = enum {
    @"0-1",
    @"0-2",

    pub fn next(self: Tag) Tag {
        var t: u8 = @intFromEnum(self);
        t += 1;
        t %= @typeInfo(Tag).@"enum".fields.len;
        return @enumFromInt(t);
    }

    pub fn path(self: Tag, scratch_alloc: Allocator) []const u8 {
        return std.fmt.allocPrint(
            scratch_alloc,
            "{s}/{s}.json",
            .{ DEFAULT_LEVEL_DIR_PATH, @tagName(self) },
        ) catch unreachable;
    }
};

pub const Levels = std.EnumArray(Tag, Level);

var scratch: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
pub var levels: Levels = .initFill(.empty());

pub fn init() void {
    inline for (0..Levels.len) |i| {
        const tag = Levels.Indexer.keyForIndex(i);
        const level = levels.getPtr(tag);
        level.tag = tag;
        level.reset();
    }
}

pub const Level = struct {
    arena: std.heap.ArenaAllocator = undefined,
    tag: Tag = undefined,

    // Edit
    selected_object: ?u32 = null,
    selected_light: ?u32 = null,
    selected_t: f32 = 0.0,
    draw_light_spheres: bool = true,

    // Player
    holding_object: ?u32 = null,
    put_down_object: ?u32 = null,

    started: bool = false,
    starting: bool = false,
    solved: bool = false,
    finishing: bool = false,
    finished: bool = false,

    // Cursor
    looking_at_pickable_object: bool = false,

    objects: std.ArrayListUnmanaged(Object) = .{},
    environment: Renderer.Environment = .{},

    pub const Object = struct {
        model: Assets.ModelType,
        tag: Object.Tag = .None,
        material: Object.Material = .Original,
        position: math.Vec3 = .{},
        rotation_x: f32 = 0.0,
        rotation_y: f32 = 0.0,
        rotation_z: f32 = 0.0,

        pub const MaterialTag = enum {
            Original,
            Custom,
        };

        pub const Material = union(MaterialTag) {
            Original,
            Custom: Mesh.Material,
        };

        pub const Tag = enum {
            None,
            EntranceDoor,
            ExitDoor,
            CorrectBox,
        };

        fn transform(self: *const Object) math.Mat4 {
            const rotation = math.Quat.from_axis_angle(.X, self.rotation_x)
                .mul(math.Quat.from_axis_angle(.Y, self.rotation_y))
                .mul(math.Quat.from_axis_angle(.Z, self.rotation_z))
                .to_mat4();
            return math.Mat4.IDENDITY.translate(self.position).mul(rotation);
        }
    };

    const DOOR_OPEN_ANIMATION_TIME = 1.5;
    const PICKUP_DISTANCE: f32 = 1.5;
    const Self = @This();

    pub fn reset(self: *Self) void {
        var arena = self.arena;
        _ = arena.reset(.retain_capacity);
        const tag = self.tag;
        self.* = .{ .arena = arena, .tag = tag };

        _ = scratch.reset(.retain_capacity);
        const scratch_alloc = scratch.allocator();
        const path = self.tag.path(scratch_alloc);
        self.load(scratch_alloc, path) catch |e| {
            log.err(@src(), "Error loading level from path: {s}: {}", .{ path, e });
        };
    }

    pub fn empty() Self {
        const arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        return .{
            .arena = arena,
        };
    }

    pub fn select(self: *Self, ray: *const math.Ray) void {
        self.selected_object = null;
        self.selected_light = null;
        self.selected_t = 0.0;
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

        for (&self.environment.lights_position, 0..) |*lp, i| {
            const m = Assets.meshes.getPtrConst(.Sphere);
            const t = math.Mat4.IDENDITY.translate(lp.*).scale(math.vec3(0.1, 0.1, 0.1));
            if (m.ray_intersection(&t, ray)) |r| {
                if (r.t < closest_t) {
                    closest_t = r.t;
                    self.selected_object = null;
                    self.selected_light = @intCast(i);
                }
            }
        }
    }

    pub fn player_offset_in_exit_door(self: *const Self, camera: *const Camera) math.Vec3 {
        for (self.objects.items) |*object| {
            if (object.tag != .ExitDoor) continue;
            return camera.position.sub(object.position);
        }
        log.panic(@src(), "No exit door found", .{});
    }

    pub fn on_entrance_door_open(self: *Self, _: ?*anyopaque) void {
        self.starting = false;
        self.started = true;
    }

    pub fn start_level(self: *Self, camera: *Camera, player_offset: ?math.Vec3) void {
        if (self.started or self.starting) return;

        self.starting = true;
        for (self.objects.items) |*object| {
            if (object.tag != .EntranceDoor) continue;
            camera.position = object.position;
            if (player_offset) |po|
                camera.position = camera.position.add(po);
            camera.position.z = 1.0;
        }
        self.open_doors(.EntranceDoor);

        if (player_offset == null)
            Animations.add(
                .{
                    .object = .{ .Float = &Ui.blur_strength },
                    .action = .{ .move_f32 = .{
                        .start = 10.0,
                        .end = 0.0,
                    } },
                    .duration = DOOR_OPEN_ANIMATION_TIME,
                    .callback_data = self,
                    .callback = @ptrCast(&Self.on_entrance_door_open),
                },
            )
        else
            self.on_entrance_door_open(null);
    }

    pub fn open_doors(self: *Self, tag: Object.Tag) void {
        for (self.objects.items) |*object| {
            if (object.tag != tag) continue;
            Audio.play(.Door, &object.position);
            Animations.add(
                .{
                    .object = .{ .LevelObject = object },
                    .action = .{ .rotate_z = .{
                        .start = object.rotation_z,
                        .end = 0.0,
                    } },
                    .duration = DOOR_OPEN_ANIMATION_TIME,
                },
            );
        }
    }

    pub fn on_exit_door_close(self: *Self, _: *anyopaque) void {
        self.finishing = false;
        self.finished = true;
        log.info(@src(), "Level finished", .{});
    }

    pub fn close_doors(self: *Self) void {
        for (self.objects.items) |*object| {
            if (object.tag != .ExitDoor) continue;
            Audio.play(.Door, &object.position);
            Animations.add(
                .{
                    .object = .{ .LevelObject = object },
                    .action = .{ .rotate_z = .{
                        .start = object.rotation_z,
                        .end = std.math.pi / 2.0,
                    } },
                    .duration = DOOR_OPEN_ANIMATION_TIME,
                    .callback_data = self,
                    .callback = @ptrCast(&Self.on_exit_door_close),
                },
            );
        }
    }

    pub fn player_in_the_door(self: *Self, camera: *const Camera) void {
        if (!self.solved or self.finished) return;

        for (self.objects.items) |*object| {
            if (object.tag != .ExitDoor) continue;
            const distance_to_object = camera.position.xy()
                .sub(object.position.xy()).len();
            if (distance_to_object < 0.26 and !self.finishing) {
                self.close_doors();
                self.finishing = true;
                log.info(@src(), "Level finishing", .{});
            } else if (0.26 < distance_to_object and self.finishing) {
                self.open_doors(.ExitDoor);
                self.finishing = false;
                log.info(@src(), "Level un finishing", .{});
            }
        }
    }

    pub fn player_look_at_object(self: *Self, ray: *const math.Ray, pickup: bool) void {
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
                    if (pickup) {
                        self.holding_object = @intCast(i);
                        Audio.play(.BoxPickup, null);
                    }
                }
            }
        }
        if (self.holding_object != null)
            self.looking_at_pickable_object = false;
    }

    pub fn player_put_down_object(self: *Self) void {
        if (self.holding_object) |ho| {
            if (self.is_box_on_the_box())
                return;

            const object = &self.objects.items[ho];
            Animations.add(
                .{
                    .object = .{ .LevelObject = object },
                    .action = .{ .move = .{
                        .start = object.position,
                        .end = object.position.xy().extend(0.0),
                    } },
                    .duration = 0.2,
                    .callback_data = self,
                    .callback = @ptrCast(&Self.on_box_placement),
                },
            );
        }
        self.holding_object = null;
    }

    pub fn player_move_object(self: *Self, camera: *const Camera, dt: f32) void {
        if (self.holding_object) |ho| {
            const object = &self.objects.items[ho];
            const new_position =
                camera.position
                    .add(camera.forward_xy().mul_f32(0.5))
                    .add(.{ .z = -0.7 });
            object.position = object.position.exp_decay(new_position, 14.0, dt);
            object.rotation_z = math.exp_decay(object.rotation_z, camera.yaw, 14.0, dt);
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
                    for (&[_]f32{
                        object.rotation_z + DELTA_RADIANS,
                        object.rotation_z + DELTA_RADIANS + std.math.pi,
                    }) |starting_rotation| {
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
                    }
                },
                .DoorFrame => {
                    const distance_to_object = camera.position.xy()
                        .sub(object.position.xy()).len();
                    if (RING_RADIUS * 2.0 < distance_to_object) continue;

                    const NNN: u32 = @floor((180.0 - 2 * DELTA_DEGREES) / (DELTA_DEGREES / 2)) + 1;
                    const position = object.position;
                    for (&[_]f32{
                        object.rotation_z + DELTA_RADIANS,
                        object.rotation_z + DELTA_RADIANS + std.math.pi,
                    }) |starting_rotation| {
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
                    }
                },
                else => {},
            }
        }
    }

    fn on_box_placement(
        self: *Self,
        object: *Object,
    ) void {
        Audio.play(.BoxPutDown, &object.position);
        var r1 = Assets.aabbs.get(object.model);
        r1.rotation = object.rotation_z;
        const r1_position = object.position.xy();

        if (object.tag != .CorrectBox) return;

        for (self.objects.items) |*o| {
            if (o.model != .Platform) continue;

            const r2 = Assets.aabbs.get(o.model);
            const r2_position = o.position.xy();
            if (!self.solved and physics.rectangle_rectangle_intersection(
                r1,
                r1_position,
                r2,
                r2_position,
            ) == .Full) {
                self.solved = true;
                Audio.play(.Success, null);
                self.open_doors(.ExitDoor);
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
        self.selected_t += dt;
        for (self.objects.items, 0..) |*object, i| {
            const material = switch (object.material) {
                .Original => Assets.materials.get(object.model),
                .Custom => |m| m,
            };
            _ = i;
            // if (self.selected_object) |so| {
            //     if (so == i) {
            //         material.albedo =
            //             material.albedo.lerp(.TEAL, @abs(@sin(self.selected_t)));
            //     }
            // }

            Renderer.draw_mesh(
                Assets.gpu_meshes.getPtr(object.model),
                object.transform(),
                material,
            );
        }
        if (self.draw_light_spheres) {
            for (
                &self.environment.lights_position,
                &self.environment.lights_color,
                0..,
            ) |*lp, *lc, i| {
                var color: math.Color4 = lc.*.with_alpha(1.0);
                if (self.selected_light) |sl| {
                    if (sl == i)
                        color =
                            color.lerp(.TEAL, @abs(@sin(self.selected_t)));
                }
                Renderer.draw_mesh(
                    Assets.gpu_meshes.getPtr(.Sphere),
                    math.Mat4.IDENDITY.translate(lp.*).scale(math.vec3(0.1, 0.1, 0.1)),
                    .{ .albedo = color },
                );
            }
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
            0,
        )) {
            cimgui.format(null, self);

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
        }

        if (self.selected_object) |so| {
            _ = cimgui.igBegin("Selected object", &open, 0);
            defer cimgui.igEnd();

            const object = &self.objects.items[so];
            cimgui.format(null, object);

            if (cimgui.igButton("Change to custom material", .{})) {
                object.material = .{ .Custom = .{} };
            }
            if (cimgui.igButton("Change to origina material", .{})) {
                object.material = .Original;
            }
        }

        if (self.selected_light) |sl| {
            _ = cimgui.igBegin("Selected light", &open, 0);
            defer cimgui.igEnd();

            cimgui.format("Position", &self.environment.lights_position[sl]);
            cimgui.format("Color", &self.environment.lights_color[sl]);
        }
    }
};
