import Foundation

// MARK: - Configuration Models

/// Rotation mode for wallpaper selection
public enum RotationMode: String, Codable, CaseIterable, Sendable {
    case random = "random"
    case sequential = "sequential"
    case noRepeat = "no-repeat"
    case weightedRandom = "weighted-random"
    
    public var description: String {
        switch self {
        case .random: return "Random selection"
        case .sequential: return "Sequential order"
        case .noRepeat: return "No repeats until all shown"
        case .weightedRandom: return "Weighted random (prefer less-shown images)"
        }
    }
}

/// Wallpaper fit style
public enum FitStyle: String, Codable, CaseIterable, Sendable {
    case fill = "fill"
    case fit = "fit"
    case stretch = "stretch"
    case center = "center"
    case tile = "tile"
    
    public var description: String {
        switch self {
        case .fill: return "Fill screen (may crop)"
        case .fit: return "Fit to screen (may letterbox)"
        case .stretch: return "Stretch to fill"
        case .center: return "Center without scaling"
        case .tile: return "Tile image"
        }
    }
}

/// Blacklist storage strategy
public enum BlacklistStrategy: String, Codable, Sendable {
    case folder = "folder"  // Move files to a blacklist folder
    case list = "list"      // Store paths/hashes in a list file
}

/// Per-screen configuration overrides
public struct ScreenConfig: Codable, Equatable, Sendable {
    public var imagesFolder: String?
    public var rotationMode: RotationMode?
    public var fitStyle: FitStyle?
    public var recursive: Bool?
    public var preferMatchingAspect: Bool?
    
    public init(
        imagesFolder: String? = nil,
        rotationMode: RotationMode? = nil,
        fitStyle: FitStyle? = nil,
        recursive: Bool? = nil,
        preferMatchingAspect: Bool? = nil
    ) {
        self.imagesFolder = imagesFolder
        self.rotationMode = rotationMode
        self.fitStyle = fitStyle
        self.recursive = recursive
        self.preferMatchingAspect = preferMatchingAspect
    }
}

/// Main configuration structure
public struct LumenConfig: Codable, Equatable, Sendable {
    // Global settings
    public var imagesFolder: String
    public var rotationMode: RotationMode
    public var fitStyle: FitStyle
    public var interval: Int  // In minutes
    public var recursive: Bool
    public var preferMatchingAspect: Bool
    
    // Storage locations
    public var dataDirectory: String
    public var favoritesFolder: String
    public var blacklistStrategy: BlacklistStrategy
    public var blacklistFolder: String?
    
    // Behavior
    public var logLevel: String
    public var applyAllSpaces: Bool
    
    // Per-screen overrides (keyed by screen identifier)
    public var screens: [String: ScreenConfig]
    
    // Computed paths
    public var historyFile: String {
        return (dataDirectory as NSString).appendingPathComponent("history.json")
    }
    
    public var blacklistFile: String {
        return (dataDirectory as NSString).appendingPathComponent("blacklist.json")
    }
    
    public var stateFile: String {
        return (dataDirectory as NSString).appendingPathComponent("state.json")
    }
    
    public init(
        imagesFolder: String = "~/Pictures/Wallpapers",
        rotationMode: RotationMode = .random,
        fitStyle: FitStyle = .fill,
        interval: Int = 30,
        recursive: Bool = true,
        preferMatchingAspect: Bool = false,
        dataDirectory: String = "~/Library/Application Support/lumen",
        favoritesFolder: String = "~/Pictures/Wallpapers/Favorites",
        blacklistStrategy: BlacklistStrategy = .list,
        blacklistFolder: String? = nil,
        logLevel: String = "info",
        applyAllSpaces: Bool = false,
        screens: [String: ScreenConfig] = [:]
    ) {
        self.imagesFolder = imagesFolder
        self.rotationMode = rotationMode
        self.fitStyle = fitStyle
        self.interval = interval
        self.recursive = recursive
        self.preferMatchingAspect = preferMatchingAspect
        self.dataDirectory = dataDirectory
        self.favoritesFolder = favoritesFolder
        self.blacklistStrategy = blacklistStrategy
        self.blacklistFolder = blacklistFolder
        self.logLevel = logLevel
        self.applyAllSpaces = applyAllSpaces
        self.screens = screens
    }

