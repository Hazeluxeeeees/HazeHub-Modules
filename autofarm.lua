-- ╔══════════════════════════════════════════════════════════╗
--  HazeHUB – autofarm.lua  v2.8.1
--  GitHub: Hazeluxeeeees/HazeHub-Modules
--
--  v2.8.1:
--    + Alle Pfade nutzen LP.Name (dynamisch, kein Hardcode)
--    + TeleportToLobby via TeleportService (ID: 111446873000464)
--    + Auto-Resume: Settings.json AutoFarm=true → nach 5s starten
--    + Re-Load nach Teleport: loadstring(game:HttpGet(MAIN_URL))()
--    + 2s Pflicht-Delay nach Change-Chapter (Scanner)
--    + item.Name als primärer Identifier (ignoriert UIGridLayout)
--    + Location-Check via workspace:FindFirstChild("Lobby")
-- ╚══════════════════════════════════════════════════════════╝

local VERSION    = "2.8.1"
local LOBBY_ID   = 111446873000464
local MAIN_URL   = "https://raw.githubusercontent.com/Hazeluxeeeees/Tap-Sim/refs/heads/main/script"

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

-- ★ TeleportToLobby aus Main (falls schon gesetzt), sonst lokal
local TeleportToLobby = HS.TeleportToLobby or function()
    pcall(function() game:GetService("TeleportService"):Teleport(LOBBY_ID) end)
end

-- ============================================================
--  SERVICES
-- ============================================================
local Players          = game:GetService("Players")
local VirtualUser      = game:GetService("VirtualUser")
local TeleportService  = game:GetService("TeleportService")
-- ★ LP immer dynamisch – niemals hardcoded
local LP               = Players.LocalPlayer
local RS               = game:GetService("ReplicatedStorage")
local WS               = game:GetService("Workspace")

-- ============================================================
--  DATEIPFADE
-- ============================================================
local FOLDER        = "HazeHUB"
local DB_FILE       = "HazeHUB/HazeHUB_RewardDB.json"
local QUEUE_FILE    = "HazeHUB/HazeHUB_Queue.json"
local STATE_FILE    = "HazeHUB/HazeHUB_State.json"
local SETTINGS_FILE = "HazeHUB/HazeHUB_Settings.json"

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

local function Fire(action, data)
    if PlayRoomEvent then
        pcall(function()
            if data then PlayRoomEvent:FireServer(action, data)
            else         PlayRoomEvent:FireServer(action) end
        end)
    else PR(action, data) end
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
            if cur >= q.amount then table.remove(AF.Queue, i); changed = true end
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
    -- ============================================================
--  ★ autofarm.lua – EINZEILIGE ERGÄNZUNG (RewardDB-Brücke)
--
--  Suche in autofarm.lua nach dieser Zeile:
--      AF.RewardDatabase = data
--
--  Diese Zeile kommt in der Funktion LoadDB() vor.
--  Füge DIREKT DANACH folgende Zeile ein:
-- ============================================================
 
_G.HazeShared._AutoFarm_RewardDB = AF.RewardDatabase
 
-- ============================================================
--  ZUSÄTZLICH: In ScanAllRewards(), nach der Zeile:
--      if DBCount() > 0 then SaveDB() end
--  auch diese Zeile einfügen:
-- ============================================================
 
_G.HazeShared._AutoFarm_RewardDB = AF.RewardDatabase
 
