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

local creditedKills = {};
local creditedCreatureAt = {};
local nameCreditedAt = {};
local engagedUnits = {};
local pendingDeadUnits = {};
local creatureIDByName = {};
local playerGUIDByName = {};
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

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true;
end

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
	PruneExpired(nameCreditedAt, now, NAME_KILL_WINDOW);
	PruneExpired(engagedUnits, now, ENGAGED_WINDOW);
	PruneExpired(pendingDeadUnits, now, PENDING_DEAD_WINDOW);
	for sessionID, totals in pairs(meterTotals) do
		if not pendingMeterSessions[sessionID] and now - (totals.at or 0) > METER_SESSION_WINDOW then
			meterTotals[sessionID] = nil;
		end
	end
	CapNameCache(creatureIDByName);
	CapNameCache(playerGUIDByName);
end

local function ScheduleRefresh(refreshTypes, reason)
	if refreshTypes then
		Resolvers.ScheduleCriteriaTypesRefresh(refreshTypes, true, 0.15, reason);
	end
end

local function CreditCreatureKill(guid, creatureID, creatureWindow)
	local now = GetTime();
	PruneState(now);
	if guid then
		if creditedKills[guid] and now - creditedKills[guid] < KILL_DEDUPE_WINDOW then
			return false;
		end
		creditedKills[guid] = now;
		engagedUnits[guid] = nil;
		pendingDeadUnits[guid] = nil;
		local blind = nameCreditedAt[creatureID];
		if blind and now - blind.at < blind.window then
			nameCreditedAt[creatureID] = nil;
			return false;
		end
	else
		if creditedCreatureAt[creatureID] and now - creditedCreatureAt[creatureID] < creatureWindow then
			return false;
		end
		nameCreditedAt[creatureID] = { at = now, window = creatureWindow };
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
	if not guid or IsSecret(guid) then
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

local function UnitTargetsPlayerGroup(unit)
	local targetUnit = unit .. "target";
	if not UnitExists(targetUnit) then
		return false;
	end
	return UnitIsUnit(targetUnit, "player") or UnitIsUnit(targetUnit, "pet") or UnitInParty(targetUnit) or UnitInRaid(targetUnit);
end

local function RememberPlayerUnit(unit, guid)
	local name = UnitName(unit);
	if name and not IsSecret(name) and UnitCanAttack("player", unit) then
		playerGUIDByName[name] = guid;
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
	if name and not IsSecret(name) then
		creatureIDByName[name] = creatureID;
	end
	if not UnitCanAttack("player", unit) or UnitIsTapDenied(unit) then
		return false;
	end
	if UnitAffectingCombat(unit) and (UnitTargetsPlayerGroup(unit) or (UnitAffectingCombat("player") and UnitIsUnit(unit, "target"))) then
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
	local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid) or nil;
	if unit and not IsSecret(unit) and UnitExists(unit) then
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
		local creatureID = type(status) == "table" and status.creatureID or nil;
		local health = type(status) == "table" and status.remainingHealthPercent or nil;
		local survived = not IsSecret(health) and (tonumber(health) or 0) > 0;
		if not survived and creatureID and not IsSecret(creatureID) and tonumber(creatureID) and tonumber(creatureID) > 0 then
			recorded = CreditCreatureKill(nil, tonumber(creatureID), KILL_DEDUPE_WINDOW) or recorded;
		end
	end
	return recorded;
end

local function RecordLootSources()
	if not GetNumLootItems or not GetLootSourceInfo then
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
				if not IsSecret(guid) and type(guid) == "string" and not creditedKills[guid] then
					local creatureID = Resolvers.GetCreatureIDFromGUID(guid);
					if creatureID and creatureID ~= 0 then
						local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid) or nil;
						local alive = unit and not IsSecret(unit) and UnitExists(unit) and not UnitIsDead(unit);
						if not alive then
							recorded = CreditCreatureKill(guid, creatureID) or recorded;
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
	for creatureID, creature in pairs(Resolvers.creatures or {}) do
		local name = Achievements.GetClientLocaleText and Achievements.GetClientLocaleText("creatures", creatureID, "name") or creature.name;
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
	return CreditCreatureKill(nil, creatureID, NAME_KILL_WINDOW);
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
	local ctx = Resolvers.BuildKillCombatContext(UnitGUID("player"), nil, playerGUIDByName[name], nil, nil);
	ctx.targetIsPlayer = true;
	ctx.targetIsEnemy = true;
	local refreshTypes;
	Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.KILL_PLAYER, 0);
	if Resolvers.RecordCriteriaEvent(CRITERIA_TYPE.HONORABLE_KILL, 0, ctx) then
		refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.HONORABLE_KILL);
	end
	if ctx.zoneAreaID and Resolvers.RecordCriteriaEvent(CRITERIA_TYPE.KILL_PLAYER_IN_AREA, ctx.zoneAreaID, ctx) then
		refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILL_PLAYER_IN_AREA);
	end
	if Resolvers.RecordCriteriaEvent(CRITERIA_TYPE.KILL_PLAYER_NO_HONOR_CHECK, 0, ctx) then
		refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILL_PLAYER_NO_HONOR_CHECK);
	end
	ScheduleRefresh(refreshTypes, "forever-honor");
	return refreshTypes ~= nil;
end

local baseRecordPlayerSpellcast = Achievements.RecordPlayerSpellcast;
Achievements.RecordPlayerSpellcast = function(unit, castGUID, spellID)
	local handled = baseRecordPlayerSpellcast and baseRecordPlayerSpellcast(unit, castGUID, spellID) or false;
	if (unit and unit ~= "player") or IsSecret(spellID) then
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
	local targetGUID = UnitExists("target") and UnitGUID("target") or nil;
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
	if unit and unit ~= "player" then
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
		if Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.TOTAL_DAMAGE_TAKEN, 0, amount, {}, nil) then
			refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.TOTAL_DAMAGE_TAKEN);
		end
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
RegisterEventSafe("CHAT_MSG_COMBAT_XP_GAIN");
RegisterEventSafe("CHAT_MSG_COMBAT_HONOR_GAIN");
RegisterEventSafe("PLAYER_REGEN_ENABLED");
RegisterEventSafe("DAMAGE_METER_COMBAT_SESSION_UPDATED");
RegisterEventSafe("DAMAGE_METER_RESET");
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_COMBAT", "player");
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
