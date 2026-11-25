-- Forever: combat criteria from unit, loot, chat, death-recap and damage-meter signals.

local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsForeverCriteria.lua");
end

local Resolvers = Achievements.criteriaResolvers;
local Private = Achievements.private;
local CRITERIA_TYPE = Resolvers.criteriaTypes;
local CRITERIA_START_EVENT = Resolvers.criteriaStartEvents;
local CRITERIA_FAIL_EVENT = Resolvers.criteriaFailEvents;

local KILL_DEDUPE_WINDOW = 600;
local NAME_KILL_WINDOW = 5;
local ENGAGED_WINDOW = 300;
local COMBAT_GRACE = 3;
local RECAP_ATTEMPTS = 8;
local RECAP_RETRY_DELAY = 0.25;
local RECAP_MAX_AGE = 30;
local PRUNE_INTERVAL = 60;
local PENDING_DEAD_WINDOW = 30;
local METER_SESSION_WINDOW = 3600;
local NAME_CACHE_LIMIT = 2000;
local GATHER_CAST_WINDOW = 10;
local GATHER_LOOT_WINDOW = 2;
local LOOTED_CORPSE_WINDOW = 3600;
-- A creature credited without a GUID stands for its next GUID credit within `match` s, or within `window` s for a corpse looted or not seen alive since.
local BLIND_XP_LINE = { match = NAME_KILL_WINDOW, window = 600 };
local BLIND_ENCOUNTER = { match = KILL_DEDUPE_WINDOW, window = 3600 };
-- Forever 1.60.1 spells with a SKINNING (true) or PICKPOCKET ("pocket") effect.
local GATHER_LOOT_SPELLS = {
	[921] = "pocket", [5967] = "pocket",
	[8613] = true, [8617] = true, [8618] = true, [10768] = true,
	[1235230] = true, [1235236] = true, [1235244] = true,
};

local creditedKills = {};
local creditedCreatureAt = {};
local blindCredits = {};
local engagedUnits = {};
local pendingDeadUnits = {};
local creatureIDByName = {};
local playerGUIDByName = {};
local playerGUIDByFirstName = {};
local dataCreatureIDByName;
local lastCombatEndedAt = 0;
local lastPruneAt = 0;
local xpGainPatterns;
local honorGainPatterns;
local incomingAuraAssets;
local knownIncomingAuras = {};
local meterTotals = {};
local pendingMeterSessions = {};
local pendingDeath = false;
local gatherCast;
local gatherLootWindow = false;
local lootedCorpses = {};

local IsSecret = Private.IsSecret;

local function PruneExpired(entries, now, window)
	for key, entry in pairs(entries) do
		local at = type(entry) == "table" and entry.at or entry;
		if now - at > (type(entry) == "table" and entry.window or window) then
			entries[key] = nil;
		end
	end
end

local function CapNameCache(cache)
	local count = 0;
	for _ in pairs(cache) do
		count = count + 1;
		if count > NAME_CACHE_LIMIT then
			wipe(cache);
			return;
		end
	end
end

local function PruneState(now)
	if now - lastPruneAt < PRUNE_INTERVAL then
		return;
	end
	lastPruneAt = now;
	PruneExpired(creditedKills, now, KILL_DEDUPE_WINDOW);
	PruneExpired(creditedCreatureAt, now, KILL_DEDUPE_WINDOW);
	for creatureID, tokens in pairs(blindCredits) do
		for index = #tokens, 1, -1 do
			if now - tokens[index].at > tokens[index].window then
				table.remove(tokens, index);
			end
		end
		if #tokens == 0 then
			blindCredits[creatureID] = nil;
		end
	end
	PruneExpired(engagedUnits, now, ENGAGED_WINDOW);
	PruneExpired(pendingDeadUnits, now, PENDING_DEAD_WINDOW);
	PruneExpired(lootedCorpses, now, LOOTED_CORPSE_WINDOW);
	for sessionID, totals in pairs(meterTotals) do
		if not pendingMeterSessions[sessionID] and now - (totals.at or 0) > METER_SESSION_WINDOW then
			meterTotals[sessionID] = nil;
		end
	end
	CapNameCache(creatureIDByName);
	CapNameCache(playerGUIDByName);
	CapNameCache(playerGUIDByFirstName);
end

local function SaveEntries(entries, now, serverNow, window)
	local saved;
	for key, entry in pairs(entries) do
		local at = type(entry) == "table" and entry.at or entry;
		local keep = type(entry) == "table" and entry.window or window;
		if now - at <= keep then
			local savedAt = serverNow - math.floor(now - at);
			saved = saved or {};
			saved[key] = type(entry) == "table" and { at = savedAt, window = keep } or savedAt;
		end
	end
	return saved;
end

