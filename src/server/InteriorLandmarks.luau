--!strict
-- Parte 2 do detalhamento interno do IFSul — Câmpus Sapucaia do Sul:
-- 1) Pátio Interno do Setor 300 (Plásticos — lajotas, canteiro verde-escuro e murais) + Jardins 100 e 200
-- 2) Murais Icônicos de Corredor: Ipê Rosa (Setor 300/800) e Acrílico "Cursos Superiores" (Setor 200/230)
-- 3) Biblioteca Completa em 5 Zonas (Central, Periódicos/OPAC, Acervo Geral, Salão de Leitura, Cabines/Infanteca)
-- 4) Auditório 504 — Pedro Kaizer (palco, púlpito, telão, mesa, painéis acústicos) e Miniauditório 201

local CampusData = require(game:GetService("ReplicatedStorage"):WaitForChild("IFSul"):WaitForChild("CampusData"))
local Helpers = require(script.Parent.InteriorHelpers)

local InteriorLandmarks = {}

local C = Helpers.Colors

local C_DarkGreenPlanter = Color3.fromRGB(34, 86, 62)
local C_PaverDark = Color3.fromRGB(78, 80, 82)
local C_PaverAlt = Color3.fromRGB(68, 70, 73)
local C_StageWood = Color3.fromRGB(164, 110, 62)
local C_AcousticWood = Color3.fromRGB(186, 134, 82)
local C_SeatUpholstery = Color3.fromRGB(38, 118, 62)
local C_CarpetGreen = Color3.fromRGB(34, 88, 52)
local C_BinderColors = {
	Color3.fromRGB(192, 54, 48),
	Color3.fromRGB(44, 108, 168),
	Color3.fromRGB(48, 148, 68),
	Color3.fromRGB(218, 162, 46),
	Color3.fromRGB(112, 74, 148),
	Color3.fromRGB(224, 224, 220),
}

local function findRoom(id: string): CampusData.RoomData?
	for _, r in ipairs(CampusData.Rooms) do
		if r.id == id then
			return r
		end
	end
	return nil
end

local function roomCFrame(r: CampusData.RoomData): CFrame
	return CFrame.new(r.center.X, 0, r.center.Z) * CFrame.Angles(0, math.rad(r.rotDeg), 0)
end

local function hideBaselinePart(inst: BasePart)
	inst:SetAttribute("RelocatedHidden", true)
	inst.Transparency = 1
	inst.CanCollide = false
	inst.CanQuery = false
	for _, g in ipairs(inst:GetDescendants()) do
		if g:IsA("SurfaceGui") then
			g:SetAttribute("RelocatedHidden", true)
			g.Enabled = false
		end
	end
end

local function newSurfaceGui(parent: BasePart, face: Enum.NormalId, canvasW: number, canvasH: number): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = Vector2.new(canvasW, canvasH)
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.LightInfluence = 0.15
	sg.Parent = parent
	return sg
end

local function isInRectXZ(pos: Vector3, cf: CFrame, halfX: number, halfZ: number): boolean
	local rel = cf:PointToObjectSpace(Vector3.new(pos.X, 0, pos.Z))
	return math.abs(rel.X) <= halfX and math.abs(rel.Z) <= halfZ
end

local function addSplitAC(parent: Folder, wallCF: CFrame, name: string, counter: { count: number })
	Helpers.MakePart(parent, name .. "_Body", Vector3.new(3.8, 1.05, 0.85), wallCF, Color3.fromRGB(242, 244, 246), Enum.Material.SmoothPlastic, false, false, counter)
	Helpers.MakePart(parent, name .. "_Vent", Vector3.new(3.4, 0.16, 0.08), wallCF * CFrame.new(0, -0.36, -0.42), C.DarkSteel, Enum.Material.SmoothPlastic, false, false, counter)
end

local function addOfficeChair(parent: Folder, baseCF: CFrame, seatColor: Color3, counter: { count: number })
	Helpers.MakePart(parent, "ChairPedestal", Vector3.new(1.1, 0.9, 1.1), baseCF * CFrame.new(0, 0.45, 0), C.DarkSteel, Enum.Material.Metal, true, false, counter)
	Helpers.MakePart(parent, "ChairSeat", Vector3.new(1.55, 0.22, 1.55), baseCF * CFrame.new(0, 1.52, 0), seatColor, Enum.Material.Fabric, true, false, counter)
	Helpers.MakePart(parent, "ChairBack", Vector3.new(1.5, 1.5, 0.22), baseCF * CFrame.new(0, 2.32, 0.68), seatColor, Enum.Material.Fabric, true, false, counter)
end

local function addComputerStation(parent: Folder, deskCF: CFrame, counter: { count: number })
	Helpers.MakePart(parent, "MonStand", Vector3.new(0.45, 0.45, 0.35), deskCF * CFrame.new(0, 0.22, -0.55), C.DarkSteel, Enum.Material.Metal, false, false, counter)
	local scr = Helpers.MakePart(parent, "MonScreen", Vector3.new(1.9, 1.15, 0.10), deskCF * CFrame.new(0, 0.95, -0.55), Color3.fromRGB(24, 30, 38), Enum.Material.SmoothPlastic, false, false, counter)
	Helpers.MakePart(parent, "MonGlow", Vector3.new(1.72, 0.96, 0.04), deskCF * CFrame.new(0, 0.95, -0.49), Color3.fromRGB(58, 128, 196), Enum.Material.Neon, false, false, counter)
	scr.CastShadow = false
	Helpers.MakePart(parent, "Keyboard", Vector3.new(1.25, 0.06, 0.42), deskCF * CFrame.new(-0.15, 0.03, 0.18), C.DarkSteel, Enum.Material.SmoothPlastic, false, false, counter)
	Helpers.MakePart(parent, "Mouse", Vector3.new(0.20, 0.06, 0.32), deskCF * CFrame.new(0.68, 0.03, 0.18), C.DarkSteel, Enum.Material.SmoothPlastic, false, false, counter)
end

