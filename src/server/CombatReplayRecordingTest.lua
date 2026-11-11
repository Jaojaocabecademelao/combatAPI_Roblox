return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Recording = require(Shared.Simulation.ReplayRecording)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Replay recording assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local externalFacts = {
	Version = 1,
	Facts = {
		{ Frame = 1, QueryId = "projectile:1:wall", AdapterId = "geometry.mock",
			AdapterVersion = 1, Request = { Radius = 2 }, Outcome = { Hit = false } },
	},
}
local recording = Recording.new({
	Metadata = { ContentFingerprint = "build-42", StartFrame = 0, Seed = 7 },
	InitialState = { Frame = 0, Health = 100 },
	ExternalFacts = externalFacts,
})
recording:AppendFrame(1, { EntityId = 12, Inputs = { Light = "Pressed" } }, "state-a",
	{ Frame = 1, Facts = 1 })
recording:AppendFrame(2, {}, "state-b")
check(not pcall(function() recording:AppendFrame(4, {}, "state-c") end),
	"Replay frames must be contiguous and ordered")

local exported = recording:Capture()
local imported, importError = Recording.FromSnapshot(exported)
check(imported ~= nil, tostring(importError))
check(imported:Capture().ExternalFacts.Facts[1].Outcome.Hit == false
	and imported.Frames[1].Inputs.EntityId == 12,
	"Replay recording round-trips inputs, initial state and external facts")
local sameFrameState = Recording.new({
	Metadata = { ContentFingerprint = "build-42", StartFrame = 0, Seed = 7 },
	InitialState = { Frame = 0, Health = 100 },
	ExternalFacts = externalFacts,
})
sameFrameState:AppendFrame(1, { EntityId = 12, Inputs = { Light = "Pressed" } }, "state-a",
	{ Frame = 1, Facts = 1 })
sameFrameState:AppendFrame(2, {}, "state-diverged")
local divergedFrame, divergence = imported:FindFirstDivergence(sameFrameState)
check(divergedFrame == 2 and divergence.Reason == "StateHashMismatch"
	and divergence.ExpectedHash == "state-b" and divergence.ActualHash == "state-diverged",
	"Replay comparison reports the first divergent state frame")
local inputDiverged = Recording.new({
	Metadata = { ContentFingerprint = "build-42", StartFrame = 0, Seed = 7 },
	InitialState = { Frame = 0, Health = 100 },
	ExternalFacts = externalFacts,
})
inputDiverged:AppendFrame(1, {}, "state-a", { Frame = 1, Facts = 1 })
local inputFrame, inputDetail = imported:FindFirstDivergence(inputDiverged)
check(inputFrame == 1 and inputDetail.Reason == "InputMismatch",
	"Replay comparison reports the first divergent input frame even when its state hash matches")
local matching = Recording.FromSnapshot(exported)
local noDivergence = imported:FindFirstDivergence(matching)
check(noDivergence == nil, "Equivalent recordings have no divergent frame")
local shorter = Recording.new({
	Metadata = { ContentFingerprint = "build-42", StartFrame = 0, Seed = 7 },
	InitialState = { Frame = 0, Health = 100 },
	ExternalFacts = externalFacts,
})
shorter:AppendFrame(1, { EntityId = 12, Inputs = { Light = "Pressed" } }, "state-a",
	{ Frame = 1, Facts = 1 })
local missingFrame, missingDetail = imported:FindFirstDivergence(shorter)
check(missingFrame == 2 and missingDetail.Reason == "MissingFrame",
	"Replay comparison identifies a missing frame")

local oldSnapshot = {
	Version = 0,
	Metadata = { ContentFingerprint = "build-42", StartFrame = 0 },
	InitialState = { Frame = 0 },
	Frames = {},
}
local migrated, migrationError = Recording.FromSnapshot(oldSnapshot, {
	[0] = function(snapshot)
		snapshot.Version = 1
		return snapshot
	end,
})
check(migrated ~= nil, tostring(migrationError))
local unsupported = table.clone(exported)
unsupported.Version = Recording.Version + 1
local rejected, rejectReason = Recording.FromSnapshot(unsupported)
check(rejected == nil and rejectReason == "UnsupportedReplayRecordingVersion",
	"Unknown replay versions fail unless an explicit migration is provided")
local wrongContent = Recording.new({
	Metadata = { ContentFingerprint = "other-build", StartFrame = 0 },
	InitialState = { Frame = 0, Health = 100 },
})
local noComparableFrame, contentReason = imported:FindFirstDivergence(wrongContent)
check(noComparableFrame == nil and contentReason == "ContentFingerprintMismatch",
	"Replay comparison refuses to compare different content fingerprints")

print(("CombatReplayRecordingTest: PASS (%d assertions)"):format(assertions))

end
