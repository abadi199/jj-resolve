const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const gdk = @import("gdk");
const gtksource = @import("gtksource");
const parser = @import("parser.zig");
const ui = @import("ui.zig");

var base_revision_widget: ?ui.RevisionWidget = null;
var base_buffer: *gtksource.Buffer = undefined;

pub fn main() void {
    base_buffer = gtksource.Buffer.new(null);
    defer deinit();

    var app = gtk.Application.new("org.gtk.example", .{});
    defer app.unref();
    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{});
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}

fn deinit() void {
    if (file) |f| {
        f.deinit(gpa);
    }

    base_buffer.unref();
}

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.c) void {
    var provider = gtk.CssProvider.new();
    provider.loadFromString(@embedFile("style.css"));

    gtk.StyleContext.addProviderForDisplay(
        gdk.Display.getDefault().?,
        provider.as(gtk.StyleProvider),
        gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    );

    var window = gtk.ApplicationWindow.new(app);
    gtk.Window.setTitle(window.as(gtk.Window), "Window");
    gtk.Window.setDefaultSize(window.as(gtk.Window), 800, 600);
    gtk.Window.maximize(window.as(gtk.Window));

    // gtk.Window.setChild(window.as(gtk.Window), scrolled_window.as(gtk.Widget));
    createColumns(window.as(gtk.Window));

    gtk.Widget.show(window.as(gtk.Widget));

    // load file
    const f = openFile(
        "./example/test1.ts",
    ) catch {
        return;
    };
    file = f;

    if (base_revision_widget) |widget| {
        const base_revision = f.getBaseRevision();
        if (base_revision) |rev| {
            widget.setRevision(gpa, rev) catch {};
        }
    }

    const base_content = f.getBase(gpa) catch |err| {
        std.log.err("Failed to get base content: {}", .{err});
        return;
    };
    const text = gpa.dupeZ(u8, base_content) catch |err| {
        std.log.err("Failed to get base content: {}", .{err});
        return;
    };
    gtk.TextBuffer.setText(base_buffer.as(gtk.TextBuffer), text.ptr, -1);

    var base_view = ui.BaseView.new();
    base_view.render(gpa, f, left_box) catch |err| {
        std.log.err("Failed to render base: {}", .{err});
        return;
    };
}

fn closeWindow(_: *gtk.Button, window: *gtk.ApplicationWindow) callconv(.c) void {
    gtk.Window.destroy(window.as(gtk.Window));
}

var left_box: *gtk.Box = undefined;
fn createColumns(window: *gtk.Window) void {
    var hbox = gtk.Box.new(.horizontal, 5);
    // gtk.Widget.setMarginBottom(hbox.as(gtk.Widget), 10);
    // gtk.Widget.setMarginTop(hbox.as(gtk.Widget), 10);
    // gtk.Widget.setMarginEnd(hbox.as(gtk.Widget), 10);
    // gtk.Widget.setMarginStart(hbox.as(gtk.Widget), 10);
    gtk.Widget.setHexpand(hbox.as(gtk.Widget), 1);
    gtk.Box.setHomogeneous(hbox, 1);

    left_box = gtk.Box.new(.vertical, 5);
    base_revision_widget = ui.RevisionWidget.new(left_box);
    gtk.Widget.addCssClass(left_box.as(gtk.Widget), "left-box");

    var middle_box = gtk.Box.new(.vertical, 5);
    _ = ui.RevisionWidget.new(middle_box);
    gtk.Widget.addCssClass(middle_box.as(gtk.Widget), "middle-box");

    var right_box = gtk.Box.new(.vertical, 5);
    _ = ui.RevisionWidget.new(right_box);
    gtk.Widget.addCssClass(right_box.as(gtk.Widget), "right-box");

    hbox.append(left_box.as(gtk.Widget));
    hbox.append(middle_box.as(gtk.Widget));
    hbox.append(right_box.as(gtk.Widget));

    gtk.Window.setChild(window, hbox.as(gtk.Widget));
}

var file: ?parser.ParsedFile = null;
const gpa = std.heap.page_allocator;

fn openFile(filename: []const u8) !parser.ParsedFile {
    const data = try std.fs.cwd().readFileAlloc(gpa, filename, 10 * 1024 * 1024);
    return try parser.parse(gpa, data);
}
