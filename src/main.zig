const std = @import("std");
const cv = @import("zigcv");
const websocket = @import("websocket");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Mat = cv.Mat;
const Size = cv.Size;

// *** GLOBALS ***
pub const io_mode = .evented;
var CLASSES = [_][]const u8{"person","bicycle","car","motorcycle","airplane","bus","train","truck","boat","traffic light", "fire hydrant", "stop sign", "parking meter",
  "bench", "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard",
  "sports ball", "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
  "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote",
  "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"};

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

var wsClient: websocket.Client = undefined;     // Websocket client
//var client: std.net.Stream = undefined;       // TCP client for sending tracking / predictions / messages
//var httpClient: std.http.Client = undefined;  // HTTP client for sending images
//var server: std.net.StreamServer = undefined; // listening TCP socket for receiving commands from client

const MsgHandler = struct {
    allocator: Allocator,

    // Handle Commands via websocket
    pub fn handle(self: MsgHandler, msg: websocket.Message) !void {
        std.log.debug("got msg: {any}", .{msg.data});
        if (msg.data[0] == 1) {
            const mode: GameMode = @enumFromInt(msg.data[1]);
            lastGameMode = gameMode;
            gameMode = mode;
            var mb: u8 = std.mem.asBytes(&gameMode)[0];
            std.log.debug("switched mode from: {any} to {any}", .{lastGameMode, gameMode});
            const res = try self.allocator.alloc(u8, 8);
            @memcpy(res, &[_]u8{0, mb, 2, 0, 0, 0, 0x4f, 0x4b}); // OK
            _ = try wsClient.writeBin(res);
        } else {
            const res = try self.allocator.alloc(u8, 9);
            var mb: u8 = std.mem.asBytes(&gameMode)[0];
            @memcpy(res, &[_]u8{0, mb, 2, 0, 0, 0, 0x4e, 0x4f, 0x4b}); // NOK
            _ = try wsClient.write(res);
        }
    }
    pub fn close(_: MsgHandler) void {
    }
};

// Result is a rect object containing scores and a class
const Result = struct {
    id: usize,  // the result score id
    box: cv.Rect,
    centre: cv.Point,
    prevCentre: cv.Point,
    score: f32,
    classId: usize,
    disappeared: i32 = 0,

    fn increaseDisapperance(self: *Result) void {
        self.disappeared += 1;
    }
};

