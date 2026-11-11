return function()
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Core, Combat = Shared:WaitForChild("Core"), Shared:WaitForChild("Combat")
local World = require(Core.World)
local InputFrame = require(Combat.InputFrame)
local InputState = require(Combat.InputState)
local Input = require(Combat.Input)
local InputResolver = require(Combat.InputResolver)
local InputComponent = require(Combat.InputComponent)
local PredictionComponent = require(Combat.PredictionComponent)
local PredictionProfile = require(Combat.PredictionProfile)
local PredictionHistory = require(Combat.PredictionHistory)
local PredictionSnapshot = require(Combat.PredictionSnapshot)
local PredictionEvent = require(Combat.PredictionEvent)
local PredictionResult = require(Combat.PredictionResult)
local NetworkSnapshot = require(Combat.NetworkSnapshot)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Prediction assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local function rejected(result, kind)
	check(result.Type == kind and not result.Accepted, "Expected prediction result " .. kind)
end

local defaultProfile = PredictionProfile.new()
check(defaultProfile.MaxHistoryFrames == 120, "Default history capacity")
check(defaultProfile.MaxPredictionFrames == 8, "Default prediction limit")
check(defaultProfile.InputPolicy == PredictionProfile.InputPolicy.RepeatLast, "Default repeat-last policy")
local configuredProfile = PredictionProfile.new({
	MaxHistoryFrames = 4,
	MaxPredictionFrames = 2,
	InputPolicy = PredictionProfile.InputPolicy.Neutral,
})
check(configuredProfile.MaxHistoryFrames == 4, "Configured bounded history")
check(configuredProfile.MaxPredictionFrames == 2, "Configured prediction frame limit")
check(configuredProfile.InputPolicy == "Neutral", "Configured neutral input policy")
check(not pcall(function() PredictionProfile.new({ MaxHistoryFrames = 0 }) end), "Zero history rejected")
check(not pcall(function() PredictionProfile.new({ MaxHistoryFrames = 1.5 }) end), "Fractional history rejected")
check(not pcall(function() PredictionProfile.new({ MaxPredictionFrames = -1 }) end), "Negative limit rejected")
check(not pcall(function() PredictionProfile.new({ InputPolicy = "Random" }) end), "Unknown policy rejected")

local history = PredictionHistory.new(2)
check(history:Count() == 0, "History starts empty")
history:Put(4, "four")
history:Put(2, "two")
check(history:Get(4) == "four" and history:Has(2), "History indexes inserted frames")
history:Put(3, "three")
check(history:Count() == 2, "History enforces capacity")
check(history:Get(2) == nil and history:Get(3) == "three" and history:Get(4) == "four",
	"History evicts the oldest frame")
