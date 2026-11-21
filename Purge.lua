-- Pints Shield Arcs: Purge. When your target is an enemy with a magic buff you can take off (Purge, Dispel Magic,
-- Devour Magic), a red-rimmed icon of your purge spell sits at the bottom of the arcs, with how many such buffs it has
-- and the name of the first one - so you see it without looking up at the target frame.
--   Read from the target's buffs (only Magic ones can be purged). On WoW Forever the game can hide a buff's type in a
--   fight; then nothing is shown rather than a guess.
-- /sarc purge turns it on or off; /sarc purge test shows it.
local SA = _G.ShieldArcs
if not SA then return end

local SECRET = type(issecretvalue) == "function"
local function IsSecret(v) return SECRET and issecretvalue(v) end
local GetSpellInfo = GetSpellInfo or function(s)
  local i = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(s)
  if i then return i.name, nil, i.iconID end
end
-- the spell each class takes a magic buff off an enemy with
local SPELL = { SHAMAN = 370, PRIEST = 527, WARLOCK = 19505 }
local _, CLASS = UnitClass("player")
if not SPELL[CLASS] then return end
local P_NAME, _, P_ICON = GetSpellInfo(SPELL[CLASS])
P_NAME = P_NAME or "Purge"
P_ICON = P_ICON or "Interface\\Icons\\Spell_Nature_Purge"
local SIZE = 34

local b = CreateFrame("Frame", nil, _G.ShieldArcsFrame or UIParent)
b:SetSize(SIZE, SIZE); b:Hide()
b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetPoint("TOPLEFT", -2, 2); b.edge:SetPoint("BOTTOMRIGHT", 2, -2)
b.edge:SetColorTexture(0.95, 0.25, 0.2, 0.95)
b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexture(P_ICON); b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
b.glow = b:CreateTexture(nil, "OVERLAY"); b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); b.glow:SetBlendMode("ADD")
b.glow:SetSize(SIZE * 1.9, SIZE * 1.9); b.glow:SetPoint("CENTER"); b.glow:SetVertexColor(1, 0.35, 0.3)
b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge"); b.count:SetPoint("BOTTOMRIGHT", 2, -2)
b.buff = b:CreateTexture(nil, "OVERLAY"); b.buff:SetSize(16, 16); b.buff:SetPoint("TOPRIGHT", b, "TOPLEFT", -3, 0); b.buff:SetTexCoord(0.08, 0.92, 0.08, 0.92)
b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.label:SetPoint("TOP", b, "BOTTOM", 0, -2); b.label:SetShadowOffset(1, -1)
local pulse = b.glow:CreateAnimationGroup(); pulse:SetLooping("BOUNCE")
local an = pulse:CreateAnimation("Alpha"); an:SetFromAlpha(1); an:SetToAlpha(0.35); an:SetDuration(0.5)

local function On() local db = SA.db; return db and db.purge ~= false end

local function Place()
  -- the bottom of the arcs, below the lower ends
  local db = SA.db
  local bottom = (db and db.radius or 150) * math.sin(math.rad(db and db.arc or 42)) + 14
  b:ClearAllPoints(); b:SetPoint("TOP", _G.ShieldArcsFrame or UIParent, "CENTER", 0, -(bottom + 30))
end
local function Show(n, name, icon, hasIcon)
  if not On() then b:Hide(); return end
  Place()
  b.count:SetText(n > 1 and n or "")
  b.label:SetText("|cffff6050" .. P_NAME .. "|r" .. (name and (": |cffffffff" .. name .. "|r") or ""))
  if hasIcon then pcall(b.buff.SetTexture, b.buff, icon); b.buff:Show() else b.buff:Hide() end
  if not b:IsShown() then b:Show(); pulse:Play() end
end
local function Hide() pulse:Stop(); b:Hide() end

-- the target's magic buffs: how many, and the first one's name and icon
-- In a fight WoW Forever hides what each buff is, but it still lists the ones YOU can take off (it filters them itself):
-- count those, and show the first one's icon (the game draws it even when it won't tell us what it is)
local function ScanHidden()
  local GetAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not (SECRET and GetAura) then return nil end
  local ok, first = pcall(GetAura, "target", 1, "HELPFUL")
  if not ok or first == nil or not (IsSecret(first) or IsSecret(first.dispelName) or IsSecret(first.name)) then return nil end
  local n, icon = 0, nil
  for i = 1, 40 do
    local okD, d = pcall(GetAura, "target", i, "HELPFUL|RAID_PLAYER_DISPELLABLE")
    if not okD or d == nil or IsSecret(d) then break end
    n = n + 1
    if n == 1 then icon = d.icon end
  end
  return n, nil, icon, n > 0
end
local function Scan()
  if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDeadOrGhost("target") then return 0 end
  local hn, hname, hicon, hhas = ScanHidden()
  if hn then return hn, hname, hicon, hhas end
  local n, name, icon = 0
  local GetAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  for i = 1, 40 do
    local nm, ic, kind
    if GetAura then
      local ok, d = pcall(GetAura, "target", i, "HELPFUL")
      if not ok or not d then break end
      nm, ic, kind = d.name, d.icon, d.dispelName
    elseif UnitBuff then
      local a1, a2, _, a4 = UnitBuff("target", i)
      if not a1 then break end
      nm, ic, kind = a1, a2, a4
    else break end
    if not IsSecret(kind) and kind == "Magic" then
      n = n + 1
      if not name and not IsSecret(nm) then name, icon = nm, (not IsSecret(ic)) and ic or nil end
    end
  end
  return n, name, icon, icon ~= nil
end

local function Check()
  if not On() then Hide(); return end
  local n, name, icon, has = Scan()
  if n > 0 then Show(n, name, icon, has) else Hide() end
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "target")
pcall(ev.RegisterEvent, ev, "PLAYER_TARGET_CHANGED")
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", Check)

-- /sarc purge: on or off   /sarc purge test: an example
SA.PurgeTest = function() Show(2, "Power Word: Shield", "Interface\\Icons\\Spell_Holy_PowerWordShield", true) end
SA.PurgeToggle = function()
  SA.db.purge = (SA.db.purge == false) and true or false
  print("|cff66ccffPints Shield Arcs|r purge icon " .. (SA.db.purge and "on." or "off."))
  Check()
end
