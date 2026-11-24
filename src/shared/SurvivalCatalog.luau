--!strict
-- Catálogo completo do Modo "Sobrevivência no Câmpus" — IFSul Sapucaia do Sul
-- Centraliza artes geradas no Nano Banana (rbxassetid://), armas prontas evolutivas do Roblox,
-- as Cartas de Habilidade (3 opções -> escolhe 1 por onda), a Nova Loja de Upgrades na tela,
-- arquétipos de horda R15, as 4 brechas externas reais e Missões Bônus por setor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("IFSul"):WaitForChild("Config"))

local S = Config.STUDS_PER_METER

export type CardRarity = "Comum" | "Rara" | "Épica" | "Lendária"

export type SkillCardDef = {
	id: string,
	name: string,
	courseTag: string,
	rarity: CardRarity,
	artAssetId: string,
	description: string,
	statKey: string,
	statDelta: number,
	maxStacks: number,
}

export type WeaponDef = {
	id: string,
	name: string,
	slot: "Primary" | "Secondary" | "Melee",
	assetFolder: string,
	tierTools: { string }, -- Nv 1-2 = [1], Nv 3-4 = [2], Nv 5 = [3]
	price: number,
	description: string,
	baseDamage: number,
	fireRate: number, -- tiros por segundo (ou golpes/s)
	magSize: number, -- 0 = corpo a corpo infinito
	reserveAmmo: number,
	reloadTime: number,
	pellets: number,
	spreadDeg: number,
	rangeStuds: number,
	isExplosive: boolean?,
	splashRadius: number?,
	autoFire: boolean,
}

export type ShopUpgradeDef = {
	id: string,
	name: string,
	category: "Melhorias" | "Tático",
	basePrice: number,
	priceScale: number,
	maxLevel: number,
	description: string,
	iconArt: string,
}

export type ArchetypeDef = {
	id: string,
	name: string,
	minWave: number,
	weight: number,
	baseHealth: number,
	walkSpeed: number,
	attackDamage: number,
	attackRange: number,
	attackCooldown: number,
	scale: number,
	skinColor: Color3,
	torsoColor: Color3,
	legsColor: Color3,
	creditReward: number,
	isBoss: boolean?,
	isAcidic: boolean?,
}

export type BreachDef = {
	id: string,
	name: string,
	minWave: number,
	spawnPoints: { Vector3 },
	entryPoint: Vector3,
}

export type SectorMissionDef = {
	id: string,
	title: string,
	sectorLabel: string,
	instruction: string,
	kind: "Blackout" | "HoldZone" | "SupplyRescue" | "ValveContainment" | "AirDrop",
	position: Vector3,
	durationSec: number,
	holdTimeSec: number,
	rewardCredits: number,
	artAssetId: string,
}

local SurvivalCatalog = {}

-- Artes de alta qualidade e coerência geradas via Nano Banana e enviadas ao Roblox
SurvivalCatalog.UIArt = {
	PortalBanner = "rbxassetid://75904893803813",
	ShopBanner = "rbxassetid://127938571719643",
	CardMecanica = "rbxassetid://104237513353317",
	CardQuimica = "rbxassetid://70688079664814",
	CardInformatica = "rbxassetid://121659870077648",
	CardSaudeCantina = "rbxassetid://89600293788898",
	CardEsportesBib = "rbxassetid://75609569362002",
}

SurvivalCatalog.Sounds = {
	SchoolBellWaveStart = "rbxassetid://77996837173949",
	WaveCleared = "rbxasset://sounds/electronicpingshort.wav",
	CardPick = "rbxasset://sounds/action_get_up.mp3",
	HitMarker = "rbxasset://sounds/ein.wav",
}

SurvivalCatalog.RarityColors = {
	Comum = Color3.fromRGB(47, 158, 65),
	Rara = Color3.fromRGB(56, 152, 236),
	["Épica"] = Color3.fromRGB(168, 85, 247),
	["Lendária"] = Color3.fromRGB(250, 204, 21),
}

SurvivalCatalog.RarityWeights = {
	Comum = 54,
	Rara = 30,
	["Épica"] = 12,
	["Lendária"] = 4,
}

