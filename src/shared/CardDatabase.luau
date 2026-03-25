local DEFAULT_CARD_TEMPLATE = {
    Attack = 50,
    Health = 120,
    AttackIntervalSeconds = 5.0,
    Category = "Uncategorized",
    Rarity = "Common",
    ArtFitMode = "Fit",
    ArtAssetId = "",
    VideoAssetId = "",
    HoverVideoAssetId = "",
    AbilityId = "",
    AbilityCooldownSeconds = 10,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

-- Duplicate DEFAULT_CARD_TEMPLATE removed; definition is at top of file
local CardDatabase = {}

local cardData = {
    ["BeliodusX"] = {
        Name = "BeliodusX",
        Attack = 1200000000,
        Health = 10800000000,
        AttackIntervalSeconds = 5.0,
        Category = "Seven Deadly Sins",
        Rarity = "God",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://77873660521351",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
    },
    ["lightyagami"] = {
        Name = "Death Writer",
        Attack = 100000,
        Health = 400000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://94327015801389",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Uncommon custom card.",
    },
    ["johnathanjoestar"] = {
        Name = "Hamon Gentleman",
        Attack = 1100,
        Health = 4200,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Uncommon",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://84035880933924",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Uncommon custom card.",
    },
    ["armin"] = {
        Name = "Genius Scout",
        Attack = 1200,
        Health = 4400,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Uncommon",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://115526881157290",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Uncommon custom card.",
    },
    ["asta"] = {
        Name = "Manaless Wizard",
        Attack = 1300000,
        Health = 4600000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://112767549806462",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Uncommon custom card.",
    },
    ["bojji"] = {
        Name = "Mirai",
        Attack = 140,
        Health = 480,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Uncommon",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://118551319885422",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Uncommon custom card.",
    },
    ["denji"] = {
        Name = "Women Seeking Hunter",
        Attack = 20000,
        Health = 60000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://111215871489552",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Rare custom card.",
    },
    ["edwardelric"] = {
        Name = "Metal Alchemist",
        Attack = 210000,
        Health = 620000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://139542750963805",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Rare custom card.",
    },
    ["gon"] = {
        Name = "Rookie Hunter",
        Attack = 22000,
        Health = 64000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://119477439205269",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Rare custom card.",
    },
    ["kiba"] = {
        Name = "Dog Breeding Ninja",
        Attack = 23000,
        Health = 66000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://75583669154514",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Rare custom card.",
    },
    ["kidcoby"] = {
        Name = "Coward of Justice",
        Attack = 2400,
        Health = 6800,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Uncommon",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://74953934441998",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Rare custom card.",
    },
    ["killua"] = {
        Name = "Assassin Hunter",
        Attack = 250000,
        Health = 750000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://73858850936933",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Rare custom card.",
    },
    ["naruto"] = {
        Name = "Knucklehead Ninja",
        Attack = 27000,
        Health = 81000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://76654451871487",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Rare custom card.",
    },
    ["lisalisa"] = {
        Name = "Hamon Mentor",
        Attack = 29000,
        Health = 87000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://74695816890751",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Rare custom card.",
    },
    ["masterroshi"] = {
        Name = "Turtle Hermit",
        Attack = 31000,
        Health = 93000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://100086228347779",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Rare custom card.",
    },
    ["mob"] = {
        Name = "Restrained Esper",
        Attack = 3300,
        Health = 9900,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Uncommon",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://109730325430363",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Rare custom card.",
    },
    ["mrsatan"] = {
        Name = "Martial Arts Champion",
        Attack = 3500,
        Health = 10500,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Uncommon",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://133628416601785",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Rare custom card.",
    },
    ["natsu"] = {
        Name = "Fire Salamander",
        Attack = 100000,
        Health = 500000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://125732494372665",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["saibaman"] = {
        Name = "Explosive Plant ",
        Attack = 1200,
        Health = 6000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Uncommon",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://106682466467156",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["sakura"] = {
        Name = "Pink Ninja",
        Attack = 140000,
        Health = 700000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://84478360843205",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["blueslime"] = {
        Name = "Blue Slime",
        Attack = 1600,
        Health = 8000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Uncommon",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://128109245961112",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["sungjinwoo"] = {
        Name = "F Rank Hunter",
        Attack = 1800,
        Health = 9000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Uncommon",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://87343609974295",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["yugi"] = {
        Name = "King of Games",
        Attack = 200000,
        Health = 1000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://125072644833143",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["genya"] = {
        Name = "Demon Eating Swordsman",
        Attack = 22000,
        Health = 110000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://79714372400036",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["luffy"] = {
        Name = "Straw Hat",
        Attack = 24000,
        Health = 30000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://86790998588928",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["arima"] = {
        Name = "Aurarima",
        Attack = 26000000,
        Health = 130000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://124257683228455",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["supervegeta"] = {
        Name = "Super Vegan",
        Attack = 280000,
        Health = 1400000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://81103831884990",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["majinbuu"] = {
        Name = "King Bau",
        Attack = 300000,
        Health = 1500000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://76060963956133",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["cell"] = {
        Name = "Ultimate Mitosis",
        Attack = 320000,
        Health = 1600000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://93094320882806",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["ichigo"] = {
        Name = "Substitute Shinigami",
        Attack = 34000,
        Health = 50000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://120615459234079",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["KidNaruto"] = {
        Name = "Knucklehead Ninja (Kid)",
        Attack = 36000,
        Health = 68000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://98021691212672",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["kidgoku"] = {
        Name = "Earth's Defender (Kid)",
        Attack = 38000,
        Health = 80000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://72331545229425",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["emiyashirou"] = {
        Name = "Projection Mage",
        Attack = 40000000,
        Health = 200000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://79189848936927",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["onepunchman"] = {
        Name = "Bald Hero",
        Attack = 420000,
        Health = 2100000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://105179177507876",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Erwin"] = {
        Name = "Scout Commander",
        Attack = 440000,
        Health = 2200000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://123764198228582",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["25thbaam"] = {
        Name = "Irregular",
        Attack = 160000000,
        Health = 230000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://117036576029292",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["touma"] = {
        Name = "Twoma",
        Attack = 4800000,
        Health = 24000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://123401161010160",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["mikasa"] = {
        Name = "Mikosa",
        Attack = 50000,
        Health = 250000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://138354277926400",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["SolarisWitch"] = {
        Name = "Solaris Witch",
        Attack = 110000000,
        Health = 80000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://89844517591936",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["PsyKing"] = {
        Name = "Psy King",
        Attack = 150000000,
        Health = 200000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://127321903075119",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["TinTin"] = {
        Name = "TinTin",
        Attack = 5600,
        Health = 28000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Uncommon",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://129250568589572",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Hamcha"] = {
        Name = "Hamcha",
        Attack = 58000,
        Health = 290000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://89119667852200",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Chillin"] = {
        Name = "Chillin",
        Attack = 60000,
        Health = 300000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://108249090376433",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Bimibaru"] = {
        Name = "Bimibaru",
        Attack = 620000,
        Health = 3100000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://78405085193341",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Zaza"] = {
        Name = "Zaza",
        Attack = 640000,
        Health = 3200000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://70396265517152",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Kagara"] = {
        Name = "Kagara",
        Attack = 30000000,
        Health = 80000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://130749447452005",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Legendary custom card.",
    },
    ["Oshimoru"] = {
        Name = "Oshimoru",
        Attack = 45000000,
        Health = 56000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://132638306722484",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Legendary custom card.",
    },
    ["BeastNurudo"] = {
        Name = "Beast Nurudo",
        Attack = 660000,
        Health = 3300000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://104401685586690",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Bakashi"] = {
        Name = "Bakashi",
        Attack = 680000,
        Health = 3400000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://113390490720780",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Deji"] = {
        Name = "Deji",
        Attack = 70000,
        Health = 350000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://114174829826817",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Pocky"] = {
        Name = "Pocky",
        Attack = 72000,
        Health = 360000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://93123386103288",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Narutobi"] = {
        Name = "Narutobi",
        Attack = 7400000,
        Health = 37000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://71720529372306",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Shiniparu"] = {
        Name = "Shiniparu",
        Attack = 760000,
        Health = 3800000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://112990377291091",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Koro"] = {
        Name = "Koro",
        Attack = 78000,
        Health = 390000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://81669998482188",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["CursedZosuke"] = {
        Name = "Cursed Zosuke",
        Attack = 100000000,
        Health = 90000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://106883272275852",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Pippolo"] = {
        Name = "Pippolo",
        Attack = 82000,
        Health = 410000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://112268337007455",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Nakama"] = {
        Name = "Nakama",
        Attack = 84000,
        Health = 420000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://135464233858566",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Vegan"] = {
        Name = "Vegan",
        Attack = 86000,
        Health = 430000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://129721390377551",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Jinyu"] = {
        Name = "Jinyu",
        Attack = 88000,
        Health = 440000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://110114431747693",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Freezer"] = {
        Name = "Freezer",
        Attack = 90000000,
        Health = 455000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://132241129797306",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["SuperBoku"] = {
        Name = "Super Boku",
        Attack = 92000000,
        Health = 465000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://100058730390303",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["LarrenYoger"] = {
        Name = "Larren Yoger",
        Attack = 94000,
        Health = 470000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://124181131548110",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["BigGiant"] = {
        Name = "Big Giant",
        Attack = 9600000,
        Health = 4800000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://86629198295971",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["ArmoredGiant"] = {
        Name = "Armored Giant",
        Attack = 9800000,
        Health = 49000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://115234694388580",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["GorillaGiant"] = {
        Name = "Gorilla Giant",
        Attack = 10000000,
        Health = 50000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://115988826643837",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Revy"] = {
        Name = "Revy",
        Attack = 10200000,
        Health = 5100000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://93933871364780",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["rui"] = {
        Name = "Loui",
        Attack = 104000,
        Health = 520000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Rare",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://109019402944199",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["GirlGiant"] = {
        Name = "Girl Giant",
        Attack = 10800000,
        Health = 54000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://118313632487592",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["enmu"] = {
        Name = "Inma",
        Attack = 11000000,
        Health = 55000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://112104829546175",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Giyutu"] = {
        Name = "Giyutu",
        Attack = 11200000,
        Health = 56000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://80924145111655",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["mastereduigoku"] = {
        Name = "Omega Boku",
        Attack = 1140000000,
        Health = 5700000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "God",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://140539112286647",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["sinbad"] = {
        Name = "Zinba Lightning God",
        Attack = 1160000000,
        Health = 5800000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "God",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://96720792003088",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["Wantengo"] = {
        Name = "Wantengo",
        Attack = 11600000,
        Health = 58000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://98217450101948",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["daki"] = {
        Name = "Saki",
        Attack = 11600000,
        Health = 58000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://135120754795304",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["gyokko"] = {
        Name = "Kyoko",
        Attack = 11600000,
        Health = 58000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://115794821435062",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["mitsuri"] = {
        Name = "Catsuri",
        Attack = 118000000,
        Health = 590000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://82202474274633",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["inosuke"] = {
        Name = "Boar Bandit",
        Attack = 35000000,
        Health = 90000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://93321513087787",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Legendary custom card.",
    },
    ["nezuko"] = {
        Name = "Yesuko",
        Attack = 12200000,
        Health = 61000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Epic",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://101061610934105",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Epic custom card.",
    },
    ["tanjiro"] = {
        Name = "Banjoro",
        Attack = 55000000,
        Health = 140000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://114299715654896",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Legendary custom card.",
    },
    ["zenitsu"] = {
        Name = "Tenzetsu",
        Attack = 75000000,
        Health = 190000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://131041870279708",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Legendary custom card.",
    },
    ["shinobu"] = {
        Name = "Shinoko",
        Attack = 80000000,
        Health = 200000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://71661611456386",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Legendary custom card.",
    },
    ["muichiro"] = {
        Name = "Mochirow",
        Attack = 85000000,
        Health = 210000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://104738991259225",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Legendary custom card.",
    },
    ["rengoku"] = {
        Name = "Ringkou",
        Attack = 90000000,
        Health = 220000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://90496984463626",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Legendary custom card.",
    },
    ["tengen"] = {
        Name = "Ninegen",
        Attack = 95000000,
        Health = 230000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://80771976298860",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Legendary custom card.",
    },
    ["giyuu"] = {
        Name = "Kiyou",
        Attack = 100000000,
        Health = 240000000,
        AttackIntervalSeconds = 5.0,
        Category = "Custom",
        Rarity = "Legendary",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://117691618947027",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        Description = "Legendary custom card.",
    },
    ["asuna"] = {
        Name = "Arune",
        Attack = 12500,
        Health = 82500,
        AttackIntervalSeconds = 5.0,
        Category = "Sword Art Online",
        Rarity = "Rare",
        ArtFitMode = "Crop",
        ArtAssetId = "rbxassetid://86073937479874",
        AbilityId = "AttackSpeedBoost",
        AbilityCooldownSeconds = 12
    },
    ["misaamane"] = {
        Name = "Lisa Enmane",
        Attack = 98000,
        Health = 89000,
        AttackIntervalSeconds = 5.0,
        Category = "Demon Slayer",
        Rarity = "Rare",
        ArtFitMode = "Crop",
        ArtAssetId = "rbxassetid://139639316125366",
        AbilityId = "AttackDamageBoost",
        AbilityCooldownSeconds = 15
    },
    ["ElfMage"] = {
        Name = "Elf Mage",
        Attack = 98000,
        Health = 89000,
        AttackIntervalSeconds = 5.0,
        Category = "Magic World",
        Rarity = "Epic",
        ArtFitMode = "Crop",
        ArtAssetId = "rbxassetid://126141819707798",
        AbilityId = "AttackDamageBoost",
        AbilityCooldownSeconds = 15
    },
    ["power"] = {
        Name = "Boawer",
        Attack = 98000,
        Health = 89000,
        AttackIntervalSeconds = 5.0,
        Category = "Magic World",
        Rarity = "Epic",
        ArtFitMode = "Crop",
        ArtAssetId = "rbxassetid://139360187158907",
        AbilityId = "AttackDamageBoost",
        AbilityCooldownSeconds = 15
    },
    ["cc"] = {
        Name = "Kiki",
        Attack = 98000,
        Health = 89000,
        AttackIntervalSeconds = 5.0,
        Category = "Magic World",
        Rarity = "Epic",
        ArtFitMode = "Crop",
        ArtAssetId = "rbxassetid://108032115040659",
        AbilityId = "AttackDamageBoost",
        AbilityCooldownSeconds = 15
    },
    ["esdeath"] = {
        Name = "Esla",
        Attack = 98000000,
        Health = 890000000,
        AttackIntervalSeconds = 5.0,
        Category = "Magic World",
        Rarity = "Legendary",
        ArtFitMode = "Crop",
        ArtAssetId = "rbxassetid://90045181883052",
        AbilityId = "AttackDamageBoost",
        AbilityCooldownSeconds = 15
    },
    ["aqua"] = {
        Name = "Water Princess",
        Attack = 13200,
        Health = 86000,
        AttackIntervalSeconds = 5.0,
        Category = "Konosuba",
        Rarity = "Rare",
        ArtFitMode = "Crop",
        ArtAssetId = "rbxassetid://122803861262986",
        AbilityId = "HealAlly",
        AbilityCooldownSeconds = 9
    },
    ["PerfectCell"] = {
        Name = "Perfect Cell",
        Attack = 4000000,
        Health = 10000000,
        AttackIntervalSeconds = 4.0,
        Category = "NPC",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://124313099860742",
        AbilityId = "",
        AbilityCooldownSeconds = 10,
        IsNpcCard = true,
    },
    ["Aokoji"] = {
        Name = "Aokoji",
        Attack = 4000000,
        Health = 10000000,
        AttackIntervalSeconds = 8.0,
        Category = "NPC",
        ArtFitMode = "Fit",
        ArtAssetId = "rbxassetid://130664963456992",
        AbilityId = "IceAge",
        AbilityCooldownSeconds = 20,
        IsNpcCard = true
    }
}

local specialVideoCardData = {
    ["AstraEclipse"] = {
        Name = "Astra Eclipse",
        Attack = 1850000000,
        Health = 4200000000,
        AttackIntervalSeconds = 5.0,
        Category = "Celestial",
        Rarity = "Transcendent",
        ArtFitMode = "Fit",
        VideoAssetId = "rbxassetid://104020003412677",
        HoverVideoAssetId = "",
        IsSpecialVideoCard = true
    },
}

local cardDataReady = false

local COMBAT_POWER_RARITY_MULTIPLIER = {
    Common = 1,
    Uncommon = 1.5,
    Rare = 3,
    Epic = 8,
    Legendary = 25,
    God = 100,
    Transcendent = 500,
}

local function deriveDefaultHealth(attackValue)
    local atk = math.max(1, math.floor(tonumber(attackValue) or DEFAULT_CARD_TEMPLATE.Attack))
    return math.max(60, atk)
end

local function sanitizeHealth(value, attackValue)
    if type(value) == "number" then
        return math.max(1, math.floor(value))
    end
    return deriveDefaultHealth(attackValue)
end

local function sanitizeString(value, fallback)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return fallback
end

local function sanitizeAttack(value)
    if type(value) == "number" then
        return math.max(0, math.floor(value))
    end
    return DEFAULT_CARD_TEMPLATE.Attack
end

local function sanitizeAttackIntervalSeconds(_value, _rarityValue)
    -- Global balance rule: all cards use a 5.0s attack interval.
    return DEFAULT_CARD_TEMPLATE.AttackIntervalSeconds
end

local function sanitizeArtFitMode(value)
    if type(value) ~= "string" then
        return DEFAULT_CARD_TEMPLATE.ArtFitMode
    end

    local normalized = string.lower(value)
    if normalized == "stretch" then
        return "Stretch"
    end
    if normalized == "crop" then
        return "Crop"
    end
    return "Fit"
end

local function sanitizeVideoAssetId(value)
    if type(value) ~= "string" then
        return ""
    end
    if value == "" or value == "rbxassetid://0" then
        return ""
    end
    local digits = value:match("^%d+$")
    if digits then
        return "rbxassetid://" .. digits
    end
    return value
end

local function sanitizeImageAssetId(value)
    if type(value) ~= "string" then
        return ""
    end
    if value == "" or value == "rbxassetid://0" then
        return ""
    end
    local digits = value:match("^%d+$")
    if digits then
        return "rbxassetid://" .. digits
    end
    return value
end

local function sanitizeAbilityId(value)
    if type(value) ~= "string" then
        return DEFAULT_CARD_TEMPLATE.AbilityId
    end
    return value
end

local function sanitizeAbilityCooldownSeconds(value)
    local n = tonumber(value)
    if not n then
        return DEFAULT_CARD_TEMPLATE.AbilityCooldownSeconds
    end
    return math.max(1, math.floor(n + 0.5))
end

local function prettifyCardId(cardId)
    -- Converts ids like "Goku5Star" into "Goku 5 Star" for a readable default name.
    local pretty = cardId:gsub("(%l)(%u)", "%1 %2")
    pretty = pretty:gsub("(%d)(%a)", "%1 %2")
    return pretty
end

local function autoRegisterCardArtCards()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local cardArtFolder = ReplicatedStorage:FindFirstChild("CardArt")
    if not cardArtFolder then
        return
    end

    for _, art in ipairs(cardArtFolder:GetChildren()) do
        if art:IsA("Decal") then
            local cardId = art.Name
            local existing = cardData[cardId]
            -- Editable metadata can be set directly on each CardArt decal in Studio:
            -- DisplayName or Label (string), Attack (number), Category (string), Rarity (string)
            local displayNameAttr = art:GetAttribute("DisplayName")
            if displayNameAttr == nil then
                displayNameAttr = art:GetAttribute("Label")
            end
            local attackAttr = art:GetAttribute("Attack")
            local categoryAttr = art:GetAttribute("Category")
            local rarityAttr = art:GetAttribute("Rarity")
            local artFitModeAttr = art:GetAttribute("ArtFitMode")
            local forceStretchAttr = art:GetAttribute("ForceStretch")
            local squareArtAttr = art:GetAttribute("SquareArt")
            local videoAssetIdAttr = art:GetAttribute("VideoAssetId")

            local artFitMode = (existing and existing.ArtFitMode) or DEFAULT_CARD_TEMPLATE.ArtFitMode
            if type(artFitModeAttr) == "string" then
                artFitMode = sanitizeArtFitMode(artFitModeAttr)
            elseif forceStretchAttr == true or squareArtAttr == true then
                artFitMode = "Stretch"
            end

            if existing then
                -- Keep hardcoded/registered card identity authoritative.
                -- Only art fit behavior may be inferred from decal metadata.
                cardData[cardId] = {
                    Name = sanitizeString(existing.Name, prettifyCardId(cardId)),
                    Attack = sanitizeAttack(existing.Attack),
                    Health = sanitizeHealth(existing.Health, existing.Attack),
                    AttackIntervalSeconds = sanitizeAttackIntervalSeconds(existing.AttackIntervalSeconds, existing.Rarity),
                    Category = sanitizeString(existing.Category, DEFAULT_CARD_TEMPLATE.Category),
                    Rarity = sanitizeString(existing.Rarity, DEFAULT_CARD_TEMPLATE.Rarity),
                    ArtFitMode = artFitMode,
                    ArtAssetId = sanitizeImageAssetId(existing.ArtAssetId),
                    VideoAssetId = sanitizeVideoAssetId(existing.VideoAssetId),
                    HoverVideoAssetId = sanitizeVideoAssetId(existing.HoverVideoAssetId),
                    AbilityId = sanitizeAbilityId(existing.AbilityId),
                    AbilityCooldownSeconds = sanitizeAbilityCooldownSeconds(existing.AbilityCooldownSeconds),
                    IsSpecialVideoCard = existing.IsSpecialVideoCard == true
                }
            else
                -- New cards discovered from CardArt may use decal attributes as metadata.
                cardData[cardId] = {
                    Name = sanitizeString(displayNameAttr, prettifyCardId(cardId)),
                    Attack = (type(attackAttr) == "number") and sanitizeAttack(attackAttr) or DEFAULT_CARD_TEMPLATE.Attack,
                    Health = sanitizeHealth(art:GetAttribute("Health"), attackAttr),
                    AttackIntervalSeconds = sanitizeAttackIntervalSeconds(art:GetAttribute("AttackIntervalSeconds"), rarityAttr),
                    Category = sanitizeString(categoryAttr, DEFAULT_CARD_TEMPLATE.Category),
                    Rarity = sanitizeString(rarityAttr, DEFAULT_CARD_TEMPLATE.Rarity),
                    ArtFitMode = artFitMode,
                    ArtAssetId = "",
                    VideoAssetId = sanitizeVideoAssetId(videoAssetIdAttr),
                    HoverVideoAssetId = "",
                    AbilityId = DEFAULT_CARD_TEMPLATE.AbilityId,
                    AbilityCooldownSeconds = DEFAULT_CARD_TEMPLATE.AbilityCooldownSeconds,
                    IsSpecialVideoCard = false,
                }
            end
        end
    end
end

local function normalizeAllCardDataEntries()
    for cardId, data in pairs(cardData) do
        cardData[cardId] = {
            Name = sanitizeString(data.Name, prettifyCardId(cardId)),
            Attack = sanitizeAttack(data.Attack),
            Health = sanitizeHealth(data.Health, data.Attack),
            AttackIntervalSeconds = sanitizeAttackIntervalSeconds(data.AttackIntervalSeconds, data.Rarity),
            Category = sanitizeString(data.Category, DEFAULT_CARD_TEMPLATE.Category),
            Rarity = sanitizeString(data.Rarity, DEFAULT_CARD_TEMPLATE.Rarity),
            ArtFitMode = sanitizeArtFitMode(data.ArtFitMode),
            ArtAssetId = sanitizeImageAssetId(data.ArtAssetId),
            VideoAssetId = sanitizeVideoAssetId(data.VideoAssetId),
            HoverVideoAssetId = sanitizeVideoAssetId(data.HoverVideoAssetId),
            AbilityId = sanitizeAbilityId(data.AbilityId),
            AbilityCooldownSeconds = sanitizeAbilityCooldownSeconds(data.AbilityCooldownSeconds),
            IsSpecialVideoCard = data.IsSpecialVideoCard == true,
        }
    end
end

local function registerSpecialVideoCards()
    for cardId, data in pairs(specialVideoCardData) do
        cardData[cardId] = {
            Name = sanitizeString(data.Name, prettifyCardId(cardId)),
            Attack = sanitizeAttack(data.Attack),
            Health = sanitizeHealth(data.Health, data.Attack),
            AttackIntervalSeconds = sanitizeAttackIntervalSeconds(data.AttackIntervalSeconds, data.Rarity),
            Category = sanitizeString(data.Category, DEFAULT_CARD_TEMPLATE.Category),
            Rarity = sanitizeString(data.Rarity, "Transcendent"),
            ArtFitMode = sanitizeArtFitMode(data.ArtFitMode),
            ArtAssetId = sanitizeImageAssetId(data.ArtAssetId),
            VideoAssetId = sanitizeVideoAssetId(data.VideoAssetId),
            HoverVideoAssetId = sanitizeVideoAssetId(data.HoverVideoAssetId),
            AbilityId = sanitizeAbilityId(data.AbilityId),
            AbilityCooldownSeconds = sanitizeAbilityCooldownSeconds(data.AbilityCooldownSeconds),
            IsSpecialVideoCard = true
        }
    end
end

local function ensureCardDataReady()
    if cardDataReady then
        return
    end
    normalizeAllCardDataEntries()
    registerSpecialVideoCards()
    autoRegisterCardArtCards()
    cardDataReady = true
end

local FOIL_CARD_SUFFIX = "::Foil"       -- Canonical foil/border variant format
local BORDERED_CARD_SUFFIX = "::Bordered"  -- Legacy alias; parsed then normalized to ::Foil

-- Explicit tier keys that may appear after ::Bordered in a card reference.
-- Why: encoding the tier in the ref (e.g. "BeliodusX::Bordered::Gold") keeps card
-- rarity (Common…God) and border-tier rarity (Silver…Rainbow) fully independent —
-- no coupling to a player's FoilChance stat is needed to identify the visual tier.
local VALID_FOIL_TIERS = {
        Silver = true, Gold = true, Diamond = true, Rainbow = true,
        Corrupted = true,  -- Gallery-only concept tier
}

local function resolveCardId(cardRef)
    if type(cardRef) ~= "string" or cardRef == "" then
        return nil
    end

    -- Strip any ::Bordered or ::Foil (legacy) suffix including optional ::Tier so all
    -- ref formats resolve to the same base card:
    --   "BeliodusX", "BeliodusX::Bordered", "BeliodusX::Bordered::Gold", "BeliodusX::Foil::Silver"
    cardRef = string.gsub(cardRef, BORDERED_CARD_SUFFIX .. ".*$", "")
    cardRef = string.gsub(cardRef, FOIL_CARD_SUFFIX .. ".*$", "")
    cardRef = string.gsub(cardRef, "^%s*(.-)%s*$", "%1")
    if cardRef == "" then
        return nil
    end

    if cardData[cardRef] then
        return cardRef
    end

    local target = string.lower(cardRef)

    -- Pass 1: resolve by id only (case-insensitive), no name fallback yet.
    for id in pairs(cardData) do
        if string.lower(id) == target then
            return id
        end
    end

    -- Pass 2: resolve by display name only after id checks are exhausted.
    for id, data in pairs(cardData) do
        if type(data.Name) == "string" and string.lower(data.Name) == target then
            return id
        end
    end

    return nil
end

local function resolveCardIdStrict(cardRef)
    if type(cardRef) ~= "string" or cardRef == "" then
        return nil
    end

    cardRef = string.gsub(cardRef, BORDERED_CARD_SUFFIX .. ".*$", "")
    cardRef = string.gsub(cardRef, FOIL_CARD_SUFFIX .. ".*$", "")
    cardRef = string.gsub(cardRef, "^%s*(.-)%s*$", "%1")
    if cardRef == "" then
        return nil
    end

    if cardData[cardRef] then
        return cardRef
    end

    local target = string.lower(cardRef)
    for id in pairs(cardData) do
        if string.lower(id) == target then
            return id
        end
    end

    return nil
end

local function formatCompactNumber(value)
    local num = tonumber(value)
    if not num then
        return tostring(value)
    end

    local absNum = math.abs(num)
    local suffix = ""
    local divisor = 1

    if absNum >= 1e12 then
        suffix = "T"
        divisor = 1e12
    elseif absNum >= 1e9 then
        suffix = "B"
        divisor = 1e9
    elseif absNum >= 1e6 then
        suffix = "M"
        divisor = 1e6
    elseif absNum >= 1e3 then
        suffix = "K"
        divisor = 1e3
    end

    if suffix == "" then
        return tostring(math.floor(num + 0.5))
    end

    local compact = num / divisor
    local roundedToTenth = math.floor((compact * 10) + 0.5) / 10
    if math.abs(roundedToTenth - math.floor(roundedToTenth)) < 0.001 then
        return string.format("%d%s", math.floor(roundedToTenth), suffix)
    end
    return string.format("%.1f%s", roundedToTenth, suffix)
end

function CardDatabase.ParseCardReference(cardRef)
    ensureCardDataReady()
    if type(cardRef) ~= "string" or cardRef == "" then
        return nil
    end

    local trimmedRef = string.gsub(cardRef, "^%s*(.-)%s*$", "%1")
    if trimmedRef == "" then
        return nil
    end

    -- ── Canonical tier-encoded foil: "CardId::Foil::Tier" ─────────────────────
    local foilBaseRef, foilRawTier = string.match(trimmedRef, "^(.+)" .. FOIL_CARD_SUFFIX .. "::([%w]+)$")
    if foilBaseRef and foilRawTier then
        local resolvedTier = nil
        for tier in pairs(VALID_FOIL_TIERS) do
            if string.lower(tier) == string.lower(foilRawTier) then
                resolvedTier = tier
                break
            end
        end
        if resolvedTier then
            local resolvedId = resolveCardIdStrict(foilBaseRef)
            if resolvedId then
                return {
                    CardId     = resolvedId,
                    BaseCardId = resolvedId,
                    CardRef    = resolvedId .. FOIL_CARD_SUFFIX .. "::" .. resolvedTier,
                    IsBordered = true,
                    BorderTier = resolvedTier,
                }
            end
        end
    end

    -- ── Canonical plain foil: "CardId::Foil" ──────────────────────────────────
    local isPlainFoil = string.match(trimmedRef, FOIL_CARD_SUFFIX .. "$") ~= nil
    if isPlainFoil then
        local plainBase = string.gsub(trimmedRef, FOIL_CARD_SUFFIX .. "$", "")
        local resolvedId = resolveCardIdStrict(plainBase)
        if resolvedId then
            return {
                CardId     = resolvedId,
                BaseCardId = resolvedId,
                CardRef    = resolvedId .. FOIL_CARD_SUFFIX,
                IsBordered = true,
                BorderTier = nil,
            }
        end
    end

    -- ── Legacy tier-encoded bordered: "CardId::Bordered::Tier" ─────────────────
    -- Why: this format keeps card rarity (Common/…/God) and border-tier rarity
    -- (Silver/Gold/Diamond/Rainbow) fully independent.  No player stat is needed
    -- to know which foil palette to render.
    local baseRef, rawTier = string.match(trimmedRef, "^(.+)" .. BORDERED_CARD_SUFFIX .. "::([%w]+)$")
    if baseRef and rawTier then
        -- Normalise tier key casing so "gold" → "Gold" etc. Normalize to ::Foil::.
        local resolvedTier = nil
        for tier in pairs(VALID_FOIL_TIERS) do
            if string.lower(tier) == string.lower(rawTier) then
                resolvedTier = tier
                break
            end
        end

        if resolvedTier then
            local resolvedId = resolveCardIdStrict(baseRef)
            if resolvedId then
                return {
                    CardId     = resolvedId,
                    BaseCardId = resolvedId,
                    CardRef    = resolvedId .. BORDERED_CARD_SUFFIX .. "::" .. resolvedTier,
                    IsBordered = true,
                    BorderTier = resolvedTier,
                }
            end
        end
        -- Unknown tier suffix — fall through to plain-bordered check below.
    end

    -- ── Plain bordered: "CardId::Bordered" ───────────────────────────────────
    -- Why: backward-compatible with existing rolled bordered cards that were
    -- stored before the tier-encoding system was introduced.  Their display tier
    -- is resolved at render-time from the player's FoilChance stat.
    local isBordered = string.match(trimmedRef, BORDERED_CARD_SUFFIX .. "$") ~= nil
    local plainBase  = isBordered and string.gsub(trimmedRef, BORDERED_CARD_SUFFIX .. "$", "") or trimmedRef
    local resolvedId = resolveCardIdStrict(plainBase)
    if not resolvedId then
        return nil
    end

    return {
        CardId     = resolvedId,
        BaseCardId = resolvedId,
        CardRef    = isBordered and (resolvedId .. FOIL_CARD_SUFFIX) or resolvedId,
        IsBordered = isBordered,
        BorderTier = nil,  -- tier is stat-driven; determined at render-time
    }
end

function CardDatabase.NormalizeCardReference(cardRef)
    local parsed = CardDatabase.ParseCardReference(cardRef)
    return parsed and parsed.CardRef or nil
end

function CardDatabase.GetCardReference(cardId, isBordered)
    ensureCardDataReady()
    local resolvedId = resolveCardIdStrict(cardId)
    if not resolvedId then
        return nil
    end
    return isBordered and (resolvedId .. BORDERED_CARD_SUFFIX) or resolvedId
end

function CardDatabase.GetCardData(cardRef)
    ensureCardDataReady()
    local parsed = CardDatabase.ParseCardReference(cardRef)
    local resolvedId = parsed and parsed.BaseCardId or resolveCardIdStrict(cardRef)
    if not resolvedId then
        return nil
    end
    local data = cardData[resolvedId]
    if not data then
        return nil
    end
    return data
end

function CardDatabase.IsBorderedCard(cardRef)
    local parsed = CardDatabase.ParseCardReference(cardRef)
    return parsed ~= nil and parsed.IsBordered == true
end

function CardDatabase.FormatAttack(value)
    return formatCompactNumber(value)
end

function CardDatabase.GetFoilStatMultipliers(cardRef, foilChancePoints)
    local parsed = CardDatabase.ParseCardReference(cardRef)
    if not (parsed and parsed.IsBordered) then
        return { AtkMultiplier = 1, HpMultiplier = 1, Tier = nil }
    end

    -- Why: if the card ref encodes an explicit tier (e.g. ::Foil::Gold), use
    -- that directly.  Fallback to the stat-driven resolver for legacy refs.
    if parsed.BorderTier then
        local tierName    = parsed.BorderTier
        local multipliers = BalanceConfig.FOIL_TIER_MULTIPLIERS[tierName]
            or BalanceConfig.FOIL_TIER_MULTIPLIERS[BalanceConfig.DEFAULT_FOIL_TIER]
            or { AtkMultiplier = 1, HpMultiplier = 1 }
        return {
            AtkMultiplier = math.max(1, tonumber(multipliers.AtkMultiplier) or 1),
            HpMultiplier  = math.max(1, tonumber(multipliers.HpMultiplier)  or 1),
            Tier          = tierName,
        }
    end

    return BalanceConfig.GetFoilMultipliers(foilChancePoints)
end

function CardDatabase.GetCombatPower(cardId, foilChancePoints)
    ensureCardDataReady()
    local parsed = CardDatabase.ParseCardReference(cardId)
    local resolvedId = parsed and parsed.BaseCardId or resolveCardId(cardId)
    local data = resolvedId and cardData[resolvedId] or nil
    if not data then
        return 0
    end
    local multipliers = CardDatabase.GetFoilStatMultipliers(cardId, foilChancePoints)
    local atk = math.max(1, math.floor((tonumber(data.Attack) or 1) * (tonumber(multipliers.AtkMultiplier) or 1)))
    local hp = math.max(1, math.floor((tonumber(data.Health) or 1) * (tonumber(multipliers.HpMultiplier) or 1)))
    local rarity = data.Rarity or "Common"
    local multiplier = COMBAT_POWER_RARITY_MULTIPLIER[rarity] or 1
    return math.floor((atk + hp * 0.3) * multiplier)
end

function CardDatabase.FormatCombatPower(cardId, foilChancePoints)
    return formatCompactNumber(CardDatabase.GetCombatPower(cardId, foilChancePoints))
end
-- Function to get all available card IDs (unordered)
function CardDatabase.GetAllCardIds()
    ensureCardDataReady()
    local ids = {}
    for id in pairs(cardData) do
        table.insert(ids, id)
    end
    return ids
end

-- Function to get all available card IDs, sorted by rarity then name
function CardDatabase.GetAllCardIdsSorted()
    ensureCardDataReady()
    local ids = {}
    for id in pairs(cardData) do
        table.insert(ids, id)
    end
    table.sort(ids, function(a, b)
        local dataA = cardData[a]
        local dataB = cardData[b]
        local rarityOrder = {
            Common = 1,
            Uncommon = 2,
            Rare = 3,
            Epic = 4,
            Legendary = 5,
            God = 6,
            Transcendent = 7
        }
        local rA = rarityOrder[(dataA and dataA.Rarity) or "Common"] or 0
        local rB = rarityOrder[(dataB and dataB.Rarity) or "Common"] or 0
        if rA ~= rB then
            return rA < rB
        end
        local nA = (dataA and dataA.Name) or a
        local nB = (dataB and dataB.Name) or b
        return nA < nB
    end)
    return ids
end

-- Function to validate if a card has all required assets
function CardDatabase.ValidateCard(cardId)
    ensureCardDataReady()
    local data = cardData[cardId]
    if not data then
        return false, "Card not found in database"
    end
    
    -- Check if required fields exist
    if not data.Name or not data.Attack or not data.Category then
        return false, "Missing required card data fields"
    end
    
    -- In a real implementation, you could check for assets here
    -- For now, just validate data structure
    return true, "Valid"
end

-- Function to get cards by category
function CardDatabase.GetCardsByCategory(category)
    ensureCardDataReady()
    local cards = {}
    for id, data in pairs(cardData) do
        if data.Category == category then
            table.insert(cards, id)
        end
    end
    return cards
end

-- Function to get cards by rarity
function CardDatabase.GetCardsByRarity(rarity)
    ensureCardDataReady()
    local cards = {}
    for id, data in pairs(cardData) do
        local cardRarity = data.Rarity or "Common"
        if cardRarity == rarity then
            table.insert(cards, id)
        end
    end
    return cards
end

-- Function to get all unique categories
function CardDatabase.GetAllCategories()
    ensureCardDataReady()
    local categories = {}
    local seen = {}
    for _, data in pairs(cardData) do
        if data.Category and not seen[data.Category] then
            seen[data.Category] = true
            table.insert(categories, data.Category)
        end
    end
    return categories
end

-- Optional helper to explicitly override or add cards from scripts.
function CardDatabase.RegisterCard(cardId, data)
    if type(cardId) ~= "string" or type(data) ~= "table" then
        return false, "Invalid args"
    end
    if not data.Name or not data.Attack or not data.Category then
        return false, "Missing required fields: Name, Attack, Category"
    end

    cardData[cardId] = {
        Name = data.Name,
        Attack = data.Attack,
        Health = sanitizeHealth(data.Health, data.Attack),
        AttackIntervalSeconds = sanitizeAttackIntervalSeconds(data.AttackIntervalSeconds, data.Rarity),
        Category = data.Category,
        Rarity = data.Rarity or "Common",
        ArtFitMode = sanitizeArtFitMode(data.ArtFitMode),
        ArtAssetId = sanitizeImageAssetId(data.ArtAssetId),
        VideoAssetId = sanitizeVideoAssetId(data.VideoAssetId),
        HoverVideoAssetId = sanitizeVideoAssetId(data.HoverVideoAssetId),
        AbilityId = sanitizeAbilityId(data.AbilityId),
        AbilityCooldownSeconds = sanitizeAbilityCooldownSeconds(data.AbilityCooldownSeconds),
        IsSpecialVideoCard = data.IsSpecialVideoCard == true,
    }
    cardDataReady = true
    return true, "Registered"
end

return CardDatabase

