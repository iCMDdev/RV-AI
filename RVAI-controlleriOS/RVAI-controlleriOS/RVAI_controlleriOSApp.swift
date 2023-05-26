//
//  RVAI_controlleriOSApp.swift
//  RVAI-controlleriOS
//
//  Created by Cristian-Mihai Dinca on 23.05.2023.
//

import SwiftUI

@main
struct RVAI_controlleriOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    appDelegate.registerForPushNotifications()
                }
        }
    }
}
