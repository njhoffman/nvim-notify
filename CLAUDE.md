# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

nvim-notify is a fancy, configurable notification manager for NeoVim. It provides animated notification windows with customizable rendering styles, animation stages, and highlight groups. The plugin can replace vim.notify to intercept all notifications in NeoVim.

## Development Commands

### Testing
- Run all tests: `./scripts/test`
- Run a single test file: `./scripts/test tests/unit/init_spec.lua`
- Tests use plenary.nvim and run headless with the init file at `tests/init.vim`
- **Note**: Tests require plenary.nvim to be installed in Neovim's runtime path
- CI tests against Neovim 0.9.5, 0.10.2, and nightly

### Code Style
- Format code: `./scripts/style` (runs stylua on lua/ and tests/)
- Check formatting: `stylua --check lua/ tests/`
- Style configuration is in `stylua.toml` (100 column width, 2 space indentation)

### Documentation
- Generate docs: `./scripts/docgen`
- Runs `scripts/gendocs.lua` headless to generate vim help docs

### Version Management
- Version is tracked in `package.json` and git tags
- Releases are automated via semantic-release on master branch
- Use conventional commit format with gitmoji for commit messages
- CHANGELOG.md is automatically updated on minor/major version bumps

## Architecture

### Core Components

**Notification Flow:**
1. `lua/notify/init.lua` - Main entry point, provides public API
2. `lua/notify/instance.lua` - Creates notification instances with independent config
3. `lua/notify/service/notification.lua` - Notification object model
4. `lua/notify/service/init.lua` (NotificationService) - Manages pending notification queue and rendering loop
5. `lua/notify/service/buffer/init.lua` (NotificationBuf) - Renders notification content to buffers
6. `lua/notify/windows/init.lua` (WindowAnimator) - Manages window animation states and stages

**Key Architecture Patterns:**
- **Instance-based design**: Global instance created on setup, but supports multiple independent instances with separate configs
- **Service/Queue pattern**: NotificationService maintains a FIFO queue and runs a render loop at configured FPS
- **Stage-based animation**: WindowAnimator progresses windows through animation stages (open → intermediate states → close)
- **Spring physics**: Animations use dampened spring algorithm for natural motion (see `lua/notify/animate/spring.lua`)

### Directory Structure

- `lua/notify/`
  - `init.lua` - Public API and global instance
  - `instance.lua` - Instance factory, handles notification lifecycle
  - `config/` - Configuration system and highlight management
  - `service/` - NotificationService (queue manager) and NotificationBuf (buffer renderer)
  - `windows/` - WindowAnimator (animation state machine)
  - `animate/` - Spring animation physics
  - `stages/` - Built-in animation stage configurations (fade, slide, static, etc.)
  - `render/` - Built-in rendering styles (default, minimal, compact, etc.)
  - `parsers/` - Message parsing and formatting utilities
  - `util/` - Utility functions (queue, string operations)
  - `integrations/` - FZF integration
- `lua/telescope/_extensions/notify.lua` - Telescope extension for notification history

### Animation System

Animations work in stages defined by functions that return window config goals:

1. **Stage 1 (open)**: Returns `nvim_open_win` config with optional `opacity` field
2. **Subsequent stages**: Return goal values for `row`, `col`, `width`, `height`, `opacity`
   - Instant changes: Pass numbers directly
   - Animated transitions: Pass tables like `{goal_value, frequency=1, damping=1}`
3. **Timed stage**: One stage must return `time=true` to indicate the notification display timeout
4. **Last stage**: When complete, window closes

See `lua/notify/stages/` for examples of built-in stage configurations.

### Configuration System

Config in `lua/notify/config/init.lua` uses a function-based accessor pattern where `config.setup()` returns an object with functions like `config.level()`, `config.timeout()`, etc. This allows lazy evaluation and dynamic values (e.g., `max_width` can be a function).

### Duplicate Merging

When `merge_duplicates` is enabled, the system compares new notifications against visible ones by checking message, level, title, and icon equality. If duplicates exceed the threshold, the notification replaces the existing one using the `replace` mechanism.

## Common Patterns

### Creating Notifications
- Simple: `require("notify")("message", "error")`
- With options: `require("notify")("message", "info", {title = "Title", timeout = 5000})`
- Async (requires plenary): `require("notify").async("message").events.open()` or `.events.close()`

### Replacing Notifications
Pass `replace = notification_record.id` or `replace = notification_record` in options to update an existing notification. Unspecified options are inherited from the original.

### Custom Rendering
Render functions receive a buffer number and notification object, must call `vim.api.nvim_buf_set_lines()` and return `{width, height, highlights}`. See `lua/notify/render/base.lua` for base renderer utilities.

### Testing
Tests use plenary.nvim's async test framework. Use `a.it()` for async tests and `async_notify().events.open()` or `.close()` to wait for notification lifecycle events.

## Important Implementation Notes

- The render loop runs at configured FPS (default 30) when notifications are active
- Windows must not be current window to close/advance stages (checked in multiple places)
- Highlight groups follow pattern `Notify<LEVEL><Section>` (e.g., NotifyERRORBorder)
- Background color for opacity changes must be RGB hex or highlight group with bg value
- Spring animation state maintains position and velocity for smooth physics-based motion
- NotificationBuf caches rendered content; call `:render()` after changes
