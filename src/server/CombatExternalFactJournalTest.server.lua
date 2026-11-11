local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)

local assertions = 0
local function check(value, message)
	assert(value, message or ("External fact journal assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local world = World.new({ ExternalFacts = { MaxFacts = 8 } })
Simulation.new(world)
local journal = world:GetExternalFactJournal()
local queryCalls = 0
local request = { Origin = { 1, 2, 3 }, Radius = 0.5 }
local outcome = journal:Resolve(0, "projectile:17:environment", "geometry.mock", "1",
	request, function()
		queryCalls += 1
		return { Hit = true, Distance = 4, ObjectId = "wall:2" }
	end)
check(outcome and outcome.Hit and queryCalls == 1, "Normal execution records a serializable external result")

world:SetExecutionContext("Replay")
local replayed = journal:Resolve(0, "projectile:17:environment", "geometry.mock", "1",
	request, function()
		queryCalls += 1
		return { Hit = false }
	end)
check(replayed and replayed.Hit and queryCalls == 1,
	"Replay returns the captured result without executing the current-world query")
local missing, missingReason = journal:Resolve(1, "projectile:17:environment", "geometry.mock", "1",
	request, function()
		queryCalls += 1
		return { Hit = false }
	end)
check(missing == nil and missingReason == "MissingExternalFact" and queryCalls == 1,
	"Replay fails explicitly when the frame has no captured fact")
local mismatch, mismatchReason = journal:Resolve(0, "projectile:17:environment", "geometry.mock", "2",
	request, function() error("Replay must not query") end)
check(mismatch == nil and mismatchReason == "ExternalFactAdapterMismatch",
	"Replay rejects an adapter version mismatch")
local requestMismatch, requestMismatchReason = journal:Resolve(0, "projectile:17:environment",
	"geometry.mock", "1", { Origin = { 9, 2, 3 }, Radius = 0.5 }, function()
		error("Replay must not query")
	end)
check(requestMismatch == nil and requestMismatchReason == "ExternalFactRequestMismatch",
	"Replay rejects query parameters that differ from the recorded request")
world:SetExecutionContext("Normal")

local saved = journal:Capture()
local copyWorld = World.new({ ExternalFacts = { MaxFacts = 8 } })
local copyJournal = copyWorld:GetExternalFactJournal()
local imported, importError = copyJournal:Import(saved)
check(imported, tostring(importError))
check(copyJournal:Read(0, "projectile:17:environment", "geometry.mock", "1", request).ObjectId == "wall:2",
	"Captured external facts round-trip through the versioned journal format")
local before = copyJournal:Capture()
local invalidImport = table.clone(saved)
invalidImport.Version = saved.Version + 1
local accepted, reason = copyJournal:Import(invalidImport)
check(not accepted and reason == "UnsupportedExternalFactJournalVersion",
	"Incompatible future journal versions are rejected without migration")
check(copyJournal:Capture().Facts[1].Outcome.ObjectId == before.Facts[1].Outcome.ObjectId,
	"Rejected import does not mutate the existing journal")
local duplicate, duplicateReason = journal:Record(0, "projectile:17:environment",
	"geometry.mock", "1", request, { Hit = true })
check(not duplicate and duplicateReason == "DuplicateExternalFact",
	"A frame/query identity can only be recorded once")
world:SetExecutionContext("Replay")
local forbiddenRecord, forbiddenReason = journal:Record(2, "query", "geometry.mock", "1",
	{}, { Hit = false })
check(not forbiddenRecord and forbiddenReason == "CannotRecordExternalFactDuringReplay",
	"Replay cannot replace historical external facts")
world:SetExecutionContext("Normal")

check(journal:PruneBefore(1), "Journal supports explicit retention pruning")
local pruned, prunedReason = journal:Read(0, "projectile:17:environment", "geometry.mock", "1", request)
check(pruned == nil and prunedReason == "MissingExternalFact", "Pruning removes facts before the requested frame")

copyWorld:Destroy()
world:Destroy()
print(("CombatExternalFactJournalTest: PASS (%d assertions)"):format(assertions))