local function RestoreEntries(entries, saved, now, serverNow, window)
	if type(saved) ~= "table" then
		return;
	end
	for key, entry in pairs(saved) do
		local savedAt = tonumber(type(entry) == "table" and entry.at or entry);
		local keep = type(entry) == "table" and math.min(tonumber(entry.window) or 0, window) or window;
		if savedAt and entries[key] == nil and serverNow - savedAt <= keep then
			local at = now - math.max(serverNow - savedAt, 0);
			entries[key] = type(entry) == "table" and { at = at, window = keep } or at;
		end
	end
end

local function SaveBlindCredits(now, serverNow)
	local saved;
	for creatureID, tokens in pairs(blindCredits) do
		for _, token in ipairs(tokens) do
			if now - token.at <= token.window then
				saved = saved or {};
				saved[creatureID] = saved[creatureID] or {};
				table.insert(saved[creatureID], { at = serverNow - math.floor(now - token.at), match = token.match, window = token.window });
			end
		end
	end
	return saved;
end

local function RestoreBlindCredits(saved, now, serverNow)
	if type(saved) ~= "table" then
		return;
	end
	for key, tokens in pairs(saved) do
		local creatureID = tonumber(key);
		if creatureID and type(tokens) == "table" and not blindCredits[creatureID] then
			for _, token in ipairs(tokens) do
				local savedAt = type(token) == "table" and tonumber(token.at);
				local window = savedAt and math.min(tonumber(token.window) or 0, BLIND_ENCOUNTER.window);
				if savedAt and serverNow - savedAt <= window then
					blindCredits[creatureID] = blindCredits[creatureID] or {};
					table.insert(blindCredits[creatureID], { at = now - math.max(serverNow - savedAt, 0), match = math.min(tonumber(token.match) or 0, window), window = window });
				end
			end
		end
	end
end

-- Saved as server times: GetTime restarts with the computer.
local function SaveKillCredit()
	local db = rawget(_G, "AchievementsCharacterDB");
	if type(db) ~= "table" then
		return;
	end
	local now, serverNow = GetTime(), GetServerTime();
	local saved = {
		lootedCorpses = SaveEntries(lootedCorpses, now, serverNow, LOOTED_CORPSE_WINDOW),
		creditedKills = SaveEntries(creditedKills, now, serverNow, KILL_DEDUPE_WINDOW),
		creditedCreatureAt = SaveEntries(creditedCreatureAt, now, serverNow, KILL_DEDUPE_WINDOW),
		blindCredits = SaveBlindCredits(now, serverNow),
	};
	db.foreverKillCredit = next(saved) and saved or nil;
end

local function RestoreKillCredit()
	local db = rawget(_G, "AchievementsCharacterDB");
	local saved = type(db) == "table" and db.foreverKillCredit;
	if type(saved) ~= "table" then
		return;
	end
	local now, serverNow = GetTime(), GetServerTime();
	RestoreEntries(lootedCorpses, saved.lootedCorpses, now, serverNow, LOOTED_CORPSE_WINDOW);
	RestoreEntries(creditedKills, saved.creditedKills, now, serverNow, KILL_DEDUPE_WINDOW);
	RestoreEntries(creditedCreatureAt, saved.creditedCreatureAt, now, serverNow, KILL_DEDUPE_WINDOW);
	RestoreBlindCredits(saved.blindCredits, now, serverNow);
end

local function ScheduleRefresh(refreshTypes, reason)
	if refreshTypes then
		Resolvers.ScheduleCriteriaTypesRefresh(refreshTypes, true, 0.15, reason);
	end
end

-- A corpse not seen alive since the token may be its kill; the matching token that ends first is used up.
local function TakeBlindCredit(creatureID, now, fromLoot, aliveAt)
	local tokens = blindCredits[creatureID];
	local pick;
	for index, token in ipairs(tokens or {}) do
		local age = now - token.at;
		local matches = age < token.match or (age < token.window and not (aliveAt and aliveAt > token.at));
		if matches and (not pick or token.at + token.window < tokens[pick].at + tokens[pick].window) then
			pick = index;
		end
	end
	if not pick then
		return false;
	end
	table.remove(tokens, pick);
	if #tokens == 0 then
		blindCredits[creatureID] = nil;
	end
	return true;
end

