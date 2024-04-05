const std = @import("std");

// EXPORTED CONSTANTS

pub const SIMPLEBLE_PERIPHERALS_MAX_COUNT = @as(c_int, 30);
pub const SIMPLEBLE_PERIPHERALS = @as(c_int, SIMPLEBLE_PERIPHERALS_MAX_COUNT - 1);
pub const SIMPLEBLE_DEPRECATED = @compileError("unable to translate macro: undefined identifier `__attribute__`"); // ../simpleble/build/export/simpleble/export.h:25:11
pub const SIMPLEBLE_UUID_STR_LEN = @as(c_int, 37);
pub const SIMPLEBLE_CHARACTERISTIC_MAX_COUNT = @as(c_int, 16);
pub const SIMPLEBLE_DESCRIPTOR_MAX_COUNT = @as(c_int, 16);
pub const SIMPLEBLE_SUCCESS: c_int = 0;
pub const SIMPLEBLE_FAILURE: c_int = 1;
pub const simpleble_err_t = c_uint;
pub const simpleble_uuid_t = extern struct {
    value: [37]u8,
};

pub const simpleble_adapter_t = ?*anyopaque;
pub const simpleble_peripheral_t = ?*anyopaque;
pub const SIMPLEBLE_OS_WINDOWS: c_int = 0;
pub const SIMPLEBLE_OS_MACOS: c_int = 1;
pub const SIMPLEBLE_OS_LINUX: c_int = 2;
pub const simpleble_os_t = c_uint;
pub const SIMPLEBLE_ADDRESS_TYPE_PUBLIC: c_int = 0;
pub const SIMPLEBLE_ADDRESS_TYPE_RANDOM: c_int = 1;
pub const SIMPLEBLE_ADDRESS_TYPE_UNSPECIFIED: c_int = 2;
pub const simpleble_address_type_t = c_uint;
pub const simpleble_descriptor_t = extern struct {
    uuid: simpleble_uuid_t,
};

pub const service_characteristic_t = extern struct {
    service: simpleble_uuid_t,
    characteristic: simpleble_uuid_t,
};

pub const simpleble_characteristic_t = extern struct {
    uuid: simpleble_uuid_t,
    can_read: bool,
    can_write_request: bool,
    can_write_command: bool,
    can_notify: bool,
    can_indicate: bool,
    descriptor_count: usize,
    descriptors: [16]simpleble_descriptor_t,
};
pub const simpleble_service_t = extern struct {
    uuid: simpleble_uuid_t,
    data_length: usize,
    data: [27]u8,
    characteristic_count: usize,
    characteristics: [16]simpleble_characteristic_t,
};
pub const simpleble_manufacturer_data_t = extern struct {
    manufacturer_id: u16,
    data_length: usize,
    data: [27]u8,
};

// EXPORTED VARIABLES

pub var characteristic_list: [32]service_characteristic_t = [1]service_characteristic_t{
    service_characteristic_t{
        .service = simpleble_uuid_t{
            .value = [1]u8{
                0,
            } ++ [1]u8{0} ** 36,
        },
        .characteristic = @import("std").mem.zeroes(simpleble_uuid_t),
    },
} ++ [1]service_characteristic_t{@import("std").mem.zeroes(service_characteristic_t)} ** 31;
pub var peripheral_list: [SIMPLEBLE_PERIPHERALS_MAX_COUNT]simpleble_peripheral_t = [1]simpleble_peripheral_t{
    null,
} ++ [1]simpleble_peripheral_t{@import("std").mem.zeroes(simpleble_peripheral_t)} ** SIMPLEBLE_PERIPHERALS;

pub var peripheral_list_len: usize = 0;
//pub var adapter: simpleble_adapter_t = @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)));

