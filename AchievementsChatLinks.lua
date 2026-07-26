local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsChatLinks.lua");
end

local achievementChatLinksHooked;
local recentOutgoingAchievementMessages = {};
local ADDON_PREFIX = "ACHV";
local LINK_META_MESSAGE_TYPE = "LNK";
local LINK_META_VERSION = "3";
local LINK_META_TTL_SECONDS = 15;
local linkMetaPrefixRegistered;
local linkMetaListenerFrame;
local recentIncomingAchievementLinks = {};
local NormalizeAchievementChatLinks;

local function RegisterLinkMetaPrefix()
	if linkMetaPrefixRegistered then
		return;
	end
	local ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, ADDON_PREFIX);
	if ok then
		linkMetaPrefixRegistered = true;
	end
end

local function SendLinkMetaAddonMessage(message, channel, target)
	RegisterLinkMetaPrefix();
	return C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, channel, target);
end

local function NormaliseSenderName(name)
	if type(name) ~= "string" or name == "" then
		return "";
	end
	local ambiguousName = Ambiguate(name, "none");
	if ambiguousName and ambiguousName ~= "" then
		return string.lower(ambiguousName);
	end
	return string.lower(name);
end

local function NormaliseCompletionTimestamp(timestamp)
	timestamp = tonumber(timestamp);
	if not timestamp or timestamp <= 0 then
		return 0;
	end
	return math.floor(timestamp);
end

local function PruneIncomingAchievementLinks()
	local currentTime = GetTime();
	for index = #recentIncomingAchievementLinks, 1, -1 do
		if recentIncomingAchievementLinks[index].expires <= currentTime then
			tremove(recentIncomingAchievementLinks, index);
		end
	end
end

local function BuildAchievementLinkFromMeta(achievementID, displayText, guid, completionTimestamp, ownerName, criteriaProgress)
	local timestamp = NormaliseCompletionTimestamp(completionTimestamp);
	local hasOwner = ownerName and ownerName ~= "";
	local hasCriteriaProgress = criteriaProgress and criteriaProgress ~= "";
	local ownerSuffix = "";
	if hasCriteriaProgress then
		ownerSuffix = ":" .. tostring(hasOwner and ownerName or "") .. ":" .. tostring(criteriaProgress);
	elseif hasOwner then
		ownerSuffix = ":" .. tostring(ownerName);
	end
	return string.format("|cffffff00|Hachievement:%d:%s:%d%s|h[%s]|h|r",
		tonumber(achievementID) or 0,
		tostring(guid or ""),
		timestamp,
		ownerSuffix,
		tostring(displayText or ""));
