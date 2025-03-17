const std = @import("std");
const cv = @import("zigcv");
const websocket = @import("websocket");
const ble = @import("simpleble.zig"); // animatronic eyes controlled over bluetooth

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Mat = cv.Mat;
const Size = cv.Size;

// TODO: remove use of Result.id - we only track one object at a time anyways

var btConnected: bool = false;

// BLE HMSoft10
//const btPeriphStr: []const u8 = "A4:06:E9:8E:00:0A";
//const btServiceUuidStr: []const u8 = "0000ffe0-0000-1000-8000-00805f9b34fb";
//const btCharId: usize = 0;

// micro:bit v1
//const btPeriphStr: []const u8 = "FB:C9:6D:CB:9D:63";
//const btServiceUuidStr: []const u8 = "e2e00001-15cf-4074-9331-6fac42a4920b";
//const btCharId: usize = 1; // choose second characteristic, as it is writable

// microbi:t v2
const btPeriphStr: []const u8 = "D1:FB:74:83:54:34";
const btServiceUuidStr: []const u8 = "e2e10001-15cf-4074-9331-6fac42a4920b";
const btCharId: usize = 1; // choose second characteristic, as it is writable

var btPeripheral: ble.simpleble_peripheral_t = undefined;
var btService: ble.simpleble_service_t = undefined; //.{ .value = microbitUartServicePtr };

// *** GLOBALS ***
pub const io_mode = .evented;
const green = cv.Color{ .g = 255 };
const red = cv.Color{ .r = 255 };

// SSE mobilenet v2 (90)
// var CLASSES = [_][]const u8{
//     "unknown", "person","bicycle","car","motorcycle","airplane","bus","train","truck","boat","traffic light","fire hydrant","unknown","stop sign","parking meter",
//     "bench","bird","cat","dog","horse","sheep","cow","elephant","bear","zebra","giraffe","unknown","backpack","umbrella","unknown","unknown","handbag",
//     "tie","suitcase","frisbee","skis","snowboard","sports ball","kite","baseball bat","baseball glove","skateboard","surfboard","tennis racket","bottle",
//     "unknown","wine glass","cup","fork","knife","spoon","bowl","banana","apple","sandwich","orange","broccoli","carrot","hot dog","pizza","donut","cake",
//     "chair","couch","potted plant","bed","unknown","dining table","unknown","unknown","toilet","unknown","tv","laptop","mouse","remote","keyboard",
//     "cell phone","microwave","oven","toaster","sink","refrigerator","unknown","book","clock","vase","scissors","teddy bear","hair drier","toothbrush",
// };
// piconet coco 80 classes
var CLASSES = [_][]const u8{
    "person",       "bicycle",   "car",           "motorcycle", "airplane",     "bus",            "train",      "truck",      "boat",          "traffic light",
    "fire hydrant", "stop sign", "parking meter", "bench",      "bird",         "cat",            "dog",        "horse",      "sheep",         "cow",
    "elephant",     "bear",      "zebra",         "giraffe",    "backpack",     "umbrella",       "handbag",    "tie",        "suitcase",      "frisbee",
    "skis",         "snowboard", "sports ball",   "kite",       "baseball bat", "baseball glove", "skateboard", "surfboard",  "tennis racket", "bottle",
    "wine glass",   "cup",       "fork",          "knife",      "spoon",        "bowl",           "banana",     "apple",      "sandwich",      "orange",
    "broccoli",     "carrot",    "hot dog",       "pizza",      "donut",        "cake",           "chair",      "couch",      "potted plant",  "bed",
    "dining table", "toilet",    "tv",            "laptop",     "mouse",        "remote",         "keyboard",   "cell phone", "microwave",     "oven",
    "toaster",      "sink",      "refrigerator",  "book",       "clock",        "vase",           "scissors",   "teddy bear", "hair drier",    "toothbrush",
};

// GameMode is modified by timer and external Socket commands
pub const GameMode = enum(u8) {
    IDLE,
    START,
    STOP,
    SNAP,
    TRACK,
    TRACK_IDLE,
    _,

    // Probably no longer neccessary
    pub fn enum2str(self: GameMode) []u8 {
        return std.meta.fields(?GameMode)[self];
    }
    pub fn str2enum(str: []const u8) ?GameMode {
        return std.meta.stringToEnum(GameMode, str);
    }
};

var gameMode = GameMode.IDLE;
var lastGameMode = GameMode.IDLE;
var trackerVit: cv.TrackerVit = undefined;
const initialCenterPoint = cv.Point{ .x = 160, .y = 160 };

var wsClient: websocket.Client = undefined; // Websocket client
//var client: std.net.Stream = undefined;       // TCP client for sending tracking / predictions / messages
//var httpClient: std.http.Client = undefined;  // HTTP client for sending images
//var server: std.net.StreamServer = undefined; // listening TCP socket for receiving commands from client

// This is the message handler API:
// request format:  [cmd] [optional param]
// response format: [0x00] [GameMode] [length 4byte int] [string byte array]
// 1: Change of GameMode         - ex: 0x01 0x02 = change to GameMode.STOP
// 2: Connect BTLE peripheral    - ex: 0x02
// 3: Disconnect BTLE peripheral - ex: 0x03
const MsgHandler = struct {
    allocator: Allocator,

    // Handle Commands via websocket
    pub fn serverMessage(self: MsgHandler, msg: []u8) !void {
        std.log.debug("got msg: {any}", .{msg});
        const cmd = msg[0];
        if (cmd == 1) {
            const mode: GameMode = @enumFromInt(msg[1]);
            lastGameMode = gameMode;
            gameMode = mode;
            const mb: u8 = std.mem.asBytes(&gameMode)[0];
            std.log.debug("switched mode from: {any} to {any}", .{ lastGameMode, gameMode });
            const res = try self.allocator.alloc(u8, 8);
            @memcpy(res, &[_]u8{ 0, mb, 2, 0, 0, 0, 0x4f, 0x4b }); // OK
            _ = try wsClient.writeBin(res);
        } else if (cmd == 2) {
            connectBluetooth();
        } else if (cmd == 3) {
            disconnectBluetooth();
        } else {
            std.log.debug("ignoring unknown command: {d}", .{cmd});
            const res = try self.allocator.alloc(u8, 8);
            const mb: u8 = std.mem.asBytes(&gameMode)[0];
            @memcpy(res, &[_]u8{ 0, mb, 2, 0, 0, 0, 0x4b, 0x4f }); // KO
            _ = try wsClient.writeBin(res);
        }
    }
    pub fn close(_: MsgHandler) void {}
};

