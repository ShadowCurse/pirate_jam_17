const std = @import("std");
const log = @import("log.zig");
const math = @import("math.zig");

const Levels = @import("levels.zig");

var animations: [32]Animation = .{Animation{}} ** 32;

pub fn play(dt: f32) void {
    for (&animations) |*animation| {
        if (animation.object) |object| {
            const p = animation.progression / animation.duration;
            const t = p * p * (3.0 - 2.0 * p);

            switch (animation.action) {
                .move => |*m| {
                    object.position = m.start.lerp(m.end, t);
                },
                .rotate_z => |rz| {
                    object.rotation_z = math.lerp(rz.start, rz.end, t);
                },
            }

            animation.progression += dt;
            if (animation.duration < animation.progression) {
                if (animation.callback) |callback|
                    callback(animation.callback_data, object);
                animation.* = .{};
            }
        }
    }
}

pub fn add(animation: Animation) void {
    for (&animations) |*a| {
        if (a.object) |o| {
            if (o == animation.object) {
                log.info(
                    @src(),
                    "Found already playing animation, replacing with: {any}",
                    .{animation},
                );
                a.* = animation;
                return;
            }
        }
    }
    for (&animations) |*a| {
        if (a.object != null) continue;
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
    rotate_z: struct {
        start: f32,
        end: f32,
    },
};

pub const Animation = struct {
    object: ?*Levels.Level.Object = null,
    action: Action = undefined,
    duration: f32 = 0.0,
    progression: f32 = 0.0,
    callback_data: *anyopaque = undefined,
    callback: ?*const fn (*anyopaque, *Levels.Level.Object) void = null,
};
