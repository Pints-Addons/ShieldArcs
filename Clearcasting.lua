-- Pints Shield Arcs: Clearcasting. When you go Clearcasting (shamans' Elemental Focus - your next damage spell costs no
-- mana; also mages' Arcane Concentration, priests' Holy Concentration, druids' Omen of Clarity), a glowing icon sits at
-- the top of the arcs, above the Ancestral Fortitude row, with the seconds left - so you spend it on Chain Lightning.
--   Read from your own buffs. On WoW Forever the game can hide them in a fight; then the cost of your spells is
--   checked instead (a free cast means you're Clearcasting).
-- /sarc cc turns it on or off; /sarc cc test shows it.
local SA = _G.ShieldArcs
if not SA then return end

local SECRET = type(issecretvalue) == "function"
local function IsSecret(v) return SECRET and issecretvalue(v) end
local GetSpellInfo = GetSpellInfo or function(s)
  local i = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(s)
  if i then return i.name, nil, i.iconID end
end
-- Clearcasting from Elemental Focus, Arcane Concentration, Holy Concentration, Omen of Clarity
local CC_IDS = { [16246] = true, [12536] = true, [34754] = true, [16870] = true }
local CC_NAME, _, CC_ICON = GetSpellInfo(16246)
CC_NAME = CC_NAME or "Clearcasting"
CC_ICON = CC_ICON or "Interface\\Icons\\Spell_Shadow_ManaBurn"
local SIZE = 36
-- a spell to check the cost of, when the buff itself is hidden (one you know that Clearcasting makes free)
local PROBE = { SHAMAN = { "Lightning Bolt", "Chain Lightning", "Flame Shock" }, MAGE = { "Frostbolt", "Fireball", "Arcane Missiles" },
  PRIEST = { "Smite", "Heal", "Greater Heal" }, DRUID = { "Wrath", "Healing Touch", "Starfire" } }
local _, CLASS = UnitClass("player")
if not PROBE[CLASS] then return end            -- (no Clearcasting for this class)

local b = CreateFrame("Frame", nil, _G.ShieldArcsFrame or UIParent)
b:SetSize(SIZE, SIZE); b:Hide()
b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetPoint("TOPLEFT", -2, 2); b.edge:SetPoint("BOTTOMRIGHT", 2, -2)
b.edge:SetColorTexture(0.35, 0.75, 1, 0.95)
b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexture(CC_ICON); b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
b.glow = b:CreateTexture(nil, "OVERLAY"); b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); b.glow:SetBlendMode("ADD")
b.glow:SetSize(SIZE * 1.9, SIZE * 1.9); b.glow:SetPoint("CENTER"); b.glow:SetVertexColor(0.4, 0.8, 1)
b.time = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge"); b.time:SetPoint("CENTER", 0, 0)
b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
b.label:SetText("|cff66ccffClearcasting|r"); b.label:SetShadowOffset(1, -1)
local pulse = b.glow:CreateAnimationGroup(); pulse:SetLooping("BOUNCE")
local a = pulse:CreateAnimation("Alpha"); a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.5)

local function On() local db = SA.db; return db and db.clearcasting ~= false end
local expires, viaCost = nil, false

local function Place()
  -- the top of the arcs, above the Ancestral Fortitude icons
  local db = SA.db
  local top = (db and db.radius or 150) * math.sin(math.rad(db and db.arc or 42)) + 14
  b:ClearAllPoints(); b:SetPoint("BOTTOM", _G.ShieldArcsFrame or UIParent, "CENTER", 0, top + 52)
end
local function Show(exp, cost)
  if not On() then b:Hide(); return end
  expires, viaCost = exp, cost
  Place()
  if not b:IsShown() then b:Show(); pulse:Play() end
end
local function Hide() expires = nil; viaCost = false; pulse:Stop(); b:Hide() end

-- the buff on you
local function FromAura()
  local found, readable = false, true
  if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    for id in pairs(CC_IDS) do
      local ok, d = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
      if not ok then readable = false
      elseif d then
        local exp = d.expirationTime
        return true, true, (not IsSecret(exp) and exp and exp > 0) and exp or nil
      end
    end
  end
  if UnitBuff and not SECRET then
    for i = 1, 40 do
      local name, _, _, _, _, exp, _, _, _, id = UnitBuff("player", i)
      if not name then break end
      if CC_IDS[id] or name == CC_NAME then return true, true, (exp and exp > 0) and exp or nil end
    end
  end
  return found, readable
end
-- a spell that costs mana suddenly costing none
local GetCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
local function FreeCast()
  if not GetCost then return nil end
  for _, s in ipairs(PROBE[CLASS]) do
    local ok, costs = pcall(GetCost, s)
    if ok and type(costs) == "table" then
      for _, c in ipairs(costs) do
        local t, n = c.type, c.cost
        if IsSecret(t) or IsSecret(n) then return nil end
        if t == 0 then return n == 0 end
      end
    end
  end
end

local function Check()
  if not On() then Hide(); return end
  local yes, readable, exp = FromAura()
  if yes then Show(exp, false); return end
  if readable and not SECRET then Hide(); return end
  local free = FreeCast()
  if free == true then Show(nil, true)
  elseif free == false or readable then Hide() end
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function() C_Timer.After(0.05, Check) end)

local acc = 0
b:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 0.2 then return end
  acc = 0
  if expires then
    local left = expires - GetTime()
    if left <= 0 then Check(); return end
    b.time:SetText(math.ceil(left))
  else b.time:SetText("") end
end)

-- /sarc cc: on or off   /sarc cc test: an example
SA.ClearcastTest = function() Show(GetTime() + 15, false) end
SA.ClearcastToggle = function()
  SA.db.clearcasting = (SA.db.clearcasting == false) and true or false
  print("|cff66ccffPints Shield Arcs|r Clearcasting icon " .. (SA.db.clearcasting and "on." or "off."))
  Check()
end
