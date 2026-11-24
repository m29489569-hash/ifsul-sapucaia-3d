--!strict
-- Controlador Principal de Partida do Modo "Sobrevivência no Câmpus" (IFSul Sapucaia 3D)
-- Orquestra Ondas -> Draft de 3 Cartas de Habilidade -> Nova Loja de Upgrades na Tela ->
-- Sistema Cooperativo de Jogador Caído/Reviver [E] -> Vitória/Fim de Jogo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local Config = require(IFSulFolder:WaitForChild("Config"))
local MatchMode = require(IFSulFolder:WaitForChild("MatchMode"))
local SurvivalCatalog = require(IFSulFolder:WaitForChild("SurvivalCatalog"))

local SurvivalWeapons = require(script.Parent:WaitForChild("SurvivalWeapons"))
local SurvivalInvaders = require(script.Parent:WaitForChild("SurvivalInvaders"))
local SurvivalEvents = require(script.Parent:WaitForChild("SurvivalEvents"))

local remotes = IFSulFolder:FindFirstChild("Remotes") :: Folder?
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = IFSulFolder
end

local function ensureRE(name: string): RemoteEvent
	local ex = remotes:FindFirstChild(name)
	if ex and ex:IsA("RemoteEvent") then
		return ex
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = remotes
	return re
end

local function ensureRF(name: string): RemoteFunction
	local ex = remotes:FindFirstChild(name)
	if ex and ex:IsA("RemoteFunction") then
		return ex
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = remotes
	return rf
end

local matchStateRE = ensureRE("SurvivalMatchState")
local cardOfferRE = ensureRE("SurvivalCardOffer")
local pickCardRE = ensureRE("SurvivalPickCard")
local shopBuyRF = ensureRF("SurvivalShopBuy")
local shopReadyRE = ensureRE("SurvivalShopReady")
local toastRE = ensureRE("SurvivalToast")
local fxRE = ensureRE("SurvivalFX")

local rng = Random.new()

local matchRunning = false
local matchSessionId = 0
local currentWave = 0
local currentPhase: "Idle" | "Prep" | "Wave" | "CardDraft" | "Shop" | "VictoryChoice" | "GameOver" = "Idle"
local phaseEndsAt = 0
local totalToSpawnInWave = 0
local spawnedInWave = 0
local activeMissionState: { [string]: any }? = nil

local pendingCardOffers: { [Player]: { string } } = {}
local cardChosenThisWave: { [Player]: boolean } = {}
local shopReadyPlayers: { [Player]: boolean } = {}
local purchaseCountsByPlayer: { [Player]: { [string]: number } } = {}

local function ensureLeaderstats(player: Player)
	local ls = player:FindFirstChild("leaderstats") :: Folder?
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local function ensureInt(name: string): IntValue
		local v = ls:FindFirstChild(name) :: IntValue?
		if not v then
			v = Instance.new("IntValue")
			v.Name = name
			v.Parent = ls
		end
		return v
	end
	ensureInt("Onda").Value = currentWave
	local st = SurvivalWeapons.GetStats(player)
	ensureInt("Abates").Value = if st then st.kills else 0
end

local function updateAllLeaderstats()
	for _, p in ipairs(Players:GetPlayers()) do
		if MatchMode.IsSurvival() then
			ensureLeaderstats(p)
		end
	end
end

local function broadcastMatchState(extraBanner: string?)
	local remainingAlive = SurvivalInvaders.GetAliveCount() + math.max(0, totalToSpawnInWave - spawnedInWave)
	local readyCount = 0
	local totalPlayers = #Players:GetPlayers()
	for _, p in ipairs(Players:GetPlayers()) do
		if shopReadyPlayers[p] then
			readyCount += 1
		end
	end

	matchStateRE:FireAllClients({
		active = MatchMode.IsSurvival() and matchRunning,
		wave = currentWave,
		targetWaves = SurvivalCatalog.TotalTargetWaves,
		phase = currentPhase,
		timeLeft = math.max(0, math.ceil(phaseEndsAt - os.clock())),
		enemiesRemaining = remainingAlive,
		readyCount = readyCount,
		totalPlayers = totalPlayers,
		mission = activeMissionState,
		banner = extraBanner,
	})
