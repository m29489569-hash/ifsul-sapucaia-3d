--!strict
-- HUD institucional do IFSul — Câmpus Sapucaia do Sul (Roblox)
-- Exibe contador de moedas, Buscador de Salas/POIs [G],
-- alternância Dia/Noite local [N] e Sprint (Shift no PC / botão padrão no celular).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local CampusData = require(IFSulFolder:WaitForChild("CampusData"))
local ShopCatalog = require(IFSulFolder:WaitForChild("ShopCatalog"))
local remotes = IFSulFolder:WaitForChild("Remotes")
local teleportRemote = remotes:WaitForChild("TeleportToLocation") :: RemoteEvent
local shopGetStateRF = remotes:WaitForChild("ShopGetState") :: RemoteFunction
local shopBuyCoinsRF = remotes:WaitForChild("ShopBuyCoins") :: RemoteFunction
local shopBuyRobuxRF = remotes:WaitForChild("ShopBuyRobux") :: RemoteFunction
local shopOwnedUpdatedRE = remotes:WaitForChild("ShopOwnedUpdated") :: RemoteEvent

local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Remove HUD antigo se recarregado
local oldGui = playerGui:FindFirstChild("IFSulHUD")
if oldGui then
	oldGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "IFSulHUD"
screenGui.ResetOnSpawn = false
screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Barra superior esquerda responsiva (Contador de Moedas + Botão Loja)
-- Usa CoreUISafeInsets para respeitar Topbar, notches/bordas arredondadas e overscan de TV.
local topLeftHud = Instance.new("Frame")
topLeftHud.Name = "TopLeftHud"
topLeftHud.AnchorPoint = Vector2.new(0, 0)
topLeftHud.AutomaticSize = Enum.AutomaticSize.XY
topLeftHud.Size = UDim2.fromOffset(0, 46)
topLeftHud.Position = UDim2.fromOffset(16, 12)
topLeftHud.BackgroundTransparency = 1
topLeftHud.Parent = screenGui

local topLeftLayout = Instance.new("UIListLayout")
topLeftLayout.FillDirection = Enum.FillDirection.Horizontal
topLeftLayout.VerticalAlignment = Enum.VerticalAlignment.Center
topLeftLayout.Padding = UDim.new(0, 8)
topLeftLayout.SortOrder = Enum.SortOrder.LayoutOrder
topLeftLayout.Parent = topLeftHud

local coinCounter = Instance.new("Frame")
coinCounter.Name = "CoinCounter"
coinCounter.LayoutOrder = 1
coinCounter.AnchorPoint = Vector2.new(0, 0)
coinCounter.AutomaticSize = Enum.AutomaticSize.X
coinCounter.Size = UDim2.fromOffset(0, 46)
coinCounter.BackgroundColor3 = Config.Colors.PanelBg
coinCounter.BackgroundTransparency = 0.22
coinCounter.Parent = topLeftHud

local shopBtn = Instance.new("TextButton")
shopBtn.Name = "ShopButton"
shopBtn.LayoutOrder = 2
shopBtn.AutomaticSize = Enum.AutomaticSize.X
shopBtn.Size = UDim2.fromOffset(0, 46)
shopBtn.BackgroundColor3 = Config.Colors.IFSulGreen
shopBtn.BackgroundTransparency = 0.1
shopBtn.Font = Enum.Font.GothamBold
shopBtn.TextSize = 16
shopBtn.TextColor3 = Color3.new(1, 1, 1)
shopBtn.Text = "Loja"
shopBtn.AutoButtonColor = true
shopBtn.Parent = topLeftHud

local shopBtnCorner = Instance.new("UICorner")
shopBtnCorner.CornerRadius = UDim.new(1, 0)
shopBtnCorner.Parent = shopBtn

local shopBtnStroke = Instance.new("UIStroke")
shopBtnStroke.Color = Color3.fromRGB(224, 180, 64)
shopBtnStroke.Thickness = 1.6
shopBtnStroke.Transparency = 0.15
shopBtnStroke.Parent = shopBtn

local shopBtnPad = Instance.new("UIPadding")
shopBtnPad.PaddingLeft = UDim.new(0, 16)
shopBtnPad.PaddingRight = UDim.new(0, 16)
shopBtnPad.Parent = shopBtn

local coinScale = Instance.new("UIScale")
coinScale.Scale = 1
coinScale.Parent = coinCounter

local coinConstraint = Instance.new("UISizeConstraint")
coinConstraint.MinSize = Vector2.new(124, 46)
coinConstraint.MaxSize = Vector2.new(320, 64)
coinConstraint.Parent = coinCounter

local coinCorner = Instance.new("UICorner")
coinCorner.CornerRadius = UDim.new(1, 0) -- Cápsula/pílula completa
coinCorner.Parent = coinCounter

local coinStroke = Instance.new("UIStroke")
coinStroke.Color = Color3.fromRGB(224, 180, 64)
coinStroke.Thickness = 1.6
coinStroke.Transparency = 0.1
coinStroke.Parent = coinCounter

