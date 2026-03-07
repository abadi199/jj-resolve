const parser = @import("parser.zig");
const std = @import("std");
const gtk = @import("gtk");

pub const OutputFile = struct {
    segments: []Segment,

    pub fn from(allocator: std.mem.Allocator, parsed_file: parser.ParsedFile) !OutputFile {
        var list = std.ArrayList(Segment).empty;
        for (parsed_file.segments) |segment| {
            switch (segment) {
                .no_conflict => |no_conflict| {
                    const input = try no_conflict.toString(allocator);
                    const text = try allocator.dupe(u8, input);
                    try list.append(
                        allocator,
                        Segment{ .no_conflict = NoConflict{ .text = text } },
                    );
                },
                .conflict => |conflict| {
                    const conflict_index = conflict.index;
                    try list.append(
                        allocator,
                        Segment{ .conflict = Conflict{
                            .conflict_index = conflict_index,
                            .total = conflict.total,
                            .text = "",
                        } },
                    );
                },
            }
        }
        return .{
            .segments = try list.toOwnedSlice(allocator),
        };
    }

    pub fn deinit(self: OutputFile, allocator: std.mem.Allocator) void {
        allocator.free(self.segments);
    }

    pub fn toContent(self: OutputFile, allocator: std.mem.Allocator) ![]const u8 {
        var stringBuffer = std.ArrayList(u8).empty;
        defer stringBuffer.deinit(allocator);
        for (self.segments) |segment| {
            switch (segment) {
                .conflict => |conflict| {
                    try stringBuffer.append(allocator, '\n');
                    try stringBuffer.appendSlice(allocator, conflict.text);
                },
                .no_conflict => |no_conflict| {
                    try stringBuffer.appendSlice(allocator, no_conflict.text);
                },
            }
        }

        return try stringBuffer.toOwnedSlice(allocator);
    }
};

const Segment = union(enum) {
    conflict: Conflict,
    no_conflict: NoConflict,
};

const NoConflict = struct {
    text: []u8,
};

const Conflict = struct {
    conflict_index: u32,
    total: u32,
    text: []const u8,
};
