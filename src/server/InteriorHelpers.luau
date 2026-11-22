--!strict
-- Utilitários compartilhados, paleta institucional e construtores de mobiliário/sinalização
-- reutilizáveis pelos módulos de detalhamento interno do IFSul — Câmpus Sapucaia do Sul.

local InteriorHelpers = {}

InteriorHelpers.Colors = {
	FloorGraphite = Color3.fromRGB(64, 67, 71),
	FloorTileDark = Color3.fromRGB(54, 57, 61),
	FloorTileLight = Color3.fromRGB(76, 79, 84),
	FloorJoint = Color3.fromRGB(38, 41, 45),
	WallWhite = Color3.fromRGB(232, 234, 231),
	BaseboardGrey = Color3.fromRGB(104, 108, 112),
	ConcreteBeam = Color3.fromRGB(196, 198, 194),
	IFSulGreen = Color3.fromRGB(47, 158, 65),
	CorridorGreenDado = Color3.fromRGB(48, 148, 68),
	HallLimeBand = Color3.fromRGB(128, 184, 86),
	IFSulRed = Color3.fromRGB(205, 28, 32),
	FirePipeRed = Color3.fromRGB(198, 28, 28),
	GalvSteel = Color3.fromRGB(142, 148, 154),
	DarkSteel = Color3.fromRGB(36, 40, 44),
	PanelGrey = Color3.fromRGB(124, 130, 136),
	WoodWarm = Color3.fromRGB(172, 118, 68),
	WoodLight = Color3.fromRGB(206, 174, 128),
	ChalkboardGreen = Color3.fromRGB(36, 86, 56),
	ChalkboardFrame = Color3.fromRGB(42, 94, 168),
	CorkBoard = Color3.fromRGB(184, 146, 98),
	GlassTint = Color3.fromRGB(196, 224, 232),
	LampCoolWhite = Color3.fromRGB(246, 250, 255),
	LampWarmPoint = Color3.fromRGB(248, 250, 255),
	SignWhite = Color3.fromRGB(240, 242, 240),
	SignRowBg = Color3.fromRGB(228, 231, 233),
	SignInk = Color3.fromRGB(28, 32, 34),
}

local function registerPart(p: BasePart, counter: { count: number }?)
	if counter then
		counter.count += 1
		if counter.count % 450 == 0 then
			task.wait()
		end
	end
end

function InteriorHelpers.MakePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	canCollide: boolean?,
	castShadow: boolean?,
	counter: { count: number }?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	local collide = if canCollide ~= nil then canCollide else true
	p.CanCollide = collide
	p.CanTouch = false
	if not collide then
		p.CanQuery = false
	end
	p.CastShadow = if castShadow ~= nil then castShadow else false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	registerPart(p, counter)
	return p
end

