-- ╔══════════════════════════════════════════════════════════╗
--  HazeHUB – autofarm.lua  v1.6.0
--  GitHub: Hazeluxeeeees/HazeHub-Modules
--  NEU: Location-Check (Lobby vs. Game), Anti-AFK v2,
--       sicherer Lobby-Return, Persistenz-Fix, Debug-Logs
-- ╚══════════════════════════════════════════════════════════╝

local VERSION = "1.6.0"

-- ============================================================
--  WARTEN BIS SHARED-TABLE BEREIT  (max. 10s)
-- ============================================================
local waited = 0
while not (_G.HazeShared and _G.HazeShared.Container and _G.HazeShared.SetModuleLoaded) do
    task.wait(0.3); waited = waited + 0.3
    if waited >= 10 then
        warn("[HazeHub] _G.HazeShared nicht bereit – Abbruch.")
        return
    end
end

-- ============================================================
--  SHARED ALIASE
-- ============================================================
local HS  = _G.HazeShared
local CFG = HS.Config
local ST  = HS.State
local D   = HS.D
local TF  = HS.TF; local TM = HS.TM; local Tw = HS.Tw
local Svc = HS.Svc

local Card    = HS.Card;    local NeonBtn = HS.NeonBtn
local MkLbl   = HS.MkLbl;  local SecLbl  = HS.SecLbl
local MkInput = HS.MkInput; local VList   = HS.VList
local HList   = HS.HList;   local Pad     = HS.Pad
local Corner  = HS.Corner;  local Stroke  = HS.Stroke

local PR               = HS.PR
local IsInLobby        = HS.IsInLobby
local SaveConfig       = HS.SaveConfig
local SendWebhook      = HS.SendWebhook

local Container = HS.Container

-- ============================================================
--  SERVICES
-- ============================================================
local VIM         = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local LP          = game:GetService("Players").LocalPlayer
local RS          = game:GetService("ReplicatedStorage")
local Players     = game:GetService("Players")

-- ============================================================
--  ★ ANTI-AFK  (verhindert Kick nach 20 Minuten Inaktivität)
-- ============================================================
LP.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
    print("[HazeHub] Anti-AFK: Idle-Event abgefangen – Controller simuliert.")
end)

-- Zusätzliches Anti-AFK alle 8 Minuten (Backup)
task.spawn(function()
    while true do
        task.wait(480)  -- 8 Minuten
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
        print("[HazeHub] Anti-AFK: Periodischer Heartbeat (8min).")
    end
end)

-- ============================================================
--  REMOTES
-- ============================================================
local REM = {}
task.spawn(function()
    pcall(function()
        REM.PlayRoomEvent = RS
            :WaitForChild("Remote",   10)
            :WaitForChild("Server",   10)
            :WaitForChild("PlayRoom", 10)
            :WaitForChild("Event",    10)
    end)
    pcall(function()
        REM.VoteRetry = RS
            :WaitForChild("Remote",    10)
            :WaitForChild("Server",    10)
            :WaitForChild("OnGame",    10)
            :WaitForChild("Voting",    10)
            :WaitForChild("VoteRetry", 10)
    end)
end)

local function Fire(action, data)
    local ok = false
    if REM.PlayRoomEvent then
        ok = pcall(function()
            if data then REM.PlayRoomEvent:FireServer(action, data)
            else         REM.PlayRoomEvent:FireServer(action) end
        end)
    end
    if not ok then PR(action, data) end
end

-- ============================================================
--  DATEI-KONSTANTEN
-- ============================================================
local FOLDER     = "HazeHUB"
local DB_FILE    = "HazeHUB/HazeHUB_RewardDB.json"
local QUEUE_FILE = "HazeHUB/HazeHUB_Queue.json"
local STATE_FILE = "HazeHUB/HazeHUB_State.json"   -- ★ Umbenennung von FarmState

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
    UI             = { Lbl={}, Fr={}, Btn={} },
}

_G.AutoFarmRunning = false

-- ============================================================
--  UTIL
-- ============================================================
local function DBCount()
    local c = 0; for _ in pairs(AF.RewardDatabase) do c = c + 1 end; return c
end

local function SetMainStatus(text, color)
    pcall(function()
        local ml = LP.PlayerGui:FindFirstChild("ModulStatus", true)
        if ml and ml:IsA("TextLabel") then
            ml.Text = text; ml.TextColor3 = color or D.TextMid
        end
    end)
end

local function SetStatus(text, color)
    pcall(function()
        AF.UI.Lbl.Status.Text       = text
        AF.UI.Lbl.Status.TextColor3 = color or D.TextMid
    end)
    SetMainStatus(text, color)
end

-- ============================================================
--  ★ LOCATION-CHECK  (Lobby vs. Game)
-- ============================================================
-- Gibt true zurück wenn wir in der Lobby sind
-- Methode 1: PlayRoom GUI sichtbar/aktiv
-- Methode 2: IsInLobby() vom Hauptskript
-- Methode 3: game.PlaceId Check (falls Lobby eigene PlaceId hat)
local LOBBY_PLACE_IDS = {}   -- optional: trage hier Lobby-PlaceIds ein

local function CheckIsLobby()
    -- Methode 1: PlayRoom GUI nicht aktiv = Lobby
    local prGui = LP.PlayerGui:FindFirstChild("PlayRoom")
    if prGui then
        if not prGui.Enabled then return true end  -- PlayRoom GUI existiert aber deaktiviert = Lobby
    else
        return true  -- kein PlayRoom GUI = Lobby
    end

    -- Methode 2: Shared IsInLobby Funktion
    local sharedLobby = false
    pcall(function() sharedLobby = IsInLobby() end)
    if sharedLobby then return true end

    -- Methode 3: PlaceId Check (falls konfiguriert)
    if #LOBBY_PLACE_IDS > 0 then
        local pid = game.PlaceId
        for _, lid in ipairs(LOBBY_PLACE_IDS) do
            if pid == lid then return true end
        end
        return false  -- Wir sind in einer bekannten Nicht-Lobby PlaceId
    end

    -- Default: PlayRoom aktiv = im Spiel
    return false
end

