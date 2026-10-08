-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
--!strict

-- mazerigs sets up the rigs and probes, this bit handles movement and shared knowledge
-- collapse controller handles walls and replay timing, we check where the agents can go
-- hud just shows messages and says a viewer is ready, it cant send routes or discoveries
-- mazerigs checks the maze for spawns, it doesnt give that wall map to the agents

-- missing cell means we dont know yet, false means we checked and its clear
type discovery = {blocked: boolean} -- a record keeps checked clear distinct from unknown while the boolean only describes collision knowledge
type grid = {width: number, height: number, revision: number, cells: {[number]: discovery}} -- dimensions bound ids and a revision tracks changed observations without preloading wall geometry
type entry = {cell: number, cost: number, score: number} -- keep paid cost beside estimated total so stale candidates and heap priorities can be checked separately

local function newgrid(width: number, height: number): grid -- keep grid size and learned cells together so pure searches need no Roblox instances
	assert(width > 0 and height > 0, "grid dimensions must be positive") -- a valid grid width is needed by modulo and row division so invalid dimensions fail before any search
	return {width = width, height = height, revision = 0, cells = {}} -- keep size revision and sparse observations in one value while an empty table deliberately means unknown
end -- valid dimensions keep sparse knowledge safe for later encoding and search

-- the table uses one id per tile, subtracting 1 makes the x/z calculation zero based
-- the remainder gives the column, whole rows give z
local function coordinates(map: grid, cell: number): (number, number) -- decode one based ids into zero based tile offsets used by both neighbors and world transforms
	return (cell - 1) % map.width, math.floor((cell - 1) / map.width) -- subtract the one based offset before remainder and division so column zero belongs to the first row
end -- both returned axes use the same one based grid convention

local function cellat(map: grid, x: number, z: number): number? -- one bounds check owns id creation so every neighbor uses the same valid grid limits
	if x < 0 or z < 0 or x >= map.width or z >= map.height then -- reject both axes before encoding so an edge step cannot wrap into a valid but unrelated row
		return nil -- no id means the caller must drop this step instead of guess a neighboring tile
	end -- encoding below is reachable only with bounded axes so an off row step cannot become another valid id
	-- check bounds first so stepping off a row wont wrap into the next one
	return z * map.width + x + 1 -- row width separates z from x and the final one restores the tables one based cell ids
end -- bounds ownership stays here before other helpers receive an encoded id

-- each move crosses one grid edge, so manhattan distance is a lower bound on the cost left
-- no diagonals here, they would cut through the corners of these walls
local function distance(map: grid, left: number, right: number): number -- the four way movement model needs a lower bound shared by search scores and shortcut checks
	local x, z = coordinates(map, left) -- decode the first id once so distance can compare axes independently of world transforms
	local otherx, otherz = coordinates(map, right) -- decode the second id using the same grid width so the lower bound compares like coordinates
	return math.abs(x - otherx) + math.abs(z - otherz) -- each legal move changes one axis and costs at least one so this sum cannot overestimate remaining travel
end -- this lower bound remains independent of physics observations and unknown penalties

-- try one step along each axis, cellat drops any step outside the maze
local function neighbors(map: grid, cell: number): {number} -- build only legal axis neighbors so every generated step matches the rigs grid movement
	local x, z = coordinates(map, cell) -- the same tile decoder is used for movement and observations so centers cannot disagree
	local result = {} -- a separate neighbor list lets callers traverse valid cells without sharing mutable scratch state
	for _, offset in {{1, 0}, {0, 1}, {-1, 0}, {0, -1}} do -- only axis steps match this maze because diagonals could cut through wall corners
		local nextcell = cellat(map, x + offset[1], z + offset[2]) -- the common encoder rejects off floor candidates so every returned neighbor is usable as a table key
		if nextcell then -- only encoded in bounds ids may enter the neighbors list used by sensing and A star
			table.insert(result, nextcell) -- append legal ids to a dense array so callers can traverse every valid neighbor in order
		end -- nil neighbors never become array holes so both sensing and search receive only usable grid ids
	end -- this local batch contains at most four legal axis steps and has not revealed any distant walls
	return result -- the caller receives its own valid neighbor array instead of share a scratch table with another scan
end -- only checked in bounds candidates reach the returned neighbor list

-- cheapest estimate stays at index 1, saves sorting everything each time
local function push(heap: {entry}, item: entry) -- own heap insertion separately so search expansion never sorts the entire frontier
	local index = #heap + 1 -- start with the new array slot as a gap so the item can move upward without sparse indices
	while index > 1 do -- only nonroot entries have parents and comparing above the root would access an invalid slot
		-- children sit at twice their parent index, rounding down walks back up one level
		local parent = math.floor(index / 2) -- halving the child slot walks one level toward the cheaper root in the binary heap
		if heap[parent].score <= item.score then -- the parent already satisfies heap order so lifting the item farther cannot improve the invariant
			break -- no further iteration can improve this decision because the gap repair keeps ancestor scores ordered before this item is visible to another pop
		end -- the candidate keeps moving only while its score would violate the current ancestor order
		-- shift the parent down, keep the new item until theres room for it
		heap[index] = heap[parent] -- fill the child gap with its parent while the candidate stays outside the array until it fits
		index = parent -- the vacated parent becomes the next gap so the upward comparison remains one heap level at a time
	end -- the upward repair stops at a valid parent or the root before the held item fills its final gap
	heap[index] = item -- fill the final gap only after the parent comparison proves this candidate belongs here
end -- the gap repair keeps ancestor scores ordered before this item is visible to another pop

-- after taking the root, slide the cheaper child upward until the last entry fits
local function pop(heap: {entry}): entry -- own root removal separately so A star always gets the lowest current estimated cost
	local first = heap[1] -- keep the cheapest entry safe while the final heap item repairs its vacated slot
	local last = table.remove(heap) :: entry -- reuse the final array entry as the spare item so root removal does not leave a sparse heap
	if #heap == 0 then -- a single entry needs no downward repair after removal of its last array slot
		return first -- return the original cheapest candidate and let the caller validate its saved cost
	end -- only a heap with remaining children reaches the downward repair below
	local index = 1 -- this slot tracks the moving gap in the heap instead of repeatedly swap entries
	while index * 2 <= #heap do -- a left child must exist before testing siblings so a leaf cannot read beyond the heap
		-- the left child is 2 * index, its right sibling is the next slot
		local child = index * 2 -- choose between sibling scores before lifting one so the smaller branch remains nearer the root
		-- lift the cheaper child so the other branch never ends up above a cheaper entry
		if child < #heap and heap[child + 1].score < heap[child].score then -- test right child existence first and choose the smaller sibling to preserve heap ordering
			child += 1 -- the right sibling replaces the left candidate only after its smaller score was established
		end -- the chosen child is the cheaper existing sibling so lifting it cannot hide a smaller score
		if heap[child].score >= last.score then -- the spare already belongs above both children so further lifting would disturb heap order
			break -- no further iteration can improve this decision because the spare fills only a slot whose cheaper child comparisons are satisfied
		end -- the gap moves lower only when the spare cannot yet sit above the selected child
		heap[index] = heap[child] -- lift the cheaper child into the gap while keeping the spare for a later valid slot
		index = child -- carry the gap downward along the selected branch instead of moving both siblings
	end -- the spare now fits above its children or reached a leaf and can safely close the gap
	-- both children now cost at least this much, so the spare entry can fill the gap
	heap[index] = last -- both child comparisons are satisfied so the spare can safely close the final gap
	return first -- return the original cheapest candidate and let the caller validate its saved cost
end -- the spare fills only a slot whose cheaper child comparisons are satisfied

local function discover(map: grid, cell: number, blocked: boolean): boolean -- keep observation updates together so repeated scans cannot keep invalidating peer plans
	assert(cell >= 1 and cell <= map.width * map.height, "discovery outside grid") -- observations are checked at their common entry so no caller can create knowledge beyond the grids ids
	local previous = map.cells[cell] -- keep the prior observation so equal scans and real reopenings can be distinguished before changing knowledge
	-- another agent checked this already, dont need to redo the routes
	if previous and previous.blocked == blocked then -- equal observations do not change routes so avoid consuming another shared revision
		return false -- unchanged occupancy denies invalidation work so every peer avoids the same redundant replan
	end -- only a changed observation reaches the revision increment that can invalidate peer plans
	map.revision += 1 -- advance only for a changed cell so route and display witnesses can compare meaningful observations
	map.cells[cell] = {blocked = blocked} -- a record distinguishes checked clear from a missing entry that A star must still treat as unknown
	return true -- the changed record permits publish to queue affected peers exactly once
end -- only changed occupancy crosses this boundary into shared invalidation work

