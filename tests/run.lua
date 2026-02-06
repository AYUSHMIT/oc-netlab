package.path = "./openos/lib/?.lua;./openos/lib/?/init.lua;./openos/lib/?/?.lua;" .. package.path

local tests = {
  "tests/test_ring.lua",
  "tests/test_filters.lua",
  "tests/test_schema.lua",
}

local failures = 0
for _, path in ipairs(tests) do
  local ok, err = pcall(dofile, path)
  if ok then
    io.write("ok - " .. path .. "\n")
  else
    failures = failures + 1
    io.write("not ok - " .. path .. "\n" .. tostring(err) .. "\n")
  end
end

if failures > 0 then
  os.exit(1)
end
