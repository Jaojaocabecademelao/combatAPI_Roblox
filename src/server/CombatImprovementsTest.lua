return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local Combat = Shared:WaitForChild("Combat")
	local CombatAPI = require(Shared.CombatAPI)
	local Projectile = require(Combat.Projectile)
	local SceneQuery = require(Combat.SceneQuery)
	local Presentation = require(Combat.Presentation)
	local RestoreReadiness = require(Combat.RestoreReadiness)
	local PerformanceBudget = require(Combat.PerformanceBudget)
	local ActionTimeline = require(Combat.ActionTimeline)
	local CombatActionDefinition = require(Combat.CombatActionDefinition)
	local CombatSession = require(Combat.CombatSession)
	local AdapterConformance = require(Combat.AdapterConformance)

	local projectile = Projectile.new({
		Id = "projectile.test",
		Position = Vector3.new(0, 0, 0),
		Velocity = Vector3.new(10, 0, 0),
		Acceleration = Vector3.new(0, 0, 0),
		MaxSpeed = 12,
		Drag = 0,
		LifetimeFrames = 3,
		ContactPolicy = Projectile.ContactPolicy.Reflect,
	})
	projectile:Step(1)
	assert(projectile.Position == Vector3.new(10, 0, 0)
		and projectile.ElapsedFrames == 1,
		"Projectile advances authoritative position and elapsed frames")
	local reflected = projectile:ResolveContact({ Normal = Vector3.new(-1, 0, 0) })
	assert(reflected == Projectile.ContactPolicy.Reflect
		and projectile.Velocity.X == -10,
		"Projectile reflect policy updates deterministic velocity")
	local captured = projectile:Capture()
	local restored = Projectile.new({ Position = Vector3.zero }):Restore(captured)
	assert(restored.Position == Vector3.new(10, 0, 0)
		and restored.ElapsedFrames == 1,
		"Projectile capture/restore preserves authoritative state")

	local world = CombatAPI.CreateWorld()
	local sceneQuery = SceneQuery.new(world)
	local outcome = sceneQuery:Resolve(1, "wall:1", "geometry.mock", "1",
		{ Origin = "test", Direction = "forward" },
		function()
			return { Hit = true, ObjectId = "wall:1" }
		end)
	assert(outcome.Hit and outcome.ObjectId == "wall:1",
		"SceneQuery records and returns a serializable external result")
	assert(sceneQuery:GetQuery("wall:1").Frame == 1,
		"SceneQuery exposes inspected query metadata")

	local presentation = Presentation.new()
	local effectId = presentation:Create("effect:1", "ProjectileSpawn", { ProjectileId = "p1" })
	assert(presentation:Get(effectId).State == Presentation.State.Speculative,
		"Presentation effects begin speculative")
	assert(presentation:Confirm(effectId),
		"Presentation effects can be confirmed")
	assert(presentation:Get(effectId).State == Presentation.State.Confirmed,
		"Confirmed presentation state is preserved")
	local interpolated = presentation:InterpolatePosition(
		Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), 0.25)
	assert(interpolated == Vector3.new(2.5, 0, 0),
		"Presentation interpolation returns a visual-only interpolated position")

	local session = CombatSession.new(world)
	assert(session:RegisterPeer("peer.1"),
		"CombatSession registers a stable peer")
	local proposed = session:ProposeInput("peer.1", "entity.1", 2, 1, { Move = "Forward" })
	assert(proposed.Move == "Forward",
		"CombatSession preserves proposed serializable input")
	assert(select(1, session:AcceptInput("peer.1", "entity.1", 2)),
		"CombatSession accepts proposed input")
	assert(session:ConfirmFrame(2),
		"CombatSession confirms an authoritative frame")
	local sessionStatus = session:GetStatus()
	assert(sessionStatus.ConfirmedFrame == 2
		and sessionStatus.State == CombatSession.State.Confirmed,
		"CombatSession status exposes confirmed frame and state")

	local conformance = AdapterConformance.new()
	conformance:Register("presentation.adapter", {
		Version = "1.0.0",
		Authoritative = false,
		Contexts = { AdapterConformance.Context.Normal },
		Adapter = {},
		Cleanup = function() end,
	})
	conformance:Register("authority.adapter", {
		Version = "1.0.0",
		Authoritative = true,
		Contexts = {
			AdapterConformance.Context.Normal,
			AdapterConformance.Context.Replay,
			AdapterConformance.Context.Rollback,
		},
		CaptureRollbackState = function() return { Version = 1 } end,
		ValidateRollbackState = function(_, state) return state.Version == 1 end,
		PrepareRollbackRestore = function() return function() end end,
		Adapter = {},
		Cleanup = function() end,
	})
	local conformanceReport = conformance:Report()
	assert(conformanceReport.Passed and conformanceReport.FailedCount == 0
		and #conformanceReport.Adapters == 2,
		"AdapterConformance reports registered adapter guarantees")

	local readiness = RestoreReadiness.new()
	readiness:RegisterParticipant("test.state", {
		CaptureRollbackState = function() return { Version = 1, Value = 5 } end,
		ValidateRollbackState = function(_, state) return state.Version == 1 and state.Value == 5 end,
		PrepareRollbackRestore = function() return function() end end,
	})
	readiness:AddExternalDependency("wall:1", "geometry.mock", "1")
	local report = readiness:Report(world)
	assert(report.CanRestore and #report.Ready == 1
		and #report.ExternalDependencies == 1,
		"RestoreReadiness reports ready participants and external dependencies")

	local budget = PerformanceBudget.new({
		CandidatePairs = 100,
		Contacts = 10,
	})
	local budgetResult = budget:Check({ CandidatePairs = 120, Contacts = 3 })
	assert(not budgetResult.Passed and #budgetResult.Violations == 1
		and budgetResult.Violations[1].Metric == "CandidatePairs",
		"PerformanceBudget rejects exceeded named limits")

	local definition = CombatActionDefinition.new({
		Id = "timeline.test",
		StartupFrames = 2,
		ActiveFrames = 2,
		RecoveryFrames = 1,
		GameplayEvents = {
			{ FrameOffset = 3, Type = "combat.test.v1", Parameters = { Value = 1 } },
		},
	})
	local timeline = ActionTimeline.new(definition)
	assert(timeline:GetFrame(1).Phase == "Startup"
		and timeline:GetFrame(3).Phase == "Active"
		and timeline:GetFrame(3).Events[1].Type == "combat.test.v1"
		and timeline:GetFrame(5).Phase == "Recovery",
		"ActionTimeline exposes phases and frame events")

	world:Destroy()
	print("CombatImprovementsTest passed")
end
