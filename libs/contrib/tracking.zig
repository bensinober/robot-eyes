const std = @import("std");
const c = @import("../c_api.zig");
const core = @import("../core.zig");
const utils = @import("../utils.zig");
const assert = std.debug.assert;
const epnn = utils.ensurePtrNotNull;
const ensureFileExists = utils.ensureFileExists;
const Mat = core.Mat;
const Mats = core.Mats;
const Size = core.Size;
const Scalar = core.Scalar;
const Rect = core.Rect;
const AsyncArray = @import("../asyncarray.zig").AsyncArray;

// TrackerKCF is a Tracker based on KCF, which is a novel tracking framework that
// utilizes properties of circulant matrix to enhance the processing speed.
//
// For further details, please see:
// https://docs.opencv.org/master/d2/dff/classcv_1_1TrackerKCF.html
//

pub const TrackerKCF = struct {

    ptr: c.TrackerKCF,
    rect: Rect,
    tracking: bool,

    const Self = @This();

    pub fn init() !Self {
        var ptr = c.TrackerKCF_Create();
        ptr = try epnn(ptr);
        return Self{ .ptr = ptr, .rect = undefined, .tracking = false };
    }

    pub fn deinit(self: *Self) void {
        assert(self.ptr != null);
        _ = c.TrackerKCF_Close(self.ptr);
        self.*.ptr = null;
    }

    pub fn load(self: *Self, mat: *Mat, rect: Rect) void {
        _ = c.TrackerSubclass_Init(self.ptr, mat.*.ptr, rect.toC());
        self.rect = rect;
    }

    pub fn update(self: *Self, mat: *Mat) void {
        var c_rect: c.Rect = undefined;
        _ = c.TrackerSubclass_Update(self.ptr, mat.*.ptr, &c_rect);
        self.rect = Rect.initFromC(c_rect);
    }
};