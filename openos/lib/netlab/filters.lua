local filters = {}

local function matches_port(event, filter)
  if not filter then
    return true
  end
  if filter.port then
    return event.local_port == filter.port or event.remote_port == filter.port
  end
  if filter.ports then
    return filter.ports[event.local_port] or filter.ports[event.remote_port]
  end
  return true
end

local function matches_remote(event, remote)
  if not remote then
    return true
  end
  return tostring(event.remote_address or "") == tostring(remote)
end

local function matches_direction(event, direction)
  if not direction then
    return true
  end
  return event.direction == direction
end

local function matches_payload(event, filter)
  if not filter then
    return true
  end
  local preview = tostring(event.preview or "")
  if filter.payload and filter.payload ~= "" then
    return preview:find(filter.payload, 1, true) ~= nil
  end
  if filter.payload_regex and filter.payload_regex ~= "" then
    local ok, result = pcall(function()
      return preview:find(filter.payload_regex)
    end)
    if not ok then
      return false
    end
    return result ~= nil
  end
  return true
end

function filters.match(event, filter)
  if not filter then
    return true
  end
  if not matches_port(event, filter) then
    return false
  end
  if not matches_remote(event, filter.remote) then
    return false
  end
  if not matches_direction(event, filter.direction) then
    return false
  end
  if not matches_payload(event, filter) then
    return false
  end
  return true
end

return filters