-- parents lead back to the start, flip the chain so we walk it the right way
local function retrace(previous: {[number]: number}, start: number, goal: number): {number} -- follow parent links only after a successful search so movement gets the chosen route in forward order
	local reversed = {goal} -- the parent chain starts at the goal so this temporary list keeps the backward walk separate
	local cell = goal -- the current id ties this step to grid bounds instead of relying on instance names
	while cell ~= start do -- the successful parent chain must reach the original start before it can become a forward route
		cell = previous[cell] -- each link belongs to the best found cost and leads toward the start without resimulating the search
		table.insert(reversed, cell) -- preserve each parent in backward order before one final reversal gives movement its steps
	end -- the backward witness now includes the reached start and can be reversed without guessing another parent
	local route = table.create(#reversed) -- reserve the known path size instead of repeatedly grow storage while reversing it
	for index = #reversed, 1, -1 do -- walking the parent chain backward makes the reached start the first movement anchor
		table.insert(route, reversed[index]) -- copy into a new dense route so backward search state is not adopted by the mover
	end -- the completed array follows movement order instead of the reverse direction of parent links
	return route -- the mover receives an ordered path beginning at its anchor and ending at the searched goal
end -- parent links remain search evidence until their reversal is complete

-- costs is the distance already paid, score adds the estimate still left to the goal
local function findroute(map: grid, start: number, goal: number): ({number}, number) -- keep A star pure so map knowledge and costs can be checked independently from humanoid physics
	-- frontier holds candidates, costs remembers the best price found for each cell
	local frontier: {entry} = {} -- the heap stores candidate scores while costs owns the best known price for each cell
	local costs: {[number]: number} = {[start] = 0} -- an id keyed cost table allows improved routes to replace old prices without searching the heap
	-- previous remembers which cell led here, retrace follows these links back to the start
	local previous: {[number]: number} = {} -- parent links keep how the best route reached each cell without copying routes into heap entries
	push(frontier, {cell = start, cost = 0, score = distance(map, start, goal)}) -- the initial anchor costs nothing and its priority begins with the admissible goal distance alone
	while #frontier > 0 do -- remaining candidates mean the current knowledge still offers possible ways to the goal
		local current = pop(frontier) -- this candidate comes from the cheapest heap root and still needs its stale cost check
		-- better cost adds another heap entry, skip the old one if its cost is stale
		if current.cost ~= costs[current.cell] then -- an improved cost leaves older heap entries behind and only the current best one may expand neighbors
			continue -- skip this candidate while preserving the remaining work because candidate expansion keeps the best cost and parent invariant for the next cheapest pop
		end -- only the best saved candidate cost reaches expansion so old heap entries cannot restore outdated parents
		-- the goal is settled when popped, finding it as a neighbor could still leave a cheaper route waiting
		if current.cell == goal then -- the lowest nonstale goal entry settles the search instead of stopping at the first discovered goal neighbor
			return retrace(previous, start, goal), current.cost -- return the best parent witness with its accumulated price so adoption can compare actual alternatives
		end -- neighbor expansion below belongs only to candidates whose goal has not yet settled
		for _, cell in neighbors(map, current.cell) do -- reuse the grid encoder so search expansion obeys the same four way bounds as physical sensing
			local known = map.cells[cell] -- missing knowledge stays distinguishable from a checked clear cell so exploration remains possible
			if known and known.blocked then -- a checked wall is excluded while nil knowledge must remain searchable for exploration
				continue -- skip this candidate while preserving the remaining work because candidate expansion keeps the best cost and parent invariant for the next cheapest pop
			end -- only clear or unknown cells reach pricing and unknown remains available for exploration
			-- unknown doesnt mean blocked or nobody would leave spawn
			-- add a little cost here so checked paths win when the routes are close
			local cost = current.cost + (if known then 1 else 1.15) -- checked clear cells cost one and unknown cells get a small preference penalty instead of become impassable
			-- no cost saved yet, infinity lets the first route through
			if cost >= (costs[cell] or math.huge) then -- only a cheaper arrival can replace parent links and infinity permits the first arrival to an unseen cell
				continue -- skip this candidate while preserving the remaining work because candidate expansion keeps the best cost and parent invariant for the next cheapest pop
			end -- only a real cost improvement reaches the parent and frontier updates below
			costs[cell] = cost -- this best price becomes the stale entry check used when old heap candidates are eventually popped
			previous[cell] = current.cell -- keep the predecessor that achieved this best price so retrace does not follow an outdated candidate
			push(frontier, {cell = cell, cost = cost, score = cost + distance(map, cell, goal)}) -- keep paid cost separate from its lower bound estimate so heap priority still represents A star total cost
		end -- all legal local alternatives have been priced before the next heap priority decides expansion order
	end -- no unsettled candidate remains so failure below is explicit instead of a fabricated route
	-- cant reach the goal with what we know, wait and try again
	return {}, math.huge -- an empty route and infinite price explicitly represent failure so the caller can wait instead of command a bogus target
end -- candidate expansion keeps the best cost and parent invariant for the next cheapest pop

-- count only the part of the old route still ahead of this agent
-- first is where we already are, only entering the cells after it adds cost
local function routecost(map: grid, route: {number}, first: number): number -- price the unwalked route with the same costs as A star so route comparisons stay fair
	if #route == 0 then return math.huge end -- no route is not a free journey so it cannot be compared as zero remaining cost
	local cost = 0 -- one accumulated price lets route checks use the same unknown cell preference as the search
	for index = first + 1, #route do -- exclude the reached anchor and completed prefix so only future cell entries add travel cost
		local known = map.cells[route[index]] -- missing knowledge stays distinguishable from a checked clear cell so exploration remains possible
		if known and known.blocked then return math.huge end -- a wall on the remaining route invalidates its baseline so a physically impossible path is never kept
		cost += if known then 1 else 1.15 -- reuse the search weights so unknown cell preferences do not change between planning and comparisons
	end -- only the unwalked entries contributed to this price so the reached anchor was not charged again
	return cost -- return one consistent remaining price for the shortcut filter and final route adoption
end -- the remaining price uses the same cell weights as its search baseline

-- tiny margin so float rounding doesnt look like a better route
local function couldshorten(map: grid, anchor: number, opened: number, goal: number, cost: number): boolean -- use a cheap distance bound to reject useless openings before spending a search slot
	-- even a perfectly clear way through this opening can't help if this lower bound is too long
	return distance(map, anchor, opened) + distance(map, opened, goal) < cost - 0.0001 -- even the best axis distance through this opening must beat the old price beyond floating point noise
end -- this filter only rejects impossible savings and never substitutes for a real search

-- runtime adapter
-- above is just cell ids, below hooks it up to the actual maze
local runservice = game:GetService("RunService") -- the server heartbeat supplies the scheduler clock without one coroutine for every rig
local players = game:GetService("Players") -- the ready set must be tied to actual connected players and cleared when they leave
local httpservice = game:GetService("HttpService") -- json keeps the important message and sequence in one attribute instead of split replication updates
local replicatedstorage = game:GetService("ReplicatedStorage") -- presentation remotes live where clients can find them while route state stays private here
local serverstorage = game:GetService("ServerStorage") -- the wall event stays server only so clients cannot supply collapse authority
local rigs = require(script.Parent:WaitForChild("mazerigs")) -- require reuses the authored setup and drawing helper while navigation keeps its own decisions
local maze = workspace:WaitForChild("Maze") -- the authored maze is the physical source used by the adapter instead of a prefilled navigation map
local agents = workspace:WaitForChild("MazeAgents") -- this folder owns the rig lifecycle and shared presentation attributes for the current demo
local floor = maze:WaitForChild("MazeFloor") :: BasePart -- the floor size and frame define the coordinate system shared by navigation and overlap checks
local goal = maze:WaitForChild("GoalPad") :: BasePart -- the authored goal gives the adapter one destination while A star still chooses the route
local knowledgeevent = replicatedstorage:WaitForChild("maze_knowledge_event") :: RemoteEvent -- clients can receive display state and send only the ready acknowledgement
local worldevent = serverstorage:WaitForChild("maze_world_changed") :: BindableEvent -- wall events stay between server scripts instead of exposing physical authority to clients
-- start also registers the agent collision group before it is used by the overlap query
local initialrigs = rigs.start(maze, agents) -- setup supplies valid rigs and collisions before any body query uses their collision group

-- these walls are 8 stud tiles, keep the cell centers lined up with the authored maze
local cellsize = 8 -- eight stud spacing matches the authored walls so adjacent ids map to usable cell centers
-- lower this for more scans, just remember thats more queries too
local interval = 0.16 -- a common scan interval bounds repeated overlap work instead of assuming a fixed frame rate
-- leave some room for humanoid arrival tolerance, too tight and it can get stuck
local reach = 1.1 -- allow a little arrival tolerance because an exact center requirement can fight humanoid movement
-- this caps the whole move, even if the rig keeps inching forward
local movetimeout = 2.5 -- total movement time is bounded even while a rig makes tiny forward progress
-- this one measures time since useful progress, so a fully stuck rig is caught sooner
local recoverytime = 1.5 -- a separate useful progress deadline catches a fully stuck rig before the total deadline
local map = newgrid(math.round(floor.Size.X / cellsize), math.round(floor.Size.Z / cellsize)) -- floor dimensions become a shared empty grid and authored wall knowledge is not copied into it
-- half a tile moves the origin from the floor corner to the center of its first cell
local origin = Vector3.new(-floor.Size.X / 2 + cellsize / 2, floor.Size.Y / 2, -floor.Size.Z / 2 + cellsize / 2) -- half a tile and the floor top place the first center correctly inside the authored floor bounds
-- use the same collision rules as the rigs, otherwise a decorative marker could look like a wall
local overlap = OverlapParams.new() -- reuse one collision query configuration so all observers agree on which parts can block a rig
overlap.FilterType = Enum.RaycastFilterType.Exclude -- exclude mode removes the rigs folder from queries so peers do not become navigation walls
-- dont let rigs see each other as walls, collision group lets them pass too
overlap.FilterDescendantsInstances = {agents} -- exclude all agent descendants so bodies and their decorative probes cannot become peers walls
overlap.CollisionGroup = "MazeAgents" -- the query uses the same collision matrix as walking rigs so invisible nonblocking decorations stay ignored
overlap.RespectCanCollide = true -- use physical collidability instead of canquery alone so decorative markers do not block movement
-- one collidable part is enough to call the body space blocked
overlap.MaxParts = 1 -- one collision candidate proves this body box is obstructed so extra result allocation is unnecessary

-- anchor is the last reached center, target can still be halfway through a move
-- dirty asks for another search, mode says what the rig is doing until that search can run
-- cursor points into the route, openings keeps every cleared cell waiting for comparison
type agent = { -- group private rig movement state separately from the shared map so discoveries do not overwrite peer progress
	rig: rigs.rig, mode: string, anchor: number, target: number, route: {number}, cursor: number, -- rig references stay separate from mode and grid ids so reached centers cannot be confused with pending waypoints
	dirty: boolean, reason: string, started: number, progress: number, best: number, -- search causes and independent total versus progress timers keep replanning and stall recovery from masking each other
	nextplan: number, nextcommand: number, failures: number, sharedat: number, peerchanges: number, -- planning command refresh recovery bounds and peer evidence need independent clocks and counters
	peertrigger: number?, peersource: string, openings: {[number]: boolean}, shortcuts: number, demopath: boolean, demoentry: number?, demohold: boolean, -- pending peer and opening witnesses survive until comparison while demo flags remain separate from normal route validity
	alignment: AlignOrientation?, attachment: Attachment?, autorotate: boolean?, -- owned turning objects and prior humanoid rotation survive only until this rig retires
	startturn: (agent) -> (), stopturn: (agent) -> (), drive: (agent, Vector3?) -> (), retire: (agent, string) -> (), -- inherited lifecycle signatures describe the shared behavior every rig can call
} -- private movement and turning ownership stays separate from the shared learned map
-- keep the last blocker and scan time so moving debris can be checked again later
type obstruction = {part: BasePart, checked: number} -- the part reference and scan age jointly determine whether cached physical evidence needs another query
type collapse = {revision: number, phase: string, cell: number, parts: {BasePart}, footprint: {[number]: boolean}} -- phase order cell ownership fragment references and candidate footprints must travel together across updates
local collapses: {[string]: collapse} = {} -- id keyed records let later phases be compared with the same physical wall event
-- separate holds per collapse let overlapping debris keep a cell closed until both finish
local gates: {[number]: {[string]: boolean}} = {} -- separate collapse ids preserve overlapping holds until every owner clears its source cell
local generation: Instance? = nil -- folder identity distinguishes replay lifetimes even when replacement folders reuse the same name
local states: {agent} = {} -- one list owns per rig routes while every entry reads the same learned map
local blockers: {[number]: obstruction} = {} -- cache an observed part and its scan age so movable obstructions can be checked again later
local connections: {RBXScriptConnection} = {} -- store event handles under this controller so its lifetime has explicit disconnection ownership
local running = true -- this latch prevents late callbacks from repopulating state after teardown
local nextnotice = 0 -- presentation throttling has its own deadline so repeated discoveries still update the map
local noticerevision = 0 -- a sequence survives map resets so mounted clients can reject older demo snapshots
local started = false -- the countdown must latch once per cycle instead of restart when another viewer registers
local viewers: {[Player]: boolean} = {} -- player keys avoid duplicate readiness work and support cleanup when a viewer leaves
local resetowner: Instance? = nil -- one accepted reset per debris folder prevents duplicate events from teleporting rigs again

local democell = agents:GetAttribute("democell") -- the setup chooses the staged opening but navigation still discovers and searches through it normally
assert(typeof(democell) == "number", "demo cell was not set by the rig setup") -- setup must provide the staged id before event and route witnesses use it as a grid key

local function demomessage(phase: string, message: string, now: number) -- own important presentation snapshots separately from the map so late clients can read the current phase
	agents:SetAttribute("demophase", phase) -- other components can observe presentation phase without receiving mutable route state
	agents:SetAttribute("demomessage", message) -- late viewers need the last server message even after its original announcement passed
	-- give this demo message a moment before the normal notices take over
	nextnotice = now + 4 -- reserve presentation time for the important phase before routine discoveries can compete with it
	local kind = if phase == "warning" then "collapse_warning" elseif phase == "falling" then "collapse" elseif phase == "shortcut" or phase == "complete" then "recommended" else "shared" -- hud categories are derived from server phase evidence instead of client supplied navigation claims
	-- one replicated string keeps the message and its sequence together for late joiners
	noticerevision += 1 -- increase presentation sequence independently of learned map revisions so replay cannot make a new snapshot look older
	agents:SetAttribute("demosnapshot", httpservice:JSONEncode({message = message, kind = kind, serial = noticerevision})) -- one json attribute keeps message kind and serial together for late mounting clients
end -- presentation publishes validated server evidence without taking ownership of the map

-- keep the grid relative to the floor rather than duplicating world offsets in each caller
local function worldpoint(cell: number): Vector3 -- one floor relative transform owns cell centers so sensing and movement cannot drift apart
	local x, z = coordinates(map, cell) -- decode tile axes with the common grid rule before scaling and applying the floor frame
	-- local tile offsets pass through the floor transform so the map does not copy world offsets everywhere
	return floor.CFrame:PointToWorldSpace(origin + Vector3.new(x * cellsize, 0, z * cellsize)) -- scale tile axes before the floor transform so every world center stays relative to the authored maze
end -- the returned center is shared by movement and every physical query

local function cellfromworld(position: Vector3): number? -- invert the center transform at the adapter boundary so the planner keeps using numeric ids
	-- undo the floor transform first, then round the tile distances to the nearest center
	local point = floor.CFrame:PointToObjectSpace(position) - origin -- subtract the center origin after changing frames so grid math uses cell distances not world offsets
	return cellat(map, math.round(point.X / cellsize), math.round(point.Z / cellsize)) -- round local tile distances to the nearest center then reuse bounds checking before creating a grid key
end -- grid keys are created only after floor relative conversion and bounds checking

local goalcell = cellfromworld(goal.Position) -- the goal uses the same inverse transform as rigs so every search agrees on its destination id
assert(goalcell, "goal is outside the navigation grid") -- all searches need a valid destination id and an authored goal outside the floor must fail visibly

-- ignore the path behind us, a wall back there doesnt block our next move
local function remainingcontains(state: agent, cell: number): boolean -- test only future waypoints so new walls behind the rig cannot interrupt its current journey
	return table.find(state.route, cell, state.cursor) ~= nil -- starting at the cursor checks only pending steps so old walls behind the rig cannot trigger recovery
end -- past waypoints stay outside the current blockage decision

local function setmode(state: agent, mode: string) -- keep internal state and its visible attribute together so inspection follows the actual controller state
	state.mode = mode -- the private controller mode owns transitions while its attribute below only mirrors them for inspection
	state.rig.model:SetAttribute("PathState", mode) -- replicate the controller mode for inspection while the local state remains its decision source
end -- internal mode remains the owner while its visible attribute mirrors the transition

-- all movement commands go through here
-- sensing and shared discoveries ask for a new plan instead of steering over each other
local function stopturn(state: agent) -- release only this controllers turning objects and restore the setting it borrowed
	if state.alignment then state.alignment:Destroy() end -- repeated cleanup is safe even after root removal already destroyed the constraint
	if state.attachment then state.attachment:Destroy() end -- keep the authored rig attachments outside this owned cleanup
	if state.autorotate ~= nil and state.rig.humanoid.Parent then state.rig.humanoid.AutoRotate = state.autorotate end -- false is a valid saved setting so test nil rather than truthiness
	state.alignment, state.attachment, state.autorotate = nil, nil, nil -- cleared ownership cannot be reused by an old state after replay
end -- restored humanoid rotation has no competing constraint left behind

local function startturn(state: agent) -- acquire one rotation owner after spawn setup has produced the physical rig
	state:stopturn() -- repeated setup releases the earlier owned pair before replacing it
	local root = state.rig.root -- the root assembly owns turning and its collider is already welded by the rig helper
	local owned, problem = pcall(function() -- ownership failures must leave humanoid turning usable instead of abort controller startup
		local canown, reason = root:CanSetNetworkOwnership() -- anchored or ineligible assemblies cannot adopt controlled turning
		assert(canown, reason) -- fail before creating owned objects if this root cannot change its simulation owner
		root:SetNetworkOwner(nil) -- keep this navigation assembly under the server choosing its targets
		assert(root:GetNetworkOwner() == nil, "turning requires server network ownership") -- verify the actual owner before installing a second physics component
	end) -- ownership acquisition has no constraint or humanoid changes to leak on failure
	if not owned then warn("turning unavailable for " .. state.rig.model.Name .. " " .. tostring(problem)) return end -- a denied rig keeps its original humanoid facing and receives no partial constraint pair
	local attachment = Instance.new("Attachment") -- one local identity frame lets the solver apply the desired root orientation
	attachment.Name = "navturnattachment" -- a dedicated owned name makes duplicate pairs inspectable without touching authored attachments
	local alignment = Instance.new("AlignOrientation") -- torque changes facing while humanoid MoveTo remains responsible for translation
	alignment.Name = "navturnalignment" -- the owned constraint can be counted and inspected separately from the collider weld
	alignment.Mode = Enum.OrientationAlignmentMode.OneAttachment -- one attachment uses the supplied goal frame without a second moving physical target
	alignment.AlignType = Enum.AlignType.AllAxes -- this flat maze goal keeps the root upright while changing its horizontal heading
	alignment.Attachment0 = attachment -- tie torque to the rigs own attachment rather than another assembly
	alignment.CFrame = root.CFrame.Rotation -- begin from the current orientation before a real waypoint supplies another goal
	alignment.MaxTorque = math.clamp(root.AssemblyMass * 1800, 5000, 100000) -- scale the initial torque limit with mass but keep finite lower and upper bounds
	alignment.MaxAngularVelocity = math.rad(240) -- cap the initial turn rate instead of requesting an instantaneous direction change
	alignment.Responsiveness = 12 -- finite response lets the solver converge without forcing rigid snapping
	alignment.RigidityEnabled = false -- use the finite torque speed and response limits rather than the solvers maximum reaction
	alignment.ReactionTorqueEnabled = false -- only this root receives torque and no second assembly is counter rotated
	alignment.Enabled = false -- queued and observing rigs must not start turning before a valid movement target
	state.attachment, state.alignment, state.autorotate = attachment, alignment, state.rig.humanoid.AutoRotate -- retain exact object ownership and the original true or false setting for cleanup
	attachment.Parent = root -- publish the configured local frame only after the owned pair is complete
	alignment.Parent = root -- attach the disabled solver after all of its parameters and target references are ready
	state.rig.humanoid.AutoRotate = false -- the constraint becomes the sole active facing owner while humanoid walking continues
end -- creation adds no route choice and leaves translation with the existing movement path

local function drive(state: agent, target: Vector3?) -- one movement entry point prevents sensing and planning from issuing competing humanoid commands
	local alignment = state.alignment -- a rig denied ownership may still use its original humanoid facing
	if alignment then -- only an acquired owned pair participates in constraint turning
		if not alignment.Parent or not state.attachment or state.attachment.Parent ~= state.rig.root then state:stopturn() -- losing either owned object restores the borrowed humanoid setting
		else -- the valid pair can receive a goal without touching the root transform directly
			local delta = if target then target - state.rig.root.Position else Vector3.zero -- a stop has no facing direction and must disable the old goal
			local flat = Vector3.new(delta.X, 0, delta.Z) -- this authored flat maze turns horizontally while preserving humanoid translation
			alignment.Enabled = flat.Magnitude > 0.05 -- near zero targets cannot produce a meaningful unit direction or facing frame
			if alignment.Enabled then alignment.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit) end -- a guarded unit vector yields an upright orientation for the solver without teleporting the rig
		end -- only a complete active pair can own facing during this movement command
	end -- target nil disables the constraint and later retirement releases its objects
	state.rig.humanoid:MoveTo(target or state.rig.root.Position) -- a nil target cancels travel at the present position through the same humanoid command owner
