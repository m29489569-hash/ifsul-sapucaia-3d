--!strict
-- Configurações globais e constantes métricas do IFSul — Câmpus Sapucaia do Sul (Roblox)

local Config = {}

-- Escala métrica oficial do Roblox: 1 stud = 0,28 metros
Config.METERS_PER_STUD = 0.28
Config.STUDS_PER_METER = 1 / 0.28 -- ~3.57142857

Config.CampusName = "IFSul — Câmpus Sapucaia do Sul"
Config.Address = "Av. Copacabana, 100 — Piratini, Sapucaia do Sul/RS"
Config.GeographicLatitude = -29.8

-- Spawn na entrada principal (convertido de data/campus.json)
Config.SpawnPosition = Vector3.new(-55.0 * Config.STUDS_PER_METER, 1.5, 12.0 * Config.STUDS_PER_METER)
Config.SpawnLookAt = Vector3.new(-20.0 * Config.STUDS_PER_METER, 1.5, 8.0 * Config.STUDS_PER_METER)

-- Paleta institucional oficial da Rede Federal / IFSul
Config.Colors = {
	IFSulGreen = Color3.fromRGB(47, 158, 65),
	IFSulRed = Color3.fromRGB(205, 25, 30),
	PanelBg = Color3.fromRGB(16, 22, 28),
	PanelBorder = Color3.fromRGB(47, 158, 65),
	TextPrimary = Color3.fromRGB(244, 246, 248),
	TextMuted = Color3.fromRGB(168, 178, 188),
}

-- Movimentação e segurança
Config.WalkSpeed = 16
Config.SprintSpeed = 28
Config.TeleportCooldown = 1.0

-- Iluminação Dia / Noite
Config.Lighting = {
	Day = {
		ClockTime = 14,
		Brightness = 2.2,
		OutdoorAmbient = Color3.fromRGB(115, 125, 135),
		AtmosphereDensity = 0.24,
		AtmosphereColor = Color3.fromRGB(199, 218, 236),
		AtmosphereDecay = Color3.fromRGB(120, 145, 175),
		AtmosphereHaze = 1.2,
	},
	Night = {
		ClockTime = 21.5,
		Brightness = 0.65,
		OutdoorAmbient = Color3.fromRGB(35, 45, 65),
		AtmosphereDensity = 0.34,
		AtmosphereColor = Color3.fromRGB(28, 38, 58),
		AtmosphereDecay = Color3.fromRGB(18, 24, 40),
		AtmosphereHaze = 2.0,
	},
}

return Config
