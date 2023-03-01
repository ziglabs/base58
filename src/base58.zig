const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const characters = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const digits = [128]u8{
    255, 255, 255, 255, 255, 255, 255, 255, // 0-7
    255, 255, 255, 255, 255, 255, 255, 255, // 8-15
    255, 255, 255, 255, 255, 255, 255, 255, // 16-23
    255, 255, 255, 255, 255, 255, 255, 255, // 24-31
    255, 255, 255, 255, 255, 255, 255, 255, // 32-39
    255, 255, 255, 255, 255, 255, 255, 255, // 40-47
    255, 0, 1, 2, 3, 4, 5, 6, // 48-55
    7, 8, 255, 255, 255, 255, 255, 255, // 56-63
    255, 9, 10, 11, 12, 13, 14, 15, // 64-71
    16, 255, 17, 18, 19, 20, 21, 255, // 72-79
    22, 23, 24, 25, 26, 27, 28, 29, // 80-87
    30, 31, 32, 255, 255, 255, 255, 255, // 88-95
    255, 33, 34, 35, 36, 37, 38, 39, // 96-103
    40, 41, 42, 43, 255, 44, 45, 46, // 104-111
    47, 48, 49, 50, 51, 52, 53, 54, // 112-119
    55, 56, 57, 255, 255, 255, 255, 255, // 120-127
};

pub const Base58Error = error{ DataIsEmpty, InvalidCharacter, CarryNotZero, AllocatingBuffer, AllocationResult };

pub fn decode(allocator: Allocator, data: []const u8) Base58Error![]const u8 {
    if (data.len == 0) return Base58Error.DataIsEmpty;

    const buffer_length = 1 + data.len * 11 / 15;
    var buffer = allocator.alloc(u8, buffer_length) catch return Base58Error.AllocatingBuffer;
    defer allocator.free(buffer);

    std.mem.set(u8, buffer, 0);

    for (data) |d58| {
        if (d58 >= digits.len) return Base58Error.InvalidCharacter;
        var carry: u32 = switch (digits[d58]) {
            255 => return Base58Error.InvalidCharacter,
            else => @as(u32, digits[d58]),
        };
        var index = buffer.len - 1;
        while (true) : (index -= 1) {
            carry += @as(u32, buffer[index]) * 58;
            buffer[index] = @truncate(u8, carry);
            carry /= 256;
            if (index == 0) break;
        }
        if (carry != 0) return Base58Error.CarryNotZero;
    }
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (data) |d58| {
        if (d58 != characters[0]) break;
        result.append(0) catch return Base58Error.AllocationResult;
    }

    for (buffer) |b| {
        if (b != 0) result.append(b) catch return Base58Error.AllocationResult;
    }

    return result.toOwnedSlice();
}

test "decode" {
    const result = try decode(testing.allocator, "1211");
    std.debug.print("\n{any}\n", .{result});
    defer testing.allocator.free(result);
    try testing.expect(true);
    // try testing.expectEqualSlices(u8, result, "Hello World!");
}

// fn decodeAlloc(ally: Allocator, ...) ![]const u8 {
//     const buf = try ally.alloc(u8, getEncodedLengthUpperBound(...));
//     errdefer ally.free(buf);
//     const result = try decodeBuffer(..., buf);
//     _ = ally.resize(buf, result.len);
//     return result;
// }

// fn shrink(ally: Allocator, buf: anytype, new_size: usize) @TypeOf(buf) {
//     if (ally.resize(buf, new_size)) return buf;

//     const new_buf = try ally.dupe(std.meta.Child(@TypeOf(buf)), buf);
//     ally.free(buf);
//     return new_buf;
// }
