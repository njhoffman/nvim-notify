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
- [ ] **`custom_wrap` drops blank lines.** (p3) [bug] Confirmed: `custom_wrap({ "a", "", "b" }, 10)` returns `{ "a", "b" }`, because
      `split_length` returns nothing for an empty line, so wrapped messages lose their paragraph breaks.
- [ ] **A test run can lose output and still pass.** (p3) [test] One full run in 16 stopped reporting one test before the end of
      `notification_spec.lua` and dropped its summary: 263 counted instead of 281, 0 failed, exit 0. Likely plenary's output
      capture, not confirmed. A failure in the lost output would go unseen. Make `scripts/test` require one summary for each
      spec file; relates to the `grep -v '0'` item above.
- [ ] **Tests and scripts write to the real log.** (p3) [test] `tests/init.vim` does not redirect the log, so test runs and any
      headless script append to `~/.local/state/nvim/logs/nvim-notify.log` next to real errors. Set `XDG_STATE_HOME` in
      `scripts/test`.
- [ ] **`render/default.lua` fails the style check.** (p3) [chore] `stylua --check` reports the `math.max` call at line 37, which
      the CI style job would reject. Run `./scripts/style`.
- [ ] **`setup({ timeout = false })` stops the render loop.** (p2) [bug] Confirmed by running it: the `x == nil and false or x`
      in `_start_timer` (`lua/notify/windows/init.lua:178`) yields nil, so `timer:start(nil)` errors and the notification
      never closes. `on_refresh` (`:172`) has the same problem with `set_repeat(false)`. Passing `timeout = false` per
      notification works. Test the default for nil explicitly instead of using `and`/`or`.
- [ ] **`scripts/test` can pass when tests fail.** (p2) [bug] `grep -v '0'` (`scripts/test:11`) drops any count containing a
      zero, so 10 or 20 failures exit 0. Found by reading the script. Match counts that are not exactly `0`:
      `grep -vx '0'`.
- [ ] **Stage returning nil crashes the window update.** (p3) [bug] `_update_window` (`lua/notify/windows/init.lua:208`) removes
      the window when goals are nil but carries on and indexes them, and the error stops the loop for every notification.
      Found by reading the code. Return right after `_remove_win`.
- [ ] **Overdamped spring returns the wrong position.** (p3) [bug] `lua/notify/animate/spring.lua:52` assigns `new_pos` twice;
      the second should be `new_vel`, which stays nil. Only reachable from custom stages with `damping > 1`, as built-in
      stages use 1 or less. Found by reading the code.
- [ ] **`available_slot` tests a function instead of the direction.** (p3) [bug] `is_increasing and interval.max`
      (`lua/notify/stages/util.lua:138`) is always truthy, so bottom-up stacking compares the wrong edge. It should use the
      local `increasing`. Found by reading the code; the visible effect has not been checked.
- [ ] **Window timers are stopped but never closed.** (p3) [bug] `_start_timer` (`lua/notify/windows/init.lua:190`) calls
      `timer:stop()` without `timer:close()`, leaving a libuv handle open for each timed notification,
      and `_remove_win` leaves the timer of a dismissed window running. Found by reading the code.

## Docs

- [ ] **Document `animate = false` for routine messages.** (p3) [docs] The config now shows its startup time with
      `animate = false`, which skips the slide-in and costs far fewer redraws than the default. The option is only described as
      being for long-running notifications in `lua/notify/init.lua:45`.
- [ ] **The stated Neovim support is out of date.** (p2) [docs] README and CI claim 0.9.5 and 0.10.2, but the code calls
      `nvim__redraw` (0.10+) and the two-argument `vim.str_utfindex(s, "utf-32")` (0.11+). Pick a minimum, then update
      `README.md`, `CLAUDE.md` and the matrix in `.github/workflows/workflow.yaml`. Not run on those versions; found by
      reading the code.
- [ ] **CHANGELOG has a gap from 3.17 to 3.21.** (p3) [docs] Its newest released section was 3.16.0 while `package.json` was at
      3.21.0, and tag `v3.21.0` does not exist. Backfill from the tags and commit messages.

## Cleanup

- [ ] **Treesitter override depends on private fields.** (p3) [refactor] `_redefine_treesitter` reads `query.hl_cache` and
      `query._query` (`lua/notify/service/buffer/highlights.lua:139`), which Neovim can change without notice, and nothing
      guards the call. It works on 0.13-dev today.
- [ ] **`border_padding` assumes a border on both sides.** (p3) [refactor] `lua/notify/stages/util.lua:55` always returns 2 for
      any border, as its own TODO comment notes, so a border list with missing sides stacks with the wrong spacing.