-- ============================================================================
-- 1) PÁTIOS INTERNOS (Setor 300 Plásticos 085317 + Jardins 100 e 200)
-- ============================================================================
local function buildCourtyards(campusRoot: Instance, geomFolder: Folder, counter: { count: number })
	local props = campusRoot:FindFirstChild("Props")

	-- Substitui bancos em bloco verde genéricos nos 3 jardins por bancos reais + lajotas + borda de canteiro
	for _, cy in ipairs(CampusData.Courtyards) do
		local cyCF = CFrame.new(cy.center.X, 0, cy.center.Z) * CFrame.Angles(0, math.rad(cy.rotDeg), 0)
		local hx, hz = cy.size.X * 0.5, cy.size.Y * 0.5

		if props then
			for _, p in ipairs(props:GetDescendants()) do
				if p:IsA("BasePart") and not p:GetAttribute("RelocatedHidden") and isInRectXZ(p.Position, cyCF, hx, hz) then
					local col = p.Color
					local r, g, b = math.round(col.R * 255), math.round(col.G * 255), math.round(col.B * 255)
					-- Bancos bloco verde (47,158,65) ou bases cinza escuras (42,47,53) de jardim sem ser árvores
					if p.Position.Y <= 2.4 and p.Size.Y <= 2.4 and ((r == 47 and g == 158 and b == 65) or (r == 42 and g == 47 and b == 53)) then
						local benchCF = CFrame.new(p.Position.X, 0.44, p.Position.Z) * CFrame.Angles(0, math.rad(cy.rotDeg), 0)
						hideBaselinePart(p)
						if r == 47 then
							Helpers.CreateWoodenSlatBench(geomFolder, benchCF, 5.8, true, counter)
						end
					end
				end
			end
		end

		-- Trilha de lajotas elevada acima da grama e canteiro central estruturado
		local pathLen = cy.size.X * 0.72
		Helpers.MakePart(geomFolder, cy.id .. "_Walk", Vector3.new(pathLen, 0.42, 6.2), cyCF * CFrame.new(0, 0.23, 0), C_PaverDark, Enum.Material.Concrete, true, false, counter)
		Helpers.MakePart(geomFolder, cy.id .. "_PlanterCurb", Vector3.new(cy.size.X * 0.42, 1.25, cy.size.Y * 0.34), cyCF * CFrame.new(-hx * 0.18, 0.62, hz * 0.15), Color3.fromRGB(168, 170, 166), Enum.Material.Concrete, true, true, counter)
		Helpers.MakePart(geomFolder, cy.id .. "_PlanterSoil", Vector3.new(cy.size.X * 0.42 - 0.8, 1.32, cy.size.Y * 0.34 - 0.8), cyCF * CFrame.new(-hx * 0.18, 0.66, hz * 0.15), Color3.fromRGB(62, 46, 34), Enum.Material.Ground, false, false, counter)

		Helpers.CreateWoodenSlatBench(geomFolder, cyCF * CFrame.new(hx * 0.25, 0.44, -2.0), 6.0, true, counter)
		Helpers.CreateWoodenSlatBench(geomFolder, cyCF * CFrame.new(-hx * 0.22, 0.44, -3.5) * CFrame.Angles(0, math.pi, 0), 6.0, true, counter)
		Helpers.CreatePottedPlant(geomFolder, (cyCF * CFrame.new(hx * 0.35, 0.44, 2.2)).Position, 0.95, counter)
	end

	-- Pátio Interno do Setor 300 — Plásticos (foto 085317)
	-- Localizado entre a passarela norte (z ~ -130), a ligação central e a parede oeste do Lab de Plásticos
	local p300CF = CFrame.new(77.0, 0, -112.0) * CFrame.Angles(0, math.rad(9.0), 0)
	local cols, rows = 9, 12
	local tileS = 2.25
	local startX = -(cols * tileS) * 0.5 + tileS * 0.5
	local startZ = -(rows * tileS) * 0.5 + tileS * 0.5

	-- Sub-base escura elevada de rejunte das lajotas (acima da grama)
	Helpers.MakePart(geomFolder, "Patio300_GroutBase", Vector3.new(cols * tileS + 0.4, 0.34, rows * tileS + 0.4), p300CF * CFrame.new(0, 0.19, 0), Color3.fromRGB(42, 48, 38), Enum.Material.Concrete, true, false, counter)
	for cx = 0, cols - 1 do
		for rz = 0, rows - 1 do
			local alt = ((cx + rz) % 2 == 0)
			local tCol = if alt then C_PaverDark else C_PaverAlt
			Helpers.MakePart(
				geomFolder,
				"Patio300_Paver",
				Vector3.new(tileS - 0.10, 0.08, tileS - 0.10),
				p300CF * CFrame.new(startX + cx * tileS, 0.38, startZ + rz * tileS),
				tCol,
				Enum.Material.Concrete,
				true,
				false,
				counter
			)
		end
	end

	-- Grande canteiro/banco elevado verde-escuro (085317)
	Helpers.MakePart(geomFolder, "Patio300_PlanterBase", Vector3.new(9.6, 0.95, 14.5), p300CF * CFrame.new(-1.0, 0.85, 0.5), C_DarkGreenPlanter, Enum.Material.Concrete, true, true, counter)
	Helpers.MakePart(geomFolder, "Patio300_BenchLedge", Vector3.new(1.85, 1.95, 14.5), p300CF * CFrame.new(3.1, 1.35, 0.5), C_DarkGreenPlanter, Enum.Material.Concrete, true, true, counter)
	Helpers.CreatePottedPlant(geomFolder, (p300CF * CFrame.new(-3.2, 1.32, -5.0)).Position, 0.95, counter)
	Helpers.CreatePottedPlant(geomFolder, (p300CF * CFrame.new(-3.2, 1.32, 6.0)).Position, 0.85, counter)

	-- Parede mural sul/fundo do Pátio 300 com o mural "CURSO TÉCNICO EM PLÁSTICOS" (duas andorinhas + brasão)
	local muralWallCF = p300CF * CFrame.new(0.2, 6.8, 12.6)
	Helpers.MakePart(geomFolder, "Patio300_BackWall", Vector3.new(20.6, 13.4, 0.45), muralWallCF, Color3.fromRGB(224, 214, 198), Enum.Material.SmoothPlastic, true, true, counter)

	local pCanvas = Helpers.MakePart(geomFolder, "Patio300_PlasticsMural", Vector3.new(17.6, 11.4, 0.08), muralWallCF * CFrame.new(0, 0.2, -0.26), Color3.fromRGB(228, 218, 202), Enum.Material.SmoothPlastic, false, false, counter)
	local mGui = newSurfaceGui(pCanvas, Enum.NormalId.Front, 960, 700)

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(228, 218, 200)
	bg.BorderSizePixel = 0
	bg.ZIndex = 1
	bg.Parent = mGui

	-- Brasão tricolor central (referência 085317)
	local shield = Instance.new("Frame")
	shield.Size = UDim2.fromOffset(170, 190)
	shield.Position = UDim2.fromOffset(395, 190)
	shield.BackgroundColor3 = Color3.fromRGB(240, 240, 236)
	shield.BorderSizePixel = 4
	shield.BorderColor3 = Color3.fromRGB(142, 108, 42)
	shield.ZIndex = 2
	shield.Parent = bg

	for idx, stripCol in ipairs({ Color3.fromRGB(168, 36, 44), Color3.fromRGB(240, 240, 236), Color3.fromRGB(36, 56, 108) }) do
		local st = Instance.new("Frame")
		st.Size = UDim2.new(1, 0, 0.33, 0)
		st.Position = UDim2.new(0, 0, (idx - 1) * 0.33, 0)
		st.BackgroundColor3 = stripCol
		st.BorderSizePixel = 0
		st.ZIndex = 3
		st.Parent = shield
	end

	-- Duas andorinhas azuis estilizadas flanqueando o brasão
	for _, birdX in ipairs({ 135, 610 }) do
		local wing = Instance.new("Frame")
		wing.Size = UDim2.fromOffset(165, 80)
		wing.Position = UDim2.fromOffset(birdX + (if birdX < 400 then -35 else 75), 110)
		wing.Rotation = if birdX < 400 then -26 else 26
		wing.BackgroundColor3 = Color3.fromRGB(156, 188, 214)
		wing.BorderSizePixel = 3
		wing.BorderColor3 = Color3.fromRGB(32, 40, 48)
		wing.ZIndex = 2
		local wc = Instance.new("UICorner")
		wc.CornerRadius = UDim.new(0.35, 0)
		wc.Parent = wing
		wing.Parent = bg

		local body = Instance.new("Frame")
		body.Size = UDim2.fromOffset(200, 140)
		body.Position = UDim2.fromOffset(birdX, 200)
		body.BackgroundColor3 = Color3.fromRGB(122, 162, 196)
		body.BorderSizePixel = 3
		body.BorderColor3 = Color3.fromRGB(32, 40, 48)
		body.ZIndex = 3
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0.45, 0)
		bc.Parent = body
		body.Parent = bg
	end

	-- Faixa branca "CURSO TÉCNICO EM PLÁSTICOS"
	local ribbon = Instance.new("TextLabel")
	ribbon.Size = UDim2.fromOffset(580, 96)
	ribbon.Position = UDim2.fromOffset(190, 515)
	ribbon.BackgroundColor3 = Color3.fromRGB(238, 236, 230)
	ribbon.BorderColor3 = Color3.fromRGB(32, 40, 48)
	ribbon.BorderSizePixel = 3
	ribbon.Text = "CURSO TÉCNICO EM\nPLÁSTICOS"
	ribbon.TextColor3 = Color3.fromRGB(28, 32, 36)
	ribbon.Font = Enum.Font.GothamBold
	ribbon.TextSize = 34
	ribbon.ZIndex = 4
	ribbon.Parent = bg

	-- Mural geométrico colorido na parede leste do Pátio 300 (encostado na parede leste)
	local geoWall = Helpers.MakePart(geomFolder, "Patio300_GeometricMural", Vector3.new(0.10, 9.6, 15.0), p300CF * CFrame.new(9.8, 6.2, 0.5), Color3.fromRGB(236, 230, 216), Enum.Material.SmoothPlastic, false, false, counter)
	local gGui = newSurfaceGui(geoWall, Enum.NormalId.Left, 800, 560)

	local gBg = Instance.new("Frame")
	gBg.Size = UDim2.fromScale(1, 1)
	gBg.BackgroundColor3 = Color3.fromRGB(236, 230, 216)
	gBg.BorderSizePixel = 0
	gBg.ZIndex = 1
	gBg.Parent = gGui

	local swoosh = Instance.new("Frame")
	swoosh.Size = UDim2.fromOffset(620, 120)
	swoosh.Position = UDim2.fromOffset(80, 320)
	swoosh.BackgroundColor3 = Color3.fromRGB(116, 206, 218)
	swoosh.BorderSizePixel = 0
	swoosh.ZIndex = 2
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0.5, 0)
	sc.Parent = swoosh
	swoosh.Parent = gBg

	for idx, cSpec in ipairs({
		{ sz = 250, col = Color3.fromRGB(246, 210, 92) },
		{ sz = 185, col = Color3.fromRGB(242, 240, 236) },
		{ sz = 128, col = Color3.fromRGB(36, 46, 78) },
		{ sz = 68, col = Color3.fromRGB(218, 86, 98) },
	}) do
		local ring = Instance.new("Frame")
		ring.Size = UDim2.fromOffset(cSpec.sz, cSpec.sz)
		ring.Position = UDim2.fromOffset(400 - cSpec.sz * 0.5, 240 - cSpec.sz * 0.5)
		ring.BackgroundColor3 = cSpec.col
		ring.BorderSizePixel = 0
		ring.ZIndex = idx + 2
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(1, 0)
		rc.Parent = ring
		ring.Parent = gBg
	end