local function CreditCreatureKill(guid, creatureID, blindSource, fromLoot)
	local now = GetTime();
	PruneState(now);
	if guid then
		if creditedKills[guid] and now - creditedKills[guid] < KILL_DEDUPE_WINDOW then
			return false;
		end
		creditedKills[guid] = now;
		-- A credited corpse never credits from loot again.
		lootedCorpses[guid] = now;
		local engaged = engagedUnits[guid];
		engagedUnits[guid] = nil;
		pendingDeadUnits[guid] = nil;
		if TakeBlindCredit(creatureID, now, fromLoot, engaged and engaged.at) then
			return false;
		end
	else
		if creditedCreatureAt[creatureID] and now - creditedCreatureAt[creatureID] < blindSource.match then
			return false;
		end
		blindCredits[creatureID] = blindCredits[creatureID] or {};
		table.insert(blindCredits[creatureID], { at = now, match = blindSource.match, window = blindSource.window });
	end
	creditedCreatureAt[creatureID] = now;

	local ctx = Resolvers.BuildKillCombatContext(UnitGUID("player"), nil, guid, nil, creatureID);
	local refreshTypes;
	Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.KILL_NPC, creatureID);
	if Resolvers.RecordCombatCriteriaAsset(CRITERIA_TYPE.KILL_NPC, creatureID, 1) then
		refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILL_NPC);
	end
	if Resolvers.RecordCriteriaEvent(CRITERIA_TYPE.KILL_NPC, creatureID, ctx) then
		refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILL_NPC);
	end
	if Resolvers.RecordCriteriaEvent(CRITERIA_TYPE.KILL_ANY_NPC, 0, ctx) then
		refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILL_ANY_NPC);
	end
	ScheduleRefresh(refreshTypes, "forever-kill");
	return true;
end

local function CreatureGUIDForUnit(unit)
	if not unit or not UnitExists(unit) then
		return nil;
	end
	local guid = UnitGUID(unit);
	if IsSecret(guid) or not guid then
		return nil;
	end
	local creatureID = Resolvers.GetCreatureIDFromGUID(guid);
	if not creatureID or creatureID == 0 then
		return nil, nil, guid;
	end
	return guid, creatureID;
end

local function PlayerInCombatRecently()
	return UnitAffectingCombat("player") or (GetTime() - lastCombatEndedAt) < COMBAT_GRACE;
end

local function Readable(value)
	return not IsSecret(value) and value;
end

local function UnitTargetsPlayerGroup(unit)
	local targetUnit = unit .. "target";
	if not UnitExists(targetUnit) then
		return false;
	end
	return Readable(UnitIsUnit(targetUnit, "player")) or Readable(UnitIsUnit(targetUnit, "pet")) or UnitInParty(targetUnit) or Readable(UnitInRaid(targetUnit));
end

local function RememberPlayerUnit(unit, guid)
	local name = UnitName(unit);
	if not IsSecret(name) and name and UnitCanAttack("player", unit) then
		local fullName = Private.UnitFullName(unit);
		if fullName then
			playerGUIDByName[fullName] = guid;
		end
		-- First names of surnamed players are read only when no exact name matches.
		if fullName ~= name then
			playerGUIDByFirstName[name] = guid;
		end
		Resolvers.CacheTargetFacts(guid, unit, nil, nil);
	end
end

local function InspectUnit(unit)
	local guid, creatureID, playerGUID = CreatureGUIDForUnit(unit);
	if not guid then
		if playerGUID and UnitIsPlayer(unit) then
			RememberPlayerUnit(unit, playerGUID);
		end
		return false;
	end
	local now = GetTime();
	if UnitIsDead(unit) then
		if creditedKills[guid] then
			return false;
		end
		if engagedUnits[guid] then
			return CreditCreatureKill(guid, creatureID);
		end
		local hostile = UnitCanAttack("player", unit) or UnitIsEnemy("player", unit);
		if hostile and not UnitIsTapDenied(unit) and PlayerInCombatRecently() then
			pendingDeadUnits[guid] = { creatureID = creatureID, at = now };
		end
		return false;
	end

	local name = UnitName(unit);
	if not IsSecret(name) and name then
		creatureIDByName[name] = creatureID;
	end
	if not UnitCanAttack("player", unit) or UnitIsTapDenied(unit) then
		return false;
	end
	if UnitAffectingCombat(unit) and (UnitTargetsPlayerGroup(unit) or (UnitAffectingCombat("player") and Readable(UnitIsUnit(unit, "target")))) then
		engagedUnits[guid] = { creatureID = creatureID, at = now };
		Resolvers.CacheTargetFacts(guid, unit, nil, creatureID);
	end
	return false;
end

local function InspectUnitSafe(unit)
	local ok, result = pcall(InspectUnit, unit);
	return ok and result or false;
end

local function HandleUnitDied(guid)
	if IsSecret(guid) or type(guid) ~= "string" or creditedKills[guid] then
		return false;
	end
	local creatureID = Resolvers.GetCreatureIDFromGUID(guid);
	if not creatureID or creatureID == 0 then
		return false;
	end
	local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid);
	if not IsSecret(unit) and unit and UnitExists(unit) then
		return InspectUnitSafe(unit);
	end
	local engaged = engagedUnits[guid];
	if engaged and (GetTime() - engaged.at) <= ENGAGED_WINDOW then
		return CreditCreatureKill(guid, engaged.creatureID);
	end
	return false;
end

