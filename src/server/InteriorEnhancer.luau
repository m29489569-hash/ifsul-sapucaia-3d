--!strict
-- Parte 1 do detalhamento interno do IFSul — Câmpus Sapucaia do Sul:
-- 1) Pisos cerâmicos cinza-grafite quadriculados e rodapés em todo o câmpus
-- 2) Barrado inferior verde-IFSul nos corredores + faixa superior verde-lima e clerestório no Saguão
-- 3) Eletrocalhas galvanizadas, luminárias lineares duplas (AlwaysOn) e tubulação vermelha de incêndio
-- 4) Saguão / Hall Principal completo (Recepção branco/vidro, mesas com cadeiras acopladas,
--    quadro verde + telefones, hidrante + TV Perdidos e Achados, mural colorido, vitrine de troféus e bancos)
-- 5) Placas direcionais oficiais de parede, hidrantes, quadros elétricos e lixeiras seletivas.

local CampusData = require(game:GetService("ReplicatedStorage"):WaitForChild("IFSul"):WaitForChild("CampusData"))
local Helpers = require(script.Parent.InteriorHelpers)

local InteriorEnhancer = {}

local STUDS_PER_METER = 1 / 0.28
local C = Helpers.Colors

local function m2s(xm: number, yStuds: number, zm: number): Vector3
	return Vector3.new(xm * STUDS_PER_METER, yStuds, zm * STUDS_PER_METER)
end

local function isInSaguaoZone(posStuds: Vector3): boolean
	local xm = posStuds.X / STUDS_PER_METER
	local zm = posStuds.Z / STUDS_PER_METER
	return xm >= -24.5 and xm <= -1.0 and zm >= -12.6 and zm <= 7.5
end

local function isOldRecepcaoProp(posStuds: Vector3, sizeStuds: Vector3): boolean
	local xm = posStuds.X / STUDS_PER_METER
	local zm = posStuds.Z / STUDS_PER_METER
	if posStuds.Y > 0.25 and posStuds.Y < 5.8 and sizeStuds.Y < 5.5 then
		-- Antigo balcão verde/madeira e banco da recepção (-15..-11.5m, -5.5..-1.5m)
		if xm >= -15.2 and xm <= -11.4 and zm >= -5.6 and zm <= -1.6 then
			return true
		end
	end
	return false
end

local function hideOriginalPart(inst: Instance)
	if inst:IsA("BasePart") then
		inst:SetAttribute("RelocatedHidden", true)
		inst.Transparency = 1
		inst.CanCollide = false
		inst.CanQuery = false
	end
	for _, g in ipairs(inst:GetDescendants()) do
		if g:IsA("SurfaceGui") then
			g:SetAttribute("RelocatedHidden", true)
			g.Enabled = false
		end
	end
end

local function sanitizeBaseline(campusRoot: Instance, interiors: Instance, lights: Instance)
	for _, host in ipairs({ campusRoot, interiors, lights }) do
		local prev = host:FindFirstChild("InteriorEnhanced")
		if prev then
			prev:Destroy()
		end
	end

	-- Restaura peças originalmente ocultadas por relocação de portas para manter idempotência
	for _, container in ipairs({ interiors, campusRoot:FindFirstChild("Signage") }) do
		if container then
			for _, d in ipairs(container:GetDescendants()) do
				if d:GetAttribute("RelocatedHidden") then
					d:SetAttribute("RelocatedHidden", nil)
					if d:IsA("BasePart") then
						d.Transparency = 0
						d.CanCollide = true
						d.CanQuery = true
					elseif d:IsA("SurfaceGui") then
						d.Enabled = true
					end
				end
			end
		end
	end

	local toDestroy: { Instance } = {}
	for _, d in ipairs(interiors:GetDescendants()) do
		if d:IsA("BasePart") and isOldRecepcaoProp(d.Position, d.Size) then
			table.insert(toDestroy, d)
		end
	end
	for _, inst in ipairs(toDestroy) do
		inst:Destroy()
	end
end

local function makeBuildingsRayParams(buildings: Instance?): RaycastParams?
	if not buildings then
		return nil
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { buildings }
	return rp
end

local function raycastCeilingY(rp: RaycastParams?, pos: Vector3, startY: number): number?
	if not rp then
		return nil
	end
	local res = workspace:Raycast(Vector3.new(pos.X, startY, pos.Z), Vector3.new(0, 20, 0), rp)
	if res then
		return res.Position.Y
	end
	return nil
end

local function placeDoorSignPlate(
	geomFolder: Folder,
	name: string,
	pos: Vector3,
	outwardNormal: Vector3,
	text: string,
	accentColor: Color3,
	counter: { count: number }
)
	local n = Vector3.new(outwardNormal.X, 0, outwardNormal.Z).Unit
	local cf = CFrame.lookAt(pos, pos + n)
	local w = 6.2
	local h = 0.89
	local backing = Helpers.MakePart(
		geomFolder,
		name .. "_Plate",
		Vector3.new(w, h, 0.10),
		cf,
		Color3.fromRGB(30, 37, 45),
		Enum.Material.SmoothPlastic,
		false,
		false,
		counter
	)
	Helpers.MakePart(
		geomFolder,
		name .. "_Accent",
		Vector3.new(0.30, h, 0.10),
		cf * CFrame.new(w * 0.5 + 0.15, 0, 0),
		accentColor,
		Enum.Material.SmoothPlastic,
		false,
		false,
		counter
	)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(620, 90)
	gui.LightInfluence = 0.2
	gui.Parent = backing

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(245, 248, 250)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = false
	lbl.TextSize = 36
	lbl.Parent = gui
end

local function buildWrappedWallSegment(
	geomFolder: Folder,
	baseCF: CFrame,
	sizeX: number,
	sizeZ: number,
	ceilY: number,
	namePrefix: string,
	counter: { count: number }
)
	local wallH = math.max(1.0, ceilY - 0.14)
	Helpers.MakePart(
		geomFolder,
		namePrefix .. "_Wall",
		Vector3.new(sizeX, wallH, sizeZ),
		baseCF * CFrame.new(0, 0.16 + wallH * 0.5, 0),
		C.WallWhite,
		Enum.Material.SmoothPlastic,
		true,
		false,
		counter
	)

	local xThin = sizeX < sizeZ
	local wrapX = if xThin then sizeX + 0.04 else sizeX
	local wrapZ = if xThin then sizeZ else sizeZ + 0.04
	local baseWrapX = if xThin then sizeX + 0.05 else sizeX
	local baseWrapZ = if xThin then sizeZ else sizeZ + 0.05

	Helpers.MakePart(
		geomFolder,
		namePrefix .. "_Baseboard",
		Vector3.new(baseWrapX, 0.43, baseWrapZ),
		baseCF * CFrame.new(0, 0.38, 0),
		C.BaseboardGrey,
		Enum.Material.SmoothPlastic,
		false,
		false,
		counter
	)

	if isInSaguaoZone(baseCF.Position) then
		local bandH = 2.15
		Helpers.MakePart(
			geomFolder,
			namePrefix .. "_LimeBand",
			Vector3.new(wrapX, bandH, wrapZ),
			baseCF * CFrame.new(0, math.min(ceilY, 12.86) - bandH * 0.5 - 0.05, 0),
			C.HallLimeBand,
			Enum.Material.SmoothPlastic,
			false,
			false,
			counter
		)
	else
		local dadoH = 3.85
		Helpers.MakePart(
			geomFolder,
			namePrefix .. "_Dado",
			Vector3.new(wrapX, dadoH, wrapZ),
			baseCF * CFrame.new(0, 0.56 + dadoH * 0.5, 0),
			C.CorridorGreenDado,
			Enum.Material.SmoothPlastic,
			false,
			false,
			counter
		)
	end
end

