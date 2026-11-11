return function()
-- Phase 3: a HitstopComponent's local timer and source must survive a validated round-trip.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local HitstopComponent = require(Shared.Combat.HitstopComponent)

local world = World.new()
local source = world:CreateEntity()
local target = world:CreateEntity()
local component = HitstopComponent.new()
target:AddComponent(component)
component:Apply(9, 4, source)
component:SetEnabled(false)

local snapshot = component:CaptureRollbackState()
local valid, reason = component:ValidateRollbackState(snapshot)
assert(valid, "Captured component state must validate: " .. tostring(reason))

component:Clear()
component:SetEnabled(true)
local commit, prepareError = component:PrepareRollbackRestore(snapshot, world)
assert(type(commit) == "function", "Restore preparation failed: " .. tostring(prepareError))
commit()
assert(component.RemainingFrames == 9, "RemainingFrames was not restored")
assert(component.Priority == 4, "Priority was not restored")
assert(component.Source == source, "Source reference was not restored")
assert(component:IsEnabled() == false, "Enabled flag was not restored")

local invalid = {
	Version = 1, Enabled = true, RemainingFrames = 0,
	Priority = 2, SourceEntityId = source.Id,
}
local invalidOk = component:ValidateRollbackState(invalid)
assert(not invalidOk, "Inactive hitstop must not retain source or priority")

local missing = {
	Version = 1, Enabled = true, RemainingFrames = 3,
	Priority = 1, SourceEntityId = "missing-source",
}
local missingCommit = component:PrepareRollbackRestore(missing, world)
assert(missingCommit == nil, "Missing source entity must be rejected")

world:Destroy()
print("HitstopComponentRollbackTest: PASS")

end
