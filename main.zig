const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.clap);

inline fn strcmp(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn parse_str_value(comptime T: type, str: []const u8) !T {
    switch (T) {
        u8, i8, u16, i16, u32, i32, u64, i64, u128, i128, usize => return try std.fmt.parseInt(T, str, 0),
        f16, f32, f64, f128 => return try std.fmt.parseFloat(T, str),
        []const u8 => return str,
        else => return error.InvalidValue,
    }
}

pub const Command = struct {
    name: []const u8,
    about: []const u8,
    params: []const Param = &[_]Param{},
    subcommands: []const Command = &[_]Command{},

    /// the args list does not contain program name
    /// this method is recursive to parse subcommand
    /// return null if the user input does not allow the program to continue
    pub fn parse_from_str(comptime self: *const Command, args: []const [:0]const u8) !?DeriveCommand(self) {
        const CommandData = DeriveCommand(self);
        var command_data: CommandData = undefined;
        command_data.subcommand = null;

        if (args.len == 0) {
            log.debug("no arguments provided, printing help", .{});
            self.printHelp();
            return null;
        }

        // parse subcommands
        inline for (self.subcommands) |*command| {
            // only the first argument can be treated as subcommand
            if (strcmp(args[0], command.name)) {
                const subcommand_data = try command.parse_from_str(args[1..]);
                if (subcommand_data) |sub| {
                    command_data.subcommand = @unionInit(@typeInfo(@TypeOf(command_data.subcommand)).Optional.child, command.name, sub);
                } else {
                    return null;
                }
            }
        }

        inline for (self.params) |param| {
            if (param.T == void) {
                std.debug.panic("Param {s} has type void. This is not supported. If you want a flag use bool type", .{param.name});
            }
            var field = &@field(command_data.args, param.name);
            var i: usize = 0;
            var field_set: bool = false;
            while (i < args.len) : (i += 1) {
                if (strcmp(args[i], "--help") or strcmp(args[i], "-h")) {
                    self.printHelp();
                    return null;
                }

                // if we have a match, parse the str
                if ((param.long and strcmp(args[i][0..2], "--") and strcmp(args[i][2..], param.name)) or (param.short and args[i][0] == '-' and args[i][1] == param.name[0])) {
                    switch (param.T) {
                        bool => field.* = true,
                        else => {
                            if (i + 1 >= args.len) {
                                std.log.warn("missing value for argument: {s}", .{param.name});
                                return null;
                            }
                            field.* = try parse_str_value(param.T, args[i + 1]);
                            i += 1;
                        },
                    }
                    field_set = true;

                    // we don't `continue` here, the rule is last one wins
                }
            }
            if (!field_set) {
                // no match, fill in default value
                if (param.default_value) |default| {
                    field.* = try parse_str_value(param.T, default);
                } else if (@typeInfo(param.T) == .Optional) {
                    field.* = null;
                } else {
                    std.log.warn("missing required argument: {s}", .{param.name});
                    return null;
                }
            }
        }

        return command_data;
    }

    pub fn parse(comptime self: *const Command, allocator: std.mem.Allocator) !?DeriveCommand(self) {
        const os_args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, os_args[1..]);
        return self.parse_from_str(os_args);
    }

    fn printHelp(comptime self: *const Command) void {
        std.debug.print("{s}\n", .{self.name});
        std.debug.print("{s}\n", .{self.about});
        std.debug.print("USAGE:\n", .{});
        inline for (self.params) |arg| {
            std.debug.print("  --{s}\t{s}\n", .{ arg.name, arg.help });
        }
    }
};

/// if neither long nor short is set, it's a positional argument
pub const Param = struct {
    name: []const u8,
    T: type,
    long: bool,
    short: bool,
    help: []const u8,
    default_value: ?[]const u8 = null,
};