-- Realoca portas bloqueadas contra paredes traseiras (WC-F230 leste->oeste e Sala 112 centro->leste)
local function fixDoorRelocations(campusRoot: Instance, interiors: Instance, geomFolder: Folder, counter: { count: number })
	local buildingsRP = makeBuildingsRayParams(campusRoot:FindFirstChild("Buildings"))
	local signage = campusRoot:FindFirstChild("Signage")

	local function buildDoorFrame(baseCF: CFrame, doorLocalPos: Vector3, doorW: number, thkFrame: number, alongZ: boolean, prefix: string)
		local jambH = 7.86
		local jambSz = if alongZ then Vector3.new(thkFrame, jambH, 0.20) else Vector3.new(0.20, jambH, thkFrame)
		local headSz = if alongZ then Vector3.new(thkFrame, 0.22, doorW) else Vector3.new(doorW, 0.22, thkFrame)
		local off = doorW * 0.5 - 0.10
		local j1 = if alongZ then Vector3.new(0, 4.11, -off) else Vector3.new(-off, 4.11, 0)
		local j2 = if alongZ then Vector3.new(0, 4.11, off) else Vector3.new(off, 4.11, 0)
		Helpers.MakePart(geomFolder, prefix .. "_Jamb1", jambSz, baseCF * CFrame.new(doorLocalPos + j1), Color3.fromRGB(43, 50, 56), Enum.Material.SmoothPlastic, true, false, counter)
		Helpers.MakePart(geomFolder, prefix .. "_Jamb2", jambSz, baseCF * CFrame.new(doorLocalPos + j2), Color3.fromRGB(43, 50, 56), Enum.Material.SmoothPlastic, true, false, counter)
		Helpers.MakePart(geomFolder, prefix .. "_Head", headSz, baseCF * CFrame.new(doorLocalPos + Vector3.new(0, 7.93, 0)), Color3.fromRGB(43, 50, 56), Enum.Material.SmoothPlastic, true, false, counter)
	end

	-- 1) WC-F230 (banheiro_fem_cantina): fecha porta Leste (encostada na Cantina) e abre na Oeste
	local eastLintel: BasePart? = nil
	local westWall: BasePart? = nil
	for _, d in ipairs(interiors:GetDescendants()) do
		if d:IsA("BasePart") then
			local col = d.Color
			local r, g, b = math.round(col.R * 255), math.round(col.G * 255), math.round(col.B * 255)
			local dEast = Vector2.new(d.Position.X - 108.90, d.Position.Z - 84.95).Magnitude
			if dEast <= 4.2 and d.Position.Y > 0.5 and d.Position.Y < 13.5 then
				if (r < 60 and g < 65 and b < 70 and d.Size.Y < 8.5)
					or (math.min(d.Size.X, d.Size.Y, d.Size.Z) <= 0.15 and d.Position.Y > 7.5 and d.Position.Y < 9.8) then
					hideOriginalPart(d)
				elseif r >= 225 and g >= 225 and b >= 220 and d.Position.Y >= 8.5 and d.Size.Y < 8.0 and dEast <= 1.2 then
					eastLintel = d
					hideOriginalPart(d)
				end
			end

			local dWest = Vector2.new(d.Position.X - 95.95, d.Position.Z - 86.90).Magnitude
			if dWest <= 1.5 then
				if d.Size.Y >= 10.0 and d.Size.Z >= 8.0 then
					westWall = d
					hideOriginalPart(d)
				elseif d.Position.Y < 0.8 and d.Size.Y <= 0.65 then
					hideOriginalPart(d)
				end
			end
		end
	end

	if signage then
		for _, s in ipairs(signage:GetDescendants()) do
			if s:IsA("BasePart") then
				if Vector2.new(s.Position.X - 108.90, s.Position.Z - 84.95).Magnitude <= 14.0 and s.Position.Y > 7.5 then
					for _, lbl in ipairs(s:GetDescendants()) do
						if lbl:IsA("TextLabel") and (string.find(lbl.Text, "WC%-F230") or string.find(lbl.Text, "Banheiro Feminino")) then
							hideOriginalPart(s)
							break
						end
					end
				end
			end
		end
	end

	if eastLintel then
		local lCF = eastLintel.CFrame * CFrame.new(0, -eastLintel.Position.Y, 0)
		local ceilY = raycastCeilingY(buildingsRP, eastLintel.Position, 12.9) or 17.71
		buildWrappedWallSegment(geomFolder, lCF, eastLintel.Size.X, eastLintel.Size.Z, ceilY, "WC_F230_EastClose", counter)
	end

	if westWall then
		local wCF = westWall.CFrame * CFrame.new(0, -westWall.Position.Y, 0)
		local ceilY = raycastCeilingY(buildingsRP, westWall.Position, westWall.Position.Y + westWall.Size.Y * 0.5 + 0.05) or 17.71
		local thk = westWall.Size.X
		local totalLen = westWall.Size.Z
		local doorW = 4.46
		local sideLen = (totalLen - doorW) * 0.5
		if sideLen > 0.3 then
			for _, dir in ipairs({ -1, 1 }) do
				local segCF = wCF * CFrame.new(0, 0, dir * (doorW * 0.5 + sideLen * 0.5))
				buildWrappedWallSegment(geomFolder, segCF, thk, sideLen, ceilY, "WC_F230_WestSide", counter)
			end
			local lintelH = math.max(0.5, ceilY - 8.02)
			Helpers.MakePart(
				geomFolder,
				"WC_F230_WestLintel",
				Vector3.new(thk, lintelH, doorW),
				wCF * CFrame.new(0, 8.04 + lintelH * 0.5, 0),
				C.WallWhite,
				Enum.Material.SmoothPlastic,
				true,
				false,
				counter
			)
			buildDoorFrame(wCF, Vector3.zero, doorW, 0.60, true, "WC_F230_WestDoor")
			local roomCenter = Vector3.new(102.43, 0, 85.93)
			local toOut = (Vector3.new(westWall.Position.X, 0, westWall.Position.Z) - roomCenter).Unit
			local outwardWest = if toOut:Dot(wCF.RightVector) >= 0 then wCF.RightVector else -wCF.RightVector
			placeDoorSignPlate(
				geomFolder,
				"WC_F230_WestSign",
				Vector3.new(westWall.Position.X, 8.82, westWall.Position.Z) + outwardWest * (thk * 0.5 + 0.08),
				outwardWest,
				"WC-F230 • Banheiro Feminino",
				Color3.fromRGB(88, 178, 123),
				counter
			)
		end
	end

	-- 2) Sala 112 (Setor de Saúde): fecha porta central (bloqueada pela Sala 111) e abre no corredor Setor 100 (leste da parede sul)
	local s112Lintel: BasePart? = nil
	local s112RightWall: BasePart? = nil
	for _, d in ipairs(interiors:GetDescendants()) do
		if d:IsA("BasePart") then
			local col = d.Color
			local r, g, b = math.round(col.R * 255), math.round(col.G * 255), math.round(col.B * 255)
			local dCenter = Vector2.new(d.Position.X + 221.85, d.Position.Z + 120.70).Magnitude
			if dCenter <= 3.6 and d.Position.Y > 0.5 and d.Position.Y < 13.5 then
				if (r < 60 and g < 65 and b < 70 and d.Size.Y < 8.5)
					or (math.min(d.Size.X, d.Size.Y, d.Size.Z) <= 0.15 and d.Position.Y > 7.5 and d.Position.Y < 9.8) then
					hideOriginalPart(d)
				elseif r >= 225 and g >= 225 and b >= 220 and d.Position.Y >= 8.5 and d.Size.Y < 8.0 and dCenter <= 1.2 then
					s112Lintel = d
					hideOriginalPart(d)
				end
			end

			local dRight = Vector2.new(d.Position.X + 215.75, d.Position.Z + 121.75).Magnitude
			if dRight <= 1.5 then
				if d.Size.Y >= 10.0 and d.Size.X >= 6.0 then
					s112RightWall = d
					hideOriginalPart(d)
				elseif d.Position.Y < 0.8 and d.Size.Y <= 0.65 then
					hideOriginalPart(d)
				end
			end
		end
	end

	if signage then
		for _, s in ipairs(signage:GetDescendants()) do
			if s:IsA("BasePart") and Vector2.new(s.Position.X + 221.64, s.Position.Z + 120.31).Magnitude <= 4.0 and s.Position.Y > 7.5 then
				hideOriginalPart(s)
			end
		end
	end

	if s112Lintel then
		local lCF = s112Lintel.CFrame * CFrame.new(0, -s112Lintel.Position.Y, 0)
		local ceilY = raycastCeilingY(buildingsRP, s112Lintel.Position, 12.2) or 17.00
		buildWrappedWallSegment(geomFolder, lCF, s112Lintel.Size.X, s112Lintel.Size.Z, ceilY, "S112_CenterClose", counter)
	end

	if s112RightWall then
		local rCF = s112RightWall.CFrame * CFrame.new(0, -s112RightWall.Position.Y, 0)
		local ceilY = raycastCeilingY(buildingsRP, s112RightWall.Position, s112RightWall.Position.Y + s112RightWall.Size.Y * 0.5 + 0.05) or 17.00
		local totalLen = s112RightWall.Size.X -- 7.70
		local thk = s112RightWall.Size.Z -- 0.50
		local doorW = 4.29 -- 1.2m
		local eastSign = if rCF.RightVector.X >= 0 then 1 else -1
		local doorLocalX = eastSign * 0.80 -- alinha com offset +1.95m da sala 112 (abertura franca no corredor N-S)
		local leftEdge = -totalLen * 0.5
		local rightEdge = totalLen * 0.5
		local dLeft = doorLocalX - doorW * 0.5
		local dRight = doorLocalX + doorW * 0.5
		local leftSegLen = dLeft - leftEdge
		local rightSegLen = rightEdge - dRight

		if leftSegLen > 0.25 then
			buildWrappedWallSegment(geomFolder, rCF * CFrame.new(leftEdge + leftSegLen * 0.5, 0, 0), leftSegLen, thk, ceilY, "S112_RightSegL", counter)
		end
		if rightSegLen > 0.25 then
			buildWrappedWallSegment(geomFolder, rCF * CFrame.new(dRight + rightSegLen * 0.5, 0, 0), rightSegLen, thk, ceilY, "S112_RightSegR", counter)
		end

		local lintelH = math.max(0.5, ceilY - 8.02)
		Helpers.MakePart(
			geomFolder,
			"S112_NewLintel",
			Vector3.new(doorW, lintelH, thk),
			rCF * CFrame.new(doorLocalX, 8.04 + lintelH * 0.5, 0),
			C.WallWhite,
			Enum.Material.SmoothPlastic,
			true,
			false,
			counter
		)
		buildDoorFrame(rCF, Vector3.new(doorLocalX, 0, 0), doorW, 0.60, false, "S112_NewDoor")
		local s112Center = Vector3.new(-223.14, 0, -128.18)
		local toOut = (Vector3.new(s112RightWall.Position.X, 0, s112RightWall.Position.Z) - s112Center).Unit
		local outwardSouth = if toOut:Dot(rCF.LookVector) >= 0 then rCF.LookVector else -rCF.LookVector
		local signWorldPos = (rCF * CFrame.new(doorLocalX, 8.82, 0)).Position + outwardSouth * (thk * 0.5 + 0.08)
		placeDoorSignPlate(
			geomFolder,
			"S112_NewSign",
			signWorldPos,
			outwardSouth,
			"112 • Setor de Saúde",
			Color3.fromRGB(126, 168, 201),
			counter
		)
	end
