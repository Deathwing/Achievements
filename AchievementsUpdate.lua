local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsUpdate.lua");
end

local Update = {};
Achievements.Update = Update;

local SOURCES = {
	{ name = "CurseForge", url = "https://www.curseforge.com/wow/addons/achievements-addon" },
	{ name = "GitHub", url = "https://github.com/Deathwing/Achievements/releases/latest" },
	{ name = "Wago", url = "https://addons.wago.io/addons/achievements" },
	{ name = "WoWInterface", url = "https://www.wowinterface.com/downloads/info27169-Achievements.html" },
};

local warnedVersions = {};
local sourceFrame;
local pendingVersion;
local retryScheduled;

local function GetVersion()
	local ok, version = pcall(C_AddOns.GetAddOnMetadata, "Achievements", "Version");
	return ok and version and tostring(version) or "unknown";
end

local function CompareVersions(left, right)
	local leftParts = {};
	local rightParts = {};
	for part in tostring(left or ""):gmatch("%d+") do
		leftParts[#leftParts + 1] = tonumber(part) or 0;
	end
	for part in tostring(right or ""):gmatch("%d+") do
		rightParts[#rightParts + 1] = tonumber(part) or 0;
	end
	for index = 1, math.max(#leftParts, #rightParts, 1) do
		local difference = (leftParts[index] or 0) - (rightParts[index] or 0);
		if difference ~= 0 then
			return difference;
		end
	end
	return 0;
end

local function Print(message)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(message);
	end
end

local function CreateSourceFrame()
	local frame = CreateFrame("Frame", "AchievementsUpdateSourcesFrame", UIParent, "BackdropTemplate");
	local BUTTONS_PER_ROW, BUTTON_WIDTH, BUTTON_HEIGHT = 2, 170, 28;
	local COL_GAP, ROW_GAP = 10, 6;
	local rows = math.ceil(#SOURCES / BUTTONS_PER_ROW);
	local grid_width = BUTTONS_PER_ROW * BUTTON_WIDTH + (BUTTONS_PER_ROW - 1) * COL_GAP;
	local grid_height = rows * BUTTON_HEIGHT + (rows - 1) * ROW_GAP;
	local frame_width = grid_width + 100;
	frame:SetSize(frame_width, 200); -- height is set below once the text is measured
	frame:SetPoint("CENTER");
	frame:SetFrameStrata("DIALOG");
	frame:SetClampedToScreen(true);
	frame:SetMovable(true);
	frame:EnableMouse(true);
	frame:RegisterForDrag("LeftButton");
	frame:SetScript("OnDragStart", frame.StartMoving);
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing);
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	});

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
	close:SetPoint("TOPRIGHT", -4, -4);

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
	title:SetPoint("TOP", 0, -22);
	title:SetText("Achievements Updates");
	frame.title = title;

	local description = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	description:SetPoint("TOP", title, "BOTTOM", 0, -10);
	description:SetWidth(frame_width - 50);
	description:SetJustifyH("CENTER");
	description:SetText("Choose an official download source, then copy the selected address.");

	-- top margin + title + gap + description + gap + grid + gap + address box + bottom margin
	frame:SetHeight(22 + title:GetStringHeight() + 10 + description:GetStringHeight() + 20
		+ grid_height + 24 + 28 + 24);

	local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate");
	editBox:SetSize(grid_width + 20, 28);
	editBox:SetPoint("BOTTOM", 0, 24);
	editBox:SetAutoFocus(false);
	editBox:SetScript("OnEscapePressed", editBox.ClearFocus);
	frame.editBox = editBox;

	local grid = CreateFrame("Frame", nil, frame);
	grid:SetSize(grid_width, grid_height);
	grid:SetPoint("TOP", description, "BOTTOM", 0, -20);

	for index, source in ipairs(SOURCES) do
		local col = (index - 1) % BUTTONS_PER_ROW;
		local row = math.floor((index - 1) / BUTTONS_PER_ROW);
		local button = CreateFrame("Button", nil, grid, "UIPanelButtonTemplate");
		button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT);
		button:SetPoint("TOPLEFT", grid, "TOPLEFT",
			col * (BUTTON_WIDTH + COL_GAP), -row * (BUTTON_HEIGHT + ROW_GAP));
		button:SetText(source.name);
		button:SetScript("OnClick", function()
			editBox:SetText(source.url);
			editBox:SetFocus();
			editBox:HighlightText();
		end);
	end

	editBox:SetText(SOURCES[1].url);
	frame:Hide();
	return frame;
end

