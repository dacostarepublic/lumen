import Foundation
import ArgumentParser
import LumenCore

// MARK: - Main Entry Point

@main
struct Lumen: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lumen",
        abstract: "A terminal-first wallpaper manager for macOS",
        discussion: """
            Lumen rotates wallpapers from local folders with support for multiple monitors,
            rotation modes, history, favorites, and blacklisting.
            
            Configuration is stored in ~/.lumen-config (JSON format).
            Run 'lumen config init' to create a default configuration.
            """,
        version: "1.0.0",
        subcommands: [
            Update.self,
            Set.self,
            Status.self,
            Prev.self,
            Favorite.self,
            Ban.self,
            Config.self,
            History.self,
            List.self
        ],
        defaultSubcommand: Status.self
    )
}

// MARK: - Shared Options

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Path to configuration file")
    var config: String?
    
    @Flag(name: .long, help: "Output in JSON format")
    var json: Bool = false
    
    @Flag(name: [.short, .long], help: "Verbose output")
    var verbose: Bool = false
}

struct ScreenSelector: ParsableArguments {
    @Option(name: .long, help: "Screen index (1-based)")
    var screen: Int?
    
    @Option(name: .long, help: "Screen ID (stable identifier)")
    var screenId: String?
    
    /// Resolve to a MonitorInfo
    func resolveMonitor() throws -> MonitorInfo {
        let monitors = MonitorManager.getMonitors()
        
        if monitors.isEmpty {
            throw MonitorError.noMonitorsFound
        }
        
        if let id = screenId {
            guard let monitor = MonitorManager.findMonitor(byId: id) else {
                throw MonitorError.monitorNotFound(id: id)
            }
            return monitor
        }
        
        if let index = screen {
            guard let monitor = MonitorManager.findMonitor(byIndex: index) else {
                throw MonitorError.monitorNotFoundByIndex(index)
            }
            return monitor
        }
        
        // Default to main display
        guard let main = monitors.first(where: { $0.isMain }) ?? monitors.first else {
            throw MonitorError.noMonitorsFound
        }
        return main
    }
    
    /// Check if any screen was specified
    var hasSelection: Bool {
        return screen != nil || screenId != nil
    }
}

// MARK: - Update Command

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Update wallpaper(s) according to configuration"
    )
    
    @OptionGroup var global: GlobalOptions
    @OptionGroup var screenSelector: ScreenSelector
    
    @Flag(name: .long, help: "Show what would be done without applying changes")
    var dryRun: Bool = false
    
    @Flag(name: .long, help: "Update all screens")
    var all: Bool = false
    
    mutating func run() throws {
        let config = try loadConfig(global.config)
        let stateManager = try StateManager(config: config)
        let selector = ImageSelector(config: config, stateManager: stateManager)
        
        let monitors = MonitorManager.getMonitors()
        if monitors.isEmpty {
            throw MonitorError.noMonitorsFound
        }
        
        var results: [UpdateResult] = []
        
        // Determine which screens to update
        let screensToUpdate: [MonitorInfo]
        if all || !screenSelector.hasSelection {
            screensToUpdate = monitors
        } else {
            screensToUpdate = [try screenSelector.resolveMonitor()]
        }
        
        // Track already-selected images to ensure different wallpapers per screen
        var alreadySelected = Swift.Set<String>()
        
        for monitor in screensToUpdate {
            do {
                // Pass already-selected images to exclude them from selection
                let selected = try selector.selectNext(for: monitor.id, excluding: alreadySelected, dryRun: dryRun)
                let fitStyle = config.fitStyleForScreen(monitor.id)
                
                // Add to exclusion set for subsequent screens
                alreadySelected.insert(selected)
                
                if !dryRun {
                    try MonitorManager.setWallpaper(for: monitor.id, imagePath: selected, fitStyle: fitStyle)
                    try stateManager.recordWallpaperChange(screenId: monitor.id, path: selected)
                }
                
                results.append(UpdateResult(
                    screenIndex: monitor.index,
                    screenId: monitor.id,
                    screenName: monitor.name,
                    imagePath: selected,
                    fitStyle: fitStyle,
                    success: true,
                    error: nil
                ))
                
                if global.verbose && !global.json {
                    print("[\(monitor.index)] \(monitor.name): \(selected)")
                }
            } catch {
                results.append(UpdateResult(
                    screenIndex: monitor.index,
                    screenId: monitor.id,
                    screenName: monitor.name,
                    imagePath: nil,
                    fitStyle: config.fitStyleForScreen(monitor.id),
                    success: false,
                    error: String(describing: error)
                ))
            }
        }
        
        if global.json {
            let output = UpdateOutput(dryRun: dryRun, results: results)
            print(try output.toJSON())
        } else if !global.verbose {
            let successCount = results.filter { $0.success }.count
            let dryRunPrefix = dryRun ? "[dry-run] " : ""
            if results.count == 1 {
                if let result = results.first, result.success {
                    print("\(dryRunPrefix)Updated \(result.screenName): \((result.imagePath! as NSString).lastPathComponent)")
                } else if let result = results.first {
                    printError("Failed to update \(result.screenName): \(result.error ?? "Unknown error")")
                }
            } else {
                print("\(dryRunPrefix)Updated \(successCount)/\(results.count) screens")
                for result in results where !result.success {
                    printError("  [\(result.screenIndex)] \(result.screenName): \(result.error ?? "Unknown error")")
                }
            }
        }
    }
}

