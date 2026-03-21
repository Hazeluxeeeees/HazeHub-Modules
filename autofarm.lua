-- ╔══════════════════════════════════════════════════════════╗
--  HazeHUB – autofarm.lua  v1.2.0
--  GitHub: Hazeluxeeeees/HazeHub-Modules
--  NEU: Klick-basierter Scanner, ChildAdded-Erkennung,
--       Force-Rescan Button, Queue-Validierung, Debug-Prints
-- ╚══════════════════════════════════════════════════════════╝

local VERSION = "1.2.0"

-- ============================================================
--  WARTEN BIS SHARED-TABLE BEREIT IST  (max. 10s)
-- ============================================================
local waited = 0
while not (_G.HazeShared and _G.HazeShared.Container and _G.HazeShared.SetModuleLoaded) do
    task.wait(0.3); waited = waited + 0.3
    if waited >= 10 then
        warn("[HazeHub] _G.HazeShared nicht bereit nach 10s – Abbruch.")
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

local PR                 = HS.PR
local FireCreateAndStart = HS.FireCreateAndStart
local FireVoteRetry      = HS.FireVoteRetry
local GetInvAmt          = HS.GetInvAmt
local IsInLobby          = HS.IsInLobby
local ClickBackToLobby   = HS.ClickBackToLobby
local SaveConfig         = HS.SaveConfig
local SendWebhook        = HS.SendWebhook

local Container = HS.Container

-- ============================================================
--  AUTOFARM STATE
-- ============================================================
local AF = {
    Queue      = {},
    Active     = false,
    Running    = true,
    Scanning   = false,
    RewardDB   = {},   -- [chapId] = {world, mode, items={[name]={dropRate,dropAmount}}}
    UI         = { Lbl={}, Fr={}, Btn={} },
}

local DB_FILE   = "HazeHUB/HazeHUB_RewardDB.json"
local QUEUE_KEY = "SavedQueue"

-- ============================================================
--  QUEUE PERSISTENZ
-- ============================================================
local function SaveQueue()
    CFG[QUEUE_KEY] = {}
    for _, q in ipairs(AF.Queue) do
        table.insert(CFG[QUEUE_KEY], {item=q.item, amount=q.amount, done=q.done})
    end
    SaveConfig()
end

local function LoadQueue()
    if not CFG[QUEUE_KEY] then return end
    AF.Queue = {}
    for _, q in ipairs(CFG[QUEUE_KEY]) do
        if q.item and tonumber(q.amount) then
            table.insert(AF.Queue, {item=q.item, amount=tonumber(q.amount), done=q.done==true})
        end
    end
end

-- ============================================================
--  DB SAVE / LOAD  (mit Groessen-Validierung)
-- ============================================================
local function DBCount()
    local c = 0; for _ in pairs(AF.RewardDB) do c = c + 1 end; return c
end