// This is the main tracking function for the game
pub const Error = error{MissingFocus};
const GameTracker = struct {
    const Self = @This();
    allocator: Allocator,
    maxLife: i32,                 // num of frames to keep disappeared objects before removing them
    objects: ArrayList(Result),   // box, centroid (x, y), scores etc.
    disappeared: ArrayList(i32),  // counter(s) for measuring disappearance
    focusId: usize,               // The ID of Result struct containing ball - our main focus
    lastFocusObj: ?Result,         // The Result struct of LAST KNOWN GOOD focus - failover even if lost/disappeared
    timer: std.time.Timer,        // FPS timer
    overlay: Mat,                 // empty mat to draw movements on
    frames: f64,
    fps: f64,

    pub fn init(allocator: Allocator) !Self {
        var objs: ArrayList(Result) = ArrayList(Result).init(allocator);
        var disapp: ArrayList(i32) = ArrayList(i32).init(allocator);
        var overlay = try cv.Mat.initOnes( 640, 640, cv.Mat.MatType.cv8uc4); // CV_8UC4 for transparency
        var timer = try std.time.Timer.start();
        var lastFocusObj = Result{ .id = 0, .box = undefined, .centre = cv.Point{.x=320,.y=320}, .prevCentre = cv.Point{.x=320,.y=320}, .score=0, .classId=0};
        return Self{
            .maxLife = 10, // we keep a tracker alive for 10 frames, if not it is considered lost
            .allocator = allocator,
            .objects = objs,
            .disappeared = disapp,
            .focusId = 0,
            .lastFocusObj = lastFocusObj,
            .timer = timer,
            .overlay = overlay,
            .frames = 0,
            .fps = 0,
        };
    }

    // NOT USED
    fn sortAsc(context: void, a: f32, b: f32) bool {
        return std.sort.asc(f32)(context, a, b);
    }

    fn register(self: *Self, res: Result) !void {
        //std.debug.print("Registering NEW Object. {any}\n", .{res});
        try self.objects.append(res);
        self.focusId = res.id;
        //try self.disappeared.append(1);
    }

    // remove stale and disappeared objects
    fn unregister(self: *Self, id: usize) !void {
        //std.debug.print("TRACKER LOST: unregistering stale or disappeared object: {d}\n", .{id});
        _ = self.objects.orderedRemove(id);
        //_ = self.disappeared.orderedRemove(id);
    }

    fn startTimer(self: *Self) void {
        std.debug.print("Starting game timer\n", .{});
        self.timer.reset();
    }

    fn getTimeSpent(self: *Self) u64 {
        //std.debug.print("getting lap time\n", .{});
        return self.timer.lap();
    }

    fn getFocusObj(self: Self) ?Result {
        for (self.objects.items) |obj| {
            if (obj.id == self.focusId) {
                return obj;
            }
        }
        // failover object if lost focus
        if (self.lastFocusObj) | obj| {
            std.debug.print("getFocusObj : LOST OBJECT, TRYING LAST KNOWN FOCUS ID {d}!\n", .{obj.id});
            return obj;
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
        std.debug.print("centroid: {any}\n", .{p});
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

    // input: rects of discovered boxes for updating tracker and watching for
    // disappearances by an incrementing counter
    // for info read python similar solution https://pyimagesearch.com/2018/07/23/simple-object-tracking-with-opencv/
    fn update(self: *Self, results: ArrayList(Result), allocator: Allocator) !void {

        // 1) no objects found? we increase disappeared for all until maxLife reached
        if (results.items.len == 0) {
            std.debug.print("TRACKER: no input vs {d} tracked.\n", .{self.objects.items.len});
            for (self.objects.items, 0..) |*obj, idx| {
                obj.increaseDisapperance();
                if (obj.disappeared > self.maxLife) {
                    std.debug.print("TRACKER LOST ALL: unregistering item {d}\n", .{idx});
                    try self.unregister(idx);
                }
            }
            return;
        }

        // 2) objects found, but not tracking any? register each as new
        if (self.objects.items.len == 0) {
            std.debug.print("TRACKER: no existing objects. Adding {d} new\n", .{results.items.len});
            for (results.items) |res| {
                try self.register(res);
            }

        // 3) We do TRACKER MAGIC, updating tracker on existing, optionally adding new if extra input
        } else {
            // rows => tracked objects
            // cols => input objects
            var rows = try allocator.alloc(f32, self.objects.items.len);
            var cols = try allocator.alloc(f32, results.items.len);
            // keep record of assigned trackers

            var usedTrackers = try allocator.alloc(bool, self.objects.items.len);
            var usedInputs = try allocator.alloc(bool, results.items.len);
            defer allocator.free(rows);
            defer allocator.free(cols);
            defer allocator.free(usedTrackers);
            defer allocator.free(usedInputs);


            //std.log.debug("TRACKED {d} INPUT: {d}\n", .{self.objects.items.len, results.items.len});
            //std.log.debug("TRACKED OBJECTS: {any}\n", .{self.objects.items});
            //std.log.debug("INPUT   OBJECTS: {any}\n", .{results.items});

            // 1) calculate all euclidean distances between tracked objects and ALL input objects
            // allocate a matrix for computing eucledian dist between each pair of centroids
            var mat = try allocator.alloc([]f32, self.objects.items.len);
            defer allocator.free(mat);

            for (self.objects.items, 0..) |obj, objIdx| {
                const objCent = obj.centre;
                // TODO: is this memory safe?
                var diffs = try allocator.alloc(f32, results.items.len);
                for (results.items, 0..) |res, resIdx| {
                    const resCent = res.centre;
                    const xDiff: f32 = @floatFromInt(resCent.x - objCent.x);
                    const yDiff: f32 = @floatFromInt(resCent.y - objCent.y);
                    const diff: f32 = std.math.sqrt((xDiff * xDiff) + (yDiff * yDiff));
                    diffs[resIdx] = diff;
                }
                mat[objIdx] = diffs;
            }
            //std.debug.print("Distance matrix: {d:.2}\n", .{mat});

            // 2) assign tracker to result object
            // option a) sort rows based on min distance, then sort cols based on sorted rows
            // option b) iterate tracker, choose min dist for each sequentially
            for (self.objects.items, 0..) |obj, objIdx| {
                // tracker has already assigned new input
                if (objIdx > usedInputs.len - 1) {
                    break;
                }
                if (usedInputs[objIdx] == true) {
                    continue;
                }
                // find the minimum distance from tracker object to matrix of input object
                var minIdx: usize = 0;
                for (mat[objIdx], 0..) |diff, i| {
                    if (diff < mat[objIdx][minIdx]) {
                        minIdx = i;
                    }
                }

                // All other items
                results.items[minIdx].id = obj.id; // we want to keep old id
                self.objects.items[objIdx] = results.items[minIdx];

                // Mark input object as handled so we dont use it again
                usedTrackers[objIdx] = true;
                usedInputs[minIdx] = true;
            }

            // tracker objects with no matching input objects? increase disappeared on those NOT USED
            if (self.objects.items.len > results.items.len) {
                var i: usize = 0;
                while (i < self.objects.items.len) : (i += 1) {
                    if (usedTrackers[i] == true) {
                        continue;
                    }
                    //std.log.debug("Increasing tracker ID disappearance: {d}\n", .{i});
                    self.objects.items[i].increaseDisapperance();
                    if (self.objects.items[i].disappeared > self.maxLife) {
                        //_ = self.objects.orderedRemove(i);
                        //_ = self.disappeared.orderedRemove(i);
                        try self.unregister(i);
                        //i -= 1; // need to decrease counter, as unregister mutates in-place
                    }
                }
            }
            // more input objects than tracked objects? add to tracker
            if (results.items.len > self.objects.items.len) {
                //std.log.debug("Surplus results found: usedCols: {any}\n", .{usedCols});
                for (results.items, 0..) |res, i| {
                    if (usedInputs[i] == true) {
                        continue;
                    }
                    //std.log.debug("Found new object to track:  res: {any}\n", .{res});
                    try self.register(res);
                }
            }
        }
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
fn performDetection(img: *Mat, scoreMat: Mat, rows: usize, _: i32, tracker: *GameTracker, allocator: Allocator) !void {
    //try cv.imWrite("object.jpg", img.*);
    //std.debug.print("rows {d}\n", .{rows});
    //std.debug.print("cols {d}\n", .{cols});
    const green = cv.Color{ .g = 255 };
    const red = cv.Color{ .r = 255 };
    var i: usize = 0;

    //std.debug.print("shape input {any}\n", .{cols});
    // factor is model input / model shape
    // float x_factor = modelInput.cols / modelShape.width;
    const iRow: f32 = @floatFromInt(img.cols());
    const iCol: f32 = @floatFromInt(img.rows());
    const xFact: f32 = iRow / 640.0;
    const yFact: f32 = iCol / 640.0;

    var bboxes = ArrayList(cv.Rect).init(allocator);
    var centrs = ArrayList(cv.Point).init(allocator);
    var scores = ArrayList(f32).init(allocator);
    var classes = ArrayList(i32).init(allocator);
    defer bboxes.deinit();
    defer centrs.deinit();
    defer scores.deinit();
    defer classes.deinit();

    // 1) first run, fetch all detections with a minimum score
    while (i < rows) : (i += 1) {
        // scores is a vector of results[0..4] (x,y,w,h) followed by scores for each class
        //var classScores = try results.region(cv.Rect.init(4, @intCast(i), CLASSES.len, 1));
        //var classScores = try cv.Mat.initFromMat(results, 1, 4,results.getType(), 1, 4);
        //defer classScores.deinit();

        // minMaxLoc extracts max and min scores from entire result vector
        //const sc = cv.Mat.minMaxLoc(scoreMat);
        var classScores = try scoreMat.region(cv.Rect.init(4, @intCast(i), CLASSES.len, 1));
        defer classScores.deinit();
        // minMaxLoc extracts max and min scores (and locations) from entire result vector
        // we want sc.max_val (=conf) and sc.max_loc (=class) might be faster to do in std lib though
        const sc = cv.Mat.minMaxLoc(classScores);
        //std.debug.print("scores {any}\n", .{sc});
        if (sc.max_val > 0.30) {
            //std.debug.print("results: conf {d:.2}  class: {any}\n", .{sc.max_val, sc.max_loc});
            // compose rect, score and confidence for detection
            var x: f32 = scoreMat.get(f32, i, 0);
            var y: f32 = scoreMat.get(f32, i, 1);
            var w: f32 = scoreMat.get(f32, i, 2);
            var h: f32 = scoreMat.get(f32, i, 3);
            var left: i32 = @intFromFloat((x - 0.5 * w) * xFact);
            var top: i32 = @intFromFloat((y - 0.5 * h) * yFact);
            var width: i32 = @intFromFloat(w * xFact);
            var height: i32 = @intFromFloat(h * yFact);
            const rect = cv.Rect{ .x = left, .y = top, .width = width, .height = height };
            const cx: i32 = @intFromFloat(x * xFact);
            const cy: i32 = @intFromFloat(y * yFact);
            const centr: cv.Point = cv.Point.init(cx, cy);
            //std.debug.print("class id {d}\n", .{sc.max_loc.x});  // yes, scores.max_loc is Point with x vector as class ID
            //std.debug.print("confidence {d:.3}\n", .{sc.max_val});
            try centrs.append(centr);
            try bboxes.append(rect);
            try scores.append(@floatCast(sc.max_val));
            try classes.append(sc.max_loc.x);
        }
    }
    // 2) Non Maximum Suppression : remove overlapping boxes (= max confidence and least overlap)
    // return arraylist of indices of non overlapping boxes
    const indices = try cv.dnn.nmsBoxes(bboxes.items, scores.items, 0.25, 0.45, 1, allocator);
    defer indices.deinit();

    // 3) reduce results
    var reduced = ArrayList(Result).init(allocator);
    defer reduced.deinit();
    for (indices.items, 0..indices.items.len) |numIndex, _| {
        const idx: usize = @intCast(numIndex);
        //const cls: usize = @intCast(classes.items[idx]);
        //const sco = scores.items[idx];
        try reduced.append(Result{
            .id = idx,
            .box = bboxes.items[idx],
            .centre = centrs.items[idx],
            .prevCentre = centrs.items[idx],
            .score = scores.items[idx],
            .classId = @intCast(classes.items[idx]),
        });
    }
    // 4) update tracker items with cleaned results
    try tracker.update(reduced, allocator);

    // 5) print info
    //std.debug.print("reduced items: {d}\n", .{reduced.items.len});
    //std.debug.print("tracked items: {d}\n", .{tracker.objects.items.len});
    //std.debug.print("disappr items: {d}\n", .{tracker.disappeared.items.len});

    // Add bounding boxes, centroids, arrows and labels to image
    //for (reduced.items) |obj| {
    for (tracker.objects.items) |obj| {
        if (obj.classId == 1) { // class 1: a ball! we return focus
            tracker.focusId = obj.id;
            tracker.lastFocusObj = obj;
            cv.arrowedLine(img, cv.Point.init(obj.box.x + @divFloor(obj.box.width, 2), obj.box.y - 50), cv.Point.init(obj.box.x + @divFloor(obj.box.width, 2), obj.box.y - 30), green, 4);
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

    // Frames per second timing
    tracker.frames += 1;
    if (tracker.frames >= 60) {
        const lap: u64 = tracker.getTimeSpent();
        var flap: f64 = @floatFromInt(lap);
        const secs: f64 = flap / 1000000000;
        tracker.fps = tracker.frames / secs;
        tracker.frames = 0;
    }
    var fpsBuf = [_]u8{undefined} ** 20;
    const fpsTxt = try std.fmt.bufPrint(&fpsBuf, "FPS ({d:.2})", .{ tracker.fps });
    cv.putText(img, fpsTxt, cv.Point.init(10,30), cv.HersheyFont{ .type = .simplex }, 0.5, green, 2);
    var modeBuf = [_]u8{undefined} ** 14;
    const modeTxt = try std.fmt.bufPrint(&modeBuf, "{s}", .{ @tagName(gameMode) });
    cv.putText(img, modeTxt, cv.Point.init(10,620), cv.HersheyFont{ .type = .simplex }, 0.5, green, 2);

    const focusObj = tracker.getFocusObj();
    // TODO: is this neccessary? we should always have a focus object
    // const focusObj = tracker.getFocusObj() catch |err| {
    //     std.debug.print("Tracker error: {any}\n", .{err});
    // };

    // Now see if we have pending modes
    switch (gameMode) {
        .IDLE, .TRACK, .TRACK_IDLE, .STOP => {
            if (focusObj) |obj| {
                try tracker.sendCentroid(obj.centre);
            }
        },
        .SNAP => {
            std.debug.print("SENDING IMAGE\n", .{});
            img.addMatWeighted(1.0, tracker.overlay, 0.4, 0.5, img);
            try tracker.sendImage(img);
            gameMode = lastGameMode;
        },
        else => {
            if (focusObj) |obj| {
                std.debug.print("Centroid: {any}\n", .{obj.centre});
            }
        },
    }
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

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = try std.process.argsWithAllocator(allocator);

    const prog = args.next();
    const deviceIdChar = args.next() orelse {
        std.log.err("usage: {s} [cameraID] [model]", .{prog.?});
        std.os.exit(1);
    };
    const model = args.next() orelse {
        std.log.err("usage: {s} [cameraID [model]]", .{prog.?});
        std.os.exit(1);
    };
    args.deinit();

    const deviceId = try std.fmt.parseUnsigned(i32, deviceIdChar, 10);
    _ = try std.fmt.parseUnsigned(i32, deviceIdChar, 10);

    // open webcam
    var webcam = try cv.VideoCapture.init();
    try webcam.openDevice(deviceId);
    defer webcam.deinit();

    // open display window
    const winName = "DNN Detection";
    var window = try cv.Window.init(winName);
    defer window.deinit();

    // prepare image matrix
    var img = try cv.Mat.init();
    defer img.deinit();
    //img = try cv.imRead("object.jpg", .unchanged);
    //img = try cv.imRead("cardboard_cup1-00022.png", .unchanged);

    //var img = try cv.Mat.initSize(640,640, cv.Mat.MatType.cv8uc3);

    // open DNN object tracking model
    const scale: f64 = 1.0 / 255.0;
    const size: cv.Size = cv.Size.init(640, 640);
    var net = cv.Net.readNetFromONNX(model) catch |err| {
        std.debug.print("Error: {any}\n", .{err});
        std.os.exit(1);
    };

    // const scale: f64 = 1.0;
    // const size: cv.Size = cv.Size.init(300, 300);
    // var net = cv.Net.readNet("./saved_model.pb", "./saved_model.pbtxt") catch |err| {
    //     std.debug.print("Error: {}\n", .{err});
    //     std.os.exit(1);
    // };


    // tensorflowjs mobilenet
    // const scale: f64 = 1.0 / 255.0;
    // const size: cv.Size = cv.Size.init(300, 300);
    // var net = cv.Net.readNetFromTensorflow(model) catch |err| {
    //     //var net = cv.Net.readNet(model, "") catch |err| {
    //     std.debug.print("Error: {any}\n", .{err});
    //     std.os.exit(1);
    // };
    defer net.deinit();

    if (net.isEmpty()) {
        std.debug.print("Error: could not load model\n", .{});
        std.os.exit(1);
    }

    net.setPreferableBackend(.default);  // .default, .halide, .open_vino, .open_cv. .vkcom, .cuda
    net.setPreferableTarget(.fp16);       // .cpu, .fp32, .fp16, .vpu, .vulkan, .fpga, .cuda, .cuda_fp16

    var layers = try net.getLayerNames(allocator);
    std.debug.print("getLayerNames {any}\n", .{layers.len});
    const unconnected = try net.getUnconnectedOutLayers(allocator);
    std.debug.print("getUnconnectedOutLayers {any}\n", .{unconnected.items});


    // Game mode manager in separate thread
    wsClient = try websocket.connect(allocator, "localhost", 8665, .{});
    defer wsClient.deinit();

    try wsClient.handshake("/ws?channels=shell-game", .{
         .timeout_ms = 5000,
         .headers = "host: localhost:8665\r\n",
    });
    const msgHandler = MsgHandler{.allocator = allocator};
    const thread = try wsClient.readLoopInNewThread(msgHandler);
    thread.detach();

    // centroid tracker to remember objects
    var tracker = try GameTracker.init(allocator);
    //defer tracker.deinit();
    // onnx
    //const mean = cv.Scalar.init(0, 0, 0, 0); // mean subtraction is a technique used to aid our Convolutional Neural Networks.
    //const swapRB = true;
    //const crop = false;

    // mobilenet
    const mean = cv.Scalar.init(0, 0, 0, 0); // mean subtraction is a technique used to aid our Convolutional Neural Networks.
    const swapRB = true;
    const crop = false;

    while (true) {
        webcam.read(&img) catch {
            std.debug.print("capture failed", .{});
            std.os.exit(1);
        };
        if (img.isEmpty()) {
            continue;
        }

        img.flip(&img, 1); // flip horizontally
        var squaredImg = try formatToSquare(img);
        defer squaredImg.deinit();
        cv.resize(squaredImg, &squaredImg, size, 0, 0, .{});

        // transform image to CV matrix / 4D blob
        var blob = try cv.Blob.initFromImage(squaredImg, scale, size, mean, swapRB, crop);
        defer blob.deinit();
        // run inference on Matrix
        // prob result: objid, classid, confidence, left, top, right, bottom.
        net.setInput(blob, "");
        //The model outputs two Mats (1 x 4420 x 2) and (1 x 4420 x 4) of scores and boxes
        //var outNames = [_][]const u8{ "scores", "boxes" };
        //var probs = try net.forwardLayers(&outNames, allocator);
        //var scoreMat = probs.list.items[0];
        //var boxMat = probs.list.items[1];
        //std.debug.print("scoreMat size {any}\n", .{probMatScores.size()});
        //std.debug.print("boxMat size {any}\n", .{probMatBoxes.size()});
        var probs = try net.forward("");
        defer probs.deinit();
        //std.debug.print("orig probmat size {any}\n", .{probs.size()});
        // Yolo v8 reshape
        // xywh vector + numclasses * 8400 rows
        //std.debug.print("orig probmat: {any}\n", .{probs.size()});
        // orig probmat: { 1, 84, 8400 (ch, cols, rows)} : want to reshape to { 8400, 84 (rows, cols) }
        // To do so : we reshape to 2D array and then transpose
        // reshape(channels, rows) (channels val of 0 means no change)
        const rows: usize = @intCast(probs.size()[2]);
        const dims: i32 = probs.size()[1];
        var probMat = try probs.reshape(1, @intCast(dims));
        defer probMat.deinit();
        cv.Mat.transpose(probMat, &probMat);
        //const rows = probMat.get(i32, 0, 0);
        //const dimensions = probMat.get(i32, 0, 1);
        // xywh vector + numclasses * 8400 rows
        // const rows: usize = @intCast(probs.list.items[0].size()[1]);
        // const dims: i32 = probs.list.items[0].size()[2];
        // var probMatScores = try scoreMat.reshape(-1, 2);
        // var probMatBoxes = try boxMat.reshape(-1, 4);
        //defer probMatScores.deinit();
        //defer probMatBoxes.deinit();

        // yolov8 has an output of shape (batchSize, 84,  8400) (Num classes + box[x,y,w,h])
        try performDetection(&squaredImg, probMat, rows, dims, &tracker, allocator);
        // time frames per sec

        window.imShow(squaredImg);
        if (window.waitKey(1) == 27) {
            break;
        }
    }
}