local function RecordEncounterUnits(_, success, encounterUnitStatus)
	if (success ~= 1 and success ~= true) or type(encounterUnitStatus) ~= "table" then
		return false;
	end
	local recorded = false;
	for _, status in ipairs(encounterUnitStatus) do
		local creatureID = type(status) == "table" and status.creatureID;
		local health = type(status) == "table" and status.remainingHealthPercent;
		local survived = not IsSecret(health) and (tonumber(health) or 0) > 0;
		if not survived and not IsSecret(creatureID) and creatureID and tonumber(creatureID) and tonumber(creatureID) > 0 then
			recorded = CreditCreatureKill(nil, tonumber(creatureID), BLIND_ENCOUNTER) or recorded;
		end
	end
	return recorded;
end

local function NoteGatherCast(unit, castGUID, spellID, succeeded)
	local kind = IsSecret(spellID) and "secret" or GATHER_LOOT_SPELLS[tonumber(spellID) or 0];
	if (not IsSecret(unit) and unit and unit ~= "player") or not kind then
		return;
	end
	castGUID = Readable(castGUID) or nil;
	local expires = GetTime() + (succeeded and GATHER_LOOT_WINDOW or GATHER_CAST_WINDOW);
	local cast = gatherCast;
	-- A known gather cast keeps its SENT/START window when SUCCEEDED comes.
	if cast and kind ~= "secret" and kind == cast.kind and castGUID == cast.castGUID and (castGUID or not cast.looted) then
		cast.succeeded = cast.succeeded or succeeded;
		cast.expires = math.max(cast.expires, expires);
		return;
	end
	if cast and cast.looted and castGUID and castGUID == cast.castGUID then
		return;
	end
	-- A live mark whose window has not opened stays behind the new mark until that cast succeeds.
	local live = cast and not cast.looted and GetTime() <= cast.expires and cast;
	local carried = cast and not cast.succeeded and cast.previous;
	local previous = (carried and not carried.looted and GetTime() <= carried.expires and carried) or live or nil;
	if previous then
		previous.previous = nil;
	end
	gatherCast = { castGUID = castGUID, expires = expires, succeeded = succeeded, kind = kind, previous = previous };
end

local function EndGatherCast(castGUID)
	if not gatherCast or IsSecret(castGUID) or not castGUID then
		return;
	end
	local previous = gatherCast.previous;
	if not gatherCast.succeeded and castGUID == gatherCast.castGUID then
		gatherCast = previous;
	elseif previous and not previous.succeeded and castGUID == previous.castGUID then
		gatherCast.previous = nil;
	end
end

local function IsGatherLootWindow()
	local cast = gatherCast;
	local kind = cast and cast.kind;
	local previous = cast and not cast.succeeded and cast.previous;
	if previous and not previous.looted and GetTime() <= previous.expires then
		-- The window may be either cast's; the stricter kind wins.
		kind = (kind == true or previous.kind == true) or ((kind == "secret" or previous.kind == "secret") and "secret" or "pocket");
		cast = previous;
	end
	if not gatherLootWindow and cast and not cast.looted and GetTime() <= cast.expires then
		cast.looted = true;
		gatherLootWindow = kind;
	end
	return gatherLootWindow;
end

local function RecordLootSources()
	if not GetNumLootItems or not GetLootSourceInfo then
		return false;
	end
	local gathering = IsGatherLootWindow();
	if gathering == "secret" then
		return false;
	end
	local recorded = false;
	for slot = 1, GetNumLootItems() do
		local ok, sources = pcall(function()
			return { GetLootSourceInfo(slot) };
		end);
		if ok then
			for index = 1, #sources, 2 do
				local guid = sources[index];
				if not IsSecret(guid) and type(guid) == "string" then
					local creatureID = Resolvers.GetCreatureIDFromGUID(guid);
					if creatureID and creatureID ~= 0 then
						local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid);
						local seen = not IsSecret(unit) and unit and UnitExists(unit);
						local alive = seen and not UnitIsDead(unit);
						-- Pick-pocket victims are alive; a corpse looted once never credits from loot again.
						if not alive and (seen or gathering ~= "pocket") then
							if gathering ~= true and not creditedKills[guid] and not lootedCorpses[guid] then
								recorded = CreditCreatureKill(guid, creatureID, nil, true) or recorded;
							end
							lootedCorpses[guid] = GetTime();
						end
					end
				end
			end
		end
	end
	return recorded;
end