local function SaveDB()
    if not writefile then return end
    pcall(function()
        local encoded = Svc.Http:JSONEncode(AF.RewardDB)
        writefile(DB_FILE, encoded)
        print("[HazeHub] Speichere Datenbank... (" .. #encoded .. " Bytes, " .. DBCount() .. " Chapters)")
    end)
end

local function LoadDB()
    if not (isfile and isfile(DB_FILE)) then return false end
    local raw; pcall(function() raw = readfile(DB_FILE) end)
    if not raw or #raw < 10 then
        warn("[HazeHub] DB-Datei zu klein (<10 Bytes) – wird ignoriert.")
        return false
    end
    local ok, data = pcall(function() return Svc.Http:JSONDecode(raw) end)
    if not ok or type(data) ~= "table" then return false end
    local count = 0; for _ in pairs(data) do count = count + 1 end
    if count == 0 then return false end
    AF.RewardDB = data
    print("[HazeHub] DB geladen: " .. count .. " Chapters aus Datei.")
    return true
end

local function ClearDB()
    AF.RewardDB = {}
    if writefile and isfile and isfile(DB_FILE) then
        pcall(function() writefile(DB_FILE, "{}") end)
    end
    print("[HazeHub] Datenbank geloescht – bereit fuer Neu-Scan.")
end

-- ============================================================
--  CHAPTER-ORDNER HOLEN  (Lobby-UI)
-- ============================================================
local function GetChapterFolder()
    local f = nil
    pcall(function()
        f = game:GetService("Players").LocalPlayer
            :WaitForChild("PlayerGui", 10)
            :WaitForChild("PlayRoom",  10)
            :WaitForChild("Main",      10)
            :WaitForChild("GameStage", 10)
            :WaitForChild("Main",      10)
            :WaitForChild("Base",      10)
            :WaitForChild("Chapter",   10)
    end)
    return f
end

-- ============================================================
--  ITEMSLIST WARTEN  (ChildAdded + Polling)
-- ============================================================
local function WaitForItemsListFilled(timeoutSec)
    timeoutSec = timeoutSec or 2.5
    local itemsList = nil

    -- Pfad finden
    local deadline = os.clock() + 5
    while os.clock() < deadline and AF.Running do
        pcall(function()
            itemsList = game:GetService("Players").LocalPlayer
                :WaitForChild("PlayerGui", 2)
                :WaitForChild("PlayRoom",  2)
                :WaitForChild("Main",      2)
                :WaitForChild("GameStage", 2)
                :WaitForChild("Main",      2)
                :WaitForChild("Base",      2)
                :WaitForChild("Rewards",   2)
                :WaitForChild("ItemsList", 2)
        end)
        if itemsList and itemsList.Parent then break end
        itemsList = nil; task.wait(0.3)
    end
    if not itemsList then return nil end

    -- Warten bis mindestens 1 Kind da ist (ChildAdded ODER Polling)
    if #itemsList:GetChildren() == 0 then
        local filled = false
        local conn
        conn = itemsList.ChildAdded:Connect(function()
            filled = true
            if conn then conn:Disconnect(); conn = nil end
        end)
        local tEnd = os.clock() + timeoutSec
        while os.clock() < tEnd and AF.Running and not filled do
            task.wait(0.1)
        end
        if conn then pcall(function() conn:Disconnect() end) end
    end

    return itemsList
end

-- ============================================================
--  ITEMSLIST PARSEN
-- ============================================================
local function ParseItemsList(itemsList)
    local items = {}
    if not itemsList then return items end
    for _, info in ipairs(itemsList:GetChildren()) do
        pcall(function()
            local inf   = info:FindFirstChild("Info"); if not inf then return end
            local nameV = inf:FindFirstChild("ItemNames")
            local rateV = inf:FindFirstChild("DropRate")
            local amtV  = inf:FindFirstChild("DropAmount")
            local iname = nameV and tostring(nameV.Value) or info.Name
            local rate  = rateV and tonumber(rateV.Value) or 0
            local amt   = amtV  and tonumber(amtV.Value)  or 1
            if iname and iname ~= "" then
                items[iname] = { dropRate=rate, dropAmount=amt }
                print(string.format("[HazeHub] Item gefunden: %s (Rate: %.1f%%)", iname, rate))
            end
        end)
    end
    return items
end

-- ============================================================
--  WELT-BUTTON SIMULIEREN  (MouseButton1Click feuern)
-- ============================================================
local function SimulateChapterClick(chapFolder, chapId)
    if not chapFolder then return false end
    local success = false
    pcall(function()
        -- Direkte Suche im Chapter-Ordner und seinen Unterordnern
        local btn = chapFolder:FindFirstChild(chapId, true)
        if btn then
            btn.MouseButton1Click:Fire()
            success = true
            return
        end
        -- Fallback: Weltordner durchsuchen
        for _, worldFolder in ipairs(chapFolder:GetChildren()) do
            local b = worldFolder:FindFirstChild(chapId)
            if b then
                b.MouseButton1Click:Fire()
                success = true
                return
            end
        end
    end)
    return success
end

-- ============================================================
--  MODUL-STATUS IM HAUPT-GUI SETZEN
-- ============================================================
local function SetMainModulStatus(text, color)
    pcall(function()
        local sg = game:GetService("Players").LocalPlayer.PlayerGui
        local ml = sg:FindFirstChild("ModulStatus", true)
        if ml then
            ml.Text       = text
            ml.TextColor3 = color or D.TextMid
        end
    end)
end

-- ============================================================
--  STATUS SETZEN  (eigenes Label + Haupt-GUI)
-- ============================================================
local function SetStatus(text, color)
    pcall(function()
        AF.UI.Lbl.Status.Text       = text
        AF.UI.Lbl.Status.TextColor3 = color or D.TextMid
    end)
    SetMainModulStatus(text, color)
end

-- ============================================================
--  SCAN FORTSCHRITT ANZEIGEN
-- ============================================================
local function SetScanProgress(current, total, chapId, worldId)
    local text = string.format("🔍 Scanne %d/%d – %s", current, total, chapId)
    pcall(function()
        if AF.UI.Lbl.ScanProgress then
            AF.UI.Lbl.ScanProgress.Text       = text
            AF.UI.Lbl.ScanProgress.TextColor3 = D.Yellow
        end
        if AF.UI.Fr.ScanProgressFrame then
            AF.UI.Fr.ScanProgressFrame.Visible = true
        end
    end)
    SetMainModulStatus(string.format("🔍 Scanne %d/%d Chapters...", current, total), D.Yellow)
    print(string.format("[HazeHub] Scanne Welt: %s...  (Chapter: %s,  %d/%d)",
        worldId, chapId, current, total))
end

-- ============================================================
--  HAUPT-SCAN-FUNKTION  (klick-basiert + ChildAdded)
-- ============================================================
local function ScanAllRewards(onProgress)
    if AF.Scanning then
        warn("[HazeHub] Scan laeuft bereits!"); return false
    end
    if not HS.IsScanDone() then
        local msg = "Welten noch nicht geladen! Bitte Game-Tab oeffnen."
        pcall(function() onProgress("⚠ " .. msg) end)
        warn("[HazeHub] " .. msg); return false
    end

    AF.Scanning = true
    AF.RewardDB = {}

    local WorldData = HS.GetWorldData()
    local WorldIds  = HS.GetWorldIds()
    local total, scanned, skipped = 0, 0, 0

    for _, wid in ipairs(WorldIds) do
        local wd = WorldData[wid] or {}
        total = total + #(wd.story or {}) + #(wd.ranger or {})
    end

    print(string.format("[HazeHub] === SCAN GESTARTET: %d Chapters geplant ===", total))

    -- Chapter-Ordner fuer Klick-Simulation
    local chapFolder = GetChapterFolder()
    if chapFolder then
        print("[HazeHub] Chapter-Ordner gefunden: " .. chapFolder:GetFullName())
    else
        warn("[HazeHub] Chapter-Ordner nicht gefunden – nur Remote-Methode.")
    end

    for _, wid in ipairs(WorldIds) do
        if not AF.Running or not AF.Scanning then break end

        local wd = WorldData[wid] or {}
        local chapters = {}
        for _, cid in ipairs(wd.story  or {}) do table.insert(chapters, {id=cid, mode="Story"})  end
        for _, cid in ipairs(wd.ranger or {}) do table.insert(chapters, {id=cid, mode="Ranger"}) end

        for _, chap in ipairs(chapters) do
            if not AF.Running or not AF.Scanning then break end
            scanned = scanned + 1

            SetScanProgress(scanned, total, chap.id, wid)
            pcall(function() onProgress(string.format("⏳ %d/%d – %s", scanned, total, chap.id)) end)

            -- SCHRITT 1: Welt/Modus per Remote wechseln
            pcall(function()
                if chap.mode == "Story" then
                    PR("Change-World", {World = wid})
                elseif chap.mode == "Ranger" then
                    PR("Change-Mode", {KeepWorld = wid, Mode = "Ranger Stage"})
                end
                task.wait(0.2)
                PR("Change-Chapter", {Chapter = chap.id})
            end)

            -- SCHRITT 2: GUI-Button klick simulieren
            if chapFolder then
                local clicked = SimulateChapterClick(chapFolder, chap.id)
                if clicked then
                    print(string.format("[HazeHub] GUI-Klick simuliert: %s", chap.id))
                end
            end

            -- SCHRITT 3: Warten bis ItemsList sich fuellt (ChildAdded-basiert)
            local itemsList = WaitForItemsListFilled(2.5)
            local items     = ParseItemsList(itemsList)
            local itemCount = 0; for _ in pairs(items) do itemCount = itemCount + 1 end

            if itemCount > 0 then
                AF.RewardDB[chap.id] = {world=wid, mode=chap.mode, items=items}
                print(string.format("[HazeHub] OK: %s – %d Items gespeichert.", chap.id, itemCount))
            else
                skipped = skipped + 1
                warn(string.format("[HazeHub] Timeout/Leer: %s uebersprungen.", chap.id))
                pcall(function() onProgress("⚠ Timeout: " .. chap.id) end)
            end

            task.wait(0.4)
        end
    end

    print("[HazeHub] Speichere Datenbank...")
    SaveDB()
    AF.Scanning = false

    local finalMsg = string.format(
        "✅ Scan fertig: %d/%d Chapters  (%d Timeouts)", DBCount(), total, skipped)
    print("[HazeHub] " .. finalMsg)
    pcall(function() onProgress(finalMsg) end)
    pcall(function()
        if AF.UI.Lbl.ScanProgress then
            AF.UI.Lbl.ScanProgress.Text       = finalMsg
            AF.UI.Lbl.ScanProgress.TextColor3 = D.Green
        end
    end)
    SetMainModulStatus("🟢  Autofarm v"..VERSION.." – DB: "..DBCount().." Chapters", D.Green)
    return true
end

-- ============================================================
--  BEST CHAPTER SUCHEN
-- ============================================================
local function FindBestChapter(itemName)
    local best, bestRate, bestWorld, bestMode = nil, -1, nil, nil
    for chapId, data in pairs(AF.RewardDB) do
        if data.items and data.items[itemName] then
            local r = data.items[itemName].dropRate or 0
            if r > bestRate then
                bestRate=r; best=chapId; bestWorld=data.world; bestMode=data.mode
            end
        end
    end
    if best then
        print(string.format("[HazeHub] Ziel-Item gefunden in Welt: %s  Kapitel: %s  (DropRate: %.1f%%)",
            bestWorld, best, bestRate))
    else
        warn(string.format("[HazeHub] Kein Chapter fuer '%s' in DB.", itemName))
    end
    return best, bestWorld, bestMode, bestRate
end

-- ============================================================
--  REMOTE ABFOLGE  (exakte Reihenfolge + Pausen)
-- ============================================================
local function FireRoomSequence(worldId, mode, chapId)
    print(string.format("[HazeHub] Starte Raum: %s | %s | %s", worldId, mode, chapId))
    task.spawn(function()
        pcall(function()
            PR("Create");                                           task.wait(0.3)
            if     mode == "Story"    then PR("Change-World", {World=worldId})
            elseif mode == "Ranger"   then PR("Change-Mode", {KeepWorld=worldId, Mode="Ranger Stage"})
            elseif mode == "Calamity" then PR("Change-Mode", {Mode="Calamity"}) end
                                                                    task.wait(0.3)
            PR("Change-Chapter", {Chapter=chapId});                 task.wait(0.3)
            PR("Submit");                                           task.wait(0.5)
            PR("Start")
            print("[HazeHub] Raum-Sequenz abgeschlossen.")
        end)
    end)
end

-- ============================================================
--  QUEUE UI UPDATE
-- ============================================================
local function UpdateQueueUI()
    if not AF.UI.Fr.List then return end
    for _, v in pairs(AF.UI.Fr.List:GetChildren()) do
        if v:IsA("Frame") then v:Destroy() end
    end
    if AF.UI.Lbl.QueueEmpty then
        AF.UI.Lbl.QueueEmpty.Visible = (#AF.Queue == 0)
    end

    local function NextItem()
        for _, q in ipairs(AF.Queue) do if not q.done then return q end end
        return nil
    end

    for i, q in ipairs(AF.Queue) do
        local inv    = GetInvAmt(q.item)
        local pct    = math.min(1, inv / math.max(1, q.amount))
        local isNext = (not q.done) and (NextItem() == q)

        local row = Instance.new("Frame", AF.UI.Fr.List)
        row.Size = UDim2.new(1,0,0,44); row.BorderSizePixel = 0; Corner(row,8)
        if q.done then
            row.BackgroundColor3 = D.GreenDark; Stroke(row, D.GreenBright, 1.5, 0)
        elseif isNext then
            row.BackgroundColor3 = Color3.fromRGB(0,30,55); Stroke(row, D.Cyan, 1.5, 0)
        else
            row.BackgroundColor3 = D.Card; Stroke(row, D.Border, 1, 0.4)
        end

        local barC = q.done and D.GreenBright or (isNext and D.Cyan or D.Purple)
        local bar  = Instance.new("Frame", row)
        bar.Size = UDim2.new(0,3,0.65,0); bar.Position = UDim2.new(0,0,0.175,0)
        bar.BackgroundColor3 = barC; bar.BorderSizePixel = 0; Corner(bar,2)

        local pgBg = Instance.new("Frame", row)
        pgBg.Size = UDim2.new(1,-52,0,3); pgBg.Position = UDim2.new(0,8,1,-6)
        pgBg.BackgroundColor3 = Color3.fromRGB(28,38,62); pgBg.BorderSizePixel = 0; Corner(pgBg,2)
        local pgF = Instance.new("Frame", pgBg)
        pgF.Size = UDim2.new(pct,0,1,0); pgF.BackgroundColor3 = barC
        pgF.BorderSizePixel = 0; Corner(pgF,2)

        local nL = Instance.new("TextLabel", row)
        nL.Position = UDim2.new(0,12,0,5); nL.Size = UDim2.new(1,-52,0.5,-3)
        nL.BackgroundTransparency = 1
        nL.Text = (isNext and "▶ " or "") .. (q.done and "✅ " or "") .. q.item
        nL.TextColor3 = q.done and D.GreenBright or (isNext and D.Cyan or D.TextHi)
        nL.TextSize = 11; nL.Font = Enum.Font.GothamBold
        nL.TextXAlignment = Enum.TextXAlignment.Left
        nL.TextTruncate = Enum.TextTruncate.AtEnd

        local pL = Instance.new("TextLabel", row)
        pL.Position = UDim2.new(0,12,0.5,1); pL.Size = UDim2.new(1,-52,0.5,-5)
        pL.BackgroundTransparency = 1
        pL.Text = inv .. " / " .. q.amount .. "  (" .. math.floor(pct*100) .. "%)"
        pL.TextColor3 = q.done and D.GreenBright or D.TextMid
        pL.TextSize = 10; pL.Font = Enum.Font.GothamSemibold
        pL.TextXAlignment = Enum.TextXAlignment.Left

        local ci = i
        local xBtn = Instance.new("TextButton", row)
        xBtn.Size = UDim2.new(0,34,0,34); xBtn.Position = UDim2.new(1,-38,0.5,-17)
        xBtn.BackgroundColor3 = Color3.fromRGB(50,12,12); xBtn.Text = "✕"
        xBtn.TextColor3 = D.Red; xBtn.TextSize = 13; xBtn.Font = Enum.Font.GothamBold
        xBtn.AutoButtonColor = false; xBtn.BorderSizePixel = 0
        Corner(xBtn,7); Stroke(xBtn,D.Red,1,0.4)
        xBtn.MouseEnter:Connect(function() Tw(xBtn,{BackgroundColor3=D.RedDark}) end)
        xBtn.MouseLeave:Connect(function() Tw(xBtn,{BackgroundColor3=Color3.fromRGB(50,12,12)}) end)
        xBtn.MouseButton1Click:Connect(function()
            table.remove(AF.Queue, ci); SaveQueue(); UpdateQueueUI()
        end)
    end
end

-- ============================================================
--  FARM LOOP
-- ============================================================
local function GetNextItem()
    for _, q in ipairs(AF.Queue) do if not q.done then return q end end
    return nil
end

local function FarmLoop()
    AF.Active = true
    print("[HazeHub] === FARM LOOP GESTARTET ===")
    while AF.Running do
        local q = GetNextItem()
        if not q then
            AF.Active = false
            SetStatus("✅  Queue fertig!", D.Green)
            print("[HazeHub] Queue vollstaendig abgearbeitet.")
            break
        end

        local chapId, worldId, mode, rate = FindBestChapter(q.item)

        -- Fallback: erstes verfuegbares Chapter
        if not chapId then
            local ids = HS.GetWorldIds()
            if #ids > 0 then
                local wd = HS.GetWorldData()[ids[1]] or {}
                if wd.story and #wd.story > 0 then
                    chapId=wd.story[1]; worldId=ids[1]; mode="Story"; rate=0
                    warn(string.format("[HazeHub] Fallback: %s (Item '%s' nicht in DB)", chapId, q.item))
                end
            end
        end

        if not chapId then
            SetStatus("⚠ Kein Chapter fuer '" .. q.item .. "'", D.Orange)
            task.wait(3); q.done=true; pcall(UpdateQueueUI); continue
        end

        SetStatus(string.format("🚀 Farm: %s → %s  (%.1f%%)", q.item, chapId, rate or 0), D.Cyan)
        FireRoomSequence(worldId, mode, chapId)

        local deadline = os.time() + 600
        local goalMet  = false
        while AF.Running and os.time() < deadline do
            task.wait(5)
            local cur = GetInvAmt(q.item)
            SetStatus(string.format("📊 %s: %d / %d  (%.0f%%)",
                q.item, cur, q.amount, math.min(100, cur/math.max(1,q.amount)*100)), D.Cyan)
            pcall(UpdateQueueUI)
            pcall(function() HS.UpdateGoalsUI() end)
            if cur >= q.amount then goalMet = true; break end
        end

        if goalMet then
            q.done = true; SaveQueue(); pcall(UpdateQueueUI)
            local cur = GetInvAmt(q.item)
            print(string.format("[HazeHub] Ziel erreicht: %s (%d/%d)", q.item, cur, q.amount))
            task.spawn(function() pcall(function() SendWebhook({}, q.item, cur) end) end)
            SetStatus("🏠 Ziel erreicht – Back To Lobby...", D.Yellow)
            task.wait(2); ClickBackToLobby()
            local lw = 0
            while AF.Running and not IsInLobby() and lw < 15 do task.wait(1); lw=lw+1 end
            task.wait(2)
        else
            warn(string.format("[HazeHub] Timeout fuer '%s' – naechstes Item.", q.item))
            SetStatus("⚠ Timeout – naechstes Item...", D.Orange)
            task.wait(2)
        end
    end
    AF.Active = false
end

-- Auto-Restart nach Lobby-Rueckkehr
task.spawn(function()
    local wasInGame = false
    while AF.Running do
        task.wait(3)
        local inLobby = IsInLobby()
        if wasInGame and inLobby then
            wasInGame = false
            if #AF.Queue > 0 and GetNextItem() and not AF.Active then
                task.wait(3)
                if AF.Running then task.spawn(FarmLoop) end
            end
        end
        if not inLobby then wasInGame = true end
    end
end)

task.spawn(function()
    while AF.Running do task.wait(5); pcall(UpdateQueueUI) end
end)

-- ============================================================
--  STOP
-- ============================================================
local function StopFarm()
    AF.Active   = false
    AF.Running  = false
    AF.Scanning = false
    SetStatus("⏹  Auto-Farm gestoppt", D.TextMid)
    print("[HazeHub] Auto-Farm gestoppt.")
end
HS.StopFarm = StopFarm

-- ============================================================
--  GUI AUFBAUEN
-- ============================================================

-- STATUS CARD
local sCard = Card(Container, 36); Pad(sCard, 6, 10, 6, 10)
AF.UI.Lbl.Status = Instance.new("TextLabel", sCard)
AF.UI.Lbl.Status.Size               = UDim2.new(1,0,1,0)
AF.UI.Lbl.Status.BackgroundTransparency = 1
AF.UI.Lbl.Status.Text               = "⏹  Auto-Farm gestoppt"
AF.UI.Lbl.Status.TextColor3         = D.TextMid
AF.UI.Lbl.Status.TextSize           = 11
AF.UI.Lbl.Status.Font               = Enum.Font.GothamSemibold
AF.UI.Lbl.Status.TextXAlignment     = Enum.TextXAlignment.Left

-- REWARD-DB KARTE
local dbCard = Card(Container); Pad(dbCard, 10, 10, 10, 10); VList(dbCard, 6)
SecLbl(dbCard, "🗃  REWARD-DATENBANK")

AF.UI.Lbl.DBStatus = MkLbl(dbCard, "Keine DB geladen.", 11, D.TextLow)
AF.UI.Lbl.DBStatus.Size = UDim2.new(1,0,0,18)

-- Scan-Fortschritts-Frame (wird waehrend Scan sichtbar)
local spFrame = Instance.new("Frame", dbCard)
spFrame.Size = UDim2.new(1,0,0,18); spFrame.BackgroundTransparency = 1; spFrame.Visible = false
AF.UI.Fr.ScanProgressFrame = spFrame
AF.UI.Lbl.ScanProgress = Instance.new("TextLabel", spFrame)
AF.UI.Lbl.ScanProgress.Size               = UDim2.new(1,0,1,0)
AF.UI.Lbl.ScanProgress.BackgroundTransparency = 1
AF.UI.Lbl.ScanProgress.Text               = ""
AF.UI.Lbl.ScanProgress.TextColor3         = D.Yellow
AF.UI.Lbl.ScanProgress.TextSize           = 10
AF.UI.Lbl.ScanProgress.Font               = Enum.Font.Gotham
AF.UI.Lbl.ScanProgress.TextXAlignment     = Enum.TextXAlignment.Left
AF.UI.Lbl.ScanProgress.TextTruncate       = Enum.TextTruncate.AtEnd

-- Zwei kleine Buttons: DB laden + Neu scannen
local dbBtnRow = Instance.new("Frame", dbCard)
dbBtnRow.Size = UDim2.new(1,0,0,30); dbBtnRow.BackgroundTransparency = 1; HList(dbBtnRow, 6)

local loadDbBtn = Instance.new("TextButton", dbBtnRow)
loadDbBtn.Size = UDim2.new(0.48,0,0,30); loadDbBtn.BackgroundColor3 = D.CardHover
loadDbBtn.Text = "📂  DB laden"; loadDbBtn.TextColor3 = D.CyanDim
loadDbBtn.TextSize = 11; loadDbBtn.Font = Enum.Font.GothamBold
loadDbBtn.AutoButtonColor = false; loadDbBtn.BorderSizePixel = 0
Corner(loadDbBtn, 7); Stroke(loadDbBtn, D.CyanDim, 1, 0.3)
loadDbBtn.MouseEnter:Connect(function() Tw(loadDbBtn,{BackgroundColor3=Color3.fromRGB(0,50,80)}) end)
loadDbBtn.MouseLeave:Connect(function() Tw(loadDbBtn,{BackgroundColor3=D.CardHover}) end)

local scanDbBtn = Instance.new("TextButton", dbBtnRow)
scanDbBtn.Size = UDim2.new(0.48,0,0,30); scanDbBtn.BackgroundColor3 = D.CardHover
scanDbBtn.Text = "🔍  Neu scannen"; scanDbBtn.TextColor3 = D.Purple
scanDbBtn.TextSize = 11; scanDbBtn.Font = Enum.Font.GothamBold
scanDbBtn.AutoButtonColor = false; scanDbBtn.BorderSizePixel = 0
Corner(scanDbBtn, 7); Stroke(scanDbBtn, D.Purple, 1, 0.3)
scanDbBtn.MouseEnter:Connect(function() Tw(scanDbBtn,{BackgroundColor3=Color3.fromRGB(40,10,70)}) end)
scanDbBtn.MouseLeave:Connect(function() Tw(scanDbBtn,{BackgroundColor3=D.CardHover}) end)

-- ★ FORCE RESCAN BUTTON (grosser, auffaelliger, eigene Zeile) ★
local forceRescanBtn = Instance.new("TextButton", dbCard)
forceRescanBtn.Size             = UDim2.new(1,0,0,36)
forceRescanBtn.BackgroundColor3 = Color3.fromRGB(75, 15, 115)
forceRescanBtn.Text             = "🗑  Datenbank loeschen & NEU SCANNEN"
forceRescanBtn.TextColor3       = Color3.new(1,1,1)
forceRescanBtn.TextSize         = 12
forceRescanBtn.Font             = Enum.Font.GothamBold
forceRescanBtn.AutoButtonColor  = false
forceRescanBtn.BorderSizePixel  = 0
Corner(forceRescanBtn, 8)
Stroke(forceRescanBtn, D.Purple, 2, 0)
forceRescanBtn.MouseEnter:Connect(function()
    Tw(forceRescanBtn, {BackgroundColor3=Color3.fromRGB(120, 30, 180)})
end)
forceRescanBtn.MouseLeave:Connect(function()
    Tw(forceRescanBtn, {BackgroundColor3=Color3.fromRGB(75, 15, 115)})
end)
forceRescanBtn.MouseButton1Down:Connect(function()
    Tw(forceRescanBtn, {BackgroundColor3=Color3.fromRGB(45, 8, 80)})
end)
forceRescanBtn.MouseButton1Up:Connect(function()
    Tw(forceRescanBtn, {BackgroundColor3=Color3.fromRGB(120, 30, 180)})
end)

-- SCAN TASK FUNKTION
local function StartScanTask(forceDelete)
    if AF.Scanning then
        SetStatus("⚠ Scan laeuft bereits!", D.Yellow); return
    end
    task.spawn(function()
        if forceDelete then
            ClearDB()
            pcall(function()
                AF.UI.Lbl.DBStatus.Text       = "🗑 DB geloescht – Scan startet..."
                AF.UI.Lbl.DBStatus.TextColor3 = D.Orange
            end)
            task.wait(0.5)
        end
        spFrame.Visible        = true
        scanDbBtn.Text         = "⏳ Scannt..."
        scanDbBtn.TextColor3   = D.Yellow
        forceRescanBtn.Text    = "⏳ Scannt..."
        SetStatus("🔍 Scan laeuft...", D.Purple)

        local ok = ScanAllRewards(function(msg)
            pcall(function()
                AF.UI.Lbl.DBStatus.Text       = msg
                AF.UI.Lbl.DBStatus.TextColor3 = D.Yellow
            end)
        end)

        local c = DBCount()
        local resultText  = ok and string.format("✅  %d Chapters gescannt", c) or "⚠  Scan fehlgeschlagen"
        local resultColor = ok and D.Green or D.Orange
        pcall(function()
            AF.UI.Lbl.DBStatus.Text       = resultText
            AF.UI.Lbl.DBStatus.TextColor3 = resultColor
            spFrame.Visible               = false
            scanDbBtn.Text                = "🔍  Neu scannen"
            scanDbBtn.TextColor3          = D.Purple
            forceRescanBtn.Text           = "🗑  Datenbank loeschen & NEU SCANNEN"
        end)
        SetStatus(ok and "✅ Scan fertig!" or "⚠ Scan fehlgeschlagen", resultColor)
    end)
end

loadDbBtn.MouseButton1Click:Connect(function()
    if LoadDB() then
        AF.UI.Lbl.DBStatus.Text       = string.format("✅  DB: %d Chapters geladen", DBCount())
        AF.UI.Lbl.DBStatus.TextColor3 = D.Green
    else
        AF.UI.Lbl.DBStatus.Text       = "⚠  Keine gueltige DB. Bitte neu scannen."
        AF.UI.Lbl.DBStatus.TextColor3 = D.Orange
    end
end)

scanDbBtn.MouseButton1Click:Connect(function()
    StartScanTask(false)
end)

forceRescanBtn.MouseButton1Click:Connect(function()
    StartScanTask(true)
end)

-- QUEUE KARTE
local qCard = Card(Container); Pad(qCard, 10, 10, 10, 10); VList(qCard, 8)
SecLbl(qCard, "📋  AUTO-FARM QUEUE")

local qRow = Instance.new("Frame", qCard)
qRow.Size = UDim2.new(1,0,0,30); qRow.BackgroundTransparency = 1; HList(qRow, 5)
local qItemOuter, qItemBox = MkInput(qRow, "Item-Name..."); qItemOuter.Size = UDim2.new(0.50,0,0,30)
local qAmtOuter,  qAmtBox  = MkInput(qRow, "Anzahl");       qAmtOuter.Size  = UDim2.new(0.28,0,0,30)

local qAddBtn = Instance.new("TextButton", qRow)
qAddBtn.Size = UDim2.new(0.19,0,0,30); qAddBtn.BackgroundColor3 = D.Green
qAddBtn.Text = "+ Add"; qAddBtn.TextColor3 = Color3.new(1,1,1); qAddBtn.TextSize = 11
qAddBtn.Font = Enum.Font.GothamBold; qAddBtn.AutoButtonColor = false; qAddBtn.BorderSizePixel = 0
Corner(qAddBtn, 7); Stroke(qAddBtn, D.Green, 1, 0.2)
qAddBtn.MouseEnter:Connect(function() Tw(qAddBtn,{BackgroundColor3=Color3.fromRGB(0,160,80)}) end)
qAddBtn.MouseLeave:Connect(function() Tw(qAddBtn,{BackgroundColor3=D.Green}) end)

AF.UI.Fr.List = Instance.new("Frame", qCard)
AF.UI.Fr.List.Size = UDim2.new(1,0,0,0); AF.UI.Fr.List.AutomaticSize = Enum.AutomaticSize.Y
AF.UI.Fr.List.BackgroundTransparency = 1; VList(AF.UI.Fr.List, 4)
AF.UI.Lbl.QueueEmpty = MkLbl(AF.UI.Fr.List, "Queue leer. Item + Anzahl eintragen.", 11, D.TextLow)
AF.UI.Lbl.QueueEmpty.Size = UDim2.new(1,0,0,24)

qAddBtn.MouseButton1Click:Connect(function()
    local iname = (qItemBox.Text or ""):match("^%s*(.-)%s*$")
    local iamt  = tonumber(qAmtBox.Text)
    if iname == "" or not iamt or iamt <= 0 then return end
    local found = false
    for _, g in ipairs(ST.Goals) do if g.item == iname then found=true; break end end
    if not found then
        table.insert(ST.Goals, {item=iname, amount=iamt, reached=false}); SaveConfig()
    end
    table.insert(AF.Queue, {item=iname, amount=iamt, done=false})
    SaveQueue(); qItemBox.Text=""; qAmtBox.Text=""
    UpdateQueueUI(); pcall(function() HS.UpdateGoalsUI() end)
    print(string.format("[HazeHub] Queue: '%s' (x%d) hinzugefuegt.", iname, iamt))
end)

-- STEUERUNG
local ctrlRow = Instance.new("Frame", qCard)
ctrlRow.Size = UDim2.new(1,0,0,32); ctrlRow.BackgroundTransparency = 1; HList(ctrlRow, 8)

local startBtn = Instance.new("TextButton", ctrlRow)
startBtn.Size = UDim2.new(0.48,0,0,32); startBtn.BackgroundColor3 = D.Green
startBtn.Text = "▶  Start Queue"; startBtn.TextColor3 = Color3.new(1,1,1)
startBtn.TextSize = 12; startBtn.Font = Enum.Font.GothamBold
startBtn.AutoButtonColor = false; startBtn.BorderSizePixel = 0
Corner(startBtn, 8); Stroke(startBtn, D.Green, 1, 0.2)

local stopBtn = Instance.new("TextButton", ctrlRow)
stopBtn.Size = UDim2.new(0.48,0,0,32); stopBtn.BackgroundColor3 = D.RedDark
stopBtn.Text = "⏹  Stop"; stopBtn.TextColor3 = D.Red
stopBtn.TextSize = 12; stopBtn.Font = Enum.Font.GothamBold
stopBtn.AutoButtonColor = false; stopBtn.BorderSizePixel = 0
Corner(stopBtn, 8); Stroke(stopBtn, D.Red, 1, 0.4)

-- ★ QUEUE START VALIDIERUNG ★
startBtn.MouseButton1Click:Connect(function()
    if AF.Active then
        SetStatus("⚠ Farm laeuft bereits!", D.Yellow)
        warn("[HazeHub] Start: Farm laeuft bereits."); return
    end
    if #AF.Queue == 0 then
        SetStatus("⚠ Queue ist leer!", D.Orange)
        warn("[HazeHub] Start: Queue leer."); return
    end

    -- DB-Pruefung: LEER = Warnung + Abbruch
    if DBCount() == 0 then
        SetStatus("⚠ Bitte zuerst scannen!", D.Orange)
        pcall(function()
            AF.UI.Lbl.DBStatus.Text       = "⚠  DB leer – erst scannen!"
            AF.UI.Lbl.DBStatus.TextColor3 = D.Orange
        end)
        -- Blink-Hinweis auf Force-Rescan Button
        task.spawn(function()
            for _ = 1, 5 do
                Tw(forceRescanBtn, {BackgroundColor3=Color3.fromRGB(160, 40, 220)}); task.wait(0.18)
                Tw(forceRescanBtn, {BackgroundColor3=Color3.fromRGB(75, 15, 115)});  task.wait(0.18)
            end
        end)
        warn("[HazeHub] Start abgebrochen: DB ist leer!"); return
    end

    -- Alles ok
    AF.Running = true
    print(string.format("[HazeHub] Queue gestartet: %d Items, DB: %d Chapters",
        #AF.Queue, DBCount()))
    task.spawn(FarmLoop)
end)

stopBtn.MouseButton1Click:Connect(function()
    AF.Running = false
    StopFarm()
    startBtn.Text       = "▶  Start Queue"
    startBtn.TextColor3 = Color3.new(1,1,1)
end)

local clearBtn = NeonBtn(qCard, "🗑  Queue leeren", D.Red, 28)
clearBtn.MouseButton1Click:Connect(function()
    AF.Queue = {}; SaveQueue(); UpdateQueueUI()
    print("[HazeHub] Queue geleert.")
end)

-- ============================================================
--  STARTUP
-- ============================================================
LoadQueue()

-- DB beim Start pruefen
if isfile and isfile(DB_FILE) then
    local raw; pcall(function() raw = readfile(DB_FILE) end)
    if raw and #raw < 10 then
        warn("[HazeHub] HazeHUB_RewardDB.json ist leer/korrupt (<10 Bytes)!")
        AF.UI.Lbl.DBStatus.Text       = "⚠  DB korrupt – Neu-Scan noetig!"
        AF.UI.Lbl.DBStatus.TextColor3 = D.Orange
    elseif LoadDB() then
        AF.UI.Lbl.DBStatus.Text       = string.format("✅  DB: %d Chapters geladen", DBCount())
        AF.UI.Lbl.DBStatus.TextColor3 = D.Green
    end
else
    AF.UI.Lbl.DBStatus.Text       = "Keine DB. Bitte scannen."
    AF.UI.Lbl.DBStatus.TextColor3 = D.TextLow
end

UpdateQueueUI()

-- Modul erfolgreich geladen
_G.HazeShared.SetModuleLoaded(VERSION)
print("[HazeHub] autofarm.lua v" .. VERSION .. " geladen ✅  |  DB: " .. DBCount() .. " Chapters")
