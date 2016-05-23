//
//  AppDelegate.swift
//  Radon
//
//  Created by mhaddl on 01/11/15.
//  Copyright © 2015 Martin Hartl. All rights reserved.
//

import UIKit
import CloudKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        
        let notificationSettings = UIUserNotificationSettings(forTypes: .None, categories: nil)
        application.registerUserNotificationSettings(notificationSettings)
        application.registerForRemoteNotifications()
        
        return true
    }
    
    func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject]) {
        
        guard let userInfo = userInfo as? [String:NSObject] else {
            return
        }
        
        let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        if cloudKitNotification.notificationType == .Query {
            if let queryNotification = cloudKitNotification as? CKQueryNotification {
                TestClassRadon.radon.handleQueryNotification(queryNotification)
            }
        }
    }
}

