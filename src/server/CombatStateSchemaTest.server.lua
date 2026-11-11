local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local Component = require(Shared.Core.Component)
local CombatStateSchema = require(Shared.Combat.CombatStateSchema)

local CounterComponent = setmetatable({}, { __index = Component })
CounterComponent.__index = CounterComponent
CounterComponent.RollbackKey = "test.counter.v1"

function CounterComponent.new(value)
	local self = setmetatable(Component.new(), CounterComponent)
	self.Value = value or 0
	return self
end

function CounterComponent:CaptureRollbackState()
	return { Value = self.Value }
end

function CounterComponent:RestoreRollbackState(state)
	if type(state) ~= "table" or type(state.Value) ~= "number" then
		return false, "Invalid counter state"
	end
	self.Value = state.Value
	return true
end

local world = World.new()
local simulation = Simulation.new(world)
local schema = CombatStateSchema.new()
schema:RegisterMigration(1, function(legacy)
	legacy.Version = 2
	legacy.Migrated = true
	return legacy
end)
local versionTwoSnapshot, versionTwoError = schema:Migrate({ Version = 2, Value = 7 })
assert(versionTwoSnapshot and versionTwoSnapshot.Version == 3 and versionTwoSnapshot.Value == 7,
	tostring(versionTwoError or "Version 2 snapshot should migrate to schema v3"))
local legacySnapshot = { Version = 1, Value = 9 }
local migratedSnapshot, migrationError = schema:Migrate(legacySnapshot)
assert(migratedSnapshot and migratedSnapshot.Version == CombatStateSchema.Version
	and migratedSnapshot.Migrated == true and legacySnapshot.Version == 1,
	tostring(migrationError or "Explicit migration did not produce an isolated current-version snapshot"))
local noMigration = CombatStateSchema.new()
local unsupportedSnapshot, unsupportedError = noMigration:Migrate({ Version = 1 })
assert(unsupportedSnapshot == nil
	and string.find(tostring(unsupportedError), "Missing combat state migration", 1, true),
	"Old snapshots without an explicit migration must be rejected")
local defaultCombatState = world:CaptureCombatState()
assert(defaultCombatState.Providers["combat.hitstop-resolver.v1"] ~= nil,
	"World combat snapshots should include the Hitstop resolver state")
schema:RegisterComponent("test.counter.v1", function(_, state)
	return CounterComponent.new(state.Value)
end)
local provider = { Value = 41, FailNextCommit = false }
function provider:CaptureRollbackState()
	return { Value = self.Value }
end
function provider:ValidateRollbackState(state)
	return type(state) == "table" and type(state.Value) == "number" and state.Value % 1 == 0,
		"Value must be an integer"
end
function provider:PrepareRollbackRestore(state)
	local valid, detail = self:ValidateRollbackState(state)
	assert(valid, detail)
	local value = state.Value
	return function()
		if self.FailNextCommit then
			self.Value = value
			self.FailNextCommit = false
			error("Injected provider commit failure")
		end
		self.Value = value
	end
end
schema:RegisterStateProvider("test.provider.v1", provider)
local scheduledExecutions = 0
local scheduledAmount = 0
assert(simulation:RegisterGameplayEventHandler("test.schema.event", function(event)
	scheduledExecutions += 1
	scheduledAmount += event.Parameters.Amount
	provider.Value += event.Parameters.Amount
end), "Gameplay event handler should register")

local first = world:CreateEntity()
first:AddComponent(CounterComponent.new(17))
local second = world:CreateEntity()
second:AddComponent(CounterComponent.new(29))
second:GetComponent(CounterComponent):SetEnabled(false)

local snapshot = schema:Capture(world)
assert(schema:Validate(snapshot))
local scheduledEventId = simulation:ScheduleGameplayEventAfter(
	1, "test.schema.event", 1, { Amount = 3 })
local scheduledSnapshot = schema:Capture(world)
assert(scheduledSnapshot.Simulation.DeterministicScheduler.Events[1].Id == scheduledEventId,
	"Coordinated snapshot should capture pending gameplay events")
