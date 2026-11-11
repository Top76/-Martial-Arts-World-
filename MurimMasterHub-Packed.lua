-- Murim Master Hub v2: startup diagnostics for Delta.
-- Entire implementation is embedded locally; no network download or external loadstring URL.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then warn("Murim Hub: LocalPlayer unavailable"); return end
local pg = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 10)
if not pg then warn("Murim Hub: PlayerGui unavailable"); return end
local old = pg:FindFirstChild("MurimHubStartup")
if old then old:Destroy() end
local notice = Instance.new("ScreenGui")
notice.Name = "MurimHubStartup"
notice.ResetOnSpawn = false
notice.DisplayOrder = 2147483647
notice.Parent = pg
local box = Instance.new("TextLabel")
box.Position = UDim2.new(0.5, -160, 0, 12)
box.Size = UDim2.fromOffset(320, 100)
box.BackgroundColor3 = Color3.fromRGB(28, 35, 49)
box.TextColor3 = Color3.new(1, 1, 1)
box.Font = Enum.Font.SourceSansBold
box.TextSize = 15
box.TextWrapped = true
box.Text = "Murim Hub v2 • กำลังเปิด..."
box.Parent = notice
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)
local dismiss = Instance.new("TextButton")
dismiss.Size = UDim2.fromOffset(26, 26)
dismiss.Position = UDim2.new(1, -28, 0, 2)
dismiss.Text = "×"
dismiss.BackgroundColor3 = Color3.fromRGB(110, 45, 55)
dismiss.TextColor3 = Color3.new(1, 1, 1)
dismiss.Parent = box
dismiss.Activated:Connect(function() notice:Destroy() end)
local function report(message, failed)
    if box.Parent then
        box.Text = "Murim Hub v2\n" .. tostring(message)
        box.BackgroundColor3 = failed and Color3.fromRGB(115, 40, 45) or Color3.fromRGB(28, 35, 49)
    end
    if failed then warn("[Murim Hub] " .. tostring(message)) end
end
local function finishNotice()
    if notice.Parent then notice:Destroy() end
end

local source = [====[
local report, finishNotice = ...
-- Murim Master Hub: supplied farm GUI + Alchemy / Forge / Cultivation.
-- Run the entire file once. Minus hides the menu; Destroy removes all systems.
-- No automatic reset, purchase, or breakthrough-start actions are added.
if type(_G.ArtificeGuiCleanup) == "function" then
    pcall(_G.ArtificeGuiCleanup)
end
-- ============================================================================
-- 🎃 HALLOWEEN RAID CONSTANTS & HELPERS (FILE-LEVEL SCOPE TO AVOID 200 REGISTER LIMIT)
-- ============================================================================
local HALLOW_GATE_CFRAME = CFrame.new(17958, 2, 2058)

local HALLOW_FOE_KEYWORDS = {
    "jiangshi", "driver", "effigy", "paper tailor", "hg_tailor", "hungry", "lure", "cerberus", "matriarch", "hg_", "raidmob", "ghost", "corpse", "zombie", "ghoul", "specter", "shadow", "paper", "hallow"
}
local HALLOW_IGNORE_KEYWORDS = {
    "watchman", "sedan", "faceless", "gu heng", "tailor gu heng", "an rou", "tailor an rou", "under", "guest", "ledger", "outfit", "cloth"
}

local HALLOW_ROOM_DATA = {
    { name = "A01_Causeway", title = "Causeway of Unlit Lanterns", hz = "滅燈堤" },
    { name = "A02_CoffinLodge", title = "The Coffin Lodge", hz = "義莊" },
    { name = "A03_EffigyShop", title = "The Paper Effigy Shop", hz = "紙紮鋪" },
    { name = "A04_WatchmanStreet", title = "Watchman's Street", hz = "更夫街" },
    { name = "A05_Teahouse", title = "The Last Teahouse", hz = "末茶樓" },
    { name = "A06_Kennel", title = "Kennel of the Yin Gate", hz = "陰門獒院" },
    { name = "A07_Throat", title = "The Throat", hz = "咽井" },
    { name = "A08_Banquet", title = "Banquet of the Hungry", hz = "餓鬼宴" },
    { name = "A09_EmptyBelly", title = "The Empty Belly", hz = "空腹" },
    { name = "A10_MoonReturns", title = "The Moon Returns", hz = "月歸" },
}

local isAutoHallowRaid = false
local hallowDifficulty = "Normal"
local isHallowAutoRepeat = false
local isHallowPacifySeen = true
local lastSeenPacifyTime = 0
local currentRaidRoomIndex = 1
local roomEnterTime = 0
local lastRaidActionTime = 0
local room3Phase = 1 -- 1 = kill effigies, 2 = kill Boss Paper Tailor
local bossTailorFought = false
local immortalEffigies = {} -- blacklist of effigies confirmed immortal (HP never drops)
local effigyHpSnapshot = {} -- { [npc] = { hp = number, t = clock } } for tracking
local openedCoffins = {}
local toggleHallowRaidBtn = nil
local hallowStatusLabel = nil

local function findGuestLedger()
    local ws = game:GetService("Workspace")
    for _, desc in ipairs(ws:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled then
            local act = (desc.ActionText or ""):lower()
            local obj = (desc.ObjectText or ""):lower()
            if obj:find("ledger") or act:find("ledger") or obj:find("guest") or act:find("guest") then
                local pPart = desc.Parent:IsA("BasePart") and desc.Parent or (desc.Parent and desc.Parent:FindFirstChildWhichIsA("BasePart", true))
                if pPart then
                    return desc, pPart
                end
            end
        end
    end
    for _, desc in ipairs(ws:GetDescendants()) do
        local n = desc.Name:lower()
        if n:find("guest") and n:find("ledger") then
            local p = desc:IsA("BasePart") and desc or (desc:IsA("Model") and (desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart", true)))
            if p then
                local prompt = desc:FindFirstChildWhichIsA("ProximityPrompt", true)
                return prompt, p
            end
        end
    end
    return nil, nil
end

local function getActiveRaidModel()
    local ws = game:GetService("Workspace")
    local raidsFolder = ws:FindFirstChild("Raids")
    if raidsFolder then
        local hg1 = raidsFolder:FindFirstChild("HallowGate_1")
        if hg1 then return hg1 end
        for _, child in ipairs(raidsFolder:GetChildren()) do
            if child.Name:find("HallowGate") then
                return child
            end
        end
    end
    return nil
end

local function checkIsInsideRaid(ply)
    if not ply then return false end
    local pg = ply:FindFirstChild("PlayerGui")
    if pg and pg:FindFirstChild("MurimHallowHUD") then
        return true
    end
    local ws = game:GetService("Workspace")
    local raids = ws:FindFirstChild("Raids")
    local hrp = ply.Character and ply.Character:FindFirstChild("HumanoidRootPart")
    if raids and hrp then
        local hg = raids:FindFirstChild("HallowGate_1") or raids:FindFirstChildWhichIsA("Model")
        if hg then
            local pv = hg:GetPivot().Position
            if (hrp.Position - pv).Magnitude < 4000 then
                return true
            end
        end
    end
    if hrp and math.abs(hrp.Position.X - 40000) < 4000 then
        return true
    end
    return false
end

local function getRoomTargetPosition(roomIndex, activeRaidModel)
    local data = HALLOW_ROOM_DATA[roomIndex]
    if not data then return nil end

    if activeRaidModel then
        local roomModel = activeRaidModel:FindFirstChild(data.name)
        if roomModel then
            local markers = roomModel:FindFirstChild("Markers")
            if markers then
                local entry = markers:FindFirstChild("HallowEntry")
                if entry and entry:IsA("BasePart") then
                    return entry.Position + Vector3.new(0, 3, 0)
                elseif entry and entry:IsA("Attachment") then
                    return entry.WorldPosition + Vector3.new(0, 3, 0)
                end
                local shrine = markers:FindFirstChild("HallowShrine")
                if shrine and shrine:IsA("BasePart") then
                    return shrine.Position + Vector3.new(0, 3, 0)
                end
            end
            local zone = roomModel:FindFirstChild("HallowZone")
            if zone and zone:IsA("BasePart") then
                return Vector3.new(zone.Position.X, zone.Position.Y - zone.Size.Y / 2 + 3.5, zone.Position.Z)
            end
            if roomModel:IsA("Model") then
                local cf, sz = roomModel:GetBoundingBox()
                if sz.Magnitude > 0 then
                    return Vector3.new(cf.Position.X, cf.Position.Y - math.min(sz.Y / 2, 20) + 3.5, cf.Position.Z)
                end
            end
        end
    end
    return nil
end

local function isHallowFoe(npc)
    if not npc or not npc:IsA("Model") or not npc.Parent then return false end
    local Players = game:GetService("Players")
    if Players:GetPlayerFromCharacter(npc) then return false end
    local hum = npc:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end

    local prompt = npc:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and prompt.Enabled then
        local act = (prompt.ActionText or ""):lower()
        if act:find("talk") or act:find("shop") or act:find("buy") or act:find("cloth") or act:find("outfit") or act:find("chat") then
            return false
        end
    end

    if npc:GetAttribute("unhurt") or npc:GetAttribute("HallowNoBar") then
        return false
    end

    local name = npc.Name:lower()
    for _, ign in ipairs(HALLOW_IGNORE_KEYWORDS) do
        if name:find(ign, 1, true) then return false end
    end

    local p = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart")
    if not p then return false end

    local ws = game:GetService("Workspace")
    local raidsFolder = ws:FindFirstChild("Raids")
    if raidsFolder and npc:IsDescendantOf(raidsFolder) then
        return true
    end

    if math.abs(p.Position.X - 40000) > 4000 then
        return false
    end

    for _, kw in ipairs(HALLOW_FOE_KEYWORDS) do
        if name:find(kw, 1, true) then return true end
    end

    local ply = Players.LocalPlayer
    local hrp = ply and ply.Character and ply.Character:FindFirstChild("HumanoidRootPart")
    if hrp and math.abs(hrp.Position.X - 40000) < 4000 then
        local npcsFolder = ws:FindFirstChild("Murim_NPCs")
        if npcsFolder and npc.Parent == npcsFolder then
            if (p.Position - hrp.Position).Magnitude < 300 then
                return true
            end
        end
    end

    return false
end

local function buildMaster()
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualInputManager
pcall(function() VirtualInputManager = game:GetService("VirtualInputManager") end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remote สำหรับสั่งโจมตี
local function findCombatRemote()
    local murim = ReplicatedStorage:FindFirstChild("Murim")
    local remotes = murim and murim:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("CombatInput")
end
local combatRemote = findCombatRemote()

local function findArtifactRemote()
    local murim = ReplicatedStorage:FindFirstChild("Murim")
    local remotes = murim and murim:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("Artifact")
end
local artifactRemote = findArtifactRemote()

local hubUI = {}
local originalHitboxes = setmetatable({}, { __mode = "k" })
local selectedNPCNames = {} -- รายชื่อมอนที่เลือก [Name] = true/false
local knownNPCNames = {}    -- รายชื่อมอนสเตอร์พร้อมเลเวล [Name] = Level Number
local savedNPCPositions = {}-- บันทึกตำแหน่งมอนสเตอร์ [Name] = CFrame (Auto Save)
local favoriteNPCNames = {} -- [Name] = true; priority targets for this session
local currentTarget = nil
local isAutoFarmBoss = false -- เปิดใช้งาน Auto Farm Boss
local selectedBossNames = {} -- รายชื่อบอสที่เลือก [Key/Name] = true/false
local bossCache = {}         -- [Key] = { Name, CFrame, TimeText, InFolder, Key, Level }
local activeBossTarget = nil
local bossProbeAt = {}
local lastBossCFrame = nil
local bossLootWaitUntil = 0
local updateBossTimers = nil

local KNOWN_BOSSES = {
    {
        Key = "Ye Wuxian, the Stringless Bow",
        Name = "Ye Wuxian, the Stringless Bow",
        Alias = {"ye wuxian", "stringless bow", "wuxian"},
        Level = 95
    },
    {
        Key = "Qiongyu, the White-Jade Dragon",
        Name = "Qiongyu, the White-Jade Dragon",
        Alias = {"qiongyu", "white-jade dragon", "jade dragon", "white jade dragon"},
        Level = 92
    },
    {
        Key = "Patriarch Lou Kunshan",
        Name = "Patriarch Lou Kunshan",
        Alias = {"patriarch lou kunshan", "lou kunshan", "kunshan", "patriarch"},
        Level = 126
    }
}

local function resolveBossKey(rawName)
    if not rawName or rawName == "" then return nil end
    local lower = rawName:lower()
    for _, info in ipairs(KNOWN_BOSSES) do
        if info.Key:lower() == lower or info.Name:lower() == lower then
            return info.Key
        end
        for _, alias in ipairs(info.Alias or {}) do
            if lower:find(alias:lower(), 1, true) then
                return info.Key
            end
        end
    end
    for key, data in pairs(bossCache) do
        local kLow = key:lower()
        local dLow = (data.Name or ""):lower()
        if kLow == lower or dLow == lower or kLow:find(lower, 1, true) or lower:find(kLow, 1, true) then
            return key
        end
    end
    return rawName
end

local function checkIsBossName(name)
    if not name or name == "" then return false end
    local lower = name:lower()
    for _, info in ipairs(KNOWN_BOSSES) do
        if info.Key == name or info.Name == name or lower == info.Key:lower() or lower == info.Name:lower() then
            return true
        end
        for _, alias in ipairs(info.Alias or {}) do
            if lower:find(alias:lower(), 1, true) then
                return true
            end
        end
    end
    if name:find(",%s*the%s+") then
        return true
    end
    if lower:find("dragon") or lower:find("boss") or lower:find("patriarch") or lower:find("kunshan") then
        return true
    end
    if bossCache[name] then
        return true
    end
    return false
end

local bossEntityCache = setmetatable({}, { __mode = "k" })
local function checkIsBoss(npc)
    if not npc or not npc:IsA("Model") then return false, nil end
    local cached = bossEntityCache[npc]
    if cached ~= nil then
        if cached == false then return false, nil end
        return true, cached
    end
    local name = npc.Name
    if checkIsBossName(name) then
        local k = resolveBossKey(name) or name
        bossEntityCache[npc] = k
        return true, k
    end
    if npc:FindFirstChild("BossTimer", true) then
        bossEntityCache[npc] = name
        return true, name
    end
    bossEntityCache[npc] = false
    return false, nil
end

local npcLevelCache = setmetatable({}, { __mode = "k" })
local function getNPCLevel(npc)
	if not npc then return 0 end
    local cachedLvl = npcLevelCache[npc]
    if cachedLvl ~= nil then return cachedLvl end

	local attrLevel = npc:GetAttribute("Level") or npc:GetAttribute("Lv") or npc:GetAttribute("LevelValue")
	if typeof(attrLevel) == "number" then
        npcLevelCache[npc] = attrLevel
        return attrLevel
    end

	local levelVal = npc:FindFirstChild("Level") or npc:FindFirstChild("Lv") or npc:FindFirstChild("LevelValue")
	if levelVal and (levelVal:IsA("IntValue") or levelVal:IsA("NumberValue")) then
        npcLevelCache[npc] = levelVal.Value
		return levelVal.Value
	end

	local statsFolder = npc:FindFirstChild("Stats") or npc:FindFirstChild("Configuration") or npc:FindFirstChild("Data")
	if statsFolder then
		local lvl = statsFolder:FindFirstChild("Level") or statsFolder:FindFirstChild("Lv")
		if lvl and (lvl:IsA("IntValue") or lvl:IsA("NumberValue")) then
            npcLevelCache[npc] = lvl.Value
			return lvl.Value
		end
	end

	local bKey = resolveBossKey(npc.Name)
	if bKey then
		for _, info in ipairs(KNOWN_BOSSES) do
			if (info.Key == bKey or info.Name == bKey) and info.Level and info.Level > 0 then
				npcLevelCache[npc] = info.Level
				return info.Level
			end
		end
	end

	local match = npc.Name:match("%d+")
	if match then
        local num = tonumber(match)
        npcLevelCache[npc] = num
        return num
    end

    for _, desc in ipairs(npc:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            local lvlMatch = desc.Text:match("[Ll][Vv]%.?%s*(%d+)") or desc.Text:match("[Ll]evel%s*(%d+)")
            if lvlMatch then
                local num = tonumber(lvlMatch)
                if num and num > 0 then
                    npcLevelCache[npc] = num
                    return num
                end
            end
        end
    end

    npcLevelCache[npc] = 0
	return 0
end

local function getNPCRootPart(npc)
    if not npc or not npc:IsA("Model") then return nil end
    return npc:FindFirstChild("HumanoidRootPart")
        or npc.PrimaryPart
        or npc:FindFirstChild("Torso")
        or npc:FindFirstChild("UpperTorso")
        or npc:FindFirstChild("LowerTorso")
        or npc:FindFirstChild("Root")
        or npc:FindFirstChild("RootPart")
        or npc:FindFirstChild("Hitbox")
        or npc:FindFirstChild("Main")
        or npc:FindFirstChild("Base")
        or npc:FindFirstChild("Head")
        or npc:FindFirstChildWhichIsA("BasePart")
end

local function revealInvisibleNPC(npc)
    if not npc or not npc:IsA("Model") then return end
    pcall(function()
        for _, p in ipairs(npc:GetDescendants()) do
            if p:IsA("BasePart") then
                p.LocalTransparencyModifier = 0
                if p.Transparency >= 0.85 and p.Name ~= "HumanoidRootPart" then
                    p.Transparency = 0.25
                    p.Material = Enum.Material.ForceField
                    p.Color = Color3.fromRGB(190, 80, 255)
                end
            end
        end
        local hl = npc:FindFirstChild("MurimBossHighlight")
        if not hl then
            hl = Instance.new("Highlight")
            hl.Name = "MurimBossHighlight"
            hl.FillColor = Color3.fromRGB(180, 70, 255)
            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
            hl.FillTransparency = 0.5
            hl.OutlineTransparency = 0
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = npc
        end
    end)
end

local friendlyCache = setmetatable({}, { __mode = "k" })
local function isFriendlyOrTalkable(npc)
    if not npc or not npc:IsA("Model") then return true end
    local cached = friendlyCache[npc]
    if cached ~= nil then return cached end

    if checkIsBoss(npc) then
        friendlyCache[npc] = false
        return false
    end

    -- 1. ProximityPrompt check (interactive dialogue/quest NPCs have prompts)
    if npc:FindFirstChildWhichIsA("ProximityPrompt", true) then
        friendlyCache[npc] = true
        return true
    end

    -- 2. Dialog / DialogChoice objects
    if npc:FindFirstChildWhichIsA("Dialog", true) or npc:FindFirstChildWhichIsA("DialogChoice", true) then
        friendlyCache[npc] = true
        return true
    end

    -- 3. ClickDetector
    if npc:FindFirstChildWhichIsA("ClickDetector", true) then
        friendlyCache[npc] = true
        return true
    end

    -- 4. Dialogue / Interaction folders or objects
    for _, name in ipairs({"Interaction", "Dialog", "Dialogue", "Talk", "Quest", "Shop", "Conversation"}) do
        if npc:FindFirstChild(name, true) then
            friendlyCache[npc] = true
            return true
        end
    end

    -- 5. Check BillboardGuis / SurfaceGuis for talk / writ / quest prompts
    for _, desc in ipairs(npc:GetDescendants()) do
        if desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
            local descName = desc.Name:lower()
            if descName:find("dialog") or descName:find("talk") or descName:find("quest") or descName:find("writ") or descName:find("prompt") or descName:find("interact") then
                friendlyCache[npc] = true
                return true
            end
            for _, label in ipairs(desc:GetDescendants()) do
                if label:IsA("TextLabel") then
                    local txt = label.Text:lower()
                    if txt:find("writ") or txt:find("talk") or txt:find("speak") or txt:find("quest") or txt:find("again every hour") or txt:find("hour") then
                        friendlyCache[npc] = true
                        return true
                    end
                end
            end
        end
    end

    friendlyCache[npc] = false
    return false
end

local function isAlive(npc)
	if not npc or not npc:IsA("Model") or not npc.Parent or not npc:IsDescendantOf(Workspace) then return false end
    if isFriendlyOrTalkable(npc) then return false end
	local hum = npc:FindFirstChildOfClass("Humanoid")
	if hum and hum.MaxHealth > 0 then
		if hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then return false end
	end
    if npc:GetAttribute("Dead") == true or npc:GetAttribute("IsDead") == true then return false end
	local targetPart = getNPCRootPart(npc)
	return targetPart ~= nil
end

-- Pre-seed bossCache so Boss tab is NEVER blank!
for _, info in ipairs(KNOWN_BOSSES) do
    bossCache[info.Key] = {
        Key = info.Key,
        Name = info.Name,
        Level = info.Level,
        TimeText = "🔥 บอสเกิดแล้ว!",
        InFolder = false,
        CFrame = nil
    }
end

local isFarming = false
local isAutoLooting = true -- เปิดใช้งาน Auto Loot เป็นค่าเริ่มต้น
local isHitboxExpanded = true -- เปิดใช้งาน ขยาย Hitbox เป็นค่าเริ่มต้น
local isAutoParry = true -- เปิดใช้งาน Auto Parry เป็นค่าเริ่มต้น
local PARRY_DISTANCE = 18
local PARRY_WINDOW = 0.22
local PARRY_LEAD = 0.12
local isParrying = false
local handledAttacks = setmetatable({}, { __mode = "k" })

local isAutoArtifact = true -- เปิดใช้งาน Auto Artifact เป็นค่าเริ่มต้น
local artifactCooldown = 2.0 -- ความถี่ในการยิง Artifact (วินาที)
local lastArtifactUsed = 0
local artifactTask = nil

-- 🎁 Auto Loot & Loot Filter Configuration
local murimShared = nil
pcall(function()
    local murim = ReplicatedStorage:FindFirstChild("Murim") or ReplicatedStorage:WaitForChild("Murim", 5)
    murimShared = murim and (murim:FindFirstChild("Shared") or murim:WaitForChild("Shared", 5))
end)
local murimItems = nil
local murimConfig = nil
local murimBossKeys = nil
local murimItemColors = nil
if murimShared then
    pcall(function() murimItems = require(murimShared:WaitForChild("Items", 3)) end)
    pcall(function() murimConfig = require(murimShared:WaitForChild("Config", 3)) end)
    pcall(function() murimBossKeys = require(murimShared:WaitForChild("BossKeys", 3)) end)
    pcall(function() murimItemColors = require(murimShared:WaitForChild("ItemColors", 3)) end)
end

local heavenGradeThreshold = 4
if murimItems and murimItems.HeavenGrade then
    heavenGradeThreshold = tonumber(murimItems.HeavenGrade) or 4
end

local LOOT_FILTER_OPTIONS = {
    { text = "ทั้งหมด (All)", minIdx = 1 },
    { text = "เขียวขึ้นไป (Uncommon+)", minIdx = 2 },
    { text = "ฟ้าขึ้นไป (Rare+)", minIdx = 3 },
    { text = "ม่วงขึ้นไป (Epic+)", minIdx = 4 },
    { text = "ส้ม/ทอง (Legendary+)", minIdx = 5 }
}
local currentLootFilterIdx = 1

local KEEP_CATS = {
    ["Currency"] = true,
    ["Quest"] = true,
    ["Collectible"] = true,
    ["Pet"] = true
}

local RARITY_MAP = {
    ["Common"] = 1,
    ["Uncommon"] = 2,
    ["Rare"] = 3,
    ["Epic"] = 4,
    ["Legendary"] = 5
}

local openedChests = setmetatable({}, { __mode = "k" })
local chestAttempts = setmetatable({}, { __mode = "k" })

local function isBossKey(id)
    if not murimBossKeys or type(id) ~= "string" then return false end
    local ok, res = pcall(function()
        if type(murimBossKeys.of) == "function" then
            return murimBossKeys.of(id) ~= nil
        end
        return false
    end)
    return ok and res or false
end

local chestCache = setmetatable({}, { __mode = "k" })
local function isChest(obj)
    if not obj then return false end
    local cached = chestCache[obj]
    if cached ~= nil then return cached end

    local name = obj.Name:lower()
    if name:find("chest") then
        chestCache[obj] = true
        return true
    end
    for _, prompt in ipairs(obj:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local action = (prompt.ActionText or ""):lower()
            local objText = (prompt.ObjectText or ""):lower()
            if action:find("open") or objText:find("chest") or prompt.Name:lower():find("chest") then
                chestCache[obj] = true
                return true
            end
        end
    end
    chestCache[obj] = false
    return false
end

local function shouldLootItem(drop)
    if not drop or not drop.Parent then return false end
    local personal = drop:GetAttribute("Personal")
    local owner = drop:GetAttribute("Owner")
    if personal == true and owner ~= player.UserId then
        return false
    end
    if currentLootFilterIdx <= 1 then
        return true
    end
    local itemId = drop:GetAttribute("ItemId")
    if not itemId then
        local p = drop:IsA("BasePart") and drop or drop:FindFirstChildWhichIsA("BasePart", true)
        if p then itemId = p:GetAttribute("ItemId") end
    end
    if type(itemId) ~= "string" then
        return true
    end
    local held = drop:GetAttribute("Held")
    if held and owner == player.UserId then
        return true
    end
    if drop:GetAttribute("Enchant") then
        return true
    end
    local grade = tonumber(drop:GetAttribute("Grade"))
    if grade and grade >= heavenGradeThreshold then
        return true
    end
    local seaColor = drop:GetAttribute("SeaColor")
    if type(seaColor) == "string" and murimItemColors and murimItemColors.tier then
        local ok, tier = pcall(murimItemColors.tier, seaColor)
        if ok and (tonumber(tier) or 0) >= 2 then
            return true
        end
    end
    local itemInfo = nil
    if murimItems and murimItems.get then
        local ok, info = pcall(murimItems.get, itemId)
        if ok and type(info) == "table" then
            itemInfo = info
        end
    end
    if itemInfo then
        if KEEP_CATS[itemInfo.cat] then
            return true
        end
        if isBossKey(itemInfo.id or itemId) then
            return true
        end
        local rIndex = 1
        if murimConfig and murimConfig.rarityIndex then
            local ok, idx = pcall(murimConfig.rarityIndex, itemInfo.rarity)
            if ok and tonumber(idx) then
                rIndex = tonumber(idx)
            end
        else
            rIndex = RARITY_MAP[itemInfo.rarity] or 1
        end
        return rIndex >= currentLootFilterIdx
    end
    return true
end

local mainTask = nil
local attackTask = nil
local folderConnections = {}
local externalConnections = {}
local destroyed = false
local refreshQueued = false
local npcSignature, tpSignature
local cachedTarget
local targetScanAt = 0
local TARGET_SCAN_INTERVAL = 0.15
local refreshNPCList
local function queueRefresh()
    if destroyed or refreshQueued then return end
    refreshQueued = true
    task.delay(0.1, function()
        refreshQueued = false
        if not destroyed and refreshNPCList then refreshNPCList() end
    end)
end
local function listSignature(names, levels)
    local parts = {}
    for name in pairs(names) do
        parts[#parts + 1] = string.format("%d:%s:%s", #name, name, tostring(levels[name] or 0))
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

-- ⚙️ ตั้งค่าระยะมุดใต้ตัวมอนสเตอร์ และขนาด Hitbox
local heightUnder = -10
local lyingRotation = CFrame.Angles(math.rad(90), 0, 0)
local HITBOX_SIZE = Vector3.new(12, 12, 12)
local HITBOX_TRANSPARENCY = 0.7

--------------------------------------------------------------------------------
-- 🎨 1. สร้าง ScreenGui และตั้งค่าให้อยู่ชั้นบนสุด
--------------------------------------------------------------------------------
local previousGui = playerGui:FindFirstChild("MurimMasterGui")
if previousGui then previousGui:Destroy() end
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MurimMasterGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 2147483647 -- บังคับให้อยู่บนสุดเหนือทุก GUI
screenGui.Parent = playerGui

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "ToggleButton"
toggleBtn.Size = UDim2.new(0, 160, 0, 42)
toggleBtn.Position = UDim2.new(0, 20, 0.5, -21)
toggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Text = "📜 เปิด/ปิด เมนูหลัก"
toggleBtn.Font = Enum.Font.SourceSansBold
toggleBtn.TextSize = 15
toggleBtn.Parent = screenGui

local cornerToggle = Instance.new("UICorner")
cornerToggle.CornerRadius = UDim.new(0, 8)
cornerToggle.Parent = toggleBtn

local strokeToggle = Instance.new("UIStroke")
strokeToggle.Color = Color3.fromRGB(90, 80, 160)
strokeToggle.Thickness = 1.5
strokeToggle.Parent = toggleBtn

--------------------------------------------------------------------------------
-- 🎨 2. Main Frame หน้าต่างหลัก
--------------------------------------------------------------------------------
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 340, 0, 680)
mainFrame.Position = UDim2.new(0.5, -170, 0.5, -340)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
mainFrame.Visible = true
mainFrame.Parent = screenGui

local cornerMain = Instance.new("UICorner")
cornerMain.CornerRadius = UDim.new(0, 12)
cornerMain.Parent = mainFrame

local strokeMain = Instance.new("UIStroke")
strokeMain.Color = Color3.fromRGB(50, 50, 70)
strokeMain.Thickness = 1.5
strokeMain.Parent = mainFrame

-- Title Header Bar
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 45)
titleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, -50, 1, 0)
titleLabel.Position = UDim2.new(0, 15, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "MURIM MASTER HUB • v2"
titleLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 15
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

-- ระบบลากหน้าต่าง GUI
local dragging, dragInput, dragStart, startPos
titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = mainFrame.Position

	end
end)
titleBar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)
externalConnections[#externalConnections + 1] = UserInputService.InputChanged:Connect(function(input)
	if input == dragInput and dragging then
		local delta = input.Position - dragStart
		mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

externalConnections[#externalConnections + 1] = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- ปุ่มปิด (X)
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -36, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Text = "−"
closeBtn.Font = Enum.Font.SourceSansBold
closeBtn.TextSize = 14
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

--------------------------------------------------------------------------------
-- 🎨 3. ส่วนเนื้อหาภายใน GUI
--------------------------------------------------------------------------------

local npcListHeader = Instance.new("TextLabel")
npcListHeader.Size = UDim2.new(1, -24, 0, 20)
npcListHeader.Position = UDim2.new(0, 12, 0, 52)
npcListHeader.BackgroundTransparency = 1
npcListHeader.Text = "🎯 เลือกมอนสเตอร์ที่ต้องการฟาร์ม:"
npcListHeader.TextColor3 = Color3.fromRGB(200, 200, 220)
npcListHeader.Font = Enum.Font.SourceSansBold
npcListHeader.TextSize = 13
npcListHeader.TextXAlignment = Enum.TextXAlignment.Left
npcListHeader.Parent = mainFrame

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Name = "NPCList"
scrollFrame.Size = UDim2.new(1, -24, 0, 140)
scrollFrame.Position = UDim2.new(0, 12, 0, 74)
scrollFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 5
scrollFrame.Parent = mainFrame
Instance.new("UICorner", scrollFrame).CornerRadius = UDim.new(0, 8)

local uiListLayout = Instance.new("UIListLayout")
uiListLayout.Parent = scrollFrame
uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiListLayout.Padding = UDim.new(0, 4)
uiListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, uiListLayout.AbsoluteContentSize.Y + 8)
end)

local tpHeaderLabel = Instance.new("TextLabel")
tpHeaderLabel.Name = "TPHeaderLabel"
tpHeaderLabel.Size = UDim2.new(1, -24, 0, 20)
tpHeaderLabel.Position = UDim2.new(0, 12, 0, 222)
tpHeaderLabel.BackgroundTransparency = 1
tpHeaderLabel.Text = "🌀 พิกัดวาร์ปมอนสเตอร์ (Auto-Saved | มาก -> น้อย):"
tpHeaderLabel.TextColor3 = Color3.fromRGB(180, 160, 255)
tpHeaderLabel.Font = Enum.Font.SourceSansBold
tpHeaderLabel.TextSize = 13
tpHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
tpHeaderLabel.Parent = mainFrame

local tpScrollFrame = Instance.new("ScrollingFrame")
tpScrollFrame.Name = "TPList"
tpScrollFrame.Size = UDim2.new(1, -24, 0, 120)
tpScrollFrame.Position = UDim2.new(0, 12, 0, 244)
tpScrollFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
tpScrollFrame.BorderSizePixel = 0
tpScrollFrame.ScrollBarThickness = 5
tpScrollFrame.Parent = mainFrame
Instance.new("UICorner", tpScrollFrame).CornerRadius = UDim.new(0, 8)

local tpListLayout = Instance.new("UIListLayout")
tpListLayout.Parent = tpScrollFrame
tpListLayout.SortOrder = Enum.SortOrder.LayoutOrder
tpListLayout.Padding = UDim.new(0, 4)
tpListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	tpScrollFrame.CanvasSize = UDim2.new(0, 0, 0, tpListLayout.AbsoluteContentSize.Y + 8)
end)

--------------------------------------------------------------------------------
-- 🎨 4. ส่วนปุ่มควบคุมและการตั้งค่า
--------------------------------------------------------------------------------

local distLabel = Instance.new("TextLabel")
distLabel.Name = "DistanceLabel"
distLabel.Size = UDim2.new(1, -24, 0, 20)
distLabel.Position = UDim2.new(0, 12, 1, -298)
distLabel.BackgroundTransparency = 1
distLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
distLabel.Font = Enum.Font.SourceSansBold
distLabel.TextSize = 13
distLabel.Parent = mainFrame

local function updateDistText()
	distLabel.Text = string.format("📏 ระยะมุดใต้ตัว: %.1f studs", heightUnder)
end
updateDistText()

local addDistBtn = Instance.new("TextButton")
addDistBtn.Size = UDim2.new(0, 152, 0, 28)
addDistBtn.Position = UDim2.new(0, 12, 1, -274)
addDistBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
addDistBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
addDistBtn.Text = "⬆️ +0.5 (ตื้นขึ้น)"
addDistBtn.Font = Enum.Font.SourceSansBold
addDistBtn.TextSize = 12
addDistBtn.Parent = mainFrame
Instance.new("UICorner", addDistBtn).CornerRadius = UDim.new(0, 6)

local subDistBtn = Instance.new("TextButton")
subDistBtn.Size = UDim2.new(0, 152, 0, 28)
subDistBtn.Position = UDim2.new(1, -164, 1, -274)
subDistBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
subDistBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
subDistBtn.Text = "⬇️ -0.5 (ลึกลง)"
subDistBtn.Font = Enum.Font.SourceSansBold
subDistBtn.TextSize = 12
subDistBtn.Parent = mainFrame
Instance.new("UICorner", subDistBtn).CornerRadius = UDim.new(0, 6)

addDistBtn.MouseButton1Click:Connect(function()
	heightUnder = math.min(-0.5, heightUnder + 0.5)
	updateDistText()
end)
subDistBtn.MouseButton1Click:Connect(function()
	heightUnder = math.max(-15.0, heightUnder - 0.5)
	updateDistText()
end)

local toggleHitboxBtn = Instance.new("TextButton")
toggleHitboxBtn.Size = UDim2.new(1, -24, 0, 32)
toggleHitboxBtn.Position = UDim2.new(0, 12, 1, -240)
toggleHitboxBtn.BackgroundColor3 = Color3.fromRGB(40, 110, 150)
toggleHitboxBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleHitboxBtn.Text = "🎯 ขยาย Hitbox มอนสเตอร์ (Hitbox: ON)"
toggleHitboxBtn.Font = Enum.Font.SourceSansBold
toggleHitboxBtn.TextSize = 13
toggleHitboxBtn.Parent = mainFrame
Instance.new("UICorner", toggleHitboxBtn).CornerRadius = UDim.new(0, 6)

local toggleLootBtn = Instance.new("TextButton")
toggleLootBtn.Size = UDim2.new(1, -24, 0, 32)
toggleLootBtn.Position = UDim2.new(0, 12, 1, -202)
toggleLootBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 80)
toggleLootBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleLootBtn.Text = "🎁 เก็บของอัตโนมัติ (Auto Loot: ON)"
toggleLootBtn.Font = Enum.Font.SourceSansBold
toggleLootBtn.TextSize = 13
toggleLootBtn.Parent = mainFrame
Instance.new("UICorner", toggleLootBtn).CornerRadius = UDim.new(0, 6)

local startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.new(1, -24, 0, 36)
startBtn.Position = UDim2.new(0, 12, 1, -162)
startBtn.BackgroundColor3 = Color3.fromRGB(35, 150, 65)
startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
startBtn.Text = "เริ่มฟาร์ม"
startBtn.Font = Enum.Font.SourceSansBold
startBtn.TextSize = 14
startBtn.Parent = mainFrame
Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0, 6)

local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(1, -24, 0, 34)
stopBtn.Position = UDim2.new(0, 12, 1, -120)
stopBtn.BackgroundColor3 = Color3.fromRGB(170, 75, 30)
stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
stopBtn.Text = "หยุดทั้งหมด"
stopBtn.Font = Enum.Font.SourceSansBold
stopBtn.TextSize = 14
stopBtn.Parent = mainFrame
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 6)

local destroyBtn = Instance.new("TextButton")
destroyBtn.Size = UDim2.new(1, -24, 0, 34)
destroyBtn.Position = UDim2.new(0, 12, 1, -80)
destroyBtn.BackgroundColor3 = Color3.fromRGB(140, 35, 35)
destroyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
destroyBtn.Text = "🗑️ ปิดและลบ GUI (Destroy)"
destroyBtn.Font = Enum.Font.SourceSansBold
destroyBtn.TextSize = 14
destroyBtn.Parent = mainFrame
Instance.new("UICorner", destroyBtn).CornerRadius = UDim.new(0, 6)

--------------------------------------------------------------------------------
-- ⚙️ 5. ระบบคำนวณและฟังก์ชันฟาร์ม
--------------------------------------------------------------------------------

do
-- Presentation only: all existing callbacks and farming logic stay unchanged.
-- Use the same positioning style as the original GUI.
local windowWidth, windowHeight = 460, 680
local camera = Workspace.CurrentCamera
if camera then
    local viewport = camera.ViewportSize
    if viewport.X > 0 and viewport.Y > 0 then
        windowWidth = math.min(windowWidth, math.max(240, viewport.X - 24))
        windowHeight = math.min(windowHeight, math.max(240, viewport.Y - 72))
    end
end
mainFrame.Size = UDim2.new(0, windowWidth, 0, windowHeight)
mainFrame.Position = UDim2.new(0.5, -windowWidth / 2, 0.5, -windowHeight / 2)
mainFrame.BackgroundColor3 = Color3.fromRGB(17, 20, 29)
strokeMain.Color = Color3.fromRGB(55, 65, 87)

titleBar.Size = UDim2.new(1, 0, 0, 56)
titleBar.BackgroundColor3 = Color3.fromRGB(24, 29, 41)
titleLabel.Position = UDim2.new(0, 16, 0, 0)
titleLabel.Size = UDim2.new(1, -76, 1, 0)
titleLabel.TextColor3 = Color3.fromRGB(231, 235, 248)
titleLabel.TextSize = 16
titleLabel.TextWrapped = true
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -44, 0, 12)
closeBtn.BackgroundColor3 = Color3.fromRGB(106, 46, 58)
toggleBtn.Position = UDim2.new(0, 16, 0.5, -21)

