local utils = {}

local has_computer, computer = pcall(require, "computer")
local has_serialization, serialization = pcall(require, "serialization")

utils.json_null = { __json_null = true }

function utils.now()
  if has_computer and computer.uptime then
    return computer.uptime()
  end
  return os.clock()
end

function utils.wall_time()
  if os.date then
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
  end
  return tostring(utils.now())
end

function utils.sleep(seconds)
  if seconds <= 0 then
    return
  end
  if os.sleep then
    os.sleep(seconds)
    return
  end
  local target = utils.now() + seconds
  while utils.now() < target do end
end

function utils.safe_preview(value, max_len)
  max_len = max_len or 48
  local text
  if type(value) == "table" and has_serialization and serialization.serialize then
    text = serialization.serialize(value)
  else
    text = tostring(value or "")
  end
  local out = {}
  local count = 0
  local truncated = false
  for i = 1, #text do
    local byte = text:byte(i)
    if byte >= 32 and byte <= 126 then
      table.insert(out, string.char(byte))
      count = count + 1
    else
      table.insert(out, string.format("\\x%02X", byte))
      count = count + 4
    end
    if count >= max_len then
      if i < #text then
        truncated = true
      end
      break
    end
  end
  local preview = table.concat(out)
  if truncated then
    preview = preview .. "…"
  end
  return preview
end

function utils.payload_length(payloads)
  local total = 0
  for i = 1, #payloads do
    local value = payloads[i]
    if type(value) == "string" then
      total = total + #value
    else
      total = total + #tostring(value)
    end
  end
  return total
end

local function is_array(tbl)
  local count = 0
  local max = 0
  for key, _ in pairs(tbl) do
    if type(key) ~= "number" then
      return false
    end
    if key > max then
      max = key
    end
    count = count + 1
  end
  return max == count
end

local function encode_string(value)
  local replacements = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
  }
  return '"' .. value:gsub('[\\"%z\1-\31]', function(char)
    return replacements[char] or string.format("\\u%04X", char:byte())
  end) .. '"'
end

function utils.encode_json(value)
  local value_type = type(value)
  if value == nil or value == utils.json_null then
    return "null"
  elseif value_type == "string" then
    return encode_string(value)
  elseif value_type == "number" then
    return tostring(value)
  elseif value_type == "boolean" then
    return value and "true" or "false"
  elseif value_type == "table" then
    if is_array(value) then
      local items = {}
      for i = 1, #value do
        items[#items + 1] = utils.encode_json(value[i])
      end
      return "[" .. table.concat(items, ",") .. "]"
    end
    local keys = {}
    for key, _ in pairs(value) do
      keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local items = {}
    for _, key in ipairs(keys) do
      local encoded = utils.encode_json(value[key])
      if encoded ~= "null" or value[key] == utils.json_null then
        items[#items + 1] = encode_string(tostring(key)) .. ":" .. encoded
      end
    end
    return "{" .. table.concat(items, ",") .. "}"
  end
  return encode_string(tostring(value))
end

local function decode_error(message)
  error("JSON decode error: " .. message)
end

function utils.decode_json(input)
  local pos = 1
  local parse_string
  local parse_number
  local parse_array
  local parse_object
  local function skip()
    local _, next_pos = input:find("^[%s]*", pos)
    pos = (next_pos or pos - 1) + 1
  end

  local function parse_value()
    skip()
    local char = input:sub(pos, pos)
    if char == "" then
      decode_error("unexpected end")
    elseif char == "\"" then
      return parse_string()
    elseif char == "{" then
      return parse_object()
    elseif char == "[" then
      return parse_array()
    elseif char == "t" and input:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif char == "f" and input:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    elseif char == "n" and input:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    else
      return parse_number()
    end
  end

  function parse_string()
    pos = pos + 1
    local result = {}
    while true do
      local char = input:sub(pos, pos)
      if char == "" then
        decode_error("unterminated string")
      elseif char == "\"" then
        pos = pos + 1
        return table.concat(result)
      elseif char == "\\" then
        local next_char = input:sub(pos + 1, pos + 1)
        if next_char == "u" then
          local hex = input:sub(pos + 2, pos + 5)
          if not hex:match("^%x%x%x%x$") then
            decode_error("invalid unicode escape")
          end
          result[#result + 1] = string.char(tonumber(hex, 16))
          pos = pos + 6
        else
          local map = { ['"'] = '"', ['\\'] = "\\", ['/'] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
          local replacement = map[next_char]
          if not replacement then
            decode_error("invalid escape")
          end
          result[#result + 1] = replacement
          pos = pos + 2
        end
      else
        result[#result + 1] = char
        pos = pos + 1
      end
    end
  end

  function parse_number()
    local start = pos
    local pattern = "^-?%d+%.?%d*[eE]?[+-]?%d*"
    local number = input:sub(pos):match(pattern)
    if not number or number == "" then
      decode_error("invalid number")
    end
    pos = pos + #number
    return tonumber(number)
  end

  function parse_array()
    pos = pos + 1
    local result = {}
    skip()
    if input:sub(pos, pos) == "]" then
      pos = pos + 1
      return result
    end
    while true do
      result[#result + 1] = parse_value()
      skip()
      local char = input:sub(pos, pos)
      if char == "," then
        pos = pos + 1
      elseif char == "]" then
        pos = pos + 1
        return result
      else
        decode_error("expected ',' or ']' in array")
      end
    end
  end

  function parse_object()
    pos = pos + 1
    local result = {}
    skip()
    if input:sub(pos, pos) == "}" then
      pos = pos + 1
      return result
    end
    while true do
      if input:sub(pos, pos) ~= "\"" then
        decode_error("expected string key")
      end
      local key = parse_string()
      skip()
      if input:sub(pos, pos) ~= ":" then
        decode_error("expected ':' after key")
      end
      pos = pos + 1
      result[key] = parse_value()
      skip()
      local char = input:sub(pos, pos)
      if char == "," then
        pos = pos + 1
      elseif char == "}" then
        pos = pos + 1
        return result
      else
        decode_error("expected ',' or '}' in object")
      end
    end
  end

  local value = parse_value()
  skip()
  if pos <= #input then
    decode_error("trailing characters")
  end
  return value
end

function utils.ensure_dir(path)
  local ok, filesystem = pcall(require, "filesystem")
  if not ok or not filesystem then
    return false
  end
  if filesystem.exists(path) then
    return true
  end
  return filesystem.makeDirectory(path)
end

return utils
