//
//  Disk.swift
//  TimeMachineEjector
//

import Foundation
import os

enum Disk {
    struct Info: Decodable, Equatable {
        struct PhysicalStore: Decodable, Equatable {
            let deviceIdentifier: String

            enum CodingKeys: String, CodingKey {
                case deviceIdentifier = "APFSPhysicalStore"
            }
        }

        let parentWholeDisk: String
        let volumeUUID: String?
        /// アンマウント中のボリュームでは空文字になる。
        let mountPoint: String?
        let physicalStores: [PhysicalStore]?

        enum CodingKeys: String, CodingKey {
            case parentWholeDisk = "ParentWholeDisk"
            case volumeUUID = "VolumeUUID"
            case mountPoint = "MountPoint"
            case physicalStores = "APFSPhysicalStores"
        }

        var isMounted: Bool {
            guard let mountPoint else { return false }
            return !mountPoint.isEmpty
        }
    }

    static func parseInfo(_ data: Data) -> Info? {
        try? PropertyListDecoder().decode(Info.self, from: data)
    }

    /// `target` はマウントポイント・ボリューム UUID・デバイス識別子のいずれでもよい。
    /// UUID ならアンマウント中でも、ディスクが接続されていれば情報が返る。
    static func info(for target: String) async -> Info? {
        guard let result = await Command.diskutil("info", "-plist", target), result.isSuccess else { return nil }
        return parseInfo(result.output)
    }

    /// APFS のボリュームの ParentWholeDisk は合成されたコンテナなので、物理ストアをたどって実ディスクを求める。
    /// 実ディスクごとアンマウントすれば、Finder の取り出しと同じく同じディスク上の他のボリュームも外れる。
    static func physicalWholeDisk(of info: Info) async -> String {
        guard
            let store = info.physicalStores?.first,
            let storeInfo = await self.info(for: store.deviceIdentifier)
        else { return info.parentWholeDisk }
        return storeInfo.parentWholeDisk
    }

    /// 物理的な取り出しはしない。ディスクを挿したままにしておけば Back Up Now でマウントし直せるため。
    static func unmountDisk(_ wholeDisk: String) async -> Bool {
        guard let result = await Command.diskutil("unmountDisk", wholeDisk) else { return false }
        if !result.isSuccess {
            Logger.app.error("diskutil unmountDisk \(wholeDisk, privacy: .public) failed (\(result.exitStatus)): \(result.errorOutput, privacy: .public)")
        }
        return result.isSuccess
    }

    static func mount(_ volumeUUID: String) async -> Bool {
        guard let result = await Command.diskutil("mount", volumeUUID) else { return false }
        if !result.isSuccess {
            Logger.app.error("diskutil mount \(volumeUUID, privacy: .public) failed (\(result.exitStatus)): \(result.errorOutput, privacy: .public)")
        }
        return result.isSuccess
    }
}