end

-- Converte pisos arenosos/Slate em cerâmica cinza-grafite, fecha vãos até o teto e aplica barrado verde-IFSul
local function upgradeFloorsAndWalls(campusRoot: Instance, interiors: Instance, geomFolder: Folder, counter: { count: number })
	local buildingsRP = makeBuildingsRayParams(campusRoot:FindFirstChild("Buildings"))
	local wallCache: { BasePart } = {}
	local ceilingExtendCache: { BasePart } = {}

	for _, d in ipairs(interiors:GetDescendants()) do
		if d:IsA("BasePart") and not d:GetAttribute("RelocatedHidden") and d.Transparency < 0.99 then
			local col = d.Color
			local r = math.round(col.R * 255)
			local g = math.round(col.G * 255)
			local b = math.round(col.B * 255)

			local isFloorSlab = d.Position.Y <= 0.35 and math.min(d.Size.X, d.Size.Y, d.Size.Z) <= 0.35
				and (d.Material == Enum.Material.Slate or (r == 176 and g == 170 and b == 158) or (r == 64 and g == 67 and b == 71) or (r == 68 and g == 72 and b == 76))

			if isFloorSlab then
				d.Color = C.FloorGraphite
				d.Material = Enum.Material.SmoothPlastic
				d.Reflectance = 0
			elseif d.Position.Y > 0.5 and d.Position.Y < 9.5 and d.Size.Y >= 10.0 and math.min(d.Size.X, d.Size.Z) <= 0.9 then
				if r >= 220 and g >= 220 and b >= 215 then
					d.Color = C.WallWhite
					d.Material = Enum.Material.SmoothPlastic
					table.insert(wallCache, d)
					table.insert(ceilingExtendCache, d)
				end
			elseif d.Position.Y >= 8.0 and d.Position.Y <= 13.5 and d.Size.Y >= 2.5 and d.Size.Y < 10.0 and math.min(d.Size.X, d.Size.Z) >= 0.3 and math.min(d.Size.X, d.Size.Z) <= 0.9 then
				-- Bandeiras / vergas acima das portas
				if r >= 220 and g >= 220 and b >= 215 then
					d.Color = C.WallWhite
					d.Material = Enum.Material.SmoothPlastic
					table.insert(ceilingExtendCache, d)
				end
			elseif d.Position.Y > 0.25 and d.Position.Y < 0.75 and d.Size.Y <= 0.65 and r == 75 and g == 82 and b == 89 then
				d.Color = C.BaseboardGrey
			end
		end
	end

	for _, wall in ipairs(wallCache) do
		local sz = wall.Size
		local xThin = sz.X < sz.Z
		local wrapX = if xThin then sz.X + 0.04 else sz.X
		local wrapZ = if xThin then sz.Z else sz.Z + 0.04
		local baseCF = CFrame.new(wall.Position.X, 0, wall.Position.Z) * wall.CFrame.Rotation

		if isInSaguaoZone(wall.Position) then
			-- Faixa superior verde-lima característica do Saguão (084933, 085053)
			local topY = wall.Position.Y + sz.Y * 0.5
			local bandH = 2.15
			Helpers.MakePart(
				geomFolder,
				"SaguaoLimeBand",
				Vector3.new(wrapX, bandH, wrapZ),
				baseCF * CFrame.new(0, topY - bandH * 0.5 - 0.05, 0),
				C.HallLimeBand,
				Enum.Material.SmoothPlastic,
				false,
				false,
				counter
			)
		else
			-- Barrado inferior verde-IFSul nos corredores (~1.15m = 3.85 studs acima do rodapé)
			local dadoH = 3.85
			Helpers.MakePart(
				geomFolder,
				"CorridorGreenDado",
				Vector3.new(wrapX, dadoH, wrapZ),
				baseCF * CFrame.new(0, 0.56 + dadoH * 0.5, 0),
				C.CorridorGreenDado,
				Enum.Material.SmoothPlastic,
				false,
				false,
				counter
			)
		end
	end

	-- Fecha todos os vãos entre o topo das divisórias/vergas de porta e a laje do teto
	for _, wall in ipairs(ceilingExtendCache) do
		local topY = wall.Position.Y + wall.Size.Y * 0.5
		local ceilY = raycastCeilingY(buildingsRP, wall.Position, topY + 0.05)
		if ceilY then
			local gap = ceilY - topY
			if gap >= 0.15 and gap <= 12.0 then
				local fillerH = gap + 0.02
				local baseCF = CFrame.new(wall.Position.X, 0, wall.Position.Z) * wall.CFrame.Rotation
				Helpers.MakePart(
					geomFolder,
					"WallTopFiller",
					Vector3.new(wall.Size.X, fillerH, wall.Size.Z),
					baseCF * CFrame.new(0, topY + fillerH * 0.5, 0),
					C.WallWhite,
					Enum.Material.SmoothPlastic,
					true,
					false,
					counter
				)
			end
		end
	end
end

