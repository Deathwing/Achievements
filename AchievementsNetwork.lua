local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsNetwork.lua");
end

local Private = Achievements.private;

local ADDON_PREFIX = "ACHV";
local PROTOCOL_VERSION = "2";
local CHANNEL_BASE = "achievements";
local CHANNEL_PASSWORD = nil;
local CHANNEL_JOIN_DELAY = 3;
local CHANNEL_RETRY_DELAY = 4;
local VERSION_ANNOUNCE_DELAY = 3;
local VERSION_ANNOUNCE_COOLDOWN = 120;
local CHUNK_SOFT_LIMIT = 220;

local channelCandidates = {
	"achievements",
	"achievementsb",
	"achievementsc",
	"achievementsd",
	"achievementse",
};

local Network = Achievements.Network or {};
Achievements.Network = Network;

local prefixRegistered;
local listenerFrame;
local activeChannelName;
local joiningChannel;
local versionAnnounceScheduled;
local filtersInstalled;
local staticPopupHooked;
local lastVersionAnnounce = {};
local warnedVersions = {};
local warnedDataVersions = {};
local knownChannelMembers = {};
local sendTraceHooksInstalled;

local function GetNow()
	return GetServerTime();
end

local function CallAfter(delay, callback)
	C_Timer.After(delay, callback);
end

local function NameIncludesRealm(name)
	return type(name) == "string" and name:find("%-") ~= nil;
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
		return ambiguousName:match("^([^%-]+)") or ambiguousName;
	end
	return name:match("^([^%-]+)") or name;
end

local function NormaliseLiveSenderName(name)
	return NormaliseName(name, NameIncludesRealm(name));
end

local function RememberKnownPlayerName(name)
	if Achievements.RememberKnownPlayerName then
		Achievements.RememberKnownPlayerName(name);
	end
end

local function GetKnownWhisperTarget(name)
	if Achievements.GetKnownPlayerFullName then
		local shortName = NormaliseName(name, false);
		local fullName, hasRealm = Achievements.GetKnownPlayerFullName(shortName);
		if fullName and hasRealm then
			return fullName, true;
		end
	end
	return nil, false;
end

local function DebugNetwork(message)
	if Private and Private.DebugMessage then
		Private.DebugMessage("network: " .. tostring(message));
	end
end

local function DebugOutboundMessage(apiName, prefix, message, channel, target)
	if channel ~= "WHISPER" then
		return;
	end
	if prefix ~= ADDON_PREFIX and not NameIncludesRealm(target) then
		return;
	end
	DebugNetwork("hook api=" .. tostring(apiName) .. " prefix=" .. tostring(prefix) .. " type=" .. tostring(type(message) == "string" and (message:match("^([^\t]+)") or message) or nil) .. " target=" .. tostring(target) .. " normalised=" .. tostring(NormaliseName(target, NameIncludesRealm(target))));
end

local function InstallSendTraceHooks()
	if sendTraceHooksInstalled then
		return;
	end
	sendTraceHooksInstalled = true;
	pcall(hooksecurefunc, C_ChatInfo, "SendAddonMessage", function(prefix, message, channel, target)
		DebugOutboundMessage("C_ChatInfo.SendAddonMessage", prefix, message, channel, target);
	end);
	pcall(hooksecurefunc, "SendAddonMessage", function(prefix, message, channel, target)
		DebugOutboundMessage("SendAddonMessage", prefix, message, channel, target);
	end);
	if _G.ChatThrottleLib and _G.ChatThrottleLib.SendAddonMessage then
		pcall(hooksecurefunc, _G.ChatThrottleLib, "SendAddonMessage", function(_, _, prefix, message, channel, target)
			DebugOutboundMessage("ChatThrottleLib.SendAddonMessage", prefix, message, channel, target);
		end);
	end
	pcall(hooksecurefunc, "SendChatMessage", function(_, chatType, _, target)
		if chatType == "WHISPER" and NameIncludesRealm(target) then
			DebugNetwork("hook api=SendChatMessage target=" .. tostring(target));
		end
	end);
