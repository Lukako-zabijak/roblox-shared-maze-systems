--!strict

-- Made by LukakoZabijak (lukakozabijak) on Discord, killerox3905 on Roblox.
-- 4d616465206279204c756b616b6f5a6162696a616b20286c756b616b6f7a6162696a616b29206f6e20446973636f72642c206b696c6c65726f7833393035206f6e20526f626c6f782e
local debris_service = game:GetService("Debris")
local physics_service = game:GetService("PhysicsService")
local run_service = game:GetService("RunService")
local server_storage = game:GetService("ServerStorage")
local tween_service = game:GetService("TweenService")

local maze = workspace:WaitForChild("Maze")
local agents = workspace:WaitForChild("MazeAgents")
local maze_floor = maze:WaitForChild("MazeFloor") :: BasePart
local goal = maze:WaitForChild("GoalPad") :: BasePart
local world_changed_event = server_storage:WaitForChild("maze_world_changed") :: BindableEvent
local spawn_location = workspace:FindFirstChildOfClass("SpawnLocation")

local random = Random.new(76231)
local collapse_collision_group = "maze_collapse_debris"
pcall(function()
	physics_service:RegisterCollisionGroup(collapse_collision_group)
end)
physics_service:CollisionGroupSetCollidable(collapse_collision_group, collapse_collision_group, false)

local collapse_count = 8
local minimum_wall_spacing = 48
local warning_pulses = 3
local minimum_collapse_interval = 8
local maximum_collapse_interval = 13
local chunk_cleanup_delay = 5.5
local boundary_margin = 20
local goal_exclusion_radius = 32
local spawn_exclusion_radius = 28

local old_debris_folder = workspace:FindFirstChild("maze_collapse_debris")
if old_debris_folder then
	old_debris_folder:Destroy()
end

local debris_folder = Instance.new("Folder")
debris_folder.Name = "maze_collapse_debris"
debris_folder.Parent = workspace

-- the folder identity changes on restart, so old callbacks can't send changes into the next run
local function currentrun(): boolean
	return script:IsDescendantOf(game) and workspace:FindFirstChild("maze_collapse_debris") == debris_folder
end

local function announce(id: string, position: Vector3, phase: string, revision: number, parts: {BasePart})
	if not currentrun() then return end
	world_changed_event:Fire({owner = debris_folder, id = id, position = position, phase = phase, revision = revision, parts = table.clone(parts)})
end

local function planar_distance(left: Vector3, right: Vector3): number
	local difference = left - right
	return Vector2.new(difference.X, difference.Z).Magnitude
end
-- watermark:1/8:4d616465206279204c75

local function collect_candidates(): {BasePart}
	local candidates: {BasePart} = {}
	local half_floor = maze_floor.Size * 0.5

	for _, child in maze:GetChildren() do
		if child:IsA("BasePart")
			and string.find(child.Name, "Wall_", 1, true) == 1
			and child.Anchored
			and child.CanCollide
			and child.Size.Y >= 8
			and child.Size.X >= 4
			and child.Size.Z >= 4 then
			local local_position = maze_floor.CFrame:PointToObjectSpace(child.Position)
			local is_interior = math.abs(local_position.X) <= half_floor.X - boundary_margin
				and math.abs(local_position.Z) <= half_floor.Z - boundary_margin
			local far_from_goal = planar_distance(child.Position, goal.Position) >= goal_exclusion_radius
			local far_from_spawn = not spawn_location
				or planar_distance(child.Position, spawn_location.Position) >= spawn_exclusion_radius

			if is_interior and far_from_goal and far_from_spawn then
				table.insert(candidates, child)
			end
		end
	end

	for index = #candidates, 2, -1 do
		local swap_index = random:NextInteger(1, index)
		candidates[index], candidates[swap_index] = candidates[swap_index], candidates[index]
	end
	return candidates
end

local function choose_walls(candidates: {BasePart}): {BasePart}
	local selected: {BasePart} = {}
	local focus = maze:FindFirstChild("Wall_32_31")
	assert(focus and focus:IsA("BasePart"), "demo wall is missing")
	table.insert(selected, focus)

	local function is_spaced(candidate: BasePart, spacing: number): boolean
		for _, existing in selected do
			if planar_distance(candidate.Position, existing.Position) < spacing then
				return false
			end
		end
		return true
	end
