const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("jjresolve", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "jjresolve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "jjresolve", .module = mod },
            },
        }),
    });

    // DVUI
    // const dvui_dep = b.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .sdl3 });
    // exe.root_module.addImport("dvui", dvui_dep.module("dvui_sdl3"));

    // GObject (GTK)
    const gobject = b.dependency("gobject", .{});
    exe.root_module.addImport("gtk", gobject.module("gtk4"));
    exe.root_module.addImport("gdk", gobject.module("gdk4"));
    exe.root_module.addImport("adw", gobject.module("adw1"));
    exe.root_module.addImport("gio", gobject.module("gio2"));
    exe.root_module.addImport("gobject", gobject.module("gobject2"));
    exe.root_module.addImport("gtksource", gobject.module("gtksource5"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
