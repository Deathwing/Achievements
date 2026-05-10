-- AchievementsCompare.lua
--
-- Whisper-based achievement comparison between two players running this
-- addon. Native Classic clients have no built-in comparison protocol, so we
-- exchange completion lists over the addon channel ("ACHV" prefix, distinct
-- message types) and report the diff to the requesting player's chat.
--
--   Sender                                 Receiver
--   ------                                 --------
--   CMP_REQ\tversion          ----WHISPER---->   queue response
--                             <---WHISPER----    CMP_BEG\tversion\tcount\tpoints
--                             <---WHISPER----    CMP_PRT\tchunk
--                             <---WHISPER----    CMP_PRT\tchunk
--                             <---WHISPER----    CMP_STS\tchunk
--                             <---WHISPER----    CMP_END
--   print diff to chat
--
-- Each chunk is a `;`-separated list of `id:ts` pairs (timestamp may be
-- omitted as just `id` when the saved state has no timestamp). Chunks are kept
-- below 230 bytes so they fit comfortably under the 255-byte addon-message
-- payload cap.
-- Statistic chunks use `id:transport` entries. The transport value is produced
-- by Achievements.GetStatisticTransportString and kept compact so money texture
-- strings are formatted locally instead of crossing the addon-message channel.

local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsCompare.lua");
end

local Private = Achievements.private;

local ADDON_PREFIX = "ACHV";
local PROTOCOL_VERSION = "2";
local CHUNK_SOFT_LIMIT = 230;
local REQUEST_TIMEOUT_SECONDS = 15;
local DUPLICATE_REQUEST_WINDOW_SECONDS = 3;
-- If we don't see a CMP_BEG (the first response packet) within this window
-- we assume the target either doesn't have the addon or never replied. We
-- finalise the comparison anyway, treating their data as 0 achievements,
-- so the user sees the result quickly instead of waiting for the full
-- REQUEST_TIMEOUT_SECONDS no-response message.
local NO_RESPONSE_FAST_FINALISE_SECONDS = 1;

local prefixRegistered;
local listenerFrame;
local pendingRequests = {};      -- normalisedTargetName -> { startTime, target, expectedCount, points, completed, statistics }
local lastRequestTimes = {};     -- normalisedTargetName -> last outgoing CMP_REQ timestamp

local function StripRealmSuffix(name)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	return name:match("^([^%-]+)") or name;
end

local function NameIncludesRealm(name)
	return type(name) == "string" and name:find("%-") ~= nil;
end

local function DebugValue(value)
	if value == nil then
		return "nil";
	end
	return tostring(value);
end

local function DebugCompare(message)
	if Private and Private.DebugMessage then
		Private.DebugMessage("compare: " .. tostring(message));
	end
end

local function NormaliseName(name, preserveRealm)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	if preserveRealm then
		local ambiguousName = Ambiguate(name, "none");
		if ambiguousName and ambiguousName ~= "" and NameIncludesRealm(ambiguousName) then
			return ambiguousName;
		end
		return name;
	end
	local ambiguousName = Ambiguate(name, "short");
	if ambiguousName and ambiguousName ~= "" then
		return StripRealmSuffix(ambiguousName);
	end
	return StripRealmSuffix(name);
end

local function GetPendingRequestKey(name, hasRealm)
	local key = NormaliseName(name, hasRealm == true);
	if key and not hasRealm then
		return string.lower(key);
	end
	return key;
end

local function GetLocalRealmName()
	local realmName = GetRealmName();
	if realmName and realmName ~= "" then
		return realmName;
	end
	realmName = GetNormalizedRealmName();
	if realmName and realmName ~= "" then
		return realmName;
	end
	local _, unitRealmName = UnitFullName("player");
	if unitRealmName and unitRealmName ~= "" then
		return unitRealmName;
	end
	return nil;
end

local function RememberKnownPlayerName(name)
	if Achievements.RememberKnownPlayerName then
		return Achievements.RememberKnownPlayerName(name);
	end
	return nil;
end

local function GetKnownPlayerFullName(name)
	if Achievements.GetKnownPlayerFullName then
		return Achievements.GetKnownPlayerFullName(name);
	end
	return name, NameIncludesRealm(name);
end

local function ExpandKnownPlayerName(name)
	local expandedName, expandedHasRealm = GetKnownPlayerFullName(name);
	if expandedName and expandedName ~= name then
		DebugCompare("known player expanded name=" .. DebugValue(name) .. " full=" .. DebugValue(expandedName));
	end
	return expandedName, expandedHasRealm == true;
end

local ResolveTargetFromUnit;

