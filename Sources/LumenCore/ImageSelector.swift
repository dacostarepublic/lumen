import Foundation
import ImageIO

// MARK: - Image Discovery

/// Discovers and manages images in folders
public class ImageDiscovery {
    
    /// Supported image extensions
    public static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp"]
    
    /// Get all images in a folder
    public static func getImages(in folderPath: String, recursive: Bool = true) throws -> [String] {
        let fileManager = FileManager.default
        let expandedPath = (folderPath as NSString).expandingTildeInPath
        
        // Check folder exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ImageDiscoveryError.folderNotFound(path: expandedPath)
        }
        
        var images: [String] = []
        
        if recursive {
            // Use enumerator for recursive search
            guard let enumerator = fileManager.enumerator(atPath: expandedPath) else {
                throw ImageDiscoveryError.accessDenied(path: expandedPath)
            }
            
            while let file = enumerator.nextObject() as? String {
                let fullPath = (expandedPath as NSString).appendingPathComponent(file)
                if isImageFile(fullPath) {
                    images.append(fullPath)
                }
            }
        } else {
            // Non-recursive, just top level
            let contents = try fileManager.contentsOfDirectory(atPath: expandedPath)
            for file in contents {
                let fullPath = (expandedPath as NSString).appendingPathComponent(file)
                if isImageFile(fullPath) {
                    images.append(fullPath)
                }
            }
        }
        
        return images.sorted()
    }
    
    /// Check if a file is a supported image
    public static func isImageFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }
    
    /// Verify a folder exists and contains images
    public static func validateFolder(_ folderPath: String) -> Result<Int, ImageDiscoveryError> {
        do {
            let images = try getImages(in: folderPath)
            if images.isEmpty {
                return .failure(.noImagesFound(path: folderPath))
            }
            return .success(images.count)
        } catch let error as ImageDiscoveryError {
            return .failure(error)
        } catch {
            return .failure(.accessDenied(path: folderPath))
        }
    }
}

// MARK: - Image Selector

/// Selects images based on rotation mode
public class ImageSelector {
    private let config: LumenConfig
    private let stateManager: StateManager
    
    public init(config: LumenConfig, stateManager: StateManager) {
        self.config = config
        self.stateManager = stateManager
    }
    
    /// Select next image for a screen
    /// - Parameters:
    ///   - screenId: The screen identifier
    ///   - excluding: Set of image paths to exclude (e.g., already selected for other screens)
    ///   - dryRun: If true, don't update state
    /// - Returns: Path to selected image
    public func selectNext(
        for screenId: String,
        excluding: Set<String> = [],
        dryRun: Bool = false,
        monitorWidth: Int? = nil,
        monitorHeight: Int? = nil
    ) throws -> String {
        let folder = config.imagesFolderForScreen(screenId)
        let mode = config.rotationModeForScreen(screenId)
        let recursive = config.recursiveForScreen(screenId)
        
        // Get all available images
        var images = try ImageDiscovery.getImages(in: folder, recursive: recursive)
        
        // Filter out blacklisted images
        let blacklist = stateManager.getBlacklistedPaths()
        images = images.filter { !blacklist.contains($0) }
        
        // Filter out excluded images (already selected for other screens in this batch)
        images = images.filter { !excluding.contains($0) }
        
        if images.isEmpty {
            throw SelectionError.noImagesAvailable(folder: folder)
        }
        
        // Select based on mode
        let selected: String
        switch mode {
        case .random:
            selected = try selectRandom(
                from: images,
                screenId: screenId,
                monitorWidth: monitorWidth,
                monitorHeight: monitorHeight
            )
        case .sequential:
            selected = try selectSequential(from: images, screenId: screenId, dryRun: dryRun, excluding: excluding)
        case .noRepeat:
            selected = try selectNoRepeat(
                from: images,
                screenId: screenId,
                dryRun: dryRun,
                monitorWidth: monitorWidth,
                monitorHeight: monitorHeight
            )
        case .weightedRandom:
            selected = try selectWeightedRandom(
                from: images,
                screenId: screenId,
                dryRun: dryRun,
                monitorWidth: monitorWidth,
                monitorHeight: monitorHeight
            )
        }
        
        return selected
    }
    
