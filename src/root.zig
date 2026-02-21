const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const Error = error{
    GenericError,
    Todo,
};

const State = enum {
    no_conflict,
    in_conflict,
    in_diff,
    in_snapshot,
    end_conflict,
};

pub fn parse(allocator: mem.Allocator, text: []const u8) !ParsedFile {
    var state: State = .no_conflict;

    // temporary segments
    var temp_segments: std.ArrayList(Segment) = .empty;
    defer temp_segments.deinit(allocator);

    // temporary data for no conflict lines
    var temp_lines: std.ArrayList([]const u8) = .empty;
    defer temp_lines.deinit(allocator);

    // temporary data for conflict and markers
    var temp_conflict: ?Conflict = null;
    var temp_conflict_markers: std.ArrayList(ConflictMarker) = .empty;
    defer temp_conflict_markers.deinit(allocator);

    var diff_parser: Diff.Parser = Diff.Parser.new();
    var snapshot_parser: Snapshot.Parser = Snapshot.Parser.new();

    var iter = mem.splitSequence(u8, text, "\n");
    var i: usize = 0;
    while (iter.next()) |line| {
        defer i += 1;
        // std.debug.print("############################ line {d}:\n{s}\n", .{ i, line });
        const marker = Marker.detect(line);

        // std.debug.print("state: {any}\n", .{state});
        // std.debug.print("marker: {any}\n", .{marker});
        switch (state) {
            .no_conflict => {
                switch (marker) {
                    .conflict => {
                        state = .in_conflict;
                        // add text to segment
                        try temp_segments.append(allocator, .{
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
                    .snapshot,
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
                    => {
                        state = .in_diff;
                        try diff_parser.parse(line);
                    },
                    .snapshot,
                    => {
                        state = .in_snapshot;
                        try snapshot_parser.parse(allocator, line);
                    },
                    .multi_line,
                    .none,
                    => {
                        // TODO
                    },
                }
            },
            .in_diff => {
                switch (marker) {
                    .diff,
                    => {
                        // new diff
                        state = .in_diff;
                        try temp_conflict_markers.append(
                            allocator,
                            ConflictMarker{
                                .diff = try diff_parser.toDiff(allocator),
                            },
                        );

                        diff_parser = Diff.Parser.new();
                        try diff_parser.parse(line);
                    },
                    .end_conflict,
                    => {
                        // end diff body, end of conflict
                        state = .end_conflict;
                        try temp_conflict_markers.append(
                            allocator,
                            ConflictMarker{
                                .diff = try diff_parser.toDiff(allocator),
                            },
                        );

                        if (temp_conflict == null) {
                            return error.GenericError;
                        }
                        temp_conflict.?.conflict_markers = try temp_conflict_markers.toOwnedSlice(allocator);
                        try temp_segments.append(allocator, Segment{ .conflict = temp_conflict.? });
                    },
                    .multi_line,
                    => {
                        state = .in_diff;
                        try diff_parser.parse(line);
                        // std.debug.print("diff: {any}\n", .{diff});
                    },
                    .snapshot,
                    => {
                        state = .in_snapshot;

                        // add diff to conflict_makers
                        if (temp_conflict == null) {
                            return error.GenericError;
                        }

                        try temp_conflict_markers.append(
                            allocator,
                            ConflictMarker{
                                .diff = try diff_parser.toDiff(allocator),
                            },
                        );
                        try snapshot_parser.parse(allocator, line);
                    },
                    .conflict,
                    .none,
                    => {
                        state = .in_diff;
                        // start capturing diff body
                        try diff_parser.diff_lines.append(allocator, try DiffLine.parse(line));
                    },
                }
            },
            .end_conflict => {
                switch (marker) {
                    .conflict => {},
                    .end_conflict => {},
                    .diff => {},
                    .multi_line => {},
                    .snapshot => {},
                    .none => {
                        state = .no_conflict;
                        try temp_lines.append(allocator, line);
                    },
                }
            },
            .in_snapshot,
            => {
                switch (marker) {
                    .conflict => {},
                    .end_conflict => {
                        // end of conflict, add to segments
                        state = .end_conflict;
                        const snapshot = try snapshot_parser.toSnapshot(allocator);
                        try temp_conflict_markers.append(
                            allocator,
                            ConflictMarker{
                                .snapshot = snapshot,
                            },
                        );

                        if (temp_conflict == null) {
                            return error.GenericError;
                        }
                        temp_conflict.?.conflict_markers = try temp_conflict_markers.toOwnedSlice(allocator);
                        try temp_segments.append(allocator, .{ .conflict = temp_conflict.? });
                    },
                    .diff => {},
                    .multi_line => {},
                    .snapshot => {},
                    .none => {
                        state = .in_snapshot;
                        try snapshot_parser.parse(allocator, line);
                    },
                }
            },
        }
    }

    switch (state) {
        .no_conflict,
        .end_conflict,
        => {
            try temp_segments.append(allocator, .{
                .no_conflict = NoConflict{
                    .lines = try temp_lines.toOwnedSlice(allocator),
                },
            });
        },
        .in_conflict,
        .in_diff,
        .in_snapshot,
        => {},
    }

    // debugPrintSegments(&segments);
    return ParsedFile{
        .segments = try temp_segments.toOwnedSlice(allocator),
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
    try testing.expectEqual(1, conflict.index);
    try testing.expectEqual(3, conflict.total);

    const diff = conflict.conflict_markers[0].diff;
    try testing.expectEqualDeep(Diff{
        .from = Revision{
            .changeID = "ulopzqqq",
            .commitID = "6606ba58",
            .description = "a",
        },
        .to = Revision{
            .changeID = "ltrosymo",
            .commitID = "096e9f1c",
            .description = "b+c",
        },
        .diff_lines = &[2]DiffLine{ DiffLine{
            .delete = "  console.log(\"before test\");",
        }, DiffLine{
            .add = "  console.log(\"before main\");",
        } },
    }, diff);

    const snapshot = conflict.conflict_markers[1].snapshot;
    try testing.expectEqualDeep(Snapshot{
        .commit = Revision{
            .changeID = "vsqszzzy",
            .commitID = "af5bacc0",
            .description = "c",
        },
        .lines = &[_][]const u8{"  console.log(\"BEFORE TEST\");"},
    }, snapshot);

    const segment_3 = try output.segments[2].no_conflict.toString(allocator);
    defer allocator.free(segment_3);
    try std.testing.expectEqualStrings("}", segment_3);
}

test "parse with multiple conflicts" {
    const allocator = std.testing.allocator;
    var output = try parse(
        allocator,
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
        \\
        \\<<<<<<< conflict 2 of 3
        \\%%%%%%% diff from: ulopzqqq 6606ba58 "a"
        \\\\\\\\\        to: ltrosymo 096e9f1c "b+c" (rebased revision)
        \\-function test() {
        \\+function main() {
        \\   console.log("apple");
        \\-  console.log("grape");
        \\+  console.log("grapefruit");
        \\   console.log("orange");
        \\+++++++ vsqszzzy af5bacc0 "c"
        \\function test() {
        \\  console.log("APPLE");
        \\  console.log("GRAPE");
        \\  console.log("ORANGE");
        \\>>>>>>> conflict 2 of 3 ends
        \\}
        \\
        \\function after() {
        \\<<<<<<< conflict 3 of 3
        \\%%%%%%% diff from: ulopzqqq 6606ba58 "a"
        \\\\\\\\\        to: ltrosymo 096e9f1c "b+c" (rebased revision)
        \\-  console.log("after test");
        \\+  console.log("after main");
        \\+++++++ vsqszzzy af5bacc0 "c"
        \\  console.log("AFTER TEST");
        \\>>>>>>> conflict 3 of 3 ends
        \\}
        ,
    );

    defer output.deinit(allocator);
    try testing.expectEqual(7, output.segments.len);
}

const Marker = enum {
    conflict, // <<<<<<<
    end_conflict, // >>>>>>>
    diff, // %%%%%%%
    multi_line, // \\\\\\\
    snapshot, // +++++++
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
        if (mem.startsWith(u8, line, "+++++++")) {
            return .snapshot;
        }
        return .none;
    }
};

pub const ParsedFile = struct {
    segments: []const Segment,

    pub fn deinit(self: *ParsedFile, allocator: mem.Allocator) void {
        for (self.segments) |segment| {
            switch (segment) {
                .no_conflict => |no_conflict| {
                    allocator.free(no_conflict.lines);
                },
                .conflict => |conflict| {
                    conflict.deinit(allocator);
                },
            }
        }

        allocator.free(self.segments);
    }

    pub fn getBaseRevision(self: ParsedFile) ?Revision {
        for (self.segments) |segment| {
            switch (segment) {
                .no_conflict => {},
                .conflict => |conflict| {
                    for (conflict.conflict_markers) |conflict_marker| {
                        switch (conflict_marker) {
                            .diff => |diff| {
                                return diff.from;
                            },
                            else => {},
                        }
                    }
                },
            }
        }

        return null;
    }

    pub fn getContent(self: ParsedFile, allocator: mem.Allocator, revision: Revision) ![]const u8 {
        var buffer = std.ArrayList(u8).empty;
        for (self.segments, 0..) |segment, i| {
            switch (segment) {
                .no_conflict => |no_conflict| {
                    const str = try no_conflict.toString(allocator);
                    defer allocator.free(str);

                    try buffer.appendSlice(allocator, str);
                    if (i < self.segments.len - 1) {
                        try buffer.append(allocator, '\n');
                    }
                },
                .conflict => |conflict| {
                    for (conflict.conflict_markers) |conflict_marker| {
                        switch (conflict_marker) {
                            .diff => |diff| {
                                const str = try diff.getContent(allocator, revision.commitID);
                                defer allocator.free(str);
                                try buffer.appendSlice(allocator, str);
                            },
                            .snapshot => |snapshot| {
                                if (snapshot.commit.eql(revision)) {
                                    const str = try snapshot.getContent(allocator);
                                    defer allocator.free(str);
                                    try buffer.appendSlice(allocator, str);
                                }
                            },
                        }
                    }
                },
            }
        }

        return try buffer.toOwnedSlice(allocator);
    }

    pub fn getBase(self: ParsedFile, allocator: mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).empty;
        for (self.segments, 0..) |segment, i| {
            switch (segment) {
                .no_conflict => |no_conflict| {
                    const str = try no_conflict.toString(allocator);
                    defer allocator.free(str);

                    try buffer.appendSlice(allocator, str);
                    if (i < self.segments.len - 1) {
                        try buffer.append(allocator, '\n');
                    }
                },
                .conflict => |conflict| {
                    for (conflict.conflict_markers) |conflict_marker| {
                        switch (conflict_marker) {
                            .diff => |diff| {
                                const str = try diff.getBase(allocator);
                                defer allocator.free(str);
                                try buffer.appendSlice(allocator, str);
                            },
                            .snapshot => {},
                        }
                    }
                },
            }
        }

        return try buffer.toOwnedSlice(allocator);
    }

    pub fn getRevisions(self: ParsedFile, allocator: mem.Allocator) ![]Revision {
        var revisions: std.ArrayHashMap(Revision, void, Revision.HashContext, false) = .init(allocator);
        defer revisions.deinit();

        for (self.segments) |segment| {
            switch (segment) {
                .no_conflict => {},
                .conflict => |conflict| {
                    for (conflict.conflict_markers) |conflict_marker| {
                        switch (conflict_marker) {
                            .diff => |diff| {
                                try revisions.put(diff.to, {});
                            },
                            .snapshot => |snapshot| {
                                try revisions.put(snapshot.commit, {});
                            },
                        }
                    }
                },
            }
        }

        var list = std.ArrayList(Revision).empty;
        for (revisions.keys()) |rev| {
            try list.append(allocator, rev);
        }

        return list.toOwnedSlice(allocator);
    }
};

test "ParsedFile.getRevisions" {
    const allocator = std.testing.allocator;
    var parsed_file = try parse(allocator,
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
    defer parsed_file.deinit(allocator);

    const output = try parsed_file.getRevisions(allocator);
    defer allocator.free(output);

    try testing.expectEqual(output.len, 2);
}

test "ParsedFile.getBase" {
    const allocator = std.testing.allocator;
    var parsed_file = try parse(allocator,
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
    defer parsed_file.deinit(allocator);
    const output = try parsed_file.getBase(allocator);
    defer allocator.free(output);

    try testing.expectEqualStrings(
        \\function before() {
        \\  console.log("before test");
        \\}
    , output);
}

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
        for (self.lines, 0..) |line, line_num| {
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

    fn deinit(self: Conflict, allocator: mem.Allocator) void {
        for (self.conflict_markers) |conflict_marker| {
            switch (conflict_marker) {
                .diff => |diff| {
                    diff.deinit(allocator);
                },
                .snapshot => |snapshot| {
                    snapshot.deinit(allocator);
                },
            }
        }
        allocator.free(self.conflict_markers);
    }

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

    fn getBase(self: Diff, allocator: mem.Allocator) ![]const u8 {
        return try self.getContent(allocator, self.from.commitID);
    }

    fn getContent(self: Diff, allocator: mem.Allocator, commitID: []const u8) ![]const u8 {
        if (mem.eql(u8, self.from.commitID, commitID)) {
            var buffer = std.ArrayList(u8).empty;
            defer buffer.deinit(allocator);
            for (self.diff_lines) |diff_line| {
                switch (diff_line) {
                    .delete,
                    .text,
                    => |text| {
                        try buffer.appendSlice(allocator, text);
                        try buffer.append(allocator, '\n');
                    },
                    .add => {},
                }
            }

            return try buffer.toOwnedSlice(allocator);
        } else if (mem.eql(u8, self.to.commitID, commitID)) {
            var buffer = std.ArrayList(u8).empty;
            defer buffer.deinit(allocator);
            for (self.diff_lines) |diff_line| {
                switch (diff_line) {
                    .add,
                    .text,
                    => |text| {
                        try buffer.appendSlice(allocator, text);
                        try buffer.append(allocator, '\n');
                    },
                    .delete => {},
                }
            }

            return try buffer.toOwnedSlice(allocator);
        } else {
            return "";
        }
    }

    fn deinit(self: Diff, allocator: mem.Allocator) void {
        allocator.free(self.diff_lines);
    }

    const Parser = struct {
        from: ?Revision,
        to: ?Revision,
        // rebasedCommitID: ?[]const u8,
        diff_lines: std.ArrayList(DiffLine),

        fn reset(self: *Parser) void {
            self.*.from = null;
            self.*.to = null;
            self.*.diff_lines = .empty;
        }

        fn new() Parser {
            return Parser{
                .from = null,
                .to = null,
                .diff_lines = .empty,
            };
        }

        fn parse(self: *Parser, line: []const u8) !void {
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

        fn toDiff(self: *Parser, allocator: mem.Allocator) !Diff {
            defer self.reset();
            const diff_lines = try self.diff_lines.toOwnedSlice(allocator);
            defer self.diff_lines.deinit(allocator);
            return Diff{
                .to = self.to.?,
                .from = self.from.?,
                .diff_lines = diff_lines,
            };
        }
    };
};

test "Diff.Partial.parse" {
    var diff = Diff.Parser.new();
    try diff.parse("%%%%%%% diff from: ulopzqqq 6606ba58 \"a\"");
    try std.testing.expectEqualDeep("ulopzqqq", diff.from.?.changeID);
}

const DiffLine = union(enum) {
    text: []const u8,
    delete: []const u8,
    add: []const u8,

    const Marker = enum {
        add,
        delete,
        text,

        fn detect(line: []const u8) DiffLine.Marker {
            if (mem.startsWith(u8, line, "-")) return .delete;
            if (mem.startsWith(u8, line, "+")) return .add;
            return .text;
        }
    };

    fn parse(line: []const u8) !DiffLine {
        const marker = DiffLine.Marker.detect(line);
        switch (marker) {
            .add => {
                return DiffLine{ .add = line[1..] };
            },
            .delete => {
                return DiffLine{ .delete = line[1..] };
            },
            .text => {
                return DiffLine{ .text = line[1..] };
            },
        }
    }
};

// marker: +++++++
const Snapshot = struct {
    commit: Revision,
    lines: []const []const u8,

    fn deinit(self: Snapshot, allocator: mem.Allocator) void {
        allocator.free(self.lines);
    }

    fn getContent(self: Snapshot, allocator: mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).empty;
        for (self.lines) |line| {
            try buffer.appendSlice(allocator, line);
            try buffer.append(allocator, '\n');
        }

        return try buffer.toOwnedSlice(allocator);
    }

    const Parser = struct {
        commit: ?Revision,
        lines: std.ArrayList([]const u8),

        fn reset(self: *Parser) void {
            self.*.commit = null;
            self.*.lines = .empty;
        }

        fn new() Snapshot.Parser {
            return Snapshot.Parser{
                .commit = null,
                .lines = .empty,
            };
        }

        fn parse(self: *Parser, allocator: mem.Allocator, line: []const u8) !void {
            const marker = Marker.detect(line);
            switch (marker) {
                .snapshot => {
                    self.*.commit = try Revision.parseSnapshot(line);
                },
                else => {
                    try self.lines.append(allocator, line);
                },
            }
        }
        fn toSnapshot(self: *Parser, allocator: mem.Allocator) !Snapshot {
            defer self.reset();
            const lines = try self.lines.toOwnedSlice(allocator);
            defer self.lines.deinit(allocator);
            return Snapshot{
                .commit = self.commit.?,
                .lines = lines,
            };
        }
    };
};

// a.k.a Commit
pub const Revision = struct {
    changeID: []const u8,
    commitID: []const u8,
    description: []const u8,

    pub fn eql(self: Revision, b: Revision) bool {
        return mem.eql(u8, self.changeID, b.changeID) and
            mem.eql(u8, self.commitID, b.commitID);
    }

    const HashContext = struct {
        pub fn hash(_: @This(), key: Revision) u32 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(key.changeID);
            hasher.update(key.commitID);
            return @truncate(hasher.final());
        }

        pub fn eql(_: @This(), a: Revision, b: Revision, _: usize) bool {
            return a.eql(b);
        }
    };

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

    fn parseSnapshot(line: []const u8) !Revision {
        //+++++++ vsqszzzy af5bacc0 "c"
        var it = mem.splitScalar(u8, line, ' ');
        _ = it.next();

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

test "Revision.parseLine1" {
    const output = try Revision.parseLine1("%%%%%%% diff from: ulopzqqq 6606ba58 \"a + b = c\"");
    try std.testing.expectEqualStrings("ulopzqqq", output.changeID);
    try std.testing.expectEqualStrings("6606ba58", output.commitID);
    try std.testing.expectEqualStrings("a + b = c", output.description);
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

fn parseQuoted(line: []const u8) ![]const u8 {
    const first = std.mem.indexOfScalar(u8, line, '"') orelse return error.GenericError;
    const rest = line[(first + 1)..];
    const second_rel = std.mem.indexOfScalar(u8, rest, '"') orelse return error.GenericError;

    return rest[0..second_rel];
}