local function BuildMessagePatterns(globalNames)
	local patterns = {};
	for _, globalName in ipairs(globalNames) do
		local pattern = Resolvers.BuildChatFormatPattern(_G[globalName]);
		if pattern then
			patterns[#patterns + 1] = pattern;
		end
	end
	return patterns;
end

local XP_GAIN_GLOBALS = {
	"COMBATLOG_XPGAIN_FIRSTPERSON",
	"COMBATLOG_XPGAIN_FIRSTPERSON_GROUP",
	"COMBATLOG_XPGAIN_FIRSTPERSON_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION1",
	"COMBATLOG_XPGAIN_EXHAUSTION1_GROUP",
	"COMBATLOG_XPGAIN_EXHAUSTION1_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION2",
	"COMBATLOG_XPGAIN_EXHAUSTION2_GROUP",
	"COMBATLOG_XPGAIN_EXHAUSTION2_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION4",
	"COMBATLOG_XPGAIN_EXHAUSTION4_GROUP",
	"COMBATLOG_XPGAIN_EXHAUSTION4_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION5",
	"COMBATLOG_XPGAIN_EXHAUSTION5_GROUP",
	"COMBATLOG_XPGAIN_EXHAUSTION5_RAID",
};

local HONOR_GAIN_GLOBALS = {
	"COMBATLOG_HONORGAIN",
	"COMBATLOG_HONORGAIN_NO_RANK",
	"COMBATLOG_HONORGAIN_EXHAUSTION1",
	"COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1",
};

local function MatchVictimName(message, patterns)
	if type(message) ~= "string" then
		return nil;
	end
	for _, pattern in ipairs(patterns) do
		local name = string.match(message, pattern);
		if name and name ~= "" then
			return name;
		end
	end
	return nil;
end

local function GetDataCreatureIDByName()
	if dataCreatureIDByName then
		return dataCreatureIDByName;
	end
	dataCreatureIDByName = {};
	if not Resolvers.IsEnglishClientLocale() then
		return dataCreatureIDByName;
	end
	for _, criteria in ipairs(Resolvers.GetRecordableCriteriaByType(CRITERIA_TYPE.KILL_NPC)) do
		local creatureID = tonumber(criteria.asset) or 0;
		local name = creatureID ~= 0 and Achievements.GetClientLocaleText and Achievements.GetClientLocaleText("creatures", creatureID, "name");
		if type(name) == "string" and name ~= "" then
			dataCreatureIDByName[name] = creatureID;
		end
	end
	return dataCreatureIDByName;
end

local function CreditConfirmedKill(creatureID)
	local now = GetTime();
	local confirmedGUID, confirmedAt;
	for guid, pending in pairs(pendingDeadUnits) do
		if pending.creatureID == creatureID and now - pending.at <= PENDING_DEAD_WINDOW and (not confirmedAt or pending.at > confirmedAt) then
			confirmedGUID, confirmedAt = guid, pending.at;
		end
	end
	if confirmedGUID then
		return CreditCreatureKill(confirmedGUID, creatureID);
	end
	return CreditCreatureKill(nil, creatureID, BLIND_XP_LINE);
end

local function RecordXPGainKill(message)
	xpGainPatterns = xpGainPatterns or BuildMessagePatterns(XP_GAIN_GLOBALS);
	local name = MatchVictimName(message, xpGainPatterns);
	if not name then
		return false;
	end
	local creatureID = creatureIDByName[name] or GetDataCreatureIDByName()[name];
	if not creatureID then
		return false;
	end
	C_Timer.After(1, function()
		pcall(CreditConfirmedKill, creatureID);
	end);
	return true;
end

local function RecordHonorGainKill(message)
	honorGainPatterns = honorGainPatterns or BuildMessagePatterns(HONOR_GAIN_GLOBALS);
	local name = MatchVictimName(message, honorGainPatterns);
	if not name then
		return false;
	end
	name = Private.NormaliseForeverName(name) or name;
	local ctx = Resolvers.BuildKillCombatContext(UnitGUID("player"), nil, playerGUIDByName[name] or playerGUIDByFirstName[name], nil, nil);
	ctx.targetIsPlayer = true;
	ctx.targetIsEnemy = true;
	local refreshTypes;
	Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.KILL_PLAYER, 0);
	if Resolvers.RecordCriteriaEvent(CRITERIA_TYPE.HONORABLE_KILL, 0, ctx) then
		refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.HONORABLE_KILL);
	end
	refreshTypes = Resolvers.RecordKillInPlayerArea(refreshTypes, ctx);
	if Resolvers.RecordCriteriaEvent(CRITERIA_TYPE.KILL_PLAYER_NO_HONOR_CHECK, 0, ctx) then
		refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILL_PLAYER_NO_HONOR_CHECK);
	end
	ScheduleRefresh(refreshTypes, "forever-honor");
	return refreshTypes ~= nil;
end

