import Foundation
import AppKit
import CoreGraphics

// MARK: - Monitor Information

/// Represents a connected display/monitor
public struct MonitorInfo: Codable, Equatable, Sendable {
    public let id: String           // Stable identifier (CGDirectDisplayID as string)
    public let index: Int           // 1-based index for user convenience
    public let name: String         // Display name
    public let isMain: Bool         // Whether this is the main display
    public let width: Int           // Resolution width
    public let height: Int          // Resolution height
    public var currentWallpaper: String?  // Current wallpaper path if known
    
    public init(id: String, index: Int, name: String, isMain: Bool, width: Int, height: Int, currentWallpaper: String? = nil) {
        self.id = id
        self.index = index
        self.name = name
        self.isMain = isMain
        self.width = width
        self.height = height
        self.currentWallpaper = currentWallpaper
    }
    
    public var displayDescription: String {
        let mainIndicator = isMain ? " (main)" : ""
        return "[\(index)] \(name)\(mainIndicator) - \(width)x\(height) [id: \(id)]"
    }
}

// MARK: - Monitor Manager

public class MonitorManager {
    
    /// Get all connected monitors
    public static func getMonitors() -> [MonitorInfo] {
        var monitors: [MonitorInfo] = []
        
        // Get all active displays
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        
        guard displayCount > 0 else { return [] }
        
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        
        let mainDisplay = CGMainDisplayID()
        
        for (index, displayID) in displays.enumerated() {
            let name = getDisplayName(for: displayID)
            let isMain = displayID == mainDisplay
            let width = CGDisplayPixelsWide(displayID)
            let height = CGDisplayPixelsHigh(displayID)
            let currentWallpaper = getCurrentWallpaper(for: displayID)
            
            let monitor = MonitorInfo(
                id: String(displayID),
                index: index + 1,  // 1-based for user friendliness
                name: name,
                isMain: isMain,
                width: width,
                height: height,
                currentWallpaper: currentWallpaper
            )
            monitors.append(monitor)
        }
        
        return monitors
    }
    
    /// Find a monitor by index (1-based)
    public static func findMonitor(byIndex index: Int) -> MonitorInfo? {
        let monitors = getMonitors()
        return monitors.first { $0.index == index }
    }
    
    /// Find a monitor by ID
    public static func findMonitor(byId id: String) -> MonitorInfo? {
        let monitors = getMonitors()
        return monitors.first { $0.id == id }
    }
    
