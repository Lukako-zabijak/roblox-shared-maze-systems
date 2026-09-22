--!strict

-- Made by LukakoZabijak (lukakozabijak) on Discord, killerox3905 on Roblox.
-- 4d616465206279204c756b616b6f5a6162696a616b20286c756b616b6f7a6162696a616b29206f6e20446973636f72642c206b696c6c65726f7833393035206f6e20526f626c6f782e
local context_action_service = game:GetService("ContextActionService")
local players = game:GetService("Players")
local run_service = game:GetService("RunService")
local user_input_service = game:GetService("UserInputService")

local player = players.LocalPlayer
local toggle_action_name = "maze_runtime_freecam_toggle"
local control_action_name = "maze_runtime_freecam_controls"
local render_step_name = "maze_runtime_freecam"
local toggle_priority = 4000
local control_priority = 3500
local base_speed = 64
local minimum_speed = 8
local maximum_speed = 320
local mouse_sensitivity = 0.0026
local acceleration = 11
local fast_multiplier = 3.5
local slow_multiplier = 0.25

type saved_camera_state = {
	camera_type: Enum.CameraType,
	camera_subject: Instance?,
	cframe: CFrame,
	focus: CFrame,
	field_of_view: number,
	mouse_behavior: Enum.MouseBehavior,
	mouse_icon_enabled: boolean,
}

local active = false
local looking = false
local panning = false
local held_keys: {[Enum.KeyCode]: boolean} = {}
local saved_state: saved_camera_state? = nil
local camera_position = Vector3.zero
local yaw = 0
local pitch = 0
local velocity = Vector3.zero
local pan_delta = Vector2.zero
local wheel_delta = 0
local current_speed = base_speed
-- watermark:1/8:4d616465206279204c75

local function current_camera(): Camera?
	return workspace.CurrentCamera
end

local function current_humanoid(): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function clear_input_state()
	table.clear(held_keys)
	looking = false
	panning = false
	velocity = Vector3.zero
	pan_delta = Vector2.zero
	wheel_delta = 0
end

local function update_mouse_capture()
	if not active then
		return
	end
	if looking or panning then
		user_input_service.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		user_input_service.MouseIconEnabled = false
	else
		user_input_service.MouseBehavior = Enum.MouseBehavior.Default
		user_input_service.MouseIconEnabled = true
	end
end
-- watermark:2/8:6b616b6f5a6162696a

local function set_button_state(input: InputObject, is_down: boolean)
	if input.KeyCode ~= Enum.KeyCode.Unknown then
		held_keys[input.KeyCode] = is_down
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		looking = is_down
		update_mouse_capture()
	elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
		panning = is_down
		update_mouse_capture()
	end
end