end

local function SanitiseWhisperTarget(channel, target, preserveTargetRealm)
	if channel == "WHISPER" then
		if not preserveTargetRealm then
			local knownTarget = GetKnownWhisperTarget(target);
			if knownTarget then
				return knownTarget;
			end
		end
		return NormaliseName(target, preserveTargetRealm == true);
	end
	return target;
end

local function IsLocalSender(sender)
	local localName = UnitName("player");
	if not localName or not sender then
		return false;
	end
	local shortSender = Ambiguate(sender, "short") or sender:match("^([^%-]+)") or sender;
	return shortSender == localName;
end

local function PrintMessage(message)
	if Private and Private.PrintMessage then
		Private.PrintMessage(message);
	elseif DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(message);
	end
end

local function RegisterPrefix()
	if prefixRegistered then
		return true;
	end
	local ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, ADDON_PREFIX);
	prefixRegistered = ok == true;
	return prefixRegistered == true;
end

local function SendAddonMessageSafe(message, channel, target, preserveTargetRealm)
	RegisterPrefix();
	InstallSendTraceHooks();
	if type(message) ~= "string" or type(channel) ~= "string" then
		return false;
	end
	local originalTarget = target;
	target = SanitiseWhisperTarget(channel, target, preserveTargetRealm == true);
	if channel == "WHISPER" then
		DebugNetwork("send type=" .. tostring(message:match("^([^\t]+)") or message) .. " originalTarget=" .. tostring(originalTarget) .. " target=" .. tostring(target));
	end
	if _G.ChatThrottleLib then
		local ok = pcall(_G.ChatThrottleLib.SendAddonMessage, _G.ChatThrottleLib, "BULK", ADDON_PREFIX, message, channel, target);
		return ok == true;
	end
	local ok = pcall(C_ChatInfo.SendAddonMessage, ADDON_PREFIX, message, channel, target);
	return ok == true;
end

local function GetAddonVersion()
	local addonName = Achievements.addonName or "Achievements";
	local ok, version = pcall(C_AddOns.GetAddOnMetadata, addonName, "Version");
	if ok and version and version ~= "" then
		return tostring(version);
	end
	return "0.0.0";
end

local function GetDataVersion()
	local data = (Private and Private.data) or _G.AchievementsData;
	local version = data and (data.version or data.dataVersion);
	if version and version ~= "" then
		return tostring(version);
	end
	local ok, metadataVersion = pcall(C_AddOns.GetAddOnMetadata, "AchievementsData", "Version");
	if ok and metadataVersion and metadataVersion ~= "" then
		return tostring(metadataVersion);
	end
	return "unknown";
end

local function GetClientLabel()
	return (Private and Private.data and Private.data.client) or (_G.AchievementsData and _G.AchievementsData.client) or "unknown";
end

