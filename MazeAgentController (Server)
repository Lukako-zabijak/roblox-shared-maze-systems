-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.
--!strict

local pfs = game:GetService("PathfindingService")
local ps = game:GetService("PhysicsService")
local rs = game:GetService("ReplicatedStorage")
local ss = game:GetService("ServerStorage")

local existing_world_changed_event = ss:FindFirstChild("maze_world_changed")
if existing_world_changed_event and not existing_world_changed_event:IsA("BindableEvent") then
	error("[maze agents] serverstorage.maze_world_changed must be a bindableevent")
end
local world_changed_event: BindableEvent
if existing_world_changed_event then
	world_changed_event = existing_world_changed_event :: BindableEvent
else
	world_changed_event = Instance.new("BindableEvent")
	world_changed_event.Name = "maze_world_changed"
	world_changed_event.Parent = ss
end

local existing_knowledge_event = rs:FindFirstChild("maze_knowledge_event")
if existing_knowledge_event and not existing_knowledge_event:IsA("RemoteEvent") then
	error("[maze agents] replicatedstorage.maze_knowledge_event must be a remoteevent")
end
local knowledge_event: RemoteEvent
if existing_knowledge_event then
	knowledge_event = existing_knowledge_event :: RemoteEvent
else
	knowledge_event = Instance.new("RemoteEvent")
	knowledge_event.Name = "maze_knowledge_event"
	knowledge_event.Parent = rs
end

local agents_folder = workspace:WaitForChild("MazeAgents")
local maze = workspace:WaitForChild("Maze")
local goal = maze:WaitForChild("GoalPad") :: BasePart
local maze_floor = maze:WaitForChild("MazeFloor") :: BasePart
local marker_ground_y = maze_floor.Position.Y + maze_floor.Size.Y * 0.5 + 0.07

local agent_collision_group = "MazeAgents"
local navigation_decor_collision_group = "MazeNavigationDecor"
local repath_delay = 0.05
local path_failure_delay = 0.35
local waypoint_timeout = 3
local stuck_timeout = 1.1
local scan_interval = 0.16
local scan_distance = 14
local probe_dot_spacing = 2.2
local probe_dot_count = 6
local minimum_spawn_spacing = 32
local far_side_agent_count = 4
local obstacle_lookahead = 5.5
local body_query_size = Vector3.new(2.2, 4.5, 2.2)
local body_query_offset = Vector3.new(0, -0.45, 0)
local cruise_speed = 13
local corner_speed = 10.5
local straight_reach_radius = 1.35
local corner_reach_radius = 0.8
local scan_angles = {-72, -48, -24, 0, 24, 48, 72}
local correct_color = Color3.fromRGB(55, 255, 120)
local wrong_color = Color3.fromRGB(255, 62, 72)
local shared_color = Color3.fromRGB(53, 217, 255)
local memory_cell_size = 12
local memory_direction_count = 16
local memory_lifetime = 30
local knowledge_broadcast_interval = 4.2

type memory_observation = {
	status: string,
	updated_at: number,
}

type memory_entry = {
	observations: {[string]: memory_observation},
	status: string,
	updated_at: number,
	source: string,
}

type known_memory_entry = {
	status: string,
	source: string,
	updated_at: number,
	version: number,
}

type communication_message = {
	version: number,
	key: string,
	status: string,
	source_name: string,
	expected_receivers: number,
	acknowledged_receivers: number,
	ui_sent: boolean,
}

type agent_state = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	markers: {{BasePart}},
	raycast_params: RaycastParams,
	overlap_params: OverlapParams,
	active_path: Path?,
	blocked_connection: RBXScriptConnection?,
	waypoints: {PathWaypoint},
	waypoint_index: number,
	route_version: number,
	needs_repath: boolean,
	last_scan: number,
	scan_target: Vector3,
	avoidance_until: number,
	next_obstacle_repath: number,
	shared_flash_started: number,
	last_received_version: number,
	arrived: boolean,
	knowledge_inbox: {communication_message},
	known_memory: {[string]: known_memory_entry},
	received_message_count: number,
}

local states: {agent_state} = {}
local shared_memory: {[string]: memory_entry} = {}
local shared_memory_version = 0
local next_knowledge_broadcast_at = 0
local published_message_count = 0
local acknowledged_message_count = 0

local function configure_collision_group()
	pcall(function()
		ps:RegisterCollisionGroup(agent_collision_group)
	end)
	pcall(function()
		ps:RegisterCollisionGroup(navigation_decor_collision_group)
	end)
	ps:CollisionGroupSetCollidable(agent_collision_group, agent_collision_group, false)
	ps:CollisionGroupSetCollidable(agent_collision_group, navigation_decor_collision_group, false)
