const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Specify static or dynamic linkage",
    ) orelse .static;

    const std_dep_options = .{ .target = target, .optimize = optimize, .linkage = linkage };
    const std_mod_options: std.Build.Module.CreateOptions = .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .pic = true,
    };

    const fastdds = b.dependency("fastdds", std_dep_options).artifact("fast-dds");
    const fastcdr = b.dependency("fastcdr", std_dep_options).artifact("fast-cdr");
    const microcdr = b.dependency("microcdr", std_dep_options).artifact("microcdr");
    const uxr_client = b.dependency("uxr_client", std_dep_options).artifact("micro-xrce-dds-client");
    // const spdlog = b.dependency("spdlog", .{});
    const upstream = b.dependency("uxr_agent", .{});

    const std_cxx_flags: []const []const u8 = &.{
        "--std=c++11",
        "-pthread",
        "-Wall",
        "-Wextra",
        "-pedantic",
        "-Wcast-align",
        "-Wshadow",
        "-fstrict-aliasing",
        // Required to *actually* bring in the POSIX portions of the C std lib.
        // No idea why 'zig cc' sets this but build.zig does not :shrug:
        "-D_POSIX_C_SOURCE=200112L",
    };

    ////////////////////////////////////////////////////////////////////////////////
    // Micro-XRCE-DDS-Agent Library
    ////////////////////////////////////////////////////////////////////////////////

    const uagent_lib = b.addLibrary(.{
        .name = "micro-xrce-dds-agent",
        .root_module = b.createModule(std_mod_options),
        .linkage = linkage,
    });

    // // My guess at what ABIs support spdlog.
    // // I know that GNU works and MUSL does not. Besides that, just a guess.
    // const spdlog_supported: bool = switch (@import("builtin").abi) {
    //     .gnu, .gnuabi64, .gnuabin32, .gnueabi, .gnueabihf, .gnuf32, .gnuilp32, .gnusf, .gnux32, .msvc => true,
    //     else => false,
    // };

    // It seems that when logging is enabled, we encounter an illegal instruction and crash.
    // So, just leave it entirely disabled.
    const spdlog_supported: bool = false;

    const config_h = b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("include/uxr/agent//config.hpp.in") },
        .include_path = "uxr/agent/config.hpp",
    }, .{
        .UAGENT_FAST_PROFILE = 1,
        .UAGENT_CED_PROFILE = 1,
        .UAGENT_DISCOVERY_PROFILE = 1,
        .UAGENT_P2P_PROFILE = 1,
        .UAGENT_LOGGER_PROFILE = if (spdlog_supported) 1 else null,
        .UAGENT_SOCKETCAN_PROFILE = null,
        .UAGENT_CONFIG_RELIABLE_STREAM_DEPTH = 16,
        .UAGENT_CONFIG_BEST_EFFORT_STREAM_DEPTH = 16,
        .UAGENT_CONFIG_HEARTBEAT_PERIOD = 200,
        .UAGENT_CONFIG_TCP_MAX_CONNECTIONS = 100,
        .UAGENT_CONFIG_TCP_MAX_BACKLOG_CONNECTIONS = 100,
        .UAGENT_CONFIG_SERVER_QUEUE_MAX_SIZE = 32000,
        .UAGENT_CONFIG_CLIENT_DEAD_TIME = 30000,
        .UAGENT_SERVER_BUFFER_SIZE = 65535,
        .UAGENT_TWEAK_XRCE_WRITE_LIMIT = 1,
    });
    uagent_lib.addConfigHeader(config_h);
    uagent_lib.installHeader(config_h.getOutput(), "uxr/agent/config.hpp");

    uagent_lib.addCSourceFiles(.{
        .root = upstream.path("src/cpp"),
        .files = source_files ++ transport_files,
        .flags = std_cxx_flags,
    });
    uagent_lib.addIncludePath(upstream.path("include"));
    uagent_lib.addIncludePath(upstream.path("src/cpp"));
    // uagent_lib.addIncludePath(spdlog.path("include"));
    uagent_lib.installHeadersDirectory(upstream.path("include"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });

    uagent_lib.linkLibrary(fastdds);
    uagent_lib.linkLibrary(fastcdr);
    uagent_lib.linkLibrary(microcdr);
    uagent_lib.linkLibrary(uxr_client);

    b.installArtifact(uagent_lib);

    ////////////////////////////////////////////////////////////////////////////////
    // MicroXRCEAgent Executable
    ////////////////////////////////////////////////////////////////////////////////

    const uagent = b.addExecutable(.{
        .name = "MicroXRCEAgent",
        .root_module = b.createModule(std_mod_options),
    });
    uagent.addCSourceFile(.{ .file = upstream.path("microxrce_agent.cpp"), .flags = std_cxx_flags });

    uagent.linkLibrary(fastdds);
    uagent.linkLibrary(fastcdr);
    uagent.linkLibrary(microcdr);
    uagent.linkLibrary(uxr_client);
    uagent.linkLibrary(uagent_lib);
    // uagent.addIncludePath(spdlog.path("include"));

    b.installArtifact(uagent);
}

const source_files: []const []const u8 = &.{
    "Agent.cpp",
    "AgentInstance.cpp",
    "Root.cpp",
    "processor/Processor.cpp",
    "client/ProxyClient.cpp",
    "participant/Participant.cpp",
    "topic/Topic.cpp",
    "publisher/Publisher.cpp",
    "subscriber/Subscriber.cpp",
    "datawriter/DataWriter.cpp",
    "datareader/DataReader.cpp",
    "requester/Requester.cpp",
    "replier/Replier.cpp",
    "object/XRCEObject.cpp",
    "types/XRCETypes.cpp",
    "types/MessageHeader.cpp",
    "types/SubMessageHeader.cpp",
    "message/InputMessage.cpp",
    "message/OutputMessage.cpp",
    "utils/ArgumentParser.cpp",
    "transport/Server.cpp",
    "transport/stream_framing/StreamFramingProtocol.cpp",
    "transport/custom/CustomAgent.cpp",
    "transport/discovery/DiscoveryServer.cpp",
    "types/TopicPubSubType.cpp",
    "middleware/fastdds/FastDDSEntities.cpp",
    "middleware/fastdds/FastDDSMiddleware.cpp",
    "middleware/ced/CedEntities.cpp",
    "middleware/ced/CedMiddleware.cpp",
    "transport/p2p/AgentDiscoverer.cpp",
    "p2p/InternalClientManager.cpp",
    "p2p/InternalClient.cpp",
};

const transport_files: []const []const u8 = &.{
    "transport/udp/UDPv4AgentLinux.cpp",
    "transport/udp/UDPv6AgentLinux.cpp",
    "transport/tcp/TCPv4AgentLinux.cpp",
    "transport/tcp/TCPv6AgentLinux.cpp",
    "transport/serial/SerialAgentLinux.cpp",
    "transport/serial/TermiosAgentLinux.cpp",
    "transport/serial/MultiSerialAgentLinux.cpp",
    "transport/serial/MultiTermiosAgentLinux.cpp",
    "transport/serial/PseudoTerminalAgentLinux.cpp",
    "transport/discovery/DiscoveryServerLinux.cpp",
    "transport/p2p/AgentDiscovererLinux.cpp",
};