-- watermark:2/8:6b616b6f5a6162696a

	for _, candidate in candidates do
		if candidate ~= focus and is_spaced(candidate, minimum_wall_spacing) then
			table.insert(selected, candidate)
			if #selected >= collapse_count then
				return selected
			end
		end
	end

	for _, candidate in candidates do
		if not table.find(selected, candidate) and is_spaced(candidate, 24) then
			table.insert(selected, candidate)
			if #selected >= collapse_count then
				break
			end
		end
	end
	return selected
end

local function create_warning_marker(wall: BasePart): (Highlight, BasePart)
	local highlight = Instance.new("Highlight")
	highlight.Name = "collapse_warning"
	highlight.Adornee = wall
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(255, 132, 44)
	highlight.FillTransparency = 0.78
	highlight.OutlineColor = Color3.fromRGB(255, 205, 82)
	highlight.OutlineTransparency = 0.08
	highlight.Parent = wall

	local marker = Instance.new("Part")
	marker.Name = "collapse_warning"
	marker.Size = Vector3.new(wall.Size.X * 1.18, 0.08, wall.Size.Z * 1.18)
	marker.CFrame = CFrame.new(
		wall.Position.X,
		maze_floor.Position.Y + maze_floor.Size.Y * 0.5 + 0.05,
		wall.Position.Z
	)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 151, 48)
	marker.Transparency = 0.48
	marker.Parent = debris_folder

	return highlight, marker
end

local function warn_wall(wall: BasePart): boolean
	if not wall.Parent or not currentrun() then
		return false
	end