-- ============================================================
--  INVENTAR  (Live-Wert aus ReplicatedStorage)
-- ============================================================
local function GetLiveInvAmt(itemName)
    local n = 0
    pcall(function()
        local f = RS:WaitForChild("Player_Data", 3)
            :WaitForChild(LP.Name, 3)
            :WaitForChild("Items", 3)
        local item = f:FindFirstChild(itemName)
        if not item then return end
        local vc = item:FindFirstChild("Value") or item:FindFirstChild("Amount")
        if vc then n = tonumber(vc.Value) or 0
        elseif item:IsA("IntValue") or item:IsA("NumberValue") then n = tonumber(item.Value) or 0 end
    end)
    return n
end

-- ============================================================
--  ★ SICHERER LOBBY-RETURN
--  Prüft erst ob das Ziel tatsächlich im Inventar erreicht ist,
--  bevor "Back To Lobby" ausgeführt wird.
-- ============================================================
local function SafeReturnToLobby(itemName, targetAmount)
    -- Schritt 1: Sicherheits-Check – ist das Ziel wirklich erreicht?
    local cur = GetLiveInvAmt(itemName)
    if cur < targetAmount then
        warn(string.format("[HazeHub] SafeReturnToLobby: Ziel NICHT erreicht (%s: %d/%d) – Abbruch.",
            itemName, cur, targetAmount))
        return false
    end

    print(string.format("[HazeHub] SafeReturnToLobby: Ziel bestätigt (%s: %d/%d) – kehre zur Lobby zurück.",
        itemName, cur, targetAmount))

    -- Schritt 2: Versuche "Back To Lobby" Button über getconnections
    local btnClicked = false
    pcall(function()
        local btn = LP.PlayerGui
            :WaitForChild("Settings", 3)
            :WaitForChild("Main",     3)
            :WaitForChild("Base",     3)
            :WaitForChild("Space",    3)
            :WaitForChild("ScrollingFrame", 3)
            :WaitForChild("Back To Lobby",  3)
        if btn then
            -- getconnections (Exploit-API) – feuert alle Connected-Callbacks
            local conns = nil
            pcall(function() conns = getconnections(btn.MouseButton1Click) end)
            if conns and #conns > 0 then
                for _, conn in ipairs(conns) do
                    pcall(function() conn:Fire() end)
                end
                btnClicked = true
                print("[HazeHub] SafeReturnToLobby: getconnections erfolgreich gefeuert.")
            else
                -- Fallback: direktes Fire
                btn.MouseButton1Click:Fire()
                btnClicked = true
                print("[HazeHub] SafeReturnToLobby: MouseButton1Click:Fire() Fallback.")
            end
        end
    end)

    -- Schritt 3: Fallback via Remote
    if not btnClicked then
        pcall(function() Fire("Leave") end)
        pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end)
        print("[HazeHub] SafeReturnToLobby: Remote/Teleport-Fallback.")
    end

    return true
end

-- ============================================================
--  PERSISTENZ: STATE FILE  (AutoFarmRunning)
-- ============================================================
local function SaveState()
    if not writefile then return end
    pcall(function()
        writefile(STATE_FILE, Svc.Http:JSONEncode({
            running = _G.AutoFarmRunning,
            version = VERSION,
            ts      = os.time(),
        }))
    end)
    print("[HazeHub] State gespeichert: AutoFarmRunning=" .. tostring(_G.AutoFarmRunning))
end

local function LoadState()
    if not (isfile and isfile(STATE_FILE)) then return end
    local raw; pcall(function() raw = readfile(STATE_FILE) end)
    if not raw or #raw < 5 then return end
    local ok, data = pcall(function() return Svc.Http:JSONDecode(raw) end)
    if not ok or type(data) ~= "table" then return end
    _G.AutoFarmRunning = data.running == true
    print("[HazeHub] State geladen: AutoFarmRunning=" .. tostring(_G.AutoFarmRunning))
end

