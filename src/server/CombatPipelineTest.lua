return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local Definition = require(Shared.Combat.CombatActionDefinition)
local ActionCatalog = require(Shared.Combat.CombatActionCatalog)
local Result = require(Shared.Combat.CombatActionResult)
local Event = require(Shared.Combat.CombatActionEvent)
local HealthComponent = require(Shared.Combat.HealthComponent)
local MotionComponent = require(Shared.Combat.MotionComponent)
local InputComponent = require(Shared.Combat.InputComponent)
local ResourceComponent = require(Shared.Combat.ResourceComponent)
local Status = require(Shared.Combat.Status)
local StatusContainer = require(Shared.Combat.StatusContainer)
local MovementStateComponent = require(Shared.Combat.MovementStateComponent)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Pipeline assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local externalState = { Value = 7 }
local provider = {}
function provider:CaptureRollbackState()
	return { Version = 1, Value = externalState.Value }
end
function provider:ValidateRollbackState(state)
	return type(state) == "table" and state.Version == 1 and type(state.Value) == "number",
		"Invalid test provider state"
end
function provider:PrepareRollbackRestore(state)
	return function()
		externalState.Value = state.Value
	end
end

local world = World.new({
	StateProviders = {
		["test.pipeline-provider.v1"] = provider,
	},
	ComponentFactories = {
		["test.pipeline-component.v1"] = function(_, state)
			return {
				RollbackKey = "test.pipeline-component.v1",
				CaptureRollbackState = function() return state end,
				RestoreRollbackState = function() return true end,
				ValidateRollbackState = function() return true end,
			}
		end,
	},
})
local simulation = Simulation.new(world)
local entity = world:CreateEntity()
entity:AddComponent(HealthComponent.new({ MaxHealth = 100, CurrentHealth = 75 }))
entity:AddComponent(MotionComponent.new())
entity:AddComponent(InputComponent.new())
entity:AddComponent(ResourceComponent.new({
	Resources = { Stamina = { Max = 100, Current = 60 } },
}))
local pipeline = world:GetCombatPipeline()
check(world:RegisterGameplayEventHandler("TestGameplayEvent", function() end),
	"World registers data-driven gameplay event handlers")
local definition = Definition.new({
	Id = "melee.light", StartupFrames = 1, ActiveFrames = 2,
	RecoveryFrames = 2, Cancelable = true, Tags = { "Melee", "Grounded" },
	Requirements = { Resources = { Stamina = 10 } },
	Costs = { Resources = { Stamina = 10 } },
})
check(definition:GetTotalFrames() == 5, "Definition computes total duration")
check(pipeline:RegisterDefinition(definition), "Definition registers")
check(not pipeline:RegisterDefinition(definition), "Duplicate definition is rejected")
check(pipeline:Start(entity, "unknown", 0).Type == Result.Type.UnknownAction, "Unknown action is rejected")
local started = pipeline:Start(entity, definition.Id, 0)
check(started.Type == Result.Type.Started and started.Accepted, "Action starts")
check(pipeline:GetAction(entity).Phase == "Startup", "Action starts in startup")
check(pipeline:Start(entity, definition.Id, 0).Type == Result.Type.AlreadyRunning, "Concurrent action is rejected")

simulation:Step()
check(pipeline:GetAction(entity).Phase == "Active", "Frame one enters active phase")
simulation:Step()
check(pipeline:GetAction(entity).Phase == "Active", "Active phase spans its configured duration")
simulation:Step()
check(pipeline:GetAction(entity).Phase == "Recovery", "Recovery phase follows active phase")
local cancelled = pipeline:Cancel(entity, world.CurrentFrame)
check(cancelled.Type == Result.Type.Cancelled, "Cancelable action can be cancelled")
check(pipeline:GetAction(entity) == nil or pipeline:GetAction(entity):IsFinished(), "Cancelled action is terminal")

local second = pipeline:Start(entity, definition.Id, world.CurrentFrame)
check(second.Type == Result.Type.Started, "A new action can start after cancellation")
for _ = 1, 5 do simulation:Step() end
check(pipeline:GetAction(entity) == nil, "Completed action is removed")
local events = pipeline:GetEvents()
local foundStart, foundCancel, foundComplete = false, false, false
for _, value in ipairs(events) do
	foundStart = foundStart or value.Type == Event.Type.Started
	foundCancel = foundCancel or value.Type == Event.Type.Cancelled
	foundComplete = foundComplete or value.Type == Event.Type.Completed
end
check(foundStart and foundCancel and foundComplete, "Lifecycle events are emitted")
check(world:GetCombatActionEvents()[1] ~= nil and world:GetCombatActionResults()[1] ~= nil,
	"World exposes action outputs")

local rollbackAction = pipeline:Start(entity, definition.Id, world.CurrentFrame)
check(rollbackAction.Accepted, "Action can be captured while active")
simulation:Step()
local actionState = pipeline:CaptureRollbackState()
local validState, stateDetail = pipeline:ValidateRollbackState(actionState, world)
check(validState, stateDetail)
pipeline:Cancel(entity, world.CurrentFrame)
local prepareRestore, restoreDetail = pipeline:PrepareRollbackRestore(actionState, world)
check(prepareRestore ~= nil, restoreDetail)
check(prepareRestore() and pipeline:GetAction(entity).Id == actionState.Actions[1].Id,
	"Pipeline restore rebinds an active action without emitting replay events")
