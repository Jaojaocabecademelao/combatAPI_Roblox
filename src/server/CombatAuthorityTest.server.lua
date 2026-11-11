local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core, Combat, SimulationFolder = Shared:WaitForChild("Core"), Shared:WaitForChild("Combat"), Shared:WaitForChild("Simulation")

local Component = require(Core.Component)
local World = require(Core.World)
local Simulation = require(SimulationFolder.Simulation)
local Input = require(Combat.Input)
local InputState = require(Combat.InputState)
local InputComponent = require(Combat.InputComponent)
local InputProfile = require(Combat.InputProfile)
local InputBinding = require(Combat.InputBinding)
local InputFrame = require(Combat.InputFrame)
local AuthorityProfile = require(Combat.AuthorityProfile)
local AuthorityState = require(Combat.AuthorityState)
local AuthorityPolicy = require(Combat.AuthorityPolicy)
local AuthorityInput = require(Combat.AuthorityInput)
local AuthorityRequest = require(Combat.AuthorityRequest)
local AuthoritySnapshot = require(Combat.AuthoritySnapshot)
local AuthorityResult = require(Combat.AuthorityResult)
local AuthorityEvent = require(Combat.AuthorityEvent)
local AuthorityValidation = require(Combat.AuthorityValidation)
local NetworkAdapter = require(Combat.NetworkAdapter)
local NetworkPeer = require(Combat.NetworkPeer)
local NetworkMessage = require(Combat.NetworkMessage)
local NetworkChannel = require(Combat.NetworkChannel)
local NetworkSequence = require(Combat.NetworkSequence)
local NetworkResult = require(Combat.NetworkResult)
local InputPacketAdapter = require(Combat.InputPacketAdapter)
local RollbackProfile = require(Combat.RollbackProfile)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Authority assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local Counter = {}
Counter.__index = Counter
setmetatable(Counter, { __index = Component })

function Counter.new()
	local self = setmetatable(Component.new(), Counter)
	self.Value = 0
	self.Frames = 0
	return self
end

function Counter:Step()
	local inputState = self.Entity.World:GetInputResolver():GetInput(self.Entity, Input.Light)
	if inputState == InputState.Pressed then self.Value += 10
	elseif inputState == InputState.Held then self.Value += 1 end
	self.Frames += 1
end

Counter.RollbackKey = "AuthorityTest.Counter"

function Counter:CaptureRollbackState()
	return { Value = self.Value, Frames = self.Frames }
end

function Counter:RestoreRollbackState(state)
	self.Value = state.Value
	self.Frames = state.Frames
end

local sent = {}
local adapter = NetworkAdapter.new("AuthorityTest", {
	Send = function(peer, message)
		table.insert(sent, { Peer = peer.Id, Message = message })
		return true
	end,
})
local inputProfile = InputProfile.new({
	Bindings = { InputBinding.new("light", Input.Light) },
})
local world = World.new({
	InputProfile = inputProfile,
	Network = { Adapters = { Mock = adapter } },
	Authority = {
		MaxFutureFrames = 8,
		MaxInputLeadFrames = 8,
		MaxPastFrames = 0,
		MaxInputDelayFrames = 0,
		MaxInputsPerFrame = 8,
		MaxFramesPerAdvance = 16,
		SnapshotInterval = 3,
		PublishSnapshots = true,
		SnapshotFilter = function(entity)
			local counter = entity:GetComponent(Counter)
			return {
				Complete = true,
				Components = counter and {
					TestCounter = { Value = counter.Value, Frames = counter.Frames },
				} or {},
			}
		end,
	},
})
local simulation = Simulation.new(world, { Seed = 73 })
local authority = world:GetAuthorityResolver()
local network = world:GetNetworkResolver()

check(authority ~= nil and world:GetAuthorityResolver() == authority, "World exposes a stable authority resolver")
check(authority.Component.AuthorityState == AuthorityState.Inactive, "Authority starts inactive")
check(authority.Component.Enabled == false, "Authority is disabled until explicitly enabled")
check(authority.Component.CurrentAuthoritativeFrame == 0, "Authority starts at frame zero")
check(authority.Component.LastProcessedInputFrame == nil, "No input frame is claimed before processing")
check(authority.Component.LastPublishedFrame == nil, "No publication is claimed before one occurs")
check(authority.Profile.MaxFutureFrames == 8 and authority.Profile.MaxInputLeadFrames == 8, "Future limits are configured")
check(authority.Profile.MaxPastFrames == 0 and authority.Profile.MaxInputDelayFrames == 0, "Past limits are configured")
check(authority.Profile.MaxInputsPerFrame == 8, "Per-peer frame rate limit is configured")
check(authority.Profile.SnapshotInterval == 3, "Snapshot interval is configured")
check(authority.Profile.PublishSnapshots, "Snapshot publication is enabled")
check(not pcall(function() AuthorityProfile.new({ MaxInputsPerFrame = -1 }) end), "Negative rate limit is invalid")
check(not pcall(function() AuthorityProfile.new({ SnapshotInterval = 0 }) end), "Zero snapshot interval is invalid")
check(not pcall(function() AuthorityProfile.new({ MaxFutureFrames = 1.5 }) end), "Fractional future limit is invalid")
check(not pcall(function() AuthorityProfile.new({ PastInputPolicy = "Teleport" }) end), "Unknown late-input policy is invalid")
check(not pcall(function() AuthorityProfile.new({ SnapshotFilter = true }) end), "Non-function snapshot filter is invalid")
check(AuthorityPolicy.PastInput.Reject == "Reject", "Reject late-input policy is exposed")
check(AuthorityPolicy.PastInput.Rollback == "Rollback", "Rollback late-input policy is exposed")
check(AuthorityResult.Type.UnauthorizedEntity == "UnauthorizedEntity", "Ownership failure has an explicit result")
check(AuthorityResult.Type.FutureInput == "FutureInput", "Future failure has an explicit result")
check(AuthorityResult.Type.PastInput == "PastInput", "Past failure has an explicit result")
check(AuthorityResult.Type.RecoveryRequired == "RecoveryRequired",
	"Out-of-window recovery has an explicit result")
