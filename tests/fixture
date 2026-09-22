-- Made by LukakoZabijak (lukakozabijak) on Discord, killerox3905 on Roblox.
local testworld = Instance.new("Folder")
testworld.Name = "navigationtestfixture"
testworld.Parent = workspace
local maze = Instance.new("Folder")
maze.Name = "Maze"
maze.Parent = testworld
local floor = Instance.new("Part")
floor.Name = "MazeFloor"
floor.Size = Vector3.new(40, 1, 24)
floor.CFrame = CFrame.new(10000, -0.5, 10000)
floor.Anchored = true
floor.CanCollide = false
floor.Parent = maze
local goal = Instance.new("Part")
goal.Name = "GoalPad"
goal.Position = Vector3.new(10016, 0.25, 10000)
goal.Anchored = true
goal.CanCollide = false
goal.Parent = maze
local agents = Instance.new("Folder")
agents.Name = "MazeAgents"
agents.Parent = testworld
local owner = Instance.new("Folder")
owner.Name = "maze_collapse_debris"
owner.Parent = testworld
agents:SetAttribute("democell", 8)
local ok, result = pcall(function()
