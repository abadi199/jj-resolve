const std = @import("std");
const app = @import("app.zig");
const gtk = @import("gtk");
const gio = @import("gio");

pub fn main() void {
    defer app.deinit();

    var gtkapp = gtk.Application.new("org.abadi199.jj-resolve", .{});

    defer gtkapp.unref();
    _ = gio.Application.signals.startup.connect(gtkapp, ?*anyopaque, &app.buildMenu, null, .{});
    _ = gio.Application.signals.activate.connect(gtkapp, ?*anyopaque, &app.buildUI, null, .{});
    const status = gio.Application.run(gtkapp.as(gio.Application), 0, null);
    std.process.exit(@intCast(status));
}
