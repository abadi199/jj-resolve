const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const gdk = @import("gdk");
const gtksource = @import("gtksource");
const parser = @import("parser.zig");
const ui = @import("ui.zig");

// Base view state
var base_box: *gtk.Box = undefined;
var base_revision_widget: ?ui.RevisionWidget = null;
var base_buffer: *gtksource.Buffer = undefined;
var base_view: ?*ui.BaseView = null;

// Revisions view state
var revisions_box: *gtk.Box = undefined;
var revisions_view: ?*ui.RevisionsView = null;

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

    if (base_view) |v| {
        v.deinit();
        gpa.destroy(v);
    }

    if (revisions_view) |v| {
        v.deinit();
        gpa.destroy(v);
    }
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
    // gtk.Window.maximize(window.as(gtk.Window));

    // gtk.Window.setChild(window.as(gtk.Window), scrolled_window.as(gtk.Widget));
    buildUI(window.as(gtk.Window));

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

    const view = gpa.create(ui.BaseView) catch return;
    view.* = ui.BaseView.new(gpa);
    base_view = view;
    view.render(f, base_box) catch |err| {
        std.log.err("Failed to render base: {}", .{err});
        return;
    };
    view.onConflictSelected(&onConflictSelected) catch |err| {
        std.log.err("Failed to register onConflictSelected callback: {}", .{err});
        return;
    };
}

fn onConflictSelected(conflict_index: u32) void {
    std.log.info("index: {d}", .{conflict_index});
    const view = gpa.create(ui.RevisionsView) catch unreachable;
    view.* = ui.RevisionsView.new(gpa, conflict_index);
    revisions_view = view;
    if (file) |f| {
        view.render(f, revisions_box) catch unreachable;
        view.onRevisionSelected(&onRevisionSelected) catch unreachable;
    }
}
fn onRevisionSelected(conflict_index: u32, commitID: []const u8) void {
    std.log.info("onRevisionSelected: {s}, {d}", .{ commitID, conflict_index });
}

fn closeWindow(_: *gtk.Button, window: *gtk.ApplicationWindow) callconv(.c) void {
    gtk.Window.destroy(window.as(gtk.Window));
}

fn buildUI(window: *gtk.Window) void {
    var hbox = gtk.Box.new(.horizontal, 10);
    gtk.Widget.setHexpand(hbox.as(gtk.Widget), 1);
    gtk.Box.setHomogeneous(hbox, 1);

    // base column
    base_box = gtk.Box.new(.vertical, 5);
    base_revision_widget = ui.RevisionWidget.new(base_box, null, .{ .is_radio = false });
    gtk.Widget.addCssClass(base_box.as(gtk.Widget), "base-box");

    // revision column
    revisions_box = gtk.Box.new(.vertical, 5);
    // _ = ui.RevisionWidget.new(revisions_box, null);
    gtk.Widget.addCssClass(revisions_box.as(gtk.Widget), "revisions-box");

    // output column
    var right_box = gtk.Box.new(.vertical, 5);
    // _ = ui.RevisionWidget.new(right_box, null);
    gtk.Widget.addCssClass(right_box.as(gtk.Widget), "output-box");

    hbox.append(base_box.as(gtk.Widget));
    hbox.append(revisions_box.as(gtk.Widget));
    hbox.append(right_box.as(gtk.Widget));

    gtk.Window.setChild(window, hbox.as(gtk.Widget));
}

var file: ?parser.ParsedFile = null;
const gpa = std.heap.page_allocator;

fn openFile(filename: []const u8) !parser.ParsedFile {
    const data = try std.fs.cwd().readFileAlloc(gpa, filename, 10 * 1024 * 1024);
    return try parser.parse(gpa, data);
}
