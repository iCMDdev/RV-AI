//
//  AppDelegate.swift
//  RVAI-controlleriOS
//
//  Created by Cristian-Mihai Dinca on 25.05.2023.
//

import Foundation
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                      didFinishLaunchingWithOptions launchOptions:
                     [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
      // Override point for customization after application launch.
          
      return true
   }

   func application(_ application: UIApplication,
               didRegisterForRemoteNotificationsWithDeviceToken
                   deviceToken: Data) {
       let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
       let token = tokenParts.joined()
       print("Got device token: \(token)")
   }

   func application(_ application: UIApplication,
               didFailToRegisterForRemoteNotificationsWithError
                   error: Error) {
      // Try again later.
      print("Try again later.")
   }
    
    
    func registerForPushNotifications() {
      //1
      UNUserNotificationCenter.current()
        //2
        .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          //3guard settings.authorizationStatus == .authorized else { return }
            DispatchQueue.main.async {
              UIApplication.shared.registerForRemoteNotifications()
            }

          print("Permission granted: \(granted)")
        }
    }
}
