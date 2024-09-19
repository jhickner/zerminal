const std = @import("std");
const posix = std.posix;
const resize = @import("resize.zig");
const KeyboardEnhancementFlags = @import("terminal.zig").KeyboardEnhancementFlags;
const Size = resize.Size;

pub const Event = union(enum) {
    key: Key,
    resize: Size,
    cursor_pos: CursorPos,
    keyboard_enhancement_flags: KeyboardEnhancementFlags,
    focus_gained,
    focus_lost,
    mouse: MouseEvent,

    pub fn format(
        self: Event,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .key => |key| {
                try writer.print("Key: ", .{});
                switch (key.id) {
                    .char => |c| try writer.print("'{u}'", .{c}),
                    .f => |f| try writer.print("'F{d}'", .{f}),
                    else => try writer.print("{s}", .{@tagName(key.id)}),
                }
                try writer.print("{}", .{key.modifiers});
                try writer.print(" {s}", .{@tagName(key.kind)});
            },
            .resize => |size| try writer.print(
                "Resize: {}x{}",
                .{ size.width, size.height },
            ),
            .cursor_pos => |pos| try writer.print(
                "Cursor Pos: {}x{}",
                .{ pos.x, pos.y },
            ),
            .focus_gained => try writer.writeAll("Focus Gained"),
            .focus_lost => try writer.writeAll("Focus Lost"),
            .keyboard_enhancement_flags => |flags| try writer.print("{}", .{flags}),
            .mouse => |mouse| try writer.print(
                "Mouse: {s} at {}x{} {}",
                .{ @tagName(mouse.kind), mouse.x, mouse.y, mouse.modifiers },
            ),
        }
    }
};

pub const CursorPos = extern struct {
    x: u16,
    y: u16,
};

pub const KeyId = union(enum) {
    char: u21,
    f: u8,

    // misc keys
    backspace,
    esc,
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    end,
    enter,
    home,
    tab,
    backtab,
    page_up,
    page_down,
    insert,
    delete,
    caps_lock,
    num_lock,
    scroll_lock,
    print_screen,
    menu,
    keypad_begin,

    // media keys
    play,
    pause,
    play_pause,
    reverse,
    stop,
    fast_forward,
    rewind,
    track_next,
    track_previous,
    record,
    lower_volume,
    raise_volume,
    mute_volume,

    // modifiers
    left_shift,
    left_control,
    left_alt,
    left_super,
    left_hyper,
    left_meta,
    right_shift,
    right_control,
    right_alt,
    right_super,
    right_hyper,
    right_meta,
    iso_level_3_shift,
    iso_level_5_shift,

    pub fn char(v: u21) KeyId {
        return KeyId{ .char = v };
    }

    pub fn f(v: u8) KeyId {
        return KeyId{ .f = v };
    }
};

test "KeyId" {
    std.debug.print("{}\n", .{KeyId{ .f = 1 }});
    const x: KeyId = .delete;
    std.debug.assert(x == .delete);
}

pub const Key = struct {
    id: KeyId,
    modifiers: Modifiers = Modifiers{},
    kind: KeyEventKind = .press,
};

pub const Modifiers = packed struct(u8) {
    shift: bool = false,
    alt: bool = false,
    control: bool = false,
    super: bool = false,
    hyper: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,

    pub fn format(
        self: Modifiers,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (self.shift) try writer.writeAll(" +SHIFT");
        if (self.alt) try writer.writeAll(" +ALT");
        if (self.control) try writer.writeAll(" +CTRL");
        if (self.super) try writer.writeAll(" +SUPER");
        if (self.hyper) try writer.writeAll(" +HYPER");
        if (self.meta) try writer.writeAll(" +META");
        if (self.num_lock) try writer.writeAll(" +NUM_LOCK");
        if (self.caps_lock) try writer.writeAll(" +CAPS_LOCK");
    }
};

