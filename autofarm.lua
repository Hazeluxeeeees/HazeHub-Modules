-- ╔══════════════════════════════════════════════════════════╗
--  HazeHUB – autofarm.lua  v1.4.0
--  GitHub: Hazeluxeeeees/HazeHub-Modules
--  Active-Selection Scan: Create→Change→Wait→Read→Reset
--  VirtualInput Backup, DB-Integrität, Fortschritts-GUI
-- ╚══════════════════════════════════════════════════════════╝

local VERSION = "1.4.0"

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
local GetInvAmt        = HS.GetInvAmt
local IsInLobby        = HS.IsInLobby
local ClickBackToLobby = HS.ClickBackToLobby
local SaveConfig       = HS.SaveConfig
local SendWebhook      = HS.SendWebhook

local Container = HS.Container

-- ============================================================
--  SERVICES
-- ============================================================
local VIM = game:GetService("VirtualInputManager")
local LP  = game:GetService("Players").LocalPlayer
local RS  = game:GetService("ReplicatedStorage")

-- ============================================================
--  REMOTES  (direkte Referenz, robuster als PR-Wrapper)
-- ============================================================
local REM = {}
task.spawn(function()
    pcall(function()
        local root = RS:WaitForChild("Remote", 10)
        REM.PlayRoomEvent = root
            :WaitForChild("Server", 10)
            :WaitForChild("PlayRoom", 10)
            :WaitForChild("Event", 10)
    end)
    pcall(function()
        REM.VoteRetry = RS
            :WaitForChild("Remote",  10)
            :WaitForChild("Server",  10)
            :WaitForChild("OnGame",  10)
            :WaitForChild("Voting",  10)
            :WaitForChild("VoteRetry", 10)
    end)
end)

-- Sicheres FireServer mit Fallback auf PR-Wrapper
local function Fire(action, data)
    local ok = false
    if REM.PlayRoomEvent then
        ok = pcall(function()
            if data then REM.PlayRoomEvent:FireServer(action, data)
            else         REM.PlayRoomEvent:FireServer(action) end
        end)
    end
    if not ok then PR(action, data) end  -- Fallback
end

-- ============================================================
--  STATE
-- ============================================================
local AF = {
    Queue          = {},
    Active         = false,
    Running        = true,
    Scanning       = false,
    RewardDatabase = {},
    UI             = { Lbl={}, Fr={}, Btn={} },
}

local DB_FILE   = "HazeHUB/HazeHUB_RewardDB.json"
local QUEUE_KEY = "SavedQueue"

-- ============================================================
--  UTIL
-- ============================================================
local function DBCount()
    local c = 0
    for _ in pairs(AF.RewardDatabase) do c = c + 1 end
    return c
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
--  SCAN-FORTSCHRITT
-- ============================================================
local function SetScanProgress(current, total, label)
    local pct = math.max(0, math.min(1, current / math.max(1, total)))
    local txt = string.format("%s  (%d/%d  –  %.0f%%)", label, current, total, pct * 100)

    pcall(function()
        AF.UI.Lbl.ScanProgress.Text       = txt
        AF.UI.Lbl.ScanProgress.TextColor3 = D.Yellow
        AF.UI.Fr.ScanBar.Visible          = true
        -- Balken animiert
        Tw(AF.UI.Fr.ScanBarFill, {Size = UDim2.new(pct, 0, 1, 0)}, TF)
    end)
    SetMainStatus(txt, D.Yellow)
end

local function SetScanDone(success, count, total, skipped)
    local txt = success
        and string.format("OK  %d/%d Chapters  (%d Timeouts)", count, total, skipped)
        or  "Scan fehlgeschlagen"
    local col = success and D.Green or D.Orange
    pcall(function()
        AF.UI.Lbl.ScanProgress.Text       = txt
        AF.UI.Lbl.ScanProgress.TextColor3 = col
        Tw(AF.UI.Fr.ScanBarFill, {
            Size             = UDim2.new(success and 1 or 0, 0, 1, 0),
            BackgroundColor3 = col,
        }, TM)
        AF.UI.Lbl.DBStatus.Text       = txt
        AF.UI.Lbl.DBStatus.TextColor3 = col
        AF.UI.Btn.ForceRescan.Text    = "DATENBANK NEU SCANNEN"
        AF.UI.Btn.ForceRescan.TextColor3 = Color3.new(1, 1, 1)
    end)
    SetMainStatus("Autofarm v" .. VERSION .. "  –  DB: " .. DBCount() .. " Chapters", col)
end

-- ============================================================
--  QUEUE / DB PERSISTENZ
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

