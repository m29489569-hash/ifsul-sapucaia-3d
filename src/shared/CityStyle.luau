--!strict
-- Constantes e estilos para geracao e streaming de tiles de cidade (Sapucaia do Sul e regiao).

local CityStyle = {}

CityStyle.METERS_PER_STUD = 0.28
CityStyle.STUDS_PER_METER = 1 / 0.28

CityStyle.LoadRadiusMeters = 1500
CityStyle.UnloadRadiusMeters = 1800
CityStyle.LoadRadiusStuds = CityStyle.LoadRadiusMeters * CityStyle.STUDS_PER_METER
CityStyle.UnloadRadiusStuds = CityStyle.UnloadRadiusMeters * CityStyle.STUDS_PER_METER

CityStyle.CheckIntervalSeconds = 2.0
CityStyle.TileBatchYieldSize = 450

CityStyle.Materials = {
	[1] = Enum.Material.SmoothPlastic,
	[2] = Enum.Material.Concrete,
	[3] = Enum.Material.Grass,
	[4] = Enum.Material.Asphalt,
	[5] = Enum.Material.Slate,
	[6] = Enum.Material.Metal,
	[7] = Enum.Material.Glass,
	[8] = Enum.Material.Wood,
	[9] = Enum.Material.Neon,
}

CityStyle.Categories = {
	[1] = "Ground",
	[2] = "Roads",
	[3] = "Sidewalks",
	[4] = "Buildings",
}

return CityStyle
