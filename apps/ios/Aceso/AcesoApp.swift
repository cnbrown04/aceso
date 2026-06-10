//
//  AcesoApp.swift
//  Aceso
//
//  Created by Caleb Brown on 6/10/26.
//

import SwiftUI

@main
struct AcesoApp: App {
    init() {
        AddonLoader.shared.activateAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
