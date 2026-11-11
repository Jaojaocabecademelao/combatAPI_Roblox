return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local Simulation = require(Shared.Simulation.Simulation)
local Profiles = require(Shared.Combat.CombatActionProfiles)
local Result = require(Shared.Combat.CombatActionResult)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Action profile assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local world = World.new()
local simulation = Simulation.new(world)
local entity = world:CreateEntity()
local pipeline = world:GetCombatPipeline()
local definitions = { Profiles.Melee(), Profiles.Projectile(), Profiles.AreaOfEffect() }
local instant = require(Shared.Combat.CombatActionDefinition).new({
	Id = "test.instant", DurationModel = "Instant",
})
local persistent = require(Shared.Combat.CombatActionDefinition).new({
	Id = "test.persistent", DurationModel = "Persistent", Cancelable = true,
})
table.insert(definitions, instant)
table.insert(definitions, persistent)

for _, definition in ipairs(definitions) do
	check(pipeline:RegisterDefinition(definition), "Profile definition registers: " .. definition.Id)
	local totalFrames = definition:GetTotalFrames()
	check(definition.DurationModel == "Persistent" or
		(totalFrames ~= nil and totalFrames >= definition.ActiveFrames),
		"Profile definition has a valid duration: " .. definition.Id)
end

for _, definition in ipairs(definitions) do
	local started = pipeline:Start(entity, definition.Id, world.CurrentFrame)
	check(started.Type == Result.Type.Started, "Profile action starts: " .. definition.Id)
	if definition.DurationModel == "Persistent" then
		simulation:Step()
		check(pipeline:GetAction(entity) ~= nil, "Persistent action remains active")
		check(pipeline:Cancel(entity, world.CurrentFrame).Type == Result.Type.Cancelled,
			"Persistent action can be cancelled")
	else
		for _ = 1, definition:GetTotalFrames() do simulation:Step() end
	end
	check(pipeline:GetAction(entity) == nil or pipeline:GetAction(entity):IsFinished(),
		"Profile action completes: " .. definition.Id)
end

world:Destroy()
print(("CombatActionProfilesTest: PASS (%d assertions)"):format(assertions))

end
