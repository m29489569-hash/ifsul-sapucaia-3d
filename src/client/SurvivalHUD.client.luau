--!strict
-- Interface Completa do Modo "Sobrevivência no Câmpus" (IFSul Sapucaia 3D)
-- Inclui:
-- 1) Popup de Fila do Portal na Portaria (1–6 jogadores + Iniciar Agora);
-- 2) HUD Limpo de Sobrevivência (Onda, Inimigos, Missão de Setor, Vida/Colete, Créditos, Munição e Mira);
-- 3) Tela 1 entre ondas: Sorteio de 3 Cartas de Habilidade (com artes do Nano Banana);
-- 4) Tela 2 entre ondas: Nova Loja de Upgrades na Tela (com banner do Nano Banana);
-- 5) Efeitos visuais de disparo (Beams, Explosões, Hitmarker e Números de Dano flutuantes).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local MatchMode = require(IFSulFolder:WaitForChild("MatchMode"))
local SurvivalCatalog = require(IFSulFolder:WaitForChild("SurvivalCatalog"))

local remotes = IFSulFolder:WaitForChild("Remotes")
local portalStateRE = remotes:WaitForChild("SurvivalPortalState") :: RemoteEvent
local portalActionRE = remotes:WaitForChild("SurvivalPortalAction") :: RemoteEvent
local matchStateRE = remotes:WaitForChild("SurvivalMatchState") :: RemoteEvent
local cardOfferRE = remotes:WaitForChild("SurvivalCardOffer") :: RemoteEvent
local pickCardRE = remotes:WaitForChild("SurvivalPickCard") :: RemoteEvent
local shopBuyRF = remotes:WaitForChild("SurvivalShopBuy") :: RemoteFunction
local shopReadyRE = remotes:WaitForChild("SurvivalShopReady") :: RemoteEvent
local toastRE = remotes:WaitForChild("SurvivalToast") :: RemoteEvent
local fxRE = remotes:WaitForChild("SurvivalFX") :: RemoteEvent
local fireRE = remotes:WaitForChild("SurvivalFireWeapon") :: RemoteEvent
local reloadRE = remotes:WaitForChild("SurvivalReloadWeapon") :: RemoteEvent
local tacticalRE = remotes:WaitForChild("SurvivalUseTactical") :: RemoteEvent

local oldGui = playerGui:FindFirstChild("IFSulSurvivalGUI")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "IFSulSurvivalGUI"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function addCorner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function addStroke(inst: GuiObject, color: Color3, thick: number, transp: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick
	s.Transparency = transp or 0.15
	s.Parent = inst
	return s
end

-- ============================================================================
-- 1. POPUP DO PORTAL NA PORTARIA (MODO LOBBY)
-- ============================================================================
local portalPopup = Instance.new("Frame")
portalPopup.Name = "PortalQueuePopup"
portalPopup.AnchorPoint = Vector2.new(0.5, 1)
portalPopup.Position = UDim2.new(0.5, 0, 1, -24)
portalPopup.Size = UDim2.fromOffset(390, 118)
portalPopup.BackgroundColor3 = Config.Colors.PanelBg
portalPopup.BackgroundTransparency = 0.06
portalPopup.Visible = false
portalPopup.ZIndex = 15
portalPopup.Parent = gui
addCorner(portalPopup, 14)
addStroke(portalPopup, Config.Colors.IFSulGreen, 2)

local portalTitle = Instance.new("TextLabel")
portalTitle.Size = UDim2.new(1, -24, 0, 26)
portalTitle.Position = UDim2.fromOffset(12, 10)
portalTitle.BackgroundTransparency = 1
portalTitle.Font = Enum.Font.GothamBlack
portalTitle.TextSize = 16
portalTitle.TextColor3 = Color3.fromRGB(250, 204, 21)
portalTitle.Text = "🧟 FILA DO ESQUADRÃO (1 / 6)"
portalTitle.ZIndex = 16
portalTitle.Parent = portalPopup

local portalSub = Instance.new("TextLabel")
portalSub.Size = UDim2.new(1, -24, 0, 20)
portalSub.Position = UDim2.fromOffset(12, 36)
portalSub.BackgroundTransparency = 1
portalSub.Font = Enum.Font.GothamSemibold
portalSub.TextSize = 13
portalSub.TextColor3 = Config.Colors.TextMuted
portalSub.Text = "Iniciando partida em 12s..."
portalSub.ZIndex = 16
portalSub.Parent = portalPopup

local startNowBtn = Instance.new("TextButton")
startNowBtn.Size = UDim2.new(0.64, -14, 0, 40)
startNowBtn.Position = UDim2.new(0, 12, 1, -50)
startNowBtn.BackgroundColor3 = Config.Colors.IFSulGreen
startNowBtn.Font = Enum.Font.GothamBlack
startNowBtn.TextSize = 14
startNowBtn.TextColor3 = Color3.new(1, 1, 1)
startNowBtn.Text = "▶ INICIAR AGORA"
startNowBtn.ZIndex = 16
startNowBtn.Parent = portalPopup
addCorner(startNowBtn, 9)

local leaveQueueBtn = Instance.new("TextButton")
leaveQueueBtn.Size = UDim2.new(0.36, -14, 0, 40)
leaveQueueBtn.Position = UDim2.new(0.64, 2, 1, -50)
leaveQueueBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 68)
leaveQueueBtn.Font = Enum.Font.GothamBold
leaveQueueBtn.TextSize = 13
leaveQueueBtn.TextColor3 = Config.Colors.TextPrimary
leaveQueueBtn.Text = "Sair"
leaveQueueBtn.ZIndex = 16
leaveQueueBtn.Parent = portalPopup
addCorner(leaveQueueBtn, 9)

startNowBtn.MouseButton1Click:Connect(function()
	portalActionRE:FireServer("StartNow")
end)
leaveQueueBtn.MouseButton1Click:Connect(function()
	portalActionRE:FireServer("LeaveQueue")
end)

portalStateRE.OnClientEvent:Connect(function(state: any)
	if typeof(state) ~= "table" then
		return
	end
	portalPopup.Visible = (state.visible == true) and (state.inQueue == true) and MatchMode.IsLobby()
	if portalPopup.Visible then
		portalTitle.Text = string.format("🧟 ESQUADRÃO PRONTO (%d / %d)", state.count or 1, state.maxPlayers or 6)
		portalSub.Text = string.format("Partida começa em %ds — convide amigos ou inicie já!", state.countdown or 10)
	end
end)

-- ============================================================================
-- 2. HUD DE COMBATE E SOBREVIVÊNCIA
-- ============================================================================
local survivalRoot = Instance.new("Frame")
survivalRoot.Name = "SurvivalHUDRoot"
survivalRoot.Size = UDim2.fromScale(1, 1)
survivalRoot.BackgroundTransparency = 1
survivalRoot.Visible = MatchMode.IsSurvival()
survivalRoot.Parent = gui

-- Barra Superior Central (Onda + Restantes + Fase)
local topBar = Instance.new("Frame")
topBar.AnchorPoint = Vector2.new(0.5, 0)
topBar.Position = UDim2.new(0.5, 0, 0, 8)
topBar.Size = UDim2.fromOffset(380, 52)
topBar.BackgroundColor3 = Config.Colors.PanelBg
topBar.BackgroundTransparency = 0.12
topBar.Parent = survivalRoot
addCorner(topBar, 14)
addStroke(topBar, Config.Colors.IFSulGreen, 1.8)

