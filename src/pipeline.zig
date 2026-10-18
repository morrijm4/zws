const std = @import("std");
const Allocator = std.mem.Allocator;

const http = @import("http.zig");
const Request = http.Request;

const Controller = @import("controller.zig");

pub const Pipeline = @This();

global: std.ArrayList(Controller),
prefixed: std.ArrayList(Controller),

gets: std.StringHashMapUnmanaged(Controller),
heads: std.StringHashMapUnmanaged(Controller),
posts: std.StringHashMapUnmanaged(Controller),
puts: std.StringHashMapUnmanaged(Controller),
patchs: std.StringHashMapUnmanaged(Controller),
deletes: std.StringHashMapUnmanaged(Controller),
options: std.StringHashMapUnmanaged(Controller),
connects: std.StringHashMapUnmanaged(Controller),

index: u32,

pub fn init() Pipeline {
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

pub fn deinit(self: *Pipeline, gpa: Allocator) void {
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
    self: *Pipeline,
    gpa: Allocator,
    kind: Controller.Kind,
) Allocator.Error!void {
    const controller: Controller = .{
        .priority = self.index,
        .kind = kind,
    };

    self.index += 1;

    try switch (kind) {
        .global => self.global.append(gpa, controller),
        .prefixed => self.prefixed.append(gpa, controller),
        .get => |h| self.gets.put(gpa, h.path, controller),
        .head => |h| self.heads.put(gpa, h.path, controller),
        .post => |h| self.posts.put(gpa, h.path, controller),
        .put => |h| self.puts.put(gpa, h.path, controller),
        .patch => |h| self.patchs.put(gpa, h.path, controller),
        .delete => |h| self.deletes.put(gpa, h.path, controller),
        .option => |h| self.options.put(gpa, h.path, controller),
        .connect => |h| self.connects.put(gpa, h.path, controller),
    };
}

pub fn build(
    self: *Pipeline,
    gpa: Allocator,
    req: *Request,
) Allocator.Error![]Controller {
    var pipeline = try self.global.clone(gpa);

    for (self.prefixed.items) |controller| {
        switch (controller.kind) {
            .prefixed => |h| {
                if (std.mem.startsWith(u8, req.path.buf, h.prefix)) {
                    try pipeline.append(gpa, controller);
                }
            },
            else => unreachable,
        }
    }

    const maybe_controller = switch (req.method) {
        .GET => self.gets.get(req.path.buf),
        .HEAD => self.heads.get(req.path.buf),
        .POST => self.posts.get(req.path.buf),
        .PUT => self.puts.get(req.path.buf),
        .PATCH => self.patchs.get(req.path.buf),
        .DELETE => self.deletes.get(req.path.buf),
        .OPTIONS => self.options.get(req.path.buf),
        .CONNECT => self.connects.get(req.path.buf),
    };

    if (maybe_controller) |controller| {
        try pipeline.append(gpa, controller);
    }

    std.mem.sort(Controller, pipeline.items, {}, Controller.lessThan);
    return pipeline.items;
}
