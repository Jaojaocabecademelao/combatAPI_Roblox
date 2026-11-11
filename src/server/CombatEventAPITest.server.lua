local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Combat = Shared:WaitForChild("Combat")
local Events = Shared:WaitForChild("Events")
local Sim = Shared:WaitForChild("Simulation")

local World = require(Core.World)
local Simulation = require(Sim.Simulation)
local CombatAPI = require(Shared.CombatAPI)
local EventBus = require(Events.EventBus)
local Event = require(Events.Event)
local EventTypes = require(Events.EventTypes)
local APIResult = require(Events.APIResult)
local APIError = require(Events.APIError)
local Hitbox = require(Combat.Hitbox)
local Hurtbox = require(Combat.Hurtbox)
local CollisionWorld = require(Combat.CollisionWorld)
local Attack = require(Combat.Attack)
local AttackInstance = require(Combat.AttackInstance)
local Damage = require(Combat.Damage)
local HealthComponent = require(Combat.HealthComponent)

local assertions = 0
local function check(value, message)
	assert(value, message or ("event/API assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

-- Public event registry: stable names for distinct facts.
for _, name in ipairs({ "EntityCreated", "EntityDestroyed", "EntityRespawned", "HitConfirmed", "HitRejected",
	"DamageApplied", "HealApplied", "StatusEffectApplied", "Death", "Block", "Parry", "GuardBreak", "ComboStarted", "ComboUpdated",
	"ComboEnded", "JuggleStarted", "JuggleEnded", "MovementStateChanged", "CancelAllowed",
	"CancelRejected", "InputPressed", "InputReleased", "PredictionDiverged", "FrameConfirmed",
	"RollbackStarted", "RollbackCompleted", "RollbackFailed", "AuthorityInputAccepted",
	"AuthorityInputRejected", "AuthoritySnapshotPublished", "Clash", "ArmorApplied", "MotionApplied",
	"HitstopStarted", "HitstopEnded", "CounterHit", "ProtectionApplied" }) do
	check(EventTypes[name] == name, "official EventType should be stable: " .. name)
end

-- Envelope projection, common metadata, freezing, nested copy isolation, and cycles.
local nested = { Amount = 12, Info = { Flag = true } }
local cyclic = {}; cyclic.Self = cyclic
local sourceEntity = { Id = 77 }
local envelope = Event.new("Probe", { Amount = 12, Entity = sourceEntity, Nested = nested, Cycle = cyclic }, {
	SimulationFrame = 42, SourceSystem = "Test", EntityId = 77, Sequence = 9, ExecutionMode = "Replay" })
check(envelope.Type == "Probe")
check(envelope.Frame == 42 and envelope.SimulationFrame == 42)
check(envelope.SourceSystem == "Test")
check(envelope.EntityId == 77)
check(envelope.Sequence == 9)
check(envelope.ExecutionMode == "Replay")
check(envelope.Version == 1)
check(envelope.Amount == 12 and envelope.Payload.Amount == 12)
check(envelope.Payload.Entity == 77)
check(envelope.Payload.Nested.Info.Flag == true)
check(table.isfrozen(envelope) and table.isfrozen(envelope.Payload))
check(table.isfrozen(envelope.Payload.Nested) and table.isfrozen(envelope.Payload.Nested.Info))
check(envelope.Payload.Cycle.Self == "<cycle>")
nested.Info.Flag = false
check(envelope.Payload.Nested.Info.Flag == true, "published payload must not alias caller-owned plain tables")
check(not pcall(function() envelope.Amount = 999 end))
check(not pcall(function() envelope.Payload.Amount = 999 end))
local noContext = Event.new("Plain", { Frame = 8, EntityId = 4 })
check(noContext.Frame == 8 and noContext.EntityId == 4 and noContext.SourceSystem == "Unknown")
check(noContext.ExecutionMode == "Normal" and noContext.Version == 1)

-- EventBus creation, listener IDs, duplicate listeners, ordering, and stable dispatch.
local bus = EventBus.new({ Marker = "ctx" })
check(type(bus) == "table" and bus.Destroyed == false)
local trace = {}
local low = bus:Subscribe("Order", function(event, context)
	table.insert(trace, "low:" .. event.Payload.N)
	check(context.Marker == "ctx")
end)
local high1 = bus:Subscribe("Order", function(event) table.insert(trace, "high1:" .. event.Payload.N) end, { Priority = 10 })
local high2 = bus:Subscribe("Order", function(event) table.insert(trace, "high2:" .. event.Payload.N) end, { Priority = 10 })
check(low ~= nil and high1 ~= nil and high2 ~= nil)
check(low:GetId() < high1:GetId() and high1:GetId() < high2:GetId())
check(low:IsConnected() and high1:IsConnected() and high2:IsConnected())
local dispatched = bus:Dispatch("Order", { N = 1 }, { Frame = 3, SourceSystem = "Test" })
check(dispatched.Type == "Order" and #trace == 3)
check(trace[1] == "high1:1" and trace[2] == "high2:1" and trace[3] == "low:1")
check(#bus:GetErrors() == 0, "valid callbacks receive explicit context without errors")
check(bus:Dispatch("NoListeners", {}) ~= nil)
check(low:Disconnect() and not low:IsConnected())
check(not low:Disconnect(), "second Disconnect is a safe no-op")
check(not bus:Unsubscribe(low:GetId()))
check(high1:Disconnect() and high2:Disconnect())
check(bus:Unsubscribe(999999) == false)
check(bus:Unsubscribe("invalid") == false)
local duplicateCalls = 0
local sameCallback = function() duplicateCalls += 1 end
local duplicateA = bus:Subscribe("Duplicate", sameCallback)
local duplicateB = bus:Subscribe("Duplicate", sameCallback)
check(duplicateA:GetId() ~= duplicateB:GetId())
bus:Dispatch("Duplicate", {})
check(duplicateCalls == 2)
duplicateA:Disconnect(); duplicateB:Disconnect()

-- Subscription mutation during dispatch: additions start next dispatch; removals skip pending listeners.
local mutationBus = EventBus.new()
local mutationTrace, added, pending = {}, nil, nil
mutationBus:Subscribe("Mutate", function()
	table.insert(mutationTrace, "A")
	if not added then added = mutationBus:Subscribe("Mutate", function() table.insert(mutationTrace, "C") end) end
	if pending then pending:Disconnect() end
end)
pending = mutationBus:Subscribe("Mutate", function() table.insert(mutationTrace, "B") end)
mutationBus:Dispatch("Mutate", {})
check(table.concat(mutationTrace, "") == "A")
mutationTrace = {}
mutationBus:Dispatch("Mutate", {})
check(table.concat(mutationTrace, "") == "AC")
check(added:IsConnected() and not pending:IsConnected())

-- Listener errors are structured and isolated; later listeners still run.
local errorBus = EventBus.new()
local afterError = false
errorBus:Subscribe("Failure", function() error("expected listener failure") end)
errorBus:Subscribe("Failure", function() afterError = true end)
errorBus:Dispatch("Failure", {}, { Frame = 11 })
check(afterError)
local errors = errorBus:GetErrors()
check(#errors == 1 and getmetatable(errors[1]) == APIError)
check(errors[1].Code == APIError.Code.InternalError and errors[1].System == "Events")
check(errors[1].Frame == 11 and errors[1].Context.ListenerId ~= nil)
table.clear(errors)
check(#errorBus:GetErrors() == 1, "error getter returns a detached array")
errorBus:ClearErrors(); check(#errorBus:GetErrors() == 0)

-- Filters are pure, composable predicates over the immutable envelope.
local filterBus = EventBus.new()
local filtered = { Entity = 0, Source = 0, Attacker = 0, Defender = 0, Predicate = 0, All = 0 }
filterBus:Subscribe("Filter", function() filtered.Entity += 1 end, { EntityId = 5 })
filterBus:Subscribe("Filter", function() filtered.Source += 1 end, { SourceSystem = "Damage" })
filterBus:Subscribe("Filter", function() filtered.Attacker += 1 end, { AttackerId = 8 })
filterBus:Subscribe("Filter", function() filtered.Defender += 1 end, { DefenderId = 5 })
filterBus:Subscribe("Filter", function() filtered.Predicate += 1 end, { Predicate = function(event) return event.Payload.Amount == 4 end })
filterBus:Subscribe("Filter", function() filtered.All += 1 end,
	{ EntityId = 5, SourceSystem = "Damage", AttackerId = 8, DefenderId = 5 })
filterBus:Dispatch("Filter", { Amount = 4, AttackerId = 8, DefenderId = 5 },
	{ EntityId = 5, SourceSystem = "Damage" })
for _, count in pairs(filtered) do check(count == 1) end
filterBus:Dispatch("Filter", { Amount = 0, AttackerId = 3, DefenderId = 2 },
	{ EntityId = 6, SourceSystem = "Other" })
for _, count in pairs(filtered) do check(count == 1) end
local invalidSubscription, invalidError = filterBus:Subscribe("", function() end)
check(invalidSubscription == nil and invalidError.Code == APIError.Code.InvalidArgument)
local invalidFilter, filterError = filterBus:Subscribe("Filter", function() end, { EntityId = {} })
check(invalidFilter == nil and filterError.Code == APIError.Code.InvalidArgument)
local invalidPriority, priorityError = filterBus:Subscribe("Filter", function() end, { Priority = math.huge })
check(invalidPriority == nil and priorityError.Code == APIError.Code.InvalidArgument)

-- APIResult is explicit and immutable; expected lookup failures do not throw.
local successResult = APIResult.new(true, "value")
local failResult = APIResult.new(false, nil, APIError.new(APIError.Code.NotFound, "missing", "Test", 2))
check(successResult.Success and successResult.Value == "value" and successResult.Error == nil)
check(not failResult.Success and failResult.Value == nil and failResult.Error.Code == "NotFound")
check(table.isfrozen(successResult) and table.isfrozen(failResult) and table.isfrozen(failResult.Error))
for _, code in ipairs({ "InvalidArgument", "InvalidEntity", "InvalidOperation", "NotFound", "AlreadyExists",
	"NotInitialized", "Disabled", "PermissionDenied", "InternalError", "Destroyed" }) do
	check(APIError.Code[code] == code)
end

-- Public entry point, per-World contexts, capabilities, and explicit system access.
local worldA = CombatAPI.CreateWorld()
local worldB = CombatAPI.CreateWorld()
check(CombatAPI.IsWorld(worldA) and CombatAPI.IsWorld(worldB) and not CombatAPI.IsWorld({}))
local apiA, apiB = CombatAPI.GetContext(worldA), CombatAPI.GetAPIContext(worldB)
check(apiA == worldA:GetCombatAPI() and apiB == worldB:GetCombatAPI() and apiA ~= apiB)
check(worldA:GetEvents() == apiA:GetEvents() and worldB:GetEvents() == apiB:GetEvents())
check(apiA:GetWorld() == worldA and apiB:GetWorld() == worldB)
check(apiA:HasFeature("Events") and apiA:HasFeature("Simulation"))
check(not apiA:HasFeature("MadeUpFeature") and not apiA:HasSystem("MadeUpSystem"))
for _, pair in ipairs({ { "Input", "GetInputResolver" }, { "Guard", "GetGuardResolver" },
	{ "Combo", "GetComboResolver" }, { "Juggle", "GetJuggleResolver" },
	{ "MovementState", "GetMovementStateResolver" }, { "Cancel", "GetCancelResolver" },
	{ "Character", "GetCharacterResolver" }, { "Animation", "GetAnimationResolver" },
	{ "Networking", "GetNetworkResolver" }, { "Prediction", "GetPredictionResolver" },
	{ "Rollback", "GetRollbackResolver" }, { "Authority", "GetAuthorityResolver" },
	{ "Armor", "GetArmorResolver" }, { "Protection", "GetProtectionResolver" },
	{ "Hitstop", "GetHitstopResolver" } }) do
	local name, getter = pair[1], pair[2]
	check(type(apiA[getter]) == "function", name .. " getter is explicit")
	check(apiA:HasSystem(name), name .. " system is available")
	local result = apiA:GetSystem(name)
	check(result.Success and result.Value == worldA[getter](worldA))
	check(apiA:HasFeature(name))
end
local unknownSystem = apiA:GetSystem("PrivateInternals")
check(not unknownSystem.Success and unknownSystem.Error.Code == APIError.Code.NotFound)
local uninitializedDamage = apiA:GetSystem("Damage")
check(not uninitializedDamage.Success and uninitializedDamage.Error.Code == APIError.Code.NotInitialized)

-- Public entity lifecycle and world isolation.
local entitiesA, entitiesB = {}, {}
apiA:On(EventTypes.EntityCreated, function(event) table.insert(entitiesA, event.EntityId) end)
apiB:On(EventTypes.EntityCreated, function(event) table.insert(entitiesB, event.EntityId) end)
local createdEntity = apiA:CreateEntity()
local entityA = createdEntity.Value
check(createdEntity.Success and entityA ~= nil and worldA:HasEntity(entityA))
check(#entitiesA == 1 and entitiesA[1] == entityA.Id and #entitiesB == 0)
worldA:SetExecutionContext("Rollback")
local deniedCreate = apiA:CreateEntity()
check(not deniedCreate.Success and deniedCreate.Error.Code == APIError.Code.InvalidOperation)
worldA:SetExecutionContext("Normal")
local foundEntity = apiA:GetEntity(entityA.Id)
check(foundEntity.Success and foundEntity.Value == entityA)
local missingEntity = apiA:GetEntity("missing")
check(not missingEntity.Success and missingEntity.Error.Code == APIError.Code.InvalidEntity)
local destroyedIds = {}
local reentrantDestroy
apiA:On(EventTypes.EntityDestroyed, function(event)
	table.insert(destroyedIds, event.EntityId)
	if event.EntityId == entityA.Id then reentrantDestroy = worldA:DestroyEntity(event.EntityId) end
end)
local destroyResult = apiA:DestroyEntity(entityA.Id)
check(destroyResult.Success and destroyResult.Value and not worldA:HasEntity(entityA.Id))
check(#destroyedIds == 1 and destroyedIds[1] == entityA.Id)
check(reentrantDestroy == false, "destroy callbacks cannot recursively destroy the same entity")
check(not apiA:DestroyEntity(entityA.Id).Success)
local directEntity = worldA:CreateEntity()
check(entitiesA[#entitiesA] == directEntity.Id)
check(worldA:DestroyEntity(directEntity) and destroyedIds[#destroyedIds] == directEntity.Id)
check(not worldA:DestroyEntity(directEntity))

-- Priority/filter dispatch remains deterministic over repeated batches.
local orderBus = EventBus.new()
local order = {}
for i = 1, 12 do
	local priority = (i * 7) % 5
	orderBus:Subscribe("Batch", function(event) table.insert(order, tostring(priority) .. ":" .. tostring(event.Payload.Index)) end,
		{ Priority = priority })
end
for i = 1, 10 do
	local result = orderBus:Dispatch("Batch", { Index = i }, { Frame = 100 + i, SourceSystem = "Batch" })
	check(result.Frame == 100 + i and result.SourceSystem == "Batch")
end
check(#order == 120)
local firstBatch = table.concat(order, ",")
table.clear(order)
for i = 1, 10 do orderBus:Dispatch("Batch", { Index = i }, { Frame = 100 + i, SourceSystem = "Batch" }) end
check(table.concat(order, ",") == firstBatch, "same listener set and event sequence dispatch identically")

-- World adapters publish internal Simulation facts once, in deterministic source order.
local integrationWorld = World.new()
local collision = CollisionWorld.new(integrationWorld)
local simulation = Simulation.new(integrationWorld, { FixedDeltaTime = 1 / 60 })
check(integrationWorld:GetCollisionWorld() == collision and integrationWorld:GetSimulation() == simulation)
local integrationApi = integrationWorld:GetCombatAPI()
check(integrationApi:GetCollisionWorld() == collision)
check(integrationApi:GetDamageResolver() == collision.DamageResolver)
check(integrationApi:GetDefenseResolver() == collision.DefenseResolver)
check(integrationApi:GetCombatResolver() == collision.CombatResolver)
check(integrationApi:GetMotionResolver() == collision.MotionResolver)
local attacker = integrationWorld:CreateEntity()
local target = integrationWorld:CreateEntity()
target:AddComponent(HealthComponent.new({ MaxHealth = 50 }))
target:AddComponent(Hurtbox.new({ Shape = "Sphere", Radius = 1, Position = Vector3.new(0, 0, 0) }))
local hitbox = Hitbox.new({ Shape = "Sphere", Radius = 1, Position = Vector3.new(0, 0, 0) })
local attack = Attack.new({ Id = "PublicEventProbe", Damage = Damage.new({ Amount = 7 }) })
local attackInstance = AttackInstance.new(attack, attacker):Activate()
attackInstance:AddHitbox(hitbox)
attacker:AddComponent(hitbox)
local facts = {}
for _, eventType in ipairs({ EventTypes.HitConfirmed, EventTypes.DamageApplied }) do
	integrationWorld:GetEvents():Subscribe(eventType, function(event) table.insert(facts, event) end)
end
simulation:Step()
check(#facts == 2 and facts[1].Type == EventTypes.HitConfirmed and facts[2].Type == EventTypes.DamageApplied)
check(facts[1].SimulationFrame == simulation:GetGameTime():GetFrame()
	and facts[2].SimulationFrame == simulation:GetGameTime():GetFrame())
check(facts[1].Payload.AttackerId == attacker.Id and facts[1].Payload.DefenderId == target.Id)
check(facts[2].Payload.AttackerId == attacker.Id and facts[2].Payload.DefenderId == target.Id)
check(facts[2].Payload.Amount == 7 and facts[2].SourceSystem == "Damage")
check(integrationWorld:GetDamageEvents()[1].AppliedAmount == facts[2].Payload.Amount)
local beforeRepeat = #facts
integrationWorld:FlushEvents()
check(#facts == beforeRepeat, "an internal result is published at most once")

-- Adapters preserve prediction, rollback, authority, and replay metadata.
local mappedWorld = World.new()
local mappedEvents = {}
for _, name in ipairs({ EventTypes.PredictionDiverged, EventTypes.FrameConfirmed, EventTypes.RollbackStarted,
	EventTypes.RollbackCompleted, EventTypes.RollbackFailed, EventTypes.AuthorityInputAccepted,
	EventTypes.AuthorityInputRejected, EventTypes.AuthoritySnapshotPublished }) do
	mappedWorld:GetEvents():Subscribe(name, function(event) table.insert(mappedEvents, event) end)
end
local function fakeEvent(resolver, data) table.insert(resolver.Events, data) end
fakeEvent(mappedWorld.PredictionResolver, { Type = "PredictionDiverged", Frame = 21, EntityId = 1, Cause = "State" })
fakeEvent(mappedWorld.PredictionResolver, { Type = "FrameConfirmed", Frame = 22, EntityId = 1 })
fakeEvent(mappedWorld.RollbackResolver, { Type = "RollbackStarted", Frame = 23, EntityId = 1 })
fakeEvent(mappedWorld.RollbackResolver, { Type = "RollbackCompleted", Frame = 24, EntityId = 1 })
fakeEvent(mappedWorld.RollbackResolver, { Type = "RollbackFailed", Frame = 25, EntityId = 1 })
fakeEvent(mappedWorld.AuthorityResolver, { Type = "InputAccepted", Frame = 26, EntityId = 1 })
fakeEvent(mappedWorld.AuthorityResolver, { Type = "InputRejected", Frame = 27, EntityId = 1 })
fakeEvent(mappedWorld.AuthorityResolver, { Type = "SnapshotPublished", Frame = 28, EntityId = 1 })
mappedWorld:FlushEvents()
check(#mappedEvents == 8)
for index, expected in ipairs({ EventTypes.PredictionDiverged, EventTypes.FrameConfirmed, EventTypes.RollbackStarted,
	EventTypes.RollbackCompleted, EventTypes.RollbackFailed, EventTypes.AuthorityInputAccepted,
	EventTypes.AuthorityInputRejected, EventTypes.AuthoritySnapshotPublished }) do
	check(mappedEvents[index].Type == expected)
	check(mappedEvents[index].Frame == 20 + index)
	check(mappedEvents[index].ExecutionMode == "Normal")
	check(mappedEvents[index].EntityId == 1)
end
mappedWorld:SetExecutionContext("Replay")
mappedWorld:FlushEvents()
check(#mappedEvents == 16, "the same deterministic facts can be published again during replay")
for index = 1, 8 do
	check(mappedEvents[index + 8].Type == mappedEvents[index].Type)
	check(mappedEvents[index + 8].Frame == mappedEvents[index].Frame)
	check(mappedEvents[index + 8].ExecutionMode == "Replay")
end
local mappedCount = #mappedEvents
mappedWorld:FlushEvents()
check(#mappedEvents == mappedCount)
mappedWorld:SetExecutionContext("Normal")

-- Remaining combat adapters retain their public fact types and originating frame.
local adapterWorld = World.new()
local adapterCollision = CollisionWorld.new(adapterWorld)
local adapterEntity = adapterWorld:CreateEntity()
local adapterObserved = {}
for _, name in ipairs({ EventTypes.Block, EventTypes.Parry, EventTypes.GuardBreak, EventTypes.Clash,
	EventTypes.HitRejected, EventTypes.HitConfirmed,
	EventTypes.CounterHit, EventTypes.ArmorApplied, EventTypes.MotionApplied, EventTypes.HitstopStarted,
	EventTypes.ComboStarted, EventTypes.ComboUpdated, EventTypes.ComboEnded, EventTypes.JuggleStarted,
	EventTypes.JuggleEnded, EventTypes.MovementStateChanged, EventTypes.CancelAllowed,
	EventTypes.CancelRejected, EventTypes.InputPressed, EventTypes.InputReleased, EventTypes.ProtectionApplied }) do
	adapterWorld:GetEvents():Subscribe(name, function(event) table.insert(adapterObserved, event) end)
end
adapterWorld.DefenseResolver.DefenseEvents = {
	{ Result = "Blocked", Attacker = adapterEntity, Defender = adapterEntity, Frame = 31 },
	{ Result = "Parried", Attacker = adapterEntity, Defender = adapterEntity, Frame = 32 },
}
adapterWorld.GuardResolver.Events = { { GuardBroken = true, Defender = adapterEntity, Frame = 33 } }
adapterWorld.CombatResolver.ResolutionEvents = { { Outcome = "Clash", Frame = 34,
	AttackerEntityIdA = adapterEntity.Id } }
adapterWorld.ProtectionResolver.Results = {
	{ Result = "Blocked", Category = "Hit", Target = adapterEntity, Frame = 30 },
	{ Result = "Blocked", Category = "Damage", Target = adapterEntity, Frame = 49 },
}
adapterWorld.LastResolvedHitEvents = { { Attacker = adapterEntity, Target = adapterEntity,
	AttackInstanceId = 99, Frame = 34 } }
adapterWorld.CounterResolver.Results = { { Type = "CounterHit", Target = adapterEntity, Frame = 35 } }
adapterWorld.ArmorResolver.Results = { { Found = true, Target = adapterEntity, Frame = 36 } }
adapterCollision.MotionResolver.Results = { { Target = adapterEntity, Type = "Launch", Frame = 37 } }
adapterWorld.HitstopResolver.Results = { { Type = "Hitstop", Outcome = "Applied", Target = adapterEntity, Frame = 38 } }
adapterWorld.ComboResolver.Events = {
	{ Type = "ComboStarted", Defender = adapterEntity, Frame = 39 },
	{ Type = "ComboHit", Defender = adapterEntity, Frame = 40 },
	{ Type = "ComboEnded", Defender = adapterEntity, Frame = 41 },
}
adapterWorld.JuggleResolver.Events = {
	{ Type = "JuggleStarted", EntityId = adapterEntity.Id, Frame = 42 },
	{ Type = "JuggleEnded", EntityId = adapterEntity.Id, Frame = 43 },
}
adapterWorld.MovementStateResolver.Events = { { Type = "StateChanged", EntityId = adapterEntity.Id, Frame = 44 } }
adapterWorld.CancelResolver.Events = {
	{ Type = "CancelAllowed", EntityId = adapterEntity.Id, Frame = 45 },
	{ Type = "CancelRejected", EntityId = adapterEntity.Id, Frame = 46 },
}
adapterWorld.InputResolver.Events = {
	{ Type = "InputPressed", EntityId = adapterEntity.Id, Frame = 47 },
	{ Type = "InputReleased", EntityId = adapterEntity.Id, Frame = 48 },
}
adapterWorld:FlushEvents()
check(#adapterObserved == 21, "all configured combat event adapters publish once")
for _, event in ipairs(adapterObserved) do
	check(event.Frame >= 30 and event.Frame <= 49)
	check(event.EntityId == adapterEntity.Id)
end
for index, eventType in ipairs({ EventTypes.Clash, EventTypes.HitRejected, EventTypes.Block, EventTypes.Parry,
	EventTypes.HitConfirmed, EventTypes.CounterHit, EventTypes.GuardBreak, EventTypes.ProtectionApplied,
	EventTypes.ArmorApplied, EventTypes.MotionApplied,
	EventTypes.HitstopStarted, EventTypes.ComboStarted, EventTypes.ComboUpdated, EventTypes.ComboEnded,
	EventTypes.JuggleStarted, EventTypes.JuggleEnded, EventTypes.MovementStateChanged,
	EventTypes.CancelAllowed, EventTypes.CancelRejected, EventTypes.InputPressed, EventTypes.InputReleased }) do
	check(adapterObserved[index].Type == eventType)
end

-- EventBus lifecycle and API destruction invalidate subscriptions safely.
local lifecycleWorld = CombatAPI.CreateWorld()
local lifecycleApi = lifecycleWorld:GetCombatAPI()
local lifecycleSub = lifecycleApi:On("Lifetime", function() end)
check(lifecycleSub:IsConnected())
check(lifecycleWorld:Destroy())
check(not lifecycleSub:IsConnected())
check(not lifecycleWorld:Destroy())
local postDestroySubscription, postDestroyError = lifecycleApi:On("Lifetime", function() end)
check(postDestroySubscription == nil and postDestroyError.Code == APIError.Code.Destroyed)
check(not lifecycleApi:HasFeature("Events") and not lifecycleApi:HasSystem("Input"))
check(lifecycleApi:GetInputResolver() == nil and lifecycleApi:GetWorld() == nil)
local postDestroyLookup = lifecycleApi:GetEntity(1)
check(not postDestroyLookup.Success and postDestroyLookup.Error.Code == APIError.Code.Destroyed)
check(lifecycleApi:DestroyEntity(1).Error.Code == APIError.Code.Destroyed)
local deadDispatch, deadDispatchError = lifecycleApi:GetEvents():Dispatch("Lifetime", {})
check(deadDispatch == nil and deadDispatchError.Code == APIError.Code.Destroyed)
check(not lifecycleWorld:GetEvents())

-- Independent Worlds retain independent subscriptions and event sequences.
local isolationA, isolationB = World.new(), World.new()
local receivedA, receivedB = 0, 0
isolationA:GetEvents():Subscribe("Isolated", function() receivedA += 1 end)
isolationB:GetEvents():Subscribe("Isolated", function() receivedB += 1 end)
isolationA:_PublishPublicEvent("Isolated", { Value = "a" }, "Test", 1)
check(receivedA == 1 and receivedB == 0)
isolationB:_PublishPublicEvent("Isolated", { Value = "b" }, "Test", 1)
check(receivedA == 1 and receivedB == 1)
check(isolationA.EventSequence == 1 and isolationB.EventSequence == 1)
local modes = {}
isolationA:GetEvents():Subscribe("Mode", function(event) table.insert(modes, event.ExecutionMode) end)
for _, mode in ipairs({ "Normal", "Prediction", "Replay", "Rollback", "Authority" }) do
	isolationA:SetExecutionContext(mode)
	isolationA:_PublishPublicEvent("Mode", {}, "Test", 2)
	check(modes[#modes] == mode, "envelope preserves execution mode " .. mode)
end
isolationA:SetExecutionContext("Normal")

check(assertions >= 220, "expected at least 220 meaningful API/event assertions")
print("Combat event/API tests passed (" .. tostring(assertions) .. " assertions)")
