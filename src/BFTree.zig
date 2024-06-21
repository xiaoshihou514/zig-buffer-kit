//! Implementation of balanced Fenwick tree.
//! A Fenwick tree stores intervals, this implementation only stores
//! the start of the interval since intervals are next to each other.
//! It supports the following operations:
//!     - get: O(log n)
//!     - set: O(log n)
//!     - insert: O(log n)

const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const expectEqual = @import("utils.zig").expectEqual;

/// Balanced Fenwick tree node
const BFNode = struct {
    /// relative offset (in bytes)
    r_off: i128,
    /// relative line number
    r_lnum: i64,
    /// optional left child
    left: ?*BFNode = null,
    /// optional right child
    right: ?*BFNode = null,
    const print_indent = 2;

    fn printHelper(node: ?*BFNode, indent: u16) void {
        for (0..indent) |_| {
            print(" ", .{});
        }
        if (node) |n| {
            print("r_off: {}, r_lnum: {} {{\n", .{ n.r_off, n.r_lnum });
            printHelper(n.left, indent + print_indent);
            printHelper(n.right, indent + print_indent);
            for (0..indent) |_| {
                print(" ", .{});
            }
            print("}}\n", .{});
        } else {
            print("null\n", .{});
        }
    }

    pub fn printONode(node: *BFNode) void {
        print("\n", .{});
        printHelper(node, 0);
    }

    fn bufPrintHelper(node: ?*BFNode, indent: u16, buf: []u8) ![]u8 {
        var b = buf;
        for (0..indent) |_| {
            _ = try std.fmt.bufPrint(b, " ", .{});
            b = b[1..];
        }
        if (node) |n| {
            var s = try std.fmt.bufPrint(b, "r_off: {}, r_lnum: {} {{\n", .{ n.r_off, n.r_lnum });
            b = b[s.len..];
            b = try bufPrintHelper(n.left, indent + print_indent, b);
            b = try bufPrintHelper(n.right, indent + print_indent, b);
            for (0..indent) |_| {
                _ = try std.fmt.bufPrint(b, " ", .{});
                b = b[1..];
            }
            _ = try std.fmt.bufPrint(b, "}}\n", .{});
            b = b[2..];
        } else {
            _ = try std.fmt.bufPrint(b, "null\n", .{});
            b = b[5..];
        }
        return b;
    }

    pub fn bufPrintONode(node: *BFNode, buf: []u8) !void {
        _ = try bufPrintHelper(node, 0, buf);
    }
};