-- Fecha frestas estreitas entre salas adjacentes (preservando passagens/portas reais e recorte da porta 112)
local function fillInterRoomGaps(campusRoot: Instance, geomFolder: Folder, counter: { count: number })
	local buildingsRP = makeBuildingsRayParams(campusRoot:FindFirstChild("Buildings"))
	local roomsByBuilding: { [string]: { CampusData.RoomData } } = {}
	for _, rm in ipairs(CampusData.Rooms) do
		if rm.buildingId ~= "bloco_800" then
			roomsByBuilding[rm.buildingId] = roomsByBuilding[rm.buildingId] or {}
			table.insert(roomsByBuilding[rm.buildingId], rm)
		end
	end

	local function hasOpeningOnSide(rm: CampusData.RoomData, side: string, sMin: number, sMax: number): boolean
		for _, os in ipairs(rm.openSides) do
			if os == side then
				return true
			end
		end
		for _, dr in ipairs(rm.doors) do
			if dr.side == side then
				local hw = dr.width * 0.5
				if dr.offset + hw >= sMin and dr.offset - hw <= sMax then
					return true
				end
			end
		end
		return false
	end

	local function buildGapFillerBox(centerCF: CFrame, wallSize: Vector3, dadoSize: Vector3, baseSize: Vector3, ceilY: number)
		local wallH = math.max(1.0, ceilY - 0.14)
		Helpers.MakePart(
			geomFolder,
			"WallGapFiller",
			Vector3.new(wallSize.X, wallH, wallSize.Z),
			centerCF * CFrame.new(0, 0.16 + wallH * 0.5, 0),
			C.WallWhite,
			Enum.Material.SmoothPlastic,
			true,
			false,
			counter
		)
		Helpers.MakePart(
			geomFolder,
			"WallGapBaseboard",
			Vector3.new(baseSize.X, 0.43, baseSize.Z),
			centerCF * CFrame.new(0, 0.38, 0),
			C.BaseboardGrey,
			Enum.Material.SmoothPlastic,
			false,
			false,
			counter
		)
		if isInSaguaoZone(centerCF.Position) then
			local bandH = 2.15
			Helpers.MakePart(
				geomFolder,
				"WallGapLimeBand",
				Vector3.new(dadoSize.X, bandH, dadoSize.Z),
				centerCF * CFrame.new(0, math.min(ceilY, 12.86) - bandH * 0.5 - 0.05, 0),
				C.HallLimeBand,
				Enum.Material.SmoothPlastic,
				false,
				false,
				counter
			)
		else
			local dadoH = 3.85
			Helpers.MakePart(
				geomFolder,
				"WallGapDado",
				Vector3.new(dadoSize.X, dadoH, dadoSize.Z),
				centerCF * CFrame.new(0, 0.56 + dadoH * 0.5, 0),
				C.CorridorGreenDado,
				Enum.Material.SmoothPlastic,
				false,
				false,
				counter
			)
		end
	end

	local minGap = 0.08 * STUDS_PER_METER
	local maxGap = 1.15 * STUDS_PER_METER
	local minOverlap = 1.2 * STUDS_PER_METER

	for _, list in pairs(roomsByBuilding) do
		for i = 1, #list do
			local A = list[i]
			local aCF = CFrame.new(A.center.X, 0, A.center.Z) * CFrame.Angles(0, math.rad(A.rotDeg), 0)
			local ax0, az0 = A.size.X * 0.5, A.size.Y * 0.5

			for j = i + 1, #list do
				local B = list[j]
				local diff = math.abs((A.rotDeg - B.rotDeg + 180) % 360 - 180)
				if diff <= 5 then
					local rel = aCF:PointToObjectSpace(Vector3.new(B.center.X, 0, B.center.Z))
					local bx, bz = rel.X, rel.Z
					local bx0, bz0 = B.size.X * 0.5, B.size.Y * 0.5

					-- 1) Fresta ao longo de X (Leste/Oeste entre A e B)
					local xGap = if bx > 0 then (bx - bx0 - ax0) else (-ax0 - (bx + bx0))
					local zMin, zMax = math.max(-az0, bz - bz0), math.min(az0, bz + bz0)
					local zLen = zMax - zMin
					if xGap >= minGap and xGap <= maxGap and zLen >= minOverlap then
						local aSide = if bx > 0 then "east" else "west"
						local bSide = if bx > 0 then "west" else "east"
						if not hasOpeningOnSide(A, aSide, zMin, zMax) and not hasOpeningOnSide(B, bSide, zMin - bz, zMax - bz) then
							local xMid = if bx > 0 then (ax0 + xGap * 0.5) else (-ax0 - xGap * 0.5)
							local zMid = (zMin + zMax) * 0.5
							local worldCF = aCF * CFrame.new(xMid, 0, zMid)
							local ceilY = raycastCeilingY(buildingsRP, worldCF.Position, 10.0) or (A.ceilingH + 5.0)
							local xSpan = xGap + 0.40
							buildGapFillerBox(
								worldCF,
								Vector3.new(xSpan, 1, zLen + 0.50),
								Vector3.new(xSpan - 0.02, 1, zLen + 0.54),
								Vector3.new(xSpan - 0.02, 1, zLen + 0.55),
								ceilY
							)
						end
					end

					-- 2) Fresta ao longo de Z (Norte/Sul entre A e B)
					local zGap = if bz > 0 then (bz - bz0 - az0) else (-az0 - (bz + bz0))
					local xMin, xMax = math.max(-ax0, bx - bx0), math.min(ax0, bx + bx0)
					-- Recorta atrás da Sala 111 para não invadir a nova porta leste-sul da Sala 112
					if (A.id == "sala_112" and B.id == "sala_111") or (A.id == "sala_111" and B.id == "sala_112") then
						if A.id == "sala_112" then
							xMax = math.min(xMax, 4.10)
						else
							xMax = math.min(xMax, bx + 4.10)
						end
					end
					local xLen = xMax - xMin
					if zGap >= minGap and zGap <= maxGap and xLen >= minOverlap then
						local aSide = if bz > 0 then "south" else "north"
						local bSide = if bz > 0 then "north" else "south"
						if not hasOpeningOnSide(A, aSide, xMin, xMax) and not hasOpeningOnSide(B, bSide, xMin - bx, xMax - bx) then
							local zMid = if bz > 0 then (az0 + zGap * 0.5) else (-az0 - zGap * 0.5)
							local xMid = (xMin + xMax) * 0.5
							local worldCF = aCF * CFrame.new(xMid, 0, zMid)
							local ceilY = raycastCeilingY(buildingsRP, worldCF.Position, 10.0) or (A.ceilingH + 5.0)
							local zSpan = zGap + 0.40
							buildGapFillerBox(
								worldCF,
								Vector3.new(xLen + 0.50, 1, zSpan),
								Vector3.new(xLen + 0.54, 1, zSpan - 0.02),
								Vector3.new(xLen + 0.55, 1, zSpan - 0.02),
								ceilY
							)
						end
					end
				end
			end
		end
	end
end

-- Juntas quadriculadas e variações sutis de cerâmica grafite no Saguão e eixos principais
local function buildTileGridAccents(geomFolder: Folder, counter: { count: number })
	local function addTiledRun(p0m: { number }, p1m: { number }, widthM: number, tileStepM: number, addChecker: boolean)
		local p0 = m2s(p0m[1], 0.178, p0m[2])
		local p1 = m2s(p1m[1], 0.178, p1m[2])
		local delta = p1 - p0
		local len = delta.Magnitude
		if len < 2 then return end
		local dir = delta.Unit
		local side = dir:Cross(Vector3.yAxis).Unit
		local cf = CFrame.lookAt((p0 + p1) * 0.5, p1)
		local widthS = widthM * STUDS_PER_METER
		local stepS = tileStepM * STUDS_PER_METER

		-- Juntas longitudinais
		local lanes = math.max(1, math.floor(widthS / stepS))
		for k = -lanes * 0.5, lanes * 0.5 do
			local off = k * stepS
			if math.abs(off) <= widthS * 0.5 then
				Helpers.MakePart(
					geomFolder,
					"TileJointLong",
					Vector3.new(0.05, 0.025, len),
					cf * CFrame.new(off, 0, 0),
					C.FloorJoint,
					Enum.Material.SmoothPlastic,
					false,
					false,
					counter
				)
			end
		end

		-- Juntas transversais + placas alternadas opcionais
		local count = math.floor(len / stepS)
		for i = 0, count do
			local dAlong = -len * 0.5 + i * stepS
			Helpers.MakePart(
				geomFolder,
				"TileJointCross",
				Vector3.new(widthS, 0.025, 0.05),
				cf * CFrame.new(0, 0, dAlong),
				C.FloorJoint,
				Enum.Material.SmoothPlastic,
				false,
				false,
				counter
			)
			if addChecker and i < count then
				for j = -math.floor(lanes * 0.5), math.floor(lanes * 0.5) - 1 do
					if (i + j) % 2 == 0 then
						local tileCol = if (i * 3 + j) % 4 == 0 then C.FloorTileDark else C.FloorTileLight
						local tilePos = (p0 + p1) * 0.5 + dir * (dAlong + stepS * 0.5) + side * ((j + 0.5) * stepS)
						Helpers.MakePart(
							geomFolder,
							"CeramicTilePatch",
							Vector3.new(stepS - 0.08, 0.02, stepS - 0.08),
							CFrame.lookAt(tilePos - Vector3.new(0, 0.004, 0), tilePos - Vector3.new(0, 0.004, 0) + dir),
							tileCol,
							Enum.Material.SmoothPlastic,
							false,
							false,
							counter
						)
					end
				end
			end
		end
	end

	-- Saguão (malha quadriculada com variação tonal fiel a 084933 / 085053)
	addTiledRun({ -23.0, -6.8 }, { -8.8, -6.8 }, 8.6, 1.15, true)
	addTiledRun({ -18.5, -1.8 }, { -2.0, 8.8 }, 6.2, 1.15, false)
	-- Principais eixos de corredor
	addTiledRun({ -25.2, -18.3 }, { 17.5, -25.3 }, 3.4, 1.2, false) -- Setor 200 O-L
	addTiledRun({ 31.6, -13.0 }, { 37.8, 27.5 }, 3.4, 1.2, false) -- Setor 200/230 N-S
	addTiledRun({ 34.5, -51.0 }, { 37.5, -22.5 }, 3.4, 1.2, false) -- Setor 300 N-S
	addTiledRun({ 25.0, -36.5 }, { 53.0, -40.8 }, 3.4, 1.2, false) -- Setor 300 E-O
	addTiledRun({ -59.0, -11.6 }, { -33.5, -16.0 }, 3.2, 1.2, false) -- Setor 100 Sul
	addTiledRun({ -59.0, -33.8 }, { -37.0, -37.6 }, 3.2, 1.2, false) -- Setor 100 Norte
