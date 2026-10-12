-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
--!strict
type grid = {width: number, height: number, revision: number, cells: {[number]: {blocked: boolean}}} -- a missing cell is unknown rather than a wall
type priority = {score: number}
type entry = {cell: number, cost: number, score: number}
type search = {
	map: grid, start: number, goal: number?, revision: number, -- no goal means explore the whole connected component
	heap: {entry}, costs: {[number]: number}, parents: {[number]: number},
	route: {number}?, cost: number, expansions: number, pops: number, contrast: search?, -- nil means still working and empty means no goal path or a completed reachability sweep
}

local function newgrid(width: number, height: number): grid
	assert(width > 0 and height > 0, "grid dimensions must be positive")
	return {width = width, height = height, revision = 0, cells = {}}
end
local function coordinates(map: grid, cell: number): (number, number)
	return (cell - 1) % map.width, math.floor((cell - 1) / map.width)
end
local function cellat(map: grid, x: number, z: number): number?
	if x < 0 or z < 0 or x >= map.width or z >= map.height then return nil end -- check bounds before encoding so edge neighbors cannot wrap into another row
	return z * map.width + x + 1
end
local function distance(map: grid, left: number, right: number): number
	local x, z = coordinates(map, left)
	local otherx, otherz = coordinates(map, right)
	return math.abs(x - otherx) + math.abs(z - otherz) -- four axis moves cost at least one each so this bound never overestimates
end
local function neighbors(map: grid, cell: number): {number}
	local x, z = coordinates(map, cell)
	local result = {}
	for _, offset in {{1, 0}, {0, 1}, {-1, 0}, {0, -1}} do
		local adjacent = cellat(map, x + offset[1], z + offset[2])
		if adjacent then table.insert(result, adjacent) end
	end
	return result
end

local function push<t>(heap: {t & priority}, item: t & priority) -- path frontiers and effect deadlines can use the same score based heap
	local index = #heap + 1
	while index > 1 do
		local parent = math.floor(index / 2) -- the parent slot is half the child index rounded down
		if heap[parent].score <= item.score then break end
		heap[index], index = heap[parent], parent
	end
	heap[index] = item
end
local function pop<t>(heap: {t & priority}): t & priority
	local first = heap[1]
	local last = table.remove(heap) :: (t & priority)
	if #heap == 0 then return first end
	local index = 1
	while index * 2 <= #heap do
		local child = index * 2
		if child < #heap and heap[child + 1].score < heap[child].score then child += 1 end -- sinking through the cheaper child keeps both branches ordered
		if heap[child].score >= last.score then break end
		heap[index], index = heap[child], child
	end
	heap[index] = last
	return first
end
local function discover(map: grid, cell: number, blocked: boolean): boolean
	assert(cell >= 1 and cell <= map.width * map.height, "discovery outside grid")
	local old = map.cells[cell]
	if old and old.blocked == blocked then return false end -- seeing the same wall again should not restart every search
	map.cells[cell] = {blocked = blocked} -- replace records instead of editing them so shallow search snapshots stay fixed
	map.revision += 1
	return true