struct UpdateResult: Codable {
    let screenIndex: Int
    let screenId: String
    let screenName: String
    let imagePath: String?
    let fitStyle: FitStyle
    let success: Bool
    let error: String?
}

struct UpdateOutput: Codable {
    let dryRun: Bool
    let results: [UpdateResult]
    
    func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Set Command

struct Set: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set a specific wallpaper for a screen"
    )
    
    @OptionGroup var global: GlobalOptions
    @OptionGroup var screenSelector: ScreenSelector
    
    @Option(name: .long, help: "Path to image file")
    var file: String
    
    @Option(name: .long, help: "Fit style (fill/fit/stretch/center/tile)")
    var fit: FitStyle?
    
    mutating func run() throws {
        let config = try loadConfig(global.config)
        let stateManager = try StateManager(config: config)
        
        let monitor = try screenSelector.resolveMonitor()
        let fitStyle = fit ?? config.fitStyleForScreen(monitor.id)
        
        // Expand path
        let expandedPath = (file as NSString).expandingTildeInPath
        
        // Set wallpaper
        try MonitorManager.setWallpaper(for: monitor.id, imagePath: expandedPath, fitStyle: fitStyle)
        try stateManager.recordWallpaperChange(screenId: monitor.id, path: expandedPath)
        
        if global.json {
            let output: [String: Any] = [
                "screen_index": monitor.index,
                "screen_id": monitor.id,
                "screen_name": monitor.name,
                "image_path": expandedPath,
                "fit_style": fitStyle.rawValue
            ]
            print(try jsonString(from: output))
        } else {
            print("Set wallpaper on \(monitor.name): \((expandedPath as NSString).lastPathComponent)")
        }
    }
}

