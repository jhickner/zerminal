const std = @import("std");
const posix = std.posix;
const csi = "\x1B[";

pub fn enterAlternateScreen(writer: anytype) !void {
    try writer.writeAll(csi ++ "?1049h");
}

pub fn leaveAlternateScreen(writer: anytype) !void {
    try writer.writeAll(csi ++ "?1049l");
}

pub fn beginSynchronizedUpdate(writer: anytype) !void {
    try writer.writeAll(csi ++ "?2026h");
}

pub fn endSynchronizedUpdate(writer: anytype) !void {
    try writer.writeAll(csi ++ "?2026l");
}

pub fn enableMouseCapture(writer: anytype) !void {
    // Normal tracking: Send mouse X & Y on button press and release
    try writer.writeAll(csi ++ "?1000h");
    // Button-event tracking: Report button motion events (dragging)
    try writer.writeAll(csi ++ "?1002h");
    // Any-event tracking: Report all motion events
    try writer.writeAll(csi ++ "?1003h");
    // RXVT mouse mode: Allows mouse coordinates of >223
    try writer.writeAll(csi ++ "?1015h");
    // SGR mouse mode: Allows mouse coordinates of >223, preferred over RXVT mode
    try writer.writeAll(csi ++ "?1006h");
}

pub fn disableMouseCapture(writer: anytype) !void {
    try writer.writeAll(csi ++ "?1006l");
    try writer.writeAll(csi ++ "?1015l");
    try writer.writeAll(csi ++ "?1003l");
    try writer.writeAll(csi ++ "?1002l");
    try writer.writeAll(csi ++ "?1000l");
}

pub fn enableFocusChange(writer: anytype) !void {
    try writer.writeAll(csi ++ "?1004h");
}

pub fn disableFocusChange(writer: anytype) !void {
    try writer.writeAll(csi ++ "?1004l");
}

pub fn getKeyboardEnhancementFlags(writer: anytype) !void {
    try writer.writeAll(csi ++ "?u");
}

pub const KeyboardEnhancementFlags = packed struct(u8) {
    disambiguate_escape_codes: bool = false,
    report_event_types: bool = false,
    report_alternate_keys: bool = false,
    report_all_keys_as_escape_codes: bool = false,
    report_associated_text: bool = false,
    padding: u3 = 0,

    pub fn format(
        self: KeyboardEnhancementFlags,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.writeAll("Keyboard Enhancement Flags: ");
        if (self.disambiguate_escape_codes) try writer.writeAll(" +DISAMBIGUATE_ESCAPE_CODES");
        if (self.report_event_types) try writer.writeAll(" +REPORT_EVENT_TYPES");
        if (self.report_alternate_keys) try writer.writeAll(" +REPORT_ALTERNATE_KEYS");
        if (self.report_all_keys_as_escape_codes) try writer.writeAll(" +REPORT_ALL_KEYS_AS_ESCAPE_CODES");
        if (self.report_associated_text) try writer.writeAll(" +REPORT_ASSOCIATED_TEXT");
    }
};

pub fn pushKeyboardEnhancementFlags(writer: anytype, flags: KeyboardEnhancementFlags) !void {
    const i: u8 = std.mem.asBytes(&flags)[0];
    try writer.print(csi ++ ">{d}u", .{i});
}

pub fn popKeyboardEnhancementFlags(writer: anytype) !void {
    try writer.writeAll(csi ++ "<1u");
}

pub const BlockingMode = enum {
    BLOCKING,
    NON_BLOCKING,
};

pub fn enableRawMode(blocking_mode: BlockingMode) !void {
    var state = try posix.tcgetattr(posix.STDIN_FILENO);

    state.lflag.ECHO = false;
    state.lflag.ICANON = false;
    state.lflag.ISIG = false;
    state.lflag.IEXTEN = false;
    state.lflag.ECHONL = false;

    state.iflag.IXON = false;
    state.iflag.BRKINT = false;
    state.iflag.INPCK = false;
    state.iflag.ISTRIP = false;
    state.iflag.IGNBRK = false;
    state.iflag.INLCR = false;
    state.iflag.PARMRK = false;

    //state.oflag.OPOST = false;

    state.cflag.CSIZE = .CS8;
    state.cflag.PARENB = false;

    switch (blocking_mode) {
        .NON_BLOCKING => {
            state.cc[@intFromEnum(posix.V.TIME)] = 0;
            state.cc[@intFromEnum(posix.V.MIN)] = 0;
        },
        .BLOCKING => {
            state.cc[@intFromEnum(posix.V.TIME)] = 0;
            state.cc[@intFromEnum(posix.V.MIN)] = 1;
        },
    }

    try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, state);
}

pub fn disableRawMode() !void {
    var state = try posix.tcgetattr(posix.STDIN_FILENO);

    state.lflag.ECHO = true;
    state.lflag.ICANON = true;
    state.lflag.ISIG = true;
    state.lflag.IEXTEN = true;

    try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, state);
}

pub fn getTermios() !posix.termios {
    return posix.tcgetattr(posix.STDIN_FILENO);
}

pub fn setTermios(v: posix.termios) !void {
    try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, v);
}
