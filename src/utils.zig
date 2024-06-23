const std = @import("std");

/// dirty workaroud for https://github.com/ziglang/zig/issues/4437
pub fn expectEqual(expected: anytype, actual: anytype) !void {
    try std.testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}

/// returns new rng object
pub inline fn newRand() std.Random {
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    return rng.random();
}

/// generates a random UTF8 string with certain length, distribution is (somewhat) linear
pub fn randomUTF8(len: u16, allocator: std.mem.Allocator, r: std.Random) !std.ArrayList(u8) {
    var list = std.ArrayList(u8).init(allocator);
    if (len == 1) {
        try list.append(0xA);
        return list;
    }
    for (0..len) |_| {
        const bytes = r.uintAtMost(u8, 4);
        // https://datatracker.ietf.org/doc/html/rfc3629#section-4
        // UTF8-char   = UTF8-1 / UTF8-2 / UTF8-3 / UTF8-4
        // UTF8-1      = %x00-7F
        // UTF8-2      = %xC2-DF UTF8-tail
        // UTF8-3      = %xE0 %xA0-BF UTF8-tail / %xE1-EC 2( UTF8-tail ) /
        //               %xED %x80-9F UTF8-tail / %xEE-EF 2( UTF8-tail )
        // UTF8-4      = %xF0 %x90-BF 2( UTF8-tail ) / %xF1-F3 3( UTF8-tail ) /
        //               %xF4 %x80-8F 2( UTF8-tail )
        // UTF8-tail   = %x80-BF
        switch (bytes) {
            0 => {
                // 1-byte, 0xxxxxxx
                const b1: u8 = r.uintAtMost(u8, 0x7F);
                try list.append(b1);
            },
            1 => {
                // 2-byte, 110xxxxx 10xxxxxx
                const b1: u8 = r.uintAtMost(u8, 0xDF - 0xC2) + 0xC2;
                const b2: u8 = r.uintAtMost(u8, 0xBF - 0x80) + 0x80;
                try list.append(b1);
                try list.append(b2);
            },
            2 => {
                // 3-byte
                const b1 = 0xE0 + r.uintAtMost(u8, 0xF);

                const b2 = if (b1 == 0xE0) r.uintAtMost(u8, 0xBF - 0xA0) + 0xA0 //
                else if (b1 == 0xED) r.uintAtMost(u8, 0x9F - 0x80) + 0x80 //
                else r.uintAtMost(u8, 0xBF - 0x80) + 0x80;

                const b3 = r.uintAtMost(u8, 0xBF - 0x80) + 0x80;
                try list.append(b1);
                try list.append(b2);
                try list.append(b3);
            },
            3 => {
                // 4-byte
                const b1 = r.uintAtMost(u8, 0x4) + 0xF0;

                const b2 =
                    if (b1 == 0xF0) r.uintAtMost(u8, 0xBF - 0x90) + 0x90 //
                else if (b1 == 0xF4) r.uintAtMost(u8, 0x8F - 0x80) + 0x80 //
                else r.uintAtMost(u8, 0xBF - 0x80) + 0x80;

                const b3 = r.uintAtMost(u8, 0xBF - 0x80) + 0x80;
                const b4 = r.uintAtMost(u8, 0xBF - 0x80) + 0x80;

                try list.append(b1);
                try list.append(b2);
                try list.append(b3);
                try list.append(b4);
            },
            4 => {
                // \n
                try list.append(0xA);
            },
            else => unreachable,
        }
    }

    return list;
}

pub const TestStringStruct = struct {
    str: std.ArrayList(u8),
    breaks: std.ArrayList(u64),
};

/// generates a random UTF8 string with [1..65536] length, and records all the line breaks
pub fn genInput(allocator: std.mem.Allocator) !TestStringStruct {
    var r = newRand();
    const arr = try randomUTF8(r.uintAtMost(u16, 0xFFFE) + 1, allocator, r);

    var iter = (try std.unicode.Utf8View.init(arr.items)).iterator();
    var offs = std.ArrayList(u64).init(allocator);

    // first line always starts at zero
    try offs.append(0);
    var i: u64 = 0;
    while (iter.nextCodepointSlice()) |c| {
        if (c.len == 1 and c[0] == '\n') {
            // record pos of line start
            try offs.append(i + 1);
        }
        i += c.len;
    }
    return TestStringStruct{
        .str = arr,
        .breaks = offs,
    };
}

/// generates a random UTF8 string with [1..32] length, and records all the line breaks
pub fn genSmallInput(allocator: std.mem.Allocator) !TestStringStruct {
    var r = newRand();
    const arr = try randomUTF8(r.uintAtMost(u16, 32) + 1, allocator, r);

    var iter = (try std.unicode.Utf8View.init(arr.items)).iterator();
    var offs = std.ArrayList(u64).init(allocator);

    // first line always starts at zero
    try offs.append(0);
    var i: u64 = 0;
    while (iter.nextCodepointSlice()) |c| {
        if (c.len == 1 and c[0] == '\n') {
            // record pos of line start
            try offs.append(i + 1);
        }
        i += c.len;
    }
    return TestStringStruct{
        .str = arr,
        .breaks = offs,
    };
}

test "utf-8 is valid" {
    var rng = newRand();
    const arr = try randomUTF8(rng.uintAtMost(u16, 1 << 15), std.testing.allocator, rng);
    defer arr.deinit();
    try std.testing.expect(std.unicode.utf8ValidateSlice(arr.items));
}
