# TODO

Open work on this fork, from profiling startup in the Neovim config that uses it (`fps = 30`,
`stages = "fade_in_slide_out"`, `timeout = 5000`).

Reviewed: 2026-11-05

## Performance

- [x] **The render loop runs at full fps while nothing moves.** (p2) [perf] Once every window is settled in its timed stage
      the loop runs every 500 ms instead of every frame, and timers, new notifications, replacements, closed windows and
      resizes wake it at once. Measured over 2 s of hold with three windows: 61 renders down to about 10, and 60-110 ms of
      CPU down to under 10 ms. It keeps a slow tick rather than stopping, so custom stages with changing goals and windows
      closed with `:noautocmd` are still noticed.
- [x] **Every open window repaints on each animation frame.** (p2) [perf] Confirmed: `nvim_set_hl` on a global group repaints
      every window. Faded colours now live in a highlight namespace per window (`nvim_win_set_hl_ns`), unchanged colours are
      not rewritten, and each tick flushes once and only if something changed. Measured over three notifications: 476 line
      updates per window down to 191, 37,543 terminal cells down to 27,340, and 870-1,160 ms of CPU down to 140-160 ms.
      Fade colours match the old code frame for frame. `winblend` was rejected: it saves about the same CPU but shows
      the text underneath and ignores `background_colour`.
- [ ] **Slide-ins take longer when others are open.** (p3) [perf] One startup with three notifications: the first animated for
      about 0.6 s, the second about 1.3 s and the third about 1.4 s, at about 28 fps. Together they kept the screen busy for
      about 3 s, which the config's benchmark counted as startup time. A single measurement; the cause is not known.
      Stage frequencies are in `lua/notify/stages/fade_in_slide_out.lua`. Measure again first: the repaint work removed
      above may have been part of the cause.

## Bugs

- [x] **Render errors fill the log.** (p2) [bug] Three causes, all reproduced and fixed: `wrapped-compact` wrote past its title
      row, `highlight_inline` added the first row's prefix width to every row, and wrapped renderers used ranges measured
      against the unwrapped message. Inline highlights now land on the right text, split across wrapped lines where needed,
      and the log line records the position and line length. Which cause produced how many of the logged 1,002 is not
      known, so watch `nvim-notify.log` for any that remain.
- [x] **Wrapping cuts multibyte characters in half.** (p2) [bug] `split_length` (`lua/notify/render/base.lua`) now walks UTF-8
      characters and counts display cells, so wide characters count as two, combining characters stay with their base, and
      invalid bytes pass through unchanged. `segments` from `custom_wrap` stay in bytes.
- [x] **`compact` and `wrapped-compact` clip message text.** (p2) [bug] The `compact` rule ignored the prefix, so a 28-cell titled
      message at `max_width = 30` stayed on a 42-cell line and lost 12 letters. `wrapped-compact` added its prefix after
      wrapping and lost 3. The rule now measures the rendered line, and `custom_wrap` counts `pad_left` and can reserve
      space on the first line.
- [ ] **Long titles are clipped.** (p3) [bug] A title wider than `max_width` is cut off at the window edge in `wrapped-compact` and
      `wrapped-default` (measured: 13 and 14 letters of a 40-letter title at width 30), and `max_line_width` does not count it.
      Decide whether to truncate with an ellipsis or wrap the title.
- [x] **`custom_wrap` drops blank lines.** (p3) [bug] Blank lines now survive wrapping, so wrapped messages keep their paragraph
      breaks.
- [x] **A test run can lose output and still pass.** (p3) [test] `scripts/test` now requires one summary for each spec file, so
      a run that loses a summary fails instead of passing. The cause is still not confirmed; one full run in 16 lost
      output, so an occasional failure reading "N of M spec files reported a summary" is this, and a rerun is the check.
- [x] **Tests and scripts write to the real log.** (p3) [test] `scripts/test` now uses a temporary `XDG_STATE_HOME`.
- [x] **`render/default.lua` fails the style check.** (p3) [chore] Formatted; `stylua --check lua tests` passes.
- [x] **`setup({ timeout = false })` stops the render loop.** (p2) [bug] `_start_timer` and `on_refresh` now share one timeout lookup: a
      notification's own number wins, `true` or nil means the configured default, and anything else stays until dismissed.
      Replacing a notification with `timeout = false` also cancels its running timer.
- [x] **`scripts/test` can pass when tests fail.** (p2) [bug] Reproduced with real specs: 1 failure exited 1, 10 failures exited
      0, and CI's `release` job depends on this result. The script now compares counts numerically and respects nvim's
      exit status, which it used to discard.
- [x] **Stage returning nil crashes the window update.** (p3) [bug] `_update_window` now removes the window and returns, including when
      the nil comes from a later stage of an `animate = false` notification.
- [x] **Overdamped spring returns the wrong position.** (p3) [bug] `lua/notify/animate/spring.lua` now sets `new_vel`.
- [x] **`available_slot` tests a function instead of the direction.** (p3) [bug] Now uses `increasing`, so bottom-up stacking checks the window's top
      edge and no longer places windows above the screen.
- [x] **Window timers are stopped but never closed.** (p3) [bug] Timers are now closed when they fire, and when their window is removed.
      A callback already queued for a stopped timer is ignored.

## Cleanup

- [ ] **`notify.async` discards the caller's callbacks.** (p3) [bug] `instance.async` (`lua/notify/instance.lua:187`) overwrites
      `opts.on_open` and `opts.on_close` with its own channels, so callbacks passed to it never run. Call both.
- [ ] **The docgen workflow cannot run.** (p3) [chore] `.github/workflows/docgen.yaml` uses `ubuntu-20.04` and Neovim 0.5.1, far
      below the 0.11 minimum, and `actions/*@v2`. `doc/nvim-notify.txt` was edited by hand in this change as a result.
      Found by reading the workflow; its CI status has not been checked.

- [ ] **Treesitter override depends on private fields.** (p3) [refactor] `_redefine_treesitter` reads `query.hl_cache` and
      `query._query` (`lua/notify/service/buffer/highlights.lua:139`), which Neovim can change without notice, and nothing
      guards the call. It works on 0.13-dev today.
- [ ] **`border_padding` assumes a border on both sides.** (p3) [refactor] `lua/notify/stages/util.lua:55` always returns 2 for
      any border, as its own TODO comment notes, so a border list with missing sides stacks with the wrong spacing.

## Completed

### Docs (completed 2026-11-05)

- [x] **Document `animate = false` for routine messages.** (p3) [docs] Described in `lua/notify/init.lua` and `doc/nvim-notify.txt`.
- [x] **The stated Neovim support is out of date.** (p2) [docs] Minimum is now 0.11, in `README.md`, `CLAUDE.md` and the CI matrix. Measured with
      real builds: 0.11.0 passes the whole suite, while 0.10.2 fails 38 tests on `vim.str_utfindex`. CI's download
      URL also 404s for 0.11 and nightly, because the asset is now `nvim-linux-x86_64.tar.gz`; fixed there and in `Dockerfile`.
      Removed the code that only ran on older versions.
- [x] **CHANGELOG has a gap from 3.17 to 3.21.** (p3) [docs] Backfilled from tags and commit messages, and added tag `v3.21.0`.
