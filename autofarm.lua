-- ╔══════════════════════════════════════════════════════════╗
--  HazeHUB – autofarm.lua  v2.0.0
--  GitHub: Hazeluxeeeees/HazeHub-Modules
--  FIX: UIGridLayout-Fehler, Kapitel-Auswahl 0.5s Delay,
--       Item-Tracker mit Debug-Print, Queue-Cleanup, getconnections
-- ╚══════════════════════════════════════════════════════════╝

local VERSION = "2.0.0"

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
local TF  = HS.TF;  local TM = HS.TM;  local Tw = HS.Tw
local Svc = HS.Svc

local Card    = HS.Card;    local NeonBtn = HS.NeonBtn
local MkLbl   = HS.MkLbl;  local SecLbl  = HS.SecLbl
local MkInput = HS.MkInput; local VList   = HS.VList
local HList   = HS.HList;   local Pad     = HS.Pad
local Corner  = HS.Corner;  local Stroke  = HS.Stroke

local PR         = HS.PR
local SaveConfig = HS.SaveConfig
local SendWebhook= HS.SendWebhook
local Container  = HS.Container

-- ============================================================
--  SERVICES
-- ============================================================
local VIM         = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local LP          = game:GetService("Players").LocalPlayer
local RS          = game:GetService("ReplicatedStorage")
local WS          = game:GetService("Workspace")

-- ============================================================
--  ANTI-AFK
-- ============================================================
pcall(function()
    LP.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
        print("[HazeHub] Anti-AFK: Idle abgefangen.")
    end)
