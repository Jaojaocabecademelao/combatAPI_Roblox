--!strict
-- CharacterDatabase.lua (ModuleScript — ReplicatedStorage.Shared.Data)
-- Registro de todos os personagens disponíveis no jogo

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterClass = require(Shared:WaitForChild("CharacterClass"))

local CharacterDatabase = {}

-- ======================================================================
-- HELPERS PARA IDs DE ANIMAÇÃO
-- ======================================================================

-- Função helper para criar tabela de animações
-- Você substituirá os "0" pelos IDs reais
local function A(id: string): string
	return "rbxassetid://" .. id
end

-- ======================================================================
-- PERSONAGEM 1: BALANCED FIGHTER
-- ======================================================================

CharacterDatabase.BALANCED = CharacterClass.new({
	id = "fighter_balanced",
	name = "Balanced Fighter",
	description = "Personagem equilibrado, sem pontos fortes ou fracos extremos. Ideal para iniciantes.",

	stats = {
		health = 100,
		walkSpeed = 8,
		sprintSpeed = 16,
		jumpHeight = 8,
		weight = 1.0,  -- Neutro
	},

	frameModifiers = {
		startupMultiplier = 1.0,   -- Normal
		recoveryMultiplier = 1.0,  -- Normal
		damageMultiplier = 1.0,    -- Normal
	},

	movementModifiers = {
		dashSpeed = 20,
		dashCooldown = 180,  -- 3s
		crouchSpeedMultiplier = 0.6,
		airControl = 0.5,
	},

	animations = {
		-- Movimento
		idle = A("0000000001"),
		walk = A("0000000002"),
		sprint = A("0000000003"),
		crouch = A("0000000004"),
		jump = A("0000000005"),
		fall = A("0000000006"),

		-- Ataques Fracos (3 únicas: frente=parado=trás, esquerda, direita)
		jab_front = A("0000000010"),  -- W + LClick OU parado (neutral)
		jab_left = A("0000000011"),   -- A + LClick
		jab_right = A("0000000012"),  -- D + LClick
		jab_back = A("0000000010"),   -- S + LClick (REUSA jab_front)

		-- Ataques Fracos Agachados
		crouch_jab = A("0000000014"),
		crouch_sweep = A("0000000015"),
		crouch_uppercut = A("0000000016"),

		-- Ataques Fortes (3 únicas: charge, front, side)
		strong_charge_startup = A("0000000020"),
		strong_charge_release = A("0000000021"),
		strong_front = A("0000000022"),
		strong_left = A("0000000023"),   -- Soco lateral
		strong_right = A("0000000023"),  -- REUSA strong_left (mirror ou mesma)

		-- Ataques de Altura
		attack_low = A("0000000030"),
		attack_high = A("0000000031"),

		-- Defesa
		block_startup = A("0000000040"),
		block_idle = A("0000000041"),
		parry = A("0000000042"),

		-- Grab
		grab_startup = A("0000000050"),
		grab_hold = A("0000000051"),
		grab_throw = A("0000000052"),
		grabbed = A("0000000053"),
		thrown = A("0000000054"),
		mount = A("0000000055"),
		mounted = A("0000000056"),

		-- Movimento Especial (3 únicas: front, back, side)
		dash_front = A("0000000060"),
		dash_back = A("0000000061"),
		dash_left = A("0000000062"),     -- Dash lateral
		dash_right = A("0000000062"),    -- REUSA dash_left (mirror ou mesma)
		feint = A("0000000064"),
		slide = A("0000000065"),

		-- Parkour
		wall_run = A("0000000070"),
		wall_jump = A("0000000071"),
		ledge_grab = A("0000000072"),
		ledge_climb = A("0000000073"),

		-- Ataques Aéreos
		air_normal = A("0000000080"),
		air_divekick = A("0000000081"),
		air_plunging = A("0000000082"),
		air_grab = A("0000000083"),

		-- Hit Reactions
		hitstun_light = A("0000000090"),
		hitstun_heavy = A("0000000091"),
		blockstun = A("0000000092"),
		knockdown = A("0000000093"),
		getup = A("0000000094"),

		-- Morte (4 tipos)
		death_front = A("0000000100"),
		death_back = A("0000000101"),
		death_side = A("0000000102"),
		death_explosion = A("0000000103"),

		-- Emotes
		taunt_1 = A("0000000110"),  -- "Vem"
		taunt_2 = A("0000000111"),  -- Dança
		taunt_3 = A("0000000112"),  -- Flex
		victory_1 = A("0000000113"),
		victory_2 = A("0000000114"),
		victory_3 = A("0000000115"),

		-- Cinemáticas
		intro = A("0000000120"),
		outro_win = A("0000000121"),
		outro_lose = A("0000000122"),
	},
})