local function sectionHeading(label, parent, text)
    label.Parent = parent
    label.Position = UDim2.new(0, 12, 0, 8)
    label.Size = UDim2.new(1, -24, 0, 28)
    label.Text = text
    label.TextColor3 = Color3.fromRGB(199, 210, 235)
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
end
local function newHeading(parent, text)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.SourceSansBold
    sectionHeading(label, parent, text)
end
local function placeButton(button, parent, xScale, xOffset, y, widthScale, widthOffset)
    button.Parent = parent
    button.Position = UDim2.new(xScale, xOffset, 0, y)
    button.Size = UDim2.new(widthScale, widthOffset, 0, 36)
    button.BorderSizePixel = 0
    button.TextSize = 14
    button.TextWrapped = true
end

local tabsBar = Instance.new("Frame")
tabsBar.Name = "Tabs"
tabsBar.Position = UDim2.new(0, 12, 0, 66)
tabsBar.Size = UDim2.new(1, -24, 0, 82)
tabsBar.BackgroundTransparency = 1
tabsBar.Parent = mainFrame
local pagesHost = Instance.new("Frame")
pagesHost.Name = "Pages"
pagesHost.Position = UDim2.new(0, 12, 0, 158)
pagesHost.Size = UDim2.new(1, -24, 1, -220)
pagesHost.BackgroundTransparency = 1
pagesHost.ClipsDescendants = true
pagesHost.Parent = mainFrame
local pages, tabs = {}, {}
local function showPage(index)
    for i, page in pairs(pages) do
        page.Visible = i == index
        if tabs[i] then
            tabs[i].BackgroundColor3 = i == index and Color3.fromRGB(72, 86, 147) or Color3.fromRGB(30, 37, 51)
            tabs[i].TextColor3 = i == index and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(165, 179, 205)
        end
    end
    if index == 2 and typeof(updateBossTimers) == "function" then
        task.defer(function()
            pcall(updateBossTimers)
        end)
    end
end
local function makePage(name, index, caption)
    local page = Instance.new("Frame")
    page.Name = name
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
    page.BorderSizePixel = 0
    page.Visible = false
    page.Parent = pagesHost
    Instance.new("UICorner", page).CornerRadius = UDim.new(0, 10)
    pages[index] = page
    local tab = Instance.new("TextButton")
    tab.Name = name .. "Tab"
    tab.Size = UDim2.new(1 / 4, -4, 0, 38)
    tab.Position = UDim2.new(((index - 1) % 4) / 4, ((index - 1) % 4) * 2, 0, math.floor((index - 1) / 4) * 44)
    tab.BorderSizePixel = 0
    tab.Font = Enum.Font.SourceSansBold
    tab.TextSize = 13
    tab.Text = caption
    tab.TextWrapped = true
    tab.Parent = tabsBar
    Instance.new("UICorner", tab).CornerRadius = UDim.new(0, 8)
    tabs[index] = tab
    tab.MouseButton1Click:Connect(function() showPage(index) end)
    return page
end

local npcPage = makePage("Monsters", 1, "มอนสเตอร์")
sectionHeading(npcListHeader, npcPage, "เลือกมอนสเตอร์ • กด ★ เพื่อตีตัวโปรดก่อน")

--------------------------------------------------------------------------------
-- ⚔️ Boss Page (Index 2)
--------------------------------------------------------------------------------
local function getCFrameFromAnchor(anchor)
    if not anchor then return nil end
    if anchor:IsA("BasePart") then return anchor.CFrame end
    if anchor:IsA("Model") then return anchor:GetPivot() end
    if anchor:IsA("CFrameValue") then return anchor.Value end
    if anchor:IsA("Vector3Value") then return CFrame.new(anchor.Value) end
    if anchor:IsA("ObjectValue") and anchor.Value then
        local t = anchor.Value
        if t:IsA("BasePart") then return t.CFrame end
        if t:IsA("Model") then return t:GetPivot() end
    end
    return nil
end

local function parseBossInfo(bossItem)
    local bossName = bossItem.Name
    local timeText = "N/A"
    local cf = nil

    local anchor = bossItem:FindFirstChild("Anchor") or bossItem
    if anchor then
        cf = getCFrameFromAnchor(anchor)
        local bossTimer = (bossItem:FindFirstChild("Anchor") and bossItem.Anchor:FindFirstChild("BossTimer"))
            or bossItem:FindFirstChild("BossTimer")
            or bossItem:FindFirstChildWhichIsA("BillboardGui", true)
            or bossItem:FindFirstChildWhichIsA("SurfaceGui", true)
        if bossTimer then
            local textLabels = {}
            for _, desc in ipairs(bossTimer:GetDescendants()) do
                if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and desc.Text ~= "" then
                    table.insert(textLabels, desc)
                end
            end
            if #textLabels > 0 then
                local nameObj = nil
                local timerObj = nil
                for _, lbl in ipairs(textLabels) do
                    local txt = lbl.Text
                    if txt:find("%d+[%smh:]") or txt:find("เกิดแล้ว") then
                        timerObj = lbl
                    else
                        nameObj = lbl
                    end
                end
                if nameObj then bossName = nameObj.Text end
                if timerObj then timeText = timerObj.Text end
            end

            for _, desc in ipairs(bossTimer:GetDescendants()) do
                if desc:IsA("ValueBase") then
                    local rawVal = desc.Value
                    if type(rawVal) == "number" then
                        if rawVal <= 0 then
                            timeText = "🔥 บอสเกิดแล้ว!"
                        elseif rawVal >= 60 then
                            local mins = math.floor(rawVal / 60)
                            local secs = math.floor(rawVal % 60)
                            timeText = string.format("%dm %02ds", mins, secs)
                        else
                            timeText = string.format("%.1fs", rawVal)
                        end
                    else
                        timeText = tostring(rawVal)
                    end
                    break
                end
            end
        end
    end
    
    return bossName, timeText, cf
end

local bossPage = makePage("Bosses", 2, "บอส")
newHeading(bossPage, "ล่าบอสอัตโนมัติ & ตรวจจับเวลาบอส")

local toggleBossBtn = Instance.new("TextButton")
toggleBossBtn.Name = "ToggleBossFarmBtn"
toggleBossBtn.Size = UDim2.new(1, -24, 0, 36)
toggleBossBtn.Position = UDim2.new(0, 12, 0, 44)
toggleBossBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
toggleBossBtn.Text = "⚔️ ล่าบอสอัตโนมัติ (Auto Boss: OFF)"
toggleBossBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBossBtn.TextSize = 13
toggleBossBtn.Font = Enum.Font.SourceSansBold
toggleBossBtn.Parent = bossPage
Instance.new("UICorner", toggleBossBtn).CornerRadius = UDim.new(0, 6)

local bossSubHeading = Instance.new("TextLabel")
bossSubHeading.Size = UDim2.new(1, -24, 0, 20)
bossSubHeading.Position = UDim2.new(0, 12, 0, 84)
bossSubHeading.BackgroundTransparency = 1
bossSubHeading.Text = "เลือกบอสที่ต้องการตี • บอสเกิดวาร์ปไปตีทันที • ตีเสร็จวาร์ปกลับมาฟาร์ม"
bossSubHeading.TextColor3 = Color3.fromRGB(165, 179, 205)
bossSubHeading.TextSize = 11
bossSubHeading.Font = Enum.Font.SourceSans
bossSubHeading.TextXAlignment = Enum.TextXAlignment.Left
bossSubHeading.Parent = bossPage

local bossScrollFrame = Instance.new("ScrollingFrame")
bossScrollFrame.Name = "BossScrollFrame"
bossScrollFrame.Size = UDim2.new(1, -24, 1, -112)
bossScrollFrame.Position = UDim2.new(0, 12, 0, 106)
bossScrollFrame.BackgroundColor3 = Color3.fromRGB(18, 23, 33)
bossScrollFrame.BorderSizePixel = 0
bossScrollFrame.ScrollBarThickness = 4
bossScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
bossScrollFrame.Parent = bossPage
Instance.new("UICorner", bossScrollFrame).CornerRadius = UDim.new(0, 6)

local bossListLayout = Instance.new("UIListLayout")
bossListLayout.SortOrder = Enum.SortOrder.LayoutOrder
bossListLayout.Padding = UDim.new(0, 6)
bossListLayout.Parent = bossScrollFrame

bossListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    bossScrollFrame.CanvasSize = UDim2.new(0, 0, 0, bossListLayout.AbsoluteContentSize.Y + 10)
end)

toggleBossBtn.MouseButton1Click:Connect(function()
    isAutoFarmBoss = not isAutoFarmBoss
    if isAutoFarmBoss then
        toggleBossBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 60)
        toggleBossBtn.Text = "⚔️ ล่าบอสอัตโนมัติ (Auto Boss: ON)"
    else
        toggleBossBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
        toggleBossBtn.Text = "⚔️ ล่าบอสอัตโนมัติ (Auto Boss: OFF)"
        activeBossTarget = nil
    end
end)

updateBossTimers = function()
    -- 1. Ensure known bosses are pre-seeded in bossCache and have CFrames from savedNPCPositions
    for _, info in ipairs(KNOWN_BOSSES) do
        local key = info.Key
        if not bossCache[key] then
            bossCache[key] = {
                Key = key,
                Name = info.Name,
                Level = info.Level,
                TimeText = "🔥 บอสเกิดแล้ว!",
                InFolder = false,
                CFrame = nil
            }
        end
        if not bossCache[key].CFrame then
            bossCache[key].CFrame = savedNPCPositions[key] or savedNPCPositions[info.Name]
        end
    end

    -- 2. Scan Workspace.Murim_BossTimers (countdown timer objects when bosses are dead)
    local bossFolder = Workspace:FindFirstChild("Murim_BossTimers")
    local activeInFolder = {}

    if bossFolder then
        for _, item in pairs(bossFolder:GetChildren()) do
            local bName, tText, cf = parseBossInfo(item)
            local key = resolveBossKey(bName) or resolveBossKey(item.Name) or item.Name
            activeInFolder[key] = true

            if not bossCache[key] then
                bossCache[key] = {
                    Key = key,
                    Name = bName or key,
                }
            end
            if bName and bName ~= "" and bossCache[key].Name == key then
                bossCache[key].Name = bName
            end
            if cf then
                bossCache[key].CFrame = cf
                savedNPCPositions[key] = cf
                savedNPCPositions[bName or key] = cf
            elseif not bossCache[key].CFrame then
                bossCache[key].CFrame = savedNPCPositions[key] or savedNPCPositions[bName or key]
            end
            bossCache[key].TimeText = tText
            bossCache[key].InFolder = true
        end
    end

    -- 3. Scan Workspace.Murim_NPCs (live bosses currently spawned in the world)
    local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")
    if npcsFolder then
        for _, npc in ipairs(npcsFolder:GetChildren()) do
            if npc:IsA("Model") and isAlive(npc) then
                local isBoss, bKey = checkIsBoss(npc)
                if isBoss and bKey then
                    revealInvisibleNPC(npc)
                    local part = getNPCRootPart(npc)
                    local cf = part and part.CFrame
                    if not bossCache[bKey] then
                        bossCache[bKey] = {
                            Key = bKey,
                            Name = npc.Name,
                            Level = getNPCLevel(npc)
                        }
                    end
                    if cf then
                        bossCache[bKey].CFrame = cf
                        savedNPCPositions[bKey] = cf
                        savedNPCPositions[npc.Name] = cf
                    end
                    bossCache[bKey].TimeText = "🔥 บอสเกิดแล้ว!"
                    bossCache[bKey].InFolder = false
                end
            end
        end
    end

    -- 4. Check savedNPCPositions for any previously recorded bosses
    for name, cf in pairs(savedNPCPositions) do
        if checkIsBossName(name) then
            local bKey = resolveBossKey(name) or name
            if not bossCache[bKey] then
                bossCache[bKey] = {
                    Key = bKey,
                    Name = name,
                    Level = knownNPCNames[name] or 0,
                    TimeText = "🔥 บอสเกิดแล้ว!",
                    InFolder = false,
                    CFrame = cf
                }
            elseif not bossCache[bKey].CFrame then
                bossCache[bKey].CFrame = cf
            end
        end
    end

    -- 5. Any boss not in Murim_BossTimers is considered alive/spawned
    for key, data in pairs(bossCache) do
        if not activeInFolder[key] then
            data.InFolder = false
            data.TimeText = "🔥 บอสเกิดแล้ว!"
            if not data.CFrame then
                data.CFrame = savedNPCPositions[key] or savedNPCPositions[data.Name]
            end
        end
    end

    if not bossScrollFrame or not bossScrollFrame.Parent then return end

    -- Sort bosses by Level descending, then Name
    local sortedBosses = {}
    for key, data in pairs(bossCache) do
        table.insert(sortedBosses, data)
    end
    table.sort(sortedBosses, function(a, b)
        local la = a.Level or 0
        local lb = b.Level or 0
        if la == lb then
            return (a.Name or a.Key) < (b.Name or b.Key)
        end
        return la > lb
    end)

    local existingCards = {}
    for _, child in pairs(bossScrollFrame:GetChildren()) do
        if child:IsA("Frame") then
            existingCards[child.Name] = child
        end
    end

    for idx, data in ipairs(sortedBosses) do
        local key = data.Key
        local card = existingCards[key]
        local isSelected = selectedBossNames[key] == true
        local isSpawned = data.TimeText and data.TimeText:find("เกิดแล้ว")

        if not card then
            card = Instance.new("Frame")
            card.Name = key
            card.Size = UDim2.new(1, -6, 0, 42)
            card.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
            card.BorderSizePixel = 0
            card.Parent = bossScrollFrame

            local cardCorner = Instance.new("UICorner")
            cardCorner.CornerRadius = UDim.new(0, 6)
            cardCorner.Parent = card

            local selectBtn = Instance.new("TextButton")
            selectBtn.Name = "SelectBtn"
            selectBtn.Size = UDim2.new(0.50, -5, 1, 0)
            selectBtn.Position = UDim2.new(0, 8, 0, 0)
            selectBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
            selectBtn.TextSize = 13
            selectBtn.Font = Enum.Font.SourceSansBold
            selectBtn.TextXAlignment = Enum.TextXAlignment.Left
            selectBtn.TextTruncate = Enum.TextTruncate.AtEnd
            selectBtn.BackgroundTransparency = 1
            selectBtn.Parent = card

            local valLabel = Instance.new("TextLabel")
            valLabel.Name = "ValLabel"
            valLabel.Size = UDim2.new(0.30, -5, 1, 0)
            valLabel.Position = UDim2.new(0.50, 0, 0, 0)
            valLabel.TextColor3 = Color3.fromRGB(85, 255, 127)
            valLabel.TextSize = 12
            valLabel.Font = Enum.Font.SourceSansBold
            valLabel.TextXAlignment = Enum.TextXAlignment.Right
            valLabel.BackgroundTransparency = 1
            valLabel.Parent = card

            local tpBtn = Instance.new("TextButton")
            tpBtn.Name = "TPBtn"
            tpBtn.Size = UDim2.new(0.18, -6, 0, 26)
            tpBtn.Position = UDim2.new(0.82, 0, 0.5, -13)
            tpBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 240)
            tpBtn.Text = "TP"
            tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            tpBtn.Font = Enum.Font.SourceSansBold
            tpBtn.TextSize = 12
            tpBtn.Parent = card

            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, 4)
            btnCorner.Parent = tpBtn

            selectBtn.MouseButton1Click:Connect(function()
                selectedBossNames[key] = not selectedBossNames[key]
                pcall(updateBossTimers)
            end)

            tpBtn.MouseButton1Click:Connect(function()
                local currentData = bossCache[key]
                local targetCF = (currentData and currentData.CFrame)
                    or savedNPCPositions[key]
                    or (currentData and savedNPCPositions[currentData.Name])
                if targetCF then
                    local char = player.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        hrp.CFrame = targetCF * CFrame.new(0, 4, 0)
                        tpBtn.Text = "✅"
                        task.delay(1, function()
                            if tpBtn and tpBtn.Parent then tpBtn.Text = "TP" end
                        end)
                    end
                else
                    tpBtn.Text = "❌ รอพิกัด"
                    task.delay(1.5, function()
                        if tpBtn and tpBtn.Parent then tpBtn.Text = "TP" end
                    end)
                end
            end)
        end

        card.LayoutOrder = idx

        local selectBtn = card:FindFirstChild("SelectBtn")
        local valLabel = card:FindFirstChild("ValLabel")
        local tpBtn = card:FindFirstChild("TPBtn")

        if selectBtn and valLabel then
            local lvlStr = (data.Level and data.Level > 0) and string.format(" [Lv.%d]", data.Level) or ""
            local newSelTxt = (isSelected and "[✓] " or "[ ] ") .. (data.Name or key) .. lvlStr
            if selectBtn.Text ~= newSelTxt then selectBtn.Text = newSelTxt end
            local newTimeTxt = data.TimeText or "🔥 บอสเกิดแล้ว!"
            if valLabel.Text ~= newTimeTxt then valLabel.Text = newTimeTxt end

            if isSpawned then
                if valLabel.TextColor3 ~= Color3.fromRGB(255, 80, 80) then
                    valLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
                end
                local targetBg = isSelected and Color3.fromRGB(75, 30, 35) or Color3.fromRGB(55, 25, 30)
                if card.BackgroundColor3 ~= targetBg then card.BackgroundColor3 = targetBg end
            else
                if valLabel.TextColor3 ~= Color3.fromRGB(85, 255, 127) then
                    valLabel.TextColor3 = Color3.fromRGB(85, 255, 127)
                end
                local targetBg = isSelected and Color3.fromRGB(30, 60, 45) or Color3.fromRGB(35, 35, 45)
                if card.BackgroundColor3 ~= targetBg then card.BackgroundColor3 = targetBg end
            end
        end

        if tpBtn then
            local hasCF = data.CFrame or savedNPCPositions[key] or (data.Name and savedNPCPositions[data.Name])
            if hasCF then
                if tpBtn.BackgroundColor3 ~= Color3.fromRGB(0, 140, 240) then
                    tpBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 240)
                end
                if tpBtn.Text ~= "✅" and not tpBtn.Text:find("❌") and tpBtn.Text ~= "TP" then
                    tpBtn.Text = "TP"
                end
            else
                if tpBtn.BackgroundColor3 ~= Color3.fromRGB(70, 70, 85) then
                    tpBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
                end
                if tpBtn.Text ~= "✅" and not tpBtn.Text:find("❌") and tpBtn.Text ~= "รอพิกัด" then
                    tpBtn.Text = "รอพิกัด"
                end
            end
        end
    end

    local totalCards = #sortedBosses
    local layoutH = bossListLayout.AbsoluteContentSize.Y
    if layoutH <= 0 then layoutH = totalCards * 48 end
    bossScrollFrame.CanvasSize = UDim2.new(0, 0, 0, math.max(layoutH + 10, totalCards * 48 + 10))
end

externalConnections[#externalConnections + 1] = Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Murim_BossTimers" then updateBossTimers() end
end)

task.spawn(function()
    while not destroyed do
        pcall(updateBossTimers)
        task.wait(1)
    end
end)

local tpPage = makePage("Teleport", 3, "จุดวาร์ป")
sectionHeading(tpHeaderLabel, tpPage, "จุดวาร์ป • บันทึกอัตโนมัติ • เลเวลสูง → ต่ำ")
scrollFrame.Parent = npcPage
tpScrollFrame.Parent = tpPage
for _, list in ipairs({scrollFrame, tpScrollFrame}) do
    list.Position = UDim2.new(0, 12, 0, 44)
    list.Size = UDim2.new(1, -24, 1, -56)
    list.BackgroundColor3 = Color3.fromRGB(18, 23, 33)
    list.ScrollBarImageColor3 = Color3.fromRGB(114, 131, 171)
    list.CanvasSize = UDim2.new(0, 0, 0, 0)

end