local baseRecordPlayerSpellcast = Achievements.RecordPlayerSpellcast;
Achievements.RecordPlayerSpellcast = function(unit, castGUID, spellID)
	local handled = baseRecordPlayerSpellcast and baseRecordPlayerSpellcast(unit, castGUID, spellID) or false;
	NoteGatherCast(unit, castGUID, spellID, true);
	if IsSecret(unit) or IsSecret(spellID) or (unit and unit ~= "player") then
		return handled;
	end
	spellID = tonumber(spellID) or 0;
	if spellID == 0 then
		return handled;
	end

	Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.CAST_SPELL, spellID);
	Resolvers.RecordCriteriaFail(CRITERIA_FAIL_EVENT.CAST_SPELL, spellID);
	local refreshTypes;
	if Resolvers.RecordCombatCriteriaAsset(CRITERIA_TYPE.CAST_SPELL, spellID, 1, 0.05) then
		refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.CAST_SPELL);
	end
	local targetGUID = UnitGUID("target");
	if IsSecret(targetGUID) then
		targetGUID = nil;
	end
	local ctx = Resolvers.BuildKillCombatContext(UnitGUID("player"), nil, targetGUID, nil, Resolvers.GetCreatureIDFromGUID(targetGUID));
	if Resolvers.RecordCriteriaEvent(CRITERIA_TYPE.CAST_SPELL, spellID, ctx, "cast-" .. tostring(spellID)) then
		refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.CAST_SPELL);
	end
	if targetGUID and Resolvers.RecordCriteriaEvent(CRITERIA_TYPE.LAND_TARGETED_SPELL, spellID, ctx) then
		refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.LAND_TARGETED_SPELL);
	end
	ScheduleRefresh(refreshTypes, "forever-cast");
	return handled or refreshTypes ~= nil;
end;

local function GetIncomingAuraAssets()
	if incomingAuraAssets then
		return incomingAuraAssets;
	end
	incomingAuraAssets = {};
	for _, criteria in ipairs(Resolvers.GetRecordableCriteriaByType(CRITERIA_TYPE.HAVE_SPELL_CAST_ON_YOU)) do
		local spellID = tonumber(criteria.asset) or 0;
		if spellID ~= 0 then
			incomingAuraAssets[spellID] = true;
		end
	end
	return incomingAuraAssets;
end

local baseRecordPlayerAuraCriteria = Achievements.RecordPlayerAuraCriteria;
Achievements.RecordPlayerAuraCriteria = function(unit)
	local handled = baseRecordPlayerAuraCriteria and baseRecordPlayerAuraCriteria(unit) or false;
	if IsSecret(unit) or (unit and unit ~= "player") then
		return handled;
	end
	local assets = GetIncomingAuraAssets();
	if next(assets) == nil then
		return handled;
	end
	local auraSpellIDs = Resolvers.BuildPlayerAuraSnapshot("player").spellIDs or {};
	local refreshTypes;
	for spellID in pairs(assets) do
		local hasAura = auraSpellIDs[spellID] == true;
		if hasAura and not knownIncomingAuras[spellID] then
			Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.HAVE_SPELL_CAST_ON_YOU, spellID);
			Resolvers.RecordCriteriaFail(CRITERIA_FAIL_EVENT.HAVE_SPELL_CAST_ON_YOU, spellID);
			if Resolvers.RecordCombatCriteriaAsset(CRITERIA_TYPE.HAVE_SPELL_CAST_ON_YOU, spellID, 1, 0.2) then
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.HAVE_SPELL_CAST_ON_YOU);
			end
			local ctx = Resolvers.BuildKillCombatContext(nil, nil, UnitGUID("player"), nil, nil);
			ctx.targetIsPlayer = true;
			if Resolvers.RecordCriteriaEvent(CRITERIA_TYPE.HAVE_SPELL_CAST_ON_YOU, spellID, ctx, "incoming-" .. tostring(spellID)) then
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.HAVE_SPELL_CAST_ON_YOU);
			end
		end
		knownIncomingAuras[spellID] = hasAura;
	end
	ScheduleRefresh(refreshTypes, "forever-incoming-aura");
	return handled or refreshTypes ~= nil;
end;

local function NormalizeEnvironmentalType(environmentalType)
	if type(environmentalType) ~= "string" or environmentalType == "" then
		return nil;
	end
	return string.upper(string.sub(environmentalType, 1, 1)) .. string.lower(string.sub(environmentalType, 2));
end

local function ApplyDeathRecap()
	if not C_DeathRecap or not C_DeathRecap.HasRecapEvents or not C_DeathRecap.GetRecapEvents then
		return false;
	end
	local ok, hasEvents = pcall(C_DeathRecap.HasRecapEvents);
	if not ok or hasEvents ~= true then
		return false;
	end
	local okEvents, events = pcall(C_DeathRecap.GetRecapEvents);
	if not okEvents or type(events) ~= "table" or type(events[1]) ~= "table" then
		return false;
	end
	local killingBlow = events[1];
	local timestamp = killingBlow.timestamp;
	if IsSecret(timestamp) or type(timestamp) ~= "number" or math.abs(GetServerTime() - timestamp) > RECAP_MAX_AGE then
		return false;
	end

	local eventName = killingBlow.event;
	local sourceGUID = killingBlow.sourceGUID;
	if IsSecret(eventName) then
		eventName = nil;
	end
	if IsSecret(sourceGUID) then
		sourceGUID = nil;
	end
	if eventName == "ENVIRONMENTAL_DAMAGE" then
		local environmentalType = killingBlow.environmentalType;
		if not IsSecret(environmentalType) then
			Resolvers.RecordEnvironmentalDamage(NormalizeEnvironmentalType(environmentalType));
		end
	elseif type(sourceGUID) == "string" then
		if Resolvers.GetCreatureIDFromGUID(sourceGUID) then
			Resolvers.RecordRecentPlayerDamageSource(sourceGUID, nil);
		elseif string.find(sourceGUID, "^Player%-") then
			Private.state = Private.state or {};
			Private.state.lastPlayerDamagePlayer = {
				at = Resolvers.GetNow(),
				sourceGUID = sourceGUID,
				destGUID = UnitGUID("player"),
				sourceIsEnemy = true,
			};
		end
	end
	return true;