end

type CorridorRun = {
	name: string,
	p0: { number },
	p1: { number },
	ceilY: number,
	trayY: number,
	lampY: number,
	pipeOff: number,
	lampSpacing: number,
}

-- Eletrocalhas galvanizadas, luminárias lineares duplas (AlwaysOn) e tubulação vermelha de incêndio
local function buildCorridorInfrastructure(geomFolder: Folder, lightsFolder: Folder, counter: { count: number })
	local runs: { CorridorRun } = {
		{ name = "Setor100_Sul", p0 = { -59.0, -11.6 }, p1 = { -33.5, -16.0 }, ceilY = 17.0, trayY = 14.0, lampY = 13.1, pipeOff = 5.4, lampSpacing = 18.5 },
		{ name = "Setor100_Oeste", p0 = { -57.6, -32.8 }, p1 = { -55.0, -13.5 }, ceilY = 17.0, trayY = 14.0, lampY = 13.1, pipeOff = 5.2, lampSpacing = 18.5 },
		{ name = "Setor100_Norte", p0 = { -59.0, -33.8 }, p1 = { -37.0, -37.6 }, ceilY = 17.0, trayY = 14.0, lampY = 13.1, pipeOff = -5.4, lampSpacing = 18.5 },
		{ name = "Setor100_Leste", p0 = { -41.2, -35.5 }, p1 = { -38.6, -15.0 }, ceilY = 17.0, trayY = 14.0, lampY = 13.1, pipeOff = -5.2, lampSpacing = 18.5 },
		{ name = "Convivencia", p0 = { -32.5, -16.8 }, p1 = { -25.5, -17.5 }, ceilY = 15.5, trayY = 13.2, lampY = 12.3, pipeOff = 4.4, lampSpacing = 14.0 },
		{ name = "Setor200_EW", p0 = { -25.2, -18.3 }, p1 = { 17.5, -25.3 }, ceilY = 17.7, trayY = 14.2, lampY = 13.2, pipeOff = 6.2, lampSpacing = 19.0 },
		{ name = "Setor200_Conn", p0 = { 18.0, -12.0 }, p1 = { 31.6, -13.0 }, ceilY = 17.7, trayY = 14.2, lampY = 13.2, pipeOff = 0, lampSpacing = 18.0 },
		{ name = "Setor200_230_NS", p0 = { 31.6, -13.0 }, p1 = { 37.8, 27.5 }, ceilY = 17.7, trayY = 14.2, lampY = 13.2, pipeOff = -6.2, lampSpacing = 19.0 },
		{ name = "Saguao_Diag", p0 = { -23.0, -7.8 }, p1 = { -0.5, 8.2 }, ceilY = 17.7, trayY = 14.4, lampY = 13.4, pipeOff = 0, lampSpacing = 17.5 },
		{ name = "Saguao_Norte", p0 = { -22.0, -9.2 }, p1 = { -9.5, -8.5 }, ceilY = 17.7, trayY = 14.4, lampY = 13.4, pipeOff = 0, lampSpacing = 16.5 },
		{ name = "Setor300_NS", p0 = { 34.5, -51.0 }, p1 = { 37.5, -22.5 }, ceilY = 22.0, trayY = 15.0, lampY = 13.8, pipeOff = -6.2, lampSpacing = 19.5 },
		{ name = "Setor300_EW_W", p0 = { 24.5, -36.5 }, p1 = { 33.8, -37.9 }, ceilY = 22.0, trayY = 15.0, lampY = 13.8, pipeOff = 6.0, lampSpacing = 14.0 },
		{ name = "Setor300_EW_E", p0 = { 39.2, -38.7 }, p1 = { 53.0, -40.8 }, ceilY = 22.0, trayY = 15.0, lampY = 13.8, pipeOff = 0, lampSpacing = 16.0 },
		{ name = "Setor400_EW", p0 = { 39.5, 53.5 }, p1 = { 68.0, 49.0 }, ceilY = 22.0, trayY = 15.0, lampY = 13.8, pipeOff = 0, lampSpacing = 20.0 },
		{ name = "Bloco800_NS", p0 = { 26.5, -72.0 }, p1 = { 40.5, -92.5 }, ceilY = 18.4, trayY = 14.2, lampY = 13.1, pipeOff = 0, lampSpacing = 18.0 },
		{ name = "Bloco800_EW", p0 = { 23.0, -89.5 }, p1 = { 44.0, -75.0 }, ceilY = 18.4, trayY = 14.2, lampY = 13.1, pipeOff = 0, lampSpacing = 18.0 },
	}

	for _, r in ipairs(runs) do
		local p0 = m2s(r.p0[1], r.trayY, r.p0[2])
		local p1 = m2s(r.p1[1], r.trayY, r.p1[2])
		local delta = p1 - p0
		local len = delta.Magnitude
		if len >= 2 then
			local dir = delta.Unit
			local side = dir:Cross(Vector3.yAxis).Unit
			local mid = (p0 + p1) * 0.5
			local cf = CFrame.lookAt(mid, p1)

			-- Eletrocalha galvanizada (fundo + abas laterais + tirantes até o teto)
			Helpers.MakePart(geomFolder, r.name .. "_TrayBase", Vector3.new(0.72, 0.08, len), cf, C.GalvSteel, Enum.Material.Metal, false, false, counter)
			for _, sx in ipairs({ -0.34, 0.34 }) do
				Helpers.MakePart(geomFolder, r.name .. "_TrayRim", Vector3.new(0.06, 0.16, len), cf * CFrame.new(sx, 0.08, 0), C.GalvSteel, Enum.Material.Metal, false, false, counter)
			end
			local dropH = math.max(0.4, r.ceilY - r.trayY)
			local rodStep = 14.0
			local rodCount = math.max(2, math.floor(len / rodStep))
			for i = 0, rodCount do
				local dAlong = -len * 0.5 + (i / rodCount) * len
				Helpers.MakePart(
					geomFolder,
					r.name .. "_TrayRod",
					Vector3.new(0.06, dropH, 0.06),
					cf * CFrame.new(0, dropH * 0.5, dAlong),
					C.GalvSteel,
					Enum.Material.Metal,
					false,
					false,
					counter
				)
			end

			-- Luminárias lineares duplas suspensas
			local lampCount = math.max(1, math.floor(len / r.lampSpacing))
			for i = 1, lampCount do
				local t = (i - 0.5) / lampCount
				local lPos = Vector3.new(p0.X, r.lampY, p0.Z) + dir * (t * len)
				local lCF = CFrame.lookAt(lPos, lPos + dir)
				Helpers.CreateSuspendedFluorescent(
					geomFolder,
					lightsFolder,
					lCF,
					4.5,
					r.trayY - r.lampY,
					28,
					0.24,
					0.85,
					true,
					counter
				)
			end

			-- Tubulação vermelha de incêndio aparente ao longo da parede alta (085352)
			if math.abs(r.pipeOff) > 0.1 then
				local pipeY = 11.45
				local pipeP0 = Vector3.new(p0.X, pipeY, p0.Z) + side * r.pipeOff
				local pipeP1 = Vector3.new(p1.X, pipeY, p1.Z) + side * r.pipeOff
				Helpers.MakeSegmentCylinder(geomFolder, r.name .. "_FirePipe", pipeP0, pipeP1, 0.20, C.FirePipeRed, Enum.Material.Metal, false, counter)
			end
		end
	end
