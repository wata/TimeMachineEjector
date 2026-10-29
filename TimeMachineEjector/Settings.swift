//
//  Settings.swift
//  TimeMachineEjector
//
//  Created by Wataru Nagasawa on 2021/10/12.
//

import Foundation
import os
import ServiceManagement

enum Settings {
    static var isDisabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: .isDisabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: .isDisabled)
        }
    }

    /// アンマウント中や再起動後でもディスクを特定できるよう、マウント中に取った VolumeUUID を宛先 ID ごとに覚えておく。
    static var volumeUUIDs: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: .volumeUUIDs) as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: .volumeUUIDs)
        }
    }

    static var isLaunchAtLoginEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Logger.app.error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

fileprivate extension String {
    static let isDisabled = "isDisabled"
    static let volumeUUIDs = "volumeUUIDs"
}
