-- ╔══════════════════════════════════════════════════════════╗
--  HazeHUB – autofarm.lua  v4.0.0
--
--  v4.0.0 Änderungen:
--    ✓ Vollständige _G.HazeHUB Tabelle (StartFarm, StopFarm,
--      UpdateWorldData, StartChallenge, ScanChallengeItems usw.)
--    ✓ Challenge-Modul vollständig reintegriert
--      · Scan: RS.Gameplay.Game.Challenge.Items
--      · Attribute: DropRate, MaxDrop, MinDrop pro Item
--      · Start-Remote: PlayRoom.Event:FireServer("Create",
--        {["CreateChallengeRoom"]=true})
--    ✓ Raid als eigener Spielmodus in WELT & KAPITEL AUSWAHL
--      · Modus-Buttons: Story | Ranger | Calamity | Raid
--      · Raid-Dropdown: dynamisch aus ChapterLevels-Scan
--        (JJK_Raid_*, Esper_Raid_*)
--      · Schwierigkeit bei Raids korrekt per SafeFire übermittelt
--    ✓ Alle spielbezogenen Logik-Funktionen aus Hauptskript
--      hierher migriert (CreateRoom, Welt-Wechsel, Start/Stop)
--    ✓ Callback-System: Buttons im Game-Tab rufen _G.HazeHUB.*
--    ✓ SafeFire überall (nil-Check vor FireServer)
-- ╚══════════════════════════════════════════════════════════╝

local VERSION  = "4.0.0"
local LOBBY_ID = 111446873000464
local MAIN_URL = "https://raw.githubusercontent.com/Hazeluxeeeees/Tap-Sim/refs/heads/main/script"

-- ============================================================
--  WARTEN BIS SHARED BEREIT (max 10s)
-- ============================================================
local waited = 0
while not (_G.HazeShared and _G.HazeShared.Container and _G.HazeShared.SetModuleLoaded) do
    task.wait(0.3); waited = waited + 0.3
    if waited >= 10 then warn("[HazeHub] _G.HazeShared nicht bereit."); return end
end

-- ============================================================
--  SHARED ALIASE
-- ============================================================
local HS          = _G.HazeShared
local CFG         = HS.Config
local ST          = HS.State
local D           = HS.D
local TF          = HS.TF;  local TM = HS.TM;  local Tw = HS.Tw
local Svc         = HS.Svc
local Card        = HS.Card;    local NeonBtn  = HS.NeonBtn
local MkLbl       = HS.MkLbl;  local SecLbl   = HS.SecLbl
local MkInput     = HS.MkInput; local VList    = HS.VList
local HList       = HS.HList;   local Pad      = HS.Pad
local Corner      = HS.Corner;  local Stroke   = HS.Stroke
local PR          = HS.PR
local SaveConfig  = HS.SaveConfig
local SaveSettings = HS.SaveSettings
local SendWebhook = HS.SendWebhook
local Container   = HS.Container

local TeleportToLobby = HS.TeleportToLobby or function()
    pcall(function() game:GetService("TeleportService"):Teleport(LOBBY_ID) end)
end

-- ============================================================
--  SERVICES
-- ============================================================
local Players         = game:GetService("Players")
local VirtualUser     = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local LP              = game.Players.LocalPlayer
local RS              = game:GetService("ReplicatedStorage")
local WS              = game:GetService("Workspace")

-- ============================================================
--  DATEIPFADE
-- ============================================================
local FOLDER        = "HazeHUB"
local DB_FILE       = FOLDER .. "/" .. LP.Name .. "_RewardDB.json"
local QUEUE_FILE    = FOLDER .. "/" .. LP.Name .. "_Queue.json"
local STATE_FILE    = FOLDER .. "/" .. LP.Name .. "_State.json"
local SETTINGS_FILE = FOLDER .. "/" .. LP.Name .. "_settings.json"

if makefolder then pcall(function() makefolder(FOLDER) end) end

-- ============================================================
--  SCHWIERIGKEITSGRAD-DEFINITIONEN
-- ============================================================
local DIFF_CHANGES_REWARDS = {
    ["Esper_Raid"]   = true,
    ["JJK_Raid"]     = false,
    ["Calamity"]     = true,
}

local function DiffChangesRewards(chapId)
    if not chapId then return false end
    for prefix, val in pairs(DIFF_CHANGES_REWARDS) do
        if chapId:find(prefix, 1, true) then return val end
    end
    return false
end

local function GetDBKey(chapId, difficulty)
    if DiffChangesRewards(chapId) then
        return (chapId or "?") .. "::" .. (difficulty or "Normal")
    end
    return chapId or "?"
end

local CHAPTER_DIFFICULTIES = {
    ["Calamity_Chapter1"]   = { "Normal", "Hard", "Nightmare" },
    ["Calamity_Chapter2"]   = { "Nightmare" },
    ["Esper_Raid_Chapter1"] = { "Normal", "Nightmare" },
    ["JJK_Raid_Chapter1"]   = { "Normal" },
    ["JJK_Raid_Chapter2"]   = { "Normal" },
}

local function GetDifficultiesForChap(chapId, mode)
    if CHAPTER_DIFFICULTIES[chapId] then
        return CHAPTER_DIFFICULTIES[chapId]
    end
    if mode == "Ranger" then return { "Nightmare" } end
    return { "Normal", "Hard", "Nightmare" }
end

-- ============================================================
--  STATE
-- ============================================================
local AF = {
    Queue          = {},
    Active         = false,
    Running        = false,
    Scanning       = false,
    RewardDatabase = {},
    SelDifficulty  = "Normal",
    -- Challenge-State
    Challenges     = {},           -- gescannte Challenge-Daten
    ChallengeItems = {},           -- gescannte Items aus RS.Gameplay.Game.Challenge.Items
    -- Raid-State (dynamisch gescannt aus ChapterLevels)
    RaidChapters   = {},           -- { {id, label, difficulty, mode} }
    UI             = { Lbl = {}, Fr = {}, Btn = {} },
}
_G.AutoFarmRunning = false

-- ============================================================
--  LOCATION CHECK
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

local function Fire(action, data)
    if PlayRoomEvent then
        pcall(function()
            if data then PlayRoomEvent:FireServer(action, data)
            else         PlayRoomEvent:FireServer(action) end
        end)
    else
        PR(action, data)
    end
end

local function SafeFire(action, data)
    if not action or action == "" then
        warn("[HazeHub] SafeFire: action nil – überspringe."); return
    end
    if data then
        for k, v in pairs(data) do
            if v == nil then
                warn(string.format("[HazeHub] SafeFire '%s': '%s' ist nil.", action, tostring(k)))
                return
            end
        end
    end
    pcall(function()
        if data then PlayRoomEvent:FireServer(action, data)
        else         PlayRoomEvent:FireServer(action) end
    end)
end

