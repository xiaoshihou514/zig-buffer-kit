const std = @import("std");

/// dirty workaroud for https://github.com/ziglang/zig/issues/4437
pub fn expectEqual(expected: anytype, actual: anytype) !void {
    try std.testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}

/// returns new rng object
pub fn newRand() std.rand.Xoshiro256 {
    return std.rand.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
}

/// generates a random UTF8 string with certain length, distribution is (somewhat) linear
pub fn randomUTF8(len: u16, allocator: std.mem.Allocator, r: std.rand.Xoshiro256) !std.ArrayList(u8) {
    var list = std.ArrayList(u8).init(allocator);
    var rng = r;
    for (0..len) |_| {
        const bytes = rng.next() % 5;
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
                const b1: u8 = @intCast(rng.next() % (1 << 7));
                try list.append(b1);
            },
            1 => {
                // 2-byte, 110xxxxx 10xxxxxx
                const hb1 = rng.next() % (1 << 3);
                const hb2 = rng.next() % ((1 << 4) - 0x8) + 0x8;
                const hb3 = rng.next() % (1 << 4);
                const b1: u8 = @intCast(0b11000000 + (hb1 << 2) + (hb2 >> 2));
                const b2: u8 = @intCast(0b10000000 + ((hb2 & 0b11) << 4) + hb3);
                try list.append(b1);
                try list.append(b2);
            },
            2 => {
                // 3-byte
                const hb1 = rng.next() % (1 << 4);
                const b1: u8 = @intCast(0b11100000 + hb1);

                const hb2 =
                    if (b1 == 0xE0) rng.next() % ((1 << 4) - 0x8) + 0x8 // stop zig fmt
                else if (b1 == 0xED) rng.next() % (1 << 3) // stop zig fmt
                else rng.next() % (1 << 4);

                const hb3 = rng.next() % (1 << 4);
                const hb4 = rng.next() % (1 << 4);
                const b2: u8 = @intCast(0b10000000 + (hb2 << 2) + (hb3 >> 2));
                const b3: u8 = @intCast(0b10000000 + ((hb3 & 0b11) << 4) + hb4);
                try list.append(b1);
                try list.append(b2);
                try list.append(b3);
            },
            3 => {
                // 4-byte
                const hb1 = rng.next() % (1 << 4) + 1;
                const b1: u8 = @intCast(0b11110000 + (hb1 >> 2));

                const hb2 =
                    if (b1 == 0xF0) ((rng.next() % (1 << 2)) << 2) + (rng.next() % ((1 << 2) - 1)) + 1 // stop zig fmt
                else if (b1 == 0xF4) (rng.next() % (1 << 2)) << 2 // stop zig fmt
                else rng.next() % (1 << 4);

                const hb3 = rng.next() % (1 << 4);
                const hb4 = rng.next() % (1 << 4);
                const hb5 = rng.next() % (1 << 4);
                const b2: u8 = @intCast(0b10000000 + ((hb1 & 0b11) << 4) + hb2);
                const b3: u8 = @intCast(0b10000000 + (hb3 << 2) + (hb4 >> 2));
                const b4: u8 = @intCast(0b10000000 + ((hb4 & 0b11) << 4) + hb5);
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
    var rng = newRand();
    const arr = try randomUTF8(@intCast(rng.next() % (1 << 16)), allocator, rng);

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
    var rng = std.rand.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const arr = try randomUTF8(@intCast(rng.next() % (1 << 16)), std.testing.allocator, rng);
    defer arr.deinit();
    try std.testing.expect(std.unicode.utf8ValidateSlice(arr.items));
}