local waveTitleLbl = Instance.new("TextLabel")
waveTitleLbl.Size = UDim2.new(0.46, -12, 1, 0)
waveTitleLbl.Position = UDim2.fromOffset(14, 0)
waveTitleLbl.BackgroundTransparency = 1
waveTitleLbl.Font = Enum.Font.GothamBlack
waveTitleLbl.TextSize = 20
waveTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
waveTitleLbl.TextColor3 = Color3.fromRGB(250, 204, 21)
waveTitleLbl.Text = "ONDA 1 / 15"
waveTitleLbl.Parent = topBar

local waveStatusLbl = Instance.new("TextLabel")
waveStatusLbl.Size = UDim2.new(0.54, -14, 1, 0)
waveStatusLbl.Position = UDim2.new(0.46, 0, 0, 0)
waveStatusLbl.BackgroundTransparency = 1
waveStatusLbl.Font = Enum.Font.GothamBold
waveStatusLbl.TextSize = 15
waveStatusLbl.TextXAlignment = Enum.TextXAlignment.Right
waveStatusLbl.TextColor3 = Config.Colors.TextPrimary
waveStatusLbl.Text = "Prepare-se..."
waveStatusLbl.Parent = topBar

-- Card de Missão Bônus de Setor (abaixo da barra de onda)
local missionCard = Instance.new("Frame")
missionCard.AnchorPoint = Vector2.new(0.5, 0)
missionCard.Position = UDim2.new(0.5, 0, 0, 68)
missionCard.Size = UDim2.fromOffset(420, 62)
missionCard.BackgroundColor3 = Color3.fromRGB(22, 28, 38)
missionCard.BackgroundTransparency = 0.08
missionCard.Visible = false
missionCard.Parent = survivalRoot
addCorner(missionCard, 11)
addStroke(missionCard, Color3.fromRGB(250, 204, 21), 1.6)

local missionIcon = Instance.new("ImageLabel")
missionIcon.Size = UDim2.fromOffset(46, 46)
missionIcon.Position = UDim2.fromOffset(8, 8)
missionIcon.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
missionIcon.ScaleType = Enum.ScaleType.Crop
missionIcon.Parent = missionCard
addCorner(missionIcon, 8)

local missionTitleLbl = Instance.new("TextLabel")
missionTitleLbl.Size = UDim2.new(1, -68, 0, 22)
missionTitleLbl.Position = UDim2.fromOffset(62, 6)
missionTitleLbl.BackgroundTransparency = 1
missionTitleLbl.Font = Enum.Font.GothamBlack
missionTitleLbl.TextSize = 13
missionTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
missionTitleLbl.TextColor3 = Color3.fromRGB(250, 204, 21)
missionTitleLbl.Parent = missionCard

local missionInstLbl = Instance.new("TextLabel")
missionInstLbl.Size = UDim2.new(1, -68, 0, 28)
missionInstLbl.Position = UDim2.fromOffset(62, 27)
missionInstLbl.BackgroundTransparency = 1
missionInstLbl.Font = Enum.Font.Gotham
missionInstLbl.TextSize = 11
missionInstLbl.TextWrapped = true
missionInstLbl.TextXAlignment = Enum.TextXAlignment.Left
missionInstLbl.TextColor3 = Config.Colors.TextPrimary
missionInstLbl.Parent = missionCard

-- Toast Central de Avisos
local toastBanner = Instance.new("TextLabel")
toastBanner.AnchorPoint = Vector2.new(0.5, 0)
toastBanner.Position = UDim2.new(0.5, 0, 0, 138)
toastBanner.Size = UDim2.fromOffset(480, 34)
toastBanner.BackgroundColor3 = Color3.fromRGB(16, 22, 28)
toastBanner.BackgroundTransparency = 0.15
toastBanner.Font = Enum.Font.GothamBold
toastBanner.TextSize = 14
toastBanner.TextColor3 = Color3.fromRGB(110, 240, 138)
toastBanner.Visible = false
toastBanner.Parent = survivalRoot
addCorner(toastBanner, 9)

local toastToken = 0
local function showSurvivalToast(msg: string, isPositive: boolean)
	toastToken += 1
	local myToken = toastToken
	toastBanner.Text = msg
	toastBanner.TextColor3 = if isPositive then Color3.fromRGB(110, 240, 138) else Color3.fromRGB(255, 130, 110)
	toastBanner.Visible = true
	task.delay(4.0, function()
		if toastToken == myToken then
			toastBanner.Visible = false
		end
	end)
end

toastRE.OnClientEvent:Connect(showSurvivalToast)

-- Painel Inferior Esquerdo (Vida + Colete + Créditos + Botões Táticos H / T)
local statusPanel = Instance.new("Frame")
statusPanel.AnchorPoint = Vector2.new(0, 1)
statusPanel.Position = UDim2.new(0, 16, 1, -18)
statusPanel.Size = UDim2.fromOffset(268, 122)
statusPanel.BackgroundColor3 = Config.Colors.PanelBg
statusPanel.BackgroundTransparency = 0.14
statusPanel.Parent = survivalRoot
addCorner(statusPanel, 12)
addStroke(statusPanel, Color3.fromRGB(64, 82, 98), 1.4)

local creditsLbl = Instance.new("TextLabel")
creditsLbl.Size = UDim2.new(1, -20, 0, 24)
creditsLbl.Position = UDim2.fromOffset(10, 8)
creditsLbl.BackgroundTransparency = 1
creditsLbl.Font = Enum.Font.GothamBlack
creditsLbl.TextSize = 16
creditsLbl.TextXAlignment = Enum.TextXAlignment.Left
creditsLbl.TextColor3 = Color3.fromRGB(250, 204, 21)
creditsLbl.Text = "⚡ 150 CRÉDITOS"
creditsLbl.Parent = statusPanel

local hpBarBg = Instance.new("Frame")
hpBarBg.Size = UDim2.new(1, -20, 0, 18)
hpBarBg.Position = UDim2.fromOffset(10, 36)
hpBarBg.BackgroundColor3 = Color3.fromRGB(32, 38, 46)
hpBarBg.BorderSizePixel = 0
hpBarBg.Parent = statusPanel
addCorner(hpBarBg, 6)

local hpBarFill = Instance.new("Frame")
hpBarFill.Size = UDim2.fromScale(1, 1)
hpBarFill.BackgroundColor3 = Config.Colors.IFSulGreen
hpBarFill.BorderSizePixel = 0
hpBarFill.Parent = hpBarBg
addCorner(hpBarFill, 6)

local hpText = Instance.new("TextLabel")
hpText.Size = UDim2.fromScale(1, 1)
hpText.BackgroundTransparency = 1
hpText.Font = Enum.Font.GothamBold
hpText.TextSize = 11
hpText.TextColor3 = Color3.new(1, 1, 1)
hpText.Text = "VIDA: 100 / 100"
hpText.Parent = hpBarBg

local armorBarBg = Instance.new("Frame")
armorBarBg.Size = UDim2.new(1, -20, 0, 14)
armorBarBg.Position = UDim2.fromOffset(10, 58)
armorBarBg.BackgroundColor3 = Color3.fromRGB(28, 34, 44)
armorBarBg.BorderSizePixel = 0
armorBarBg.Parent = statusPanel
addCorner(armorBarBg, 6)

local armorBarFill = Instance.new("Frame")
armorBarFill.Size = UDim2.fromScale(0.25, 1)
armorBarFill.BackgroundColor3 = Color3.fromRGB(56, 168, 245)
armorBarFill.BorderSizePixel = 0
armorBarFill.Parent = armorBarBg
addCorner(armorBarFill, 6)

