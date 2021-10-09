//
//  Settings.swift
//  TimeMachineEjector
//
//  Created by Wataru Nagasawa on 2021/10/12.
//

import Foundation

struct Settings {
    static var isDisabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: .isDisabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: .isDisabled)
        }
    }
}

fileprivate extension String {
    static let isDisabled = "isDisabled"
}