local function CompareVersions(leftVersion, rightVersion)
	local leftParts = {};
	local rightParts = {};
	for part in tostring(leftVersion or ""):gmatch("%d+") do
		leftParts[#leftParts + 1] = tonumber(part) or 0;
	end
	for part in tostring(rightVersion or ""):gmatch("%d+") do
		rightParts[#rightParts + 1] = tonumber(part) or 0;
	end
	local maxParts = math.max(#leftParts, #rightParts, 1);
	for partIndex = 1, maxParts do
		local leftValue = leftParts[partIndex] or 0;
		local rightValue = rightParts[partIndex] or 0;
		if leftValue > rightValue then
			return 1;
		elseif leftValue < rightValue then
			return -1;
		end
	end
	return 0;
end

local function SendVersion(channel, target, preserveTargetRealm)
	local titleID, titleAchievementID = 0, 0;
	if Achievements.GetAddonTitleSnapshot then
		titleID, titleAchievementID = Achievements.GetAddonTitleSnapshot();
	end
	local message = "VER\t" .. PROTOCOL_VERSION .. "\t" .. GetAddonVersion() .. "\t" .. GetClientLabel() .. "\t" .. GetDataVersion() .. "\t" .. tostring(titleID or 0) .. "\t" .. tostring(titleAchievementID or 0);
	return SendAddonMessageSafe(message, channel, target, preserveTargetRealm == true);
end

local function NotifyNewerVersion(sender, remoteVersion)
	local localVersion = GetAddonVersion();
	if CompareVersions(remoteVersion, localVersion) <= 0 then
		return;
	end
	if Achievements.Update and Achievements.Update.Notify then
		Achievements.Update.Notify(remoteVersion);
		return;
	end
	local warningKey = tostring(remoteVersion);
	if warnedVersions[warningKey] then
		return;
	end
	warnedVersions[warningKey] = true;
	PrintMessage("|cffffff00Achievements:|r A newer version (v" .. tostring(remoteVersion) .. ") is available; you are running v" .. tostring(localVersion) .. " with data " .. tostring(GetDataVersion()) .. ".");
end

local function NotifyDifferentDataVersion(sender, remoteDataVersion)
	local localDataVersion = GetDataVersion();
	if type(remoteDataVersion) ~= "string" or remoteDataVersion == "" or remoteDataVersion == "unknown" then
		return;
	end
	if localDataVersion == "unknown" or remoteDataVersion == localDataVersion then
		return;
	end
	local warningKey = tostring(remoteDataVersion);
	if warnedDataVersions[warningKey] then
		return;
	end
	warnedDataVersions[warningKey] = true;
	PrintMessage("|cffffff00Achievements:|r Different AchievementsData version detected from " .. tostring(NormaliseName(sender) or sender or "another player") .. " (remote data " .. tostring(remoteDataVersion) .. ", local data " .. tostring(localDataVersion) .. ").");
end

local function HandleVersionMessage(sender, remoteVersion, remoteDataVersion)
	if IsLocalSender(sender) then
		return;
	end
	if type(remoteVersion) ~= "string" or remoteVersion == "" then
		return;
	end
	local comparison = CompareVersions(remoteVersion, GetAddonVersion());
	if comparison > 0 then
		NotifyNewerVersion(sender, remoteVersion);
	elseif comparison < 0 then
		local target = NormaliseLiveSenderName(sender);
		if target then
			SendVersion("WHISPER", target, NameIncludesRealm(target));
		end
	end
	NotifyDifferentDataVersion(sender, remoteDataVersion);
end

local function HideChannelFromChatFrames(channelName)
	if not channelName then
		return;
	end
	for frameIndex = 1, 10 do
		local chatFrame = _G["ChatFrame" .. frameIndex];
		if chatFrame then
			pcall(ChatFrame_RemoveChannel, chatFrame, channelName);
		end
	end
end

local function CleanChannelName(channelName)
	if type(channelName) ~= "string" then
		return nil;
	end
	local cleaned = channelName:match("^%d+%.%s*(.+)$") or channelName;
	return string.lower(cleaned or "");
end

local function IsDiscoveryChannelName(channelName)
	local cleaned = CleanChannelName(channelName);
	return cleaned and cleaned:sub(1, #CHANNEL_BASE) == CHANNEL_BASE;
end

local function ExtractChannelName(...)
	local explicitName = select(9, ...);
	if type(explicitName) == "string" and explicitName ~= "" then
		return CleanChannelName(explicitName);
	end
	local channelText = select(4, ...);
	if type(channelText) == "string" and channelText ~= "" then
		return CleanChannelName(channelText);
	end
	return nil;
end

local function RememberChannelMember(memberName)
	local normalised = NormaliseName(memberName);
	if normalised and not IsLocalSender(memberName) then
		RememberKnownPlayerName(memberName);
		knownChannelMembers[normalised] = normalised;
		return normalised;
	end
	return nil;
end

local function ForgetChannelMember(memberName)
	local normalised = NormaliseName(memberName);
	if normalised then
		knownChannelMembers[normalised] = nil;
	end
end

local function CaptureChannelRosterMembers(channelID, membersByName)
	if not channelID then
		return 0;
	end
	local count;
	local ok, _, _, _, _, displayCount = pcall(GetChannelDisplayInfo, channelID);
	count = ok and tonumber(displayCount) or nil;
	local found = 0;
	local maxRosterIndex = count and count > 0 and count or 100;
	for rosterIndex = 1, maxRosterIndex do
		local rosterOK, memberName = pcall(C_ChatInfo.GetChannelRosterInfo, channelID, rosterIndex);
		if rosterOK and memberName and memberName ~= "" then
			local normalised = RememberChannelMember(memberName);
			if normalised then
				found = found + 1;
				if membersByName then
					membersByName[normalised] = normalised;
				end
			end
		elseif not count or count <= 0 then
			break;
		end
	end
	return found;
end

local function RememberChannelListMembers(text)
	if type(text) ~= "string" or text == "" then
		return;
	end
	for token in text:gmatch("[^,%s]+") do
		local memberName = token:gsub("^[%@%*%+]+", ""):gsub("[%.,;:]+$", "");
		if memberName ~= "" and not tonumber(memberName) then
			RememberChannelMember(memberName);
		end
	end
end

local function InstallChannelFilters()
	if filtersInstalled then
		return;
	end
	filtersInstalled = true;
	local function channelFilter(_, _, ...)
		return IsDiscoveryChannelName(ExtractChannelName(...));
	end
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", channelFilter);
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", channelFilter);
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", channelFilter);
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_JOIN", channelFilter);
	ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_LEAVE", channelFilter);
	if not staticPopupHooked then
		staticPopupHooked = true;
		hooksecurefunc("StaticPopup_Show", function(which, _, _, data)
			if data and IsDiscoveryChannelName(data) then
				StaticPopup_Hide(which);
			end
		end);
	end
end

local function GetJoinedChannelID(channelName)
	if type(channelName) ~= "string" then
		return nil;
	end
	local ok, channelID = pcall(GetChannelName, channelName);
	channelID = ok and tonumber(channelID) or nil;
	if channelID and channelID ~= 0 then
		return channelID;
	end
	return nil;
end

local function TryJoinDiscoveryChannel(candidateIndex)
	candidateIndex = candidateIndex or 1;
	local channelName = channelCandidates[candidateIndex];
	if not channelName then
		joiningChannel = nil;
		return;
	end
	activeChannelName = channelName;
	joiningChannel = true;
	if JoinChannelByName then
		pcall(JoinChannelByName, channelName, CHANNEL_PASSWORD, nil, false);
	end
	HideChannelFromChatFrames(channelName);
	CallAfter(CHANNEL_RETRY_DELAY, function()
		if GetJoinedChannelID(channelName) then
			activeChannelName = channelName;
			joiningChannel = nil;
			HideChannelFromChatFrames(channelName);
			return;
		end
		TryJoinDiscoveryChannel(candidateIndex + 1);
	end);
end

local function JoinDiscoveryChannel()
	InstallChannelFilters();
	if activeChannelName and GetJoinedChannelID(activeChannelName) then
		HideChannelFromChatFrames(activeChannelName);
		return;
	end
	if joiningChannel then
		return;
	end
	CallAfter(CHANNEL_JOIN_DELAY, function()
		TryJoinDiscoveryChannel(1);
	end);
end

local function ShouldAnnounceOnChannel(channel)
	local now = GetNow();
	if lastVersionAnnounce[channel] and now - lastVersionAnnounce[channel] < VERSION_ANNOUNCE_COOLDOWN then
		return false;
	end
	lastVersionAnnounce[channel] = now;
	return true;
end

local function AnnounceVersionOnSocialChannels()
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and ShouldAnnounceOnChannel("INSTANCE_CHAT") then
		SendVersion("INSTANCE_CHAT");
	elseif IsInRaid() and ShouldAnnounceOnChannel("RAID") then
		SendVersion("RAID");
	elseif IsInGroup() and ShouldAnnounceOnChannel("PARTY") then
		SendVersion("PARTY");
	end
	if IsInGuild() and ShouldAnnounceOnChannel("GUILD") then
		SendVersion("GUILD");
	end
end

local function ScheduleVersionAnnounce()
	if versionAnnounceScheduled then
		return;
	end
	versionAnnounceScheduled = true;
	CallAfter(VERSION_ANNOUNCE_DELAY, function()
		versionAnnounceScheduled = nil;
		AnnounceVersionOnSocialChannels();
	end);
end

local function FormatAchievementEntry(entry)
	if entry.ts then
		return string.format("%d:%d", entry.id, entry.ts);
	end
	return tostring(entry.id);
end

local function PackAchievementEntries(entries)
	local chunks = {};
	local current = "";
	for _, entry in ipairs(entries) do
		local piece = FormatAchievementEntry(entry);
		if current == "" then
			current = piece;
		elseif #current + 1 + #piece > CHUNK_SOFT_LIMIT then
			chunks[#chunks + 1] = current;
			current = piece;
		else
			current = current .. ";" .. piece;
		end
	end
	if current ~= "" then
		chunks[#chunks + 1] = current;
	end
	return chunks;
end

local function PackStatisticEntries(entries)
	local chunks = {};
	local current = "";
	for _, entry in ipairs(entries) do
		local piece = string.format("%d:%s", entry.id, entry.quantity or "n0");
		if current == "" then
			current = piece;
		elseif #current + 1 + #piece > CHUNK_SOFT_LIMIT then
			chunks[#chunks + 1] = current;
			current = piece;
		else
			current = current .. ";" .. piece;
		end
	end
	if current ~= "" then
		chunks[#chunks + 1] = current;
	end
	return chunks;
end

local function BuildLocalCompletionList()
	local entries = {};
	local data = Private and Private.data and Private.data.achievements;
	if type(data) ~= "table" then
		return entries, 0, 0;
	end
	local count, points = 0, 0;
	for achievementID, achievement in pairs(data) do
		local savedState = Private.GetSavedCompletions and Private.GetSavedCompletions(achievementID);
		savedState = savedState and savedState[achievementID];
		local timestamp = Private.GetSavedCompletionTimestamp and Private.GetSavedCompletionTimestamp(savedState);
		if timestamp then
			entries[#entries + 1] = {
				id = achievementID,
				ts = timestamp,
			};
			count = count + 1;
			if not (Private.IsFeatOfStrengthAchievement and Private.IsFeatOfStrengthAchievement(achievement))
				and not (Private.IsStatisticAchievement and Private.IsStatisticAchievement(achievement)) then
				points = points + (achievement.points or 0);
			end
		end
	end
	table.sort(entries, function(left, right)
		return (left.id or 0) < (right.id or 0);
	end);
	return entries, count, points;
end

local function BuildLocalStatisticList()
	local entries = {};
	local data = Private and Private.data and Private.data.achievements;
	if type(data) ~= "table" or not Private.IsStatisticAchievement or not Achievements.GetStatisticTransportString then
		return entries;
	end
	for statisticID, statistic in pairs(data) do
		if Private.IsStatisticAchievement(statistic)
			and (not Private.IsAchievementForPlayerFaction or Private.IsAchievementForPlayerFaction(statistic))
			and (not Private.ShouldShowAchievementInUI or Private.ShouldShowAchievementInUI(statisticID)) then
			entries[#entries + 1] = {
				id = statisticID,
				quantity = Achievements.GetStatisticTransportString(statisticID) or "n0",
			};
		end
	end
	table.sort(entries, function(left, right)
		return (left.id or 0) < (right.id or 0);
	end);
	return entries;
end

local function SendArmorySnapshot(target, preserveTargetRealm)
	local entries, count, points = BuildLocalCompletionList();
	local statistics = BuildLocalStatisticList();
	local titleID, titleAchievementID = 0, 0;
	if Achievements.GetAddonTitleSnapshot then
		titleID, titleAchievementID = Achievements.GetAddonTitleSnapshot();
	end
	SendAddonMessageSafe(string.format("ARM_BEG\t%s\t%s\t%d\t%d\t%d\t%s\t%s\t%d\t%d", PROTOCOL_VERSION, GetAddonVersion(), count, points, #statistics, GetClientLabel(), GetDataVersion(), titleID or 0, titleAchievementID or 0), "WHISPER", target, preserveTargetRealm == true);
	for _, chunk in ipairs(PackAchievementEntries(entries)) do
		SendAddonMessageSafe("ARM_ACH\t" .. chunk, "WHISPER", target, preserveTargetRealm == true);
	end
	for _, chunk in ipairs(PackStatisticEntries(statistics)) do
		SendAddonMessageSafe("ARM_STS\t" .. chunk, "WHISPER", target, preserveTargetRealm == true);
	end
	SendAddonMessageSafe("ARM_END", "WHISPER", target, preserveTargetRealm == true);
end

local function HandleArmoryRequest(sender)
	if IsLocalSender(sender) then
		return;
	end
	local target = NormaliseLiveSenderName(sender);
	if not target then
		return;
	end
	SendVersion("WHISPER", target, NameIncludesRealm(target));
	SendArmorySnapshot(target, NameIncludesRealm(target));
end

local function HandleAddonMessage(prefix, message, channel, sender)
	if prefix ~= ADDON_PREFIX or type(message) ~= "string" then
		return;
	end
	RememberKnownPlayerName(sender);
	local messageType, payload = message:match("^([^\t]+)\t?(.*)$");
	if messageType == "VER" then
		local protocolVersion, remoteVersion, remoteClient, remoteDataVersion, remoteTitleID, remoteTitleAchievementID = strsplit("\t", payload or "");
		if protocolVersion == PROTOCOL_VERSION then
			HandleVersionMessage(sender, remoteVersion, remoteDataVersion, remoteClient);
			if Achievements.StoreRemoteAddonTitleSnapshot then
				Achievements.StoreRemoteAddonTitleSnapshot(sender, remoteTitleID, remoteTitleAchievementID);
			end
		end
	elseif messageType == "VER_REQ" then
		if payload ~= PROTOCOL_VERSION then
			return;
		end
		local target = NormaliseLiveSenderName(sender);
		if target then
			SendVersion("WHISPER", target, NameIncludesRealm(target));
		end
	elseif messageType == "ARM_REQ" and channel == "WHISPER" then
		if payload ~= PROTOCOL_VERSION then
			return;
		end
		HandleArmoryRequest(sender);
	elseif messageType == "TTL" then
		if Achievements.HandleAddonTitleMessage then
			Achievements.HandleAddonTitleMessage(payload, sender);
		end
	end
end

local function HandleChannelEvent(event, ...)
	local channelName = ExtractChannelName(...);
	if not IsDiscoveryChannelName(channelName) then
		return;
	end
	local sender = select(2, ...);
	if event == "CHAT_MSG_CHANNEL_JOIN" then
		RememberChannelMember(sender);
	elseif event == "CHAT_MSG_CHANNEL_LEAVE" then
		ForgetChannelMember(sender);
	elseif event == "CHAT_MSG_CHANNEL" then
		RememberChannelMember(sender);
	elseif event == "CHAT_MSG_CHANNEL_LIST" then
		RememberChannelListMembers(select(1, ...));
	end
end

local function EnsureListener()
	if listenerFrame then
		return;
	end
	listenerFrame = CreateFrame("Frame");
	listenerFrame:RegisterEvent("CHAT_MSG_ADDON");
	listenerFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "GROUP_ROSTER_UPDATE");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "RAID_ROSTER_UPDATE");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "GUILD_ROSTER_UPDATE");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "PLAYER_GUILD_UPDATE");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "CHAT_MSG_GUILD");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "ZONE_CHANGED_NEW_AREA");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "CHAT_MSG_CHANNEL");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "CHAT_MSG_CHANNEL_JOIN");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "CHAT_MSG_CHANNEL_LEAVE");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "CHAT_MSG_CHANNEL_LIST");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "CHANNEL_ROSTER_UPDATE");
	pcall(listenerFrame.RegisterEvent, listenerFrame, "CHANNEL_COUNT_UPDATE");
	listenerFrame:SetScript("OnEvent", function(_, event, ...)
		if event == "CHAT_MSG_ADDON" then
			HandleAddonMessage(...);
		elseif event == "PLAYER_ENTERING_WORLD" then
			JoinDiscoveryChannel();
			ScheduleVersionAnnounce();
		elseif event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" or event == "CHAT_MSG_GUILD" then
			ScheduleVersionAnnounce();
		elseif event == "ZONE_CHANGED_NEW_AREA" then
			JoinDiscoveryChannel();
		elseif event == "CHAT_MSG_CHANNEL" or event == "CHAT_MSG_CHANNEL_JOIN" or event == "CHAT_MSG_CHANNEL_LEAVE" or event == "CHAT_MSG_CHANNEL_LIST" then
			HandleChannelEvent(event, ...);
		elseif event == "CHANNEL_ROSTER_UPDATE" or event == "CHANNEL_COUNT_UPDATE" then
			local channelID = select(1, ...);
			if channelID and channelID == (Achievements.GetAchievementsChannelID and Achievements.GetAchievementsChannelID() or nil) then
				CaptureChannelRosterMembers(channelID);
			end
		end
	end);