    enum CodingKeys: String, CodingKey {
        case imagesFolder
        case rotationMode
        case fitStyle
        case interval
        case recursive
        case preferMatchingAspect
        case dataDirectory
        case favoritesFolder
        case blacklistStrategy
        case blacklistFolder
        case logLevel
        case applyAllSpaces
        case screens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imagesFolder = try container.decode(String.self, forKey: .imagesFolder)
        rotationMode = try container.decode(RotationMode.self, forKey: .rotationMode)
        fitStyle = try container.decode(FitStyle.self, forKey: .fitStyle)
        interval = try container.decode(Int.self, forKey: .interval)
        recursive = try container.decodeIfPresent(Bool.self, forKey: .recursive) ?? true
        preferMatchingAspect = try container.decodeIfPresent(Bool.self, forKey: .preferMatchingAspect) ?? false
        dataDirectory = try container.decode(String.self, forKey: .dataDirectory)
        favoritesFolder = try container.decode(String.self, forKey: .favoritesFolder)
        blacklistStrategy = try container.decode(BlacklistStrategy.self, forKey: .blacklistStrategy)
        blacklistFolder = try container.decodeIfPresent(String.self, forKey: .blacklistFolder)
        logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel) ?? "info"
        applyAllSpaces = try container.decodeIfPresent(Bool.self, forKey: .applyAllSpaces) ?? false
        screens = try container.decodeIfPresent([String: ScreenConfig].self, forKey: .screens) ?? [:]
    }
    
    /// Get effective images folder for a screen
    public func imagesFolderForScreen(_ screenId: String) -> String {
        return screens[screenId]?.imagesFolder ?? imagesFolder
    }
    
    /// Get effective rotation mode for a screen
    public func rotationModeForScreen(_ screenId: String) -> RotationMode {
        return screens[screenId]?.rotationMode ?? rotationMode
    }
    
    /// Get effective fit style for a screen
    public func fitStyleForScreen(_ screenId: String) -> FitStyle {
        return screens[screenId]?.fitStyle ?? fitStyle
    }

    /// Get effective recursion setting for a screen
    public func recursiveForScreen(_ screenId: String) -> Bool {
        return screens[screenId]?.recursive ?? recursive
    }

    /// Get effective aspect preference setting for a screen
    public func preferMatchingAspectForScreen(_ screenId: String) -> Bool {
        return screens[screenId]?.preferMatchingAspect ?? preferMatchingAspect
    }
    
    /// Expand all tilde paths to full paths
    public func expanded() -> LumenConfig {
        var config = self
        config.imagesFolder = (imagesFolder as NSString).expandingTildeInPath
        config.dataDirectory = (dataDirectory as NSString).expandingTildeInPath
        config.favoritesFolder = (favoritesFolder as NSString).expandingTildeInPath
        if let folder = blacklistFolder {
            config.blacklistFolder = (folder as NSString).expandingTildeInPath
        }
        // Expand per-screen folders
        for (key, var screenConfig) in config.screens {
            if let folder = screenConfig.imagesFolder {
                screenConfig.imagesFolder = (folder as NSString).expandingTildeInPath
            }
            config.screens[key] = screenConfig
        }
        return config
    }

    /// Validate configuration values for runtime safety.
    public func validated() throws -> LumenConfig {
        if imagesFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConfigError.invalidValue(field: "images_folder", value: imagesFolder)
        }

        if interval <= 0 {
            throw ConfigError.invalidValue(field: "interval", value: String(interval))
        }

        let normalizedLogLevel = logLevel.lowercased()
        let allowedLogLevels = ["debug", "info", "warn", "error"]
        if !allowedLogLevels.contains(normalizedLogLevel) {
            throw ConfigError.invalidValue(field: "log_level", value: logLevel)
        }

        if blacklistStrategy == .folder,
           (blacklistFolder?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            throw ConfigError.invalidValue(field: "blacklist_folder", value: "null")
        }

        return self
    }
}

