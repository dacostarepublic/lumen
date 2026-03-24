import XCTest
@testable import LumenCore

final class StateTests: XCTestCase {
    
    // MARK: - Screen State Tests
    
    func testScreenStateInitialization() {
        let state = ScreenState()
        
        XCTAssertNil(state.currentWallpaper)
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertTrue(state.shownImages.isEmpty)
        XCTAssertEqual(state.sequentialIndex, 0)
        XCTAssertTrue(state.selectionCounts.isEmpty)
    }
    
    func testAddToHistory() {
        var state = ScreenState()
        
        state.addToHistory("/path/to/image1.jpg", screenId: "screen1")
        
        XCTAssertEqual(state.currentWallpaper, "/path/to/image1.jpg")
        XCTAssertEqual(state.history.count, 1)
        XCTAssertEqual(state.history[0].path, "/path/to/image1.jpg")
        XCTAssertEqual(state.history[0].screenId, "screen1")
        XCTAssertTrue(state.shownImages.contains("/path/to/image1.jpg"))
        XCTAssertEqual(state.selectionCounts["/path/to/image1.jpg"], 1)
    }
    
    func testPreviousWallpaper() {
        var state = ScreenState()
        
        // No history - should return nil
        XCTAssertNil(state.previousWallpaper())
        
        // One entry - should return nil (no previous)
        state.addToHistory("/path/to/image1.jpg", screenId: "screen1")
        XCTAssertNil(state.previousWallpaper())
        
        // Two entries - should return first one
        state.addToHistory("/path/to/image2.jpg", screenId: "screen1")
        XCTAssertEqual(state.previousWallpaper(), "/path/to/image1.jpg")
        
        // Three entries - should return second one
        state.addToHistory("/path/to/image3.jpg", screenId: "screen1")
        XCTAssertEqual(state.previousWallpaper(), "/path/to/image2.jpg")
    }
    
    func testResetShownImages() {
        var state = ScreenState()
        state.addToHistory("/path/to/image1.jpg", screenId: "screen1")
        state.addToHistory("/path/to/image2.jpg", screenId: "screen1")
        
        XCTAssertEqual(state.shownImages.count, 2)
        
        state.resetShownImages()
        
        XCTAssertTrue(state.shownImages.isEmpty)
        XCTAssertEqual(state.history.count, 2) // History preserved
    }
    
    func testHistoryLimit() {
        var state = ScreenState()
        
        // Add more than 1000 entries
        for i in 0..<1100 {
            state.addToHistory("/path/to/image\(i).jpg", screenId: "screen1")
        }
        
        // Should be limited to 1000
        XCTAssertEqual(state.history.count, 1000)
        XCTAssertEqual(state.history.first?.path, "/path/to/image100.jpg")
        XCTAssertEqual(state.history.last?.path, "/path/to/image1099.jpg")
    }
    
    // MARK: - App State Tests
    
    func testAppStateInitialization() {
        let state = AppState()
        
        XCTAssertTrue(state.screens.isEmpty)
        XCTAssertTrue(state.blacklist.isEmpty)
        XCTAssertTrue(state.favorites.isEmpty)
        XCTAssertEqual(state.version, AppState.currentVersion)
    }
    
    func testScreenStateCreation() {
        var state = AppState()
        
        // Getting state for new screen creates it
        let screenState = state.screenState(for: "screen1")
        XCTAssertNil(screenState.currentWallpaper)
        
        // Update and retrieve
        var updatedState = screenState
        updatedState.currentWallpaper = "/test/path.jpg"
        state.updateScreen("screen1", updatedState)
        
        let retrieved = state.screenState(for: "screen1")
        XCTAssertEqual(retrieved.currentWallpaper, "/test/path.jpg")
    }
    
    // MARK: - Blacklist Tests
    
    func testBlacklistOperations() {
        var state = AppState()
        
        XCTAssertFalse(state.isBlacklisted("/path/to/image.jpg"))
        
        state.addToBlacklist("/path/to/image.jpg")
        XCTAssertTrue(state.isBlacklisted("/path/to/image.jpg"))
        XCTAssertEqual(state.blacklist.count, 1)
        
        // Adding duplicate should not increase count
        state.addToBlacklist("/path/to/image.jpg")
        XCTAssertEqual(state.blacklist.count, 1)
        
        state.removeFromBlacklist("/path/to/image.jpg")
        XCTAssertFalse(state.isBlacklisted("/path/to/image.jpg"))
        XCTAssertTrue(state.blacklist.isEmpty)
    }
    
