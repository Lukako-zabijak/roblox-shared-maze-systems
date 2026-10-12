-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
--!strict
type grid = {width: number, height: number, revision: number, cells: {[number]: {blocked: boolean}}} -- bounds and revisions travel with the observations they describe
type priority = {score: number} -- both deadlines and path estimates only need a score for heap ordering
type entry = {cell: number, cost: number, score: number} -- path entries keep paid cost separate from the goal bound
type search = { -- a job owns its snapshot frontier and result until adoption or cancellation
	map: grid, start: number, goal: number?, revision: number, -- a real goal uses its lower bound while nil explores the entire reachable component
	heap: {entry}, costs: {[number]: number}, parents: {[number]: number}, -- frontier prices and parent links belong to this job rather than to another rig
	route: {number}?, cost: number, expansions: number, pops: number, contrast: search?, -- nil means unfinished and an empty route means the search finished without a path
} -- the job shape keeps fixed beliefs separate from mutable work and finished results

local function newgrid(width: number, height: number): grid -- start with no observations so spawning cant give the agents the answer
	assert(width > 0 and height > 0, "grid dimensions must be positive") -- invalid dimensions would make neighbor encoding unsafe
	return {width = width, height = height, revision = 0, cells = {}} -- fresh bounds and empty memory keep replay independent of earlier discoveries
end -- this map has valid bounds but no borrowed observations
local function coordinates(map: grid, cell: number): (number, number) -- row width decodes one bounded id into its two grid axes
	return (cell - 1) % map.width, math.floor((cell - 1) / map.width) -- the remainder stays within its row while division selects the row
end -- both coordinates use the same cell origin as encoding
local function cellat(map: grid, x: number, z: number): number? -- a checked id keeps edge neighbors from wrapping into another row
	if x < 0 or z < 0 or x >= map.width or z >= map.height then return nil end -- off floor coordinates cannot become valid table keys
	return z * map.width + x + 1 -- row stride makes each bounded center a unique one based id
end -- only bounded coordinates can leave as an encoded id
local function distance(map: grid, left: number, right: number): number -- axis distance is a lower bound because every legal step costs at least one
	local x, z = coordinates(map, left) -- both distance endpoints use the same grid row stride
	local otherx, otherz = coordinates(map, right) -- both endpoints must use the same row width for a valid distance bound
	return math.abs(x - otherx) + math.abs(z - otherz) -- two axis gaps cannot overestimate a four way route whose steps cost at least one
end -- the result is a lower bound rather than a promise that the straight route is clear
local function neighbors(map: grid, cell: number): {number} -- only four axis moves are allowed so the distance bound stays valid
	local x, z = coordinates(map, cell) -- bounded axis offsets come from the current cells decoded row and column
	local result = {} -- the caller gets an independent bounded neighbor list
	for _, offset in {{1, 0}, {0, 1}, {-1, 0}, {0, -1}} do -- four axis steps keep the same movement model as the distance bound
		local adjacent = cellat(map, x + offset[1], z + offset[2]) -- the common encoder rejects off floor steps before they enter the list
		if adjacent then table.insert(result, adjacent) end -- only bounded neighbors can enter this returned list
	end -- the neighbor list is bounded before it leaves this helper
	return result -- only checked neighbor ids leave this encoder
end -- the returned list has no wrapped or off floor centers

local function push<t>(heap: {t & priority}, item: t & priority) -- climb parent slots instead of sorting the whole frontier after each insertion
	local index = #heap + 1 -- the new tail slot lets insertion climb without moving unrelated branches
	while index > 1 do -- insertion only walks the ancestors whose order could change
		local parent = math.floor(index / 2) -- binary heap parent slots are half the child index
		if heap[parent].score <= item.score then break end -- an already cheaper parent is where the inserted item can stop climbing
		heap[index], index = heap[parent], parent -- the entry and its new hole move together along the parent branch
	end -- the inserted item now fits above its children and below its first ordered parent
	heap[index] = item -- this slot already fits between its parent and children
end -- parent and child ordering is restored without sorting the whole frontier
local function pop<t>(heap: {t & priority}): t & priority -- take the cheapest score and repair just the branch that lost its root
	local first = heap[1] -- save the root before repairing the remaining heap
	local last = table.remove(heap) :: (t & priority) -- reuse the old tail to fill the root hole without shifting the array
	if #heap == 0 then return first end -- removing the last entry leaves no root hole to repair
	local index = 1 -- repair starts at the root hole left by the cheapest heap entry
	while index * 2 <= #heap do -- only parents with a child need another heap repair comparison
		local child = index * 2 -- the two children occupy consecutive slots below this parent
		if child < #heap and heap[child + 1].score < heap[child].score then child += 1 end -- choose the cheaper sibling before deciding where the old tail belongs
		if heap[child].score >= last.score then break end -- a dearer child cannot require the tail to move any farther down
		heap[index], index = heap[child], child -- moving the smaller child also advances the hole that still needs repair
	end -- the chosen tail slot satisfies both parent and child order
	heap[index] = last -- the tail now fits below its parent and above its children
	return first -- the caller gets the cheapest saved entry and checks whether its price is stale
end -- remaining entries keep heap order and the saved cheapest entry belongs to the caller
local function discover(map: grid, cell: number, blocked: boolean): boolean -- only changed evidence needs a new revision and new route work
	assert(cell >= 1 and cell <= map.width * map.height, "discovery outside grid") -- outside ids would corrupt both discovery memory and route comparisons
	local old = map.cells[cell] -- the earlier occupancy lets repeated observations stay silent
	if old and old.blocked == blocked then return false end -- duplicate evidence must not keep invalidating everyone elses route
	map.cells[cell] = {blocked = blocked} -- replace the record so running snapshots never see an in place edit
	map.revision += 1 -- only a real observation change gets a new revision
	return true -- all relevant checks passed before this result leaves the helper
