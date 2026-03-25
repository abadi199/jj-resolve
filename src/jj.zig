const std = @import("std");

pub const ConflictFile = struct {
    name: []const u8,
};

pub fn getConflicts(allocator: std.mem.Allocator, cwd: []const u8) ![]ConflictFile {
    try std.process.changeCurDir(cwd);
    var child = std.process.Child.init(&[_][]const u8{ "jj", "resolve", "--list" }, allocator);
    child.stderr_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    try child.spawn();
    const stdout = try child.stdout.?.readToEndAlloc(allocator, std.math.maxInt(usize));
    const stderr = try child.stderr.?.readToEndAlloc(allocator, std.math.maxInt(usize));
    std.log.debug("stdout: {s}", .{stdout});
    std.log.debug("stderr: {s}", .{stderr});

    var list = std.ArrayList(ConflictFile).empty;
    const array = try list.toOwnedSlice(allocator);
    return array;
}
