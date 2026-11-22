---@diagnostic disable: undefined-global, undefined-field
--
-- RaceCosmetic - cosmetic race reshuffle for Baldur's Gate 3
--
-- Opens the real character creation screen, then applies ONLY the visual parts
-- (appearance, body type, voice) to the existing character. Race component, tags,
-- passives, class, background and the Dream Guardian stay untouched.
--

local SPELL_BOX  = "RC_Shout_Reshape"
local SPELL_OPEN = "RC_Shout_Reshape"

-- Tested: swapping the race inside the shapeshift also changes the race name and the
-- tags shown on the character, and on its own it does NOT fix the level up preview.
-- The Race component is written directly instead (see COPY_RACE_COMPONENT).
local USE_FULL_RACE = false

-- Which visual data is written into the character.
--
-- The Race component and the race stored in CharacterCreationStats are deliberately NOT written.
-- Withers' respec replays the racial progression of the race found in CharacterCreationStats, so
-- writing the picked race there is what used to make a reshaped character receive the looked
-- race's traits while keeping the original name and tags. Leaving both alone means every respec
-- replays the original progression - the model itself is carried by the visual template and the
-- appearance data, which is enough (verified in game).
--
-- Half a write is worse than no write: appearance without the visual template produced detached
-- hair and mismatched limbs. The pieces below therefore have to succeed together (copyAppearanceData).
local COPY_APPEARANCE_DATA = true
local COPY_VISUAL_COMPONENT = true
local COPY_CREATION_RACE = false
local COPY_RACE_COMPONENT = false

local RULE_SAFE = "3b8e5c41-9f2d-4a71-b6c3-8d1e4f7a2c95"
local RULE_FULL = "c1a7f2d9-6b34-4e05-9d8a-3f2b7c51e694"
local NULL_GUID = "00000000-0000-0000-0000-000000000000"

local LOG_FILE = "RaceCosmetic.log"

-- Vanilla race table generated from the game data (Races.lsx + Progressions.lsx).
local okRaceData, RaceData = pcall(Ext.Require, "RaceCosmetic/RaceData.lua")
if not okRaceData or type(RaceData) ~= "table" then
    RaceData = { parent = {} }
end

-- Visual fields that live on ServerCharacter.Template instead of on components.
-- EquipmentRace picks which race/gender variant of an armour mesh is worn, which is
-- why armour kept the old body shape while the body itself was already the new one.
local TEMPLATE_VISUAL_KEYS = { "EquipmentRace", "CharacterVisualResourceID", "VisualTemplate" }

-- 30 minutes: plenty of time to sculpt, short enough that a stale cast cannot
-- hijack a companion who joins much later.
local OPEN_TIMEOUT_MS = 1800000

---------------------------------------------------------------------------------------------------
-- logging (SE console + Script Extender\RaceCosmetic.log)
---------------------------------------------------------------------------------------------------

local logLines = {}

local function flushLog()
    pcall(function()
        Ext.IO.SaveFile(LOG_FILE, table.concat(logLines, "\n"))
    end)
end