-- ============================================================
--  CHALLENGE-MODUL: ITEM-SCAN
--  Pfad: RS.Gameplay.Game.Challenge.Items
--  Attribute pro Item: DropRate, MaxDrop, MinDrop
-- ============================================================
local function ScanChallengeItems()
    local items = {}
    local ok, challengeFolder = pcall(function()
        local gp = RS:WaitForChild("Gameplay", 5)
        local gf = gp:WaitForChild("Game",      5)
        local cf = gf:WaitForChild("Challenge",  5)
        return cf:WaitForChild("Items", 5)
    end)
    if not ok or not challengeFolder then
        warn("[HazeHub] Challenge.Items Pfad nicht gefunden.")
        return items
    end

    for _, item in pairs(challengeFolder:GetChildren()) do
        if item:IsA("Folder") or item:IsA("Model") or item:IsA("BasePart")
           or item:IsA("Configuration") or item:IsA("StringValue") then
            local entry = {
                id       = item.Name,
                label    = item.Name,
                dropRate = tonumber(item:GetAttribute("DropRate")) or 0,
                maxDrop  = tonumber(item:GetAttribute("MaxDrop"))  or 0,
                minDrop  = tonumber(item:GetAttribute("MinDrop"))  or 0,
            }
            -- Fallback: Kind-Werte (falls Attribute als ValueBase-Kinder gespeichert)
            if entry.dropRate == 0 then
                local dr = item:FindFirstChild("DropRate")
                if dr then entry.dropRate = tonumber(dr.Value) or 0 end
            end
            if entry.maxDrop == 0 then
                local md = item:FindFirstChild("MaxDrop")
                if md then entry.maxDrop = tonumber(md.Value) or 0 end
            end
            if entry.minDrop == 0 then
                local mi = item:FindFirstChild("MinDrop")
                if mi then entry.minDrop = tonumber(mi.Value) or 0 end
            end
            table.insert(items, entry)
            print(string.format(
                "[HazeHub] Challenge-Item: %s  DR=%.2f  Max=%d  Min=%d",
                entry.label, entry.dropRate, entry.maxDrop, entry.minDrop))
        end
    end
    AF.ChallengeItems = items
    print("[HazeHub] Challenge-Items gescannt: " .. #items)
    return items
end

-- ============================================================
--  CHALLENGE STARTEN
--  Remote: RS.Remote.Server.PlayRoom.Event:FireServer("Create",
--          {["CreateChallengeRoom"]=true})
-- ============================================================
local function StartChallengeRoom()
    if not PlayRoomEvent then
        warn("[HazeHub] StartChallengeRoom: PlayRoomEvent nil!")
        return false
    end
    local ok = pcall(function()
        PlayRoomEvent:FireServer("Create", { ["CreateChallengeRoom"] = true })
    end)
    if ok then print("[HazeHub] Challenge-Raum erstellt.")
    else  warn("[HazeHub] Challenge-Raum Fehler!") end
    return ok
end

-- ============================================================
--  RAID-KAPITEL-SCAN aus ChapterLevels
--  Erkennt alle Einträge, die "Raid" im Namen tragen.
--  Gibt { {id, label, mode, difficulty} } zurück.
-- ============================================================
local function ScanRaidChapters()
    local raids = {}
    local ok, chapLevels = pcall(function()
        return RS
            :WaitForChild("Player_Data", 5)
            :WaitForChild(LP.Name,       5)
            :WaitForChild("ChapterLevels", 5)
    end)
    if not ok or not chapLevels then
        warn("[HazeHub] ChapterLevels nicht gefunden – Raid-Scan übersprungen.")
        return raids
    end

    for _, child in pairs(chapLevels:GetChildren()) do
        local n = child.Name
        if n:find("Raid", 1, true) then
            -- Esper-Raid unterstützt Normal + Nightmare
            if n:find("Esper", 1, true) then
                table.insert(raids, {
                    id         = n .. "::Normal",
                    label      = "🔮 " .. n .. " (Normal)",
                    chapId     = n,
                    mode       = "EsperRaid",
                    difficulty = "Normal",
                })
                table.insert(raids, {
                    id         = n .. "::Nightmare",
                    label      = "🔮 " .. n .. " (Nightmare)",
                    chapId     = n,
                    mode       = "EsperRaid",
                    difficulty = "Nightmare",
                })
            else
                -- JJK-Raid und alle anderen: nur Normal
                table.insert(raids, {
                    id         = n .. "::Normal",
                    label      = "🗡 " .. n .. " (Normal)",
                    chapId     = n,
                    mode       = "JJKRaid",
                    difficulty = "Normal",
                })
            end
            print("[HazeHub] Raid gescannt: " .. n)
        end
    end

    table.sort(raids, function(a, b) return a.id < b.id end)
    AF.RaidChapters = raids
    print("[HazeHub] Raid-Kapitel gesamt: " .. #raids)
    return raids
end

-- ============================================================
--  ROOM STARTEN – zentrale Funktion
-- ============================================================
local function FireStartRoom(mode, worldId, chapId, difficulty)
    if not chapId or chapId == "" then
        warn("[HazeHub] FireStartRoom: chapId nil – abgebrochen."); return false
    end
    difficulty = difficulty or "Normal"

    local ok = pcall(function()
        if mode == "Story" then
            if not worldId then error("worldId nil") end
            SafeFire("Create")
            task.wait(0.35)
            SafeFire("Change-World",      { World      = worldId })
            task.wait(0.35)
            SafeFire("Change-Chapter",    { Chapter    = chapId })
            task.wait(0.35)
            SafeFire("Change-Difficulty", { Difficulty = difficulty })
            task.wait(0.35)
            SafeFire("Submit")
            task.wait(0.50)
            SafeFire("Start")

        elseif mode == "Ranger" then
            if not worldId then error("worldId nil") end
            SafeFire("Create")
            task.wait(0.35)
            SafeFire("Change-Mode",       { KeepWorld = worldId, Mode = "Ranger Stage" })
            task.wait(0.50)
            SafeFire("Change-World",      { World     = worldId })
            task.wait(0.35)
            SafeFire("Change-Chapter",    { Chapter   = chapId })
            task.wait(0.35)
            SafeFire("Change-Difficulty", { Difficulty = "Nightmare" })
            task.wait(0.35)
            SafeFire("Submit")
            task.wait(0.50)
            SafeFire("Start")

        elseif mode == "EsperRaid" then
            SafeFire("Create")
            task.wait(0.35)
            SafeFire("Change-Mode",       { KeepWorld = "OnePiece", Mode = "Raids Stage" })
            task.wait(0.50)
            SafeFire("Change-World",      { World     = "EsperRaid" })
            task.wait(0.35)
            SafeFire("Change-Chapter",    { Chapter   = chapId })
            task.wait(0.35)
            SafeFire("Change-Difficulty", { Difficulty = difficulty })
            task.wait(0.35)
            SafeFire("Submit")
            task.wait(0.50)
            SafeFire("Start")

        elseif mode == "JJKRaid" then
            SafeFire("Create")
            task.wait(0.35)
            SafeFire("Change-Mode",       { KeepWorld = "OnePiece", Mode = "Raids Stage" })
            task.wait(0.50)
            SafeFire("Change-World",      { World     = "JJKRaid" })
            task.wait(0.35)
            SafeFire("Change-Chapter",    { Chapter   = chapId })
            task.wait(0.35)
            SafeFire("Change-Difficulty", { Difficulty = "Normal" })
            task.wait(0.35)
            SafeFire("Submit")
            task.wait(0.50)
            SafeFire("Start")

        elseif mode == "Calamity" then
            SafeFire("Create")
            task.wait(0.35)
            SafeFire("Change-Mode",       { Mode      = "Calamity" })
            task.wait(0.35)
            SafeFire("Change-Chapter",    { Chapter   = chapId })
            task.wait(0.35)
            SafeFire("Change-Difficulty", { Difficulty = difficulty })
            task.wait(0.35)
            SafeFire("Submit")
            task.wait(0.50)
            SafeFire("Start")

        elseif mode == "Challenge" then
            -- Challenge-Raum über separates Remote
            StartChallengeRoom()
        end
    end)

    if ok then
        print(string.format("[HazeHub] Raum gestartet: [%s/%s] %s", mode, difficulty, chapId))
    end
    return ok
end

-- ============================================================
--  INVENTAR
-- ============================================================
local function GetLiveInvAmt(itemName)
    local n = 0
    pcall(function()
        local f = RS:WaitForChild("Player_Data",3):WaitForChild(LP.Name,3):WaitForChild("Items",3)
        local item = f:FindFirstChild(itemName); if not item then return end
        local vc = item:FindFirstChild("Value") or item:FindFirstChild("Amount")
        if vc then n = tonumber(vc.Value) or 0
        elseif item:IsA("IntValue") or item:IsA("NumberValue") then n = tonumber(item.Value) or 0 end
    end)
    return n
end

-- ============================================================
--  TELEPORT
-- ============================================================
local function DoTeleportToLobby(keepAutoFarm)
    if keepAutoFarm then
        if CFG then CFG.AutoFarm = true end
        pcall(SaveConfig); pcall(SaveSettings)
    end
    print("[HazeHub] Teleportiere zur Lobby ID: " .. LOBBY_ID)
    pcall(function() TeleportService:Teleport(LOBBY_ID) end)
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

-- ============================================================
--  DB
-- ============================================================
local function DBCount()
    local c = 0; for _ in pairs(AF.RewardDatabase) do c = c + 1 end; return c
end

local function SaveDB()
    if not writefile then return end
    pcall(function() writefile(DB_FILE, Svc.Http:JSONEncode(AF.RewardDatabase)) end)
    print("[HazeHub] DB gespeichert: " .. DBCount() .. " Einträge")
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
    print("[HazeHub] DB geladen: " .. c .. " Einträge")
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
local function SetStatus(text, color)
    pcall(function()
        AF.UI.Lbl.Status.Text       = text
        AF.UI.Lbl.Status.TextColor3 = color or D.TextMid
    end)
end

local function SetScanProgress(current, total, label)
    local pct = math.max(0, math.min(1, current / math.max(1, total)))
    local txt = string.format("%s  (%d/%d – %.0f%%)", label, current, total, pct * 100)
    pcall(function()
        AF.UI.Lbl.ScanProgress.Text       = txt
        AF.UI.Lbl.ScanProgress.TextColor3 = D.Yellow
        AF.UI.Fr.ScanBar.Visible          = true
        Tw(AF.UI.Fr.ScanBarFill, { Size = UDim2.new(pct, 0, 1, 0) }, TF)
    end)
end

-- ============================================================
--  REWARD-SCAN (PlayerGui)
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
            or item:IsA("UIPadding")    or item:IsA("UICorner") then continue end

            if item:IsA("Frame") or item:IsA("ImageLabel")
            or item:IsA("TextButton") or item:IsA("TextLabel") then
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
--  DEEP-SCAN TASK-LISTE
-- ============================================================
local function BuildScanTaskList()
    local tasks = {}
    local WorldData = HS.GetWorldData()
    local WorldIds  = HS.GetWorldIds()

    for _, wid in ipairs(WorldIds) do
        local wd = WorldData[wid] or {}
        local isCal     = wid:lower():find("calamity") ~= nil
        local isEsper   = wid == "EsperRaid"
        local isJJKRaid = wid == "JJKRaid"

        for _, cid in ipairs(wd.story or {}) do
            if isCal then
                local diffs = GetDifficultiesForChap(cid, "Calamity")
                for _, diff in ipairs(diffs) do
                    table.insert(tasks, {
                        worldId    = wid, chapId     = cid,
                        mode       = "Calamity",  difficulty = diff,
                        dbKey      = GetDBKey(cid, diff),
                    })
                end
            else
                table.insert(tasks, {
                    worldId    = wid, chapId     = cid,
                    mode       = "Story",     difficulty = "Normal",
                    dbKey      = GetDBKey(cid, "Normal"),
                })
            end
        end

        for _, cid in ipairs(wd.ranger or {}) do
            table.insert(tasks, {
                worldId    = wid, chapId     = cid,
                mode       = "Ranger",    difficulty = "Nightmare",
                dbKey      = GetDBKey(cid, "Nightmare"),
            })
        end

        if isEsper then
            for _, cid in ipairs(wd.story or {}) do
                for _, diff in ipairs({ "Normal", "Nightmare" }) do
                    table.insert(tasks, {
                        worldId    = wid, chapId     = cid,
                        mode       = "EsperRaid", difficulty = diff,
                        dbKey      = GetDBKey(cid, diff),
                    })
                end
            end
        end

        if isJJKRaid then
            for _, cid in ipairs(wd.story or {}) do
                table.insert(tasks, {
                    worldId    = wid, chapId     = cid,
                    mode       = "JJKRaid",   difficulty = "Normal",
                    dbKey      = GetDBKey(cid, "Normal"),
                })
            end
        end
    end

    return tasks
end

-- ============================================================
--  FIRE-ROOM FÜR SCAN (intern)
-- ============================================================
local function FireRoomForScan(t)
    local mode       = t.mode
    local worldId    = t.worldId
    local chapId     = t.chapId
    local difficulty = t.difficulty or "Normal"

    if mode == "Story" then
        Fire("Create");                                          task.wait(0.5)
        Fire("Change-World",      { World      = worldId });     task.wait(0.5)
        Fire("Change-Chapter",    { Chapter    = chapId });      task.wait(2.0)

    elseif mode == "Ranger" then
        Fire("Create");                                          task.wait(0.5)
        Fire("Change-Mode",       { KeepWorld  = worldId, Mode = "Ranger Stage" })
        task.wait(1.0)
        Fire("Change-World",      { World      = worldId });     task.wait(0.5)
        Fire("Change-Chapter",    { Chapter    = chapId });      task.wait(2.0)

    elseif mode == "EsperRaid" then
        Fire("Create");                                          task.wait(0.5)
        Fire("Change-Mode",       { KeepWorld  = "OnePiece", Mode = "Raids Stage" })
        task.wait(0.8)
        Fire("Change-World",      { World      = "EsperRaid" }); task.wait(0.5)
        Fire("Change-Chapter",    { Chapter    = chapId });      task.wait(0.5)
        Fire("Change-Difficulty", { Difficulty = difficulty });  task.wait(2.0)

    elseif mode == "JJKRaid" then
        Fire("Create");                                          task.wait(0.5)
        Fire("Change-Mode",       { KeepWorld  = "OnePiece", Mode = "Raids Stage" })
        task.wait(0.8)
        Fire("Change-World",      { World      = "JJKRaid" });   task.wait(0.5)
        Fire("Change-Chapter",    { Chapter    = chapId });      task.wait(0.5)
        Fire("Change-Difficulty", { Difficulty = "Normal" });    task.wait(2.0)

    elseif mode == "Calamity" then
        Fire("Create");                                          task.wait(0.5)
        Fire("Change-Mode",       { Mode       = "Calamity" }); task.wait(0.5)
        Fire("Change-Chapter",    { Chapter    = chapId });      task.wait(0.5)
        Fire("Change-Difficulty", { Difficulty = difficulty });  task.wait(2.0)
    end
end

-- ============================================================
--  DEEP-SCAN
-- ============================================================
local function ScanAllRewards(onProgress)
    if AF.Scanning then return false end
    if not HS.IsScanDone() then
        pcall(function() onProgress("Weltdaten fehlen – Game-Tab öffnen!") end)
        return false
    end

    AF.Scanning = true; AF.RewardDatabase = {}
    local tasks   = BuildScanTaskList()
    local total   = #tasks
    local scanned = 0
    local failed  = 0
    local retried = 0

    if total == 0 then
        AF.Scanning = false
        pcall(function() onProgress("Keine Chapters zum Scannen!") end)
        return false
    end

    print(string.format("[HazeHub] DEEP-SCAN START: %d Tasks", total))
    Fire("Create"); task.wait(1.5)

    for _, t in ipairs(tasks) do
        if not AF.Scanning then break end
        scanned = scanned + 1

        local label = string.format("[%s/%s] %s", t.mode, t.difficulty, t.chapId)
        SetScanProgress(scanned, total, "Scanne: " .. label)
        pcall(function() onProgress(string.format("Scanne %d/%d: %s", scanned, total, label)) end)
        print(string.format("[HazeHub] %s (%d/%d)", label, scanned, total))

        FireRoomForScan(t)

        local filled = WaitForItemsListFilled(4)
        if not filled then
            print(string.format("[HazeHub] Retry: %s", label))
            task.wait(2.0); filled = WaitForItemsListFilled(2)
            if filled then retried = retried + 1 end
        end

        if filled then
            local items, hasItems = ScanRewardsSafe()
            local cnt = 0; for _ in pairs(items) do cnt = cnt + 1 end
            if hasItems then
                AF.RewardDatabase[t.dbKey] = {
                    world      = t.worldId, mode       = t.mode,
                    chapId     = t.chapId,  difficulty = t.difficulty,
                    dbKey      = t.dbKey,   items      = items,
                }
                print(string.format("[HazeHub] OK %s: %d Items", label, cnt))
            else
                failed = failed + 1
                warn(string.format("[HazeHub] LEER %s", label))
                pcall(function() onProgress("LEER: " .. label) end)
            end
        else
            failed = failed + 1
            warn(string.format("[HazeHub] TIMEOUT %s", label))
            pcall(function() onProgress("TIMEOUT: " .. label) end)
        end

        pcall(function() Fire("Submit"); task.wait(0.4); Fire("Create"); task.wait(0.6) end)
    end

    if DBCount() > 0 then
        SaveDB()
        _G.HazeShared._AutoFarm_RewardDB = AF.RewardDatabase
    end
    AF.Scanning = false

    local c   = DBCount()
    local ok  = c > 0
    local msg = string.format(
        "%s Scan: %d/%d Einträge (%d Fehler, %d Retries)",
        ok and "OK" or "FEHLER", c, total, failed, retried)
    print("[HazeHub] " .. msg)
    pcall(function() onProgress(msg) end)

    pcall(function()
        local col = ok and D.Green or D.Orange
        AF.UI.Lbl.ScanProgress.Text = msg
        AF.UI.Lbl.ScanProgress.TextColor3 = col
        Tw(AF.UI.Fr.ScanBarFill, { Size = UDim2.new(ok and 1 or 0, 0, 1, 0), BackgroundColor3 = col }, TM)
        if AF.UI.Btn.ForceRescan then
            AF.UI.Btn.ForceRescan.Text       = "DATENBANK NEU SCANNEN"
            AF.UI.Btn.ForceRescan.TextColor3 = Color3.new(1,1,1)
        end
    end)

    if ok then NotifyDBReady(c, string.format("Datenbank fertig! (%d Einträge, %d Fehler)", c, failed)) end
    return ok
end

-- ============================================================
--  BESTES CHAPTER FÜR ITEM
-- ============================================================
local function FindBestChapter(itemName)
    local bestKey  = nil
    local bestRate = -1
    local bestData = nil

    for dbKey, data in pairs(AF.RewardDatabase) do
        if data.items and data.items[itemName] then
            local r = data.items[itemName].dropRate or 0
            if data.mode == "Story" or data.mode == "Ranger" then
                local wantedDiff = data.mode == "Ranger" and "Nightmare" or AF.SelDifficulty
                if data.difficulty ~= wantedDiff then continue end
            end
            if r > bestRate then
                bestRate = r; bestKey = dbKey; bestData = data
            end
        end
    end

    if bestData then
        print(string.format("[HazeHub] Best '%s': [%s/%s] %s (%.1f%%)",
            itemName, bestData.mode, bestData.difficulty, bestData.chapId, bestRate))
        return bestData.chapId, bestData.world, bestData.mode, bestData.difficulty, bestRate
    end

    warn("[HazeHub] '" .. itemName .. "' nicht in DB.")
    return nil, nil, nil, nil, 0
end

-- ============================================================
--  QUEUE UI
-- ============================================================
local UpdateQueueUI
UpdateQueueUI = function()
    if not AF.UI.Fr.List then return end
    for _, v in pairs(AF.UI.Fr.List:GetChildren()) do if v:IsA("Frame") then v:Destroy() end end
    local hasActive = false
    for _, q in ipairs(AF.Queue) do if not q.done then hasActive = true; break end end
    if AF.UI.Lbl.QueueEmpty then AF.UI.Lbl.QueueEmpty.Visible = not hasActive end

    local function NextItem()
        for _, q in ipairs(AF.Queue) do if not q.done then return q end end; return nil
    end

    for i, q in ipairs(AF.Queue) do
        if q.done then continue end
        local inv    = GetLiveInvAmt(q.item)
        local pct    = math.min(1, inv / math.max(1, q.amount))
        local isNext = (NextItem() == q)

        local row = Instance.new("Frame", AF.UI.Fr.List)
        row.Size = UDim2.new(1,0,0,44); row.BorderSizePixel = 0; Corner(row,8)
        if isNext then
            row.BackgroundColor3 = D.RowSelect or D.TabActive
            Stroke(row, D.Accent or D.Cyan, 1.5, 0)
        else
            row.BackgroundColor3 = D.Card
            Stroke(row, D.Border, 1, 0.4)
        end

        local barC = isNext and (D.Accent or D.Cyan) or D.Purple
        local bar  = Instance.new("Frame", row)
        bar.Size = UDim2.new(0,3,0.65,0); bar.Position = UDim2.new(0,0,0.175,0)
        bar.BackgroundColor3 = barC; bar.BorderSizePixel = 0; Corner(bar,2)

        local pgBg = Instance.new("Frame", row)
        pgBg.Size = UDim2.new(1,-52,0,3); pgBg.Position = UDim2.new(0,8,1,-6)
        pgBg.BackgroundColor3 = D.Input; pgBg.BackgroundTransparency = D.GlassPane or 0.18
        pgBg.BorderSizePixel = 0; Corner(pgBg,2)
        local pgF = Instance.new("Frame", pgBg)
        pgF.Size = UDim2.new(pct,0,1,0); pgF.BackgroundColor3 = barC
        pgF.BorderSizePixel = 0; Corner(pgF,2)

        local nL = Instance.new("TextLabel", row)
        nL.Position = UDim2.new(0,12,0,5); nL.Size = UDim2.new(1,-52,0.5,-3)
        nL.BackgroundTransparency = 1
        nL.Text = (isNext and "▶ " or "") .. q.item
        nL.TextColor3 = isNext and (D.Accent or D.Cyan) or D.TextHi
        nL.TextSize = 11; nL.Font = Enum.Font.GothamBold
        nL.TextXAlignment = Enum.TextXAlignment.Left; nL.TextTruncate = Enum.TextTruncate.AtEnd

        local pL = Instance.new("TextLabel", row)
        pL.Position = UDim2.new(0,12,0.5,1); pL.Size = UDim2.new(1,-52,0.5,-5)
        pL.BackgroundTransparency = 1
        pL.Text = string.format("%d / %d  (%.0f%%)", inv, q.amount, pct*100)
        pL.TextColor3 = D.TextMid; pL.TextSize = 10; pL.Font = Enum.Font.GothamSemibold
        pL.TextXAlignment = Enum.TextXAlignment.Left

        local ci = i
        local xBtn = Instance.new("TextButton", row)
        xBtn.Size = UDim2.new(0,34,0,34); xBtn.Position = UDim2.new(1,-38,0.5,-17)
        xBtn.BackgroundColor3 = Color3.fromRGB(50,12,12); xBtn.Text = "✕"
        xBtn.TextColor3 = D.Red; xBtn.TextSize = 13; xBtn.Font = Enum.Font.GothamBold
        xBtn.AutoButtonColor = false; xBtn.BorderSizePixel = 0; Corner(xBtn,7); Stroke(xBtn,D.Red,1,0.4)
        xBtn.MouseEnter:Connect(function() Tw(xBtn,{BackgroundColor3=D.RedDark}) end)
        xBtn.MouseLeave:Connect(function() Tw(xBtn,{BackgroundColor3=Color3.fromRGB(50,12,12)}) end)
        xBtn.MouseButton1Click:Connect(function()
            if AF.Queue[ci] then table.remove(AF.Queue, ci); SaveQueueFile() end
            UpdateQueueUI()
        end)
    end
end

-- ============================================================
--  RUNDEN-MONITOR
-- ============================================================
local function RoundMonitorLoop(q)
    print("[HazeHub] RUNDE: Tracker '" .. q.item .. "'")
    SetStatus(string.format("RUNDE: Warte auf '%s'", q.item), D.TextMid)
    local deadline = os.time() + 600

    while AF.Running and os.time() < deadline do
        if CheckIsLobby() then
            print("[HazeHub] Tracker: Lobby erkannt."); break
        end
        task.wait(4)
        local cur = GetLiveInvAmt(q.item)
        SetStatus(string.format("RUNDE: '%s'  %d/%d  (%.0f%%)",
            q.item, cur, q.amount,
            math.min(100, cur / math.max(1, q.amount) * 100)), D.Cyan)
        pcall(UpdateQueueUI)
        pcall(function() HS.UpdateGoalsUI() end)

        if cur >= q.amount then
            print(string.format("[HazeHub] ZIEL ERREICHT: '%s' %d/%d → Teleport!", q.item, cur, q.amount))
            task.spawn(function() pcall(function() SendWebhook({}, q.item, cur) end) end)
            RemoveFromQueue(q.item); pcall(UpdateQueueUI)
            SetStatus(string.format("✅ '%s' erreicht! Teleportiere...", q.item), D.GreenBright)
            SaveState()
            DoTeleportToLobby(true)
            local w = 0
            while AF.Running and not CheckIsLobby() and w < 15 do
                task.wait(1); w = w + 1
            end
            return true
        end
    end
    return false
end

-- ============================================================
--  SYNC INVENTORY → QUEUE
-- ============================================================
local function GetNextItem()
    for _, q in ipairs(AF.Queue) do if not q.done then return q end end; return nil
end

local function SyncInventoryWithQueue()
    local changed = false
    for i = #AF.Queue, 1, -1 do
        local q = AF.Queue[i]
        if not q.done then
            local cur = GetLiveInvAmt(q.item)
            if cur >= q.amount then
                print(string.format("[HazeHub] ZIEL ERREICHT: '%s' %d/%d", q.item, cur, q.amount))
                task.spawn(function() pcall(function() SendWebhook({}, q.item, cur) end) end)
                RemoveFromQueue(q.item); pcall(UpdateQueueUI)
                SetStatus(string.format("✅ '%s' erreicht!", q.item), D.GreenBright)
                SaveState()

                local nextQ = GetNextItem()
                if nextQ and AF.Running then
                    SetStatus(string.format("⏳ Wechsel → '%s'", nextQ.item), D.Yellow)
                    local waitDeadline = os.time() + 600
                    while AF.Running and not CheckIsLobby() and os.time() < waitDeadline do
                        task.wait(3)
                    end
                    if CheckIsLobby() and AF.Running then
                        task.wait(2)
                        local nextChapId, nextWorldId, nextMode, nextDiff = FindBestChapter(nextQ.item)
                        if nextChapId then
                            SetStatus(string.format("🚀 Starte: [%s/%s] %s",
                                nextMode or "?", nextDiff or "?", nextChapId), D.Cyan)
                            task.spawn(function()
                                FireStartRoom(nextMode, nextWorldId, nextChapId, nextDiff)
                            end)
                            return true
                        end
                    end
                    warn("[HazeHub] Queue-Wechsel Timeout – Teleport-Fallback.")
                    DoTeleportToLobby(true)
                    return true
                else
                    SetStatus("✅ Queue leer.", D.Green)
                    AF.Active = false; AF.Running = false; _G.AutoFarmRunning = false
                    if CFG then CFG.AutoFarm = false end
                    pcall(SaveConfig); pcall(SaveSettings); SaveState()
                    return true
                end

                changed = true
            end
        end
    end
    return changed
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

    local q = GetNextItem()
    if not q then
        SetStatus("Queue leer – Farm beendet.", D.Green)
        AF.Active = false; AF.Running = false; _G.AutoFarmRunning = false; SaveState()
        if CFG then CFG.AutoFarm = false end
        pcall(SaveConfig); pcall(SaveSettings)
        return false
    end

    local chapId, worldId, mode, difficulty = FindBestChapter(q.item)

    if not chapId then
        for _, data in pairs(AF.RewardDatabase) do
            worldId = data.world; mode = data.mode
            chapId  = data.chapId or data.dbKey:match("^([^:]+)")
            difficulty = data.difficulty or "Normal"
            break
        end
    end
    if not chapId then
        local ids = HS.GetWorldIds()
        if #ids > 0 then
            local wd = HS.GetWorldData()[ids[1]] or {}
            if wd.story and #wd.story > 0 then
                worldId = ids[1]; mode = "Story"
                chapId  = wd.story[1]; difficulty = "Normal"
            end
        end
    end
    if not chapId then
        SetStatus("Kein Level für '" .. q.item .. "'!", D.Orange)
        RemoveFromQueue(q.item); pcall(UpdateQueueUI); return true
    end

    SetStatus(string.format("LOBBY: [%s/%s] '%s' → %s",
        mode or "?", difficulty or "?", q.item, chapId), D.Cyan)

    task.spawn(function()
        FireStartRoom(mode, worldId, chapId, difficulty)
    end)

    local ws = os.clock()
    while AF.Running and CheckIsLobby() and os.clock() - ws < 30 do
        task.wait(1)
    end
    task.wait(1)
    return true
end

-- ============================================================
--  FARM LOOP
-- ============================================================
local function FarmLoop()
    AF.Active = true; AF.Running = true; _G.AutoFarmRunning = true; SaveState()
    print("[HazeHub] ===== FARM LOOP START =====")
    local firstLobby = true

    while AF.Running do
        if not CheckIsLobby() then
            firstLobby = true
            local q = GetNextItem()
            if not q then
                SetStatus("Queue leer – Teleportiere zur Lobby.", D.Orange)
                task.wait(3); DoTeleportToLobby(false); task.wait(10); break
            end
            RoundMonitorLoop(q); task.wait(2)
        else
            local delay = firstLobby and 5 or 2; firstLobby = false
            local cont = LobbyActionLoop(delay)
            if not cont then break end; task.wait(2)
        end
    end

    AF.Active = false; _G.AutoFarmRunning = false; SaveState()
    print("[HazeHub] ===== FARM LOOP ENDE =====")
    SetStatus("Farm beendet.", D.TextMid)
end

-- ============================================================
--  STOP
-- ============================================================
local function StopFarm()
    AF.Active = false; AF.Running = false; AF.Scanning = false
    _G.AutoFarmRunning = false
    if CFG then CFG.AutoFarm = false end
    pcall(SaveConfig); pcall(SaveSettings)
    SaveState(); SetStatus("Gestoppt.", D.TextMid)
    print("[HazeHub] Farm gestoppt.")
end
HS.StopFarm = StopFarm

-- ============================================================
--  QUEUE ITEM HINZUFÜGEN
-- ============================================================
local function AddOrUpdateQueueItem(itemName, amount)
    local iname = tostring(itemName or ""):match("^%s*(.-)%s*$")
    local iamt  = math.floor(tonumber(amount) or 0)
    if iname == "" or iamt <= 0 then return false end

    for _, q in ipairs(AF.Queue) do
        if q.item == iname then
            q.amount = math.max(1, q.amount + iamt)
            q.done   = false
            SaveQueueFile(); pcall(UpdateQueueUI)
            pcall(function() HS.UpdateGoalsUI() end)
            return true
        end
    end

    table.insert(AF.Queue, { item = iname, amount = iamt, done = false })
    SaveQueueFile(); pcall(UpdateQueueUI)
    pcall(function() HS.UpdateGoalsUI() end)
    return true
end

HS.StartFarmFromMain = function()
    if AF.Active then SetStatus("Farm läuft!", D.Yellow); return end
    if #AF.Queue == 0 then SetStatus("Queue leer!", D.Orange); return end
    if CFG then CFG.AutoFarm = true end
    pcall(SaveConfig); pcall(SaveSettings)
    if DBCount() == 0 then
        SetStatus("DB leer – Scan...", D.Yellow)
        AF.Running = true; _G.AutoFarmRunning = true; SaveState()
        task.spawn(function()
            local ok = ScanAllRewards(function(msg)
                pcall(function() AF.UI.Lbl.ScanProgress.Text = msg end)
            end)
            if ok and AF.Running and not AF.Active and GetNextItem() then
                task.spawn(FarmLoop)
            end
        end)
    else
        task.spawn(FarmLoop)
    end
end

HS.AddAutoFarmQueueItem = AddOrUpdateQueueItem
_G.AddAutoFarmQueueItem  = AddOrUpdateQueueItem
HS.AddToQueue            = AddOrUpdateQueueItem
_G.AddToQueue            = AddOrUpdateQueueItem

-- ============================================================
--  _G.HazeHUB – GLOBALE FUNKTIONS-TABELLE
--  Alle spielbezogenen Logik-Funktionen sind hier definiert.
--  Das Hauptskript ruft diese über Callbacks auf.
-- ============================================================
if not _G.HazeHUB then _G.HazeHUB = {} end

-- Basis-Farm-Steuerung
_G.HazeHUB.StartFarm = function()
    HS.StartFarmFromMain()
end

_G.HazeHUB.StopFarm = function()
    StopFarm()
end

_G.HazeHUB.IsFarmActive = function()
    return AF.Active
end

-- Welt-/Kapitel-Daten für UI-Buttons im Hauptskript
_G.HazeHUB.UpdateWorldData = function()
    -- Triggert einen Neuaufbau der Weltliste (via HS.GetWorldData)
    -- Das Hauptskript-UI kann RebuildWorldList() aufrufen.
    if _G.HazeHUB.RebuildWorldList then
        pcall(_G.HazeHUB.RebuildWorldList)
    end
    print("[HazeHub] UpdateWorldData aufgerufen.")
end

-- Raum erstellen & starten (wird vom "Create & Start Room"-Button aufgerufen)
_G.HazeHUB.CreateAndStartRoom = function(mode, worldId, chapId, difficulty)
    if not chapId then
        warn("[HazeHub] CreateAndStartRoom: kein chapId!"); return false
    end
    return FireStartRoom(mode, worldId, chapId, difficulty or "Normal")
end

-- Raid starten (für Raid-Buttons im Game-Tab)
_G.HazeHUB.StartRaid = function(raidEntry)
    -- raidEntry = { chapId, mode, difficulty } aus dem Raid-Dropdown
    if type(raidEntry) == "table" then
        FireStartRoom(raidEntry.mode, nil, raidEntry.chapId, raidEntry.difficulty)
    else
        -- Fallback: ersten gefundenen Raid starten
        if #AF.RaidChapters > 0 then
            local r = AF.RaidChapters[1]
            FireStartRoom(r.mode, nil, r.chapId, r.difficulty)
        else
            warn("[HazeHub] StartRaid: keine Raid-Kapitel verfügbar!")
        end
    end
end

_G.HazeHUB.StopRaid = function()
    StopFarm()
end

-- Challenge starten
_G.HazeHUB.StartChallenge = function()
    return StartChallengeRoom()
end

-- Challenge-Items scannen und zurückgeben
_G.HazeHUB.ScanChallengeItems = function()
    local items = ScanChallengeItems()
    -- Status-Update im UI
    pcall(function()
        if AF.UI.Lbl.ChallengeStatus then
            AF.UI.Lbl.ChallengeStatus.Text = string.format(
                "✅ %d Challenge-Items gescannt", #items)
            AF.UI.Lbl.ChallengeStatus.TextColor3 = D.Green
        end
    end)
    return items
end

-- Raid-Kapitel scannen und Dropdown aktualisieren
_G.HazeHUB.ScanAndUpdateRaids = function()
    local raids = ScanRaidChapters()
    -- Callback zum Aktualisieren des Raid-Dropdowns im UI
    if _G.HazeHUB.RebuildRaidDropdown then
        pcall(_G.HazeHUB.RebuildRaidDropdown, raids)
    end
    return raids
end

-- Raid-Kapitel für externes UI abrufen
_G.HazeHUB.GetRaidChapters = function()
    return AF.RaidChapters
end

-- Challenge-Items für externes UI abrufen
_G.HazeHUB.GetChallengeItems = function()
    return AF.ChallengeItems
end

-- Schwierigkeit setzen (für Callbacks aus dem Hauptskript)
_G.HazeHUB.SetDifficulty = function(diff)
    AF.SelDifficulty = diff or "Normal"
end

-- DB neu scannen (Callback für Rescan-Button)
_G.HazeHUB.TriggerRescan = function(onProgress)
    if AF.Scanning then
        if onProgress then pcall(onProgress, "⚠ Scan läuft bereits!") end
        return
    end
    ClearDB()
    task.spawn(function()
        ScanAllRewards(onProgress or function() end)
    end)
end

-- Status-Update Callback (für Hauptskript-Labels)
_G.HazeHUB.UpdateStatus = function(text, color)
    SetStatus(text, color)
end

-- Queue-Steuerung
_G.HazeHUB.AddToQueue = AddOrUpdateQueueItem
_G.HazeHUB.ClearQueue = function()
    AF.Queue = {}; SaveQueueFile(); pcall(UpdateQueueUI)
end
_G.HazeHUB.GetQueue = function()
    return AF.Queue
end

-- Hilfsfunktionen
_G.HazeHUB.IsInLobby = function()
    return CheckIsLobby()
end

_G.HazeHUB.TeleportToLobby = function(keepFarm)
    DoTeleportToLobby(keepFarm)
end

-- ============================================================
--  AUTO-RESUME
-- ============================================================
local function TryAutoResume()
    task.wait(3)
    local hasQueue = LoadQueueFile()
    local state    = LoadState()
    local settings = LoadSettingsFile()

    print(string.format(
        "[HazeHub] TryAutoResume [%s]: Lobby=%s Queue=%s State.running=%s Settings.AutoFarm=%s",
        LP.Name, tostring(CheckIsLobby()), tostring(hasQueue),
        tostring(state and state.running),
        tostring(settings and settings.AutoFarm)))

    if hasQueue then SyncInventoryWithQueue(); pcall(UpdateQueueUI) end

    local shouldResume = (settings and settings.AutoFarm == true)
                      or (state    and state.running     == true)

    if not shouldResume then
        SetStatus(hasQueue
            and string.format("Queue: %d Items – Farm AUS", #AF.Queue)
            or  "Bereit.", D.TextMid)
        pcall(UpdateQueueUI); return
    end

    if not hasQueue or not GetNextItem() then
        _G.AutoFarmRunning = false
        if CFG then CFG.AutoFarm = false end
        pcall(SaveConfig); pcall(SaveSettings)
        if writefile then
            pcall(function() writefile(STATE_FILE, Svc.Http:JSONEncode({running=false,ts=os.time()})) end)
        end
        SetStatus("Queue leer – Farm nicht fortgesetzt.", D.Orange)
        pcall(UpdateQueueUI); return
    end

    if DBCount() == 0 then LoadDB() end
    if DBCount() == 0 then
        SetStatus("DB fehlt – Farm kann nicht fortgesetzt werden!", D.Orange)
        warn("[HazeHub] TryAutoResume: DB leer."); return
    end

    SetStatus(string.format("Auto-Resume: Farm startet in 5s... (%d Items)", #AF.Queue), D.Yellow)
    task.wait(5)

    if not GetNextItem() then SetStatus("Auto-Resume: Queue leer.", D.Orange); return end

    if CheckIsLobby() then
        task.spawn(FarmLoop)
    else
        AF.Active = true; AF.Running = true; _G.AutoFarmRunning = true; SaveState()
        task.spawn(function()
            local q = GetNextItem()
            if q then
                RoundMonitorLoop(q); task.wait(2)
                while AF.Running do
                    if not CheckIsLobby() then
                        local nq = GetNextItem()
                        if not nq then DoTeleportToLobby(false); task.wait(10); break end
                        RoundMonitorLoop(nq); task.wait(2)
                    else
                        local cont = LobbyActionLoop(3); if not cont then break end; task.wait(2)
                    end
                end
                AF.Active = false; _G.AutoFarmRunning = false; SaveState()
            end
        end)
    end
    pcall(UpdateQueueUI)
end

-- Hintergrund-Sync
task.spawn(function()
    while true do task.wait(10)
        if #AF.Queue > 0 then
            local changed = SyncInventoryWithQueue()
            if changed then pcall(UpdateQueueUI) end
        end
    end
end)

-- ============================================================
--  GUI
-- ============================================================
VList(Container, 5)

-- STATUS
local sCard = Card(Container, 36); Pad(sCard, 6,10,6,10)
AF.UI.Lbl.Status = Instance.new("TextLabel", sCard)
AF.UI.Lbl.Status.Size = UDim2.new(1,0,1,0)
AF.UI.Lbl.Status.BackgroundTransparency = 1
AF.UI.Lbl.Status.Text = "Auto-Farm gestoppt"
AF.UI.Lbl.Status.TextColor3 = D.TextMid
AF.UI.Lbl.Status.TextSize = 11
AF.UI.Lbl.Status.Font = Enum.Font.GothamSemibold
AF.UI.Lbl.Status.TextXAlignment = Enum.TextXAlignment.Left

-- LOCATION
local locCard = Card(Container, 22); Pad(locCard, 2,10,2,10)
local locLbl  = Instance.new("TextLabel", locCard)
locLbl.Size = UDim2.new(1,0,1,0); locLbl.BackgroundTransparency = 1
locLbl.Text = "Ort: wird erkannt..."; locLbl.TextColor3 = D.TextLow
locLbl.TextSize = 10; locLbl.Font = Enum.Font.Gotham
locLbl.TextXAlignment = Enum.TextXAlignment.Left
task.spawn(function()
    while true do task.wait(2); pcall(function()
        if CheckIsLobby() then locLbl.Text = "📍 LOBBY"; locLbl.TextColor3 = D.Green
        else                   locLbl.Text = "⚔ RUNDE";  locLbl.TextColor3 = D.Orange end
    end) end
end)

-- ============================================================
--  WELT & KAPITEL AUSWAHL (mit Raid als eigenem Modus)
-- ============================================================
local worldCard = Card(Container); Pad(worldCard, 10,10,10,10); VList(worldCard, 8)
SecLbl(worldCard, "🌍  WELT & KAPITEL AUSWAHL")

-- Modus-Auswahl: Story | Ranger | Calamity | Raid | Challenge
local modeSelRow = Instance.new("Frame", worldCard)
modeSelRow.Size = UDim2.new(1,0,0,28); modeSelRow.BackgroundTransparency = 1; HList(modeSelRow, 4)

local WORLD_MODI = {
    { id = "Story",     label = "📖",  color = D.Cyan   },
    { id = "Ranger",    label = "🏹",  color = D.Green  },
    { id = "Calamity",  label = "⚡",  color = D.Orange },
    { id = "Raid",      label = "⚔",  color = D.Purple },
    { id = "Challenge", label = "🏆",  color = D.Gold   },
}

local SelWorldMode = "Story"
local SelWorldId   = nil
local SelChapId    = nil
local SelRaidEntry = nil  -- aktuelle Raid-Auswahl { chapId, mode, difficulty }

AF.UI.Btn.WorldModeBtns = {}

-- Schwierigkeit für Story/Calamity
local SelDiffForRoom = "Normal"

-- Kapitel-Buttons Rebuild
local ChapBtnsFrame = Instance.new("Frame", worldCard)
ChapBtnsFrame.Size = UDim2.new(1,0,0,0); ChapBtnsFrame.AutomaticSize = Enum.AutomaticSize.Y
ChapBtnsFrame.BackgroundTransparency = 1; HList(ChapBtnsFrame, 4)

local WorldStatusLbl = Instance.new("TextLabel", worldCard)
WorldStatusLbl.Size = UDim2.new(1,0,0,16); WorldStatusLbl.BackgroundTransparency = 1
WorldStatusLbl.Text = "Modus → Welt → Kapitel wählen"
WorldStatusLbl.TextColor3 = D.TextLow; WorldStatusLbl.TextSize = 10
WorldStatusLbl.Font = Enum.Font.GothamSemibold
WorldStatusLbl.TextXAlignment = Enum.TextXAlignment.Left

local function HighlightWorldMode(activeId)
    for _, def in ipairs(WORLD_MODI) do
        local mb = AF.UI.Btn.WorldModeBtns[def.id]; if not mb then continue end
        if def.id == activeId then
            local c = def.color
            local rr = math.clamp(math.floor(c.R*255*0.22),0,255)
            local rg = math.clamp(math.floor(c.G*255*0.22),0,255)
            local rb = math.clamp(math.floor(c.B*255*0.22),0,255)
            Tw(mb, { BackgroundColor3 = Color3.fromRGB(rr,rg,rb) })
            Stroke(mb, c, 1.5, 0)
        else
            Tw(mb, { BackgroundColor3 = D.CardHover })
            Stroke(mb, D.Border, 1, 0.5)
        end
    end
end

-- Raid-Dropdown: wird dynamisch mit Raid-Kapitel-Daten befüllt
local RaidDropCard = Card(worldCard); Pad(RaidDropCard, 8,8,8,8); VList(RaidDropCard, 5)
RaidDropCard.Visible = false
SecLbl(RaidDropCard, "RAID KAPITEL WÄHLEN")

local RaidScrollFrame = Instance.new("ScrollingFrame", RaidDropCard)
RaidScrollFrame.Size = UDim2.new(1,0,0,120)
RaidScrollFrame.CanvasSize = UDim2.new(0,0,0,0)
RaidScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
RaidScrollFrame.ScrollBarThickness = 4
RaidScrollFrame.ScrollBarImageColor3 = D.CyanDim
RaidScrollFrame.BackgroundTransparency = 1
RaidScrollFrame.BorderSizePixel = 0
VList(RaidScrollFrame, 3)

local RaidStatusLbl = MkLbl(RaidDropCard, "⏳ Raid-Kapitel laden...", 10, D.Yellow)
RaidStatusLbl.Size = UDim2.new(1,0,0,18)

local function RebuildRaidDropdown(raidList)
    raidList = raidList or AF.RaidChapters
    for _, v in pairs(RaidScrollFrame:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end
    SelRaidEntry = nil

    if not raidList or #raidList == 0 then
        RaidStatusLbl.Text = "⚠ Keine Raid-Kapitel gefunden – Rescan klicken"
        RaidStatusLbl.TextColor3 = D.Orange
        return
    end

    RaidStatusLbl.Text = string.format("✅ %d Raid-Kapitel verfügbar", #raidList)
    RaidStatusLbl.TextColor3 = D.Green

    for _, entry in ipairs(raidList) do
        local capEntry = entry
        local btn = Instance.new("TextButton", RaidScrollFrame)
        btn.Size = UDim2.new(1,0,0,28); btn.BackgroundColor3 = D.CardHover
        btn.Text = entry.label; btn.TextColor3 = D.TextHi
        btn.TextSize = 11; btn.Font = Enum.Font.GothamSemibold
        btn.AutoButtonColor = false; btn.BorderSizePixel = 0
        Corner(btn, 7); Stroke(btn, D.Border, 1, 0.4)

        btn.MouseButton1Click:Connect(function()
            SelRaidEntry = capEntry
            SelChapId    = capEntry.chapId
            -- Alle Buttons zurücksetzen
            for _, ch in pairs(RaidScrollFrame:GetChildren()) do
                if ch:IsA("TextButton") then
                    Tw(ch, { BackgroundColor3 = D.CardHover }); Stroke(ch, D.Border, 1, 0.4)
                end
            end
            Tw(btn, { BackgroundColor3 = D.RowSelect }); Stroke(btn, D.Purple, 1.5, 0)
            WorldStatusLbl.Text = string.format(
                "⚔ %s  [%s]", capEntry.label, capEntry.difficulty)
            WorldStatusLbl.TextColor3 = D.Purple
        end)
    end
end

-- Callback für _G.HazeHUB
_G.HazeHUB.RebuildRaidDropdown = RebuildRaidDropdown

-- Scan-Button für Raids
local raidScanBtn = NeonBtn(RaidDropCard, "🔄 Raids neu scannen", D.Purple, 28)
raidScanBtn.MouseButton1Click:Connect(function()
    RaidStatusLbl.Text = "⏳ Scanne Raid-Kapitel..."
    RaidStatusLbl.TextColor3 = D.Yellow
    task.spawn(function()
        local raids = ScanRaidChapters()
        RebuildRaidDropdown(raids)
    end)
end)

-- Challenge-Sektion
local ChallengeCard = Card(worldCard); Pad(ChallengeCard, 8,8,8,8); VList(ChallengeCard, 6)
ChallengeCard.Visible = false
SecLbl(ChallengeCard, "🏆  CHALLENGE")

AF.UI.Lbl.ChallengeStatus = MkLbl(ChallengeCard, "Challenge-Items nicht gescannt.", 10, D.TextLow)
AF.UI.Lbl.ChallengeStatus.Size = UDim2.new(1,0,0,18)

local challengeItemsFrame = Instance.new("ScrollingFrame", ChallengeCard)
challengeItemsFrame.Size = UDim2.new(1,0,0,100)
challengeItemsFrame.CanvasSize = UDim2.new(0,0,0,0)
challengeItemsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
challengeItemsFrame.ScrollBarThickness = 4
challengeItemsFrame.ScrollBarImageColor3 = D.CyanDim
challengeItemsFrame.BackgroundTransparency = 1
challengeItemsFrame.BorderSizePixel = 0
VList(challengeItemsFrame, 3)

local function RebuildChallengeItemsUI(items)
    for _, v in pairs(challengeItemsFrame:GetChildren()) do if v:IsA("Frame") then v:Destroy() end end
    if not items or #items == 0 then return end

    for _, item in ipairs(items) do
        local row = Instance.new("Frame", challengeItemsFrame)
        row.Size = UDim2.new(1,0,0,32); row.BackgroundColor3 = D.CardHover
        row.BorderSizePixel = 0; Corner(row, 7); Stroke(row, D.Gold, 1, 0.5)

        local bar = Instance.new("Frame", row)
        bar.Size = UDim2.new(0,3,0.6,0); bar.Position = UDim2.new(0,0,0.2,0)
        bar.BackgroundColor3 = D.Gold; bar.BorderSizePixel = 0; Corner(bar, 2)

        local nL = Instance.new("TextLabel", row)
        nL.Position = UDim2.new(0,10,0,3); nL.Size = UDim2.new(0.55,-10,0,13)
        nL.BackgroundTransparency = 1; nL.Text = item.label
        nL.TextColor3 = D.TextHi; nL.TextSize = 10; nL.Font = Enum.Font.GothamBold
        nL.TextXAlignment = Enum.TextXAlignment.Left; nL.TextTruncate = Enum.TextTruncate.AtEnd

        local infoL = Instance.new("TextLabel", row)
        infoL.Position = UDim2.new(0.55,0,0,3); infoL.Size = UDim2.new(0.45,-6,0,26)
        infoL.BackgroundTransparency = 1
        infoL.Text = string.format("DR:%.1f  %d–%d",
            item.dropRate, item.minDrop, item.maxDrop)
        infoL.TextColor3 = D.Gold; infoL.TextSize = 9; infoL.Font = Enum.Font.GothamSemibold
        infoL.TextXAlignment = Enum.TextXAlignment.Right; infoL.TextWrapped = true
    end
end

local scanChallengeBtn = NeonBtn(ChallengeCard, "🔍 Challenge-Items scannen", D.Gold, 28)
scanChallengeBtn.MouseButton1Click:Connect(function()
    AF.UI.Lbl.ChallengeStatus.Text = "⏳ Scanne Challenge-Items..."
    AF.UI.Lbl.ChallengeStatus.TextColor3 = D.Yellow
    task.spawn(function()
        local items = ScanChallengeItems()
        RebuildChallengeItemsUI(items)
        AF.UI.Lbl.ChallengeStatus.Text = string.format(
            "✅ %d Items gescannt  (DropRate | Min–Max)", #items)
        AF.UI.Lbl.ChallengeStatus.TextColor3 = D.Green
    end)
end)

local startChallengeBtn = NeonBtn(ChallengeCard, "🏆 Challenge-Raum starten", D.Gold, 32)
startChallengeBtn.MouseButton1Click:Connect(function()
    if not CheckIsLobby() then
        AF.UI.Lbl.ChallengeStatus.Text = "⚠ Nur in Lobby möglich!"
        AF.UI.Lbl.ChallengeStatus.TextColor3 = D.Red
        return
    end
    StartChallengeRoom()
    AF.UI.Lbl.ChallengeStatus.Text = "✅ Challenge-Raum erstellt!"
    AF.UI.Lbl.ChallengeStatus.TextColor3 = D.Green
end)

-- Welt-Buttons (Story/Ranger)
local worldBtnFrame = Instance.new("Frame", worldCard)
worldBtnFrame.Size = UDim2.new(1,0,0,0); worldBtnFrame.AutomaticSize = Enum.AutomaticSize.Y
worldBtnFrame.BackgroundTransparency = 1; VList(worldBtnFrame, 4)

local function RebuildChapBtns(chapList)
    for _, v in pairs(ChapBtnsFrame:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end
    if not chapList or #chapList == 0 then return end
    SelChapId = chapList[1]
    for i, cid in ipairs(chapList) do
        local num = cid:match("(%d+)$") or tostring(i)
        local cb = Instance.new("TextButton", ChapBtnsFrame)
        cb.Size = UDim2.new(0,34,0,26); cb.BackgroundColor3 = D.CardHover; cb.Text = num
        cb.TextColor3 = D.TextHi; cb.TextSize = 12; cb.Font = Enum.Font.GothamBold
        cb.AutoButtonColor = false; cb.BorderSizePixel = 0; Corner(cb,7); Stroke(cb,D.Border,1,0.4)
        local capCid = cid
        cb.MouseButton1Click:Connect(function()
            SelChapId = capCid
            for _, b in pairs(ChapBtnsFrame:GetChildren()) do
                if b:IsA("TextButton") then
                    Tw(b,{BackgroundColor3=D.CardHover}); local s=b:FindFirstChildOfClass("UIStroke"); if s then s.Color=D.Border; s.Transparency=0.4 end
                end
            end
            Tw(cb,{BackgroundColor3=D.RowSelect}); Stroke(cb,D.Accent,1.5,0)
            WorldStatusLbl.Text = string.format("⚙ %s [%s] → %s", SelWorldId or "?", SelWorldMode, capCid)
            WorldStatusLbl.TextColor3 = D.Cyan
        end)
    end
    if ChapBtnsFrame:FindFirstChildOfClass("TextButton") then
        local first = ChapBtnsFrame:FindFirstChildOfClass("TextButton")
        Tw(first,{BackgroundColor3=D.RowSelect}); Stroke(first,D.Accent,1.5,0)
    end
end

local function RebuildWorldBtns()
    for _, v in pairs(worldBtnFrame:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end
    for _, v in pairs(ChapBtnsFrame:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end

    local worldData = HS.GetWorldData()
    local worldIds  = HS.GetWorldIds()

    if SelWorldMode == "Calamity" then
        SelWorldId = "Calamity"
        local wd = worldData["Calamity"] or {}
        RebuildChapBtns(wd.story or {})
        WorldStatusLbl.Text = "⚡ Calamity → Kapitel wählen"
        WorldStatusLbl.TextColor3 = D.Orange
        return
    end

    if SelWorldMode == "Raid" then
        -- Raid-Modus: kein Welt-Button, direkt Dropdown
        WorldStatusLbl.Text = "⚔ Raid → Kapitel aus Liste wählen"
        WorldStatusLbl.TextColor3 = D.Purple
        -- Raids scannen falls noch leer
        if #AF.RaidChapters == 0 then
            task.spawn(function()
                local raids = ScanRaidChapters()
                RebuildRaidDropdown(raids)
            end)
        else
            RebuildRaidDropdown(AF.RaidChapters)
        end
        return
    end

    if SelWorldMode == "Challenge" then
        WorldStatusLbl.Text = "🏆 Challenge → Items scannen & Raum starten"
        WorldStatusLbl.TextColor3 = D.Gold
        return
    end

    -- Story / Ranger
    for _, wid in ipairs(worldIds) do
        local wd = worldData[wid] or {}
        local hasCaps = (SelWorldMode == "Ranger" and #(wd.ranger or {}) > 0)
                     or (SelWorldMode == "Story"  and #(wd.story  or {}) > 0)
        if not hasCaps then continue end

        local wb = Instance.new("TextButton", worldBtnFrame)
        wb.Size = UDim2.new(1,0,0,30); wb.BackgroundColor3 = D.CardHover
        wb.Text = "🌍  " .. wid
        wb.TextColor3 = D.TextHi; wb.TextSize = 11; wb.Font = Enum.Font.GothamSemibold
        wb.AutoButtonColor = false; wb.BorderSizePixel = 0; Corner(wb,7); Stroke(wb,D.Border,1,0.4)

        local capWid = wid
        wb.MouseButton1Click:Connect(function()
            SelWorldId = capWid
            for _, b in pairs(worldBtnFrame:GetChildren()) do
                if b:IsA("TextButton") then
                    Tw(b,{BackgroundColor3=D.CardHover}); local s=b:FindFirstChildOfClass("UIStroke"); if s then s.Color=D.Border; s.Transparency=0.4 end
                end
            end
            Tw(wb,{BackgroundColor3=D.RowSelect}); Stroke(wb,D.Accent,1.5,0)
            WorldStatusLbl.Text = "🌍 " .. capWid .. " [" .. SelWorldMode .. "] → Kapitel wählen"
            WorldStatusLbl.TextColor3 = D.Yellow
            local chapList = (SelWorldMode == "Ranger") and wd.ranger or wd.story
            RebuildChapBtns(chapList or {})
        end)
    end
end

-- Schwierigkeit (für Story & Raid)
local diffCard2 = Card(worldCard); Pad(diffCard2, 8,8,8,8); VList(diffCard2, 5)
SecLbl(diffCard2, "SCHWIERIGKEIT")
local diffRow2 = Instance.new("Frame", diffCard2)
diffRow2.Size = UDim2.new(1,0,0,26); diffRow2.BackgroundTransparency = 1; HList(diffRow2, 6)
local DC2 = { Normal = D.Green, Hard = D.Orange, Nightmare = D.Red }
local diffBtns2 = {}
local function SetDiffHighlight2(active)
    for diff, btn in pairs(diffBtns2) do
        local isActive = (diff == active)
        local col = DC2[diff] or D.TextMid
        if isActive then
            Tw(btn, { BackgroundColor3 = Color3.fromRGB(
                math.clamp(math.floor(col.R*255*0.28),0,255),
                math.clamp(math.floor(col.G*255*0.28),0,255),
                math.clamp(math.floor(col.B*255*0.28),0,255)) })
            local s = btn:FindFirstChildOfClass("UIStroke"); if s then s.Transparency = 0 end
        else
            Tw(btn, { BackgroundColor3 = D.CardHover })
            local s = btn:FindFirstChildOfClass("UIStroke"); if s then s.Transparency = 0.4 end
        end
    end
end
for _, diff in ipairs({ "Normal", "Hard", "Nightmare" }) do
    local db = Instance.new("TextButton", diffRow2)
    db.Size = UDim2.new(0.32,0,0,24); db.BackgroundColor3 = D.CardHover
    db.Text = diff; db.TextColor3 = DC2[diff]; db.TextSize = 10
    db.Font = Enum.Font.GothamBold; db.AutoButtonColor = false; db.BorderSizePixel = 0
    Corner(db, 7); Stroke(db, DC2[diff], 1, 0.4)
    diffBtns2[diff] = db
    local capDiff = diff
    db.MouseButton1Click:Connect(function()
        SelDiffForRoom = capDiff
        AF.SelDifficulty = capDiff
        SetDiffHighlight2(capDiff)
    end)
end
SetDiffHighlight2("Normal")

-- Modus-Buttons bauen
for _, def in ipairs(WORLD_MODI) do
    local mb = Instance.new("TextButton", modeSelRow)
    mb.Size = UDim2.new(0,32,0,26); mb.BackgroundColor3 = D.CardHover
    mb.Text = def.label; mb.TextColor3 = def.color
    mb.TextSize = 13; mb.Font = Enum.Font.GothamBold
    mb.AutoButtonColor = false; mb.BorderSizePixel = 0; Corner(mb, 7); Stroke(mb, D.Border, 1, 0.5)
    local capId = def.id
    mb.MouseButton1Click:Connect(function()
        SelWorldMode = capId
        HighlightWorldMode(capId)
        -- Sichtbarkeit der Sektionen steuern
        RaidDropCard.Visible    = (capId == "Raid")
        ChallengeCard.Visible   = (capId == "Challenge")
        worldBtnFrame.Visible   = (capId ~= "Raid" and capId ~= "Challenge")
        ChapBtnsFrame.Visible   = (capId ~= "Raid" and capId ~= "Challenge")
        diffCard2.Visible       = (capId == "Story" or capId == "Raid" or capId == "Calamity")
        RebuildWorldBtns()
    end)
    AF.UI.Btn.WorldModeBtns[def.id] = mb
end
HighlightWorldMode("Story")
worldBtnFrame.Visible  = true
ChapBtnsFrame.Visible  = true
RaidDropCard.Visible   = false
ChallengeCard.Visible  = false
diffCard2.Visible      = true

-- Create & Start Room Button
local createStartBtn = NeonBtn(worldCard, "🚀  Create & Start Room", D.Green, 36)
createStartBtn.MouseButton1Click:Connect(function()
    -- Callback an _G.HazeHUB
    if SelWorldMode == "Raid" then
        if not SelRaidEntry then
            WorldStatusLbl.Text = "⚠ Raid-Kapitel wählen!"
            WorldStatusLbl.TextColor3 = D.Red
            return
        end
        WorldStatusLbl.Text = "⚙ Raid: " .. SelRaidEntry.label
        WorldStatusLbl.TextColor3 = D.Yellow
        createStartBtn.Text = "⏳ Gestartet..."
        task.spawn(function()
            _G.HazeHUB.StartRaid(SelRaidEntry)
        end)
    elseif SelWorldMode == "Challenge" then
        createStartBtn.Text = "⏳ Challenge startet..."
        task.spawn(function()
            StartChallengeRoom()
        end)
    else
        if not SelChapId then
            WorldStatusLbl.Text = "⚠ Welt & Kapitel wählen!"
            WorldStatusLbl.TextColor3 = D.Red
            return
        end
        WorldStatusLbl.Text = "⚙ Erstelle: " .. SelChapId
        WorldStatusLbl.TextColor3 = D.Yellow
        createStartBtn.Text = "⏳ Gestartet..."
        local capMode  = SelWorldMode
        local capWorld = SelWorldId
        local capChap  = SelChapId
        local capDiff  = SelDiffForRoom
        task.spawn(function()
            FireStartRoom(capMode, capWorld, capChap, capDiff)
        end)
    end
    task.delay(2.5, function()
        pcall(function()
            createStartBtn.Text = "🚀  Create & Start Room"
            if SelChapId or SelRaidEntry then
                WorldStatusLbl.Text = "✅ Gestartet"
                WorldStatusLbl.TextColor3 = D.Green
            end
        end)
    end)
end)

-- SCHWIERIGKEIT (Autofarm-interne Auswahl)
local diffCard = Card(Container); Pad(diffCard, 8,10,8,10); VList(diffCard, 6)
SecLbl(diffCard, "⚙  SCHWIERIGKEIT (Farm-DB)")
MkLbl(diffCard, "Ranger: immer Nightmare  |  Raids/Calamity: automatisch", 9, D.TextLow).Size = UDim2.new(1,0,0,14)

local diffRow = Instance.new("Frame", diffCard)
diffRow.Size = UDim2.new(1,0,0,28); diffRow.BackgroundTransparency = 1; HList(diffRow, 6)

local DIFF_COLORS = { Normal = D.Green, Hard = D.Orange, Nightmare = D.Red }
local diffBtns = {}
local function SetDiffHighlight(active)
    for diff, btn in pairs(diffBtns) do
        local isActive = (diff == active)
        local col = DIFF_COLORS[diff] or D.TextMid
        if isActive then
            Tw(btn, { BackgroundColor3 = Color3.fromRGB(
                math.clamp(math.floor(col.R*255*0.28),0,255),
                math.clamp(math.floor(col.G*255*0.28),0,255),
                math.clamp(math.floor(col.B*255*0.28),0,255)) })
            local s = btn:FindFirstChildOfClass("UIStroke"); if s then s.Transparency = 0 end
        else
            Tw(btn, { BackgroundColor3 = D.CardHover })
            local s = btn:FindFirstChildOfClass("UIStroke"); if s then s.Transparency = 0.4 end
        end
    end
end
for _, diff in ipairs({ "Normal", "Hard", "Nightmare" }) do
    local col = DIFF_COLORS[diff]
    local db  = Instance.new("TextButton", diffRow)
    db.Size = UDim2.new(0.32,0,0,26); db.BackgroundColor3 = D.CardHover
    db.Text = diff; db.TextColor3 = col; db.TextSize = 10
    db.Font = Enum.Font.GothamBold; db.AutoButtonColor = false; db.BorderSizePixel = 0
    Corner(db, 7); Stroke(db, col, 1, 0.4)
    diffBtns[diff] = db
    local capDiff = diff
    db.MouseButton1Click:Connect(function()
        AF.SelDifficulty = capDiff
        SetDiffHighlight(capDiff)
    end)
end
SetDiffHighlight("Normal")

-- SCAN-PROGRESS
local spCard = Card(Container); Pad(spCard, 8,10,8,10); VList(spCard, 6)
SecLbl(spCard, "🔄  DATENBANK SCAN")

AF.UI.Lbl.ScanProgress = MkLbl(spCard, "Keine DB geladen.", 10, D.TextLow)
AF.UI.Lbl.ScanProgress.Size = UDim2.new(1,0,0,18)

local barBg = Instance.new("Frame", spCard)
barBg.Size = UDim2.new(1,0,0,7); barBg.BackgroundColor3 = D.Input
barBg.BackgroundTransparency = D.GlassPane or 0.18; barBg.BorderSizePixel = 0
barBg.Visible = false; Corner(barBg, 3); AF.UI.Fr.ScanBar = barBg
local barFill = Instance.new("Frame", barBg)
barFill.Size = UDim2.new(0,0,1,0); barFill.BackgroundColor3 = D.Purple
barFill.BorderSizePixel = 0; Corner(barFill, 3); AF.UI.Fr.ScanBarFill = barFill

local forceBtn = Instance.new("TextButton", spCard)
forceBtn.Size = UDim2.new(1,0,0,38); forceBtn.BackgroundColor3 = Color3.fromRGB(68,10,108)
forceBtn.Text = "DATENBANK NEU SCANNEN"; forceBtn.TextColor3 = Color3.new(1,1,1)
forceBtn.TextSize = 12; forceBtn.Font = Enum.Font.GothamBold
forceBtn.AutoButtonColor = false; forceBtn.BorderSizePixel = 0
Corner(forceBtn, 9); Stroke(forceBtn, Color3.fromRGB(180,80,255), 2, 0)
AF.UI.Btn.ForceRescan = forceBtn
forceBtn.MouseEnter:Connect(function() Tw(forceBtn, {BackgroundColor3 = Color3.fromRGB(110,22,170)}) end)
forceBtn.MouseLeave:Connect(function() Tw(forceBtn, {BackgroundColor3 = Color3.fromRGB(68,10,108)}) end)
forceBtn.MouseButton1Click:Connect(function()
    if AF.Scanning then SetStatus("Scan läuft!", D.Yellow); return end
    if not CheckIsLobby() then SetStatus("Nur in Lobby scannen!", D.Orange); return end
    ClearDB()
    forceBtn.Text = "Scannt..."; forceBtn.TextColor3 = D.Yellow
    AF.UI.Fr.ScanBar.Visible = true
    AF.UI.Fr.ScanBarFill.Size = UDim2.new(0,0,1,0)
    AF.UI.Fr.ScanBarFill.BackgroundColor3 = D.Purple
    task.spawn(function()
        ScanAllRewards(function(msg)
            pcall(function() AF.UI.Lbl.ScanProgress.Text = msg end)
        end)
    end)
end)

-- QUEUE-KARTE
local qCard = Card(Container); Pad(qCard, 10,10,10,10); VList(qCard, 8)
SecLbl(qCard, "AUTO-FARM QUEUE")

local qFileInfo = MkLbl(qCard, "Keine Queue.", 10, D.TextLow)
qFileInfo.Size = UDim2.new(1,0,0,14); AF.UI.Lbl.QueueFileInfo = qFileInfo

local qRow = Instance.new("Frame", qCard)
qRow.Size = UDim2.new(1,0,0,30); qRow.BackgroundTransparency = 1; HList(qRow, 5)
local qItemOuter, qItemBox = MkInput(qRow, "Item-Name..."); qItemOuter.Size = UDim2.new(0.50,0,0,30)
local qAmtOuter,  qAmtBox  = MkInput(qRow, "Anzahl");      qAmtOuter.Size  = UDim2.new(0.28,0,0,30)

local qAddBtn = Instance.new("TextButton", qRow)
qAddBtn.Size = UDim2.new(0.19,0,0,30); qAddBtn.BackgroundColor3 = D.Green
qAddBtn.Text = "+ Add"; qAddBtn.TextColor3 = Color3.new(1,1,1)
qAddBtn.TextSize = 11; qAddBtn.Font = Enum.Font.GothamBold
qAddBtn.AutoButtonColor = false; qAddBtn.BorderSizePixel = 0
Corner(qAddBtn, 7); Stroke(qAddBtn, D.Green, 1, 0.2)
qAddBtn.MouseEnter:Connect(function() Tw(qAddBtn, {BackgroundColor3 = Color3.fromRGB(0,160,80)}) end)
qAddBtn.MouseLeave:Connect(function() Tw(qAddBtn, {BackgroundColor3 = D.Green}) end)
qAddBtn.MouseButton1Click:Connect(function()
    local iname = (qItemBox.Text or ""):match("^%s*(.-)%s*$")
    local iamt  = tonumber(qAmtBox.Text)
    if iname == "" or not iamt or iamt <= 0 then return end
    local inQ = false
    for _, q in ipairs(AF.Queue) do if q.item == iname then inQ = true; break end end
    if not inQ then table.insert(AF.Queue, {item=iname, amount=iamt, done=false}); SaveQueueFile() end
    qItemBox.Text = ""; qAmtBox.Text = ""; UpdateQueueUI()
    pcall(function()
        AF.UI.Lbl.QueueFileInfo.Text = "Queue: " .. #AF.Queue .. " Items"
        AF.UI.Lbl.QueueFileInfo.TextColor3 = D.Green
    end)
end)

local ctrlRow = Instance.new("Frame", qCard)
ctrlRow.Size = UDim2.new(1,0,0,32); ctrlRow.BackgroundTransparency = 1; HList(ctrlRow, 8)

local startBtn = Instance.new("TextButton", ctrlRow)
startBtn.Size = UDim2.new(0.48,0,0,32); startBtn.BackgroundColor3 = D.Green
startBtn.Text = "Start Queue"; startBtn.TextColor3 = Color3.new(1,1,1)
startBtn.TextSize = 12; startBtn.Font = Enum.Font.GothamBold
startBtn.AutoButtonColor = false; startBtn.BorderSizePixel = 0
Corner(startBtn, 8); Stroke(startBtn, D.Green, 1, 0.2)

local stopBtn = Instance.new("TextButton", ctrlRow)
stopBtn.Size = UDim2.new(0.48,0,0,32); stopBtn.BackgroundColor3 = D.RedDark
stopBtn.Text = "Stop"; stopBtn.TextColor3 = D.Red
stopBtn.TextSize = 12; stopBtn.Font = Enum.Font.GothamBold
stopBtn.AutoButtonColor = false; stopBtn.BorderSizePixel = 0
Corner(stopBtn, 8); Stroke(stopBtn, D.Red, 1, 0.4)

startBtn.MouseButton1Click:Connect(function()
    if AF.Active then SetStatus("Farm läuft!", D.Yellow); return end
    if #AF.Queue == 0 then SetStatus("Queue leer!", D.Orange); return end
    if CFG then CFG.AutoFarm = true end
    pcall(SaveConfig); pcall(SaveSettings)
    AF.Running = true; _G.AutoFarmRunning = true; SaveState()
    if DBCount() == 0 then
        SetStatus("DB leer – Scan...", D.Yellow)
        startBtn.Text = "Scannt..."; startBtn.TextColor3 = D.Yellow
        task.spawn(function()
            ScanAllRewards(function(msg)
                pcall(function() AF.UI.Lbl.ScanProgress.Text = msg end)
            end)
            pcall(function() startBtn.Text = "Start Queue"; startBtn.TextColor3 = Color3.new(1,1,1) end)
            if AF.Running and not AF.Active and GetNextItem() then task.spawn(FarmLoop) end
        end)
    else
        task.spawn(FarmLoop)
    end
end)

stopBtn.MouseButton1Click:Connect(function()
    StopFarm(); startBtn.Text = "Start Queue"; startBtn.TextColor3 = Color3.new(1,1,1)
end)

local clearBtn = NeonBtn(qCard, "Queue leeren", D.Red, 28)
clearBtn.MouseButton1Click:Connect(function()
    AF.Queue = {}; SaveQueueFile(); UpdateQueueUI()
    pcall(function()
        AF.UI.Lbl.QueueFileInfo.Text = "Queue geleert."
        AF.UI.Lbl.QueueFileInfo.TextColor3 = D.TextLow
    end)
end)

AF.UI.Fr.List = Instance.new("ScrollingFrame", qCard)
AF.UI.Fr.List.Size = UDim2.new(1,0,0,190)
AF.UI.Fr.List.CanvasSize = UDim2.new(0,0,0,0)
AF.UI.Fr.List.AutomaticCanvasSize = Enum.AutomaticSize.Y
AF.UI.Fr.List.ScrollBarThickness = 4
AF.UI.Fr.List.ScrollBarImageColor3 = D.CyanDim
AF.UI.Fr.List.BackgroundTransparency = 1
AF.UI.Fr.List.BorderSizePixel = 0
VList(AF.UI.Fr.List, 4)
AF.UI.Lbl.QueueEmpty = MkLbl(AF.UI.Fr.List, "Queue leer.", 11, D.TextLow)
AF.UI.Lbl.QueueEmpty.Size = UDim2.new(1,0,0,24)

-- ============================================================
--  TriggerResetRescan (für Hauptskript-Callback)
-- ============================================================
HS.TriggerResetRescan = function(onProgress)
    if AF.Scanning then
        pcall(function() if onProgress then onProgress("⚠ Scan läuft bereits!") end end)
        return
    end
    ClearDB()
    pcall(function()
        AF.UI.Fr.ScanBar.Visible = true
        AF.UI.Fr.ScanBarFill.Size = UDim2.new(0,0,1,0)
        AF.UI.Fr.ScanBarFill.BackgroundColor3 = D.Purple
        AF.UI.Lbl.ScanProgress.Text = "Reset & Rescan startet..."
        AF.UI.Lbl.ScanProgress.TextColor3 = D.Yellow
        if AF.UI.Btn.ForceRescan then
            AF.UI.Btn.ForceRescan.Text = "Scannt..."
            AF.UI.Btn.ForceRescan.TextColor3 = D.Yellow
        end
    end)
    task.spawn(function()
        local function combined(msg)
            pcall(function() AF.UI.Lbl.ScanProgress.Text = msg end)
            if onProgress then pcall(function() onProgress(msg) end) end
        end
        local ok = ScanAllRewards(combined)
        pcall(function()
            if AF.UI.Btn.ForceRescan then
                AF.UI.Btn.ForceRescan.Text = "DATENBANK NEU SCANNEN"
                AF.UI.Btn.ForceRescan.TextColor3 = Color3.new(1,1,1)
            end
        end)
        local finalMsg = ok
            and string.format("✅ Reset & Rescan fertig! %d Einträge.", DBCount())
            or  "⚠ Scan abgeschlossen (einige Chapters fehlgeschlagen)."
        pcall(function() onProgress(finalMsg) end)
        if ok then NotifyDBReady(DBCount(), finalMsg) end
        print("[HazeHub] TriggerResetRescan: " .. finalMsg)
    end)
end

-- _G.HazeHUB Aliase für Hauptskript-Callbacks
_G.HazeHUB.TriggerRescan    = HS.TriggerResetRescan
_G.HazeHUB.ScanAllRewards   = function(cb) return ScanAllRewards(cb or function() end) end
_G.HazeHUB.FireStartRoom    = FireStartRoom

-- ============================================================
--  STARTUP
-- ============================================================
if isfile and isfile(DB_FILE) then
    if LoadDB() then
        local c = DBCount()
        AF.UI.Lbl.ScanProgress.Text = string.format("✅ DB: %d Einträge", c)
        AF.UI.Lbl.ScanProgress.TextColor3 = D.Green
        _G.HazeHUB_Database = AF.RewardDatabase
        task.delay(0.5, function()
            NotifyDBReady(c, string.format("Datenbank geladen! (%d Einträge)", c))
        end)
    else
        AF.UI.Lbl.ScanProgress.Text = "Keine gültige DB."
        AF.UI.Lbl.ScanProgress.TextColor3 = D.Orange
    end
else
    AF.UI.Lbl.ScanProgress.Text = "Keine DB."
    AF.UI.Lbl.ScanProgress.TextColor3 = D.TextLow
end

-- Raid-Kapitel beim Start scannen (im Hintergrund)
task.spawn(function()
    task.wait(3)
    local raids = ScanRaidChapters()
    if #raids > 0 then
        RebuildRaidDropdown(raids)
        print(string.format("[HazeHub] Startup: %d Raid-Kapitel gescannt.", #raids))
    end
end)

-- Challenge-Items beim Start scannen (im Hintergrund)
task.spawn(function()
    task.wait(4)
    local items = ScanChallengeItems()
    if #items > 0 then
        RebuildChallengeItemsUI(items)
        print(string.format("[HazeHub] Startup: %d Challenge-Items gescannt.", #items))
    end
end)

task.spawn(TryAutoResume)

HS.SetModuleLoaded(VERSION)
pcall(function()
    for _, gui in ipairs(Container:GetDescendants()) do
        if gui:IsA("GuiObject") then gui.ZIndex = 1 end
    end
end)

print(string.format("[HazeHub] autofarm.lua v%s geladen | Spieler: %s | DB: %d Einträge",
    VERSION, LP.Name, DBCount()))
