-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
local service = game:GetService("StudioTestService")
if service:GetTestArgs() ~= "final lifetime" then return end
assert(game.PlaceId == 113425488924507)
local template = game.ServerScriptService.candidatecontroller
for _,item in game.ServerScriptService:GetChildren() do
 if item:IsA("Script") and item ~= script then item.Enabled = false end
end
local fixture = game.ServerStorage.candidatefixture
fixture.Parent = workspace
game.Players.PlayerAdded:Connect(function(player) player.ReplicationFocus = fixture.Maze.MazeFloor end)
for _,player in game.Players:GetPlayers() do player.ReplicationFocus = fixture.Maze.MazeFloor end
local rotation = {}
local index = 0
for _,model in fixture.MazeAgents:GetChildren() do
 if model:IsA("Model") then
  index += 1
  if index <= 2 then model.Humanoid.AutoRotate = false end
  rotation[model.Name] = model.Humanoid.AutoRotate
 end
end
local results = {}
for _,kind in {"live", "detached", "destroyed"} do
 local controller = template:Clone()
 controller.Name = "lifetime controller"
 controller.Parent = game.ServerScriptService
 controller.Enabled = true
 local deadline = os.clock() + 60
 local active = 0
 repeat
  task.wait(0.1)
  active = 0
  for _,model in fixture.MazeAgents:GetChildren() do
   if not model:IsA("Model") then continue end
   local v = model.HumanoidRootPart.AssemblyLinearVelocity
   if model:GetAttribute("PathState") == "moving" and Vector2.new(v.X,v.Z).Magnitude > 1 then active += 1 end
  end
 until active >= 2 or os.clock() >= deadline
 assert(active >= 2, "two physically moving rigs are required before shutdown")
 if kind == "live" then controller.Parent = fixture
 elseif kind == "detached" then controller.Parent = nil
 else controller:Destroy() end
 task.wait(0.6)
 local proof = {moving = 0, resources = 0, unchanged = 0, stopped = 0, offline = 0, ownedchildren = #controller:GetChildren()}
 for _,item in fixture:GetDescendants() do
  if item:IsA("AlignOrientation") or item:IsA("Highlight") or item.Name == "navgoal"
   or (item:IsA("BasePart") and item.Name:match("^Dot_")) then proof.resources += 1 end
 end
 for _,model in fixture.MazeAgents:GetChildren() do
  if not model:IsA("Model") then continue end
  local v = model.HumanoidRootPart.AssemblyLinearVelocity
  if Vector2.new(v.X,v.Z).Magnitude > 0.15 then proof.moving += 1 end
  if model.Humanoid.AutoRotate == rotation[model.Name] then proof.unchanged += 1 end
  if model:GetAttribute("PathState") == "stopped" then proof.stopped += 1 end
  if model:GetAttribute("CommunicationState") == "offline" and not model:GetAttribute("ScannerActive") then proof.offline += 1 end
 end
 assert(proof.moving == 0 and proof.resources == 0 and proof.unchanged == 15, "native ownership must stop motion and remove active resources")
 if kind == "live" then assert(proof.stopped == 15 and proof.offline == 15 and proof.ownedchildren == 0, "live shutdown still publishes complete retirement") end
 if kind == "destroyed" then assert(proof.ownedchildren == 0, "destroyed owner cannot retain children") end
 results[kind] = proof
 controller:Destroy()
 task.wait(0.1)
end
fixture:Destroy()
service:EndTest({ok = true, cases = results})
