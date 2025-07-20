const math = @import("math.zig");

pub const Body = struct {
    position: math.Vec2 = .{},
    velocity: math.Vec2 = .{},
    acceleration: math.Vec2 = .{},
    restitution: f32 = 1.0,
    friction: f32 = 0.0,
    inv_mass: f32 = 0.0,
};

pub const Circle = struct {
    radius: f32 = 0.0,
};

pub const Rectangle = struct {
    size: math.Vec2 = .{},
    rotation: f32 = 0.0,
};

pub const Line = struct {
    a: math.Vec2,
    b: math.Vec2,

    const Self = @This();

    pub fn a_to_b(self: *const Self) math.Vec2 {
        return self.b.sub(self.a);
    }
};

pub const CollisionPoint = struct {
    position: math.Vec2,
    normal: math.Vec2,
};

// Assuming that it is the circle who is tryign to collide with rectangle. If they collide
// the collision point will be on the rectangle surface.
pub fn circle_rectangle_collision(
    circle: Circle,
    circle_position: math.Vec2,
    rectangle: Rectangle,
    rectangle_position: math.Vec2,
) ?CollisionPoint {
    const angle = rectangle.rotation;
    const rectangle_x_axis = math.Vec2{ .x = @cos(angle), .y = @sin(angle) };
    const rectangle_y_axis = math.Vec2{ .x = -@sin(angle), .y = @cos(angle) };
    const circle_x = circle_position.sub(rectangle_position).dot(rectangle_x_axis);
    const circle_y = circle_position.sub(rectangle_position).dot(rectangle_y_axis);

    const circle_v2: math.Vec2 = .{ .x = circle_x, .y = circle_y };
    const half_width = rectangle.size.x / 2.0;
    const half_height = rectangle.size.y / 2.0;

    const px: math.Vec2 = .{
        .x = @min(@max(circle_x, -half_width), half_width),
        .y = @min(@max(circle_y, -half_height), half_height),
    };

    const px_to_circle_v2 = circle_v2.sub(px);
    if (px_to_circle_v2.len_squared() < circle.radius * circle.radius) {
        // const collision_position = rectangle_position.add(px);
        const collision_position = rectangle_position
            .add(rectangle_x_axis.mul_f32(px.x))
            .add(rectangle_y_axis.mul_f32(px.y));
        const collision_normal = circle_position.sub(collision_position).normalize();
        return .{
            .position = collision_position,
            .normal = collision_normal,
        };
    } else {
        return null;
    }
}

test "test_circle_rectangle_collision" {
    const std = @import("std");
    const expect = std.testing.expect;
    // no rotation
    // no collision
    // left
    {
        const c: Circle = .{ .radius = 1.0 };
        const c_position: math.Vec2 = .{ .x = -2.0 };
        const r: Rectangle = .{ .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const r_position: math.Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position);
        try expect(collision == null);
    }
    // right
    {
        const c: Circle = .{ .radius = 1.0 };
        const c_position: math.Vec2 = .{ .x = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const r_position: math.Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position);
        try expect(collision == null);
    }
    // bottom
    {
        const c: Circle = .{ .radius = 1.0 };
        const c_position: math.Vec2 = .{ .y = -2.0 };
        const r: Rectangle = .{ .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const r_position: math.Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position);
        try expect(collision == null);
    }
    // top
    {
        const c: Circle = .{ .radius = 1.0 };
        const c_position: math.Vec2 = .{ .y = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const r_position: math.Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position);
        try expect(collision == null);
    }
    // collision
    // inside
    {
        const c: Circle = .{ .radius = 1.0 };
        const c_position: math.Vec2 = .{ .x = 1.0 };
        const r: Rectangle = .{ .size = .{ .x = 4.0, .y = 4.0 } };
        const r_position: math.Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(math.Vec2{ .x = 1.0, .y = 0.0 }));
        try expect(!collision.normal.is_valid());
    }
    // left
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: math.Vec2 = .{ .x = -2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: math.Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(math.Vec2{ .x = -1.0, .y = 0.0 }));
        try expect(collision.normal.eq(math.Vec2{ .x = -1.0, .y = 0.0 }));
    }
    // right
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: math.Vec2 = .{ .x = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: math.Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(math.Vec2{ .x = 1.0, .y = 0.0 }));
        try expect(collision.normal.eq(math.Vec2{ .x = 1.0, .y = 0.0 }));
    }
    // bottom
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: math.Vec2 = .{ .y = -2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: math.Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(math.Vec2{ .x = 0.0, .y = -1.0 }));
        try expect(collision.normal.eq(math.Vec2{ .x = 0.0, .y = -1.0 }));
    }
    // top
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: math.Vec2 = .{ .y = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: math.Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(math.Vec2{ .x = 0.0, .y = 1.0 }));
        try expect(collision.normal.eq(math.Vec2{ .x = 0.0, .y = 1.0 }));
    }
    // collision rect not in the center
    // left
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: math.Vec2 = .{ .y = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: math.Vec2 = .{ .x = 2.0, .y = 2.0 };
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(math.Vec2{ .x = 1.0, .y = 2.0 }));
        try expect(collision.normal.eq(math.Vec2{ .x = -1.0, .y = 0.0 }));
    }
    // right
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: math.Vec2 = .{ .x = 4.0, .y = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: math.Vec2 = .{ .x = 2.0, .y = 2.0 };
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(math.Vec2{ .x = 3.0, .y = 2.0 }));
        try expect(collision.normal.eq(math.Vec2{ .x = 1.0, .y = 0.0 }));
    }
    // bottom
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: math.Vec2 = .{ .x = 2.0, .y = 0.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: math.Vec2 = .{ .x = 2.0, .y = 2.0 };
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(math.Vec2{ .x = 2.0, .y = 1.0 }));
        try expect(collision.normal.eq(math.Vec2{ .x = 0.0, .y = -1.0 }));
    }
    // top
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: math.Vec2 = .{ .x = 2.0, .y = 4.0 };
        const r: Rectangle = .{
            .size = .{ .x = 2.0, .y = 2.0 },
        };
        const r_position: math.Vec2 = .{ .x = 2.0, .y = 2.0 };
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(math.Vec2{ .x = 2.0, .y = 3.0 }));
        try expect(collision.normal.eq(math.Vec2{ .x = 0.0, .y = 1.0 }));
    }

    // collision with rotation
    // top left
    {
        const c: Circle = .{ .radius = 1.0 };
        const c_position: math.Vec2 = .{
            .x = -2.0 * @cos(std.math.pi / 4.0),
            .y = 2.0 * @cos(std.math.pi / 4.0),
        };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 }, .rotation = std.math.pi / 2.0 };
        const r_position: math.Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        const expected_postion: math.Vec2 = .{ .x = -1.0, .y = 0.99999994 };
        // cannot compare normals
        try expect(collision.position.eq(expected_postion));
    }
}