function Update.Show(newVersion)
	if not sourceFrame then
		sourceFrame = CreateSourceFrame();
	end
	if newVersion then
		sourceFrame.title:SetText("Achievements " .. tostring(newVersion) .. " is available");
	else
		sourceFrame.title:SetText("Achievements Updates - v" .. GetVersion());
	end
	sourceFrame:Show();
	sourceFrame:Raise();
end

local TryShowPendingUpdate;

local function ScheduleRetry(delay)
	if retryScheduled then
		return;
	end
	retryScheduled = true;
	C_Timer.After(delay, function()
		TryShowPendingUpdate();
	end);
end

TryShowPendingUpdate = function()
	retryScheduled = nil;
	if not pendingVersion then
		return;
	end
	if AchievementsDB.lastUpdatePopupVersion == pendingVersion then
		pendingVersion = nil;
		return;
	end
	if InCombatLockdown() then
		return;
	end
	-- Only surface the update popup in rested areas (inns/cities). Popping it up
	-- mid-world is too intrusive, so defer and retry until the player is resting.
	if not IsResting() then
		ScheduleRetry(5);
		return;
	end
	-- Parity with Deathlog/MRP: they also defer while their changelog popup
	-- is open. Achievements has no changelog popup, so only combat/resting defer.
	local version = pendingVersion;
	pendingVersion = nil;
	AchievementsDB.lastUpdatePopupVersion = version;
	Update.Show(version);
end

local function ScheduleUpdatePopup(newVersion)
	newVersion = tostring(newVersion or "unknown");
	local detectedVersion = AchievementsDB.newestDetectedUpdateVersion;
	if detectedVersion and CompareVersions(detectedVersion, newVersion) > 0 then
		newVersion = detectedVersion;
	end
	AchievementsDB.newestDetectedUpdateVersion = newVersion;
	if AchievementsDB.lastUpdatePopupVersion and CompareVersions(newVersion, AchievementsDB.lastUpdatePopupVersion) <= 0 then
		return;
	end
	pendingVersion = newVersion;
	ScheduleRetry(3);
end

function Update.Notify(newVersion)
	newVersion = tostring(newVersion or "unknown");
	ScheduleUpdatePopup(newVersion);
	if warnedVersions[newVersion] then
		return;
	end
	warnedVersions[newVersion] = true;
	Print("|cffffff00Achievements:|r A newer version (v" .. newVersion .. ") is available; you are running v" .. GetVersion() .. ". Type |cffffffff/ach update|r for official CurseForge, GitHub, and Wago downloads.");
end

local function FormatVersion(version)
	if type(version) == "number" then
		if version >= 1e9 then
			return date("!%Y-%m-%d", version);
		elseif version >= 10000 then
			return string.format("%d.%d.%d", math.floor(version / 10000), math.floor(version / 100) % 100, version % 100);
		end
	end
	return tostring(version);
end

local function FormatTocVersion(version)
	local stamp = tonumber(version);
	return stamp and stamp >= 1e9 and FormatVersion(stamp) or tostring(version);
end

local function GetMetadata(name, field)
	local ok, value = pcall(C_AddOns.GetAddOnMetadata, name, field);
	return ok and value or nil;
end

--- Print the versions of Achievements and its bundled sub-addons to chat,
--- noting if a newer version has been detected from other players.
function Update.PrintVersions()
	Print("|cffffd200Achievements versions|r");

	local mainVersion = GetVersion();
	Print("  Achievements: |cffffffff" .. mainVersion .. "|r");

	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded;
	local embeds = ", " .. (GetMetadata("Achievements", "X-Embeds") or "") .. ",";
	local function PrintCompanion(label, name, lib)
		local version = GetMetadata(name, "Version");
		local runtimeVersion = lib and lib.VERSION;
		local standaloneLoaded = version and isLoaded and isLoaded(name);
		local embedded = embeds:find(", " .. name .. ",", 1, true) ~= nil;
		if runtimeVersion ~= nil then
			local tocVersion = (tostring(version or ""):gsub("^v", ""));
			local standaloneActive = standaloneLoaded and (tostring(runtimeVersion) == tocVersion or FormatVersion(runtimeVersion) == tocVersion or tostring(lib.version) == tocVersion);
			local note = "";
			if standaloneLoaded and not standaloneActive then
				note = " |cff999999(" .. (embedded and "embedded in Achievements" or "another addon's copy") .. "; standalone " .. FormatTocVersion(version) .. " superseded)|r";
			elseif standaloneLoaded then
				note = " |cff999999(standalone)|r";
			elseif embedded then
				note = " |cff999999(embedded in Achievements)|r";
			end
			Print("  " .. label .. ": |cffffffff" .. FormatVersion(runtimeVersion) .. "|r" .. note);
		elseif standaloneLoaded then
			Print("  " .. label .. ": |cffffffff" .. FormatTocVersion(version) .. "|r |cff999999(standalone)|r");
		elseif version then
			Print("  " .. label .. ": |cffffffff" .. FormatTocVersion(version) .. "|r |cff999999(installed, disabled)|r");
		end
	end

	PrintCompanion("AchievementsData", "AchievementsData", rawget(_G, "AchievementsData"));

	-- Note a known newer version, if one has been detected from other players.
	local detected = AchievementsDB and AchievementsDB.newestDetectedUpdateVersion;
	if detected and CompareVersions(detected, mainVersion) > 0 then
		Print("|cffff5555Update available:|r Achievements v" .. tostring(detected)
			.. " has been seen from other players. Type |cffffffff/ach update|r for download sources.");
	else
		Print("|cff55ff55You're up to date|r as far as Achievements can tell.");
	end