check(world:GetCombatStateSchema() ~= nil,
	"World exposes the coordinated schema for pipeline state providers")
local schemaSnapshot = world:CaptureCombatState()
local schemaHash = world:HashCombatState(schemaSnapshot)
check(type(schemaHash) == "string" and string.match(schemaHash, "^state%-v1:") ~= nil,
	"World exposes a deterministic combat state hash")
check(schemaSnapshot.Providers["combat.pipeline"] ~= nil
	and schemaSnapshot.Providers["combat.combo-resolver.v1"] ~= nil
	and schemaSnapshot.Providers["combat.juggle-resolver.v1"] ~= nil
	and schemaSnapshot.Providers["combat.cancel-resolver.v1"] ~= nil
	and schemaSnapshot.Providers["test.pipeline-provider.v1"] ~= nil,
	"World schema captures active resolver providers")
local restored, restoreDetail = world:RestoreCombatState(schemaSnapshot)
check(restored, restoreDetail)
local restoredEntity = world:GetEntity(entity.Id)
check(restoredEntity ~= entity, "State restore rebuilds entity instances")
check(restoredEntity:GetComponent(HealthComponent):GetHealth() == 75,
	"State restore preserves native health state")
check(restoredEntity:GetComponent(ResourceComponent):Get("Stamina") == 30,
	"State restore preserves native resource state")
check(world:HashCombatState(world:CaptureCombatState()) == schemaHash,
	"State round-trip preserves the canonical state hash")
local comparison = world:CompareCombatStates(schemaSnapshot, world:CaptureCombatState())
check(comparison.Equal and comparison.LeftHash == comparison.RightHash,
	"World compares equivalent combat snapshots deterministically")

local contentDefinition = Definition.new({
	Id = "catalog.action", StartupFrames = 1, ActiveFrames = 2,
	RecoveryFrames = 1, Tags = { "Melee" },
})
local catalog = ActionCatalog.new()
catalog:Register(contentDefinition, 2)
catalog:RegisterMigration("catalog.action", 1, 2, function(data)
	data.Tags = { "Melee" }
	return data
end)
catalog:Seal()
check(catalog:Resolve(contentDefinition.Id, 2) == contentDefinition,
	"Action catalog resolves a definition by its content version")
local migratedDefinition = catalog:MigrateDefinitionData("catalog.action", 1, 2, {
	Id = "catalog.action", StartupFrames = 1, ActiveFrames = 2, RecoveryFrames = 1,
})
check(migratedDefinition and migratedDefinition.Tags[1] == "Melee",
	"Action content migrates through an explicit versioned transformation")
local missingMigration, missingMigrationReason = catalog:MigrateDefinitionData(
	"catalog.action", 1, 3, { Id = "catalog.action" })
check(not missingMigration and string.find(missingMigrationReason, "MissingActionMigration", 1, true),
	"Action content without a complete migration path is rejected")
check(not catalog:MigrateDefinitionData("catalog.action", 1, 2, {
	Id = "another.action", ActiveFrames = 1,
}), "Migration cannot change a stable action ID")
local catalogPipeline = require(Shared.Combat.CombatPipeline).new(world)
check(catalogPipeline:RegisterCatalog(catalog), "Pipeline registers a sealed action catalog")
check(not catalogPipeline:RegisterDefinition(contentDefinition),
	"Catalog-backed pipelines reject definitions outside the pinned catalog")
check(catalogPipeline:Start(restoredEntity, contentDefinition.Id).Type == Result.Type.Started,
	"Catalog-backed action definitions execute through the existing pipeline")
local catalogState = catalogPipeline:CaptureRollbackState()
check(catalogState.CatalogManifest ~= nil
	and catalogPipeline:ValidateRollbackState(catalogState, world),
	"Pipeline snapshots pin and validate the action catalog manifest")
local catalogStateWithoutManifest = { Version = 1, Actions = {} }
check(not catalogPipeline:ValidateRollbackState(catalogStateWithoutManifest, world),
	"Catalog-backed pipeline rejects snapshots without a content manifest")
local changedCatalogState = table.clone(catalogState)
changedCatalogState.CatalogManifest = table.clone(catalogState.CatalogManifest)
changedCatalogState.CatalogManifest.Entries = table.clone(catalogState.CatalogManifest.Entries)
changedCatalogState.CatalogManifest.Entries[1] = table.clone(changedCatalogState.CatalogManifest.Entries[1])
changedCatalogState.CatalogManifest.Entries[1].ContentVersion += 1
check(not catalogPipeline:ValidateRollbackState(changedCatalogState, world),
	"Pipeline rejects a snapshot with an incompatible action content version")