end

	local function ParseAchievementLinkData(linkData)
		if type(linkData) ~= "string" then
			return nil;
		end
		local achievementID, guid, completionTimestampText = linkData:match("^(%d+):([^:]*):(%d+)");
		if not achievementID then
			return nil;
		end
		return tonumber(achievementID), guid, NormaliseCompletionTimestamp(completionTimestampText);
	end

	local function ExtractAchievementLinkMetas(text)
		local linkedText = NormalizeAchievementChatLinks(text);
		local metas = {};

		local function addMeta(linkData, displayText)
			local achievementID, guid, completionTimestamp = ParseAchievementLinkData(linkData);
			if achievementID then
				metas[#metas + 1] = {
					achievementID = achievementID,
					guid = guid,
					completionTimestamp = completionTimestamp,
					criteriaProgress = Achievements.GetAchievementCriteriaProgressPayload and Achievements.GetAchievementCriteriaProgressPayload(achievementID) or "",
				};
			end
			return "";
		end

		local remaining = linkedText:gsub("|c%x%x%x%x%x%x%x%x|Hachievement:([^|]+)|h%[([^%]]+)%]|h|r", addMeta);
		remaining:gsub("|Hachievement:([^|]+)|h%[([^%]]+)%]|h", addMeta);
		return metas;
	end

	local function ResolveLinkMetaAddonChannel(chatType, target)
		local channel = type(chatType) == "string" and string.upper(chatType) or "SAY";
		if channel == "EMOTE" then
			channel = "SAY";
		elseif channel == "RAID_WARNING" then
			channel = "RAID";
		end

		if channel == "SAY" or channel == "YELL" or channel == "PARTY" or channel == "RAID" or channel == "GUILD" or channel == "INSTANCE_CHAT" or channel == "BATTLEGROUND" then
			return channel, nil;
		end
		if channel == "WHISPER" then
			return channel, target;
		end
		if channel == "CHANNEL" then
			return channel, target;
		end
		return nil, nil;
	end

	local function SendOutgoingAchievementLinkMetas(text, chatType, target)
		local channel, addonTarget = ResolveLinkMetaAddonChannel(chatType, target);
		if not channel then
			return;
		end
		local metas = ExtractAchievementLinkMetas(text);
		for _, meta in ipairs(metas) do
			local message = table.concat({
				LINK_META_MESSAGE_TYPE,
				LINK_META_VERSION,
				tostring(meta.achievementID or 0),
				tostring(meta.guid or ""),
				tostring(meta.completionTimestamp or 0),
				tostring(meta.criteriaProgress or ""),
			}, "\t");
			pcall(SendLinkMetaAddonMessage, message, channel, addonTarget);
		end
	end

	local function RememberIncomingAchievementLink(sender, payload)
		local messageType, version, idText, guidText, completionTimestampText, criteriaProgressText = strsplit("\t", payload or "");
		if messageType ~= LINK_META_MESSAGE_TYPE or version ~= LINK_META_VERSION then
			return false;
		end
		local achievementID = tonumber(idText);
		if not achievementID then
			return true;
		end
		local ownerName = "";
		if sender and sender ~= "" then
			ownerName = Ambiguate(sender, "none") or sender;
		end
		local completionTimestamp = NormaliseCompletionTimestamp(completionTimestampText);

		PruneIncomingAchievementLinks();
		tinsert(recentIncomingAchievementLinks, {
			senderKey = NormaliseSenderName(sender),
			achievementID = achievementID,
			guid = guidText or "",
			completionTimestamp = completionTimestamp,
			criteriaProgress = criteriaProgressText or "",
			ownerName = ownerName,
			expires = GetTime() + LINK_META_TTL_SECONDS,
		});

		while #recentIncomingAchievementLinks > 40 do
			tremove(recentIncomingAchievementLinks, 1);
		end
		return true;
	end

	local function FindIncomingAchievementLink(sender, achievementID)
		PruneIncomingAchievementLinks();
		local senderKey = NormaliseSenderName(sender);
		for index = #recentIncomingAchievementLinks, 1, -1 do
			local entry = recentIncomingAchievementLinks[index];
			if entry.senderKey == senderKey and entry.achievementID == achievementID then
				return entry;
			end
		end
		return nil;
	end

	local function EnsureLinkMetaListener()
		if linkMetaListenerFrame then
			return;
		end
		RegisterLinkMetaPrefix();
		linkMetaListenerFrame = CreateFrame("Frame");
		linkMetaListenerFrame:RegisterEvent("CHAT_MSG_ADDON");
		linkMetaListenerFrame:SetScript("OnEvent", function(_, event, prefix, message, _, sender)
			if event ~= "CHAT_MSG_ADDON" or prefix ~= ADDON_PREFIX then
				return;
			end
			RememberIncomingAchievementLink(sender, message);
		end);
	end

function NormalizeAchievementChatLinks(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x|Hachievement:([^|]+)|h%[([^%]]+)%]|h|r", function(linkData, displayText)
		local achievementID = tonumber(string.match(linkData, "^(%d+)"));
		return achievementID and Achievements.GetAchievementLink(achievementID) or string.format("|cffffff00|Hachievement:%s|h[%s]|h|r", linkData, displayText);
	end);

	text = text:gsub("|Hachievement:([^|]+)|h%[([^%]]+)%]|h", function(linkData, displayText)
		local achievementID = tonumber(string.match(linkData, "^(%d+)"));
		return achievementID and Achievements.GetAchievementLink(achievementID) or string.format("|cffffff00|Hachievement:%s|h[%s]|h|r", linkData, displayText);
	end);

	return text;
end

