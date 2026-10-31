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

local hubUI = {}
local originalHitboxes = setmetatable({}, { __mode = "k" })
local selectedNPCNames = {} -- รายชื่อมอนที่เลือก [Name] = true/false
local knownNPCNames = {}    -- รายชื่อมอนสเตอร์พร้อมเลเวล [Name] = Level Number
local savedNPCPositions = {}-- บันทึกตำแหน่งมอนสเตอร์ [Name] = CFrame (Auto Save)
local favoriteNPCNames = {} -- [Name] = true; priority targets for this session
local currentTarget = nil

local isFarming = false
local isAutoLooting = true -- เปิดใช้งาน Auto Loot เป็นค่าเริ่มต้น
local isHitboxExpanded = true -- เปิดใช้งาน ขยาย Hitbox เป็นค่าเริ่มต้น
local isAutoParry = true -- เปิดใช้งาน Auto Parry เป็นค่าเริ่มต้น
local PARRY_DISTANCE = 18
local PARRY_WINDOW = 0.22
local PARRY_LEAD = 0.12
local isParrying = false
local handledAttacks = setmetatable({}, { __mode = "k" })

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
        tabs[i].BackgroundColor3 = i == index and Color3.fromRGB(72, 86, 147) or Color3.fromRGB(30, 37, 51)
        tabs[i].TextColor3 = i == index and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(165, 179, 205)
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
    tab.Size = UDim2.new(1 / 3, -4, 0, 38)
    tab.Position = UDim2.new(((index - 1) % 3) / 3, ((index - 1) % 3) * 2, 0, math.floor((index - 1) / 3) * 44)
    tab.BorderSizePixel = 0
    tab.Font = Enum.Font.SourceSansBold
    tab.TextSize = 15
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
local tpPage = makePage("Teleport", 2, "จุดวาร์ป")
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

local settingsPage = makePage("Settings", 6, "ตั้งค่า")
newHeading(settingsPage, "ตั้งค่าการฟาร์ม")
local settingsBody = Instance.new("ScrollingFrame")
settingsBody.Name = "SettingsContent"
settingsBody.Position = UDim2.new(0, 0, 0, 44)
settingsBody.Size = UDim2.new(1, 0, 1, -56)
settingsBody.BackgroundTransparency = 1
settingsBody.BorderSizePixel = 0
settingsBody.ScrollBarThickness = 4
settingsBody.CanvasSize = UDim2.new(0, 0, 0, 330)
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

local toggleParryBtn = Instance.new("TextButton")
toggleParryBtn.Name = "AutoParryToggle"
toggleParryBtn.Font = Enum.Font.SourceSansBold
toggleParryBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", toggleParryBtn).CornerRadius = UDim.new(0, 6)
placeButton(toggleParryBtn, settingsBody, 0, 12, 180, 1, -24)
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

