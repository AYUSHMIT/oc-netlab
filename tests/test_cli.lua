local calls = {}
local modem = {
  send = function(...) calls[#calls + 1] = { ... }; return true end,
}
local component = {
  list = function()
    local done = false
    return function()
      if not done then done = true; return "test-modem" end
    end
  end,
  proxy = function() return modem end,
}
local env = setmetatable({
  require = function(name)
    if name == "component" then return component end
    if name == "event" then
      return { pull = function() error("send must not start the TUI") end }
    end
    if name == "term" then return {} end
    return require(name)
  end,
  print = function() end,
}, { __index = _G })
local program = assert(loadfile("openos/bin/netlab.lua", "t", env))
local launcher_env = setmetatable({
  loadfile = function(path)
    assert(path == "/bin/netlab.lua")
    return program
  end,
  dofile = function(path)
    assert(path == "/bin/netlab.lua")
    return program()
  end,
}, { __index = _G })
local launcher = assert(loadfile("openos/bin/netlab", "t", launcher_env))
assert(launcher("send", "--to", "remote", "--port", "123", "--data", "hello world") == 0)
assert(#calls == 1 and calls[1][1] == "remote" and calls[1][2] == 123)
assert(calls[1][3] == "hello world", "launcher must forward all CLI arguments")
assert(launcher("help") == 0, "launcher must return the command status")
