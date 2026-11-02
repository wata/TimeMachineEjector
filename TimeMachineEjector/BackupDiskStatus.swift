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
    /// `isStartingBackup` は Back Up Now かスケジュールでバックアップを始めてから backupd が Running になるまでの間。マウントと準備に数秒かかる。
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

    /// 抜いてはいけない間。メニューバーのアイコンを切り替え、終わるまでメニューを閉じていても読み直す。
    var isBackupInProgress: Bool {
        switch self {
        case .startingBackup, .backingUp:
            true
        case .noDestination, .connected, .ejected, .ejectFailed, .notConnected:
            false
        }
    }

    /// メニューバーのアイコン（SF Symbols）。形ごと変えると変化に気づきにくいので、普段も同じディスクにしておき、バックアップ中は Time Machine のバッジが付くことだけで見分けられるようにする。
    var symbolName: String {
        isBackupInProgress ? "externaldrive.fill.badge.timemachine" : "externaldrive.fill"
    }

    var progress: Int? {
        guard case .backingUp(let progress) = self else {
            return nil
        }
        return progress
    }

    func title(destinationName: String?) -> String {
        guard let destinationName, self != .noDestination else {
            return "No Backup Disk"
        }
        return "\(destinationName): \(description)"
    }

    /// Time Machine 自身のメニューと同じ書き方にする（今日・昨日は相対表記）。
    static func latestBackupTitle(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return "Latest Backup: \(formatter.string(from: date))"
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