local function ResolveTargetFromGUIDValue(guid, fallbackName)
	if type(guid) ~= "string" or guid == "" then
		return nil;
	end
	local ok, _, _, _, _, _, playerName, realmName = pcall(GetPlayerInfoByGUID, guid);
	if ok and playerName and playerName ~= "" and NameIncludesRealm(playerName) then
		local target = NormaliseName(playerName, true);
		DebugCompare("unit guid resolved full playerName guid=" .. DebugValue(guid) .. " target=" .. DebugValue(target));
		RememberKnownPlayerName(target);
		return target, true;
	end
	if ok and playerName and playerName ~= "" and realmName and realmName ~= "" then
		local target = playerName .. "-" .. realmName;
		DebugCompare("unit guid resolved guid=" .. DebugValue(guid) .. " target=" .. DebugValue(target));
		RememberKnownPlayerName(target);
		return target, true;
	end
	DebugCompare("unit guid player info no realm guid=" .. DebugValue(guid) .. " ok=" .. DebugValue(ok) .. " playerName=" .. DebugValue(playerName) .. " realmName=" .. DebugValue(realmName) .. " fallback=" .. DebugValue(fallbackName));
	local realmID = guid:match("^Player%-(%d+)%-");
	if realmID and C_RealmInfo and C_RealmInfo.GetRealmInfo then
		local ok, realmInfo = pcall(C_RealmInfo.GetRealmInfo, tonumber(realmID));
		local realmName = ok and realmInfo and (realmInfo.realmName or realmInfo.name or realmInfo.normalizedRealmName);
		local playerName = fallbackName;
		if playerName and playerName ~= "" and realmName and realmName ~= "" then
			local target = playerName .. "-" .. realmName;
			DebugCompare("unit guid realm resolved guid=" .. DebugValue(guid) .. " realmID=" .. DebugValue(realmID) .. " target=" .. DebugValue(target));
			RememberKnownPlayerName(target);
			return target, true;
		end
		DebugCompare("unit guid realm lookup no target guid=" .. DebugValue(guid) .. " realmID=" .. DebugValue(realmID) .. " ok=" .. DebugValue(ok) .. " realmName=" .. DebugValue(realmName) .. " fallback=" .. DebugValue(fallbackName));
	end
	return nil;
end

local function ResolveTargetFromGUID(unit, fallbackName)
	if not unit then
		return nil;
	end
	local guid = UnitGUID(unit);
	if not guid or guid == "" then
		DebugCompare("unit guid missing unit=" .. DebugValue(unit) .. " fallback=" .. DebugValue(fallbackName));
		return nil;
	end
	return ResolveTargetFromGUIDValue(guid, fallbackName or UnitName(unit));
end

local function ResolveTargetFromPlayerLocation(playerLocation, fallbackName)
	if type(playerLocation) ~= "table" then
		return nil;
	end
	local guid;
	if type(playerLocation.GetGUID) == "function" then
		local ok, value = pcall(playerLocation.GetGUID, playerLocation);
		if ok then
			guid = value;
		end
	end
	guid = guid or playerLocation.guid or playerLocation.playerGUID or playerLocation.GUID;
	if guid then
		DebugCompare("playerLocation guid=" .. DebugValue(guid));
		return ResolveTargetFromGUIDValue(guid, fallbackName);
	end
	local unit;
	if type(playerLocation.GetUnit) == "function" then
		local ok, value = pcall(playerLocation.GetUnit, playerLocation);
		if ok then
			unit = value;
		end
	end
	unit = unit or playerLocation.unit or playerLocation.unitToken;
	if unit then
		DebugCompare("playerLocation unit=" .. DebugValue(unit));
		return ResolveTargetFromUnit(unit);
	end
	DebugCompare("playerLocation no guid or unit fallback=" .. DebugValue(fallbackName) .. " hasGetGUID=" .. DebugValue(type(playerLocation.GetGUID) == "function") .. " hasGetUnit=" .. DebugValue(type(playerLocation.GetUnit) == "function"));
	return nil;
end

local function ResolveTargetFromLocalRealm(shortName, unit)
	if not shortName or shortName == "" then
		return nil;
	end
	local relationship = unit and UnitRealmRelationship(unit) or nil;
	if relationship and relationship ~= LE_REALM_RELATION_SAME then
		DebugCompare("unit local realm fallback skipped unit=" .. DebugValue(unit) .. " short=" .. DebugValue(shortName) .. " relationship=" .. DebugValue(relationship));
		return nil;
	end
	local realmName = GetLocalRealmName();
	if realmName and realmName ~= "" then
		local target = shortName .. "-" .. realmName;
		DebugCompare("unit local realm fallback unit=" .. DebugValue(unit) .. " short=" .. DebugValue(shortName) .. " realm=" .. DebugValue(realmName) .. " relationship=" .. DebugValue(relationship) .. " target=" .. DebugValue(target));
		RememberKnownPlayerName(target);
		return target, true;
	end
	DebugCompare("unit local realm fallback missing realm unit=" .. DebugValue(unit) .. " short=" .. DebugValue(shortName) .. " relationship=" .. DebugValue(relationship));
	return nil;
