const std = @import("std");
const log = @import("log.zig");
const math = @import("math.zig");

const Levels = @import("levels.zig");

var animations: [32]Animation = .{Animation{}} ** 32;

pub fn play(dt: f32) void {
    for (&animations) |*animation| {
        switch (animation.object) {
            .None => {},
            .LevelObject => |object| {
                const p = animation.progression / animation.duration;
                const t = p * p * (3.0 - 2.0 * p);

                switch (animation.action) {
                    .move => |*m| {
                        object.position = m.start.lerp(m.end, t);
                    },
                    .rotate_z => |rz| {
                        object.rotation_z = math.lerp(rz.start, rz.end, t);
                    },
                    else => {},
                }

                animation.progression += dt;
                if (animation.duration < animation.progression) {
                    if (animation.callback) |callback|
                        callback(animation.callback_data, object);
                    animation.* = .{};
                }
            },
            .Float => |float| {
                const p = animation.progression / animation.duration;
                const t = p * p * (3.0 - 2.0 * p);

                switch (animation.action) {
                    .move_f32 => |*m| {
                        float.* = math.lerp(m.start, m.end, t);
                    },
                    else => {},
                }

                animation.progression += dt;
                if (animation.duration < animation.progression) {
                    if (animation.callback) |callback|
                        callback(animation.callback_data, float);
                    animation.* = .{};
                }
            },
        }
    }
}

pub fn add(animation: Animation) void {
    switch (animation.object) {
        .None => log.err(@src(), "Adding animation with None object", .{}),
        .LevelObject => |lo| {
            for (&animations) |*a| {
                switch (a.object) {
                    .LevelObject => |o| {
                        if (lo == o) {
                            log.info(
                                @src(),
                                "Found already playing animation, replacing with: {any}",
                                .{animation},
                            );
                            a.* = animation;
                            return;
                        }
                    },
                    else => {},
                }
            }
        },
        .Float => |ff| {
            for (&animations) |*a| {
                switch (a.object) {
                    .Float => |f| {
                        if (ff == f) {
                            log.info(
                                @src(),
                                "Found already playing animation, replacing with: {any}",
                                .{animation},
                            );
                            a.* = animation;
                            return;
                        }
                    },
                    else => {},
                }
            }
        },
    }
    for (&animations) |*a| {
        if (a.object != .None) continue;
        a.* = animation;
        return;
    }
    log.err(@src(), "Cannot add animation because queue is full: {any}", .{animation});
}

pub const Action = union(enum) {
    move: struct {
        start: math.Vec3,
        end: math.Vec3,
    },
    move_f32: struct {
        start: f32,
        end: f32,
    },
    rotate_z: struct {
        start: f32,
        end: f32,
    },
};

pub const Object = union(enum) {
    None,
    LevelObject: *Levels.Level.Object,
    Float: *f32,
};

pub const Animation = struct {
    object: Object = .None,
    action: Action = undefined,
    duration: f32 = 0.0,
    progression: f32 = 0.0,
    callback_data: *anyopaque = undefined,
    callback: ?*const fn (*anyopaque, *anyopaque) void = null,
};
