local Capture = require("netlab.capture")
local Ring = require("netlab.ring")
local utils = require("netlab.utils")

local calls = {}
local modem = {
  address = "local",
  send = function(...)
    calls[#calls + 1] = { ... }
    return true, "sent"
  end,
  broadcast = function(...)
    calls[#calls + 1] = { ... }
    return true, "broadcast"
  end,
}
local original_send, original_broadcast = modem.send, modem.broadcast
local ring = Ring.new(10)
local capture = Capture.new({ modem = modem, ring = ring })
capture:wrap_modem()
local ok, detail = modem.send("remote", 123, "hello", 42)
assert(ok and detail == "sent", "wrapping must preserve modem return values")
ok, detail = modem.broadcast(321, "world")
assert(ok and detail == "broadcast")
assert(calls[1][1] == "remote" and calls[1][2] == 123 and calls[1][3] == "hello")
assert(calls[1][4] == 42 and calls[2][1] == 321 and calls[2][2] == "world")
local records = ring:items()
assert(records[1].remote_address == "remote" and records[1].remote_port == 123)
assert(records[1].payload[1] == "hello" and records[1].payload[2] == 42)
assert(records[2].remote_address == "<broadcast>" and records[2].remote_port == 321)
assert(records[2].payload[1] == "world", "capture must follow the modem's dot-call API")
capture:unwrap_modem()
assert(modem.send == original_send and modem.broadcast == original_broadcast)

local path = os.tmpname()
local saved, err = pcall(function()
  assert(capture:start_file(path, { source = "test" }))
  capture:handle_inbound("local", "remote", 123, 2, { "last message" })
  capture:stop_file() -- Stop before the periodic flush can run.
  local file = assert(io.open(path, "r"))
  local header, event = file:read("*l"), file:read("*l")
  file:close()
  assert(utils.decode_json(header).type == "header")
  assert(event, "stopping a capture must flush its pending final records")
  assert(utils.decode_json(event).payload[1] == "last message")
end)
capture:stop_file()
os.remove(path)
assert(saved, err)