local coinPadding = Instance.new("UIPadding")
coinPadding.PaddingLeft = UDim.new(0, 7)
coinPadding.PaddingRight = UDim.new(0, 16)
coinPadding.Parent = coinCounter

local coinLayout = Instance.new("UIListLayout")
coinLayout.FillDirection = Enum.FillDirection.Horizontal
coinLayout.VerticalAlignment = Enum.VerticalAlignment.Center
coinLayout.Padding = UDim.new(0, 8)
coinLayout.SortOrder = Enum.SortOrder.LayoutOrder
coinLayout.Parent = coinCounter

local coinIcon = Instance.new("ImageLabel")
coinIcon.Name = "CoinIcon"
coinIcon.LayoutOrder = 1
coinIcon.Size = UDim2.fromOffset(34, 34)
coinIcon.BackgroundTransparency = 1
coinIcon.ScaleType = Enum.ScaleType.Fit
coinIcon.Image = Config.CoinIconAssetId
coinIcon.Parent = coinCounter

local coinIconAspect = Instance.new("UIAspectRatioConstraint")
coinIconAspect.AspectRatio = 1
coinIconAspect.Parent = coinIcon

local coinLbl = Instance.new("TextLabel")
coinLbl.Name = "CoinAmount"
coinLbl.LayoutOrder = 2
coinLbl.AutomaticSize = Enum.AutomaticSize.X
coinLbl.Size = UDim2.fromOffset(0, 34)
coinLbl.BackgroundTransparency = 1
coinLbl.Font = Enum.Font.GothamBold
coinLbl.TextSize = 20
coinLbl.TextXAlignment = Enum.TextXAlignment.Left
coinLbl.TextColor3 = Config.Colors.TextPrimary
coinLbl.TextStrokeColor3 = Color3.fromRGB(10, 14, 18)
coinLbl.TextStrokeTransparency = 0.65
coinLbl.Text = "0"
coinLbl.Parent = coinCounter

type CoinProfile = {
	height: number,
	minWidth: number,
	iconSize: number,
	textSize: number,
	padLeft: number,
	padRight: number,
	gap: number,
	posX: number,
	posY: number,
	strokeThickness: number,
}

local COIN_PROFILES: { [string]: CoinProfile } = {
	Phone = {
		height = 36,
		minWidth = 92,
		iconSize = 26,
		textSize = 15,
		padLeft = 5,
		padRight = 12,
		gap = 6,
		posX = 12,
		posY = 8,
		strokeThickness = 1.4,
	},
	Tablet = {
		height = 42,
		minWidth = 112,
		iconSize = 30,
		textSize = 18,
		padLeft = 6,
		padRight = 14,
		gap = 8,
		posX = 16,
		posY = 12,
		strokeThickness = 1.5,
	},
	Desktop = {
		height = 46,
		minWidth = 124,
		iconSize = 34,
		textSize = 20,
		padLeft = 7,
		padRight = 16,
		gap = 8,
		posX = 16,
		posY = 12,
		strokeThickness = 1.6,
	},
	Console = {
		height = 58,
		minWidth = 156,
		iconSize = 42,
		textSize = 26,
		padLeft = 9,
		padRight = 20,
		gap = 10,
		posX = 32,
		posY = 24,
		strokeThickness = 2.0,
	},
}

local function detectDeviceProfile(): string
	if GuiService:IsTenFootInterface() then
		return "Console"
	end
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local minSide = math.min(vp.X, vp.Y)
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		if minSide < 550 then
			return "Phone"
		end
		return "Tablet"
	end
	if minSide < 520 then
		return "Phone"
	elseif vp.X < 1050 then
		return "Tablet"
	end
	return "Desktop"
end

local function applyCoinResponsiveLayout()
	local profileName = detectDeviceProfile()
	local p = COIN_PROFILES[profileName] or COIN_PROFILES.Desktop
	topLeftHud.Position = UDim2.fromOffset(p.posX, p.posY)
	topLeftLayout.Padding = UDim.new(0, p.gap)
	coinCounter.Size = UDim2.fromOffset(0, p.height)
	coinConstraint.MinSize = Vector2.new(p.minWidth, p.height)
	coinConstraint.MaxSize = Vector2.new(340, p.height)
	coinStroke.Thickness = p.strokeThickness
	coinPadding.PaddingLeft = UDim.new(0, p.padLeft)
	coinPadding.PaddingRight = UDim.new(0, p.padRight)
	coinLayout.Padding = UDim.new(0, p.gap)
	coinIcon.Size = UDim2.fromOffset(p.iconSize, p.iconSize)
	coinLbl.Size = UDim2.fromOffset(0, p.iconSize)
	coinLbl.TextSize = p.textSize
	shopBtn.Size = UDim2.fromOffset(0, p.height)
	shopBtn.TextSize = math.max(13, p.textSize - 2)
	shopBtnStroke.Thickness = p.strokeThickness
	shopBtnPad.PaddingLeft = UDim.new(0, p.padRight)
	shopBtnPad.PaddingRight = UDim.new(0, p.padRight)
