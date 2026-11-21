import AppKit
import Foundation
import UserNotifications

// brew-autoupdate notify <title> <subtitle> <message>
//   Posts a notification.
//
// brew-autoupdate run-updater <log> <launcher-pid>
//   Runs the generated updater script, appending its output to <log>. The
//   launch agent opens the app through LaunchServices for this, so macOS holds
//   this signed app, rather than Homebrew's portable Ruby, responsible for App
//   Management checks, and a single grant survives portable Ruby upgrades.

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list])
  }
}

let notificationDelegate = NotificationDelegate()
var dispatchSources: [DispatchSourceProtocol] = []

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("brew-autoupdate: \(message)\n".utf8))
  exit(1)
}

func notify(title: String, subtitle: String, message: String) {
  let application = NSApplication.shared
  application.setActivationPolicy(.accessory)

  let notificationCenter = UNUserNotificationCenter.current()
  notificationCenter.delegate = notificationDelegate

  notificationCenter.requestAuthorization(options: [.alert]) { granted, error in
    if let error {
      fail("could not request notification permission: \(error.localizedDescription)")
    }
    guard granted else {
      fail("notifications are disabled in System Settings")
    }

    let content = UNMutableNotificationContent()
    content.title = title
    content.subtitle = subtitle
    content.body = message

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    notificationCenter.add(request) { error in
      if let error {
        fail("could not deliver notification: \(error.localizedDescription)")
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        exit(0)
      }
    }
  }
}

// The updater runs with this app's App Management permission, so refuse
// anything another user could have replaced.
func requireOwnedByUser(_ path: String, type: FileAttributeType) {
  guard
    let attributes = try? FileManager.default.attributesOfItem(atPath: path),
    attributes[.type] as? FileAttributeType == type,
    (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
    let permissions = attributes[.posixPermissions] as? Int,
    permissions & 0o022 == 0
  else {
    fail("\(path) must be owned by you and not writable by others")
  }
}

func runUpdater(log: String, launcherPID: pid_t) {
  // The script path is fixed so the app cannot be used to run arbitrary
  // programs with its permissions.
  guard let home = getpwuid(getuid())?.pointee.pw_dir else {
    fail("could not determine the home directory")
  }
  let supportDirectory = "\(String(cString: home))/Library/Application Support/com.github.hybras.homebrew-autoupdate"
  let updater = "\(supportDirectory)/brew_autoupdate"
  requireOwnedByUser(supportDirectory, type: .typeDirectory)
  requireOwnedByUser(updater, type: .typeRegular)

  // Append, like launchd does, so concurrent writers never overwrite each other.
  let descriptor = open(log, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o644)
  guard descriptor >= 0 else {
    fail("could not open \(log): \(String(cString: strerror(errno)))")
  }
  let logHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

  // LaunchServices does not apply the launch agent's background priority to
  // apps it opens, so apply it to the updater explicitly.
  let updaterProcess = Process()
  updaterProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/taskpolicy")
  updaterProcess.arguments = ["-b", "/bin/sh", updater]
  updaterProcess.standardInput = FileHandle.nullDevice
  updaterProcess.standardOutput = logHandle
  updaterProcess.standardError = logHandle
  updaterProcess.terminationHandler = { process in
    let status = process.terminationStatus + (process.terminationReason == .uncaughtSignal ? 128 : 0)
    try? "\(status)\n".write(toFile: "\(supportDirectory)/brew_autoupdate.status", atomically: true, encoding: .utf8)
    exit(status)
  }

  do {
    try updaterProcess.run()
  } catch {
    fail("could not start the updater: \(error.localizedDescription)")
  }

  // Process starts the updater in its own process group. Stop the whole group
  // when this app is asked to quit or the launcher exits, e.g. on
  // `brew autoupdate stop`.
  let stopUpdater = { _ = kill(-updaterProcess.processIdentifier, SIGTERM) }
  signal(SIGTERM, SIG_IGN)
  let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
  terminationSource.setEventHandler(handler: stopUpdater)
  let launcherSource = DispatchSource.makeProcessSource(identifier: launcherPID, eventMask: .exit, queue: .main)
  launcherSource.setEventHandler(handler: stopUpdater)
  dispatchSources = [terminationSource, launcherSource]
  dispatchSources.forEach { $0.resume() }

  if kill(launcherPID, 0) != 0 {
    stopUpdater()
  }
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch (arguments.first, arguments.count) {
case ("notify", 4):
  notify(title: arguments[1], subtitle: arguments[2], message: arguments[3])
case ("run-updater", 3):
  guard let launcherPID = pid_t(arguments[2]), launcherPID > 0 else {
    fail("invalid launcher PID: \(arguments[2])")
  }
  runUpdater(log: arguments[1], launcherPID: launcherPID)
default:
  fail("usage: brew-autoupdate notify <title> <subtitle> <message>\n" +
       "       brew-autoupdate run-updater <log> <launcher-pid>")
}

RunLoop.main.run()