-- ============================================================
--  PERSISTENZ: QUEUE FILE
-- ============================================================
local function SaveQueueFile()
    if not writefile then return end
    pcall(function()
        local out = {}
        for _, q in ipairs(AF.Queue) do
            if not q.done then
                table.insert(out, {item=q.item, amount=q.amount})
            end
        end
        writefile(QUEUE_FILE, Svc.Http:JSONEncode(out))
        print(string.format("[HazeHub] Queue gespeichert: %d Items.", #out))
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
            table.insert(AF.Queue, {item=q.item, amount=tonumber(q.amount), done=false})
        end
    end
    print(string.format("[HazeHub] Queue geladen: %d Items aus %s.", #AF.Queue, QUEUE_FILE))
    return #AF.Queue > 0
end

local function RemoveFromQueue(itemName)
    for i = #AF.Queue, 1, -1 do
        if AF.Queue[i].item == itemName then
            table.remove(AF.Queue, i)
        end
    end
    SaveQueueFile()
    print(string.format("[HazeHub] '%s' aus Queue entfernt.", itemName))
end

-- ============================================================
--  INVENTAR-SYNC
-- ============================================================
local function SyncInventoryWithQueue()
    local changed = false
    for i = #AF.Queue, 1, -1 do
        local q = AF.Queue[i]
        if not q.done then
            local cur = GetLiveInvAmt(q.item)
            if cur >= q.amount then
                print(string.format("[HazeHub] Sync: '%s' bereits erreicht (%d/%d) – entfernt.",
                    q.item, cur, q.amount))
                table.remove(AF.Queue, i)
                changed = true
            end
        end
    end
    if changed then SaveQueueFile() end
    return changed
end

-- ============================================================
--  DB SAVE / LOAD
-- ============================================================
local function SaveDB()
    if not writefile then return end
    pcall(function()
        writefile(DB_FILE, Svc.Http:JSONEncode(AF.RewardDatabase))
        print("[HazeHub] DB gespeichert: " .. DBCount() .. " Chapters.")
    end)
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
    print("[HazeHub] DB geladen: " .. c .. " Chapters.")
    return true
end

local function ClearDB()
    AF.RewardDatabase = {}
    if writefile then pcall(function() writefile(DB_FILE, "{}") end) end
end

-- ============================================================
--  SCAN-HELFER
-- ============================================================
local function SetScanProgress(current, total, label)
    local pct = math.max(0, math.min(1, current / math.max(1, total)))
    local txt = string.format("%s  (%d/%d – %.0f%%)", label, current, total, pct * 100)
    pcall(function()
        AF.UI.Lbl.ScanProgress.Text       = txt
        AF.UI.Lbl.ScanProgress.TextColor3 = D.Yellow
        AF.UI.Fr.ScanBar.Visible          = true
        Tw(AF.UI.Fr.ScanBarFill, {Size = UDim2.new(pct, 0, 1, 0)}, TF)
    end)
    SetMainStatus(txt, D.Yellow)
end

local function GetItemsList(timeoutSec)
    local result = nil
    local deadline = os.clock() + (timeoutSec or 4)
    while os.clock() < deadline do
        pcall(function()
            result = LP.PlayerGui
                :WaitForChild("PlayRoom",  1)
                :WaitForChild("Main",      1)
                :WaitForChild("GameStage", 1)
                :WaitForChild("Main",      1)
                :WaitForChild("Base",      1)
                :WaitForChild("Rewards",   1)
                :WaitForChild("ItemsList", 1)
        end)
        if result and result.Parent then break end
        result = nil; task.wait(0.2)
    end
    return result
end

local function WaitForItems(itemsList, timeoutSec)
    if not itemsList then return false end
    timeoutSec = timeoutSec or 3
    if #itemsList:GetChildren() > 0 then return true end
    local filled = false
    local conn = itemsList.ChildAdded:Connect(function() filled = true end)
    local deadline = os.clock() + timeoutSec
    while os.clock() < deadline and not filled do
        if #itemsList:GetChildren() > 0 then filled = true; break end
        task.wait(0.15)
    end
    pcall(function() conn:Disconnect() end)
    return filled
end

local function ParseItems(itemsList)
    local items = {}
    if not itemsList then return items end
    for _, frame in ipairs(itemsList:GetChildren()) do
        pcall(function()
            local inf = frame:FindFirstChild("Info")
            if inf then
                local nameV = inf:FindFirstChild("ItemNames")
                local rateV = inf:FindFirstChild("DropRate")
                local amtV  = inf:FindFirstChild("DropAmount")
                local iname = nameV and tostring(nameV.Value) or ""
                local rate  = rateV and tonumber(rateV.Value) or 0
                local amt   = amtV  and tonumber(amtV.Value)  or 1
                if iname ~= "" then items[iname] = {dropRate=rate, dropAmount=amt} end
            else
                local nameV = frame:FindFirstChild("ItemNames")
                local rateV = frame:FindFirstChild("DropRate")
                local amtV  = frame:FindFirstChild("DropAmount")
                local iname = nameV and tostring(nameV.Value) or frame.Name
                local rate  = rateV and tonumber(rateV.Value) or 0
                local amt   = amtV  and tonumber(amtV.Value)  or 1
                if iname ~= "" and iname ~= frame.ClassName then
                    items[iname] = {dropRate=rate, dropAmount=amt}
                end
            end
        end)
    end
    return items
end

local function GetChapterBase()
    local f = nil
    pcall(function()
        f = LP.PlayerGui
            :WaitForChild("PlayRoom",  5):WaitForChild("Main",      5)
            :WaitForChild("GameStage", 5):WaitForChild("Main",      5)
            :WaitForChild("Base",      5):WaitForChild("Chapter",   5)
    end)
    return f
end

local function ClickChapterButton(chapBase, worldId, chapId)
    if not chapBase then return false end
    local btn = nil
    pcall(function()
        local wf = chapBase:FindFirstChild(worldId)
        if wf then btn = wf:FindFirstChild(chapId) end
    end)
    if not btn then pcall(function() btn = chapBase:FindFirstChild(chapId, true) end) end
    if not btn then return false end
    pcall(function() btn.MouseButton1Click:Fire() end)
    pcall(function()
        local ap = btn.AbsolutePosition + btn.AbsoluteSize * 0.5
        VIM:SendMouseButtonEvent(ap.X, ap.Y, 0, true,  game, 0); task.wait(0.06)
        VIM:SendMouseButtonEvent(ap.X, ap.Y, 0, false, game, 0)
    end)
    return true
end

local function ClearItemsList(itemsList)
    if not itemsList then return end
    pcall(function()
        for _, child in ipairs(itemsList:GetChildren()) do child:Destroy() end
    end)
end

-- ============================================================
--  SCAN-FUNKTION
-- ============================================================
local function ScanAllRewards(onProgress)
    if AF.Scanning then return false end
    if not HS.IsScanDone() then
        pcall(function() onProgress("X Weltdaten fehlen.") end); return false
    end
    AF.Scanning = true; AF.RewardDatabase = {}
    local WorldData = HS.GetWorldData()
    local WorldIds  = HS.GetWorldIds()
    local tasks = {}
    for _, wid in ipairs(WorldIds) do
        local wd = WorldData[wid] or {}
        local isCal = wid:lower():find("calamity") ~= nil
        for _, cid in ipairs(wd.story  or {}) do table.insert(tasks,{worldId=wid,chapId=cid,mode=isCal and "Calamity" or "Story"}) end
        for _, cid in ipairs(wd.ranger or {}) do table.insert(tasks,{worldId=wid,chapId=cid,mode="Ranger"}) end
    end
    local total,scanned,failed = #tasks,0,0
    if total == 0 then AF.Scanning=false; return false end
    local chapBase = GetChapterBase()
    Fire("Create"); task.wait(0.8)
    local itemsList = GetItemsList(5)
    for _, t in ipairs(tasks) do
        if not AF.Scanning then break end
        scanned = scanned + 1
        SetScanProgress(scanned, total, string.format("Scanne: %s %s", t.worldId, t.chapId))
        pcall(function() onProgress(string.format("Scanne %d/%d: %s %s", scanned, total, t.worldId, t.chapId)) end)
        print(string.format("[HazeHub] Scanne Welt: %s... (Chapter: %s, %d/%d)", t.worldId, t.chapId, scanned, total))
        if not itemsList or not itemsList.Parent then
            Fire("Create"); task.wait(0.8); itemsList = GetItemsList(4)
        end
        ClearItemsList(itemsList); task.wait(0.1)
        pcall(function()
            if     t.mode=="Story"    then Fire("Change-World",{World=t.worldId})
            elseif t.mode=="Ranger"   then Fire("Change-Mode",{KeepWorld=t.worldId,Mode="Ranger Stage"})
            elseif t.mode=="Calamity" then Fire("Change-Mode",{Mode="Calamity"}) end
        end)
        task.wait(0.25)
        Fire("Change-Chapter",{Chapter=t.chapId}); task.wait(0.25)
        if chapBase then ClickChapterButton(chapBase, t.worldId, t.chapId) end
        if not itemsList or not itemsList.Parent then itemsList = GetItemsList(3) end
        local got = WaitForItems(itemsList, 3)
        if got and itemsList then
            local items = ParseItems(itemsList)
            local cnt = 0; for _ in pairs(items) do cnt=cnt+1 end
            if cnt > 0 then
                AF.RewardDatabase[t.chapId] = {world=t.worldId, mode=t.mode, items=items}
                for iname,idata in pairs(items) do
                    print(string.format("[HazeHub] Gefunden: %s in %s %s (Rate: %.1f%%)",
                        iname, t.worldId, t.chapId, idata.dropRate or 0))
                end
            else failed=failed+1 end
        else
            failed=failed+1
            warn(string.format("[HazeHub] TIMEOUT: %s", t.chapId))
        end
        pcall(function() Fire("Submit"); task.wait(0.15); Fire("Create"); task.wait(0.3) end)
        task.wait(0.2)
    end
    if DBCount() > 0 then SaveDB() end
    AF.Scanning = false
    local c = DBCount()
    local ok = c > 0
    local msg = string.format("%s Scan: %d/%d (%d Timeouts)", ok and "OK" or "X", c, total, failed)
    print("[HazeHub] " .. msg)
    pcall(function() onProgress(msg) end)
    pcall(function()
        AF.UI.Lbl.ScanProgress.Text       = msg
        AF.UI.Lbl.ScanProgress.TextColor3 = ok and D.Green or D.Orange
        Tw(AF.UI.Fr.ScanBarFill,{Size=UDim2.new(ok and 1 or 0,0,1,0),BackgroundColor3=ok and D.Green or D.Orange},TM)
        AF.UI.Lbl.DBStatus.Text       = msg
        AF.UI.Lbl.DBStatus.TextColor3 = ok and D.Green or D.Orange
        AF.UI.Btn.ForceRescan.Text    = "DATENBANK NEU SCANNEN"
        AF.UI.Btn.ForceRescan.TextColor3 = Color3.new(1,1,1)
    end)
    return ok
end

-- ============================================================
--  BESTES CHAPTER
-- ============================================================
local function FindBestChapter(itemName)
    local best,bestRate,bestWorld,bestMode = nil,-1,nil,nil
    for chapId,data in pairs(AF.RewardDatabase) do
        if data.items and data.items[itemName] then
            local r = data.items[itemName].dropRate or 0
            if r > bestRate then bestRate=r; best=chapId; bestWorld=data.world; bestMode=data.mode end
        end
    end
    if best then
        print(string.format("[HazeHub] Ziel-Item: %s  Welt: %s  Kapitel: %s  (%.1f%%)",
            itemName, bestWorld, best, bestRate))
    else
        warn(string.format("[HazeHub] '%s' nicht in DB.", itemName))
    end
    return best, bestWorld, bestMode, bestRate
end

-- ============================================================
--  RAUM STARTEN  (nur aus der Lobby aufrufen!)
-- ============================================================
local function FireRoomSequence(worldId, mode, chapId)
    print(string.format("[HazeHub] Erstelle Raum: %s | %s | %s", worldId, mode, chapId))
    task.spawn(function()
        pcall(function()
            Fire("Create");                                         task.wait(0.35)
            if     mode=="Story"    then Fire("Change-World",{World=worldId})
            elseif mode=="Ranger"   then Fire("Change-Mode",{KeepWorld=worldId,Mode="Ranger Stage"})
            elseif mode=="Calamity" then Fire("Change-Mode",{Mode="Calamity"}) end
                                                                    task.wait(0.35)
            Fire("Change-Chapter",{Chapter=chapId});                task.wait(0.35)
            Fire("Submit");                                         task.wait(0.5)
            Fire("Start")
            print("[HazeHub] Raum gestartet.")
        end)
    end)
end

-- ============================================================
--  QUEUE UI
-- ============================================================
local UpdateQueueUI

UpdateQueueUI = function()
    if not AF.UI.Fr.List then return end
    for _, v in pairs(AF.UI.Fr.List:GetChildren()) do
        if v:IsA("Frame") then v:Destroy() end
    end
    if AF.UI.Lbl.QueueEmpty then
        local visible = true
        for _, q in ipairs(AF.Queue) do if not q.done then visible=false; break end end
        AF.UI.Lbl.QueueEmpty.Visible = visible
    end

    local function NextItem()
        for _, q in ipairs(AF.Queue) do if not q.done then return q end end
        return nil
    end

    for i, q in ipairs(AF.Queue) do
        if q.done then continue end
        local inv    = GetLiveInvAmt(q.item)
        local pct    = math.min(1, inv / math.max(1, q.amount))
        local isNext = NextItem() == q

        local row = Instance.new("Frame", AF.UI.Fr.List)
        row.Size=UDim2.new(1,0,0,44); row.BorderSizePixel=0; Corner(row,8)
        if isNext then row.BackgroundColor3=Color3.fromRGB(0,30,55); Stroke(row,D.Cyan,1.5,0)
        else           row.BackgroundColor3=D.Card;                  Stroke(row,D.Border,1,0.4) end

        local barC = isNext and D.Cyan or D.Purple
        local bar = Instance.new("Frame",row)
        bar.Size=UDim2.new(0,3,0.65,0); bar.Position=UDim2.new(0,0,0.175,0)
        bar.BackgroundColor3=barC; bar.BorderSizePixel=0; Corner(bar,2)
        local pgBg = Instance.new("Frame",row)
        pgBg.Size=UDim2.new(1,-52,0,3); pgBg.Position=UDim2.new(0,8,1,-6)
        pgBg.BackgroundColor3=Color3.fromRGB(28,38,62); pgBg.BorderSizePixel=0; Corner(pgBg,2)
        local pgF = Instance.new("Frame",pgBg)
        pgF.Size=UDim2.new(pct,0,1,0); pgF.BackgroundColor3=barC; pgF.BorderSizePixel=0; Corner(pgF,2)

        local nL = Instance.new("TextLabel",row)
        nL.Position=UDim2.new(0,12,0,5); nL.Size=UDim2.new(1,-52,0.5,-3)
        nL.BackgroundTransparency=1
        nL.Text=(isNext and ">> " or "")..q.item
        nL.TextColor3=isNext and D.Cyan or D.TextHi
        nL.TextSize=11; nL.Font=Enum.Font.GothamBold
        nL.TextXAlignment=Enum.TextXAlignment.Left; nL.TextTruncate=Enum.TextTruncate.AtEnd

        local pL = Instance.new("TextLabel",row)
        pL.Position=UDim2.new(0,12,0.5,1); pL.Size=UDim2.new(1,-52,0.5,-5)
        pL.BackgroundTransparency=1
        pL.Text=string.format("%d / %d  (%.0f%%)", inv, q.amount, pct*100)
        pL.TextColor3=D.TextMid; pL.TextSize=10; pL.Font=Enum.Font.GothamSemibold
        pL.TextXAlignment=Enum.TextXAlignment.Left

        local ci = i
        local xBtn = Instance.new("TextButton",row)
        xBtn.Size=UDim2.new(0,34,0,34); xBtn.Position=UDim2.new(1,-38,0.5,-17)
        xBtn.BackgroundColor3=Color3.fromRGB(50,12,12); xBtn.Text="X"
        xBtn.TextColor3=D.Red; xBtn.TextSize=13; xBtn.Font=Enum.Font.GothamBold
        xBtn.AutoButtonColor=false; xBtn.BorderSizePixel=0; Corner(xBtn,7); Stroke(xBtn,D.Red,1,0.4)
        xBtn.MouseEnter:Connect(function() Tw(xBtn,{BackgroundColor3=D.RedDark}) end)
        xBtn.MouseLeave:Connect(function() Tw(xBtn,{BackgroundColor3=Color3.fromRGB(50,12,12)}) end)
        xBtn.MouseButton1Click:Connect(function()
            if AF.Queue[ci] then
                local name = AF.Queue[ci].item
                table.remove(AF.Queue, ci)
                SaveQueueFile()
                print("[HazeHub] Manuell entfernt: " .. name)
            end
            UpdateQueueUI()
        end)
    end
end

-- ============================================================
--  ★ HAUPT-FARM-LOGIK  (Lobby vs. Game getrennt)
-- ============================================================

-- GAME-MODUS: Nur Inventar überwachen, keine Remotes feuern
local function GameMonitorLoop(q)
    print("[HazeHub] Ort erkannt: GAME. Ueberwachungskurs aktiv...")
    SetStatus(string.format("IM SPIEL – ueberwache: %s", q.item), D.TextMid)

    local deadline = os.time() + 600
    while AF.Running and os.time() < deadline do
        -- ★ CHECKPOINT: Lobby-Return wenn fertig
        if CheckIsLobby() then
            print("[HazeHub] Server-Wechsel erkannt: nun in Lobby.")
            break
        end

        task.wait(5)
        local cur = GetLiveInvAmt(q.item)
        SetStatus(string.format("SPIEL: %s  %d/%d  (%.0f%%)",
            q.item, cur, q.amount, math.min(100, cur/math.max(1,q.amount)*100)), D.Cyan)
        pcall(UpdateQueueUI)
        pcall(function() HS.UpdateGoalsUI() end)

        -- Ziel erreicht?
        if cur >= q.amount then
            print(string.format("[HazeHub] Ziel im Spiel erreicht: %s (%d/%d)", q.item, cur, q.amount))
            task.spawn(function() pcall(function() SendWebhook({}, q.item, cur) end) end)

            -- Item aus Queue entfernen
            RemoveFromQueue(q.item)
            pcall(UpdateQueueUI)
            SetStatus(string.format("Ziel erreicht! %s – kehre zur Lobby zurueck...", q.item), D.Green)

            -- Kurz warten, dann sicherer Lobby-Return
            task.wait(2)
            SafeReturnToLobby(q.item, q.amount)

            -- Warten bis Lobby
            local lw = 0
            while AF.Running and not CheckIsLobby() and lw < 20 do
                task.wait(1); lw = lw + 1
            end
            return true  -- Ziel erreicht
        end
    end
    return false  -- Timeout oder Lobby-Switch
end

-- LOBBY-MODUS: Queue prüfen und Raum starten
local function LobbyActionLoop()
    print("[HazeHub] Ort erkannt: LOBBY. Pruefe Queue...")
    SetStatus("LOBBY: Pruefe Queue...", D.Yellow)

    -- Inventar-Sync: bereits erreichte Items entfernen
    local changed = SyncInventoryWithQueue()
    if changed then
        pcall(UpdateQueueUI)
        print("[HazeHub] Lobby-Sync: Queue bereinigt.")
    end

    local function GetNextItem()
        for _, q in ipairs(AF.Queue) do if not q.done then return q end end
        return nil
    end

    local q = GetNextItem()
    if not q then
        SetStatus("Queue leer – Farm beendet.", D.Green)
        print("[HazeHub] Queue leer. Farm-Loop beendet.")
        AF.Active          = false
        _G.AutoFarmRunning = false
        SaveState()
        return false
    end

    -- Bestes Chapter finden
    local chapId, worldId, mode, rate = FindBestChapter(q.item)
    if not chapId then
        -- Fallback: erstes Chapter in DB
        for cid,data in pairs(AF.RewardDatabase) do
            chapId=cid; worldId=data.world; mode=data.mode; rate=0; break
        end
    end
    if not chapId then
        -- Letzter Fallback: WorldIds
        local ids = HS.GetWorldIds()
        if #ids > 0 then
            local wd = HS.GetWorldData()[ids[1]] or {}
            if wd.story and #wd.story > 0 then
                chapId=wd.story[1]; worldId=ids[1]; mode="Story"; rate=0
            end
        end
    end
    if not chapId then
        SetStatus("Kein Level fuer '"..q.item.."'", D.Orange)
        warn("[HazeHub] Kein Chapter – Item entfernt.")
        RemoveFromQueue(q.item); pcall(UpdateQueueUI); return true
    end

    -- Raum erstellen und starten
    SetStatus(string.format("LOBBY: Erstelle %s -> %s  (%.1f%%)", q.item, chapId, rate or 0), D.Cyan)
    FireRoomSequence(worldId, mode, chapId)

    -- Warten bis Spielstart (max 30s)
    local waitStart = os.time()
    while AF.Running and CheckIsLobby() and os.time()-waitStart < 30 do
        task.wait(2)
    end
    return true
end

-- HAUPT-LOOP
local function FarmLoop()
    AF.Active          = true
    _G.AutoFarmRunning = true
    SaveState()
    print("[HazeHub] === FARM LOOP GESTARTET ===")

    while AF.Running do
        local isLobby = CheckIsLobby()

        if isLobby then
            -- Lobby-Modus
            local continue_ = LobbyActionLoop()
            if not continue_ then break end  -- Queue leer
            -- Nach Raum-Start: warten bis im Spiel
            local ws = os.time()
            while AF.Running and CheckIsLobby() and os.time()-ws < 30 do
                task.wait(2)
            end
            task.wait(1)
        else
            -- Game-Modus: nur überwachen
            local function GetNextItem()
                for _, q in ipairs(AF.Queue) do if not q.done then return q end end
                return nil
            end
            local q = GetNextItem()
            if not q then
                -- Keine Items mehr – in Lobby wechseln
                print("[HazeHub] Queue leer im Spiel – kehre zur Lobby.")
                SafeReturnToLobby("", 0)  -- kein Inventar-Check nötig, Queue leer
                task.wait(5); break
            end
            GameMonitorLoop(q)
            -- Nach GameMonitorLoop kurze Pause
            task.wait(3)
        end
    end

    AF.Active = false
    if not AF.Running then
        _G.AutoFarmRunning = false
        SaveState()
    end
    print("[HazeHub] Farm-Loop beendet.")
end

-- ============================================================
--  STOP
-- ============================================================
local function StopFarm()
    AF.Active          = false
    AF.Running         = false
    AF.Scanning        = false
    _G.AutoFarmRunning = false
    SaveState()   -- ★ AUS-Status sofort in Datei schreiben
    SetStatus("Gestoppt.", D.TextMid)
    print("[HazeHub] Auto-Farm gestoppt. State gespeichert (AUS).")
end
HS.StopFarm = StopFarm

-- ============================================================
--  SCAN-TASK
-- ============================================================
local function RunScanTask(forceDelete, thenStartFarm)
    if AF.Scanning then SetStatus("Scan laeuft!", D.Yellow); return end
    task.spawn(function()
        if forceDelete then ClearDB() end
        pcall(function()
            AF.UI.Fr.ScanBar.Visible              = true
            AF.UI.Fr.ScanBarFill.Size             = UDim2.new(0,0,1,0)
            AF.UI.Fr.ScanBarFill.BackgroundColor3 = D.Purple
            AF.UI.Lbl.ScanProgress.Text           = "Scan startet..."
            AF.UI.Lbl.ScanProgress.TextColor3     = D.Yellow
            AF.UI.Btn.ForceRescan.Text            = "Scannt..."
            AF.UI.Btn.ForceRescan.TextColor3      = D.Yellow
        end)
        SetStatus("Scan laeuft...", D.Purple)
        local ok = ScanAllRewards(function(msg)
            pcall(function()
                AF.UI.Lbl.DBStatus.Text       = msg
                AF.UI.Lbl.DBStatus.TextColor3 = D.Yellow
            end)
        end)
        pcall(function()
            AF.UI.Btn.ForceRescan.Text       = "DATENBANK NEU SCANNEN"
            AF.UI.Btn.ForceRescan.TextColor3 = Color3.new(1,1,1)
        end)
        if thenStartFarm and ok and DBCount()>0 and AF.Running and not AF.Active then
            local function nxt()
                for _,q in ipairs(AF.Queue) do if not q.done then return q end end
            end
            if nxt() then task.spawn(FarmLoop) end
        end
    end)
end

-- ============================================================
--  ★ AUTO-RESUME  (nach Server-Wechsel / Reload)
-- ============================================================
local function TryAutoResume()
    task.wait(3)   -- kurz warten bis Spiel-Services bereit

    -- Dateien laden
    local hasQueue = LoadQueueFile()
    LoadState()   -- lädt _G.AutoFarmRunning

    -- Inventar-Sync
    if hasQueue then
        SyncInventoryWithQueue()
        pcall(UpdateQueueUI)
    end

    -- ★ Ort erkennen
    local isLobby = CheckIsLobby()
    if isLobby then
        print("[HazeHub] Ort erkannt: LOBBY. Pruefe Queue...")
    else
        print("[HazeHub] Ort erkannt: GAME. Ueberwachungskurs aktiv...")
    end

    -- AutoFarmRunning=false → NICHT starten (User hat manuell gestoppt)
    if not _G.AutoFarmRunning then
        print("[HazeHub] Auto-Resume: AutoFarmRunning=false – Farm bleibt gestoppt.")
        SetStatus(hasQueue and string.format("Queue: %d Items (Farm AUS)", #AF.Queue) or "Farm gestoppt.", D.TextMid)
        pcall(UpdateQueueUI)
        return
    end

    -- Keine Items → nicht starten
    local function nxt()
        for _,q in ipairs(AF.Queue) do if not q.done then return q end end
    end
    if not hasQueue or not nxt() then
        print("[HazeHub] Auto-Resume: Queue leer – Farm bleibt gestoppt.")
        _G.AutoFarmRunning = false
        SaveState()
        pcall(UpdateQueueUI)
        return
    end

    -- DB laden
    if DBCount() == 0 then LoadDB() end

    -- ★ AUTO-RESUME STARTEN
    SetStatus("Auto-Resume: Farm startet in 5s...", D.Yellow)
    print("[HazeHub] Auto-Resume: Starte in 5 Sekunden...")
    task.wait(5)

    if nxt() then
        AF.Running = true
        task.spawn(FarmLoop)
        print("[HazeHub] Auto-Resume: FarmLoop gestartet.")
    end

    pcall(UpdateQueueUI)
end

-- ============================================================
--  HINTERGRUND: Inventar-Sync alle 10s
-- ============================================================
task.spawn(function()
    while true do
        task.wait(10)
        if #AF.Queue > 0 then
            local changed = SyncInventoryWithQueue()
            if changed then pcall(UpdateQueueUI) end
        end
    end
end)

-- ============================================================
--  GUI AUFBAUEN
-- ============================================================

-- STATUS
local sCard = Card(Container, 36); Pad(sCard, 6, 10, 6, 10)
AF.UI.Lbl.Status = Instance.new("TextLabel", sCard)
AF.UI.Lbl.Status.Size               = UDim2.new(1,0,1,0)
AF.UI.Lbl.Status.BackgroundTransparency = 1
AF.UI.Lbl.Status.Text               = "Auto-Farm gestoppt"
AF.UI.Lbl.Status.TextColor3         = D.TextMid
AF.UI.Lbl.Status.TextSize           = 11
AF.UI.Lbl.Status.Font               = Enum.Font.GothamSemibold
AF.UI.Lbl.Status.TextXAlignment     = Enum.TextXAlignment.Left

-- LOCATION-INDIKATOR (klein, unter Status)
local locCard = Card(Container, 24); Pad(locCard, 2, 10, 2, 10)
local locLbl = Instance.new("TextLabel", locCard)
locLbl.Size=UDim2.new(1,0,1,0); locLbl.BackgroundTransparency=1
locLbl.Text="Ort: wird erkannt..."; locLbl.TextColor3=D.TextLow
locLbl.TextSize=10; locLbl.Font=Enum.Font.Gotham
locLbl.TextXAlignment=Enum.TextXAlignment.Left
-- Live-Ort-Update
task.spawn(function()
    while true do
        task.wait(3)
        pcall(function()
            local isLobby = CheckIsLobby()
            locLbl.Text = isLobby and "Ort: LOBBY" or "Ort: IM SPIEL"
            locLbl.TextColor3 = isLobby and D.Green or D.Orange
        end)
    end
end)

-- DB-KARTE
local dbCard = Card(Container); Pad(dbCard,10,10,10,10); VList(dbCard,7)
SecLbl(dbCard, "REWARD-DATENBANK")

AF.UI.Lbl.DBStatus = MkLbl(dbCard, "Keine DB geladen.", 11, D.TextLow)
AF.UI.Lbl.DBStatus.Size = UDim2.new(1,0,0,18)

local spLbl = Instance.new("TextLabel", dbCard)
spLbl.Size=UDim2.new(1,0,0,16); spLbl.BackgroundTransparency=1
spLbl.Text=""; spLbl.TextColor3=D.Yellow; spLbl.TextSize=10
spLbl.Font=Enum.Font.Gotham; spLbl.TextXAlignment=Enum.TextXAlignment.Left
spLbl.TextTruncate=Enum.TextTruncate.AtEnd
AF.UI.Lbl.ScanProgress = spLbl

local barBg = Instance.new("Frame", dbCard)
barBg.Size=UDim2.new(1,0,0,7); barBg.BackgroundColor3=Color3.fromRGB(18,26,48)
barBg.BorderSizePixel=0; barBg.Visible=false; Corner(barBg,3)
AF.UI.Fr.ScanBar = barBg
local barFill = Instance.new("Frame", barBg)
barFill.Size=UDim2.new(0,0,1,0); barFill.BackgroundColor3=D.Purple
barFill.BorderSizePixel=0; Corner(barFill,3)
AF.UI.Fr.ScanBarFill = barFill

local loadDbBtn = Instance.new("TextButton", dbCard)
loadDbBtn.Size=UDim2.new(1,0,0,28); loadDbBtn.BackgroundColor3=D.CardHover
loadDbBtn.Text="DB laden"; loadDbBtn.TextColor3=D.CyanDim
loadDbBtn.TextSize=11; loadDbBtn.Font=Enum.Font.GothamBold
loadDbBtn.AutoButtonColor=false; loadDbBtn.BorderSizePixel=0
Corner(loadDbBtn,7); Stroke(loadDbBtn,D.CyanDim,1,0.3)
loadDbBtn.MouseEnter:Connect(function() Tw(loadDbBtn,{BackgroundColor3=Color3.fromRGB(0,45,75)}) end)
loadDbBtn.MouseLeave:Connect(function() Tw(loadDbBtn,{BackgroundColor3=D.CardHover}) end)
loadDbBtn.MouseButton1Click:Connect(function()
    if LoadDB() then
        AF.UI.Lbl.DBStatus.Text=string.format("OK DB: %d Chapters", DBCount()); AF.UI.Lbl.DBStatus.TextColor3=D.Green
    else
        AF.UI.Lbl.DBStatus.Text="Keine gueltige DB."; AF.UI.Lbl.DBStatus.TextColor3=D.Orange
    end
end)

local forceBtn = Instance.new("TextButton", dbCard)
forceBtn.Size=UDim2.new(1,0,0,40); forceBtn.BackgroundColor3=Color3.fromRGB(68,10,108)
forceBtn.Text="DATENBANK NEU SCANNEN"; forceBtn.TextColor3=Color3.new(1,1,1)
forceBtn.TextSize=13; forceBtn.Font=Enum.Font.GothamBold
forceBtn.AutoButtonColor=false; forceBtn.BorderSizePixel=0
Corner(forceBtn,9); Stroke(forceBtn,Color3.fromRGB(180,80,255),2,0)
AF.UI.Btn.ForceRescan = forceBtn
forceBtn.MouseEnter:Connect(function()   Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(110,22,170)}) end)
forceBtn.MouseLeave:Connect(function()   Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(68,10,108)})  end)
forceBtn.MouseButton1Down:Connect(function() Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(40,5,72)}) end)
forceBtn.MouseButton1Up:Connect(function()   Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(110,22,170)}) end)
forceBtn.MouseButton1Click:Connect(function() RunScanTask(true, false) end)

