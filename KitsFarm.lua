-- Luau | KitsFarm.lua | Roblox executor (firetouchinterest, gethui) | Murder Mystery 2 autofarm hub
-- RightShift = menu
local Players, RS, UIS, TS, Lighting = game:GetService("Players"), game:GetService("RunService"),
    game:GetService("UserInputService"), game:GetService("TweenService"), game:GetService("Lighting")
local LP, Camera = Players.LocalPlayer, workspace.CurrentCamera
local alive, conns = true, {}
local function bind(sig, fn) local c = sig:Connect(fn); conns[#conns + 1] = c; return c end

local ACC = Color3.fromRGB(90, 200, 160)      -- KitsFarm teal/green brand accent
local ACC_DIM = Color3.fromRGB(50, 110, 92)
local ROLE = {Murderer = Color3.fromRGB(255, 60, 60), Sheriff = Color3.fromRGB(70, 140, 255), Innocent = Color3.fromRGB(80, 230, 120)}
local FARM_START_RANGE = 450
local FARM_SPEED_CAP = 34
local FARM_HIP = 3
local S = {esp = true, farm = false, farmspeed = 28, bagcap = 50, flingafter = true, autogun = false,
           speed = false, speedval = 32, noclip = false}

local busy, killing = false, false
local cur_cont, blocked_cont, collected, farm_session, fling_running = nil, nil, 0, false, false
local seen = {}
local role_data = {}
local dbg_labels, bag_labels = {}, {}

local function dbg(t) for _, l in ipairs(dbg_labels) do l.Text = "status: " .. t end end
local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o, r) mk("UICorner", {CornerRadius = UDim.new(0, r or 10)}, o) end

-- ===== core helpers =====
local function get_char(plr)
    local c = plr.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if h and r and h.Health > 0 then return c, h, r end
end
local function real_root() return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") end
local function tool_of(plr, n)
    local c, bp = plr.Character, plr:FindFirstChild("Backpack")
    return (c and c:FindFirstChild(n)) or (bp and bp:FindFirstChild(n))
end

-- role data (handles role-held-out-only visibility for other players)
local function norm_role(s)
    s = tostring(s or ""):lower()
    if s == "murderer" then return "Murderer" end
    if s == "sheriff" or s == "hero" then return "Sheriff" end
    return "Innocent"
end
local function ingest(data)
    if type(data) ~= "table" then return end
    for name, info in pairs(data) do
        if type(info) == "table" and info.Role ~= nil then
            role_data[tostring(name)] = norm_role(info.Role)
        end
    end
end
task.spawn(function()
    local RepStorage = game:GetService("ReplicatedStorage")
    local ev = RepStorage:FindFirstChild("PlayerDataChanged", true)
    if ev and ev:IsA("RemoteEvent") then bind(ev.OnClientEvent, ingest) end
    while alive do
        local rf = RepStorage:FindFirstChild("GetPlayerData", true)
        if rf and rf:IsA("RemoteFunction") then pcall(function() ingest(rf:InvokeServer()) end) end
        task.wait(2)
    end
end)
local function role(plr)
    if tool_of(plr, "Knife") then return "Murderer" end
    if tool_of(plr, "Gun") then return "Sheriff" end
    return role_data[plr.Name] or "Innocent"
end
local function find_role(r)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and role(p) == r and get_char(p) then return p end
    end
end
local function find_gundrop()
    local gd = workspace:FindFirstChild("GunDrop", true)
    return gd and gd:IsA("BasePart") and gd or nil
end
local function find_cont()
    for _, m in ipairs(workspace:GetChildren()) do
        local c = m:FindFirstChild("CoinContainer")
        if c then return c end
    end
end
local function coin_part(c)
    if c:IsA("BasePart") then return c end
    if c:IsA("Model") then return c.PrimaryPart or c:FindFirstChildWhichIsA("BasePart", true) end
end

-- real body briefly goes to cf, runs fn, returns
local function with_real(cf, fn)
    local r = real_root()
    if busy or not r then return false end
    busy = true
    local back = r.CFrame
    r.CFrame = cf
    r.AssemblyLinearVelocity = Vector3.zero
    task.wait(LP:GetNetworkPing() + 0.06)
    local ok = pcall(fn)
    r = real_root()
    if r then
        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero
        r.CFrame = back
    end
    busy = false
    return ok
end
local function grab_gun()
    local gd = find_gundrop()
    if not gd then return end
    with_real(gd.CFrame, function()
        local r = real_root()
        if firetouchinterest then firetouchinterest(r, gd, 0); firetouchinterest(r, gd, 1) end
        task.wait(0.2)
    end)
