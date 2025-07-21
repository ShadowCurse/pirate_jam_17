const std = @import("std");
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

// Assuming that it is the circle_1 who is trying to collide with circle_2. If they collide
// the collision point will be on the circle_2 surface.
pub fn circle_circle_collision(
    circle_1: Circle,
    circle_1_position: math.Vec2,
    circle_2: Circle,
    circle_2_position: math.Vec2,
) ?CollisionPoint {
    const to_circle_2 = circle_2_position.sub(circle_1_position);
    const to_circle_2_len = to_circle_2.len();
    if (to_circle_2_len < circle_1.radius + circle_2.radius) {
        const to_collision_len = to_circle_2_len - circle_2.radius;
        const to_circle_2_normalized = to_circle_2.normalize();
        const collision_position = circle_1_position
            .add(to_circle_2_normalized.mul_f32(to_collision_len));
        const collision_normal = to_circle_2_normalized.neg();
        return .{
            .position = collision_position,
            .normal = collision_normal,
        };
    } else {
        return null;
    }
}

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

pub const Intersection = enum {
    None,
    Partial,
    Full,
};

const MinMax = struct {
    min_x: f32,
    max_x: f32,
    min_y: f32,
    max_y: f32,
};
fn rectangle_min_max(
    rect: Rectangle,
    position: math.Vec2,
) MinMax {
    const angle = rect.rotation;
    const x_axis = math.Vec2{ .x = @cos(angle), .y = @sin(angle) };
    const y_axis = math.Vec2{ .x = -@sin(angle), .y = @cos(angle) };
    const half_width = rect.size.x / 2.0;
    const half_height = rect.size.y / 2.0;

    const p0 = x_axis.mul_f32(half_width).add(y_axis.mul_f32(half_height));
    const p1 = x_axis.mul_f32(-half_width).add(y_axis.mul_f32(half_height));
    const p2 = x_axis.mul_f32(-half_width).add(y_axis.mul_f32(-half_height));
    const p3 = x_axis.mul_f32(half_width).add(y_axis.mul_f32(-half_height));

    return .{
        .min_x = position.x + @min(@min(p0.x, p1.x), @min(p2.x, p3.x)),
        .max_x = position.x + @max(@max(p0.x, p1.x), @max(p2.x, p3.x)),
        .min_y = position.y + @min(@min(p0.y, p1.y), @min(p2.y, p3.y)),
        .max_y = position.y + @max(@max(p0.y, p1.y), @max(p2.y, p3.y)),
    };
}

// Returns intersection of rectangles AABBs.
pub fn rectangle_rectangle_intersection(
    rect1: Rectangle,
    rect1_position: math.Vec2,
    rect2: Rectangle,
    rect2_position: math.Vec2,
) Intersection {
    const r1 = rectangle_min_max(rect1, rect1_position);
    const r2 = rectangle_min_max(rect2, rect2_position);

    if (r2.min_x <= r1.min_x and r1.max_x <= r2.max_x and
        r2.min_y <= r1.min_y and r1.max_y <= r2.max_y)
        return .Full
    else if (!(r1.max_x < r2.min_x or
        r2.max_x < r1.min_x or
        r2.max_y < r1.min_y or
        r1.max_y < r2.min_y))
        return .Partial
    else
        return .None;
}

test "test_circle_rectangle_collision" {
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