-- ======================================================================
-- PERSONAGEM 2: SPEED FIGHTER (Rushdown)
-- ======================================================================

CharacterDatabase.SPEED = CharacterClass.new({
	id = "fighter_speed",
	name = "Speed Demon",
	description = "Personagem rápido com ataques velozes e pouco dano. Estilo rushdown/pressure.",

	stats = {
		health = 90,        -- Menos HP
		walkSpeed = 10,     -- Mais rápido
		sprintSpeed = 18,   -- Sprint mais rápido
		jumpHeight = 9,     -- Pula mais alto
		weight = 0.9,       -- Mais leve (voa mais com knockback)
	},

	frameModifiers = {
		startupMultiplier = 0.85,   -- 15% mais rápido em startup
		recoveryMultiplier = 0.9,   -- 10% mais rápido em recovery
		damageMultiplier = 0.85,    -- 15% menos dano
	},

	movementModifiers = {
		dashSpeed = 24,         -- Dash mais rápido
		dashCooldown = 150,     -- Cooldown menor (2.5s)
		crouchSpeedMultiplier = 0.7,  -- Crouch mais rápido
		airControl = 0.7,       -- Mais controle no ar
	},

	animations = {
		-- TODO: Preencher com animações de speed character
		-- (Copie estrutura do BALANCED e ajuste IDs)
		idle = A("SPEED_IDLE_ID"),
		walk = A("SPEED_WALK_ID"),
		sprint = A("SPEED_SPRINT_ID"),

		jab_front = A("SPEED_JAB_FRONT"),
		jab_left = A("SPEED_JAB_LEFT"),
		jab_right = A("SPEED_JAB_RIGHT"),
		jab_back = A("SPEED_JAB_BACK"),

		crouch = A("SPEED_CROUCH"),
		crouch_jab = A("SPEED_CROUCH_JAB"),
		crouch_sweep = A("SPEED_SWEEP"),
		crouch_uppercut = A("SPEED_UPPERCUT"),

		strong_charge_startup = A("SPEED_CHARGE_START"),
		strong_charge_release = A("SPEED_CHARGE_RELEASE"),
		strong_front = A("SPEED_STRONG_FRONT"),
		strong_left = A("SPEED_STRONG_LEFT"),
		strong_right = A("SPEED_STRONG_RIGHT"),

		attack_low = A("SPEED_LOW"),
		attack_high = A("SPEED_HIGH"),

		block_startup = A("SPEED_BLOCK_START"),
		block_idle = A("SPEED_BLOCK_IDLE"),
		parry = A("SPEED_PARRY"),

		grab_startup = A("SPEED_GRAB_START"),
		grab_hold = A("SPEED_GRAB_HOLD"),
		grab_throw = A("SPEED_GRAB_THROW"),
		grabbed = A("SPEED_GRABBED"),
		thrown = A("SPEED_THROWN"),
		mount = A("SPEED_MOUNT"),
		mounted = A("SPEED_MOUNTED"),

		dash_front = A("SPEED_DASH_FRONT"),
		dash_back = A("SPEED_DASH_BACK"),
		dash_left = A("SPEED_DASH_LEFT"),
		dash_right = A("SPEED_DASH_RIGHT"),
		feint = A("SPEED_FEINT"),
		slide = A("SPEED_SLIDE"),

		wall_run = A("SPEED_WALL_RUN"),
		wall_jump = A("SPEED_WALL_JUMP"),
		ledge_grab = A("SPEED_LEDGE_GRAB"),
		ledge_climb = A("SPEED_LEDGE_CLIMB"),

		jump = A("SPEED_JUMP"),
		fall = A("SPEED_FALL"),
		air_normal = A("SPEED_AIR_NORMAL"),
		air_divekick = A("SPEED_AIR_DIVEKICK"),
		air_plunging = A("SPEED_AIR_PLUNGING"),
		air_grab = A("SPEED_AIR_GRAB"),

		hitstun_light = A("SPEED_HITSTUN_LIGHT"),
		hitstun_heavy = A("SPEED_HITSTUN_HEAVY"),
		blockstun = A("SPEED_BLOCKSTUN"),
		knockdown = A("SPEED_KNOCKDOWN"),
		getup = A("SPEED_GETUP"),

		death_front = A("SPEED_DEATH_FRONT"),
		death_back = A("SPEED_DEATH_BACK"),
		death_side = A("SPEED_DEATH_SIDE"),
		death_explosion = A("SPEED_DEATH_EXPLODE"),

		taunt_1 = A("SPEED_TAUNT_1"),
		taunt_2 = A("SPEED_TAUNT_2"),
		taunt_3 = A("SPEED_TAUNT_3"),
		victory_1 = A("SPEED_VICTORY_1"),
		victory_2 = A("SPEED_VICTORY_2"),
		victory_3 = A("SPEED_VICTORY_3"),

		intro = A("SPEED_INTRO"),
		outro_win = A("SPEED_OUTRO_WIN"),
		outro_lose = A("SPEED_OUTRO_LOSE"),
	},
})

