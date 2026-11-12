return function()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatAPI = require(ReplicatedStorage.Shared.CombatAPI)

local world = CombatAPI.CreateWorld()
local ok, failure = pcall(function()
	CombatAPI.Simulation.new(world, { Seed = 17 })
	local collisionWorld = CombatAPI.CollisionWorld.new(world)
	local attackCatalog = CombatAPI.AttackCatalog.new()
	local chargedAttack = CombatAPI.Attack.new({
		Id = "consumer-test.charged-strike",
		Damage = 12,
		Hitstun = 18,
		CustomData = {
			BaseRadius = 3,
			Element = "Arcane",
			Visual = { Trail = "Blue" },
		},
	})
	attackCatalog:Register(chargedAttack, 1)
	attackCatalog:Seal()
	collisionWorld:SetAttackCatalog(attackCatalog)

	local topologyCatalog = CombatAPI.CollisionTopologyCatalog.new()
	topologyCatalog:Register("consumer-test.charged-hitbox", 1, function(saved, owner)
		assert(saved.Shape == "Box", "Unexpected consumer-test hitbox shape")
		return CombatAPI.Hitbox.new({
			Id = saved.Id,
			Owner = owner,
			Shape = "Box",
			Size = Vector3.new(saved.Size[1], saved.Size[2], saved.Size[3]),
			Position = Vector3.new(0, 0, 0),
			Enabled = saved.Enabled,
			Priority = saved.PriorityOverride,
			ClashGroup = saved.ClashGroup,
			Damage = saved.Damage,
			Hitstun = saved.Hitstun,
			HitPolicy = saved.HitPolicy,
			HitScope = saved.HitScope,
			TopologyDefinitionId = "consumer-test.charged-hitbox",
			TopologyDefinitionVersion = 1,
		})
	end)
	topologyCatalog:Seal()
	collisionWorld:SetTopologyCatalog(topologyCatalog)

	local attacker = world:CreateEntity()
	local attackerId = attacker.Id
	local hitbox = CombatAPI.Hitbox.new({
		Id = 7001,
		Owner = attacker,
		AttackId = chargedAttack.Id,
		Position = Vector3.new(0, 3, 0),
		Size = Vector3.new(6, 4, 6),
		Damage = 12,
		Hitstun = 18,
		TopologyDefinitionId = "consumer-test.charged-hitbox",
		TopologyDefinitionVersion = 1,
	})
	collisionWorld:RegisterHitbox(hitbox)
	local initialState = world:CaptureCombatState()

	local function getConsumerHitbox()
		for _, region in ipairs(collisionWorld:GetHitboxes()) do
			if region.Id == 7001 then
				return region
			end
		end
		return nil
	end

	local function applyCharge(chargeFrames)
		local owner = world:GetEntity(attackerId)
		assert(owner ~= nil, "Attacker entity is unavailable after restore")
		local currentHitbox = getConsumerHitbox()
		assert(currentHitbox ~= nil, "Hitbox is unavailable after collision topology restore")

		local radius = 3 + math.floor(chargeFrames / 12)
		local attackInstance = CombatAPI.AttackInstance.new(chargedAttack, owner, nil, {
			Id = "consumer-test.charged-strike.instance",
			CustomDataOverrides = {
				Radius = radius,
				ChargeFrames = chargeFrames,
				Visual = { Trail = "ChargedBlue" },
			},
		})
		currentHitbox.Size = Vector3.new(radius * 2, 4, radius * 2)
		attackInstance:AddHitbox(currentHitbox)
		return attackInstance
	end

	local chargeFrames = 24
	local firstInstance = applyCharge(chargeFrames)
	assert(firstInstance.OffensiveProperties.CustomData.Radius == 5,
		"Public attack instance must expose the effective frame-derived override")
	assert(firstInstance.OffensiveProperties.CustomData.Element == "Arcane",
		"Public override must inherit keys from the attack definition")
	assert(firstInstance.OffensiveProperties.CustomData.Visual.Trail == "ChargedBlue",
		"Public shallow merge must replace the nested definition value")
	local firstRunHash = world:HashCombatState(world:CaptureCombatState())

	firstInstance:RemoveHitbox(hitbox)
	local restored, restoreError = world:RestoreCombatState(initialState)
	assert(restored, "Initial rollback failed: " .. tostring(restoreError))
	local replayedInstance = applyCharge(chargeFrames)
	assert(replayedInstance.OffensiveProperties.CustomData.Radius == 5,
		"Replay must rebuild the same effective CustomData from frame input")
	local replayedHash = world:HashCombatState(world:CaptureCombatState())
	assert(firstRunHash == replayedHash, "Public CustomData consumer replay diverged")

	local manifest = attackCatalog:CaptureManifest()
	local parts = { "AttackCatalogManifest", tostring(manifest.Version) }
	local function append(value)
		local encoded = tostring(value)
		table.insert(parts, tostring(#encoded) .. ":" .. encoded)
	end
	for _, entry in ipairs(manifest.Entries) do
		append(entry.Id)
		append(entry.Version)
		append(entry.Priority)
		append(entry.CanClash)
		append(entry.HitPolicy)
		append(entry.HitScope)
		append(entry.Damage and entry.Damage.Amount)
		append(entry.Damage and entry.Damage.Type)
		append(entry.Hitstun)
		append(entry.HasCanHitCallback)
		append(entry.CustomDataCanonical)
	end

	local recording = CombatAPI.ReplayRecording.new({
		Metadata = {
			ContentFingerprint = table.concat(parts, "|"),
			StartFrame = 0,
		},
		InitialState = initialState,
	})
	recording:AppendFrame(1, { ChargeFrames = chargeFrames }, replayedHash)
	local loadedRecording, recordingError = CombatAPI.ReplayRecording.FromSnapshot(recording:Capture())
	assert(loadedRecording ~= nil,
		"Public replay recording failed to load: " .. tostring(recordingError))
	assert(recording:FindFirstDivergence(loadedRecording) == nil,
		"Serialized public replay recording must preserve its frame hash and fingerprint")
end)

world:Destroy()
assert(ok, "CustomData consumer test failed: " .. tostring(failure))
print("CombatCustomDataConsumerTest: PASS")
end
