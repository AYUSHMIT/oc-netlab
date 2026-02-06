local Ring = {}
Ring.__index = Ring

function Ring.new(size)
  size = tonumber(size) or 256
  local self = setmetatable({
    size = size,
    head = 1,
    count = 0,
    data = {},
  }, Ring)
  return self
end

function Ring:push(value)
  self.data[self.head] = value
  self.head = self.head + 1
  if self.head > self.size then
    self.head = 1
  end
  if self.count < self.size then
    self.count = self.count + 1
  end
end

function Ring:clear()
  self.data = {}
  self.head = 1
  self.count = 0
end

function Ring:len()
  return self.count
end

function Ring:items()
  local items = {}
  if self.count == 0 then
    return items
  end
  local start = self.head - self.count
  if start <= 0 then
    start = start + self.size
  end
  for i = 0, self.count - 1 do
    local idx = start + i
    if idx > self.size then
      idx = idx - self.size
    end
    items[#items + 1] = self.data[idx]
  end
  return items
end

return Ring
