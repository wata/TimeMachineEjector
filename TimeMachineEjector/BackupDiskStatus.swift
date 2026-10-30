//
//  BackupDiskStatus.swift
//  TimeMachineEjector
//

import Foundation

enum BackupDiskStatus: Equatable {
    case noDestination
    case startingBackup
    case backingUp(progress: Int)
    case connected
    case ejected
    case ejectFailed
    case notConnected

    /// `volume` は宛先のボリュームの diskutil info。ディスクが見つからなければ nil。
    /// `isStartingBackup` は Back Up Now を押してから backupd が Running になるまでの間。マウントと準備に数秒かかる。
    /// `lastProgress` は直前に表示していた進捗。準備中やコピー後の片付けは backupd が進捗を出さないので、0% から始めてその値を保つ。
    init(destination: TimeMachine.Destination?, status: TimeMachine.Status?, volume: Disk.Info?, didFailToEject: Bool, isStartingBackup: Bool = false, lastProgress: Int? = nil) {
        guard destination != nil else {
            self = .noDestination
            return
        }
        if let status, status.isRunning {
            self = .backingUp(progress: status.progress ?? lastProgress ?? 0)
            return
        }
        guard !isStartingBackup else {
            self = .startingBackup
            return
        }
        guard let volume else {
            self = .notConnected
            return
        }
        guard volume.isMounted else {
            self = .ejected
            return
        }
        self = didFailToEject ? .ejectFailed : .connected
    }

    var canStartBackup: Bool {
        switch self {
        case .connected, .ejected, .ejectFailed:
            true
        case .noDestination, .startingBackup, .backingUp, .notConnected:
            false
        }
    }

    var progress: Int? {
        guard case .backingUp(let progress) = self else { return nil }
        return progress
    }

    func title(destinationName: String?) -> String {
        guard let destinationName, self != .noDestination else { return "No Backup Disk" }
        return "\(destinationName): \(description)"
    }

    private var description: String {
        switch self {
        case .noDestination:
            "No Backup Disk"
        case .startingBackup:
            "Starting Backup…"
        case .backingUp(let progress):
            "Backing Up… \(progress)%"
        case .connected:
            "Connected"
        case .ejected:
            "Ejected"
        case .ejectFailed:
            "Couldn't Eject"
        case .notConnected:
            "Not Connected"
        }
    }
}
