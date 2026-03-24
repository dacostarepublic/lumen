import Foundation
import AppKit
import ArgumentParser
import LumenCore

struct Daemon: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run continuous wallpaper rotation with space-change and wake handling"
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Run one update cycle and exit")
    var once: Bool = false

    mutating func run() throws {
        let runtime = try DaemonRuntime(
            configPath: global.config,
            jsonOutput: global.json,
            verboseOutput: global.verbose
        )

        if once {
            let hadFailures = try runtime.runRotationOnce(trigger: "once")
            if hadFailures {
                throw ExitCode.failure
            }
            return
        }

        try runtime.start()
        dispatchMain()
    }
}

private final class DaemonRuntime {
    private let configPath: String?
    private let jsonOutput: Bool
    private let verboseOutput: Bool

    private let config: LumenConfig
    private let stateManager: StateManager

    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    init(configPath: String?, jsonOutput: Bool, verboseOutput: Bool) throws {
        self.configPath = configPath
        self.jsonOutput = jsonOutput
        self.verboseOutput = verboseOutput

        self.config = try loadConfig(configPath)
        self.stateManager = try StateManager(config: config)
    }

    func start() throws {
        _ = try runRotationOnce(trigger: "startup")
        installObservers()
        installTimer()

        if !jsonOutput {
            print("Daemon running (interval: \(config.interval) minute\(config.interval == 1 ? "" : "s"))")
        }
    }

    func runRotationOnce(trigger: String) throws -> Bool {
        let results = try performUpdateCycle(
            config: config,
            stateManager: stateManager,
            updateAll: true,
            dryRun: false,
            verbose: verboseOutput,
            json: jsonOutput
        )

        let hadFailures = results.contains { !$0.success }

        if jsonOutput {
            emitRotationEvent(trigger: trigger, results: results)
        } else {
            let successful = results.filter { $0.success }.count
            print("[\(trigger)] Rotated \(successful)/\(results.count) screens")
            if hadFailures {
                for result in results where !result.success {
                    printError("  [\(result.screenIndex)] \(result.screenName): \(result.error ?? "Unknown error")")
                }
            }
        }

        return hadFailures
    }

    private func installTimer() {
        let intervalSeconds = TimeInterval(config.interval * 60)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.handleTimerTick()
        }
        timer.resume()
        self.timer = timer
    }

    private func installObservers() {
        let center = NSWorkspace.shared.notificationCenter

        let spaceObserver = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleReapply(trigger: "space-change")
        }

        let wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleReapply(trigger: "wake")
        }

        observers = [spaceObserver, wakeObserver]
    }

    private func handleTimerTick() {
        do {
            _ = try runRotationOnce(trigger: "timer")
        } catch {
            if jsonOutput {
                emitErrorEvent(trigger: "timer", error: String(describing: error))
            } else {
                printError("[timer] Rotation failed: \(error)")
            }
        }
    }

    private func handleReapply(trigger: String) {
        let results = reapplyCurrentWallpapers()

        if jsonOutput {
            emitReapplyEvent(trigger: trigger, results: results)
        } else if verboseOutput {
            let successCount = results.filter { $0.success }.count
            print("[\(trigger)] Reapplied \(successCount)/\(results.count) screens")
            for result in results where !result.success {
                printError("  [\(result.screenIndex)] \(result.screenName): \(result.error ?? "Unknown error")")
            }
        }
    }

    private func reapplyCurrentWallpapers() -> [ReapplyResult] {
        do {
            try stateManager.refresh()
        } catch {
            if jsonOutput {
                emitErrorEvent(trigger: "reapply-refresh", error: String(describing: error))
            } else {
                printError("Failed to refresh state before reapply: \(error)")
            }
        }

        let monitors = MonitorManager.getMonitors()
        let trackedIds = Swift.Set(stateManager.getState().screens.keys)
        let targetMonitors = trackedIds.isEmpty ? monitors : monitors.filter { trackedIds.contains($0.id) }

        var results: [ReapplyResult] = []

        for monitor in targetMonitors {
            let fitStyle = config.fitStyleForScreen(monitor.id)

            guard let currentPath = stateManager.getCurrentWallpaper(for: monitor.id) else {
                results.append(ReapplyResult(
                    screenIndex: monitor.index,
                    screenId: monitor.id,
                    screenName: monitor.name,
                    imagePath: nil,
                    success: false,
                    error: "No current wallpaper in state"
                ))
                continue
            }

            do {
                try MonitorManager.setWallpaper(
                    for: monitor.id,
                    imagePath: currentPath,
                    fitStyle: fitStyle,
                    syncAllSpaces: config.applyAllSpaces
                )
                results.append(ReapplyResult(
                    screenIndex: monitor.index,
                    screenId: monitor.id,
                    screenName: monitor.name,
                    imagePath: currentPath,
                    success: true,
                    error: nil
                ))
            } catch {
                results.append(ReapplyResult(
                    screenIndex: monitor.index,
                    screenId: monitor.id,
                    screenName: monitor.name,
                    imagePath: currentPath,
                    success: false,
                    error: String(describing: error)
                ))
            }
        }

        return results
    }

    private func emitRotationEvent(trigger: String, results: [UpdateResult]) {
        emitJSON(DaemonRotationEvent(trigger: trigger, timestamp: Date(), results: results))
    }

    private func emitReapplyEvent(trigger: String, results: [ReapplyResult]) {
        emitJSON(DaemonReapplyEvent(trigger: trigger, timestamp: Date(), results: results))
    }

    private func emitErrorEvent(trigger: String, error: String) {
        emitJSON(DaemonErrorEvent(trigger: trigger, timestamp: Date(), error: error))
    }

    private func emitJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        do {
            let data = try encoder.encode(value)
            if let line = String(data: data, encoding: .utf8) {
                print(line)
            }
        } catch {
            printError("Failed to encode daemon event JSON: \(error)")
        }
    }
}

private struct ReapplyResult: Encodable {
    let screenIndex: Int
    let screenId: String
    let screenName: String
    let imagePath: String?
    let success: Bool
    let error: String?
}

private struct DaemonRotationEvent: Encodable {
    let event: String = "rotation"
    let trigger: String
    let timestamp: Date
    let results: [UpdateResult]
}

private struct DaemonReapplyEvent: Encodable {
    let event: String = "reapply"
    let trigger: String
    let timestamp: Date
    let results: [ReapplyResult]
}

private struct DaemonErrorEvent: Encodable {
    let event: String = "error"
    let trigger: String
    let timestamp: Date
    let error: String
}
