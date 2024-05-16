//!
//! Compile time diagnostics module.
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
pub const SourceRef = @import("SourceRef.zig");

pub const Description = union(enum) {
    static: []const u8,
    dynamic: struct { begin: usize, end: usize },
};

pub const Diagnostic = struct {
    pub const Severity = enum(u8) {
        Hint = 1,
        Warning = 2,
        Error = 3,

        pub fn terminalColor(self: Severity) []const u8 {
            return switch (self) {
                .Warning => SourceRef.terminal_colors.yellow,
                .Error => SourceRef.terminal_colors.red,
                .Hint => SourceRef.terminal_colors.blue,
            };
        }
    };

    /// A description of the error.
    description: Description,
    /// An optional view into the source code that localizes the error.
    location: ?[]const u8 = null,
    /// The severity of the diagnostic.
    severity: Severity = .Error,
    /// A linked list of related diagnostics.
    related: ?*Diagnostic = null,
    /// Whether this is a primary diagnostic, i.e. it's not related to an earlier diagnostic.
    primary: bool = true,
};

pub const DiagnosticList = struct {
    /// The diagnostics
    list: ArrayList(Diagnostic),
    /// Points to the last appended primary/related diagnostic
    last: ?*Diagnostic,
    /// Holds descriptions in a contigous buffer
    description_buffer: ArrayList(u8),
    /// The maximum severity of diagnostics encountered so far
    max_severity: ?Diagnostic.Severity,
    /// The source code
    source: []const u8,
    /// Disable terminal colors
    no_color: bool = false,

    allocator: Allocator,

    pub fn init(allocator: Allocator, source: []const u8) DiagnosticList {
        return .{
            .list = ArrayList(Diagnostic).init(allocator),
            .last = null,
            .description_buffer = ArrayList(u8).init(allocator),
            .source = source,
            .allocator = allocator,
            .max_severity = null,
        };
    }

    pub fn deinit(self: *DiagnosticList) void {
        for (self.list.items) |err| {
            if (err.related) |related| {
                var curr: ?*Diagnostic = related;
                var prev: *Diagnostic = undefined;
                while (curr) |curr_| {
                    prev = curr_;
                    curr = curr_.related;
                    self.allocator.destroy(prev);
                }
            }
        }
        self.list.deinit();
        self.description_buffer.deinit();
    }

    pub fn newDynamicDescription(
        self: *DiagnosticList,
        comptime fmt: []const u8,
        args: anytype,
        // i screwed up here, it should return Description but I don't wanna change all occurences...
    ) !@TypeOf(@as(Description, undefined).dynamic) {
        const begin = self.description_buffer.items.len;
        try self.description_buffer.writer().print(fmt, args);
        return .{
            .begin = begin,
            .end = self.description_buffer.items.len,
        };
    }

    pub fn getDescriptionString(self: *const DiagnosticList, description: Description) []const u8 {
        return switch (description) {
            .static => |v| v,
            .dynamic => |v| self.description_buffer.items[v.begin..v.end],
        };
    }

    pub fn addDiagnostic(self: *DiagnosticList, diagnostic: Diagnostic) !void {
        try self.list.append(diagnostic);
        self.last = &self.list.items[self.list.items.len - 1];
        self.updateMaxSeverity(diagnostic.severity);
    }

    pub fn addRelated(self: *DiagnosticList, diagnostic: Diagnostic) !void {
        if (self.last) |*last| {
            var copy = try self.allocator.create(Diagnostic);
            copy.* = diagnostic;
            copy.primary = false;
            last.*.related = copy;
            last.* = copy;
            self.updateMaxSeverity(diagnostic.severity);
        } else return error.NoPreviousDiagnostic;
    }

    fn updateMaxSeverity(self: *DiagnosticList, severity: Diagnostic.Severity) void {
        const current: u8 = @intFromEnum(self.max_severity orelse {
            self.max_severity = severity;
            return;
        });
        const new: u8 = @intFromEnum(severity);
        self.max_severity = @enumFromInt(@max(current, new));
    }

    pub fn hasDiagnosticsMinSeverity(
        self: *const DiagnosticList,
        severity: Diagnostic.Severity,
    ) bool {
        if (self.max_severity) |max_severity| {
            const max: u8 = @intFromEnum(max_severity);
            const requested: u8 = @intFromEnum(severity);
            return max >= requested;
        } else return false;
    }

    pub fn printSingleDiagnostic(
        self: *const DiagnosticList,
        diagnostic: *const Diagnostic,
        writer: anytype,
    ) !void {
        if (diagnostic.location) |location| {
            const ref = try SourceRef.init(self.source, location);
            try writer.print("{s} (line {d}): {s}:\n", .{
                @tagName(diagnostic.severity),
                ref.line_num,
                self.getDescriptionString(diagnostic.description),
            });
            try ref.print(writer, if (self.no_color) null else diagnostic.severity.terminalColor());
        } else {
            try writer.print("{s}: {s}.\n", .{
                @tagName(diagnostic.severity),
                self.getDescriptionString(diagnostic.description),
            });
        }
    }

    pub fn printAllDiagnostic(
        self: *const DiagnosticList,
        writer: anytype,
    ) !void {
        var it = self.iterator();
        while (it.next()) |diagnostic| {
            if (diagnostic.primary) try writer.writeAll("=" ** 80 ++ "\n");
            try self.printSingleDiagnostic(diagnostic, writer);
        }
    }

    pub fn iterator(self: *const DiagnosticList) Iterator {
        return .{ .diagnostics = self };
    }

    pub const Iterator = struct {
        diagnostics: *const DiagnosticList,
        primary_index: usize = 0,
        related: ?*const Diagnostic = null,

        pub fn next(self: *Iterator) ?*const Diagnostic {
            if (self.related) |related| {
                self.related = related.related;
                return related;
            } else {
                if (self.primary_index == self.diagnostics.list.items.len) {
                    return null;
                } else {
                    const diagnostic = &self.diagnostics.list.items[self.primary_index];
                    self.primary_index += 1;
                    self.related = diagnostic.related;
                    return diagnostic;
                }
            }
        }
    };
};