-- ======================================================================
-- PERSONAGEM 3: HEAVY BRAWLER (Grappler)
-- ======================================================================

CharacterDatabase.HEAVY = CharacterClass.new({
	id = "fighter_heavy",
	name = "Heavy Brawler",
	description = "Personagem pesado com alto dano e grabs poderosos. Lento mas devastador.",

	stats = {
		health = 130,       -- Muito HP
		walkSpeed = 6,      -- Lento
		sprintSpeed = 14,   -- Sprint lento
		jumpHeight = 6,     -- Pula baixo
		weight = 1.3,       -- Pesado (knockback reduzido)
	},

	frameModifiers = {
		startupMultiplier = 1.2,    -- 20% mais lento em startup
		recoveryMultiplier = 1.15,  -- 15% mais lento em recovery
		damageMultiplier = 1.3,     -- 30% mais dano!
	},

	movementModifiers = {
		dashSpeed = 18,         -- Dash mais lento
		dashCooldown = 210,     -- Cooldown maior (3.5s)
		crouchSpeedMultiplier = 0.5,  -- Crouch bem lento
		airControl = 0.3,       -- Pouco controle no ar
	},

	animations = {
		-- TODO: Preencher com animações de heavy character
		idle = A("HEAVY_IDLE_ID"),
		walk = A("HEAVY_WALK_ID"),
		sprint = A("HEAVY_SPRINT_ID"),

		jab_front = A("HEAVY_JAB_FRONT"),
		jab_left = A("HEAVY_JAB_LEFT"),
		jab_right = A("HEAVY_JAB_RIGHT"),
		jab_back = A("HEAVY_JAB_BACK"),

		crouch = A("HEAVY_CROUCH"),
		crouch_jab = A("HEAVY_CROUCH_JAB"),
		crouch_sweep = A("HEAVY_SWEEP"),
		crouch_uppercut = A("HEAVY_UPPERCUT"),

		strong_charge_startup = A("HEAVY_CHARGE_START"),
		strong_charge_release = A("HEAVY_CHARGE_RELEASE"),
		strong_front = A("HEAVY_STRONG_FRONT"),
		strong_left = A("HEAVY_STRONG_LEFT"),
		strong_right = A("HEAVY_STRONG_RIGHT"),

		attack_low = A("HEAVY_LOW"),
		attack_high = A("HEAVY_HIGH"),

		block_startup = A("HEAVY_BLOCK_START"),
		block_idle = A("HEAVY_BLOCK_IDLE"),
		parry = A("HEAVY_PARRY"),

		grab_startup = A("HEAVY_GRAB_START"),
		grab_hold = A("HEAVY_GRAB_HOLD"),
		grab_throw = A("HEAVY_GRAB_THROW"),
		grabbed = A("HEAVY_GRABBED"),
		thrown = A("HEAVY_THROWN"),
		mount = A("HEAVY_MOUNT"),
		mounted = A("HEAVY_MOUNTED"),

		dash_front = A("HEAVY_DASH_FRONT"),
		dash_back = A("HEAVY_DASH_BACK"),
		dash_left = A("HEAVY_DASH_LEFT"),
		dash_right = A("HEAVY_DASH_RIGHT"),
		feint = A("HEAVY_FEINT"),
		slide = A("HEAVY_SLIDE"),

		wall_run = A("HEAVY_WALL_RUN"),
		wall_jump = A("HEAVY_WALL_JUMP"),
		ledge_grab = A("HEAVY_LEDGE_GRAB"),
		ledge_climb = A("HEAVY_LEDGE_CLIMB"),

		jump = A("HEAVY_JUMP"),
		fall = A("HEAVY_FALL"),
		air_normal = A("HEAVY_AIR_NORMAL"),
		air_divekick = A("HEAVY_AIR_DIVEKICK"),
		air_plunging = A("HEAVY_AIR_PLUNGING"),
		air_grab = A("HEAVY_AIR_GRAB"),

		hitstun_light = A("HEAVY_HITSTUN_LIGHT"),
		hitstun_heavy = A("HEAVY_HITSTUN_HEAVY"),
		blockstun = A("HEAVY_BLOCKSTUN"),
		knockdown = A("HEAVY_KNOCKDOWN"),
		getup = A("HEAVY_GETUP"),

		death_front = A("HEAVY_DEATH_FRONT"),
		death_back = A("HEAVY_DEATH_BACK"),
		death_side = A("HEAVY_DEATH_SIDE"),
		death_explosion = A("HEAVY_DEATH_EXPLODE"),

		taunt_1 = A("HEAVY_TAUNT_1"),
		taunt_2 = A("HEAVY_TAUNT_2"),
		taunt_3 = A("HEAVY_TAUNT_3"),
		victory_1 = A("HEAVY_VICTORY_1"),
		victory_2 = A("HEAVY_VICTORY_2"),
		victory_3 = A("HEAVY_VICTORY_3"),

		intro = A("HEAVY_INTRO"),
		outro_win = A("HEAVY_OUTRO_WIN"),
		outro_lose = A("HEAVY_OUTRO_LOSE"),
	},
})

