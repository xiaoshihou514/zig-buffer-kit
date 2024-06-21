//! A linear allocation with gaps in between

const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;
const mem = std.mem;
const testing = std.testing;
const expectEqual = @import("utils.zig").expectEqual;

/// Offset node item
const ONode = struct {
    /// relative offset (in bytes)
    r_off: i128,
    /// relative line number
    r_lnum: i64,
    /// optional left child
    left: ?*ONode = null,
    /// optional right child
    right: ?*ONode = null,
};

/// Represents where all the line starts in a buffer
const Offsets = struct {
    /// root of the tree
    root: ?*ONode,
    /// max line number
    max: u32,

    /// initializes offset metadata from utf8 string
    pub fn init(src: []const u8, allocator: mem.Allocator) !Offsets {
        // if it's empty we won't bother
        if (src.len == 0) {
            return Offsets{
                .root = null,
                .max = 0,
            };
        }
        // try interpret bytes as utf8
        var iter = (std.unicode.Utf8View.init(src) catch |e| switch (e) {
            error.InvalidUtf8 => {
                print("Offsets.init: invalid utf8\n", .{});
                // print raw invalid data
                for (src) |b| {
                    print("{x} ", .{b});
                }
                print("\n", .{});
                return error.InvalidUtf8;
            },
        }).iterator();
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer std.debug.assert(gpa.deinit() == .ok);
        var list = std.ArrayList(u64).init(gpa.allocator());
        defer list.deinit();

        // first line always starts at zero
        try list.append(0);
        var i: u64 = 0;
        while (iter.nextCodepointSlice()) |c| {
            if (c.len == 1 and c[0] == '\n') {
                // record pos of line start
                try list.append(i + 1);
            }
            i += c.len;
        }
        return Offsets{
            .root = try init_tree(list, 0, @intCast(list.items.len), 0, 0, allocator),
            .max = @intCast(list.items.len),
        };
    }

    /// recursively initializes a tree, start inclusive, end exclusive
    fn init_tree(offsets: std.ArrayList(u64), start: u32, end: u32, parent_r_off: i128, parent_r_lnum: i64, allocator: mem.Allocator) !*ONode {
        var node = try allocator.create(ONode);
        if (start + 1 == end) {
            node.* = ONode{
                .r_off = @as(i128, offsets.items[start]) - parent_r_off,
                .r_lnum = @as(i64, start) - parent_r_lnum,
            };
            return node;
        }
        const off: i128 = offsets.items[(start + end) / 2];
        const lnum: u32 = (start + end) / 2;
        node.* = ONode{
            .r_off = off + parent_r_off,
            .r_lnum = lnum,
            .left = try init_tree(offsets, start, lnum, off, lnum, allocator),
            .right = try init_tree(offsets, lnum + 1, end, off, lnum, allocator),
        };
        return node;
    }
};

test "init offsets: empty" {
    const empty = "";
    const offs = try Offsets.init(empty, testing.allocator);
    try expectEqual(0, offs.max);
    try expectEqual(null, offs.root);
}