check(AuthorityEvent.Type.InputAccepted == "AuthorityInputAccepted", "Input event type is explicit")
check(AuthorityEvent.Type.SnapshotPublished == "AuthoritySnapshotPublished", "Snapshot event type is explicit")
check(not pcall(function() AuthorityRequest.new({}) end), "Request requires a simulation frame")

-- Every existing combat input is accepted only with one of the existing InputState values.
local states = { InputState.None, InputState.Pressed, InputState.Held, InputState.Released }
for inputId in pairs(Input) do
	for _, inputState in ipairs(states) do
		local parsed = AuthorityValidation.Parse({
			EntityId = 1, SimulationFrame = 0, Inputs = { [inputId] = inputState },
		}, authority.Profile, inputProfile, nil)
		check(parsed ~= nil and parsed.Inputs[inputId] == inputState, "Whitelisted input/state parses")
	end
end
for inputId in pairs(Input) do
	check(inputProfile:IsValidInput(inputId), "InputProfile recognizes existing combat input")
end
check(not AuthorityValidation.Parse({
	EntityId = 1, SimulationFrame = 0, Inputs = { UnknownButton = InputState.Pressed },
}, authority.Profile, inputProfile, nil), "Unknown input is rejected")
check(not AuthorityValidation.Parse({
	EntityId = 1, SimulationFrame = 0, Inputs = { [Input.Light] = "HitConfirmed" },
}, authority.Profile, inputProfile, nil), "Unrecognized input state is rejected")
check(not AuthorityValidation.Parse({
	EntityId = 1, SimulationFrame = 0, Inputs = { [Input.Light] = { Pressed = true } },
}, authority.Profile, inputProfile, nil), "Nested input payload is rejected")
check(not AuthorityValidation.Parse({
	EntityId = 0 / 0, SimulationFrame = 0, Inputs = {},
}, authority.Profile, inputProfile, nil), "NaN entity identifier is rejected before registry lookup")
check(not AuthorityValidation.Parse({
	EntityId = math.huge, SimulationFrame = 0, Inputs = {},
}, authority.Profile, inputProfile, nil), "Infinite entity identifier is rejected")
check(not AuthorityValidation.Parse({
	EntityId = string.rep("x", 129), SimulationFrame = 0, Inputs = {},
}, authority.Profile, inputProfile, nil), "Oversized entity identifier is rejected")
check(not AuthorityValidation.Parse({
	EntityId = 1, SimulationFrame = 0, Inputs = setmetatable({}, {}),
}, authority.Profile, inputProfile, nil), "Metatable-backed input map is rejected")

local forbiddenFields = {
	"Health", "Damage", "Hit", "HitConfirmed", "AttackConnected", "ComboCount",
	"GuardBroken", "Position", "Velocity", "Dead", "Death", "Guard", "DamageEvent",
	"Motion", "Juggle", "Armor", "Protection", "State", "RNGState", "Components",
}
for _, field in ipairs(forbiddenFields) do
	local payload = {
		EntityId = 1, SimulationFrame = 0, NetworkSequence = 1,
		Inputs = { [Input.Light] = InputState.Pressed },
	}
	payload[field] = 999999
	check(not AuthorityValidation.Parse(payload, authority.Profile, inputProfile, "peer-a"),
		"Client combat-state field is rejected: " .. field)
end
check(not AuthorityValidation.Parse({
	EntityId = 1, SimulationFrame = 0, NetworkSequence = 1,
	Inputs = { [Input.Light] = InputState.Pressed }, Extra = true,
}, authority.Profile, inputProfile, "peer-a"), "Unknown top-level input field is rejected")

local attacker = world:CreateEntity()
local defender = world:CreateEntity()
local projectile = world:CreateEntity()
local dummy = world:CreateEntity()
local serverEntity = world:CreateEntity()
local function addInputAndCounter(entity)
	entity:AddComponent(InputComponent.new(inputProfile))
	return entity:AddComponent(Counter.new())
end
local attackerCounter = addInputAndCounter(attacker)
local defenderCounter = addInputAndCounter(defender)
local projectileCounter = addInputAndCounter(projectile)
local dummyCounter = addInputAndCounter(dummy)
local serverCounter = addInputAndCounter(serverEntity)
check(world:HasEntity(attacker), "Attacker is registered in authoritative World")
check(world:HasEntity(defender), "Defender is registered in authoritative World")
check(world:HasEntity(projectile), "Projectile entity is registered")
check(world:HasEntity(dummy), "Dummy entity is registered")
check(world:HasEntity(serverEntity), "Peerless server entity is registered")
check(attacker:GetComponent(InputComponent) ~= nil, "Attacker uses shared InputComponent")
check(defender:GetComponent(InputComponent) ~= nil, "Defender uses shared InputComponent")
check(projectile:GetComponent(InputComponent) ~= nil, "Projectile can share the input abstraction")
check(dummy:GetComponent(InputComponent) ~= nil, "Dummy can share the input abstraction")
check(serverEntity:GetComponent(InputComponent) ~= nil, "Server entity has the shared input component")

