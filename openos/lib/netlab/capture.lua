local utils = require("netlab.utils")
local schema = require("netlab.schema")

local Capture = {}
Capture.__index = Capture

local function build_record(direction, local_address, remote_address, local_port, remote_port, distance, payloads, preview_len)
  local preview = utils.safe_preview(payloads[1], preview_len or 64)
  local record = {
    type = "modem_message",
    direction = direction,
    timestamp = utils.now(),
    wall_time = utils.wall_time(),
    local_address = local_address,
    remote_address = remote_address,
    local_port = local_port,
    remote_port = remote_port,
    distance = distance,
    payload = payloads,
    payload_len = utils.payload_length(payloads),
    preview = preview,
  }
  return schema.event(record)
end

function Capture.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Capture)
  self.ring = opts.ring
  self.config = opts.config or {}
  self.event_api = opts.event_api
  self.modem = opts.modem
  self.on_event = opts.on_event
  self.pending = {}
  self.flush_interval = tonumber(self.config.flush_interval or 2)
  self.sample_rate = tonumber(self.config.sample_rate or 1)
  self._timer_id = nil
  return self
end

function Capture:start()
  if not self.event_api or not self.event_api.listen then
    return false, "event API missing"
  end
  if self.listener then
    return true
  end
  self.listener = function(_, local_address, remote_address, port, distance, ...)
    local ok, err = pcall(function()
      self:handle_inbound(local_address, remote_address, port, distance, { ... })
    end)
    if not ok then
      self.error_count = (self.error_count or 0) + 1
    end
  end
  self.event_api.listen("modem_message", self.listener)
  if self.flush_interval > 0 and self.event_api.timer then
    self._timer_id = self.event_api.timer(self.flush_interval, function()
      self:flush()
    end, math.huge)
  end
  return true
end

function Capture:stop()
  if self.listener and self.event_api and self.event_api.ignore then
    self.event_api.ignore("modem_message", self.listener)
  end
  self.listener = nil
  if self._timer_id and self.event_api and self.event_api.cancel then
    self.event_api.cancel(self._timer_id)
  end
  self._timer_id = nil
  self:flush()
  self:stop_file()
end

function Capture:handle_inbound(local_address, remote_address, port, distance, payloads)
  local record = build_record("inbound", local_address, remote_address, port, nil, distance, payloads, self.config.preview_len)
  self:record(record)
end

function Capture:handle_outbound(remote_address, port, payloads)
  local local_address = self.modem and self.modem.address or nil
  local record = build_record("outbound", local_address, remote_address, nil, port, nil, payloads, self.config.preview_len)
  self:record(record)
end

function Capture:record(record)
  if self.sample_rate < 1 and math.random() > self.sample_rate then
    return
  end
  if self.ring then
    self.ring:push(record)
  end
  if self.file then
    self.pending[#self.pending + 1] = record
  end
  if self.on_event then
    pcall(self.on_event, record)
  end
end

function Capture:wrap_modem()
  if not self.modem or self._wrapped then
    return
  end
  self._wrapped = true
  self._orig_send = self.modem.send
  self._orig_broadcast = self.modem.broadcast
  local capture = self
  self.modem.send = function(_, address, port, ...)
    capture:handle_outbound(address, port, { ... })
    return capture._orig_send(_, address, port, ...)
  end
  self.modem.broadcast = function(_, port, ...)
    capture:handle_outbound("<broadcast>", port, { ... })
    return capture._orig_broadcast(_, port, ...)
  end
end

function Capture:unwrap_modem()
  if not self._wrapped or not self.modem then
    return
  end
  if self._orig_send then
    self.modem.send = self._orig_send
  end
  if self._orig_broadcast then
    self.modem.broadcast = self._orig_broadcast
  end
  self._wrapped = false
end

function Capture:start_file(path, meta)
  local dir = path:match("^(.+)/[^/]+$")
  if dir then
    utils.ensure_dir(dir)
  end
  local file, err = io.open(path, "w")
  if not file then
    return false, err
  end
  self.file = file
  self.pending = {}
  self.file:write(utils.encode_json(schema.header(meta)) .. "\n")
  self.file:flush()
  self.path = path
  return true
end

function Capture:stop_file()
  if self.file then
    self.file:flush()
    self.file:close()
  end
  self.file = nil
  self.path = nil
  self.pending = {}
end

function Capture:flush()
  if not self.file or #self.pending == 0 then
    return
  end
  for _, record in ipairs(self.pending) do
    self.file:write(utils.encode_json(record) .. "\n")
  end
  self.file:flush()
  self.pending = {}
end

function Capture.export(ring, path, meta)
  local dir = path:match("^(.+)/[^/]+$")
  if dir then
    utils.ensure_dir(dir)
  end
  local file, err = io.open(path, "w")
  if not file then
    return false, err
  end
  file:write(utils.encode_json(schema.header(meta)) .. "\n")
  for _, record in ipairs(ring:items()) do
    file:write(utils.encode_json(record) .. "\n")
  end
  file:flush()
  file:close()
  return true
end

return Capture