/// A balanced Fenwick tree
const BFTree = struct {
    /// root of the tree
    root: ?*BFNode,
    /// max line number
    max: u32,

    /// initializes BFTree from utf8 string
    pub fn init(src: []const u8, allocator: Allocator) !BFTree {
        // if it's empty we won't bother
        if (src.len == 0) {
            return BFTree{
                .root = null,
                .max = 0,
            };
        }
        // try interpret bytes as utf8
        var iter = (std.unicode.Utf8View.init(src) catch |e| switch (e) {
            error.InvalidUtf8 => {
                // print raw invalid data
                print("Offsets.init: invalid utf8\n", .{});
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
        // turns array into tree
        return BFTree{
            .root = try init_tree(list, 0, @intCast(list.items.len), 0, 0, allocator),
            .max = @intCast(list.items.len),
        };
    }

    /// recursively initializes a tree, start inclusive, end exclusive
    fn init_tree(offsets: std.ArrayList(u64), start: u32, end: u32, parent_r_off: i128, parent_r_lnum: i64, allocator: Allocator) !?*BFNode {
        if (start == end) {
            return null;
        }
        var node = try allocator.create(BFNode);
        const off: i128 = offsets.items[(start + end) / 2];
        const lnum: u32 = (start + end) / 2;
        node.* = BFNode{
            .r_off = off - parent_r_off,
            .r_lnum = lnum - parent_r_lnum,
            .left = try init_tree(offsets, start, lnum, off, lnum, allocator),
            .right = try init_tree(offsets, lnum + 1, end, off, lnum, allocator),
        };
        return node;
    }

    /// deinitializes the tree structure
    fn deinit_tree(tree: ?*BFNode, allocator: Allocator) !void {
        if (tree) |t| {
            try deinit_tree(t.left, allocator);
            try deinit_tree(t.right, allocator);
            allocator.destroy(t);
        }
    }

    /// deinitializes a BFTree
    pub fn deinit(self: *BFTree, allocator: Allocator) !void {
        try deinit_tree(self.root, allocator);
        self.* = undefined;
    }

    pub const OutOfBoundError = error{BFTreeIndexOutOfBound};
    /// gets start of interval given the index
    pub fn get(self: *BFTree, lnum: u32) OutOfBoundError!?u64 {
        if (lnum > self.max) {
            return error.BFTreeIndexOutOfBound;
        }
        if (lnum == 0) {
            return 0;
        }

        var lnum_acc: i64 = 0;
        var off_acc: i128 = 0;
        var node = self.root;
        while (node != null) {
            off_acc += node.?.r_off;
            lnum_acc += node.?.r_lnum;
            if (lnum_acc == lnum) {
                return @intCast(off_acc);
            } else if (lnum_acc < lnum) {
                node = node.?.right;
            } else {
                node = node.?.left;
            }
        }

        return null;
    }

    /// sets start of interval of line `lnum`
    pub fn set(self: *BFTree, lnum: u32, off: u64) OutOfBoundError!void {
        if (lnum > self.max or lnum == 0) {
            return error.BFTreeIndexOutOfBound;
        }
        // TODO
    }
};

test "init: empty" {
    const empty = "";
    var bft = try BFTree.init(empty, testing.allocator);
    try expectEqual(0, bft.max);
    try expectEqual(null, bft.root);
    try bft.deinit(testing.allocator);
}

test "init: non-empty" {
    const src = "const\nvar\n";
    var bft = try BFTree.init(src, testing.allocator);
    try expectEqual(3, bft.max);
    var expected =
        \\r_off: 6, r_lnum: 1 {
        \\  r_off: -6, r_lnum: -1 {
        \\    null
        \\    null
        \\  }
        \\  r_off: 4, r_lnum: 1 {
        \\    null
        \\    null
        \\  }
        \\}
    ;
    var buf = try testing.allocator.alloc(u8, 256);
    try BFNode.bufPrintONode(bft.root.?, buf);
    try testing.expect(std.mem.eql(u8, expected, buf[0..expected.len]));
    try bft.deinit(testing.allocator);
    testing.allocator.free(buf);
}

test "init: edge cases" {
    const src = "\nzig\nc\nrust\ncpp\n";
    var bft = try BFTree.init(src, testing.allocator);
    try expectEqual(6, bft.max);
    var expected =
        \\r_off: 7, r_lnum: 3 {
        \\  r_off: -6, r_lnum: -2 {
        \\    r_off: -1, r_lnum: -1 {
        \\      null
        \\      null
        \\    }
        \\    r_off: 4, r_lnum: 1 {
        \\      null
        \\      null
        \\    }
        \\  }
        \\  r_off: 9, r_lnum: 2 {
        \\    r_off: -4, r_lnum: -1 {
        \\      null
        \\      null
        \\    }
        \\    null
        \\  }
        \\}
    ;
    var buf = try testing.allocator.alloc(u8, 512);
    try BFNode.bufPrintONode(bft.root.?, buf);
    try testing.expect(std.mem.eql(u8, expected, buf[0..expected.len]));
    try bft.deinit(testing.allocator);
    testing.allocator.free(buf);
}

test "get" {
    const src = "a\nf\noo\nbbaar\nb\naaaa\nzzz\n";
    var bft = try BFTree.init(src, testing.allocator);
    const offs = [8]u64{ 0, 2, 4, 7, 13, 15, 20, 24 };
    for (0..offs.len) |i| {
        try expectEqual(offs[i], bft.get(@intCast(i)));
    }
    try bft.deinit(testing.allocator);
}

test "set" {
    const src = "a\nf\noo\nbbaar\nb\naaaa\nzzz\n";
    var bft = try BFTree.init(src, testing.allocator);
    const offs = [8]u64{ 0, 2, 4, 7, 13, 15, 20, 24 };
    try bft.set(3, 10);
    for (0..3) |i| {
        try expectEqual(offs[i], bft.get(@intCast(i)));
    }
    for (3..offs.len) |i| {
        try expectEqual(offs[i] + 3, bft.get(@intCast(i)));
    }
    try bft.deinit(testing.allocator);
}
