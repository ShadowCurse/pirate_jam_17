const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var env_map = try std.process.getEnvMap(b.allocator);
    defer env_map.deinit();

    const no_sound = b.option(bool, "no_sound", "Compile without sound") orelse false;
    const shipping = b.option(bool, "shipping", "Compile for shipping") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "no_sound", no_sound);
    options.addOption(bool, "shipping", shipping);

    const c_lib = build_c_libc(b, target, &env_map);

    const artifact = if (target.result.os.tag == .emscripten) blk: {
        const cache_include = std.fs.path.join(
            b.allocator,
            &.{
                b.sysroot.?,
                "cache",
                "sysroot",
                "include",
            },
        ) catch @panic("Out of memory");
        defer b.allocator.free(cache_include);
        const cache_path = std.Build.LazyPath{ .cwd_relative = cache_include };

        c_lib.addIncludePath(cache_path);
        b.installArtifact(c_lib);

        const lib = b.addStaticLibrary(.{
            .name = "wasm",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        lib.addIncludePath(cache_path);
        break :blk lib;
    } else blk: {
        const exe = b.addExecutable(.{
            .name = "pirate_jam_17",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // does not work with audio @Vector usage
            // .use_llvm = false,
        });
        exe.linkSystemLibrary("SDL3");
        exe.linkSystemLibrary("GL");
        break :blk exe;
    };
    artifact.root_module.addOptions("options", options);
    artifact.addIncludePath(.{ .cwd_relative = env_map.get("SDL3_INCLUDE_PATH").? });
    artifact.addIncludePath(.{ .cwd_relative = env_map.get("LIBGL_INCLUDE_PATH").? });
    artifact.addIncludePath(b.path("thirdparty/cimgui"));
    artifact.addIncludePath(b.path("thirdparty/cgltf/"));
    artifact.addIncludePath(b.path("thirdparty/stb/"));
    // artifact.addCSourceFile(.{ .file = b.path("thirdparty/cgltf/cgltf.c") });
    // artifact.addCSourceFile(.{ .file = b.path("thirdparty/stb/stb.c") });
    artifact.linkLibrary(c_lib);
    artifact.linkLibrary(c_lib);
    artifact.linkLibC();
    b.installArtifact(artifact);

    if (target.result.os.tag != .emscripten) {
        const run_cmd = b.addRunArtifact(artifact);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.option(bool, "X11", "Use X11 backend") == null) {
            run_cmd.setEnvironmentVariable("SDL_VIDEODRIVER", "wayland");
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }
}

fn build_c_libc(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    env_map: *const std.process.EnvMap,
) *std.Build.Step.Compile {
    const c_lib = b.addStaticLibrary(.{
        .name = "cimgui",
        .target = target,
        .optimize = .ReleaseFast,
    });
    c_lib.addCSourceFiles(.{
        .files = &.{
            "thirdparty/cimgui/cimgui.cpp",
            "thirdparty/cimgui/imgui/imgui.cpp",
            "thirdparty/cimgui/imgui/imgui_demo.cpp",
            "thirdparty/cimgui/imgui/imgui_draw.cpp",
            "thirdparty/cimgui/imgui/imgui_tables.cpp",
            "thirdparty/cimgui/imgui/imgui_widgets.cpp",
            "thirdparty/cimgui/imgui/backends/imgui_impl_sdl3.cpp",
            "thirdparty/cimgui/imgui/backends/imgui_impl_opengl3.cpp",
            "thirdparty/cgltf/cgltf.c",
            "thirdparty/stb/stb.c",
        },
    });
    c_lib.addIncludePath(b.path("thirdparty/stb/"));
    c_lib.addIncludePath(b.path("thirdparty/cgltf/"));
    c_lib.addIncludePath(b.path("thirdparty/cimgui"));
    c_lib.addIncludePath(b.path("thirdparty/cimgui/imgui"));
    c_lib.addIncludePath(b.path("thirdparty/cimgui/imgui/backends"));
    c_lib.addIncludePath(.{ .cwd_relative = env_map.get("SDL3_INCLUDE_PATH").? });
    c_lib.linkLibCpp();
    return c_lib;
}
