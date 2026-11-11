local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core, Combat = Shared:WaitForChild("Core"), Shared:WaitForChild("Combat")
local World = require(Core.World)
local CombatEntity = require(Core.CombatEntity)
local JuggleComponent = require(Combat.JuggleComponent)
local MotionType = require(Combat.MotionType)

local function check(value, message) assert(value, message) end

local world = World.new()
local attacker, target = world:CreateEntity(), world:CreateEntity()
target:AddComponent(JuggleComponent.new())
local resolver = world:GetJuggleResolver()
resolver:Process({}, { { Type = MotionType.Launch, Source = attacker, Target = target, Frame = 4 } }, {}, 4)
local savedComponent = target:GetComponent(JuggleComponent):CaptureRollbackState()
local savedResolver = resolver:CaptureRollbackState()
check(savedComponent.Active and savedComponent.AttackerId == attacker.Id, "Juggle component must capture active attacker identity")
check(#savedResolver.Active == 1, "Juggle resolver must capture its active index")

resolver:Break(target, "RollbackTest", 5)
check(#resolver:GetActiveJuggles() == 0, "Mutation must end the live juggle")

local stagedAttacker, stagedTarget = CombatEntity.new(attacker.Id), CombatEntity.new(target.Id)
local stagedById = { [attacker.Id] = stagedAttacker, [target.Id] = stagedTarget }
local stagedComponent = stagedTarget:AddComponent(JuggleComponent.new())
local restored, restoreError = stagedComponent:RestoreRollbackState(savedComponent, { EntitiesById = stagedById })
check(restored == true, "Staged JuggleComponent restore failed: " .. tostring(restoreError))
local context = { TargetEntitiesById = stagedById, CurrentEntitiesById = { [attacker.Id] = attacker, [target.Id] = target } }
local commit, prepareError = resolver:PrepareRollbackRestore(savedResolver, world, context, "Target")
check(type(commit) == "function", "JuggleResolver prepare failed: " .. tostring(prepareError))
commit()
local active = resolver:GetActiveJuggles()
check(#active == 1 and active[1].Target == stagedTarget and active[1].Attacker == stagedAttacker,
	"Restored juggle must reference staged entities")
check(active[1].LaunchFrame == 4 and stagedComponent.AttackerId == attacker.Id,
	"Juggle temporal state and attacker ID must survive restore")
check(#resolver:GetEvents() == 0 and #resolver:GetResults() == 0,
	"Target restore must clear frame-local juggle output buffers for replay")

local invalid = table.clone(savedComponent)
invalid.AttackerId = nil
check(stagedComponent:ValidateRollbackState(invalid) == false, "Active juggle without attacker ID must be rejected")
world:Destroy()
print("CombatJuggleRollbackTest passed")
