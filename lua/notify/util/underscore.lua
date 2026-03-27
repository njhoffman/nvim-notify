local _ = {}

function _.any(list, func)
  if _.isEmpty(list) then
    return false
  end

  func = func or _.identity

  local found = false
  _.each(list, function(value, index, object)
    if not found and func(value, index, object) then
      found = true
    end
  end)

  return found
end

function _.include(list, v)
  return _.any(list, function(value)
    return v == value
  end)
end

_.contains = _.include

function _.isArray(value)
  return type(value) == "table" and (value[1] or next(value) == nil)
end

function _.isString(value)
  return type(value) == "string"
end

function _.isNumber(value)
  return type(value) == "number"
end

function _.isFunction(value)
  return type(value) == "function"
end

function _.isObject(value)
  return type(value) == "table"
end

function _.isEmpty(value)
  if not value then
    return true
  elseif _.isArray(value) or _.isObject(value) then
    return next(value) == nil
  elseif _.isString(value) then
    return string.len(value) == 0
  else
    return false
  end
end

function _.each(list, func)
  local pairing = pairs
  if _.isArray(list) then
    pairing = ipairs
  end

  for index, value in pairing(list) do
    func(value, index, list)
  end
end

function _.flatten(list, shallow, output)
  output = output or {}

  _.each(list, function(value)
    if _.isArray(value) then
      if shallow then
        _.each(value, function(v)
          table.insert(output, v)
        end)
      else
        _.flatten(value, false, output)
      end
    else
      table.insert(output, value)
    end
  end)

  return output
end

function _.pick(list, ...)
  local keys = _.flatten({ ... })

  local array = {}
  _.each(keys, function(key)
    if list[key] then
      array[key] = list[key]
    end
  end)

  return array
end

function _.omit(list, ...)
  local keys = _.flatten({ ... })

  local array = {}
  _.each(list, function(value, key)
    if not _.contains(keys, key) then
      array[key] = list[key]
    end
  end)

  return array
end

return _