// Result is a rect object containing scores and a class
const Result = struct {
    id: usize, // the result score id
    box: cv.Rect,
    centre: cv.Point,
    prevCentre: cv.Point,
    score: f32,
    classId: usize,
    disappeared: i32 = 0, // we dont use this unless we track multiple objects

    fn increaseDisapperance(self: *Result) void {
        self.disappeared += 1;
    }
};

// This is the main tracking function for the game
pub const Error = error{MissingFocus};

const Tracker = struct {
    const Self = @This();
    allocator: Allocator,
    maxLife: i32, // num of frames to keep disappeared objects before removing them
    objects: ArrayList(Result), // box, centroid (x, y), scores etc.
    disappeared: ArrayList(i32), // counter(s) for measuring disappearance
    focusId: usize, // The ID of Result struct containing ball - our main focus
    lastFocusObj: ?Result, // The Result struct of LAST KNOWN GOOD focus - failover even if lost/disappeared
    fpsTimer: std.time.Timer, // FPS timer
    overlay: Mat, // empty mat to draw movements on
    frames: f64,
    fps: f64,
    tracking: bool,
    trackingDisappeared: i32,
    trackingIdleTimer: std.time.Timer, // tracker timer for detecting stale objects
    trackingPrevCentroid: cv.Point, // previous trackerVit centroid

    pub fn init(allocator: Allocator) !Self {
        const objs: ArrayList(Result) = ArrayList(Result).init(allocator);
        const disapp: ArrayList(i32) = ArrayList(i32).init(allocator);
        const overlay = try cv.Mat.initOnes(320, 320, cv.Mat.MatType.cv8uc4); // CV_8UC4 for transparency
        const fpsTimer = try std.time.Timer.start();
        const idleTimer = try std.time.Timer.start();
        const lastFocusObj = Result{ .id = 0, .box = undefined, .centre = initialCenterPoint, .prevCentre = initialCenterPoint, .score = 0, .classId = 0 };
        return Self{
            .maxLife = 30, // number of frames to allow tracking to wait before resetting focus
            .allocator = allocator,
            .objects = objs,
            .disappeared = disapp,
            .focusId = 0,
            .lastFocusObj = lastFocusObj,
            .fpsTimer = fpsTimer,
            .overlay = overlay,
            .frames = 0,
            .fps = 0,
            .tracking = false,
            .trackingDisappeared = 0,
            .trackingIdleTimer = idleTimer,
            .trackingPrevCentroid = initialCenterPoint,
        };
    }

    fn increaseDisapperance(self: *Self) void {
        self.trackingDisappeared += 1;
    }

    // NOT USED
    fn sortAsc(context: void, a: f32, b: f32) bool {
        return std.sort.asc(f32)(context, a, b);
    }

    fn register(self: *Self, res: Result) !void {
        std.debug.print("Registering NEW Object. {any}\n", .{res});
        try self.objects.append(res);
        self.focusId = res.id;
        //try self.disappeared.append(1); // not in use
    }

    // remove stale and disappeared objects
    fn unregister(self: *Self, id: usize) !void {
        const idx: usize = id - 1; // index in arraylist
        std.debug.print("TRACKER LOST: unregistering stale or disappeared object: {d}\n", .{idx});
        _ = self.objects.swapRemove(idx);
        //_ = self.disappeared.orderedRemove(idx); not in use
    }

    fn startFpsTimer(self: *Self) void {
        std.debug.print("Starting game timer\n", .{});
        self.fpsTimer.reset();
    }

    fn getFpsTimeSpent(self: *Self) u64 {
        return self.fpsTimer.lap();
    }

    // just resets timer for idle tracker
    fn startIdleTimer(self: *Self) void {
        std.debug.print("Starting idle tracker timer\n", .{});
        self.trackingIdleTimer.reset();
    }

    fn getIdleTimeSpent(self: *Self) u64 {
        return self.trackingIdleTimer.read();
    }

    fn getFocusObj(self: Self) ?Result {
        for (self.objects.items) |obj| {
            if (obj.id == self.focusId) {
                return obj;
            }
        }
        // failover object if lost focus
        if (self.lastFocusObj) |obj| {
            // dont send last known object forever
            if (obj.disappeared < self.maxLife) {
                //std.debug.print("getFocusObj : LOST OBJECT, TRYING LAST KNOWN FOCUS ID {d}!\n", .{obj.id});
                return obj;
            }
        }
        return null;
    }

    fn clearOverlay(self: *Self) void {
        return self.overlay.setTo(cv.Scalar.init(0, 0, 0, 0));
    }

    // first 6 bytes is cmd (1) , gamemode (1) and buffer length (4)
    fn sendImage(self: Self, img: *cv.Mat) !void {
        var bs = cv.imEncode(cv.FileExt.png, img.*, self.allocator) catch |err| {
            std.debug.print("Error encoding image: {any}\n", .{err});
            return err;
        };
        defer bs.deinit();
        const cmd: u8 = @intFromEnum(gameMode);
        const len: i32 = @intCast(bs.items.len);
        std.debug.print("Image length: {d}\n", .{len});
        _ = try bs.insert(0, cmd);
        _ = try bs.insertSlice(1, std.mem.asBytes(&gameMode));
        _ = try bs.insertSlice(2, std.mem.asBytes(&len));
        wsClient.writeBin(bs.items) catch |err| {
            std.debug.print("Error sending image: {any}\n", .{err});
            return err;
        };
    }

    // centroid is x,y i32
    fn sendCentroid(_: Self, p: cv.core.Point) !void {
        //std.debug.print("centroid: {any}\n", .{p});
        var buf = [_]u8{0} ** 14;
        const len: i32 = @intCast(8);
        var wr = std.io.fixedBufferStream(&buf);
        _ = try wr.write(&[_]u8{0x02}); // cmd 2    = send centroid
        _ = try wr.write(std.mem.asBytes(&gameMode));
        _ = try wr.write(std.mem.asBytes(&len)); // length
        _ = try wr.write(std.mem.asBytes(&p.x));
        _ = try wr.write(std.mem.asBytes(&p.y));
        //_ = try client.write(&buf);
        _ = try wsClient.writeBin(&buf);
    }

    // sending directly to animatronic eyes
    // we need to map input vector x,y (640, 480) to u8 bytes (255, 255)
    // send as 5 u8 bytes { 0, 2, x, y, CRLF }, not expecting any response
    fn sendCentroidToEyes(_: Self, p: cv.core.Point) !void {
        if (btConnected == false) {
            return;
        }
        const t = std.time.milliTimestamp();
        if (@mod(t, 2) != 0) {
            return; // only send 1/5 of signals not to choke BTLE peripheral
        }
        // x, y is only two u8 bytes + 0, 2
        const x1: f32 = @floatFromInt(p.x);
        const y1: f32 = @floatFromInt(p.y);
        const x2: f32 = std.math.round(x1 / 640.0 * 255.0); // map 0-640 to 0-255
        const y2: f32 = std.math.round(@abs(640.0 - y1) / 640.0 * 255.0); // map to 0-255 and invert
        std.debug.print("Sending x, y: ({d}, {d}) mapped: ({d:.0}, {d:.0}) to eyes\n", .{ p.x, p.y, x2, y2 });
        const xByte: u8 = @truncate(@as(u32, @bitCast(@as(i32, @intFromFloat(x2)))));
        const yByte: u8 = @truncate(@as(u32, @bitCast(@as(i32, @intFromFloat(y2)))));
        var cmd: [5]u8 = .{ 0, 2, xByte, yByte, 13 };
        //std.debug.print("Sending x, y: ({d}, {d}) to eyes: {any} \n", .{x2, y2, cmd});
        const cmd_c: [*c]const u8 = @ptrCast(&cmd);
        const err_code = ble.simpleble_peripheral_write_request(btPeripheral, btService.uuid, btService.characteristics[btCharId].uuid, cmd_c, 5);
        if (err_code != @as(c_uint, @bitCast(ble.SIMPLEBLE_SUCCESS))) {
            std.debug.print("Failed to send data to eyes.\n", .{});
        }
    }

    // send stats to websocket
    fn sendStats(_: Self, r: Result) !void {
        var buf = [_]u8{0} ** 40;
        const len: i32 = @intCast(8);
        var wr = std.io.fixedBufferStream(&buf);
        _ = try wr.write(&[_]u8{0x09}); // cmd 9    = send stats
        _ = try wr.write(std.mem.asBytes(&gameMode));
        _ = try wr.write(std.mem.asBytes(&len)); // length
        _ = try wr.write(std.mem.asBytes(&r.box)); // bounding box 4 x i32
        _ = try wr.write(std.mem.asBytes(&r.centre)); // x,y 2 x i32
        _ = try wr.write(std.mem.asBytes(&r.score)); // score f32
        //_ = try client.write(&buf);
        _ = try wsClient.writeBin(&buf);
    }

    // Add result objects to tracker
    fn add(self: *Self, results: ArrayList(Result)) !void {
        for (results.items) |res| {
            try self.register(res);
        }
    }

    // Clear all result objects from tracker, in reverse since it mutates arraylist length
    fn clearObjects(self: *Self) !void {
        var i: usize = self.objects.items.len;
        while (i > 0) : (i -= 1) {
            std.debug.print("Obj length: {d}.\n", .{self.objects.items.len});
            try self.unregister(i);
        }
        // for (self.objects.items, 0..) |_, objIdx| {
        //    try self.unregister(objIdx);
        // }
    }
};