pub const KeyEventKind = enum(u8) {
    press = 1,
    repeat = 2,
    release = 3,

    pub fn parse(v: u8) KeyEventKind {
        if (v >= 1 and v <= 3) {
            return @enumFromInt(v);
        } else {
            return .press;
        }
    }
};

pub fn keyId(comptime id: KeyId) Event {
    return Event{ .key = Key{ .id = id } };
}

pub fn keyChar(comptime c: u32) Event {
    return Event{
        .key = Key{ .id = .{ .char = c } },
    };
}

pub const MouseEvent = struct {
    kind: MouseEventKind,
    x: u16,
    y: u16,
    modifiers: Modifiers,
};

pub const MouseButton = enum {
    left,
    right,
    middle,
};

pub const MouseEventKind = union(enum) {
    down: MouseButton,
    up: MouseButton,
    drag: MouseButton,
    moved,
    scroll_down,
    scroll_up,
    scroll_left,
    scroll_right,
};

// NOTE:
// https://sw.kovidgoyal.net/kitty/keyboard-protocol/
// http://defindit.com/ascii.html

pub const EventReader = struct {
    buffer: std.ArrayList(u8),
    events: std.fifo.LinearFifo(Event, .{ .Static = 100 }),
    stdin_buffer: [1024]u8 = undefined,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !EventReader {
        return EventReader{
            .buffer = try std.ArrayList(u8).initCapacity(allocator, 1024),
            .events = std.fifo.LinearFifo(Event, .{ .Static = 100 }).init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.events.deinit();
    }

    pub fn readStdin(self: *Self, timeout_ms: i32) !?Event {
        if (self.events.readItem()) |evt| {
            return evt;
        }

        if (try resize.pollResize()) |sz| {
            return Event{ .resize = sz };
        }

        if (try pollStdin(timeout_ms) != 0) {
            var reader = std.io.getStdIn().reader();
            const count = try reader.read(&self.stdin_buffer);
            if (count == 0) return null;
            try self.parseBuffer(self.stdin_buffer[0..count], false);
            return self.events.readItem();
        }

        return null;
    }

    pub fn parseBuffer(self: *Self, buffer: []u8, raise_errors: bool) !void {
        for (0.., buffer) |idx, byte| {
            const input_available = idx + 1 < buffer.len;
            try self.buffer.append(byte);
            const oevt = parse_event(self.buffer.items, input_available) catch |err| {
                // Parsing returned an error. More bytes won't help.
                // Clear the current internal buffer and continue.
                self.buffer.clearRetainingCapacity();
                if (raise_errors) {
                    return err;
                } else {
                    std.debug.print("parse error: {}\n", .{err});
                    continue;
                }
            };
            if (oevt) |evt| {
                // Parsing succeeded. Clear the current internal buffer, write
                // the parsed item, and continue.
                try self.events.writeItem(evt);
                self.buffer.clearRetainingCapacity();
            } else {
                // Parsing returned null, indicating that it might succeed in
                // the future if given more bytes. Continue.
                if (!input_available) {
                    self.buffer.clearRetainingCapacity();
                    std.debug.print("parse error, no more bytes\n", .{});
                    if (raise_errors) return error.InvalidFormat;
                }
            }
        }
    }
};

fn pollStdin(timeout_ms: i32) !usize {
    var fds = [1]posix.pollfd{posix.pollfd{
        .fd = posix.STDIN_FILENO,
        .events = posix.POLL.IN,
        .revents = undefined,
    }};
    return try posix.poll(&fds, timeout_ms);
}

// https://github.com/crossterm-rs/crossterm/blob/master/src/event/sys/unix/parse.rs

fn parse_event(buffer: []u8, input_available: bool) !?Event {
    //std.debug.print("parsing buffer: {x}, {}\n", .{ buffer, input_available });
    if (buffer.len == 0) return null;

    return switch (buffer[0]) {
        '\x1b' => if (buffer.len == 1)
            if (input_available) null else keyId(.esc)
        else switch (buffer[1]) {
            'O' => if (buffer.len == 2) null else switch (buffer[2]) {
                'P' => keyId(KeyId.f(1)),
                'Q' => keyId(KeyId.f(2)),
                'R' => keyId(KeyId.f(3)),
                'S' => keyId(KeyId.f(4)),
                else => error.InvalidCSI,
            },
            '[' => try parse_csi(buffer, input_available),
            else => null,
        },
        '\r', '\n' => keyId(.enter),
        '\t' => keyId(.tab),
        '\x7f' => keyId(.backspace),
        // Ctrl-A - Ctrl-Z
        '\x01'...'\x08', '\x0b'...'\x0c', '\x0e'...'\x1a' => Event{
            .key = Key{
                .id = KeyId.char(buffer[0] - 0x1 + 'a'),
                .modifiers = .{ .control = true },
            },
        },
        // ^\, ^], ^^, ^_
        '\x1c'...'\x1f' => Event{
            .key = Key{
                .id = KeyId.char(buffer[0] - 0x1c + '4'),
                .modifiers = .{ .control = true },
            },
        },
        else => Event{
            .key = Key{
                // TODO: support full utf8 chars
                .id = KeyId.char(buffer[0]),
            },
        },
    };
}

// Called when buffer begins with \x1b[
fn parse_csi(buffer: []u8, input_available: bool) !?Event {
    if (buffer.len == 2) {
        return null;
    }

    const evt = switch (buffer[2]) {
        'D' => keyId(.arrow_left),
        'C' => keyId(.arrow_right),
        'A' => keyId(.arrow_up),
        'B' => keyId(.arrow_down),
        'H' => keyId(.home),
        'F' => keyId(.end),
        'M' => try parse_csi_normal_mouse(buffer),
        '<' => try parse_csi_sgr_mouse(buffer),
        'I' => .focus_gained,
        'O' => .focus_lost,

        // NOTE: P, Q, S needed for compatibility with kitty
        // in the case where no modifiers are present
        'P' => keyId(KeyId.f(1)),
        'Q' => keyId(KeyId.f(2)),
        'S' => keyId(KeyId.f(4)),

        '?' => switch (buffer[buffer.len - 1]) {
            'u' => parse_csi_keyboard_enhancement_flags(buffer),
            else => null,
        },
        '0'...'9' => blk: {
            if (buffer.len == 3) {
                break :blk null;
            } else {
                const last_byte = buffer[buffer.len - 1];
                break :blk switch (last_byte) {
                    // 64-126 are valid values for the final byte of a CSI.
                    64...126 => switch (last_byte) {
                        'M' => try parse_csi_rxvt_mouse(buffer),
                        '~' => parse_csi_special_key(buffer),
                        'u' => parse_csi_u_encoded(buffer),
                        'R' => try parse_csi_cursor_position(buffer),
                        else => try parse_csi_modifier(buffer),
                    },
                    // Otherwise keep reading.
                    else => if (input_available) null else return error.InvalidCSI,
                };
            }
        },
        else => return error.InvalidCSI,
    };

    return evt;
}

fn parse_csi_normal_mouse(buffer: []u8) !?Event {
    if (buffer.len < 6) return null;

    const cb = buffer[3] -| 32;
    const cb_parsed = try parse_cb(cb);

    const x = buffer[4] -| 32;
    const y = buffer[5] -| 32;

    return Event{
        .mouse = MouseEvent{
            .kind = cb_parsed.kind,
            .x = x,
            .y = y,
            .modifiers = cb_parsed.modifiers,
        },
    };
}

fn parse_csi_rxvt_mouse(buffer: []u8) !?Event {
    // ESC [ cb<u8> ; x<u16> ; y<u16> ; M

    const raw = buffer[2 .. buffer.len - 1];
    var iter = std.mem.splitScalar(u8, raw, ';');

    const cb = std.fmt.parseInt(u8, iter.first(), 10) catch return error.InvalidCSIRXVT;
    const cb_parsed = try parse_cb(cb);

    const x_str = iter.next() orelse return error.InvalidCSIRXVT;
    const x = std.fmt.parseInt(u16, x_str, 10) catch return error.InvalidCSIRXVT;

    const y_str = iter.next() orelse return error.InvalidCSIRXVT;
    const y = std.fmt.parseInt(u16, y_str, 10) catch return error.InvalidCSIRXVT;

    return Event{
        .mouse = MouseEvent{
            .kind = cb_parsed.kind,
            .modifiers = cb_parsed.modifiers,
            .x = x -| 1,
            .y = y -| 1,
        },
    };
}

fn parse_csi_sgr_mouse(buffer: []u8) !?Event {
    // ESC [ cb<u8> ; x<u16> ; y<u16> (;) (M or m)
    const last_byte = buffer[buffer.len - 1];
    if (last_byte != 'm' and last_byte != 'M') return null;

    const raw = buffer[3 .. buffer.len - 1];
    var iter = std.mem.splitScalar(u8, raw, ';');

    const cb = std.fmt.parseInt(u8, iter.first(), 10) catch return error.InvalidCSISGR;
    const cb_parsed = try parse_cb(cb);

    const x_str = iter.next() orelse return error.InvalidCSISGR;
    const x = std.fmt.parseInt(u16, x_str, 10) catch return error.InvalidCSISGR;

    const y_str = iter.next() orelse return error.InvalidCSISGR;
    const y = std.fmt.parseInt(u16, y_str, 10) catch return error.InvalidCSISGR;

    const kind: MouseEventKind = switch (last_byte) {
        'm' => switch (cb_parsed.kind) {
            .down => |button| .{ .up = button },
            else => cb_parsed.kind,
        },
        else => cb_parsed.kind,
    };

    return Event{
        .mouse = MouseEvent{
            .kind = kind,
            .modifiers = cb_parsed.modifiers,
            .x = x -| 1,
            .y = y -| 1,
        },
    };
}

fn parse_cb(cb: u8) !struct { kind: MouseEventKind, modifiers: Modifiers } {
    const button_num = (cb & 0b0000_0011) | ((cb & 0b1100_0000) >> 4);
    const dragging = cb & 0b0010_0000 == 0b0010_00000;

    const kind: MouseEventKind = switch (dragging) {
        false => switch (button_num) {
            0 => .{ .down = .left },
            1 => .{ .down = .middle },
            2 => .{ .down = .right },
            3 => .{ .up = .left },
            4 => .scroll_up,
            5 => .scroll_down,
            6 => .scroll_left,
            7 => .scroll_right,
            else => return error.InvalidCB,
        },
        true => switch (button_num) {
            0 => .{ .drag = .left },
            1 => .{ .drag = .middle },
            2 => .{ .drag = .right },
            3, 4, 5 => .moved,
            else => return error.InvalidCB,
        },
    };

    var modifiers = Modifiers{};
    if (cb & 0b0000_0100 == 0b0000_0100) {
        modifiers.shift = true;
    }
    if (cb & 0b0000_1000 == 0b0000_1000) {
        modifiers.alt = true;
    }
    if (cb & 0b0001_0000 == 0b0001_0000) {
        modifiers.control = true;
    }

    return .{ .kind = kind, .modifiers = modifiers };
}

fn parse_csi_special_key(buffer: []u8) !?Event {
    const mods = buffer[2 .. buffer.len - 1];
    var iter = std.mem.splitScalar(u8, mods, ';');

    const key_code = std.fmt.parseInt(u8, iter.first(), 10) catch return error.InvalidCSISpecialKey;

    var modifiers = Modifiers{};
    var kind = KeyEventKind.press;

    if (iter.next()) |modifier_str| {
        var parts = std.mem.splitScalar(u8, modifier_str, ':');
        const modmask = std.fmt.parseInt(u8, parts.first(), 10) catch return error.InvalidCSISpecialKey;
        modifiers = @bitCast(modmask -| 1);

        if (parts.next()) |event_str| {
            const event_code = std.fmt.parseInt(u8, event_str, 10) catch return error.InvalidCSISpecialKey;
            kind = KeyEventKind.parse(event_code);
        }
    }

    const key_id: KeyId = switch (key_code) {
        1, 7 => .home,
        2 => .insert,
        3 => .delete,
        4, 8 => .end,
        5 => .page_up,
        6 => .page_down,
        11...15 => KeyId.f(key_code - 10),
        17...21 => KeyId.f(key_code - 11),
        23...26 => KeyId.f(key_code - 12),
        28...29 => KeyId.f(key_code - 15),
        31...34 => KeyId.f(key_code - 17),
        else => return error.InvalidCSISpecialKey,
    };

    const evt = Event{
        .key = Key{
            .id = key_id,
            .modifiers = modifiers,
            .kind = kind,
        },
    };

    return evt;
}

fn parse_csi_modifier(buffer: []u8) !?Event {
    if (buffer.len < 6) return null;
    const mods = buffer[2 .. buffer.len - 1];
    var iter = std.mem.splitScalar(u8, mods, ';');

    // discard key code
    _ = iter.first();

    const modifier_str = iter.next() orelse return error.InvalidCSIModifier;
    var parts = std.mem.splitScalar(u8, modifier_str, ':');
    const modmask = std.fmt.parseInt(u8, parts.first(), 10) catch return error.InvalidCSIModifier;

    var kind = KeyEventKind.press;
    if (parts.next()) |event_str| {
        const event_code = std.fmt.parseInt(u8, event_str, 10) catch return error.InvalidCSIModifier;
        kind = KeyEventKind.parse(event_code);
    }

    const key_code = buffer[buffer.len - 1];
    const key_id: KeyId = switch (key_code) {
        'A' => .arrow_up,
        'B' => .arrow_down,
        'C' => .arrow_right,
        'D' => .arrow_left,
        'F' => .end,
        'H' => .home,
        'P' => .{ .f = 1 },
        'Q' => .{ .f = 2 },
        'R' => .{ .f = 3 },
        'S' => .{ .f = 4 },
        else => return error.InvalidCSIModifier,
    };

    const evt = Event{
        .key = Key{
            .id = key_id,
            .modifiers = @bitCast(modmask -| 1),
            .kind = kind,
        },
    };

    return evt;
}

fn parse_csi_cursor_position(buffer: []u8) !?Event {
    const numbers = buffer[2 .. buffer.len - 1];

    // Split the numbers at the semicolon
    var iter = std.mem.split(u8, numbers, ";");

    // Parse the first number (row)
    const row_str = iter.next() orelse return error.InvalidCursorPosition;
    const row = std.fmt.parseInt(u16, row_str, 10) catch return error.InvalidCursorPosition;

    // Parse the second number (column)
    const col_str = iter.next() orelse return error.InvalidCursorPosition;
    const col = std.fmt.parseInt(u16, col_str, 10) catch return error.InvalidCursorPosition;

    return Event{ .cursor_pos = CursorPos{ .x = col - 1, .y = row - 1 } };
}

fn parse_csi_keyboard_enhancement_flags(buffer: []u8) ?Event {
    if (buffer.len < 5) return null;
    const bits = buffer[3];
    return Event{ .keyboard_enhancement_flags = @bitCast(bits) };
}

fn parse_csi_u_encoded(buffer: []u8) !?Event {
    // ESC [ codepoint : alternate key codes ; modifiers : event type ; text u
    // NOTE: codepoint is ASCII decimal value

    var parts = std.mem.splitScalar(u8, buffer[2 .. buffer.len - 1], ';');

    // parse codepoint
    var codepoints = std.mem.splitScalar(u8, parts.first(), ':');
    const first_codepoint = std.fmt.parseInt(u21, codepoints.first(), 10) catch return error.InvalidCSI;

    // std.debug.print("codepoint: {}\n", .{first_codepoint});

    // parse modifiers
    var modifiers = Modifiers{};
    var event = KeyEventKind.press;
    if (parts.next()) |modifier_str| {
        var modifier_parts = std.mem.splitScalar(u8, modifier_str, ':');
        const modmask = std.fmt.parseInt(u8, modifier_parts.first(), 10) catch return error.InvalidCSI;
        modifiers = @bitCast(modmask -| 1);

        if (modifier_parts.next()) |event_str| {
            const event_code = std.fmt.parseInt(u8, event_str, 10) catch return error.InvalidCSI;
            event = KeyEventKind.parse(event_code);
        }
    }

    var k = Key{
        .id = KeyId.char(first_codepoint),
        .modifiers = modifiers,
        .kind = event,
    };

    if (translateFunctionalKeyCode(first_codepoint)) |id| {
        k.id = id;
    } else {
        switch (first_codepoint) {
            '\x1b' => k.id = .esc,
            '\r', '\n' => k.id = .enter,
            '\t' => if (modifiers.shift) {
                k.id = .backtab;
            } else {
                k.id = .tab;
            },
            '\x7f' => k.id = .backspace,
            else => {},
        }
    }

    return Event{ .key = k };
}

fn translateFunctionalKeyCode(codepoint: u32) ?KeyId {
    return switch (codepoint) {
        // keypad keys
        57399...57408 => KeyId.char('0' + @as(u8, @intCast(codepoint - 57399))),
        57409 => KeyId.char('.'),
        57410 => KeyId.char('/'),
        57411 => KeyId.char('*'),
        57412 => KeyId.char('-'),
        57413 => KeyId.char('+'),
        57414 => .enter,
        57415 => KeyId.char('='),
        57416 => KeyId.char(','),
        57417 => .arrow_left,
        57418 => .arrow_right,
        57419 => .arrow_up,
        57420 => .arrow_down,
        57421 => .page_up,
        57422 => .page_down,
        57423 => .home,
        57424 => .end,
        57425 => .insert,
        57426 => .delete,
        57427 => .keypad_begin,

        // other keys
        57358 => .caps_lock,
        57359 => .scroll_lock,
        57360 => .num_lock,
        57361 => .print_screen,
        57362 => .pause,
        57363 => .menu,
        57376...57398 => KeyId.f(@as(u8, @intCast(codepoint - 57363))), // F13-F35

        // media keys
        57428 => .play,
        57429 => .pause,
        57430 => .play_pause,
        57431 => .reverse,
        57432 => .stop,
        57433 => .fast_forward,
        57434 => .rewind,
        57435 => .track_next,
        57436 => .track_previous,
        57437 => .record,
        57438 => .lower_volume,
        57439 => .raise_volume,
        57440 => .mute_volume,

        // modifiers
        57441 => .left_shift,
        57442 => .left_control,
        57443 => .left_alt,
        57444 => .left_super,
        57445 => .left_hyper,
        57446 => .left_meta,
        57447 => .right_shift,
        57448 => .right_control,
        57449 => .right_alt,
        57450 => .right_super,
        57451 => .right_hyper,
        57452 => .right_meta,
        57453 => .iso_level_3_shift,
        57454 => .iso_level_5_shift,
        else => null,
    };
}

test "parse events" {
    var reader = try EventReader.init(std.testing.allocator);
    defer reader.deinit();

    var input = [_]u8{ '\x1b', '[', '1', 'R' };
    try std.testing.expectError(
        error.InvalidCursorPosition,
        reader.parseBuffer(&input, true),
    );
}