end

local function bindViewportResize(cam: Camera?)
	if not cam then
		return
	end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyCoinResponsiveLayout)
end

applyCoinResponsiveLayout()
bindViewportResize(Workspace.CurrentCamera)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindViewportResize(Workspace.CurrentCamera)
	applyCoinResponsiveLayout()
end)

local function formatCoins(amount: number): string
	local n = math.max(0, math.floor(amount))
	if n >= 1_000_000_000 then
		return (string.format("%.1fB", n / 1_000_000_000):gsub("%.0B$", "B"))
	elseif n >= 1_000_000 then
		return (string.format("%.1fM", n / 1_000_000):gsub("%.0M$", "M"))
	elseif n >= 10_000 then
		return (string.format("%.1fK", n / 1_000):gsub("%.0K$", "K"))
	end
	local s = tostring(n)
	local formatted = string.reverse(s):gsub("(%d%d%d)", "%1."):reverse()
	return (formatted:gsub("^%.", ""))
end

local lastCoins = 0
local popInInfo = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local popOutInfo = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function updateCoinsDisplay()
	local raw = player:GetAttribute("Coins")
	local value = if typeof(raw) == "number" then raw else 0
	coinLbl.Text = formatCoins(value)
	if value > lastCoins then
		local tIn = TweenService:Create(coinScale, popInInfo, { Scale = 1.12 })
		tIn:Play()
		tIn.Completed:Connect(function()
			TweenService:Create(coinScale, popOutInfo, { Scale = 1 }):Play()
		end)
	end
	lastCoins = value
end

updateCoinsDisplay()
player:GetAttributeChangedSignal("Coins"):Connect(updateCoinsDisplay)

-- Lógica de Sprint (Shift no PC e botão padrão de correr no celular)
local isSprinting = false

local function applySprintToCharacter(char: Model?)
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = if isSprinting then Config.SprintSpeed else Config.WalkSpeed
	end
end

local function setSprinting(active: boolean)
	isSprinting = active
	applySprintToCharacter(player.Character)
end

player.CharacterAdded:Connect(function(char: Model)
	char:WaitForChild("Humanoid")
	applySprintToCharacter(char)
end)

local function handleSprintAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		setSprinting(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprinting(false)
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction(
	"IFSulSprint",
	handleSprintAction,
	true,
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.RightShift
)
ContextActionService:SetTitle("IFSulSprint", "Correr")

-- Lógica de Dia / Noite LOCAL (cada jogador escolhe seu horário sem afetar outros jogadores)
local isNight = false

local function applyLocalLighting(night: boolean)
	isNight = night
	local preset = if night then Config.Lighting.Night else Config.Lighting.Day
	Lighting.ClockTime = preset.ClockTime
	Lighting.Brightness = preset.Brightness
	Lighting.OutdoorAmbient = preset.OutdoorAmbient
	Lighting.GeographicLatitude = Config.GeographicLatitude

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = preset.AtmosphereDensity
		atmosphere.Color = preset.AtmosphereColor
		atmosphere.Decay = preset.AtmosphereDecay
		atmosphere.Haze = preset.AtmosphereHaze
	end

	local campus = Workspace:FindFirstChild("IFSul_Campus")
	if campus then
		local lightsFolder = campus:FindFirstChild("Lights")
		if lightsFolder then
			for _, desc in ipairs(lightsFolder:GetDescendants()) do
				if desc:IsA("PointLight") then
					local alwaysOn = desc:GetAttribute("AlwaysOn") == true
					desc.Enabled = alwaysOn or night
					if alwaysOn then
						local targetB = if night then desc:GetAttribute("NightBrightness") else desc:GetAttribute("DayBrightness")
						if typeof(targetB) == "number" then
							desc.Brightness = targetB
						end
					end
				end
			end
		end
	end
end

-- Backdrop clicável para fechar o modal no celular ou PC
local modalBackdrop = Instance.new("TextButton")
modalBackdrop.Name = "RoomFinderBackdrop"
modalBackdrop.Size = UDim2.fromScale(1, 1)
modalBackdrop.BackgroundColor3 = Color3.new(0, 0, 0)
modalBackdrop.BackgroundTransparency = 0.55
modalBackdrop.Text = ""
modalBackdrop.AutoButtonColor = false
modalBackdrop.Visible = false
modalBackdrop.ZIndex = 10
modalBackdrop.Parent = screenGui

-- Modal Buscador de Salas & POIs (responsivo para celular paisagem e desktop)
local modal = Instance.new("Frame")
modal.Name = "RoomFinder"
modal.AnchorPoint = Vector2.new(0.5, 0.5)
modal.Position = UDim2.fromScale(0.5, 0.5)
modal.Size = UDim2.fromScale(0.86, 0.78)
modal.BackgroundColor3 = Config.Colors.PanelBg
modal.BackgroundTransparency = 0.05
modal.ZIndex = 11
modal.Parent = modalBackdrop

local modalConstraint = Instance.new("UISizeConstraint")
modalConstraint.MinSize = Vector2.new(260, 220)
modalConstraint.MaxSize = Vector2.new(460, 480)
modalConstraint.Parent = modal

local modalCorner = Instance.new("UICorner")
modalCorner.CornerRadius = UDim.new(0, 12)
modalCorner.Parent = modal

local modalStroke = Instance.new("UIStroke")
modalStroke.Color = Config.Colors.PanelBorder
modalStroke.Thickness = 1.8
modalStroke.Parent = modal

-- Cabeçalho do modal com título e botão Fechar (✕)
local modalHeader = Instance.new("Frame")
modalHeader.Size = UDim2.new(1, -24, 0, 32)
modalHeader.Position = UDim2.fromOffset(12, 10)
modalHeader.BackgroundTransparency = 1
modalHeader.ZIndex = 12
modalHeader.Parent = modal

local modalTitle = Instance.new("TextLabel")
modalTitle.Size = UDim2.new(1, -38, 1, 0)
modalTitle.BackgroundTransparency = 1
modalTitle.Font = Enum.Font.GothamBold
modalTitle.TextSize = 15
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.TextColor3 = Config.Colors.IFSulGreen
modalTitle.Text = "Buscador de Salas & POIs"
modalTitle.ZIndex = 12
modalTitle.Parent = modalHeader

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.Size = UDim2.fromOffset(30, 30)
closeBtn.Position = UDim2.new(1, -30, 0, 1)
closeBtn.BackgroundColor3 = Color3.fromRGB(38, 48, 58)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.TextColor3 = Config.Colors.TextPrimary
closeBtn.Text = "✕"
closeBtn.ZIndex = 12
closeBtn.Parent = modalHeader

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeBtn

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -24, 0, 36)
searchBox.Position = UDim2.fromOffset(12, 48)
searchBox.BackgroundColor3 = Color3.fromRGB(26, 34, 42)
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 13
searchBox.TextColor3 = Config.Colors.TextPrimary
searchBox.PlaceholderText = "Buscar sala (ex: 112, Cantina, Biblioteca, Auditório)..."
searchBox.PlaceholderColor3 = Config.Colors.TextMuted
searchBox.ClearTextOnFocus = false
searchBox.Text = ""
searchBox.ZIndex = 12
searchBox.Parent = modal

