# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

## [2.0.0] - 2026-03-24

### Added
- New `lumen daemon` command with interval-based rotation plus space-change and wake re-apply handling.
- New `lumen unban` and `lumen open` commands for blacklist recovery and quick wallpaper reveal/open flows.
- New rotation mode `weighted-random` and config options `recursive` and `prefer_matching_aspect`.

### Changed
- `lumen set` now accepts the wallpaper path as a positional argument (legacy `--file` still works).
- State writes are now atomic with corruption fallback and migration to state schema v2.
- `lumen status` now caches image discovery during a run to avoid repeated folder scans.

### Removed
- Removed unused monitor and state error surface area and dead helper APIs.

## [1.1.0] - 2026-03-24

### Added
- Homebrew-oriented release and CI documentation.
- Config option `apply_all_spaces` to enable best-effort multi-space wallpaper sync.
- MIT `LICENSE` file for distribution packaging.

### Changed
- Improved CLI input validation and non-zero exit behavior for operational failures.
- Hardened wallpaper apply path to keep private macOS store mutation opt-in.
- Updated sample config to be valid JSON and include new options.

### Removed
- Internal debug artifact file from source tree.
