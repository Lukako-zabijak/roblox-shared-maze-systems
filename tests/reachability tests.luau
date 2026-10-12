-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
local checks = 0
local function check(value, message)
 assert(value, message)
 checks += 1
end
local seed = 82731
local function random()
 seed = seed * 48271 % 2147483647
 return seed / 2147483647
end
for trial = 1, 100 do
 local width, height = 5 + trial % 11, 4 + trial % 7
 local map = newgrid(width, height)
 local start = 1 + trial % (width * height)
 for cell = 1, width * height do
  if cell ~= start and random() < 0.33 then discover(map, cell, true) end
 end
 local seen, queue = {[start] = true}, {start}
 local cursor = 1
 while cursor <= #queue do
  local current = queue[cursor]
  local x, z = (current - 1) % width, math.floor((current - 1) / width)
  for _, offset in {{1, 0}, {-1, 0}, {0, 1}, {0, -1}} do
   local nx, nz = x + offset[1], z + offset[2]
   if nx < 0 or nz < 0 or nx >= width or nz >= height then continue end
   local cell = nz * width + nx + 1
   if seen[cell] or (map.cells[cell] and map.cells[cell].blocked) then continue end
   seen[cell] = true
   table.insert(queue, cell)
  end
  cursor += 1
 end
 local flood = newsearch(map, start, nil)
 while flood.route == nil do
  local before = flood.pops
  local spent = stepsearch(flood, 13)
  check(spent <= 13 and flood.pops - before == spent, "reachability uses the same charged pop allowance")
 end
 for cell = 1, width * height do
  check((flood.costs[cell] ~= nil) == (seen[cell] == true), "no goal search matches independent rectangular flood fill")
 end
 check(#flood.route == 0 and flood.goal == nil, "component completion never invents a destination route")
end
local physical = newgrid(10, 10)
local learned = newgrid(10, 10)
discover(physical, 2, true)
local flood = newsearch(physical, 1, nil)
while flood.route == nil do stepsearch(flood, 7) end
check(learned.revision == 0 and next(learned.cells) == nil, "physical reachability does not teach the shared navigation map")
print("reachability=" .. checks)