-- QUEUE-KARTE
local qCard = Card(Container); Pad(qCard,10,10,10,10); VList(qCard,8)
SecLbl(qCard, "AUTO-FARM QUEUE")

local qFileInfo = MkLbl(qCard, "Keine gespeicherte Queue.", 10, D.TextLow)
qFileInfo.Size = UDim2.new(1,0,0,14)
AF.UI.Lbl.QueueFileInfo = qFileInfo

local qRow = Instance.new("Frame",qCard)
qRow.Size=UDim2.new(1,0,0,30); qRow.BackgroundTransparency=1; HList(qRow,5)
local qItemOuter,qItemBox = MkInput(qRow,"Item-Name..."); qItemOuter.Size=UDim2.new(0.50,0,0,30)
local qAmtOuter, qAmtBox  = MkInput(qRow,"Anzahl");       qAmtOuter.Size =UDim2.new(0.28,0,0,30)

local qAddBtn = Instance.new("TextButton",qRow)
qAddBtn.Size=UDim2.new(0.19,0,0,30); qAddBtn.BackgroundColor3=D.Green
qAddBtn.Text="+ Add"; qAddBtn.TextColor3=Color3.new(1,1,1); qAddBtn.TextSize=11
qAddBtn.Font=Enum.Font.GothamBold; qAddBtn.AutoButtonColor=false; qAddBtn.BorderSizePixel=0
Corner(qAddBtn,7); Stroke(qAddBtn,D.Green,1,0.2)
qAddBtn.MouseEnter:Connect(function() Tw(qAddBtn,{BackgroundColor3=Color3.fromRGB(0,160,80)}) end)
qAddBtn.MouseLeave:Connect(function() Tw(qAddBtn,{BackgroundColor3=D.Green}) end)

