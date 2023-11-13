const std = @import("std");

inline fn strcmp(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

const Command = struct {
    name: []const u8,
    about: []const u8,
    args: []const Arg,

    fn parse(comptime self: *const Command, allocator: std.mem.Allocator) !?DeriveArgs(self.args) {
        const os_args = try std.process.argsAlloc(allocator);
        const Args = DeriveArgs(self.args);
        var args: Args = undefined;
        defer std.process.argsFree(allocator, os_args);

        if (os_args.len == 0) {
            self.printHelp();
            return null;
        }

        inline for (self.args) |arg| {
            for (os_args) |os_arg| {
                if (strcmp(os_arg, "--help") or strcmp(os_arg, "-h")) {
                    self.printHelp();
                    return null;
                }

                // no match, fill in default value
                if (arg.default_value) |default| {
                    switch (arg.T) {
                        u8, i8, u16, i16, u32, i32, u64, i64, u128, i128, usize => @field(args, arg.name) = try std.fmt.parseInt(arg.T, default, 0),
                        f16, f32, f64, f128 => @field(args, arg.name) = try std.fmt.parseFloat(arg.T, default),
                        []const u8 => @field(args, arg.name) = default,
                        else => std.debug.panic("unimplemented", .{}),
                    }
                }
            }
        }

        return args;
    }

    fn printHelp(comptime self: *const Command) void {
        std.debug.print("{s}\n", .{self.name});
        std.debug.print("{s}\n", .{self.about});
        std.debug.print("USAGE:\n", .{});
        inline for (self.args) |arg| {
            std.debug.print("  --{s}\t{s}\n", .{ arg.name, arg.help });
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
    default_value: ?[]const u8 = null,
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
            .{
                .name = "width",
                .T = u32,
                .long = true,
                .short = true,
                .help = "the width of the image",
            },
            .{
                .name = "height",
                .T = u32,
                .long = true,
                .short = true,
                .help = "the height of the image",
            },
            .{
                .name = "scene",
                .T = usize,
                .long = true,
                .short = false,
                .help = "scene to render",
                .default_value = "0",
            },
        },
    };

    const args = try command.parse(allocator);
    _ = args;
}
