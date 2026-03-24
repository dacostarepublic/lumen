import Foundation
import CryptoKit
import Darwin

// MARK: - History Entry

/// A single entry in the wallpaper history
public struct HistoryEntry: Codable, Equatable, Sendable {
    public let path: String
    public let timestamp: Date
    public let screenId: String
    
    public init(path: String, timestamp: Date = Date(), screenId: String) {
        self.path = path
        self.timestamp = timestamp
        self.screenId = screenId
    }
}

// MARK: - Screen State

/// State for a single screen
public struct ScreenState: Codable, Equatable, Sendable {
    public var currentWallpaper: String?
    public var history: [HistoryEntry]
    public var shownImages: Set<String>  // For no-repeat mode
    public var sequentialIndex: Int      // For sequential mode
    public var selectionCounts: [String: Int]  // For weighted-random mode
    
    public init(
        currentWallpaper: String? = nil,
        history: [HistoryEntry] = [],
        shownImages: Set<String> = [],
        sequentialIndex: Int = 0,
        selectionCounts: [String: Int] = [:]
    ) {
        self.currentWallpaper = currentWallpaper
        self.history = history
        self.shownImages = shownImages
        self.sequentialIndex = sequentialIndex
        self.selectionCounts = selectionCounts
    }

    enum CodingKeys: String, CodingKey {
        case currentWallpaper
        case history
        case shownImages
        case sequentialIndex
        case selectionCounts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentWallpaper = try container.decodeIfPresent(String.self, forKey: .currentWallpaper)
        history = try container.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
        shownImages = try container.decodeIfPresent(Set<String>.self, forKey: .shownImages) ?? []
        sequentialIndex = try container.decodeIfPresent(Int.self, forKey: .sequentialIndex) ?? 0
        selectionCounts = try container.decodeIfPresent([String: Int].self, forKey: .selectionCounts) ?? [:]
    }
    
    /// Get the previous wallpaper from history (not including current)
    public func previousWallpaper() -> String? {
        guard history.count >= 2 else { return nil }
        return history[history.count - 2].path
    }
    
    /// Add a wallpaper to history
    public mutating func addToHistory(_ path: String, screenId: String) {
        let entry = HistoryEntry(path: path, screenId: screenId)
        history.append(entry)
        currentWallpaper = path
        shownImages.insert(path)
        selectionCounts[path, default: 0] += 1
        
        // Keep history manageable (last 1000 entries)
        if history.count > 1000 {
            history = Array(history.suffix(1000))
        }
    }
    
    /// Reset the shown images set (for no-repeat mode when cycle completes)
    public mutating func resetShownImages() {
        shownImages.removeAll()
    }

    public mutating func pruneSelectionCounts(validPaths: Set<String>) {
        selectionCounts = selectionCounts.filter { validPaths.contains($0.key) }
    }
}

// MARK: - Blacklist Entry

/// A blacklisted image
public struct BlacklistEntry: Codable, Equatable, Sendable {
    public let path: String
    public let hash: String?  // Optional SHA256 hash for content-based matching
    public let timestamp: Date
    public let reason: String?
    
    public init(path: String, hash: String? = nil, timestamp: Date = Date(), reason: String? = nil) {
        self.path = path
        self.hash = hash
        self.timestamp = timestamp
        self.reason = reason
    }
}

// MARK: - Favorites Entry

/// A favorited image
public struct FavoriteEntry: Codable, Equatable, Sendable {
    public let originalPath: String
    public let favoritePath: String?  // Path in favorites folder if copied
    public let timestamp: Date
    
    public init(originalPath: String, favoritePath: String? = nil, timestamp: Date = Date()) {
        self.originalPath = originalPath
        self.favoritePath = favoritePath
        self.timestamp = timestamp
    }
}

// MARK: - App State

/// Complete application state
public struct AppState: Codable, Equatable, Sendable {
    public var screens: [String: ScreenState]  // Keyed by screen ID
    public var blacklist: [BlacklistEntry]
    public var favorites: [FavoriteEntry]
    public var version: Int
    
    public static let currentVersion = 2
    