function InteriorHelpers.MakeSegmentCylinder(
	parent: Instance,
	name: string,
	p0: Vector3,
	p1: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	canCollide: boolean?,
	counter: { count: number }?
): Part?
	local delta = p1 - p0
	local len = delta.Magnitude
	if len < 0.03 then
		return nil
	end
	local xAxis = delta.Unit
	local ref = if math.abs(xAxis.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis
	local zAxis = xAxis:Cross(ref).Unit
	local yAxis = zAxis:Cross(xAxis).Unit
	local cf = CFrame.fromMatrix((p0 + p1) * 0.5, xAxis, yAxis, zAxis)

	local p = InteriorHelpers.MakePart(
		parent,
		name,
		Vector3.new(len, diameter, diameter),
		cf,
		color,
		material,
		canCollide,
		false,
		counter
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function InteriorHelpers.MakeFacingBox(
	parent: Instance,
	name: string,
	pos: Vector3,
	outwardDir: Vector3,
	w: number,
	h: number,
	depth: number,
	color: Color3,
	material: Enum.Material?,
	canCollide: boolean?,
	counter: { count: number }?
): Part
	local dir = Vector3.new(outwardDir.X, 0, outwardDir.Z)
	if dir.Magnitude < 0.01 then
		dir = Vector3.zAxis
	else
		dir = dir.Unit
	end
	local cf = CFrame.lookAt(pos, pos + dir)
	return InteriorHelpers.MakePart(parent, name, Vector3.new(w, h, depth), cf, color, material, canCollide, false, counter)
end

function InteriorHelpers.MakeSurfaceGui(parent: BasePart, pxPerStud: number, face: Enum.NormalId?): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pxPerStud
	sg.LightInfluence = 0.2
	sg.Parent = parent
	return sg
end

function InteriorHelpers.PopulateIfsulGridLogo(container: Frame)
	local layout = {
		{ 1, 1, true },
		{ 2, 1, false },
		{ 3, 1, false },
		{ 1, 2, false },
		{ 2, 2, false },
		{ 1, 3, false },
		{ 2, 3, false },
		{ 3, 3, false },
		{ 1, 4, false },
		{ 2, 4, false },
	}
	for _, cell in ipairs(layout) do
		local c = cell[1] :: number
		local r = cell[2] :: number
		local isRed = cell[3] :: boolean
		local dot = Instance.new("Frame")
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = if isRed then InteriorHelpers.Colors.IFSulRed else Color3.new(1, 1, 1)
		dot.Size = UDim2.fromScale(0.27, 0.20)
		dot.Position = UDim2.fromScale((c - 1) * 0.34, (r - 1) * 0.255)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if isRed then UDim.new(1, 0) else UDim.new(0.18, 0)
		corner.Parent = dot
		dot.Parent = container
	end
end

export type SignRow = {
	arrow: string,
	label: string,
}

-- Constrói placa direcional oficial de parede (cabeçalho verde IFSul + linhas cinza com círculos vermelhos)
function InteriorHelpers.CreateOfficialWallSign(
	parent: Instance,
	name: string,
	pos: Vector3,
	outwardDir: Vector3,
	w: number,
	h: number,
	rows: { SignRow },
	counter: { count: number }?
): Part
	local plate = InteriorHelpers.MakeFacingBox(
		parent,
		name,
		pos,
		outwardDir,
		w,
		h,
		0.10,
		InteriorHelpers.Colors.SignWhite,
		Enum.Material.SmoothPlastic,
		false,
		counter
	)
	local sg = InteriorHelpers.MakeSurfaceGui(plate, 52)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = InteriorHelpers.Colors.SignRowBg
	bg.BorderSizePixel = 0
	bg.Parent = sg

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(170, 175, 178)
	stroke.Thickness = 2
	stroke.Parent = bg

	local headerH = 0.21
	local header = Instance.new("Frame")
	header.Size = UDim2.fromScale(1, headerH)
	header.BackgroundColor3 = InteriorHelpers.Colors.IFSulGreen
	header.BorderSizePixel = 0
	header.Parent = bg

	local logoBox = Instance.new("Frame")
	logoBox.BackgroundTransparency = 1
	logoBox.Position = UDim2.fromScale(0.03, 0.12)
	logoBox.Size = UDim2.fromScale(0.11, 0.76)
	logoBox.Parent = header
	InteriorHelpers.PopulateIfsulGridLogo(logoBox)

	local h1 = Instance.new("TextLabel")
	h1.BackgroundTransparency = 1
	h1.Position = UDim2.fromScale(0.16, 0.08)
	h1.Size = UDim2.fromScale(0.81, 0.38)
	h1.Font = Enum.Font.GothamBold
	h1.Text = "INSTITUTO FEDERAL"
	h1.TextColor3 = Color3.new(1, 1, 1)
	h1.TextScaled = true
	h1.TextXAlignment = Enum.TextXAlignment.Left
	h1.Parent = header

	local h2 = Instance.new("TextLabel")
	h2.BackgroundTransparency = 1
	h2.Position = UDim2.fromScale(0.16, 0.46)
	h2.Size = UDim2.fromScale(0.81, 0.44)
	h2.Font = Enum.Font.Gotham
	h2.Text = "Sul-rio-grandense • Câmpus Sapucaia do Sul"
	h2.TextColor3 = Color3.fromRGB(235, 248, 238)
	h2.TextScaled = true
	h2.TextXAlignment = Enum.TextXAlignment.Left
	h2.Parent = header

	local n = math.max(1, #rows)
	local bodyH = (1 - headerH) / n
	for idx, row in ipairs(rows) do
		local yTop = headerH + (idx - 1) * bodyH
		local rowFrame = Instance.new("Frame")
		rowFrame.Position = UDim2.fromScale(0, yTop)
		rowFrame.Size = UDim2.fromScale(1, bodyH)
		rowFrame.BackgroundColor3 = if idx % 2 == 1 then Color3.fromRGB(235, 237, 239) else Color3.fromRGB(222, 226, 229)
		rowFrame.BorderSizePixel = 0
		rowFrame.Parent = bg

		local sep = Instance.new("Frame")
		sep.Position = UDim2.fromScale(0.03, 0.96)
		sep.Size = UDim2.fromScale(0.94, 0.04)
		sep.BackgroundColor3 = Color3.fromRGB(185, 190, 194)
		sep.BorderSizePixel = 0
		sep.Parent = rowFrame

		local badge = Instance.new("TextLabel")
		badge.Position = UDim2.fromScale(0.04, 0.14)
		badge.Size = UDim2.fromScale(0.11, 0.72)
		badge.BackgroundColor3 = InteriorHelpers.Colors.IFSulRed
		badge.Font = Enum.Font.GothamBold
		badge.Text = row.arrow
		badge.TextColor3 = Color3.new(1, 1, 1)
		badge.TextScaled = true
		badge.Parent = rowFrame
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(1, 0)
		bc.Parent = badge

		local lbl = Instance.new("TextLabel")
		lbl.Position = UDim2.fromScale(0.18, 0.12)
		lbl.Size = UDim2.fromScale(0.79, 0.76)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.Text = row.label
		lbl.TextColor3 = InteriorHelpers.Colors.SignInk
		lbl.TextScaled = true
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = rowFrame
	end

	return plate
end

-- Luminária linear dupla suspensa (calha metálica + 2 tubos Neon + PointLight AlwaysOn)
function InteriorHelpers.CreateSuspendedFluorescent(
	geomParent: Instance,
	lightsParent: Instance,
	cf: CFrame,
	lengthStuds: number,
	ceilDropStuds: number,
	lightRange: number,
	dayBright: number,
	nightBright: number,
	addPointLight: boolean,
	counter: { count: number }?
)
	InteriorHelpers.MakePart(
		geomParent,
		"LampHood",
		Vector3.new(0.78, 0.16, lengthStuds),
		cf,
		InteriorHelpers.Colors.GalvSteel,
		Enum.Material.Metal,
		false,
		false,
		counter
	)
	for _, dx in ipairs({ -0.18, 0.18 }) do
		InteriorHelpers.MakePart(
			geomParent,
			"LampTube",
			Vector3.new(0.16, 0.12, lengthStuds - 0.3),
			cf * CFrame.new(dx, -0.11, 0),
			InteriorHelpers.Colors.LampCoolWhite,
			Enum.Material.Neon,
			false,
			false,
			counter
		)
	end
	if ceilDropStuds > 0.3 then
		for _, dz in ipairs({ -lengthStuds * 0.35, lengthStuds * 0.35 }) do
			InteriorHelpers.MakePart(
				geomParent,
				"LampRod",
				Vector3.new(0.06, ceilDropStuds, 0.06),
				cf * CFrame.new(0, ceilDropStuds * 0.5 + 0.08, dz),
				InteriorHelpers.Colors.GalvSteel,
				Enum.Material.Metal,
				false,
				false,
				counter
			)
		end
	end

	if addPointLight then
		local lp = InteriorHelpers.MakePart(
			lightsParent,
			"InteriorCeilingLight",
			Vector3.new(0.4, 0.4, 0.4),
			cf * CFrame.new(0, -0.6, 0),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			false,
			false,
			counter
		)
		lp.Transparency = 1
		local pl = Instance.new("PointLight")
		pl.Color = InteriorHelpers.Colors.LampWarmPoint
		pl.Range = lightRange
		pl.Brightness = dayBright
		pl.Shadows = false
		pl.Enabled = true
		pl:SetAttribute("AlwaysOn", true)
		pl:SetAttribute("DayBrightness", dayBright)
		pl:SetAttribute("NightBrightness", nightBright)
		pl.Parent = lp
	end
end

-- Banco de ripas de madeira com pés metálicos pretos (085053, 085352)
function InteriorHelpers.CreateWoodenSlatBench(
	parent: Instance,
	baseCF: CFrame,
	lengthStuds: number,
	withBackrest: boolean,
	counter: { count: number }?
)
	local depth = 1.65
	local seatY = 1.52
	for _, dz in ipairs({ -0.45, 0, 0.45 }) do
		InteriorHelpers.MakePart(
			parent,
			"BenchSlat",
			Vector3.new(lengthStuds, 0.14, 0.36),
			baseCF * CFrame.new(0, seatY, dz),
			InteriorHelpers.Colors.WoodWarm,
			Enum.Material.Wood,
			true,
			false,
			counter
		)
	end
	if withBackrest then
		for _, dy in ipairs({ 2.15, 2.65 }) do
			InteriorHelpers.MakePart(
				parent,
				"BenchBackSlat",
				Vector3.new(lengthStuds, 0.34, 0.14),
				baseCF * CFrame.new(0, dy, depth * 0.42),
				InteriorHelpers.Colors.WoodWarm,
				Enum.Material.Wood,
				true,
				false,
				counter
			)
		end
	end
	for _, dx in ipairs({ -lengthStuds * 0.38, lengthStuds * 0.38 }) do
		InteriorHelpers.MakePart(
			parent,
			"BenchLeg",
			Vector3.new(0.18, seatY, depth * 0.86),
			baseCF * CFrame.new(dx, seatY * 0.5, 0),
			InteriorHelpers.Colors.DarkSteel,
			Enum.Material.Metal,
			true,
			false,
			counter
		)
		if withBackrest then
			InteriorHelpers.MakePart(
				parent,
				"BenchBackPost",
				Vector3.new(0.16, 1.45, 0.16),
				baseCF * CFrame.new(dx, seatY + 0.65, depth * 0.44),
				InteriorHelpers.Colors.DarkSteel,
				Enum.Material.Metal,
				false,
				false,
				counter
			)
		end
	end
end

-- Mesa branca de estudo do Saguão com estrutura preta e 4 assentos acoplados (084933)
function InteriorHelpers.CreateSaguaoStudyTable(
	parent: Instance,
	baseCF: CFrame,
	counter: { count: number }?
)
	local w, d, h = 7.4, 3.3, 2.7
	InteriorHelpers.MakePart(
		parent,
		"StudyTableTop",
		Vector3.new(w, 0.16, d),
		baseCF * CFrame.new(0, h, 0),
		InteriorHelpers.Colors.WallWhite,
		Enum.Material.SmoothPlastic,
		true,
		false,
		counter
	)
	for _, dx in ipairs({ -w * 0.46, 0, w * 0.46 }) do
		for _, dz in ipairs({ -d * 0.44, d * 0.44 }) do
			InteriorHelpers.MakePart(
				parent,
				"StudyTableLeg",
				Vector3.new(0.16, h, 0.16),
				baseCF * CFrame.new(dx, h * 0.5, dz),
				InteriorHelpers.Colors.DarkSteel,
				Enum.Material.Metal,
				true,
				false,
				counter
			)
		end
	end
	-- Travessas longitudinais pretas inferiores
	for _, dz in ipairs({ -d * 0.44, d * 0.44 }) do
		InteriorHelpers.MakePart(
			parent,
			"StudyTableRail",
			Vector3.new(w * 0.92, 0.12, 0.12),
			baseCF * CFrame.new(0, 0.55, dz),
			InteriorHelpers.Colors.DarkSteel,
			Enum.Material.Metal,
			false,
			false,
			counter
		)
	end
	-- 4 cadeiras brancas acopladas (2 de cada lado)
	for _, side in ipairs({ -1, 1 }) do
		for _, dx in ipairs({ -w * 0.24, w * 0.24 }) do
			local seatPos = baseCF * CFrame.new(dx, 1.52, side * (d * 0.56))
			InteriorHelpers.MakePart(
				parent,
				"AttachedSeat",
				Vector3.new(1.28, 0.14, 1.18),
				seatPos,
				InteriorHelpers.Colors.WallWhite,
				Enum.Material.SmoothPlastic,
				true,
				false,
				counter
			)
			InteriorHelpers.MakePart(
				parent,
				"AttachedBack",
				Vector3.new(1.18, 0.95, 0.12),
				seatPos * CFrame.new(0, 0.55, side * 0.54),
				InteriorHelpers.Colors.WallWhite,
				Enum.Material.SmoothPlastic,
				false,
				false,
				counter
			)
			InteriorHelpers.MakePart(
				parent,
				"AttachedStem",
				Vector3.new(0.14, 1.15, 0.14),
				baseCF * CFrame.new(dx, 0.98, side * (d * 0.48)),
				InteriorHelpers.Colors.DarkSteel,
				Enum.Material.Metal,
				false,
				false,
				counter
			)
		end
	end
end

-- Caixa dupla vermelha de hidrante + moldura (085040, 085053)
function InteriorHelpers.CreateHydrantCabinet(
	parent: Instance,
	pos: Vector3,
	outwardDir: Vector3,
	counter: { count: number }?
)
	local box = InteriorHelpers.MakeFacingBox(
		parent,
		"HydrantCabinet",
		pos,
		outwardDir,
		3.6,
		3.2,
		0.45,
		InteriorHelpers.Colors.IFSulRed,
		Enum.Material.Metal,
		false,
		counter
	)
	local cf = box.CFrame
	InteriorHelpers.MakePart(
		parent,
		"HydrantDivider",
		Vector3.new(0.08, 3.0, 0.08),
		cf * CFrame.new(0, 0, -0.24),
		InteriorHelpers.Colors.DarkSteel,
		Enum.Material.Metal,
		false,
		false,
		counter
	)
	for _, dx in ipairs({ -0.9, 0.9 }) do
		InteriorHelpers.MakePart(
			parent,
			"HydrantGlass",
			Vector3.new(0.65, 1.0, 0.06),
			cf * CFrame.new(dx, 0.2, -0.23),
			InteriorHelpers.Colors.GlassTint,
			Enum.Material.Glass,
			false,
			false,
			counter
		)
	end
end

-- Conjunto de lixeiras de coleta seletiva (085010, 085352)
function InteriorHelpers.CreateRecyclingBins(
	parent: Instance,
	baseCF: CFrame,
	count: number,
	counter: { count: number }?
)
	local binColors = {
		Color3.fromRGB(122, 92, 68), -- Orgânico marrom
		Color3.fromRGB(48, 134, 72), -- Vidro verde
		Color3.fromRGB(196, 46, 44), -- Plástico vermelho
		Color3.fromRGB(42, 98, 168), -- Papel azul
		Color3.fromRGB(132, 136, 140), -- Não reciclável cinza
	}
	local n = math.clamp(count, 1, #binColors)
	local spacing = 1.45
	local startX = -((n - 1) * spacing) * 0.5
	for i = 1, n do
		local x = startX + (i - 1) * spacing
		InteriorHelpers.MakePart(
			parent,
			"RecyclingBinBody",
			Vector3.new(1.15, 2.35, 1.15),
			baseCF * CFrame.new(x, 1.35, 0),
			binColors[i],
			Enum.Material.SmoothPlastic,
			true,
			false,
			counter
		)
		InteriorHelpers.MakePart(
			parent,
			"RecyclingBinLid",
			Vector3.new(1.22, 0.42, 1.22),
			baseCF * CFrame.new(x, 2.65, 0),
			binColors[i],
			Enum.Material.SmoothPlastic,
			false,
			false,
			counter
		)
		InteriorHelpers.MakePart(
			parent,
			"RecyclingBinSlot",
			Vector3.new(0.75, 0.24, 0.12),
			baseCF * CFrame.new(x, 2.55, -0.58),
			InteriorHelpers.Colors.DarkSteel,
			Enum.Material.SmoothPlastic,
			false,
			false,
			counter
		)
	end
end

-- Quadro elétrico cinza de parede (084933, 085358)
function InteriorHelpers.CreateElectricalPanel(
	parent: Instance,
	pos: Vector3,
	outwardDir: Vector3,
	w: number,
	h: number,
	counter: { count: number }?
)
	local box = InteriorHelpers.MakeFacingBox(
		parent,
		"ElectricalPanel",
		pos,
		outwardDir,
		w,
		h,
		0.18,
		InteriorHelpers.Colors.PanelGrey,
		Enum.Material.Metal,
		false,
		counter
	)
	InteriorHelpers.MakePart(
		parent,
		"ElectricalHazardTag",
		Vector3.new(w * 0.42, h * 0.22, 0.04),
		box.CFrame * CFrame.new(0, h * 0.2, -0.10),
		Color3.fromRGB(235, 188, 36),
		Enum.Material.SmoothPlastic,
		false,
		false,
		counter
	)
end

-- Vaso branco/cinza com folhagem ornamental (085053)
function InteriorHelpers.CreatePottedPlant(
	parent: Instance,
	pos: Vector3,
	scale: number?,
	counter: { count: number }?
)
	local sc = scale or 1.0
	local potH = 1.65 * sc
	InteriorHelpers.MakePart(
		parent,
		"PlanterPot",
		Vector3.new(1.4 * sc, potH, 1.4 * sc),
		CFrame.new(pos + Vector3.new(0, potH * 0.5, 0)),
		InteriorHelpers.Colors.WallWhite,
		Enum.Material.Concrete,
		true,
		false,
		counter
	)
	for idx, ang in ipairs({ 0, 55, 125, 200, 290 }) do
		local rad = math.rad(ang)
		local leafCF = CFrame.new(pos + Vector3.new(math.cos(rad) * 0.35 * sc, potH + 0.75 * sc, math.sin(rad) * 0.35 * sc))
			* CFrame.Angles(math.rad(25), rad, math.rad(15))
		InteriorHelpers.MakePart(
			parent,
			"PlantLeaf_" .. tostring(idx),
			Vector3.new(0.45 * sc, 1.4 * sc, 0.14 * sc),
			leafCF,
			Color3.fromRGB(52, 126, 56),
			Enum.Material.Grass,
			false,
			false,
			counter
		)
	end
end

return InteriorHelpers