    /// Select next image from a given list (for testing)
    public func selectNextFrom(
        images: [String],
        screenId: String,
        mode: RotationMode,
        dryRun: Bool = false,
        monitorWidth: Int? = nil,
        monitorHeight: Int? = nil
    ) throws -> String {
        let blacklist = stateManager.getBlacklistedPaths()
        let filteredImages = images.filter { !blacklist.contains($0) }
        
        if filteredImages.isEmpty {
            throw SelectionError.noImagesAvailable(folder: "provided list")
        }
        
        switch mode {
        case .random:
            return try selectRandom(
                from: filteredImages,
                screenId: screenId,
                monitorWidth: monitorWidth,
                monitorHeight: monitorHeight
            )
        case .sequential:
            return try selectSequential(from: filteredImages, screenId: screenId, dryRun: dryRun)
        case .noRepeat:
            return try selectNoRepeat(
                from: filteredImages,
                screenId: screenId,
                dryRun: dryRun,
                monitorWidth: monitorWidth,
                monitorHeight: monitorHeight
            )
        case .weightedRandom:
            return try selectWeightedRandom(
                from: filteredImages,
                screenId: screenId,
                dryRun: dryRun,
                monitorWidth: monitorWidth,
                monitorHeight: monitorHeight
            )
        }
    }
    
    /// Random selection - pure random from available images
    private func selectRandom(
        from images: [String],
        screenId: String,
        monitorWidth: Int?,
        monitorHeight: Int?
    ) throws -> String {
        let candidates = preferredCandidates(
            from: images,
            screenId: screenId,
            monitorWidth: monitorWidth,
            monitorHeight: monitorHeight
        )

        guard let selected = candidates.randomElement() else {
            throw SelectionError.noImagesAvailable(folder: config.imagesFolderForScreen(screenId))
        }
        return selected
    }
    
    /// Sequential selection - go through images in sorted order
    private func selectSequential(from images: [String], screenId: String, dryRun: Bool, excluding: Set<String> = []) throws -> String {
        let sortedImages = images.sorted()
        var index = stateManager.getSequentialIndex(for: screenId)
        
        // Wrap around if needed
        if index >= sortedImages.count {
            index = 0
        }
        
        var selected = sortedImages[index]
        
        // If the selected image is excluded (used by another screen), find next available
        var attempts = 0
        while excluding.contains(selected) && attempts < sortedImages.count {
            index = (index + 1) % sortedImages.count
            selected = sortedImages[index]
            attempts += 1
        }
        
        // Update index if not dry run
        if !dryRun {
            let nextIndex = (index + 1) % sortedImages.count
            try stateManager.setSequentialIndex(for: screenId, index: nextIndex)
        }
        
        return selected
    }
    
    /// No-repeat selection - random but don't repeat until all shown
    private func selectNoRepeat(
        from images: [String],
        screenId: String,
        dryRun: Bool,
        monitorWidth: Int?,
        monitorHeight: Int?
    ) throws -> String {
        var shown = stateManager.getShownImages(for: screenId)
        
        // Filter to only unshown images
        var available = images.filter { !shown.contains($0) }
        
        // If all images have been shown, reset
        if available.isEmpty {
            if !dryRun {
                try stateManager.resetShownImages(for: screenId)
            }
            available = images
            shown = []
        }
        
        // Select randomly from available
        let candidates = preferredCandidates(
            from: available,
            screenId: screenId,
            monitorWidth: monitorWidth,
            monitorHeight: monitorHeight
        )

        guard let selected = candidates.randomElement() else {
            throw SelectionError.noImagesAvailable(folder: config.imagesFolderForScreen(screenId))
        }
        
        return selected
    }

