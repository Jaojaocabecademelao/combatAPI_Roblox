return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local Status = require(Shared.Combat.Status)
local StatusCatalog = require(Shared.Combat.StatusCatalog)
local StatusContainer = require(Shared.Combat.StatusContainer)
local CombatStateSchema = require(Shared.Combat.CombatStateSchema)

local function check(value, message)
	assert(value, message)
end

local Mark = {}
Mark.__index = Mark
Mark.RollbackTypeId = "Game.Mark"
Mark.RollbackVersion = 1
Mark.RollbackCustomStateContract = true
setmetatable(Mark, { __index = Status })

function Mark.new()
	local status = Status.new({
		Name = "Mark", DurationFrames = 8, ReapplicationPolicy = "Stack",
		Tags = { "Debuff", "Control.Root" }, Modifiers = { MoveSpeed = -0.25 },
	})
	status.Counter = 0
	return setmetatable(status, Mark)
end

function Mark:Update()
	self.Counter += 1
end

function Mark:CaptureCustomRollbackState()
	return { Counter = self.Counter }
end

function Mark:ValidateCustomRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or type(state.Counter) ~= "number"
		or state.Counter < 0 or state.Counter % 1 ~= 0 then return false, "Invalid Mark counter" end
	for key in pairs(state) do if key ~= "Counter" then return false, "Unknown Mark state field" end end
	return true
end

function Mark:RestoreCustomRollbackState(state)
	self.Counter = state.Counter
	return true
end

local catalog = StatusCatalog.new()
catalog:Register("Game.Mark", 1, function() return Mark.new() end)
catalog:Seal()
local world = World.new()
local simulation = Simulation.new(world)
local source = world:CreateEntity()
local target = world:CreateEntity()
local container = target:AddComponent(StatusContainer.new(catalog))
local mark = Mark.new()
mark.Source = source
mark.Counter = 7
container:AddStatus(mark)
check(container:HasTag("Debuff") and container:HasTag("Control.Root"),
	"Status tags are queryable by gameplay systems")
check(container:GetModifier("MoveSpeed") == -0.25,
	"Status numeric modifiers are exposed through deterministic additive aggregation")
local schema = CombatStateSchema.new()
schema:RegisterComponent(StatusContainer.RollbackKey, function()
	return StatusContainer.new(catalog)
end)
simulation:Step()
local snapshot = schema:Capture(world)
local sourceId, targetId = source.Id, target.Id
local saved = snapshot.Entities[2].Components[1].State
local customRecord
for _, record in ipairs(saved.Statuses) do
	if record.TypeId == "Game.Mark" then customRecord = record end
end
check(customRecord and customRecord.TypeVersion == 1 and customRecord.CustomState.Counter == 8,
	"Versioned custom state should be present in the captured snapshot")
mark.Counter = 99
local restored, detail = schema:Restore(world, snapshot)
check(restored, "Custom status restore failed: " .. tostring(detail))
local restoredSource = world:GetEntity(sourceId)
local restoredContainer = world:GetEntity(targetId):GetComponent(StatusContainer)
local restoredMark = restoredContainer:GetStatus("Mark")
check(restoredMark and restoredMark.Source == restoredSource and restoredMark.Counter == 8,
	"Custom state and staged source reference must restore")
local secondMark = Mark.new()
restoredContainer:AddStatus(secondMark)
check(restoredContainer:GetModifier("MoveSpeed") == -0.5,
	"Stacked statuses add their numeric modifiers")
check(restoredContainer:RemoveByTag("Debuff", "Cleansed") == 2
	and not restoredContainer:HasTag("Control.Root")
	and restoredContainer:GetModifier("MoveSpeed") == 0,
	"Tag cleanse removes every matching stack and clears its modifiers")

local incompatibleCatalog = StatusCatalog.new()
incompatibleCatalog:Register("Game.Mark", 2, function() return Mark.new() end)
local incompatibleContainer = StatusContainer.new(incompatibleCatalog)
check(incompatibleContainer:ValidateRollbackState(saved) == false,
	"A different registered factory version must reject the snapshot")
local invalidCustom = table.clone(saved)
invalidCustom.Statuses = table.clone(saved.Statuses)
for index, record in ipairs(invalidCustom.Statuses) do
	if record.TypeId == "Game.Mark" then
		invalidCustom.Statuses[index] = table.clone(record)
		invalidCustom.Statuses[index].CustomState = { Counter = -1 }
	end
end
check(restoredContainer:ValidateRollbackState(invalidCustom) == false,
	"Custom status must validate its own serialized fields")

local Untracked = {}
Untracked.__index = Untracked
Untracked.RollbackTypeId = "Game.Untracked"
Untracked.RollbackVersion = 1
setmetatable(Untracked, { __index = Status })
function Untracked.new()
	return setmetatable(Status.new({ Name = "Untracked", DurationFrames = 3 }), Untracked)
end
local untrackedCatalog = StatusCatalog.new()
untrackedCatalog:Register("Game.Untracked", 1, function() return Untracked.new() end)
local unsupported, unsupportedDetail = untrackedCatalog:Create("Game.Untracked", 1)
check(unsupported == nil and string.find(unsupportedDetail, "RollbackCustomStateContract") ~= nil,
	"Custom factories without an explicit state contract must be rejected")

world:Destroy()
print("CombatCustomStatusRollbackTest: PASS")

end
