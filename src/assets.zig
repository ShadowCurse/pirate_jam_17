const std = @import("std");
const Allocator = std.mem.Allocator;

const stb = @import("bindings/stb.zig");
const cgltf = @import("bindings/cgltf.zig");

const log = @import("log.zig");
const gpu = @import("gpu.zig");
const math = @import("math.zig");
const physics = @import("physics.zig");

const Platform = @import("platform.zig");
const Mesh = @import("mesh.zig");
const Audio = @import("audio.zig");

pub const DEFAULT_MESHES_DIR_PATH = "resources/models";
pub const ModelType = enum {
    Sphere,
    Floor,
    Wall,
    Box,
    Platform,
    DoorDoor,
    DoorFrame,
    DoorInnerLight,
};
const ModelPathsType = std.EnumArray(ModelType, [:0]const u8);
const MODEL_PATHS = ModelPathsType.init(.{
    .Sphere = DEFAULT_MESHES_DIR_PATH ++ "/sphere.glb",
    .Floor = DEFAULT_MESHES_DIR_PATH ++ "/floor.glb",
    .Wall = DEFAULT_MESHES_DIR_PATH ++ "/wall.glb",
    .Box = DEFAULT_MESHES_DIR_PATH ++ "/box.glb",
    .Platform = DEFAULT_MESHES_DIR_PATH ++ "/platform.glb",
    .DoorDoor = DEFAULT_MESHES_DIR_PATH ++ "/door_door.glb",
    .DoorFrame = DEFAULT_MESHES_DIR_PATH ++ "/door_frame.glb",
    .DoorInnerLight = DEFAULT_MESHES_DIR_PATH ++ "/door_inner_light.glb",
});

pub const GpuMeshes = std.EnumArray(ModelType, gpu.Mesh);
pub const Materials = std.EnumArray(ModelType, Mesh.Material);
pub const Meshes = std.EnumArray(ModelType, Mesh);
pub const AABBs = std.EnumArray(ModelType, physics.Rectangle);

pub const DEFAULT_SOUNDTRACKS_DIR_PATH = "resources/soundtracks";
pub const SoundtrackType = enum {
    Background,
    Door,
    Success,
    Error,
    BoxPickup,
    BoxPutDown,
    Footstep0,
    Footstep1,
    Footstep2,
    Footstep3,
    Footstep4,
};
const SoundtrackPathsType = std.EnumArray(SoundtrackType, [:0]const u8);
const SOUNDTRACK_PATHS = SoundtrackPathsType.init(.{
    .Background = DEFAULT_SOUNDTRACKS_DIR_PATH ++ "/background.ogg",
    .Door = DEFAULT_SOUNDTRACKS_DIR_PATH ++ "/door.ogg",
    .Success = DEFAULT_SOUNDTRACKS_DIR_PATH ++ "/success.ogg",
    .Error = DEFAULT_SOUNDTRACKS_DIR_PATH ++ "/error.ogg",
    .BoxPickup = DEFAULT_SOUNDTRACKS_DIR_PATH ++ "/impactSoft_medium_001.ogg",
    .BoxPutDown = DEFAULT_SOUNDTRACKS_DIR_PATH ++ "/impactSoft_heavy_001.ogg",
    .Footstep0 = DEFAULT_SOUNDTRACKS_DIR_PATH ++ "/footstep_concrete_000.ogg",
    .Footstep1 = DEFAULT_SOUNDTRACKS_DIR_PATH ++ "/footstep_concrete_001.ogg",
    .Footstep2 = DEFAULT_SOUNDTRACKS_DIR_PATH ++ "/footstep_concrete_002.ogg",
    .Footstep3 = DEFAULT_SOUNDTRACKS_DIR_PATH ++ "/footstep_concrete_003.ogg",
    .Footstep4 = DEFAULT_SOUNDTRACKS_DIR_PATH ++ "/footstep_concrete_004.ogg",
});
pub const Soundtracks = std.EnumArray(SoundtrackType, Audio.Soundtrack);

pub const DEFAULT_TEXTURES_DIR_PATH = "resources/textures";
pub const TextureType = enum {
    SpeakerIcon,
};
const TexturePathsType = std.EnumArray(TextureType, [:0]const u8);
const TEXTURE_PATHS = TexturePathsType.init(.{
    .SpeakerIcon = DEFAULT_TEXTURES_DIR_PATH ++ "/speaker.png",
});
pub const GpuTextures = std.EnumArray(TextureType, gpu.Texture);