AF.UI.Fr.List = Instance.new("Frame",qCard)
AF.UI.Fr.List.Size=UDim2.new(1,0,0,0); AF.UI.Fr.List.AutomaticSize=Enum.AutomaticSize.Y
AF.UI.Fr.List.BackgroundTransparency=1; VList(AF.UI.Fr.List,4)
AF.UI.Lbl.QueueEmpty = MkLbl(AF.UI.Fr.List,"Queue leer.",11,D.TextLow)
AF.UI.Lbl.QueueEmpty.Size=UDim2.new(1,0,0,24)

qAddBtn.MouseButton1Click:Connect(function()
    local iname=(qItemBox.Text or ""):match("^%s*(.-)%s*$")
    local iamt=tonumber(qAmtBox.Text)
    if iname=="" or not iamt or iamt<=0 then return end
    local found=false
    for _,g in ipairs(ST.Goals) do if g.item==iname then found=true; break end end
    if not found then table.insert(ST.Goals,{item=iname,amount=iamt,reached=false}); SaveConfig() end
    local inQueue=false
    for _,q in ipairs(AF.Queue) do if q.item==iname then inQueue=true; break end end
    if not inQueue then
        table.insert(AF.Queue,{item=iname,amount=iamt,done=false})
        SaveQueueFile()
        print(string.format("[HazeHub] Queue: '%s' (x%d) gespeichert.", iname, iamt))
    end
    qItemBox.Text=""; qAmtBox.Text=""
    UpdateQueueUI(); pcall(function() HS.UpdateGoalsUI() end)
    pcall(function()
        AF.UI.Lbl.QueueFileInfo.Text="Queue: "..#AF.Queue.." Items gespeichert"
        AF.UI.Lbl.QueueFileInfo.TextColor3=D.Green
    end)
end)

