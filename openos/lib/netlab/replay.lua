local utils = require("netlab.utils")

local replay = {}

function replay.new_dispatcher(timer_api)
  local dispatcher = { listeners = {} }
  function dispatcher.listen(name, handler)
    dispatcher.listeners[name] = dispatcher.listeners[name] or {}
    table.insert(dispatcher.listeners[name], handler)
  end
  function dispatcher.ignore(name, handler)
    local list = dispatcher.listeners[name]
    if not list then
      return
    end
    for i = #list, 1, -1 do
      if list[i] == handler then
        table.remove(list, i)
      end
    end
  end
  function dispatcher.emit(name, ...)
    local list = dispatcher.listeners[name]
    if not list then
      return
    end
    for _, handler in ipairs(list) do
      pcall(handler, name, ...)
    end
  end
  -- Scheduling belongs to OpenOS's event loop. A coroutine with no yield
  -- blocks replay startup instead of installing a periodic flush callback.
  if timer_api then
    dispatcher.timer = timer_api.timer
    dispatcher.cancel = timer_api.cancel
  end
  return dispatcher
end

local function read_events(path)
  local file, err = io.open(path, "r")
  if not file then
    return nil, err
  end
  local events = {}
  for line in file:lines() do
    if line ~= "" then
      local data = utils.decode_json(line)
      if data and data.type ~= "header" then
        table.insert(events, data)
      end
    end
  end
  file:close()
  return events
end

function replay.load(path)
  return read_events(path)
end

function replay.run(path, opts)
  opts = opts or {}
  local events, err = read_events(path)
  if not events then
    return false, err
  end
  local speed = tonumber(opts.speed or 1)
  if speed <= 0 then
    speed = 1
  end
  local dispatcher = opts.dispatcher
  local on_event = opts.on_event
  local dry_run = opts.dry_run
  local last_ts = nil
  for _, record in ipairs(events) do
    if last_ts then
      local delta = (record.timestamp or 0) - last_ts
      if delta > 0 then
        utils.sleep(delta / speed)
      end
    end
    last_ts = record.timestamp or last_ts
    if on_event then
      on_event(record)
    end
    if dispatcher and not dry_run then
      dispatcher.emit("modem_message", record.local_address, record.remote_address, record.local_port or record.remote_port, record.distance, table.unpack(record.payload or {}))
    end
  end
  return true
end

return replay