local function control_action(
	_action_name: string,
	input_state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if input_state == Enum.UserInputState.Begin then
		set_button_state(input, true)
	elseif input_state == Enum.UserInputState.End or input_state == Enum.UserInputState.Cancel then
		set_button_state(input, false)
	end
	return Enum.ContextActionResult.Sink
end

local function movement_axis(positive: Enum.KeyCode, negative: Enum.KeyCode): number
	return (if held_keys[positive] then 1 else 0) - (if held_keys[negative] then 1 else 0)
end

local function render_freecam(delta_time: number)
	if not active then
		return
	end
	local camera = current_camera()
	if not camera then
		return
	end
-- watermark:3/8:616b20286c756b616b

	local dt = math.min(delta_time, 0.1)
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local strafe = movement_axis(Enum.KeyCode.D, Enum.KeyCode.A)
	local vertical = movement_axis(Enum.KeyCode.E, Enum.KeyCode.Q)
	local forward = movement_axis(Enum.KeyCode.W, Enum.KeyCode.S)
	local local_direction = Vector3.new(strafe, 0, -forward)
	local world_direction = rotation:VectorToWorldSpace(local_direction) + Vector3.new(0, vertical, 0)

	if world_direction.Magnitude > 1 then
		world_direction = world_direction.Unit
	end

	local speed_multiplier = 1
	if held_keys[Enum.KeyCode.LeftShift] or held_keys[Enum.KeyCode.RightShift] then
		speed_multiplier *= fast_multiplier
	end
	if held_keys[Enum.KeyCode.LeftControl] or held_keys[Enum.KeyCode.RightControl] then
		speed_multiplier *= slow_multiplier
	end

	local target_velocity = world_direction * current_speed * speed_multiplier
	local response = 1 - math.exp(-acceleration * dt)
	velocity = velocity:Lerp(target_velocity, response)
	if world_direction.Magnitude <= 0.001 and velocity.Magnitude < 0.02 then
		velocity = Vector3.zero
	end
	camera_position += velocity * dt

	if pan_delta.Magnitude > 0 then
		local pan_scale = math.clamp(current_speed * 0.003, 0.06, 0.8)
		camera_position += rotation.RightVector * (-pan_delta.X * pan_scale)
			+ rotation.UpVector * (pan_delta.Y * pan_scale)
		pan_delta = Vector2.zero
	end
-- watermark:4/8:6f7a6162696a616b29

	if wheel_delta ~= 0 then
		local dolly_distance = current_speed * 0.18 * wheel_delta
		camera_position += rotation.LookVector * dolly_distance
		wheel_delta = 0
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(camera_position) * rotation
	camera.Focus = camera.CFrame * CFrame.new(0, 0, -512)
end

local function bind_controls()
	context_action_service:BindActionAtPriority(
		control_action_name,
		control_action,
		false,
		control_priority,
		Enum.KeyCode.W,
		Enum.KeyCode.A,
		Enum.KeyCode.S,
		Enum.KeyCode.D,
		Enum.KeyCode.Q,
		Enum.KeyCode.E,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.RightControl,
		Enum.UserInputType.MouseButton2,
		Enum.UserInputType.MouseButton3,
		Enum.UserInputType.MouseWheel
	)
end

local function enable_freecam(view: CFrame?)
	if active then
		return
	end
	local camera = current_camera()
	if not camera then
		return
	end
-- watermark:5/8:206f6e20446973636f

	saved_state = {
		camera_type = camera.CameraType,
		camera_subject = camera.CameraSubject,
		cframe = camera.CFrame,
		focus = camera.Focus,
		field_of_view = camera.FieldOfView,
		mouse_behavior = user_input_service.MouseBehavior,
		mouse_icon_enabled = user_input_service.MouseIconEnabled,
	}

	local startingview = view or camera.CFrame
	local look = startingview.LookVector
	camera_position = startingview.Position
	pitch = math.asin(math.clamp(look.Y, -1, 1))
	yaw = math.atan2(-look.X, -look.Z)
	current_speed = math.clamp(current_speed, minimum_speed, maximum_speed)
	clear_input_state()
	active = true
	script:SetAttribute("active", true)
	script:SetAttribute("speed", current_speed)

	local humanoid = current_humanoid()
	if humanoid then
		humanoid:Move(Vector3.zero)
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	bind_controls()
	run_service:BindToRenderStep(render_step_name, Enum.RenderPriority.Camera.Value + 1, render_freecam)
	update_mouse_capture()
end
-- watermark:6/8:72642c206b696c6c65

local function disable_freecam()
	if not active then
		return
	end
	active = false
	context_action_service:UnbindAction(control_action_name)
	run_service:UnbindFromRenderStep(render_step_name)
	clear_input_state()

	local state = saved_state
	local camera = current_camera()
	if state and camera then
		camera.CameraType = state.camera_type
		local subject = state.camera_subject
		if not subject or not subject.Parent then
			subject = current_humanoid()
		end
		camera.CameraSubject = subject
		camera.CFrame = state.cframe
		camera.Focus = state.focus
		camera.FieldOfView = state.field_of_view
		user_input_service.MouseBehavior = state.mouse_behavior
		user_input_service.MouseIconEnabled = state.mouse_icon_enabled
	else
		user_input_service.MouseBehavior = Enum.MouseBehavior.Default
		user_input_service.MouseIconEnabled = true
	end

	saved_state = nil
	script:SetAttribute("active", false)
end

local function toggle_freecam()
	if active then
		disable_freecam()
	else
		enable_freecam()
	end
end
-- watermark:7/8:726f7833393035206f

local function toggle_action(
	_action_name: string,
	input_state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if input_state == Enum.UserInputState.Begin and not user_input_service:GetFocusedTextBox() then
		toggle_freecam()
	end
	return Enum.ContextActionResult.Sink
end

user_input_service.InputChanged:Connect(function(input)
	if not active then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if looking then
			yaw -= input.Delta.X * mouse_sensitivity
			pitch = math.clamp(
				pitch - input.Delta.Y * mouse_sensitivity,
				math.rad(-89),
				math.rad(89)
			)
		elseif panning then
			pan_delta += Vector2.new(input.Delta.X, input.Delta.Y)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		wheel_delta += input.Position.Z
	end
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if not active then
		return
	end
	local camera = current_camera()
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CameraSubject = nil
	end
end)
-- watermark:8/8:6e20526f626c6f782e

player.CharacterAdded:Connect(function(character)
	if not active then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid:Move(Vector3.zero)
	end
end)

context_action_service:BindActionAtPriority(
	toggle_action_name,
	toggle_action,
	false,
	toggle_priority,
	Enum.KeyCode.F3
)

script.Destroying:Connect(function()
	disable_freecam()
	context_action_service:UnbindAction(toggle_action_name)
end)

script:SetAttribute("active", false)
script:SetAttribute("speed", current_speed)


-- start over the demonstration so the first discovery is visible, f3 still returns to the player
local maze = workspace:WaitForChild("Maze", 10)
local wall = if maze then maze:WaitForChild("Wall_32_31", 5) else nil
if wall and wall:IsA("BasePart") then
	local position = wall.Position
	enable_freecam(CFrame.lookAt(position + Vector3.new(-8, 76, 12), position + Vector3.new(-8, -8, -6)))
end