pub extern fn simpleble_adapter_is_bluetooth_enabled() bool;
pub extern fn simpleble_adapter_get_count() usize;
pub extern fn simpleble_adapter_get_handle(index: usize) simpleble_adapter_t;
pub extern fn simpleble_adapter_release_handle(handle: simpleble_adapter_t) void;
pub extern fn simpleble_adapter_identifier(handle: simpleble_adapter_t) [*c]u8;
pub extern fn simpleble_adapter_address(handle: simpleble_adapter_t) [*c]u8;
pub extern fn simpleble_adapter_scan_start(handle: simpleble_adapter_t) simpleble_err_t;
pub extern fn simpleble_adapter_scan_stop(handle: simpleble_adapter_t) simpleble_err_t;
pub extern fn simpleble_adapter_scan_is_active(handle: simpleble_adapter_t, active: [*c]bool) simpleble_err_t;
pub extern fn simpleble_adapter_scan_for(handle: simpleble_adapter_t, timeout_ms: c_int) simpleble_err_t;
pub extern fn simpleble_adapter_scan_get_results_count(handle: simpleble_adapter_t) usize;
pub extern fn simpleble_adapter_scan_get_results_handle(handle: simpleble_adapter_t, index: usize) simpleble_peripheral_t;
pub extern fn simpleble_adapter_get_paired_peripherals_count(handle: simpleble_adapter_t) usize;
pub extern fn simpleble_adapter_get_paired_peripherals_handle(handle: simpleble_adapter_t, index: usize) simpleble_peripheral_t;
pub extern fn simpleble_adapter_set_callback_on_scan_start(handle: simpleble_adapter_t, callback: ?*const fn (simpleble_adapter_t, ?*anyopaque) callconv(.C) void, userdata: ?*anyopaque) simpleble_err_t;
pub extern fn simpleble_adapter_set_callback_on_scan_stop(handle: simpleble_adapter_t, callback: ?*const fn (simpleble_adapter_t, ?*anyopaque) callconv(.C) void, userdata: ?*anyopaque) simpleble_err_t;
pub extern fn simpleble_adapter_set_callback_on_scan_updated(handle: simpleble_adapter_t, callback: ?*const fn (simpleble_adapter_t, simpleble_peripheral_t, ?*anyopaque) callconv(.C) void, userdata: ?*anyopaque) simpleble_err_t;
pub extern fn simpleble_adapter_set_callback_on_scan_found(handle: simpleble_adapter_t, callback: ?*const fn (simpleble_adapter_t, simpleble_peripheral_t, ?*anyopaque) callconv(.C) void, userdata: ?*anyopaque) simpleble_err_t;
pub extern fn simpleble_peripheral_release_handle(handle: simpleble_peripheral_t) void;
pub extern fn simpleble_peripheral_identifier(handle: simpleble_peripheral_t) [*c]u8;
pub extern fn simpleble_peripheral_address(handle: simpleble_peripheral_t) [*c]u8;
pub extern fn simpleble_peripheral_address_type(handle: simpleble_peripheral_t) simpleble_address_type_t;
pub extern fn simpleble_peripheral_rssi(handle: simpleble_peripheral_t) i16;
pub extern fn simpleble_peripheral_tx_power(handle: simpleble_peripheral_t) i16;
pub extern fn simpleble_peripheral_mtu(handle: simpleble_peripheral_t) u16;
pub extern fn simpleble_peripheral_connect(handle: simpleble_peripheral_t) simpleble_err_t;
pub extern fn simpleble_peripheral_disconnect(handle: simpleble_peripheral_t) simpleble_err_t;
pub extern fn simpleble_peripheral_is_connected(handle: simpleble_peripheral_t, connected: [*c]bool) simpleble_err_t;
pub extern fn simpleble_peripheral_is_connectable(handle: simpleble_peripheral_t, connectable: [*c]bool) simpleble_err_t;
pub extern fn simpleble_peripheral_is_paired(handle: simpleble_peripheral_t, paired: [*c]bool) simpleble_err_t;
pub extern fn simpleble_peripheral_unpair(handle: simpleble_peripheral_t) simpleble_err_t;
pub extern fn simpleble_peripheral_services_count(handle: simpleble_peripheral_t) usize;
pub extern fn simpleble_peripheral_services_get(handle: simpleble_peripheral_t, index: usize, services: [*c]simpleble_service_t) simpleble_err_t;
pub extern fn simpleble_peripheral_manufacturer_data_count(handle: simpleble_peripheral_t) usize;
pub extern fn simpleble_peripheral_manufacturer_data_get(handle: simpleble_peripheral_t, index: usize, manufacturer_data: [*c]simpleble_manufacturer_data_t) simpleble_err_t;
pub extern fn simpleble_peripheral_read(handle: simpleble_peripheral_t, service: simpleble_uuid_t, characteristic: simpleble_uuid_t, data: [*c][*c]u8, data_length: [*c]usize) simpleble_err_t;
pub extern fn simpleble_peripheral_write_request(handle: simpleble_peripheral_t, service: simpleble_uuid_t, characteristic: simpleble_uuid_t, data: [*c]const u8, data_length: usize) simpleble_err_t;
pub extern fn simpleble_peripheral_write_command(handle: simpleble_peripheral_t, service: simpleble_uuid_t, characteristic: simpleble_uuid_t, data: [*c]const u8, data_length: usize) simpleble_err_t;
pub extern fn simpleble_peripheral_notify(handle: simpleble_peripheral_t, service: simpleble_uuid_t, characteristic: simpleble_uuid_t, callback: ?*const fn (simpleble_uuid_t, simpleble_uuid_t, [*c]const u8, usize, ?*anyopaque) callconv(.C) void, userdata: ?*anyopaque) simpleble_err_t;
pub extern fn simpleble_peripheral_indicate(handle: simpleble_peripheral_t, service: simpleble_uuid_t, characteristic: simpleble_uuid_t, callback: ?*const fn (simpleble_uuid_t, simpleble_uuid_t, [*c]const u8, usize, ?*anyopaque) callconv(.C) void, userdata: ?*anyopaque) simpleble_err_t;
pub extern fn simpleble_peripheral_unsubscribe(handle: simpleble_peripheral_t, service: simpleble_uuid_t, characteristic: simpleble_uuid_t) simpleble_err_t;
pub extern fn simpleble_peripheral_read_descriptor(handle: simpleble_peripheral_t, service: simpleble_uuid_t, characteristic: simpleble_uuid_t, descriptor: simpleble_uuid_t, data: [*c][*c]u8, data_length: [*c]usize) simpleble_err_t;
pub extern fn simpleble_peripheral_write_descriptor(handle: simpleble_peripheral_t, service: simpleble_uuid_t, characteristic: simpleble_uuid_t, descriptor: simpleble_uuid_t, data: [*c]const u8, data_length: usize) simpleble_err_t;
pub extern fn simpleble_peripheral_set_callback_on_connected(handle: simpleble_peripheral_t, callback: ?*const fn (simpleble_peripheral_t, ?*anyopaque) callconv(.C) void, userdata: ?*anyopaque) simpleble_err_t;
pub extern fn simpleble_peripheral_set_callback_on_disconnected(handle: simpleble_peripheral_t, callback: ?*const fn (simpleble_peripheral_t, ?*anyopaque) callconv(.C) void, userdata: ?*anyopaque) simpleble_err_t;
pub extern fn simpleble_free(handle: ?*anyopaque) void;