    /// Get display name for a display ID
    private static func getDisplayName(for displayID: CGDirectDisplayID) -> String {
        // Try to get a friendly name
        // On newer macOS, we can use CGDisplayCopyDisplayMode and related APIs
        // For a simpler approach, we'll use screen enumeration
        
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                if screenNumber == displayID {
                    return screen.localizedName
                }
            }
        }
        
        // Fallback to generic name
        if displayID == CGMainDisplayID() {
            return "Main Display"
        }
        return "Display \(displayID)"
    }
    
    /// Get current wallpaper for a display
    private static func getCurrentWallpaper(for displayID: CGDirectDisplayID) -> String? {
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                if screenNumber == displayID {
                    if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                        return url.path
                    }
                }
            }
        }
        return nil
    }
    
    /// Get NSScreen for a display ID
    private static func getScreen(for displayID: CGDirectDisplayID) -> NSScreen? {
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                if screenNumber == displayID {
                    return screen
                }
            }
        }
        return nil
    }
    
    /// Set wallpaper for a specific monitor
    public static func setWallpaper(for monitorId: String, imagePath: String, fitStyle: FitStyle = .fill, syncAllSpaces: Bool = false) throws {
        guard let displayID = UInt32(monitorId) else {
            throw MonitorError.invalidMonitorId(monitorId)
        }
        
        guard let screen = getScreen(for: displayID) else {
            throw MonitorError.monitorNotFound(id: monitorId)
        }
        
        let imageURL = URL(fileURLWithPath: imagePath)
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw MonitorError.imageNotFound(path: imagePath)
        }
        
        // Verify it's a supported image
        let supportedExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp"]
        let ext = imageURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw MonitorError.unsupportedImageFormat(extension: ext)
        }
        
        // Set wallpaper options based on fit style
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        
        switch fitStyle {
        case .fill:
            options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
            options[.allowClipping] = true
        case .fit:
            options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
            options[.allowClipping] = false
        case .stretch:
            options[.imageScaling] = NSImageScaling.scaleAxesIndependently.rawValue
            options[.allowClipping] = true
        case .center:
            options[.imageScaling] = NSImageScaling.scaleNone.rawValue
            options[.allowClipping] = false
        case .tile:
            options[.imageScaling] = NSImageScaling.scaleNone.rawValue
            options[.allowClipping] = true
        }
        
        do {
            try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: options)
        } catch {
            throw MonitorError.setWallpaperFailed(path: imagePath, underlying: error)
        }
        
        if syncAllSpaces {
            // Best-effort compatibility shim for older macOS behavior where only the current
            // space updates through NSWorkspace APIs.
            syncWallpaperAcrossSpacesBestEffort(monitorId: monitorId, imagePath: imagePath)
        }
    }
    
    /// Updates the system backing store so all desktop spaces on the display use the same image.
    /// setDesktopImageURL only affects the current space; this syncs all spaces (Ventura: Dock db, Sonoma+: Wallpaper plist).
    private static func syncWallpaperAcrossSpacesBestEffort(monitorId: String, imagePath: String) {
        _ = monitorId
        let ver = ProcessInfo.processInfo.operatingSystemVersion
        let fileURL = URL(fileURLWithPath: imagePath).absoluteString
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        
        // Skip this path on newer systems where private storage formats have diverged.
        if ver.majorVersion >= 26 {
            return
        }
        if ver.majorVersion >= 14 {
            // macOS 14-15 (Sonoma/Sequoia): com.apple.wallpaper Store, AllSpacesAndDisplays dict
            let plistPath = "\(home)/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
            guard FileManager.default.fileExists(atPath: plistPath) else { return }
            // Edit plist in Swift (PlistBuddy "set" fails when key path or structure differs by OS)
            let plistURL = URL(fileURLWithPath: plistPath)
            var format: PropertyListSerialization.PropertyListFormat = .binary
            guard let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainers, format: &format) as? NSMutableDictionary else {
                return
            }
            // macOS 14-15: AllSpacesAndDisplays is a dict (Desktop -> Content -> Choices -> Files).
            // macOS 26+: AllSpacesAndDisplays can be a string; use "Spaces" or "Displays" dict and set relative in each entry.
            var didSet = false
            if let allSpacesAny = plist["AllSpacesAndDisplays"],
               let allSpaces = (allSpacesAny as? NSMutableDictionary) ?? (allSpacesAny as? NSDictionary)?.mutableCopy() as? NSMutableDictionary {
                let desktopKey = allSpaces["Desktop"] != nil ? "Desktop" : (allSpaces.allKeys.first as? String)
                if let desktopKey = desktopKey,
                   let desktopAny = allSpaces[desktopKey],
                   let desktop = (desktopAny as? NSMutableDictionary) ?? (desktopAny as? NSDictionary)?.mutableCopy() as? NSMutableDictionary,
                   let contentAny = desktop["Content"],
                   let content = (contentAny as? NSMutableDictionary) ?? (contentAny as? NSDictionary)?.mutableCopy() as? NSMutableDictionary,
                   let choicesAny = content["Choices"],
                   let choices = (choicesAny as? NSMutableArray) ?? (choicesAny as? NSArray)?.mutableCopy() as? NSMutableArray,
                   choices.count > 0,
                   let choice0Any = choices[0] as? NSDictionary,
                   let choice0 = choice0Any.mutableCopy() as? NSMutableDictionary,
                   let filesAny = choice0["Files"],
                   let files = (filesAny as? NSMutableArray) ?? (filesAny as? NSArray)?.mutableCopy() as? NSMutableArray,
                   files.count > 0,
                   let file0Any = files[0] as? NSDictionary,
                   let file0 = file0Any.mutableCopy() as? NSMutableDictionary {
                    file0["relative"] = fileURL
                    files.replaceObject(at: 0, with: file0)
                    choice0["Files"] = files
                    choices.replaceObject(at: 0, with: choice0)
                    content["Choices"] = choices
                    desktop["Content"] = content
                    allSpaces[desktopKey] = desktop
                    plist["AllSpacesAndDisplays"] = allSpaces
                    didSet = true
                }
            }
            if !didSet, let spacesAny = plist["Spaces"] as? NSDictionary {
                // macOS 26: "Spaces" is a dict; each value is a space config. Set Content->Choices[0]->Files[0]->relative in each.
                let spaces = (spacesAny as? NSMutableDictionary) ?? spacesAny.mutableCopy() as? NSMutableDictionary
                guard let spaces = spaces else { return }
                for key in spaces.allKeys {
                    guard let entryAny = spaces[key],
                          let entry = (entryAny as? NSMutableDictionary) ?? (entryAny as? NSDictionary)?.mutableCopy() as? NSMutableDictionary,
                          let contentAny = entry["Content"],
                          let content = (contentAny as? NSMutableDictionary) ?? (contentAny as? NSDictionary)?.mutableCopy() as? NSMutableDictionary,
                          let choicesAny = content["Choices"],
                          let choices = (choicesAny as? NSArray) ?? (choicesAny as? NSMutableArray),
                          choices.count > 0,
                          let choice0Any = choices[0] as? NSDictionary,
                          let choice0 = choice0Any.mutableCopy() as? NSMutableDictionary,
                          let filesAny = choice0["Files"],
                          let files = (filesAny as? NSArray) ?? (filesAny as? NSMutableArray),
                          files.count > 0,
                          let file0Any = files[0] as? NSDictionary,
                          let file0 = file0Any.mutableCopy() as? NSMutableDictionary else { continue }
                    file0["relative"] = fileURL
                    let filesMut = (files as? NSMutableArray) ?? files.mutableCopy() as? NSMutableArray
                    let choicesMut = (choices as? NSMutableArray) ?? choices.mutableCopy() as? NSMutableArray
                    filesMut?.replaceObject(at: 0, with: file0)
                    choice0["Files"] = filesMut ?? files
                    choicesMut?.replaceObject(at: 0, with: choice0)
                    content["Choices"] = choicesMut ?? choices
                    entry["Content"] = content
                    spaces[key] = entry
                }
                plist["Spaces"] = spaces
                didSet = true
            }
            if !didSet, let displaysAny = plist["Displays"] as? NSDictionary {
                // macOS 26: "Displays" dict; same pattern per display.
                let displays = (displaysAny as? NSMutableDictionary) ?? displaysAny.mutableCopy() as? NSMutableDictionary
                guard let displays = displays else { return }
                for key in displays.allKeys {
                    guard let entryAny = displays[key],
                          let entry = (entryAny as? NSMutableDictionary) ?? (entryAny as? NSDictionary)?.mutableCopy() as? NSMutableDictionary,
                          let contentAny = entry["Content"],
                          let content = (contentAny as? NSMutableDictionary) ?? (contentAny as? NSDictionary)?.mutableCopy() as? NSMutableDictionary,
                          let choicesAny = content["Choices"],
                          let choices = (choicesAny as? NSArray) ?? (choicesAny as? NSMutableArray),
                          choices.count > 0,
                          let choice0Any = choices[0] as? NSDictionary,
                          let choice0 = choice0Any.mutableCopy() as? NSMutableDictionary,
                          let filesAny = choice0["Files"],
                          let files = (filesAny as? NSArray) ?? (filesAny as? NSMutableArray),
                          files.count > 0,
                          let file0Any = files[0] as? NSDictionary,
                          let file0 = file0Any.mutableCopy() as? NSMutableDictionary else { continue }
                    file0["relative"] = fileURL
                    let filesMut = (files as? NSMutableArray) ?? files.mutableCopy() as? NSMutableArray
                    let choicesMut = (choices as? NSMutableArray) ?? choices.mutableCopy() as? NSMutableArray
                    filesMut?.replaceObject(at: 0, with: file0)
                    choice0["Files"] = filesMut ?? files
                    choicesMut?.replaceObject(at: 0, with: choice0)
                    content["Choices"] = choicesMut ?? choices
                    entry["Content"] = content
                    displays[key] = entry
                }
                plist["Displays"] = displays
                didSet = true
            }
            guard didSet else { return }
            guard let outData = try? PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0) else { return }
            do {
                try outData.write(to: plistURL)
            } catch {
                return
            }
            runKillAll("WallpaperAgent")
        } else if ver.majorVersion == 13 {
            // macOS 13 (Ventura): Dock desktoppicture.db
            let dbPath = "\(home)/Library/Application Support/Dock/desktoppicture.db"
            guard FileManager.default.fileExists(atPath: dbPath) else { return }
            let escaped = imagePath.replacingOccurrences(of: "'", with: "''")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            proc.arguments = [dbPath, "UPDATE data SET value = '\(escaped)';"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                runKillAll("Dock")
            }
        }
    }
    
    private static func runKillAll(_ name: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        proc.arguments = [name]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }
    
    /// Set wallpaper for all monitors
    public static func setWallpaperForAll(imagePath: String, fitStyle: FitStyle = .fill, syncAllSpaces: Bool = false) throws {
        let monitors = getMonitors()
        var errors: [String] = []
        
        for monitor in monitors {
            do {
                try setWallpaper(for: monitor.id, imagePath: imagePath, fitStyle: fitStyle, syncAllSpaces: syncAllSpaces)
            } catch {
                errors.append("Screen \(monitor.index): \(error)")
            }
        }
        
        if !errors.isEmpty {
            throw MonitorError.multipleErrors(errors)
        }
    }
}

