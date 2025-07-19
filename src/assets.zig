const std = @import("std");
const Allocator = std.mem.Allocator;

const stb = @import("bindings/stb.zig");
const cgltf = @import("bindings/cgltf.zig");

const log = @import("log.zig");
const gpu = @import("gpu.zig");
const math = @import("math.zig");

const Mesh = @import("mesh.zig");

pub const DEFAULT_MESHES_DIR_PATH = "resources/models";

pub const ModelType = enum {
    Floor,
    Wall,
    Box,
};

const ModelPathsType = std.EnumArray(ModelType, [:0]const u8);
const MODEL_PATHS = ModelPathsType.init(.{
    .Floor = DEFAULT_MESHES_DIR_PATH ++ "/floor.glb",
    .Wall = DEFAULT_MESHES_DIR_PATH ++ "/wall.glb",
    .Box = DEFAULT_MESHES_DIR_PATH ++ "/box.glb",
});

pub const GpuMeshes = std.EnumArray(ModelType, gpu.Mesh);
pub const Materials = std.EnumArray(ModelType, Mesh.Material);
pub const Meshes = std.EnumArray(ModelType, Mesh);

var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
var scratch: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
pub var gpu_meshes: GpuMeshes = undefined;
pub var materials: Materials = undefined;
pub var meshes: Meshes = undefined;

const Self = @This();

pub fn init() void {
    _ = arena.reset(.retain_capacity);
    _ = scratch.reset(.retain_capacity);

    const arena_alloc = arena.allocator();
    const scratch_alloc = scratch.allocator();

    for (0..ModelPathsType.len) |i| {
        const model_type = ModelPathsType.Indexer.keyForIndex(i);
        const path = MODEL_PATHS.values[i];

        load_model(path, arena_alloc, scratch_alloc, model_type) catch |e| {
            log.panic(@src(), "Error loading model from path: {s}: {}", .{ path, e });
        };
    }

    for (std.enums.values(ModelType)) |v| {
        gpu_meshes.getPtr(v).* = gpu.Mesh.from_mesh(meshes.getPtrConst(v));
    }
}

pub fn load_model(
    path: [:0]const u8,
    assests_alloc: Allocator,
    scratch_alloc: Allocator,
    model_type: ModelType,
) !void {
    log.info(
        @src(),
        "Loading gltf model of type {any} from path: {s}",
        .{ model_type, path },
    );

    // TODO add allocator params?
    const options = cgltf.cgltf_options{};
    var data: *cgltf.cgltf_data = undefined;
    try cgltf.check_result(cgltf.cgltf_parse_file(&options, path.ptr, @ptrCast(&data)));
    try cgltf.check_result(cgltf.cgltf_load_buffers(&options, data, path.ptr));
    defer cgltf.cgltf_free(data);

    if (data.meshes_count != 1)
        return error.cgltf_too_many_meshes;

    const gltf_mesh = &data.meshes[0];

    if (gltf_mesh.primitives_count != 1)
        return error.cgltf_too_many_primitives;

    if (data.materials_count != 1)
        return error.cgltf_too_many_materials;

    const material = &data.materials[0];
    materials.getPtr(model_type).* = .{
        .albedo = @bitCast(material.pbr_metallic_roughness.base_color_factor),
        .metallic = material.pbr_metallic_roughness.metallic_factor,
        .roughness = material.pbr_metallic_roughness.roughness_factor,
    };

    const mesh_name = std.mem.span(gltf_mesh.name);
    log.info(@src(), "Mesh name: {s}", .{mesh_name});

    const primitive = &gltf_mesh.primitives[0];
    const number_of_indices = primitive.indices[0].count;

    const initial_index_num = 0;
    const indices = try assests_alloc.alloc(Mesh.Index, initial_index_num + number_of_indices);
    for (indices[initial_index_num..], 0..) |*i, j| {
        const index = cgltf.cgltf_accessor_read_index(primitive.indices, j);
        i.* = @intCast(index);
    }

    const number_of_vertices = primitive.attributes[0].data[0].count;
    const initial_vertex_num = 0;
    const vertices = try assests_alloc.alloc(Mesh.Vertex, initial_vertex_num + number_of_vertices);

    log.info(@src(), "Mesh primitive type: {}", .{primitive.type});
    for (primitive.attributes[0..primitive.attributes_count]) |attr| {
        log.info(
            @src(),
            "Mesh primitive attr name: {s}, type: {}, index: {}, data type: {}, data count: {}",
            .{
                attr.name,
                attr.type,
                attr.index,
                attr.data[0].type,
                attr.data[0].count,
            },
        );
        const num_floats = cgltf.cgltf_accessor_unpack_floats(attr.data, null, 0);
        const floats = try scratch_alloc.alloc(f32, num_floats);
        _ = cgltf.cgltf_accessor_unpack_floats(attr.data, floats.ptr, num_floats);

        switch (attr.type) {
            cgltf.cgltf_attribute_type_position => {
                const num_components = cgltf.cgltf_num_components(attr.data[0].type);
                log.info(@src(), "Position has components: {}", .{num_components});
                log.assert(
                    @src(),
                    num_components == 3,
                    "Position has {d} components insead of {d}",
                    .{ num_components, @as(u32, 3) },
                );

                var positions: []const math.Vec3 = undefined;
                positions.ptr = @ptrCast(floats.ptr);
                positions.len = floats.len / 3;

                for (vertices[initial_vertex_num..], positions) |*vertex, position| {
                    vertex.position = position;
                }
            },
            cgltf.cgltf_attribute_type_normal => {
                const num_components = cgltf.cgltf_num_components(attr.data[0].type);
                log.info(@src(), "Normal has components: {}", .{num_components});
                log.assert(
                    @src(),
                    num_components == 3,
                    "Normal has {d} componenets insead of {d}",
                    .{ num_components, @as(u32, 3) },
                );

                var normals: []const math.Vec3 = undefined;
                normals.ptr = @ptrCast(floats.ptr);
                normals.len = floats.len / 3;

                for (vertices[initial_vertex_num..], normals) |*vertex, normal| {
                    vertex.normal = normal;
                }
            },
            cgltf.cgltf_attribute_type_texcoord => {
                const num_components = cgltf.cgltf_num_components(attr.data[0].type);
                log.info(@src(), "Texture coord has components: {}", .{num_components});
                log.assert(
                    @src(),
                    num_components == 2,
                    "Texture coord has {d} components insead of {d}",
                    .{ num_components, @as(u32, 2) },
                );

                var uvs: []const math.Vec2 = undefined;
                uvs.ptr = @ptrCast(floats.ptr);
                uvs.len = floats.len / 2;

                for (vertices[initial_vertex_num..], uvs) |*vertex, uv| {
                    vertex.uv_x = uv.x;
                    vertex.uv_y = uv.y;
                }
            },
            else => {
                log.err(@src(), "Unknown attribute type: {}. Skipping", .{attr.type});
            },
        }

        // For debugging use normals as colors
        for (vertices) |*v| {
            v.color = v.normal.extend(1.0);
        }
    }

    const mesh = meshes.getPtr(model_type);
    mesh.indices = indices;
    mesh.vertices = vertices;
}