end

ResolveTargetFromUnit = function(unit)
	if not unit then
		return nil;
	end
	local shortName;
	local fullName, fullRealm = UnitFullName(unit);
	if fullName and fullName ~= "" then
		if fullRealm and fullRealm ~= "" then
			return fullName .. "-" .. fullRealm, true;
		end
		shortName = fullName;
	end
	if not shortName then
		local unitName = UnitName(unit);
		shortName = unitName;
	end
	local guidTarget, guidHasRealm = ResolveTargetFromGUID(unit, shortName);
	if guidTarget then
		return guidTarget, guidHasRealm;
	end
	local localTarget, localHasRealm = ResolveTargetFromLocalRealm(shortName, unit);
	if localTarget then
		return localTarget, localHasRealm;
	end
	if shortName and shortName ~= "" then
		return ExpandKnownPlayerName(shortName);
	end
	local name, realm = UnitName(unit);
	if not name or name == "" then
		return nil;
	end
	if realm and realm ~= "" then
		return name .. "-" .. realm, true;
	end
	local localTarget, localHasRealm = ResolveTargetFromLocalRealm(name, unit);
	if localTarget then
		return localTarget, localHasRealm;
	end
	return ExpandKnownPlayerName(name);
end

local function PrintMessage(msg)
	if Private.PrintMessage then
		Private.PrintMessage(msg);
	elseif DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(msg);
	end
end

local function RegisterPrefix()
	if prefixRegistered then
		return;
	end
	local ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, ADDON_PREFIX);
	if ok then
		prefixRegistered = true;
	end
end

local function SendAddonMessage(message, channel, target, preserveTargetRealm)
	if channel == "WHISPER" then
		if preserveTargetRealm then
			target = NormaliseName(target, true);
		else
			target = (select(1, ExpandKnownPlayerName(target))) or NormaliseName(target, false);
		end
	end
	return C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, channel, target);
end

-- Build a flat list of completed-achievement records for the local player.
local function BuildLocalCompletionList()
	local entries = {};
	local data = Private.data and Private.data.achievements;
	if type(data) ~= "table" then
		return entries, 0, 0;
	end
	local getCompletions = Private.GetSavedCompletions;
	local getTimestamp = Private.GetSavedCompletionTimestamp;
	local isFeat = Private.IsFeatOfStrengthAchievement;
	local isStat = Private.IsStatisticAchievement;
	local count, points = 0, 0;
	for achievementID, achievement in pairs(data) do
		local savedState = getCompletions and getCompletions(achievementID);
		savedState = savedState and savedState[achievementID];
		local timestamp = getTimestamp and getTimestamp(savedState);
		if timestamp then
			tinsert(entries, {
				id = achievementID,
				ts = timestamp,
			});
			count = count + 1;
			if not (isFeat and isFeat(achievement)) and not (isStat and isStat(achievement)) then
				points = points + (achievement.points or 0);
			end
		end
	end
	return entries, count, points;
end

local function BuildLocalStatisticList()
	local entries = {};
	local data = Private.data and Private.data.achievements;
	local isStat = Private.IsStatisticAchievement;
	local isForFaction = Private.IsAchievementForPlayerFaction;
	local shouldShow = Private.ShouldShowAchievementInUI;
	if type(data) ~= "table" or not isStat or not Achievements.GetStatisticTransportString then
		return entries;
	end

	for statisticID, statistic in pairs(data) do
		if isStat(statistic)
			and (not isForFaction or isForFaction(statistic))
			and (not shouldShow or shouldShow(statisticID)) then
			local quantity = Achievements.GetStatisticTransportString(statisticID) or "n0";
			tinsert(entries, {
				id = statisticID,
				quantity = quantity,
			});
		end
	end

	table.sort(entries, function(left, right)
		return (left.id or 0) < (right.id or 0);
	end);
	return entries;
end

local function FormatEntry(entry)
	if entry.ts then
		return string.format("%d:%d", entry.id, entry.ts);
	end
	return tostring(entry.id);
end

