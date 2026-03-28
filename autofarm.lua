-- ╔══════════════════════════════════════════════════════════╗
--  HazeHUB – autofarm.lua  v2.8.2
--  GitHub: Hazeluxeeeees/HazeHub-Modules
--
--  v2.8.2:
--    + Fire() / GetPlayRoomEvent(): kanonisch RS.Remote.Server.PlayRoom.Event (fix: nil Fire → Zeile 628)
--    + ScanAllRewards: nil-sichere WorldData/story/ranger; Raid-Tasks aus Player_Data[LP.Name].ChapterLevels
--    + Challenge-Scanner: RS.Gameplay.Game.Challenge.Items + Metadaten aus Challenge-Ordner (Values)
--    + Queue-Wechsel: EsperRaid / JJKRaid + optional Difficulty
--  v2.8.1:
--    + Alle Pfade nutzen LP.Name (dynamisch, kein Hardcode)
--    + TeleportToLobby via TeleportService (ID: 111446873000464)
--    + Auto-Resume: Settings.json AutoFarm=true → nach 5s starten
--    + Re-Load nach Teleport: loadstring(game:HttpGet(MAIN_URL))()
--    + 2s Pflicht-Delay nach Change-Chapter (Scanner)
--    + item.Name als primärer Identifier (ignoriert UIGridLayout)
--    + Location-Check via workspace:FindFirstChild("Lobby")
-- ╚══════════════════════════════════════════════════════════╝

local VERSION    = "2.8.2"
local LOBBY_ID   = 111446873000464
local MAIN_URL   = "https://raw.githubusercontent.com/Hazeluxeeeees/Tap-Sim/refs/heads/main/script"

-- ============================================================
--  WARTEN BIS HAZEHUB BEREIT (max 10s)
-- ============================================================
-- FIX: Sicherer Start & Pfad-Check
local LP = game:GetService("Players").LocalPlayer
local RS = game:GetService("ReplicatedStorage")

-- Warte bis das Hauptskript vollständig geladen ist
repeat task.wait(1) until _G.HazeHUB_Ready == true

-- ============================================================
--  GLOBALE HAZEHUB REFERENZEN
-- ============================================================
local HH = _G.HazeHUB
local HS = _G.HazeShared
local CFG         = HS.Config
local ST          = HS.State
local D           = HS.D
local TF          = HS.TF;  local TM = HS.TM;  local Tw = HH.Tw
local Svc         = HS.Svc
local Card        = HH.Card;    local NeonBtn  = HH.NeonBtn
local MkLbl       = HH.MkLbl;  local SecLbl   = HH.SecLbl
local MkInput     = HH.MkInput; local VList    = HH.VList
local HList       = HH.HList;   local Pad      = HH.Pad
local Corner      = HH.Corner;  local Stroke   = HH.Stroke
local PR          = HS.PR
local SaveConfig  = HH.SaveConfig
local SaveSettings = HH.SaveSettings
local SendWebhook = HS.SendWebhook
local Container   = HS.Container

-- ★ TeleportToLobby aus HazeHUB (falls schon gesetzt), sonst lokal
local TeleportToLobby = HH.TeleportToLobby or function()
    pcall(function() game:GetService("TeleportService"):Teleport(LOBBY_ID) end)
end

-- ============================================================
--  SERVICES
-- ============================================================
local Players          = game:GetService("Players")
local VirtualUser      = game:GetService("VirtualUser")
local TeleportService  = game:GetService("TeleportService")
-- REQUIRED: Account-spezifisch via LocalPlayer
local LP               = game.Players.LocalPlayer
local RS               = game:GetService("ReplicatedStorage")
local WS               = game:GetService("Workspace")

-- ============================================================
--  DATEIPFADE
-- ============================================================
local FOLDER        = "HazeHUB"
local saveFile     = LP.Name .. "_settings.json"
local DB_FILE       = FOLDER .. "/" .. LP.Name .. "_RewardDB.json"
local QUEUE_FILE    = FOLDER .. "/" .. LP.Name .. "_Queue.json"
local STATE_FILE    = FOLDER .. "/" .. LP.Name .. "_State.json"
local SETTINGS_FILE = FOLDER .. "/" .. saveFile

if makefolder then pcall(function() makefolder(FOLDER) end) end

-- ============================================================
--  STATE
-- ============================================================
local AF = {
    Queue          = {},
    Active         = false,
    Running        = false,
    Scanning       = false,
    RewardDatabase = {},
    UI             = { Lbl = {}, Fr = {}, Btn = {} },
}
_G.AutoFarmRunning = false

-- ============================================================
--  ★ LOCATION CHECK  (workspace:FindFirstChild("Lobby"))
-- ============================================================
local function CheckIsLobby()
    return WS:FindFirstChild("Lobby") ~= nil
end

-- ============================================================
--  ANTI-AFK
-- ============================================================
pcall(function()
    LP.Idled:Connect(function()
        pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
    end)
end)
task.spawn(function()
    while true do task.wait(480)
        pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
    end
end)

-- ============================================================
--  REMOTE
-- ============================================================
local PlayRoomEvent = nil
task.spawn(function()
    pcall(function()
        PlayRoomEvent = RS
            :WaitForChild("Remote",   15)
            :WaitForChild("Server",   15)
            :WaitForChild("PlayRoom", 15)
            :WaitForChild("Event",    15)
    end)
    if PlayRoomEvent then print("[HazeHub] Remote: " .. PlayRoomEvent:GetFullName())
    else warn("[HazeHub] PlayRoomEvent nicht gefunden!") end
end)

-- ★ Wie autofarm_FULL_CORRECTED: zuerst PlayRoom Event, sonst HS.PR (mit nil-Check!)
--    Remote.Server.PlayRoom.Event z. B. :FireServer("Change-World", { ["World"] = "JJKRaid" })
local function GetPlayRoomEvent()
    if PlayRoomEvent and PlayRoomEvent.Parent then return PlayRoomEvent end
    local ok, ev = pcall(function()
        return RS:WaitForChild("Remote", 8)
            :WaitForChild("Server", 8)
            :WaitForChild("PlayRoom", 8)
            :WaitForChild("Event", 8)
    end)
    if ok and ev then
        PlayRoomEvent = ev
        return ev
    end
    return nil
end

local function Fire(action, data)
    local ev = GetPlayRoomEvent()
    if ev then
        local ok, err = pcall(function()
            if data ~= nil then ev:FireServer(action, data)
            else ev:FireServer(action) end
        end)
        if not ok then warn("[HazeHub] Fire-Fehler: " .. tostring(err)) end
    else
        warn("[HazeHub] Fire-Fehler: PlayRoom Event ist NIL!")
    end
end

-- Fallback-Suche (nur wenn kanonischer Pfad fehlt)
local function GetPlayRoomRemote()
    local ev = GetPlayRoomEvent()
    if ev then return ev end
    local remoteFolder = RS:FindFirstChild("Remote") or RS:FindFirstChild("Remotes")
    if not remoteFolder then return nil end
    return remoteFolder:FindFirstChild("Event", true) or remoteFolder:FindFirstChild("PlayRoomEvent", true)
end

-- ★ Nil-sicherer SafeFire (wie Fire: PR-Fallback)
local function SafeFire(action, data)
    local remote = GetPlayRoomRemote()
    if remote then
        local ok, err = pcall(function()
            if data then remote:FireServer(action, data)
            else remote:FireServer(action) end
        end)
        if not ok then warn("[HazeHub] SafeFire Fehler (" .. tostring(action) .. "): " .. tostring(err)) end
    elseif PR and type(PR) == "function" then
        pcall(function() PR(action, data) end)
    else
        warn("[HazeHub] SafeFire abgebrochen – Remote + PR nil. Action: " .. tostring(action))
    end
end
-- ============================================================
--  INVENTAR  (★ LP.Name dynamisch)
-- ============================================================
local function GetLiveInvAmt(itemName)
    local n = 0
    pcall(function()
        -- ★ Dynamisch: LP.Name statt hardcoded
        local f = RS:WaitForChild("Player_Data",3):WaitForChild(LP.Name,3):WaitForChild("Items",3)
        local item = f:FindFirstChild(itemName); if not item then return end
        local vc = item:FindFirstChild("Value") or item:FindFirstChild("Amount")
        if vc then n = tonumber(vc.Value) or 0
        elseif item:IsA("IntValue") or item:IsA("NumberValue") then n = tonumber(item.Value) or 0 end
    end)
    return n
end

-- ============================================================
--  ★ DoTeleportToLobby
-- ============================================================
local function DoTeleportToLobby(keepAutoFarm)
    if keepAutoFarm then
        if CFG then CFG.AutoFarm = true end
        if SaveConfig  then pcall(SaveConfig)  end
        if SaveSettings then pcall(SaveSettings) end
        print("[HazeHub] AutoFarm=true in Settings gespeichert (Teleport-Persistenz)")
    end
    print("[HazeHub] Teleportiere zur Lobby ID: " .. LOBBY_ID)
    pcall(function()
        TeleportService:Teleport(LOBBY_ID)
    end)
end

-- ============================================================
--  PERSISTENZ
-- ============================================================
local function SaveState()
    if not writefile then return end
    pcall(function()
        writefile(STATE_FILE, Svc.Http:JSONEncode({
            running = AF.Running or AF.Active,
            active  = AF.Active,
            version = VERSION,
            ts      = os.time(),
        }))
    end)
end

local function LoadState()
    if not (isfile and isfile(STATE_FILE)) then return nil end
    local raw; pcall(function() raw = readfile(STATE_FILE) end)
    if not raw or #raw < 5 then return nil end
    local ok, data = pcall(function() return Svc.Http:JSONDecode(raw) end)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

local function LoadSettingsFile()
    if not (isfile and isfile(SETTINGS_FILE)) then return nil end
    local raw; pcall(function() raw = readfile(SETTINGS_FILE) end)
    if not raw or #raw < 3 then return nil end
    local ok, data = pcall(function() return Svc.Http:JSONDecode(raw) end)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

local function SaveQueueFile()
    if not writefile then return end
    pcall(function()
        local out = {}
        for _, q in ipairs(AF.Queue) do
            if not q.done then table.insert(out, { item = q.item, amount = q.amount }) end
        end
        writefile(QUEUE_FILE, Svc.Http:JSONEncode(out))
    end)
end

