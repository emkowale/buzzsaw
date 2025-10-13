# Changelog

All notable changes to **Buzzsaw** will be documented in this file.

## [1.1.4] - 2025-10-13
### Added
- Built-in **GitHub updater**: update via WordPress Updates using GitHub Releases.
- README.md and CHANGELOG.md bundled.

## [1.1.3] - 2025-10-13
### Added
- README.md as a human-readable blueprint with full source.
- CHANGELOG.md introduced.

## [1.1.2] - 2025-10-13
### Changed
- **Hardcoded** base path (`/mnt/ccpi/mnt/nas/Website-Orders`) via `BUZZSAW_BASE_PATH`.
- Settings page made **read-only**; shows existence/writable checks.

## [1.1.0] - 2025-10-13
### Changed
- Switched from remote REST to **local mount** copy strategy.
- Added Local Base Path setting (superseded by 1.1.2 hardcode).

## [1.0.1] - 2025-10-13
### Changed
- Limited to Featured Image + `original-art` only.
- Path segment sanitization.

## [1.0.0] - 2025-10-13
### Added
- Initial scaffold with admin UI (Settings + Push), background processing, progress pie, and nightly cron.