local function SaveDB()
    if not writefile then
        warn("[HazeHub] writefile nicht verfuegbar – DB nicht gespeichert.")
        return
    end
    pcall(function()
        local enc = Svc.Http:JSONEncode(AF.RewardDatabase)
        writefile(DB_FILE, enc)
        print(string.format("[HazeHub] DB gespeichert: %d Bytes, %d Chapters.", #enc, DBCount()))
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
    print("[HazeHub] Datenbank geleert.")
end

-- ============================================================
--  ITEMSLIST-PFAD FINDEN
-- ============================================================
local function GetItemsList(timeoutSec)
    local result = nil
    local deadline = os.clock() + (timeoutSec or 4)
    while os.clock() < deadline and AF.Running do
        pcall(function()
            result = LP.PlayerGui
                :WaitForChild("PlayRoom",   1)
                :WaitForChild("Main",       1)
                :WaitForChild("GameStage",  1)
                :WaitForChild("Main",       1)
                :WaitForChild("Base",       1)
                :WaitForChild("Rewards",    1)
                :WaitForChild("ItemsList",  1)
        end)
        if result and result.Parent then break end
        result = nil; task.wait(0.2)
    end
    return result
end

-- ============================================================
--  AUF ITEMS WARTEN  (ChildAdded-Event + Polling-Fallback)
-- ============================================================
local function WaitForItems(itemsList, timeoutSec)
    if not itemsList then return false end
    timeoutSec = timeoutSec or 3

    -- Sofortcheck: schon Kinder vorhanden?
    if #itemsList:GetChildren() > 0 then return true end

    local filled  = false
    local conn    = itemsList.ChildAdded:Connect(function()
        filled = true
    end)

    local deadline = os.clock() + timeoutSec
    while os.clock() < deadline and AF.Running and not filled do
        -- Polling-Fallback
        if #itemsList:GetChildren() > 0 then filled = true; break end
        task.wait(0.15)
    end

    pcall(function() conn:Disconnect() end)
    return filled
end

-- ============================================================
--  ITEMS AUS LISTE LESEN
-- ============================================================
local function ParseItems(itemsList)
    local items = {}
    if not itemsList then return items end
    for _, frame in ipairs(itemsList:GetChildren()) do
        pcall(function()
            -- Versuche Info-Unterordner
            local inf = frame:FindFirstChild("Info")
            if inf then
                local nameV = inf:FindFirstChild("ItemNames")
                local rateV = inf:FindFirstChild("DropRate")
                local amtV  = inf:FindFirstChild("DropAmount")
                local iname = nameV and tostring(nameV.Value) or ""
                local rate  = rateV and tonumber(rateV.Value) or 0
                local amt   = amtV  and tonumber(amtV.Value)  or 1
                if iname ~= "" then
                    items[iname] = {dropRate = rate, dropAmount = amt}
                end
            else
                -- Fallback: direkte Werte im Frame
                local nameV = frame:FindFirstChild("ItemNames") or frame:FindFirstChild("Name")
                local rateV = frame:FindFirstChild("DropRate")
                local amtV  = frame:FindFirstChild("DropAmount") or frame:FindFirstChild("Amount")
                local iname = nameV and tostring(nameV.Value) or frame.Name
                local rate  = rateV and tonumber(rateV.Value) or 0
                local amt   = amtV  and tonumber(amtV.Value)  or 1
                if iname ~= "" and iname ~= frame.ClassName then
                    items[iname] = {dropRate = rate, dropAmount = amt}
                end
            end
        end)
    end
    return items
end

-- ============================================================
--  CHAPTER-BUTTON FINDEN + AGGRESSIV KLICKEN
-- ============================================================
local function GetChapterBase()
    local f = nil
    pcall(function()
        f = LP.PlayerGui
            :WaitForChild("PlayRoom",   5)
            :WaitForChild("Main",       5)
            :WaitForChild("GameStage",  5)
            :WaitForChild("Main",       5)
            :WaitForChild("Base",       5)
            :WaitForChild("Chapter",    5)
    end)
    return f
end

local function ClickChapterButton(chapBase, worldId, chapId)
    if not chapBase then return false end
    local btn = nil
    -- Suche zuerst im passenden Weltordner, dann global
    pcall(function()
        local wf = chapBase:FindFirstChild(worldId)
        if wf then btn = wf:FindFirstChild(chapId) end
    end)
    if not btn then
        pcall(function() btn = chapBase:FindFirstChild(chapId, true) end)
    end
    if not btn then return false end

    -- Methode 1 – direktes Event
    pcall(function() btn.MouseButton1Click:Fire() end)

    -- Methode 2 – VirtualInputManager (absolute Koordinaten)
    pcall(function()
        local ap = btn.AbsolutePosition + btn.AbsoluteSize * 0.5
        VIM:SendMouseButtonEvent(ap.X, ap.Y, 0, true,  game, 0)
        task.wait(0.06)
        VIM:SendMouseButtonEvent(ap.X, ap.Y, 0, false, game, 0)
    end)

    -- Methode 3 – InputBegan/Ended simulieren
    pcall(function()
        local fi = {
            UserInputType  = Enum.UserInputType.MouseButton1,
            UserInputState = Enum.UserInputState.Begin,
            Position       = Vector3.new(0, 0, 0),
        }
        btn.InputBegan:Fire(fi)
        fi.UserInputState = Enum.UserInputState.End
        btn.InputEnded:Fire(fi)
    end)

    return true
end

-- ============================================================
--  ITEMSLIST LEEREN  (Reset zwischen Chapters)
-- ============================================================
local function ClearItemsList(itemsList)
    if not itemsList then return end
    -- Entferne alle Kinder (Spiel re-populiert sie beim naechsten Change)
    pcall(function()
        for _, child in ipairs(itemsList:GetChildren()) do
            child:Destroy()
        end
    end)
end

-- ============================================================
--  ★ ACTIVE-SELECTION SCAN ★
-- ============================================================
local function ScanAllRewards(onProgress)
    if AF.Scanning then
        warn("[HazeHub] Scan laeuft bereits.")
        return false
    end

    -- Weltdaten benoetigt
    if not HS.IsScanDone() then
        local msg = "Weltdaten fehlen! Bitte Game-Tab -> Welten laden."
        warn("[HazeHub] " .. msg)
        pcall(function() onProgress("X " .. msg) end)
        return false
    end

    AF.Scanning = true
    AF.RewardDatabase = {}

    local WorldData = HS.GetWorldData()
    local WorldIds  = HS.GetWorldIds()

    -- Alle Tasks aufbauen
    local tasks = {}
    for _, wid in ipairs(WorldIds) do
        local wd = WorldData[wid] or {}
        local isCalamity = wid:lower():find("calamity") ~= nil
        for _, cid in ipairs(wd.story or {}) do
            local mode = isCalamity and "Calamity" or "Story"
            table.insert(tasks, {worldId=wid, chapId=cid, mode=mode})
        end
        for _, cid in ipairs(wd.ranger or {}) do
            table.insert(tasks, {worldId=wid, chapId=cid, mode="Ranger"})
        end
    end

    local total   = #tasks
    local scanned = 0
    local skipped = 0
    local failed  = 0

    print(string.format("[HazeHub] === SCAN GESTARTET: %d Chapters ===", total))

    if total == 0 then
        warn("[HazeHub] Keine Chapters gefunden. Weltdaten geladen?")
        AF.Scanning = false
        pcall(function() onProgress("X Keine Chapters. Welten neu laden.") end)
        return false
    end

    -- Chapter-Ordner fuer Klick-Simulation
    local chapBase = GetChapterBase()
    if chapBase then
        print("[HazeHub] Chapter-Ordner: " .. chapBase:GetFullName())
    else
        warn("[HazeHub] Chapter-Ordner nicht sichtbar – nur Remote-Methode.")
    end

    -- ── SCHRITT 0: Raumerstell-Menue oeffnen ─────────────────
    print("[HazeHub] Oeffne Create-Menue...")
    Fire("Create")
    task.wait(0.8)

    -- ItemsList-Referenz einmal holen (bleibt gleich waehrend Menue offen)
    local itemsList = GetItemsList(5)
    if not itemsList then
        warn("[HazeHub] ItemsList nicht gefunden – ggf. nicht in Lobby/Menue.")
        -- trotzdem weitermachen, versuchen bei jedem Chapter neu
    end

    for _, t in ipairs(tasks) do
        if not AF.Running or not AF.Scanning then break end
        scanned = scanned + 1

        SetScanProgress(scanned, total,
            string.format("Scanne: %s %s", t.worldId, t.chapId))
        pcall(function()
            onProgress(string.format("Scanne %d/%d: %s  %s",
                scanned, total, t.worldId, t.chapId))
        end)

        print(string.format("[HazeHub] Scanne Welt: %s...  (Chapter: %s,  %d/%d)",
            t.worldId, t.chapId, scanned, total))

        -- Wenn ItemsList weg: Menue neu oeffnen
        if not itemsList or not itemsList.Parent then
            print("[HazeHub] ItemsList verloren – oeffne Menue neu.")
            Fire("Create"); task.wait(0.8)
            itemsList = GetItemsList(4)
        end

        -- ItemsList vor neuem Chapter leeren (damit ChildAdded zuverlaessig feuert)
        ClearItemsList(itemsList)
        task.wait(0.1)

        -- ── SCHRITT 1: Welt/Modus per Remote setzen ───────────
        pcall(function()
            if     t.mode == "Story"    then Fire("Change-World", {World = t.worldId})
            elseif t.mode == "Ranger"   then Fire("Change-Mode",  {KeepWorld=t.worldId, Mode="Ranger Stage"})
            elseif t.mode == "Calamity" then Fire("Change-Mode",  {Mode="Calamity"}) end
        end)
        task.wait(0.25)

        -- ── SCHRITT 2: Chapter per Remote setzen ──────────────
        Fire("Change-Chapter", {Chapter = t.chapId})
        task.wait(0.25)

        -- ── SCHRITT 3: VirtualInput Backup – Button klicken ───
        if chapBase then
            local clicked = ClickChapterButton(chapBase, t.worldId, t.chapId)
            if clicked then
                print(string.format("[HazeHub] GUI-Klick simuliert: %s", t.chapId))
            end
        end

        -- ── SCHRITT 4: Auf Items warten (max 3s, Timeout-Schutz) ──
        -- Neue ItemsList-Referenz holen falls noetig
        if not itemsList or not itemsList.Parent then
            itemsList = GetItemsList(3)
        end

        local gotItems = WaitForItems(itemsList, 3)

        if gotItems and itemsList then
            local items     = ParseItems(itemsList)
            local itemCount = 0
            for _ in pairs(items) do itemCount = itemCount + 1 end

            if itemCount > 0 then
                AF.RewardDatabase[t.chapId] = {
                    world = t.worldId,
                    mode  = t.mode,
                    items = items,
                }
                for iname, idata in pairs(items) do
                    print(string.format("[HazeHub] Gefunden: %s in %s %s  (Rate: %.1f%%)",
                        iname, t.worldId, t.chapId, idata.dropRate or 0))
                end
                print(string.format("[HazeHub] OK: %s – %d Items.", t.chapId, itemCount))
            else
                -- Items-Frames da aber kein Info-Ordner auslesbar
                failed  = failed + 1
                skipped = skipped + 1
                warn(string.format("[HazeHub] FAILED (Info leer): %s", t.chapId))
                pcall(function() onProgress("FAILED (leer): " .. t.chapId) end)
            end
        else
            -- Timeout nach 3s
            failed  = failed + 1
            skipped = skipped + 1
            warn(string.format("[HazeHub] TIMEOUT: %s – mache weiter.", t.chapId))
            pcall(function() onProgress("TIMEOUT: " .. t.chapId) end)
        end

        -- ── SCHRITT 5: Reset – Submit+Cancel, damit naechstes Chapter sauber laedt ──
        pcall(function()
            -- Sende Submit und sofort wieder Create um Menue offen zu halten
            Fire("Submit"); task.wait(0.15)
            Fire("Create"); task.wait(0.3)
        end)

        task.wait(0.2)  -- kurze Pause zwischen Chapters
    end

    -- DB nur speichern wenn genuegend Chapters erfolgreich gescannt
    local successCount = DBCount()
    if successCount >= 10 then
        print(string.format("[HazeHub] Speichere Datenbank... (%d erfolgreiche Chapters)", successCount))
        SaveDB()
    elseif successCount > 0 then
        warn(string.format("[HazeHub] Nur %d Chapters gescannt (<10) – DB wird trotzdem gespeichert.", successCount))
        SaveDB()
    else
        warn("[HazeHub] 0 Chapters gescannt – DB wird NICHT gespeichert.")
    end

    AF.Scanning = false

    local ok = successCount > 0
    print(string.format("[HazeHub] === SCAN FERTIG: %d/%d OK,  %d Timeouts ===",
        successCount, total, failed))
    SetScanDone(ok, successCount, total, failed)
    pcall(function()
        onProgress(string.format(
            ok and "OK Scan: %d/%d  (%d Timeouts)"
               or "X Scan: 0 Chapters. Menue offen?",
            successCount, total, failed))
    end)
    return ok
end

-- ============================================================
--  BESTES CHAPTER FINDEN
-- ============================================================
local function FindBestChapter(itemName)
    local best, bestRate, bestWorld, bestMode = nil, -1, nil, nil
    for chapId, data in pairs(AF.RewardDatabase) do
        if data.items and data.items[itemName] then
            local r = data.items[itemName].dropRate or 0
            if r > bestRate then
                bestRate = r; best = chapId
                bestWorld = data.world; bestMode = data.mode
            end
        end
    end
    if best then
        print(string.format("[HazeHub] Ziel-Item: %s  Welt: %s  Kapitel: %s  (%.1f%%)",
            itemName, bestWorld, best, bestRate))
    else
        warn(string.format("[HazeHub] '%s' nicht in DB gefunden.", itemName))
    end
    return best, bestWorld, bestMode, bestRate
end

-- ============================================================
--  RAUM ERSTELLEN + STARTEN
-- ============================================================
local function FireRoomSequence(worldId, mode, chapId)
    print(string.format("[HazeHub] Erstelle Raum: %s | %s | %s", worldId, mode, chapId))
    task.spawn(function()
        pcall(function()
            Fire("Create");                                         task.wait(0.35)
            if     mode == "Story"    then Fire("Change-World", {World = worldId})
            elseif mode == "Ranger"   then Fire("Change-Mode",  {KeepWorld=worldId, Mode="Ranger Stage"})
            elseif mode == "Calamity" then Fire("Change-Mode",  {Mode="Calamity"}) end
                                                                    task.wait(0.35)
            Fire("Change-Chapter", {Chapter = chapId});             task.wait(0.35)
            Fire("Submit");                                         task.wait(0.5)
            Fire("Start")
            print("[HazeHub] Raum gestartet.")
        end)
    end)
end

-- ============================================================
--  QUEUE UI
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
        for _, q in ipairs(AF.Queue) do
            if not q.done then return q end
        end
        return nil
    end

    for i, q in ipairs(AF.Queue) do
        local inv    = GetInvAmt(q.item)
        local pct    = math.min(1, inv / math.max(1, q.amount))
        local isNext = (not q.done) and (NextItem() == q)

        local row = Instance.new("Frame", AF.UI.Fr.List)
        row.Size = UDim2.new(1, 0, 0, 44); row.BorderSizePixel = 0; Corner(row, 8)
        if     q.done  then row.BackgroundColor3 = D.GreenDark;             Stroke(row, D.GreenBright, 1.5, 0)
        elseif isNext  then row.BackgroundColor3 = Color3.fromRGB(0,30,55); Stroke(row, D.Cyan, 1.5, 0)
        else                row.BackgroundColor3 = D.Card;                  Stroke(row, D.Border, 1, 0.4)
        end

        local barC = q.done and D.GreenBright or (isNext and D.Cyan or D.Purple)

        local bar = Instance.new("Frame", row)
        bar.Size = UDim2.new(0, 3, 0.65, 0); bar.Position = UDim2.new(0, 0, 0.175, 0)
        bar.BackgroundColor3 = barC; bar.BorderSizePixel = 0; Corner(bar, 2)

        local pgBg = Instance.new("Frame", row)
        pgBg.Size = UDim2.new(1, -52, 0, 3); pgBg.Position = UDim2.new(0, 8, 1, -6)
        pgBg.BackgroundColor3 = Color3.fromRGB(28, 38, 62)
        pgBg.BorderSizePixel = 0; Corner(pgBg, 2)
        local pgF = Instance.new("Frame", pgBg)
        pgF.Size = UDim2.new(pct, 0, 1, 0); pgF.BackgroundColor3 = barC
        pgF.BorderSizePixel = 0; Corner(pgF, 2)

        local nL = Instance.new("TextLabel", row)
        nL.Position = UDim2.new(0, 12, 0, 5); nL.Size = UDim2.new(1, -52, 0.5, -3)
        nL.BackgroundTransparency = 1
        nL.Text = (isNext and ">> " or "") .. (q.done and "[OK] " or "") .. q.item
        nL.TextColor3 = q.done and D.GreenBright or (isNext and D.Cyan or D.TextHi)
        nL.TextSize = 11; nL.Font = Enum.Font.GothamBold
        nL.TextXAlignment = Enum.TextXAlignment.Left
        nL.TextTruncate = Enum.TextTruncate.AtEnd

        local pL = Instance.new("TextLabel", row)
        pL.Position = UDim2.new(0, 12, 0.5, 1); pL.Size = UDim2.new(1, -52, 0.5, -5)
        pL.BackgroundTransparency = 1
        pL.Text = inv .. " / " .. q.amount .. "  (" .. math.floor(pct * 100) .. "%)"
        pL.TextColor3 = q.done and D.GreenBright or D.TextMid
        pL.TextSize = 10; pL.Font = Enum.Font.GothamSemibold
        pL.TextXAlignment = Enum.TextXAlignment.Left

        local ci = i
        local xBtn = Instance.new("TextButton", row)
        xBtn.Size = UDim2.new(0, 34, 0, 34); xBtn.Position = UDim2.new(1, -38, 0.5, -17)
        xBtn.BackgroundColor3 = Color3.fromRGB(50, 12, 12); xBtn.Text = "X"
        xBtn.TextColor3 = D.Red; xBtn.TextSize = 13; xBtn.Font = Enum.Font.GothamBold
        xBtn.AutoButtonColor = false; xBtn.BorderSizePixel = 0
        Corner(xBtn, 7); Stroke(xBtn, D.Red, 1, 0.4)
        xBtn.MouseEnter:Connect(function() Tw(xBtn, {BackgroundColor3=D.RedDark}) end)
        xBtn.MouseLeave:Connect(function() Tw(xBtn, {BackgroundColor3=Color3.fromRGB(50,12,12)}) end)
        xBtn.MouseButton1Click:Connect(function()
            table.remove(AF.Queue, ci); SaveQueue(); UpdateQueueUI()
        end)
    end
end

-- ============================================================
--  FARM LOOP
-- ============================================================
local function GetNextItem()
    for _, q in ipairs(AF.Queue) do
        if not q.done then return q end
    end
    return nil
end

local function FarmLoop()
    AF.Active = true
    print("[HazeHub] === FARM LOOP GESTARTET ===")

    while AF.Running do
        local q = GetNextItem()
        if not q then
            AF.Active = false
            SetStatus("Queue fertig!", D.Green)
            print("[HazeHub] Alle Items gefarmt.")
            break
        end

        local chapId, worldId, mode, rate = FindBestChapter(q.item)

        -- Fallback: erstes Chapter in DB
        if not chapId then
            for cid, data in pairs(AF.RewardDatabase) do
                chapId = cid; worldId = data.world; mode = data.mode; rate = 0
                warn("[HazeHub] Fallback-Chapter: " .. chapId); break
            end
        end

        -- Letzter Fallback: WorldIds
        if not chapId then
            local ids = HS.GetWorldIds()
            if #ids > 0 then
                local wd = HS.GetWorldData()[ids[1]] or {}
                if wd.story and #wd.story > 0 then
                    chapId = wd.story[1]; worldId = ids[1]; mode = "Story"; rate = 0
                end
            end
        end

        if not chapId then
            SetStatus("Kein Level fuer '" .. q.item .. "'", D.Orange)
            q.done = true; pcall(UpdateQueueUI); task.wait(3); continue
        end

        SetStatus(string.format("Farm: %s  ->  %s  (%.1f%%)", q.item, chapId, rate or 0), D.Cyan)
        FireRoomSequence(worldId, mode, chapId)

        local deadline = os.time() + 600
        local goalMet  = false

        while AF.Running and os.time() < deadline do
            task.wait(5)
            local cur = GetInvAmt(q.item)
            SetStatus(string.format("%s: %d/%d  (%.0f%%)",
                q.item, cur, q.amount,
                math.min(100, cur / math.max(1, q.amount) * 100)), D.Cyan)
            pcall(UpdateQueueUI)
            pcall(function() HS.UpdateGoalsUI() end)
            if cur >= q.amount then goalMet = true; break end
        end

        if goalMet then
            q.done = true; SaveQueue(); pcall(UpdateQueueUI)
            local cur = GetInvAmt(q.item)
            print(string.format("[HazeHub] Ziel erreicht: %s  (%d/%d)", q.item, cur, q.amount))
            task.spawn(function() pcall(function() SendWebhook({}, q.item, cur) end) end)
            SetStatus("Zurueck zur Lobby...", D.Yellow)
            task.wait(2); ClickBackToLobby()
            local lw = 0
            while AF.Running and not IsInLobby() and lw < 15 do
                task.wait(1); lw = lw + 1
            end
            task.wait(2)
        else
            warn("[HazeHub] Timeout fuer '" .. q.item .. "'")
            SetStatus("Timeout – naechstes Item...", D.Orange)
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
    SetStatus("Gestoppt.", D.TextMid)
    print("[HazeHub] Auto-Farm gestoppt.")
end
HS.StopFarm = StopFarm

-- ============================================================
--  SCAN-TASK (fuer Button + Queue-Autostart)
-- ============================================================
local function RunScanTask(forceDelete, thenStartFarm)
    if AF.Scanning then SetStatus("Scan laeuft!", D.Yellow); return end
    task.spawn(function()
        if forceDelete then ClearDB() end

        pcall(function()
            AF.UI.Fr.ScanBar.Visible              = true
            AF.UI.Fr.ScanBarFill.Size             = UDim2.new(0, 0, 1, 0)
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

        -- Scan-Button zuruecksetzen
        pcall(function()
            AF.UI.Btn.ForceRescan.Text       = "DATENBANK NEU SCANNEN"
            AF.UI.Btn.ForceRescan.TextColor3 = Color3.new(1, 1, 1)
        end)

        -- Nach Scan Farm starten
        if thenStartFarm and ok and DBCount() > 0 and AF.Running and not AF.Active then
            local nxt = GetNextItem()
            if nxt then
                print("[HazeHub] Queue-Autostart nach Scan.")
                task.spawn(FarmLoop)
            end
        end
    end)
end

-- ============================================================
--  GUI AUFBAUEN
-- ============================================================

-- STATUS-CARD
local sCard = Card(Container, 36); Pad(sCard, 6, 10, 6, 10)
AF.UI.Lbl.Status = Instance.new("TextLabel", sCard)
AF.UI.Lbl.Status.Size               = UDim2.new(1, 0, 1, 0)
AF.UI.Lbl.Status.BackgroundTransparency = 1
AF.UI.Lbl.Status.Text               = "Auto-Farm gestoppt"
AF.UI.Lbl.Status.TextColor3         = D.TextMid
AF.UI.Lbl.Status.TextSize           = 11
AF.UI.Lbl.Status.Font               = Enum.Font.GothamSemibold
AF.UI.Lbl.Status.TextXAlignment     = Enum.TextXAlignment.Left

-- DB-KARTE
local dbCard = Card(Container); Pad(dbCard, 10, 10, 10, 10); VList(dbCard, 7)
SecLbl(dbCard, "REWARD-DATENBANK")

AF.UI.Lbl.DBStatus = MkLbl(dbCard, "Keine DB geladen.", 11, D.TextLow)
AF.UI.Lbl.DBStatus.Size = UDim2.new(1, 0, 0, 18)

-- Scan-Fortschrittstext
local spLbl = Instance.new("TextLabel", dbCard)
spLbl.Size               = UDim2.new(1, 0, 0, 16)
spLbl.BackgroundTransparency = 1
spLbl.Text               = ""
spLbl.TextColor3         = D.Yellow
spLbl.TextSize           = 10
spLbl.Font               = Enum.Font.Gotham
spLbl.TextXAlignment     = Enum.TextXAlignment.Left
spLbl.TextTruncate       = Enum.TextTruncate.AtEnd
AF.UI.Lbl.ScanProgress   = spLbl

-- Fortschrittsbalken
local barBg = Instance.new("Frame", dbCard)
barBg.Size             = UDim2.new(1, 0, 0, 7)
barBg.BackgroundColor3 = Color3.fromRGB(18, 26, 48)
barBg.BorderSizePixel  = 0; barBg.Visible = false; Corner(barBg, 3)
AF.UI.Fr.ScanBar = barBg

local barFill = Instance.new("Frame", barBg)
barFill.Size             = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = D.Purple
barFill.BorderSizePixel  = 0; Corner(barFill, 3)
AF.UI.Fr.ScanBarFill = barFill

-- DB laden
local loadDbBtn = Instance.new("TextButton", dbCard)
loadDbBtn.Size = UDim2.new(1, 0, 0, 28); loadDbBtn.BackgroundColor3 = D.CardHover
loadDbBtn.Text = "DB laden"; loadDbBtn.TextColor3 = D.CyanDim
loadDbBtn.TextSize = 11; loadDbBtn.Font = Enum.Font.GothamBold
loadDbBtn.AutoButtonColor = false; loadDbBtn.BorderSizePixel = 0
Corner(loadDbBtn, 7); Stroke(loadDbBtn, D.CyanDim, 1, 0.3)
loadDbBtn.MouseEnter:Connect(function() Tw(loadDbBtn, {BackgroundColor3=Color3.fromRGB(0,45,75)}) end)
loadDbBtn.MouseLeave:Connect(function() Tw(loadDbBtn, {BackgroundColor3=D.CardHover}) end)
loadDbBtn.MouseButton1Click:Connect(function()
    if LoadDB() then
        AF.UI.Lbl.DBStatus.Text       = string.format("OK DB: %d Chapters geladen", DBCount())
        AF.UI.Lbl.DBStatus.TextColor3 = D.Green
    else
        AF.UI.Lbl.DBStatus.Text       = "Keine gueltige DB. Bitte scannen."
        AF.UI.Lbl.DBStatus.TextColor3 = D.Orange
    end
end)

-- ★ FORCE-RESCAN BUTTON ★
local forceBtn = Instance.new("TextButton", dbCard)
forceBtn.Size             = UDim2.new(1, 0, 0, 40)
forceBtn.BackgroundColor3 = Color3.fromRGB(68, 10, 108)
forceBtn.Text             = "DATENBANK NEU SCANNEN"
forceBtn.TextColor3       = Color3.new(1, 1, 1)
forceBtn.TextSize         = 13; forceBtn.Font = Enum.Font.GothamBold
forceBtn.AutoButtonColor  = false; forceBtn.BorderSizePixel = 0
Corner(forceBtn, 9); Stroke(forceBtn, Color3.fromRGB(180, 80, 255), 2, 0)
AF.UI.Btn.ForceRescan = forceBtn
forceBtn.MouseEnter:Connect(function()   Tw(forceBtn, {BackgroundColor3=Color3.fromRGB(110,22,170)}) end)
forceBtn.MouseLeave:Connect(function()   Tw(forceBtn, {BackgroundColor3=Color3.fromRGB(68,10,108)})  end)
forceBtn.MouseButton1Down:Connect(function() Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(40,5,72)}) end)
forceBtn.MouseButton1Up:Connect(function()   Tw(forceBtn,{BackgroundColor3=Color3.fromRGB(110,22,170)}) end)
forceBtn.MouseButton1Click:Connect(function() RunScanTask(true, false) end)

-- QUEUE-KARTE
local qCard = Card(Container); Pad(qCard, 10, 10, 10, 10); VList(qCard, 8)
SecLbl(qCard, "AUTO-FARM QUEUE")

local qRow = Instance.new("Frame", qCard)
qRow.Size = UDim2.new(1, 0, 0, 30); qRow.BackgroundTransparency = 1; HList(qRow, 5)
local qItemOuter, qItemBox = MkInput(qRow, "Item-Name..."); qItemOuter.Size = UDim2.new(0.50, 0, 0, 30)
local qAmtOuter,  qAmtBox  = MkInput(qRow, "Anzahl");       qAmtOuter.Size  = UDim2.new(0.28, 0, 0, 30)

local qAddBtn = Instance.new("TextButton", qRow)
qAddBtn.Size = UDim2.new(0.19, 0, 0, 30); qAddBtn.BackgroundColor3 = D.Green
qAddBtn.Text = "+ Add"; qAddBtn.TextColor3 = Color3.new(1,1,1); qAddBtn.TextSize = 11
qAddBtn.Font = Enum.Font.GothamBold; qAddBtn.AutoButtonColor = false; qAddBtn.BorderSizePixel = 0
Corner(qAddBtn, 7); Stroke(qAddBtn, D.Green, 1, 0.2)
qAddBtn.MouseEnter:Connect(function() Tw(qAddBtn,{BackgroundColor3=Color3.fromRGB(0,160,80)}) end)
qAddBtn.MouseLeave:Connect(function() Tw(qAddBtn,{BackgroundColor3=D.Green}) end)

AF.UI.Fr.List = Instance.new("Frame", qCard)
AF.UI.Fr.List.Size = UDim2.new(1, 0, 0, 0); AF.UI.Fr.List.AutomaticSize = Enum.AutomaticSize.Y
AF.UI.Fr.List.BackgroundTransparency = 1; VList(AF.UI.Fr.List, 4)
AF.UI.Lbl.QueueEmpty = MkLbl(AF.UI.Fr.List, "Queue leer. Item + Anzahl eintragen.", 11, D.TextLow)
AF.UI.Lbl.QueueEmpty.Size = UDim2.new(1, 0, 0, 24)

qAddBtn.MouseButton1Click:Connect(function()
    local iname = (qItemBox.Text or ""):match("^%s*(.-)%s*$")
    local iamt  = tonumber(qAmtBox.Text)
    if iname == "" or not iamt or iamt <= 0 then return end
    local found = false
    for _, g in ipairs(ST.Goals) do if g.item == iname then found = true; break end end
    if not found then
        table.insert(ST.Goals, {item=iname, amount=iamt, reached=false}); SaveConfig()
    end
    table.insert(AF.Queue, {item=iname, amount=iamt, done=false})
    SaveQueue(); qItemBox.Text = ""; qAmtBox.Text = ""
    UpdateQueueUI(); pcall(function() HS.UpdateGoalsUI() end)
    print(string.format("[HazeHub] Queue: '%s' (x%d) hinzugefuegt.", iname, iamt))
end)

-- STEUERUNG
local ctrlRow = Instance.new("Frame", qCard)
ctrlRow.Size = UDim2.new(1, 0, 0, 32); ctrlRow.BackgroundTransparency = 1; HList(ctrlRow, 8)

local startBtn = Instance.new("TextButton", ctrlRow)
startBtn.Size = UDim2.new(0.48, 0, 0, 32); startBtn.BackgroundColor3 = D.Green
startBtn.Text = "Start Queue"; startBtn.TextColor3 = Color3.new(1, 1, 1)
startBtn.TextSize = 12; startBtn.Font = Enum.Font.GothamBold
startBtn.AutoButtonColor = false; startBtn.BorderSizePixel = 0
Corner(startBtn, 8); Stroke(startBtn, D.Green, 1, 0.2)

local stopBtn = Instance.new("TextButton", ctrlRow)
stopBtn.Size = UDim2.new(0.48, 0, 0, 32); stopBtn.BackgroundColor3 = D.RedDark
stopBtn.Text = "Stop"; stopBtn.TextColor3 = D.Red
stopBtn.TextSize = 12; stopBtn.Font = Enum.Font.GothamBold
stopBtn.AutoButtonColor = false; stopBtn.BorderSizePixel = 0
Corner(stopBtn, 8); Stroke(stopBtn, D.Red, 1, 0.4)

-- START MIT VALIDIERUNG + AUTO-SCAN
startBtn.MouseButton1Click:Connect(function()
    if AF.Active then SetStatus("Farm laeuft bereits!", D.Yellow); return end
    if #AF.Queue == 0 then SetStatus("Queue ist leer!", D.Orange); return end

    AF.Running = true

    if DBCount() == 0 then
        -- DB leer: automatisch scannen, dann Farm starten
        SetStatus("Datenbank leer! Starte Scan-Vorgang...", D.Yellow)
        pcall(function()
            AF.UI.Lbl.DBStatus.Text       = "Datenbank leer! Starte Scan-Vorgang..."
            AF.UI.Lbl.DBStatus.TextColor3 = D.Yellow
            startBtn.Text                 = "Scannt DB..."
            startBtn.TextColor3           = D.Yellow
        end)
        warn("[HazeHub] DB leer – automatischer Scan vor Queue-Start.")
        RunScanTask(false, true)  -- thenStartFarm = true
    else
        print(string.format("[HazeHub] Queue gestartet: %d Items, DB: %d Chapters.",
            #AF.Queue, DBCount()))
        task.spawn(FarmLoop)
    end
end)

stopBtn.MouseButton1Click:Connect(function()
    AF.Running = false; StopFarm()
    startBtn.Text = "Start Queue"; startBtn.TextColor3 = Color3.new(1, 1, 1)
end)

-- Button-Text zuruecksetzen nach Scan
task.spawn(function()
    while true do
        task.wait(1)
        if not AF.Scanning then
            pcall(function()
                if startBtn.Text == "Scannt DB..." then
                    startBtn.Text       = "Start Queue"
                    startBtn.TextColor3 = Color3.new(1, 1, 1)
                end
            end)
        end
    end
end)

local clearBtn = NeonBtn(qCard, "Queue leeren", D.Red, 28)
clearBtn.MouseButton1Click:Connect(function()
    AF.Queue = {}; SaveQueue(); UpdateQueueUI()
    print("[HazeHub] Queue geleert.")
end)

-- ============================================================
--  STARTUP
-- ============================================================
LoadQueue()

if isfile and isfile(DB_FILE) then
    local raw; pcall(function() raw = readfile(DB_FILE) end)
    if raw and #raw < 10 then
        warn("[HazeHub] DB leer/korrupt.")
        AF.UI.Lbl.DBStatus.Text       = "DB korrupt – Neu-Scan noetig!"
        AF.UI.Lbl.DBStatus.TextColor3 = D.Orange
    elseif LoadDB() then
        AF.UI.Lbl.DBStatus.Text       = string.format("OK DB: %d Chapters geladen", DBCount())
        AF.UI.Lbl.DBStatus.TextColor3 = D.Green
    end
else
    AF.UI.Lbl.DBStatus.Text       = "Keine DB. Bitte scannen."
    AF.UI.Lbl.DBStatus.TextColor3 = D.TextLow
end

UpdateQueueUI()

_G.HazeShared.SetModuleLoaded(VERSION)
print("[HazeHub] autofarm.lua v" .. VERSION .. " geladen  |  DB: " .. DBCount() .. " Chapters")
