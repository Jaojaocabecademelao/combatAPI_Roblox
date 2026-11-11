return function()
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Core, Combat = Shared:WaitForChild("Core"), Shared:WaitForChild("Combat")
local World = require(Core.World)
local EntityState = require(Core.EntityState)
local MovementState = require(Combat.MovementState)
local MovementStateComponent = require(Combat.MovementStateComponent)
local CancelComponent = require(Combat.CancelComponent)
local CancelProfile = require(Combat.CancelProfile)
local CancelResult = require(Combat.CancelResult)
local CancelEvent = require(Combat.CancelEvent)
local CancelType = require(Combat.CancelType)

local cases = 0
local function check(condition, message)
	assert(condition, message or ("Cancel assertion " .. tostring(cases + 1) .. " failed"))
	cases += 1
end

local profile = CancelProfile.new({
	Rules = {
		{ RuleId = "LightSpecial", FromAction = "LightAttack", ToAction = "Special",
			CancelType = CancelType.Special, StartFrame = 5, EndFrame = 15, Priority = 10 },
		{ RuleId = "LightDash", FromAction = "LightAttack", ToAction = "Dash",
			CancelType = CancelType.Dash, StartFrame = 0, EndFrame = 20, Priority = 5,
			RequiredMovementStates = { MovementState.Idle, MovementState.Moving } },
		{ RuleId = "RepeatMovement", FromAction = "LightAttack", ToAction = "Step",
			CancelType = CancelType.Movement, StartFrame = 0, EndFrame = 20, Repeatable = true },
		{ RuleId = "TieA", FromAction = "HeavyAttack", ToAction = "Special",
			CancelType = CancelType.Special, StartFrame = 0, EndFrame = 20, Priority = 1 },
		{ RuleId = "TieB", FromAction = "HeavyAttack", ToAction = "Special",
			CancelType = CancelType.Super, StartFrame = 0, EndFrame = 20, Priority = 1 },
	},
})
local world = World.new({ CancelProfile = profile })
local resolver = world:GetCancelResolver()
local entity = world:CreateEntity()
local movement = entity:AddComponent(MovementStateComponent.new(world:GetMovementStateResolver().Profile))
local cancel = entity:AddComponent(CancelComponent.new(profile))

check(profile:GetRules()[1].RuleId == "LightSpecial", "Profile preserves rule identity")
check(profile:GetRules()[1].FromAction == "LightAttack", "Rule preserves source action")
check(profile:GetRules()[1].ToAction == "Special", "Rule preserves target action")
check(profile:GetRules()[1].CancelType == CancelType.Special, "Rule preserves cancel type")
check(profile:GetRules()[1].StartFrame == 5 and profile:GetRules()[1].EndFrame == 15, "Rule preserves inclusive window")
check(profile:GetRules()[1].Priority == 10, "Rule preserves priority")
check(profile:GetRules()[2].RequiredMovementStates[1] == MovementState.Idle, "Rule preserves conditions")
check(profile:GetRules()[3].Repeatable, "Repeatable rule is configured")
check(not pcall(function() CancelProfile.new({ Rules = {
		{ RuleId = "Duplicate", FromAction = "A", ToAction = "B" },
		{ RuleId = "Duplicate", FromAction = "A", ToAction = "C" },
	} }) end), "Duplicate rule IDs are rejected")
check(not pcall(function() require(Combat.CancelRule).new({
		RuleId = "BadWindow", FromAction = "A", ToAction = "B", StartFrame = 5, EndFrame = 4,
	}) end), "Invalid windows are rejected")
check(not pcall(function() require(Combat.CancelRule).new({
		RuleId = "MissingSource", ToAction = "B",
	}) end), "Missing source action is rejected")
check(not pcall(function() require(Combat.CancelRule).new({
		RuleId = "MissingTarget", FromAction = "A",
	}) end), "Missing target action is rejected")
check(cancel:GetCurrentAction() == nil, "Component starts without an action")
check(cancel.ActionStartFrame == nil and cancel.ActionEndFrame == nil, "Action timing starts empty")
check(cancel.CancelCount == 0, "Cancel count starts at zero")
check(resolver:GetCurrentAction(entity) == nil, "Resolver sees no current action")
check(resolver:CanCancel(entity, "Special", { Frame = 100 }) == false, "No action cannot cancel")

