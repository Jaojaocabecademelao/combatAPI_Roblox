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
local inspectedFrame, inspectError = imported:GetFrame(1)
check(inspectedFrame ~= nil and inspectedFrame.Inputs.EntityId == 12
	and inspectedFrame.StateHash == "state-a", tostring(inspectError))
inspectedFrame.Inputs.EntityId = 99
check(imported:GetFrame(1).Inputs.EntityId == 12,
	"Replay frame inspection returns a defensive copy")
local inspectedRange, rangeError = imported:GetFrameRange(1, 2)
check(inspectedRange ~= nil and #inspectedRange == 2
	and inspectedRange[1].Frame == 1 and inspectedRange[2].Frame == 2,
	tostring(rangeError))
inspectedRange[1].ExternalFacts.Facts = 99
check(imported:GetFrame(1).ExternalFacts.Facts == 1,
	"Replay frame range returns defensive copies")
local missingInspection, missingInspectionCode = imported:GetFrame(0)
check(missingInspection == nil and missingInspectionCode == "FrameNotFound",
	"Replay frame lookup reports unavailable frames explicitly")
local invalidInspection, invalidInspectionCode = imported:GetFrame(1.5)
check(invalidInspection == nil and invalidInspectionCode == "InvalidFrame",
	"Replay frame lookup rejects fractional frames explicitly")
local invalidRange, invalidRangeCode = imported:GetFrameRange(2, 1)
check(invalidRange == nil and invalidRangeCode == "InvalidFrameRange",
	"Replay frame range rejects reversed bounds explicitly")
local unavailableRange, unavailableRangeCode = imported:GetFrameRange(1, 3)
check(unavailableRange == nil and unavailableRangeCode == "FrameNotFound",
	"Replay frame range rejects partially unavailable ranges")
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
check(inputFrame == 1 and inputDetail.Reason == "InputMismatch"
	and inputDetail.ExpectedInputs.EntityId == 12
	and next(inputDetail.ActualInputs) == nil,
	"Replay comparison reports the first divergent input frame even when its state hash matches")
inputDetail.ExpectedInputs.EntityId = 99
check(imported:GetFrame(1).Inputs.EntityId == 12,
	"Replay divergence details do not expose internal input tables")
local factDiverged = Recording.new({
	Metadata = { ContentFingerprint = "build-42", StartFrame = 0, Seed = 7 },
	InitialState = { Frame = 0, Health = 100 },
	ExternalFacts = externalFacts,
})
factDiverged:AppendFrame(1, { EntityId = 12, Inputs = { Light = "Pressed" } }, "state-a",
	{ Frame = 1, Facts = 2 })
local factsFrame, factsDetail = imported:FindFirstDivergence(factDiverged)
check(factsFrame == 1 and factsDetail.Reason == "ExternalFactsMismatch"
	and factsDetail.ExpectedExternalFacts.Facts == 1
	and factsDetail.ActualExternalFacts.Facts == 2,
	"Replay comparison includes copies of divergent per-frame external facts")
local initialStateDiverged = Recording.new({
	Metadata = { ContentFingerprint = "build-42", StartFrame = 0, Seed = 7 },
	InitialState = { Frame = 0, Health = 90 },
	ExternalFacts = externalFacts,
})
local initialFrame, initialDetail = imported:FindFirstDivergence(initialStateDiverged)
check(initialFrame == 0 and initialDetail.Reason == "InitialStateMismatch"
	and initialDetail.ExpectedState.Health == 100
	and initialDetail.ActualState.Health == 90,
	"Replay comparison includes copies of divergent initial states")
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
check(missingFrame == 2 and missingDetail.Reason == "MissingFrame"
	and missingDetail.ExpectedFrame.Frame == 2 and missingDetail.ActualFrame == nil,
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
