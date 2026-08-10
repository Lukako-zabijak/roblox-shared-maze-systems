-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.
--!strict

local rs = game:GetService("ReplicatedStorage")
local ts = game:GetService("TweenService")

local screen_gui = script.Parent :: ScreenGui
local title = screen_gui:WaitForChild("title") :: TextLabel
local legend = screen_gui:WaitForChild("legend") :: TextLabel
local notification = screen_gui:WaitForChild("notification") :: TextLabel
local knowledge_event = rs:WaitForChild("maze_knowledge_event") :: RemoteEvent

title.Text = ""
legend.Text = ""
legend.RichText = false
notification.Text = ""
notification.TextTransparency = 1

local message_queue: {{message: string, kind: string}} = {}
local queue_running = false

local function type_text(label: TextLabel, message: string, delay_per_character: number)
	label.Text = ""
	for index = 1, #message do
		if not label.Parent then
			return
		end
		label.Text = string.sub(message, 1, index)
		task.wait(delay_per_character)
	end
end

local function notification_color(kind: string): Color3
	if kind == "blocked" then
		return Color3.fromRGB(255, 82, 92)
	end
	if kind == "recommended" then
		return Color3.fromRGB(55, 255, 120)
	end
	if kind == "collapse_warning" then
		return Color3.fromRGB(255, 190, 72)
	end
	if kind == "collapse" then
		return Color3.fromRGB(255, 118, 66)
	end
	return Color3.fromRGB(53, 217, 255)
end

local function run_queue()
	if queue_running then
		return
	end
	queue_running = true
	while #message_queue > 0 and screen_gui.Parent do
		local item = table.remove(message_queue, 1)
		notification.TextColor3 = notification_color(item.kind)
		notification.TextTransparency = 0
		type_text(notification, item.message, 0.022)
		task.wait(1.8)
		local fade = ts:Create(
			notification,
			TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{TextTransparency = 1}
		)
		fade:Play()
		fade.Completed:Wait()
		notification.Text = ""
		task.wait(0.12)
	end
	queue_running = false
	if #message_queue > 0 and screen_gui.Parent then
		task.spawn(run_queue)
	end
end

local function queue_message(message: string, kind: string)
	if #message_queue >= 4 then
		table.remove(message_queue, 1)
	end
	table.insert(message_queue, {
		message = message,
		kind = kind,
	})
	if not queue_running then
		task.spawn(run_queue)
	end
end

knowledge_event.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local message = payload.message
	local kind = payload.kind
	if typeof(message) ~= "string" or typeof(kind) ~= "string" then
		return
	end
	if #message > 140 then
		return
	end
	queue_message(message, kind)
end)

task.spawn(function()
	type_text(title, "one learns. all know.", 0.045)
	task.wait(0.25)
	local plain_legend = "green = best route    red = avoid    cyan = shared info    orange = collapse warning"
	type_text(legend, plain_legend, 0.014)
	legend.RichText = true
	legend.Text = '<font color="#37ff78">green</font> = best route    <font color="#ff3e48">red</font> = avoid    <font color="#35d9ff">cyan</font> = shared info    <font color="#ffbe48">orange</font> = collapse warning'
	task.wait(0.35)
	queue_message("dummies share discoveries and structural changes in real time", "shared")
end)
