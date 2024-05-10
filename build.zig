const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Compile static zig library of opencv
    const cv = b.addStaticLibrary(std.Build.StaticLibraryOptions{
        .name = "zigcv",
        .target = target,
        .optimize = optimize,
    });
    cv.addIncludePath(.{ .path = "include" });
    cv.addIncludePath(.{ .path = "include/contrib" });
    cv.addLibraryPath(.{ .path = "libs" });
    cv.addLibraryPath(.{ .path = "libs/contrib" });
    cv.addIncludePath(.{ .path = "/usr/local/include" });
    cv.addIncludePath(.{ .path = "/usr/local/include/opencv4" });
    cv.addCSourceFiles(.{ .files = &.{
        "libs/asyncarray.cpp",
        "libs/calib3d.cpp",
        "libs/core.cpp",
        "libs/dnn.cpp",
        "libs/features2d.cpp",
        "libs/highgui.cpp",
        "libs/imgcodecs.cpp",
        "libs/imgproc.cpp",
        "libs/objdetect.cpp",
        "libs/photo.cpp",
        "libs/svd.cpp",
        "libs/version.cpp",
        "libs/video.cpp",
        "libs/videoio.cpp",
        "libs/contrib/tracking.cpp",
    }, .flags = &[_][]const u8{
        "-Wall",
        "-Wextra",
        "-std=c++11",
        "-stdlib=libc++",
    } });

    cv.linkLibC();
    cv.linkLibCpp();
    b.installArtifact(cv);

    // Compile static library of opencv for win64
    const wincv = b.addStaticLibrary(std.Build.StaticLibraryOptions{
        .name = "opencv",
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
        }),
        .optimize = optimize,
    });
    wincv.addIncludePath(.{ .path = "include" });
    wincv.addIncludePath(.{ .path = "include/contrib" });
    wincv.addLibraryPath(.{ .path = "libs" });
    wincv.addLibraryPath(.{ .path = "libs/contrib" });
    wincv.addIncludePath(.{ .path = "/usr/local/include" });
    wincv.addIncludePath(.{ .path = "/usr/local/include/opencv4" });
    wincv.addCSourceFiles(.{ .files = &.{
        "libs/asyncarray.cpp",
        "libs/calib3d.cpp",
        "libs/core.cpp",
        "libs/dnn.cpp",
        "libs/features2d.cpp",
        "libs/highgui.cpp",
        "libs/imgcodecs.cpp",
        "libs/imgproc.cpp",
        "libs/objdetect.cpp",
        "libs/photo.cpp",
        "libs/svd.cpp",
        "libs/version.cpp",
        "libs/video.cpp",
        "libs/videoio.cpp",
        "libs/contrib/tracking.cpp",
    }, .flags = &[_][]const u8{
        "-Wall",
        "-Wextra",
        "-std=c++11",
    } });

    wincv.linkLibC();
    wincv.linkLibCpp();
    b.installArtifact(wincv);
    // target host compiler

    const exe = b.addExecutable(.{
        .name = "robot-eyes",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // //exe.root_module.addImport("zigcv", b.createModule(.{ .root_source_file = .{ .path = "libs/zigcv.zig" } }));
    //exe.addObjectFile(.{ .path = "zig-out/lib/libopencv.a"});
    const zigcvMod = b.addModule("zigcv", .{ .root_source_file = .{ .path = "libs/zigcv.zig" } });
    zigcvMod.addCSourceFiles(.{ .files = &.{
        "libs/asyncarray.cpp",
        "libs/calib3d.cpp",
        "libs/core.cpp",
        "libs/dnn.cpp",
        "libs/features2d.cpp",
        "libs/highgui.cpp",
        "libs/imgcodecs.cpp",
        "libs/imgproc.cpp",
        "libs/objdetect.cpp",
        "libs/photo.cpp",
        "libs/svd.cpp",
        "libs/version.cpp",
        "libs/video.cpp",
        "libs/videoio.cpp",
        "libs/contrib/tracking.cpp",
    }, .flags = &[_][]const u8{
        "-Wall",
        "-Wextra",
        "-std=c++11",
    } });
    zigcvMod.addIncludePath(.{ .path = "include" });
    zigcvMod.addIncludePath(.{ .path = "include/contrib" });
    zigcvMod.addIncludePath(.{ .path = "/usr/local/include" });
    zigcvMod.addIncludePath(.{ .path = "/usr/local/include/opencv4" });
    exe.root_module.addImport("zigcv", zigcvMod);

    // // Websocket module
    const wsMod = b.dependency("websocket", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("websocket", wsMod.module("websocket"));

    exe.linkLibC();
    exe.linkSystemLibrary("opencv4");
    exe.linkSystemLibrary("simpleble-c");
    exe.linkSystemLibrary("unwind");
    exe.linkSystemLibrary("m");
    exe.linkSystemLibrary("c");
    exe.linkLibrary(cv);
    b.installArtifact(exe);

    // target armv7 - raspberry PI
    // const arm = b.addExecutable(.{
    //     .name = "robot-eyes-arm",
    //     .root_source_file = .{ .path = "src/main.zig" },
    //     .target = std.zig.CrossTarget{
    //         .cpu_arch = .aarch64,
    //         .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.cortex_a72 },
    //         .os_tag = .linux,
    //     },
    //     .optimize = optimize,
    // });
    // arm.linkLibrary(cv);
    // arm.linkLibC();
    // arm.addLibraryPath(.{ .path = "lib/armv7"});
    // arm.addIncludePath(.{ .path = "include" });
    // arm.addIncludePath(.{ .path = "include/contrib" });
    // arm.linkSystemLibrary("simpleble-c");
    // arm.linkSystemLibrary("opencv4");
    // arm.linkSystemLibrary("unwind");
    // arm.linkSystemLibrary("m");
    // arm.addAnonymousModule("zigcv", .{ .source_file = .{ .path = "libs/zigcv.zig" } });
    // arm.addModule("websocket", wsMod.module("websocket"));
    // _ = b.installArtifact(arm);

    // target win64
    // const win = b.addExecutable(.{
    //     .name = "robot-eyes-win",
    //     .root_source_file = .{ .path = "src/main.zig" },
    //     .target = std.zig.CrossTarget{
    //         .cpu_arch = .x86_64,
    //         .os_tag = .windows,
    //         //.abi = .msvc, // .gnu
    //     },
    //     .optimize = optimize,
    // });
    // win.linkLibC();
    // win.linkSystemLibrary("unwind");
    // win.linkSystemLibrary("m");
    // win.addIncludePath(.{ .path = "include" });
    // win.addIncludePath(.{ .path = "include/contrib" });

    // // mingw
    // win.addLibraryPath(.{ .path = "/usr/x86_64-w64-mingw32"});
    // win.addIncludePath(.{ .path = "include/win64/mingw64" });

    // // Opencv4
    // win.linkLibrary(wincv); // we add statick object instead
    // win.addLibraryPath(.{ .path = "libs/win64/opencv4/static"});
    // win.addObjectFile(.{ .path = "zig-out/lib/opencv-win.lib"});
    // win.addObjectFile(.{ .path = "libs/win64/opencv4/opencv_world490.dll"});
    // win.linkSystemLibrary("opencv4");

    // // SimpleBLE
    // win.addIncludePath(.{ .path = "include/simpleble-c" });
    // win.addLibraryPath(.{ .path = "libs/win64/simpleble"});
    // win.addObjectFile(.{ .path = "libs/win64/simpleble/simpleble-c.dll"});
    // win.linkSystemLibraryName("simpleble-c");
    // // // mingw
    // // win.addLibraryPath(.{ .path = "libs/win64/mingw64" });
    // // //win.addLibraryPath(.{ .path = "libs/win64/mingw/install/staticlib" });
    // // win.addIncludePath(.{ .path = "include/install" });
    // // //win.addIncludePath("c:/opencv/build/install/include");
    // // //win.addLibraryPath("c:/opencv/build/install/x64/mingw/staticlib");

    // // win.addObjectFile(.{ .path = "libs/win64/mingw64/libstdc++-6.dll"});
    // win.addAnonymousModule("zigcv", .{ .source_file = .{ .path = "libs/zigcv.zig" } });
    // win.addModule("websocket", wsMod.module("websocket"));
    // _ = b.installArtifact(win);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
