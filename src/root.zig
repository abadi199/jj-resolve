const std = @import("std");
const mem = std.mem;

const Error = error{
    GenericError,
    Todo,
};

const State = enum {
    no_conflict,
    in_conflict,
    in_diff_header,
    in_diff_body,
    in_snapshot_header,
    in_snapshot_body,
    end_conflict,
};

pub fn parse(allocator: mem.Allocator, text: []const u8) !ParsedFile {
    var state: State = .no_conflict;
    var segments: std.ArrayList(Segment) = .empty;
    defer segments.deinit(allocator);

    // temporary data for no conflict lines
    var temp_lines: std.ArrayList([]const u8) = .empty;
    defer temp_lines.deinit(allocator);

    // temporary data for conflict and markers
    var temp_conflict: ?Conflict = null;
    var temp_conflict_markers: std.ArrayList(ConflictMarker) = .empty;
    defer temp_conflict_markers.deinit(allocator);

    var temp_diff: Diff.Partial = Diff.Partial.new();
    defer temp_diff.deinit(allocator);

    var iter = mem.splitSequence(u8, text, "\n");
    while (iter.next()) |line| {
        std.debug.print("############################\nline: {s}\n", .{line});
        const marker = Marker.detect(line);

        std.debug.print("state: {any}\n", .{state});
        std.debug.print("marker: {any}\n", .{marker});
        switch (state) {
            .no_conflict => {
                switch (marker) {
                    .conflict => {
                        state = .in_conflict;
                        // add text to segment
                        try segments.append(allocator, .{
                            .no_conflict = NoConflict{
                                .lines = try temp_lines.toOwnedSlice(allocator),
                            },
                        });
                        temp_lines = .empty;

                        // capture conflict
                        temp_conflict = try Conflict.parse(line);
                    },
                    .end_conflict => {
                        return error.GenericError;
                    },
                    .none,
                    .diff,
                    .multi_line,
                    => {
                        try temp_lines.append(allocator, line);
                    },
                }
            },
            .in_conflict => {
                switch (marker) {
                    .conflict,
                    .end_conflict,
                    => {
                        return error.GenericError;
                    },
                    .diff,
                    .multi_line,
                    => {
                        state = .in_diff_header;
                        try temp_diff.parse(line);
                        // std.debug.print("diff: {any}\n", .{diff});
                        // try markers.append(allocator, diff);
                    },
                    .none,
                    => {
                        // TODO
                    },
                }
            },
            .in_diff_header => {
                switch (marker) {
                    .diff,
                    .conflict,
                    .end_conflict,
                    => {
                        // end of conflict, add to segments
                        state = .end_conflict;
                        try segments.append(allocator, .{ .conflict = temp_conflict.? });
                    },
                    .multi_line,
                    => {
                        state = .in_diff_header;
                        try temp_diff.parse(line);
                        // std.debug.print("diff: {any}\n", .{diff});
                    },
                    .none,
                    => {
                        state = .in_diff_body;
                        // start capturing diff body
                        try temp_diff.diff_lines.append(allocator, DiffLine.parse(line));
                        // TODO
                    },
                }
            },
            .in_diff_body => {
                switch (marker) {
                    .none,
                    .multi_line,
                    => {
                        // more body
                    },
                    .diff,
                    => {
                        // new diff
                        state = .in_diff_header;
                        try temp_conflict_markers.append(
                            allocator,
                            ConflictMarker{
                                .diff = temp_diff.toDiff(allocator),
                            },
                        );

                        temp_diff = Diff.Partial.new();
                        try temp_diff.parse(line);
                    },
                    .end_conflict,
                    => {
                        // end diff body, end of conflict
                        state = .end_conflict;
                        try temp_conflict_markers.append(allocator, ConflictMarker{
                            .diff = Diff{
                                .from = temp_diff.from.?,
                                .to = temp_diff.to.?,
                                .diff_lines = &[0]DiffLine{}, // TODO
                            },
                        });
                    },
                    .conflict => {
                        return error.GenericError;
                    },
                }
            },
            .end_conflict => {
                switch (marker) {
                    .conflict => {},
                    .end_conflict => {},
                    .diff => {},
                    .multi_line => {},
                    .none => {
                        state = .no_conflict;
                        try temp_lines.append(allocator, line);
                    },
                }
            },
            .in_snapshot_header,
            .in_snapshot_body,
            => {},
        }
    }

    switch (state) {
        .no_conflict,
        .end_conflict,
        => {
            try segments.append(allocator, .{
                .no_conflict = NoConflict{
                    .lines = try temp_lines.toOwnedSlice(allocator),
                },
            });
        },
        .in_conflict,
        .in_diff_header,
        .in_diff_body,
        .in_snapshot_header,
        .in_snapshot_body,
        => {},
    }

    // debugPrintSegments(&segments);
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
    const segment = try output.segments[0].no_conflict.toString(allocator);
    defer allocator.free(segment);
    try std.testing.expectEqualStrings(
        \\function before() {
        \\  console.log("before test");
        \\  console.log("before main");
        \\  console.log("BEFORE TEST");
        \\}
    , segment);
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
    const segment_1 = try output.segments[0].no_conflict.toString(allocator);
    defer allocator.free(segment_1);
    try std.testing.expectEqualStrings("function before() {", segment_1);

    const conflict = output.segments[1].conflict;
    try std.testing.expectEqual(1, conflict.index);
    try std.testing.expectEqual(3, conflict.total);
    try std.testing.expectEqual(2, conflict.conflict_markers.len);

    const segment_3 = try output.segments[2].no_conflict.toString(allocator);
    defer allocator.free(segment_3);
    try std.testing.expectEqualStrings("}", segment_3);
}

