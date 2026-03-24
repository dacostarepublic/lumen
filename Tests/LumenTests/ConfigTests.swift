import XCTest
@testable import LumenCore

final class ConfigTests: XCTestCase {
    
    // MARK: - Default Config Tests
    
    func testDefaultConfigValues() {
        let config = LumenConfig()
        
        XCTAssertEqual(config.imagesFolder, "~/Pictures/Wallpapers")
        XCTAssertEqual(config.rotationMode, .random)
        XCTAssertEqual(config.fitStyle, .fill)
        XCTAssertEqual(config.interval, 30)
        XCTAssertEqual(config.dataDirectory, "~/Library/Application Support/lumen")
        XCTAssertEqual(config.favoritesFolder, "~/Pictures/Wallpapers/Favorites")
        XCTAssertEqual(config.blacklistStrategy, .list)
        XCTAssertNil(config.blacklistFolder)
        XCTAssertEqual(config.logLevel, "info")
        XCTAssertFalse(config.applyAllSpaces)
        XCTAssertTrue(config.screens.isEmpty)
    }
    
    func testComputedPaths() {
        let config = LumenConfig(dataDirectory: "/tmp/lumen-test")
        
        XCTAssertEqual(config.historyFile, "/tmp/lumen-test/history.json")
        XCTAssertEqual(config.blacklistFile, "/tmp/lumen-test/blacklist.json")
        XCTAssertEqual(config.stateFile, "/tmp/lumen-test/state.json")
    }
    
    // MARK: - Per-Screen Config Tests
    
    func testPerScreenImagesFolderOverride() {
        var config = LumenConfig(imagesFolder: "/default/folder")
        config.screens["screen1"] = ScreenConfig(imagesFolder: "/screen1/folder")
        
        XCTAssertEqual(config.imagesFolderForScreen("screen1"), "/screen1/folder")
        XCTAssertEqual(config.imagesFolderForScreen("screen2"), "/default/folder")
    }
    
    func testPerScreenRotationModeOverride() {
        var config = LumenConfig(rotationMode: .random)
        config.screens["screen1"] = ScreenConfig(rotationMode: .sequential)
        
        XCTAssertEqual(config.rotationModeForScreen("screen1"), .sequential)
        XCTAssertEqual(config.rotationModeForScreen("screen2"), .random)
    }
    
    func testPerScreenFitStyleOverride() {
        var config = LumenConfig(fitStyle: .fill)
        config.screens["screen1"] = ScreenConfig(fitStyle: .center)
        
        XCTAssertEqual(config.fitStyleForScreen("screen1"), .center)
        XCTAssertEqual(config.fitStyleForScreen("screen2"), .fill)
    }
    
    // MARK: - Path Expansion Tests
    
    func testPathExpansion() {
        let config = LumenConfig(
            imagesFolder: "~/Pictures",
            dataDirectory: "~/Library/Application Support/lumen",
            favoritesFolder: "~/Pictures/Favorites"
        )
        
        let expanded = config.expanded()
        let home = NSHomeDirectory()
        
        XCTAssertEqual(expanded.imagesFolder, "\(home)/Pictures")
        XCTAssertEqual(expanded.dataDirectory, "\(home)/Library/Application Support/lumen")
        XCTAssertEqual(expanded.favoritesFolder, "\(home)/Pictures/Favorites")
    }
    
    func testPerScreenPathExpansion() {
        var config = LumenConfig()
        config.screens["screen1"] = ScreenConfig(imagesFolder: "~/Screen1Wallpapers")
        
        let expanded = config.expanded()
        let home = NSHomeDirectory()
        
        XCTAssertEqual(expanded.screens["screen1"]?.imagesFolder, "\(home)/Screen1Wallpapers")
    }
    
    // MARK: - JSON Parsing Tests
    