local armorText = Instance.new("TextLabel")
armorText.Size = UDim2.fromScale(1, 1)
armorText.BackgroundTransparency = 1
armorText.Font = Enum.Font.GothamBold
armorText.TextSize = 10
armorText.TextColor3 = Color3.new(1, 1, 1)
armorText.Text = "COLETE: 25"
armorText.Parent = armorBarBg

local medkitBtn = Instance.new("TextButton")
medkitBtn.Size = UDim2.new(0.5, -13, 0, 34)
medkitBtn.Position = UDim2.new(0, 10, 1, -42)
medkitBtn.BackgroundColor3 = Color3.fromRGB(32, 108, 62)
medkitBtn.Font = Enum.Font.GothamBold
medkitBtn.TextSize = 12
medkitBtn.TextColor3 = Color3.new(1, 1, 1)
medkitBtn.Text = "[H] Kit Médico (1)"
medkitBtn.Parent = statusPanel
addCorner(medkitBtn, 8)

local turretBtn = Instance.new("TextButton")
turretBtn.Size = UDim2.new(0.5, -13, 0, 34)
turretBtn.Position = UDim2.new(0.5, 3, 1, -42)
turretBtn.BackgroundColor3 = Color3.fromRGB(34, 78, 132)
turretBtn.Font = Enum.Font.GothamBold
turretBtn.TextSize = 12
turretBtn.TextColor3 = Color3.new(1, 1, 1)
turretBtn.Text = "[T] Torreta (0)"
turretBtn.Parent = statusPanel
addCorner(turretBtn, 8)

medkitBtn.MouseButton1Click:Connect(function()
	tacticalRE:FireServer("Medkit")
end)
turretBtn.MouseButton1Click:Connect(function()
	tacticalRE:FireServer("Turret")
end)

-- Painel Inferior Direito (Arma Atual + Munição + Botões Mobile Atirar/Recarregar)
local ammoPanel = Instance.new("Frame")
ammoPanel.AnchorPoint = Vector2.new(1, 1)
ammoPanel.Position = UDim2.new(1, -16, 1, -18)
ammoPanel.Size = UDim2.fromOffset(224, 92)
ammoPanel.BackgroundColor3 = Config.Colors.PanelBg
ammoPanel.BackgroundTransparency = 0.14
ammoPanel.Parent = survivalRoot
addCorner(ammoPanel, 12)
addStroke(ammoPanel, Config.Colors.IFSulGreen, 1.4)

local weaponNameLbl = Instance.new("TextLabel")
weaponNameLbl.Size = UDim2.new(1, -20, 0, 20)
weaponNameLbl.Position = UDim2.fromOffset(10, 8)
weaponNameLbl.BackgroundTransparency = 1
weaponNameLbl.Font = Enum.Font.GothamBold
weaponNameLbl.TextSize = 13
weaponNameLbl.TextXAlignment = Enum.TextXAlignment.Right
weaponNameLbl.TextColor3 = Config.Colors.TextMuted
weaponNameLbl.Text = "Equipada"
weaponNameLbl.Parent = ammoPanel

local ammoCountLbl = Instance.new("TextLabel")
ammoCountLbl.Size = UDim2.new(1, -20, 0, 34)
ammoCountLbl.Position = UDim2.fromOffset(10, 26)
ammoCountLbl.BackgroundTransparency = 1
ammoCountLbl.Font = Enum.Font.GothamBlack
ammoCountLbl.TextSize = 26
ammoCountLbl.TextXAlignment = Enum.TextXAlignment.Right
ammoCountLbl.TextColor3 = Color3.new(1, 1, 1)
ammoCountLbl.Text = "14 / 112"
ammoCountLbl.Parent = ammoPanel

local reloadBtn = Instance.new("TextButton")
reloadBtn.Size = UDim2.fromOffset(112, 24)
reloadBtn.Position = UDim2.new(1, -122, 1, -28)
reloadBtn.BackgroundColor3 = Color3.fromRGB(40, 52, 66)
reloadBtn.Font = Enum.Font.GothamBold
reloadBtn.TextSize = 11
reloadBtn.TextColor3 = Config.Colors.TextPrimary
reloadBtn.Text = "[R] Recarregar"
reloadBtn.Parent = ammoPanel
addCorner(reloadBtn, 6)

reloadBtn.MouseButton1Click:Connect(function()
	reloadRE:FireServer()
end)

-- Mira central discreta + Hitmarker
local crosshair = Instance.new("Frame")
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(6, 6)
crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
crosshair.BackgroundTransparency = 0.25
crosshair.Parent = survivalRoot
addCorner(crosshair, 6)
addStroke(crosshair, Color3.new(0, 0, 0), 1, 0.4)

local hitMarker = Instance.new("TextLabel")
hitMarker.AnchorPoint = Vector2.new(0.5, 0.5)
hitMarker.Position = UDim2.fromScale(0.5, 0.5)
hitMarker.Size = UDim2.fromOffset(28, 28)
hitMarker.BackgroundTransparency = 1
hitMarker.Font = Enum.Font.GothamBlack
hitMarker.TextSize = 20
hitMarker.TextColor3 = Color3.fromRGB(255, 75, 75)
hitMarker.Text = "✕"
hitMarker.Visible = false
hitMarker.Parent = survivalRoot

-- ============================================================================
-- 3. TELA 1 ENTRE ONDAS: DRAFT DE 3 CARTAS DE HABILIDADE (NANO BANANA ART)
-- ============================================================================
local cardOverlay = Instance.new("Frame")
cardOverlay.Name = "CardDraftOverlay"
cardOverlay.Size = UDim2.fromScale(1, 1)
cardOverlay.BackgroundColor3 = Color3.fromRGB(6, 10, 14)
cardOverlay.BackgroundTransparency = 0.32
cardOverlay.Visible = false
cardOverlay.ZIndex = 30
cardOverlay.Parent = survivalRoot

local cardHeader = Instance.new("TextLabel")
cardHeader.AnchorPoint = Vector2.new(0.5, 0)
cardHeader.Position = UDim2.new(0.5, 0, 0, 72)
cardHeader.Size = UDim2.new(0.9, 0, 0, 32)
cardHeader.BackgroundTransparency = 1
cardHeader.Font = Enum.Font.GothamBlack
cardHeader.TextSize = 22
cardHeader.TextColor3 = Color3.new(1, 1, 1)
cardHeader.Text = "✨ ONDA VENCIDA! ESCOLHA 1 CARTA DE HABILIDADE"
cardHeader.ZIndex = 31
cardHeader.Parent = cardOverlay

local cardTimerLbl = Instance.new("TextLabel")
cardTimerLbl.AnchorPoint = Vector2.new(0.5, 0)
cardTimerLbl.Position = UDim2.new(0.5, 0, 0, 106)
cardTimerLbl.Size = UDim2.new(0.8, 0, 0, 22)
cardTimerLbl.BackgroundTransparency = 1
cardTimerLbl.Font = Enum.Font.GothamSemibold
cardTimerLbl.TextSize = 14
cardTimerLbl.TextColor3 = Color3.fromRGB(250, 204, 21)
cardTimerLbl.Text = "Escolha uma especialização do IFSul para acumular nesta partida"
cardTimerLbl.ZIndex = 31
cardTimerLbl.Parent = cardOverlay

local cardsContainer = Instance.new("Frame")
cardsContainer.AnchorPoint = Vector2.new(0.5, 0.5)
cardsContainer.Position = UDim2.fromScale(0.5, 0.55)
cardsContainer.Size = UDim2.new(0.92, 0, 0.68, 0)
cardsContainer.BackgroundTransparency = 1
cardsContainer.ZIndex = 31
cardsContainer.Parent = cardOverlay

