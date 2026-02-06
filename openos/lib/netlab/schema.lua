local utils = require("netlab.utils")

local schema = {}

schema.version = 1

function schema.header(meta)
  return {
    type = "header",
    schema_version = schema.version,
    created_at = utils.wall_time(),
    meta = meta or {},
  }
end

function schema.event(record)
  record.schema_version = schema.version
  return record
end

return schema