const Marker = enum {
    conflict, // <<<<<<<
    end_conflict, // >>>>>>>
    diff, // %%%%%%%
    multi_line, // \\\\\\\
    none,

    fn detect(line: []const u8) Marker {
        if (mem.startsWith(u8, line, "<<<<<<<")) {
            return .conflict;
        }
        if (mem.startsWith(u8, line, ">>>>>>>")) {
            return .end_conflict;
        }
        if (mem.startsWith(u8, line, "%%%%%%%")) {
            return .diff;
        }
        if (mem.startsWith(u8, line, "\\\\\\\\\\\\\\")) {
            return .multi_line;
        }
        return .none;
    }
};

const ParsedFile = struct {
    segments: []const Segment,

    fn deinit(self: *ParsedFile, allocator: mem.Allocator) void {
        for (self.segments) |segment| {
            switch (segment) {
                .no_conflict => |no_conflict| {
                    allocator.free(no_conflict.lines);
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
    no_conflict: NoConflict,
    conflict: Conflict,
};

const NoConflict = struct {
    lines: []const []const u8,

    fn toString(self: NoConflict, allocator: mem.Allocator) ![]const u8 {
        if (self.lines.len == 0) {
            return "";
        }

        var total_len: usize = 0;
        for (self.lines) |line| {
            total_len += line.len;
        }

        // add space for new line, excluding last line
        total_len += self.lines.len - 1;

        var result = try allocator.alloc(u8, total_len);
        var i: usize = 0;
        // std.debug.print("lines.len:{d}\n", .{self.lines.len});
        for (self.lines, 0..) |line, line_num| {
            // std.debug.print("line:{s}|i:{}|line_num:{d}|line.len:{d}\n", .{
            //     line,
            //     i,
            //     line_num,
            //     line.len,
            // });
            @memcpy(result[i..(i + line.len)], line);
            i += line.len;

            if (line_num < self.lines.len - 1) {
                // append \n expect the last line
                result[i] = '\n';
                i += 1;
            }
        }

        return result;
    }
};

test "toString" {
    const allocator = std.testing.allocator;
    const input = [_][]const u8{ "a", "b", "c" };
    const output = try NoConflict.toString(NoConflict{
        .lines = input[0..],
    }, allocator);
    defer allocator.free(output);
    try std.testing.expectEqualStrings("a\nb\nc", output);
}

// marker: <<<<<<<
const Conflict = struct {
    index: u32,
    total: u32,
    conflict_markers: []const ConflictMarker,

    fn parse(line: []const u8) !Conflict {
        var it = mem.splitScalar(u8, line, ' ');
        _ = it.next();
        _ = it.next();

        const index_str = it.next() orelse return error.GenericError;
        _ = it.next();
        const total_str = it.next() orelse return error.GenericError;

        const index = try std.fmt.parseInt(u32, index_str, 10);
        const total = try std.fmt.parseInt(u32, total_str, 10);

        return Conflict{
            .index = index,
            .total = total,
            .conflict_markers = &[0]ConflictMarker{},
        };
    }
};

test "Conflict.parse" {
    const output = try Conflict.parse("<<<<<<< conflict 1 of 3");
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
    // rebasedCommitID: []const u8,
    diff_lines: []const DiffLine,

    const Partial = struct {
        from: ?Revision,
        to: ?Revision,
        // rebasedCommitID: ?[]const u8,
        diff_lines: std.ArrayList(DiffLine),

        fn new() Partial {
            return Partial{
                .from = null,
                .to = null,
                .diff_lines = .empty,
            };
        }

        fn deinit(self: *Partial, allocator: mem.Allocator) void {
            self.*.from = null;
            self.*.to = null;
            self.diff_lines.deinit(allocator);
        }

        fn parse(self: *Partial, line: []const u8) !void {
            switch (Marker.detect(line)) {
                .diff => {
                    // first line
                    self.*.from = try Revision.parseLine1(line);
                },
                .multi_line => {
                    // first line
                    const to = try Revision.parseLine2(line);
                    self.*.to = to;
                    // if (mem.containsAtLeast(u8, line, 1, "(rebased revision)")) {
                    //     self.*.rebasedCommitID = to.commitID;
                    // }
                },
                else => {
                    return error.GenericError;
                },
            }
        }

        fn toDiff(self: Partial, allocator: mem.Allocator) Diff {
            const diff_lines = try self.diff_lines.toOwnedSlice(allocator);
            defer self.diff_lines.deinit(allocator);
            return Diff{
                .to = self.to,
                .from = self.from,
                .diff_lines = diff_lines,
            };
        }
    };
};

test "Diff.parse - line 1" {
    const output = try Diff.parse("diff from: ulopzqqq 6606ba58 \"a\"");
    try std.testing.expectEqualDeep("ulopzqqq", output.from.changeID);
}

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

    fn parseQuoted(line: []const u8) ![]const u8 {
        const first = std.mem.indexOfScalar(u8, line, '"') orelse return error.GenericError;
        const rest = line[(first + 1)..];
        const second_rel = std.mem.indexOfScalar(u8, rest, '"') orelse return error.GenericError;

        return rest[0..second_rel];
    }

    fn parseLine1(line: []const u8) !Revision {
        //%%%%%%% diff from: ulopzqqq 6606ba58 "a"
        var it = mem.splitScalar(u8, line, ' ');
        _ = it.next();
        _ = it.next();
        const from = it.next() orelse "";
        if (!mem.eql(u8, from, "from:")) {
            return error.GenericError;
        }

        const changeID = it.next() orelse {
            return error.GenericError;
        };
        const commitID = it.next() orelse {
            return error.GenericError;
        };

        const description = try parseQuoted(line);

        return Revision{
            .changeID = changeID,
            .commitID = commitID,
            .description = description,
        };
    }

    fn parseLine2(line: []const u8) !Revision {
        //\\\\\\\        to: ltrosymo 096e9f1c "b+c" (rebased revision)
        var it = mem.splitScalar(u8, line, ' ');
        while (it.next()) |token| {
            if (mem.eql(u8, token, "to:")) {
                break;
            }
        }

        const changeID = it.next() orelse {
            return error.GenericError;
        };
        const commitID = it.next() orelse {
            return error.GenericError;
        };

        const description = try parseQuoted(line);

        return Revision{
            .changeID = changeID,
            .commitID = commitID,
            .description = description,
        };
    }
};

test "Revision.parse" {
    const allocator = std.testing.allocator;
    const output = try Revision.parse(allocator, "%%%%%%% diff from: ulopzqqq 6606ba58 \"a + b = c\"");
    try std.testing.expectEqualStrings("ulopzqqq", output.?.changeID);
    try std.testing.expectEqualStrings("6606ba58", output.?.commitID);
    try std.testing.expectEqualStrings("a + b = c", output.?.description);
}

fn debugPrintSegments(segments: *const std.ArrayList(Segment)) void {
    std.debug.print("#######################################################\n", .{});
    std.debug.print("segments.len={d}\n", .{segments.items.len});

    for (segments.items, 0..) |segment, i| {
        switch (segment) {
            .no_conflict => |no_conflict| {
                std.debug.print("  [{d}] text lines={d}\n", .{ i, no_conflict.lines.len });
                for (no_conflict.lines, 0..) |line, j| {
                    std.debug.print("    [{d}] {s}\n", .{ j, line });
                }
            },
            .conflict => |conflict| {
                std.debug.print(
                    "  [{d}] conflict {d} of {d}, markers={d}\n",
                    .{ i, conflict.index, conflict.total, conflict.conflict_markers.len },
                );
            },
        }
    }
}
