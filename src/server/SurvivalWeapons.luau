--!strict
-- Sistema de Armas, Munição, Kits Médicos e Torretas Sentinelas do Modo Sobrevivência
-- Usa os modelos 3D prontos oficiais do Roblox em ServerStorage.IFSul_SurvivalAssets
-- (com evolução visual de 3 níveis nas armas) e aplica todas as sinergias das Cartas do IF.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local IFSulFolder = ReplicatedStorage:WaitForChild("IFSul")
local SurvivalCatalog = require(IFSulFolder:WaitForChild("SurvivalCatalog"))

export type WeaponInstanceState = {
	weaponId: string,
	mag: number,
	reserve: number,
	reloading: boolean,
	lastShotAt: number,
	tool: Tool?,
}

export type PlayerCombatStats = {
	credits: number,
	kills: number,
	weaponUpgradeLevel: number,
	damageMult: number,
	fireRateMult: number,
	reloadSpeedMult: number,
	moveSpeedMult: number,
	creditMult: number,
	maxHealthBonus: number,
	pierceCount: number,
	acidBurn: number,
	slowOnHit: number,
	deathExplosion: number,
	turretBoost: number,
	critChance: number,
	chainLightning: number,
	lifeOnKill: number,
	medkits: number,
	turretsAvailable: number,
	reactiveAmmoUntil: number,
	slots: {
		Primary: WeaponInstanceState?,
		Secondary: WeaponInstanceState?,
		Melee: WeaponInstanceState?,
	},
	cardCounts: { [string]: number },
}

local SurvivalWeapons = {}

local statsByPlayer: { [Player]: PlayerCombatStats } = {}
local activeTurretsFolder: Folder? = nil
local fxRemote: RemoteEvent? = nil
local onEnemyDamagedCallback: ((attacker: Player, enemyModel: Model, damage: number, killed: boolean, hitPos: Vector3, isCrit: boolean) -> ())? = nil

local rng = Random.new()

function SurvivalWeapons.Init(
	remotesFolder: Folder,
	damageCallback: (attacker: Player, enemyModel: Model, damage: number, killed: boolean, hitPos: Vector3, isCrit: boolean) -> ()
)
	onEnemyDamagedCallback = damageCallback

	local function ensureRE(name: string): RemoteEvent
		local ex = remotesFolder:FindFirstChild(name)
		if ex and ex:IsA("RemoteEvent") then
			return ex
		end
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = remotesFolder
		return re
	end

	fxRemote = ensureRE("SurvivalFX")
	local fireRE = ensureRE("SurvivalFireWeapon")
	local reloadRE = ensureRE("SurvivalReloadWeapon")
	local tacticalRE = ensureRE("SurvivalUseTactical")

	fireRE.OnServerEvent:Connect(function(player: Player, aimOrigin: unknown, aimDir: unknown)
		if typeof(aimOrigin) ~= "Vector3" or typeof(aimDir) ~= "Vector3" then
			return
		end
		if aimDir.Magnitude < 0.01 or aimDir.X ~= aimDir.X then
			return
		end
		SurvivalWeapons.HandleFire(player, aimOrigin, aimDir.Unit)
	end)

	reloadRE.OnServerEvent:Connect(function(player: Player)
		SurvivalWeapons.HandleReload(player)
	end)

	tacticalRE.OnServerEvent:Connect(function(player: Player, kind: unknown)
		if kind == "Medkit" then
			SurvivalWeapons.UsePocketMedkit(player)
		elseif kind == "Turret" then
			SurvivalWeapons.DeploySentryTurret(player)
		end
	end)
end

function SurvivalWeapons.CreateDefaultStats(): PlayerCombatStats
	return {
		credits = 150,
		kills = 0,
		weaponUpgradeLevel = 1,
		damageMult = 1.0,
		fireRateMult = 1.0,
		reloadSpeedMult = 1.0,
		moveSpeedMult = 1.0,
		creditMult = 1.0,
		maxHealthBonus = 0,
		pierceCount = 0,
		acidBurn = 0,
		slowOnHit = 0,
		deathExplosion = 0,
		turretBoost = 0,
		critChance = 0.05,
		chainLightning = 0,
		lifeOnKill = 0,
		medkits = 1,
		turretsAvailable = 0,
		reactiveAmmoUntil = 0,
		slots = {
			Primary = nil,
			Secondary = nil,
			Melee = nil,
		},
		cardCounts = {},
	}
