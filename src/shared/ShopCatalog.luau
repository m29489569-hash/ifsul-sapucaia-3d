--!strict
-- Catálogo oficial da Loja do IFSul — Câmpus Sapucaia do Sul
-- 12 armas e itens pré-prontos da Creator Store (de 100 até 10.000 moedas, ou 1 até 50 Robux).
-- Para ativar a cobrança real em Robux, crie os Produtos do Desenvolvedor no Creator Dashboard
-- (Monetização -> Produtos do Desenvolvedor) e preencha o campo `devProductId` de cada item.

export type ShopItem = {
	id: string,
	name: string,
	category: "Armas" | "Mobilidade" | "Especiais",
	rarity: "Comum" | "Incomum" | "Raro" | "Épico" | "Lendário",
	description: string,
	coinPrice: number,
	robuxPrice: number,
	devProductId: number,
	icon: string,
	accentColor: Color3,
}

local RARITY_COLORS = {
	Comum = Color3.fromRGB(92, 184, 92),
	Incomum = Color3.fromRGB(56, 152, 236),
	Raro = Color3.fromRGB(168, 85, 247),
	["Épico"] = Color3.fromRGB(236, 72, 153),
	["Lendário"] = Color3.fromRGB(250, 204, 21),
}

local ShopCatalog = {}

ShopCatalog.Items = {
	{
		id = "lanterna_tatica",
		name = "Lanterna Tática",
		category = "Especiais",
		rarity = "Comum",
		description = "Ilumina corredores e salas escuras no modo noite.",
		coinPrice = 100,
		robuxPrice = 1,
		devProductId = 0,
		icon = "",
		accentColor = RARITY_COLORS.Comum,
	},
	{
		id = "bloxy_cola",
		name = "Bloxy Cola Clássica",
		category = "Especiais",
		rarity = "Comum",
		description = "O clássico refrigerante do Roblox para recarregar as energias.",
		coinPrice = 200,
		robuxPrice = 3,
		devProductId = 0,
		icon = "rbxassetid://10472127",
		accentColor = RARITY_COLORS.Comum,
	},
	{
		id = "espada_classica",
		name = "Espada Clássica",
		category = "Armas",
		rarity = "Comum",
		description = "A lendária Linked Sword animada com som clássico.",
		coinPrice = 350,
		robuxPrice = 5,
		devProductId = 0,
		icon = "rbxassetid://18801092898",
		accentColor = RARITY_COLORS.Comum,
	},
	{
		id = "mola_gravidade",
		name = "Mola de Gravidade",
		category = "Mobilidade",
		rarity = "Incomum",
		description = "Salte muito mais alto pelos pátios e telhados do câmpus.",
		coinPrice = 650,
		robuxPrice = 8,
		devProductId = 0,
		icon = "rbxassetid://16619617",
		accentColor = RARITY_COLORS.Incomum,
	},
	{
		id = "mola_fogo",
		name = "Mola de Fogo",
		category = "Mobilidade",
		rarity = "Incomum",
		description = "Mola flamejante com efeito visual e impulso turbinado.",
		coinPrice = 1000,
		robuxPrice = 12,
		devProductId = 0,
		icon = "rbxassetid://17813680",
		accentColor = RARITY_COLORS.Incomum,
	},
	{
		id = "espada_lava",
		name = "Espada de Lava",
		category = "Armas",
		rarity = "Raro",
		description = "Lâmina incandescente forjada para duelos no câmpus.",
		coinPrice = 1500,
		robuxPrice = 15,
		devProductId = 0,
		icon = "rbxasset://Textures/Sword128.png",
		accentColor = RARITY_COLORS.Raro,
	},
	{
		id = "pistola_laser",
		name = "Pistola Laser Sci-Fi",
		category = "Armas",
		rarity = "Raro",
		description = "Blaster futurista com disparos rápidos de energia.",
		coinPrice = 2200,
		robuxPrice = 20,
		devProductId = 0,
		icon = "rbxassetid://130093050",
		accentColor = RARITY_COLORS.Raro,
	},
	{
		id = "pistola_laser_dupla",
		name = "Laser Duplo Hyper",
		category = "Armas",
		rarity = "Raro",
		description = "Duas pistolas laser simultâneas com cadência dobrada.",
		coinPrice = 3200,
		robuxPrice = 25,
		devProductId = 0,
		icon = "rbxassetid://209727372",
		accentColor = RARITY_COLORS.Raro,
	},
	{
		id = "super_mola",
		name = "Super Mola 3 em 1",
		category = "Mobilidade",
		rarity = "Épico",
		description = "Velocidade, gravidade reduzida e regeneração juntas.",
		coinPrice = 4500,
		robuxPrice = 30,
		devProductId = 0,
		icon = "rbxassetid://16619617",
		accentColor = RARITY_COLORS["Épico"],
	},
	{
		id = "lanca_foguetes",
		name = "Lança-Foguetes Clássico",
		category = "Armas",
		rarity = "Épico",
		description = "Dispara foguetes explosivos pelo câmpus inteiro.",
		coinPrice = 6200,
		robuxPrice = 35,
		devProductId = 0,
		icon = "rbxassetid://90021376",
		accentColor = RARITY_COLORS["Épico"],
	},
	{
		id = "tapete_magico",
		name = "Tapete Mágico Arco-Íris",
		category = "Especiais",
		rarity = "Épico",
		description = "Voe livremente sobre todos os blocos do IFSul.",
		coinPrice = 8000,
		robuxPrice = 42,
		devProductId = 0,
		icon = "rbxassetid://223080070",
		accentColor = RARITY_COLORS["Épico"],
	},
	{
		id = "hyperlaser_supremo",
		name = "Hyperlaser Supremo",
		category = "Armas",
		rarity = "Lendário",
		description = "A arma mais poderosa da loja: disparo contínuo de hyperlaser.",
		coinPrice = 10000,
		robuxPrice = 50,
		devProductId = 0,
		icon = "rbxassetid://130093050",
		accentColor = RARITY_COLORS["Lendário"],
	},
} :: { ShopItem }

local byId: { [string]: ShopItem } = {}
local byProductId: { [number]: ShopItem } = {}

for _, item in ipairs(ShopCatalog.Items) do
	byId[item.id] = item
	if item.devProductId > 0 then
		byProductId[item.devProductId] = item
	end
end

function ShopCatalog.GetById(id: string): ShopItem?
	return byId[id]
end

function ShopCatalog.GetByProductId(productId: number): ShopItem?
	return byProductId[productId]
end

return ShopCatalog