local peerA = NetworkPeer.new("peer-a", NetworkPeer.Role.Client)
local peerB = NetworkPeer.new("peer-b", NetworkPeer.Role.Client)
check(network:RegisterPeer(peerA).Accepted, "NetworkResolver registers peer A")
check(network:RegisterPeer(peerB).Accepted, "NetworkResolver registers peer B")
check(authority:RegisterPeer(peerA).Accepted, "Authority registers a NetworkPeer")
check(authority:RegisterPeer(peerB).Accepted, "Authority registers a second NetworkPeer")
check(not authority:RegisterPeer(peerA).Accepted, "Authority rejects duplicate peer registration")
check(not authority:RegisterPeer({ Id = "forged" }).Accepted, "Authority rejects a forged peer table")
check(not authority:RegisterPeer(NetworkPeer.new("unregistered")).Accepted, "Authority requires NetworkResolver registration")
check(not authority:RegisterPeer(NetworkPeer.new(0 / 0)).Accepted, "Authority rejects non-finite peer IDs")
check(network:Connect(peerA.Id).Accepted, "Peer A connects through Networking")
check(network:Connect(peerB.Id).Accepted, "Peer B connects through Networking")
check(authority:BindEntity(peerA.Id, attacker).Accepted, "Peer A binds to attacker")
check(authority:BindEntity(peerB.Id, defender).Accepted, "Peer B binds to defender")
check(not authority:BindEntity("missing-peer", projectile).Accepted, "Unknown peer cannot bind an entity")
check(not authority:BindEntity(peerB.Id, attacker).Accepted, "Second peer cannot take owned entity")
check(not authority:BindEntity(peerA.Id, world:CreateEntity()).Accepted, "Entity without InputComponent cannot be bound")
check(not authority:BindEntity(peerA.Id, 987654).Accepted, "Nonexistent entity cannot be bound")
check(not authority:UnbindEntity(peerB.Id, attacker).Accepted, "Non-owner cannot unbind entity")
check(authority:Enable().Accepted, "Authority enables against the existing Simulation")
check(authority:IsEnabled(), "Enabled state is observable")
check(authority.Component.AuthorityState == AuthorityState.Active, "Enable enters Active state")
check(authority:GetAuthoritativeFrame() == simulation:GetGameTime():GetFrame(), "Enable syncs authoritative frame")

local inputMessage = NetworkMessage.new({
	Type = NetworkMessage.Type.Input,
	Channel = NetworkChannel.Input,
	Sequence = 1,
	SimulationFrame = 3,
	Sender = peerA.Id,
	Payload = { EntityId = attacker.Id, Inputs = { [Input.Light] = InputState.Released } },
})
check(authority:ValidateInput(peerA.Id, inputMessage).Accepted, "Valid transport message passes authority validation")
local transportAccepted, authorityAccepted = authority:ReceiveNetworkInput(peerA.Id, inputMessage)
check(transportAccepted.Accepted and authorityAccepted.Accepted,
	"Network transport sequence is accepted before the authority queues peer input")
local duplicateTransport, duplicateAuthority = authority:ReceiveNetworkInput(peerA.Id, inputMessage)
check(not duplicateTransport.Accepted and duplicateAuthority == nil,
	"Duplicate transport message is rejected before authority can queue it twice")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = defender.Id, SimulationFrame = 1, NetworkSequence = 2,
	Inputs = { [Input.Light] = InputState.Pressed },
}).Accepted, "Peer A cannot submit input for peer B entity")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 1, NetworkSequence = 0,
	Inputs = { [Input.Light] = InputState.Pressed },
}).Accepted, "Old transport sequence is rejected")
check(not authority:SubmitInput("missing-peer", {
	EntityId = attacker.Id, SimulationFrame = 1, NetworkSequence = 2,
	Inputs = { [Input.Light] = InputState.Pressed },
}).Accepted, "Unknown peer submission is rejected")
check(not authority:SubmitInput(nil, {}).Accepted, "Public peer submission cannot bypass ownership with nil peer")
check(not authority:SubmitInput(peerA.Id, {}).Accepted, "Malformed payload is rejected")
local negativeFrameResult = authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = -1, NetworkSequence = 2, Inputs = {},
})
check(not negativeFrameResult.Accepted and negativeFrameResult.Type == AuthorityResult.Type.InvalidFrame,
	"Negative simulation frame has explicit rejection result")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 1.5, NetworkSequence = 2, Inputs = {},
}).Accepted, "Fractional simulation frame is rejected")
local negativeSequenceResult = authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 1, NetworkSequence = -1, Inputs = {},
})
check(not negativeSequenceResult.Accepted and negativeSequenceResult.Type == AuthorityResult.Type.InvalidSequence,
	"Negative network sequence has explicit rejection result")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 1, NetworkSequence = 4294967296, Inputs = {},
}).Accepted, "Out-of-range network sequence is rejected")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 1, NetworkSequence = 2,
	Inputs = { [Input.Light] = InputState.Pressed }, Health = 999999,
}).Accepted, "Forged health cannot enter the input queue")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 1, NetworkSequence = 2,
	Inputs = { [Input.Light] = InputState.Pressed }, Damage = 999999,
}).Accepted, "Forged damage cannot enter the input queue")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 1, NetworkSequence = 2,
	Inputs = { [Input.Light] = InputState.Pressed }, HitConfirmed = true,
}).Accepted, "Forged hit confirmation cannot enter the input queue")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 1, NetworkSequence = 2,
	Inputs = { [Input.Light] = InputState.Pressed }, Dead = true,
}).Accepted, "Forged death cannot enter the input queue")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 1, NetworkSequence = 2,
	Inputs = { [Input.Light] = InputState.Pressed }, Position = { X = 1e9, Y = 1e9, Z = 1e9 },
}).Accepted, "Forged position cannot enter the input queue")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 1, NetworkSequence = 2,
	Inputs = { [Input.Light] = "Pressed", Unknown = "true" },
}).Accepted, "Invalid and extra button values are rejected")

