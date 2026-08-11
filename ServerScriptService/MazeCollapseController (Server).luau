-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.
--!strict

local debris_service = game:GetService("Debris")
local physics_service = game:GetService("PhysicsService")
local run_service = game:GetService("RunService")
local server_storage = game:GetService("ServerStorage")
local tween_service = game:GetService("TweenService")

local maze = workspace:WaitForChild("Maze")
local agents_folder = workspace:WaitForChild("MazeAgents")
local maze_floor = maze:WaitForChild("MazeFloor") :: BasePart
local goal = maze:WaitForChild("GoalPad") :: BasePart
local world_changed_event = server_storage:WaitForChild("maze_world_changed") :: BindableEvent
local spawn_location = workspace:FindFirstChildOfClass("SpawnLocation")

-- debris uses its own collision group so pieces can collide with the maze without
-- repeatedly colliding with one another and creating unstable physics clusters.
local random = Random.new()
local collapse_collision_group = "maze_collapse_debris"
pcall(function()
	-- registration can fail when a previous run already created the group, but that
	-- existing group is still valid and should be reused.
	physics_service:RegisterCollisionGroup(collapse_collision_group)
end)
-- disabling debris-to-debris collision prevents twelve chunks from repeatedly
-- striking each other while they are released from the same wall volume.
physics_service:CollisionGroupSetCollidable(
	collapse_collision_group,
	collapse_collision_group,
	false
)

local collapse_count = 8
local minimum_wall_spacing = 48
local warning_pulses = 3
local first_collapse_delay = 5.5
local minimum_collapse_interval = 8
local maximum_collapse_interval = 13
local chunk_cleanup_delay = 5.5
local boundary_margin = 20
local goal_exclusion_radius = 32
local spawn_exclusion_radius = 28

local old_debris_folder = workspace:FindFirstChild("maze_collapse_debris")
if old_debris_folder then
	-- studio test sessions can leave generated debris behind, so stale state must not
	-- be counted or simulated by the next controller run.
	old_debris_folder:Destroy()
end

local debris_folder = Instance.new("Folder")
debris_folder.Name = "maze_collapse_debris"
debris_folder.Parent = workspace

-- wall selection only needs horizontal distance because height differences do not
-- affect whether two collapses are too close together on the maze grid.
local function planar_distance(left: Vector3, right: Vector3): number
	local difference = left - right
	return Vector2.new(difference.X, difference.Z).Magnitude
end

-- candidates must be structural interior walls. boundary, spawn, and goal exclusions
-- preserve the playable enclosure and prevent a collapse from invalidating key areas.
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
			-- object space keeps the boundary test correct even if the whole maze is rotated.
			local local_position = maze_floor.CFrame:PointToObjectSpace(child.Position)
			local is_interior = math.abs(local_position.X) <= half_floor.X - boundary_margin
				and math.abs(local_position.Z) <= half_floor.Z - boundary_margin
			-- opening a wall beside the objective or spawn could create an unintended
			-- shortcut or place falling debris where players enter the experience.
			local far_from_goal = planar_distance(child.Position, goal.Position) >= goal_exclusion_radius
			local far_from_spawn = not spawn_location
				or planar_distance(child.Position, spawn_location.Position) >= spawn_exclusion_radius

			if is_interior and far_from_goal and far_from_spawn then
				table.insert(candidates, child)
			end
		end
	end

	-- fisher-yates randomizes the candidate order without bias before spacing is applied.
	for index = #candidates, 2, -1 do
		local swap_index = random:NextInteger(1, index)
		candidates[index], candidates[swap_index] = candidates[swap_index], candidates[index]
	end
	return candidates
end

-- the first pass favors wide distribution. the second pass relaxes spacing only when
-- the maze cannot supply the requested count, while still avoiding adjacent collapses.
local function choose_walls(candidates: {BasePart}): {BasePart}
	local selected: {BasePart} = {}

	local function is_spaced(candidate: BasePart, spacing: number): boolean
		for _, existing in selected do
			if planar_distance(candidate.Position, existing.Position) < spacing then
				return false
			end
		end
		return true
	end

	-- if strict spacing cannot provide eight walls, a smaller lower bound is preferable
	-- to silently omitting most of the scheduled structural events.
	for _, candidate in candidates do
		if is_spaced(candidate, minimum_wall_spacing) then
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

