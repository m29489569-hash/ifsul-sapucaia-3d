--!strict
-- HUD institucional do IFSul — Câmpus Sapucaia do Sul (Roblox)
-- Exibe localização em tempo real (sala/setor), alternância Dia/Noite [N] e Buscador de Salas/POIs [G].

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local CampusData = require(IFSulFolder:WaitForChild("CampusData"))
local remotes = IFSulFolder:WaitForChild("Remotes")
local toggleDayNightRemote = remotes:WaitForChild("ToggleDayNight") :: RemoteEvent
local teleportRemote = remotes:WaitForChild("TeleportToLocation") :: RemoteEvent

-- Remove HUD antigo se recarregado
local oldGui = playerGui:FindFirstChild("IFSulHUD")
if oldGui then oldGui:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "IFSulHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.Parent = playerGui

-- Barra superior esquerda: título + sala atual
local topPill = Instance.new("Frame")
topPill.Name = "LocationPill"
topPill.Size = UDim2.fromOffset(330, 56)
topPill.Position = UDim2.fromOffset(16, 16)
topPill.BackgroundColor3 = Config.Colors.PanelBg
topPill.BackgroundTransparency = 0.12
topPill.Parent = screenGui

local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(0, 10)
pillCorner.Parent = topPill

local pillStroke = Instance.new("UIStroke")
pillStroke.Color = Config.Colors.PanelBorder
pillStroke.Thickness = 1.5
pillStroke.Parent = topPill

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -20, 0, 22)
titleLbl.Position = UDim2.fromOffset(12, 6)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 14
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextColor3 = Config.Colors.IFSulGreen
titleLbl.Text = "IFSul — Câmpus Sapucaia do Sul"
titleLbl.Parent = topPill

local locLbl = Instance.new("TextLabel")
locLbl.Size = UDim2.new(1, -20, 0, 20)
locLbl.Position = UDim2.fromOffset(12, 29)
locLbl.BackgroundTransparency = 1
locLbl.Font = Enum.Font.Gotham
locLbl.TextSize = 13
locLbl.TextXAlignment = Enum.TextXAlignment.Left
locLbl.TextColor3 = Config.Colors.TextPrimary
locLbl.Text = "Área Externa do Câmpus"
locLbl.Parent = topPill

-- Botões de ação (Buscador [G] e Dia/Noite [N])
local function makeActionBtn(text: string, xOffset: number, width: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(width, 36)
	btn.Position = UDim2.fromOffset(xOffset, 80)
	btn.BackgroundColor3 = Config.Colors.PanelBg
	btn.BackgroundTransparency = 0.12
	btn.Font = Enum.Font.GothamSemibold
	btn.TextSize = 13
	btn.TextColor3 = Config.Colors.TextPrimary
	btn.Text = text
	btn.Parent = screenGui

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = btn

	local s = Instance.new("UIStroke")
	s.Color = Config.Colors.PanelBorder
	s.Thickness = 1.2
	s.Parent = btn
	return btn
end

local finderBtn = makeActionBtn("Salas & POIs [G]", 16, 155)
local dayNightBtn = makeActionBtn("Dia / Noite [N]", 180, 140)

-- Modal Buscador de Salas & POIs
local modal = Instance.new("Frame")
modal.Name = "RoomFinder"
modal.Size = UDim2.fromOffset(420, 440)
modal.Position = UDim2.new(0.5, -210, 0.5, -220)
modal.BackgroundColor3 = Config.Colors.PanelBg
modal.BackgroundTransparency = 0.06
modal.Visible = false
modal.Parent = screenGui

local modalCorner = Instance.new("UICorner")
modalCorner.CornerRadius = UDim.new(0, 12)
modalCorner.Parent = modal

local modalStroke = Instance.new("UIStroke")
modalStroke.Color = Config.Colors.PanelBorder
modalStroke.Thickness = 1.8
modalStroke.Parent = modal

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -24, 0, 36)
searchBox.Position = UDim2.fromOffset(12, 12)
searchBox.BackgroundColor3 = Color3.fromRGB(26, 34, 42)
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 14
searchBox.TextColor3 = Config.Colors.TextPrimary
searchBox.PlaceholderText = "Buscar sala (ex: 112, Cantina, Biblioteca, Auditório)..."
searchBox.PlaceholderColor3 = Config.Colors.TextMuted
searchBox.ClearTextOnFocus = false
searchBox.Text = ""
searchBox.Parent = modal

