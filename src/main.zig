const std = @import("std");
const jjresolve = @import("root.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    _ = try jjresolve.parse(allocator,
        \\function before() {
        \\<<<<<<< conflict 1 of 3
        \\%%%%%%% diff from: ulopzqqq 6606ba58 "a"
        \\\\\\\\\        to: ltrosymo 096e9f1c "b+c" (rebased revision)
        \\-  console.log("before test");
        \\+  console.log("before main");
        \\+++++++ vsqszzzy af5bacc0 "c"
        \\  console.log("BEFORE TEST");
        \\>>>>>>> conflict 1 of 3 ends
        \\}
    );
}
