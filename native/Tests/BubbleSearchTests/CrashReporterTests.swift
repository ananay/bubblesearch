import XCTest
@testable import bubblesearch

/// The .ips crash-log parser feeding anonymous crash telemetry: a one-line
/// JSON header followed by a JSON body, as written by macOS Crash Reporter.
final class CrashReporterTests: XCTestCase {

    private let sampleIPS = """
    {"app_name":"BubbleSearch","timestamp":"2026-07-22 12:46:27.00 -0700","app_version":"1.0.4","bundleID":"com.ananayarora.bubblesearch","os_version":"macOS 27.0 (26A5388g)","incident_id":"C081277F"}
    {
      "faultingThread" : 0,
      "exception" : {"type":"EXC_CRASH","signal":"SIGABRT"},
      "termination" : {"indicator":"Abort trap: 6"},
      "threads" : [
        {"triggered":true,"frames":[
          {"imageOffset":38480,"symbol":"__pthread_kill","imageIndex":1},
          {"imageOffset":504728,"symbol":"abort","imageIndex":2},
          {"imageOffset":49580,"imageIndex":0}
        ]},
        {"frames":[{"imageOffset":3104,"symbol":"mach_msg2_trap","imageIndex":1}]}
      ],
      "usedImages" : [
        {"name":"Sparkle"},
        {"name":"libsystem_kernel.dylib"},
        {"name":"libsystem_c.dylib"}
      ]
    }
    """

    func testParsesHeaderFields() throws {
        let summary = try XCTUnwrap(CrashReporter.parse(ips: sampleIPS))
        XCTAssertEqual(summary.bundleID, "com.ananayarora.bubblesearch")
        XCTAssertEqual(summary.crashTime, "2026-07-22 12:46:27.00 -0700")
        XCTAssertEqual(summary.version, "1.0.4")
        XCTAssertEqual(summary.os, "macOS 27.0 (26A5388g)")
    }

    func testParsesExceptionAndTermination() throws {
        let summary = try XCTUnwrap(CrashReporter.parse(ips: sampleIPS))
        XCTAssertEqual(summary.exception, "EXC_CRASH / SIGABRT — Abort trap: 6")
    }

    func testParsesFaultingThreadFrames() throws {
        let summary = try XCTUnwrap(CrashReporter.parse(ips: sampleIPS))
        let lines = summary.frames.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "libsystem_kernel.dylib __pthread_kill")
        XCTAssertEqual(lines[1], "libsystem_c.dylib abort")
        // Symbol-less frame (stripped third-party code) falls back to offset.
        XCTAssertEqual(lines[2], "Sparkle +49580")
    }

    func testRejectsGarbage() {
        XCTAssertNil(CrashReporter.parse(ips: "not a crash log"))
        XCTAssertNil(CrashReporter.parse(ips: "{}\nnot json"))
    }
}