local function PackEntriesIntoChunks(entries)
	local chunks = {};
	local current = "";
	for _, entry in ipairs(entries) do
		local piece = FormatEntry(entry);
		if current == "" then
			current = piece;
		elseif #current + 1 + #piece > CHUNK_SOFT_LIMIT then
			tinsert(chunks, current);
			current = piece;
		else
			current = current .. ";" .. piece;
		end
	end
	if current ~= "" then
		tinsert(chunks, current);
	end
	return chunks;
end

local function PackStatisticEntriesIntoChunks(entries)
	local chunks = {};
	local current = "";
	for _, entry in ipairs(entries) do
		local piece = string.format("%d:%s", entry.id, entry.quantity or "n0");
		if current == "" then
			current = piece;
		elseif #current + 1 + #piece > CHUNK_SOFT_LIMIT then
			tinsert(chunks, current);
			current = piece;
		else
			current = current .. ";" .. piece;
		end
	end
	if current ~= "" then
		tinsert(chunks, current);
	end
	return chunks;
end

local function ParseEntries(text, target)
	if type(text) ~= "string" or text == "" then
		return;
	end
	for piece in (text .. ";"):gmatch("([^;]+);") do
		local id, timestamp = piece:match("^(%d+):(%d+)$");
		if not id then
			id = piece:match("^(%d+)$");
		end
		id = tonumber(id);
		if id then
			target[id] = {
				ts = tonumber(timestamp),
			};
		end
	end
end

local function ParseStatisticEntries(text, target)
	if type(text) ~= "string" or text == "" then
		return;
	end
	for piece in (text .. ";"):gmatch("([^;]+);") do
		local id, quantity = piece:match("^(%d+):(.+)$");
		id = tonumber(id);
		if id then
			if Achievements.FormatStatisticTransportString then
				target[id] = Achievements.FormatStatisticTransportString(id, quantity);
			else
				target[id] = "--";
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Receiver: assemble a response to an incoming CMP_REQ.

local function SendResponsePacket(message, target, shouldLog, preserveTargetRealm)
	local messageType = message:match("^([^\t]+)") or message;
	local ok, result = pcall(SendAddonMessage, message, "WHISPER", target, preserveTargetRealm == true);
	if shouldLog then
		DebugCompare("send " .. tostring(messageType) .. " target=" .. DebugValue(target) .. " ok=" .. DebugValue(ok) .. " result=" .. DebugValue(result));
	end
	return ok, result;
end