check(#history:GetWindow(3, 4) == 2, "History window is ordered and bounded")
history:Put(4, "updated")
check(history:Count() == 2 and history:Get(4) == "updated", "Replacing frame does not consume capacity")
history:Clear()
check(history:Count() == 0 and history:Get(3) == nil, "History clears all indexed frames")
check(not pcall(function() PredictionHistory.new(0) end), "Zero history capacity rejected")

local world = World.new({ PredictionProfile = configuredProfile })
local resolver = world:GetPredictionResolver()
check(resolver == world:GetPredictionResolver(), "World exposes a stable prediction resolver")
check(world:GetPredictionEvents() ~= nil and world:GetPredictionResults() ~= nil, "World exposes event and result lists")
local entity = world:CreateEntity()
check(world:GetPredictionResolver() == resolver, "World keeps resolver across entity creation")
check(resolver:GetState(entity) == nil, "Prediction is opt-in per entity")
rejected(resolver:Begin(entity, 0), PredictionResult.Type.InvalidEntity)
local noPredictionProfile = PredictionProfile.new({
	MaxHistoryFrames = 4, MaxPredictionFrames = 0, InputPolicy = "Neutral",
})
check(resolver:Enable(entity, noPredictionProfile).Accepted, "Entity prediction enables")
check(entity:GetComponent(PredictionComponent) ~= nil, "Enable attaches prediction component")
check(resolver:GetState(entity).Enabled, "Enabled state is recorded per entity")
rejected(resolver:Enable(entity), PredictionResult.Type.AlreadyEnabled)
rejected(resolver:Enable(entity, { InputPolicy = "Invalid" }), PredictionResult.Type.InvalidProfile)
rejected(resolver:Begin(entity, -1), PredictionResult.Type.InvalidFrame)
rejected(resolver:Begin(entity, 0, {}), PredictionResult.Type.InvalidInput)
check(resolver:Begin(entity, 0).Accepted, "Prediction lifecycle begins at the requested frame")
rejected(resolver:Begin(entity, 0), PredictionResult.Type.AlreadyStarted)
check(resolver:GetFrame(entity, 0).Confirmed, "Seed frame is confirmed")
check(resolver:GetFrame(entity, 0).Inputs ~= nil, "Seed frame has input abstraction")
rejected(resolver:Advance(entity, 1), PredictionResult.Type.MaxPredictionFrames)
check(resolver:Disable(entity).Accepted, "Prediction disables")
check(not resolver:GetState(entity).Enabled and not entity:GetComponent(PredictionComponent):IsEnabled(),
	"Disable updates resolver and component state")
rejected(resolver:Advance(entity, 1), PredictionResult.Type.AlreadyDisabled)
rejected(resolver:Disable(entity), PredictionResult.Type.AlreadyDisabled)
check(resolver:Enable(entity, noPredictionProfile).Accepted, "Disabled prediction re-enables")
rejected(resolver:Begin(entity, 1), PredictionResult.Type.AlreadyStarted)
check(resolver:Advance(entity, 1, InputFrame.new({
	Frame = 1, EntityId = entity.Id, Inputs = {},
})).Accepted, "Re-enabled prediction resumes on an actual input frame")

local limited = world:CreateEntity()
check(resolver:Enable(limited).Accepted, "Second entity prediction enables")
check(resolver:Begin(limited, 0).Accepted, "Second entity begins")
local firstPredicted = resolver:Advance(limited, 1)
check(firstPredicted.Accepted and firstPredicted.Predicted, "First missing input frame is predicted")
check(firstPredicted.PredictionIndex == 1, "First prediction receives deterministic index")
local secondPredicted = resolver:Advance(limited, 2)
check(secondPredicted.Accepted and secondPredicted.PredictionIndex == 2, "Prediction reaches configured limit")
local previousFrame = resolver:GetState(limited).CurrentFrame
rejected(resolver:Advance(limited, 3), PredictionResult.Type.MaxPredictionFrames)
check(resolver:GetState(limited).CurrentFrame == previousFrame, "Limit rejection does not advance state")
check(resolver:Confirm(limited, 1).Accepted, "Confirm accepts a frame in history")
check(resolver:GetFrame(limited, 1).Confirmed, "Confirm marks requested frame")
check(not resolver:GetFrame(limited, 2).Confirmed, "Confirm leaves later speculative frames unconfirmed")
check(resolver:GetState(limited).PredictionFrameCount == 1, "Confirm retains prediction count after confirmed frame")
check(resolver:Advance(limited, 3).Accepted, "Confirm releases prediction budget")
rejected(resolver:Confirm(limited, 4), PredictionResult.Type.UnknownFrame)
rejected(resolver:Confirm(limited, -1), PredictionResult.Type.InvalidFrame)
rejected(resolver:Confirm(limited, 0), PredictionResult.Type.OutOfOrder)
rejected(resolver:Advance(limited, 5), PredictionResult.Type.OutOfOrder)
rejected(resolver:Advance(limited, 4, {}), PredictionResult.Type.InvalidInput)

local inputWorld = World.new()
local inputResolver = inputWorld:GetInputResolver()
local inputEntity = inputWorld:CreateEntity()
inputEntity:AddComponent(InputComponent.new(inputResolver.Profile))
local inputPrediction = inputWorld:GetPredictionResolver()
check(inputPrediction:Enable(inputEntity).Accepted, "Input prediction enables")
check(inputPrediction:Begin(inputEntity, 10).Accepted, "Input prediction begins")
check(inputResolver:SetInput(inputEntity, Input.Light, InputState.Pressed, 11) ~= nil,
	"Input abstraction records actual press")
local actual = inputPrediction:Advance(inputEntity, 11)
check(actual.Accepted and not actual.Predicted, "Advance consumes recorded InputFrame")
check(inputPrediction:GetFrame(inputEntity, 11).Inputs[Input.Light] == InputState.Pressed,
	"Actual frame preserves pressed input")
local repeated = inputPrediction:Advance(inputEntity, 12)
check(repeated.Accepted and repeated.Predicted, "Missing input uses deterministic prediction")
check(inputPrediction:GetFrame(inputEntity, 12).Inputs[Input.Light] == InputState.Held,
	"RepeatLast converts press to held")
check(inputPrediction:Advance(inputEntity, 13).Accepted, "Held input can advance again")
check(inputPrediction:GetFrame(inputEntity, 13).Inputs[Input.Light] == InputState.Held,
	"RepeatLast preserves held state")
check(inputResolver:SetInput(inputEntity, Input.Light, InputState.Released, 14) ~= nil,
	"Input abstraction records release")
check(inputPrediction:Advance(inputEntity, 14).Accepted, "Release frame is consumed")
check(inputPrediction:Advance(inputEntity, 15).Accepted, "Prediction follows release")
check(inputPrediction:GetFrame(inputEntity, 15).Inputs[Input.Light] == InputState.None,
	"RepeatLast converts release to neutral")
rejected(inputPrediction:Advance(inputEntity, 16, InputFrame.new({
	Frame = 16, EntityId = "other", Inputs = {},
})), PredictionResult.Type.InvalidInput)
rejected(inputPrediction:Advance(inputEntity, 16, InputFrame.new({
	Frame = 16, EntityId = inputEntity.Id, Inputs = { UnknownInput = InputState.Pressed },
})), PredictionResult.Type.InvalidInput)
rejected(inputPrediction:Advance(inputEntity, 16, InputFrame.new({
	Frame = 16, EntityId = inputEntity.Id, Inputs = { [Input.Light] = "InvalidState" },
})), PredictionResult.Type.InvalidInput)

local neutralWorld = World.new()
local neutralEntity = neutralWorld:CreateEntity()
local neutralResolver = neutralWorld:GetPredictionResolver()
check(neutralResolver:Enable(neutralEntity, PredictionProfile.new({
	MaxHistoryFrames = 8, MaxPredictionFrames = 3, InputPolicy = "Neutral",
})).Accepted, "Neutral-policy entity enables")
check(neutralResolver:Begin(neutralEntity, 0, InputFrame.new({
	Frame = 0, EntityId = neutralEntity.Id, Inputs = { [Input.Light] = InputState.Held },
})).Accepted, "Neutral-policy seed accepts input frame")
check(neutralResolver:Advance(neutralEntity, 1).Accepted, "Neutral policy predicts a frame")
check(neutralResolver:GetFrame(neutralEntity, 1).Inputs[Input.Light] == InputState.None,
	"Neutral policy replaces held input with neutral")
check(neutralResolver:Advance(neutralEntity, 2).Accepted, "Neutral policy advances repeatedly")
check(neutralResolver:GetFrame(neutralEntity, 2).Inputs[Input.Light] == InputState.None,
	"Neutral policy remains deterministic")

local snapshots = World.new()
local snapshotEntity = snapshots:CreateEntity()
local snapshotResolver = snapshots:GetPredictionResolver()
check(snapshotResolver:Enable(snapshotEntity).Accepted, "Snapshot entity enables")
check(snapshotResolver:Begin(snapshotEntity, 20).Accepted, "Snapshot entity begins")
check(snapshotResolver:Advance(snapshotEntity, 21).Accepted, "Snapshot entity predicts")
local expected = snapshotResolver:GetFrame(snapshotEntity, 21)
local matchingSnapshot = NetworkSnapshot.new({
	SimulationFrame = 21,
	Entities = {},
	Components = { Prediction = {
		[snapshotEntity.Id] = { Frame = 21, Inputs = expected.Inputs },
	} },
})
local wrappedSnapshot = PredictionSnapshot.new(matchingSnapshot)
check(wrappedSnapshot.SimulationFrame == 21, "Prediction snapshot keeps simulation frame")
check(#wrappedSnapshot:CompareFrame(snapshotEntity.Id, expected) == 0, "Matching structured snapshot has no divergence")
local matching = snapshotResolver:CompareSnapshot(matchingSnapshot)
check(matching.Accepted and #matching.Divergences == 0, "Resolver reports matching snapshot")
local divergentSnapshot = NetworkSnapshot.new({
	SimulationFrame = 21,
	Components = { Prediction = {
		[snapshotEntity.Id] = { Frame = 22, Inputs = { [Input.Light] = InputState.Pressed, Extra = true } },
	} },
})
local divergence = snapshotResolver:CompareSnapshot(divergentSnapshot)
check(divergence.Accepted and #divergence.Divergences == 3, "Snapshot reports all structured divergences")
check(divergence.Divergences[1].Path == "Frame", "Divergence includes deterministic frame path")
check(divergence.Divergences[2].Path == "Inputs.Extra", "Divergence reports unexpected input")
check(divergence.Divergences[3].Path == "Inputs.Light", "Divergence includes nested input path")
check(divergence.Divergences[1].Expected == 21 and divergence.Divergences[1].Actual == 22,
	"Divergence retains expected and received values")
check(not snapshotResolver:GetFrame(snapshotEntity, 21).Confirmed,
	"Snapshot comparison does not confirm or mutate prediction")
rejected(snapshotResolver:CompareSnapshot({}), PredictionResult.Type.InvalidSnapshot)
local missingSnapshot = NetworkSnapshot.new({ SimulationFrame = 21 })
local missing = snapshotResolver:CompareSnapshot(missingSnapshot)
check(#missing.Divergences == 1 and missing.Divergences[1].Kind == "MissingPrediction",
	"Missing remote prediction is an explicit divergence")
check(missing.Divergences[1].EntityId == snapshotEntity.Id, "Divergence identifies entity")
local malformedSnapshot = NetworkSnapshot.new({
	SimulationFrame = 21,
	Components = { Prediction = {
		[snapshotEntity.Id] = { Frame = 21, Inputs = "not-a-map" },
	} },
})
local malformed = snapshotResolver:CompareSnapshot(malformedSnapshot)
check(#malformed.Divergences == 1 and malformed.Divergences[1].Kind == "InvalidPredictionData",
	"Malformed remote prediction returns a structured divergence")
local hasDivergenceEvent = false
for _, event in ipairs(snapshotResolver:GetEvents()) do
	if event.Type == PredictionEvent.Type.Divergence then hasDivergenceEvent = true end
end
check(hasDivergenceEvent,
	"Divergence emits prediction event")

local historyWorld = World.new()
local historyEntity = historyWorld:CreateEntity()
local historyResolver = historyWorld:GetPredictionResolver()
check(historyResolver:Enable(historyEntity, PredictionProfile.new({
	MaxHistoryFrames = 3, MaxPredictionFrames = 10,
})).Accepted, "Bounded-history entity enables")
check(historyResolver:Begin(historyEntity, 0).Accepted, "Bounded-history entity begins")
for frame = 1, 7 do
	local result = historyResolver:Advance(historyEntity, frame)
	check(result.Accepted and result.Frame == frame, "Bounded history advances each frame")
	check(historyResolver:GetState(historyEntity).History:Count() <= 3, "History remains within configured capacity")
end
check(historyResolver:GetFrame(historyEntity, 4) == nil, "Old frame is evicted from bounded history")
check(historyResolver:GetFrame(historyEntity, 5) ~= nil, "Newest retained history begins at expected frame")
check(#historyResolver:GetHistory(historyEntity) == 3, "Resolver returns only retained frames")

local order = {}
local ids = { "zeta", "alpha", "middle" }
local idGenerator = { Next = function(self)
	local id = ids[1]
	table.remove(ids, 1)
	return id
end }
local orderWorld = World.new({ IdGenerator = idGenerator })
local orderResolver = orderWorld:GetPredictionResolver()
local orderEntities = {}
for _, id in ipairs({ "zeta", "alpha", "middle" }) do
	local orderedEntity = orderWorld:CreateEntity()
	check(orderedEntity.Id == id, "Test entity has controlled ID")
	check(orderResolver:Enable(orderedEntity).Accepted, "Ordered entity enables")
	check(orderResolver:Begin(orderedEntity, 0).Accepted, "Ordered entity begins")
	orderEntities[id] = orderedEntity
end
local allResults = orderResolver:AdvanceAll(1)
check(#allResults == 3, "AdvanceAll advances each enabled entity")
for _, result in ipairs(allResults) do table.insert(order, result.EntityId) end
check(order[1] == "alpha" and order[2] == "middle" and order[3] == "zeta",
	"AdvanceAll uses stable lexical entity ordering")
local mapped = orderResolver:AdvanceAll(2, {
	alpha = InputFrame.new({ Frame = 2, EntityId = "alpha", Inputs = { [Input.Light] = InputState.Pressed } }),
	middle = InputFrame.new({ Frame = 2, EntityId = "middle", Inputs = {} }),
	zeta = InputFrame.new({ Frame = 2, EntityId = "zeta", Inputs = {} }),
})
check(#mapped == 3, "AdvanceAll accepts entity-keyed input-frame map")
check(mapped[1].EntityId == "alpha" and mapped[1].Predicted == false, "Mapped frames retain sorted order and actual input")
check(mapped[2].EntityId == "middle" and not mapped[2].Predicted, "Empty actual InputFrame is not treated as prediction")
check(mapped[3].EntityId == "zeta" and not mapped[3].Predicted, "Input map binds to correct entity")
local invalidBatch = orderResolver:AdvanceAll(3, false)
check(#invalidBatch == 1 and invalidBatch[1].Type == PredictionResult.Type.InvalidInput,
	"AdvanceAll reports an invalid input map")
check(orderResolver:GetState(orderEntities.alpha).CurrentFrame == 2,
	"Invalid AdvanceAll input map does not advance any entity")

local firstOrder = orderResolver:GetEvents()
check(#firstOrder > 0 and firstOrder[1].EntityId == "alpha", "Events are deterministically ordered by entity")
local componentWorld = World.new()
local componentEntity = componentWorld:CreateEntity()
local componentResolver = componentWorld:GetPredictionResolver()
check(componentResolver:Enable(componentEntity).Accepted, "Component lifecycle entity enables")
check(componentResolver:GetState(componentEntity) ~= nil, "Component state registered")
check(componentWorld:DestroyEntity(componentEntity), "World destroys prediction entity")
check(componentResolver:GetState(componentEntity) == nil, "World destruction unregisters prediction state")
check(componentEntity:GetComponent(PredictionComponent) == nil, "World destruction removes prediction component")
check(componentWorld:GetPredictionEvents()[#componentWorld:GetPredictionEvents()].Type == PredictionEvent.Type.Removed,
	"World destruction emits removed event")
rejected(componentResolver:Begin(componentEntity, 0), PredictionResult.Type.InvalidEntity)
local detachedEntity = componentWorld:CreateEntity()
check(componentResolver:Enable(detachedEntity).Accepted, "Direct-detach entity enables")
check(detachedEntity:RemoveComponent(PredictionComponent), "Entity can detach prediction component")
check(componentResolver:GetState(detachedEntity) == nil, "Direct component removal unregisters prediction state")

local repeatWorldA, repeatWorldB = World.new(), World.new()
local repeatA, repeatB = repeatWorldA:CreateEntity(), repeatWorldB:CreateEntity()
local resolverA, resolverB = repeatWorldA:GetPredictionResolver(), repeatWorldB:GetPredictionResolver()
local longProfile = PredictionProfile.new({ MaxHistoryFrames = 64, MaxPredictionFrames = 4 })
check(resolverA:Enable(repeatA, longProfile).Accepted and resolverB:Enable(repeatB, longProfile).Accepted,
	"Equivalent simulations enable matching prediction profiles")
check(resolverA:Begin(repeatA, 0).Accepted and resolverB:Begin(repeatB, 0).Accepted,
	"Equivalent simulations begin at same frame")
for frame = 1, 48 do
	local inputState = frame % 4 == 1 and InputState.Pressed
		or (frame % 4 == 2 and InputState.Held or (frame % 4 == 3 and InputState.Released or InputState.None))
	local inputA = InputFrame.new({
		Frame = frame, EntityId = repeatA.Id, Inputs = { [Input.Light] = inputState },
	})
	local inputB = InputFrame.new({
		Frame = frame, EntityId = repeatB.Id, Inputs = { [Input.Light] = inputState },
	})
	local resultA, resultB = resolverA:Advance(repeatA, frame, inputA), resolverB:Advance(repeatB, frame, inputB)
	check(resultA.Accepted and resultB.Accepted, "Equivalent frame inputs advance successfully")
	local frameA, frameB = resolverA:GetFrame(repeatA, frame), resolverB:GetFrame(repeatB, frame)
	check(frameA.Frame == frameB.Frame, "Equivalent frame numbers remain deterministic")
	check(frameA.Inputs[Input.Light] == frameB.Inputs[Input.Light], "Equivalent input states remain deterministic")
	check(frameA.Predicted == frameB.Predicted and frameA.Confirmed == frameB.Confirmed,
		"Equivalent prediction metadata remains deterministic")
end
check(assertions >= 200, "Prediction test exercises at least 200 meaningful assertions")

print(("Combat prediction tests passed (%d assertions)"):format(assertions))

end
