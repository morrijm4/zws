const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const zws = @import("zws");
const App = zws.App;
const Request = zws.Request;
const Response = zws.Response;
const Context = zws.Context;
const Controller = zws.Controller;
const assets = zws.assets;
const logger = zws.logger;

const CounterController = struct {
    fn onRequest(
        req: *Request,
        res: *Response,
        ctx: *Context,
    ) anyerror!void {
        _ = req;

        const count = ctx.getUserData(u32);

        const gpa = ctx.arena.allocator();

        res.code = .Ok;
        res.body = try std.fmt.allocPrint(gpa, "{d}\n", .{count.*});
        try res.headers.put("Content-Type", "text/plain");
        try res.headers.put("Content-Length", try std.fmt.allocPrint(gpa, "{d}", .{
            res.body.len,
        }));

        count.* += 1;
    }

    fn init(gpa: Allocator) Allocator.Error!Controller.Interface {
        const count = try gpa.create(u32);
        count.* = 0;
        return .{
            .userdata = count,
            .on_request = &onRequest,
        };
    }

    fn deinit(self: Controller.Interface, gpa: Allocator) void {
        gpa.free(self.userdata);
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const buf = try gpa.alloc(u8, 1024 * 1024 * 16); // 16 MB
    defer gpa.free(buf);

    var fba = FixedBufferAllocator.init(buf);
    const arena = fba.allocator();

    var app = App.init(.{});
    try app.get(arena, "/counter", try CounterController.init(arena));
    try app.use(arena, assets.init("./public"));
    try app.use(arena, logger.init());
    try app.listen(io, arena, "127.0.0.1:3000");
}