// performDetection analyzes the results from the detector network,
// which produces an output blob with a shape 1x1xNx7
// where N is the number of detections, and each detection
// is a vector of float values
// yolov8 has an output of shape (batchSize, 84,  8400) (Num classes + box[x,y,w,h])
// float x_factor = modelInput.cols / modelShape.width;
// float y_factor = modelInput.rows / modelShape.height;
//cols = bbox (xywh) + classcores (numclass*1)
fn performDetection(img: *Mat, scoreMat: Mat, rows: usize, _: Size, tracker: *Tracker, allocator: Allocator) !void {
    //try cv.imWrite("object.jpg", img.*);
    //std.debug.print("scoreMat size: {any}\n", .{scoreMat.size()});
    var i: usize = 0;

    //std.debug.print("shape input {any}\n", .{cols});
    // factor is model input / model shape
    // float x_factor = modelInput.cols / modelShape.width;
    // image dims is { cols, rows }
    const imgWidth: f32 = @floatFromInt(img.cols());
    const imgHeight: f32 = @floatFromInt(img.rows());

    var bboxes = ArrayList(cv.Rect).init(allocator);
    var centrs = ArrayList(cv.Point).init(allocator);
    var scores = ArrayList(f32).init(allocator);
    var classes = ArrayList(i32).init(allocator);
    defer bboxes.deinit();
    defer centrs.deinit();
    defer scores.deinit();
    defer classes.deinit();

    // // YOLO-FASTEST DARKNET
    // // Mat is {1200, 85 } (x,y,w,h, cl, scores*80)
    // // Bounding box : [x_center, y_center, width, height]
    while (i < rows) : (i += 1) {
        // scores is a vector of results[0..4] (centr_x,centr_y,w,h) followed by clsid + 80 scores (for each class)
        var classScores = try scoreMat.region(cv.Rect.init(5, @intCast(i), CLASSES.len, 1));
        defer classScores.deinit();
        // minMaxLoc extracts max and min scores from entire result vector
        const sc = cv.Mat.minMaxLoc(classScores);
        if (sc.max_val > 0.30) {
            // std.debug.print("minMaxLoc: {any}\n", .{sc});
            const fx: f32 = scoreMat.get(f32, i, 0);
            const fy: f32 = scoreMat.get(f32, i, 1);
            const fw: f32 = scoreMat.get(f32, i, 2);
            const fh: f32 = scoreMat.get(f32, i, 3);
            //std.debug.print("imgW {d} imgH {d} fx {d}, fy {d}, fw {d}, fh {d}\n", .{imgWidth, imgHeight, fx, fy, fw, fh});
            const left: i32 = @intFromFloat((fx - (fw / 2)) * imgWidth);
            const top: i32 = @intFromFloat((fy - (fh / 2)) * imgHeight);
            const width: i32 = @intFromFloat(fw * imgWidth);
            const height: i32 = @intFromFloat(fh * imgHeight);
            const rect = cv.Rect{ .x = left, .y = top, .width = width, .height = height };
            const cx: i32 = @intFromFloat(fx * imgWidth);
            const cy: i32 = @intFromFloat(fy * imgHeight);
            const centr: cv.Point = cv.Point.init(cx, cy);
            //std.debug.print("rect: {any}\n", .{rect});
            //std.debug.print("centr: {any}\n", .{centr});
            try centrs.append(centr);
            try bboxes.append(rect);
            try scores.append(@floatCast(sc.max_val));
            try classes.append(sc.max_loc.x);
        }
    }

    // YOLO-FASTEST-V2
    // Mat is {605, 95} (x,y,w,h, cl, scores*80)
    // Bounding box : [x_center, y_center, width, height]
    // const xFact: f32 = 352.0 / imgWidth;
    // const yFact: f32 = 352.0 / imgHeight;
    // while (i < rows) : (i += 1) {
    //     // scores is a vector of results[0..4] (centr_x,centr_y,w,h) followed by clsid + 80 scores (for each class)
    //     var classScores = try scoreMat.region(cv.Rect.init(5, @intCast(i), CLASSES.len, 1));
    //     defer classScores.deinit();
    //     // minMaxLoc extracts max and min scores from entire result vector
    //     const sc = cv.Mat.minMaxLoc(classScores);
    //     if (sc.max_val > 0.30) {
    //         // std.debug.print("minMaxLoc: {any}\n", .{sc});
    //         var fx: f32 = scoreMat.get(f32, i, 0);
    //         var fy: f32 = scoreMat.get(f32, i, 1);
    //         var fw: f32 = scoreMat.get(f32, i, 2);
    //         var fh: f32 = scoreMat.get(f32, i, 3);

    //         //std.debug.print("imgW {d} imgH {d} fx {d}, fy {d}, fw {d}, fh {d}\n", .{imgWidth, imgHeight, fx, fy, fw, fh});
    //         var left: i32 = @intFromFloat((fx - 0.5 * fw) * imgWidth * xFact);
    //         var top: i32 = @intFromFloat((fy - 0.5 * fh) * imgHeight * yFact);
    //         var width: i32 = @intFromFloat(fw * imgWidth * xFact);
    //         var height: i32 = @intFromFloat(fh * imgWidth * yFact);
    //         const rect = cv.Rect{ .x = left, .y = top, .width = width, .height = height };
    //         const cx: i32 = @intFromFloat(fx * imgWidth * xFact);
    //         const cy: i32 = @intFromFloat(fy * imgWidth * yFact);
    //         const centr: cv.Point = cv.Point.init(cx, cy);
    //         //std.debug.print("rect: {any}\n", .{rect});
    //         //std.debug.print("centr: {any}\n", .{centr});
    //         try centrs.append(centr);
    //         try bboxes.append(rect);
    //         try scores.append(@floatCast(sc.max_val));
    //         try classes.append(sc.max_loc.x);
    //     }
    // }

    // YOLO-v8
    // Mat is {8400, 85} (x,y,w,h, scores*80)
    // Bounding box : [x_center, y_center, width, height]
    // const xFact: f32 = 640.0 / imgWidth;
    // const yFact: f32 = 640.0 / imgHeight;
    // while (i < rows) : (i += 1) {
    //     // scores is a vector of results[0..4] (centr_x,centr_y,w,h) followed by clsid + 80 scores (for each class)
    //     var classScores = try scoreMat.region(cv.Rect.init(4, @intCast(i), CLASSES.len, 1));
    //     defer classScores.deinit();
    //     // minMaxLoc extracts max and min scores from entire result vector
    //     const sc = cv.Mat.minMaxLoc(classScores);
    //     if (sc.max_val > 0.30) {
    //         // std.debug.print("minMaxLoc: {any}\n", .{sc});
    //         var fx: f32 = scoreMat.get(f32, i, 0);
    //         var fy: f32 = scoreMat.get(f32, i, 1);
    //         var fw: f32 = scoreMat.get(f32, i, 2);
    //         var fh: f32 = scoreMat.get(f32, i, 3);

    //         //std.debug.print("imgW {d} imgH {d} fx {d}, fy {d}, fw {d}, fh {d}\n", .{imgWidth, imgHeight, fx, fy, fw, fh});
    //         var left: i32 = @intFromFloat((fx - 0.5 * fw) * imgWidth * xFact);
    //         var top: i32 = @intFromFloat((fy - 0.5 * fh) * imgHeight * yFact);
    //         var width: i32 = @intFromFloat(fw * imgWidth * xFact);
    //         var height: i32 = @intFromFloat(fh * imgWidth * yFact);
    //         const rect = cv.Rect{ .x = left, .y = top, .width = width, .height = height };
    //         const cx: i32 = @intFromFloat(fx * imgWidth * xFact);
    //         const cy: i32 = @intFromFloat(fy * imgWidth * yFact);
    //         const centr: cv.Point = cv.Point.init(cx, cy);
    //         //std.debug.print("rect: {any}\n", .{rect});
    //         //std.debug.print("centr: {any}\n", .{centr});
    //         try centrs.append(centr);
    //         try bboxes.append(rect);
    //         try scores.append(@floatCast(sc.max_val));
    //         try classes.append(sc.max_loc.x);
    //     }
    // }

    // YOLOv5-lite
    // Mat is {6300, 85} (x,y,w,h, conf, scores*80)
    // Bounding box : [x_center, y_center, width, height]
    // const xFact: f32 = 640.0 / imgWidth;
    // const yFact: f32 = 640.0 / imgHeight;
    // while (i < rows) : (i += 1) {
    //     // scores is a vector of results[0..4] (centr_x,centr_y,w,h) followed by clsid + 80 scores (for each class)
    //     var classScores = try scoreMat.region(cv.Rect.init(5, @intCast(i), CLASSES.len, 1));
    //     defer classScores.deinit();
    //     // minMaxLoc extracts max and min scores from entire result vector
    //     const sc = cv.Mat.minMaxLoc(classScores);
    //     if (sc.max_val > 0.50) {
    //         // std.debug.print("minMaxLoc: {any}\n", .{sc});
    //         var fx: f32 = scoreMat.get(f32, i, 0);
    //         var fy: f32 = scoreMat.get(f32, i, 1);
    //         var fw: f32 = scoreMat.get(f32, i, 2);
    //         var fh: f32 = scoreMat.get(f32, i, 3);

    //         //std.debug.print("imgW {d} imgH {d} fx {d}, fy {d}, fw {d}, fh {d}\n", .{imgWidth, imgHeight, fx, fy, fw, fh});
    //         var left: i32 = @intFromFloat((fx - 0.5 * fw) * imgWidth * xFact);
    //         var top: i32 = @intFromFloat((fy - 0.5 * fh) * imgHeight * yFact);
    //         var width: i32 = @intFromFloat(fw * imgWidth * xFact);
    //         var height: i32 = @intFromFloat(fh * imgWidth * yFact);
    //         const rect = cv.Rect{ .x = left, .y = top, .width = width, .height = height };
    //         const cx: i32 = @intFromFloat(fx * imgWidth * xFact);
    //         const cy: i32 = @intFromFloat(fy * imgWidth * yFact);
    //         const centr: cv.Point = cv.Point.init(cx, cy);
    //         //std.debug.print("rect: {any}\n", .{rect});
    //         //std.debug.print("centr: {any}\n", .{centr});
    //         try centrs.append(centr);
    //         try bboxes.append(rect);
    //         try scores.append(@floatCast(sc.max_val));
    //         try classes.append(sc.max_loc.x);
    //     }
    // }

    // 2) Non Maximum Suppression : remove overlapping boxes (= max confidence and least overlap)
    // return arraylist of indices of non overlapping boxes
    const indices = try cv.dnn.nmsBoxes(bboxes.items, scores.items, 0.25, 0.45, 1, allocator);
    defer indices.deinit();

    // 3) reduce results
    var reduced = ArrayList(Result).init(allocator);
    defer reduced.deinit();
    for (indices.items, 0..indices.items.len) |numIndex, _| {
        const idx: usize = @intCast(numIndex);
        try reduced.append(Result{
            .id = idx,
            .box = bboxes.items[idx],
            .centre = centrs.items[idx],
            .prevCentre = centrs.items[idx],
            .score = scores.items[idx],
            .classId = @intCast(classes.items[idx]),
        });
    }
    // 4) update tracker objects with cleaned results
    try tracker.add(reduced);

    // Sort objects by largest box size
    //var objects = try tracker.objects.toOwnedSlice();
    //const objects = tracker.objects.items;
    std.mem.sort(Result, tracker.objects.items, {}, sortResultObjectsDesc);
    //tracker.objects = objects;

    // Add bounding boxes, centroids, arrows and labels to image
    for (tracker.objects.items) |obj| {
        switch (obj.classId) {
            0 => { // person
                _ = trackerVit.initialize(img, obj.box);
                std.debug.print("found and initialized tracker {any}\n", .{obj.box});
                tracker.tracking = true;
                tracker.focusId = obj.id;
                tracker.lastFocusObj = obj;
                cv.arrowedLine(img, cv.Point.init(obj.box.x + @divFloor(obj.box.width, 2), obj.box.y - 50), cv.Point.init(obj.box.x + @divFloor(obj.box.width, 2), obj.box.y - 30), green, 4);
                tracker.startIdleTimer();
                lastGameMode = gameMode;
                gameMode = GameMode.TRACK;
            },
            39, 41, 63, 64, 65, 66, 67, 76 => {}, //bottle, cup, laptop, etc, scissors
            else => {},
        }
        var buf = [_]u8{undefined} ** 40;
        const lbl = try std.fmt.bufPrint(&buf, "{s} ({d:.2}) ID: {d}", .{ CLASSES[obj.classId], obj.score, obj.id });
        cv.rectangle(img, obj.box, green, 1);
        cv.putText(img, "+", obj.centre, cv.HersheyFont{ .type = .simplex }, 0.5, green, 1);
        cv.putText(img, lbl, cv.Point.init(obj.box.x - 10, obj.box.y - 10), cv.HersheyFont{ .type = .simplex }, 0.5, green, 1);

        cv.drawMarker(&tracker.overlay, obj.centre, red, .cross, 4, 2, .filled);
    }

    // add overlay traces to output img, need to convert input img to 4chan with alpha first
    cv.cvtColor(img.*, img, .bgr_to_bgra);
    //tracker.overlay.copyTo(img);
    //img.addMatWeighted(1.0, tracker.overlay, 0.4, 0.5, img);

    // Add FPS and gameMode to output
    var fpsBuf = [_]u8{undefined} ** 20;
    const fpsTxt = try std.fmt.bufPrint(&fpsBuf, "FPS ({d:.2})", .{tracker.fps});
    cv.putText(img, fpsTxt, cv.Point.init(10, 30), cv.HersheyFont{ .type = .simplex }, 0.5, green, 2);
    var modeBuf = [_]u8{undefined} ** 14;
    const modeTxt = try std.fmt.bufPrint(&modeBuf, "{s}", .{@tagName(gameMode)});
    cv.putText(img, modeTxt, cv.Point.init(10, 620), cv.HersheyFont{ .type = .simplex }, 0.5, green, 2);
}

