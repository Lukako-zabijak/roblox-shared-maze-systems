-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
local fixture = workspace:WaitForChild("candidatefixture",60)
if not fixture then return end
local event = fixture:WaitForChild("maze_knowledge_event",60)
if not event then return end
for attempt=1,240 do
 if not event.Parent then break end
 event:FireServer("ready")
 task.wait(0.5)
end
