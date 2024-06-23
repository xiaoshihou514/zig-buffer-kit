//! Implementation of balanced offset tree.
//! Given a range, a BOTree stores closed intervals [x0,x1], [x1, x2], ..., [xn-1, xn].
//! Only the start of the interval is stored since intervals are next to each other.
//! It supports the following operations:
//!     - get(lnum)
//!     - set(lnum, off)
//!     - incr(lnum, delta)
//!     - insertAfter(lnum)
//!     - remove(lnum)

const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const utils = @import("utils.zig");
const expectEqual = @import("utils.zig").expectEqual;

/// Balanced Fenwick tree node
const BONode = struct {
    /// relative offset (in bytes)
    r_off: i128,
    /// relative line number
    r_lnum: i64,
    /// optional left child
    left: ?*BONode = null,
    /// optional right child
    right: ?*BONode = null,
    /// optional parent
    parent: ?*BONode = null,

    const print_indent = 2;

    fn printHelper(node: ?*BONode, indent: u16) void {
        for (0..indent) |_| {
            print(" ", .{});
        }
        if (node) |n| {
            print("r_lnum: {}, r_off: {} {{\n", .{ n.r_lnum, n.r_off });
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

    /// print structure of tree to stderr
    pub fn printONode(node: *BONode) void {
        print("\n", .{});
        printHelper(node, 0);
    }

    fn bufPrintHelper(node: ?*BONode, indent: u16, buf: []u8) ![]u8 {
        var b = buf;
        for (0..indent) |_| {
            _ = try std.fmt.bufPrint(b, " ", .{});
            b = b[1..];
        }
        if (node) |n| {
            const s = try std.fmt.bufPrint(b, "r_lnum: {}, r_off: {} {{\n", .{ n.r_lnum, n.r_off });
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

    /// print structure of tree to buffer
    pub fn bufPrintONode(node: *BONode, buf: []u8) !void {
        _ = try bufPrintHelper(node, 0, buf);
    }

    /// print single node
    pub fn printSingle(self: ?*BONode, name: []const u8) void {
        if (self == null) {
            print("{s}: null\n", .{name});
        } else {
            print("{s}: r_lnum = {d}, r_off = {d}\n", .{ name, self.?.r_lnum, self.?.r_off });
        }
    }

    pub fn insert_node(self: *BONode, offset: u64, lnum: u32, oacc: i128, lacc: i64, allocator: Allocator) !*BONode {
        const lnum_acc = lacc + self.r_lnum;
        const off_acc = oacc + self.r_off;
        if (off_acc > offset) {
            // go left
            if (self.left) |left| {
                self.left = try insert_node(left, offset, lnum, off_acc, lnum_acc, allocator);
            } else {
                // insert right here
                self.left = try allocator.create(BONode);
                self.left.?.* = BONode{
                    .r_lnum = lnum - lnum_acc,
                    .r_off = offset - off_acc,
                    .parent = self,
                };
            }
        } else if (off_acc < offset) {
            // go right
            if (self.right) |right| {
                self.right = try insert_node(right, offset, lnum, off_acc, lnum_acc, allocator);
            } else {
                // insert right here
                self.right = try allocator.create(BONode);
                self.right.?.* = BONode{
                    .r_lnum = lnum - lnum_acc,
                    .r_off = offset - off_acc,
                    .parent = self,
                };
            }
        } else {
            unreachable;
        }
        const bf = height(self.left) - height(self.right);
        if (bf > 1 and lnum < lnum_acc + self.left.?.r_lnum) {
            return self.rotate_right();
        }
        if (bf < -1 and lnum > lnum_acc + self.right.?.r_lnum) {
            return self.rotate_left();
        }
        if (bf > 1 and lnum > lnum_acc + self.left.?.r_lnum) {
            self.left = self.left.?.rotate_left();
            return self.rotate_right();
        }
        if (bf < -1 and lnum < lnum_acc + self.right.?.r_lnum) {
            self.right = self.right.?.rotate_right();
            return self.rotate_left();
        }
        return self;
    }

    /// gets height of tree
    pub fn height(self: ?*BONode) i64 {
        if (self) |it| {
            return @max(height(it.left), height(it.right)) + 1;
        } else {
            return 0;
        }
    }

    fn rotate_left(self: *BONode) *BONode {
        // rotate nodes
        const B = self.right.?;
        const Y = B.left;

        B.left = self;
        self.right = Y;

        B.parent = self.parent;
        self.parent = B;

        // fix relative fields
        const Boff = B.r_off + self.r_off;
        const Blnum = B.r_lnum + self.r_lnum;
        const off = -B.r_off;
        const lnum = -B.r_lnum;

        if (Y) |y| {
            y.r_off += B.r_off;
            y.r_lnum += B.r_lnum;
            y.parent = self;
        }

        B.r_off = Boff;
        B.r_lnum = Blnum;
        self.r_off = off;
        self.r_lnum = lnum;

        return B;
    }

    fn rotate_right(self: *BONode) *BONode {
        // rotate nodes
        const A = self.left.?;
        const Y = A.right;

        A.right = self;
        self.left = Y;

        A.parent = self.parent;
        self.parent = A;

        // fix relative fields
        const Aoff = A.r_off + self.r_off;
        const Alnum = A.r_lnum + self.r_lnum;
        const off = -A.r_off;
        const lnum = -A.r_lnum;

        if (Y) |y| {
            y.r_off += A.r_off;
            y.r_lnum += A.r_lnum;
            y.parent = self;
        }

        A.r_off = Aoff;
        A.r_lnum = Alnum;
        self.r_off = off;
        self.r_lnum = lnum;

        return A;
    }

    fn balanced(self: ?*BONode) bool {
        if (self == null) {
            return true;
        }
        return (@abs( //
            height(self.?.left) - height(self.?.right) //
        )) <= 1 //
        and balanced(self.?.left) //
        and balanced(self.?.right);
    }
};

/// A balanced offset tree
const BOTree = struct {
    /// root of the tree
    root: *BONode,
    /// max line number
    max: u32,
    /// allocator
    allocator: Allocator,

    /// initializes BOTree from utf8 string encoded in LF
    pub fn init(src: []const u8, allocator: Allocator) !BOTree {
        try testing.expect(src.len > 0);
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
        return BOTree{
            .root = (try init_tree(list, 0, @intCast(list.items.len), 0, 0, allocator, null)).?,
            .max = @intCast(list.items.len),
            .allocator = allocator,
        };
    }

    /// recursively initializes a tree, start inclusive, end exclusive
    fn init_tree(offsets: std.ArrayList(u64), start: u32, end: u32, parent_r_off: i128, parent_r_lnum: i64, allocator: Allocator, parent: ?*BONode) !?*BONode {
        if (start == end) {
            return null;
        }
        const node = try allocator.create(BONode);
        const off: i128 = offsets.items[(start + end) / 2];
        const lnum: u32 = (start + end) / 2;
        node.* = BONode{
            .r_off = off - parent_r_off,
            .r_lnum = lnum - parent_r_lnum,
            .left = try init_tree(offsets, start, lnum, off, lnum, allocator, node),
            .right = try init_tree(offsets, lnum + 1, end, off, lnum, allocator, node),
            .parent = parent,
        };
        return node;
    }

    /// deinitializes the tree structure
    fn deinit_tree(tree: ?*BONode, allocator: Allocator) void {
        if (tree) |t| {
            deinit_tree(t.left, allocator);
            deinit_tree(t.right, allocator);
            allocator.destroy(t);
        }
    }

    /// deinitializes a BOTree
    pub fn deinit(self: *BOTree, allocator: Allocator) void {
        deinit_tree(self.root, allocator);
        self.* = undefined;
    }

    pub const OutOfBoundError = error{BOTreeIndexOutOfBound};
    /// gets start of interval given the index
    pub fn get(self: *BOTree, lnum: u32) OutOfBoundError!u64 {
        if (lnum >= self.max) {
            print("get: lnum: {d}, max: {d} not allowed\n", .{ lnum, self.max });
            return error.BOTreeIndexOutOfBound;
        }
        if (lnum == 0) {
            return 0;
        }

        var lnum_acc: i64 = 0;
        var off_acc: i128 = 0;
        var node: ?*BONode = self.root;
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

        unreachable;
    }

    /// sets start of interval of line `lnum`
    pub fn set(self: *BOTree, lnum: u32, off: u64) OutOfBoundError!void {
        if (lnum >= self.max or lnum == 0) {
            print("set: lnum: {d}, max: {d} not allowed\n", .{ lnum, self.max });
            return error.BOTreeIndexOutOfBound;
        }
        var lnum_acc: i64 = 0;
        var off_acc: i128 = 0;
        var node: ?*BONode = self.root;
        while (node != null) {
            off_acc += node.?.r_off;
            lnum_acc += node.?.r_lnum;
            if (lnum_acc == lnum) {
                break;
            } else if (lnum_acc < lnum) {
                node = node.?.right;
            } else {
                node = node.?.left;
            }
        }

        // change in r_off
        const delta = off - off_acc;
        if (delta == 0) {
            return;
        }
        var child = node.?.left;
        if (child) |c| {
            c.r_off -= delta;
        }
        var left = true;

        // trace upwards
        // invariant: subtree of node is fixed
        while (node.?.parent != null) {
            child = node.?;
            node = node.?.parent;
            if (child == node.?.left) {
                // child is left of node and we reached child via its right node
                // in this case child.lnum < target.lnum, hence needs to be "corrected"
                if (!left) {
                    child.?.r_off -= delta;
                }
                left = true;
            } else {
                // child is right of node and we reached child via its left node
                // in this case chidl.lnum > target.lnum, we change as required
                if (left) {
                    child.?.r_off += delta;
                }
                left = false;
            }
        }
        if (left) {
            node.?.r_off += delta;
        }
    }
    /// increments start of interval of line `lnum`
    pub fn incr(self: *BOTree, lnum: u32, off: i128) OutOfBoundError!void {
        if (lnum >= self.max or lnum == 0) {
            print("incr: lnum: {d}, max: {d} not allowed\n", .{ lnum, self.max });
            return error.BOTreeIndexOutOfBound;
        }
        if (off == 0) {
            return;
        }
        var lnum_acc: i64 = 0;
        var off_acc: i128 = 0;
        var node: ?*BONode = self.root;
        while (node != null) {
            off_acc += node.?.r_off;
            lnum_acc += node.?.r_lnum;
            if (lnum_acc == lnum) {
                break;
            } else if (lnum_acc < lnum) {
                node = node.?.right;
            } else {
                node = node.?.left;
            }
        }

        // change in r_off
        var child = node.?.left;
        if (child) |c| {
            c.r_off -= off;
        }
        var left = true;

        // trace upwards
        // invariant: subtree of node is fixed
        while (node.?.parent != null) {
            child = node.?;
            node = node.?.parent;
            if (child == node.?.left) {
                // child is left of node and we reached child via its right node
                // in this case child.lnum < target.lnum, hence needs to be "corrected"
                if (!left) {
                    child.?.r_off -= off;
                }
                left = true;
            } else {
                // child is right of node and we reached child via its left node
                // in this case chidl.lnum > target.lnum, we change as required
                if (left) {
                    child.?.r_off += off;
                }
                left = false;
            }
        }
        if (left) {
            node.?.r_off += off;
        }
    }

    /// decrements start of interval of line `lnum`
    pub fn decr(self: *BOTree, lnum: u32, off: i128) OutOfBoundError!void {
        try incr(self, lnum, -off);
    }

    /// adds a new offset of 0 `after` idx, preserves tree balance
    pub fn insertAfter(self: *BOTree, lnum: u32) !void {
        if (lnum >= self.max) {
            print("insertAfter: lnum: {d}, max: {d} not allowed\n", .{ lnum, self.max });
            return error.BOTreeIndexOutOfBound;
        }
        const off = if (lnum == self.max - 1) (try get(self, lnum)) + 1 else (try get(self, lnum + 1));
        if (lnum != self.max - 1) {
            // shift offset and lnum for lnum + 1 onwards
            const target = lnum + 1;
            var lnum_acc: i64 = 0;
            var off_acc: i128 = 0;
            var node: ?*BONode = self.root;
            while (node != null) {
                off_acc += node.?.r_off;
                lnum_acc += node.?.r_lnum;
                if (lnum_acc == target) {
                    break;
                } else if (lnum_acc < target) {
                    node = node.?.right;
                } else {
                    node = node.?.left;
                }
            }

            // change in r_off
            var child = node.?.left;
            if (child) |c| {
                c.r_off -= 1;
                c.r_lnum -= 1;
            }
            var left = true;

            // trace upwards
            while (node.?.parent != null) {
                child = node.?;
                node = node.?.parent;
                if (child == node.?.left) {
                    // child is left of node and we reached child via its right node
                    if (!left) {
                        child.?.r_off -= 1;
                        child.?.r_lnum -= 1;
                    }
                    left = true;
                } else {
                    // child is right of node and we reached child via its left node
                    if (left) {
                        child.?.r_off += 1;
                        child.?.r_lnum += 1;
                    }
                    left = false;
                }
            }
            if (left) {
                node.?.r_off += 1;
                node.?.r_lnum += 1;
            }
        }

        // print("shifted:\n", .{});
        // self.root.printONode();

        self.root = try self.root.insert_node(off, lnum + 1, 0, 0, self.allocator);
        self.max += 1;
    }

    /// remove offset at idx, preserves tree balance
    pub fn remove(self: *BOTree, lnum: u32) !void {
        if (lnum >= self.max or lnum == 0) {
            print("remove: lnum: {d}, max: {d} not allowed\n", .{ lnum, self.max });
            return error.BOTreeIndexOutOfBound;
        }
        // TODO
        unreachable;
    }
};

test "init: simple" {
    const src = "const\nvar\n";
    var bft = try BOTree.init(src, testing.allocator);
    defer bft.deinit(testing.allocator);
    try expectEqual(3, bft.max);
    const expected =
        \\r_lnum: 1, r_off: 6 {
        \\  r_lnum: -1, r_off: -6 {
        \\    null
        \\    null
        \\  }
        \\  r_lnum: 1, r_off: 4 {
        \\    null
        \\    null
        \\  }
        \\}
    ;
    var buf = try testing.allocator.alloc(u8, 256);
    try BONode.bufPrintONode(bft.root, buf);
    try testing.expect(std.mem.eql(u8, expected, buf[0..expected.len]));
    testing.allocator.free(buf);
}

test "init: edge cases" {
    const src = "\nzig\nc\nrust\ncpp\n";
    var bft = try BOTree.init(src, testing.allocator);
    defer bft.deinit(testing.allocator);
    try expectEqual(6, bft.max);
    const expected =
        \\r_lnum: 3, r_off: 7 {
        \\  r_lnum: -2, r_off: -6 {
        \\    r_lnum: -1, r_off: -1 {
        \\      null
        \\      null
        \\    }
        \\    r_lnum: 1, r_off: 4 {
        \\      null
        \\      null
        \\    }
        \\  }
        \\  r_lnum: 2, r_off: 9 {
        \\    r_lnum: -1, r_off: -4 {
        \\      null
        \\      null
        \\    }
        \\    null
        \\  }
        \\}
    ;
    var buf = try testing.allocator.alloc(u8, 512);
    try BONode.bufPrintONode(bft.root, buf);
    try testing.expect(std.mem.eql(u8, expected, buf[0..expected.len]));
    testing.allocator.free(buf);
}

test "get" {
    const input = try utils.genInput(testing.allocator);
    const str = input.str;
    const offs = input.breaks;
    defer str.deinit();
    defer offs.deinit();

    var bft = try BOTree.init(str.items, testing.allocator);
    defer bft.deinit(testing.allocator);

    const len: u32 = @intCast(offs.items.len);
    try expectEqual(len, bft.max);
    try testing.expect(bft.root.balanced());
    for (0..len) |j| {
        try expectEqual(offs.items[j], bft.get(@intCast(j)));
    }
}

test "set" {
    const input = try utils.genInput(testing.allocator);
    const str = input.str;
    const offs = input.breaks;
    defer str.deinit();
    defer offs.deinit();

    var bft = try BOTree.init(str.items, testing.allocator);
    defer bft.deinit(testing.allocator);

    var r = utils.newRand();
    if (offs.items.len == 1) {
        return;
    }
    const idx = r.intRangeAtMost(u32, 1, @intCast(offs.items.len - 1));
    const newOff: u64 = (try bft.get(idx)) + 42;
    try bft.set(@intCast(idx), newOff);

    for (0..idx) |i| {
        try expectEqual(offs.items[i], bft.get(@intCast(i)));
    }
    for (idx..offs.items.len) |i| {
        try expectEqual(offs.items[i] + 42, bft.get(@intCast(i)));
    }
}

test "incr" {
    const input = try utils.genInput(testing.allocator);
    const str = input.str;
    const offs = input.breaks;
    defer str.deinit();
    defer offs.deinit();

    var bft = try BOTree.init(str.items, testing.allocator);
    defer bft.deinit(testing.allocator);

    var r = utils.newRand();
    if (offs.items.len == 1) {
        return;
    }
    const idx = r.intRangeAtMost(u32, 1, @intCast(offs.items.len - 1));
    try bft.incr(@intCast(idx), 42);

    for (0..idx) |i| {
        try expectEqual(offs.items[i], bft.get(@intCast(i)));
    }
    for (idx..offs.items.len) |i| {
        try expectEqual(offs.items[i] + 42, bft.get(@intCast(i)));
    }
}

test "decr" {
    const input = try utils.genInput(testing.allocator);
    const str = input.str;
    const offs = input.breaks;
    defer str.deinit();
    defer offs.deinit();

    var bft = try BOTree.init(str.items, testing.allocator);
    defer bft.deinit(testing.allocator);

    var r = utils.newRand();
    if (offs.items.len == 1) {
        return;
    }
    const idx = r.intRangeAtMost(u32, 1, @intCast(offs.items.len - 1));
    try bft.decr(@intCast(idx), -42);

    for (0..idx) |i| {
        try expectEqual(offs.items[i], bft.get(@intCast(i)));
    }
    for (idx..offs.items.len) |i| {
        try expectEqual(offs.items[i] + 42, bft.get(@intCast(i)));
    }
}

test "insert: once" {
    const input = try utils.genInput(testing.allocator);
    const str = input.str;
    const offs = input.breaks;
    defer str.deinit();
    defer offs.deinit();

    var bft = try BOTree.init(str.items, testing.allocator);
    defer bft.deinit(testing.allocator);

    var r = utils.newRand();
    const idx = r.intRangeAtMost(u32, 0, @intCast(offs.items.len - 1));
    try bft.insertAfter(@intCast(idx));

    const new = idx + 1;
    if (new != offs.items.len) {
        for (0..new) |i| {
            try expectEqual(offs.items[i], bft.get(@intCast(i)));
        }
        try expectEqual(offs.items[new], bft.get(@intCast(new)));
        for (new + 1..offs.items.len + 1) |i| {
            try expectEqual(offs.items[i - 1] + 1, bft.get(@intCast(i)));
        }
    } else {
        for (0..new) |i| {
            try expectEqual(offs.items[i], bft.get(@intCast(i)));
        }
        try expectEqual(offs.items[new - 1] + 1, bft.get(@intCast(new)));
    }

    try testing.expect(bft.root.balanced());
}

test "insert: many" {
    const input = try utils.genInput(testing.allocator);
    const str = input.str;
    var offs = input.breaks;
    defer str.deinit();
    defer offs.deinit();

    var bft = try BOTree.init(str.items, testing.allocator);
    defer bft.deinit(testing.allocator);

    for (0..256) |_| {
        var r = utils.newRand();
        const idx = r.intRangeAtMost(u32, 0, @intCast(offs.items.len - 1));
        const newOff = if (idx == offs.items.len - 1) offs.getLast() + 1 else offs.items[idx + 1];

        try bft.insertAfter(@intCast(idx));

        try offs.insert(idx + 1, newOff);
        for (idx + 2..offs.items.len) |i| {
            offs.items[i] += 1;
        }

        try testing.expect(bft.root.balanced());
        for (0..offs.items.len) |i| {
            try expectEqual(offs.items[i], bft.get(@intCast(i)));
        }
    }
}