end

-- Saguão / Hall Principal completo (084933, 085040, 085053)
local function buildSaguaoPrincipal(geomFolder: Folder, lightsFolder: Folder, counter: { count: number })
	-- 1. Balcão branco/vidro da Recepção ([-13.4, -3.5]m, rot 143° para frente voltada à entrada principal)
	local recPos = m2s(-13.4, 0.16, -3.5)
	local recRot = CFrame.Angles(0, math.rad(143), 0)
	local recCF = CFrame.new(recPos) * recRot

	-- Balcão em L branco com tampo amadeirado
	Helpers.MakePart(geomFolder, "RecDeskFront", Vector3.new(10.5, 3.6, 2.2), recCF * CFrame.new(0, 1.8, 0), C.WallWhite, Enum.Material.SmoothPlastic, true, false, counter)
	Helpers.MakePart(geomFolder, "RecDeskTop", Vector3.new(10.8, 0.20, 2.5), recCF * CFrame.new(0, 3.70, 0), C.WoodLight, Enum.Material.Wood, true, false, counter)
	Helpers.MakePart(geomFolder, "RecDeskSide", Vector3.new(2.2, 3.6, 6.4), recCF * CFrame.new(4.15, 1.8, 2.8), C.WallWhite, Enum.Material.SmoothPlastic, true, false, counter)
	Helpers.MakePart(geomFolder, "RecDeskSideTop", Vector3.new(2.5, 0.20, 6.6), recCF * CFrame.new(4.15, 3.70, 2.8), C.WoodLight, Enum.Material.Wood, true, false, counter)

	-- Fechamento envidraçado superior da Recepção (085040)
	Helpers.MakePart(geomFolder, "RecGlassFront", Vector3.new(9.8, 3.3, 0.14), recCF * CFrame.new(0, 5.45, -0.85), C.GlassTint, Enum.Material.Glass, false, false, counter).Transparency = 0.62
	Helpers.MakePart(geomFolder, "RecGlassHeader", Vector3.new(10.6, 0.25, 0.24), recCF * CFrame.new(0, 7.15, -0.85), C.WallWhite, Enum.Material.Metal, false, false, counter)
	for _, mx in ipairs({ -5.0, -1.7, 1.7, 5.0 }) do
		Helpers.MakePart(geomFolder, "RecGlassMullion", Vector3.new(0.18, 3.4, 0.22), recCF * CFrame.new(mx, 5.45, -0.85), C.WallWhite, Enum.Material.Metal, false, false, counter)
	end
	-- Monitor e cadeira atrás do balcão
	Helpers.MakePart(geomFolder, "RecMonitor", Vector3.new(1.7, 1.1, 0.14), recCF * CFrame.new(-1.8, 4.45, 0.45), C.DarkSteel, Enum.Material.SmoothPlastic, false, false, counter)
	Helpers.MakePart(geomFolder, "RecChairSeat", Vector3.new(1.5, 0.2, 1.5), recCF * CFrame.new(-1.8, 1.75, 2.2), C.DarkSteel, Enum.Material.SmoothPlastic, true, false, counter)
	Helpers.MakePart(geomFolder, "RecChairBack", Vector3.new(1.4, 1.6, 0.2), recCF * CFrame.new(-1.8, 2.65, 2.85), C.DarkSteel, Enum.Material.SmoothPlastic, false, false, counter)

	-- Placa discreta "RECEPÇÃO" no topo frontal do fechamento (visível em ambos os lados)
	local recSign = Helpers.MakePart(geomFolder, "RecHeaderSign", Vector3.new(4.2, 0.72, 0.14), recCF * CFrame.new(0, 7.65, -0.85), C.IFSulGreen, Enum.Material.SmoothPlastic, false, false, counter)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local rsg = Helpers.MakeSurfaceGui(recSign, 55, face)
		local rlbl = Instance.new("TextLabel")
		rlbl.Size = UDim2.fromScale(1, 1)
		rlbl.BackgroundTransparency = 1
		rlbl.Font = Enum.Font.GothamBold
		rlbl.Text = "RECEPÇÃO"
		rlbl.TextColor3 = Color3.new(1, 1, 1)
		rlbl.TextScaled = true
		rlbl.Parent = rsg
	end

	-- 2. Parede norte da sala 201 ([-18.20, -11.13]m, rot -9.4°, voltada para o Sul into Saguão)
	local wallDir = Vector3.new(0.1633, 0, 0.9866).Unit -- Sul local da parede (normal externa)
	local wallRight = Vector3.yAxis:Cross(wallDir).Unit -- Leste local ao longo da parede

	-- Quadro verde com moldura azul + aba de cortiça (084933)
	local boardPos = m2s(-18.2, 5.8, -10.82)
	local board = Helpers.MakeFacingBox(geomFolder, "SaguaoChalkboard", boardPos, wallDir, 9.2, 4.1, 0.16, C.ChalkboardFrame, Enum.Material.Metal, false, counter)
	Helpers.MakePart(geomFolder, "ChalkGreenFace", Vector3.new(6.8, 3.7, 0.06), board.CFrame * CFrame.new(0.9, 0, -0.09), C.ChalkboardGreen, Enum.Material.SmoothPlastic, false, false, counter)
	Helpers.MakePart(geomFolder, "ChalkCorkStrip", Vector3.new(1.8, 3.7, 0.06), board.CFrame * CFrame.new(-3.45, 0, -0.09), C.CorkBoard, Enum.Material.Wood, false, false, counter)

	-- 2 Telefones internos na prateleira à direita do quadro (084933)
	local phoneAnchor = boardPos + wallRight * 6.0
	Helpers.MakeFacingBox(geomFolder, "PhoneShelf", phoneAnchor - Vector3.new(0, 1.3, 0), wallDir, 2.2, 0.14, 0.8, C.WallWhite, Enum.Material.Wood, false, counter)
	for _, pxOff in ipairs({ -0.55, 0.55 }) do
		Helpers.MakeFacingBox(geomFolder, "WallPhone", phoneAnchor + wallRight * pxOff - Vector3.new(0, 0.4, 0), wallDir, 0.65, 0.85, 0.35, C.DarkSteel, Enum.Material.SmoothPlastic, false, counter)
	end

	-- Quadro elétrico à esquerda do quadro verde (084933)
	Helpers.CreateElectricalPanel(geomFolder, boardPos - wallRight * 7.8 - Vector3.new(0, 0.4, 0), wallDir, 1.9, 2.6, counter)

	-- 2 Mesas brancas de estudo com 4 cadeiras acopladas cada (084933)
	local tRot = CFrame.lookAt(Vector3.zero, wallDir)
	Helpers.CreateSaguaoStudyTable(geomFolder, CFrame.new(m2s(-19.5, 0.16, -8.8)) * tRot, counter)
	Helpers.CreateSaguaoStudyTable(geomFolder, CFrame.new(m2s(-16.5, 0.16, -9.3)) * tRot, counter)

	-- 3. Parede de apoio_academico ([-13.06, -11.97]m): Hidrante duplo + TV "PERDIDOS E ACHADOS" + Mural Colorido (085040, 085053)
	local apWallPos = m2s(-13.06, 0, -11.65)
	Helpers.CreateHydrantCabinet(geomFolder, apWallPos + Vector3.new(0, 2.6, 0) - wallRight * 3.8, wallDir, counter)

	-- TV Perdidos e Achados
	local tvPart = Helpers.MakeFacingBox(geomFolder, "TVPerdidosAchados", apWallPos + Vector3.new(0, 6.4, 0) - wallRight * 3.8, wallDir, 3.8, 2.2, 0.18, C.DarkSteel, Enum.Material.SmoothPlastic, false, counter)
	local tvSg = Helpers.MakeSurfaceGui(tvPart, 50)
	local tvBg = Instance.new("Frame")
	tvBg.Size = UDim2.fromScale(1, 1)
	tvBg.BackgroundColor3 = Color3.fromRGB(246, 206, 48)
	tvBg.BorderSizePixel = 0
	tvBg.Parent = tvSg
	local tvLbl = Instance.new("TextLabel")
	tvLbl.Size = UDim2.fromScale(0.84, 0.76)
	tvLbl.Position = UDim2.fromScale(0.08, 0.12)
	tvLbl.BackgroundTransparency = 1
	tvLbl.Font = Enum.Font.GothamBold
	tvLbl.Text = "PERDIDOS\nE ACHADOS"
	tvLbl.TextColor3 = Color3.fromRGB(30, 34, 38)
	tvLbl.TextScaled = true
	tvLbl.Parent = tvBg

	-- Grande Mural Colorido Institucional ao lado do hidrante (085040, 085053)
	local muralPos = apWallPos + Vector3.new(0, 5.5, 0) + wallRight * 3.8
	local muralPart = Helpers.MakeFacingBox(geomFolder, "SaguaoColorMural", muralPos, wallDir, 8.6, 6.8, 0.10, Color3.fromRGB(238, 240, 238), Enum.Material.SmoothPlastic, false, counter)
	local msg = Helpers.MakeSurfaceGui(muralPart, 36)
	local mCanvas = Instance.new("Frame")
	mCanvas.Size = UDim2.fromScale(1, 1)
	mCanvas.BackgroundColor3 = Color3.fromRGB(246, 246, 242)
	mCanvas.BorderSizePixel = 0
	mCanvas.Parent = msg
	local blocks = {
		{ 0.00, 0.55, 0.42, 0.45, Color3.fromRGB(244, 212, 64) },
		{ 0.42, 0.62, 0.36, 0.38, Color3.fromRGB(238, 198, 52) },
		{ 0.12, 0.18, 0.28, 0.36, Color3.fromRGB(48, 152, 72) },
		{ 0.44, 0.14, 0.30, 0.42, Color3.fromRGB(52, 112, 186) },
		{ 0.74, 0.24, 0.24, 0.44, Color3.fromRGB(68, 168, 86) },
		{ 0.02, 0.04, 0.18, 0.16, Color3.fromRGB(64, 162, 78) },
		{ 0.62, 0.04, 0.22, 0.16, Color3.fromRGB(242, 196, 48) },
	}
	for _, b in ipairs(blocks) do
		local f = Instance.new("Frame")
		f.Position = UDim2.fromScale(b[1] :: number, b[2] :: number)
		f.Size = UDim2.fromScale(b[3] :: number, b[4] :: number)
		f.BackgroundColor3 = b[5] :: Color3
		f.BorderSizePixel = 0
		f.Parent = mCanvas
	end
	local mTag = Instance.new("TextLabel")
	mTag.Position = UDim2.fromScale(0.06, 0.80)
	mTag.Size = UDim2.fromScale(0.45, 0.14)
	mTag.BackgroundTransparency = 1
	mTag.Font = Enum.Font.GothamBold
	mTag.Text = "IFSul • Sapucaia do Sul"
	mTag.TextColor3 = Color3.fromRGB(32, 72, 42)
	mTag.TextScaled = true
	mTag.TextXAlignment = Enum.TextXAlignment.Left
	mTag.Parent = mCanvas

	-- 4. Parede leste do Saguão ([-9.17, -3.36]m, 8.2m de largura voltada para Oeste): Vitrine de Troféus + Bancos + Clerestório (085053)
	local eastWallOutward = Vector3.new(-0.987, 0, -0.160).Unit -- Apontando para Oeste (dentro do Saguão)
	local eastWallAlong = Vector3.yAxis:Cross(eastWallOutward).Unit
	local vitrineCenter = m2s(-9.42, 4.4, -3.36)

	-- Gabinete envidraçado de troféus (4.8m = 17.1 studs)
	local vitW, vitH, vitD = 16.4, 7.6, 1.55
	local vitBase = Helpers.MakeFacingBox(geomFolder, "TrophyCaseBack", vitrineCenter, eastWallOutward, vitW, vitH, 0.14, Color3.fromRGB(178, 184, 190), Enum.Material.SmoothPlastic, true, counter)
	local vCF = vitBase.CFrame
	Helpers.MakePart(geomFolder, "TrophyCaseTop", Vector3.new(vitW, 0.22, vitD), vCF * CFrame.new(0, vitH * 0.5, -vitD * 0.5), C.GalvSteel, Enum.Material.Metal, true, false, counter)
	Helpers.MakePart(geomFolder, "TrophyCaseBot", Vector3.new(vitW, 0.48, vitD), vCF * CFrame.new(0, -vitH * 0.5 + 0.24, -vitD * 0.5), Color3.fromRGB(108, 114, 120), Enum.Material.Metal, true, false, counter)
	Helpers.MakePart(geomFolder, "TrophyCaseGlass", Vector3.new(vitW - 0.2, vitH - 0.6, 0.10), vCF * CFrame.new(0, 0, -vitD), C.GlassTint, Enum.Material.Glass, true, false, counter).Transparency = 0.72
	for _, mx in ipairs({ -vitW * 0.5, -vitW * 0.25, 0, vitW * 0.25, vitW * 0.5 }) do
		Helpers.MakePart(geomFolder, "TrophyMullion", Vector3.new(0.16, vitH, 0.18), vCF * CFrame.new(mx, 0, -vitD), Color3.fromRGB(108, 114, 120), Enum.Material.Metal, false, false, counter)
	end
	for shelfIdx, sy in ipairs({ -1.8, 0.2, 2.0 }) do
		Helpers.MakePart(geomFolder, "TrophyShelf_" .. tostring(shelfIdx), Vector3.new(vitW - 0.4, 0.10, vitD - 0.2), vCF * CFrame.new(0, sy, -vitD * 0.5), C.GlassTint, Enum.Material.Glass, false, false, counter).Transparency = 0.42
		for tx = -6.2, 6.2, 3.1 do
			local cupCol = if (math.floor(tx) + shelfIdx) % 2 == 0 then Color3.fromRGB(214, 162, 34) else Color3.fromRGB(154, 162, 170)
			Helpers.MakePart(geomFolder, "TrophyPedestal", Vector3.new(0.55, 0.26, 0.55), vCF * CFrame.new(tx, sy + 0.18, -vitD * 0.5), C.DarkSteel, Enum.Material.SmoothPlastic, false, false, counter)
			Helpers.MakePart(geomFolder, "TrophyCup", Vector3.new(0.46, 0.85, 0.46), vCF * CFrame.new(tx, sy + 0.72, -vitD * 0.5), cupCol, Enum.Material.Metal, false, false, counter)
		end
	end

	-- 2 Bancos de ripas de madeira com ferro preto em frente à vitrine de troféus (085053)
	for _, bOff in ipairs({ -4.5, 4.5 }) do
		local bPos = m2s(-9.42, 0.16, -3.36) + eastWallAlong * bOff + eastWallOutward * 2.8
		local bCF = CFrame.lookAt(bPos, bPos + eastWallOutward)
		Helpers.CreateWoodenSlatBench(geomFolder, bCF, 6.4, true, counter)
	end

	-- Faixa verde-lima superior e janela clerestório sobre a parede leste do Saguão (085053)
	Helpers.MakeFacingBox(geomFolder, "EastHallLimeBand", m2s(-9.42, 11.8, -3.36), eastWallOutward, 28.0, 2.2, 0.25, C.HallLimeBand, Enum.Material.SmoothPlastic, false, counter)
	Helpers.MakeFacingBox(geomFolder, "EastHallClerestory", m2s(-9.42, 15.2, -3.36), eastWallOutward, 28.0, 3.2, 0.20, C.GlassTint, Enum.Material.Glass, false, counter).Transparency = 0.35

	-- 5. Expositores centrais, lixeiras seletivas e vasos de planta no Saguão (085053)
	for _, exPosM in ipairs({ { -10.8, -6.2 }, { -11.5, -0.5 } }) do
		local exPos = m2s(exPosM[1], 0.16, exPosM[2])
		local exCF = CFrame.new(exPos) * CFrame.Angles(0, math.rad(-25), 0)
		Helpers.MakePart(geomFolder, "DisplayStandBase", Vector3.new(2.2, 0.16, 1.4), exCF * CFrame.new(0, 0.08, 0), C.DarkSteel, Enum.Material.Metal, true, false, counter)
		Helpers.MakePart(geomFolder, "DisplayStandBoard", Vector3.new(2.0, 5.4, 0.18), exCF * CFrame.new(0, 3.2, 0), Color3.fromRGB(238, 186, 62), Enum.Material.Wood, true, false, counter)
	end

	local binCF = CFrame.lookAt(m2s(-19.5, 0.16, -3.2), m2s(-15.0, 0.16, -5.0))
	Helpers.CreateRecyclingBins(geomFolder, binCF, 4, counter)
	Helpers.CreatePottedPlant(geomFolder, m2s(-10.2, 0.16, -7.8), 1.05, counter)
	Helpers.CreatePottedPlant(geomFolder, m2s(-9.6, 0.16, 0.6), 1.05, counter)