// MARK: - Config File Management

public struct ConfigManager {
    public static let defaultConfigPath = "~/.lumen-config"
    
    /// Load configuration from file
    public static func load(from path: String? = nil) throws -> LumenConfig {
        let configPath = (path ?? defaultConfigPath) as NSString
        let expandedPath = configPath.expandingTildeInPath
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: expandedPath) else {
            throw ConfigError.fileNotFound(path: expandedPath)
        }
        
        guard let data = fileManager.contents(atPath: expandedPath) else {
            throw ConfigError.readError(path: expandedPath)
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let config = try decoder.decode(LumenConfig.self, from: data)
            return try config.expanded().validated()
        } catch let error as DecodingError {
            throw ConfigError.parseError(details: describeDecodingError(error))
        }
    }
    
    /// Load configuration from JSON data (for testing)
    public static func load(from data: Data) throws -> LumenConfig {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config = try decoder.decode(LumenConfig.self, from: data)
        return try config.expanded().validated()
    }
    
    /// Save configuration to file
    public static func save(_ config: LumenConfig, to path: String? = nil) throws {
        let configPath = (path ?? defaultConfigPath) as NSString
        let expandedPath = configPath.expandingTildeInPath
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(config)
            let fileManager = FileManager.default
            
            // Create parent directory if needed
            let parentDir = (expandedPath as NSString).deletingLastPathComponent
            if !fileManager.fileExists(atPath: parentDir) {
                try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            }
            
            try data.write(to: URL(fileURLWithPath: expandedPath))
        } catch {
            throw ConfigError.writeError(path: expandedPath, underlying: error)
        }
    }
    
    /// Encode config to JSON data
    public static func encode(_ config: LumenConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }
    
    /// Create default configuration file
    public static func createDefault(at path: String? = nil, force: Bool = false) throws -> String {
        let configPath = (path ?? defaultConfigPath) as NSString
        let expandedPath = configPath.expandingTildeInPath
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: expandedPath) && !force {
            throw ConfigError.fileExists(path: expandedPath)
        }
        
        let defaultConfig = LumenConfig()
        try save(defaultConfig, to: expandedPath)
        return expandedPath
    }
    
    /// Ensure data directory exists
    public static func ensureDataDirectory(config: LumenConfig) throws {
        let fileManager = FileManager.default
        let dataDir = config.dataDirectory
        
        if !fileManager.fileExists(atPath: dataDir) {
            try fileManager.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        }
    }
    
    /// Ensure favorites folder exists
    public static func ensureFavoritesFolder(config: LumenConfig) throws {
        let fileManager = FileManager.default
        let favDir = config.favoritesFolder
        
        if !fileManager.fileExists(atPath: favDir) {
            try fileManager.createDirectory(atPath: favDir, withIntermediateDirectories: true)
        }
    }
    
    private static func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "Missing value of type \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return "Corrupted data at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

// MARK: - Config Errors

public enum ConfigError: Error, CustomStringConvertible {
    case fileNotFound(path: String)
    case readError(path: String)
    case parseError(details: String)
    case writeError(path: String, underlying: Error)
    case fileExists(path: String)
    case invalidValue(field: String, value: String)
    
    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Configuration file not found at '\(path)'. Run 'lumen config init' to create one."
        case .readError(let path):
            return "Could not read configuration file at '\(path)'"
        case .parseError(let details):
            return "Invalid configuration format: \(details)"
        case .writeError(let path, let underlying):
            return "Could not write configuration to '\(path)': \(underlying.localizedDescription)"
        case .fileExists(let path):
            return "Configuration file already exists at '\(path)'. Use --force to overwrite."
        case .invalidValue(let field, let value):
            return "Invalid value '\(value)' for field '\(field)'"
        }
    }
}
