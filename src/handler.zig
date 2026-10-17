const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const http = @import("http.zig");
const Request = http.Request;
const Response = http.Response;

const work = @import("worker.zig");
const Context = work.Context;

pub const Handlers = @This();

global: std.ArrayList(Handler),
prefixed: std.ArrayList(Handler),

gets: std.StringHashMapUnmanaged(Handler),
heads: std.StringHashMapUnmanaged(Handler),
posts: std.StringHashMapUnmanaged(Handler),
puts: std.StringHashMapUnmanaged(Handler),
patchs: std.StringHashMapUnmanaged(Handler),
deletes: std.StringHashMapUnmanaged(Handler),
options: std.StringHashMapUnmanaged(Handler),
connects: std.StringHashMapUnmanaged(Handler),

index: u32,

pub fn init() Handlers {
    return .{
        .global = .empty,
        .prefixed = .empty,
        .gets = .empty,
        .heads = .empty,
        .posts = .empty,
        .puts = .empty,
        .patchs = .empty,
        .deletes = .empty,
        .options = .empty,
        .connects = .empty,
        .index = 0,
    };
}

pub fn deinit(self: *Handlers, gpa: Allocator) void {
    self.global.deinit(gpa);
    self.prefixed.deinit(gpa);
    self.gets.deinit(gpa);
    self.heads.deinit(gpa);
    self.posts.deinit(gpa);
    self.puts.deinit(gpa);
    self.patchs.deinit(gpa);
    self.deletes.deinit(gpa);
    self.options.deinit(gpa);
    self.connects.deinit(gpa);
}

pub fn add(
    self: *Handlers,
    gpa: Allocator,
    kind: Handler.Kind,
) Allocator.Error!void {
    const handler: Handler = .{
        .priority = self.index,
        .kind = kind,
    };

    self.index += 1;

    try switch (kind) {
        .global => self.global.append(gpa, handler),
        .prefixed => self.prefixed.append(gpa, handler),
        .get => |h| self.gets.put(gpa, h.path, handler),
        .head => |h| self.heads.put(gpa, h.path, handler),
        .post => |h| self.posts.put(gpa, h.path, handler),
        .put => |h| self.puts.put(gpa, h.path, handler),
        .patch => |h| self.patchs.put(gpa, h.path, handler),
        .delete => |h| self.deletes.put(gpa, h.path, handler),
        .option => |h| self.options.put(gpa, h.path, handler),
        .connect => |h| self.connects.put(gpa, h.path, handler),
    };
}

pub const Callback = *const fn (
    *Request,
    *Response,
    *Context,
) anyerror!void;

pub const Global = struct {
    on_request: ?Callback,
    on_error: ?Callback,
    userdata: *anyopaque,
};

pub const Prefixed = struct {
    on_request: ?Callback,
    on_error: ?Callback,
    userdata: *anyopaque,
    prefix: []const u8,
};

pub const Exact = struct {
    on_request: ?Callback,
    on_error: ?Callback,
    userdata: *anyopaque,
    path: []const u8,
};

pub const Handler = struct {
    priority: u32,
    kind: Kind,

    pub fn getUserData(self: *Handler, U: type) *U {
        const userdata = switch (self.kind) {
            .global => |h| h.userdata,
            .prefixed => |h| h.userdata,
            .get,
            .head,
            .post,
            .put,
            .patch,
            .delete,
            .connect,
            .option,
            => |h| h.userdata,
        };

        return @ptrCast(@alignCast(userdata));
    }

    pub const Kind = union(enum) {
        global: Global,
        prefixed: Prefixed,
        get: Exact,
        head: Exact,
        post: Exact,
        put: Exact,
        patch: Exact,
        delete: Exact,
        option: Exact,
        connect: Exact,
    };

    pub fn lessThan(_: void, a: Handler, b: Handler) bool {
        return a.priority < b.priority;
    }

    pub const Interface = struct {
        on_request: ?Callback = null,
        on_error: ?Callback = null,
        userdata: *anyopaque,
    };
};