// We need square for onnx inferencing to work
pub fn formatToSquare(src: Mat) !Mat {
    const col = src.cols();
    const row = src.rows();
    const _max = @max(col, row);
    var res = try cv.Mat.initZeros(_max, _max, cv.Mat.MatType.cv8uc4);
    src.copyTo(&res);
    return res;
}

pub fn connectBluetooth() void {
    std.debug.print("Connecting to bluetooth.\n", .{});
    if (btConnected == true) {
        return; // already connected
    }
    const adapter_count: usize = ble.simpleble_adapter_get_count();
    if (adapter_count == @as(usize, @bitCast(@as(c_long, @as(c_int, 0))))) {
        std.debug.print("No adapter was found.\n", .{});
        return;
    }
    const adapter: ble.simpleble_adapter_t = ble.simpleble_adapter_get_handle(@as(usize, @bitCast(@as(c_long, @as(c_int, 0)))));
    if (adapter == @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))) {
        std.debug.print("No adapter was found.\n", .{});
        return;
    }

    _ = ble.simpleble_adapter_set_callback_on_scan_start(adapter, &ble.adapter_on_scan_start, @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))));
    _ = ble.simpleble_adapter_set_callback_on_scan_stop(adapter, &ble.adapter_on_scan_stop, @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))));
    _ = ble.simpleble_adapter_set_callback_on_scan_found(adapter, &ble.adapter_on_scan_found, @as(?*anyopaque, @ptrFromInt(@as(c_int, 0))));
    _ = ble.simpleble_adapter_scan_for(adapter, @as(c_int, 3000));

    var selection: usize = undefined;
    var found: bool = false;
    var i: usize = 0;
    while (i < ble.peripheral_list_len) : (i +%= 1) {
        const peripheral: ble.simpleble_peripheral_t = ble.peripheral_list[i];
        //var peripheral_identifier: [*c]u8 = ble.simpleble_peripheral_identifier(peripheral);
        const peripheral_address: [*c]u8 = ble.simpleble_peripheral_address(peripheral);
        const periphStr = std.mem.span(@as([*:0]u8, @ptrCast(@alignCast(peripheral_address))));
        std.debug.print("comp peripheral: {s} vs {s}\n", .{ periphStr, btPeriphStr });
        if (std.mem.eql(u8, periphStr, btPeriphStr)) {
            std.debug.print("found peripheral: {s} id: {any}\n", .{ btPeriphStr, selection });
            selection = i;
            found = true;
            break;
        }
    }
    if (!found) {
        std.debug.print("Could not find peripheral with mac: {s}\n", .{btPeriphStr});
        return;
    }

    std.debug.print("Selected: {d}\n", .{selection});
    if ((selection < @as(c_int, 0)) or (selection >= @as(c_int, @bitCast(@as(c_uint, @truncate(ble.peripheral_list_len)))))) {
        std.debug.print("Invalid bluetooth selection\n", .{});
        return;
    }
    btPeripheral = ble.peripheral_list[@as(c_uint, @intCast(selection))];
    const peripheral_identifier: [*c]u8 = ble.simpleble_peripheral_identifier(btPeripheral);
    const peripheral_address: [*c]u8 = ble.simpleble_peripheral_address(btPeripheral);
    std.debug.print("Connecting to {s} [{s}]\n", .{ peripheral_identifier, peripheral_address });
    ble.simpleble_free(@as(?*anyopaque, @ptrCast(peripheral_identifier)));
    ble.simpleble_free(@as(?*anyopaque, @ptrCast(peripheral_address)));
    var err_code = ble.simpleble_peripheral_connect(btPeripheral);
    if (err_code != @as(c_uint, @bitCast(ble.SIMPLEBLE_SUCCESS))) {
        std.debug.print("Failed to connect to bluetooth peripheral\n", .{});
        ble.clean_on_exit(adapter);
        return;
    }

    // Service
    const services_count: usize = ble.simpleble_peripheral_services_count(btPeripheral);
    var s: usize = 0;
    while (s < services_count) : (s +%= 1) {
        var service: ble.simpleble_service_t = undefined;
        err_code = ble.simpleble_peripheral_services_get(btPeripheral, s, &service);
        if (err_code != @as(c_uint, @bitCast(ble.SIMPLEBLE_SUCCESS))) {
            std.debug.print("Invalid bluetooth service selection\n", .{});
            ble.clean_on_exit(adapter);
            return;
        }

        // Select HMSoft Serial service
        var serviceStr: []const u8 = @ptrCast(@alignCast(&service.uuid.value));
        std.debug.print("comp service uuid: {s} vs {s}\n", .{ serviceStr, btServiceUuidStr });
        if (std.mem.eql(u8, serviceStr[0..36], btServiceUuidStr[0..36])) {
            std.debug.print("found right UART service: {s}\n", .{btServiceUuidStr});
            btService = service;
            btConnected = true;
            break;
        }
    }
    return;
}