end

local function playGlobalSound(soundId: string, volume: number, speed: number?)
	local snd = Instance.new("Sound")
	snd.SoundId = soundId
	snd.Volume = volume
	snd.PlaybackSpeed = speed or 1.0
	snd.Parent = SoundService
	snd:Play()
	snd.Ended:Connect(function()
		snd:Destroy()
	end)
	task.delay(10, function()
		if snd.Parent then
			snd:Destroy()
		end
	end)
end

-- Revive um jogador que estava no estado Caído
local function reviveCharacter(player: Player, healRatio: number)
	local char = player.Character
	if not char or char:GetAttribute("Downed") ~= true then
		return
	end
	char:SetAttribute("Downed", false)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.PlatformStand = false
		hum.JumpPower = 50
		hum.Health = math.max(35, math.round(hum.MaxHealth * healRatio))
		local st = SurvivalWeapons.GetStats(player)
		local mult = if st then st.moveSpeedMult else 1
		hum.WalkSpeed = Config.WalkSpeed * mult
	end
	for _, childName in ipairs({ "DownedHighlight", "DownedBillboard", "RevivePrompt" }) do
		local inst = char:FindFirstChild(childName, true)
		if inst then
			inst:Destroy()
		end
	end
end

local function countStandingPlayers(): number
	local standing = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char and char:GetAttribute("Downed") ~= true and hum and hum.Health > 0 then
			standing += 1
		end
	end
	return standing
end