-- ============================================================
--  Das war es. Das Craft-Modul kann jetzt automatisch die
--  beste Welt/Stage für jedes fehlende Crafting-Material
--  aus der Reward-Datenbank lesen.
-- ============================================================
 
    print("[HazeHub] DB geladen: " .. c .. " Chapters")
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
    local WorldData = HS.GetWorldData(); local WorldIds = HS.GetWorldIds()
    local tasks = {}
    for _, wid in ipairs(WorldIds) do
        local wd = WorldData[wid] or {}; local isCal = wid:lower():find("calamity") ~= nil
        for _, cid in ipairs(wd.story or {})  do table.insert(tasks, { worldId=wid, chapId=cid, mode=isCal and "Calamity" or "Story" }) end
        for _, cid in ipairs(wd.ranger or {}) do table.insert(tasks, { worldId=wid, chapId=cid, mode="Ranger" }) end
    end
    local total=0; for _ in ipairs(tasks) do total=total+1 end
    local scanned=0; local failed=0; local retried=0
    if total == 0 then AF.Scanning=false; pcall(function() onProgress("Keine Chapters!") end); return false end
    print(string.format("[HazeHub] DEEP-SCAN START: %d Chapters", total))
    Fire("Create"); task.wait(1.5)

    for _, t in ipairs(tasks) do
        if not AF.Scanning then break end
        scanned = scanned + 1
        SetScanProgress(scanned, total, string.format("Scanne: %s %s...", t.worldId, t.chapId))
        pcall(function() onProgress(string.format("Scanne %d/%d: [%s] %s", scanned, total, t.mode, t.chapId)) end)
        print(string.format("[HazeHub] [%s] %s > %s (%d/%d)", t.mode, t.worldId, t.chapId, scanned, total))

        if t.mode == "Story" then
            Fire("Create");                                             task.wait(0.5)
            Fire("Change-World",   { World   = t.worldId });           task.wait(0.5)
            Fire("Change-Chapter", { Chapter = t.chapId })
            task.wait(2.0)
        elseif t.mode == "Ranger" then
            Fire("Create");                                             task.wait(0.5)
            Fire("Change-Mode", { KeepWorld=t.worldId, Mode="Ranger Stage" })
            task.wait(1.0)
            Fire("Change-World",   { World   = t.worldId });           task.wait(0.5)
            Fire("Change-Chapter", { Chapter = t.chapId })
            task.wait(2.0)
        elseif t.mode == "Calamity" then
            Fire("Create");                                             task.wait(0.5)
            Fire("Change-Mode",    { Mode    = "Calamity" });          task.wait(0.5)
            Fire("Change-Chapter", { Chapter = t.chapId })
            task.wait(2.0)
        end

        local filled = WaitForItemsListFilled(3)
        if not filled then
            print(string.format("[HazeHub] Retry für %s...", t.chapId))
            task.wait(2.0); filled = WaitForItemsListFilled(2)
            if filled then retried = retried + 1 end
        end

        if filled then
            local items, hasItems = ScanRewardsSafe()
            local cnt = 0; for _ in pairs(items) do cnt=cnt+1 end
            if hasItems then
                AF.RewardDatabase[t.chapId] = { world=t.worldId, mode=t.mode, chapId=t.chapId, items=items }
                print(string.format("[HazeHub] OK [%s] %s: %d Items", t.mode, t.chapId, cnt))
            else
                failed=failed+1; warn(string.format("[HazeHub] LEER [%s] %s", t.mode, t.chapId))
                pcall(function() onProgress("LEER: "..t.chapId) end)
            end
        else
            failed=failed+1; warn(string.format("[HazeHub] TIMEOUT [%s] %s", t.mode, t.chapId))
            pcall(function() onProgress("TIMEOUT: "..t.chapId) end)
        end

        pcall(function() Fire("Submit"); task.wait(0.4); Fire("Create"); task.wait(0.6) end)
    end

    if DBCount() > 0 then SaveDB() end
    AF.Scanning = false
    local c=DBCount(); local ok=c>0
    local msg = string.format("%s Scan: %d/%d (%d Fehler, %d Retries)", ok and "OK" or "FEHLER", c, total, failed, retried)
    print("[HazeHub] " .. msg); pcall(function() onProgress(msg) end)
    pcall(function()
        local col = ok and D.Green or D.Orange
        AF.UI.Lbl.ScanProgress.Text=msg; AF.UI.Lbl.ScanProgress.TextColor3=col
        Tw(AF.UI.Fr.ScanBarFill, { Size=UDim2.new(ok and 1 or 0,0,1,0), BackgroundColor3=col }, TM)
        AF.UI.Lbl.DBStatus.Text=msg; AF.UI.Lbl.DBStatus.TextColor3=col
        if AF.UI.Btn.ForceRescan then AF.UI.Btn.ForceRescan.Text="DATENBANK NEU SCANNEN"; AF.UI.Btn.ForceRescan.TextColor3=Color3.new(1,1,1) end
        if AF.UI.Btn.UpdateDB   then AF.UI.Btn.UpdateDB.Text="Update Database";           AF.UI.Btn.UpdateDB.TextColor3=D.Cyan             end
    end)
    if ok then NotifyDBReady(c, string.format("Datenbank aktualisiert! (%d Chapters, %d Fehler)", c, failed)) end
    return ok
end

