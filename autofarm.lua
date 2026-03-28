-- ╔══════════════════════════════════════════════════════════╗
--  HazeHUB V21 – Hauptskript  v21.0
--  CHANGES v21.0:
--    ✓ Tab-Reihenfolge: Game Session Quests Shops Crafting Traits Teams Inventory Misc Settings
--    ✓ Auto-Retry aus Game-Tab → Misc-Tab
--    ✓ Raid-Farm in Welt & Kapitel integriert (neben Calamity)
--    ✓ DB-Status Cards nebeneinander (Game-Tab)
--    ✓ DB-Werkzeuge nebeneinander (Reset + Clear Cache)
--    ✓ Quests 2-spaltig nebeneinander
--    ✓ Inventory: Spieler Stats + Shop Currency nebeneinander
--    ✓ Inventory Items 2-Spalten UIGridLayout
--    ✓ Neuer Anti-AFK (Kamera-basiert, kein VirtualUser-Spacebar-Spam)
--  FIXES v20.6:
--    ✓ Tab-Leiste: ScrollingFrame, CanvasSize via UIListLayout.AbsoluteContentSize, ScrollBar 0
--    ✓ MainFrame / Content / Sidebar: UDim2.fromScale + UIAspectRatioConstraint (Fenster)
--    ✓ UpdateLayoutForMobile(): TouchEnabled → Tab-Canvas + Trait-Layout (HS._isTouchClient)
--    ✓ Welt-Cache: HazeHUB/<LP.Name>_WorldCache.json + SaveWorldCache für Autofarm-Rescan
--    ✓ MakeTab-Inhalte: ScrollBarThickness 0, AutomaticCanvasSize Y
--  FIXES v20.5:
--    ✓ Multi-Selection Stat-Reroll: Checkboxen für alle Ratings
--      (C-, C, C+, B-, B, B+, A-, A, A+, S-, S, S+, SS, SSS, O-, O, O+)
--    ✓ AutoStatRerollLoop stoppt bei übereinstimmendem Rating (Multi-Match)
--    ✓ Stat-Reroll nutzt ...Collection[UnitName].Tag.Value als Security-Key
--    ✓ Neues Modul: Team Manager (Teams-Tab)
--      - Save/Load Loadouts (6 Slots) per LP.Name .. "_teams.json"
--      - Equip / UnEquip Remotes + AutoUpgradeConfig-Remote
--    ✓ Teams-Tab vollständig scrollbar (AutomaticCanvasSize)
--    ✓ Alle Hazeluxe1-Referenzen → LP.Name
--  FIXES v20.4:
--    ✓ Mobile-Toggle: runder Button links mittig (UDim2 0,10 / 0.5,-25); Logo PNG zentriert
--    ✓ MainFrame.Visible = not MainFrame.Visible; Blur folgt Sichtbarkeit; GuiVisible im Autosave
--  FIXES v20.3:
--    ✓ Settings + AutoSave pro LocalPlayer (…/Spielername_settings.json, …_autosave.json)
--    ✓ Früh-Load AutoFarm liest dieselbe account-spezifische Datei (kein Überschreiben zwischen Accounts)
--    ✓ Webhook: schwarzes Embed; Inline Account / Runde·Ø·Zeit; Währungen & Items getrennt
--  FIXES v20.2:
--    ✓ formatTime(seconds): <60 → „27s“, sonst „M:SSm“; Session-Tab + Webhook + Header-Timer
--    ✓ Webhook: Embed 0x000000; Inline Runde / Zeit / Ø Zeit; Felder „Statistiken“ + „Drops“
--    ✓ Währungs-Keys (Gold/Exp/Gems) fest im Session-Item-Filter; Logo im Header/Mini zentriert
--  FIXES v20.1:
--    ✓ Session-Item-Liste ohne Gold/Exp/Gems (Dupplikat-Filter); Webhook: Status / Währungen / Items
--    ✓ Ø Rundenzeit in Sekunden (UI + Webhook); Footer „Session Bericht • Zeit“ + Logo
--    ✓ Logo im Top-Header; leichter Lighting-Blur; SecLbl → GothamMedium
--  FIXES v20.0:
--  FIXES v19.9:
--    ✓ CoreGui-Check via reines pcall
--    ✓ Kein auto-rescan beim Start – nur DB laden
--    ✓ Keine doppelten Header in Tabs
--    ✓ GUI zentriert: AnchorPoint(0.5,0.5)
--    ✓ D.BorderCyan = neutrales Grau (Legacy-Name)
--    ✓ ViewportFrame + ImageLabel Dual-System
--    ✓ LoadItemImage exportiert (Texture rbxassetid aus Front)
--    ✓ LoadItemViewport exportiert (Multi-Part zentriert)
--    ✓ Neuer Traits-Tab (lädt trait.lua Modul)
-- ╚══════════════════════════════════════════════════════════╝

-- ── Früh-Flag (AutoFarm aus account-spezifischer settings-Datei, siehe nach Services) ──
local _earlyAutoFarm = false

-- ★ Globaler Anti-Spam / Anti-Reenter (Priorität)
-- verhindert, dass das komplette Hauptskript tausende Male neu initialisiert wird
if _G.HazHubLoaded then return end
_G.HazHubLoaded = true

-- ★ Account-spezifische Dynamik (für Multi-Account korrekt)
local LP = game:GetService('Players').LocalPlayer
if not LP then repeat task.wait(0.1) LP = game:GetService('Players').LocalPlayer until LP end
local PlayerGui = nil
pcall(function()
    PlayerGui = LP:WaitForChild('PlayerGui', 10)
end)
if not PlayerGui then
    warn("[HazeHub] PlayerGui konnte nicht innerhalb von 10s geladen werden. Script stoppt, um Absturz zu vermeiden.")
    return
end

-- ★ CRITICAL: GUI Duplication Guard (Anti-Loop)
local function HazHubMainExists()
    -- je nach Setup kann ScreenGui in PlayerGui oder CoreGui liegen
    if PlayerGui and PlayerGui:FindFirstChild("HazHub_Main") then
        return true
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg and cg:FindFirstChild("HazHub_Main") then
        return true
    end
    return false
end
if HazHubMainExists() then return end

-- ── Haupttabelle ──────────────────────────────────────────────
local Haze = {
    UI   = { Fr={}, Lbl={}, Btn={}, Inp={} },
    Svc  = {},
    Tabs = {}, TBtns = {},
    Config = { WebhookURL="", UISize="PC", ToggleKey="F4", AutoRetry=false, SavedGoals={}, AutoFarm=false, GuiVisible=true },
    S = {
        Goals={}, GoalsNotified={},
        SessStart=os.time(), Running=true, RoundWallStart=nil,
        WhEnabled=true, GuiVisible=true, KeyListening=false,
        KeyConn=nil, ActiveTab=nil, SelMode="Story",
        SelWorld=nil, SelChap=nil, WorldData={}, WorldIds={},
        ScanDone=false, ChapFolderRef=nil, ChildConn=nil, DBReady=false,
        _EndedScreenDebounce=0,
    },
    K = {
        INFO          = { Exp=true, Gems=true, Gold=true },
        RARE          = { ["Legendary Stone"]=true, ["Mythic Egg"]=true },
        FOLDER        = "HazeHUB",
        LOBBY_ID      = 111446873000464,
        AF_URL        = "https://raw.githubusercontent.com/Hazeluxeeeees/HazeHub-Modules/refs/heads/main/autofarm.lua",
        SHOP_URL      = "https://raw.githubusercontent.com/Hazeluxeeeees/HazeHub-Modules/refs/heads/main/Shops",
        CRAFT_URL     = "https://raw.githubusercontent.com/Hazeluxeeeees/HazeHub-Modules/refs/heads/main/craft",
        TRAIT_URL     = "https://raw.githubusercontent.com/Hazeluxeeeees/HazeHub-Modules/refs/heads/main/trait",
        TEAMS_URL     = "https://raw.githubusercontent.com/Hazeluxeeeees/HazeHub-Modules/refs/heads/main/teams",
    },
}

_G.HazeShared = {
    Container          = nil,
    ShopContainer      = nil,
    CraftPage          = nil,
    TraitPage          = nil,
    Status             = "Wird geladen...",
    Version            = "1.0.0",
    _AutoFarm_RewardDB = nil,
}

-- ── Services ─────────────────────────────────────────────────
Haze.Svc.Http     = game:GetService("HttpService")
Haze.Svc.Input    = game:GetService("UserInputService")
Haze.Svc.Vuser    = game:GetService("VirtualUser")
Haze.Svc.Player   = LP
Haze.Svc.RS       = game:GetService("ReplicatedStorage")
Haze.Svc.Tween    = game:GetService("TweenService")
Haze.Svc.Teleport = game:GetService("TeleportService")

local H   = Haze
local S   = Haze.S
local K   = Haze.K
local Svc = Haze.Svc
--- Globale Funktionstabelle für tab-übergreifende Sicherheit
_G.HazeHubFunctions = {
    SetGoalFromInventory = nil,
    SetKeyDisplay = nil,
    UpdateAutoRetryUI = nil,
    TriggerResetRescan = nil,
    StartRaid = nil,
    StopRaid = nil,
    ToggleAntiAFK = nil
}

--- Globale Session (UI + Webhook – identische Daten)
local GlobalSession = { CurrentRound = 0, TotalTime = 0, AllRewards = {} }
GlobalSession.Items = GlobalSession.AllRewards
_G.GlobalSession = GlobalSession

-- === GLOBALE HAZEHUB TABELLE (SYNCHRONISATION) ===
_G.HazeHUB = {}
_G.HazeHUB_Loaded = false
_G.HazeHUB_Ready = false

-- ── GLOBALE FUNKTIONS-DEFINITIONEN (HOISTING - VERHINDERT SCOPE-FEHLER) ──
-- ALLE wichtigen Funktionen werden hier definiert und global gemacht

-- Vorwärtsdeklarationen für alle UI-Funktionen
local UpdateGoalsUI, UpdateSessionUI, RebuildWorldList, LoadWorldCache
local RefreshPlayerStats, SelectTab, OnMiniBtnClick, ToggleHubGui
local SendWebhook, AccumulateRewards, BuildItemPreview, LoadItemViewport
local GetItemTextureId, ApplySharpTypography

-- Globale Variablen
local AntiAFKEnabled = true

-- === GLOBALE KERNFUNKTIONEN ===
_G.HazeHUB.ToggleAntiAFK = function()
    AntiAFKEnabled = not AntiAFKEnabled
    if afkDot and afkTxt then
        if AntiAFKEnabled then
            afkDot.BackgroundColor3 = D.Green
            afkTxt.Text = "Anti-AFK  —  Aktiv"
            afkTxt.TextColor3 = D.Green
        else
            afkDot.BackgroundColor3 = D.Red
            afkTxt.Text = "Anti-AFK  —  Inaktiv"
            afkTxt.TextColor3 = D.Red
        end
    end
end

_G.HazeHUB.StartRaid = function()
    if _G.HazeShared and _G.HazeShared.StartFarmFromMain and type(_G.HazeShared.StartFarmFromMain) == "function" then
        _G.HazeShared.StartFarmFromMain()
    else
        warn("[HazeHUB] StartFarmFromMain Funktion nicht gefunden!")
    end
end

_G.HazeHUB.StopRaid = function()
    if _G.HazeShared and _G.HazeShared.StopFarm and type(_G.HazeShared.StopFarm) == "function" then
        _G.HazeShared.StopFarm()
    else
        warn("[HazeHUB] StopFarm Funktion nicht gefunden!")
    end
end

_G.HazeHUB.SetGoalFromInventory = function(itemName)
    if not itemName or itemName == "" then return end
    if _G.HazeHUB.SelectTab then _G.HazeHUB.SelectTab("Session") end
    if H.UI.Inp.GoalItem then H.UI.Inp.GoalItem.Text=itemName end
    if H.UI.Inp.GoalAmt then H.UI.Inp.GoalAmt.Text="" end
    task.defer(function() pcall(function() if H.UI.Inp.GoalAmt then H.UI.Inp.GoalAmt:CaptureFocus() end end) end)
    if gItemOuter and gAmtOuter then
        Stroke(gItemOuter,D.Purple,1.5,0); Stroke(gAmtOuter,D.Purple,1.5,0)
        task.delay(2.5,function() Stroke(gItemOuter,D.Border,1,0.2); Stroke(gAmtOuter,D.Border,1,0.2) end)
    end
end

_G.HazeHUB.SetKeyDisplay = function(k)
    if H.UI.Btn.KeyBtn then
        H.UI.Btn.KeyBtn.Text="[ "..(k or "F4").." ]"
        H.UI.Btn.KeyBtn.TextColor3=D.Accent
        Stroke(H.UI.Btn.KeyBtn,D.Accent,1,0.3)
    end
end

_G.HazeHUB.UpdateAutoRetryUI = function()
    if not H.UI.Btn.ARToggle or not H.UI.Lbl.ARStatus then return end
    if H.Config.AutoRetry then
        H.UI.Btn.ARToggle.Text="✅ AN"; H.UI.Btn.ARToggle.TextColor3=D.TextHi
        H.UI.Lbl.ARStatus.Text="Auto Retry: AN"; H.UI.Lbl.ARStatus.TextColor3=D.Green
        Stroke(H.UI.Btn.ARToggle,D.Green,1.5,0); Tw(H.UI.Btn.ARToggle,{BackgroundColor3=D.GreenDark,BackgroundTransparency=0.12})
    else
        H.UI.Btn.ARToggle.Text="⬜ AUS"; H.UI.Btn.ARToggle.TextColor3=D.TextLow
        H.UI.Lbl.ARStatus.Text="Auto Retry: AUS"; H.UI.Lbl.ARStatus.TextColor3=D.TextMid
        Stroke(H.UI.Btn.ARToggle,D.TextLow,1,0.4); Tw(H.UI.Btn.ARToggle,{BackgroundColor3=D.CardHover,BackgroundTransparency=D.GlassPane})
    end
end

_G.HazeHUB.StartAutofarm = function()
    warn("[HazeHUB] StartAutofarm nicht implementiert")
end

_G.HazeHUB.StopAutofarm = function()
    warn("[HazeHUB] StopAutofarm nicht implementiert")
end

_G.HazeHUB.UpdateStatus = function(status, color)
    warn("[HazeHUB] UpdateStatus nicht implementiert: " .. tostring(status))
end

