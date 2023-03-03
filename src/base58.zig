const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const fmt = std.fmt;

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

pub const Base58Error = error{ CannotConcatStrings, BadChecksum, DecodedTooShort, EncodedIsEmpty, DecodedIsEmpty, InvalidCharacter, CannotAllocateConcatBuffer, CharacterOutOfRange, CarryNotZero, CannotAllocateBuffer, CannotReallocate, BufferTooSmall, ConcatBufferTooSmall };

pub fn doubleSha256(input: []const u8) [std.crypto.hash.sha2.Sha256.digest_length]u8 {
    var h1: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &h1, .{});

    var h2: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&h1, &h2, .{});

    return h2;
}

// decode -----------------------------------------------------------------------------------------
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
        return decoded[0..].*;
    }
}

// decode check -----------------------------------------------------------------------------------
pub fn decodeCheckWithBuffer(buffer: []u8, encoded: []const u8) Base58Error![]const u8 {
    if (encoded.len == 0) return Base58Error.EncodedIsEmpty;
    if (buffer.len < encoded.len) return Base58Error.BufferTooSmall;
    const decoded = try decodeWithBuffer(buffer, encoded);
    if (decoded.len < 4) return Base58Error.DecodedTooShort;
    const check_start = decoded.len - 4;
    const double_sha256 = doubleSha256(decoded[0..check_start]);
    const hash_check = [_]u8{ double_sha256[0], double_sha256[1], double_sha256[2], double_sha256[3] };
    const data_check = [_]u8{ decoded[check_start], decoded[check_start + 1], decoded[check_start + 2], decoded[check_start + 3] };
    const expected = std.mem.readIntLittle(u32, &hash_check);
    const actual = std.mem.readIntLittle(u32, &data_check);
    if (expected != actual) return Base58Error.BadChecksum;
    return decoded[0..check_start];
}

pub fn decodeCheckWithAllocator(allocator: Allocator, encoded: []const u8) Base58Error![]const u8 {
    if (encoded.len == 0) return Base58Error.EncodedIsEmpty;
    const decoded = try decodeWithAllocator(allocator, encoded);
    if (decoded.len < 4) return Base58Error.DecodedTooShort;
    const check_start = decoded.len - 4;
    const double_sha256 = doubleSha256(decoded[0..check_start]);
    const hash_check = [_]u8{ double_sha256[0], double_sha256[1], double_sha256[2], double_sha256[3] };
    const data_check = [_]u8{ decoded[check_start], decoded[check_start + 1], decoded[check_start + 2], decoded[check_start + 3] };
    const expected = std.mem.readIntLittle(u32, &hash_check);
    const actual = std.mem.readIntLittle(u32, &data_check);
    if (expected != actual) return Base58Error.BadChecksum;
    return decoded[0..check_start];
}

// TODO: hashing during comptime is broken - https://discord.com/channels/605571803288698900/1081022464911474839
pub fn comptimeDecodeCheck(comptime encoded: []const u8) [comptimeGetDecodedLength(encoded)]u8 {
    comptime {
        @setEvalBranchQuota(100_000);
        var buffer: [getDecodedLengthUpperBound(encoded.len)]u8 = undefined;
        const decoded = decodeCheckWithBuffer(&buffer, encoded) catch |err| {
            @compileError("failed to decode base58 string: '" ++ @errorName(err) ++ "'");
        };
        return decoded[0..].*;
    }
}

// get decode length ------------------------------------------------------------------------------
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

// encode -----------------------------------------------------------------------------------------
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