    func testJSONParsing() throws {
        let json = """
        {
            "images_folder": "/test/images",
            "rotation_mode": "sequential",
            "fit_style": "fit",
            "interval": 60,
            "data_directory": "/test/data",
            "favorites_folder": "/test/favorites",
            "blacklist_strategy": "folder",
            "blacklist_folder": "/test/blacklist",
            "log_level": "debug",
            "apply_all_spaces": true,
            "screens": {
                "123": {
                    "images_folder": "/test/screen123",
                    "rotation_mode": "no-repeat",
                    "fit_style": "center"
                }
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let config = try ConfigManager.load(from: data)
        
        XCTAssertEqual(config.imagesFolder, "/test/images")
        XCTAssertEqual(config.rotationMode, .sequential)
        XCTAssertEqual(config.fitStyle, .fit)
        XCTAssertEqual(config.interval, 60)
        XCTAssertEqual(config.dataDirectory, "/test/data")
        XCTAssertEqual(config.favoritesFolder, "/test/favorites")
        XCTAssertEqual(config.blacklistStrategy, .folder)
        XCTAssertEqual(config.blacklistFolder, "/test/blacklist")
        XCTAssertEqual(config.logLevel, "debug")
        XCTAssertTrue(config.applyAllSpaces)
        
        let screenConfig = config.screens["123"]
        XCTAssertNotNil(screenConfig)
        XCTAssertEqual(screenConfig?.imagesFolder, "/test/screen123")
        XCTAssertEqual(screenConfig?.rotationMode, .noRepeat)
        XCTAssertEqual(screenConfig?.fitStyle, .center)
    }
    
    func testJSONEncodingDecoding() throws {
        let original = LumenConfig(
            imagesFolder: "/test/path",
            rotationMode: .noRepeat,
            fitStyle: .stretch,
            interval: 45
        )
        
        let data = try ConfigManager.encode(original)
        let decoded = try ConfigManager.load(from: data)
        
        XCTAssertEqual(decoded.imagesFolder, original.imagesFolder)
        XCTAssertEqual(decoded.rotationMode, original.rotationMode)
        XCTAssertEqual(decoded.fitStyle, original.fitStyle)
        XCTAssertEqual(decoded.interval, original.interval)
    }
    
    // MARK: - Rotation Mode Tests
    
    func testRotationModeRawValues() {
        XCTAssertEqual(RotationMode.random.rawValue, "random")
        XCTAssertEqual(RotationMode.sequential.rawValue, "sequential")
        XCTAssertEqual(RotationMode.noRepeat.rawValue, "no-repeat")
    }
    
    func testRotationModeFromRawValue() {
        XCTAssertEqual(RotationMode(rawValue: "random"), .random)
        XCTAssertEqual(RotationMode(rawValue: "sequential"), .sequential)
        XCTAssertEqual(RotationMode(rawValue: "no-repeat"), .noRepeat)
        XCTAssertNil(RotationMode(rawValue: "invalid"))
    }
    
    // MARK: - Fit Style Tests
    
    func testFitStyleRawValues() {
        XCTAssertEqual(FitStyle.fill.rawValue, "fill")
        XCTAssertEqual(FitStyle.fit.rawValue, "fit")
        XCTAssertEqual(FitStyle.stretch.rawValue, "stretch")
        XCTAssertEqual(FitStyle.center.rawValue, "center")
        XCTAssertEqual(FitStyle.tile.rawValue, "tile")
    }
    
    // MARK: - Config Error Tests
    
    func testConfigFileNotFoundError() {
        let error = ConfigError.fileNotFound(path: "/nonexistent/path")
        XCTAssertTrue(error.description.contains("not found"))
        XCTAssertTrue(error.description.contains("/nonexistent/path"))
    }
    
    func testConfigParseError() {
        let error = ConfigError.parseError(details: "invalid JSON")
        XCTAssertTrue(error.description.contains("Invalid configuration"))
        XCTAssertTrue(error.description.contains("invalid JSON"))
    }

    func testInvalidIntervalFailsValidation() {
        let json = """
        {
            "images_folder": "/test/images",
            "rotation_mode": "random",
            "fit_style": "fill",
            "interval": 0,
            "data_directory": "/test/data",
            "favorites_folder": "/test/favorites",
            "blacklist_strategy": "list",
            "log_level": "info",
            "screens": {}
        }
        """

        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try ConfigManager.load(from: data))
    }

    func testFolderStrategyRequiresBlacklistFolder() {
        let json = """
        {
            "images_folder": "/test/images",
            "rotation_mode": "random",
            "fit_style": "fill",
            "interval": 30,
            "data_directory": "/test/data",
            "favorites_folder": "/test/favorites",
            "blacklist_strategy": "folder",
            "blacklist_folder": null,
            "log_level": "info",
            "screens": {}
        }
        """

        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try ConfigManager.load(from: data))
    }
}
