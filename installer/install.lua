local filesystem = require("filesystem")
local shell = require("shell")

local source_root = shell.resolve("../openos")
local target_root = "/"

local function copy_tree(source, target)
  if filesystem.isDirectory(source) then
    filesystem.makeDirectory(target)
    for name in filesystem.list(source) do
      copy_tree(filesystem.concat(source, name), filesystem.concat(target, name))
    end
  else
    filesystem.copy(source, target)
  end
end

if not filesystem.exists(source_root) then
  io.stderr:write("Missing openos directory at " .. source_root .. "\n")
  return
end

copy_tree(source_root, target_root)
filesystem.makeDirectory("/home/netlab/captures")

print("netlab installed to /bin/netlab")
