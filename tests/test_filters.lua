local Filters = require("netlab.filters")

local record = {
  remote_address = "abc",
  local_port = 123,
  remote_port = 456,
  direction = "inbound",
  preview = "hello world",
}

assert(Filters.match(record, { port = 123 }))
assert(not Filters.match(record, { port = 999 }))
assert(Filters.match(record, { remote = "abc" }))
assert(not Filters.match(record, { remote = "def" }))
assert(Filters.match(record, { direction = "inbound" }))
assert(not Filters.match(record, { direction = "outbound" }))
assert(Filters.match(record, { payload = "hello" }))
assert(not Filters.match(record, { payload = "missing" }))
assert(Filters.match(record, { payload_regex = "world" }))
assert(not Filters.match(record, { payload_regex = "^nomatch" }))
