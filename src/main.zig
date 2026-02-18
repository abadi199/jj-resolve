const std = @import("std");
const jjresolve = @import("root.zig");
const ParsedFile = jjresolve.ParsedFile;
const Revision = jjresolve.Revision;
const dvui = @import("dvui");

var file: ?ParsedFile = null;

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
    try openFile("./example/test1.ts");
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {
    if (file) |*f| {
        f.deinit(gpa);
    }
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
                    try openFile(f);
                }
            }

            if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
                return .close;
            }
        }
    }

    // Main pane
    {
        var split_ratio: f32 = 0.33;
        var main_pane = dvui.paned(
            @src(),
            .{ .direction = .horizontal, .collapsed_size = 100, .handle_margin = 0, .split_ratio = &split_ratio },
            .{ .style = .window, .background = true, .expand = .both },
        );
        defer main_pane.deinit();

        if (main_pane.showFirst()) {
            // Base Column
            var vbox = dvui.box(
                @src(),
                .{ .dir = .vertical },
                .{ .expand = .both, .background = true },
            );
            defer vbox.deinit();

            if (file) |f| {
                if (f.getBaseRevision()) |rev| {
                    renderRevision(rev);
                }
            }

            const base_text: []u8 = @constCast(if (file) |f| try f.getBase(gpa) else "");
            var text_entry = dvui.textEntry(
                @src(),
                .{ .multiline = true, .text = .{ .buffer = base_text } },
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
                if (file) |f| {
                    try renderBranches(f);
                }
            }
            if (output_pane.showSecond()) {
                // Output column
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

fn renderBranches(parsed_file: ParsedFile) !void {
    const revisions = try parsed_file.getRevisions(gpa);
    for (revisions, 0..) |rev, i| {
        const vbox = dvui.box(
            @src(),
            .{
                .dir = .vertical,
            },
            .{
                .expand = .horizontal,
                .background = true,
                .color_fill = .blue,
                .id_extra = i,
            },
        );
        defer vbox.deinit();
        renderRevision(rev);
        try renderContent(parsed_file, rev);
    }
}

fn renderContent(parsed_file: ParsedFile, revision: Revision) !void {
    const text = try parsed_file.getContent(gpa, revision);
    const text_entry = dvui.textEntry(
        @src(),
        .{ .multiline = true, .text = .{ .buffer = @constCast(text) } },
        .{ .expand = .both },
    );
    defer text_entry.deinit();
}

fn renderRevision(revision: jjresolve.Revision) void {
    {
        const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .background = true, .color_fill = .red });
        defer hbox.deinit();
        dvui.label(@src(), "Change ID: {s}", .{revision.changeID}, .{ .expand = .horizontal });
        dvui.label(@src(), "Commit ID: {s}", .{revision.commitID}, .{ .expand = .horizontal });
    }

    dvui.label(@src(), "Description: {s}", .{revision.description}, .{ .expand = .horizontal });
}

fn openFile(filename: []const u8) !void {
    const data = try std.fs.cwd().readFileAlloc(gpa, filename, 10 * 1024 * 1024);
    file = try jjresolve.parse(gpa, data);
}