-- ======================================================================
-- REGISTRO E LOOKUP
-- ======================================================================

-- Tabela de lookup por ID
CharacterDatabase.Registry = {
	[CharacterDatabase.BALANCED.id] = CharacterDatabase.BALANCED,
	[CharacterDatabase.SPEED.id] = CharacterDatabase.SPEED,
	[CharacterDatabase.HEAVY.id] = CharacterDatabase.HEAVY,
}

-- Lookup por ID
function CharacterDatabase.GetById(id: string): CharacterClass?
	return CharacterDatabase.Registry[id]
end

-- Lista todos os IDs disponíveis
function CharacterDatabase.GetAllIds(): { string }
	local ids = {}
	for id, _ in pairs(CharacterDatabase.Registry) do
		table.insert(ids, id)
	end
	return ids
end

-- Lista todos os personagens
function CharacterDatabase.GetAll(): { CharacterClass }
	local all = {}
	for _, class in pairs(CharacterDatabase.Registry) do
		table.insert(all, class)
	end
	return all
end

-- Valida todos os personagens
function CharacterDatabase.ValidateAll()
	local allValid = true
	for id, class in pairs(CharacterDatabase.Registry) do
		local valid, err = class:Validate()
		if not valid then
			warn(string.format("[CharacterDatabase] %s INVÁLIDO: %s", id, err or ""))
			allValid = false
		else
			print(string.format("[CharacterDatabase] %s ✓ válido", id))
		end
	end
	return allValid
end

-- ======================================================================
-- INICIALIZAÇÃO
-- ======================================================================

-- Valida ao carregar
task.spawn(function()
	task.wait(1)  -- Espera 1 segundo para evitar spam no console
	if not CharacterDatabase.ValidateAll() then
		warn("[CharacterDatabase] Alguns personagens têm problemas! Verifique os logs acima.")
	else
		print("[CharacterDatabase] Todos os personagens validados com sucesso!")
	end
end)

return CharacterDatabase

