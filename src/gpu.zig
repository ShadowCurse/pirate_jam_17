const gl = @import("bindings/gl.zig");

pub const Mesh = struct {
    vertex_buffer: u32,
    index_buffer: u32,
    n_indices: i32,
    vertex_array: u32,

    const Self = @This();

    pub fn init(VERTEX_TYPE: type, vertices: []const VERTEX_TYPE, indices: []const u32) Self {
        var vertex_buffer: u32 = undefined;
        gl.glGenBuffers(1, &vertex_buffer);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vertex_buffer);
        gl.glBufferData(
            gl.GL_ARRAY_BUFFER,
            @intCast(@sizeOf(VERTEX_TYPE) * vertices.len),
            vertices.ptr,
            gl.GL_STATIC_DRAW,
        );

        var index_buffer: u32 = undefined;
        gl.glGenBuffers(1, &index_buffer);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, index_buffer);
        gl.glBufferData(
            gl.GL_ELEMENT_ARRAY_BUFFER,
            @intCast(@sizeOf(u32) * indices.len),
            indices.ptr,
            gl.GL_STATIC_DRAW,
        );
        const n_indices: i32 = @intCast(indices.len);

        var vertex_array: u32 = undefined;
        gl.glGenVertexArrays(1, &vertex_array);
        gl.glBindVertexArray(vertex_array);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vertex_buffer);
        VERTEX_TYPE.set_attributes();

        return .{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .n_indices = n_indices,
            .vertex_array = vertex_array,
        };
    }

    const M = @import("mesh.zig");
    pub fn from_mesh(mesh: *const M) Self {
        return Self.init(M.Vertex, mesh.vertices, mesh.indices);
    }

    pub fn draw(self: *const Self) void {
        gl.glBindVertexArray(self.vertex_array);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.index_buffer);
        gl.glDrawElements(gl.GL_TRIANGLES, self.n_indices, gl.GL_UNSIGNED_INT, null);
    }
};