local cardsConstraint = Instance.new("UISizeConstraint")
cardsConstraint.MaxSize = Vector2.new(840, 390)
cardsConstraint.Parent = cardsContainer

local cardsLayout = Instance.new("UIListLayout")
cardsLayout.FillDirection = Enum.FillDirection.Horizontal
cardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cardsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
cardsLayout.Padding = UDim.new(0, 16)
cardsLayout.Parent = cardsContainer

-- ============================================================================
-- 4. TELA 2 ENTRE ONDAS: NOVA LOJA DE UPGRADES NA TELA (NANO BANANA BANNER)
-- ============================================================================
local shopOverlay = Instance.new("Frame")
shopOverlay.Name = "SurvivalShopOverlay"
shopOverlay.Size = UDim2.fromScale(1, 1)
shopOverlay.BackgroundColor3 = Color3.fromRGB(6, 10, 14)
shopOverlay.BackgroundTransparency = 0.35
shopOverlay.Visible = false
shopOverlay.ZIndex = 40
shopOverlay.Parent = survivalRoot

local shopWindow = Instance.new("Frame")
shopWindow.AnchorPoint = Vector2.new(0.5, 0.5)
shopWindow.Position = UDim2.fromScale(0.5, 0.5)
shopWindow.Size = UDim2.fromScale(0.92, 0.86)
shopWindow.BackgroundColor3 = Config.Colors.PanelBg
shopWindow.ZIndex = 41
shopWindow.Parent = shopOverlay
addCorner(shopWindow, 16)
addStroke(shopWindow, Color3.fromRGB(250, 204, 21), 2)

local shopWinConstraint = Instance.new("UISizeConstraint")
shopWinConstraint.MaxSize = Vector2.new(820, 560)
shopWinConstraint.Parent = shopWindow

-- Banner superior gerado no Nano Banana
local shopBannerImg = Instance.new("ImageLabel")
shopBannerImg.Size = UDim2.new(1, 0, 0, 108)
shopBannerImg.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
shopBannerImg.BorderSizePixel = 0
shopBannerImg.ScaleType = Enum.ScaleType.Crop
shopBannerImg.Image = SurvivalCatalog.UIArt.ShopBanner
shopBannerImg.ZIndex = 42
shopBannerImg.Parent = shopWindow
addCorner(shopBannerImg, 16)

local bannerShade = Instance.new("Frame")
bannerShade.Size = UDim2.fromScale(1, 1)
bannerShade.BackgroundColor3 = Color3.fromRGB(10, 14, 20)
bannerShade.BackgroundTransparency = 0.35
bannerShade.BorderSizePixel = 0
bannerShade.ZIndex = 43
bannerShade.Parent = shopBannerImg
addCorner(bannerShade, 16)

local shopHeaderTitle = Instance.new("TextLabel")
shopHeaderTitle.Size = UDim2.new(0.62, 0, 0, 32)
shopHeaderTitle.Position = UDim2.fromOffset(18, 16)
shopHeaderTitle.BackgroundTransparency = 1
shopHeaderTitle.Font = Enum.Font.GothamBlack
shopHeaderTitle.TextSize = 22
shopHeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
shopHeaderTitle.TextColor3 = Color3.new(1, 1, 1)
shopHeaderTitle.Text = "🛠️ ARSENAL & UPGRADES DO CÂMPUS"
shopHeaderTitle.ZIndex = 44
shopHeaderTitle.Parent = shopBannerImg

local shopSubTimer = Instance.new("TextLabel")
shopSubTimer.Size = UDim2.new(0.62, 0, 0, 22)
shopSubTimer.Position = UDim2.fromOffset(18, 50)
shopSubTimer.BackgroundTransparency = 1
shopSubTimer.Font = Enum.Font.GothamSemibold
shopSubTimer.TextSize = 13
shopSubTimer.TextXAlignment = Enum.TextXAlignment.Left
shopSubTimer.TextColor3 = Color3.fromRGB(178, 232, 192)
shopSubTimer.Text = "Próxima onda em 20s"
shopSubTimer.ZIndex = 44
shopSubTimer.Parent = shopBannerImg

local shopCreditsBadge = Instance.new("TextLabel")
shopCreditsBadge.AnchorPoint = Vector2.new(1, 0)
shopCreditsBadge.Position = UDim2.new(1, -18, 0, 18)
shopCreditsBadge.Size = UDim2.fromOffset(175, 36)
shopCreditsBadge.BackgroundColor3 = Color3.fromRGB(16, 22, 28)
shopCreditsBadge.Font = Enum.Font.GothamBlack
shopCreditsBadge.TextSize = 16
shopCreditsBadge.TextColor3 = Color3.fromRGB(250, 204, 21)
shopCreditsBadge.Text = "⚡ 0 CRÉDITOS"
shopCreditsBadge.ZIndex = 44
shopCreditsBadge.Parent = shopBannerImg
addCorner(shopCreditsBadge, 18)
addStroke(shopCreditsBadge, Color3.fromRGB(250, 204, 21), 1.5)

local shopTabBar = Instance.new("Frame")
shopTabBar.Size = UDim2.new(1, -32, 0, 34)
shopTabBar.Position = UDim2.fromOffset(16, 116)
shopTabBar.BackgroundTransparency = 1
shopTabBar.ZIndex = 42
shopTabBar.Parent = shopWindow

local activeShopTab: "Armas" | "Upgrades" = "Armas"

local tabWeaponsBtn = Instance.new("TextButton")
tabWeaponsBtn.Size = UDim2.fromOffset(160, 32)
tabWeaponsBtn.BackgroundColor3 = Config.Colors.IFSulGreen
tabWeaponsBtn.Font = Enum.Font.GothamBold
tabWeaponsBtn.TextSize = 13
tabWeaponsBtn.TextColor3 = Color3.new(1, 1, 1)
tabWeaponsBtn.Text = "🔫 Armas Prontas"
tabWeaponsBtn.ZIndex = 43
tabWeaponsBtn.Parent = shopTabBar
addCorner(tabWeaponsBtn, 8)

local tabUpgradesBtn = Instance.new("TextButton")
tabUpgradesBtn.Size = UDim2.fromOffset(200, 32)
tabUpgradesBtn.Position = UDim2.fromOffset(170, 0)
tabUpgradesBtn.BackgroundColor3 = Color3.fromRGB(32, 42, 54)
tabUpgradesBtn.Font = Enum.Font.GothamBold
tabUpgradesBtn.TextSize = 13
tabUpgradesBtn.TextColor3 = Config.Colors.TextMuted
tabUpgradesBtn.Text = "⚙️ Melhorias & Engenhocas"
tabUpgradesBtn.ZIndex = 43
tabUpgradesBtn.Parent = shopTabBar
addCorner(tabUpgradesBtn, 8)

local readyNextWaveBtn = Instance.new("TextButton")
readyNextWaveBtn.AnchorPoint = Vector2.new(1, 0)
readyNextWaveBtn.Position = UDim2.new(1, 0, 0, 0)
readyNextWaveBtn.Size = UDim2.fromOffset(215, 32)
readyNextWaveBtn.BackgroundColor3 = Color3.fromRGB(234, 179, 8)
readyNextWaveBtn.Font = Enum.Font.GothamBlack
readyNextWaveBtn.TextSize = 13
readyNextWaveBtn.TextColor3 = Color3.fromRGB(18, 20, 24)
readyNextWaveBtn.Text = "✓ PRONTO P/ PRÓXIMA ONDA"
readyNextWaveBtn.ZIndex = 43
readyNextWaveBtn.Parent = shopTabBar
addCorner(readyNextWaveBtn, 8)

