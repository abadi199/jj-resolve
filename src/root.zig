const std = @import("std");

const Error = error{
    GenericError,
};

const State = enum {
    no_conflict,
    in_conflict_header,
    in_diff_header,
    in_diff_body,
    in_snapshot_header,
    in_snapshot_body,
    end_conflict,
};

pub fn parse(allocator: std.mem.Allocator, text: []const u8) !ParsedFile {
    var state: State = .no_conflict;
    var segments: std.ArrayList(Segment) = .empty;
    defer segments.deinit(allocator);

    var text_list: std.ArrayList([]const u8) = .empty;
    defer text_list.deinit(allocator);

    var iter = std.mem.splitSequence(u8, text, "\n");
    var conflict: ?Conflict = null;
    while (iter.next()) |line| {
        std.debug.print("line: {s}\n", .{line});
        const marker = Marker.detect(line);

        std.debug.print("state: {any}\n", .{state});
        std.debug.print("marker: {any}\n", .{marker});
        switch (state) {
            .no_conflict => {
                switch (marker) {
                    .conflict => {
                        state = .in_conflict_header;
                        // add text to segment
                        try segments.append(allocator, .{
                            .text = try text_list.toOwnedSlice(allocator),
                        });
                        text_list = .empty;

                        // capture conflict
                        conflict = try Conflict.parseHeader(line);
                    },
                    .end_conflict => {
                        return error.ParseError;
                    },
                    .none => {
                        try text_list.append(allocator, line);
                    },
                }
            },
            .in_conflict_header => {
                switch (marker) {
                    .conflict => {
                        return error.ParseError;
                    },
                    .end_conflict => {
                        // end of conflict, add to segments
                        state = .end_conflict;
                        try segments.append(allocator, .{ .conflict = conflict.? });
                    },
                    .none => {
                        // TODO
                    },
                }
            },
            .end_conflict => {
                switch (marker) {
                    .conflict => {},
                    .end_conflict => {},
                    .none => {
                        state = .no_conflict;
                        try text_list.append(allocator, line);
                    },
                }
            },
            .in_diff_header,
            .in_diff_body,
            .in_snapshot_header,
            .in_snapshot_body,
            => {},
        }
    }

    switch (state) {
        .no_conflict,
        .end_conflict,
        => {
            try segments.append(allocator, .{ .text = try text_list.toOwnedSlice(allocator) });
        },
        .in_conflict_header,
        .in_diff_header,
        .in_diff_body,
        .in_snapshot_header,
        .in_snapshot_body,
        => {},
    }

    debugPrintSegments(&segments);
    return ParsedFile{
        .segments = try segments.toOwnedSlice(allocator),
    };
}

test "parse without conflicts" {
    const allocator = std.testing.allocator;
    var output = try parse(allocator,
        \\function before() {
        \\  console.log("before test");
        \\  console.log("before main");
        \\  console.log("BEFORE TEST");
        \\}
    );
    defer output.deinit(allocator);

    try std.testing.expectEqual(1, output.segments.len);
}

test "parse file with text and conflict" {
    const allocator = std.testing.allocator;
    var output = try parse(allocator,
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
    defer output.deinit(allocator);
    try std.testing.expectEqual(3, output.segments.len);
}

const Marker = enum {
    conflict,
    end_conflict,
    none,

    fn detect(line: []const u8) Marker {
        if (std.mem.startsWith(u8, line, "<<<<<<<")) {
            return .conflict;
        }
        if (std.mem.startsWith(u8, line, ">>>>>>>")) {
            return .end_conflict;
        }
        return .none;
    }
};

const ParsedFile = struct {
    segments: []const Segment,

    fn deinit(self: *ParsedFile, allocator: std.mem.Allocator) void {
        for (self.segments) |segment| {
            switch (segment) {
                .text => |text| {
                    allocator.free(text);
                },
                .conflict => |conflict| {
                    // TODO
                    _ = conflict;
                },
            }
        }

        allocator.free(self.segments);
    }
};

const Segment = union(enum) {
    text: [][]const u8,
    conflict: Conflict,
};

// marker: <<<<<<<
const Conflict = struct {
    index: u32,
    total: u32,
    markers: []const ConflictMarker,

    fn parseHeader(line: []const u8) !Conflict {
        var it = std.mem.splitScalar(u8, line, ' ');
        _ = it.next();
        _ = it.next();

        const index_str = it.next() orelse return error.ParseError;
        _ = it.next();
        const total_str = it.next() orelse return error.ParseError;

        const index = try std.fmt.parseInt(u32, index_str, 10);
        const total = try std.fmt.parseInt(u32, total_str, 10);

        return Conflict{
            .index = index,
            .total = total,
            .markers = &[0]ConflictMarker{},
        };
    }
};

test "Conflict.parseHeader" {
    const output = try Conflict.parseHeader("<<<<<<< conflict 1 of 3");
    try std.testing.expectEqual(1, output.index);
    try std.testing.expectEqual(3, output.total);
}

const ConflictMarker = union(enum) {
    snapshot: Snapshot,
    diff: Diff,
};

// marker: %%%%%%%
const Diff = struct {
    from: Revision,
    to: Revision,
    rebasedCommitID: []const u8,
    content: []const DiffLine,

    // fn parse(line: []const u8) !Diff {
    //     return Diff{
    //         .from = try Revision.parse(line),
    //     };
    // }
};

// test "Diff.parse" {
//     const output = try Diff.parse(
//         \\%%%%%%% diff from: ulopzqqq 6606ba58 "a"
//         \\\\\\\\\        to: ltrosymo 096e9f1c "b+c" (rebased revision)
//         \\-  console.log("before test");
//         \\+  console.log("before main");
//     );
//     try std.testing.expectEqualDeep("ulopzqqq", output.from.changeID);
// }

const DiffLine = union(enum) {
    text: []const u8,
    delete: []const u8,
    add: []const u8,
};

// marker: +++++++
const Snapshot = struct {
    commit: Revision,
    content: []const u8,
};

// a.k.a Commit
const Revision = struct {
    changeID: []const u8,
    commitID: []const u8,
    description: []const u8,

    const Error = error{
        ParseError,
    };

    fn parse(line: []const u8) Revision.Error!Revision {
        _ = line;
        return Revision.Error.ParseError;
    }
};

// test "Revision.parse" {
//     const output = try Revision.parse("from: ulopzqqq 6606ba58 \"a\"");
//     try std.testing.expectEqualStrings("ulopzqqq", output.changeID);
//     try std.testing.expectEqualStrings("6606ba58", output.commitID);
//     try std.testing.expectEqualStrings("a", output.description);
// }

fn debugPrintSegments(segments: *const std.ArrayList(Segment)) void {
    std.debug.print("#######################################################\n", .{});
    std.debug.print("segments.len={d}\n", .{segments.items.len});

    for (segments.items, 0..) |segment, i| {
        switch (segment) {
            .text => |lines| {
                std.debug.print("  [{d}] text lines={d}\n", .{ i, lines.len });
                for (lines, 0..) |line, j| {
                    std.debug.print("    [{d}] {s}\n", .{ j, line });
                }
            },
            .conflict => |conflict| {
                std.debug.print(
                    "  [{d}] conflict {d} of {d}, markers={d}\n",
                    .{ i, conflict.index, conflict.total, conflict.markers.len },
                );
            },
        }
    }
}