end)
task.spawn(function()
    while true do
        task.wait(480)
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
        print("[HazeHub] Anti-AFK: Heartbeat (8min).")
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
--  DATEIPFADE
-- ============================================================
local FOLDER     = "HazeHUB"
local DB_FILE    = "HazeHUB/HazeHUB_RewardDB.json"
local QUEUE_FILE = "HazeHUB/HazeHUB_Queue.json"
local STATE_FILE = "HazeHUB/HazeHUB_State.json"

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
_G.InGameServer    = false

-- ============================================================
--  WORKSPACE-LOCATION CHECK
-- ============================================================
local function CheckIsLobby()
    return WS:FindFirstChild("Lobby") ~= nil
end

local function UpdateLocationState()
    _G.InGameServer = not CheckIsLobby()
end

-- Hintergrund-Loop alle 2s
task.spawn(function()
    while true do
        task.wait(2)
        pcall(UpdateLocationState)
    end
end)

-- ============================================================
--  INVENTAR (Live aus ReplicatedStorage)
-- ============================================================
local function GetLiveInvAmt(itemName)
    local n = 0
    pcall(function()
        local f = RS:WaitForChild("Player_Data", 3)
            :WaitForChild(LP.Name, 3)
            :WaitForChild("Items",  3)
        local item = f:FindFirstChild(itemName)
        if not item then return end
        local vc = item:FindFirstChild("Value") or item:FindFirstChild("Amount")
        if vc then
            n = tonumber(vc.Value) or 0
        elseif item:IsA("IntValue") or item:IsA("NumberValue") then
            n = tonumber(item.Value) or 0
        end
    end)
    return n
end

-- ============================================================
--  FORCE BACK TO LOBBY via getconnections
-- ============================================================
local function ForceBackToLobby()
    print("[HazeHub] ForceBackToLobby: Starte via getconnections...")
    local clicked = false

    pcall(function()
        local btn = LP.PlayerGui
            :WaitForChild("Settings",       4)
            :WaitForChild("Main",           4)
            :WaitForChild("Base",           4)
            :WaitForChild("Space",          4)
            :WaitForChild("ScrollingFrame", 4)
            :WaitForChild("Back To Lobby",  4)
        if not btn then return end

        local conns
        pcall(function() conns = getconnections(btn.MouseButton1Click) end)
        if conns and #conns > 0 then
            for _, conn in ipairs(conns) do
                pcall(function() conn:Fire() end)
            end
            clicked = true
            print(string.format("[HazeHub] ForceBackToLobby: getconnections OK (%d Conn).", #conns))
        else
            btn.MouseButton1Click:Fire()
            clicked = true
            print("[HazeHub] ForceBackToLobby: MouseButton1Click:Fire() Fallback.")
        end
    end)

    if not clicked then
        pcall(function()
            if HS.ClickBackToLobby then HS.ClickBackToLobby(); clicked = true end
        end)
        if clicked then print("[HazeHub] ForceBackToLobby: HS.ClickBackToLobby() Backup.") end
    end

    if not clicked then warn("[HazeHub] ForceBackToLobby: Alle Methoden fehlgeschlagen.") end
    return clicked
end

-- ============================================================
--  PERSISTENZ: STATE
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
    print("[HazeHub] State: AutoFarmRunning=" .. tostring(_G.AutoFarmRunning))
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
--  PERSISTENZ: QUEUE
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
    print(string.format("[HazeHub] Queue geladen: %d Items.", #AF.Queue))
    return #AF.Queue > 0
end

local function RemoveFromQueue(itemName)
    for i = #AF.Queue, 1, -1 do
        if AF.Queue[i].item == itemName then table.remove(AF.Queue, i) end
    end
    SaveQueueFile()
    print(string.format("[HazeHub] '%s' aus Queue entfernt + Queue.json gespeichert.", itemName))
end

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
local function DBCount()
    local c = 0; for _ in pairs(AF.RewardDatabase) do c = c + 1 end; return c
end

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
--  GAME-TAB RE-INIT
-- ============================================================
local function WaitForChapterFolderWithRetry(maxSec)
    maxSec = maxSec or 40
    local deadline = os.clock() + maxSec
    while os.clock() < deadline do
        local f = nil
        pcall(function()
            f = LP.PlayerGui
                :WaitForChild("PlayRoom",  2):WaitForChild("Main",     2)
                :WaitForChild("GameStage", 2):WaitForChild("Main",     2)
                :WaitForChild("Base",      2):WaitForChild("Chapter",  2)
        end)
        if f and f.Parent then
            print("[HazeHub] Chapter-Ordner: " .. f:GetFullName())
            return f
        end
        print("[HazeHub] Chapter-Ordner noch nicht da – Retry in 2s...")
        task.wait(2)
    end
    warn("[HazeHub] Chapter-Ordner nicht gefunden.")
    return nil
end

local function ReinitGameTab()
    print("[HazeHub] Game-Tab Re-Init...")
    pcall(function() if ST then ST.ChapFolderRef = nil end end)
    local f = WaitForChapterFolderWithRetry(30)
    if f then
        pcall(function()
            if ST then ST.ChapFolderRef = f; ST.ScanDone = true end
        end)
        print("[HazeHub] Game-Tab Re-Init OK.")
    end
    return f
end

-- ============================================================
--  STATUS-HELPER
-- ============================================================
local function SetStatus(text, color)
    pcall(function()
        AF.UI.Lbl.Status.Text       = text
        AF.UI.Lbl.Status.TextColor3 = color or D.TextMid
    end)
    pcall(function()
        local ml = LP.PlayerGui:FindFirstChild("ModulStatus", true)
        if ml and ml:IsA("TextLabel") then
            ml.Text = text; ml.TextColor3 = color or D.TextMid
        end
    end)
end

local function SetScanProgress(current, total, label)
    local pct = math.max(0, math.min(1, current / math.max(1, total)))
    local txt = string.format("%s  (%d/%d – %.0f%%)", label, current, total, pct * 100)
    pcall(function()
        AF.UI.Lbl.ScanProgress.Text       = txt
        AF.UI.Lbl.ScanProgress.TextColor3 = D.Yellow
        AF.UI.Fr.ScanBar.Visible          = true
        Tw(AF.UI.Fr.ScanBarFill, {Size = UDim2.new(pct, 0, 1, 0)}, TF)
    end)
    pcall(function()
        local ml = LP.PlayerGui:FindFirstChild("ModulStatus", true)
        if ml then ml.Text = txt; ml.TextColor3 = D.Yellow end
    end)
end

-- ============================================================
--  ★ PARSE ITEMS – NUR Frame-Objekte, niemals Layouts
-- ============================================================
--  Garantiert kein UIGridLayout/UIListLayout Fehler:
--  Einzige Bedingung: child:IsA("Frame")
local function ParseItems(itemsList)
    local items = {}
    if not itemsList then return items end

    for _, child in pairs(itemsList:GetChildren()) do
        -- ★ NUR Frame-Instanzen verarbeiten
        if not child:IsA("Frame") then continue end

        pcall(function()
            local iname, rate, amt = "", 0, 1

            -- Versuche Info-Unterordner
            local inf = child:FindFirstChild("Info")
            if inf then
                local nameV = inf:FindFirstChild("ItemNames")
                local rateV = inf:FindFirstChild("DropRate")
                local amtV  = inf:FindFirstChild("DropAmount")
                iname = nameV and tostring(nameV.Value) or ""
                rate  = rateV and tonumber(rateV.Value) or 0
                amt   = amtV  and tonumber(amtV.Value)  or 1
            else
                -- Direkte Kinder des Frame
                local nameV = child:FindFirstChild("ItemNames")
                local rateV = child:FindFirstChild("DropRate")
                local amtV  = child:FindFirstChild("DropAmount")
                if nameV then
                    iname = tostring(nameV.Value)
                    rate  = rateV and tonumber(rateV.Value) or 0
                    amt   = amtV  and tonumber(amtV.Value)  or 1
                end
            end

            if iname ~= "" then
                items[iname] = {dropRate = rate, dropAmount = amt}
                print(string.format("[HazeHub] Scan Item: %s (Rate: %.1f%%)", iname, rate))
            end
        end)
    end
    return items
end

-- ★ ClearItemsList: nur Frame-Kinder entfernen
local function ClearItemsList(itemsList)
    if not itemsList then return end
    pcall(function()
        for _, child in pairs(itemsList:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end
    end)
end

-- ============================================================
--  SCAN-HELFER
-- ============================================================
local function GetItemsList(timeoutSec)
    local result = nil
    local deadline = os.clock() + (timeoutSec or 4)
    while os.clock() < deadline do
        pcall(function()
            result = LP.PlayerGui
                :WaitForChild("PlayRoom",  1):WaitForChild("Main",      1)
                :WaitForChild("GameStage", 1):WaitForChild("Main",      1)
                :WaitForChild("Base",      1):WaitForChild("Rewards",   1)
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
    -- Zähle nur Frame-Kinder (nicht Layouts!)
    local function frameCount()
        local c = 0
        for _, child in pairs(itemsList:GetChildren()) do
            if child:IsA("Frame") then c = c + 1 end
        end
        return c
    end
    if frameCount() > 0 then return true end
    local filled = false
    local conn = itemsList.ChildAdded:Connect(function(child)
        if child:IsA("Frame") then filled = true end
    end)
    local deadline = os.clock() + timeoutSec
    while os.clock() < deadline and not filled do
        if frameCount() > 0 then filled = true; break end
        task.wait(0.15)
    end
    pcall(function() conn:Disconnect() end)
    return filled
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

-- ============================================================
--  SCAN-FUNKTION
-- ============================================================
local function ScanAllRewards(onProgress)
    if AF.Scanning then return false end
    if not HS.IsScanDone() then
        pcall(function() onProgress("X Weltdaten fehlen.") end)
        return false
    end

    AF.Scanning = true
    AF.RewardDatabase = {}

    local WorldData = HS.GetWorldData()
    local WorldIds  = HS.GetWorldIds()
    local tasks = {}
    for _, wid in ipairs(WorldIds) do
        local wd = WorldData[wid] or {}
        local isCal = wid:lower():find("calamity") ~= nil
        for _, cid in ipairs(wd.story  or {}) do
            table.insert(tasks, {worldId=wid, chapId=cid, mode=isCal and "Calamity" or "Story"})
        end
        for _, cid in ipairs(wd.ranger or {}) do
            table.insert(tasks, {worldId=wid, chapId=cid, mode="Ranger"})
        end
    end

    local total = #tasks; local scanned = 0; local failed = 0
    if total == 0 then AF.Scanning=false; return false end

    local chapBase = nil
    pcall(function()
        chapBase = LP.PlayerGui
            :WaitForChild("PlayRoom",  5):WaitForChild("Main",     5)
            :WaitForChild("GameStage", 5):WaitForChild("Main",     5)
            :WaitForChild("Base",      5):WaitForChild("Chapter",  5)
    end)

    -- ★ PlayRoom Remote feuern um Menü zu initialisieren
    Fire("Create"); task.wait(0.8)
    local itemsList = GetItemsList(5)

    for _, t in ipairs(tasks) do
        if not AF.Scanning then break end
        scanned = scanned + 1

        SetScanProgress(scanned, total, string.format("Scanne: %s %s", t.worldId, t.chapId))
        pcall(function()
            onProgress(string.format("Scanne %d/%d: %s %s", scanned, total, t.worldId, t.chapId))
        end)
        print(string.format("[HazeHub] Scanne: %s > %s (%d/%d)", t.worldId, t.chapId, scanned, total))

        if not itemsList or not itemsList.Parent then
            Fire("Create"); task.wait(0.8)
            itemsList = GetItemsList(4)
        end

        -- ★ Nur Frame-Kinder leeren
        ClearItemsList(itemsList)
        task.wait(0.1)

        -- ★ Welt/Modus setzen
        pcall(function()
            if     t.mode=="Story"    then Fire("Change-World", {World=t.worldId})
            elseif t.mode=="Ranger"   then Fire("Change-Mode",  {KeepWorld=t.worldId, Mode="Ranger Stage"})
            elseif t.mode=="Calamity" then Fire("Change-Mode",  {Mode="Calamity"}) end
        end)

        -- ★ 0.5s Delay zwischen Welten-Wechsel und Kapitel-Auswahl
        task.wait(0.5)

        -- ★ Kapitel per Remote + GUI-Klick
        Fire("Change-Chapter", {Chapter=t.chapId})
        task.wait(0.3)
        if chapBase then ClickChapterButton(chapBase, t.worldId, t.chapId) end

        if not itemsList or not itemsList.Parent then itemsList = GetItemsList(3) end

        -- Warten auf Frame-Kinder
        local got = WaitForItems(itemsList, 3)
        if got and itemsList then
            local items = ParseItems(itemsList)    -- ★ nur Frame-Objekte
            local cnt = 0; for _ in pairs(items) do cnt = cnt + 1 end
            if cnt > 0 then
                AF.RewardDatabase[t.chapId] = {world=t.worldId, mode=t.mode, items=items}
                print(string.format("[HazeHub] OK: %s – %d Items gespeichert.", t.chapId, cnt))
            else
                failed = failed + 1
                warn(string.format("[HazeHub] LEER: %s (keine Frame-Items).", t.chapId))
            end
        else
            failed = failed + 1
            warn(string.format("[HazeHub] TIMEOUT: %s.", t.chapId))
            pcall(function() onProgress("TIMEOUT: " .. t.chapId) end)
        end

        -- Reset für nächstes Chapter
        pcall(function()
            Fire("Submit"); task.wait(0.15)
            Fire("Create"); task.wait(0.3)
        end)
        task.wait(0.2)
    end

    if DBCount() > 0 then SaveDB() end
    AF.Scanning = false

    local c  = DBCount()
    local ok = c > 0
    local msg = string.format("%s Scan: %d/%d (%d Fehler)", ok and "OK" or "X", c, total, failed)
    print("[HazeHub] " .. msg)
    pcall(function() onProgress(msg) end)
    pcall(function()
        local col = ok and D.Green or D.Orange
        AF.UI.Lbl.ScanProgress.Text        = msg
        AF.UI.Lbl.ScanProgress.TextColor3  = col
        Tw(AF.UI.Fr.ScanBarFill, {Size=UDim2.new(ok and 1 or 0,0,1,0), BackgroundColor3=col}, TM)
        AF.UI.Lbl.DBStatus.Text            = msg
        AF.UI.Lbl.DBStatus.TextColor3      = col
        AF.UI.Btn.ForceRescan.Text         = "DATENBANK NEU SCANNEN"
        AF.UI.Btn.ForceRescan.TextColor3   = Color3.new(1,1,1)
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
            if r > bestRate then
                bestRate=r; best=chapId; bestWorld=data.world; bestMode=data.mode
            end
        end
    end
    if best then
        print(string.format("[HazeHub] Best: %s in %s [%s] (%.1f%%)", best, bestWorld, bestMode, bestRate))
    else
        warn("[HazeHub] '" .. itemName .. "' nicht in DB.")
    end
    return best, bestWorld, bestMode, bestRate
end

-- ============================================================
--  RAUM STARTEN (★ nur wenn workspace.Lobby existiert!)
-- ============================================================
local function FireRoomSequence(worldId, mode, chapId)
    if not CheckIsLobby() then
        warn("[HazeHub] FireRoomSequence BLOCKIERT – kein workspace.Lobby!")
        return
    end
    print(string.format("[HazeHub] Erstelle Raum: %s | %s | %s", worldId, mode, chapId))
    task.spawn(function()
        pcall(function()
            -- ★ Menü initialisieren
            Fire("Create");                                          task.wait(0.35)

            -- ★ Welt/Modus setzen
            if     mode=="Story"    then Fire("Change-World", {World=worldId})
            elseif mode=="Ranger"   then Fire("Change-Mode",  {KeepWorld=worldId, Mode="Ranger Stage"})
            elseif mode=="Calamity" then Fire("Change-Mode",  {Mode="Calamity"}) end

            -- ★ 0.5s Delay damit Server hinterherkommt
            task.wait(0.5)

            -- ★ Kapitel-ID senden
            Fire("Change-Chapter", {Chapter=chapId});                task.wait(0.35)
            Fire("Submit");                                          task.wait(0.5)
            Fire("Start")
            print("[HazeHub] Raum gestartet: " .. chapId)
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

    local hasActive = false
    for _, q in ipairs(AF.Queue) do if not q.done then hasActive=true; break end end
    if AF.UI.Lbl.QueueEmpty then AF.UI.Lbl.QueueEmpty.Visible = not hasActive end

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
        if isNext then
            row.BackgroundColor3=Color3.fromRGB(0,30,55); Stroke(row,D.Cyan,1.5,0)
        else
            row.BackgroundColor3=D.Card; Stroke(row,D.Border,1,0.4)
        end

        local barC = isNext and D.Cyan or D.Purple
        local bar = Instance.new("Frame",row)
        bar.Size=UDim2.new(0,3,0.65,0); bar.Position=UDim2.new(0,0,0.175,0)
        bar.BackgroundColor3=barC; bar.BorderSizePixel=0; Corner(bar,2)

        local pgBg = Instance.new("Frame",row)
        pgBg.Size=UDim2.new(1,-52,0,3); pgBg.Position=UDim2.new(0,8,1,-6)
        pgBg.BackgroundColor3=Color3.fromRGB(28,38,62); pgBg.BorderSizePixel=0; Corner(pgBg,2)
        local pgF = Instance.new("Frame",pgBg)
        pgF.Size=UDim2.new(pct,0,1,0); pgF.BackgroundColor3=barC
        pgF.BorderSizePixel=0; Corner(pgF,2)

        local nL = Instance.new("TextLabel",row)
        nL.Position=UDim2.new(0,12,0,5); nL.Size=UDim2.new(1,-52,0.5,-3)
        nL.BackgroundTransparency=1
        nL.Text=(isNext and ">> " or "")..q.item
        nL.TextColor3=isNext and D.Cyan or D.TextHi
        nL.TextSize=11; nL.Font=Enum.Font.GothamBold
        nL.TextXAlignment=Enum.TextXAlignment.Left
        nL.TextTruncate=Enum.TextTruncate.AtEnd

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
        xBtn.AutoButtonColor=false; xBtn.BorderSizePixel=0
        Corner(xBtn,7); Stroke(xBtn,D.Red,1,0.4)
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
--  ★ RUNDEN-MONITOR (kein workspace.Lobby = Runde)
--  Nur Inventar prüfen, KEINE Create/Start Remotes
-- ============================================================
local function RoundMonitorLoop(q)
    print("[HazeHub] Runde erkannt (kein workspace.Lobby). Tracker aktiv: " .. q.item)
    SetStatus(string.format("RUNDE – Tracker: %s", q.item), D.TextMid)

    local deadline = os.time() + 600
    while AF.Running and os.time() < deadline do
        -- Wenn workspace.Lobby erscheint → raus
        if CheckIsLobby() then
            print("[HazeHub] workspace.Lobby erschienen – verlasse Runden-Monitor.")
            break
        end

        task.wait(5)
        local cur = GetLiveInvAmt(q.item)

        -- ★ Debug-Print für Item-Tracker
        print(string.format("[HazeHub] Tracker: Item gefunden! Fortschritt: %d/%d",
            cur, q.amount))

        SetStatus(string.format("RUNDE: %s  %d/%d  (%.0f%%)",
            q.item, cur, q.amount,
            math.min(100, cur / math.max(1, q.amount) * 100)), D.Cyan)
        pcall(UpdateQueueUI)
        pcall(function() HS.UpdateGoalsUI() end)

        -- ★ Ziel erreicht: Queue-Cleanup + sofortiger ForceBackToLobby
        if cur >= q.amount then
            print(string.format("[HazeHub] Tracker: Ziel erreicht! %s (%d/%d) – Starte Lobby-Exit.",
                q.item, cur, q.amount))
            task.spawn(function() pcall(function() SendWebhook({}, q.item, cur) end) end)

            -- ★ 1. Item sofort aus Queue.json entfernen
            RemoveFromQueue(q.item)
            pcall(UpdateQueueUI)

            SetStatus(string.format("Ziel erreicht! %s – Lobby-Exit...", q.item), D.Green)

            -- ★ 2. 3 Sekunden warten
            task.wait(3)

            -- ★ 3. ForceBackToLobby (getconnections) nur wenn noch in Runde
            if not CheckIsLobby() then
                ForceBackToLobby()
            end

            -- Warten bis workspace.Lobby erscheint
            local lw = 0
            while AF.Running and not CheckIsLobby() and lw < 20 do
                task.wait(1); lw = lw + 1
            end
            return true
        end
    end
    return false
end

-- ============================================================
--  LOBBY-AKTION (workspace.Lobby vorhanden = Lobby)
-- ============================================================
local function LobbyActionLoop(delaySeconds)
    delaySeconds = delaySeconds or 5
    print("[HazeHub] Lobby erkannt (workspace.Lobby). Sync in " .. delaySeconds .. "s...")
    SetStatus(string.format("LOBBY: Sync in %ds...", delaySeconds), D.Yellow)

    task.wait(delaySeconds)

    -- Nochmal prüfen
    if not CheckIsLobby() then
        print("[HazeHub] LobbyAction: workspace.Lobby verschwunden – abgebrochen.")
        return true
    end

    -- ★ PlayRoom Remote initialisieren (Menü öffnen)
    Fire("Create")
    task.wait(0.5)

    -- Inventar-Sync
    local changed = SyncInventoryWithQueue()
    if changed then pcall(UpdateQueueUI) end

    local function NextItem()
        for _, q in ipairs(AF.Queue) do if not q.done then return q end end
        return nil
    end

    local q = NextItem()
    if not q then
        SetStatus("Queue leer – Farm beendet.", D.Green)
        print("[HazeHub] Queue leer.")
        AF.Active=false; _G.AutoFarmRunning=false; SaveState()
        return false
    end

    -- Bestes Chapter
    local chapId, worldId, mode, rate = FindBestChapter(q.item)
    if not chapId then
        for cid,data in pairs(AF.RewardDatabase) do
            chapId=cid; worldId=data.world; mode=data.mode; rate=0; break
        end
    end
    if not chapId then
        local ids = HS.GetWorldIds()
        if #ids > 0 then
            local wd = HS.GetWorldData()[ids[1]] or {}
            if wd.story and #wd.story > 0 then
                chapId=wd.story[1]; worldId=ids[1]; mode="Story"; rate=0
            end
        end
    end
    if not chapId then
        SetStatus("Kein Level fuer '" .. q.item .. "'", D.Orange)
        RemoveFromQueue(q.item); pcall(UpdateQueueUI); return true
    end

    -- ★ Raum starten (intern mit 0.5s Delay zwischen Welt + Kapitel)
    SetStatus(string.format("LOBBY: %s -> %s (%.1f%%)", q.item, chapId, rate or 0), D.Cyan)
    FireRoomSequence(worldId, mode, chapId)

    -- Warten bis workspace.Lobby verschwindet (= Runde gestartet)
    local ws = os.clock()
    while AF.Running and CheckIsLobby() and os.clock()-ws < 30 do
        task.wait(1)
    end
    task.wait(1)
    return true
end

-- HAUPT-LOOP
local function GetNextItem()
    for _, q in ipairs(AF.Queue) do if not q.done then return q end end
    return nil
end

local function FarmLoop()
    AF.Active          = true
    _G.AutoFarmRunning = true
    SaveState()
    print("[HazeHub] === FARM LOOP GESTARTET ===")

    local firstLobby = true

    while AF.Running do
        UpdateLocationState()
        local isLobby = CheckIsLobby()

        if not isLobby then
            firstLobby = true
            local q = GetNextItem()
            if not q then
                print("[HazeHub] Queue leer in Runde – ForceBackToLobby.")
                task.wait(3)
                if not CheckIsLobby() then ForceBackToLobby() end
                task.wait(8); break
            end
            RoundMonitorLoop(q)
            task.wait(2)
        else
            local delay = firstLobby and 5 or 2
            firstLobby = false
            local continue_ = LobbyActionLoop(delay)
            if not continue_ then break end
            task.wait(2)
        end
    end

    AF.Active = false
    if not AF.Running then
        _G.AutoFarmRunning=false; SaveState()
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
    _G.InGameServer    = false
    SaveState()
    SetStatus("Gestoppt.", D.TextMid)
    print("[HazeHub] Farm gestoppt.")
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
            if GetNextItem() then task.spawn(FarmLoop) end
        end
    end)
end

-- ============================================================
--  AUTO-RESUME
-- ============================================================
local function TryAutoResume()
    task.wait(3)

    local hasQueue = LoadQueueFile()
    LoadState()
    UpdateLocationState()
    local isLobby = CheckIsLobby()

    if isLobby then
        print("[HazeHub] Auto-Resume Ort: LOBBY (workspace.Lobby vorhanden).")
        task.spawn(function() task.wait(1); ReinitGameTab() end)
    else
        print("[HazeHub] Auto-Resume Ort: RUNDE (kein workspace.Lobby).")
    end

    if hasQueue then
        SyncInventoryWithQueue()
        pcall(UpdateQueueUI)
    end

    if not _G.AutoFarmRunning then
        print("[HazeHub] Auto-Resume: AutoFarmRunning=false – Farm bleibt AUS.")
        SetStatus(hasQueue
            and string.format("Queue: %d Items (Farm AUS)", #AF.Queue)
            or  "Farm gestoppt.", D.TextMid)
        pcall(UpdateQueueUI)
        return
    end

    if not hasQueue or not GetNextItem() then
        print("[HazeHub] Auto-Resume: Queue leer.")
        _G.AutoFarmRunning=false; SaveState()
        pcall(UpdateQueueUI)
        return
    end

    if DBCount() == 0 then LoadDB() end

    local delay = isLobby and 5 or 2
    SetStatus(string.format("Auto-Resume: Start in %ds...", delay), D.Yellow)
    print(string.format("[HazeHub] Auto-Resume: Start in %ds...", delay))
    task.wait(delay)

    if GetNextItem() then
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

-- LOCATION-INDIKATOR
local locCard = Card(Container, 22); Pad(locCard, 2, 10, 2, 10)
local locLbl  = Instance.new("TextLabel", locCard)
locLbl.Size=UDim2.new(1,0,1,0); locLbl.BackgroundTransparency=1
locLbl.Text="Ort: wird erkannt..."; locLbl.TextColor3=D.TextLow
locLbl.TextSize=10; locLbl.Font=Enum.Font.Gotham
locLbl.TextXAlignment=Enum.TextXAlignment.Left
task.spawn(function()
    while true do
        task.wait(2)
        pcall(function()
            if CheckIsLobby() then
                locLbl.Text      = "Ort: LOBBY  (workspace.Lobby exists)"
                locLbl.TextColor3 = D.Green
            else
                locLbl.Text      = "Ort: RUNDE  (no workspace.Lobby)"
                locLbl.TextColor3 = D.Orange
            end
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
        AF.UI.Lbl.DBStatus.Text=string.format("OK DB: %d Chapters",DBCount())
        AF.UI.Lbl.DBStatus.TextColor3=D.Green
    else
        AF.UI.Lbl.DBStatus.Text="Keine gueltige DB."
        AF.UI.Lbl.DBStatus.TextColor3=D.Orange
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
        AF.UI.Lbl.QueueFileInfo.Text="Queue: "..#AF.Queue.." Items"
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
    if AF.Active then SetStatus("Farm laeuft!", D.Yellow); return end
    if #AF.Queue==0 then SetStatus("Queue leer!", D.Orange); return end
    AF.Running         = true
    _G.AutoFarmRunning = true
    SaveState()
    if DBCount()==0 then
        SetStatus("DB leer – starte Scan...", D.Yellow)
        pcall(function() startBtn.Text="Scannt..."; startBtn.TextColor3=D.Yellow end)
        RunScanTask(false, true)
    else
        print(string.format("[HazeHub] Start: %d Items, DB: %d Chapters.", #AF.Queue, DBCount()))
        task.spawn(FarmLoop)
    end
end)

stopBtn.MouseButton1Click:Connect(function()
    StopFarm()
    startBtn.Text="Start Queue"; startBtn.TextColor3=Color3.new(1,1,1)
end)

task.spawn(function()
    while true do
        task.wait(1)
        if not AF.Scanning then
            pcall(function()
                if startBtn.Text=="Scannt..." then
                    startBtn.Text="Start Queue"; startBtn.TextColor3=Color3.new(1,1,1)
                end
            end)
        end
    end
end)

task.spawn(function()
    while true do task.wait(8); pcall(UpdateQueueUI) end
end)

local clearBtn = NeonBtn(qCard, "Queue leeren", D.Red, 28)
clearBtn.MouseButton1Click:Connect(function()
    AF.Queue={}; SaveQueueFile(); UpdateQueueUI()
    print("[HazeHub] Queue geleert.")
    pcall(function()
        AF.UI.Lbl.QueueFileInfo.Text="Queue geleert."
        AF.UI.Lbl.QueueFileInfo.TextColor3=D.TextLow
    end)
end)

-- ============================================================
--  STARTUP
-- ============================================================
if isfile and isfile(DB_FILE) then
    local raw; pcall(function() raw=readfile(DB_FILE) end)
    if raw and #raw < 10 then
        AF.UI.Lbl.DBStatus.Text="DB korrupt – Neu-Scan!"
        AF.UI.Lbl.DBStatus.TextColor3=D.Orange
    elseif LoadDB() then
        AF.UI.Lbl.DBStatus.Text=string.format("OK DB: %d Chapters",DBCount())
        AF.UI.Lbl.DBStatus.TextColor3=D.Green
    end
else
    AF.UI.Lbl.DBStatus.Text="Keine DB."
    AF.UI.Lbl.DBStatus.TextColor3=D.TextLow
end

task.spawn(TryAutoResume)

_G.HazeShared.SetModuleLoaded(VERSION)
print("[HazeHub] autofarm.lua v"..VERSION.." geladen  |  DB: "..DBCount().." Chapters")