-- both an always-visible highlight and a floor marker are used so the warning remains
-- readable when the wall is occluded or outside the player's direct viewing angle.
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
	-- the marker is placed from the floor's top surface instead of the wall's bottom,
	-- ensuring it stays visible when wall pivots or heights differ.
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

-- warnings complete before physics begins. checking parent throughout the yielded
-- tween sequence prevents work from continuing if another system removes the wall.
local function warn_wall(wall: BasePart): boolean
	if not wall.Parent then
		return false
	end

	wall:SetAttribute("CollapseState", "warning")
	world_changed_event:Fire(
		string.format("structural warning - %s is becoming unstable", string.lower(wall.Name)),
		"collapse_warning",
		false
	)

	local highlight, marker = create_warning_marker(wall)
	for _ = 1, warning_pulses do
		if not wall.Parent then
			-- every tween yields, so the wall may have been removed since the last check.
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
		-- waiting on one tween keeps both warning visuals in the same pulse phase.
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
	return wall.Parent ~= nil
end

-- small fragments are temporary visual detail. only a bounded portion can collide,
-- which keeps the effect readable without making every fragment a physics obstacle.
local function spawn_small_debris(wall: BasePart, amount: number)
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
		-- only forty percent become obstacles; the rest are visual detail that cannot
		-- multiply contact calculations or block the newly opened route.
		local is_collidable = index <= math.ceil(amount * 0.4)
		fragment.CanCollide = is_collidable
		fragment.CanQuery = is_collidable
		fragment.CanTouch = false
		fragment.CastShadow = true
		fragment.Color = wall.Color
		fragment.Material = wall.Material
		fragment.CustomPhysicalProperties = PhysicalProperties.new(1.8, 0.65, 0.05, 100, 20)
		fragment.Parent = debris_folder
		pcall(function()
			-- server ownership makes the authoritative collapse identical for all clients.
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
		-- randomized lifetimes prevent every fragment from disappearing on one frame.
		debris_service:AddItem(fragment, random:NextNumber(3.5, 5))
	end
end

-- large chunks remain usable obstacles briefly, then lose collision before fading so
-- players and agents cannot become trapped by debris that is already disappearing.
local function schedule_chunk_cleanup(chunk: BasePart)
	task.delay(chunk_cleanup_delay + random:NextNumber(0, 1.2), function()
		if not chunk.Parent then
			-- debris may be removed by a reset before this delayed callback resumes.
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

-- cloning the original wall preserves its material and appearance. a fixed three by
-- two by two partition produces twelve predictable chunks for layered destruction.
local function build_chunks(wall: BasePart): ({{BasePart}}, {BasePart})
	local layers: {{BasePart}} = table.create(3)
	local all_chunks: {BasePart} = {}
	-- the small subtraction leaves a visible seam and prevents cloned chunks from
	-- starting in overlapping contact with one another.
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
				-- subtracting 1.5 centers the two horizontal indices around the wall pivot.
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

-- landing is derived from the chunk's rotated vertical extent rather than its center.
-- anchoring settled chunks removes ongoing solver cost and gives debris a stable pose.
local function monitor_chunk_landing(chunk: BasePart)
	local floor_top = maze_floor.Position.Y + maze_floor.Size.Y * 0.5
	local started_at = os.clock()

	task.spawn(function()
		while chunk.Parent and not chunk.Anchored and os.clock() - started_at < 4.5 do
			local right = chunk.CFrame.RightVector
			local up = chunk.CFrame.UpVector
			local look = chunk.CFrame.LookVector
			-- projecting all three local axes onto world y finds the true lowest point
			-- while the chunk is tumbling; size.y alone only works when it is upright.
			local vertical_half_extent = (
				math.abs(right.Y) * chunk.Size.X
				+ math.abs(up.Y) * chunk.Size.Y
				+ math.abs(look.Y) * chunk.Size.Z
			) * 0.5
			local lowest_point = chunk.Position.Y - vertical_half_extent
			-- the short grace period prevents a newly released chunk from being marked
			-- landed before physics has advanced it away from its starting position.
			local has_fallen = os.clock() - started_at >= 0.05

			if has_fallen
				and lowest_point <= floor_top + 0.18
				and chunk.AssemblyLinearVelocity.Y <= 1.5 then
				local position = chunk.Position
				local yaw = math.rad(random:NextNumber(0, 360))
				local rest_rotation: CFrame
				local rest_height: number

				-- rest the chunk on its longest horizontal side to avoid an implausible
				-- upright pose and reduce the chance that it tips after being anchored.
				if chunk.Size.X >= chunk.Size.Z then
					rest_rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.rad(90))
					rest_height = chunk.Size.X * 0.5
				else
					rest_rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(90), 0, 0)
					rest_height = chunk.Size.Z * 0.5
				end

				chunk.CFrame = CFrame.new(
					position.X,
					floor_top + rest_height + 0.04,
					position.Z
				) * rest_rotation
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

-- layers are released separately to make the wall fail progressively. server network
-- ownership keeps the authoritative collapse consistent for every connected client.
local function release_layer(wall: BasePart, layer: {BasePart}, layer_index: number)
	for _, chunk in layer do
		local offset = chunk.Position - wall.Position
		local outward = Vector3.new(offset.X, 0, offset.Z)
		if outward.Magnitude < 0.1 then
			outward = wall.CFrame.RightVector
		end
		outward = outward.Unit
		-- a small perpendicular component stops all chunks from following identical
		-- radial paths while preserving the overall outward collapse direction.
		local tangent = Vector3.new(-outward.Z, 0, outward.X) * random:NextNumber(-0.3, 0.3)
		local release_direction = (outward + tangent).Unit
		local downward_speed = random:NextNumber(1, 4) + (3 - layer_index) * 0.5

		chunk.Anchored = false
		pcall(function()
			-- the server owns gameplay debris because clients must not disagree about
			-- whether the newly opened route is physically blocked.
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
	spawn_small_debris(wall, 6)
end

-- the count is calculated when the notification is sent so it reflects the current
-- simulation rather than the number of agents that existed during initialization.
local function current_agent_count(): number
	local count = 0
	for _, child in agents_folder:GetChildren() do
		if child:IsA("Model") then
			count += 1
		end
	end
	return count
end

-- this is the collapse transaction: warn, replace the wall with chunks, notify pathing,
-- release debris, remove the original, and announce when the new route becomes usable.
local function collapse_wall(wall: BasePart)
	if not warn_wall(wall) then
		return
	end

	wall:SetAttribute("CollapseState", "falling")
	local layers, all_chunks = build_chunks(wall)
	-- disable the original wall before notifying pathfinding so the route query sees
	-- the same open geometry described by the structural-change event.
	wall.Transparency = 1
	wall.CanCollide = false
	wall.CanQuery = false
	wall.CanTouch = false

	world_changed_event:Fire(
		string.format(
			"%s collapsed - %d dummies are recalculating",
			string.lower(wall.Name),
			current_agent_count()
		),
		"collapse",
		-- true tells the agent controller to clear stale memory and compute new paths.
		true
	)

	for layer_index = 1, 3 do
		release_layer(wall, layers[layer_index], layer_index)
		task.wait(0.09)
	end

	local collapsed_name = string.lower(wall.Name)
	wall:Destroy()
	debris_folder:SetAttribute("LastCollapsedChunkCount", #all_chunks)
	local collapsed_wall_count = debris_folder:GetAttribute("CollapsedWalls") or 0
	debris_folder:SetAttribute("CollapsedWalls", collapsed_wall_count + 1)
	task.delay(chunk_cleanup_delay + 1.4, function()
		world_changed_event:Fire(
			string.format("%s debris cleared - the new opening is usable", collapsed_name),
			"shared",
			true
		)
	end)
end

-- selection happens once so every wall has a stable collapse order that can also be
-- inspected through attributes while the staggered sequence is running.
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

task.wait(first_collapse_delay)
for index, wall in selected_walls do
	if wall.Parent then
		collapse_wall(wall)
	end
	if index < #selected_walls then
		-- random spacing avoids a predictable cadence and guarantees only one wall is
		-- performing its warning and chunk release sequence at a time.
		task.wait(random:NextNumber(minimum_collapse_interval, maximum_collapse_interval))
	end
end

print(string.format(
	"[maze collapse] completed %d of %d selected structural collapses",
	debris_folder:GetAttribute("CollapsedWalls") or 0,
	#selected_walls
))
