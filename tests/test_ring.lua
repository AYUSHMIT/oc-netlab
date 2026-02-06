local Ring = require("netlab.ring")

local ring = Ring.new(3)
ring:push(1)
ring:push(2)
ring:push(3)
assert(#ring:items() == 3, "ring should contain 3 items")

ring:push(4)
local items = ring:items()
assert(#items == 3, "ring should keep size limit")
assert(items[1] == 2 and items[2] == 3 and items[3] == 4, "ring order should be oldest to newest")

ring:clear()
assert(ring:len() == 0, "ring cleared")