-- ============================================================
--  BESTES CHAPTER
-- ============================================================
local function FindBestChapter(itemName)
    local bestChapId=nil; local bestRate=-1; local bestWorldId=nil; local bestMode=nil
    for chapId, data in pairs(AF.RewardDatabase) do
        if data.items and data.items[itemName] then
            local r = data.items[itemName].dropRate or 0
            if r > bestRate then bestRate=r; bestChapId=data.chapId or chapId; bestWorldId=data.world; bestMode=data.mode end
        end
    end
    if bestChapId then print(string.format("[HazeHub] Best '%s': [%s] %s (%.1f%%)", itemName, bestMode, bestChapId, bestRate))
    else warn("[HazeHub] '"..itemName.."' nicht in DB.") end
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
        local inv=GetLiveInvAmt(q.item); local pct=math.min(1,inv/math.max(1,q.amount)); local isNext=(NextItem()==q)
        local row=Instance.new("Frame",AF.UI.Fr.List); row.Size=UDim2.new(1,0,0,44); row.BorderSizePixel=0; Corner(row,8)
        if isNext then row.BackgroundColor3=Color3.fromRGB(0,30,55); Stroke(row,D.Cyan,1.5,0)
        else            row.BackgroundColor3=D.Card;                 Stroke(row,D.Border,1,0.4) end
        local barC=isNext and D.Cyan or D.Purple
        local bar=Instance.new("Frame",row); bar.Size=UDim2.new(0,3,0.65,0); bar.Position=UDim2.new(0,0,0.175,0); bar.BackgroundColor3=barC; bar.BorderSizePixel=0; Corner(bar,2)
        local pgBg=Instance.new("Frame",row); pgBg.Size=UDim2.new(1,-52,0,3); pgBg.Position=UDim2.new(0,8,1,-6); pgBg.BackgroundColor3=Color3.fromRGB(28,38,62); pgBg.BorderSizePixel=0; Corner(pgBg,2)
        local pgF=Instance.new("Frame",pgBg); pgF.Size=UDim2.new(pct,0,1,0); pgF.BackgroundColor3=barC; pgF.BorderSizePixel=0; Corner(pgF,2)
        local nL=Instance.new("TextLabel",row); nL.Position=UDim2.new(0,12,0,5); nL.Size=UDim2.new(1,-52,0.5,-3); nL.BackgroundTransparency=1; nL.Text=(isNext and "▶ " or "")..q.item; nL.TextColor3=isNext and D.Cyan or D.TextHi; nL.TextSize=11; nL.Font=Enum.Font.GothamBold; nL.TextXAlignment=Enum.TextXAlignment.Left; nL.TextTruncate=Enum.TextTruncate.AtEnd
        local pL=Instance.new("TextLabel",row); pL.Position=UDim2.new(0,12,0.5,1); pL.Size=UDim2.new(1,-52,0.5,-5); pL.BackgroundTransparency=1; pL.Text=string.format("%d / %d  (%.0f%%)",inv,q.amount,pct*100); pL.TextColor3=D.TextMid; pL.TextSize=10; pL.Font=Enum.Font.GothamSemibold; pL.TextXAlignment=Enum.TextXAlignment.Left
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
    print("[HazeHub] RUNDE: Tracker '" .. q.item .. "'")
    SetStatus(string.format("RUNDE: Warte auf '%s'", q.item), D.TextMid)
    local deadline = os.time() + 600
    while AF.Running and os.time() < deadline do
        if CheckIsLobby() then print("[HazeHub] Tracker: Lobby erkannt."); break end
        task.wait(4)
        -- ★ Dynamisch: GetLiveInvAmt nutzt LP.Name intern
        local cur = GetLiveInvAmt(q.item)
        print(string.format("[HazeHub] '%s': %d/%d", q.item, cur, q.amount))
        SetStatus(string.format("RUNDE: '%s'  %d/%d  (%.0f%%)",
            q.item, cur, q.amount, math.min(100, cur/math.max(1,q.amount)*100)), D.Cyan)
        pcall(UpdateQueueUI); pcall(function() HS.UpdateGoalsUI() end)

        if cur >= q.amount then
            print(string.format("[HazeHub] ZIEL ERREICHT: '%s' %d/%d → Teleport zur Lobby!", q.item, cur, q.amount))
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
        for cid,data in pairs(AF.RewardDatabase) do worldId=data.world; mode=data.mode; useChapId=data.chapId or cid; break end
    end
    if not useChapId then
        local ids=HS.GetWorldIds()
        if #ids>0 then local wd=HS.GetWorldData()[ids[1]] or {}; if wd.story and #wd.story>0 then worldId=ids[1]; mode="Story"; useChapId=wd.story[1] end end
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
                pcall(function() AF.UI.Lbl.DBStatus.Text=msg; AF.UI.Lbl.DBStatus.TextColor3=D.Yellow end)
            end)
            if ok and AF.Running and not AF.Active and GetNextItem() then task.spawn(FarmLoop) end
        end)
    else task.spawn(FarmLoop) end
