local Replay = require("netlab.replay")
local Capture = require("netlab.capture")
local Ring = require("netlab.ring")
local utils = require("netlab.utils")

local original_sleep = utils.sleep
local sleeps = {}
utils.sleep = function(seconds) sleeps[#sleeps + 1] = seconds end
local ok, err = pcall(function()
  local records, emitted = {}, {}
  local dispatcher = Replay.new_dispatcher()
  dispatcher.listen("modem_message", function(...) emitted[#emitted + 1] = { ... } end)
  assert(Replay.run("examples/captures/sample.jsonl", {
    speed = 2, dry_run = true, dispatcher = dispatcher,
    on_event = function(record) records[#records + 1] = record end,
  }))
  assert(#records == 2 and records[1].preview == "hello" and records[2].preview == "pong")
  assert(records[2].direction == "outbound", "dry-run must preserve stored metadata")
  assert(#emitted == 0, "dry-run must not dispatch modem events")
  assert(#sleeps == 1 and math.abs(sleeps[1] - 0.45) < 0.000001)

  assert(Replay.run("examples/captures/sample.jsonl", { dispatcher = dispatcher }))
  assert(#emitted == 2 and emitted[1][4] == 123 and emitted[2][4] == 321)
  assert(emitted[1][6] == "hello" and emitted[2][6] == "pong")

  -- Fail immediately if a replay dispatcher tries to run a synchronous timer loop.
  utils.sleep = function() error("replay startup must not block on a timer") end
  local callback, cancelled
  local timer_id = {}
  local timed = Replay.new_dispatcher({
    timer = function(interval, handler, count)
      assert(interval == 2 and count == math.huge)
      callback = handler
      return timer_id
    end,
    cancel = function(id) cancelled = id end,
  })
  local ring = Ring.new(4)
  local capture = Capture.new({ ring = ring, event_api = timed })
  assert(capture:start())
  assert(callback, "replay must delegate scheduling to the event loop")
  timed.emit("modem_message", "local", "remote", 123, 1, "replayed")
  assert(ring:items()[1].payload[1] == "replayed")
  callback()
  capture:stop()
  assert(cancelled == timer_id, "stopping capture must cancel its flush timer")
  timed.emit("modem_message", "local", "remote", 123, 1, "ignored")
  assert(ring:len() == 1, "stopping capture must detach its listener")
end)
utils.sleep = original_sleep
assert(ok, err)
