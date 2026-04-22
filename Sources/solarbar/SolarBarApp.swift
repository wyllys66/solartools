// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Wyllys Ingersoll
//
// solarbar — menu bar widget showing the Logitech K750's solar charge and
// ambient-light readings as two circular gauges.
//
// Runs as an NSApplication.accessory (no dock icon) with a single
// MenuBarExtra. The menu bar label shows an SF Symbol battery glyph plus the
// current charge %; clicking opens a popover with larger gauges for charge
// (0-100%) and lux (0-500).
//
// The underlying HID++ transport is shared with solarcli via the SolarCore
// library.
//

import AppKit
import SwiftUI
import SolarCore

@main
struct SolarBarApp: App {
    @StateObject private var store = ReadingStore()

    init() {
        // No dock icon, no main menu — pure menu bar accessory.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            Label(store.menuBarTitle, systemImage: store.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