end

-- ============================================================
--  SCAN-TASK HELPER
-- ============================================================
local function RunScanTask(forceDelete, thenStartFarm)
    if AF.Scanning then SetStatus("Scan läuft!", D.Yellow); return end
    task.spawn(function()
        if forceDelete then ClearDB() end
        pcall(function()
            AF.UI.Fr.ScanBar.Visible=true; AF.UI.Fr.ScanBarFill.Size=UDim2.new(0,0,1,0)
            AF.UI.Fr.ScanBarFill.BackgroundColor3=D.Purple
            AF.UI.Lbl.ScanProgress.Text="Deep-Scan startet..."; AF.UI.Lbl.ScanProgress.TextColor3=D.Yellow
            if AF.UI.Btn.ForceRescan then AF.UI.Btn.ForceRescan.Text="Scannt..."; AF.UI.Btn.ForceRescan.TextColor3=D.Yellow end
        end)
        SetStatus("Deep-Scan läuft...", D.Purple)
        local ok=ScanAllRewards(function(msg)
            pcall(function() AF.UI.Lbl.DBStatus.Text=msg; AF.UI.Lbl.DBStatus.TextColor3=D.Yellow end)
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

-- DB-KARTE
local dbCard=Card(Container); Pad(dbCard,10,10,10,10); VList(dbCard,7)
SecLbl(dbCard,"REWARD-DATENBANK")
AF.UI.Lbl.DBStatus=MkLbl(dbCard,"Keine DB geladen.",11,D.TextLow); AF.UI.Lbl.DBStatus.Size=UDim2.new(1,0,0,18)
local spLbl=Instance.new("TextLabel",dbCard); spLbl.Size=UDim2.new(1,0,0,16); spLbl.BackgroundTransparency=1
spLbl.Text=""; spLbl.TextColor3=D.Yellow; spLbl.TextSize=10; spLbl.Font=Enum.Font.Gotham
spLbl.TextXAlignment=Enum.TextXAlignment.Left; spLbl.TextTruncate=Enum.TextTruncate.AtEnd; AF.UI.Lbl.ScanProgress=spLbl
local barBg=Instance.new("Frame",dbCard); barBg.Size=UDim2.new(1,0,0,7); barBg.BackgroundColor3=Color3.fromRGB(18,26,48); barBg.BorderSizePixel=0; barBg.Visible=false; Corner(barBg,3); AF.UI.Fr.ScanBar=barBg
local barFill=Instance.new("Frame",barBg); barFill.Size=UDim2.new(0,0,1,0); barFill.BackgroundColor3=D.Purple; barFill.BorderSizePixel=0; Corner(barFill,3); AF.UI.Fr.ScanBarFill=barFill

-- DB LADEN
local loadDbBtn=Instance.new("TextButton",dbCard); loadDbBtn.Size=UDim2.new(1,0,0,28); loadDbBtn.BackgroundColor3=D.CardHover; loadDbBtn.Text="DB laden"; loadDbBtn.TextColor3=D.CyanDim; loadDbBtn.TextSize=11; loadDbBtn.Font=Enum.Font.GothamBold; loadDbBtn.AutoButtonColor=false; loadDbBtn.BorderSizePixel=0; Corner(loadDbBtn,7); Stroke(loadDbBtn,D.CyanDim,1,0.3)
loadDbBtn.MouseEnter:Connect(function() Tw(loadDbBtn,{BackgroundColor3=Color3.fromRGB(0,45,75)}) end)
loadDbBtn.MouseLeave:Connect(function() Tw(loadDbBtn,{BackgroundColor3=D.CardHover}) end)
loadDbBtn.MouseButton1Click:Connect(function()
    if LoadDB() then
        local c=DBCount(); AF.UI.Lbl.DBStatus.Text=string.format("✅ DB: %d Chapters",c); AF.UI.Lbl.DBStatus.TextColor3=D.Green
        NotifyDBReady(c,string.format("Datenbank geladen! (%d Chapters)",c))
    else AF.UI.Lbl.DBStatus.Text="Keine gültige DB."; AF.UI.Lbl.DBStatus.TextColor3=D.Orange end
end)

-- UPDATE DATABASE
local updateDbBtn=Instance.new("TextButton",dbCard); updateDbBtn.Size=UDim2.new(1,0,0,34); updateDbBtn.BackgroundColor3=Color3.fromRGB(0,50,90); updateDbBtn.Text="Update Database"; updateDbBtn.TextColor3=D.Cyan; updateDbBtn.TextSize=12; updateDbBtn.Font=Enum.Font.GothamBold; updateDbBtn.AutoButtonColor=false; updateDbBtn.BorderSizePixel=0; Corner(updateDbBtn,8); Stroke(updateDbBtn,D.Cyan,1.5,0.2); AF.UI.Btn.UpdateDB=updateDbBtn
updateDbBtn.MouseEnter:Connect(function() Tw(updateDbBtn,{BackgroundColor3=Color3.fromRGB(0,70,120)}) end)
updateDbBtn.MouseLeave:Connect(function() Tw(updateDbBtn,{BackgroundColor3=Color3.fromRGB(0,50,90)}) end)
updateDbBtn.MouseButton1Click:Connect(function()
    if not CheckIsLobby() then SetStatus("Update DB: Nur in Lobby!",D.Orange); Tw(updateDbBtn,{BackgroundColor3=D.RedDark}); task.wait(0.5); Tw(updateDbBtn,{BackgroundColor3=Color3.fromRGB(0,50,90)}); return end
    if AF.Scanning then SetStatus("Scan läuft!",D.Yellow); return end
    updateDbBtn.Text="Scannt..."; updateDbBtn.TextColor3=D.Yellow; RunScanTask(true,false)
end)

-- FORCE RESCAN
local forceBtn=Instance.new("TextButton",dbCard); forceBtn.Size=UDim2.new(1,0,0,40); forceBtn.BackgroundColor3=Color3.fromRGB(68,10,108); forceBtn.Text="DATENBANK NEU SCANNEN"; forceBtn.TextColor3=Color3.new(1,1,1); forceBtn.TextSize=13; forceBtn.Font=Enum.Font.GothamBold; forceBtn.AutoButtonColor=false; forceBtn.BorderSizePixel=0; Corner(forceBtn,9); Stroke(forceBtn,Color3.fromRGB(180,80,255),2,0); AF.UI.Btn.ForceRescan=forceBtn
forceBtn.MouseEnter:Connect(function()   Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(110,22,170)}) end)
forceBtn.MouseLeave:Connect(function()   Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(68,10,108)})  end)
forceBtn.MouseButton1Down:Connect(function() Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(40,5,72)}) end)
forceBtn.MouseButton1Up:Connect(function()   Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(110,22,170)}) end)
forceBtn.MouseButton1Click:Connect(function() RunScanTask(true,false) end)