    /// Weighted-random selection - prefer images with lower historical selection count
    private func selectWeightedRandom(
        from images: [String],
        screenId: String,
        dryRun: Bool,
        monitorWidth: Int?,
        monitorHeight: Int?
    ) throws -> String {
        let candidates = preferredCandidates(
            from: images,
            screenId: screenId,
            monitorWidth: monitorWidth,
            monitorHeight: monitorHeight
        )

        if !dryRun {
            try stateManager.pruneSelectionCounts(for: screenId, validPaths: Set(images))
        }

        let counts = stateManager.getSelectionCounts(for: screenId)
        let weighted = candidates.map { imagePath in
            let count = counts[imagePath] ?? 0
            let weight = 1.0 / Double(count + 1)
            return (path: imagePath, weight: weight)
        }

        let totalWeight = weighted.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            throw SelectionError.noImagesAvailable(folder: config.imagesFolderForScreen(screenId))
        }

        var target = Double.random(in: 0..<totalWeight)
        for entry in weighted {
            target -= entry.weight
            if target <= 0 {
                return entry.path
            }
        }

        return weighted.last!.path
    }

    private func preferredCandidates(
        from images: [String],
        screenId: String,
        monitorWidth: Int?,
        monitorHeight: Int?
    ) -> [String] {
        guard config.preferMatchingAspectForScreen(screenId),
              let monitorWidth,
              let monitorHeight,
              monitorWidth > 0,
              monitorHeight > 0 else {
            return images
        }

        let targetAspect = Double(monitorWidth) / Double(monitorHeight)
        let tolerance = 0.10

        var matching: [String] = []
        for path in images {
            guard let imageAspect = imageAspectRatio(for: path) else {
                continue
            }

            let relativeDiff = abs(imageAspect - targetAspect) / targetAspect
            if relativeDiff <= tolerance {
                matching.append(path)
            }
        }

        return matching.isEmpty ? images : matching
    }

    private func imageAspectRatio(for path: String) -> Double? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let widthValue = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightValue = props[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }

        let width = widthValue.doubleValue
        let height = heightValue.doubleValue
        guard width > 0, height > 0 else {
            return nil
        }

        return width / height
    }
    
    /// Get a preview of what would be selected (dry run)
    public func preview(for screenId: String) throws -> SelectionPreview {
        let folder = config.imagesFolderForScreen(screenId)
        let mode = config.rotationModeForScreen(screenId)
        let fitStyle = config.fitStyleForScreen(screenId)
        let recursive = config.recursiveForScreen(screenId)
        
        // Get all available images
        var images = try ImageDiscovery.getImages(in: folder, recursive: recursive)
        let blacklist = stateManager.getBlacklistedPaths()
        images = images.filter { !blacklist.contains($0) }
        
        let current = stateManager.getCurrentWallpaper(for: screenId)
        let selected = try selectNext(for: screenId, dryRun: true)
        
        return SelectionPreview(
            screenId: screenId,
            folder: folder,
            mode: mode,
            fitStyle: fitStyle,
            totalImages: images.count,
            currentWallpaper: current,
            nextWallpaper: selected
        )
    }
}

// MARK: - Selection Preview

/// Preview of what would be selected
public struct SelectionPreview: Codable, Sendable {
    public let screenId: String
    public let folder: String
    public let mode: RotationMode
    public let fitStyle: FitStyle
    public let totalImages: Int
    public let currentWallpaper: String?
    public let nextWallpaper: String
}

// MARK: - Errors

public enum ImageDiscoveryError: Error, CustomStringConvertible {
    case folderNotFound(path: String)
    case accessDenied(path: String)
    case noImagesFound(path: String)
    
    public var description: String {
        switch self {
        case .folderNotFound(let path):
            return "Images folder not found: '\(path)'"
        case .accessDenied(let path):
            return "Access denied to folder: '\(path)'"
        case .noImagesFound(let path):
            return "No images found in folder: '\(path)'. Supported formats: jpg, png, heic, tiff, gif, bmp"
        }
    }
}

public enum SelectionError: Error, CustomStringConvertible {
    case noImagesAvailable(folder: String)
    case invalidMode(String)
    
    public var description: String {
        switch self {
        case .noImagesAvailable(let folder):
            return "No images available in '\(folder)' (all may be blacklisted or folder is empty)"
        case .invalidMode(let mode):
            return "Invalid rotation mode: '\(mode)'"
        }
    }
}