end

local function configure_navigation_decor()
	local floor_top = maze_floor.Position.Y + maze_floor.Size.Y * 0.5
	local half_floor = maze_floor.Size * 0.5
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= maze_floor and not descendant:IsDescendantOf(agents_folder) then
			local local_position = maze_floor.CFrame:PointToObjectSpace(descendant.Position)
			local bottom = descendant.Position.Y - descendant.Size.Y * 0.5
			local top = descendant.Position.Y + descendant.Size.Y * 0.5
			local is_inside_maze = math.abs(local_position.X) <= half_floor.X and math.abs(local_position.Z) <= half_floor.Z
			local is_thin_overlay = descendant.Size.Y <= 2 and descendant.Size.X <= 16 and descendant.Size.Z <= 16
			local is_on_floor = bottom <= floor_top + 0.2 and top <= floor_top + 2.1
			if is_inside_maze and is_thin_overlay and is_on_floor then
				descendant.CollisionGroup = navigation_decor_collision_group
				descendant:SetAttribute("MazeNavigationDecor", true)
			end
		end
	end
end

local function grid_key(x_index: number, z_index: number): string
	return string.format("%d:%d", x_index, z_index)
end

local function collect_reachable_spawn_points(): {Vector3}
	local walls = {}
	local cell_size = nil
	local min_x = math.huge
	local max_x = -math.huge
	local min_z = math.huge
	local max_z = -math.huge

	for _, child in maze:GetChildren() do
		if child:IsA("BasePart") and string.find(child.Name, "Wall_", 1, true) == 1 then
			table.insert(walls, child)
			cell_size = cell_size or math.max(child.Size.X, child.Size.Z)
			min_x = math.min(min_x, child.Position.X)
			max_x = math.max(max_x, child.Position.X)
			min_z = math.min(min_z, child.Position.Z)
			max_z = math.max(max_z, child.Position.Z)
		end
	end

	if not cell_size or #walls == 0 then
		return {}
	end

	local x_count = math.round((max_x - min_x) / cell_size)
	local z_count = math.round((max_z - min_z) / cell_size)
	local blocked = {}
	for _, wall in walls do
		local x_index = math.round((wall.Position.X - min_x) / cell_size)
		local z_index = math.round((wall.Position.Z - min_z) / cell_size)
		blocked[grid_key(x_index, z_index)] = true
	end

	local goal_x = math.round((goal.Position.X - min_x) / cell_size)
	local goal_z = math.round((goal.Position.Z - min_z) / cell_size)
	local queue = {{goal_x, goal_z}}
	local reachable = {[grid_key(goal_x, goal_z)] = true}
	local queue_index = 1

	while queue_index <= #queue do
		local cell = queue[queue_index]
		queue_index += 1
		local x_index = cell[1]
		local z_index = cell[2]
		for _, offset in {{1, 0}, {-1, 0}, {0, 1}, {0, -1}} do
			local next_x = x_index + offset[1]
			local next_z = z_index + offset[2]
			local key = grid_key(next_x, next_z)
			if next_x >= 0 and next_x <= x_count and next_z >= 0 and next_z <= z_count
				and not blocked[key] and not reachable[key] then
				reachable[key] = true
				table.insert(queue, {next_x, next_z})
			end
		end
	end

	local floor_top = maze_floor.Position.Y + maze_floor.Size.Y * 0.5
	local points = {}
	for x_index = 0, x_count do
		for z_index = 0, z_count do
			local key = grid_key(x_index, z_index)
			if reachable[key] and not blocked[key] then
				local point = Vector3.new(min_x + x_index * cell_size, floor_top + 3, min_z + z_index * cell_size)
				local goal_difference = point - goal.Position
				if Vector2.new(goal_difference.X, goal_difference.Z).Magnitude >= 24 then
					table.insert(points, point)
				end
			end
		end
	end
	return points
end

