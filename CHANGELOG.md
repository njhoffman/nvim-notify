# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.21.5] - 2026-11-05

### Fixed
- `scripts/test` no longer exits 0 when the number of failures contains a zero, such as 10 or 20. It
  also fails if nvim exits with an error, if no spec files are found, or if a spec file reports no
  summary.

## [3.21.4] - 2026-11-05

### Fixed
- `compact` notifications no longer lose the end of their first line. A message that only overflows
  because of its icon and title now wraps, so it takes more rows than before.
- `wrapped-compact` and `wrapped-minimal` no longer run past `max_width` on the first line.

### Changed
- `custom_wrap` now counts `pad_left` towards `max_width`, and accepts `first_line_reserve`.

## [3.21.3] - 2026-11-05

### Fixed
- Wrapped notifications no longer show garbage where a line break fell inside an icon or accented
  character. Lines now wrap by display width, so wide characters such as CJK and emoji fit the window.

## [3.21.2] - 2026-11-05

### Fixed
- Inline highlights now land on the right text in `compact` and `wrapped-*` notifications with more
  than one line, or with a message that wraps, instead of being lost or shifted.
- `wrapped-compact` no longer logs errors and loses highlights when a notification has a title, and
  no longer shows the word "nil" for an empty message.
- `minimal` accounts for the duplicate count when placing inline highlights.

### Changed
- Failed highlight errors in `nvim-notify.log` now include the line, columns and line length.

## [3.21.1] - 2026-11-05

### Changed
- Fading a notification no longer repaints the editor and the other notifications. Three notifications
  now use about 85% less CPU over their lifetime, with the same colours on screen.
- The render loop slows to two ticks a second while every notification is waiting out its timeout, and
  wakes immediately for new notifications, replacements, closed windows and resizes.

### Fixed
- Faded text now returns to its exact colour at full opacity instead of stopping one step short.

## [3.16.0] - 2025-11-07

### Changed
- Updated deprecated Neovim API calls for Neovim 0.9+ compatibility
  - `vim.loop` → `vim.uv` (with fallback for older versions) in `lua/notify/windows/init.lua`
  - `nvim_buf_set_option`/`nvim_buf_get_option` → `nvim_set_option_value`/`nvim_get_option_value` in tests
  - Updated `bit` library usage to support both bit32 and LuaJIT's bit library in `lua/notify/util/init.lua`
- Updated CI/CD workflow to test against Neovim 0.9.5, 0.10.2, and nightly
- Upgraded GitHub Actions from v2 to v4 and Node.js from version 18 to 20
- Updated Ubuntu runner from 20.04 to 22.04
- Updated README.md to specify Neovim 0.9.0+ requirement

### Removed
- Removed unused `instance.clear_dupes()` function from `lua/notify/instance.lua`

### Added
- Created CLAUDE.md for AI-assisted development guidance
- Created CHANGELOG.md for version tracking
- Created package.json for semantic-release integration
- Added semantic-release plugins for automatic changelog and version management

## [3.15.0] - Previous Release

See GitHub releases for previous version history.