end

function Achievements.GetAddonVersion()
	return GetAddonVersion();
end

function Achievements.GetDataVersion()
	return GetDataVersion();
end

function Achievements.GetVersionInfo()
	return GetAddonVersion(), GetDataVersion(), GetClientLabel();
end

function Achievements.SendNetworkAddonMessage(message, channel, target, preserveTargetRealm)
	return SendAddonMessageSafe(message, channel, target, preserveTargetRealm == true);
end

function Achievements.SendAchievementVersion(channel, target, preserveTargetRealm)
	return SendVersion(channel, target, preserveTargetRealm == true);
end

function Achievements.JoinAchievementsChannel()
	JoinDiscoveryChannel();
end

function Achievements.GetAchievementsChannelName()
	return activeChannelName or channelCandidates[1];
end

function Achievements.GetAchievementsChannelID()
	return GetJoinedChannelID(activeChannelName or channelCandidates[1]);
end

function Achievements.GetAchievementsChannelMembers()
	local membersByName = {};
	local channelName = Achievements.GetAchievementsChannelName and Achievements.GetAchievementsChannelName() or channelCandidates[1];
	local channelID = Achievements.GetAchievementsChannelID and Achievements.GetAchievementsChannelID() or nil;
	if channelID and not activeChannelName then
		activeChannelName = channelName;
	end
	if channelID and channelName then
		pcall(ListChannelByName, channelName);
	end
	if channelID then
		CaptureChannelRosterMembers(channelID, membersByName);
	end
	for normalised, memberName in pairs(knownChannelMembers) do
		membersByName[normalised] = memberName;
	end
	local members = {};
	for _, memberName in pairs(membersByName) do
		members[#members + 1] = memberName;
	end
	table.sort(members);
	return members;
end

InstallSendTraceHooks();
RegisterPrefix();
EnsureListener();
InstallChannelFilters();
JoinDiscoveryChannel();