end

local baseRecordPlayerDeath = Achievements.RecordPlayerDeath;
Achievements.RecordPlayerDeath = function()
	if pendingDeath then
		return false;
	end
	pendingDeath = true;
	local attempt = 0;
	local function finish()
		pendingDeath = false;
		return baseRecordPlayerDeath();
	end
	local function try()
		attempt = attempt + 1;
		local ok, applied = pcall(ApplyDeathRecap);
		if (ok and applied) or attempt >= RECAP_ATTEMPTS or not UnitIsDeadOrGhost("player") then
			finish();
		else
			C_Timer.After(RECAP_RETRY_DELAY, try);
		end
	end
	try();
	return true;
end;

local METER_CRITERIA_BY_TYPE;
local function GetMeterCriteriaByType()
	if METER_CRITERIA_BY_TYPE then
		return METER_CRITERIA_BY_TYPE;
	end
	METER_CRITERIA_BY_TYPE = {};
	if Enum and Enum.DamageMeterType then
		METER_CRITERIA_BY_TYPE[Enum.DamageMeterType.DamageDone] = CRITERIA_TYPE.DAMAGE_DEALT;
		METER_CRITERIA_BY_TYPE[Enum.DamageMeterType.HealingDone] = CRITERIA_TYPE.HEALING_DONE;
		METER_CRITERIA_BY_TYPE[Enum.DamageMeterType.DamageTaken] = CRITERIA_TYPE.TOTAL_DAMAGE_TAKEN;
	end
	return METER_CRITERIA_BY_TYPE;
end

local function ReadMeterSession(sessionID, meterType)
	local criteriaType = GetMeterCriteriaByType()[meterType];
	if not criteriaType or not C_DamageMeter or not C_DamageMeter.GetCombatSessionFromID then
		return true;
	end
	local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, meterType);
	if not ok or type(session) ~= "table" or type(session.combatSources) ~= "table" then
		return true;
	end
	for _, source in ipairs(session.combatSources) do
		if type(source) == "table" and source.isLocalPlayer == true then
			local total = source.totalAmount;
			if IsSecret(total) then
				return false;
			end
			total = tonumber(total) or 0;
			local totals = meterTotals[sessionID] or {};
			meterTotals[sessionID] = totals;
			totals.at = GetTime();
			local delta = total - (totals[meterType] or 0);
			if delta > 0 then
				totals[meterType] = total;
				if Resolvers.RecordCriteriaProgress(criteriaType, 0, delta, {}, nil) then
					Resolvers.ScheduleCriteriaTypesRefresh(Resolvers.MarkCriteriaRefreshType(nil, criteriaType), true, 0.75, "forever-damage-meter");
				end
			end
			return true;
		end
	end
	return true;
end

local function HandleMeterSessionUpdate(meterType, sessionID)
	if IsSecret(meterType) or IsSecret(sessionID) or not sessionID or sessionID == 0 or not GetMeterCriteriaByType()[meterType] then
		return;
	end
	if UnitAffectingCombat("player") or not ReadMeterSession(sessionID, meterType) then
		pendingMeterSessions[sessionID] = pendingMeterSessions[sessionID] or {};
		pendingMeterSessions[sessionID][meterType] = true;
	end
end

local function FlushPendingMeterSessions()
	if UnitAffectingCombat("player") then
		return;
	end
	for sessionID, meterTypes in pairs(pendingMeterSessions) do
		for meterType in pairs(meterTypes) do
			if ReadMeterSession(sessionID, meterType) then
				meterTypes[meterType] = nil;
			end
		end
		if next(meterTypes) == nil then
			pendingMeterSessions[sessionID] = nil;
		end
	end
end

