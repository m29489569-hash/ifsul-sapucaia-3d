--!strict
-- Aplica o detalhamento arquitetônico fidedigno da entrada principal (Av. Copacabana, 100)
-- sobre Workspace.IFSul_Campus, alinhado às fotos do Street View (2024/2026).

local Lighting = game:GetService("Lighting")

local EntranceEnhancer = {}

local COLOR_CREAM_WALL = Color3.fromRGB(234, 230, 223)
local COLOR_DARK_GREEN = Color3.fromRGB(36, 92, 46)
local COLOR_SIGN_WHITE = Color3.fromRGB(238, 240, 238)
local COLOR_SIGN_INK = Color3.fromRGB(28, 34, 30)
local COLOR_IF_GREEN = Color3.fromRGB(47, 158, 65)
local COLOR_IF_RED = Color3.fromRGB(200, 30, 30)
local COLOR_SAGE_PARAPET = Color3.fromRGB(143, 184, 155)
local COLOR_ZEBRA_PAINT = Color3.fromRGB(224, 212, 168)
local COLOR_DARK_ROOF = Color3.fromRGB(44, 48, 50)
local COLOR_GALV_STEEL = Color3.fromRGB(168, 174, 178)
local COLOR_CONCRETE_BLOCK = Color3.fromRGB(132, 128, 122)
local COLOR_BUS_BLUE = Color3.fromRGB(22, 78, 155)

local COLOR_CANOPY_ROOF = Color3.fromRGB(240, 233, 173)
local COLOR_CANOPY_GREEN = Color3.fromRGB(46, 110, 54)
local COLOR_WALKWAY_PAVEMENT = Color3.fromRGB(78, 82, 88)
local COLOR_WALKWAY_JOINT = Color3.fromRGB(45, 48, 53)
local COLOR_WALKWAY_LINE = Color3.fromRGB(194, 155, 34)
local COLOR_WALKWAY_ARROW = Color3.fromRGB(234, 178, 8)
local COLOR_CURB_LIGHT = Color3.fromRGB(140, 138, 132)
local COLOR_CURB_DARK = Color3.fromRGB(125, 124, 118)