end

-- ============================================================================
-- 2) MURAIS ICÔNICOS DE CORREDOR (Ipê Rosa 085352 + Acrílico 085358)
-- ============================================================================
local function buildCorridorMurals(interiors: Instance, geomFolder: Folder, counter: { count: number })
	local wallParams = RaycastParams.new()
	wallParams.FilterType = Enum.RaycastFilterType.Include
	wallParams.FilterDescendantsInstances = { interiors }

	-- 2A) Mural Árvore / Ipê Rosa no corredor Setor 300/800 (ao norte da placa Sign_Setor300_800 em z ~ -98.8)
	local hit300 = workspace:Raycast(Vector3.new(131.0, 6.2, -98.8), Vector3.new(-12, 0, 0), wallParams)
	local p300 = if hit300 then (hit300.Position + hit300.Normal * 0.08) else Vector3.new(125.6, 6.2, -98.8)
	local n300 = if hit300 then hit300.Normal else Vector3.new(0.99, 0, -0.16).Unit
	local cf300 = CFrame.lookAt(Vector3.new(p300.X, 7.3, p300.Z), Vector3.new(p300.X, 7.3, p300.Z) + n300)

	local ipePanel = Helpers.MakePart(geomFolder, "Mural_IpeRosa", Vector3.new(8.2, 11.4, 0.08), cf300, Color3.fromRGB(110, 178, 228), Enum.Material.SmoothPlastic, false, false, counter)
	local iGui = newSurfaceGui(ipePanel, Enum.NormalId.Front, 640, 880)

	local sky = Instance.new("Frame")
	sky.Size = UDim2.fromScale(1, 1)
	sky.BackgroundColor3 = Color3.fromRGB(110, 178, 228)
	sky.BorderSizePixel = 0
	sky.ZIndex = 1
	sky.Parent = iGui

	-- Faixa de gramado inferior e nuvens suaves
	local grass = Instance.new("Frame")
	grass.Size = UDim2.new(1, 0, 0.10, 0)
	grass.Position = UDim2.new(0, 0, 0.90, 0)
	grass.BackgroundColor3 = Color3.fromRGB(64, 152, 68)
	grass.BorderSizePixel = 0
	grass.ZIndex = 2
	grass.Parent = sky

	for _, cl in ipairs({ { 55, 65, 145, 55 }, { 430, 85, 150, 50 } }) do
		local cloud = Instance.new("Frame")
		cloud.Position = UDim2.fromOffset(cl[1], cl[2])
		cloud.Size = UDim2.fromOffset(cl[3], cl[4])
		cloud.BackgroundColor3 = Color3.fromRGB(240, 246, 252)
		cloud.BorderSizePixel = 0
		cloud.ZIndex = 2
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(1, 0)
		cc.Parent = cloud
		cloud.Parent = sky
	end

	-- Tronco e galhos marrom escuro do Ipê
	local trunk = Instance.new("Frame")
	trunk.Size = UDim2.fromOffset(96, 430)
	trunk.Position = UDim2.fromOffset(272, 385)
	trunk.BackgroundColor3 = Color3.fromRGB(118, 80, 52)
	trunk.BorderSizePixel = 0
	trunk.ZIndex = 3
	trunk.Parent = sky

	for _, br in ipairs({ { x = 195, y = 315, r = -32 }, { x = 355, y = 315, r = 32 } }) do
		local branch = Instance.new("Frame")
		branch.Size = UDim2.fromOffset(54, 170)
		branch.Position = UDim2.fromOffset(br.x, br.y)
		branch.Rotation = br.r
		branch.BackgroundColor3 = Color3.fromRGB(118, 80, 52)
		branch.BorderSizePixel = 0
		branch.ZIndex = 3
		branch.Parent = sky
	end

	-- Copa florida do Ipê Rosa
	for idx, blob in ipairs({
		{ x = 90, y = 135, w = 230, h = 210, c = Color3.fromRGB(238, 152, 182) },
		{ x = 285, y = 115, w = 245, h = 220, c = Color3.fromRGB(242, 166, 192) },
		{ x = 185, y = 75, w = 250, h = 200, c = Color3.fromRGB(246, 198, 214) },
		{ x = 140, y = 210, w = 180, h = 150, c = Color3.fromRGB(244, 182, 204) },
		{ x = 335, y = 225, w = 180, h = 145, c = Color3.fromRGB(236, 144, 176) },
	}) do
		local cFrame = Instance.new("Frame")
		cFrame.Size = UDim2.fromOffset(blob.w, blob.h)
		cFrame.Position = UDim2.fromOffset(blob.x, blob.y)
		cFrame.BackgroundColor3 = blob.c
		cFrame.BorderSizePixel = 0
		cFrame.ZIndex = 3 + idx
		local cr = Instance.new("UICorner")
		cr.CornerRadius = UDim.new(1, 0)
		cr.Parent = cFrame
		cFrame.Parent = sky
	end

	-- 2B) Mural Acrílico "Cursos Superiores" no corredor Setor 200/230 (parede sólida em z ~ 58.2)
	local hit230 = workspace:Raycast(Vector3.new(131.0, 6.2, 58.2), Vector3.new(14, 0, 0), wallParams)
	local p230 = if hit230 then (hit230.Position + hit230.Normal * 0.08) else Vector3.new(138.3, 6.2, 58.2)
	local n230 = if hit230 then hit230.Normal else Vector3.new(-0.99, 0, 0.15).Unit
	local cf230 = CFrame.lookAt(Vector3.new(p230.X, 6.8, p230.Z), Vector3.new(p230.X, 6.8, p230.Z) + n230)

	local acrW, acrH = 3.8, 4.3
	-- Cartazes internos atrás do acrílico
	local flyerBacking = Helpers.MakePart(geomFolder, "MuralCursos_Flyers", Vector3.new(acrW - 0.3, acrH - 0.4, 0.04), cf230, Color3.fromRGB(242, 244, 242), Enum.Material.SmoothPlastic, false, false, counter)
	local fGui = newSurfaceGui(flyerBacking, Enum.NormalId.Front, 420, 480)

	local hdr = Instance.new("TextLabel")
	hdr.Size = UDim2.new(1, 0, 0, 56)
	hdr.BackgroundTransparency = 1
	hdr.Text = "Cursos Superiores"
	hdr.TextColor3 = C.IFSulGreen
	hdr.Font = Enum.Font.GothamBold
	hdr.TextSize = 30
	hdr.ZIndex = 2
	hdr.Parent = fGui

	local fGrid = {
		{ 24, 70, 170, 110, Color3.fromRGB(242, 198, 66) },
		{ 220, 74, 175, 115, Color3.fromRGB(48, 134, 198) },
		{ 28, 200, 165, 120, Color3.fromRGB(224, 92, 74) },
		{ 218, 206, 172, 118, Color3.fromRGB(64, 168, 92) },
		{ 30, 340, 170, 110, Color3.fromRGB(42, 62, 108) },
		{ 222, 342, 170, 110, Color3.fromRGB(246, 152, 54) },
	}
	for idx, fl in ipairs(fGrid) do
		local card = Instance.new("Frame")
		card.Position = UDim2.fromOffset(fl[1], fl[2])
		card.Size = UDim2.fromOffset(fl[3], fl[4])
		card.BackgroundColor3 = fl[5]
		card.BorderSizePixel = 1
		card.BorderColor3 = Color3.fromRGB(160, 168, 174)
		card.ZIndex = idx + 2
		card.Parent = fGui
	end

	-- Placa acrílica translúcida (SmoothPlastic preserva SurfaceGui atrás ao contrário de Material.Glass)
	local acrGlass = Helpers.MakePart(geomFolder, "MuralCursos_Acrylic", Vector3.new(acrW, acrH, 0.05), cf230 * CFrame.new(0, 0, -0.10), Color3.fromRGB(220, 238, 244), Enum.Material.SmoothPlastic, false, false, counter)
	acrGlass.Transparency = 0.78
	for _, sx in ipairs({ -acrW * 0.5 + 0.22, acrW * 0.5 - 0.22 }) do
		for _, sy in ipairs({ -acrH * 0.5 + 0.22, acrH * 0.5 - 0.22 }) do
			Helpers.MakePart(geomFolder, "MuralCursos_Bolt", Vector3.new(0.14, 0.14, 0.14), cf230 * CFrame.new(sx, sy, -0.06), C.GalvSteel, Enum.Material.Metal, false, false, counter)
		end
	end