local sbCorner = Instance.new("UICorner")
sbCorner.CornerRadius = UDim.new(0, 8)
sbCorner.Parent = searchBox

local listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.new(1, -24, 1, -66)
listFrame.Position = UDim2.fromOffset(12, 56)
listFrame.BackgroundTransparency = 1
listFrame.ScrollBarThickness = 6
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.Parent = modal

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = listFrame

type SearchItem = {
	key: string,
	label: string,
	searchText: string,
	badgeColor: Color3,
}

local allItems: { SearchItem } = {
	{
		key = "spawn",
		label = "Portaria Principal (Spawn)",
		searchText = "portaria principal entrada spawn inicio",
		badgeColor = Config.Colors.IFSulGreen,
	},
}

for _, poi in ipairs(CampusData.POIs) do
	table.insert(allItems, {
		key = "poi:" .. poi.id,
		label = "POI • " .. poi.title,
		searchText = string.lower(poi.title .. " " .. poi.subtitle),
		badgeColor = Config.Colors.IFSulRed,
	})
end

for _, room in ipairs(CampusData.Rooms) do
	local sec = CampusData.Sectors[room.sector]
	local badge = if sec then sec.color else Config.Colors.IFSulGreen
	local aliasStr = table.concat(room.aliases, " ")
	local label = if room.code ~= "" then (room.code .. " — " .. room.name) else room.name
	table.insert(allItems, {
		key = "room:" .. room.id,
		label = label,
		searchText = string.lower(room.code .. " " .. room.name .. " " .. aliasStr .. " setor " .. room.sector),
		badgeColor = badge,
	})
end

local function rebuildList(query: string)
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local q = string.lower(query)
	local shown = 0
	for _, item in ipairs(allItems) do
		if q == "" or string.find(item.searchText, q, 1, true) then
			shown += 1
			if shown > 40 then
				break
			end
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, -8, 0, 34)
			row.BackgroundColor3 = Color3.fromRGB(28, 36, 46)
			row.Font = Enum.Font.Gotham
			row.TextSize = 13
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextColor3 = Config.Colors.TextPrimary
			row.Text = "   " .. item.label
			row.Parent = listFrame

			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 6)
			rc.Parent = row

			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(0, 4, 1, -8)
			bar.Position = UDim2.fromOffset(4, 4)
			bar.BackgroundColor3 = item.badgeColor
			bar.BorderSizePixel = 0
			bar.Parent = row

			row.MouseButton1Click:Connect(function()
				teleportRemote:FireServer(item.key)
				modal.Visible = false
			end)
		end
	end
end

rebuildList("")

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	rebuildList(searchBox.Text)
end)

local function toggleFinder()
	modal.Visible = not modal.Visible
	if modal.Visible then
		searchBox:CaptureFocus()
	end
end

finderBtn.MouseButton1Click:Connect(toggleFinder)
dayNightBtn.MouseButton1Click:Connect(function()
	toggleDayNightRemote:FireServer()
end)

toggleDayNightRemote.OnClientEvent:Connect(function(night: boolean)
	dayNightBtn.Text = if night then "Modo Noite [N]" else "Modo Dia [N]"
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.G then
		toggleFinder()
	elseif input.KeyCode == Enum.KeyCode.N then
		toggleDayNightRemote:FireServer()
	elseif input.KeyCode == Enum.KeyCode.Escape and modal.Visible then
		modal.Visible = false
	end
end)

-- Detecta em tempo real em qual sala o jogador está
local accum = 0
RunService.Heartbeat:Connect(function(dt: number)
	accum += dt
	if accum < 0.35 then
		return
	end
	accum = 0
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local pos = hrp.Position
	local foundText = "Área Externa do Câmpus"
	for _, room in ipairs(CampusData.Rooms) do
		local dx = pos.X - room.center.X
		local dz = pos.Z - room.center.Z
		local halfW = room.size.X * 0.5
		local halfD = room.size.Y * 0.5
		if math.abs(dx) <= halfW + 1 and math.abs(dz) <= halfD + 1 then
			local rad = math.rad(-room.rotDeg)
			local c, s = math.cos(rad), math.sin(rad)
			local lx = dx * c - dz * s
			local lz = dx * s + dz * c
			if math.abs(lx) <= halfW and math.abs(lz) <= halfD then
				foundText = if room.code ~= "" then ("Sala " .. room.code .. " — " .. room.name) else room.name
				break
			end
		end
	end
	locLbl.Text = foundText
end)