local started = resolver:BeginAction(entity, "LightAttack", 100)
check(started.Type == CancelResult.Type.Allowed, "BeginAction accepts a valid action")
check(resolver:GetCurrentAction(entity) == "LightAttack", "Current action is queryable")
check(cancel.ActionStartFrame == 100, "Action start frame is recorded")
check(cancel.ActionEndFrame == nil, "Action end frame is optional")
check(cancel.ConsumedRules.LightSpecial == nil, "Beginning an action clears consumed rules")
check(resolver:CanCancel(entity, "Special", { Frame = 104 }) == false, "Frame before window is rejected")
local allowed = resolver:RequestCancel(entity, "Special", { Frame = 105, Source = "Test" })
check(allowed.Type == CancelResult.Type.Allowed and allowed.Allowed, "Window start is inclusive")
check(allowed.EntityId == entity.Id and allowed.CurrentAction == "LightAttack", "Allowed result identifies source")
check(allowed.RequestedAction == "Special" and allowed.CancelType == CancelType.Special, "Allowed result identifies target/type")
check(allowed.RuleId == "LightSpecial" and allowed.Frame == 105, "Allowed result identifies rule/frame")
check(resolver:GetEvents()[1].Type == CancelEvent.Type.Allowed, "CancelAllowed event is emitted")
check(resolver:GetEvents()[1].FromAction == "LightAttack", "Allowed event stores source")
check(resolver:GetEvents()[1].ToAction == "Special", "Allowed event stores target")
check(resolver:GetEvents()[1].RuleId == "LightSpecial", "Allowed event stores rule")
check(resolver:GetEvents()[1].Frame == 105, "Allowed event stores frame")
check(resolver:GetCurrentAction(entity) == "LightAttack", "Cancel does not execute target action")
check(cancel.CancelCount == 1 and cancel.LastCancelFrame == 105, "Request records consumption metadata")
check(resolver:GetCurrentAction(entity) ~= "Special", "Cancel does not replace the action")
check(resolver:CanCancel(entity, "Special", { Frame = 106 }) == true, "CanCancel does not consume a window")
local consumed = resolver:RequestCancel(entity, "Special", { Frame = 106 })
check(consumed.Type == CancelResult.Type.AlreadyCancelled, "Non-repeatable cancel is consumed")
check(not consumed.Allowed, "Consumed cancel is not allowed")
check(resolver:CanCancel(entity, "Special", { Frame = 115 }) == true, "Query remains non-mutating")
local atEnd = resolver:RequestCancel(entity, "Special", { Frame = 115 })
check(atEnd.Type == CancelResult.Type.AlreadyCancelled, "Consumption remains through window end")
check(resolver:CanCancel(entity, "Special", { Frame = 116 }) == false, "Frame after window is rejected")
local outside = resolver:RequestCancel(entity, "Special", { Frame = 116 })
check(outside.Type == CancelResult.Type.OutsideWindow, "Outside-window reason is explicit")
check(resolver:GetEvents()[#resolver:GetEvents()].Type == CancelEvent.Type.Rejected, "Rejected event is emitted")

local repeated = resolver:RequestCancel(entity, "Step", { Frame = 105 })
check(repeated.Type == CancelResult.Type.Allowed, "Repeatable cancel is allowed")
local repeatedAgain = resolver:RequestCancel(entity, "Step", { Frame = 106 })
check(repeatedAgain.Type == CancelResult.Type.Allowed, "Repeatable cancel remains allowed")
check(cancel.CancelCount == 3, "Repeatable requests increment count independently")

movement:SetState(MovementState.Crouching, 110)
resolver:BeginAction(entity, "LightAttack", 110)
local failedCondition = resolver:RequestCancel(entity, "Dash", { Frame = 110 })
check(failedCondition.Type == CancelResult.Type.ConditionFailed, "Movement condition can reject a cancel")
check(failedCondition.Reason == "ConditionFailed", "Condition failure reason is explicit")
movement:SetState(MovementState.Moving, 111)
local movementAllowed = resolver:RequestCancel(entity, "Dash", { Frame = 111 })
check(movementAllowed.Type == CancelResult.Type.Allowed, "Allowed movement state permits cancel")
check(resolver:GetCurrentAction(entity) == "LightAttack", "Movement condition does not mutate action")

resolver:BeginAction(entity, "HeavyAttack", 120)
local tie = resolver:RequestCancel(entity, "Special", { Frame = 120 })
check(tie.Type == CancelResult.Type.Allowed, "Equal-priority rules still resolve")
check(tie.RuleId == "TieA", "Equal priority uses deterministic RuleId ordering")
resolver:EndAction(entity, 130)
check(resolver:GetCurrentAction(entity) == nil, "EndAction clears current action")
check(cancel.ActionEndFrame == 130, "EndAction records end frame")
check(resolver:RequestCancel(entity, "Special", { Frame = 130 }).Type == CancelResult.Type.InvalidAction,
	"Ended action cannot cancel")

resolver:BeginAction(entity, "LightAttack", 140)
entity:SetState(EntityState.Dead)
local dead = resolver:RequestCancel(entity, "Special", { Frame = 145 })
check(dead.Type == CancelResult.Type.Rejected, "Dead entity cancel is rejected")
check(dead.Reason == "DeadEntity", "Dead entity reason is explicit")
check(cancel:GetCurrentAction() == nil, "Death resets cancel runtime")
entity:SetState(EntityState.Alive)
resolver:BeginAction(entity, "LightAttack", 150)
check(resolver:RequestCancel(entity, "Special", { Frame = 155 }).Allowed, "Alive entity can reuse cancel")

local second = world:CreateEntity()
second:AddComponent(CancelComponent.new(profile))
resolver:BeginAction(second, "LightAttack", 200)
check(resolver:RequestCancel(second, "Special", { Frame = 205 }).Allowed, "Second entity can cancel independently")
check(resolver:RequestCancel(entity, "Special", { Frame = 160 }).Type == CancelResult.Type.AlreadyCancelled,
	"First entity consumption is isolated")
check(resolver:GetCurrentAction(second) == "LightAttack", "Second action remains abstract")
check(resolver:GetCurrentAction(entity) == "LightAttack", "First action remains abstract")

resolver:Reset(entity)
check(resolver:GetCurrentAction(entity) == nil, "Reset clears action")
check(cancel.CancelCount == 0 and cancel.LastCancelFrame == nil, "Reset clears consumption metadata")
movement:SetState(MovementState.Moving, 304)
resolver:BeginAction(entity, "LightAttack", 300)
check(resolver:RequestCancel(entity, "Special", { Frame = 305 }).Allowed, "Reset permits a new sequence")
check(movement:GetState() == MovementState.Moving, "Cancel does not alter Movement State")
check(entity:GetState() == EntityState.Alive, "Cancel does not alter Entity State")
check(#resolver:GetResults() > 0 and #resolver:GetEvents() > 0, "Results and events are queryable")
resolver:Clear()
check(#resolver:GetResults() == 0 and #resolver:GetEvents() == 0, "Clear removes transient output")

for _, cancelType in ipairs({ CancelType.Normal, CancelType.Chain, CancelType.Special,
	CancelType.Super, CancelType.Movement, CancelType.Jump, CancelType.Dash, CancelType.Universal }) do
	check(type(cancelType) == "string" and cancelType ~= "", "CancelType remains a non-empty identifier")
end
local independentProfile = CancelProfile.new({
	Rules = {{ RuleId = "Independent", FromAction = "A", ToAction = "B", StartFrame = 0, EndFrame = 2 }},
})
local third = world:CreateEntity()
local thirdComponent = third:AddComponent(CancelComponent.new(independentProfile))
local independentResolver = require(Combat.CancelResolver).new(world, independentProfile)
check(independentResolver:BeginAction(third, "A", 10).Allowed, "Independent profile starts its own action")
check(independentResolver:RequestCancel(third, "B", { Frame = 10 }).Allowed, "Independent profile accepts its rule")
check(resolver:GetCurrentAction(entity) == "LightAttack", "Independent resolver does not mutate entity A")
check(resolver:GetCurrentAction(second) == "LightAttack", "Independent resolver does not mutate entity B")
check(thirdComponent:GetCurrentAction() == "A", "Allowed cancel does not execute target action")
check(independentResolver:GetResults()[2].Type == CancelResult.Type.Allowed, "Independent result is deterministic")
check(independentResolver:GetResults()[2].RuleId == "Independent", "Independent result selects its configured rule")
check(independentResolver:GetEvents()[1].Type == CancelEvent.Type.Allowed, "Independent event is emitted")
check(independentResolver:GetEvents()[1].EntityId == third.Id, "Independent event identifies its entity")
check(independentResolver:CanCancel(third, "B", { Frame = 11 }) == true, "CanCancel remains a non-consuming eligibility query")
check(independentResolver:RequestCancel(third, "B", { Frame = 11 }).Type == CancelResult.Type.AlreadyCancelled,
	"Independent consumed rule cannot be requested twice")
check(independentResolver:RequestCancel(third, "B", { Frame = 13 }).Type == CancelResult.Type.OutsideWindow,
	"Independent window expires deterministically")
check(independentProfile.Rules[1].RuleId == "Independent", "Profile remains unchanged after queries")
check(independentProfile.Rules[1].StartFrame == 0 and independentProfile.Rules[1].EndFrame == 2,
	"Profile window remains immutable")
check(third:GetState() == EntityState.Alive, "Cancel does not mutate third Core state")
check(thirdComponent.CancelCount == 1, "CanCancel does not consume another use after the first request")
check(resolver:GetCurrentAction(entity) == "LightAttack", "Querying another resolver is isolated")
check(resolver:GetCurrentAction(second) == "LightAttack", "Entity B action remains isolated")
check(type(resolver.IsCancelWindowActive) == "function", "Window query API exists")
check(type(resolver.BeginAction) == "function", "BeginAction API exists")
check(type(resolver.EndAction) == "function", "EndAction API exists")
check(type(resolver.RequestCancel) == "function", "RequestCancel API exists")
check(type(resolver.CanCancel) == "function", "CanCancel API exists")
check(type(resolver.Reset) == "function", "Reset API exists")
check(world:GetCancelResolver() == resolver, "World returns the configured CancelResolver")
check(resolver:GetCurrentAction(third) == "A",
	"Resolver lookup safely reads the action stored on an entity owned by another resolver")
check(cancel.Profile == profile, "Component retains its configured profile")
check(second:GetComponent(CancelComponent).Profile == profile, "Shared profiles do not share runtime state")
check(thirdComponent.Profile == independentProfile, "Independent component retains its own profile")
check(resolver:GetEvents() ~= resolver.Events, "Event query returns a copy")
check(resolver:GetResults() ~= resolver.Results, "Result query returns a copy")

print("Combat cancel tests passed (" .. tostring(cases) .. " cases)")

end