local sbCorner = Instance.new("UICorner")
sbCorner.CornerRadius = UDim.new(0, 8)
sbCorner.Parent = searchBox

local countLbl = Instance.new("TextLabel")
countLbl.Size = UDim2.new(1, -24, 0, 18)
countLbl.Position = UDim2.fromOffset(12, 88)
countLbl.BackgroundTransparency = 1
countLbl.Font = Enum.Font.Gotham
countLbl.TextSize = 11
countLbl.TextXAlignment = Enum.TextXAlignment.Left
countLbl.TextColor3 = Config.Colors.TextMuted
countLbl.Text = ""
countLbl.ZIndex = 12
countLbl.Parent = modal

local listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.new(1, -24, 1, -118)
listFrame.Position = UDim2.fromOffset(12, 108)
listFrame.BackgroundTransparency = 1
listFrame.ScrollBarThickness = 6
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.ZIndex = 12
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

local function setFinderVisible(visible: boolean)
	modalBackdrop.Visible = visible
	if visible and not isTouchOnly then
		searchBox:CaptureFocus()
	end
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
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, -8, 0, 34)
			row.BackgroundColor3 = Color3.fromRGB(28, 36, 46)
			row.Font = Enum.Font.Gotham
			row.TextSize = 13
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextTruncate = Enum.TextTruncate.AtEnd
			row.TextColor3 = Config.Colors.TextPrimary
			row.Text = "   " .. item.label
			row.ZIndex = 13
			row.Parent = listFrame

			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 6)
			rc.Parent = row

			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(0, 4, 1, -8)
			bar.Position = UDim2.fromOffset(4, 4)
			bar.BackgroundColor3 = item.badgeColor
			bar.BorderSizePixel = 0
			bar.ZIndex = 14
			bar.Parent = row

			row.MouseButton1Click:Connect(function()
				teleportRemote:FireServer(item.key)
				setFinderVisible(false)
			end)
		end
	end

	countLbl.Text = if shown == 1 then "1 local encontrado" else (tostring(shown) .. " locais encontrados")
end

rebuildList("")

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	rebuildList(searchBox.Text)
end)

closeBtn.MouseButton1Click:Connect(function()
	setFinderVisible(false)
end)
modalBackdrop.MouseButton1Click:Connect(function()
	setFinderVisible(false)
end)

-- ============================================================================
-- LOJA DE ARMAS E ITENS (MOEDAS + ROBUX)
-- ============================================================================
local shopBackdrop = Instance.new("TextButton")
shopBackdrop.Name = "ShopBackdrop"
shopBackdrop.Size = UDim2.fromScale(1, 1)
shopBackdrop.BackgroundColor3 = Color3.new(0, 0, 0)
shopBackdrop.BackgroundTransparency = 0.52
shopBackdrop.Text = ""
shopBackdrop.AutoButtonColor = false
shopBackdrop.Visible = false
shopBackdrop.ZIndex = 20
shopBackdrop.Parent = screenGui

