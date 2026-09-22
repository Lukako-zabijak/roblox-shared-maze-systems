--!strict

-- Made by LukakoZabijak (lukakozabijak) on Discord, killerox3905 on Roblox.
-- 4d616465206279204c756b616b6f5a6162696a616b20286c756b616b6f7a6162696a616b29206f6e20446973636f72642c206b696c6c65726f7833393035206f6e20526f626c6f782e
export type rig = {model: Model, humanoid: Humanoid, root: BasePart, markers: {{BasePart}}, raycastparams: RaycastParams}
local physicsservice = game:GetService("PhysicsService")
local agentcollisiongroup = "MazeAgents"
local navigationdecorcollisiongroup = "MazeNavigationDecor"
local minimumspawnspacing = 32
local farsideagentcount = 4
local cruisespeed = 13
local scanangles = {-72, -48, -24, 0, 24, 48, 72}
local probedotcount = 6
local wrongcolor = Color3.fromRGB(255, 62, 72)
local module = {}
local owners: {[Instance]: () -> ()} = {}

-- this connection belongs to the module's require context, not a controller calling start
-- a destroyed script can't run its own deferred cleanup, so check its owner from here
game:GetService("RunService").Heartbeat:Connect(function()
    for owner, cleanup in owners do
        if not owner:IsDescendantOf(game) then
            owners[owner] = nil
            cleanup()
        end
    end
end)

-- keep the authored rigs and spawn spacing, this module owns their collider and probe setup
function module.start(maze: Instance, agentsfolder: Instance): {rig}
	local mazefloor = maze:WaitForChild("MazeFloor") :: BasePart
	local goal = maze:WaitForChild("GoalPad") :: BasePart
	local function configurecollisiongroup()
		pcall(function()
			physicsservice:RegisterCollisionGroup(agentcollisiongroup)
		end)
		pcall(function()
			physicsservice:RegisterCollisionGroup(navigationdecorcollisiongroup)
		end)
		physicsservice:CollisionGroupSetCollidable(agentcollisiongroup, agentcollisiongroup, false)
		physicsservice:CollisionGroupSetCollidable(agentcollisiongroup, navigationdecorcollisiongroup, false)
	end

	local function configurenavigationdecor()
		local floortop = mazefloor.Position.Y + mazefloor.Size.Y * 0.5
		local halffloor = mazefloor.Size * 0.5
		for _, descendant in maze:GetDescendants() do
			if descendant:IsA("BasePart") and descendant ~= mazefloor and not descendant:IsDescendantOf(agentsfolder) then
				local localposition = mazefloor.CFrame:PointToObjectSpace(descendant.Position)
				local bottom = descendant.Position.Y - descendant.Size.Y * 0.5
				local top = descendant.Position.Y + descendant.Size.Y * 0.5
				local isinsidemaze = math.abs(localposition.X) <= halffloor.X and math.abs(localposition.Z) <= halffloor.Z
				local isthinoverlay = descendant.Size.Y <= 2 and descendant.Size.X <= 16 and descendant.Size.Z <= 16
				local isonfloor = bottom <= floortop + 0.2 and top <= floortop + 2.1
				if isinsidemaze and isthinoverlay and isonfloor then
					descendant.CollisionGroup = navigationdecorcollisiongroup
					descendant:SetAttribute("MazeNavigationDecor", true)
				end
			end
		end
	end
-- watermark:1/8:4d616465206279204c75

	local function gridkey(xindex: number, zindex: number): string
		return string.format("%d:%d", xindex, zindex)
	end

	local function collectreachablespawnpoints(): {Vector3}
		local walls = {}
		local cellsize = nil
		local minx = math.huge
		local maxx = -math.huge
		local minz = math.huge
		local maxz = -math.huge

		for _, child in maze:GetChildren() do
			if child:IsA("BasePart") and string.find(child.Name, "Wall_", 1, true) == 1 then
				table.insert(walls, child)
				cellsize = cellsize or math.max(child.Size.X, child.Size.Z)
				minx = math.min(minx, child.Position.X)
				maxx = math.max(maxx, child.Position.X)
				minz = math.min(minz, child.Position.Z)
				maxz = math.max(maxz, child.Position.Z)
			end
		end

		if not cellsize or #walls == 0 then
			return {}
		end

		local xcount = math.round((maxx - minx) / cellsize)
		local zcount = math.round((maxz - minz) / cellsize)
		local blocked = {}
		for _, wall in walls do
			local xindex = math.round((wall.Position.X - minx) / cellsize)
			local zindex = math.round((wall.Position.Z - minz) / cellsize)
			blocked[gridkey(xindex, zindex)] = true
		end

		local goalx = math.round((goal.Position.X - minx) / cellsize)
		local goalz = math.round((goal.Position.Z - minz) / cellsize)
		local queue = {{goalx, goalz}}
		local reachable = {[gridkey(goalx, goalz)] = true}
		local queueindex = 1