-- watermark:3/8:616b20286c756b616b

	wall:SetAttribute("CollapseState", "warning")
	announce(wall.Name, wall.Position, "warning", 1, {})

	local highlight, marker = create_warning_marker(wall)
	for _ = 1, warning_pulses do
		if not wall.Parent or not currentrun() then
			highlight:Destroy()
			marker:Destroy()
			return false
		end

		local brighten_highlight = tween_service:Create(
			highlight,
			TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{FillTransparency = 0.38, OutlineTransparency = 0}
		)
		local brighten_marker = tween_service:Create(
			marker,
			TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Transparency = 0.12}
		)
		brighten_highlight:Play()
		brighten_marker:Play()
		brighten_marker.Completed:Wait()

		local dim_highlight = tween_service:Create(
			highlight,
			TweenInfo.new(0.26, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{FillTransparency = 0.82, OutlineTransparency = 0.32}
		)
		local dim_marker = tween_service:Create(
			marker,
			TweenInfo.new(0.26, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{Transparency = 0.62}
		)
		dim_highlight:Play()
		dim_marker:Play()
		dim_marker.Completed:Wait()
	end

	highlight:Destroy()
	marker:Destroy()
	return wall.Parent ~= nil and currentrun()
end
-- watermark:4/8:6f7a6162696a616b29

local function spawn_small_debris(wall: BasePart, amount: number, parts: {BasePart})
	for index = 1, amount do
		local fragment = Instance.new("Part")
		fragment.Name = "falling_fragment"
		local width = random:NextNumber(0.18, 0.55)
		fragment.Size = Vector3.new(width, random:NextNumber(0.15, 0.5), width)
		fragment.CFrame = wall.CFrame * CFrame.new(
			random:NextNumber(-wall.Size.X * 0.48, wall.Size.X * 0.48),
			random:NextNumber(-wall.Size.Y * 0.25, wall.Size.Y * 0.48),
			random:NextNumber(-wall.Size.Z * 0.48, wall.Size.Z * 0.48)
		)
		fragment.Anchored = false
		local is_collidable = index <= math.ceil(amount * 0.4)
		fragment.CanCollide = is_collidable
		fragment.CanQuery = is_collidable
		fragment.CanTouch = false
		fragment.CastShadow = true
		fragment.Color = wall.Color
		fragment.Material = wall.Material
		fragment.CustomPhysicalProperties = PhysicalProperties.new(1.8, 0.65, 0.05, 100, 20)
		fragment.Parent = debris_folder
		table.insert(parts, fragment)
		pcall(function()
			fragment:SetNetworkOwner(nil)
		end)
		fragment.AssemblyLinearVelocity = Vector3.new(
			random:NextNumber(-10, 10),
			random:NextNumber(3, 12),
			random:NextNumber(-10, 10)
		)
		fragment.AssemblyAngularVelocity = Vector3.new(
			random:NextNumber(-8, 8),
			random:NextNumber(-8, 8),
			random:NextNumber(-8, 8)
		)
		debris_service:AddItem(fragment, random:NextNumber(3.5, 5))
	end
end

local function schedule_chunk_cleanup(chunk: BasePart)
	task.delay(chunk_cleanup_delay + random:NextNumber(0, 1.2), function()
		if not chunk.Parent then
			return
		end
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		local fade = tween_service:Create(
			chunk,
			TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = 1}
		)
		fade:Play()
		debris_service:AddItem(chunk, 0.75)
	end)
end
-- watermark:5/8:206f6e20446973636f

local function build_chunks(wall: BasePart): ({{BasePart}}, {BasePart})
	local layers: {{BasePart}} = table.create(3)
	local all_chunks: {BasePart} = {}
	local chunk_size = Vector3.new(
		math.max(0.5, wall.Size.X / 2 - 0.08),
		math.max(0.5, wall.Size.Y / 3 - 0.08),
		math.max(0.5, wall.Size.Z / 2 - 0.08)
	)

	for y_index = 1, 3 do
		local layer: {BasePart} = {}
		layers[y_index] = layer
		for x_index = 1, 2 do
			for z_index = 1, 2 do
				local chunk = wall:Clone()
				chunk:ClearAllChildren()
				chunk.Name = string.lower(wall.Name) .. "_chunk"
				chunk.Size = chunk_size
				local x_offset = (x_index - 1.5) * (wall.Size.X / 2)
				local y_offset = (y_index - 2) * (wall.Size.Y / 3)
				local z_offset = (z_index - 1.5) * (wall.Size.Z / 2)
				chunk.CFrame = wall.CFrame * CFrame.new(x_offset, y_offset, z_offset)
				chunk.Anchored = true
				chunk.CanCollide = true
				chunk.CanQuery = true
				chunk.CanTouch = true
				chunk.CollisionGroup = collapse_collision_group
				chunk.Transparency = wall.Transparency
				chunk.CustomPhysicalProperties = PhysicalProperties.new(2, 0.35, 0.1, 100, 25)
				chunk:SetAttribute("CollapseDebris", true)
				chunk.Parent = debris_folder
				table.insert(layer, chunk)
				table.insert(all_chunks, chunk)
			end
		end
	end

	return layers, all_chunks
end

local function monitor_chunk_landing(chunk: BasePart)
	local floor_top = maze_floor.Position.Y + maze_floor.Size.Y * 0.5
	local started_at = os.clock()

	task.spawn(function()
		while chunk.Parent and not chunk.Anchored and os.clock() - started_at < 4.5 do
			local right = chunk.CFrame.RightVector
			local up = chunk.CFrame.UpVector
			local look = chunk.CFrame.LookVector
			local vertical_half_extent = (
				math.abs(right.Y) * chunk.Size.X
				+ math.abs(up.Y) * chunk.Size.Y
				+ math.abs(look.Y) * chunk.Size.Z
			) * 0.5
			local lowest_point = chunk.Position.Y - vertical_half_extent
			local has_fallen = os.clock() - started_at >= 0.05
-- watermark:6/8:72642c206b696c6c65

			if has_fallen
				and lowest_point <= floor_top + 0.18
				and chunk.AssemblyLinearVelocity.Y <= 1.5 then
				local position = chunk.Position
				local yaw = math.rad(random:NextNumber(0, 360))
				local rest_rotation: CFrame
				local rest_height: number

				if chunk.Size.X >= chunk.Size.Z then
					rest_rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.rad(90))
					rest_height = chunk.Size.X * 0.5
				else
					rest_rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(90), 0, 0)
					rest_height = chunk.Size.Z * 0.5
				end

				chunk.CFrame = CFrame.new(position.X, floor_top + rest_height + 0.04, position.Z) * rest_rotation
				chunk.AssemblyLinearVelocity = Vector3.zero
				chunk.AssemblyAngularVelocity = Vector3.zero
				chunk.Anchored = true
				chunk:SetAttribute("LandedOnMazeFloor", true)
				chunk:SetAttribute("LandingY", chunk.Position.Y)
				return
			end
			run_service.Heartbeat:Wait()
		end
	end)
end