end -- the single movement owner remains separate from sensing and route invalidation

local function publish(cell: number, blocked: boolean, source: string, now: number) -- commit shared knowledge before queuing routes or showing messages so presentation cannot become authority
	-- scan might catch a gap between falling bits, dont open it until the whole collapse clears
	blocked = blocked or gates[cell] ~= nil -- a gate holds the passage closed even when this body scan catches a gap between fragments
	local previous = map.cells[cell] -- keep the earlier observation so a newly learned clear cell is not mistaken for a reopened wall
	if not discover(map, cell, blocked) then -- discover compares the shared state first so repeated scans do not schedule the same work again
		return -- leave this path before later work can undo it because shared observations are committed before notifications and before later route comparisons
	end -- shared invalidation below belongs only to a new observation instead of repeated peer scans
	-- learning an unknown cell is clear is not the same as removing a wall from a known route
	local reopened = previous ~= nil and previous.blocked and not blocked -- only a known blocked cell becoming clear can offer a shortcut through an old obstruction
	if cell == democell and blocked and not previous then -- record the first scout once so later peer scans cannot replace who supplied this discovery
		agents:SetAttribute("demoscout", source) -- attributes let the collapse script and hud observe evidence without owning the navigation map
		agents:SetAttribute("demodiscoveredat", now) -- use the same local clock as movement so discovery timing stays comparable inside this server
	end -- only the first observation of the staged wall can own the scout witness
	local affected = 0 -- count peers needing a plan separately from the map revision used to track observations
	for _, state in states do -- each rig reads this one shared map but keeps its own route and movement state
		if state.mode == "arrived" or state.mode == "stopped" then -- finished rigs must not restart when another agent learns something
			continue -- skip this candidate while preserving the remaining work because shared observations are committed before notifications and before later route comparisons
		end -- terminal rigs are excluded from route work so another discovery cannot revive their completed journey
		-- the attribute exposes which shared update reached this rig while its route can still be from an older revision
		state.rig.model:SetAttribute("SharedMemoryVersion", map.revision) -- expose received knowledge independently of the route revision because peer observations can outpace searches
		local first = table.find(state.route, state.anchor) or 1 -- compare only from the last reached center so cells already walked do not inflate the remaining cost
		-- skip the search if even the shortest possible way through this opening cannot beat the old route
		-- the distance bound is a cheap filter and a useful candidate still needs a real search before adoption
		local useful = reopened and couldshorten(map, state.anchor, cell, goalcell :: number, routecost(map, state.route, first)) -- the distance bound rejects openings that cannot improve the remaining cost before a full search
		-- waiting rig has no route anyway, give the new opening a try
		-- these are the three ways a changed cell can matter to the remaining journey
		if not (useful or (reopened and state.mode == "waiting") or (blocked and remainingcontains(state, cell))) then -- only a promising opening a waiting rig or a future blocked waypoint can justify another search
			continue -- skip this candidate while preserving the remaining work because shared observations are committed before notifications and before later route comparisons
		end -- the state reaching invalidation has a future blockage useful opening or missing route to justify another search
		-- keep all pending openings, dont let a new event overwrite one we havent checked
		if reopened then state.openings[cell] = true end -- a set keeps overlapping openings until plan can compare them against the old route
		state.dirty = true -- queue the decision here so a discovery never steers a rig halfway between cell centers
		local external = source == "structural change" or source == "debris cleared" -- wall events have no scouting rig so keep them separate from peer communication evidence
		-- this reason travels with the queued search so the resulting route can explain what triggered it
		state.reason = if external then "structural change" elseif state.rig.model.Name == source then "local discovery" else "shared discovery" -- keep the physical local or peer source with the queued decision so the route witness explains its cause
		state.rig.model:SetAttribute("LastKnowledgeSource", source) -- keep the source beside the route evidence so a shared change can be traced back to its sender
		state.rig.model:SetAttribute("lastdiscoverycell", cell) -- cell ids join the observation and route records without sending world geometry to the client
		-- local scans and wall events still change plans, they just are not discoveries from a peer
		if state.rig.model.Name == source or external then continue end -- the earlier map update still applies but a rig cannot receive its own discovery as a peer message
		state.sharedat = now -- the drawing helper uses this age for its communication pulse instead of inventing a separate timer
		if blocked then -- a shared blockage needs a witness so the later route comparison can prove that obstacle was avoided
			state.peertrigger = cell -- hold the blocked cell until recordshared checks the old and new routes
			state.peersource = source -- keep the scout with its trigger even if other observations arrive before planning
		end -- a cleared event removes its own hold below and never erases another active wall owner
		affected += 1 -- this counts notified peers instead of successful reroutes which are only known after planning
	end -- shared observations are committed before notifications and before later route comparisons
	agents:SetAttribute("KnowledgeMessagesPublished", map.revision) -- this legacy attribute counts map revisions despite its name and is not a count of remote deliveries
	-- only the notification is throttled, the map and all affected agents were updated above
	-- presentation can wait because shared knowledge was already committed before this guard
	if affected == 0 or now < nextnotice or (democell and not agents:GetAttribute("democomplete")) then -- the map is already updated and only display work waits for an affected peer and an available notice window
		return -- leave this path before later work can undo it because shared observations are committed before notifications and before later route comparisons
	end -- the notification below has an affected peer and a display window but its map work already happened
	nextnotice = now + 2 -- reserve the notice window here so a second discovery in this update cannot flood the hud
	knowledgeevent:FireAllClients({ -- the server sends display evidence through a remote while the route tables stay server owned
		-- format from server owned observations rather than accepting client supplied claims
		message = string.format("%s found %s - %d agents are updating their routes", string.lower(source), if blocked then "a blockage" else "an opening", affected), -- format display text from server observations instead of use client supplied route claims
		kind = if blocked then "blocked" else "recommended", version = map.revision, -- the hud gets a display category and observation revision without needing the full shared map
	}) -- the display payload contains server evidence and leaves mutable navigation state with this controller
