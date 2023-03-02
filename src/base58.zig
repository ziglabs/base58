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

pub const Base58Error = error{ EncodedIsEmpty, DecodedIsEmpty, InvalidCharacter, CharacterOutOfRange, CarryNotZero, CannotAllocateBuffer, CannotReallocate, BufferTooSmall };

pub fn decodeWithBuffer(buffer: []u8, encoded: []const u8) Base58Error![]const u8 {
    if (encoded.len == 0) return Base58Error.EncodedIsEmpty;
    if (buffer.len < encoded.len) return Base58Error.BufferTooSmall;
    std.mem.set(u8, buffer, 0);
    var length: usize = 0;
    for (encoded) |r| {
        if (r >= digits.len) return Base58Error.CharacterOutOfRange;
        var carry: u32 = digits[r];
        if (carry == 255) return Base58Error.InvalidCharacter;
        for (buffer[0..length]) |b, i| {
            carry += @as(u32, b) * 58;
            buffer[i] = @truncate(u8, carry);
            carry >>= 8;
        }
        while (carry > 0) : (carry >>= 8) {
            buffer[length] = @truncate(u8, carry);
            length += 1;
        }
    }
    for (encoded) |r| {
        if (r != characters[0]) break;
        buffer[length] = 0;
        length += 1;
    }
    std.mem.reverse(u8, buffer[0..length]);
    return buffer[0..length];
}

pub fn decodeWithAllocator(allocator: Allocator, encoded: []const u8) Base58Error![]const u8 {
    if (encoded.len == 0) return Base58Error.EncodedIsEmpty;
    const buffer = allocator.alloc(u8, getDecodedLengthUpperBound(encoded.len)) catch return Base58Error.CannotAllocateBuffer;
    errdefer allocator.free(buffer);
    const decoded = try decodeWithBuffer(buffer, encoded);
    _ = allocator.realloc(buffer, decoded.len) catch return Base58Error.CannotReallocate;
    return decoded;
}

pub fn comptimeDecode(comptime encoded: []const u8) [comptimeGetDecodedLength(encoded)]u8 {
    comptime {
        @setEvalBranchQuota(100_000);
        var buffer: [getDecodedLengthUpperBound(encoded.len)]u8 = undefined;
        const decoded = decodeWithBuffer(&buffer, encoded) catch |err| {
            @compileError("failed to decode base58 string: '" ++ @errorName(err) ++ "'");
        };
        return decoded[0..decoded.len].*;
    }
}

pub fn getDecodedLengthUpperBound(encoded_length: usize) usize {
    return encoded_length;
}

pub fn comptimeGetDecodedLength(comptime encoded: []const u8) usize {
    comptime {
        @setEvalBranchQuota(100_000);
        var buffer = std.mem.zeroes([getDecodedLengthUpperBound(encoded.len)]u8);
        var length: usize = 0;
        for (encoded) |r| {
            var carry: u32 = digits[r];
            if (carry == 255) @compileError("failed to compute base58 string length: invalid character '" ++ [_]u8{r} ++ "'");
            for (buffer[0..length]) |b, i| {
                carry += @as(u32, b) * 58;
                buffer[i] = @truncate(u8, carry);
                carry >>= 8;
            }
            while (carry > 0) : (carry >>= 8) {
                buffer[length] = @truncate(u8, carry);
                length += 1;
            }
        }
        for (encoded) |r| {
            if (r != characters[0]) break;
            length += 1;
        }
        return length;
    }
}

pub fn encodeWithBuffer(buffer: []u8, decoded: []const u8) Base58Error![]const u8 {
    if (decoded.len == 0) return Base58Error.DecodedIsEmpty;
    if (buffer.len < getEncodedLengthUpperBound(decoded.len)) return Base58Error.BufferTooSmall;
    std.mem.set(u8, buffer, 0);
    var length: usize = 0;
    for (decoded) |r| {
        var carry: u32 = r;
        for (buffer[0..length]) |b, i| {
            carry += @as(u32, b) << 8;
            buffer[i] = @intCast(u8, carry % 58);
            carry /= 58;
        }
        while (carry > 0) : (carry /= 58) {
            buffer[length] = @intCast(u8, carry % 58);
            length += 1;
        }
    }
    for (buffer[0..length]) |b, i| {
        buffer[i] = characters[b];
    }
    for (decoded) |r| {
        if (r != 0) break;
        buffer[length] = characters[0];
        length += 1;
    }
    std.mem.reverse(u8, buffer[0..length]);
    return buffer[0..length];
}

pub fn encodeWithAllocator(allocator: Allocator, decoded: []const u8) Base58Error![]const u8 {
    if (decoded.len == 0) return Base58Error.DecodedIsEmpty;
    const buffer = allocator.alloc(u8, getEncodedLengthUpperBound(decoded.len)) catch return Base58Error.CannotAllocateBuffer;
    errdefer allocator.free(buffer);
    const encoded = try encodeWithBuffer(buffer, decoded);
    _ = allocator.realloc(buffer, encoded.len) catch return Base58Error.CannotReallocate;
    return encoded;
}

