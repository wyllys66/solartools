// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Wyllys Ingersoll
//
// ReadingStore — owns the IOHIDDevice + SolarReceiver for the menu bar app and
// republishes incoming readings to SwiftUI.
//
// The receiver is scheduled on the main run loop (the SwiftUI app's run loop),
// so input-report callbacks fire on main and can update @Published state
// directly. A repeating Timer re-sends the solar-charge query every
// `pollInterval` seconds, since the K750's broadcasts are sporadic and a
// freshly-opened session may not see one for a while.
//

import Foundation
import Combine
import IOKit.hid
import SolarCore

final class ReadingStore: ObservableObject {
    @Published private(set) var reading: Reading?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdate: Date?

    // Poll every 60s in case the keyboard's broadcast doesn't arrive
    // organically. Matches solarcli's default monitor interval.
    private let pollInterval: TimeInterval = 60

    private var device: IOHIDDevice?
    private var receiver: SolarReceiver?
    private var pollTimer: Timer?

    init() {
        start()
    }

    deinit {
        pollTimer?.invalidate()
        if let device = device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    // MARK: - Menu bar rendering helpers

    var menuBarTitle: String {
        if let r = reading { return "\(r.charge)%" }
        return "--"
    }

    var menuBarSymbol: String {
        guard let c = reading?.charge else { return "battery.0" }
        switch c {
        case ..<13:  return "battery.0"
        case ..<38:  return "battery.25"
        case ..<63:  return "battery.50"
        case ..<88:  return "battery.75"
        default:     return "battery.100"
        }
    }

    // MARK: - Actions

    func refresh() {
        do {
            try receiver?.sendQuery(reports: UInt8(clamping: Int(pollInterval)))
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Setup

    private func start() {
        do {
            let dev = try openReceiver()
            let rx = SolarReceiver(device: dev)
            rx.onReading = { [weak self] r in
                // Callback fires on whatever thread the run loop is serviced
                // on; we scheduled on main, but marshal anyway for safety.
                DispatchQueue.main.async {
                    self?.reading = r
                    self?.lastUpdate = Date()
                    self?.errorMessage = nil
                }
            }
            rx.scheduleOnCurrentRunLoop()
            self.device = dev
            self.receiver = rx

            try rx.sendQuery(reports: UInt8(clamping: Int(pollInterval)))

            pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        } catch {
            self.errorMessage = String(describing: error)
        }
    }
}