end
local function retrace(parents: {[number]: number}, start: number, goal: number): {number}
	local reversed = {goal} -- parent links point toward the start so build backward then reverse once
	while reversed[#reversed] ~= start do table.insert(reversed, parents[reversed[#reversed]]) end
	local route = table.create(#reversed) :: {number}
	for index = #reversed, 1, -1 do table.insert(route, reversed[index]) end
	return route
end
local function newsearch(map: grid, start: number, goal: number?): search
	local snapshot = {width = map.width, height = map.height, revision = map.revision, cells = table.clone(map.cells)} -- only the table needs copying because discoveries replace the cell records
	local job: search = {
		map = snapshot, start = start, goal = goal, revision = map.revision,
		heap = {}, costs = {[start] = 0}, parents = {}, route = nil, cost = math.huge, expansions = 0, pops = 0,
	}
	push(job.heap, {cell = start, cost = 0, score = if goal then distance(map, start, goal) else 0}) -- without a goal use paid cost alone to find the full reachable region
	return job
end
local function stepsearch(job: search, limit: number, deadline: number?): number
	local spent = 0
	while spent < limit and job.route == nil do
		if deadline and os.clock() >= deadline then break end -- check time between pops but this is not a hard frame time guarantee
		if #job.heap == 0 then
			job.route = {}
			break
		end
		local current = pop(job.heap)
		spent, job.pops = spent + 1, job.pops + 1 -- charge stale entries too or duplicates could dodge the slice limit
		if current.cost ~= job.costs[current.cell] then continue end -- better arrivals add new entries so older prices can still be in the heap
		if job.goal and current.cell == job.goal then
			job.route, job.cost = retrace(job.parents, job.start, job.goal), current.cost
			break
		end
		job.expansions += 1
		for _, cell in neighbors(job.map, current.cell) do
			local known = job.map.cells[cell]
			if known and known.blocked then continue end
			local cost = current.cost + (if known then 1 else 1.15) -- unknown stays usable but costs a little more than a checked clear cell
			if cost >= (job.costs[cell] or math.huge) then continue end
			job.costs[cell], job.parents[cell] = cost, current.cell
			push(job.heap, {cell = cell, cost = cost, score = cost + (if job.goal then distance(job.map, cell, job.goal) else 0)})
		end
	end
	return spent
end
local function routecost(map: grid, route: {number}, first: number): number
	if #route == 0 then return math.huge end
	local cost = 0
	for index = first + 1, #route do -- the price comparison starts after the reached anchor and ignores travel already done
		local known = map.cells[route[index]]
		if known and known.blocked then return math.huge end
		cost += if known then 1 else 1.15
	end
	return cost
end
local function couldshorten(map: grid, anchor: number, opened: number, goal: number, cost: number): boolean
	return distance(map, anchor, opened) + distance(map, opened, goal) < cost - 0.0001 -- this only rules out hopeless openings and a promising one still needs a search
end

local players = game:GetService("Players")
local httpservice = game:GetService("HttpService")
local physicsservice = game:GetService("PhysicsService")
local tweenservice = game:GetService("TweenService")
local debrisservice = game:GetService("Debris")
local world = workspace
local maze = world:WaitForChild("Maze")
local agents = world:WaitForChild("MazeAgents")
local floor = maze:WaitForChild("MazeFloor") :: BasePart
local goal = maze:WaitForChild("GoalPad") :: BasePart
local knowledgeevent = game:GetService("ReplicatedStorage"):WaitForChild("maze_knowledge_event") :: RemoteEvent
local worldevent = game:GetService("ServerStorage"):WaitForChild("maze_world_changed") :: BindableEvent
local spawnlocation = world:FindFirstChildOfClass("SpawnLocation")
local map = newgrid(math.round(floor.Size.X / 8), math.round(floor.Size.Z / 8))
local origin = Vector3.new(-floor.Size.X / 2 + 4, floor.Size.Y / 2, -floor.Size.Z / 2 + 4) -- the first tile center is four studs in from each edge of the floor
local states, connections, viewers = {}, {}, {}
local blockers, collapses, gates = {}, {}, {}
local running, started, generation = true, false, 0
local debrisfolder = world:FindFirstChild("maze_collapse_debris") :: Folder?
local elapsed, searchcursor, noticerevision, nextnotice = 0, 0, 0, 0
local spawnrandom, random = Random.new(41317), Random.new(76231)
local scanangles = {-72, -48, -24, 0, 24, 48, 72}
local wrongcolor = Color3.fromRGB(255, 62, 72)
local agentmethods = {}
local agentmetatable = {__index = agentmethods} -- share the methods while routes clocks and owned parts stay private to each rig

local function attributes(item: Instance, values: {[string]: any})
	for name, value in values do item:SetAttribute(name, value) end
end
local function object(class: string | Instance, parent: Instance, values: {[string]: any}): any
	local item = if typeof(class) == "string" then Instance.new(class) else class:Clone()
	if typeof(class) ~= "string" then item:ClearAllChildren() end -- a copied chunk should not bring along scripts or welds from the original wall
	for property, value in values do (item :: any)[property] = value end
	item.Parent = parent -- finish setting properties before the instance enters the world
	return item
end
local visual = object("Part", script, {
	Name = "maze visual template", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.58, 0.58),
	Anchored = true, CastShadow = false, Material = Enum.Material.Neon, Color = wrongcolor, Transparency = 1,
	CanCollide = false, CanQuery = false, CanTouch = false,
})
local function collisions(part: BasePart, enabled: boolean, query: boolean?)
	part.CanCollide, part.CanQuery, part.CanTouch = enabled, if query == nil then enabled else query, false
end
local function own(part: BasePart)
	return pcall(function()
		assert(part:CanSetNetworkOwnership())
		part:SetNetworkOwner(nil) -- movement and debris stay server owned so nearby clients do not drive the simulation
		assert(part:GetNetworkOwner() == nil, "server ownership required")
	end)
end
local function tween(item: Instance, duration: number, values: {[string]: any}, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local animation = tweenservice:Create(item, TweenInfo.new(duration, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.Out), values)
	animation:Play()
end
local function worldpoint(cell: number): Vector3
	local x, z = coordinates(map, cell)
	return floor.CFrame:PointToWorldSpace(origin + Vector3.new(x * 8, 0, z * 8)) -- floor space keeps tile centers aligned when the maze is rotated
end
local function cellfromworld(position: Vector3): number?
	local point = floor.CFrame:PointToObjectSpace(position) - origin
	return cellat(map, math.round(point.X / 8), math.round(point.Z / 8))
end
local goalcell = assert(cellfromworld(goal.Position), "goal is outside the grid")
local demowall = maze:WaitForChild("Wall_32_31") :: BasePart
local democell = cellfromworld(demowall.Position) :: number
local function planar(left: Vector3, right: Vector3): number
	return Vector2.new(left.X - right.X, left.Z - right.Z).Magnitude
end
local function choose(list, selected, spacing: number, wanted: number, threshold: number)
	for _, item in list do
		if #selected >= wanted then break end
		local point = if typeof(item) == "Vector3" then item else item.Position
		local allowed = not table.find(selected, item) and planar(point, goal.Position) >= threshold
		for _, old in selected do
			allowed = allowed and planar(point, if typeof(old) == "Vector3" then old else old.Position) >= spacing
		end
		if allowed then table.insert(selected, item) end
	end
end
local function shuffle(list: {any}, rng: Random)
	for index = #list, 2, -1 do
		local other = rng:NextInteger(1, index)
		list[index], list[other] = list[other], list[index]
	end
end

for _, group in {"MazeAgents", "MazeNavigationDecor", "maze_collapse_debris"} do
	pcall(function() physicsservice:RegisterCollisionGroup(group) end)
	physicsservice:CollisionGroupSetCollidable(group, group, false) -- rigs and debris should not pile up against others in their own group
end
physicsservice:CollisionGroupSetCollidable("MazeAgents", "MazeNavigationDecor", false)
local overlap = OverlapParams.new() -- reuse query settings since every cell uses the same body and collision policy
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.FilterDescendantsInstances = {agents, floor} -- floor contact and other rigs are expected but low debris still needs checking
overlap.CollisionGroup = "MazeAgents"
overlap.RespectCanCollide = true
overlap.MaxParts = 1
local function readcell(cell: number): BasePart?
	local pose = CFrame.new(worldpoint(cell) + floor.CFrame.UpVector * 2.3) * floor.CFrame.Rotation
	return workspace:GetPartBoundsInBox(pose, Vector3.new(2.6, 4.6, 2.6), overlap)[1] -- check the whole body space since a center ray can miss low rubble
end
for _, part in maze:GetDescendants() do
	if not part:IsA("BasePart") or part == floor or part:IsDescendantOf(agents) then continue end
	local point = floor.CFrame:PointToObjectSpace(part.Position)
	local bottom, top = part.Position.Y - part.Size.Y / 2, part.Position.Y + part.Size.Y / 2
	local inside = math.abs(point.X) <= floor.Size.X / 2 and math.abs(point.Z) <= floor.Size.Z / 2
	if inside and part.Size.Y <= 2 and part.Size.X <= 16 and part.Size.Z <= 16 -- only small floor overlays qualify so solid walls keep their collision role
		and bottom <= floor.Position.Y + floor.Size.Y / 2 + 0.2 and top <= floor.Position.Y + floor.Size.Y / 2 + 2.1 then
		part.CollisionGroup = "MazeNavigationDecor"
		part:SetAttribute("MazeNavigationDecor", true)
	end
end

local function spawnpoints(): {Vector3}
	local physical = newgrid(map.width, map.height) -- use real walls to validate spawns without teaching the shared map their positions
	for _, part in maze:GetChildren() do
		if not part:IsA("BasePart") or string.find(part.Name, "Wall_", 1, true) ~= 1 then continue end
		local cell = cellfromworld(part.Position)
		if cell then discover(physical, cell, true) end
	end
	local flood = newsearch(physical, goalcell, nil) -- the same search kernel finds spawn connectivity with the goal bound turned off
	while flood.route == nil do stepsearch(flood, 1024) end
	local points = {}
	for index = 0, map.width * map.height - 1 do
		local cell = index % map.height * map.width + math.floor(index / map.height) + 1
		local point = worldpoint(cell) + Vector3.new(0, 3, 0)
		if flood.costs[cell] ~= nil and planar(point, goal.Position) >= 24 then table.insert(points, point) end
	end
	return points
end

local function setup()
	local old = script:FindFirstChild("maze probes")
	if old then old:Destroy() end
	local probes = object("Folder", script, {Name = "maze probes"})
	spawnrandom = Random.new(41317)
	local models, selected, points, maximum = {}, {}, spawnpoints(), 0
	for _, model in agents:GetChildren() do if model:IsA("Model") then table.insert(models, model) end end
	table.sort(models, function(left, right) return left.Name < right.Name end) -- sort first so seeded choices do not depend on child enumeration order
	shuffle(points, spawnrandom)
	for _, point in points do maximum = math.max(maximum, planar(point, goal.Position)) end
	for _, rule in {{maximum * 0.76, 32, math.min(4, #models)}, {0, 32, #models}, {0, 0, #models}} do -- try spaced distant starts first then relax spacing without allowing unreachable cells
		choose(points, selected, rule[2], rule[3], rule[1])
	end
	assert(#selected >= #models, "not enough reachable spawn cells")
	for name in agents:GetAttributes() do if string.sub(name, 1, 4) == "demo" then agents:SetAttribute(name, nil) end end
	attributes(agents, {demofocus = demowall.Position, democell = democell, demowall = demowall.Name,
		demophase = "discovery", demoshared = false, demoshortcut = false, democomplete = false})
	for index, model in models do
		local base = selected[index]
		local jitter = Vector3.new(spawnrandom:NextNumber(-0.7, 0.7), 0, spawnrandom:NextNumber(-0.7, 0.7))
		local yaw = math.rad(spawnrandom:NextInteger(0, 3) * 90)
		local start = ({1219, 1137, 1221})[index] -- stage the two runners and scout near the focus wall without giving them a route
		if start then base = worldpoint(start) + floor.CFrame.UpVector * 3 end
		local pose = if start then CFrame.new(base) else CFrame.new(base + jitter) * CFrame.Angles(0, yaw, 0)
		model:PivotTo(pose)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root or not root:IsA("BasePart") then
			warn("skipped invalid rig " .. model.Name)
			continue
		end
		for _, name in {"PathScanMarkers", "NavigationCollider"} do
			local old = model:FindFirstChild(name)
			if old then old:Destroy() end
		end
		local collider = object("Part", model, {
			Name = "NavigationCollider", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.6, 2.35, 2.35),
			CFrame = root.CFrame * CFrame.new(0, -0.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Transparency = 1, CastShadow = false, CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 1, 1), -- low friction helps the welded collider slide past wall corners
		})
		collisions(collider, true, false)
		object("WeldConstraint", collider, {Name = "NavigationColliderWeld", Part0 = root, Part1 = collider})
		for _, part in model:GetDescendants() do
			if not part:IsA("BasePart") then continue end
			if part ~= collider then part.CanCollide = false end
			part.CollisionGroup = "MazeAgents"
			if not part.Anchored then own(part) end
		end
		humanoid.WalkSpeed = 13
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		local rays = RaycastParams.new()
		rays.FilterDescendantsInstances = {agents} -- probe rays should see the maze rather than hit the other rigs
		rays.RespectCanCollide = true
		rays.CollisionGroup = "MazeAgents"
		local folder = object("Folder", probes, {Name = model.Name})
		local markers = {}
		for direction = 1, 7 do
			local line = {}
			local group = object("Folder", folder, {Name = string.format("Direction_%02d", direction)})
			for dot = 1, 6 do
				table.insert(line, object(visual, group, {Name = string.format("Dot_%02d", dot)}))
			end
			table.insert(markers, line)
		end
		local cell = cellfromworld(root.Position) :: number
		local state = setmetatable({model = model, root = root, humanoid = humanoid, markers = markers, rays = rays, markerfolder = folder,
			mode = "queued", anchor = cell, target = cell, route = {}, cursor = 2, failures = 0, dirty = true,
			peerchanges = 0, shortcuts = 0, sharedat = -math.huge, openings = {}, reason = "initial plan",
			nextplan = math.huge, started = 0, progress = 0, best = math.huge, nextcommand = 0,
		}, agentmetatable)
		attributes(model, {SpawnCellX = base.X, SpawnCellZ = base.Z,
			SpawnGoalDistance = if start then (base - goal.Position).Magnitude else planar(base, goal.Position),
			MazeAgent = true, PathState = "queued", CommunicationState = "online", ScannerActive = true,
			ReceivedKnowledgeMessages = 0, sharedroutechanges = 0, shortcutchanges = 0, currentcell = cell, targetcell = cell,
			demorole = if index == 3 then "scout" elseif index <= 2 then "runner" else "background", startdelay = if index <= 3 then 5 else 23})
		table.insert(states, state)
		state.goalpart = object(visual, script, {Name = "navgoal"}) -- the move target belongs to the script so owner loss removes it with the constraints
		state:startturn()
	end
end

local function draw(state, now: number)
	local forward = Vector3.new(state.root.CFrame.LookVector.X, 0, state.root.CFrame.LookVector.Z)
	if forward.Magnitude < 0.01 then return end
	forward = forward.Unit
	local flat = (worldpoint(state.target) - state.root.Position) * Vector3.new(1, 0, 1)
	local desired = if flat.Magnitude > 0.01 then flat.Unit else forward
	local best, score, directions, clearances = 1, -math.huge, {}, {}
	for index, angle in scanangles do
		local direction = CFrame.Angles(0, -math.rad(angle), 0):VectorToWorldSpace(forward)
		local side = Vector3.new(-direction.Z, 0, direction.X) * 0.8
		local clearance = 14
		for _, offset in {Vector3.zero, side, -side} do -- side rays catch obstacles that a single center ray would miss
			local hit = workspace:Raycast(state.root.Position + Vector3.new(0, 1.25, 0) + offset, direction * 14, state.rays)
			if hit then clearance = math.min(clearance, hit.Distance) end
		end
		directions[index], clearances[index] = direction, clearance
		if clearance >= 3.96 and direction:Dot(desired) > score then best, score = index, direction:Dot(desired) end -- this picks the probe display direction and does not choose the actual route
	end
	for index, line in state.markers do
		for dot, marker in line do
			local chosen = index == best and score > -math.huge
			local age = now - state.sharedat
			local pulse = age >= (dot - 1) * 0.075 and age <= (dot - 1) * 0.075 + 0.18
			local color = if pulse then Color3.fromRGB(53, 217, 255) elseif chosen then Color3.fromRGB(55, 255, 120) else wrongcolor -- cyan shows a received peer update while green shows the useful probe direction
			local alpha = if dot * 2.2 > clearances[index] + 0.15 then 1 elseif chosen then 0.06 else 0.16
			local point = state.root.Position + directions[index] * dot * 2.2
			marker.Color = marker.Color:Lerp(color, 0.62)
			marker.Transparency += (alpha - marker.Transparency) * 0.62
			marker.Size = marker.Size:Lerp(Vector3.new(0.1, if chosen then 0.68 else 0.58, if chosen then 0.68 else 0.58), 0.62)
			marker.CFrame = CFrame.new(point.X, 0.07, point.Z) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
	state.model:SetAttribute("CorrectProbe", best)
end

local function mode(state, value: string)
	state.mode = value
	attributes(state.model, {PathState = value, currentcell = state.anchor, targetcell = state.target})
end
function agentmethods.stopturn(state)
	if state.alignment then state.alignment:Destroy() end
	state.alignment, state.attachment = nil, nil
end
function agentmethods.startturn(state)
	state:stopturn()
	local ok, problem = own(state.root)
	if not ok then return warn("turning unavailable for " .. state.model.Name .. " " .. tostring(problem)) end
	state.attachment = state.root:FindFirstChild("RootAttachment") -- borrow the authored attachment and leave it alone during cleanup
	assert(state.attachment and state.attachment:IsA("Attachment"), "rig needs its authored RootAttachment")
	state.alignment = object("AlignOrientation", script, { -- own the solver under the script so destruction does not need a second cleanup script
		Name = "navturnalignment", Mode = Enum.OrientationAlignmentMode.OneAttachment, AlignType = Enum.AlignType.AllAxes,
		Attachment0 = state.attachment, CFrame = state.root.CFrame.Rotation * state.attachment.CFrame.Rotation, -- include the attachment rotation so its local axes do not tilt the target pose
		MaxTorque = math.clamp(state.root.AssemblyMass * 1800, 5000, 100000), -- heavier rigs need more torque but keep an upper limit
		MaxAngularVelocity = math.rad(240), Responsiveness = 12, RigidityEnabled = false, ReactionTorqueEnabled = false, Enabled = false,
	})
end
function agentmethods.drive(state, target: Vector3?)
	local alignment = state.alignment
	if alignment and (not alignment.Parent or not state.attachment or state.attachment.Parent ~= state.root) then state:stopturn() end
	if state.alignment then
		local flat = ((target or state.root.Position) - state.root.Position) * Vector3.new(1, 0, 1)
		state.alignment.Enabled = flat.Magnitude > 0.05
		if state.alignment.Enabled then state.alignment.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit) * state.attachment.CFrame.Rotation end -- aim on the horizontal plane and account for the authored attachment axes
	end
	local moving = target and state.goalpart
	local destination = if moving then target :: Vector3 else state.root.Position
	if moving then moving.CFrame = CFrame.new(destination) end
	state.humanoid:MoveTo(destination, moving or nil) -- the native target part lets owner loss end the move without code running afterward
end
local function cancel(state)
	if not state.job then return end
	state.job = nil
	state.model:SetAttribute("searchcancellations", (state.model:GetAttribute("searchcancellations") or 0) + 1)
end
function agentmethods.retire(state, value: string)
	mode(state, value)
	if state.root.Parent and state.humanoid.Parent then state:drive(nil) end -- stop translation before deleting the target and turning resources
	state.route = {}
	cancel(state)
	state:stopturn()
	if state.goalpart then state.goalpart:Destroy() end
	state.goalpart = nil
	state.markerfolder:ClearAllChildren()
	table.clear(state.markers)
	attributes(state.model, {currentcell = state.anchor, ScannerActive = false, CommunicationState = "offline"})
	return false
end
local function message(phase: string, text: string, now: number)
	noticerevision += 1
	nextnotice = now + 4
	local kinds = {warning = "collapse_warning", falling = "collapse", shortcut = "recommended", complete = "recommended"}
	attributes(agents, {demophase = phase, demomessage = text,
		demosnapshot = httpservice:JSONEncode({message = text, kind = kinds[phase] or "shared", serial = noticerevision})}) -- late viewers can read the current notice without needing earlier remote messages
end

local function publish(cell: number, blocked: boolean, source: string, now: number)
	blocked = blocked or gates[cell] ~= nil -- warning gates hold the opening even before falling pieces occupy it
	local old = map.cells[cell]
	if not discover(map, cell, blocked) then return end -- repeat observations stop here so only changed knowledge reaches the rigs
	local reopened = old ~= nil and old.blocked and not blocked
	if cell == democell and blocked and not old then attributes(agents, {demoscout = source, demodiscoveredat = now}) end
	local affected = 0
	for _, state in states do
		if state.mode == "arrived" or state.mode == "stopped" then continue end
		state.model:SetAttribute("SharedMemoryVersion", map.revision)
		local first = table.find(state.route, state.anchor) or 1
		local useful = reopened and couldshorten(map, state.anchor, cell, goalcell, routecost(map, state.route, first)) -- an opening is worth replanning only if its best possible route could save travel
		if not (useful or (reopened and state.mode == "waiting") or (blocked and table.find(state.route, cell, state.cursor))) then continue end -- blocked route cells and waiting rigs matter without making every rig replan
		if reopened then state.openings[cell] = true end
		state.dirty = true
		local external = source == "structural change" or source == "debris cleared"
		state.reason = if external then "structural change" elseif state.model.Name == source then "local discovery" else "shared discovery"
		attributes(state.model, {LastKnowledgeSource = source, lastdiscoverycell = cell})
		if external or source == state.model.Name then continue end -- local sensing and structural changes are not counted as received peer knowledge
		state.sharedat, affected = now, affected + 1
		if blocked then state.peertrigger, state.peersource = cell, source end
	end
	agents:SetAttribute("KnowledgeMessagesPublished", map.revision)
	if affected == 0 or now < nextnotice or not agents:GetAttribute("democomplete") then return end -- let the staged demonstration explain itself before sending extra live notices
	nextnotice = now + 2
	knowledgeevent:FireAllClients({message = string.format("%s found %s - %d agents are updating their routes",
		string.lower(source), if blocked then "a blockage" else "an opening", affected),
		kind = if blocked then "blocked" else "recommended", version = map.revision})
end
local function refresh(cells: {[number]: boolean}, source: string, now: number)
	for cell in cells do
		local part = readcell(cell)
		blockers[cell] = if part then {part = part, checked = now} else nil
		publish(cell, part ~= nil, source, now)
	end
end
local function sense(state, now: number)
	publish(state.anchor, false, state.model.Name, now) -- the anchor was physically reached so it is safe to share as clear unless gated
	local cells = {}
	for _, cell in neighbors(map, state.anchor) do cells[cell] = true end
	refresh(cells, state.model.Name, now) -- body checks supply learned neighbors and the probe display does not fill the map
	mode(state, "planning")
end
local function beginmove(state, target: number, value: string, now: number)
	state.target, state.started, state.progress, state.best, state.nextcommand = target, now, now, math.huge, now + 0.5
	mode(state, value)
	state:drive(worldpoint(target))
end

local function witnesses(state, route: {number}, cost: number, first: number, oldcost: number, now: number, contrast: search?)
	local old = state.route
	local before = if contrast and oldcost == math.huge then contrast.route :: {number} else old -- if the old route is gone use the closed passage search as the detour comparison
	local begin = if before == old then first else 1
	local price = if before == old then oldcost else routecost(map, before, 1)
	for cell in state.openings do
		if price == math.huge or cost >= price - 0.0001 then break end
		if not table.find(route, cell) or table.find(before, cell, begin) then continue end
		state.shortcuts += 1
		attributes(state.model, {shortcutchanges = state.shortcuts, shortcutcell = cell, shortcutbeforecost = price, shortcutaftercost = cost})
		break
	end
	if state.openings[democell] and price < math.huge and #route > 0 and #route < #before - begin + 1
		and table.find(route, democell) and not table.find(before, democell, begin) then
		state.demopath = true
		if not agents:GetAttribute("demoshortcut") then
			attributes(agents, {demoshortcut = true, demoshortcutagent = state.model.Name,
				demobeforesteps = #before - begin, demoaftersteps = #route - 1, demoshortcutat = now})
			message("shortcut", string.format("%s found a shorter route through the cleared wall: %d moves instead of %d",
				state.model.Name, #route - 1, #before - begin), now)
		end
	end
	local changed = #route ~= #old - first + 1
	for index, cell in route do changed = changed or old[first + index - 1] ~= cell end
	local trigger = state.peertrigger
	if not changed or not trigger or #route == 0 or not table.find(old, trigger, first) or table.find(route, trigger) then return end -- count a peer reroute only when its reported blocker actually leaves the route
	state.peerchanges += 1
	local separation = (state.root.Position - worldpoint(trigger)).Magnitude
	attributes(state.model, {sharedroutechanges = state.peerchanges, sharedchangeat = now,
		sharedchangecell = trigger, sharedchangesource = state.peersource, sharedchangedistance = separation})
	if trigger ~= democell or distance(map, state.anchor, trigger) < 2 or agents:GetAttribute("demoshared") then return end
	state.demohold = true
	state.nextplan = now + 25
	attributes(agents, {demoshared = true, demoreceiver = state.model.Name, demosource = state.peersource,
		demoshareddistance = separation, demosharedat = now})
	message("shared", state.peersource .. " found the wall - " .. state.model.Name .. " changed route before reaching it", now)
end
local function adopt(state, job: search, now: number)
	local first = table.find(state.route, state.anchor) or 1
	local oldcost = if state.route[first] == state.anchor then routecost(map, state.route, first) else math.huge
	local route, cost = job.route :: {number}, job.cost
	if next(state.openings) and oldcost < math.huge and cost >= oldcost - 0.0001 then -- keep a valid old remainder when the opening search offers no cheaper route
		route, cost = table.move(state.route, first, #state.route, 1, {}), oldcost
	end
	witnesses(state, route, cost, first, oldcost, now, job.contrast)
	table.clear(state.openings)
	state.peertrigger = nil
	state.route, state.cursor, state.dirty, state.primed = route, 2, false, #route > 1 -- the first route cell is the reached anchor so movement starts at the second
	attributes(state.model, {routerevision = job.revision, routecost = if cost == math.huge then -1 else cost,
		WaypointCount = #route, replanreason = state.reason, plannedroute = table.concat(route, ","),
		searchexpansions = job.expansions, searchpops = job.pops, searchwait = now - state.queuedat})
	if #route == 0 then
		mode(state, "waiting")
		state.nextplan = now + 1
		return
	end
	if #route == 1 then return state:retire("arrived") end
	if state.demohold then
		state.target = state.anchor
		state:drive(nil)
		mode(state, "observing")
		return
	end
	beginmove(state, route[2], "moving", now)
end
local function recover(state, now: number)
	state.failures += 1
	state.dirty = true
	cancel(state)
	beginmove(state, state.anchor, "recovering", now) -- return to the last reached center before planning around a stalled move
end
local function update(state, now: number): boolean
	if state.mode == "arrived" or state.mode == "stopped" then return false end
	if not state.model:IsDescendantOf(agents) or state.humanoid.Health <= 0 or not state.root.Parent then return state:retire("stopped") end
	if state.mode == "observing" and (agents:GetAttribute("democlearedat") or now >= state.nextplan) then
		state.demohold, state.dirty = false, true
		mode(state, "planning")
		agents:SetAttribute("demoresumedat", now)
	end
	if state.mode == "queued" then
		local ready = states[1].primed and states[2].primed
		if now < state.nextplan or (state.model:GetAttribute("demorole") == "scout" and not ready) then return false end -- wait for both runners to plan before the scout supplies its discovery
		beginmove(state, state.anchor, "recovering", now)
	end
	if state.mode == "moving" or state.mode == "recovering" then
		local known = map.cells[state.target]
		if state.mode == "moving" and known and known.blocked then recover(state, now) end
		local horizontal = planar(state.root.Position, worldpoint(state.target))
		if horizontal <= 1.1 then
			local crossing = state.anchor == democell and state.target ~= democell and state.demoentry -- a crossing needs a distinct entry and exit rather than just touching the doorway
				and state.target ~= state.demoentry and state.demopath and not agents:GetAttribute("democomplete")
			if crossing then
				attributes(agents, {democomplete = true, demotraversedby = state.model.Name, demotraversedat = now,
					demoexitcell = state.target, demoentrycell = state.demoentry})
				message("complete", state.model.Name .. " walked through the new passage - shared discovery and shortcut demonstrated", now)
			end
			if state.target == democell and state.anchor ~= democell then state.demoentry = state.anchor end
			state.anchor, state.failures = state.target, 0 -- advance the anchor only after the root actually reaches the target center
			state:drive(nil)
			sense(state, now)
			if state.anchor == goalcell then return state:retire("arrived") end
			if not state.dirty and state.cursor < #state.route then
				state.cursor += 1
				beginmove(state, state.route[state.cursor], "moving", now)
			end
		else
			if horizontal < state.best - 0.15 then state.best, state.progress = horizontal, now end
			if state.mode == "moving" and (now - state.progress > 1.5 or now - state.started > 2.5) then -- track both loss of progress and total move time so tiny motion cannot stall forever
				refresh({[state.target] = true}, state.model.Name, now)
				state.reason = "movement recovery"
				recover(state, now)
			elseif state.mode == "recovering" and now - state.started > 2.5 then
				local cell = cellfromworld(state.root.Position)
				if not cell or readcell(cell) or state.failures >= 4 then return state:retire("stopped") end -- a recovery can use a nearby clear cell but repeated failures eventually stop the rig
				state.anchor, state.failures = cell, state.failures + 1
				beginmove(state, cell, "recovering", now)
			elseif now >= state.nextcommand then
				state.nextcommand = now + 0.5
				state:drive(worldpoint(state.target)) -- refresh the native move command without resetting the stall clocks
			end
		end
	end
	if state.mode == "waiting" and now >= state.nextplan then sense(state, now) end
	draw(state, now)
	return state.mode == "planning" or (state.mode == "observing" and state.dirty)
end

local function compatible(job: search, closed: number?): boolean
	local price = routecost(map, job.route :: {number}, 1)
	for cell, known in map.cells do
		if cell == closed or job.map.cells[cell] == known then continue end -- unchanged record identities let us skip observations already in this snapshot
		local invalid = if known.blocked then table.find(job.route :: {number}, cell) ~= nil
			else couldshorten(map, job.start, cell, job.goal :: number, price) -- a newer opening can make a route stale even when no cell on that route is blocked
		if invalid then return false end
	end
	return true
end
local function searches(now: number)
	local budget, deadline, visits = 1024, os.clock() + 0.003, 0 -- pops time and visits bound different kinds of work and none promises a hard deadline
	while running and budget > 0 and visits < #states * 8 and os.clock() < deadline do
		searchcursor = searchcursor % #states + 1 -- keep the cursor between passes so the first rig does not always get the budget
		visits += 1
		local state = states[searchcursor]
		if not state.eligible then continue end
		if state.job and (state.job.start ~= state.anchor or state.jobgeneration ~= generation) then cancel(state) end -- a job from another reached anchor or replay cannot be adopted here
		local job = state.job
		if not job then
			job = newsearch(map, state.anchor, goalcell)
			state.job, state.jobgeneration, state.queuedat = job, generation, now
		end
		if job.route and state.openings[democell] and not job.contrast then
			job.contrast = newsearch(job.map, state.anchor, goalcell) -- compare the same knowledge with just the focus doorway closed
			job.contrast.map.cells[democell] = {blocked = true}
		end
		local active = job.contrast or job
		local spent = stepsearch(active, math.min(128, budget), deadline) -- normal and detour searches share the budget instead of doubling the work allowance
		budget -= spent
		state.model:SetAttribute("searchslices", (state.model:GetAttribute("searchslices") or 0) + 1)
		if job.route and active.route then
			if job.revision ~= map.revision and (not compatible(job) or (job.contrast and not compatible(job.contrast, democell))) then
				cancel(state)
				continue
			end
			job.cost, job.revision = routecost(map, job.route, 1), map.revision -- compatible discoveries may change prices so reprice before adopting
			state.job, state.eligible = nil, false
			adopt(state, job, now)
		end
	end
	agents:SetAttribute("searchwork", 1024 - budget)
end
local function collidable(part: BasePart): boolean
	return part:IsDescendantOf(world) and part.CanCollide
end
local function footprint(record): {[number]: boolean}
	local cells = {[record.cell] = true}
	for _, part in record.parts do
		if not collidable(part) then continue end
		local pose, size = floor.CFrame:ToObjectSpace(part.CFrame), part.Size / 2
		local right, up, look = pose.RightVector, pose.UpVector, pose.LookVector
		local xradius = math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z + 1.3 -- project the rotated box onto floor axes and add half the agent body width
		local zradius = math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z + 1.3
		local point = pose.Position - origin
		for z = math.max(0, math.ceil((point.Z - zradius) / 8)), math.min(map.height - 1, math.floor((point.Z + zradius) / 8)) do
			for x = math.max(0, math.ceil((point.X - xradius) / 8)), math.min(map.width - 1, math.floor((point.X + xradius) / 8)) do
				cells[z * map.width + x + 1] = true
			end
		end
	end
	return cells
end
local function setgate(cell: number, id: string, blocked: boolean)
	local gate = gates[cell] or {}
	gate[id] = if blocked then true else nil -- each collapse holds its own gate so clearing one cannot release another
	gates[cell] = if next(gate) then gate else nil
end
local function anysolid(parts): boolean
	for _, part in parts do if collidable(part) then return true end end
	return false
end
local function worldchanged(data)
	if typeof(data) ~= "table" or data.owner ~= debrisfolder or not running then return end -- only the current debris owner can report a phase into navigation
	local phases = {warning = 1, falling = 2, cleared = 3}
	if typeof(data.phase) ~= "string" or not phases[data.phase] then return end
	if typeof(data.id) ~= "string" or #data.id == 0 or #data.id > 128 or phases[data.phase] ~= data.revision then return end
	if typeof(data.position) ~= "Vector3" or typeof(data.parts) ~= "table" or #data.parts > 64 then return end
	if not (data.position.Magnitude < math.huge) then return end
	local cell = cellfromworld(data.position)
	local old = collapses[data.id]
	if not cell or (old and (data.revision <= old.revision or cell ~= old.cell)) then return end -- a wall keeps its cell and phase revisions must move forward
	for _, part in data.parts do
		if typeof(part) ~= "Instance" or not part:IsA("BasePart") or (part.Parent and not part:IsDescendantOf(debrisfolder)) then return end
	end
	if data.phase == "cleared" and (anysolid(if old then old.parts else {}) or anysolid(data.parts)) then return end -- a removed wall is not an opening while one of its solid pieces remains
	local record = {cell = cell, phase = data.phase, revision = data.revision, parts = table.clone(data.parts),
		id = data.id, position = data.position}
	local cells = footprint(record)
	if old then for oldcell in old.footprint do cells[oldcell] = true end end -- check the old footprint too or vacated cells could stay blocked forever
	record.footprint = if data.phase == "cleared" then {} else cells
	if data.phase == "cleared" then table.clear(record.parts) end
	collapses[data.id] = record
	setgate(cell, data.id, data.phase ~= "cleared")
	refresh(cells, "structural change", os.clock())
	attributes(agents, {lastcollapsephase = data.phase, lastcollapsecell = cell})
	local notices = {
		warning = {"the runner pauses nearby - watch the orange wall", "is becoming unstable", "collapse_warning"},
		falling = {"the wall collapsed - waiting for all debris to clear", "collapsed - watching the debris", "collapse"},
		cleared = {"debris is clear - agents can now compare routes through the opening", "debris cleared - checking the opening", "shared"},
	}
	local notice = notices[data.phase]
	if cell == democell then
		agents:SetAttribute("demo" .. data.phase .. "at", os.clock())
		message(data.phase, notice[1], os.clock())
	else
		knowledgeevent:FireAllClients({message = string.lower(data.id) .. " " .. notice[2], kind = notice[3], version = map.revision})
	end
end

local function announce(wall, phase: string, revision: number)
	wall.clearing = phase == "cleared" -- the event can be deferred so mark clearance pending before sending it
	worldevent:Fire({owner = debrisfolder, id = wall.id, position = wall.position,
		phase = phase, revision = revision, parts = table.clone(wall.parts)})
end

local function updatedebris(now: number)
	local cells = {}
	for _, record in collapses do
		if record.phase ~= "falling" then continue end
		local fresh = footprint(record)
		for cell in record.footprint do cells[cell] = true end -- query both old and new coverage as rubble moves across tile boundaries
		for cell in fresh do cells[cell] = true end
		record.footprint = fresh
	end
	refresh(cells, "structural change", now)
	for cell, obstruction in blockers do
		local part = obstruction.part
		local static = part:IsDescendantOf(maze) and part.CanCollide and part.Anchored and string.match(part.Name, "^Wall_")
		if now - obstruction.checked >= 1 and not static then refresh({[cell] = true}, "debris cleared", now) end -- stable authored walls need no polling but temporary blockers get checked again
	end
end

local timers, chunks, templates, selected, candidatecount = {}, {}, {}, {}, 0
local cycledeadline, replayat, collapseindex = 0, nil, 0
local function schedule(delay: number, callback: () -> ())
	push(timers, {score = os.clock() + delay, callback = callback, generation = generation}) -- generation tags keep old effect callbacks out of the next replay
end
local function selectwalls()
	local candidates = {}
	for _, wall in maze:GetChildren() do
		if not wall:IsA("BasePart") or not string.match(wall.Name, "^Wall_") or not wall.Anchored or not wall.CanCollide then continue end
		local point = floor.CFrame:PointToObjectSpace(wall.Position)
		if wall.Size.Y >= 8 and wall.Size.X >= 4 and wall.Size.Z >= 4 -- leave room at the boundary goal and player spawn when selecting extra walls
			and math.abs(point.X) <= floor.Size.X / 2 - 20 and math.abs(point.Z) <= floor.Size.Z / 2 - 20
			and planar(wall.Position, goal.Position) >= 32 and (not spawnlocation or planar(wall.Position, spawnlocation.Position) >= 28) then
			table.insert(candidates, wall)
		end
	end
	shuffle(candidates, random)
	selected, candidatecount = {demowall}, #candidates
	for _, spacing in {48, 24} do choose(candidates, selected, spacing, 8, 0) end
	for index, wall in selected do
		attributes(wall, {CollapsibleWall = true, CollapseOrder = index, CollapseState = "stable"})
		table.insert(templates, wall:Clone()) -- keep a clean wall template before warning or debris changes its appearance
	end
end

local function debris(wall, layer: {BasePart}, number: number)
	for _, chunk in layer do
		local offset = chunk.Position - wall.position
		local outward = Vector3.new(offset.X, 0, offset.Z)
		outward = if outward.Magnitude < 0.1 then wall.pose.RightVector else outward.Unit
		local tangent = Vector3.new(-outward.Z, 0, outward.X) * random:NextNumber(-0.3, 0.3)
		local downward = random:NextNumber(1, 4) + (3 - number) * 0.5
		chunk.Anchored = false
		own(chunk)
		chunk.AssemblyLinearVelocity = (outward + tangent).Unit * random:NextNumber(11, 18) + Vector3.new(0, -downward, 0) -- launch real physical chunks instead of tweening their fall
		chunk.AssemblyAngularVelocity = Vector3.new(random:NextNumber(-9, 9), random:NextNumber(-6, 6), random:NextNumber(-9, 9))
		chunk:SetAttribute("ReleasedTowardGround", true)
		chunks[chunk] = os.clock()
		schedule(5.5 + random:NextNumber(0, 1.2), function()
			if not chunk.Parent then return end
			collisions(chunk, false)
			tween(chunk, 0.65, {Transparency = 1}, Enum.EasingStyle.Quad)
			schedule(0.75, function() chunk:Destroy() end)
		end)
	end
	for index = 1, 6 do
		local width, height = random:NextNumber(0.18, 0.55), random:NextNumber(0.15, 0.5)
		local offset = Vector3.new(random:NextNumber(-wall.size.X * 0.48, wall.size.X * 0.48),
			random:NextNumber(-wall.size.Y * 0.25, wall.size.Y * 0.48), random:NextNumber(-wall.size.Z * 0.48, wall.size.Z * 0.48))
		local fragment = object("Part", debrisfolder, {
			Name = "falling_fragment", Size = Vector3.new(width, height, width), CFrame = wall.pose * CFrame.new(offset),
			Color = wall.color, Material = wall.material, CustomPhysicalProperties = PhysicalProperties.new(1.8, 0.65, 0.05, 100, 20),
		})
		collisions(fragment, index <= 3) -- only half the small fragments are solid to limit extra contact work
		own(fragment)
		table.insert(wall.parts, fragment)
		fragment.AssemblyLinearVelocity = Vector3.new(random:NextNumber(-10, 10), random:NextNumber(3, 12), random:NextNumber(-10, 10))
		fragment.AssemblyAngularVelocity = Vector3.new(random:NextNumber(-8, 8), random:NextNumber(-8, 8), random:NextNumber(-8, 8))
		debrisservice:AddItem(fragment, random:NextNumber(3.5, 5)) -- native expiry still removes fragments if the controller stops
	end
end
local function release(wall)
	if not wall.part.Parent then return announce(wall, "cleared", 3) end
	wall.part:SetAttribute("CollapseState", "falling")
	local layers = {{}, {}, {}}
	local size = Vector3.new(math.max(0.5, wall.size.X / 2 - 0.08), -- small gaps between chunks reduce overlap when the wall splits
		math.max(0.5, wall.size.Y / 3 - 0.08), math.max(0.5, wall.size.Z / 2 - 0.08))
	for index = 0, 11 do
		local x, y, z = math.floor(index % 4 / 2) + 1, math.floor(index / 4) + 1, index % 2 + 1
		local chunk = object(wall.part, debrisfolder, {
			Name = string.lower(wall.id) .. "_chunk", Size = size,
			CFrame = wall.pose * CFrame.new((x - 1.5) * wall.size.X / 2, (y - 2) * wall.size.Y / 3, (z - 1.5) * wall.size.Z / 2),
			CollisionGroup = "maze_collapse_debris", CanTouch = true,
			CustomPhysicalProperties = PhysicalProperties.new(2, 0.35, 0.1, 100, 25),
		})
		chunk:SetAttribute("CollapseDebris", true)
		table.insert(layers[y], chunk)
		table.insert(wall.parts, chunk)
	end
	wall.part.Transparency = 1
	collisions(wall.part, false)
	local function layer(number: number)
		debris(wall, layers[number], number)
		schedule(0.09, function()
			if number < 3 then return layer(number + 1) end -- release bottom layers first with a short gap before the next layer
			announce(wall, "falling", 2)
			wall.part:Destroy()
			attributes(debrisfolder, {LastCollapsedChunkCount = 12, CollapsedWalls = (debrisfolder:GetAttribute("CollapsedWalls") or 0) + 1})
		end)
	end
	layer(1)
end
local function warnwall(part: BasePart)
	local wall = {part = part, id = part.Name, position = part.Position, pose = part.CFrame,
		size = part.Size, color = part.Color, material = part.Material, parts = {}}
	part:SetAttribute("CollapseState", "warning")
	announce(wall, "warning", 1)
	local highlight = object("Highlight", debrisfolder, {
		Name = "collapse_warning", Adornee = part, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		FillColor = Color3.fromRGB(255, 132, 44), FillTransparency = 0.78,
		OutlineColor = Color3.fromRGB(255, 205, 82), OutlineTransparency = 0.08,
	})
	local marker = object(visual, debrisfolder, {
		Name = "collapse_warning", Size = Vector3.new(part.Size.X * 1.18, 0.08, part.Size.Z * 1.18),
		CFrame = CFrame.new(part.Position.X, floor.Position.Y + floor.Size.Y / 2 + 0.05, part.Position.Z),
		Shape = Enum.PartType.Block, Color = Color3.fromRGB(255, 151, 48), Transparency = 0.48,
	})
	local function pulse(stage: number) -- six bright and dim stages make three warning pulses before release
		local bright = stage % 2 == 1
		if stage == 7 or (bright and not part.Parent) then
			highlight:Destroy()
			marker:Destroy()
			return if part.Parent then release(wall) else announce(wall, "cleared", 3)
		end
		local duration = if bright then 0.22 else 0.26
		local direction = if bright then Enum.EasingDirection.Out else Enum.EasingDirection.In
		tween(highlight, duration, {FillTransparency = if bright then 0.38 else 0.82, OutlineTransparency = if bright then 0 else 0.32}, nil, direction)
		tween(marker, duration, {Transparency = if bright then 0.12 else 0.62}, nil, direction)
		schedule(duration, function() pulse(stage + 1) end)
	end
	pulse(1)
end

local function effects(now: number)
	while #timers > 0 and timers[1].score <= now do
		local timer = pop(timers)
		if running and timer.generation == generation then timer.callback() end -- a callback from an earlier replay must not change the current walls
	end
	for _, record in collapses do
		if record.phase == "falling" and not record.clearing and not anysolid(record.parts) then announce(record, "cleared", 3) end -- clearance waits for all solid pieces including the smaller fragments
	end
	for chunk, born in chunks do
		if not chunk.Parent or chunk.Anchored or now - born >= 4.5 then
			chunks[chunk] = nil
			continue
		end
		local pose, size = chunk.CFrame, chunk.Size
		local extent = (math.abs(pose.RightVector.Y) * size.X + math.abs(pose.UpVector.Y) * size.Y + math.abs(pose.LookVector.Y) * size.Z) / 2 -- use the rotated box extent since half the height alone misses tilted corners
		local top = floor.Position.Y + floor.Size.Y / 2
		if now - born < 0.05 or chunk.Position.Y - extent > top + 0.18 or chunk.AssemblyLinearVelocity.Y > 1.5 then continue end -- wait for a descending chunk near the floor before settling it
		local yaw = CFrame.Angles(0, math.rad(random:NextNumber(0, 360)), 0)
		local rotation = if size.X >= size.Z then CFrame.Angles(0, 0, math.rad(90)) else CFrame.Angles(math.rad(90), 0, 0)
		chunk.CFrame = CFrame.new(chunk.Position.X, top + math.max(size.X, size.Z) / 2 + 0.04, chunk.Position.Z) * yaw * rotation
		chunk.AssemblyLinearVelocity, chunk.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		chunk.Anchored = true
		attributes(chunk, {LandedOnMazeFloor = true, LandingY = chunk.Position.Y})
	end
end

local demo = {phase = "waiting", due = 0, deadline = 0}
local function pause()
	for _, state in states do
		if state.mode ~= "arrived" and state.mode ~= "stopped" then state:retire("stopped") end
	end
end

local function reset()
	pause()
	generation += 1 -- invalidate pending work before rebuilding walls and rig resources
	for _, list in {states, blockers, collapses, gates, map.cells, timers, chunks} do table.clear(list) end -- clear learned cells too so replay starts without knowledge from the previous run
	map.revision, started, replayat, collapseindex = 0, false, nil, 0
	if debrisfolder then debrisfolder:Destroy() end
	debrisfolder = object("Folder", script, {Name = "maze_collapse_debris"})
	selected = {}
	for _, template in templates do
		local old = maze:FindFirstChild(template.Name)
		if old then old:Destroy() end
		table.insert(selected, template:Clone())
		selected[#selected].Parent = maze
	end
	demowall = selected[1]
	setup()
	attributes(agents, {cyclecount = (agents:GetAttribute("cyclecount") or 0) + 1})
	attributes(debrisfolder, {CandidateCount = candidatecount, SelectedWallCount = #selected, CollapsedWalls = 0})
	demo = {phase = "waiting", due = 0, deadline = 0}
	message("waiting", "waiting for the viewer to finish loading", os.clock())
end

local function demonstration(now: number)
	if not started then return end
	if demo.phase == "sharing" and agents:GetAttribute("demoshared") then demo.phase, demo.due = "collapse", now + 3 end -- start the first collapse after an observed shared reroute rather than a timer alone
	if demo.phase == "first" and agents:GetAttribute("democomplete") then demo.phase, demo.due = "collapse", now + random:NextNumber(8, 13) end
	if demo.phase == "collapse" and now >= demo.due then
		collapseindex += 1
		local wall = selected[collapseindex]
		if wall and wall.Parent then warnwall(wall) end
		demo.phase = if collapseindex == 1 then "first" elseif collapseindex < #selected then "collapse" else "done"
		demo.due = now + 1.71 + (if collapseindex < #selected and collapseindex ~= 1 then random:NextNumber(8, 13) else 0)
		demo.deadline = if collapseindex == 1 then now + 91.71 else math.huge
	end
	if (demo.phase == "sharing" or demo.phase == "first") and now > demo.deadline then
		agents:SetAttribute("demophase", "incomplete")
		demo.phase = "done"
	end
	local finished = true
	for _, state in states do finished = finished and (state.mode == "arrived" or state.mode == "stopped") end
	if not replayat and (demo.phase == "done" or now >= cycledeadline) and (finished or now >= cycledeadline) then
		pause()
		replayat = now + 15
		agents:SetAttribute("demoreplayat", workspace:GetServerTimeNow() + 15) -- clients need shared server time while local deadlines use the monotonic clock
		message("replay", "run finished - restoring the maze for another demonstration in 15 seconds", now)
	end
	if replayat and now >= replayat then reset() end
end

script.Parent = maze -- world ancestry activates owned resources and engine destruction removes their tree
selectwalls()
reset()
table.insert(connections, knowledgeevent.OnServerEvent:Connect(function(player, action)
	if not running or action ~= "ready" or player.Parent ~= players then return end -- the client can announce readiness but cannot send routes or edit knowledge
	viewers[player] = true
	player:SetAttribute("mazeviewerready", true)
end))
table.insert(connections, players.PlayerRemoving:Connect(function(player) viewers[player] = nil end))
table.insert(connections, worldevent.Event:Connect(worldchanged))

local heartbeat = game:GetService("RunService").Heartbeat
while script.Parent == maze do
	local dt = heartbeat:Wait()
	if script.Parent ~= maze then break end -- the parent may change during the wait so check again before issuing any work
	local now = os.clock()
	effects(now) -- effect deadlines run every heartbeat even when navigation waits for its interval
	demonstration(now)
	elapsed += dt
	if elapsed < 0.16 then continue end
	elapsed = 0
	if not started and next(viewers) then
		started = true
		cycledeadline = now + 240
		demo.phase, demo.deadline = "sharing", now + 30
		for _, state in states do state.nextplan = now + state.model:GetAttribute("startdelay") end -- start delays begin at viewer readiness rather than script startup
		agents:SetAttribute("demostarted", true)
		message("starting", "starting in 5 seconds - watch the scout and the nearby runner", now)
	end
	updatedebris(now) -- refresh physical changes before checking completed search routes
	for _, state in states do state.eligible = started and update(state, now) end -- give every rig its movement and sensing pass before spending the search budget
	searches(now)
end
running = false
pause()
for _, connection in connections do connection:Disconnect() end
script:ClearAllChildren() -- live shutdown can publish stopped states while hard destruction leaves last snapshots