end

-- Placas direcionais oficiais de parede, bancos, hidrantes e lixeiras nos corredores (085352, 085358)
local function buildCorridorPropsAndSigns(interiors: Instance, geomFolder: Folder, counter: { count: number })
	-- Helper para encostar placa exatamente na parede real do corredor via raycast
	local wallParams = RaycastParams.new()
	wallParams.FilterType = Enum.RaycastFilterType.Include
	wallParams.FilterDescendantsInstances = { interiors }

	local function placeSignOnWall(name: string, originM: { number }, rayDir: Vector3, w: number, h: number, rows: { Helpers.SignRow })
		local origin = m2s(originM[1], 6.2, originM[2])
		local hit = workspace:Raycast(origin, rayDir.Unit * 20, wallParams)
		local pos = if hit then (hit.Position + hit.Normal * 0.12) else (origin + rayDir.Unit * 5)
		local normal = if hit then hit.Normal else (-rayDir.Unit)
		Helpers.CreateOfficialWallSign(geomFolder, name, pos, normal, w, h, rows, counter)
	end

	-- 1. Placa oficial eixo Setor 300 / 800 / Esportivo (085352) — parede oeste ao sul da porta 301
	placeSignOnWall(
		"Sign_Setor300_800",
		{ 36.8, -25.6 },
		Vector3.new(-1, 0, 0),
		4.4,
		5.2,
		{
			{ arrow = "→", label = "Salas de Aula - 308 e 309" },
			{ arrow = "←", label = "Lab de Química / LCQ" },
			{ arrow = "←", label = "Lab de Plásticos / Reciclagem" },
			{ arrow = "↑", label = "Lab de Biologia (307)" },
			{ arrow = "←", label = "Lab de Física (804)" },
			{ arrow = "←", label = "Salas de Aula - 801 a 812" },
			{ arrow = "←", label = "Complexo Esportivo" },
		}
	)

	-- 2. Placa oficial eixo Setor 200 / 230 / 400 (085358) — parede leste sólida ao norte da porta 229
	placeSignOnWall(
		"Sign_Setor200_230",
		{ 36.0, 13.8 },
		Vector3.new(1, 0, 0),
		4.4,
		5.2,
		{
			{ arrow = "←", label = "Banheiros" },
			{ arrow = "←", label = "Salas 217 a 234" },
			{ arrow = "←", label = "Labs de Informática (1–7)" },
			{ arrow = "←", label = "Lab de Mecânica / CNC" },
			{ arrow = "←", label = "Sala de Recursos (220)" },
			{ arrow = "→", label = "Sala de Docentes (229)" },
			{ arrow = "→", label = "Depep - Estágios (233)" },
		}
	)

	-- 3. Placa oficial Saguão / Setor 100 (parede norte do corredor de convivência)
	placeSignOnWall(
		"Sign_Setor100_Saguao",
		{ -28.5, -16.2 },
		Vector3.new(0, 0, -1),
		4.4,
		4.8,
		{
			{ arrow = "←", label = "Setor 100 — Direção / Ensino" },
			{ arrow = "←", label = "Setor de Saúde (112) / Psicologia" },
			{ arrow = "→", label = "Recepção / CORAC / Miniauditório" },
			{ arrow = "→", label = "Setor 200 / Cantina / Auditório 504" },
			{ arrow = "↓", label = "Biblioteca do Câmpus" },
		}
	)

	-- Bancos de ripas de madeira nos corredores (085352)
	Helpers.CreateWoodenSlatBench(geomFolder, CFrame.lookAt(m2s(-15.5, 0.16, -21.2), m2s(-15.5, 0.16, -18.0)), 6.2, true, counter)
	Helpers.CreateWoodenSlatBench(geomFolder, CFrame.lookAt(m2s(3.5, 0.16, -24.4), m2s(3.5, 0.16, -21.0)), 6.2, true, counter)
	Helpers.CreateWoodenSlatBench(geomFolder, CFrame.lookAt(m2s(34.2, 0.16, -34.2), m2s(37.5, 0.16, -34.2)), 5.8, true, counter)
	Helpers.CreateWoodenSlatBench(geomFolder, CFrame.lookAt(m2s(-48.5, 0.16, -14.8), m2s(-48.5, 0.16, -11.5)), 5.8, true, counter)

	-- Hidrantes, quadros elétricos e lixeiras seletivas nos corredores principais
	Helpers.CreateHydrantCabinet(geomFolder, m2s(2.0, 2.6, -18.2), Vector3.new(-0.16, 0, -0.987), counter)
	Helpers.CreateHydrantCabinet(geomFolder, m2s(37.2, 2.6, 2.0), Vector3.new(-0.988, 0, 0.151), counter)
	Helpers.CreateElectricalPanel(geomFolder, m2s(33.25, 4.6, 17.5), Vector3.new(0.988, 0, -0.151), 2.1, 2.8, counter)
	Helpers.CreateElectricalPanel(geomFolder, m2s(-44.0, 4.6, -11.10), Vector3.new(0.172, 0, -0.985), 2.1, 2.8, counter)

	Helpers.CreateRecyclingBins(geomFolder, CFrame.lookAt(m2s(35.8, 0.16, -25.5), m2s(35.8, 0.16, -30.0)), 3, counter)
	Helpers.CreateRecyclingBins(geomFolder, CFrame.lookAt(m2s(35.4, 0.16, 22.0), m2s(32.0, 0.16, 22.0)), 3, counter)
	Helpers.CreateRecyclingBins(geomFolder, CFrame.lookAt(m2s(-35.5, 0.16, -14.5), m2s(-35.5, 0.16, -18.0)), 3, counter)