-- Frames may arrive out of order; transport sequence and simulation frame remain independent.
check(authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 1, NetworkSequence = 2,
	Inputs = { [Input.Light] = InputState.Pressed },
}).Accepted, "Out-of-order simulation frame is queued when sequence is newer")
check(authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 2, NetworkSequence = 3,
	Inputs = { [Input.Light] = InputState.Held },
}).Accepted, "Second future frame queues independently of sequence")
check(authority:GetAuthoritativeFrame() == 0, "Receiving inputs does not advance Simulation")
check(authority:Advance(3).Accepted, "Authority advances through queued frames")
check(authority:GetAuthoritativeFrame() == 3, "Authoritative cursor reaches requested frame")
check(world.CurrentFrame == 3 and simulation:GetGameTime():GetFrame() == 3, "World and Simulation frame cursors agree")
check(attackerCounter.Frames == 3, "Attacker Simulation component ran exactly once per frame")
check(defenderCounter.Frames == 3, "Defender Simulation component ran exactly once per frame")
check(projectileCounter.Frames == 3, "Projectile Simulation component ran exactly once per frame")
check(dummyCounter.Frames == 3, "Dummy Simulation component ran exactly once per frame")
check(serverCounter.Frames == 3, "Peerless server entity ran without network ownership")
check(attackerCounter.Value == 11, "Queued Pressed/Held input is applied by shared Simulation")
check(defenderCounter.Value == 0, "Unowned entity received no client input")
check(authority.Component.LastProcessedInputFrame == 3, "Last processed input frame records simulation time")
check(not authority:Advance(3).Accepted, "Already processed frame cannot be advanced a second time")
check(not authority:Advance(4.5).Accepted, "Fractional advance frame is rejected")
check(not authority:Advance(1000).Accepted, "Advance work is bounded")
check(authority.Component.AuthorityState == AuthorityState.Active, "Normal advancement returns to Active")

check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 2, NetworkSequence = 4,
	Inputs = { [Input.Light] = InputState.Pressed },
}).Accepted, "Late frame follows explicit Reject policy")
check(authority.Profile.PastInputPolicy == AuthorityPolicy.PastInput.Reject, "Late policy is not implicit")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 12, NetworkSequence = 4, Inputs = {},
}).Accepted, "Input beyond maximum future lead is rejected")
check(authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 11, NetworkSequence = 4,
	Inputs = { [Input.Light] = InputState.Released },
}).Accepted, "Input at exact future boundary is accepted")
check(authority:Advance(11).Accepted, "Simulation processes the accepted boundary input")
check(authority:GetAuthoritativeFrame() == 11, "Boundary processing advances precisely")

local limitedEntities = {}
for index = 1, 9 do
	local entity = world:CreateEntity()
	addInputAndCounter(entity)
	limitedEntities[index] = entity
	check(authority:BindEntity(peerA.Id, entity).Accepted, "Peer can own multiple entities")
end
for index = 1, 8 do
	check(authority:SubmitInput(peerA.Id, {
		EntityId = limitedEntities[index].Id, SimulationFrame = 12, NetworkSequence = index + 4,
		Inputs = { [Input.Dash] = InputState.Pressed },
	}).Accepted, "Per-frame rate budget admits input within limit")
end
check(not authority:SubmitInput(peerA.Id, {
	EntityId = limitedEntities[9].Id, SimulationFrame = 12, NetworkSequence = 13,
	Inputs = { [Input.Dash] = InputState.Pressed },
}).Accepted, "Per-frame rate budget rejects excess input")
check(authority:Advance(12).Accepted, "Rate-limited frame can still be simulated")
check(limitedEntities[8]:GetComponent(Counter).Frames == 1, "New entities receive the frame in which they join simulation")
check(limitedEntities[9]:GetComponent(Counter).Frames == 1, "Rate rejection does not skip unrelated entity simulation")

local serverInputResult = authority:SubmitServerInput(serverEntity, {
	SimulationFrame = 13,
	Inputs = { [Input.Jump] = InputState.Pressed },
})
check(serverInputResult.Accepted, "Server-controlled entity can submit input without a peer")
check(authority:Advance(13).Accepted, "Server-controlled input uses the same Simulation")
check(serverCounter.Frames == 13, "Peerless entity remains simulated")
check(not authority:SubmitServerInput(serverEntity, {
	EntityId = attacker.Id, SimulationFrame = 14, Inputs = {},
}).Accepted, "Server input cannot override its entity identity")
check(not authority:SubmitServerInput(serverEntity, {
	SimulationFrame = 14, Inputs = { Damage = 999 },
}).Accepted, "Server input still obeys input whitelist")