local function StripAchievementChatLinks(text, keepBrackets)
	local foundLink = false;
	local strippedText = text:gsub("|c%x%x%x%x%x%x%x%x|Hachievement:[^|]+|h%[([^%]]+)%]|h|r", function(displayText)
		foundLink = true;
		return keepBrackets and ("[" .. displayText .. "]") or displayText;
	end);

	strippedText = strippedText:gsub("|Hachievement:[^|]+|h%[([^%]]+)%]|h", function(displayText)
		foundLink = true;
		return keepBrackets and ("[" .. displayText .. "]") or displayText;
	end);

	return foundLink, strippedText;
end

local function PruneOutgoingAchievementMessages()
	local currentTime = GetTime();
	for index = #recentOutgoingAchievementMessages, 1, -1 do
		if recentOutgoingAchievementMessages[index].expires <= currentTime then
			tremove(recentOutgoingAchievementMessages, index);
		end
	end
end

local function RecordOutgoingAchievementChatMessage(text)
	if type(text) ~= "string" then
		return;
	end

	local foundLink, strippedText = StripAchievementChatLinks(text, false);
	if not foundLink then
		return;
	end

	local _, bracketedText = StripAchievementChatLinks(text, true);
	local linkedText = NormalizeAchievementChatLinks(text);
	local currentTime = GetTime();
	PruneOutgoingAchievementMessages();
	tinsert(recentOutgoingAchievementMessages, {
		strippedText = strippedText,
		bracketedText = bracketedText,
		linkedText = linkedText,
		expires = currentTime + 15,
	});

	while #recentOutgoingAchievementMessages > 12 do
		tremove(recentOutgoingAchievementMessages, 1);
	end
end

local function ConsumeOutgoingAchievementChatMessage(message)
	PruneOutgoingAchievementMessages();

	for index = #recentOutgoingAchievementMessages, 1, -1 do
		local entry = recentOutgoingAchievementMessages[index];
		if message == entry.strippedText or message == entry.bracketedText then
			tremove(recentOutgoingAchievementMessages, index);
			return entry.linkedText;
		end
	end

	return nil;
end

local function IsLocalChatSender(event, sender)
	if event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
		return true;
	end

	local playerName = UnitName("player");
	if not playerName or not sender then
		return false;
	end

	return Ambiguate(sender, "none") == playerName;
end

local function AchievementChatLinkFilter(_, event, message, sender, language, channelString, target, flags, unknown, channelNumber, channelName, unknown2, counter, guid, bnSenderID)
	if type(message) ~= "string" or not IsLocalChatSender(event, sender) then
		return false;
	end

	local linkedMessage = ConsumeOutgoingAchievementChatMessage(message);
	if linkedMessage then
		return false, linkedMessage, sender, language, channelString, target, flags, unknown, channelNumber, channelName, unknown2, counter, guid, bnSenderID;
	end

	return false;
end

local ACHIEVEMENT_CHAT_LINK_EVENTS = {
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER_INFORM",
};

-- Events on which we attempt to *rebuild* a clickable achievement link from
-- bare bracketed text. The send hook strips |Hachievement|h links to plain
-- "[Name]" so the message fits the 255-byte chat cap and so the server
-- doesn't reject the unknown link type. The sender's local echo is restored
-- via the _INFORM filter above; the *recipient* would otherwise see flat
-- "[Name]" text — these filters look the name up in the achievement table
-- and re-wrap it in a real |Hachievement|h link.
local ACHIEVEMENT_INCOMING_REBUILD_EVENTS = {
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_BN_WHISPER",
};

local achievementNameToIdCache;
local function GetAchievementNameToIdMap()
	if achievementNameToIdCache then
		return achievementNameToIdCache;
	end
	local Private = Achievements.private;
	local data = Private and Private.data and Private.data.achievements;
	if type(data) ~= "table" then
		return nil;
	end
	achievementNameToIdCache = {};
	local getClientLocaleText = Achievements.GetClientLocaleText;
	for id, achievement in pairs(data) do
		-- Senders write the name in their own client locale, so match against the
		-- client-locale name rather than an overridden display-locale name.
		local name = getClientLocaleText and getClientLocaleText("achievements", id, "name") or (achievement and achievement.name);
		if type(name) == "string" and name ~= "" and not achievementNameToIdCache[name] then
			achievementNameToIdCache[name] = id;
		end
	end
	return achievementNameToIdCache;