end

-- ============================================================================
-- 3) BIBLIOTECA COMPLETA EM 5 ZONAS (0 peças originalmente)
-- ============================================================================
local function buildBookRow(parent: Folder, shelfCF: CFrame, len: number, yBase: number, zOff: number, seed: number, counter: { count: number })
	-- Preenche fileira com grupos variados de livros coloridos para manter contagem enxuta de parts
	local x = -len * 0.5 + 0.45
	local idx = seed
	while x < len * 0.5 - 0.6 do
		idx += 1
		local grpW = 0.55 + ((idx * 37) % 5) * 0.16
		local bkH = 0.76 + ((idx * 19) % 4) * 0.10
		local col = C_BinderColors[(idx % #C_BinderColors) + 1]
		Helpers.MakePart(
			parent,
			"BookBlock",
			Vector3.new(grpW, bkH, 0.68),
			shelfCF * CFrame.new(x + grpW * 0.5, yBase + bkH * 0.5, zOff),
			col,
			Enum.Material.SmoothPlastic,
			false,
			false,
			counter
		)
		x += grpW + 0.14
	end
end

local function buildLibraryShelf(parent: Folder, shelfCF: CFrame, len: number, labelText: string, seed: number, counter: { count: number })
	local h = 7.2
	local depth = 1.9
	-- Uprights e base cinza-aço
	for _, ex in ipairs({ -len * 0.5 + 0.08, 0, len * 0.5 - 0.08 }) do
		Helpers.MakePart(parent, "ShelfPost", Vector3.new(0.16, h, depth), shelfCF * CFrame.new(ex, h * 0.5, 0), C.DarkSteel, Enum.Material.Metal, true, false, counter)
	end
	Helpers.MakePart(parent, "ShelfSpine", Vector3.new(len, h - 0.3, 0.08), shelfCF * CFrame.new(0, h * 0.5, 0), C.PanelGrey, Enum.Material.Metal, true, false, counter)

	for sIdx = 0, 4 do
		local sy = 0.45 + sIdx * 1.45
		Helpers.MakePart(parent, "ShelfBoard", Vector3.new(len, 0.12, depth), shelfCF * CFrame.new(0, sy, 0), C.PanelGrey, Enum.Material.Metal, true, false, counter)
		if sIdx < 4 then
			buildBookRow(parent, shelfCF, len, sy + 0.06, -0.48, seed + sIdx * 7, counter)
			buildBookRow(parent, shelfCF, len, sy + 0.06, 0.48, seed + sIdx * 11 + 3, counter)
		end
	end

	-- Placa identificadora de classificação no topo
	local sign = Helpers.MakePart(parent, "ShelfHeader", Vector3.new(math.min(len - 0.6, 7.6), 0.78, 0.12), shelfCF * CFrame.new(0, h + 0.45, 0), C.IFSulGreen, Enum.Material.SmoothPlastic, false, false, counter)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = newSurfaceGui(sign, face, 460, 64)
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Text = labelText
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 26
		lbl.Parent = sg
	end
end

local function buildBiblioteca(geomFolder: Folder, lightsFolder: Folder, counter: { count: number })
	local rCent = findRoom("biblioteca_central")
	local rNort = findRoom("biblioteca_norte")
	local rSul = findRoom("biblioteca_sul")
	local rLest = findRoom("biblioteca_leste")
	local rOest = findRoom("biblioteca_oeste")
	if not (rCent and rNort and rSul and rLest and rOest) then
		return
	end

	-- 3A) BIB-C: Balcão em L de atendimento, 2 terminais, pórtico antifurto e tapete central
	local cfC = roomCFrame(rCent)
	Helpers.MakePart(geomFolder, "Bib_CenterRug", Vector3.new(20.0, 0.04, 18.0), cfC * CFrame.new(0, 0.17, 0), Color3.fromRGB(48, 56, 62), Enum.Material.Carpet, false, false, counter)

	-- Balcão em L (braço frontal + lateral direito)
	local deskCF = cfC * CFrame.new(0, 0.16, 1.5)
	Helpers.MakePart(geomFolder, "BibDesk_Front", Vector3.new(13.5, 3.45, 2.5), deskCF * CFrame.new(0, 1.72, 0), C.WoodLight, Enum.Material.Wood, true, true, counter)
	Helpers.MakePart(geomFolder, "BibDesk_FrontGreen", Vector3.new(13.2, 2.35, 0.08), deskCF * CFrame.new(0, 1.45, -1.27), C.IFSulGreen, Enum.Material.SmoothPlastic, false, false, counter)
	Helpers.MakePart(geomFolder, "BibDesk_Top", Vector3.new(13.9, 0.18, 2.9), deskCF * CFrame.new(0, 3.52, 0), Color3.fromRGB(228, 230, 226), Enum.Material.SmoothPlastic, true, false, counter)
	Helpers.MakePart(geomFolder, "BibDesk_Side", Vector3.new(2.5, 3.45, 7.5), deskCF * CFrame.new(5.5, 1.72, 4.8), C.WoodLight, Enum.Material.Wood, true, true, counter)
	Helpers.MakePart(geomFolder, "BibDesk_SideTop", Vector3.new(2.9, 0.18, 7.7), deskCF * CFrame.new(5.5, 3.52, 4.8), Color3.fromRGB(228, 230, 226), Enum.Material.SmoothPlastic, true, false, counter)

	local bibSign = Helpers.MakePart(geomFolder, "BibDesk_Sign", Vector3.new(10.0, 0.85, 0.06), deskCF * CFrame.new(0, 1.55, -1.32), Color3.fromRGB(32, 108, 48), Enum.Material.SmoothPlastic, false, false, counter)
	local bsg = newSurfaceGui(bibSign, Enum.NormalId.Front, 640, 64)
	bsg.LightInfluence = 0
	local bLbl = Instance.new("TextLabel")
	bLbl.Size = UDim2.fromScale(1, 1)
	bLbl.BackgroundTransparency = 1
	bLbl.Text = "BIBLIOTECA • ATENDIMENTO E EMPRÉSTIMO"
	bLbl.TextColor3 = Color3.new(1, 1, 1)
	bLbl.Font = Enum.Font.GothamBold
	bLbl.TextScaled = true
	bLbl.Parent = bsg

	for _, dx in ipairs({ -3.4, 2.4 }) do
		addComputerStation(geomFolder, deskCF * CFrame.new(dx, 3.61, 0), counter)
		addOfficeChair(geomFolder, deskCF * CFrame.new(dx, 0, 2.6) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(42, 46, 52), counter)
	end

	-- Pórtico antifurto na passagem norte da Biblioteca (localZ = -14.8)
	for _, gx in ipairs({ -3.8, 0.0, 3.8 }) do
		local gPost = Helpers.MakePart(geomFolder, "Bib_SecurityGate", Vector3.new(0.22, 5.6, 1.45), cfC * CFrame.new(gx, 2.96, -15.2), Color3.fromRGB(190, 222, 232), Enum.Material.Glass, true, false, counter)
		gPost.Transparency = 0.45
		Helpers.MakePart(geomFolder, "Bib_GateBase", Vector3.new(0.45, 0.35, 1.65), cfC * CFrame.new(gx, 0.34, -15.2), C.GalvSteel, Enum.Material.Metal, true, false, counter)
	end

	-- Luminárias suspensas no teto central (~12.0 abaixo da claraboia ~14.6)
	for _, lz in ipairs({ -8.0, 8.0 }) do
		Helpers.CreateSuspendedFluorescent(geomFolder, lightsFolder, cfC * CFrame.new(0, 12.0, lz), 14.5, 2.6, 36, 1.15, 1.85, true, counter)
	end

	-- 3B) BIB-N: Guarda-volumes (oeste), Expositor de Periódicos + 2 terminais OPAC (leste) — corredor central livre
	local cfN = roomCFrame(rNort)
	for idx = 0, 1 do
		local lkCF = cfN * CFrame.new(-10.5, 3.16, -5.5 + idx * 6.8)
		Helpers.MakePart(geomFolder, "Bib_Lockers", Vector3.new(2.0, 6.0, 6.2), lkCF, C.PanelGrey, Enum.Material.Metal, true, true, counter)
		Helpers.MakePart(geomFolder, "Bib_LockerAccent", Vector3.new(0.08, 5.4, 5.8), lkCF * CFrame.new(1.02, 0, 0), Color3.fromRGB(82, 136, 176), Enum.Material.SmoothPlastic, false, false, counter)
	end
	-- Expositor inclinado de revistas/periódicos (leste)
	local magCF = cfN * CFrame.new(10.0, 0.16, -3.5)
	Helpers.MakePart(geomFolder, "Bib_MagRackBase", Vector3.new(2.4, 4.8, 9.2), magCF * CFrame.new(0, 2.4, 0), C.WoodWarm, Enum.Material.Wood, true, true, counter)
	for mRow = 0, 2 do
		Helpers.MakePart(geomFolder, "Bib_MagShelf", Vector3.new(0.65, 0.9, 8.6), magCF * CFrame.new(-0.95, 1.3 + mRow * 1.3, 0) * CFrame.Angles(0, 0, math.rad(14)), Color3.fromRGB(232, 198, 72 + mRow * 40), Enum.Material.SmoothPlastic, false, false, counter)
	end
	-- 2 Totens OPAC
	for _, oz in ipairs({ 4.2, 8.4 }) do
		local oCF = cfN * CFrame.new(9.5, 0.16, oz) * CFrame.Angles(0, math.pi * 0.5, 0)
		Helpers.MakePart(geomFolder, "Bib_OPAC_Post", Vector3.new(1.8, 3.4, 1.4), oCF * CFrame.new(0, 1.7, 0), C.DarkSteel, Enum.Material.Metal, true, false, counter)
		addComputerStation(geomFolder, oCF * CFrame.new(0, 3.4, 0), counter)
	end
	Helpers.CreateSuspendedFluorescent(geomFolder, lightsFolder, cfN * CFrame.new(0, 8.8, 0), 9.8, 1.2, 32, 1.10, 1.75, true, counter)

	-- 3C) BIB-S: Acervo Geral — 6 estantes duplas de aço com livros coloridos e corredor central aberto
	local cfS = roomCFrame(rSul)
	local classifications = {
		"000–009 • INFORMÁTICA",
		"500–540 • QUÍMICA / FÍSICA",
		"620 • ENGENHARIA MECÂNICA",
		"660 • POLÍMEROS / PLÁSTICOS",
		"800 • LITERATURA E ARTES",
		"900 • HISTÓRIA / REFERÊNCIA",
	}
	local sIdx = 0
	for _, sx in ipairs({ -9.2, 9.2 }) do
		for rIdx = 0, 2 do
			sIdx += 1
			local sz = -9.2 + rIdx * 9.2
			buildLibraryShelf(geomFolder, cfS * CFrame.new(sx, 0.16, sz), 9.6, classifications[sIdx], sIdx * 13, counter)
		end
	end
	for _, lz in ipairs({ -6.0, 6.0 }) do
		Helpers.CreateSuspendedFluorescent(geomFolder, lightsFolder, cfS * CFrame.new(0, 8.8, lz), 9.8, 1.2, 34, 1.10, 1.75, true, counter)
	end

	-- 3D) BIB-L: Salão de Leitura — 4 grandes mesas com luminária central e cadeiras ergonômicas
	local cfL = roomCFrame(rLest)
	for _, tx in ipairs({ -6.2, 6.2 }) do
		for _, tz in ipairs({ -5.8, 5.8 }) do
			local tCF = cfL * CFrame.new(tx, 0.16, tz)
			Helpers.MakePart(geomFolder, "Bib_ReadTop", Vector3.new(7.4, 0.22, 4.4), tCF * CFrame.new(0, 2.65, 0), C.WoodLight, Enum.Material.Wood, true, true, counter)
			for _, lx in ipairs({ -3.1, 3.1 }) do
				for _, lz in ipairs({ -1.7, 1.7 }) do
					Helpers.MakePart(geomFolder, "Bib_ReadLeg", Vector3.new(0.24, 2.55, 0.24), tCF * CFrame.new(lx, 1.28, lz), C.DarkSteel, Enum.Material.Metal, true, false, counter)
				end
			end
			-- Luminária de leitura central
			Helpers.MakePart(geomFolder, "Bib_DeskLampBar", Vector3.new(3.6, 0.22, 0.36), tCF * CFrame.new(0, 3.55, 0), C.DarkSteel, Enum.Material.Metal, false, false, counter)
			Helpers.MakePart(geomFolder, "Bib_DeskLampGlow", Vector3.new(3.3, 0.08, 0.22), tCF * CFrame.new(0, 3.42, 0), C.LampCoolWhite, Enum.Material.Neon, false, false, counter)
			for _, cx in ipairs({ -1.8, 1.8 }) do
				addOfficeChair(geomFolder, tCF * CFrame.new(cx, 0, -2.5) * CFrame.Angles(0, math.pi, 0), C_SeatUpholstery, counter)
				addOfficeChair(geomFolder, tCF * CFrame.new(cx, 0, 2.5), C_SeatUpholstery, counter)
			end
		end
	end
	Helpers.CreateSuspendedFluorescent(geomFolder, lightsFolder, cfL * CFrame.new(0, 8.8, 0) * CFrame.Angles(0, math.pi * 0.5, 0), 9.8, 1.2, 34, 1.15, 1.80, true, counter)

	-- 3E) BIB-O: Cabines individuais de estudo (Norte) + Infanteca colorida (Sul)
	local cfO = roomCFrame(rOest)
	for _, cx in ipairs({ -8.2, -2.6, 3.0, 8.6 }) do
		local cCF = cfO * CFrame.new(cx, 0.16, -7.8)
		Helpers.MakePart(geomFolder, "Bib_BoothBack", Vector3.new(4.8, 4.6, 0.18), cCF * CFrame.new(0, 2.3, -1.6), C.WoodWarm, Enum.Material.Wood, true, false, counter)
		Helpers.MakePart(geomFolder, "Bib_BoothSideL", Vector3.new(0.18, 4.6, 3.2), cCF * CFrame.new(-2.4, 2.3, 0), C.WoodWarm, Enum.Material.Wood, true, false, counter)
		Helpers.MakePart(geomFolder, "Bib_BoothSideR", Vector3.new(0.18, 4.6, 3.2), cCF * CFrame.new(2.4, 2.3, 0), C.WoodWarm, Enum.Material.Wood, true, false, counter)
		Helpers.MakePart(geomFolder, "Bib_BoothDesk", Vector3.new(4.6, 0.18, 2.4), cCF * CFrame.new(0, 2.58, -0.35), C.WoodLight, Enum.Material.Wood, true, false, counter)
		addOfficeChair(geomFolder, cCF * CFrame.new(0, 0, 1.3), Color3.fromRGB(48, 52, 58), counter)
	end

	-- Infanteca (área Sul da BIB-O)
	local infCF = cfO * CFrame.new(0, 0.16, 6.2)
	local matCols = { Color3.fromRGB(48, 148, 68), Color3.fromRGB(238, 188, 56), Color3.fromRGB(52, 128, 198), Color3.fromRGB(218, 72, 68) }
	for m = 0, 3 do
		local mx = (m % 2 - 0.5) * 6.8
		local mz = (math.floor(m / 2) - 0.5) * 5.2
		Helpers.MakePart(geomFolder, "Bib_KidsMat", Vector3.new(6.6, 0.08, 5.0), infCF * CFrame.new(mx, 0.04, mz), matCols[m + 1], Enum.Material.Carpet, true, false, counter)
	end
	for p = 1, 3 do
		Helpers.MakePart(geomFolder, "Bib_Pouf", Vector3.new(2.2, 1.15, 2.2), infCF * CFrame.new(-5.2 + (p - 1) * 4.8, 0.62, 1.6), matCols[(p % 4) + 1], Enum.Material.Fabric, true, false, counter)
	end
	Helpers.MakePart(geomFolder, "Bib_KidsShelf", Vector3.new(11.0, 3.6, 1.4), infCF * CFrame.new(0, 1.8, 6.2), Color3.fromRGB(56, 142, 196), Enum.Material.SmoothPlastic, true, true, counter)
	buildBookRow(geomFolder, infCF * CFrame.new(0, 1.85, 6.2), 10.4, 0, -0.3, 91, counter)
	Helpers.CreateSuspendedFluorescent(geomFolder, lightsFolder, cfO * CFrame.new(0, 8.8, 0) * CFrame.Angles(0, math.pi * 0.5, 0), 9.8, 1.2, 34, 1.15, 1.80, true, counter)
