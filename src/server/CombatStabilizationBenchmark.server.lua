local runBenchmark = script:GetAttribute("RunBenchmark")
assert(runBenchmark == nil or type(runBenchmark) == "boolean",
	"RunBenchmark attribute must be a boolean")
if runBenchmark ~= true then return end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local CollisionWorld = require(Shared.Combat.CollisionWorld)
local Hitbox = require(Shared.Combat.Hitbox)
local Hurtbox = require(Shared.Combat.Hurtbox)
local CombatStateSchema = require(Shared.Combat.CombatStateSchema)
local CollisionTopologyCatalog = require(Shared.Combat.CollisionTopologyCatalog)
local Serializer = require(Shared.Simulation.StateSerializer)

local function positiveIntegerAttribute(name, defaultValue, maximum)
	local value = script:GetAttribute(name)
	if value == nil then return defaultValue end
	assert(type(value) == "number" and value >= 1 and value <= maximum and value % 1 == 0,
		name .. " attribute must be a positive integer no greater than " .. tostring(maximum))
	return value
end

local ENTITY_COUNT = positiveIntegerAttribute("EntityCount", 32, 512)
local VOLUME_COUNT = positiveIntegerAttribute("VolumeCount", 64, 256)
local FRAME_COUNT = positiveIntegerAttribute("FrameCount", 30, 600)
local REPETITIONS = positiveIntegerAttribute("Repetitions", 3, 10)
local hitboxCount = math.floor(VOLUME_COUNT / 2)
local hurtboxCount = VOLUME_COUNT - hitboxCount
local estimatedCollisionPairChecks = hitboxCount * hurtboxCount * FRAME_COUNT * REPETITIONS * 2
local estimatedEntityFrameSteps = ENTITY_COUNT * FRAME_COUNT * REPETITIONS * 2
assert(estimatedCollisionPairChecks <= 1000000,
	"Benchmark workload is too large; reduce VolumeCount, FrameCount, or Repetitions")
assert(estimatedEntityFrameSteps <= 1000000,
	"Benchmark workload is too large; reduce EntityCount, FrameCount, or Repetitions")
local world = World.new()
local simulation = Simulation.new(world, { Seed = 90210 })
local collision = CollisionWorld.new(world)
local schema = CombatStateSchema.new()
local topology = CollisionTopologyCatalog.new()
topology:Register("benchmark.hitbox", 1, function(saved, owner)
	local options = {
		Id = saved.Id, Owner = owner, Shape = saved.Shape,
		Position = Vector3.new(saved.Position[1], saved.Position[2], saved.Position[3]),
		TopologyDefinitionId = "benchmark.hitbox",
		TopologyDefinitionVersion = 1,
	}
	if saved.Shape == "Sphere" then options.Radius = saved.Radius else
		options.Size = Vector3.new(saved.Size[1], saved.Size[2], saved.Size[3])
	end
	return Hitbox.new(options)
end)
topology:Register("benchmark.hurtbox", 1, function(saved, owner)
	local options = {
		Id = saved.Id, Owner = owner, Shape = saved.Shape,
		Position = Vector3.new(saved.Position[1], saved.Position[2], saved.Position[3]),
		TopologyDefinitionId = "benchmark.hurtbox",
		TopologyDefinitionVersion = 1,
	}
	if saved.Shape == "Sphere" then options.Radius = saved.Radius else
		options.Size = Vector3.new(saved.Size[1], saved.Size[2], saved.Size[3])
	end
	return Hurtbox.new(options)
end)
topology:Seal()
collision:SetTopologyCatalog(topology)
local entities = {}

for index = 1, ENTITY_COUNT do
	entities[index] = world:CreateEntity()
end
for index = 1, VOLUME_COUNT do
	local owner = entities[((index - 1) % ENTITY_COUNT) + 1]
	local position = Vector3.new(index * 4, 0, 0)
	if index % 2 == 0 then
		collision:RegisterHitbox(Hitbox.new({
			Id = 10000 + index, Owner = owner, Shape = "Sphere", Radius = 1,
			Position = position,
			TopologyDefinitionId = "benchmark.hitbox", TopologyDefinitionVersion = 1,
		}))
	else
		collision:RegisterHurtbox(Hurtbox.new({
			Id = 10000 + index, Owner = owner, Shape = "Sphere", Radius = 1,
			Position = position,
			TopologyDefinitionId = "benchmark.hurtbox", TopologyDefinitionVersion = 1,
		}))
	end
end

local function timed(callback)
	local start = os.clock()
	local result = callback()
	return os.clock() - start, result
end

local function averageTime(callback, setup)
	local total, result = 0, nil
	for _ = 1, REPETITIONS do
		if setup then setup() end
		local elapsed, value = timed(callback)
		total += elapsed
		result = value
	end
	return total / REPETITIONS, result
end

local captureTime, state = averageTime(function() return schema:Capture(world) end)
local serializeTime = averageTime(function() return Serializer.CloneSerializable(state) end)
local serializedSnapshot = Serializer.Serialize(state)
local snapshotBytes = #serializedSnapshot
local function stepFrames()
	local cpuSeconds = 0
	for _ = 1, FRAME_COUNT do
		local frameStart = os.clock()
		simulation:Step()
		cpuSeconds += os.clock() - frameStart
		task.wait()
	end
	return cpuSeconds
end
local function restoreInitialState()
	local ok, detail = schema:Restore(world, state)
	assert(ok, detail)
end
local function averageMeasuredTime(callback, setup)
	local total = 0
	for _ = 1, REPETITIONS do
		if setup then setup() end
		total += callback()
	end
	return total / REPETITIONS
end
local stepTime = averageMeasuredTime(stepFrames, restoreInitialState)
local replayTime = averageMeasuredTime(function()
	local restoreStart = os.clock()
	restoreInitialState()
	return os.clock() - restoreStart + stepFrames()
end)
local restored = true

local diagnostics = world:GetDiagnostics()
local rollbackMetrics = diagnostics.Rollback
local networkMetrics = diagnostics.Network
print(("CombatStabilizationBenchmark: {\"entities\":%d,\"volumes\":%d,\"frames\":%d,\"repetitions\":%d,\"estimatedCollisionPairChecks\":%d,\"snapshotBytes\":%d,\"captureSecondsMean\":%.6f,\"serializeSecondsMean\":%.6f,\"stepSecondsMean\":%.6f,\"restoreReplaySecondsMean\":%.6f,\"restored\":%s,\"rollback\":{\"snapshotsCaptured\":%d,\"rollbacksStarted\":%d,\"rollbacksCompleted\":%d,\"rollbacksFailed\":%d,\"replayFrames\":%d,\"historyFrames\":%d,\"historyCapacity\":%d},\"network\":{\"sent\":%d,\"received\":%d,\"rejected\":%d,\"duplicates\":%d,\"outOfOrder\":%d}}")
	:format(ENTITY_COUNT, VOLUME_COUNT, FRAME_COUNT, REPETITIONS, estimatedCollisionPairChecks, snapshotBytes,
		captureTime, serializeTime, stepTime, replayTime,
		tostring(restored), rollbackMetrics.SnapshotsCaptured, rollbackMetrics.RollbacksStarted,
		rollbackMetrics.RollbacksCompleted, rollbackMetrics.RollbacksFailed, rollbackMetrics.ReplayFrames,
		rollbackMetrics.HistoryFrames, rollbackMetrics.HistoryCapacity, networkMetrics.Sent,
		networkMetrics.Received, networkMetrics.Rejected, networkMetrics.Duplicates,
		networkMetrics.OutOfOrder))
world:Destroy()