-- QUEUE-KARTE
local qCard=Card(Container); Pad(qCard,10,10,10,10); VList(qCard,8); SecLbl(qCard,"AUTO-FARM QUEUE")
local qFileInfo=MkLbl(qCard,"Keine Queue.",10,D.TextLow); qFileInfo.Size=UDim2.new(1,0,0,14); AF.UI.Lbl.QueueFileInfo=qFileInfo
local qRow=Instance.new("Frame",qCard); qRow.Size=UDim2.new(1,0,0,30); qRow.BackgroundTransparency=1; HList(qRow,5)
local qItemOuter,qItemBox=MkInput(qRow,"Item-Name..."); qItemOuter.Size=UDim2.new(0.50,0,0,30)
local qAmtOuter,qAmtBox=MkInput(qRow,"Anzahl"); qAmtOuter.Size=UDim2.new(0.28,0,0,30)
local qAddBtn=Instance.new("TextButton",qRow); qAddBtn.Size=UDim2.new(0.19,0,0,30); qAddBtn.BackgroundColor3=D.Green; qAddBtn.Text="+ Add"; qAddBtn.TextColor3=Color3.new(1,1,1); qAddBtn.TextSize=11; qAddBtn.Font=Enum.Font.GothamBold; qAddBtn.AutoButtonColor=false; qAddBtn.BorderSizePixel=0; Corner(qAddBtn,7); Stroke(qAddBtn,D.Green,1,0.2)
qAddBtn.MouseEnter:Connect(function() Tw(qAddBtn,{BackgroundColor3=Color3.fromRGB(0,160,80)}) end)
qAddBtn.MouseLeave:Connect(function() Tw(qAddBtn,{BackgroundColor3=D.Green}) end)
AF.UI.Fr.List=Instance.new("Frame",qCard); AF.UI.Fr.List.Size=UDim2.new(1,0,0,0); AF.UI.Fr.List.AutomaticSize=Enum.AutomaticSize.Y; AF.UI.Fr.List.BackgroundTransparency=1; VList(AF.UI.Fr.List,4)
AF.UI.Lbl.QueueEmpty=MkLbl(AF.UI.Fr.List,"Queue leer.",11,D.TextLow); AF.UI.Lbl.QueueEmpty.Size=UDim2.new(1,0,0,24)
qAddBtn.MouseButton1Click:Connect(function()
    local iname=(qItemBox.Text or ""):match("^%s*(.-)%s*$"); local iamt=tonumber(qAmtBox.Text)
    if iname=="" or not iamt or iamt<=0 then return end
    if ST and ST.Goals then local found=false; for _,g in ipairs(ST.Goals) do if g.item==iname then found=true; break end end; if not found then table.insert(ST.Goals,{item=iname,amount=iamt,reached=false}); SaveConfig() end end
    local inQ=false; for _,q in ipairs(AF.Queue) do if q.item==iname then inQ=true; break end end
    if not inQ then table.insert(AF.Queue,{item=iname,amount=iamt,done=false}); SaveQueueFile() end
    qItemBox.Text=""; qAmtBox.Text=""; UpdateQueueUI(); pcall(function() HS.UpdateGoalsUI() end)
    pcall(function() AF.UI.Lbl.QueueFileInfo.Text="Queue: "..#AF.Queue.." Items"; AF.UI.Lbl.QueueFileInfo.TextColor3=D.Green end)
end)
local ctrlRow=Instance.new("Frame",qCard); ctrlRow.Size=UDim2.new(1,0,0,32); ctrlRow.BackgroundTransparency=1; HList(ctrlRow,8)
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
    if updateDbBtn.Text=="Scannt..." then updateDbBtn.Text="Update Database"; updateDbBtn.TextColor3=D.Cyan end
end) end end end)
task.spawn(function() while true do task.wait(8); pcall(UpdateQueueUI) end end)
local clearBtn=NeonBtn(qCard,"Queue leeren",D.Red,28)
clearBtn.MouseButton1Click:Connect(function()
    AF.Queue={}; SaveQueueFile(); UpdateQueueUI()
    pcall(function() AF.UI.Lbl.QueueFileInfo.Text="Queue geleert."; AF.UI.Lbl.QueueFileInfo.TextColor3=D.TextLow end)
end)

