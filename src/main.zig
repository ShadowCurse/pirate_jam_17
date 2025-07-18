const std = @import("std");
const builtin = @import("builtin");

const log = @import("log.zig");

pub const log_options = log.Options{
    .level = .Info,
    .colors = builtin.target.os.tag != .emscripten,
};

pub fn main() void {}