--------------------------------------------------------------------------------
-- ☯️ Hongmeng & Wild Qi Page (Index 7)
--------------------------------------------------------------------------------
local HongmengConfig = {
    Enabled = false,
    AutoTeleportWildQi = false,
    DiscordWebhook = "",
    DiscordNotify = true,
}
hubUI.HongmengConfig = HongmengConfig

local GradeColors = {
    [99] = Color3.fromRGB(255, 60, 100), -- WildQi Special
    [7]  = Color3.fromRGB(180, 40, 40),   -- Void
    [6]  = Color3.fromRGB(220, 170, 40),  -- Mist/Fog
    [5]  = Color3.fromRGB(130, 50, 200),  -- Thunder
    [0]  = Color3.fromRGB(60, 100, 160)   -- General
}

local GradeNames = {
    [99] = "★ WildQi (Special Target)",
    [7]  = "Grade 7 (Void)",
    [6]  = "Grade 6 (Mist/Fog)",
    [5]  = "Grade 5 (Thunder)",
}

local hongmengPage = makePage("Hongmeng", 7, "Hongmeng")
newHeading(hongmengPage, "พิธี Hongmeng & จุดเกิด Wild Qi")

local hongmengBody = Instance.new("Frame")
hongmengBody.Name = "HongmengBody"
hongmengBody.Position = UDim2.new(0, 0, 0, 44)
hongmengBody.Size = UDim2.new(1, 0, 1, -44)
hongmengBody.BackgroundTransparency = 1
hongmengBody.Parent = hongmengPage

-- Sub-tabs Bar
local hTabBar = Instance.new("Frame")
hTabBar.Name = "HTabBar"
hTabBar.Size = UDim2.new(1, -24, 0, 30)
hTabBar.Position = UDim2.new(0, 12, 0, 0)
hTabBar.BackgroundTransparency = 1
hTabBar.Parent = hongmengBody

local autoTabBtn = Instance.new("TextButton")
autoTabBtn.Name = "AutoTabBtn"
autoTabBtn.Size = UDim2.new(0.48, 0, 1, 0)
autoTabBtn.Position = UDim2.new(0, 0, 0, 0)
autoTabBtn.BackgroundColor3 = Color3.fromRGB(72, 86, 147)
autoTabBtn.Text = "Auto Hongmeng"
autoTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoTabBtn.TextSize = 13
autoTabBtn.Font = Enum.Font.SourceSansBold
autoTabBtn.Parent = hTabBar
Instance.new("UICorner", autoTabBtn).CornerRadius = UDim.new(0, 6)

local wildQiTabBtn = Instance.new("TextButton")
wildQiTabBtn.Name = "WildQiTabBtn"
wildQiTabBtn.Size = UDim2.new(0.48, 0, 1, 0)
wildQiTabBtn.Position = UDim2.new(0.52, 0, 0, 0)
wildQiTabBtn.BackgroundColor3 = Color3.fromRGB(35, 42, 58)
wildQiTabBtn.Text = "Wild Qi List"
wildQiTabBtn.TextColor3 = Color3.fromRGB(165, 179, 205)
wildQiTabBtn.TextSize = 13
wildQiTabBtn.Font = Enum.Font.SourceSansBold
wildQiTabBtn.Parent = hTabBar
Instance.new("UICorner", wildQiTabBtn).CornerRadius = UDim.new(0, 6)

-- Sub-pages
local autoPage = Instance.new("Frame")
autoPage.Name = "AutoPage"
autoPage.Size = UDim2.new(1, -24, 1, -38)
autoPage.Position = UDim2.new(0, 12, 0, 36)
autoPage.BackgroundTransparency = 1
autoPage.Visible = true
autoPage.Parent = hongmengBody

local wildQiPage = Instance.new("Frame")
wildQiPage.Name = "WildQiPage"
wildQiPage.Size = UDim2.new(1, -24, 1, -38)
wildQiPage.Position = UDim2.new(0, 12, 0, 36)
wildQiPage.BackgroundTransparency = 1
wildQiPage.Visible = false
wildQiPage.Parent = hongmengBody

-- 1. Auto Page Controls
local toggleHBtn = Instance.new("TextButton")
toggleHBtn.Name = "ToggleHBtn"
toggleHBtn.Size = UDim2.new(1, 0, 0, 38)
toggleHBtn.Position = UDim2.new(0, 0, 0, 4)
toggleHBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
toggleHBtn.Text = "AUTO HONGMENG: OFF"
toggleHBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleHBtn.TextSize = 13
toggleHBtn.Font = Enum.Font.SourceSansBold
toggleHBtn.Parent = autoPage
Instance.new("UICorner", toggleHBtn).CornerRadius = UDim.new(0, 6)

local statusHLabel = Instance.new("TextLabel")
statusHLabel.Name = "StatusHLabel"
statusHLabel.Size = UDim2.new(1, 0, 0, 56)
statusHLabel.Position = UDim2.new(0, 0, 0, 48)
statusHLabel.BackgroundTransparency = 1
statusHLabel.Text = "สถานะ: ปิดการทำงาน\n(ระบบตรวจสอบเงื่อนไขและยิง Remote อัตโนมัติ)"
statusHLabel.TextColor3 = Color3.fromRGB(170, 180, 205)
statusHLabel.TextSize = 12
statusHLabel.Font = Enum.Font.SourceSans
statusHLabel.TextWrapped = true
statusHLabel.Parent = autoPage

local searchHBtn = Instance.new("TextButton")
searchHBtn.Name = "SearchHBtn"
searchHBtn.Size = UDim2.new(1, 0, 0, 34)
searchHBtn.Position = UDim2.new(0, 0, 0, 110)
searchHBtn.BackgroundColor3 = Color3.fromRGB(45, 100, 160)
searchHBtn.Text = "เริ่ม Auto H จากข้อมูลพิธี"
searchHBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
searchHBtn.TextSize = 13
searchHBtn.Font = Enum.Font.SourceSansBold
searchHBtn.Parent = autoPage
Instance.new("UICorner", searchHBtn).CornerRadius = UDim.new(0, 6)

local guideBox = Instance.new("Frame")
guideBox.Name = "GuideBox"
guideBox.Size = UDim2.new(1, 0, 0, 110)
guideBox.Position = UDim2.new(0, 0, 0, 154)
guideBox.BackgroundColor3 = Color3.fromRGB(18, 23, 33)
guideBox.BorderSizePixel = 0
guideBox.Parent = autoPage
Instance.new("UICorner", guideBox).CornerRadius = UDim.new(0, 6)

local guideLabel = Instance.new("TextLabel")
guideLabel.Size = UDim2.new(1, -16, 1, -12)
guideLabel.Position = UDim2.new(0, 8, 0, 6)
guideLabel.BackgroundTransparency = 1
guideLabel.Text = "• ระบบตรวจจับ Remote Hongmeng และถอดรหัสอัตโนมัติ\n• เฟส Weave: หมุนผนึกแก้ค่ายกลตามจังหวะ\n• เฟส Hold: สลับทิศทางลูกศรและกดย้อนกลับทันที\n• เฟส Trib: คำนวณเวลาและกด Ward สายฟ้าอัตโนมัติ"
guideLabel.TextColor3 = Color3.fromRGB(145, 160, 185)
guideLabel.TextSize = 11
guideLabel.Font = Enum.Font.SourceSans
guideLabel.TextWrapped = true
guideLabel.TextXAlignment = Enum.TextXAlignment.Left
guideLabel.TextYAlignment = Enum.TextYAlignment.Top
guideLabel.Parent = guideBox

-- 2. Wild Qi Page Controls
local refreshQiBtn = Instance.new("TextButton")
refreshQiBtn.Name = "RefreshQiBtn"
refreshQiBtn.Size = UDim2.new(0.48, -4, 0, 30)
refreshQiBtn.Position = UDim2.new(0, 0, 0, 4)
refreshQiBtn.BackgroundColor3 = Color3.fromRGB(40, 110, 180)
refreshQiBtn.Text = "🔄 Refresh List"
refreshQiBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshQiBtn.TextSize = 12
refreshQiBtn.Font = Enum.Font.SourceSansBold
refreshQiBtn.Parent = wildQiPage
Instance.new("UICorner", refreshQiBtn).CornerRadius = UDim.new(0, 4)

local autoWarpQiBtn = Instance.new("TextButton")
autoWarpQiBtn.Name = "AutoWarpQiBtn"
autoWarpQiBtn.Size = UDim2.new(0.48, -4, 0, 30)
autoWarpQiBtn.Position = UDim2.new(0.52, 4, 0, 4)
autoWarpQiBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
autoWarpQiBtn.Text = "AUTO BEST: OFF"
autoWarpQiBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoWarpQiBtn.TextSize = 12
autoWarpQiBtn.Font = Enum.Font.SourceSansBold
autoWarpQiBtn.Parent = wildQiPage
Instance.new("UICorner", autoWarpQiBtn).CornerRadius = UDim.new(0, 4)

local webhookBox = Instance.new("TextBox")
webhookBox.Name = "DiscordWebhook"
webhookBox.Size = UDim2.new(1, 0, 0, 28)
webhookBox.Position = UDim2.new(0, 0, 0, 40)
webhookBox.BackgroundColor3 = Color3.fromRGB(18, 23, 33)
webhookBox.TextColor3 = Color3.fromRGB(240, 240, 240)
webhookBox.PlaceholderText = "Discord Webhook URL · กด Enter"
webhookBox.ClearTextOnFocus = false
webhookBox.MultiLine = false
webhookBox.TextSize = 11
webhookBox.Font = Enum.Font.SourceSans
webhookBox.TextXAlignment = Enum.TextXAlignment.Left
webhookBox.Parent = wildQiPage
Instance.new("UICorner", webhookBox).CornerRadius = UDim.new(0, 4)

local webhookStatus = Instance.new("TextLabel")
webhookStatus.Size = UDim2.new(1, 0, 0, 20)
webhookStatus.Position = UDim2.new(0, 0, 0, 72)
webhookStatus.BackgroundTransparency = 1
webhookStatus.TextColor3 = Color3.fromRGB(170, 180, 200)
webhookStatus.TextSize = 11
webhookStatus.Font = Enum.Font.SourceSans
webhookStatus.Text = "ใส่ Webhook เพื่อแจ้งเกรด 11 / 12 / 13"
webhookStatus.TextXAlignment = Enum.TextXAlignment.Left
webhookStatus.Parent = wildQiPage

local qiScrollList = Instance.new("ScrollingFrame")
qiScrollList.Name = "ScrollList"
qiScrollList.Size = UDim2.new(1, 0, 1, -100)
qiScrollList.Position = UDim2.new(0, 0, 0, 96)
qiScrollList.BackgroundColor3 = Color3.fromRGB(18, 23, 33)
qiScrollList.BorderSizePixel = 0
qiScrollList.ScrollBarThickness = 4
qiScrollList.CanvasSize = UDim2.new(0, 0, 0, 0)
qiScrollList.Parent = wildQiPage
Instance.new("UICorner", qiScrollList).CornerRadius = UDim.new(0, 6)

local qiListLayout = Instance.new("UIListLayout")
qiListLayout.Parent = qiScrollList
qiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
qiListLayout.Padding = UDim.new(0, 4)

-- Sub-tab toggling
autoTabBtn.MouseButton1Click:Connect(function()
    autoPage.Visible = true
    wildQiPage.Visible = false
    autoTabBtn.BackgroundColor3 = Color3.fromRGB(72, 86, 147)
    autoTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    wildQiTabBtn.BackgroundColor3 = Color3.fromRGB(35, 42, 58)
    wildQiTabBtn.TextColor3 = Color3.fromRGB(165, 179, 205)
end)

local scanAllWildQi, refreshQiButtons

wildQiTabBtn.MouseButton1Click:Connect(function()
    autoPage.Visible = false
    wildQiPage.Visible = true
    wildQiTabBtn.BackgroundColor3 = Color3.fromRGB(72, 86, 147)
    wildQiTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    autoTabBtn.BackgroundColor3 = Color3.fromRGB(35, 42, 58)
    autoTabBtn.TextColor3 = Color3.fromRGB(165, 179, 205)
    if refreshQiButtons then refreshQiButtons() end
end)