simulation:Step()
assert(simulation:GetGameTime():GetFrame() == 1
	and scheduledExecutions == 1
	and scheduledAmount == 3
	and not simulation:GetGameplayScheduler():HasPendingEvents(),
	"Simulation should execute the scheduled gameplay event")
local firstReplaySnapshot = schema:Capture(world)
local firstReplayHash = world:HashCombatState(firstReplaySnapshot)
assert(scheduledExecutions == 1 and provider.Value == 44,
	"Scheduled gameplay event should mutate deterministic provider state")
local restoredScheduled, scheduledRestoreError = schema:Restore(world, scheduledSnapshot)
assert(restoredScheduled, tostring(scheduledRestoreError))
assert(simulation:GetGameplayScheduler():HasPendingEvents(),
	"Coordinated restore should restore pending gameplay events")
simulation:Step()
local secondReplaySnapshot = schema:Capture(world)
local secondReplayHash = world:HashCombatState(secondReplaySnapshot)
assert(firstReplayHash == secondReplayHash,
	"Restoring and replaying the same scheduled event should reproduce the same hash")
local replayComparison = schema:Compare(firstReplaySnapshot, secondReplaySnapshot)
assert(replayComparison.Equal
	and replayComparison.LeftHash == replayComparison.RightHash,
	"Restoring and replaying the same scheduled event should reproduce detailed state")

world:GetEntity(first.Id):GetComponent(CounterComponent).Value = 100
provider.Value = 999
world:DestroyEntity(second)
local extra = world:CreateEntity()
extra:AddComponent(CounterComponent.new(999))

local restored, restoreError = schema:Restore(world, snapshot)
assert(restored, tostring(restoreError))
assert(#world:GetEntities() == 2, "Entity roster was not restored")
assert(world:GetEntity(first.Id) ~= first, "Restore must rebuild entity instances, not reuse stale references")

local entities = world:GetEntities()
local a = world:GetEntity(entities[1].Id)
local b = world:GetEntity(entities[2].Id)
assert(a:GetComponent(CounterComponent).Value == 17)
assert(b:GetComponent(CounterComponent).Value == 29)
assert(b:GetComponent(CounterComponent):IsEnabled() == false)
assert(provider.Value == 41, "Registered state provider was not restored")
assert(world.IdGenerator.LastId == snapshot.IdGeneratorState)
assert(world.CurrentFrame == snapshot.Frame)

-- Inject a provider commit failure after the roster participant has committed. The coordinator
-- must compensate the provider and restore the exact previous entity objects and registry.
local preFailureEntities = world:GetEntities()
local preFailureById = {}
for _, entity in ipairs(preFailureEntities) do preFailureById[entity.Id] = entity end
provider.Value = 777
provider.FailNextCommit = true
local failedRestore, failedRestoreError = schema:Restore(world, snapshot)
assert(failedRestore == false, "Injected provider commit failure must fail the transaction")
assert(string.find(tostring(failedRestoreError), "Injected provider commit failure", 1, true),
	"Failure result should preserve the injected error")
assert(provider.Value == 777, "Provider compensation did not restore its pre-transaction value")
assert(#world:GetEntities() == #preFailureEntities, "Roster compensation did not restore entity count")
for id, entity in pairs(preFailureById) do
	assert(world:GetEntity(id) == entity, "Roster compensation changed entity identity for ID " .. tostring(id))
end
provider.FailNextCommit = false

local invalidSnapshot = table.clone(snapshot)
invalidSnapshot.Version = -1
local beforeInvalidRestore = world:GetEntities()
local beforeProviderValue = provider.Value
local invalidRestored = schema:Restore(world, invalidSnapshot)
assert(invalidRestored == false, "Invalid snapshot version must be rejected")
assert(#world:GetEntities() == #beforeInvalidRestore, "Rejected snapshot mutated the entity registry")
assert(provider.Value == beforeProviderValue, "Rejected snapshot mutated external provider state")

world:Destroy()
print("CombatStateSchemaTest: PASS")