SurvivalCatalog.MaxPlayersPerSquad = 6
SurvivalCatalog.TotalTargetWaves = 15
SurvivalCatalog.CardDraftSeconds = 18
SurvivalCatalog.ShopPhaseSeconds = 22
SurvivalCatalog.DownedBleedoutSeconds = 30
SurvivalCatalog.ReviveHoldSeconds = 2.8

-- Spawn do esquadrão no coração do câmpus (Praça Central da Caixa d'Água / Auditório 504)
SurvivalCatalog.MatchSpawn = Vector3.new(-24.0 * S, 3.8, 6.0 * S)
-- Portal no modo Lobby (na praça da entrada principal, visível imediatamente ao nascer)
SurvivalCatalog.LobbyPortalPosition = Vector3.new(-45.5 * S, 0.25, 5.5 * S)

-- Polígono do perímetro murado do câmpus (em metros -> studs) para barreira que impede sair da área do IF
local RAW_PERIMETER_M = {
	{ -92.7, -143.8 },
	{ 44.8, -165.0 },
	{ 80.0, 75.3 },
	{ -30.7, 161.5 },
	{ -43.6, 163.4 },
	{ -64.6, 28.1 },
	{ -59.2, 27.3 },
	{ -64.1, -1.6 },
	{ -68.7, -0.8 },
}

SurvivalCatalog.PerimeterPoints = {} :: { Vector3 }
for _, pt in ipairs(RAW_PERIMETER_M) do
	table.insert(SurvivalCatalog.PerimeterPoints, Vector3.new(pt[1] * S, 0, pt[2] * S))
end

-- Portões visuais trancados com grades prontas no Modo Sobrevivência
SurvivalCatalog.GateVisualBarricades = {
	{ pos = Vector3.new(-61.6 * S, 0.2, 13.5 * S), lookAt = Vector3.new(-80.0 * S, 0.2, 16.0 * S) },
	{ pos = Vector3.new(-61.2 * S, 0.2, 20.5 * S), lookAt = Vector3.new(-80.0 * S, 0.2, 22.0 * S) },
	{ pos = Vector3.new(-70.0 * S, 0.2, -48.2 * S), lookAt = Vector3.new(-88.0 * S, 0.2, -50.0 * S) },
}

-- 4 Brechas externas reais (os invasores vêm das ruas de fora e entram no câmpus)
SurvivalCatalog.Breaches = {
	{
		id = "oeste_copacabana",
		name = "Av. Copacabana (Portaria Principal)",
		minWave = 1,
		spawnPoints = {
			Vector3.new(-76.0 * S, 3.5, 17.5 * S),
			Vector3.new(-79.0 * S, 3.5, 19.0 * S),
			Vector3.new(-74.0 * S, 3.5, 5.2 * S),
		},
		entryPoint = Vector3.new(-52.0 * S, 3.5, 17.5 * S),
	},
	{
		id = "norte_colombo",
		name = "Portão Norte & Rua Cristóvão Colombo",
		minWave = 3,
		spawnPoints = {
			Vector3.new(-82.0 * S, 3.5, -48.0 * S),
			Vector3.new(8.0 * S, 3.5, -152.0 * S),
			Vector3.new(16.0 * S, 3.5, -150.0 * S),
		},
		entryPoint = Vector3.new(-35.0 * S, 3.5, -46.0 * S),
	},
	{
		id = "sul_joao_rodrigues",
		name = "Rua João Rodrigues (Biblioteca & Lago)",
		minWave = 6,
		spawnPoints = {
			Vector3.new(-22.0 * S, 3.5, 152.0 * S),
			Vector3.new(-14.0 * S, 3.5, 148.0 * S),
		},
		entryPoint = Vector3.new(-14.0 * S, 3.5, 96.0 * S),
	},
	{
		id = "leste_palestina",
		name = "Rua Palestina (Setores 300 & 400)",
		minWave = 9,
		spawnPoints = {
			Vector3.new(68.0 * S, 3.5, -20.0 * S),
			Vector3.new(76.0 * S, 3.5, 52.0 * S),
		},
		entryPoint = Vector3.new(44.0 * S, 3.5, 18.0 * S),
	},
} :: { BreachDef }

-- Pontos de Caixas de Munição e Suprimentos pelos pátios do IFSul
SurvivalCatalog.SupplySpots = {
	Vector3.new(-20.0 * S, 0.3, 4.0 * S),   -- Praça da Caixa d'Água
	Vector3.new(-40.0 * S, 0.3, 50.0 * S),  -- Estacionamento Principal
	Vector3.new(-30.0 * S, 0.3, -74.0 * S), -- Estacionamento Norte
	Vector3.new(26.0 * S, 0.3, -78.0 * S),  -- Pátio do Bloco 800
	Vector3.new(12.0 * S, 0.3, 28.0 * S),   -- Pátio entre Auditório e Cantina
	Vector3.new(-10.0 * S, 0.3, 88.0 * S),  -- Alameda do Lago dos Patos
}

-- Missões Bônus dinâmicas usando os setores reais do IFSul
SurvivalCatalog.SectorMissions = {
	{
		id = "apagao_manutencao",
		title = "APAGÃO NO CÂMPUS!",
		sectorLabel = "Manutenção 404 (Setor 400)",
		instruction = "Vá até a Oficina de Manutenção (404) e religue o quadro elétrico [E]!",
		kind = "Blackout",
		position = Vector3.new(230.0, 4.5, 206.0), -- Coordenada em studs da Sala 404
		durationSec = 65,
		holdTimeSec = 3.0,
		rewardCredits = 350,
		artAssetId = SurvivalCatalog.UIArt.CardMecanica,
	},
	{
		id = "backup_informatica",
		title = "BACKUP DE EMERGÊNCIA!",
		sectorLabel = "Lab de Inovação 234 (Setor 230)",
		instruction = "Permaneça na zona de sinal junto ao Lab de Inovação (234) para concluir o upload!",
		kind = "HoldZone",
		position = Vector3.new(136.0, 4.5, 90.0), -- Corredor/Entrada do Lab 234 em studs
		durationSec = 60,
		holdTimeSec = 16.0,
		rewardCredits = 400,
		artAssetId = SurvivalCatalog.UIArt.CardInformatica,
	},
	{
		id = "resgate_saude",
		title = "SUPRIMENTO MÉDICO!",
		sectorLabel = "Setor de Saúde 112 (Setor 100)",
		instruction = "Recupere a maleta médica no acesso do Setor de Saúde (112) para curar toda a equipe!",
		kind = "SupplyRescue",
		position = Vector3.new(-210.0, 4.5, -116.0), -- Acesso Saúde 112 em studs
		durationSec = 55,
		holdTimeSec = 2.0,
		rewardCredits = 300,
		artAssetId = SurvivalCatalog.UIArt.CardSaudeCantina,
	},
	{
		id = "contencao_quimica",
		title = "CONTENÇÃO QUÍMICA!",
		sectorLabel = "Lab de Química 304 (Setor 300)",
		instruction = "Feche a válvula de contenção no acesso do Lab de Química (304) para ganhar munição reativa!",
		kind = "ValveContainment",
		position = Vector3.new(34.0, 4.5, -182.0), -- Acesso Lab Química 304 em studs
		durationSec = 60,
		holdTimeSec = 2.8,
		rewardCredits = 380,
		artAssetId = SurvivalCatalog.UIArt.CardQuimica,
	},
	{
		id = "drop_quadra",
		title = "DROP AÉREO TÁTICO!",
		sectorLabel = "Quadra Poliesportiva Coberta",
		instruction = "Abra o carregamento especial na Quadra Poliesportiva Coberta antes que expire!",
		kind = "AirDrop",
		position = Vector3.new(-195.0, 1.2, -310.0), -- Quadra coberta em studs
		durationSec = 60,
		holdTimeSec = 3.0,
		rewardCredits = 450,
		artAssetId = SurvivalCatalog.UIArt.CardEsportesBib,
	},
} :: { SectorMissionDef }

-- Arsenal com modelos oficiais do Roblox (evoluem visualmente em 3 estágios com o nível de Upgrade!)
SurvivalCatalog.Weapons = {
	{
		id = "pistol",
		name = "Pistola Tática",
		slot = "Secondary",
		assetFolder = "pistol",
		tierTools = { "Pistol", "Pistol2", "Pistol3" },
		price = 0,
		description = "Arma inicial precisa e confiável com recarga rápida.",
		baseDamage = 24,
		fireRate = 4.2,
		magSize = 14,
		reserveAmmo = 112,
		reloadTime = 1.35,
		pellets = 1,
		spreadDeg = 1.2,
		rangeStuds = 240,
		autoFire = false,
	},
	{
		id = "machete",
		name = "Facão de Campo",
		slot = "Melee",
		assetFolder = "machete",
		tierTools = { "Machete", "Machete", "Machete" },
		price = 0,
		description = "Golpe corpo a corpo rápido que nunca fica sem munição.",
		baseDamage = 42,
		fireRate = 2.2,
		magSize = 0,
		reserveAmmo = 0,
		reloadTime = 0,
		pellets = 1,
		spreadDeg = 0,
		rangeStuds = 9.5,
		autoFire = true,
	},
	{
		id = "smg",
		name = "Submetralhadora",
		slot = "Primary",
		assetFolder = "smg",
		tierTools = { "SMG", "SMG2", "SMG3" },
		price = 280,
		description = "Alta cadência automática ideal para corredores estreitos do IF.",
		baseDamage = 18,
		fireRate = 9.5,
		magSize = 32,
		reserveAmmo = 224,
		reloadTime = 1.65,
		pellets = 1,
		spreadDeg = 2.8,
		rangeStuds = 200,
		autoFire = true,
	},
	{
		id = "shotgun",
		name = "Escopeta Tática",
		slot = "Primary",
		assetFolder = "shotgun",
		tierTools = { "Shotgun", "Shotgun2", "Shotgun3" },
		price = 420,
		description = "Dispara 7 balins devastadores a curta distância.",
		baseDamage = 16,
		fireRate = 1.35,
		magSize = 8,
		reserveAmmo = 64,
		reloadTime = 2.0,
		pellets = 7,
		spreadDeg = 6.5,
		rangeStuds = 120,
		autoFire = false,
	},
	{
		id = "auto_rifle",
		name = "Rifle de Assalto",
		slot = "Primary",
		assetFolder = "auto_rifle",
		tierTools = { "AR", "AR2", "AR3" },
		price = 680,
		description = "Rifle automático equilibrado de alto alcance e poder de parada.",
		baseDamage = 31,
		fireRate = 7.2,
		magSize = 30,
		reserveAmmo = 210,
		reloadTime = 1.85,
		pellets = 1,
		spreadDeg = 1.8,
		rangeStuds = 320,
		autoFire = true,
	},
	{
		id = "sniper_rifle",
		name = "Rifle de Precisão",
		slot = "Primary",
		assetFolder = "sniper_rifle",
		tierTools = { "Sniper", "Sniper2", "Sniper3" },
		price = 950,
		description = "Disparo perfurante de altíssimo dano contra Tanques e Chefões.",
		baseDamage = 135,
		fireRate = 0.95,
		magSize = 6,
		reserveAmmo = 48,
		reloadTime = 2.2,
		pellets = 1,
		spreadDeg = 0.25,
		rangeStuds = 500,
		autoFire = false,
	},
	{
		id = "grenade_launcher",
		name = "Lança-Granadas",
		slot = "Primary",
		assetFolder = "grenade_launcher",
		tierTools = { "Grenade Launcher", "Grenade Launcher2", "Grenade Launcher3" },
		price = 1350,
		description = "Explosão em área que limpa hordas inteiras sem ferir aliados.",
		baseDamage = 115,
		fireRate = 1.1,
		magSize = 6,
		reserveAmmo = 36,
		reloadTime = 2.4,
		pellets = 1,
		spreadDeg = 1.0,
		rangeStuds = 260,
		isExplosive = true,
		splashRadius = 18,
		autoFire = false,
	},
} :: { WeaponDef }

-- Melhorias e Itens Táticos da Nova Loja na Tela
SurvivalCatalog.ShopUpgrades = {
	{
		id = "weapon_upgrade",
		name = "Usinagem de Arma (Evoluir Nível)",
		category = "Melhorias",
		basePrice = 220,
		priceScale = 1.55,
		maxLevel = 5,
		description = "+22% de Dano, +15% Munição e evolui o modelo visual das suas armas!",
		iconArt = SurvivalCatalog.UIArt.CardMecanica,
	},
	{
		id = "ammo_refill",
		name = "Recarga Completa de Munição",
		category = "Melhorias",
		basePrice = 90,
		priceScale = 1.0,
		maxLevel = 999,
		description = "Reabastece 100% dos pentes e munição reserva de todas as suas armas.",
		iconArt = SurvivalCatalog.UIArt.CardMecanica,
	},
	{
		id = "armor_vest",
		name = "Colete Balístico Institucional",
		category = "Melhorias",
		basePrice = 160,
		priceScale = 1.15,
		maxLevel = 999,
		description = "Concede +75 de Escudo/Colete que absorve ataques antes da sua vida.",
		iconArt = SurvivalCatalog.UIArt.CardSaudeCantina,
	},
	{
		id = "pocket_medkit",
		name = "Kit Médico Portátil [Tecla H]",
		category = "Tático",
		basePrice = 140,
		priceScale = 1.1,
		maxLevel = 3,
		description = "+1 Kit Médico na cintura para curar +65 HP instantaneamente em combate.",
		iconArt = SurvivalCatalog.UIArt.CardSaudeCantina,
	},
	{
		id = "deploy_turret",
		name = "Torreta Sentinela Automática [Tecla T]",
		category = "Tático",
		basePrice = 450,
		priceScale = 1.35,
		maxLevel = 3,
		description = "+1 Torreta Sentinela colocável nos pátios/corredores para alvejar a horda.",
		iconArt = SurvivalCatalog.UIArt.CardInformatica,
	},
} :: { ShopUpgradeDef }

-- 15 Cartas de Habilidade Temáticas do IFSul (3 sorteadas no fim da onda -> escolhe 1!)
SurvivalCatalog.SkillCards = {
	-- MECÂNICA / OFENSIVAS
	{
		id = "cnc_calibre",
		name = "Usinagem CNC de Precisão",
		courseTag = "Eng. Mecânica • Setor 400",
		rarity = "Comum",
		artAssetId = SurvivalCatalog.UIArt.CardMecanica,
		description = "Aumenta o dano de todas as suas armas em +18%.",
		statKey = "DamageMult",
		statDelta = 0.18,
		maxStacks = 6,
	},
	{
		id = "gatilho_rapido",
		name = "Mecanismo de Disparo Rápido",
		courseTag = "Mecânica • Oficina 400",
		rarity = "Rara",
		artAssetId = SurvivalCatalog.UIArt.CardMecanica,
		description = "Aumenta a cadência de tiro e golpes em +20%.",
		statKey = "FireRateMult",
		statDelta = 0.20,
		maxStacks = 5,
	},
	{
		id = "municao_perfurante",
		name = "Projétil de Liga Temperada",
		courseTag = "Metalurgia • Setor 400",
		rarity = "Épica",
		artAssetId = SurvivalCatalog.UIArt.CardMecanica,
		description = "Seus disparos atravessam +1 invasor adicional na mesma linha e causam +20% dano.",
		statKey = "PierceCount",
		statDelta = 1,
		maxStacks = 3,
	},
	-- QUÍMICA & PLÁSTICOS
	{
		id = "reagente_acido",
		name = "Reagente Corrosivo 304",
		courseTag = "Química • Lab 304",
		rarity = "Rara",
		artAssetId = SurvivalCatalog.UIArt.CardQuimica,
		description = "Seus tiros aplicam corrosão química (+25% dano contínuo ao longo de 3s).",
		statKey = "AcidBurn",
		statDelta = 0.25,
		maxStacks = 4,
	},
	{
		id = "polimero_crio",
		name = "Polímero Viscoso Retentor",
		courseTag = "Plásticos • Lab 301",
		rarity = "Comum",
		artAssetId = SurvivalCatalog.UIArt.CardQuimica,
		description = "Disparos desaceleram invasores atingidos em 22% por 2,5 segundos.",
		statKey = "SlowOnHit",
		statDelta = 0.22,
		maxStacks = 3,
	},
	{
		id = "combustao_instavel",
		name = "Síntese Exotérmica",
		courseTag = "Química • Setor 300",
		rarity = "Lendária",
		artAssetId = SurvivalCatalog.UIArt.CardQuimica,
		description = "Invasores eliminados explodem em energia química, causando 55 de dano em área!",
		statKey = "DeathExplosion",
		statDelta = 55,
		maxStacks = 3,
	},
	-- INFORMÁTICA & INOVAÇÃO
	{
		id = "overclock_torreta",
		name = "Overclock de Automação",
		courseTag = "Inovação • Lab 234",
		rarity = "Rara",
		artAssetId = SurvivalCatalog.UIArt.CardInformatica,
		description = "Suas Torretas causam +35% de dano e você ganha +1 Torreta pronta para usar!",
		statKey = "TurretBoost",
		statDelta = 0.35,
		maxStacks = 4,
	},
	{
		id = "mira_assistida",
		name = "Algoritmo de Visão Computacional",
		courseTag = "Informática • Labs 1–6",
		rarity = "Épica",
		artAssetId = SurvivalCatalog.UIArt.CardInformatica,
		description = "+25% de chance de Acerto Crítico (dano dobrado) em qualquer disparo.",
		statKey = "CritChance",
		statDelta = 0.25,
		maxStacks = 4,
	},
	{
		id = "bobina_choque",
		name = "Descarga Eletrostática",
		courseTag = "Física • Lab 804",
		rarity = "Lendária",
		artAssetId = SurvivalCatalog.UIArt.CardInformatica,
		description = "Disparos saltam um raio elétrico para até 2 invasores próximos (+40 dano)!",
		statKey = "ChainLightning",
		statDelta = 40,
		maxStacks = 3,
	},
	-- SAÚDE & CANTINA
	{
		id = "plantao_saude",
		name = "Primeiros Socorros 112",
		courseTag = "Saúde • Setor 100",
		rarity = "Comum",
		artAssetId = SurvivalCatalog.UIArt.CardSaudeCantina,
		description = "+35 de Vida Máxima imediata e regenera +3 HP por segundo.",
		statKey = "MaxHealthBonus",
		statDelta = 35,
		maxStacks = 6,
	},
	{
		id = "combo_cantina",
		name = "Energético Duplo da Cantina",
		courseTag = "Cantina • Setor 230",
		rarity = "Comum",
		artAssetId = SurvivalCatalog.UIArt.CardSaudeCantina,
		description = "Recarrega armas 28% mais rápido e cura 25 HP ao final de cada onda.",
		statKey = "ReloadSpeedMult",
		statDelta = 0.28,
		maxStacks = 4,
	},
	{
		id = "vampirismo_vital",
		name = "Adrenalina de Sobrevivência",
		courseTag = "Saúde • CAE 103",
		rarity = "Épica",
		artAssetId = SurvivalCatalog.UIArt.CardSaudeCantina,
		description = "Cada invasor eliminado restaura instantaneamente +8 HP e +4 de Colete.",
		statKey = "LifeOnKill",
		statDelta = 8,
		maxStacks = 4,
	},
	-- ESPORTES & BIBLIOTECA
	{
		id = "atleta_ifsul",
		name = "Sprint Poliesportivo",
		courseTag = "Ed. Física • Ginásio",
		rarity = "Comum",
		artAssetId = SurvivalCatalog.UIArt.CardEsportesBib,
		description = "+12% de Velocidade de Movimento e Sprint pelo câmpus.",
		statKey = "MoveSpeedMult",
		statDelta = 0.12,
		maxStacks = 4,
	},
	{
		id = "bolsa_pesquisa",
		name = "Bolsa de Pesquisa & Extensão",
		courseTag = "Biblioteca • Setor Sul",
		rarity = "Rara",
		artAssetId = SurvivalCatalog.UIArt.CardEsportesBib,
		description = "Ganha +30% mais Créditos da Loja em todos os abates e missões.",
		statKey = "CreditMult",
		statDelta = 0.30,
		maxStacks = 4,
	},
	{
		id = "mestre_campus",
		name = "Lenda do Câmpus Sapucaia",
		courseTag = "IFSul • Honra Máxima",
		rarity = "Lendária",
		artAssetId = SurvivalCatalog.UIArt.CardEsportesBib,
		description = "+25% Dano, +15% Velocidade, +40 Vida Máxima e +150 Créditos na hora!",
		statKey = "AllRoundLegend",
		statDelta = 1,
		maxStacks = 2,
	},
} :: { SkillCardDef }

-- 5 Arquétipos de Invasores + Bosses (Ondas 5, 10, 15)
SurvivalCatalog.Archetypes = {
	{
		id = "walker",
		name = "Zumbi Invasor",
		minWave = 1,
		weight = 60,
		baseHealth = 65,
		walkSpeed = 12.5,
		attackDamage = 10,
		attackRange = 5.5,
		attackCooldown = 1.1,
		scale = 1.0,
		skinColor = Color3.fromRGB(110, 152, 96),
		torsoColor = Color3.fromRGB(64, 76, 92),
		legsColor = Color3.fromRGB(44, 48, 56),
		creditReward = 22,
	},
	{
		id = "runner",
		name = "Zumbi Corredor",
		minWave = 3,
		weight = 28,
		baseHealth = 52,
		walkSpeed = 20.5,
		attackDamage = 11,
		attackRange = 5.2,
		attackCooldown = 0.85,
		scale = 0.94,
		skinColor = Color3.fromRGB(168, 92, 88),
		torsoColor = Color3.fromRGB(135, 36, 36),
		legsColor = Color3.fromRGB(36, 36, 42),
		creditReward = 28,
	},
	{
		id = "brute",
		name = "Brutamontes Blindado",
		minWave = 5,
		weight = 16,
		baseHealth = 240,
		walkSpeed = 10.2,
		attackDamage = 26,
		attackRange = 6.8,
		attackCooldown = 1.35,
		scale = 1.38,
		skinColor = Color3.fromRGB(88, 118, 84),
		torsoColor = Color3.fromRGB(48, 56, 48),
		legsColor = Color3.fromRGB(32, 36, 32),
		creditReward = 55,
	},
	{
		id = "toxic",
		name = "Infectado Químico",
		minWave = 7,
		weight = 14,
		baseHealth = 110,
		walkSpeed = 14.5,
		attackDamage = 18,
		attackRange = 6.0,
		attackCooldown = 1.0,
		scale = 1.06,
		skinColor = Color3.fromRGB(116, 224, 92),
		torsoColor = Color3.fromRGB(118, 54, 168),
		legsColor = Color3.fromRGB(45, 32, 58),
		creditReward = 42,
		isAcidic = true,
	},
	{
		id = "boss",
		name = "Chefão da Horda",
		minWave = 5,
		weight = 0, -- Spawnado especificamente nas ondas múltiplas de 5
		baseHealth = 1150,
		walkSpeed = 12.8,
		attackDamage = 38,
		attackRange = 8.5,
		attackCooldown = 1.25,
		scale = 1.78,
		skinColor = Color3.fromRGB(72, 102, 68),
		torsoColor = Color3.fromRGB(165, 24, 28),
		legsColor = Color3.fromRGB(24, 24, 28),
		creditReward = 260,
		isBoss = true,
	},
} :: { ArchetypeDef }

local weaponsById: { [string]: WeaponDef } = {}
for _, w in ipairs(SurvivalCatalog.Weapons) do
	weaponsById[w.id] = w
end

local cardsById: { [string]: SkillCardDef } = {}
for _, c in ipairs(SurvivalCatalog.SkillCards) do
	cardsById[c.id] = c
end

local upgradesById: { [string]: ShopUpgradeDef } = {}
for _, u in ipairs(SurvivalCatalog.ShopUpgrades) do
	upgradesById[u.id] = u
end

function SurvivalCatalog.GetWeapon(id: string): WeaponDef?
	return weaponsById[id]
end

function SurvivalCatalog.GetCard(id: string): SkillCardDef?
	return cardsById[id]
end

function SurvivalCatalog.GetUpgrade(id: string): ShopUpgradeDef?
	return upgradesById[id]
end

return SurvivalCatalog
