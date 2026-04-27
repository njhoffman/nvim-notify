local basic_body = function(props)
  return "Rendering " .. props.name .. "(" .. props.render .. ") level: " .. props.level
end

local basic_wide_body = function(props)
  return props.name
    .. "("
    .. props.render
    .. ") level: "
    .. props.level
    .. "Use parentheses to group and prioritize calculations."
    .. "For example, <Ctrl>+<R>=3*(4+2) will calculate the result of the expression 3*(4+2)."
end

return {
  basic = { body = basic_body },
  basic_wide = { body = basic_wide_body },
  title_1 = {
    title = function(props)
      return props.name .. "(" .. props.render .. ")"
    end,
  },
  title_2 = {
    title = function(props)
      return { props.name .. "(" .. props.render .. ")", "10:50:32" }
    end,
  },
  title_1_table = {
    title = function(props)
      return { props.name .. "(" .. props.render .. ")" }
    end,
  },
  title_right = {
    title = function(props)
      return { "", props.name .. "(" .. props.render .. ")" }
    end,
  },
  -- basic_multi = { },
  -- title_1_long = { },
  -- title_2_long = { },
  -- replace = { },
  -- duplicate = { },
}
