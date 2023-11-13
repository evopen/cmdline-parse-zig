const std = @import("std");

const Command = struct {
    name: []const u8,
    about: []const u8,
    args: []const Arg,

    fn parse(comptime self: *const Command, allocator: std.mem.Allocator) !?DeriveArgs(self.args) {
        const os_args = try std.process.argsAlloc(allocator);
        const Args = DeriveArgs(self.args);
        _ = Args;
        defer std.process.argsFree(allocator, os_args);

        if (os_args.len == 0) {
            self.printHelp();
            return null;
        }

        for (os_args) |os_arg| {
            if (std.mem.eql(u8, os_arg, "--help") or std.mem.eql(u8, os_arg, "-h")) {
                self.printHelp();
                return null;
            }
            inline for (self.args) |arg| {
                _ = arg;
            }
        }
        return undefined;
    }

    fn printHelp(comptime self: *const Command) void {
        std.debug.print("{s}\n", .{self.name});
        std.debug.print("{s}\n", .{self.about});
        std.debug.print("USAGE:\n", .{});
        inline for (self.args) |arg| {
            std.debug.print("  --{s}\t{s}", .{ arg.name, arg.help });
        }
    }
};

const Arg = struct {
    name: []const u8,
    T: type,
    long: bool,
    short: bool,
    help: []const u8,
    required: bool = false,
};

fn DeriveArgs(comptime args: []const Arg) type {
    const Type = std.builtin.Type;
    var len = 0;
    _ = len;
    var fields: [args.len]Type.StructField = undefined;
    for (&fields, args) |*field, arg| {
        field.* = Type.StructField{
            .name = arg.name,
            .type = arg.T,
            .is_comptime = false,
            .default_value = null,
            .alignment = @alignOf(arg.T),
        };
    }
    const data_type = @Type(std.builtin.Type{
        .Struct = .{
            .layout = .Auto,
            .fields = &fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
    return data_type;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const command = Command{
        .name = "clap-test",
        .about = "this is a cmdline test program in zig",
        .args = &[_]Arg{
            .{ .name = "width", .T = u32, .long = true, .short = true, .help = "the width of the image" },
            .{ .name = "height", .T = u32, .long = true, .short = true, .help = "the height of the image" },
        },
    };

    const args = try command.parse(allocator);
    _ = args;
}
