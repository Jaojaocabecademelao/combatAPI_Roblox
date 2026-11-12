--!strict
-- Reference consumer: uses only the CombatAPI public module.
-- Copy this script into ServerScriptService to run it in a test place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatAPI = require(ReplicatedStorage.Shared.CombatAPI)
local CombatAPITypes = require(ReplicatedStorage.Shared.CombatAPITypes)
type AttackOptions = CombatAPITypes.AttackOptions
type AttackInstanceOptions = CombatAPITypes.AttackInstanceOptions

local world: CombatAPITypes.World = CombatAPI.CreateWorld()
local collisionWorld = CombatAPI.CollisionWorld.new(world)
local attackCatalog = CombatAPI.AttackCatalog.new()

local chargedAttackOptions: AttackOptions = {
    Id = "example.charged-strike",
    Damage = 12,
    Hitstun = 18,
    CustomData = {
        BaseRadius = 3,
        Element = "Arcane",
        Visual = { Trail = "Blue" },
    },
}
local chargedAttack: CombatAPITypes.Attack = CombatAPI.Attack.new(chargedAttackOptions)

attackCatalog:Register(chargedAttack, 1)
attackCatalog:Seal()
collisionWorld:SetAttackCatalog(attackCatalog)

local attacker = world:CreateEntity()
local attackerId = attacker.Id
local initialState = world:CaptureCombatState()

local function applyCharge(chargeFrames: number)
    -- Restore rebuilds the entity roster, so always reacquire by stable ID.
    local owner = world:GetEntity(attackerId)
    assert(owner ~= nil, "Attacker entity is unavailable")

    local radius = 3 + math.floor(chargeFrames / 12)
    local instanceOptions: AttackInstanceOptions = {
        Id = "example.charged-strike.instance",
        CustomDataOverrides = {
            Radius = radius,
            ChargeFrames = chargeFrames,
            Visual = { Trail = "ChargedBlue" },
        },
    }
    local attackInstance = CombatAPI.AttackInstance.new(chargedAttack, owner, nil, instanceOptions)

    attackInstance:Activate()
    local hitbox = CombatAPI.Hitbox.new({
        Id = 7001,
        Owner = owner,
        AttackId = chargedAttack.Id,
        Position = Vector3.new(0, 3, 0),
        Size = Vector3.new(radius * 2, 4, radius * 2),
        Damage = 12,
        Hitstun = 18,
    })
    attackInstance:AddHitbox(hitbox)
    -- Register the region directly: Hitbox is rollback-owned by CollisionWorld,
    -- not a generic Entity component with its own CaptureRollbackState contract.
    collisionWorld:RegisterHitbox(hitbox)
end

local chargeFrames = 24
applyCharge(chargeFrames)
local firstRunState = world:CaptureCombatState()
local firstRunHash = world:HashCombatState(firstRunState)

-- Roll back to the pre-action state and replay the same deterministic input.
local restored, restoreError = world:RestoreCombatState(initialState)
assert(restored, "Initial rollback failed: " .. tostring(restoreError))
applyCharge(chargeFrames)
local replayedState = world:CaptureCombatState()
local replayedHash = world:HashCombatState(replayedState)
assert(firstRunHash == replayedHash, "Deterministic CustomData replay diverged")

-- Build a deterministic fingerprint from every field in the sorted attack manifest.
-- A production game should combine this with its other gameplay content manifests.
local function buildCatalogFingerprint(catalog)
    local manifest = catalog:CaptureManifest()
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
    return table.concat(parts, "|")
end

-- Persist the input/hash pair so a host can compare later replay executions.
local recording = CombatAPI.ReplayRecording.new({
    Metadata = {
        ContentFingerprint = buildCatalogFingerprint(attackCatalog),
        StartFrame = 0,
    },
    InitialState = initialState,
})
recording:AppendFrame(1, { ChargeFrames = chargeFrames }, replayedHash)
local loadedRecording, recordingError = CombatAPI.ReplayRecording.FromSnapshot(recording:Capture())
assert(loadedRecording ~= nil, "Replay recording failed to load: " .. tostring(recordingError))
local divergence = recording:FindFirstDivergence(loadedRecording)
assert(divergence == nil, "Serialized replay recording diverged")

print("CustomData consumer example passed", replayedHash)
world:Destroy()
