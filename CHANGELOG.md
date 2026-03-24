# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

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