local function LoadQueueFile()
    if not (isfile and isfile(QUEUE_FILE)) then return false end
    local raw; pcall(function() raw = readfile(QUEUE_FILE) end)
    if not raw or #raw < 3 then return false end
    local ok, data = pcall(function() return Svc.Http:JSONDecode(raw) end)
    if not ok or type(data) ~= "table" then return false end
    AF.Queue = {}
    for _, q in ipairs(data) do
        if q.item and tonumber(q.amount) and tonumber(q.amount) > 0 then
            table.insert(AF.Queue, { item = q.item, amount = tonumber(q.amount), done = false })
        end
    end
    print("[HazeHub] Queue: " .. #AF.Queue .. " Items geladen")
    return #AF.Queue > 0
end

local function RemoveFromQueue(itemName)
    for i = #AF.Queue, 1, -1 do
        if AF.Queue[i].item == itemName then table.remove(AF.Queue, i) end
    end
    SaveQueueFile()
end

local function SyncInventoryWithQueue()
    local changed = false
    for i = #AF.Queue, 1, -1 do
        local q = AF.Queue[i]
        if not q.done then
            local cur = GetLiveInvAmt(q.item)
            local need = tonumber(q.amount) or 1
            if need < 1 then need = 1 end
            if cur >= need then table.remove(AF.Queue, i); changed = true end
        end
    end
    if changed then SaveQueueFile() end
    return changed
end

-- ============================================================
--  DB
-- ============================================================
local function DBCount()
    local c = 0; for _ in pairs(AF.RewardDatabase) do c = c + 1 end; return c
end

local function SaveDB()
    if not writefile then return end
    pcall(function() writefile(DB_FILE, Svc.Http:JSONEncode(AF.RewardDatabase)) end)
    print("[HazeHub] DB gespeichert: " .. DBCount() .. " Chapters")
end

local function LoadDB()
    if not (isfile and isfile(DB_FILE)) then return false end
    local raw; pcall(function() raw = readfile(DB_FILE) end)
    if not raw or #raw < 10 then return false end
    local ok, data = pcall(function() return Svc.Http:JSONDecode(raw) end)
    if not ok or type(data) ~= "table" then return false end
    local c = 0; for _ in pairs(data) do c = c + 1 end
    if c == 0 then return false end
    AF.RewardDatabase = data
    _G.HazeShared._AutoFarm_RewardDB = AF.RewardDatabase
    print("[HazeHub] DB geladen: " .. c .. " Chapters")
    return true
end

local function BuildDBFromModuleData()
    local candidates = {
        "Worlds",
        "WorldData",
        "WorldService",
        "StageData",
        "Rewards",
    }
    local built = {}

    local function addEntry(chapId, worldId, mode, itemName, dropRate, dropAmount)
        if not chapId or chapId == "" or not itemName or itemName == "" then return end
        if not built[chapId] then
            built[chapId] = { world = worldId or "Unknown", mode = mode or "Story", chapId = chapId, items = {} }
        end
        built[chapId].items[itemName] = {
            dropRate = tonumber(dropRate) or 0,
            dropAmount = tonumber(dropAmount) or 1,
        }
    end

    local function parseStage(stageKey, stageData, worldId, mode)
        if type(stageData) ~= "table" then return end
        local chapId = tostring(stageData.chapId or stageData.chapterId or stageData.StageId or stageData.Chapter or stageKey)
        local rewardContainers = {
            stageData.items, stageData.Items, stageData.rewards, stageData.Rewards,
            stageData.drop, stageData.Drop, stageData.drops, stageData.Drops,
        }
        for _, container in ipairs(rewardContainers) do
            if type(container) == "table" then
                for iname, idata in pairs(container) do
                    if type(idata) == "table" then
                        addEntry(chapId, worldId, mode, tostring(idata.item or idata.name or idata.ItemName or iname),
                            idata.dropRate or idata.rate or idata.chance or idata.DropRate,
                            idata.dropAmount or idata.amount or idata.DropAmount)
                    else
                        addEntry(chapId, worldId, mode, tostring(iname), 0, 1)
                    end
                end
            end
        end
    end

    for _, name in ipairs(candidates) do
        local mod = nil
        pcall(function()
            local shared = RS:FindFirstChild("Shared")
            local info = shared and shared:FindFirstChild("Info")
            local target = info and info:FindFirstChild(name)
            if target and target:IsA("ModuleScript") then
                mod = require(target)
            end
        end)
        if type(mod) == "table" then
            for worldKey, worldData in pairs(mod) do
                if type(worldData) == "table" then
                    local worldId = tostring(worldData.world or worldData.World or worldKey)
                    local mode = tostring(worldData.mode or worldData.Mode or "Story")
                    local stageContainers = {
                        worldData.stages, worldData.Stages, worldData.chapters, worldData.Chapters,
                        worldData.story, worldData.Story, worldData.ranger, worldData.Ranger,
                    }
                    local parsedAny = false
                    for _, sc in ipairs(stageContainers) do
                        if type(sc) == "table" then
                            parsedAny = true
                            for stageKey, stageData in pairs(sc) do
                                parseStage(stageKey, stageData, worldId, mode)
                            end
                        end
                    end
                    if not parsedAny then
                        parseStage(worldKey, worldData, worldId, mode)
                    end
                end
            end
        end
    end

    local c = 0
    for _ in pairs(built) do c = c + 1 end
    if c == 0 then return false end

    AF.RewardDatabase = built
    _G.HazeShared._AutoFarm_RewardDB = AF.RewardDatabase
    _G.HazeHUB_Database = AF.RewardDatabase
    SaveDB()
    print("[HazeHub] DB aus Shared.Info aufgebaut: " .. c .. " Chapters")
    return true
end

local function ClearDB()
    AF.RewardDatabase = {}
    if writefile then pcall(function() writefile(DB_FILE, "{}") end) end
end

local function NotifyDBReady(chapCount, msg)
    pcall(function()
        if HS.OnDBReady then HS.OnDBReady(chapCount, msg) end
        if ST then ST.DBReady = true end
    end)
end

-- ============================================================
--  STATUS
-- ============================================================
-- ============================================================
--  SICHERE STATUS-UPDATE FUNKTION (beugt nil-Errors vor)
-- ============================================================
local function UpdateStatus(label, message, color)
    if label and typeof(label) == "Instance" and label:IsA("TextLabel") then
        label.Text = message
        if color then label.TextColor3 = color end
    end
end

local function SetStatus(text, color)
    UpdateStatus(AF.UI.Lbl.Status, text, color)
end

local function SetScanProgress(current, total, label)
    local pct = math.max(0, math.min(1, current / math.max(1, total)))
    local txt = string.format("%s  (%d/%d – %.0f%%)", label, current, total, pct * 100)
    UpdateStatus(AF.UI.Lbl.ScanProgress, txt, D.Yellow)
    if AF.UI.Fr.ScanBar and AF.UI.Fr.ScanBarFill then
        AF.UI.Fr.ScanBar.Visible = true
        Tw(AF.UI.Fr.ScanBarFill, { Size = UDim2.new(pct, 0, 1, 0) }, TF)
    end
end

-- ============================================================
--  ★ RAID_DEFS + ChapterLevels-Scanner (vor Deep-Scan & UI)
-- ============================================================
local RAID_DEFS = {
    {
        id        = "EsperRaid",
        label     = "🔮 Esper Raid",
        world     = "EsperRaid",
        chapters  = {
            { id = "Esper_Raid_Chapter1", label = "Chapter 1", modes = {"Normal","Nightmare"} },
        },
        scanPath  = "ChapterLevels",
        itemsPath = "PlayRoom.Main.GameStage.Main.Base.Rewards.ItemsList",
        accent    = Color3.fromRGB(160, 80, 255),
    },
    {
        id        = "JJKRaid",
        label     = "🌀 JJK Raid",
        world     = "JJKRaid",
        chapters  = {
            { id = "JJK_Raid_Chapter1", label = "Chapter 1", modes = {"Normal"} },
            { id = "JJK_Raid_Chapter2", label = "Chapter 2", modes = {"Normal"} },
        },
        scanPath  = "ChapterLevels",
        itemsPath = "PlayRoom.Main.GameStage.Main.Base.Rewards.ItemsList",
        accent    = Color3.fromRGB(80, 140, 255),
    },
}

local RaidState = {
    Active   = false,
    Running  = false,
    SelRaid  = nil,
    SelChap  = nil,
    SelMode  = "Normal",
    BestChap = nil,
    BestMode = nil,
}

local function ReadChapterIdsFromFolder(folder)
    local ids = {}
    local seen = {}
    if not folder then return ids end
    for _, ch in ipairs(folder:GetChildren()) do
        if ch:IsA("UIGridLayout") or ch:IsA("UIListLayout") or ch:IsA("UIPadding") or ch:IsA("UICorner") then
            continue
        end
        if ch:IsA("Folder") then
            for _, c2 in ipairs(ch:GetChildren()) do
                local id = tostring(c2.Name)
                if id ~= "" and not seen[id] then
                    seen[id] = true
                    table.insert(ids, id)
                end
            end
        else
            local id = tostring(ch.Name)
            if id ~= "" and not seen[id] then
                seen[id] = true
                table.insert(ids, id)
            end
        end
    end
    return ids
end

-- RS.Player_Data[LP.Name].ChapterLevels → Raid-Kapitel-IDs (Fallback: RAID_DEFS)
local function GetRaidChapterIdsFromPlayerData(worldKey, fallbackChapters)
    local ids = {}
    local seen = {}
    local function add(id)
        id = tostring(id or "")
        if id == "" or seen[id] then return end
        seen[id] = true
        table.insert(ids, id)
    end
    pcall(function()
        local pd = RS:FindFirstChild("Player_Data")
        if not pd then return end
        local pf = pd:FindFirstChild(LP.Name)
        if not pf then return end
        local cl = pf:FindFirstChild("ChapterLevels")
        if not cl then return end
        local candidates = {
            worldKey,
            (worldKey:gsub("Raid", "_Raid")),
            worldKey == "EsperRaid" and "Esper" or nil,
            worldKey == "JJKRaid" and "JJK" or nil,
        }
        local sub = nil
        for _, name in ipairs(candidates) do
            if name and cl:FindFirstChild(name) then
                sub = cl:FindFirstChild(name)
                break
            end
        end
        if sub then
            for _, id in ipairs(ReadChapterIdsFromFolder(sub)) do
                add(id)
            end
        end
    end)
    if #ids == 0 and type(fallbackChapters) == "table" then
        for _, ch in ipairs(fallbackChapters) do
            if ch and ch.id then add(ch.id) end
        end
    end
    return ids
end

local function AppendRaidScanTasks(tasks)
    local esperIds = GetRaidChapterIdsFromPlayerData("EsperRaid", RAID_DEFS[1] and RAID_DEFS[1].chapters)
    for _, cid in ipairs(esperIds) do
        table.insert(tasks, { worldId = "EsperRaid", chapId = cid, mode = "EsperRaid", difficulty = "Normal" })
        table.insert(tasks, { worldId = "EsperRaid", chapId = cid, mode = "EsperRaid", difficulty = "Nightmare" })
    end
    local jjkIds = GetRaidChapterIdsFromPlayerData("JJKRaid", RAID_DEFS[2] and RAID_DEFS[2].chapters)
    for _, cid in ipairs(jjkIds) do
        table.insert(tasks, { worldId = "JJKRaid", chapId = cid, mode = "JJKRaid", difficulty = "Normal" })
    end
end

local function RewardDbKeyForTask(t)
    local base = tostring(t.chapId or "unknown")
    if t.mode == "EsperRaid" and t.difficulty == "Nightmare" then
        return base .. " [Nightmare]"
    end
    return base
end

-- ============================================================
--  ★ ScanRewardsSafe
--  Pfad: LP.PlayerGui.PlayRoom.Main.GameStage.Main.Base.Rewards.ItemsList
--  ★ LP.Name ist bereits dynamisch durch LP = Players.LocalPlayer
-- ============================================================
local function ScanRewardsSafe()
    local rewards = {}
    local ok, list = pcall(function()
        return LP.PlayerGui.PlayRoom.Main.GameStage.Main.Base.Rewards.ItemsList
    end)
    if not ok or not list then return rewards, false end

    pcall(function()
        for _, item in pairs(list:GetChildren()) do
            if item:IsA("UIGridLayout") or item:IsA("UIListLayout")
            or item:IsA("UIPageLayout") or item:IsA("UITableLayout")
            or item:IsA("UIPadding") or item:IsA("UICorner") then continue end

            if item:IsA("Frame") or item:IsA("ImageLabel") or item:IsA("TextButton") or item:IsA("TextLabel") then
                local iname = item.Name
                local rate  = 0
                local amt   = 1

                pcall(function()
                    local inf = item:FindFirstChild("Info")
                    if inf then
                        local nv = inf:FindFirstChild("ItemNames")
                        local rv = inf:FindFirstChild("DropRate")
                        local av = inf:FindFirstChild("DropAmount")
                        if nv and tostring(nv.Value) ~= "" then iname = tostring(nv.Value) end
                        if rv then rate = tonumber(rv.Value) or 0 end
                        if av then amt  = tonumber(av.Value) or 1 end
                    else
                        local nv = item:FindFirstChild("ItemNames")
                        local rv = item:FindFirstChild("DropRate")
                        local av = item:FindFirstChild("DropAmount")
                        if nv and tostring(nv.Value) ~= "" then iname = tostring(nv.Value) end
                        if rv then rate = tonumber(rv.Value) or 0 end
                        if av then amt  = tonumber(av.Value) or 1 end
                    end
                end)

                if iname ~= "" and not iname:match("^UI") and not iname:match("^Frame$") then
                    rewards[iname] = { dropRate = rate, dropAmount = amt }
                    print(string.format("[HazeHub] Item: '%s'  Rate=%.1f%%", iname, rate))
                end
            end
        end
    end)

    local cnt = 0; for _ in pairs(rewards) do cnt = cnt + 1 end
    return rewards, cnt > 0
end

local function WaitForItemsListFilled(timeoutSec)
    timeoutSec = timeoutSec or 5
    local deadline = os.clock() + timeoutSec
    while os.clock() < deadline do
        local ok, list = pcall(function()
            return LP.PlayerGui.PlayRoom.Main.GameStage.Main.Base.Rewards.ItemsList
        end)
        if ok and list then
            local n = 0
            for _, child in pairs(list:GetChildren()) do
                if child:IsA("Frame") or child:IsA("ImageLabel") or child:IsA("TextButton") then
                    n = n + 1
                end
            end
            if n > 0 then return true end
        end
        task.wait(0.3)
    end
    return false
end

-- ============================================================
--  ★ DEEP-SCAN  (2s Pflicht-Delay nach Change-Chapter)
-- ============================================================
local function ScanAllRewards(onProgress)
    if AF.Scanning then return false end
    if not HS.IsScanDone() then
        pcall(function() onProgress("Weltdaten fehlen – Game-Tab öffnen!") end)
        return false
    end
    AF.Scanning = true; AF.RewardDatabase = {}
    local WorldData = nil
    local WorldIds = nil
    pcall(function() WorldData = HS.GetWorldData() end)
    pcall(function() WorldIds = HS.GetWorldIds() end)
    if type(WorldData) ~= "table" then WorldData = {} end
    if type(WorldIds) ~= "table" then WorldIds = {} end

    local tasks = {}
    for _, wid in ipairs(WorldIds) do
        local wkey = tostring(wid or "")
        if wkey == "" then continue end
        local wd = WorldData[wkey]
        if type(wd) ~= "table" then continue end
        local storyList = wd.story
        local rangerList = wd.ranger
        if type(storyList) ~= "table" then storyList = {} end
        if type(rangerList) ~= "table" then rangerList = {} end
        local isCal = wkey:lower():find("calamity") ~= nil
        for _, cid in ipairs(storyList) do
            if cid == nil or tostring(cid) == "" then continue end
            table.insert(tasks, { worldId = wkey, chapId = cid, mode = isCal and "Calamity" or "Story" })
        end
        for _, cid in ipairs(rangerList) do
            if cid == nil or tostring(cid) == "" then continue end
            table.insert(tasks, { worldId = wkey, chapId = cid, mode = "Ranger" })
        end
    end

    pcall(function() AppendRaidScanTasks(tasks) end)

    local total = 0
    for _ in ipairs(tasks) do total = total + 1 end
    local scanned = 0
    local failed = 0
    local retried = 0
    if total == 0 then
        AF.Scanning = false
        pcall(function() onProgress("Keine Chapters!") end)
        return false
    end
    print(string.format("[HazeHub] DEEP-SCAN START: %d Chapters", total))
    Fire("Create")
    task.wait(1.5)

    for _, t in ipairs(tasks) do
        if not AF.Scanning then break end
        scanned = scanned + 1
        local diffLabel = (t.difficulty and t.difficulty ~= "Normal") and (" " .. tostring(t.difficulty)) or ""
        SetScanProgress(scanned, total, string.format("Scanne: %s %s%s...", t.worldId or "?", tostring(t.chapId), diffLabel))
        pcall(function()
            onProgress(string.format("Scanne %d/%d: [%s] %s%s", scanned, total, tostring(t.mode), tostring(t.chapId), diffLabel))
        end)
        print(string.format("[HazeHub] [%s] %s > %s (%d/%d)", tostring(t.mode), tostring(t.worldId), tostring(t.chapId), scanned, total))

        if t.mode == "Story" then
            Fire("Create")
            task.wait(0.5)
            Fire("Change-World", { World = t.worldId })
            task.wait(0.5)
            Fire("Change-Chapter", { Chapter = t.chapId })
            task.wait(2.0)
        elseif t.mode == "Ranger" then
            Fire("Create")
            task.wait(0.5)
            Fire("Change-Mode", { KeepWorld = t.worldId, Mode = "Ranger Stage" })
            task.wait(1.0)
            Fire("Change-World", { World = t.worldId })
            task.wait(0.5)
            Fire("Change-Chapter", { Chapter = t.chapId })
            task.wait(2.0)
        elseif t.mode == "Calamity" then
            Fire("Create")
            task.wait(0.5)
            Fire("Change-Mode", { Mode = "Calamity" })
            task.wait(0.5)
            Fire("Change-Chapter", { Chapter = t.chapId })
            task.wait(2.0)
        elseif t.mode == "EsperRaid" then
            Fire("Create")
            task.wait(0.5)
            Fire("Change-World", { ["World"] = "EsperRaid" })
            task.wait(0.4)
            Fire("Change-Chapter", { Chapter = t.chapId })
            task.wait(2.0)
            if t.difficulty == "Nightmare" then
                Fire("Change-Difficulty", { Difficulty = "Nightmare" })
                task.wait(0.35)
            end
        elseif t.mode == "JJKRaid" then
            Fire("Create")
            task.wait(0.5)
            Fire("Change-World", { ["World"] = "JJKRaid" })
            task.wait(0.4)
            Fire("Change-Chapter", { Chapter = t.chapId })
            task.wait(2.0)
        else
            failed = failed + 1
            warn(string.format("[HazeHub] Scan: unbekannter Modus – überspringe (%s)", tostring(t.mode)))
            pcall(function() onProgress("SKIP: " .. tostring(t.chapId)) end)
            continue
        end

        local filled = WaitForItemsListFilled(3)
        if not filled then
            print(string.format("[HazeHub] Retry für %s...", tostring(t.chapId)))
            task.wait(2.0)
            filled = WaitForItemsListFilled(2)
            if filled then retried = retried + 1 end
        end

        local dbKey = RewardDbKeyForTask(t)
        if filled then
            local items, hasItems = ScanRewardsSafe()
            local cnt = 0
            for _ in pairs(items) do cnt = cnt + 1 end
            if hasItems then
                AF.RewardDatabase[dbKey] = {
                    world = t.worldId,
                    mode = t.mode,
                    chapId = t.chapId,
                    items = items,
                    difficulty = t.difficulty,
                }
                print(string.format("[HazeHub] OK [%s] %s: %d Items (DB-Key: %s)", t.mode, tostring(t.chapId), cnt, dbKey))
            else
                failed = failed + 1
                warn(string.format("[HazeHub] LEER [%s] %s", t.mode, tostring(t.chapId)))
                pcall(function() onProgress("LEER: " .. tostring(t.chapId)) end)
            end
        else
            failed = failed + 1
            warn(string.format("[HazeHub] TIMEOUT [%s] %s", t.mode, tostring(t.chapId)))
            pcall(function() onProgress("TIMEOUT: " .. tostring(t.chapId)) end)
        end

        pcall(function()
            Fire("Submit")
            task.wait(0.4)
            Fire("Create")
            task.wait(0.6)
        end)
    end

    if DBCount() > 0 then
        SaveDB()
        _G.HazeShared._AutoFarm_RewardDB = AF.RewardDatabase
        pcall(function()
            if HS.SaveWorldCache then HS.SaveWorldCache() end
        end)
    end
    AF.Scanning = false
    local c=DBCount(); local ok=c>0
    local msg = string.format("%s Scan: %d/%d (%d Fehler, %d Retries)", ok and "OK" or "FEHLER", c, total, failed, retried)
    print("[HazeHub] " .. msg); pcall(function() onProgress(msg) end)
    pcall(function()
        local col = ok and D.Green or D.Orange
        UpdateStatus(AF.UI.Lbl.ScanProgress, msg, col)
        Tw(AF.UI.Fr.ScanBarFill, { Size=UDim2.new(ok and 1 or 0,0,1,0), BackgroundColor3=col }, TM)
        UpdateStatus(AF.UI.Lbl.DBStatus, msg, col)
        if AF.UI.Btn.ForceRescan then AF.UI.Btn.ForceRescan.Text="DATENBANK NEU SCANNEN"; AF.UI.Btn.ForceRescan.TextColor3=Color3.new(1,1,1) end
        if AF.UI.Btn.UpdateDB   then AF.UI.Btn.UpdateDB.Text="Update Database";           AF.UI.Btn.UpdateDB.TextColor3=D.Accent or D.Cyan             end
    end)
    if ok then NotifyDBReady(c, string.format("Datenbank aktualisiert! (%d Chapters, %d Fehler)", c, failed)) end
    return ok
end

-- ============================================================
--  BESTES CHAPTER
-- ============================================================
local function FindBestChapter(itemName)
    local bestChapId = nil
    local bestRate = -1
    local bestWorldId = nil
    local bestMode = nil
    for chapId, data in pairs(AF.RewardDatabase) do
        if data.items and data.items[itemName] then
            local r = data.items[itemName].dropRate or 0
            if r > bestRate then
                bestRate = r
                bestChapId = data.chapId or chapId
                bestWorldId = data.world
                bestMode = data.mode
            end
        end
    end
    if bestChapId then
        print(string.format("[HazeHub] Best '%s': [%s] %s (%.1f%%)", itemName, bestMode, bestChapId, bestRate))
    else
        warn("[HazeHub] '" .. itemName .. "' nicht in DB.")
    end
    return bestChapId, bestWorldId, bestMode, bestRate
end

-- ============================================================
--  QUEUE UI
-- ============================================================
local UpdateQueueUI
UpdateQueueUI = function()
    if not AF.UI.Fr.List then return end
    for _, v in pairs(AF.UI.Fr.List:GetChildren()) do if v:IsA("Frame") then v:Destroy() end end
    local hasActive = false
    for _, q in ipairs(AF.Queue) do if not q.done then hasActive=true; break end end
    if AF.UI.Lbl.QueueEmpty then AF.UI.Lbl.QueueEmpty.Visible = not hasActive end
    local function NextItem()
        for _, q in ipairs(AF.Queue) do if not q.done then return q end end; return nil
    end
    for i, q in ipairs(AF.Queue) do
        if q.done then continue end
        local qa = math.max(1, tonumber(q.amount) or 1)
        local inv = GetLiveInvAmt(q.item)
        local pct = math.min(1, inv / qa)
        local isNext = (NextItem() == q)
        local row=Instance.new("Frame",AF.UI.Fr.List); row.Size=UDim2.new(1,0,0,44); row.BorderSizePixel=0; Corner(row,8)
        if isNext then row.BackgroundColor3=D.RowSelect or D.TabActive; Stroke(row,D.Accent or D.Cyan,1.5,0)
        else            row.BackgroundColor3=D.Card;                 Stroke(row,D.Border,1,0.4) end
        local barC=isNext and (D.Accent or D.Cyan) or D.Purple
        local bar=Instance.new("Frame",row); bar.Size=UDim2.new(0,3,0.65,0); bar.Position=UDim2.new(0,0,0.175,0); bar.BackgroundColor3=barC; bar.BorderSizePixel=0; Corner(bar,2)
        local pgBg=Instance.new("Frame",row); pgBg.Size=UDim2.new(1,-52,0,3); pgBg.Position=UDim2.new(0,8,1,-6); pgBg.BackgroundColor3=D.Input; pgBg.BackgroundTransparency=D.GlassPane or 0.18; pgBg.BorderSizePixel=0; Corner(pgBg,2)
        local pgF=Instance.new("Frame",pgBg); pgF.Size=UDim2.new(pct,0,1,0); pgF.BackgroundColor3=barC; pgF.BorderSizePixel=0; Corner(pgF,2)
        local nL=Instance.new("TextLabel",row); nL.Position=UDim2.new(0,12,0,5); nL.Size=UDim2.new(1,-52,0.5,-3); nL.BackgroundTransparency=1; nL.Text=(isNext and "▶ " or "")..q.item; nL.TextColor3=isNext and (D.Accent or D.Cyan) or D.TextHi; nL.TextSize=11; nL.Font=Enum.Font.GothamBold; nL.TextXAlignment=Enum.TextXAlignment.Left; nL.TextTruncate=Enum.TextTruncate.AtEnd
        local pL=Instance.new("TextLabel",row); pL.Position=UDim2.new(0,12,0.5,1); pL.Size=UDim2.new(1,-52,0.5,-5); pL.BackgroundTransparency=1; pL.Text=string.format("%d / %d  (%.0f%%)",inv,qa,pct*100); pL.TextColor3=D.TextMid; pL.TextSize=10; pL.Font=Enum.Font.GothamSemibold; pL.TextXAlignment=Enum.TextXAlignment.Left
        local ci=i
        local xBtn=Instance.new("TextButton",row); xBtn.Size=UDim2.new(0,34,0,34); xBtn.Position=UDim2.new(1,-38,0.5,-17); xBtn.BackgroundColor3=Color3.fromRGB(50,12,12); xBtn.Text="✕"; xBtn.TextColor3=D.Red; xBtn.TextSize=13; xBtn.Font=Enum.Font.GothamBold; xBtn.AutoButtonColor=false; xBtn.BorderSizePixel=0; Corner(xBtn,7); Stroke(xBtn,D.Red,1,0.4)
        xBtn.MouseEnter:Connect(function() Tw(xBtn,{BackgroundColor3=D.RedDark}) end)
        xBtn.MouseLeave:Connect(function() Tw(xBtn,{BackgroundColor3=Color3.fromRGB(50,12,12)}) end)
        xBtn.MouseButton1Click:Connect(function()
            if AF.Queue[ci] then table.remove(AF.Queue,ci); SaveQueueFile() end; UpdateQueueUI()
        end)
    end
end

-- ============================================================
--  ★ RUNDEN-MONITOR
-- ============================================================
local function RoundMonitorLoop(q)
    local need = math.max(1, tonumber(q.amount) or 1)
    print("[HazeHub] RUNDE: Tracker '" .. q.item .. "'")
    SetStatus(string.format("RUNDE: Warte auf '%s'", q.item), D.TextMid)
    local deadline = os.time() + 600
    while AF.Running and os.time() < deadline do
        if CheckIsLobby() then print("[HazeHub] Tracker: Lobby erkannt."); break end
        task.wait(4)
        local cur = GetLiveInvAmt(q.item)
        print(string.format("[HazeHub] '%s': %d/%d", q.item, cur, need))
        SetStatus(string.format("RUNDE: '%s'  %d/%d  (%.0f%%)",
            q.item, cur, need, math.min(100, cur / need * 100)), D.Cyan)
        pcall(UpdateQueueUI); pcall(function() HS.UpdateGoalsUI() end)

        if cur >= need then
            print(string.format("[HazeHub] ZIEL ERREICHT: '%s' %d/%d → Teleport zur Lobby!", q.item, cur, need))
            task.spawn(function() pcall(function() SendWebhook({}, q.item, cur) end) end)
            RemoveFromQueue(q.item); pcall(UpdateQueueUI)
            SetStatus(string.format("✅ '%s' erreicht! Teleportiere...", q.item), D.GreenBright)
            SaveState()
            DoTeleportToLobby(true)
            local w = 0
            while AF.Running and not CheckIsLobby() and w < 15 do
                task.wait(1); w = w + 1
                print(string.format("[HazeHub] Warte auf Teleport... %d/15s", w))
            end
            return true
        end
    end
    return false
end

-- ============================================================
--  LOBBY-AKTION
-- ============================================================
local function LobbyActionLoop(delaySeconds)
    delaySeconds = delaySeconds or 5
    SetStatus(string.format("LOBBY: Nächste Runde in %ds...", delaySeconds), D.Yellow)
    task.wait(delaySeconds)
    if not CheckIsLobby() then return true end
    local changed = SyncInventoryWithQueue(); if changed then pcall(UpdateQueueUI) end
    local function NextItem()
        for _, q in ipairs(AF.Queue) do if not q.done then return q end end; return nil
    end
    local q = NextItem()
    if not q then
        SetStatus("Queue leer – Farm beendet.", D.Green)
        AF.Active=false; AF.Running=false; _G.AutoFarmRunning=false; SaveState()
        if CFG then CFG.AutoFarm=false end
        if SaveConfig  then pcall(SaveConfig)  end
        if SaveSettings then pcall(SaveSettings) end
        return false
    end
    local useChapId, worldId, mode = FindBestChapter(q.item)
    if not useChapId then
        for cid, data in pairs(AF.RewardDatabase) do worldId=data.world; mode=data.mode; useChapId=data.chapId or cid; break end
    end
    if not useChapId then
        local ids = HS.GetWorldIds and HS.GetWorldIds() or {}
        if #ids>0 then local wd=(HS.GetWorldData and HS.GetWorldData() or {})[ids[1]] or {}; if wd.story and #wd.story>0 then worldId=ids[1]; mode="Story"; useChapId=wd.story[1] end end
    end
    if not useChapId then SetStatus("Kein Level für '"..q.item.."'!", D.Orange); RemoveFromQueue(q.item); pcall(UpdateQueueUI); return true end
    SetStatus(string.format("LOBBY: [%s] '%s' → %s", mode or "?", q.item, useChapId), D.Cyan)
    task.spawn(function() pcall(function()
        if mode=="Story" then
            Fire("Create"); task.wait(0.35); Fire("Change-World",{World=worldId}); task.wait(0.35); Fire("Change-Chapter",{Chapter=useChapId}); task.wait(0.35); Fire("Submit"); task.wait(0.50); Fire("Start")
        elseif mode=="Ranger" then
            Fire("Create"); task.wait(0.35); Fire("Change-Mode",{KeepWorld=worldId,Mode="Ranger Stage"}); task.wait(0.50); Fire("Change-World",{World=worldId}); task.wait(0.35); Fire("Change-Chapter",{Chapter=useChapId}); task.wait(0.35); Fire("Submit"); task.wait(0.50); Fire("Start")
        elseif mode=="Calamity" then
            Fire("Create"); task.wait(0.35); Fire("Change-Mode",{Mode="Calamity"}); task.wait(0.35); Fire("Change-Chapter",{Chapter=useChapId}); task.wait(0.35); Fire("Submit"); task.wait(0.50); Fire("Start")
        end
        print("[HazeHub] Raum gestartet: " .. useChapId)
    end) end)
    local ws=os.clock()
    while AF.Running and CheckIsLobby() and os.clock()-ws<30 do task.wait(1) end
    task.wait(1); return true
end

-- ============================================================
--  FARM LOOP
-- ============================================================
local function GetNextItem()
    for _, q in ipairs(AF.Queue) do if not q.done then return q end end; return nil
end

local function AddOrUpdateQueueItem(itemName, amount)
    local iname = tostring(itemName or ""):match("^%s*(.-)%s*$")
    local iamt = math.floor(tonumber(amount) or 0)
    if iname == "" or iamt <= 0 then return false end

    for _, q in ipairs(AF.Queue) do
        if q.item == iname then
            q.amount = math.max(1, (tonumber(q.amount) or 0) + iamt)
            q.done = false
            SaveQueueFile()
            pcall(UpdateQueueUI)
            pcall(function() HS.UpdateGoalsUI() end)
            return true
        end
    end

    table.insert(AF.Queue, { item = iname, amount = iamt, done = false })
    SaveQueueFile()
    pcall(UpdateQueueUI)
    pcall(function() HS.UpdateGoalsUI() end)
    return true
end

local function FarmLoop()
    AF.Active=true; AF.Running=true; _G.AutoFarmRunning=true; SaveState()
    print("[HazeHub] ===== FARM LOOP START =====")
    local firstLobby=true
    while AF.Running do
        if not CheckIsLobby() then
            firstLobby=true
            local q=GetNextItem()
            if not q then
                SetStatus("Queue leer – Teleportiere zur Lobby.", D.Orange)
                task.wait(3); DoTeleportToLobby(false); task.wait(10); break
            end
            RoundMonitorLoop(q); task.wait(2)
        else
            local delay=firstLobby and 5 or 2; firstLobby=false
            local cont=LobbyActionLoop(delay)
            if not cont then break end; task.wait(2)
        end
    end
    AF.Active=false; _G.AutoFarmRunning=false; SaveState()
    print("[HazeHub] ===== FARM LOOP ENDE =====")
    SetStatus("Farm beendet.", D.TextMid)
end

-- ============================================================
--  STOP
-- ============================================================
local function StopFarm()
    AF.Active=false; AF.Running=false; AF.Scanning=false; _G.AutoFarmRunning=false
    if CFG then CFG.AutoFarm=false end
    if SaveConfig  then pcall(SaveConfig)  end
    if SaveSettings then pcall(SaveSettings) end
    SaveState(); SetStatus("Gestoppt.", D.TextMid)
    print("[HazeHub] Farm gestoppt.")
end
HS.StopFarm = StopFarm

HS.StartFarmFromMain = function()
    if AF.Active then SetStatus("Farm läuft!", D.Yellow); return end
    if #AF.Queue==0 then SetStatus("Queue leer!", D.Orange); return end
    if CFG then CFG.AutoFarm=true end
    if SaveConfig  then pcall(SaveConfig)  end
    if SaveSettings then pcall(SaveSettings) end
    if DBCount()==0 then
        SetStatus("DB leer – Scan...", D.Yellow)
        AF.Running=true; _G.AutoFarmRunning=true; SaveState()
        task.spawn(function()
            local ok=ScanAllRewards(function(msg)
                UpdateStatus(AF.UI.Lbl.DBStatus, msg, D.Yellow)
            end)
            if ok and AF.Running and not AF.Active and GetNextItem() then task.spawn(FarmLoop) end
        end)
    else task.spawn(FarmLoop) end
end
HS.AddAutoFarmQueueItem = AddOrUpdateQueueItem
_G.AddAutoFarmQueueItem = AddOrUpdateQueueItem
HS.AddToQueue = AddOrUpdateQueueItem
_G.AddToQueue = AddOrUpdateQueueItem

-- ============================================================
--  SCAN-TASK HELPER
-- ============================================================
local function RunScanTask(forceDelete, thenStartFarm)
    if AF.Scanning then SetStatus("Scan läuft!", D.Yellow); return end
    task.spawn(function()
        if forceDelete then ClearDB() end
        pcall(function()
            UpdateStatus(AF.UI.Lbl.ScanProgress, "Deep-Scan startet...", D.Yellow)
            if AF.UI.Btn.ForceRescan then AF.UI.Btn.ForceRescan.Text="Scannt..."; AF.UI.Btn.ForceRescan.TextColor3=D.Yellow end
        end)
        SetStatus("Deep-Scan läuft...", D.Purple)
        local ok=ScanAllRewards(function(msg)
            UpdateStatus(AF.UI.Lbl.DBStatus, msg, D.Yellow)
        end)
        pcall(function()
            if AF.UI.Btn.ForceRescan then AF.UI.Btn.ForceRescan.Text="DATENBANK NEU SCANNEN"; AF.UI.Btn.ForceRescan.TextColor3=Color3.new(1,1,1) end
        end)
        if thenStartFarm and ok and DBCount()>0 and AF.Running and not AF.Active and GetNextItem() then task.spawn(FarmLoop) end
    end)
end

-- ============================================================
--  ★ AUTO-RESUME  (Settings.json AutoFarm=true ODER State.running=true)
-- ============================================================
local function TryAutoResume()
    task.wait(3)
    local hasQueue  = LoadQueueFile()
    local state     = LoadState()
    local settings  = LoadSettingsFile()
    local isLobby   = CheckIsLobby()

    -- ★ LP.Name in Log (dynamisch)
    print(string.format(
        "[HazeHub] TryAutoResume [%s]: Lobby=%s  Queue=%s  State.running=%s  Settings.AutoFarm=%s",
        LP.Name,
        tostring(isLobby), tostring(hasQueue),
        tostring(state and state.running),
        tostring(settings and settings.AutoFarm)))

    if hasQueue then SyncInventoryWithQueue(); pcall(UpdateQueueUI) end

    local shouldResume = (settings and settings.AutoFarm == true)
                      or (state and state.running == true)

    if not shouldResume then
        SetStatus(hasQueue and string.format("Queue: %d Items – Farm AUS", #AF.Queue) or "Bereit.", D.TextMid)
        pcall(UpdateQueueUI); return
    end

    if not hasQueue or not GetNextItem() then
        _G.AutoFarmRunning=false
        if CFG then CFG.AutoFarm=false end
        if SaveConfig  then pcall(SaveConfig)  end
        if SaveSettings then pcall(SaveSettings) end
        if writefile then pcall(function() writefile(STATE_FILE, Svc.Http:JSONEncode({running=false,ts=os.time()})) end) end
        SetStatus("Queue leer – Farm nicht fortgesetzt.", D.Orange); pcall(UpdateQueueUI); return
    end

    if DBCount()==0 then LoadDB() end
    if DBCount()==0 then
        SetStatus("DB fehlt – Farm kann nicht fortgesetzt werden!", D.Orange)
        warn("[HazeHub] TryAutoResume: DB leer."); return
    end

    SetStatus(string.format("Auto-Resume: Farm startet in 5s... (%d Items)", #AF.Queue), D.Yellow)
    print("[HazeHub] Auto-Resume: Warte 5s...")
    task.wait(5)

    if not GetNextItem() then SetStatus("Auto-Resume: Queue leer.", D.Orange); return end

    if CheckIsLobby() then
        print("[HazeHub] Auto-Resume: In Lobby → FarmLoop starten.")
        task.spawn(FarmLoop)
    else
        print("[HazeHub] Auto-Resume: In Runde → RoundMonitor starten.")
        AF.Active=true; AF.Running=true; _G.AutoFarmRunning=true; SaveState()
        task.spawn(function()
            local q=GetNextItem()
            if q then
                RoundMonitorLoop(q); task.wait(2)
                while AF.Running do
                    if not CheckIsLobby() then
                        local nq=GetNextItem()
                        if not nq then DoTeleportToLobby(false); task.wait(10); break end
                        RoundMonitorLoop(nq); task.wait(2)
                    else
                        local cont=LobbyActionLoop(3); if not cont then break end; task.wait(2)
                    end
                end
                AF.Active=false; _G.AutoFarmRunning=false; SaveState()
            end
        end)
    end
    pcall(UpdateQueueUI)
end

-- Hintergrund-Sync
task.spawn(function()
    while true do task.wait(10)
        if #AF.Queue>0 then local changed=SyncInventoryWithQueue(); if changed then pcall(UpdateQueueUI) end end
    end
end)

-- ============================================================
--  GUI AUFBAUEN
-- ============================================================
VList(Container,5)

-- STATUS
local sCard=Card(Container,36); Pad(sCard,6,10,6,10)
AF.UI.Lbl.Status=Instance.new("TextLabel",sCard)
AF.UI.Lbl.Status.Size=UDim2.new(1,0,1,0); AF.UI.Lbl.Status.BackgroundTransparency=1
AF.UI.Lbl.Status.Text="Auto-Farm gestoppt"; AF.UI.Lbl.Status.TextColor3=D.TextMid
AF.UI.Lbl.Status.TextSize=11; AF.UI.Lbl.Status.Font=Enum.Font.GothamSemibold
AF.UI.Lbl.Status.TextXAlignment=Enum.TextXAlignment.Left

-- LOCATION
local locCard=Card(Container,22); Pad(locCard,2,10,2,10)
local locLbl=Instance.new("TextLabel",locCard)
locLbl.Size=UDim2.new(1,0,1,0); locLbl.BackgroundTransparency=1
locLbl.Text="Ort: wird erkannt..."; locLbl.TextColor3=D.TextLow
locLbl.TextSize=10; locLbl.Font=Enum.Font.Gotham; locLbl.TextXAlignment=Enum.TextXAlignment.Left
task.spawn(function()
    while true do task.wait(2); pcall(function()
        if CheckIsLobby() then locLbl.Text="📍 LOBBY"; locLbl.TextColor3=D.Green
        else                    locLbl.Text="⚔ RUNDE";  locLbl.TextColor3=D.Orange end
    end) end
end)

-- DB-KARTE wurde entfernt - Status wird jetzt im Header angezeigt

-- QUEUE-KARTE
local qCard=Card(Container); Pad(qCard,10,10,10,10); VList(qCard,8); SecLbl(qCard,"AUTO-FARM QUEUE")
local qFileInfo=MkLbl(qCard,"Keine Queue.",10,D.TextLow); qFileInfo.Size=UDim2.new(1,0,0,14); AF.UI.Lbl.QueueFileInfo=qFileInfo
local qRow=Instance.new("Frame",qCard); qRow.Size=UDim2.new(1,0,0,30); qRow.BackgroundTransparency=1; HList(qRow,5)
local qItemOuter,qItemBox=MkInput(qRow,"Item-Name..."); qItemOuter.Size=UDim2.new(0.50,0,0,30)
local qAmtOuter,qAmtBox=MkInput(qRow,"Anzahl"); qAmtOuter.Size=UDim2.new(0.28,0,0,30)
local qAddBtn=Instance.new("TextButton",qRow); qAddBtn.Size=UDim2.new(0.19,0,0,30); qAddBtn.BackgroundColor3=D.Green; qAddBtn.Text="+ Add"; qAddBtn.TextColor3=Color3.new(1,1,1); qAddBtn.TextSize=11; qAddBtn.Font=Enum.Font.GothamBold; qAddBtn.AutoButtonColor=false; qAddBtn.BorderSizePixel=0; Corner(qAddBtn,7); Stroke(qAddBtn,D.Green,1,0.2)
qAddBtn.MouseEnter:Connect(function() Tw(qAddBtn,{BackgroundColor3=Color3.fromRGB(0,160,80)}) end)
qAddBtn.MouseLeave:Connect(function() Tw(qAddBtn,{BackgroundColor3=D.Green}) end)
qAddBtn.MouseButton1Click:Connect(function()
    local iname=(qItemBox.Text or ""):match("^%s*(.-)%s*$"); local iamt=tonumber(qAmtBox.Text)
    if iname=="" or not iamt or iamt<=0 then return end
    if ST and ST.Goals then local found=false; for _,g in ipairs(ST.Goals) do if g.item==iname then found=true; break end end; if not found then table.insert(ST.Goals,{item=iname,amount=iamt,reached=false}); SaveConfig() end end
    local inQ=false; for _,q in ipairs(AF.Queue) do if q.item==iname then inQ=true; break end end
    if not inQ then table.insert(AF.Queue,{item=iname,amount=iamt,done=false}); SaveQueueFile() end
    qItemBox.Text=""; qAmtBox.Text=""; UpdateQueueUI(); pcall(function() HS.UpdateGoalsUI() end)
    UpdateStatus(AF.UI.Lbl.QueueFileInfo, "Queue: "..#AF.Queue.." Items", D.Green)
end)
local ctrlRow=Instance.new("Frame",qCard); ctrlRow.Size=UDim2.new(1,0,0,32); ctrlRow.BackgroundTransparency=1; ctrlRow.LayoutOrder=3; HList(ctrlRow,8)
local startBtn=Instance.new("TextButton",ctrlRow); startBtn.Size=UDim2.new(0.48,0,0,32); startBtn.BackgroundColor3=D.Green; startBtn.Text="Start Queue"; startBtn.TextColor3=Color3.new(1,1,1); startBtn.TextSize=12; startBtn.Font=Enum.Font.GothamBold; startBtn.AutoButtonColor=false; startBtn.BorderSizePixel=0; Corner(startBtn,8); Stroke(startBtn,D.Green,1,0.2)
local stopBtn=Instance.new("TextButton",ctrlRow); stopBtn.Size=UDim2.new(0.48,0,0,32); stopBtn.BackgroundColor3=D.RedDark; stopBtn.Text="Stop"; stopBtn.TextColor3=D.Red; stopBtn.TextSize=12; stopBtn.Font=Enum.Font.GothamBold; stopBtn.AutoButtonColor=false; stopBtn.BorderSizePixel=0; Corner(stopBtn,8); Stroke(stopBtn,D.Red,1,0.4)
startBtn.MouseButton1Click:Connect(function()
    if AF.Active then SetStatus("Farm läuft!",D.Yellow); return end
    if #AF.Queue==0 then SetStatus("Queue leer!",D.Orange); return end
    if CFG then CFG.AutoFarm=true end; if SaveConfig then pcall(SaveConfig) end; if SaveSettings then pcall(SaveSettings) end
    AF.Running=true; _G.AutoFarmRunning=true; SaveState()
    if DBCount()==0 then SetStatus("DB leer – Scan...",D.Yellow); pcall(function() startBtn.Text="Scannt..."; startBtn.TextColor3=D.Yellow end); RunScanTask(false,true)
    else task.spawn(FarmLoop) end
end)
stopBtn.MouseButton1Click:Connect(function() StopFarm(); startBtn.Text="Start Queue"; startBtn.TextColor3=Color3.new(1,1,1) end)
task.spawn(function() while true do task.wait(1); if not AF.Scanning then pcall(function()
    if startBtn.Text=="Scannt..." then startBtn.Text="Start Queue"; startBtn.TextColor3=Color3.new(1,1,1) end
    if updateDbBtn.Text=="Scannt..." then updateDbBtn.Text="Update Database"; updateDbBtn.TextColor3=D.Accent or D.Cyan end
end) end end end)
task.spawn(function() while true do task.wait(8); pcall(UpdateQueueUI) end end)
local clearBtn=NeonBtn(qCard,"Queue leeren",D.Red,28)
clearBtn.LayoutOrder=4
clearBtn.MouseButton1Click:Connect(function()
    AF.Queue={}; SaveQueueFile(); UpdateQueueUI()
    UpdateStatus(AF.UI.Lbl.QueueFileInfo, "Queue geleert.", D.TextLow)
end)
AF.UI.Fr.List=Instance.new("ScrollingFrame",qCard)
AF.UI.Fr.List.LayoutOrder=5
AF.UI.Fr.List.Size=UDim2.new(1,0,0,190)
AF.UI.Fr.List.CanvasSize=UDim2.new(0,0,0,0)
AF.UI.Fr.List.AutomaticCanvasSize=Enum.AutomaticSize.Y
AF.UI.Fr.List.ScrollBarThickness=4
AF.UI.Fr.List.ScrollBarImageColor3=D.CyanDim
AF.UI.Fr.List.BackgroundTransparency=1
AF.UI.Fr.List.BorderSizePixel=0
VList(AF.UI.Fr.List,4)
AF.UI.Lbl.QueueEmpty=MkLbl(AF.UI.Fr.List,"Queue leer.",11,D.TextLow)
AF.UI.Lbl.QueueEmpty.Size=UDim2.new(1,0,0,24)

-- ============================================================
--  ★ AUTO-CHALLENGE
-- ============================================================
local AF_Challenge = {
    Items    = {},  -- { name, displayName, dropRate, minDrop, maxDrop, chapName, world, chapter }
    Active   = false,
    Running  = false,
    SelIdx   = nil,
    Title    = "Challenge",
}

local function ReadChallengeMetaFromFolder(folder)
    local chapName, world, chapter = "Challenge", "Unknown", "Unknown"
    if not folder then return chapName, world, chapter end
    pcall(function()
        local function gv(name)
            local o = folder:FindFirstChild(name)
            if o and (o:IsA("StringValue") or o:IsA("IntValue") or o:IsA("NumberValue") or o:IsA("ObjectValue")) then
                return tostring(o.Value)
            end
            return nil
        end
        chapName = gv("ChallengeName") or chapName
        world = gv("World") or world
        chapter = gv("Chapter") or chapter
    end)
    return chapName, world, chapter
end

local function ScanChallengeItems()
    AF_Challenge.Items = {}
    AF_Challenge.Title = "Challenge"
    local challengeFolder = nil
    local ok = pcall(function()
        challengeFolder = RS:WaitForChild("Gameplay", 10):WaitForChild("Game", 10):WaitForChild("Challenge", 10)
    end)
    if not ok or not challengeFolder then
        warn("[HazeHub] ScanChallengeItems: RS.Gameplay.Game.Challenge nicht gefunden.")
        return 0
    end

    local chapName, world, chapter = ReadChallengeMetaFromFolder(challengeFolder)
    AF_Challenge.Title = chapName

    local itemsFolder = challengeFolder:FindFirstChild("Items")
    if not itemsFolder then
        warn("[HazeHub] ScanChallengeItems: RS.Gameplay.Game.Challenge.Items fehlt.")
        return 0
    end

    for _, item in ipairs(itemsFolder:GetChildren()) do
        if item:IsA("UIGridLayout") or item:IsA("UIListLayout")
            or item:IsA("UIPadding") or item:IsA("UICorner") or item:IsA("UIScale") then
            continue
        end

        local dropRate = tonumber(item:GetAttribute("DropRate")) or 0
        local maxDrop  = tonumber(item:GetAttribute("MaxDrop")) or 1
        local minDrop  = tonumber(item:GetAttribute("MinDrop")) or 1

        if dropRate == 0 then
            local dr = item:FindFirstChild("DropRate")
            if dr and dr.Value ~= nil then dropRate = tonumber(dr.Value) or 0 end
        end
        if maxDrop == 1 then
            local md = item:FindFirstChild("MaxDrop")
            if md and md.Value ~= nil then maxDrop = tonumber(md.Value) or 1 end
        end
        if minDrop == 1 then
            local mi = item:FindFirstChild("MinDrop")
            if mi and mi.Value ~= nil then minDrop = tonumber(mi.Value) or 1 end
        end

        local avgDrop = (minDrop + maxDrop) / 2
        local score = dropRate * avgDrop

        local displayName = item.Name
        pcall(function()
            local inf = item:FindFirstChild("Info")
            local nv = (inf and inf:FindFirstChild("ItemNames")) or item:FindFirstChild("ItemNames")
            if nv and nv.Value ~= nil and tostring(nv.Value) ~= "" then
                displayName = tostring(nv.Value)
            end
        end)

        table.insert(AF_Challenge.Items, {
            name         = item.Name,
            displayName = displayName,
            chapName    = chapName,
            world       = world,
            chapter     = chapter,
            dropRate    = dropRate,
            minDrop     = minDrop,
            maxDrop     = maxDrop,
            score       = score,
        })
    end

    table.sort(AF_Challenge.Items, function(a, b)
        return a.score > b.score
    end)

    print(string.format("[HazeHub] ScanChallengeItems: %d Items gefunden.", #AF_Challenge.Items))
    return #AF_Challenge.Items
end

local function StartChallengeLoop()
    if AF_Challenge.Running then return end
    local sel = AF_Challenge.SelIdx and AF_Challenge.Items[AF_Challenge.SelIdx]
    if not sel then
        SetStatus("⚠ Kein Challenge-Item gewählt!", D.Orange)
        return
    end
    AF_Challenge.Active = true
    AF_Challenge.Running = true
    task.spawn(function()
        SetStatus(string.format("⚡ Challenge: %s", sel.displayName or sel.name), D.Cyan)
        pcall(function()
            Fire("Create", { ["CreateChallengeRoom"] = true })
        end)
        while AF_Challenge.Running and AF_Challenge.Active do
            task.wait(2)
        end
        AF_Challenge.Running = false
        AF_Challenge.Active = false
        SetStatus("Challenge beendet.", D.TextMid)
    end)
end

-- ── Challenge UI ──────────────────────────────────────────────
local chalCard = Card(Container)
Pad(chalCard, 10, 10, 10, 10); VList(chalCard, 8)
SecLbl(chalCard, "⚡  AUTO-CHALLENGE")

local chalStatusLbl = MkLbl(chalCard, "Challenge Items nicht gescannt.", 10, D.TextLow)
chalStatusLbl.Size = UDim2.new(1, 0, 0, 16)

local chalTitleLbl = MkLbl(chalCard, "", 12, D.Cyan, true)
chalTitleLbl.Size = UDim2.new(1, 0, 0, 22)
chalTitleLbl.Text = ""
chalTitleLbl.Visible = false
chalTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
chalTitleLbl.TextWrapped = true

local chalListFrame = Instance.new("ScrollingFrame", chalCard)
chalListFrame.Size                = UDim2.new(1, 0, 0, 160)
chalListFrame.CanvasSize          = UDim2.new(0, 0, 0, 0)
chalListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
chalListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
chalListFrame.BackgroundTransparency = 1
chalListFrame.BorderSizePixel     = 0
chalListFrame.ScrollBarThickness  = 0
chalListFrame.ScrollBarImageColor3 = D.CyanDim
chalListFrame.ScrollingEnabled    = true
chalListFrame.ScrollingDirection  = Enum.ScrollingDirection.Y
VList(chalListFrame, 4)

local chalEmptyLbl = MkLbl(chalListFrame, "Keine Items gescannt.", 10, D.TextLow)
chalEmptyLbl.Size = UDim2.new(1, 0, 0, 22)

local function RebuildChallengeList()
    for _, v in pairs(chalListFrame:GetChildren()) do
        if v:IsA("Frame") then v:Destroy() end
    end
    local has = #AF_Challenge.Items > 0
    chalEmptyLbl.Visible = not has
    chalTitleLbl.Text = has and (AF_Challenge.Title or "Challenge") or ""
    chalTitleLbl.Visible = has
    for i, item in ipairs(AF_Challenge.Items) do
        local isSel = (AF_Challenge.SelIdx == i)
        local row = Instance.new("Frame", chalListFrame)
        row.Size                   = UDim2.new(1, 0, 0, 44)
        row.BackgroundColor3       = isSel and D.TabActive or D.CardHover
        row.BackgroundTransparency = 0.3
        row.BorderSizePixel        = 0
        Corner(row, 7)
        Stroke(row, isSel and D.Cyan or D.Border, 1.5, isSel and 0 or 0.5)

        local nL = Instance.new("TextLabel", row)
        nL.Position = UDim2.new(0, 8, 0, 3); nL.Size = UDim2.new(1, -16, 0, 18)
        nL.BackgroundTransparency = 1
        nL.Text = item.displayName or item.name
        nL.TextColor3 = isSel and D.Cyan or D.TextHi
        nL.TextSize = 11; nL.Font = Enum.Font.GothamBold
        nL.TextXAlignment = Enum.TextXAlignment.Left; nL.TextTruncate = Enum.TextTruncate.AtEnd

        local sL = Instance.new("TextLabel", row)
        sL.Position = UDim2.new(0, 8, 0, 23); sL.Size = UDim2.new(1, -16, 0, 14)
        sL.BackgroundTransparency = 1
        sL.Text = string.format("Drop: %.1f%%  ·  Min:%d  Max:%d  ·  %s › %s",
            item.dropRate, item.minDrop, item.maxDrop, item.world, item.chapter)
        sL.TextColor3 = D.TextMid; sL.TextSize = 9; sL.Font = Enum.Font.Gotham
        sL.TextXAlignment = Enum.TextXAlignment.Left

        local btn = Instance.new("TextButton", row)
        btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1
        btn.Text = ""; btn.BorderSizePixel = 0
        local capI = i
        btn.MouseButton1Click:Connect(function()
            AF_Challenge.SelIdx = capI; RebuildChallengeList()
        end)
    end
end

local chalScanBtn = NeonBtn(chalCard, "🔍 Challenge Items scannen", D.CyanDim, 28)
chalScanBtn.MouseButton1Click:Connect(function()
    chalScanBtn.Text = "⏳ Scanne..."; chalScanBtn.TextColor3 = D.Yellow
    task.spawn(function()
        local n = ScanChallengeItems()
        RebuildChallengeList()
        chalStatusLbl.Text = n > 0
            and string.format("✅ %d Challenge-Items gefunden.", n)
            or  "⚠ Keine Items gefunden (Pfad prüfen)."
        chalStatusLbl.TextColor3 = n > 0 and D.Green or D.Orange
        chalScanBtn.Text = "🔍 Challenge Items scannen"
        chalScanBtn.TextColor3 = D.CyanDim
    end)
end)

local chalCtrlRow = Instance.new("Frame", chalCard)
chalCtrlRow.Size = UDim2.new(1, 0, 0, 32); chalCtrlRow.BackgroundTransparency = 1
HList(chalCtrlRow, 8)

local chalStartBtn = Instance.new("TextButton", chalCtrlRow)
chalStartBtn.Size = UDim2.new(0.58, 0, 0, 32)
chalStartBtn.BackgroundColor3 = D.Green; chalStartBtn.Text = "▶ Start Challenge"
chalStartBtn.TextColor3 = Color3.new(1,1,1); chalStartBtn.TextSize = 11
chalStartBtn.Font = Enum.Font.GothamBold; chalStartBtn.AutoButtonColor = false
chalStartBtn.BorderSizePixel = 0; Corner(chalStartBtn, 8); Stroke(chalStartBtn, D.Green, 1, 0.2)

local chalStopBtn = Instance.new("TextButton", chalCtrlRow)
chalStopBtn.Size = UDim2.new(0.38, 0, 0, 32)
chalStopBtn.BackgroundColor3 = D.RedDark; chalStopBtn.Text = "■ Stop"
chalStopBtn.TextColor3 = D.Red; chalStopBtn.TextSize = 11
chalStopBtn.Font = Enum.Font.GothamBold; chalStopBtn.AutoButtonColor = false
chalStopBtn.BorderSizePixel = 0; Corner(chalStopBtn, 8); Stroke(chalStopBtn, D.Red, 1, 0.4)

chalStartBtn.MouseButton1Click:Connect(function()
    if AF_Challenge.Active then SetStatus("⚠ Challenge läuft!", D.Yellow); return end
    StartChallengeLoop()
end)
chalStopBtn.MouseButton1Click:Connect(function()
    AF_Challenge.Active = false; AF_Challenge.Running = false
    SetStatus("⏹ Challenge gestoppt.", D.TextMid)
end)

-- ============================================================
--  ★ RAID FUNCTION (Esper & JJK)  — RAID_DEFS / RaidState weiter oben
-- ============================================================

-- Scanne Drop-Daten aus dem PlayRoom GUI
local function ScanRaidDrops(raidId)
    local results = {}
    pcall(function()
        local plr = game.Players.LocalPlayer
        if not plr or not plr.PlayerGui then return end
        local itemsList = nil
        pcall(function()
            itemsList = plr.PlayerGui.PlayRoom.Main.GameStage.Main.Base.Rewards.ItemsList
        end)
        if not itemsList then return end
        for _, item in ipairs(itemsList:GetChildren()) do
            if item:IsA("UIGridLayout") or item:IsA("UIListLayout") then continue end
            local iname    = item.Name
            local dropAmt  = 0
            local dropRate = 0
            pcall(function()
                local frame     = item:FindFirstChild("Frame")
                local itemFrame = frame and frame:FindFirstChild("ItemFrame")
                local info      = itemFrame and itemFrame:FindFirstChild("Info")
                if info then
                    -- "DropAmonut" ist ein Typo im Spiel – beide prüfen
                    local da = info:FindFirstChild("DropAmonut")
                            or info:FindFirstChild("DropAmount")
                    local dr = info:FindFirstChild("DropRate")
                    if da then dropAmt  = tonumber(da.Text or da.Value) or 0 end
                    if dr then dropRate = tonumber(dr.Text or dr.Value) or 0 end
                end
            end)
            if iname ~= "" then
                results[iname] = {
                    dropAmount = dropAmt,
                    dropRate   = dropRate,
                    score      = (tonumber(dropRate) or 0) * (tonumber(dropAmt) or 1),
                }
            end
        end
    end)
    return results
end

-- Wählt beste Chap+Mode-Kombi anhand DropRate × DropAmount
local function FindBestRaidOption(raidDef)
    local bestScore = -1
    local bestChapIdx, bestMode = 1, "Normal"
    -- Wir müssen für jeden Chap+Mode die Drops scannen
    -- Da wir den GUI-Scan nur im laufenden Spiel nutzen können,
    -- geben wir hier die erste verfügbare Option zurück und
    -- lassen den Live-Scan im Loop entscheiden
    for ci, chap in ipairs(raidDef.chapters) do
        for _, mode in ipairs(chap.modes) do
            -- Fallback-Score: Chapter 1 Normal zuerst
            local score = (ci == 1 and mode == "Normal") and 1 or 0
            if score > bestScore then
                bestScore = score; bestChapIdx = ci; bestMode = mode
            end
        end
    end
    return bestChapIdx, bestMode
end

local function FireStartRaid(raidDef, chapDef, mode)
    pcall(function()
        Fire("Create")
        task.wait(0.4)
        Fire("Change-World", { ["World"] = raidDef.world })
        task.wait(0.4)
        Fire("Change-Chapter", { Chapter = chapDef.id })
        task.wait(0.4)
        if mode == "Nightmare" then
            Fire("Change-Difficulty", { Difficulty = "Nightmare" })
            task.wait(0.35)
        end
        Fire("Submit")
        task.wait(0.5)
        Fire("Start")
    end)
end

local function StartRaidLoop()
    if RaidState.Active then return end
    local raidDef = RaidState.SelRaid and RAID_DEFS[RaidState.SelRaid]
    if not raidDef then SetStatus("⚠ Kein Raid gewählt!", D.Orange); return end
    local chapIdx, mode = RaidState.SelChap or 1, RaidState.SelMode or "Normal"
    local chapDef = raidDef.chapters[chapIdx]
    if not chapDef then SetStatus("⚠ Chapter nicht gefunden!", D.Orange); return end

    RaidState.Active = true; RaidState.Running = true
    SetStatus(string.format("⚔ Raid: %s %s (%s)", raidDef.label, chapDef.label, mode), D.Cyan)

    task.spawn(function()
        while RaidState.Running do
            if CheckIsLobby() then
                SetStatus(string.format("🚀 Starte %s %s", raidDef.label, chapDef.label), D.Yellow)
                FireStartRaid(raidDef, chapDef, mode)
                -- Warten bis Spiel startet
                local ws = os.clock()
                while CheckIsLobby() and os.clock() - ws < 30 and RaidState.Running do
                    task.wait(1)
                end
            else
                -- In Runde: Live-Drop-Scan für Optimierung
                local drops = ScanRaidDrops(raidDef.id)
                local dropInfo = ""
                for iname, d in pairs(drops) do
                    dropInfo = dropInfo .. string.format("%s: %.1f%% ×%d  ", iname, d.dropRate, d.dropAmount)
                end
                SetStatus(string.format("⚔ Raid läuft | %s", #dropInfo > 0 and dropInfo or "..."), D.Cyan)
                -- Warten bis Lobby
                local deadline = os.time() + 600
                while not CheckIsLobby() and os.time() < deadline and RaidState.Running do
                    task.wait(3)
                end
                task.wait(2)
            end
        end
        RaidState.Active = false
        SetStatus("⏹ Raid gestoppt.", D.TextMid)
    end)
end

-- ── Raid UI ───────────────────────────────────────────────────
local raidCard = Card(Container)
Pad(raidCard, 10, 10, 10, 10); VList(raidCard, 8)
SecLbl(raidCard, "⚔  RAID FARM")

-- Raid-Auswahl
local raidSelRow = Instance.new("Frame", raidCard)
raidSelRow.Size = UDim2.new(1, 0, 0, 0)
raidSelRow.AutomaticSize = Enum.AutomaticSize.Y
raidSelRow.BackgroundTransparency = 1
VList(raidSelRow, 4)

for ri, rdef in ipairs(RAID_DEFS) do
    local rRow = Instance.new("Frame", raidSelRow)
    rRow.Size = UDim2.new(1, 0, 0, 0)
    rRow.AutomaticSize = Enum.AutomaticSize.Y
    rRow.BackgroundTransparency = 1
    VList(rRow, 3)

    local rHdr = Instance.new("TextButton", rRow)
    rHdr.Size = UDim2.new(1, 0, 0, 28)
    rHdr.BackgroundColor3 = D.CardHover; rHdr.BackgroundTransparency = 0.3
    rHdr.Text = rdef.label; rHdr.TextColor3 = rdef.accent
    rHdr.TextSize = 12; rHdr.Font = Enum.Font.GothamBold
    rHdr.AutoButtonColor = false; rHdr.BorderSizePixel = 0
    Corner(rHdr, 7); Stroke(rHdr, rdef.accent, 1, 0.4)

    -- Chapter + Mode Buttons
    local chapModeRow = Instance.new("Frame", rRow)
    chapModeRow.Size = UDim2.new(1, 0, 0, 0)
    chapModeRow.AutomaticSize = Enum.AutomaticSize.Y
    chapModeRow.BackgroundTransparency = 1
    chapModeRow.Visible = false
    VList(chapModeRow, 3)

    local capRi = ri
    rHdr.MouseButton1Click:Connect(function()
        RaidState.SelRaid = capRi
        chapModeRow.Visible = not chapModeRow.Visible
        Stroke(rHdr, rdef.accent, 1.5, chapModeRow.Visible and 0 or 0.4)
    end)

    for ci, chap in ipairs(rdef.chapters) do
        local chapRow = Instance.new("Frame", chapModeRow)
        chapRow.Size = UDim2.new(1, 0, 0, 26)
        chapRow.BackgroundTransparency = 1
        HList(chapRow, 4)

        local chapLbl = Instance.new("TextLabel", chapRow)
        chapLbl.Size = UDim2.new(0.35, 0, 1, 0); chapLbl.BackgroundTransparency = 1
        chapLbl.Text = chap.label; chapLbl.TextColor3 = D.TextMid
        chapLbl.TextSize = 10; chapLbl.Font = Enum.Font.GothamSemibold
        chapLbl.TextXAlignment = Enum.TextXAlignment.Left

        for _, modeStr in ipairs(chap.modes) do
            local mb = Instance.new("TextButton", chapRow)
            mb.Size = UDim2.new(0, 70, 1, 0)
            mb.BackgroundColor3 = D.CardHover; mb.BackgroundTransparency = 0.4
            mb.Text = modeStr
            mb.TextColor3 = modeStr == "Nightmare" and D.Red or D.Green
            mb.TextSize = 10; mb.Font = Enum.Font.GothamBold
            mb.AutoButtonColor = false; mb.BorderSizePixel = 0
            Corner(mb, 6); Stroke(mb, modeStr == "Nightmare" and D.Red or D.Green, 1, 0.4)
            local capCi, capMode, capR = ci, modeStr, ri
            mb.MouseButton1Click:Connect(function()
                RaidState.SelRaid = capR
                RaidState.SelChap = capCi
                RaidState.SelMode = capMode
                -- Visuelles Feedback
                mb.BackgroundColor3 = modeStr == "Nightmare" and D.RedDark or D.GreenDark
                local s = mb:FindFirstChildOfClass("UIStroke"); if s then s.Transparency = 0 end
                SetStatus(string.format("✔ Gewählt: %s %s (%s)", rdef.label, chap.label, modeStr), D.Cyan)
            end)
        end
    end
end

local raidCtrlRow = Instance.new("Frame", raidCard)
raidCtrlRow.Size = UDim2.new(1, 0, 0, 32); raidCtrlRow.BackgroundTransparency = 1
HList(raidCtrlRow, 8)

local raidStartBtn = Instance.new("TextButton", raidCtrlRow)
raidStartBtn.Size = UDim2.new(0.58, 0, 0, 32)
raidStartBtn.BackgroundColor3 = D.Green; raidStartBtn.Text = "▶ Start Raid"
raidStartBtn.TextColor3 = Color3.new(1,1,1); raidStartBtn.TextSize = 11
raidStartBtn.Font = Enum.Font.GothamBold; raidStartBtn.AutoButtonColor = false
raidStartBtn.BorderSizePixel = 0; Corner(raidStartBtn, 8); Stroke(raidStartBtn, D.Green, 1, 0.2)

local raidStopBtn = Instance.new("TextButton", raidCtrlRow)
raidStopBtn.Size = UDim2.new(0.38, 0, 0, 32)
raidStopBtn.BackgroundColor3 = D.RedDark; raidStopBtn.Text = "■ Stop"
raidStopBtn.TextColor3 = D.Red; raidStopBtn.TextSize = 11
raidStopBtn.Font = Enum.Font.GothamBold; raidStopBtn.AutoButtonColor = false
raidStopBtn.BorderSizePixel = 0; Corner(raidStopBtn, 8); Stroke(raidStopBtn, D.Red, 1, 0.4)

raidStartBtn.MouseButton1Click:Connect(function()
    if RaidState.Active then SetStatus("⚠ Raid läuft!", D.Yellow); return end
    if not RaidState.SelRaid then SetStatus("⚠ Bitte Raid + Chapter + Modus wählen!", D.Orange); return end
    StartRaidLoop()
end)
raidStopBtn.MouseButton1Click:Connect(function()
    RaidState.Active = false; RaidState.Running = false
    SetStatus("⏹ Raid gestoppt.", D.TextMid)
end)

-- ============================================================
--  STARTUP
-- ============================================================
if isfile and isfile(DB_FILE) then
    local raw; pcall(function() raw=readfile(DB_FILE) end)
    if raw and #raw<10 then UpdateStatus(AF.UI.Lbl.DBStatus, "⚠ DB korrupt!", D.Orange)
    elseif LoadDB() or BuildDBFromModuleData() then
        local c=DBCount(); UpdateStatus(AF.UI.Lbl.DBStatus, string.format("✅ DB: %d Chapters",c), D.Green)
        _G.HazeHUB_Database = AF.RewardDatabase
        task.delay(0.5, function() NotifyDBReady(c, string.format("Datenbank geladen! (%d Chapters)",c)) end)
    else UpdateStatus(AF.UI.Lbl.DBStatus, "Keine DB.", D.TextLow) end
else UpdateStatus(AF.UI.Lbl.DBStatus, "Keine DB.", D.TextLow)

task.spawn(TryAutoResume)
-- ============================================================
--  ★ autofarm.lua – Ergänzung (an das Ende des Startup-Blocks)
--  Einfügen NACH: task.spawn(TryAutoResume)
--  und VOR:       HS.SetModuleLoaded(VERSION)
-- ============================================================

-- ────────────────────────────────────────────────────────────
--  ★ TriggerResetRescan
--  Wird vom Hauptskript (Settings-Tab Button 1) aufgerufen.
--  Löscht die DB im RAM, startet ScanAllRewards() und
--  ruft am Ende NotifyDBReady() auf, damit der Start-Button
--  im Game-Tab wieder freigeschaltet wird.
-- ────────────────────────────────────────────────────────────
HS.TriggerResetRescan = function(onProgress)
    if AF.Scanning then
        pcall(function()
            if onProgress then onProgress("⚠ Scan läuft bereits – bitte warten!") end
        end)
        return
    end

    -- RAM-DB leeren (Datei wurde bereits vom Hauptskript gelöscht)
    ClearDB()

    -- Status-Labels im Autofarm-UI zurücksetzen (ohne DB-Status)
    pcall(function()
        AF.UI.Lbl.ScanProgress.Text   = "Reset & Rescan: startet..."
        AF.UI.Lbl.ScanProgress.TextColor3 = D.Yellow
        if AF.UI.Btn.ForceRescan then
            AF.UI.Btn.ForceRescan.Text       = "Scannt..."
            AF.UI.Btn.ForceRescan.TextColor3 = D.Yellow
        end
        if AF.UI.Btn.UpdateDB then
            AF.UI.Btn.UpdateDB.Text       = "Scannt..."
            AF.UI.Btn.UpdateDB.TextColor3 = D.Yellow
        end
    end)

    -- Deep-Scan asynchron ausführen
    task.spawn(function()
        local combinedProgress = function(msg)
            pcall(function()
                AF.UI.Lbl.ScanProgress.Text = msg
                AF.UI.Lbl.ScanProgress.TextColor3 = D.Yellow
            end)
            if onProgress then pcall(function() onProgress(msg) end) end
        end

        local ok = ScanAllRewards(combinedProgress)

        -- Buttons zurücksetzen
        pcall(function()
            if AF.UI.Btn.ForceRescan then
                AF.UI.Btn.ForceRescan.Text       = "DATENBANK NEU SCANNEN"
                AF.UI.Btn.ForceRescan.TextColor3 = Color3.new(1, 1, 1)
            end
            if AF.UI.Btn.UpdateDB then
                AF.UI.Btn.UpdateDB.Text       = "Update Database"
                AF.UI.Btn.UpdateDB.TextColor3 = D.Accent or D.Cyan
            end
        end)

        local finalMsg = ok
            and string.format("✅ Reset & Rescan fertig! %d Chapters in DB.", DBCount())
            or  "⚠ Scan abgeschlossen (einige Chapters fehlgeschlagen)."

        pcall(function() onProgress(finalMsg) end)

        -- Hauptskript-UI über Ergebnis informieren
        if ok then
            NotifyDBReady(DBCount(), finalMsg)
        end

        print("[HazeHub] TriggerResetRescan: " .. finalMsg)
    end)
end

HS.SetModuleLoaded(VERSION)
pcall(function()
    for _, gui in ipairs(Container:GetDescendants()) do
        if gui:IsA("GuiObject") then
            gui.ZIndex = 1
        end
    end
end)
print(string.format("[HazeHub] autofarm.lua v%s geladen | Spieler: %s | DB: %d Chapters", VERSION, LP.Name, DBCount()))

return AF
