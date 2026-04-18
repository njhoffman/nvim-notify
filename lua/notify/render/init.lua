---@tag notify-render
---@text
--- Notification buffer rendering
---
--- Custom rendering can be provided by both the user config in the setup or on
--- an individual notification using the `render` key.
--- The key can either be the name of a built-in renderer or a custom function.
---
--- Built-in renderers:
--- - `"default"`
--- - `"minimal"`
--- - `"simple"`
--- - `"compact"`
--- - `"wrapped-default"`
--- - `"wrapped-compact"`
--- - `"wrapped-minimal"`
--- - `"auto"` — pick a renderer at notify-time from a rule-based ruleset
---   (see `notify.render.base.dispatch`).
---
--- Custom functions should accept a buffer, a notification record and a highlights table
---
--- >
---     render: fun(buf: integer, notification: notify.Record, highlights: notify.Highlights, config)
--- <
--- You should use the provided highlight groups to take advantage of opacity
--- changes as they will be updated as the notification is animated
---
--- ### Auto renderer and rulesets
---
--- Set `render = "auto"` to let nvim-notify pick a renderer per notification
--- by walking a list of rules. Each rule is a table
--- `{ when = fn(notif, config) -> bool, pick = <renderer name> }`; a rule
--- with no `when` always matches. First match wins.
---
--- Two built-in rulesets ship:
--- - `"default"` — minimal / wrapped-minimal / wrapped-default / default,
---   depending on whether the notification has a title and whether its body
---   fits within `config.max_width`.
--- - `"compact"` — compact / wrapped-compact.
---
--- Selection precedence:
--- 1. `config.render_ruleset = "<name>"` (explicit, overrides everything)
--- 2. `config.compact = true` → `"compact"`
--- 3. otherwise → `"default"`
---
--- Register or extend rulesets: ~
--- >lua
---     local base = require("notify.render.base")
---     base.register_ruleset("mine", {
---       { when = function(n) return n.level == "ERROR" end, pick = "simple" },
---       { pick = "default" },
---     })
---     base.add_rule("default", {
---       when = function(n) return n.icon == "!" end,
---       pick = "simple",
---     })
--- <

---@class notify.Highlights
---@field title string
---@field icon string
---@field border string
---@field body string

local M = {}

setmetatable(M, {
  __index = function(_, key)
    return require("notify.render." .. key)
  end,
})

return M
