const std = @import("std");
const posix = std.posix;

/// This internal flag tracks whether a resize event was received by
/// the signal handler (if enabled).
var resize_occurred: bool = false;

export fn winch_signal_cb(_: c_int, _: *const posix.siginfo_t, _: ?*const anyopaque) callconv(.C) void {
    resize_occurred = true;
}

/// Non-blocking. Returns true if a resize occured since the last
/// time this function was called.
/// Requires first calling `enableResizeEvents`.
pub fn pollResize() !?Size {
    if (resize_occurred) {
        resize_occurred = false;
        return try getSize();
    }
    return null;
}

pub const Size = extern struct {
    width: u16 = 0,
    height: u16 = 0,
};

/// Enable tracking of resize events. Call `checkResize` to check
/// if a resize has occurred.
pub fn enableResizeEvents() !void {
    try posix.sigaction(posix.SIG.WINCH, &posix.Sigaction{
        .handler = .{ .sigaction = winch_signal_cb },
        .mask = posix.empty_sigset,
        .flags = 0,
    }, null);
}

/// Get terminal size.
pub fn getSize() !Size {
    var wsz: posix.winsize = undefined;
    const rv = posix.system.ioctl(0, posix.T.IOCGWINSZ, @intFromPtr(&wsz));
    const err = posix.errno(rv);
    if (rv != 0) {
        return posix.unexpectedErrno(err);
    }
    return Size{ .width = wsz.ws_col, .height = wsz.ws_row };
}