// MARK: - Status Command

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show current wallpaper status for all screens"
    )
    
    @OptionGroup var global: GlobalOptions
    
    mutating func run() throws {
        let monitors = MonitorManager.getMonitors()
        
        if monitors.isEmpty {
            if global.json {
                print("[]")
            } else {
                print("No monitors detected")
            }
            return
        }
        
        // Try to load config for additional info
        let config = try? loadConfig(global.config)
        let stateManager = config.flatMap { try? StateManager(config: $0) }
        
        var statusList: [ScreenStatus] = []
        
        for monitor in monitors {
            let storedWallpaper = stateManager?.getCurrentWallpaper(for: monitor.id)
            let currentWallpaper = monitor.currentWallpaper ?? storedWallpaper
            var nextCandidate: String? = nil
            
            if let config = config, let stateManager = stateManager {
                let selector = ImageSelector(config: config, stateManager: stateManager)
                nextCandidate = try? selector.selectNext(for: monitor.id, dryRun: true)
            }
            
            let status = ScreenStatus(
                index: monitor.index,
                id: monitor.id,
                name: monitor.name,
                isMain: monitor.isMain,
                resolution: "\(monitor.width)x\(monitor.height)",
                currentWallpaper: currentWallpaper,
                nextCandidate: nextCandidate,
                imagesFolder: config?.imagesFolderForScreen(monitor.id),
                rotationMode: config?.rotationModeForScreen(monitor.id)
            )
            statusList.append(status)
        }
        
        if global.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(statusList)
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            print("Detected \(monitors.count) screen(s):\n")
            for status in statusList {
                let mainIndicator = status.isMain ? " (main)" : ""
                print("[\(status.index)] \(status.name)\(mainIndicator)")
                print("    ID: \(status.id)")
                print("    Resolution: \(status.resolution)")
                if let current = status.currentWallpaper {
                    print("    Current: \((current as NSString).lastPathComponent)")
                    if global.verbose {
                        print("             \(current)")
                    }
                } else {
                    print("    Current: Unknown")
                }
                if let next = status.nextCandidate {
                    print("    Next: \((next as NSString).lastPathComponent)")
                }
                if let folder = status.imagesFolder {
                    print("    Folder: \(folder)")
                }
                if let mode = status.rotationMode {
                    print("    Mode: \(mode.rawValue)")
                }
                print()
            }
        }
    }
}

struct ScreenStatus: Codable {
    let index: Int
    let id: String
    let name: String
    let isMain: Bool
    let resolution: String
    let currentWallpaper: String?
    let nextCandidate: String?
    let imagesFolder: String?
    let rotationMode: RotationMode?
}

// MARK: - Prev Command

struct Prev: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Revert to previous wallpaper"
    )
    
    @OptionGroup var global: GlobalOptions
    @OptionGroup var screenSelector: ScreenSelector
    
    mutating func run() throws {
        let config = try loadConfig(global.config)
        let stateManager = try StateManager(config: config)
        
        let monitor = try screenSelector.resolveMonitor()
        
        guard let previousPath = stateManager.getPreviousWallpaper(for: monitor.id) else {
            throw StateError.noHistory(screenId: monitor.id)
        }
        
        // Verify file still exists
        guard FileManager.default.fileExists(atPath: previousPath) else {
            printError("Previous wallpaper no longer exists: \(previousPath)")
            return
        }
        
        let fitStyle = config.fitStyleForScreen(monitor.id)
        try MonitorManager.setWallpaper(for: monitor.id, imagePath: previousPath, fitStyle: fitStyle)
        try stateManager.recordWallpaperChange(screenId: monitor.id, path: previousPath)
        
        if global.json {
            let output: [String: Any] = [
                "screen_index": monitor.index,
                "screen_id": monitor.id,
                "screen_name": monitor.name,
                "image_path": previousPath
            ]
            print(try jsonString(from: output))
        } else {
            print("Reverted \(monitor.name) to: \((previousPath as NSString).lastPathComponent)")
        }
    }
}

// MARK: - Favorite Command

struct Favorite: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Favorite current wallpaper"
    )
    
    @OptionGroup var global: GlobalOptions
    @OptionGroup var screenSelector: ScreenSelector
    
    @Flag(name: .long, help: "Don't copy file to favorites folder")
    var noCopy: Bool = false
    
    mutating func run() throws {
        let config = try loadConfig(global.config)
        let stateManager = try StateManager(config: config)
        
        let monitor = try screenSelector.resolveMonitor()
        
        // Get current wallpaper
        let currentPath = monitor.currentWallpaper ?? stateManager.getCurrentWallpaper(for: monitor.id)
        guard let imagePath = currentPath else {
            printError("No current wallpaper known for screen \(monitor.index)")
            return
        }
        
        // Check if already favorited
        if stateManager.isFavorited(imagePath) {
            print("Already favorited: \((imagePath as NSString).lastPathComponent)")
            return
        }
        
        try stateManager.addToFavorites(imagePath, copyToFolder: !noCopy)
        
        if global.json {
            let output: [String: Any] = [
                "screen_index": monitor.index,
                "screen_name": monitor.name,
                "image_path": imagePath,
                "copied_to_favorites": !noCopy
            ]
            print(try jsonString(from: output))
        } else {
            let copiedMsg = noCopy ? "" : " (copied to favorites folder)"
            print("Favorited: \((imagePath as NSString).lastPathComponent)\(copiedMsg)")
        }
    }
}