pub fn print_buffer_hex(arg_buf: [*c]u8, arg_len: usize, arg_newline: bool) callconv(.C) void {
    var buf = arg_buf;
    var len = arg_len;
    var newline = arg_newline;
    {
        var i: usize = 0;
        while (i < len) : (i +%= 1) {
            std.debug.print("{X}", .{@as(c_int, @bitCast(@as(c_uint, buf[i])))});
            if (i < (len -% @as(usize, @bitCast(@as(c_long, @as(c_int, 1)))))) {
                std.debug.print(" ", .{});
            }
        }
    }
    if (newline) {
        std.debug.print("\n", .{});
    }
}
pub fn adapter_on_scan_start(arg_adapter: simpleble_adapter_t, arg_userdata: ?*anyopaque) callconv(.C) void {
    var adapter = arg_adapter;
    var userdata = arg_userdata;
    _ = @TypeOf(userdata);
    var identifier: [*c]u8 = simpleble_adapter_identifier(adapter);
    if (identifier == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
        return;
    }
    std.debug.print("Adapter {s} started scanning.\n", .{identifier});
    simpleble_free(@as(?*anyopaque, @ptrCast(identifier)));
}
pub fn adapter_on_scan_stop(arg_adapter: simpleble_adapter_t, arg_userdata: ?*anyopaque) callconv(.C) void {
    var adapter = arg_adapter;
    var userdata = arg_userdata;
    _ = @TypeOf(userdata);
    var identifier: [*c]u8 = simpleble_adapter_identifier(adapter);
    if (identifier == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) {
        return;
    }
    std.debug.print("Adapter {s} stopped scanning.\n", .{identifier});
    simpleble_free(@as(?*anyopaque, @ptrCast(identifier)));
}
pub fn adapter_on_scan_found(arg_adapter: simpleble_adapter_t, arg_peripheral: simpleble_peripheral_t, arg_userdata: ?*anyopaque) callconv(.C) void {
    var adapter = arg_adapter;
    var peripheral = arg_peripheral;
    var userdata = arg_userdata;
    _ = @TypeOf(userdata);
    var adapter_identifier: [*c]u8 = simpleble_adapter_identifier(adapter);
    var peripheral_identifier: [*c]u8 = simpleble_peripheral_identifier(peripheral);
    var peripheral_address: [*c]u8 = simpleble_peripheral_address(peripheral);
    if (((adapter_identifier == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) or (peripheral_identifier == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))) or (peripheral_address == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))) {
        return;
    }
    std.debug.print("Adapter {s} found device: {s} [{s}]\n", .{adapter_identifier, peripheral_identifier, peripheral_address});
    if (peripheral_list_len < @as(usize, @bitCast(@as(c_long, @as(c_int, SIMPLEBLE_PERIPHERALS_MAX_COUNT))))) {
        peripheral_list[blk: {
                const ref = &peripheral_list_len;
                const tmp = ref.*;
                ref.* +%= 1;
                break :blk tmp;
            }] = peripheral;
    } else {
        simpleble_peripheral_release_handle(peripheral);
    }
    simpleble_free(@as(?*anyopaque, @ptrCast(peripheral_address)));
    simpleble_free(@as(?*anyopaque, @ptrCast(peripheral_identifier)));
}