end

-- ============================================================================
-- 4) AUDITÓRIO 504 (PEDRO KAIZER) & MINIAUDITÓRIO 201
-- ============================================================================
local function buildAuditoriums(interiors: Instance, geomFolder: Folder, lightsFolder: Folder, counter: { count: number })
	-- 4A) Auditório 504 (palco ao Norte localZ ~ -17.5, plateia ao Sul voltada para o palco)
	local aud = findRoom("auditorio_504")
	if aud then
		local cfA = roomCFrame(aud)
		local hx, hz = aud.size.X * 0.5, aud.size.Y * 0.5

		-- Oculta todas as poltronas antigas (vermelhas, escuras e verdes), tela preta simples e luminárias antigas
		for _, p in ipairs(interiors:GetDescendants()) do
			if p:IsA("BasePart") and not p:GetAttribute("RelocatedHidden") and isInRectXZ(p.Position, cfA, hx - 1.5, hz - 1.5) then
				local col = p.Color
				local r, g, b = math.round(col.R * 255), math.round(col.G * 255), math.round(col.B * 255)
				local isOldSeat = p.Position.Y >= 0.4 and p.Position.Y <= 3.8 and p.Size.Y <= 3.5
				local isOldScreen = p.Position.Y >= 5.0 and p.Position.Y <= 13.5 and math.min(p.Size.X, p.Size.Z) <= 0.4 and p.Size.X >= 15.0 and (r == 26 and g == 30 and b == 36)
				local isOldLamp = p.Position.Y >= 17.5 and p.Size.Y <= 0.4 and r == 255 and g == 255 and b == 255
				if isOldSeat or isOldScreen or isOldLamp then
					hideBaselinePart(p)
				end
			end
		end

		-- Palco elevado em madeira na extremidade Norte (localZ = -17.0)
		local stageCF = cfA * CFrame.new(0, 0.16, -17.2)
		Helpers.MakePart(geomFolder, "Aud_StageDeck", Vector3.new(38.0, 2.75, 11.5), stageCF * CFrame.new(0, 1.38, 0), C_StageWood, Enum.Material.Wood, true, true, counter)
		Helpers.MakePart(geomFolder, "Aud_StageSkirt", Vector3.new(38.0, 2.55, 0.25), stageCF * CFrame.new(0, 1.28, 5.75), C.DarkSteel, Enum.Material.SmoothPlastic, true, false, counter)
		for _, sideX in ipairs({ -20.5, 20.5 }) do
			for step = 0, 2 do
				Helpers.MakePart(geomFolder, "Aud_StageStep", Vector3.new(3.2, 0.88, 3.6 - step * 1.0), stageCF * CFrame.new(sideX, 0.44 + step * 0.88, 2.5 - step * 0.5), C_StageWood, Enum.Material.Wood, true, false, counter)
			end
		end

		-- Telão de projeção amplo na parede Norte + texto institucional (SmoothPlastic sem estourar bloom Neon)
		local screenPart = Helpers.MakePart(geomFolder, "Aud_ScreenFrame", Vector3.new(25.5, 10.6, 0.35), stageCF * CFrame.new(0, 9.2, -5.2), Color3.fromRGB(26, 30, 36), Enum.Material.SmoothPlastic, false, false, counter)
		local screenFace = Helpers.MakePart(geomFolder, "Aud_ScreenSurface", Vector3.new(24.0, 9.4, 0.10), stageCF * CFrame.new(0, 9.2, -4.98), Color3.fromRGB(24, 56, 38), Enum.Material.SmoothPlastic, false, false, counter)
		screenFace.CastShadow = false
		local sGui = newSurfaceGui(screenFace, Enum.NormalId.Back, 960, 380)
		sGui.LightInfluence = 0
		local sTxt = Instance.new("TextLabel")
		sTxt.Size = UDim2.fromScale(1, 1)
		sTxt.BackgroundColor3 = Color3.fromRGB(24, 58, 38)
		sTxt.Text = "AUDITÓRIO PEDRO KAIZER\nIFSul — Câmpus Sapucaia do Sul"
		sTxt.TextColor3 = Color3.fromRGB(244, 248, 245)
		sTxt.Font = Enum.Font.GothamBold
		sTxt.TextSize = 54
		sTxt.ZIndex = 2
		sTxt.Parent = sGui
		screenPart.CastShadow = false

		-- Mesa de autoridades + 4 poltronas + microfones
		local authCF = stageCF * CFrame.new(-3.0, 2.75, 1.2)
		Helpers.MakePart(geomFolder, "Aud_AuthTable", Vector3.new(13.5, 2.5, 2.4), authCF * CFrame.new(0, 1.25, 0), C.WoodLight, Enum.Material.Wood, true, true, counter)
		Helpers.MakePart(geomFolder, "Aud_AuthModesty", Vector3.new(13.1, 2.1, 0.12), authCF * CFrame.new(0, 1.1, 1.22), C.IFSulGreen, Enum.Material.SmoothPlastic, false, false, counter)
		for _, ax in ipairs({ -4.8, -1.6, 1.6, 4.8 }) do
			addOfficeChair(geomFolder, authCF * CFrame.new(ax, 0, -1.8) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(36, 40, 46), counter)
			Helpers.MakePart(geomFolder, "Aud_Mic", Vector3.new(0.12, 0.65, 0.12), authCF * CFrame.new(ax, 2.82, 0.4), C.DarkSteel, Enum.Material.Metal, false, false, counter)
		end

		-- Púlpito institucional à direita do palco (para quem olha da plateia)
		local pulCF = stageCF * CFrame.new(11.5, 2.75, 2.6)
		Helpers.MakePart(geomFolder, "Aud_LecternBody", Vector3.new(2.8, 3.6, 2.0), pulCF * CFrame.new(0, 1.8, 0), C.WoodWarm, Enum.Material.Wood, true, true, counter)
		Helpers.MakePart(geomFolder, "Aud_LecternBadge", Vector3.new(2.2, 2.2, 0.08), pulCF * CFrame.new(0, 2.1, 1.02), C.IFSulGreen, Enum.Material.SmoothPlastic, false, false, counter)
		Helpers.MakePart(geomFolder, "Aud_LecternTop", Vector3.new(3.1, 0.18, 2.2), pulCF * CFrame.new(0, 3.65, 0) * CFrame.Angles(math.rad(-12), 0, 0), C.WoodLight, Enum.Material.Wood, true, false, counter)

		-- Painéis acústicos ripados em madeira nas paredes Leste e Oeste
		for _, sideSign in ipairs({ -1, 1 }) do
			local xWall = sideSign * (hx - 0.65)
			for pIdx = 0, 6 do
				local pz = -12.0 + pIdx * 5.2
				Helpers.MakePart(geomFolder, "Aud_AcousticPanel", Vector3.new(0.28, 10.5, 3.4), cfA * CFrame.new(xWall, 7.6, pz), C_AcousticWood, Enum.Material.Wood, false, false, counter)
			end
			addSplitAC(geomFolder, cfA * CFrame.new(sideSign * (hx - 0.8), 14.5, 0) * CFrame.Angles(0, sideSign * math.pi * 0.5, 0), "Aud_AC", counter)
		end

		-- Corredor central destacado e 7 fileiras x 2 alas x 5 poltronas = 70 poltronas confortáveis
		Helpers.MakePart(geomFolder, "Aud_CenterCarpet", Vector3.new(5.6, 0.06, 29.0), cfA * CFrame.new(0, 0.19, 6.2), C_CarpetGreen, Enum.Material.Carpet, false, false, counter)
		for row = 0, 6 do
			local rz = -6.5 + row * 4.1
			for _, wing in ipairs({ -1, 1 }) do
				for seat = 0, 4 do
					local sx = wing * (4.4 + seat * 3.0)
					local scf = cfA * CFrame.new(sx, 0.16, rz) -- frente = LookVector (-Z) apontando para o palco Norte!
					Helpers.MakePart(geomFolder, "Aud_SeatCushion", Vector3.new(1.85, 0.85, 1.65), scf * CFrame.new(0, 0.68, 0), C.DarkSteel, Enum.Material.Metal, true, false, counter)
					Helpers.MakePart(geomFolder, "Aud_SeatTop", Vector3.new(1.78, 0.30, 1.55), scf * CFrame.new(0, 1.18, 0), C_SeatUpholstery, Enum.Material.Fabric, true, false, counter)
					Helpers.MakePart(geomFolder, "Aud_SeatBack", Vector3.new(1.78, 1.65, 0.28), scf * CFrame.new(0, 2.05, 0.68), C_SeatUpholstery, Enum.Material.Fabric, true, false, counter)
				end
			end
		end

		-- Luminárias lineares suspensas (AlwaysOn)
		for _, lx in ipairs({ -11.0, 11.0 }) do
			for _, lz in ipairs({ -6.0, 9.0 }) do
				Helpers.CreateSuspendedFluorescent(geomFolder, lightsFolder, cfA * CFrame.new(lx, 16.5, lz), 12.0, 2.8, 42, 1.25, 2.0, true, counter)
			end
		end
	end

	-- 4B) Miniauditório 201 (porta Norte, telão na parede Sul localZ ~ +8.2)
	local mini = findRoom("sala_201")
	if mini then
		local cfM = roomCFrame(mini)
		local hx, hz = mini.size.X * 0.5, mini.size.Y * 0.5

		for _, p in ipairs(interiors:GetDescendants()) do
			if p:IsA("BasePart") and not p:GetAttribute("RelocatedHidden") and isInRectXZ(p.Position, cfM, hx - 0.4, hz - 0.4) then
				local col = p.Color
				local r, g, b = math.round(col.R * 255), math.round(col.G * 255), math.round(col.B * 255)
				local isOldChair = p.Position.Y >= 0.4 and p.Position.Y <= 3.2 and ((r == 42 and g == 122 and b == 58) or (r == 35 and g == 39 and b == 45))
				local isOldScreen = p.Position.Y >= 5.0 and p.Position.Y <= 12.0 and math.min(p.Size.X, p.Size.Z) <= 0.3 and p.Size.X >= 10.0 and (r == 26 and g == 30 and b == 36)
				if isOldChair or isOldScreen then
					hideBaselinePart(p)
				end
			end
		end

		-- Estrado baixo + telão Sul + mesa do palestrante (olhando para Norte)
		local pCF = cfM * CFrame.new(0, 0.16, 6.4)
		Helpers.MakePart(geomFolder, "Mini_Dais", Vector3.new(16.5, 0.48, 4.2), pCF * CFrame.new(0, 0.24, 0.4), C_StageWood, Enum.Material.Wood, true, true, counter)
		Helpers.MakePart(geomFolder, "Mini_ScreenFrame", Vector3.new(12.8, 6.8, 0.22), cfM * CFrame.new(0, 7.6, hz - 0.8), Color3.fromRGB(26, 30, 36), Enum.Material.SmoothPlastic, false, false, counter)
		local scr = Helpers.MakePart(geomFolder, "Mini_Screen", Vector3.new(12.2, 6.2, 0.12), cfM * CFrame.new(0, 7.6, hz - 0.92), Color3.fromRGB(24, 56, 38), Enum.Material.SmoothPlastic, false, false, counter)
		scr.CastShadow = false
		local mSg = newSurfaceGui(scr, Enum.NormalId.Front, 640, 320)
		mSg.LightInfluence = 0
		local mTxt = Instance.new("TextLabel")
		mTxt.Size = UDim2.fromScale(1, 1)
		mTxt.BackgroundColor3 = Color3.fromRGB(24, 58, 38)
		mTxt.Text = "MINIAUDITÓRIO 201\nIFSul — Câmpus Sapucaia do Sul"
		mTxt.TextColor3 = Color3.fromRGB(244, 248, 245)
		mTxt.Font = Enum.Font.GothamBold
		mTxt.TextSize = 36
		mTxt.ZIndex = 2
		mTxt.Parent = mSg
		Helpers.MakePart(geomFolder, "Mini_PresenterDesk", Vector3.new(6.8, 2.35, 2.0), pCF * CFrame.new(-1.5, 1.65, -0.4), C.WoodLight, Enum.Material.Wood, true, true, counter)
		addComputerStation(geomFolder, pCF * CFrame.new(-1.5, 2.84, -0.4) * CFrame.Angles(0, math.pi, 0), counter)
		addOfficeChair(geomFolder, pCF * CFrame.new(-1.5, 0.48, 1.1), Color3.fromRGB(40, 44, 50), counter)

		-- Ar-condicionado split na parede Oeste
		addSplitAC(geomFolder, cfM * CFrame.new(-hx + 0.8, 10.6, 0) * CFrame.Angles(0, -math.pi * 0.5, 0), "Mini_AC", counter)

		-- 3 fileiras x 2 alas x 3 poltronas = 18 cadeiras (frente = +Z olhando para o telão Sul!)
		for row = 0, 2 do
			local rz = -3.8 + row * 2.7
			for _, wing in ipairs({ -1, 1 }) do
				for seat = 0, 2 do
					local sx = wing * (2.6 + seat * 2.3)
					local scf = cfM * CFrame.new(sx, 0.16, rz) * CFrame.Angles(0, math.pi, 0)
					Helpers.MakePart(geomFolder, "Mini_Seat", Vector3.new(1.55, 1.15, 1.45), scf * CFrame.new(0, 0.65, 0), C_SeatUpholstery, Enum.Material.Fabric, true, false, counter)
					Helpers.MakePart(geomFolder, "Mini_Back", Vector3.new(1.55, 1.45, 0.24), scf * CFrame.new(0, 1.85, 0.60), C_SeatUpholstery, Enum.Material.Fabric, true, false, counter)
				end
			end
		end

		Helpers.CreateSuspendedFluorescent(geomFolder, lightsFolder, cfM * CFrame.new(0, 11.4, -1.0) * CFrame.Angles(0, math.pi * 0.5, 0), 12.0, 1.5, 34, 1.15, 1.85, true, counter)
	end
end

function InteriorLandmarks.Apply(campusRoot: Instance, geomFolder: Folder, lightsFolder: Folder, counter: { count: number })
	local interiors = campusRoot:WaitForChild("Interiors")

	local function runSub(name: string, fn: (Folder) -> ())
		local sub = Instance.new("Folder")
		sub.Name = name
		fn(sub)
		sub.Parent = geomFolder
		task.wait()
	end

	runSub("Courtyards", function(f)
		buildCourtyards(campusRoot, f, counter)
	end)
	runSub("CorridorMurals", function(f)
		buildCorridorMurals(interiors, f, counter)
	end)
	runSub("Biblioteca", function(f)
		buildBiblioteca(f, lightsFolder, counter)
	end)
	runSub("Auditoriums", function(f)
		buildAuditoriums(interiors, f, lightsFolder, counter)
	end)
end

return InteriorLandmarks
