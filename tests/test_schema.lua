local schema = require("netlab.schema")

local header = schema.header({ source = "test" })
assert(header.type == "header", "header type")
assert(header.schema_version == schema.version, "header version")

local event = schema.event({ type = "modem_message" })
assert(event.schema_version == schema.version, "event version")