// MARK: - Ban Command

struct Ban: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Ban current wallpaper from appearing again"
    )
    
    @OptionGroup var global: GlobalOptions
    @OptionGroup var screenSelector: ScreenSelector
    
    @Flag(name: .long, help: "Move file to blacklist folder (if configured)")
    var moveFile: Bool = false
    
    @Flag(name: .long, help: "Also update to next wallpaper")
    var andUpdate: Bool = false
    
    mutating func run() throws {
        let config = try loadConfig(global.config)
        let stateManager = try StateManager(config: config)
        
        let monitor = try screenSelector.resolveMonitor()
        
        // Get current wallpaper
        let currentPath = monitor.currentWallpaper ?? stateManager.getCurrentWallpaper(for: monitor.id)
        guard let imagePath = currentPath else {
            printError("No current wallpaper known for screen \(monitor.index)")
            return
        }
        
        // Check if already blacklisted
        if stateManager.isBlacklisted(imagePath) {
            print("Already blacklisted: \((imagePath as NSString).lastPathComponent)")
            return
        }
        
        let shouldMove = moveFile && config.blacklistStrategy == .folder && config.blacklistFolder != nil
        try stateManager.addToBlacklist(imagePath, moveToFolder: shouldMove)
        
        if global.json {
            let output: [String: Any] = [
                "screen_index": monitor.index,
                "screen_name": monitor.name,
                "image_path": imagePath,
                "moved_to_blacklist_folder": shouldMove
            ]
            print(try jsonString(from: output))
        } else {
            let movedMsg = shouldMove ? " (moved to blacklist folder)" : ""
            print("Banned: \((imagePath as NSString).lastPathComponent)\(movedMsg)")
        }
        
        // Update to next wallpaper if requested
        if andUpdate {
            let selector = ImageSelector(config: config, stateManager: stateManager)
            let nextImage = try selector.selectNext(for: monitor.id, dryRun: false)
            let fitStyle = config.fitStyleForScreen(monitor.id)
            try MonitorManager.setWallpaper(for: monitor.id, imagePath: nextImage, fitStyle: fitStyle)
            try stateManager.recordWallpaperChange(screenId: monitor.id, path: nextImage)
            
            if !global.json {
                print("Updated to: \((nextImage as NSString).lastPathComponent)")
            }
        }
    }
}

// MARK: - Config Command

struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage configuration",
        subcommands: [ConfigInit.self, ConfigShow.self, ConfigPath.self]
    )
}

struct ConfigInit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a default configuration file"
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(name: .long, help: "Overwrite existing configuration")
    var force: Bool = false
    
    mutating func run() throws {
        let configPath = global.config ?? ConfigManager.defaultConfigPath
        
        do {
            let createdPath = try ConfigManager.createDefault(at: configPath, force: force)
            
            if global.json {
                let output: [String: Any] = [
                    "path": createdPath,
                    "created": true
                ]
                print(try jsonString(from: output))
            } else {
                print("Created configuration file at: \(createdPath)")
                print("\nEdit this file to customize your settings:")
                print("  - Set 'images_folder' to your wallpapers directory")
                print("  - Choose rotation mode: random, sequential, or no-repeat")
                print("  - Configure per-screen settings if needed")
                print("\nRun 'lumen status' to see detected screens.")
            }
        } catch ConfigError.fileExists(let path) {
            printError("Configuration already exists at: \(path)")
            print("Use --force to overwrite")
        }
    }
}