local snapshot = authority:CreateSnapshot()
check(snapshot ~= nil and getmetatable(snapshot) == AuthoritySnapshot, "Authority creates an AuthoritySnapshot")
check(snapshot.SimulationFrame == 13, "Snapshot uses authoritative SimulationFrame")
check(snapshot.NetworkSequence ~= snapshot.SimulationFrame, "Network snapshot sequence is distinct from simulation frame")
check(#snapshot.Entities == #world:GetEntities(), "Snapshot includes current authoritative entity roster")
check(snapshot.Entities[1].Components ~= nil, "Snapshot exposes a component-filter boundary")
check(snapshot.Entities[1].Health == nil, "Default public snapshot does not expose internal health fields")
check(snapshot.Complete, "Trusted snapshot filter marks its projection complete")
check(snapshot.Entities[1].Components.TestCounter.Value == attackerCounter.Value, "Snapshot filter exports authoritative component data")
check(snapshot.Components.Prediction[attacker.Id].Frame == 13, "Snapshot includes frame-indexed authoritative input for Prediction")
check(snapshot.RNGState == simulation:GetRNG():GetState(), "Snapshot captures authoritative RNG state")
check(authority.Component.LastPublishedFrame == 12, "Last published frame tracks successful prior periodic publication")
check(authority:PublishSnapshot(snapshot).Accepted, "Authority snapshot publishes through NetworkResolver")
check(authority.Component.LastPublishedFrame == 13, "Successful publication advances last published frame")
check(#sent > 0, "Existing NetworkResolver adapter transports snapshots")
check(sent[#sent].Message.Type == NetworkMessage.Type.Snapshot, "Publication uses NetworkSnapshot message type")
check(sent[#sent].Message.Channel == NetworkChannel.Snapshot, "Publication uses snapshot channel")
check(sent[#sent].Message.SimulationFrame == 13, "Network envelope preserves SimulationFrame")
check(sent[#sent].Message.Sequence == snapshot.NetworkSequence, "Network envelope carries independent sequence")
check(sent[#sent].Message.Payload.Metadata.Authority == true, "Transport snapshot marks authoritative origin")
check(sent[#sent].Message.Payload.Metadata.Complete == true, "Transport snapshot marks complete projection")
check(sent[#sent].Message.Payload.Metadata.RNGState == snapshot.RNGState, "Transport snapshot carries RNG state")
check(not authority:PublishSnapshot({ SimulationFrame = 13 }).Accepted, "Non-authority snapshot object is rejected")

local snapshotAtFrame3
for _, send in ipairs(sent) do
	if send.Message.Type == NetworkMessage.Type.Snapshot and send.Message.SimulationFrame == 3 then
		snapshotAtFrame3 = send.Message.Payload
		break
	end
end
check(snapshotAtFrame3 ~= nil, "Periodic authority snapshot is available for client prediction")
local function makePredictionClient(mismatch)
	local clientWorld = World.new({ InputProfile = inputProfile })
	local clientEntity = clientWorld:CreateEntity()
	clientEntity:AddComponent(InputComponent.new(inputProfile))
	local prediction = clientWorld:GetPredictionResolver()
	check(prediction:Enable(clientEntity).Accepted, "Client Prediction enables through existing resolver")
	check(prediction:Begin(clientEntity, 0).Accepted, "Client Prediction begins at the matching frame")
	for frame = 1, 3 do
		local authoritativeFrame = attacker:GetComponent(InputComponent).InputBuffer:Get(frame)
		local inputs = {}
		for inputId, state in pairs(authoritativeFrame.Inputs) do inputs[inputId] = state end
		if mismatch and frame == 3 then inputs[Input.Light] = InputState.Pressed end
		check(prediction:Advance(clientEntity, frame, InputFrame.new({
			Frame = frame, EntityId = clientEntity.Id, Inputs = inputs,
		})).Accepted, "Prediction stores client input at its simulation frame")
	end
	return prediction, clientEntity
end
local matchingPrediction, matchingPredictionEntity = makePredictionClient(false)
local matchingComparison = matchingPrediction:CompareSnapshot(snapshotAtFrame3)
check(matchingComparison.Accepted and #matchingComparison.Divergences == 0,
	"Matching prediction agrees with authoritative snapshot input")
local divergentPrediction, divergentPredictionEntity = makePredictionClient(true)
local divergentComparison = divergentPrediction:CompareSnapshot(snapshotAtFrame3)
check(divergentComparison.Accepted and #divergentComparison.Divergences > 0,
	"PredictionResolver detects deliberately divergent client input")
check(divergentPrediction:GetFrame(divergentPredictionEntity, 3).Inputs[Input.Light] == InputState.Pressed,
	"Authority comparison does not mutate local prediction")
check(authority:GetAuthoritativeFrame() == 13, "Client divergence does not change server authority")
check(matchingPredictionEntity.Id == attacker.Id, "Prediction entity identity is compared independently of Peer")

local forgedNetworkPayload = InputPacketAdapter.ToSerializerInput(
	InputFrame.new({ Frame = 14, EntityId = attacker.Id, Inputs = { [Input.Light] = InputState.Pressed } }),
	{ Seq = 99 })
local forgedMessage = NetworkMessage.new({
	Type = NetworkMessage.Type.Input, Channel = NetworkChannel.Input, Sequence = 14,
	SimulationFrame = 14, Sender = peerA.Id, Payload = forgedNetworkPayload,
})
check(not authority:SubmitInput(peerA.Id, forgedMessage).Accepted, "Serializer movement fields are not accepted as combat-state authority")
check(not authority:SubmitInput(peerA.Id, NetworkMessage.new({
	Type = NetworkMessage.Type.Snapshot, Channel = NetworkChannel.Snapshot, Sequence = 14,
	SimulationFrame = 14, Sender = peerA.Id, Payload = {},
})).Accepted, "Client snapshot cannot be submitted as combat input")
check(not authority:SubmitInput(peerA.Id, NetworkMessage.new({
	Type = NetworkMessage.Type.Input, Channel = NetworkChannel.Snapshot, Sequence = 14,
	SimulationFrame = 14, Sender = peerA.Id, Payload = {},
})).Accepted, "Wrong message channel is rejected")
check(not authority:SubmitInput(peerA.Id, NetworkMessage.new({
	Type = NetworkMessage.Type.Input, Channel = NetworkChannel.Input, Sequence = 14,
	SimulationFrame = 14, Sender = peerB.Id,
	Payload = { EntityId = attacker.Id, Inputs = {} },
})).Accepted, "Sender metadata cannot impersonate transport peer")

local seq = NetworkSequence.new(4294967295)
check(seq:Next() == 0, "Transport sequence wraps by its own modulus")
check(NetworkSequence.new(0):Compare(4294967295) > 0, "Wrapped network sequence ordering is independent of simulation frames")
check(NetworkSequence.new(10):Compare(10) == 0, "Network sequence detects equality")
check(NetworkSequence.new(11):Compare(10) > 0, "Network sequence detects newer message")
check(NetworkSequence.new(9):Compare(10) < 0, "Network sequence detects older message")
check(network:GetPeer(peerA.Id) == peerA, "Networking remains owner of peer registry")
check(network:Acknowledge(peerA.Id, 77, 13).Accepted, "ACK remains a NetworkResolver concern")
check(authority:GetAuthoritativeFrame() == 13, "Network ACK does not redefine authoritative frame")
check(authority:UnbindEntity(peerA.Id, attacker).Accepted, "Owner can unbind entity")
check(not authority:SubmitInput(peerA.Id, {
	EntityId = attacker.Id, SimulationFrame = 14, NetworkSequence = 15,
	Inputs = { [Input.Light] = InputState.Pressed },
}).Accepted, "Unbound peer cannot control former entity")
check(authority:BindEntity(peerA.Id, attacker).Accepted, "Entity can be rebound for ownership transfer")
local peerC = NetworkPeer.new("peer-c", NetworkPeer.Role.Client)
check(network:RegisterPeer(peerC).Accepted, "Additional peer registers with NetworkResolver")
check(network:Connect(peerC.Id).Accepted, "Additional peer connects")
check(authority:RegisterPeer(peerC).Accepted, "Additional peer registers with AuthorityResolver")
check(authority:BindEntity(peerC.Id, dummy).Accepted, "Additional peer receives explicit entity ownership")
check(network:UnregisterPeer(peerC.Id).Accepted, "Transport peer can be removed independently")
check(not authority:SubmitInput(peerC.Id, {
	EntityId = dummy.Id, SimulationFrame = 14, NetworkSequence = 1, Inputs = {},
}).Accepted, "Authority rejects a stale peer removed from NetworkResolver")
check(authority:UnregisterPeer(peerC.Id).Accepted, "Authority removes stale peer ownership and queued input")
check(authority:UnregisterPeer(peerB.Id).Accepted, "Peer can be unregistered")
check(not authority:SubmitInput(peerB.Id, {
	EntityId = defender.Id, SimulationFrame = 14, NetworkSequence = 1, Inputs = {},
}).Accepted, "Unregistered peer loses authority")
check(authority:Disable().Accepted, "Authority can be disabled")
check(not authority:IsEnabled(), "Disable clears enabled state")
check(authority.Component.AuthorityState == AuthorityState.Inactive, "Disable enters Inactive state")
check(not authority:SubmitInput(peerA.Id, {}).Accepted, "Disabled authority cannot queue input")
check(authority:Enable().Accepted, "Authority can be re-enabled")

-- Late Rollback policy is explicit, and never invokes an alternate simulation or fake fallback.
local rollbackWorld = World.new({
	InputProfile = inputProfile,
	ComponentFactories = {
		["AuthorityTest.Counter"] = function(_, state)
			local component = Counter.new()
			component.Value = state.Value
			component.Frames = state.Frames
			return component
		end,
	},
	RollbackProfile = RollbackProfile.new({
		HistorySize = 8, MaxRollbackFrames = 8, MaxReplayFrames = 8,
		RecordReplayFrames = true,
	}),
	Authority = {
		PublishSnapshots = false,
		PastInputPolicy = AuthorityPolicy.PastInput.Rollback,
		MaxPastFrames = 8,
		MaxInputDelayFrames = 8,
	},
})
Simulation.new(rollbackWorld, { Seed = 73 })
local rollbackEntity = rollbackWorld:CreateEntity()
addInputAndCounter(rollbackEntity)
check(rollbackWorld:GetRollbackResolver():Enable(rollbackEntity).Accepted,
	"Rollback-policy world enables its rollback participant")
local rollbackPeer = NetworkPeer.new("late-peer", NetworkPeer.Role.Client)
rollbackWorld:GetNetworkResolver():RegisterPeer(rollbackPeer)
rollbackPeer.State = NetworkPeer.State.Connected
local lateAuthority = rollbackWorld:GetAuthorityResolver()
lateAuthority:RegisterPeer(rollbackPeer)
lateAuthority:BindEntity(rollbackPeer.Id, rollbackEntity)
lateAuthority:Enable()
local seedSnapshotResult = rollbackWorld:GetRollbackResolver():RecordFrame(
	rollbackWorld, { Confirmed = true })
check(seedSnapshotResult.Accepted,
	"Rollback-policy world records a confirmed seed snapshot: "
		.. tostring(seedSnapshotResult.Type) .. " "
		.. tostring(seedSnapshotResult.Detail))
check(lateAuthority:Advance(1).Accepted
	and rollbackWorld:GetRollbackResolver():RecordFrame(rollbackWorld).Accepted,
	"Rollback-policy world records frame one history")
check(lateAuthority:Advance(2).Accepted
	and rollbackWorld:GetRollbackResolver():RecordFrame(rollbackWorld).Accepted,
	"Rollback-policy world records frame two history")
local lateResult = lateAuthority:SubmitInput(rollbackPeer.Id, {
	EntityId = rollbackEntity.Id, SimulationFrame = 1, NetworkSequence = 1,
	Inputs = { [Input.Light] = InputState.Pressed },
})
check(lateResult.Accepted and lateResult.Replayed == true,
	("Late rollback accepts input when snapshot and replay history are complete (%s: %s)")
		:format(tostring(lateResult.Type), tostring(lateResult.Detail)))
check(lateAuthority:GetAuthoritativeFrame() == 2, "Late rollback preserves the authoritative frame cursor")
local restoredRollbackEntity = rollbackWorld:GetEntity(rollbackEntity.Id)
local restoredCounter = restoredRollbackEntity and restoredRollbackEntity:GetComponent(Counter)
check(restoredCounter ~= nil and restoredCounter.Value == 11,
	("Late rollback replays the authoritative input into the simulation (value=%s)")
		:format(tostring(restoredCounter and restoredCounter.Value)))
check(rollbackWorld:GetRollbackResolver() ~= nil, "Authority reuses the world's existing RollbackResolver boundary")
local unsupportedLate = lateAuthority:SubmitInput(rollbackPeer.Id, {
	EntityId = rollbackEntity.Id, SimulationFrame = 0, NetworkSequence = 2,
	Inputs = { [Input.Light] = InputState.Pressed },
})
check(not unsupportedLate.Accepted and unsupportedLate.Type == AuthorityResult.Type.RollbackUnsupported,
	"Late rollback rejects input without a preceding snapshot frame")
local afterRejectedLate = lateAuthority:SubmitInput(rollbackPeer.Id, {
	EntityId = rollbackEntity.Id, SimulationFrame = 3, NetworkSequence = 2,
	Inputs = { [Input.Light] = InputState.Pressed },
})
check(afterRejectedLate.Accepted, "Rejected late rollback does not consume the network sequence")

local incompleteWorld = World.new({
	InputProfile = inputProfile,
	Authority = { PublishSnapshots = true, SnapshotInterval = 1 },
})
Simulation.new(incompleteWorld)
local incompleteEntity = incompleteWorld:CreateEntity()
incompleteEntity:AddComponent(InputComponent.new(inputProfile))
local incompleteAuthority = incompleteWorld:GetAuthorityResolver()
check(incompleteAuthority:Enable().Accepted, "Authority can run without a public snapshot projection")
local incompleteAdvance = incompleteAuthority:Advance(1)
check(incompleteAdvance.Accepted, "Missing snapshot adapter does not alter successful Simulation advancement")
check(incompleteAdvance.SnapshotResult.Type == AuthorityResult.Type.SnapshotFailed,
	"Missing complete filter is an explicit snapshot failure")
check(incompleteAuthority.Component.LastPublishedFrame == nil,
	"Incomplete lifecycle-only data is never reported as published")
check(incompleteAuthority:GetAuthoritativeFrame() == 1,
	"Snapshot capability failure does not fabricate or rewind the authoritative frame")

local invalidFrames = { -1, 0.5, math.huge, -math.huge, 0 / 0, "1", {}, false }
for _, invalidFrame in ipairs(invalidFrames) do
	check(not AuthorityValidation.Parse({
		EntityId = attacker.Id, SimulationFrame = invalidFrame, NetworkSequence = 15, Inputs = {},
	}, authority.Profile, inputProfile, peerA.Id), "Malformed frame is rejected")
end
local invalidSequences = { -1, 0.5, math.huge, 4294967296, "1", {}, false }
for _, invalidSequence in ipairs(invalidSequences) do
	check(not AuthorityValidation.Parse({
		EntityId = attacker.Id, SimulationFrame = 14, NetworkSequence = invalidSequence, Inputs = {},
	}, authority.Profile, inputProfile, peerA.Id), "Malformed transport sequence is rejected")
end
local invalidPayloads = { false, 1, "input", function() end, setmetatable({}, {}) }
for _, invalidPayload in ipairs(invalidPayloads) do
	check(not AuthorityValidation.Parse(invalidPayload, authority.Profile, inputProfile, peerA.Id),
		"Non-table or metatable input payload is rejected")
end
for _, forbidden in ipairs(forbiddenFields) do
	local bad = {
		EntityId = attacker.Id, SimulationFrame = 14, NetworkSequence = 15,
		Inputs = { [Input.Guard] = InputState.Pressed },
	}
	bad[forbidden] = true
	check(not AuthorityValidation.Parse(bad, authority.Profile, inputProfile, peerA.Id),
		"Forbidden authority field cannot pass validation: " .. forbidden)
end

check(not pcall(function()
	AuthoritySnapshot.new({ SimulationFrame = -1, Entities = {} })
end), "Snapshot rejects negative frame")
check(not pcall(function()
	AuthoritySnapshot.new({ SimulationFrame = 1.25, Entities = {} })
end), "Snapshot rejects fractional frame")
check(not pcall(function()
	AuthoritySnapshot.new({ SimulationFrame = math.huge, Entities = {} })
end), "Snapshot rejects non-finite frame")
local unserializable = Instance.new("Folder")
local instanceRejected = not pcall(function()
	AuthoritySnapshot.new({ SimulationFrame = 1, Entities = { Instance = unserializable } })
end)
unserializable:Destroy()
check(instanceRejected, "Snapshot rejects Roblox Instances")
local cycle = {}
cycle.Self = cycle
check(not pcall(function()
	AuthoritySnapshot.new({ SimulationFrame = 1, Entities = { cycle } })
end), "Snapshot rejects cyclic data")
check(not pcall(function()
	AuthoritySnapshot.new({ SimulationFrame = 1, Entities = { { Value = function() end } } })
end), "Snapshot rejects functions")
check(not pcall(function()
	AuthoritySnapshot.new({ SimulationFrame = 1, Entities = { { Value = math.huge } } })
end), "Snapshot rejects non-finite component data")
check(not pcall(function()
	AuthoritySnapshot.new({ SimulationFrame = 1, Entities = setmetatable({}, {}) })
end), "Snapshot rejects metatable-backed entity data")
local snapshotSource = { SimulationFrame = 1, Entities = { { Id = 1, Components = { Safe = 7 } } } }
local clonedSnapshot = AuthoritySnapshot.new(snapshotSource)
snapshotSource.Entities[1].Components.Safe = 8
check(clonedSnapshot.Entities[1].Components.Safe == 7, "Snapshot copies data instead of retaining client or component aliases")

-- Deterministic agreement check: identical initial seed and frame-indexed inputs produce identical state.
local function makeDeterministicWorld()
	local testWorld = World.new({ InputProfile = inputProfile, Authority = { PublishSnapshots = false } })
	Simulation.new(testWorld, { Seed = 991 })
	local entity = testWorld:CreateEntity()
	local counter = addInputAndCounter(entity)
	local peer = NetworkPeer.new("deterministic-peer", NetworkPeer.Role.Client)
	testWorld:GetNetworkResolver():RegisterPeer(peer)
	peer.State = NetworkPeer.State.Connected
	local resolver = testWorld:GetAuthorityResolver()
	resolver:RegisterPeer(peer)
	resolver:BindEntity(peer.Id, entity)
	resolver:Enable()
	resolver:SubmitInput(peer.Id, {
		EntityId = entity.Id, SimulationFrame = 1, NetworkSequence = 10,
		Inputs = { [Input.Light] = InputState.Pressed },
	})
	resolver:SubmitInput(peer.Id, {
		EntityId = entity.Id, SimulationFrame = 2, NetworkSequence = 11,
		Inputs = { [Input.Light] = InputState.Held },
	})
	resolver:Advance(2)
	return testWorld, counter
end
local deterministicWorldA, deterministicCounterA = makeDeterministicWorld()
local deterministicWorldB, deterministicCounterB = makeDeterministicWorld()
check(deterministicCounterA.Value == deterministicCounterB.Value, "Same seed and input history produce same component state")
check(deterministicCounterA.Frames == deterministicCounterB.Frames, "Deterministic runs process the same number of frames")
check(deterministicWorldA:GetSimulation():GetRNG():GetState() == deterministicWorldB:GetSimulation():GetRNG():GetState(),
	"Deterministic runs preserve identical RNG state")
check(deterministicWorldA.CurrentFrame == deterministicWorldB.CurrentFrame, "Deterministic runs finish on identical simulation frame")

local networkSnapshot = network:CreateSnapshot({
	SimulationFrame = snapshot.SimulationFrame,
	Sequence = snapshot.NetworkSequence,
	Entities = snapshot.Entities,
	Components = snapshot.Components,
	Metadata = { Authority = true },
})
check(networkSnapshot.SimulationFrame == snapshot.SimulationFrame, "NetworkSnapshot retains SimulationFrame")
check(networkSnapshot.Sequence ~= networkSnapshot.SimulationFrame, "NetworkSnapshot sequence stays distinct")
check(networkSnapshot.Entities[1].Health == nil, "NetworkSnapshot contains only projected authority data")
check(#world:GetAuthorityEvents() == #authority:GetEvents(), "World exposes authority events")
check(#world:GetAuthorityResults() == #authority:GetResults(), "World exposes authority results")
check(#authority:GetEvents() > 0, "Authority records lifecycle and input events")
check(#authority:GetResults() > 0, "Authority records structured operation results")
check(authority:GetEvents()[1].Type == AuthorityEvent.Type.Started, "Authority lifecycle event begins at start")
check(authority.Component.RejectedInputFrames ~= nil, "Component tracks bounded rejected input diagnostics")
check(authority.Component.AcceptedInputFrames ~= nil, "Component tracks bounded accepted input diagnostics")
check(authority.Component.PendingInputFrames ~= nil, "Component owns deterministic frame queue")
check(authority.Component.AuthorityState == AuthorityState.Active, "Authority remains active after diagnostics")
check(attackerCounter.Value == 11, "No forged combat state changed the authoritative simulation result")
check(defenderCounter.Value == 0, "Client-provided target health/damage was never applied")
check(authority.Component.LastProcessedInputFrame == 13, "Input cursor reflects last actually simulated input frame")
check(authority:GetAuthoritativeFrame() == 13, "Current authority cursor is distinct from last input cursor")
check(assertions >= 220, "Authority test suite contains at least 220 counted runtime assertions")

print("Combat authority tests passed")
