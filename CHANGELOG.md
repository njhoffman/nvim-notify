# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