end -- shared observations are committed before notifications and before later route comparisons

local function readcell(cell: number): BasePart? -- one body query owns obstacle observations so sensing and physical clearance use identical collision rules
	-- lift the box a bit so the floor doesnt count as a wall
	local center = worldpoint(cell) + floor.CFrame.UpVector * 2.5 -- lift a floor relative center into the body region so the floor itself does not register as a wall
	-- check the space the body needs, a single center ray can miss debris beside it
	-- translation puts the query at this cell and floor rotation lines its axes up with the authored maze
	-- this checks part bounding boxes and suits our box walls but is not exact mesh collision testing
	local parts = workspace:GetPartBoundsInBox(CFrame.new(center) * floor.CFrame.Rotation, Vector3.new(2.6, 4, 2.6), overlap) -- the overlap query returns candidates using the shared collision rules instead of only a center ray
	return parts[1] -- one filtered candidate is enough to mark a box blocked and nil means the query found none
end -- collision filtering and body geometry stay common to sensing and clearance

-- only learn this cell and the four beside it, no peeking at the whole maze
local function sense(state: agent, now: number) -- grow partial map knowledge from a reached anchor instead of reveal the whole authored maze
	publish(state.anchor, false, state.rig.model.Name, now) -- reaching this center is evidence the rig fits here though an active collapse gate can still hold it closed
	for _, cell in neighbors(map, state.anchor) do -- four nearby body checks grow partial knowledge without scanning the whole authored maze
		local part = readcell(cell) -- readcell applies the rig collision rules to a body sized overlap instead of trusting a center ray
		blockers[cell] = if part then {part = part, checked = now} else nil -- save the obstruction and scan age for later debris rechecks and discard a cleared observation
		publish(cell, part ~= nil, state.rig.model.Name, now) -- publishing after the query lets every peer react to this real nearby observation
	end -- these local body queries have been published before another rig can use their new shared knowledge
end -- local queries grow one shared partial map without revealing authored maze geometry

local function beginmove(state: agent, target: number, mode: string, now: number) -- a new target owns fresh progress timers so repeated commands cannot disguise a stalled move
	state.target = target -- keep the command destination separate from the anchor until arrival is physically checked
	state.started = now -- each new move gets a total deadline while later command refreshes leave it intact
	-- progress has its own timer so repeated movement commands cannot hide a stuck rig
	state.progress = now -- use a separate useful progress timer so tiny drift and command refreshes cannot hide a stall
	-- first distance sample beats this, after that we need actual progress
	state.best = math.huge -- the first distance sample must set a baseline before later progress is measured
	state.nextcommand = now + 0.5 -- limit humanoid command refreshes while the faster scheduler still checks observations and deadlines
	setmode(state, mode) -- synchronize the move or recovery mode with its inspection attribute before the command is issued
	state.rig.model:SetAttribute("currentcell", state.anchor) -- the visible anchor must represent a reached center instead of a commanded destination
	state.rig.model:SetAttribute("targetcell", target) -- expose the destination separately so a target is never mistaken for arrival evidence
	state:drive(worldpoint(target)) -- the grid target passes through the common center transform before the sole movement owner commands it
end -- fresh timers belong to this target while later command refreshes leave them intact

local function retire(state: agent, mode: string) -- release movement and probe work together so finished or removed rigs cannot keep acting
	setmode(state, mode) -- synchronize the move or recovery mode with its inspection attribute before the command is issued
	if state.rig.root.Parent and state.rig.humanoid.Parent then -- only surviving rig components can accept the stop command during removal or teardown
		state:drive(nil) -- cancel travel through the common command entry instead of leave the old target active
	end -- retirement clears route and probes even when removed physical components cannot accept a stop command
	state.rig.model:SetAttribute("currentcell", state.anchor) -- the visible anchor must represent a reached center instead of a commanded destination
	state.route = {} -- a retired rig must not keep future waypoints that another observation could revive
	state.rig.model:SetAttribute("ScannerActive", false) -- finished rigs should no longer display scans that imply ongoing navigation work
	state.rig.model:SetAttribute("CommunicationState", "offline") -- offline presentation matches retired navigation instead of keeping the last communication pulse
	state:stopturn() -- arrival pause failure removal and controller teardown all release turning through retirement
	rigs.clear(state.rig) -- the drawing helper releases probes alongside navigation retirement so presentation matches the inactive state
end -- retired state has no live route movement or misleading probe presentation

local agentmethods = {startturn = startturn, stopturn = stopturn, drive = drive, retire = retire} -- store lifecycle functions once while each rig keeps its own routes timers and instances
local agentmetatable = {__index = agentmethods} -- missing method lookup uses this shared table and ordinary state writes stay on the individual rig