local shopScroll = Instance.new("ScrollingFrame")
shopScroll.Size = UDim2.new(1, -32, 1, -196)
shopScroll.Position = UDim2.fromOffset(16, 158)
shopScroll.BackgroundTransparency = 1
shopScroll.ScrollBarThickness = 6
shopScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopScroll.CanvasSize = UDim2.fromOffset(0, 0)
shopScroll.ZIndex = 42
shopScroll.Parent = shopWindow

local shopGrid = Instance.new("UIGridLayout")
shopGrid.CellSize = UDim2.fromOffset(244, 134)
shopGrid.CellPadding = UDim2.fromOffset(12, 12)
shopGrid.SortOrder = Enum.SortOrder.LayoutOrder
shopGrid.Parent = shopScroll

local shopFeedbackLbl = Instance.new("TextLabel")
shopFeedbackLbl.Size = UDim2.new(1, -32, 0, 26)
shopFeedbackLbl.AnchorPoint = Vector2.new(0, 1)
shopFeedbackLbl.Position = UDim2.new(0, 16, 1, -8)
shopFeedbackLbl.BackgroundColor3 = Color3.fromRGB(22, 30, 38)
shopFeedbackLbl.Font = Enum.Font.GothamSemibold
shopFeedbackLbl.TextSize = 12
shopFeedbackLbl.TextColor3 = Config.Colors.TextMuted
shopFeedbackLbl.Text = "Dica: Evoluir o nível de Usinagem melhora o dano E muda o visual 3D de todas as armas!"
shopFeedbackLbl.ZIndex = 42
shopFeedbackLbl.Parent = shopWindow
addCorner(shopFeedbackLbl, 7)

local function populateSurvivalShop()
	for _, ch in ipairs(shopScroll:GetChildren()) do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	local rawCred = player:GetAttribute("SurvivalCredits")
	local credits = if typeof(rawCred) == "number" then rawCred else 0
	shopCreditsBadge.Text = string.format("⚡ %d CRÉDITOS", credits)

	tabWeaponsBtn.BackgroundColor3 = if activeShopTab == "Armas" then Config.Colors.IFSulGreen else Color3.fromRGB(32, 42, 54)
	tabWeaponsBtn.TextColor3 = if activeShopTab == "Armas" then Color3.new(1, 1, 1) else Config.Colors.TextMuted
	tabUpgradesBtn.BackgroundColor3 = if activeShopTab == "Upgrades" then Config.Colors.IFSulGreen else Color3.fromRGB(32, 42, 54)
	tabUpgradesBtn.TextColor3 = if activeShopTab == "Upgrades" then Color3.new(1, 1, 1) else Config.Colors.TextMuted

	if activeShopTab == "Armas" then
		for idx, w in ipairs(SurvivalCatalog.Weapons) do
			if w.price > 0 then
				local card = Instance.new("Frame")
				card.LayoutOrder = idx
				card.BackgroundColor3 = Color3.fromRGB(24, 32, 42)
				card.ZIndex = 43
				card.Parent = shopScroll
				addCorner(card, 10)
				addStroke(card, Config.Colors.IFSulGreen, 1.2, 0.35)

				local title = Instance.new("TextLabel")
				title.Size = UDim2.new(1, -20, 0, 22)
				title.Position = UDim2.fromOffset(10, 8)
				title.BackgroundTransparency = 1
				title.Font = Enum.Font.GothamBlack
				title.TextSize = 14
				title.TextXAlignment = Enum.TextXAlignment.Left
				title.TextColor3 = Color3.new(1, 1, 1)
				title.Text = w.name
				title.ZIndex = 44
				title.Parent = card

				local statsTxt = Instance.new("TextLabel")
				statsTxt.Size = UDim2.new(1, -20, 0, 16)
				statsTxt.Position = UDim2.fromOffset(10, 30)
				statsTxt.BackgroundTransparency = 1
				statsTxt.Font = Enum.Font.GothamSemibold
				statsTxt.TextSize = 11
				statsTxt.TextXAlignment = Enum.TextXAlignment.Left
				statsTxt.TextColor3 = Color3.fromRGB(110, 224, 152)
				statsTxt.Text = string.format("Dano Base: %d • Pente: %d", w.baseDamage, w.magSize)
				statsTxt.ZIndex = 44
				statsTxt.Parent = card

				local desc = Instance.new("TextLabel")
				desc.Size = UDim2.new(1, -20, 0, 38)
				desc.Position = UDim2.fromOffset(10, 48)
				desc.BackgroundTransparency = 1
				desc.Font = Enum.Font.Gotham
				desc.TextSize = 11
				desc.TextWrapped = true
				desc.TextXAlignment = Enum.TextXAlignment.Left
				desc.TextYAlignment = Enum.TextYAlignment.Top
				desc.TextColor3 = Config.Colors.TextMuted
				desc.Text = w.description
				desc.ZIndex = 44
				desc.Parent = card

				local buyBtn = Instance.new("TextButton")
				buyBtn.Size = UDim2.new(1, -20, 0, 30)
				buyBtn.Position = UDim2.new(0, 10, 1, -38)
				buyBtn.BackgroundColor3 = if credits >= w.price then Config.Colors.IFSulGreen else Color3.fromRGB(46, 56, 68)
				buyBtn.Font = Enum.Font.GothamBold
				buyBtn.TextSize = 12
				buyBtn.TextColor3 = Color3.new(1, 1, 1)
				buyBtn.Text = string.format("Comprar • ⚡ %d", w.price)
				buyBtn.ZIndex = 44
				buyBtn.Parent = card
				addCorner(buyBtn, 7)

				buyBtn.MouseButton1Click:Connect(function()
					local ok, res = pcall(function()
						return shopBuyRF:InvokeServer("Weapon", w.id)
					end)
					if ok and typeof(res) == "table" then
						shopFeedbackLbl.Text = res.message or ""
						shopFeedbackLbl.TextColor3 = if res.ok then Color3.fromRGB(110, 240, 138) else Color3.fromRGB(255, 145, 115)
						populateSurvivalShop()
					end
				end)
			end
		end
	else
		local rawUpLv = player:GetAttribute("WeaponUpgradeLevel")
		local upLv = if typeof(rawUpLv) == "number" then rawUpLv else 1

		for idx, u in ipairs(SurvivalCatalog.ShopUpgrades) do
			local card = Instance.new("Frame")
			card.LayoutOrder = idx
			card.BackgroundColor3 = Color3.fromRGB(24, 32, 42)
			card.ZIndex = 43
			card.Parent = shopScroll
			addCorner(card, 10)
			addStroke(card, Color3.fromRGB(250, 204, 21), 1.2, 0.4)

			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.fromOffset(38, 38)
			icon.Position = UDim2.fromOffset(10, 10)
			icon.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
			icon.ScaleType = Enum.ScaleType.Crop
			icon.Image = u.iconArt
			icon.ZIndex = 44
			icon.Parent = card
			addCorner(icon, 8)

			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, -60, 0, 38)
			title.Position = UDim2.fromOffset(54, 10)
			title.BackgroundTransparency = 1
			title.Font = Enum.Font.GothamBold
			title.TextSize = 13
			title.TextWrapped = true
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Color3.new(1, 1, 1)
			title.Text = if u.id == "weapon_upgrade"
				then string.format("%s (Nv.%d/5)", u.name, upLv)
				else u.name
			title.ZIndex = 44
			title.Parent = card

			local desc = Instance.new("TextLabel")
			desc.Size = UDim2.new(1, -20, 0, 36)
			desc.Position = UDim2.fromOffset(10, 52)
			desc.BackgroundTransparency = 1
			desc.Font = Enum.Font.Gotham
			desc.TextSize = 11
			desc.TextWrapped = true
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextYAlignment = Enum.TextYAlignment.Top
			desc.TextColor3 = Config.Colors.TextMuted
			desc.Text = u.description
			desc.ZIndex = 44
			desc.Parent = card

			local estPrice = if u.id == "weapon_upgrade"
				then math.round(u.basePrice * (u.priceScale ^ (upLv - 1)))
				else u.basePrice
			local maxed = (u.id == "weapon_upgrade" and upLv >= u.maxLevel)

			local buyBtn = Instance.new("TextButton")
			buyBtn.Size = UDim2.new(1, -20, 0, 30)
			buyBtn.Position = UDim2.new(0, 10, 1, -38)
			buyBtn.BackgroundColor3 = if maxed
				then Color3.fromRGB(48, 60, 72)
				elseif credits >= estPrice then Config.Colors.IFSulGreen
				else Color3.fromRGB(46, 56, 68)
			buyBtn.Font = Enum.Font.GothamBold
			buyBtn.TextSize = 12
			buyBtn.TextColor3 = Color3.new(1, 1, 1)
			buyBtn.Text = if maxed then "NÍVEL MÁXIMO ✓" else string.format("Adquirir • ⚡ %d+", estPrice)
			buyBtn.ZIndex = 44
			buyBtn.Parent = card
			addCorner(buyBtn, 7)

			buyBtn.MouseButton1Click:Connect(function()
				if maxed then
					return
				end
				local ok, res = pcall(function()
					return shopBuyRF:InvokeServer("Upgrade", u.id)
				end)
				if ok and typeof(res) == "table" then
					shopFeedbackLbl.Text = res.message or ""
					shopFeedbackLbl.TextColor3 = if res.ok then Color3.fromRGB(110, 240, 138) else Color3.fromRGB(255, 145, 115)
					populateSurvivalShop()
				end
			end)
		end
	end
