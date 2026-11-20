import AppKit
import Darwin
import Foundation
import UserNotifications

// This app has two modes:
//
//   brew-autoupdate-notifier <title> <subtitle> <message>
//     Posts a single notification and exits.
//
//   brew-autoupdate-notifier --run-updater <log>
//     Runs the generated updater script and appends its output to <log>. The
//     launch agent opens the app in this mode through LaunchServices, which
//     makes this signed app, rather than Homebrew's portable Ruby, the process
//     macOS holds responsible for App Management checks. The grant therefore
//     survives portable Ruby upgrades.

let runUpdaterFlag = "--run-updater"
let supportDirectoryName = "com.github.domt4.homebrew-autoupdate"
let updaterScriptName = "brew_autoupdate"
let pidFileName = "brew_autoupdate.pid"
let statusFileName = "brew_autoupdate.status"

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("brew-autoupdate notifier: \(message)\n".utf8))
  exit(1)
}

// MARK: - Updater mode

func homeDirectory() -> String {
  guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
    fail("could not determine the home directory")
  }
  return String(cString: directory)
}

func errnoDescription() -> String {
  String(cString: strerror(errno))
}

/// Refuses paths that another user could have replaced. The updater script is
/// run with this app's App Management permission, so only the current user's
/// own, non-shared files are accepted.
func requireOwnedPath(_ path: String, isDirectory: Bool) {
  var info = stat()
  guard lstat(path, &info) == 0 else {
    fail("cannot inspect \(path): \(errnoDescription())")
  }
  let expectedType = isDirectory ? S_IFDIR : S_IFREG
  guard info.st_mode & S_IFMT == expectedType else {
    fail("\(path) is not a \(isDirectory ? "directory" : "regular file")")
  }
  guard info.st_uid == getuid() else {
    fail("\(path) is not owned by the current user")
  }
  guard info.st_mode & (S_IWGRP | S_IWOTH) == 0 else {
    fail("\(path) is writable by other users")
  }
}

func writeFile(_ path: String, _ contents: String) {
  do {
    try contents.write(toFile: path, atomically: true, encoding: .utf8)
  } catch {
    FileHandle.standardError.write(
      Data("brew-autoupdate notifier: could not write \(path): \(error.localizedDescription)\n".utf8)
    )
  }
}

func exitCode(fromWaitStatus status: Int32) -> Int32 {
  let signal = status & 0x7f
  if signal == 0 {
    return (status >> 8) & 0xff
  }
  return 128 + signal
}

func runUpdater(arguments: [String]) -> Never {
  guard arguments.count == 1, !arguments[0].isEmpty else {
    fail("expected \(runUpdaterFlag) <log>")
  }
  let logPath = arguments[0]

  // The script path is fixed rather than taken from the arguments, so the
  // app cannot be used to run arbitrary programs with its permissions.
  let supportDirectory = "\(homeDirectory())/Library/Application Support/\(supportDirectoryName)"
  let updaterScript = "\(supportDirectory)/\(updaterScriptName)"
  let pidFile = "\(supportDirectory)/\(pidFileName)"
  let statusFile = "\(supportDirectory)/\(statusFileName)"
  requireOwnedPath(supportDirectory, isDirectory: true)
  requireOwnedPath(updaterScript, isDirectory: false)

  let logDescriptor = open(logPath, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o644)
  guard logDescriptor >= 0 else {
    fail("cannot open \(logPath): \(errnoDescription())")
  }

  let application = NSApplication.shared
  application.setActivationPolicy(.accessory)

  let activity = ProcessInfo.processInfo.beginActivity(
    options: [.background, .suddenTerminationDisabled, .automaticTerminationDisabled],
    reason: "Running Homebrew autoupdate"
  )

  // Forward termination requests (e.g. `brew autoupdate stop`) to the whole
  // updater process group, then exit once it has finished.
  let forwardedSignals = [SIGTERM, SIGINT, SIGHUP]
  var defaultSignals = sigset_t()
  sigemptyset(&defaultSignals)
  for forwardedSignal in forwardedSignals {
    signal(forwardedSignal, SIG_IGN)
    sigaddset(&defaultSignals, forwardedSignal)
  }
  var emptyMask = sigset_t()
  sigemptyset(&emptyMask)

  var fileActions: posix_spawn_file_actions_t?
  posix_spawn_file_actions_init(&fileActions)
  posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
  posix_spawn_file_actions_adddup2(&fileActions, logDescriptor, STDOUT_FILENO)
  posix_spawn_file_actions_adddup2(&fileActions, logDescriptor, STDERR_FILENO)

  var attributes: posix_spawnattr_t?
  posix_spawnattr_init(&attributes)
  posix_spawnattr_setflags(
    &attributes,
    Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
  )
  posix_spawnattr_setpgroup(&attributes, 0)
  posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
  posix_spawnattr_setsigmask(&attributes, &emptyMask)

  // LaunchServices does not apply the launch agent's background priority to
  // apps it opens, so apply the same throttling to the updater explicitly.
  let childArguments = ["/usr/sbin/taskpolicy", "-b", "/bin/sh", updaterScript]
  var argv: [UnsafeMutablePointer<CChar>?] = childArguments.map { strdup($0) }
  argv.append(nil)

  var childPID: pid_t = 0
  let spawnResult = posix_spawn(&childPID, childArguments[0], &fileActions, &attributes, argv, environ)
  argv.forEach { free($0) }
  posix_spawn_file_actions_destroy(&fileActions)
  posix_spawnattr_destroy(&attributes)
  close(logDescriptor)
  guard spawnResult == 0 else {
    fail("could not start the updater: \(String(cString: strerror(spawnResult)))")
  }

  writeFile(pidFile, "\(getpid())\n")

  var signalSources: [DispatchSourceSignal] = []
  for forwardedSignal in forwardedSignals {
    let source = DispatchSource.makeSignalSource(signal: forwardedSignal, queue: .main)
    source.setEventHandler {
      kill(-childPID, SIGTERM)
    }
    source.resume()
    signalSources.append(source)
  }

  DispatchQueue.global(qos: .utility).async {
    var waitStatus: Int32 = 0
    while waitpid(childPID, &waitStatus, 0) == -1 && errno == EINTR {}
    let code = exitCode(fromWaitStatus: waitStatus)

    DispatchQueue.main.async {
      signalSources.forEach { $0.cancel() }
      writeFile(statusFile, "\(code)\n")
      unlink(pidFile)
      ProcessInfo.processInfo.endActivity(activity)
      exit(code)
    }
  }

  RunLoop.main.run()
  fail("the run loop exited unexpectedly")
}

// MARK: - Notification mode

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list])
  }
}

func postNotification(title: String, subtitle: String, message: String) -> Never {
  let application = NSApplication.shared
  application.setActivationPolicy(.accessory)

  let notificationCenter = UNUserNotificationCenter.current()
  let notificationDelegate = NotificationDelegate()
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

  RunLoop.main.run()
  fail("the run loop exited unexpectedly")
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == runUpdaterFlag {
  runUpdater(arguments: Array(arguments.dropFirst()))
}

guard arguments.count == 3 else {
  fail("expected a title, subtitle, and message, or \(runUpdaterFlag) <log>")
}

postNotification(title: arguments[0], subtitle: arguments[1], message: arguments[2])