-- count a shortcut only when the new route uses a reopened cell the old route didn't use
local function recordopenings(state: agent, route: {number}, cost: number, oldstart: number, oldcost: number, now: number) -- compare real old and new routes before counting a shortcut so notices alone prove nothing
	local oldroute = state.route -- keep the currently adopted route available until opening and peer comparisons have finished
	for cell in state.openings do -- inspect every kept reopening so closely spaced events cannot overwrite possible shortcuts
		-- finding a first usable route is not a shortcut, there must be a finite old route to beat
		if oldcost == math.huge or cost >= oldcost - 0.0001 then break end -- a shortcut needs a valid cheaper comparison and this condition applies to the whole candidate route
		if not table.find(route, cell) or table.find(oldroute, cell, oldstart) then continue end -- the reopened cell must be new to the adopted remainder otherwise it did not create this improvement
		-- count it once even if theres a few new openings on the route
		state.shortcuts += 1 -- one adopted route improvement is counted even if the route uses several reopened cells
		state.rig.model:SetAttribute("shortcutchanges", state.shortcuts) -- keep a count of actual adopted improvements so one visual notice cannot stand in for a route change
		state.rig.model:SetAttribute("shortcutcell", cell) -- the opened cell links the improvement to the physical passage that enabled it
		state.rig.model:SetAttribute("shortcutbeforecost", oldcost) -- keep the valid old remainder so the improvement has an inspectable baseline
		state.rig.model:SetAttribute("shortcutaftercost", cost) -- the adopted cost uses the same model as the baseline so the comparison is meaningful
		break -- no further iteration can improve this decision because a shortcut witness is kept only after the adopted route beats a valid old remainder
	end -- the route receives at most one shortcut increment while the specific demo witness is checked separately
	-- needs fewer grid moves for the demo, just saving some unknown-cell cost doesnt count
	if not state.openings[democell] or oldcost == math.huge then return end -- the staged witness needs this particular reopening and a finite previous journey to improve
	if #route == 0 or #route >= #oldroute - oldstart + 1 then return end -- the demo counts saved grid moves instead of only a cheaper unknown cell penalty
	if not table.find(route, democell) or table.find(oldroute, democell, oldstart) then return end -- the opening must appear in the new route and be absent from the old remainder to explain the shortcut
	state.demopath = true -- remember that this rig adopted the demonstrated opening before the later physical crossing check
	if agents:GetAttribute("demoshortcut") then return end -- preserve the first witnessed improvement instead of overwrite it when another rig adopts one
	agents:SetAttribute("demoshortcut", true) -- latch the staged shortcut once so later agents cannot overwrite the first witness
	agents:SetAttribute("demoshortcutagent", state.rig.model.Name) -- the rigs name identifies whose planned route supplied the shortcut evidence
	agents:SetAttribute("demobeforesteps", #oldroute - oldstart) -- exclude the old prefix and anchor so this witness counts remaining grid moves
	-- route includes where we stand, that first cell isnt a move
	agents:SetAttribute("demoaftersteps", #route - 1) -- the new route includes its start so subtract one cell to count actual moves
	agents:SetAttribute("demoshortcutat", now) -- save comparison timing independently from the later physical crossing witness
	demomessage("shortcut", string.format("%s found a shorter route through the cleared wall: %d moves instead of %d", state.rig.model.Name, #route - 1, #oldroute - oldstart), now) -- the accepted navigation witness becomes the current presentation snapshot without authorizing any client movement
end -- a shortcut witness is kept only after the adopted route beats a valid old remainder

-- the blocked cell must disappear from a real planned route before this counts as a shared change
local function recordshared(state: agent, route: {number}, oldstart: number, now: number) -- tie a peer discovery to an actual route replacement so communication evidence has a route witness
	local oldroute = state.route -- keep the currently adopted route available until opening and peer comparisons have finished
	-- compare against the old route from our current anchor, not the part already walked
	local changed = #route ~= #oldroute - oldstart + 1 -- compare remaining cells instead of only costs so shared reroutes need a geometric route witness
	for index, cell in route do -- check the replacement cell sequence against the old remainder so equal prices do not hide a real reroute
		changed = changed or oldroute[oldstart + index - 1] ~= cell -- align both sequences at the reached anchor so completed prefixes cannot fabricate differences
	end -- the whole replacement remainder was compared so equal route lengths cannot hide different cells
	local trigger = state.peertrigger -- the pending peer blockage joins its source observation to the old and replacement routes
	if not changed or not trigger or #route == 0 then return end -- a shared change requires a new valid route and the pending peer blockage that explains it
	if not table.find(oldroute, trigger, oldstart) or table.find(route, trigger) then return end -- the peer wall must disappear from the old remainder before this counts as successful avoidance
	state.peerchanges += 1 -- count only a completed route comparison instead of increment on every communication pulse
	state.rig.model:SetAttribute("sharedroutechanges", state.peerchanges) -- communication evidence counts only a changed adopted route instead of every shared scan
	state.rig.model:SetAttribute("sharedchangeat", now) -- the timestamp joins this rig reaction to the earlier peer discovery
	state.rig.model:SetAttribute("sharedchangecell", trigger) -- keep the triggering wall id beside the route witness so avoidance can be checked
	state.rig.model:SetAttribute("sharedchangesource", state.peersource) -- the saved scout explains whose observation caused this receiver to change its route
	local separation = (state.rig.root.Position - worldpoint(trigger)).Magnitude -- actual rig distance is exposed alongside grid distance so the demo evidence can be inspected
	state.rig.model:SetAttribute("sharedchangedistance", separation) -- expose actual separation so reacting before reaching the wall is inspectable
	-- leave at least two grid steps to the blockage so the demo shows a reaction before reaching it
	if trigger ~= democell or distance(map, state.anchor, trigger) < 2 then return end -- the staged peer witness must be separated from the wall by at least two grid steps before it pauses for visibility
	if agents:GetAttribute("demoshared") then return end -- the first shared witness owns staging so later peer updates do not repeatedly pause the group
	-- pause here so people can see the demo, planner still picks the route after
	state.demohold = true -- pause movement for visibility while the planner still reads normal shared observations
	-- the runner can resume when debris clears, this deadline also releases it if clearance never arrives
	state.nextplan = now + 25 -- clearance may release the pause sooner but this timeout bounds a missing collapse event
	agents:SetAttribute("demoshared", true) -- latch the first visible peer reaction instead of restage every later observation
	agents:SetAttribute("demoreceiver", state.rig.model.Name) -- identify the affected rig separately from the scout that supplied the observation
	agents:SetAttribute("demosource", state.peersource) -- keep the scout in the shared presentation snapshot even after the runner moves away
	agents:SetAttribute("demoshareddistance", separation) -- the staged evidence includes separation instead of only asserting that a peer reacted
	agents:SetAttribute("demosharedat", now) -- the shared reaction timestamp can be compared with warning falling and clearance times
	demomessage("shared", state.peersource .. " found the wall - " .. state.rig.model.Name .. " changed route before reaching it", now) -- the accepted navigation witness becomes the current presentation snapshot without authorizing any client movement
end -- peer evidence stays tied to a real changed route instead of a communication animation

local function plan(state: agent, now: number) -- compare against the old route before adopting the new one so better knowledge does not cause pointless churn
	local oldroute = state.route -- keep the currently adopted route available until opening and peer comparisons have finished
	local oldstart = table.find(oldroute, state.anchor) or 1 -- locate the reached anchor so the completed route prefix cannot inflate remaining cost
	-- recovery moved us off the old route, cant compare against it now
	local oldcost = if oldroute[oldstart] == state.anchor then routecost(map, oldroute, oldstart) else math.huge -- a finite valid remainder is the baseline required to claim that an opening saved travel
	local route, cost = findroute(map, state.anchor, goalcell :: number) -- search from the physically reached anchor and keep both the candidate geometry and its cost for adoption
	-- worth checking the opening, doesnt mean the route is better though
	if next(state.openings) and oldcost < math.huge and cost >= oldcost - 0.0001 then -- a valid old remainder is kept when a newly checked opening fails to offer a real saving
		-- copy just the remaining cells, keeping the old table intact until the comparisons below finish
		route = table.move(oldroute, oldstart, #oldroute, 1, {}) -- copy only the valid remainder into a fresh route while the original stays available for evidence comparisons
		cost = oldcost -- the copied old geometry must keep its matching price instead of the rejected candidates price
	end -- opening checks may keep the valid old remainder and both evidence checks still see that baseline
	-- both checks need the old route and its trigger before we replace them below
	recordopenings(state, route, cost, oldstart, oldcost, now) -- check opening evidence while both old and candidate routes exist before any adoption overwrites the baseline
	table.clear(state.openings) -- the comparison consumed this batch so old openings cannot be credited to a later search
	recordshared(state, route, oldstart, now) -- check peer evidence while the old route and pending wall still exist before adoption
	state.peertrigger = nil -- consume the compared peer blockage so another search cannot claim the same cause again
	state.route = route -- adopt only after both evidence checks have finished reading the previous route
	-- the first entry is our anchor, moving starts at the next cell
	state.cursor = 2 -- the first route entry is the reached anchor and the second is the first unwalked cell
	state.dirty = false -- this search consumed current invalidation work and a later observation can mark it dirty again
	state.rig.model:SetAttribute("routerevision", map.revision) -- a planned route has its own knowledge revision because observations can outpace searches
	state.rig.model:SetAttribute("routecost", if cost == math.huge then -1 else cost) -- use a negative sentinel for no route so inspection does not receive an infinite number
	state.rig.model:SetAttribute("WaypointCount", #route) -- expose the chosen route size without making that count an input to the planner
	state.rig.model:SetAttribute("replanreason", state.reason) -- keep the search trigger visible so recovery and shared discoveries are not confused
	state.rig.model:SetAttribute("plannedroute", table.concat(route, ",")) -- a comma separated witness makes the adopted cell sequence inspectable without exposing mutable tables
	if #route == 0 then -- a failed search needs waiting and fresh sensing instead of a movement target
		setmode(state, "waiting") -- failed search enters a bounded retry state instead of keep an impossible movement target
		-- give the search a breather before trying the same blocked map again
		state.nextplan = now + 1 -- delay the retry to bound repeated searches while later sensing can refresh the blocked map
		return -- leave this path before later work can undo it because old evidence is consumed before the replacement becomes the rigs active route
	end -- only a usable search result reaches goal or movement handling below
	-- only the anchor in the route, we started at the goal already
	if #route == 1 then -- a route containing only the anchor means the rig is already at the requested goal
		state:retire("arrived") -- stop movement and probe work together once the actual goal center has been reached
		return -- leave this path before later work can undo it because old evidence is consumed before the replacement becomes the rigs active route
	end -- movement below requires a future waypoint because an anchor only route already retired as arrived
	if state.demohold then -- a valid route may be recorded during the demo pause without permission to walk it yet
		state.target = state.anchor -- keep the visible destination at the reached center during the presentation hold
		state:drive(nil) -- cancel travel through the common command entry instead of leave the old target active
		setmode(state, "observing") -- a demo hold may have a valid route but movement stays paused until clearance or its deadline
		return -- leave this path before later work can undo it because old evidence is consumed before the replacement becomes the rigs active route
	end -- only an unheld valid route may command its first future cell below
	beginmove(state, route[2], "moving", now) -- start only the first future center through the normal movement timers and command owner
end -- old evidence is consumed before the replacement becomes the rigs active route

local function recover(state: agent, now: number) -- return toward the reached anchor before replanning so a mid tile shove cannot cause corner cutting
	state.failures += 1 -- keep recovery attempts bounded so the same impossible physical move cannot retry forever
	state.dirty = true -- recovery needs a fresh search once a valid center is reached instead of trust the stalled remainder
	-- head back to the last reached center, don't cut across a corner from half a tile away
	beginmove(state, state.anchor, "recovering", now) -- align the staged spawn to its reached cell before allowing a first search
end -- the safe anchor remains the movement goal until a reached center allows a fresh search

-- touching the opening and turning back isn't a crossing, remember which side the rig entered from
local function recordcrossing(state: agent, now: number) -- require entry and exit through the opened cell so touching a passage is not counted as using it
	local crossed = state.anchor == democell and state.target ~= democell and state.demoentry ~= nil and state.target ~= state.demoentry -- the saved entry side and reached exit distinguish a complete traversal from turning back
	if not crossed or not state.demopath or agents:GetAttribute("democomplete") then return end -- completion needs a distinct reached exit and the adopted demo opening route and may be recorded only once
	agents:SetAttribute("democomplete", true) -- completion latches only after a valid passage traversal instead of a route suggestion
	agents:SetAttribute("demotraversedby", state.rig.model.Name) -- identify the physical runner separately from whichever scout supplied knowledge
	agents:SetAttribute("demotraversedat", now) -- record reached exit timing so the demo distinguishes planning from actual traversal
	agents:SetAttribute("demoexitcell", state.target) -- a reached exit different from the entrance is the evidence that the opening was crossed
	agents:SetAttribute("demoentrycell", state.demoentry) -- keep the original entrance for checking that the runner did not simply turn back
	demomessage("complete", state.rig.model.Name .. " walked through the new passage - shared discovery and shortcut demonstrated", now) -- the accepted navigation witness becomes the current presentation snapshot without authorizing any client movement
end -- completion needs both the chosen opening route and a reached distinct exit

local function reachcell(state: agent, now: number) -- commit arrival before learning neighbors so sensing is anchored to a center the rig really reached
	-- check the entry and exit before replacing anchor, otherwise we lose the side we came from
	recordcrossing(state, now) -- test entry and exit before replacing the old anchor so the crossing still knows its origin side
	if state.target == democell and state.anchor ~= democell then state.demoentry = state.anchor end -- save the reached entry side once the opening is entered so turning back can be rejected later
	state.anchor = state.target -- only physical arrival advances the anchor that future sensing and planning are allowed to use
	state.failures = 0 -- a reached center is successful progress and ends the current chain of stalled attempts
	state:drive(nil) -- cancel travel through the common command entry instead of leave the old target active
	setmode(state, "planning") -- arrival offers a safe center for replanning before another waypoint can be commanded
	sense(state, now) -- new neighbors are learned from the reached center before deciding whether the remainder is still valid
	if state.anchor == goalcell then -- arrival at the destination takes priority over sending another queued waypoint
		state:retire("arrived") -- stop movement and probe work together once the actual goal center has been reached
		return -- leave this path before later work can undo it because new knowledge and the next step use the physically reached anchor
	end -- another waypoint can be issued only when physical arrival has not completed the journey
	if not state.dirty and state.cursor < #state.route then -- reuse only a still valid route with another future cell instead of spend a search at every center
		state.cursor += 1 -- arrival consumed the current waypoint so the cursor may advance to the next unwalked entry
		beginmove(state, state.route[state.cursor], "moving", now) -- reuse the chosen remainder through the same command and timeout setup as a freshly planned step
	end -- the old remainder advances only while valid and otherwise the scheduler gets a safe reached planning center
end -- new knowledge and the next step use the physically reached anchor

local function maintainmove(state: agent, now: number) -- combine progress and total deadlines so both complete stalls and slow drifting get bounded recovery
	local rig = state.rig -- the rig holds physical and drawing references while state owns the navigation decisions
	-- an overall deadline catches slow drifting as well as a rig making no progress at all
	local stalled = now - state.progress > recoverytime or now - state.started > movetimeout -- either no useful progress or excessive total time is enough to begin bounded recovery
	if state.mode == "moving" and stalled then -- ordinary travel failure must first publish an actual obstruction before attempting a return to its anchor
		local part = readcell(state.target) -- a stall alone is not wall evidence and the target body box must be checked first
		if part then -- only a collision candidate justifies sharing a blocked target with the rest of the group
			blockers[state.target] = {part = part, checked = now} -- keep the observed obstruction and query time for later clearance checks
			publish(state.target, true, rig.model.Name, now) -- share the observed target wall before this rigs recovery so peers can avoid it early
		end -- a movement stall is shared as a wall only with an actual body query witness
		state.reason = "movement recovery" -- record the actual trigger for the upcoming search instead of blame an unrelated peer update
		recover(state, now) -- bounded anchor recovery owns movement cancellation and marks the remainder for reconsideration
		return -- leave this path before later work can undo it because only active travel owns command refreshes and recovery stays bounded
	end -- the normal travel stall path already returned before recovery mode or command refresh handling
	if state.mode == "recovering" and now - state.started > movetimeout then -- a failed anchor return needs a safe alternative or retirement instead of endless MoveTo refreshes
		-- a shove can move the agent into another cell, only accept it if the body fits there
		local cell = cellfromworld(rig.root.Position) -- the current id ties this step to grid bounds instead of relying on instance names
		if not cell or readcell(cell) or state.failures >= 4 then -- an alternate anchor must be inside the grid physically clear and within the recovery attempt limit
			state:retire("stopped") -- a dead removed or unrecoverable rig releases movement and presentation instead of keeping live work
			return -- leave this path before later work can undo it because only active travel owns command refreshes and recovery stays bounded
		end -- an alternate recovery target exists only after grid clearance and attempt bounds passed
		state.anchor = cell -- accept an alternate center only after its bounds and body clearance checks passed
		beginmove(state, cell, "recovering", now) -- reach the new anchor through normal movement timing before planning from it
		state.failures += 1 -- keep recovery attempts bounded so the same impossible physical move cannot retry forever
		return -- leave this path before later work can undo it because only active travel owns command refreshes and recovery stays bounded
	end -- the bounded recovery branch cannot fall through into an extra stale command for the previous anchor
	if state.mode ~= "moving" and state.mode ~= "recovering" then return end -- inactive modes must not refresh an old command that would undo a pause or retirement
	if now < state.nextcommand then return end -- command cadence is independent of useful progress checks so refreshes cannot reset stall deadlines
	-- send the move again, dont restart the stuck timers
	state.nextcommand = now + 0.5 -- limit humanoid command refreshes while the faster scheduler still checks observations and deadlines
	state:drive(worldpoint(state.target)) -- refresh the same floor relative target without restarting the total or useful progress deadlines
end -- only active travel owns command refreshes and recovery stays bounded

-- keep arrival/progress checks separate from the lifecycle states and the timeout recovery
local function advance(state: agent, now: number): boolean -- separate physical progress from lifecycle decisions so update can share search slots safely
	local blocked = map.cells[state.target] -- check the shared target observation before issuing more movement into a newly known obstruction
	if state.mode == "moving" and blocked and blocked.blocked then -- shared knowledge can reveal a wall before local movement reaches it and must stop that approach
		recover(state, now) -- bounded anchor recovery owns movement cancellation and marks the remainder for reconsideration
		return false -- this path cannot offer normal planning work until its invalid or terminal movement state is handled
	end -- arrival measurement below is reached only when shared knowledge permits the active approach
	local delta = state.rig.root.Position - worldpoint(state.target) -- measure the rig against the same world center that movement was commanded to reach
	-- root height sits above the floor, only x/z tells us how close it is to this flat maze cell
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude -- root height differs from the floor center so this flat maze measures arrival along x and z
	if horizontal <= reach then -- humanoid tolerance counts arrival before timeout logic can misclassify a successfully reached center
		reachcell(state, now) -- one arrival handler commits the anchor learns neighbors and records any real passage crossing
		return state.mode ~= "arrived" -- a terminal arrival must stop this update before the scheduler tries to plan another route
	end -- timeout handling belongs only to rigs outside arrival tolerance so successful movement is not mistaken for a stall
	-- little physics nudges dont count, rig needs to actually get closer
	if horizontal < state.best - 0.15 then -- only a useful distance reduction refreshes progress so physics jitter cannot postpone recovery forever
		state.best = horizontal -- keep the closest measured approach as the reference for deciding whether progress is useful
		state.progress = now -- use a separate useful progress timer so tiny drift and command refreshes cannot hide a stall
	end -- only useful approach progress resets its timer while total movement time remains bounded
	maintainmove(state, now) -- arrival did not occur so command refresh and bounded stall recovery still need to run
	return true -- arrival is not terminal so the lifecycle update may continue checking this rigs state
end -- useful physical progress remains separate from search eligibility

-- true just means it can use a search slot, doesnt mean it arrived
local function update(state: agent, now: number): boolean -- offer planning work only after lifecycle and movement checks so budget limits never freeze recovery
	local rig = state.rig -- state owns the navigation decision while this rig holds the humanoid and drawing assets
	if state.mode == "arrived" or state.mode == "stopped" then -- terminal states cannot ask the shared scheduler for another search
		return false -- this path cannot offer normal planning work until its invalid or terminal movement state is handled
	end -- terminal rigs are excluded from route work so another discovery cannot revive their completed journey
	-- a removed or dead rig must release its route and probes rather than leave live movement work behind
	if not rig.model:IsDescendantOf(agents) or rig.humanoid.Health <= 0 or not rig.root.Parent then -- a removed dead or incomplete rig must retire instead of keep a command or search eligibility
		state:retire("stopped") -- a dead removed or unrecoverable rig releases movement and presentation instead of keeping live work
		return false -- this path cannot offer normal planning work until its invalid or terminal movement state is handled
	end -- only a surviving active rig reaches the mode specific movement and search decisions
	if state.mode == "observing" then -- the demo hold can update its plan but must not issue a new walking target yet
		-- give the viewer time to follow the collapse, while new discoveries still update this runner's plan
		if agents:GetAttribute("democlearedat") or now >= state.nextplan then -- clearance normally releases the hold and the deadline prevents an endless pause if its event is missed
			state.demohold = false -- release only the presentation hold while normal gates still decide whether the passage is usable
			state.dirty = true -- compare current shared knowledge before movement resumes after the pause
			setmode(state, "planning") -- planning makes this rig eligible for the next shared search slot
			agents:SetAttribute("demoresumedat", now) -- store observable timing so the demo can distinguish a queued resume from an actual crossing
		end -- the hold ends only on accepted clearance or its deadline while normal navigation gates still apply
		rigs.draw(rig, worldpoint(state.target), now - state.sharedat) -- drawing consumes the current target and message age but never supplies a route back to this controller
		return state.dirty -- an observing rig may spend a search slot and plan still respects its active hold
	end -- the observing path returns before ordinary walking so planning a held route cannot resume movement early

	if state.mode == "queued" then -- start delays must expire before a rig can take its first grid aligned movement step
		if now < state.nextplan then return false end -- each start delay uses the readiness based deadline set by the heartbeat owner
		-- line the queued rig up with its cell center before planning its first grid step
		beginmove(state, state.anchor, "recovering", now) -- align the staged spawn to its reached cell before allowing a first search
	end -- the initial delay has expired and its center alignment now uses normal recovery handling
	local travelling = state.mode == "moving" or state.mode == "recovering" -- both ordinary movement and the trip back to an anchor need arrival and stall checks
	if travelling and not advance(state, now) then return false end -- finish movement checks first so the planner uses a reached center instead of a halfway position
	if state.mode == "waiting" and now >= state.nextplan then -- a failed search gets periodic nearby sensing since a passage might change without a useful peer route
		sense(state, now) -- refresh observations before retrying so the new search does not blindly repeat stale knowledge
		setmode(state, "planning") -- planning makes this rig eligible for the next shared search slot
	end -- only an expired failed search retry performs fresh sensing and reenters planning
	if state.mode ~= "arrived" and state.mode ~= "stopped" then -- only active rigs need probe updates since retire already cleared finished ones
		rigs.draw(rig, worldpoint(state.target), now - state.sharedat) -- drawing consumes the current target and message age but never supplies a route back to this controller
	end -- inactive rigs no longer need probe drawing because retirement already cleared their presentation
	rig.model:SetAttribute("currentcell", state.anchor) -- expose the reached anchor separately from the command destination for inspection
	rig.model:SetAttribute("targetcell", state.target) -- the target can be ahead of the anchor and is not evidence that the humanoid arrived
	return state.mode == "planning" -- this boolean offers a search slot and movement updates have already run regardless of the budget
end -- every lifecycle and movement check runs before the shared scheduler spends a search slot

-- re-query the body space before publishing, a cleared chunk can still have another wall behind it
local function refresh(cells: {[number]: boolean}, now: number) -- requery physical occupants before publishing so a removed fragment does not hide another obstruction
	for cell in cells do -- a set deduplicates overlapping footprints so each candidate body box is refreshed once per pass
		local part = readcell(cell) -- physical clearance must use the current occupant not assume a vanished reference means an empty cell
		blockers[cell] = if part then {part = part, checked = now} else nil -- keep the current collision evidence and scan age or discard the cache when the body query is clear
		publish(cell, part ~= nil, "structural change", now) -- the actual body query decides occupancy and this server source does not invent a scouting peer
	end -- each deduplicated candidate has been queried before its structural occupancy is shared
end -- the candidate set becomes occupancy only through actual body queries

local function collidable(part: BasePart): boolean -- surviving references are not enough and only parts still in the world with collisions matter
	return part:IsDescendantOf(workspace) and part.CanCollide -- a saved reference only matters while its part still exists in the live physical world with collisions
end -- only live colliding references can deny clearance in this run

local function footprint(record: collapse): {[number]: boolean} -- project rotated fragment bounds into grid space to find body queries worth refreshing
	local cells = {[record.cell] = true} -- always include the original wall cell because its collapse gate owns clearance there
	for _, part in record.parts do -- each surviving fragment can overlap multiple cells so the footprint must union their candidates
		if not collidable(part) then continue end -- removed or noncolliding fragments no longer justify refreshing blocked navigation cells
		local pose = floor.CFrame:ToObjectSpace(part.CFrame) -- project the fragment in floor space so its rotated footprint uses the same axes as grid coordinates
		local size = part.Size * 0.5 -- half extents describe both sides of the fragment center before projecting its rotated box
		local right, up, look = pose.RightVector, pose.UpVector, pose.LookVector -- these basis vectors tell us how each local size axis contributes to the grid axes
		-- rotated debris can overlap more than its center cell, include the body's half width too
		-- each basis component projects one half-size onto this axis, abs keeps both sides positive
		-- 1.3 is half the body query, these are cells worth checking, the body query still decides what's blocked
		local xradius = math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z + 1.3 -- absolute axis projections plus body half width give conservative x query candidates
		local zradius = math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z + 1.3 -- the matching z projection includes body width so fragments beside a center are still rechecked
		local point = pose.Position - origin -- subtract the center origin after changing frames so grid math uses cell distances not world offsets
		-- round inward to the cell centers whose body boxes might overlap this part, then clamp to the grid
		local minx = math.max(0, math.ceil((point.X - xradius) / cellsize)) -- ceil selects the first center inside the expanded bound and clamping rejects cells beyond the floor
		local maxx = math.min(map.width - 1, math.floor((point.X + xradius) / cellsize)) -- floor selects the last center inside the expanded bound without indexing past the grid width
		local minz = math.max(0, math.ceil((point.Z - zradius) / cellsize)) -- the lower z center uses the same inclusive rule so the rotated box is checked consistently
		local maxz = math.min(map.height - 1, math.floor((point.Z + zradius) / cellsize)) -- the upper z center is limited to the authored grid height instead of assume debris stays inside it
		for z = minz, maxz do -- walk the bounded z rows touched by projected debris instead of scan the whole maze
			for x = minx, maxx do -- check each x center within those projected rows so rotated fragments can affect several tiles
				cells[z * map.width + x + 1] = true -- encode candidate centers using the same row stride and one based id rule as the grid
			end -- each center inside the bounded row joins the candidate set and still needs its physical query
		end -- only projected rows were queried so a moving fragment does not trigger a full maze scan
	end -- all surviving fragment projections are unioned before refresh decides which body spaces are blocked
	return cells -- return a conservative candidate set and let refresh perform the actual collision decisions
end -- projected candidates remain a query region instead of a claim of exact collision geometry

local function updategeneration(now: number) -- replace stale collapse ownership before querying so delayed events cannot affect a new maze run
	local current = workspace:FindFirstChild("maze_collapse_debris") -- the folder instance identifies this physical lifetime and its reused name alone cannot establish ownership
	if generation == current then return end -- unchanged folder identity means existing revisions still belong to this physical run
	local affected: {[number]: boolean} = {} -- a set keeps every newly occupied and vacated cell available for one physical refresh pass
	for _, record in collapses do -- each old record owns footprint cells that may need requerying when its physical folder is replaced
		for cell in record.footprint do affected[cell] = true end -- keep vacated candidates before clearing old records so removed fragments do not leave stale walls
	end -- old and current fragment regions from every relevant wall contribute before one refresh pass
	generation = current -- future event checks now compare against this exact folder instance instead of its reused name
	table.clear(collapses) -- old phase revisions belong to the prior physical generation and cannot govern a replacement wall
	table.clear(gates) -- old collapse holds must leave with their owners or they would keep restored cells closed forever
	-- old debris belongs to the old folder, its delayed messages can't reopen the new maze
	refresh(affected, now) -- refresh occupied and vacated candidates so the map follows current physical occupants
end -- old folder history cannot govern the replacement physical run

local function setgate(cell: number, id: string, blocked: boolean) -- hold each source cell by collapse id so overlapping collapses cannot clear each others passage
	if blocked then -- a warning or falling phase adds its own hold instead of overwrite another collapse owner
		gates[cell] = gates[cell] or {} -- reuse a cell hold collection so overlapping collapses remain independently represented
		gates[cell][id] = true -- this wall owns one hold and only its clearance may release it
		return -- leave this path before later work can undo it because one cleared owner cannot release another active collapse hold
	end -- a cleared event removes its own hold below and never erases another active wall owner
	local gate = gates[cell] -- fetch this cells collection so removing one collapse hold cannot remove its other owners
	if not gate then return end -- a missing hold collection is already clear and does not need to be recreated for removal
	gate[id] = nil -- release only the named wall so another active collapse still prevents passage use
	-- publish checks if the entry exists, empty table needs to go too
	if not next(gate) then gates[cell] = nil end -- publish tests entry existence so an empty collection must be removed after the final owner clears
end -- one cleared owner cannot release another active collapse hold

local phases = {warning = 1, falling = 2, cleared = 3} -- phase names have explicit ordering so stale or mismatched event revisions cannot reopen a passage
local function worldchanged(payload: unknown) -- validate phase and generation contracts before physical events can alter shared navigation knowledge
	if not running or typeof(payload) ~= "table" then return end -- closed controller lifetime and invalid server data cannot create new navigation records
	-- this is a server bindable, still validate the fields before using them as cell or table keys
	local data = payload :: any -- the broad cast is kept at this validated server boundary before any fields become grid keys
	local current = workspace:FindFirstChild("maze_collapse_debris") -- the folder instance identifies this physical lifetime and its reused name alone cannot establish ownership
	-- check the actual folder, same name doesnt mean its the same run
	if not current or data.owner ~= current then return end -- only the current folder instance can announce phases even if an old folder used the same name
	if typeof(data.id) ~= "string" or #data.id > 80 then return end -- a bounded wall id is required before indexing the collapse history table
	if typeof(data.phase) ~= "string" or not phases[data.phase] then return end -- only recognized phase names may select revision order and presentation text
	-- the phase name and number must agree before we compare this event with the previous one
	if phases[data.phase] ~= data.revision then return end -- a phase name and revision number must represent the same contract before history comparison
	if typeof(data.position) ~= "Vector3" or typeof(data.parts) ~= "table" or #data.parts > 64 then return end -- bounded fragment lists and a vector position keep invalid events out of grid and physical queries
	local position = data.position :: Vector3 -- the vector cast follows its runtime type check and finite coordinates are still checked next
	-- nan is unequal to itself, reject it and infinity before turning coordinates into table keys
	if position.X ~= position.X or position.Z ~= position.Z or math.abs(position.X) == math.huge or math.abs(position.Z) == math.huge then return end -- nan and infinity cannot become finite grid ids so reject them before coordinate rounding or indexing
	local cell = cellfromworld(position) -- the current id ties this step to grid bounds instead of relying on instance names
	if not cell then return end -- events outside the authored floor cannot claim ownership of a navigation tile
	local now = os.clock() -- one local timestamp keeps this decision consistent with movement notice and event timing in the same server
	updategeneration(now) -- replace old ownership before comparing phase revisions for a wall id reused by replay
	local previous = collapses[data.id] -- the last accepted phase for this wall is the baseline that rejects repeats and out of order events
	-- warning, falling, cleared must advance for the same cell, late or repeated phases do nothing
	if previous and (data.revision <= previous.revision or cell ~= previous.cell) then return end -- one wall id must advance phases at the same cell instead of accept duplicates or a displaced event
	local parts: {BasePart} = {} -- the overlap query returns candidates using the shared collision rules instead of only a center ray
	for _, part in data.parts do -- validate every fragment before any list becomes authoritative clearance evidence
		if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return end -- only physical parts support the pose and collidability checks required by footprint handling
		if part.Parent and not part:IsDescendantOf(current) then return end -- a live fragment must belong to this generation while removed fragments may remain as harmless references
		table.insert(parts, part) -- copy validated references so later payload mutation cannot alter this accepted snapshot list
	end -- only a completely validated snapshot list reaches clearance or record adoption
	if data.phase == "cleared" then -- clearance has a stronger contract because a false opening could command a rig into surviving debris
		-- check the earlier snapshot too, an empty payload must not hide a piece still blocking the path
		for _, part in if previous then previous.parts else parts do -- the earlier snapshot must still be checked so an empty new payload cannot hide a blocking fragment
			if collidable(part) then return end -- a remaining live collision part denies clearance even if its source wall was destroyed
		end -- the earlier accepted fragments cannot be hidden by an empty incoming clear list
		-- the new snapshot may contain a piece that was absent from the earlier one
		for _, part in parts do -- newly supplied fragments also need clearance checks because the previous snapshot may not include them
			if collidable(part) then return end -- a remaining live collision part denies clearance even if its source wall was destroyed
		end -- every incoming fragment also passed clearance because old history may not have included it
	end -- record adoption below cannot advertise clearance while either snapshot contains a live collidable fragment
	local record: collapse = {revision = data.revision, phase = data.phase, cell = cell, parts = parts, footprint = {[cell] = true}} -- keep phase revision owner cell and physical footprint together for the next comparison
	collapses[data.id] = record -- adopt the validated revision before publishing affected cells so subsequent events see the accepted phase
	setgate(cell, data.id, data.phase ~= "cleared") -- warning and falling keep the source hold while validated clearance releases only this wall
	local cells = footprint(record) -- a set unions query candidates so overlapping fragments do not duplicate refresh work
	-- include the old footprint too, those cells may need to be marked clear after a piece moved
	if previous then -- old footprint candidates are still needed because a fragment can vacate a tile without being destroyed
		for oldcell in previous.footprint do cells[oldcell] = true end -- union the vacated region with the current footprint before querying actual body clearance
	end -- vacated candidates remain in the union so a shifted fragment cannot leave stale occupancy behind
	refresh(cells, now) -- physical queries decide the resulting shared occupancy after phase validation and gate updates
	record.footprint = if data.phase == "cleared" then {} else cells -- cleared records keep revision history but no longer need repeated fragment region updates
	-- keep revision for late events, let go of the cleared fragments though
	if data.phase == "cleared" then table.clear(record.parts) end -- release fragment references after clearance while preserving revision history against late phases
	agents:SetAttribute("lastcollapsephase", data.phase) -- expose the accepted server phase while rejected events cannot update the display
	agents:SetAttribute("lastcollapsecell", cell) -- join the accepted phase to the affected grid cell for inspection
	if cell == democell then -- the staged wall uses persistent presentation evidence while ordinary walls use transient notices
		agents:SetAttribute("demo" .. data.phase .. "at", now) -- phase timestamps let the runner hold and viewing sequence observe validated server progression
		local messages = {warning = "the runner pauses nearby - watch the orange wall", falling = "the wall collapsed - waiting for all debris to clear", cleared = "debris is clear - agents can now compare routes through the opening"} -- server phase names select display text while the navigation decision has already been validated
		demomessage(data.phase, messages[data.phase], now) -- publish the accepted phase as a snapshot so clients mounting later still receive its current meaning
		return -- leave this path before later work can undo it because only validated current generation phases can publish structural knowledge
	end -- the staged wall already used its persistent snapshot and only ordinary phases reach the transient notice below
	local messages = {warning = "is becoming unstable", falling = "collapsed - watching the debris", cleared = "debris cleared - checking the opening"} -- server phase names select display text while the navigation decision has already been validated
	knowledgeevent:FireAllClients({message = string.lower(data.id) .. " " .. messages[data.phase], kind = if data.phase == "warning" then "collapse_warning" elseif data.phase == "falling" then "collapse" else "shared", version = map.revision}) -- send accepted server evidence as display data while route and physical authority remain on the server
end -- only validated current generation phases can publish structural knowledge

local function updatedebris(now: number) -- union occupied and vacated cells so moving fragments can block new cells and free old ones
	updategeneration(now) -- replace old ownership before comparing phase revisions for a wall id reused by replay
	local affected: {[number]: boolean} = {} -- a set keeps every newly occupied and vacated cell available for one physical refresh pass
	for _, record in collapses do -- each old record owns footprint cells that may need requerying when its physical folder is replaced
		if record.phase ~= "falling" then continue end -- only moving fragments need repeated footprint queries and stable cleared history remains untouched
		local cells = footprint(record) -- a set unions query candidates so overlapping fragments do not duplicate refresh work
		for cell in record.footprint do affected[cell] = true end -- keep vacated candidates before clearing old records so removed fragments do not leave stale walls
		for cell in cells do affected[cell] = true end -- newly occupied candidates join the vacated set so movement can both block and free cells
		record.footprint = cells -- keep the current region as the old footprint for the next debris movement comparison
	end -- old and current fragment regions from every relevant wall contribute before one refresh pass
	-- both the new and the vacated cells matter when a fragment rolls away
	refresh(affected, now) -- refresh occupied and vacated candidates so the map follows current physical occupants
end -- the union includes both cells entered and cells vacated by moving fragments

-- stop accepting updates before dropping the shared map and rig references
local function stop() -- disconnect event owners before clearing state so teardown cannot be followed by new navigation work
	if not running then -- teardown is idempotent because several ownership callbacks may notice removal of the same controller
		return -- leave this path before later work can undo it because closed ownership prevents later callbacks from reviving cleared navigation state
	end -- only the first teardown caller performs disconnection and releases shared references
	running = false -- close the controller before disconnecting or clearing so late callbacks cannot restore work
	for _, connection in connections do -- event handles are owned by this controller and must not survive its teardown
		connection:Disconnect() -- release the callback before dropping its state references so the scheduler and remotes stop producing work
	end -- all owned producers are disconnected before state is retired or cleared
	for _, state in states do -- each private movement state must obey the shared lifecycle boundary instead of keep an independent command
		state:retire("stopped") -- a dead removed or unrecoverable rig releases movement and presentation instead of keeping live work
	end -- closed ownership prevents later callbacks from reviving cleared navigation state
	table.clear(states) -- old per rig routes must not survive teardown or be reused in another navigation lifetime
	table.clear(blockers) -- cached obstruction references no longer belong to active scans and can be released
	table.clear(collapses) -- old phase revisions belong to the prior physical generation and cannot govern a replacement wall
	table.clear(gates) -- old collapse holds must leave with their owners or they would keep restored cells closed forever
	table.clear(connections) -- clear disconnected handles so controller state no longer keeps callback owners
	table.clear(map.cells) -- learned occupancy belongs to this run and must not leak into a replay or removed controller
	table.clear(viewers) -- a stopped controller no longer owns readiness acknowledgements or connected player references
end -- closed ownership prevents later callbacks from reviving cleared navigation state

local function seed(riglist: {rigs.rig}) -- create separate per rig state over one shared map so spawn setup does not become a planned route
	for _, rig in riglist do -- each authored rig receives fresh private movement state over the same common observation map
		local cell = cellfromworld(rig.root.Position) -- the current id ties this step to grid bounds instead of relying on instance names
		assert(cell, "agent is outside the navigation grid") -- spawn setup must place every rig in a valid tile before its route and target ids are created
		local state = setmetatable({ -- attach shared behavior to fresh per rig fields rather than copy methods or share mutable routes
			rig = rig, mode = "planning", anchor = cell, target = cell, route = {}, cursor = 1, -- a new rig starts at its valid cell with no assumed route and physical references kept outside map knowledge
			dirty = true, reason = "initial plan", started = 0, progress = 0, best = math.huge, -- fresh state requires a first search and cannot inherit movement progress or a previous run cause
			nextplan = 0, nextcommand = 0, failures = 0, sharedat = -math.huge, peerchanges = 0, -- ready work begins without old deadlines while an infinitely old pulse means no peer message has been seen yet
			peertrigger = nil, peersource = "", openings = {}, shortcuts = 0, demopath = false, demoentry = nil, demohold = false, -- each replay must begin without pending blockage or crossing witnesses from its previous physical generation
		}, agentmetatable) :: agent -- this constructor has all private fields and __index supplies the declared lifecycle methods
		table.insert(states, state) -- the shared scheduler owns this state entry so search work can be limited across all rigs
		state:startturn() -- acquire facing before the first recovery command but after lifecycle ownership enters the states list
		rig.model:SetAttribute("currentcell", cell) -- the visible anchor must represent a reached center instead of a commanded destination
		rig.model:SetAttribute("targetcell", cell) -- expose the destination separately so a target is never mistaken for arrival evidence
		rig.model:SetAttribute("sharedroutechanges", 0) -- communication evidence counts only a changed adopted route instead of every shared scan
		rig.model:SetAttribute("shortcutchanges", 0) -- keep a count of actual adopted improvements so one visual notice cannot stand in for a route change
		local delay = rig.model:GetAttribute("startdelay") -- the authored delay stages the viewer sequence without supplying any route to the planner
		if typeof(delay) == "number" and delay > 0 then -- only a valid positive authored delay stages a queued start instead of feed invalid deadlines
			state.nextplan = os.clock() + delay -- initialize the staged deadline before the readiness heartbeat rebases queued rigs on client loading
			setmode(state, "queued") -- queued state prevents movement and search until the authored delay is released by the scheduler
		else -- an unstaged rig first aligns with its valid center instead of inheriting a viewing delay
			beginmove(state, cell, "recovering", os.clock()) -- an unstaged rig first reaches its grid center so later searches use a physically reached anchor
		end -- both start branches use a valid grid center and neither injects an authored waypoint route
	end -- each accepted spawn has private route state while learned walls remain in the one shared map

end -- fresh per rig state cannot carry evidence from a previous replay

-- the server owns replay, a ready message can only register its sending player once
table.insert(connections, knowledgeevent.OnServerEvent:Connect(function(player, action) -- store the remote callback under the controller lifetime so only readiness has a client input path
	if not running or action ~= "ready" or player.Parent ~= players or viewers[player] then return end -- only a connected sending player can register once and no client action can change routes or reset the maze
	viewers[player] = true -- a player keyed set bounds readiness work to one entry per actual viewer
	-- the hud retries until it sees this acknowledgement, only the first ready message registers the player
	player:SetAttribute("mazeviewerready", true) -- the server acknowledgement ends hud retries after this actual sending player has registered once
end)) -- the sender is registered once and only the server owns navigation decisions
table.insert(connections, players.PlayerRemoving:Connect(function(player) viewers[player] = nil end)) -- remove departing viewer keys under the same lifetime so disconnected players cannot keep the start condition alive

local function pause() -- retire remaining movers before wall restoration so new solid walls never appear around active commands
	for _, state in states do -- each private movement state must obey the shared lifecycle boundary instead of keep an independent command
		if state.mode ~= "arrived" and state.mode ~= "stopped" then state:retire("stopped") end -- preserve completed arrival evidence while stopping only the movers before wall restoration
	end -- wall restoration can proceed only after active movement has been retired
end -- wall restoration can proceed only after active movement has been retired

local function reset() -- replace navigation knowledge and rig state together so replays cannot reuse stale discoveries
	pause() -- cancel remaining movement before replacing routes and restoring solid maze walls
	table.clear(states) -- old per rig routes must not survive teardown or be reused in another navigation lifetime
	table.clear(blockers) -- cached obstruction references no longer belong to active scans and can be released
	table.clear(collapses) -- old phase revisions belong to the prior physical generation and cannot govern a replacement wall
	table.clear(gates) -- old collapse holds must leave with their owners or they would keep restored cells closed forever
	table.clear(map.cells) -- learned occupancy belongs to this run and must not leak into a replay or removed controller
	-- each run learns the maze again, but keep ready viewers and the message serial across replays
	map.revision = 0 -- navigation knowledge is fresh per replay while the presentation sequence stays independent
	generation = nil -- the replacement folder must establish new ownership before collapse records can be accepted
	started = false -- the next cycle needs its own readiness based countdown instead of reuse previous movement timing
	seed(rigs.start(maze, agents)) -- reset authored rigs and private movement state together after the shared map has been cleared
	agents:SetAttribute("cyclecount", (agents:GetAttribute("cyclecount") or 0) + 1) -- count resets outside cleared demo attributes so replays remain observable
	demomessage("waiting", "waiting for a viewer before the next demonstration", os.clock()) -- the accepted navigation witness becomes the current presentation snapshot without authorizing any client movement
end -- shared knowledge and rig centers now belong to the same fresh replay

agents:SetAttribute("cyclecount", 1) -- count resets outside cleared demo attributes so replays remain observable
seed(initialrigs) -- the initial setup supplies rigs only and does not preload their searched routes
demomessage("waiting", "waiting for the viewer to finish loading", os.clock()) -- the accepted navigation witness becomes the current presentation snapshot without authorizing any client movement
local elapsed = 0 -- accumulated heartbeat time sets a scan cadence without replaying missed updates after a slow frame
table.insert(connections, worldevent.Event:Connect(function(payload) -- the stored server callback dispatches phases and replay actions while teardown can disconnect both together
	if typeof(payload) ~= "table" or not running then return end -- the server event boundary must reject invalid data and closed lifetimes before any reset action
	if payload.action ~= "reset" and payload.action ~= "pause" then worldchanged(payload) return end -- physical phase events go through validation while replay actions use their separate ownership contract
	-- only the current server debris folder can control a cycle, never a client message
	if not payload.owner or payload.owner ~= workspace:FindFirstChild("maze_collapse_debris") then return end -- only the current physical generation can pause or reset this navigation cycle
	if payload.action == "pause" then pause() return end -- stop movers before wall restoration without clearing their recorded terminal arrival evidence
	-- one new debris folder means one reset, duplicate events must not restart agents again
	if resetowner == payload.owner then return end -- one replacement folder permits one reset so duplicate server events cannot restart the cycle again
	resetowner = payload.owner -- remember the accepted generation before resetting so repeated delivery is already rejected
	reset() -- replay replaces knowledge and rig movement state only after the owner and duplicate checks passed
end)) -- phase validation and replay actions keep separate ownership checks
-- the module watches the owner because a destroyed script cannot reliably run its own deferred cleanup
rigs.watch(script, stop) -- the helper owns removal watching because a destroyed script cannot reliably finish its own deferred cleanup
table.insert(connections, runservice.Heartbeat:Connect(function(dt) -- one stored heartbeat owns the shared cadence instead of independent unbounded rig update loops
	elapsed += dt -- heartbeat supplies elapsed frame time so the scan cadence does not assume a fixed frame rate
	if not running or elapsed < interval then -- teardown disables all work and the interval avoids repeating body queries on every frame
		return -- leave this path before later work can undo it because movement observation and the limited search budget share one server update timestamp
	end -- movement observation and the limited search budget share one server update timestamp
	-- slow frame, just do one update instead of piling up searches
	elapsed = 0 -- drop missed intervals instead of running several expensive updates after a slow frame
	local now = os.clock() -- one timestamp keeps movement deadlines and notice throttles consistent throughout this update
	if not started then -- viewer readiness gates the first countdown but it does not take ownership of agent decisions
		-- the delay begins after a real HUD is listening, not while its client is still loading
		if not next(viewers) then return end -- no registered viewer means keep queued agents still so loading does not skip the example
		started = true -- latch the start before announcing it so another heartbeat cannot reset every delay
		-- each rig delay is relative to readiness rather than time spent loading the client
		for _, state in states do state.nextplan = now + (state.rig.model:GetAttribute("startdelay") or 5) end -- rebase authored delays on viewer readiness so time spent loading cannot skip the demonstration
		agents:SetAttribute("demostarted", true) -- the collapse controller watches this flag so its schedule begins with navigation
		-- the snapshot keeps this starting phase available to a client mounting after the announcement
		demomessage("starting", "starting in 5 seconds - watch the scout and the nearby runner", now) -- the accepted navigation witness becomes the current presentation snapshot without authorizing any client movement
	end -- the readiness countdown is latched before regular debris movement and search work begins
	-- the collapse script owns the replay deadline and the phase guard announces it only once
	if agents:GetAttribute("demoreplayat") and agents:GetAttribute("demophase") ~= "replay" then -- the wall controller owns replay timing and this phase guard prevents repeated announcements
		-- update the shared presentation snapshot while the server controller handles restoration
		demomessage("replay", "run finished - restoring the maze for another demonstration in 15 seconds", now) -- the accepted navigation witness becomes the current presentation snapshot without authorizing any client movement
	end -- the replay message is recorded once while the wall controller keeps restoration ownership
	-- share one search budget across the group, discoveries still arrive even when planning has to wait
	local budget = 2 -- cap searches started this update but a single search is still synchronous and not time limited
	updatedebris(now) -- refresh physical changes before agents decide whether their next cell is still usable
	-- falling bit can leave the cell while its still around
	for cell, obstruction in blockers do -- this cache covers observed blockers that can leave a cell without a collapse event
		local part = obstruction.part -- the saved instance distinguishes authored fixed walls from movable or removed blockers
		-- skip only fixed authored walls since their collapse phase explicitly tells navigation when they change
		local staticwall = part:IsDescendantOf(maze) and part.CanCollide and part.Anchored and string.match(part.Name, "^Wall_") -- only fixed authored walls can skip cache polling because their collapse phases explicitly announce physical changes
		if now - obstruction.checked < 1 or staticwall then -- throttle cached obstruction queries while falling debris also gets its own footprint refresh
			continue -- skip this candidate while preserving the remaining work because movement observation and the limited search budget share one server update timestamp
		end -- movement observation and the limited search budget share one server update timestamp
		local part = readcell(cell) -- ask what occupies the cell now since the original part moving away does not prove the space is clear
		blockers[cell] = if part then {part = part, checked = now} else nil -- replace the old blocker with the current occupant and reset only this scan age
		publish(cell, part ~= nil, "debris cleared", now) -- the structural source prevents a physics recheck from being counted as a scouting peer message
	end -- movement observation and the limited search budget share one server update timestamp
	for _, state in states do -- the group shares search slots while every rig still receives its movement and recovery checks
		-- still update with no search slots left, movement and recovery cant wait for the planner
		if update(state, now) and budget > 0 then -- update runs first even with an exhausted budget so movement deadlines still get checked
			budget -= 1 -- spend a slot before plan so one rig cannot reuse it when its search finds no route
			plan(state, now) -- only states allowed by update search from their reached anchor using the latest shared observations
		end -- movement observation and the limited search budget share one server update timestamp
	end -- movement observation and the limited search budget share one server update timestamp
end)) -- movement observation and the limited search budget share one server update timestamp