local function release_layer(wall: BasePart, layer: {BasePart}, layer_index: number, parts: {BasePart})
	for _, chunk in layer do
		local offset = chunk.Position - wall.Position
		local outward = Vector3.new(offset.X, 0, offset.Z)
		if outward.Magnitude < 0.1 then
			outward = wall.CFrame.RightVector
		end
		outward = outward.Unit
		local tangent = Vector3.new(-outward.Z, 0, outward.X) * random:NextNumber(-0.3, 0.3)
		local release_direction = (outward + tangent).Unit
		local downward_speed = random:NextNumber(1, 4) + (3 - layer_index) * 0.5
-- watermark:7/8:726f7833393035206f

		chunk.Anchored = false
		pcall(function()
			chunk:SetNetworkOwner(nil)
		end)
		chunk.AssemblyLinearVelocity = release_direction * random:NextNumber(11, 18)
			+ Vector3.new(0, -downward_speed, 0)
		chunk.AssemblyAngularVelocity = Vector3.new(
			random:NextNumber(-9, 9),
			random:NextNumber(-6, 6),
			random:NextNumber(-9, 9)
		)
		chunk:SetAttribute("ReleasedTowardGround", true)
		monitor_chunk_landing(chunk)
		schedule_chunk_cleanup(chunk)
	end
	spawn_small_debris(wall, 6, parts)
end

local function waitforclear(id: string, position: Vector3, parts: {BasePart})
	task.spawn(function()
		while currentrun() do
			local blocked = false
			for _, part in parts do
				if part:IsDescendantOf(workspace) and part.CanCollide then
					blocked = true
					break
				end
			end
			if not blocked then
				announce(id, position, "cleared", 3, parts)
				return
			end
			-- include the small pieces too, the last big chunk isn't always the last obstruction
			task.wait(0.16)
		end
	end)
end

local function collapse_wall(wall: BasePart)
	local id, position = wall.Name, wall.Position
	if not warn_wall(wall) then
		announce(id, position, "cleared", 3, {})
		return
	end
	wall:SetAttribute("CollapseState", "falling")
	local layers, parts = build_chunks(wall)
	local chunkcount = #parts
	wall.Transparency = 1
	wall.CanCollide = false
	wall.CanQuery = false
	wall.CanTouch = false
	for layer_index = 1, 3 do
		if not currentrun() then return end
		release_layer(wall, layers[layer_index], layer_index, parts)
		task.wait(0.09)
	end
	-- every layer has released now, this snapshot includes all chunks and fragments
	announce(id, position, "falling", 2, parts)
	wall:Destroy()
	debris_folder:SetAttribute("LastCollapsedChunkCount", chunkcount)
	debris_folder:SetAttribute("CollapsedWalls", (debris_folder:GetAttribute("CollapsedWalls") or 0) + 1)
	waitforclear(id, position, parts)
end
-- watermark:8/8:6e20526f626c6f782e

local function awaitdemo(attribute: string, timeout: number): boolean
	local deadline = os.clock() + timeout
	while currentrun() and os.clock() < deadline do
		if agents:GetAttribute(attribute) == true then return true end
		task.wait(0.16)
	end
	if currentrun() then
		agents:SetAttribute("demophase", "incomplete")
		warn("[maze demo] timed out waiting for " .. attribute)
	end
	return false
end

local candidates = collect_candidates()
local selected_walls = choose_walls(candidates)
debris_folder:SetAttribute("CandidateCount", #candidates)
debris_folder:SetAttribute("SelectedWallCount", #selected_walls)
debris_folder:SetAttribute("CollapsedWalls", 0)

for index, wall in selected_walls do
	wall:SetAttribute("CollapsibleWall", true)
	wall:SetAttribute("CollapseOrder", index)
	wall:SetAttribute("CollapseState", "stable")
end

-- leave time to see the peer react before drawing attention to the wall
if not awaitdemo("demoshared", 30) then return end
task.wait(3)
for index, wall in selected_walls do
	if not currentrun() then break end
	if wall.Parent then
		collapse_wall(wall)
	end
	if index == 1 and not awaitdemo("democomplete", 90) then return end
	if index < #selected_walls then
		task.wait(random:NextNumber(minimum_collapse_interval, maximum_collapse_interval))
	end
end

print(string.format(
	"[maze collapse] completed %d of %d selected structural collapses",
	debris_folder:GetAttribute("CollapsedWalls") or 0,
	#selected_walls
))
