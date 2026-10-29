//
//  BackupMonitor.swift
//  TimeMachineEjector
//

import Foundation
import os

/// NewSystemBackupAvailable の時点では backupd がまだ後片付け（thinning）を続けているので、
/// `tmutil status` の Running が落ちるまで待ってから完了を知らせる。
/// 片付けの通知は回数が一定しないため数えない。
final class BackupMonitor {
    private static let pollInterval: Duration = .seconds(5)

    private var observer: NSObjectProtocol?
    private var waitTask: Task<Void, Never>?

    func start(onFinish: @escaping @MainActor (_ machineStorePath: String) async -> Void) {
        stop()
        observer = DistributedNotificationCenter.default().addObserver(forName: .newSystemBackupAvailable, object: nil, queue: .main) { [weak self] notification in
            guard
                let self,
                let path = notification.userInfo?["MachineStorePath"] as? String
            else { return }
            Logger.app.info("New backup available on \(path, privacy: .public). Waiting for backupd to finish.")
            waitTask?.cancel()
            waitTask = Task { @MainActor in
                await Self.waitUntilIdle()
                guard !Task.isCancelled else { return }
                Logger.app.info("Backup finished on \(path, privacy: .public)")
                await onFinish(path)
            }
        }
    }

    func stop() {
        waitTask?.cancel()
        waitTask = nil
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
    }

    deinit {
        stop()
    }

    private static func waitUntilIdle() async {
        while !Task.isCancelled {
            let status = await TimeMachine.status()
            if status?.isRunning == false {
                return
            }
            // 読めないときに取り出すとバックアップ中のディスクを外しかねないので、読めるまで待ち続ける
            if status == nil {
                Logger.app.error("Couldn't read tmutil status")
            }
            try? await Task.sleep(for: pollInterval)
        }
    }
}

private extension Notification.Name {
    static let newSystemBackupAvailable = Notification.Name("com.apple.backupd.NewSystemBackupAvailableNotification")
}