local function log(msg)
    logLines[#logLines + 1] = "[?] " .. tostring(msg)
    if #logLines > 300 then table.remove(logLines, 1) end
    pcall(function() Ext.Utils.Print("[RaceCosmetic] " .. tostring(msg)) end)
    flushLog()
end

log("=== RaceCosmetic bootstrap (full race swap = " .. tostring(USE_FULL_RACE) .. ") ===")

---------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------

local function guid(ref)
    if type(ref) ~= "string" then return "" end
    local i = ref:find("_[^_]*$")
    if i then return ref:sub(i + 1) end
    return ref
end

local function copyComponent(srcEntity, dstEntity, component)
    if not (srcEntity and dstEntity) then return false end

    local src, dst
    if not pcall(function() src = srcEntity[component]; dst = dstEntity[component] end) then
        return false
    end
    if src == nil or dst == nil then return false end
    if type(TryToReserializeObject) ~= "function" then return false end

    -- signature is TryToReserializeObject(source, destination)
    local ok = pcall(TryToReserializeObject, src, dst)
    if not ok then return false end

    pcall(function() dstEntity:Replicate(component) end)
    return true
end

local function tagSet(entity)
    local set = {}
    if not pcall(function()
        if entity.Tag and entity.Tag.Tags then
            for _, tag in pairs(entity.Tag.Tags) do
                if type(tag) == "string" then set[tag] = true end
            end
        end
    end) then return nil end
    return set
end

-- A character created by the character creation screen is flagged as a player.
-- Companions joining the party are not, which is what keeps a real companion from
-- ever being mistaken for the throwaway character and getting deleted.
local function looksLikeCreatedPlayer(ref)
    local ok, value = pcall(Osi.IsPlayer, ref)
    if not ok then return true end -- cannot verify, keep the old behaviour
    return value == 1
end

---------------------------------------------------------------------------------------------------
-- spell provisioning
---------------------------------------------------------------------------------------------------

local function statsCheck()
    local ok, entry = pcall(function() return Ext.Stats.Get(SPELL_BOX) end)
    if ok and entry ~= nil then
        log("stats OK: " .. SPELL_BOX .. " exists")
        return true
    end
    log("stats MISSING: " .. SPELL_BOX .. " was not found in the stat database")
    return false
end

local function collectPlayers()
    local list, seen = {}, {}

    local function add(ref)
        if type(ref) ~= "string" or ref == "" then return end
        if ref:find("NULL_") then return end
        local key = guid(ref)
        if key == "" or seen[key] then return end
        seen[key] = true
        list[#list + 1] = ref
    end

    local okH, host = pcall(Osi.GetHostCharacter)
    if okH and host ~= nil then add(host) end

    local okQ, rows = pcall(function() return Osi.DB_Players:Get(nil) end)
    if okQ and type(rows) == "table" then
        for _, row in pairs(rows) do
            if row then add(row[1]) end
        end
    end

    local okP, party = pcall(function() return Osi.DB_PartyMembers:Get(nil) end)
    if okP and type(party) == "table" then
        for _, row in pairs(party) do
            if row then add(row[1]) end
        end
    end

    return list
end

local function grantTo(ref)
    local g = guid(ref)
    if g == "" then return false end

    -- Older builds handed out a container spell with two variants; drop it so no
    -- orphan icon is left behind.
    pcall(Osi.RemoveSpell, g, "RC_Spell_Container")

    local okHas, has = pcall(Osi.HasSpell, g, SPELL_BOX)
    if okHas and has == 1 then return false end

    local okAdd = pcall(Osi.AddSpell, g, SPELL_BOX, 1, 1)
    if okAdd then log("spell granted to " .. g) end
    return okAdd
end

local grantAttempts = 0

local function tryGrant()
    grantAttempts = grantAttempts + 1

    local players = collectPlayers()
    if #players == 0 then
        if grantAttempts < 15 then
            pcall(Osi.TimerLaunch, "RC_GRANT_RETRY", 2000)
        else
            log("giving up granting the spell: no player characters found")
        end
        return false
    end

    local any = false
    for _, ref in ipairs(players) do
        if grantTo(ref) then any = true end
    end
    if any then log("spell granted to " .. #players .. " player(s)") end
    return any
end

---------------------------------------------------------------------------------------------------
-- voice / template helpers
--
-- The reshape is a permanent conversion, there is no snapshot and no restore path.
---------------------------------------------------------------------------------------------------

local function readVoice(entity)
    local value
    pcall(function() value = entity.Voice and entity.Voice.Voice end)
    return value
end

local function writeVoice(entity, value)
    local ok = pcall(function() entity.Voice.Voice = value end)
    if ok then pcall(function() entity:Replicate("Voice") end) end
    return ok
end

local function readTemplateKey(entity, key)
    local value
    pcall(function() value = entity.ServerCharacter.Template[key] end)
    return value
end

local function writeTemplateKey(entity, key, value)
    local ok = pcall(function() entity.ServerCharacter.Template[key] = value end)
    if ok then return true end
    if type(protectedSet) == "function" then
        return pcall(protectedSet, entity.ServerCharacter.Template, key, value)
    end
    return false
end

local function copyVoice(srcEntity, dstEntity)
    local value = readVoice(srcEntity)
    if type(value) ~= "string" or value == "" then return false end
    return writeVoice(dstEntity, value)
end

-- Old builds wrote the picked race into CharacterCreationStats, which is what Withers' respec
-- reads when it replays racial progression. Since that field is no longer written, characters
-- converted by an older build are put back in sync here: the runtime Race component is the truth.
local function guidText(value)
    if value == nil then return "" end
    return (tostring(value):gsub("[{}]", ""):lower())
end

local function repairCreationRace(entity)
    local stats = entity.CharacterCreationStats
    local raceComponent = entity.Race
    if stats == nil or raceComponent == nil then return false end

    local runtime = guidText(raceComponent.Race)
    if runtime == "" then return false end
    if guidText(stats.SubRace) == runtime then return false end

    local parent = RaceData.parent[runtime]
    local ok = pcall(function()
        stats.SubRace = raceComponent.Race
        if parent ~= nil then stats.Race = parent end
        entity:Replicate("CharacterCreationStats")
    end)
    log("creation race repaired to " .. runtime ..
        " (parent=" .. tostring(parent) .. ") ok=" .. tostring(ok))
    return ok
end

local function repairAllPlayers()
    local players = collectPlayers()
    for _, ref in ipairs(players) do
        local entity = Ext.Entity.Get(guid(ref))
        if entity ~= nil then pcall(repairCreationRace, entity) end
    end
end

---------------------------------------------------------------------------------------------------
-- appearance data copy
--
-- The shapeshift alone only changes what the world renders. The character sheet and
-- the level up screen rebuild a preview from the saved character data instead, so the
-- data has to be written as well or those screens mix old body data with new parts.
-- Technique borrowed from Appearance Edit Enhanced: serialize the source component and
-- unserialize it into the destination component, then replicate.
---------------------------------------------------------------------------------------------------

local DEFAULT_ELEMENTS = {
    ["1"] = { Color = "00000000-0000-0000-0000-000000000000", Material = "00000000-0000-0000-0000-000000000000", ColorIntensity = 1.0, MetallicTint = 0, GlossyTint = 1.0 },
    ["2"] = { Color = "00000000-0000-0000-0000-000000000000", Material = "00000000-0000-0000-0000-000000000000", ColorIntensity = 1.0, MetallicTint = 0, GlossyTint = 0.0 },
    ["3"] = { Color = "00000000-0000-0000-0000-000000000000", Material = "f03b33ae-5d47-4cb5-80bc-ea06a3c55c96", ColorIntensity = 1.0, MetallicTint = 0, GlossyTint = 1.0 },
    ["4"] = { Color = "00000000-0000-0000-0000-000000000000", Material = "00000000-0000-0000-0000-000000000000", ColorIntensity = 0.0, MetallicTint = 0, GlossyTint = 1.0 },
    ["5"] = { Color = "00000000-0000-0000-0000-000000000000", Material = "00000000-0000-0000-0000-000000000000", ColorIntensity = 0.0, MetallicTint = 0, GlossyTint = 1.0 },
    ["6"] = { Color = "00000000-0000-0000-0000-000000000000", Material = "00000000-0000-0000-0000-000000000000", ColorIntensity = 0.0, MetallicTint = 0, GlossyTint = 1.0 },
    ["7"] = { Color = "00000000-0000-0000-0000-000000000000", Material = "00000000-0000-0000-0000-000000000000", ColorIntensity = 1.0, MetallicTint = 0, GlossyTint = 0.0 },
    ["8"] = { Color = "00000000-0000-0000-0000-000000000000", Material = "00000000-0000-0000-0000-000000000000", ColorIntensity = 0.0, MetallicTint = 0, GlossyTint = 1.0 },
    ["9"] = { Color = "00000000-0000-0000-0000-000000000000", Material = "00000000-0000-0000-0000-000000000000", ColorIntensity = 0.0, MetallicTint = 0, GlossyTint = 1.0 },
}

-- nil on success, error string otherwise
local function cloneProxy(original, clone)
    if original == nil or clone == nil then return "missing component" end
    if Ext.Types == nil or Ext.Types.Serialize == nil or Ext.Types.Unserialize == nil then
        return "no serialize api"
    end
    local ok, err = pcall(function()
        local serialized = Ext.Types.Serialize(clone)
        Ext.Types.Unserialize(original, serialized)
    end)
    if not ok then return tostring(err) end
    return nil
end

local function isEmpty(value)
    if value == nil then return true end
    local ok, empty = pcall(function()
        for _ in pairs(value) do return false end
        return true
    end)
    return ok and empty
end

local function ensureOverride(entity)
    local override
    pcall(function() override = entity.AppearanceOverride end)
    if override ~= nil then return true end

    pcall(function() entity:CreateComponent("AppearanceOverride") end)
    pcall(function() override = entity.AppearanceOverride end)
    if override ~= nil then return true end

    -- Some entities only accept the immediate variant.
    pcall(function() entity:CreateComponentImmediate("AppearanceOverride") end)
    pcall(function() override = entity.AppearanceOverride end)
    return override ~= nil
end

-- The game keeps the last applied look in AppearanceOverride; fill it from the
-- character creation appearance so every preview has something coherent to render.
local function syncOverride(entity)
    local override
    pcall(function() override = entity.AppearanceOverride end)
    if override == nil and not ensureOverride(entity) then
        return false
    end
    pcall(function() override = entity.AppearanceOverride end)

    local source = entity.CharacterCreationAppearance
    if override == nil or source == nil then
        log("AppearanceOverride unavailable (component=" .. tostring(override ~= nil) ..
            " source=" .. tostring(source ~= nil) .. ")")
        return false
    end

    local visual
    pcall(function() visual = override.Visual end)
    if visual ~= nil then
        if isEmpty(visual.Elements) then
            pcall(function() visual.Elements = DEFAULT_ELEMENTS end)
        end
        pcall(function() cloneProxy(visual, source) end)
        pcall(function() cloneProxy(visual.Visuals, source.Visuals) end)
        pcall(function() cloneProxy(visual.Elements, source.Elements) end)
    end

    pcall(function() entity:Replicate("AppearanceOverride") end)
    pcall(function() entity:Replicate("GameObjectVisual") end)
    return true
end

local function copyAppearanceData(casterEntity, tempEntity)
    local report = {}

    local function step(label, dst, src, component)
        local err = cloneProxy(dst, src)
        report[#report + 1] = label .. "=" .. (err and ("ERR:" .. err) or "ok")
        if not err and component then
            pcall(function() casterEntity:Replicate(component) end)
        end
        return err == nil
    end

    -- Abort before touching anything: a half applied write is what produced the
    -- detached hair and the mismatched limbs earlier.
    if not ensureOverride(casterEntity) then
        log("appearance data: SKIPPED (AppearanceOverride could not be created)")
        return
    end

    step("appearance", casterEntity.CharacterCreationAppearance,
        tempEntity.CharacterCreationAppearance, "CharacterCreationAppearance")
    step("bodyType", casterEntity.BodyType, tempEntity.BodyType, "BodyType")

    -- The Race component drives which skeleton / body the game builds, both in the
    -- world and in previews. It has to match the appearance parts, otherwise the new
    -- head cannot anchor to the old body. Racial traits do not come from here (they
    -- come from ProgressionTableUUID and are already stored on the character), and
    -- the original tags are put back right after this call.
    if COPY_RACE_COMPONENT then
        step("race", casterEntity.Race, tempEntity.Race, "Race")
    end

    -- EquipmentRace and friends decide the armour mesh variant, so they have to follow
    -- the new race as well or the preview wears the old body's clothes.
    local tplParts = {}
    for _, key in ipairs(TEMPLATE_VISUAL_KEYS) do
        local value = readTemplateKey(tempEntity, key)
        if value == nil then
            tplParts[#tplParts + 1] = key .. "=n/a"
        else
            tplParts[#tplParts + 1] = key .. "=" .. tostring(writeTemplateKey(casterEntity, key, value))
        end
    end
    report[#report + 1] = "template[" .. table.concat(tplParts, ",") .. "]"

    -- The visual template decides which model/skeleton the game builds for previews.
    -- Cloned but intentionally not replicated, exactly like Appearance Edit Enhanced.
    if COPY_VISUAL_COMPONENT then
        local err = cloneProxy(casterEntity.GameObjectVisual, tempEntity.GameObjectVisual)
        report[#report + 1] = "gameObjectVisual=" .. (err and ("ERR:" .. err) or "ok")
    end

    report[#report + 1] = "override=" .. tostring(syncOverride(casterEntity))

    -- Keep the creation stats in sync: body always, race only when the switch is on.
    -- Race component itself stays untouched so racial traits are preserved.
    if tempEntity.CharacterCreationStats ~= nil and casterEntity.CharacterCreationStats ~= nil then
        local ok = pcall(function()
            casterEntity.CharacterCreationStats.BodyType = tempEntity.CharacterCreationStats.BodyType
            casterEntity.CharacterCreationStats.BodyShape = tempEntity.CharacterCreationStats.BodyShape
            if COPY_CREATION_RACE then
                casterEntity.CharacterCreationStats.Race = tempEntity.CharacterCreationStats.Race
                casterEntity.CharacterCreationStats.SubRace = tempEntity.CharacterCreationStats.SubRace
            end
        end)
        if ok then pcall(function() casterEntity:Replicate("CharacterCreationStats") end) end
        report[#report + 1] = "ccStats=" .. tostring(ok)
    end

    log("appearance data: " .. table.concat(report, " "))
end

---------------------------------------------------------------------------------------------------
-- temporary character cleanup
---------------------------------------------------------------------------------------------------

local function prepareTempRemoval(charRef)
    local g = guid(charRef)
    if g == "" then return end

    pcall(Osi.PROC_GLO_PartyMembers_Remove, charRef, "NULL_" .. NULL_GUID, 1, 0)
    pcall(Osi.MakeNPC, charRef)
    pcall(Osi.SetHasDialog, charRef, 0)
    pcall(Osi.SetOnStage, charRef, 0)
    log("temp character prepared for removal: " .. g)
end

local function finishTempRemoval(charRef)
    local g = guid(charRef)
    if g == "" then return end

    pcall(Osi.PROC_RemoveAllPolymorphs, charRef)
    pcall(Osi.PROC_RemoveAllDialogEntriesForSpeaker, charRef)
    pcall(Osi.SetImmortal, charRef, 0)
    pcall(Osi.Die, charRef, 0, "NULL_" .. NULL_GUID, 0, 0)
    pcall(Osi.PROC_CheckPartyFull)
    log("temp character removed: " .. g)
end

---------------------------------------------------------------------------------------------------
-- state
--
-- Every cast gets its own generation id and every timer carries that id in its
-- name, so a timer left over from an earlier cast can never clear a later one.
---------------------------------------------------------------------------------------------------

local pendingCaster = nil
local pendingTemp = nil
local pendingGen = nil
local genCounter = 0
local lastTempGuid = nil
local cleanupRef = nil

local function clearState(reason)
    if reason then log("state cleared: " .. reason) end
    pendingCaster, pendingTemp, pendingGen = nil, nil, nil
end

local function genOf(name, prefix)
    local s = name:match("^" .. prefix .. "_([%d]+)$")
    if not s then return nil end
    return tonumber(s)
end

local function scheduleApply(delay)
    if pendingGen == nil then return end
    pcall(Osi.TimerLaunch, "RC_APPLY_" .. pendingGen, delay)
end

---------------------------------------------------------------------------------------------------
-- core: apply the look of the temporary character onto the player
---------------------------------------------------------------------------------------------------

local function applyCosmetic()
    local caster, temp = pendingCaster, pendingTemp
    if not caster or not temp then
        log("apply skipped: no pending refs")
        return
    end

    local casterGuid = guid(caster)
    local tempGuid = guid(temp)

    local casterEntity = Ext.Entity.Get(casterGuid)
    local tempEntity = Ext.Entity.Get(tempGuid)
    if not casterEntity or not tempEntity then
        clearState("entity missing")
        return
    end

    -- Never destroy something that is not the character creation result.
    if not looksLikeCreatedPlayer(temp) then
        log("apply aborted: candidate is not a created player character")
        clearState("candidate rejected")
        return
    end

    local okA, userA = pcall(Osi.GetReservedUserID, caster)
    local okB, userB = pcall(Osi.GetReservedUserID, temp)
    if okA and okB and userA ~= userB then
        clearState("different owner")
        return
    end

    local tagsBefore = tagSet(casterEntity)

    pcall(repairCreationRace, casterEntity)

    local raceBefore, raceAfter
    pcall(function()
        raceBefore = casterEntity.CharacterCreationStats and casterEntity.CharacterCreationStats.Race
        raceAfter = tempEntity.CharacterCreationStats and tempEntity.CharacterCreationStats.Race
    end)
    log("race before=" .. tostring(raceBefore) .. " picked=" .. tostring(raceAfter))

    local rule = USE_FULL_RACE and RULE_FULL or RULE_SAFE
    local okTransform = pcall(Osi.Transform, caster, temp, rule)
    log("transform ok=" .. tostring(okTransform) .. " fullRace=" .. tostring(USE_FULL_RACE))

    log("copy voice ok=" .. tostring(copyVoice(tempEntity, casterEntity)))

    if COPY_APPEARANCE_DATA then
        pcall(copyAppearanceData, casterEntity, tempEntity)
    end

    if USE_FULL_RACE then
        log("copy Race component ok=" ..
            tostring(copyComponent(tempEntity, casterEntity, "Race")))
    end

    if tagsBefore then
        local tagsAfter = tagSet(casterEntity) or {}
        local restored = 0
        for tag in pairs(tagsBefore) do
            if not tagsAfter[tag] then
                if pcall(Osi.SetTag, caster, tag) then restored = restored + 1 end
            end
        end
        if restored > 0 then log("restored tags: " .. restored) end
    end

    clearState(nil)
    lastTempGuid = tempGuid
    cleanupRef = temp
    prepareTempRemoval(temp)
    pcall(Osi.TimerLaunch, "RC_CLEANUP", 1500)
    pcall(Osi.MakePlayerActive, caster)

    log("reshape finished for " .. casterGuid)
end

---------------------------------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------------------------------

pcall(function()
    Ext.Osiris.RegisterListener("UsingSpell", 5, "after", function(caster, spell)
        if type(spell) ~= "string" then return end

        if spell ~= SPELL_OPEN then
            -- Self healing: whoever casts any spell gets the menu spell once.
            grantTo(caster)
            return
        end

        if pendingCaster ~= nil then
            log("ignored: another reshape is already in progress")
            return
        end

        genCounter = genCounter + 1
        pendingGen = genCounter
        pendingCaster = caster
        pendingTemp = nil

        log("opening character creation for " .. tostring(caster) .. " (gen " .. pendingGen .. ")")
        local ok, err = pcall(Osi.StartCharacterCreation)
        if not ok then
            clearState(nil)
            log("StartCharacterCreation FAILED: " .. tostring(err))
        else
            pcall(Osi.TimerLaunch, "RC_OPEN_TIMEOUT_" .. pendingGen, OPEN_TIMEOUT_MS)
        end
    end)
end)

pcall(function()
    Ext.Osiris.RegisterListener("CharacterCreationFinished", 0, "before", function()
        if pendingCaster == nil then return end
        log("character creation finished")
        if pendingTemp ~= nil then scheduleApply(1500) end
    end)
end)

pcall(function()
    Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", function(char)
        -- The created character may join before or after CharacterCreationFinished,
        -- so the order of the two events must not matter here.
        if pendingCaster ~= nil and pendingTemp == nil
            and guid(char) ~= guid(pendingCaster)
            and looksLikeCreatedPlayer(char) then
            pendingTemp = char
            log("candidate character joined: " .. tostring(char))
            scheduleApply(2000)
        else
            grantTo(char)
        end
    end)
end)

pcall(function()
    Ext.Osiris.RegisterListener("TimerFinished", 1, "after", function(name)
        local g = genOf(name, "RC_APPLY")
        if g then
            if g == pendingGen then applyCosmetic() end
            return
        end

        g = genOf(name, "RC_OPEN_TIMEOUT")
        if g then
            if g == pendingGen then
                clearState("creation screen opened but never completed")
            end
            return
        end

        if name == "RC_GRANT_RETRY" then
            tryGrant()
        elseif name == "RC_CLEANUP" then
            if cleanupRef ~= nil then
                local ref = cleanupRef
                cleanupRef = nil
                finishTempRemoval(ref)
            end
        end
    end)
end)

pcall(function()
    Ext.Events.SessionLoaded:Subscribe(function()
        log("event: SessionLoaded")
        statsCheck()
        grantAttempts = 0
        tryGrant()
        pcall(repairAllPlayers)
    end)
end)

pcall(function()
    Ext.Events.GameStateChanged:Subscribe(function(e)
        if e.ToState == "Running" then
            grantAttempts = 0
            tryGrant()
            pcall(repairAllPlayers)
        end
    end)
end)

pcall(function()
    Ext.Osiris.RegisterListener("SavegameLoaded", 0, "after", function()
        log("event: SavegameLoaded")
        grantAttempts = 0
        tryGrant()
        pcall(repairAllPlayers)
    end)
end)

pcall(function()
    Ext.Osiris.RegisterListener("CharacterCreationFinished", 0, "after", function()
        statsCheck()
        grantAttempts = 0
        tryGrant()
    end)
end)

pcall(function()
    Ext.Osiris.RegisterListener("Died", 1, "after", function(char)
        -- Only the throwaway character is interesting here; logging every death in
        -- combat would flood the log file.
        local g = guid(char)
        if lastTempGuid ~= nil and g == lastTempGuid then
            log("temp character death event: " .. g)
        end
    end)
end)

log("=== RaceCosmetic ready ===")