    public init(screens: [String: ScreenState] = [:], blacklist: [BlacklistEntry] = [], favorites: [FavoriteEntry] = [], version: Int = currentVersion) {
        self.screens = screens
        self.blacklist = blacklist
        self.favorites = favorites
        self.version = version
    }

    enum CodingKeys: String, CodingKey {
        case screens
        case blacklist
        case favorites
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        screens = try container.decodeIfPresent([String: ScreenState].self, forKey: .screens) ?? [:]
        blacklist = try container.decodeIfPresent([BlacklistEntry].self, forKey: .blacklist) ?? []
        favorites = try container.decodeIfPresent([FavoriteEntry].self, forKey: .favorites) ?? []
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    public func migratedToCurrentVersion() -> AppState {
        var migrated = self

        if migrated.version < 2 {
            migrated.version = 2
        }

        return migrated
    }
    
    /// Get or create state for a screen
    public mutating func screenState(for screenId: String) -> ScreenState {
        if let state = screens[screenId] {
            return state
        }
        let newState = ScreenState()
        screens[screenId] = newState
        return newState
    }
    
    /// Update state for a screen
    public mutating func updateScreen(_ screenId: String, _ state: ScreenState) {
        screens[screenId] = state
    }
    
    /// Check if a path is blacklisted
    public func isBlacklisted(_ path: String) -> Bool {
        return blacklist.contains { $0.path == path }
    }
    
    /// Check if a hash is blacklisted
    public func isBlacklistedByHash(_ hash: String) -> Bool {
        return blacklist.contains { $0.hash == hash }
    }
    
    /// Add to blacklist
    public mutating func addToBlacklist(_ path: String, hash: String? = nil, reason: String? = nil) {
        // Don't add duplicates
        if isBlacklisted(path) { return }
        let entry = BlacklistEntry(path: path, hash: hash, reason: reason)
        blacklist.append(entry)
    }
    
    /// Remove from blacklist
    public mutating func removeFromBlacklist(_ path: String) {
        blacklist.removeAll { $0.path == path }
    }
    
    /// Check if a path is favorited
    public func isFavorited(_ path: String) -> Bool {
        return favorites.contains { $0.originalPath == path }
    }
    
    /// Add to favorites
    public mutating func addToFavorites(_ path: String, favoritePath: String? = nil) {
        // Don't add duplicates
        if isFavorited(path) { return }
        let entry = FavoriteEntry(originalPath: path, favoritePath: favoritePath)
        favorites.append(entry)
    }
    
    /// Remove from favorites
    public mutating func removeFromFavorites(_ path: String) {
        favorites.removeAll { $0.originalPath == path }
    }
}

// MARK: - State Manager

public class StateManager {
    private let config: LumenConfig
    private var state: AppState
    private let stateFilePath: String
    private let lockFilePath: String
    
    public init(config: LumenConfig) throws {
        self.config = config
        self.stateFilePath = config.stateFile
        self.lockFilePath = config.stateFile + ".lock"
        self.state = AppState()
        
        // Ensure data directory exists
        try ConfigManager.ensureDataDirectory(config: config)
        
        // Load existing state or create new
        self.state = try withStateLock {
            try StateManager.load(from: stateFilePath) ?? AppState()
        }
    }
    
    /// Initialize with provided state (for testing)
    public init(config: LumenConfig, initialState: AppState, stateFilePath: String) {
        self.config = config
        self.state = initialState
        self.stateFilePath = stateFilePath
        self.lockFilePath = stateFilePath + ".lock"
    }
    
    /// Load state from file
    private static func load(from path: String) throws -> AppState? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return nil
        }
        
