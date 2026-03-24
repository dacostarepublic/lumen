import XCTest
@testable import LumenCore

final class ImageSelectorTests: XCTestCase {
    
    var tempDir: URL!
    var config: LumenConfig!
    var stateManager: StateManager!
    var selector: ImageSelector!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary directory for test files
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create test images
        let imageNames = ["image1.jpg", "image2.jpg", "image3.jpg", "image4.jpg", "image5.jpg"]
        for name in imageNames {
            let imagePath = tempDir.appendingPathComponent(name)
            // Create minimal valid JPEG data (placeholder)
            let placeholderData = Data([0xFF, 0xD8, 0xFF, 0xE0])
            try placeholderData.write(to: imagePath)
        }
        
        // Create config pointing to temp directory
        config = LumenConfig(
            imagesFolder: tempDir.path,
            rotationMode: .random,
            dataDirectory: tempDir.appendingPathComponent("data").path
        )
        
        stateManager = try StateManager(config: config)
        selector = ImageSelector(config: config, stateManager: stateManager)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }
    
    // MARK: - Image Discovery Tests
    
    func testImageDiscoveryFindsImages() throws {
        let images = try ImageDiscovery.getImages(in: tempDir.path)
        XCTAssertEqual(images.count, 5)
    }

    func testRecursiveDiscoveryToggle() throws {
        let parentDir = tempDir.appendingPathComponent("recursive-only")
        let nestedDir = parentDir.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        let nestedImage = nestedDir.appendingPathComponent("nested.jpg")
        let placeholderData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        try placeholderData.write(to: nestedImage)

        let nonRecursiveConfig = LumenConfig(
            imagesFolder: parentDir.path,
            rotationMode: .random,
            recursive: false,
            dataDirectory: tempDir.appendingPathComponent("data-non-recursive").path
        )
        let nonRecursiveState = try StateManager(config: nonRecursiveConfig)
        let nonRecursiveSelector = ImageSelector(config: nonRecursiveConfig, stateManager: nonRecursiveState)

        XCTAssertThrowsError(try nonRecursiveSelector.selectNext(for: "screen1", dryRun: true))

        let recursiveConfig = LumenConfig(
            imagesFolder: parentDir.path,
            rotationMode: .random,
            recursive: true,
            dataDirectory: tempDir.appendingPathComponent("data-recursive").path
        )
        let recursiveState = try StateManager(config: recursiveConfig)
        let recursiveSelector = ImageSelector(config: recursiveConfig, stateManager: recursiveState)

        let selected = try recursiveSelector.selectNext(for: "screen1", dryRun: true)
        XCTAssertEqual(selected, nestedImage.path)
    }
    
    func testImageDiscoverySupportsMultipleFormats() {
        let supported = ImageDiscovery.supportedExtensions
        
        XCTAssertTrue(supported.contains("jpg"))
        XCTAssertTrue(supported.contains("jpeg"))
        XCTAssertTrue(supported.contains("png"))
        XCTAssertTrue(supported.contains("heic"))
        XCTAssertTrue(supported.contains("heif"))
        XCTAssertTrue(supported.contains("tiff"))
        XCTAssertTrue(supported.contains("gif"))
        XCTAssertTrue(supported.contains("bmp"))
    }
    
    func testImageDiscoveryIsImageFile() {
        XCTAssertTrue(ImageDiscovery.isImageFile("/path/to/image.jpg"))
        XCTAssertTrue(ImageDiscovery.isImageFile("/path/to/image.JPEG"))
        XCTAssertTrue(ImageDiscovery.isImageFile("/path/to/image.PNG"))
        XCTAssertTrue(ImageDiscovery.isImageFile("/path/to/image.heic"))
        
        XCTAssertFalse(ImageDiscovery.isImageFile("/path/to/document.pdf"))
        XCTAssertFalse(ImageDiscovery.isImageFile("/path/to/video.mp4"))
        XCTAssertFalse(ImageDiscovery.isImageFile("/path/to/file.txt"))
    }
    
    func testImageDiscoveryFolderNotFound() {
        let result = ImageDiscovery.validateFolder("/nonexistent/folder")
        
        switch result {
        case .failure(let error):
            XCTAssertTrue(error.description.contains("not found"))
        case .success:
            XCTFail("Should have failed for nonexistent folder")
        }
    }
    
    func testImageDiscoveryEmptyFolder() throws {
        let emptyDir = tempDir.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        
        let result = ImageDiscovery.validateFolder(emptyDir.path)
        
        switch result {
        case .failure(let error):
            XCTAssertTrue(error.description.contains("No images"))
        case .success:
            XCTFail("Should have failed for empty folder")
        }
    }
    
    // MARK: - Random Selection Tests
    
    func testRandomSelectionReturnsImage() throws {
        let selected = try selector.selectNext(for: "screen1", dryRun: true)
        
        XCTAssertTrue(selected.contains(tempDir.path))
        XCTAssertTrue(selected.hasSuffix(".jpg"))
    }
    
    func testRandomSelectionVariety() throws {
        // Run multiple times to check that we get variety (probabilistic)
        var selections = Set<String>()
        
        for _ in 0..<50 {
            let selected = try selector.selectNext(for: "screen1", dryRun: true)
            selections.insert(selected)
        }
        
        // With 5 images and 50 selections, we should get at least 2 different ones
        // (extremely unlikely to always get the same one)
        XCTAssertGreaterThan(selections.count, 1)
    }

    func testWeightedRandomPrefersLessShownImages() throws {
        let weightedConfig = LumenConfig(
            imagesFolder: tempDir.path,
            rotationMode: .weightedRandom,
            dataDirectory: tempDir.appendingPathComponent("data-weighted").path
        )
        let weightedState = try StateManager(config: weightedConfig)
        let weightedSelector = ImageSelector(config: weightedConfig, stateManager: weightedState)

        let images = try ImageDiscovery.getImages(in: tempDir.path).sorted()
        let overused = images[0]

        for _ in 0..<40 {
            try weightedState.recordWallpaperChange(screenId: "screen1", path: overused)
        }

        var overusedHits = 0
        for _ in 0..<400 {
            let selected = try weightedSelector.selectNext(for: "screen1", dryRun: true)
            if selected == overused {
                overusedHits += 1
            }
        }

        XCTAssertLessThan(overusedHits, 50)
    }

    func testWeightedRandomDryRunDoesNotMutateCounts() throws {
        let weightedConfig = LumenConfig(
            imagesFolder: tempDir.path,
            rotationMode: .weightedRandom,
            dataDirectory: tempDir.appendingPathComponent("data-weighted-dry-run").path
        )
        let weightedState = try StateManager(config: weightedConfig)
        let weightedSelector = ImageSelector(config: weightedConfig, stateManager: weightedState)

        let images = try ImageDiscovery.getImages(in: tempDir.path).sorted()
        try weightedState.recordWallpaperChange(screenId: "screen1", path: images[0])

        let before = weightedState.getSelectionCounts(for: "screen1")
        _ = try weightedSelector.selectNext(for: "screen1", dryRun: true)
        _ = try weightedSelector.selectNext(for: "screen1", dryRun: true)
        let after = weightedState.getSelectionCounts(for: "screen1")

        XCTAssertEqual(before, after)
    }
    
    // MARK: - Sequential Selection Tests
    
    func testSequentialSelectionOrder() throws {
        // Create config with sequential mode
        let seqConfig = LumenConfig(
            imagesFolder: tempDir.path,
            rotationMode: .sequential,
            dataDirectory: tempDir.appendingPathComponent("data").path
        )
        let seqState = try StateManager(config: seqConfig)
        let seqSelector = ImageSelector(config: seqConfig, stateManager: seqState)
        
        let images = try ImageDiscovery.getImages(in: tempDir.path).sorted()
        
        // First selection should be first image
        let first = try seqSelector.selectNext(for: "screen1", dryRun: false)
        XCTAssertEqual(first, images[0])
        
        // Second should be second image
        let second = try seqSelector.selectNext(for: "screen1", dryRun: false)
        XCTAssertEqual(second, images[1])
        
        // Third should be third image
        let third = try seqSelector.selectNext(for: "screen1", dryRun: false)
        XCTAssertEqual(third, images[2])
    }
    
    func testSequentialSelectionWrapsAround() throws {
        let seqConfig = LumenConfig(
            imagesFolder: tempDir.path,
            rotationMode: .sequential,
            dataDirectory: tempDir.appendingPathComponent("data").path
        )
        let seqState = try StateManager(config: seqConfig)
        let seqSelector = ImageSelector(config: seqConfig, stateManager: seqState)
        
        let images = try ImageDiscovery.getImages(in: tempDir.path).sorted()
        
        // Go through all images
        for i in 0..<images.count {
            let selected = try seqSelector.selectNext(for: "screen1", dryRun: false)
            XCTAssertEqual(selected, images[i])
        }
        
        // Should wrap back to first
        let wrapped = try seqSelector.selectNext(for: "screen1", dryRun: false)
        XCTAssertEqual(wrapped, images[0])
    }
    
    func testSequentialDryRunDoesNotAdvance() throws {
        let seqConfig = LumenConfig(
            imagesFolder: tempDir.path,
            rotationMode: .sequential,
            dataDirectory: tempDir.appendingPathComponent("data").path
        )
        let seqState = try StateManager(config: seqConfig)
        let seqSelector = ImageSelector(config: seqConfig, stateManager: seqState)
        
        let images = try ImageDiscovery.getImages(in: tempDir.path).sorted()
        
        // Dry run should return first image
        let dryRun1 = try seqSelector.selectNext(for: "screen1", dryRun: true)
        XCTAssertEqual(dryRun1, images[0])
        
        // Another dry run should still return first image
        let dryRun2 = try seqSelector.selectNext(for: "screen1", dryRun: true)
        XCTAssertEqual(dryRun2, images[0])
        
        // Real selection should also return first
        let real = try seqSelector.selectNext(for: "screen1", dryRun: false)
        XCTAssertEqual(real, images[0])
    }
    
    // MARK: - No-Repeat Selection Tests
    
    func testNoRepeatDoesNotRepeat() throws {
        let nrConfig = LumenConfig(
            imagesFolder: tempDir.path,
            rotationMode: .noRepeat,
            dataDirectory: tempDir.appendingPathComponent("data").path
        )
        let nrState = try StateManager(config: nrConfig)
        let nrSelector = ImageSelector(config: nrConfig, stateManager: nrState)
        
        var selections = [String]()
        let images = try ImageDiscovery.getImages(in: tempDir.path)
        
        // Select all images
        for _ in 0..<images.count {
            let selected = try nrSelector.selectNext(for: "screen1", dryRun: false)
            // Record the change to mark it as shown
            try nrState.recordWallpaperChange(screenId: "screen1", path: selected)
            
            // Should not have been selected before
            XCTAssertFalse(selections.contains(selected), "Image \(selected) was repeated")
            selections.append(selected)
        }
        
        // All images should have been selected
        XCTAssertEqual(Set(selections), Set(images))
    }
    
    func testNoRepeatResetsAfterCycle() throws {
        let nrConfig = LumenConfig(
            imagesFolder: tempDir.path,
            rotationMode: .noRepeat,
            dataDirectory: tempDir.appendingPathComponent("data").path
        )
        let nrState = try StateManager(config: nrConfig)
        let nrSelector = ImageSelector(config: nrConfig, stateManager: nrState)
        
        let images = try ImageDiscovery.getImages(in: tempDir.path)
        
        // Select all images
        for _ in 0..<images.count {
            let selected = try nrSelector.selectNext(for: "screen1", dryRun: false)
            try nrState.recordWallpaperChange(screenId: "screen1", path: selected)
        }
        
        // Next selection should work (cycle resets)
        let afterCycle = try nrSelector.selectNext(for: "screen1", dryRun: false)
        XCTAssertTrue(images.contains(afterCycle))
    }
    
    // MARK: - Blacklist Tests
    
    func testBlacklistExcludesImages() throws {
        let images = try ImageDiscovery.getImages(in: tempDir.path)
        
        // Blacklist the first image
        try stateManager.addToBlacklist(images[0], moveToFolder: false)
        
        // Run multiple selections - blacklisted image should never appear
        for _ in 0..<50 {
            let selected = try selector.selectNext(for: "screen1", dryRun: true)
            XCTAssertNotEqual(selected, images[0], "Blacklisted image was selected")
        }
    }
    
    func testAllImagesBlacklistedThrowsError() throws {
        let images = try ImageDiscovery.getImages(in: tempDir.path)
        
        // Blacklist all images
        for image in images {
            try stateManager.addToBlacklist(image, moveToFolder: false)
        }
        
        // Selection should throw error
        XCTAssertThrowsError(try selector.selectNext(for: "screen1", dryRun: true)) { error in
            XCTAssertTrue((error as? SelectionError) != nil)
        }
    }
    
    // MARK: - Multi-Screen Exclusion Tests
    
    func testExcludingImagesFromSelection() throws {
        let images = try ImageDiscovery.getImages(in: tempDir.path)
        
        // Select first image
        let first = try selector.selectNext(for: "screen1", excluding: [], dryRun: true)
        XCTAssertTrue(images.contains(first))
        
        // Select second image, excluding the first
        let second = try selector.selectNext(for: "screen2", excluding: [first], dryRun: true)
        XCTAssertTrue(images.contains(second))
        XCTAssertNotEqual(first, second, "Second screen should get different wallpaper")
        
        // Select third image, excluding first and second
        let third = try selector.selectNext(for: "screen3", excluding: [first, second], dryRun: true)
        XCTAssertTrue(images.contains(third))
        XCTAssertNotEqual(third, first, "Third screen should get different wallpaper than first")
        XCTAssertNotEqual(third, second, "Third screen should get different wallpaper than second")
    }
    
    func testExcludingAllImagesThrowsError() throws {
        let images = try ImageDiscovery.getImages(in: tempDir.path)
        
        // Exclude all images
        XCTAssertThrowsError(try selector.selectNext(for: "screen1", excluding: Swift.Set(images), dryRun: true)) { error in
            XCTAssertTrue((error as? SelectionError) != nil)
        }
    }
    
    func testSequentialModeWithExclusions() throws {
        let seqConfig = LumenConfig(
            imagesFolder: tempDir.path,
            rotationMode: .sequential,
            dataDirectory: tempDir.appendingPathComponent("data").path
        )
        let seqState = try StateManager(config: seqConfig)
        let seqSelector = ImageSelector(config: seqConfig, stateManager: seqState)
        
        let images = try ImageDiscovery.getImages(in: tempDir.path).sorted()
        
        // First selection should be first image
        let first = try seqSelector.selectNext(for: "screen1", excluding: [], dryRun: false)
        XCTAssertEqual(first, images[0])
        
        // Second screen with first excluded should skip to second image
        let second = try seqSelector.selectNext(for: "screen2", excluding: [images[0]], dryRun: true)
        XCTAssertNotEqual(second, images[0], "Should not select excluded image")
    }
    
    // MARK: - Selection Error Tests
    
    func testSelectionErrorDescriptions() {
        let error1 = SelectionError.noImagesAvailable(folder: "/test/folder")
        XCTAssertTrue(error1.description.contains("No images"))
        XCTAssertTrue(error1.description.contains("/test/folder"))
        
        let error2 = SelectionError.invalidMode("invalid")
        XCTAssertTrue(error2.description.contains("Invalid rotation mode"))
    }
    
    // MARK: - Selection Preview Tests
    
    func testSelectionPreview() throws {
        let preview = try selector.preview(for: "screen1")
        
        XCTAssertEqual(preview.screenId, "screen1")
        XCTAssertEqual(preview.folder, tempDir.path)
        XCTAssertEqual(preview.mode, .random)
        XCTAssertEqual(preview.fitStyle, .fill)
        XCTAssertEqual(preview.totalImages, 5)
        XCTAssertNotNil(preview.nextWallpaper)
    }
}
