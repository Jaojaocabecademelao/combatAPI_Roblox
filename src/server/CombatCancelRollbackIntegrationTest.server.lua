local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local CombatStateSchema = require(Shared.Combat.CombatStateSchema)
local CancelComponent = require(Shared.Combat.CancelComponent)
local CancelProfile = require(Shared.Combat.CancelProfile)

local function check(value, message)
	assert(value, message)
end

local profile = CancelProfile.new({
	Rules = {
		{ RuleId = "LightToSpecial", FromAction = "Light", ToAction = "Special",
			StartFrame = 0, EndFrame = 10, Relative = true, Repeatable = false, Priority = 3 },
	},
})
local world = World.new({ CancelProfile = profile })
Simulation.new(world)
local schema = CombatStateSchema.new()
schema:RegisterComponent(CancelComponent.RollbackKey, function()
	return CancelComponent.new(profile)
end)
local resolver = world:GetCancelResolver()
schema:RegisterStateProvider("combat.cancel-resolver.v1", resolver)
local contextProbe = { Value = 41 }
function contextProbe:CaptureRollbackState()
	return { Value = self.Value }
end
function contextProbe:ValidateRollbackState(state)
	return type(state) == "table" and type(state.Value) == "number" and state.Value % 1 == 0,
		"Probe value must be an integer"
end
function contextProbe:PrepareRollbackRestore(state, restoreWorld, context, role)
	if role == "Target" then
		assert(type(context) == "table" and type(context.TargetEntitiesById) == "table"
			and type(context.CurrentEntitiesById) == "table", "Schema must forward restore context to providers")
		local foundDistinctRoster = false
		for id, targetEntity in pairs(context.TargetEntitiesById) do
			if context.CurrentEntitiesById[id] and context.CurrentEntitiesById[id] ~= targetEntity then
				foundDistinctRoster = true
				break
			end
		end
		assert(foundDistinctRoster, "Target and current entity maps should reference distinct staged/current entities")
	end
	local value = state.Value
	return function()
		self.Value = value
		if role == "Target" and self.FailNextTargetCommit then
			self.FailNextTargetCommit = false
			error("Injected context-probe commit failure")
		end
	end
end
schema:RegisterStateProvider("test.context-probe.v1", contextProbe)

local entity = world:CreateEntity()
entity:AddComponent(CancelComponent.new(profile))
check(resolver:BeginAction(entity, "Light", 0, 20).Allowed, "BeginAction should succeed")
check(resolver:RequestCancel(entity, "Special", { Frame = 0 }).Allowed, "Initial cancel should be allowed")
local snapshot = schema:Capture(world)
local savedEntityId = entity.Id
contextProbe.Value = 999
local savedComponent = snapshot.Entities[1].Components[1].State
check(savedComponent.CancelCount == 1 and savedComponent.ConsumedRules.LightToSpecial == true,
	"Snapshot must preserve consumed cancel state")

resolver:EndAction(entity, 0)
resolver:RequestCancel(entity, "Special", { Frame = 0 })
check(#resolver:GetEvents() > 0 and #resolver:GetResults() > 0, "Mutation should create frame-local outputs")
check(resolver:ValidateRollbackState({ Version = 1, ProfileManifest = { AllowUniversalCancels = false, Rules = {} } }) == false,
	"Resolver must reject a changed profile manifest")

local restored, restoreError = schema:Restore(world, snapshot)
check(restored, "Coordinated cancel restore failed: " .. tostring(restoreError))
local restoredEntity = world:GetEntity(savedEntityId)
check(restoredEntity ~= entity, "Schema restore must rebuild entity instances")
local restoredComponent = restoredEntity:GetComponent(CancelComponent)
check(restoredComponent.CurrentAction == "Light" and restoredComponent.ActionStartFrame == 0,
	"Current action and timing must be restored")
check(restoredComponent.CancelCount == 1 and restoredComponent.ConsumedRules.LightToSpecial == true,
	"Consumed cancel rule state must be restored")
check(#resolver:GetEvents() == 0 and #resolver:GetResults() == 0,
	"Target restore must clear frame-local CancelResolver outputs for replay")
check(contextProbe.Value == 41, "State provider must restore its snapshot value")

-- Inject a failure after the cancel provider has cleared output buffers; compensation must
-- restore the exact prior output objects and preserve the live roster.
local currentEntity = world:GetEntity(savedEntityId)
resolver:RequestCancel(currentEntity, "Special", { Frame = 0 })
local priorEvents, priorResults = resolver:GetEvents(), resolver:GetResults()
check(#priorEvents > 0 and #priorResults > 0, "Pre-failure output buffers must be populated")
contextProbe.Value = 777
contextProbe.FailNextTargetCommit = true
local failed, failureDetail = schema:Restore(world, snapshot)
check(failed == false and string.find(tostring(failureDetail), "Injected context-probe commit failure", 1, true),
	"Injected provider failure must fail the coordinated restore")
check(world:GetEntity(savedEntityId) == currentEntity, "Failed restore must compensate the entity roster")
check(contextProbe.Value == 777, "Failed restore must compensate provider state")
local afterFailureEvents, afterFailureResults = resolver:GetEvents(), resolver:GetResults()
check(#afterFailureEvents == #priorEvents and #afterFailureResults == #priorResults,
	"Failed restore must preserve output buffer lengths")
for index, event in ipairs(priorEvents) do check(afterFailureEvents[index] == event, "Event buffer compensation changed object identity") end
for index, result in ipairs(priorResults) do check(afterFailureResults[index] == result, "Result buffer compensation changed object identity") end

-- The component contract must reject a snapshot when rule data changes despite stable IDs.
local changedProfile = CancelProfile.new({
	Rules = {
		{ RuleId = "LightToSpecial", FromAction = "Light", ToAction = "Special",
			StartFrame = 0, EndFrame = 11, Relative = true, Repeatable = false, Priority = 3 },
	},
})
local changedComponent = CancelComponent.new(changedProfile)
check(changedComponent:ValidateRollbackState(savedComponent) == false,
	"Stable rule IDs must not hide changed cancel-window data")
local unknownComponentField = table.clone(savedComponent)
unknownComponentField.Unexpected = true
check(restoredComponent:ValidateRollbackState(unknownComponentField) == false,
	"Unknown CancelComponent fields must be rejected")

world:Destroy()
print("CombatCancelRollbackIntegrationTest: PASS")