-- ============================================================
--  WELT-SPEICHER FUNKTIONEN
-- ============================================================
_G.HazeHUB.SaveWorlds = function()
    if not writefile then return false end
    
    local worldData = {
        worlds = {},
        timestamp = os.time(),
        version = "1.0"
    }
    
    -- Welten-Daten sammeln
    if S.WorldData and S.WorldIds then
        for _, worldId in ipairs(S.WorldIds) do
            local worldInfo = S.WorldData[worldId]
            if worldInfo then
                table.insert(worldData.worlds, {
                    id = worldId,
                    story = worldInfo.story or {},
                    ranger = worldInfo.ranger or {},
                    calamity = worldInfo.calamity or {},
                    label = worldInfo.label or worldId
                })
            end
        end
    end
    
    local success = pcall(function()
        writefile("HazeHUB/HazeHUB_Worlds.json", Svc.Http:JSONEncode(worldData))
    end)
    
    if success then
        print("[HazeHUB] Welten-Daten gespeichert: " .. #worldData.worlds .. " Welten")
        return true
    else
        warn("[HazeHUB] Fehler beim Speichern der Welten-Daten")
        return false
    end
end

_G.HazeHUB.LoadWorlds = function()
    if not (isfile and isfile("HazeHUB/HazeHUB_Worlds.json")) then return false end
    
    local success, rawData = pcall(function()
        return readfile("HazeHUB/HazeHUB_Worlds.json")
    end)
    
    if not success or not rawData or #rawData < 10 then
        warn("[HazeHUB] Welten-Datei nicht lesbar oder leer")
        return false
    end
    
    local success, worldData = pcall(function()
        return Svc.Http:JSONDecode(rawData)
    end)
    
    if not success or type(worldData) ~= "table" or not worldData.worlds then
        warn("[HazeHUB] Welten-Datei ungültig")
        return false
    end
    
    -- Welten-Daten wiederherstellen
    S.WorldData = {}
    S.WorldIds = {}
    
    for _, world in ipairs(worldData.worlds) do
        S.WorldData[world.id] = {
            story = world.story or {},
            ranger = world.ranger or {},
            calamity = world.calamity or {},
            label = world.label or world.id
        }
        table.insert(S.WorldIds, world.id)
    end
    
    print("[HazeHUB] Welten-Daten geladen: " .. #worldData.worlds .. " Welten")
    return true
end

_G.HazeHUB.RefreshWorlds = function()
    -- Aktuelle Welten leeren
    S.WorldData = {}
    S.WorldIds = {}
    
    -- Welten neu scannen
    LoadWorldCache()
    
    -- Sofort speichern
    _G.HazeHUB.SaveWorlds()
    
    -- UI live aktualisieren
    if RebuildWorldList then
        pcall(RebuildWorldList)
    end
    
    -- Status aktualisieren
    if H.UI.Lbl.WorldStatus then
        H.UI.Lbl.WorldStatus.Text = "🔄 Welten aktualisiert"
        H.UI.Lbl.WorldStatus.TextColor3 = D.Green
    end
    
    print("[HazeHUB] Welten aktualisiert und neu geladen")
    return true
end

_G.HazeHUB.SaveSettings = function()
    if not writefile then return end
    pcall(function() writefile(GetSettingsFilePath(), Svc.Http:JSONEncode({ AutoFarm = H.Config.AutoFarm, ts = os.time() })) end)
end

-- === GLOBALE HELPER-FUNKTIONEN ===
_G.HazeHUB.TeleportToLobby = function()
    pcall(function() game:GetService("TeleportService"):Teleport(K.LOBBY_ID) end)
end

_G.HazeHUB.IsInLobby = function()
    return game:GetService("Workspace"):FindFirstChild("Lobby") ~= nil
end

_G.HazeHUB.GetInvAmt = function(itemName)
    local n=0
    pcall(function()
        local f=Svc.RS:WaitForChild("Player_Data",3):WaitForChild(LP.Name,3):WaitForChild("Items",3)
        local it=f:FindFirstChild(itemName)
        if it and it:IsA("IntValue") then n=it.Value end
    end)
    return n
end

_G.HazeHUB.FmtDur = function(sec)
    local h=math.floor(sec/3600); local m=math.floor((sec%3600)/60); local s=sec%60
    if h>0 then return string.format("%dh %02dm %02ds",h,m,s) else return string.format("%dm %02ds",m,s) end
end

_G.HazeHUB.FmtNum = function(n)
    n=math.floor(tonumber(n) or 0); local s=tostring(n); local r=""; local c=0
    for i=#s,1,-1 do c=c+1; r=s:sub(i,i)..r; if c%3==0 and i>1 then r=","..r end end
    return r
end

_G.HazeHUB.formatTime = function(sec)
    local t = tonumber(sec) or 0
    if t < 0 then t = 0 end
    if t < 60 then return string.format("%ds", t) end
    local minInt = math.floor(t / 60)
    local secInt = t % 60
    return string.format("%d:%02d", minInt, secInt)
end

-- === GLOBALE UI FACTORY FUNKTIONEN ===
_G.HazeHUB.Tw = function(o,p,ti) Svc.Tween:Create(o,ti or TF,p):Play() end

_G.HazeHUB.Corner = function(p,r)
    local c=Instance.new("UICorner",p); c.CornerRadius=UDim.new(0,r or 10); return c
end

_G.HazeHUB.Stroke = function(p,col,th,tr)
    local s=Instance.new("UIStroke",p); s.Color=col or D.Border; s.Thickness=th or 1; s.Transparency=tr or 0; return s
end

_G.HazeHUB.Pad = function(p,l,t,r,b)
    local pl=Instance.new("UIPadding",p); pl.PaddingLeft=UDim.new(0,l or 0); pl.PaddingTop=UDim.new(0,t or 0)
    pl.PaddingRight=UDim.new(0,r or 0); pl.PaddingBottom=UDim.new(0,b or 0); return pl
end

_G.HazeHUB.VList = function(p,spacing)
    local l=Instance.new("UIListLayout",p); l.SortOrder=Enum.SortOrder.LayoutOrder; l.Padding=UDim.new(0,spacing or 8); return l
end

_G.HazeHUB.HList = function(p,spacing)
    local l=Instance.new("UIListLayout",p); l.SortOrder=Enum.SortOrder.LayoutOrder; l.Padding=UDim.new(0,spacing or 8); l.FillDirection=Enum.FillDirection.Horizontal; return l
end

_G.HazeHUB.MkLbl = function(parent,text,size,color)
    local lbl=Instance.new("TextLabel",parent); lbl.Text=text or ""; lbl.Size=UDim2.new(1,0,0,size or 12)
    lbl.TextColor3=color or D.TextMid; lbl.TextSize=size or 12; lbl.Font=Enum.Font.Gotham; lbl.BackgroundTransparency=1; return lbl
end

_G.HazeHUB.SecLbl = function(parent,text)
    local lbl=_G.HazeHUB.MkLbl(parent,text,13,D.Accent); lbl.Font=Enum.Font.GothamBold; return lbl
end

_G.HazeHUB.MkInput = function(parent,placeholder)
    local outer=Instance.new("Frame",parent); outer.Size=UDim2.new(1,0,0,28); outer.BackgroundColor3=D.Input; outer.BackgroundTransparency=D.GlassPane or 0.18; outer.BorderSizePixel=0; _G.HazeHUB.Corner(outer,6); _G.HazeHUB.Stroke(outer,D.Border,1,0.4)
    _G.HazeHUB.Pad(outer,8,0,8,0); local box=Instance.new("TextBox",outer); box.Size=UDim2.new(1,0,1,0); box.BackgroundTransparency=1; box.Text=placeholder or ""; box.PlaceholderText=placeholder or ""; box.TextColor3=D.TextHi; box.PlaceholderColor3=D.TextLow; box.TextSize=12; box.Font=Enum.Font.Gotham; return outer,box
end

_G.HazeHUB.Card = function(parent,sizeY)
    local card=Instance.new("Frame",parent); card.Size=UDim2.new(1,0,0,sizeY or 60); card.BackgroundColor3=D.Card; card.BackgroundTransparency=D.GlassPane or 0.18; card.BorderSizePixel=0; _G.HazeHUB.Corner(card,8); _G.HazeHUB.Stroke(card,D.Border,1,0.5); return card
end

_G.HazeHUB.NeonBtn = function(parent,text,color,sizeY)
    local btn=Instance.new("TextButton",parent); btn.Size=UDim2.new(1,0,0,sizeY or 34); btn.BackgroundColor3=color; btn.BackgroundTransparency=D.GlassPane or 0.18; btn.Text=text; btn.TextColor3=Color3.new(1,1,1); btn.TextSize=13; btn.Font=Enum.Font.GothamBold; btn.AutoButtonColor=false; btn.BorderSizePixel=0; _G.HazeHUB.Corner(btn,8); _G.HazeHUB.Stroke(btn,color,1.5,0)
    btn.MouseEnter:Connect(function() _G.HazeHUB.Tw(btn,{BackgroundColor3=Color3.fromRGB(math.min(255,color.R*255*1.3),math.min(255,color.G*255*1.3),math.min(255,color.B*255*1.3))}) end)
    btn.MouseLeave:Connect(function() _G.HazeHUB.Tw(btn,{BackgroundColor3=color}) end)
    return btn
end

-- === GLOBALE REGISTRIERUNG (sofort verfügbar) ===
_G.HazeHubFunctions.ToggleAntiAFK = _G.HazeHUB.ToggleAntiAFK
_G.HazeHubFunctions.StartRaid = _G.HazeHUB.StartRaid
_G.HazeHubFunctions.StopRaid = _G.HazeHUB.StopRaid
_G.HazeHubFunctions.SetGoalFromInventory = _G.HazeHUB.SetGoalFromInventory
_G.HazeHubFunctions.SetKeyDisplay = _G.HazeHUB.SetKeyDisplay
_G.HazeHubFunctions.UpdateAutoRetryUI = _G.HazeHUB.UpdateAutoRetryUI

-- Session: Währungen/XP (nicht in der Item-Drop-Liste / Webhook-Items)
local _SessionCurrencyLower = { gem = true }
for k in pairs(K.INFO) do _SessionCurrencyLower[string.lower(k)] = true end
for _, _cur in ipairs({ "gold", "exp", "gems", "gem", "xp", "yen", "coin", "coins" }) do
    _SessionCurrencyLower[_cur] = true
end
local function IsSessionCurrencyKey(name)
    if name == nil or name == "" then return true end
    if tonumber(name) ~= nil then return true end
    return _SessionCurrencyLower[string.lower(tostring(name))] == true
end

-- CoreGui-Check via reines pcall
local guiParent = PlayerGui
pcall(function()
    local cg = game:GetService("CoreGui")
    if not guiParent and cg then guiParent = cg end
end)
if makefolder then pcall(function() makefolder(K.FOLDER) end) end

-- ── Account-spezifische Dateien (kein Überschreiben zwischen mehreren Accounts) ──
-- REQUIRED: Pro Account eindeutig; Dateiname basiert exakt auf LP.Name.
local saveFile = LP.Name .. "_settings.json"
local autoSaveFile = LP.Name .. "_autosave.json"
local function GetSettingsFilePath()
    return K.FOLDER .. "/" .. saveFile
end
local function GetAutoSaveFilePath()
    return K.FOLDER .. "/" .. autoSaveFile
end
pcall(function()
    if not (isfile and readfile) then return end
    local path = GetSettingsFilePath()
    if not isfile(path) then return end
    local raw = readfile(path)
    if not raw or #raw < 3 then return end
    local ok, d = pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
    if ok and d and d.AutoFarm == true then _earlyAutoFarm = true; _G.AutoFarmRunning = true end
end)

-- ── Helpers ──────────────────────────────────────────────────
local function TeleportToLobby()
    pcall(function() game:GetService("TeleportService"):Teleport(K.LOBBY_ID) end)
end
local function IsInLobby()
    return game:GetService("Workspace"):FindFirstChild("Lobby") ~= nil
end
local function FmtDur(sec)
    local h=math.floor(sec/3600); local m=math.floor((sec%3600)/60); local s=sec%60
    if h>0 then return string.format("%dh %02dm %02ds",h,m,s) else return string.format("%dm %02ds",m,s) end
end
local function FmtNum(n)
    n=math.floor(tonumber(n) or 0); local s=tostring(n); local r=""; local c=0
    for i=#s,1,-1 do c=c+1; r=s:sub(i,i)..r; if c%3==0 and i>1 then r=","..r end end
    return r
end
-- Human-readable Dauer: <60s nur Sekunden; ab 60s Minuten:Sekunden + „m“ (z. B. 1:05m)
local function formatTime(sec)
    local t = tonumber(sec) or 0
    if t < 0 then t = 0 end
    -- REQUIRED: 0.04 min -> lesbar (Sekunden oder Min:Sekunden).
    -- Wenn ein Wert im Minuten-Format (0..1) reinkommt, konvertieren wir zu Sekunden.
    if t > 0 and t < 1 then
        t = t * 60
    end
    local secInt = math.floor(t)
    if secInt < 60 then
        return tostring(secInt) .. "s"
    end
    local m = math.floor(secInt / 60)
    local s = secInt % 60
    return string.format("%d:%02d", m, s)
end
local function GetInvAmt(itemName)
    local n=0
    pcall(function()
        local f=Svc.RS:WaitForChild("Player_Data",3):WaitForChild(LP.Name,3):WaitForChild("Items",3)
        local item=f:FindFirstChild(itemName); if not item then return end
        local vc=item:FindFirstChild("Value") or item:FindFirstChild("Amount")
        if vc then n=tonumber(vc.Value) or 0
        elseif item:IsA("IntValue") or item:IsA("NumberValue") then n=tonumber(item.Value) or 0 end
    end)
    return n
end

-- ── Save / Load ──────────────────────────────────────────────
local function SaveConfig()
    H.Config.GuiVisible = S.GuiVisible
    H.Config.SavedGoals={}
    for _,g in ipairs(S.Goals) do table.insert(H.Config.SavedGoals,{item=g.item,amount=g.amount}) end
    if writefile then pcall(function() writefile(GetAutoSaveFilePath(), Svc.Http:JSONEncode(H.Config)) end) end
end
local function LoadConfig()
    local savePath = GetAutoSaveFilePath()
    if not (isfile and isfile(savePath)) then return end
    local ok,data=pcall(function() return Svc.Http:JSONDecode(readfile(savePath)) end)
    if not ok or not data then return end
    local C=H.Config
    if data.WebhookURL~=nil then C.WebhookURL=data.WebhookURL end
    if data.UISize~=nil     then C.UISize=data.UISize         end
    if data.ToggleKey~=nil  then C.ToggleKey=data.ToggleKey   end
    if data.AutoRetry~=nil  then C.AutoRetry=data.AutoRetry   end
    if data.AutoFarm~=nil   then C.AutoFarm=data.AutoFarm     end
    if data.GuiVisible~=nil then S.GuiVisible=data.GuiVisible==true; C.GuiVisible=S.GuiVisible end
    if data.SavedGoals and type(data.SavedGoals)=="table" then
        for _,g in ipairs(data.SavedGoals) do
            if g.item and tonumber(g.amount) then
                table.insert(S.Goals,{item=g.item,amount=tonumber(g.amount),reached=false})
            end
        end
    end
end
local function SaveSettings()
    if not writefile then return end
    pcall(function() writefile(GetSettingsFilePath(), Svc.Http:JSONEncode({ AutoFarm = H.Config.AutoFarm, ts = os.time() })) end)
end
local function LoadSettings()
    local stPath = GetSettingsFilePath()
    if not (isfile and isfile(stPath)) then return end
    local ok, data = pcall(function() return Svc.Http:JSONDecode(readfile(stPath)) end)
    if not ok or not data then return end
    if data.AutoFarm~=nil then H.Config.AutoFarm=data.AutoFarm end
end

-- ── Remotes ──────────────────────────────────────────────────
local R={}
pcall(function() R.Remote=Svc.RS:WaitForChild("Remote",10):WaitForChild("Client",10):WaitForChild("UI",10):WaitForChild("GameEndedUI",10) end)
pcall(function() R.VoteRetry=Svc.RS:WaitForChild("Remote",10):WaitForChild("Server",10):WaitForChild("OnGame",10):WaitForChild("Voting",10):WaitForChild("VoteRetry",10) end)
pcall(function() R.PlayRoom=Svc.RS:WaitForChild("Remote",10):WaitForChild("Server",10):WaitForChild("PlayRoom",10):WaitForChild("Event",10) end)

local function PR(...) if R.PlayRoom then pcall(R.PlayRoom.FireServer,R.PlayRoom,...) end end
local function FireVoteRetry()
    task.spawn(function()
        task.wait(1)
        pcall(function()
            if R.VoteRetry then R.VoteRetry:FireServer()
            else Svc.RS.Remote.Server.OnGame.Voting.VoteRetry:FireServer() end
        end)
    end)
end
local function FireCreateAndStart(worldId,mode,chapId)
    task.spawn(function()
        pcall(function()
            PR("Create"); task.wait(0.3)
            if     mode=="Story"    then PR("Change-World",{World=worldId})
            elseif mode=="Ranger"   then PR("Change-Mode",{KeepWorld=worldId,Mode="Ranger Stage"})
            elseif mode=="Calamity" then PR("Change-Mode",{Mode="Calamity"}) end
            PR("Change-Chapter",{Chapter=chapId}); PR("Submit"); task.wait(0.5); PR("Start")
        end)
    end)
end

-- ── World-Scan ────────────────────────────────────────────────
-- Account-spezifischer Cache (wie Queue/DB), weiterhin LP.Name in allen Pfaden
local WORLD_CACHE_FILE = K.FOLDER .. "/" .. LP.Name .. "_WorldCache.json"
local function SaveWorldData()
    if not writefile then return end
    if next(S.WorldData) == nil then return end
    pcall(function() writefile(WORLD_CACHE_FILE, Svc.Http:JSONEncode({ worlds = S.WorldData, ids = S.WorldIds, ts = os.time() })) end)
end
local function LoadWorldCache()
    if not (isfile and isfile(WORLD_CACHE_FILE)) then return false end
    local ok,data=pcall(function() return Svc.Http:JSONDecode(readfile(WORLD_CACHE_FILE)) end)
    if not ok or not data or type(data.worlds)~="table" then return false end
    local count=0; for _ in pairs(data.worlds) do count=count+1 end
    if count==0 then return false end
    S.WorldData=data.worlds; S.WorldIds=data.ids or {}
    if #S.WorldIds==0 then
        for wid in pairs(S.WorldData) do table.insert(S.WorldIds,wid) end
        table.sort(S.WorldIds,function(a,b) return a:lower()<b:lower() end)
    end
    S.ScanDone=true; return true
end
local function ScanChapterFolder(folder)
    S.WorldData={}
    for _,wf in ipairs(folder:GetChildren()) do
        local wid=wf.Name; local story,ranger={},{}
        for _,btn in ipairs(wf:GetChildren()) do
            local n=btn.Name
            if n:find("_RangerStage") then table.insert(ranger,n)
            elseif n:find("_Chapter") and not wid:lower():find("calamity") then table.insert(story,n)
            elseif wid:lower():find("calamity") and n:find("_Chapter") then table.insert(story,n) end
        end
        local function bn(a,b) return (tonumber(a:match("(%d+)$")) or 0)<(tonumber(b:match("(%d+)$")) or 0) end
        table.sort(story,bn); table.sort(ranger,bn)
        if #story>0 or #ranger>0 then S.WorldData[wid]={story=story,ranger=ranger} end
    end
    local ids={}; for wid in pairs(S.WorldData) do table.insert(ids,wid) end
    table.sort(ids,function(a,b) return a:lower()<b:lower() end)
    S.WorldIds=ids; S.ScanDone=true
    task.spawn(function() pcall(SaveWorldData) end)
end
local function GetChapterFolder()
    if S.ChapFolderRef then return S.ChapFolderRef end
    local f
    pcall(function() f=Svc.Player.PlayerGui.PlayRoom.Main.GameStage.Main.Base.Chapter end)
    if not f then
        pcall(function()
            f=Svc.Player:WaitForChild("PlayerGui",10):WaitForChild("PlayRoom",10)
             :WaitForChild("Main",10):WaitForChild("GameStage",10)
             :WaitForChild("Main",10):WaitForChild("Base",10):WaitForChild("Chapter",10)
        end)
    end
    S.ChapFolderRef=f; return f
end
local function ApplyFallback()
    S.WorldData={
        JJK={story={"JJK_Chapter1","JJK_Chapter2","JJK_Chapter3","JJK_Chapter4","JJK_Chapter5"},ranger={"JJK_RangerStage1","JJK_RangerStage2","JJK_RangerStage3","JJK_RangerStage4"}},
        OnePiece={story={"OnePiece_Chapter1","OnePiece_Chapter2","OnePiece_Chapter3","OnePiece_Chapter4","OnePiece_Chapter5"},ranger={"OnePiece_RangerStage1","OnePiece_RangerStage2","OnePiece_RangerStage3"}},
        Naruto={story={"Naruto_Chapter1","Naruto_Chapter2","Naruto_Chapter3","Naruto_Chapter4","Naruto_Chapter5"},ranger={"Naruto_RangerStage1","Naruto_RangerStage2","Naruto_RangerStage3"}},
        Namek={story={"Namek_Chapter1","Namek_Chapter2","Namek_Chapter3","Namek_Chapter4","Namek_Chapter5"},ranger={"Namek_RangerStage1","Namek_RangerStage2","Namek_RangerStage3"}},
        TokyoGhoul={story={"TokyoGhoul_Chapter1","TokyoGhoul_Chapter2","TokyoGhoul_Chapter3","TokyoGhoul_Chapter4","TokyoGhoul_Chapter5"},ranger={"TokyoGhoul_RangerStage1","TokyoGhoul_RangerStage2","TokyoGhoul_RangerStage3"}},
        SAO={story={"SAO_Chapter1","SAO_Chapter2","SAO_Chapter3","SAO_Chapter4","SAO_Chapter5"},ranger={"SAO_RangerStage1","SAO_RangerStage2","SAO_RangerStage3"}},
        Calamity={story={"Calamity_Chapter1","Calamity_Chapter2"},ranger={}},
    }
    local ids={}; for wid in pairs(S.WorldData) do table.insert(ids,wid) end
    table.sort(ids,function(a,b) return a:lower()<b:lower() end)
    S.WorldIds=ids; S.ScanDone=true
end

-- Anti-AFK wird im Misc-Tab gestartet (neuer Kamera-basierter Anti-AFK)


-- ╔══════════════════════════════════════════════════════════╗
--  DESIGN – Glas-Schwarz + leichter Lighting-Blur (HazeHUB_Blur)
-- ╚══════════════════════════════════════════════════════════╝
-- Logo: Emblem-PNG nach Roblox hochladen → LogoRbx setzen (GUI + Mobile).
-- LogoHttps: gleiche Datei öffentlich hosten (z. B. raw.githubusercontent.com/.../haze_emblem_logo.png).
local HAZE_LOGO_ASSET_ID = "107582349721093"
local HAZE_ASSETS = {
    LogoRbx = "rbxassetid://" .. HAZE_LOGO_ASSET_ID,
    -- Discord kann keine rbxassetid://-Links; Roblox-Thumbnail derselben ID (fallback: GitHub raw)
    LogoHttps = "https://www.roblox.com/asset-thumbnail/image?assetId=" .. HAZE_LOGO_ASSET_ID .. "&width=420&height=420&format=png",
}
local D={
    GlassPane=0.2, GlassDeep=0.24, GlassStroke=0.4,
    BG=Color3.fromRGB(12,12,14), Sidebar=Color3.fromRGB(8,8,10),
    Card=Color3.fromRGB(22,22,24), CardHover=Color3.fromRGB(34,34,38),
    Input=Color3.fromRGB(18,18,20), TabActive=Color3.fromRGB(40,40,44),
    TabInactive=Color3.fromRGB(22,22,24),
    Accent=Color3.fromRGB(210,210,215), AccentDim=Color3.fromRGB(130,130,138),
    Cyan=Color3.fromRGB(200,200,206), CyanDim=Color3.fromRGB(115,115,122),
    Green=Color3.fromRGB(95,210,130), GreenDark=Color3.fromRGB(16,44,28), GreenBright=Color3.fromRGB(120,235,160),
    Red=Color3.fromRGB(215,75,75), RedDark=Color3.fromRGB(44,18,20),
    Yellow=Color3.fromRGB(220,190,85), Orange=Color3.fromRGB(220,145,70),
    Purple=Color3.fromRGB(175,125,220), Gold=Color3.fromRGB(225,190,115),
    Teal=Color3.fromRGB(150,175,170), Lavender=Color3.fromRGB(175,165,200),
    TextHi=Color3.fromRGB(235,235,238), TextMid=Color3.fromRGB(155,155,162),
    TextLow=Color3.fromRGB(105,105,112), Border=Color3.fromRGB(52,52,58),
    BorderCyan=Color3.fromRGB(88,88,94), RowSelect=Color3.fromRGB(46,46,50),
}
local TF=TweenInfo.new(0.15,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local TM=TweenInfo.new(0.25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local function Tw(o,p,ti) Svc.Tween:Create(o,ti or TF,p):Play() end

-- ── UI-Factories ─────────────────────────────────────────────
local function Corner(p,r)
    local c=Instance.new("UICorner",p); c.CornerRadius=UDim.new(0,r or 10); return c
end
local function Stroke(p,col,th,tr)
    local o=p:FindFirstChildOfClass("UIStroke"); if o then o:Destroy() end
    local s=Instance.new("UIStroke",p); s.Color=col or D.Border; s.Thickness=th or 1; s.Transparency=tr or 0; return s
end
local function Pad(p,pt,pr,pb,pl)
    local u=Instance.new("UIPadding",p)
    u.PaddingTop=UDim.new(0,pt or 6); u.PaddingRight=UDim.new(0,pr or 6)
    u.PaddingBottom=UDim.new(0,pb or 6); u.PaddingLeft=UDim.new(0,pl or 6)
end
local function VList(p,gap)
    local l=Instance.new("UIListLayout",p)
    l.FillDirection=Enum.FillDirection.Vertical; l.HorizontalAlignment=Enum.HorizontalAlignment.Left
    l.Padding=UDim.new(0,gap or 6); l.SortOrder=Enum.SortOrder.LayoutOrder; return l
end
local function HList(p,gap)
    local l=Instance.new("UIListLayout",p)
    l.FillDirection=Enum.FillDirection.Horizontal; l.VerticalAlignment=Enum.VerticalAlignment.Center
    l.Padding=UDim.new(0,gap or 6); l.SortOrder=Enum.SortOrder.LayoutOrder; return l
end
local function ApplySharpTypography(o)
    if not (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) then return end
    if o.Name == "StatNameLabel" then
        -- mobile-optimiert: lange Stat-Namen dürfen skalieren und wrapen
        o.TextScaled = true
        pcall(function() o.TextWrapped = true end)
    else
        o.TextScaled = false
    end
    o.RichText = true
    o.TextStrokeTransparency = 1
    if o.Name ~= "StatNameLabel" and o.TextSize > 0 and o.TextSize < 12 then o.TextSize = 12 end
    if o:IsA("TextBox") then
        if o.Font == Enum.Font.Gotham or o.Font == Enum.Font.GothamSemibold then o.Font = Enum.Font.GothamMedium end
        return
    end
    if o.Font == Enum.Font.Gotham or o.Font == Enum.Font.GothamSemibold then o.Font = Enum.Font.GothamMedium end
end
local function MkLbl(parent,text,size,color,bold,xa)
    local l=Instance.new("TextLabel",parent); l.BackgroundTransparency=1; l.Text=text or ""
    l.TextSize=size or 14; l.TextColor3=color or D.TextHi
    l.Font=bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
    l.TextXAlignment=xa or Enum.TextXAlignment.Left; l.TextWrapped=true
    l.TextScaled=false; l.RichText=true; l.TextStrokeTransparency=1
    l.Size=UDim2.new(1,0,0,(size or 14)+8); return l
end
local function SecLbl(p,t) local l=MkLbl(p,t,12,D.TextLow,false); l.Size=UDim2.new(1,0,0,16); return l end
local function Card(parent,fh,tGlass)
    local f=Instance.new("Frame",parent); f.BackgroundColor3=D.Card; f.BackgroundTransparency=tGlass or D.GlassPane; f.BorderSizePixel=0
    if fh then f.Size=UDim2.new(1,0,0,fh) else f.Size=UDim2.new(1,0,0,0); f.AutomaticSize=Enum.AutomaticSize.Y end
    Corner(f,8); Stroke(f,D.Border,1,D.GlassStroke); return f
end
local function NeonBtn(parent,text,accent,h)
    local acc=accent or D.Accent
    local b=Instance.new("TextButton",parent); b.Size=UDim2.new(1,0,0,h or 34); b.BackgroundColor3=D.CardHover; b.BackgroundTransparency=D.GlassPane
    b.Text=text; b.TextColor3=acc; b.TextSize=14; b.Font=Enum.Font.GothamBold
    b.TextScaled=false; b.RichText=true; b.TextStrokeTransparency=1
    b.AutoButtonColor=false; b.BorderSizePixel=0; Corner(b,8); Stroke(b,acc,1,0.4)
    local function ct(f) return Color3.fromRGB(math.clamp(math.floor(acc.R*255*f),0,255),math.clamp(math.floor(acc.G*255*f),0,255),math.clamp(math.floor(acc.B*255*f),0,255)) end
    b.MouseEnter:Connect(function() Tw(b,{BackgroundColor3=ct(0.22),BackgroundTransparency=D.GlassPane}) end)
    b.MouseLeave:Connect(function() Tw(b,{BackgroundColor3=D.CardHover,BackgroundTransparency=D.GlassPane}) end)
    b.MouseButton1Down:Connect(function() Tw(b,{BackgroundColor3=ct(0.40)}) end)
    b.MouseButton1Up:Connect(function() Tw(b,{BackgroundColor3=ct(0.25)}) end)
    return b
end
local function MkInput(parent,ph,h)
    local outer=Instance.new("Frame",parent); outer.Size=UDim2.new(1,0,0,h or 30); outer.BackgroundColor3=D.Input; outer.BackgroundTransparency=D.GlassPane; outer.BorderSizePixel=0
    Corner(outer,8); Stroke(outer,D.Border,1,0.25)
    local box=Instance.new("TextBox",outer); box.Size=UDim2.new(1,0,1,0); box.BackgroundTransparency=1
    box.PlaceholderText=ph or ""; box.PlaceholderColor3=D.TextLow; box.Text=""; box.TextColor3=D.TextHi
    box.TextSize=14; box.Font=Enum.Font.GothamMedium; box.ClearTextOnFocus=false; Pad(box,0,8,0,8)
    box.TextScaled=false; box.RichText=true; box.TextStrokeTransparency=1
    return outer,box
end

-- ── ★ IMAGE LOADER – Texture ID aus Assets.ItemModels.Models.[Cat].[Item].Objects.Front ──
-- Gibt die rbxassetid zurück oder nil
local function GetItemTextureId(itemName)
    local id = nil
    pcall(function()
        local modelsRoot = Svc.RS.Assets.ItemModels.Models
        -- Suche in allen Kategorien
        for _, catFolder in pairs(modelsRoot:GetChildren()) do
            if catFolder:IsA("Folder") or catFolder:IsA("Model") then
                local itemFolder = catFolder:FindFirstChild(itemName)
                if not itemFolder then
                    -- Case-insensitive
                    for _, ch in pairs(catFolder:GetChildren()) do
                        if ch.Name:lower() == itemName:lower() then itemFolder = ch; break end
                    end
                end
                if itemFolder then
                    local objFolder = itemFolder:FindFirstChild("Objects") or itemFolder
                    local front = objFolder:FindFirstChild("Front")
                    if front then
                        -- Versuche Texture-Property
                        local tex = front:FindFirstChildOfClass("Texture") or front:FindFirstChildOfClass("Decal")
                        if tex then
                            id = tostring(tex.Texture or tex.TextureId or "")
                        elseif front:IsA("BasePart") then
                            -- Kein Texture-Child → direkte Textur (falls MeshPart)
                            pcall(function() id = tostring(front.TextureID) end)
                        end
                        if id and id ~= "" then return end
                    end
                    local back = objFolder:FindFirstChild("Back")
                    if back then
                        local btex = back:FindFirstChildOfClass("Texture") or back:FindFirstChildOfClass("Decal")
                        if btex then
                            id = tostring(btex.Texture or btex.TextureId or "")
                        elseif back:IsA("BasePart") then
                            pcall(function() id = tostring(back.TextureID) end)
                        end
                        if id and id ~= "" and id ~= "rbxassetid://0" then return end
                    end
                    -- Fallback: alle BaseParts durchsuchen
                    for _, desc in pairs(itemFolder:GetDescendants()) do
                        if desc:IsA("Texture") or desc:IsA("Decal") then
                            local t = tostring(desc.Texture or desc.TextureId or "")
                            if t ~= "" and t ~= "rbxassetid://0" then id = t; return end
                        end
                    end
                end
            end
        end
    end)
    return id
end
_G.HazeShared.GetItemTextureId = GetItemTextureId

local function GetItemModelBounds(itemName)
    local foundModel=nil
    local maxDim=nil
    pcall(function()
        local modelsRoot = Svc.RS.Assets.ItemModels.Models
        for _, catFolder in pairs(modelsRoot:GetChildren()) do
            if catFolder:IsA("Folder") or catFolder:IsA("Model") then
                local itemFolder = catFolder:FindFirstChild(itemName)
                if not itemFolder then
                    for _, ch in pairs(catFolder:GetChildren()) do
                        if ch.Name:lower() == itemName:lower() then itemFolder = ch; break end
                    end
                end
                if itemFolder then
                    foundModel = itemFolder
                    break
                end
            end
        end
        if not foundModel then return end
        local minX,minY,minZ=math.huge,math.huge,math.huge
        local maxX,maxY,maxZ=-math.huge,-math.huge,-math.huge
        local count=0
        for _, d in pairs(foundModel:GetDescendants()) do
            if d:IsA("BasePart") then
                count=count+1
                local p=d.Position; local s=d.Size
                minX=math.min(minX,p.X-s.X*0.5); maxX=math.max(maxX,p.X+s.X*0.5)
                minY=math.min(minY,p.Y-s.Y*0.5); maxY=math.max(maxY,p.Y+s.Y*0.5)
                minZ=math.min(minZ,p.Z-s.Z*0.5); maxZ=math.max(maxZ,p.Z+s.Z*0.5)
            end
        end
        if count > 0 then
            local sx=maxX-minX; local sy=maxY-minY; local sz=maxZ-minZ
            maxDim = math.max(sx, sy, sz, 0.05)
        end
    end)
    return foundModel, maxDim
end

-- ── ★ VIEWPORT LOADER – Multi-Part zentriert aus Assets ──
local function LoadItemViewport(vp, itemName)
    pcall(function()
        for _,v in pairs(vp:GetDescendants()) do
            if v:IsA("Model") or v:IsA("Camera") or v:IsA("WorldModel") then v:Destroy() end
        end
    end)
    local ok=false
    pcall(function()
        local modelsFolder=nil
        pcall(function() modelsFolder=Svc.RS.Assets.ItemModels.Models end)
        if not modelsFolder then return end
        -- Suche in Kategorien
        local template=nil
        for _, cat in pairs(modelsFolder:GetChildren()) do
            template = cat:FindFirstChild(itemName)
            if not template then
                for _,ch in pairs(cat:GetChildren()) do
                    if ch.Name:lower()==itemName:lower() then template=ch; break end
                end
            end
            if template then break end
        end
        if not template then return end
        local wm=Instance.new("WorldModel"); wm.Parent=vp
        local clone=template:Clone(); clone.Parent=wm
        local cam=Instance.new("Camera"); cam.Parent=vp; vp.CurrentCamera=cam
        local parts={}
        for _,d in pairs(clone:GetDescendants()) do if d:IsA("BasePart") then table.insert(parts,d) end end
        if clone:IsA("BasePart") then table.insert(parts,clone) end
        if #parts==0 then return end
        local minX,minY,minZ=math.huge,math.huge,math.huge
        local maxX,maxY,maxZ=-math.huge,-math.huge,-math.huge
        for _,p in ipairs(parts) do
            local pos=p.Position; local sz=p.Size
            minX=math.min(minX,pos.X-sz.X/2); maxX=math.max(maxX,pos.X+sz.X/2)
            minY=math.min(minY,pos.Y-sz.Y/2); maxY=math.max(maxY,pos.Y+sz.Y/2)
            minZ=math.min(minZ,pos.Z-sz.Z/2); maxZ=math.max(maxZ,pos.Z+sz.Z/2)
        end
        local center=Vector3.new((minX+maxX)/2,(minY+maxY)/2,(minZ+maxZ)/2)
        local size=Vector3.new(maxX-minX,maxY-minY,maxZ-minZ)
        local maxDim=math.max(size.X,size.Y,size.Z,0.1)
        local dist=maxDim*1.8
        cam.CFrame=CFrame.new(center+Vector3.new(dist*0.5,dist*0.4,dist),center)
        ok=true
    end)
    return ok
end

-- ── ★ ITEM PREVIEW BUILDER – erst ImageLabel, dann ViewportFrame Fallback ──
local function BuildItemPreview(parent, itemName, size)
    size = size or 44
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(0,size,0,size)
    frame.BackgroundColor3 = D.Input
    frame.BackgroundTransparency = D.GlassPane
    frame.BorderSizePixel = 0
    Corner(frame, 6)

    task.spawn(function()
        -- Versuche zuerst Texture-ID
        local texId = GetItemTextureId(itemName)
        if texId and texId ~= "" and texId ~= "rbxassetid://0" then
            local img = Instance.new("ImageLabel", frame)
            local _, maxDim = GetItemModelBounds(itemName)
            local scale = 1
            if maxDim then
                if maxDim < 0.35 then
                    scale = 1.08
                elseif maxDim < 0.7 then
                    scale = 1.02
                elseif maxDim > 3.2 then
                    scale = 0.86
                elseif maxDim > 2.2 then
                    scale = 0.92
                else
                    scale = 0.98
                end
            end
            img.AnchorPoint = Vector2.new(0.5,0.5)
            img.Position = UDim2.new(0.5,0,0.5,0)
            img.Size = UDim2.new(scale,0,scale,0)
            img.BackgroundTransparency = 1
            img.Image = texId
            img.ScaleType = Enum.ScaleType.Fit
            Corner(img, 6)
            return
        end
        -- Fallback: ViewportFrame
        local vp = Instance.new("ViewportFrame", frame)
        vp.Size = UDim2.new(1,0,1,0)
        vp.BackgroundTransparency = 1
        vp.ImageColor3 = Color3.new(1,1,1)
        Corner(vp, 6)
        local loaded = LoadItemViewport(vp, itemName)
        if not loaded then
            -- Letter fallback
            local fb = Instance.new("TextLabel", frame)
            fb.Size = UDim2.new(1,0,1,0)
            fb.BackgroundTransparency = 1
            fb.Text = itemName:sub(1,1):upper()
            fb.TextColor3 = D.TextMid
            fb.TextSize = math.floor(size*0.45)
            fb.Font = Enum.Font.GothamBold
            fb.TextXAlignment = Enum.TextXAlignment.Center
            fb.TextYAlignment = Enum.TextYAlignment.Center
        end
    end)
    return frame
end

-- ── Drag ─────────────────────────────────────────────────────
local function MakeDraggable(frame,handle)
    local dragging,dragInput,dragStart,startPos
    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
            dragging=true; dragStart=inp.Position; startPos=frame.Position
            inp.Changed:Connect(function() if inp.UserInputState==Enum.UserInputState.End then dragging=false end end)
        end
    end)
    handle.InputChanged:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch then dragInput=inp end
    end)
    Svc.Input.InputChanged:Connect(function(inp)
        if inp==dragInput and dragging then
            local d=inp.Position-dragStart
            frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
end

-- ── Logo (Mond / Sterne – HAZE_ASSETS.LogoRbx oder Fallback) ──
local function BuildMoonLogo(parent,sz,lx,ly)
    sz = sz or 32
    local root = Instance.new("Frame", parent)
    root.Size = UDim2.new(0, sz, 0, sz)
    root.AnchorPoint = Vector2.new(0, 0)
    root.Position = UDim2.new(0, lx or 0, 0, ly or 0)
    root.BackgroundTransparency = 1
    root.BorderSizePixel = 0
    local ring = Instance.new("Frame", root)
    ring.Size = UDim2.new(1, 0, 1, 0)
    ring.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
    ring.BackgroundTransparency = D.GlassDeep
    ring.BorderSizePixel = 0
    Corner(ring, 99)
    Stroke(ring, D.Border, 1, 0.45)
    if HAZE_ASSETS.LogoRbx ~= "" and HAZE_ASSETS.LogoRbx ~= "rbxassetid://0" then
        local img = Instance.new("ImageLabel", ring)
        img.AnchorPoint = Vector2.new(0.5, 0.5)
        img.Size = UDim2.new(0.88, 0, 0.88, 0)
        img.Position = UDim2.new(0.5, 0, 0.5, 0)
        img.BackgroundTransparency = 1
        img.Image = HAZE_ASSETS.LogoRbx
        img.ScaleType = Enum.ScaleType.Fit
        Corner(img, 99)
        return root
    end
    local disc = Instance.new("Frame", ring)
    disc.Size = UDim2.new(0.82, 0, 0.82, 0)
    disc.Position = UDim2.new(0.09, 0, 0.09, 0)
    disc.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    disc.BackgroundTransparency = 0.1
    disc.BorderSizePixel = 0
    Corner(disc, 99)
    local moon = Instance.new("TextLabel", disc)
    moon.Size = UDim2.new(1, 0, 1, 0)
    moon.BackgroundTransparency = 1
    moon.Text = "☽"
    moon.TextColor3 = D.TextHi
    moon.TextTransparency = 0.05
    moon.TextSize = math.clamp(math.floor(sz * 0.52), 12, 42)
    moon.Font = Enum.Font.GothamBold
    moon.TextXAlignment = Enum.TextXAlignment.Center
    moon.TextYAlignment = Enum.TextYAlignment.Center
    moon.TextStrokeTransparency = 1
    moon.RichText = true
    local function star(px, py, r, tr)
        local d = Instance.new("Frame", disc)
        d.Size = UDim2.new(0, r, 0, r)
        d.Position = UDim2.new(px, -r / 2, py, -r / 2)
        d.BackgroundColor3 = D.TextHi
        d.BackgroundTransparency = tr or 0.2
        d.BorderSizePixel = 0
        Corner(d, 99)
    end
    star(0.78, 0.28, math.max(2, math.floor(sz / 14)), 0.15)
    star(0.68, 0.42, math.max(2, math.floor(sz / 18)), 0.35)
    star(0.85, 0.48, math.max(2, math.floor(sz / 20)), 0.4)
    return root
end

-- ╔══════════════════════════════════════════════════════════╗
--  SCREEN GUI  – AnchorPoint(0.5,0.5) → zentriert
-- ╚══════════════════════════════════════════════════════════╝
local ScreenGui=Instance.new("ScreenGui")
ScreenGui.Name="HazHub_Main"; ScreenGui.ResetOnSpawn=false
ScreenGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder=999; ScreenGui.IgnoreGuiInset=true
ScreenGui.Parent=guiParent
local LightingSvc = game:GetService("Lighting")
local HazeHubBlur = Instance.new("BlurEffect")
HazeHubBlur.Name = "HazeHUB_Blur"
HazeHubBlur.Size = 5
HazeHubBlur.Enabled = true
HazeHubBlur.Parent = LightingSvc
ScreenGui.AncestryChanged:Connect(function()
    if not ScreenGui.Parent and HazeHubBlur and HazeHubBlur.Parent then pcall(function() HazeHubBlur:Destroy() end) end
end)

H.UI.Fr.Main=Instance.new("Frame",ScreenGui)
H.UI.Fr.Main.Name="MainFrame"
local MainFrame=H.UI.Fr.Main
MainFrame.Size=UDim2.fromScale(0.40, 0.48)
MainFrame.AnchorPoint=Vector2.new(0.5,0.5)
MainFrame.Position=UDim2.new(0.5,0,0.5,0)
local MainAspect = Instance.new("UIAspectRatioConstraint", MainFrame)
MainAspect.Name = "MainAspect"
MainAspect.AspectRatio = 580 / 450
MainAspect.AspectType = Enum.AspectType.ScaleWithParentSize
MainAspect.DominantAxis = Enum.DominantAxis.Width
MainFrame.BackgroundColor3=D.BG
MainFrame.BackgroundTransparency=0.18
MainFrame.BorderSizePixel=0
Corner(MainFrame,12)
Stroke(MainFrame,D.Border,1.5,0.45)

local MainUIScale = Instance.new("UIScale", MainFrame)
MainUIScale.Name = "MainUIScale"
MainUIScale.Scale = 1

local headerStrip=Instance.new("Frame",MainFrame)
headerStrip.Size=UDim2.new(1,0,0,22); headerStrip.Position=UDim2.new(0,0,0,0)
headerStrip.BackgroundColor3=D.Sidebar; headerStrip.BackgroundTransparency=0.35
headerStrip.BorderSizePixel=0; Corner(headerStrip,12)
local headerBottom=Instance.new("Frame",MainFrame)
headerBottom.Size=UDim2.new(1,0,0,11); headerBottom.Position=UDim2.new(0,0,0,11)
headerBottom.BackgroundColor3=D.Sidebar; headerBottom.BackgroundTransparency=0.35; headerBottom.BorderSizePixel=0
local headerLine=Instance.new("Frame",MainFrame)
headerLine.Size=UDim2.new(1,0,0,1); headerLine.Position=UDim2.new(0,0,0,22)
headerLine.BackgroundColor3=D.Border; headerLine.BackgroundTransparency=0.45; headerLine.BorderSizePixel=0
local headerLogoSlot=Instance.new("Frame",headerStrip)
headerLogoSlot.Size=UDim2.new(0,22,0,22); headerLogoSlot.Position=UDim2.new(0,5,0.5,0); headerLogoSlot.AnchorPoint=Vector2.new(0,0.5)
headerLogoSlot.BackgroundTransparency=1; headerLogoSlot.BorderSizePixel=0
local _headerMoon=BuildMoonLogo(headerLogoSlot,20,0,0)
_headerMoon.AnchorPoint=Vector2.new(0.5,0.5); _headerMoon.Position=UDim2.new(0.5,0,0.5,0)
local headerTimerLbl=Instance.new("TextLabel",headerStrip)
headerTimerLbl.Size=UDim2.new(1,-120,1,0); headerTimerLbl.Position=UDim2.new(0,30,0,0)
headerTimerLbl.BackgroundTransparency=1; headerTimerLbl.Text="⏱  Session: 0s"
headerTimerLbl.TextColor3=D.TextLow; headerTimerLbl.TextSize=10; headerTimerLbl.Font=Enum.Font.GothamMedium
headerTimerLbl.TextScaled=false; headerTimerLbl.RichText=true; headerTimerLbl.TextStrokeTransparency=1
headerTimerLbl.TextXAlignment=Enum.TextXAlignment.Right; H.UI.Lbl.HeaderTimer=headerTimerLbl
task.spawn(function() while S.Running do task.wait(1); pcall(function() H.UI.Lbl.HeaderTimer.Text="⏱  Session: "..formatTime(os.time()-S.SessStart) end) end end)

-- Status indicators
local statusRow=Instance.new("Frame",headerStrip)
statusRow.Size=UDim2.new(0,80,0,20); statusRow.Position=UDim2.new(1,-85,0,1)
statusRow.BackgroundTransparency=1; HList(statusRow,4)

-- Autofarm Module Status
H.UI.Lbl.ModulStatus=Instance.new("TextLabel",statusRow)
H.UI.Lbl.ModulStatus.Size=UDim2.new(1,0,1,0); H.UI.Lbl.ModulStatus.BackgroundTransparency=1
H.UI.Lbl.ModulStatus.Text="🟠  Loading..."; H.UI.Lbl.ModulStatus.TextColor3=D.Orange
H.UI.Lbl.ModulStatus.TextSize=8; H.UI.Lbl.ModulStatus.Font=Enum.Font.GothamMedium
H.UI.Lbl.ModulStatus.TextXAlignment=Enum.TextXAlignment.Left

-- Lobby/Round Status
H.UI.Lbl.LobbyStatus=Instance.new("Frame",statusRow)
H.UI.Lbl.LobbyStatus.Size=UDim2.new(0,50,0,16); H.UI.Lbl.LobbyStatus.BackgroundColor3=Color3.fromRGB(20,25,35)
H.UI.Lbl.LobbyStatus.BackgroundTransparency=0.8; H.UI.Lbl.LobbyStatus.BorderSizePixel=0
Corner(H.UI.Lbl.LobbyStatus,8); Stroke(H.UI.Lbl.LobbyStatus,D.Green,1,0.3)

local lobbyIcon=Instance.new("Frame",H.UI.Lbl.LobbyStatus)
lobbyIcon.Size=UDim2.new(0,8,0,8); lobbyIcon.Position=UDim2.new(0,4,0.5,-4)
lobbyIcon.BackgroundColor3=D.Green; lobbyIcon.BorderSizePixel=0; Corner(lobbyIcon,99)

local lobbyText=Instance.new("TextLabel",H.UI.Lbl.LobbyStatus)
lobbyText.Size=UDim2.new(1,-16,1,0); lobbyText.Position=UDim2.new(0,14,0,0)
lobbyText.BackgroundTransparency=1; lobbyText.Text="LOBBY"; lobbyText.TextColor3=D.Green
lobbyText.TextSize=9; lobbyText.Font=Enum.Font.GothamBold; lobbyText.TextXAlignment=Enum.TextXAlignment.Left

-- Update lobby status function
local function UpdateLobbyStatus()
    pcall(function()
        local inLobby = game.PlaceId and game.PlaceId == K.LOBBY_ID
        if H.UI.Lbl.LobbyStatus and lobbyText and lobbyIcon then
            if inLobby then
                lobbyText.Text = "LOBBY"
                lobbyIcon.BackgroundColor3 = D.Green
                lobbyText.TextColor3 = D.Green
                Stroke(H.UI.Lbl.LobbyStatus,D.Green,1,0.3)
            else
                lobbyText.Text = "RUNDE"
                lobbyIcon.BackgroundColor3 = D.Orange
                lobbyText.TextColor3 = D.Orange
                Stroke(H.UI.Lbl.LobbyStatus,D.Orange,1,0.3)
            end
        end
    end)
end

-- Update lobby status every 2 seconds
task.spawn(function()
    while S.Running do
        task.wait(2)
        UpdateLobbyStatus()
    end
end)

local glow=Instance.new("Frame",MainFrame)
glow.Size=UDim2.new(1,0,0.35,0); glow.BackgroundColor3=Color3.fromRGB(255,255,255); glow.BackgroundTransparency=0.965; glow.BorderSizePixel=0; Corner(glow,12)
Instance.new("UIGradient",glow).Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(200,210,215)),ColorSequenceKeypoint.new(1,Color3.fromRGB(0,0,0))})