/// return a struct containing the arguments for a command
/// const DerivedArgs = struct {
///     what: u32,
///     ever: []const u8,
///     this: ?f32,
///     is: bool,
/// }
fn DeriveArgs(comptime args: []const Param) type {
    const Type = std.builtin.Type;
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

/// return an taged union of commands
/// const DerivedCommands = union(enum) {
///    start: DerivedCommand,
///    stop: DerivedCommand,
/// }
fn DeriveCommands(comptime commands: []const Command) type {
    const Type = std.builtin.Type;
    var tags_fields: [commands.len]Type.EnumField = undefined;
    for (&tags_fields, commands, 0..) |*field, command, i| {
        field.* = Type.EnumField{
            .name = command.name,
            .value = i,
        };
    }
    const tag_type = @Type(std.builtin.Type{
        .Enum = .{
            .fields = &tags_fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_exhaustive = true,
            .tag_type = u32, // TODO: use a smaller type based on the number of commands
        },
    });
    var union_fields: [commands.len]Type.UnionField = undefined;
    for (&union_fields, commands, 0..) |*field, *command, i| {
        _ = i;
        const field_type = DeriveCommand(command);
        field.* = Type.UnionField{
            .name = command.name,
            .type = field_type,
            .alignment = @alignOf(field_type),
        };
    }
    const union_type = @Type(Type{ .Union = .{
        .tag_type = tag_type,
        .decls = &[_]std.builtin.Type.Declaration{},
        .layout = .Auto,
        .fields = &union_fields,
    } });
    return union_type;
}

/// return a single command data type
/// const DerivedCommand = struct {
///     args: DerivedArgs,
///     subcommand: DerivedCommand, // tagged union this is
/// }
fn DeriveCommand(comptime command: *const Command) type {
    const Type = std.builtin.Type;
    var fields: [2]Type.StructField = undefined;
    fields[0] = Type.StructField{
        .name = "args",
        .type = DeriveArgs(command.params),
        .is_comptime = false,
        .default_value = null,
        .alignment = @alignOf(DeriveArgs(command.params)),
    };
    fields[1] = Type.StructField{
        .name = "subcommand",
        .type = ?DeriveCommands(command.subcommands),
        .is_comptime = false,
        .default_value = null,
        .alignment = @alignOf(DeriveCommands(command.subcommands)),
    };
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

test "mandatory parameters" {
    const command = Command{
        .name = "command-test",
        .about = "this is root command",
        .params = &[_]Param{
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
                .short = false,
                .help = "the height of the image",
            },
        },
    };
    const matches = try command.parse_from_str(&[_][:0]const u8{
        "--width",
        "100",
        "--height",
        "200",
    });

    std.debug.assert(matches.?.args.width == 100);
    std.debug.assert(matches.?.args.height == 200);
}

test "optional parameters" {
    const command = Command{
        .name = "command-test",
        .about = "this is root command",
        .params = &[_]Param{
            .{
                .name = "width",
                .T = u32,
                .long = true,
                .short = true,
                .help = "the width of the image",
            },
            .{
                .name = "height",
                .T = ?u32,
                .long = true,
                .short = false,
                .help = "the height of the image",
            },
        },
    };
    const matches = try command.parse_from_str(&[_][:0]const u8{
        "--width",
        "100",
    });

    std.debug.assert(matches.?.args.width == 100);
    std.debug.assert(matches.?.args.height == null);
}

test "subcommand" {
    const command = Command{
        .name = "command-test",
        .about = "this is root command",
        .params = &[_]Param{
            .{
                .name = "width",
                .T = ?u32,
                .long = true,
                .short = true,
                .help = "the width of the image",
            },
            .{
                .name = "height",
                .T = ?u32,
                .long = true,
                .short = false,
                .help = "the height of the image",
            },
        },
        .subcommands = &[_]Command{
            .{
                .name = "start",
                .about = "this is second layer command",
                .params = &[_]Param{
                    .{
                        .name = "quiet", // this is a flag
                        .T = bool,
                        .long = true,
                        .short = true,
                        .help = "start quietly",
                    },
                },
            },
            .{
                .name = "stop",
                .about = "this is another second layer command",
                .params = &[_]Param{
                    .{
                        .name = "purge",
                        .T = bool,
                        .long = true,
                        .short = false,
                        .help = "start quietly",
                    },
                },
            },
        },
    };

    const matches_1 = try command.parse_from_str(&[_][:0]const u8{
        "start",
        "--quiet",
    });
    const subcommand = matches_1.?.subcommand.?;
    switch (subcommand) {
        .start => {
            std.debug.assert(subcommand.start.args.quiet == true);
        },
        else => {
            return error.WrongBranch;
        },
    }
}
