local args = { ... }

local component = require("component")
local event = require("event")
local term = require("term")
local netlab = require("netlab")

local utils = netlab.utils
local Ring = netlab.ring
local Filters = netlab.filters
local Capture = netlab.capture
local Replay = netlab.replay

local function load_config()
  local ok, config = pcall(dofile, "/etc/netlab/config.lua")
  if ok and type(config) == "table" then
    return config
  end
  return {
    capture_dir = "/home/netlab/captures",
    ring_size = 512,
    sample_rate = 1,
    flush_interval = 2,
    preview_len = 64,
    stats_window = 5,
    ui_refresh = 0.1,
  }
end

local function print_usage()
  print([[netlab - OpenComputers network debugger

Usage:
  netlab
  netlab replay <file> [--speed <factor>] [--dry-run]
  netlab send --to <addr> --port <p> --data <string>
  netlab ping --to <addr> --port <p> [--timeout <sec>]
  netlab ping --listen --port <p>
]])
end

local function parse_flags(input)
  local opts = { args = {} }
  local i = 1
  while i <= #input do
    local token = input[i]
    if token:sub(1, 2) == "--" then
      local key = token:sub(3)
      local value = input[i + 1]
      if not value or value:sub(1, 2) == "--" then
        opts[key] = true
      else
        opts[key] = value
        i = i + 1
      end
    else
      opts.args[#opts.args + 1] = token
    end
    i = i + 1
  end
  return opts
end

local function select_modem()
  local addresses = {}
  for address in component.list("modem") do
    addresses[#addresses + 1] = address
  end
  if #addresses == 0 then
    return nil, "No modem found. Install or attach a modem to this computer."
  end
  if #addresses == 1 then
    return component.proxy(addresses[1])
  end
  term.clear()
  term.setCursor(1, 1)
  print("Multiple modems detected:")
  for index, address in ipairs(addresses) do
    print(string.format("  %d) %s", index, address))
  end
  io.write("Select modem [1-" .. #addresses .. "]: ")
  local choice = term.read()
  if choice then
    choice = choice:gsub("\n", "")
  end
  choice = tonumber(choice) or 1
  return component.proxy(addresses[math.min(math.max(choice, 1), #addresses)])
end

local function new_stats(window)
  local stats = {
    window = window or 5,
    total = 0,
    bytes = 0,
    per_remote = {},
    per_port = {},
    recent = {},
    errors = 0,
  }
  function stats:reset()
    self.total = 0
    self.bytes = 0
    self.per_remote = {}
    self.per_port = {}
    self.recent = {}
    self.errors = 0
  end
  function stats:add(record)
    self.total = self.total + 1
    self.bytes = self.bytes + (record.payload_len or 0)
    local remote = record.remote_address or "<unknown>"
    self.per_remote[remote] = (self.per_remote[remote] or 0) + 1
    local port = record.local_port or record.remote_port or 0
    self.per_port[port] = (self.per_port[port] or 0) + 1
    table.insert(self.recent, record.timestamp or utils.now())
  end
  function stats:rate(now)
    local cutoff = now - self.window
    while self.recent[1] and self.recent[1] < cutoff do
      table.remove(self.recent, 1)
    end
    return #self.recent / self.window
  end
  function stats:avg_size()
    if self.total == 0 then
      return 0
    end
    return self.bytes / self.total
  end
  return stats
end

local function top_entries(map, limit)
  local items = {}
  for key, value in pairs(map) do
    items[#items + 1] = { key = key, value = value }
  end
  table.sort(items, function(a, b) return a.value > b.value end)
  local out = {}
  for i = 1, math.min(limit, #items) do
    out[#out + 1] = items[i]
  end
  return out
end

local function format_event(record, width)
  local time = string.format("%7.2f", record.timestamp or 0)
  local direction = record.direction == "outbound" and "->" or "<-"
  local remote = tostring(record.remote_address or "?")
  if #remote > 8 then
    remote = remote:sub(1, 8)
  end
  local local_port = record.local_port or "-"
  local remote_port = record.remote_port or "-"
  local length = record.payload_len or 0
  local distance = record.distance and string.format(" d=%s", record.distance) or ""
  local preview = record.preview or ""
  local line = string.format("%s %s %-8s lp=%-5s rp=%-5s len=%-4s%s %s", time, direction, remote, local_port, remote_port, length, distance, preview)
  if #line > width then
    line = line:sub(1, width)
  end
  return line
end

local function prompt_line(label, default)
  term.clearLine()
  io.write(label)
  if default then
    io.write(" [" .. tostring(default) .. "]")
  end
  io.write(": ")
  local input = term.read()
  if not input then
    return default
  end
  input = input:gsub("\n", "")
  if input == "" then
    return default
  end
  return input
end

local function run_tui(options)
  local config = load_config()
  local modem
  if not options or not options.replay_file then
    local err
    modem, err = select_modem()
    if not modem then
      print(err)
      return 1
    end
  end

  local ring = Ring.new(config.ring_size)
  local stats = new_stats(config.stats_window)
  local state = {
    paused = false,
    filter = {},
    status = "live",
    message = "",
  }

  local function on_record(record)
    stats:add(record)
    if not state.paused then
      state.dirty = true
    end
  end

  local dispatcher = options and options.dispatcher
  local event_api = dispatcher or event
  local capture = Capture.new({
    ring = ring,
    config = config,
    event_api = event_api,
    modem = modem,
    on_event = on_record,
  })

  if not (options and options.replay_file) then
    capture:wrap_modem()
    capture:start()
  end

  local function render()
    local gpu = component.gpu
    local width, height = gpu.getResolution()
    term.setCursor(1, 1)
    term.clearLine()
    local header = string.format("netlab [%s] (p pause, f filter, s save, e export, r replay, q quit) %s", state.status, state.message)
    io.write(header:sub(1, width))

    local events = ring:items()
    local filtered = {}
    for _, record in ipairs(events) do
      if Filters.match(record, state.filter) then
        filtered[#filtered + 1] = record
      end
    end
    local available = height - 4
    local start = math.max(1, #filtered - available + 1)
    for i = 1, available do
      term.setCursor(1, 1 + i)
      term.clearLine()
      local record = filtered[start + i - 1]
      if record then
        io.write(format_event(record, width))
      end
    end

    local now = utils.now()
    term.setCursor(1, height - 2)
    term.clearLine()
    local rate = stats:rate(now)
    io.write(string.format("rate: %.1f msg/s  avg size: %.1f bytes  total: %d  errors: %d", rate, stats:avg_size(), stats.total, capture.error_count or 0):sub(1, width))
    term.setCursor(1, height - 1)
    term.clearLine()
    local talkers = top_entries(stats.per_remote, 3)
    local talker_text = {}
    for _, item in ipairs(talkers) do
      talker_text[#talker_text + 1] = string.format("%s(%d)", item.key, item.value)
    end
    io.write(("talkers: " .. table.concat(talker_text, ", ")):sub(1, width))
    term.setCursor(1, height)
    term.clearLine()
    local ports = top_entries(stats.per_port, 3)
    local port_text = {}
    for _, item in ipairs(ports) do
      port_text[#port_text + 1] = string.format("%s(%d)", item.key, item.value)
    end
    io.write(("ports: " .. table.concat(port_text, ", ")):sub(1, width))
  end

  local function handle_filter()
    term.setCursor(1, 1)
    term.clear()
    local port = prompt_line("Filter port", state.filter.port)
    local remote = prompt_line("Remote address", state.filter.remote)
    local payload = prompt_line("Payload substring", state.filter.payload)
    local payload_regex = prompt_line("Payload regex", state.filter.payload_regex)
    local direction = prompt_line("Direction (inbound/outbound)", state.filter.direction)
    state.filter = {
      port = tonumber(port) or nil,
      remote = remote ~= "" and remote or nil,
      payload = payload ~= "" and payload or nil,
      payload_regex = payload_regex ~= "" and payload_regex or nil,
      direction = direction ~= "" and direction or nil,
    }
    state.dirty = true
  end

  local function start_capture_file()
    utils.ensure_dir(config.capture_dir)
    local filename = string.format("%s/capture-%d.jsonl", config.capture_dir, os.time())
    local ok, err = capture:start_file(filename, { mode = state.status })
    if ok then
      state.message = "capturing to " .. filename
    else
      state.message = "capture failed: " .. tostring(err)
    end
    state.dirty = true
  end

  local function stop_capture_file()
    capture:stop_file()
    state.message = "capture stopped"
    state.dirty = true
  end

  local function export_capture()
    utils.ensure_dir(config.capture_dir)
    local filename = string.format("%s/export-%d.jsonl", config.capture_dir, os.time())
    local ok, err = Capture.export(ring, filename, { mode = state.status })
    if ok then
      state.message = "exported to " .. filename
    else
      state.message = "export failed: " .. tostring(err)
    end
    state.dirty = true
  end

  local replay_state = nil
  local replay_dispatcher = nil

  local function start_replay(file, speed, dry_run)
    local events, err = Replay.load(file)
    if not events then
      state.message = "replay error: " .. tostring(err)
      state.dirty = true
      return
    end
    capture:stop()
    capture:unwrap_modem()
    replay_dispatcher = Replay.new_dispatcher()
    capture = Capture.new({
      ring = ring,
      config = config,
      event_api = replay_dispatcher,
      modem = modem,
      on_event = on_record,
    })
    capture:start()
    replay_state = {
      events = events,
      index = 1,
      base_ts = events[1] and events[1].timestamp or 0,
      start_time = utils.now(),
      speed = speed or 1,
      dry_run = dry_run,
    }
    state.status = "replay"
    state.message = file
    ring:clear()
    stats:reset()
    state.dirty = true
  end

  local function update_replay()
    if not replay_state then
      return
    end
    local now = utils.now()
    while replay_state.index <= #replay_state.events do
      local record = replay_state.events[replay_state.index]
      local target = replay_state.start_time + ((record.timestamp or 0) - replay_state.base_ts) / replay_state.speed
      if now < target then
        break
      end
      if replay_state.dry_run then
        capture:record(record)
      else
        replay_dispatcher.emit("modem_message", record.local_address, record.remote_address, record.local_port or record.remote_port, record.distance, table.unpack(record.payload or {}))
      end
      replay_state.index = replay_state.index + 1
    end
    if replay_state.index > #replay_state.events then
      state.message = "replay finished"
      replay_state = nil
      state.dirty = true
    end
  end

  if options and options.replay_file then
    start_replay(options.replay_file, options.speed or 1, options.dry_run)
  end

  state.dirty = true
  while true do
    update_replay()
    if state.dirty then
      render()
      state.dirty = false
    end
    local name, _, char = event.pull(config.ui_refresh, "key_down")
    if name == "key_down" and char and char > 0 then
      local key = string.char(char)
      if key == "q" then
        break
      elseif key == "p" then
        state.paused = not state.paused
        state.message = state.paused and "paused" or "resumed"
        state.dirty = true
      elseif key == "c" then
        ring:clear()
        stats:reset()
        state.message = "cleared"
        state.dirty = true
      elseif key == "f" then
        handle_filter()
      elseif key == "s" then
        if capture.file then
          stop_capture_file()
        else
          start_capture_file()
        end
      elseif key == "e" then
        export_capture()
      elseif key == "r" then
        term.setCursor(1, 1)
        term.clear()
        local file = prompt_line("Replay file", config.capture_dir .. "/")
        local speed = tonumber(prompt_line("Speed factor", "1")) or 1
        local dry_run = prompt_line("Dry run? (y/n)", "n")
        start_replay(file, speed, dry_run:lower() == "y")
      end
    end
  end

  capture:stop()
  capture:unwrap_modem()
  term.clear()
  term.setCursor(1, 1)
  return 0
end

local function run_send(opts)
  local modem, err = select_modem()
  if not modem then
    print(err)
    return 1
  end
  local to = opts.to
  local port = tonumber(opts.port)
  local data = opts.data
  if not to or not port or not data then
    print_usage()
    return 1
  end
  modem.send(to, port, data)
  print("sent")
  return 0
end

local function run_ping(opts)
  local modem, err = select_modem()
  if not modem then
    print(err)
    return 1
  end
  local port = tonumber(opts.port)
  if not port then
    print_usage()
    return 1
  end
  modem.open(port)
  if opts.listen then
    print("Listening for netlab ping on port " .. port .. "...")
    while true do
      local _, local_address, remote_address, recv_port, _, payload = event.pull("modem_message")
      if recv_port == port and type(payload) == "string" then
        local id = payload:match("^NETLAB_PING:(.+)$")
        if id then
          modem.send(remote_address, port, "NETLAB_PONG:" .. id)
        end
      end
    end
  end
  local to = opts.to
  if not to then
    print_usage()
    return 1
  end
  local timeout = tonumber(opts.timeout) or 5
  local id = tostring(math.random(100000, 999999))
  local start = utils.now()
  modem.send(to, port, "NETLAB_PING:" .. id)
  while utils.now() - start < timeout do
    local _, _, remote_address, recv_port, _, payload = event.pull(0.5, "modem_message")
    if recv_port == port and remote_address == to and type(payload) == "string" then
      if payload == "NETLAB_PONG:" .. id then
        local rtt = (utils.now() - start) * 1000
        print(string.format("pong from %s: %.1f ms", remote_address, rtt))
        return 0
      end
    end
  end
  print("ping timeout")
  return 1
end

local opts = parse_flags(args)
local command = opts.args[1]

if not command then
  return run_tui()
end

if command == "replay" then
  local file = opts.args[2]
  if not file then
    print_usage()
    return 1
  end
  local speed = tonumber(opts.speed) or 1
  local dry_run = opts["dry-run"] or opts.dry_run
  return run_tui({
    replay_file = file,
    speed = speed,
    dry_run = dry_run,
  })
elseif command == "send" then
  return run_send(opts)
elseif command == "ping" then
  return run_ping(opts)
elseif command == "help" then
  print_usage()
  return 0
end

print_usage()
return 1