// MARK: - Monitor Errors

public enum MonitorError: Error, CustomStringConvertible {
    case noMonitorsFound
    case invalidMonitorId(String)
    case monitorNotFound(id: String)
    case monitorNotFoundByIndex(Int)
    case imageNotFound(path: String)
    case unsupportedImageFormat(extension: String)
    case setWallpaperFailed(path: String, underlying: Error)
    case multipleErrors([String])
    case permissionDenied
    
    public var description: String {
        switch self {
        case .noMonitorsFound:
            return "No monitors detected"
        case .invalidMonitorId(let id):
            return "Invalid monitor ID: '\(id)'"
        case .monitorNotFound(let id):
            return "Monitor with ID '\(id)' not found. Use 'lumen status' to see available monitors."
        case .monitorNotFoundByIndex(let index):
            return "Monitor with index \(index) not found. Use 'lumen status' to see available monitors."
        case .imageNotFound(let path):
            return "Image file not found: '\(path)'"
        case .unsupportedImageFormat(let ext):
            return "Unsupported image format: '.\(ext)'. Supported: jpg, png, heic, tiff, gif, bmp"
        case .setWallpaperFailed(let path, let underlying):
            return "Failed to set wallpaper '\(path)': \(underlying.localizedDescription)"
        case .multipleErrors(let errors):
            return "Multiple errors occurred:\n" + errors.joined(separator: "\n")
        case .permissionDenied:
            return "Permission denied. Ensure lumen has access to control your desktop."
        }
    }
}
