const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // =======================================================================
    // Build Options
    // =======================================================================
    const enable_liboqs = b.option(bool, "liboqs", "Enable post-quantum crypto via liboqs (requires liboqs installed)") orelse false;
    const liboqs_enabled = b.option(bool, "enable-liboqs", "Enable post-quantum crypto via liboqs") orelse enable_liboqs;

    // =======================================================================
    // L0: Transport Layer (mod.zig is the root - re-exports all L0 modules)
    // Note: time is NOT re-exported from mod.zig to avoid module conflicts
    // =======================================================================
    const l0_mod = b.createModule(.{
        .root_source_file = b.path("../core/l0-transport/mod.zig"),
    });

    // =======================================================================
    // Time Module (for direct import by QVL and others)
    // =======================================================================
    const time_mod = b.createModule(.{
        .root_source_file = b.path("../core/l0-transport/time.zig"),
    });

    // =======================================================================
    // liboqs Module (real or stub based on build option)
    // =======================================================================
    const liboqs_mod = b.createModule(.{
        .root_source_file = if (liboqs_enabled)
            b.path("../core/l1-identity/liboqs_real.zig")
        else
            b.path("../core/l1-identity/liboqs_stub.zig"),
    });

    // =======================================================================
    // Build Options Module
    // =======================================================================
    const options = b.addOptions();
    options.addOption(bool, "liboqs_enabled", liboqs_enabled);
    const options_mod = options.createModule();

    // =======================================================================
    // PQXDH Module (for soulkey.zig and did.zig imports)
    // =======================================================================
    const pqxdh_mod = b.createModule(.{
        .root_source_file = b.path("../core/l1-identity/pqxdh.zig"),
    });
    pqxdh_mod.addImport("liboqs", liboqs_mod);
    pqxdh_mod.addImport("build_options", options_mod);

    // =======================================================================
    // L1: Identity Layer (mod.zig is the root - re-exports all L1 modules)
    // Internal files use @import("file.zig"), not module imports
    // =======================================================================
    const l1_mod = b.createModule(.{
        .root_source_file = b.path("../core/l1-identity/mod.zig"),
    });
    // L1 needs time as module import for qvl/types.zig
    // L1 needs pqxdh as module import for soulkey.zig, did.zig
    l1_mod.addImport("time", time_mod);
    l1_mod.addImport("pqxdh", pqxdh_mod);

    // =======================================================================
    // Crypto Support (src/crypto - separate from L0/L1)
    // =======================================================================
    const shake_mod = b.createModule(.{
        .root_source_file = b.path("../src/crypto/shake.zig"),
    });
    const fips202_mod = b.createModule(.{
        .root_source_file = b.path("../src/crypto/fips202_bridge.zig"),
    });

    // =======================================================================
    // UTCP needs special handling - it imports from multiple layers
    // =======================================================================
    const utcp_mod = b.createModule(.{
        .root_source_file = b.path("../core/l0-transport/utcp/socket.zig"),
    });
    utcp_mod.addImport("lwf", l0_mod);
    utcp_mod.addImport("shake", shake_mod);
    utcp_mod.addImport("fips202_bridge", fips202_mod);
    utcp_mod.addImport("entropy", l1_mod);
    utcp_mod.addImport("slash", l1_mod);
    // pqxdh is accessed via l1_mod.pqxdh

    // =======================================================================
    // Quarantine (L0 security) - separate module as it's used independently
    // =======================================================================
    const quarantine_mod = b.createModule(.{
        .root_source_file = b.path("../core/l0-transport/quarantine.zig"),
    });

    // =======================================================================
    // QVL Module (standalone for direct import)
    // =======================================================================
    const qvl_mod = b.createModule(.{
        .root_source_file = b.path("../core/l1-identity/qvl.zig"),
    });
    qvl_mod.addImport("time", time_mod);

    // =======================================================================
    // Vaxis Dependency (TUI library)
    // =======================================================================
    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    const vaxis_mod = vaxis_dep.module("vaxis");

    // =======================================================================
    // L2 Membrane Module (from core)
    // =======================================================================
    const l2_membrane_mod = b.createModule(.{
        .root_source_file = b.path("../core/l2-membrane/policy.zig"),
    });
    l2_membrane_mod.addImport("lwf", l0_mod);

    // =======================================================================
    // Capsule Executable
    // =======================================================================
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "capsule",
        .root_module = exe_mod,
    });

    // Wire up all imports for the executable
    exe.root_module.addImport("l0_transport", l0_mod);
    exe.root_module.addImport("utcp", utcp_mod);
    exe.root_module.addImport("l1_identity", l1_mod);
    exe.root_module.addImport("qvl", qvl_mod);
    exe.root_module.addImport("quarantine", quarantine_mod);
    exe.root_module.addImport("l2_membrane", l2_membrane_mod);
    exe.root_module.addImport("vaxis", vaxis_mod);
    exe.root_module.addImport("build_options", options_mod);

    // Link system libraries
    exe.linkSystemLibrary("sqlite3");
    exe.linkSystemLibrary("duckdb");

    // Conditionally link liboqs for post-quantum crypto
    if (liboqs_enabled) {
        exe.linkSystemLibrary("oqs");
        std.log.info("Building with liboqs (post-quantum crypto enabled)", .{});
    } else {
        std.log.warn("Building WITHOUT liboqs. Post-quantum crypto disabled. Use -Denable-liboqs=true for PQ security.", .{});
    }

    exe.linkLibC();

    b.installArtifact(exe);

    // =======================================================================
    // Run command
    // =======================================================================
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // =======================================================================
    // Test step
    // =======================================================================
    const test_step = b.step("test", "Run unit tests");

    // Add test for core modules
    const pqxdh_test_mod = b.createModule(.{
        .root_source_file = b.path("../core/l1-identity/pqxdh.zig"),
        .target = target,
        .optimize = optimize,
    });
    pqxdh_test_mod.addImport("liboqs", liboqs_mod);
    pqxdh_test_mod.addImport("build_options", options_mod);

    const core_tests = b.addTest(.{
        .root_module = pqxdh_test_mod,
    });
    if (liboqs_enabled) {
        core_tests.linkSystemLibrary("oqs");
    }
    core_tests.linkLibC();

    const run_core_tests = b.addRunArtifact(core_tests);
    test_step.dependOn(&run_core_tests.step);
}