end

tabWeaponsBtn.MouseButton1Click:Connect(function()
	activeShopTab = "Armas"
	populateSurvivalShop()
end)
tabUpgradesBtn.MouseButton1Click:Connect(function()
	activeShopTab = "Upgrades"
	populateSurvivalShop()
end)
readyNextWaveBtn.MouseButton1Click:Connect(function()
	readyNextWaveBtn.Text = "✓ AGUARDANDO EQUIPE..."
	readyNextWaveBtn.BackgroundColor3 = Config.Colors.IFSulGreen
	readyNextWaveBtn.TextColor3 = Color3.new(1, 1, 1)
	shopReadyRE:FireServer("Ready")
end)

-- ============================================================================
-- 5. MODAL DE FIM DE JOGO / VITÓRIA (ONDA 15)
-- ============================================================================
local endModal = Instance.new("Frame")
endModal.Name = "EndModal"
endModal.AnchorPoint = Vector2.new(0.5, 0.5)
endModal.Position = UDim2.fromScale(0.5, 0.5)
endModal.Size = UDim2.fromOffset(440, 250)
endModal.BackgroundColor3 = Config.Colors.PanelBg
endModal.Visible = false
endModal.ZIndex = 50
endModal.Parent = survivalRoot
addCorner(endModal, 16)
addStroke(endModal, Color3.fromRGB(250, 204, 21), 2)

local endTitle = Instance.new("TextLabel")
endTitle.Size = UDim2.new(1, -32, 0, 38)
endTitle.Position = UDim2.fromOffset(16, 18)
endTitle.BackgroundTransparency = 1
endTitle.Font = Enum.Font.GothamBlack
endTitle.TextSize = 22
endTitle.TextColor3 = Color3.fromRGB(250, 204, 21)
endTitle.Text = "FIM DA PARTIDA"
endTitle.ZIndex = 51
endTitle.Parent = endModal

local endSummary = Instance.new("TextLabel")
endSummary.Size = UDim2.new(1, -32, 0, 86)
endSummary.Position = UDim2.fromOffset(16, 64)
endSummary.BackgroundTransparency = 1
endSummary.Font = Enum.Font.GothamSemibold
endSummary.TextSize = 15
endSummary.TextWrapped = true
endSummary.TextColor3 = Config.Colors.TextPrimary
endSummary.ZIndex = 51
endSummary.Parent = endModal

local playAgainBtn = Instance.new("TextButton")
playAgainBtn.Size = UDim2.new(0.5, -22, 0, 44)
playAgainBtn.Position = UDim2.new(0, 16, 1, -62)
playAgainBtn.BackgroundColor3 = Config.Colors.IFSulGreen
playAgainBtn.Font = Enum.Font.GothamBlack
playAgainBtn.TextSize = 14
playAgainBtn.TextColor3 = Color3.new(1, 1, 1)
playAgainBtn.Text = "🔄 Jogar Novamente"
playAgainBtn.ZIndex = 51
playAgainBtn.Parent = endModal
addCorner(playAgainBtn, 10)

local backLobbyBtn = Instance.new("TextButton")
backLobbyBtn.Size = UDim2.new(0.5, -22, 0, 44)
backLobbyBtn.Position = UDim2.new(0.5, 6, 1, -62)
backLobbyBtn.BackgroundColor3 = Color3.fromRGB(44, 54, 68)
backLobbyBtn.Font = Enum.Font.GothamBold
backLobbyBtn.TextSize = 14
backLobbyBtn.TextColor3 = Color3.new(1, 1, 1)
backLobbyBtn.Text = "🏛️ Voltar ao Lobby"
backLobbyBtn.ZIndex = 51
backLobbyBtn.Parent = endModal
addCorner(backLobbyBtn, 10)

local currentServerPhase = "Idle"

playAgainBtn.MouseButton1Click:Connect(function()
	if currentServerPhase == "VictoryChoice" then
		endModal.Visible = false
		shopReadyRE:FireServer("ContinueEndless")
	else
		shopReadyRE:FireServer("RestartMatch")
	end
end)

backLobbyBtn.MouseButton1Click:Connect(function()
	portalActionRE:FireServer("ReturnToLobby")
end)