pub fn disconnectBluetooth() void {
    const errUnpair = ble.simpleble_peripheral_unpair(btPeripheral);
    if (errUnpair != @as(c_uint, @bitCast(ble.SIMPLEBLE_SUCCESS))) {
        std.debug.print("Failed to disconnect to bluetooth peripheral\n", .{});
    }
    const errDisconect = ble.simpleble_peripheral_disconnect(btPeripheral);
    if (errDisconect != @as(c_uint, @bitCast(ble.SIMPLEBLE_SUCCESS))) {
        std.debug.print("Failed to disconnect to bluetooth peripheral\n", .{});
    }
    std.debug.print("Disconnected bluetooth peripheral: {any}\n", .{btPeripheral});
    btPeripheral = undefined;
    btConnected = false;
    return;
}

// calculate Euclidean distance between two points
fn euclidDist(prev: cv.Point, new: cv.Point) f32 {
    const xDiff: f32 = @floatFromInt(prev.x - new.x);
    const yDiff: f32 = @floatFromInt(prev.y - new.y);
    const diff: f32 = std.math.sqrt((xDiff * xDiff) + (yDiff * yDiff));
    return diff;
}

// Sort Result objects by largest area
fn sortResultObjectsDesc(_: void, a: Result, b: Result) bool {
    const aArea = a.box.width * a.box.height;
    const bArea = b.box.width * b.box.height;
    return bArea > aArea;
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = try std.process.argsWithAllocator(allocator);

    const prog = args.next();
    const startModeChar = args.next() orelse {
        std.log.err("usage: {s} [startMode] [cameraID] [model]", .{prog.?});
        std.process.exit(1);
    };
    const deviceIdChar = args.next() orelse {
        std.log.err("usage: {s} [startMode] [cameraID] [model]", .{prog.?});
        std.process.exit(1);
    };
    const model = args.next() orelse {
        std.log.err("usage: {s} [startMode] [cameraID] [model]", .{prog.?});
        std.process.exit(1);
    };
    std.debug.print("input model: {s} \n", .{model});
    args.deinit();

    const startMode = try std.fmt.parseUnsigned(i32, startModeChar, 10);
    _ = try std.fmt.parseUnsigned(i32, deviceIdChar, 10);
    const mode: GameMode = @enumFromInt(startMode);
    gameMode = mode;

    const deviceId = try std.fmt.parseUnsigned(i32, deviceIdChar, 10);
    _ = try std.fmt.parseUnsigned(i32, deviceIdChar, 10);

    // open webcam
    var webcam = try cv.VideoCapture.init();
    try webcam.openDevice(deviceId);
    defer webcam.deinit();

    // open display window
    const winName = "Robot eyes";
    var window = try cv.Window.init(winName);
    defer window.deinit();

    // Init bluetooth and find HMSoft adapter
    connectBluetooth();
    defer disconnectBluetooth();

    // prepare image matrix
    var img = try cv.Mat.init();
    defer img.deinit();
    //img = try cv.imRead("object.jpg", .unchanged);

    // YOLO-FASTEST 1.1 DARKNET - OK
    const swapRB = false;
    const scale: f64 = 1.0 / 255.5;
    const size: cv.Size = cv.Size.init(320, 320);
    const mean = cv.Scalar.init(0, 0, 0, 0); // mean subtraction is a technique used to aid our Convolutional Neural Networks.
    const crop = false;
    var net = cv.Net.readNetFromDarknet("models/yolo-fastest-1.1-xl.cfg", model) catch |err| {
        //var net = cv.Net.readNetFromDarknet("models/yolo-fastest-1.1.cfg", model) catch |err| {
        std.debug.print("Error: {any}\n", .{err});
        std.process.exit(1);
    };

    // YOLO FASTEST V2
    // https://github.com/hpc203/yolo-fastestv2-opencv/blob/main/main.cpp
    // const swapRB = false;
    // const scale: f64 = 1.0 / 255.5;
    // const size: cv.Size = cv.Size.init(352, 352);
    // const mean = cv.Scalar.init(0, 0, 0, 0); // mean subtraction is a technique used to aid our Convolutional Neural Networks.
    // const crop = false;
    // var net = cv.Net.readNetFromONNX(model) catch |err| {
    //     std.debug.print("Error: {any}\n", .{err});
    //     std.process.exit(1);
    // };

    // YOLOv5n
    // https://github.com/doleron/yolov5-opencv-cpp-python/blob/main/cpp/yolo.cpp
    // const swapRB = true;
    // const scale: f64 = 1.0 / 255.5;
    // const size: cv.Size = cv.Size.init(640, 640);
    // const mean = cv.Scalar.init(0, 0, 0, 0); // mean subtraction is a technique used to aid our Convolutional Neural Networks.
    // const crop = false;
    // var net = cv.Net.readNetFromONNX(model) catch |err| {
    //     std.debug.print("Error: {any}\n", .{err});
    //     std.process.exit(1);
    // };

    // YOLOv5-lite
    // https://github.com/ppogg/YOLOv5-Lite/blob/master/test.py
    // const swapRB = true;
    // const scale: f64 = 1.0 / 255.5;
    // const size: cv.Size = cv.Size.init(320, 320);
    // const mean = cv.Scalar.init(0, 0, 0, 0); // mean subtraction is a technique used to aid our Convolutional Neural Networks.
    // const crop = false;
    // var net = cv.Net.readNetFromONNX(model) catch |err| {
    //     std.debug.print("Error: {any}\n", .{err});
    //     std.process.exit(1);
    // };

    // TrackerVit fast dnn tracker
    trackerVit = try cv.TrackerVit.init("models/object_tracking_vittrack_2023sep.onnx");
    defer trackerVit.deinit();
    std.debug.print("vitModel: {any}\n", .{trackerVit});

    defer net.deinit();

    if (net.isEmpty()) {
        std.debug.print("Error: could not load model\n", .{});
        std.process.exit(1);
    }

    net.setPreferableBackend(.default); // .default, .halide, .open_vino, .open_cv. .vkcom, .cuda
    net.setPreferableTarget(.fp16); // .cpu, .fp32, .fp16, .vpu, .vulkan, .fpga, .cuda, .cuda_fp16
    //var layers = try net.getLayerNames(allocator);
    //std.debug.print("getLayerNames {s}\n", .{layers});
    //const unconnected = try net.getUnconnectedOutLayers(allocator);
    //std.debug.print("getUnconnectedOutLayers {any}\n", .{unconnected.items});
    //const unconnected = try net.getUnconnectedOutLayersNames(allocator);
    //std.debug.print("getUnconnectedOutLayersNames {s}\n", .{unconnected});

    // for (unconnected.items) |li| {
    //     const l = try net.getLayer(li);
    //     std.debug.print("unconnected layer output {d}: {s}\n", .{li, l.getName()});
    // }

    var certBundle: std.crypto.Certificate.Bundle = .{};
    defer certBundle.deinit(allocator);
    var certFile = try std.fs.cwd().openFile("cert.pem", .{});
    defer certFile.close();

    _ = try std.crypto.Certificate.Bundle.addCertsFromFile(&certBundle, allocator, certFile);
    wsClient = try websocket.Client.init(allocator, .{ .host = "localhost", .port = 8665, .tls = true, .ca_bundle = certBundle });
    defer wsClient.deinit();

    // Game mode manager in separate thread
    try wsClient.handshake("/ws?channels=robot-eyes", .{
        .timeout_ms = 5000,
        .headers = "host: localhost:8665\r\n",
    });
    const msgHandler = MsgHandler{ .allocator = allocator };
    const thread = try wsClient.readLoopInNewThread(msgHandler);
    thread.detach();

    // initial tracker to find objects to track
    var tracker = try Tracker.init(allocator);
    //defer tracker.deinit();

    while (true) {
        webcam.read(&img) catch {
            std.debug.print("capture failed", .{});
            std.process.exit(1);
        };
        if (img.isEmpty()) {
            continue;
        }
        // Frames (FPS) per second timing
        tracker.frames += 1;
        if (tracker.frames >= 60) {
            const lap: u64 = tracker.getFpsTimeSpent();
            const flap: f64 = @floatFromInt(lap);
            const secs: f64 = flap / 1000000000;
            tracker.fps = tracker.frames / secs;
            tracker.frames = 0;
        }

        img.flip(&img, 1); // flip horizontally
        // var squaredImg = try formatToSquare(img);
        // defer squaredImg.deinit();
        // cv.resize(squaredImg, &squaredImg, size, 0, 0, .{});

        if (tracker.tracking == false) {
            // We need to see if we find something to track, say, a person
            // TODO: We should focus on the largest object if there are multiple (persons)
            // it is usually the closest that want attention...
            // transform image to CV matrix / 4D blob
            // batch_size, channels, height, width
            var blob = try cv.Blob.initFromImage(img, scale, size, mean, swapRB, crop);
            defer blob.deinit();
            std.debug.print("orig blob batch size {any},\n", .{blob.mat.size()});

            // INFERENCE YOLO-FASTEST DARKNET OK
            // run inference on Matrix
            // No need to reshape since output is single.channel and no batch size
            // prob result: objid, classid, confidence, left, top, right, bottom.
            // input: {1, 3, 320, 320} (b,ch,w,h)
            // output {1200, 85} scores and boxes
            net.setInput(blob, "");
            var probs = try net.forward("");
            defer probs.deinit();
            std.debug.print("output probs size {any},\n", .{probs.size()});
            const rows: usize = @intCast(probs.size()[0]);
            try performDetection(&img, probs, rows, size, &tracker, allocator);

            // INFERENCE YOLOv8-n sparse
            // run inference on Matrix
            // yolov8 has an output of shape (batchSize, 84,  8400) (Num classes + box[x,y,w,h])
            // prob result: objid, classid, confidence, left, top, right, bottom.
            // input: {1, 3, 640, 640} (b,ch,w,h)
            // output {1, 84,  8400} scores and boxes
            // net.setInput(blob, "");
            // var probs = try net.forward("");
            // defer probs.deinit();
            // const rows: usize = @intCast(probs.size()[2]);
            // var probMat = try probs.reshape(1, rows);
            // defer probMat.deinit();
            // std.debug.print("output probMat size {any},\n", .{probMat.size()});
            // try performDetection(&img, probMat, rows, size, &tracker, allocator);

            // INFERENCE YOLOv5-lite-e
            // run inference on Matrix
            // prob result: objid, classid, confidence, left, top, right, bottom.
            // input: {1, 3, 320, 320} (b,ch,w,h)
            // output {1, 6300,  85} scores and boxes
            // net.setInput(blob, "");
            // var probs = try net.forward("");
            // defer probs.deinit();
            // const rows: usize = @intCast(probs.size()[1]);
            // var probMat = try probs.reshape(1, rows);
            // defer probMat.deinit();
            // std.debug.print("output probMat size {any},\n", .{probMat.size()});
            // try performDetection(&img, probMat, rows, size, &tracker, allocator);

        } else {
            // we are tracking...
            // we keep an idleTimer for avoiding tracking frozen objects
            const updateRes = trackerVit.update(&img);
            if (updateRes.success == true) {
                const newScore = trackerVit.getTrackingScore();
                if (newScore > 0.4) {
                    tracker.trackingDisappeared = 0;

                    // Centre crosshair
                    const cx: i32 = updateRes.box.x + @divFloor(updateRes.box.width, 2);
                    const cy: i32 = updateRes.box.y + @divFloor(updateRes.box.height, 2);
                    const centroid = cv.Point.init(cx, cy);
                    cv.putText(&img, "+", centroid, cv.HersheyFont{ .type = .simplex }, 0.5, green, 1);

                    // check if centroid distance is low (can be a stale object)
                    const dist: f32 = euclidDist(tracker.trackingPrevCentroid, centroid);
                    if (dist < 10.0) { // less than 10 points distance = idle
                        // Seems we have a stale object
                        lastGameMode = gameMode;
                        gameMode = GameMode.TRACK_IDLE;
                        const idleTime = tracker.getIdleTimeSpent();
                        if (idleTime > 5 * 1000 * 1000 * 1000) { // 5 secs idle
                            tracker.tracking = false;
                            try tracker.clearObjects();
                            std.debug.print("TIMEOUT FOR STALE TRACKER: time: {d}\n", .{idleTime});
                        }
                    } else {
                        tracker.startIdleTimer(); // just reset idle timer
                        lastGameMode = gameMode;
                        gameMode = GameMode.TRACK;
                    }

                    tracker.trackingPrevCentroid = centroid;

                    // send centroid
                    try tracker.sendCentroid(centroid);

                    var buf = [_]u8{undefined} ** 20; // common buf for outputting cv labels to img
                    const fpsTxt = try std.fmt.bufPrint(&buf, "FPS ({d:.2})", .{tracker.fps});
                    cv.putText(&img, fpsTxt, cv.Point.init(10, 30), cv.HersheyFont{ .type = .simplex }, 0.5, green, 2);
                    @memset(&buf, 0);
                    const modeTxt = try std.fmt.bufPrint(&buf, "{s}", .{@tagName(gameMode)});
                    cv.putText(&img, modeTxt, cv.Point.init(10, 60), cv.HersheyFont{ .type = .simplex }, 0.5, green, 2);
                    @memset(&buf, 0);
                    const lbl = try std.fmt.bufPrint(&buf, "{s} ({d:.2})", .{ "person", newScore });
                    cv.rectangle(&img, updateRes.box, green, 1);
                    cv.putText(&img, lbl, cv.Point.init(updateRes.box.x - 10, updateRes.box.y - 10), cv.HersheyFont{ .type = .simplex }, 0.5, green, 1);

                    // Now see if we have a focus object and pending modes
                    switch (gameMode) {
                        .TRACK, .TRACK_IDLE, .STOP => {
                            try tracker.sendCentroid(centroid);
                            try tracker.sendCentroidToEyes(centroid);
                        },
                        .SNAP => {
                            std.debug.print("SENDING IMAGE\n", .{});
                            //img.addMatWeighted(1.0, tracker.overlay, 0.4, 0.5, img);
                            try tracker.sendImage(&img);
                            gameMode = lastGameMode;
                        },
                        else => {
                            std.debug.print("Centroid: {any}\n", .{centroid});
                        },
                    }
                } else {
                    std.debug.print("LOSING IT...\n", .{});
                    tracker.trackingDisappeared += 1;
                    if (tracker.trackingDisappeared > tracker.maxLife) {
                        std.debug.print("LOST IT FOR GOOD!\n", .{});
                        tracker.tracking = false;
                        try tracker.clearObjects();
                        lastGameMode = gameMode;
                        gameMode = GameMode.TRACK_IDLE;
                    }
                }
            } else {
                std.debug.print("LOST IT TOTALLY\n", .{});
                tracker.tracking = false;
                try tracker.clearObjects();
                lastGameMode = gameMode;
                gameMode = GameMode.TRACK_IDLE;
            }
        }

        window.imShow(img);
        if (window.waitKey(1) == 27) {
            break;
        }
    }
}
