//
//  PiaKeys_iOSApp.swift
//  PiaKeys_iOS
//
//  Created by Ho Ngoc Dung on 13/7/26.
//

import SwiftUI
import UIKit

@main
struct PiaKeys_iOSApp: App {
    @UIApplicationDelegateAdaptor(PiaKeysAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@MainActor
final class PiaKeysAppDelegate: NSObject, UIApplicationDelegate {
    static var supportedOrientations: UIInterfaceOrientationMask = .allButUpsideDown

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }
}
