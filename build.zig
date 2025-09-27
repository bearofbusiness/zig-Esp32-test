const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .whitelist = espressif_targets,
        .default_target = espressif_targets[0],
    });
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "app_zig",
        .root_source_file = b.path("main/app.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.addIncludePath(b.path("main"));

    lib.linkLibC(); // stubs for libc

    // const check_lib = b.addStaticLibrary(.{
    //     .name = "app_zig_check",
    //     .root_source_file = b.path("main/app.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // check_lib.root_module.addImport("idf", idf_wrapped_modules(b));
    // check_lib.linkLibC();
    // try includeDeps(b, check_lib);

    // const check = b.step("check", "ZLS type-check only");
    // check.dependOn(&check_lib.step);

    try includeDeps(b, lib);
    b.installArtifact(lib);
}

fn includeDeps(b: *std.Build, lib: *std.Build.Step.Compile) !void {
    const include_dirs = std.process.getEnvVarOwned(b.allocator, "INCLUDE_DIRS") catch "";
    if (!std.mem.eql(u8, include_dirs, "")) {
        var it_inc = std.mem.tokenizeAny(u8, include_dirs, ";");
        while (it_inc.next()) |dir| {
            lib.addIncludePath(.{ .cwd_relative = dir });
        }
    }

    const idf_path = std.process.getEnvVarOwned(b.allocator, "IDF_PATH") catch "";
    if (!std.mem.eql(u8, idf_path, "")) {
        try searched_idf_include(b, lib, idf_path);
        try searched_idf_libs(b, lib);
    }

    const home_dir = std.process.getEnvVarOwned(b.allocator, "HOME") catch "";
    if (!std.mem.eql(u8, home_dir, "")) {
        const archtools = b.fmt("{s}-esp-elf", .{
            @tagName(lib.rootModuleTarget().cpu.arch),
        });

        lib.addIncludePath(.{
            .cwd_relative = b.pathJoin(&.{
                home_dir,
                ".espressif",
                "tools",
                archtools,
                "esp-14.2.0_20241119",
                archtools,
                "include",
            }),
        });
        lib.addSystemIncludePath(.{
            .cwd_relative = b.pathJoin(&.{
                home_dir,
                ".espressif",
                "tools",
                archtools,
                "esp-14.2.0_20241119",
                archtools,
                archtools,
                "sys-include",
            }),
        });
        lib.addIncludePath(.{
            .cwd_relative = b.pathJoin(&.{
                home_dir,
                ".espressif",
                "tools",
                archtools,
                "esp-14.2.0_20241119",
                archtools,
                archtools,
                "include",
            }),
        });
    }

    // user include dirs
    lib.addIncludePath(b.path("include"));
}

pub fn searched_idf_libs(b: *std.Build, lib: *std.Build.Step.Compile) !void {

    // this block fixes zls not being able to compile and not having completions
    var zls_is_builder = true;
    var dir = std.fs.cwd().openDir("./build", .{
        .iterate = true,
    }) catch DIR: {
        zls_is_builder = false;
        break :DIR try std.fs.cwd().openDir("../build", .{
            .iterate = true,
        });
    };
    defer dir.close();
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const ext = std.fs.path.extension(entry.basename);
        const lib_ext = inline for (&.{".obj"}) |e| {
            if (std.mem.eql(u8, ext, e))
                break true;
        } else false;
        if (lib_ext) {
            // removed std.fs.path.dirname(@src().file) because it always fails only returns build.zig
            const src_path = if (zls_is_builder) b.pathResolve(&.{"."}) else b.pathResolve(&.{".."});
            const cwd_path = b.pathJoin(&.{ src_path, "build", b.dupe(entry.path) });
            const lib_file: std.Build.LazyPath = .{ .cwd_relative = cwd_path };
            lib.addObjectFile(lib_file);
        }
    }
}

pub fn searched_idf_include(b: *std.Build, lib: *std.Build.Step.Compile, idf_path: []const u8) !void {
    const comp = b.pathJoin(&.{ idf_path, "components" });
    var dir = try std.fs.cwd().openDir(comp, .{
        .iterate = true,
    });
    defer dir.close();
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const ext = std.fs.path.extension(entry.basename);
        const include_file = inline for (&.{".h"}) |e| {
            if (std.mem.eql(u8, ext, e))
                break true;
        } else false;
        if (include_file) {
            const include_dir = b.pathJoin(&.{ comp, std.fs.path.dirname(b.dupe(entry.path)).? });
            lib.addIncludePath(.{ .cwd_relative = include_dir });
        }
    }
}

// Targets config
pub const espressif_targets: []const std.Target.Query = if (isEspXtensa())
    xtensa_targets ++ riscv_targets
else
    riscv_targets;

const riscv_targets = &[_]std.Target.Query{
    // esp32-c3/c2
    .{
        .cpu_arch = .riscv32,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = std.Target.riscv.featureSet(&.{ .m, .c, .zifencei, .zicsr }),
    },
    // esp32-c6/61/h2
    .{
        .cpu_arch = .riscv32,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = std.Target.riscv.featureSet(&.{ .m, .a, .c, .zifencei, .zicsr }),
    },
    // esp32-p4 have .xesppie cpu-feature (espressif vendor extension)
    .{
        .cpu_arch = .riscv32,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.esp32p4 },
        .os_tag = .freestanding,
        .abi = .eabihf,
        .cpu_features_sub = std.Target.riscv.featureSet(&.{ .zca, .zcb, .zcmt, .zcmp }),
    },
};
const xtensa_targets = &[_]std.Target.Query{
    // need zig-fork (using espressif-llvm backend) to support this
    .{
        .cpu_arch = .xtensa,
        .cpu_model = .{ .explicit = &std.Target.xtensa.cpu.esp32 },
        .os_tag = .freestanding,
        .abi = .none,
    },
    .{
        .cpu_arch = .xtensa,
        .cpu_model = .{ .explicit = &std.Target.xtensa.cpu.esp32s2 },
        .os_tag = .freestanding,
        .abi = .none,
    },
    .{
        .cpu_arch = .xtensa,
        .cpu_model = .{ .explicit = &std.Target.xtensa.cpu.esp32s3 },
        .os_tag = .freestanding,
        .abi = .none,
    },
};

fn isEspXtensa() bool {
    var result = false;
    for (std.Target.Cpu.Arch.xtensa.allCpuModels()) |model| {
        result = std.mem.startsWith(u8, model.name, "esp");
        if (result) break;
    }
    return result;
}
