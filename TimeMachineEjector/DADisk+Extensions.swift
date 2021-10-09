//
//  DADisk+Extensions.swift
//  TimeMachineEjector
//
//  Created by Wataru Nagasawa on 2021/10/13.
//

import Foundation

extension DADisk {
    func isDiskImage() -> Bool {
        guard let description = DADiskCopyDescription(self) as NSDictionary? else {
            return false
        }
        guard let deviceModel = description[kDADiskDescriptionDeviceModelKey] as? String else {
            return false
        }
        if deviceModel == "Disk Image" {
            return true
        } else {
            return false
        }
    }
}