-- ============================================================
--  STARTUP
-- ============================================================
if isfile and isfile(DB_FILE) then
    local raw; pcall(function() raw=readfile(DB_FILE) end)
    if raw and #raw<10 then AF.UI.Lbl.DBStatus.Text="⚠ DB korrupt!"; AF.UI.Lbl.DBStatus.TextColor3=D.Orange
    elseif LoadDB() then
        local c=DBCount(); AF.UI.Lbl.DBStatus.Text=string.format("✅ DB: %d Chapters",c); AF.UI.Lbl.DBStatus.TextColor3=D.Green
        task.delay(0.5, function() NotifyDBReady(c, string.format("Datenbank geladen! (%d Chapters)",c)) end)
    end
else AF.UI.Lbl.DBStatus.Text="Keine DB."; AF.UI.Lbl.DBStatus.TextColor3=D.TextLow end

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

    -- Status-Labels im Autofarm-UI zurücksetzen
    pcall(function()
        AF.UI.Lbl.DBStatus.Text       = "⏳ Reset & Rescan gestartet..."
        AF.UI.Lbl.DBStatus.TextColor3 = D.Yellow
        AF.UI.Fr.ScanBar.Visible      = true
        AF.UI.Fr.ScanBarFill.Size     = UDim2.new(0, 0, 1, 0)
        AF.UI.Fr.ScanBarFill.BackgroundColor3 = D.Purple
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
                AF.UI.Lbl.DBStatus.Text       = msg
                AF.UI.Lbl.DBStatus.TextColor3 = D.Yellow
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
                AF.UI.Btn.UpdateDB.TextColor3 = D.Cyan
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
print(string.format("[HazeHub] autofarm.lua v%s geladen | Spieler: %s | DB: %d Chapters", VERSION, LP.Name, DBCount()))