// encode check -----------------------------------------------------------------------------------
pub fn encodeCheckWithBuffers(buffer: []u8, concat_buffer: []u8, decoded: []const u8) Base58Error![]const u8 {
    if (decoded.len == 0) return Base58Error.DecodedIsEmpty;
    if (buffer.len < getEncodedLengthUpperBound(decoded.len + 4)) return Base58Error.BufferTooSmall;
    if (concat_buffer.len < decoded.len + 4) return Base58Error.ConcatBufferTooSmall;
    const double_sha256 = doubleSha256(decoded);
    var fba = std.heap.FixedBufferAllocator.init(concat_buffer);
    const concatenated = std.mem.concat(fba.allocator(), u8, &[_][]const u8{ decoded, &[_]u8{ double_sha256[0], double_sha256[1], double_sha256[2], double_sha256[3] } }) catch return Base58Error.CannotConcatStrings;
    return try encodeWithBuffer(buffer, concatenated);
}

pub fn encodeCheckWithAllocator(allocator: Allocator, decoded: []const u8) Base58Error![]const u8 {
    if (decoded.len == 0) return Base58Error.DecodedIsEmpty;
    const buffer = allocator.alloc(u8, getEncodedLengthUpperBound(decoded.len + 4)) catch return Base58Error.CannotAllocateBuffer;
    errdefer allocator.free(buffer);
    const double_sha256 = doubleSha256(decoded);
    const concatenated = std.mem.concat(allocator, u8, &[_][]const u8{ decoded, &[_]u8{ double_sha256[0], double_sha256[1], double_sha256[2], double_sha256[3] } }) catch return Base58Error.CannotConcatStrings;
    defer allocator.free(concatenated);
    const encoded = try encodeWithBuffer(buffer, concatenated);
    _ = allocator.realloc(buffer, encoded.len) catch return Base58Error.CannotReallocate;
    return encoded;
}

// TODO: hashing during comptime is broken - https://discord.com/channels/605571803288698900/1081022464911474839
pub fn comptimeEncodeCheck(comptime decoded: []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(100_000);
        var buffer: [getEncodedLengthUpperBound(decoded.len + 4)]u8 = undefined;
        var concat_buffer: [decoded.len + 4]u8 = undefined;
        return encodeCheckWithBuffers(&buffer, &concat_buffer, decoded) catch |err| {
            @compileError("failed to base58 check encode string: '" ++ @errorName(err) ++ "'");
        };
    }
}

// get encode length ------------------------------------------------------------------------------
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
        try testing.expectEqualStrings(result, d.decoded);
    }
}

test "decodeWithAllocator" {
    const td = testing_data();
    for (td) |d| {
        const result = try decodeWithAllocator(testing.allocator, d.encoded);
        try testing.expectEqualStrings(result, d.decoded);
        testing.allocator.free(result);
    }
}

test "comptimeDecode" {
    const td = comptime testing_data();
    inline for (td) |d| {
        const result = comptimeDecode(d.encoded);
        try testing.expectEqualStrings(&result, d.decoded);
    }
}

test "decodeCheckWithBuffer" {
    var buffer: [100]u8 = undefined;
    const result = try decodeCheckWithBuffer(&buffer, "1PfJpZsjreyVrqeoAfabrRwwjQyoSQMmHH");
    try testing.expectEqualStrings(result, &[_]u8{ 0, 248, 145, 115, 3, 191, 168, 239, 36, 242, 146, 232, 250, 20, 25, 178, 4, 96, 186, 6, 77 });
}

test "decodeCheckWithAllocator" {
    const result = try decodeCheckWithAllocator(testing.allocator, "1PfJpZsjreyVrqeoAfabrRwwjQyoSQMmHH");
    try testing.expectEqualStrings(result, &[_]u8{ 0, 248, 145, 115, 3, 191, 168, 239, 36, 242, 146, 232, 250, 20, 25, 178, 4, 96, 186, 6, 77 });
    testing.allocator.free(result);
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
        try testing.expectEqualStrings(result, d.encoded);
    }
}

test "encodeWithAllocator" {
    const td = testing_data();
    for (td) |d| {
        const result = try encodeWithAllocator(testing.allocator, d.decoded);
        try testing.expectEqualStrings(result, d.encoded);
        testing.allocator.free(result);
    }
}

