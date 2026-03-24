# Releasing Lumen

This project is distributed through a custom Homebrew tap first.

## Prerequisites

- A clean `master` branch with CI passing
- Access to:
  - `dacostarepublic/lumen` (this repo)
  - `dacostarepublic/homebrew-tap` (tap repo)
- `gh` CLI authenticated

## 1) Prepare the release commit

1. Update version in `Sources/lumen/Lumen.swift` (`Lumen.configuration.version`).
2. Update `CHANGELOG.md`:
   - Move relevant notes from `Unreleased` into a version section, e.g. `## [1.1.0] - 2026-03-24`.
3. Run checks:

```bash
make ci
```

## 2) Create and publish a tag

```bash
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0
```

Pushing the tag triggers `.github/workflows/release.yml`, which builds and uploads release assets.

## 3) Compute release artifact checksum

The release workflow uploads `lumen-vX.Y.Z-macos.tar.gz` and its checksum file.
If you need to recompute locally:

```bash
make release-artifact VERSION=1.1.0
curl -L -o /tmp/lumen-v1.1.0-macos.tar.gz https://github.com/dacostarepublic/lumen/releases/download/v1.1.0/lumen-v1.1.0-macos.tar.gz
shasum -a 256 /tmp/lumen-v1.1.0-macos.tar.gz
```

## 4) Update tap formula

Use `packaging/homebrew/lumen.rb` in this repo as the source template.

In `dacostarepublic/homebrew-tap/Formula/lumen.rb` update:
- `url` to the new release artifact
- `sha256` to the computed checksum
- `version` (if explicitly pinned)

Then run locally in the tap repo:

```bash
brew audit --strict --formula ./Formula/lumen.rb
brew install ./Formula/lumen.rb
brew test lumen
```

Commit and push the tap change.

## 5) Verify install path from a clean environment

```bash
brew untap dacostarepublic/tap || true
brew tap dacostarepublic/tap
brew install lumen
lumen --version
```

## Notes

- Keep formula tests non-interactive (`--version`, `config path`, etc.).
- Avoid invoking wallpaper-changing commands in formula tests.
- If macOS wallpaper internals change, keep `apply_all_spaces` optional and default `false`.