-- Anti-idle input approach adapted from Infinite Yield's antiafk command:
-- https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source
-- Keep other scripts' Idled connections intact; own connection is cleaned up by cleanup().
local antiAFKEnabled = true
local antiAFKButton = Instance.new("TextButton")
antiAFKButton.Name = "AntiAFKToggle"
antiAFKButton.Font = Enum.Font.SourceSansBold
antiAFKButton.TextColor3 = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", antiAFKButton).CornerRadius = UDim.new(0, 6)
placeButton(antiAFKButton, settingsBody, 0, 12, 228, 1, -24)
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
placeButton(destroyBtn, settingsBody, 0, 12, 276, 1, -24)

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
	if not isHitboxExpanded or not npc or not npc:IsA("Model") then return end

	local hum = npc:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local hrp = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart or npc:FindFirstChild("Torso")
	if hrp then
		pcall(function()
			if not originalHitboxes[hrp] then
                originalHitboxes[hrp] = {
                    Size = hrp.Size, Transparency = hrp.Transparency,
                    CanCollide = hrp.CanCollide, Material = hrp.Material,
                }
            end
            if hrp.Size ~= HITBOX_SIZE then hrp.Size = HITBOX_SIZE end
			if hrp.Transparency ~= HITBOX_TRANSPARENCY then hrp.Transparency = HITBOX_TRANSPARENCY end
			if hrp.CanCollide ~= false then hrp.CanCollide = false end
			if hrp.Material ~= Enum.Material.ForceField then hrp.Material = Enum.Material.ForceField end
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

local function getNPCLevel(npc)
	if not npc then return 0 end

	local attrLevel = npc:GetAttribute("Level") or npc:GetAttribute("Lv") or npc:GetAttribute("LevelValue")
	if typeof(attrLevel) == "number" then return attrLevel end

	local levelVal = npc:FindFirstChild("Level") or npc:FindFirstChild("Lv") or npc:FindFirstChild("LevelValue")
	if levelVal and (levelVal:IsA("IntValue") or levelVal:IsA("NumberValue")) then
		return levelVal.Value
	end

	local statsFolder = npc:FindFirstChild("Stats") or npc:FindFirstChild("Configuration") or npc:FindFirstChild("Data")
	if statsFolder then
		local lvl = statsFolder:FindFirstChild("Level") or statsFolder:FindFirstChild("Lv")
		if lvl and (lvl:IsA("IntValue") or lvl:IsA("NumberValue")) then
			return lvl.Value
		end
	end

	local match = npc.Name:match("%d+")
	if match then return tonumber(match) end
	return 0
end

local function interactWithDrop(dropItem)
	if not dropItem or not dropItem.Parent then return end
	if dropItem.Name == "LootChest_Wooden" or dropItem.Name == "LootChest_Iron" then return end

	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end
	local hrp = character.HumanoidRootPart

	local targetPart = dropItem:IsA("BasePart") and dropItem or (dropItem:IsA("Model") and dropItem.PrimaryPart) or dropItem:FindFirstChildWhichIsA("BasePart", true)
	if not targetPart then return end

	hrp.CFrame = targetPart.CFrame
	task.wait(0.1)
    if destroyed or not isFarming or not dropItem.Parent or (hubUI.isBusy and hubUI.isBusy()) then return end
    local descendants = dropItem:GetDescendants()

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
		end
	end

	for _, desc in ipairs(descendants) do
        if destroyed or not isFarming or (hubUI.isBusy and hubUI.isBusy()) then return end
		if desc:IsA("ProximityPrompt") and desc.Enabled then
			if typeof(fireproximityprompt) == "function" then
				pcall(function() fireproximityprompt(desc) end)
			elseif VirtualInputManager then
				local holdTime = desc.HoldDuration or 0
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
				task.wait(holdTime + 0.05)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
			end
			task.wait(0.05)
		end
	end
end

local function isAlive(npc)
	if not npc or not npc:IsA("Model") or not npc.Parent or not npc:IsDescendantOf(Workspace) then return false end
	local hum = npc:FindFirstChildOfClass("Humanoid")
	if hum then
		if hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then return false end
	end
	local targetPart = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart or npc:FindFirstChild("Torso")
	return targetPart ~= nil
end

local function getHighestLevelTarget()
    local now = os.clock()
    if now < targetScanAt then
        if cachedTarget and isAlive(cachedTarget) then
            local part = cachedTarget:FindFirstChild("HumanoidRootPart") or cachedTarget.PrimaryPart or cachedTarget:FindFirstChild("Torso")
            return part.CFrame, true, cachedTarget
        elseif not cachedTarget then
            return nil, false, nil
        end
    end
    targetScanAt = now + TARGET_SCAN_INTERVAL
	local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")
	local highestLevel = -1
	local bestCFrame = nil
	local bestNPCObj = nil
    local bestIsFavorite = false

	local hasSelection = false
	for _, isSelected in pairs(selectedNPCNames) do
		if isSelected then hasSelection = true break end
	end

	if npcsFolder then
		for _, npc in ipairs(npcsFolder:GetChildren()) do
			if (favoriteNPCNames[npc.Name] or not hasSelection or selectedNPCNames[npc.Name]) and isAlive(npc) then
				local level = getNPCLevel(npc)
                local isFavorite = favoriteNPCNames[npc.Name] == true
				local targetPart = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart or npc:FindFirstChild("Torso")
				
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
		local levelText = item.Level > 0 and string.format(" [Lv.%d]", item.Level) or ""
		local displayText = "🌀 วาร์ปไป: " .. item.Name .. levelText

		local tpBtn = Instance.new("TextButton")
		tpBtn.Name = "TP_" .. item.Name
		tpBtn.Size = UDim2.new(1, -8, 0, 28)
		tpBtn.LayoutOrder = idx
		tpBtn.BackgroundColor3 = Color3.fromRGB(90, 50, 140)
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

-- บันทึกพิกัดมอนสเตอร์ + บันทึกรายชื่อ (แก้บัคการข้ามชื่อมอนสเตอร์)
local function autoSaveNPCPosition(npc)
	if not npc or not npc:IsA("Model") then return end
	
	local lvl = getNPCLevel(npc)
	knownNPCNames[npc.Name] = math.max(knownNPCNames[npc.Name] or 0, lvl)

	local targetPart = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart or npc:FindFirstChild("Torso")
	if targetPart and isAlive(npc) then
		if not savedNPCPositions[npc.Name] then
			savedNPCPositions[npc.Name] = targetPart.CFrame
			queueRefresh()
		end
	end
end

local function stopAll()
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
                startBtn.Text = "ฟาร์มพัก • มินิเกมทำงาน"
                task.wait(0.15)
                continue
            end
            startBtn.Text = "กำลังฟาร์ม..."
            local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")

			if hrp then
                local targetCF, aliveStatus, npcObj = getHighestLevelTarget()
                local favoriteReady = aliveStatus and npcObj and favoriteNPCNames[npcObj.Name]
                local dropsFolder = Workspace:FindFirstChild("Murim_Drops")
				local validDrop = nil
				
				if isAutoLooting and dropsFolder and not favoriteReady then
					for _, drop in ipairs(dropsFolder:GetChildren()) do
						if drop and drop.Parent and drop.Name ~= "LootChest_Wooden" and drop.Name ~= "LootChest_Iron" then
							validDrop = drop
							break
						end
					end
				end

				if validDrop then
					currentTarget = nil
					interactWithDrop(validDrop)
					task.wait(0.1)
				else

					if aliveStatus and targetCF and npcObj then
						currentTarget = npcObj
						hrp.CFrame = targetCF * CFrame.new(0, heightUnder, 0) * lyingRotation
					else
						currentTarget = nil
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
			applyHitboxToNPC(npc)
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
	for name, _ in pairs(knownNPCNames) do
		table.insert(nameList, name)
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

	refreshTPButtons()
end

local function bindFolderEvents()
    for _, conn in ipairs(folderConnections) do conn:Disconnect() end
    table.clear(folderConnections)
    targetScanAt = 0
    local folder = Workspace:FindFirstChild("Murim_NPCs")
    if not folder then return end
    folderConnections[#folderConnections + 1] = folder.DescendantAdded:Connect(function()
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

local function checkAttacker(enemy)
    if not isAutoParry or isParrying or not enemy or enemy == player.Character then return end
    local char = player.Character
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    local enemyHrp = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart or enemy:FindFirstChild("Torso")
    if not myHrp or not enemyHrp then return end

    local dist = (myHrp.Position - enemyHrp.Position).Magnitude
    if dist > PARRY_DISTANCE then return end

    local act = enemy:GetAttribute("Act")
    local actT = enemy:GetAttribute("ActT")
    local actW = enemy:GetAttribute("ActW")

    if act and type(actT) == "number" and type(actW) == "number" and actW > 0 then
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
end

externalConnections[#externalConnections + 1] = RunService.Heartbeat:Connect(function()
    if destroyed or not isAutoParry or isParrying or (hubUI.isBusy and hubUI.isBusy()) then return end
    local npcsFolder = Workspace:FindFirstChild("Murim_NPCs")
    if npcsFolder then
        for _, npc in ipairs(npcsFolder:GetChildren()) do
            checkAttacker(npc)
        end
    end
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            checkAttacker(otherPlayer.Character)
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
local qiAuto, tribAuto = false, false
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
        skipped.Text = "เลขที่ข้าม: -"
        status.Text = enabled and "สถานะ: รอมินิเกม" or "สถานะ: หยุด"
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
    skipped.Text = "เลขที่ข้าม: " .. (#display > 0 and table.concat(display, ", ") or "-")
    status.Text = enabled and (unknownCount > 0 and ("ทำงาน • สีไม่ตรงเงื่อนไข " .. unknownCount .. " จุด") or "สถานะ: Auto ทำงาน") or "สถานะ: หยุด • ตรวจเลขอย่างเดียว"
    lastLabel.Text = "ส่งล่าสุด: " .. (lastId and ("Mote" .. lastId) or "-")
    updateCounter()
end)

connect(RunService.Heartbeat, function()
    if closed or not forgeEnabled then return end
    if not enabled then forgeStatus.Text = "Forge: พักอยู่ กรุณาเปิด Auto กด"; return end
    if forgeBusy then return end
    if awaitingGame then
        if os.clock() - awaitingSince > 10 then stopForge("Forge: ไม่ได้รับสัญญาณเริ่มเกม หยุดส่งซ้ำ") end
        return
    end
    if gameActive or gameIsVisible() or os.clock() < nextForgeAt then return end
    if cultivationPhase or alchemyBusy or alchemyPending or alchemyActive or generalMinigameActive then
        forgeStatus.Text = "Forge: รอมินิเกมอื่นจบ"
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
        alchemyActive = alchemyPending or data.kind == "Alchemy"
        alchemyPending = false
        beatVersion += 1
        currentBeat = nil
        if alchemyActive then
            alchemyCount += 1
            alchemyStatus.Text = "กำลังปรุง • เริ่มแล้ว " .. alchemyCount .. " รอบ"
        end
    elseif data.op == "Beat" then
        if not alchemyActive then return end
        currentBeat = {}
        local beat = currentBeat
        if not alchemyHit then return end
        local version = beatVersion
        local window = tonumber(data.window) or 0.5
        if window < 0 or window > 30 or data.i == nil then return end
        local target = os.clock() + window
        task.delay(window, function()
            if closed or not alchemyHit or not alchemyActive or currentBeat ~= beat or version ~= beatVersion then return end
            minigameRemote:FireServer({ op = "Hit", i = data.i, off = os.clock() - target })
        end)
    elseif data.op == "Hit" or data.op == "Miss" or data.op == "Early" then
        if alchemyActive then
            currentBeat = nil
            alchemyResult.Text = "จังหวะล่าสุด: " .. ({ Hit = "สำเร็จ", Miss = "พลาด", Early = "เร็วเกินไป" })[data.op]
        end
    elseif data.op == "End" then
        local wasAlchemy = alchemyActive or alchemyPending
        generalMinigameActive, alchemyActive, alchemyPending = false, false, false
        beatVersion += 1
        currentBeat = nil
        alchemyNextAt = os.clock() + 3.2
        if wasAlchemy then
            alchemyResult.Text = "ผลล่าสุด: " .. tostring(data.text or (data.success and "สำเร็จ" or "จบรอบ"))
            alchemyStatus.Text = alchemyAuto and "จบรอบ • รอเริ่มรอบถัดไป" or "จบรอบแล้ว"
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
    if not alchemyHit then alchemyStatus.Text = "พักอยู่ • เปิด Auto กดจังหวะเพื่อทำต่อ"; return end
    if os.clock() >= alchemyNextAt then requestMix() end
end)

local stopAll = pageButton(panel, "หยุดทั้งหมด", 495, 36)
stopAll.BackgroundColor3 = Color3.fromRGB(150, 55, 55)
local function stopWorkshop()
    enabled, forgeEnabled, alchemyAuto, alchemyHit = false, false, false, false
    breakthroughEnabled = false
    qiAuto, tribAuto = false, false
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


-- Cultivation controls derived from UI.Circulation (CircStart / TribStart).
-- Install before starting the trial so the server's schedule can be observed.
pageLabel(breakthroughPage, "ทะลวงขั้น • Circulation / Tribulation", 0, 40, 17)
pageLabel(breakthroughPage, "เปิดปุ่มที่ต้องการ แล้วเริ่มทะลวงขั้นในเกมเอง", 43, 40, 13)
local qiButton = pageButton(breakthroughPage, "Qi Circulation: ปิด", 94, 43)
local tribButton = pageButton(breakthroughPage, "Heavenly Tribulation: ปิด", 147, 43)
local cultStatus = pageLabel(breakthroughPage, "รอข้อมูลรอบใหม่จากเกม", 201, 45)
local cultResult = pageLabel(breakthroughPage, "ผลล่าสุด: -", 250, 44)
local cultCounter = pageLabel(breakthroughPage, "Click: 0 | Ward: 0 | Tap: 0", 300, 30, 13)
pageLabel(breakthroughPage, "Qi: รอจังหวะและข้ามแดง • Tribulation: ตามสัญญาณ\nไม่เริ่มรอบ ไม่ใช้วัตถุดิบ และไม่รีเซ็ตเลเวล", 339, 48, 12)
local circulation, tribulation
local clickCount, wardCount, tapCount = 0, 0, 0
local wardReadyAt = 0
local latestPaint = 0
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
refreshBreakthrough = function()
    qiButton.Text = qiAuto and "Qi Circulation: เปิด" or "Qi Circulation: ปิด"
    tribButton.Text = tribAuto and "Heavenly Tribulation: เปิด" or "Heavenly Tribulation: ปิด"
    qiButton.BackgroundColor3 = qiAuto and Color3.fromRGB(52, 125, 102) or Color3.fromRGB(54, 65, 82)
    tribButton.BackgroundColor3 = tribAuto and Color3.fromRGB(75, 100, 170) or Color3.fromRGB(54, 65, 82)
    if not qiAuto and not tribAuto then cultStatus.Text = "Auto ปิด • ยังรับข้อมูลรอบจากเกม" end
end
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
        cultCounter.Text = string.format("Click: %d | Ward: %d | Tap: %d", clickCount, wardCount, tapCount)
        if circulation then
            cultStatus.Text = qiAuto and "Qi: รอจังหวะทอง • กดเฉพาะ blue" or "Qi: ปิด Auto"
        elseif tribulation then
            cultStatus.Text = tribAuto and "Tribulation: รอ Bolt / TapPrompt" or "Tribulation: ปิด Auto"
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
mountPage("Alchemy", 3, "ปรุงยา", alchemyPage, 390)
mountPage("Forge", 4, "Forge", forgePage, 400)
mountPage("Cultivation", 5, "ทะลวงขั้น", breakthroughPage, 400)
panel.Visible = false
restore.Visible = false
host.stopWorkshop = stopWorkshop
host.isBusy = function()
    if closed then return false end
    return cultivationPhase ~= nil or alchemyAuto or alchemyBusy or alchemyPending
        or alchemyActive or generalMinigameActive or forgeEnabled or forgeBusy
        or awaitingGame or gameActive or gameIsVisible()
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
        report("พร้อมใช้งาน • 6 แท็บ", false)
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