return function()
-- Phase 3: pending Hitstop requests are captured by stable IDs and restored without replaying outputs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local HitstopRequest = require(Shared.Combat.HitstopRequest)

local world = World.new()
local source = world:CreateEntity()
local target = world:CreateEntity()
local resolver = world.HitstopResolver
resolver.Frame = 12
resolver:Submit(HitstopRequest.new({ Source = source, Target = target, Frames = 7, Priority = 3 }))
local snapshot = resolver:CaptureRollbackState()
local valid, reason = resolver:ValidateRollbackState(snapshot)
assert(valid, "Captured Hitstop state must validate: " .. tostring(reason))

resolver:Clear()
resolver.Frame = 99
local commit, prepareError = resolver:PrepareRollbackRestore(snapshot)
assert(type(commit) == "function", "Hitstop restore preparation failed: " .. tostring(prepareError))
commit()
assert(resolver.Frame == 12, "Hitstop frame was not restored")
assert(#resolver.PendingRequests == 1, "Pending Hitstop request was not restored")
assert(resolver.PendingRequests[1].Target == target, "Hitstop target reference was not resolved")
assert(resolver.PendingRequests[1].Source == source, "Hitstop source reference was not resolved")
assert(resolver.PendingRequests[1].Frames == 7 and resolver.PendingRequests[1].Priority == 3,
	"Hitstop request data was not restored")
assert(#resolver.Results == 0, "Restore must clear output results")

local invalid = { Version = 1, Frame = 12, PendingRequests = {
	{ TargetEntityId = target.Id, Frames = 1.5, Priority = 0 },
} }
local invalidOk = resolver:ValidateRollbackState(invalid)
assert(not invalidOk, "Fractional Hitstop frame count must be rejected")

local missing = { Version = 1, Frame = 12, PendingRequests = {
	{ TargetEntityId = "missing-target", Frames = 2, Priority = 0 },
} }
local missingCommit = resolver:PrepareRollbackRestore(missing)
assert(missingCommit == nil, "Missing target reference must be rejected during preparation")

world:Destroy()
print("HitstopResolverRollbackTest: PASS")

end
