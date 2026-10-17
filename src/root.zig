//! [ZWS] Zig Web Server
const http = @import("http.zig");
const app = @import("app.zig");

pub const assets = @import("plugins/assets.zig");
pub const logger = @import("plugins/logger.zig");

pub const App = app.App;
pub const Request = http.Request;
pub const Response = http.Response;
pub const Error = http.Error;