H.UI.Fr.Sidebar=Instance.new("Frame",MainFrame)
H.UI.Fr.Sidebar.Name="Sidebar"; H.UI.Fr.Sidebar.BackgroundColor3=D.Sidebar
H.UI.Fr.Sidebar.BackgroundTransparency=0.14; H.UI.Fr.Sidebar.BorderSizePixel=0; Corner(H.UI.Fr.Sidebar,10)
local sStripe=Instance.new("Frame",H.UI.Fr.Sidebar)
sStripe.Size=UDim2.new(0,2,0.65,0); sStripe.Position=UDim2.new(0,0,0.175,0)
sStripe.BackgroundColor3=D.Accent; sStripe.BorderSizePixel=0; Corner(sStripe,2)
Instance.new("UIGradient",sStripe).Color=ColorSequence.new({ColorSequenceKeypoint.new(0,D.AccentDim),ColorSequenceKeypoint.new(0.5,D.Accent),ColorSequenceKeypoint.new(1,D.AccentDim)})
local lf=Instance.new("Frame",H.UI.Fr.Sidebar)
lf.Size=UDim2.new(1,0,0,46); lf.Position=UDim2.new(0,0,0,2); lf.BackgroundTransparency=1
local sl=BuildMoonLogo(lf,32,0,7); sl.AnchorPoint=Vector2.new(0.5,0); sl.Position=UDim2.new(0.5,0,0,7)
H.UI.Fr.TabScroll = Instance.new("ScrollingFrame", H.UI.Fr.Sidebar)
H.UI.Fr.TabScroll.Name = "TabScroll"
H.UI.Fr.TabScroll.Position = UDim2.new(0, 0, 0, 52)
H.UI.Fr.TabScroll.Size = UDim2.new(1, 0, 1, -56)
H.UI.Fr.TabScroll.BackgroundTransparency = 1
H.UI.Fr.TabScroll.BorderSizePixel = 0
H.UI.Fr.TabScroll.ClipsDescendants = true
H.UI.Fr.TabScroll.ScrollingDirection = Enum.ScrollingDirection.Y
H.UI.Fr.TabScroll.ScrollBarThickness = 0
H.UI.Fr.TabScroll.ScrollingEnabled = true
H.UI.Fr.TabScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
H.UI.Fr.TabScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
H.UI.Fr.TabScroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
H.UI.Fr.TabHolder = Instance.new("Frame", H.UI.Fr.TabScroll)
H.UI.Fr.TabHolder.Name = "TabHolder"
H.UI.Fr.TabHolder.Size = UDim2.new(1, 0, 0, 0)
H.UI.Fr.TabHolder.AutomaticSize = Enum.AutomaticSize.Y
H.UI.Fr.TabHolder.BackgroundTransparency = 1
H.UI.Fr.TabHolder.BorderSizePixel = 0
local tabBarList = VList(H.UI.Fr.TabHolder, 3)
Pad(H.UI.Fr.TabHolder, 3, 5, 3, 5)
local function SyncTabScrollCanvas()
    -- AutomaticCanvasSize=Y übernimmt das Canvas; manueller Sync nur als Fallback
    pcall(function()
        local needed = tabBarList.AbsoluteContentSize.Y + 12
        if H.UI.Fr.TabScroll.AutomaticCanvasSize == Enum.AutomaticSize.None then
            H.UI.Fr.TabScroll.CanvasSize = UDim2.new(0, 0, 0, needed)
        end
    end)
end
tabBarList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(SyncTabScrollCanvas)
task.defer(SyncTabScrollCanvas)
H.UI.Fr.Content=Instance.new("Frame",MainFrame); H.UI.Fr.Content.Name="Content"; H.UI.Fr.Content.BackgroundTransparency=1

-- ── Tab-System ────────────────────────────────────────────────
local function SelectTab(name)
    for n,p in pairs(H.Tabs) do p.Visible=(n==name) end
    for n,b in pairs(H.TBtns) do
        local s=b:FindFirstChildOfClass("UIStroke")
        if n==name then
            b.BackgroundColor3=D.TabActive; b.TextColor3=D.Accent; b.BackgroundTransparency=D.GlassPane
            if s then s.Transparency=0; s.Color=D.Accent end
        else
            b.BackgroundColor3=D.TabInactive; b.TextColor3=D.TextMid; b.BackgroundTransparency=D.GlassPane
            if s then s.Transparency=1 end
        end
    end
    S.ActiveTab=name
end
local function MakeTab(name,icon)
    local B=Instance.new("TextButton",H.UI.Fr.TabHolder)
    B.Size=UDim2.new(1,0,0,34); B.BackgroundColor3=D.TabInactive; B.BackgroundTransparency=D.GlassPane
    B.Text=icon.."  "..name; B.TextColor3=D.TextMid; B.TextSize=12
    B.Font=Enum.Font.GothamMedium; B.TextScaled=false; B.RichText=true; B.TextStrokeTransparency=1
    B.TextTruncate=Enum.TextTruncate.AtEnd
    B.AutoButtonColor=false; B.BorderSizePixel=0
    Corner(B,8); Stroke(B,D.Accent,1,1)
    B.MouseEnter:Connect(function() if S.ActiveTab~=name then Tw(B,{BackgroundColor3=D.CardHover}) end end)
    B.MouseLeave:Connect(function() if S.ActiveTab~=name then Tw(B,{BackgroundColor3=D.TabInactive}) end end)
    local P=Instance.new("ScrollingFrame",H.UI.Fr.Content)
    P.Name=name; P.Size=UDim2.new(1,0,1,0); P.Visible=false
    P.BackgroundTransparency=1; P.ScrollBarThickness=0
    P.ScrollingEnabled=true
    P.ScrollBarImageColor3=D.CyanDim; P.AutomaticCanvasSize=Enum.AutomaticSize.Y
    P.BorderSizePixel=0; VList(P,8); Pad(P,10,10,10,10)
    H.Tabs[name]=P; H.TBtns[name]=B; B.MouseButton1Click:Connect(function() SelectTab(name) end)
    return P
end

local function MakeTraitsTab(name, icon)
    local B = Instance.new("TextButton", H.UI.Fr.TabHolder)
    B.Size = UDim2.new(1, 0, 0, 34)
    B.BackgroundColor3 = D.TabInactive
    B.BackgroundTransparency = D.GlassPane
    B.Text = icon .. "  " .. name
    B.TextColor3 = D.TextMid
    B.TextSize = 12
    B.Font = Enum.Font.GothamMedium
    B.TextScaled = false; B.RichText = true; B.TextStrokeTransparency = 1
    B.TextTruncate = Enum.TextTruncate.AtEnd
    B.AutoButtonColor = false
    B.BorderSizePixel = 0
    Corner(B, 8)
    Stroke(B, D.Accent, 1, 1)
    B.MouseEnter:Connect(function() if S.ActiveTab ~= name then Tw(B, { BackgroundColor3 = D.CardHover }) end end)
    B.MouseLeave:Connect(function() if S.ActiveTab ~= name then Tw(B, { BackgroundColor3 = D.TabInactive }) end end)
    -- Ein äußeres ScrollingFrame: gesamter Trait-Tab (Sticky + Inhalt) vertikal, AutomaticCanvasSize Y
    local TraitRoot = Instance.new("ScrollingFrame", H.UI.Fr.Content)
    TraitRoot.Name = name
    TraitRoot.Size = UDim2.new(1, 0, 1, 0)
    TraitRoot.Visible = false
    TraitRoot.BackgroundTransparency = 1
    TraitRoot.BorderSizePixel = 0
    TraitRoot.ClipsDescendants = true
    TraitRoot.ScrollingDirection = Enum.ScrollingDirection.Y
    TraitRoot.ScrollBarThickness = 0
    TraitRoot.ScrollBarImageColor3 = D.CyanDim
    TraitRoot.ScrollingEnabled = true
    TraitRoot.AutomaticCanvasSize = Enum.AutomaticSize.Y
    TraitRoot.CanvasSize = UDim2.new(0, 0, 0, 0)
    TraitRoot.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable

    local TraitContent = Instance.new("Frame", TraitRoot)
    TraitContent.Name = "TraitContent"
    TraitContent.Size = UDim2.new(1, 0, 0, 0)
    TraitContent.AutomaticSize = Enum.AutomaticSize.Y
    TraitContent.BackgroundTransparency = 1
    TraitContent.BorderSizePixel = 0

    local rootList = Instance.new("UIListLayout", TraitContent)
    rootList.FillDirection = Enum.FillDirection.Vertical
    rootList.SortOrder = Enum.SortOrder.LayoutOrder
    rootList.Padding = UDim.new(0, 6)
    rootList.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local TraitSticky = Instance.new("Frame", TraitContent)
    TraitSticky.Name = "TraitSticky"
    TraitSticky.Size = UDim2.new(1, 0, 0, 0)
    TraitSticky.AutomaticSize = Enum.AutomaticSize.Y
    TraitSticky.BackgroundTransparency = 1
    TraitSticky.LayoutOrder = 1
    VList(TraitSticky, 6)
    Pad(TraitSticky, 4, 10, 4, 10)

    local TraitPage = Instance.new("Frame", TraitContent)
    TraitPage.Name = "TraitPage"
    TraitPage.Size = UDim2.new(1, 0, 0, 0)
    TraitPage.AutomaticSize = Enum.AutomaticSize.Y
    TraitPage.BackgroundTransparency = 1
    TraitPage.BorderSizePixel = 0
    TraitPage.LayoutOrder = 2
    VList(TraitPage, 8)
    Pad(TraitPage, 10, 10, 10, 10)

    H.Tabs[name] = TraitRoot
    H.TBtns[name] = B
    B.MouseButton1Click:Connect(function() SelectTab(name) end)
    return TraitRoot, TraitSticky, TraitPage
end

local GamePage  = MakeTab("Game","◈")
local SessPage  = MakeTab("Session","◎")
local QuestPage = MakeTab("Quests","≡")
local ShopPage  = MakeTab("Shops","▤")
local CraftPage = MakeTab("Crafting","⚒")
local TraitRoot, TraitSticky, TraitPage = MakeTraitsTab("Traits", "✦")
local TeamsPage = MakeTab("Teams","⚔")
local InvPage   = MakeTab("Inventory","▣")
local MiscPage  = MakeTab("Misc","◇")
local SettPage  = MakeTab("Settings","⛭")

-- Sofort setzen für Module
_G.HazeShared.ShopContainer = ShopPage
_G.HazeShared.CraftPage     = CraftPage
_G.HazeShared.TraitPage     = TraitPage
_G.HazeShared.TraitSticky   = TraitSticky
_G.HazeShared.TraitPageRoot = TraitRoot
_G.HazeShared.TeamsPage     = TeamsPage

-- ── Touch / Mobile Layout Sync (Tabs + Trait-Modul) ───────────
local function UpdateLayoutForMobile()
    local touch = Svc.Input.TouchEnabled
    H._isTouchClient = touch
    _G.HazeShared._isTouchClient = touch
    -- TabScroll: bei Touch dünne Scrollbar für Feedback, sonst unsichtbar
    pcall(function()
        H.UI.Fr.TabScroll.ScrollBarThickness = touch and 3 or 0
        H.UI.Fr.TabScroll.ScrollingEnabled = true
        H.UI.Fr.TabScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    end)
    pcall(SyncTabScrollCanvas)
    pcall(function()
        local traitsTab = H.UI.Fr.Content:FindFirstChild("Traits")
        if traitsTab and traitsTab:IsA("ScrollingFrame") then
            traitsTab.ScrollBarThickness = touch and 6 or 0
            traitsTab.ScrollingEnabled = true
            traitsTab.AutomaticCanvasSize = Enum.AutomaticSize.Y
        end
    end)
    if _G.HazeShared._ApplyTraitResponsiveLayout then
        task.defer(function() pcall(_G.HazeShared._ApplyTraitResponsiveLayout) end)
    end
end

-- ── GUI-Resize ────────────────────────────────────────────────
-- Kompakt: 70%/80% der PC-Scale (kleiner als Desktop); UIScale nur bei Touch
local PC_FRAME_SCALE_X, PC_FRAME_SCALE_Y = 0.40, 0.48
-- Mobile: 85% Breite, 68% Hoehe des Bildschirms
local MOBILE_FRAME = UDim2.new(0.855, 0, 0.684, 0)
local TOUCH_MAIN_UI_SCALE = 1.0   -- kein zusaetzlicher Scale-Shrink auf Mobile

