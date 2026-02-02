# Lumen

A terminal-first wallpaper manager for macOS. Inspired by [Irvue](https://irvue.app), but designed for local folders and power users who prefer the command line.

## Features

- 🖼️ **Rotate wallpapers** from local folders (jpg, png, heic, tiff, gif, bmp)
- 🖥️ **Multi-monitor support** with independent wallpapers per screen
- 🎲 **Rotation modes**: random, sequential, or no-repeat
- ⏪ **History tracking** with ability to go back to previous wallpapers
- ⭐ **Favorites** - save wallpapers you love
- 🚫 **Blacklist** - ban wallpapers you don't want to see again
- 🔧 **Per-screen configuration** - different folders and settings per monitor
- 📋 **JSON output** for scripting and automation
- ⚡ **Fast startup** - perfect for cron/launchd scheduling

## Installation

### Build from Source

```bash
# Clone the repository
git clone https://github.com/dacostarepublic/lumen.git
cd lumen

# Build the release binary
swift build -c release

# Copy to your PATH
cp .build/release/lumen /usr/local/bin/
```

### Requirements

- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools (for building)
- Xcode (optional, required for running tests)

## Quick Start

```bash
# Create default configuration
lumen config init

# Edit the config to set your wallpapers folder
# Default location: ~/.lumen-config

# View detected monitors and current wallpapers
lumen status

# Update wallpaper on all screens
lumen update

# Update only screen 1
lumen update --screen 1
```

## Commands

### `lumen update`

Updates wallpapers according to your configuration.

```bash
# Update all screens
lumen update

# Update specific screen by index
lumen update --screen 1

# Update specific screen by ID
lumen update --screen-id 123456789

# Preview what would happen without applying
lumen update --dry-run

# Output in JSON format
lumen update --json
```

### `lumen set`

Manually set a specific wallpaper.

```bash
# Set wallpaper on screen 2
lumen set --screen 2 --file "/path/to/wallpaper.jpg"

# Set with specific fit style
lumen set --screen 1 --file "~/Pictures/photo.png" --fit center
```

### `lumen status`

Show current status of all screens.

```bash
lumen status
# Output:
# Detected 2 screen(s):
#
# [1] Built-in Retina Display (main)
#     ID: 1
#     Resolution: 2560x1600
#     Current: mountains.jpg
#     Next: beach.png
#     Folder: /Users/you/Pictures/Wallpapers
#     Mode: random
#
# [2] DELL U2720Q
#     ID: 188178051
#     Resolution: 3840x2160
#     Current: cityscape.heic
#     ...

# JSON output for scripting
lumen status --json
```

### `lumen prev`

Revert to the previous wallpaper.

```bash
# Go back on screen 1
lumen prev --screen 1
```

### `lumen favorite`

Save the current wallpaper to your favorites.

```bash
# Favorite current wallpaper on screen 1
lumen favorite --screen 1

# Favorite without copying to favorites folder
lumen favorite --screen 1 --no-copy
```

### `lumen ban`

Ban the current wallpaper so it never appears again.

```bash
# Ban current wallpaper on screen 1
lumen ban --screen 1

# Ban and immediately show next wallpaper
lumen ban --screen 1 --and-update

# Ban and move file to blacklist folder (if configured)
lumen ban --screen 1 --move-file
```

### `lumen history`

View wallpaper history.

```bash
# History for all screens
lumen history

# History for specific screen
lumen history --screen 1

# Limit number of entries
lumen history --limit 50
```

### `lumen list`

List favorites or blacklisted images.

```bash
# List favorites
lumen list --favorites

# List blacklisted images
lumen list --blacklist

# Verbose output with full paths
lumen list --favorites --verbose
```

### `lumen config`

Manage configuration.

```bash
# Create default config
lumen config init

# Overwrite existing config
lumen config init --force

# Show current config
lumen config show

# Show config file path
lumen config path
```

## Configuration

The configuration file is stored at `~/.lumen-config` by default (JSON format).

### Example Configuration

```json
{
  "images_folder": "~/Pictures/Wallpapers",
  "rotation_mode": "random",
  "fit_style": "fill",
  "interval": 30,
  "data_directory": "~/Library/Application Support/lumen",
  "favorites_folder": "~/Pictures/Wallpapers/Favorites",
  "blacklist_strategy": "list",
  "blacklist_folder": null,
  "log_level": "info",
  "screens": {}
}
```

### Configuration Options

| Option | Description | Values |
|--------|-------------|--------|
| `images_folder` | Default folder containing wallpapers | Path (supports `~`) |
| `rotation_mode` | How to select next wallpaper | `random`, `sequential`, `no-repeat` |
| `fit_style` | How wallpaper fits the screen | `fill`, `fit`, `stretch`, `center`, `tile` |
| `interval` | Rotation interval in minutes (for documentation) | Integer |
| `data_directory` | Where to store state files | Path |
| `favorites_folder` | Where to copy favorited wallpapers | Path |
| `blacklist_strategy` | How to handle blacklisted images | `list` (record only) or `folder` (move files) |
| `blacklist_folder` | Folder to move blacklisted images (if strategy is `folder`) | Path |
| `log_level` | Logging verbosity | `debug`, `info`, `warn`, `error` |
| `screens` | Per-screen configuration overrides | Object (see below) |

### Per-Screen Configuration

Override settings for specific screens:

```json
{
  "images_folder": "~/Pictures/Wallpapers",
  "rotation_mode": "random",
  "screens": {
    "188178051": {
      "images_folder": "~/Pictures/PortraitWallpapers",
      "rotation_mode": "sequential",
      "fit_style": "center"
    }
  }
}
```

Use `lumen status` to find screen IDs.

### Rotation Modes

- **`random`**: Pure random selection from available images
- **`sequential`**: Go through images in alphabetical order
- **`no-repeat`**: Random selection but don't repeat until all images have been shown

### Fit Styles

- **`fill`**: Scale to fill screen, may crop edges (default)
- **`fit`**: Scale to fit within screen, may show bars
- **`stretch`**: Stretch to fill screen exactly, may distort
- **`center`**: Center without scaling
- **`tile`**: Tile the image

## Scheduling

Lumen is designed to be scheduled externally using launchd or cron.

### Using launchd (Recommended)

Create `~/Library/LaunchAgents/com.user.lumen.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.lumen</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/lumen</string>
        <string>update</string>
    </array>
    <key>StartInterval</key>
    <integer>1800</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/lumen.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/lumen.error.log</string>
</dict>
</plist>
```

Then load it:

```bash
launchctl load ~/Library/LaunchAgents/com.user.lumen.plist
```

The `StartInterval` is in seconds (1800 = 30 minutes).

### Using cron

```bash
# Edit crontab
crontab -e

# Add line to update every 30 minutes
*/30 * * * * /usr/local/bin/lumen update
```

## Scripting Examples

### Update and get result as JSON

```bash
result=$(lumen update --json)
echo $result | jq '.results[0].image_path'
```

### Cycle through favorites only

```bash
# Create a config that points to your favorites folder
lumen update --config ~/.lumen-favorites-config
```

### Random wallpaper on login

Add to your shell profile or create a login item:

```bash
lumen update
```

## Data Storage

Lumen stores its state in the data directory (default: `~/Library/Application Support/lumen/`):

- `state.json` - Current wallpaper state, history, favorites, blacklist

## Running Tests

Tests require Xcode (not just Command Line Tools) because they use XCTest:

```bash
# With Xcode installed
swift test

# Or using xcodebuild
xcodebuild test -scheme lumen
```

## Troubleshooting

### "No images found"

- Check that `images_folder` points to a valid directory
- Ensure the folder contains supported image formats (jpg, png, heic, tiff, gif, bmp)
- Check folder permissions

### "Permission denied"

macOS may require permission for Lumen to change your desktop wallpaper. This is typically granted automatically, but if you encounter issues:

1. Open System Preferences > Privacy & Security
2. Check if there are any pending permissions for your terminal or Lumen

### Wallpaper not changing

- Run `lumen status` to verify the configuration
- Try `lumen update --dry-run` to see what would happen
- Check if all images are blacklisted

### Finding screen IDs

```bash
lumen status
# Look for the "ID:" line for each screen
```

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