pub fn comptimeEncode(comptime decoded: []const u8) [comptimeGetEncodedLength(decoded)]u8 {
    comptime {
        @setEvalBranchQuota(100_000);
        var buffer: [getEncodedLengthUpperBound(decoded.len)]u8 = undefined;
        const encoded = encodeWithBuffer(&buffer, decoded) catch |err| {
            @compileError("failed to base58 encode string: '" ++ @errorName(err) ++ "'");
        };
        return encoded[0..encoded.len].*;
    }
}

pub fn getEncodedLengthUpperBound(decoded_length: usize) usize {
    return decoded_length * 137 / 100 + 1;
}

pub fn comptimeGetEncodedLength(comptime decoded: []const u8) usize {
    comptime {
        @setEvalBranchQuota(100_000);
        var buffer = std.mem.zeroes([getEncodedLengthUpperBound(decoded.len)]u8);
        var length: usize = 0;
        for (decoded) |r| {
            var carry: u32 = r;
            for (buffer[0..length]) |b, i| {
                carry += @as(u32, b) << 8;
                buffer[i] = @intCast(u8, carry % 58);
                carry /= 58;
            }
            while (carry > 0) : (carry /= 58) {
                buffer[length] = @intCast(u8, carry % 58);
                length += 1;
            }
        }
        for (decoded) |r| {
            if (r != 0) break;
            length += 1;
        }
        return length;
    }
}

// decode
test "decodeWithBuffer" {
    var buffer: [100]u8 = undefined;
    const td = testing_data();
    for (td) |d| {
        const result = try decodeWithBuffer(&buffer, d.encoded);
        try testing.expectEqualSlices(u8, result, d.decoded);
    }
}

test "decodeWithAllocator" {
    const td = testing_data();
    for (td) |d| {
        const result = try decodeWithAllocator(testing.allocator, d.encoded);
        try testing.expectEqualSlices(u8, result, d.decoded);
        testing.allocator.free(result);
    }
}

test "comptimeDecode" {
    const td = comptime testing_data();
    inline for (td) |d| {
        const result = comptimeDecode(d.encoded);
        try testing.expectEqualSlices(u8, &result, d.decoded);
    }
}

test "getDecodedLengthUpperBound" {
    try testing.expect(6 == getDecodedLengthUpperBound("111211".len));
}

test "comptimeGetDecodedLength" {
    try testing.expect(5 == comptimeGetDecodedLength("111211"));
}

// encode
test "encodeWithBuffer" {
    var buffer: [100]u8 = undefined;
    const td = testing_data();
    for (td) |d| {
        const result = try encodeWithBuffer(&buffer, d.decoded);
        try testing.expectEqualSlices(u8, result, d.encoded);
    }
}

test "encodeWithAllocator" {
    const td = testing_data();
    for (td) |d| {
        const result = try encodeWithAllocator(testing.allocator, d.decoded);
        try testing.expectEqualSlices(u8, result, d.encoded);
        testing.allocator.free(result);
    }
}

test "comptimeEncode" {
    const td = comptime testing_data();
    inline for (td) |d| {
        const result = comptimeEncode(d.decoded);
        try testing.expectEqualSlices(u8, &result, d.encoded);
    }
}

test "getEncodedLengthUpperBound" {
    try testing.expect(7 == getEncodedLengthUpperBound(([_]u8{ 0, 0, 0, 13, 36 }).len));
}

test "comptimeGetEncodedLength" {
    try testing.expect(6 == comptimeGetEncodedLength(&[_]u8{ 0, 0, 0, 13, 36 }));
}

test "t" {
    const s = try std.fmt.allocPrint(testing.allocator, "{}", .{ std.fmt.fmtSliceHexLower("00f8917303bfa8ef24f292e8fa1419b20460ba064d") });
    defer testing.allocator.free(s);
    std.debug.print("\n{s}\n", .{s});
    try testing.expectEqualSlices(u8, "303066383931373330336266613865663234663239326538666131343139623230343630626130363464", s);
}
// https://github.com/travisstaloch/protobuf-zig/blob/main/src/test-common.zig#L35

const TestData = struct {
    encoded: []const u8,
    decoded: []const u8,
};

fn testing_data() []const TestData {
    return &[_]TestData{
        .{ .encoded = "USm3fpXnKG5EUBx2ndxBDMPVciP5hGey2Jh4NDv6gmeo1LkMeiKrLJUUBk6Z", .decoded = "The quick brown fox jumps over the lazy dog." },
        .{ .encoded = "2NEpo7TZRRrLZSi2U", .decoded = "Hello World!" },
        .{ .encoded = "11233QC4", .decoded = &[_]u8{ 0, 0, 40, 127, 180, 205 } },
        .{ .encoded = "1", .decoded = &[_]u8{0} },
        .{ .encoded = "2", .decoded = &[_]u8{1} },
        .{ .encoded = "21", .decoded = &[_]u8{58} },
        .{ .encoded = "211", .decoded = &[_]u8{ 13, 36 } },
        .{ .encoded = "1211", .decoded = &[_]u8{ 0, 13, 36 } },
        .{ .encoded = "111211", .decoded = &[_]u8{ 0, 0, 0, 13, 36 } },
    };
}