-- Coloca o jogador em estado Caído (se houver equipe viva) ou encerra se todos caírem
local function putPlayerDowned(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not hum or not hrp or char:GetAttribute("Downed") == true then
		return
	end

	-- Em partida solo (1 jogador), não há quem reviva -> derrota imediata se zerar HP
	if #Players:GetPlayers() <= 1 then
		char:SetAttribute("Downed", true)
		hum.Health = 0
		return
	end

	char:SetAttribute("Downed", true)
	hum.Health = math.max(25, math.round(hum.MaxHealth * 0.25))
	hum.WalkSpeed = 3.5
	hum.JumpPower = 0
	hum:UnequipTools()

	local hl = Instance.new("Highlight")
	hl.Name = "DownedHighlight"
	hl.FillColor = Config.Colors.IFSulRed
	hl.FillTransparency = 0.45
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = char

	local bbg = Instance.new("BillboardGui")
	bbg.Name = "DownedBillboard"
	bbg.Size = UDim2.fromOffset(180, 44)
	bbg.StudsOffset = Vector3.new(0, 3.8, 0)
	bbg.AlwaysOnTop = true
	bbg.Parent = hrp

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundColor3 = Color3.fromRGB(165, 22, 26)
	lbl.BackgroundTransparency = 0.12
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.Text = "⚠️ CAÍDO! REVIVER [E]"
	lbl.Parent = bbg

	local lc = Instance.new("UICorner")
	lc.CornerRadius = UDim.new(0, 8)
	lc.Parent = lbl

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Reviver " .. player.DisplayName
	prompt.ObjectText = "Segure para levantar o colega"
	prompt.HoldDuration = SurvivalCatalog.ReviveHoldSeconds
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = hrp

	toastRE:FireAllClients(player.DisplayName .. " caiu! Aproxime-se e segure [E] para reviver!", false)

	prompt.Triggered:Connect(function(savior: Player)
		if savior == player then
			return
		end
		if savior.Character and savior.Character:GetAttribute("Downed") ~= true then
			reviveCharacter(player, 0.60)
			local sst = SurvivalWeapons.GetStats(savior)
			if sst then
				sst.credits += math.round(60 * sst.creditMult)
				SurvivalWeapons.SyncPlayerAttributes(savior)
			end
			toastRE:FireAllClients(savior.DisplayName .. " reviveu " .. player.DisplayName .. "! (+60 Créditos)", true)
		end
	end)

	-- Sangramento gradual caso ninguém reviva a tempo
	local sessionSnap = matchSessionId
	task.spawn(function()
		local bleedLeft = SurvivalCatalog.DownedBleedoutSeconds
		while bleedLeft > 0 and matchRunning and matchSessionId == sessionSnap do
			if not char.Parent or char:GetAttribute("Downed") ~= true then
				return
			end
			task.wait(1.0)
			bleedLeft -= 1
		end
		if char.Parent and char:GetAttribute("Downed") == true and matchRunning and matchSessionId == sessionSnap then
			hum.Health = 0
		end
	end)
end

-- Dano dos invasores nos jogadores (absorvendo primeiro no Colete/Armor)
local function handlePlayerHitByInvader(player: Player, damage: number)
	if not matchRunning or currentPhase ~= "Wave" then
		return
	end
	local char = player.Character
	if not char or char:GetAttribute("Downed") == true then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end

	local rawArmor = player:GetAttribute("Armor")
	local armor = if typeof(rawArmor) == "number" then rawArmor else 0
	local remainingDmg = damage
	if armor > 0 then
		local absorbed = math.min(armor, remainingDmg)
		armor -= absorbed
		remainingDmg -= absorbed
		player:SetAttribute("Armor", armor)
	end

	if remainingDmg > 0 then
		if hum.Health - remainingDmg <= 0.5 then
			putPlayerDowned(player)
		else
			hum:TakeDamage(remainingDmg)
		end
	end
end

-- Callback quando um jogador causa dano ou elimina um invasor
SurvivalWeapons.Init(remotes :: Folder, function(attacker: Player, enemyModel: Model, damage: number, killed: boolean, hitPos: Vector3, isCrit: boolean)
	fxRE:FireClient(attacker, "HitNumber", hitPos, damage, isCrit, killed)
	local st = SurvivalWeapons.GetStats(attacker)
	if not st then
		return
	end

	if killed then
		st.kills += 1
		local baseReward = enemyModel:GetAttribute("CreditReward")
		local reward = if typeof(baseReward) == "number" then baseReward else 22
		st.credits += math.round(reward * st.creditMult)
		SurvivalWeapons.SyncPlayerAttributes(attacker)
		updateAllLeaderstats()
		broadcastMatchState()
	else
		-- Pequeno ganho por dano contínuo (útil contra Chefões)
		st.credits += math.max(1, math.floor(damage * 0.06 * st.creditMult))
		SurvivalWeapons.SyncPlayerAttributes(attacker)
	end
end)

-- Sorteia 3 Cartas de Habilidade distintas ponderadas por raridade para um jogador
local function rollThreeCardsForPlayer(player: Player): { SurvivalCatalog.SkillCardDef }
	local st = SurvivalWeapons.GetStats(player)
	local counts = if st then st.cardCounts else {}

	local available: { SurvivalCatalog.SkillCardDef } = {}
	for _, card in ipairs(SurvivalCatalog.SkillCards) do
		if (counts[card.id] or 0) < card.maxStacks then
			table.insert(available, card)
		end
	end
	if #available < 3 then
		available = table.clone(SurvivalCatalog.SkillCards)
	end

	local chosen: { SurvivalCatalog.SkillCardDef } = {}
	local pool = table.clone(available)
	for _ = 1, math.min(3, #pool) do
		local totalW = 0
		for _, c in ipairs(pool) do
			totalW += SurvivalCatalog.RarityWeights[c.rarity] or 20
		end
		local roll = rng:NextNumber(0, totalW)
		local acc = 0
		local pickedIdx = 1
		for idx, c in ipairs(pool) do
			acc += SurvivalCatalog.RarityWeights[c.rarity] or 20
			if roll <= acc then
				pickedIdx = idx
				break
			end
		end
		table.insert(chosen, pool[pickedIdx])
		table.remove(pool, pickedIdx)
	end
	return chosen
end

pickCardRE.OnServerEvent:Connect(function(player: Player, cardId: unknown)
	if not matchRunning or currentPhase ~= "CardDraft" or typeof(cardId) ~= "string" then
		return
	end
	if cardChosenThisWave[player] then
		return
	end
	local offered = pendingCardOffers[player]
	if not offered then
		return
	end
	local valid = false
	for _, id in ipairs(offered) do
		if id == cardId then
			valid = true
			break
		end
	end
	if not valid then
		return
	end

	cardChosenThisWave[player] = true
	SurvivalWeapons.ApplySkillCard(player, cardId)
	local card = SurvivalCatalog.GetCard(cardId)
	if card then
		toastRE:FireClient(player, "Carta equipada: " .. card.name .. "!", true)
	end
end)

shopReadyRE.OnServerEvent:Connect(function(player: Player, action: unknown)
	if not matchRunning then
		return
	end
	if action == "RestartMatch" and (currentPhase == "GameOver" or currentPhase == "VictoryChoice") then
		task.spawn(function()
			stopSurvivalSession()
			task.wait(0.25)
			if MatchMode.IsSurvival() then
				startSurvivalSession()
			else
				MatchMode.SetSurvivalServer(true)
			end
		end)
		return
	elseif action == "ContinueEndless" and currentPhase == "VictoryChoice" then
		shopReadyPlayers[player] = true
		broadcastMatchState()
		return
	end

	if currentPhase == "Shop" then
		shopReadyPlayers[player] = true
		broadcastMatchState()
	end
end)

shopBuyRF.OnServerInvoke = function(player: Player, itemKind: unknown, itemId: unknown)
	if not matchRunning or currentPhase ~= "Shop" then
		return { ok = false, message = "A loja só pode ser usada no intervalo entre as ondas." }
	end
	if typeof(itemKind) ~= "string" or typeof(itemId) ~= "string" then
		return { ok = false, message = "Seleção inválida." }
	end
	local st = SurvivalWeapons.GetStats(player)
	if not st then
		return { ok = false, message = "Jogador não inicializado na partida." }
	end

	if itemKind == "Weapon" then
		local wdef = SurvivalCatalog.GetWeapon(itemId)
		if not wdef then
			return { ok = false, message = "Arma não encontrada." }
		end
		local curInSlot = st.slots[wdef.slot]
		if curInSlot and curInSlot.weaponId == wdef.id then
			return { ok = false, message = "Você já está com " .. wdef.name .. " equipada!" }
		end
		if st.credits < wdef.price then
			return { ok = false, message = "Créditos insuficientes (" .. tostring(wdef.price) .. " necessários)." }
		end
		st.credits -= wdef.price
		SurvivalWeapons.GrantOrReplaceWeapon(player, wdef.id, true)
		SurvivalWeapons.SyncPlayerAttributes(player)
		return { ok = true, message = wdef.name .. " adquirida e equipada!" }
	elseif itemKind == "Upgrade" then
		local udef = SurvivalCatalog.GetUpgrade(itemId)
		if not udef then
			return { ok = false, message = "Upgrade não encontrado." }
		end
		purchaseCountsByPlayer[player] = purchaseCountsByPlayer[player] or {}
		local boughtCount = purchaseCountsByPlayer[player][udef.id] or 0

		local curLevel = if udef.id == "weapon_upgrade" then st.weaponUpgradeLevel else boughtCount
		if udef.id == "weapon_upgrade" and st.weaponUpgradeLevel >= udef.maxLevel then
			return { ok = false, message = "Suas armas já atingiram o Nível Máximo (Nv. 5)!" }
		elseif udef.id == "pocket_medkit" and st.medkits >= 5 then
			return { ok = false, message = "Limite máximo de 5 Kits Médicos atingido!" }
		elseif udef.id == "deploy_turret" and st.turretsAvailable >= 3 then
			return { ok = false, message = "Limite de 3 Torretas prontas no inventário atingido!" }
		end

		local price = math.round(udef.basePrice * (udef.priceScale ^ (if udef.id == "weapon_upgrade" then (curLevel - 1) else boughtCount)))
		if st.credits < price then
			return { ok = false, message = "Você precisa de " .. tostring(price) .. " Créditos." }
		end

		st.credits -= price
		purchaseCountsByPlayer[player][udef.id] = boughtCount + 1

		if udef.id == "weapon_upgrade" then
			st.weaponUpgradeLevel += 1
			SurvivalWeapons.RebuildPlayerLoadoutTools(player)
			SurvivalWeapons.SyncPlayerAttributes(player)
			return {
				ok = true,
				message = string.format("Armas evoluídas para Nível %d!", st.weaponUpgradeLevel),
				nextPrice = math.round(udef.basePrice * (udef.priceScale ^ (st.weaponUpgradeLevel - 1))),
			}
		elseif udef.id == "ammo_refill" then
			SurvivalWeapons.RefillAllAmmo(player)
			SurvivalWeapons.SyncPlayerAttributes(player)
			return { ok = true, message = "Munição 100% recarregada!" }
		elseif udef.id == "armor_vest" then
			local curArmor = player:GetAttribute("Armor")
			local armorNum = if typeof(curArmor) == "number" then curArmor else 0
			player:SetAttribute("Armor", math.min(200, armorNum + 75))
			SurvivalWeapons.SyncPlayerAttributes(player)
			return { ok = true, message = "+75 de Colete Balístico equipado!" }
		elseif udef.id == "pocket_medkit" then
			st.medkits += 1
			SurvivalWeapons.SyncPlayerAttributes(player)
			return { ok = true, message = "+1 Kit Médico [H] adicionado!" }
		elseif udef.id == "deploy_turret" then
			st.turretsAvailable += 1
			SurvivalWeapons.SyncPlayerAttributes(player)
			return { ok = true, message = "+1 Torreta Sentinela [T] pronta para posicionar!" }
		end
	end

	return { ok = false, message = "Operação desconhecida." }
end

local function spawnOrTeleportPlayerIntoMatch(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then
		player:LoadCharacter()
		char = player.Character or player.CharacterAdded:Wait()
		hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
	end
	local hrp = char and char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if char and hrp and hum then
		char:SetAttribute("Downed", false)
		hum.MaxHealth = 100
		hum.Health = 100
		local offset = Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))
		char:PivotTo(CFrame.new(SurvivalCatalog.MatchSpawn + offset))
	end
	SurvivalWeapons.SetupPlayerForMatch(player)
	ensureLeaderstats(player)
end

local function cleanupMatchWorld()
	SurvivalEvents.ClearActiveMission()
	SurvivalEvents.ApplyDayOrBlackoutLighting(false)
	SurvivalInvaders.SetContext(nil, handlePlayerHitByInvader)
	SurvivalWeapons.SetTurretsFolder(nil)

	local existing = Workspace:FindFirstChild("IFSul_Survival")
	if existing then
		existing:Destroy()
	end

	table.clear(pendingCardOffers)
	table.clear(cardChosenThisWave)
	table.clear(shopReadyPlayers)
	table.clear(purchaseCountsByPlayer)

	for _, p in ipairs(Players:GetPlayers()) do
		reviveCharacter(p, 1.0)
		SurvivalWeapons.ResetPlayerToLobby(p)
		local ls = p:FindFirstChild("leaderstats")
		if ls then
			ls:Destroy()
		end
		if p.Character then
			p.Character:PivotTo(CFrame.lookAt(Config.SpawnPosition, Config.SpawnLookAt))
		end
	end
end

local function startSurvivalSession()
	if matchRunning then
		return
	end
	matchRunning = true
	matchSessionId += 1
	local sessionId = matchSessionId
	currentWave = 0
	currentPhase = "Prep"

	local oldRoot = Workspace:FindFirstChild("IFSul_Survival")
	if oldRoot then
		oldRoot:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "IFSul_Survival"
	root.Parent = Workspace

	local enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = root

	local cratesFolder = Instance.new("Folder")
	cratesFolder.Name = "SupplyCrates"
	cratesFolder.Parent = root

	local missionFolder = Instance.new("Folder")
	missionFolder.Name = "Mission"
	missionFolder.Parent = root

	local turretsFolder = Instance.new("Folder")
	turretsFolder.Name = "Turrets"
	turretsFolder.Parent = root

	SurvivalWeapons.SetTurretsFolder(turretsFolder)
	SurvivalInvaders.SetContext(enemiesFolder, handlePlayerHitByInvader)
	SurvivalEvents.SetContext(
		cratesFolder,
		missionFolder,
		function(mState)
			activeMissionState = mState
			broadcastMatchState()
		end,
		function(creditsEach, msg, reviveAll, grantReactiveAmmo)
			for _, p in ipairs(Players:GetPlayers()) do
				local st = SurvivalWeapons.GetStats(p)
				if st then
					st.credits += math.round(creditsEach * st.creditMult)
					if grantReactiveAmmo then
						st.reactiveAmmoUntil = os.clock() + 45
					end
					SurvivalWeapons.SyncPlayerAttributes(p)
				end
				if reviveAll then
					reviveCharacter(p, 0.85)
					if p.Character then
						local hum = p.Character:FindFirstChildOfClass("Humanoid")
						if hum and hum.Health > 0 then
							hum.Health = hum.MaxHealth
						end
					end
				end
			end
			toastRE:FireAllClients(msg, true)
		end
	)

	-- Aguarda até haver ao menos 1 jogador carregado
	while #Players:GetPlayers() == 0 and matchRunning and matchSessionId == sessionId do
		task.wait(0.3)
	end
	if not matchRunning or matchSessionId ~= sessionId then
		return
	end

	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(spawnOrTeleportPlayerIntoMatch, p)
	end

	-- Contagem rápida inicial de 5s
	phaseEndsAt = os.clock() + 5
	toastRE:FireAllClients("Sobrevivência iniciada! Permaneça vivo dentro do câmpus do IFSul!", true)
	while os.clock() < phaseEndsAt and matchRunning and matchSessionId == sessionId do
		broadcastMatchState("Prepare-se! A Onda 1 vai começar!")
		task.wait(0.5)
	end

	-- Loop principal das Ondas
	while matchRunning and matchSessionId == sessionId and MatchMode.IsSurvival() do
		currentWave += 1
		currentPhase = "Wave"
		updateAllLeaderstats()

		-- Levanta colegas que caíram ou morreram na onda anterior
		for _, p in ipairs(Players:GetPlayers()) do
			if not p.Character or (p.Character:FindFirstChildOfClass("Humanoid") and (p.Character:FindFirstChildOfClass("Humanoid") :: Humanoid).Health <= 0) then
				p:LoadCharacter()
				task.wait(0.2)
				if p.Character then
					p.Character:PivotTo(CFrame.new(SurvivalCatalog.MatchSpawn))
				end
				SurvivalWeapons.RebuildPlayerLoadoutTools(p)
			else
				reviveCharacter(p, 0.55)
			end
			SurvivalWeapons.SyncPlayerAttributes(p)
		end

		-- Brechas ativas nesta onda
		local activeBreaches: { SurvivalCatalog.BreachDef } = {}
		local newlyOpenedBreach: string? = nil
		for _, b in ipairs(SurvivalCatalog.Breaches) do
			if currentWave >= b.minWave then
				table.insert(activeBreaches, b)
				if currentWave == b.minWave and currentWave > 1 then
					newlyOpenedBreach = b.name
				end
			end
		end

		playGlobalSound(SurvivalCatalog.Sounds.SchoolBellWaveStart, 0.55, 1.0)
		if newlyOpenedBreach then
			toastRE:FireAllClients("⚠️ NOVA BRECHA ABERTA: " .. newlyOpenedBreach .. "!", false)
		else
			toastRE:FireAllClients(string.format("🔔 ONDA %d INICIADA!", currentWave), true)
		end

		SurvivalEvents.SpawnWaveSupplyCrates(currentWave)
		SurvivalEvents.TryStartSectorMission(currentWave)

		local pCount = math.max(1, #Players:GetPlayers())
		local isBossWave = (currentWave % 5 == 0)
		totalToSpawnInWave = math.round((6 + currentWave * 3.5) * (1 + (pCount - 1) * 0.35)) + (if isBossWave then 1 else 0)
		spawnedInWave = 0
		phaseEndsAt = os.clock()

		-- Spawner assíncrono controlado (máximo 26 inimigos vivos simultâneos para 60 FPS liso)
		task.spawn(function()
			for i = 1, totalToSpawnInWave do
				if not matchRunning or matchSessionId ~= sessionId or currentPhase ~= "Wave" then
					break
				end
				while SurvivalInvaders.GetAliveCount() >= 26 and matchRunning and matchSessionId == sessionId and currentPhase == "Wave" do
					task.wait(0.4)
				end
				local breach = activeBreaches[((i - 1) % #activeBreaches) + 1]
				local spawnBossNow = isBossWave and (i == totalToSpawnInWave)
				SurvivalInvaders.SpawnInvader(currentWave, pCount, breach, spawnBossNow)
				spawnedInWave += 1
				broadcastMatchState()
				task.wait(math.max(0.32, 1.15 - currentWave * 0.04))
			end
		end)

		-- Monitora término da onda ou queda de todo o esquadrão
		local squadWiped = false
		while matchRunning and matchSessionId == sessionId do
			broadcastMatchState()
			if countStandingPlayers() == 0 then
				squadWiped = true
				break
			end
			if spawnedInWave >= totalToSpawnInWave and SurvivalInvaders.GetAliveCount() == 0 then
				break
			end
			task.wait(0.4)
		end

		if not matchRunning or matchSessionId ~= sessionId then
			return
		end

		SurvivalEvents.ClearActiveMission()

		if squadWiped then
			currentPhase = "GameOver"
			phaseEndsAt = os.clock() + 30
			broadcastMatchState("FIM DE JOGO — O câmpus foi tomado na Onda " .. tostring(currentWave) .. "!")
			while currentPhase == "GameOver" and matchRunning and matchSessionId == sessionId do
				task.wait(0.5)
			end
			return
		end

		-- Bônus de fim de onda + cura da carta Combo da Cantina
		playGlobalSound(SurvivalCatalog.Sounds.WaveCleared, 0.65, 1.15)
		local waveClearBonus = 75 + currentWave * 18
		for _, p in ipairs(Players:GetPlayers()) do
			reviveCharacter(p, 0.65)
			local st = SurvivalWeapons.GetStats(p)
			if st then
				st.credits += math.round(waveClearBonus * st.creditMult)
				local cantinaStacks = st.cardCounts["combo_cantina"] or 0
				if cantinaStacks > 0 and p.Character then
					local hum = p.Character:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						hum.Health = math.min(hum.MaxHealth, hum.Health + cantinaStacks * 25)
					end
				end
				SurvivalWeapons.SyncPlayerAttributes(p)
			end
		end

		-- Se venceu a Onda 15 (alvo principal), exibe celebração de Vitória com opção de Modo Infinito!
		if currentWave == SurvivalCatalog.TotalTargetWaves then
			currentPhase = "VictoryChoice"
			table.clear(shopReadyPlayers)
			phaseEndsAt = os.clock() + 25
			toastRE:FireAllClients("🏆 VITÓRIA! Vocês protegeram o IFSul Sapucaia até a Onda 15!", true)
			while os.clock() < phaseEndsAt and matchRunning and matchSessionId == sessionId do
				broadcastMatchState("🏆 CÂMPUS DEFENDIDO COM SUCESSO!")
				local allReady = #Players:GetPlayers() > 0
				for _, p in ipairs(Players:GetPlayers()) do
					if not shopReadyPlayers[p] then
						allReady = false
						break
					end
				end
				if allReady then
					break
				end
				task.wait(0.4)
			end
		end

		-- ETAPA 1 ENTRE ONDAS: Escolha de 1 entre 3 Cartas de Habilidade
		currentPhase = "CardDraft"
		table.clear(pendingCardOffers)
		table.clear(cardChosenThisWave)
		phaseEndsAt = os.clock() + SurvivalCatalog.CardDraftSeconds

		for _, p in ipairs(Players:GetPlayers()) do
			local cards = rollThreeCardsForPlayer(p)
			local ids: { string } = {}
			local payload: { { [string]: any } } = {}
			for _, c in ipairs(cards) do
				table.insert(ids, c.id)
				local st = SurvivalWeapons.GetStats(p)
				local curStacks = if st then (st.cardCounts[c.id] or 0) else 0
				table.insert(payload, {
					id = c.id,
					name = c.name,
					courseTag = c.courseTag,
					rarity = c.rarity,
					artAssetId = c.artAssetId,
					description = c.description,
					stacks = curStacks,
					maxStacks = c.maxStacks,
				})
			end
			pendingCardOffers[p] = ids
			cardOfferRE:FireClient(p, payload, SurvivalCatalog.CardDraftSeconds)
		end

		while os.clock() < phaseEndsAt and matchRunning and matchSessionId == sessionId do
			broadcastMatchState()
			local everyonePicked = #Players:GetPlayers() > 0
			for _, p in ipairs(Players:GetPlayers()) do
				if not cardChosenThisWave[p] then
					everyonePicked = false
					break
				end
			end
			if everyonePicked then
				break
			end
			task.wait(0.25)
		end

		-- Auto-aplica a 1ª carta para quem não clicou antes do tempo acabar
		for _, p in ipairs(Players:GetPlayers()) do
			if not cardChosenThisWave[p] and pendingCardOffers[p] and pendingCardOffers[p][1] then
				cardChosenThisWave[p] = true
				SurvivalWeapons.ApplySkillCard(p, pendingCardOffers[p][1])
			end
		end

		-- ETAPA 2 ENTRE ONDAS: Nova Loja de Upgrades na Tela
		currentPhase = "Shop"
		table.clear(shopReadyPlayers)
		phaseEndsAt = os.clock() + SurvivalCatalog.ShopPhaseSeconds

		while os.clock() < phaseEndsAt and matchRunning and matchSessionId == sessionId do
			broadcastMatchState()
			local allReady = #Players:GetPlayers() > 0
			for _, p in ipairs(Players:GetPlayers()) do
				if not shopReadyPlayers[p] then
					allReady = false
					break
				end
			end
			if allReady then
				break
			end
			task.wait(0.25)
		end
	end
end

local function stopSurvivalSession()
	if not matchRunning then
		return
	end
	matchRunning = false
	matchSessionId += 1
	currentPhase = "Idle"
	currentWave = 0
	cleanupMatchWorld()
	broadcastMatchState()
end

-- Jogadores que entrarem com a partida em andamento (ex: amigos no grupo)
Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(char: Model)
		if MatchMode.IsSurvival() and matchRunning then
			task.wait(0.15)
			char:PivotTo(CFrame.new(SurvivalCatalog.MatchSpawn))
			if SurvivalWeapons.GetStats(player) then
				SurvivalWeapons.RebuildPlayerLoadoutTools(player)
				SurvivalWeapons.SyncPlayerAttributes(player)
			else
				SurvivalWeapons.SetupPlayerForMatch(player)
			end
		end
	end)
	if MatchMode.IsSurvival() and matchRunning then
		task.spawn(spawnOrTeleportPlayerIntoMatch, player)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	pendingCardOffers[player] = nil
	cardChosenThisWave[player] = nil
	shopReadyPlayers[player] = nil
	purchaseCountsByPlayer[player] = nil
end)

if MatchMode.IsSurvival() then
	task.spawn(startSurvivalSession)
end

MatchMode.OnChanged(function(isSurvival: boolean)
	if isSurvival then
		task.spawn(startSurvivalSession)
	else
		stopSurvivalSession()
	end
end)
