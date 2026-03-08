const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const gdk = @import("gdk");
const gtksource = @import("gtksource");
const parser = @import("parser.zig");
const ui = @import("ui.zig");
const output = @import("output.zig");

var file: ?parser.ParsedFile = null;
const gpa = std.heap.page_allocator;

// Base view state
var base_box: *gtk.Box = undefined;
var base_view: ?*ui.BaseView = null;

// Revisions view state
var revisions_box: *gtk.Box = undefined;
var revisions_view: ?*ui.RevisionsView = null;

// Output view state
var output_box: *gtk.Box = undefined;
var output_view: ?*ui.OutputView = null;

pub fn main() void {
    defer deinit();

    var app = gtk.Application.new("org.abadi199.jj-resolve", .{});

    defer app.unref();
    _ = gio.Application.signals.startup.connect(app, ?*anyopaque, &startup, null, .{});
    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{});
    const status = gio.Application.run(app.as(gio.Application), 0, null);
    std.process.exit(@intCast(status));
}

fn deinit() void {
    if (file) |f| {
        f.deinit(gpa);
    }

    if (base_view) |v| {
        v.deinit();
        gpa.destroy(v);
    }

    if (revisions_view) |v| {
        v.deinit();
        gpa.destroy(v);
    }
}

fn startup(app: *gtk.Application, _: ?*anyopaque) callconv(.c) void {
    buildMenu(app);
}

fn buildMenu(app: *gtk.Application) void {
    // file > open
    const act_open = gio.SimpleAction.new("file_open", null);
    _ = gio.SimpleAction.signals.activate.connect(act_open, *gtk.Application, &onFileOpen, app, .{});
    gio.ActionMap.addAction(app.as(gio.ActionMap), act_open.as(gio.Action));
    app.setAccelsForAction("app.file_open", @ptrCast(&[_]?[*:0]const u8{ "<Primary>o", null }));

    // file > open
    const act_save = gio.SimpleAction.new("file_save", null);
    _ = gio.SimpleAction.signals.activate.connect(act_save, *gtk.Application, &onFileSave, app, .{});
    gio.ActionMap.addAction(app.as(gio.ActionMap), act_save.as(gio.Action));
    app.setAccelsForAction("app.file_save", @ptrCast(&[_]?[*:0]const u8{ "<Primary>s", null }));

    // file > quit
    const act_quit = gio.SimpleAction.new("file_quit", null);
    _ = gio.SimpleAction.signals.activate.connect(act_quit, *gtk.Application, &onFileQuit, app, .{});
    gio.ActionMap.addAction(app.as(gio.ActionMap), act_quit.as(gio.Action));
    app.setAccelsForAction("app.file_quit", @ptrCast(&[_]?[*:0]const u8{ "<Primary>q", null }));

    const file_menu = gio.Menu.new();
    defer file_menu.unref();
    gio.Menu.append(file_menu, "Open", "app.file_open");
    gio.Menu.append(file_menu, "Save", "app.file_save");
    gio.Menu.append(file_menu, "Quit", "app.file_quit");

    const file_item = gio.MenuItem.new("_File", null);
    defer file_item.unref();
    gio.MenuItem.setSubmenu(file_item, file_menu.as(gio.MenuModel));

    const menu_bar = gio.Menu.new();
    defer menu_bar.unref();

    gio.Menu.appendItem(menu_bar, file_item);
    app.setMenubar(menu_bar.as(gio.MenuModel));
}

fn onFileOpen(_: *gio.SimpleAction, _: ?*glib.Variant, app: *gtk.Application) callconv(.c) void {
    const window = app.getActiveWindow();
    std.log.debug("file open", .{});
    const dialog = gtk.FileDialog.new();
    dialog.setTitle("Select a file");
    // dialog.open(window, null, &onOpenReady, null);
    dialog.open(window, null, @ptrCast(&onOpenReady), null);
}

fn onOpenReady(dialog: *gtk.FileDialog, res: *gio.AsyncResult, _: ?*anyopaque) callconv(.c) void {
    const gio_file = gtk.FileDialog.openFinish(dialog, res, null) orelse {
        std.debug.print("File dialog was cancelled\n", .{});
        return;
    };
    defer gio_file.unref();

    const path = gio.File.getPath(gio_file) orelse "(no path)";
    std.debug.print("Selected file: {s}\n", .{path});
    const f = openFile(std.mem.span(path)) catch @panic("Failed to open file");
    file = f;
    loadFile(f);
}

