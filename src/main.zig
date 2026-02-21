const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const gdk = @import("gdk");
const gtksource = @import("gtksource");
const jjresolve = @import("root.zig");
const ui = @import("ui.zig");

var base_revision_widget: ?ui.RevisionWidget = null;
var base_buffer: *gtksource.Buffer = undefined;
var base_view: *gtksource.View = undefined;

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
    base_view.unref();
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

    file = f;
}

fn closeWindow(_: *gtk.Button, window: *gtk.ApplicationWindow) callconv(.c) void {
    gtk.Window.destroy(window.as(gtk.Window));
}

fn createColumns(window: *gtk.Window) void {
    var hbox = gtk.Box.new(.horizontal, 5);
    gtk.Widget.setMarginBottom(hbox.as(gtk.Widget), 10);
    gtk.Widget.setMarginTop(hbox.as(gtk.Widget), 10);
    gtk.Widget.setMarginEnd(hbox.as(gtk.Widget), 10);
    gtk.Widget.setMarginStart(hbox.as(gtk.Widget), 10);
    gtk.Widget.setHexpand(hbox.as(gtk.Widget), 1);
    gtk.Box.setHomogeneous(hbox, 1);

    var left_box = gtk.Box.new(.vertical, 5);
    base_revision_widget = ui.RevisionWidget.new(left_box);
    base_view = appendCodeView(left_box, base_buffer);
    gtk.TextView.setEditable(base_view.as(gtk.TextView), 0);
    gtk.TextView.setCursorVisible(base_view.as(gtk.TextView), 0);
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

fn appendCodeView(box: *gtk.Box, buffer: *gtksource.Buffer) *gtksource.View {
    const lang_manager = gtksource.LanguageManager.getDefault();
    if (gtksource.LanguageManager.getLanguage(lang_manager, "typescript")) |language| {
        gtksource.Buffer.setLanguage(buffer, language);
    }

    const scheme_manager = gtksource.StyleSchemeManager.getDefault();
    if (gtksource.StyleSchemeManager.getScheme(scheme_manager, "Adwaita-dark")) |scheme| {
        gtksource.Buffer.setStyleScheme(buffer, scheme);
    }

    // Create the GtkSourceView with the buffer
    var source_view = gtksource.View.newWithBuffer(buffer.as(gtksource.Buffer));
    gtksource.View.setShowLineNumbers(source_view, 0); // show line numbers
    gtksource.View.setHighlightCurrentLine(source_view, 1); // highlight current line
    gtksource.View.setTabWidth(source_view, 4);
    gtk.TextView.setMonospace(source_view.as(gtk.TextView), 1); // use monospace font

    // Wrap the source view in a scrolled window
    var scrolled_window = gtk.ScrolledWindow.new();
    gtk.ScrolledWindow.setChild(scrolled_window, source_view.as(gtk.Widget));
    gtk.Widget.setVexpand(scrolled_window.as(gtk.Widget), 1); // fill vertical space
    gtk.Widget.setHexpand(scrolled_window.as(gtk.Widget), 1); // fill horizontal space

    box.append(scrolled_window.as(gtk.Widget));

    return source_view;
}

var file: ?jjresolve.ParsedFile = null;
const gpa = std.heap.page_allocator;

fn openFile(filename: []const u8) !jjresolve.ParsedFile {
    const data = try std.fs.cwd().readFileAlloc(gpa, filename, 10 * 1024 * 1024);
    return try jjresolve.parse(gpa, data);
}
