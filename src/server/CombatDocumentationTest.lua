return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ServerTests = ServerScriptService:WaitForChild("Server")

local assertions = 0
local function check(value, message)
	assert(value, message or ("Documentation assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local function moduleAt(path)
	local node = Shared
	for part in string.gmatch(path, "[^/]+") do
		node = node:FindFirstChild(part)
		if not node then return nil end
	end
	return node and node:IsA("ModuleScript") and node or nil
end

-- Modules explicitly cited as the current architecture/API are checked at their real Roblox paths.
local documentedModules = {
	"CombatAPI", "Core/CombatEntity", "Core/EntityRegistry", "Core/Component", "Core/EntityState",
	"Core/World", "Core/IdGenerator", "Simulation/Simulation", "Simulation/GameTime",
	"Simulation/Scheduler", "Simulation/DeterministicRNG", "Combat/Hitbox", "Combat/Hurtbox",
	"Simulation/SimulationState", "Simulation/FrameCommandBuffer", "Simulation/DeterministicScheduler",
	"Simulation/DeterminismGuard", "Simulation/StateSerializer", "Simulation/StateHasher",
	"Combat/CollisionWorld", "Combat/CollisionQuery", "Combat/HitResolver", "Combat/Attack",
	"Combat/AttackInstance", "Combat/HitEvent", "Combat/HitPolicy", "Combat/HitHistory",
	"Combat/HitProcessor", "Combat/HealthComponent", "Combat/Damage", "Combat/DamageRequest",
	"Combat/DamageResolver", "Combat/DamageEvent", "Combat/DeathEvent", "Combat/Status",
	"Combat/StatusContainer", "Combat/StatusEffectResolver", "Combat/Hitstun",
	"Combat/DefenseComponent", "Combat/DefenseResolver",
	"Combat/DefenseResult", "Combat/CombatResolver", "Combat/CombatResolutionResult",
	"Combat/CounterResolver", "Combat/CounterResult", "Combat/MotionRequest", "Combat/MotionResult",
	"Combat/MotionComponent", "Combat/MotionResolver", "Combat/HitstopRequest", "Combat/HitstopComponent",
	"Combat/HitstopResolver", "Combat/ProtectionComponent", "Combat/ProtectionQuery",
	"Combat/ProtectionResolver", "Combat/ProtectionResult", "Combat/ArmorComponent", "Combat/ArmorProfile",
	"Combat/ArmorResolver", "Combat/ArmorResult", "Combat/GuardComponent", "Combat/GuardProfile",
	"Combat/GuardResolver", "Combat/GuardResult", "Combat/Combo", "Combat/ComboComponent",
	"Combat/ComboProfile", "Combat/ComboResolver", "Combat/ComboEvent", "Combat/ComboResult",
	"Combat/Juggle", "Combat/JuggleComponent", "Combat/JuggleProfile", "Combat/JuggleResolver",
	"Combat/JuggleEvent", "Combat/JuggleResult", "Combat/MovementState", "Combat/MovementStateComponent",
	"Combat/MovementStateResolver", "Combat/CancelComponent", "Combat/CancelProfile", "Combat/CancelResolver",
	"Combat/Input", "Combat/InputState", "Combat/InputFrame", "Combat/InputComponent", "Combat/InputResolver",
	"Combat/CharacterComponent", "Combat/CharacterProfile", "Combat/CharacterAdapter", "Combat/CharacterResolver",
	"Combat/AnimationComponent", "Combat/AnimationProfile", "Combat/AnimationAdapter", "Combat/AnimationResolver",
	"Combat/NetworkComponent", "Combat/NetworkProfile", "Combat/NetworkResolver", "Combat/PredictionComponent",
	"Combat/RobloxRemoteEventAdapter",
	"Combat/CombatActionDefinition", "Combat/CombatActionInstance", "Combat/CombatActionResult",
	"Combat/CombatActionEvent", "Combat/CombatActionCatalog", "Combat/CombatPipeline",
	"Simulation/ReplayRecording",
	"Combat/ReconciliationResolver", "Combat/ReconciliationResult",
	"Combat/PredictionProfile", "Combat/PredictionResolver", "Combat/PredictionResult", "Combat/RollbackComponent",
	"Combat/RollbackProfile", "Combat/RollbackResolver", "Combat/RollbackResult", "Combat/AuthorityComponent",
	"Combat/AuthorityProfile", "Combat/AuthorityResolver", "Combat/AuthorityResult", "Events/EventBus",
	"Events/EventTypes", "Events/APIContext", "Events/APIResult", "Events/APIError",
	"Events/ExternalFactJournal", "Plugins/Plugin", "Plugins/PluginProfile", "Plugins/PluginResolver", "Plugins/PluginContext",
}
for _, path in ipairs(documentedModules) do
	local moduleScript = moduleAt(path)
	check(moduleScript ~= nil, "Documented module exists: " .. path)
	local ok, value = pcall(require, moduleScript)
	check(ok and value ~= nil, "Documented module loads: " .. path)
end

-- Public entry-point names in API.md must exist, and World methods named in that page are checked.
local CombatAPI = require(Shared.CombatAPI)
for _, method in ipairs({ "CreateWorld", "GetContext", "GetAPIContext", "IsWorld", "GetPluginResolver",
	"RegisterPlugin", "StartPlugin", "StopPlugin", "EnablePlugin", "DisablePlugin", "UnregisterPlugin" }) do
	check(type(CombatAPI[method]) == "function", "Documented CombatAPI method exists: " .. method)
end
for _, export in ipairs({ "APIContext", "EventTypes", "APIResult", "APIError", "Plugin", "PluginProfile", "PluginState" }) do
	check(CombatAPI[export] ~= nil, "Documented CombatAPI export exists: " .. export)
end
check(CombatAPI.CombatActionCatalog ~= nil and CombatAPI.ReplayRecording ~= nil,
	"Public API exposes the versioned action catalog and replay recording contracts")
check(CombatAPI.Contracts.CombatActionCatalog == CombatAPI.CombatActionCatalog.Version
	and CombatAPI.Contracts.ReplayRecording == CombatAPI.ReplayRecording.Version,
	"Public contract versions match the exported catalog and replay modules")

local World = require(Shared.Core.World)
for _, method in ipairs({
	"CreateEntity", "GetEntity", "HasEntity", "DestroyEntity", "GetEntities", "GetEvents", "GetCombatAPI",
	"GetAPIContext", "GetPluginResolver", "SetCollisionWorld", "GetCollisionWorld", "GetSimulation", "SetSimulation",
	"GetDamageResolver", "GetReactionResolver", "GetDefenseResolver", "GetCombatResolver", "GetCombatResolutionEvents",
	"GetCounterResults", "GetMotionResolver", "GetMotionResults", "GetDamageRequests", "GetDamageEvents",
	"GetHealthChangedEvents", "GetDeathEvents", "GetDefenseEvents", "GetHitstopResolver", "GetTimeEffectResults",
	"GetStatusEffectResolver",
	"GetProtectionResolver", "GetProtectionResults", "GetArmorResolver", "GetArmorResults", "GetGuardResolver",
	"GetGuardEvents", "GetGuardResults", "GetComboResolver", "GetComboEvents", "GetComboResults", "GetJuggleResolver",
	"GetJuggleEvents", "GetJuggleResults", "GetMovementStateResolver", "GetCancelResolver", "GetCancelEvents",
	"GetCancelResults", "GetInputResolver", "GetInputEvents", "GetCharacterResolver", "GetCharacterEvents",
	"GetCharacterResults", "GetAnimationResolver", "GetAnimationEvents", "GetAnimationResults", "GetNetworkResolver",
	"GetNetworkEvents", "GetNetworkResults", "GetPredictionResolver", "GetPredictionEvents", "GetPredictionResults",
	"GetRollbackResolver", "GetRollbackEvents", "GetRollbackResults", "GetAuthorityResolver", "GetAuthorityEvents",
	"GetAuthorityResults", "GetCombatPipeline", "GetCombatActionEvents", "GetCombatActionResults",
	"GetExternalFactJournal",
	"GetReconciliationResolver", "GetReconciliationResults",
	"Update", "Step", "Clear", "Destroy",
}) do
	check(type(World[method]) == "function", "Documented World method exists: " .. method)
end

-- Every test path used by the test inventory is mounted in the Server folder.
local documentedTests = {
	"SimulationTest.lua", "CombatDeterminismTest.lua", "CoreTest.lua",
	"CombatTest.lua", "CombatActionProfilesTest.lua", "CombatAnimationTest.lua",
	"CombatArmorTest.lua", "CombatAttackCatalogRollbackTest.lua",
	"CombatAttackCustomDataTest.lua", "CombatAttackPropertiesTest.lua", "CombatAPITypesTest.lua", "CombatAuthorityTest.lua",
	"CombatCancelRollbackIntegrationTest.lua", "CombatCancelTest.lua",
	"CombatCharacterTest.lua", "CombatCollisionRollbackTest.lua",
	"CombatComboRollbackTest.lua", "CombatComboTest.lua",
	"CombatCounterRollbackIntegrationTest.lua", "CombatCounterTest.lua",
	"CombatCustomStatusRollbackTest.lua", "CombatCustomDataReplayTest.lua", "CombatPublicSurfaceTest.lua", "CombatAPIPublicContractTest.lua", "CombatDamageRollbackIntegrationTest.lua",
	"CombatDefenseRollbackIntegrationTest.lua", "CombatDefenseTest.lua",
	"CombatDocumentationExamplesTest.lua", "CombatDocumentationTest.lua",
	"CombatEventAPITest.lua", "CombatExternalEffectGateTest.lua",
	"CombatExternalFactJournalTest.lua", "CombatGameplayComponentsRollbackTest.lua",
	"CombatGuardTest.lua", "CombatHitHistoryRollbackTest.lua",
	"CombatInputTest.lua", "CombatJuggleRollbackTest.lua",
	"CombatMotionTest.lua", "CombatMovementComponentsRollbackTest.lua",
	"CombatMovementStateTest.lua", "CombatNetworkingTest.lua",
	"CombatPipelineTest.lua", "CombatPluginTest.lua", "CombatPluginErrorMappingTest.lua",
	"CombatPredictionTest.lua", "CombatProtectionTest.lua",
	"CombatReactionResolverRollbackTest.lua", "CombatReactionTest.lua",
	"CombatReconciliationTest.lua", "CombatReplayRecordingTest.lua",
	"CombatResolutionTest.lua", "CombatRestoreCoordinatorTest.lua",
	"CombatRobloxRemoteEventAdapterTest.lua", "CombatRollbackEventReplayTest.lua",
	"CombatRollbackTest.lua", "CombatStateSchemaCollisionIntegrationTest.lua",
	"CombatStateSchemaTest.lua", "CombatStatusContainerRollbackTest.lua",
	"CombatStatusEffectsTest.lua", "CombatTimeEffectTest.lua",
	"CombatTopologyRebuildRollbackTest.lua", "HitstopComponentRollbackTest.lua",
	"HitstopResolverRollbackTest.lua",
}
local mountedTestModules = {}
for _, child in ipairs(ServerTests:GetChildren()) do
	if child:IsA("ModuleScript") and string.match(child.Name, "Test$") then
		mountedTestModules[child.Name] = true
	end
end
local mountedTestCount = 0
for _ in pairs(mountedTestModules) do mountedTestCount += 1 end
check(mountedTestCount == #documentedTests,
	"Documented test inventory matches all distinct mounted test module names")
for _, testName in ipairs(documentedTests) do
	local instanceName = string.gsub(testName, "%.lua$", "")
	check(mountedTestModules[instanceName] == true,
		"Documented test module exists: " .. testName)
end
local smokeTest = ServerTests:FindFirstChild("CombatMultiplayerSmokeTest")
check(smokeTest ~= nil and smokeTest:IsA("Script"),
	"Multiplayer smoke test remains a separately gated server script")

local EventTypes = require(Shared.Events.EventTypes)
local seenEvents = {}
for name, value in pairs(EventTypes) do
	check(type(name) == "string" and type(value) == "string", "Public EventTypes use string names and values")
	check(not seenEvents[value], "Public EventType is unique: " .. value)
	seenEvents[value] = true
end
for _, eventName in ipairs({ "EntityCreated", "EntityDestroyed", "HitConfirmed", "HitRejected", "DamageApplied",
	"HealApplied", "StatusEffectApplied",
	"Death", "Block", "Parry", "GuardBreak", "ComboStarted", "ComboUpdated", "ComboEnded", "JuggleStarted",
	"JuggleEnded", "MovementStateChanged", "CancelAllowed", "CancelRejected", "InputPressed", "InputReleased",
	"PredictionDiverged", "FrameConfirmed", "RollbackStarted", "RollbackCompleted", "RollbackFailed",
	"AuthorityInputAccepted", "AuthorityInputRejected", "AuthoritySnapshotPublished", "Clash", "ArmorApplied",
	"MotionApplied", "HitstopStarted", "HitstopEnded", "CounterHit", "ProtectionApplied", "PluginRegistered",
	"PluginInitializing", "PluginStarted", "PluginStopping", "PluginStopped", "PluginFailed", "PluginEnabled",
	"PluginDisabled", "PluginDependencyFailed", "PluginCapabilityRegistered", "PluginCapabilityUnregistered" }) do
	check(EventTypes[eventName] == eventName, "Documented public event exists: " .. eventName)
end

-- Architecture contracts documented as stable boundaries.
local EntityState = require(Shared.Core.EntityState)
check(EntityState.Alive ~= nil and EntityState.Dead ~= nil, "Core exposes Alive and Dead")
check(EntityState.Attacking == nil and EntityState.Blocking == nil and EntityState.Parrying == nil,
	"Combat actions are not Core entity states")
local firstWorld, secondWorld = CombatAPI.CreateWorld(), CombatAPI.CreateWorld()
check(CombatAPI.IsWorld(firstWorld), "CombatAPI-created value is a World")
check(firstWorld ~= secondWorld, "World is an independent context")
check(firstWorld:GetEvents() == firstWorld:GetCombatAPI():GetEvents(), "World exposes one shared EventBus")
check(firstWorld:GetPluginResolver() ~= secondWorld:GetPluginResolver(), "Plugin registry is World-scoped")
check(firstWorld:GetCollisionWorld() == nil, "CollisionWorld is an explicit optional setup")
check(firstWorld:GetArmorResolver() ~= nil and firstWorld:GetComboResolver() ~= nil,
	"World-owned systems are immediately available")
check(firstWorld:GetDamageResolver() == nil, "Collision-derived resolver awaits CollisionWorld setup")
firstWorld:Destroy(); secondWorld:Destroy()

assertions = assertions
print("Combat documentation tests passed (" .. tostring(assertions) .. " assertions)")

end