local shopModal = Instance.new("Frame")
shopModal.Name = "ShopModal"
shopModal.AnchorPoint = Vector2.new(0.5, 0.5)
shopModal.Position = UDim2.fromScale(0.5, 0.5)
shopModal.Size = UDim2.fromScale(0.9, 0.84)
shopModal.BackgroundColor3 = Config.Colors.PanelBg
shopModal.BackgroundTransparency = 0.04
shopModal.ZIndex = 21
shopModal.Parent = shopBackdrop

local shopModalConstraint = Instance.new("UISizeConstraint")
shopModalConstraint.MinSize = Vector2.new(300, 260)
shopModalConstraint.MaxSize = Vector2.new(760, 560)
shopModalConstraint.Parent = shopModal

local shopModalCorner = Instance.new("UICorner")
shopModalCorner.CornerRadius = UDim.new(0, 14)
shopModalCorner.Parent = shopModal

local shopModalStroke = Instance.new("UIStroke")
shopModalStroke.Color = Color3.fromRGB(224, 180, 64)
shopModalStroke.Thickness = 1.8
shopModalStroke.Parent = shopModal

-- Cabeçalho da loja
local shopHeader = Instance.new("Frame")
shopHeader.Size = UDim2.new(1, -24, 0, 38)
shopHeader.Position = UDim2.fromOffset(12, 10)
shopHeader.BackgroundTransparency = 1
shopHeader.ZIndex = 22
shopHeader.Parent = shopModal

local shopTitle = Instance.new("TextLabel")
shopTitle.Size = UDim2.new(0.55, 0, 1, 0)
shopTitle.BackgroundTransparency = 1
shopTitle.Font = Enum.Font.GothamBlack
shopTitle.TextSize = 18
shopTitle.TextXAlignment = Enum.TextXAlignment.Left
shopTitle.TextColor3 = Config.Colors.TextPrimary
shopTitle.Text = "Loja do Câmpus"
shopTitle.ZIndex = 22
shopTitle.Parent = shopHeader

local shopBalancePill = Instance.new("Frame")
shopBalancePill.AnchorPoint = Vector2.new(1, 0.5)
shopBalancePill.Position = UDim2.new(1, -40, 0.5, 0)
shopBalancePill.AutomaticSize = Enum.AutomaticSize.X
shopBalancePill.Size = UDim2.fromOffset(0, 30)
shopBalancePill.BackgroundColor3 = Color3.fromRGB(26, 34, 44)
shopBalancePill.ZIndex = 22
shopBalancePill.Parent = shopHeader

local sbPillCorner = Instance.new("UICorner")
sbPillCorner.CornerRadius = UDim.new(1, 0)
sbPillCorner.Parent = shopBalancePill

local sbPillPad = Instance.new("UIPadding")
sbPillPad.PaddingLeft = UDim.new(0, 6)
sbPillPad.PaddingRight = UDim.new(0, 12)
sbPillPad.Parent = shopBalancePill

local sbPillLayout = Instance.new("UIListLayout")
sbPillLayout.FillDirection = Enum.FillDirection.Horizontal
sbPillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
sbPillLayout.Padding = UDim.new(0, 6)
sbPillLayout.Parent = shopBalancePill

local sbCoinIcon = Instance.new("ImageLabel")
sbCoinIcon.Size = UDim2.fromOffset(22, 22)
sbCoinIcon.BackgroundTransparency = 1
sbCoinIcon.ScaleType = Enum.ScaleType.Fit
sbCoinIcon.Image = Config.CoinIconAssetId
sbCoinIcon.ZIndex = 23
sbCoinIcon.Parent = shopBalancePill

local shopBalanceLbl = Instance.new("TextLabel")
shopBalanceLbl.AutomaticSize = Enum.AutomaticSize.X
shopBalanceLbl.Size = UDim2.fromOffset(0, 22)
shopBalanceLbl.BackgroundTransparency = 1
shopBalanceLbl.Font = Enum.Font.GothamBold
shopBalanceLbl.TextSize = 14
shopBalanceLbl.TextColor3 = Color3.fromRGB(250, 214, 92)
shopBalanceLbl.Text = "0"
shopBalanceLbl.ZIndex = 23
shopBalanceLbl.Parent = shopBalancePill

local shopCloseBtn = Instance.new("TextButton")
shopCloseBtn.Size = UDim2.fromOffset(32, 32)
shopCloseBtn.AnchorPoint = Vector2.new(1, 0.5)
shopCloseBtn.Position = UDim2.new(1, 0, 0.5, 0)
shopCloseBtn.BackgroundColor3 = Color3.fromRGB(38, 48, 58)
shopCloseBtn.Font = Enum.Font.GothamBold
shopCloseBtn.TextSize = 15
shopCloseBtn.TextColor3 = Config.Colors.TextPrimary
shopCloseBtn.Text = "X"
shopCloseBtn.ZIndex = 22
shopCloseBtn.Parent = shopHeader

