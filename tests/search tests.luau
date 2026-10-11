-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
local turns=0
while adopted<15 do
 searches(os.clock())
 check(agents.searchwork<=1024,"dispatch respects its global work budget")
 turns+=1
 assert(turns<10000,"all queued agents must eventually get a result")
end
check(adopted==15,"all fifteen agents get search results")
for _,state in states do check(state.model.searchslices>0,"every agent gets a slice") end
local state=states[1]
state.eligible=true
state.job=newsearch(map,state.anchor,goalcell)
state.jobgeneration=generation
discover(map,451,true)
searches(os.clock())
check(state.job~=nil or not state.eligible,"changed observations do not discard unfinished work blindly")
state.eligible=true
state.job=newsearch(map,state.anchor,goalcell)
state.jobgeneration=generation
generation+=1
searches(os.clock())
check(cancelled>=1,"replay rejects an old generation even with unchanged grid knowledge")
map=newgrid(6,3)
for cell=1,18 do discover(map,cell,false) end
local reference=newsearch(map,7,12)
while reference.route==nil do stepsearch(reference,4) end
discover(map,1,true)
check(compatible(reference),"a new wall outside the route cannot make a shorter alternative")
discover(map,reference.route[2],true)
check(not compatible(reference),"a blocked route cell rejects adoption")
map=newgrid(6,3)
for cell=1,18 do discover(map,cell,false) end
local openjob=newsearch(map,7,12)
local closedjob=newsearch(map,7,12)
closedjob.map.cells[9]={blocked=true}
while openjob.route==nil do stepsearch(openjob,2) end
while closedjob.route==nil do stepsearch(closedjob,2) end
check(openjob.cost<closedjob.cost,"the comparison measures a real closed passage detour")
check(table.find(openjob.route,9)~=nil and table.find(closedjob.route,9)==nil,"only the open route uses the passage")
check(compatible(closedjob,9),"the intended comparison cell is not mistaken for an unrelated stale observation")
print("baseline="..baseline.." additional="..extra.." dispatches="..turns)
