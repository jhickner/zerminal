const std = @import("std");

pub const clear = @import("clear.zig");
pub const cursor = @import("cursor.zig");
pub const format = @import("format.zig");
pub const events = @import("events.zig");
pub const resize = @import("resize.zig");
pub const style = @import("style.zig");
pub const terminal = @import("terminal.zig");

pub usingnamespace @import("clear.zig");
pub usingnamespace @import("cursor.zig");
pub usingnamespace @import("format.zig");
pub usingnamespace @import("events.zig");
pub usingnamespace @import("resize.zig");
pub usingnamespace @import("style.zig");
pub usingnamespace @import("terminal.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
