-- Run from the repository root: lua .tools/tests/test_tooltip_unit_details.lua
local path = arg[1] or "EllesmereUIBlizzardSkin/EUI_BlizzardSkin_TooltipSkin.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local first = assert(source:find("    do\n        local installed = false\n        EllesmereUI._applyTooltipUnitDetails", 1, true))
local last = assert(source:find('    -- "Targeting" line:', first, true))
local production = source:sub(first, last - 1)
local checks = 0
local function Check(condition, message)
    checks = checks + 1
    assert(condition, message)
end

local secret = setmetatable({}, {
    __index = function() error("attempted to read a secret") end,
    __tostring = function() error("attempted to format a secret") end,
})
local inaccessible = {}
local function Copy(value)
    if type(value) ~= "table" or value == secret then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = Copy(item) end
    return copy
end
local function Same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" or a == secret or b == secret then return false end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function Fixture()
    local f = {
        enabled = true, usable = true,
        classification = "normal", registrations = 0, identityCalls = 0,
        settings = { tooltipShowRarity = false },
    }
    f.tooltip = { rendered = {} }
    function f.tooltip:IsForbidden() return f.forbidden end
    local env = setmetatable({
        EllesmereUIDB = f.settings,
        EllesmereUI = {
            L = function(text) return text end,
            BlizzSkinPadStandDown = function() return f.standDown end,
        },
        Enum = { TooltipDataType = { Unit = 2 },
            TooltipDataLineType = { None = 0, UnitName = 2, UnitLevel = 47, UnitType = 48 } },
        ELITE = "Elite", NORMAL_FONT_COLOR = { r = 1, g = 1, b = 1 },
        TOOLTIP_UNIT_LEVEL = "Level %s",
        TOOLTIP_UNIT_LEVEL_RACE = "Level %s %s",
        TOOLTIP_UNIT_LEVEL_TYPE = "Level %s (%s)",
        TOOLTIP_UNIT_LEVEL_RACE_TYPE = "Level %s %s (%s)",
        _GameTooltip = f.tooltip,
        _enabled = function() return f.enabled end,
        _ttUsable = function() return f.usable end,
        _isSecret = function(value) return value == secret end,
        canaccesstable = function(value)
            return type(value) == "table" and value ~= secret and not inaccessible[value]
        end,
        canaccessallvalues = function(...)
            for i = 1, select("#", ...) do
                if select(i, ...) == secret then return false end
            end
            return true
        end,
        _resolveTipIdentity = function()
            f.identityCalls = f.identityCalls + 1
            if f.identityError then error("restricted identity") end
            return "Creature-1", not f.noUnit and "mouseover" or nil
        end,
        UnitClassification = function() return f.classification end,
        GameTooltip_AddColoredLine = function(tt, text, color, wrap, offset)
            if f.renderError then error("restricted widget") end
            tt.rendered[#tt.rendered + 1] = { leftText = text, leftColor = color,
                wrapText = wrap, leftOffset = offset }
        end,
        TooltipDataProcessor = {
            AllTypes = "all",
            AddTooltipPreCall = function(kind, callback)
                Check(kind == 2 and not f.pre, "register exactly one unit pre-call")
                f.pre = callback
                f.registrations = f.registrations + 1
            end,
            AddLinePreCall = function(kind, callback)
                Check(kind == "all" and not f.line, "register exactly one line pre-call")
                f.line = callback
                f.registrations = f.registrations + 1
            end,
        },
    }, { __index = _G })
    f.env = env
    setfenv(assert(loadstring(production, "@" .. path)), env)()
    f.apply = env.EllesmereUI._applyTooltipUnitDetails
    function f:Render(data, tooltip)
        tooltip = tooltip or self.tooltip
        tooltip.rendered = {}
        local before = Copy(data)
        if self.pre then self.pre(tooltip, data) end
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if not (self.line and self.line(tooltip, line)) then
                    tooltip.rendered[#tooltip.rendered + 1] = line
                end
            end
        end
        Check(Same(data, before), "callbacks must not mutate Blizzard tooltip data")
        return tooltip.rendered
    end
    return f
end

local function CreatureData(text)
    return { guid = "Creature-1", lines = {
        { type = 2, leftText = "Deviate Coiler" },
        { type = 0, leftText = text or "Level 15 (Elite)" },
        { type = 0, leftText = "Beast" },
    } }
end
local function Unchanged(f, data, message, tooltip)
    local rendered = f:Render(data, tooltip)
    Check(Same(rendered, data.lines), message)
end

local f = Fixture()
f.apply()
f.apply()
Check(f.registrations == 0 and f.identityCalls == 0, "disabled setting must install nothing")
f.settings.tooltipShowRarity = true
f.enabled = false
f.apply()
Check(f.registrations == 0, "master disabled must install nothing")
f.enabled = true
f.standDown = true
f.apply()
Check(f.registrations == 0, "skin stand-down must install nothing")
f.standDown = false
f.apply()
f.apply()
Check(f.registrations == 2, "first enable installs callbacks once")

local data, rendered
for _, case in ipairs({
    { "rare", "Level 15", "Level 15 (Rare)" },
    { "rare", "Level 15 (Elite)", "Level 15 (Rare)" },
    { "rareelite", "Level 15 (Elite)", "Level 15 (Rare Elite)" },
    { "rareelite", "Level 15 (Rare)", "Level 15 (Rare Elite)" },
    { "rareelite", "Level 15", "Level 15 (Rare Elite)" },
    { "rare", "Level 15 (Rare)", "Level 15 (Rare)" },
    { "rareelite", "Level 15 (Rare Elite)", "Level 15 (Rare Elite)" },
    { "rareelite", "Level 15 (elite)", "Level 15 (Rare Elite)" },
}) do
    f.classification = case[1]
    data = CreatureData(case[2])
    rendered = f:Render(data)
    Check(#rendered == 3 and rendered[2].leftText == case[3], "render " .. case[1] .. " classification")
    Check(Same(f:Render(data), rendered), "repeat rarity render without duplication")
end

data = CreatureData()
data.lines[2].type = 47
rendered = f:Render(data)
Check(#rendered == 3 and rendered[2].leftText == "Level 15 (Rare Elite)", "typed creature level shows rare elite")
data = CreatureData("|cffffff00Level 15|r (Elite)")
data.lines[2].leftColor = { r = 1, g = 1, b = 0 }
data.lines[2].wrapText = true
data.lines[2].leftOffset = 3
data.lines[2].rightText = ""
table.insert(data.lines, 2, { type = 0, leftText = "<Guild Name>" })
table.insert(data.lines, { type = 0, leftText = "Targeting:", rightText = "You" })
rendered = f:Render(data)
Check(#rendered == 5 and rendered[3].leftText == "|cffffff00Level 15|r (Rare Elite)", "retain level formatting")
Check(rendered[3].leftColor == data.lines[3].leftColor and rendered[3].wrapText == true
    and rendered[3].leftOffset == 3, "preserve level color, wrapping and offset")
Check(rendered[2].leftText == "<Guild Name>" and rendered[4].leftText == "Beast"
    and rendered[5].rightText == "You", "preserve surrounding lines and targeting")

for _, case in ipairs({
    { "Level %1$s (%2$s)", "Level 15 (Elite)", "Level 15 (Rare Elite)" },
    { "%s - (%s)", "15 - (Elite)", "15 - (Rare Elite)" },
    { "Level.%s [%s]", "Level.15 [Beast]", "Level.15 [Beast] (Rare Elite)" },
}) do
    local localized = Fixture()
    localized.env.TOOLTIP_UNIT_LEVEL_TYPE = case[1]
    localized.settings.tooltipShowRarity = true
    localized.classification = "rareelite"
    localized.apply()
    rendered = localized:Render(CreatureData(case[2]))
    Check(#rendered == 3 and rendered[2].leftText == case[3], "recognize localized level format " .. case[1])
end
for _, classification in ipairs({ "normal", "elite", "worldboss", "minus" }) do
    f.classification = classification
    Unchanged(f, CreatureData(), classification .. " must remain unchanged")
end
f.classification = "rareelite"
for _, case in ipairs({
    { "right-side level content", function(d) d.lines[2].rightText = "Useful content" end },
    { "missing level type", function(d) d.lines[2].type = nil end },
    { "unrelated generic text", function(d) d.lines[2].leftText = "Current focus (Elite)" end },
    { "missing level line", function(d) table.remove(d.lines, 2) end },
}) do
    data = CreatureData()
    case[2](data)
    Unchanged(f, data, case[1] .. " must leave original lines intact")
end
f.enabled = false
local calls = f.identityCalls
Unchanged(f, CreatureData(), "master disabled leaves original lines intact")
Check(f.identityCalls == calls, "master disabled must not resolve unit identity")
f.enabled = true
f.settings.tooltipShowRarity = false
Unchanged(f, CreatureData(), "disabled after installation leaves original lines intact")
Check(f.identityCalls == calls, "disabled setting must not resolve unit identity")
f.settings.tooltipShowRarity = true
f.apply()
Check(f.registrations == 2, "re-enabling must reuse existing callbacks")

for _, flag in ipairs({ "forbidden", "noUnit", "identityError", "renderError" }) do
    f[flag] = true
    Unchanged(f, CreatureData(), flag .. " leaves original lines intact")
    f[flag] = false
end
f.usable = false
Unchanged(f, CreatureData(), "unusable tooltip leaves original lines intact")
f.usable = true
local other = { IsForbidden = function() return false end }
Unchanged(f, CreatureData(), "other tooltip must remain unchanged", other)

for _, field in ipairs({ "type", "leftText", "rightText", "leftColor", "wrapText", "leftOffset" }) do
    data = CreatureData()
    data.lines[2][field] = secret
    Unchanged(f, data, "secret level " .. field .. " leaves original lines intact")
end
for _, part in ipairs({ "data", "lines", "level" }) do
    data = CreatureData()
    local restricted = part == "data" and data or part == "lines" and data.lines or data.lines[2]
    inaccessible[restricted] = true
    Unchanged(f, data, "inaccessible " .. part .. " leaves original lines intact")
    inaccessible[restricted] = nil
end
f.classification = secret
Unchanged(f, CreatureData(), "secret classification leaves original lines intact")
f.classification = "rareelite"
f:Render(nil)
Check(#f.tooltip.rendered == 0, "missing tooltip data is safe")
Check(not f.line(f.tooltip, secret), "secret line callback must be ignored")

print("PASS: tooltip unit details (" .. checks .. " assertions)")
