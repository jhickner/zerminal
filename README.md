# zerminal

A terminal library for zig.

- [X] set/get cursor position
- [X] styled printing
- [X] events: keyboard, mouse, focus, resize
- [X] misc terminal ops: alternate screen, synchronized updates, save/restore, etc. 
- [X] [kitty protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/) support
- [ ] windows support

WIP, needs docs.

## Including zerminal in your project
```zig
// build.zig.zon
.dependencies = .{
    .zerminal = .{
        .url = "https://github.com/jhickner/zerminal/archive/master.tar.gz",
        // You can leave this blank initially, then plug in the hash you get 
        // from the `zig build` error.
        .hash = "",
    },

// build.zig
const zerminal = b.dependency("zerminal", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zerminal", zerminal.module("zerminal"));
```

## Basic usage
```zig
const std = @import("std");
const z = @import("zerminal");


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const writer = std.io.getStdOut().writer();

    // save terminal state
    const orig = try z.getTermios();

    // enable individual key events
    try z.enableRawMode(.BLOCKING);

    // enable resize events
    try z.enableResizeEvents();

    // enable terminal focus change events
    try z.enableFocusChange(writer);

    // enable kitty protocol events (if supported)
    try z.pushKeyboardEnhancementFlags(writer, .{
        .report_all_keys_as_escape_codes = true,
        .report_event_types = true,
    });

    // enable mouse events
    try z.enableMouseCapture(writer);

    // create an event reader
    var reader = try z.EventReader.init(allocator);
    defer reader.deinit();

    // loop printing events until ESC is pressed
    while (try reader.readStdin(100)) |oevt| {
        if (oevt) |evt| {
            switch (evt) {
                .key => |key| switch (key.id) {
                    .esc => break,
                    else => std.debug.print("{}\n", .{evt}),
                },
                else => std.debug.print("{}\n", .{evt}),
            }
        }
    } else |err| {
        // handle errors
    }

    // disable terminal flags we enabled
    try z.popKeyboardEnhancementFlags(writer);
    try z.disableMouseCapture(writer);
    try z.disableFocusChange(writer);

    // restore original terminal state
    try z.setTermios(orig);
}
```

## Acknowledgements
- incorporates format and styling code originally from
[ansi-term](https://github.com/ziglibs/ansi-term) (MIT license)
- Inspired by rust's [crossterm](https://github.com/crossterm-rs/crossterm) library
(although this library has no windows support)