end

function InteriorEnhancer.Apply(campusRoot: Instance): Folder
	local interiors = campusRoot:WaitForChild("Interiors")
	local lights = campusRoot:WaitForChild("Lights")

	sanitizeBaseline(campusRoot, interiors, lights)

	local geomFolder = Instance.new("Folder")
	geomFolder.Name = "InteriorEnhanced"
	geomFolder.Parent = interiors

	local lightsSub = Instance.new("Folder")
	lightsSub.Name = "InteriorEnhanced"
	lightsSub.Parent = lights

	local counter = { count = 0 }

	local function runChunk(name: string, fn: (Folder) -> ())
		local chunk = Instance.new("Folder")
		chunk.Name = name
		fn(chunk)
		chunk.Parent = geomFolder
		task.wait()
	end

	runChunk("DoorRelocations", function(f)
		fixDoorRelocations(campusRoot, interiors, f, counter)
	end)
	runChunk("WallsAndDado", function(f)
		upgradeFloorsAndWalls(campusRoot, interiors, f, counter)
	end)
	runChunk("InterRoomGaps", function(f)
		fillInterRoomGaps(campusRoot, f, counter)
	end)
	runChunk("TileGrid", function(f)
		buildTileGridAccents(f, counter)
	end)
	runChunk("CorridorInfra", function(f)
		buildCorridorInfrastructure(f, lightsSub, counter)
	end)
	runChunk("Saguao", function(f)
		buildSaguaoPrincipal(f, lightsSub, counter)
	end)
	runChunk("CorridorProps", function(f)
		buildCorridorPropsAndSigns(interiors, f, counter)
	end)

	-- Mantém referência tipada ao CampusData carregado para uso direto nas Partes 2 e 3
	geomFolder:SetAttribute("RoomsCataloged", #CampusData.Rooms)

	return geomFolder
end

return InteriorEnhancer
