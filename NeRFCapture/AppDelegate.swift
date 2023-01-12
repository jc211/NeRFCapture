//
//  AppDelegate.swift
//  NeRFCapture
//
//  Created by Jad Abou-Chakra on 13/7/2022.
//

import UIKit
import SwiftUI

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var view: ContentView?
    
    var appSettings = AppSettings()
    var datasetWriter = DatasetWriter()
    var ddsWriter = DDSWriter()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Create the SwiftUI view that provides the window contents.
        let viewModel = ARViewModel(datasetWriter: datasetWriter, ddsWriter: ddsWriter)
        let contentView = ContentView(viewModel: viewModel)

        // Use a UIHostingController as window root view controller.
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        self.view = contentView
        window.makeKeyAndVisible()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        datasetWriter.clean()
        saveSettings()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        datasetWriter.clean()
        saveSettings()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }
    

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    
    func saveSettings() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(appSettings) {
            UserDefaults.standard.set(data, forKey: "appSettings")
        }
    }
    
    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "appSettings") {
            do {
                let decoder = JSONDecoder()
                appSettings = try decoder.decode(AppSettings.self, from: data)
            } catch {
                appSettings = AppSettings()
            }
        }
    }


}