local function SetGUISize(mode)
    H.Config.UISize=mode; SaveConfig()
    local ma = MainFrame:FindFirstChild("MainAspect")
    local us = MainFrame:FindFirstChildOfClass("UIScale")
    if not us then
        us = Instance.new("UIScale", MainFrame)
        us.Name = "MainUIScale"
    end
    local touch = Svc.Input.TouchEnabled
    local useCompact = (mode == "Mobile" or touch)
    H.UI.Fr.Sidebar.Position=UDim2.new(0,0,0,0)
    if useCompact then
        MainFrame.Size = MOBILE_FRAME
        -- Seitenverhaeltnis fuer 90% x 72%
        if ma then ma.AspectRatio = 0.855 / 0.684; ma.DominantAxis = Enum.DominantAxis.Width end
        -- Sidebar 32%, Content 68%
        H.UI.Fr.Sidebar.Size=UDim2.new(0.32, 0, 1, 0)
        H.UI.Fr.Content.Position=UDim2.new(0.32, 4, 0, 25)
        H.UI.Fr.Content.Size=UDim2.new(0.68, -6, 1, -33)
    else
        MainFrame.Size=UDim2.fromScale(PC_FRAME_SCALE_X, PC_FRAME_SCALE_Y)
        if ma then ma.AspectRatio = 580 / 450 end
        H.UI.Fr.Sidebar.Size=UDim2.new(0.22, 0, 1, 0)
        H.UI.Fr.Content.Position=UDim2.new(0.22, 6, 0, 25)
        H.UI.Fr.Content.Size=UDim2.new(0.78, -8, 1, -33)
    end
    us.Scale = touch and TOUCH_MAIN_UI_SCALE or 1
    UpdateLayoutForMobile()
end

