local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return
end

local started = false
local function startSmokeTest()
	if started or ReplicatedStorage:GetAttribute("CombatMultiplayerSmokeTest") ~= true then
		return
	end
	started = true

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Core.World)
local NetworkPeer = require(Shared.Combat.NetworkPeer)
local NetworkMessage = require(Shared.Combat.NetworkMessage)
local NetworkChannel = require(Shared.Combat.NetworkChannel)
local RemoteAdapter = require(Shared.Combat.RobloxRemoteEventAdapter)

local remote = ReplicatedStorage:FindFirstChild("CombatMultiplayerSmokeEvent")
if remote then
	assert(remote:IsA("RemoteEvent"), "CombatMultiplayerSmokeEvent must be a RemoteEvent")
else
	remote = Instance.new("RemoteEvent")
	remote.Name = "CombatMultiplayerSmokeEvent"
	remote.Parent = ReplicatedStorage
end

local world = World.new()
local resolver = world:GetNetworkResolver()
print(("Combat multiplayer smoke server started; connected players: %d"):format(#Players:GetPlayers()))
local completedPeers = {}
local startedPeers = {}
local finished = false
local adapter

adapter = RemoteAdapter.new(remote, {
	Role = "Server",
	GetPlayer = function(peerId)
		return Players:GetPlayerByUserId(peerId)
	end,
	GetPeerId = function(player)
		return player.UserId
	end,
	OnReceive = function(peerId, message, player)
		if finished then
			return
		end
		print(("Combat multiplayer smoke server received a message from %s"):format(tostring(peerId)))
		if not player or player.UserId ~= peerId or message.Sender ~= tostring(peerId)
			or message.Type ~= NetworkMessage.Type.Input
			or message.Channel ~= NetworkChannel.Input
			or type(message.Payload) ~= "table"
			or message.Payload.Test ~= "CombatMultiplayerSmoke"
			or message.Payload.UserId ~= peerId then
			warn(("Combat multiplayer smoke rejected message from peer %s"):format(tostring(peerId)))
			return
		end

		local received = resolver:Receive(peerId, message)
		if not received.Accepted then
			warn(("Combat multiplayer smoke network receive rejected: %s"):format(received.Type))
			return
		end

		if completedPeers[peerId] then
			return
		end
		completedPeers[peerId] = true
		local ack = NetworkMessage.new({
			Type = NetworkMessage.Type.Event,
			Channel = NetworkChannel.Events,
			Sequence = 1,
			SimulationFrame = message.SimulationFrame,
			Sender = "server",
			Payload = {
				Test = "CombatMultiplayerSmoke",
				UserId = peerId,
				Status = "Acknowledged",
			},
		})
		local sent = resolver:Send(peerId, ack, { AdapterId = "RobloxRemoteEvent" })
		assert(sent.Accepted, "Combat multiplayer smoke failed to send client acknowledgement")

		local count = 0
		for _ in pairs(completedPeers) do count += 1 end
		print(("Combat multiplayer smoke acknowledged client %d (%d/2)"):format(peerId, count))
		if count >= 2 and not finished then
			finished = true
			print("Combat multiplayer smoke test passed (2 clients, bidirectional RemoteEvent, peer validation)")
			adapter:Stop()
			world:Destroy()
		end
	end,
})

assert(resolver:RegisterAdapter("RobloxRemoteEvent", adapter.Transport), "Remote adapter registration failed")
assert(adapter:Start(), "Remote adapter failed to start")

local function registerPlayer(player)
	if startedPeers[player.UserId] then
		return
	end
	startedPeers[player.UserId] = true
	local peer = NetworkPeer.new(player.UserId, NetworkPeer.Role.Client)
	local registered = resolver:RegisterPeer(peer)
	assert(registered.Accepted, "Failed to register multiplayer smoke peer")
	local connected = resolver:Connect(player.UserId, { AdapterId = "RobloxRemoteEvent" })
	assert(connected.Accepted, "Failed to connect multiplayer smoke peer")
	print(("Combat multiplayer smoke registered client %d"):format(player.UserId))
end

Players.PlayerAdded:Connect(registerPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	registerPlayer(player)
end

task.delay(60, function()
	if finished then
		return
	end
	local count = 0
	for _ in pairs(completedPeers) do count += 1 end
	if count < 2 then
		local peerCount = 0
		for _ in pairs(startedPeers) do peerCount += 1 end
		error(("Combat multiplayer smoke timed out: acknowledged %d of 2 clients; registered %d peers; Players has %d")
			:format(count, peerCount, #Players:GetPlayers()))
	end
end)
end

ReplicatedStorage:GetAttributeChangedSignal("CombatMultiplayerSmokeTest"):Connect(startSmokeTest)
startSmokeTest()
