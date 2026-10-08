-- Connected Discord-GitHub
-- Made by LukakoZabijak (lukakozabijak) on Discord, killerox3905 on Roblox.
local fixture = Instance.new("Model") -- isolate physical test parts away from the authored maze and its agent state
fixture.Name = "turningtestfixture" -- the owner is inspectable and removed on both success and failure
fixture.Parent = workspace -- network ownership checks need a live server physics assembly
local root = Instance.new("Part") -- a real unanchored part exercises ownership and actual constraint properties
root.Name = "HumanoidRootPart" -- this identity lets the test humanoid accept normal movement commands
root.Size = Vector3.new(2, 2, 1) -- keep the fixture small and independent from the authored navigation collider
root.CFrame = CFrame.new(10000, 50, 10000) -- no fixture can overlap the actual maze during its short synchronous test
root.Parent = fixture -- a live root is required before server network ownership can be acquired
local humanoid = Instance.new("Humanoid") -- real properties check borrowed AutoRotate restoration without stubbing the engine
humanoid.RequiresNeck = false -- the minimal isolated fixture deliberately has no authored avatar head or neck
humanoid.Parent = fixture -- keep both physical components inside the one cleanup owner
local authored = Instance.new("Attachment") -- cleanup must preserve an unrelated attachment of the same class
authored.Name = "authoredattachment" -- its identity is separate from the controllers owned turning pair
authored.Parent = root -- compare owned destruction with preservation on the same physical root
local ok, result = pcall(function() -- destroy the isolated fixture even if an assertion fails
    local count = 0 -- assertions report their actual number without claiming distinct gameplay scenarios
    local function check(condition, message) -- failure messages identify the invariant rather than swallow a broken result
        assert(condition, message) -- stop the fixture at the first failed lifecycle or target contract
        count += 1 -- successful checks remain distinguishable from skipped cases
    end -- all test decisions share one assertion owner
    local state = {rig = {model = fixture, root = root, humanoid = humanoid}} -- tests own one private controller state over real engine components
    local function pairsowned() -- duplicate setup must not create several facing owners on the same root
        local attachments, alignments = 0, 0 -- count owned names independently from the authored attachment
        for _, child in root:GetChildren() do -- inspect only this fixtures children rather than scan unrelated workspace objects
            if child.Name == "navturnattachment" then attachments += 1 end -- each active turn owner needs exactly one local frame
            if child.Name == "navturnalignment" then alignments += 1 end -- each active rig must have exactly one physical turning solver
        end -- the counts expose leaked pairs even after repeated setup
        return attachments, alignments -- both resource types are checked independently
    end -- counting is test evidence and never controller authority
    humanoid.AutoRotate = true -- verify restoring true separately from the valid false case later
    startturn(state) -- acquire the same functions extracted from the current main controller
    check(state.alignment ~= nil and state.attachment ~= nil, "owned pair missing") -- eligible server physics must produce the complete pair
    check(root:GetNetworkOwner() == nil, "root not server owned") -- the controller must verify actual server simulation authority
    check(not humanoid.AutoRotate and state.autorotate == true, "AutoRotate handoff") -- humanoid and constraint must not compete for facing
    check(state.alignment.Mode == Enum.OrientationAlignmentMode.OneAttachment and state.alignment.Attachment0 == state.attachment, "attachment mode") -- the solver must use the owned local frame and its supplied goal
    check(not state.alignment.RigidityEnabled and not state.alignment.ReactionTorqueEnabled, "unbounded or reaction torque") -- finite single assembly control is part of the turning contract
    check(state.alignment.MaxTorque >= 5000 and state.alignment.MaxTorque <= 100000 and state.alignment.MaxAngularVelocity > 0, "turn bounds") -- parameters must remain finite and within the documented design limits
    check(not state.alignment.Enabled, "queued solver active") -- setup alone must not turn a queued or observing rig
    local position, pose = root.Position, root.CFrame -- goal updates must not manually teleport or rotate the root
    drive(state, position + Vector3.new(8, 20, 0)) -- a vertical offset must not tilt horizontal navigation facing
    check(state.alignment.Enabled and state.alignment.CFrame.LookVector:Dot(Vector3.xAxis) > 0.99999, "horizontal goal") -- the goal points along the horizontal waypoint direction
    check(root.CFrame == pose, "goal update wrote root CFrame") -- the physical solver owns rotation rather than a direct transform assignment
    drive(state, position - Vector3.new(8, 0, 0)) -- a reversal represents recovery toward the reached anchor
    check(state.alignment.CFrame.LookVector:Dot(-Vector3.xAxis) > 0.99999, "recovery reversal") -- recovery must not keep the old forward orientation goal
    drive(state, position + Vector3.new(0.01, 2, 0)) -- a near zero horizontal vector must not be normalized into an unstable direction
    check(not state.alignment.Enabled, "near zero target active") -- tiny or vertical only targets disable stale torque
    drive(state, position) -- exact arrival also supplies no meaningful facing direction
    check(not state.alignment.Enabled, "zero target active") -- the goal frame must never depend on a zero Unit vector
    drive(state, nil) -- pause and retirement use the existing nil movement command path
    check(not state.alignment.Enabled, "stop retained torque") -- a stop cannot leave the previous waypoint orientation active
    startturn(state) -- repeated acquisition must release the earlier owner before creating a replacement
    local attachments, alignments = pairsowned() -- count actual resources after the replacement path
    check(attachments == 1 and alignments == 1 and state.autorotate == true, "duplicate setup or lost original rotation") -- replacement keeps the original borrowed value rather than capture the temporary false setting
    state.attachment:Destroy() -- simulate an externally removed owned frame while the rig survives
    drive(state, position + Vector3.new(0, 0, -8)) -- missing pair handling must release torque and restore normal humanoid facing
    attachments, alignments = pairsowned() -- a broken pair must not leave its surviving counterpart behind
    check(attachments == 0 and alignments == 0 and humanoid.AutoRotate, "missing attachment cleanup") -- fallback restores the original setting without retaining an incomplete solver
    humanoid.AutoRotate = false -- false is a legitimate authored setting and must not be mistaken for no saved value
    startturn(state) -- acquire with the alternate original setting
    state.alignment:Destroy() -- simulate losing the other half of the owned pair
    drive(state, position + Vector3.new(8, 0, 0)) -- losing a constraint must release its attachment and borrowed setting too
    check(state.alignment == nil and state.attachment == nil and not humanoid.AutoRotate, "false restoration or constraint removal") -- the nil sentinel must preserve an original false value
    stopturn(state) -- cleanup is allowed after the fallback already removed every owned resource
    stopturn(state) -- repeated retirement or owner removal must stay harmless
    check(authored.Parent == root, "authored attachment destroyed") -- owned cleanup cannot remove unrelated rig assets
    root.Anchored = true -- this assembly is deliberately ineligible for manual network ownership
    humanoid.AutoRotate = true -- denial must leave its original rotation setting usable
    startturn(state) -- expected denial must not abort the whole navigation controller or leak partial objects
    attachments, alignments = pairsowned() -- denied setup must create neither owned resource
    check(attachments == 0 and alignments == 0 and state.autorotate == nil and humanoid.AutoRotate, "ownership denial leaked state") -- acquisition failure precedes all constraint and humanoid changes
    root.Anchored = false -- restore eligibility before testing removal of the actual physical owner
    startturn(state) -- create one final owned pair before its model is destroyed
    fixture:Destroy() -- model removal destroys physical objects before controller cleanup may run
    stopturn(state) -- dangling Lua references must be safe to release after engine destruction
    check(state.alignment == nil and state.attachment == nil and state.autorotate == nil, "removed model retained ownership") -- teardown must leave no retained turning references
    return count -- the report counts only assertions actually reached and passed
end) -- the fixture result retains the first failed invariant if any
fixture:Destroy() -- the same owner is removed on success or any earlier assertion failure
assert(ok, result) -- expose failures after cleanup rather than leave hidden test objects in the game
return result -- isolated API checks do not claim the physics solver or full navigation loop was validated
