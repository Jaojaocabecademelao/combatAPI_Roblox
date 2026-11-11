local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local CombatStateSchema = require(Shared.Combat.CombatStateSchema)
local DefenseResolver = require(Shared.Combat.DefenseResolver)
local DefenseComponent = require(Shared.Combat.DefenseComponent)
local DefenseResult = require(Shared.Combat.DefenseResult)

local function check(value, message)
	assert(value, message)
end

local world = World.new()
Simulation.new(world)
local entity = world:CreateEntity()
local defense = entity:AddComponent(DefenseComponent.new())
defense:SetBlocking(true)
local resolver = DefenseResolver.new()
world.DefenseResolver = resolver
local probe = { FailTarget = false }
function probe:CaptureRollbackState() return { Version = 1 } end
function probe:ValidateRollbackState(state) return type(state) == "table" and state.Version == 1 end
function probe:PrepareRollbackRestore(state, restoreWorld, context, role)
	return function()
		if role == "Target" and self.FailTarget then
			self.FailTarget = false
			error("Injected post-defense commit failure")
		end
	end
end

local schema = CombatStateSchema.new()
schema:RegisterComponent(DefenseComponent.RollbackKey, function()
	return DefenseComponent.new()
end)
schema:RegisterStateProvider("combat.defense-resolver.v1", resolver)
schema:RegisterStateProvider("zz.test.failure.v1", probe)
local entityId = entity.Id
local function makeHit(frame)
	return {
		Frame = frame,
		Target = world:GetEntity(entityId),
		Attacker = { Id = "attacker" },
		Attack = { Id = "test-attack" },
		AttackInstance = { Id = 7 },
		AttackInstanceId = 7,
	}
end

local snapshot = schema:Capture(world)
resolver:Process({ makeHit(1) }, 1)
check(resolver:GetDefenseEvents()[1].Result == DefenseResult.Blocked,
	"Blocking intent should produce a DefenseEvent")
local restored, detail = schema:Restore(world, snapshot)
check(restored, "Coordinated defense restore failed: " .. tostring(detail))
local restoredEntity = world:GetEntity(entityId)
check(restoredEntity ~= entity and restoredEntity:GetComponent(DefenseComponent):IsBlocking(),
	"Defense intent must be restored on the staged entity roster")
check(#resolver:GetDefenseEvents() == 0,
	"Target restore must clear frame-local DefenseEvents to prevent duplicate publication")

resolver:Process({ makeHit(2) }, 2)
local priorEvents = resolver:GetDefenseEvents()
check(#priorEvents == 1, "A subsequent frame should populate the defense output buffer")
probe.FailTarget = true
local failed, failureDetail = schema:Restore(world, snapshot)
check(failed == false and string.find(tostring(failureDetail), "Injected post-defense commit failure", 1, true),
	"An injected later commit failure should abort restoration")
local afterFailure = resolver:GetDefenseEvents()
check(#afterFailure == #priorEvents and afterFailure[1] == priorEvents[1],
	"Compensation must restore the exact previous DefenseEvent object")
check(world:GetEntity(entityId) == restoredEntity,
	"Failed restore must compensate to the exact live entity instance")

world:Destroy()
print("CombatDefenseRollbackIntegrationTest: PASS")