end -- only accepted changed evidence advanced shared knowledge
local function retrace(parents: {[number]: number}, start: number, goal: number): {number} -- these parent links belong to the best prices from this search
	local reversed = {goal} -- parent links run backward so collect them before producing forward travel
	while reversed[#reversed] ~= start do table.insert(reversed, parents[reversed[#reversed]]) end -- follow this jobs best parents until the reached start is included
	local route = table.create(#reversed) :: {number} -- the result has the same length as the parent chain and only receives numeric ids
	for index = #reversed, 1, -1 do table.insert(route, reversed[index]) end -- reverse only the collected chain so movement gets forward order
	return route -- the route is forward ordered and begins at the reached start
end -- forward travel now follows the parent chain that achieved the best goal price
local function newsearch(map: grid, start: number, goal: number?): search -- route jobs and spawn reachability share one frontier but keep separate belief snapshots
	local snapshot = {width = map.width, height = map.height, revision = map.revision, cells = table.clone(map.cells)} -- records are replaced on discovery so a shallow copy safely keeps this belief revision
	local job: search = { -- this frontier belongs to one reached start and one replay generation
		map = snapshot, start = start, goal = goal, revision = map.revision, -- each job gets a fixed belief map while the shared map can keep learning
		heap = {}, costs = {[start] = 0}, parents = {}, route = nil, cost = math.huge, expansions = 0, pops = 0, -- the empty frontier only knows the start price and no finite result yet
	} -- the job shape keeps fixed beliefs separate from mutable work and finished results
	push(job.heap, {cell = start, cost = 0, score = if goal then distance(map, start, goal) else 0}) -- a zero bound makes no goal mode explore by paid cost without guessing a destination
	return job -- the caller owns this unfinished frontier and can resume it later
end -- this frontier can pause without losing its belief revision or previous work
local function stepsearch(job: search, limit: number, deadline: number?): number -- unfinished heaps survive the slice so movement doesnt wait for a full search
	local spent = 0 -- this allowance belongs to one resumed slice rather than the whole job
	while spent < limit and job.route == nil do -- a finished or exhausted slice gives control back to movement and the other jobs
		if deadline and os.clock() >= deadline then break end -- check elapsed time between pops rather than pretend the slice is a hard real time limit
		if #job.heap == 0 then -- exhaustion settles either a failed goal route or the complete reachable component
			job.route = {} -- an empty result marks completion while the reached prices remain available to no goal callers
			break -- the goal or exhausted frontier settled this snapshot so no more work belongs to this slice
		end -- no more reachable cells can leave an exhausted frontier
		local current = pop(job.heap) -- heap order picks the lowest estimated total cost next
		spent, job.pops = spent + 1, job.pops + 1 -- every removed entry charges both this slice and the whole job including stale entries
		if current.cost ~= job.costs[current.cell] then continue end -- a cheaper saved arrival makes this older heap entry stale
		if job.goal and current.cell == job.goal then -- a destination settles only goal mode while reachability keeps exploring
			job.route, job.cost = retrace(job.parents, job.start, job.goal), current.cost -- the completed geometry and its settled price become one result
			break -- the goal or exhausted frontier settled this snapshot so no more work belongs to this slice
		end -- only nongoal candidates reach neighbor pricing below
		job.expansions += 1 -- only nonstale nongoal candidates reach neighbor expansion
		for _, cell in neighbors(job.map, current.cell) do -- legal neighbor candidates keep the same bounds as every other grid operation
			local known = job.map.cells[cell] -- unknown is still searchable while confirmed walls are excluded before pricing
			if known and known.blocked then continue end -- confirmed wall evidence excludes this neighbor before pricing it
			local cost = current.cost + (if known then 1 else 1.15) -- known clear steps cost one and unknown steps keep the existing small penalty
			if cost >= (job.costs[cell] or math.huge) then continue end -- keep the saved parent when this arrival doesnt improve its price
			job.costs[cell], job.parents[cell] = cost, current.cell -- this better price and the parent that achieved it replace the old record together
			push(job.heap, {cell = cell, cost = cost, score = cost + (if job.goal then distance(job.map, cell, job.goal) else 0)}) -- goal mode adds its admissible bound while reachability orders only the paid travel
		end -- all usable local alternatives now have their best price and parent recorded
	end -- the returned pop count covers everything consumed in this slice
	return spent -- the scheduler charges actual popped work including stale entries
end -- unfinished work remains owned by this job for its next fair slice
local function routecost(map: grid, route: {number}, first: number): number -- use the same prices as search when comparing the unwalked part of a route
	if #route == 0 then return math.huge end -- no route cannot be compared as a zero cost journey
	local cost = 0 -- only unwalked edges contribute to the comparison price
	for index = first + 1, #route do -- only unwalked edges count toward the remaining price
		local known = map.cells[route[index]] -- the current observation decides whether this remaining edge is usable and what it costs
		if known and known.blocked then return math.huge end -- an obstructed remainder is not a valid cheap baseline
		cost += if known then 1 else 1.15 -- checked clear cells keep the same price as search and unknown stays slightly dearer
	end -- only the remaining route edges contributed to its price
	return cost -- this remaining price uses the same unknown cell penalty as search
end -- completed travel did not enter this remaining cost
local function couldshorten(map: grid, anchor: number, opened: number, goal: number, cost: number): boolean -- even the best path through this opening needs to beat the remaining price
	return distance(map, anchor, opened) + distance(map, opened, goal) < cost - 0.0001 -- reject the opening when even its best possible axis route cannot save travel
end -- this cheap bound filters work and still leaves real route comparison to search

local players = game:GetService("Players") -- the engine player identity owns viewer readiness and departure
local httpservice = game:GetService("HttpService") -- a serialized snapshot can reach late viewers without sharing mutable state
local physicsservice = game:GetService("PhysicsService") -- collision groups belong to the server and are shared by sensing and movement
local tweenservice = game:GetService("TweenService") -- engine interpolation keeps warning pulses and fades independent of path work
local debrisservice = game:GetService("Debris") -- short lived fragments still get cleanup even if their individual record is dropped
local world = workspace -- this candidate owns one world and never searches another open Studio place
local maze = world:WaitForChild("Maze") -- keep the authored maze as the source of world geometry
local agents = world:WaitForChild("MazeAgents") -- the controller owns the existing rigs rather than replace their authored models
local floor = maze:WaitForChild("MazeFloor") :: BasePart -- the same floor supplies grid axes query height and landing height
local goal = maze:WaitForChild("GoalPad") :: BasePart -- the authored goal pad is checked before it becomes a destination id
local knowledgeevent = game:GetService("ReplicatedStorage"):WaitForChild("maze_knowledge_event") :: RemoteEvent -- the existing remote only carries notices and the viewers ready signal
local worldevent = game:GetService("ServerStorage"):WaitForChild("maze_world_changed") :: BindableEvent -- server phase messages keep a narrow boundary around world changes
local spawnlocation = world:FindFirstChildOfClass("SpawnLocation") -- collapse exclusions use the actual spawn when the place has one
local map = newgrid(math.round(floor.Size.X / 8), math.round(floor.Size.Z / 8)) -- shared observations stay separate from the physical spawn validation map
local origin = Vector3.new(-floor.Size.X / 2 + 4, floor.Size.Y / 2, -floor.Size.Z / 2 + 4) -- half a cell puts encoded positions at centers instead of tile corners
local states, connections, viewers = {}, {}, {} -- rig ownership and viewer membership must not share the map cell table
local blockers, collapses, gates = {}, {}, {} -- physical obstruction references and wall holds need their own lifetimes
local running, started, generation = true, false, 0 -- a stopped owner cannot restart through a later callback
local debrisfolder = world:FindFirstChild("maze_collapse_debris") :: Folder? -- folder identity separates old falling parts from a restored replay
local elapsed, searchcursor, noticerevision, nextnotice = 0, 0, 0, 0 -- movement cadence queue rotation and notice serials are separate counters
local spawnrandom, random = Random.new(41317), Random.new(76231) -- replay starts the spawn stream again without restarting collapse variation
local scanangles = {-72, -48, -24, 0, 24, 48, 72} -- keep seven existing directions so the visible probes stay the same
local wrongcolor = Color3.fromRGB(255, 62, 72) -- unselected directions keep the existing red cue
local agentmethods = {} -- one method table avoids copying lifecycle functions into every rig
local agentmetatable = {__index = agentmethods} -- missing method lookup uses shared behavior while ordinary writes stay private

local function attributes(item: Instance, values: {[string]: any}) -- these inspection values are snapshots and keep their last value after unexpected owner destruction
	for name, value in values do item:SetAttribute(name, value) end -- publish copies through the existing attribute names instead of expose private tables
end -- private mutable tables never leave through this inspection adapter
local function object(class: string | Instance, parent: Instance, values: {[string]: any}): any -- set properties before parenting so observers see a configured instance
	local item = if typeof(class) == "string" then Instance.new(class) else class:Clone() -- a fresh class or childless geometry clone gets the same configured ownership boundary
	if typeof(class) ~= "string" then item:ClearAllChildren() end -- cloned geometry keeps its authored style but not old children or scripts
	for property, value in values do (item :: any)[property] = value end -- the requested instance class is the only boundary where property names are dynamic
	item.Parent = parent -- parent only after configuration so listeners dont see half initialized parts
	return item -- the configured object is returned after its ownership parent is assigned
end -- the configured instance has one explicit resource parent
local visual = object("Part", script, { -- probes warnings and goals share nonphysical defaults and the controller lifetime
	Name = "maze visual template", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.58, 0.58), -- ordered probe dots inherit this shape instead of repeating its construction
	Anchored = true, CastShadow = false, Material = Enum.Material.Neon, Color = wrongcolor, Transparency = 1, -- hidden defaults prevent a new part from flashing before its caller places it
	CanCollide = false, CanQuery = false, CanTouch = false, -- visual instances cannot become navigation evidence or physical obstacles
}) -- each caller overrides only its different size pose color or name
local function collisions(part: BasePart, enabled: boolean, query: boolean?) -- query and contact flags need an explicit choice even for invisible parts
	part.CanCollide, part.CanQuery, part.CanTouch = enabled, if query == nil then enabled else query, false -- contact query and touch flags move together according to the callers physical role
end -- physical contact and query visibility now match this parts role
local function own(part: BasePart) -- all physical owners use the same checked server transfer
	return pcall(function() -- a denied transfer can fall back without aborting an unrelated physical release
		assert(part:CanSetNetworkOwnership()) -- an ineligible assembly cannot silently become client controlled
		part:SetNetworkOwner(nil) -- nil gives the server responsibility for this eligible assembly
		assert(part:GetNetworkOwner() == nil, "server ownership required") -- the returned success includes the actual owner rather than just the attempted call
	end) -- callers can either inspect the failure or continue cosmetic debris work
end -- this boundary returns success and the engine reason without yielding
local function tween(item: Instance, duration: number, values: {[string]: any}, style: Enum.EasingStyle?, direction: Enum.EasingDirection?) -- warning and cleanup animations share timing setup without sharing mutable goals
	local animation = tweenservice:Create(item, TweenInfo.new(duration, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.Out), values) -- the engine tween owns interpolation while the scheduler owns its lifetime
	animation:Play() -- the configured tween starts interpolation without blocking the scheduler
end -- the animation has started without yielding the navigation owner
local function worldpoint(cell: number): Vector3 -- commands and sensing must agree on the same floor relative cell center
	local x, z = coordinates(map, cell) -- the decoded axes become distances in the existing eight stud grid
	return floor.CFrame:PointToWorldSpace(origin + Vector3.new(x * 8, 0, z * 8)) -- the floor frame makes the same cell usable for commands and queries
end -- world commands and grid decisions now refer to the same center
local function cellfromworld(position: Vector3): number? -- change frames before rounding so world offsets dont change cell ids
	local point = floor.CFrame:PointToObjectSpace(position) - origin -- subtract the center origin in floor space before rounding into cell coordinates
	return cellat(map, math.round(point.X / 8), math.round(point.Z / 8)) -- round only after changing frames then let the bounds encoder reject off floor positions
end -- an off floor position cannot supply a reached anchor
local goalcell = assert(cellfromworld(goal.Position), "goal is outside the grid") -- the validated destination must be a bounded cell before any spawn or route work starts
local demowall = maze:WaitForChild("Wall_32_31") :: BasePart -- the demonstration keeps the same focus wall through template restoration
local democell = cellfromworld(demowall.Position) :: number -- shared change and crossing evidence refer to the same encoded opening
local function planar(left: Vector3, right: Vector3): number -- standing height must not inflate arrival or spacing checks
	return Vector2.new(left.X - right.X, left.Z - right.Z).Magnitude -- only the horizontal gap contributes to this flat maze distance
end -- vertical rig height stays out of the comparison
local function choose(list, selected, spacing: number, wanted: number, threshold: number) -- spawns and walls share selection while their distance policies stay explicit
	for _, item in list do -- input order keeps the seeded shuffle and fallback passes meaningful
		if #selected >= wanted then break end -- later entries cannot exceed the requested count
		local point = if typeof(item) == "Vector3" then item else item.Position -- both supported inputs expose one physical position for policy checks
		local allowed = not table.find(selected, item) and planar(point, goal.Position) >= threshold -- duplicates and the goal exclusion are checked before spacing
		for _, old in selected do -- every earlier selection contributes its own separation requirement
			allowed = allowed and planar(point, if typeof(old) == "Vector3" then old else old.Position) >= spacing -- one close earlier choice is enough to reject this candidate
		end -- later comparisons cannot undo an earlier failed policy
		if allowed then table.insert(selected, item) end -- only an accepted candidate extends the ordered selection
	end -- the result keeps both the caller policy and the incoming seeded order
end -- fallback passes can relax spacing without borrowing another callers choices
local function shuffle(list: {any}, rng: Random) -- fixed seeds make the demonstration repeatable without giving anyone a route
	for index = #list, 2, -1 do -- shuffle only the range that hasnt already been placed
		local other = rng:NextInteger(1, index) -- each swap uses the same seeded stream and the remaining shuffled range
		list[index], list[other] = list[other], list[index] -- swap rather than remove elements so the seeded candidate set keeps its size
	end -- each completed tail position is outside the remaining shuffle range
end -- the seeded set kept its contents while changing their order

for _, group in {"MazeAgents", "MazeNavigationDecor", "maze_collapse_debris"} do -- register the owned collision policies before creating or querying their parts
	pcall(function() physicsservice:RegisterCollisionGroup(group) end) -- a group that already exists should not stop startup
	physicsservice:CollisionGroupSetCollidable(group, group, false) -- these owned groups must not create collisions within themselves
end -- all owned collision policies exist before any rig body query
physicsservice:CollisionGroupSetCollidable("MazeAgents", "MazeNavigationDecor", false) -- thin navigation decoration stays out of agent contact and sensing
local overlap = OverlapParams.new() -- body queries keep their collision policy without allocating parameters for every cell
overlap.FilterType = Enum.RaycastFilterType.Exclude -- exclude the owned rigs and floor rather than make them map obstructions
overlap.FilterDescendantsInstances = {agents, floor} -- floor contact is expected and the low collider space still needs debris checks
overlap.CollisionGroup = "MazeAgents" -- body sensing uses the same collision rules as the moving rig
overlap.RespectCanCollide = true -- decorative and queryable objects shouldnt become solid navigation evidence
overlap.MaxParts = 1 -- occupancy only needs one live blocker so the result list stays bounded
local function readcell(cell: number): BasePart? -- check the collider sized body space instead of trust a single center ray
	local pose = CFrame.new(worldpoint(cell) + floor.CFrame.UpVector * 2.3) * floor.CFrame.Rotation -- the query follows the floor rotation and full collider height while excluding floor contact
	return workspace:GetPartBoundsInBox(pose, Vector3.new(2.6, 4.6, 2.6), overlap)[1] -- the full collider height catches low debris while the expected floor contact is excluded
end -- one physical blocker is enough to deny this body space
for _, part in maze:GetDescendants() do -- thin overlays need classification without touching the floor or owned rigs
	if not part:IsA("BasePart") or part == floor or part:IsDescendantOf(agents) then continue end -- only physical maze decoration can enter the overlay check
	local point = floor.CFrame:PointToObjectSpace(part.Position) -- overlay bounds are checked against this floors own axes
	local bottom, top = part.Position.Y - part.Size.Y / 2, part.Position.Y + part.Size.Y / 2 -- both overlay faces need to stay near the floor before its collision policy changes
	local inside = math.abs(point.X) <= floor.Size.X / 2 and math.abs(point.Z) <= floor.Size.Z / 2 -- decoration outside this floor must not inherit its navigation classification
	if inside and part.Size.Y <= 2 and part.Size.X <= 16 and part.Size.Z <= 16 -- keep decoration small thin and at floor level rather than hide a real wall
		and bottom <= floor.Position.Y + floor.Size.Y / 2 + 0.2 and top <= floor.Position.Y + floor.Size.Y / 2 + 2.1 then -- the height checks exclude raised solid geometry from the thin overlay policy
		part.CollisionGroup = "MazeNavigationDecor" -- each physical or decorative part receives the matching navigation policy
		part:SetAttribute("MazeNavigationDecor", true) -- leave the classification inspectable instead of rely only on a group name
	end -- only floor level thin overlays received the decorative collision policy
end -- authored solid walls were not reclassified as navigation decoration

local function spawnpoints(): {Vector3} -- real wall geometry checks spawns but stays out of shared discovery memory
	local physical = newgrid(map.width, map.height) -- only this private map receives authored walls for validating spawn connectivity
	for _, part in maze:GetChildren() do -- authored direct wall children supply geometry for spawn reachability only
		if not part:IsA("BasePart") or string.find(part.Name, "Wall_", 1, true) ~= 1 then continue end -- the wall naming contract selects solid grid geometry without counting markers
		local cell = cellfromworld(part.Position) -- the common floor encoder keeps geometry and reachability on matching cells
		if cell then discover(physical, cell, true) end -- physical wall evidence stays out of the shared observations that agents learn themselves
	end -- physical spawn walls were collected without updating the belief map
	local flood = newsearch(physical, goalcell, nil) -- no goal mode settles every reachable cell using the same bounded neighbor and heap rules
	while flood.route == nil do stepsearch(flood, 1024) end -- the exhausted frontier gives the complete connected component before seeded spawn choices begin
	local points = {} -- a reachable tile supplies a standing height without sharing its geometry with the planner
	for index = 0, map.width * map.height - 1 do -- this order keeps the existing x first spawn enumeration and seeded shuffle behavior
		local cell = index % map.height * map.width + math.floor(index / map.height) + 1 -- column first enumeration matches the original spawn ordering so the same seeded shuffle gets the same candidates
		local point = worldpoint(cell) + Vector3.new(0, 3, 0) -- a reachable tile supplies a standing height without sharing its geometry with the planner
		if flood.costs[cell] ~= nil and planar(point, goal.Position) >= 24 then table.insert(points, point) end -- a finite reached price proves connectivity and the existing goal gap still excludes close starts
	end -- ordinary spawn candidates keep their original deterministic enumeration order
	return points -- spawn geometry is returned without writing any agent discoveries
end -- spawn reachability stayed separate from agent belief memory

local function setup() -- fresh private state keeps replay from borrowing an old route or search
	local old = script:FindFirstChild("maze probes") -- replay replaces this controller owned visual tree without touching rig attachments
	if old then old:Destroy() end -- old probes cannot stay alongside their replacement generation
	local probes = object("Folder", script, {Name = "maze probes"}) -- deleting the controller also deletes every probe without a callback
	spawnrandom = Random.new(41317) -- fresh replays restart spawn choices without restarting the collapse stream
	local models, selected, points, maximum = {}, {}, spawnpoints(), 0 -- a stable name order keeps staged roles and seeded spawn choices repeatable
	for _, model in agents:GetChildren() do if model:IsA("Model") then table.insert(models, model) end end -- only authored models can become rigs or staged roles
	table.sort(models, function(left, right) return left.Name < right.Name end) -- stable rig order keeps the staged roles attached to the same authored models
	shuffle(points, spawnrandom) -- spawn order uses the fresh spawn seed while collapse randomness stays separate
	for _, point in points do maximum = math.max(maximum, planar(point, goal.Position)) end -- measure the far side threshold against real reachable positions
	for _, rule in {{maximum * 0.76, 32, math.min(4, #models)}, {0, 32, #models}, {0, 0, #models}} do -- far side choices ordinary spacing and fallback remain separate policies
		choose(points, selected, rule[2], rule[3], rule[1]) -- these three passes keep far side starts spacing and the final spacing fallback
	end -- the final pass can relax spacing without duplicating a chosen center
	assert(#selected >= #models, "not enough reachable spawn cells") -- every ordinary rig needs a reachable spawn choice before setup can continue
	for name in agents:GetAttributes() do if string.sub(name, 1, 4) == "demo" then agents:SetAttribute(name, nil) end end -- clear only demo fields so unrelated authored metadata stays alone
	attributes(agents, {demofocus = demowall.Position, democell = democell, demowall = demowall.Name, -- focus identity and fresh demo flags belong to the new staged run
		demophase = "discovery", demoshared = false, demoshortcut = false, democomplete = false}) -- fresh demo flags must not borrow completion from the last cycle
	for index, model in models do -- stable model order keeps stage roles while every rig gets fresh private resources
		local base = selected[index] -- spawn inspection records the center rather than the small physical jitter
		local jitter = Vector3.new(spawnrandom:NextNumber(-0.7, 0.7), 0, spawnrandom:NextNumber(-0.7, 0.7)) -- a small offset makes starts less uniform without changing their cells
		local yaw = math.rad(spawnrandom:NextInteger(0, 3) * 90) -- keep the seeded quarter turns for ordinary background starts
		local start = ({1219, 1137, 1221})[index] -- the staged starts choose positions and roles but supply no path
		if start then base = worldpoint(start) + floor.CFrame.UpVector * 3 end -- the first three rigs keep their staged centers while background starts keep jitter and yaw
		local pose = if start then CFrame.new(base) else CFrame.new(base + jitter) * CFrame.Angles(0, yaw, 0) -- staged rigs keep an exact center pose while ordinary rigs keep seeded jitter and quarter turns
		model:PivotTo(pose) -- staging chooses a start pose while the planner still has to find the route
		local humanoid = model:FindFirstChildOfClass("Humanoid") -- movement goes through the rig controller instead of teleporting the root
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart? -- the root assembly is the owner for collision shape facing and travel
		if not humanoid or not root or not root:IsA("BasePart") then -- invalid rigs cant own movement collision or probes and must be skipped
			warn("skipped invalid rig " .. model.Name) -- an incomplete authored rig is skipped with its identity rather than abort every other rig
			continue -- this incomplete model cannot own physical movement so the other authored rigs continue
		end -- only valid physical rigs reach collider and movement setup below
		for _, name in {"PathScanMarkers", "NavigationCollider"} do -- replay replaces only the two resource names created by this setup
			local old = model:FindFirstChild(name) -- find only earlier geometry owned under this same resource name
			if old then old:Destroy() end -- remove the earlier owned instance before creating its replacement
		end -- replay has removed old owned geometry before replacing it
		local collider = object("Part", model, { -- this welded body keeps the rigs limbs out of navigation collisions
			Name = "NavigationCollider", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.6, 2.35, 2.35), -- keep the welded cylinder contract and its existing physical dimensions
			CFrame = root.CFrame * CFrame.new(0, -0.7, 0) * CFrame.Angles(0, 0, math.rad(90)), -- the root local offset and quarter turn put the cylinder upright beneath the rig
			Transparency = 1, CastShadow = false, CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 1, 1), -- the collider is invisible but its density and friction still affect the assembly
		}) -- the root now has its configured physical cylinder before the weld joins them
		collisions(collider, true, false) -- the collider contacts walls but doesnt appear in sensor results
		object("WeldConstraint", collider, {Name = "NavigationColliderWeld", Part0 = root, Part1 = collider}) -- the collider follows the root as one physical assembly
		for _, part in model:GetDescendants() do -- every body part needs the same group while the single collider owns contact
			if not part:IsA("BasePart") then continue end -- nonphysical descendants cannot receive collision or ownership settings
			if part ~= collider then part.CanCollide = false end -- limb collisions must not fight the single navigation body
			part.CollisionGroup = "MazeAgents" -- each physical or decorative part receives the matching navigation policy
			if not part.Anchored then own(part) end -- only dynamic assemblies can accept network ownership
		end -- the navigation cylinder is the only body part that still owns contact
		humanoid.WalkSpeed = 13 -- keep the current walking pace rather than speed up the demonstration
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false) -- climbing a wall would skip the flat grid movement contract
		local rays = RaycastParams.new() -- probe queries use the same agent collision policy as body sensing
		rays.FilterDescendantsInstances = {agents} -- a rig must not read its own probes or another agents limbs as walls
		rays.RespectCanCollide = true -- the probe should report physical clearance rather than visual decoration
		rays.CollisionGroup = "MazeAgents" -- side rays and the body box use the same agent collision policy
		local folder = object("Folder", probes, {Name = model.Name}) -- each rig keeps its own probe tree under the controller lifetime
		local markers = {} -- each direction keeps its own six dots for drawing and cleanup
		for direction = 1, 7 do -- keep all seven named directions rather than pool their marker state
			local line = {} -- each direction owns a separate six dot line instead of reuse another direction
			local group = object("Folder", folder, {Name = string.format("Direction_%02d", direction)}) -- direction folders keep the existing probe paths available to observers
			for dot = 1, 6 do -- each direction retains its existing six ordered dots
				table.insert(line, object(visual, group, {Name = string.format("Dot_%02d", dot)})) -- cloned defaults keep all six ordered dots nonphysical and independently owned
			end -- the six dots keep separate positions pulse delays and cleanup references
			table.insert(markers, line) -- directions keep separate dot lines instead of share mutable marker state
		end -- each probe direction now has its own complete marker line
		local cell = cellfromworld(root.Position) :: number -- the actual configured root position becomes this rigs checked starting anchor
		local state = setmetatable({model = model, root = root, humanoid = humanoid, markers = markers, rays = rays, markerfolder = folder, -- private fields belong to this rig while the metatable supplies shared methods
			mode = "queued", anchor = cell, target = cell, route = {}, cursor = 2, failures = 0, dirty = true, -- fresh movement fields start without a borrowed route or progress history
			peerchanges = 0, shortcuts = 0, sharedat = -math.huge, openings = {}, reason = "initial plan", -- sharing shortcut counters and pending openings belong to this run only
			nextplan = math.huge, started = 0, progress = 0, best = math.huge, nextcommand = 0, -- viewer readiness chooses the initial deadline and no old clock can start this rig early
		}, agentmetatable) -- method lookup is shared while this route clocks resources and pending evidence stay private
		attributes(model, {SpawnCellX = base.X, SpawnCellZ = base.Z, -- setup keeps the existing public rig fields without giving them planning authority
			SpawnGoalDistance = if start then (base - goal.Position).Magnitude else planar(base, goal.Position), -- staged centers use actual goal distance and ordinary spawn centers keep their planar measurement
			MazeAgent = true, PathState = "queued", CommunicationState = "online", ScannerActive = true, -- the client sees a real initialized rig while route evidence still starts empty
			ReceivedKnowledgeMessages = 0, sharedroutechanges = 0, shortcutchanges = 0, currentcell = cell, targetcell = cell, -- keep existing inspection names while giving staged roles their original start delays
			demorole = if index == 3 then "scout" elseif index <= 2 then "runner" else "background", startdelay = if index <= 3 then 5 else 23}) -- the scout and runners keep their existing roles while background rigs keep the later start
		table.insert(states, state) -- the shared scheduler owns this rigs private state entry
		state.goalpart = object(visual, script, {Name = "navgoal"}) -- a movement target has its own lifetime even if facing falls back
		state:startturn() -- acquire facing after collider setup has produced the physical assembly
	end -- each configured rig now belongs to the shared scheduler and its own resource lifetime
end -- each accepted rig has new owned geometry probes and navigation state

local function draw(state, now: number) -- probes show clearance and sharing while the grid still owns route choices
	local forward = Vector3.new(state.root.CFrame.LookVector.X, 0, state.root.CFrame.LookVector.Z) -- a horizontal facing vector stops root height from tilting the probes
	if forward.Magnitude < 0.01 then return end -- a near vertical facing vector cannot supply a horizontal probe basis
	forward = forward.Unit -- a unit facing vector makes angle scoring independent of root scale
	local flat = (worldpoint(state.target) - state.root.Position) * Vector3.new(1, 0, 1) -- project the current target gap onto this flat maze before choosing a facing direction
	local desired = if flat.Magnitude > 0.01 then flat.Unit else forward -- the destination only selects a probe and doesnt replace the planned route
	local best, score, directions, clearances = 1, -math.huge, {}, {} -- a direction must beat the previous score and still have body clearance
	for index, angle in scanangles do -- each existing angle keeps its own clearance and desired direction score
		local direction = CFrame.Angles(0, -math.rad(angle), 0):VectorToWorldSpace(forward) -- the angle rotates a direction rather than moving the rig itself
		local side = Vector3.new(-direction.Z, 0, direction.X) * 0.8 -- offset rays check the sides that a center ray could miss
		local clearance = 14 -- the shortest of these hits sets how far this probe can be drawn
		for _, offset in {Vector3.zero, side, -side} do -- three rays catch side obstructions that one center ray would miss
			local hit = workspace:Raycast(state.root.Position + Vector3.new(0, 1.25, 0) + offset, direction * 14, state.rays) -- a live query result is evidence of clearance rather than map knowledge
			if hit then clearance = math.min(clearance, hit.Distance) end -- the nearest physical hit limits this directions visible length
		end -- side and center evidence now share one conservative clearance
		directions[index], clearances[index] = direction, clearance -- drawing uses the exact direction and shortest clearance checked for this probe
		if clearance >= 3.96 and direction:Dot(desired) > score then best, score = index, direction:Dot(desired) end -- a good angle still needs enough body clearance to become green
	end -- direction scores use the same clearances later used to hide dots
	for index, line in state.markers do -- draw each owned direction using its own checked clearance
		for dot, marker in line do -- dot order supplies distance and the traveling shared pulse delay
			local chosen = index == best and score > -math.huge -- green needs both the best direction and a usable clearance score
			local age = now - state.sharedat -- the peer pulse uses time since receipt rather than the movement clock
			local pulse = age >= (dot - 1) * 0.075 and age <= (dot - 1) * 0.075 + 0.18 -- each dot has its own delayed short cyan window so the peer message travels along the line
			local color = if pulse then Color3.fromRGB(53, 217, 255) elseif chosen then Color3.fromRGB(55, 255, 120) else wrongcolor -- peer cyan takes priority over the selected green direction
			local alpha = if dot * 2.2 > clearances[index] + 0.15 then 1 elseif chosen then 0.06 else 0.16 -- dots behind a hit stay hidden even when that direction is selected
			local point = state.root.Position + directions[index] * dot * 2.2 -- dot distance follows this checked direction and leaves the root position unchanged
			marker.Color = marker.Color:Lerp(color, 0.62) -- smooth the chosen or shared cue instead of snap every update
			marker.Transparency += (alpha - marker.Transparency) * 0.62 -- clearance still hides dots even while their color is interpolating
			marker.Size = marker.Size:Lerp(Vector3.new(0.1, if chosen then 0.68 else 0.58, if chosen then 0.68 else 0.58), 0.62) -- the selected direction has its existing slightly larger dot diameter
			marker.CFrame = CFrame.new(point.X, 0.07, point.Z) * CFrame.Angles(0, 0, math.rad(90)) -- the dots lie flat at their original display height and never move the rig
		end -- this direction kept its individual distance and shared pulse timing
	end -- every owned line was drawn without changing the planned path
	state.model:SetAttribute("CorrectProbe", best) -- this direction witness stays presentation data rather than a movement command
end -- display changes did not command movement or change learned occupancy

local function mode(state, value: string) -- keep the private lifecycle and its visible state in step
	state.mode = value -- private lifecycle state changes with the visible inspection field below
	attributes(state.model, {PathState = value, currentcell = state.anchor, targetcell = state.target}) -- private state reached center and command destination remain distinct visible witnesses
end -- the private state and visible lifecycle label now agree
function agentmethods.stopturn(state) -- only the acquired solver leaves while the authored attachment and rotation setting stay on the rig
	if state.alignment then state.alignment:Destroy() end -- destroy only the constraint acquired by this turning owner
	state.alignment, state.attachment = nil, nil -- the authored frame stays in the rig while this state drops its borrowed reference
end -- the authored frame and rotation setting stay on the rig after its solver leaves
function agentmethods.startturn(state) -- take server ownership before adding a second source of rotation
	state:stopturn() -- release the solver without mutating the authored frame or humanoid setting
	local ok, problem = own(state.root) -- facing starts only after the common transfer proved server ownership
	if not ok then return warn("turning unavailable for " .. state.model.Name .. " " .. tostring(problem)) end -- ownership denial keeps normal humanoid facing available and records its reason
	state.attachment = state.root:FindFirstChild("RootAttachment") -- this authored frame stays on the rig through controller teardown
	assert(state.attachment and state.attachment:IsA("Attachment"), "rig needs its authored RootAttachment") -- missing authored frames cannot create a hidden second physics owner
	state.alignment = object("AlignOrientation", script, { -- the solver is active in the world but belongs to the controller for automatic destruction
		Name = "navturnalignment", Mode = Enum.OrientationAlignmentMode.OneAttachment, AlignType = Enum.AlignType.AllAxes, -- one attachment and all axes keep this flat maze turning owner explicit
		Attachment0 = state.attachment, CFrame = state.root.CFrame.Rotation * state.attachment.CFrame.Rotation, -- the authored frame offset turns an attachment goal into the intended root heading
		MaxTorque = math.clamp(state.root.AssemblyMass * 1800, 5000, 100000), -- heavier assemblies gain torque while both extremes stay bounded
		MaxAngularVelocity = math.rad(240), Responsiveness = 12, RigidityEnabled = false, ReactionTorqueEnabled = false, Enabled = false, -- finite angular speed and soft response avoid an unlimited rigid rotation owner
	}) -- the owned solver stays soft and the authored humanoid rotation setting remains unchanged
end -- translation is still with the humanoid and only facing gained an owner
function agentmethods.drive(state, target: Vector3?) -- one command owner keeps route following and recovery from fighting each other
	local alignment = state.alignment -- an owned constraint can receive a facing goal without changing the root pose
	if alignment and (not alignment.Parent or not state.attachment or state.attachment.Parent ~= state.root) then state:stopturn() end -- a missing owned part must restore the humanoid fallback rather than keep partial turning
	if state.alignment then -- only the still valid owned pair can receive a new goal
		local flat = ((target or state.root.Position) - state.root.Position) * Vector3.new(1, 0, 1) -- project the current target gap onto this flat maze before choosing a facing direction
		state.alignment.Enabled = flat.Magnitude > 0.05 -- a stop or near zero gap cannot supply a valid facing direction
		if state.alignment.Enabled then state.alignment.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit) * state.attachment.CFrame.Rotation end -- the borrowed attachment offset must not turn the root away from the chosen heading
	end -- the facing goal only reached a complete still owned pair
	local moving = target and state.goalpart -- only a request with its owned native target can become travel
	local destination = if moving then target :: Vector3 else state.root.Position -- ordinary stops still point at the current root rather than a stale route cell
	if moving then moving.CFrame = CFrame.new(destination) end -- the part center and requested world destination agree before the engine receives them
	state.humanoid:MoveTo(destination, moving or nil) -- one native command either follows the owned part or clears its earlier movement request
end -- the same command owner handled either travel or cancellation
local function cancel(state) -- old frontier storage must leave when its start or owner is no longer valid
	if not state.job then return end -- repeated cancellation is harmless once no frontier is owned
	state.job = nil -- the cancelled frontier no longer belongs to this rigs next plan
	state.model:SetAttribute("searchcancellations", (state.model:GetAttribute("searchcancellations") or 0) + 1) -- count abandoned jobs separately from finished route searches
end -- a cancelled search no longer has a path into route adoption
function agentmethods.retire(state, value: string) -- a finished rig has no travel command search or turning constraint left running
	mode(state, value) -- the command or retirement phase updates both private state and its inspection label
	if state.root.Parent and state.humanoid.Parent then state:drive(nil) end -- removed physical components cannot accept a final stop command
	state.route = {} -- terminal state must not retain waypoints that another discovery could revive
	cancel(state) -- the abandoned frontier cannot install another result later
	state:stopturn() -- release the solver without mutating the authored frame or humanoid setting
	if state.goalpart then state.goalpart:Destroy() end -- normal retirement releases the native target after the stop command
	state.goalpart = nil -- this state cannot reuse a deleted movement target
	state.markerfolder:ClearAllChildren() -- all these direction folders and dots were created by this rig owner
	table.clear(state.markers) -- no later drawing pass can keep references to the retired dots
	attributes(state.model, {currentcell = state.anchor, ScannerActive = false, CommunicationState = "offline"}) -- the reached anchor stays visible while scanner and communication labels become inactive
	return false -- this path cannot offer valid work or clearance to its caller
end -- this rig cannot keep scanning moving or planning after retirement
local function message(phase: string, text: string, now: number) -- the cached snapshot lets a late viewer see the current explanation
	noticerevision += 1 -- late clients can distinguish this explanation from an older snapshot
	nextnotice = now + 4 -- notice pacing never controls whether changed evidence reaches the shared map
	local kinds = {warning = "collapse_warning", falling = "collapse", shortcut = "recommended", complete = "recommended"} -- notice colors describe the accepted state rather than decide it
	attributes(agents, {demophase = phase, demomessage = text, -- the phase text and serialized serial form one current client snapshot
		demosnapshot = httpservice:JSONEncode({message = text, kind = kinds[phase] or "shared", serial = noticerevision})}) -- serialize a current notice copy so a late viewer need not catch an earlier remote
end -- the cached notice explains server evidence without granting client authority

local function publish(cell: number, blocked: boolean, source: string, now: number) -- share changed evidence before deciding which rigs actually need another route
	blocked = blocked or gates[cell] ~= nil -- an active collapse hold takes priority over a temporarily empty body query
	local old = map.cells[cell] -- a confirmed old blockage is needed before this can count as a reopened cell
	if not discover(map, cell, blocked) then return end -- unchanged occupancy needs neither new peer work nor another notice
	local reopened = old ~= nil and old.blocked and not blocked -- only confirmed blocked to clear changes count as openings
	if cell == democell and blocked and not old then attributes(agents, {demoscout = source, demodiscoveredat = now}) end -- the first checked blockage identifies the actual scouting source and time
	local affected = 0 -- a notice counts peers whose existing route actually needs work
	for _, state in states do -- shared evidence considers each active private route without overwriting it
		if state.mode == "arrived" or state.mode == "stopped" then continue end -- finished rigs must not be revived by another discovery
		state.model:SetAttribute("SharedMemoryVersion", map.revision) -- knowledge can advance before this rig finishes another search
		local first = table.find(state.route, state.anchor) or 1 -- completed route prefixes must not inflate the remaining cost
		local useful = reopened and couldshorten(map, state.anchor, cell, goalcell, routecost(map, state.route, first)) -- the cheap bound rejects openings that cannot beat the old remainder
		if not (useful or (reopened and state.mode == "waiting") or (blocked and table.find(state.route, cell, state.cursor))) then continue end -- only a useful opening a waiting rig or a blocked remaining route needs new work
		if reopened then state.openings[cell] = true end -- remember the opening until a finished route comparison consumes it
		state.dirty = true -- this route needs another comparison and has not yet been replaced
		local external = source == "structural change" or source == "debris cleared" -- world changes are not credited as messages from a scouting peer
		state.reason = if external then "structural change" elseif state.model.Name == source then "local discovery" else "shared discovery" -- world changes local sensing and peer messages keep different planning causes
		attributes(state.model, {LastKnowledgeSource = source, lastdiscoverycell = cell}) -- this pending reroute keeps the actual source and affected cell together
		if external or source == state.model.Name then continue end -- a rig does not receive its own observation as a peer message
		state.sharedat, affected = now, affected + 1 -- this accepted peer update owns both the pulse time and its one notice recipient count
		if blocked then state.peertrigger, state.peersource = cell, source end -- save the peers actual blocked cell until both old and new routes can be compared
	end -- other rigs kept their private routes while relevant ones gained pending work
	agents:SetAttribute("KnowledgeMessagesPublished", map.revision) -- the visible counter follows real changed occupancy rather than repeated scans
	if affected == 0 or now < nextnotice or not agents:GetAttribute("democomplete") then return end -- notice pacing cannot turn irrelevant or staged evidence into a public route claim
	nextnotice = now + 2 -- notice pacing never controls whether changed evidence reaches the shared map
	knowledgeevent:FireAllClients({message = string.format("%s found %s - %d agents are updating their routes", -- clients receive explanations while the server keeps navigation decisions
		string.lower(source), if blocked then "a blockage" else "an opening", affected), -- the caption names the checked source and the number of affected peers
		kind = if blocked then "blocked" else "recommended", version = map.revision}) -- notice style follows the accepted occupancy and carries its revision
end -- only relevant active routes were marked and unchanged observations stayed silent
local function refresh(cells: {[number]: boolean}, source: string, now: number) -- a missing chunk isnt proof of clearance if another part occupies its cell
	for cell in cells do -- each affected body box is queried once even when several fragments touched it
		local part = readcell(cell) -- the current physical occupant decides blockage and stays available for rechecks
		blockers[cell] = if part then {part = part, checked = now} else nil -- keep the live occupant and scan age or drop the cache when the box is clear
		publish(cell, part ~= nil, source, now) -- only the physical query result becomes shared occupancy evidence
	end -- the whole candidate set has fresh occupancy evidence before it is discarded
end -- occupancy came from current body queries rather than old part references
local function sense(state, now: number) -- nearby body queries teach the map without handing it the whole maze
	publish(state.anchor, false, state.model.Name, now) -- the reached center is checked clear before sensing its neighbors
	local cells = {} -- only adjacent bounded centers become this rigs next local observations
	for _, cell in neighbors(map, state.anchor) do cells[cell] = true end -- only nearby centers become fresh local observations
	refresh(cells, state.model.Name, now) -- neighbor body evidence is shared under this actual scouting rigs name
	mode(state, "planning") -- this reached rig can offer work to the fair search queue
end -- planning can now use fresh observations around a reached center
local function beginmove(state, target: number, value: string, now: number) -- new targets get new stall clocks while ordinary command refreshes dont
	state.target, state.started, state.progress, state.best, state.nextcommand = target, now, now, math.huge, now + 0.5 -- a new destination owns its clocks best gap and next refresh deadline together
	mode(state, value) -- the command or retirement phase updates both private state and its inspection label
	state:drive(worldpoint(target)) -- commands use the same cell transform as sensing and arrival checks
end -- later command refreshes must not restart these movement clocks

local function witnesses(state, route: {number}, cost: number, first: number, oldcost: number, now: number, contrast: search?) -- route geometry and prices are needed before claiming a shared change or shortcut
	local old = state.route -- peer rerouting still compares with the actually adopted path rather than the closed comparison path
	local before = if contrast and oldcost == math.huge then contrast.route :: {number} else old -- a valid old route stays the baseline unless a closed passage comparison is needed
	local begin = if before == old then first else 1 -- the comparison starts at the reached anchor rather than at completed travel
	local price = if before == old then oldcost else routecost(map, before, 1) -- compare against current prices instead of an outdated saved total
	for cell in state.openings do -- each pending opening still needs a finite cheaper route that actually uses it
		if price == math.huge or cost >= price - 0.0001 then break end -- an invalid baseline or a nonimproving price cannot support a shortcut claim
		if not table.find(route, cell) or table.find(before, cell, begin) then continue end -- the proposed path must use a cell that the baseline did not already use
		state.shortcuts += 1 -- count a real adopted improvement rather than a visual opening notice
		attributes(state.model, {shortcutchanges = state.shortcuts, shortcutcell = cell, shortcutbeforecost = price, shortcutaftercost = cost}) -- the adopted saving keeps its opening cell and both checked prices
		break -- one checked improvement is enough for this adoption and no other opening should get duplicate credit
	end -- shortcut counts came only from finite cheaper geometry through a new cell
	if state.openings[democell] and price < math.huge and #route > 0 and #route < #before - begin + 1 -- the focus demonstration needs fewer real remaining moves through its actual opening
		and table.find(route, democell) and not table.find(before, democell, begin) then -- the open path really uses this doorway and the checked detour did not already use it
		state.demopath = true -- the chosen geometry really uses the opening and can later supply a crossing witness
		if not agents:GetAttribute("demoshortcut") then -- one accepted comparison owns the displayed shortcut explanation
			attributes(agents, {demoshortcut = true, demoshortcutagent = state.model.Name, -- the saving includes the chosen agent both remaining move counts and its adoption time
				demobeforesteps = #before - begin, demoaftersteps = #route - 1, demoshortcutat = now}) -- compare remaining moves against a valid detour without counting completed travel
			message("shortcut", string.format("%s found a shorter route through the cleared wall: %d moves instead of %d", -- the caption follows a checked route saving rather than assume every opening helps
				state.model.Name, #route - 1, #before - begin), now) -- both move counts come from the compared route geometry
		end -- the displayed shortcut witness cannot be overwritten by a later notice
	end -- the focus claim now has fewer moves and an actual path through the opening
	local changed = #route ~= #old - first + 1 -- a sharing animation alone cant prove that a different route was adopted
	for index, cell in route do changed = changed or old[first + index - 1] ~= cell end -- compare cell order as well as length so equal length reroutes still count
	local trigger = state.peertrigger -- the saved blocked cell links this reroute to the earlier peer message
	if not changed or not trigger or #route == 0 or not table.find(old, trigger, first) or table.find(route, trigger) then return end -- the new path must really change around the saved peers blocked cell
	state.peerchanges += 1 -- the new route must actually change around the peers blocked cell
	local separation = (state.root.Position - worldpoint(trigger)).Magnitude -- a remote reaction needs actual distance from the discovered cell
	attributes(state.model, {sharedroutechanges = state.peerchanges, sharedchangeat = now, -- the changed route keeps its time blocked cell sender and physical separation
		sharedchangecell = trigger, sharedchangesource = state.peersource, sharedchangedistance = separation}) -- keep the source cell sender and separation with this adopted reroute
	if trigger ~= democell or distance(map, state.anchor, trigger) < 2 or agents:GetAttribute("demoshared") then return end -- the staged hold needs a distant reaction to the focus wall and can happen only once
	state.demohold = true -- a planned route can be shown during the collapse pause without allowing travel yet
	state.nextplan = now + 25 -- this deadline belongs to retry or observation waiting rather than useful travel progress
	attributes(agents, {demoshared = true, demoreceiver = state.model.Name, demosource = state.peersource, -- the first distant reroute records the receiver and the peers actual source
		demoshareddistance = separation, demosharedat = now}) -- the demonstration records a distant peer reaction with its actual timestamp
	message("shared", state.peersource .. " found the wall - " .. state.model.Name .. " changed route before reaching it", now) -- this explanation follows a real reroute before the receiver reached the wall
end -- shortcut and sharing claims stayed tied to real compared geometry
local function adopt(state, job: search, now: number) -- compare old and new evidence before replacing the rigs active route
	local first = table.find(state.route, state.anchor) or 1 -- completed route prefixes must not inflate the remaining cost
	local oldcost = if state.route[first] == state.anchor then routecost(map, state.route, first) else math.huge -- only a remainder that begins at the actual reached anchor can supply a finite old baseline
	local route, cost = job.route :: {number}, job.cost -- this is a candidate until price geometry and ownership checks finish
	if next(state.openings) and oldcost < math.huge and cost >= oldcost - 0.0001 then -- a newly checked opening does not justify dropping an already valid cheaper remainder
		route, cost = table.move(state.route, first, #state.route, 1, {}), oldcost -- keep the valid old remainder when the checked opening did not give a cheaper alternative
	end -- the valid old remainder survived any nonimproving opening candidate
	witnesses(state, route, cost, first, oldcost, now, job.contrast) -- read both routes and their pending causes before adoption overwrites the old one
	table.clear(state.openings) -- this comparison consumed the openings so later searches cant claim them again
	state.peertrigger = nil -- this comparison consumed the saved peer blockage
	state.route, state.cursor, state.dirty, state.primed = route, 2, false, #route > 1 -- adoption sets the next unwalked entry and keeps first plan readiness private to this cycle
	attributes(state.model, {routerevision = job.revision, routecost = if cost == math.huge then -1 else cost, -- publish the chosen geometry with its validated belief revision and current price
		WaypointCount = #route, replanreason = state.reason, plannedroute = table.concat(route, ","), -- inspection gets the chosen geometry and cause without access to the mutable route table
		searchexpansions = job.expansions, searchpops = job.pops, searchwait = now - state.queuedat}) -- completed search work and queue wait stay separate from physical movement timing
	if #route == 0 then -- a finished failed search needs bounded waiting and new sensing
		mode(state, "waiting") -- a failed result pauses commands until bounded sensing and retry can reconsider it
		state.nextplan = now + 1 -- this deadline belongs to retry or observation waiting rather than useful travel progress
		return -- waiting or a presentation hold has already handled this result so no travel command can follow
	end -- only a usable result can reach physical movement handling below
	if #route == 1 then return state:retire("arrived") end -- the reached anchor is already the goal so this rig can retire
	if state.demohold then -- planning during the presentation hold cannot start physical travel
		state.target = state.anchor -- an observation hold keeps its destination at the reached anchor
		state:drive(nil) -- stop the old command before waiting comparing or retiring this rig
		mode(state, "observing") -- this rig may compare knowledge during the demo hold without walking yet
		return -- waiting or a presentation hold has already handled this result so no travel command can follow
	end -- held route work returned before a travel command could escape
	beginmove(state, route[2], "moving", now) -- this finished adopted route supplies its first unwalked waypoint
end -- the chosen route starts at the current anchor and owns the next movement step
local function recover(state, now: number) -- go back to a checked center and keep the recovery attempts bounded
	state.failures += 1 -- recovery cannot retry an impossible physical move forever
	state.dirty = true -- this route needs another comparison and has not yet been replaced
	cancel(state) -- returning toward an anchor invalidates any frontier tied to the previous reached start
	beginmove(state, state.anchor, "recovering", now) -- the return command uses the checked anchor and a new bounded recovery attempt
end -- the next plan still needs a physically reached clear center
local function update(state, now: number): boolean -- physical arrival and recovery run even when no search work is available
	if state.mode == "arrived" or state.mode == "stopped" then return false end -- terminal movement states cannot offer another search slot
	if not state.model:IsDescendantOf(agents) or state.humanoid.Health <= 0 or not state.root.Parent then return state:retire("stopped") end -- removed dead or incomplete rigs release their commands before another movement decision
	if state.mode == "observing" and (agents:GetAttribute("democlearedat") or now >= state.nextplan) then -- accepted clearance normally ends the hold and its deadline prevents endless waiting
		state.demohold, state.dirty = false, true -- clear only the presentation hold and request a fresh route comparison
		mode(state, "planning") -- this reached rig can offer work to the fair search queue
		agents:SetAttribute("demoresumedat", now) -- a requested resume is timed separately from the later physical crossing
	end -- the presentation hold ended without bypassing normal collision gates
	if state.mode == "queued" then -- initial alignment waits for readiness and the staged start gate
		local ready = states[1].primed and states[2].primed -- current private search results gate the scout and dont leak across replay
		if now < state.nextplan or (state.model:GetAttribute("demorole") == "scout" and not ready) then return false end -- the scout needs current first routes and every rig keeps its own countdown
		beginmove(state, state.anchor, "recovering", now) -- the initial queued rig reaches its exact grid center before asking for a route
	end -- the start deadline and current first route gate passed before alignment
	if state.mode == "moving" or state.mode == "recovering" then -- both travel and a return to the anchor need physical arrival checks
		local known = map.cells[state.target] -- shared target evidence can stop this move before physical contact
		if state.mode == "moving" and known and known.blocked then recover(state, now) end -- peer evidence can stop an approach before local contact reaches the wall
		local horizontal = planar(state.root.Position, worldpoint(state.target)) -- arrival ignores the roots standing height above the floor
		if horizontal <= 1.1 then -- arrival tolerance is checked before a successful step could look like a timeout
			local crossing = state.anchor == democell and state.target ~= democell and state.demoentry -- the agent must leave the opening on a different side after choosing its shortcut
				and state.target ~= state.demoentry and state.demopath and not agents:GetAttribute("democomplete") -- different entry and exit sides plus an adopted shortcut are needed for a real traversal claim
			if crossing then -- entry and exit evidence is accepted only after the chosen shortcut is physically used
				attributes(agents, {democomplete = true, demotraversedby = state.model.Name, demotraversedat = now, -- real crossing stores both sides and the agent that physically used the passage
					demoexitcell = state.target, demoentrycell = state.demoentry}) -- different entry and exit cells prove passage traversal rather than touching its center
				message("complete", state.model.Name .. " walked through the new passage - shared discovery and shortcut demonstrated", now) -- the agent has physically left the new passage after adopting its shortcut
			end -- physical entry and exit evidence now owns the complete caption
			if state.target == democell and state.anchor ~= democell then state.demoentry = state.anchor end -- remember the side this rig entered from before the anchor is updated
			state.anchor, state.failures = state.target, 0 -- only measured arrival can commit a new search start and reset recovery attempts
			state:drive(nil) -- stop the old command before waiting comparing or retiring this rig
			sense(state, now) -- learn the reached center and its neighbors before choosing another step
			if state.anchor == goalcell then return state:retire("arrived") end -- a measured goal arrival ends both movement and its owned resources
			if not state.dirty and state.cursor < #state.route then -- an unchanged valid route can keep its next waypoint without another search
				state.cursor += 1 -- advance the existing route only while newer evidence has not made it dirty
				beginmove(state, state.route[state.cursor], "moving", now) -- an unchanged path supplies the next actual waypoint without a new search
			end -- an unchanged route reused its next waypoint without another search
		else -- only an unreached target needs progress timing and possible recovery
			if horizontal < state.best - 0.15 then state.best, state.progress = horizontal, now end -- arrival tolerance is checked before a successful step could look like a timeout
			if state.mode == "moving" and (now - state.progress > 1.5 or now - state.started > 2.5) then -- useful progress and total travel time both bound a stalled approach
				refresh({[state.target] = true}, state.model.Name, now) -- recheck the stalled body target before deciding this was only a movement failure
				state.reason = "movement recovery" -- world changes local sensing and peer messages keep different planning causes
				recover(state, now) -- return toward a checked center before another route search is allowed
			elseif state.mode == "recovering" and now - state.started > 2.5 then -- a failed return needs a clear bounded alternative rather than endless refreshes
				local cell = cellfromworld(state.root.Position) -- a failed anchor return can consider only the roots current bounded body center
				if not cell or readcell(cell) or state.failures >= 4 then return state:retire("stopped") end -- an alternate anchor must be inside the grid clear for the body and within the retry cap
				state.anchor, state.failures = cell, state.failures + 1 -- accepting a new recovery anchor also spends one of this rigs bounded retries
				beginmove(state, cell, "recovering", now) -- the body checked alternative anchor gets its own bounded return command
			elseif now >= state.nextcommand then -- command cadence does not restart useful progress or total travel clocks
				state.nextcommand = now + 0.5 -- refresh the same command without restarting total or useful progress clocks
				state:drive(worldpoint(state.target)) -- commands use the same cell transform as sensing and arrival checks
			end -- only active surviving movement reaches further lifecycle work
		end -- unreached targets received stall handling while reached ones committed their anchor
	end -- active travel completed its arrival or recovery checks before planning
	if state.mode == "waiting" and now >= state.nextplan then sense(state, now) end -- a delayed failed search learns nearby geometry before asking for work again
	draw(state, now) -- clearance and peer pulses are presentation and dont pick the route
	return state.mode == "planning" or (state.mode == "observing" and state.dirty) -- this boolean offers search work and is not arrival evidence
end -- search eligibility was decided after physical lifecycle and progress checks

local function compatible(job: search, closed: number?): boolean -- changed cells need a proof that this finished route is still a valid best choice
	local price = routecost(map, job.route :: {number}, 1) -- compare against current prices instead of an outdated saved total
	for cell, known in map.cells do -- changed observations need checking while identical immutable records can be skipped
		if cell == closed or job.map.cells[cell] == known then continue end -- ignore only the intended comparison door or an observation record that has not changed
		local invalid = if known.blocked then table.find(job.route :: {number}, cell) ~= nil -- a new wall invalidates this result only if the chosen route actually uses its cell
			else couldshorten(map, job.start, cell, job.goal :: number, price) -- only goal jobs reach adoption and a newly clear cell must not admit a cheaper path
		if invalid then return false end -- unchanged or harmless observations leave this fixed result eligible
	end -- all changed cells were harmless under the checked route and lower bound tests
	return true -- every changed observation passed the route validity and best case improvement checks
end -- changed evidence cannot invalidate this path or improve an alternative beyond its checked price
local function searches(now: number) -- rotate between pending jobs and charge every heap pop to the same allowance
	local budget, deadline, visits = 1024, os.clock() + 0.003, 0 -- node allowance and elapsed time both limit a dispatch and neither is a hard real time promise
	while running and budget > 0 and visits < #states * 8 and os.clock() < deadline do -- node allowance elapsed time and finite fair rounds all bound this dispatch
		searchcursor = searchcursor % #states + 1 -- resume after the last served rig instead of always begin at the first array entry
		visits += 1 -- even skipped rigs contribute to the finite dispatch scan limit
		local state = states[searchcursor] -- private fields belong to this rig while the metatable supplies shared methods
		if not state.eligible then continue end -- movement has already run and this rig currently has no planning work
		if state.job and (state.job.start ~= state.anchor or state.jobgeneration ~= generation) then cancel(state) end -- stale starts and previous runs lose their frontier before any further work
		local job = state.job -- this reference is now absent or belongs to the current reached anchor and run
		if not job then -- construct only one frontier for this rigs current planning request
			job = newsearch(map, state.anchor, goalcell) -- this new job starts from the currently reached center and current beliefs
			state.job, state.jobgeneration, state.queuedat = job, generation, now -- the rig owns this frontier along with its replay token and queue time
		end -- the rig now owns one unfinished search rather than duplicate requests
		if job.route and state.openings[democell] and not job.contrast then -- a closed passage comparison is needed only after the open route has finished
			job.contrast = newsearch(job.map, state.anchor, goalcell) -- the detour search starts from the same snapshot as the open route
			job.contrast.map.cells[democell] = {blocked = true} -- only this passage changes so the comparison does not borrow unrelated knowledge
		end -- the closed comparison uses the same belief snapshot with just this doorway changed
		local active = job.contrast or job -- the comparison search uses the same allowance as the open route search
		local spent = stepsearch(active, math.min(128, budget), deadline) -- stale entries count too so they cant bypass the work limit
		budget -= spent -- comparison work and ordinary path work use the same node allowance
		state.model:SetAttribute("searchslices", (state.model:GetAttribute("searchslices") or 0) + 1) -- partial progress stays visible even before a route finishes
		if job.route and active.route then -- both the ordinary route and any closed passage comparison must have settled before adoption
			if job.revision ~= map.revision and (not compatible(job) or (job.contrast and not compatible(job.contrast, democell))) then -- a changed map needs valid open and closed results rather than a stale installation
				cancel(state) -- this job failed an ownership or changed observation check and cannot install its result
				continue -- the cancelled stale result cannot fall through into adoption
			end -- a stale route did not reach the adoption code below
			job.cost, job.revision = routecost(map, job.route, 1), map.revision -- current prices and the validated revision travel with the adopted route
			state.job, state.eligible = nil, false -- a consumed job cannot start a second plan for this rig in the same dispatch
			adopt(state, job, now) -- ownership and changed observation checks have finished before this route becomes active
		end -- only required finished validated results reached adoption
	end -- no job exceeded the global work allowance or finite fair scan limit
	agents:SetAttribute("searchwork", 1024 - budget) -- the global counter includes stale and closed comparison pops too
end -- remaining jobs keep their work and cannot bypass the shared dispatch allowance
local function collidable(part: BasePart): boolean -- a saved fragment reference is not proof of a live obstruction
	return part:IsDescendantOf(world) and part.CanCollide -- only a part still in this copied world and still solid can hold clearance
end -- old or nonphysical pieces cannot keep a passage blocked
local function footprint(record): {[number]: boolean} -- project rotated bounds into floor space then check those candidate body boxes
	local cells = {[record.cell] = true} -- the source cell stays included even after fragments move away from it
	for _, part in record.parts do -- only the parts from this accepted wall phase contribute footprint candidates
		if not collidable(part) then continue end -- removed and noncolliding fragments cannot keep cells under a debris refresh
		local pose, size = floor.CFrame:ToObjectSpace(part.CFrame), part.Size / 2 -- the part basis is expressed in floor space before expanding its rotated x and z bounds
		local right, up, look = pose.RightVector, pose.UpVector, pose.LookVector -- each local box axis contributes to the projected floor bounds
		local xradius = math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z + 1.3 -- scalar products keep the earlier precision and include the same horizontal body margin
		local zradius = math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z + 1.3 -- the other floor axis needs contributions from all three rotated box directions too
		local point = pose.Position - origin -- the projected box center uses the same center origin as encoded grid cells
		for z = math.max(0, math.ceil((point.Z - zradius) / 8)), math.min(map.height - 1, math.floor((point.Z + zradius) / 8)) do -- clamp projected rows to real centers within the floor bounds
			for x = math.max(0, math.ceil((point.X - xradius) / 8)), math.min(map.width - 1, math.floor((point.X + xradius) / 8)) do -- check every body center touched by the expanded rotated x bound
				cells[z * map.width + x + 1] = true -- each expanded bound contributes a unique query center using the common row stride
			end -- this projected row contains every potentially touched body center
		end -- only bounded rows can enter the physical refresh set
	end -- old source cells and rotated current parts now form one candidate set
	return cells -- these are conservative query candidates rather than claims of exact overlap
end -- these conservative candidates still need actual body queries
local function setgate(cell: number, id: string, blocked: boolean) -- each wall owns one hold and clearing it cant release another walls hold
	local gate = gates[cell] or {} -- reuse existing holds but allow a missing set to be cleared harmlessly
	gate[id] = if blocked then true else nil -- this wall adds or removes only its own hold
	gates[cell] = if next(gate) then gate else nil -- an empty set must disappear because entry presence means the cell is held
end -- empty gate sets no longer pretend to own a blocked cell
local function anysolid(parts): boolean -- clearance needs every tracked collidable part to be gone or disabled
	for _, part in parts do if collidable(part) then return true end end -- one live collidable part is enough to deny clearance
	return false -- every tracked piece failed the live solid test so none can keep this passage blocked
end -- no tracked collidable part remained when this helper returned clear
local function worldchanged(data) -- the current owner and ordered phase must agree before changing navigation
	if typeof(data) ~= "table" or data.owner ~= debrisfolder or not running then return end -- phase messages need the current physical owner and a running controller
	local phases = {warning = 1, falling = 2, cleared = 3} -- phase names and revisions must describe the same transition
	if typeof(data.phase) ~= "string" or not phases[data.phase] then return end -- unknown phase names cannot choose a revision or a display state
	if typeof(data.id) ~= "string" or #data.id == 0 or #data.id > 128 or phases[data.phase] ~= data.revision then return end -- a bounded wall id and matching phase revision are needed before looking up history
	if typeof(data.position) ~= "Vector3" or typeof(data.parts) ~= "table" or #data.parts > 64 then return end -- world inputs must have a usable position and a bounded list of parts
	if not (data.position.Magnitude < math.huge) then return end -- a finite length rejects every invalid axis before its world position becomes a cell
	local cell = cellfromworld(data.position) -- the phase position must identify a real grid cell before it can own a hold
	local old = collapses[data.id] -- prior phase and cell identity reject reordered events for this wall
	if not cell or (old and (data.revision <= old.revision or cell ~= old.cell)) then return end -- an id cannot move cells or replay an earlier phase within this generation
	for _, part in data.parts do -- validate the complete payload before storing any part references
		if typeof(part) ~= "Instance" or not part:IsA("BasePart") or (part.Parent and not part:IsDescendantOf(debrisfolder)) then return end -- only physical parts from this debris owner can support its phase
	end -- the accepted payload contains only physical references owned by this folder
	if data.phase == "cleared" and (anysolid(if old then old.parts else {}) or anysolid(data.parts)) then return end -- both previous and reported parts must have stopped colliding before a gate opens
	local record = {cell = cell, phase = data.phase, revision = data.revision, parts = table.clone(data.parts), -- one ordered occupancy record also owns clearance tracking for these pieces
		id = data.id, position = data.position} -- the accepted identity and origin stay available for the later physical clearance event
	local cells = footprint(record) -- old and new projected regions choose the body queries needed before this phase changes occupancy
	if old then for oldcell in old.footprint do cells[oldcell] = true end end -- vacated footprint cells need another query as well as newly touched ones
	record.footprint = if data.phase == "cleared" then {} else cells -- keep the new affected region only while this record still owns falling parts
	if data.phase == "cleared" then table.clear(record.parts) end -- finished records should not retain dead fragment references
	collapses[data.id] = record -- accepted phase history belongs to this wall within the current folder lifetime
	setgate(cell, data.id, data.phase ~= "cleared") -- warning and falling hold the source cell while accepted clearance releases only this id
	refresh(cells, "structural change", os.clock()) -- accepted phase geometry still needs physical rechecks before reopening any candidate
	attributes(agents, {lastcollapsephase = data.phase, lastcollapsecell = cell}) -- publish this checked demo state through the existing client contract
	local notices = { -- each phase keeps its focus explanation background wording and existing client kind together
		warning = {"the runner pauses nearby - watch the orange wall", "is becoming unstable", "collapse_warning"}, -- the warning describes the stable wall before any physical release
		falling = {"the wall collapsed - waiting for all debris to clear", "collapsed - watching the debris", "collapse"}, -- falling never promises that the passage is already usable
		cleared = {"debris is clear - agents can now compare routes through the opening", "debris cleared - checking the opening", "shared"}, -- physical clearance precedes both notices and route comparisons
	} -- presentation words cannot choose the validated phase or occupancy
	local notice = notices[data.phase] -- validation above guarantees one of the three presentation records
	if cell == democell then -- the staged doorway also owns the cached explanation and timestamp
		agents:SetAttribute("demo" .. data.phase .. "at", os.clock()) -- this timestamp follows the accepted phase rather than a scheduled guess
		message(data.phase, notice[1], os.clock()) -- late viewers can read the focus explanation from its current snapshot
	else -- other walls still send their existing live notices without replacing the focus snapshot
		knowledgeevent:FireAllClients({message = string.lower(data.id) .. " " .. notice[2], kind = notice[3], version = map.revision}) -- the checked wall id and revision accompany this background phase
	end -- focus and background notices follow the same ordered validation
end -- only a current owner and valid phase can change navigation or its explanation

local function announce(wall, phase: string, revision: number) -- copy the part list so the next release cant change an earlier phase message
	wall.clearing = phase == "cleared" -- one pending clearance announcement is enough while its deferred validator catches up
	worldevent:Fire({owner = debrisfolder, id = wall.id, position = wall.position, -- the phase list is copied so later release work cant rewrite this message
		phase = phase, revision = revision, parts = table.clone(wall.parts)}) -- the copied part list and revision describe this completed release stage
end -- later release layers cannot mutate the part list already sent

local function updatedebris(now: number) -- old and new footprints both need checks when fragments move
	local cells = {} -- all moving walls contribute before one deduplicated refresh pass
	for _, record in collapses do -- only current falling records can move their tracked footprint
		if record.phase ~= "falling" then continue end -- warnings and cleared records need no moving fragment projection
		local fresh = footprint(record) -- new debris positions need checking alongside the cells they just left
		for cell in record.footprint do cells[cell] = true end -- keep the vacated region for physical refresh
		for cell in fresh do cells[cell] = true end -- join newly occupied candidates before making any occupancy claim
		record.footprint = fresh -- keep the new affected region only while this record still owns falling parts
	end -- all current moving footprints joined the refresh candidates
	refresh(cells, "structural change", now) -- moving fragments refresh both the region they occupied and the one they just vacated
	for cell, obstruction in blockers do -- cached moving occupants need rechecks even when no phase message arrived
		local part = obstruction.part -- the current physical occupant decides blockage and stays available for rechecks
		local static = part:IsDescendantOf(maze) and part.CanCollide and part.Anchored and string.match(part.Name, "^Wall_") -- anchored authored walls dont need repeated moving debris queries
		if now - obstruction.checked >= 1 and not static then refresh({[cell] = true}, "debris cleared", now) end -- age limits repeat work while static authored walls keep their stable evidence
	end -- cached dynamic blockers were rechecked without repeatedly querying static walls
end -- occupied and vacated regions both received current physical checks

local timers, chunks, templates, selected, candidatecount = {}, {}, {}, {}, 0 -- replay keeps selection counts while effect and template resources have separate lifetimes
local cycledeadline, replayat, collapseindex = 0, nil, 0 -- the whole run has a deadline even if one rig never reaches a terminal state
local function schedule(delay: number, callback: () -> ()) -- the action deadline and replay ownership travel together
	push(timers, {score = os.clock() + delay, callback = callback, generation = generation}) -- the same heap orders deadlines while the generation rejects obsolete work
end -- a delayed action cannot borrow the lifetime of the next replay
local function selectwalls() -- keep the focus wall and select the other interior walls with the same exclusions
	local candidates = {} -- interior and exclusion checks happen before random spacing selection
	for _, wall in maze:GetChildren() do -- selection only considers actual authored direct wall parts
		if not wall:IsA("BasePart") or not string.match(wall.Name, "^Wall_") or not wall.Anchored or not wall.CanCollide then continue end -- only solid anchored wall geometry can enter the collapse candidate filter
		local point = floor.CFrame:PointToObjectSpace(wall.Position) -- the boundary exclusion is measured in floor axes rather than unshifted world axes
		if wall.Size.Y >= 8 and wall.Size.X >= 4 and wall.Size.Z >= 4 -- wall dimensions distinguish substantial collapse geometry from small decoration
			and math.abs(point.X) <= floor.Size.X / 2 - 20 and math.abs(point.Z) <= floor.Size.Z / 2 - 20 -- the floor boundary margin keeps the chosen collapse inside the maze
			and planar(wall.Position, goal.Position) >= 32 and (not spawnlocation or planar(wall.Position, spawnlocation.Position) >= 28) then -- the goal and actual spawn keep their existing exclusion radii
			table.insert(candidates, wall) -- only walls that passed all physical and exclusion checks enter selection
		end -- only substantial safe interior walls entered random selection
	end -- selection candidates kept all interior goal and spawn exclusions
	shuffle(candidates, random) -- keep the seeded wall order before applying spacing fallbacks
	selected, candidatecount = {demowall}, #candidates -- keep the focus first and retain the real candidate count for every replay
	for _, spacing in {48, 24} do choose(candidates, selected, spacing, 8, 0) end -- the relaxed spacing pass fills remaining choices without duplicating earlier walls
	for index, wall in selected do -- selected order and stable metadata belong to the templates used for replay
		attributes(wall, {CollapsibleWall = true, CollapseOrder = index, CollapseState = "stable"}) -- stable collapse metadata follows the real selected order and survives template replay
		table.insert(templates, wall:Clone()) -- these eight authored originals are the only walls replay may restore
	end -- every captured template has its selected order and stable phase metadata
end -- the focus and spaced choices now have owned replay templates

local function debris(wall, layer: {BasePart}, number: number) -- physical chunks and little fragments keep their separate cleanup rules
	for _, chunk in layer do -- each chunk takes ownership and release timing when its own layer falls
		local offset = chunk.Position - wall.position -- release force is measured away from this wall rather than from the world origin
		local outward = Vector3.new(offset.X, 0, offset.Z) -- a usable outward direction avoids a zero length normalization
		outward = if outward.Magnitude < 0.1 then wall.pose.RightVector else outward.Unit -- the wall basis supplies a direction when an offset is too small to normalize
		local tangent = Vector3.new(-outward.Z, 0, outward.X) * random:NextNumber(-0.3, 0.3) -- a little sideways variation keeps the release from being perfectly radial
		local downward = random:NextNumber(1, 4) + (3 - number) * 0.5 -- lower layers get their own downward speed rather than float in place
		chunk.Anchored = false -- the layer becomes physical only after its split and ownership setup
		own(chunk) -- the server keeps authority as each anchored chunk starts falling
		chunk.AssemblyLinearVelocity = (outward + tangent).Unit * random:NextNumber(11, 18) + Vector3.new(0, -downward, 0) -- outward tangent and downward terms give the same layered release motion
		chunk.AssemblyAngularVelocity = Vector3.new(random:NextNumber(-9, 9), random:NextNumber(-6, 6), random:NextNumber(-9, 9)) -- each physical chunk keeps the existing seeded tumble ranges
		chunk:SetAttribute("ReleasedTowardGround", true) -- this witness records an actual release rather than a planned one
		chunks[chunk] = os.clock() -- landing checks need time since this particular chunk was released
		schedule(5.5 + random:NextNumber(0, 1.2), function() -- large chunks keep their original delayed collision removal and fade
			if not chunk.Parent then return end -- a chunk already removed by reset needs no fade or collision mutation
			collisions(chunk, false) -- fading debris must stop blocking before the last visible fade finishes
			tween(chunk, 0.65, {Transparency = 1}, Enum.EasingStyle.Quad) -- collision has ended and this tween only finishes the visible cleanup
			schedule(0.75, function() chunk:Destroy() end) -- the fade has finished before the owned chunk is destroyed
		end) -- this owned chunk now has collision removal fade and final destruction deadlines
	end -- all chunks in this layer own release landing and cleanup work
	for index = 1, 6 do -- each released layer still creates its original six little fragments
		local width, height = random:NextNumber(0.18, 0.55), random:NextNumber(0.15, 0.5) -- x and z share this width while height has its own draw
		local offset = Vector3.new(random:NextNumber(-wall.size.X * 0.48, wall.size.X * 0.48), -- these random local offsets keep small fragments inside the captured wall volume before world conversion
			random:NextNumber(-wall.size.Y * 0.25, wall.size.Y * 0.48), random:NextNumber(-wall.size.Z * 0.48, wall.size.Z * 0.48)) -- offsets remain inside the authored wall volume on all three axes
		local fragment = object("Part", debrisfolder, { -- small pieces keep the authored material and their shorter lifetime
			Name = "falling_fragment", Size = Vector3.new(width, height, width), CFrame = wall.pose * CFrame.new(offset), -- fragment dimensions and offsets use the seeded draws rather than change the wall shape
			Color = wall.color, Material = wall.material, CustomPhysicalProperties = PhysicalProperties.new(1.8, 0.65, 0.05, 100, 20), -- small debris keeps the authored surface with its own physical material response
		}) -- the new fragment has its authored surface and independent physical response
		collisions(fragment, index <= 3) -- only the existing collidable fraction can obstruct agents
		own(fragment) -- fragment physics also stays with the server rather than a nearby viewer
		table.insert(wall.parts, fragment) -- clearance tracks the actual created parts from every release layer
		fragment.AssemblyLinearVelocity = Vector3.new(random:NextNumber(-10, 10), random:NextNumber(3, 12), random:NextNumber(-10, 10)) -- little fragments keep their existing outward and upward variation
		fragment.AssemblyAngularVelocity = Vector3.new(random:NextNumber(-8, 8), random:NextNumber(-8, 8), random:NextNumber(-8, 8)) -- small debris also keeps seeded tumble rather than borrow chunk rotation
		debrisservice:AddItem(fragment, random:NextNumber(3.5, 5)) -- little fragments use their shorter engine owned cleanup lifetime
	end -- this layer has added its existing six physical fragments to clearance tracking
end -- every released piece keeps its own physical and cleanup lifetime
local function release(wall) -- split the authored wall before its solid original leaves the world
	if not wall.part.Parent then return announce(wall, "cleared", 3) end -- a cancelled warning clears its own hold without inventing falling parts
	wall.part:SetAttribute("CollapseState", "falling") -- the solid wall changes phase only after its warning completes
	local layers = {{}, {}, {}} -- the twelve chunks stay grouped by the order they will be released
	local size = Vector3.new(math.max(0.5, wall.size.X / 2 - 0.08), -- gaps between chunks stop the split from starting with overlapping solid faces
		math.max(0.5, wall.size.Y / 3 - 0.08), math.max(0.5, wall.size.Z / 2 - 0.08)) -- small gaps separate adjacent split faces without changing the three layer layout
	for index = 0, 11 do -- the same twelve slots retain the original layer first creation order
		local x, y, z = math.floor(index % 4 / 2) + 1, math.floor(index / 4) + 1, index % 2 + 1 -- the twelve slots stay ordered by layer so release order and seeded draws stay the same
		local chunk = object(wall.part, debrisfolder, { -- clone the wall style but leave its old children and scripts behind
			Name = string.lower(wall.id) .. "_chunk", Size = size, -- the chunk keeps its wall identity while taking the split box size
			CFrame = wall.pose * CFrame.new((x - 1.5) * wall.size.X / 2, (y - 2) * wall.size.Y / 3, (z - 1.5) * wall.size.Z / 2), -- local slot offsets keep the split aligned with the original wall orientation
			CollisionGroup = "maze_collapse_debris", CanTouch = true, -- released chunks dont collide with each other but still contact the floor and agents
			CustomPhysicalProperties = PhysicalProperties.new(2, 0.35, 0.1, 100, 25), -- keep chunk density friction and bounce separate from the lighter fragments
		}) -- this split keeps the wall style without copying old children into physical chunks
		chunk:SetAttribute("CollapseDebris", true) -- footprint inspection can identify the owned large physical fragments
		table.insert(layers[y], chunk) -- slot order keeps each chunk with the layer that must release it
		table.insert(wall.parts, chunk) -- clearance tracks the actual created parts from every release layer
	end -- all twelve authored split slots now belong to their ordered layers
	wall.part.Transparency = 1 -- hide the original only after the replacement solid chunks exist
	collisions(wall.part, false) -- the hidden original must not keep blocking behind its physical replacements
	local function layer(number: number) -- release lower layers first while all remaining layers still have an owner
		debris(wall, layers[number], number) -- this layer supplies physical chunks and its six smaller fragments
		schedule(0.09, function() -- the next layer waits for the existing release interval
			if number < 3 then return layer(number + 1) end -- release the next layer only after the existing interlayer delay
			announce(wall, "falling", 2) -- all three layers are released and the copied phase list now includes every created piece
			wall.part:Destroy() -- all layers and phase evidence now belong to the replacement parts
			attributes(debrisfolder, {LastCollapsedChunkCount = 12, CollapsedWalls = (debrisfolder:GetAttribute("CollapsedWalls") or 0) + 1}) -- twelve created chunks and one destroyed original justify this completed collapse count
		end) -- the next layer or final phase now waits for its scheduled release boundary
	end -- the next layer or final phase now waits for its scheduled release boundary
	layer(1) -- the first layer starts the ordered release chain
end -- the original wall no longer competes with its twelve physical replacements
local function warnwall(part: BasePart) -- three visible pulses come before the solid wall becomes falling parts
	local wall = {part = part, id = part.Name, position = part.Position, pose = part.CFrame, -- the wall id and captured geometry must survive destruction of its original part
		size = part.Size, color = part.Color, material = part.Material, parts = {}} -- capture wall geometry and style before the original is destroyed
	part:SetAttribute("CollapseState", "warning") -- the warning label matches the still solid wall and visible pulse
	announce(wall, "warning", 1) -- the phase only includes parts that this wall has already created
	local highlight = object("Highlight", debrisfolder, { -- the warning stays visible while the wall is still solid
		Name = "collapse_warning", Adornee = part, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, -- the outline belongs to the still solid wall and stays visible through it
		FillColor = Color3.fromRGB(255, 132, 44), FillTransparency = 0.78, -- fill color and transparency keep the existing orange warning pulse
		OutlineColor = Color3.fromRGB(255, 205, 82), OutlineTransparency = 0.08, -- the brighter outline makes the warning readable before the wall disappears
	}) -- the wall outline has its existing visible warning appearance
	local marker = object(visual, debrisfolder, { -- this visual part must never turn into a sensed obstruction
		Name = "collapse_warning", Size = Vector3.new(part.Size.X * 1.18, 0.08, part.Size.Z * 1.18), -- the floor cue slightly exceeds the wall footprint so its edges remain visible
		CFrame = CFrame.new(part.Position.X, floor.Position.Y + floor.Size.Y / 2 + 0.05, part.Position.Z), -- the warning sits above the top face rather than inside the floor
		Shape = Enum.PartType.Block, Color = Color3.fromRGB(255, 151, 48), Transparency = 0.48, -- the orange rectangular cue overrides the dot template without changing its nonphysical defaults
	}) -- this owned visual part is configured before drawing can reach it
	local function pulse(stage: number) -- three bright and fading pairs keep their original relative deadlines
		local bright = stage % 2 == 1 -- the odd stages start a pulse while even stages finish its fade
		if stage == 7 or (bright and not part.Parent) then -- completion and a cancelled wall release the same warning owner
			highlight:Destroy() -- this owner cannot leave an outline behind either exit
			marker:Destroy() -- its footprint has the same lifetime as the outline
			return if part.Parent then release(wall) else announce(wall, "cleared", 3) -- only a still solid original can become falling pieces
		end -- an unfinished live warning keeps its next original interval
		local duration = if bright then 0.22 else 0.26 -- the original bright and fading delays still drive each stage
		local direction = if bright then Enum.EasingDirection.Out else Enum.EasingDirection.In -- each half keeps its original easing direction
		tween(highlight, duration, {FillTransparency = if bright then 0.38 else 0.82, OutlineTransparency = if bright then 0 else 0.32}, nil, direction) -- highlight goals change together for this half pulse
		tween(marker, duration, {Transparency = if bright then 0.12 else 0.62}, nil, direction) -- the footprint follows the same owned interval
		schedule(duration, function() pulse(stage + 1) end) -- the next stage still passes through the generation checked deadline heap
	end -- only one subsequent stage is queued at a time
	pulse(1) -- the first bright interval begins immediately
end -- the pulse chain owns both cues until cancellation or actual release

local function effects(now: number) -- all delayed work is checked against the active replay owner
	while #timers > 0 and timers[1].score <= now do -- only due work leaves the ordered deadline heap
		local timer = pop(timers) -- a due time alone isnt enough and the replay generation still has to match
		if running and timer.generation == generation then timer.callback() end -- a due callback still needs the same live replay generation
	end -- the next remaining deadline is still in the future
	for _, record in collapses do -- the validated phase record already owns both navigation holds and physical clearance
		if record.phase == "falling" and not record.clearing and not anysolid(record.parts) then announce(record, "cleared", 3) end -- the ordered phase needs actual clearance and cannot be queued twice
	end -- the shared phase owner replaces a second list of the same falling walls
	for chunk, born in chunks do -- landing checks belong to the release time of each actual physical chunk
		if not chunk.Parent or chunk.Anchored or now - born >= 4.5 then -- expired or anchored chunks no longer need active landing work
			chunks[chunk] = nil -- dead anchored or expired landing records no longer need a frame check
			continue -- this inactive landing record cannot reach the resting pose calculations
		end -- only live unanchored unexpired chunks reach resting pose math
		local pose, size = chunk.CFrame, chunk.Size -- the world box basis supplies the lowest vertical extent while this chunk is still moving
		local extent = (math.abs(pose.RightVector.Y) * size.X + math.abs(pose.UpVector.Y) * size.Y + math.abs(pose.LookVector.Y) * size.Z) / 2 -- rotated basis vectors give the actual bottom of this falling box
		local top = floor.Position.Y + floor.Size.Y / 2 -- landing uses the top face of the floor rather than its center
		if now - born < 0.05 or chunk.Position.Y - extent > top + 0.18 or chunk.AssemblyLinearVelocity.Y > 1.5 then continue end -- the box must have fallen to the floor and slowed vertically before it is anchored
		local yaw = CFrame.Angles(0, math.rad(random:NextNumber(0, 360)), 0) -- seeded landing yaw spreads the resting debris without changing its physical clearance checks
		local rotation = if size.X >= size.Z then CFrame.Angles(0, 0, math.rad(90)) else CFrame.Angles(math.rad(90), 0, 0) -- the longer horizontal dimension becomes the resting height
		chunk.CFrame = CFrame.new(chunk.Position.X, top + math.max(size.X, size.Z) / 2 + 0.04, chunk.Position.Z) * yaw * rotation -- put the resting long side above the actual floor top before anchoring
		chunk.AssemblyLinearVelocity, chunk.AssemblyAngularVelocity = Vector3.zero, Vector3.zero -- landing stops both translation and spin before the part becomes static
		chunk.Anchored = true -- the accepted resting pose must not continue tumbling through the floor
		attributes(chunk, {LandedOnMazeFloor = true, LandingY = chunk.Position.Y}) -- these fields record a physical landing after the bottom extent check
	end -- only active falling parts remain eligible for another landing check
end -- due actions and physical landing checks kept their own generation and lifetime checks

local demo = {phase = "waiting", due = 0, deadline = 0} -- the coordinator keeps phase deadlines separate from rig progress timers
local function pause() -- stop remaining movers before any solid wall can return
	for _, state in states do -- every unfinished rig must release travel and facing before walls can return
		if state.mode ~= "arrived" and state.mode ~= "stopped" then state:retire("stopped") end -- completed arrivals stay completed while only remaining movers are stopped
	end -- arrivals stay terminal while the remaining rigs have no travel command left
end -- wall restoration can now happen without active travel commands

local function reset() -- a new generation gets fresh map state rigs walls and delayed work
	pause() -- old travel stops before restoring authored solid geometry and fresh rig state
	generation += 1 -- all pending actions from the old replay become stale together
	for _, list in {states, blockers, collapses, gates, map.cells, timers, chunks} do table.clear(list) end -- old map jobs gates and effect trackers leave with the replay generation
	map.revision, started, replayat, collapseindex = 0, false, nil, 0 -- a fresh replay owns fresh observation history and demonstration timing
	if debrisfolder then debrisfolder:Destroy() end -- only this controllers physical debris owner is destroyed
	debrisfolder = object("Folder", script, {Name = "maze_collapse_debris"}) -- this new folder is the physical owner for the next collapse generation
	selected = {} -- rebuild the selection from captured templates so replay uses the same walls
	for _, template in templates do -- template order keeps the focus wall first during restoration
		local old = maze:FindFirstChild(template.Name) -- a surviving copy of this selected wall must leave before its template is restored
		if old then old:Destroy() end -- remove the earlier owned instance before creating its replacement
		table.insert(selected, template:Clone()) -- keep the full captured wall including authored children in its original selection order
		selected[#selected].Parent = maze -- the latest restored wall enters the maze before setup can command another rig
	end -- selected walls have their authored geometry before any new rig is seeded
	demowall = selected[1] -- the focus reference must point to the restored instance rather than the destroyed original
	setup() -- rebuild per rig resources only after the old generation has been retired
	attributes(agents, {cyclecount = (agents:GetAttribute("cyclecount") or 0) + 1}) -- count the new run outside the demo fields that setup just cleared
	attributes(debrisfolder, {CandidateCount = candidatecount, SelectedWallCount = #selected, CollapsedWalls = 0}) -- each fresh owner keeps selection evidence and starts with no completed collapses
	demo = {phase = "waiting", due = 0, deadline = 0} -- new phase deadlines cannot inherit a completed countdown from the last run
	message("waiting", "waiting for the viewer to finish loading", os.clock()) -- viewer readiness still gates the next demonstration rather than a fixed startup delay
end -- new state cannot inherit old collision holds route jobs or phase deadlines

local function demonstration(now: number) -- advance from observed sharing and crossing rather than just a countdown
	if not started then return end -- the coordinator does no countdown work before viewer readiness
	if demo.phase == "sharing" and agents:GetAttribute("demoshared") then demo.phase, demo.due = "collapse", now + 3 end -- real shared reroute evidence opens the first warning countdown
	if demo.phase == "first" and agents:GetAttribute("democomplete") then demo.phase, demo.due = "collapse", now + random:NextNumber(8, 13) end -- the focus must actually be traversed before another wall is scheduled
	if demo.phase == "collapse" and now >= demo.due then -- only a due phase can warn the next selected wall
		collapseindex += 1 -- each selected wall is warned and released only once per run
		local wall = selected[collapseindex] -- only the currently selected instance can receive this phase warning
		if wall and wall.Parent then warnwall(wall) end -- a missing selected instance cannot be treated as an actual collapse
		demo.phase = if collapseindex == 1 then "first" elseif collapseindex < #selected then "collapse" else "done" -- the focus crossing has its own wait before the remaining collapse sequence
		demo.due = now + 1.71 + (if collapseindex < #selected and collapseindex ~= 1 then random:NextNumber(8, 13) else 0) -- warning release and interwall intervals remain separate scheduled delays
		demo.deadline = if collapseindex == 1 then now + 91.71 else math.huge -- a missing focus crossing cannot hold the demonstration forever
	end -- the next wall still waits for its own phase and interval
	if (demo.phase == "sharing" or demo.phase == "first") and now > demo.deadline then -- a missing sharing or crossing witness remains an incomplete demonstration
		agents:SetAttribute("demophase", "incomplete") -- a timeout stays visible rather than being reported as successful traversal
		demo.phase = "done" -- the focus crossing has its own wait before the remaining collapse sequence
	end -- missing witnesses stayed incomplete rather than looking like successful traversal
	local finished = true -- terminal rigs no longer need the replay coordinator to wait for movement
	for _, state in states do finished = finished and (state.mode == "arrived" or state.mode == "stopped") end -- all rigs must be terminal before an ordinary early replay can begin
	if not replayat and (demo.phase == "done" or now >= cycledeadline) and (finished or now >= cycledeadline) then -- the run ends once and movers stop before the restoration deadline is set
		pause() -- unfinished movers stop before the replay deadline can put solid walls back
		replayat = now + 15 -- the existing replay pause gives viewers time before walls and starts return
		agents:SetAttribute("demoreplayat", workspace:GetServerTimeNow() + 15) -- clients get synchronized server time while the coordinator uses a monotonic deadline
		message("replay", "run finished - restoring the maze for another demonstration in 15 seconds", now) -- the caption follows stopped movers and a scheduled restoration
	end -- the replay deadline was created only after movers stopped
	if replayat and now >= replayat then reset() end -- restoration belongs to its own due time rather than a movement update
end -- the next phase still needs either its real witness or its bounded deadline

script.Parent = maze -- world ancestry activates owned constraints while destruction removes their whole tree
selectwalls() -- wall templates are captured once so replay changes only the chosen walls
reset() -- old delayed work and movement owners leave before this new replay starts
table.insert(connections, knowledgeevent.OnServerEvent:Connect(function(player, action) -- only the existing ready request crosses this client boundary
	if not running or action ~= "ready" or player.Parent ~= players then return end -- only the actual connected player can send the existing ready action
	viewers[player] = true -- ready membership belongs to the actual engine sender
	player:SetAttribute("mazeviewerready", true) -- keep the existing readiness witness for the client loading flow
end)) -- readiness has been recorded only for the actual current player
table.insert(connections, players.PlayerRemoving:Connect(function(player) viewers[player] = nil end)) -- departed players cannot remain in the current viewer membership set
table.insert(connections, worldevent.Event:Connect(worldchanged)) -- phase evidence enters one validated owner path instead of directly changing routes

local heartbeat = game:GetService("RunService").Heartbeat -- one engine tick paces physical effects and bounded movement work
while script.Parent == maze do -- moving the controller out of its live owner stops this composition root
	local dt = heartbeat:Wait() -- the running script owns this wait and destruction cancels its thread
	if script.Parent ~= maze then break end -- the wait can outlive a live parent change so no old effects or commands may run after it
	local now = os.clock() -- this pass uses one monotonic timestamp for its phase and movement checks
	effects(now) -- due visual and cleanup work isnt held up by the navigation sampling interval
	demonstration(now) -- phase and replay deadlines keep running independently of a search result
	elapsed += dt -- sampling uses accumulated frame time rather than assume a fixed frame rate
	if elapsed < 0.16 then continue end -- effect deadlines still advance while movement waits for its sampling interval
	elapsed = 0 -- one navigation pass consumes this interval without replaying missed frame work
	if not started and next(viewers) then -- one real ready viewer starts the current cycle only once
		started = true -- one ready viewer opens the start gate for this cycle
		cycledeadline = now + 240 -- even incomplete navigation has a bounded whole run lifetime
		demo.phase, demo.deadline = "sharing", now + 30 -- sharing must happen before the first collapse warning can begin
		for _, state in states do state.nextplan = now + state.model:GetAttribute("startdelay") end -- each authored start delay is relative to actual viewer readiness
		agents:SetAttribute("demostarted", true) -- world and client observers see a real readiness based start
		message("starting", "starting in 5 seconds - watch the scout and the nearby runner", now) -- the existing countdown explains the staged scout and runner positions
	end -- one current readiness signal started this cycle and its relative delays
	updatedebris(now) -- fresh physical evidence is ready before the scheduler considers finished routes
	for _, state in states do state.eligible = started and update(state, now) end -- every rig gets physical checks before any planning allowance is spent
	searches(now) -- route work runs after every rig has had its movement and sensing checks
end -- the next pass requires this same live owner and another engine tick
running = false -- callbacks still reachable after an ordinary move cannot revive this controller
pause() -- live context shutdown retires rigs before owned instances leave
for _, connection in connections do connection:Disconnect() end -- the ready and phase adapters cannot retain the retired state
script:ClearAllChildren() -- these children were created by this controller and contain only its runtime resources
