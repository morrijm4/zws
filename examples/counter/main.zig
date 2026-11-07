const std = @import("std");
const Allocator = std.mem.Allocator;
const zws = @import("zws");

const CounterController = struct {
    fn init(gpa: Allocator) Allocator.Error!zws.Controller.Interface {
        const count = try gpa.create(u32);
        count.* = 0;
        return .{
            .userdata = count,
            .on_request = &onRequest,
        };
    }

    fn deinit(self: zws.Controller.Interface, gpa: Allocator) void {
        gpa.free(self.userdata);
    }

    fn onRequest(
        req: *zws.Request,
        res: *zws.Response,
        ctx: *zws.Context,
    ) anyerror!void {
        _ = req;

        const count = ctx.getUserData(u32);
        const gpa = ctx.arena.allocator();

        res.code = .ok;
        res.body = try std.fmt.allocPrint(gpa, "{d}\n", .{count.*});
        try res.headers.put("Content-Type", "text/plain");
        try res.headers.put("Content-Length", try std.fmt.allocPrint(gpa, "{d}", .{
            res.body.len,
        }));

        count.* += 1;
    }
};

pub fn main(init: std.process.Init) !void {
    var app = zws.App.init(.{});
    try app.get(init.gpa, "/counter", try CounterController.init(init.gpa));
    try app.use(init.gpa, zws.logger.init());
    try app.listen(init.io, init.gpa, "127.0.0.1:3000");
}
