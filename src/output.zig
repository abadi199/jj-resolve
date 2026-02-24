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
    text: []u8,
};
