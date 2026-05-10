local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsFetcher.lua");
end

local Private = Achievements.private;

local ADDON_PREFIX = "ACHV";
local PROTOCOL_VERSION = "2";
local REQUEST_TIMEOUT_SECONDS = 30;
local CHANNEL_FETCH_ATTEMPTS = 4;
local CHANNEL_FETCH_RETRY_SECONDS = 2;

local listenerFrame;
local pendingRequests = {};
local fetcherNamesSanitised;

local function NameIncludesRealm(name)
	return type(name) == "string" and name:find("%-") ~= nil;
end

local function GetNow()
	return GetServerTime();
end

local function CallAfter(delay, callback)
	C_Timer.After(delay, callback);
end

local function NormaliseName(name)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	local shortName = Ambiguate(name, "short");
	if shortName and shortName ~= "" then
		return shortName:match("^([^%-]+)") or shortName;
	end
	return name:match("^([^%-]+)") or name;
end

local function SanitiseStoredFetcherPlayers(players)
	if type(players) ~= "table" then
		return;
	end
	local moves;
	for key, record in pairs(players) do
		if type(record) == "table" then
			local cleanKey = NormaliseName(key);
			local cleanName = NormaliseName(record.name) or cleanKey;
			if cleanName then
				record.name = cleanName;
			end
			if cleanKey and cleanKey ~= key then
				moves = moves or {};
				moves[#moves + 1] = { from = key, to = cleanKey };
			end
		end
	end
	if not moves then
		return;
	end
	for _, move in ipairs(moves) do
		local record = players[move.from];
		if record then
			if not players[move.to] then
				players[move.to] = record;
			end
			players[move.from] = nil;
		end
	end
end

local function IsLocalName(name)
	local localName = UnitName("player");
	if not localName then
		return false;
	end
	local shortName = Ambiguate(name or "", "short") or tostring(name or ""):match("^([^%-]+)");
	return shortName == localName;
end

local function PrintMessage(message)
	if Private and Private.PrintMessage then
		Private.PrintMessage(message);
	elseif DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(message);
	end
end

local function GetFetcherDB()
	AchievementsDB.fetcher = AchievementsDB.fetcher or {};
	AchievementsDB.fetcher.players = AchievementsDB.fetcher.players or {};
	if not fetcherNamesSanitised then
		SanitiseStoredFetcherPlayers(AchievementsDB.fetcher.players);
		fetcherNamesSanitised = true;
	end
	return AchievementsDB.fetcher;
end

local function CountEntries(tableValue)
	local count = 0;
	if type(tableValue) == "table" then
		for _ in pairs(tableValue) do
			count = count + 1;
		end
	end
	return count;
end

local function ParseAchievementEntries(text, target)
	if type(text) ~= "string" or text == "" then
		return;
	end
	for piece in (text .. ";"):gmatch("([^;]+);") do
		local achievementID, timestamp = piece:match("^(%d+):(%d+)$");
		if not achievementID then
			achievementID = piece:match("^(%d+)$");
		end
		achievementID = tonumber(achievementID);
		if achievementID then
			target[achievementID] = {
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
		local statisticID, quantity = piece:match("^(%d+):(.+)$");
		statisticID = tonumber(statisticID);
		if statisticID then
			if Achievements.FormatStatisticTransportString then
				target[statisticID] = Achievements.FormatStatisticTransportString(statisticID, quantity);
			else
				target[statisticID] = "--";
			end
		end
	end
end

local function StorePeerVersion(sender, version, client, dataVersion, titleID, titleAchievementID)
	local key = NormaliseName(sender);
	if not key then
		return;
	end
	local db = GetFetcherDB();
	local record = db.players[key] or {};
	record.name = key;
	record.version = version or record.version;
	record.mainVersion = version or record.mainVersion;
	record.dataVersion = dataVersion or record.dataVersion;
	record.client = client or record.client;
	titleID = tonumber(titleID);
	titleAchievementID = tonumber(titleAchievementID);
	if titleID and titleID > 0 then
		record.titleID = titleID;
		record.titleAchievementID = titleAchievementID and titleAchievementID > 0 and titleAchievementID or nil;
	end
	record.versionSeenAt = GetNow();
	db.players[key] = record;
	if Achievements.StoreRemoteAddonTitleSnapshot then
		Achievements.StoreRemoteAddonTitleSnapshot(sender, titleID, titleAchievementID);
	end
end

local function FinaliseRequest(key)
	local request = pendingRequests[key];
	if not request then
		return;
	end
	pendingRequests[key] = nil;
	local db = GetFetcherDB();
	local achievements = request.achievements or {};
	local statistics = request.statistics or {};
	db.players[key] = {
		name = key,
		version = request.version,
		mainVersion = request.mainVersion or request.version,
		dataVersion = request.dataVersion,
		client = request.client,
		titleID = request.titleID,
		titleAchievementID = request.titleAchievementID,
		updatedAt = GetNow(),
		points = request.points or 0,
		expectedAchievementCount = request.expectedAchievementCount,
		expectedStatisticCount = request.expectedStatisticCount,
		achievementCount = CountEntries(achievements),
		statisticCount = CountEntries(statistics),
		achievements = achievements,
		statistics = statistics,
	};
	PrintMessage("Achievements fetch complete for " .. tostring(key) .. ": " .. tostring(CountEntries(achievements)) .. " achievements, " .. tostring(CountEntries(statistics)) .. " statistics.");
end

local function PruneStaleRequests()
	local now = GetNow();
	for key, request in pairs(pendingRequests) do
		if request.startedAt and now - request.startedAt > REQUEST_TIMEOUT_SECONDS then
			pendingRequests[key] = nil;
			PrintMessage("Achievements fetch timed out for " .. tostring(request.target or key) .. ".");
		end
	end
end

local function HandleArmoryMessage(messageType, payload, sender)
	if Achievements.RememberKnownPlayerName then
		Achievements.RememberKnownPlayerName(sender);
	end
	local key = NormaliseName(sender);
	if not key then
		return;
	end
	local request = pendingRequests[key];
	if messageType == "ARM_BEG" then
		local protocolVersion, addonVersion, achievementCount, points, statisticCount, client, dataVersion, titleID, titleAchievementID = strsplit("\t", payload or "");
		if protocolVersion ~= PROTOCOL_VERSION then
			return;
		end
		request = request or { target = sender, startedAt = GetNow() };
		request.version = addonVersion;
		request.mainVersion = addonVersion;
		request.dataVersion = dataVersion;
		request.client = client;
		request.titleID = tonumber(titleID);
		request.titleAchievementID = tonumber(titleAchievementID);
		request.expectedAchievementCount = tonumber(achievementCount);
		request.expectedStatisticCount = tonumber(statisticCount);
		request.points = tonumber(points) or 0;
		request.achievements = {};
		request.statistics = {};
		pendingRequests[key] = request;
	elseif messageType == "ARM_ACH" and request then
		request.achievements = request.achievements or {};
		ParseAchievementEntries(payload, request.achievements);
	elseif messageType == "ARM_STS" and request then
		request.statistics = request.statistics or {};
		ParseStatisticEntries(payload, request.statistics);
	elseif messageType == "ARM_END" and request then
		FinaliseRequest(key);
	end
end

local function HandleAddonMessage(prefix, message, channel, sender)
	if prefix ~= ADDON_PREFIX or channel ~= "WHISPER" or type(message) ~= "string" then
		return;
	end
	if Achievements.RememberKnownPlayerName then
		Achievements.RememberKnownPlayerName(sender);
	end
	if IsLocalName(sender) then
		return;
	end
	local messageType, payload = message:match("^([^\t]+)\t?(.*)$");
	if messageType == "VER" then
		local protocolVersion, addonVersion, client, dataVersion, titleID, titleAchievementID = strsplit("\t", payload or "");
		if protocolVersion == PROTOCOL_VERSION then
			StorePeerVersion(sender, addonVersion, client, dataVersion, titleID, titleAchievementID);
		end
	elseif messageType == "ARM_BEG" or messageType == "ARM_ACH" or messageType == "ARM_STS" or messageType == "ARM_END" then
		HandleArmoryMessage(messageType, payload, sender);
	end
end

local function EnsureListener()
	if listenerFrame then
		return;
	end
	listenerFrame = CreateFrame("Frame");
	listenerFrame:RegisterEvent("CHAT_MSG_ADDON");
	listenerFrame:SetScript("OnEvent", function(_, event, ...)
		if event == "CHAT_MSG_ADDON" then
			HandleAddonMessage(...);
		end
		PruneStaleRequests();
	end);
end

local function RequestPlayer(target)
	local key = NormaliseName(target);
	if not key or IsLocalName(target) then
		return false;
	end
	local sendTarget = target;
	local preserveTargetRealm = NameIncludesRealm(sendTarget);
	if not preserveTargetRealm and Achievements.GetKnownPlayerFullName then
		local knownFullName, hasRealm = Achievements.GetKnownPlayerFullName(key);
		if knownFullName and hasRealm then
			sendTarget = knownFullName;
			preserveTargetRealm = true;
		end
	end
	if not preserveTargetRealm then
		sendTarget = string.lower(key);
	end
	pendingRequests[key] = {
		target = key,
		startedAt = GetNow(),
		achievements = {},
		statistics = {},
	};
	if Achievements.SendAchievementVersion then
		Achievements.SendAchievementVersion("WHISPER", sendTarget, preserveTargetRealm);
	end
	if Achievements.SendNetworkAddonMessage then
		Achievements.SendNetworkAddonMessage("VER_REQ\t" .. PROTOCOL_VERSION, "WHISPER", sendTarget, preserveTargetRealm);
		Achievements.SendNetworkAddonMessage("ARM_REQ\t" .. PROTOCOL_VERSION, "WHISPER", sendTarget, preserveTargetRealm);
	end
	CallAfter(REQUEST_TIMEOUT_SECONDS + 1, PruneStaleRequests);
	return true;
end

local function RequestChannelMembers(attempt)
	attempt = attempt or 1;
	if Achievements.JoinAchievementsChannel then
		Achievements.JoinAchievementsChannel();
	end
	CallAfter(1, function()
		local members = Achievements.GetAchievementsChannelMembers and Achievements.GetAchievementsChannelMembers() or {};
		if #members == 0 and attempt < CHANNEL_FETCH_ATTEMPTS then
			CallAfter(CHANNEL_FETCH_RETRY_SECONDS, function()
				RequestChannelMembers(attempt + 1);
			end);
			return;
		end
		local requested = 0;
		for _, memberName in ipairs(members) do
			if RequestPlayer(memberName) then
				requested = requested + 1;
			end
		end
		PrintMessage("Achievements fetch requested from " .. tostring(requested) .. " player(s) in " .. tostring(Achievements.GetAchievementsChannelName and Achievements.GetAchievementsChannelName() or "achievements") .. ".");
	end);
end

local function PrintStoredSummary()
	local players = GetFetcherDB().players;
	local names = {};
	for name in pairs(players) do
		names[#names + 1] = name;
	end
	table.sort(names);
	PrintMessage("Achievements fetcher has " .. tostring(#names) .. " stored player snapshot(s).");
	local firstIndex = math.max(1, #names - 9);
	for playerIndex = firstIndex, #names do
		local name = names[playerIndex];
		local record = players[name];
		local versionText = tostring(record.mainVersion or record.version or "?");
		if record.dataVersion and record.dataVersion ~= "" then
			versionText = versionText .. " / data " .. tostring(record.dataVersion);
		end
		PrintMessage("  " .. tostring(record.name or name) .. " v" .. versionText .. ": " .. tostring(record.achievementCount or 0) .. " achievements, " .. tostring(record.statisticCount or 0) .. " statistics.");
	end
end

function Achievements.FetchAchievementsFromPlayer(target)
	EnsureListener();
	if not RequestPlayer(target) then
		PrintMessage("Usage: /ach-fetch player <name>");
	end
end

function Achievements.FetchAchievementsFromChannel()
	EnsureListener();
	RequestChannelMembers();
end

EnsureListener();

SLASH_ACHIEVEMENTSFETCHER1 = "/ach-fetch";
SlashCmdList["ACHIEVEMENTSFETCHER"] = function(arg)
	local rawArg = tostring(arg or "");
	local command, rest = rawArg:match("^(%S*)%s*(.-)$");
	command = string.lower(command or "");
	if command == "" or command == "scan" or command == "channel" then
		Achievements.FetchAchievementsFromChannel();
	elseif command == "player" or command == "whisper" then
		Achievements.FetchAchievementsFromPlayer(rest);
	elseif command == "show" or command == "summary" then
		PrintStoredSummary();
	elseif command == "clear" then
		AchievementsDB.fetcher = { players = {} };
		PrintMessage("Achievements fetcher snapshots cleared.");
	else
		Achievements.FetchAchievementsFromPlayer(rawArg);
	end
end