return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local CombatStateSchema = require(Shared.Combat.CombatStateSchema)
local StatusContainer = require(Shared.Combat.StatusContainer)
local Hitstun = require(Shared.Combat.Hitstun)
local Blockstun = require(Shared.Combat.Blockstun)

local function check(value, message)
	assert(value, message)
end

local world = World.new()
local simulation = Simulation.new(world)
local source = world:CreateEntity()
local target = world:CreateEntity()
local container = target:AddComponent(StatusContainer.new())
container:AddStatus(Hitstun.new({ DurationFrames = 6, Source = source }))
container:AddStatus(Blockstun.new({ DurationFrames = 4, Source = source }))
simulation:Step()
local schema = CombatStateSchema.new()
schema:RegisterComponent(StatusContainer.RollbackKey, function()
	return StatusContainer.new()
end)
local snapshot = schema:Capture(world)
local sourceId, targetId = source.Id, target.Id
local savedStatusState = snapshot.Entities[2].Components[1].State
check(savedStatusState.Statuses[1].RemainingFrames == 5,
	"Status snapshot should capture frame-accurate remaining duration")
container:ClearStatuses("TestMutation")
local restored, detail = schema:Restore(world, snapshot)
check(restored, "StatusContainer restore failed: " .. tostring(detail))
local restoredSource = world:GetEntity(sourceId)
local restoredTarget = world:GetEntity(targetId)
local restoredContainer = restoredTarget:GetComponent(StatusContainer)
local hitstun = restoredContainer:GetStatus("Hitstun")
local blockstun = restoredContainer:GetStatus("Blockstun")
check(restoredSource ~= source and hitstun and hitstun.Source == restoredSource
	and hitstun.RemainingFrames == 5 and hitstun.DurationFrames == 6,
	"Hitstun state and source reference should restore against staged entities")
check(blockstun and blockstun.Source == restoredSource and blockstun.RemainingFrames == 3,
	"Blockstun duration and source reference should restore")
check(#restoredContainer:GetEvents() == 0,
	"Restoring statuses must not emit application/removal events a second time")

local invalidSource = table.clone(savedStatusState)
invalidSource.Statuses = table.clone(savedStatusState.Statuses)
invalidSource.Statuses[1] = table.clone(savedStatusState.Statuses[1])
invalidSource.Statuses[1].SourceId = "missing-source"
check(restoredContainer:ValidateRollbackState(invalidSource, {
	EntitiesById = { [targetId] = restoredTarget },
}) == false, "Missing status source entity must be rejected")
local invalidCounter = table.clone(savedStatusState)
invalidCounter.Statuses = table.clone(savedStatusState.Statuses)
invalidCounter.Statuses[1] = table.clone(savedStatusState.Statuses[1])
invalidCounter.Statuses[1].RemainingFrames = invalidCounter.Statuses[1].DurationFrames + 1
check(restoredContainer:ValidateRollbackState(invalidCounter) == false,
	"Status remaining frames beyond its duration must be rejected")
restoredContainer:RemoveStatus(hitstun, "ReuseTest")
restoredContainer:AddStatus(hitstun)
check(hitstun.RemainingFrames == hitstun.DurationFrames,
	"Reapplying an ended status instance must reset its timer")

world:Destroy()
print("CombatStatusContainerRollbackTest: PASS")

end