test "comptimeEncode" {
    const td = comptime testing_data();
    inline for (td) |d| {
        const result = comptimeEncode(d.decoded);
        try testing.expectEqualStrings(&result, d.encoded);
    }
}

test "encodeCheckWithBuffers" {
    var buffer: [100]u8 = undefined;
    var concat_buffer: [100]u8 = undefined;
    const result = try encodeCheckWithBuffers(&buffer, &concat_buffer, &[_]u8{ 0, 248, 145, 115, 3, 191, 168, 239, 36, 242, 146, 232, 250, 20, 25, 178, 4, 96, 186, 6, 77 });
    try testing.expectEqualStrings(result, "1PfJpZsjreyVrqeoAfabrRwwjQyoSQMmHH");
}

test "encodeCheckWithAllocator" {
    const result = try encodeCheckWithAllocator(testing.allocator, &[_]u8{ 0, 248, 145, 115, 3, 191, 168, 239, 36, 242, 146, 232, 250, 20, 25, 178, 4, 96, 186, 6, 77 });
    try testing.expectEqualStrings(result, "1PfJpZsjreyVrqeoAfabrRwwjQyoSQMmHH");
    testing.allocator.free(result);
}

// TODO: hashing during comptime is broken - https://discord.com/channels/605571803288698900/1081022464911474839
// test "comptimeEncodeCheck" {
//     const result = comptimeEncodeCheck(&[_]u8{ 0, 248, 145, 115, 3, 191, 168, 239, 36, 242, 146, 232, 250, 20, 25, 178, 4, 96, 186, 6, 77 });
//     try testing.expectEqualStrings(result, "1PfJpZsjreyVrqeoAfabrRwwjQyoSQMmHH");
// }

test "getEncodedLengthUpperBound" {
    try testing.expect(7 == getEncodedLengthUpperBound(([_]u8{ 0, 0, 0, 13, 36 }).len));
}

test "comptimeGetEncodedLength" {
    try testing.expect(6 == comptimeGetEncodedLength(&[_]u8{ 0, 0, 0, 13, 36 }));
}

test "doubleSha256" {
    try testing.expectEqualStrings(&doubleSha256("abc"), &[_]u8{ 79, 139, 66, 194, 45, 211, 114, 155, 81, 155, 166, 246, 141, 45, 167, 204, 91, 45, 96, 109, 5, 218, 237, 90, 213, 18, 140, 192, 62, 108, 99, 88 });
    try testing.expectEqualStrings(&doubleSha256(&[_]u8{ 0, 248, 145, 115, 3, 191, 168, 239, 36, 242, 146, 232, 250, 20, 25, 178, 4, 96, 186, 6, 77 }), &[_]u8{ 24, 89, 104, 144, 199, 86, 241, 252, 155, 51, 19, 79, 47, 120, 220, 189, 212, 20, 244, 188, 187, 216, 61, 49, 182, 168, 113, 79, 159, 22, 54, 104 });
}

// test "hex 1" {
//     const s = try std.fmt.allocPrint(testing.allocator, "{}", .{ std.fmt.fmtSliceHexLower("00f8917303bfa8ef24f292e8fa1419b20460ba064d") });
//     defer testing.allocator.free(s);
//     std.debug.print("\n{s}\n", .{s});
//     try testing.expectEqualStrings("303066383931373330336266613865663234663239326538666131343139623230343630626130363464", s);
// }
// https://discord.com/channels/605571803288698900/1080707312739696710

// test "hex 2" {
//     const hex = "00f8917303bfa8ef24f292e8fa1419b20460ba064d";
//     var buf: [hex.len / 2]u8 = undefined;
//     _ = try std.fmt.hexToBytes(&buf, hex);
//     const s = try std.fmt.allocPrint(testing.allocator, "{}", .{std.fmt.fmtSliceHexLower(&buf)});
//     defer testing.allocator.free(s);
//     std.debug.print("\nhex bytes{any}\n", .{buf});
//     try testing.expectEqualStrings(hex, s);
// }
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
