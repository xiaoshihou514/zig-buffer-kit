/// dirty workaroud for https://github.com/ziglang/zig/issues/4437
pub fn expectEqual(expected: anytype, actual: anytype) !void {
    try @import("std").testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}