-- ============================================================================
-- RECEPÇÃO DO SORTEIO DAS 3 CARTAS E ESTADOS DA PARTIDA
-- ============================================================================
cardOfferRE.OnClientEvent:Connect(function(cards: any, _durationSec: any)
	if typeof(cards) ~= "table" then
		return
	end
	for _, ch in ipairs(cardsContainer:GetChildren()) do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end

	cardOverlay.Visible = true
	shopOverlay.Visible = false

	for idx, c in ipairs(cards) do
		local rarityColor = SurvivalCatalog.RarityColors[c.rarity] or Config.Colors.IFSulGreen

		local btn = Instance.new("TextButton")
		btn.Name = "SkillCard_" .. tostring(idx)
		btn.LayoutOrder = idx
		btn.Size = UDim2.new(0.31, 0, 0.96, 0)
		btn.BackgroundColor3 = Color3.fromRGB(18, 24, 32)
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.ZIndex = 32
		btn.Parent = cardsContainer
		addCorner(btn, 14)
		addStroke(btn, rarityColor, 2.4)

		local topBand = Instance.new("Frame")
		topBand.Size = UDim2.new(1, 0, 0, 28)
		topBand.BackgroundColor3 = rarityColor
		topBand.BorderSizePixel = 0
		topBand.ZIndex = 33
		topBand.Parent = btn
		addCorner(topBand, 14)

		local rarityTxt = Instance.new("TextLabel")
		rarityTxt.Size = UDim2.fromScale(1, 1)
		rarityTxt.BackgroundTransparency = 1
		rarityTxt.Font = Enum.Font.GothamBlack
		rarityTxt.TextSize = 12
		rarityTxt.TextColor3 = if c.rarity == "Lendária" then Color3.fromRGB(20, 18, 10) else Color3.new(1, 1, 1)
		rarityTxt.Text = string.upper(c.rarity) .. " • " .. tostring(c.courseTag)
		rarityTxt.ZIndex = 34
		rarityTxt.Parent = topBand

		local artImg = Instance.new("ImageLabel")
		artImg.AnchorPoint = Vector2.new(0.5, 0)
		artImg.Position = UDim2.new(0.5, 0, 0, 38)
		artImg.Size = UDim2.fromOffset(128, 128)
		artImg.BackgroundColor3 = Color3.fromRGB(10, 14, 20)
		artImg.ScaleType = Enum.ScaleType.Crop
		artImg.Image = c.artAssetId
		artImg.ZIndex = 33
		artImg.Parent = btn
		addCorner(artImg, 12)
		addStroke(artImg, rarityColor, 1.4, 0.35)

		local cTitle = Instance.new("TextLabel")
		cTitle.Size = UDim2.new(1, -20, 0, 38)
		cTitle.Position = UDim2.fromOffset(10, 174)
		cTitle.BackgroundTransparency = 1
		cTitle.Font = Enum.Font.GothamBlack
		cTitle.TextSize = 15
		cTitle.TextWrapped = true
		cTitle.TextColor3 = Color3.new(1, 1, 1)
		cTitle.Text = c.name
		cTitle.ZIndex = 33
		cTitle.Parent = btn

		local cDesc = Instance.new("TextLabel")
		cDesc.Size = UDim2.new(1, -24, 0, 74)
		cDesc.Position = UDim2.fromOffset(12, 214)
		cDesc.BackgroundTransparency = 1
		cDesc.Font = Enum.Font.Gotham
		cDesc.TextSize = 13
		cDesc.TextWrapped = true
		cDesc.TextColor3 = Config.Colors.TextMuted
		cDesc.Text = c.description
		cDesc.ZIndex = 33
		cDesc.Parent = btn

		local chooseBadge = Instance.new("TextLabel")
		chooseBadge.AnchorPoint = Vector2.new(0.5, 1)
		chooseBadge.Position = UDim2.new(0.5, 0, 1, -12)
		chooseBadge.Size = UDim2.new(1, -24, 0, 34)
		chooseBadge.BackgroundColor3 = rarityColor
		chooseBadge.Font = Enum.Font.GothamBlack
		chooseBadge.TextSize = 13
		chooseBadge.TextColor3 = if c.rarity == "Lendária" then Color3.fromRGB(20, 18, 10) else Color3.new(1, 1, 1)
		chooseBadge.Text = "ESCOLHER CARTA"
		chooseBadge.ZIndex = 33
		chooseBadge.Parent = btn
		addCorner(chooseBadge, 9)

		btn.MouseButton1Click:Connect(function()
			pickCardRE:FireServer(c.id)
			cardOverlay.Visible = false
		end)
	end
end)

matchStateRE.OnClientEvent:Connect(function(state: any)
	if typeof(state) ~= "table" then
		return
	end
	currentServerPhase = state.phase or "Idle"
	survivalRoot.Visible = MatchMode.IsSurvival()
	if not survivalRoot.Visible then
		cardOverlay.Visible = false
		shopOverlay.Visible = false
		endModal.Visible = false
		return
	end

	waveTitleLbl.Text = string.format("ONDA %d / %d", math.max(1, state.wave or 1), state.targetWaves or 15)

	if state.phase == "Wave" then
		waveStatusLbl.Text = string.format("🧟 Restantes: %d", state.enemiesRemaining or 0)
		cardOverlay.Visible = false
		shopOverlay.Visible = false
		endModal.Visible = false
	elseif state.phase == "CardDraft" then
		waveStatusLbl.Text = string.format("✨ Cartas (%ds)", state.timeLeft or 0)
		cardTimerLbl.Text = string.format("Tempo restante para escolher: %ds", state.timeLeft or 0)
		shopOverlay.Visible = false
		endModal.Visible = false
	elseif state.phase == "Shop" then
		waveStatusLbl.Text = string.format("🛠️ Loja (%ds)", state.timeLeft or 0)
		shopSubTimer.Text = string.format(
			"Próxima onda em %ds • Prontos: %d / %d",
			state.timeLeft or 0,
			state.readyCount or 0,
			state.totalPlayers or 1
		)
		cardOverlay.Visible = false
		if not shopOverlay.Visible then
			shopOverlay.Visible = true
			readyNextWaveBtn.Text = "✓ PRONTO P/ PRÓXIMA ONDA"
			readyNextWaveBtn.BackgroundColor3 = Color3.fromRGB(234, 179, 8)
			readyNextWaveBtn.TextColor3 = Color3.fromRGB(18, 20, 24)
			populateSurvivalShop()
		end
	elseif state.phase == "VictoryChoice" then
		cardOverlay.Visible = false
		shopOverlay.Visible = false
		endModal.Visible = true
		endTitle.Text = "🏆 CÂMPUS DEFENDIDO!"
		endSummary.Text = string.format(
			"Parabéns! Você sobreviveu às 15 Ondas no IFSul Sapucaia com %d abates!\nDeseja continuar no Modo Infinito (%ds)?",
			tonumber(player:GetAttribute("SurvivalKills")) or 0,
			state.timeLeft or 0
		)
		playAgainBtn.Text = "🔥 Modo Infinito (Onda 16+)"
	elseif state.phase == "GameOver" then
		cardOverlay.Visible = false
		shopOverlay.Visible = false
		endModal.Visible = true
		endTitle.Text = "💀 ESQUADRÃO DERRUBADO"
		endSummary.Text = string.format(
			"Vocês resistiram bravamente até a Onda %d no IFSul Sapucaia!\nTotal de Abates: %d",
			state.wave or 1,
			tonumber(player:GetAttribute("SurvivalKills")) or 0
		)
		playAgainBtn.Text = "🔄 Jogar Novamente"
	else
		waveStatusLbl.Text = state.banner or "Preparando..."
	end

	-- Missão de Setor ativa
	if typeof(state.mission) == "table" then
		local m = state.mission
		missionCard.Visible = true
		missionIcon.Image = m.artAssetId or SurvivalCatalog.UIArt.CardMecanica
		local progSuffix = if m.isHoldZone then string.format(" [%d%%]", math.round((m.progress or 0) * 100)) else ""
		missionTitleLbl.Text = string.format("%s • %s (%ds)%s", m.title, m.sector, m.remainingSec or 0, progSuffix)
		missionInstLbl.Text = m.instruction or ""
	else
		missionCard.Visible = false
	end
end)

MatchMode.OnChanged(function(isSurvival: boolean)
	survivalRoot.Visible = isSurvival
	if isSurvival then
		portalPopup.Visible = false
	else
		cardOverlay.Visible = false
		shopOverlay.Visible = false
		endModal.Visible = false
	end
end)