local shopCloseCorner = Instance.new("UICorner")
shopCloseCorner.CornerRadius = UDim.new(0, 8)
shopCloseCorner.Parent = shopCloseBtn

-- Abas de categoria
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -24, 0, 30)
tabBar.Position = UDim2.fromOffset(12, 54)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 22
tabBar.Parent = shopModal

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabLayout.Parent = tabBar

local CATEGORIES = { "Todos", "Armas", "Mobilidade", "Especiais" }
local activeCategory = "Todos"
local tabButtons: { [string]: TextButton } = {}

-- Grade de itens
local shopGridFrame = Instance.new("ScrollingFrame")
shopGridFrame.Size = UDim2.new(1, -24, 1, -130)
shopGridFrame.Position = UDim2.fromOffset(12, 92)
shopGridFrame.BackgroundTransparency = 1
shopGridFrame.ScrollBarThickness = 6
shopGridFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopGridFrame.CanvasSize = UDim2.fromOffset(0, 0)
shopGridFrame.ZIndex = 22
shopGridFrame.Parent = shopModal

local shopGridLayout = Instance.new("UIGridLayout")
shopGridLayout.CellSize = UDim2.fromOffset(224, 152)
shopGridLayout.CellPadding = UDim2.fromOffset(10, 10)
shopGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopGridLayout.Parent = shopGridFrame

local shopGridPad = Instance.new("UIPadding")
shopGridPad.PaddingTop = UDim.new(0, 2)
shopGridPad.PaddingBottom = UDim.new(0, 8)
shopGridPad.Parent = shopGridFrame

-- Barra de status / feedback
local shopToast = Instance.new("TextLabel")
shopToast.Size = UDim2.new(1, -24, 0, 26)
shopToast.AnchorPoint = Vector2.new(0, 1)
shopToast.Position = UDim2.new(0, 12, 1, -8)
shopToast.BackgroundColor3 = Color3.fromRGB(24, 32, 42)
shopToast.Font = Enum.Font.GothamSemibold
shopToast.TextSize = 12
shopToast.TextColor3 = Config.Colors.TextMuted
shopToast.Text = "Colete cartazes pelos corredores para ganhar moedas ou compre com Robux!"
shopToast.ZIndex = 22
shopToast.Parent = shopModal

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 7)
toastCorner.Parent = shopToast

local ownedSet: { [string]: boolean } = {}
local isPurchasing = false

local function setShopToast(msg: string, isOk: boolean?)
	shopToast.Text = msg
	if isOk == true then
		shopToast.TextColor3 = Color3.fromRGB(110, 235, 130)
	elseif isOk == false then
		shopToast.TextColor3 = Color3.fromRGB(252, 165, 110)
	else
		shopToast.TextColor3 = Config.Colors.TextMuted
	end
end

local function updateTabStyles()
	for cat, btn in pairs(tabButtons) do
		local selected = (cat == activeCategory)
		btn.BackgroundColor3 = if selected then Config.Colors.IFSulGreen else Color3.fromRGB(30, 39, 50)
		btn.TextColor3 = if selected then Color3.new(1, 1, 1) else Config.Colors.TextMuted
	end
end

