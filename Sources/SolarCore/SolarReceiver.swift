// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Wyllys Ingersoll
//
// SolarCore — shared HID++ access layer for the Logitech K750.
//
// The K750 is a solar-powered wireless keyboard that talks to a host through
// a Logitech Unifying Receiver (USB VID 0x046d, PID 0xc52b). It reports
// battery charge and ambient light over Logitech's vendor-specific HID++
// protocol. This module wraps the IOKit HID Manager plumbing so both the
// `solarcli` command-line tool and the `solarbar` menu bar app can share the
// same transport.
//
// See Sources/solarcli/main.swift for a longer description of the HID++
// query/response flow.
//

import Foundation
import IOKit.hid

// MARK: - Protocol constants

public let logitechVendorID      = 0x046d
public let unifyingProductID     = 0xc52b
public let hidppUsagePage        = 0xFF00

public let hidppShortReportID: UInt8 = 0x10   // 7-byte outgoing report
public let hidppLongReportID:  UInt8 = 0x11   // 20-byte incoming report
public let solarSubID:         UInt8 = 0x0b
public let solarResponseAddr:  UInt8 = 0x20   // echo-ack from the receiver
public let solarRequestAddr:   UInt8 = 0x03   // request address
public let solarBroadcastAddr: UInt8 = 0x10   // periodic broadcast from the keyboard

// Full HID++ short request, including the leading report ID byte.
public let solarRequestReport: [UInt8] = [0x10, 0x01, 0x09, 0x03, 0x78, 0x01, 0x00]

// MARK: - Public types

public struct Reading: Sendable, Equatable {
    public let charge: Int
    public let lux: Int
    public let timestamp: Date

    public init(charge: Int, lux: Int, timestamp: Date = Date()) {
        self.charge = charge
        self.lux = lux
        self.timestamp = timestamp
    }
}

public enum SolarError: Error, CustomStringConvertible {
    case noReceiverFound
    case openFailed(IOReturn)
    case setReportFailed(IOReturn)
    case timedOut

    public var description: String {
        switch self {
        case .noReceiverFound:
            return "no Logitech Unifying Receiver (046d:c52b) with a HID++ collection found"
        case .openFailed(let r):
            return "IOHIDDeviceOpen failed (0x\(String(r, radix: 16))); try granting Input Monitoring permission"
        case .setReportFailed(let r):
            return "IOHIDDeviceSetReport failed (0x\(String(r, radix: 16)))"
        case .timedOut:
            return "timed out waiting for a response (is the K750 paired and in range?)"
        }
    }
}

// MARK: - Receiver

public final class SolarReceiver {
    public let device: IOHIDDevice
    private let bufferSize = 64
    private let buffer: UnsafeMutablePointer<UInt8>
    public var onReading: ((Reading) -> Void)?
    public var debug: Bool = false

    public init(device: IOHIDDevice) {
        self.device = device
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        self.buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit {
        buffer.deinitialize(count: bufferSize)
        buffer.deallocate()
    }

    public func scheduleOnCurrentRunLoop() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, bufferSize,
            { context, _, _, _, reportID, report, length in
                guard let context = context else { return }
                let me = Unmanaged<SolarReceiver>.fromOpaque(context).takeUnretainedValue()
                me.handle(reportID: reportID, report: report, length: length)
            },
            context
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    public func sendQuery() throws {
        let result = solarRequestReport.withUnsafeBufferPointer { ptr -> IOReturn in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(hidppShortReportID),
                ptr.baseAddress!,
                ptr.count
            )
        }
        if result != kIOReturnSuccess {
            throw SolarError.setReportFailed(result)
        }
    }

    private func handle(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        if debug {
            var hex = ""
            for i in 0..<length { hex += String(format: "%02x ", report[i]) }
            FileHandle.standardError.write(Data("[hid in] id=0x\(String(reportID, radix: 16)) len=\(length) data: \(hex)\n".utf8))
        }
        // macOS delivers the input buffer with the report ID as the first byte.
        // Long response layout: [0x11, deviceIdx, subID, addr, charge, lux_hi, lux_lo, ...]
        guard reportID == UInt32(hidppLongReportID), length >= 7 else { return }
        guard report[0] == hidppLongReportID else { return }
        guard report[2] == solarSubID else { return }

        // 0x20 is triggered by pressing the test button on the K750 keyboard.
        // 0x10 is automatically broadcast.
        let addrs = [solarResponseAddr, solarBroadcastAddr]
        guard addrs.contains(report[3]) else { return }

        let charge = Int(report[4])
        let lux = Int(report[5]) << 8 + Int(report[6])
        onReading?(Reading(charge: charge, lux: lux))
    }
}

// MARK: - Device lookup

public func findReceivers() -> [IOHIDDevice] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let match: [String: Any] = [
        kIOHIDVendorIDKey:         logitechVendorID,
        kIOHIDProductIDKey:        unifyingProductID,
        kIOHIDPrimaryUsagePageKey: hidppUsagePage,
    ]
    IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
    guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
    return (set as NSSet).allObjects.map { $0 as! IOHIDDevice }
}

public func openReceiver() throws -> IOHIDDevice {
    guard let device = findReceivers().first else { throw SolarError.noReceiverFound }

    // Seize the vendor-defined HID++ collection (usage page 0xFF00). It
    // doesn't carry keyboard/mouse events, so seizing doesn't affect user
    // input but lets us SetReport/GetReport without fighting the default
    // HID driver.
    var result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    if result != kIOReturnSuccess {
        result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }
    if result != kIOReturnSuccess { throw SolarError.openFailed(result) }
    return device
}