local function HandleIncomingRequest(senderName)
	local preserveTargetRealm = NameIncludesRealm(senderName);
	local target = NormaliseName(senderName, preserveTargetRealm);
	DebugCompare("incoming request sender=" .. DebugValue(senderName) .. " replyTarget=" .. DebugValue(target));
	if not target then
		return;
	end
	local entries, count, points = BuildLocalCompletionList();
	local chunks = PackEntriesIntoChunks(entries);
	local statisticChunks = PackStatisticEntriesIntoChunks(BuildLocalStatisticList());

	DebugCompare("incoming response target=" .. DebugValue(target) .. " achievements=" .. tostring(count) .. " chunks=" .. tostring(#chunks) .. " statisticChunks=" .. tostring(#statisticChunks));
	SendResponsePacket(
		string.format("CMP_BEG\t%s\t%d\t%d", PROTOCOL_VERSION, count, points),
		target, true, preserveTargetRealm);
	for _, chunk in ipairs(chunks) do
		SendResponsePacket("CMP_PRT\t" .. chunk, target, false, preserveTargetRealm);
	end
	for _, chunk in ipairs(statisticChunks) do
		SendResponsePacket("CMP_STS\t" .. chunk, target, false, preserveTargetRealm);
	end
	SendResponsePacket("CMP_END", target, true, preserveTargetRealm);
end

-- ---------------------------------------------------------------------------
-- Sender: collect chunks and emit the final diff report.

local function GetLocalCompletedSet()
	local set = {};
	local data = Private.data and Private.data.achievements;
	if type(data) ~= "table" then
		return set;
	end
	local getCompletions = Private.GetSavedCompletions;
	local isComplete = Private.IsSavedCompletionComplete;
	for achievementID in pairs(data) do
		local savedState = getCompletions and getCompletions(achievementID);
		savedState = savedState and savedState[achievementID];
		if isComplete and isComplete(savedState) then
			set[achievementID] = true;
		end
	end
	return set;
end

local function FinaliseRequest(key)
	local request = pendingRequests[key];
	if not request then
		return;
	end
	pendingRequests[key] = nil;

	local theirCompleted = request.completed or {};
	local target = request.target or key;

	-- Refresh the already-open frame with the real data.
	if Achievements.RefreshComparisonData then
		Achievements.RefreshComparisonData(target, request.points or 0, theirCompleted, request.unit, request.statistics or {});
	end
end

local function HandleResponse(messageType, payload, senderName)
	RememberKnownPlayerName(senderName);
	local hasRealm = NameIncludesRealm(senderName);
	local key = GetPendingRequestKey(senderName, hasRealm);
	if not key then
		return;
	end
	local request = pendingRequests[key];
	if not request and hasRealm then
		key = GetPendingRequestKey(senderName, false);
		request = key and pendingRequests[key];
	elseif not request and not hasRealm then
		local expandedKey, expandedHasRealm = ExpandKnownPlayerName(senderName);
		if expandedHasRealm then
			key = GetPendingRequestKey(expandedKey, true);
			request = key and pendingRequests[key];
		end
	end
	if not request then
		return;
	end

	if messageType == "CMP_BEG" then
		local protocolVersion, expectedCountStr, pointsStr = strsplit("\t", payload);
		if protocolVersion ~= PROTOCOL_VERSION then
			return;
		end
		request.expectedCount = tonumber(expectedCountStr);
		request.points = tonumber(pointsStr);
		request.completed = {};
	elseif messageType == "CMP_PRT" then
		ParseEntries(payload, request.completed or {});
	elseif messageType == "CMP_STS" then
		request.statistics = request.statistics or {};
		ParseStatisticEntries(payload, request.statistics);
	elseif messageType == "CMP_END" then
		-- All chunks received — open immediately, like INSPECT_ACHIEVEMENT_READY.
		FinaliseRequest(key);
	end
end

local function PruneStaleRequests()
	local now = GetTime();
	for key, request in pairs(pendingRequests) do
		if request.startTime then
			local elapsed = now - request.startTime;
			-- No CMP_BEG yet after the fast window: assume the target has no
			-- addon and report 0 achievements rather than make the user wait.
			if not request.expectedCount and elapsed > NO_RESPONSE_FAST_FINALISE_SECONDS then
				request.completed = request.completed or {};
				request.points = request.points or 0;
				request.assumedNoAddon = true;

				FinaliseRequest(key);
			elseif elapsed > REQUEST_TIMEOUT_SECONDS then
				pendingRequests[key] = nil;
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Event wiring.

local function EnsureListener()
	if listenerFrame then
		return;
	end
	listenerFrame = CreateFrame("Frame");
	listenerFrame:RegisterEvent("CHAT_MSG_ADDON");
	listenerFrame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
		if event ~= "CHAT_MSG_ADDON" or prefix ~= ADDON_PREFIX then
			return;
		end
		if channel ~= "WHISPER" then
			return;
		end
		RememberKnownPlayerName(sender);
		PruneStaleRequests();
		if type(message) ~= "string" then
			return;
		end
		local messageType, rest = message:match("^([^\t]+)\t?(.*)$");
		if not messageType then
			return;
		end
		if messageType == "CMP_REQ" then
			if rest ~= PROTOCOL_VERSION then
				return;
			end
			HandleIncomingRequest(sender);
		elseif messageType == "CMP_BEG" or messageType == "CMP_PRT" or messageType == "CMP_STS" or messageType == "CMP_END" then
			HandleResponse(messageType, rest, sender);
		end
	end);
end

-- ---------------------------------------------------------------------------
-- Public API.

function Achievements.RequestAchievementComparison(target, unit, forceShortName)
	DebugCompare("request input target=" .. DebugValue(target) .. " unit=" .. DebugValue(unit) .. " forceShortName=" .. DebugValue(forceShortName));
	local inputHasRealm = NameIncludesRealm(target);
	local resolvedTarget, resolvedHasRealm;
	if inputHasRealm then
		resolvedTarget = target;
		resolvedHasRealm = true;
	else
		resolvedTarget, resolvedHasRealm = ResolveTargetFromUnit(unit);
	end
	DebugCompare("request unit resolvedTarget=" .. DebugValue(resolvedTarget) .. " resolvedHasRealm=" .. DebugValue(resolvedHasRealm));
	if not resolvedTarget then
		resolvedTarget = target;
		resolvedHasRealm = NameIncludesRealm(target);
	end
	if forceShortName then
		resolvedTarget = StripRealmSuffix(resolvedTarget);
		resolvedHasRealm = false;
	end
	if resolvedTarget and not resolvedHasRealm then
		resolvedTarget, resolvedHasRealm = ExpandKnownPlayerName(resolvedTarget);
	end
	local normalised = NormaliseName(resolvedTarget, resolvedHasRealm);
	local targetHasRealm = resolvedHasRealm or NameIncludesRealm(normalised);
	local sendTarget = normalised;
	if sendTarget and not targetHasRealm and not unit then
		local lowerTarget = string.lower(sendTarget);
		if lowerTarget ~= sendTarget then
			DebugCompare("request short send lowercased normalised=" .. DebugValue(sendTarget) .. " sendTarget=" .. DebugValue(lowerTarget));
		end
		sendTarget = lowerTarget;
	end
	local requestKey = GetPendingRequestKey(normalised, targetHasRealm);
	DebugCompare("request final resolvedTarget=" .. DebugValue(resolvedTarget) .. " resolvedHasRealm=" .. DebugValue(resolvedHasRealm) .. " normalised=" .. DebugValue(normalised) .. " requestKey=" .. DebugValue(requestKey) .. " sendTarget=" .. DebugValue(sendTarget));
	if not normalised then
		PrintMessage("|cffff8080Achievements:|r usage: /ach-compare <name>");
		return;
	end
	local now = GetTime();
	if lastRequestTimes[requestKey] and now - lastRequestTimes[requestKey] < DUPLICATE_REQUEST_WINDOW_SECONDS then
		local request = pendingRequests[requestKey];
		if request then
			request.unit = unit or request.unit;
			DebugCompare("request duplicate reopened pending target=" .. DebugValue(requestKey) .. " elapsed=" .. DebugValue(now - lastRequestTimes[requestKey]));
			if Achievements.OpenComparisonForName then
				Achievements.OpenComparisonForName(request.target or resolvedTarget, request.points or 0, request.completed or {}, request.unit, request.statistics or {});
			end
			return;
		end
		DebugCompare("request duplicate window without pending target=" .. DebugValue(requestKey) .. " elapsed=" .. DebugValue(now - lastRequestTimes[requestKey]) .. "; sending again");
	end
	lastRequestTimes[requestKey] = now;
	RegisterPrefix();
	EnsureListener();
	pendingRequests[requestKey] = {
		startTime = now,
		target = resolvedTarget,  -- preserve original casing for display
		unit = unit,
		completed = {},
		statistics = {},
	};

	-- Open the frame immediately with skeleton data, like INSPECT_ACHIEVEMENT_READY.
	-- It will be refreshed with real data when CMP_END arrives.
	if Achievements.OpenComparisonForName then
		Achievements.OpenComparisonForName(resolvedTarget, 0, {}, unit, {});
	end

	local ok, result = pcall(SendAddonMessage, "CMP_REQ\t" .. PROTOCOL_VERSION, "WHISPER", sendTarget, targetHasRealm);
	DebugCompare("send CMP_REQ target=" .. DebugValue(sendTarget) .. " requestKey=" .. DebugValue(requestKey) .. " ok=" .. DebugValue(ok) .. " result=" .. DebugValue(result));


	-- Schedule a fast prune so that targets without the addon (and thus no
	-- incoming CHAT_MSG_ADDON to drive PruneStaleRequests) still get
	-- finalised promptly.
	C_Timer.After(NO_RESPONSE_FAST_FINALISE_SECONDS + 0.1, PruneStaleRequests);
	C_Timer.After(REQUEST_TIMEOUT_SECONDS + 0.1, PruneStaleRequests);
end

RegisterPrefix();
EnsureListener();

SLASH_ACHIEVEMENTSCOMPARE1 = "/ach-compare";
SlashCmdList["ACHIEVEMENTSCOMPARE"] = function(arg)
	DebugCompare("slash /ach-compare arg=" .. DebugValue(arg));
	Achievements.RequestAchievementComparison(arg, nil, false);
end

-- ---------------------------------------------------------------------------
-- Right-click menu integration.
--
-- Modern Classic clients build unit popups through Blizzard_Menu and range-
-- check stock buttons with protected APIs. Register our own addon menu item
-- through Menu.ModifyMenu instead of mutating UnitPopupAchievementButtonMixin,
-- which can taint Blizzard's menu construction path.

local function ResolveTargetFromContext(contextData)
	if not contextData then
		DebugCompare("context resolve no contextData");
		return nil;
	end
	local contextSummary = {};
	if type(contextData) == "table" then
		for key, value in pairs(contextData) do
			if type(value) ~= "function" and #contextSummary < 12 then
				contextSummary[#contextSummary + 1] = tostring(key) .. "=" .. tostring(value);
			end
		end
	end
	DebugCompare("context keys " .. table.concat(contextSummary, " "));
	if contextData.name and contextData.name ~= "" and contextData.server and contextData.server ~= "" then
		local target = NormaliseName(tostring(contextData.name) .. "-" .. tostring(contextData.server), true);
		DebugCompare("context name+server name=" .. DebugValue(contextData.name) .. " server=" .. DebugValue(contextData.server) .. " final=" .. DebugValue(target));
		return target;
	end
	local fallbackTarget;
	local target, hasRealm = ResolveTargetFromUnit(contextData.unit);
	if target and target ~= "" and hasRealm then
		DebugCompare("context unit=" .. DebugValue(contextData.unit) .. " name=" .. DebugValue(contextData.name) .. " server=" .. DebugValue(contextData.server) .. " unitTarget=" .. DebugValue(target) .. " hasRealm=" .. DebugValue(hasRealm) .. " final=" .. DebugValue(target));
		return target;
	elseif target and target ~= "" then
		fallbackTarget = target;
		DebugCompare("context unit short fallback unit=" .. DebugValue(contextData.unit) .. " name=" .. DebugValue(contextData.name) .. " server=" .. DebugValue(contextData.server) .. " unitTarget=" .. DebugValue(target));
	end
	target, hasRealm = ResolveTargetFromPlayerLocation(contextData.playerLocation, contextData.name);
	if target and target ~= "" and hasRealm then
		DebugCompare("context playerLocation name=" .. DebugValue(contextData.name) .. " server=" .. DebugValue(contextData.server) .. " hasRealm=" .. DebugValue(hasRealm) .. " final=" .. DebugValue(target));
		return target;
	elseif target and target ~= "" then
		fallbackTarget = fallbackTarget or target;
		DebugCompare("context playerLocation short fallback name=" .. DebugValue(contextData.name) .. " server=" .. DebugValue(contextData.server) .. " target=" .. DebugValue(target));
	end
	local ok, value = pcall(UnitPopupSharedUtil.GetFullPlayerName, contextData);
	if ok and type(value) == "string" and value ~= "" then
		local normalised = NormaliseName(value, NameIncludesRealm(value));
		local hasPopupRealm = NameIncludesRealm(normalised);
		if not NameIncludesRealm(normalised) then
			normalised, hasPopupRealm = ExpandKnownPlayerName(normalised);
		end
		if normalised and normalised ~= "" and hasPopupRealm then
			DebugCompare("context popup name=" .. DebugValue(contextData.name) .. " server=" .. DebugValue(contextData.server) .. " full=" .. DebugValue(value) .. " hasRealm=" .. DebugValue(hasPopupRealm) .. " final=" .. DebugValue(normalised));
			return normalised;
		end
		fallbackTarget = fallbackTarget or normalised;
		DebugCompare("context popup short fallback name=" .. DebugValue(contextData.name) .. " server=" .. DebugValue(contextData.server) .. " full=" .. DebugValue(value) .. " target=" .. DebugValue(normalised));
	else
		DebugCompare("context popup failed ok=" .. DebugValue(ok) .. " value=" .. DebugValue(value) .. " name=" .. DebugValue(contextData.name) .. " server=" .. DebugValue(contextData.server));
	end
	if contextData.name and contextData.name ~= "" then
		local normalised, hasRawRealm = ExpandKnownPlayerName(contextData.name);
		normalised = normalised or NormaliseName(contextData.name, false);
		if normalised and normalised ~= "" and hasRawRealm then
			DebugCompare("context raw name=" .. DebugValue(contextData.name) .. " server=" .. DebugValue(contextData.server) .. " hasRealm=" .. DebugValue(hasRawRealm) .. " final=" .. DebugValue(normalised));
			return normalised;
		end
		fallbackTarget = fallbackTarget or normalised;
		DebugCompare("context raw short fallback name=" .. DebugValue(contextData.name) .. " server=" .. DebugValue(contextData.server) .. " target=" .. DebugValue(normalised));
	end
	if fallbackTarget and fallbackTarget ~= "" then
		DebugCompare("context final short fallback=" .. DebugValue(fallbackTarget));
		return fallbackTarget;
	end
	DebugCompare("context no target name server=" .. DebugValue(contextData.server) .. " unit=" .. DebugValue(contextData.unit));
	return nil;
end

local function CanCompareContext(contextData)
	if not contextData then
		return false;
	end
	local unit = contextData.unit;
	if unit then
		if not UnitIsPlayer(unit) then
			return false;
		end
		if UnitIsUnit(unit, "player") then
			return false;
		end
		if UnitCanAttack("player", unit) then
			return false;
		end
		return true;
	end
	local name = contextData.name;
	if not name or name == "" then
		return false;
	end
	local localName = UnitName("player");
	return not (localName and NormaliseName(name) == NormaliseName(localName));
end

local function OnUnitPopupCompareClick(contextData)
	local target = ResolveTargetFromContext(contextData);
	DebugCompare("menu click target=" .. DebugValue(target) .. " unit=" .. DebugValue(contextData and contextData.unit) .. " name=" .. DebugValue(contextData and contextData.name) .. " server=" .. DebugValue(contextData and contextData.server));
	if target and target ~= "" then
		Achievements.RequestAchievementComparison(target, contextData and contextData.unit, false);
	end
	return MenuResponse.Close;
end

local function GetCompareButtonText()
	return COMPARE_ACHIEVEMENTS or "Compare Achievements";
end

local function PrepareCompareButton(button, contextData)
	if not button then
		return nil;
	end
	if button.SetData then
		button:SetData(contextData);
	end
	if button.SetResponder then
		button:SetResponder(OnUnitPopupCompareClick);
	end
	if button.SetEnabled then
		button:SetEnabled(true);
	end
	if button.SetSelectionIgnored then
		button:SetSelectionIgnored();
	end
	return button;
end

local function CreateCompareButtonDescription(contextData)
	local button;
	if MenuUtil and MenuUtil.CreateButton then
		button = MenuUtil.CreateButton(GetCompareButtonText(), OnUnitPopupCompareClick, contextData);
	end
	return PrepareCompareButton(button, contextData);
end

local function InsertCompareButtonAfterInspect(rootDescription, contextData)
	if not (rootDescription.Insert and rootDescription.EnumerateElementDescriptions and MenuUtil and MenuUtil.GetElementText) then
		return nil;
	end
	local inspectText = INSPECT or "Inspect";
	local compareText = GetCompareButtonText();
	local inspectIndex, existingCompare;
	for index, elementDescription in rootDescription:EnumerateElementDescriptions() do
		local text = MenuUtil.GetElementText(elementDescription);
		if text == compareText then
			existingCompare = PrepareCompareButton(elementDescription, contextData);
		elseif text == inspectText then
			inspectIndex = index;
		end
	end
	if existingCompare then
		DebugCompare("menu prepared existing compare button name=" .. DebugValue(contextData and contextData.name) .. " server=" .. DebugValue(contextData and contextData.server) .. " unit=" .. DebugValue(contextData and contextData.unit));
		return existingCompare;
	end
	if inspectIndex then
		local button = CreateCompareButtonDescription(contextData);
		if button then
			DebugCompare("menu inserted compare after inspect index=" .. DebugValue(inspectIndex) .. " name=" .. DebugValue(contextData and contextData.name) .. " server=" .. DebugValue(contextData and contextData.server) .. " unit=" .. DebugValue(contextData and contextData.unit));
			return rootDescription:Insert(button, inspectIndex + 1);
		end
	end
	return nil;
end

local function AddCompareButtonToMenu(_, rootDescription, contextData)
	if not rootDescription or not CanCompareContext(contextData) then
		return;
	end
	local button = InsertCompareButtonAfterInspect(rootDescription, contextData);
	if not button and rootDescription.CreateButton then
		DebugCompare("menu appended compare fallback name=" .. DebugValue(contextData and contextData.name) .. " server=" .. DebugValue(contextData and contextData.server) .. " unit=" .. DebugValue(contextData and contextData.unit));
		button = rootDescription:CreateButton(GetCompareButtonText(), OnUnitPopupCompareClick, contextData);
	end
	PrepareCompareButton(button, contextData);
end

local popupHookRegistered;

local function HookUnitPopupCompareButton()
	if popupHookRegistered then
		return;
	end
	if not (Menu and Menu.ModifyMenu) then
		return;
	end
	popupHookRegistered = true;
	local tags = {
		"MENU_UNIT_PLAYER",
		"MENU_UNIT_TARGET",
		"MENU_UNIT_FOCUS",
		"MENU_UNIT_PARTY",
		"MENU_UNIT_RAID",
		"MENU_UNIT_RAID_PLAYER",
		"MENU_UNIT_FRIEND",
		"MENU_UNIT_GUILD",
		"MENU_UNIT_COMMUNITIES_MEMBER",
		"MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
		"MENU_UNIT_COMMUNITIES_WOW_MEMBER",
		"MENU_UNIT_CHAT_ROSTER",
		"MENU_UNIT_WORLD_STATE_SCORE",
		"MENU_UNIT_PVP_SCOREBOARD",
	};
	for _, tag in ipairs(tags) do
		Menu.ModifyMenu(tag, AddCompareButtonToMenu);
	end
end

HookUnitPopupCompareButton();
if not popupHookRegistered then
	local popupHookFrame = CreateFrame("Frame");
	popupHookFrame:RegisterEvent("ADDON_LOADED");
	popupHookFrame:RegisterEvent("PLAYER_LOGIN");
	popupHookFrame:SetScript("OnEvent", function(self)
		HookUnitPopupCompareButton();
		if popupHookRegistered then
			self:UnregisterAllEvents();
		end
	end);
end