local repeatWorldA, repeatWorldB = World.new(), World.new()
local repeatSimulationA, repeatSimulationB = Simulation.new(repeatWorldA), Simulation.new(repeatWorldB)
local repeatEntityA, repeatEntityB = repeatWorldA:CreateEntity(), repeatWorldB:CreateEntity()
repeatEntityA:AddComponent(HealthComponent.new({ MaxHealth = 50, CurrentHealth = 40 }))
repeatEntityB:AddComponent(HealthComponent.new({ MaxHealth = 50, CurrentHealth = 40 }))
for _ = 1, 3 do
	repeatSimulationA:Step()
	repeatSimulationB:Step()
	check(repeatWorldA:HashCombatState() == repeatWorldB:HashCombatState(),
		"Identical simulation sequences remain deterministic")
end
repeatWorldA:Destroy()
repeatWorldB:Destroy()

local dynamicProvider = {
	CaptureRollbackState = function() return { Version = 1 } end,
	ValidateRollbackState = function(_, state) return type(state) == "table" and state.Version == 1 end,
	PrepareRollbackRestore = function() return function() end end,
}
world:RegisterCombatStateProvider("test.dynamic-provider.v1", dynamicProvider)
local dynamicSnapshot = world:CaptureCombatState()
check(dynamicSnapshot.Providers["test.dynamic-provider.v1"] ~= nil,
	"World registers dynamic state providers")
check(world:GetCombatStateSchema().Factories["Combat.HealthComponent"] ~= nil
	and world:GetCombatStateSchema().Factories["Combat.MotionComponent"] ~= nil
	and world:GetCombatStateSchema().Factories["Combat.InputComponent"] ~= nil
	and world:GetCombatStateSchema().Factories["Combat.GuardComponent"] ~= nil
	and world:GetCombatStateSchema().Factories["Combat.StatusContainer"] ~= nil,
	"World registers default rollback component factories")
check(world:GetCombatStateSchema().Factories["Combat.ResourceComponent"] ~= nil,
	"World registers the default resource rollback factory")
local currentEntity = world:GetEntity(entity.Id)
local respawned = world:RespawnEntity(currentEntity)
check(respawned and respawned.Id == entity.Id and world:GetEntity(entity.Id) == respawned,
	"World respawns an entity with its stable ID")
check(type(world.DisconnectPeer) == "function", "World exposes peer lifecycle cleanup")
local diagnostics = world:GetDiagnostics()
check(diagnostics.ForbiddenOperations ~= nil, "World exposes forbidden operation diagnostics")
check(world:AssertDeterministicOperation("WallClock") == true
	and type(world:GetDeterminismViolations()) == "table",
	"World exposes deterministic operation checks")
local gameplayEventId = world:ScheduleGameplayEvent(world.CurrentFrame + 1, "TestGameplayEvent",
	entity.Id, { Kind = "Test" })
check(type(gameplayEventId) == "number", "World schedules data-driven gameplay events")

local gatedDefinition = Definition.new({
	Id = "melee.grounded",
	Cancelable = true,
	Requirements = {
		RequiredStatusTags = { "Grounded" },
		ForbiddenStatusTags = { "Silenced" },
		MovementStates = { "Idle", "Moving" },
	},
})
local forbiddenDefinition = Definition.new({
	Id = "melee.silence-proof",
	Requirements = { ForbiddenStatusTags = { "Silenced" } },
})
check(pipeline:RegisterDefinition(gatedDefinition) and pipeline:RegisterDefinition(forbiddenDefinition),
	"Pipeline registers status- and movement-gated actions")
local gateEntity = world:CreateEntity()
check(pipeline:Start(gateEntity, gatedDefinition.Id).Reason == "MissingRequiredStatusTag:Grounded",
	"Required status tags reject an action before its resources or costs are applied")
local gateStatuses = gateEntity:AddComponent(StatusContainer.new())
gateStatuses:AddStatus(Status.new({ Name = "Grounded", Tags = { "Grounded" } }))
check(pipeline:Start(gateEntity, gatedDefinition.Id).Reason == "MissingMovementState",
	"Movement requirements report when the entity has no movement-state component")
local gateMovement = gateEntity:AddComponent(MovementStateComponent.new())
gateMovement:SetState("Dashing", world.CurrentFrame)
check(pipeline:Start(gateEntity, gatedDefinition.Id).Reason == "MovementStateRequirementFailed",
	"Movement requirements reject a state outside the allowed set")
gateMovement:SetState("Idle", world.CurrentFrame)
check(pipeline:Start(gateEntity, gatedDefinition.Id).Type == Result.Type.Started,
	"Action starts after its required tag and movement state are satisfied")
check(pipeline:Cancel(gateEntity).Type == Result.Type.Cancelled,
	"Status-gated action remains compatible with the existing cancellation pipeline")
gateStatuses:AddStatus(Status.new({ Name = "Silenced", Tags = { "Silenced" } }))
check(gateStatuses:HasTag("Silenced"), "The forbidden-tag fixture is active before action validation")
local silenceRejected = pipeline:Start(gateEntity, forbiddenDefinition.Id)
check(silenceRejected.Reason == "ForbiddenStatusTag:Silenced",
	"Forbidden status tags prevent a declarative action")

world:Destroy()
print(("CombatPipelineTest: PASS (%d assertions)"):format(assertions))

end
