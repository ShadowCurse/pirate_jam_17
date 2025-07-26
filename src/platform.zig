const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");
const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");
const gl = @import("bindings/gl.zig");
const cimgui = @import("bindings/cimgui.zig");
const math = @import("math.zig");

pub const WINDOW_WIDTH = 1280;
pub const WINDOW_HEIGHT = 720;

pub var window: *sdl.SDL_Window = undefined;
pub var imgui_io: *cimgui.ImGuiIO = undefined;
pub var stop: bool = false;

pub const MAX_EVENTS = 32;
var sdl_events_buffer: [MAX_EVENTS]sdl.SDL_Event = undefined;
pub var sdl_events: []const sdl.SDL_Event = &.{};

pub var mouse_position: math.Vec2 = .{};

pub fn init() void {
    if (options.no_sound)
        sdl.assert(@src(), sdl.SDL_Init(sdl.SDL_INIT_VIDEO))
    else
        sdl.assert(@src(), sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_AUDIO));

    // for 24bit depth
    sdl.assert(@src(), sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DEPTH_SIZE, 24));

    // For desktops use GL4
    if (builtin.target.os.tag != .emscripten)
        _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 4);

    window = sdl.SDL_CreateWindow(
        "pirate_jam_17",
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        sdl.SDL_WINDOW_OPENGL,
    ) orelse {
        log.assert(@src(), false, "Cannot create a window: {s}", .{sdl.SDL_GetError()});
        unreachable;
    };

    sdl.assert(@src(), sdl.SDL_SetWindowResizable(window, false));

    const context = sdl.SDL_GL_CreateContext(window);
    sdl.assert(@src(), sdl.SDL_GL_MakeCurrent(window, context));

    log.info(@src(), "Vendor graphic card: {s}", .{gl.glGetString(gl.GL_VENDOR)});
    log.info(@src(), "Renderer: {s}", .{gl.glGetString(gl.GL_RENDERER)});
    log.info(@src(), "Version GL: {s}", .{gl.glGetString(gl.GL_VERSION)});
    log.info(@src(), "Version GLSL: {s}", .{gl.glGetString(gl.GL_SHADING_LANGUAGE_VERSION)});

    sdl.assert(@src(), sdl.SDL_ShowWindow(window));

    _ = cimgui.igCreateContext(null);
    _ = cimgui.ImGui_ImplSDL3_InitForOpenGL(@ptrCast(window), context);
    const cimgli_opengl_version = "#version 300 es";
    _ = cimgui.ImGui_ImplOpenGL3_Init(cimgli_opengl_version);
    imgui_io = @ptrCast(cimgui.igGetIO_Nil());
    // Otherwise imgui will force cursor to be visible
    imgui_io.ConfigFlags |= cimgui.ImGuiConfigFlags_NoMouseCursorChange;

    gl.glViewport(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT);

    if (builtin.target.os.tag != .emscripten)
        gl.glClipControl(gl.GL_LOWER_LEFT, gl.GL_ZERO_TO_ONE);

    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glEnable(gl.GL_BLEND);
    gl.glEnable(gl.GL_CULL_FACE);
    gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
}

pub fn get_events() void {
    var num_events: u32 = 0;
    while (num_events < sdl_events_buffer.len and
        sdl.SDL_PollEvent(&sdl_events_buffer[num_events]))
        num_events += 1;
    sdl_events = sdl_events_buffer[0..@intCast(num_events)];
}

pub fn get_mouse_pos() void {
    _ = sdl.SDL_GetMouseState(&mouse_position.x, &mouse_position.y);
}

pub fn process_events() void {
    for (sdl_events) |*sdl_event| {
        _ = cimgui.ImGui_ImplSDL3_ProcessEvent(@ptrCast(sdl_event));
        switch (sdl_event.type) {
            sdl.SDL_EVENT_QUIT => {
                stop = true;
            },
            else => {},
        }
    }
}

pub fn imgui_wants_to_handle_events() bool {
    return imgui_io.WantCaptureMouse or
        imgui_io.WantCaptureKeyboard or
        imgui_io.WantTextInput;
}

pub fn present() void {
    sdl.assert(@src(), sdl.SDL_GL_SwapWindow(window));
}

pub fn hide_mouse(enable: bool) void {
    // On web this works if canvas is at 0,0, but on itch.io it is not,
    // so people will have to deal with non relative mode there.
    if (builtin.os.tag != .emscripten)
        _ = sdl.SDL_SetWindowRelativeMouseMode(window, enable);
    if (enable) {
        if (!sdl.SDL_HideCursor())
            log.err(@src(), "Cannot hide cursor: {s}", .{sdl.SDL_GetError()});
    } else {
        if (!sdl.SDL_ShowCursor())
            log.err(@src(), "Cannot show cursor: {s}", .{sdl.SDL_GetError()});
    }
}

pub fn mouse_clip() math.Vec2 {
    return .{
        .x = (mouse_position.x / WINDOW_WIDTH * 2.0) - 1.0,
        .y = -((mouse_position.y / WINDOW_HEIGHT * 2.0) - 1.0),
    };
}

pub const FileMem = struct {
    mem: []align(std.heap.page_size_min) u8,

    const Self = @This();

    pub fn init(path: []const u8) !Self {
        const fd = try std.posix.open(path, .{ .ACCMODE = .RDONLY }, 0);
        defer std.posix.close(fd);

        const stat = try std.posix.fstat(fd);
        const mem = try std.posix.mmap(
            null,
            @intCast(stat.size),
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .PRIVATE },
            fd,
            0,
        );
        return .{
            .mem = mem,
        };
    }

    pub fn deinit(self: Self) void {
        std.posix.munmap(self.mem);
    }
};
