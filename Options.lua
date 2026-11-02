-- Pints Shield Arcs: options window (one page per arc) + minimap button.
local SA = _G.ShieldArcs
local floor = math.floor

---------------------------------------------------------------- widgets
local function Fmt(v, step) return step < 1 and ("%.2f"):format(v) or ("%d"):format(v) end

local function Slider(parent, x, y, w, spec)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 40); f:SetPoint("TOPLEFT", x, y)
  local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("TOPLEFT", 2, 0); label:SetText(spec.label)
  local val = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  val:SetPoint("TOPRIGHT", -2, 0)
  local s = CreateFrame("Slider", nil, f, "BackdropTemplate")
  s:SetOrientation("HORIZONTAL"); s:SetSize(w - 60, 16); s:SetPoint("TOPLEFT", 30, -16)
  s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  s:SetMinMaxValues(spec.min, spec.max); s:SetValueStep(spec.step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:EnableMouseWheel(true)
  s:SetScript("OnValueChanged", function(_, v)
    v = math.max(spec.min, math.min(spec.max, floor(v / spec.step + 0.5) * spec.step))
    val:SetText(Fmt(v, spec.step))
    if not f.lock then spec.set(v) end
  end)
  s:SetScript("OnMouseWheel", function(self, d) self:SetValue(self:GetValue() + d * spec.step) end)
  local minus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  minus:SetSize(22, 18); minus:SetPoint("RIGHT", s, "LEFT", -3, 0); minus:SetText("-")
  minus:SetScript("OnClick", function() s:SetValue(s:GetValue() - spec.step) end)
  local plus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  plus:SetSize(22, 18); plus:SetPoint("LEFT", s, "RIGHT", 3, 0); plus:SetText("+")
  plus:SetScript("OnClick", function() s:SetValue(s:GetValue() + spec.step) end)
  f.Refresh = function()
    f.lock = true
    local v = spec.get()
    s:SetValue(v); val:SetText(Fmt(v, spec.step))
    f.lock = false
  end
  return f
end

local function Check(parent, x, y, label, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", x, y)
  local l = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  l:SetPoint("LEFT", cb, "RIGHT", 1, 0); l:SetText(label)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  cb.Refresh = function() cb:SetChecked(get() and true or false) end
  return cb
end

local function PickColor(r, g, b, apply)
  local function cur() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); apply(nr, ng, nb) end
  local function cancel() apply(r, g, b) end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = cur, cancelFunc = cancel })
  else
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.func, ColorPickerFrame.cancelFunc, ColorPickerFrame.opacityFunc = cur, cancel, nil
    ColorPickerFrame.previousValues = { r, g, b }
    ColorPickerFrame:SetColorRGB(r, g, b)
    ShowUIPanel(ColorPickerFrame)
  end
end

local function Swatch(parent, x, y, label, getC)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(26, 18); b:SetPoint("TOPLEFT", x, y)
  b:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
  local t = b:CreateTexture(nil, "ARTWORK"); t:SetPoint("TOPLEFT", 3, -3); t:SetPoint("BOTTOMRIGHT", -3, 3)
  local l = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  l:SetPoint("LEFT", b, "RIGHT", 4, 0); l:SetText(label)
  b.Refresh = function() local c = getC(); t:SetColorTexture(c[1], c[2], c[3]) end
  b:SetScript("OnClick", function()
    local c = getC()
    PickColor(c[1], c[2], c[3], function(nr, ng, nb) c[1], c[2], c[3] = nr, ng, nb; b.Refresh(); SA.Changed() end)
  end)
  return b
end

---------------------------------------------------------------- window
local win, pages, navButtons, current = nil, {}, {}, nil
local W, H, NAVW = 700, 520, 150