end

-- fling (used only to speed up a round once the bag is full)
local function fling_player(plr)
    local _, th, tr = get_char(plr)
    if not tr then return false end
    local start = tr.Position
    local flung = false
    local old_h = workspace.FallenPartsDestroyHeight
    with_real(tr.CFrame, function()
        local lc, r = LP.Character, real_root()
        if not (lc and r) then return end
        local saved = {}
        for _, p in ipairs(lc:GetDescendants()) do
            if p:IsA("BasePart") then
                saved[p] = p.CustomPhysicalProperties
                p.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5, 1, 1)
            end
        end
        pcall(function() workspace.FallenPartsDestroyHeight = 0 / 0 end)
        Camera.CameraSubject = th
        local t0, angle = os.clock(), 0
        pcall(function()
            while alive and os.clock() - t0 < 2.6 do
                local _, th2, t = get_char(plr)
                if not t then flung = true; break end
                if t.AssemblyLinearVelocity.Magnitude > 300 or (t.Position - start).Magnitude > 140 then flung = true; break end
                angle += 100
                local lead = th2.MoveDirection * math.clamp(t.AssemblyLinearVelocity.Magnitude / 1.25, 0, 12)
                local yoff = (math.floor(angle / 100) % 2 == 0) and 1.5 or -1.5
                r.CFrame = CFrame.new(t.Position + lead + Vector3.new(0, yoff, 0)) * CFrame.Angles(math.rad(angle), 0, 0)
                r.AssemblyLinearVelocity = Vector3.new(9e7, 9e8, 9e7)
                r.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
                RS.Heartbeat:Wait()
            end
        end)
        for p, v in pairs(saved) do if p.Parent then p.CustomPhysicalProperties = v end end
        pcall(function() workspace.FallenPartsDestroyHeight = old_h end)
        local hum = lc:FindFirstChildOfClass("Humanoid")
        if hum then Camera.CameraSubject = hum end
    end)
    return flung
end

-- ===== character hooks =====
bind(LP.CharacterAdded, function() farm_session = false end)

-- ===== UI =====
local gui = mk("ScreenGui", {Name = "KitsFarm", ResetOnSpawn = false}, (gethui and gethui()) or game:GetService("CoreGui"))
local main = mk("Frame", {Size = UDim2.fromOffset(480, 320), Position = UDim2.new(0.5, -240, 0.5, -160),
    BackgroundColor3 = Color3.fromRGB(14, 16, 18), BorderSizePixel = 0}, gui)
corner(main, 14)
mk("UIStroke", {Color = Color3.fromRGB(40, 55, 50), Thickness = 1}, main)

local header = mk("Frame", {Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Color3.fromRGB(20, 24, 22), BorderSizePixel = 0}, main)
corner(header, 14)
mk("Frame", {Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), BackgroundColor3 = Color3.fromRGB(20, 24, 22), BorderSizePixel = 0}, header)
local logo = mk("Frame", {Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(12, 9), BackgroundColor3 = ACC}, header)
corner(logo, 8)
mk("TextLabel", {Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Text = "K", Font = Enum.Font.GothamBlack,
    TextSize = 15, TextColor3 = Color3.fromRGB(10, 14, 12)}, logo)
mk("TextLabel", {Size = UDim2.new(1, -140, 1, 0), Position = UDim2.fromOffset(46, 0), BackgroundTransparency = 1,
    Text = "KitsFarm", Font = Enum.Font.GothamBlack, TextSize = 17, TextColor3 = Color3.new(1, 1, 1),
    TextXAlignment = Enum.TextXAlignment.Left}, header)
mk("TextLabel", {Size = UDim2.fromOffset(90, 16), Position = UDim2.fromOffset(46, 24), BackgroundTransparency = 1,
    Text = "MM2 autofarm", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Color3.fromRGB(140, 150, 146),
    TextXAlignment = Enum.TextXAlignment.Left}, header)

local min_btn = mk("TextButton", {Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -40, 0, 8),
    BackgroundColor3 = Color3.fromRGB(30, 34, 32), Text = "—", Font = Enum.Font.GothamBold, TextSize = 14,
    TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = false}, header)
corner(min_btn, 8)

