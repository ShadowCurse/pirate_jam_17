const gl = @import("bindings/gl.zig");
const math = @import("math.zig");

indices: []const Index,
vertices: []const Vertex,

pub const Material = struct {
    albedo: math.Color4 = .WHITE,
    metallic: f32 = 0.5,
    roughness: f32 = 0.5,
    emissive_strength: f32 = 0.0,
    no_shadow: bool = false,
};

const Self = @This();

pub const Index = u32;
pub const Vertex = extern struct {
    position: math.Vec3 = .{},
    uv_x: f32 = 0.0,
    normal: math.Vec3 = .{},
    uv_y: f32 = 0.0,
    color: math.Vec4 = .{},

    pub fn set_attributes() void {
        gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(0));
        gl.glVertexAttribPointer(1, 1, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(3 * @sizeOf(f32)));
        gl.glVertexAttribPointer(2, 3, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(4 * @sizeOf(f32)));
        gl.glVertexAttribPointer(3, 1, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(7 * @sizeOf(f32)));
        gl.glVertexAttribPointer(4, 4, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(8 * @sizeOf(f32)));
        gl.glEnableVertexAttribArray(0);
        gl.glEnableVertexAttribArray(1);
        gl.glEnableVertexAttribArray(2);
        gl.glEnableVertexAttribArray(3);
        gl.glEnableVertexAttribArray(4);
    }
};

pub fn triangle_iterator(self: *const Self) TriangleIterator {
    return .{
        .mesh = self,
    };
}

pub const TriangleIterator = struct {
    index: usize = 0,
    mesh: *const Self,

    pub fn next(self: *TriangleIterator) ?math.Triangle {
        const index = self.index;
        if (index < self.mesh.indices.len) {
            self.index += 3;
            return .{
                .v0 = self.mesh.vertices[self.mesh.indices[index]].position,
                .v1 = self.mesh.vertices[self.mesh.indices[index + 1]].position,
                .v2 = self.mesh.vertices[self.mesh.indices[index + 2]].position,
            };
        }
        return null;
    }
};

pub fn ray_intersection(
    self: *const Self,
    transform: *const math.Mat4,
    ray: *const math.Ray,
) ?math.TriangleIntersectionResult {
    var ti = self.triangle_iterator();
    while (ti.next()) |t| {
        const tt = t.translate(transform);

        const is_ccw = math.triangle_ccw(ray.direction, &tt);
        if (!is_ccw)
            continue;

        if (math.triangle_ray_intersect(ray, &tt)) |intersection|
            return intersection;
    }
    return null;
}

pub const Cube = Self{
    .indices = &.{
        1,
        14,
        20,
        1,
        20,
        7,
        10,
        6,
        19,
        10,
        19,
        23,
        21,
        18,
        12,
        21,
        12,
        15,
        16,
        3,
        9,
        16,
        9,
        22,
        5,
        2,
        8,
        5,
        8,
        11,
        17,
        13,
        0,
        17,
        0,
        4,
    },
    .vertices = &.{
        .{
            .position = .{ .x = 0.5, .y = 0.5, .z = -0.5 },
            .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 },
            .uv_x = 6.25e-1,
            .uv_y = 5e-1,
            .color = .{ .x = 0.0, .y = 0.0, .z = -1.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = 0.5, .y = 0.5, .z = -0.5 },
            .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
            .uv_x = 6.25e-1,
            .uv_y = 5e-1,
            .color = .{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = 0.5, .y = 0.5, .z = -0.5 },
            .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
            .uv_x = 6.25e-1,
            .uv_y = 5e-1,
            .color = .{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = 0.5, .y = -0.5, .z = -0.5 },
            .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 },
            .uv_x = 3.75e-1,
            .uv_y = 5e-1,
            .color = .{ .x = 0.0, .y = -1.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = 0.5, .y = -0.5, .z = -0.5 },
            .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 },
            .uv_x = 3.75e-1,
            .uv_y = 5e-1,
            .color = .{ .x = 0.0, .y = 0.0, .z = -1.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = 0.5, .y = -0.5, .z = -0.5 },
            .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
            .uv_x = 3.75e-1,
            .uv_y = 5e-1,
            .color = .{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
            .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 },
            .uv_x = 6.25e-1,
            .uv_y = 2.5e-1,
            .color = .{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
            .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
            .uv_x = 6.25e-1,
            .uv_y = 2.5e-1,
            .color = .{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
            .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
            .uv_x = 6.25e-1,
            .uv_y = 2.5e-1,
            .color = .{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = 0.5, .y = -0.5, .z = 0.5 },
            .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 },
            .uv_x = 3.75e-1,
            .uv_y = 2.5e-1,
            .color = .{ .x = 0.0, .y = -1.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = 0.5, .y = -0.5, .z = 0.5 },
            .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 },
            .uv_x = 3.75e-1,
            .uv_y = 2.5e-1,
            .color = .{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = 0.5, .y = -0.5, .z = 0.5 },
            .normal = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
            .uv_x = 3.75e-1,
            .uv_y = 2.5e-1,
            .color = .{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = 0.5, .z = -0.5 },
            .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 },
            .uv_x = 6.25e-1,
            .uv_y = 7.5e-1,
            .color = .{ .x = -1.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = 0.5, .z = -0.5 },
            .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 },
            .uv_x = 6.25e-1,
            .uv_y = 7.5e-1,
            .color = .{ .x = 0.0, .y = 0.0, .z = -1.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = 0.5, .z = -0.5 },
            .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
            .uv_x = 8.75e-1,
            .uv_y = 5e-1,
            .color = .{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = -0.5, .z = -0.5 },
            .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 },
            .uv_x = 3.75e-1,
            .uv_y = 7.5e-1,
            .color = .{ .x = -1.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = -0.5, .z = -0.5 },
            .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 },
            .uv_x = 1.25e-1,
            .uv_y = 5e-1,
            .color = .{ .x = 0.0, .y = -1.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = -0.5, .z = -0.5 },
            .normal = .{ .x = 0.0, .y = 0.0, .z = -1.0 },
            .uv_x = 3.75e-1,
            .uv_y = 7.5e-1,
            .color = .{ .x = 0.0, .y = 0.0, .z = -1.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = 0.5, .z = 0.5 },
            .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 },
            .uv_x = 6.25e-1,
            .uv_y = 0.5,
            .color = .{ .x = -1.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = 0.5, .z = 0.5 },
            .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 },
            .uv_x = 6.25e-1,
            .uv_y = 0.0,
            .color = .{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = 0.5, .z = 0.5 },
            .normal = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
            .uv_x = 8.75e-1,
            .uv_y = 2.5e-1,
            .color = .{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = -0.5, .z = 0.5 },
            .normal = .{ .x = -1.0, .y = 0.0, .z = 0.0 },
            .uv_x = 3.75e-1,
            .uv_y = 0.5,
            .color = .{ .x = -1.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = -0.5, .z = 0.5 },
            .normal = .{ .x = 0.0, .y = -1.0, .z = 0.0 },
            .uv_x = 1.25e-1,
            .uv_y = 2.5e-1,
            .color = .{ .x = 0.0, .y = -1.0, .z = 0.0, .w = 1.0 },
        },
        .{
            .position = .{ .x = -0.5, .y = -0.5, .z = 0.5 },
            .normal = .{ .x = 0.0, .y = 0.0, .z = 1.0 },
            .uv_x = 3.75e-1,
            .uv_y = 0.0,
            .color = .{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 1.0 },
        },
    },
};