local function randomize_agent_spawns(models: {Model})
	local random = Random.new()
	local points = collect_reachable_spawn_points()
	if #points < #models then
		warn(string.format("[maze agents] only %d reachable random spawn cells were found", #points))
		return
	end

	for index = #points, 2, -1 do
		local swap_index = random:NextInteger(1, index)
		points[index], points[swap_index] = points[swap_index], points[index]
	end

	local maximum_goal_distance = 0
	for _, point in points do
		local difference = point - goal.Position
		maximum_goal_distance = math.max(maximum_goal_distance, Vector2.new(difference.X, difference.Z).Magnitude)
	end
	local far_side_threshold = maximum_goal_distance * 0.76
	local selected_points = {}
	local function try_select(point: Vector3): boolean
		local is_spaced = true
		for _, selected in selected_points do
			local difference = point - selected
			if Vector2.new(difference.X, difference.Z).Magnitude < minimum_spawn_spacing then
				is_spaced = false
				break
			end
		end
		if is_spaced then
			table.insert(selected_points, point)
			return true
		end
		return false
	end

	local far_side_target = math.min(far_side_agent_count, #models)
	for _, point in points do
		local difference = point - goal.Position
		local goal_distance = Vector2.new(difference.X, difference.Z).Magnitude
		if goal_distance >= far_side_threshold then
			try_select(point)
			if #selected_points >= far_side_target then
				break
			end
		end
	end

	for _, point in points do
		if #selected_points >= #models then
			break
		end
		if not table.find(selected_points, point) then
			try_select(point)
		end
	end

	if #selected_points < #models then
		warn(string.format("[maze agents] spacing fallback: selected %d of %d agents", #selected_points, #models))
		for _, point in points do
			if #selected_points >= #models then
				break
			end
			if not table.find(selected_points, point) then
				table.insert(selected_points, point)
			end
		end
	end

	for index, model in models do
		local base_position = selected_points[index]
		local jitter = Vector3.new(random:NextNumber(-0.7, 0.7), 0, random:NextNumber(-0.7, 0.7))
		local yaw = math.rad(random:NextInteger(0, 3) * 90)
		local spawn_position = base_position + jitter
		model:PivotTo(CFrame.new(spawn_position) * CFrame.Angles(0, yaw, 0))
		model:SetAttribute("SpawnCellX", base_position.X)
		model:SetAttribute("SpawnCellZ", base_position.Z)
		local goal_difference = base_position - goal.Position
		model:SetAttribute("SpawnGoalDistance", Vector2.new(goal_difference.X, goal_difference.Z).Magnitude)
	end
end

local function disconnect_route(state: agent_state)
	if state.blocked_connection then
		state.blocked_connection:Disconnect()
		state.blocked_connection = nil
	end
	state.active_path = nil
	state.waypoints = {}
	state.waypoint_index = 0
end

local function create_markers(model: Model): {{BasePart}}
	local existing = model:FindFirstChild("PathScanMarkers")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "PathScanMarkers"
	folder.Parent = model

	local markers = table.create(#scan_angles)
	for direction_index = 1, #scan_angles do
		local direction_folder = Instance.new("Folder")
		direction_folder.Name = string.format("Direction_%02d", direction_index)
		direction_folder.Parent = folder

		local line = table.create(probe_dot_count)
		for dot_index = 1, probe_dot_count do
			local marker = Instance.new("Part")
			marker.Name = string.format("Dot_%02d", dot_index)
			marker.Shape = Enum.PartType.Cylinder
			marker.Size = Vector3.new(0.1, 0.58, 0.58)
			marker.Anchored = true
			marker.CanCollide = false
			marker.CanQuery = false
			marker.CanTouch = false
			marker.CastShadow = false
			marker.Material = Enum.Material.Neon
			marker.Color = wrong_color
			marker.Transparency = 1
			marker.Parent = direction_folder
			line[dot_index] = marker
		end
		markers[direction_index] = line
	end
	return markers
end

local function create_navigation_collider(model: Model, root: BasePart): BasePart
	local existing = model:FindFirstChild("NavigationCollider")
	if existing then
		existing:Destroy()
	end

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
	local pathfinding_modifier = Instance.new("PathfindingModifier")
	pathfinding_modifier.Name = "NavigationPassThrough"
	pathfinding_modifier.PassThrough = true
	pathfinding_modifier.Parent = collider

	local weld = Instance.new("WeldConstraint")
	weld.Name = "NavigationColliderWeld"
	weld.Part0 = root
	weld.Part1 = collider
	weld.Parent = collider
	return collider
end

local function configure_agent(model: Model): agent_state?
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
	humanoid.WalkSpeed = cruise_speed
	humanoid.AutoRotate = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	local collider = create_navigation_collider(model, root)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant ~= collider then
				descendant.CanCollide = false
			end
			descendant.CollisionGroup = agent_collision_group
			if not descendant.Anchored then
				pcall(function()
					descendant:SetNetworkOwner(nil)
				end)
			end
		end
	end

	local raycast_params = RaycastParams.new()
	raycast_params.FilterType = Enum.RaycastFilterType.Exclude
	raycast_params.FilterDescendantsInstances = {agents_folder}
	raycast_params.RespectCanCollide = true
	raycast_params.CollisionGroup = agent_collision_group

	local overlap_params = OverlapParams.new()
	overlap_params.FilterType = Enum.RaycastFilterType.Exclude
	overlap_params.FilterDescendantsInstances = {agents_folder}
	overlap_params.RespectCanCollide = true
	overlap_params.CollisionGroup = agent_collision_group
	overlap_params.MaxParts = 8

	return {
		model = model,
		humanoid = humanoid,
		root = root,
		markers = create_markers(model),
		raycast_params = raycast_params,
		overlap_params = overlap_params,
		active_path = nil,
		blocked_connection = nil,
		waypoints = {},
		waypoint_index = 0,
		route_version = 0,
		needs_repath = false,
		last_scan = 0,
		scan_target = goal.Position,
		avoidance_until = 0,
		next_obstacle_repath = 0,
		shared_flash_started = -math.huge,
		last_received_version = 0,
		arrived = false,
		knowledge_inbox = {},
		known_memory = {},
		received_message_count = 0,
	}
end

local function flat_unit(vector: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude > 0.01 then
		return flat.Unit
	end
	local fallback_flat = Vector3.new(fallback.X, 0, fallback.Z)
	if fallback_flat.Magnitude > 0.01 then
		return fallback_flat.Unit
	end
	return Vector3.new(0, 0, -1)
end

local function planar_distance(left: Vector3, right: Vector3): number
	local difference = left - right
	return Vector2.new(difference.X, difference.Z).Magnitude
end

local function rotate_flat(vector: Vector3, angle_degrees: number): Vector3
	local angle = math.rad(angle_degrees)
	local cosine = math.cos(angle)
	local sine = math.sin(angle)
	return Vector3.new(
		vector.X * cosine - vector.Z * sine,
		0,
		vector.X * sine + vector.Z * cosine
	)
end

local function memory_key(position: Vector3, direction: Vector3): string
	local local_position = maze_floor.CFrame:PointToObjectSpace(position)
	local x_index = math.round(local_position.X / memory_cell_size)
	local z_index = math.round(local_position.Z / memory_cell_size)
	local angle = math.atan2(direction.Z, direction.X)
	local direction_step = math.pi * 2 / memory_direction_count
	local direction_index = math.round(angle / direction_step)
	return string.format("%d:%d:%d", x_index, z_index, direction_index)
end

local function summarize_memory(entry: memory_entry): string
	local blocked_count = 0
	local recommended_count = 0
	local open_count = 0
	for _, observation in entry.observations do
		if observation.status == "blocked" then
			blocked_count += 1
		elseif observation.status == "recommended" then
			recommended_count += 1
		else
			open_count += 1
		end
	end
	if blocked_count >= math.max(1, recommended_count + open_count) then
		return "blocked"
	end
	if recommended_count > 0 then
		return "recommended"
	end
	return "open"
end

local function observe_memory(state: agent_state, direction: Vector3, status: string): (string?, string?)
	local now = os.clock()
	local key = memory_key(state.root.Position, direction)
	local entry = shared_memory[key]
	if entry and now - entry.updated_at > memory_lifetime then
		shared_memory[key] = nil
		entry = nil
	end
	if not entry then
		entry = {
			observations = {},
			status = "unknown",
			updated_at = now,
			source = state.model.Name,
		}
		shared_memory[key] = entry
	end

	local previous_status = entry.status
	entry.observations[state.model.Name] = {
		status = status,
		updated_at = now,
	}
	entry.status = summarize_memory(entry)
	entry.updated_at = now
	entry.source = state.model.Name
	state.known_memory[key] = {
		status = entry.status,
		source = state.model.Name,
		updated_at = now,
		version = state.last_received_version,
	}

	if entry.status ~= previous_status and (entry.status == "blocked" or entry.status == "recommended") then
		return entry.status, key
	end
	return nil, nil
end

local function read_memory(state: agent_state, direction: Vector3): (string?, string?)
	local key = memory_key(state.root.Position, direction)
	local entry = state.known_memory[key]
	if not entry then
		return nil, nil
	end
	if os.clock() - entry.updated_at > memory_lifetime then
		state.known_memory[key] = nil
		return nil, nil
	end
	return entry.status, entry.source
end

local function finalize_message(message: communication_message)
	if message.ui_sent
		or message.expected_receivers <= 0
		or message.acknowledged_receivers < message.expected_receivers then
		return
	end

	message.ui_sent = true
	acknowledged_message_count += 1
	agents_folder:SetAttribute("KnowledgeMessagesAcknowledged", acknowledged_message_count)
	local discovery = if message.status == "blocked" then "a blocked route" else "a better route"
	knowledge_event:FireAllClients({
		message = string.format(
			"%s shared %s - %d active dummies received it",
			string.lower(message.source_name),
			discovery,
			message.expected_receivers
		),
		kind = message.status,
		version = message.version,
	})
end

local function discard_knowledge_inbox(state: agent_state)
	for _, message in state.knowledge_inbox do
		message.expected_receivers = math.max(0, message.expected_receivers - 1)
		finalize_message(message)
	end
	table.clear(state.knowledge_inbox)
end

local function drain_knowledge_inbox(state: agent_state)
	if state.arrived then
		discard_knowledge_inbox(state)
		return
	end

	local now = os.clock()
	while #state.knowledge_inbox > 0 do
		local message = table.remove(state.knowledge_inbox, 1)
		state.known_memory[message.key] = {
			status = message.status,
			source = message.source_name,
			updated_at = now,
			version = message.version,
		}
		state.last_received_version = message.version
		state.shared_flash_started = now
		state.received_message_count += 1
		state.model:SetAttribute("SharedMemoryVersion", message.version)
		state.model:SetAttribute("LastKnowledgeSource", message.source_name)
		state.model:SetAttribute("ReceivedKnowledgeMessages", state.received_message_count)
		state.model:SetAttribute("CommunicationState", "online")
		message.acknowledged_receivers += 1
		finalize_message(message)
	end
end

local function share_discovery(source_state: agent_state, status: string, key: string)
	if source_state.arrived then
		return
	end

	local now = os.clock()
	if now < next_knowledge_broadcast_at then
		return
	end

	local receivers: {agent_state} = {}
	for _, receiver in states do
		if receiver ~= source_state
			and not receiver.arrived
			and receiver.model.Parent
			and receiver.humanoid.Health > 0 then
			table.insert(receivers, receiver)
		end
	end
	if #receivers == 0 then
		return
	end

	next_knowledge_broadcast_at = now + knowledge_broadcast_interval
	shared_memory_version += 1
	published_message_count += 1
	local message: communication_message = {
		version = shared_memory_version,
		key = key,
		status = status,
		source_name = source_state.model.Name,
		expected_receivers = #receivers,
		acknowledged_receivers = 0,
		ui_sent = false,
	}

	for _, receiver in receivers do
		table.insert(receiver.knowledge_inbox, message)
		receiver.model:SetAttribute("CommunicationState", "pending")
	end

	source_state.model:SetAttribute("KnowledgeSharedVersion", shared_memory_version)
	agents_folder:SetAttribute("KnowledgeMessagesPublished", published_message_count)
end

local function handle_world_change(message: unknown, kind: unknown, should_repath: unknown)
	if typeof(message) ~= "string" or typeof(kind) ~= "string" or #message > 140 then
		return
	end

	local active_states: {agent_state} = {}
	for _, state in states do
		if not state.arrived and state.model.Parent and state.humanoid.Health > 0 then
			table.insert(active_states, state)
		end
	end
	if #active_states == 0 then
		return
	end

	if should_repath == true then
		table.clear(shared_memory)
		shared_memory_version += 1
		local now = os.clock()
		for _, state in active_states do
			table.clear(state.known_memory)
			state.needs_repath = true
			state.shared_flash_started = now
			state.last_received_version = shared_memory_version
			state.model:SetAttribute("SharedMemoryVersion", shared_memory_version)
			state.model:SetAttribute("LastKnowledgeSource", "structural_change")
		end
	end

	knowledge_event:FireAllClients({
		message = message,
		kind = kind,
		version = shared_memory_version,
	})
end

world_changed_event.Event:Connect(handle_world_change)

local function find_body_overlap(state: agent_state): BasePart?
	local query_cframe = CFrame.new(state.root.Position + body_query_offset)
	for _, part in workspace:GetPartBoundsInBox(query_cframe, body_query_size, state.overlap_params) do
		if part.CanCollide then
			return part
		end
	end
	return nil
end

local function find_forward_obstacle(state: agent_state, target: Vector3): (Instance?, Vector3?, Vector3?)
	local difference = target - state.root.Position
	local flat = Vector3.new(difference.X, 0, difference.Z)
	if flat.Magnitude <= 0.1 then
		return nil, nil, nil
	end
	local cast = flat.Unit * math.min(obstacle_lookahead, flat.Magnitude)
	local closest_result: RaycastResult? = nil
	for _, height_offset in {-2.2, -0.45, 1.3} do
		local origin = state.root.Position + Vector3.new(0, height_offset, 0)
		local result = workspace:Raycast(origin, cast, state.raycast_params)
		if result and (not closest_result or result.Distance < closest_result.Distance) then
			closest_result = result
		end
	end
	if closest_result then
		return closest_result.Instance, closest_result.Normal, closest_result.Position
	end
	return nil, nil, nil
end

local function choose_avoidance_target(state: agent_state, obstacle_position: Vector3, surface_normal: Vector3?): Vector3
	local desired = flat_unit(state.scan_target - state.root.Position, state.root.CFrame.LookVector)
	local away_vector = state.root.Position - obstacle_position
	local away = flat_unit(away_vector, -desired)
	if surface_normal then
		local flat_normal = Vector3.new(surface_normal.X, 0, surface_normal.Z)
		if flat_normal.Magnitude > 0.1 then
			away = flat_normal.Unit
		end
	end
	local tangent = Vector3.new(-away.Z, 0, away.X)
	if tangent:Dot(desired) < 0 then
		tangent = -tangent
	end
	local avoidance_direction = flat_unit(tangent * 0.85 + away * 0.55, away)
	return state.root.Position + avoidance_direction * 4
end

local function monitor_obstacles(state: agent_state): boolean
	local obstacle: Instance? = find_body_overlap(state)
	local obstacle_position: Vector3? = if obstacle and obstacle:IsA("BasePart") then obstacle.Position else nil
	local surface_normal: Vector3? = nil
	if not obstacle then
		obstacle, surface_normal, obstacle_position = find_forward_obstacle(state, state.scan_target)
	end
	if not obstacle then
		state.model:SetAttribute("AvoidingObstacle", false)
		return false
	end

	local now = os.clock()
	local avoidance_target = choose_avoidance_target(state, obstacle_position or state.root.Position, surface_normal)
	state.scan_target = avoidance_target
	state.avoidance_until = now + 0.4
	state.model:SetAttribute("AvoidingObstacle", true)
	state.model:SetAttribute("ObstacleName", obstacle.Name)
	state.model:SetAttribute("ObstacleClass", obstacle.ClassName)
	state.model:SetAttribute("PathState", "avoiding_obstacle")
	state.humanoid.WalkSpeed = cruise_speed
	state.humanoid:MoveTo(avoidance_target)
	if now >= state.next_obstacle_repath then
		state.needs_repath = true
		state.next_obstacle_repath = now + 0.45
	end
	return true
end

local function probe_clearance(state: agent_state, direction: Vector3): (boolean, number)
	local origin = state.root.Position + Vector3.new(0, 1.25, 0)
	local side = Vector3.new(-direction.Z, 0, direction.X) * 0.8
	local cast = direction * scan_distance
	local minimum_clearance = scan_distance

	for _, offset in {Vector3.zero, side, -side} do
		local result = workspace:Raycast(origin + offset, cast, state.raycast_params)
		if result then
			minimum_clearance = math.min(minimum_clearance, result.Distance)
		end
	end

	return minimum_clearance >= probe_dot_spacing * 1.8, minimum_clearance
end

local function update_scan(state: agent_state, next_position: Vector3, force: boolean?)
	if state.arrived then
		return
	end
	local now = os.clock()
	if not force and now - state.last_scan < scan_interval then
		return
	end
	state.last_scan = now

	local desired = flat_unit(next_position - state.root.Position, state.root.CFrame.LookVector)
	local forward = flat_unit(state.root.CFrame.LookVector, desired)
	local probes = table.create(#scan_angles)
	local best_index = nil
	local best_score = -math.huge

	for index, angle in scan_angles do
		local direction = rotate_flat(forward, angle)
		local is_locally_open, clearance = probe_clearance(state, direction)
		local memory_status, memory_source = read_memory(state, direction)
		local is_open = is_locally_open and memory_status ~= "blocked"
		local score = direction:Dot(desired) * 10 + clearance * 0.08
		if memory_status == "recommended" then
			score += 3.5
		elseif memory_status == "blocked" then
			score -= 30
		end
		probes[index] = {
			direction = direction,
			is_open = is_open,
			is_locally_open = is_locally_open,
			clearance = clearance,
			score = score,
			memory_status = memory_status,
			memory_source = memory_source,
		}
		if is_open and score > best_score then
			best_score = score
			best_index = index
		end
	end

	local discovered_status: string? = nil
	local discovered_key: string? = nil
	for direction_index, probe in probes do
		local observation = if not probe.is_locally_open
			then "blocked"
			elseif direction_index == best_index
			then "recommended"
			else "open"
		local changed_status, changed_key = observe_memory(state, probe.direction, observation)
		if changed_status and changed_key then
			discovered_status = changed_status
			discovered_key = changed_key
		end
	end
	if discovered_status and discovered_key then
		share_discovery(state, discovered_status, discovered_key)
	end

	for direction_index, probe in probes do
		local is_correct = direction_index == best_index
		local color = if is_correct then correct_color else wrong_color
		local line = state.markers[direction_index]
		for dot_index, marker in line do
			local distance = dot_index * probe_dot_spacing
			local candidate = state.root.Position + probe.direction * distance
			local is_visible = distance <= probe.clearance + 0.15
			local target_transparency = if not is_visible then 1 elseif is_correct then 0.06 else 0.16
			local diameter = if is_correct then 0.68 else 0.58
			local shared_elapsed = now - state.shared_flash_started
			local pulse_time = (dot_index - 1) * 0.075
			local is_shared_pulse = shared_elapsed >= pulse_time and shared_elapsed <= pulse_time + 0.18
			local display_color = if is_shared_pulse then shared_color else color
			marker.Color = marker.Color:Lerp(display_color, 0.62)
			marker.Transparency += (target_transparency - marker.Transparency) * 0.62
			marker.Size = marker.Size:Lerp(Vector3.new(0.1, diameter, diameter), 0.62)
			marker.CFrame = CFrame.new(candidate.X, marker_ground_y, candidate.Z) * CFrame.Angles(0, 0, math.rad(90))
		end
	end

	state.model:SetAttribute("OpeningsScanned", #scan_angles)
	state.model:SetAttribute("CorrectProbe", best_index or 0)
end

local function compute_route(state: agent_state): boolean
	disconnect_route(state)
	state.needs_repath = false
	state.route_version += 1
	state.model:SetAttribute("PathState", "computing")
	state.model:SetAttribute("RouteVersion", state.route_version)

	local path = pfs:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = 2.5,
	})

	local computed, error_message = pcall(function()
		path:ComputeAsync(state.root.Position, goal.Position)
	end)
	if not computed then
		state.model:SetAttribute("PathState", "compute_error")
		state.model:SetAttribute("PathError", tostring(error_message))
		return false
	end
	if path.Status ~= Enum.PathStatus.Success then
		state.model:SetAttribute("PathState", "no_route")
		state.model:SetAttribute("PathError", tostring(path.Status))
		return false
	end

	local waypoints = path:GetWaypoints()
	if #waypoints < 2 then
		state.model:SetAttribute("PathState", "already_arrived")
		return (state.root.Position - goal.Position).Magnitude <= 5
	end

	state.active_path = path
	state.waypoints = waypoints
	state.waypoint_index = 2
	state.model:SetAttribute("PathState", "following")
	state.model:SetAttribute("PathError", nil)
	state.model:SetAttribute("WaypointCount", #waypoints)
	state.blocked_connection = path.Blocked:Connect(function(blocked_index)
		if blocked_index >= state.waypoint_index then
			local current_waypoint = state.waypoints[state.waypoint_index]
			if current_waypoint then
				local obstacle = find_forward_obstacle(state, current_waypoint.Position)
				if obstacle then
					state.needs_repath = true
				end
			end
		end
	end)
	state.scan_target = waypoints[2].Position
	return true
end

local function waypoint_turn_angle(waypoints: {PathWaypoint}, index: number): number
	local previous = waypoints[index - 1]
	local current = waypoints[index]
	local following = waypoints[index + 1]
	if not previous or not current or not following then
		return 0
	end
	local incoming = flat_unit(current.Position - previous.Position, Vector3.new(0, 0, -1))
	local outgoing = flat_unit(following.Position - current.Position, incoming)
	return math.deg(math.acos(math.clamp(incoming:Dot(outgoing), -1, 1)))
end

local function move_to_waypoint(state: agent_state, waypoint: PathWaypoint, reach_radius: number, is_corner: boolean): boolean
	state.scan_target = waypoint.Position
	state.humanoid.WalkSpeed = if is_corner then corner_speed else cruise_speed
	if waypoint.Action == Enum.PathWaypointAction.Jump then
		state.humanoid.Jump = true
	end

	local started_at = os.clock()
	local last_progress_at = started_at
	local last_move_command = started_at
	if started_at >= state.avoidance_until then
		state.humanoid:MoveTo(waypoint.Position)
	end
	local best_distance = planar_distance(state.root.Position, waypoint.Position)

	while state.model.Parent and state.humanoid.Health > 0 do
		local now = os.clock()
		local distance = planar_distance(state.root.Position, waypoint.Position)
		if distance <= reach_radius then
			state.humanoid.WalkSpeed = cruise_speed
			return true
		end
		if state.needs_repath then
			state.humanoid.WalkSpeed = cruise_speed
			return false
		end
		if distance < best_distance - 0.2 then
			best_distance = distance
			last_progress_at = now
		end
		if now >= state.avoidance_until and now - last_move_command >= 0.45 then
			state.humanoid:MoveTo(waypoint.Position)
			last_move_command = now
		end
		if now >= state.avoidance_until and now - last_progress_at >= stuck_timeout then
			state.model:SetAttribute("PathState", "recovering")
			state.humanoid.WalkSpeed = cruise_speed
			state.needs_repath = true
			return false
		end
		if now - started_at >= waypoint_timeout then
			state.humanoid.WalkSpeed = cruise_speed
			state.needs_repath = true
			return false
		end
		task.wait(0.08)
	end
	state.humanoid.WalkSpeed = cruise_speed
	return false
end

local function mark_arrived(state: agent_state)
	if state.arrived then
		return
	end
	state.arrived = true
	discard_knowledge_inbox(state)
	state.model:SetAttribute("PathState", "arrived")
	state.model:SetAttribute("WaypointIndex", #state.waypoints)
	state.model:SetAttribute("CommunicationState", "offline")
	state.model:SetAttribute("ScannerActive", false)
	state.scan_target = goal.Position
	state.humanoid:MoveTo(state.root.Position)
	disconnect_route(state)
end

local function run_scanner(state: agent_state)
	while state.model.Parent and state.humanoid.Health > 0 and not state.arrived do
		drain_knowledge_inbox(state)
		monitor_obstacles(state)
		update_scan(state, state.scan_target, true)
		task.wait(scan_interval)
	end
	discard_knowledge_inbox(state)
	state.model:SetAttribute("ScannerActive", false)
	for _, line in state.markers do
		for _, marker in line do
			if marker.Parent then
				marker:Destroy()
			end
		end
	end
end

local function run_agent(state: agent_state, start_delay: number)
	task.wait(start_delay)
	local failures = 0

	while state.model.Parent and state.humanoid.Health > 0 do
		if (state.root.Position - goal.Position).Magnitude <= 5 then
			mark_arrived(state)
			return
		end

		if not compute_route(state) then
			failures += 1
			state.scan_target = goal.Position
			task.wait(math.min(2.5, path_failure_delay * (1 + failures)))
			continue
		end

		failures = 0
		local route_completed = true
		for index = 2, #state.waypoints do
			state.waypoint_index = index
			state.model:SetAttribute("WaypointIndex", index)
			local turn_angle = waypoint_turn_angle(state.waypoints, index)
			local is_corner = turn_angle >= 28
			local reach_radius = if is_corner then corner_reach_radius else straight_reach_radius
			state.model:SetAttribute("TurnAngle", math.round(turn_angle))
			if not move_to_waypoint(state, state.waypoints[index], reach_radius, is_corner) then
				route_completed = false
				break
			end
		end

		if route_completed and (state.root.Position - goal.Position).Magnitude <= 5 then
			mark_arrived(state)
			return
		end

		disconnect_route(state)
		task.wait(repath_delay)
	end

	disconnect_route(state)
end

configure_collision_group()
configure_navigation_decor()

local agent_models = {}
for _, child in agents_folder:GetChildren() do
	if child:IsA("Model") then
		table.insert(agent_models, child)
	end
end
table.sort(agent_models, function(left, right)
	return left.Name < right.Name
end)
randomize_agent_spawns(agent_models)

for _, model in agent_models do
	local state = configure_agent(model)
	if state then
		table.insert(states, state)
	end
end

table.sort(states, function(left, right)
	return left.model.Name < right.model.Name
end)

for index, state in states do
	task.spawn(run_scanner, state)
	task.spawn(run_agent, state, (index - 1) * 0.1)
end

print(string.format("[maze agents] started %d advanced navigators", #states))