    func testBlacklistWithHash() {
        var state = AppState()
        
        state.addToBlacklist("/path/to/image.jpg", hash: "abc123")
        
        XCTAssertTrue(state.isBlacklistedByHash("abc123"))
        XCTAssertFalse(state.isBlacklistedByHash("xyz789"))
    }
    
    // MARK: - Favorites Tests
    
    func testFavoritesOperations() {
        var state = AppState()
        
        XCTAssertFalse(state.isFavorited("/path/to/image.jpg"))
        
        state.addToFavorites("/path/to/image.jpg")
        XCTAssertTrue(state.isFavorited("/path/to/image.jpg"))
        XCTAssertEqual(state.favorites.count, 1)
        
        // Adding duplicate should not increase count
        state.addToFavorites("/path/to/image.jpg")
        XCTAssertEqual(state.favorites.count, 1)
        
        state.removeFromFavorites("/path/to/image.jpg")
        XCTAssertFalse(state.isFavorited("/path/to/image.jpg"))
        XCTAssertTrue(state.favorites.isEmpty)
    }
    
    func testFavoritesWithCopiedPath() {
        var state = AppState()
        
        state.addToFavorites("/original/path.jpg", favoritePath: "/favorites/path.jpg")
        
        let favorite = state.favorites.first!
        XCTAssertEqual(favorite.originalPath, "/original/path.jpg")
        XCTAssertEqual(favorite.favoritePath, "/favorites/path.jpg")
    }
    
    // MARK: - History Entry Tests
    
    func testHistoryEntry() {
        let now = Date()
        let entry = HistoryEntry(path: "/path/to/image.jpg", timestamp: now, screenId: "screen1")
        
        XCTAssertEqual(entry.path, "/path/to/image.jpg")
        XCTAssertEqual(entry.timestamp, now)
        XCTAssertEqual(entry.screenId, "screen1")
    }
    
    // MARK: - Blacklist Entry Tests
    
    func testBlacklistEntry() {
        let now = Date()
        let entry = BlacklistEntry(path: "/path/to/image.jpg", hash: "abc123", timestamp: now, reason: "Too bright")
        
        XCTAssertEqual(entry.path, "/path/to/image.jpg")
        XCTAssertEqual(entry.hash, "abc123")
        XCTAssertEqual(entry.timestamp, now)
        XCTAssertEqual(entry.reason, "Too bright")
    }
    
    // MARK: - JSON Serialization Tests
    
    func testAppStateSerialization() throws {
        var state = AppState()
        state.addToBlacklist("/banned/image.jpg", hash: "hash123")
        state.addToFavorites("/favorite/image.jpg")
        
        var screenState = ScreenState()
        screenState.addToHistory("/history/image.jpg", screenId: "screen1")
        state.updateScreen("screen1", screenState)
        
        // Encode
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        
        // Decode
        let loaded = try StateManager.loadFromData(data)
        
        XCTAssertEqual(loaded.version, state.version)
        XCTAssertEqual(loaded.blacklist.count, 1)
        XCTAssertEqual(loaded.favorites.count, 1)
        XCTAssertNotNil(loaded.screens["screen1"])
    }

    func testStateMigrationFromV1Data() throws {
        let json = """
        {
          "screens": {
            "screen1": {
              "current_wallpaper": "/path/old.jpg",
              "history": [],
              "shown_images": [],
              "sequential_index": 0
            }
          },
          "blacklist": [],
          "favorites": [],
          "version": 1
        }
        """

        let loaded = try StateManager.loadFromData(json.data(using: .utf8)!)
        XCTAssertEqual(loaded.version, AppState.currentVersion)
        XCTAssertEqual(loaded.screens["screen1"]?.selectionCounts, [:])
    }

    func testCorruptStateFileFallsBackToFreshState() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = LumenConfig(dataDirectory: tempDir.path)
        let statePath = (tempDir.path as NSString).appendingPathComponent("state.json")
        try "{ invalid-json".write(toFile: statePath, atomically: true, encoding: .utf8)

        let manager = try StateManager(config: config)
        let state = manager.getState()

        XCTAssertEqual(state.version, AppState.currentVersion)
        XCTAssertTrue(state.screens.isEmpty)
        XCTAssertTrue(state.blacklist.isEmpty)
        XCTAssertTrue(state.favorites.isEmpty)
    }
    
    // MARK: - State Error Tests
    
    func testStateErrorDescriptions() {
        let error1 = StateError.noHistory(screenId: "screen1")
        XCTAssertTrue(error1.description.contains("No history"))
        XCTAssertTrue(error1.description.contains("screen1"))
        
        let error2 = StateError.fileOperationFailed(operation: "lock", path: "/test/path", underlying: NSError(domain: "test", code: 1))
        XCTAssertTrue(error2.description.contains("Failed to lock"))
    }
}
