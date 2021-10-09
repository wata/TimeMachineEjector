//
//  AppDelegate.swift
//  TimeMachineEjector
//
//  Created by Wataru Nagasawa on 2021/10/04.
//

import Cocoa
import BackupMonitor

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private let backupMonitor = BackupMonitor()
    private lazy var statusItem: NSStatusItem = {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(named: "Icon")!
        image.size = .init(width: 16, height: 16)
        image.isTemplate = true
        statusItem.button?.image = image
        return statusItem
    }()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        start()
    }

    private func start() {
        stop()

        setupMenu()

        guard !Settings.isDisabled else { return }

        backupMonitor.delegate = self
        backupMonitor.start()
    }

    private func stop() {
        backupMonitor.delegate = nil
        backupMonitor.stop()
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: "Disable", selector: #selector(AppDelegate.toggleDisable(_:)), isEnabled: Settings.isDisabled))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Mount and Backup", selector: #selector(AppDelegate.mountAndBackup(_:))))
        menu.addItem(.separator())
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        menu.addItem(makeMenuItem(title: "About \(name) \(version)", selector: #selector(AppDelegate.openGitHub(_:))))
        menu.addItem(makeMenuItem(title: "Quit", selector: #selector(AppDelegate.quit(_:))))
        statusItem.menu = menu
    }

    private func makeMenuItem(title: String, selector: Selector?, target: AnyObject? = nil, isEnabled: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        if let target = target {
            item.target = target
        }
        if let isEnabled = isEnabled {
            item.state = isEnabled ? .on : .off
        }
        return item
    }

    @objc private func toggleDisable(_ sender: NSButton) {
        Settings.isDisabled = !Settings.isDisabled
        Settings.isDisabled ? stop() : start()
        sender.state = Settings.isDisabled ? .on : .off
    }

    @objc private func mountAndBackup(_ sender: NSButton) {
    }

    @objc private func openGitHub(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "https://github.com/wata/TimeMachineEjector")!)
    }

    @objc private func quit(_ sender: NSButton) {
        NSApplication.shared.terminate(self)
    }
}

extension AppDelegate: BackupMonitorDelegate {
    func backupMonitor(_ monitor: BackupMonitor, backupStarted destinationMountPoint: String) {
    }

    func backupMonitor(_ monitor: BackupMonitor, backupEnded latestBackupPath: String) {
    }

    func backupMonitor(_ monitor: BackupMonitor, backupCleaningUpStarted backupPath: String) {
    }

    func backupMonitor(_ monitor: BackupMonitor, backupCleaningUpEnded backupPath: String, error: Int) {
    }
}