-- ============================================================================
-- ATUALIZAÇÃO DE BARRAS, DISPARO CONTÍNUO E EFEITOS VISUAIS 3D
-- ============================================================================
local isHoldingFire = false

local function getAimRay(): (Vector3, Vector3)
	local cam = Workspace.CurrentCamera
	if not cam then
		return Vector3.zero, Vector3.zAxis
	end
	local vp = cam.ViewportSize
	local unitRay = cam:ViewportPointToRay(vp.X * 0.5, vp.Y * 0.5)
	local exclude: { Instance } = {}
	if player.Character then
		table.insert(exclude, player.Character)
	end
	local perim = Workspace:FindFirstChild("IFSul_SurvivalPerimeter")
	if perim then
		table.insert(exclude, perim)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, params)
	local targetPoint = if hit then hit.Position else (unitRay.Origin + unitRay.Direction * 500)

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = if hrp then (hrp.Position + Vector3.new(0, 1.6, 0)) else unitRay.Origin
	local dir = (targetPoint - origin)
	if dir.Magnitude < 0.05 then
		dir = unitRay.Direction
	end
	return origin, dir.Unit
end

local function tryShootEquipped(onlyIfAuto: boolean)
	if not MatchMode.IsSurvival() or cardOverlay.Visible or shopOverlay.Visible or endModal.Visible then
		return
	end
	local char = player.Character
	if not char or char:GetAttribute("Downed") == true then
		return
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool or tool:GetAttribute("SurvivalWeaponId") == nil then
		return
	end
	if onlyIfAuto and tool:GetAttribute("AutoFire") ~= true then
		return
	end
	local origin, dir = getAimRay()
	fireRE:FireServer(origin, dir)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if not MatchMode.IsSurvival() then
		return
	end
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isHoldingFire = true
		tryShootEquipped(false)
	elseif input.KeyCode == Enum.KeyCode.R then
		reloadRE:FireServer()
	elseif input.KeyCode == Enum.KeyCode.H then
		tacticalRE:FireServer("Medkit")
	elseif input.KeyCode == Enum.KeyCode.T then
		tacticalRE:FireServer("Turret")
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isHoldingFire = false
	end
end)

RunService.RenderStepped:Connect(function()
	if not MatchMode.IsSurvival() then
		return
	end

	if isHoldingFire then
		tryShootEquipped(true)
	end

	-- Atualiza HP / Colete / Créditos / Táticos / Munição
	local rawCred = player:GetAttribute("SurvivalCredits")
	creditsLbl.Text = string.format("⚡ %d CRÉDITOS", if typeof(rawCred) == "number" then rawCred else 0)
	if shopOverlay.Visible then
		shopCreditsBadge.Text = creditsLbl.Text
	end

	local medCount = tonumber(player:GetAttribute("Medkits")) or 0
	local turCount = tonumber(player:GetAttribute("TurretsAvailable")) or 0
	medkitBtn.Text = string.format("[H] Kit Médico (%d)", medCount)
	turretBtn.Text = string.format("[T] Torreta (%d)", turCount)

	local rawArmor = tonumber(player:GetAttribute("Armor")) or 0
	armorBarFill.Size = UDim2.fromScale(math.clamp(rawArmor / 150, 0, 1), 1)
	armorText.Text = string.format("COLETE: %d", math.round(rawArmor))

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local ratio = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
		hpBarFill.Size = UDim2.fromScale(ratio, 1)
		hpBarFill.BackgroundColor3 = if char and char:GetAttribute("Downed") == true
			then Config.Colors.IFSulRed
			else Config.Colors.IFSulGreen
		hpText.Text = if char and char:GetAttribute("Downed") == true
			then "⚠️ CAÍDO — AGUARDANDO SOCORRO!"
			else string.format("VIDA: %d / %d", math.ceil(hum.Health), math.round(hum.MaxHealth))
	end

	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("SurvivalWeaponId") ~= nil then
		ammoPanel.Visible = true
		weaponNameLbl.Text = tool.Name
		if tool:GetAttribute("IsMelee") == true then
			ammoCountLbl.Text = "∞ CORPO A CORPO"
			reloadBtn.Visible = false
		elseif tool:GetAttribute("Reloading") == true then
			ammoCountLbl.Text = "RECARREGANDO..."
			reloadBtn.Visible = false
		else
			local mag = tonumber(tool:GetAttribute("Mag")) or 0
			local res = tonumber(tool:GetAttribute("Reserve")) or 0
			ammoCountLbl.Text = string.format("%d / %d", mag, res)
			reloadBtn.Visible = true
		end
	else
		ammoPanel.Visible = false
	end
end)

-- Efeitos Visuais 3D (Tracers, Explosões, Hitmarker e Números de Dano)
fxRE.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any)
	if kind == "Beam" then
		local p0: Vector3, p1: Vector3, col: Color3, dur: number = a, b, c, d or 0.08
		local dist = (p1 - p0).Magnitude
		if dist < 0.2 then
			return
		end
		local tracer = Instance.new("Part")
		tracer.Anchored = true
		tracer.CanCollide = false
		tracer.CanQuery = false
		tracer.CanTouch = false
		tracer.Material = Enum.Material.Neon
		tracer.Color = col
		tracer.Transparency = 0.2
		tracer.Size = Vector3.new(0.14, 0.14, dist)
		tracer.CFrame = CFrame.lookAt((p0 + p1) * 0.5, p1)
		tracer.Parent = Workspace
		TweenService:Create(tracer, TweenInfo.new(dur), { Transparency = 1 }):Play()
		Debris:AddItem(tracer, dur + 0.02)
	elseif kind == "Blast" then
		local center: Vector3, radius: number, col: Color3 = a, b, c
		local sphere = Instance.new("Part")
		sphere.Shape = Enum.PartType.Ball
		sphere.Anchored = true
		sphere.CanCollide = false
		sphere.CanQuery = false
		sphere.CanTouch = false
		sphere.Material = Enum.Material.Neon
		sphere.Color = col
		sphere.Transparency = 0.35
		sphere.Size = Vector3.new(2, 2, 2)
		sphere.Position = center
		sphere.Parent = Workspace
		TweenService:Create(
			sphere,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1 }
		):Play()
		Debris:AddItem(sphere, 0.32)
	elseif kind == "HitNumber" then
		local hitPos: Vector3, dmg: number, isCrit: boolean, killed: boolean = a, b, c, d
		hitMarker.TextColor3 = if killed
			then Color3.fromRGB(250, 204, 21)
			elseif isCrit then Color3.fromRGB(255, 165, 40)
			else Color3.fromRGB(255, 75, 75)
		hitMarker.Visible = true
		task.delay(0.11, function()
			hitMarker.Visible = false
		end)

		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Transparency = 1
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.Position = hitPos + Vector3.new((math.random() - 0.5) * 1.6, 1.5, (math.random() - 0.5) * 1.6)
		p.Parent = Workspace

		local bbg = Instance.new("BillboardGui")
		bbg.Size = UDim2.fromOffset(90, 32)
		bbg.AlwaysOnTop = true
		bbg.Parent = p

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextScaled = true
		lbl.TextStrokeTransparency = 0.25
		lbl.TextColor3 = if isCrit then Color3.fromRGB(255, 214, 50) else Color3.new(1, 1, 1)
		lbl.Text = if isCrit then ("★" .. tostring(dmg)) else tostring(dmg)
		lbl.Parent = bbg

		TweenService:Create(p, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = p.Position + Vector3.new(0, 3.2, 0),
		}):Play()
		TweenService:Create(lbl, TweenInfo.new(0.55), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(p, 0.6)
	end
end)
