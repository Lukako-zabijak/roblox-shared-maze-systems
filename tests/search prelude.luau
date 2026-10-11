-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, YieldForever on Roblox.
local extra=0
local function check(value, text)
 assert(value,text)
 extra+=1
end
local sample=newgrid(22,22)
local job=newsearch(sample,1,484)
local oldrevision=job.revision
discover(sample,2,true)
check(job.map.cells[2]==nil and job.revision==oldrevision,"snapshot is isolated")
check(job.revision~=sample.revision,"changed knowledge makes old result stale")
local rng=Random.new(14687)
for trial=1,100 do
 local field=newgrid(12,12)
 for cell=2,143 do
  local roll=rng:NextNumber()
  if roll<0.22 then discover(field,cell,true)
  elseif roll<0.65 then discover(field,cell,false) end
 end
 local expected,cost=findroute(field,1,144)
 local sliced=newsearch(field,1,144)
 local guard=0
 while sliced.route==nil do
  local before=sliced.pops
  local spent=stepsearch(sliced,7)
  check(spent<=7 and sliced.pops-before==spent,"every heap pop uses the slice allowance")
  guard+=1
  assert(guard<1000,"sliced search must terminate")
 end
 check(sliced.cost==cost and #sliced.route==#expected,"slices keep shortest path cost and route length")
end
local expired=newsearch(newgrid(100,100),1,10000)
check(stepsearch(expired,30,os.clock()-1)==0 and expired.pops==0,"elapsed deadline defers all search work")
local map=newgrid(30,30)
local generation=1
local running=true
local democell=451
local searchcursor=0
local states={}
local adopted=0
local cancelled=0
local agents={SetAttribute=function(self,name,value) self[name]=value end}
local function cancel(state)
 state.job=nil
 cancelled+=1
end
local function adopt(state,job,now)
 check(job.revision==map.revision and state.jobgeneration==generation,"only a current result can install")
 state.eligible=false
 adopted+=1
end
for index=1,15 do
 local model={SetAttribute=function(self,name,value) self[name]=value end,GetAttribute=function(self,name) return self[name] end}
 table.insert(states,{anchor=index,eligible=true,model=model,openings={}})
end