-- Scanner Logic
local lastQiScanTime = 0
local cachedQiList = {}
scanAllWildQi = function(force)
    local now = os.clock()
    if not force and (now - lastQiScanTime < 0.6) and #cachedQiList > 0 then
        return cachedQiList
    end
    lastQiScanTime = now
    local folder = Workspace:FindFirstChild("Murim_WildQi")
    local qiList = {}
    if not folder then
        cachedQiList = qiList
        return qiList
    end

    for _, desc in ipairs(folder:GetDescendants()) do
        if desc.Name == "WildQi" or desc.Name:find("WildQi") then
            local targetPart = desc:IsA("BasePart") and desc or (desc:IsA("Model") and (desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart", true)))
            if targetPart then
                table.insert(qiList, {
                    Target = targetPart,
                    Grade = tonumber(desc:GetAttribute("Grade"))
                        or tonumber(targetPart:GetAttribute("Grade"))
                        or tonumber(desc.Parent:GetAttribute("Grade")) or 99,
                    Name = "WildQi (Direct Target)"
                })
            end
        elseif desc:IsA("BasePart") and desc.Name == "QiSpot" and desc:GetAttribute("Wild") == true then
            local grade = tonumber(desc:GetAttribute("Grade")) or 0
            table.insert(qiList, {
                Target = desc,
                Grade = grade,
                Name = GradeNames[grade] or ("QiSpot Grade " .. tostring(grade))
            })
        end
    end

    table.sort(qiList, function(a, b)
        return a.Grade > b.Grade
    end)

    cachedQiList = qiList
    return qiList
end

refreshQiButtons = function()
    if not qiScrollList or not qiScrollList.Parent then return end
    for _, child in ipairs(qiScrollList:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local qiList = scanAllWildQi()

    if #qiList == 0 then
        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.Size = UDim2.new(1, 0, 0, 40)
        emptyLabel.BackgroundTransparency = 1
        emptyLabel.Text = "ไม่พบจุด Wild Qi เกิดในแผนที่ขณะนี้"
        emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
        emptyLabel.TextSize = 12
        emptyLabel.Font = Enum.Font.SourceSans
        emptyLabel.Parent = qiScrollList
        qiScrollList.CanvasSize = UDim2.new(0, 0, 0, 50)
        return
    end

    for i, item in ipairs(qiList) do
        local btnColor = GradeColors[item.Grade] or GradeColors[0]

        local itemBtn = Instance.new("TextButton")
        itemBtn.Name = "QiItem_" .. tostring(i)
        itemBtn.Size = UDim2.new(1, -6, 0, 32)
        itemBtn.BackgroundColor3 = btnColor
        itemBtn.Text = string.format("[%d] %s - คลิกเพื่อวาร์ป", i, item.Name)
        itemBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        itemBtn.TextSize = 12
        itemBtn.Font = Enum.Font.SourceSansBold
        itemBtn.LayoutOrder = i
        itemBtn.Parent = qiScrollList

        local itemCorner = Instance.new("UICorner", itemBtn)
        itemCorner.CornerRadius = UDim.new(0, 4)

        itemBtn.MouseButton1Click:Connect(function()
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") and item.Target and item.Target.Parent then
                char.HumanoidRootPart.CFrame = (item.Target:IsA("Model") and item.Target:GetPivot() or item.Target.CFrame) + Vector3.new(0, 3, 0)
                itemBtn.Text = "✅ วาร์ปสำเร็จ!"
                task.delay(1.5, function()
                    if itemBtn and itemBtn.Parent then
                        itemBtn.Text = string.format("[%d] %s - คลิกเพื่อวาร์ป", i, item.Name)
                    end
                end)
            end
        end)
    end

    qiScrollList.CanvasSize = UDim2.new(0, 0, 0, (#qiList * 36) + 10)
end

-- Discord Webhook Task
local HttpService = game:GetService("HttpService")
local sendRequest = request or http_request or (syn and syn.request)
local notified = setmetatable({}, {__mode = "k"})
local webhookRevision = 0
local retryAt = 0

webhookBox.FocusLost:Connect(function(enterPressed)
    if not enterPressed then return end
    local url = webhookBox.Text:match("^%s*(.-)%s*$")
    if url ~= "" and not url:match("^https://discord%.com/api/webhooks/%d+/[%w_-]+$")
        and not url:match("^https://discord%.com/api/v%d+/webhooks/%d+/[%w_-]+$") then
        webhookStatus.Text = "URL ไม่ถูกต้อง · ใช้ URL Webhook จาก Discord"
        return
    end
    if url ~= "" and type(sendRequest) ~= "function" then
        webhookStatus.Text = "ตัวรันนี้ไม่มีฟังก์ชันส่ง HTTP"
        return
    end
    HongmengConfig.DiscordWebhook = url
    HongmengConfig.DiscordNotify = url ~= ""
    webhookRevision = webhookRevision + 1
    table.clear(notified)
    retryAt = 0
    webhookStatus.Text = url == "" and "ปิดแจ้ง Discord แล้ว" or "เปิดแจ้งแล้ว · รอ Wild Qi เกรด 11–13"
end)

task.spawn(function()
    while not destroyed do
        if HongmengConfig.DiscordNotify and HongmengConfig.DiscordWebhook ~= "" and time() >= retryAt then
            if type(sendRequest) ~= "function" then
                warn("[Wild Qi] Discord requires an executor with an HTTP request function.")
                break
            end
            local batch, lines, included = {}, {}, {}
            for _, item in ipairs(scanAllWildQi()) do
                local grade = item.Grade
                local target = item.Target
                if (grade == 11 or grade == 12 or grade == 13)
                    and notified[target] ~= grade and not included[target] then
                    included[target] = true
                    table.insert(batch, {target = target, grade = grade})
                    local position = target.Position
                    table.insert(lines, string.format("Wild Qi Grade %d · (%.0f, %.0f, %.0f)",
                        grade, position.X, position.Y, position.Z))
                    if #batch >= 10 then break end
                end
            end
            if #batch > 0 then
                table.insert(lines, "Place ID: " .. tostring(game.PlaceId))
                table.insert(lines, "Server ID: " .. game.JobId)
                local revision = webhookRevision
                local url = HongmengConfig.DiscordWebhook
                url = url .. (string.find(url, "?", 1, true) and "&" or "?") .. "wait=true"
                local ok, response = pcall(sendRequest, {
                    Url = url,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = HttpService:JSONEncode({
                        content = table.concat(lines, "\n"),
                        allowed_mentions = {parse = {}}
                    })
                })
                if destroyed then return end
                if revision ~= webhookRevision then continue end
                local status = ok and type(response) == "table" and tonumber(response.StatusCode)
                if status and status >= 200 and status < 300 then
                    for _, entry in ipairs(batch) do
                        notified[entry.target] = entry.grade
                    end
                    retryAt = time() + 5
                    webhookStatus.Text = "ส่ง Discord สำเร็จ · " .. tostring(#batch) .. " จุด"
                else
                    local delay = 30
                    if status == 429 then
                        local decoded, body = pcall(HttpService.JSONDecode, HttpService, response.Body or "")
                        if decoded and type(body) == "table" then
                            delay = math.max(delay, tonumber(body.retry_after) or 0)
                        end
                    elseif status == 401 or status == 403 or status == 404 then
                        HongmengConfig.DiscordNotify = false
                        webhookStatus.Text = "Webhook ถูกปฏิเสธ · ใส่ URL ใหม่แล้ว Enter"
                    end
                    warn("[Wild Qi] Discord delivery failed; retrying later. HTTP " .. tostring(status))
                    retryAt = time() + delay
                    if HongmengConfig.DiscordNotify then
                        webhookStatus.Text = "ส่งไม่สำเร็จ · จะลองใหม่ใน " .. tostring(delay) .. " วินาที"
                    end
                end
            end
        end
        task.wait(5)
    end
end)

-- Hongmeng Rules & Remote
local hmRules = nil
pcall(function()
    local murim = ReplicatedStorage:FindFirstChild("Murim") or ReplicatedStorage:WaitForChild("Murim", 5)
    local shared = murim and (murim:FindFirstChild("Shared") or murim:WaitForChild("Shared", 5))
    hmRules = shared and require(shared:WaitForChild("Hongmeng", 5))
end)
local opposite = {U = "D", D = "U", L = "R", R = "L"}
local wardWindowStart = (hmRules and hmRules.Trib and hmRules.Trib.window and hmRules.Trib.window[1]) or -0.15
local wardWindowEnd = (hmRules and hmRules.Trib and hmRules.Trib.window and hmRules.Trib.window[2]) or 0.15
local wardCooldown = (hmRules and hmRules.Trib and hmRules.Trib.wardCooldown) or 0.5
local wardTargetOffset = (wardWindowStart + wardWindowEnd) / 2
local hmPhase, hmWeave, hmSeq
local hmBolts = {}
local hmPos, hmSentPos = 1, 0
local hmLastSeal, hmLastWard = -math.huge, -math.huge
local hmInWindow = false
local lastWarpTime = 0
local wardStatus = "รอสัญญาณ bolt"
local wardSent, wardMissed = 0, 0

local function resetHongmeng(nextPhase)
    hmPhase, hmWeave, hmSeq = nextPhase, nil, nil
    table.clear(hmBolts)
    hmInWindow = false
    hmLastSeal, hmLastWard = -math.huge, -math.huge
    wardSent, wardMissed = 0, 0
    wardStatus = "รอสัญญาณ bolt"
end

local function receiveHongmeng(msg)
    if type(msg) ~= "table" then return end
    local op = msg.op
    if op == "start" then
        resetHongmeng("gather")
    elseif op == "result" or op == "seat" then
        resetHongmeng(nil)
    elseif op == "phase" and msg.phase ~= hmPhase then
        resetHongmeng(msg.phase)
    elseif op == "weave" then
        hmWeave, hmPhase = msg, "weave"
    elseif op == "weaveEnd" then
        hmWeave = nil
    elseif op == "seq" then
        hmSeq, hmPhase, hmPos, hmSentPos = msg, "hold", 1, 0
    elseif op == "seqKey" and hmSeq and type(msg.pos) == "number" then
        hmPos = math.max(hmPos, msg.pos + 1)
    elseif op == "seqDone" then
        hmSeq = nil
    elseif op == "warded" then
        wardStatus = "เกมยืนยันป้องกันสำเร็จ"
    elseif op == "unwarded" then
        wardMissed = wardMissed + 1
        wardStatus = "เกมแจ้งว่าป้องกันพลาด"
    elseif op == "trib" then
        hmPhase = "trib"
    elseif op == "bolt" and type(msg.land) == "number" then
        hmPhase = "trib"
        table.insert(hmBolts, msg.land)
        table.sort(hmBolts)
    end
end

local boundHongmengRemote = nil
local function bindHongmengRemote()
    local murim = ReplicatedStorage:FindFirstChild("Murim")
    local remotes = murim and murim:FindFirstChild("Remotes")
    local remote = remotes and remotes:FindFirstChild("Hongmeng")
    if remote == boundHongmengRemote then return end
    resetHongmeng(nil)
    boundHongmengRemote = remote
    if boundHongmengRemote and boundHongmengRemote:IsA("RemoteEvent") then
        externalConnections[#externalConnections + 1] = boundHongmengRemote.OnClientEvent:Connect(receiveHongmeng)
    end
end
bindHongmengRemote()
local remotesFolder = ReplicatedStorage:FindFirstChild("Murim") and ReplicatedStorage.Murim:FindFirstChild("Remotes")
if remotesFolder then
    externalConnections[#externalConnections + 1] = remotesFolder.ChildAdded:Connect(bindHongmengRemote)
    externalConnections[#externalConnections + 1] = remotesFolder.ChildRemoved:Connect(bindHongmengRemote)
end

local function gateDistance(angle)
    return math.abs((angle + 180) % 360 - 180)
end

local function setHongmengEnabled(enabled)
    HongmengConfig.Enabled = enabled
    if HongmengConfig.Enabled then
        toggleHBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 60)
        toggleHBtn.Text = "AUTO HONGMENG: ON"
        statusHLabel.Text = "สถานะ: กำลังตรวจจับค่ายกลและยิง Remote..."
    else
        toggleHBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
        toggleHBtn.Text = "AUTO HONGMENG: OFF"
        statusHLabel.Text = "สถานะ: ปิดการทำงาน"
    end
end

toggleHBtn.Activated:Connect(function()
    setHongmengEnabled(not HongmengConfig.Enabled)
end)

searchHBtn.Activated:Connect(function()
    setHongmengEnabled(true)
end)

autoWarpQiBtn.MouseButton1Click:Connect(function()
    HongmengConfig.AutoTeleportWildQi = not HongmengConfig.AutoTeleportWildQi
    autoWarpQiBtn.BackgroundColor3 = HongmengConfig.AutoTeleportWildQi and Color3.fromRGB(40, 160, 60) or Color3.fromRGB(160, 40, 40)
    autoWarpQiBtn.Text = HongmengConfig.AutoTeleportWildQi and "AUTO BEST: ON" or "AUTO BEST: OFF"
end)

refreshQiBtn.MouseButton1Click:Connect(function()
    refreshQiButtons()
end)

-- Murim_WildQi folder listeners
task.spawn(function()
    local wildQiFolder = Workspace:WaitForChild("Murim_WildQi", 10)
    if wildQiFolder and not destroyed then
        externalConnections[#externalConnections + 1] = wildQiFolder.DescendantAdded:Connect(function(desc)
            if desc.Name == "WildQi" or (desc:IsA("BasePart") and desc.Name == "QiSpot") then
                task.defer(refreshQiButtons)
            end
        end)
        externalConnections[#externalConnections + 1] = wildQiFolder.DescendantRemoving:Connect(function(desc)
            if desc.Name == "WildQi" or (desc:IsA("BasePart") and desc.Name == "QiSpot") then
                task.defer(refreshQiButtons)
            end
        end)
    end
end)

-- Heartbeat loop for Hongmeng Solver and Auto Best Qi Teleport
externalConnections[#externalConnections + 1] = RunService.Heartbeat:Connect(function()
    if destroyed then return end
    local now = tick()

    -- 1. Auto Teleport หาจุด Wild Qi
    if HongmengConfig.AutoTeleportWildQi and (now - lastWarpTime >= 1.5) then
        lastWarpTime = now
        local qiList = scanAllWildQi()
        if qiList[1] and qiList[1].Target then
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local targetCFrame = qiList[1].Target:IsA("Model") and qiList[1].Target:GetPivot() or qiList[1].Target.CFrame
                char.HumanoidRootPart.CFrame = targetCFrame + Vector3.new(0, 3, 0)
            end
        end
    end

    if not HongmengConfig.Enabled then return end
    if not boundHongmengRemote or not boundHongmengRemote:IsA("RemoteEvent") then
        if statusHLabel.Text ~= "รอ Remote Hongmeng" then
            statusHLabel.Text = "รอ Remote Hongmeng"
        end
        return
    end
    local t = Workspace:GetServerTimeNow()
    local newHText = hmPhase and ("เฟส " .. hmPhase) or "รอข้อมูลพิธีจากเกม"
    if statusHLabel.Text ~= newHText then
        statusHLabel.Text = newHText
    end
    if hmPhase == "weave" and hmWeave and t < hmWeave.ends then
        local ring = hmWeave.rings[hmWeave.active]
        if not ring then return end
        local chaos = hmWeave.chaos
        local runeAngle = ring.base + ring.w * (t - ring.tBase) + ring.key
        local darkAngle = chaos.base + chaos.w * (t - chaos.tBase)
        local ready = gateDistance(runeAngle) <= 4 and gateDistance(darkAngle) > chaos.width / 2
        if ready and not hmInWindow and t - hmLastSeal >= 0.22 then
            boundHongmengRemote:FireServer({op = "seal", t = t})
            hmLastSeal, hmInWindow = t, true
        elseif not ready then
            hmInWindow = false
        end
    elseif hmPhase == "hold" and hmSeq and t < hmSeq.deadline and hmPos ~= hmSentPos then
        local key = hmSeq.keys[hmPos]
        if opposite[key] then
            local dir = hmSeq.inv[hmPos] and opposite[key] or key
            boundHongmengRemote:FireServer({op = "key", dir = dir})
            hmSentPos = hmPos
        end
    elseif hmPhase == "trib" then
        while hmBolts[1] and t > hmBolts[1] + wardWindowEnd do
            table.remove(hmBolts, 1)
            wardStatus = "พลาดเวลาส่ง · ข้อมูลมาช้าหรือคูลดาวน์"
        end
        if hmBolts[1] then
            local remaining = hmBolts[1] + wardTargetOffset - t
            if remaining <= 0 then
                local cooldown = wardCooldown
                if t - hmLastWard >= cooldown then
                    boundHongmengRemote:FireServer({op = "ward", t = t})
                    hmLastWard = t
                    wardSent = wardSent + 1
                    table.remove(hmBolts, 1)
                    wardStatus = "ส่ง ward แล้ว · รอผลจากเกม"
                else
                    wardStatus = "รอคูลดาวน์"
                end
            else
                wardStatus = string.format("ส่ง ward ใน %.2f วินาที", remaining)
            end
        end
        statusHLabel.Text = string.format("Trib · ส่ง %d · พลาด %d\n%s", wardSent, wardMissed, wardStatus)
    end
end)

do
    local halloweenPage = makePage("Halloween", 8, "🎃 ฮาโลวีน")
    newHeading(halloweenPage, "🎃 The Hungry Ghost Gate • Auto Raid (ครบ 10 ห้อง)")
    local hallowBody = Instance.new("ScrollingFrame")
    hallowBody.Name = "HalloweenContent"
    hallowBody.Position = UDim2.new(0, 0, 0, 44)
    hallowBody.Size = UDim2.new(1, 0, 1, -56)
    hallowBody.BackgroundTransparency = 1
    hallowBody.BorderSizePixel = 0
    hallowBody.ScrollBarThickness = 4
    hallowBody.CanvasSize = UDim2.new(0, 0, 0, 470)
    hallowBody.Parent = halloweenPage

    toggleHallowRaidBtn = Instance.new("TextButton")
    toggleHallowRaidBtn.Name = "ToggleHallowRaidBtn"
    toggleHallowRaidBtn.Font = Enum.Font.SourceSansBold
    toggleHallowRaidBtn.TextSize = 13
    toggleHallowRaidBtn.TextColor3 = Color3.new(1, 1, 1)
    toggleHallowRaidBtn.Text = "🎃 ออโต้ผ่านด่าน Hungry Ghost Gate (Auto: OFF)"
    toggleHallowRaidBtn.BackgroundColor3 = Color3.fromRGB(150, 45, 60)
    Instance.new("UICorner", toggleHallowRaidBtn).CornerRadius = UDim.new(0, 6)
    placeButton(toggleHallowRaidBtn, hallowBody, 0, 12, 12, 1, -24)

    local diffHeader = Instance.new("TextLabel")
    diffHeader.Text = "🎯 เลือกระดับความยาก (Difficulty):"
    diffHeader.Font = Enum.Font.SourceSansBold
    diffHeader.TextSize = 13
    diffHeader.TextColor3 = Color3.fromRGB(240, 240, 240)
    diffHeader.BackgroundTransparency = 1
    diffHeader.TextXAlignment = Enum.TextXAlignment.Left
    diffHeader.Parent = hallowBody
    diffHeader.Position = UDim2.new(0, 12, 0, 54)
    diffHeader.Size = UDim2.new(1, -24, 0, 20)

    local diffNormalBtn = Instance.new("TextButton")
    local diffHardBtn = Instance.new("TextButton")
    local diffHardcoreBtn = Instance.new("TextButton")

    local function updateDiffButtons()
        diffNormalBtn.BackgroundColor3 = (hallowDifficulty == "Normal") and Color3.fromRGB(60, 100, 200) or Color3.fromRGB(45, 45, 60)
        diffHardBtn.BackgroundColor3 = (hallowDifficulty == "Hard") and Color3.fromRGB(60, 100, 200) or Color3.fromRGB(45, 45, 60)
        diffHardcoreBtn.BackgroundColor3 = (hallowDifficulty == "Hardcore") and Color3.fromRGB(60, 100, 200) or Color3.fromRGB(45, 45, 60)
    end

    diffNormalBtn.Text = "Normal"
    diffNormalBtn.Font = Enum.Font.SourceSansBold
    diffNormalBtn.TextSize = 12
    diffNormalBtn.TextColor3 = Color3.new(1, 1, 1)
    Instance.new("UICorner", diffNormalBtn).CornerRadius = UDim.new(0, 6)
    placeButton(diffNormalBtn, hallowBody, 0, 12, 78, 0.31, -8)

    diffHardBtn.Text = "Hard"
    diffHardBtn.Font = Enum.Font.SourceSansBold
    diffHardBtn.TextSize = 12
    diffHardBtn.TextColor3 = Color3.new(1, 1, 1)
    Instance.new("UICorner", diffHardBtn).CornerRadius = UDim.new(0, 6)
    placeButton(diffHardBtn, hallowBody, 0.33, 4, 78, 0.31, -8)

    diffHardcoreBtn.Text = "Hardcore"
    diffHardcoreBtn.Font = Enum.Font.SourceSansBold
    diffHardcoreBtn.TextSize = 12
    diffHardcoreBtn.TextColor3 = Color3.new(1, 1, 1)
    Instance.new("UICorner", diffHardcoreBtn).CornerRadius = UDim.new(0, 6)
    placeButton(diffHardcoreBtn, hallowBody, 0.66, -4, 78, 0.34, -8)

    diffNormalBtn.MouseButton1Click:Connect(function() hallowDifficulty = "Normal"; updateDiffButtons() end)
    diffHardBtn.MouseButton1Click:Connect(function() hallowDifficulty = "Hard"; updateDiffButtons() end)
    diffHardcoreBtn.MouseButton1Click:Connect(function() hallowDifficulty = "Hardcore"; updateDiffButtons() end)
    updateDiffButtons()

    local toggleRepeatBtn = Instance.new("TextButton")
    toggleRepeatBtn.Font = Enum.Font.SourceSansBold
    toggleRepeatBtn.TextSize = 12
    toggleRepeatBtn.TextColor3 = Color3.new(1, 1, 1)
    toggleRepeatBtn.Text = isHallowAutoRepeat and "🔄 ลงซ้ำอัตโนมัติเมื่อจบด่าน: เปิด (ON)" or "🔄 ลงซ้ำอัตโนมัติเมื่อจบด่าน: ปิด (OFF)"
    toggleRepeatBtn.BackgroundColor3 = isHallowAutoRepeat and Color3.fromRGB(35, 140, 75) or Color3.fromRGB(90, 60, 110)
    Instance.new("UICorner", toggleRepeatBtn).CornerRadius = UDim.new(0, 6)
    placeButton(toggleRepeatBtn, hallowBody, 0, 12, 118, 1, -24)

    toggleRepeatBtn.MouseButton1Click:Connect(function()
        isHallowAutoRepeat = not isHallowAutoRepeat
        toggleRepeatBtn.Text = isHallowAutoRepeat and "🔄 ลงซ้ำอัตโนมัติเมื่อจบด่าน: เปิด (ON)" or "🔄 ลงซ้ำอัตโนมัติเมื่อจบด่าน: ปิด (OFF)"
        toggleRepeatBtn.BackgroundColor3 = isHallowAutoRepeat and Color3.fromRGB(35, 140, 75) or Color3.fromRGB(90, 60, 110)
    end)

    local toggleSeenBtn = Instance.new("TextButton")
    toggleSeenBtn.Font = Enum.Font.SourceSansBold
    toggleSeenBtn.TextSize = 12
    toggleSeenBtn.TextColor3 = Color3.new(1, 1, 1)
    toggleSeenBtn.Text = "👁️ สยบผีอัตโนมัติ (Auto Pacify / Seen: ON)"
    toggleSeenBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 140)
    Instance.new("UICorner", toggleSeenBtn).CornerRadius = UDim.new(0, 6)
    placeButton(toggleSeenBtn, hallowBody, 0, 12, 156, 1, -24)

    toggleSeenBtn.MouseButton1Click:Connect(function()
        isHallowPacifySeen = not isHallowPacifySeen
        toggleSeenBtn.Text = isHallowPacifySeen and "👁️ สยบผีอัตโนมัติ (Auto Pacify / Seen: ON)" or "👁️ สยบผีอัตโนมัติ (Auto Pacify / Seen: OFF)"
        toggleSeenBtn.BackgroundColor3 = isHallowPacifySeen and Color3.fromRGB(40, 80, 140) or Color3.fromRGB(90, 60, 110)
    end)

    local tpLedgerBtn = Instance.new("TextButton")
    tpLedgerBtn.Font = Enum.Font.SourceSansBold
    tpLedgerBtn.TextSize = 12
    tpLedgerBtn.TextColor3 = Color3.new(1, 1, 1)
    tpLedgerBtn.Text = "⚡ วาร์ปไปแท่นสมุดลงชื่อ (Guest Ledger)"
    tpLedgerBtn.BackgroundColor3 = Color3.fromRGB(110, 50, 140)
    Instance.new("UICorner", tpLedgerBtn).CornerRadius = UDim.new(0, 6)
    placeButton(tpLedgerBtn, hallowBody, 0, 12, 194, 1, -24)

    tpLedgerBtn.MouseButton1Click:Connect(function()
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local prompt, part = findGuestLedger()
            if part then
                hrp.CFrame = part.CFrame * CFrame.new(0, 2, -4) * CFrame.Angles(0, math.rad(180), 0)
            else
                hrp.CFrame = HALLOW_GATE_CFRAME
            end
        end
    end)

    hallowStatusLabel = Instance.new("TextLabel")
    hallowStatusLabel.Font = Enum.Font.SourceSansBold
    hallowStatusLabel.TextSize = 12
    hallowStatusLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
    hallowStatusLabel.BackgroundColor3 = Color3.fromRGB(20, 25, 35)
    hallowStatusLabel.BorderSizePixel = 0
    hallowStatusLabel.TextWrapped = true
    hallowStatusLabel.Text = "💤 ระบบออโต้ด่านฮาโลวีนปิดอยู่"
    Instance.new("UICorner", hallowStatusLabel).CornerRadius = UDim.new(0, 6)
    placeButton(hallowStatusLabel, hallowBody, 0, 12, 234, 1, -24)
    hallowStatusLabel.Size = UDim2.new(1, -24, 0, 40)

    local infoLabel = Instance.new("TextLabel")
    infoLabel.Font = Enum.Font.SourceSans
    infoLabel.TextSize = 11
    infoLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    infoLabel.BackgroundTransparency = 1
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextYAlignment = Enum.TextYAlignment.Top
    infoLabel.TextWrapped = true
    infoLabel.Text = "📌 ข้อมูลการทำงาน (ห้อง 1 - 5):\n• ห้อง 1: เดินไปหน้าประตูรอประตูเปิด -> ไม่ตีมอน วาร์ปเข้าห้อง 2 ทันที\n• ห้อง 2: เปิดโลงศพเรื่อยๆ จนเจอกุญแจ (Key) เพื่อเปิดประตูห้อง 3\n• ห้อง 3: กำจัด Paper Effigies จนประตูเปิด -> ผ่านประตูไปตี Boss Paper Tailor\n• ห้อง 4: วาร์ปจุดไฟ/ตะเกียงให้ครบทุกจุด (หลบตัวอมตะ) -> ประตูห้อง 5 เปิด\n• ห้อง 5: โรงน้ำชา (ผ่านเข้าห้อง 6)\n• ห้อง 6: กำจัดมินิบอส Cerberus Jiangshi [Lv.90]\n• ห้อง 7-8: ดิ่งบ่อน้ำ The Throat & ผ่านงานเลี้ยงผีหิว\n• ห้อง 9: กำจัดบอสใหญ่ Hungry Ghost Matriarch [Lv.110]\n• ห้อง 10: รับของรางวัลที่กองผ้าและจบด่าน"
    infoLabel.Position = UDim2.new(0, 12, 0, 284)
    infoLabel.Size = UDim2.new(1, -24, 0, 120)
    infoLabel.Parent = hallowBody

    toggleHallowRaidBtn.MouseButton1Click:Connect(function()
        isAutoHallowRaid = not isAutoHallowRaid
        if isAutoHallowRaid then
            currentRaidRoomIndex = 1
            roomEnterTime = 0
            room3Phase = 1
            immortalEffigies = {}
            effigyHpSnapshot = {}
            toggleHallowRaidBtn.Text = "🎃 ออโต้ผ่านด่าน Hungry Ghost Gate (Auto: ON)"
            toggleHallowRaidBtn.BackgroundColor3 = Color3.fromRGB(35, 140, 75)
            hallowStatusLabel.Text = "🚀 เริ่มต้นระบบ Auto Hungry Ghost Gate (ห้อง 1-5)..."
        else
            currentRaidRoomIndex = 1
            toggleHallowRaidBtn.Text = "🎃 ออโต้ผ่านด่าน Hungry Ghost Gate (Auto: OFF)"
            toggleHallowRaidBtn.BackgroundColor3 = Color3.fromRGB(150, 45, 60)
            hallowStatusLabel.Text = "💤 ปิดระบบ Auto Hungry Ghost Gate แล้ว"
        end
    end)
end

local settingsPage = makePage("Settings", 9, "ตั้งค่า")
newHeading(settingsPage, "ตั้งค่าการฟาร์ม")
local settingsBody = Instance.new("ScrollingFrame")
settingsBody.Name = "SettingsContent"
settingsBody.Position = UDim2.new(0, 0, 0, 44)
settingsBody.Size = UDim2.new(1, 0, 1, -56)
settingsBody.BackgroundTransparency = 1
settingsBody.BorderSizePixel = 0
settingsBody.ScrollBarThickness = 4
settingsBody.CanvasSize = UDim2.new(0, 0, 0, 430)
settingsBody.Parent = settingsPage
distLabel.Parent = settingsBody
distLabel.Position = UDim2.new(0, 12, 0, 0)
distLabel.Size = UDim2.new(1, -24, 0, 28)
distLabel.TextXAlignment = Enum.TextXAlignment.Left
distLabel.TextSize = 14
placeButton(addDistBtn, settingsBody, 0, 12, 36, 0.5, -16)
placeButton(subDistBtn, settingsBody, 0.5, 4, 36, 0.5, -16)
placeButton(toggleHitboxBtn, settingsBody, 0, 12, 84, 1, -24)
placeButton(toggleLootBtn, settingsBody, 0, 12, 132, 1, -24)

local toggleLootFilterBtn = Instance.new("TextButton")
toggleLootFilterBtn.Name = "LootFilterToggle"
toggleLootFilterBtn.Font = Enum.Font.SourceSansBold
toggleLootFilterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleLootFilterBtn.TextSize = 13
Instance.new("UICorner", toggleLootFilterBtn).CornerRadius = UDim.new(0, 6)
placeButton(toggleLootFilterBtn, settingsBody, 0, 12, 180, 1, -24)
local function displayLootFilter()
    local opt = LOOT_FILTER_OPTIONS[currentLootFilterIdx]
    toggleLootFilterBtn.Text = "🎁 กรองไอเทม: " .. (opt and opt.text or "ทั้งหมด (All)")
    toggleLootFilterBtn.BackgroundColor3 = currentLootFilterIdx > 1 and Color3.fromRGB(40, 140, 80) or Color3.fromRGB(90, 60, 110)
end
toggleLootFilterBtn.MouseButton1Click:Connect(function()
    currentLootFilterIdx = (currentLootFilterIdx % #LOOT_FILTER_OPTIONS) + 1
    displayLootFilter()
end)
displayLootFilter()

local toggleParryBtn = Instance.new("TextButton")
toggleParryBtn.Name = "AutoParryToggle"
toggleParryBtn.Font = Enum.Font.SourceSansBold
toggleParryBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", toggleParryBtn).CornerRadius = UDim.new(0, 6)
placeButton(toggleParryBtn, settingsBody, 0, 12, 228, 1, -24)
local function displayParry()
    toggleParryBtn.Text = isAutoParry and "🛡️ ป้องกันอัตโนมัติ (Auto Parry: ON)" or "🛡️ ป้องกันอัตโนมัติ (Auto Parry: OFF)"
    toggleParryBtn.BackgroundColor3 = isAutoParry and Color3.fromRGB(40, 110, 150) or Color3.fromRGB(90, 60, 110)
end
toggleParryBtn.MouseButton1Click:Connect(function()
    isAutoParry = not isAutoParry
    if not isAutoParry and isParrying then
        combatRemote = combatRemote or findCombatRemote()
        if combatRemote then pcall(function() combatRemote:FireServer("ParryUp", nil) end) end
        isParrying = false
    end
    displayParry()
end)
displayParry()

local toggleArtifactBtn = Instance.new("TextButton")
toggleArtifactBtn.Name = "AutoArtifactToggle"
toggleArtifactBtn.Font = Enum.Font.SourceSansBold
toggleArtifactBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", toggleArtifactBtn).CornerRadius = UDim.new(0, 6)
placeButton(toggleArtifactBtn, settingsBody, 0, 12, 276, 1, -24)
local function displayArtifact()
    toggleArtifactBtn.Text = isAutoArtifact and "📿 ใช้อาวุธวิเศษ (Auto Artifact: ON)" or "📿 ใช้อาวุธวิเศษ (Auto Artifact: OFF)"
    toggleArtifactBtn.BackgroundColor3 = isAutoArtifact and Color3.fromRGB(40, 110, 150) or Color3.fromRGB(90, 60, 110)
end
toggleArtifactBtn.MouseButton1Click:Connect(function()
    isAutoArtifact = not isAutoArtifact
    displayArtifact()
end)
displayArtifact()

-- Anti-idle input approach adapted from Infinite Yield's antiafk command:
-- https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source
-- Keep other scripts' Idled connections intact; own connection is cleaned up by cleanup().
local antiAFKEnabled = true
local antiAFKButton = Instance.new("TextButton")
antiAFKButton.Name = "AntiAFKToggle"
antiAFKButton.Font = Enum.Font.SourceSansBold
antiAFKButton.TextColor3 = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", antiAFKButton).CornerRadius = UDim.new(0, 6)
placeButton(antiAFKButton, settingsBody, 0, 12, 324, 1, -24)
local function displayAntiAFK()
    antiAFKButton.Text = antiAFKEnabled and "ป้องกัน AFK (Anti-AFK: ON)" or "ป้องกัน AFK (Anti-AFK: OFF)"
    antiAFKButton.BackgroundColor3 = antiAFKEnabled and Color3.fromRGB(40, 110, 150) or Color3.fromRGB(90, 60, 110)
end
antiAFKButton.MouseButton1Click:Connect(function()
    antiAFKEnabled = not antiAFKEnabled
    displayAntiAFK()
end)
displayAntiAFK()
externalConnections[#externalConnections + 1] = player.Idled:Connect(function()
    if destroyed or not antiAFKEnabled or (hubUI.isBusy and hubUI.isBusy()) then return end
    -- No polling loop; send a press/release only when Roblox reports idle.
    local ok, message = pcall(function()
        for _, pressed in ipairs({true, false}) do
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, pressed, game, 0)
        end
    end)
    if not ok then
        -- Attempt release even if the initial input failed.
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
        antiAFKEnabled = false
        displayAntiAFK()
        antiAFKButton.Text = "Anti-AFK: ตัวรันไม่อนุญาตให้ส่งอินพุต"
        warn("[Murim Anti-AFK] " .. tostring(message))
    end
end)
placeButton(destroyBtn, settingsBody, 0, 12, 372, 1, -24)

-- Keep Start/Stop accessible from every page.
local footer = Instance.new("Frame")
footer.Name = "PersistentControls"
footer.Position = UDim2.new(0, 12, 1, -50)
footer.Size = UDim2.new(1, -24, 0, 38)
footer.BackgroundTransparency = 1
footer.Parent = mainFrame
placeButton(startBtn, footer, 0, 0, 0, 0.5, -4)
placeButton(stopBtn, footer, 0.5, 4, 0, 0.5, -4)
hubUI.makePage = makePage
hubUI.showPage = showPage
hubUI.settingsBody = settingsBody
showPage(1)
end


local function restoreHitboxes()
    for part, props in pairs(originalHitboxes) do
        if part.Parent then
            pcall(function()
                part.Size = props.Size
                part.Transparency = props.Transparency
                part.CanCollide = props.CanCollide
                part.Material = props.Material
            end)
        end
        originalHitboxes[part] = nil
    end
end


local function applyHitboxToNPC(npc)
	if not isHitboxExpanded or not npc or not npc:IsA("Model") or isFriendlyOrTalkable(npc) then return end

    if checkIsBossName(npc.Name) then
        revealInvisibleNPC(npc)
    end

	local hrp = getNPCRootPart(npc)
	if hrp then
        if hrp.Size == HITBOX_SIZE and hrp.Transparency == HITBOX_TRANSPARENCY and hrp.CanCollide == false then
            return
        end
		pcall(function()
			if not originalHitboxes[hrp] then
                originalHitboxes[hrp] = {
                    Size = hrp.Size, Transparency = hrp.Transparency,
                    CanCollide = hrp.CanCollide, Material = hrp.Material,
                }
            end
            hrp.Size = HITBOX_SIZE
			hrp.Transparency = HITBOX_TRANSPARENCY
			hrp.CanCollide = false
			hrp.Material = Enum.Material.ForceField
		end)
	end
end

local function updateAllHitboxes()
	local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")
	if not npcsFolder then return end

	for _, npc in ipairs(npcsFolder:GetChildren()) do
		applyHitboxToNPC(npc)
	end
end

local function interactWithDrop(dropItem)
	if not dropItem or not dropItem.Parent then return end

	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end
	local hrp = character.HumanoidRootPart

	local targetPart = dropItem:IsA("BasePart") and dropItem or (dropItem:IsA("Model") and dropItem.PrimaryPart) or dropItem:FindFirstChildWhichIsA("BasePart", true)
	if not targetPart then return end

	hrp.CFrame = targetPart.CFrame * CFrame.new(0, 2, 0)
	task.wait(0.05)
    if destroyed or not isFarming or not dropItem.Parent or (hubUI.isBusy and hubUI.isBusy()) then return end

    if typeof(firetouchinterest) == "function" then
        pcall(function()
            firetouchinterest(hrp, targetPart, 0)
            task.wait(0.01)
            firetouchinterest(hrp, targetPart, 1)
        end)
    end

    local descendants = dropItem:GetDescendants()
    local hadPrompt = false
	for _, desc in ipairs(descendants) do
        if destroyed or not isFarming or (hubUI.isBusy and hubUI.isBusy()) then return end
		if desc:IsA("TouchTransmitter") or desc.Name == "TouchInterest" then
			if typeof(firetouchinterest) == "function" then
				pcall(function()
					firetouchinterest(hrp, desc.Parent, 0)
					task.wait(0.01)
					firetouchinterest(hrp, desc.Parent, 1)
				end)
			end
		elseif desc:IsA("ProximityPrompt") and desc.Enabled then
            hadPrompt = true
			if typeof(fireproximityprompt) == "function" then
				pcall(function() fireproximityprompt(desc) end)
			elseif VirtualInputManager then
				local holdTime = desc.HoldDuration or 0
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
				task.wait(holdTime + 0.1)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
			end
			task.wait(0.1)
		end
	end

    if isChest(dropItem) then
        chestAttempts[dropItem] = (chestAttempts[dropItem] or 0) + 1
        if not hadPrompt or chestAttempts[dropItem] >= 4 then
            openedChests[dropItem] = os.clock() + 20
        else
            openedChests[dropItem] = os.clock() + 1.2
        end
    end
end

local function findBossInNPCs(key, data)
    local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")
    if not npcsFolder then return nil end
    local targetName = (data.Name or key):lower()
    local keyLower = key:lower()

    -- 1. Check exact or substring match
    for _, npc in ipairs(npcsFolder:GetChildren()) do
        if isAlive(npc) then
            local nName = npc.Name:lower()
            if nName == targetName or nName:find(targetName, 1, true) or targetName:find(nName, 1, true)
               or nName:find(keyLower, 1, true) or keyLower:find(nName, 1, true) then
                return npc
            end
        end
    end

    -- 2. Check aliases from KNOWN_BOSSES
    for _, info in ipairs(KNOWN_BOSSES) do
        if info.Key == key or info.Name == key or (data and (info.Key == data.Name or info.Name == data.Name)) then
            for _, alias in ipairs(info.Alias or {}) do
                local aLow = alias:lower()
                for _, npc in ipairs(npcsFolder:GetChildren()) do
                    if isAlive(npc) and npc.Name:lower():find(aLow, 1, true) then
                        return npc
                    end
                end
            end
        end
    end

    -- 2. Word token match (e.g. "White-Jade Dragon" matches "White-Jade" or "Dragon")
    local words = {}
    for w in targetName:gmatch("[%a%d]+") do
        if #w >= 3 and w ~= "the" and w ~= "boss" then
            table.insert(words, w)
        end
    end
    for w in keyLower:gmatch("[%a%d]+") do
        if #w >= 3 and w ~= "the" and w ~= "boss" then
            table.insert(words, w)
        end
    end

    if #words > 0 then
        for _, npc in ipairs(npcsFolder:GetChildren()) do
            if isAlive(npc) then
                local nName = npc.Name:lower()
                for _, word in ipairs(words) do
                    if nName:find(word, 1, true) then
                        return npc
                    end
                end
            end
        end
    end

    return nil
end

local function getBossChest()
    local searchContainers = {}
    local dropsFolder = Workspace:FindFirstChild("Murim_Drops")
    if dropsFolder then searchContainers[#searchContainers + 1] = dropsFolder end
    for _, name in ipairs({"Murim_Chests", "Chests", "Drops", "Debris"}) do
        local f = Workspace:FindFirstChild(name)
        if f then searchContainers[#searchContainers + 1] = f end
    end
    searchContainers[#searchContainers + 1] = Workspace

    local bossDeathPos = lastBossCFrame and lastBossCFrame.Position

    for _, container in ipairs(searchContainers) do
        for _, obj in ipairs(container:GetChildren()) do
            if obj and obj.Parent then
                local objName = obj.Name
                local isBossNamed = (objName == "LootChest_Boss")
                    or (objName:find("LootChest_Boss", 1, true) ~= nil)
                    or (objName:find("BossChest", 1, true) ~= nil)
                    or (objName:find("LootChest", 1, true) ~= nil and objName:find("Boss", 1, true) ~= nil)
                    or (objName:find("Chest", 1, true) ~= nil and objName:find("Boss", 1, true) ~= nil)

                local part = obj:IsA("BasePart") and obj
                    or (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)))

                local isNearBoss = false
                if part and bossDeathPos and isChest(obj) then
                    local dist = (part.Position - bossDeathPos).Magnitude
                    if dist <= 120 then
                        isNearBoss = true
                    end
                end

                if (isBossNamed or isNearBoss) and part then
                    local cooldown = openedChests[obj]
                    if not cooldown or os.clock() >= cooldown then
                        local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                        return obj, part, prompt
                    end
                end
            end
        end
    end
    return nil, nil, nil
end

local activeBossProbeCount = 0
local function chooseBossTarget()
    if not isAutoFarmBoss then return nil, false, nil end
    local now = os.clock()

    -- Check if we currently have an active boss
    if activeBossTarget then
        local data = bossCache[activeBossTarget.Key]
        if data and selectedBossNames[activeBossTarget.Key] then
            local npc = findBossInNPCs(activeBossTarget.Key, data)
            if npc and isAlive(npc) then
                revealInvisibleNPC(npc)
                local part = getNPCRootPart(npc)
                if part then
                    lastBossCFrame = part.CFrame
                    return part.CFrame, true, npc
                end
            end
        end
        -- Boss died or despawned!
        if lastBossCFrame then
            bossLootWaitUntil = os.clock() + 6.0
        end
        activeBossTarget = nil
        cachedTarget = nil
        targetScanAt = 0
        activeBossProbeCount = 0
    end

    -- Find any selected boss that is spawned
    for key, isSelected in pairs(selectedBossNames) do
        if isSelected then
            local data = bossCache[key]
            if data and data.TimeText and data.TimeText:find("เกิดแล้ว") then
                local probeTime = bossProbeAt[key] or 0
                if now >= probeTime then
                    local npc = findBossInNPCs(key, data)
                    if npc and isAlive(npc) then
                        revealInvisibleNPC(npc)
                        activeBossTarget = { Key = key, NPC = npc, Name = data.Name }
                        activeBossProbeCount = 0
                        local part = getNPCRootPart(npc)
                        if part then
                            return part.CFrame, true, npc
                        end
                    elseif data.CFrame then
                        return data.CFrame, false, nil
                    end
                end
            end
        end
    end

    return nil, false, nil
end

local function getHighestLevelTarget()
    local now = os.clock()
    if now < targetScanAt then
        if cachedTarget and isAlive(cachedTarget) and getNPCLevel(cachedTarget) > 0 then
            local part = getNPCRootPart(cachedTarget)
            return part.CFrame, true, cachedTarget
        elseif not cachedTarget then
            return nil, false, nil
        end
    end
    targetScanAt = now + TARGET_SCAN_INTERVAL
	local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")
	local highestLevel = 0
	local bestCFrame = nil
	local bestNPCObj = nil
    local bestIsFavorite = false

	local hasSelection = false
	for _, isSelected in pairs(selectedNPCNames) do
		if isSelected then hasSelection = true break end
	end

    -- If user is running Auto Farm Boss and did not select any regular monsters,
    -- do not randomly attack NPCs when the boss is dead! Wait for the next boss.
    if isAutoFarmBoss and not hasSelection then
        cachedTarget = nil
        return nil, false, nil
    end

	if npcsFolder then
		for _, npc in ipairs(npcsFolder:GetChildren()) do
            local level = getNPCLevel(npc)
			if level > 0 and (favoriteNPCNames[npc.Name] or not hasSelection or selectedNPCNames[npc.Name]) and isAlive(npc) then
				local isFavorite = favoriteNPCNames[npc.Name] == true
				local targetPart = getNPCRootPart(npc)
				
				if targetPart then
					if (isFavorite and not bestIsFavorite) or (isFavorite == bestIsFavorite and level > highestLevel) then
                        bestIsFavorite = isFavorite
						highestLevel = level
						bestCFrame = targetPart.CFrame
						bestNPCObj = npc
					end
				end
			end
		end
	end

	cachedTarget = bestNPCObj
	if bestCFrame then
		return bestCFrame, true, bestNPCObj
	end
	return nil, false, nil
end

local function refreshTPButtons()
    local signature = listSignature(savedNPCPositions, knownNPCNames)
    if signature == tpSignature then return end
    tpSignature = signature
	for _, child in ipairs(tpScrollFrame:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end

	local sortedList = {}
	for npcName, cf in pairs(savedNPCPositions) do
		local level = knownNPCNames[npcName] or 0
		table.insert(sortedList, {Name = npcName, Level = level, CFrame = cf})
	end

	table.sort(sortedList, function(a, b)
		if a.Level == b.Level then return a.Name < b.Name end
		return a.Level > b.Level
	end)

	for idx, item in ipairs(sortedList) do
		local levelText = item.Level > 0 and string.format(" [Lv.%d]", item.Level) or " [NPC]"
		local displayText = "🌀 วาร์ปไป: " .. item.Name .. levelText

		local tpBtn = Instance.new("TextButton")
		tpBtn.Name = "TP_" .. item.Name
		tpBtn.Size = UDim2.new(1, -8, 0, 28)
		tpBtn.LayoutOrder = idx
		tpBtn.BackgroundColor3 = item.Level > 0 and Color3.fromRGB(90, 50, 140) or Color3.fromRGB(45, 75, 120)
		tpBtn.Text = displayText
		tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		tpBtn.Font = Enum.Font.SourceSansBold
		tpBtn.TextSize = 13
		tpBtn.Parent = tpScrollFrame
		Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 5)

		tpBtn.MouseButton1Click:Connect(function()
            if hubUI.isBusy and hubUI.isBusy() then return end
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp and savedNPCPositions[item.Name] then
				hrp.CFrame = savedNPCPositions[item.Name]
				tpBtn.Text = "⚡ วาร์ปสำเร็จ!"
				task.wait(1)
                if not destroyed and tpBtn.Parent then tpBtn.Text = displayText end
			end
		end)
	end
end

-- บันทึกพิกัดมอนสเตอร์และ NPC (แสดงในหมวดหมู่วาร์ป)
local function autoSaveNPCPosition(npc)
	if not npc or not npc:IsA("Model") then return end
	
	local lvl = getNPCLevel(npc)
	knownNPCNames[npc.Name] = math.max(knownNPCNames[npc.Name] or 0, lvl)

	local targetPart = getNPCRootPart(npc)
	if targetPart then
		if not savedNPCPositions[npc.Name] then
			savedNPCPositions[npc.Name] = targetPart.CFrame
			queueRefresh()
		end
	end

    local isBoss, bKey = checkIsBoss(npc)
    if isBoss and bKey then
        revealInvisibleNPC(npc)
        if not bossCache[bKey] then
            bossCache[bKey] = {
                Key = bKey,
                Name = npc.Name,
                Level = lvl
            }
        end
        if targetPart then
            bossCache[bKey].CFrame = targetPart.CFrame
            savedNPCPositions[bKey] = targetPart.CFrame
        end
        if not bossCache[bKey].InFolder then
            bossCache[bKey].TimeText = "🔥 บอสเกิดแล้ว!"
        end
    end
end

local function stopAll()
    if isAutoHallowRaid then isAutoHallowRaid = false currentRaidRoomIndex = 1 table.clear(openedCoffins) if toggleHallowRaidBtn and toggleHallowRaidBtn.Parent then toggleHallowRaidBtn.Text = "🎃 ออโต้ผ่านด่าน Hungry Ghost Gate (Auto: OFF)" toggleHallowRaidBtn.BackgroundColor3 = Color3.fromRGB(150, 45, 60) end end
    activeBossTarget = nil
    activeBossProbeCount = 0
    lastBossCFrame = nil
    bossLootWaitUntil = 0
	isFarming = false
    currentTarget = nil
    cachedTarget = nil
    targetScanAt = 0
    pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)

	if mainTask then task.cancel(mainTask) mainTask = nil end
	if attackTask then task.cancel(attackTask) attackTask = nil end

	startBtn.Text = "เริ่มฟาร์ม"
	startBtn.BackgroundColor3 = Color3.fromRGB(35, 150, 65)
end

local function useArtifact(aimPosition)
    if not isAutoArtifact or (hubUI.isBusy and hubUI.isBusy()) then return end
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local aim = aimPosition
    if not aim then
        if currentTarget and isAlive(currentTarget) then
            local targetPart = getNPCRootPart(currentTarget)
            if targetPart then aim = targetPart.Position end
        end
    end
    if not aim then
        aim = hrp.Position + hrp.CFrame.LookVector * 25
    end

    artifactRemote = artifactRemote or findArtifactRemote()
    if artifactRemote then
        pcall(function()
            artifactRemote:FireServer({
                op = "Use",
                aim = aim
            })
        end)
    end
end

local function startFarming()
    if isFarming then return end
    combatRemote = findCombatRemote()
    if not combatRemote then
        startBtn.Text = "ยังไม่พบ CombatInput • กดลองใหม่"
        return
    end
	isFarming = true
	startBtn.Text = "🔄 กำลังทำงาน..."
	startBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 100)

	if mainTask then task.cancel(mainTask) end
	if attackTask then task.cancel(attackTask) end

	mainTask = task.spawn(function()
		while isFarming do
            if hubUI.isBusy and hubUI.isBusy() then
                currentTarget = nil
                if startBtn.Text ~= "ฟาร์มพัก • มินิเกมทำงาน" then
                    startBtn.Text = "ฟาร์มพัก • มินิเกมทำงาน"
                end
                task.wait(0.15)
                continue
            end
            local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")

			if hrp then
                -- ตรวจกล่องบอสและ loot wait ก่อนเสมอ เพื่อไม่ให้ข้ามกล่องแล้วรีบไปบอสถัดไป
                if isAutoLooting and lastBossCFrame then
                    local bossChestObj, bossChestPart = getBossChest()
                    if bossChestObj and bossChestPart then
                        currentTarget = nil
                        local bTxt = "🎁 เปิดกล่องบอส: " .. tostring(bossChestObj.Name)
                        if startBtn.Text ~= bTxt then startBtn.Text = bTxt end
                        interactWithDrop(bossChestObj)
                        task.wait(0.1)
                        continue
                    elseif os.clock() < bossLootWaitUntil then
                        currentTarget = nil
                        local secsLeft = math.ceil(bossLootWaitUntil - os.clock())
                        local wTxt = "⏳ รอกล่องบอสเกิด... (" .. secsLeft .. "s)"
                        if startBtn.Text ~= wTxt then startBtn.Text = wTxt end
                        hrp.CFrame = lastBossCFrame * CFrame.new(0, 3, 0)
                        task.wait(0.25)
                        continue
                    end
                end

                local bossCF, bossAlive, bossObj = chooseBossTarget()
                local targetCF, aliveStatus, npcObj
                local isBoss = false

                if bossCF and bossAlive and bossObj then
                    targetCF = bossCF
                    aliveStatus = true
                    npcObj = bossObj
                    isBoss = true
                    local bTxt = "กำลังตีบอส: " .. tostring(npcObj.Name)
                    if startBtn.Text ~= bTxt then startBtn.Text = bTxt end
                elseif bossCF and not bossAlive then
                    -- Boss is spawned, teleport to its anchor position so client streams it in!
                    activeBossProbeCount = (activeBossProbeCount or 0) + 1
                    if activeBossProbeCount > 15 then
                        for key, isSelected in pairs(selectedBossNames) do
                            if isSelected and bossCache[key] and bossCache[key].CFrame == bossCF then
                                bossProbeAt[key] = os.clock() + 20
                            end
                        end
                        activeBossProbeCount = 0
                    else
                        hrp.CFrame = bossCF * CFrame.new(0, 4, 0)
                        if startBtn.Text ~= "วาร์ปหาบอส..." then startBtn.Text = "วาร์ปหาบอส..." end
                        task.wait(0.25)
                        continue
                    end
                else
                    if startBtn.Text ~= "กำลังฟาร์ม..." then startBtn.Text = "กำลังฟาร์ม..." end
                    targetCF, aliveStatus, npcObj = getHighestLevelTarget()
                end

                local isNearBossLoot = lastBossCFrame and os.clock() < (bossLootWaitUntil + 5.0)
                local favoriteReady = isBoss or (not isNearBossLoot and aliveStatus and npcObj and favoriteNPCNames[npcObj.Name])
                local dropsFolder = Workspace:FindFirstChild("Murim_Drops")
				local validDrop = nil
				
				if isAutoLooting and dropsFolder and not favoriteReady then
					local bestItem = nil
					local bestChest = nil
					local bestItemDist = math.huge
					local bestChestDist = math.huge
					local hrpPos = hrp.Position

					for _, drop in ipairs(dropsFolder:GetChildren()) do
						if drop and drop.Parent then
							local part = drop:IsA("BasePart") and drop or (drop:IsA("Model") and drop.PrimaryPart) or drop:FindFirstChildWhichIsA("BasePart", true)
							if part then
								local dist = (part.Position - hrpPos).Magnitude
								if isChest(drop) then
									local cooldown = openedChests[drop]
									if not cooldown or os.clock() >= cooldown then
										local prompt = drop:FindFirstChildWhichIsA("ProximityPrompt", true)
										if prompt and prompt.Enabled and dist < bestChestDist then
											bestChest = drop
											bestChestDist = dist
										end
									end
								else
									if shouldLootItem(drop) and dist < bestItemDist then
										bestItem = drop
										bestItemDist = dist
									end
								end
							end
						end
					end

					-- Always prioritize dropped items first! Chests only opened when ground is clear of loot.
					validDrop = bestItem or bestChest
				end

				if validDrop then
					currentTarget = nil
					interactWithDrop(validDrop)
					task.wait(0.08)
				else

					if aliveStatus and targetCF and npcObj then
						currentTarget = npcObj
						hrp.CFrame = targetCF * CFrame.new(0, heightUnder, 0) * lyingRotation
					else
						currentTarget = nil
                        -- If we were away fighting a boss or died, and no selected monsters are currently loaded:
                        -- Teleport back to the monster's saved position so streaming loads them!
                        local returnCF = nil
                        for name, isFav in pairs(favoriteNPCNames) do
                            if isFav and savedNPCPositions[name] and (knownNPCNames[name] or 0) > 0 then
                                returnCF = savedNPCPositions[name]
                                break
                            end
                        end
                        if not returnCF then
                            for name, isSel in pairs(selectedNPCNames) do
                                if isSel and savedNPCPositions[name] and (knownNPCNames[name] or 0) > 0 then
                                    returnCF = savedNPCPositions[name]
                                    break
                                end
                            end
                        end
                        if returnCF then
                            hrp.CFrame = returnCF
                            if startBtn.Text ~= "วาร์ปกลับจุดฟาร์มมอน..." then
                                startBtn.Text = "วาร์ปกลับจุดฟาร์มมอน..."
                            end
                            task.wait(0.35)
                        elseif isAutoFarmBoss then
                            if startBtn.Text ~= "รอเกิดบอสรอบถัดไป..." then
                                startBtn.Text = "รอเกิดบอสรอบถัดไป..."
                            end
                        end
					end
					task.wait(0.03)
				end
			else
				task.wait(0.5)
			end
		end
	end)

	attackTask = task.spawn(function()
		while isFarming do
			if not (hubUI.isBusy and hubUI.isBusy()) and currentTarget and isAlive(currentTarget) then
				pcall(function()
					combatRemote:FireServer("Attack")
				end)
                pcall(function()
                    local prompt = currentTarget:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt and prompt.Enabled and typeof(fireproximityprompt) == "function" then
                        fireproximityprompt(prompt)
                    end
                end)
                if isAutoArtifact and os.clock() - lastArtifactUsed >= artifactCooldown then
                    lastArtifactUsed = os.clock()
                    local targetPart = getNPCRootPart(currentTarget)
                    if targetPart then
                        useArtifact(targetPart.Position)
                    end
                end
			end
			task.wait(0.1)
		end
	end)
end

toggleHitboxBtn.MouseButton1Click:Connect(function()
	isHitboxExpanded = not isHitboxExpanded
	if isHitboxExpanded then
		toggleHitboxBtn.Text = "🎯 ขยาย Hitbox มอนสเตอร์ (Hitbox: ON)"
		toggleHitboxBtn.BackgroundColor3 = Color3.fromRGB(40, 110, 150)
		updateAllHitboxes()
	else
		restoreHitboxes()
		toggleHitboxBtn.Text = "🎯 ขยาย Hitbox มอนสเตอร์ (Hitbox: OFF)"
		toggleHitboxBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 110)
	end
end)

toggleLootBtn.MouseButton1Click:Connect(function()
	isAutoLooting = not isAutoLooting
	if isAutoLooting then
		toggleLootBtn.Text = "🎁 เก็บของอัตโนมัติ (Auto Loot: ON)"
		toggleLootBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 80)
	else
		toggleLootBtn.Text = "🎁 เก็บของอัตโนมัติ (Auto Loot: OFF)"
		toggleLootBtn.BackgroundColor3 = Color3.fromRGB(110, 50, 130)
	end
end)

-- สแกนลิสต์มอนสเตอร์ลงใน GUI (แสดงทุกตัว ไม่บล็อกด้วย Lv)
refreshNPCList = function()
    if destroyed then return end
	local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")
	if npcsFolder then
		for _, npc in ipairs(npcsFolder:GetChildren()) do
            if not isFriendlyOrTalkable(npc) and getNPCLevel(npc) > 0 then
                applyHitboxToNPC(npc)
            end
            autoSaveNPCPosition(npc)
		end
	end

    refreshTPButtons()
    local signature = listSignature(knownNPCNames, knownNPCNames)
    if signature == npcSignature then return end
    npcSignature = signature

    for _, child in ipairs(scrollFrame:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("Frame") then child:Destroy() end
    end

	local nameList = {}
	for name, lvl in pairs(knownNPCNames) do
        if (lvl or 0) > 0 and not checkIsBossName(name) then
		    table.insert(nameList, name)
        end
	end

	table.sort(nameList, function(a, b)
		local lvlA = knownNPCNames[a] or 0
		local lvlB = knownNPCNames[b] or 0
		if lvlA == lvlB then return a < b end
		return lvlA > lvlB
	end)

	for index, name in ipairs(nameList) do
		local isSelected = selectedNPCNames[name] or false
		local level = knownNPCNames[name] or 0
		local levelDisplay = level > 0 and string.format(" [Lv.%d]", level) or ""

        local row = Instance.new("Frame")
        row.Name = "NPCRow_" .. name
        row.Size = UDim2.new(1, -8, 0, 32)
        row.LayoutOrder = index
        row.BackgroundTransparency = 1
        row.Parent = scrollFrame
        local btn = Instance.new("TextButton")
        btn.Name = name
        btn.Size = UDim2.new(1, -42, 1, 0)
        btn.ClipsDescendants = true
        btn.TextWrapped = true
		btn.BackgroundColor3 = isSelected and Color3.fromRGB(45, 110, 55) or Color3.fromRGB(35, 35, 45)
		btn.Text = (isSelected and "  [✓] " or "  [  ] ") .. name .. levelDisplay
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Font = Enum.Font.SourceSans
		btn.TextSize = 14
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Parent = row
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
        local favoriteBtn = Instance.new("TextButton")
        favoriteBtn.Name = "Favorite"
        favoriteBtn.Position = UDim2.new(1, -36, 0, 0)
        favoriteBtn.Size = UDim2.new(0, 36, 1, 0)
        favoriteBtn.BorderSizePixel = 0
        favoriteBtn.Font = Enum.Font.SourceSansBold
        favoriteBtn.TextSize = 22
        favoriteBtn.Parent = row
        Instance.new("UICorner", favoriteBtn).CornerRadius = UDim.new(0, 5)
        local function updateFavoriteButton()
            local active = favoriteNPCNames[name] == true
            favoriteBtn.Text = active and "★" or "☆"
            favoriteBtn.TextColor3 = active and Color3.fromRGB(255, 215, 80) or Color3.fromRGB(160, 170, 190)
            favoriteBtn.BackgroundColor3 = active and Color3.fromRGB(90, 70, 25) or Color3.fromRGB(35, 35, 45)
        end
        updateFavoriteButton()
        favoriteBtn.MouseButton1Click:Connect(function()
            favoriteNPCNames[name] = not favoriteNPCNames[name]
            targetScanAt = 0
            cachedTarget = nil
            currentTarget = nil
            updateFavoriteButton()
        end)

		btn.MouseButton1Click:Connect(function()
			selectedNPCNames[name] = not selectedNPCNames[name]
            targetScanAt = 0
			if selectedNPCNames[name] then
				btn.BackgroundColor3 = Color3.fromRGB(45, 110, 55)
				btn.Text = "  [✓] " .. name .. levelDisplay
			else
				btn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
				btn.Text = "  [  ] " .. name .. levelDisplay
			end
		end)
	end
end

local function bindFolderEvents()
    for _, conn in ipairs(folderConnections) do conn:Disconnect() end
    table.clear(folderConnections)
    targetScanAt = 0
    local folder = Workspace:FindFirstChild("Murim_NPCs")
    if not folder then return end
    folderConnections[#folderConnections + 1] = folder.ChildAdded:Connect(function()
        targetScanAt = 0
        queueRefresh()
    end)
    folderConnections[#folderConnections + 1] = folder.ChildRemoved:Connect(function()
        targetScanAt = 0
    end)
    queueRefresh()
end
externalConnections[#externalConnections + 1] = Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Murim_NPCs" then bindFolderEvents() end
end)
externalConnections[#externalConnections + 1] = Workspace.ChildRemoved:Connect(function(child)
    if child.Name == "Murim_NPCs" then bindFolderEvents() end
end)
bindFolderEvents()

--------------------------------------------------------------------------------
-- 🛡️ ระบบ Auto Parry (อ้างอิงจาก MurimClient.CombatInput)
--------------------------------------------------------------------------------
local function canParry()
    local char = player.Character
    if not char then return false end
    if char:GetAttribute("Armed") == nil then return false end
    local stance = char:GetAttribute("Stance")
    if stance == "GuardBroken" or stance == "Stunned" or stance == "Parried" then return false end
    if char:GetAttribute("Knocked") or char:GetAttribute("Ragdoll") or char:GetAttribute("Busy") then return false end
    local readyAt = tonumber(char:GetAttribute("ParryReadyAt")) or 0
    if Workspace:GetServerTimeNow() < readyAt then return false end
    return true
end

local function executeParry()
    if isParrying or not canParry() then return end
    isParrying = true
    combatRemote = combatRemote or findCombatRemote()
    if combatRemote then
        pcall(function() combatRemote:FireServer("ParryDown", nil) end)
    end
    task.delay(PARRY_WINDOW, function()
        if combatRemote then
            pcall(function() combatRemote:FireServer("ParryUp", nil) end)
        end
        isParrying = false
    end)
end

local function checkAttacker(enemy, myPos, myHrp)
    if not isAutoParry or isParrying or not enemy or enemy == player.Character then return end
    local act = enemy:GetAttribute("Act")
    if not act then return end

    local actT = enemy:GetAttribute("ActT")
    local actW = enemy:GetAttribute("ActW")
    if type(actT) ~= "number" or type(actW) ~= "number" or actW <= 0 then return end

    local enemyHrp = getNPCRootPart(enemy)
    if not enemyHrp then return end

    local ep = enemyHrp.Position
    if math.abs(myPos.X - ep.X) > PARRY_DISTANCE or math.abs(myPos.Z - ep.Z) > PARRY_DISTANCE then return end

    local dist = (myPos - ep).Magnitude
    if dist > PARRY_DISTANCE then return end

    local attackId = tostring(act) .. "_" .. tostring(actT)
    if handledAttacks[enemy] == attackId then return end

    local serverNow = Workspace:GetServerTimeNow()
    local hitTime = actT + actW
    local timeRemaining = hitTime - serverNow

    if timeRemaining > 0 and timeRemaining <= (actW + 0.1) then
        handledAttacks[enemy] = attackId
        local delayTime = math.max(0, timeRemaining - PARRY_LEAD)
        if delayTime <= 0.02 then
            executeParry()
        else
            task.delay(delayTime, function()
                if not destroyed and isAutoParry and enemy and enemy.Parent and myHrp.Parent then
                    local currentDist = (myHrp.Position - enemyHrp.Position).Magnitude
                    if currentDist <= PARRY_DISTANCE then
                        executeParry()
                    end
                end
            end)
        end
    end
end

externalConnections[#externalConnections + 1] = RunService.Heartbeat:Connect(function()
    if destroyed or not isAutoParry or isParrying or (hubUI.isBusy and hubUI.isBusy()) then return end
    local char = player.Character
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not myHrp then return end
    local myPos = myHrp.Position

    local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")
    if npcsFolder then
        for _, npc in ipairs(npcsFolder:GetChildren()) do
            checkAttacker(npc, myPos, myHrp)
        end
    end
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            checkAttacker(otherPlayer.Character, myPos, myHrp)
        end
    end
end)


--------------------------------------------------------------------------------
-- 📿 ระบบ Auto Artifact (ทำงานอัตโนมัติเมื่ออยู่ในระยะศัตรู)
--------------------------------------------------------------------------------
artifactTask = task.spawn(function()
    while not destroyed do
        if isAutoArtifact and not isFarming and not (hubUI.isBusy and hubUI.isBusy()) then
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and os.clock() - lastArtifactUsed >= artifactCooldown then
                local targetPos = nil
                local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")
                local closestDist = 50
                if npcsFolder then
                    for _, npc in ipairs(npcsFolder:GetChildren()) do
                        if isAlive(npc) then
                            local tPart = getNPCRootPart(npc)
                            if tPart then
                                local d = (hrp.Position - tPart.Position).Magnitude
                                if d < closestDist then
                                    closestDist = d
                                    targetPos = tPart.Position
                                end
                            end
                        end
                    end
                end
                if not targetPos then
                    for _, otherP in ipairs(Players:GetPlayers()) do
                        if otherP ~= player and otherP.Character then
                            local otherHrp = otherP.Character:FindFirstChild("HumanoidRootPart")
                            local hum = otherP.Character:FindFirstChildOfClass("Humanoid")
                            if otherHrp and hum and hum.Health > 0 then
                                local d = (hrp.Position - otherHrp.Position).Magnitude
                                if d < closestDist then
                                    closestDist = d
                                    targetPos = otherHrp.Position
                                end
                            end
                        end
                    end
                end
                if targetPos then
                    lastArtifactUsed = os.clock()
                    useArtifact(targetPos)
                end
            end
        end
        task.wait(0.5)
    end
end)

--------------------------------------------------------------------------------
-- 🎃 ระบบ Auto The Hungry Ghost Gate Raid (ห้อง 1 - 5)
--------------------------------------------------------------------------------
local hallowRaidTask = task.spawn(function()
    while not destroyed do
        if isAutoHallowRaid and not (hubUI.isBusy and hubUI.isBusy()) then
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local isInside = checkIsInsideRaid(player)

                if not isInside then
                    currentRaidRoomIndex = 1
                    roomEnterTime = 0
                    room3Phase = 1
                    immortalEffigies = {}
                    effigyHpSnapshot = {}
                    local dialog = player.PlayerGui:FindFirstChild("MurimDialog")
                    if dialog and dialog:FindFirstChild("Panel") then
                        local sf = dialog.Panel:FindFirstChild("ScrollingFrame")
                        local diffChoice = sf and sf:FindFirstChild(hallowDifficulty)
                        if not diffChoice and sf then
                            for _, child in ipairs(sf:GetChildren()) do
                                if child.Name:lower() == hallowDifficulty:lower() then
                                    diffChoice = child
                                    break
                                end
                                local lbl = child:FindFirstChild("Label") or child:FindFirstChildWhichIsA("TextLabel", true)
                                if lbl and lbl.Text:lower():find(hallowDifficulty:lower(), 1, true) then
                                    diffChoice = child
                                    break
                                end
                            end
                        end
                        if diffChoice then
                            local targetBtn = (diffChoice:IsA("GuiButton") and diffChoice) or diffChoice:FindFirstChildWhichIsA("GuiButton", true) or diffChoice
                            if hallowStatusLabel then hallowStatusLabel.Text = "🚪 กำลังกดเลือก: " .. hallowDifficulty .. "..." end
                            if typeof(firesignal) == "function" and targetBtn:IsA("GuiButton") then
                                pcall(function() firesignal(targetBtn.MouseButton1Click) end)
                                pcall(function() firesignal(targetBtn.Activated) end)
                            end
                            pcall(function()
                                if VirtualInputManager and targetBtn:IsA("GuiObject") and targetBtn.AbsoluteSize.X > 0 then
                                    local cx = targetBtn.AbsolutePosition.X + targetBtn.AbsoluteSize.X / 2
                                    local cy = targetBtn.AbsolutePosition.Y + targetBtn.AbsoluteSize.Y / 2
                                    VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
                                    task.wait(0.05)
                                    VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
                                end
                            end)
                            task.wait(1.5)
                        end
                    else
                        local ledgerPrompt, ledgerPart = findGuestLedger()
                        if ledgerPart then
                            local dist = (hrp.Position - ledgerPart.Position).Magnitude
                            if dist > 8 then
                                if hallowStatusLabel then hallowStatusLabel.Text = "⚡ กำลังวาร์ปไปที่แท่นสมุด Guest Ledger..." end
                                hrp.CFrame = ledgerPart.CFrame * CFrame.new(0, 2, -4) * CFrame.Angles(0, math.rad(180), 0)
                                task.wait(0.5)
                            else
                                if hallowStatusLabel then hallowStatusLabel.Text = "📜 กำลังกด Sign the guest ledger..." end
                                if ledgerPrompt then
                                    if typeof(fireproximityprompt) == "function" then
                                        fireproximityprompt(ledgerPrompt)
                                    else
                                        pcall(function()
                                            ledgerPrompt:InputHoldBegin()
                                            task.wait(ledgerPrompt.HoldDuration or 0.1)
                                            ledgerPrompt:InputHoldEnd()
                                        end)
                                    end
                                else
                                    pcall(function()
                                        if VirtualInputManager then
                                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                            task.wait(0.1)
                                            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                        end
                                    end)
                                end
                                task.wait(0.8)
                            end
                        else
                            local gateDist = (hrp.Position - HALLOW_GATE_CFRAME.Position).Magnitude
                            if gateDist > 35 then
                                if hallowStatusLabel then hallowStatusLabel.Text = "⚡ กำลังวาร์ปไปลานพิธี (Sunken Waystation)..." end
                                hrp.CFrame = HALLOW_GATE_CFRAME
                                task.wait(0.6)
                            else
                                if hallowStatusLabel then hallowStatusLabel.Text = "🔍 กำลังค้นหาแท่นสมุด Guest Ledger..." end
                                task.wait(0.5)
                            end
                        end
                    end
                else
                    -- INSIDE RAID!
                    local activeRaidModel = getActiveRaidModel()

                    if roomEnterTime == 0 then
                        roomEnterTime = os.clock()
                        lastRaidActionTime = os.clock()
                        currentRaidRoomIndex = 1
                        room3Phase = 1
                        immortalEffigies = {}
                        effigyHpSnapshot = {}
                    end

                    -- Auto Pacify / Seen
                    if isHallowPacifySeen and os.clock() - lastSeenPacifyTime >= 0.5 then
                        lastSeenPacifyTime = os.clock()
                        pcall(function()
                            local seenRemote = ReplicatedStorage:FindFirstChild("HallowGateSeen")
                            if seenRemote then
                                local CollectionService = game:GetService("CollectionService")
                                local ids = {}
                                for _, obj in ipairs(CollectionService:GetTagged("HallowWatched")) do
                                    local hId = obj:GetAttribute("HallowId")
                                    if hId then table.insert(ids, hId) end
                                    if #ids >= 32 then break end
                                end
                                if #ids > 0 then
                                    seenRemote:FireServer("seen", ids)
                                end
                            end
                        end)
                    end

                    -- Check for drops nearby
                    local dropsFolder = Workspace:FindFirstChild("Murim_Drops")
                    local raidDrop = nil
                    if dropsFolder then
                        for _, drop in ipairs(dropsFolder:GetChildren()) do
                            if drop and drop.Parent then
                                local dPart = drop:IsA("BasePart") and drop or (drop:IsA("Model") and (drop.PrimaryPart or drop:FindFirstChildWhichIsA("BasePart", true)))
                                if dPart and (dPart.Position - hrp.Position).Magnitude <= 80 then
                                    raidDrop = drop
                                    break
                                end
                            end
                        end
                    end
                    if raidDrop then
                        if hallowStatusLabel then hallowStatusLabel.Text = "🎁 กำลังเก็บของรางวัล: " .. tostring(raidDrop.Name) end
                        interactWithDrop(raidDrop)
                        task.wait(0.1)
                    else
                        local timeInRoom = os.clock() - roomEnterTime

                        -- ========================================================
                        -- ROOM 1: เดินไปหน้าประตู A02_CoffinLodge.Scripted.HallowDoor (LeafL & LeafR)
                        -- รอประตูเปิด -> ไม่ตีมอน วาร์ปเข้าห้อง 2 ทันที
                        -- ========================================================
                        if currentRaidRoomIndex == 1 then
                            local door2 = activeRaidModel and activeRaidModel:FindFirstChild("A02_CoffinLodge") and activeRaidModel.A02_CoffinLodge:FindFirstChild("Scripted") and activeRaidModel.A02_CoffinLodge.Scripted:FindFirstChild("HallowDoor")
                            local leafL = door2 and door2:FindFirstChild("LeafL")
                            local leafR = door2 and door2:FindFirstChild("LeafR")
                            local doorCenter = nil
                            if leafL and leafR and leafL:IsA("BasePart") and leafR:IsA("BasePart") then
                                doorCenter = (leafL.Position + leafR.Position) / 2
                            elseif leafL and leafL:IsA("BasePart") then
                                doorCenter = leafL.Position
                            elseif door2 and door2:IsA("Model") then
                                doorCenter = door2:GetPivot().Position
                            end

                            if not doorCenter then
                                local m1 = activeRaidModel and activeRaidModel:FindFirstChild("A01_Causeway") and activeRaidModel.A01_Causeway:FindFirstChild("Markers")
                                local shrine = m1 and m1:FindFirstChild("HallowShrine")
                                if shrine and shrine:IsA("BasePart") then
                                    doorCenter = shrine.Position
                                end
                            end

                            if doorCenter then
                                -- ยืนหน้าประตู HallowDoor ฝั่งห้อง 1 (Causeway)
                                local waitPos = Vector3.new(doorCenter.X, doorCenter.Y + 2, doorCenter.Z - 6)
                                if (hrp.Position - waitPos).Magnitude > 6 then
                                    hrp.CFrame = CFrame.new(waitPos)
                                end
                            end

                            -- ตรวจสอบว่าประตูเปิดแล้วหรือยัง
                            local isDoorOpen = false
                            if leafL and leafR and leafL:IsA("BasePart") and leafR:IsA("BasePart") then
                                if not leafL.CanCollide or not leafR.CanCollide then
                                    isDoorOpen = true
                                elseif (leafL.Position - leafR.Position).Magnitude > 7.5 then
                                    isDoorOpen = true
                                end
                            end
                            if door2 then
                                if door2:GetAttribute("Open") == true or door2:GetAttribute("Opened") == true or door2:GetAttribute("IsOpen") == true then
                                    isDoorOpen = true
                                end
                            end

                            -- เช็คว่ามอนสเตอร์โผล่มาแล้วหรือเวลารอหน้าประตูครบ (~7.5 วินาที)
                            local hasMobsSpawned = false
                            local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")
                            if npcsFolder then
                                for _, m in ipairs(npcsFolder:GetChildren()) do
                                    if isHallowFoe(m) and isAlive(m) then
                                        hasMobsSpawned = true
                                        break
                                    end
                                end
                            end
                            if not hasMobsSpawned and activeRaidModel then
                                local room1 = activeRaidModel:FindFirstChild("A01_Causeway")
                                if room1 then
                                    for _, m in ipairs(room1:GetDescendants()) do
                                        if m:IsA("Model") and isHallowFoe(m) and isAlive(m) then
                                            hasMobsSpawned = true
                                            break
                                        end
                                    end
                                end
                            end

                            if isDoorOpen or hasMobsSpawned or timeInRoom >= 7.5 then
                                if hallowStatusLabel then hallowStatusLabel.Text = "🚪 [1/5 滅燈堤] ประตู HallowDoor (LeafL/R) เปิดแล้ว! มุ่งหน้าเข้าห้อง 2..." end
                                currentRaidRoomIndex = 2
                                roomEnterTime = os.clock()
                                lastRaidActionTime = os.clock()
                                table.clear(openedCoffins)
                                local nextPos = getRoomTargetPosition(2, activeRaidModel)
                                if nextPos then
                                    hrp.CFrame = CFrame.new(nextPos + Vector3.new(0, 3, 0))
                                end
                                task.wait(1.0)
                            else
                                if hallowStatusLabel then
                                    hallowStatusLabel.Text = string.format("⏳ [1/5 滅燈堤] ยืนรอหน้าประตู HallowDoor เปิด... (%.1fs/7.5s)", timeInRoom)
                                end
                            end

                        -- ========================================================
                        -- ROOM 2: เปิดโลงศพเรื่อยๆ เพื่อหากุญแจ (Key) -> ประตูห้อง 3 เปิด
                        -- (กรองข้ามโลงซ่อนตัว HallowHideCoffin 100% + ปลดล็อกหากนั่ง/ติดในโลง)
                        -- ========================================================
                        elseif currentRaidRoomIndex == 2 then
                            local room2Model = activeRaidModel and activeRaidModel:FindFirstChild("A02_CoffinLodge")
                            local door3 = activeRaidModel and activeRaidModel:FindFirstChild("A03_EffigyShop") and activeRaidModel.A03_EffigyShop:FindFirstChild("Scripted") and activeRaidModel.A03_EffigyShop.Scripted:FindFirstChild("HallowDoor")
                            local room3Entry = activeRaidModel and activeRaidModel:FindFirstChild("A03_EffigyShop") and activeRaidModel.A03_EffigyShop:FindFirstChild("Markers") and activeRaidModel.A03_EffigyShop.Markers:FindFirstChild("HallowEntry")
                            
                            -- แก้บัคถ้าตัวละครเผลอนั่งหรือติดในโลงซ่อน
                            local hum = char:FindFirstChildOfClass("Humanoid")
                            if hum and hum.Sit then
                                hum.Sit = false
                                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                            end

                            -- ตรวจสอบว่าประตูด่าน 3 เปิดแล้วหรือยัง
                            local isRoom3Open = false
                            if door3 then
                                local leafL3 = door3:FindFirstChild("LeafL")
                                local leafR3 = door3:FindFirstChild("LeafR")
                                if leafL3 and leafR3 and leafL3:IsA("BasePart") and leafR3:IsA("BasePart") then
                                    if not leafL3.CanCollide or not leafR3.CanCollide or (leafL3.Position - leafR3.Position).Magnitude > 7.5 then
                                        isRoom3Open = true
                                    end
                                end
                                if door3:GetAttribute("Open") == true or door3:GetAttribute("Opened") == true or door3:GetAttribute("IsOpen") == true then
                                    isRoom3Open = true
                                end
                            end
                            if not isRoom3Open and room3Entry and room3Entry:IsA("BasePart") then
                                if (hrp.Position - room3Entry.Position).Magnitude < 40 then
                                    isRoom3Open = true
                                end
                            end

                            -- เช็คว่ามี Key ในตัวหรือในกระเป๋าไหม
                            local hasKey = false
                            local bp = player:FindFirstChild("Backpack")
                            if bp then
                                for _, item in ipairs(bp:GetChildren()) do
                                    if item.Name:lower():find("key") then hasKey = true break end
                                end
                            end
                            if not hasKey and char then
                                for _, item in ipairs(char:GetChildren()) do
                                    if item.Name:lower():find("key") then hasKey = true break end
                                end
                            end

                            if isRoom3Open or hasKey or (timeInRoom >= 90.0 and isRoom3Open) then
                                if hallowStatusLabel then hallowStatusLabel.Text = "🔑 [2/10 義莊] ได้กุญแจแล้ว / ประตูห้อง 3 เปิด! มุ่งหน้าไปห้อง 3..." end
                                currentRaidRoomIndex = 3
                                roomEnterTime = os.clock()
                                lastRaidActionTime = os.clock()
                                room3Phase = 1
                                immortalEffigies = {}
                                effigyHpSnapshot = {}
                                local nextPos = getRoomTargetPosition(3, activeRaidModel)
                                if nextPos then
                                    hrp.CFrame = CFrame.new(nextPos + Vector3.new(0, 3, 0))
                                end
                                task.wait(1.0)
                            else
                                local targetPrompt = nil
                                local targetPart = nil
                                local targetCoffinModel = nil

                                if room2Model and os.clock() - lastRaidActionTime >= 0.3 then
                                    -- วนหาโลงศพ HallowCoffin ใน Scripted โดยตรง (เช็ค Risen ~= true)
                                    local scripted = room2Model:FindFirstChild("Scripted")
                                    if scripted then
                                        for _, coffin in ipairs(scripted:GetChildren()) do
                                            if coffin.Name == "HallowCoffin" and coffin:GetAttribute("Risen") ~= true then
                                                local prompt = coffin:FindFirstChildWhichIsA("ProximityPrompt", true)
                                                if prompt and prompt.Enabled and not openedCoffins[prompt] and not openedCoffins[coffin] then
                                                    local p = prompt.Parent:IsA("BasePart") and prompt.Parent or coffin:FindFirstChildWhichIsA("BasePart", true)
                                                    if p then
                                                        targetPrompt = prompt
                                                        targetPart = p
                                                        targetCoffinModel = coffin
                                                        break
                                                    end
                                                end
                                            end
                                        end
                                    end

                                    -- ถ้าไม่พบใน Scripted หาจาก Descendants โดยกรองโลงซ่อนตัว HallowHideCoffin ทิ้ง
                                    if not targetPrompt then
                                        for _, prompt in ipairs(room2Model:GetDescendants()) do
                                            if prompt:IsA("ProximityPrompt") and prompt.Enabled and not openedCoffins[prompt] then
                                                local parent = prompt.Parent
                                                local grandParent = parent and parent.Parent
                                                local pName = (prompt.Name or ""):lower() .. " " .. (prompt.ActionText or ""):lower() .. " " .. (prompt.ObjectText or ""):lower() .. " " .. (parent and parent.Name or ""):lower() .. " " .. (grandParent and grandParent.Name or ""):lower()
                                                local isHidingSpot = pName:find("hide") or pName:find("enter") or pName:find("crawl") or pName:find("sit") or pName:find("seat") or pName:find("shelter")

                                                if not isHidingSpot then
                                                    local p = prompt.Parent:IsA("BasePart") and prompt.Parent or prompt.Parent:FindFirstChildWhichIsA("BasePart", true)
                                                    if p then
                                                        targetPrompt = prompt
                                                        targetPart = p
                                                        break
                                                    end
                                                end
                                            end
                                        end
                                    end

                                    if targetPrompt and targetPart then
                                        lastRaidActionTime = os.clock()
                                        if targetCoffinModel then openedCoffins[targetCoffinModel] = true end
                                        openedCoffins[targetPrompt] = true
                                        local holdTime = targetPrompt.HoldDuration or 2.0
                                        if holdTime <= 0 then holdTime = 1.5 end

                                        if hallowStatusLabel then
                                            hallowStatusLabel.Text = string.format("⚰️ [2/10 義莊] กำลังเปิดโลงศพหากุญแจ (รอ %.1fs)...", holdTime)
                                        end
                                        hrp.CFrame = CFrame.new(targetPart.Position + Vector3.new(0, 3, 0))

                                        -- ยืนรอที่โลงและเปิดให้เสร็จสมบูรณ์
                                        if typeof(fireproximityprompt) == "function" then
                                            fireproximityprompt(targetPrompt)
                                        end
                                        pcall(function()
                                            targetPrompt:InputHoldBegin()
                                            task.wait(holdTime)
                                            targetPrompt:InputHoldEnd()
                                        end)
                                        task.wait(0.4)
                                    else
                                        if hallowStatusLabel then
                                            hallowStatusLabel.Text = string.format("🔍 [2/10 義莊] ค้นหาโลงศพถัดไปหากุญแจ... (%.0fs)", timeInRoom)
                                        end
                                    end
                                end
                            end

                        -- ========================================================
                        -- ROOM 3: ตี Paper Effigies จนประตูเปิด -> ผ่านประตูไปตี Boss Paper Tailor
                        -- ========================================================
                        elseif currentRaidRoomIndex == 3 then
                            local room3Model = activeRaidModel and activeRaidModel:FindFirstChild("A03_EffigyShop")
                            local tailorSpot = room3Model and room3Model:FindFirstChild("Markers") and room3Model.Markers:FindFirstChild("HallowTailorSpot")
                            local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")

                            -- ตรวจสอบว่าบอส Paper Tailor เกิดแล้วหรือยัง
                            local bossTailor = nil
                            local function checkTailor(npc)
                                if npc:IsA("Model") and npc.Parent then
                                    local nLow = npc.Name:lower()
                                    local isTailor = nLow:find("tailor") or nLow:find("boss") or (nLow:find("paper") and not nLow:find("effigy"))
                                    if isTailor and not nLow:find("gu heng") and not nLow:find("an rou") then
                                        local hum = npc:FindFirstChildOfClass("Humanoid")
                                        if hum and hum.Health > 0 then
                                            bossTailor = npc
                                        end
                                    end
                                end
                            end

                            if npcsFolder then
                                for _, npc in ipairs(npcsFolder:GetChildren()) do checkTailor(npc) end
                            end
                            if not bossTailor and room3Model then
                                for _, desc in ipairs(room3Model:GetDescendants()) do checkTailor(desc) end
                            end

                            -- ถ้าพบบอส Paper Tailor แล้ว สลับเป็นเฟส 2 ทันที
                            if bossTailor then
                                room3Phase = 2
                            end

                            -- เฟส 1: ตี Paper Effigies จนหมด เพื่อเปิดประตูใน
                            if room3Phase == 1 then
                                local bestEffigy = nil
                                local bestDist = math.huge
                                local hrpPos = hrp.Position
                                local effigyCount = 0

                                local function checkEffigy(npc)
                                    if npc:IsA("Model") and npc.Parent then
                                        local nLow = npc.Name:lower()
                                        if nLow:find("effigy") or nLow:find("paper") then
                                            -- ข้ามตัวที่อมตะจาก attribute
                                            if npc:GetAttribute("Invulnerable") or npc:GetAttribute("Immune")
                                                or npc:GetAttribute("unhurt") or npc:GetAttribute("HallowNoBar") then
                                                return
                                            end
                                            -- ข้ามตัวที่ blacklist ว่าอมตะ
                                            if immortalEffigies[npc] then return end
                                            local hum = npc:FindFirstChildOfClass("Humanoid")
                                            if hum and hum.Health > 0 then
                                                effigyCount = effigyCount + 1
                                                local part = getNPCRootPart(npc)
                                                if part then
                                                    local d = (part.Position - hrpPos).Magnitude
                                                    if d < bestDist then
                                                        bestDist = d
                                                        bestEffigy = npc
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end

                                if npcsFolder then
                                    for _, npc in ipairs(npcsFolder:GetChildren()) do checkEffigy(npc) end
                                end
                                if not bestEffigy and room3Model then
                                    for _, desc in ipairs(room3Model:GetDescendants()) do checkEffigy(desc) end
                                end

                                if bestEffigy then
                                    lastRaidActionTime = os.clock()
                                    local targetPart = getNPCRootPart(bestEffigy)
                                    if targetPart then
                                        currentTarget = bestEffigy
                                        applyHitboxToNPC(bestEffigy)
                                        revealInvisibleNPC(bestEffigy)
                                        hrp.CFrame = targetPart.CFrame * CFrame.new(0, 0, 3)
                                        combatRemote = combatRemote or findCombatRemote()
                                        if combatRemote then
                                            pcall(function() combatRemote:FireServer("Attack") end)
                                        end
                                        if isAutoArtifact and os.clock() - lastArtifactUsed >= artifactCooldown then
                                            lastArtifactUsed = os.clock()
                                            useArtifact(targetPart.Position)
                                        end
                                        -- ตรวจสอบ immortal: ถ้าตีนาน 4 วินาที HP ไม่ลดเลย ให้ blacklist
                                        local hum = bestEffigy:FindFirstChildOfClass("Humanoid")
                                        if hum then
                                            local snap = effigyHpSnapshot[bestEffigy]
                                            if snap then
                                                if hum.Health >= snap.hp and (os.clock() - snap.t) >= 4.0 then
                                                    -- HP ไม่ลดเลยใน 4 วินาที = อมตะ
                                                    immortalEffigies[bestEffigy] = true
                                                    effigyHpSnapshot[bestEffigy] = nil
                                                elseif hum.Health < snap.hp then
                                                    -- HP ลดได้ปกติ รีเซต snapshot
                                                    effigyHpSnapshot[bestEffigy] = { hp = hum.Health, t = os.clock() }
                                                end
                                            else
                                                effigyHpSnapshot[bestEffigy] = { hp = hum.Health, t = os.clock() }
                                            end
                                        end
                                        local hpText = hum and string.format(" (HP: %.0f, เหลือ %d ตัว)", hum.Health, effigyCount) or ""
                                        if hallowStatusLabel then
                                            hallowStatusLabel.Text = "✂️ [3/10 เฟส 1] กำลังกำจัด Paper Effigy" .. hpText .. " เพื่อเปิดประตู..."
                                        end
                                    end
                                else
                                    -- มอนสเตอร์หุ่นกระดาษหมดแล้ว เดินผ่านประตูในไปจุดเกิดบอส Paper Tailor
                                    if hallowStatusLabel then
                                        hallowStatusLabel.Text = "✂️ [3/10 เฟส 1] Paper Effigy หมดแล้ว! กำลังเดินผ่านประตูไปหาบอส Paper Tailor..."
                                    end
                                    room3Phase = 2
                                    lastRaidActionTime = os.clock()
                                    if tailorSpot and tailorSpot:IsA("BasePart") then
                                        hrp.CFrame = CFrame.new(tailorSpot.Position + Vector3.new(0, 3, 0))
                                    end
                                    task.wait(1.5)
                                end

                            -- เฟส 2: กำจัด Boss Paper Tailor
                            else
                                if bossTailor then
                                    bossTailorFought = true
                                    lastRaidActionTime = os.clock()
                                    local targetPart = getNPCRootPart(bossTailor)
                                    if targetPart then
                                        currentTarget = bossTailor
                                        applyHitboxToNPC(bossTailor)
                                        revealInvisibleNPC(bossTailor)
                                        hrp.CFrame = targetPart.CFrame * CFrame.new(0, 0, 3)
                                        combatRemote = combatRemote or findCombatRemote()
                                        if combatRemote then
                                            pcall(function() combatRemote:FireServer("Attack") end)
                                        end
                                        if isAutoArtifact and os.clock() - lastArtifactUsed >= artifactCooldown then
                                            lastArtifactUsed = os.clock()
                                            useArtifact(targetPart.Position)
                                        end
                                        local hum = bossTailor:FindFirstChildOfClass("Humanoid")
                                        local hpText = hum and string.format(" (HP: %.0f)", hum.Health) or ""
                                        if hallowStatusLabel then
                                            hallowStatusLabel.Text = "👑 [3/10 เฟส 2] กำลังกำจัดบอส: " .. bossTailor.Name .. hpText .. "!"
                                        end
                                    end
                                else
                                    -- ตรวจสอบประตูไปห้อง 4 (A04_WatchmanStreet)
                                    local doorToRoom4 = room3Model and room3Model:FindFirstChild("Scripted") and room3Model.Scripted:FindFirstChild("HallowDoor")
                                    local isDoor4Open = false
                                    if doorToRoom4 then
                                        local leafL = doorToRoom4:FindFirstChild("LeafL")
                                        local leafR = doorToRoom4:FindFirstChild("LeafR")
                                        if leafL and leafR and leafL:IsA("BasePart") and leafR:IsA("BasePart") then
                                            if not leafL.CanCollide or not leafR.CanCollide or (leafL.Position - leafR.Position).Magnitude > 7.5 then
                                                isDoor4Open = true
                                            end
                                        end
                                        if doorToRoom4:GetAttribute("Open") == true or doorToRoom4:GetAttribute("Opened") == true then
                                            isDoor4Open = true
                                        end
                                    end

                                    -- ย้ายไปห้อง 4 เฉพาะเมื่อเคยเจอบอสแล้วและบอสตาย หรือประตูห้อง 4 เปิดแล้วเท่านั้น (ห้ามข้ามเองเด็ดขาด!)
                                    if isDoor4Open or (bossTailorFought and (os.clock() - lastRaidActionTime >= 3.0)) then
                                        if hallowStatusLabel then hallowStatusLabel.Text = "🚪 [3/10 紙紮鋪] บอส Paper Tailor ถูกกำจัดแล้ว! มุ่งหน้าไปห้อง 4..." end
                                        currentRaidRoomIndex = 4
                                        roomEnterTime = os.clock()
                                        lastRaidActionTime = os.clock()
                                        bossTailorFought = false
                                        local nextPos = getRoomTargetPosition(4, activeRaidModel)
                                        if nextPos then
                                            hrp.CFrame = CFrame.new(nextPos + Vector3.new(0, 3, 0))
                                        end
                                        task.wait(1.0)
                                    else
                                        -- ยังไม่เจอบอส ให้เดินไปยืนที่ tailorSpot เพื่อทริกเกอร์ให้บอสเกิด
                                        if tailorSpot and tailorSpot:IsA("BasePart") and (hrp.Position - tailorSpot.Position).Magnitude > 8 then
                                            hrp.CFrame = CFrame.new(tailorSpot.Position + Vector3.new(0, 3, 0))
                                        end
                                        if hallowStatusLabel then
                                            hallowStatusLabel.Text = string.format("⏳ [3/10 เฟส 2] เดินผ่านประตู/รอเกิดบอส Paper Tailor... (%.0fs)", timeInRoom)
                                        end
                                    end
                                end
                            end

                        -- ========================================================
                        -- ROOM 4: จุดตะเกียงศาลเจ้า 3 แห่ง (HallowStreetShrine) -> ประตูห้อง 5 เปิด
                        -- ========================================================
                        elseif currentRaidRoomIndex == 4 then
                            local room4Model = activeRaidModel and activeRaidModel:FindFirstChild("A04_WatchmanStreet")
                            local room5Entry = activeRaidModel and activeRaidModel:FindFirstChild("A05_Teahouse") and activeRaidModel.A05_Teahouse:FindFirstChild("Markers") and activeRaidModel.A05_Teahouse.Markers:FindFirstChild("HallowEntry")
                            
                            local isRoom5Open = false
                            if room5Entry and room5Entry:IsA("BasePart") then
                                if (hrp.Position - room5Entry.Position).Magnitude < 40 then
                                    isRoom5Open = true
                                end
                            end
                            if room4Model and room4Model:FindFirstChild("Scripted") then
                                for _, d in ipairs(room4Model.Scripted:GetChildren()) do
                                    if d.Name == "HallowDoor" then
                                        local leafL = d:FindFirstChild("LeafL")
                                        local leafR = d:FindFirstChild("LeafR")
                                        if leafL and leafR and leafL:IsA("BasePart") and leafR:IsA("BasePart") then
                                            if not leafL.CanCollide or not leafR.CanCollide or (leafL.Position - leafR.Position).Magnitude > 7.5 then
                                                isRoom5Open = true
                                            end
                                        end
                                        if d:GetAttribute("Open") == true or d:GetAttribute("Opened") == true then
                                            isRoom5Open = true
                                        end
                                    end
                                end
                            end
                            if timeInRoom >= 35.0 then
                                isRoom5Open = true
                            end

                            if isRoom5Open then
                                if hallowStatusLabel then hallowStatusLabel.Text = "🏮 [4/10 更夫街] จุดไฟศาลเจ้าครบแล้ว / ประตูเปิด! มุ่งหน้าไปห้อง 5..." end
                                currentRaidRoomIndex = 5
                                roomEnterTime = os.clock()
                                lastRaidActionTime = os.clock()
                                local nextPos = getRoomTargetPosition(5, activeRaidModel)
                                if nextPos then
                                    hrp.CFrame = CFrame.new(nextPos + Vector3.new(0, 3, 0))
                                end
                                task.wait(1.0)
                            else
                                local targetShrinePrompt = nil
                                local targetShrinePart = nil
                                local unlitShrinesCount = 0

                                if room4Model and room4Model:FindFirstChild("Scripted") then
                                    for _, shrine in ipairs(room4Model.Scripted:GetChildren()) do
                                        if shrine.Name == "HallowStreetShrine" then
                                            local prompt = shrine:FindFirstChildWhichIsA("ProximityPrompt", true)
                                            if prompt and prompt.Enabled then
                                                unlitShrinesCount = unlitShrinesCount + 1
                                                if not targetShrinePrompt then
                                                    local p = prompt.Parent:IsA("BasePart") and prompt.Parent or shrine:FindFirstChildWhichIsA("BasePart", true)
                                                    if p then
                                                        targetShrinePrompt = prompt
                                                        targetShrinePart = p
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end

                                -- ถ้าไม่เจอใน HallowStreetShrine ให้หาจาก ProximityPrompt ทั่วไปแต่ข้ามจุดซ่อนตัว HallowHide
                                if not targetShrinePrompt and room4Model and os.clock() - lastRaidActionTime >= 0.7 then
                                    for _, prompt in ipairs(room4Model:GetDescendants()) do
                                        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
                                            local pName = (prompt.ActionText or ""):lower() .. " " .. (prompt.ObjectText or ""):lower() .. " " .. (prompt.Parent and prompt.Parent.Name or ""):lower()
                                            if not pName:find("hide") and not pName:find("crawl") and not pName:find("enter") and not pName:find("watchman") and not pName:find("sedan") and not pName:find("talk") and not pName:find("shop") then
                                                local p = prompt.Parent:IsA("BasePart") and prompt.Parent or prompt.Parent:FindFirstChildWhichIsA("BasePart", true)
                                                if p then
                                                    targetShrinePrompt = prompt
                                                    targetShrinePart = p
                                                    break
                                                end
                                            end
                                        end
                                    end
                                end

                                if targetShrinePrompt and targetShrinePart then
                                    lastRaidActionTime = os.clock()
                                    if hallowStatusLabel then
                                        hallowStatusLabel.Text = string.format("🏮 [4/10 更夫街] กำลังจุดตะเกียงศาลเจ้า (เหลืออีก %d จุด)...", math.max(1, unlitShrinesCount))
                                    end
                                    hrp.CFrame = CFrame.new(targetShrinePart.Position + Vector3.new(0, 3, 0))
                                    if typeof(fireproximityprompt) == "function" then
                                        fireproximityprompt(targetShrinePrompt)
                                    end
                                    pcall(function()
                                        targetShrinePrompt:InputHoldBegin()
                                        task.wait(targetShrinePrompt.HoldDuration or 4.0)
                                        targetShrinePrompt:InputHoldEnd()
                                    end)
                                else
                                    if unlitShrinesCount == 0 and timeInRoom >= 5.0 then
                                        isRoom5Open = true
                                    end
                                    if hallowStatusLabel then
                                        hallowStatusLabel.Text = string.format("🔍 [4/10 更夫街] กำลังตรวจหาศาลเจ้าที่ยังไม่จุดไฟ... (%.0fs)", timeInRoom)
                                    end
                                end
                            end

                        -- ========================================================
                        -- ROOM 5: โรงน้ำชา (The Last Teahouse - 末茶樓)
                        -- ========================================================
                        elseif currentRaidRoomIndex == 5 then
                            local room5Model = activeRaidModel and activeRaidModel:FindFirstChild("A05_Teahouse")
                            local door6 = activeRaidModel and activeRaidModel:FindFirstChild("A06_Kennel") and activeRaidModel.A06_Kennel:FindFirstChild("Scripted") and activeRaidModel.A06_Kennel.Scripted:FindFirstChild("HallowDoor")
                            local room6Entry = activeRaidModel and activeRaidModel:FindFirstChild("A06_Kennel") and activeRaidModel.A06_Kennel:FindFirstChild("Markers") and activeRaidModel.A06_Kennel.Markers:FindFirstChild("HallowEntry")

                            local isRoom6Open = false
                            if door6 then
                                local leafL6 = door6:FindFirstChild("LeafL")
                                local leafR6 = door6:FindFirstChild("LeafR")
                                if leafL6 and leafR6 and leafL6:IsA("BasePart") and leafR6:IsA("BasePart") then
                                    if not leafL6.CanCollide or not leafR6.CanCollide or (leafL6.Position - leafR6.Position).Magnitude > 7.5 then
                                        isRoom6Open = true
                                    end
                                end
                                if door6:GetAttribute("Open") == true or door6:GetAttribute("Opened") == true then
                                    isRoom6Open = true
                                end
                            end
                            if not isRoom6Open and room6Entry and room6Entry:IsA("BasePart") then
                                if (hrp.Position - room6Entry.Position).Magnitude < 40 then
                                    isRoom6Open = true
                                end
                            end

                            if not isRoom6Open and room5Model and os.clock() - lastRaidActionTime >= 0.8 then
                                for _, prompt in ipairs(room5Model:GetDescendants()) do
                                    if prompt:IsA("ProximityPrompt") and prompt.Enabled then
                                        local act = (prompt.ActionText or ""):lower()
                                        if not act:find("talk") and not act:find("shop") and not act:find("hide") then
                                            local p = prompt.Parent:IsA("BasePart") and prompt.Parent or (prompt.Parent and prompt.Parent:FindFirstChildWhichIsA("BasePart", true))
                                            if p then
                                                lastRaidActionTime = os.clock()
                                                hrp.CFrame = CFrame.new(p.Position + Vector3.new(0, 3, 0))
                                                if typeof(fireproximityprompt) == "function" then
                                                    fireproximityprompt(prompt)
                                                end
                                                break
                                            end
                                        end
                                    end
                                end
                            end

                            if isRoom6Open or timeInRoom >= 12.0 then
                                if hallowStatusLabel then hallowStatusLabel.Text = "🍵 [5/10 末茶樓] ผ่านโรงน้ำชาแล้ว! มุ่งหน้าไปห้อง 6 (บอส Cerberus)..." end
                                currentRaidRoomIndex = 6
                                roomEnterTime = os.clock()
                                lastRaidActionTime = os.clock()
                                local nextPos = getRoomTargetPosition(6, activeRaidModel)
                                if nextPos then
                                    hrp.CFrame = CFrame.new(nextPos + Vector3.new(0, 3, 0))
                                end
                                task.wait(1.0)
                            else
                                if hallowStatusLabel then
                                    hallowStatusLabel.Text = string.format("🍵 [5/10 末茶樓] กำลังผ่านโรงน้ำชา... (%.0fs)", timeInRoom)
                                end
                            end

                        -- ========================================================
                        -- ROOM 6: คอกสุนัขหยิน (บอส Cerberus Jiangshi [Lv.90])
                        -- ========================================================
                        elseif currentRaidRoomIndex == 6 then
                            local room6Model = activeRaidModel and activeRaidModel:FindFirstChild("A06_Kennel")
                            local cerberusBoss = nil
                            local bestDist = math.huge
                            local hrpPos = hrp.Position
                            local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")

                            local function checkCerberus(npc)
                                if isHallowFoe(npc) and isAlive(npc) then
                                    local nLow = npc.Name:lower()
                                    if nLow:find("cerberus") or nLow:find("hound") or nLow:find("dog") then
                                        local part = getNPCRootPart(npc)
                                        if part then
                                            local d = (part.Position - hrpPos).Magnitude
                                            if d < bestDist then
                                                bestDist = d
                                                cerberusBoss = npc
                                            end
                                        end
                                    end
                                end
                            end

                            if npcsFolder then
                                for _, npc in ipairs(npcsFolder:GetChildren()) do checkCerberus(npc) end
                            end
                            if not cerberusBoss and room6Model then
                                for _, desc in ipairs(room6Model:GetDescendants()) do
                                    if desc:IsA("Model") then checkCerberus(desc) end
                                end
                            end
                            if not cerberusBoss and npcsFolder then
                                for _, npc in ipairs(npcsFolder:GetChildren()) do
                                    if isHallowFoe(npc) and isAlive(npc) then
                                        local part = getNPCRootPart(npc)
                                        if part and (part.Position - hrpPos).Magnitude < 160 then
                                            cerberusBoss = npc
                                            break
                                        end
                                    end
                                end
                            end

                            if cerberusBoss then
                                lastRaidActionTime = os.clock()
                                local targetPart = getNPCRootPart(cerberusBoss)
                                if targetPart then
                                    currentTarget = cerberusBoss
                                    applyHitboxToNPC(cerberusBoss)
                                    revealInvisibleNPC(cerberusBoss)
                                    hrp.CFrame = targetPart.CFrame * CFrame.new(0, 0, 4)
                                    combatRemote = combatRemote or findCombatRemote()
                                    if combatRemote then
                                        pcall(function() combatRemote:FireServer("Attack") end)
                                    end
                                    if isAutoArtifact and os.clock() - lastArtifactUsed >= artifactCooldown then
                                        lastArtifactUsed = os.clock()
                                        useArtifact(targetPart.Position)
                                    end
                                    if hallowStatusLabel then
                                        hallowStatusLabel.Text = "🐕 [6/10 陰門獒院] กำลังกำจัดมินิบอส: Cerberus Jiangshi!"
                                    end
                                end
                            else
                                if os.clock() - lastRaidActionTime >= 3.5 or timeInRoom >= 25.0 then
                                    if hallowStatusLabel then hallowStatusLabel.Text = "🐕 [6/10 陰門獒院] บอส Cerberus ตายแล้ว! มุ่งหน้าลงห้อง 7 (The Throat)..." end
                                    currentRaidRoomIndex = 7
                                    roomEnterTime = os.clock()
                                    lastRaidActionTime = os.clock()
                                    local nextPos = getRoomTargetPosition(7, activeRaidModel)
                                    if nextPos then
                                        hrp.CFrame = CFrame.new(nextPos + Vector3.new(0, 3, 0))
                                    end
                                    task.wait(1.0)
                                else
                                    if hallowStatusLabel then
                                        hallowStatusLabel.Text = string.format("⏳ [6/10 陰門獒院] รอเกิด/ค้นหาบอส Cerberus... (%.0fs)", timeInRoom)
                                    end
                                end
                            end

                        -- ========================================================
                        -- ROOM 7: บ่อน้ำดิ่งลงไปข้างล่าง (The Throat - 咽井)
                        -- ========================================================
                        elseif currentRaidRoomIndex == 7 then
                            local room7Model = activeRaidModel and activeRaidModel:FindFirstChild("A07_Throat")
                            local room8Entry = activeRaidModel and activeRaidModel:FindFirstChild("A08_Banquet") and activeRaidModel.A08_Banquet:FindFirstChild("Markers") and activeRaidModel.A08_Banquet.Markers:FindFirstChild("HallowEntry")

                            if room7Model and os.clock() - lastRaidActionTime >= 0.8 then
                                for _, prompt in ipairs(room7Model:GetDescendants()) do
                                    if prompt:IsA("ProximityPrompt") and prompt.Enabled then
                                        local act = (prompt.ActionText or ""):lower()
                                        if not act:find("talk") and not act:find("shop") and not act:find("hide") then
                                            local p = prompt.Parent:IsA("BasePart") and prompt.Parent or (prompt.Parent and prompt.Parent:FindFirstChildWhichIsA("BasePart", true))
                                            if p then
                                                lastRaidActionTime = os.clock()
                                                hrp.CFrame = CFrame.new(p.Position + Vector3.new(0, 3, 0))
                                                if typeof(fireproximityprompt) == "function" then
                                                    fireproximityprompt(prompt)
                                                end
                                                break
                                            end
                                        end
                                    end
                                end
                            end

                            if timeInRoom >= 8.0 or (room8Entry and (hrp.Position - room8Entry.Position).Magnitude < 40) then
                                if hallowStatusLabel then hallowStatusLabel.Text = "🕳️ [7/10 咽井] ดิ่งลงบ่อน้ำเรียบร้อย! มุ่งหน้าไปห้อง 8 (งานเลี้ยงผีหิว)..." end
                                currentRaidRoomIndex = 8
                                roomEnterTime = os.clock()
                                lastRaidActionTime = os.clock()
                                local nextPos = getRoomTargetPosition(8, activeRaidModel)
                                if nextPos then
                                    hrp.CFrame = CFrame.new(nextPos + Vector3.new(0, 3, 0))
                                end
                                task.wait(1.0)
                            else
                                if hallowStatusLabel then
                                    hallowStatusLabel.Text = string.format("🕳️ [7/10 咽井] กำลังผ่านบ่อน้ำ The Throat... (%.0fs)", timeInRoom)
                                end
                            end

                        -- ========================================================
                        -- ROOM 8: งานเลี้ยงผีหิว (Banquet of the Hungry - 餓鬼宴)
                        -- ========================================================
                        elseif currentRaidRoomIndex == 8 then
                            local room8Model = activeRaidModel and activeRaidModel:FindFirstChild("A08_Banquet")
                            local door9 = activeRaidModel and activeRaidModel:FindFirstChild("A09_EmptyBelly") and activeRaidModel.A09_EmptyBelly:FindFirstChild("Scripted") and activeRaidModel.A09_EmptyBelly.Scripted:FindFirstChild("HallowDoor")
                            
                            local banquetFoe = nil
                            local bestDist = math.huge
                            local hrpPos = hrp.Position
                            local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")

                            local function checkBanquetFoe(npc)
                                if isHallowFoe(npc) and isAlive(npc) then
                                    local part = getNPCRootPart(npc)
                                    if part then
                                        local d = (part.Position - hrpPos).Magnitude
                                        if d < bestDist and d < 200 then
                                            bestDist = d
                                            banquetFoe = npc
                                        end
                                    end
                                end
                            end

                            if npcsFolder then
                                for _, npc in ipairs(npcsFolder:GetChildren()) do checkBanquetFoe(npc) end
                            end
                            if not banquetFoe and room8Model then
                                for _, desc in ipairs(room8Model:GetDescendants()) do
                                    if desc:IsA("Model") then checkBanquetFoe(desc) end
                                end
                            end

                            if banquetFoe then
                                lastRaidActionTime = os.clock()
                                local targetPart = getNPCRootPart(banquetFoe)
                                if targetPart then
                                    currentTarget = banquetFoe
                                    applyHitboxToNPC(banquetFoe)
                                    revealInvisibleNPC(banquetFoe)
                                    hrp.CFrame = targetPart.CFrame * CFrame.new(0, 0, 3)
                                    combatRemote = combatRemote or findCombatRemote()
                                    if combatRemote then
                                        pcall(function() combatRemote:FireServer("Attack") end)
                                    end
                                    if isAutoArtifact and os.clock() - lastArtifactUsed >= artifactCooldown then
                                        lastArtifactUsed = os.clock()
                                        useArtifact(targetPart.Position)
                                    end
                                    if hallowStatusLabel then
                                        hallowStatusLabel.Text = "🍽️ [8/10 餓鬼宴] กำลังกำจัดผีหิว Hungry Ghost ในงานเลี้ยง..."
                                    end
                                end
                            else
                                local isRoom9Open = false
                                if door9 then
                                    local leafL9 = door9:FindFirstChild("LeafL")
                                    local leafR9 = door9:FindFirstChild("LeafR")
                                    if leafL9 and leafR9 and leafL9:IsA("BasePart") and leafR9:IsA("BasePart") then
                                        if not leafL9.CanCollide or not leafR9.CanCollide or (leafL9.Position - leafR9.Position).Magnitude > 7.5 then
                                            isRoom9Open = true
                                        end
                                    end
                                    if door9:GetAttribute("Open") == true or door9:GetAttribute("Opened") == true then
                                        isRoom9Open = true
                                    end
                                end

                                if isRoom9Open or os.clock() - lastRaidActionTime >= 3.5 or timeInRoom >= 20.0 then
                                    if hallowStatusLabel then hallowStatusLabel.Text = "🍽️ [8/10 餓鬼宴] เคลียร์ห้องงานเลี้ยงแล้ว! มุ่งหน้าไปห้อง 9 (บอสใหญ่ Matriarch)..." end
                                    currentRaidRoomIndex = 9
                                    roomEnterTime = os.clock()
                                    lastRaidActionTime = os.clock()
                                    local nextPos = getRoomTargetPosition(9, activeRaidModel)
                                    if nextPos then
                                        hrp.CFrame = CFrame.new(nextPos + Vector3.new(0, 3, 0))
                                    end
                                    task.wait(1.0)
                                else
                                    if hallowStatusLabel then
                                        hallowStatusLabel.Text = string.format("⏳ [8/10 餓鬼宴] ค้นหาผีหิวในงานเลี้ยง... (%.0fs)", timeInRoom)
                                    end
                                end
                            end

                        -- ========================================================
                        -- ROOM 9: ท้องว่าง (บอสใหญ่ Hungry Ghost Matriarch [Lv.110])
                        -- ========================================================
                        elseif currentRaidRoomIndex == 9 then
                            local room9Model = activeRaidModel and activeRaidModel:FindFirstChild("A09_EmptyBelly")
                            local matriarchBoss = nil
                            local bestDist = math.huge
                            local hrpPos = hrp.Position
                            local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")

                            local function checkMatriarch(npc)
                                if isHallowFoe(npc) and isAlive(npc) then
                                    local nLow = npc.Name:lower()
                                    if nLow:find("matriarch") or nLow:find("mother") or nLow:find("queen") then
                                        local part = getNPCRootPart(npc)
                                        if part then
                                            local d = (part.Position - hrpPos).Magnitude
                                            if d < bestDist then
                                                bestDist = d
                                                matriarchBoss = npc
                                            end
                                        end
                                    end
                                end
                            end

                            if npcsFolder then
                                for _, npc in ipairs(npcsFolder:GetChildren()) do checkMatriarch(npc) end
                            end
                            if not matriarchBoss and room9Model then
                                for _, desc in ipairs(room9Model:GetDescendants()) do
                                    if desc:IsA("Model") then checkMatriarch(desc) end
                                end
                            end
                            if not matriarchBoss and npcsFolder then
                                for _, npc in ipairs(npcsFolder:GetChildren()) do
                                    if isHallowFoe(npc) and isAlive(npc) then
                                        local part = getNPCRootPart(npc)
                                        if part and (part.Position - hrpPos).Magnitude < 180 then
                                            matriarchBoss = npc
                                            break
                                        end
                                    end
                                end
                            end

                            if matriarchBoss then
                                lastRaidActionTime = os.clock()
                                local targetPart = getNPCRootPart(matriarchBoss)
                                if targetPart then
                                    currentTarget = matriarchBoss
                                    applyHitboxToNPC(matriarchBoss)
                                    revealInvisibleNPC(matriarchBoss)
                                    hrp.CFrame = targetPart.CFrame * CFrame.new(0, 0, 4)
                                    combatRemote = combatRemote or findCombatRemote()
                                    if combatRemote then
                                        pcall(function() combatRemote:FireServer("Attack") end)
                                    end
                                    if isAutoArtifact and os.clock() - lastArtifactUsed >= artifactCooldown then
                                        lastArtifactUsed = os.clock()
                                        useArtifact(targetPart.Position)
                                    end
                                    if hallowStatusLabel then
                                        hallowStatusLabel.Text = "👑 [9/10 空腹] กำลังกำจัดบอสใหญ่: Hungry Ghost Matriarch!"
                                    end
                                end
                            else
                                if os.clock() - lastRaidActionTime >= 3.5 or timeInRoom >= 30.0 then
                                    if hallowStatusLabel then hallowStatusLabel.Text = "👑 [9/10 空腹] บอสใหญ่ตายแล้ว! มุ่งหน้าไปห้อง 10 (รับรางวัล)..." end
                                    currentRaidRoomIndex = 10
                                    roomEnterTime = os.clock()
                                    lastRaidActionTime = os.clock()
                                    local nextPos = getRoomTargetPosition(10, activeRaidModel)
                                    if nextPos then
                                        hrp.CFrame = CFrame.new(nextPos + Vector3.new(0, 3, 0))
                                    end
                                    task.wait(1.0)
                                else
                                    if hallowStatusLabel then
                                        hallowStatusLabel.Text = string.format("⏳ [9/10 空腹] ค้นหาบอสใหญ่ Matriarch... (%.0fs)", timeInRoom)
                                    end
                                end
                            end

                        -- ========================================================
                        -- ROOM 10: จบด่าน รับของรางวัล (The Moon Returns - 月歸)
                        -- ========================================================
                        elseif currentRaidRoomIndex == 10 then
                            local room10Model = activeRaidModel and activeRaidModel:FindFirstChild("A10_MoonReturns")
                            local moonbeam = room10Model and room10Model:FindFirstChild("Scripted") and room10Model.Scripted:FindFirstChild("HallowMoonbeam")
                            local clothHeap = room10Model and room10Model:FindFirstChild("Scripted") and (room10Model.Scripted:FindFirstChild("HallowClothHeap") or room10Model.Scripted:FindFirstChild("HallowRobeHeap"))

                            local rewardTarget = moonbeam or clothHeap or (room10Model and room10Model:FindFirstChild("Markers") and room10Model.Markers:FindFirstChild("HallowEntry"))
                            if rewardTarget then
                                local prompt = rewardTarget:FindFirstChildWhichIsA("ProximityPrompt", true)
                                local p = prompt and prompt.Parent:IsA("BasePart") and prompt.Parent or rewardTarget:FindFirstChildWhichIsA("BasePart", true)
                                if p then
                                    hrp.CFrame = CFrame.new(p.Position + Vector3.new(0, 3, 0))
                                    if prompt and prompt.Enabled and typeof(fireproximityprompt) == "function" then
                                        fireproximityprompt(prompt)
                                    end
                                end
                            end

                            if hallowStatusLabel then
                                hallowStatusLabel.Text = "🏆 [10/10 月歸] เคลียร์ครบ 10 ห้องสำเร็จ! ได้รับของรางวัลเรียบร้อย (รอวนรอบใหม่)..."
                            end

                            if isHallowAutoRepeat then
                                task.wait(4.0)
                            end
                        end
                    end
                end
            end
            task.wait(0.04)
        else
            if hallowStatusLabel and hallowStatusLabel.Text ~= "💤 ระบบออโต้ด่านฮาโลวีนปิดอยู่" and not isAutoHallowRaid then
                hallowStatusLabel.Text = "💤 ระบบออโต้ด่านฮาโลวีนปิดอยู่"
            end
            task.wait(0.5)
        end
    end
end)

-- อีเวนต์ปุ่มเปิดปิด GUI
toggleBtn.MouseButton1Click:Connect(function()
	mainFrame.Visible = not mainFrame.Visible
	if mainFrame.Visible then refreshNPCList() end
end)

closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)
startBtn.MouseButton1Click:Connect(function() startFarming() end)
stopBtn.MouseButton1Click:Connect(function()
    stopAll()
    if hubUI.stopWorkshop then hubUI.stopWorkshop() end
end)
local function cleanup()
    if destroyed then return end
    destroyed = true
    stopAll()
    if isParrying and combatRemote then
        pcall(function() combatRemote:FireServer("ParryUp", nil) end)
    end
    isParrying = false
    if artifactTask then task.cancel(artifactTask) artifactTask = nil end
    restoreHitboxes()
    for _, conn in ipairs(folderConnections) do conn:Disconnect() end
    for _, conn in ipairs(externalConnections) do conn:Disconnect() end
    table.clear(folderConnections)
    table.clear(externalConnections)
end
screenGui.Destroying:Connect(cleanup)
destroyBtn.MouseButton1Click:Connect(function()
    cleanup()
    screenGui:Destroy()
end)
-- The supplied main window remains the only visible menu.
hubUI.gui = screenGui
hubUI.frame = mainFrame
hubUI.stopFarm = stopAll
hubUI.refresh = refreshNPCList
return hubUI

end

local function mountWorkshop(host)
-- Murim Workshop: Alchemy + Forge. Run this entire file as one script.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

_G.ArtificeAuto = false

if _G.ArtificeTapConnection then
    _G.ArtificeTapConnection:Disconnect()
    _G.ArtificeTapConnection = nil
end

local function need(parent, name)
    local item = parent:FindFirstChild(name) or parent:WaitForChild(name, 5)
    assert(item, "ไม่พบ " .. parent.Name .. "." .. name .. " ภายใน 5 วินาที")
    return item
end
local remotes = need(need(RS, "Murim"), "Remotes")
local remote = need(remotes, "Artifice")
local forgeRemote = need(remotes, "ArtificeRequest")
local alchemyRequest = need(remotes, "AlchemyRequest")
local minigameRemote = need(remotes, "Minigame")
local alchemyAuto, alchemyHit, alchemyBusy = false, false, false
local alchemyActive, alchemyPending, generalMinigameActive = false, false, false
local alchemyPendingAt, alchemyNextAt, alchemyCount, beatVersion = 0, 0, 0, 0
local alchemyRequestVersion = 0
local refreshAlchemy
local breakthroughEnabled, breakthroughToken = false, 0
local qiAuto, tribAuto, minorAuto = false, false, true
local minorHitCount, minorTotalHits = 0, 0
local cultStatus, cultResult, cultCounter, updateCultCounter
local cultivationPhase
local cultRemote = need(remotes, "Cultivation")
local refreshBreakthrough
local enabled, closed = false, false
local connections = {}
local sent = setmetatable({}, { __mode = "k" })
local sentCount, successCount, missedCount = 0, 0, 0
local lastId
local forgeEnabled, forgeBusy, awaitingGame, gameActive = false, false, false, false
local awaitingSince, nextForgeAt, forgeCount = 0, 0, 0
local MAX_ATTEMPTS, RETRY_DELAY = 3, 0.2

local function connect(signal, callback)
    local c = signal:Connect(callback)
    connections[#connections + 1] = c
    return c
end
local function create(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = parent
    return object
end

local gui = host.gui
local panel = create("Frame", {
    Visible = false, Size = UDim2.fromOffset(330, 435), Position = UDim2.new(0.5, -165, 0.12, 0),
    BackgroundColor3 = Color3.fromRGB(28, 28, 34), BorderSizePixel = 0,
}, gui)
create("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
create("UIStroke", { Color = Color3.fromRGB(195, 159, 77), Thickness = 1.5 }, panel)
local function label(text, y, height, color)
    return create("TextLabel", {
        Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, height),
        BackgroundTransparency = 1, Text = text, TextSize = 14,
        TextColor3 = color or Color3.fromRGB(225, 225, 230),
        Font = Enum.Font.Gotham, TextWrapped = true,
    }, panel)
end
local title = label("Artifice Auto", 0, 42, Color3.fromRGB(235, 205, 132))
title.Size = UDim2.new(1, -65, 0, 42)
title.TextSize = 19
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
local close = create("TextButton", {
    Position = UDim2.new(1, -42, 0, 4), Size = UDim2.fromOffset(36, 36),
    BackgroundTransparency = 1, Text = "×", TextSize = 28,
    TextColor3 = Color3.fromRGB(255, 115, 115), Font = Enum.Font.GothamBold,
}, panel)
local function makeButton(text, y, color)
    local b = create("TextButton", {
        Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, 42),
        BackgroundColor3 = color, BorderSizePixel = 0, Text = text, TextSize = 17,
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold,
    }, panel)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
    return b
end
local toggle = makeButton("เปิด Auto กด", 50, Color3.fromRGB(57, 132, 89))
local status = label("สถานะ: หยุด", 100, 28)
label("เลขน้อยก่อน • ข้ามสี [255, 80, 40]", 130, 26, Color3.fromRGB(235, 205, 132))
label("ลองได้สูงสุด 3 ครั้ง / ห่าง 0.2 วินาที", 157, 24)
local skipped = label("เลขที่ข้าม: -", 183, 45, Color3.fromRGB(255, 145, 125))
local lastLabel = label("ส่งล่าสุด: -", 231, 24)
local counter = label("ส่ง: 0 | สำเร็จ: 0 | จม: 0", 258, 24)
local resultLabel = label("ผลจากเกม: ยังไม่มี", 285, 28)
local forgeButton = makeButton("เปิด Auto Forge", 326, Color3.fromRGB(66, 105, 165))
local forgeStatus = label("Forge: หยุด", 373, 48)

local dragArea = create("Frame", {
    Size = UDim2.new(1, -50, 0, 42), BackgroundTransparency = 1, Active = true, ZIndex = 5,
}, panel)
local dragInput, dragStart, panelStart
connect(dragArea.InputBegan, function(input)
    if closed or dragInput then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragInput, dragStart, panelStart = input, input.Position, panel.Position
    end
end)
connect(UIS.InputChanged, function(input)
    if closed or not dragInput then return end
    local mouse = dragInput.UserInputType == Enum.UserInputType.MouseButton1
    if (mouse and input.UserInputType == Enum.UserInputType.MouseMovement) or input == dragInput then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + delta.X,
            panelStart.Y.Scale, panelStart.Y.Offset + delta.Y)
    end
end)
connect(UIS.InputEnded, function(input) if input == dragInput then dragInput = nil end end)
connect(UIS.WindowFocusReleased, function() dragInput = nil end)

local cleanup
local function stopConnections()
    closed, enabled, forgeEnabled = true, false, false
    breakthroughEnabled = false
    qiAuto, tribAuto = false, false
    breakthroughToken += 1
    alchemyAuto, alchemyHit = false, false
    beatVersion += 1
    dragInput = nil
    for _, c in ipairs(connections) do c:Disconnect() end
    table.clear(connections)
    if _G.ArtificeGuiCleanup == cleanup then _G.ArtificeGuiCleanup = nil end
end
cleanup = function()
    if closed then return end
    stopConnections()
    gui:Destroy()
end
_G.ArtificeGuiCleanup = cleanup
connect(close.Activated, cleanup)
connect(gui.Destroying, function() if not closed then stopConnections() end end)
local function paintTap()
    toggle.Text = enabled and "หยุด Auto กด" or "เปิด Auto กด"
    toggle.BackgroundColor3 = enabled and Color3.fromRGB(165, 66, 66) or Color3.fromRGB(57, 132, 89)
end
connect(toggle.Activated, function() enabled = not enabled; paintTap() end)

local function getMotes(requireVisible)
    local gameGui = playerGui:FindFirstChild("MurimArtificeGame")
    if not gameGui or not gameGui:IsA("ScreenGui") then return nil end
    if requireVisible and not gameGui.Enabled then return nil end
    local current = gameGui
    for _, name in ipairs({ "Sheet", "Area", "Face", "Motes" }) do
        current = current:FindFirstChild(name)
        if not current then return nil end
        if requireVisible and current:IsA("GuiObject") and not current.Visible then return nil end
    end
    return current
end
local function gameIsVisible()
    local g = playerGui:FindFirstChild("MurimArtificeGame")
    return g and g:IsA("ScreenGui") and g.Enabled
end
local function getId(button)
    if not button:IsA("TextButton") then return nil end
    return tonumber(button.Name:match("^Mote(%d+)$"))
end
local function classify(button)
    local id = getId(button)
    if not id then return nil end
    local c = button.BackgroundColor3
    local r, g, b = math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)
    if r == 255 and g == 80 and b == 40 then return id, "skip" end
    if (r == 255 and g == 240 and b == 190) or (r == 58 and g == 52 and b == 50) then return id, "tap" end
    return id, "unknown"
end
local function updateCounter()
    counter.Text = string.format("ส่ง: %d | สำเร็จ: %d | จม: %d", sentCount, successCount, missedCount)
end
local function paintForge()
    forgeButton.Text = forgeEnabled and "หยุด Auto Forge" or "เปิด Auto Forge"
    forgeButton.BackgroundColor3 = forgeEnabled and Color3.fromRGB(165, 66, 66) or Color3.fromRGB(66, 105, 165)
end
local function stopForge(message)
    forgeEnabled = false
    paintForge()
    forgeStatus.Text = message
end
connect(forgeButton.Activated, function()
    if forgeEnabled then stopForge("Forge: หยุดเริ่มรอบใหม่"); return end
    if awaitingGame and not forgeBusy and os.clock() - awaitingSince > 10 then
        forgeStatus.Text = "Forge: ยังไม่ยืนยันคำขอก่อนหน้า"
        return
    end
    alchemyAuto = false
    alchemyRequestVersion += 1
    if refreshAlchemy then refreshAlchemy() end
    forgeEnabled, enabled = true, true
    paintForge()
    paintTap()
    forgeStatus.Text = "Forge: รอเริ่ม / รอรอบปัจจุบันจบ"
end)

connect(remote.OnClientEvent, function(data)
    if closed or type(data) ~= "table" or data.valley then return end
    if data.op == "Game" then
        gameActive, awaitingGame = true, false
        if forgeEnabled then forgeStatus.Text = "Forge: กำลังเล่นรอบปัจจุบัน" end
        return
    elseif data.op == "End" then
        gameActive, awaitingGame = false, false
        nextForgeAt = os.clock() + 3.2
        if forgeEnabled then forgeStatus.Text = "Forge: จบรอบ รอรอบถัดไป" end
        return
    end
    if data.op ~= "Mote" then return end
    local motes = getMotes(false)
    local button = motes and motes:FindFirstChild("Mote" .. tostring(data.i))
    local alreadyFinished = button and sent[button] == true
    if button then sent[button] = true end
    if not alreadyFinished then
        if data.r == "got" or data.r == "struck" then successCount += 1
        elseif data.r == "sank" then missedCount += 1 end
    end
    local names = { got = "เก็บสำเร็จ", struck = "ตีสำเร็จ", burnt = "โดนสี่เหลี่ยมแดง", sank = "จม / ไม่ทัน" }
    resultLabel.Text = "Mote" .. tostring(data.i) .. ": " .. (names[data.r] or tostring(data.r))
    updateCounter()
end)

local nextDisplayUpdate = 0
connect(RunService.Heartbeat, function()
    if closed then return end
    local motes = getMotes(true)
    if not motes then
        local tSkip = "เลขที่ข้าม: -"
        local tStat = enabled and "สถานะ: รอมินิเกม" or "สถานะ: หยุด"
        if skipped.Text ~= tSkip then skipped.Text = tSkip end
        if status.Text ~= tStat then status.Text = tStat end
        return
    end
    local entries, skipIds = {}, {}
    local unknownCount = 0
    for _, button in ipairs(motes:GetChildren()) do
        local id = getId(button)
        if id then entries[#entries + 1] = { id = id, button = button } end
    end
    table.sort(entries, function(a, b) return a.id < b.id end)
    for _, entry in ipairs(entries) do
        local button = entry.button
        if button.Parent ~= motes then continue end
        local id, kind = classify(button)
        if kind == "skip" then skipIds[#skipIds + 1] = id
        elseif kind == "unknown" and button.Visible then unknownCount += 1
        elseif kind == "tap" and enabled and button.Visible then
            local now, attempt = os.clock(), sent[button]
            if attempt ~= true then
                local first = attempt == nil
                local retry = type(attempt) == "table" and attempt.count < MAX_ATTEMPTS and now - attempt.last >= RETRY_DELAY
                if first or retry then
                    sent[button] = { count = first and 1 or attempt.count + 1, last = now }
                    remote:FireServer({ op = "Tap", i = id })
                    sentCount += 1
                    lastId = id
                end
            end
        end
    end
    local now = os.clock()
    if now < nextDisplayUpdate then return end
    nextDisplayUpdate = now + 0.1
    local display = {}
    for index, id in ipairs(skipIds) do
        if index > 20 then display[#display + 1] = "…"; break end
        display[#display + 1] = tostring(id)
    end
    local newSkip = "เลขที่ข้าม: " .. (#display > 0 and table.concat(display, ", ") or "-")
    if skipped.Text ~= newSkip then skipped.Text = newSkip end
    local newStat = enabled and (unknownCount > 0 and ("ทำงาน • สีไม่ตรงเงื่อนไข " .. unknownCount .. " จุด") or "สถานะ: Auto ทำงาน") or "สถานะ: หยุด • ตรวจเลขอย่างเดียว"
    if status.Text ~= newStat then status.Text = newStat end
    local newLast = "ส่งล่าสุด: " .. (lastId and ("Mote" .. lastId) or "-")
    if lastLabel.Text ~= newLast then lastLabel.Text = newLast end
    updateCounter()
end)

connect(RunService.Heartbeat, function()
    if closed or not forgeEnabled then return end
    if not enabled then
        local tFStat = "Forge: พักอยู่ กรุณาเปิด Auto กด"
        if forgeStatus.Text ~= tFStat then forgeStatus.Text = tFStat end
        return
    end
    if forgeBusy then return end
    if awaitingGame then
        if os.clock() - awaitingSince > 10 then stopForge("Forge: ไม่ได้รับสัญญาณเริ่มเกม หยุดส่งซ้ำ") end
        return
    end
    if gameActive or gameIsVisible() or os.clock() < nextForgeAt then return end
    if cultivationPhase or alchemyBusy or alchemyPending or alchemyActive or generalMinigameActive then
        local tFStat = "Forge: รอมินิเกมอื่นจบ"
        if forgeStatus.Text ~= tFStat then forgeStatus.Text = tFStat end
        return
    end
    forgeBusy, awaitingGame = true, true
    awaitingSince = os.clock()
    forgeStatus.Text = "Forge: กำลังขอเริ่มรอบ..."
    task.spawn(function()
        if closed or not forgeEnabled or not enabled or cultivationPhase or alchemyBusy or alchemyPending or alchemyActive or generalMinigameActive then
            forgeBusy, awaitingGame = false, false
            return
        end
        local ok, accepted, message = pcall(function()
            return forgeRemote:InvokeServer("Forge", {
                recipe = "D6", flame = "WitheringEmber",
                core = { id = "WitheredSoulCore", grade = 1 },
            })
        end)
        forgeBusy = false
        if closed then return end
        if not ok then stopForge("Forge: ติดต่อไม่สำเร็จ — " .. tostring(accepted)); return end
        if not accepted then
            awaitingGame = false
            stopForge("Forge: " .. tostring(message or "เซิร์ฟเวอร์ไม่รับคำขอ"))
            return
        end
        forgeCount += 1
        if forgeEnabled then
            forgeStatus.Text = "Forge: รับคำขอแล้ว " .. forgeCount .. " รอบ" .. (awaitingGame and " รอเริ่ม" or "")
        end
    end)
end)


-- Unified interface: preserve the working Forge controls inside their own tab.
panel.Size = UDim2.fromOffset(360, 545)
panel.Position = UDim2.new(0.5, -180, 0.5, -272)
title.Text = "Murim Workshop v4"
title.Size = UDim2.new(1, -110, 0, 42)
dragArea.Size = UDim2.new(1, -100, 0, 42)
local oldControls = {}
for _, child in ipairs(panel:GetChildren()) do
    if child:IsA("GuiObject") and child ~= title and child ~= close and child ~= dragArea then
        oldControls[#oldControls + 1] = child
    end
end
local forgePage = create("Frame", {
    Name = "ForgePage", Position = UDim2.fromOffset(0, 96),
    Size = UDim2.new(1, 0, 0, 390), BackgroundTransparency = 1,
}, panel)
for _, child in ipairs(oldControls) do
    child.Position = UDim2.new(child.Position.X.Scale, child.Position.X.Offset,
        child.Position.Y.Scale, child.Position.Y.Offset - 50)
    child.Parent = forgePage
end
local alchemyPage = create("Frame", {
    Name = "AlchemyPage", Position = UDim2.fromOffset(0, 96),
    Size = UDim2.new(1, 0, 0, 390), BackgroundTransparency = 1, Visible = false,
}, panel)
local function pageLabel(parent, text, y, height, size)
    return create("TextLabel", {
        Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, height),
        BackgroundTransparency = 1, Text = text, TextWrapped = true,
        TextSize = size or 14, Font = Enum.Font.Gotham,
        TextColor3 = Color3.fromRGB(225, 225, 230),
    }, parent)
end
local function pageButton(parent, text, y, height)
    local b = create("TextButton", {
        Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, height or 40),
        BackgroundColor3 = Color3.fromRGB(54, 65, 82), BorderSizePixel = 0,
        Text = text, TextWrapped = true, TextSize = 15,
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold,
    }, parent)
    create("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
    return b
end
local breakthroughPage = create("Frame", {
    Name = "BreakthroughPage", Position = UDim2.fromOffset(0, 96),
    Size = UDim2.new(1, 0, 0, 390), BackgroundTransparency = 1, Visible = false,
}, panel)
local tabAlchemy = pageButton(panel, "ปรุงยา", 49, 36)
local tabForge = pageButton(panel, "Forge", 49, 36)
local tabBreakthrough = pageButton(panel, "ทะลวงขั้น", 49, 36)
for index, tab in ipairs({ tabAlchemy, tabForge, tabBreakthrough }) do
    tab.Position = UDim2.new((index - 1) / 3, 8, 0, 49)
    tab.Size = UDim2.new(1 / 3, -16, 0, 36)
end
local function selectTab(name)
    alchemyPage.Visible = name == "alchemy"
    forgePage.Visible = name == "forge"
    breakthroughPage.Visible = name == "breakthrough"
    tabAlchemy.BackgroundColor3 = alchemyPage.Visible and Color3.fromRGB(52, 125, 102) or Color3.fromRGB(54, 65, 82)
    tabForge.BackgroundColor3 = forgePage.Visible and Color3.fromRGB(150, 112, 48) or Color3.fromRGB(54, 65, 82)
    tabBreakthrough.BackgroundColor3 = breakthroughPage.Visible and Color3.fromRGB(75, 100, 170) or Color3.fromRGB(54, 65, 82)
end
connect(tabAlchemy.Activated, function() selectTab("alchemy") end)
connect(tabForge.Activated, function() selectTab("forge") end)
connect(tabBreakthrough.Activated, function() selectTab("breakthrough") end)

-- The requested recipe is already present in the supplied script; keep one copy.
local recipes = {
    { name = "1. FrostMoss ×2 + SpiritGrass ×1", ings = {
        { id = "FrostMoss" }, { id = "FrostMoss" }, { id = "SpiritGrass" },
    } },
    { name = "2. Ginseng ×1 + SpiritGrass ×1", ings = {
        { id = "Ginseng" }, { id = "SpiritGrass" },
    } },
}
local selectedRecipe = 1
local recipeButtons = {}
pageLabel(alchemyPage, "เลือกสูตรปรุงยา (กดเลือกได้)", 0, 25, 16)
for index, recipe in ipairs(recipes) do
    local recipeIndex = index
    local b = pageButton(alchemyPage, recipe.name, 31 + (index - 1) * 47, 41)
    recipeButtons[index] = b
    connect(b.Activated, function()
        selectedRecipe = recipeIndex
        if refreshAlchemy then refreshAlchemy() end
    end)
end
local hitButton = pageButton(alchemyPage, "Auto กดจังหวะ: ปิด", 130, 40)
local mixButton = pageButton(alchemyPage, "ผสม 1 รอบ + กดจังหวะ", 178, 40)
local autoAlchemyButton = pageButton(alchemyPage, "เริ่ม Auto ปรุงยา", 226, 40)
local alchemyStatus = pageLabel(alchemyPage, "เลือกสูตร FrostMoss ×2 + SpiritGrass ×1 แล้ว", 273, 52)
local alchemyResult = pageLabel(alchemyPage, "ผลล่าสุด: -", 327, 50)
refreshAlchemy = function()
    for index, b in ipairs(recipeButtons) do
        b.Text = (index == selectedRecipe and "✓ " or "") .. recipes[index].name
        b.BackgroundColor3 = index == selectedRecipe and Color3.fromRGB(52, 125, 102) or Color3.fromRGB(54, 65, 82)
    end
    hitButton.Text = alchemyHit and "Auto กดจังหวะ: เปิด" or "Auto กดจังหวะ: ปิด"
    hitButton.BackgroundColor3 = alchemyHit and Color3.fromRGB(52, 125, 102) or Color3.fromRGB(54, 65, 82)
    autoAlchemyButton.Text = alchemyAuto and "หยุดเริ่มรอบปรุงยาใหม่" or "เริ่ม Auto ปรุงยา"
    autoAlchemyButton.BackgroundColor3 = alchemyAuto and Color3.fromRGB(165, 66, 66) or Color3.fromRGB(52, 125, 102)
end
connect(hitButton.Activated, function()
    alchemyHit = not alchemyHit
    beatVersion += 1
    refreshAlchemy()
end)
local function stopAlchemy(message)
    alchemyAuto = false
    alchemyRequestVersion += 1
    alchemyStatus.Text = message
    refreshAlchemy()
end

-- Wait for Start/End instead of invoking Mix every six seconds.
local function requestMix()
    if closed or alchemyBusy or alchemyPending then return end
    if cultivationPhase or generalMinigameActive or alchemyActive or gameActive or gameIsVisible() or forgeBusy or awaitingGame then
        alchemyStatus.Text = "รอมินิเกม / คำขอปัจจุบันจบก่อน"
        return
    end
    if os.clock() < alchemyNextAt then
        alchemyStatus.Text = "รอหน้าผลลัพธ์ปิดก่อน"
        return
    end
    alchemyBusy, alchemyPending = true, true
    alchemyPendingAt = os.clock()
    local chosen = recipes[selectedRecipe]
    local ingredients = {}
    for index, ingredient in ipairs(chosen.ings) do
        ingredients[index] = { id = ingredient.id }
    end
    alchemyStatus.Text = "กำลังขอผสม: " .. chosen.name
    local requestVersion = alchemyRequestVersion
    task.spawn(function()
        if closed or requestVersion ~= alchemyRequestVersion then
            alchemyBusy, alchemyPending = false, false
            return
        end
        local ok, result, message = pcall(function()
            return alchemyRequest:InvokeServer("Mix", { ings = ingredients })
        end)
        alchemyBusy = false
        if closed then return end
        if not ok then
            stopAlchemy("ติดต่อไม่สำเร็จ หยุดส่งซ้ำ: " .. tostring(result))
            return
        end
        if result == false then
            alchemyPending = false
            stopAlchemy("เริ่มไม่ได้: " .. tostring(message or "เซิร์ฟเวอร์ปฏิเสธ"))
            return
        end
        -- A nil/non-boolean return is not treated as confirmed success.
        if alchemyPending then alchemyStatus.Text = "ส่งคำขอแล้ว รอสัญญาณเริ่มมินิเกม" end
    end)
end
connect(mixButton.Activated, function()
    if closed then return end
    if alchemyPending and os.clock() - alchemyPendingAt > 12 then
        alchemyStatus.Text = "คำขอก่อนหน้ายังไม่ยืนยัน จึงไม่ส่งซ้ำ"
        return
    end
    forgeEnabled, alchemyAuto, alchemyHit = false, false, true
    paintForge()
    refreshAlchemy()
    requestMix()
end)
connect(autoAlchemyButton.Activated, function()
    if alchemyAuto then stopAlchemy("หยุดเริ่มรอบใหม่ • รอบปัจจุบันยังกดต่อ"); return end
    if alchemyPending and os.clock() - alchemyPendingAt > 12 then
        alchemyStatus.Text = "คำขอก่อนหน้ายังไม่ยืนยัน จึงไม่ส่งซ้ำ"
        return
    end
    forgeEnabled, alchemyAuto, alchemyHit = false, true, true
    paintForge()
    refreshAlchemy()
    alchemyStatus.Text = "Auto พร้อม • รอเริ่มตามสูตรที่เลือก"
end)

local currentBeat
connect(minigameRemote.OnClientEvent, function(data)
    if closed or type(data) ~= "table" then return end
    if data.op == "Start" then
        generalMinigameActive = true
        alchemyActive = alchemyPending or (data.kind == "Alchemy")
        alchemyPending = false
        beatVersion += 1
        currentBeat = nil
        if alchemyActive then
            alchemyCount += 1
            alchemyStatus.Text = "กำลังปรุง • เริ่มแล้ว " .. alchemyCount .. " รอบ"
        else
            minorHitCount = 0
            if cultStatus and cultStatus.Parent then
                cultStatus.Text = "เริ่มทะลวงย่อย • กำลังรอจังหวะ Beat"
            end
        end
    elseif data.op == "Beat" then
        generalMinigameActive = true
        local isAlchemy = alchemyActive
        if isAlchemy and not alchemyHit then return end
        if not isAlchemy and not minorAuto then return end

        currentBeat = {}
        local beat = currentBeat
        local version = beatVersion
        local window = tonumber(data.window) or tonumber(data.t) or tonumber(data.lead) or 0.5
        if window < 0 or window > 30 or data.i == nil then return end
        local target = os.clock() + window
        task.delay(window, function()
            if closed or currentBeat ~= beat or version ~= beatVersion then return end
            if isAlchemy and not (alchemyHit and alchemyActive) then return end
            if not isAlchemy and not minorAuto then return end
            local off = os.clock() - target
            minigameRemote:FireServer({ op = "Hit", i = data.i, off = off })
        end)
    elseif data.op == "Hit" or data.op == "Miss" or data.op == "Early" then
        currentBeat = nil
        if alchemyActive then
            alchemyResult.Text = "จังหวะล่าสุด: " .. ({ Hit = "สำเร็จ", Miss = "พลาด", Early = "เร็วเกินไป" })[data.op]
        else
            minorTotalHits += 1
            local opName = ({ Hit = "สำเร็จ ✅", Miss = "พลาด ❌", Early = "เร็วเกินไป ⚠️" })[data.op] or tostring(data.op)
            if cultResult and cultResult.Parent then
                cultResult.Text = "ทะลวงย่อย Beat " .. tostring(data.i or "") .. ": " .. opName
            end
            if updateCultCounter then updateCultCounter() end
        end
    elseif data.op == "End" then
        local wasAlchemy = alchemyActive or alchemyPending
        generalMinigameActive, alchemyActive, alchemyPending = false, false, false
        beatVersion += 1
        currentBeat = nil
        if wasAlchemy then
            alchemyNextAt = os.clock() + 3.2
            alchemyResult.Text = "ผลล่าสุด: " .. tostring(data.text or (data.success and "สำเร็จ" or "จบรอบ"))
            alchemyStatus.Text = alchemyAuto and "จบรอบ • รอเริ่มรอบถัดไป" or "จบรอบแล้ว"
        else
            if cultResult and cultResult.Parent then
                cultResult.Text = "ทะลวงย่อย: " .. (data.success and "ทะลวงสำเร็จ! 🎉" or ("จบรอบ " .. tostring(data.text or "")))
            end
            if cultStatus and cultStatus.Parent then
                cultStatus.Text = "จบรอบทะลวงย่อย • รอเริ่มในเกมเอง"
            end
        end
    end
end)
connect(RunService.Heartbeat, function()
    if closed then return end
    if alchemyPending and not alchemyBusy and os.clock() - alchemyPendingAt > 12 then
        if alchemyAuto then stopAlchemy("ไม่พบสัญญาณเริ่มเกม หยุดส่งซ้ำ") end
        return
    end
    if not alchemyAuto or alchemyBusy or alchemyPending then return end
    if not alchemyHit then
        local tAStat = "พักอยู่ • เปิด Auto กดจังหวะเพื่อทำต่อ"
        if alchemyStatus.Text ~= tAStat then alchemyStatus.Text = tAStat end
        return
    end
    if os.clock() >= alchemyNextAt then requestMix() end
end)

local stopAll = pageButton(panel, "หยุดทั้งหมด", 495, 36)
stopAll.BackgroundColor3 = Color3.fromRGB(150, 55, 55)
local function stopWorkshop()
    enabled, forgeEnabled, alchemyAuto, alchemyHit = false, false, false, false
    breakthroughEnabled = false
    qiAuto, tribAuto, minorAuto = false, false, false
    breakthroughToken += 1
    if refreshBreakthrough then refreshBreakthrough() end
    alchemyRequestVersion += 1
    beatVersion += 1
    paintTap()
    paintForge()
    refreshAlchemy()
    forgeStatus.Text = "Forge: หยุด"
    alchemyStatus.Text = "หยุดทั้งหมดแล้ว"
end
connect(stopAll.Activated, stopWorkshop)
local minimize = create("TextButton", {
    Position = UDim2.new(1, -82, 0, 4), Size = UDim2.fromOffset(36, 36),
    BackgroundTransparency = 1, Text = "−", TextSize = 25,
    TextColor3 = Color3.fromRGB(235, 205, 132), Font = Enum.Font.GothamBold,
}, panel)
local restore = create("TextButton", {
    Position = UDim2.fromOffset(15, 100), Size = UDim2.fromOffset(160, 42),
    BackgroundColor3 = Color3.fromRGB(40, 45, 55), Text = "เปิด Workshop",
    TextSize = 16, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold,
    Visible = false, BorderSizePixel = 0,
}, gui)
create("UICorner", { CornerRadius = UDim.new(0, 8) }, restore)
connect(minimize.Activated, function() panel.Visible = false; restore.Visible = true end)
connect(restore.Activated, function() panel.Visible = true; restore.Visible = false end)
-- Scale the menu to smaller screens without changing the gameplay GUI.
local fit = create("UIScale", { Scale = 1 }, panel)
local function refit()
    local size = gui.AbsoluteSize
    if size.X > 0 and size.Y > 0 then
        fit.Scale = math.min(1, math.max(0.1, math.min((size.X - 24) / 360, (size.Y - 24) / 545)))
        -- Keep the initial centered placement correct after scaling.
        panel.Position = UDim2.new(0.5, -180 * fit.Scale, 0.5, -272.5 * fit.Scale)
    end
end
connect(gui:GetPropertyChangedSignal("AbsoluteSize"), refit)
refreshAlchemy()
selectTab("alchemy")
refit()


-- Cultivation controls derived from UI.Circulation (CircStart / TribStart) & Minigame.
-- Install before starting the trial so the server's schedule can be observed.
pageLabel(breakthroughPage, "ทะลวงขั้น • Breakthrough & Cultivation", 0, 40, 17)
pageLabel(breakthroughPage, "เปิดปุ่มที่ต้องการ แล้วเริ่มทะลวงในเกมเอง", 43, 40, 13)
local minorButton = pageButton(breakthroughPage, "Auto ทะลวงย่อย (กดจังหวะ): เปิด", 90, 43)
local qiButton = pageButton(breakthroughPage, "Qi Circulation: ปิด", 140, 43)
local tribButton = pageButton(breakthroughPage, "Heavenly Tribulation: ปิด", 190, 43)
cultStatus = pageLabel(breakthroughPage, "รอข้อมูลรอบใหม่จากเกม", 243, 45)
cultResult = pageLabel(breakthroughPage, "ผลล่าสุด: -", 292, 44)
cultCounter = pageLabel(breakthroughPage, "Click: 0 | Ward: 0 | Tap: 0 | Hit ย่อย: 0", 340, 30, 13)
pageLabel(breakthroughPage, "Qi/Trib: ทะลวงขั้นใหญ่ • ทะลวงย่อย: กดจังหวะอัตโนมัติ 100%\nไม่เริ่มรอบ ไม่ใช้วัตถุดิบ และไม่รีเซ็ตเลเวล", 378, 48, 12)
local circulation, tribulation
local clickCount, wardCount, tapCount = 0, 0, 0
local wardReadyAt = 0
local latestPaint = 0
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
updateCultCounter = function()
    if cultCounter and cultCounter.Parent then
        local tStr = string.format("Click: %d | Ward: %d | Tap: %d | Hit ย่อย: %d", clickCount, wardCount, tapCount, minorTotalHits)
        if cultCounter.Text ~= tStr then cultCounter.Text = tStr end
    end
end
refreshBreakthrough = function()
    if minorButton then
        minorButton.Text = minorAuto and "Auto ทะลวงย่อย (กดจังหวะ): เปิด" or "Auto ทะลวงย่อย (กดจังหวะ): ปิด"
        minorButton.BackgroundColor3 = minorAuto and Color3.fromRGB(52, 125, 102) or Color3.fromRGB(54, 65, 82)
    end
    qiButton.Text = qiAuto and "Qi Circulation: เปิด" or "Qi Circulation: ปิด"
    tribButton.Text = tribAuto and "Heavenly Tribulation: เปิด" or "Heavenly Tribulation: ปิด"
    qiButton.BackgroundColor3 = qiAuto and Color3.fromRGB(52, 125, 102) or Color3.fromRGB(54, 65, 82)
    tribButton.BackgroundColor3 = tribAuto and Color3.fromRGB(75, 100, 170) or Color3.fromRGB(54, 65, 82)
    if not qiAuto and not tribAuto and not minorAuto then
        if cultStatus and cultStatus.Parent and cultStatus.Text ~= "Auto ปิด • ยังรับข้อมูลรอบจากเกม" then
            cultStatus.Text = "Auto ปิด • ยังรับข้อมูลรอบจากเกม"
        end
    end
    if updateCultCounter then updateCultCounter() end
end
connect(minorButton.Activated, function()
    minorAuto = not minorAuto
    refreshBreakthrough()
    if minorAuto and cultStatus and cultStatus.Parent then
        cultStatus.Text = "เปิด Auto ทะลวงย่อยแล้ว • เริ่มในเกมได้เลย"
    end
end)
connect(qiButton.Activated, function()
    qiAuto = not qiAuto
    refreshBreakthrough()
    if qiAuto and not circulation then cultStatus.Text = "เปิด Qi แล้ว • รอ CircStart รอบใหม่" end
end)
connect(tribButton.Activated, function()
    tribAuto = not tribAuto
    refreshBreakthrough()
    if tribAuto and not tribulation then cultStatus.Text = "เปิด Tribulation แล้ว • รอ TribStart" end
end)
local function resetCultivation()
    circulation, tribulation, cultivationPhase = nil, nil, nil
end
local function rebase(startAt)
    if not circulation or not finite(startAt) then return end
    local now = workspace:GetServerTimeNow()
    local delta = startAt - now
    if delta <= 8 and delta >= -(circulation.duration + 3) then
        circulation.t0 = os.clock() + delta
        circulation.startAt = startAt
    end
end
connect(cultRemote.OnClientEvent, function(data)
    if closed or type(data) ~= "table" then return end
    local now = os.clock()
    if data.op == "CircStart" then
        resetCultivation()
        cultivationPhase = "qi"
        local duration = finite(data.duration) and data.duration or 20
        local lead = finite(data.lead) and data.lead or 3
        circulation = { t0 = now + lead, duration = duration, orbs = {}, byId = {} }
        -- Copy fields: the game's own listener mutates the incoming orb tables.
        for _, orb in pairs(type(data.orbs) == "table" and data.orbs or {}) do
            if type(orb) == "table" and orb.id ~= nil and finite(orb.t) and finite(orb.life) and orb.life > 0 then
                local copy = { id = orb.id, kind = orb.kind, t = orb.t, life = orb.life }
                table.insert(circulation.orbs, copy)
                circulation.byId[copy.id] = copy
            end
        end
        rebase(data.startAt)
        cultResult.Text = "รอบ Qi ใหม่ • จุด " .. #circulation.orbs
    elseif data.op == "CircClock" then
        rebase(data.startAt)
    elseif data.op == "Tally" and circulation then
        local orb = circulation.byId[data.id]
        if orb then orb.done = true end
        cultResult.Text = "Qi รับแล้ว: " .. tostring(data.blue or 0) .. " | แดง: " .. tostring(data.red or 0)
        if data.early then cultResult.Text ..= " • เร็วเกินไป" end
    elseif data.op == "CircPass" then
        circulation = nil
        cultivationPhase = "transition"
        cultStatus.Text = "ผ่าน Qi • รอผลหรือ Tribulation"
    elseif data.op == "TribStart" then
        circulation = nil
        cultivationPhase = "trib"
        wardReadyAt = now
        tribulation = { endsAt = now + (finite(data.duration) and data.duration or 30), bolts = {}, tap = nil }
        cultResult.Text = "เริ่ม Heavenly Tribulation"
    elseif data.op == "Bolt" and tribulation then
        local lead = finite(data.t) and data.t or 1.3
        if lead >= 0 and lead <= 30 then
            -- Lead is relative to receipt, matching the client's shrinking ring.
            -- 0.08s is a timing allowance, not a guarantee of a successful ward.
            table.insert(tribulation.bolts, { due = now + math.max(0, lead - 0.08), expires = now + lead + 0.05 })
        end
    elseif data.op == "TapPrompt" and tribulation and finite(data.id) then
        local lead = math.clamp(tonumber(data.t) or 1.3, 0.3, 3)
        local window = math.clamp(tonumber(data.window) or 0.6, 0.1, lead)
        -- Gold/TAP opens at lead-window. Aim inside that interval.
        tribulation.tap = { id = data.id, due = now + lead - window * 0.5, expires = now + lead }
    elseif data.op == "TapEnd" and tribulation then
        if tribulation.tap and tribulation.tap.id == data.id then tribulation.tap = nil end
        cultResult.Text = "Tap " .. tostring(data.id) .. ": " .. tostring(data.how or "miss")
    elseif data.op == "TapEarly" then
        cultResult.Text = "Tap " .. tostring(data.id) .. ": เร็วเกินไป"
    elseif data.op == "Warded" then
        cultResult.Text = "เกมยืนยัน Ward"
    elseif data.op == "CircEnd" then
        resetCultivation()
        cultResult.Text = (data.success and "ผ่าน: " or "จบรอบ: ") .. tostring(data.text or data.realm or "-")
        cultStatus.Text = "จบรอบ • รอเริ่มในเกมเอง"
    elseif data.op == "Meditate" and data.on == false then
        resetCultivation()
    end
end)
connect(Players.LocalPlayer.CharacterAdded, function()
    resetCultivation()
    cultStatus.Text = "ตัวละครเกิดใหม่ • รอข้อมูลรอบใหม่"
end)
connect(RunService.Heartbeat, function()
    if closed then return end
    local now = os.clock()
    if circulation then
        local elapsed = now - circulation.t0
        if elapsed > circulation.duration + 3 then
            resetCultivation()
            cultStatus.Text = "หมดเวลารอบ • รอข้อมูลใหม่"
        elseif qiAuto then
            local ready = {}
            for _, orb in ipairs(circulation.orbs) do
                -- Client turns the border gold at 60% of life; aim at 70%.
                if orb.kind == "blue" and not orb.done and not orb.sent
                    and elapsed >= orb.t + orb.life * 0.7
                    and elapsed <= orb.t + orb.life then
                    ready[#ready + 1] = orb
                end
            end
            table.sort(ready, function(a, b)
                if type(a.id) == "number" and type(b.id) == "number" then return a.id < b.id end
                return tostring(a.id) < tostring(b.id)
            end)
            for _, orb in ipairs(ready) do
                orb.sent = true
                local payload = { op = "Click", id = orb.id }
                if circulation.startAt then payload.at = circulation.startAt + (os.clock() - circulation.t0) end
                cultRemote:FireServer(payload)
                clickCount += 1
            end
        end
    end
    if tribulation then
        if now > tribulation.endsAt + 2 then
            resetCultivation()
            cultStatus.Text = "หมดช่วง Tribulation • รอผลจากเกม"
        else
            local tap = tribulation.tap
            if tap and not tap.sent and tribAuto and now >= tap.due and now <= tap.expires then
                tap.sent = true
                cultRemote:FireServer({ op = "Tap", id = tap.id })
                tapCount += 1
            end
            -- Respect the client's 0.8s ward cooldown; never spam Ward continuously.
            for index = #tribulation.bolts, 1, -1 do
                local bolt = tribulation.bolts[index]
                if now > bolt.expires then
                    table.remove(tribulation.bolts, index)
                elseif tribAuto and now >= bolt.due and now >= wardReadyAt then
                    wardReadyAt = now + 0.8
                    cultRemote:FireServer({ op = "Ward" })
                    wardCount += 1
                    table.remove(tribulation.bolts, index)
                end
            end
        end
    end
    if now >= latestPaint then
        latestPaint = now + 0.1
        if updateCultCounter then updateCultCounter() end
        if circulation then
            local qText = qiAuto and "Qi: รอจังหวะทอง • กดเฉพาะ blue" or "Qi: ปิด Auto"
            if cultStatus.Text ~= qText then cultStatus.Text = qText end
        elseif tribulation then
            local trText = tribAuto and "Tribulation: รอ Bolt / TapPrompt" or "Tribulation: ปิด Auto"
            if cultStatus.Text ~= trText then cultStatus.Text = trText end
        end
    end
end)
refreshBreakthrough()
selectTab("breakthrough")

-- Mount controls into the supplied hub; hidden assembly controls never show.
local function mountPage(name, index, caption, contents, height)
    local page = host.makePage(name, index, caption)
    local scroll = create("ScrollingFrame", {
        Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 5,
        CanvasSize = UDim2.fromOffset(0, height), ScrollingDirection = Enum.ScrollingDirection.Y,
    }, page)
    contents.Parent = scroll
    contents.Position = UDim2.fromOffset(0, 0)
    contents.Size = UDim2.new(1, -6, 0, height)
    contents.Visible = true
end
mountPage("Alchemy", 4, "ปรุงยา", alchemyPage, 390)
mountPage("Forge", 5, "Forge", forgePage, 400)
mountPage("Cultivation", 6, "ทะลวงขั้น", breakthroughPage, 460)
panel.Visible = false
restore.Visible = false
host.stopWorkshop = stopWorkshop
host.isBusy = function()
    if closed then return false end
    return cultivationPhase ~= nil or alchemyAuto or alchemyBusy or alchemyPending
        or alchemyActive or generalMinigameActive or forgeEnabled or forgeBusy
        or awaitingGame or gameActive or gameIsVisible()
        or (host.HongmengConfig and host.HongmengConfig.Enabled)
end
host.showPage(1)
host.refresh()

end
local hub = buildMaster()
hub.frame.Visible = true
report("เมนูหลักเปิดแล้ว • กำลังโหลดปรุงยา / Forge / ทะลวงขั้น", false)
task.spawn(function()
    local ok, reason = xpcall(function() mountWorkshop(hub) end, function(e) return tostring(e) end)
    if ok then
        report("พร้อมใช้งาน • 8 แท็บ", false)
        task.delay(3, finishNotice)
    else
        report("โหลดส่วนมินิเกมไม่สำเร็จ: " .. tostring(reason), true)
    end
end)

]====]

if type(loadstring) ~= "function" then
    report("ตัวรันนี้ไม่มี loadstring จึงโหลดชุดรวมไม่ได้", true)
    return
end
local compileOK, program, compileError = pcall(loadstring, source, "MurimMasterHub-v2")
if not compileOK then report(program, true); return end
if not program then report(compileError or "Compile failed", true); return end
task.spawn(function()
    local ok, reason = xpcall(function() program(report, finishNotice) end, function(e) return tostring(e) end)
    if not ok then report(reason, true) end
end)