var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
var scratch: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
pub var gpu_meshes: GpuMeshes = undefined;
pub var gpu_textures: GpuTextures = undefined;
pub var materials: Materials = undefined;
pub var meshes: Meshes = undefined;
pub var aabbs: AABBs = undefined;
pub var soundtracks: Soundtracks = undefined;

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

    for (std.enums.values(ModelType)) |v| {
        aabbs.getPtr(v).* = calculate_aabb(meshes.getPtrConst(v));
    }

    for (0..SoundtrackPathsType.len) |i| {
        const soundtrack_type = SoundtrackPathsType.Indexer.keyForIndex(i);
        const path = SOUNDTRACK_PATHS.values[i];

        load_soundtrack(path, arena_alloc, soundtrack_type) catch |e| {
            log.panic(@src(), "Error loading soundtrack from path: {s}: {}", .{ path, e });
        };
    }

    for (0..TexturePathsType.len) |i| {
        const texture_type = TexturePathsType.Indexer.keyForIndex(i);
        const path = TEXTURE_PATHS.values[i];

        load_texture(path, texture_type) catch |e| {
            log.panic(@src(), "Error loading texture from path: {s}: {}", .{ path, e });
        };
    }
}

pub fn calculate_aabb(mesh: *const Mesh) physics.Rectangle {
    var min_x: f32 = 0.0;
    var max_x: f32 = 0.0;
    var min_y: f32 = 0.0;
    var max_y: f32 = 0.0;

    for (mesh.vertices) |*v| {
        min_x = @min(min_x, v.position.x);
        max_x = @max(max_x, v.position.x);
        min_y = @min(min_y, v.position.y);
        max_y = @max(max_y, v.position.y);
    }
    const width = max_x - min_x;
    const height = max_y - min_y;
    return .{ .size = .{ .x = width, .y = height } };
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
        .emissive_strength = material.emissive_strength.emissive_strength,
    };
    log.info(@src(), "Mesh material: {any}", .{materials.getPtr(model_type).*});

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

pub fn load_soundtrack(
    path: [:0]const u8,
    assets_alloc: Allocator,
    soundtrack_type: SoundtrackType,
) !void {
    log.info(
        @src(),
        "Loading soundtrack of type {any} from path: {s}",
        .{ soundtrack_type, path },
    );

    const file_mem = try Platform.FileMem.init(path);
    defer file_mem.deinit();

    var err: i32 = undefined;
    const vorbis = stb.stb_vorbis_open_memory(
        file_mem.mem.ptr,
        @intCast(file_mem.mem.len),
        &err,
        null,
    );
    log.assert(
        @src(),
        vorbis != null,
        "Cannot open vorbis memory: {} for the file path: {s}",
        .{ err, path },
    );
    defer stb.stb_vorbis_close(vorbis);

    const samples_per_channel = stb.stb_vorbis_stream_length_in_samples(vorbis);
    const samples = samples_per_channel * Audio.CHANNELS;
    const soundtrack_data = try assets_alloc.alignedAlloc(u16, 64, samples);

    const info = stb.stb_vorbis_get_info(vorbis);
    const n = stb.stb_vorbis_get_samples_short_interleaved(
        vorbis,
        info.channels,
        @ptrCast(soundtrack_data.ptr),
        @intCast(samples),
    );
    log.assert(
        @src(),
        n * 2 == samples,
        "Did not load the whole soundtrack in memory. Only loaded {d} out of {d}",
        .{ n * 2, samples },
    );

    log.info(
        @src(),
        "Loaded OGG file from {s} with specs: freq: {}, channels: {}, total samples: {}",
        .{
            path,
            info.sample_rate,
            info.channels,
            samples,
        },
    );

    const soundtrack = soundtracks.getPtr(soundtrack_type);
    soundtrack.data = @ptrCast(soundtrack_data);
}

pub fn load_texture(
    path: [:0]const u8,
    texture_type: TextureType,
) !void {
    log.info(
        @src(),
        "Loading textures of type {any} from path: {s}",
        .{ texture_type, path },
    );

    const file_mem = try Platform.FileMem.init(path);
    defer file_mem.deinit();

    var x: i32 = undefined;
    var y: i32 = undefined;
    var c: i32 = undefined;
    if (@as(?[*]u8, stb.stbi_load_from_memory(
        file_mem.mem.ptr,
        @intCast(file_mem.mem.len),
        &x,
        &y,
        &c,
        stb.STBI_rgb_alpha,
    ))) |image| {
        defer stb.stbi_image_free(image);

        const width: u32 = @intCast(x);
        const height: u32 = @intCast(y);
        const channels: u32 = @intCast(c);

        log.assert(
            @src(),
            channels == 4,
            "Cannot load texture with {} channels. Need 4.",
            .{channels},
        );

        const texture = gpu_textures.getPtr(texture_type);
        texture.* = .init(image, width, height);
        return;
    }
    return error.CannotLoadTexture;
}
