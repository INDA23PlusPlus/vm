const std = @import("std");
const blue = @import("blue");

const CodeGen = @This();

// TODO: deal with variables named 'value' or 'label'

ast: *const blue.Ast,
output: std.fs.File.Writer,
allocator: std.mem.Allocator,
functions: std.ArrayList(std.ArrayList(u8)),
counter: usize,

pub fn init(
    ast: *const blue.Ast,
    output: std.fs.File,
    allocator: std.mem.Allocator,
) CodeGen {
    return .{
        .ast = ast,
        .output = output.writer(),
        .allocator = allocator,
        .functions = std.ArrayList(std.ArrayList(u8)).init(allocator),
        .counter = 1,
    };
}

pub fn deinit(self: *CodeGen) void {
    self.functions.deinit();
}

pub fn run(self: *CodeGen) !void {
    try self.startFunction();
    try self.write(
        \\export function l $main() {{
        \\@start
        \\    call $__vemod_init()
        \\    %value_0 =l copy 0
        \\
    , .{});
    const ret_id = try self.genNode(self.ast.root);
    try self.write(
        \\    call $__vemod_fini()
        \\    ret %value_{d}
        \\}}
        \\
        \\
    , .{ret_id});
    try self.finishFunction();
}

fn startFunction(self: *CodeGen) !void {
    try self.functions.append(std.ArrayList(u8).init(self.allocator));
}

fn finishFunction(self: *CodeGen) !void {
    const function = &self.functions.items[self.functions.items.len - 1];
    try self.output.writeAll(function.items);
    function.deinit();
    _ = self.functions.pop();
}

fn countParams(self: CodeGen, id: ?usize) usize {
    var id_ = id;
    var count: usize = 0;
    while (id_) |node_id| {
        count += 1;
        id_ = self.ast.getNodeConst(node_id).param.next;
    }
}

fn newID(self: *CodeGen) usize {
    defer self.counter += 1;
    return self.counter;
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.io.getStdErr().writer().print("\x1b[31merror\x1b[0m: " ++ fmt, args) catch {};
    std.process.exit(1);
}

fn write(self: *CodeGen, comptime fmt: []const u8, args: anytype) !void {
    const function = &self.functions.items[self.functions.items.len - 1];
    try function.writer().print(fmt, args);
}

fn genNode(self: *CodeGen, id: usize) !usize {
    const nd: *const blue.Ast.Node = self.ast.getNodeConst(id);

    switch (nd.*) {
        .binop => |v| {
            const l_value_id = try self.genNode(v.lhs);
            const r_value_id = try self.genNode(v.rhs);
            const res_value_id = self.newID();
            const opstr = switch (v.op.tag) {
                .@"+" => "add",
                .@"-" => "sub",
                .@"*" => "mul",
                .@"/" => "div",
                .@"%" => "rem",
                .@"=" => "ceql",
                .@"!=" => "cnel",
                .@"<=" => "cslel",
                .@"<" => "csltl",
                .@">=" => "csgel",
                .@">" => "csgtl",
                else => fail("unsupported operator: {s}\n", .{@tagName(v.op.tag)}),
            };
            try self.write("    %value_{d} =l {s} %value_{d}, %value_{d}\n", .{
                res_value_id,
                opstr,
                l_value_id,
                r_value_id,
            });
            return res_value_id;
        },
        .unop => |v| {
            const opnd_value_id = try self.genNode(v.opnd);
            const res_value_id = self.newID();
            const opstr = switch (v.op.tag) {
                .@"-" => "neg",
                else => fail("unsupported operator: {s}\n", .{@tagName(v.op.tag)}),
            };
            try self.write("    %value_{d} =l {s} %value_{d}\n", .{
                res_value_id,
                opstr,
                opnd_value_id,
            });
            return res_value_id;
        },
        .if_expr => |v| {
            const cond_id = try self.genNode(v.cond);
            const then_label_id = self.newID();
            const else_label_id = self.newID();
            const done_label_id = self.newID();
            const res_id = self.newID();

            try self.write("    jnz %value_{d}, @then_{d}, @else_{d}\n", .{
                cond_id,
                then_label_id,
                else_label_id,
            });

            try self.write("\n@then_{d}\n", .{then_label_id});
            const then_value_id = try self.genNode(v.then);
            try self.write("    %value_{d} =l copy %value_{d}\n", .{ res_id, then_value_id });
            try self.write("    jmp @done_{d}\n", .{done_label_id});

            try self.write("\n@else_{d}\n", .{else_label_id});
            const else_value_id = try self.genNode(v.else_);
            try self.write("    %value_{d} =l copy %value_{d}\n", .{ res_id, else_value_id });
            try self.write("    jmp @done_{d}\n", .{done_label_id});

            try self.write("\n@done_{d}\n", .{done_label_id});

            return res_id;
        },
        .let_expr => |v| {
            _ = try self.genNode(v.stmts);
            return try self.genNode(v.in);
        },
        .let_entry => |v| {
            if (v.params) |params| {
                try self.startFunction();
                try self.write("function l ${s}_{d}(", .{ v.name, v.symid });
                _ = try self.genNode(params);
                try self.write(") {{\n@start\n    %value_0 =l copy 0\n", .{});
                const value_id = try self.genNode(v.expr);
                try self.write("    ret %value_{d}\n}}\n\n", .{value_id});
                try self.finishFunction();
            } else {
                if (v.is_const) {
                    fail("constants are yet to implemented\n", .{});
                }
                const value_id = try self.genNode(v.expr);
                try self.write("    %{s}_{d} =l copy %value_{d}\n", .{ v.name, v.symid, value_id });
            }

            if (v.next) |next| {
                _ = try self.genNode(next);
            }
        },
        .param => |v| {
            // TODO: non-recursive
            try self.write("l %{s}_{d}", .{ v.name, v.symid });
            if (v.next) |next| {
                try self.write(", ", .{});
                _ = try self.genNode(next);
            }
        },
        .reference => |v| {
            const res_id = self.newID();

            if (v.args) |_| {
                var arg_ids = std.ArrayList(usize).init(self.allocator);
                defer arg_ids.deinit();

                var arg = v.args;
                while (arg) |a| {
                    const arg_nd = self.ast.getNodeConst(a);
                    try arg_ids.append(try self.genNode(arg_nd.arg.expr));
                    arg = arg_nd.arg.next;
                }

                try self.write("    %value_{d} =l call ${s}_{d}(", .{ res_id, v.name, v.symid });

                for (arg_ids.items) |arg_id| {
                    try self.write("l %value_{d}, ", .{arg_id});
                }

                try self.write(")\n", .{});
            } else {
                try self.write("    %value_{d} =l copy %{s}_{d}\n", .{ res_id, v.name, v.symid });
            }

            return res_id;
        },
        .arg => unreachable,
        .number => |v| {
            // TODO: assert integer
            const value_id = self.newID();
            try self.write("    %value_{d} =l copy {s}\n", .{ value_id, v.where });
            return value_id;
        },
        .println => |v| {
            const value_id = try self.genNode(v.expr);
            try self.write("    call $__vemod_println(l %value_{d})\n", .{value_id});
        },
        .print => |v| {
            const value_id = try self.genNode(v.expr);
            try self.write("    call $__vemod_print(l %value_{d})\n", .{value_id});
        },
        .compound => |v| {
            _ = try self.genNode(v.discard);
            return try self.genNode(v.keep);
        },
        else => fail("unsupported language construct: {s}\n", .{@tagName(nd.*)}),
    }

    return 0;
}