local function RecordPlayerCombatText(unit, action, amount)
	if unit ~= "player" or IsSecret(action) or IsSecret(amount) then
		return false;
	end
	amount = tonumber(amount) or 0;
	if amount <= 0 then
		return false;
	end
	local characterName = Resolvers.GetProgressCharacterName();
	local refreshTypes;
	if action == "WOUND" then
		if Resolvers.SetCriteriaAssetProgressMax(CRITERIA_TYPE.MOST_DAMAGE_TAKEN_IN_SINGLE_HIT, 0, amount, characterName) then
			refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.MOST_DAMAGE_TAKEN_IN_SINGLE_HIT);
		end
	elseif action == "HEAL" then
		if Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.TOTAL_HEALING_RECEIVED, 0, amount, {}, nil) then
			refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.TOTAL_HEALING_RECEIVED);
		end
		if Resolvers.SetCriteriaAssetProgressMax(CRITERIA_TYPE.LARGEST_HEAL_RECEIVED, 0, amount, characterName) then
			refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.LARGEST_HEAL_RECEIVED);
		end
	end
	if refreshTypes then
		Resolvers.ScheduleCriteriaTypesRefresh(refreshTypes, true, 0.75, "forever-combat-text");
	end
	return refreshTypes ~= nil;
end

local eventFrame = CreateFrame("Frame");

local function RegisterEventSafe(event)
	return pcall(eventFrame.RegisterEvent, eventFrame, event);
end

RegisterEventSafe("ENCOUNTER_END");
RegisterEventSafe("PLAYER_TARGET_CHANGED");
RegisterEventSafe("PLAYER_FOCUS_CHANGED");
RegisterEventSafe("UPDATE_MOUSEOVER_UNIT");
RegisterEventSafe("NAME_PLATE_UNIT_ADDED");
RegisterEventSafe("UNIT_DIED");
RegisterEventSafe("LOOT_READY");
RegisterEventSafe("LOOT_OPENED");
RegisterEventSafe("LOOT_CLOSED");
RegisterEventSafe("CHAT_MSG_COMBAT_XP_GAIN");
RegisterEventSafe("CHAT_MSG_COMBAT_HONOR_GAIN");
RegisterEventSafe("PLAYER_REGEN_ENABLED");
RegisterEventSafe("DAMAGE_METER_COMBAT_SESSION_UPDATED");
RegisterEventSafe("DAMAGE_METER_RESET");
RegisterEventSafe("ADDON_LOADED");
RegisterEventSafe("PLAYER_LOGOUT");
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_COMBAT", "player");
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_SPELLCAST_SENT", "player");
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_SPELLCAST_START", "player");
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_SPELLCAST_FAILED", "player");
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_SPELLCAST_FAILED_QUIET", "player");
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_SPELLCAST_INTERRUPTED", "player");
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_HEALTH", "target", "focus");
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_FLAGS", "target", "focus");
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_TARGET", "target", "focus");

local function IsWatchedUnit(unit)
	return unit == "target" or unit == "focus" or unit == "mouseover" or (type(unit) == "string" and string.sub(unit, 1, 9) == "nameplate");
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4, arg5, arg6)
	if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" or event == "NAME_PLATE_UNIT_ADDED" then
		if IsWatchedUnit(arg1) then
			InspectUnitSafe(arg1);
		end
	elseif event == "UNIT_TARGET" then
		if arg1 == "target" or arg1 == "focus" then
			InspectUnitSafe(arg1 .. "target");
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		InspectUnitSafe("target");
	elseif event == "PLAYER_FOCUS_CHANGED" then
		InspectUnitSafe("focus");
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		InspectUnitSafe("mouseover");
	elseif event == "UNIT_DIED" then
		pcall(HandleUnitDied, arg1);
	elseif event == "UNIT_COMBAT" then
		pcall(RecordPlayerCombatText, arg1, arg2, arg4);
	elseif event == "ENCOUNTER_END" then
		pcall(RecordEncounterUnits, arg1, arg5, arg6);
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		pcall(RecordLootSources);
	elseif event == "LOOT_CLOSED" then
		gatherLootWindow = false;
	elseif event == "UNIT_SPELLCAST_SENT" then
		NoteGatherCast(arg1, arg3, arg4, false);
	elseif event == "UNIT_SPELLCAST_START" then
		NoteGatherCast(arg1, arg2, arg3, false);
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		EndGatherCast(arg2);
	elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
		pcall(RecordXPGainKill, arg1);
	elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
		pcall(RecordHonorGainKill, arg1);
	elseif event == "PLAYER_REGEN_ENABLED" then
		lastCombatEndedAt = GetTime();
		C_Timer.After(1, FlushPendingMeterSessions);
	elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
		pcall(HandleMeterSessionUpdate, arg1, arg2);
	elseif event == "DAMAGE_METER_RESET" then
		meterTotals = {};
		pendingMeterSessions = {};
	elseif event == "ADDON_LOADED" then
		if arg1 == "Achievements" then
			pcall(RestoreKillCredit);
		end
	elseif event == "PLAYER_LOGOUT" then
		pcall(SaveKillCredit);
	end
end);

Achievements.foreverCriteria = {
	CreditCreatureKill = CreditCreatureKill,
	InspectUnit = InspectUnitSafe,
	RecordLootSources = RecordLootSources,
	RecordXPGainKill = RecordXPGainKill,
	RecordHonorGainKill = RecordHonorGainKill,
	FlushPendingMeterSessions = FlushPendingMeterSessions,
};
