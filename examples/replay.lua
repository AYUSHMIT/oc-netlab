-- Run from the repository root with Lua 5.2 or 5.3; OpenOS is not required.
package.path = "./openos/lib/?.lua;./openos/lib/?/init.lua;" .. package.path
local Replay = require("netlab.replay")
local path = arg[1] or "examples/captures/sample.jsonl"
local speed = tonumber(arg[2]) or 1

local ok, err = Replay.run(path, {
  speed = speed,
  dry_run = true,
  on_event = function(record)
    print(string.format("%.2f %-8s %-8s port=%s %s",
      record.timestamp or 0, record.direction or "?", record.remote_address or "?",
      tostring(record.local_port or record.remote_port or "?"), record.preview or ""))
  end,
})
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end