end

local function RebuildIncomingAchievementLinks(text, sender)
	if type(text) ~= "string" or not text:find("[", 1, true) then
		return text, false;
	end

	-- Skip if the message already carries a real achievement link (e.g.
	-- another addon user that doesn't strip them on send).
	if text:find("|Hachievement:", 1, true) then
		return text, false;
	end

	local nameMap = GetAchievementNameToIdMap();
	if not nameMap then
		return text, false;
	end

	local replaced = false;
	local rebuilt = text:gsub("%[([^%[%]]+)%]", function(displayText)
		local id = nameMap[displayText];
		if not id then
			return nil;
		end
		local meta = FindIncomingAchievementLink(sender, id);
		local ownerName = meta and meta.ownerName;
		if not ownerName or ownerName == "" then
			ownerName = Ambiguate(sender or "", "none") or sender or "";
		end
		local link = BuildAchievementLinkFromMeta(id, displayText, meta and meta.guid or "", meta and meta.completionTimestamp or 0, ownerName, meta and meta.criteriaProgress or "");
		replaced = true;
		return link;
	end);

	return rebuilt, replaced;
end

local function IncomingAchievementLinkFilter(_, event, message, sender, language, channelString, target, flags, unknown, channelNumber, channelName, unknown2, counter, guid, bnSenderID)
	if type(message) ~= "string" then
		return false;
	end

	-- The local echo is handled by AchievementChatLinkFilter; don't double
	-- process our own messages here.
	if IsLocalChatSender(event, sender) then
		return false;
	end

	local rebuilt, replaced = RebuildIncomingAchievementLinks(message, sender);
	if replaced then
		return false, rebuilt, sender, language, channelString, target, flags, unknown, channelNumber, channelName, unknown2, counter, guid, bnSenderID;
	end

	return false;
end

local function HookAchievementChatLinks()
	if achievementChatLinksHooked then
		return;
	end

	for _, eventName in ipairs(ACHIEVEMENT_CHAT_LINK_EVENTS) do
		ChatFrame_AddMessageEventFilter(eventName, AchievementChatLinkFilter);
	end

	for _, eventName in ipairs(ACHIEVEMENT_INCOMING_REBUILD_EVENTS) do
		ChatFrame_AddMessageEventFilter(eventName, IncomingAchievementLinkFilter);
	end
	EnsureLinkMetaListener();

	-- Replace the outgoing send functions so we can strip our custom
	-- |Hachievement|h hyperlinks before transmission. The server enforces
	-- a 255-byte cap on chat messages and a single achievement link is
	-- already ~75 characters, so two or more in one message would silently
	-- exceed the limit and the message would never appear. We send the
	-- bracketed text instead and rebuild the rich link on the local echo.
	local originalSendChatMessage = C_ChatInfo.SendChatMessage;
	C_ChatInfo.SendChatMessage = function(text, chatType, language, target, ...)
		if type(text) == "string" then
			local foundLink, strippedText = StripAchievementChatLinks(text, true);
			if foundLink then
				RecordOutgoingAchievementChatMessage(text);
				SendOutgoingAchievementLinkMetas(text, chatType, target);
				return originalSendChatMessage(strippedText, chatType, language, target, ...);
			end
		end
		return originalSendChatMessage(text, chatType, language, target, ...);
	end;

	local originalBNSendWhisper = BNSendWhisper;
	BNSendWhisper = function(target, text, ...)
		if type(text) == "string" then
			local foundLink, strippedText = StripAchievementChatLinks(text, true);
			if foundLink then
				RecordOutgoingAchievementChatMessage(text);
				return originalBNSendWhisper(target, strippedText, ...);
			end
		end
		return originalBNSendWhisper(target, text, ...);
	end;

	achievementChatLinksHooked = true;
end

Achievements.hookAchievementChatLinks = HookAchievementChatLinks;