local function rebuildShopGrid()
	for _, child in ipairs(shopGridFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local rawCoins = player:GetAttribute("Coins")
	local currentCoins = if typeof(rawCoins) == "number" then rawCoins else 0
	shopBalanceLbl.Text = formatCoins(currentCoins)

	for idx, item in ipairs(ShopCatalog.Items) do
		if activeCategory == "Todos" or item.category == activeCategory then
			local owned = ownedSet[item.id] == true

			local card = Instance.new("Frame")
			card.Name = "Card_" .. item.id
			card.LayoutOrder = idx
			card.BackgroundColor3 = Color3.fromRGB(24, 32, 42)
			card.ZIndex = 23
			card.Parent = shopGridFrame

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 10)
			cardCorner.Parent = card

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = if owned then Config.Colors.IFSulGreen else item.accentColor
			cardStroke.Thickness = if item.rarity == "Lendário" then 1.8 else 1.2
			cardStroke.Transparency = 0.25
			cardStroke.Parent = card

			-- Faixa superior de raridade
			local accentBar = Instance.new("Frame")
			accentBar.Size = UDim2.new(1, 0, 0, 4)
			accentBar.BackgroundColor3 = item.accentColor
			accentBar.BorderSizePixel = 0
			accentBar.ZIndex = 24
			accentBar.Parent = card

			-- Ícone do item
			local iconBox = Instance.new("Frame")
			iconBox.Size = UDim2.fromOffset(44, 44)
			iconBox.Position = UDim2.fromOffset(10, 12)
			iconBox.BackgroundColor3 = Color3.fromRGB(16, 22, 30)
			iconBox.ZIndex = 24
			iconBox.Parent = card

			local iconCorner = Instance.new("UICorner")
			iconCorner.CornerRadius = UDim.new(0, 8)
			iconCorner.Parent = iconBox

			if item.icon ~= "" then
				local img = Instance.new("ImageLabel")
				img.Size = UDim2.fromScale(0.84, 0.84)
				img.AnchorPoint = Vector2.new(0.5, 0.5)
				img.Position = UDim2.fromScale(0.5, 0.5)
				img.BackgroundTransparency = 1
				img.ScaleType = Enum.ScaleType.Fit
				img.Image = item.icon
				img.ZIndex = 25
				img.Parent = iconBox
			else
				local mono = Instance.new("TextLabel")
				mono.Size = UDim2.fromScale(1, 1)
				mono.BackgroundTransparency = 1
				mono.Font = Enum.Font.GothamBlack
				mono.TextSize = 18
				mono.TextColor3 = item.accentColor
				mono.Text = "🔦"
				mono.ZIndex = 25
				mono.Parent = iconBox
			end

			-- Nome + raridade
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -66, 0, 20)
			nameLbl.Position = UDim2.fromOffset(60, 12)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextSize = 13
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.TextColor3 = Config.Colors.TextPrimary
			nameLbl.Text = item.name
			nameLbl.ZIndex = 24
			nameLbl.Parent = card

			local rarityLbl = Instance.new("TextLabel")
			rarityLbl.Size = UDim2.new(1, -66, 0, 16)
			rarityLbl.Position = UDim2.fromOffset(60, 32)
			rarityLbl.BackgroundTransparency = 1
			rarityLbl.Font = Enum.Font.GothamSemibold
			rarityLbl.TextSize = 11
			rarityLbl.TextXAlignment = Enum.TextXAlignment.Left
			rarityLbl.TextColor3 = item.accentColor
			rarityLbl.Text = item.rarity .. " • " .. item.category
			rarityLbl.ZIndex = 24
			rarityLbl.Parent = card

			-- Descrição
			local descLbl = Instance.new("TextLabel")
			descLbl.Size = UDim2.new(1, -20, 0, 42)
			descLbl.Position = UDim2.fromOffset(10, 60)
			descLbl.BackgroundTransparency = 1
			descLbl.Font = Enum.Font.Gotham
			descLbl.TextSize = 11
			descLbl.TextWrapped = true
			descLbl.TextXAlignment = Enum.TextXAlignment.Left
			descLbl.TextYAlignment = Enum.TextYAlignment.Top
			descLbl.TextColor3 = Config.Colors.TextMuted
			descLbl.Text = item.description
			descLbl.ZIndex = 24
			descLbl.Parent = card

			-- Botões de compra (Moedas + Robux) ou Equipar
			if owned then
				local equipBtn = Instance.new("TextButton")
				equipBtn.Size = UDim2.new(1, -20, 0, 32)
				equipBtn.Position = UDim2.new(0, 10, 1, -40)
				equipBtn.BackgroundColor3 = Config.Colors.IFSulGreen
				equipBtn.Font = Enum.Font.GothamBold
				equipBtn.TextSize = 12
				equipBtn.TextColor3 = Color3.new(1, 1, 1)
				equipBtn.Text = "✓ Adquirido • Pegar na Mochila"
				equipBtn.ZIndex = 24
				equipBtn.Parent = card

				local ec = Instance.new("UICorner")
				ec.CornerRadius = UDim.new(0, 7)
				ec.Parent = equipBtn

				equipBtn.MouseButton1Click:Connect(function()
					if isPurchasing then
						return
					end
					isPurchasing = true
					local ok, res = pcall(function()
						return shopBuyCoinsRF:InvokeServer(item.id)
					end)
					isPurchasing = false
					if ok and typeof(res) == "table" then
						setShopToast(res.message or "Item equipado!", res.ok == true)
					end
				end)
			else
				local canAfford = currentCoins >= item.coinPrice

				local coinBuyBtn = Instance.new("TextButton")
				coinBuyBtn.Size = UDim2.new(0.56, -12, 0, 32)
				coinBuyBtn.Position = UDim2.new(0, 10, 1, -40)
				coinBuyBtn.BackgroundColor3 = if canAfford
					then Config.Colors.IFSulGreen
					else Color3.fromRGB(44, 54, 66)
				coinBuyBtn.Font = Enum.Font.GothamBold
				coinBuyBtn.TextSize = 12
				coinBuyBtn.TextColor3 = if canAfford then Color3.new(1, 1, 1) else Config.Colors.TextMuted
				coinBuyBtn.Text = formatCoins(item.coinPrice) .. " Moedas"
				coinBuyBtn.ZIndex = 24
				coinBuyBtn.Parent = card

				local cbc = Instance.new("UICorner")
				cbc.CornerRadius = UDim.new(0, 7)
				cbc.Parent = coinBuyBtn

				local robuxBuyBtn = Instance.new("TextButton")
				robuxBuyBtn.Size = UDim2.new(0.44, -12, 0, 32)
				robuxBuyBtn.Position = UDim2.new(0.56, 2, 1, -40)
				robuxBuyBtn.BackgroundColor3 = Color3.fromRGB(32, 42, 54)
				robuxBuyBtn.Font = Enum.Font.GothamBold
				robuxBuyBtn.TextSize = 12
				robuxBuyBtn.TextColor3 = Color3.fromRGB(250, 214, 92)
				robuxBuyBtn.Text = "R$ " .. tostring(item.robuxPrice)
				robuxBuyBtn.ZIndex = 24
				robuxBuyBtn.Parent = card

				local rbc = Instance.new("UICorner")
				rbc.CornerRadius = UDim.new(0, 7)
				rbc.Parent = robuxBuyBtn

				local rbs = Instance.new("UIStroke")
				rbs.Color = Color3.fromRGB(224, 180, 64)
				rbs.Thickness = 1.1
				rbs.Transparency = 0.25
				rbs.Parent = robuxBuyBtn

				coinBuyBtn.MouseButton1Click:Connect(function()
					if isPurchasing then
						return
					end
					isPurchasing = true
					local ok, res = pcall(function()
						return shopBuyCoinsRF:InvokeServer(item.id)
					end)
					isPurchasing = false
					if ok and typeof(res) == "table" then
						if typeof(res.owned) == "table" then
							table.clear(ownedSet)
							for _, oid in ipairs(res.owned) do
								ownedSet[oid] = true
							end
						end
						setShopToast(res.message or "", res.ok == true)
						rebuildShopGrid()
					else
						setShopToast("Erro ao processar compra.", false)
					end
				end)

				robuxBuyBtn.MouseButton1Click:Connect(function()
					if isPurchasing then
						return
					end
					isPurchasing = true
					local ok, res = pcall(function()
						return shopBuyRobuxRF:InvokeServer(item.id)
					end)
					isPurchasing = false
					if ok and typeof(res) == "table" then
						setShopToast(res.message or "", res.ok == true)
					else
						setShopToast("Erro ao iniciar compra por Robux.", false)
					end
				end)
			end
		end
	end