end

SLASH_ACHIEVEMENTSUPDATES1 = "/ach-update";
SLASH_ACHIEVEMENTSUPDATES2 = "/achievements-update";
SlashCmdList["ACHIEVEMENTSUPDATES"] = function()
	Update.Show();
end

local function GetAvailableDisplayLocaleText()
	local locales = Achievements.GetAvailableDisplayLocales();
	table.insert(locales, 1, "auto");
	return table.concat(locales, ", ");
end

local function PrintDisplayLocaleStatus()
	local selectedLocale, effectiveLocale = Achievements.GetDisplayLocale();
	Print("|cffffd200Achievements display locale:|r selected: " .. selectedLocale .. "; effective: " .. effectiveLocale .. ".");
	Print("Available display locales: " .. GetAvailableDisplayLocaleText() .. ".");
	if Achievements.IsDisplayLocaleOverridingClientLocale and Achievements.IsDisplayLocaleOverridingClientLocale() then
		Print("Achievement content is shown in " .. effectiveLocale .. " while the game client runs in " .. GetLocale() .. ". Blizzard-owned labels stay in the client language.");
	end
end

local function PrintDroppedDisplayLocaleWarning()
	local droppedLocale = Achievements.GetDroppedDisplayLocale and Achievements.GetDroppedDisplayLocale();
	if not droppedLocale then
		return;
	end
	Print("|cffff2020Achievements:|r display locale '" .. droppedLocale .. "' is not available in the installed AchievementsData package; falling back to auto.");
	Print("Available display locales: " .. GetAvailableDisplayLocaleText() .. ".");
end

local function HandleDisplayLocaleCommand(argument)
	if argument == "" then
		PrintDisplayLocaleStatus();
		return;
	end

	local canonicalLocale, changed = Achievements.SetDisplayLocale(argument);
	if not canonicalLocale then
		Print("|cffff2020Achievements:|r Unknown display locale '" .. tostring(argument) .. "'.");
		Print("Available display locales: " .. GetAvailableDisplayLocaleText() .. ".");
		return;
	end
	if not changed then
		Print("|cffffd200Achievements:|r display locale " .. canonicalLocale .. " is already selected.");
		return;
	end

	Print("|cffffd200Achievements:|r display locale set to " .. canonicalLocale .. ". Reloading interface.");
	ReloadUI();
end

-- Main slash command, mirroring Deathlog (/dl update) and MRP (/mrp update).
-- Without a subcommand it toggles the achievement frame.
SLASH_ACHIEVEMENTS1 = "/ach";
SLASH_ACHIEVEMENTS2 = "/achievements";
SlashCmdList["ACHIEVEMENTS"] = function(msg)
	local command, argument = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$");
	command = string.lower(command or "");
	if command == "update" or command == "updates" then
		Update.Show();
		return;
	elseif command == "version" or command == "versions" then
		Update.PrintVersions();
		return;
	elseif command == "locale" then
		HandleDisplayLocaleCommand(argument);
		return;
	end
	Achievements.ToggleAchievementFrame();
end

local eventFrame = CreateFrame("Frame");
eventFrame:RegisterEvent("PLAYER_LOGIN");
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		PrintDroppedDisplayLocaleWarning();
		local detectedVersion = AchievementsDB.newestDetectedUpdateVersion;
		if detectedVersion and CompareVersions(detectedVersion, GetVersion()) > 0 then
			ScheduleUpdatePopup(detectedVersion);
		else
			AchievementsDB.newestDetectedUpdateVersion = nil;
		end
		return;
	end
	TryShowPendingUpdate();
end);