struct ConfigShow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show current configuration"
    )
    
    @OptionGroup var global: GlobalOptions
    
    mutating func run() throws {
        let config = try loadConfig(global.config)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        let data = try encoder.encode(config)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }
}

struct ConfigPath: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "path",
        abstract: "Show configuration file path"
    )
    
    @OptionGroup var global: GlobalOptions
    
    mutating func run() throws {
        let configPath = global.config ?? ConfigManager.defaultConfigPath
        let expandedPath = (configPath as NSString).expandingTildeInPath
        
        if global.json {
            let output: [String: Any] = [
                "path": expandedPath,
                "exists": FileManager.default.fileExists(atPath: expandedPath)
            ]
            print(try jsonString(from: output))
        } else {
            print(expandedPath)
            if !FileManager.default.fileExists(atPath: expandedPath) {
                print("(file does not exist)")
            }
        }
    }
}

// MARK: - History Command

struct History: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show wallpaper history"
    )
    
    @OptionGroup var global: GlobalOptions
    @OptionGroup var screenSelector: ScreenSelector
    
    @Option(name: .long, help: "Number of entries to show")
    var limit: Int = 20
    
    mutating func run() throws {
        let config = try loadConfig(global.config)
        let stateManager = try StateManager(config: config)
        
        let entries: [HistoryEntry]
        let screenLabel: String
        
        if screenSelector.hasSelection {
            let monitor = try screenSelector.resolveMonitor()
            entries = stateManager.getHistory(for: monitor.id, limit: limit)
            screenLabel = "Screen \(monitor.index) (\(monitor.name))"
        } else {
            entries = stateManager.getAllHistory(limit: limit)
            screenLabel = "All screens"
        }
        
        if global.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            print("History for \(screenLabel) (last \(entries.count) entries):\n")
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            
            for entry in entries.reversed() {
                let filename = (entry.path as NSString).lastPathComponent
                let date = dateFormatter.string(from: entry.timestamp)
                print("  \(date) - \(filename)")
                if global.verbose {
                    print("              \(entry.path)")
                }
            }
        }
    }
}

// MARK: - List Command

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List favorites or blacklisted images"
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Flag(name: .long, help: "List favorites")
    var favorites: Bool = false
    
    @Flag(name: .long, help: "List blacklisted images")
    var blacklist: Bool = false
    
    mutating func run() throws {
        let config = try loadConfig(global.config)
        let stateManager = try StateManager(config: config)
        
        if favorites {
            let favs = stateManager.getFavorites()
            if global.json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.keyEncodingStrategy = .convertToSnakeCase
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(favs)
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                print("Favorites (\(favs.count)):\n")
                for fav in favs {
                    let filename = (fav.originalPath as NSString).lastPathComponent
                    print("  \(filename)")
                    if global.verbose {
                        print("    Original: \(fav.originalPath)")
                        if let favPath = fav.favoritePath {
                            print("    Copy: \(favPath)")
                        }
                    }
                }
            }
        } else if blacklist {
            let banned = stateManager.getBlacklist()
            if global.json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.keyEncodingStrategy = .convertToSnakeCase
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(banned)
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                print("Blacklisted (\(banned.count)):\n")
                for entry in banned {
                    let filename = (entry.path as NSString).lastPathComponent
                    print("  \(filename)")
                    if global.verbose {
                        print("    Path: \(entry.path)")
                        if let hash = entry.hash {
                            print("    Hash: \(hash.prefix(16))...")
                        }
                    }
                }
            }
        } else {
            print("Specify --favorites or --blacklist")
        }
    }
}

// MARK: - Helpers

func loadConfig(_ customPath: String?) throws -> LumenConfig {
    return try ConfigManager.load(from: customPath)
}

func printError(_ message: String) {
    FileHandle.standardError.write("Error: \(message)\n".data(using: .utf8)!)
}

func jsonString(from dict: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    return String(data: data, encoding: .utf8) ?? "{}"
}

// Make FitStyle parsable from command line
extension FitStyle: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}