-- watermark:2/8:6b616b6f5a6162696a

		while queueindex <= #queue do
			local cell = queue[queueindex]
			queueindex += 1
			local xindex = cell[1]
			local zindex = cell[2]
			for _, offset in {{1, 0}, {-1, 0}, {0, 1}, {0, -1}} do
				local nextx = xindex + offset[1]
				local nextz = zindex + offset[2]
				local key = gridkey(nextx, nextz)
				if nextx >= 0 and nextx <= xcount and nextz >= 0 and nextz <= zcount
					and not blocked[key] and not reachable[key] then
					reachable[key] = true
					table.insert(queue, {nextx, nextz})
				end
			end
		end

		local floortop = mazefloor.Position.Y + mazefloor.Size.Y * 0.5
		local points = {}
		for xindex = 0, xcount do
			for zindex = 0, zcount do
				local key = gridkey(xindex, zindex)
				if reachable[key] and not blocked[key] then
					local point = Vector3.new(minx + xindex * cellsize, floortop + 3, minz + zindex * cellsize)
					local goaldifference = point - goal.Position
					if Vector2.new(goaldifference.X, goaldifference.Z).Magnitude >= 24 then
						table.insert(points, point)
					end
				end
			end
		end
		return points
	end

	local function randomizeagentspawns(models: {Model})
		local random = Random.new(41317)
		local points = collectreachablespawnpoints()
		if #points < #models then
			warn(string.format("[maze agents] only %d reachable random spawn cells were found", #points))
			return
		end

		for index = #points, 2, -1 do
			local swapindex = random:NextInteger(1, index)
			points[index], points[swapindex] = points[swapindex], points[index]
		end
-- watermark:3/8:616b20286c756b616b

		local maximumgoaldistance = 0
		for _, point in points do
			local difference = point - goal.Position
			maximumgoaldistance = math.max(maximumgoaldistance, Vector2.new(difference.X, difference.Z).Magnitude)
		end
		local farsidethreshold = maximumgoaldistance * 0.76
		local selectedpoints = {}
		local function tryselect(point: Vector3): boolean
			local isspaced = true
			for _, selected in selectedpoints do
				local difference = point - selected
				if Vector2.new(difference.X, difference.Z).Magnitude < minimumspawnspacing then
					isspaced = false
					break
				end
			end
			if isspaced then
				table.insert(selectedpoints, point)
				return true
			end
			return false
		end

		local farsidetarget = math.min(farsideagentcount, #models)
		for _, point in points do
			local difference = point - goal.Position
			local goaldistance = Vector2.new(difference.X, difference.Z).Magnitude
			if goaldistance >= farsidethreshold then
				tryselect(point)
				if #selectedpoints >= farsidetarget then
					break
				end
			end
		end

		for _, point in points do
			if #selectedpoints >= #models then
				break
			end
			if not table.find(selectedpoints, point) then
				tryselect(point)
			end
		end
-- watermark:4/8:6f7a6162696a616b29

		if #selectedpoints < #models then
			warn(string.format("[maze agents] spacing fallback: selected %d of %d agents", #selectedpoints, #models))
			for _, point in points do
				if #selectedpoints >= #models then
					break
				end
				if not table.find(selectedpoints, point) then
					table.insert(selectedpoints, point)
				end
			end
		end

		for index, model in models do
			local baseposition = selectedpoints[index]
			local jitter = Vector3.new(random:NextNumber(-0.7, 0.7), 0, random:NextNumber(-0.7, 0.7))
			local yaw = math.rad(random:NextInteger(0, 3) * 90)
			local spawnposition = baseposition + jitter
			model:PivotTo(CFrame.new(spawnposition) * CFrame.Angles(0, yaw, 0))
			model:SetAttribute("SpawnCellX", baseposition.X)
			model:SetAttribute("SpawnCellZ", baseposition.Z)
			local goaldifference = baseposition - goal.Position
			model:SetAttribute("SpawnGoalDistance", Vector2.new(goaldifference.X, goaldifference.Z).Magnitude)
		end
	end

	local function preparedemo(models: {Model})
		local wall = maze:FindFirstChild("Wall_32_31")
		assert(wall and wall:IsA("BasePart"), "demo wall is missing")
		-- old timestamps would release the next runner immediately, clear the whole demo state first
		for name in agentsfolder:GetAttributes() do
			if string.sub(name, 1, 4) == "demo" then agentsfolder:SetAttribute(name, nil) end
		end
		-- the camera can use this position even after the wall has been destroyed
		agentsfolder:SetAttribute("demofocus", wall.Position)
		local width = math.round(mazefloor.Size.X / 8)
		local origin = Vector3.new(-mazefloor.Size.X / 2 + 4, mazefloor.Size.Y / 2, -mazefloor.Size.Z / 2 + 4)
		local point = mazefloor.CFrame:PointToObjectSpace(wall.Position) - origin
		agentsfolder:SetAttribute("democell", math.round(point.Z / 8) * width + math.round(point.X / 8) + 1)
		agentsfolder:SetAttribute("demowall", wall.Name)
		agentsfolder:SetAttribute("demophase", "discovery")
		for _, name in {"demoshared", "demoshortcut", "democomplete"} do agentsfolder:SetAttribute(name, false) end
		-- these starts give two runners a route before the third rig checks the wall beside it
		-- the planner still has to find its own way, none of these positions supplies a route
		local starts = {1219, 1137, 1221}
		for index, model in models do
			model:SetAttribute("demorole", if index == 3 then "scout" elseif index <= 2 then "runner" else "background")
			model:SetAttribute("startdelay", if index <= 3 then 5 else 23)
			local cell = starts[index]
			if not cell then continue end
			local position = mazefloor.CFrame:PointToWorldSpace(origin + Vector3.new((cell - 1) % width * 8, 3, math.floor((cell - 1) / width) * 8))
			model:PivotTo(CFrame.new(position))
			model:SetAttribute("SpawnCellX", position.X)
			model:SetAttribute("SpawnCellZ", position.Z)
			model:SetAttribute("SpawnGoalDistance", (position - goal.Position).Magnitude)
		end
	end
-- watermark:5/8:206f6e20446973636f

	local function createmarkers(model: Model): {{BasePart}}
		local existing = model:FindFirstChild("PathScanMarkers")
		if existing then
			existing:Destroy()
		end

		local folder = Instance.new("Folder")
		folder.Name = "PathScanMarkers"
		folder.Parent = model

		local markers = table.create(#scanangles)
		for directionindex = 1, #scanangles do
			local directionfolder = Instance.new("Folder")
			directionfolder.Name = string.format("Direction_%02d", directionindex)
			directionfolder.Parent = folder

			local line = table.create(probedotcount)
			for dotindex = 1, probedotcount do
				local marker = Instance.new("Part")
				marker.Name = string.format("Dot_%02d", dotindex)
				marker.Shape = Enum.PartType.Cylinder
				marker.Size = Vector3.new(0.1, 0.58, 0.58)
				marker.Anchored = true
				marker.CanCollide = false
				marker.CanQuery = false
				marker.CanTouch = false
				marker.CastShadow = false
				marker.Material = Enum.Material.Neon
				marker.Color = wrongcolor
				marker.Transparency = 1
				marker.Parent = directionfolder
				line[dotindex] = marker
			end
			markers[directionindex] = line
		end
		return markers
	end

	local function createnavigationcollider(model: Model, root: BasePart): BasePart
		local existing = model:FindFirstChild("NavigationCollider")
		if existing then
			existing:Destroy()
		end
-- watermark:6/8:72642c206b696c6c65

		local collider = Instance.new("Part")
		collider.Name = "NavigationCollider"
		collider.Shape = Enum.PartType.Cylinder
		collider.Size = Vector3.new(4.6, 2.35, 2.35)
		collider.CFrame = root.CFrame * CFrame.new(0, -0.7, 0) * CFrame.Angles(0, 0, math.rad(90))
		collider.Transparency = 1
		collider.CanCollide = true
		collider.CanTouch = false
		collider.CanQuery = false
		collider.CastShadow = false
		collider.Massless = false
		collider.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 1, 1)
		collider.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Name = "NavigationColliderWeld"
		weld.Part0 = root
		weld.Part1 = collider
		weld.Parent = collider
		return collider
	end

	local function configureagent(model: Model): rig?
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or not root:IsA("BasePart") then
			warn(string.format("[maze agents] skipped invalid rig %s", model:GetFullName()))
			return nil
		end

		model:SetAttribute("MazeAgent", true)
		model:SetAttribute("PathState", "initializing")
		model:SetAttribute("CommunicationState", "online")
		model:SetAttribute("ReceivedKnowledgeMessages", 0)
		model:SetAttribute("ScannerActive", true)
		humanoid.WalkSpeed = cruisespeed
		humanoid.AutoRotate = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		local collider = createnavigationcollider(model, root)

		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				if descendant ~= collider then
					descendant.CanCollide = false
				end
				descendant.CollisionGroup = agentcollisiongroup
				if not descendant.Anchored then
					pcall(function()
						descendant:SetNetworkOwner(nil)
					end)
				end
			end
		end
-- watermark:7/8:726f7833393035206f

		local raycastparams = RaycastParams.new()
		raycastparams.FilterType = Enum.RaycastFilterType.Exclude
		raycastparams.FilterDescendantsInstances = {agentsfolder}
		raycastparams.RespectCanCollide = true
		raycastparams.CollisionGroup = agentcollisiongroup


		return {
	        model = model, humanoid = humanoid, root = root,
	        markers = createmarkers(model), raycastparams = raycastparams,
	    }
	end

	configurecollisiongroup()
	configurenavigationdecor()
	local models: {Model} = {}
	for _, model in agentsfolder:GetChildren() do
	    if model:IsA("Model") then
	        table.insert(models, model)
	    end
	end
	table.sort(models, function(left, right) return left.Name < right.Name end)
	randomizeagentspawns(models)
	preparedemo(models)
	local result: {rig} = {}
	for _, model in models do
	    local state = configureagent(model)
	    if state then
	        table.insert(result, state)
	    end
	end
	return result
end

function module.clear(state: rig)
    for _, line in state.markers do
        for _, marker in line do
            marker:Destroy()
        end
    end
    table.clear(state.markers)
end
-- watermark:8/8:6e20526f626c6f782e

-- green follows the next movement target, cyan is the short pulse for a shared discovery
function module.draw(state: rig, target: Vector3, sharedelapsed: number)
    local flat = Vector3.new(target.X - state.root.Position.X, 0, target.Z - state.root.Position.Z)
    local forward = Vector3.new(state.root.CFrame.LookVector.X, 0, state.root.CFrame.LookVector.Z)
    if forward.Magnitude < 0.01 then return end
    forward = forward.Unit
    local desired = if flat.Magnitude > 0.01 then flat.Unit else forward
    local best = 1
    local bestscore = -math.huge
    local directions: {Vector3} = {}
    local clearances: {number} = {}
    for index, angle in scanangles do
        local rotation = CFrame.Angles(0, -math.rad(angle), 0)
        local direction = rotation:VectorToWorldSpace(forward)
        directions[index] = direction
        local side = Vector3.new(-direction.Z, 0, direction.X) * 0.8
        local clearance = 14
        for _, offset in {Vector3.zero, side, -side} do
            local hit = workspace:Raycast(state.root.Position + Vector3.new(0, 1.25, 0) + offset, direction * 14, state.raycastparams)
            if hit then clearance = math.min(clearance, hit.Distance) end
        end
        clearances[index] = clearance
        local score = direction:Dot(desired)
        if clearance >= 3.96 and score > bestscore then
            best, bestscore = index, score
        end
    end
    for index, line in state.markers do
        for dot, marker in line do
            local distance = dot * 2.2
            local point = state.root.Position + directions[index] * distance
            local selected = index == best and bestscore > -math.huge
            local pulse = sharedelapsed >= (dot - 1) * 0.075 and sharedelapsed <= (dot - 1) * 0.075 + 0.18
            local color = if pulse then Color3.fromRGB(53, 217, 255) elseif selected then Color3.fromRGB(55, 255, 120) else wrongcolor
            local transparency = if distance > clearances[index] + 0.15 then 1 elseif selected then 0.06 else 0.16
            local diameter = if selected then 0.68 else 0.58
            marker.Color = marker.Color:Lerp(color, 0.62)
            marker.Transparency += (transparency - marker.Transparency) * 0.62
            marker.Size = marker.Size:Lerp(Vector3.new(0.1, diameter, diameter), 0.62)
            marker.CFrame = CFrame.new(point.X, 0.07, point.Z) * CFrame.Angles(0, 0, math.rad(90))
        end
    end
    state.model:SetAttribute("CorrectProbe", best)
end

function module.watch(owner: Instance, cleanup: () -> ())
    owners[owner] = cleanup
end

return module
