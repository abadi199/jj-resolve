const std = @import("std");
const jjresolve = @import("root.zig");
const dvui = @import("dvui");

var base_text: []u8 = &.{};

pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 1900.0, .h = 1000.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .title = "JJResolve",
            .window_init_options = .{
                // Could set a default theme here
                // .theme = dvui.Theme.builtin.dracula,
            },
        },
    },
    .frameFn = AppFrame,
    .initFn = AppInit,
    .deinitFn = AppDeinit,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;

const gpa = std.heap.page_allocator;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn AppInit(win: *dvui.Window) !void {
    _ = win;
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {
    gpa.free(base_text);
}

// Run each frame to do normal UI
pub fn AppFrame() !dvui.App.Result {
    return frame();
}

pub fn frame() !dvui.App.Result {
    var scaler = dvui.scale(@src(), .{ .scale = &dvui.currentWindow().content_scale, .pinch_zoom = .global }, .{ .rect = .cast(dvui.windowRect()) });
    scaler.deinit();

    {
        var hbox = dvui.box(
            @src(),
            .{ .dir = .horizontal },
            .{
                .style = .window,
                .background = true,
                .color_fill = .green,
                .expand = .horizontal,
            },
        );
        defer hbox.deinit();

        var m = dvui.menu(@src(), .horizontal, .{});
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .tag = "first-focusable" })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "Open file", .{}, .{ .expand = .horizontal }) != null) {
                m.close();
                const filename = dvui.dialogNativeFileOpen(dvui.currentWindow().arena(), .{
                    .title = "JJResolve open file",
                }) catch |err| blk: {
                    dvui.log.debug("Could not open file dialog, got {any}", .{err});
                    break :blk null;
                };
                if (filename) |f| {
                    const data = try std.fs.cwd().readFileAlloc(gpa, f, 10 * 1024 * 1024);
                    var parsed_file = try jjresolve.parse(gpa, data);
                    const base_str = try parsed_file.getBase(gpa);
                    defer gpa.free(base_str);
                    base_text = try gpa.dupe(u8, base_str);
                    defer parsed_file.deinit(gpa);
                }
            }

            if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
                return .close;
            }
        }
    }
    {
        var split_ratio: f32 = 0.33;
        var main_pane = dvui.paned(
            @src(),
            .{ .direction = .horizontal, .collapsed_size = 100, .handle_margin = 0, .split_ratio = &split_ratio },
            .{ .style = .window, .background = true, .expand = .both },
        );
        defer main_pane.deinit();

        if (main_pane.showFirst()) {
            var vbox = dvui.box(
                @src(),
                .{ .dir = .vertical },
                .{ .expand = .both, .background = true },
            );
            defer vbox.deinit();
            var text_entry = dvui.textEntry(
                @src(),
                .{ .multiline = true, .text = .{ .buffer_dynamic = .{
                    .backing = &base_text,
                    .allocator = gpa,
                } } },
                .{ .expand = .both },
            );
            defer text_entry.deinit();
        }
        if (main_pane.showSecond()) {
            var output_pane = dvui.paned(
                @src(),
                .{ .direction = .horizontal, .collapsed_size = 10 },
                .{ .expand = .both, .background = true },
            );
            defer output_pane.deinit();

            if (output_pane.showFirst()) {
                var revision_pane = dvui.paned(
                    @src(),
                    .{ .direction = .vertical, .collapsed_size = 10 },
                    .{ .expand = .both, .background = true },
                );
                defer revision_pane.deinit();
                if (revision_pane.showFirst()) {
                    var hbox1 = dvui.box(
                        @src(),
                        .{ .dir = .vertical },
                        .{ .expand = .both, .background = true },
                    );
                    defer hbox1.deinit();
                    var text_entry = dvui.textEntry(
                        @src(),
                        .{ .multiline = true },
                        .{ .expand = .both },
                    );
                    defer text_entry.deinit();
                }
                if (revision_pane.showSecond()) {
                    var hbox1 = dvui.box(
                        @src(),
                        .{ .dir = .vertical },
                        .{ .expand = .both, .background = true },
                    );
                    defer hbox1.deinit();
                    var text_entry = dvui.textEntry(
                        @src(),
                        .{ .multiline = true },
                        .{ .expand = .both },
                    );
                    defer text_entry.deinit();
                }
            }
            if (output_pane.showSecond()) {
                var vbox = dvui.box(
                    @src(),
                    .{ .dir = .vertical },
                    .{ .expand = .both, .background = true },
                );
                defer vbox.deinit();
                var text_entry = dvui.textEntry(
                    @src(),
                    .{ .multiline = true },
                    .{ .expand = .both },
                );
                defer text_entry.deinit();
            }
        }
    }

    return .ok;
}
