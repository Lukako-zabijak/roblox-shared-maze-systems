-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
local fixture = workspace:WaitForChild("candidatefixture", 30)
if not fixture then return end
local remote = fixture:WaitForChild("candidateobserver", 30)
if not remote then return end
local previous = {}
local report = {samples = 0, agents = 0, maxpairs = 0, turns = 0, minup = 1, maxdots = 0, green = false, cyan = false, red = false}
task.wait(4)
local player = game:GetService("Players").LocalPlayer
local oldcamera = player.PlayerScripts:FindFirstChild("freecam_controller")
if oldcamera then oldcamera.Enabled = false end
local oldgui = player.PlayerGui:FindFirstChild("maze_knowledge_gui")
if oldgui then oldgui.Enabled = false end
local camera = fixture:WaitForChild("candidatefreecam"):Clone()
camera.Parent = player.PlayerScripts
camera.Enabled = true
local gui = fixture:WaitForChild("candidategui"):Clone()
gui.Name = "candidate client check"
gui.Parent = player:WaitForChild("PlayerGui")
gui.controller.Enabled = true
for sample = 1, 120 do
	if not remote.Parent then break end
	local agents, pairs, dots = 0, 0, 0
	for _, model in fixture.MazeAgents:GetChildren() do
		if not model:IsA("Model") then continue end
		local root = model:FindFirstChild("HumanoidRootPart")
		if not root then continue end
		agents += 1
		report.minup = math.min(report.minup, root.CFrame.UpVector.Y)
		local direction = root.CFrame.LookVector
		if previous[model.Name] and direction:Dot(previous[model.Name]) < 0.995 then report.turns += 1 end
		previous[model.Name] = direction
	end
	for _, item in fixture:GetDescendants() do
		if item:IsA("AlignOrientation") and item.Name == "navturnalignment" then pairs += 1 end
		if not item:IsA("BasePart") or not string.match(item.Name, "^Dot_") then continue end
		dots += 1
		if item.Transparency > 0.95 then continue end
		local c = item.Color
		report.green = report.green or (c.G > 0.85 and c.R < 0.4 and c.B < 0.65)
		report.cyan = report.cyan or (c.G > 0.7 and c.B > 0.7 and c.R < 0.4)
		report.red = report.red or (c.R > 0.85 and c.G < 0.5 and c.B < 0.5)
	end
	report.samples, report.agents = sample, agents
	report.maxpairs = math.max(report.maxpairs, pairs)
	report.maxdots = math.max(report.maxdots, dots)
	report.hud = #gui.title.Text > 0 and #gui.legend.Text > 0
	report.camera = camera:GetAttribute("active") == true
	remote:FireServer(report)
	task.wait(0.5)
end
gui:Destroy()
