const std = @import("std");
const builtin = @import("builtin");

const log = @import("log.zig");
const gl = @import("bindings/gl.zig");
const cimgui = @import("bindings/cimgui.zig");

const Platform = @import("platform.zig");

pub const log_options = log.Options{
    .level = .Info,
    .colors = builtin.target.os.tag != .emscripten,
};

pub fn main() void {
    Platform.init();

    while (!Platform.stop) {
        Platform.get_events();
        Platform.get_mouse_pos();
        Platform.process_events();

        gl.glClearDepth(0.0);
        gl.glClearColor(0.0, 0.0, 0.0, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

        {
            cimgui.ImGui_ImplOpenGL3_NewFrame();
            cimgui.ImGui_ImplSDL3_NewFrame();
            cimgui.igNewFrame();
            defer cimgui.igRender();
            var a: bool = true;
            _ = cimgui.igShowDemoWindow(&a);
        }
        const imgui_data = cimgui.igGetDrawData();
        cimgui.ImGui_ImplOpenGL3_RenderDrawData(imgui_data);

        Platform.present();
    }
}
