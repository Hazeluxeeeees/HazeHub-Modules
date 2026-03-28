-- ╔══════════════════════════════════════════════════════════╗
--  HazeHUB – autofarm.lua  v3.0.0
--
--  v3.0.0 – Komplette Neuentwicklung der Scan-Logik:
--    ★ Source of Truth: Player_Data[LP.Name].ChapterLevels
--    ★ Kategorisierung per Name: Raid / Calamity / Ranger / Story
--    ★ Persistenz: HazeHUB_WorldCache.json (Laden vor UI-Build)
--    ★ Globale Daten in _G.HazeHUB.WorldData (Nil-Error Fix)
--    ★ Dynamischer Dropdown-Sync nach Modus-Wechsel
--    ★ Challenge-Scan: RS.Gameplay.Game.Challenge.Items
--    ★ Smart-Farm: DropRate × DropAmount Score
--    ★ Queue-Wechsel ohne Lobby-Teleport
--    ★ Raid Farm: Esper & JJK mit Live-Drop-Scan
-- ╚══════════════════════════════════════════════════════════╝

local VERSION  = "3.0.0"
local LOBBY_ID = 111446873000464

-- ============================================================
--  WARTEN BIS SHARED BEREIT (max 10s)
-- ============================================================
local waited = 0
while not (_G.HazeShared and _G.HazeShared.Container and _G.HazeShared.SetModuleLoaded) do
    task.wait(0.3); waited = waited + 0.3
    if waited >= 10 then warn("[HazeHub/AF] _G.HazeShared nicht bereit."); return end
end

-- ============================================================
--  SHARED ALIASE
-- ============================================================
local HS           = _G.HazeShared
local CFG          = HS.Config
local ST           = HS.State
local D            = HS.D
local TF           = HS.TF;  local TM = HS.TM;  local Tw = HS.Tw
local Svc          = HS.Svc
local Card         = HS.Card;    local NeonBtn  = HS.NeonBtn
local MkLbl        = HS.MkLbl;  local SecLbl   = HS.SecLbl
local MkInput      = HS.MkInput; local VList    = HS.VList
local HList        = HS.HList;   local Pad      = HS.Pad
local Corner       = HS.Corner;  local Stroke   = HS.Stroke
local PR           = HS.PR
local SaveConfig   = HS.SaveConfig
local SaveSettings = HS.SaveSettings
local SendWebhook  = HS.SendWebhook
local Container    = HS.Container

-- ============================================================
--  SERVICES & LOCALS
-- ============================================================
local VirtualUser     = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local LP              = game.Players.LocalPlayer
local RS              = game:GetService("ReplicatedStorage")
local WS              = game:GetService("Workspace")

-- ============================================================
--  ★ _G.HazeHUB – Globale Daten-Tabelle (Fix für Nil-Errors)
--  Alle Module greifen hierüber zu → kein Absturz bei nil
-- ============================================================
if not _G.HazeHUB then _G.HazeHUB = {} end
_G.HazeHUB.WorldData = _G.HazeHUB.WorldData or {
    Story     = {},   -- { name = "JJK_Chapter1", worldId = "JJK" }
    Ranger    = {},
    Calamity  = {},
    Raid      = {},   -- { name = "JJK_Raid_Chapter1", raidType = "JJKRaid" }
}
_G.HazeHUB.GetWorldData  = function() return _G.HazeHUB.WorldData end
_G.HazeHUB.IsDataLoaded  = function()
    local wd = _G.HazeHUB.WorldData
    return (#wd.Story > 0 or #wd.Ranger > 0 or #wd.Calamity > 0 or #wd.Raid > 0)
end

-- ============================================================
--  DATEIPFADE
-- ============================================================
local FOLDER          = "HazeHUB"
local WORLD_CACHE     = FOLDER .. "/HazeHUB_WorldCache.json"
local DB_FILE         = FOLDER .. "/" .. LP.Name .. "_RewardDB.json"
local QUEUE_FILE      = FOLDER .. "/" .. LP.Name .. "_Queue.json"
local STATE_FILE      = FOLDER .. "/" .. LP.Name .. "_State.json"
local SETTINGS_FILE   = FOLDER .. "/" .. LP.Name .. "_settings.json"

if makefolder then pcall(function() makefolder(FOLDER) end) end

-- ============================================================
--  HAUPT-STATE
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
    if PlayRoomEvent then print("[HazeHub] Remote OK: " .. PlayRoomEvent:GetFullName())
    else warn("[HazeHub] PlayRoomEvent nicht gefunden!") end
end)

local function Fire(action, data)
    if PlayRoomEvent then
        pcall(function()
            if data then PlayRoomEvent:FireServer(action, data)
            else         PlayRoomEvent:FireServer(action) end
        end)
    elseif PR then PR(action, data) end
end

