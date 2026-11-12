return function()
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CombatAPI = require(Shared.CombatAPI)
local Simulation = require(Shared.Simulation.Simulation)
local Input = require(Shared.Combat.Input)
local InputState = require(Shared.Combat.InputState)
local InputComponent = require(Shared.Combat.InputComponent)
local PredictionResult = require(Shared.Combat.PredictionResult)
local Hitbox = require(Shared.Combat.Hitbox)
local Hurtbox = require(Shared.Combat.Hurtbox)
local CollisionQuery = require(Shared.Combat.CollisionQuery)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Documentation example assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

check(CombatAPI.Version == 1 and CombatAPI.Contracts.NetworkMessage == 1
	and CombatAPI.Contracts.CombatActionDefinition == 2
	and CombatAPI.Contracts.CombatActionCatalog == 2
	and CombatAPI.Contracts.ReplayRecording == 1,
	"Public contract versions are exposed")

-- Runnable World/Event/Input/Simulation example, with observation subscribed before creation.
local world = CombatAPI.CreateWorld()
local created = {}
local subscription, subscribeError = world:GetEvents():Subscribe("EntityCreated", function(event)
	created[#created + 1] = event
end)
check(subscription ~= nil and subscribeError == nil, "Event subscription succeeds")
local entity = world:CreateEntity()
check(entity ~= nil and world:GetEntity(entity.Id) == entity, "World creates and indexes an entity")
check(#created == 1 and created[1].EntityId == entity.Id, "Pre-registered listener observes entity creation")
entity:AddComponent(InputComponent.new())
check(entity:GetComponent(InputComponent) ~= nil, "Example component attaches")
local inputResolver = world:GetInputResolver()
for frame, inputId in ipairs({ Input.Light, Input.Medium, Input.Heavy, Input.Special, Input.Guard,
	Input.Jump, Input.Dash, Input.Forward, Input.Back, Input.Up, Input.Down, Input.Left, Input.Right }) do
	local inputFrame = inputResolver:SetInput(entity, inputId, InputState.Pressed, frame, { Source = "DocumentationExample" })
	check(inputFrame ~= nil and inputFrame.Frame == frame, "Input resolver records frame " .. tostring(frame))
	check(inputResolver:IsPressed(entity, inputId), "Input query recognizes " .. inputId)
	check(inputResolver:GetInputFrame(entity, frame) ~= nil, "Input history retains frame " .. tostring(frame))
end
local simulation = Simulation.new(world, { Seed = 17 })
check(simulation:GetWorld() == world and world:GetSimulation() == simulation, "Simulation associates with World")
simulation:Step()
check(simulation:GetGameTime():GetFrame() == 1, "One fixed step advances one simulation frame")
check(world.CurrentFrame == 1, "World receives the fixed simulation frame")
check(inputResolver:GetEvents()[1] ~= nil, "Input actions produce typed input events")
subscription:Disconnect()
check(not subscription:IsConnected(), "Event subscription can be disconnected")
world:Destroy()
check(world.Destroyed, "World cleanup completes")

-- Prediction example uses the actual required frame arguments and typed Results.
local predictionWorld = CombatAPI.CreateWorld()
local predictedEntity = predictionWorld:CreateEntity()
local prediction = predictionWorld:GetPredictionResolver()
local enabled = prediction:Enable(predictedEntity)
check(enabled.Type == PredictionResult.Type.Success and enabled.Accepted, "Prediction Enable returns Success")
check(prediction:GetState(predictedEntity).Enabled, "Prediction state is enabled")
local began = prediction:Begin(predictedEntity, 0)
check(began.Type == PredictionResult.Type.Success and began.Frame == 0, "Prediction Begin seeds frame zero")
local advanced = prediction:Advance(predictedEntity, 1)
check(advanced.Type == PredictionResult.Type.Success and advanced.Predicted, "Advance records a predicted frame")
local predictionFrame = prediction:GetFrame(predictedEntity, 1)
check(predictionFrame ~= nil and predictionFrame.Frame == 1, "Prediction history returns frame one")
check(predictionFrame.Predicted and not predictionFrame.Confirmed, "Unconfirmed prediction status is represented")
local confirmed = prediction:Confirm(predictedEntity, 1)
check(confirmed.Type == PredictionResult.Type.Success, "Confirm returns Success")
check(prediction:GetFrame(predictedEntity, 1).Confirmed, "Confirmation updates retained frame")
check(#prediction:GetHistory(predictedEntity, 0, 1) == 2, "History query returns seeded and advanced frames")
check(prediction:GetEvents()[1] ~= nil and #prediction:GetResults() >= 4, "Prediction exposes events and results")
predictionWorld:Destroy()

-- The documented geometry distinction is executable without creating a Character or World.
local hitbox = Hitbox.new({ Shape = "Box", Position = Vector3.zero, Size = Vector3.new(2, 2, 2) })
local overlapping = Hurtbox.new({ Shape = "Box", Position = Vector3.new(1, 0, 0), Size = Vector3.new(2, 2, 2) })
local separated = Hurtbox.new({ Shape = "Box", Position = Vector3.new(4, 0, 0), Size = Vector3.new(2, 2, 2) })
check(CollisionQuery.Intersects(hitbox, overlapping), "Overlapping regions produce geometric contact")
check(CollisionQuery.Intersects(overlapping, hitbox), "Geometric query is symmetric")
check(not CollisionQuery.Intersects(hitbox, separated), "Separated regions are not contact")
check(hitbox.Owner == nil and overlapping.Owner == nil, "Standalone regions do not require Character ownership")

-- Identical inputs in two isolated worlds reproduce the documented deterministic setup.
local function trace()
	local replayWorld = CombatAPI.CreateWorld()
	local replaySimulation = Simulation.new(replayWorld, { Seed = 17 })
	local replayEntity = replayWorld:CreateEntity()
	replayEntity:AddComponent(InputComponent.new())
	local frame = replayWorld:GetInputResolver():SetInput(replayEntity, Input.Light, InputState.Pressed, 1, { Source = "Repeat" })
	local values = { tostring(replayEntity.Id), tostring(frame.Frame), tostring(frame.Inputs[Input.Light]) }
	replaySimulation:Step()
	values[#values + 1] = tostring(replaySimulation:GetGameTime():GetFrame())
	values[#values + 1] = tostring(replaySimulation:GetRNG():GetState())
	replayWorld:Destroy()
	return table.concat(values, "|")
end
local firstTrace, secondTrace = trace(), trace()
check(firstTrace == secondTrace, "Equivalent World setup produces the same API trace")
for index = 1, 5 do
	check(firstTrace:split("|")[index] == secondTrace:split("|")[index], "Trace field " .. tostring(index) .. " is repeatable")
end

print("Combat documentation examples tests passed (" .. tostring(assertions) .. " assertions)")

end