fn loadFile(f: parser.ParsedFile) void {
    ui.removeAllChildren(base_box);
    ui.removeAllChildren(revisions_box);
    ui.removeAllChildren(output_box);

    var base_revision_widget = ui.RevisionWidget.new(base_box, null, .{ .is_radio = false });
    const base_revision = f.getBaseRevision();
    if (base_revision) |rev| {
        base_revision_widget.setRevision(gpa, rev) catch {};
    }

    const base_content = f.getBase(gpa) catch |err| {
        std.log.err("Failed to get base content: {}", .{err});
        return;
    };
    const text = gpa.dupeZ(u8, base_content) catch |err| {
        std.log.err("Failed to get base content: {}", .{err});
        return;
    };
    const base_buffer = gtksource.Buffer.new(null);
    gtk.TextBuffer.setText(base_buffer.as(gtk.TextBuffer), text.ptr, -1);

    // create base view
    const view = gpa.create(ui.BaseView) catch unreachable;
    view.* = ui.BaseView.new(gpa);
    base_view = view;
    view.render(f, base_box) catch @panic("Failed to render base");
    view.onConflictSelected(&onConflictSelected) catch @panic("Failed to register onConflictSelected callback");

    // create output view
    const oview = gpa.create(ui.OutputView) catch unreachable;
    oview.* = ui.OutputView.new(gpa, f) catch @panic("Failed to create OutputView");
    output_view = oview;
    oview.render(output_box) catch @panic("Failed to render output_view");
}

fn onFileSave(_: *gio.SimpleAction, _: ?*glib.Variant, _: *gtk.Application) callconv(.c) void {
    if (file) |f| {
        if (output_view) |oview| {
            // const path = std.mem.replaceOwned(u8, gpa, f.path, "/example/", "/output/") catch @panic("Failed createing output file");
            const path = f.path;
            const content = oview.toContent() catch @panic("Failed calling OutputFile.toContent");
            std.log.debug("{s}", .{content});
            const cwd = std.fs.cwd();
            const output_file = cwd.createFile(path, .{}) catch @panic("Failed to create file");
            defer output_file.close();
            _ = output_file.write(content) catch @panic("Failed saving file");
        }
    }
}

fn onFileQuit(_: *gio.SimpleAction, _: ?*glib.Variant, app: *gtk.Application) callconv(.c) void {
    std.log.debug("file quit", .{});
    gio.Application.quit(app.as(gio.Application));
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
    window.setShowMenubar(1);
    // gtk.Window.maximize(window.as(gtk.Window));

    // gtk.Window.setChild(window.as(gtk.Window), scrolled_window.as(gtk.Widget));
    buildUI(window.as(gtk.Window));

    gtk.Widget.show(window.as(gtk.Widget));

    const args = std.process.argsAlloc(gpa) catch @panic("Failed reading cli args");
    defer std.process.argsFree(gpa, args);

    if (args.len == 2) {
        const f = openFile(args[1]) catch |err| {
            std.log.err("error: {}", .{err});
            return;
        };
        file = f;
        loadFile(f);
    }

    // load file
    // const f = openFile(
    //     "./example/test3.txt",
    // ) catch |err| {
    //     std.log.err("error: {}", .{err});
    //     return;
    // };
    // file = f;

    // if (base_revision_widget) |widget| {
    //     const base_revision = f.getBaseRevision();
    //     if (base_revision) |rev| {
    //         widget.setRevision(gpa, rev) catch {};
    //     }
    // }

    // const base_content = f.getBase(gpa) catch |err| {
    //     std.log.err("Failed to get base content: {}", .{err});
    //     return;
    // };
    // const text = gpa.dupeZ(u8, base_content) catch |err| {
    //     std.log.err("Failed to get base content: {}", .{err});
    //     return;
    // };
    // gtk.TextBuffer.setText(base_buffer.as(gtk.TextBuffer), text.ptr, -1);

    // // create base view
    // const view = gpa.create(ui.BaseView) catch unreachable;
    // view.* = ui.BaseView.new(gpa);
    // base_view = view;
    // view.render(f, base_box) catch @panic("Failed to render base");
    // view.onConflictSelected(&onConflictSelected) catch @panic("Failed to register onConflictSelected callback");

    // // create output view
    // const oview = gpa.create(ui.OutputView) catch unreachable;
    // oview.* = ui.OutputView.new(gpa, f) catch @panic("Failed to create OutputView");
    // output_view = oview;
    // oview.render(output_box) catch @panic("Failed to render output_view");
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
fn onRevisionSelected(conflict_index: u32, revision: parser.Revision) void {
    if (output_view) |oview| {
        if (file) |f| {
            const content = f.getConflictContent(gpa, conflict_index, revision) catch @panic("Failed to get content");
            oview.setContent(gpa, conflict_index, content) catch @panic("Failed to set content");
        }
    }
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
    gtk.Widget.addCssClass(base_box.as(gtk.Widget), "base-box");

    // revision column
    revisions_box = gtk.Box.new(.vertical, 5);
    gtk.Widget.addCssClass(revisions_box.as(gtk.Widget), "revisions-box");

    // output column
    output_box = gtk.Box.new(.vertical, 5);
    gtk.Widget.addCssClass(output_box.as(gtk.Widget), "output-box");

    hbox.append(base_box.as(gtk.Widget));
    hbox.append(revisions_box.as(gtk.Widget));
    hbox.append(output_box.as(gtk.Widget));

    gtk.Window.setChild(window, hbox.as(gtk.Widget));
}

fn openFile(filename: []const u8) !parser.ParsedFile {
    const data = try std.fs.cwd().readFileAlloc(gpa, filename, 10 * 1024 * 1024);
    return try parser.parse(gpa, filename, data);
}
