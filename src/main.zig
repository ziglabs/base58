const std = @import("std");
const Managed = std.math.big.int.Managed;
const print = std.debug.print;
const expect = std.testing.expect;
const eql = std.mem.eql;
const ArrayList = std.ArrayList;

const characters = [58]u8{ '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z' };

pub fn encode(allocator: std.mem.Allocator, content: []const u8) ![]const u8 {
    if (content.len == 0) return "";

    var sum = try Managed.initSet(allocator, 0);
    defer sum.deinit();

    var pow_mul = try Managed.initSet(allocator, 2);
    defer pow_mul.deinit();

    var letter = try Managed.init(allocator);
    defer letter.deinit();

    for (content) |content_letter, index| {
        var exponent = (content.len - index - 1) * 8;
        try letter.set(content_letter);
        try pow_mul.pow(pow_mul.toConst(), @intCast(u32, exponent));
        try pow_mul.mul(pow_mul.toConst(), letter.toConst());
        try sum.ensureAddCapacity(sum.toConst(), pow_mul.toConst());
        try sum.add(sum.toConst(), pow_mul.toConst());
        try pow_mul.set(2);
    }

    var quotients = ArrayList(Managed).init(allocator);
    defer {
        for (quotients.items) |*fd| fd.deinit();
        quotients.deinit();
    }

    var remainders = ArrayList(u8).init(allocator);
    defer remainders.deinit();

    var fd_index: usize = 0;

    var divisor = try Managed.initSet(allocator, 58);
    defer divisor.deinit();

    var zero = try Managed.initSet(allocator, 0);
    defer zero.deinit();

    while (true) {
        var quotient = try Managed.init(allocator);
        var remainder = try Managed.init(allocator);
        if (remainders.items.len == 0 and quotients.items.len == 0) {
            try Managed.divFloor(&quotient, &remainder, sum.toConst(), divisor.toConst());
        } else {
            try Managed.divFloor(&quotient, &remainder, quotients.items[fd_index].toConst(), divisor.toConst());
            fd_index += 1;
        }

        try quotients.append(quotient);
        try remainders.append(try remainder.to(u8));
        remainder.deinit();

        if (quotient.eq(zero)) break;
    }

    var results = ArrayList(u8).init(allocator);
    errdefer results.deinit();

    var r_reverse_index: usize = remainders.items.len - 1;
    while (true) : (r_reverse_index -= 1) {
        var characters_index: usize = remainders.items[r_reverse_index];
        try results.append(characters[characters_index]);
        if (r_reverse_index == 0) break;
    }

    return results.toOwnedSlice();
}

test "test 1" {
    const allocator = std.testing.allocator;
    const data = try encode(allocator, "");
    defer allocator.free(data);
    try expect(eql(u8, data, ""));
}

test "test 2" {
    const allocator = std.testing.allocator;
    const data = try encode(allocator, " ");
    defer allocator.free(data);
    try expect(eql(u8, data, "Z"));
}

test "test 3" {
    const allocator = std.testing.allocator;
    const data = try encode(allocator, "-");
    defer allocator.free(data);
    try expect(eql(u8, data, "n"));
}

test "test 4" {
    const allocator = std.testing.allocator;
    const data = try encode(allocator, "0");
    defer allocator.free(data);
    try expect(eql(u8, data, "q"));
}

test "test 5" {
    const allocator = std.testing.allocator;
    const data = try encode(allocator, "1");
    defer allocator.free(data);
    try expect(eql(u8, data, "r"));
}

test "test 6" {
    const allocator = std.testing.allocator;
    const data = try encode(allocator, "-1");
    defer allocator.free(data);
    try expect(eql(u8, data, "4SU"));
}

test "test 7" {
    const allocator = std.testing.allocator;
    const data = try encode(allocator, "11");
    defer allocator.free(data);
    try expect(eql(u8, data, "4k8"));
}

test "test 8" {
    const allocator = std.testing.allocator;
    const data = try encode(allocator, "abc");
    defer allocator.free(data);
    try expect(eql(u8, data, "ZiCa"));
}

test "test 9" {
    const allocator = std.testing.allocator;
    const data = try encode(allocator, "1234598760");
    defer allocator.free(data);
    try expect(eql(u8, data, "3mJr7AoUXx2Wqd"));
}

test "test 10" {
    const allocator = std.testing.allocator;
    const data = try encode(allocator, "abcdefghijklmnopqrstuvwxyz");
    defer allocator.free(data);
    try expect(eql(u8, data, "3yxU3u1igY8WkgtjK92fbJQCd4BZiiT1v25f"));
}

test "test 11" {
    const allocator = std.testing.allocator;
    const data = try encode(allocator, "00000000000000000000000000000000000000000000000000000000000000");
    defer allocator.free(data);
    try expect(eql(u8, data, "3sN2THZeE9Eh9eYrwkvZqNstbHGvrxSAM7gXUXvyFQP8XvQLUqNCS27icwUeDT7ckHm4FUHM2mTVh1vbLmk7y"));
}
