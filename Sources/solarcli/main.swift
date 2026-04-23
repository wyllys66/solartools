// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Wyllys Ingersoll
//
// solarcli — read the solar-charge status of a Logitech K750 keyboard on macOS.
//
// Purpose
// -------
// The K750 is a solar-powered wireless keyboard that talks to a host through a
// Logitech Unifying Receiver (USB VID 0x046d, PID 0xc52b). It reports battery
// charge and ambient light over Logitech's vendor-specific HID++ protocol.
// This tool issues a HID++ solar-charge request (sub-id 0x0b) and decodes
// the keyboard's subsequent status broadcasts (also sub-id 0x0b) into a
// human-readable charge % and lux reading. Byte 4 of the request tells the
// firmware how many reports to emit before going quiet.
//
// Approach
// --------
// Rather than claiming the USB interface directly (which on macOS would
// require DriverKit entitlements and fight the kernel HID driver), the tool
// speaks to the receiver through the IOKit HID Manager. The HID transport
// lives in the shared `SolarCore` library — this file is the CLI front end.
//
// Modes
// -----
//   solar --once              Fire the query, retry every ~1.5s up to a
//                             30-second cap, print the first valid reading,
//                             and exit. Retrying matters because the K750's
//                             status broadcast is sporadic.
//   solar --monitor           Keep the run loop alive, resending the query
//       [-i SECONDS]          on a timer (default 60s) and printing each
//                             reading as it arrives until Ctrl-C.
//   solar --debug             Dump every incoming HID report to stderr as hex,
//                             useful when porting to firmware variants that
//                             use different sub-ids or offsets.
//
// Background
// ----------
// The HID++ control packet and response layout follow from Julien Danjou's
// 2012 reverse-engineering of the K750 on Linux.
//
// Author
// ------
// Wyllys Ingersoll (with assist from Claude.ai)
//

import Foundation
import IOKit.hid
import SolarCore

private let onceTimeout: TimeInterval = 30
private let onceRetryInterval: TimeInterval = 1.5

// MARK: - Arg parsing

private enum Mode {
    case once
    case monitor(interval: TimeInterval)
}

private var debugHID = false

private func printUsage() {
    print("""
    Usage: solar [options]

    Reads solar charge and ambient light from a Logitech K750 keyboard by
    sending a HID++ message through its Unifying Receiver (046d:c52b).

    Options:
      -d, --debug             Display debug output
      -o, --once              Query once and exit (default)
      -m, --monitor           Poll continuously until interrupted (Ctrl-C)
      -i, --interval SECONDS  Poll interval in monitor mode (default: 60)
      -h, --help              Show this help

    Note: On first run, macOS may require Input Monitoring permission for
    Terminal.app (System Settings -> Privacy & Security -> Input Monitoring).
    """)
}

private func die(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("solar: \(message)\n".utf8))
    exit(code)
}

private func parseArgs() -> Mode {
    var wantMonitor = false
    var interval: TimeInterval = 60
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        switch args[i] {
        case "-o", "--once":
            wantMonitor = false
        case "-m", "--monitor":
            wantMonitor = true
        case "-i", "--interval":
            i += 1
            guard i < args.count, let v = Double(args[i]), v > 0 else {
                printUsage()
                die("--interval requires a positive number of seconds", code: 2)
            }
            interval = v
        case "-d", "--debug":
            debugHID = true
        case "-h", "--help":
            printUsage()
            exit(0)
        default:
            printUsage()
            die("unknown argument '\(args[i])'", code: 2)
        }
        i += 1
    }
    return wantMonitor ? .monitor(interval: interval) : .once
}

private func format(_ r: Reading) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return "\(f.string(from: r.timestamp))  charge: \(r.charge)%  light: \(r.lux) lux"
}

// MARK: - Entry

private let mode = parseArgs()

do {
    let device = try openReceiver()
    let receiver = SolarReceiver(device: device)
    receiver.debug = debugHID

    switch mode {
    case .once:
        var reading: Reading?
        receiver.onReading = { r in
            reading = r
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        receiver.scheduleOnCurrentRunLoop()
        try receiver.sendQuery(reports: UInt8(clamping: Int(onceTimeout)))

        // The K750's status broadcast is sporadic; resend the query periodically
        // so we don't rely on a single shot landing during the listening window.
        let retry = Timer.scheduledTimer(withTimeInterval: onceRetryInterval, repeats: true) { _ in
            do {
                try receiver.sendQuery(reports: UInt8(clamping: Int(onceTimeout)))
            } catch {
                FileHandle.standardError.write(Data("solar: \(error)\n".utf8))
            }
        }
        let timeout = Timer.scheduledTimer(withTimeInterval: onceTimeout, repeats: false) { _ in
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopRun()
        retry.invalidate()
        timeout.invalidate()

        guard let r = reading else { throw SolarError.timedOut }
        print(format(r))

    case .monitor(let interval):
        receiver.onReading = { r in
            print(format(r))
            fflush(stdout)
        }
        receiver.scheduleOnCurrentRunLoop()
        try receiver.sendQuery(reports: UInt8(clamping: Int(interval)))
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            do {
                try receiver.sendQuery(reports: UInt8(clamping: Int(interval)))
            } catch {
                FileHandle.standardError.write(Data("solar: \(error)\n".utf8))
            }
        }
        CFRunLoopRun()
    }

    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
} catch {
    die(String(describing: error))
}