end

function SurvivalWeapons.GetStats(player: Player): PlayerCombatStats?
	return statsByPlayer[player]
end

function SurvivalWeapons.SyncPlayerAttributes(player: Player)
	local st = statsByPlayer[player]
	if not st then
		return
	end
	player:SetAttribute("SurvivalCredits", math.floor(st.credits))
	player:SetAttribute("SurvivalKills", st.kills)
	player:SetAttribute("WeaponUpgradeLevel", st.weaponUpgradeLevel)
	player:SetAttribute("Medkits", st.medkits)
	player:SetAttribute("TurretsAvailable", st.turretsAvailable)
	player:SetAttribute("MoveSpeedMult", st.moveSpeedMult)

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and char and char:GetAttribute("Downed") ~= true then
		local targetMax = 100 + st.maxHealthBonus
		if math.abs(hum.MaxHealth - targetMax) > 0.5 then
			local delta = targetMax - hum.MaxHealth
			hum.MaxHealth = targetMax
			if delta > 0 then
				hum.Health = math.min(targetMax, hum.Health + delta)
			else
				hum.Health = math.min(targetMax, hum.Health)
			end
		end
	end
end

function SurvivalWeapons.ClearAllTools(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		backpack:ClearAllChildren()
	end
	local sg = player:FindFirstChildOfClass("StarterGear")
	if sg then
		sg:ClearAllChildren()
	end
	local char = player.Character
	if char then
		for _, ch in ipairs(char:GetChildren()) do
			if ch:IsA("Tool") then
				ch:Destroy()
			end
		end
	end
end

local function getTierIndex(upgradeLevel: number): number
	if upgradeLevel >= 5 then
		return 3
	elseif upgradeLevel >= 3 then
		return 2
	end
	return 1
end

local function computeMaxMag(def: SurvivalCatalog.WeaponDef, upgradeLevel: number): number
	if def.magSize <= 0 then
		return 0
	end
	return math.round(def.magSize * (1 + (upgradeLevel - 1) * 0.12))
end

local function computeMaxReserve(def: SurvivalCatalog.WeaponDef, upgradeLevel: number): number
	if def.reserveAmmo <= 0 then
		return 0
	end
	return math.round(def.reserveAmmo * (1 + (upgradeLevel - 1) * 0.15))
end

local function syncToolAmmoAttributes(tool: Tool?, def: SurvivalCatalog.WeaponDef, ws: WeaponInstanceState, upgradeLevel: number)
	if not tool then
		return
	end
	tool:SetAttribute("SurvivalWeaponId", def.id)
	tool:SetAttribute("Slot", def.slot)
	tool:SetAttribute("Mag", ws.mag)
	tool:SetAttribute("MaxMag", computeMaxMag(def, upgradeLevel))
	tool:SetAttribute("Reserve", ws.reserve)
	tool:SetAttribute("Reloading", ws.reloading)
	tool:SetAttribute("AutoFire", def.autoFire)
	tool:SetAttribute("IsMelee", def.magSize == 0)
	tool:SetAttribute("UpgradeLevel", upgradeLevel)
end

local function instantiateWeaponTool(player: Player, def: SurvivalCatalog.WeaponDef, ws: WeaponInstanceState, upgradeLevel: number): Tool?
	local assets = ServerStorage:FindFirstChild("IFSul_SurvivalAssets")
	local weaponsFolder = assets and assets:FindFirstChild("Weapons")
	local pack = weaponsFolder and weaponsFolder:FindFirstChild(def.assetFolder)
	if not pack then
		warn("[SurvivalWeapons] Pasta de arma não encontrada:", def.assetFolder)
		return nil
	end

	local tierIdx = math.clamp(getTierIndex(upgradeLevel), 1, #def.tierTools)
	local toolTemplateName = def.tierTools[tierIdx]
	local template = pack:FindFirstChild(toolTemplateName)
	if not template or not template:IsA("Tool") then
		template = pack:FindFirstChildOfClass("Tool")
	end
	if not template or not template:IsA("Tool") then
		return nil
	end

	local clone = template:Clone()
	clone.Name = if upgradeLevel > 1 then string.format("%s +%d", def.name, upgradeLevel - 1) else def.name
	clone.CanBeDropped = false
	clone.ManualActivationOnly = true -- Disparo controlado com precisão pelo cliente -> SurvivalFireWeapon

	for _, bp in ipairs(clone:GetDescendants()) do
		if bp:IsA("BasePart") then
			bp.Anchored = false
			bp.CanCollide = false
			bp.CollisionGroup = "SurvivalPlayers"
			if bp.Name ~= "Handle" then
				bp.Massless = true
			end
		end
	end

	syncToolAmmoAttributes(clone, def, ws, upgradeLevel)

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		clone.Parent = backpack
	end
	return clone
end

function SurvivalWeapons.GrantOrReplaceWeapon(player: Player, weaponId: string, autoEquip: boolean?): boolean
	local st = statsByPlayer[player]
	local def = SurvivalCatalog.GetWeapon(weaponId)
	if not st or not def then
		return false
	end

	local existing = st.slots[def.slot]
	if existing and existing.tool then
		existing.tool:Destroy()
	end

	local maxMag = computeMaxMag(def, st.weaponUpgradeLevel)
	local maxRes = computeMaxReserve(def, st.weaponUpgradeLevel)
	local ws: WeaponInstanceState = {
		weaponId = def.id,
		mag = maxMag,
		reserve = maxRes,
		reloading = false,
		lastShotAt = 0,
		tool = nil,
	}
	ws.tool = instantiateWeaponTool(player, def, ws, st.weaponUpgradeLevel)
	st.slots[def.slot] = ws

	if autoEquip and ws.tool and player.Character then
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum:EquipTool(ws.tool)
		end
	end
	return true
end

function SurvivalWeapons.RebuildPlayerLoadoutTools(player: Player)
	local st = statsByPlayer[player]
	if not st then
		return
	end
	local char = player.Character
	local equippedSlot: ("Primary" | "Secondary" | "Melee")? = nil
	if char then
		local curTool = char:FindFirstChildOfClass("Tool")
		if curTool then
			local slotAttr = curTool:GetAttribute("Slot")
			if slotAttr == "Primary" or slotAttr == "Secondary" or slotAttr == "Melee" then
				equippedSlot = slotAttr
			end
		end
	end

	SurvivalWeapons.ClearAllTools(player)

	for _, slotName in ipairs({ "Primary", "Secondary", "Melee" } :: { "Primary" | "Secondary" | "Melee" }) do
		local ws = st.slots[slotName]
		if ws then
			local def = SurvivalCatalog.GetWeapon(ws.weaponId)
			if def then
				ws.reloading = false
				ws.mag = computeMaxMag(def, st.weaponUpgradeLevel)
				ws.reserve = math.max(ws.reserve, computeMaxReserve(def, st.weaponUpgradeLevel))
				ws.tool = instantiateWeaponTool(player, def, ws, st.weaponUpgradeLevel)
			end
		end
	end

	local targetSlot = equippedSlot or (if st.slots.Primary then "Primary" else "Secondary")
	local toEquip = if targetSlot == "Primary"
		then st.slots.Primary
		elseif targetSlot == "Secondary" then st.slots.Secondary
		else st.slots.Melee
	if toEquip and toEquip.tool and char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			task.defer(function()
				if toEquip.tool and toEquip.tool.Parent then
					hum:EquipTool(toEquip.tool)
				end
			end)
		end
	end
end

function SurvivalWeapons.RefillAllAmmo(player: Player)
	local st = statsByPlayer[player]
	if not st then
		return
	end
	for _, slotName in ipairs({ "Primary", "Secondary", "Melee" } :: { "Primary" | "Secondary" | "Melee" }) do
		local ws = st.slots[slotName]
		if ws then
			local def = SurvivalCatalog.GetWeapon(ws.weaponId)
			if def and def.magSize > 0 then
				ws.reloading = false
				ws.mag = computeMaxMag(def, st.weaponUpgradeLevel)
				ws.reserve = computeMaxReserve(def, st.weaponUpgradeLevel)
				syncToolAmmoAttributes(ws.tool, def, ws, st.weaponUpgradeLevel)
			end
		end
	end
end

function SurvivalWeapons.SetupPlayerForMatch(player: Player)
	statsByPlayer[player] = SurvivalWeapons.CreateDefaultStats()
	player:SetAttribute("Armor", 25)
	SurvivalWeapons.ClearAllTools(player)
	SurvivalWeapons.GrantOrReplaceWeapon(player, "pistol", true)
	SurvivalWeapons.GrantOrReplaceWeapon(player, "machete", false)
	SurvivalWeapons.SyncPlayerAttributes(player)
end

function SurvivalWeapons.ResetPlayerToLobby(player: Player)
	statsByPlayer[player] = nil
	player:SetAttribute("Armor", 0)
	player:SetAttribute("MoveSpeedMult", 1)
	SurvivalWeapons.ClearAllTools(player)
end

local function findEquippedState(player: Player): (WeaponInstanceState?, SurvivalCatalog.WeaponDef?, Tool?)
	local st = statsByPlayer[player]
	local char = player.Character
	if not st or not char then
		return nil, nil, nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		return nil, nil, nil
	end
	local wid = tool:GetAttribute("SurvivalWeaponId")
	if typeof(wid) ~= "string" then
		return nil, nil, nil
	end
	local def = SurvivalCatalog.GetWeapon(wid)
	if not def then
		return nil, nil, nil
	end
	local ws = st.slots[def.slot]
	if not ws or ws.weaponId ~= wid then
		return nil, nil, nil
	end
	ws.tool = tool
	return ws, def, tool
end

local function findEnemyFromPart(part: BasePart, enemiesFolder: Folder): (Model?, Humanoid?)
	local cur: Instance? = part
	while cur and cur ~= Workspace do
		if cur.Parent == enemiesFolder and cur:IsA("Model") then
			local hum = cur:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				return cur, hum
			end
		end
		cur = cur.Parent
	end
	return nil, nil
end

local function applyDamageAndEffects(
	attacker: Player,
	st: PlayerCombatStats,
	enemyModel: Model,
	hum: Humanoid,
	rawDamage: number,
	hitPos: Vector3,
	allowProcs: boolean
)
	if hum.Health <= 0 then
		return
	end

	local isCrit = allowProcs and (rng:NextNumber() < st.critChance)
	local finalDmg = math.max(1, math.round(rawDamage * (if isCrit then 2.0 else 1.0)))

	hum:TakeDamage(finalDmg)
	local killed = hum.Health <= 0

	if onEnemyDamagedCallback then
		onEnemyDamagedCallback(attacker, enemyModel, finalDmg, killed, hitPos, isCrit)
	end

	-- Polímero desacelerador
	if allowProcs and not killed and st.slowOnHit > 0 then
		local baseSpd = enemyModel:GetAttribute("BaseWalkSpeed")
		if typeof(baseSpd) == "number" then
			local factor = math.max(0.38, 1 - st.slowOnHit)
			hum.WalkSpeed = baseSpd * factor
			local token = os.clock()
			enemyModel:SetAttribute("SlowToken", token)
			task.delay(2.5, function()
				if enemyModel.Parent and hum.Health > 0 and enemyModel:GetAttribute("SlowToken") == token then
					hum.WalkSpeed = baseSpd
				end
			end)
		end
	end

	-- Corrosão ácida (Lab 304) ou munição reativa temporária
	local acidMult = st.acidBurn + (if os.clock() < st.reactiveAmmoUntil then 0.30 else 0)
	if allowProcs and not killed and acidMult > 0 then
		local tickDmg = math.max(2, math.round(finalDmg * acidMult / 3))
		task.spawn(function()
			for _ = 1, 3 do
				task.wait(0.85)
				if not enemyModel.Parent or hum.Health <= 0 then
					break
				end
				hum:TakeDamage(tickDmg)
				local deadNow = hum.Health <= 0
				local erp = enemyModel:FindFirstChild("HumanoidRootPart") :: BasePart?
				if onEnemyDamagedCallback and erp then
					onEnemyDamagedCallback(attacker, enemyModel, tickDmg, deadNow, erp.Position, false)
				end
				if deadNow then
					break
				end
			end
		end)
	end

	-- Raio em cadeia (Física 804)
	if allowProcs and st.chainLightning > 0 then
		local enemiesFolder = Workspace:FindFirstChild("IFSul_Survival")
			and Workspace.IFSul_Survival:FindFirstChild("Enemies") :: Folder?
		if enemiesFolder then
			local jumped = 0
			for _, other in ipairs(enemiesFolder:GetChildren()) do
				if other ~= enemyModel and other:IsA("Model") then
					local ohum = other:FindFirstChildOfClass("Humanoid")
					local orp = other:FindFirstChild("HumanoidRootPart") :: BasePart?
					if ohum and ohum.Health > 0 and orp and (orp.Position - hitPos).Magnitude <= 18 then
						jumped += 1
						applyDamageAndEffects(attacker, st, other, ohum, st.chainLightning, orp.Position, false)
						if fxRemote then
							fxRemote:FireAllClients("Beam", hitPos, orp.Position, Color3.fromRGB(80, 225, 255), 0.22)
						end
						if jumped >= 2 then
							break
						end
					end
				end
			end
		end
	end

	-- Cura por abate + Explosão química ao morrer
	if killed then
		if st.lifeOnKill > 0 and attacker.Character then
			local ahum = attacker.Character:FindFirstChildOfClass("Humanoid")
			if ahum and ahum.Health > 0 and attacker.Character:GetAttribute("Downed") ~= true then
				ahum.Health = math.min(ahum.MaxHealth, ahum.Health + st.lifeOnKill)
			end
			local curArmor = attacker:GetAttribute("Armor")
			local armorNum = if typeof(curArmor) == "number" then curArmor else 0
			attacker:SetAttribute("Armor", math.min(150, armorNum + math.round(st.lifeOnKill * 0.5)))
		end

		if st.deathExplosion > 0 then
			if fxRemote then
				fxRemote:FireAllClients("Blast", hitPos, 13, Color3.fromRGB(132, 245, 96))
			end
			local enemiesFolder = Workspace:FindFirstChild("IFSul_Survival")
				and Workspace.IFSul_Survival:FindFirstChild("Enemies") :: Folder?
			if enemiesFolder then
				for _, other in ipairs(enemiesFolder:GetChildren()) do
					if other ~= enemyModel and other:IsA("Model") then
						local ohum = other:FindFirstChildOfClass("Humanoid")
						local orp = other:FindFirstChild("HumanoidRootPart") :: BasePart?
						if ohum and ohum.Health > 0 and orp and (orp.Position - hitPos).Magnitude <= 13 then
							applyDamageAndEffects(attacker, st, other, ohum, st.deathExplosion, orp.Position, false)
						end
					end
				end
			end
		end
	end
end

function SurvivalWeapons.HandleReload(player: Player)
	local st = statsByPlayer[player]
	local ws, def, tool = findEquippedState(player)
	if not st or not ws or not def or not tool then
		return
	end
	if def.magSize <= 0 or ws.reloading or ws.reserve <= 0 then
		return
	end
	local maxMag = computeMaxMag(def, st.weaponUpgradeLevel)
	if ws.mag >= maxMag then
		return
	end

	ws.reloading = true
	syncToolAmmoAttributes(tool, def, ws, st.weaponUpgradeLevel)

	local reloadSnd = tool:FindFirstChild("Reload", true)
	if reloadSnd and reloadSnd:IsA("Sound") then
		reloadSnd:Play()
	end

	local duration = math.max(0.35, def.reloadTime / math.max(0.5, st.reloadSpeedMult))
	task.delay(duration, function()
		if not ws.reloading then
			return
		end
		ws.reloading = false
		local needed = maxMag - ws.mag
		local transfer = math.min(needed, ws.reserve)
		ws.mag += transfer
		ws.reserve -= transfer
		syncToolAmmoAttributes(ws.tool, def, ws, st.weaponUpgradeLevel)
	end)
end

function SurvivalWeapons.HandleFire(player: Player, aimOrigin: Vector3, aimDir: Vector3)
	local st = statsByPlayer[player]
	local char = player.Character
	if not st or not char or char:GetAttribute("Downed") == true then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or hum.Health <= 0 or not hrp then
		return
	end
	if (aimOrigin - hrp.Position).Magnitude > 22 then
		aimOrigin = hrp.Position + Vector3.new(0, 1.6, 0)
	end

	local ws, def, tool = findEquippedState(player)
	if not ws or not def or not tool or ws.reloading then
		return
	end

	local now = os.clock()
	local effectiveRate = def.fireRate * st.fireRateMult
	local minInterval = (1 / math.max(0.2, effectiveRate)) * 0.88
	if (now - ws.lastShotAt) < minInterval then
		return
	end

	if def.magSize > 0 then
		if ws.mag <= 0 then
			SurvivalWeapons.HandleReload(player)
			return
		end
		ws.mag -= 1
		syncToolAmmoAttributes(tool, def, ws, st.weaponUpgradeLevel)
	end
	ws.lastShotAt = now

	-- Som original do modelo pronto da arma (ou som nativo de espada para o facão)
	local firedSnd = tool:FindFirstChild("Fired", true) or tool:FindFirstChildOfClass("Sound")
	if firedSnd and firedSnd:IsA("Sound") then
		firedSnd.PlaybackSpeed = rng:NextNumber(0.95, 1.06)
		firedSnd:Play()
	end

	local upgradeDmgMult = 1 + (st.weaponUpgradeLevel - 1) * 0.22
	local shotDamage = def.baseDamage * upgradeDmgMult * st.damageMult

	local survivalRoot = Workspace:FindFirstChild("IFSul_Survival")
	local enemiesFolder = survivalRoot and survivalRoot:FindFirstChild("Enemies") :: Folder?

	-- Arma corpo a corpo (Facão): varredura em arco frontal
	if def.magSize == 0 then
		if enemiesFolder then
			for _, enemy in ipairs(enemiesFolder:GetChildren()) do
				if enemy:IsA("Model") then
					local ehum = enemy:FindFirstChildOfClass("Humanoid")
					local erp = enemy:FindFirstChild("HumanoidRootPart") :: BasePart?
					if ehum and ehum.Health > 0 and erp then
						local delta = erp.Position - hrp.Position
						if delta.Magnitude <= def.rangeStuds then
							if delta.Unit:Dot(aimDir) > -0.15 then
								applyDamageAndEffects(player, st, enemy, ehum, shotDamage, erp.Position, true)
							end
						end
					end
				end
			end
		end
		if ws.mag == 0 and def.magSize > 0 then
			SurvivalWeapons.HandleReload(player)
		end
		return
	end

	local tipAtt = tool:FindFirstChild("TipAttachment", true) :: Attachment?
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	local muzzlePos = if tipAtt
		then tipAtt.WorldPosition
		elseif handle then handle.Position
		else (hrp.Position + Vector3.new(0, 1.5, 0))

	local excludeList: { Instance } = { char }
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer.Character then
			table.insert(excludeList, otherPlayer.Character)
		end
	end
	local perim = Workspace:FindFirstChild("IFSul_SurvivalPerimeter")
	if perim then
		table.insert(excludeList, perim)
	end

	for _ = 1, def.pellets do
		local spreadRad = math.rad(def.spreadDeg)
		local rx = (rng:NextNumber() - 0.5) * spreadRad
		local ry = (rng:NextNumber() - 0.5) * spreadRad
		local dirCF = CFrame.lookAt(Vector3.zero, aimDir) * CFrame.Angles(rx, ry, 0)
		local rayDir = dirCF.LookVector * def.rangeStuds

		local localExclude = table.clone(excludeList)
		local maxHits = 1 + st.pierceCount
		local endPos = aimOrigin + rayDir

		for hitNum = 1, maxHits do
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = localExclude
			local result = Workspace:Raycast(aimOrigin, rayDir, params)
			if not result then
				break
			end
			endPos = result.Position

			if def.isExplosive then
				local radius = def.splashRadius or 16
				if fxRemote then
					fxRemote:FireAllClients("Blast", endPos, radius, Color3.fromRGB(255, 148, 42))
				end
				if enemiesFolder then
					for _, enemy in ipairs(enemiesFolder:GetChildren()) do
						if enemy:IsA("Model") then
							local ehum = enemy:FindFirstChildOfClass("Humanoid")
							local erp = enemy:FindFirstChild("HumanoidRootPart") :: BasePart?
							if ehum and ehum.Health > 0 and erp then
								local dist = (erp.Position - endPos).Magnitude
								if dist <= radius then
									local falloff = math.clamp(1 - (dist / (radius * 1.25)), 0.35, 1)
									applyDamageAndEffects(player, st, enemy, ehum, shotDamage * falloff, erp.Position, true)
								end
							end
						end
					end
				end
				break
			end

			if enemiesFolder then
				local enemyModel, ehum = findEnemyFromPart(result.Instance, enemiesFolder)
				if enemyModel and ehum then
					local isHeadshot = result.Instance.Name == "Head"
					local mult = if isHeadshot then 1.45 else 1.0
					applyDamageAndEffects(player, st, enemyModel, ehum, shotDamage * mult, result.Position, true)
					table.insert(localExclude, enemyModel)
					if hitNum < maxHits then
						continue
					end
				end
			end
			break
		end

		if fxRemote then
			local beamColor = if os.clock() < st.reactiveAmmoUntil
				then Color3.fromRGB(110, 245, 118)
				else Color3.fromRGB(255, 224, 130)
			fxRemote:FireAllClients("Beam", muzzlePos, endPos, beamColor, 0.08)
		end
	end

	if ws.mag <= 0 and ws.reserve > 0 then
		SurvivalWeapons.HandleReload(player)
	end
end

function SurvivalWeapons.UsePocketMedkit(player: Player): boolean
	local st = statsByPlayer[player]
	local char = player.Character
	if not st or not char or st.medkits <= 0 or char:GetAttribute("Downed") == true then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.Health >= hum.MaxHealth then
		return false
	end
	st.medkits -= 1
	hum.Health = math.min(hum.MaxHealth, hum.Health + 65)
	SurvivalWeapons.SyncPlayerAttributes(player)
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if fxRemote and hrp then
		fxRemote:FireAllClients("Blast", hrp.Position, 6, Color3.fromRGB(47, 220, 105))
	end
	return true
end

function SurvivalWeapons.SetTurretsFolder(folder: Folder?)
	activeTurretsFolder = folder
end

function SurvivalWeapons.DeploySentryTurret(player: Player): boolean
	local st = statsByPlayer[player]
	local char = player.Character
	if not st or not char or st.turretsAvailable <= 0 or not activeTurretsFolder or char:GetAttribute("Downed") == true then
		return false
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end

	local assets = ServerStorage:FindFirstChild("IFSul_SurvivalAssets")
	local props = assets and assets:FindFirstChild("Props")
	local container = props and props:FindFirstChild("sentry_turret")
	local template = container and container:FindFirstChildOfClass("Model")
	if not template then
		return false
	end

	st.turretsAvailable -= 1
	SurvivalWeapons.SyncPlayerAttributes(player)

	local forward = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	if forward.Magnitude < 0.1 then
		forward = Vector3.zAxis
	else
		forward = forward.Unit
	end
	local placeOrigin = hrp.Position + forward * 5.0 + Vector3.new(0, 4, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { char, activeTurretsFolder }
	local groundHit = Workspace:Raycast(placeOrigin, Vector3.new(0, -14, 0), rayParams)
	local basePos = if groundHit then groundHit.Position + Vector3.new(0, 1.8, 0) else (hrp.Position + forward * 5.0)

	local turret = template:Clone()
	turret.Name = "SentryTurret_" .. player.Name
	for _, bp in ipairs(turret:GetDescendants()) do
		if bp:IsA("BasePart") then
			bp.Anchored = true
			bp.CanCollide = false
		end
	end
	turret:PivotTo(CFrame.lookAt(basePos, basePos + forward))
	turret.Parent = activeTurretsFolder

	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.85
	hl.OutlineColor = Color3.fromRGB(47, 158, 65)
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = turret

	local fireSnd = Instance.new("Sound")
	fireSnd.SoundId = "rbxasset://sounds/paintball.wav"
	fireSnd.PlaybackSpeed = 1.4
	fireSnd.Volume = 0.45
	local anyPart = turret:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		fireSnd.Parent = anyPart
	end

	-- Torreta dura 75s atirando automaticamente na horda
	local expiresAt = os.clock() + 75
	task.spawn(function()
		while turret.Parent and os.clock() < expiresAt do
			task.wait(0.32)
			local survivalRoot = Workspace:FindFirstChild("IFSul_Survival")
			local enemiesFolder = survivalRoot and survivalRoot:FindFirstChild("Enemies") :: Folder?
			if not enemiesFolder then
				break
			end
			local pivotPos = turret:GetPivot().Position
			local bestEnemy: Model? = nil
			local bestHum: Humanoid? = nil
			local bestPos: Vector3? = nil
			local bestDist = 78

			for _, enemy in ipairs(enemiesFolder:GetChildren()) do
				if enemy:IsA("Model") then
					local ehum = enemy:FindFirstChildOfClass("Humanoid")
					local erp = enemy:FindFirstChild("HumanoidRootPart") :: BasePart?
					if ehum and ehum.Health > 0 and erp then
						local d = (erp.Position - pivotPos).Magnitude
						if d < bestDist then
							bestDist = d
							bestEnemy = enemy
							bestHum = ehum
							bestPos = erp.Position
						end
					end
				end
			end

			if bestEnemy and bestHum and bestPos and statsByPlayer[player] then
				local lookFlat = Vector3.new(bestPos.X, pivotPos.Y, bestPos.Z)
				if (lookFlat - pivotPos).Magnitude > 0.2 then
					turret:PivotTo(CFrame.lookAt(pivotPos, lookFlat))
				end
				fireSnd:Play()
				local pst = statsByPlayer[player]
				local dmg = 16 * (1 + pst.turretBoost) * pst.damageMult
				applyDamageAndEffects(player, pst, bestEnemy, bestHum, dmg, bestPos, false)
				if fxRemote then
					fxRemote:FireAllClients("Beam", pivotPos + Vector3.new(0, 1.0, 0), bestPos, Color3.fromRGB(72, 238, 152), 0.08)
				end
			end
		end
		if turret.Parent then
			turret:Destroy()
		end
	end)

	return true
end

function SurvivalWeapons.ApplySkillCard(player: Player, cardId: string): boolean
	local st = statsByPlayer[player]
	local card = SurvivalCatalog.GetCard(cardId)
	if not st or not card then
		return false
	end

	st.cardCounts[card.id] = (st.cardCounts[card.id] or 0) + 1
	local k = card.statKey
	local d = card.statDelta

	if k == "DamageMult" then
		st.damageMult += d
	elseif k == "FireRateMult" then
		st.fireRateMult += d
	elseif k == "PierceCount" then
		st.pierceCount += math.round(d)
		st.damageMult += 0.20
	elseif k == "AcidBurn" then
		st.acidBurn += d
	elseif k == "SlowOnHit" then
		st.slowOnHit = math.min(0.60, st.slowOnHit + d)
	elseif k == "DeathExplosion" then
		st.deathExplosion += d
	elseif k == "TurretBoost" then
		st.turretBoost += d
		st.turretsAvailable += 1
	elseif k == "CritChance" then
		st.critChance = math.min(0.85, st.critChance + d)
	elseif k == "ChainLightning" then
		st.chainLightning += d
	elseif k == "MaxHealthBonus" then
		st.maxHealthBonus += d
	elseif k == "ReloadSpeedMult" then
		st.reloadSpeedMult += d
	elseif k == "LifeOnKill" then
		st.lifeOnKill += d
	elseif k == "MoveSpeedMult" then
		st.moveSpeedMult += d
	elseif k == "CreditMult" then
		st.creditMult += d
	elseif k == "AllRoundLegend" then
		st.damageMult += 0.25
		st.moveSpeedMult += 0.15
		st.maxHealthBonus += 40
		st.credits += 150
	end

	SurvivalWeapons.SyncPlayerAttributes(player)
	return true
end

Players.PlayerRemoving:Connect(function(p: Player)
	statsByPlayer[p] = nil
end)

-- Regeneração passiva da carta Plantão Saúde 112
task.spawn(function()
	while true do
		task.wait(1.0)
		for player, st in pairs(statsByPlayer) do
			local stacks = st.cardCounts["plantao_saude"] or 0
			if stacks > 0 and player.Character and player.Character:GetAttribute("Downed") ~= true then
				local hum = player.Character:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
					hum.Health = math.min(hum.MaxHealth, hum.Health + stacks * 3)
				end
			end
		end
	end
end)

return SurvivalWeapons