// TODO: handle peripheral update
pub fn adapter_on_scan_updated(arg_adapter: simpleble_adapter_t, arg_peripheral: simpleble_peripheral_t, arg_userdata: ?*anyopaque) callconv(.C) void {
    var adapter = arg_adapter;
    var peripheral = arg_peripheral;
    var userdata = arg_userdata;
    _ = @TypeOf(userdata);
    var adapter_identifier: [*c]u8 = simpleble_adapter_identifier(adapter);
    var peripheral_identifier: [*c]u8 = simpleble_peripheral_identifier(peripheral);
    var peripheral_address: [*c]u8 = simpleble_peripheral_address(peripheral);
    if (((adapter_identifier == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0))))))) or (peripheral_identifier == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))) or (peripheral_address == @as([*c]u8, @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(c_int, 0)))))))) {
        return;
    }
    std.debug.print("Adapter {s} updated device: {s} [{s}]\n", .{adapter_identifier, peripheral_identifier, peripheral_address});
    simpleble_peripheral_release_handle(peripheral);
    simpleble_free(@as(?*anyopaque, @ptrCast(peripheral_address)));
    simpleble_free(@as(?*anyopaque, @ptrCast(peripheral_identifier)));
}

pub fn peripheral_on_notify(arg_service: simpleble_uuid_t, arg_characteristic: simpleble_uuid_t, arg_data: [*c]const u8, arg_data_length: usize, arg_userdata: ?*anyopaque) callconv(.C) void {
    var service = arg_service;
    _ = @TypeOf(service);
    var characteristic = arg_characteristic;
    _ = @TypeOf(characteristic);
    var data = arg_data;
    var data_length = arg_data_length;
    var userdata = arg_userdata;
    _ = @TypeOf(userdata);
    std.debug.print("Received: ", .{});
    var i: usize = 0;
    while (i < data_length) : (i +%= 1) {
        std.debug.print("{X}", .{@as(c_int, @bitCast(@as(c_uint, data[i])))});
    }
    std.debug.print("\n", .{});
}

pub fn clean_on_exit(arg_adapter: simpleble_adapter_t) callconv(.C) void {
    std.debug.print("Releasing allocated resources,\n", .{});
    {
        var i: usize = 0;
        while (i < peripheral_list_len) : (i +%= 1) {
            simpleble_peripheral_release_handle(peripheral_list[i]);
        }
    }
    simpleble_adapter_release_handle(arg_adapter);
}
