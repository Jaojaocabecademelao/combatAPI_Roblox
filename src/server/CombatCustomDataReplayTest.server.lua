local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Attack = require(Shared.Combat.Attack)
local AttackInstance = require(Shared.Combat.AttackInstance)
local AttackCatalog = require(Shared.Combat.AttackCatalog)
local World = require(Shared.Core.World)
local Serializer = require(Shared.Simulation.StateSerializer)
local StateHasher = require(Shared.Simulation.StateHasher)
local ReplayRecording = require(Shared.Simulation.ReplayRecording)

local assertions = 0
local function check(value, message)
	assert(value, message or ("CustomData replay assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local world = World.new()
local owner = world:CreateEntity()
local attack = Attack.new({
	Id = "custom-data-replay",
	Damage = 1,
	CustomData = { Radius = 1, Mode = "Charge" },
})
local catalog = AttackCatalog.new()
catalog:Register(attack, 1)
catalog:Seal()

-- The override is derived only from a deterministic frame/charge counter.
local function captureFrame(frame, reverseInsertionOrder)
	local override
	if reverseInsertionOrder then
		override = { ChargeFrames = frame, Radius = frame * 2 }
	else
		override = { Radius = frame * 2, ChargeFrames = frame }
	end
	local instance = AttackInstance.new(attack, owner, nil, {
		Id = "custom-data-instance",
		CustomDataOverrides = override,
	})
	return {
		Frame = frame,
		AttackInstances = {
			{
				Id = instance.Id,
				AttackId = attack.Id,
				CustomDataOverrides = Serializer.CloneSerializable(instance.CustomDataOverrides),
				EffectiveCustomData = Serializer.CloneSerializable(instance.OffensiveProperties.CustomData),
			},
		},
	}
end

local manifestFingerprint = Serializer.Serialize(catalog:CaptureManifest())
local first = ReplayRecording.new({
	Metadata = { ContentFingerprint = manifestFingerprint, StartFrame = 0, Seed = 11 },
	InitialState = { Frame = 0, CustomDataManifest = manifestFingerprint },
})
local second = ReplayRecording.new({
	Metadata = { ContentFingerprint = manifestFingerprint, StartFrame = 0, Seed = 11 },
	InitialState = { Frame = 0, CustomDataManifest = manifestFingerprint },
})

for frame = 1, 5 do
	local stateA = captureFrame(frame, false)
	local stateB = captureFrame(frame, true)
	local hashA = StateHasher.Hash(stateA)
	local hashB = StateHasher.Hash(stateB)
	check(hashA == hashB, "Equivalent frame-derived overrides must produce identical canonical hashes")
	first:AppendFrame(frame, { ChargeFrames = frame }, hashA)
	second:AppendFrame(frame, { ChargeFrames = frame }, hashB)
end

local divergenceFrame = first:FindFirstDivergence(second)
check(divergenceFrame == nil, "Equivalent CustomData recordings must replay without divergence")

-- Simulate a non-deterministic source (for example, wall-clock-derived data):
-- the same input frame now produces a different override and therefore a different state hash.
local divergent = ReplayRecording.new({
	Metadata = { ContentFingerprint = manifestFingerprint, StartFrame = 0, Seed = 11 },
	InitialState = { Frame = 0, CustomDataManifest = manifestFingerprint },
})
for frame = 1, 5 do
	local state = captureFrame(frame, false)
	if frame == 3 then
		state.AttackInstances[1].CustomDataOverrides.Radius += 1
		state.AttackInstances[1].EffectiveCustomData.Radius += 1
	end
	divergent:AppendFrame(frame, { ChargeFrames = frame }, StateHasher.Hash(state))
end
local mismatchFrame, mismatch = first:FindFirstDivergence(divergent)
check(mismatchFrame == 3 and mismatch.Reason == "StateHashMismatch",
	"A changed override for identical inputs must be reported as replay divergence")

local differentContent = ReplayRecording.new({
	Metadata = { ContentFingerprint = "different-attack-catalog", StartFrame = 0, Seed = 11 },
	InitialState = { Frame = 0 },
})
local noFrame, contentReason = first:FindFirstDivergence(differentContent)
check(noFrame == nil and contentReason == "ContentFingerprintMismatch",
	"Replay comparison must reject a different CustomData-bearing catalog fingerprint")

world:Destroy()
print(("CombatCustomDataReplayTest: PASS (%d assertions)"):format(assertions))