end

for _, cat in ipairs(CATEGORIES) do
	local btn = Instance.new("TextButton")
	btn.AutomaticSize = Enum.AutomaticSize.X
	btn.Size = UDim2.fromOffset(0, 28)
	btn.BackgroundColor3 = Color3.fromRGB(30, 39, 50)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = Config.Colors.TextMuted
	btn.Text = cat
	btn.ZIndex = 22
	btn.Parent = tabBar

	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 7)
	tc.Parent = btn

	local tp = Instance.new("UIPadding")
	tp.PaddingLeft = UDim.new(0, 12)
	tp.PaddingRight = UDim.new(0, 12)
	tp.Parent = btn

	tabButtons[cat] = btn
	btn.MouseButton1Click:Connect(function()
		activeCategory = cat
		updateTabStyles()
		rebuildShopGrid()
	end)
end

local function setShopVisible(visible: boolean)
	shopBackdrop.Visible = visible
	if visible then
		modalBackdrop.Visible = false
		updateTabStyles()
		rebuildShopGrid()
	end
end

shopBtn.MouseButton1Click:Connect(function()
	setShopVisible(not shopBackdrop.Visible)
end)
shopCloseBtn.MouseButton1Click:Connect(function()
	setShopVisible(false)
end)
shopBackdrop.MouseButton1Click:Connect(function()
	setShopVisible(false)
end)

shopOwnedUpdatedRE.OnClientEvent:Connect(function(ownedList: unknown)
	if typeof(ownedList) == "table" then
		table.clear(ownedSet)
		for _, oid in ipairs(ownedList :: { string }) do
			ownedSet[oid] = true
		end
		if shopBackdrop.Visible then
			rebuildShopGrid()
		end
	end
end)

player:GetAttributeChangedSignal("Coins"):Connect(function()
	if shopBackdrop.Visible then
		rebuildShopGrid()
	end
end)

-- Carrega estado inicial de itens adquiridos
task.spawn(function()
	local ok, res = pcall(function()
		return shopGetStateRF:InvokeServer()
	end)
	if ok and typeof(res) == "table" and typeof(res.owned) == "table" then
		table.clear(ownedSet)
		for _, oid in ipairs(res.owned) do
			ownedSet[oid] = true
		end
	end
end)

-- Atalhos de teclado
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if input.KeyCode == Enum.KeyCode.Escape then
		if shopBackdrop.Visible then
			setShopVisible(false)
			return
		end
		if modalBackdrop.Visible then
			setFinderVisible(false)
			return
		end
	end
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		setShopVisible(not shopBackdrop.Visible)
	elseif input.KeyCode == Enum.KeyCode.G then
		setShopVisible(false)
		setFinderVisible(not modalBackdrop.Visible)
	elseif input.KeyCode == Enum.KeyCode.N then
		applyLocalLighting(not isNight)
	end
end)