--- ── Webhook (Gesamt-Session, kumuliert) ───────────────────────
local function SendWebhook(_a,_b,_c)
    if not S.WhEnabled then return end
    if not H.Config.WebhookURL or H.Config.WebhookURL=="" or not H.Config.WebhookURL:find("discord.com") then return end
    local gs = GlobalSession
    local cr = math.floor(tonumber(gs.CurrentRound) or 0)
    local totalSec = math.floor(tonumber(gs.TotalTime) or 0)
    local avgSec = 0
    if cr > 0 then avgSec = math.floor(totalSec / cr + 0.5) end
    local avgStr = cr > 0 and formatTime(avgSec) or "–"
    local timeStr = cr > 0 and formatTime(totalSec) or "–"
    local goldN = math.floor(tonumber(gs.AllRewards.Gold) or 0)
    local gemsN = math.floor(tonumber(gs.AllRewards.Gems) or tonumber(gs.AllRewards.Gem) or 0)
    local expN = math.floor(tonumber(gs.AllRewards.Exp) or 0)
    local statsBlock = table.concat({
        "🟡 Gold · `" .. FmtNum(goldN) .. "`",
        "💎 Gems · `" .. FmtNum(gemsN) .. "`",
        "✨ Exp · `" .. FmtNum(expN) .. "`",
    }, "\n")
    local itemLines = {}
    local sorted = {}
    for name, amt in pairs(gs.AllRewards) do
        if not IsSessionCurrencyKey(name) then table.insert(sorted, { name = name, total = amt }) end
    end
    table.sort(sorted, function(a, b) return a.total > b.total end)
    for i, it in ipairs(sorted) do
        if i > 28 then table.insert(itemLines, "… +" .. tostring(#sorted - 28) .. " weitere"); break end
        table.insert(itemLines, string.format("▸ **%s** × `%s`", it.name, FmtNum(math.floor(tonumber(it.total) or 0))))
    end
    local itemsTxt = #itemLines > 0 and table.concat(itemLines, "\n") or "*Keine Item-Drops in dieser Session erfasst.*"
    itemsTxt = itemsTxt:sub(1, 3200)
    local ava = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. tostring(LP.UserId) .. "&width=150&height=150&format=png"
    local logoOk = HAZE_ASSETS.LogoHttps and #HAZE_ASSETS.LogoHttps > 12 and HAZE_ASSETS.LogoHttps:find("^https?://")
    local whAvatar = logoOk and HAZE_ASSETS.LogoHttps or ava
    local thumbUrl = logoOk and HAZE_ASSETS.LogoHttps or ava
    local tsFooter = os.date("%Y-%m-%d %H:%M:%S")
    local embed = {
        color = 0x000000,
        title = "Session · Haze Hub",
        description = "*Kumulierte Werte dieser Sitzung*",
        thumbnail = { url = thumbUrl },
        fields = {
            { name = "Account", value = "`" .. LP.Name .. "`", inline = true },
            { name = "Runde", value = "`" .. tostring(cr) .. "`", inline = true },
            { name = "Ø Zeit", value = "`" .. avgStr .. "`", inline = true },
            { name = "Rundenzeit (gesamt)", value = "`" .. timeStr .. "`", inline = false },
            { name = "Währungen & XP", value = statsBlock, inline = false },
            { name = "Items", value = itemsTxt, inline = false },
        },
    }
    embed.footer = logoOk and { text = "Session Bericht • " .. tsFooter, icon_url = HAZE_ASSETS.LogoHttps }
        or { text = "Session Bericht • " .. tsFooter }
    task.spawn(function()
        pcall(function()
            local fn = request or http_request or (syn and syn.request)
            if not fn then return end
            fn({
                Url = H.Config.WebhookURL:gsub("discord%.com", "webhook.lewisakura.moe"),
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = Svc.Http:JSONEncode({ username = "Haze Hub", avatar_url = whAvatar, embeds = { embed } }),
            })
        end)
    end)
end

local function CheckAllGoals()
    for _, g in ipairs(S.Goals) do
        if not g.reached and not S.GoalsNotified[g.item] then
            local cur = math.max(GlobalSession.AllRewards[g.item] or 0, GetInvAmt(g.item))
            if cur >= g.amount then
                g.reached = true
                S.GoalsNotified[g.item] = true
                task.spawn(function() SendWebhook() end)
                SaveConfig()
            end
        end
    end
    if UpdateGoalsUI then pcall(UpdateGoalsUI) end
end

-- ╔══════════════════════════════════════════════════════════╗
--  GAME TAB
-- ╚══════════════════════════════════════════════════════════╝
pcall(function()
MkLbl(GamePage,"🎮  Game",14,D.Cyan,true)

-- === STATUS-ANZEIGEN (horizontal nebeneinander) ===
local statusRow=Instance.new("Frame",GamePage); statusRow.Size=UDim2.new(1,0,0,30); statusRow.BackgroundTransparency=1; HList(statusRow,10)

-- Autofarm-Modul Status
local afStatusCard=Card(statusRow,30); afStatusCard.Size=UDim2.new(0.5,-5,1,0); Pad(afStatusCard,8,8,8,8)
H.UI.Lbl.ModulStatus=Instance.new("TextLabel",afStatusCard)
H.UI.Lbl.ModulStatus.Size=UDim2.new(1,0,1,0); H.UI.Lbl.ModulStatus.BackgroundTransparency=1
H.UI.Lbl.ModulStatus.Text="⏳  Autofarm-Modul lädt..."; H.UI.Lbl.ModulStatus.TextColor3=D.Yellow
H.UI.Lbl.ModulStatus.TextSize=10; H.UI.Lbl.ModulStatus.Font=Enum.Font.GothamSemibold
H.UI.Lbl.ModulStatus.TextXAlignment=Enum.TextXAlignment.Center

-- Datenbank Status
local dbStatusCard=Card(statusRow,30); dbStatusCard.Size=UDim2.new(0.5,-5,1,0); Pad(dbStatusCard,8,8,8,8)
H.UI.Lbl.DBStatus=Instance.new("TextLabel",dbStatusCard)
H.UI.Lbl.DBStatus.Size=UDim2.new(1,0,1,0); H.UI.Lbl.DBStatus.BackgroundTransparency=1
H.UI.Lbl.DBStatus.Text="⏳  Datenbank lädt..."; H.UI.Lbl.DBStatus.TextColor3=D.Yellow
H.UI.Lbl.DBStatus.TextSize=10; H.UI.Lbl.DBStatus.Font=Enum.Font.GothamSemibold
H.UI.Lbl.DBStatus.TextXAlignment=Enum.TextXAlignment.Center

-- === RAID FARM SEKTION (ganz oben) ===
local raidCard=Card(GamePage); Pad(raidCard,10,10,10,10); VList(raidCard,8); SecLbl(raidCard,"⚔ RAID FARM")
local raidRow=Instance.new("Frame",raidCard); raidRow.Size=UDim2.new(1,0,0,36); raidRow.BackgroundTransparency=1; HList(raidRow,10)

-- Esper Raid Button
local esperBtn=NeonBtn(raidRow,"🔮 ESPER RAID",D.Purple,32); esperBtn.Size=UDim2.new(0.5,-5,1,0)
esperBtn.MouseButton1Click:Connect(function()
    if _G.HazeHUB.StartRaid and type(_G.HazeHUB.StartRaid) == "function" then
        _G.HazeHUB.StartRaid()
    else
        warn("[HazeHUB] StartRaid Funktion nicht gefunden!")
    end
end)

-- JJK Raid Button
local jjkBtn=NeonBtn(raidRow,"🗡️ JJK RAID",D.Red,32); jjkBtn.Size=UDim2.new(0.5,-5,1,0)
jjkBtn.MouseButton1Click:Connect(function()
    if _G.HazeHUB.StartRaid and type(_G.HazeHUB.StartRaid) == "function" then
        _G.HazeHUB.StartRaid()
    else
        warn("[HazeHUB] StartRaid Funktion nicht gefunden!")
    end
end)

-- === WELT & KAPITEL AUSWAHL (ohne Raid) ===
local wCard=Card(GamePage); Pad(wCard,10,10,10,10); VList(wCard,8); SecLbl(wCard,"WELT & KAPITEL AUSWAHL")
H.UI.Lbl.WorldStatus=Instance.new("TextLabel",wCard)
H.UI.Lbl.WorldStatus.Size=UDim2.new(1,0,0,16); H.UI.Lbl.WorldStatus.BackgroundTransparency=1
H.UI.Lbl.WorldStatus.Text="Modus → Welt → Kapitel"; H.UI.Lbl.WorldStatus.TextColor3=D.TextLow
H.UI.Lbl.WorldStatus.TextSize=11; H.UI.Lbl.WorldStatus.Font=Enum.Font.GothamSemibold
H.UI.Lbl.WorldStatus.TextXAlignment=Enum.TextXAlignment.Left

-- Welten-Refresh Button
local refreshRow=Instance.new("Frame",wCard); refreshRow.Size=UDim2.new(1,0,0,32); refreshRow.BackgroundTransparency=1; HList(refreshRow,6)
local refreshBtn=NeonBtn(refreshRow,"🔄 Welten neu scannen",D.Cyan,28)
refreshBtn.Size=UDim2.new(1,0,0,32)
refreshBtn.MouseButton1Click:Connect(function()
    if _G.HazeHUB.RefreshWorlds and type(_G.HazeHUB.RefreshWorlds) == "function" then
        pcall(_G.HazeHUB.RefreshWorlds)
    else
        warn("[HazeHUB] RefreshWorlds Funktion nicht gefunden!")
    end
end)
SecLbl(wCard,"SPIELMODUS")
local modeRow=Instance.new("Frame",wCard); modeRow.Size=UDim2.new(1,0,0,28); modeRow.BackgroundTransparency=1; HList(modeRow,6)
local MODI={{id="Story",label="📖 Story",color=D.Cyan},{id="Ranger",label="🏹 Ranger",color=D.Green},{id="Calamity",label="⚡ Calamity",color=D.Orange}}
H.UI.Btn.ModeBtns={}
local function HighlightMode(activeId)
    for _,def in ipairs(MODI) do
        local mb=H.UI.Btn.ModeBtns[def.id]; if not mb then continue end
        if def.id==activeId then
            local c=def.color
            Tw(mb,{BackgroundColor3=Color3.fromRGB(math.clamp(math.floor(c.R*255*0.22),0,255),math.clamp(math.floor(c.G*255*0.22),0,255),math.clamp(math.floor(c.B*255*0.22),0,255))})
            Stroke(mb,c,1.5,0)
        else
            Tw(mb,{BackgroundColor3=D.CardHover}); Stroke(mb,D.Border,1,0.5)
        end
    end
end
H.UI.Fr.DiffCard=Card(wCard); Pad(H.UI.Fr.DiffCard,8,8,8,8); VList(H.UI.Fr.DiffCard,5); H.UI.Fr.DiffCard.Visible=true; SecLbl(H.UI.Fr.DiffCard,"SCHWIERIGKEIT")
local diffRow=Instance.new("Frame",H.UI.Fr.DiffCard); diffRow.Size=UDim2.new(1,0,0,26); diffRow.BackgroundTransparency=1; HList(diffRow,6)
local DC={Normal=D.Green,Hard=D.Orange,Nightmare=D.Red}; local diffBtns={}
for _,diff in ipairs({"Normal","Hard","Nightmare"}) do
    local db=Instance.new("TextButton",diffRow); db.Size=UDim2.new(0.32,0,0,24); db.BackgroundColor3=D.CardHover
    db.Text=diff; db.TextColor3=DC[diff]; db.TextSize=10; db.Font=Enum.Font.GothamBold
    db.AutoButtonColor=false; db.BorderSizePixel=0; Corner(db,7); Stroke(db,DC[diff],1,0.4)
    db.MouseButton1Click:Connect(function()
        PR("Change-Difficulty",{Difficulty=diff})
        for _,b in pairs(diffBtns) do Tw(b,{BackgroundColor3=D.CardHover}); local s=b:FindFirstChildOfClass("UIStroke"); if s then s.Transparency=0.4 end end
        Tw(db,{BackgroundColor3=Color3.fromRGB(math.clamp(math.floor(DC[diff].R*255*0.25),0,255),math.clamp(math.floor(DC[diff].G*255*0.25),0,255),math.clamp(math.floor(DC[diff].B*255*0.25),0,255))})
        local s=db:FindFirstChildOfClass("UIStroke"); if s then s.Transparency=0 end
    end)
    diffBtns[diff]=db
end
local chapCard=Card(wCard); Pad(chapCard,8,8,8,8); VList(chapCard,5); SecLbl(chapCard,"KAPITEL / STAGE")
H.UI.Fr.ChapRow=Instance.new("Frame",chapCard); H.UI.Fr.ChapRow.Size=UDim2.new(1,0,0,0)
H.UI.Fr.ChapRow.AutomaticSize=Enum.AutomaticSize.Y; H.UI.Fr.ChapRow.BackgroundTransparency=1; HList(H.UI.Fr.ChapRow,4); H.UI.Fr.ChapBtns={}
local function RebuildChapBtns(chapList)
    for _,v in pairs(H.UI.Fr.ChapRow:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end
    H.UI.Fr.ChapBtns={}; if not chapList or #chapList==0 then return end
    S.SelChap=chapList[1]
    for i,cid in ipairs(chapList) do
        local num=cid:match("(%d+)$") or tostring(i)
        local cb=Instance.new("TextButton",H.UI.Fr.ChapRow)
        cb.Size=UDim2.new(0,34,0,26); cb.BackgroundColor3=D.CardHover; cb.Text=num
        cb.TextColor3=D.TextHi; cb.TextSize=12; cb.Font=Enum.Font.GothamBold
        cb.AutoButtonColor=false; cb.BorderSizePixel=0; Corner(cb,7); Stroke(cb,D.Border,1,0.4)
        local capCid=cid
        cb.MouseButton1Click:Connect(function()
            S.SelChap=capCid
            for _,b in pairs(H.UI.Fr.ChapBtns) do Tw(b,{BackgroundColor3=D.CardHover}); local s=b:FindFirstChildOfClass("UIStroke"); if s then s.Color=D.Border; s.Transparency=0.4 end end
            Tw(cb,{BackgroundColor3=D.RowSelect}); Stroke(cb,D.Accent,1.5,0)
            H.UI.Lbl.WorldStatus.Text=string.format("⚙ %s [%s] → %s",S.SelWorld or "?",S.SelMode,capCid); H.UI.Lbl.WorldStatus.TextColor3=D.Cyan
        end)
        H.UI.Fr.ChapBtns[i]=cb
    end
    if H.UI.Fr.ChapBtns[1] then Tw(H.UI.Fr.ChapBtns[1],{BackgroundColor3=D.RowSelect}); Stroke(H.UI.Fr.ChapBtns[1],D.Accent,1.5,0) end
end
SecLbl(wCard,"WELTEN"); H.UI.Fr.WorldBtns=Instance.new("Frame",wCard)
H.UI.Fr.WorldBtns.Size=UDim2.new(1,0,0,0); H.UI.Fr.WorldBtns.AutomaticSize=Enum.AutomaticSize.Y
H.UI.Fr.WorldBtns.BackgroundTransparency=1; VList(H.UI.Fr.WorldBtns,4)
local function CreateWorldBtn(wid)
    local wb=Instance.new("TextButton",H.UI.Fr.WorldBtns)
    wb.Size=UDim2.new(1,0,0,30); wb.BackgroundColor3=D.CardHover; wb.Text="🌍  "..wid
    wb.TextColor3=D.TextHi; wb.TextSize=11; wb.Font=Enum.Font.GothamSemibold
    wb.AutoButtonColor=false; wb.BorderSizePixel=0; Corner(wb,7); Stroke(wb,D.Border,1,0.4)
    wb.MouseEnter:Connect(function() if S.SelWorld~=wid then Tw(wb,{BackgroundColor3=D.CardHover}) end end)
    wb.MouseLeave:Connect(function() if S.SelWorld~=wid then Tw(wb,{BackgroundColor3=D.CardHover}) end end)
    wb.MouseButton1Click:Connect(function()
        S.SelWorld=wid
        for _,b in pairs(H.UI.Fr.WorldBtns:GetChildren()) do
            if b:IsA("TextButton") then Tw(b,{BackgroundColor3=D.CardHover}); local s=b:FindFirstChildOfClass("UIStroke"); if s then s.Color=D.Border; s.Transparency=0.4 end end
        end
        Tw(wb,{BackgroundColor3=D.RowSelect}); Stroke(wb,D.Accent,1.5,0)
        H.UI.Lbl.WorldStatus.Text="🌍 "..wid.." ["..S.SelMode.."] → Kapitel wählen"; H.UI.Lbl.WorldStatus.TextColor3=D.Yellow
        local wd=S.WorldData[wid] or {}; local cl=(S.SelMode=="Story" or S.SelMode=="Calamity") and wd.story or wd.ranger; RebuildChapBtns(cl or {})
    end)
end
RebuildWorldList=function()
    for _,v in pairs(H.UI.Fr.WorldBtns:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end
    for _,v in pairs(H.UI.Fr.ChapRow:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end
    H.UI.Fr.ChapBtns={}; S.SelWorld=nil; S.SelChap=nil
    if S.SelMode=="Calamity" then
        local cd=S.WorldData["Calamity"]
        if cd and #cd.story>0 then S.SelWorld="Calamity"; RebuildChapBtns(cd.story); H.UI.Lbl.WorldStatus.Text="⚡ Calamity → Kapitel wählen"; H.UI.Lbl.WorldStatus.TextColor3=D.Orange
        else H.UI.Lbl.WorldStatus.Text="⏳ Calamity lädt..."; H.UI.Lbl.WorldStatus.TextColor3=D.Yellow end; return
    end
    if S.SelMode=="Raid" then
        H.UI.Lbl.WorldStatus.Text="⚔ Raid Farm → Kapitel wählen"; H.UI.Lbl.WorldStatus.TextColor3=D.Purple
        -- Raid nutzt Fallback-Kapitel; autofarm.lua befüllt ggf. WorldData["Raid"]
        local rd=S.WorldData["Raid"]
        if rd and (#rd.story>0 or #rd.ranger>0) then
            S.SelWorld="Raid"; RebuildChapBtns(rd.story and #rd.story>0 and rd.story or rd.ranger)
        else H.UI.Lbl.WorldStatus.Text="⏳ Raid-Daten laden..."; H.UI.Lbl.WorldStatus.TextColor3=D.Yellow end; return
    end
    local avail={}
    for _,wid in ipairs(S.WorldIds) do
        if wid:lower():find("calamity") then continue end
        if wid:lower():find("raid") then continue end
        local wd=S.WorldData[wid] or {}; local list=(S.SelMode=="Story") and wd.story or wd.ranger
        if list and #list>0 then table.insert(avail,wid) end
    end
    if #avail==0 then H.UI.Lbl.WorldStatus.Text="⏳ Welten laden..."; H.UI.Lbl.WorldStatus.TextColor3=D.Yellow; return end
    for _,wid in ipairs(avail) do CreateWorldBtn(wid) end
    H.UI.Lbl.WorldStatus.Text="✅ "..#avail.." Welten verfügbar"; H.UI.Lbl.WorldStatus.TextColor3=D.Green
end
for _,def in ipairs(MODI) do
    local mb=Instance.new("TextButton",modeRow)
    mb.Size=UDim2.new(0.24,0,0,26); mb.BackgroundColor3=D.CardHover; mb.Text=def.label
    mb.TextColor3=def.color; mb.TextSize=10; mb.Font=Enum.Font.GothamBold
    mb.AutoButtonColor=false; mb.BorderSizePixel=0; Corner(mb,7); Stroke(mb,D.Border,1,0.5)
    local capId=def.id
    mb.MouseButton1Click:Connect(function()
        S.SelMode=capId; HighlightMode(capId)
        H.UI.Fr.DiffCard.Visible=(capId=="Story" or capId=="Raid")
        RebuildWorldList()
    end)
    H.UI.Btn.ModeBtns[def.id]=mb
end
HighlightMode("Story")
H.UI.Btn.CreateStart=NeonBtn(wCard,"🚀  Create & Start Room",D.Green,36)
H.UI.Btn.CreateStart.MouseButton1Click:Connect(function()
    if not S.SelChap then H.UI.Lbl.WorldStatus.Text="⚠ Welt & Kapitel wählen!"; H.UI.Lbl.WorldStatus.TextColor3=D.Red; return end
    H.UI.Lbl.WorldStatus.Text="⚙ Erstelle: "..S.SelChap; H.UI.Lbl.WorldStatus.TextColor3=D.Yellow; H.UI.Btn.CreateStart.Text="⏳ Gestartet..."
    FireCreateAndStart(S.SelWorld or "Unknown",S.SelMode,S.SelChap)
    task.delay(2.5,function() pcall(function() H.UI.Btn.CreateStart.Text="🚀  Create & Start Room"; H.UI.Lbl.WorldStatus.Text="✅ "..S.SelChap; H.UI.Lbl.WorldStatus.TextColor3=D.Green end) end)
end)
NeonBtn(wCard,"🔄  Welten neu scannen",D.CyanDim,26).MouseButton1Click:Connect(function()
    H.UI.Lbl.WorldStatus.Text="⏳ Scanne..."; H.UI.Lbl.WorldStatus.TextColor3=D.Yellow; S.ChapFolderRef=nil
    pcall(function() if isfile and isfile(WORLD_CACHE_FILE) then delfile(WORLD_CACHE_FILE) end end)
    task.spawn(function()
        local f=GetChapterFolder()
        if f then ScanChapterFolder(f); pcall(function() H.UI.Lbl.ScanStatus.Text="✅ "..#S.WorldIds.." Welten"; H.UI.Lbl.ScanStatus.TextColor3=D.Green end)
        else ApplyFallback() end
        pcall(RebuildWorldList)
    end)
end)

-- Modul-Status + DB-Confirm nebeneinander
local dbStatusRow=Instance.new("Frame",GamePage); dbStatusRow.Size=UDim2.new(1,0,0,34); dbStatusRow.BackgroundTransparency=1; HList(dbStatusRow,6)
local modulStatusCard=Instance.new("Frame",dbStatusRow); modulStatusCard.Size=UDim2.new(0.5,-3,1,0); modulStatusCard.BackgroundColor3=D.Card; modulStatusCard.BackgroundTransparency=D.GlassPane; modulStatusCard.BorderSizePixel=0; Corner(modulStatusCard,8); Stroke(modulStatusCard,D.Border,1,D.GlassStroke); Pad(modulStatusCard,4,8,4,8)
H.UI.Lbl.ModulStatus=Instance.new("TextLabel",modulStatusCard)
H.UI.Lbl.ModulStatus.Size=UDim2.new(1,0,1,0); H.UI.Lbl.ModulStatus.BackgroundTransparency=1
H.UI.Lbl.ModulStatus.Text="🔴  Autofarm-Modul nicht geladen"; H.UI.Lbl.ModulStatus.TextColor3=D.Red
H.UI.Lbl.ModulStatus.TextSize=10; H.UI.Lbl.ModulStatus.Font=Enum.Font.GothamBold; H.UI.Lbl.ModulStatus.TextXAlignment=Enum.TextXAlignment.Left

-- Database confirmation removed - status now shown in header
pcall(function()
        if H.UI.Lbl.ModulStatus then
            H.UI.Lbl.ModulStatus.Text = "🟢  Autofarm-Modul aktiv [DB: OK]"
            H.UI.Lbl.ModulStatus.TextColor3 = D.GreenBright
        end
    end)

H.UI.Fr.AutofarmInjection=Instance.new("Frame",GamePage)
H.UI.Fr.AutofarmInjection.Name="AutofarmInjection"; H.UI.Fr.AutofarmInjection.Size=UDim2.new(1,0,0,0)
H.UI.Fr.AutofarmInjection.AutomaticSize=Enum.AutomaticSize.Y; H.UI.Fr.AutofarmInjection.BackgroundTransparency=1; H.UI.Fr.AutofarmInjection.BorderSizePixel=0
_G.HazeShared.Container=H.UI.Fr.AutofarmInjection

end) -- end pcall Game Tab

-- ╔══════════════════════════════════════════════════════════╗
--  MISC TAB
-- ╚══════════════════════════════════════════════════════════╝
pcall(function()
MkLbl(MiscPage,"🔧  Misc",14,D.Cyan,true)

-- Auto-Retry (hierher verschoben aus Game Tab)
local arCard=Card(MiscPage); Pad(arCard,10,12,10,12); VList(arCard,8); SecLbl(arCard,"AUTO-RETRY")
local arRow=Instance.new("Frame",arCard); arRow.Size=UDim2.new(1,0,0,32); arRow.BackgroundTransparency=1; HList(arRow,10)
H.UI.Lbl.ARStatus=Instance.new("TextLabel",arRow)
H.UI.Lbl.ARStatus.Size=UDim2.new(0.55,0,1,0); H.UI.Lbl.ARStatus.BackgroundTransparency=1
H.UI.Lbl.ARStatus.Text="Auto Retry: AUS"; H.UI.Lbl.ARStatus.TextColor3=D.TextMid
H.UI.Lbl.ARStatus.TextSize=12; H.UI.Lbl.ARStatus.Font=Enum.Font.GothamBold
H.UI.Lbl.ARStatus.TextXAlignment=Enum.TextXAlignment.Left
H.UI.Btn.ARToggle=Instance.new("TextButton",arRow)
H.UI.Btn.ARToggle.Size=UDim2.new(0.42,0,0,30); H.UI.Btn.ARToggle.BackgroundColor3=D.CardHover; H.UI.Btn.ARToggle.BackgroundTransparency=D.GlassPane
H.UI.Btn.ARToggle.Text="⬜ AUS"; H.UI.Btn.ARToggle.TextColor3=D.TextLow
H.UI.Btn.ARToggle.TextSize=12; H.UI.Btn.ARToggle.Font=Enum.Font.GothamBold
H.UI.Btn.ARToggle.AutoButtonColor=false; H.UI.Btn.ARToggle.BorderSizePixel=0
Corner(H.UI.Btn.ARToggle,8); Stroke(H.UI.Btn.ARToggle,D.TextLow,1,0.4)
local function UpdateAutoRetryUI()
    if H.Config.AutoRetry then
        H.UI.Btn.ARToggle.Text="✅ AN"; H.UI.Btn.ARToggle.TextColor3=D.Green
        H.UI.Lbl.ARStatus.Text="Auto Retry: AN"; H.UI.Lbl.ARStatus.TextColor3=D.Green
        Stroke(H.UI.Btn.ARToggle,D.Green,1.5,0); Tw(H.UI.Btn.ARToggle,{BackgroundColor3=D.GreenDark,BackgroundTransparency=0.12})
    else
        H.UI.Btn.ARToggle.Text="⬜ AUS"; H.UI.Btn.ARToggle.TextColor3=D.TextLow
        H.UI.Lbl.ARStatus.Text="Auto Retry: AUS"; H.UI.Lbl.ARStatus.TextColor3=D.TextMid
        Stroke(H.UI.Btn.ARToggle,D.TextLow,1,0.4); Tw(H.UI.Btn.ARToggle,{BackgroundColor3=D.CardHover,BackgroundTransparency=D.GlassPane})
    end
end
H.UI.Btn.ARToggle.MouseButton1Click:Connect(function() H.Config.AutoRetry=not H.Config.AutoRetry; SaveConfig(); UpdateAutoRetryUI() end)
_G._UpdateAutoRetryUI=UpdateAutoRetryUI
_G.HazeHubFunctions.UpdateAutoRetryUI=UpdateAutoRetryUI

-- Raid-Funktionen sind bereits global definiert - hier nur UI-Implementierung

-- Anti-AFK Toggle Funktion (UI-Implementierung)
local function ToggleAntiAFKUI()
    AntiAFKEnabled = not AntiAFKEnabled
    if afkDot and afkTxt then
        if AntiAFKEnabled then
            afkDot.BackgroundColor3 = D.Green
            afkTxt.Text = "Anti-AFK  —  Aktiv"
            afkTxt.TextColor3 = D.Green
        else
            afkDot.BackgroundColor3 = D.Red
            afkTxt.Text = "Anti-AFK  —  Inaktiv"
            afkTxt.TextColor3 = D.Red
        end
    end
end
_G.HazeHubFunctions.ToggleAntiAFK = ToggleAntiAFKUI

-- Anti-AFK (neu implementiert: Mouse-Simulation + VirtualUser Kombination)
local afkCard=Card(MiscPage); Pad(afkCard,10,12,10,12); VList(afkCard,8); SecLbl(afkCard,"ANTI-AFK")
local afkTopRow=Instance.new("Frame",afkCard); afkTopRow.Size=UDim2.new(1,0,0,28); afkTopRow.BackgroundTransparency=1; HList(afkTopRow,10)
local afkDot=Instance.new("Frame",afkTopRow); afkDot.Size=UDim2.new(0,10,0,10); afkDot.AnchorPoint=Vector2.new(0,0.5); afkDot.BackgroundColor3=D.Green; afkDot.BorderSizePixel=0; Corner(afkDot,99)
local afkTxt=Instance.new("TextLabel",afkTopRow); afkTxt.Size=UDim2.new(1,-20,1,0); afkTxt.BackgroundTransparency=1
afkTxt.Text="Anti-AFK  —  Aktiv"; afkTxt.TextColor3=D.Green; afkTxt.TextSize=13; afkTxt.Font=Enum.Font.GothamBold; afkTxt.TextXAlignment=Enum.TextXAlignment.Left
local afkInfoLbl=MkLbl(afkCard,"Verhindert AFK-Kicks durch zyklische Eingaben (Kamera-Ping alle 55s).",10,D.TextLow)
afkInfoLbl.Size=UDim2.new(1,0,0,28); afkInfoLbl.TextWrapped=true

-- Anti-AFK Toggle Button
local afkToggleBtn=Instance.new("TextButton",afkCard); afkToggleBtn.Size=UDim2.new(1,0,0,32); afkToggleBtn.BackgroundColor3=D.Green; afkToggleBtn.Text="🔄 Anti-AFK Umschalten"; afkToggleBtn.TextColor3=Color3.new(1,1,1); afkToggleBtn.TextSize=12; afkToggleBtn.Font=Enum.Font.GothamBold; afkToggleBtn.AutoButtonColor=false; afkToggleBtn.BorderSizePixel=0; Corner(afkToggleBtn,8); Stroke(afkToggleBtn,D.Green,1,0.2)
afkToggleBtn.MouseButton1Click:Connect(function()
    if _G.HazeHubFunctions.ToggleAntiAFK and type(_G.HazeHubFunctions.ToggleAntiAFK) == "function" then
        _G.HazeHubFunctions.ToggleAntiAFK()
    else
        warn("[HazeHUB] ToggleAntiAFK Funktion nicht gefunden!")
    end
end)
afkToggleBtn.MouseEnter:Connect(function() Tw(afkToggleBtn,{BackgroundColor3=Color3.fromRGB(0,160,80)}) end)
afkToggleBtn.MouseLeave:Connect(function() Tw(afkToggleBtn,{BackgroundColor3=AntiAFKEnabled and D.Green or D.Red}) end)

-- Puls-Animation für den grünen Dot
task.spawn(function()
    while S.Running and ScreenGui.Parent do
        Tw(afkDot,{BackgroundTransparency=0.65},TM); task.wait(1.1)
        Tw(afkDot,{BackgroundTransparency=0},TM); task.wait(1.1)
    end
end)

-- Neuer Anti-AFK: Simuliert Mausbewegung + CameraHeartbeat (kein VirtualUser Spacebar-Spam)
local _afkLastPing = 0
task.spawn(function()
    while S.Running and ScreenGui.Parent do
        if AntiAFKEnabled then
            local now = tick()
            if now - _afkLastPing >= 55 then
                _afkLastPing = now
                pcall(function()
                    -- Kamera-Ping (minimal, aber effektiv)
                    local cam = workspace.CurrentCamera
                    if cam and cam.CFrame then
                        local cf = cam.CFrame
                        local newPos = cf.Position + Vector3.new(0, 0.1, 0)
                        cam.CFrame = CFrame.new(newPos, cf.LookVector)
                        task.wait(0.05)
                        cam.CFrame = cf
                    end
                end)
                pcall(function()
                    -- Fallback: VirtualUser Ping ohne Spacebar
                    Svc.Vuser:CaptureController()
                    Svc.Vuser:ClickButton2(Vector2.new(0,0))
                end)
            end
        end
        task.wait(2)
    end
end)

end) -- end pcall Misc Tab

-- ╔══════════════════════════════════════════════════════════╗
--  SESSION TAB
-- ╚══════════════════════════════════════════════════════════╝
pcall(function()
MkLbl(SessPage,"📊  Session",14,D.Accent,false)
local sHCard=Card(SessPage); Pad(sHCard,8,12,8,12); VList(sHCard,6)
local sHRow1=Instance.new("Frame",sHCard); sHRow1.Size=UDim2.new(1,0,0,22); sHRow1.BackgroundTransparency=1
H.UI.Lbl.Rounds=Instance.new("TextLabel",sHRow1); H.UI.Lbl.Rounds.Size=UDim2.new(1,0,1,0); H.UI.Lbl.Rounds.BackgroundTransparency=1; H.UI.Lbl.Rounds.Text="Abgeschlossene Runden: 0"; H.UI.Lbl.Rounds.TextColor3=D.TextHi; H.UI.Lbl.Rounds.TextSize=14; H.UI.Lbl.Rounds.Font=Enum.Font.GothamMedium; H.UI.Lbl.Rounds.RichText=true; H.UI.Lbl.Rounds.TextStrokeTransparency=1; H.UI.Lbl.Rounds.TextXAlignment=Enum.TextXAlignment.Left; H.UI.Lbl.Rounds.TextScaled=false; H.UI.Lbl.Rounds.TextWrapped=true
local sHRow2=Instance.new("Frame",sHCard); sHRow2.Size=UDim2.new(1,0,0,20); sHRow2.BackgroundTransparency=1; HList(sHRow2,10)
H.UI.Lbl.SessRoundTime=Instance.new("TextLabel",sHRow2); H.UI.Lbl.SessRoundTime.Size=UDim2.new(0.5,-5,1,0); H.UI.Lbl.SessRoundTime.BackgroundTransparency=1; H.UI.Lbl.SessRoundTime.Text="Rundenzeit: –"; H.UI.Lbl.SessRoundTime.TextColor3=D.TextMid; H.UI.Lbl.SessRoundTime.TextSize=12; H.UI.Lbl.SessRoundTime.Font=Enum.Font.GothamMedium; H.UI.Lbl.SessRoundTime.RichText=true; H.UI.Lbl.SessRoundTime.TextStrokeTransparency=1; H.UI.Lbl.SessRoundTime.TextXAlignment=Enum.TextXAlignment.Left; H.UI.Lbl.SessRoundTime.TextScaled=false; H.UI.Lbl.SessRoundTime.TextWrapped=true
H.UI.Lbl.ItemCount=Instance.new("TextLabel",sHRow2); H.UI.Lbl.ItemCount.Size=UDim2.new(0.5,-5,1,0); H.UI.Lbl.ItemCount.BackgroundTransparency=1; H.UI.Lbl.ItemCount.Text="Ø Zeit: –"; H.UI.Lbl.ItemCount.TextColor3=D.TextMid; H.UI.Lbl.ItemCount.TextSize=12; H.UI.Lbl.ItemCount.Font=Enum.Font.GothamMedium; H.UI.Lbl.ItemCount.RichText=true; H.UI.Lbl.ItemCount.TextStrokeTransparency=1; H.UI.Lbl.ItemCount.TextXAlignment=Enum.TextXAlignment.Right; H.UI.Lbl.ItemCount.TextScaled=false; H.UI.Lbl.ItemCount.TextWrapped=true
local infoCard=Card(SessPage); Pad(infoCard,8,10,8,10); VList(infoCard,5); SecLbl(infoCard,"ℹ  WÄHRUNG / XP (Session)")
local infoRow=Instance.new("Frame",infoCard); infoRow.Size=UDim2.new(1,0,0,0); infoRow.AutomaticSize=Enum.AutomaticSize.Y; infoRow.BackgroundTransparency=1; HList(infoRow,8)
H.UI.Lbl.InfoVals={}
for _,iname in ipairs({"Exp","Gems","Gold"}) do
    local iF=Instance.new("Frame",infoRow); iF.Size=UDim2.new(0.31,0,0,44); iF.BackgroundColor3=Color3.fromRGB(20,20,22); iF.BorderSizePixel=0; Corner(iF,8); Stroke(iF,D.Border,1,0.55)
    local iN=Instance.new("TextLabel",iF); iN.Size=UDim2.new(1,0,0.45,0); iN.BackgroundTransparency=1; iN.Text=iname; iN.TextColor3=D.TextMid; iN.TextSize=10; iN.Font=Enum.Font.GothamMedium; iN.RichText=true; iN.TextStrokeTransparency=1; iN.TextXAlignment=Enum.TextXAlignment.Center
    local iV=Instance.new("TextLabel",iF); iV.Size=UDim2.new(1,0,0.55,0); iV.Position=UDim2.new(0,0,0.45,0); iV.BackgroundTransparency=1; iV.Text="0"; iV.TextColor3=D.TextHi; iV.TextSize=14; iV.Font=Enum.Font.GothamMedium; iV.RichText=true; iV.TextStrokeTransparency=1; iV.TextXAlignment=Enum.TextXAlignment.Center
    H.UI.Lbl.InfoVals[iname]=iV
end
local goalsCard=Card(SessPage); Pad(goalsCard,10,10,10,10); VList(goalsCard,8); SecLbl(goalsCard,"🎯  ZIELE  (AutoSave)")
local gInputRow=Instance.new("Frame",goalsCard); gInputRow.Size=UDim2.new(1,0,0,30); gInputRow.BackgroundTransparency=1; HList(gInputRow,5)
local gItemOuter,gItemBox=MkInput(gInputRow,"Item-Name..."); gItemOuter.Size=UDim2.new(0.50,0,0,30); H.UI.Inp.GoalItem=gItemBox
local gAmtOuter,gAmtBox=MkInput(gInputRow,"Anzahl"); gAmtOuter.Size=UDim2.new(0.28,0,0,30); H.UI.Inp.GoalAmt=gAmtBox
local gAddBtn=Instance.new("TextButton",gInputRow); gAddBtn.Size=UDim2.new(0.19,0,0,30); gAddBtn.BackgroundColor3=D.Purple; gAddBtn.Text="+ Ziel"; gAddBtn.TextColor3=Color3.new(1,1,1); gAddBtn.TextSize=11; gAddBtn.Font=Enum.Font.GothamBold; gAddBtn.AutoButtonColor=false; gAddBtn.BorderSizePixel=0; Corner(gAddBtn,7); Stroke(gAddBtn,D.Purple,1,0.2)
gAddBtn.MouseEnter:Connect(function() Tw(gAddBtn,{BackgroundColor3=Color3.fromRGB(150,60,220)}) end); gAddBtn.MouseLeave:Connect(function() Tw(gAddBtn,{BackgroundColor3=D.Purple}) end)
H.UI.Fr.GoalsList=Instance.new("Frame",goalsCard); H.UI.Fr.GoalsList.Size=UDim2.new(1,0,0,0); H.UI.Fr.GoalsList.AutomaticSize=Enum.AutomaticSize.Y; H.UI.Fr.GoalsList.BackgroundTransparency=1; VList(H.UI.Fr.GoalsList,4)
H.UI.Lbl.GoalsEmpty=MkLbl(H.UI.Fr.GoalsList,"Keine Ziele.",11,D.TextLow); H.UI.Lbl.GoalsEmpty.Size=UDim2.new(1,0,0,28)
UpdateGoalsUI=function()
    for _,v in pairs(H.UI.Fr.GoalsList:GetChildren()) do if v:IsA("Frame") then v:Destroy() end end
    H.UI.Lbl.GoalsEmpty.Visible=(#S.Goals==0)
    for _,goal in ipairs(S.Goals) do
        local cur=math.max(GlobalSession.AllRewards[goal.item] or 0,GetInvAmt(goal.item)); local reached=cur>=goal.amount; goal.reached=reached; local pct=math.min(1,cur/math.max(1,goal.amount))
        local row=Instance.new("Frame",H.UI.Fr.GoalsList); row.Size=UDim2.new(1,0,0,44); row.BorderSizePixel=0; Corner(row,8)
        if reached then row.BackgroundColor3=D.GreenDark; Stroke(row,D.GreenBright,1.5,0) else row.BackgroundColor3=D.Card; Stroke(row,D.Border,1,0.4) end
        local bar=Instance.new("Frame",row); bar.Size=UDim2.new(0,3,0.65,0); bar.Position=UDim2.new(0,0,0.175,0); bar.BackgroundColor3=reached and D.GreenBright or D.Purple; bar.BorderSizePixel=0; Corner(bar,2)
        local pgBg=Instance.new("Frame",row); pgBg.Size=UDim2.new(1,-52,0,3); pgBg.Position=UDim2.new(0,8,1,-6); pgBg.BackgroundColor3=Color3.fromRGB(28,38,62); pgBg.BorderSizePixel=0; Corner(pgBg,2)
        local pgF=Instance.new("Frame",pgBg); pgF.Size=UDim2.new(pct,0,1,0); pgF.BackgroundColor3=reached and D.GreenBright or D.Purple; pgF.BorderSizePixel=0; Corner(pgF,2)
        local nL=Instance.new("TextLabel",row); nL.Position=UDim2.new(0,12,0,5); nL.Size=UDim2.new(1,-52,0.5,-3); nL.BackgroundTransparency=1; nL.Text=goal.item; nL.TextColor3=reached and D.GreenBright or D.TextHi; nL.TextSize=11; nL.Font=Enum.Font.GothamMedium; nL.RichText=true; nL.TextStrokeTransparency=1; nL.TextXAlignment=Enum.TextXAlignment.Left; nL.TextTruncate=Enum.TextTruncate.AtEnd
        local pL=Instance.new("TextLabel",row); pL.Position=UDim2.new(0,12,0.5,1); pL.Size=UDim2.new(1,-52,0.5,-5); pL.BackgroundTransparency=1
        if reached then pL.Text="✅ "..cur.." / "..goal.amount.."  ERREICHT!"; pL.TextColor3=D.GreenBright else pL.Text=cur.." / "..goal.amount.."  ("..math.floor(pct*100).."%)"; pL.TextColor3=D.TextMid end
        pL.TextSize=10; pL.Font=Enum.Font.GothamMedium; pL.RichText=true; pL.TextStrokeTransparency=1; pL.TextXAlignment=Enum.TextXAlignment.Left
        local capItem=goal.item; local xBtn=Instance.new("TextButton",row); xBtn.Size=UDim2.new(0,34,0,34); xBtn.Position=UDim2.new(1,-38,0.5,-17); xBtn.BackgroundColor3=Color3.fromRGB(50,12,12); xBtn.Text="✕"; xBtn.TextColor3=D.Red; xBtn.TextSize=13; xBtn.Font=Enum.Font.GothamBold; xBtn.AutoButtonColor=false; xBtn.BorderSizePixel=0; Corner(xBtn,7); Stroke(xBtn,D.Red,1,0.4)
        xBtn.MouseEnter:Connect(function() Tw(xBtn,{BackgroundColor3=D.RedDark}) end); xBtn.MouseLeave:Connect(function() Tw(xBtn,{BackgroundColor3=Color3.fromRGB(50,12,12)}) end)
        xBtn.MouseButton1Click:Connect(function() for i,g in ipairs(S.Goals) do if g.item==capItem then table.remove(S.Goals,i); break end end; S.GoalsNotified[capItem]=nil; SaveConfig(); UpdateGoalsUI() end)
        if reached then task.spawn(function() while row.Parent do Tw(row,{BackgroundColor3=Color3.fromRGB(0,75,38)},TM); task.wait(0.65); if not row.Parent then break end; Tw(row,{BackgroundColor3=D.GreenDark},TM); task.wait(0.65) end end) end
    end
end
gAddBtn.MouseButton1Click:Connect(function()
    local iname=(H.UI.Inp.GoalItem.Text or ""):match("^%s*(.-)%s*$"); local iamt=tonumber(H.UI.Inp.GoalAmt.Text)
    if iname=="" or not iamt or iamt<=0 then return end
    local found=false; for _,g in ipairs(S.Goals) do if g.item==iname then found=true; break end end
    if not found then table.insert(S.Goals,{item=iname,amount=iamt,reached=false}) end
    S.GoalsNotified[iname]=nil; SaveConfig(); UpdateGoalsUI(); H.UI.Inp.GoalItem.Text=""; H.UI.Inp.GoalAmt.Text=""
end)
local function SetGoalFromInventory(itemName)
    SelectTab("Session"); H.UI.Inp.GoalItem.Text=itemName; H.UI.Inp.GoalAmt.Text=""
    task.defer(function() pcall(function() H.UI.Inp.GoalAmt:CaptureFocus() end) end)
    Stroke(gItemOuter,D.Purple,1.5,0); Stroke(gAmtOuter,D.Purple,1.5,0)
    task.delay(2.5,function() Stroke(gItemOuter,D.Border,1,0.2); Stroke(gAmtOuter,D.Border,1,0.2) end)
end
_G._SetGoalFromInventory=SetGoalFromInventory
_G.HazeHubFunctions.SetGoalFromInventory=SetGoalFromInventory
SecLbl(SessPage,"📦  GEGENSTÄNDE ERHALTEN (diese Session)")
H.UI.Fr.SessList=Card(SessPage); Pad(H.UI.Fr.SessList,6,8,6,8); VList(H.UI.Fr.SessList,4)
H.UI.Lbl.SessEmpty=MkLbl(H.UI.Fr.SessList,"Noch keine Belohnungen – warte auf „Rewards - Items“ vom Server.",12,D.TextLow); H.UI.Lbl.SessEmpty.Size=UDim2.new(1,0,0,30); H.UI.Lbl.SessEmpty.TextXAlignment=Enum.TextXAlignment.Center; H.UI.Lbl.SessEmpty.Font=Enum.Font.GothamMedium; H.UI.Lbl.SessEmpty.RichText=true; H.UI.Lbl.SessEmpty.TextStrokeTransparency=1
local sTotCard=Card(SessPage,34); Pad(sTotCard,0,12,0,12); local sTotRow=Instance.new("Frame",sTotCard); sTotRow.Size=UDim2.new(1,0,1,0); sTotRow.BackgroundTransparency=1
H.UI.Lbl.SessTotal=MkLbl(sTotRow,"Gesamt: 0 Items",12,D.TextMid); H.UI.Lbl.SessTotal.Size=UDim2.new(1,0,1,0); H.UI.Lbl.SessTotal.TextXAlignment=Enum.TextXAlignment.Right; H.UI.Lbl.SessTotal.Font=Enum.Font.GothamMedium; H.UI.Lbl.SessTotal.RichText=true; H.UI.Lbl.SessTotal.TextStrokeTransparency=1
UpdateSessionUI=function()
    local gs = GlobalSession
    local cr = math.floor(tonumber(gs.CurrentRound) or 0)
    local totalT = math.floor(tonumber(gs.TotalTime) or 0)
    H.UI.Lbl.Rounds.Text = "Abgeschlossene Runden: " .. tostring(cr)
    if cr > 0 then
        local avgSec = math.floor(totalT / cr + 0.5)
        H.UI.Lbl.SessRoundTime.Text = "Rundenzeit: " .. formatTime(totalT)
        H.UI.Lbl.ItemCount.Text = "Ø Zeit: " .. formatTime(avgSec)
    else
        H.UI.Lbl.SessRoundTime.Text = "Rundenzeit: –"
        H.UI.Lbl.ItemCount.Text = "Ø Zeit: –"
    end
    for k, v in pairs(H.UI.Lbl.InfoVals) do v.Text = tostring(gs.AllRewards[k] or 0) end
    for _, v in pairs(H.UI.Fr.SessList:GetChildren()) do if v:IsA("Frame") then v:Destroy() end end
    local total, count = 0, 0
    for name, amt in pairs(gs.AllRewards) do
        if IsSessionCurrencyKey(name) then continue end
        total = total + amt
        count = count + 1
        local isRare = K.RARE[name] == true
        local row = Instance.new("Frame", H.UI.Fr.SessList)
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BorderSizePixel = 0
        Corner(row, 7)
        if isRare then row.BackgroundColor3 = D.RedDark; Stroke(row, D.Red, 1.5, 0) else row.BackgroundColor3 = D.CardHover; Stroke(row, D.Border, 1, 0.5) end
        local bar = Instance.new("Frame", row)
        bar.Size = UDim2.new(0, 3, 0.55, 0)
        bar.Position = UDim2.new(0, 0, 0.225, 0)
        bar.BackgroundColor3 = isRare and D.Red or D.AccentDim
        bar.BorderSizePixel = 0
        Corner(bar, 2)
        local nL = Instance.new("TextLabel", row)
        nL.Position = UDim2.new(0, 12, 0, 0)
        nL.Size = UDim2.new(1, -70, 1, 0)
        nL.BackgroundTransparency = 1
        nL.Text = name
        nL.TextColor3 = isRare and D.Red or D.TextHi
        nL.TextSize = 12
        nL.Font = Enum.Font.GothamMedium
        nL.RichText = true
        nL.TextStrokeTransparency = 1
        nL.TextXAlignment = Enum.TextXAlignment.Left
        nL.TextTruncate = Enum.TextTruncate.AtEnd
        local aL = Instance.new("TextLabel", row)
        aL.Position = UDim2.new(1, -62, 0, 0)
        aL.Size = UDim2.new(0, 56, 1, 0)
        aL.BackgroundTransparency = 1
        aL.Text = "×" .. tostring(amt)
        aL.TextColor3 = isRare and D.Red or D.Accent
        aL.TextSize = 13
        aL.Font = Enum.Font.GothamMedium
        aL.RichText = true
        aL.TextStrokeTransparency = 1
        aL.TextXAlignment = Enum.TextXAlignment.Right
    end
    H.UI.Lbl.SessEmpty.Visible = (count == 0)
    H.UI.Lbl.SessTotal.Text = "Gesamt (Stück): " .. tostring(total)
    if UpdateGoalsUI then pcall(UpdateGoalsUI) end
end
NeonBtn(SessPage,"🗑  Session zurücksetzen",D.Red,34).MouseButton1Click:Connect(function()
    GlobalSession.CurrentRound = 0
    GlobalSession.TotalTime = 0
    if table.clear then table.clear(GlobalSession.AllRewards) else for k in pairs(GlobalSession.AllRewards) do GlobalSession.AllRewards[k] = nil end end
    S.SessStart = os.time()
    S.RoundWallStart = not IsInLobby() and os.time() or nil
    for _, g in ipairs(S.Goals) do g.reached = false end
    S.GoalsNotified = {}
    UpdateSessionUI()
end)
end) -- end pcall Session Tab

-- ╔══════════════════════════════════════════════════════════╗
--  Belohnungen aus Remote „Rewards - Items“ → GlobalSession
-- ╚══════════════════════════════════════════════════════════╝
local function AccumulateRewards(data)
    if not data then return end
    for _, item in pairs(data) do
        if typeof(item) == "Instance" then
            local v = item:FindFirstChild("Amount") or item:FindFirstChild("Value")
            local amt = math.floor(tonumber(v and v.Value) or 1)
            local name = item.Name
            if name and name ~= "" then GlobalSession.AllRewards[name] = (GlobalSession.AllRewards[name] or 0) + amt end
        elseif type(item) == "table" then
            local n = item.item or item.Item or item.Name or item.name or item.ItemName
            local a = math.floor(tonumber(item.amount or item.Amount or item.count or item.Count or item.qty or 1) or 1)
            if type(n) == "string" and n ~= "" then GlobalSession.AllRewards[n] = (GlobalSession.AllRewards[n] or 0) + a end
        end
    end
    if UpdateSessionUI then pcall(UpdateSessionUI) end
    pcall(CheckAllGoals)
end

-- ╔══════════════════════════════════════════════════════════╗
--  INVENTORY TAB – ImageLabel (Texture) + ViewportFrame Fallback
-- ╚══════════════════════════════════════════════════════════╝
pcall(function()
MkLbl(InvPage,"🎒  Inventar",14,D.Cyan,true)

-- Spieler Stats + Shop Currency nebeneinander
local statsAndCurrencyRow=Instance.new("Frame",InvPage); statsAndCurrencyRow.Size=UDim2.new(1,0,0,0); statsAndCurrencyRow.AutomaticSize=Enum.AutomaticSize.Y; statsAndCurrencyRow.BackgroundTransparency=1; HList(statsAndCurrencyRow,6)

-- Player Stats (links)
local playerStatsCard=Instance.new("Frame",statsAndCurrencyRow); playerStatsCard.Size=UDim2.new(0.5,-3,0,0); playerStatsCard.AutomaticSize=Enum.AutomaticSize.Y; playerStatsCard.BackgroundColor3=D.Card; playerStatsCard.BackgroundTransparency=D.GlassPane; playerStatsCard.BorderSizePixel=0; Corner(playerStatsCard,8); Stroke(playerStatsCard,D.Border,1,D.GlassStroke); Pad(playerStatsCard,10,10,10,10); VList(playerStatsCard,8)
SecLbl(playerStatsCard,"👤 SPIELER STATS")
local xpTextLbl=MkLbl(playerStatsCard,"⏳ Lädt XP...",11,D.Yellow); xpTextLbl.Size=UDim2.new(1,0,0,18); H.UI.Lbl.XPText=xpTextLbl
local xpBarBg=Instance.new("Frame",playerStatsCard); xpBarBg.Size=UDim2.new(1,0,0,8); xpBarBg.BackgroundColor3=Color3.fromRGB(20,28,50); xpBarBg.BorderSizePixel=0; Corner(xpBarBg,4)
local xpBarFill=Instance.new("Frame",xpBarBg); xpBarFill.Size=UDim2.new(0,0,1,0); xpBarFill.BackgroundColor3=D.Cyan; xpBarFill.BorderSizePixel=0; Corner(xpBarFill,4); Instance.new("UIGradient",xpBarFill).Color=ColorSequence.new({ColorSequenceKeypoint.new(0,D.Cyan),ColorSequenceKeypoint.new(1,D.Purple)}); H.UI.Fr.XPBarFill=xpBarFill
local lvlRow=Instance.new("Frame",playerStatsCard); lvlRow.Size=UDim2.new(1,0,0,26); lvlRow.BackgroundTransparency=1; HList(lvlRow,8)
local lvlLF=MkLbl(lvlRow,"Level:",11,D.TextLow); lvlLF.Size=UDim2.new(0.4,0,1,0)
local lvlVal=MkLbl(lvlRow,"–",12,D.TextHi,true); lvlVal.Size=UDim2.new(0.6,0,1,0); H.UI.Lbl.PlayerLevel=lvlVal
SecLbl(playerStatsCard,"⚔ UPGRADE STATS")
local UPGRADE_STATS={
    {key="BaseHealth",  levelKey="BaseHealthLevel",  maxLvl=100,label="Tower Health",  icon="🏰",color=D.Red,   goldRate=200},
    {key="YenMax",      levelKey="YenMaxLevel",      maxLvl=100,label="Maximum Yen",   icon="💰",color=D.Gold,  goldRate=250},
    {key="YenGenarate", levelKey="YenGenarateLevel", maxLvl=50, label="Yen Generation",icon="⚡",color=D.Yellow,goldRate=500,flatCost=true},
}
H.UI.Lbl.UpgradeStats={}
for _,sd in ipairs(UPGRADE_STATS) do
    local sRow=Instance.new("Frame",playerStatsCard); sRow.Size=UDim2.new(1,0,0,52); sRow.BackgroundColor3=D.CardHover; sRow.BorderSizePixel=0; Corner(sRow,7); Stroke(sRow,sd.color,1,0.6)    local acBar=Instance.new("Frame",sRow); acBar.Size=UDim2.new(0,3,1,0); acBar.BackgroundColor3=sd.color; acBar.BorderSizePixel=0; Corner(acBar,2)
    local sNameLbl=Instance.new("TextLabel",sRow); sNameLbl.Position=UDim2.new(0,10,0,3); sNameLbl.Size=UDim2.new(0.55,-10,0,14); sNameLbl.BackgroundTransparency=1; sNameLbl.Text=sd.icon.." "..sd.label; sNameLbl.TextColor3=sd.color; sNameLbl.TextSize=11; sNameLbl.Font=Enum.Font.GothamBold; sNameLbl.TextXAlignment=Enum.TextXAlignment.Left
    local sLvlLbl=Instance.new("TextLabel",sRow); sLvlLbl.Position=UDim2.new(0,10,0,18); sLvlLbl.Size=UDim2.new(0.55,-10,0,13); sLvlLbl.BackgroundTransparency=1; sLvlLbl.Text="Lv. –"; sLvlLbl.TextColor3=D.TextMid; sLvlLbl.TextSize=10; sLvlLbl.Font=Enum.Font.GothamSemibold; sLvlLbl.TextXAlignment=Enum.TextXAlignment.Left
    local sGoldLbl=Instance.new("TextLabel",sRow); sGoldLbl.Position=UDim2.new(0,10,0,34); sGoldLbl.Size=UDim2.new(0.65,-10,0,13); sGoldLbl.BackgroundTransparency=1; sGoldLbl.Text="🪙 Gold bis Max: –"; sGoldLbl.TextColor3=D.TextLow; sGoldLbl.TextSize=9; sGoldLbl.Font=Enum.Font.Gotham; sGoldLbl.TextXAlignment=Enum.TextXAlignment.Left
    local sCostLbl=Instance.new("TextLabel",sRow); sCostLbl.Position=UDim2.new(0.55,0,0,3); sCostLbl.Size=UDim2.new(0.45,-6,0,28); sCostLbl.BackgroundTransparency=1; sCostLbl.Text="..."; sCostLbl.TextColor3=D.Gold; sCostLbl.TextSize=10; sCostLbl.Font=Enum.Font.GothamSemibold; sCostLbl.TextXAlignment=Enum.TextXAlignment.Right; sCostLbl.TextWrapped=true
    H.UI.Lbl.UpgradeStats[sd.key]={level=sLvlLbl,cost=sCostLbl,gold=sGoldLbl}
end
local function RefreshPlayerStats()
    pcall(function()
        local hudText=nil; pcall(function() hudText=Svc.Player.PlayerGui.HUD.ExpBar.Numbers.ContentText end)
        if hudText and hudText~="" then
            H.UI.Lbl.XPText.Text=hudText; H.UI.Lbl.XPText.TextColor3=D.Cyan
            local curXP,maxXP=hudText:match("(%d[%d,]+)/(%d[%d,]+)XP"); if not curXP then curXP,maxXP=hudText:match("(%d[%d,]+)/(%d[%d,]+)") end
            if curXP and maxXP then local c=tonumber(curXP:gsub(",","")) or 0; local m=tonumber(maxXP:gsub(",","")) or 1; Tw(H.UI.Fr.XPBarFill,{Size=UDim2.new(math.min(1,c/math.max(1,m)),0,1,0)},TM) end
        else H.UI.Lbl.XPText.Text="HUD XP nicht verfügbar"; H.UI.Lbl.XPText.TextColor3=D.TextLow end
    end)
    pcall(function()
        local df=Svc.RS:WaitForChild("Player_Data",3):WaitForChild(LP.Name,3):WaitForChild("Data",3)
        local lvl=df:FindFirstChild("Level"); local exp=df:FindFirstChild("Exp"); local maxExp=df:FindFirstChild("MaxExp")
        if lvl then
            local lvlTxt="Level "..tostring(lvl.Value)
            if exp and maxExp then lvlTxt=lvlTxt.."  ("..FmtNum(exp.Value).." / "..FmtNum(maxExp.Value).." XP)"; Tw(H.UI.Fr.XPBarFill,{Size=UDim2.new(math.min(1,(tonumber(exp.Value) or 0)/math.max(1,tonumber(maxExp.Value) or 1)),0,1,0)},TM) end
            H.UI.Lbl.PlayerLevel.Text=lvlTxt
        else H.UI.Lbl.PlayerLevel.Text="–" end
    end)
    for _,sd in ipairs(UPGRADE_STATS) do
        pcall(function()
            local lbls=H.UI.Lbl.UpgradeStats[sd.key]; if not lbls then return end
            local curLvl=nil; pcall(function() curLvl=tonumber(Svc.RS:WaitForChild("Player_Data",3):WaitForChild(LP.Name,3):WaitForChild("Stats",3):WaitForChild(sd.levelKey,3).Value) end)
            local statVal=nil; pcall(function() statVal=tonumber(Svc.RS:WaitForChild("Player_Data",3):WaitForChild(LP.Name,3):WaitForChild("Stats",3):WaitForChild(sd.key,3).Value) end)
            local isMax=curLvl~=nil and curLvl>=sd.maxLvl
            if isMax then lbls.level.Text="✅ LVL: MAX"; lbls.level.TextColor3=D.GreenBright
            elseif curLvl then lbls.level.Text=string.format("Lv. %d / %d%s",curLvl,sd.maxLvl,statVal~=nil and ("  ["..FmtNum(statVal).."]") or ""); lbls.level.TextColor3=D.TextMid
            else lbls.level.Text="Lv. –"; lbls.level.TextColor3=D.TextLow end
            if lbls.gold then
                if isMax then lbls.gold.Text="🪙 Gold bis Max: ✅ MAX"; lbls.gold.TextColor3=D.GreenBright
                elseif curLvl then
                    local gn=0; if sd.flatCost then gn=math.max(0,sd.maxLvl-curLvl)*sd.goldRate else local a=curLvl; local b=sd.maxLvl-1; if a<=b then gn=sd.goldRate*(a+b)*(b-a+1)/2 end end
                    gn=math.floor(gn); if gn==0 then lbls.gold.Text="🪙 Gold bis Max: ✅ Fertig"; lbls.gold.TextColor3=D.GreenBright else lbls.gold.Text="🪙 Gold bis Max: "..FmtNum(gn); lbls.gold.TextColor3=D.TextLow end
                else lbls.gold.Text="🪙 Gold bis Max: –"; lbls.gold.TextColor3=D.TextLow end
            end
        end)
    end
end
NeonBtn(playerStatsCard,"🔄 Stats aktualisieren",D.CyanDim,28).MouseButton1Click:Connect(function() task.spawn(function() pcall(RefreshPlayerStats) end) end)

-- Währungen (rechts neben Stats)
local currencyCard=Instance.new("Frame",statsAndCurrencyRow); currencyCard.Size=UDim2.new(0.5,-3,0,0); currencyCard.AutomaticSize=Enum.AutomaticSize.Y; currencyCard.BackgroundColor3=D.Card; currencyCard.BackgroundTransparency=D.GlassPane; currencyCard.BorderSizePixel=0; Corner(currencyCard,8); Stroke(currencyCard,D.Border,1,D.GlassStroke); Pad(currencyCard,10,10,10,10); VList(currencyCard,6)
SecLbl(currencyCard,"💰 SHOP CURRENCY")
local CURRENCIES={{key="Boss Coins",icon="🏆",color=D.Gold},{key="Esper Token",icon="🔮",color=D.Purple},{key="Cursed Scrolls",icon="📜",color=D.Lavender},{key="Cursed Essence",icon="💜",color=D.Purple},{key="CurseToken",icon="🌀",color=D.Cyan},{key="Gem",icon="💎",color=D.Cyan},{key="Gold",icon="🟡",color=D.Gold},{key="Sol Token",icon="☀️",color=D.Orange},{key="RCCells",icon="🔬",color=D.Teal}}
H.UI.Lbl.Currencies={}
for _,cur in ipairs(CURRENCIES) do
    local cRow=Instance.new("Frame",currencyCard); cRow.Size=UDim2.new(1,0,0,26); cRow.BackgroundColor3=D.CardHover; cRow.BorderSizePixel=0; Corner(cRow,7); Stroke(cRow,cur.color,1,0.65)
    local cBar=Instance.new("Frame",cRow); cBar.Size=UDim2.new(0,3,0.6,0); cBar.Position=UDim2.new(0,0,0.2,0); cBar.BackgroundColor3=cur.color; cBar.BorderSizePixel=0; Corner(cBar,2)
    local cNameLbl=Instance.new("TextLabel",cRow); cNameLbl.Position=UDim2.new(0,8,0,0); cNameLbl.Size=UDim2.new(0.6,-8,1,0); cNameLbl.BackgroundTransparency=1; cNameLbl.Text=cur.icon.."  "..cur.key; cNameLbl.TextColor3=cur.color; cNameLbl.TextSize=10; cNameLbl.Font=Enum.Font.GothamSemibold; cNameLbl.TextXAlignment=Enum.TextXAlignment.Left; cNameLbl.TextTruncate=Enum.TextTruncate.AtEnd
    local cValLbl=Instance.new("TextLabel",cRow); cValLbl.Position=UDim2.new(0.6,0,0,0); cValLbl.Size=UDim2.new(0.4,-4,1,0); cValLbl.BackgroundTransparency=1; cValLbl.Text="–"; cValLbl.TextColor3=D.TextHi; cValLbl.TextSize=11; cValLbl.Font=Enum.Font.GothamBold; cValLbl.TextXAlignment=Enum.TextXAlignment.Right
    H.UI.Lbl.Currencies[cur.key]=cValLbl
end
local function RebuildCurrencies()
    for _,cur in ipairs(CURRENCIES) do
        local lbl=H.UI.Lbl.Currencies[cur.key]; if not lbl then continue end
        local val=nil; pcall(function() val=Svc.RS:WaitForChild("Player_Data",3):WaitForChild(LP.Name,3):WaitForChild("Data",3):FindFirstChild(cur.key); if val then val=val.Value end end)
        if val~=nil then lbl.Text=FmtNum(val); lbl.TextColor3=D.TextHi else lbl.Text="–"; lbl.TextColor3=D.TextLow end
    end
end
NeonBtn(currencyCard,"🔄 Aktualisieren",D.CyanDim,26).MouseButton1Click:Connect(function() task.spawn(function() pcall(RebuildCurrencies) end) end)

-- Inventar-Items mit 2-Spalten UIGridLayout
MkLbl(InvPage,"📦 GEGENSTÄNDE",10,D.TextLow,true).Size=UDim2.new(1,0,0,14)
MkLbl(InvPage,"Klick = Ziel setzen",11,D.TextLow).Size=UDim2.new(1,0,0,20)
H.UI.Fr.InvList=Card(InvPage); Pad(H.UI.Fr.InvList,6,8,6,8)
H.UI.Fr.InvList.AutomaticSize=Enum.AutomaticSize.Y
-- 2-Spalten Grid für Items
local invGrid=Instance.new("UIGridLayout",H.UI.Fr.InvList)
invGrid.CellSize=UDim2.new(0.5,-4,0,52)
invGrid.CellPadding=UDim2.new(0,4,0,4)
invGrid.SortOrder=Enum.SortOrder.LayoutOrder
invGrid.FillDirection=Enum.FillDirection.Horizontal
invGrid.HorizontalAlignment=Enum.HorizontalAlignment.Left
invGrid.VerticalAlignment=Enum.VerticalAlignment.Top
H.UI.Lbl.InvEmpty=Instance.new("TextLabel",H.UI.Fr.InvList); H.UI.Lbl.InvEmpty.Size=UDim2.new(1,0,0,30); H.UI.Lbl.InvEmpty.BackgroundTransparency=1; H.UI.Lbl.InvEmpty.Text="Inventar wird geladen..."; H.UI.Lbl.InvEmpty.TextColor3=D.TextLow; H.UI.Lbl.InvEmpty.TextSize=12; H.UI.Lbl.InvEmpty.Font=Enum.Font.GothamMedium; H.UI.Lbl.InvEmpty.TextXAlignment=Enum.TextXAlignment.Center

local function RebuildInventory()
    for _,v in pairs(H.UI.Fr.InvList:GetChildren()) do if v:IsA("Frame") then v:Destroy() end end
    local folder; pcall(function() folder=Svc.RS:WaitForChild("Player_Data",5):WaitForChild(LP.Name,5):WaitForChild("Items",5) end)
    if not folder then H.UI.Lbl.InvEmpty.Visible=true; H.UI.Lbl.InvEmpty.Text="Pfad nicht gefunden"; H.UI.Lbl.InvEmpty.TextColor3=D.Orange; return end
    local children=folder:GetChildren(); if #children==0 then H.UI.Lbl.InvEmpty.Visible=true; H.UI.Lbl.InvEmpty.Text="Inventar leer"; H.UI.Lbl.InvEmpty.TextColor3=D.TextLow; return end
    H.UI.Lbl.InvEmpty.Visible=false; table.sort(children,function(a,b) return a.Name:lower()<b.Name:lower() end)
    for _,item in ipairs(children) do
        local iname,ival="",""; pcall(function()
            iname=item.Name; local vc=item:FindFirstChild("Value") or item:FindFirstChild("Amount")
            if vc then ival=tostring(vc.Value) elseif item:IsA("IntValue") or item:IsA("NumberValue") then ival=tostring(item.Value) end
        end)
        if iname~="" then
            local isRare=K.RARE[iname]==true
            local row=Instance.new("Frame",H.UI.Fr.InvList); row.Size=UDim2.new(1,0,0,52); row.BorderSizePixel=0; Corner(row,7)
            row.BackgroundColor3=isRare and D.RedDark or D.CardHover; Stroke(row,isRare and D.Red or D.Border,1,isRare and 0 or 0.5)
            local clickBtn=Instance.new("TextButton",row); clickBtn.Size=UDim2.new(1,0,1,0); clickBtn.BackgroundTransparency=1; clickBtn.Text=""; clickBtn.BorderSizePixel=0
            local cap=iname
            clickBtn.MouseButton1Click:Connect(function()
                if _G.HazeHubFunctions.SetGoalFromInventory and type(_G.HazeHubFunctions.SetGoalFromInventory) == "function" then
                    _G.HazeHubFunctions.SetGoalFromInventory(cap)
                else
                    warn("[HazeHUB] SetGoalFromInventory Funktion nicht gefunden!")
                end
                Tw(row,{BackgroundColor3=D.RowSelect}); task.delay(0.3,function() Tw(row,{BackgroundColor3=isRare and D.RedDark or D.CardHover}) end)
            end)
            clickBtn.MouseEnter:Connect(function() Tw(row,{BackgroundColor3=isRare and Color3.fromRGB(80,18,18) or D.CardHover}) end)
            clickBtn.MouseLeave:Connect(function() Tw(row,{BackgroundColor3=isRare and D.RedDark or D.CardHover}) end)
            -- ★ Dual Preview: erst Texture-ID, dann ViewportFrame
            local previewFrame = BuildItemPreview(row, iname, 44)
            previewFrame.Position = UDim2.new(0,4,0.5,-22)
            Stroke(previewFrame, isRare and D.Red or D.Border, 1, 0.5)
            local bar=Instance.new("Frame",row); bar.Size=UDim2.new(0,3,0.55,0); bar.Position=UDim2.new(0,52,0.225,0); bar.BackgroundColor3=isRare and D.Red or D.Purple; bar.BorderSizePixel=0; Corner(bar,2)
            local nL=Instance.new("TextLabel",row); nL.Position=UDim2.new(0,60,0,4); nL.Size=UDim2.new(1,-120,0,20); nL.BackgroundTransparency=1; nL.Text=iname; nL.TextColor3=isRare and D.Red or D.TextHi; nL.TextSize=12; nL.Font=Enum.Font.GothamSemibold; nL.TextXAlignment=Enum.TextXAlignment.Left; nL.TextTruncate=Enum.TextTruncate.AtEnd
            local hL=Instance.new("TextLabel",row); hL.Position=UDim2.new(1,-70,0,4); hL.Size=UDim2.new(0,64,0,20); hL.BackgroundTransparency=1; hL.TextXAlignment=Enum.TextXAlignment.Right
            if ival~="" then hL.Text="×"..ival; hL.TextColor3=D.Purple; hL.TextSize=13; hL.Font=Enum.Font.GothamBold else hL.Text="→ Ziel"; hL.TextColor3=D.TextLow; hL.TextSize=10; hL.Font=Enum.Font.Gotham end
        end
    end
end
NeonBtn(InvPage,"🔄  Inventar neu laden",D.CyanDim,30).MouseButton1Click:Connect(function()
    H.UI.Lbl.InvEmpty.Text="⏳ Lädt..."; H.UI.Lbl.InvEmpty.TextColor3=D.Yellow; H.UI.Lbl.InvEmpty.Visible=true
    task.spawn(function() pcall(RebuildInventory) end)
end)
task.spawn(function() while S.Running do task.wait(30); if S.ActiveTab=="Inventory" then pcall(RebuildCurrencies); pcall(RefreshPlayerStats) end end end)
end) -- end pcall Inventory Tab

-- ╔══════════════════════════════════════════════════════════╗
--  QUESTS TAB
-- ╚══════════════════════════════════════════════════════════╝
pcall(function()
MkLbl(QuestPage,"📋  Quests",14,D.Cyan,true)
local questRefBtn=NeonBtn(QuestPage,"🔄  Quests aktualisieren",D.CyanDim,28)
local function GQD(qf)
    local d=""; pcall(function() local a=qf:GetAttribute("des"); if a then d=tostring(a) else local c=qf:FindFirstChild("des"); if c then d=tostring(c.Value) end end end); return d
end
local function GQP(qf)
    local p,n=0,1
    pcall(function() local pv=qf:FindFirstChild("progress"); local nv=qf:FindFirstChild("questneed"); if pv then p=tonumber(pv.Value) or 0 end; if nv then n=tonumber(nv.Value) or 1 end end)
    return p,n
end
-- BQR gibt jetzt eine Frame zurück (ohne direkt Parent zu setzen) damit wir 2 nebeneinander legen können
local function BQR(parent,title,des,progress,questneed,isClaimed,acc)
    local pct=math.min(1,progress/math.max(1,questneed)); local rH=(des and des~="") and 60 or 44
    local row=Instance.new("Frame",parent); row.Size=UDim2.new(1,0,0,rH); row.BorderSizePixel=0; Corner(row,8)
    if isClaimed then row.BackgroundColor3=Color3.fromRGB(0,35,18); Stroke(row,D.GreenBright,1,0.3)
    else row.BackgroundColor3=D.CardHover; Stroke(row,acc or D.Cyan,1,0.55) end
    local acBar=Instance.new("Frame",row); acBar.Size=UDim2.new(0,3,0.7,0); acBar.Position=UDim2.new(0,0,0.15,0); acBar.BackgroundColor3=isClaimed and D.GreenBright or (acc or D.Cyan); acBar.BorderSizePixel=0; Corner(acBar,2)
    local tLbl=Instance.new("TextLabel",row); tLbl.Position=UDim2.new(0,10,0,4); tLbl.Size=UDim2.new(1,-60,0,16); tLbl.BackgroundTransparency=1; tLbl.Text=(isClaimed and "✅ " or "")..title; tLbl.TextColor3=isClaimed and D.GreenBright or D.TextHi; tLbl.TextSize=11; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left; tLbl.TextTruncate=Enum.TextTruncate.AtEnd
    if des and des~="" then local dLbl=Instance.new("TextLabel",row); dLbl.Position=UDim2.new(0,10,0,20); dLbl.Size=UDim2.new(1,-60,0,14); dLbl.BackgroundTransparency=1; dLbl.Text=des; dLbl.TextColor3=D.TextLow; dLbl.TextSize=9; dLbl.Font=Enum.Font.Gotham; dLbl.TextXAlignment=Enum.TextXAlignment.Left; dLbl.TextTruncate=Enum.TextTruncate.AtEnd end
    local pgBg=Instance.new("Frame",row); pgBg.Size=UDim2.new(1,-14,0,4); pgBg.Position=UDim2.new(0,10,1,(des and des~="") and -6 or -5); pgBg.BackgroundColor3=Color3.fromRGB(20,28,50); pgBg.BorderSizePixel=0; Corner(pgBg,2)
    local pgF=Instance.new("Frame",pgBg); pgF.Size=UDim2.new(pct,0,1,0); pgF.BackgroundColor3=isClaimed and D.GreenBright or (acc or D.Cyan); pgF.BorderSizePixel=0; Corner(pgF,2)
    local pctLbl=Instance.new("TextLabel",row); pctLbl.Position=UDim2.new(1,-52,0,4); pctLbl.Size=UDim2.new(0,46,0,16); pctLbl.BackgroundTransparency=1; pctLbl.Text=string.format("%d/%d",progress,questneed); pctLbl.TextColor3=isClaimed and D.GreenBright or D.TextLow; pctLbl.TextSize=9; pctLbl.Font=Enum.Font.GothamSemibold; pctLbl.TextXAlignment=Enum.TextXAlignment.Right
    return row
end
-- Hilfsfunktion: fügt Quests in 2er-Paaren als Zeilen ein
local function AddQuestsPaired(container, quests, acc, isClaims)
    local i = 1
    while i <= #quests do
        local rowFrame=Instance.new("Frame",container); rowFrame.Size=UDim2.new(1,0,0,0); rowFrame.AutomaticSize=Enum.AutomaticSize.Y; rowFrame.BackgroundTransparency=1; HList(rowFrame,6)
        -- Quest 1
        local qf1=quests[i]
        local iC1=false; pcall(function() local cl=qf1:FindFirstChild("claimed"); if cl and cl.Value==true then iC1=true end end)
        if isClaims then iC1=isClaims[i] end
        local p1,n1=GQP(qf1); local q1=BQR(rowFrame,qf1.Name,GQD(qf1),p1,n1,iC1,acc)
        q1.Size=UDim2.new(0.5,-3,0,q1.Size.Y.Offset)
        -- Quest 2 (falls vorhanden)
        if quests[i+1] then
            local qf2=quests[i+1]
            local iC2=false; pcall(function() local cl=qf2:FindFirstChild("claimed"); if cl and cl.Value==true then iC2=true end end)
            if isClaims then iC2=isClaims[i+1] end
            local p2,n2=GQP(qf2); local q2=BQR(rowFrame,qf2.Name,GQD(qf2),p2,n2,iC2,acc)
            q2.Size=UDim2.new(0.5,-3,0,math.max(q1.Size.Y.Offset,q2.Size.Y.Offset))
            q1.Size=UDim2.new(0.5,-3,0,math.max(q1.Size.Y.Offset,q2.Size.Y.Offset))
        end
        i = i + 2
    end
end
local questContainer=Instance.new("Frame",QuestPage); questContainer.Size=UDim2.new(1,0,0,0); questContainer.AutomaticSize=Enum.AutomaticSize.Y; questContainer.BackgroundTransparency=1; VList(questContainer,8)
local function RebuildQuestsUI()
    for _,v in pairs(questContainer:GetChildren()) do if v:IsA("Frame") or v:IsA("TextLabel") then v:Destroy() end end
    local pdr=nil; pcall(function() pdr=Svc.RS:WaitForChild("Player_Data",3):WaitForChild(LP.Name,3) end)
    if not pdr then MkLbl(questContainer,"⚠ Player_Data nicht gefunden!",11,D.Orange).Size=UDim2.new(1,0,0,28); return end
    local pqr=nil; pcall(function() pqr=pdr:WaitForChild("PlayerQuest",3) end)
    if not pqr then MkLbl(questContainer,"⚠ PlayerQuest nicht gefunden!",11,D.Orange).Size=UDim2.new(1,0,0,28); return end
    for _,cd in ipairs({
        {folderName="easy_quest",  label="EASY QUESTS",  icon="🟢",color=D.Green},
        {folderName="normal_quest",label="NORMAL QUESTS",icon="🟡",color=D.Yellow},
        {folderName="hard_quest",  label="HARD QUESTS",  icon="🔴",color=D.Red}
    }) do
        local catFolder=nil; pcall(function() catFolder=pqr:FindFirstChild(cd.folderName) end)
        local catCard=Card(questContainer); Pad(catCard,10,12,10,12); VList(catCard,6); Stroke(catCard,cd.color,1.5,0.3)
        local hLbl=Instance.new("TextLabel",catCard); hLbl.Size=UDim2.new(1,0,0,22); hLbl.BackgroundTransparency=1; hLbl.Text=cd.icon.."  "..cd.label; hLbl.TextColor3=cd.color; hLbl.TextSize=12; hLbl.Font=Enum.Font.GothamBold; hLbl.TextXAlignment=Enum.TextXAlignment.Left
        if not catFolder then MkLbl(catCard,"Ordner '"..cd.folderName.."' nicht gefunden.",10,D.TextLow).Size=UDim2.new(1,0,0,18); continue end
        local catClaimed=false; pcall(function() local cl=catFolder:FindFirstChild("claimed"); if cl and cl.Value==true then catClaimed=true end end)
        local cP,cN=0,1; pcall(function() local pg=catFolder:FindFirstChild("progress"); local nd=catFolder:FindFirstChild("questneed"); if pg then cP=tonumber(pg.Value) or 0 end; if nd then cN=tonumber(nd.Value) or 1 end end)
        local cpRow=Instance.new("Frame",catCard); cpRow.Size=UDim2.new(1,0,0,18); cpRow.BackgroundTransparency=1; HList(cpRow,6)
        local cpTxt=Instance.new("TextLabel",cpRow); cpTxt.Size=UDim2.new(0.55,0,1,0); cpTxt.BackgroundTransparency=1; cpTxt.Text=string.format("Gesamt: %d / %d",cP,cN); cpTxt.TextColor3=catClaimed and D.GreenBright or D.TextMid; cpTxt.TextSize=10; cpTxt.Font=Enum.Font.GothamSemibold; cpTxt.TextXAlignment=Enum.TextXAlignment.Left
        local cbBg=Instance.new("Frame",cpRow); cbBg.Size=UDim2.new(0.45,0,0,6); cbBg.BackgroundColor3=Color3.fromRGB(20,28,50); cbBg.BorderSizePixel=0; Corner(cbBg,3)
        local cbF=Instance.new("Frame",cbBg); cbF.Size=UDim2.new(math.min(1,cP/math.max(1,cN)),0,1,0); cbF.BackgroundColor3=catClaimed and D.GreenBright or cd.color; cbF.BorderSizePixel=0; Corner(cbF,3)
        if catClaimed then
            local df=Instance.new("Frame",catCard); df.Size=UDim2.new(1,0,0,30); df.BackgroundColor3=D.GreenDark; df.BorderSizePixel=0; Corner(df,7); Stroke(df,D.GreenBright,1.5,0.2)
            local dL=Instance.new("TextLabel",df); dL.Size=UDim2.new(1,0,1,0); dL.BackgroundTransparency=1; dL.Text="✅ ALLE BELOHNUNGEN ABGEHOLT!"; dL.TextColor3=D.GreenBright; dL.TextSize=12; dL.Font=Enum.Font.GothamBold; dL.TextXAlignment=Enum.TextXAlignment.Center; continue
        end
        local sq={}; local qsf=catFolder:FindFirstChild("Quests")
        if qsf then for _,ch in ipairs(qsf:GetChildren()) do if not ch:IsA("UIGridLayout") and not ch:IsA("UIListLayout") then table.insert(sq,ch) end end
        else
            for i=1,4 do local qf=catFolder:FindFirstChild(cd.folderName.."_"..i); if qf then table.insert(sq,qf) end end
            if #sq==0 then local SK={claimed=true,progress=true,questneed=true,Quests=true}; for _,ch in ipairs(catFolder:GetChildren()) do if not SK[ch.Name] then table.insert(sq,ch) end end end
        end
        if #sq==0 then MkLbl(catCard,"Keine Sub-Quests.",10,D.TextLow).Size=UDim2.new(1,0,0,18)
        else
            table.sort(sq,function(a,b) return a.Name<b.Name end)
            AddQuestsPaired(catCard, sq, cd.color)
        end
    end
    for _,spec in ipairs({
        {key="WeeklyQuest",label="🟣  WEEKLY QUESTS",color=D.Purple},
        {key="DailyQuest", label="🔵  DAILY QUESTS", color=D.Teal},
    }) do
        local root=nil; pcall(function() root=pdr:FindFirstChild(spec.key) end)
        local sc=Card(questContainer); Pad(sc,10,12,10,12); VList(sc,6); Stroke(sc,spec.color,1.5,0.3)
        local hd=Instance.new("TextLabel",sc); hd.Size=UDim2.new(1,0,0,22); hd.BackgroundTransparency=1; hd.Text=spec.label; hd.TextColor3=spec.color; hd.TextSize=12; hd.Font=Enum.Font.GothamBold; hd.TextXAlignment=Enum.TextXAlignment.Left
        if not root then
            MkLbl(sc,spec.key.." nicht gefunden.",10,D.TextLow).Size=UDim2.new(1,0,0,18)
        else
            local found=false; local SK={claimed=true,progress=true,questneed=true}
            local sqList={}
            for _,qf in ipairs(root:GetChildren()) do
                if SK[qf.Name] then continue end
                table.insert(sqList,qf); found=true
            end
            if found then
                AddQuestsPaired(sc, sqList, spec.color)
            else
                local adf=Instance.new("Frame",sc); adf.Size=UDim2.new(1,0,0,28); adf.BackgroundColor3=D.GreenDark; adf.BorderSizePixel=0; Corner(adf,7); Stroke(adf,D.GreenBright,1.5,0.2)
                local dL=Instance.new("TextLabel",adf); dL.Size=UDim2.new(1,0,1,0); dL.BackgroundTransparency=1; dL.Text="✅ Alle "..spec.key:gsub("Quest","").." Quests erledigt!"; dL.TextColor3=D.GreenBright; dL.TextSize=11; dL.Font=Enum.Font.GothamBold; dL.TextXAlignment=Enum.TextXAlignment.Center
            end
        end
    end
end
questRefBtn.MouseButton1Click:Connect(function() task.spawn(function() pcall(RebuildQuestsUI) end) end)
task.spawn(function() while S.Running do task.wait(30); if S.ActiveTab=="Quests" then pcall(RebuildQuestsUI) end end end)
task.delay(2.5,function() pcall(RebuildQuestsUI) end)
end) -- end pcall Quests Tab

-- ╔══════════════════════════════════════════════════════════╗
--  TRAITS TAB  – Placeholder (trait.lua lädt hier rein)
-- ╚══════════════════════════════════════════════════════════╝
do
    local traitWaitLbl=MkLbl(TraitPage,"⏳ Trait-Modul wird geladen...",11,D.Yellow)
    traitWaitLbl.Size=UDim2.new(1,0,0,20)
    _G._TraitWaitLbl=traitWaitLbl
end

-- ╔══════════════════════════════════════════════════════════╗
--  SHOPS TAB – Placeholder (Shops.lua lädt hier rein)
-- ╚══════════════════════════════════════════════════════════╝
do
    local shopWaitLbl=MkLbl(ShopPage,"⏳ Shop-Modul wird geladen...",11,D.Yellow)
    shopWaitLbl.Size=UDim2.new(1,0,0,20)
end

-- ╔══════════════════════════════════════════════════════════╗
--  CRAFTING TAB – Placeholder (craft.lua lädt hier rein)
-- ╚══════════════════════════════════════════════════════════╝
do
    local craftWaitLbl=MkLbl(CraftPage,"⏳ Craft-Modul wird geladen...",11,D.Yellow)
    craftWaitLbl.Size=UDim2.new(1,0,0,20)
    _G._CraftWaitLbl=craftWaitLbl
end

-- ╔══════════════════════════════════════════════════════════╗
--  TEAMS TAB – Placeholder (teams.lua lädt hier rein)
-- ╚══════════════════════════════════════════════════════════╝
do
    local teamsWaitLbl=MkLbl(TeamsPage,"⏳ Team-Manager wird geladen...",11,D.Yellow)
    teamsWaitLbl.Size=UDim2.new(1,0,0,20)
    _G._TeamsWaitLbl=teamsWaitLbl
end

-- ╔══════════════════════════════════════════════════════════╗
--  SETTINGS TAB
-- ╚══════════════════════════════════════════════════════════╝
pcall(function()
MkLbl(SettPage,"⚙  Einstellungen",14,D.Cyan,true)
local szCard=Card(SettPage); Pad(szCard,10,10,10,10); VList(szCard,8); SecLbl(szCard,"FENSTERGRÖSSE")
local szRow=Instance.new("Frame",szCard); szRow.Size=UDim2.new(1,0,0,34); szRow.BackgroundTransparency=1; HList(szRow,8)
H.UI.Btn.PCBtn=Instance.new("TextButton",szRow); H.UI.Btn.PCBtn.Size=UDim2.new(0.48,0,1,0); H.UI.Btn.PCBtn.BackgroundColor3=D.CardHover; H.UI.Btn.PCBtn.Text="🖥  PC"; H.UI.Btn.PCBtn.TextColor3=D.TextHi; H.UI.Btn.PCBtn.TextSize=12; H.UI.Btn.PCBtn.Font=Enum.Font.GothamBold; H.UI.Btn.PCBtn.AutoButtonColor=false; H.UI.Btn.PCBtn.BorderSizePixel=0; Corner(H.UI.Btn.PCBtn,7); Stroke(H.UI.Btn.PCBtn,D.Cyan,1,0.3)
local _pcAsp = Instance.new("UIAspectRatioConstraint", H.UI.Btn.PCBtn); _pcAsp.AspectRatio = 2.4; _pcAsp.DominantAxis = Enum.DominantAxis.Height
H.UI.Btn.MobBtn=Instance.new("TextButton",szRow); H.UI.Btn.MobBtn.Size=UDim2.new(0.48,0,1,0); H.UI.Btn.MobBtn.BackgroundColor3=D.CardHover; H.UI.Btn.MobBtn.Text="📱  Mobile"; H.UI.Btn.MobBtn.TextColor3=D.TextHi; H.UI.Btn.MobBtn.TextSize=12; H.UI.Btn.MobBtn.Font=Enum.Font.GothamBold; H.UI.Btn.MobBtn.AutoButtonColor=false; H.UI.Btn.MobBtn.BorderSizePixel=0; Corner(H.UI.Btn.MobBtn,7); Stroke(H.UI.Btn.MobBtn,D.Border,1,0.3)
local _mobAsp = Instance.new("UIAspectRatioConstraint", H.UI.Btn.MobBtn); _mobAsp.AspectRatio = 2.4; _mobAsp.DominantAxis = Enum.DominantAxis.Height
H.UI.Btn.PCBtn.MouseButton1Click:Connect(function() SetGUISize("PC"); Stroke(H.UI.Btn.PCBtn,D.Cyan,1,0.3); Stroke(H.UI.Btn.MobBtn,D.Border,1,0.3) end)
H.UI.Btn.MobBtn.MouseButton1Click:Connect(function() SetGUISize("Mobile"); Stroke(H.UI.Btn.MobBtn,D.Cyan,1,0.3); Stroke(H.UI.Btn.PCBtn,D.Border,1,0.3) end)
local lobCard=Card(SettPage); Pad(lobCard,10,10,10,10); VList(lobCard,8); SecLbl(lobCard,"LOBBY-TELEPORT")
MkLbl(lobCard,"Teleportiert zur Lobby (Place ID: "..K.LOBBY_ID..")",9,D.TextLow).Size=UDim2.new(1,0,0,14)
NeonBtn(lobCard,"🏠  Back to Lobby",D.Orange,38).MouseButton1Click:Connect(function() H.Config.AutoFarm=false; SaveConfig(); SaveSettings(); TeleportToLobby() end)
local kbCard=Card(SettPage); Pad(kbCard,10,10,10,10); VList(kbCard,8); SecLbl(kbCard,"GUI KEYBIND")
local kbRow=Instance.new("Frame",kbCard); kbRow.Size=UDim2.new(1,0,0,34); kbRow.BackgroundTransparency=1; HList(kbRow,8)
MkLbl(kbRow,"Toggle-Taste:",12,D.TextMid).Size=UDim2.new(0.52,0,1,0)
H.UI.Btn.KeyBtn=Instance.new("TextButton",kbRow); H.UI.Btn.KeyBtn.Size=UDim2.new(0.46,0,0,34); H.UI.Btn.KeyBtn.BackgroundColor3=D.CardHover; H.UI.Btn.KeyBtn.Text="[ F4 ]"; H.UI.Btn.KeyBtn.TextColor3=D.Accent; H.UI.Btn.KeyBtn.TextSize=13; H.UI.Btn.KeyBtn.Font=Enum.Font.GothamBold; H.UI.Btn.KeyBtn.AutoButtonColor=false; H.UI.Btn.KeyBtn.BorderSizePixel=0; Corner(H.UI.Btn.KeyBtn,8); Stroke(H.UI.Btn.KeyBtn,D.Accent,1,0.3)
local function SetKeyDisplay(k) H.UI.Btn.KeyBtn.Text="[ "..(k or "F4").." ]"; H.UI.Btn.KeyBtn.TextColor3=D.Accent; Stroke(H.UI.Btn.KeyBtn,D.Accent,1,0.3) end
_G._SetKeyDisplay=SetKeyDisplay
_G.HazeHubFunctions.SetKeyDisplay=SetKeyDisplay
H.UI.Btn.KeyBtn.MouseButton1Click:Connect(function()
    if S.KeyListening then return end; S.KeyListening=true; H.UI.Btn.KeyBtn.Text="⌨ Taste drücken..."; H.UI.Btn.KeyBtn.TextColor3=D.Yellow; Stroke(H.UI.Btn.KeyBtn,D.Yellow,1.5,0)
    task.spawn(function() while S.KeyListening do Tw(H.UI.Btn.KeyBtn,{BackgroundColor3=Color3.fromRGB(58,52,8)}); task.wait(0.4); if S.KeyListening then Tw(H.UI.Btn.KeyBtn,{BackgroundColor3=D.CardHover}); task.wait(0.4) end end end)
    S.KeyConn=Svc.Input.InputBegan:Connect(function(inp,_)
        if inp.UserInputType~=Enum.UserInputType.Keyboard then return end
        for _,k in ipairs({Enum.KeyCode.LeftShift,Enum.KeyCode.RightShift,Enum.KeyCode.LeftControl,Enum.KeyCode.RightControl,Enum.KeyCode.LeftAlt,Enum.KeyCode.RightAlt}) do if inp.KeyCode==k then return end end
        S.KeyListening=false; if S.KeyConn then S.KeyConn:Disconnect() end; S.KeyConn=nil
        H.Config.ToggleKey=inp.KeyCode.Name; SaveConfig(); SetKeyDisplay(H.Config.ToggleKey); Tw(H.UI.Btn.KeyBtn,{BackgroundColor3=D.CardHover}); Stroke(H.UI.Btn.KeyBtn,D.Green,2,0); task.delay(0.8,function() Stroke(H.UI.Btn.KeyBtn,D.Accent,1,0.3) end)
    end)
end)
MkLbl(kbCard,"Klicke, dann drücke die gewünschte Taste.",10,D.TextLow).Size=UDim2.new(1,0,0,14)
local whCard=Card(SettPage); Pad(whCard,12,12,12,12); VList(whCard,8); SecLbl(whCard,"DISCORD WEBHOOK")
local whOuter,whBox=MkInput(whCard,"https://discord.com/api/webhooks/..."); whOuter.Size=UDim2.new(1,0,0,36); H.UI.Inp.Webhook=whBox
local wLine=Instance.new("Frame",whOuter); wLine.Size=UDim2.new(0,0,0,2); wLine.Position=UDim2.new(0,0,1,-2); wLine.BackgroundColor3=D.AccentDim; wLine.BorderSizePixel=0; Corner(wLine,2)
whBox.Focused:Connect(function() Stroke(whOuter,D.Accent,1,0.2); Tw(wLine,{Size=UDim2.new(1,0,0,2)},TM) end)
whBox.FocusLost:Connect(function() H.Config.WebhookURL=whBox.Text; SaveConfig(); Stroke(whOuter,D.Border,1,0.2); Tw(wLine,{Size=UDim2.new(0,0,0,2)},TM) end)
NeonBtn(whCard,"📤  Test senden",D.CyanDim,34).MouseButton1Click:Connect(function() SendWebhook() end)
NeonBtn(SettPage,"⏏  GUI vollständig entladen",D.Red,34).MouseButton1Click:Connect(function()
    S.Running=false; S.WhEnabled=false; H.Config.AutoFarm=false; SaveSettings()
    if S.ChildConn then pcall(function() S.ChildConn:Disconnect() end) end
    if _G.HazeShared and _G.HazeShared.StopFarm then pcall(_G.HazeShared.StopFarm) end
    pcall(function() if HazeHubBlur and HazeHubBlur.Parent then HazeHubBlur:Destroy() end end)
    pcall(function() ScreenGui:Destroy() end); pcall(function() H.UI.Fr.MiniBtn:Destroy() end)
end)

-- ── DATA WIPE (3-sekündiger Hold) ────────────────────────────────────────────
do
    local wipeCard = Card(SettPage); Pad(wipeCard, 10, 10, 10, 10); VList(wipeCard, 6)
    Stroke(wipeCard, D.Red, 1.5, 0.2)
    local wipeHdr = Instance.new("TextLabel", wipeCard)
    wipeHdr.Size = UDim2.new(1, 0, 0, 14); wipeHdr.BackgroundTransparency = 1
    wipeHdr.Text = "⚠  GEFAHRENZONE"; wipeHdr.TextColor3 = D.Red
    wipeHdr.TextSize = 10; wipeHdr.Font = Enum.Font.GothamBold
    wipeHdr.TextXAlignment = Enum.TextXAlignment.Left
    local wipeLbl = MkLbl(wipeCard, "Löscht alle lokalen JSON-Dateien dieses Accounts.\nHalte den Button 3 Sekunden gedrückt.", 9, D.TextLow)
    wipeLbl.Size = UDim2.new(1, 0, 0, 28)

    -- Hold-Fortschrittsbalken
    local wipeBarBg = Instance.new("Frame", wipeCard)
    wipeBarBg.Size = UDim2.new(1, 0, 0, 4); wipeBarBg.BackgroundColor3 = Color3.fromRGB(40, 10, 10)
    wipeBarBg.BorderSizePixel = 0; Corner(wipeBarBg, 2); wipeBarBg.Visible = false
    local wipeBarFill = Instance.new("Frame", wipeBarBg)
    wipeBarFill.Size = UDim2.new(0, 0, 1, 0); wipeBarFill.BackgroundColor3 = D.Red
    wipeBarFill.BorderSizePixel = 0; Corner(wipeBarFill, 2)

    local wipeBtn = Instance.new("TextButton", wipeCard)
    wipeBtn.Size = UDim2.new(1, 0, 0, 38); wipeBtn.BackgroundColor3 = D.RedDark
    wipeBtn.Text = "⚠️ ALLE BENUTZERDATEN LÖSCHEN"; wipeBtn.TextColor3 = D.Red
    wipeBtn.TextSize = 13; wipeBtn.Font = Enum.Font.GothamBold
    wipeBtn.AutoButtonColor = false; wipeBtn.BorderSizePixel = 0
    Corner(wipeBtn, 8); Stroke(wipeBtn, D.Red, 1.5, 0.3)

    local wipeFeedback = MkLbl(wipeCard, "", 10, D.TextLow)
    wipeFeedback.Size = UDim2.new(1, 0, 0, 16)

    local _wipeHolding = false
    local _wipeConn = nil
    local HOLD_DURATION = 3.0

    local function DoWipe()
        wipeBtn.Text = "⏳ Lösche Daten..."; wipeBtn.TextColor3 = D.Orange
        local files = {
            K.FOLDER .. "/" .. LP.Name .. "_settings.json",
            K.FOLDER .. "/" .. LP.Name .. "_teams.json",
            K.FOLDER .. "/" .. LP.Name .. "_autosave.json",
        }
        local deleted = 0
        for _, fpath in ipairs(files) do
            pcall(function()
                if isfile and isfile(fpath) then
                    delfile(fpath)
                    deleted = deleted + 1
                end
            end)
        end
        wipeFeedback.Text = "✅ " .. deleted .. " Datei(en) gelöscht. UI wird geschlossen..."
        wipeFeedback.TextColor3 = D.GreenBright
        task.delay(1.2, function()
            pcall(function()
                S.Running = false; S.WhEnabled = false
                if HazeHubBlur and HazeHubBlur.Parent then HazeHubBlur:Destroy() end
                ScreenGui:Destroy()
                pcall(function() H.UI.Fr.MiniBtn:Destroy() end)
            end)
        end)
    end

    wipeBtn.MouseButton1Down:Connect(function()
        if _wipeHolding then return end
        _wipeHolding = true
        wipeBarBg.Visible = true
        wipeBtn.Text = "⏳ Halten... (3s)"; wipeBtn.TextColor3 = D.Orange
        Stroke(wipeBtn, D.Orange, 2, 0)
        local t0 = os.clock()
        local loop
        loop = game:GetService("RunService").Heartbeat:Connect(function()
            if not _wipeHolding then
                loop:Disconnect(); return
            end
            local elapsed = os.clock() - t0
            local pct = math.min(1, elapsed / HOLD_DURATION)
            wipeBarFill.Size = UDim2.new(pct, 0, 1, 0)
            if elapsed >= HOLD_DURATION then
                loop:Disconnect()
                _wipeHolding = false
                wipeBarBg.Visible = false
                wipeBarFill.Size = UDim2.new(0, 0, 1, 0)
                DoWipe()
            end
        end)
        _wipeConn = loop
    end)

    local function CancelWipe()
        if not _wipeHolding then return end
        _wipeHolding = false
        if _wipeConn then pcall(function() _wipeConn:Disconnect() end); _wipeConn = nil end
        wipeBarBg.Visible = false
        wipeBarFill.Size = UDim2.new(0, 0, 1, 0)
        wipeBtn.Text = "⚠️ ALLE BENUTZERDATEN LÖSCHEN"; wipeBtn.TextColor3 = D.Red
        Stroke(wipeBtn, D.Red, 1.5, 0.3)
    end
    wipeBtn.MouseButton1Up:Connect(CancelWipe)
    wipeBtn.MouseLeave:Connect(CancelWipe)
    wipeBtn.MouseEnter:Connect(function()
        if not _wipeHolding then Tw(wipeBtn, {BackgroundColor3 = Color3.fromRGB(60, 14, 14)}) end
    end)
    wipeBtn.MouseLeave:Connect(function()
        if not _wipeHolding then Tw(wipeBtn, {BackgroundColor3 = D.RedDark}) end
    end)
end
end) -- end pcall Settings Tab

-- ── Mobile Button (rund, links mittig, Haze-Logo PNG zentriert) ──────────────
H.UI.Fr.MiniBtn=Instance.new("TextButton",ScreenGui)
-- Groesser fuer Mobile: 6.5% Breite, quadratisch via AspectRatio
H.UI.Fr.MiniBtn.Name="MiniBtn"; H.UI.Fr.MiniBtn.Size=UDim2.new(0.065,0,0.10,0)
H.UI.Fr.MiniBtn.AnchorPoint=Vector2.new(0,0.5); H.UI.Fr.MiniBtn.Position=UDim2.new(0.008,0,0.5,0)
local MiniAsp = Instance.new("UIAspectRatioConstraint", H.UI.Fr.MiniBtn); MiniAsp.AspectRatio = 1
H.UI.Fr.MiniBtn.BackgroundColor3=D.BG; H.UI.Fr.MiniBtn.BackgroundTransparency=0.2
H.UI.Fr.MiniBtn.Text=""; H.UI.Fr.MiniBtn.AutoButtonColor=false; H.UI.Fr.MiniBtn.BorderSizePixel=0; Corner(H.UI.Fr.MiniBtn,99)
local MBRing=Instance.new("Frame",H.UI.Fr.MiniBtn); MBRing.Size=UDim2.new(1,10,1,10); MBRing.Position=UDim2.new(0.5,0,0.5,0); MBRing.AnchorPoint=Vector2.new(0.5,0.5)
MBRing.BackgroundTransparency=1; MBRing.BorderSizePixel=0; MBRing.ZIndex=0; Corner(MBRing,99); Stroke(MBRing,D.Border,1.5,0.45)
local mbLogo=Instance.new("ImageLabel",H.UI.Fr.MiniBtn); mbLogo.Name="HubLogo"; mbLogo.BackgroundTransparency=1
mbLogo.Size=UDim2.new(0.72,0,0.72,0); mbLogo.Position=UDim2.new(0.5,0,0.5,0); mbLogo.AnchorPoint=Vector2.new(0.5,0.5)
mbLogo.Image=HAZE_ASSETS.LogoRbx; mbLogo.ScaleType=Enum.ScaleType.Fit; mbLogo.ZIndex=2
local function SyncBlurToGui() pcall(function() if HazeHubBlur and HazeHubBlur.Parent then HazeHubBlur.Enabled=MainFrame.Visible end end) end
local function ToggleHubGui()
    MainFrame.Visible=not MainFrame.Visible
    S.GuiVisible=MainFrame.Visible
    H.Config.GuiVisible=S.GuiVisible
    SyncBlurToGui()
    SaveConfig()
end
local _mobFirstClick = true
local function OnMiniBtnClick()
    if _mobFirstClick then
        _mobFirstClick = false
        MainFrame.Visible = true
    else
        MainFrame.Visible = not MainFrame.Visible
    end
    S.GuiVisible=MainFrame.Visible
    H.Config.GuiVisible=S.GuiVisible
    SyncBlurToGui()
    SaveConfig()
end
H.UI.Fr.MiniBtn.MouseEnter:Connect(function() Tw(H.UI.Fr.MiniBtn,{BackgroundTransparency=0.08},TM); Stroke(MBRing,D.Accent,2,0.25) end)
H.UI.Fr.MiniBtn.MouseLeave:Connect(function() Tw(H.UI.Fr.MiniBtn,{BackgroundTransparency=0.2},TM); Stroke(MBRing,D.Border,1.5,0.45) end)
H.UI.Fr.MiniBtn.MouseButton1Down:Connect(function() Tw(H.UI.Fr.MiniBtn,{Size=UDim2.new(0.058,0,0.090,0)},TF) end)
H.UI.Fr.MiniBtn.MouseButton1Up:Connect(function() Tw(H.UI.Fr.MiniBtn,{Size=UDim2.new(0.065,0,0.10,0)},TF) end)
H.UI.Fr.MiniBtn.MouseButton1Click:Connect(OnMiniBtnClick)
MakeDraggable(H.UI.Fr.Main,MainFrame)
MakeDraggable(H.UI.Fr.MiniBtn,H.UI.Fr.MiniBtn)
Svc.Input.InputBegan:Connect(function(inp,processed)
    if processed then return end; if S.KeyListening then return end
    if inp.UserInputType==Enum.UserInputType.Keyboard and inp.KeyCode.Name==H.Config.ToggleKey then
        ToggleHubGui()
    end
end)

-- ── Game Events (GameEndedUI) ─────────────────────────────────
if R.Remote then
    R.Remote.OnClientEvent:Connect(function(cat, data)
        if cat == "GameEnded_TextAnimation" and data == "Won" then
            if H.Config.AutoRetry then FireVoteRetry() end
            return
        end
        local catStr = tostring(cat)
        if cat == "Update - EndedScreen" or catStr == "Update - EndedScreen" or (catStr:find("Update", 1, true) and catStr:find("EndedScreen", 1, true)) then
            local nowc = os.clock()
            if nowc - (S._EndedScreenDebounce or 0) > 1.2 then
                S._EndedScreenDebounce = nowc
                if S.RoundWallStart then
                    GlobalSession.TotalTime = GlobalSession.TotalTime + math.floor(os.time() - S.RoundWallStart)
                end
                GlobalSession.CurrentRound = GlobalSession.CurrentRound + 1
                S.RoundWallStart = nil
                if UpdateSessionUI then pcall(UpdateSessionUI) end
                SendWebhook()
            end
            return
        end
        if cat == "Rewards - Items" then
            AccumulateRewards(data)
        end
    end)
end

-- Rundenzeit: Startzeit wenn Lobby → Spiel
task.spawn(function()
    local wasLobby = IsInLobby()
    if not wasLobby then S.RoundWallStart = os.time() end
    while S.Running do
        task.wait(0.45)
        local lobby = IsInLobby()
        if wasLobby and not lobby then S.RoundWallStart = os.time() end
        wasLobby = lobby
    end
end)
ScreenGui.AncestryChanged:Connect(function() if not ScreenGui.Parent then S.WhEnabled=false end end)
ScreenGui.DescendantAdded:Connect(function(ch)
    task.defer(function() ApplySharpTypography(ch) end)
end)
task.defer(function()
    pcall(function() for _, ch in ipairs(ScreenGui:GetDescendants()) do ApplySharpTypography(ch) end end)
end)

-- ── HazeShared vollständig befüllen ──────────────────────────
_G.HazeShared.Config             = H.Config
_G.HazeShared.State              = S
_G.HazeShared.PR                 = PR
_G.HazeShared.FireCreateAndStart = FireCreateAndStart
_G.HazeShared.FireVoteRetry      = FireVoteRetry
_G.HazeShared.GetInvAmt          = GetInvAmt
_G.HazeShared.IsInLobby          = IsInLobby
_G.HazeShared.TeleportToLobby    = TeleportToLobby
_G.HazeShared.SaveConfig         = SaveConfig
_G.HazeShared.SaveSettings       = SaveSettings
_G.HazeShared.SaveWorldCache     = SaveWorldData
_G.HazeShared.GetSettingsFilePath = GetSettingsFilePath
_G.HazeShared.GetAutoSaveFilePath = GetAutoSaveFilePath
_G.HazeShared.SendWebhook        = SendWebhook
_G.HazeShared.SessionData        = GlobalSession
_G.HazeShared.GlobalSession      = GlobalSession
_G.HazeShared.RecordSessionTrait = function(name)
    if not name or name == "" then return end
    local k = "Trait · " .. tostring(name):sub(1, 120)
    GlobalSession.AllRewards[k] = (GlobalSession.AllRewards[k] or 0) + 1
    if UpdateSessionUI then pcall(UpdateSessionUI) end
end
_G.HazeShared.UpdateSessionUI    = function() if UpdateSessionUI then pcall(UpdateSessionUI) end end
_G.HazeShared.UpdateGoalsUI      = function() if UpdateGoalsUI   then pcall(UpdateGoalsUI)   end end
_G.HazeShared.GetWorldData       = function() return S.WorldData end
_G.HazeShared.GetWorldIds        = function() return S.WorldIds  end
_G.HazeShared.IsScanDone         = function() return S.ScanDone  end
_G.HazeShared.D                  = D
_G.HazeShared.HAZE_ASSETS        = HAZE_ASSETS
_G.HazeShared.BuildMoonLogo      = BuildMoonLogo
_G.HazeShared.TF=TF; _G.HazeShared.TM=TM; _G.HazeShared.Tw=Tw
_G.HazeShared.Svc                = Svc
_G.HazeShared.LoadItemViewport   = LoadItemViewport
_G.HazeShared.GetItemTextureId   = GetItemTextureId
_G.HazeShared.BuildItemPreview   = BuildItemPreview
_G.HazeShared.Card=Card; _G.HazeShared.NeonBtn=NeonBtn
_G.HazeShared.MkLbl=MkLbl; _G.HazeShared.SecLbl=SecLbl
_G.HazeShared.MkInput=MkInput; _G.HazeShared.VList=VList
_G.HazeShared.HList=HList; _G.HazeShared.Pad=Pad
_G.HazeShared.Corner=Corner; _G.HazeShared.Stroke=Stroke
_G.HazeShared.FmtNum=FmtNum
_G.HazeShared.ApplySharpTypography=ApplySharpTypography
_G.HazeShared.StopFarm=nil; _G.HazeShared.StartFarmFromMain=nil; _G.HazeShared.TriggerResetRescan=nil
_G.HazeShared.ShopContainer = ShopPage
_G.HazeShared.CraftPage     = CraftPage
_G.HazeShared.TraitPage     = TraitPage

_G.HazeShared.OnDBReady=function(chapCount,msg)
    pcall(function() S.DBReady=true end) -- Database confirmation removed - status now in header end)
end
_G.HazeShared.SetModuleLoaded=function(version)
    pcall(function()
        _G.HazeShared.Version=version or "1.0.0"; _G.HazeShared.Status="Geladen"
        if H.UI.Lbl.ModulStatus then
            local hasDb = false
            if _G.HazeShared and type(_G.HazeShared._AutoFarm_RewardDB) == "table" then
                hasDb = next(_G.HazeShared._AutoFarm_RewardDB) ~= nil
            end
            H.UI.Lbl.ModulStatus.Text = string.format("🟢  Autofarm-Modul v%s [Datenbank: %s]", _G.HazeShared.Version, hasDb and "GELADEN" or "FEHLT")
            H.UI.Lbl.ModulStatus.TextColor3 = hasDb and D.GreenBright or D.Orange
        end
    end)
end

-- ── Startup ───────────────────────────────────────────────────
LoadConfig(); LoadSettings()
if not H.Config.ToggleKey   then H.Config.ToggleKey  = "F4"   end
if H.Config.AutoRetry==nil  then H.Config.AutoRetry  = false  end
if not H.Config.WebhookURL  then H.Config.WebhookURL = ""     end
if not H.Config.UISize      then H.Config.UISize     = "PC"   end
if H.Config.AutoFarm==nil   then H.Config.AutoFarm   = false  end
if H.Config.GuiVisible==nil then H.Config.GuiVisible = true   end
S.GuiVisible=H.Config.GuiVisible==true
MainFrame.Visible=S.GuiVisible
pcall(function() if HazeHubBlur and HazeHubBlur.Parent then HazeHubBlur.Enabled=S.GuiVisible end end)
if _earlyAutoFarm then H.Config.AutoFarm=true end
if _G._SetKeyDisplay        then _G._SetKeyDisplay(H.Config.ToggleKey) end
if _G and _G._UpdateAutoRetryUI    then _G._UpdateAutoRetryUI() end
-- Auto-Mobile-Detection: TouchEnabled uebersteigt gespeicherte UISize-Einstellung
local _startupMode = H.Config.UISize
if Svc.Input.TouchEnabled then _startupMode = "Mobile" end
SetGUISize(_startupMode)
if H.UI.Inp.Webhook then H.UI.Inp.Webhook.Text=H.Config.WebhookURL end
SelectTab("Game")
if UpdateSessionUI then pcall(UpdateSessionUI) end
if UpdateGoalsUI   then pcall(UpdateGoalsUI)   end

-- ★ Startup: nur Cache laden, KEIN auto-rescan
task.spawn(function()
    local cacheLoaded = false
    if LoadWorldCache and type(LoadWorldCache) == "function" then
        cacheLoaded = LoadWorldCache()
    else
        warn("[HazeHUB] LoadWorldCache Funktion nicht gefunden!")
    end
    
    if cacheLoaded then
        pcall(function() if H.UI.Lbl.ScanStatus then H.UI.Lbl.ScanStatus.Text="✅ "..#S.WorldIds.." Welten (Cache)"; H.UI.Lbl.ScanStatus.TextColor3=D.Cyan end end)
        if RebuildWorldList and type(RebuildWorldList) == "function" then
            pcall(RebuildWorldList)
        else
            warn("[HazeHUB] RebuildWorldList Funktion nicht gefunden!")
        end
    else
        -- Versuche einmalig live zu lesen ohne zu scannen
        local f=GetChapterFolder()
        if f then
            ScanChapterFolder(f)
            pcall(function() if H.UI.Lbl.ScanStatus then H.UI.Lbl.ScanStatus.Text="✅ "..#S.WorldIds.." Welten"; H.UI.Lbl.ScanStatus.TextColor3=D.Green end end)
        else
            ApplyFallback()
            pcall(function() if H.UI.Lbl.ScanStatus then H.UI.Lbl.ScanStatus.Text="⚠ Fallback-Daten"; H.UI.Lbl.ScanStatus.TextColor3=D.Orange end end)
        end
    end
    if RebuildWorldList and type(RebuildWorldList) == "function" then
        pcall(RebuildWorldList)
    else
        warn("[HazeHUB] RebuildWorldList Funktion nicht gefunden!")
    end
end)

task.delay(8,function()
    pcall(function()
        local hasDb = false
        if _G.HazeShared and type(_G.HazeShared._AutoFarm_RewardDB) == "table" then
            hasDb = next(_G.HazeShared._AutoFarm_RewardDB) ~= nil
        end
        if _G.HazeHUB_Database and type(_G.HazeHUB_Database) == "table" then
            hasDb = hasDb or (next(_G.HazeHUB_Database) ~= nil)
        end
        if H.UI.Lbl.ModulStatus and (not S.DBReady or not hasDb) then
            local ver = (_G.HazeShared and _G.HazeShared.Version) or "?"
            H.UI.Lbl.ModulStatus.Text = string.format("🟠  Autofarm-Modul v%s [Datenbank: FEHLT]", ver)
            H.UI.Lbl.ModulStatus.TextColor3 = D.Orange
        end
    end)
end)

-- ╔══════════════════════════════════════════════════════════╗
--  MODULE LADEN (pcall-geschützt)
-- ╚══════════════════════════════════════════════════════════╝
local function LoadModule(url,name,delay,onErr)
    task.spawn(function()
        task.wait(delay or 1)
        
        -- Warte bis das Hauptskript vollständig geladen ist
        repeat task.wait(0.5) until _G.HazeHUB_Ready == true
        
        -- Stelle sicher, dass alle globalen Funktionen und Variablen verfügbar sind
        if not _G.HazeHubFunctions then
            _G.HazeHubFunctions = {}
        end
        
        -- Fülle ALLE möglichen Funktionen mit _G.HazeHUB Referenzen auf
        local fallbackFunctions = {
            ToggleAntiAFK = _G.HazeHUB.ToggleAntiAFK or function() warn("[HazeHUB] ToggleAntiAFK nicht implementiert") end,
            StartRaid = _G.HazeHUB.StartRaid or function() warn("[HazeHUB] StartRaid nicht implementiert") end,
            StopRaid = _G.HazeHUB.StopRaid or function() warn("[HazeHUB] StopRaid nicht implementiert") end,
            SetGoalFromInventory = _G.HazeHUB.SetGoalFromInventory or function() warn("[HazeHUB] SetGoalFromInventory nicht implementiert") end,
            SetKeyDisplay = _G.HazeHUB.SetKeyDisplay or function() warn("[HazeHUB] SetKeyDisplay nicht implementiert") end,
            UpdateAutoRetryUI = _G.HazeHUB.UpdateAutoRetryUI or function() warn("[HazeHUB] UpdateAutoRetryUI nicht implementiert") end,
            UpdateGoalsUI = _G.HazeHUB.UpdateGoalsUI or function() warn("[HazeHUB] UpdateGoalsUI nicht implementiert") end,
            UpdateSessionUI = _G.HazeHUB.UpdateSessionUI or function() warn("[HazeHUB] UpdateSessionUI nicht implementiert") end,
            RebuildWorldList = _G.HazeHUB.RebuildWorldList or function() warn("[HazeHUB] RebuildWorldList nicht implementiert") end,
            LoadWorldCache = _G.HazeHUB.LoadWorldCache or function() warn("[HazeHUB] LoadWorldCache nicht implementiert") end,
            SaveWorldData = _G.HazeHUB.SaveWorldData or function() warn("[HazeHUB] SaveWorldData nicht implementiert") end,
            SendWebhook = _G.HazeHUB.SendWebhook or function() warn("[HazeHUB] SendWebhook nicht implementiert") end,
            AccumulateRewards = _G.HazeHUB.AccumulateRewards or function() warn("[HazeHUB] AccumulateRewards nicht implementiert") end,
            RefreshPlayerStats = _G.HazeHUB.RefreshPlayerStats or function() warn("[HazeHUB] RefreshPlayerStats nicht implementiert") end,
            SelectTab = _G.HazeHUB.SelectTab or function() warn("[HazeHUB] SelectTab nicht implementiert") end,
            OnMiniBtnClick = _G.HazeHUB.OnMiniBtnClick or function() warn("[HazeHUB] OnMiniBtnClick nicht implementiert") end,
            ToggleHubGui = _G.HazeHUB.ToggleHubGui or function() warn("[HazeHUB] ToggleHubGui nicht implementiert") end,
            BuildItemPreview = _G.HazeHUB.BuildItemPreview or function() warn("[HazeHUB] BuildItemPreview nicht implementiert") end,
            LoadItemViewport = _G.HazeHUB.LoadItemViewport or function() warn("[HazeHUB] LoadItemViewport nicht implementiert") end,
            GetItemTextureId = _G.HazeHUB.GetItemTextureId or function() warn("[HazeHUB] GetItemTextureId nicht implementiert") end,
            ApplySharpTypography = _G.HazeHUB.ApplySharpTypography or function() warn("[HazeHUB] ApplySharpTypography nicht implementiert") end,
            FireCreateAndStart = _G.HazeHUB.FireCreateAndStart or function() warn("[HazeHUB] FireCreateAndStart nicht implementiert") end,
            FireVoteRetry = _G.HazeHUB.FireVoteRetry or function() warn("[HazeHUB] FireVoteRetry nicht implementiert") end,
            TeleportToLobby = _G.HazeHUB.TeleportToLobby or function() warn("[HazeHUB] TeleportToLobby nicht implementiert") end,
            IsInLobby = _G.HazeHUB.IsInLobby or function() warn("[HazeHUB] IsInLobby nicht implementiert") end,
            SaveConfig = _G.HazeHUB.SaveConfig or function() warn("[HazeHUB] SaveConfig nicht implementiert") end,
            LoadConfig = _G.HazeHUB.LoadConfig or function() warn("[HazeHUB] LoadConfig nicht implementiert") end,
            SaveSettings = _G.HazeHUB.SaveSettings or function() warn("[HazeHUB] SaveSettings nicht implementiert") end,
            LoadSettings = _G.HazeHUB.LoadSettings or function() warn("[HazeHUB] LoadSettings nicht implementiert") end,
            GetSettingsFilePath = _G.HazeHUB.GetSettingsFilePath or function() warn("[HazeHUB] GetSettingsFilePath nicht implementiert") end,
            GetAutoSaveFilePath = _G.HazeHUB.GetAutoSaveFilePath or function() warn("[HazeHUB] GetAutoSaveFilePath nicht implementiert") end,
            GetInvAmt = _G.HazeHUB.GetInvAmt or function() warn("[HazeHUB] GetInvAmt nicht implementiert") end,
            FmtDur = _G.HazeHUB.FmtDur or function() warn("[HazeHUB] FmtDur nicht implementiert") end,
            FmtNum = _G.HazeHUB.FmtNum or function() warn("[HazeHUB] FmtNum nicht implementiert") end,
            formatTime = _G.HazeHUB.formatTime or function() warn("[HazeHUB] formatTime nicht implementiert") end,
            Tw = _G.HazeHUB.Tw or function() warn("[HazeHUB] Tw nicht implementiert") end,
            Corner = _G.HazeHUB.Corner or function() warn("[HazeHUB] Corner nicht implementiert") end,
            Stroke = _G.HazeHUB.Stroke or function() warn("[HazeHUB] Stroke nicht implementiert") end,
            Pad = _G.HazeHUB.Pad or function() warn("[HazeHUB] Pad nicht implementiert") end,
            VList = _G.HazeHUB.VList or function() warn("[HazeHUB] VList nicht implementiert") end,
            HList = _G.HazeHUB.HList or function() warn("[HazeHUB] HList nicht implementiert") end,
            MkLbl = _G.HazeHUB.MkLbl or function() warn("[HazeHUB] MkLbl nicht implementiert") end,
            SecLbl = _G.HazeHUB.SecLbl or function() warn("[HazeHUB] SecLbl nicht implementiert") end,
            MkInput = _G.HazeHUB.MkInput or function() warn("[HazeHUB] MkInput nicht implementiert") end,
            Card = _G.HazeHUB.Card or function() warn("[HazeHUB] Card nicht implementiert") end,
            NeonBtn = _G.HazeHUB.NeonBtn or function() warn("[HazeHUB] NeonBtn nicht implementiert") end,
            StartAutofarm = _G.HazeHUB.StartAutofarm or function() warn("[HazeHUB] StartAutofarm nicht implementiert") end,
            StopAutofarm = _G.HazeHUB.StopAutofarm or function() warn("[HazeHUB] StopAutofarm nicht implementiert") end,
            UpdateStatus = _G.HazeHUB.UpdateStatus or function() warn("[HazeHUB] UpdateStatus nicht implementiert") end
        }
        
        -- Registriere alle Fallback-Funktionen
        for funcName, funcImpl in pairs(fallbackFunctions) do
            if not _G.HazeHubFunctions[funcName] then
                _G.HazeHubFunctions[funcName] = funcImpl
            end
        end
        
        -- Stelle sicher, dass _G.HazeShared auch verfügbar ist
        if not _G.HazeShared then
            _G.HazeShared = {}
        end
        
        -- Fülle kritische _G.HazeShared Funktionen
        if not _G.HazeShared.SetModuleLoaded then
            _G.HazeShared.SetModuleLoaded = function(version) 
                warn("[HazeHUB] SetModuleLoaded nicht implementiert") 
            end
        end
        
        if not _G.HazeShared.OnDBReady then
            _G.HazeShared.OnDBReady = function() 
                warn("[HazeHUB] OnDBReady nicht implementiert") 
            end
        end
        
        -- Stelle sicher, dass globale UI-Referenzen existieren
        if not H then H = {} end
        if not H.UI then H.UI = {} end
        if not H.Config then H.Config = {} end
        if not S then S = {} end
        
        local httpOk,raw=pcall(function() return game:HttpGet(url) end)
        if not httpOk or not raw or #raw<20 then
            warn("[HazeHUB] "..name..": HttpGet fehlgeschlagen")
            if onErr then pcall(onErr,"HttpGet fehlgeschlagen") end; return
        end
        
        -- Fange loadstring Fehler ab und gib detaillierte Informationen
        local execOk,execErr=pcall(function() 
            -- Erstelle eine sichere Umgebung für das Modul
            local success, modResult = pcall(function() 
                return loadstring(raw)() 
            end)
            if not success then
                error("Modul-Ausführungsfehler: " .. tostring(modResult))
            end
            return modResult
        end)
        
        if not execOk then
            warn("[HazeHUB] "..name.." Fehler: "..tostring(execErr):sub(1,120))
            if onErr then pcall(onErr,tostring(execErr):sub(1,60)) end
        else 
            print("[HazeHUB] Modul '"..name.."' geladen.") 
        end
    end)
end

LoadModule(K.AF_URL,   "Autofarm",  1)
LoadModule(K.SHOP_URL, "Shops",     2)
LoadModule(K.CRAFT_URL,"Crafting",  3, function(err)
    pcall(function()
        if _G._CraftWaitLbl then _G._CraftWaitLbl.Text="❌ Craft-Fehler: "..err; _G._CraftWaitLbl.TextColor3=D.Red end
    end)
end)
LoadModule(K.TRAIT_URL,"Traits",    4, function(err)
    pcall(function()
        if _G._TraitWaitLbl then _G._TraitWaitLbl.Text="❌ Trait-Fehler: "..err; _G._TraitWaitLbl.TextColor3=D.Red end
    end)
end)
task.delay(6,function()
    pcall(function() for _, ch in ipairs(ScreenGui:GetDescendants()) do ApplySharpTypography(ch) end end)
end)
-- NACH: LoadModule(K.TRAIT_URL, "Traits", 4, ...)
LoadModule(K.TEAMS_URL, "Teams", 5, function(err)
    pcall(function()
        if _G._TeamsWaitLbl then
            _G._TeamsWaitLbl.Text = "❌ Teams-Fehler: " .. err
            _G._TeamsWaitLbl.TextColor3 = D.Red
        end
    end)
end)

-- === WELT-DATEN BEIM START LADEN ===
task.spawn(function()
    -- Versuche gespeicherte Welten-Daten zu laden
    if _G.HazeHUB.LoadWorlds and type(_G.HazeHUB.LoadWorlds) == "function" then
        local loaded = pcall(_G.HazeHUB.LoadWorlds)
        if loaded then
            print("[HazeHUB] Gespeicherte Welten-Daten erfolgreich geladen")
        else
            print("[HazeHUB] Keine gespeicherten Welten-Daten gefunden - starte Scan")
            -- Wenn keine gespeicherten Daten existieren, starte normalen Scan
            task.spawn(function()
                task.wait(2) -- Kurze Verzögerung für UI-Initialisierung
                if LoadWorldCache then
                    pcall(LoadWorldCache)
                    -- Speichere die gescannten Daten für zukünftige Starts
                    pcall(_G.HazeHUB.SaveWorlds)
                end
            end)
        end
    end
end)

-- === HAUPTSKRIPT GELADEN - MODULE KÖNNEN STARTEN ===
_G.HazeHUB_Loaded = true
_G.HazeHUB_Ready = true
print("[HazeHUB] Hauptskript vollständig geladen - Module können jetzt starten")