do -- drag
    local dragging, start, origin
    bind(header.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, start, origin = true, i.Position, main.Position
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - start
            main.Position = UDim2.new(origin.X.Scale, origin.X.Offset + d.X, origin.Y.Scale, origin.Y.Offset + d.Y)
        end
    end)
    bind(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local sidebar = mk("Frame", {Size = UDim2.new(0, 112, 1, -56), Position = UDim2.fromOffset(8, 48), BackgroundTransparency = 1}, main)
mk("UIListLayout", {Padding = UDim.new(0, 6)}, sidebar)
local content = mk("Frame", {Size = UDim2.new(1, -136, 1, -56), Position = UDim2.fromOffset(128, 48), BackgroundTransparency = 1}, main)
local pages, tabs = {}, {}
local function select_tab(n)
    for k, p in pairs(pages) do p.Visible = (k == n) end
    for k, b in pairs(tabs) do
        TS:Create(b, TweenInfo.new(0.15), {BackgroundColor3 = (k == n) and ACC or Color3.fromRGB(24, 28, 26),
            TextColor3 = (k == n) and Color3.fromRGB(10, 14, 12) or Color3.fromRGB(190, 195, 192)}):Play()
    end
end
local function new_tab(n)
    local b = mk("TextButton", {Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(24, 28, 26), Text = n,
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Color3.fromRGB(190, 195, 192), AutoButtonColor = false}, sidebar)
    corner(b, 8)
    local p = mk("ScrollingFrame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = ACC, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false}, content)
    mk("UIListLayout", {Padding = UDim.new(0, 6)}, p)
    pages[n], tabs[n] = p, b
    bind(b.MouseButton1Click, function() select_tab(n) end)
    return p
end
local function label(p, t)
    return mk("TextLabel", {Size = UDim2.new(1, -8, 0, 20), BackgroundTransparency = 1, Text = string.upper(t),
        Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = ACC, TextXAlignment = Enum.TextXAlignment.Left}, p)
end
local function stat_card(p, title)
    local f = mk("Frame", {Size = UDim2.new(1, -8, 0, 54), BackgroundColor3 = Color3.fromRGB(22, 26, 24)}, p)
    corner(f, 10)
    mk("UIStroke", {Color = Color3.fromRGB(36, 48, 44), Thickness = 1}, f)
    mk("TextLabel", {Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 6), BackgroundTransparency = 1,
        Text = title, Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = Color3.fromRGB(140, 150, 146),
        TextXAlignment = Enum.TextXAlignment.Left}, f)
    local val = mk("TextLabel", {Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(10, 22), BackgroundTransparency = 1,
        Text = "—", Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Left}, f)
    return val
end
local function toggle(p, t, def, cb)
    local f = mk("Frame", {Size = UDim2.new(1, -8, 0, 36), BackgroundColor3 = Color3.fromRGB(22, 26, 24)}, p)
    corner(f, 9)
    mk("TextLabel", {Size = UDim2.new(1, -62, 1, 0), Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1, Text = t,
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(225, 228, 226), TextXAlignment = Enum.TextXAlignment.Left}, f)
    local pill = mk("Frame", {Size = UDim2.fromOffset(38, 20), Position = UDim2.new(1, -50, 0.5, -10), BackgroundColor3 = Color3.fromRGB(44, 48, 46)}, f)
    corner(pill, 10)
    local knob = mk("Frame", {Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(2, 2), BackgroundColor3 = Color3.new(1, 1, 1)}, pill)
    corner(knob, 8)
    local st = def
    local function paint()
        TS:Create(pill, TweenInfo.new(0.15), {BackgroundColor3 = st and ACC or Color3.fromRGB(44, 48, 46)}):Play()
        TS:Create(knob, TweenInfo.new(0.15), {Position = st and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)}):Play()
    end
    paint()
    local b = mk("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = ""}, f)
    bind(b.MouseButton1Click, function() st = not st; paint(); cb(st) end)
end
local function slider(p, t, min, max, def, cb)
    local f = mk("Frame", {Size = UDim2.new(1, -8, 0, 48), BackgroundColor3 = Color3.fromRGB(22, 26, 24)}, p)
    corner(f, 9)
    local l = mk("TextLabel", {Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(12, 4), BackgroundTransparency = 1,
        Text = t .. ":  " .. def, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(225, 228, 226),
        TextXAlignment = Enum.TextXAlignment.Left}, f)
    local bar = mk("Frame", {Size = UDim2.new(1, -24, 0, 6), Position = UDim2.new(0, 12, 0, 33), BackgroundColor3 = Color3.fromRGB(44, 48, 46)}, f)
    corner(bar, 3)
    local fill = mk("Frame", {Size = UDim2.fromScale((def - min) / (max - min), 1), BackgroundColor3 = ACC}, bar)
    corner(fill, 3)
    local down = false
    local function set(x)
        local a = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local v = math.floor(min + (max - min) * a + 0.5)
        fill.Size = UDim2.fromScale(a, 1); l.Text = t .. ":  " .. v; cb(v)
    end
    bind(bar.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then down = true; set(i.Position.X) end
    end)
    bind(UIS.InputChanged, function(i)
        if down and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then set(i.Position.X) end
    end)
    bind(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then down = false end
    end)
end
local function button(p, t, cb)
    local b = mk("TextButton", {Size = UDim2.new(1, -8, 0, 34), BackgroundColor3 = ACC_DIM, Text = t,
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Color3.new(1, 1, 1)}, p)
    corner(b, 9)
    bind(b.MouseButton1Click, cb)
    return b
end

-- Main tab
local t_main = new_tab("Main")
local statrow = mk("Frame", {Size = UDim2.new(1, -8, 0, 54), BackgroundTransparency = 1}, t_main)
mk("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6)}, statrow)
local bag_val = stat_card(statrow, "BAG"); bag_val.Parent.Size = UDim2.new(0.5, -3, 1, 0); bag_labels[#bag_labels + 1] = bag_val
local role_val = stat_card(statrow, "YOUR ROLE"); role_val.Parent.Size = UDim2.new(0.5, -3, 1, 0)
local dbg_lbl = label(t_main, "status: idle"); dbg_labels[#dbg_labels + 1] = dbg_lbl
label(t_main, "Autofarm")
toggle(t_main, "Enable autofarm", false, function(v) S.farm = v; farm_session = false end)
slider(t_main, "Speed (studs/s, cap 34)", 10, FARM_SPEED_CAP, 28, function(v) S.farmspeed = v end)
slider(t_main, "Stop after N collected", 5, 100, 50, function(v) S.bagcap = v end)
toggle(t_main, "Fling murderer when bag is full", true, function(v) S.flingafter = v end)
label(t_main, "Gun")
toggle(t_main, "Auto grab dropped gun", false, function(v) S.autogun = v end)
button(t_main, "Grab gun now", function() task.spawn(grab_gun) end)

-- Visuals tab
local t_vis = new_tab("Visuals")
toggle(t_vis, "Role ESP (red murd / blue sheriff / green)", true, function(v) S.esp = v end)
local gun_toggle_state = true
toggle(t_vis, "Gun drop highlight", true, function(v) gun_toggle_state = v end)
local lb = {Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
    GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient}
local function fullbright(on)
    if on then
        Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows = 2, 14, 1e6, false
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
    else for k, v in pairs(lb) do Lighting[k] = v end end
end
toggle(t_vis, "Fullbright", false, fullbright)

-- Player tab
local t_pl = new_tab("Player")
toggle(t_pl, "Speed boost", false, function(v)
    S.speed = v
    local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if h and not v then h.WalkSpeed = 16 end
end)
slider(t_pl, "Speed value", 16, 120, 32, function(v) S.speedval = v end)
toggle(t_pl, "Noclip (also on automatically while farming)", false, function(v) S.noclip = v end)
button(t_pl, "Unload KitsFarm", function()
    alive = false
    for _, c in ipairs(conns) do c:Disconnect() end
    fullbright(false)
    gui:Destroy()
end)

select_tab("Main")

local minimized = false
bind(min_btn.MouseButton1Click, function()
    minimized = not minimized
    if minimized then
        min_btn.Text = "▢"
        TS:Create(main, TweenInfo.new(0.2), {Size = UDim2.fromOffset(480, 48)}):Play()
        sidebar.Visible, content.Visible = false, false
    else
        min_btn.Text = "—"
        sidebar.Visible, content.Visible = true, true
        TS:Create(main, TweenInfo.new(0.2), {Size = UDim2.fromOffset(480, 320)}):Play()
    end
end)

-- ===== ESP / status / bag display =====
local hl = {}
local gun_hl = mk("Highlight", {FillColor = Color3.fromRGB(255, 220, 60), OutlineColor = Color3.new(1, 1, 1), FillTransparency = 0.3,
    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false}, gui)
bind(Players.PlayerRemoving, function(p) if hl[p] then hl[p]:Destroy(); hl[p] = nil end end)
task.spawn(function()
    while alive do
        for _, p in ipairs(Players:GetPlayers()) do
            local r = role(p)
            if p ~= LP then
                local h = hl[p]
                if p.Character then
                    if not h or h.Parent ~= gui then
                        h = mk("Highlight", {FillTransparency = 0.45, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop}, gui)
                        hl[p] = h
                    end
                    h.Adornee, h.FillColor, h.OutlineColor, h.Enabled = p.Character, ROLE[r], ROLE[r], S.esp
                elseif h then h.Enabled = false end
            end
        end
        local gd = find_gundrop()
        gun_hl.Adornee, gun_hl.Enabled = gd, gun_toggle_state and gd ~= nil
        if not busy and S.autogun and gd and role(LP) == "Innocent" then task.spawn(grab_gun) end
        for _, v in ipairs(bag_labels) do v.Text = tostring(collected) .. " / " .. S.bagcap end
        role_val.Text = role(LP)
        role_val.TextColor3 = ROLE[role(LP)] or Color3.new(1, 1, 1)
        task.wait(0.25)
    end
end)

-- ===== autofarm =====
local function end_round(cont)
    dbg("bag full, flinging murderer")
    local tries = 0
    while alive and S.flingafter and cont == cur_cont and cont ~= blocked_cont and tries < 10 do
        local m = find_role("Murderer")
        if not m or role(LP) == "Murderer" then break end
        if not get_char(LP) then break end
        fling_player(m)
        tries += 1
        task.wait(1.2)
    end
end
local function farm_to(obj, part, cont)
    seen[obj] = os.clock()
    local speed = math.min(S.farmspeed, FARM_SPEED_CAP)
    local reached = false
    local best_d, t_prog = math.huge, os.clock()
    while alive and S.farm and not busy do
        local dt = math.min(RS.Heartbeat:Wait(), 0.05)
        local _, _, r = get_char(LP)
        if not r or not part.Parent or cont ~= cur_cont or cont == blocked_cont then break end
        local delta = part.Position + Vector3.new(0, FARM_HIP, 0) - r.Position
        local dist = delta.Magnitude
        if dist < 1.5 then reached = true; break end
        if dist < best_d - 0.5 then best_d, t_prog = dist, os.clock() end
        if os.clock() - t_prog > 1.2 then dbg("stuck, skipping"); break end
        local step = math.min(dist, speed * dt)
        r.CFrame = CFrame.new(r.Position + delta.Unit * step) * r.CFrame.Rotation
        r.AssemblyLinearVelocity, r.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    end
    if reached and part.Parent then
        local _, _, r = get_char(LP)
        if r and firetouchinterest then firetouchinterest(r, part, 0); firetouchinterest(r, part, 1) end
        local counted, conn = false, nil
        conn = obj.AncestryChanged:Connect(function(_, parent)
            if not parent and not counted then counted = true; collected += 1 end
        end)
        task.delay(3, function() if conn then conn:Disconnect() end end)
        task.wait(0.1)
    end
end
task.spawn(function()
    while alive do
        task.wait(0.1)
        local cont = find_cont()
        if cont ~= cur_cont then
            cur_cont, collected, blocked_cont = cont, 0, nil
            seen = {}
            if not cont then role_data = {} end
        end
        local _, hum, r = get_char(LP)
        local can = S.farm and cont ~= nil and cont ~= blocked_cont and not busy and hum ~= nil and r ~= nil
        local full = can and collected >= S.bagcap
        farm_session = can and not full
        dbg(not S.farm and "idle" or (not cont and "waiting for round" or (full and "bag full" or (farm_session and "farming" or "waiting"))))
        if not can then continue end
        if full then
            if S.flingafter and not fling_running then
                fling_running = true
                task.spawn(function() end_round(cont); fling_running = false end)
            end
            continue
        end
        local best_obj, best_part, bd
        for _, c in ipairs(cont:GetChildren()) do
            local p = coin_part(c)
            if p and not (seen[c] and os.clock() - seen[c] < 4) then
                local d = (p.Position - r.Position).Magnitude
                if not bd or d < bd then best_obj, best_part, bd = c, p, d end
            end
        end
        if best_obj and bd <= FARM_START_RANGE then farm_to(best_obj, best_part, cont) end
    end
end)

-- ===== death handling: stop farming for this round, never auto-teleport back =====
local function hook_char(c)
    local h = c:WaitForChild("Humanoid", 5)
    if not h then return end
    bind(h.Died, function()
        if cur_cont then blocked_cont = cur_cont end
        farm_session = false
    end)
end
if LP.Character then task.spawn(hook_char, LP.Character) end
bind(LP.CharacterAdded, hook_char)

-- ===== movement / noclip =====
bind(RS.Heartbeat, function()
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if hum and S.speed then hum.WalkSpeed = S.speedval end
end)
bind(RS.Stepped, function()
    if busy then return end
    local c = LP.Character
    if c and (S.noclip or farm_session) then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end
end)

bind(UIS.InputBegan, function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.RightShift then main.Visible = not main.Visible end
end)