export type FrameBasis = {
	center: Vector3,
	east: Vector3,
	west: Vector3,
	south: Vector3,
	north: Vector3,
}

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	canCollide: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = if canCollide ~= nil then canCollide else true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Roblox Cylinder parts align their circular length axis with local +X,
-- so rotating +X toward (p1 - p0) aligns the cylinder strictly between two endpoints.
local function makeSegmentCylinder(
	parent: Instance,
	name: string,
	p0: Vector3,
	p1: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	canCollide: boolean?
): Part?
	local delta = p1 - p0
	local len = delta.Magnitude
	if len < 0.02 then
		return nil
	end
	local xAxis = delta.Unit
	local ref = if math.abs(xAxis.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis
	local zAxis = xAxis:Cross(ref).Unit
	local yAxis = zAxis:Cross(xAxis).Unit
	local cf = CFrame.fromMatrix((p0 + p1) * 0.5, xAxis, yAxis, zAxis)

	local p = makePart(parent, name, Vector3.new(len, diameter, diameter), cf, color, material, canCollide)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function makeFacingBox(
	parent: Instance,
	name: string,
	pos: Vector3,
	outwardDir: Vector3,
	sizeW: number,
	sizeH: number,
	depth: number,
	color: Color3,
	material: Enum.Material?,
	canCollide: boolean?
): Part
	local cf = CFrame.lookAt(pos, pos + outwardDir)
	return makePart(parent, name, Vector3.new(sizeW, sizeH, depth), cf, color, material, canCollide)
end

local function makeSurfaceGui(parent: BasePart, pxPerStud: number): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pxPerStud
	sg.LightInfluence = 0.25
	sg.Parent = parent
	return sg
end

local function populateIfsulGridLogo(container: Frame)
	-- Grid clássico 3x4 do Instituto Federal (topo-esquerda círculo vermelho, demais quadrados verdes)
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
		local c, r, isRedCircle = cell[1] :: number, cell[2] :: number, cell[3] :: boolean
		local dot = Instance.new("Frame")
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = if isRedCircle then COLOR_IF_RED else COLOR_IF_GREEN
		dot.Size = UDim2.fromScale(0.28, 0.21)
		dot.Position = UDim2.fromScale((c - 1) * 0.34, (r - 1) * 0.255)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if isRedCircle then UDim.new(1, 0) else UDim.new(0.18, 0)
		corner.Parent = dot
		dot.Parent = container
	end
end

local function detectGuaritaBasis(buildings: Instance): FrameBasis
	-- Fallback alinhado às coordenadas oficiais medidas na Av. Copacabana
	local roofPos = Vector3.new(-215.70, 0, 41.05)
	local northPos: Vector3? = nil
	local southPos: Vector3? = nil

	for _, desc in ipairs(buildings:GetDescendants()) do
		if desc:IsA("BasePart") then
			local pos = desc.Position
			if pos.X >= -220 and pos.X <= -211 and pos.Z >= 36 and pos.Z <= 46 and pos.Y >= 12.2 and pos.Y <= 13.3 then
				if math.max(desc.Size.X, desc.Size.Z) > 20 then
					roofPos = Vector3.new(pos.X, 0, pos.Z)
				end
			elseif pos.X >= -223 and pos.X <= -212 and pos.Y >= 4.0 and pos.Y <= 8.0 and desc.Size.X > 15 then
				if pos.Z >= 25 and pos.Z <= 30 then
					northPos = Vector3.new(pos.X, 0, pos.Z)
				elseif pos.Z >= 52 and pos.Z <= 58 then
					southPos = Vector3.new(pos.X, 0, pos.Z)
				end
			end
		end
	end

	local south = Vector3.new(0.1514, 0, 0.9885)
	if northPos and southPos then
		local delta = (southPos :: Vector3) - (northPos :: Vector3)
		if delta.Magnitude > 5 then
			south = delta.Unit
		end
	end

	local west = south:Cross(Vector3.yAxis).Unit
	return {
		center = roofPos,
		east = -west,
		west = west,
		south = south,
		north = -south,
	}
end

local function pt(b: FrameBasis, e: number, y: number, s: number): Vector3
	return b.center + b.east * e + Vector3.new(0, y, 0) + b.south * s
end

local function toLocal(b: FrameBasis, p: Vector3): (number, number, number)
	local d = p - b.center
	return d:Dot(b.east), p.Y, d:Dot(b.south)
end

local function sanitizeBaseline(campus: Instance, buildings: Instance, props: Instance, signage: Instance, lights: Instance, basis: FrameBasis)
	-- Limpa instâncias geradas por execuções anteriores de EntranceEnhancer
	for _, host in ipairs({ campus, buildings, props, signage, lights }) do
		local prev = host:FindFirstChild("EntranceEnhanced")
		if prev then
			prev:Destroy()
		end
	end

	local toDestroy: { Instance } = {}

	for _, p in ipairs(buildings:GetDescendants()) do
		if p:IsA("BasePart") then
			local pos = p.Position
			local col = p.Color
			local r, g, b = math.round(col.R * 255), math.round(col.G * 255), math.round(col.B * 255)
			local le, ly, ls = toLocal(basis, pos)
			local maxSz = math.max(p.Size.X, p.Size.Y, p.Size.Z)

			local inOldWalkwayNS = le >= -4.0 and le <= 16.0 and ls >= -54.5 and ls <= -13.0 and ly >= 0.5 and ly <= 12.0
			local inOldWalkwayCorner = le >= -4.0 and le < 7.35 and ls >= -65.0 and ls < -54.5 and ly >= 0.5 and ly <= 12.0
			local isOldWalkwayRoof = (inOldWalkwayNS or inOldWalkwayCorner)
				and r >= 230 and g >= 220 and b >= 160 and b <= 185 and ly >= 10.0 and ly <= 12.0
			local isOldWalkwayGreen = (inOldWalkwayNS or inOldWalkwayCorner)
				and g > r + 20 and g > b + 20 and r < 80 and b < 80 and maxSz < 50
			local isOldWalkwayLight = inOldWalkwayNS and ls <= -14.6 and ly >= 10.2 and ly <= 11.2 and maxSz < 6
				and ((r > 230 and g > 230 and b > 200) or (r >= 145 and r <= 170 and g >= 150 and g <= 175 and b >= 160 and b <= 185))

			-- Piso, juntas, meios-fios, faixa central e setas invertidas da passarela antiga (N-S + setas L-O)
			local isOldWalkwayPavement = le >= -4.0 and le <= 16.0 and ls >= -56.0 and ls <= -13.0 and ly >= 0.05 and ly <= 0.30
				and r == 78 and g == 82 and b == 88 and maxSz < 50
			local isOldWalkwayJoint = le >= -4.0 and le <= 16.0 and ls >= -62.0 and ls <= -13.0 and ly >= 0.15 and ly <= 0.30
				and r == 45 and g == 48 and b == 53 and maxSz < 12
			local isOldWalkwayCurb = le >= -4.0 and le <= 16.0 and ls >= -55.0 and ls <= -13.0 and ly >= 0.20 and ly <= 0.38
				and ((r == 125 and g == 124 and b == 118) or (r == 140 and g == 138 and b == 132))
			local isOldWalkwayLine = le >= -4.0 and le <= 16.0 and ls >= -56.0 and ls <= -13.0 and ly >= 0.15 and ly <= 0.30
				and r == 194 and g == 155 and b == 34 and maxSz < 50
			local isInvertedArrow = le >= -4.0 and le <= 120.0 and ls >= -65.0 and ls <= -13.0 and ly >= 0.15 and ly <= 0.30
				and r == 234 and g == 178 and b == 8

			-- Apara a viga verde sul da passarela L-O se estiver invadindo a curva de 90° (e < 6.9)
			if g > r + 20 and g > b + 20 and ly >= 10.5 and ly <= 11.2 and ls >= -56.5 and ls <= -54.8 and maxSz > 100 then
				local trimAmount = 2.62
				if p.Size.Z > 110 then
					p.Size = Vector3.new(p.Size.X, p.Size.Y, p.Size.Z - trimAmount)
					p.CFrame = p.CFrame + basis.east * (trimAmount * 0.5)
				end
			end

			local isFakeTotemWall = pos.X >= -231.5 and pos.X <= -227.0 and pos.Z >= -4.0 and pos.Z <= 20.5 and pos.Y > 3.5
			local isGreenLollipop = pos.X >= -236.0 and pos.X <= -232.0 and pos.Z >= 34.0 and pos.Z <= 43.0 and pos.Y > 1.0 and pos.Y < 8.5
			local isSolidVehicleGate = pos.X >= -224.0 and pos.X <= -214.0 and pos.Z >= 54.5 and pos.Z <= 90.0 and pos.Y > 1.5 and pos.Y < 6.0 and p.Size.X > 8
			local isFrontYellowCurb = pos.X >= -240.0 and pos.X <= -235.0 and pos.Z >= 18.0 and pos.Z <= 52.0 and r > 200 and g > 150 and b < 80
			local isDrivewayCrosswalk = pos.X >= -237.0 and pos.X <= -229.0 and pos.Z >= 52.0 and pos.Z <= 76.0 and pos.Y < 0.5 and r > 220 and g > 220 and b > 220
			local isNorthWallGreenCap = pos.X >= -240.0 and pos.X <= -234.0 and pos.Z >= -15.0 and pos.Z <= 6.0 and pos.Y > 4.0 and g > 120 and r < 80
			local isSouthWallGreenCap = pos.X >= -224.0 and pos.X <= -218.0 and pos.Z >= 88.0 and pos.Z <= 110.0 and pos.Y > 4.0 and g > 120 and r < 80
			local isGuaritaWestGlass = pos.X >= -226.5 and pos.X <= -223.5 and pos.Z >= 30.0 and pos.Z <= 54.0 and pos.Y >= 4.0 and pos.Y <= 9.5 and p.Material == Enum.Material.Glass
			local isGuaritaWestGreenBand = pos.X >= -226.5 and pos.X <= -223.5 and pos.Z >= 30.0 and pos.Z <= 54.0 and pos.Y > 10.5 and g > 120 and r < 80
			local isGuaritaWestMullion = pos.X >= -227.0 and pos.X <= -222.5 and pos.Z >= 31.0 and pos.Z <= 53.0 and pos.Y >= 4.5 and pos.Y <= 9.0 and p.Size.Y > 4 and r < 60 and g < 60 and b < 60

			if isOldWalkwayRoof or isOldWalkwayGreen or isOldWalkwayLight or isOldWalkwayPavement or isOldWalkwayJoint or isOldWalkwayCurb or isOldWalkwayLine or isInvertedArrow or isFakeTotemWall or isGreenLollipop or isSolidVehicleGate or isFrontYellowCurb or isDrivewayCrosswalk or isNorthWallGreenCap or isSouthWallGreenCap or isGuaritaWestGlass or isGuaritaWestGreenBand or isGuaritaWestMullion then
				table.insert(toDestroy, p)
			elseif pos.X >= -226 and pos.X <= -205 and pos.Z >= 25 and pos.Z <= 57 then
				-- Converte guarita e faixas N/S/L para o creme institucional da fachada
				local isWallOrBand = (r > 235 and g > 235 and b > 235 and pos.Y > 3 and pos.Y < 13.5)
					or (g > 120 and r < 80 and pos.Y > 10.5)
				if isWallOrBand then
					p.Color = COLOR_CREAM_WALL
					p.Material = Enum.Material.SmoothPlastic
				end
			elseif (pos.X >= -240 and pos.X <= -234 and pos.Z >= -15 and pos.Z <= 6 and pos.Y > 0.5 and pos.Y <= 4.0)
				or (pos.X >= -224 and pos.X <= -218 and pos.Z >= 88 and pos.Z <= 110 and pos.Y > 0.5 and pos.Y <= 4.0) then
				-- Muros norte e sul em blocos de concreto aparente
				p.Color = COLOR_CONCRETE_BLOCK
				p.Material = Enum.Material.Concrete
			elseif pos.X >= -195 and pos.X <= -35 and pos.Z >= -90 and pos.Z <= 125 and pos.Y >= 14.5 and pos.Y <= 23.0 then
				-- Platibandas superiores de fundo (Setor 100 e Bloco Central) em verde sálvia
				local isParapet = p.Size.Y >= 1.4 and p.Size.Y <= 1.85 and math.max(p.Size.X, p.Size.Z) >= 10
				if isParapet and r > 205 and g > 205 and b > 200 then
					p.Color = COLOR_SAGE_PARAPET
				end
			end
		end
	end

	for _, p in ipairs(signage:GetDescendants()) do
		if p:IsA("BasePart") then
			local pos = p.Position
			local onFakeWall = pos.X >= -232.0 and pos.X <= -227.0 and pos.Z >= -2.0 and pos.Z <= 18.0
			local aboveGuaritaRoof = pos.X >= -226.0 and pos.X <= -206.0 and pos.Z >= 28.0 and pos.Z <= 52.0 and pos.Y > 13.5
			if onFakeWall or aboveGuaritaRoof then
				table.insert(toDestroy, p)
			end
		end
	end

	for _, p in ipairs(props:GetDescendants()) do
		if p:IsA("BasePart") then
			local pos = p.Position
			if pos.X >= -232.0 and pos.X <= -225.0 and pos.Z >= 50.0 and pos.Z <= 57.0 then
				table.insert(toDestroy, p)
			end
		end
	end

	for _, p in ipairs(lights:GetDescendants()) do
		if p:IsA("BasePart") then
			local pos = p.Position
			if pos.X >= -232.0 and pos.X <= -225.0 and pos.Z >= 50.0 and pos.Z <= 57.0 then
				table.insert(toDestroy, p)
			end
		end
	end

	for _, inst in ipairs(toDestroy) do
		inst:Destroy()
	end
end

local function buildGuaritaFacade(folder: Folder, b: FrameBasis)
	local wFace = -9.12

	-- Arremate superior creme cobrindo pequena junta sob a cobertura
	makeFacingBox(folder, "GuaritaUpperFrieze", pt(b, wFace - 0.05, 13.0, 0), b.west, 28.20, 0.72, 0.22, COLOR_CREAM_WALL)

	-- Janela frontal menor em esquadria verde-escuro com grades
	local winS, winY, winW, winH = -1.9, 6.55, 12.0, 4.4
	local frameCol = Color3.fromRGB(34, 44, 38)
	local glassCol = Color3.fromRGB(20, 32, 30)

	local glass = makeFacingBox(folder, "GuaritaWindowGlass", pt(b, wFace - 0.10, winY, winS), b.west, winW, winH, 0.14, glassCol, Enum.Material.Glass)
	glass.Reflectance = 0.24

	-- Moldura externa da janela e peitoril inferior
	makeFacingBox(folder, "WinFrameTop", pt(b, wFace - 0.16, winY + winH * 0.5, winS), b.west, winW + 0.35, 0.24, 0.28, frameCol, Enum.Material.Metal)
	makeFacingBox(folder, "WinSill", pt(b, wFace - 0.22, winY - winH * 0.5 - 0.04, winS), b.west, winW + 0.55, 0.26, 0.44, Color3.fromRGB(52, 60, 52), Enum.Material.Concrete)
	makeFacingBox(folder, "WinFrameL", pt(b, wFace - 0.16, winY, winS - winW * 0.5 - 0.06), b.west, 0.24, winH, 0.28, frameCol, Enum.Material.Metal)
	makeFacingBox(folder, "WinFrameR", pt(b, wFace - 0.16, winY, winS + winW * 0.5 + 0.06), b.west, 0.24, winH, 0.28, frameCol, Enum.Material.Metal)

	for _, dy in ipairs({ -1.1, 0, 1.1 }) do
		makeFacingBox(folder, "WinBarH", pt(b, wFace - 0.20, winY + dy, winS), b.west, winW - 0.1, 0.08, 0.08, frameCol, Enum.Material.Metal, false)
	end
	for i = -2, 2 do
		makeFacingBox(folder, "WinBarV", pt(b, wFace - 0.20, winY, winS + i * 2.1), b.west, 0.08, winH - 0.1, 0.08, frameCol, Enum.Material.Metal, false)
	end

	-- Placa retangular branca IFSul diretamente acima da janela
	local signW, signH = 18.8, 3.35
	local signPlate = makeFacingBox(folder, "IfsulEntranceSign", pt(b, wFace - 0.14, 10.85, -2.8), b.west, signW, signH, 0.20, COLOR_SIGN_WHITE)
	local sg = makeSurfaceGui(signPlate, 44)

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = COLOR_SIGN_WHITE
	bg.BorderSizePixel = 0
	bg.Parent = sg

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(190, 194, 190)
	stroke.Thickness = 2
	stroke.Parent = bg

	local logoBox = Instance.new("Frame")
	logoBox.BackgroundTransparency = 1
	logoBox.Position = UDim2.fromScale(0.035, 0.10)
	logoBox.Size = UDim2.fromScale(0.145, 0.80)
	logoBox.Parent = bg
	populateIfsulGridLogo(logoBox)

	local l1 = Instance.new("TextLabel")
	l1.BackgroundTransparency = 1
	l1.Position = UDim2.fromScale(0.21, 0.08)
	l1.Size = UDim2.fromScale(0.76, 0.34)
	l1.Font = Enum.Font.GothamBold
	l1.Text = "INSTITUTO FEDERAL"
	l1.TextColor3 = COLOR_SIGN_INK
	l1.TextScaled = true
	l1.TextXAlignment = Enum.TextXAlignment.Left
	l1.Parent = bg

	local l2 = Instance.new("TextLabel")
	l2.BackgroundTransparency = 1
	l2.Position = UDim2.fromScale(0.21, 0.42)
	l2.Size = UDim2.fromScale(0.76, 0.24)
	l2.Font = Enum.Font.GothamMedium
	l2.Text = "Sul-rio-grandense"
	l2.TextColor3 = COLOR_SIGN_INK
	l2.TextScaled = true
	l2.TextXAlignment = Enum.TextXAlignment.Left
	l2.Parent = bg

	local l3 = Instance.new("TextLabel")
	l3.BackgroundTransparency = 1
	l3.Position = UDim2.fromScale(0.21, 0.67)
	l3.Size = UDim2.fromScale(0.76, 0.26)
	l3.Font = Enum.Font.GothamBold
	l3.Text = "Câmpus Sapucaia do Sul"
	l3.TextColor3 = COLOR_SIGN_INK
	l3.TextScaled = true
	l3.TextXAlignment = Enum.TextXAlignment.Left
	l3.Parent = bg

	-- Número predial "100" à direita da janela
	local numPart = makeFacingBox(folder, "Address100", pt(b, wFace - 0.12, 8.8, 9.8), b.west, 3.2, 1.35, 0.05, COLOR_CREAM_WALL, nil, false)
	numPart.Transparency = 1
	local nsg = makeSurfaceGui(numPart, 60)
	local nlbl = Instance.new("TextLabel")
	nlbl.Size = UDim2.fromScale(1, 1)
	nlbl.BackgroundTransparency = 1
	nlbl.Font = Enum.Font.GothamBold
	nlbl.Text = "100"
	nlbl.TextColor3 = Color3.fromRGB(35, 38, 36)
	nlbl.TextScaled = true
	nlbl.Parent = nsg

	-- Toldo inclinado escuro na face sul da guarita + condensadora de ar no lado norte
	local awningPos = pt(b, -2.5, 8.3, 15.2)
	local awningCF = CFrame.lookAt(awningPos, awningPos + b.south) * CFrame.Angles(math.rad(-18), 0, 0)
	makePart(folder, "GuaritaSouthAwning", Vector3.new(6.8, 0.18, 2.6), awningCF, COLOR_DARK_ROOF, Enum.Material.Metal, false)
	makeFacingBox(folder, "GuaritaNorthAC", pt(b, -4.5, 10.3, -14.7), b.north, 2.6, 1.8, 1.1, Color3.fromRGB(228, 230, 232), Enum.Material.Metal)
end

local function buildZebraAndTwinLamppost(folder: Folder, lightsFolder: Folder, b: FrameBasis)
	-- Zebrado trapezoidal em frente à guarita (CanCollide = false, acima da cota do pavimento)
	local eIn, eOut = -9.9, -20.5
	local yPaint = 0.135
	local thick = 0.045

	local southEdge = 13.5

	local function addFlatBar(name: string, p0: Vector3, p1: Vector3, width: number)
		local delta = p1 - p0
		local len = delta.Magnitude
		if len < 0.05 then return end
		local cf = CFrame.lookAt((p0 + p1) * 0.5, p1)
		makePart(folder, name, Vector3.new(width, thick, len), cf, COLOR_ZEBRA_PAINT, Enum.Material.SmoothPlastic, false)
	end

	-- Bordas do trapézio
	addFlatBar("ZebraBorderE", pt(b, eIn, yPaint, -13.6), pt(b, eIn, yPaint, southEdge), 0.36)
	addFlatBar("ZebraBorderW", pt(b, eOut, yPaint, -17.2), pt(b, eOut, yPaint, southEdge), 0.36)
	addFlatBar("ZebraBorderS", pt(b, eIn, yPaint, southEdge), pt(b, eOut, yPaint, southEdge), 0.36)
	addFlatBar("ZebraBorderN", pt(b, eIn, yPaint, -13.6), pt(b, eOut, yPaint, -17.2), 0.36)

	local function diagEAtS(s: number): number
		local u = math.clamp((s - (-13.6)) / (-17.2 - (-13.6)), 0, 1)
		return eIn + u * (eOut - eIn)
	end

	-- Faixas horizontais internas acompanhando inclusive a diagonal superior
	local numStripes = 14
	for i = 1, numStripes do
		local t = i / (numStripes + 1)
		local sVal = -16.8 + t * (southEdge - (-16.8))
		local eStart = if sVal < -13.6 then diagEAtS(sVal) else eIn
		if eStart > eOut + 0.8 then
			addFlatBar("ZebraStripe", pt(b, eStart - 0.25, yPaint, sVal), pt(b, eOut + 0.25, yPaint, sVal), 0.34)
		end
	end

	-- Poste alto galvanizado de braço duplo curvo (dentro da faixa zebrada junto à rua)
	local poleE, poleS = -19.0, 1.0
	local basePos = pt(b, poleE, 0, poleS)
	makePart(folder, "TwinPolePlinth", Vector3.new(1.3, 0.85, 1.3), CFrame.lookAt(basePos + Vector3.new(0, 0.42, 0), basePos + Vector3.new(0, 0.42, 0) + b.west), Color3.fromRGB(162, 158, 150), Enum.Material.Concrete)
	makeSegmentCylinder(folder, "TwinPoleLower", basePos + Vector3.new(0, 0.8, 0), basePos + Vector3.new(0, 6.2, 0), 0.68, COLOR_GALV_STEEL, Enum.Material.Metal)
	makeSegmentCylinder(folder, "TwinPoleMast", basePos + Vector3.new(0, 6.2, 0), basePos + Vector3.new(0, 25.0, 0), 0.46, COLOR_GALV_STEEL, Enum.Material.Metal)

	local lightsSub = Instance.new("Folder")
	lightsSub.Name = "EntranceEnhanced"
	lightsSub.Parent = lightsFolder

	local nightNow = Lighting.ClockTime < 6 or Lighting.ClockTime >= 18

	for _, dirSign in ipairs({ -1, 1 }) do
		local armPts = {
			pt(b, poleE, 24.4, poleS),
			pt(b, poleE, 26.8, poleS + dirSign * 1.4),
			pt(b, poleE, 28.9, poleS + dirSign * 3.3),
			pt(b, poleE, 30.3, poleS + dirSign * 5.4),
			pt(b, poleE, 31.1, poleS + dirSign * 7.3),
		}
		for k = 1, #armPts - 1 do
			makeSegmentCylinder(folder, "TwinArmSeg", armPts[k], armPts[k + 1], 0.24, COLOR_GALV_STEEL, Enum.Material.Metal, false)
		end

		local tipPos = armPts[#armPts]
		local headDir = (b.south * dirSign).Unit
		local headCF = CFrame.lookAt(tipPos, tipPos + headDir) * CFrame.Angles(math.rad(14), 0, 0)
		makePart(folder, "LedLuminaria", Vector3.new(0.85, 0.26, 2.3), headCF, Color3.fromRGB(58, 62, 66), Enum.Material.Metal, false)
		makePart(folder, "LedGlow", Vector3.new(0.68, 0.08, 1.9), headCF * CFrame.new(0, -0.14, 0), Color3.fromRGB(255, 248, 228), Enum.Material.Neon, false)

		local lp = makePart(lightsSub, "EntranceTwinLight", Vector3.new(0.5, 0.5, 0.5), CFrame.new(tipPos - Vector3.new(0, 0.5, 0)), Color3.new(1, 1, 1), nil, false)
		lp.Transparency = 1
		local pl = Instance.new("PointLight")
		pl.Color = Color3.fromRGB(255, 242, 214)
		pl.Range = 54
		pl.Brightness = 1.5
		pl.Shadows = false
		pl.Enabled = nightNow
		pl.Parent = lp
	end
end

local function addTubularFencePanel(
	folder: Folder,
	name: string,
	p0: Vector3,
	p1: Vector3,
	height: number,
	spacing: number,
	canCollide: boolean?
)
	local delta = p1 - p0
	local len = delta.Magnitude
	if len < 0.3 then return end
	local axis = delta.Unit
	local mid = (p0 + p1) * 0.5
	local cf = CFrame.lookAt(mid, p1)

	-- Travessas horizontais inferior, média e superior
	for _, yFrac in ipairs({ 0.12, 0.52, 0.96 }) do
		makePart(folder, name .. "_Rail", Vector3.new(0.14, 0.14, len), cf + Vector3.new(0, height * yFrac, 0), COLOR_DARK_GREEN, Enum.Material.Metal, canCollide)
	end

	-- Montantes verticais vazados
	local steps = math.max(2, math.floor(len / spacing))
	for i = 0, steps do
		local t = i / steps
		local base = p0 + axis * (t * len)
		local isPost = (i == 0 or i == steps or i % 7 == 0)
		local w = if isPost then 0.24 else 0.10
		makePart(folder, name .. "_Bar", Vector3.new(w, height, w), CFrame.new(base + Vector3.new(0, height * 0.5, 0)) * cf.Rotation, COLOR_DARK_GREEN, Enum.Material.Metal, canCollide)
	end
end

local function buildCoveredWalkwayL(folder: Folder, b: FrameBasis)
	-- Passarela coberta reta saindo da guarita (e constante) com curva de 90° para o corredor leste-oeste
	local walkE0 = -2.0
	local walkE1 = 7.33
	local walkW = walkE1 - walkE0
	local walkECenter = (walkE0 + walkE1) * 0.5
	local sStart = -14.1
	local sEnd = -64.08
	local roofY = 11.07

	-- Telhado translúcido ondulado reto (alinhado com a guarita e com a passarela leste-oeste)
	local stripPitch = 0.86
	local sCur = sEnd + stripPitch * 0.5
	while sCur < sStart do
		local stripPos = pt(b, walkECenter, roofY, sCur)
		local stripCF = CFrame.lookAt(stripPos, stripPos + b.south)
		local strip = makePart(
			folder,
			"WalkwayRoofStrip",
			Vector3.new(walkW, 0.14, stripPitch - 0.04),
			stripCF,
			COLOR_CANOPY_ROOF,
			Enum.Material.Grass,
			false
		)
		strip.Transparency = 0.12
		sCur += stripPitch
	end

	-- Estrutura metálica verde-escuro (vigas longitudinais, travessas e pilares)
	local colEW = -1.6
	local colEE = 6.9
	local beamY = 10.90

	local function addBeam(name: string, p0: Vector3, p1: Vector3, w: number, h: number)
		local delta = p1 - p0
		local len = delta.Magnitude
		if len < 0.1 then return end
		local cf = CFrame.lookAt((p0 + p1) * 0.5, p1)
		makePart(folder, name, Vector3.new(w, h, len), cf, COLOR_CANOPY_GREEN, Enum.Material.Metal, false)
	end

	-- Vigas longitudinais ao longo da passarela norte-sul
	addBeam("WalkwayBeamW", pt(b, colEW, beamY, sEnd + 0.45), pt(b, colEW, beamY, sStart), 0.30, 0.28)
	addBeam("WalkwayBeamE", pt(b, colEE, beamY, -54.5), pt(b, colEE, beamY, sStart), 0.30, 0.28)
	addBeam("WalkwayRidge", pt(b, walkECenter, 11.00, sEnd + 0.45), pt(b, walkECenter, 11.00, sStart), 0.20, 0.19)

	-- Vigas de transição na curva 90° conectando à passarela leste-oeste existente
	addBeam("WalkwayCornerBeamN", pt(b, colEW, beamY, -63.6), pt(b, 14.40, beamY, -63.6), 0.30, 0.28)
	addBeam("WalkwayCornerBeamS", pt(b, colEE, beamY, -54.5), pt(b, 14.56, beamY, -54.78), 0.30, 0.28)

	-- Travessas transversais e pilares verticais (passagem de pedestres em s=[-20.5..-14.1] livre)
	local sStations = { -14.5, -24.5, -34.5, -44.5, -54.5, -63.6 }
	for _, sPos in ipairs(sStations) do
		addBeam("WalkwayCrossBeam", pt(b, colEW, beamY, sPos), pt(b, colEE, beamY, sPos), 0.25, 0.27)

		local postW = pt(b, colEW, 5.45, sPos)
		makePart(folder, "WalkwayPostW", Vector3.new(0.30, 10.90, 0.30), CFrame.lookAt(postW, postW + b.south), COLOR_CANOPY_GREEN, Enum.Material.Metal, true)

		if sPos > -60.0 then
			local postE = pt(b, colEE, 5.45, sPos)
			makePart(folder, "WalkwayPostE", Vector3.new(0.30, 10.90, 0.30), CFrame.lookAt(postE, postE + b.south), COLOR_CANOPY_GREEN, Enum.Material.Metal, true)
		end
	end

	-- Luminárias fluorescentes no teto da passarela
	for _, sLight in ipairs({ -24.5, -40.0, -56.0 }) do
		local lPos = pt(b, walkECenter, 10.75, sLight)
		local lCF = CFrame.lookAt(lPos, lPos + b.south)
		makePart(folder, "WalkwayLightBody", Vector3.new(0.32, 0.28, 4.4), lCF, Color3.fromRGB(244, 244, 240), Enum.Material.Metal, false)
		makePart(folder, "WalkwayLightTube", Vector3.new(0.20, 0.10, 3.9), lCF * CFrame.new(0, -0.15, 0), Color3.fromRGB(255, 244, 214), Enum.Material.Neon, false)
	end

	-- === PISO, MEIOS-FIOS, FAIXA CENTRAL E SETAS DIRECIONAIS CORRIGIDAS ===
	-- Pavimento escuro exatamente sob o telhado reto N-S e a curva de 90°
	local pathLen = sStart - sEnd
	local pathCenter = pt(b, walkECenter, 0.145, (sStart + sEnd) * 0.5)
	makePart(
		folder,
		"WalkwayPavementNS",
		Vector3.new(walkW, 0.13, pathLen),
		CFrame.lookAt(pathCenter, pathCenter + b.south),
		COLOR_WALKWAY_PAVEMENT,
		Enum.Material.SmoothPlastic,
		true
	)

	-- Juntas de dilatação transversais no piso N-S + junta na entrada do trecho L-O
	for _, sJoint in ipairs({ -14.5, -24.5, -34.5, -44.5, -54.5 }) do
		local jPos = pt(b, walkECenter, 0.225, sJoint)
		makePart(folder, "WalkwayFloorJoint", Vector3.new(walkW - 0.12, 0.05, 0.15), CFrame.lookAt(jPos, jPos + b.south), COLOR_WALKWAY_JOINT, Enum.Material.SmoothPlastic, false)
	end
	local cornerJointPos = pt(b, walkE1, 0.225, -59.2)
	makePart(folder, "WalkwayCornerJoint", Vector3.new(9.5, 0.05, 0.15), CFrame.lookAt(cornerJointPos, cornerJointPos + b.east), COLOR_WALKWAY_JOINT, Enum.Material.SmoothPlastic, false)

	-- Meios-fios alternados seguindo as bordas externas e internas da curva de 90°
	local function addCurbRun(namePrefix: string, p0: Vector3, p1: Vector3)
		local delta = p1 - p0
		local len = delta.Magnitude
		if len < 0.5 then return end
		local dir = delta.Unit
		local segLen = 2.25
		local count = math.max(1, math.floor(len / segLen + 0.5))
		local step = len / count
		for i = 0, count - 1 do
			local cPos = p0 + dir * ((i + 0.5) * step)
			local col = if i % 2 == 0 then COLOR_CURB_LIGHT else COLOR_CURB_DARK
			makePart(folder, namePrefix, Vector3.new(0.55, 0.48, step - 0.08), CFrame.lookAt(cPos, cPos + dir), col, Enum.Material.SmoothPlastic, true)
		end
	end

	-- Borda oeste (deixa a passagem de pedestres s=[-20.5..-14.1] livre sem degrau)
	addCurbRun("WalkwayCurbW", pt(b, walkE0 - 0.28, 0.29, sEnd - 0.28), pt(b, walkE0 - 0.28, 0.29, -21.0))
	-- Borda leste até a curva interna de 90°
	addCurbRun("WalkwayCurbE", pt(b, walkE1 + 0.28, 0.29, -54.25), pt(b, walkE1 + 0.28, 0.29, -14.5))
	-- Borda externa norte na curva de 90°
	addCurbRun("WalkwayCurbCornerN", pt(b, walkE0 - 0.28, 0.29, sEnd - 0.28), pt(b, walkE1 + 0.28, 0.29, sEnd - 0.28))
	-- Continuação da borda sul da curva interna até o primeiro meio-fio L-O existente (e = 14.0)
	addCurbRun("WalkwayCurbCornerS", pt(b, walkE1 + 0.28, 0.29, -54.32), pt(b, 14.0, 0.29, -54.42))

	-- Faixa amarela central contínua fazendo a curva de 90° (alinhada ao início da linha L-O em e=6.52, s=-57.99)
	local sCornerMid = -57.99
	local lineNSLen = (-15.5) - sCornerMid
	local lineNSPos = pt(b, walkECenter, 0.225, (sCornerMid + (-15.5)) * 0.5)
	makePart(folder, "WalkwayCenterLineNS", Vector3.new(0.15, 0.05, lineNSLen), CFrame.lookAt(lineNSPos, lineNSPos + b.south), COLOR_WALKWAY_LINE, Enum.Material.SmoothPlastic, false)

	local lineCornerEndE = 6.65
	local lineCornerLen = lineCornerEndE - walkECenter
	local lineCornerPos = pt(b, (walkECenter + lineCornerEndE) * 0.5, 0.225, sCornerMid)
	makePart(folder, "WalkwayCenterLineCorner", Vector3.new(0.15, 0.05, lineCornerLen), CFrame.lookAt(lineCornerPos, lineCornerPos + b.east), COLOR_WALKWAY_LINE, Enum.Material.SmoothPlastic, false)

	-- Helper para seta direcional correta (ponta em ">" apontando no sentido de dir, sem inversão em "Y")
	local function addDirectionalArrow(pos: Vector3, dir: Vector3)
		local u = dir.Unit
		local side = u:Cross(Vector3.yAxis).Unit
		-- Haste central
		makePart(folder, "WalkwayArrowShaft", Vector3.new(0.34, 0.05, 1.80), CFrame.lookAt(pos, pos + u), COLOR_WALKWAY_ARROW, Enum.Material.SmoothPlastic, false)
		-- Ponta em V voltada para frente (wings partem da ponta e recuam para trás/lados)
		local tip = pos + u * 0.92
		for _, sign in ipairs({ -1, 1 }) do
			local backEnd = tip - u * 0.78 + side * (sign * 0.66)
			local wingDelta = tip - backEnd
			local wingMid = (tip + backEnd) * 0.5
			makePart(folder, "WalkwayArrowHead", Vector3.new(0.30, 0.05, wingDelta.Magnitude), CFrame.lookAt(wingMid, tip), COLOR_WALKWAY_ARROW, Enum.Material.SmoothPlastic, false)
		end
	end

	-- Setas corretas no trecho reto N-S (mão inglesa/direita: leste entra para norte, oeste sai para sul)
	for _, sArrow in ipairs({ -20.0, -30.0, -40.0, -50.0 }) do
		addDirectionalArrow(pt(b, walkECenter + 2.15, 0.225, sArrow), b.north)
		addDirectionalArrow(pt(b, walkECenter - 2.15, 0.225, sArrow), b.south)
	end

	-- Setas corrigidas ao longo de toda a passarela L-O existente (substituindo as antigas invertidas)
	local ewDir = (b.east - b.south * 0.0205).Unit
	for i = 0, 10 do
		-- Faixa sul: sentido entrada (+Leste)
		addDirectionalArrow(pt(b, 9.11 + i * 10.13, 0.225, -56.52 - i * 0.21), ewDir)
		-- Faixa norte: sentido saída (-Leste / Oeste)
		addDirectionalArrow(pt(b, 9.78 + i * 10.13, 0.225, -59.56 - i * 0.204), -ewDir)
	end
end

local function buildNorthWalkwayAndFence(folder: Folder, b: FrameBasis)
	-- Grade recuada (mais para trás, próxima à passarela coberta) ligando-se ao fim do muro norte
	local fenceE = -3.2
	local sWall = -48.0
	local sGateStart = -20.5

	-- Fechamento curto ligando o fundo do muro de concreto norte (e = -6.0) à linha recuada da grade (e = -3.2)
	addTubularFencePanel(folder, "NorthWallReturnFence", pt(b, -6.0, 0, sWall), pt(b, fenceE, 0, sWall), 7.6, 0.85, true)
	-- Grade tubular vazada norte recuada (separada da parada de ônibus)
	addTubularFencePanel(folder, "NorthFrontFence", pt(b, fenceE, 0, sWall), pt(b, fenceE, 0, sGateStart), 7.6, 0.85, true)

	-- Poste esquerdo do portão de pedestres e folha aberta recolhida paralela à grade (passagem 100% livre)
	makePart(folder, "PedGatePostL", Vector3.new(0.32, 8.2, 0.32), CFrame.lookAt(pt(b, fenceE, 4.1, sGateStart), pt(b, fenceE, 4.1, sGateStart) + b.west), COLOR_DARK_GREEN, Enum.Material.Metal)
	addTubularFencePanel(folder, "PedGateOpenLeaf", pt(b, fenceE + 0.55, 0, sGateStart), pt(b, fenceE + 0.55, 0, sGateStart - 4.8), 7.5, 0.85, false)

	-- Parada de ônibus independente na calçada (área frontal isolada, sem ligação com o fundo ou a guarita)
	local busE0, busE1 = -15.4, -9.4
	local busS0, busS1 = -39.6, -22.0
	local busLen = busS1 - busS0
	local busW = busE1 - busE0
	local busCenter = pt(b, (busE0 + busE1) * 0.5, 8.85, (busS0 + busS1) * 0.5)
	local busCF = CFrame.lookAt(busCenter, busCenter + b.west) * CFrame.Angles(math.rad(4), 0, 0)
	makePart(folder, "BusStopRoof", Vector3.new(busLen, 0.24, busW), busCF, COLOR_DARK_ROOF, Enum.Material.Metal, false)
	makePart(folder, "BusStopFasciaW", Vector3.new(busLen + 0.1, 0.42, 0.22), busCF * CFrame.new(0, -0.08, -busW * 0.5), COLOR_DARK_ROOF, Enum.Material.Metal, false)

	-- Nervuras da telha ondulada da parada de ônibus
	for s = busS0 + 0.6, busS1 - 0.6, 1.4 do
		local ribPos = pt(b, (busE0 + busE1) * 0.5, 9.00, s)
		local ribCF = CFrame.lookAt(ribPos, ribPos + b.west) * CFrame.Angles(math.rad(4), 0, 0)
		makePart(folder, "BusStopRib", Vector3.new(0.16, 0.14, busW), ribCF, Color3.fromRGB(36, 40, 42), Enum.Material.Metal, false)
	end

	-- Colunas e vigas próprias sustentando a parada de ônibus isolada
	local colFrontE = -14.7
	local colBackE = -10.1
	local busCols = { busS0 + 0.6, -33.5, -28.0, busS1 - 0.6 }
	for _, sCol in ipairs(busCols) do
		makeSegmentCylinder(folder, "BusStopColW", pt(b, colFrontE, 0, sCol), pt(b, colFrontE, 8.50, sCol), 0.26, COLOR_DARK_GREEN, Enum.Material.Metal, true)
		makeSegmentCylinder(folder, "BusStopColE", pt(b, colBackE, 0, sCol), pt(b, colBackE, 8.75, sCol), 0.26, COLOR_DARK_GREEN, Enum.Material.Metal, true)
		makeSegmentCylinder(folder, "BusStopCrossBeam", pt(b, colFrontE, 8.42, sCol), pt(b, colBackE, 8.68, sCol), 0.20, COLOR_DARK_GREEN, Enum.Material.Metal, false)
	end
	makeSegmentCylinder(folder, "BusStopFrontBeam", pt(b, colFrontE, 8.42, busS0 + 0.4), pt(b, colFrontE, 8.42, busS1 - 0.4), 0.22, COLOR_DARK_GREEN, Enum.Material.Metal, false)
	makeSegmentCylinder(folder, "BusStopBackBeam", pt(b, colBackE, 8.68, busS0 + 0.4), pt(b, colBackE, 8.68, busS1 - 0.4), 0.22, COLOR_DARK_GREEN, Enum.Material.Metal, false)

	-- 2 bancos escuros de espera sob a parada de ônibus
	for _, sBench in ipairs({ -34.8, -26.8 }) do
		local benchCenter = pt(b, -11.4, 1.65, sBench)
		local bcf = CFrame.lookAt(benchCenter, benchCenter + b.west)
		makePart(folder, "ShelterBenchTop", Vector3.new(5.4, 0.18, 1.5), bcf, Color3.fromRGB(48, 52, 50), Enum.Material.Metal, true)
		for _, ds in ipairs({ -2.0, 2.0 }) do
			makePart(folder, "ShelterBenchLeg", Vector3.new(0.22, 1.6, 1.2), bcf * CFrame.new(ds, -0.82, 0), COLOR_DARK_GREEN, Enum.Material.Metal, true)
		end
	end

	-- Passarela coberta reta saindo da guarita com curva 90°
	buildCoveredWalkwayL(folder, b)
end

local function buildSouthGatesBannerAndSign(folder: Folder, b: FrameBasis)
	local fenceE = -9.1
	local sGuaritaEnd = 14.1
	local sDriveStart = 18.2
	local sDriveEnd = 38.2
	local sSouthEnd = 51.0

	-- Pequena grade/portão lateral junto à face sul da guarita
	addTubularFencePanel(folder, "SouthSideGate", pt(b, fenceE, 0, sGuaritaEnd), pt(b, fenceE, 0, sDriveStart), 7.6, 0.85, true)
	makePart(folder, "DrivePostN", Vector3.new(0.36, 8.2, 0.36), CFrame.lookAt(pt(b, fenceE, 4.1, sDriveStart), pt(b, fenceE, 4.1, sDriveStart) + b.west), COLOR_DARK_GREEN, Enum.Material.Metal)
	makePart(folder, "DrivePostS", Vector3.new(0.36, 8.2, 0.36), CFrame.lookAt(pt(b, fenceE, 4.1, sDriveEnd), pt(b, fenceE, 4.1, sDriveEnd) + b.west), COLOR_DARK_GREEN, Enum.Material.Metal)

	-- Folha tubular de correr recolhida aberta à direita (deixa a pista de veículos 100% transitável)
	addTubularFencePanel(folder, "VehicleGateOpenPanel", pt(b, fenceE + 0.55, 0, sDriveEnd - 0.5), pt(b, fenceE + 0.55, 0, sSouthEnd - 0.5), 7.5, 0.9, false)

	-- Cancela "IDENTIFIQUE-SE" (CanCollide = false para não travar personagens/veículos)
	local barE = -5.8
	local barPos = pt(b, barE, 0, sDriveStart - 0.8)
	makePart(folder, "BarrierBox", Vector3.new(1.1, 3.8, 1.1), CFrame.lookAt(barPos + Vector3.new(0, 1.9, 0), barPos + Vector3.new(0, 1.9, 0) + b.west), Color3.fromRGB(205, 58, 38), Enum.Material.Metal, true)

	local armLen = sDriveEnd - sDriveStart - 1.2
	local segCount = 12
	for i = 0, segCount - 1 do
		local s0 = sDriveStart + (i / segCount) * armLen
		local s1 = sDriveStart + ((i + 1) / segCount) * armLen
		local col = if i % 2 == 0 then Color3.fromRGB(220, 38, 38) else Color3.fromRGB(242, 242, 240)
		makePart(folder, "BarrierArmSeg", Vector3.new(0.16, 0.24, (armLen / segCount)), CFrame.lookAt(pt(b, barE, 3.45, (s0 + s1) * 0.5), pt(b, barE, 3.45, s1)), col, Enum.Material.Metal, false)
	end

	local idPlate = makeFacingBox(folder, "IdentifiqueSePlate", pt(b, barE - 0.14, 3.45, (sDriveStart + sDriveEnd) * 0.5), b.west, 5.2, 0.95, 0.10, Color3.fromRGB(245, 245, 242), nil, false)
	local idsg = makeSurfaceGui(idPlate, 52)
	local idlbl = Instance.new("TextLabel")
	idlbl.Size = UDim2.fromScale(1, 1)
	idlbl.BackgroundColor3 = Color3.fromRGB(245, 245, 242)
	idlbl.Font = Enum.Font.GothamBold
	idlbl.Text = "IDENTIFIQUE-SE"
	idlbl.TextColor3 = Color3.fromRGB(22, 24, 26)
	idlbl.TextScaled = true
	idlbl.Parent = idsg

	-- Gradil sul + ligação com muro sul + banner institucional IFSul + placa acessível
	addTubularFencePanel(folder, "SouthFrontFence", pt(b, fenceE, 0, sDriveEnd), pt(b, fenceE, 0, sSouthEnd), 7.6, 0.85, true)
	addTubularFencePanel(folder, "SouthWallReturn", pt(b, fenceE, 0, sSouthEnd), pt(b, -14.0, 0, 47.0), 7.6, 0.85, true)

	local banner = makeFacingBox(folder, "SouthIfsulBanner", pt(b, fenceE - 0.26, 4.1, 43.4), b.west, 9.2, 5.0, 0.14, Color3.fromRGB(242, 244, 242))
	local bsg = makeSurfaceGui(banner, 42)
	local bFrame = Instance.new("Frame")
	bFrame.Size = UDim2.fromScale(1, 1)
	bFrame.BackgroundColor3 = Color3.fromRGB(242, 244, 242)
	bFrame.BorderSizePixel = 0
	bFrame.Parent = bsg

	local headerBar = Instance.new("Frame")
	headerBar.Size = UDim2.fromScale(1, 0.28)
	headerBar.BackgroundColor3 = COLOR_IF_GREEN
	headerBar.BorderSizePixel = 0
	headerBar.Parent = bFrame

	local headerTxt = Instance.new("TextLabel")
	headerTxt.Size = UDim2.fromScale(0.92, 0.80)
	headerTxt.Position = UDim2.fromScale(0.04, 0.10)
	headerTxt.BackgroundTransparency = 1
	headerTxt.Font = Enum.Font.GothamBold
	headerTxt.Text = "INSTITUTO FEDERAL SUL-RIO-GRANDENSE"
	headerTxt.TextColor3 = Color3.new(1, 1, 1)
	headerTxt.TextScaled = true
	headerTxt.Parent = headerBar

	local bodyBand = Instance.new("Frame")
	bodyBand.Position = UDim2.fromScale(0.05, 0.34)
	bodyBand.Size = UDim2.fromScale(0.90, 0.56)
	bodyBand.BackgroundColor3 = Color3.fromRGB(224, 232, 226)
	bodyBand.BorderSizePixel = 0
	bodyBand.Parent = bFrame

	local bodyTxt = Instance.new("TextLabel")
	bodyTxt.Position = UDim2.fromScale(0.05, 0.14)
	bodyTxt.Size = UDim2.fromScale(0.90, 0.72)
	bodyTxt.BackgroundTransparency = 1
	bodyTxt.Font = Enum.Font.GothamBold
	bodyTxt.Text = "CÂMPUS SAPUCAIA DO SUL\nEnsino Público, Gratuito e de Qualidade"
	bodyTxt.TextColor3 = Color3.fromRGB(26, 48, 32)
	bodyTxt.TextScaled = true
	bodyTxt.Parent = bodyBand

	-- Placa azul acessível ao lado do banner
	local accessSign = makeFacingBox(folder, "AccessibleParkingSign", pt(b, fenceE - 0.26, 4.1, 49.4), b.west, 2.3, 2.7, 0.12, Color3.fromRGB(240, 242, 245))
	local asg = makeSurfaceGui(accessSign, 48)
	local aBg = Instance.new("Frame")
	aBg.Size = UDim2.fromScale(1, 1)
	aBg.BackgroundColor3 = Color3.fromRGB(242, 244, 246)
	aBg.BorderSizePixel = 0
	aBg.Parent = asg

	local aBlue = Instance.new("Frame")
	aBlue.Position = UDim2.fromScale(0.08, 0.08)
	aBlue.Size = UDim2.fromScale(0.84, 0.68)
	aBlue.BackgroundColor3 = COLOR_BUS_BLUE
	aBlue.BorderSizePixel = 0
	aBlue.Parent = aBg

	local aIcon = Instance.new("TextLabel")
	aIcon.Size = UDim2.fromScale(1, 1)
	aIcon.BackgroundTransparency = 1
	aIcon.Font = Enum.Font.GothamBold
	aIcon.Text = "♿"
	aIcon.TextColor3 = Color3.new(1, 1, 1)
	aIcon.TextScaled = true
	aIcon.Parent = aBlue

	local aText = Instance.new("TextLabel")
	aText.Position = UDim2.fromScale(0.06, 0.78)
	aText.Size = UDim2.fromScale(0.88, 0.16)
	aText.BackgroundTransparency = 1
	aText.Font = Enum.Font.GothamBold
	aText.Text = "ACESSÍVEL"
	aText.TextColor3 = COLOR_SIGN_INK
	aText.TextScaled = true
	aText.Parent = aBg
end

local function buildNorthSidewalkDetails(folder: Folder, b: FrameBasis)
	-- Tela de arame e mourões sobre o muro norte de blocos (-237.15, Z ~ [-12.6, +4.0])
	local wallE = -14.35
	local s0, s1 = -56.0, -39.8
	for s = s0 + 0.5, s1 - 0.5, 5.2 do
		makeSegmentCylinder(folder, "WallMeshPost", pt(b, wallE, 3.85, s), pt(b, wallE, 7.15, s), 0.20, COLOR_GALV_STEEL, Enum.Material.Metal, false)
	end
	local meshPanel = makePart(
		folder,
		"WallWireMesh",
		Vector3.new(s1 - s0, 2.9, 0.08),
		CFrame.lookAt(pt(b, wallE, 5.4, (s0 + s1) * 0.5), pt(b, wallE, 5.4, (s0 + s1) * 0.5) + b.west),
		Color3.fromRGB(165, 172, 176),
		Enum.Material.Metal,
		false
	)
	meshPanel.Transparency = 0.66

	for _, wireY in ipairs({ 6.95, 7.12 }) do
		makePart(
			folder,
			"WallTopWire",
			Vector3.new(s1 - s0, 0.06, 0.06),
			CFrame.lookAt(pt(b, wallE, wireY, (s0 + s1) * 0.5), pt(b, wallE, wireY, (s0 + s1) * 0.5) + b.west),
			COLOR_GALV_STEEL,
			Enum.Material.Metal,
			false
		)
	end

	-- Meio-fio amarelo baixo apenas no trecho norte sob a árvore
	local curbCenter = pt(b, -21.0, 0.18, -45.5)
	makePart(folder, "NorthYellowCurb", Vector3.new(0.65, 0.36, 19.0), CFrame.lookAt(curbCenter, curbCenter + b.south), Color3.fromRGB(220, 180, 42), Enum.Material.Concrete, true)

	-- Árvore inclinada com base caiada de branco na calçada norte
	local t0 = pt(b, -19.2, 0.0, -43.2)
	local t1 = pt(b, -18.8, 2.5, -44.6)
	local t2 = pt(b, -18.0, 5.2, -43.4)
	local t3 = pt(b, -17.4, 8.6, -41.4)
	local t3N = pt(b, -17.8, 8.4, -46.2)

	local whiteWash = Color3.fromRGB(232, 230, 224)
	local barkCol = Color3.fromRGB(76, 56, 42)
	makeSegmentCylinder(folder, "TreeBaseWhite", t0, t1, 1.55, whiteWash, Enum.Material.Concrete, true)
	makeSegmentCylinder(folder, "TreeElbowWhite", t1, t1 + Vector3.new(0, 0.9, 0), 1.32, whiteWash, Enum.Material.Concrete, true)
	makeSegmentCylinder(folder, "TreeTrunkUpper", t1, t2, 1.15, barkCol, Enum.Material.Wood, true)
	makeSegmentCylinder(folder, "TreeBranchR", t2, t3, 0.78, barkCol, Enum.Material.Wood, false)
	makeSegmentCylinder(folder, "TreeBranchL", t2, t3N, 0.74, barkCol, Enum.Material.Wood, false)

	local canopySpecs = {
		{ -17.5, 11.8, -42.5, 11.5, 6.8, 12.0, Color3.fromRGB(64, 112, 46) },
		{ -18.6, 13.6, -45.8, 9.5, 6.2, 10.5, Color3.fromRGB(74, 122, 52) },
		{ -16.8, 11.2, -39.0, 8.8, 5.6, 9.2, Color3.fromRGB(68, 118, 48) },
		{ -18.0, 15.8, -42.8, 8.5, 5.2, 9.5, Color3.fromRGB(84, 134, 58) },
		{ -19.5, 12.2, -48.5, 7.8, 5.0, 8.2, Color3.fromRGB(72, 118, 50) },
		-- Pontos floridos rosados sutis da primavera (Street View out/2026 e set/2024)
		{ -20.4, 13.4, -40.8, 4.6, 3.0, 4.8, Color3.fromRGB(222, 162, 182) },
		{ -19.8, 15.8, -45.5, 4.8, 3.2, 5.0, Color3.fromRGB(228, 170, 190) },
		{ -17.6, 13.2, -37.2, 4.4, 2.8, 4.4, Color3.fromRGB(218, 158, 178) },
	}
	for idx, c in ipairs(canopySpecs) do
		local puff = makePart(
			folder,
			"TreeCanopy_" .. tostring(idx),
			Vector3.new(c[4] :: number, c[5] :: number, c[6] :: number),
			CFrame.new(pt(b, c[1] :: number, c[2] :: number, c[3] :: number)),
			c[7] :: Color3,
			Enum.Material.Grass,
			false
		)
		puff.Shape = Enum.PartType.Ball
	end

	-- Placa azul vertical "ESCOLAR" junto ao meio-fio à frente da árvore
	local signPos = pt(b, -20.0, 0, -40.8)
	makeSegmentCylinder(folder, "EscolarPost", signPos, signPos + Vector3.new(0, 9.0, 0), 0.22, COLOR_GALV_STEEL, Enum.Material.Metal, true)

	local signFaceDir = (b.west * 0.82 + b.north * 0.57).Unit
	local escolarPlate = makeFacingBox(folder, "EscolarSign", signPos + Vector3.new(0, 7.6, 0), signFaceDir, 1.9, 2.6, 0.12, COLOR_BUS_BLUE, Enum.Material.Metal)
	local esg = makeSurfaceGui(escolarPlate, 58)
	local eBg = Instance.new("Frame")
	eBg.Size = UDim2.fromScale(1, 1)
	eBg.BackgroundColor3 = COLOR_BUS_BLUE
	eBg.BorderSizePixel = 0
	eBg.Parent = esg

	local eStroke = Instance.new("UIStroke")
	eStroke.Color = Color3.new(1, 1, 1)
	eStroke.Thickness = 2
	eStroke.Parent = eBg

	local busBadge = Instance.new("Frame")
	busBadge.Position = UDim2.fromScale(0.18, 0.08)
	busBadge.Size = UDim2.fromScale(0.64, 0.46)
	busBadge.BackgroundColor3 = Color3.new(1, 1, 1)
	busBadge.BorderSizePixel = 0
	busBadge.Parent = eBg
	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(1, 0)
	bCorner.Parent = busBadge

	local busEmoji = Instance.new("TextLabel")
	busEmoji.Size = UDim2.fromScale(0.84, 0.84)
	busEmoji.Position = UDim2.fromScale(0.08, 0.08)
	busEmoji.BackgroundTransparency = 1
	busEmoji.Font = Enum.Font.GothamBold
	busEmoji.Text = "🚌"
	busEmoji.TextColor3 = COLOR_BUS_BLUE
	busEmoji.TextScaled = true
	busEmoji.Parent = busBadge

	local eBand = Instance.new("TextLabel")
	eBand.Position = UDim2.fromScale(0.08, 0.62)
	eBand.Size = UDim2.fromScale(0.84, 0.25)
	eBand.BackgroundColor3 = Color3.new(1, 1, 1)
	eBand.Font = Enum.Font.GothamBold
	eBand.Text = "ESCOLAR"
	eBand.TextColor3 = COLOR_BUS_BLUE
	eBand.TextScaled = true
	eBand.Parent = eBg
end

function EntranceEnhancer.Apply(campusRoot: Instance): Folder
	local buildings = campusRoot:WaitForChild("Buildings")
	local props = campusRoot:WaitForChild("Props")
	local signage = campusRoot:WaitForChild("Signage")
	local lights = campusRoot:WaitForChild("Lights")

	local basis = detectGuaritaBasis(buildings)
	sanitizeBaseline(campusRoot, buildings, props, signage, lights, basis)

	local folder = Instance.new("Folder")
	folder.Name = "EntranceEnhanced"
	folder.Parent = campusRoot

	buildGuaritaFacade(folder, basis)
	buildZebraAndTwinLamppost(folder, lights, basis)
	buildNorthWalkwayAndFence(folder, basis)
	buildSouthGatesBannerAndSign(folder, basis)
	buildNorthSidewalkDetails(folder, basis)

	return folder
end

return EntranceEnhancer