-- ============================================================
--  INVENTAR
-- ============================================================
local function GetLiveInvAmt(itemName)
    local n = 0
    pcall(function()
        local f = RS:WaitForChild("Player_Data",3)
                     :WaitForChild(LP.Name,3)
                     :WaitForChild("Items",3)
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
        if SaveConfig   then pcall(SaveConfig)   end
        if SaveSettings then pcall(SaveSettings) end
    end
    print("[HazeHub] Teleportiere zur Lobby: " .. LOBBY_ID)
    pcall(function() TeleportService:Teleport(LOBBY_ID) end)
end

-- ============================================================
--  PERSISTENZ (Queue / State / Settings)
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
    return (ok and type(data) == "table") and data or nil
end

local function LoadSettingsFile()
    if not (isfile and isfile(SETTINGS_FILE)) then return nil end
    local raw; pcall(function() raw = readfile(SETTINGS_FILE) end)
    if not raw or #raw < 3 then return nil end
    local ok, data = pcall(function() return Svc.Http:JSONDecode(raw) end)
    return (ok and type(data) == "table") and data or nil
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
    print("[HazeHub] Queue: " .. #AF.Queue .. " Items")
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
        if not q.done and GetLiveInvAmt(q.item) >= q.amount then
            table.remove(AF.Queue, i); changed = true
        end
    end
    if changed then SaveQueueFile() end
    return changed
end

-- ============================================================
--  ★ WELTDATEN-SCAN  (Source of Truth: ChapterLevels)
--
--  Liest Player_Data[LP.Name].ChapterLevels und kategorisiert
--  anhand des Namens:
--    - "Raid"      → Raid
--    - "Calamity"  → Calamity
--    - "Ranger"    → Ranger
--    - "Chapter"   → Story (nur wenn kein Raid/Calamity/Ranger)
-- ============================================================
local function ExtractWorldIdFromChapter(chapName)
    -- "JJK_Chapter1" → "JJK"
    -- "OnePiece_Chapter3" → "OnePiece"
    -- "JJK_Raid_Chapter1" → "JJKRaid"
    -- "Esper_Raid_Chapter1" → "EsperRaid"
    local lower = chapName:lower()
    if lower:find("raid") then
        local prefix = chapName:match("^(.-)_Raid") or chapName:match("^(.-)_raid")
        if prefix then return prefix .. "Raid" end
        return "UnknownRaid"
    end
    local prefix = chapName:match("^(.-)_")
    return prefix or chapName
end

local function ScanChapterLevels()
    local result = {
        Story    = {},
        Ranger   = {},
        Calamity = {},
        Raid     = {},
    }

    local ok, chapFolder = pcall(function()
        return RS:WaitForChild("Player_Data", 10)
                  :WaitForChild(LP.Name,       10)
                  :WaitForChild("ChapterLevels", 5)
    end)

    if not ok or not chapFolder then
        warn("[HazeHub] ChapterLevels nicht gefunden!")
        return result, false
    end

    for _, child in ipairs(chapFolder:GetChildren()) do
        local name  = child.Name
        local lower = name:lower()

        -- Numerische Sortierung: extrahiere Zahl am Ende
        local sortNum = tonumber(name:match("(%d+)$")) or 0

        if lower:find("raid") then
            -- z.B. JJK_Raid_Chapter1, Esper_Raid_Chapter1
            local raidType = ExtractWorldIdFromChapter(name)
            table.insert(result.Raid, {
                name     = name,
                raidType = raidType,
                sortNum  = sortNum,
            })
        elseif lower:find("calamity") then
            -- z.B. Calamity_Chapter1
            table.insert(result.Calamity, {
                name    = name,
                worldId = "Calamity",
                sortNum = sortNum,
            })
        elseif lower:find("ranger") or lower:find("rangerstage") then
            -- z.B. JJK_RangerStage1
            local worldId = ExtractWorldIdFromChapter(name)
            table.insert(result.Ranger, {
                name    = name,
                worldId = worldId,
                sortNum = sortNum,
            })
        elseif lower:find("chapter") then
            -- z.B. JJK_Chapter1, OnePiece_Chapter3
            local worldId = ExtractWorldIdFromChapter(name)
            table.insert(result.Story, {
                name    = name,
                worldId = worldId,
                sortNum = sortNum,
            })
        end
    end

    -- Numerisch sortieren
    local function byNum(a, b) return a.sortNum < b.sortNum end
    table.sort(result.Story,    byNum)
    table.sort(result.Ranger,   byNum)
    table.sort(result.Calamity, byNum)
    table.sort(result.Raid,     byNum)

    local total = #result.Story + #result.Ranger + #result.Calamity + #result.Raid
    print(string.format("[HazeHub] ChapterLevels gescannt: Story=%d Ranger=%d Calamity=%d Raid=%d",
        #result.Story, #result.Ranger, #result.Calamity, #result.Raid))
    return result, total > 0
end

-- ============================================================
--  ★ WELTDATEN SPEICHERN / LADEN (HazeHUB_WorldCache.json)
-- ============================================================
local function SaveWorldCache(data)
    if not writefile then return end
    local ok = pcall(function()
        writefile(WORLD_CACHE, Svc.Http:JSONEncode({
            data      = data,
            version   = VERSION,
            player    = LP.Name,
            timestamp = os.time(),
        }))
    end)
    if ok then print("[HazeHub] WorldCache gespeichert.") end
end

local function LoadWorldCache()
    if not (isfile and isfile(WORLD_CACHE)) then return nil end
    local raw; pcall(function() raw = readfile(WORLD_CACHE) end)
    if not raw or #raw < 10 then return nil end
    local ok, parsed = pcall(function() return Svc.Http:JSONDecode(raw) end)
    if not ok or type(parsed) ~= "table" or type(parsed.data) ~= "table" then return nil end

    local d = parsed.data
    -- Validierung: muss mindestens eine Kategorie haben
    local hasData = false
    for _, cat in ipairs({ "Story","Ranger","Calamity","Raid" }) do
        if type(d[cat]) == "table" and #d[cat] > 0 then hasData = true; break end
    end
    if not hasData then return nil end

    print(string.format("[HazeHub] WorldCache geladen (Story=%d Ranger=%d Calamity=%d Raid=%d)",
        #(d.Story    or {}),
        #(d.Ranger   or {}),
        #(d.Calamity or {}),
        #(d.Raid     or {})))
    return d
end

local function DeleteWorldCache()
    if isfile and isfile(WORLD_CACHE) then
        pcall(function() delfile(WORLD_CACHE) end)
        print("[HazeHub] WorldCache gelöscht.")
    end
end

-- Anwenden auf globale Tabelle
local function ApplyWorldData(data)
    if not data then return false end
    _G.HazeHUB.WorldData = {
        Story    = data.Story    or {},
        Ranger   = data.Ranger   or {},
        Calamity = data.Calamity or {},
        Raid     = data.Raid     or {},
    }
    -- Kompatibilität mit altem Shared-System
    if ST then
        ST.ScanDone = true
        -- Baue WorldData/WorldIds für Abwärtskompatibilität auf
        local wd, ids = {}, {}
        local worldSet = {}
        for _, e in ipairs(_G.HazeHUB.WorldData.Story) do
            if not wd[e.worldId] then wd[e.worldId]={story={},ranger={}}; table.insert(ids, e.worldId) end
            table.insert(wd[e.worldId].story, e.name)
            worldSet[e.worldId] = true
        end
        for _, e in ipairs(_G.HazeHUB.WorldData.Ranger) do
            if not wd[e.worldId] then wd[e.worldId]={story={},ranger={}}; table.insert(ids, e.worldId) end
            table.insert(wd[e.worldId].ranger, e.name)
        end
        if #(_G.HazeHUB.WorldData.Calamity) > 0 then
            wd["Calamity"] = { story={}, ranger={} }
            for _, e in ipairs(_G.HazeHUB.WorldData.Calamity) do
                table.insert(wd["Calamity"].story, e.name)
            end
            table.insert(ids, "Calamity")
        end
        ST.WorldData = wd
        ST.WorldIds  = ids
    end
    return true
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

-- ============================================================
--  REWARD-DATENBANK (Deep-Scan via PlayRoom GUI)
-- ============================================================
local function DBCount()
    local c = 0; for _ in pairs(AF.RewardDatabase) do c = c + 1 end; return c
end

local function SaveDB()
    if not writefile then return end
    pcall(function() writefile(DB_FILE, Svc.Http:JSONEncode(AF.RewardDatabase)) end)
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
    print("[HazeHub] RewardDB geladen: " .. c .. " Chapters")
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

local function ScanRewardsSafe()
    local rewards = {}
    local ok, list = pcall(function()
        return LP.PlayerGui.PlayRoom.Main.GameStage.Main.Base.Rewards.ItemsList
    end)
    if not ok or not list then return rewards, false end
    pcall(function()
        for _, item in pairs(list:GetChildren()) do
            if item:IsA("UIGridLayout") or item:IsA("UIListLayout")
            or item:IsA("UIPadding")    or item:IsA("UICorner") then continue end
            local iname, rate, amt = item.Name, 0, 1
            pcall(function()
                local inf = item:FindFirstChild("Info") or item
                local nv  = inf:FindFirstChild("ItemNames")
                local rv  = inf:FindFirstChild("DropRate")
                local av  = inf:FindFirstChild("DropAmount")
                if nv and tostring(nv.Value) ~= "" then iname = tostring(nv.Value) end
                if rv then rate = tonumber(rv.Value) or 0 end
                if av then amt  = tonumber(av.Value) or 1 end
            end)
            if iname ~= "" and not iname:match("^UI") and not iname:match("^Frame$") then
                rewards[iname] = { dropRate = rate, dropAmount = amt }
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
            for _, ch in pairs(list:GetChildren()) do
                if ch:IsA("Frame") or ch:IsA("ImageLabel") or ch:IsA("TextButton") then n = n + 1 end
            end
            if n > 0 then return true end
        end
        task.wait(0.3)
    end
    return false
end

-- ★ Deep-Scan nutzt jetzt _G.HazeHUB.WorldData als Quelle
local function ScanAllRewards(onProgress)
    if AF.Scanning then return false end
    if not _G.HazeHUB.IsDataLoaded() then
        pcall(function() onProgress("⚠ Weltdaten fehlen – erst 'Welten scannen' drücken!") end)
        return false
    end
    AF.Scanning = true; AF.RewardDatabase = {}
    local wd    = _G.HazeHUB.WorldData
    local tasks = {}

    -- Story-Tasks
    for _, e in ipairs(wd.Story) do
        table.insert(tasks, { chapId=e.name, worldId=e.worldId, mode="Story" })
    end
    -- Ranger-Tasks
    for _, e in ipairs(wd.Ranger) do
        table.insert(tasks, { chapId=e.name, worldId=e.worldId, mode="Ranger" })
    end
    -- Calamity-Tasks
    for _, e in ipairs(wd.Calamity) do
        table.insert(tasks, { chapId=e.name, worldId="Calamity", mode="Calamity" })
    end

    local total   = #tasks
    local scanned = 0; local failed = 0; local retried = 0
    if total == 0 then
        AF.Scanning = false
        pcall(function() onProgress("Keine Chapters in DB – Welten neu scannen!") end)
        return false
    end

    print(string.format("[HazeHub] DEEP-SCAN START: %d Chapters", total))
    Fire("Create"); task.wait(1.5)

    for _, t in ipairs(tasks) do
        if not AF.Scanning then break end
        scanned = scanned + 1
        pcall(function()
            onProgress(string.format("Scanne %d/%d: [%s] %s", scanned, total, t.mode, t.chapId))
        end)

        if t.mode == "Story" then
            Fire("Create");                                              task.wait(0.5)
            Fire("Change-World",   { World   = t.worldId });            task.wait(0.5)
            Fire("Change-Chapter", { Chapter = t.chapId });             task.wait(2.0)
        elseif t.mode == "Ranger" then
            Fire("Create");                                              task.wait(0.5)
            Fire("Change-Mode", { KeepWorld=t.worldId, Mode="Ranger Stage" }); task.wait(1.0)
            Fire("Change-World",   { World   = t.worldId });            task.wait(0.5)
            Fire("Change-Chapter", { Chapter = t.chapId });             task.wait(2.0)
        elseif t.mode == "Calamity" then
            Fire("Create");                                              task.wait(0.5)
            Fire("Change-Mode",    { Mode    = "Calamity" });           task.wait(0.5)
            Fire("Change-Chapter", { Chapter = t.chapId });             task.wait(2.0)
        end

        local filled = WaitForItemsListFilled(3)
        if not filled then
            task.wait(2.0); filled = WaitForItemsListFilled(2)
            if filled then retried = retried + 1 end
        end

        if filled then
            local items, hasItems = ScanRewardsSafe()
            if hasItems then
                AF.RewardDatabase[t.chapId] = { world=t.worldId, mode=t.mode, chapId=t.chapId, items=items }
            else
                failed = failed + 1
            end
        else
            failed = failed + 1
        end
        pcall(function() Fire("Submit"); task.wait(0.4); Fire("Create"); task.wait(0.6) end)
    end

    if DBCount() > 0 then
        SaveDB()
        _G.HazeShared._AutoFarm_RewardDB = AF.RewardDatabase
    end
    AF.Scanning = false
    local c  = DBCount(); local ok = c > 0
    local msg = string.format("%s: %d/%d Chapters (%d Fehler)", ok and "✅ Scan OK" or "⚠ Scan", c, total, failed)
    print("[HazeHub] " .. msg)
    pcall(function() onProgress(msg) end)
    pcall(function()
        local col = ok and D.Green or D.Orange
        AF.UI.Lbl.DBStatus.Text       = msg
        AF.UI.Lbl.DBStatus.TextColor3 = col
        if AF.UI.Btn.ForceRescan then
            AF.UI.Btn.ForceRescan.Text       = "DATENBANK NEU SCANNEN"
            AF.UI.Btn.ForceRescan.TextColor3 = Color3.new(1,1,1)
        end
        if AF.UI.Btn.UpdateDB then
            AF.UI.Btn.UpdateDB.Text       = "Update Database"
            AF.UI.Btn.UpdateDB.TextColor3 = D.Accent or D.Cyan
        end
    end)
    if ok then NotifyDBReady(c, msg) end
    return ok
end

-- ============================================================
--  BESTES CHAPTER (aus RewardDatabase)
-- ============================================================
local function FindBestChapter(itemName)
    local bestChapId, bestWorldId, bestMode, bestRate = nil, nil, nil, -1
    for chapId, data in pairs(AF.RewardDatabase) do
        if data.items and data.items[itemName] then
            local r = data.items[itemName].dropRate or 0
            if r > bestRate then
                bestRate    = r
                bestChapId  = data.chapId or chapId
                bestWorldId = data.world
                bestMode    = data.mode
            end
        end
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
        for _, q in ipairs(AF.Queue) do if not q.done then return q end end
    end

    for i, q in ipairs(AF.Queue) do
        if q.done then continue end
        local inv    = GetLiveInvAmt(q.item)
        local pct    = math.min(1, inv / math.max(1, q.amount))
        local isNext = (NextItem() == q)
        local row    = Instance.new("Frame", AF.UI.Fr.List)
        row.Size = UDim2.new(1,0,0,44); row.BorderSizePixel=0; Corner(row,8)
        if isNext then row.BackgroundColor3=D.RowSelect or D.TabActive; Stroke(row,D.Accent or D.Cyan,1.5,0)
        else            row.BackgroundColor3=D.Card;                    Stroke(row,D.Border,1,0.4) end
        local barC = isNext and (D.Accent or D.Cyan) or D.Purple
        local bar  = Instance.new("Frame",row); bar.Size=UDim2.new(0,3,0.65,0); bar.Position=UDim2.new(0,0,0.175,0); bar.BackgroundColor3=barC; bar.BorderSizePixel=0; Corner(bar,2)
        local pgBg = Instance.new("Frame",row); pgBg.Size=UDim2.new(1,-52,0,3); pgBg.Position=UDim2.new(0,8,1,-6); pgBg.BackgroundColor3=D.Input; pgBg.BackgroundTransparency=0.18; pgBg.BorderSizePixel=0; Corner(pgBg,2)
        local pgF  = Instance.new("Frame",pgBg); pgF.Size=UDim2.new(pct,0,1,0); pgF.BackgroundColor3=barC; pgF.BorderSizePixel=0; Corner(pgF,2)
        local nL   = Instance.new("TextLabel",row); nL.Position=UDim2.new(0,12,0,5); nL.Size=UDim2.new(1,-52,0.5,-3); nL.BackgroundTransparency=1; nL.Text=(isNext and "▶ " or "")..q.item; nL.TextColor3=isNext and (D.Accent or D.Cyan) or D.TextHi; nL.TextSize=11; nL.Font=Enum.Font.GothamBold; nL.TextXAlignment=Enum.TextXAlignment.Left; nL.TextTruncate=Enum.TextTruncate.AtEnd
        local pL   = Instance.new("TextLabel",row); pL.Position=UDim2.new(0,12,0.5,1); pL.Size=UDim2.new(1,-52,0.5,-5); pL.BackgroundTransparency=1; pL.Text=string.format("%d / %d  (%.0f%%)",inv,q.amount,pct*100); pL.TextColor3=D.TextMid; pL.TextSize=10; pL.Font=Enum.Font.GothamSemibold; pL.TextXAlignment=Enum.TextXAlignment.Left
        local ci   = i
        local xBtn = Instance.new("TextButton",row); xBtn.Size=UDim2.new(0,34,0,34); xBtn.Position=UDim2.new(1,-38,0.5,-17); xBtn.BackgroundColor3=Color3.fromRGB(50,12,12); xBtn.Text="✕"; xBtn.TextColor3=D.Red; xBtn.TextSize=13; xBtn.Font=Enum.Font.GothamBold; xBtn.AutoButtonColor=false; xBtn.BorderSizePixel=0; Corner(xBtn,7); Stroke(xBtn,D.Red,1,0.4)
        xBtn.MouseEnter:Connect(function() Tw(xBtn,{BackgroundColor3=D.RedDark}) end)
        xBtn.MouseLeave:Connect(function() Tw(xBtn,{BackgroundColor3=Color3.fromRGB(50,12,12)}) end)
        xBtn.MouseButton1Click:Connect(function()
            if AF.Queue[ci] then table.remove(AF.Queue,ci); SaveQueueFile() end
            UpdateQueueUI()
        end)
    end
end

-- ============================================================
--  ★ RUNDEN-MONITOR  (direkter Queue-Wechsel ohne Teleport)
-- ============================================================
local function GetNextItem()
    for _, q in ipairs(AF.Queue) do if not q.done then return q end end
end

local function RoundMonitorLoop(q)
    SetStatus(string.format("RUNDE: Warte auf '%s'", q.item), D.TextMid)
    local deadline = os.time() + 600
    while AF.Running and os.time() < deadline do
        if CheckIsLobby() then break end
        task.wait(4)
        local cur = GetLiveInvAmt(q.item)
        SetStatus(string.format("RUNDE: '%s'  %d/%d  (%.0f%%)",
            q.item, cur, q.amount, math.min(100, cur/math.max(1,q.amount)*100)), D.Cyan)
        pcall(UpdateQueueUI)
        pcall(function() if HS.UpdateGoalsUI then HS.UpdateGoalsUI() end end)

        if cur >= q.amount then
            task.spawn(function() pcall(function() if SendWebhook then SendWebhook({},q.item,cur) end end) end)
            RemoveFromQueue(q.item); pcall(UpdateQueueUI)
            SetStatus(string.format("✅ '%s' erreicht!", q.item), D.GreenBright)
            SaveState()

            -- ★ Direkter Queue-Wechsel: warte auf Rundenende, dann Lobby übernimmt
            local nextQ = GetNextItem()
            if nextQ and AF.Running then
                SetStatus(string.format("⏳ Rundenende... → nächstes: '%s'", nextQ.item), D.Yellow)
                local waitEnd = os.time() + 600
                while AF.Running and not CheckIsLobby() and os.time() < waitEnd do
                    task.wait(3)
                    local nc = GetLiveInvAmt(nextQ.item)
                    SetStatus(string.format("⏳ Runde endet... | '%s': %d/%d", nextQ.item, nc, nextQ.amount), D.Yellow)
                end
                if CheckIsLobby() and AF.Running then task.wait(2); return true end
                -- Timeout-Fallback
                DoTeleportToLobby(true)
                local w = 0
                while AF.Running and not CheckIsLobby() and w < 15 do task.wait(1); w=w+1 end
                return true
            else
                SetStatus("Queue leer – Teleportiere zur Lobby.", D.Orange)
                DoTeleportToLobby(false)
                local w = 0
                while AF.Running and not CheckIsLobby() and w < 15 do task.wait(1); w=w+1 end
                return true
            end
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
    SyncInventoryWithQueue(); pcall(UpdateQueueUI)
    local q = GetNextItem()
    if not q then
        SetStatus("Queue leer – Farm beendet.", D.Green)
        AF.Active=false; AF.Running=false; _G.AutoFarmRunning=false; SaveState()
        if CFG then CFG.AutoFarm=false end
        if SaveConfig   then pcall(SaveConfig)   end
        if SaveSettings then pcall(SaveSettings) end
        return false
    end
    local useChapId, worldId, mode = FindBestChapter(q.item)
    -- Fallback: erste Story-Chapter aus WorldData
    if not useChapId then
        local wd = _G.HazeHUB.WorldData
        if wd.Story and #wd.Story > 0 then
            useChapId = wd.Story[1].name
            worldId   = wd.Story[1].worldId
            mode      = "Story"
        end
    end
    if not useChapId then
        SetStatus("Kein Chapter gefunden für '" .. q.item .. "'", D.Orange)
        RemoveFromQueue(q.item); pcall(UpdateQueueUI); return true
    end
    SetStatus(string.format("LOBBY: [%s] '%s' → %s", mode or "?", q.item, useChapId), D.Cyan)
    task.spawn(function() pcall(function()
        if mode == "Story" then
            Fire("Create"); task.wait(0.35)
            Fire("Change-World",   { World   = worldId });   task.wait(0.35)
            Fire("Change-Chapter", { Chapter = useChapId }); task.wait(0.35)
            Fire("Submit"); task.wait(0.5); Fire("Start")
        elseif mode == "Ranger" then
            Fire("Create"); task.wait(0.35)
            Fire("Change-Mode",    { KeepWorld=worldId, Mode="Ranger Stage" }); task.wait(0.5)
            Fire("Change-World",   { World   = worldId });   task.wait(0.35)
            Fire("Change-Chapter", { Chapter = useChapId }); task.wait(0.35)
            Fire("Submit"); task.wait(0.5); Fire("Start")
        elseif mode == "Calamity" then
            Fire("Create"); task.wait(0.35)
            Fire("Change-Mode",    { Mode    = "Calamity" }); task.wait(0.35)
            Fire("Change-Chapter", { Chapter = useChapId }); task.wait(0.35)
            Fire("Submit"); task.wait(0.5); Fire("Start")
        end
    end) end)
    local ws = os.clock()
    while AF.Running and CheckIsLobby() and os.clock()-ws < 30 do task.wait(1) end
    task.wait(1); return true
end

-- ============================================================
--  FARM LOOP
-- ============================================================
local function AddOrUpdateQueueItem(itemName, amount)
    local iname = tostring(itemName or ""):match("^%s*(.-)%s*$")
    local iamt  = math.floor(tonumber(amount) or 0)
    if iname == "" or iamt <= 0 then return false end
    for _, q in ipairs(AF.Queue) do
        if q.item == iname then
            q.amount = math.max(1, q.amount + iamt); q.done = false
            SaveQueueFile(); pcall(UpdateQueueUI)
            pcall(function() if HS.UpdateGoalsUI then HS.UpdateGoalsUI() end end)
            return true
        end
    end
    table.insert(AF.Queue, { item = iname, amount = iamt, done = false })
    SaveQueueFile(); pcall(UpdateQueueUI)
    pcall(function() if HS.UpdateGoalsUI then HS.UpdateGoalsUI() end end)
    return true
end

local function FarmLoop()
    AF.Active=true; AF.Running=true; _G.AutoFarmRunning=true; SaveState()
    print("[HazeHub] ===== FARM LOOP START =====")
    local firstLobby = true
    while AF.Running do
        if not CheckIsLobby() then
            firstLobby = true
            local q = GetNextItem()
            if not q then
                SetStatus("Queue leer – Teleportiere.", D.Orange)
                task.wait(3); DoTeleportToLobby(false); task.wait(10); break
            end
            RoundMonitorLoop(q); task.wait(2)
        else
            local delay = firstLobby and 5 or 2; firstLobby = false
            local cont = LobbyActionLoop(delay)
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
    if SaveConfig   then pcall(SaveConfig)   end
    if SaveSettings then pcall(SaveSettings) end
    SaveState(); SetStatus("Gestoppt.", D.TextMid)
end
HS.StopFarm = StopFarm

HS.StartFarmFromMain = function()
    if AF.Active then SetStatus("Farm läuft!", D.Yellow); return end
    if #AF.Queue == 0 then SetStatus("Queue leer!", D.Orange); return end
    if CFG then CFG.AutoFarm=true end
    if SaveConfig   then pcall(SaveConfig)   end
    if SaveSettings then pcall(SaveSettings) end
    if DBCount() == 0 then
        SetStatus("DB leer – Scan...", D.Yellow)
        AF.Running=true; _G.AutoFarmRunning=true; SaveState()
        task.spawn(function()
            local ok = ScanAllRewards(function(msg)
                pcall(function() AF.UI.Lbl.DBStatus.Text=msg; AF.UI.Lbl.DBStatus.TextColor3=D.Yellow end)
            end)
            if ok and AF.Running and not AF.Active and GetNextItem() then task.spawn(FarmLoop) end
        end)
    else task.spawn(FarmLoop) end
end
HS.AddAutoFarmQueueItem = AddOrUpdateQueueItem
_G.AddAutoFarmQueueItem = AddOrUpdateQueueItem
HS.AddToQueue           = AddOrUpdateQueueItem
_G.AddToQueue           = AddOrUpdateQueueItem

-- ============================================================
--  SCAN-TASK HELPER (Deep-Scan der Rewards)
-- ============================================================
local function RunRewardScanTask(forceDelete, thenStartFarm)
    if AF.Scanning then SetStatus("Scan läuft!", D.Yellow); return end
    task.spawn(function()
        if forceDelete then ClearDB() end
        pcall(function()
            AF.UI.Fr.ScanBar.Visible             = true
            AF.UI.Fr.ScanBarFill.Size             = UDim2.new(0,0,1,0)
            AF.UI.Fr.ScanBarFill.BackgroundColor3 = D.Purple
            AF.UI.Lbl.ScanProgress.Text           = "Deep-Scan startet..."
            AF.UI.Lbl.ScanProgress.TextColor3     = D.Yellow
            if AF.UI.Btn.ForceRescan then AF.UI.Btn.ForceRescan.Text="Scannt..."; AF.UI.Btn.ForceRescan.TextColor3=D.Yellow end
        end)
        SetStatus("Deep-Scan läuft...", D.Purple)
        local ok = ScanAllRewards(function(msg)
            pcall(function()
                AF.UI.Lbl.DBStatus.Text       = msg
                AF.UI.Lbl.DBStatus.TextColor3 = D.Yellow
                if AF.UI.Lbl.ScanProgress then
                    AF.UI.Lbl.ScanProgress.Text       = msg
                    AF.UI.Lbl.ScanProgress.TextColor3 = D.Yellow
                end
            end)
        end)
        pcall(function()
            if AF.UI.Btn.ForceRescan then
                AF.UI.Btn.ForceRescan.Text       = "DATENBANK NEU SCANNEN"
                AF.UI.Btn.ForceRescan.TextColor3 = Color3.new(1,1,1)
            end
        end)
        if thenStartFarm and ok and DBCount()>0 and AF.Running and not AF.Active and GetNextItem() then
            task.spawn(FarmLoop)
        end
    end)
end

-- ★ Welten-Scan (ChapterLevels) – separater Task vom Reward-Scan
local RebuildWorldDropdowns  -- forward declaration
local function RunWorldScan(force, onDone)
    task.spawn(function()
        SetStatus("⏳ Scanne ChapterLevels...", D.Yellow)
        if force then DeleteWorldCache() end

        local data, ok = ScanChapterLevels()
        if ok then
            ApplyWorldData(data)
            SaveWorldCache(data)
            SetStatus(string.format("✅ %d Story · %d Ranger · %d Calamity · %d Raid",
                #data.Story, #data.Ranger, #data.Calamity, #data.Raid), D.Green)
        else
            SetStatus("⚠ Keine ChapterLevels gefunden.", D.Orange)
        end

        pcall(function() if RebuildWorldDropdowns then RebuildWorldDropdowns() end end)
        if onDone then pcall(onDone) end
    end)
end

-- ============================================================
--  AUTO-RESUME
-- ============================================================
local function TryAutoResume()
    task.wait(3)
    local hasQueue = LoadQueueFile()
    local state    = LoadState()
    local settings = LoadSettingsFile()

    if hasQueue then SyncInventoryWithQueue(); pcall(UpdateQueueUI) end

    local shouldResume = (settings and settings.AutoFarm == true)
                      or (state    and state.running    == true)

    if not shouldResume then
        SetStatus(hasQueue and string.format("Queue: %d Items – Farm AUS", #AF.Queue) or "Bereit.", D.TextMid)
        pcall(UpdateQueueUI); return
    end
    if not hasQueue or not GetNextItem() then
        _G.AutoFarmRunning=false
        if CFG then CFG.AutoFarm=false end
        if SaveConfig   then pcall(SaveConfig)   end
        if SaveSettings then pcall(SaveSettings) end
        if writefile then pcall(function() writefile(STATE_FILE, Svc.Http:JSONEncode({running=false,ts=os.time()})) end) end
        SetStatus("Queue leer – Farm nicht fortgesetzt.", D.Orange)
        pcall(UpdateQueueUI); return
    end
    if DBCount() == 0 then LoadDB() end
    if DBCount() == 0 then
        SetStatus("DB fehlt – Farm kann nicht gestartet werden!", D.Orange); return
    end
    SetStatus(string.format("Auto-Resume in 5s... (%d Items)", #AF.Queue), D.Yellow)
    task.wait(5)
    if not GetNextItem() then SetStatus("Auto-Resume: Queue leer.", D.Orange); return end
    if CheckIsLobby() then
        task.spawn(FarmLoop)
    else
        AF.Active=true; AF.Running=true; _G.AutoFarmRunning=true; SaveState()
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
                AF.Active=false; _G.AutoFarmRunning=false; SaveState()
            end
        end)
    end
    pcall(UpdateQueueUI)
end

-- Hintergrund-Sync
task.spawn(function()
    while true do task.wait(10)
        if #AF.Queue > 0 then
            if SyncInventoryWithQueue() then pcall(UpdateQueueUI) end
        end
    end
end)

-- ============================================================
--  GUI AUFBAUEN
-- ============================================================
VList(Container, 5)

-- STATUS
local sCard = Card(Container,36); Pad(sCard,6,10,6,10)
AF.UI.Lbl.Status = Instance.new("TextLabel",sCard)
AF.UI.Lbl.Status.Size                   = UDim2.new(1,0,1,0)
AF.UI.Lbl.Status.BackgroundTransparency = 1
AF.UI.Lbl.Status.Text                   = "Auto-Farm gestoppt"
AF.UI.Lbl.Status.TextColor3             = D.TextMid
AF.UI.Lbl.Status.TextSize               = 11
AF.UI.Lbl.Status.Font                   = Enum.Font.GothamSemibold
AF.UI.Lbl.Status.TextXAlignment         = Enum.TextXAlignment.Left

-- LOCATION
local locCard = Card(Container,22); Pad(locCard,2,10,2,10)
local locLbl  = Instance.new("TextLabel",locCard)
locLbl.Size=UDim2.new(1,0,1,0); locLbl.BackgroundTransparency=1
locLbl.Text="Ort: wird erkannt..."; locLbl.TextColor3=D.TextLow
locLbl.TextSize=10; locLbl.Font=Enum.Font.Gotham; locLbl.TextXAlignment=Enum.TextXAlignment.Left
task.spawn(function()
    while true do task.wait(2); pcall(function()
        if CheckIsLobby() then locLbl.Text="📍 LOBBY"; locLbl.TextColor3=D.Green
        else                    locLbl.Text="⚔ RUNDE";  locLbl.TextColor3=D.Orange end
    end) end
end)

-- ╔══════════════════════════════════════════════════════════╗
--  ★ WELTDATEN-KARTE  (ChapterLevels Scan + Cache)
-- ╔══════════════════════════════════════════════════════════╗
local worldCard = Card(Container); Pad(worldCard,10,10,10,10); VList(worldCard,7)
SecLbl(worldCard,"🌍  WELTDATEN")

local worldStatusLbl = MkLbl(worldCard,"Weltdaten nicht geladen.",11,D.TextLow)
worldStatusLbl.Size = UDim2.new(1,0,0,18)

-- Dropdown-State
local WD_State = {
    SelMode  = "Story",   -- "Story" | "Ranger" | "Calamity" | "Raid"
    SelWorld = nil,
    SelChap  = nil,
}

-- Modus-Buttons
local modeRow = Instance.new("Frame",worldCard)
modeRow.Size                   = UDim2.new(1,0,0,28)
modeRow.BackgroundTransparency = 1
HList(modeRow,5)

local MODES = {
    { id="Story",    label="📖 Story",    color=D.Cyan   },
    { id="Ranger",   label="🏹 Ranger",   color=D.Green  },
    { id="Calamity", label="⚡ Calamity", color=D.Orange },
    { id="Raid",     label="⚔ Raid",     color=D.Purple },
}
local modeBtns = {}

local worldListFrame = Instance.new("ScrollingFrame",worldCard)
worldListFrame.Size                = UDim2.new(1,0,0,160)
worldListFrame.CanvasSize          = UDim2.new(0,0,0,0)
worldListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
worldListFrame.BackgroundTransparency = 1
worldListFrame.BorderSizePixel     = 0
worldListFrame.ScrollBarThickness  = 4
worldListFrame.ScrollBarImageColor3 = D.CyanDim
worldListFrame.ScrollingEnabled    = true
worldListFrame.ScrollingDirection  = Enum.ScrollingDirection.Y
VList(worldListFrame,3)

local worldEmptyLbl = MkLbl(worldListFrame,"Keine Daten. Bitte 'Welten scannen' drücken.",11,D.TextLow)
worldEmptyLbl.Size = UDim2.new(1,0,0,26)

-- ★ RebuildWorldDropdowns – füllt die Liste dynamisch aus _G.HazeHUB.WorldData
RebuildWorldDropdowns = function()
    -- Alte Einträge löschen
    for _, v in pairs(worldListFrame:GetChildren()) do
        if v:IsA("Frame") or v:IsA("TextButton") then v:Destroy() end
    end

    local wd   = _G.HazeHUB.WorldData
    local mode = WD_State.SelMode
    local list = wd[mode] or {}

    worldEmptyLbl.Visible = (#list == 0)

    -- Modus-Button-Highlight
    for _, def in ipairs(MODES) do
        local b = modeBtns[def.id]
        if not b then continue end
        local active = (def.id == mode)
        if active then
            Tw(b,{BackgroundColor3=Color3.fromRGB(
                math.clamp(math.floor(def.color.R*255*0.25),0,255),
                math.clamp(math.floor(def.color.G*255*0.25),0,255),
                math.clamp(math.floor(def.color.B*255*0.25),0,255))})
            Stroke(b, def.color, 1.5, 0)
        else
            Tw(b,{BackgroundColor3=D.CardHover}); Stroke(b, D.Border, 1, 0.5)
        end
    end

    -- Weltdaten-Zeilen aufbauen
    -- Gruppiere nach World-ID (für Story/Ranger) oder direkt Chap-Name (Raid/Calamity)
    if mode == "Story" or mode == "Ranger" then
        -- Gruppiere nach worldId
        local groups   = {}
        local groupOrd = {}
        for _, e in ipairs(list) do
            if not groups[e.worldId] then
                groups[e.worldId] = {}
                table.insert(groupOrd, e.worldId)
            end
            table.insert(groups[e.worldId], e)
        end
        for _, wid in ipairs(groupOrd) do
            local chapList = groups[wid]
            -- Welt-Header
            local hdr = Instance.new("TextButton", worldListFrame)
            hdr.Size                   = UDim2.new(1,0,0,26)
            hdr.BackgroundColor3       = D.CardHover
            hdr.BackgroundTransparency = 0.3
            hdr.Text                   = "🌍  " .. wid
            hdr.TextColor3             = D.TextHi
            hdr.TextSize               = 11
            hdr.Font                   = Enum.Font.GothamBold
            hdr.AutoButtonColor        = false
            hdr.BorderSizePixel        = 0
            Corner(hdr, 6); Stroke(hdr, D.Border, 1, 0.4)

            -- Chapter-Row (expandierbar, initial ausgeblendet)
            local chapBody = Instance.new("Frame", worldListFrame)
            chapBody.Size                   = UDim2.new(1,0,0,0)
            chapBody.AutomaticSize          = Enum.AutomaticSize.Y
            chapBody.BackgroundTransparency = 1
            chapBody.Visible               = false
            VList(chapBody, 2)

            local capWid = wid
            hdr.MouseButton1Click:Connect(function()
                chapBody.Visible = not chapBody.Visible
                WD_State.SelWorld = chapBody.Visible and capWid or nil
                Stroke(hdr, chapBody.Visible and D.Cyan or D.Border, chapBody.Visible and 1.5 or 1, chapBody.Visible and 0 or 0.4)
            end)

            for _, e in ipairs(chapList) do
                local chapBtn = Instance.new("TextButton", chapBody)
                chapBtn.Size                   = UDim2.new(1,0,0,24)
                chapBtn.BackgroundColor3       = D.Card
                chapBtn.BackgroundTransparency = 0.3
                chapBtn.Text                   = "  › " .. e.name
                chapBtn.TextColor3             = D.TextMid
                chapBtn.TextSize               = 10
                chapBtn.Font                   = Enum.Font.GothamMedium
                chapBtn.AutoButtonColor        = false
                chapBtn.BorderSizePixel        = 0
                chapBtn.TextXAlignment         = Enum.TextXAlignment.Left
                Corner(chapBtn, 5); Stroke(chapBtn, D.Border, 1, 0.6)
                local capE = e
                chapBtn.MouseButton1Click:Connect(function()
                    WD_State.SelWorld = capE.worldId
                    WD_State.SelChap  = capE.name
                    -- Highlight
                    for _, ch in pairs(chapBody:GetChildren()) do
                        if ch:IsA("TextButton") then
                            ch.TextColor3 = D.TextMid
                            local s = ch:FindFirstChildOfClass("UIStroke"); if s then s.Transparency=0.6 end
                        end
                    end
                    chapBtn.TextColor3 = D.Cyan
                    Stroke(chapBtn, D.Cyan, 1.5, 0)
                    worldStatusLbl.Text      = string.format("✔ [%s] %s", mode, capE.name)
                    worldStatusLbl.TextColor3 = D.Cyan
                    -- Sync mit Hauptskript falls vorhanden
                    pcall(function()
                        if ST then ST.SelWorld=capE.worldId; ST.SelChap=capE.name; ST.SelMode=mode end
                    end)
                end)
            end
        end
    else
        -- Calamity / Raid: direkte Chap-Liste ohne World-Gruppierung
        for _, e in ipairs(list) do
            local chapBtn = Instance.new("TextButton", worldListFrame)
            chapBtn.Size                   = UDim2.new(1,0,0,26)
            chapBtn.BackgroundColor3       = D.CardHover
            chapBtn.BackgroundTransparency = 0.3
            chapBtn.Text                   = e.name
            chapBtn.TextColor3             = D.TextHi
            chapBtn.TextSize               = 10
            chapBtn.Font                   = Enum.Font.GothamBold
            chapBtn.AutoButtonColor        = false
            chapBtn.BorderSizePixel        = 0
            Corner(chapBtn, 6); Stroke(chapBtn, D.Border, 1, 0.5)
            local capE    = e
            local capMode = mode
            chapBtn.MouseButton1Click:Connect(function()
                WD_State.SelWorld = capE.raidType or capE.worldId or "Calamity"
                WD_State.SelChap  = capE.name
                for _, ch in pairs(worldListFrame:GetChildren()) do
                    if ch:IsA("TextButton") then
                        ch.TextColor3 = D.TextHi
                        local s = ch:FindFirstChildOfClass("UIStroke"); if s then s.Transparency=0.5 end
                    end
                end
                chapBtn.TextColor3 = D.Cyan
                Stroke(chapBtn, D.Cyan, 1.5, 0)
                worldStatusLbl.Text       = string.format("✔ [%s] %s", capMode, capE.name)
                worldStatusLbl.TextColor3 = D.Cyan
                pcall(function()
                    if ST then ST.SelChap=capE.name; ST.SelMode=capMode end
                end)
            end)
        end
    end

    -- Status-Zeile aktualisieren
    if _G.HazeHUB.IsDataLoaded() then
        local wd2 = _G.HazeHUB.WorldData
        worldStatusLbl.Text = string.format(
            "Story: %d  Ranger: %d  Calamity: %d  Raid: %d  |  Modus: %s",
            #wd2.Story, #wd2.Ranger, #wd2.Calamity, #wd2.Raid, mode)
        worldStatusLbl.TextColor3 = D.TextMid
    end
end

-- Modus-Buttons aufbauen
for _, def in ipairs(MODES) do
    local b = Instance.new("TextButton",modeRow)
    b.Size             = UDim2.new(0.24,0,0,26)
    b.BackgroundColor3 = D.CardHover
    b.Text             = def.label
    b.TextColor3       = def.color
    b.TextSize         = 9
    b.Font             = Enum.Font.GothamBold
    b.AutoButtonColor  = false
    b.BorderSizePixel  = 0
    Corner(b,6); Stroke(b,D.Border,1,0.5)
    modeBtns[def.id] = b
    local capDef = def
    b.MouseButton1Click:Connect(function()
        WD_State.SelMode  = capDef.id
        WD_State.SelWorld = nil
        WD_State.SelChap  = nil
        RebuildWorldDropdowns()
    end)
end

-- Welten-Scan-Buttons
local worldBtnRow = Instance.new("Frame",worldCard)
worldBtnRow.Size                   = UDim2.new(1,0,0,30)
worldBtnRow.BackgroundTransparency = 1
HList(worldBtnRow,6)

local scanWorldBtn = Instance.new("TextButton",worldBtnRow)
scanWorldBtn.Size=UDim2.new(0.62,0,0,30); scanWorldBtn.BackgroundColor3=D.CardHover; scanWorldBtn.BackgroundTransparency=0.18
scanWorldBtn.Text="🔄 Welten scannen"; scanWorldBtn.TextColor3=D.Cyan; scanWorldBtn.TextSize=11
scanWorldBtn.Font=Enum.Font.GothamBold; scanWorldBtn.AutoButtonColor=false; scanWorldBtn.BorderSizePixel=0
Corner(scanWorldBtn,8); Stroke(scanWorldBtn,D.Cyan,1,0.3)

local clearWorldBtn = Instance.new("TextButton",worldBtnRow)
clearWorldBtn.Size=UDim2.new(0.35,0,0,30); clearWorldBtn.BackgroundColor3=D.CardHover; clearWorldBtn.BackgroundTransparency=0.18
clearWorldBtn.Text="🗑 Cache löschen"; clearWorldBtn.TextColor3=D.Orange; clearWorldBtn.TextSize=10
clearWorldBtn.Font=Enum.Font.GothamBold; clearWorldBtn.AutoButtonColor=false; clearWorldBtn.BorderSizePixel=0
Corner(clearWorldBtn,8); Stroke(clearWorldBtn,D.Orange,1,0.4)

scanWorldBtn.MouseButton1Click:Connect(function()
    scanWorldBtn.Text="⏳ Scanne..."; scanWorldBtn.TextColor3=D.Yellow
    RunWorldScan(true, function()
        scanWorldBtn.Text="🔄 Welten scannen"; scanWorldBtn.TextColor3=D.Cyan
    end)
end)

clearWorldBtn.MouseButton1Click:Connect(function()
    DeleteWorldCache()
    _G.HazeHUB.WorldData = { Story={}, Ranger={}, Calamity={}, Raid={} }
    RebuildWorldDropdowns()
    worldStatusLbl.Text       = "Cache gelöscht."
    worldStatusLbl.TextColor3 = D.Orange
end)

-- DB-KARTE
local dbCard = Card(Container); Pad(dbCard,10,10,10,10); VList(dbCard,7)
SecLbl(dbCard,"REWARD-DATENBANK")
AF.UI.Lbl.DBStatus = MkLbl(dbCard,"Keine DB geladen.",11,D.TextLow); AF.UI.Lbl.DBStatus.Size=UDim2.new(1,0,0,18)

local spLbl = Instance.new("TextLabel",dbCard); spLbl.Size=UDim2.new(1,0,0,16); spLbl.BackgroundTransparency=1
spLbl.Text=""; spLbl.TextColor3=D.Yellow; spLbl.TextSize=10; spLbl.Font=Enum.Font.Gotham
spLbl.TextXAlignment=Enum.TextXAlignment.Left; spLbl.TextTruncate=Enum.TextTruncate.AtEnd
AF.UI.Lbl.ScanProgress = spLbl

local barBg = Instance.new("Frame",dbCard); barBg.Size=UDim2.new(1,0,0,7); barBg.BackgroundColor3=D.Input; barBg.BackgroundTransparency=0.18; barBg.BorderSizePixel=0; barBg.Visible=false; Corner(barBg,3); AF.UI.Fr.ScanBar=barBg
local barFill = Instance.new("Frame",barBg); barFill.Size=UDim2.new(0,0,1,0); barFill.BackgroundColor3=D.Purple; barFill.BorderSizePixel=0; Corner(barFill,3); AF.UI.Fr.ScanBarFill=barFill

local loadDbBtn = Instance.new("TextButton",dbCard)
loadDbBtn.Size=UDim2.new(1,0,0,28); loadDbBtn.BackgroundColor3=D.CardHover; loadDbBtn.BackgroundTransparency=0.18
loadDbBtn.Text="DB laden"; loadDbBtn.TextColor3=D.CyanDim; loadDbBtn.TextSize=11; loadDbBtn.Font=Enum.Font.GothamBold
loadDbBtn.AutoButtonColor=false; loadDbBtn.BorderSizePixel=0; Corner(loadDbBtn,8); Stroke(loadDbBtn,D.CyanDim,1,0.3)
loadDbBtn.MouseEnter:Connect(function() Tw(loadDbBtn,{BackgroundColor3=D.TabActive}) end)
loadDbBtn.MouseLeave:Connect(function() Tw(loadDbBtn,{BackgroundColor3=D.CardHover}) end)
loadDbBtn.MouseButton1Click:Connect(function()
    if LoadDB() then
        local c = DBCount()
        AF.UI.Lbl.DBStatus.Text       = string.format("✅ DB: %d Chapters", c)
        AF.UI.Lbl.DBStatus.TextColor3 = D.Green
        _G.HazeHUB_Database = AF.RewardDatabase
        NotifyDBReady(c, string.format("RewardDB geladen! (%d Chapters)", c))
    else
        AF.UI.Lbl.DBStatus.Text       = "Keine gültige RewardDB."
        AF.UI.Lbl.DBStatus.TextColor3 = D.Orange
    end
end)

local updateDbBtn = Instance.new("TextButton",dbCard)
updateDbBtn.Size=UDim2.new(1,0,0,34); updateDbBtn.BackgroundColor3=D.CardHover; updateDbBtn.BackgroundTransparency=0.18
updateDbBtn.Text="Update RewardDB (Deep-Scan)"; updateDbBtn.TextColor3=D.Accent or D.Cyan; updateDbBtn.TextSize=11; updateDbBtn.Font=Enum.Font.GothamBold
updateDbBtn.AutoButtonColor=false; updateDbBtn.BorderSizePixel=0; Corner(updateDbBtn,8); Stroke(updateDbBtn,D.Accent or D.Cyan,1.5,0.2)
AF.UI.Btn.UpdateDB = updateDbBtn
updateDbBtn.MouseEnter:Connect(function() Tw(updateDbBtn,{BackgroundColor3=D.TabActive}) end)
updateDbBtn.MouseLeave:Connect(function() Tw(updateDbBtn,{BackgroundColor3=D.CardHover}) end)
updateDbBtn.MouseButton1Click:Connect(function()
    if not CheckIsLobby() then SetStatus("Nur in Lobby!",D.Orange); return end
    if AF.Scanning then SetStatus("Scan läuft!",D.Yellow); return end
    if not _G.HazeHUB.IsDataLoaded() then
        SetStatus("⚠ Erst Welten scannen!",D.Orange); return
    end
    updateDbBtn.Text="Scannt..."; updateDbBtn.TextColor3=D.Yellow
    RunRewardScanTask(true,false)
end)

local forceBtn = Instance.new("TextButton",dbCard)
forceBtn.Size=UDim2.new(1,0,0,40); forceBtn.BackgroundColor3=Color3.fromRGB(68,10,108)
forceBtn.Text="REWARD-DB NEU SCANNEN"; forceBtn.TextColor3=Color3.new(1,1,1); forceBtn.TextSize=13; forceBtn.Font=Enum.Font.GothamBold
forceBtn.AutoButtonColor=false; forceBtn.BorderSizePixel=0; Corner(forceBtn,9); Stroke(forceBtn,Color3.fromRGB(180,80,255),2,0)
AF.UI.Btn.ForceRescan = forceBtn
forceBtn.MouseEnter:Connect(function()    Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(110,22,170)}) end)
forceBtn.MouseLeave:Connect(function()    Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(68,10,108)})  end)
forceBtn.MouseButton1Down:Connect(function() Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(40,5,72)}) end)
forceBtn.MouseButton1Up:Connect(function()   Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(110,22,170)}) end)
forceBtn.MouseButton1Click:Connect(function()
    if not _G.HazeHUB.IsDataLoaded() then
        SetStatus("⚠ Erst Welten scannen!", D.Orange); return
    end
    RunRewardScanTask(true,false)
end)

-- QUEUE-KARTE
local qCard = Card(Container); Pad(qCard,10,10,10,10); VList(qCard,8); SecLbl(qCard,"AUTO-FARM QUEUE")
local qFileInfo = MkLbl(qCard,"Keine Queue.",10,D.TextLow); qFileInfo.Size=UDim2.new(1,0,0,14); AF.UI.Lbl.QueueFileInfo=qFileInfo

local qRow = Instance.new("Frame",qCard); qRow.Size=UDim2.new(1,0,0,30); qRow.BackgroundTransparency=1; HList(qRow,5)
local qItemOuter,qItemBox = MkInput(qRow,"Item-Name..."); qItemOuter.Size=UDim2.new(0.50,0,0,30)
local qAmtOuter,qAmtBox   = MkInput(qRow,"Anzahl");       qAmtOuter.Size=UDim2.new(0.28,0,0,30)
local qAddBtn = Instance.new("TextButton",qRow)
qAddBtn.Size=UDim2.new(0.19,0,0,30); qAddBtn.BackgroundColor3=D.Green; qAddBtn.Text="+ Add"
qAddBtn.TextColor3=Color3.new(1,1,1); qAddBtn.TextSize=11; qAddBtn.Font=Enum.Font.GothamBold
qAddBtn.AutoButtonColor=false; qAddBtn.BorderSizePixel=0; Corner(qAddBtn,7); Stroke(qAddBtn,D.Green,1,0.2)
qAddBtn.MouseEnter:Connect(function() Tw(qAddBtn,{BackgroundColor3=Color3.fromRGB(0,160,80)}) end)
qAddBtn.MouseLeave:Connect(function() Tw(qAddBtn,{BackgroundColor3=D.Green}) end)
qAddBtn.MouseButton1Click:Connect(function()
    local iname = (qItemBox.Text or ""):match("^%s*(.-)%s*$")
    local iamt  = tonumber(qAmtBox.Text)
    if iname=="" or not iamt or iamt<=0 then return end
    if ST and ST.Goals then
        local found=false; for _,g in ipairs(ST.Goals) do if g.item==iname then found=true; break end end
        if not found then table.insert(ST.Goals,{item=iname,amount=iamt,reached=false}); if SaveConfig then pcall(SaveConfig) end end
    end
    local inQ=false; for _,q in ipairs(AF.Queue) do if q.item==iname then inQ=true; break end end
    if not inQ then table.insert(AF.Queue,{item=iname,amount=iamt,done=false}); SaveQueueFile() end
    qItemBox.Text=""; qAmtBox.Text=""
    UpdateQueueUI()
    pcall(function() if HS.UpdateGoalsUI then HS.UpdateGoalsUI() end end)
    pcall(function() AF.UI.Lbl.QueueFileInfo.Text="Queue: "..#AF.Queue.." Items"; AF.UI.Lbl.QueueFileInfo.TextColor3=D.Green end)
end)

local ctrlRow = Instance.new("Frame",qCard); ctrlRow.Size=UDim2.new(1,0,0,32); ctrlRow.BackgroundTransparency=1; ctrlRow.LayoutOrder=3; HList(ctrlRow,8)
local startBtn = Instance.new("TextButton",ctrlRow)
startBtn.Size=UDim2.new(0.48,0,0,32); startBtn.BackgroundColor3=D.Green; startBtn.Text="Start Queue"
startBtn.TextColor3=Color3.new(1,1,1); startBtn.TextSize=12; startBtn.Font=Enum.Font.GothamBold
startBtn.AutoButtonColor=false; startBtn.BorderSizePixel=0; Corner(startBtn,8); Stroke(startBtn,D.Green,1,0.2)
local stopBtn = Instance.new("TextButton",ctrlRow)
stopBtn.Size=UDim2.new(0.48,0,0,32); stopBtn.BackgroundColor3=D.RedDark; stopBtn.Text="Stop"
stopBtn.TextColor3=D.Red; stopBtn.TextSize=12; stopBtn.Font=Enum.Font.GothamBold
stopBtn.AutoButtonColor=false; stopBtn.BorderSizePixel=0; Corner(stopBtn,8); Stroke(stopBtn,D.Red,1,0.4)

startBtn.MouseButton1Click:Connect(function()
    if AF.Active then SetStatus("Farm läuft!",D.Yellow); return end
    if #AF.Queue==0 then SetStatus("Queue leer!",D.Orange); return end
    if CFG then CFG.AutoFarm=true end
    if SaveConfig   then pcall(SaveConfig)   end
    if SaveSettings then pcall(SaveSettings) end
    AF.Running=true; _G.AutoFarmRunning=true; SaveState()
    if DBCount()==0 then
        SetStatus("DB leer – Scan...",D.Yellow)
        pcall(function() startBtn.Text="Scannt..."; startBtn.TextColor3=D.Yellow end)
        RunRewardScanTask(false,true)
    else task.spawn(FarmLoop) end
end)
stopBtn.MouseButton1Click:Connect(function()
    StopFarm(); startBtn.Text="Start Queue"; startBtn.TextColor3=Color3.new(1,1,1)
end)

task.spawn(function() while true do task.wait(1); if not AF.Scanning then pcall(function()
    if startBtn.Text=="Scannt..."      then startBtn.Text="Start Queue";             startBtn.TextColor3=Color3.new(1,1,1) end
    if updateDbBtn.Text=="Scannt..."   then updateDbBtn.Text="Update RewardDB (Deep-Scan)"; updateDbBtn.TextColor3=D.Accent or D.Cyan end
end) end end end)
task.spawn(function() while true do task.wait(8); pcall(UpdateQueueUI) end end)

local clearBtn = NeonBtn(qCard,"Queue leeren",D.Red,28); clearBtn.LayoutOrder=4
clearBtn.MouseButton1Click:Connect(function()
    AF.Queue={}; SaveQueueFile(); UpdateQueueUI()
    pcall(function() AF.UI.Lbl.QueueFileInfo.Text="Queue geleert."; AF.UI.Lbl.QueueFileInfo.TextColor3=D.TextLow end)
end)

AF.UI.Fr.List = Instance.new("ScrollingFrame",qCard)
AF.UI.Fr.List.LayoutOrder            = 5
AF.UI.Fr.List.Size                   = UDim2.new(1,0,0,190)
AF.UI.Fr.List.CanvasSize             = UDim2.new(0,0,0,0)
AF.UI.Fr.List.AutomaticCanvasSize    = Enum.AutomaticSize.Y
AF.UI.Fr.List.ScrollBarThickness     = 4
AF.UI.Fr.List.ScrollBarImageColor3   = D.CyanDim
AF.UI.Fr.List.BackgroundTransparency = 1
AF.UI.Fr.List.BorderSizePixel        = 0
VList(AF.UI.Fr.List,4)
AF.UI.Lbl.QueueEmpty = MkLbl(AF.UI.Fr.List,"Queue leer.",11,D.TextLow)
AF.UI.Lbl.QueueEmpty.Size = UDim2.new(1,0,0,24)

-- ============================================================
--  ★ AUTO-CHALLENGE
-- ============================================================
local AF_Challenge = { Items={}, Active=false, Running=false, SelIdx=nil }

local function ScanChallengeItems()
    AF_Challenge.Items = {}
    pcall(function()
        local folder = RS:WaitForChild("Gameplay",10)
                          :WaitForChild("Game",10)
                          :WaitForChild("Challenge",10)
                          :WaitForChild("Items",10)
        for _, item in ipairs(folder:GetChildren()) do
            if item:IsA("UIGridLayout") or item:IsA("UIListLayout") then continue end
            local dropRate = tonumber(item:GetAttribute("DropRate")) or 0
            local maxDrop  = tonumber(item:GetAttribute("MaxDrop"))  or 1
            local minDrop  = tonumber(item:GetAttribute("MinDrop"))  or 1
            -- ★ Smart-Farm Score
            local score = dropRate * maxDrop
            table.insert(AF_Challenge.Items, {
                name     = item.Name,
                chapName = (item:FindFirstChild("ChallengeName") and tostring(item.ChallengeName.Value)) or item.Name,
                world    = (item:FindFirstChild("World")   and tostring(item.World.Value))   or "Unknown",
                chapter  = (item:FindFirstChild("Chapter") and tostring(item.Chapter.Value)) or "Unknown",
                dropRate = dropRate,
                maxDrop  = maxDrop,
                minDrop  = minDrop,
                score    = score,
            })
        end
        -- Sortiere nach Score (höchster zuerst)
        table.sort(AF_Challenge.Items, function(a,b) return a.score > b.score end)
    end)
    return #AF_Challenge.Items
end

local function StartChallengeLoop()
    if AF_Challenge.Active then return end
    local item = AF_Challenge.SelIdx and AF_Challenge.Items[AF_Challenge.SelIdx]
    if not item then SetStatus("⚠ Kein Challenge-Item gewählt!", D.Orange); return end
    AF_Challenge.Active = true; AF_Challenge.Running = true
    SetStatus(string.format("⚡ Challenge: %s (Score: %.1f)", item.chapName, item.score), D.Cyan)
    task.spawn(function()
        while AF_Challenge.Running do
            if CheckIsLobby() then
                SetStatus("⚡ Starte Challenge: " .. item.chapName, D.Yellow)
                pcall(function()
                    if PlayRoomEvent then
                        PlayRoomEvent:FireServer("Create", { ["CreateChallengeRoom"] = true })
                    end
                    task.wait(0.5)
                    Fire("Change-World",   { World   = item.world   }); task.wait(0.4)
                    Fire("Change-Chapter", { Chapter = item.chapter }); task.wait(0.4)
                    Fire("Submit"); task.wait(0.5); Fire("Start")
                end)
                local ws = os.clock()
                while CheckIsLobby() and os.clock()-ws < 30 and AF_Challenge.Running do task.wait(1) end
            else
                SetStatus("⚡ Challenge läuft: " .. item.chapName, D.Cyan)
                local deadline = os.time() + 600
                while not CheckIsLobby() and os.time() < deadline and AF_Challenge.Running do task.wait(3) end
                task.wait(2)
            end
        end
        AF_Challenge.Active = false; SetStatus("⏹ Challenge gestoppt.", D.TextMid)
    end)
end

local chalCard = Card(Container); Pad(chalCard,10,10,10,10); VList(chalCard,8)
SecLbl(chalCard,"⚡  AUTO-CHALLENGE")
local chalStatusLbl = MkLbl(chalCard,"Items nicht gescannt.",10,D.TextLow); chalStatusLbl.Size=UDim2.new(1,0,0,16)

local chalListFrame = Instance.new("ScrollingFrame",chalCard)
chalListFrame.Size=UDim2.new(1,0,0,140); chalListFrame.CanvasSize=UDim2.new(0,0,0,0)
chalListFrame.AutomaticCanvasSize=Enum.AutomaticSize.Y; chalListFrame.BackgroundTransparency=1
chalListFrame.BorderSizePixel=0; chalListFrame.ScrollBarThickness=4
chalListFrame.ScrollBarImageColor3=D.CyanDim; chalListFrame.ScrollingEnabled=true
chalListFrame.ScrollingDirection=Enum.ScrollingDirection.Y
VList(chalListFrame,4)
local chalEmptyLbl = MkLbl(chalListFrame,"Keine Items gescannt.",10,D.TextLow); chalEmptyLbl.Size=UDim2.new(1,0,0,22)

local function RebuildChallengeList()
    for _, v in pairs(chalListFrame:GetChildren()) do if v:IsA("Frame") then v:Destroy() end end
    chalEmptyLbl.Visible = (#AF_Challenge.Items == 0)
    for i, item in ipairs(AF_Challenge.Items) do
        local isSel = (AF_Challenge.SelIdx == i)
        local row   = Instance.new("Frame",chalListFrame)
        row.Size=UDim2.new(1,0,0,44); row.BackgroundColor3=isSel and D.TabActive or D.CardHover; row.BackgroundTransparency=0.3; row.BorderSizePixel=0
        Corner(row,7); Stroke(row,isSel and D.Cyan or D.Border,1.5,isSel and 0 or 0.5)
        local nL=Instance.new("TextLabel",row); nL.Position=UDim2.new(0,8,0,3); nL.Size=UDim2.new(1,-16,0,18); nL.BackgroundTransparency=1
        nL.Text=item.chapName; nL.TextColor3=isSel and D.Cyan or D.TextHi; nL.TextSize=11; nL.Font=Enum.Font.GothamBold; nL.TextXAlignment=Enum.TextXAlignment.Left; nL.TextTruncate=Enum.TextTruncate.AtEnd
        local sL=Instance.new("TextLabel",row); sL.Position=UDim2.new(0,8,0,23); sL.Size=UDim2.new(1,-16,0,14); sL.BackgroundTransparency=1
        sL.Text=string.format("Score: %.1f  Drop: %.1f%%  Min:%d  Max:%d", item.score, item.dropRate, item.minDrop, item.maxDrop)
        sL.TextColor3=D.TextMid; sL.TextSize=9; sL.Font=Enum.Font.Gotham; sL.TextXAlignment=Enum.TextXAlignment.Left
        local btn=Instance.new("TextButton",row); btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.BorderSizePixel=0
        local capI=i; btn.MouseButton1Click:Connect(function() AF_Challenge.SelIdx=capI; RebuildChallengeList() end)
    end
end

local chalScanBtn = NeonBtn(chalCard,"🔍 Challenge Items scannen",D.CyanDim,28)
chalScanBtn.MouseButton1Click:Connect(function()
    chalScanBtn.Text="⏳ Scanne..."; chalScanBtn.TextColor3=D.Yellow
    task.spawn(function()
        local n = ScanChallengeItems()
        RebuildChallengeList()
        chalStatusLbl.Text       = n>0 and string.format("✅ %d Items (nach Score sortiert).",n) or "⚠ Keine Items."
        chalStatusLbl.TextColor3 = n>0 and D.Green or D.Orange
        chalScanBtn.Text="🔍 Challenge Items scannen"; chalScanBtn.TextColor3=D.CyanDim
    end)
end)

local chalCtrlRow=Instance.new("Frame",chalCard); chalCtrlRow.Size=UDim2.new(1,0,0,32); chalCtrlRow.BackgroundTransparency=1; HList(chalCtrlRow,8)
local chalStartBtn=Instance.new("TextButton",chalCtrlRow); chalStartBtn.Size=UDim2.new(0.58,0,0,32); chalStartBtn.BackgroundColor3=D.Green; chalStartBtn.Text="▶ Start"; chalStartBtn.TextColor3=Color3.new(1,1,1); chalStartBtn.TextSize=11; chalStartBtn.Font=Enum.Font.GothamBold; chalStartBtn.AutoButtonColor=false; chalStartBtn.BorderSizePixel=0; Corner(chalStartBtn,8); Stroke(chalStartBtn,D.Green,1,0.2)
local chalStopBtn=Instance.new("TextButton",chalCtrlRow);  chalStopBtn.Size=UDim2.new(0.38,0,0,32);  chalStopBtn.BackgroundColor3=D.RedDark;  chalStopBtn.Text="■ Stop";   chalStopBtn.TextColor3=D.Red;              chalStopBtn.TextSize=11; chalStopBtn.Font=Enum.Font.GothamBold;  chalStopBtn.AutoButtonColor=false; chalStopBtn.BorderSizePixel=0;  Corner(chalStopBtn,8);  Stroke(chalStopBtn,D.Red,1,0.4)
chalStartBtn.MouseButton1Click:Connect(function()
    if AF_Challenge.Active then SetStatus("⚠ Challenge läuft!",D.Yellow); return end; StartChallengeLoop()
end)
chalStopBtn.MouseButton1Click:Connect(function()
    AF_Challenge.Active=false; AF_Challenge.Running=false; SetStatus("⏹ Challenge gestoppt.",D.TextMid)
end)

-- ============================================================
--  ★ RAID FARM
-- ============================================================
local RAID_DEFS = {
    { id="EsperRaid", label="🔮 Esper Raid", world="EsperRaid", accent=Color3.fromRGB(160,80,255),
      chapters={ { id="Esper_Raid_Chapter1", label="Chapter 1", modes={"Normal","Nightmare"} } } },
    { id="JJKRaid",   label="🌀 JJK Raid",   world="JJKRaid",   accent=Color3.fromRGB(80,140,255),
      chapters={ { id="JJK_Raid_Chapter1", label="Chapter 1", modes={"Normal"} },
                 { id="JJK_Raid_Chapter2", label="Chapter 2", modes={"Normal"} } } },
}
local RaidState = { Active=false, Running=false, SelRaid=nil, SelChap=nil, SelMode="Normal" }

local function ScanRaidDrops()
    local results, bestScore, bestName = {}, -1, "?"
    pcall(function()
        local itemsList = LP.PlayerGui.PlayRoom.Main.GameStage.Main.Base.Rewards.ItemsList
        for _, item in ipairs(itemsList:GetChildren()) do
            if item:IsA("UIGridLayout") or item:IsA("UIListLayout") then continue end
            local iname, dropAmt, dropRate = item.Name, 0, 0
            pcall(function()
                local frame = item:FindFirstChild("Frame")
                local iFrame = frame and frame:FindFirstChild("ItemFrame")
                local info   = iFrame and iFrame:FindFirstChild("Info")
                if info then
                    local da = info:FindFirstChild("DropAmonut") or info:FindFirstChild("DropAmount")
                    local dr = info:FindFirstChild("DropRate")
                    if da then dropAmt  = tonumber(da.Text or da.Value or "0") or 0 end
                    if dr then dropRate = tonumber(dr.Text or dr.Value or "0") or 0 end
                end
            end)
            if iname ~= "" then
                local score = dropRate * dropAmt
                results[iname] = { dropAmount=dropAmt, dropRate=dropRate, score=score }
                if score > bestScore then bestScore=score; bestName=iname end
            end
        end
    end)
    return results, bestName, bestScore
end

local function StartRaidLoop()
    if RaidState.Active then return end
    local raidDef = RaidState.SelRaid and RAID_DEFS[RaidState.SelRaid]
    if not raidDef then SetStatus("⚠ Raid + Chapter + Modus wählen!", D.Orange); return end
    local chapDef = raidDef.chapters[RaidState.SelChap or 1]
    local mode    = RaidState.SelMode or "Normal"
    if not chapDef then SetStatus("⚠ Chapter nicht gefunden!", D.Orange); return end
    RaidState.Active=true; RaidState.Running=true
    SetStatus(string.format("⚔ Raid: %s %s (%s)", raidDef.label, chapDef.label, mode), D.Cyan)
    task.spawn(function()
        while RaidState.Running do
            if CheckIsLobby() then
                SetStatus(string.format("🚀 Starte %s %s", raidDef.label, chapDef.label), D.Yellow)
                pcall(function()
                    Fire("Create"); task.wait(0.4)
                    Fire("Change-World",   { World   = raidDef.world }); task.wait(0.4)
                    Fire("Change-Chapter", { Chapter = chapDef.id });    task.wait(0.4)
                    if mode=="Nightmare" then Fire("Change-Difficulty",{Difficulty="Nightmare"}); task.wait(0.35) end
                    Fire("Submit"); task.wait(0.5); Fire("Start")
                end)
                local ws=os.clock(); while CheckIsLobby() and os.clock()-ws<30 and RaidState.Running do task.wait(1) end
            else
                local _, bestName, bestScore = ScanRaidDrops()
                SetStatus(string.format("⚔ Raid läuft | Best: %s (%.1f)", bestName, bestScore), D.Cyan)
                local deadline=os.time()+600; while not CheckIsLobby() and os.time()<deadline and RaidState.Running do task.wait(3) end
                task.wait(2)
            end
        end
        RaidState.Active=false; SetStatus("⏹ Raid gestoppt.",D.TextMid)
    end)
end

local raidCard=Card(Container); Pad(raidCard,10,10,10,10); VList(raidCard,8); SecLbl(raidCard,"⚔  RAID FARM")
local raidSelFrame=Instance.new("Frame",raidCard); raidSelFrame.Size=UDim2.new(1,0,0,0); raidSelFrame.AutomaticSize=Enum.AutomaticSize.Y; raidSelFrame.BackgroundTransparency=1; VList(raidSelFrame,4)

for ri, rdef in ipairs(RAID_DEFS) do
    local rCont=Instance.new("Frame",raidSelFrame); rCont.Size=UDim2.new(1,0,0,0); rCont.AutomaticSize=Enum.AutomaticSize.Y; rCont.BackgroundTransparency=1; VList(rCont,3)
    local rHdr=Instance.new("TextButton",rCont); rHdr.Size=UDim2.new(1,0,0,28); rHdr.BackgroundColor3=D.CardHover; rHdr.BackgroundTransparency=0.3; rHdr.Text=rdef.label; rHdr.TextColor3=rdef.accent; rHdr.TextSize=12; rHdr.Font=Enum.Font.GothamBold; rHdr.AutoButtonColor=false; rHdr.BorderSizePixel=0; Corner(rHdr,7); Stroke(rHdr,rdef.accent,1,0.4)
    local chapBody=Instance.new("Frame",rCont); chapBody.Size=UDim2.new(1,0,0,0); chapBody.AutomaticSize=Enum.AutomaticSize.Y; chapBody.BackgroundTransparency=1; chapBody.Visible=false; VList(chapBody,3)
    local capRi=ri
    rHdr.MouseButton1Click:Connect(function()
        RaidState.SelRaid=capRi; chapBody.Visible=not chapBody.Visible
        Stroke(rHdr,rdef.accent,1.5,chapBody.Visible and 0 or 0.4)
    end)
    for ci, chap in ipairs(rdef.chapters) do
        local cRow=Instance.new("Frame",chapBody); cRow.Size=UDim2.new(1,0,0,28); cRow.BackgroundTransparency=1; HList(cRow,4)
        local cLbl=Instance.new("TextLabel",cRow); cLbl.Size=UDim2.new(0.35,0,1,0); cLbl.BackgroundTransparency=1; cLbl.Text=chap.label; cLbl.TextColor3=D.TextMid; cLbl.TextSize=10; cLbl.Font=Enum.Font.GothamSemibold; cLbl.TextXAlignment=Enum.TextXAlignment.Left
        for _, modeStr in ipairs(chap.modes) do
            local mc=modeStr=="Nightmare" and D.Red or D.Green
            local mb=Instance.new("TextButton",cRow); mb.Size=UDim2.new(0,76,1,0); mb.BackgroundColor3=D.CardHover; mb.BackgroundTransparency=0.4; mb.Text=modeStr; mb.TextColor3=mc; mb.TextSize=10; mb.Font=Enum.Font.GothamBold; mb.AutoButtonColor=false; mb.BorderSizePixel=0; Corner(mb,6); Stroke(mb,mc,1,0.4)
            local capCi,capMode,capR=ci,modeStr,ri
            mb.MouseButton1Click:Connect(function()
                RaidState.SelRaid=capR; RaidState.SelChap=capCi; RaidState.SelMode=capMode
                Tw(mb,{BackgroundColor3=modeStr=="Nightmare" and D.RedDark or D.GreenDark,BackgroundTransparency=0.2})
                local s=mb:FindFirstChildOfClass("UIStroke"); if s then s.Transparency=0 end
                SetStatus(string.format("✔ %s %s (%s)",rdef.label,chap.label,modeStr),D.Cyan)
            end)
        end
    end
end

local raidCtrlRow=Instance.new("Frame",raidCard); raidCtrlRow.Size=UDim2.new(1,0,0,32); raidCtrlRow.BackgroundTransparency=1; HList(raidCtrlRow,8)
local raidStartBtn=Instance.new("TextButton",raidCtrlRow); raidStartBtn.Size=UDim2.new(0.58,0,0,32); raidStartBtn.BackgroundColor3=D.Green; raidStartBtn.Text="▶ Start Raid"; raidStartBtn.TextColor3=Color3.new(1,1,1); raidStartBtn.TextSize=11; raidStartBtn.Font=Enum.Font.GothamBold; raidStartBtn.AutoButtonColor=false; raidStartBtn.BorderSizePixel=0; Corner(raidStartBtn,8); Stroke(raidStartBtn,D.Green,1,0.2)
local raidStopBtn=Instance.new("TextButton",raidCtrlRow);  raidStopBtn.Size=UDim2.new(0.38,0,0,32);  raidStopBtn.BackgroundColor3=D.RedDark;  raidStopBtn.Text="■ Stop";        raidStopBtn.TextColor3=D.Red;              raidStopBtn.TextSize=11; raidStopBtn.Font=Enum.Font.GothamBold;  raidStopBtn.AutoButtonColor=false; raidStopBtn.BorderSizePixel=0;  Corner(raidStopBtn,8);  Stroke(raidStopBtn,D.Red,1,0.4)
raidStartBtn.MouseButton1Click:Connect(function()
    if RaidState.Active then SetStatus("⚠ Raid läuft!",D.Yellow); return end; StartRaidLoop()
end)
raidStopBtn.MouseButton1Click:Connect(function()
    RaidState.Active=false; RaidState.Running=false; SetStatus("⏹ Raid gestoppt.",D.TextMid)
end)

-- ============================================================
--  STARTUP
-- ============================================================

-- ★ 1. WorldCache sofort laden (verhindert Wartezeit)
local cachedWorld = LoadWorldCache()
if cachedWorld then
    ApplyWorldData(cachedWorld)
    worldStatusLbl.Text       = string.format("✅ Cache: Story:%d Ranger:%d Calamity:%d Raid:%d",
        #cachedWorld.Story, #cachedWorld.Ranger, #cachedWorld.Calamity, #cachedWorld.Raid)
    worldStatusLbl.TextColor3 = D.Green
    pcall(RebuildWorldDropdowns)
else
    worldStatusLbl.Text       = "⚠ Kein Cache – 'Welten scannen' drücken."
    worldStatusLbl.TextColor3 = D.Orange
    -- Automatischer Hintergrund-Scan beim ersten Start
    task.delay(2, function()
        RunWorldScan(false, nil)
    end)
end

-- ★ 2. RewardDB laden
if isfile and isfile(DB_FILE) then
    local raw; pcall(function() raw=readfile(DB_FILE) end)
    if raw and #raw<10 then
        AF.UI.Lbl.DBStatus.Text="⚠ RewardDB korrupt!"; AF.UI.Lbl.DBStatus.TextColor3=D.Orange
    elseif LoadDB() then
        local c=DBCount()
        AF.UI.Lbl.DBStatus.Text       = string.format("✅ RewardDB: %d Chapters",c)
        AF.UI.Lbl.DBStatus.TextColor3 = D.Green
        _G.HazeHUB_Database = AF.RewardDatabase
        task.delay(0.5, function() NotifyDBReady(c, string.format("RewardDB geladen! (%d Chapters)",c)) end)
    end
else
    AF.UI.Lbl.DBStatus.Text       = "Keine RewardDB."
    AF.UI.Lbl.DBStatus.TextColor3 = D.TextLow
end

-- ★ 3. Auto-Resume
task.spawn(TryAutoResume)

-- ============================================================
--  TRIGGER RESET RESCAN (wird vom Hauptskript aufgerufen)
-- ============================================================
HS.TriggerResetRescan = function(onProgress)
    if AF.Scanning then
        pcall(function() if onProgress then onProgress("⚠ Scan läuft!") end end); return
    end
    ClearDB()
    pcall(function()
        AF.UI.Lbl.DBStatus.Text            = "⏳ Reset & Rescan..."
        AF.UI.Lbl.DBStatus.TextColor3      = D.Yellow
        AF.UI.Fr.ScanBar.Visible           = true
        AF.UI.Fr.ScanBarFill.Size          = UDim2.new(0,0,1,0)
        AF.UI.Fr.ScanBarFill.BackgroundColor3 = D.Purple
        if AF.UI.Btn.ForceRescan then AF.UI.Btn.ForceRescan.Text="Scannt..."; AF.UI.Btn.ForceRescan.TextColor3=D.Yellow end
        if AF.UI.Btn.UpdateDB   then AF.UI.Btn.UpdateDB.Text="Scannt...";    AF.UI.Btn.UpdateDB.TextColor3=D.Yellow    end
    end)
    task.spawn(function()
        local combined = function(msg)
            pcall(function() AF.UI.Lbl.DBStatus.Text=msg; AF.UI.Lbl.DBStatus.TextColor3=D.Yellow end)
            if onProgress then pcall(function() onProgress(msg) end) end
        end
        local ok = ScanAllRewards(combined)
        pcall(function()
            if AF.UI.Btn.ForceRescan then AF.UI.Btn.ForceRescan.Text="REWARD-DB NEU SCANNEN"; AF.UI.Btn.ForceRescan.TextColor3=Color3.new(1,1,1) end
            if AF.UI.Btn.UpdateDB   then AF.UI.Btn.UpdateDB.Text="Update RewardDB (Deep-Scan)"; AF.UI.Btn.UpdateDB.TextColor3=D.Accent or D.Cyan end
        end)
        local finalMsg = ok
            and string.format("✅ Fertig! %d Chapters.", DBCount())
            or  "⚠ Scan abgeschlossen (einige Chapters fehlgeschlagen)."
        pcall(function() onProgress(finalMsg) end)
        if ok then NotifyDBReady(DBCount(), finalMsg) end
    end)
end

-- Abwärtskompatibilität: IsScanDone / GetWorldData / GetWorldIds
HS.IsScanDone  = function() return _G.HazeHUB.IsDataLoaded() end
HS.GetWorldData = function()
    local out = {}; local wd = _G.HazeHUB.WorldData
    for _, e in ipairs(wd.Story) do
        if not out[e.worldId] then out[e.worldId]={story={},ranger={}} end
        table.insert(out[e.worldId].story, e.name)
    end
    for _, e in ipairs(wd.Ranger) do
        if not out[e.worldId] then out[e.worldId]={story={},ranger={}} end
        table.insert(out[e.worldId].ranger, e.name)
    end
    return out
end
HS.GetWorldIds = function()
    local ids, seen = {}, {}
    local wd = _G.HazeHUB.WorldData
    for _, e in ipairs(wd.Story)  do if not seen[e.worldId] then seen[e.worldId]=true; table.insert(ids,e.worldId) end end
    for _, e in ipairs(wd.Ranger) do if not seen[e.worldId] then seen[e.worldId]=true; table.insert(ids,e.worldId) end end
    return ids
end

HS.SetModuleLoaded(VERSION)
pcall(function()
    for _, gui in ipairs(Container:GetDescendants()) do
        if gui:IsA("GuiObject") then gui.ZIndex = 1 end
    end
end)
print(string.format("[HazeHub] autofarm.lua v%s geladen | Spieler: %s | DB: %d Chapters | WorldData: Story=%d Ranger=%d Cal=%d Raid=%d",
    VERSION, LP.Name, DBCount(),
    #_G.HazeHUB.WorldData.Story,
    #_G.HazeHUB.WorldData.Ranger,
    #_G.HazeHUB.WorldData.Calamity,
    #_G.HazeHUB.WorldData.Raid))