local function GeneralPage(parent)
  local db, items = SA.db, {}
  local function G(label, key, mn, mx, step)
    return { label = label, min = mn, max = mx, step = step, get = function() return db[key] end,
             set = function(v) db[key] = v; SA.Changed() end }
  end
  local specs = {
    G("Whole display: left / right", "x", -800, 800, 1), G("Whole display: up / down", "y", -500, 500, 1),
    G("Circle size (radius)", "radius", 60, 400, 1), G("Base bar thickness", "thick", 4, 40, 1),
    G("Arc length (degrees up/down)", "arc", 15, 85, 1),
  }
  for i, sp in ipairs(specs) do
    local col, row = (i - 1) % 2, floor((i - 1) / 2)
    items[#items + 1] = Slider(parent, 10 + col * 258, -40 - row * 46, 250, sp)
  end
  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", 12, -190); note:SetWidth(510); note:SetJustifyH("LEFT")
  note:SetText("These move and size everything together. Pick an arc on the left to change it on its own - "
    .. "the selected arc is previewed while this window is open. Arcs only appear in play for the classes that use them.")
  return items
end

local function ElementPage(parent, key)
  local def = SA.ELEMENTS[key]
  local function E() return SA.db.el[key] end
  local items = {}
  local function S(label, field, mn, mx, step, fallback)
    return { label = label, min = mn, max = mx, step = step,
             get = function() local v = E()[field]; if v == nil then v = fallback() end; return v end,
             set = function(v) E()[field] = v; SA.Changed() end }
  end
  local function C(label, field) return function() return E()[field] end, function(v) E()[field] = v; SA.Changed() end, label end
  -- toggles
  -- visibility mode
  local ml = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ml:SetPoint("TOPLEFT", 12, -40); ml:SetText("Show:")
  local MODES = { { "always", "Always on" }, { "auto", "In combat / when changing" }, { "off", "Always off" } }
  local mbtns = {}
  local mx = 50
  for _, m in ipairs(MODES) do
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(m[1] == "auto" and 180 or 100, 22); b:SetPoint("TOPLEFT", mx, -35); b:SetText(m[2])
    b:SetScript("OnClick", function() E().mode = m[1]; for _, x in ipairs(mbtns) do x.Refresh() end; SA.Changed() end)
    b.Refresh = function() b:SetEnabled((E().mode or "auto") ~= m[1]) end
    mbtns[#mbtns + 1] = b; items[#items + 1] = b
    mx = mx + b:GetWidth() + 6
  end
  local checks = { { "Show icon", "icon" }, { "Show number", "num" } }
  if def.shield then checks[#checks + 1] = { "Countdown", "timer" } end
  if key == "PWS" then checks[#checks + 1] = { "Weakened Soul", "ws" } end
  for i, c in ipairs(checks) do
    local get, set = C(c[1], c[2])
    items[#items + 1] = Check(parent, 10 + (i - 1) * 110, -62, c[1], get, set)
  end
  -- sliders (two columns)
  local specs = {
    S("Move left / right", "dx", -300, 300, 1), S("Move up / down", "dy", -300, 300, 1),
    S("Distance from center", "dr", -150, 150, 1), S("Thickness (x base)", "thick", 0.3, 3, 0.05),
    S("Arc length (degrees)", "arc", 10, 90, 1, function() return SA.db.arc end),
    S("Empty-segment opacity", "bg", 0, 1, 0.05),
    S("Icon size", "iconSize", 8, 48, 1, function() return math.max(14, SA.db.thick * E().thick + 6) end),
    S("Number size", "numSize", 8, 60, 1),
    S("Number left / right", "ndx", -200, 200, 1), S("Number up / down", "ndy", -200, 200, 1),
  }
  for i, sp in ipairs(specs) do
    local col, row = (i - 1) % 2, floor((i - 1) / 2)
    items[#items + 1] = Slider(parent, 10 + col * 258, -94 - row * 46, 250, sp)
  end
  -- colors
  local cl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  cl:SetPoint("TOPLEFT", 12, -332); cl:SetText(key == "COMBO" and "Colors (first point -> fifth point):" or "Colors (bottom -> top):")
  local names = { "Bottom", "Middle", "Top" }
  if key == "COMBO" then names = { "1st point", "3rd point", "5th point" } end
  for i = 1, 3 do
    items[#items + 1] = Swatch(parent, 12 + (i - 1) * 110, -350, names[i], function() return E().c[i] end)
  end
  local dc = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  dc:SetSize(110, 20); dc:SetPoint("TOPLEFT", 345, -349); dc:SetText("Default colors")
  dc:SetScript("OnClick", function()
    local d = SA.DefaultElement(key).c
    E().c = d
    for _, it in ipairs(items) do it.Refresh() end
    SA.Changed()
  end)
  local ra = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  ra:SetSize(120, 22); ra:SetPoint("TOPLEFT", 12, -384); ra:SetText("Reset this arc")
  ra:SetScript("OnClick", function() SA.ResetElement(key); for _, it in ipairs(items) do it.Refresh() end end)
  if not SA.Relevant(key) then
    local n = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    n:SetPoint("TOPLEFT", 145, -389); n:SetText("(not used by this character's class - preview only)")
  end
  return items
end

local function Select(key)
  current = key
  for k, pg in pairs(pages) do pg:SetShown(k == key) end
  if not pages[key] then
    local pg = CreateFrame("Frame", nil, win)
    pg:SetPoint("TOPLEFT", NAVW + 16, -40); pg:SetPoint("BOTTOMRIGHT", -10, 44)
    local title = pg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetText(key == "GENERAL" and "Overall position and size" or SA.ELEMENTS[key].label)
    pg.items = (key == "GENERAL") and GeneralPage(pg) or ElementPage(pg, key)
    pages[key] = pg
  end
  for _, it in ipairs(pages[key].items) do it.Refresh() end
  pages[key]:Show()
  for k, b in pairs(navButtons) do b:SetEnabled(k ~= key) end
  SA.SetSelected(key ~= "GENERAL" and key or nil)
end

local function CreateWindow()
  win = CreateFrame("Frame", "ShieldArcsOptions", UIParent, "BackdropTemplate")
  win:SetSize(W, H); win:SetPoint("CENTER", 220, 40); win:SetFrameStrata("DIALOG")
  win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  win:SetBackdropColor(0, 0, 0, 0.94)
  win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton"); win:SetClampedToScreen(true)
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  tinsert(UISpecialFrames, "ShieldArcsOptions")
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12); title:SetText("Pints Shield Arcs")
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2)
  local sep = win:CreateTexture(nil, "ARTWORK"); sep:SetColorTexture(1, 0.82, 0, 0.3)
  sep:SetWidth(1); sep:SetPoint("TOPLEFT", NAVW + 12, -40); sep:SetPoint("BOTTOMLEFT", NAVW + 12, 44)

  local list = { "GENERAL" }
  for _, k in ipairs(SA.ORDER) do list[#list + 1] = k end
  for i, k in ipairs(list) do
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetSize(NAVW - 8, 24); b:SetPoint("TOPLEFT", 10, -40 - (i - 1) * 28)
    local label = (k == "GENERAL") and "Overall" or SA.ELEMENTS[k].label
    if k ~= "GENERAL" and not SA.Relevant(k) then label = "|cff909090" .. label .. "|r" end
    b:SetText(label)
    b:SetScript("OnClick", function() Select(k) end)
    navButtons[k] = b
  end

  local test = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  test:SetSize(170, 22); test:SetPoint("BOTTOMLEFT", 12, 12)
  local function TT() test:SetText(SA.IsTest() and "Preview all: ON" or "Preview all: OFF") end
  test:SetScript("OnClick", function() SA.SetTest(not SA.IsTest()); TT() end)
  win.RefreshTest = TT
  local reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  reset:SetSize(150, 22); reset:SetPoint("BOTTOMRIGHT", -12, 12); reset:SetText("Reset everything")
  reset:SetScript("OnClick", function()
    SA.ResetAll()
    if current and pages[current] then for _, it in ipairs(pages[current].items) do it.Refresh() end end
  end)
  win:SetScript("OnShow", function() SA.SetOptionsOpen(true); TT(); Select(current or "GENERAL") end)
  win:SetScript("OnHide", function() SA.SetOptionsOpen(false); SA.SetSelected(nil) end)
  win:Hide()
end

function SA.OpenOptions()
  if not win then CreateWindow() end
  if win:IsShown() then win:Hide() else win:Show() end
end

---------------------------------------------------------------- minimap button
local function MinimapButton()
  local store = SA.db.minimap
  local label, icon = "Pints Shield Arcs", "Interface\\Icons\\Spell_Holy_PowerWordShield"
  local function Tooltip(tt)
    tt:AddLine(label)
    tt:AddLine("Left-click: options", 1, 1, 1)
    tt:AddLine("Right-click: preview all on/off", 1, 1, 1)
  end
  local function Click(button)
    if button == "RightButton" then
      SA.SetTest(not SA.IsTest())
      if win and win.RefreshTest then win.RefreshTest() end
    else
      SA.OpenOptions()
    end
  end
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  local Icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if LDB and Icon then
    local obj = LDB:NewDataObject("ShieldArcs", { type = "launcher", text = label, icon = icon,
      OnClick = function(_, button) Click(button) end, OnTooltipShow = Tooltip })
    Icon:Register("ShieldArcs", obj, store)
    return
  end
  local b = CreateFrame("Button", "ShieldArcsMinimapButton", Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local ic = b:CreateTexture(nil, "BACKGROUND"); ic:SetTexture(icon); ic:SetSize(20, 20); ic:SetPoint("CENTER", 0, 1)
  ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local border = b:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53); border:SetPoint("TOPLEFT")
  local function Place()
    local a = math.rad(store.angle or 220)
    b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a))
  end
  Place()
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      store.angle = math.deg(math.atan2(py / s - my, px / s - mx)); Place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, button) Click(button) end)
  b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); Tooltip(GameTooltip); GameTooltip:Show() end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function() if SA.db then MinimapButton() end end)