        guard let data = fileManager.contents(atPath: path) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        do {
            let decoded = try decoder.decode(AppState.self, from: data)
            return decoded.migratedToCurrentVersion()
        } catch {
            printStateWarning("Could not decode state file at '\(path)'. Starting with a fresh state. Error: \(error)")
            return AppState()
        }
    }
    
    /// Load state from data (for testing)
    public static func loadFromData(_ data: Data) throws -> AppState {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppState.self, from: data)
        return decoded.migratedToCurrentVersion()
    }
    
    /// Save state to file
    public func save() throws {
        try withStateLock {
            try saveUnlocked()
        }
    }

    private func saveUnlocked() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(state)
        try data.write(to: URL(fileURLWithPath: stateFilePath), options: .atomic)
    }

    @discardableResult
    private func mutateAndSave<T>(_ mutation: (inout AppState) throws -> T) throws -> T {
        return try withStateLock {
            state = try StateManager.load(from: stateFilePath) ?? AppState()
            let result = try mutation(&state)
            try saveUnlocked()
            return result
        }
    }

    private func withStateLock<T>(_ operation: () throws -> T) throws -> T {
        let fd = open(lockFilePath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd != -1 else {
            throw StateError.fileOperationFailed(
                operation: "open lock file",
                path: lockFilePath,
                underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            )
        }

        if flock(fd, LOCK_EX) != 0 {
            let lockError = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            close(fd)
            throw StateError.fileOperationFailed(operation: "acquire lock", path: lockFilePath, underlying: lockError)
        }

        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }

        return try operation()
    }
    
    /// Get current app state (for testing)
    public func getState() -> AppState {
        return state
    }

    /// Refresh in-memory state from disk.
    public func refresh() throws {
        try withStateLock {
            state = try StateManager.load(from: stateFilePath) ?? AppState()
        }
    }
    
    // MARK: - Screen State Operations
    
    public func getScreenState(for screenId: String) -> ScreenState {
        return state.screenState(for: screenId)
    }
    
    public func recordWallpaperChange(screenId: String, path: String) throws {
        try mutateAndSave { state in
            var screenState = state.screenState(for: screenId)
            screenState.addToHistory(path, screenId: screenId)
            state.updateScreen(screenId, screenState)
        }
    }
    
    public func getPreviousWallpaper(for screenId: String) -> String? {
        return state.screenState(for: screenId).previousWallpaper()
    }
    
    public func getCurrentWallpaper(for screenId: String) -> String? {
        return state.screenState(for: screenId).currentWallpaper
    }
    
    public func getShownImages(for screenId: String) -> Set<String> {
        return state.screenState(for: screenId).shownImages
    }
    
    public func resetShownImages(for screenId: String) throws {
        try mutateAndSave { state in
            var screenState = state.screenState(for: screenId)
            screenState.resetShownImages()
            state.updateScreen(screenId, screenState)
        }
    }
    
    public func getSequentialIndex(for screenId: String) -> Int {
        return state.screenState(for: screenId).sequentialIndex
    }
    
    public func setSequentialIndex(for screenId: String, index: Int) throws {
        try mutateAndSave { state in
            var screenState = state.screenState(for: screenId)
            screenState.sequentialIndex = index
            state.updateScreen(screenId, screenState)
        }
    }

    public func pruneSelectionCounts(for screenId: String, validPaths: Set<String>) throws {
        try mutateAndSave { state in
            var screenState = state.screenState(for: screenId)
            screenState.pruneSelectionCounts(validPaths: validPaths)
            state.updateScreen(screenId, screenState)
        }
    }

    public func getSelectionCounts(for screenId: String) -> [String: Int] {
        return state.screenState(for: screenId).selectionCounts
    }
    
    // MARK: - Blacklist Operations
    
    public func isBlacklisted(_ path: String) -> Bool {
        return state.isBlacklisted(path)
    }
    
    public func addToBlacklist(_ path: String, moveToFolder: Bool = false) throws {
        // Compute hash if file exists
        var hash: String? = nil
        if FileManager.default.fileExists(atPath: path) {
            hash = try? computeFileHash(path)
        }
        
        try mutateAndSave { state in
            state.addToBlacklist(path, hash: hash)
        }

        // If using folder strategy, move the file
        if moveToFolder, let blacklistFolder = config.blacklistFolder {
            let fileName = (path as NSString).lastPathComponent
            let destPath = (blacklistFolder as NSString).appendingPathComponent(fileName)

            // Create blacklist folder if needed
            try FileManager.default.createDirectory(atPath: blacklistFolder, withIntermediateDirectories: true)

            // Move file (with unique name if conflict)
            let finalPath = getUniqueFilePath(destPath)
            try FileManager.default.moveItem(atPath: path, toPath: finalPath)
        }
    }
    
    public func removeFromBlacklist(_ path: String) throws {
        try mutateAndSave { state in
            state.removeFromBlacklist(path)
        }
    }

    public func getMostRecentBlacklisted() -> BlacklistEntry? {
        return state.blacklist.max(by: { $0.timestamp < $1.timestamp })
    }

    @discardableResult
    public func removeMostRecentBlacklisted() throws -> BlacklistEntry? {
        return try mutateAndSave { state in
            guard let latest = state.blacklist.max(by: { $0.timestamp < $1.timestamp }) else {
                return nil
            }
            state.removeFromBlacklist(latest.path)
            return latest
        }
    }

    @discardableResult
    public func clearBlacklist() throws -> Int {
        return try mutateAndSave { state in
            let count = state.blacklist.count
            state.blacklist.removeAll()
            return count
        }
    }
    
    public func getBlacklist() -> [BlacklistEntry] {
        return state.blacklist
    }
    
    public func getBlacklistedPaths() -> Set<String> {
        return Set(state.blacklist.map { $0.path })
    }
    
    // MARK: - Favorites Operations
    
    public func isFavorited(_ path: String) -> Bool {
        return state.isFavorited(path)
    }
    
    public func addToFavorites(_ path: String, copyToFolder: Bool = true) throws {
        var favoritePath: String? = nil
        
        if copyToFolder {
            try ConfigManager.ensureFavoritesFolder(config: config)
            
            let fileName = (path as NSString).lastPathComponent
            let destPath = (config.favoritesFolder as NSString).appendingPathComponent(fileName)
            
            // Copy file (with unique name if conflict)
            let finalPath = getUniqueFilePath(destPath)
            try FileManager.default.copyItem(atPath: path, toPath: finalPath)
            favoritePath = finalPath
        }
        
        try mutateAndSave { state in
            state.addToFavorites(path, favoritePath: favoritePath)
        }
    }
    
    public func removeFromFavorites(_ path: String) throws {
        try mutateAndSave { state in
            state.removeFromFavorites(path)
        }
    }
    
    public func getFavorites() -> [FavoriteEntry] {
        return state.favorites
    }
    
    // MARK: - History Operations
    
    public func getHistory(for screenId: String, limit: Int = 50) -> [HistoryEntry] {
        let screenState = state.screenState(for: screenId)
        return Array(screenState.history.suffix(limit))
    }
    
    public func getAllHistory(limit: Int = 100) -> [HistoryEntry] {
        var allHistory: [HistoryEntry] = []
        for (_, screenState) in state.screens {
            allHistory.append(contentsOf: screenState.history)
        }
        allHistory.sort { $0.timestamp > $1.timestamp }
        return Array(allHistory.prefix(limit))
    }
    
    // MARK: - Utility
    
    private func computeFileHash(_ path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func getUniqueFilePath(_ path: String) -> String {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            return path
        }
        
        let directory = (path as NSString).deletingLastPathComponent
        let filename = (path as NSString).deletingPathExtension
        let ext = (path as NSString).pathExtension
        
        var counter = 1
        var newPath: String
        repeat {
            let newFilename = "\((filename as NSString).lastPathComponent)_\(counter)"
            newPath = (directory as NSString).appendingPathComponent(newFilename + (ext.isEmpty ? "" : ".\(ext)"))
            counter += 1
        } while fileManager.fileExists(atPath: newPath)
        
        return newPath
    }
}

private func printStateWarning(_ message: String) {
    if let data = "Warning: \(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

// MARK: - State Errors

public enum StateError: Error, CustomStringConvertible {
    case noHistory(screenId: String)
    case fileOperationFailed(operation: String, path: String, underlying: Error)
    
    public var description: String {
        switch self {
        case .noHistory(let screenId):
            return "No history available for screen '\(screenId)'"
        case .fileOperationFailed(let operation, let path, let underlying):
            return "Failed to \(operation) '\(path)': \(underlying.localizedDescription)"
        }
    }
}