-- STEUERUNG
local ctrlRow = Instance.new("Frame",qCard)
ctrlRow.Size=UDim2.new(1,0,0,32); ctrlRow.BackgroundTransparency=1; HList(ctrlRow,8)

local startBtn = Instance.new("TextButton",ctrlRow)
startBtn.Size=UDim2.new(0.48,0,0,32); startBtn.BackgroundColor3=D.Green
startBtn.Text="Start Queue"; startBtn.TextColor3=Color3.new(1,1,1)
startBtn.TextSize=12; startBtn.Font=Enum.Font.GothamBold
startBtn.AutoButtonColor=false; startBtn.BorderSizePixel=0
Corner(startBtn,8); Stroke(startBtn,D.Green,1,0.2)

local stopBtn = Instance.new("TextButton",ctrlRow)
stopBtn.Size=UDim2.new(0.48,0,0,32); stopBtn.BackgroundColor3=D.RedDark
stopBtn.Text="Stop"; stopBtn.TextColor3=D.Red
stopBtn.TextSize=12; stopBtn.Font=Enum.Font.GothamBold
stopBtn.AutoButtonColor=false; stopBtn.BorderSizePixel=0
Corner(stopBtn,8); Stroke(stopBtn,D.Red,1,0.4)

startBtn.MouseButton1Click:Connect(function()
    if AF.Active then SetStatus("Farm laeuft bereits!", D.Yellow); return end
    if #AF.Queue==0 then SetStatus("Queue ist leer!", D.Orange); return end
    AF.Running = true
    _G.AutoFarmRunning = true
    SaveState()  -- ★ AN-Status sofort schreiben
    if DBCount()==0 then
        SetStatus("DB leer – starte Scan...", D.Yellow)
        pcall(function()
            startBtn.Text="Scannt DB..."; startBtn.TextColor3=D.Yellow
        end)
        RunScanTask(false, true)
    else
        print(string.format("[HazeHub] Queue gestartet: %d Items, DB: %d Chapters.", #AF.Queue, DBCount()))
        task.spawn(FarmLoop)
    end
end)

stopBtn.MouseButton1Click:Connect(function()
    StopFarm()  -- ★ StopFarm schreibt AUS in Datei
    startBtn.Text="Start Queue"; startBtn.TextColor3=Color3.new(1,1,1)
end)

-- Button-Reset nach Scan
task.spawn(function()
    while true do
        task.wait(1)
        if not AF.Scanning then
            pcall(function()
                if startBtn.Text=="Scannt DB..." then
                    startBtn.Text="Start Queue"; startBtn.TextColor3=Color3.new(1,1,1)
                end
            end)
        end
    end
end)

-- Live Queue alle 8s
task.spawn(function()
    while true do task.wait(8); pcall(UpdateQueueUI) end
end)

local clearBtn = NeonBtn(qCard, "Queue leeren", D.Red, 28)
clearBtn.MouseButton1Click:Connect(function()
    AF.Queue={}; SaveQueueFile(); UpdateQueueUI()
    print("[HazeHub] Queue geleert.")
    pcall(function()
        AF.UI.Lbl.QueueFileInfo.Text="Queue geleert."; AF.UI.Lbl.QueueFileInfo.TextColor3=D.TextLow
    end)
end)

-- ============================================================
--  STARTUP
-- ============================================================

-- DB prüfen
if isfile and isfile(DB_FILE) then
    local raw; pcall(function() raw=readfile(DB_FILE) end)
    if raw and #raw < 10 then
        AF.UI.Lbl.DBStatus.Text="DB korrupt – Neu-Scan noetig!"; AF.UI.Lbl.DBStatus.TextColor3=D.Orange
    elseif LoadDB() then
        AF.UI.Lbl.DBStatus.Text=string.format("OK DB: %d Chapters",DBCount()); AF.UI.Lbl.DBStatus.TextColor3=D.Green
    end
else
    AF.UI.Lbl.DBStatus.Text="Keine DB."; AF.UI.Lbl.DBStatus.TextColor3=D.TextLow
end

-- ★ Auto-Resume starten
task.spawn(TryAutoResume)

-- Modul geladen
_G.HazeShared.SetModuleLoaded(VERSION)
print("[HazeHub] autofarm.lua v"..VERSION.." geladen  |  DB: "..DBCount().." Chapters")
