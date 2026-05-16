local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsCriteriaResolvers.lua");
end

local Private = Achievements.private;
local data = Private.data;
local ACHIEVEMENT_DATA = data.achievements;
local CRITERIA_DATA = data.criteria;
local CRITERIA_TREE_DATA = data.criteriaTrees;
local CRITERIA_TREE_CHILDREN = data.criteriaTreeChildren;
local ACHIEVEMENT_BY_CRITERIA = data.achievementByCriteria or {};
local MODIFIER_TREE_DATA = data.modifierTrees or {};
local MODIFIER_TREE_CHILDREN = data.modifierTreeChildren or {};

-- Forward declarations for modifier-tree helpers used in early code paths.
local RecordCriteriaEvent;
local BuildKillCombatContext;
local GetPlayerRaceID;
local GetCurrentMapID;
local GetCurrentZoneAreaID;
local GetCreatureIDFromGUID;
local EvaluateCriteriaModifier;
local EvaluateModifierTreeNode;
local QUEST_AREA_QUESTS = data.questAreaQuests or {};
local QUEST_SORT_QUESTS = data.questSortQuests or {};
local UI_MAP_DATA = data.uiMaps or {};
local WORLD_MAP_OVERLAY_DATA = data.worldMapOverlays or {};
local SPELL_NAME_DATA = data.spellNames or {};
local SKILL_LINE_DATA = data.skillLines or {};
local SKILL_LINE_ABILITY_DATA = data.skillLineAbilities or {};
local FACTION_DATA = data.factions or {};
local ITEM_DATA = data.items or {};
local EMOTE_DATA = data.emotes or {};

local function AddDebugPart(parts, name, value)
	if value ~= nil then
		parts[#parts + 1] = name .. "=" .. tostring(value);
	end
end

local function FormatDebugContext(ctx)
	if type(ctx) ~= "table" then
		return "";
	end

	local parts = {};
	AddDebugPart(parts, "achievement", ctx.achievementID);
	AddDebugPart(parts, "criteria", ctx.criteriaID);
	AddDebugPart(parts, "type", ctx.criteriaType);
	AddDebugPart(parts, "asset", ctx.assetID);
	AddDebugPart(parts, "item", ctx.itemID);
	AddDebugPart(parts, "itemClass", ctx.itemClass);
	AddDebugPart(parts, "itemSubclass", ctx.itemSubclass);
	AddDebugPart(parts, "itemLevel", ctx.itemLevel);
	AddDebugPart(parts, "itemQuality", ctx.itemQuality);
	if #parts == 0 then
		return "";
	end
	return " (" .. table.concat(parts, ", ") .. ")";
end

local function DebugDataInvariant(onceKey, message)
	if Private.IsDebugBuild and Private.IsDebugBuild() and Private.DebugWarning then
		Private.DebugWarning(onceKey, message);
	end
end

local FACTION_ALLIANCE = 1;
local FACTION_HORDE = 0;

local CRITERIA_TREE_OPERATOR = {
	SINGLE = 0,
	SINGLE_NOT_COMPLETED = 1,
	ALL = 4,
	SUM_CHILDREN = 5,
	MAX_CHILD = 6,
	COUNT_DIRECT_CHILDREN = 7,
	ANY = 8,
	SUM_CHILDREN_WEIGHT = 9,
};

local CRITERIA_TREE_FLAGS = {
	PROGRESS_BAR = 0x1,
	DO_NOT_DISPLAY = 0x2,
	IS_DATE = 0x4,
	IS_MONEY = 0x8,
	TOAST_ON_COMPLETE = 0x10,
	USE_OBJECTS_DESCRIPTION = 0x20,
	SHOW_FACTION_SPECIFIC_CHILD = 0x40,
	DISPLAY_ALL_CHILDREN = 0x80,
	AWARD_BONUS_REP = 0x100,
	TREAT_AS_ALLIANCE = 0x200,
	TREAT_AS_HORDE = 0x400,
	DISPLAY_AS_FRACTION = 0x800,
	IS_FOR_QUEST = 0x1000,
};

local CRITERIA_FLAGS = {
	FAIL_ACHIEVEMENT = 0x1,
	RESET_ON_START = 0x2,
	SERVER_ONLY = 0x4,
	ALWAYS_SAVE_TO_DB = 0x8,
	ALLOW_DECREMENT = 0x10,
	IS_FOR_QUEST = 0x20,
};

local CRITERIA_START_EVENT = {
	NONE = 0,
	REACH_LEVEL = 1,
	COMPLETE_DAILY_QUEST = 2,
	START_BATTLEGROUND = 3,
	WIN_RANKED_ARENA_MATCH = 4,
	GAIN_AURA = 5,
	GAIN_AURA_EFFECT = 6,
	CAST_SPELL = 7,
	HAVE_SPELL_CAST_ON_YOU = 8,
	ACCEPT_QUEST = 9,
	KILL_NPC = 10,
	KILL_PLAYER = 11,
	USE_ITEM = 12,
	SEND_EVENT = 13,
	BEGIN_SCENARIO_STEP = 14,
};

local CRITERIA_FAIL_EVENT = {
	NONE = 0,
	DEATH = 1,
	DAILY_QUEST_STREAK_EXPIRED = 2,
	LEAVE_BATTLEGROUND = 3,
	LOSE_RANKED_ARENA_MATCH = 4,
	LOSE_AURA = 5,
	GAIN_AURA = 6,
	GAIN_AURA_EFFECT = 7,
	CAST_SPELL = 8,
	HAVE_SPELL_CAST_ON_YOU = 9,
	MODIFY_PARTY_STATUS = 10,
	LOSE_PET_BATTLE = 11,
	BATTLE_PET_DIES = 12,
	DAILY_QUESTS_CLEARED = 13,
	SEND_EVENT = 14,
};

local CRITERIA_TYPE = {
	KILL_NPC = 0,
	WIN_BATTLEGROUND = 1,
	COMPLETE_RESEARCH_PROJECT = 2,
	COMPLETE_ANY_RESEARCH_PROJECT = 3,
	FIND_RESEARCH_OBJECT = 4,
	REACH_LEVEL = CRITERIA_TYPE_REACH_LEVEL or 5,
	EXHAUST_RESEARCH_SITE = 6,
	SKILL_RAISED = 7,
	EARN_ACHIEVEMENT = CRITERIA_TYPE_ACHIEVEMENT or 8,
	QUESTS_COMPLETED = 9,
	COMPLETE_ANY_DAILY_QUEST_PER_DAY = 10,
	QUESTS_COMPLETED_IN_AREA = 11,
	CURRENCY_GAINED = 12,
	DAMAGE_DEALT = 13,
	DAILY_QUESTS_COMPLETED = 14,
	PARTICIPATE_IN_BATTLEGROUND = 15,
	DIE_ON_MAP = 16,
	DIE_ANYWHERE = 17,
	DIE_IN_INSTANCE_WITH_MAX_PLAYERS = 18,
	RUN_INSTANCE_WITH_MAX_PLAYERS = 19,
	GET_KILLED_BY_CREATURE = 20,
	DESIGNER_VALUE = 21,
	COMPLETE_ANY_CHALLENGE_MODE = 22,
	DIE_TO_PLAYER = 23,
	MAX_DISTANCE_FALLEN_WITHOUT_DYING = 24,
	EARN_CHALLENGE_MODE_MEDAL = 25,
	DIE_TO_ENVIRONMENTAL_DAMAGE = 26,
	COMPLETE_QUEST = 27,
	HAVE_SPELL_CAST_ON_YOU = 28,
	CAST_SPELL = 29,
	WORLD_STATE_UI_VALUE_MODIFIED = 30,
	KILL_PLAYER_IN_AREA = 31,
	WIN_ARENA = 32,
	PARTICIPATE_IN_ARENA = 33,
	LEARN_OR_KNOW_SPELL = 34,
	HONORABLE_KILL = 35,
	ACQUIRE_ITEM = 36,
	WIN_RANKED_ARENA_MATCH = 37,
	TEAM_ARENA_RATING = 38,
	PERSONAL_ARENA_RATING = 39,
	SKILL_STEP = 40,
	USE_ITEM = 41,
	LOOT_ITEM = 42,
	REVEAL_WORLD_MAP_OVERLAY = 43,
	DEPRECATED_PVP_TITLES = 44,
	BANK_SLOTS_PURCHASED = 45,
	REPUTATION_GAINED = 46,
	TOTAL_EXALTED_FACTIONS = 47,
	GOT_HAIRCUT = 48,
	EQUIP_ITEM_IN_SLOT = 49,
	NEED_ROLL = 50,
	GREED_ROLL = 51,
	KILLING_BLOW_TO_CLASS = 52,
	KILLING_BLOW_TO_RACE = 53,
	EMOTE = 54,
	HEALING_DONE = 55,
	KILLING_BLOW = 56,
	EQUIP_ITEM = 57,
	QUESTS_COMPLETED_IN_SORT = 58,
	SELL_ITEMS_TO_VENDORS = 59,
	MONEY_SPENT_ON_RESPECS = 60,
	TOTAL_RESPECS = 61,
	MONEY_EARNED_FROM_QUESTING = 62,
	MONEY_SPENT_ON_TAXIS = 63,
	KILL_SPAWN_REGION_UNITS = 64,
	MONEY_SPENT_AT_BARBER = 65,
	MONEY_SPENT_ON_POSTAGE = 66,
	MONEY_LOOTED_FROM_CREATURES = 67,
	USE_GAME_OBJECT = 68,
	GAIN_AURA = 69,
	KILL_PLAYER_NO_HONOR_CHECK = 70,
	COMPLETE_CHALLENGE_MODE_ON_MAP = 71,
	CATCH_FISH_IN_POOL = 72,
	PLAYER_TRIGGER_GAME_EVENT = 73,
	LOGIN = 74,
	LEARN_SPELL_FROM_SKILL_LINE = 75,
	WIN_DUEL = 76,
	LOSE_DUEL = 77,
	KILL_ANY_NPC = 78,
	CREATE_ITEMS_BY_CASTING_LIMITED = 79,
	MONEY_EARNED_FROM_AUCTIONS = 80,
	BATTLE_PET_ACHIEVEMENT_POINTS = 81,
	AUCTION_ITEMS_POSTED = 82,
	HIGHEST_AUCTION_BID = 83,
	AUCTIONS_WON = 84,
	HIGHEST_ITEM_SOLD_VALUE = 85,
	MOST_MONEY_OWNED = 86,
	TOTAL_REVERED_FACTIONS = 87,
	TOTAL_HONORED_FACTIONS = 88,
	TOTAL_FACTIONS_ENCOUNTERED = 89,
	LOOT_ANY_ITEM = 90,
	OBTAIN_ANY_ITEM = 91,
	ANYONE_TRIGGER_SCENARIO_EVENT = 92,
	ROLL_ANY_NEED = 93,
	ROLL_ANY_GREED = 94,
	RELEASED_SPIRIT = 95,
	ACCOUNT_KNOWS_PET = 96,
	DEFEAT_ENCOUNTER_WHILE_ELIGIBLE_FOR_LOOT = 97,
	HIGHEST_DAMAGE_IN_SINGLE_ABILITY = 101,
	MOST_DAMAGE_TAKEN_IN_SINGLE_HIT = 102,
	TOTAL_DAMAGE_TAKEN = 103,
	LARGEST_HEAL_CAST = 104,
	TOTAL_HEALING_RECEIVED = 105,
	LARGEST_HEAL_RECEIVED = 106,
	ABANDON_ANY_QUEST = 107,
	BUY_TAXI = 108,
	GET_LOOT_BY_ACQUISITION = 109,
	LAND_TARGETED_SPELL = 110,
	LEARN_TRADESKILL_SKILL_LINE = 112,
	HONORABLE_KILLS_LOGIN_COUNTER = 113,
	ACCEPT_SUMMON = 114,
	EARN_ACHIEVEMENT_POINTS = 115,
	DISENCHANT_ROLL = 116,
	ROLL_ANY_DISENCHANT = 117,
	COMPLETE_LFG_DUNGEON = 118,
	COMPLETE_LFG_DUNGEON_WITH_STRANGERS = 119,
	KICKED_IN_LFG_INITIATOR = 120,
	KICKED_IN_LFG_VOTER = 121,
	KICKED_IN_LFG_TARGET = 122,
	ABANDON_LFG_DUNGEON = 123,
	GUILD_REPAIR_AMOUNT_SPENT = 124,
	GUILD_ATTAINED_LEVEL = 125,
	CREATE_ITEMS_BY_CASTING = 126,
	FISH_IN_ANY_POOL = 127,
	GUILD_BANK_TABS_PURCHASED = 128,
	EARN_GUILD_ACHIEVEMENT_POINTS = 129,
	WIN_ANY_BATTLEGROUND = 130,
	PARTICIPATE_IN_ANY_BATTLEGROUND = 131,
	BATTLEGROUND_RATING = 132,
	GUILD_TABARD_CREATED = 133,
	GUILD_QUESTS_COMPLETED = 134,
	GUILD_HONORABLE_KILLS = 135,
	GUILD_KILL_ANY_NPC = 136,
	GROUPED_TANK_LEFT_LFG_EARLY = 137,
	COMPLETE_GUILD_CHALLENGE = 138,
	COMPLETE_ANY_GUILD_CHALLENGE = 139,
	MARKED_AFK_IN_BATTLEGROUND = 140,
	REMOVED_FOR_AFK_IN_BATTLEGROUND = 141,
	START_ANY_BATTLEGROUND_AFK_TRACKING = 142,
	COMPLETE_ANY_BATTLEGROUND_AFK_TRACKING = 143,
	MARKED_SOMEONE_AFK = 144,
	COMPLETE_LFR_DUNGEON = 145,
	ABANDON_LFR_DUNGEON = 146,
	KICKED_IN_LFR_INITIATOR = 147,
	KICKED_IN_LFR_VOTER = 148,
	KICKED_IN_LFR_TARGET = 149,
	GROUPED_TANK_LEFT_LFR_EARLY = 150,
	COMPLETE_SCENARIO = 151,
	COMPLETE_SCENARIO_BY_ID = 152,
	ENTER_AREA_TRIGGER = 153,
	LEAVE_AREA_TRIGGER = 154,
	ACCOUNT_LEARNED_NEW_PET = 155,
	ACCOUNT_UNIQUE_PETS_OWNED = 156,
	ACCOUNT_OBTAIN_PET_THROUGH_BATTLE = 157,
	WIN_PET_BATTLE = 158,
	LOSE_PET_BATTLE = 159,
	ACCOUNT_BATTLE_PET_REACHED_LEVEL = 160,
	PLAYER_OBTAIN_PET_THROUGH_BATTLE = 161,
	PLAYER_EARN_PET_LEVEL = 162,
	ENTER_MAP_AREA = 163,
	LEAVE_MAP_AREA = 164,
	DEFEAT_ENCOUNTER = 165,
	COMPLETE_ANY_QUEST = 203,
	EARN_LICENSE = 204,
	ENTER_TOP_LEVEL_MAP_AREA = 225,
	LEAVE_TOP_LEVEL_MAP_AREA = 226,
	TRACKING_QUEST_COMPLETED = 250,
	FACTION_RELATED = 251,
	GAIN_LEVELS = 253,
	COMPLETE_QUEST_COUNT_ON_ACCOUNT = 257,
	AREA_TABLE_RELATED = 258,
	QUEST_SORT_RELATED = 259,
	WARBAND_BANK_TAB_PURCHASED = 260,
	REACH_RENOWN_LEVEL = 261,
	LEARN_TAXI_NODE = 262,
};

local CRITERIA_TYPE_LABELS = {
	[0] = "Kill NPC",
	[1] = "Win battleground",
	[2] = "Complete research project",
	[3] = "Complete any research project",
	[4] = "Find research object",
	[5] = "Reach level",
	[6] = "Exhaust any research site",
	[7] = "Skill raised",
	[8] = "Earn achievement",
	[9] = "Count of complete quests",
	[10] = "Complete any daily quest per day",
	[11] = "Complete quests in area",
	[12] = "Currency gained",
	[13] = "Damage dealt",
	[14] = "Complete daily quest",
	[15] = "Participate in battleground",
	[16] = "Die on map",
	[17] = "Die anywhere",
	[18] = "Die in instance with max players",
	[19] = "Run instance with max players",
	[20] = "Get killed by creature",
	[21] = "Designer value",
	[22] = "Complete any challenge mode",
	[23] = "Die to player",
	[24] = "Maximum distance fallen without dying",
	[25] = "Earn challenge mode medal",
	[26] = "Die to environmental damage",
	[27] = "Complete quest",
	[28] = "Have spell cast on you",
	[29] = "Cast spell",
	[30] = "Tracked WorldStateUI value modified",
	[31] = "Kill someone in PVP in area",
	[32] = "Win arena",
	[33] = "Participate in arena",
	[34] = "Learn or know spell",
	[35] = "Earn an honorable kill",
	[36] = "Acquire item",
	[37] = "Win a ranked arena match",
	[38] = "Earn team arena rating",
	[39] = "Earn personal arena rating",
	[40] = "Achieve skill step",
	[41] = "Use item",
	[42] = "Loot item",
	[43] = "Reveal world map overlay",
	[44] = "Deprecated PVP titles",
	[45] = "Bank slots purchased",
	[46] = "Reputation gained with faction",
	[47] = "Total exalted factions",
	[48] = "Got a haircut",
	[49] = "Equip item in slot",
	[50] = "Roll need and get value",
	[51] = "Roll greed and get value",
	[52] = "Deliver killing blow to class",
	[53] = "Deliver killing blow to race",
	[54] = "Do emote",
	[55] = "Healing done",
	[56] = "Delivered killing blow",
	[57] = "Equip item",
	[58] = "Complete quests in quest sort",
	[59] = "Sell items to vendors",
	[60] = "Money spent on respecs",
	[61] = "Total respecs",
	[62] = "Money earned from questing",
	[63] = "Money spent on taxis",
	[64] = "Killed all units in spawn region",
	[65] = "Money spent at barber shop",
	[66] = "Money spent on postage",
	[67] = "Money looted from creatures",
	[68] = "Use game object",
	[69] = "Gain aura",
	[70] = "Kill player without honor check",
	[71] = "Complete challenge mode on map",
	[72] = "Catch fish in fishing hole",
	[73] = "Player triggers game event",
	[74] = "Login",
	[75] = "Learn spell from skill line",
	[76] = "Win duel",
	[77] = "Lose duel",
	[78] = "Kill any NPC",
	[79] = "Create items by casting spell with limit",
	[80] = "Money earned from auctions",
	[81] = "Battle pet achievement points earned",
	[82] = "Items posted at auction",
	[83] = "Highest auction bid",
	[84] = "Auctions won",
	[85] = "Highest coin value of item sold",
	[86] = "Most money owned",
	[87] = "Total revered factions",
	[88] = "Total honored factions",
	[89] = "Total factions encountered",
	[90] = "Loot any item",
	[91] = "Obtain any item",
	[92] = "Anyone triggers scenario game event",
	[93] = "Roll any number on need",
	[94] = "Roll any number on greed",
	[95] = "Released spirit",
	[96] = "Account knows pet",
	[97] = "Defeat encounter while eligible for loot",
	[101] = "Highest damage done in one ability",
	[102] = "Most damage taken in one hit",
	[103] = "Total damage taken",
	[104] = "Largest heal cast",
	[105] = "Total healing received",
	[106] = "Largest heal received",
	[107] = "Abandon any quest",
	[108] = "Buy a taxi",
	[109] = "Get loot by acquisition",
	[110] = "Land targeted spell",
	[112] = "Learn tradeskill skill line",
	[113] = "Honorable kills login counter",
	[114] = "Accept summon",
	[115] = "Earn achievement points",
	[116] = "Roll disenchant and get value",
	[117] = "Roll any number on disenchant",
	[118] = "Completed LFG dungeon",
	[119] = "Completed LFG dungeon with strangers",
	[120] = "Kicked in LFG dungeon as initiator",
	[121] = "Kicked in LFG dungeon as voter",
	[122] = "Kicked in LFG dungeon as target",
	[123] = "Abandoned LFG dungeon",
	[124] = "Guild repair amount spent",
	[125] = "Guild attained level",
	[126] = "Created items by casting spell",
	[127] = "Fish in any pool",
	[128] = "Guild bank tabs purchased",
	[129] = "Earn guild achievement points",
	[130] = "Win any battleground",
	[131] = "Participate in any battleground",
	[132] = "Earn battleground rating",
	[133] = "Guild tabard created",
	[134] = "Count of complete quests for guild",
	[135] = "Honorable kills for guild",
	[136] = "Kill any NPC for guild",
	[137] = "Grouped tank left early in LFG dungeon",
	[138] = "Complete guild challenge",
	[139] = "Complete any guild challenge",
	[140] = "Marked AFK in battleground",
	[141] = "Removed for being AFK in battleground",
	[142] = "Start any battleground AFK tracking",
	[143] = "Complete any battleground AFK tracking",
	[144] = "Marked someone for being AFK",
	[145] = "Completed LFR dungeon",
	[146] = "Abandoned LFR dungeon",
	[147] = "Kicked in LFR dungeon as initiator",
	[148] = "Kicked in LFR dungeon as voter",
	[149] = "Kicked in LFR dungeon as target",
	[150] = "Grouped tank left early in LFR dungeon",
	[151] = "Complete scenario",
	[152] = "Complete scenario by ID",
	[153] = "Enter area trigger",
	[154] = "Leave area trigger",
	[155] = "Account learned new pet",
	[156] = "Account unique pets owned",
	[157] = "Account obtain pet through battle",
	[158] = "Win pet battle",
	[159] = "Lose pet battle",
	[160] = "Account battle pet reached level",
	[161] = "Player obtain pet through battle",
	[162] = "Player actively earn pet level",
	[163] = "Enter map area",
	[164] = "Leave map area",
	[165] = "Defeat encounter",
	[166] = "Garrison building place any",
	[167] = "Garrison building place specific",
	[168] = "Garrison building activate any",
	[169] = "Garrison building activate specific",
	[170] = "Garrison upgrade tier",
	[171] = "Garrison mission start any follower type",
	[172] = "Garrison mission start specific",
	[173] = "Garrison mission succeed any follower type",
	[174] = "Garrison mission succeed specific",
	[175] = "Garrison follower recruit any",
	[176] = "Garrison follower recruit specific",
	[177] = "Garrison acquire",
	[178] = "Garrison blueprint learn any",
	[179] = "Garrison blueprint learn specific",
	[180] = "Garrison specialization learn any",
	[181] = "Garrison specialization learn specific",
	[182] = "Garrison shipment collected",
	[183] = "Garrison follower item level changed",
	[184] = "Garrison follower level changed",
	[185] = "Learn toy",
	[186] = "Learn any toy",
	[187] = "Garrison follower quality upgraded",
	[188] = "Learn heirloom",
	[189] = "Learn any heirloom",
	[190] = "Earn artifact XP",
	[191] = "Artifact power ranks purchased",
	[192] = "Learn transmog",
	[193] = "Learn any transmog",
	[194] = "Player honor level increase",
	[195] = "Player prestige level increase",
	[196] = "Actively level to level",
	[197] = "Garrison talent complete research any",
	[198] = "Garrison talent complete research specific",
	[199] = "Learn any transmog in slot",
	[200] = "Recruit any garrison troop",
	[201] = "Garrison talent start research any",
	[202] = "Garrison talent start research specific",
	[203] = "Complete any quest",
	[204] = "Earn license",
	[205] = "Account collect transmog set group",
	[206] = "Player paragon level increase with faction",
	[207] = "Player has earned honor",
	[208] = "Kill NPC scenario criteria",
	[209] = "Artifact power rank purchased",
	[210] = "Choose any relic talent",
	[211] = "Choose relic talent",
	[212] = "Earn expansion level",
	[213] = "Account honor level reached",
	[214] = "Earn artifact experience for Azerite item",
	[215] = "Azerite level reached",
	[216] = "Mythic plus completed",
	[217] = "Scenario group completed",
	[218] = "Complete any replay quest",
	[219] = "Buy items from vendors",
	[220] = "Sell items to vendors",
	[221] = "Reach max level",
	[222] = "Memorize spell",
	[223] = "Learn transmog illusion",
	[224] = "Learn any transmog illusion",
	[225] = "Enter top level map area",
	[226] = "Leave top level map area",
	[227] = "Socket garrison talent",
	[228] = "Socket any soulbind conduit",
	[229] = "Obtain any item with currency value",
	[230] = "Mythic plus rating attained",
	[231] = "Spent talent point",
	[234] = "Display season",
	[239] = "Mythic plus display season ended",
	[240] = "Participate in rated solo shuffle round",
	[243] = "Gain reputation amount with faction",
	[246] = "Crafting order type",
	[249] = "Perks program month complete",
	[250] = "Complete tracking quest",
	[251] = "Faction related",
	[253] = "Gain levels",
	[257] = "Complete quest count on account",
	[258] = "Area table related",
	[259] = "Quest sort related",
	[260] = "Warband bank tab purchased",
	[261] = "Reach renown level",
	[262] = "Learn taxi node",
};

local Resolvers = Achievements.criteriaResolvers or {};
Achievements.criteriaResolvers = Resolvers;
Resolvers.criteriaTypes = CRITERIA_TYPE;
Resolvers.criteriaTypeLabels = CRITERIA_TYPE_LABELS;
Resolvers.criteriaTreeOperators = CRITERIA_TREE_OPERATOR;
Resolvers.criteriaTreeFlags = CRITERIA_TREE_FLAGS;
Resolvers.criteriaFlags = CRITERIA_FLAGS;
Resolvers.criteriaStartEvents = CRITERIA_START_EVENT;
Resolvers.criteriaFailEvents = CRITERIA_FAIL_EVENT;
Resolvers.criteriaTypeHandlers = Resolvers.criteriaTypeHandlers or {};
Resolvers.criteriaTreeOperatorHandlers = Resolvers.criteriaTreeOperatorHandlers or {};
Resolvers.creatures = data.creatures or {};
Resolvers.questAreaQuests = QUEST_AREA_QUESTS;
Resolvers.questSortQuests = QUEST_SORT_QUESTS;
Resolvers.uiMaps = UI_MAP_DATA;
Resolvers.worldMapOverlays = WORLD_MAP_OVERLAY_DATA;
Resolvers.spellNames = SPELL_NAME_DATA;
Resolvers.skillLines = SKILL_LINE_DATA;
Resolvers.factions = FACTION_DATA;
Resolvers.items = ITEM_DATA;
Resolvers.emotes = EMOTE_DATA;

function Resolvers.GetEmptyCriteriaList()
	Resolvers.emptyCriteriaList = Resolvers.emptyCriteriaList or {};
	return Resolvers.emptyCriteriaList;
end

function Resolvers.GetRecordableCriteriaByType(criteriaType)
	criteriaType = tonumber(criteriaType);
	if not criteriaType then
		return Resolvers.GetEmptyCriteriaList();
	end

	if not Resolvers.recordableCriteriaByType then
		local cache = {};
		for _, criteria in pairs(CRITERIA_DATA) do
			if Resolvers.IsClientRecordableCriteria(criteria) then
				local currentType = tonumber(criteria.type);
				if currentType then
					cache[currentType] = cache[currentType] or {};
					tinsert(cache[currentType], criteria);
				end
			end
		end
		Resolvers.recordableCriteriaByType = cache;
	end

	return Resolvers.recordableCriteriaByType[criteriaType] or Resolvers.GetEmptyCriteriaList();
end

function Resolvers.GetCriteriaByStartEvent(startEvent)
	startEvent = tonumber(startEvent);
	if not startEvent then
		return Resolvers.GetEmptyCriteriaList();
	end

	if not Resolvers.criteriaByStartEvent then
		local cache = {};
		for _, criteria in pairs(CRITERIA_DATA) do
			local currentEvent = tonumber(criteria.startEvent);
			if currentEvent then
				cache[currentEvent] = cache[currentEvent] or {};
				tinsert(cache[currentEvent], criteria);
			end
		end
		Resolvers.criteriaByStartEvent = cache;
	end

	return Resolvers.criteriaByStartEvent[startEvent] or Resolvers.GetEmptyCriteriaList();
end

function Resolvers.GetRecordableCriteriaByFailEvent(failEvent)
	failEvent = tonumber(failEvent);
	if not failEvent then
		return Resolvers.GetEmptyCriteriaList();
	end

	if not Resolvers.recordableCriteriaByFailEvent then
		local cache = {};
		for _, criteria in pairs(CRITERIA_DATA) do
			if Resolvers.IsClientRecordableCriteria(criteria) then
				local currentEvent = tonumber(criteria.failEvent);
				if currentEvent then
					cache[currentEvent] = cache[currentEvent] or {};
					tinsert(cache[currentEvent], criteria);
				end
			end
		end
		Resolvers.recordableCriteriaByFailEvent = cache;
	end

	return Resolvers.recordableCriteriaByFailEvent[failEvent] or Resolvers.GetEmptyCriteriaList();
end

function Resolvers.MarkCriteriaRefreshType(criteriaTypes, criteriaType)
	criteriaType = tonumber(criteriaType);
	if not criteriaType then
		return criteriaTypes;
	end
	criteriaTypes = criteriaTypes or {};
	criteriaTypes[criteriaType] = true;
	return criteriaTypes;
end

function Resolvers.ScheduleCriteriaTypesRefresh(criteriaTypes, showAlerts, delay, reason)
	if not criteriaTypes then
		return false;
	end
	if Achievements.ScheduleCriteriaTypeRefresh then
		Achievements.ScheduleCriteriaTypeRefresh(criteriaTypes, showAlerts, delay, reason);
		return true;
	end
	if Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(showAlerts);
		return true;
	end
	return false;
end

function Resolvers.BuildPlayerAuraSnapshot(unit)
	local snapshot = { spellIDs = {}, names = {} };
	if not UnitAura then
		return snapshot;
	end
	unit = unit or "player";
	for filterIndex = 1, 2 do
		local filter = filterIndex == 1 and "HELPFUL" or "HARMFUL";
		for auraIndex = 1, 40 do
			local name, _, _, _, _, _, _, _, _, auraSpellID = UnitAura(unit, auraIndex, filter);
			if not name then
				break;
			end
			if type(name) == "string" and name ~= "" then
				snapshot.names[name] = true;
			end
			auraSpellID = tonumber(auraSpellID) or 0;
			if auraSpellID ~= 0 then
				snapshot.spellIDs[auraSpellID] = true;
			end
		end
	end
	return snapshot;
end

function Resolvers.GetAuraCriteriaCache()
	if Resolvers.auraCriteriaCache then
		return Resolvers.auraCriteriaCache;
	end

	local cache = { gains = {}, starts = {}, fails = {} };
	for _, criteria in pairs(CRITERIA_DATA) do
		if Resolvers.IsClientRecordableCriteria(criteria) then
			if criteria.type == CRITERIA_TYPE.GAIN_AURA and criteria.asset and criteria.asset ~= 0 then
				tinsert(cache.gains, criteria);
			end

			local startSpellID = criteria.startAsset ~= 0 and criteria.startAsset or criteria.asset;
			if startSpellID and startSpellID ~= 0 and (criteria.startEvent == CRITERIA_START_EVENT.GAIN_AURA or criteria.startEvent == CRITERIA_START_EVENT.GAIN_AURA_EFFECT) then
				tinsert(cache.starts, criteria);
			end

			local failSpellID = criteria.failAsset ~= 0 and criteria.failAsset or criteria.asset;
			if failSpellID and failSpellID ~= 0 and (criteria.failEvent == CRITERIA_FAIL_EVENT.GAIN_AURA or criteria.failEvent == CRITERIA_FAIL_EVENT.GAIN_AURA_EFFECT or criteria.failEvent == CRITERIA_FAIL_EVENT.LOSE_AURA) then
				tinsert(cache.fails, criteria);
			end
		end
	end

	Resolvers.auraCriteriaCache = cache;
	return cache;
end

function Resolvers.LocaleLower(value)
	value = tostring(value or "");
	local ok, lowered = pcall(strlower, value);
	if ok and type(lowered) == "string" then
		return lowered;
	end
	return string.lower(value);
end

function Resolvers.GetClientLocale()
	local ok, locale = pcall(GetLocale);
	if ok and type(locale) == "string" then
		return locale;
	end
	return "enUS";
end

function Resolvers.IsEnglishClientLocale()
	local locale = Resolvers.GetClientLocale();
	return locale == "enUS" or locale == "enGB";
end

function Resolvers.AddTextToken(tokens, value)
	if type(tokens) ~= "table" or type(value) ~= "string" or value == "" then
		return;
	end
	tokens[Resolvers.LocaleLower(value)] = true;
end

function Resolvers.GetFactionTextTokens()
	if Resolvers.factionTextTokens then
		return Resolvers.factionTextTokens;
	end
	local tokens = { Alliance = {}, Horde = {} };
	Resolvers.AddTextToken(tokens.Alliance, rawget and rawget(_G, "FACTION_ALLIANCE") or nil);
	Resolvers.AddTextToken(tokens.Alliance, rawget and rawget(_G, "ALLIANCE") or nil);
	Resolvers.AddTextToken(tokens.Horde, rawget and rawget(_G, "FACTION_HORDE") or nil);
	Resolvers.AddTextToken(tokens.Horde, rawget and rawget(_G, "HORDE") or nil);
	for _, factionID in ipairs({ 469, 730, 890 }) do
		local faction = FACTION_DATA[factionID];
		Resolvers.AddTextToken(tokens.Alliance, faction and faction.name);
	end
	for _, factionID in ipairs({ 67, 729, 889 }) do
		local faction = FACTION_DATA[factionID];
		Resolvers.AddTextToken(tokens.Horde, faction and faction.name);
	end
	Resolvers.factionTextTokens = tokens;
	return tokens;
end

function Resolvers.TextContainsAnyToken(text, tokens)
	if type(text) ~= "string" or type(tokens) ~= "table" then
		return false;
	end
	for token in pairs(tokens) do
		if token ~= "" and string.find(text, token, 1, true) then
			return true;
		end
	end
	return false;
end

function Resolvers.GetFactionFromLocalizedText(text)
	local sourceText = Resolvers.LocaleLower(text);
	local tokens = Resolvers.GetFactionTextTokens();
	local hasAlliance = Resolvers.TextContainsAnyToken(sourceText, tokens.Alliance);
	local hasHorde = Resolvers.TextContainsAnyToken(sourceText, tokens.Horde);
	if hasAlliance and not hasHorde then
		return "Alliance";
	elseif hasHorde and not hasAlliance then
		return "Horde";
	end
	return nil;
end

function Resolvers.GetFactionFromStableAssetText(text)
	local sourceText = Resolvers.LocaleLower(text);
	if string.find(sourceText, "alliance", 1, true) or string.find(sourceText, "stormpike", 1, true) or string.find(sourceText, "silverwing", 1, true) then
		return "Alliance";
	elseif string.find(sourceText, "horde", 1, true) or string.find(sourceText, "frostwolf", 1, true) or string.find(sourceText, "warsong", 1, true) then
		return "Horde";
	end
	return nil;
end

function Resolvers.ExtractTextIntegers(text)
	local numbers = {};
	if type(text) ~= "string" then
		return numbers;
	end
	for value in string.gmatch(text, "%d+") do
		numbers[#numbers + 1] = tonumber(value);
	end
	return numbers;
end

function Resolvers.ParseResourceScoreText(text, maxBases)
	local numbers = Resolvers.ExtractTextIntegers(text);
	if #numbers < 2 then
		return nil, nil;
	end
	maxBases = tonumber(maxBases) or 5;
	for index = 1, #numbers - 1 do
		local bases = numbers[index];
		if bases and bases >= 0 and bases <= maxBases then
			return bases, numbers[index + 1];
		end
	end
	return nil, nil;
end

function Resolvers.EscapeLuaPattern(text)
	return (tostring(text or ""):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"));
end

function Resolvers.FormatStringToPattern(formatString)
	if type(formatString) ~= "string" or formatString == "" then
		return nil;
	end
	local pattern = Resolvers.EscapeLuaPattern(formatString);
	pattern = string.gsub(pattern, "%%%%%d+%%%$s", ".-");
	pattern = string.gsub(pattern, "%%%%%d+%%%$d", "%%d+");
	pattern = string.gsub(pattern, "%%%%s", ".-");
	pattern = string.gsub(pattern, "%%%%d", "%%d+");
	return "^" .. pattern .. "$";
end

local criteriaTypeHandlers = Resolvers.criteriaTypeHandlers;
local criteriaTreeOperatorHandlers = Resolvers.criteriaTreeOperatorHandlers;
local questAreaQuests = Resolvers.questAreaQuests;
local questSortQuests = Resolvers.questSortQuests;
local uiMaps = Resolvers.uiMaps;
local worldMapOverlays = Resolvers.worldMapOverlays;
local spellNames = Resolvers.spellNames;
local skillLines = Resolvers.skillLines;
local factions = Resolvers.factions;
local items = Resolvers.items;
local emotes = Resolvers.emotes;

-- TBC Nagrand Slam uses type 11 quest-area criteria for AreaTable ID 3518.
-- Once questAreaQuests[3518] is populated, this counts completed quest IDs in that area.

local completedQuestLookupCache;
local worldMapOverlaysByArtID;
local exploredWorldMapOverlayCache;
local knownSpellCache;
local skillLineCache;
local factionCountCache;
local itemCountCache;
local equippedItemCache;
Resolvers.genericRidingSkillLineID = 762;
Resolvers.companionPetSkillLineID = 778;
Resolvers.dualTalentSpecializationSpellID = 63624;
Resolvers.classicRidingSkillSpells = { 824, 825, 826, 828, 10861, 10906, 10907, 18995 };
Resolvers.classicRidingSkillNames = {
	["horse riding"] = true,
	["wolf riding"] = true,
	["tiger riding"] = true,
	["ram riding"] = true,
	["raptor riding"] = true,
	["kodo riding"] = true,
	["mechanostrider piloting"] = true,
	["undead horsemanship"] = true,
};

local function ClearCompletedQuestLookup()
	completedQuestLookupCache = nil;
end

local function ClearExploredWorldMapOverlayCache()
	exploredWorldMapOverlayCache = nil;
end

local function ClearCharacterScanCache()
	knownSpellCache = nil;
	skillLineCache = nil;
	factionCountCache = nil;
	itemCountCache = nil;
	equippedItemCache = nil;
end

local function GetWorldMapOverlaysByArtID()
	if worldMapOverlaysByArtID then
		return worldMapOverlaysByArtID;
	end

	worldMapOverlaysByArtID = {};
	for overlayID, overlay in pairs(worldMapOverlays) do
		local uiMapArtID = overlay.uiMapArtID;
		if uiMapArtID and uiMapArtID ~= 0 then
			worldMapOverlaysByArtID[uiMapArtID] = worldMapOverlaysByArtID[uiMapArtID] or {};
			tinsert(worldMapOverlaysByArtID[uiMapArtID], overlay);
		end
	end

	return worldMapOverlaysByArtID;
end

local function ExploredTextureMatchesOverlay(exploredTexture, overlay)
	local hitRect = exploredTexture.hitRect;
	if not hitRect then
		return false;
	end

	return exploredTexture.textureWidth == overlay.textureWidth
		and exploredTexture.textureHeight == overlay.textureHeight
		and exploredTexture.offsetX == overlay.offsetX
		and exploredTexture.offsetY == overlay.offsetY
		and hitRect.top == overlay.hitRectTop
		and hitRect.bottom == overlay.hitRectBottom
		and hitRect.left == overlay.hitRectLeft
		and hitRect.right == overlay.hitRectRight;
end

local function BuildExploredWorldMapOverlayCache()
	local overlaysByArtID = GetWorldMapOverlaysByArtID();
	local exploredOverlays = {};
	for uiMapID in pairs(uiMaps) do
		local uiMapArtID = C_Map.GetMapArtID(uiMapID);
		local overlays = uiMapArtID and overlaysByArtID[uiMapArtID] or nil;
		if overlays then
			local exploredTextures = C_MapExplorationInfo.GetExploredMapTextures(uiMapID);
			if exploredTextures then
				for _, exploredTexture in ipairs(exploredTextures) do
					for _, overlay in ipairs(overlays) do
						if not exploredOverlays[overlay.id] and ExploredTextureMatchesOverlay(exploredTexture, overlay) then
							exploredOverlays[overlay.id] = true;
						end
					end
				end
			end
		end
	end

	return exploredOverlays;
end

local function IsWorldMapOverlayExplored(overlayID)
	if not worldMapOverlays[overlayID] then
		return nil;
	end

	if not exploredWorldMapOverlayCache then
		exploredWorldMapOverlayCache = BuildExploredWorldMapOverlayCache();
	end

	if not exploredWorldMapOverlayCache then
		return nil;
	end

	return exploredWorldMapOverlayCache[overlayID] == true;
end

local function IsKnownSpell(spellID)
	if not spellID or spellID == 0 then
		return nil;
	end

	knownSpellCache = knownSpellCache or {};
	if knownSpellCache[spellID] ~= nil then
		return knownSpellCache[spellID];
	end

	local known = IsSpellKnown(spellID, false) == true;
	if not known and IsPlayerSpell then
		known = IsPlayerSpell(spellID) == true;
	end
	if not known then
		local spellBank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or nil;
		local ok, result;
		if spellBank then
			ok, result = pcall(C_SpellBook.IsSpellKnown, spellID, spellBank);
		else
			ok, result = pcall(C_SpellBook.IsSpellKnown, spellID);
		end
		known = ok and result == true;
	end

	knownSpellCache[spellID] = known == true;
	return knownSpellCache[spellID];
end

local function BuildSkillLineCache()
	local byName = {};
	for skillLineID, skillLine in pairs(skillLines) do
		if skillLine.name and skillLine.name ~= "" then
			byName[string.lower(skillLine.name)] = skillLineID;
		end
	end

	local cache = {};
	for skillIndex = 1, GetNumSkillLines() do
		local skillName, isHeader, _, skillRank, _, skillModifier, skillMaxRank = GetSkillLineInfo(skillIndex);
		if skillName and not isHeader then
			local normalizedSkillName = string.lower(skillName);
			local skillLineID = byName[normalizedSkillName];
			if not skillLineID and Resolvers.classicRidingSkillNames[normalizedSkillName] then
				skillLineID = Resolvers.genericRidingSkillLineID;
			end
			if skillLineID then
				local rank = (skillRank or 0) + (skillModifier or 0);
				local maxRank = skillMaxRank or 0;
				local existing = cache[skillLineID];
				if existing then
					existing.rank = math.max(existing.rank or 0, rank);
					existing.maxRank = math.max(existing.maxRank or 0, maxRank);
				else
					cache[skillLineID] = {
						rank = rank,
						maxRank = maxRank,
					};
				end
			end
		end
	end

	return cache;
end

local function GetSkillLineState(skillLineID)
	if not skillLines[skillLineID] then
		return nil;
	end

	if not skillLineCache then
		skillLineCache = BuildSkillLineCache();
	end

	if not skillLineCache then
		return nil;
	end

	return skillLineCache[skillLineID] or { rank = 0, maxRank = 0 };
end

local function GetSkillLineStep(skillLineState)
	local maxRank = skillLineState and skillLineState.maxRank or 0;
	if maxRank <= 0 then
		return 0;
	end

	return math.floor(maxRank / 75);
end

local function GetFactionStateByID(factionID)
	if not factionID or factionID == 0 then
		return nil;
	end

	local name, _, standingID, barMin, barMax, barValue = GetFactionInfoByID(factionID);
	if not name then
		return nil;
	end

	return {
		name = name,
		standingID = standingID or 0,
		barMin = barMin or 0,
		barMax = barMax or 0,
		barValue = barValue or 0,
	};
end

local function RestoreCollapsedFactionHeaders(collapsedHeaders)
	for factionIndex = GetNumFactions(), 1, -1 do
		local name, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(factionIndex);
		if name and isHeader and not isCollapsed and collapsedHeaders[name] then
			CollapseFactionHeader(factionIndex);
		end
	end
end

local function BuildFactionCountCache()
	local collapsedHeaders = {};
	local factionIndex = 1;
	while factionIndex <= GetNumFactions() do
		local name, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(factionIndex);
		if name and isHeader and isCollapsed then
			collapsedHeaders[name] = true;
			ExpandFactionHeader(factionIndex);
		end
		factionIndex = factionIndex + 1;
	end

	local counts = { honored = 0, revered = 0, exalted = 0, encountered = 0 };
	for factionIndex = 1, GetNumFactions() do
		local name, _, standingID, _, _, _, _, _, isHeader, _, hasRep = GetFactionInfo(factionIndex);
		if name and (not isHeader or hasRep) and standingID and standingID > 0 then
			counts.encountered = counts.encountered + 1;
			if standingID >= 6 then
				counts.honored = counts.honored + 1;
			end
			if standingID >= 7 then
				counts.revered = counts.revered + 1;
			end
			if standingID >= 8 then
				counts.exalted = counts.exalted + 1;
			end
		end
	end

	RestoreCollapsedFactionHeaders(collapsedHeaders);
	return counts;
end

local function GetFactionCounts()
	if not factionCountCache then
		factionCountCache = BuildFactionCountCache();
	end

	return factionCountCache;
end

local function GetContainerNumSlotsCompat(bagID)
	return C_Container.GetContainerNumSlots(bagID) or 0;
end

local function GetContainerItemIDCompat(bagID, slotID)
	return C_Container.GetContainerItemID(bagID, slotID);
end

local function GetContainerItemCountCompat(bagID, slotID)
	local itemInfo, itemCount = C_Container.GetContainerItemInfo(bagID, slotID);
	if type(itemInfo) == "table" then
		return itemInfo.stackCount or itemInfo.quantity or 1;
	end
	return itemCount or 1;
end

local function CountEquippedItemID(itemID)
	local equippedCount = 0;
	for inventorySlotID = 1, 19 do
		if GetInventoryItemID("player", inventorySlotID) == itemID then
			equippedCount = equippedCount + 1;
		end
	end

	return equippedCount;
end

local function CountBagItemID(itemID)
	local bagCount = 0;
	local maxBagID = NUM_BAG_SLOTS or 4;
	for bagID = 0, maxBagID do
		for slotID = 1, GetContainerNumSlotsCompat(bagID) do
			if GetContainerItemIDCompat(bagID, slotID) == itemID then
				bagCount = bagCount + GetContainerItemCountCompat(bagID, slotID);
			end
		end
	end

	return bagCount;
end

local function GetOwnedItemCount(itemID)
	if not itemID or itemID == 0 then
		return nil;
	end

	itemCountCache = itemCountCache or {};
	if itemCountCache[itemID] ~= nil then
		return itemCountCache[itemID];
	end

	local quantity;
	local ok, result = pcall(C_Item.GetItemCount, itemID, true, false);
	if ok then
		quantity = result;
	end

	local equippedCount = CountEquippedItemID(itemID);
	if quantity == nil then
		local bagCount = CountBagItemID(itemID);
		if bagCount == nil and equippedCount == 0 then
			return nil;
		end
		quantity = (bagCount or 0) + equippedCount;
	elseif equippedCount > 0 then
		quantity = math.max(quantity, equippedCount);
	end

	itemCountCache[itemID] = quantity or 0;
	return itemCountCache[itemID];
end

function Resolvers.GetCompanionPetItemIDs()
	if Resolvers.companionPetItemIDs then
		return Resolvers.companionPetItemIDs;
	end

	Resolvers.companionPetItemIDs = {};
	for itemID, item in pairs(items) do
		if item.class == 15 and item.subclass == 2 then
			tinsert(Resolvers.companionPetItemIDs, itemID);
		end
	end

	return Resolvers.companionPetItemIDs;
end

function Resolvers.CountOwnedCompanionPetItems()
	local owned = 0;
	for _, itemID in ipairs(Resolvers.GetCompanionPetItemIDs()) do
		local itemCount = GetOwnedItemCount(itemID);
		if itemCount and itemCount > 0 then
			owned = owned + 1;
		end
	end
	return owned;
end

local function GetEquippedItemCount(itemID)
	if not itemID or itemID == 0 then
		return nil;
	end

	equippedItemCache = equippedItemCache or {};
	if equippedItemCache[itemID] ~= nil then
		return equippedItemCache[itemID];
	end

	equippedItemCache[itemID] = CountEquippedItemID(itemID);
	return equippedItemCache[itemID];
end

local function HasFlag(flags, flag)
	flags = flags or 0;
	return bit.band(flags, flag) == flag;
end

function Resolvers.HasCriteriaFlag(criteria, flag)
	return criteria and HasFlag(criteria.flags or 0, flag) or false;
end

function Resolvers.HasCriteriaTreeFlag(criteriaTree, flag)
	return criteriaTree and HasFlag(criteriaTree.flags or 0, flag) or false;
end

function Resolvers.IsClientRecordableCriteria(criteria)
	return criteria and not Resolvers.HasCriteriaFlag(criteria, CRITERIA_FLAGS.SERVER_ONLY);
end

function Resolvers.IsEventOnlyCriteriaType(criteriaType)
	return criteriaType == CRITERIA_TYPE.GET_KILLED_BY_CREATURE
		or criteriaType == CRITERIA_TYPE.WORLD_STATE_UI_VALUE_MODIFIED
		or criteriaType == CRITERIA_TYPE.KILL_PLAYER_IN_AREA
		or criteriaType == CRITERIA_TYPE.HONORABLE_KILL
		or criteriaType == CRITERIA_TYPE.EQUIP_ITEM_IN_SLOT
		or criteriaType == CRITERIA_TYPE.KILLING_BLOW_TO_CLASS
		or criteriaType == CRITERIA_TYPE.KILLING_BLOW_TO_RACE
		or criteriaType == CRITERIA_TYPE.KILLING_BLOW
		or criteriaType == CRITERIA_TYPE.KILL_PLAYER_NO_HONOR_CHECK
		or criteriaType == CRITERIA_TYPE.KILL_ANY_NPC
		or criteriaType == CRITERIA_TYPE.LAND_TARGETED_SPELL;
end

function Resolvers.UsesPerCriteriaProgress(criteria)
	return criteria and ((criteria.modifierTree and criteria.modifierTree ~= 0) or (criteria.startEvent and criteria.startEvent ~= CRITERIA_START_EVENT.NONE) or Resolvers.IsEventOnlyCriteriaType(criteria.type));
end

local function GetPlayerFaction()
	local factionGroup = UnitFactionGroup("player");
	if factionGroup == "Alliance" then
		return FACTION_ALLIANCE;
	elseif factionGroup == "Horde" then
		return FACTION_HORDE;
	end

	return nil;
end

local function CriteriaTreeAppliesToPlayer(criteriaTree)
	if not Resolvers.HasCriteriaTreeFlag(criteriaTree, CRITERIA_TREE_FLAGS.TREAT_AS_ALLIANCE) and not Resolvers.HasCriteriaTreeFlag(criteriaTree, CRITERIA_TREE_FLAGS.TREAT_AS_HORDE) then
		return true;
	end

	local playerFaction = GetPlayerFaction();
	if Resolvers.HasCriteriaTreeFlag(criteriaTree, CRITERIA_TREE_FLAGS.TREAT_AS_ALLIANCE) then
		return playerFaction == FACTION_ALLIANCE;
	end
	if Resolvers.HasCriteriaTreeFlag(criteriaTree, CRITERIA_TREE_FLAGS.TREAT_AS_HORDE) then
		return playerFaction == FACTION_HORDE;
	end

	return true;
end

function Resolvers.IsAccountWideAchievement(achievementID)
	if type(Private.IsAccountWideAchievement) == "function" then
		return Private.IsAccountWideAchievement(achievementID) == true;
	end

	local achievement = achievementID and ACHIEVEMENT_DATA[achievementID];
	local flags = achievement and achievement.flags or 0;
	local accountWideFlag = 0x20000;
	return bit.band(flags, accountWideFlag) == accountWideFlag;
end

function Resolvers.CriteriaUsesAccountProgress(criteriaOrID)
	local criteriaID = type(criteriaOrID) == "table" and criteriaOrID.id or tonumber(criteriaOrID);
	local achievementID = criteriaID and ACHIEVEMENT_BY_CRITERIA[criteriaID];
	return Resolvers.IsAccountWideAchievement(achievementID);
end

Resolvers.criteriaAssetAccountProgressCache = Resolvers.criteriaAssetAccountProgressCache or {};

function Resolvers.CriteriaAssetUsesAccountProgress(criteriaType, assetID)
	criteriaType = tonumber(criteriaType);
	assetID = tonumber(assetID) or 0;
	if not criteriaType then
		return false;
	end

	local cache = Resolvers.criteriaAssetAccountProgressCache;
	local cacheKey = tostring(criteriaType) .. ":" .. tostring(assetID);
	if cache[cacheKey] ~= nil then
		return cache[cacheKey];
	end

	local matched = false;
	local accountOnly = true;
	for _, criteria in pairs(CRITERIA_DATA) do
		if criteria.type == criteriaType and (tonumber(criteria.asset) or 0) == assetID then
			matched = true;
			if not Resolvers.CriteriaUsesAccountProgress(criteria) then
				accountOnly = false;
				break;
			end
		end
	end

	cache[cacheKey] = matched and accountOnly or false;
	return cache[cacheKey];
end

function Resolvers.GetSavedCriteriaProgress(criteriaOrID)
	local criteriaID = type(criteriaOrID) == "table" and criteriaOrID.id or tonumber(criteriaOrID);
	local useAccountProgress = Resolvers.CriteriaUsesAccountProgress(criteriaOrID);
	local ownerDB = useAccountProgress and AchievementsDB or AchievementsCharacterDB;
	ownerDB.criteria = ownerDB.criteria or {};
	if criteriaID and ownerDB.criteria[criteriaID] and Private.ValidateSavedRecord and not Private.ValidateSavedRecord(ownerDB.criteria[criteriaID], "criteria", criteriaID, useAccountProgress, "quantity", "completed") then
		ownerDB.criteria[criteriaID] = nil;
		if Private.ReportSavedIntegrityFailure then
			Private.ReportSavedIntegrityFailure("criteria progress");
		end
	end
	return ownerDB.criteria;
end

function Resolvers.GetSavedCriteriaAttempts()
	Private.state = Private.state or {};
	Private.state.criteriaAttempts = Private.state.criteriaAttempts or {};
	return Private.state.criteriaAttempts;
end

function Resolvers.GetSavedCriteriaAssetProgress(criteriaOrType, assetID)
	local useAccountProgress = false;
	local criteriaType;
	local resolvedAssetID;
	if type(criteriaOrType) == "table" then
		criteriaType = tonumber(criteriaOrType.type);
		resolvedAssetID = tonumber(criteriaOrType.asset) or 0;
		useAccountProgress = Resolvers.CriteriaUsesAccountProgress(criteriaOrType);
	else
		criteriaType = tonumber(criteriaOrType);
		resolvedAssetID = tonumber(assetID) or 0;
		useAccountProgress = Resolvers.CriteriaAssetUsesAccountProgress(criteriaOrType, assetID);
	end

	local ownerDB = useAccountProgress and AchievementsDB or AchievementsCharacterDB;
	ownerDB.criteriaAssets = ownerDB.criteriaAssets or {};
	if criteriaType and ownerDB.criteriaAssets[criteriaType] and ownerDB.criteriaAssets[criteriaType][resolvedAssetID] and Private.ValidateSavedRecord and not Private.ValidateSavedRecord(ownerDB.criteriaAssets[criteriaType][resolvedAssetID], "criteriaAsset", tostring(criteriaType) .. ":" .. tostring(resolvedAssetID), useAccountProgress, "quantity", "completed") then
		ownerDB.criteriaAssets[criteriaType][resolvedAssetID] = nil;
		if Private.ReportSavedIntegrityFailure then
			Private.ReportSavedIntegrityFailure("criteria asset progress");
		end
	end
	return ownerDB.criteriaAssets;
end

function Resolvers.ClearCriteriaAttempt(criteriaID)
	Resolvers.GetSavedCriteriaAttempts()[criteriaID] = nil;
end

function Resolvers.ResetCriteriaProgress(criteriaID)
	criteriaID = tonumber(criteriaID);
	if not criteriaID or criteriaID == 0 then
		return false;
	end

	Resolvers.GetSavedCriteriaProgress(criteriaID)[criteriaID] = nil;
	Resolvers.ClearCriteriaAttempt(criteriaID);
	return true;
end

function Resolvers.ResetAchievementCriteriaProgress(achievementID)
	local criteriaTreeIDs = achievementID and data.criteriaByAchievement[achievementID];
	if not criteriaTreeIDs then
		return false;
	end

	local reset = false;
	for _, criteriaTreeID in ipairs(criteriaTreeIDs) do
		local criteriaTree = CRITERIA_TREE_DATA[criteriaTreeID];
		local criteriaID = criteriaTree and criteriaTree.criteriaID;
		if criteriaID and criteriaID ~= 0 then
			reset = Resolvers.ResetCriteriaProgress(criteriaID) or reset;
		end
	end
	return reset;
end

local function GetRequiredQuantity(criteriaTree)
	local requiredQuantity = criteriaTree and criteriaTree.amount or 0;
	if requiredQuantity <= 0 then
		return 1;
	end

	return requiredQuantity;
end

function Resolvers.GetNow()
	return GetTime();
end

function Resolvers.CriteriaAttemptActive(criteria)
	if not criteria or not criteria.startEvent or criteria.startEvent == CRITERIA_START_EVENT.NONE then
		return true;
	end

	local attempt = Resolvers.GetSavedCriteriaAttempts()[criteria.id];
	if not attempt or attempt.active ~= true then
		return false;
	end

	if attempt.expiresAt and Resolvers.GetNow() > attempt.expiresAt then
		Resolvers.ResetCriteriaProgress(criteria.id);
		return false;
	end

	return true;
end

function Resolvers.EventAssetMatches(requiredAsset, assetID)
	requiredAsset = tonumber(requiredAsset) or 0;
	assetID = tonumber(assetID) or 0;
	return requiredAsset == 0 or requiredAsset == assetID;
end

function Resolvers.StartCriteriaAttempt(criteria)
	if not Resolvers.IsClientRecordableCriteria(criteria) then
		return false;
	end

	if Resolvers.HasCriteriaFlag(criteria, CRITERIA_FLAGS.RESET_ON_START) then
		Resolvers.ResetCriteriaProgress(criteria.id);
	end

	local now = Resolvers.GetNow();
	local startTimer = tonumber(criteria.startTimer) or 0;
	local expiresAt = startTimer > 0 and (now + startTimer) or nil;
	Resolvers.GetSavedCriteriaAttempts()[criteria.id] = {
		active = true,
		startedAt = now,
		expiresAt = expiresAt,
	};

	if expiresAt then
		local criteriaID = criteria.id;
		C_Timer.After(startTimer, function()
			local attempt = Resolvers.GetSavedCriteriaAttempts()[criteriaID];
			if attempt and attempt.expiresAt == expiresAt then
				Resolvers.ResetCriteriaProgress(criteriaID);
				if Achievements.RefreshCriteriaAchievements then
					Achievements.RefreshCriteriaAchievements(false);
				end
			end
		end);
	end

	return true;
end

function Resolvers.RecordCriteriaStart(startEvent, assetID)
	startEvent = tonumber(startEvent) or CRITERIA_START_EVENT.NONE;
	if startEvent == CRITERIA_START_EVENT.NONE then
		return false;
	end

	local recorded = false;
	for _, criteria in ipairs(Resolvers.GetCriteriaByStartEvent(startEvent)) do
		if criteria.startEvent == startEvent and Resolvers.EventAssetMatches(criteria.startAsset, assetID) then
			recorded = Resolvers.StartCriteriaAttempt(criteria) or recorded;
		end
	end
	return recorded;
end

function Resolvers.RecordCriteriaFail(failEvent, assetID)
	failEvent = tonumber(failEvent) or CRITERIA_FAIL_EVENT.NONE;
	if failEvent == CRITERIA_FAIL_EVENT.NONE then
		return false;
	end

	local recorded = false;
	for _, criteria in ipairs(Resolvers.GetRecordableCriteriaByFailEvent(failEvent)) do
		if Resolvers.IsClientRecordableCriteria(criteria)
			and criteria.failEvent == failEvent
			and Resolvers.EventAssetMatches(criteria.failAsset, assetID)
			and Resolvers.CriteriaAttemptActive(criteria)
		then
			local achievementID = data.achievementByCriteria[criteria.id];
			if achievementID and Resolvers.HasCriteriaFlag(criteria, CRITERIA_FLAGS.FAIL_ACHIEVEMENT) then
				recorded = Resolvers.ResetAchievementCriteriaProgress(achievementID) or recorded;
			else
				recorded = Resolvers.ResetCriteriaProgress(criteria.id) or recorded;
			end
		end
	end
	return recorded;
end

local function BuildResult(completed, quantity, requiredQuantity, characterName, source, eligible, statLabel)
	requiredQuantity = requiredQuantity or 1;
	quantity = quantity or 0;
	return {
		completed = completed == true,
		quantity = math.min(quantity, requiredQuantity),
		rawQuantity = quantity,
		requiredQuantity = requiredQuantity,
		characterName = characterName,
		source = source,
		eligible = eligible ~= false,
		statLabel = statLabel,
	};
end

local function GetSavedProgressRecord(criteria)
	if not criteria then
		return nil;
	end

	-- Gated criteria record progress per-criterion (RecordCriteriaEvent)
	-- so prefer the per-criterion bucket; otherwise the shared per-asset
	-- bucket from an ungated sibling would shadow real progress.
	if Resolvers.UsesPerCriteriaProgress(criteria) then
		local perCriteria = Resolvers.GetSavedCriteriaProgress(criteria)[criteria.id];
		if perCriteria then
			return perCriteria;
		end
		return nil;
	end

	local criteriaAssetProgress = Resolvers.GetSavedCriteriaAssetProgress(criteria);
	local criteriaTypeProgress = criteriaAssetProgress[criteria.type];
	if criteriaTypeProgress and criteria.asset and criteria.asset ~= 0 and criteriaTypeProgress[criteria.asset] then
		return criteriaTypeProgress[criteria.asset];
	end

	return Resolvers.GetSavedCriteriaProgress(criteria)[criteria.id];
end

local function ResolveSavedProgress(context)
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	local savedProgress = GetSavedProgressRecord(context.criteria);
	if not savedProgress then
		return BuildResult(false, 0, requiredQuantity, nil, "saved-progress");
	end

	local quantity = savedProgress.quantity or 0;
	local completed = savedProgress.completed == true or quantity >= requiredQuantity;
	if completed and quantity < requiredQuantity then
		quantity = requiredQuantity;
	end

	return BuildResult(completed, quantity, requiredQuantity, nil, "saved-progress");
end

local function GetCompletedQuestLookup()
	if completedQuestLookupCache then
		return completedQuestLookupCache;
	end

	if not GetQuestsCompleted then
		return nil;
	end

	local completedQuests = {};
	GetQuestsCompleted(completedQuests);
	completedQuestLookupCache = completedQuests;
	return completedQuestLookupCache;
end

local function IsQuestCompleted(questID, completedQuestLookup)
	if completedQuestLookup and completedQuestLookup[questID] then
		return true;
	end

	return C_QuestLog.IsQuestFlaggedCompleted(questID) == true;
end

local function CountCompletedQuestIDs(questIDs)
	if not questIDs or #questIDs == 0 then
		return nil;
	end

	local completedQuestLookup = GetCompletedQuestLookup();
	local completedCount = 0;
	for _, questID in ipairs(questIDs) do
		if IsQuestCompleted(questID, completedQuestLookup) then
			completedCount = completedCount + 1;
		end
	end

	return completedCount;
end

local function CountAllCompletedQuests()
	local completedQuestLookup = GetCompletedQuestLookup();
	if not completedQuestLookup then
		return nil;
	end

	local completedCount = 0;
	for questID in pairs(completedQuestLookup) do
		completedCount = completedCount + 1;
	end

	return completedCount;
end

local function CountCompletedQuestsInArea(areaID)
	local questIDs = questAreaQuests[areaID];
	return CountCompletedQuestIDs(questIDs);
end

local function CountCompletedQuestsInSort(questSortID)
	local questIDs = questSortQuests[questSortID];
	return CountCompletedQuestIDs(questIDs);
end

local function ResolveCompletedQuest(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end
	if Resolvers.UsesPerCriteriaProgress(criteria) then
		return ResolveSavedProgress(context);
	end

	local completed = IsQuestCompleted(criteria.asset, GetCompletedQuestLookup());
	return BuildResult(completed, completed and requiredQuantity or 0, requiredQuantity, nil, "quest-completed");
end

local function ResolvePlayerLevel(context)
	if context.achievement and Private.IsFeatOfStrengthAchievement(context.achievement) then
		return ResolveSavedProgress(context);
	end

	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	local playerLevel = Private.GetPlayerLevel and Private.GetPlayerLevel() or UnitLevel("player") or 1;
	local playerName = UnitName("player");
	return BuildResult(playerLevel >= requiredQuantity, playerLevel, requiredQuantity, playerName, "player-level");
end

local function ResolveAchievementCompleted(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 or not ACHIEVEMENT_DATA[criteria.asset] then
		return ResolveSavedProgress(context);
	end

	local completed = Private.GetAchievementState(criteria.asset) == true;
	return BuildResult(completed, completed and requiredQuantity or 0, requiredQuantity, nil, "achievement-completed");
end

local function ResolveTotalQuestsCompleted(context)
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	local completedCount = CountAllCompletedQuests();
	if not completedCount then
		return ResolveSavedProgress(context);
	end

	return BuildResult(completedCount >= requiredQuantity, completedCount, requiredQuantity, nil, "quests-completed");
end

local function ResolveDailyQuestsCompleted(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if Resolvers.UsesPerCriteriaProgress(criteria) then
		return ResolveSavedProgress(context);
	end
	if not GetDailyQuestsCompleted then
		return ResolveSavedProgress(context);
	end

	local completedCount = GetDailyQuestsCompleted() or 0;
	return BuildResult(completedCount >= requiredQuantity, completedCount, requiredQuantity, nil, "daily-quests-completed");
end

local function ResolveCompletedQuestsInArea(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local completedCount = CountCompletedQuestsInArea(criteria.asset);
	if not completedCount then
		return ResolveSavedProgress(context);
	end

	return BuildResult(completedCount >= requiredQuantity, completedCount, requiredQuantity, nil, "quests-completed-in-area");
end

local function ResolveCompletedQuestsInSort(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local completedCount = CountCompletedQuestsInSort(criteria.asset);
	if not completedCount then
		return ResolveSavedProgress(context);
	end

	return BuildResult(completedCount >= requiredQuantity, completedCount, requiredQuantity, nil, "quests-completed-in-sort");
end

local function ResolveRevealedWorldMapOverlay(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local explored = IsWorldMapOverlayExplored(criteria.asset);
	if explored == nil then
		return ResolveSavedProgress(context);
	end

	return BuildResult(explored, explored and requiredQuantity or 0, requiredQuantity, nil, "world-map-overlay-revealed");
end

local function ResolveKnownSpell(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local known = IsKnownSpell(criteria.asset);
	if known == nil then
		return ResolveSavedProgress(context);
	end

	return BuildResult(known, known and requiredQuantity or 0, requiredQuantity, nil, "spell-known");
end

local function ResolveSkillRaised(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local skillLineState = GetSkillLineState(criteria.asset);
	if not skillLineState then
		return ResolveSavedProgress(context);
	end

	return BuildResult(skillLineState.rank >= requiredQuantity, skillLineState.rank, requiredQuantity, nil, "skill-raised");
end

local function ResolveSkillStep(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local skillLineState = GetSkillLineState(criteria.asset);
	if not skillLineState then
		return ResolveSavedProgress(context);
	end

	local skillStep = GetSkillLineStep(skillLineState);
	if criteria.asset == Resolvers.genericRidingSkillLineID and skillStep < requiredQuantity then
		for index = 1, #Resolvers.classicRidingSkillSpells do
			if IsKnownSpell(Resolvers.classicRidingSkillSpells[index]) then
				skillStep = requiredQuantity;
				break;
			end
		end
	end

	return BuildResult(skillStep >= requiredQuantity, skillStep, requiredQuantity, nil, "skill-step");
end

local function ResolveSpellFromSkillLine(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local spellIDs = SKILL_LINE_ABILITY_DATA[criteria.asset];
	if not spellIDs or #spellIDs == 0 then
		return ResolveSavedProgress(context);
	end

	local known = 0;
	for index = 1, #spellIDs do
		if IsKnownSpell(spellIDs[index]) then
			known = known + 1;
		end
	end

	if criteria.asset == Resolvers.companionPetSkillLineID then
		known = math.max(known, Resolvers.CountOwnedCompanionPetItems());
	end

	return BuildResult(known >= requiredQuantity, known, requiredQuantity, nil, "spell-from-skill-line");
end

local function ResolveReachedPVPRank(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	local requiredRank = (criteria and criteria.asset) or requiredQuantity;
	if not requiredRank or requiredRank == 0 then
		return ResolveSavedProgress(context);
	end

	local function NormalizePVPRank(apiRank)
		apiRank = tonumber(apiRank) or 0;
		if apiRank > 4 then
			return apiRank - 4;
		end
		return 0;
	end

	local _, _, lifetimeRank = GetPVPLifetimeStats();
	local highestRank = NormalizePVPRank(lifetimeRank);
	if highestRank == 0 and UnitPVPRank then
		highestRank = NormalizePVPRank(UnitPVPRank("player"));
	end

	return BuildResult(highestRank >= requiredRank, highestRank, requiredRank, nil, "pvp-rank");
end

local function ResolveDeathsInArea(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local criteriaAssetProgress = Resolvers.GetSavedCriteriaAssetProgress(criteria);
	local typeProgress = criteriaAssetProgress[criteria.type];
	local record = typeProgress and typeProgress[criteria.asset];
	local quantity = (record and record.quantity) or 0;
	local completed = (record and record.completed == true) or quantity >= requiredQuantity;
	return BuildResult(completed, quantity, requiredQuantity, nil, "deaths-in-area");
end

local function ResolveAssetCounter(context, sourceLabel)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria then
		return ResolveSavedProgress(context);
	end

	local assetKey = criteria.asset or 0;
	local criteriaAssetProgress = Resolvers.GetSavedCriteriaAssetProgress(criteria);
	local typeProgress = criteriaAssetProgress[criteria.type];
	local record = typeProgress and typeProgress[assetKey];
	local quantity = (record and record.quantity) or 0;
	local completed = (record and record.completed == true) or quantity >= requiredQuantity;
	return BuildResult(completed, quantity, requiredQuantity, nil, sourceLabel);
end

local function ResolveDieAnywhere(context)
	return ResolveAssetCounter(context, "die-anywhere");
end

local function ResolveDieInInstanceWithMaxPlayers(context)
	return ResolveAssetCounter(context, "die-in-instance-max-players");
end

local function ResolveParticipateInBattleground(context)
	return ResolveAssetCounter(context, "participate-in-battleground");
end

local function ResolveReputationGained(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local factionState = GetFactionStateByID(criteria.asset);
	if not factionState then
		return ResolveSavedProgress(context);
	end

	local quantity = factionState.barValue or 0;
	if requiredQuantity <= 8 then
		quantity = factionState.standingID or 0;
	elseif requiredQuantity >= 42000 and (factionState.standingID or 0) >= 8 then
		quantity = math.max(quantity, requiredQuantity);
	end

	return BuildResult(quantity >= requiredQuantity, quantity, requiredQuantity, nil, "reputation-gained");
end

local function ResolveFactionCount(context, countKey, source)
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	local factionCounts = GetFactionCounts();
	if not factionCounts then
		return ResolveSavedProgress(context);
	end

	local quantity = factionCounts[countKey] or 0;
	return BuildResult(quantity >= requiredQuantity, quantity, requiredQuantity, nil, source);
end

local function ResolveTotalExaltedFactions(context)
	return ResolveFactionCount(context, "exalted", "total-exalted-factions");
end

local function ResolveTotalReveredFactions(context)
	return ResolveFactionCount(context, "revered", "total-revered-factions");
end

local function ResolveTotalHonoredFactions(context)
	return ResolveFactionCount(context, "honored", "total-honored-factions");
end

local function ResolveTotalFactionsEncountered(context)
	return ResolveFactionCount(context, "encountered", "total-factions-encountered");
end

local function ApplySavedProgressQuantity(context, quantity, requiredQuantity)
	local savedProgress = GetSavedProgressRecord(context.criteria);
	if not savedProgress then
		return quantity;
	end

	if savedProgress.completed == true then
		return math.max(quantity or 0, requiredQuantity or 1);
	end

	return math.max(quantity or 0, savedProgress.quantity or 0);
end

local function ResolveOwnedItemCount(context, source)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local quantity = GetOwnedItemCount(criteria.asset);
	if quantity == nil then
		return ResolveSavedProgress(context);
	end

	quantity = ApplySavedProgressQuantity(context, quantity, requiredQuantity);
	return BuildResult(quantity >= requiredQuantity, quantity, requiredQuantity, nil, source);
end

local function ResolveAcquireItem(context)
	return ResolveOwnedItemCount(context, "item-owned");
end

local function ResolveLootItem(context)
	return ResolveOwnedItemCount(context, "item-looted-owned");
end

local function ResolveEquipItem(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local quantity = GetEquippedItemCount(criteria.asset);
	if quantity == nil then
		return ResolveSavedProgress(context);
	end

	quantity = ApplySavedProgressQuantity(context, quantity, requiredQuantity);
	return BuildResult(quantity >= requiredQuantity, quantity, requiredQuantity, nil, "item-equipped");
end

-- Type 49 EQUIP_ITEM_IN_SLOT: criteria.asset is Blizzard's zero-based
-- equipment slot ID (0=head, 1=neck, ...), while Classic inventory APIs use
-- one-based inventory slots (1=head, 2=neck, ...). Modifier
-- trees gate on the equipped item's quality (cond 14) / item level (cond 3).
-- We evaluate the slot's current item against the criterion's modifier tree
-- live so the criterion flips on as soon as the player is wearing a qualifying
-- item, and PLAYER_EQUIPMENT_CHANGED additionally records a discrete event
-- through RecordEquippedItemSlot (so per-criterion saved progress sticks).
local function CriteriaSlotToInventorySlot(criteriaSlot)
	criteriaSlot = tonumber(criteriaSlot);
	return criteriaSlot and (criteriaSlot + 1) or nil;
end

local function InventorySlotToCriteriaSlot(inventorySlot)
	inventorySlot = tonumber(inventorySlot);
	return inventorySlot and (inventorySlot - 1) or nil;
end

local function BuildInventorySlotItemContext(inventorySlot, criteriaSlot)
	if inventorySlot == nil then return nil, "invalid-slot"; end
	local link = GetInventoryItemLink("player", inventorySlot);
	if not link then return nil, "empty-slot"; end
	local itemID = type(link) == "string" and tonumber(string.match(link, "item:(%d+)")) or nil;
	local _, _, quality, ilvl = GetItemInfo(link);
	local itemRecord = itemID and ITEM_DATA[itemID];
	return {
		slot = criteriaSlot,
		inventorySlot = inventorySlot,
		itemID = itemID,
		itemQuality = quality or (itemRecord and itemRecord.quality),
		itemLevel = ilvl,
	};
end

local function BuildSlotItemContext(criteriaSlot)
	return BuildInventorySlotItemContext(CriteriaSlotToInventorySlot(criteriaSlot), tonumber(criteriaSlot) or 0);
end

local function IsAchievementSavedComplete(achievementID)
	if not achievementID or not Private.GetSavedCompletions then
		return false;
	end
	local savedState = Private.GetSavedCompletions(achievementID)[achievementID];
	if Private.IsSavedCompletionComplete then
		return Private.IsSavedCompletionComplete(savedState) == true;
	end
	return tonumber(savedState and savedState.ts) ~= nil;
end

local function ResolveEquipItemInSlot(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or criteria.asset == nil then
		return ResolveSavedProgress(context);
	end

	local ctx, reason = BuildSlotItemContext(criteria.asset);
	if ctx and (criteria.modifierTree == 0 or EvaluateCriteriaModifier(criteria, ctx)) then
		return BuildResult(true, requiredQuantity, requiredQuantity, nil, "slot-equipped");
	end
	if reason == "api-unavailable" then
		return ResolveSavedProgress(context);
	end
	if not IsAchievementSavedComplete(context.achievementID) then
		Resolvers.ResetCriteriaProgress(criteria.id);
	end

	return BuildResult(false, 0, requiredQuantity, nil, "slot-equipped");
end

function Resolvers.HasEquipItemCriteriaAsset(itemID)
	itemID = tonumber(itemID);
	if not itemID then
		return false;
	end
	if not Resolvers.equipItemCriteriaAssets then
		local assets = {};
		for _, criteria in pairs(CRITERIA_DATA) do
			if criteria.type == CRITERIA_TYPE.EQUIP_ITEM and criteria.asset and criteria.asset ~= 0 and Resolvers.IsClientRecordableCriteria(criteria) then
				assets[criteria.asset] = true;
			end
		end
		Resolvers.equipItemCriteriaAssets = assets;
	end
	return Resolvers.equipItemCriteriaAssets[itemID] == true;
end

function Resolvers.RecordEquippedItemSlot(slot)
	if slot == nil then
		local recorded = false;
		-- Sweep all standard inventory slots (head=1..tabard=19).
		for s = 1, 19 do
			recorded = Resolvers.RecordEquippedItemSlot(s) or recorded;
		end
		return recorded;
	end
	local criteriaSlot = InventorySlotToCriteriaSlot(slot);
	local ctx = BuildInventorySlotItemContext(slot, criteriaSlot);
	if not ctx then return false; end
	local recorded = false;
	if ctx.itemID and Resolvers.SetCriteriaAssetProgressMax and Resolvers.HasEquipItemCriteriaAsset(ctx.itemID) then
		recorded = Resolvers.SetCriteriaAssetProgressMax(CRITERIA_TYPE.EQUIP_ITEM, ctx.itemID, 1) or recorded;
	end
	if RecordCriteriaEvent then
		recorded = RecordCriteriaEvent(CRITERIA_TYPE.EQUIP_ITEM_IN_SLOT, criteriaSlot, ctx) or recorded;
	end
	return recorded;
end

-- Type 30 WORLD_STATE_UI_VALUE_MODIFIED: criteria.asset is the world-state UI
-- id; criteria.value (or asset secondary) carries the threshold. Most rows are
-- ungated and live in Wintergrasp/instance content that does not exist on
-- Classic Era, so this helper degrades to a no-op when the underlying API is
-- absent. We iterate the active world-state UI table and dispatch each entry
-- as a discrete event with ctx.worldStateValue populated.
function Resolvers.GetWorldStateScanMapID(ctx)
	if type(ctx) == "table" and ctx.mapID then
		return Resolvers.ResolveWorldStateMapID(ctx.mapID);
	end
	local ok, _, _, _, _, _, _, _, instanceMapID = pcall(GetInstanceInfo);
	local mapID = ok and Resolvers.ResolveWorldStateMapID(instanceMapID) or nil;
	if mapID then
		return mapID;
	end
	ok, instanceMapID = pcall(C_Map.GetBestMapForUnit, "player");
	mapID = ok and Resolvers.ResolveWorldStateMapID(instanceMapID) or nil;
	if mapID then
		return mapID;
	end
	local mapUtil = rawget and rawget(_G, "MapUtil") or nil;
	if type(mapUtil) == "table" and type(mapUtil.GetDisplayableMapForPlayer) == "function" then
		local ok, uiMapID = pcall(mapUtil.GetDisplayableMapForPlayer);
		local mapID = ok and Resolvers.ResolveWorldStateMapID(uiMapID) or nil;
		if mapID then
			return mapID;
		end
	end
	local mapID = Resolvers.GetActiveBattlefieldMapID and Resolvers.GetActiveBattlefieldMapID() or nil;
	if mapID then
		return mapID;
	end
	mapID = Resolvers.GetZoneWorldStateMapID and Resolvers.GetZoneWorldStateMapID() or nil;
	if mapID then
		return mapID;
	end
	return nil;
end

function Resolvers.GetWorldStateMapCache(ctx, cacheName)
	local mapID = Resolvers.GetWorldStateScanMapID(ctx);
	if not mapID or not Private.state then
		return nil;
	end
	local byMap = Private.state[cacheName];
	return type(byMap) == "table" and byMap[mapID] or nil;
end

function Resolvers.PrepareWorldStateScanCache(mapID)
	Private.state = Private.state or {};
	Private.state.worldStateValues = {};
	Private.state.worldStateValuesByMap = Private.state.worldStateValuesByMap or {};
	Private.state.worldStateExpressionsByMap = Private.state.worldStateExpressionsByMap or {};
	Private.state.uiWidgetWorldStateTexts = {};
	Private.state.areaPoiWorldStateInfos = {};
	local values = Private.state.worldStateValues;
	local expressions = {};
	if mapID then
		Private.state.worldStateValuesByMap[mapID] = values;
		Private.state.worldStateExpressionsByMap[mapID] = expressions;
	end
	return values, expressions;
end

function Resolvers.GetWorldStateTextFaction(text, icon, tooltip)
	local localizedSource = tostring(text or "") .. " " .. tostring(tooltip or "");
	local faction = Resolvers.GetFactionFromLocalizedText(localizedSource);
	if faction then
		return faction;
	end
	faction = Resolvers.GetFactionFromStableAssetText(tostring(icon or "") .. " " .. tostring(tooltip or ""));
	if faction then
		return faction;
	end
	if Resolvers.IsEnglishClientLocale() then
		return Resolvers.GetFactionFromStableAssetText(localizedSource);
	end
	return nil;
end

function Resolvers.GetArathiScoreState(mapID)
	if mapID ~= 529 then
		return nil;
	end
	Private.state = Private.state or {};
	Private.state.arathiScoreStatesByMap = Private.state.arathiScoreStatesByMap or {};
	Private.state.arathiScoreStatesByMap[mapID] = Private.state.arathiScoreStatesByMap[mapID] or {};
	return Private.state.arathiScoreStatesByMap[mapID];
end

function Resolvers.ResetArathiScoreState(scoreState)
	if type(scoreState) ~= "table" then
		return;
	end
	scoreState.alliancePoints = nil;
	scoreState.hordePoints = nil;
	scoreState.allianceBases = nil;
	scoreState.hordeBases = nil;
	scoreState.allianceHad500Deficit = nil;
	scoreState.hordeHad500Deficit = nil;
	scoreState.allianceComebackWon = nil;
	scoreState.hordeComebackWon = nil;
end

function Resolvers.ApplyArathiScoreHistory(mapID, expressions, values)
	local scoreState = Resolvers.GetArathiScoreState(mapID);
	if not scoreState then
		return;
	end
	local alliancePoints = tonumber(scoreState.alliancePoints);
	local hordePoints = tonumber(scoreState.hordePoints);
	if not alliancePoints or not hordePoints then
		return;
	end
	if scoreState.lastAlliancePoints and scoreState.lastHordePoints and (alliancePoints < scoreState.lastAlliancePoints or hordePoints < scoreState.lastHordePoints) then
		Resolvers.ResetArathiScoreState(scoreState);
		scoreState.alliancePoints = alliancePoints;
		scoreState.hordePoints = hordePoints;
	end
	if hordePoints - alliancePoints >= 500 then
		scoreState.allianceHad500Deficit = true;
	elseif alliancePoints - hordePoints >= 500 then
		scoreState.hordeHad500Deficit = true;
	end
	if alliancePoints >= 1600 and scoreState.allianceHad500Deficit then
		scoreState.allianceComebackWon = true;
		expressions[5809] = true;
		values[3645] = 1;
	elseif hordePoints >= 1600 and scoreState.hordeHad500Deficit then
		scoreState.hordeComebackWon = true;
		expressions[5810] = true;
		values[3644] = 1;
	end
	if scoreState.allianceComebackWon then
		expressions[5809] = true;
		values[3645] = 1;
	end
	if scoreState.hordeComebackWon then
		expressions[5810] = true;
		values[3644] = 1;
	end
	scoreState.lastAlliancePoints = alliancePoints;
	scoreState.lastHordePoints = hordePoints;
end

function Resolvers.RecordArathiScoreText(text, icon, tooltip, expressions, values)
	local bases, points = Resolvers.ParseResourceScoreText(text, 5);
	if not bases and not points then
		return;
	end
	local faction = Resolvers.GetWorldStateTextFaction(text, icon, tooltip);
	local scoreState = Resolvers.GetArathiScoreState(529);
	if faction == "Alliance" then
		if bases then
			values[1779] = bases;
			if scoreState then scoreState.allianceBases = bases; end
		end
		if points then
			values[1776] = points;
			if scoreState then scoreState.alliancePoints = points; end
		end
	elseif faction == "Horde" then
		if bases then
			values[1778] = bases;
			if scoreState then scoreState.hordeBases = bases; end
		end
		if points then
			values[1777] = points;
			if scoreState then scoreState.hordePoints = points; end
		end
	end
	if bases == 5 then expressions[5717] = true; end
	if points == 1590 then expressions[5715] = true; end
	if points == 0 then expressions[5716] = true; end
	Resolvers.ApplyArathiScoreHistory(529, expressions, values);
end

function Resolvers.RecordEyeOfTheStormScoreText(text, icon, tooltip, expressions, values)
	local bases, points = Resolvers.ParseResourceScoreText(text, 4);
	local faction = Resolvers.GetWorldStateTextFaction(text, icon, tooltip);
	if faction == "Alliance" then
		if bases then values[2752] = bases; end
		if points then values[2749] = points; end
	elseif faction == "Horde" then
		if bases then values[2753] = bases; end
		if points then values[2750] = points; end
	end
	if bases == 4 then expressions[5719] = true; end
	if points == 0 then expressions[5720] = true; end
end

function Resolvers.RecordWarsongScoreText(text, icon, tooltip, values)
	if type(text) ~= "string" then
		return;
	end
	local captures = tonumber(string.match(text, "^(%d+)%s*/%s*3$")) or tonumber(string.match(text, "(%d+)%s*/%s*3"));
	if captures == nil then
		return;
	end
	local faction = Resolvers.GetWorldStateTextFaction(text, icon, tooltip);
	if faction == "Alliance" then
		values[1582] = captures;
	elseif faction == "Horde" then
		values[1581] = captures;
	end
end

function Resolvers.RecordKnownWorldStateText(text, mapID, expressions, values, icon, tooltip)
	if type(text) ~= "string" or text == "" then
		return;
	end
	if Private.state and Private.state.uiWidgetWorldStateTexts then
		local texts = Private.state.uiWidgetWorldStateTexts;
		if #texts < 30 then
			texts[#texts + 1] = text;
		end
	end
	if mapID == 566 then
		Resolvers.RecordEyeOfTheStormScoreText(text, icon, tooltip, expressions, values);
	elseif mapID == 529 then
		Resolvers.RecordArathiScoreText(text, icon, tooltip, expressions, values);
	elseif mapID == 489 then
		local faction = Resolvers.GetWorldStateTextFaction(text, icon, tooltip);
		local numbers = Resolvers.ExtractTextIntegers(text);
		if faction == "Horde" and numbers[1] then values[1581] = numbers[1]; end
		if faction == "Alliance" and numbers[1] then values[1582] = numbers[1]; end
		Resolvers.RecordWarsongScoreText(text, icon, tooltip, values);
	end
end

function Resolvers.RecordWorldStateInfoStrings(info, mapID, expressions, values, depth)
	if type(info) ~= "table" then
		return;
	end
	depth = (depth or 0) + 1;
	if depth > 3 then
		return;
	end
	local icon = info.icon or info.iconTexture or info.atlasName or info.texture or info.textureKit;
	local tooltip = info.tooltip or info.tooltipText or info.name or info.description;
	for _, value in pairs(info) do
		if type(value) == "string" then
			Resolvers.RecordKnownWorldStateText(value, mapID, expressions, values, icon, tooltip);
		elseif type(value) == "table" then
			Resolvers.RecordWorldStateInfoStrings(value, mapID, expressions, values, depth);
		end
	end
end

Resolvers.uiWidgetVisualizationGetters = Resolvers.uiWidgetVisualizationGetters or {
	"GetIconAndTextWidgetVisualizationInfo",
	"GetCaptureBarWidgetVisualizationInfo",
	"GetStatusBarWidgetVisualizationInfo",
	"GetDoubleStatusBarWidgetVisualizationInfo",
	"GetIconTextAndBackgroundWidgetVisualizationInfo",
	"GetDoubleIconAndTextWidgetVisualizationInfo",
	"GetStackedResourceTrackerWidgetVisualizationInfo",
	"GetIconTextAndCurrenciesWidgetVisualizationInfo",
	"GetTextWithStateWidgetVisualizationInfo",
	"GetHorizontalCurrenciesWidgetVisualizationInfo",
	"GetBulletTextListWidgetVisualizationInfo",
	"GetScenarioHeaderCurrenciesAndBackgroundWidgetVisualizationInfo",
	"GetTextureWithStateVisualizationInfo",
};

function Resolvers.RecordUIWidgetWorldStateScan(mapID, expressions, values)
	local widgetManager = rawget and rawget(_G, "C_UIWidgetManager") or nil;
	if type(widgetManager) ~= "table" or type(widgetManager.GetAllWidgetsBySetID) ~= "function" then
		return;
	end
	local setIDs = {};
	local seen = {};
	local function addSetID(setID)
		setID = tonumber(setID);
		if setID and setID > 0 and not seen[setID] then
			seen[setID] = true;
			setIDs[#setIDs + 1] = setID;
		end
	end
	if type(widgetManager.GetTopCenterWidgetSetID) == "function" then
		local ok, setID = pcall(widgetManager.GetTopCenterWidgetSetID);
		if ok then addSetID(setID); end
	end
	if type(widgetManager.GetBelowMinimapWidgetSetID) == "function" then
		local ok, setID = pcall(widgetManager.GetBelowMinimapWidgetSetID);
		if ok then addSetID(setID); end
	end
	for _, setID in ipairs(setIDs) do
		local ok, widgets = pcall(widgetManager.GetAllWidgetsBySetID, setID);
		if ok and type(widgets) == "table" then
			for _, widgetInfo in ipairs(widgets) do
				local widgetID = type(widgetInfo) == "table" and widgetInfo.widgetID;
				if widgetID then
					for _, getterName in ipairs(Resolvers.uiWidgetVisualizationGetters) do
						local getter = widgetManager[getterName];
						if type(getter) == "function" then
							local infoOK, visualizationInfo = pcall(getter, widgetID);
							if infoOK and type(visualizationInfo) == "table" then
								Resolvers.RecordWorldStateInfoStrings(visualizationInfo, mapID, expressions, values);
							end
						end
					end
				end
			end
		end
	end
end

Resolvers.worldStateInstanceToUiMapID = Resolvers.worldStateInstanceToUiMapID or {
	[30] = 1459,
	[489] = 1460,
	[529] = 1461,
	[566] = 1956,
};

Resolvers.worldStateUiMapToInstanceID = Resolvers.worldStateUiMapToInstanceID or {
	[1459] = 30,
	[1460] = 489,
	[1461] = 529,
	[1956] = 566,
};

Resolvers.worldStateZoneNameToInstanceID = Resolvers.worldStateZoneNameToInstanceID or {
	["alterac valley"] = 30,
	["warsong gulch"] = 489,
	["arathi basin"] = 529,
	["eye of the storm"] = 566,
};

function Resolvers.GetWorldStateZoneNameLookup()
	if Resolvers.worldStateZoneNameLookup then
		return Resolvers.worldStateZoneNameLookup;
	end
	local lookup = {};
	for instanceMapID, uiMapID in pairs(Resolvers.worldStateInstanceToUiMapID or {}) do
		local uiMap = UI_MAP_DATA[uiMapID];
		if uiMap and uiMap.name then
			lookup[Resolvers.LocaleLower(uiMap.name)] = instanceMapID;
		end
	end
	if Resolvers.IsEnglishClientLocale() then
		for zoneName, instanceMapID in pairs(Resolvers.worldStateZoneNameToInstanceID or {}) do
			lookup[zoneName] = instanceMapID;
		end
	end
	Resolvers.worldStateZoneNameLookup = lookup;
	return lookup;
end

function Resolvers.ResolveWorldStateMapID(mapID)
	mapID = tonumber(mapID);
	if not mapID or mapID == 0 then
		return nil;
	end
	if Resolvers.worldStateInstanceToUiMapID and Resolvers.worldStateInstanceToUiMapID[mapID] then
		return mapID;
	end
	if Resolvers.worldStateUiMapToInstanceID and Resolvers.worldStateUiMapToInstanceID[mapID] then
		return Resolvers.worldStateUiMapToInstanceID[mapID];
	end
	return nil;
end

function Resolvers.GetWorldStateMapIDFromName(name)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	local lookup = Resolvers.GetWorldStateZoneNameLookup();
	return lookup and lookup[Resolvers.LocaleLower(name)] or nil;
end

function Resolvers.GetActiveBattlefieldMapID()
	local maxGetter = rawget and rawget(_G, "GetMaxBattlefieldID") or nil;
	local statusGetter = rawget and rawget(_G, "GetBattlefieldStatus") or nil;
	if type(maxGetter) ~= "function" or type(statusGetter) ~= "function" then
		return nil;
	end
	local maxOK, maxBattlefields = pcall(maxGetter);
	if not maxOK or type(maxBattlefields) ~= "number" then
		return nil;
	end
	for battlefieldIndex = 1, maxBattlefields do
		local ok, status, mapName, instanceID = pcall(statusGetter, battlefieldIndex);
		if ok and status == "active" then
			local mapID = Resolvers.ResolveWorldStateMapID(instanceID) or Resolvers.GetWorldStateMapIDFromName(mapName);
			if mapID then
				return mapID;
			end
		end
	end
	return nil;
end

function Resolvers.GetZoneWorldStateMapID()
	local getters = { rawget and rawget(_G, "GetRealZoneText") or nil, rawget and rawget(_G, "GetZoneText") or nil };
	for _, getter in ipairs(getters) do
		if type(getter) == "function" then
			local ok, zoneName = pcall(getter);
			local mapID = ok and Resolvers.GetWorldStateMapIDFromName(zoneName) or nil;
			if mapID then
				return mapID;
			end
		end
	end
	return nil;
end

Resolvers.areaPoiAllianceFactionIDs = Resolvers.areaPoiAllianceFactionIDs or {
	[469] = true,
	[730] = true,
	[890] = true,
};

Resolvers.areaPoiHordeFactionIDs = Resolvers.areaPoiHordeFactionIDs or {
	[67] = true,
	[729] = true,
	[889] = true,
};

Resolvers.battlegroundAreaPoiNodes = Resolvers.battlegroundAreaPoiNodes or {
	[529] = {
		{ key = "farm", patterns = { "farm" } },
		{ key = "blacksmith", patterns = { "blacksmith" } },
		{ key = "lumberMill", patterns = { "lumber mill" } },
		{ key = "goldMine", patterns = { "gold mine" } },
		{ key = "stables", patterns = { "stables" } },
	},
	[566] = {
		{ key = "mageTower", patterns = { "mage tower" } },
		{ key = "draeneiRuins", patterns = { "draenei ruins" } },
		{ key = "felReaverRuins", patterns = { "fel reaver ruins" } },
		{ key = "bloodElfTower", patterns = { "blood elf tower" } },
	},
	[30] = {
		{ key = "irondeep", patterns = { "irondeep" } },
		{ key = "coldtooth", patterns = { "coldtooth" } },
	},
};

function Resolvers.GetWorldStateScanUiMapID(ctx)
	if type(ctx) == "table" and ctx.uiMapID then
		return tonumber(ctx.uiMapID);
	end
	local mapID = Resolvers.GetWorldStateScanMapID(ctx);
	local mapAPI = rawget and rawget(_G, "C_Map") or nil;
	if type(mapAPI) == "table" and type(mapAPI.GetBestMapForUnit) == "function" then
		local ok, uiMapID = pcall(mapAPI.GetBestMapForUnit, "player");
		uiMapID = ok and tonumber(uiMapID) or nil;
		if uiMapID and uiMapID ~= 0 and Resolvers.worldStateUiMapToInstanceID and Resolvers.worldStateUiMapToInstanceID[uiMapID] then
			return uiMapID;
		elseif uiMapID and Resolvers.worldStateInstanceToUiMapID and Resolvers.worldStateInstanceToUiMapID[uiMapID] then
			return Resolvers.worldStateInstanceToUiMapID[uiMapID];
		end
	end
	return (mapID and Resolvers.worldStateInstanceToUiMapID and Resolvers.worldStateInstanceToUiMapID[mapID]) or mapID;
end

function Resolvers.GetAreaPoiText(poiInfo)
	if type(poiInfo) ~= "table" then
		return "";
	end
	return Resolvers.LocaleLower(tostring(poiInfo.name or "") .. " " .. tostring(poiInfo.description or "") .. " " .. tostring(poiInfo.atlasName or ""));
end

function Resolvers.GetAreaPoiLocalizedText(poiInfo)
	if type(poiInfo) ~= "table" then
		return "";
	end
	return Resolvers.LocaleLower(tostring(poiInfo.name or "") .. " " .. tostring(poiInfo.description or ""));
end

function Resolvers.GetAreaPoiStableText(poiInfo)
	if type(poiInfo) ~= "table" then
		return "";
	end
	return Resolvers.LocaleLower(tostring(poiInfo.atlasName or "") .. " " .. tostring(poiInfo.textureKit or "") .. " " .. tostring(poiInfo.icon or ""));
end

function Resolvers.GetAreaPoiOwner(poiInfo)
	if type(poiInfo) ~= "table" then
		return nil;
	end
	local factionID = tonumber(poiInfo.factionID);
	if factionID and Resolvers.areaPoiAllianceFactionIDs and Resolvers.areaPoiAllianceFactionIDs[factionID] then
		return "Alliance";
	elseif factionID and Resolvers.areaPoiHordeFactionIDs and Resolvers.areaPoiHordeFactionIDs[factionID] then
		return "Horde";
	end
	local faction = Resolvers.GetFactionFromStableAssetText(Resolvers.GetAreaPoiStableText(poiInfo)) or Resolvers.GetFactionFromLocalizedText(Resolvers.GetAreaPoiLocalizedText(poiInfo));
	if faction then
		return faction;
	end
	local text = Resolvers.IsEnglishClientLocale() and Resolvers.GetAreaPoiText(poiInfo) or "";
	if text ~= "" and (string.find(text, "alliance controlled", 1, true) or string.find(text, "controlled by alliance", 1, true)) then
		return "Alliance";
	elseif text ~= "" and (string.find(text, "horde controlled", 1, true) or string.find(text, "controlled by horde", 1, true)) then
		return "Horde";
	end
	local hasAlliance = text ~= "" and string.find(text, "alliance", 1, true) ~= nil;
	local hasHorde = text ~= "" and string.find(text, "horde", 1, true) ~= nil;
	if hasAlliance and not hasHorde then
		return "Alliance";
	elseif hasHorde and not hasAlliance then
		return "Horde";
	end
	return nil;
end

function Resolvers.IsAreaPoiContested(poiInfo)
	if type(poiInfo) == "table" and (poiInfo.isContested == true or poiInfo.isUnderAttack == true or poiInfo.isNeutral == true) then
		return true;
	end
	local text = Resolvers.GetAreaPoiStableText(poiInfo);
	if Resolvers.IsEnglishClientLocale() then
		text = text .. " " .. Resolvers.GetAreaPoiText(poiInfo);
	end
	return string.find(text, "conflict", 1, true) ~= nil
		or string.find(text, "contested", 1, true) ~= nil
		or string.find(text, "assault", 1, true) ~= nil
		or string.find(text, "neutral", 1, true) ~= nil;
end

function Resolvers.GetAreaPoiNodeKey(mapID, poiInfo)
	local nodes = Resolvers.battlegroundAreaPoiNodes and Resolvers.battlegroundAreaPoiNodes[mapID];
	if type(nodes) ~= "table" then
		return nil;
	end
	local text = Resolvers.GetAreaPoiStableText(poiInfo);
	if Resolvers.IsEnglishClientLocale() then
		text = text .. " " .. Resolvers.GetAreaPoiText(poiInfo);
	end
	for _, node in ipairs(nodes) do
		for _, pattern in ipairs(node.patterns) do
			if string.find(text, pattern, 1, true) then
				return node.key;
			end
		end
	end
	return nil;
end

function Resolvers.RecordAreaPoiDebugInfo(mapID, uiMapID, areaPoiID, poiInfo, owner, contested)
	if not Private.state or type(Private.state.areaPoiWorldStateInfos) ~= "table" or type(poiInfo) ~= "table" then
		return;
	end
	local infos = Private.state.areaPoiWorldStateInfos;
	if #infos >= 40 then
		return;
	end
	infos[#infos + 1] = {
		areaPoiID = areaPoiID,
		mapID = mapID,
		uiMapID = uiMapID,
		name = poiInfo.name,
		description = poiInfo.description,
		atlasName = poiInfo.atlasName,
		factionID = poiInfo.factionID,
		owner = owner,
		contested = contested == true,
	};
end

function Resolvers.ApplyAreaPoiNodeOwners(mapID, nodeOwners, expressions, values)
	if type(nodeOwners) ~= "table" then
		return;
	end
	local allianceCount = 0;
	local hordeCount = 0;
	for _, owner in pairs(nodeOwners) do
		if owner == "Alliance" then
			allianceCount = allianceCount + 1;
		elseif owner == "Horde" then
			hordeCount = hordeCount + 1;
		end
	end
	if mapID == 529 then
		if allianceCount == 5 or hordeCount == 5 then
			expressions[5717] = true;
		end
		if allianceCount == 5 then values[1779] = 5; end
		if hordeCount == 5 then values[1778] = 5; end
	elseif mapID == 566 then
		if allianceCount == 4 or hordeCount == 4 then
			expressions[5719] = true;
		end
		if allianceCount == 4 then values[2752] = 4; end
		if hordeCount == 4 then values[2753] = 4; end
	elseif mapID == 30 then
		if nodeOwners.irondeep == "Alliance" and nodeOwners.coldtooth == "Alliance" then
			expressions[1043] = true;
			expressions[1057] = true;
			values[801] = 2;
			values[804] = 2;
		elseif nodeOwners.irondeep == "Horde" and nodeOwners.coldtooth == "Horde" then
			expressions[1041] = true;
			expressions[1058] = true;
			values[801] = 1;
			values[804] = 1;
		end
	end
end

function Resolvers.RecordBattlefieldAreaPoiScan(mapID, expressions, values)
	local areaPoi = rawget and rawget(_G, "C_AreaPoiInfo") or nil;
	if type(areaPoi) ~= "table" or type(areaPoi.GetAreaPOIForMap) ~= "function" or type(areaPoi.GetAreaPOIInfo) ~= "function" then
		return;
	end
	local uiMapID = Resolvers.GetWorldStateScanUiMapID({ mapID = mapID });
	if not uiMapID then
		return;
	end
	mapID = Resolvers.ResolveWorldStateMapID(mapID) or Resolvers.ResolveWorldStateMapID(uiMapID);
	if not mapID then
		return;
	end
	if Private.state then
		Private.state.lastWorldStateScanMapID = mapID;
	end
	local ok, areaPoiIDs = pcall(areaPoi.GetAreaPOIForMap, uiMapID);
	if not ok or type(areaPoiIDs) ~= "table" then
		return;
	end
	local nodeOwners = {};
	for _, areaPoiID in ipairs(areaPoiIDs) do
		local infoOK, poiInfo = pcall(areaPoi.GetAreaPOIInfo, uiMapID, areaPoiID);
		if infoOK and type(poiInfo) == "table" then
			local owner = Resolvers.GetAreaPoiOwner(poiInfo);
			local contested = Resolvers.IsAreaPoiContested(poiInfo);
			Resolvers.RecordAreaPoiDebugInfo(mapID, uiMapID, areaPoiID, poiInfo, owner, contested);
			Resolvers.RecordWorldStateInfoStrings(poiInfo, mapID, expressions, values);
			local nodeKey = owner and not contested and Resolvers.GetAreaPoiNodeKey(mapID, poiInfo) or nil;
			if nodeKey and nodeOwners[nodeKey] == nil then
				nodeOwners[nodeKey] = owner;
			elseif nodeKey and nodeOwners[nodeKey] ~= owner then
				nodeOwners[nodeKey] = false;
			end
		end
	end
	Resolvers.ApplyAreaPoiNodeOwners(mapID, nodeOwners, expressions, values);
	return mapID;
end

function Resolvers.NormalizeWorldStateUIInfo(state, third, fourth, fifth, sixth, seventh)
	if type(third) == "string" then
		return state, third, fourth, sixth;
	end
	return state, fourth, fifth, seventh;
end

function Resolvers.GetBattlegroundMessageState(mapID)
	if not mapID then
		return nil;
	end
	Private.state = Private.state or {};
	Private.state.battlegroundMessageStatesByMap = Private.state.battlegroundMessageStatesByMap or {};
	local byMap = Private.state.battlegroundMessageStatesByMap;
	byMap[mapID] = byMap[mapID] or {};
	return byMap[mapID];
end

function Resolvers.GlobalNameMatchesAnyToken(globalName, tokens)
	if type(globalName) ~= "string" or type(tokens) ~= "table" then
		return false;
	end
	local upperName = string.upper(globalName);
	for _, token in ipairs(tokens) do
		if string.find(upperName, token, 1, true) then
			return true;
		end
	end
	return false;
end

function Resolvers.GetBattlegroundFlagMessagePatterns(action)
	Resolvers.battlegroundFlagMessagePatterns = Resolvers.battlegroundFlagMessagePatterns or {};
	if Resolvers.battlegroundFlagMessagePatterns[action] then
		return Resolvers.battlegroundFlagMessagePatterns[action];
	end
	local actionTokens = {
		captured = { "CAPTURE" },
		pickedUp = { "PICK", "TAKEN" },
		returned = { "RETURN" },
		dropped = { "DROP" },
	};
	local patterns = {};
	for globalName, globalValue in pairs(_G) do
		if type(globalName) == "string" and type(globalValue) == "string" then
			local upperName = string.upper(globalName);
			if string.find(upperName, "FLAG", 1, true) and Resolvers.GlobalNameMatchesAnyToken(upperName, actionTokens[action]) then
				local pattern = Resolvers.FormatStringToPattern(globalValue);
				if pattern then
					patterns[#patterns + 1] = pattern;
				end
			end
		end
	end
	Resolvers.battlegroundFlagMessagePatterns[action] = patterns;
	return patterns;
end

function Resolvers.MessageMatchesBattlegroundFlagAction(message, action)
	for _, pattern in ipairs(Resolvers.GetBattlegroundFlagMessagePatterns(action)) do
		if string.match(message, pattern) then
			return true;
		end
	end
	return false;
end

function Resolvers.ApplyBattlegroundMessageState(mapID, expressions, values)
	if mapID ~= 489 or not Private.state or type(Private.state.battlegroundMessageStatesByMap) ~= "table" then
		return;
	end
	local state = Private.state.battlegroundMessageStatesByMap[mapID];
	if type(state) ~= "table" then
		return;
	end
	if values[1581] == nil and state.hordeCaptures ~= nil then
		values[1581] = state.hordeCaptures;
	end
	if values[1582] == nil and state.allianceCaptures ~= nil then
		values[1582] = state.allianceCaptures;
	end
end

function Resolvers.IsWarsongFlagAtBase(ctx, flagFaction)
	local mapID = Resolvers.GetWorldStateScanMapID(ctx);
	if mapID ~= 489 or not Private.state or type(Private.state.battlegroundMessageStatesByMap) ~= "table" then
		return nil;
	end
	local state = Private.state.battlegroundMessageStatesByMap[mapID];
	if type(state) ~= "table" then
		return nil;
	end
	if flagFaction == "Alliance" and state.allianceFlagAtBase ~= nil then
		return state.allianceFlagAtBase == true;
	elseif flagFaction == "Horde" and state.hordeFlagAtBase ~= nil then
		return state.hordeFlagAtBase == true;
	end
	return nil;
end

function Resolvers.RecordBattlegroundWorldStateMessage(message)
	if type(message) ~= "string" or message == "" then
		return false;
	end
	local mapID = Resolvers.GetWorldStateScanMapID();
	if mapID ~= 489 then
		return false;
	end
	local state = Resolvers.GetBattlegroundMessageState(mapID);
	if not state then
		return false;
	end
	local flagFaction = Resolvers.GetFactionFromLocalizedText(message) or (Resolvers.IsEnglishClientLocale() and Resolvers.GetFactionFromStableAssetText(message) or nil);
	if not flagFaction then
		return false;
	end

	state.lastMessage = message;
	if Resolvers.MessageMatchesBattlegroundFlagAction(message, "captured") then
		if flagFaction == "Alliance" then
			state.hordeCaptures = (tonumber(state.hordeCaptures) or 0) + 1;
		else
			state.allianceCaptures = (tonumber(state.allianceCaptures) or 0) + 1;
		end
		state.allianceFlagCarrier = nil;
		state.hordeFlagCarrier = nil;
		state.allianceFlagAtBase = true;
		state.hordeFlagAtBase = true;
	elseif Resolvers.MessageMatchesBattlegroundFlagAction(message, "pickedUp") then
		if flagFaction == "Alliance" then
			state.allianceFlagCarrier = true;
			state.allianceFlagAtBase = false;
		else
			state.hordeFlagCarrier = true;
			state.hordeFlagAtBase = false;
		end
	elseif Resolvers.MessageMatchesBattlegroundFlagAction(message, "returned") then
		if flagFaction == "Alliance" then
			state.allianceFlagCarrier = nil;
			state.allianceFlagAtBase = true;
		else
			state.hordeFlagCarrier = nil;
			state.hordeFlagAtBase = true;
		end
	elseif Resolvers.MessageMatchesBattlegroundFlagAction(message, "dropped") then
		if flagFaction == "Alliance" then
			state.allianceFlagCarrier = nil;
			state.allianceFlagAtBase = false;
		else
			state.hordeFlagCarrier = nil;
			state.hordeFlagAtBase = false;
		end
	else
		return false;
	end
	return true;
end

function Resolvers.RecordBattlefieldFlagPositionScan(mapID)
	if mapID ~= 489 then
		return;
	end
	local countGetter = rawget and rawget(_G, "GetNumBattlefieldFlagPositions") or nil;
	local positionGetter = rawget and rawget(_G, "GetBattlefieldFlagPosition") or nil;
	if type(countGetter) ~= "function" or type(positionGetter) ~= "function" then
		return;
	end
	local ok, count = pcall(countGetter);
	if not ok or type(count) ~= "number" or count <= 0 then
		return;
	end
	local state = Resolvers.GetBattlegroundMessageState(mapID);
	if not state then
		return;
	end
	state.flagPositions = {};
	state.allianceFlagPosition = nil;
	state.hordeFlagPosition = nil;
	for flagIndex = 1, count do
		local positionOK, x, y, texture = pcall(positionGetter, flagIndex);
		if positionOK and x and y then
			local position = { x = tonumber(x), y = tonumber(y), texture = texture };
			state.flagPositions[#state.flagPositions + 1] = position;
			local textureText = string.lower(tostring(texture or ""));
			if string.find(textureText, "alliance", 1, true) then
				state.allianceFlagPosition = position;
				state.allianceFlagAtBase = false;
			elseif string.find(textureText, "horde", 1, true) then
				state.hordeFlagPosition = position;
				state.hordeFlagAtBase = false;
			end
		end
	end
	if state.allianceFlagPosition == nil and state.allianceFlagAtBase ~= false then
		state.allianceFlagAtBase = true;
	end
	if state.hordeFlagPosition == nil and state.hordeFlagAtBase ~= false then
		state.hordeFlagAtBase = true;
	end
end

function Resolvers.FinalizeWorldStateScanCache(mapID, expressions, values)
	Resolvers.ApplyBattlegroundMessageState(mapID, expressions, values);
	Resolvers.ApplyArathiScoreHistory(mapID, expressions, values);
	if mapID == 489 and values[1581] ~= nil and values[1582] ~= nil then
		local difference = math.abs((tonumber(values[1581]) or 0) - (tonumber(values[1582]) or 0));
		if difference == 3 then
			expressions[5718] = true;
		end
	end
end

function Resolvers.RecordWorldStateScan()
	local mapID = Resolvers.GetWorldStateScanMapID();
	if mapID and Private.state then
		Private.state.lastWorldStateScanMapID = mapID;
	end
	local values, expressions = Resolvers.PrepareWorldStateScanCache(mapID);
	if type(GetNumWorldStateUI) == "function" and type(GetWorldStateUIInfo) == "function" then
		local count = GetNumWorldStateUI();
		if count and count > 0 then
			for i = 1, count do
				local _, state, third, fourth, fifth, sixth, seventh = GetWorldStateUIInfo(i);
				local text, icon, tooltip;
				state, text, icon, tooltip = Resolvers.NormalizeWorldStateUIInfo(state, third, fourth, fifth, sixth, seventh);
				Resolvers.RecordKnownWorldStateText(text, mapID, expressions, values, icon, tooltip);
				-- The world-state id is not exposed by the classic API; we fall back
				-- to (i) as the asset key, which still allows criteria authored with
				-- iteration-based assets to fire. Numeric value comes from `state`.
				local value = tonumber(state) or tonumber(text);
				if value then
					values[i] = value;
					if RecordCriteriaEvent then
						RecordCriteriaEvent(CRITERIA_TYPE.WORLD_STATE_UI_VALUE_MODIFIED, i, { worldStateValue = value, mapID = mapID });
					end
				end
			end
		end
	end
	Resolvers.RecordUIWidgetWorldStateScan(mapID, expressions, values);
	mapID = Resolvers.RecordBattlefieldAreaPoiScan(mapID, expressions, values) or mapID;
	Resolvers.RecordBattlefieldFlagPositionScan(mapID);
	Resolvers.FinalizeWorldStateScanCache(mapID, expressions, values);
end
local recentUsedItems = {};
local itemUseRefreshPending = false;

local function GetItemUseCriteriaItems()
	if itemUseCriteriaItems then
		return itemUseCriteriaItems;
	end

	itemUseCriteriaItems = {};
	for _, criteria in pairs(CRITERIA_DATA) do
		if Resolvers.IsClientRecordableCriteria(criteria) and criteria.type == CRITERIA_TYPE.USE_ITEM and criteria.asset and criteria.asset ~= 0 then
			itemUseCriteriaItems[criteria.asset] = true;
		end
	end

	return itemUseCriteriaItems;
end

local function ExtractItemIDFromLink(itemLink)
	if type(itemLink) ~= "string" then
		return nil;
	end

	return tonumber(string.match(itemLink, "item:(%d+)"));
end

local function ExtractItemIDFromItemInfo(itemInfo)
	if type(itemInfo) == "number" then
		return itemInfo;
	end
	if type(itemInfo) ~= "string" then
		return nil;
	end

	local numericItemID = tonumber(itemInfo);
	if numericItemID then
		return numericItemID;
	end

	local linkedItemID = ExtractItemIDFromLink(itemInfo);
	if linkedItemID then
		return linkedItemID;
	end

	local ok, itemID = pcall(C_Item.GetItemInfoInstant, itemInfo);
	if ok and itemID then
		return itemID;
	end
	ok, itemID = pcall(GetItemInfoInstant, itemInfo);
	if ok and itemID then
		return itemID;
	end

	local itemLink;
	local linkOK, result = pcall(function()
		return select(2, C_Item.GetItemInfo(itemInfo));
	end);
	if linkOK then
		itemLink = result;
	end
	if not itemLink then
		linkOK, result = pcall(function()
			return select(2, GetItemInfo(itemInfo));
		end);
		if linkOK then
			itemLink = result;
		end
	end

	return ExtractItemIDFromLink(itemLink);
end

local function GetProgressCharacterName()
	return UnitName("player");
end

local function ScheduleItemUseCriteriaRefresh()
	if itemUseRefreshPending then
		return;
	end

	itemUseRefreshPending = true;
	local refresh = function()
		itemUseRefreshPending = false;
		if Achievements.RefreshCriteriaAchievements then
			Achievements.RefreshCriteriaAchievements(true);
		end
	end;

	C_Timer.After(0, refresh);
end

local function RecordUsedItemID(itemID)
	itemID = tonumber(itemID);
	if not itemID or itemID == 0 or not GetItemUseCriteriaItems()[itemID] then
		return false;
	end

	local now = GetTime();
	if recentUsedItems[itemID] and now and now - recentUsedItems[itemID] < 0.2 then
		return false;
	end
	recentUsedItems[itemID] = now or 0;

	Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.USE_ITEM, itemID);
	Resolvers.IncrementCriteriaAssetProgress(CRITERIA_TYPE.USE_ITEM, itemID, 1, nil, GetProgressCharacterName());
	RecordCriteriaEvent(CRITERIA_TYPE.USE_ITEM, itemID, { itemID = itemID }, "use-item-" .. tostring(itemID));
	ScheduleItemUseCriteriaRefresh();
	return true;
end

-- Wago/Blizzard environmental damage subtype -> Criteria asset mapping for type 26.
local ENVIRONMENTAL_TYPE_TO_ASSET = {
	Drowning = 0,
	Falling = 1,
	Fatigue = 2,
	Fire = 3,
	Lava = 4,
	Slime = 5,
};
local lastEnvironmentalDamageType = nil;
local lastEnvironmentalDamageAt = 0;
local ENVIRONMENTAL_DAMAGE_DEATH_WINDOW = 5; -- seconds

function Resolvers.PlayerIsDruidCatForm()
	local _, classFile = UnitClass("player");
	return classFile == "DRUID" and Resolvers.PlayerHasAuraSpell(768) == true;
end

function Resolvers.RecordSurvivedFallDamage(damageAmount)
	damageAmount = tonumber(damageAmount) or 0;
	if damageAmount <= 0 or not UnitHealthMax then
		return false;
	end

	local maxHealth = tonumber(UnitHealthMax("player")) or 0;
	if maxHealth <= 0 then
		return false;
	end

	local requiredDamage = maxHealth * 0.95;
	if Resolvers.PlayerIsDruidCatForm() then
		requiredDamage = requiredDamage * 0.83;
	end
	if damageAmount < requiredDamage then
		return false;
	end

	Private.state = Private.state or {};
	local now = Resolvers.GetNow();
	if Private.state.lastSurvivedFallDamageAt and (now - Private.state.lastSurvivedFallDamageAt) < 2 then
		return false;
	end
	Private.state.lastSurvivedFallDamageAt = now;

	local recordIfAlive = function()
		if UnitIsDeadOrGhost("player") then
			return;
		end

		local recorded = false;
		for _, criteria in pairs(CRITERIA_DATA) do
			if criteria.type == CRITERIA_TYPE.MAX_DISTANCE_FALLEN_WITHOUT_DYING
				and Resolvers.IsClientRecordableCriteria(criteria)
				and Resolvers.CriteriaAttemptActive(criteria)
				and EvaluateCriteriaModifier(criteria, { fallDamage = damageAmount, maxHealth = maxHealth })
			then
				recorded = Resolvers.SetCriteriaProgress(criteria.id, 1, true, GetProgressCharacterName()) or recorded;
			end
		end
		if recorded then
			Resolvers.ScheduleCriteriaTypesRefresh(CRITERIA_TYPE.MAX_DISTANCE_FALLEN_WITHOUT_DYING, true, 0.15, "fall-damage");
		end
	end;

	C_Timer.After(0.2, recordIfAlive);
	return true;
end

local function RecordPlayerDeath()
	local characterName = GetProgressCharacterName();
	Private.state = Private.state or {};
	local recentPlayerDamage = Private.state.lastPlayerDamagePlayer;
	local recentPlayerDamageValid = recentPlayerDamage and (Resolvers.GetNow() - (recentPlayerDamage.at or 0)) <= 10;
	local deathContext = {};
	deathContext.targetIsEnemy = false;
	local arenaContext = Resolvers.GetActiveArenaContext and Resolvers.GetActiveArenaContext() or nil;
	if arenaContext then
		for key, value in pairs(arenaContext) do
			deathContext[key] = value;
		end
	end
	if recentPlayerDamageValid then
		deathContext.targetIsPlayer = true;
		deathContext.targetIsEnemy = recentPlayerDamage.sourceIsEnemy == true;
		deathContext.sourceGUID = recentPlayerDamage.sourceGUID;
		deathContext.sourceFlags = recentPlayerDamage.sourceFlags;
		deathContext.destGUID = recentPlayerDamage.destGUID;
		deathContext.destFlags = recentPlayerDamage.destFlags;
	end

	Resolvers.RecordCriteriaFail(CRITERIA_FAIL_EVENT.DEATH, 0);
	if Resolvers.RecordSoulOfIronNaxxRaidDeath then
		Resolvers.RecordSoulOfIronNaxxRaidDeath();
	end

	-- Type 17 DIE_ANYWHERE: global counter regardless of zone.
	Resolvers.IncrementCriteriaAssetProgress(CRITERIA_TYPE.DIE_ANYWHERE, 0, 1, nil, characterName);
	RecordCriteriaEvent(CRITERIA_TYPE.DIE_ANYWHERE, 0, deathContext, "death-anywhere");
	Resolvers.RecordPlayerKilledByCreature();
	if recentPlayerDamageValid then
		Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.DIE_TO_PLAYER, 0, 1, deathContext, "death-player");
	end
	Private.state.lastPlayerDamagePlayer = nil;

	-- Type 26 DIE_TO_ENVIRONMENTAL_DAMAGE: only count if the player was hit by environmental
	-- damage in the recent past (the same fall/lava/etc. that triggered this death).
	if lastEnvironmentalDamageType then
		local now = GetTime();
		if now - lastEnvironmentalDamageAt <= ENVIRONMENTAL_DAMAGE_DEATH_WINDOW then
			local assetID = ENVIRONMENTAL_TYPE_TO_ASSET[lastEnvironmentalDamageType];
			if assetID then
				Resolvers.IncrementCriteriaAssetProgress(CRITERIA_TYPE.DIE_TO_ENVIRONMENTAL_DAMAGE, assetID, 1, nil, characterName);
				RecordCriteriaEvent(CRITERIA_TYPE.DIE_TO_ENVIRONMENTAL_DAMAGE, assetID, {}, "death-environmental-" .. tostring(assetID));
			end
		end
		lastEnvironmentalDamageType = nil;
		lastEnvironmentalDamageAt = 0;
	end

	local _, instanceType, _, _, maxPlayers, _, _, instanceMapID = GetInstanceInfo();
	instanceMapID = tonumber(instanceMapID);
	maxPlayers = tonumber(maxPlayers);

	if instanceMapID and instanceMapID ~= 0 then
		Resolvers.IncrementCriteriaAssetProgress(CRITERIA_TYPE.DIE_ON_MAP, instanceMapID, 1, nil, characterName);
		RecordCriteriaEvent(CRITERIA_TYPE.DIE_ON_MAP, instanceMapID, { mapID = instanceMapID, zoneAreaID = instanceMapID }, "death-map-" .. tostring(instanceMapID));
		Resolvers.RecordCriteriaFail(CRITERIA_FAIL_EVENT.DEATH, instanceMapID);
	end

	-- Type 18 DIE_IN_INSTANCE_WITH_MAX_PLAYERS: only count inside party/raid instances.
	if maxPlayers and maxPlayers > 0 and (instanceType == "party" or instanceType == "raid") then
		Resolvers.IncrementCriteriaAssetProgress(CRITERIA_TYPE.DIE_IN_INSTANCE_WITH_MAX_PLAYERS, maxPlayers, 1, nil, characterName);
		RecordCriteriaEvent(CRITERIA_TYPE.DIE_IN_INSTANCE_WITH_MAX_PLAYERS, maxPlayers, { mapID = instanceMapID, zoneAreaID = instanceMapID }, "death-instance-" .. tostring(maxPlayers));
	end

	ScheduleItemUseCriteriaRefresh();
	return true;
end

local lastBattlegroundMapID = nil;
local recentBattlegroundWinMapID = nil;

local function RecordBattlegroundWin()
	local _, instanceType, _, _, _, _, _, instanceMapID = GetInstanceInfo();
	instanceMapID = tonumber(instanceMapID);
	if instanceType ~= "pvp" or not instanceMapID or instanceMapID == 0 then
		return false;
	end

	local winner = GetBattlefieldWinner();
	if winner == nil then
		return false;
	end

	local playerFactionGroup = UnitFactionGroup("player");
	-- GetBattlefieldWinner: 0 = Horde, 1 = Alliance.
	local winnerFactionGroup;
	if winner == 0 then
		winnerFactionGroup = "Horde";
	elseif winner == 1 then
		winnerFactionGroup = "Alliance";
	end

	if not winnerFactionGroup or winnerFactionGroup ~= playerFactionGroup then
		return false;
	end

	if recentBattlegroundWinMapID == instanceMapID then
		return false;
	end
	recentBattlegroundWinMapID = instanceMapID;

	Resolvers.IncrementCriteriaAssetProgress(CRITERIA_TYPE.WIN_BATTLEGROUND, instanceMapID, 1, nil, GetProgressCharacterName());
	RecordCriteriaEvent(CRITERIA_TYPE.WIN_BATTLEGROUND, instanceMapID, {
		mapID = instanceMapID,
		zoneAreaID = instanceMapID,
		sourceRaceID = GetPlayerRaceID(),
	}, "win-bg-" .. tostring(instanceMapID));
	ScheduleItemUseCriteriaRefresh();
	return true;
end

-- Build Lua match patterns from Blizzard's localized duel-result format strings.
-- The retreat string names the loser first in some clients, and newer clients
-- can use positional tokens (`%1$s`/`%2$s`), so keep capture roles with the pattern.
local function BuildDuelOutcomePattern(globalString, defaultRoles)
	if type(globalString) ~= "string" or globalString == "" then
		return nil;
	end
	local function EscapeLuaPatternText(text)
		return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"));
	end

	local parts = {};
	local roles = {};
	local cursor = 1;
	local sequentialIndex = 1;
	while cursor <= #globalString do
		local positionalStart, positionalEnd, position = globalString:find("%%(%d+)%$s", cursor);
		local simpleStart, simpleEnd = globalString:find("%%s", cursor);
		local tokenStart, tokenEnd, role;
		if positionalStart and (not simpleStart or positionalStart < simpleStart) then
			tokenStart = positionalStart;
			tokenEnd = positionalEnd;
			position = tonumber(position);
			role = position == 1 and "winner" or position == 2 and "loser" or defaultRoles[sequentialIndex];
		elseif simpleStart then
			tokenStart = simpleStart;
			tokenEnd = simpleEnd;
			role = defaultRoles[sequentialIndex];
		else
			parts[#parts + 1] = EscapeLuaPatternText(globalString:sub(cursor));
			break;
		end

		parts[#parts + 1] = EscapeLuaPatternText(globalString:sub(cursor, tokenStart - 1));
		parts[#parts + 1] = "(.+)";
		roles[#roles + 1] = role;
		cursor = tokenEnd + 1;
		sequentialIndex = sequentialIndex + 1;
	end

	if #roles < 2 then
		return nil;
	end

	return {
		pattern = "^" .. table.concat(parts) .. "$",
		roles = roles,
	};
end

local duelOutcomePatterns = nil;
local function GetDuelOutcomePatterns()
	if duelOutcomePatterns then
		return duelOutcomePatterns;
	end
	duelOutcomePatterns = {};
	local sources = {
		{ text = _G.DUEL_WINNER_KNOCKOUT or _G.ERR_DUEL_WINNER_KNOCKOUT_S or "%s has defeated %s in a duel", roles = { "winner", "loser" } },
		{ text = _G.DUEL_WINNER_RETREAT or _G.ERR_DUEL_WINNER_RETREAT_S or "%s has fled from %s in a duel", roles = { "loser", "winner" } },
	};
	for _, source in ipairs(sources) do
		local outcomePattern = BuildDuelOutcomePattern(source.text, source.roles);
		if outcomePattern then
			tinsert(duelOutcomePatterns, outcomePattern);
		end
	end
	return duelOutcomePatterns;
end

local function RecordDuelOutcomeFromSystemMessage(message)
	if type(message) ~= "string" or message == "" then
		return false;
	end
	local function NormalizeDuelName(name)
		if type(name) ~= "string" then
			return nil;
		end
		name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "");
		name = name:match("^%s*(.-)%s*$");
		name = Ambiguate(name, "none");
		name = name:match("^([^%-]+)") or name;
		return name;
	end

	local playerName = NormalizeDuelName(UnitName("player"));
	if not playerName or playerName == "" then
		return false;
	end

	for _, outcomePattern in ipairs(GetDuelOutcomePatterns()) do
		local captures = { message:match(outcomePattern.pattern) };
		if captures[1] and captures[2] then
			local winner, loser;
			for index, role in ipairs(outcomePattern.roles) do
				if role == "winner" then
					winner = NormalizeDuelName(captures[index]);
				elseif role == "loser" then
					loser = NormalizeDuelName(captures[index]);
				end
			end

			local criteriaType;
			if winner == playerName then
				criteriaType = CRITERIA_TYPE.WIN_DUEL;
			elseif loser == playerName then
				criteriaType = CRITERIA_TYPE.LOSE_DUEL;
			end
			if criteriaType then
				Resolvers.IncrementCriteriaAssetProgress(criteriaType, 0, 1, nil, GetProgressCharacterName());
				RecordCriteriaEvent(criteriaType, 0, {}, "duel-" .. tostring(criteriaType));
				ScheduleItemUseCriteriaRefresh();
				if Achievements.RefreshCriteriaAchievements then
					Achievements.RefreshCriteriaAchievements(true);
				end
				return true;
			end
			return false;
		end
	end
	return false;
end

local function RecordBattlegroundParticipation()
	local _, instanceType, _, _, _, _, _, instanceMapID = GetInstanceInfo();
	instanceMapID = tonumber(instanceMapID);

	if instanceType ~= "pvp" or not instanceMapID or instanceMapID == 0 then
		if lastBattlegroundMapID then
			Resolvers.RecordCriteriaFail(CRITERIA_FAIL_EVENT.LEAVE_BATTLEGROUND, lastBattlegroundMapID);
		end
		lastBattlegroundMapID = nil;
		return false;
	end

	if lastBattlegroundMapID == instanceMapID then
		return false;
	end
	lastBattlegroundMapID = instanceMapID;

	Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.START_BATTLEGROUND, instanceMapID);
	Resolvers.IncrementCriteriaAssetProgress(CRITERIA_TYPE.PARTICIPATE_IN_BATTLEGROUND, instanceMapID, 1, nil, GetProgressCharacterName());
	RecordCriteriaEvent(CRITERIA_TYPE.PARTICIPATE_IN_BATTLEGROUND, instanceMapID, {
		mapID = instanceMapID,
		zoneAreaID = instanceMapID,
		sourceRaceID = GetPlayerRaceID(),
	}, "participate-bg-" .. tostring(instanceMapID));
	ScheduleItemUseCriteriaRefresh();
	return true;
end

function Resolvers.GetActiveArenaContext()
	local _, instanceType, _, _, _, _, _, instanceMapID = GetInstanceInfo();
	instanceMapID = tonumber(instanceMapID);
	local activeArena = instanceType == "arena";
	if not activeArena then
		local _, isArena = IsActiveBattlefieldArena();
		activeArena = isArena == true;
	end
	if not activeArena or not instanceMapID or instanceMapID == 0 then
		return nil;
	end

	local teamSize;
	local registeredMatch;
	for i = 1, GetMaxBattlefieldID() do
		local status, _, _, _, _, statusTeamSize, statusRegisteredMatch = GetBattlefieldStatus(i);
		if status == "active" then
			teamSize = tonumber(statusTeamSize) or teamSize;
			registeredMatch = statusRegisteredMatch == true or registeredMatch;
		end
	end

	return {
		mapID = instanceMapID,
		zoneAreaID = instanceMapID,
		arenaTeamSize = teamSize,
		rated = registeredMatch,
		sourceRaceID = GetPlayerRaceID and GetPlayerRaceID() or nil,
		arenaRating = teamSize and Resolvers.GetArenaRating(teamSize, true) or nil,
	};
end

function Resolvers.GetPlayerBattlefieldFaction()
	local playerName = UnitName("player");
	if not playerName or playerName == "" then
		return nil;
	end

	for i = 1, GetNumBattlefieldScores() do
		local name, _, _, _, _, _, faction = GetBattlefieldScore(i);
		if type(name) == "string" then
			local shortName = string.match(name, "^[^-]+") or name;
			if shortName == playerName then
				return tonumber(faction);
			end
		end
	end
	return nil;
end

function Resolvers.PlayerIsOnlyLivingArenaScore()
	local playerName = UnitName("player");
	if not playerName or playerName == "" then
		return false;
	end

	local aliveCount = 0;
	local playerAlive = false;
	local sawPlayer = false;
	for i = 1, GetNumBattlefieldScores() do
		local name, _, _, deaths = GetBattlefieldScore(i);
		if type(name) == "string" and name ~= "" then
			local shortName = string.match(name, "^[^-]+") or name;
			local deathCount = tonumber(deaths);
			if deathCount == nil then
				return false;
			end
			if deathCount == 0 then
				aliveCount = aliveCount + 1;
				if shortName == playerName then
					playerAlive = true;
				end
			end
			if shortName == playerName then
				sawPlayer = true;
			end
		end
	end

	return sawPlayer and playerAlive and aliveCount == 1;
end

function Resolvers.RecordLastManStanding(ctx)
	if type(ctx) ~= "table" or ctx.rated ~= true or tonumber(ctx.arenaTeamSize) ~= 5 then
		return false;
	end
	if Resolvers.PlayerIsOnlyLivingArenaScore() ~= true then
		return false;
	end
	return Achievements.markAchievementComplete and Achievements.markAchievementComplete(409, true) == true;
end

function Resolvers.RecordArenaParticipation()
	local ctx = Resolvers.GetActiveArenaContext();
	Private.state = Private.state or {};
	if not ctx then
		Private.state.lastArenaMapID = nil;
		return false;
	end

	if Private.state.lastArenaMapID == ctx.mapID then
		return false;
	end
	Private.state.lastArenaMapID = ctx.mapID;

	local recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.PARTICIPATE_IN_ARENA, ctx.mapID, 1, ctx, "participate-arena-" .. tostring(ctx.mapID));
	if recorded then
		ScheduleItemUseCriteriaRefresh();
	end
	return recorded;
end

function Resolvers.RecordArenaWin()
	local ctx = Resolvers.GetActiveArenaContext();
	if not ctx then
		return false;
	end

	local winner = GetBattlefieldWinner();
	if winner == nil then
		return false;
	end

	local playerFaction = Resolvers.GetPlayerBattlefieldFaction();
	if playerFaction == nil then
		return false;
	end

	if tonumber(winner) ~= playerFaction then
		if ctx.rated then
			Resolvers.RecordCriteriaFail(CRITERIA_FAIL_EVENT.LOSE_RANKED_ARENA_MATCH, 0);
		end
		return false;
	end

	local recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.WIN_ARENA, ctx.mapID, 1, ctx, "win-arena-" .. tostring(ctx.mapID));
	if ctx.rated then
		Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.WIN_RANKED_ARENA_MATCH, 0);
		recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.WIN_RANKED_ARENA_MATCH, 0, 1, ctx, "win-ranked-arena") or recorded;
		recorded = Resolvers.RecordLastManStanding(ctx) or recorded;
	end
	if recorded then
		ScheduleItemUseCriteriaRefresh();
	end
	return recorded;
end

function Resolvers.RecordQuestAccepted(questID)
	questID = tonumber(questID);
	if not questID or questID == 0 then
		return false;
	end

	local recorded = Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.ACCEPT_QUEST, questID);
	if recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(false);
	end
	return recorded;
end

function Resolvers.RecordQuestTurnedIn(questID, moneyReward)
	questID = tonumber(questID);
	if not questID or questID == 0 then
		return false;
	end

	local recorded = false;
	moneyReward = tonumber(moneyReward) or 0;
	local questContext = {
		questID = questID,
		moneyReward = moneyReward,
		mapID = GetCurrentMapID(),
		zoneAreaID = GetCurrentZoneAreaID and GetCurrentZoneAreaID() or nil,
		sourceRaceID = GetPlayerRaceID and GetPlayerRaceID() or nil,
		sourceFaction = Resolvers.GetPlayerFactionName and Resolvers.GetPlayerFactionName() or nil,
	};
	recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.COMPLETE_QUEST, questID, 1, questContext, "quest-complete-" .. tostring(questID)) or recorded;
	if moneyReward > 0 then
		recorded = Resolvers.RecordMoneyCriteria(CRITERIA_TYPE.MONEY_EARNED_FROM_QUESTING, moneyReward, "quest-money-" .. tostring(questID)) or recorded;
	end

	local quest = data.quests[questID];
	if not quest or quest.daily ~= true then
		return recorded;
	end

	recorded = Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.COMPLETE_DAILY_QUEST, questID) or recorded;
	AchievementsCharacterDB = AchievementsCharacterDB or {};
	local today = date("%Y-%m-%d");
	recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.DAILY_QUESTS_COMPLETED, 0, 1, questContext, "daily-quest-" .. tostring(questID) .. ":" .. today) or recorded;
	if AchievementsCharacterDB.dailyQuestStreakLastDay ~= today then
		AchievementsCharacterDB.dailyQuestStreakLastDay = today;
		recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.COMPLETE_ANY_DAILY_QUEST_PER_DAY, 0, 1, {}, "daily-streak-" .. today) or recorded;
	end
	if recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(false);
	end
	return recorded;
end

function Resolvers.RecordDailyQuestResetCheck()
	if not GetDailyQuestsCompleted then
		return false;
	end

	local currentCount = tonumber(GetDailyQuestsCompleted()) or 0;
	AchievementsCharacterDB = AchievementsCharacterDB or {};
	AchievementsCharacterDB.dailyQuestsCompletedLastSeen = AchievementsCharacterDB.dailyQuestsCompletedLastSeen or currentCount;
	local previousCount = AchievementsCharacterDB.dailyQuestsCompletedLastSeen or 0;
	AchievementsCharacterDB.dailyQuestsCompletedLastSeen = currentCount;

	if previousCount > 0 and currentCount == 0 then
		return Resolvers.RecordCriteriaFail(CRITERIA_FAIL_EVENT.DAILY_QUESTS_CLEARED, 0)
			or Resolvers.RecordCriteriaFail(CRITERIA_FAIL_EVENT.DAILY_QUEST_STREAK_EXPIRED, 0);
	end

	return false;
end

function Resolvers.PlayerHasAuraSpell(spellID)
	spellID = tonumber(spellID) or 0;
	if spellID == 0 or not UnitAura then
		return nil;
	end

	for filterIndex = 1, 2 do
		local filter = filterIndex == 1 and "HELPFUL" or "HARMFUL";
		for auraIndex = 1, 40 do
			local name, _, _, _, _, _, _, _, _, auraSpellID = UnitAura("player", auraIndex, filter);
			if not name then
				break;
			end
			if auraSpellID == spellID then
				return true;
			end
		end
	end

	return false;
end

function Resolvers.GetNumPlayerTalentGroups()
	local ok, count = pcall(GetNumTalentGroups, false, false);
	if ok and tonumber(count) then
		return tonumber(count);
	end
	ok, count = pcall(GetNumTalentGroups);
	if ok and tonumber(count) then
		return tonumber(count);
	end

	ok, count = pcall(GetNumSpecGroups, false);
	if ok and tonumber(count) then
		return tonumber(count);
	end
	ok, count = pcall(GetNumSpecGroups);
	if ok and tonumber(count) then
		return tonumber(count);
	end

	return nil;
end

function Resolvers.GetActivePlayerTalentGroup()
	local ok, group = pcall(C_SpecializationInfo.GetActiveSpecGroup, false, false);
	if ok and tonumber(group) then
		return tonumber(group);
	end
	ok, group = pcall(C_SpecializationInfo.GetActiveSpecGroup);
	if ok and tonumber(group) then
		return tonumber(group);
	end

	ok, group = pcall(GetActiveTalentGroup, false, false);
	if ok and tonumber(group) then
		return tonumber(group);
	end
	ok, group = pcall(GetActiveTalentGroup);
	if ok and tonumber(group) then
		return tonumber(group);
	end

	return nil;
end

function Resolvers.PlayerHasDualTalentSpecialization()
	local talentGroups = Resolvers.GetNumPlayerTalentGroups();
	if talentGroups and talentGroups > 1 then
		return true;
	end

	local activeGroup = Resolvers.GetActivePlayerTalentGroup();
	if activeGroup and activeGroup > 1 then
		return true;
	end

	if talentGroups == nil and activeGroup == nil then
		return nil;
	end
	return false;
end

do
local SOUL_OF_IRON_AURA_SPELL_IDS = { 364487, 364282, 364001 };
local SOUL_OF_IRON_FAILURE_AURA_SPELL_IDS = { 364226, 364227, 364228, 364456 };
local SOUL_OF_IRON_TRACKER_ACHIEVEMENTS = { [15332] = true, [16437] = true };
local SPECIAL_TITLE_ACHIEVEMENTS = {
	[15018] = 697,
	[16433] = 756,
};
local SOUL_OF_IRON_BOSS_ACHIEVEMENTS = {
	[11502] = 15330,
	[11583] = 15333,
	[15727] = 15334,
	[15990] = 15335,
};
local SOUL_OF_IRON_ACHIEVEMENT_BOSS_NPCS = {
	[15330] = 11502,
	[15333] = 11583,
	[15334] = 15727,
	[15335] = 15990,
};

local function BuildAuraNameLookup(spellIDs, fallbackNames)
	local names = {};
	for _, spellID in ipairs(spellIDs) do
		local name = GetSpellInfo(spellID);
		if type(name) == "string" and name ~= "" then
			names[name] = true;
		end
	end
	if type(fallbackNames) == "table" then
		for _, name in ipairs(fallbackNames) do
			if type(name) == "string" and name ~= "" then
				names[name] = true;
			end
		end
	end
	return names;
end

local function BuildSoulOfIronAuraNameLookup()
	local fallbackNames = { "Soul of Iron" };
	local tree = CRITERIA_TREE_DATA[138593];
	if tree and type(tree.description) == "string" and tree.description ~= "" then
		tinsert(fallbackNames, tree.description);
	end
	return BuildAuraNameLookup(SOUL_OF_IRON_AURA_SPELL_IDS, fallbackNames);
end

local function BuildSoulOfIronFailureAuraNameLookup()
	return BuildAuraNameLookup(SOUL_OF_IRON_FAILURE_AURA_SPELL_IDS, { "Tarnished Soul", "Perished at Level" });
end

local function PlayerHasAnyAuraSpellOrName(spellIDs, cacheField, buildNameLookup, auraSnapshot)
	if auraSnapshot then
		local auraSpellIDs = auraSnapshot.spellIDs or {};
		for _, spellID in ipairs(spellIDs) do
			spellID = tonumber(spellID) or 0;
			if spellID ~= 0 and auraSpellIDs[spellID] then
				return true;
			end
		end

		Private.state = Private.state or {};
		Private.state[cacheField] = Private.state[cacheField] or buildNameLookup();
		local names = Private.state[cacheField];
		local auraNames = auraSnapshot.names or {};
		for name in pairs(names) do
			if auraNames[name] then
				return true;
			end
		end

		return false;
	end

	for _, spellID in ipairs(spellIDs) do
		if Resolvers.PlayerHasAuraSpell(spellID) == true then
			return true;
		end
	end

	Private.state = Private.state or {};
	Private.state[cacheField] = Private.state[cacheField] or buildNameLookup();
	local names = Private.state[cacheField];
	for filterIndex = 1, 2 do
		local filter = filterIndex == 1 and "HELPFUL" or "HARMFUL";
		for auraIndex = 1, 40 do
			local name = UnitAura("player", auraIndex, filter);
			if not name then
				break;
			end
			if names[name] then
				return true;
			end
		end
	end

	return false;
end

function Resolvers.PlayerHasSoulOfIronTerminated(auraSnapshot)
	return PlayerHasAnyAuraSpellOrName(SOUL_OF_IRON_FAILURE_AURA_SPELL_IDS, "soulOfIronFailureAuraNames", BuildSoulOfIronFailureAuraNameLookup, auraSnapshot) == true;
end

function Resolvers.PlayerHasSoulOfIron(auraSnapshot)
	if Resolvers.PlayerHasSoulOfIronTerminated(auraSnapshot) then
		return false;
	end
	return PlayerHasAnyAuraSpellOrName(SOUL_OF_IRON_AURA_SPELL_IDS, "soulOfIronAuraNames", BuildSoulOfIronAuraNameLookup, auraSnapshot) == true;
end

local function HasSavedCriteriaAssetProgress(criteriaType, assetID)
	local allProgress = Resolvers.GetSavedCriteriaAssetProgress(criteriaType, assetID);
	local typeProgress = allProgress and allProgress[criteriaType];
	local progress = typeProgress and typeProgress[assetID];
	if not progress then
		return false;
	end
	return progress.completed == true or (tonumber(progress.quantity) or 0) > 0;
end

local function ResolveSoulOfIronBossAchievement(achievementID)
	local creatureID = SOUL_OF_IRON_ACHIEVEMENT_BOSS_NPCS[achievementID];
	if not creatureID then
		return nil;
	end

	local completed = (achievementID == 15330 and Resolvers.PlayerHasTitle(757) == true)
		or (Resolvers.PlayerHasSoulOfIron() == true and HasSavedCriteriaAssetProgress(CRITERIA_TYPE.KILL_NPC, creatureID));
	return completed, completed and 1 or 0, 1;
end

local function GetPlayerLevel()
	return tonumber(UnitLevel("player")) or 0;
end

function Resolvers.ResolveSpecialAchievementState(achievementID)
	achievementID = tonumber(achievementID) or 0;
	if achievementID == 0 then
		return nil;
	end

	if SOUL_OF_IRON_TRACKER_ACHIEVEMENTS[achievementID] then
		local completed = Resolvers.PlayerHasSoulOfIron() == true;
		return completed, completed and 1 or 0, 1;
	end

	if achievementID == 16433 then
		local completed = Resolvers.PlayerHasTitle(756) == true or (Resolvers.PlayerHasSoulOfIron() == true and GetPlayerLevel() >= 60);
		return completed, completed and 1 or 0, 1;
	end

	local bossCompleted, bossQuantity, bossRequiredQuantity = ResolveSoulOfIronBossAchievement(achievementID);
	if bossCompleted ~= nil then
		return bossCompleted, bossQuantity, bossRequiredQuantity;
	end

	local titleID = SPECIAL_TITLE_ACHIEVEMENTS[achievementID];
	if titleID then
		local completed = Resolvers.PlayerHasTitle(titleID) == true;
		return completed, completed and 1 or 0, 1;
	end

	return nil;
end

Achievements.ResolveSpecialAchievementState = Resolvers.ResolveSpecialAchievementState;

local NAXXRAMAS_MAP_ID = 533;
local NAXXRAMAS_BOSS_TOKENS = {
	[15956] = "anubrekhan",
	[15953] = "faerlina",
	[15952] = "maexxna",
	[15954] = "noth",
	[15936] = "heigan",
	[16011] = "loatheb",
	[16061] = "razuvious",
	[16060] = "gothik",
	[16064] = "korthazz",
	[16065] = "blaumeux",
	[16063] = "zeliek",
	[16062] = "mograine",
	[16028] = "patchwerk",
	[15931] = "grobbulus",
	[15932] = "gluth",
	[15928] = "thaddius",
	[15989] = "sapphiron",
	[15990] = "kelthuzad",
};
local NAXXRAMAS_REQUIRED_TOKENS = {
	"anubrekhan", "faerlina", "maexxna", "noth", "heigan", "loatheb",
	"razuvious", "gothik", "korthazz", "blaumeux", "zeliek", "mograine",
	"patchwerk", "grobbulus", "gluth", "thaddius", "sapphiron", "kelthuzad",
};

local function IsCurrentNaxxramas()
	return GetCurrentMapID() == NAXXRAMAS_MAP_ID;
end

local function GetSpecialProgressStore()
	AchievementsCharacterDB = AchievementsCharacterDB or {};
	AchievementsCharacterDB.specialAchievementProgress = AchievementsCharacterDB.specialAchievementProgress or {};
	return AchievementsCharacterDB.specialAchievementProgress;
end

local function GetWeeklyLockoutKey()
	local now = GetServerTime();
	local resetSeconds;
	local ok, seconds = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset);
	if ok then
		resetSeconds = tonumber(seconds);
	end
	if resetSeconds and resetSeconds > 0 then
		return "naxx:" .. tostring(math.floor((now + resetSeconds) / 60));
	end
	return "naxx-week:" .. tostring(math.floor(now / 604800));
end

local function GetSoulOfIronNaxxAttempt(create)
	if not IsCurrentNaxxramas() then
		return nil;
	end

	local store = GetSpecialProgressStore();
	local key = GetWeeklyLockoutKey();
	local attempt = store.soulOfIronNaxx;
	if attempt and attempt.key ~= key then
		attempt = nil;
	end
	if not attempt and create then
		attempt = { key = key, kills = {}, failed = false };
		store.soulOfIronNaxx = attempt;
	end
	return attempt;
end

local function NaxxramasAttemptComplete(attempt)
	if not attempt or attempt.failed or type(attempt.kills) ~= "table" then
		return false;
	end
	for _, token in ipairs(NAXXRAMAS_REQUIRED_TOKENS) do
		if not attempt.kills[token] then
			return false;
		end
	end
	return true;
end

local function MarkSpecialAchievementComplete(achievementID, showAlert)
	if Achievements.markAchievementComplete then
		return Achievements.markAchievementComplete(achievementID, showAlert) == true;
	end
	return false;
end

function Resolvers.RecordSoulOfIronBossKill(creatureID)
	creatureID = tonumber(creatureID) or 0;
	if creatureID == 0 or Resolvers.PlayerHasSoulOfIron() ~= true then
		return false;
	end

	local recorded = false;
	local achievementID = SOUL_OF_IRON_BOSS_ACHIEVEMENTS[creatureID];
	if achievementID then
		recorded = MarkSpecialAchievementComplete(achievementID, true) or recorded;
	end

	local token = NAXXRAMAS_BOSS_TOKENS[creatureID];
	if token then
		local attempt = GetSoulOfIronNaxxAttempt(true);
		if attempt and not attempt.failed then
			attempt.kills = attempt.kills or {};
			attempt.kills[token] = true;
			if NaxxramasAttemptComplete(attempt) then
				recorded = MarkSpecialAchievementComplete(15637, true) or recorded;
			end
		end
	end

	return recorded;
end

local function SoulOfIronNaxxBossCombatActive()
	Private.state = Private.state or {};
	local active = Private.state.soulOfIronNaxxBossActive;
	return active and active.lastSeen and (Resolvers.GetNow() - active.lastSeen) <= 120;
end

local function SoulOfIronDestIsGroupPlayer(destGUID, destFlags)
	if destGUID and destGUID == UnitGUID("player") then
		return true;
	end
	return destFlags
		and COMBATLOG_OBJECT_TYPE_PLAYER
		and HasFlag(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER)
		and (HasFlag(destFlags, COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001)
			or HasFlag(destFlags, COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002)
			or HasFlag(destFlags, COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004));
end

function Resolvers.RecordSoulOfIronNaxxRaidDeath()
	local attempt = GetSoulOfIronNaxxAttempt(false);
	if not attempt or attempt.failed or not SoulOfIronNaxxBossCombatActive() then
		return false;
	end
	attempt.failed = true;
	return true;
end

function Resolvers.RecordSoulOfIronNaxxCombatLog(subevent, sourceGUID, sourceFlags, destGUID, destFlags)
	if not IsCurrentNaxxramas() then
		return false;
	end

	local sourceCreatureID = GetCreatureIDFromGUID(sourceGUID);
	local destCreatureID = GetCreatureIDFromGUID(destGUID);
	local bossToken = (sourceCreatureID and NAXXRAMAS_BOSS_TOKENS[sourceCreatureID]) or (destCreatureID and NAXXRAMAS_BOSS_TOKENS[destCreatureID]);
	if bossToken then
		Private.state = Private.state or {};
		Private.state.soulOfIronNaxxBossActive = { token = bossToken, lastSeen = Resolvers.GetNow() };
		if Resolvers.PlayerHasSoulOfIron() == true then
			GetSoulOfIronNaxxAttempt(true);
		end
	end

	if (subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED")
		and SoulOfIronDestIsGroupPlayer(destGUID, destFlags)
	then
		return Resolvers.RecordSoulOfIronNaxxRaidDeath();
	end

	return false;
end

end

function Resolvers.RecordPlayerAuraCriteria(unit)
	if unit and unit ~= "player" then
		return false;
	end

	Private.state = Private.state or {};
	Private.state.criteriaAuraStates = Private.state.criteriaAuraStates or {};
	local auraStates = Private.state.criteriaAuraStates;
	local auraSnapshot = Resolvers.BuildPlayerAuraSnapshot("player");
	local auraSpellIDs = auraSnapshot.spellIDs or {};
	local auraCriteria = Resolvers.GetAuraCriteriaCache();
	local checkedAuras = {};
	local recordedAuraGains = {};
	local refreshTypes;
	local needsFullRefresh = false;
	local recorded = false;
	local hasSoulOfIron = Resolvers.PlayerHasSoulOfIron(auraSnapshot) == true;
	if Private.state.lastSoulOfIronAura ~= hasSoulOfIron then
		Private.state.lastSoulOfIronAura = hasSoulOfIron;
		needsFullRefresh = true;
		recorded = true;
	end

	for _, criteria in ipairs(auraCriteria.gains) do
		local auraSpellID = tonumber(criteria.asset) or 0;
		if auraSpellID ~= 0 then
			if checkedAuras[auraSpellID] == nil then
				checkedAuras[auraSpellID] = auraSpellIDs[auraSpellID] == true;
			end
			if checkedAuras[auraSpellID] and auraStates[auraSpellID] ~= true and not recordedAuraGains[auraSpellID] then
				recordedAuraGains[auraSpellID] = true;
				local ctx = {
					mapID = GetCurrentMapID(),
					zoneAreaID = GetCurrentZoneAreaID and GetCurrentZoneAreaID() or nil,
					sourceRaceID = GetPlayerRaceID and GetPlayerRaceID() or nil,
				};
				if Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.GAIN_AURA, auraSpellID, 1, ctx, "gain-aura-" .. tostring(auraSpellID)) then
					recorded = true;
					refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.GAIN_AURA);
				end
			end
		end
	end

	for _, criteria in ipairs(auraCriteria.starts) do
		local startSpellID = criteria.startAsset ~= 0 and criteria.startAsset or criteria.asset;
		startSpellID = tonumber(startSpellID) or 0;
		if startSpellID ~= 0 then
			if checkedAuras[startSpellID] == nil then
				checkedAuras[startSpellID] = auraSpellIDs[startSpellID] == true;
			end
			if checkedAuras[startSpellID] and Resolvers.StartCriteriaAttempt(criteria) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, criteria.type);
			end
		end
	end

	for _, criteria in ipairs(auraCriteria.fails) do
		local failSpellID = criteria.failAsset ~= 0 and criteria.failAsset or criteria.asset;
		failSpellID = tonumber(failSpellID) or 0;
		if failSpellID ~= 0 then
			if checkedAuras[failSpellID] == nil then
				checkedAuras[failSpellID] = auraSpellIDs[failSpellID] == true;
			end
			local hasAura = checkedAuras[failSpellID];
			local lostAura = criteria.failEvent == CRITERIA_FAIL_EVENT.LOSE_AURA and auraStates[failSpellID] == true and hasAura == false;
			local gainedAura = criteria.failEvent ~= CRITERIA_FAIL_EVENT.LOSE_AURA and hasAura == true;
			if (lostAura or gainedAura) and Resolvers.RecordCriteriaFail(criteria.failEvent, failSpellID) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, criteria.type);
			end
		end
	end

	for spellID, hasAura in pairs(checkedAuras) do
		auraStates[spellID] = hasAura;
	end

	if recorded and needsFullRefresh then
		if Achievements.ScheduleCriteriaRefresh then
			Achievements.ScheduleCriteriaRefresh(true, 0.35, "unit-aura");
		elseif Achievements.RefreshCriteriaAchievements then
			Achievements.RefreshCriteriaAchievements(true);
		end
	elseif recorded then
		Resolvers.ScheduleCriteriaTypesRefresh(refreshTypes or CRITERIA_TYPE.GAIN_AURA, true, 0.35, "unit-aura");
	end
	return recorded;
end

function Resolvers.HookTableFunction(apiTable, methodName, callback)
	if type(apiTable) == "table" and type(apiTable[methodName]) == "function" then
		hooksecurefunc(apiTable, methodName, callback);
		return true;
	end
	return false;
end

function Resolvers.HookGlobalFunction(functionName, callback)
	if type(_G[functionName]) == "function" then
		hooksecurefunc(functionName, callback);
		return true;
	end
	return false;
end

local function HookItemUseCriteria()
	if itemUseHooksInstalled then
		return itemUseHooksInstalled;
	end

	itemUseHooksInstalled = true;
	Resolvers.HookTableFunction(C_Container, "UseContainerItem", function(bagID, slotID)
		Resolvers.RecordVendorItemSale(bagID, slotID);
		RecordUsedItemID(GetContainerItemIDCompat(bagID, slotID));
	end);
	Resolvers.HookGlobalFunction("UseContainerItem", function(bagID, slotID)
		Resolvers.RecordVendorItemSale(bagID, slotID);
		RecordUsedItemID(GetContainerItemIDCompat(bagID, slotID));
	end);
	Resolvers.HookGlobalFunction("UseInventoryItem", function(slotID)
		RecordUsedItemID(GetInventoryItemID("player", slotID));
	end);
	Resolvers.HookTableFunction(C_Item, "UseItemByName", function(itemInfo)
		RecordUsedItemID(ExtractItemIDFromItemInfo(itemInfo));
	end);
	Resolvers.HookGlobalFunction("UseItemByName", function(itemInfo)
		RecordUsedItemID(ExtractItemIDFromItemInfo(itemInfo));
	end);

	return true;
end

local function ResolveUseItem(context)
	return ResolveSavedProgress(context);
end

function Resolvers.ResolveSimpleSavedProgress(context)
	return ResolveSavedProgress(context);
end

function Resolvers.ResolveGainAura(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if criteria and criteria.asset == Resolvers.dualTalentSpecializationSpellID and Resolvers.PlayerHasDualTalentSpecialization() == true then
		return BuildResult(true, requiredQuantity, requiredQuantity, nil, "dual-talent-specialization");
	end
	if criteria and criteria.asset and criteria.asset ~= 0 and Resolvers.PlayerHasAuraSpell(criteria.asset) == true then
		local ctx = {
			mapID = GetCurrentMapID(),
			zoneAreaID = GetCurrentZoneAreaID and GetCurrentZoneAreaID() or nil,
			sourceRaceID = GetPlayerRaceID and GetPlayerRaceID() or nil,
		};
		if EvaluateCriteriaModifier(criteria, ctx) then
			return BuildResult(true, requiredQuantity, requiredQuantity, nil, "gain-aura-live");
		end
	end
	return ResolveSavedProgress(context);
end

function Resolvers.RecordDualTalentSpecializationCriteria()
	if Resolvers.PlayerHasDualTalentSpecialization() ~= true then
		return false;
	end
	return Resolvers.SetCriteriaAssetProgressMax(CRITERIA_TYPE.GAIN_AURA, Resolvers.dualTalentSpecializationSpellID, 1, GetProgressCharacterName());
end

function Resolvers.GetCurrencyQuantity(currencyID)
	currencyID = tonumber(currencyID);
	if not currencyID or currencyID == 0 then
		return nil;
	end

	local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID);
	if ok and type(info) == "table" then
		return tonumber(info.totalEarned) or tonumber(info.quantity);
	end

	ok, _, info = pcall(GetCurrencyInfo, currencyID);
	if ok then
		return tonumber(info);
	end

	return nil;
end

function Resolvers.ResolveCurrencyGained(context)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local quantity = Resolvers.GetCurrencyQuantity(criteria.asset);
	if quantity == nil then
		return ResolveSavedProgress(context);
	end

	quantity = ApplySavedProgressQuantity(context, quantity, requiredQuantity);
	return BuildResult(quantity >= requiredQuantity, quantity, requiredQuantity, nil, "currency-gained");
end

function Resolvers.RecordCurrencyScan()
	AchievementsCharacterDB = AchievementsCharacterDB or {};
	AchievementsCharacterDB.currencyLastSeen = AchievementsCharacterDB.currencyLastSeen or {};
	local seen = AchievementsCharacterDB.currencyLastSeen;
	local recorded = false;

	for _, criteria in pairs(CRITERIA_DATA) do
		if Resolvers.IsClientRecordableCriteria(criteria) and criteria.type == CRITERIA_TYPE.CURRENCY_GAINED and criteria.asset and criteria.asset ~= 0 then
			local quantity = Resolvers.GetCurrencyQuantity(criteria.asset);
			if quantity ~= nil then
				local previous = seen[criteria.asset];
				seen[criteria.asset] = quantity;
				if previous ~= nil and quantity > previous then
					recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.CURRENCY_GAINED, criteria.asset, quantity - previous, { currencyID = criteria.asset }, "currency-" .. tostring(criteria.asset)) or recorded;
			end
			end
		end
	end

	if recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

function Resolvers.GetArenaRating(teamSize, personal)
	teamSize = tonumber(teamSize);
	if not teamSize or teamSize == 0 then
		return nil;
	end

	if GetPersonalRatedInfo then
		local bracket = teamSize == 2 and 1 or teamSize == 3 and 2 or teamSize == 5 and 3 or nil;
		if bracket then
			local ok, rating, seasonBest = pcall(GetPersonalRatedInfo, bracket);
			if ok then
				return tonumber(seasonBest) or tonumber(rating);
			end
		end
	end

	local maxTeams = MAX_ARENA_TEAMS or 3;
	for teamIndex = 1, maxTeams do
		local values = { GetArenaTeam(teamIndex) };
		local size = tonumber(values[2]);
		if size == teamSize then
			if personal then
				return tonumber(values[10]) or tonumber(values[9]) or tonumber(values[3]);
			end
			return tonumber(values[3]);
		end
	end

	return nil;
end

Resolvers.timeEventArenaSeasonStarts = Resolvers.timeEventArenaSeasonStarts or {
	[156] = 1,
	[159] = 2,
	[162] = 3,
	[165] = 4,
	[268] = 1,
	[270] = 5,
	[276] = 6,
	[283] = 7,
	[290] = 8,
	[135] = 9,
};

function Resolvers.GetCurrentArenaSeason(ctx)
	if type(ctx) == "table" then
		local season = tonumber(ctx.currentArenaSeason) or tonumber(ctx.arenaSeason);
		if season then
			return season;
		end
	end

	if GetCurrentArenaSeason then
		local ok, season = pcall(GetCurrentArenaSeason);
		if ok then
			return tonumber(season);
		end
	end

	return nil;
end

function Resolvers.IsArenaSeasonActive(ctx)
	if type(ctx) == "table" and ctx.arenaSeasonActive ~= nil then
		return ctx.arenaSeasonActive == true;
	end

	if IsArenaSeasonActive then
		local ok, active = pcall(IsArenaSeasonActive);
		if ok then
			return active == true;
		end
	end

	return nil;
end

function Resolvers.CurrentArenaSeasonUsesTeams()
	local ok, usesTeams = pcall(GetCurrentArenaSeasonUsesTeams);
	if ok then
		return usesTeams == true;
	end

	return nil;
end

function Resolvers.EvaluateKnownTimeEventPassed(ctx, asset)
	asset = tonumber(asset) or 0;
	if type(ctx) == "table" and type(ctx.timeEventsPassed) == "table" and ctx.timeEventsPassed[asset] ~= nil then
		return ctx.timeEventsPassed[asset] == true;
	end

	local requiredSeason = Resolvers.timeEventArenaSeasonStarts and Resolvers.timeEventArenaSeasonStarts[asset];
	if not requiredSeason then
		return nil;
	end

	local currentSeason = Resolvers.GetCurrentArenaSeason(ctx);
	if currentSeason and currentSeason > 0 then
		return currentSeason >= requiredSeason;
	end

	if asset == 268 then
		local active = Resolvers.IsArenaSeasonActive(ctx);
		if active ~= nil then
			return active;
		end
		local usesTeams = Resolvers.CurrentArenaSeasonUsesTeams();
		if usesTeams ~= nil then
			return usesTeams;
		end
	end

	return false;
end

function Resolvers.ResolveArenaRating(context, personal)
	local criteria = context.criteria;
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if not criteria or not criteria.asset or criteria.asset == 0 then
		return ResolveSavedProgress(context);
	end

	local rating = Resolvers.GetArenaRating(criteria.asset, personal);
	if not rating then
		return ResolveSavedProgress(context);
	end

	rating = ApplySavedProgressQuantity(context, rating, requiredQuantity);
	return BuildResult(rating >= requiredQuantity, rating, requiredQuantity, nil, personal and "personal-arena-rating" or "team-arena-rating");
end

function Resolvers.NormalizeCriteriaText(text)
	if type(text) ~= "string" then
		return nil;
	end
	text = Resolvers.LocaleLower(text);
	text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "");
	text = string.gsub(text, "|r", "");
	text = string.gsub(text, "^%s+", "");
	text = string.gsub(text, "%s+$", "");
	text = string.gsub(text, "%s+", " ");
	if text == "" then
		return nil;
	end
	return text;
end

function Resolvers.GetCriteriaAssetsByDescription(criteriaType)
	Resolvers.criteriaAssetsByDescription = Resolvers.criteriaAssetsByDescription or {};
	if Resolvers.criteriaAssetsByDescription[criteriaType] then
		return Resolvers.criteriaAssetsByDescription[criteriaType];
	end

	local byDescription = {};
	for _, criteriaTree in pairs(CRITERIA_TREE_DATA) do
		local criteria = criteriaTree.criteriaID and CRITERIA_DATA[criteriaTree.criteriaID] or nil;
		if criteria and Resolvers.IsClientRecordableCriteria(criteria) and criteria.type == criteriaType and criteria.asset and criteria.asset ~= 0 then
			local key = Resolvers.NormalizeCriteriaText(criteriaTree.description);
			if key then
				byDescription[key] = byDescription[key] or {};
				byDescription[key][criteria.asset] = true;
			end
		end
	end

	Resolvers.criteriaAssetsByDescription[criteriaType] = byDescription;
	return byDescription;
end

function Resolvers.RecordGameObjectTextCriteria(title)
	if not title and ItemTextGetItem then
		title = ItemTextGetItem();
	end
	if not title and ItemTextFrameTitleText and ItemTextFrameTitleText.GetText then
		title = ItemTextFrameTitleText:GetText();
	end

	local key = Resolvers.NormalizeCriteriaText(title);
	if not key then
		return false;
	end

	local recorded = false;
	local assets = Resolvers.GetCriteriaAssetsByDescription(CRITERIA_TYPE.USE_GAME_OBJECT)[key];
	if assets then
		for objectID in pairs(assets) do
			recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.USE_GAME_OBJECT, objectID, 1, { objectID = objectID }, "gameobject-text-" .. tostring(objectID)) or recorded;
		end
	end

	if recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

function Resolvers.GetGameObjectIDFromGUID(guid)
	if type(guid) ~= "string" then
		return nil;
	end

	local objectType, _, _, _, _, objectID = strsplit("-", guid);
	if objectType == "GameObject" then
		return tonumber(objectID);
	end
	return nil;
end

function Resolvers.RecordPlayerSpellcast(unit, _, spellID)
	if unit and unit ~= "player" then
		return false;
	end
	spellID = tonumber(spellID) or 0;
	if spellID == 0 then
		return false;
	end

	Private.state = Private.state or {};
	local now = Resolvers.GetNow();
	if spellID == 7620 or spellID == 7731 or spellID == 7732 or spellID == 18248 or spellID == 33095 or spellID == 51294 then
		Private.state.lastFishingCastAt = now;
		return true;
	elseif spellID == 13262 then
		Private.state.lastDisenchantCastAt = now;
		return true;
	end
	return false;
end

function Resolvers.RecentCriteriaCast(kind, window)
	Private.state = Private.state or {};
	local key = kind == "disenchant" and "lastDisenchantCastAt" or "lastFishingCastAt";
	local lastCastAt = Private.state[key];
	return lastCastAt and (Resolvers.GetNow() - lastCastAt) <= (window or 20);
end

function Resolvers.BuildChatFormatPattern(formatText, rolesByArgument)
	if type(formatText) ~= "string" or formatText == "" then
		return nil;
	end

	local parts = { "^" };
	local captureRoles = {};
	local index = 1;
	local nextArgument = 1;
	while index <= string.len(formatText) do
		local char = string.sub(formatText, index, index);
		if char == "%" then
			local marker = string.sub(formatText, index + 1, index + 1);
			if marker == "%" then
				parts[#parts + 1] = "%%";
				index = index + 2;
			else
				local specIndex = index + 1;
				local positionText = string.match(formatText, "^(%d+)%$", specIndex);
				local argumentIndex;
				if positionText then
					argumentIndex = tonumber(positionText);
					specIndex = specIndex + string.len(positionText) + 1;
				else
					argumentIndex = nextArgument;
					nextArgument = nextArgument + 1;
				end
				while specIndex <= string.len(formatText) do
					local spec = string.sub(formatText, specIndex, specIndex);
					if string.find("diuoxXfFeEgGaAcspq", spec, 1, true) then
						local role = rolesByArgument and rolesByArgument[argumentIndex] or nil;
						if spec == "d" or spec == "i" or spec == "u" then
							parts[#parts + 1] = "([+-]?%d+)";
						elseif spec == "s" then
							parts[#parts + 1] = "(.-)";
						else
							parts[#parts + 1] = "(.+)";
						end
						captureRoles[#captureRoles + 1] = role or false;
						index = specIndex + 1;
						break;
					end
					specIndex = specIndex + 1;
				end
				if specIndex > string.len(formatText) then
					parts[#parts + 1] = Resolvers.EscapeLuaPattern(char);
					index = index + 1;
				end
			end
		else
			parts[#parts + 1] = Resolvers.EscapeLuaPattern(char);
			index = index + 1;
		end
	end
	parts[#parts + 1] = "$";
	return table.concat(parts), captureRoles;
end

function Resolvers.ReadPatternCaptures(captureRoles, ...)
	local values = {};
	local count = select("#", ...);
	for index = 1, count do
		local role = captureRoles and captureRoles[index] or nil;
		if role then
			values[role] = select(index, ...);
		end
	end
	return values;
end

function Resolvers.GetLootRollPatterns()
	if Resolvers.lootRollPatterns then
		return Resolvers.lootRollPatterns;
	end

	local patterns = {};
	local function add(formatText, criteriaType, rolesByArgument, selfRoll)
		local pattern, captureRoles = Resolvers.BuildChatFormatPattern(formatText, rolesByArgument);
		if pattern then
			patterns[#patterns + 1] = { pattern = pattern, captureRoles = captureRoles, criteriaType = criteriaType, selfRoll = selfRoll == true };
		end
	end

	add(_G.LOOT_ROLL_ROLLED_NEED, CRITERIA_TYPE.NEED_ROLL, { [2] = "roll", [3] = "item", [4] = "roller" });
	add(_G.LOOT_ROLL_ROLLED_NEED_ROLE_BONUS, CRITERIA_TYPE.NEED_ROLL, { [1] = "roll", [2] = "item", [3] = "roller" });
	add(_G.LOOT_ROLL_ROLLED_NEED_SELF, CRITERIA_TYPE.NEED_ROLL, { [1] = "roll", [2] = "item" }, true);
	add(_G.LOOT_ROLL_ROLLED_GREED, CRITERIA_TYPE.GREED_ROLL, { [2] = "roll", [3] = "item", [4] = "roller" });
	add(_G.LOOT_ROLL_ROLLED_GREED_SELF, CRITERIA_TYPE.GREED_ROLL, { [1] = "roll", [2] = "item" }, true);
	add(_G.LOOT_ROLL_ROLLED_DE, CRITERIA_TYPE.DISENCHANT_ROLL, { [1] = "roll", [2] = "item", [3] = "roller" });

	Resolvers.lootRollPatterns = patterns;
	return patterns;
end

function Resolvers.GetLocalizedSelfNames()
	if Resolvers.localizedSelfNames then
		return Resolvers.localizedSelfNames;
	end
	local names = {};
	local seen = {};
	for _, globalName in ipairs({ "YOU", "UNIT_YOU", "UNIT_YOU_SOURCE", "UNIT_YOU_DEST" }) do
		local value = rawget and rawget(_G, globalName) or _G[globalName];
		if type(value) == "string" and value ~= "" and not seen[value] then
			seen[value] = true;
			names[#names + 1] = value;
		end
	end
	Resolvers.localizedSelfNames = names;
	return names;
end

function Resolvers.IsPlayerNameOrSelf(name)
	if type(name) ~= "string" or name == "" then
		return false;
	end
	for _, selfName in ipairs(Resolvers.GetLocalizedSelfNames()) do
		if name == selfName then
			return true;
		end
	end
	local playerName = UnitName("player");
	local shortName = string.match(name, "^[^-]+") or name;
	return name == playerName or shortName == playerName;
end

function Resolvers.ParseLootRollMessage(message)
	if type(message) ~= "string" or message == "" then
		return nil;
	end

	for _, info in ipairs(Resolvers.GetLootRollPatterns()) do
		local captures = Resolvers.ReadPatternCaptures(info.captureRoles, string.match(message, info.pattern));
		local rollValue = tonumber(captures.roll);
		if rollValue then
			local rollerName = captures.roller;
			if info.selfRoll then
				rollerName = UnitName("player") or Resolvers.GetLocalizedSelfNames()[1];
			end
			return info.criteriaType, rollValue, captures.item, rollerName;
		end
	end

	return nil;
end

function Resolvers.RecordLootRollCriteria(message)
	local criteriaType, rollValue, itemText, rollerName = Resolvers.ParseLootRollMessage(message);
	if not criteriaType or not rollValue or not Resolvers.IsPlayerNameOrSelf(rollerName) then
		return false;
	end

	Private.state = Private.state or {};
	Private.state.recentLootRollMessages = Private.state.recentLootRollMessages or {};
	local now = Resolvers.GetNow();
	local key = tostring(criteriaType) .. ":" .. tostring(rollValue) .. ":" .. tostring(itemText or "");
	if Private.state.recentLootRollMessages[key] and (now - Private.state.recentLootRollMessages[key]) < 2 then
		return false;
	end
	Private.state.recentLootRollMessages[key] = now;

	local recorded = Resolvers.RecordCriteriaProgress(criteriaType, rollValue, 1, {
		rollValue = rollValue,
		itemText = itemText,
	}, "loot-roll-" .. key);
	if recorded and Achievements.ScheduleCriteriaRefresh then
		Achievements.ScheduleCriteriaRefresh(true, 0.25, "loot-roll");
	elseif recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

function Resolvers.RecordLootAcquisitionCriteria(message)
	local recorded = false;
	recorded = Resolvers.RecordLootRollCriteria(message) or recorded;
	local lootContexts = {};
	if type(message) == "string" then
		for itemLink in string.gmatch(message, "|Hitem:[^|]+|h%[[^%]]+%]|h") do
			local itemID = ExtractItemIDFromLink(itemLink);
			local itemRecord = itemID and ITEM_DATA[itemID] or nil;
			local itemQuality, itemLevel;
			local _, _, quality, level = GetItemInfo(itemLink);
			itemQuality = quality;
			itemLevel = level;
			local ctx = {
				itemLink = itemLink,
				itemID = itemID,
				itemClass = itemRecord and itemRecord.class,
				itemSubclass = itemRecord and itemRecord.subclass,
				itemQuality = itemQuality or (itemRecord and itemRecord.quality),
				itemLevel = itemLevel,
			};
			lootContexts[#lootContexts + 1] = ctx;
			recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.ACQUIRE_ITEM, 0, 1, ctx, "acquire-item-any-" .. itemLink) or recorded;
			recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.LOOT_ITEM, 0, 1, ctx, "loot-item-any-" .. itemLink) or recorded;
			recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.LOOT_ANY_ITEM, 0, 1, ctx, "loot-any-item-" .. itemLink) or recorded;
			recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.OBTAIN_ANY_ITEM, 0, 1, ctx, "obtain-any-item-" .. itemLink) or recorded;
		end
	end

	if Resolvers.RecentCriteriaCast("fishing", 30) then
		if #lootContexts > 0 then
			for index, ctx in ipairs(lootContexts) do
				recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.GET_LOOT_BY_ACQUISITION, 3, 1, ctx, "loot-fishing-" .. tostring(ctx.itemLink or "") .. ":" .. tostring(index)) or recorded;
			end
		else
			recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.GET_LOOT_BY_ACQUISITION, 3, 1, {}, "loot-fishing") or recorded;
		end
	elseif Resolvers.RecentCriteriaCast("disenchant", 10) then
		if #lootContexts > 0 then
			for index, ctx in ipairs(lootContexts) do
				recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.GET_LOOT_BY_ACQUISITION, 4, 1, ctx, "loot-disenchant-" .. tostring(ctx.itemLink or "") .. ":" .. tostring(index)) or recorded;
			end
		else
			recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.GET_LOOT_BY_ACQUISITION, 4, 1, {}, "loot-disenchant") or recorded;
		end
	end

	for slot = 1, GetNumLootItems() do
		local sourceGUID = GetLootSourceInfo(slot);
		local objectID = Resolvers.GetGameObjectIDFromGUID(sourceGUID);
		if objectID then
			recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.USE_GAME_OBJECT, objectID, 1, { objectID = objectID }, "loot-object-" .. tostring(objectID)) or recorded;
			if Resolvers.RecentCriteriaCast("fishing", 30) then
				recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.CATCH_FISH_IN_POOL, objectID, 1, { objectID = objectID }, "fish-pool-" .. tostring(objectID)) or recorded;
			end
		end
	end

	if recorded and Achievements.ScheduleCriteriaRefresh then
		Achievements.ScheduleCriteriaRefresh(true, 0.25, "loot");
	elseif recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

function Resolvers.RecordMoneyCriteria(criteriaType, amount, source)
	amount = tonumber(amount) or 0;
	if amount <= 0 then
		return false;
	end
	local recorded = Resolvers.RecordCriteriaProgress(criteriaType, 0, amount, { money = amount }, source or ("money-" .. tostring(criteriaType)));
	if recorded and Achievements.ScheduleCriteriaRefresh then
		Achievements.ScheduleCriteriaRefresh(true, 0.25, source or ("money-" .. tostring(criteriaType)));
	elseif recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

function Resolvers.GetEconomySeenTable(name)
	AchievementsCharacterDB = AchievementsCharacterDB or {};
	AchievementsCharacterDB.economySeen = AchievementsCharacterDB.economySeen or {};
	AchievementsCharacterDB.economySeen[name] = AchievementsCharacterDB.economySeen[name] or {};
	return AchievementsCharacterDB.economySeen[name];
end

function Resolvers.GetCoinAmountPatterns()
	if Resolvers.coinAmountPatterns then
		return Resolvers.coinAmountPatterns;
	end

	local patterns = {};
	local seen = {};
	local function addPattern(pattern, multiplier)
		if pattern and not seen[pattern] then
			seen[pattern] = true;
			table.insert(patterns, { pattern = pattern, multiplier = multiplier });
		end
	end
	local function addFormat(formatText, multiplier)
		local pattern = Resolvers.BuildChatFormatPattern(formatText);
		if pattern then
			pattern = string.gsub(pattern, "^%^", "");
			pattern = string.gsub(pattern, "%$$", "");
			addPattern(pattern, multiplier);
		end
	end

	addFormat(_G.GOLD_AMOUNT, 10000);
	addFormat(_G.GOLD_AMOUNT_TEXTURE, 10000);
	addFormat(_G.GOLD_AMOUNT_TEXTURE_STRING, 10000);
	addFormat(_G.SILVER_AMOUNT, 100);
	addFormat(_G.SILVER_AMOUNT_TEXTURE, 100);
	addFormat(_G.COPPER_AMOUNT, 1);
	addFormat(_G.COPPER_AMOUNT_TEXTURE, 1);

	Resolvers.coinAmountPatterns = patterns;
	return patterns;
end

function Resolvers.ParseCoinAmountValue(value)
	if value == nil then
		return 0;
	end
	local normalized = string.gsub(tostring(value), "[^%d+-]", "");
	return tonumber(normalized) or 0;
end

function Resolvers.ParseMoneyString(message)
	if type(message) ~= "string" or message == "" then
		return 0;
	end
	local total = 0;
	for _, info in ipairs(Resolvers.GetCoinAmountPatterns()) do
		for value in string.gmatch(message, info.pattern) do
			total = total + (Resolvers.ParseCoinAmountValue(value) * info.multiplier);
		end
	end
	return total;
end

function Resolvers.RecordMoneyChatCriteria(message)
	local amount = Resolvers.ParseMoneyString(message);
	if amount <= 0 then
		return false;
	end
	return Resolvers.RecordMoneyCriteria(CRITERIA_TYPE.MONEY_LOOTED_FROM_CREATURES, amount, "loot-money-chat");
end

function Resolvers.GetInboxHeader(index)
	if C_Mail and C_Mail.GetInboxHeaderInfo then
		local ok, info = pcall(C_Mail.GetInboxHeaderInfo, index);
		if ok and type(info) == "table" then
			return {
				mailID = info.mailID or info.id,
				sender = info.sender,
				subject = info.subject,
				money = tonumber(info.money) or 0,
				hasItem = info.hasItem,
			};
		end
	end
	local _, _, sender, subject, money, _, _, hasItem = GetInboxHeaderInfo(index);
	return {
		mailID = nil,
		sender = sender,
		subject = subject,
		money = tonumber(money) or 0,
		hasItem = hasItem,
	};
end

function Resolvers.GetInboxInvoice(index)
	local ok, invoiceType, itemName, playerName, bid, buyout, deposit, consignment = pcall(GetInboxInvoiceInfo, index);
	if not ok or not invoiceType then
		return nil;
	end
	return {
		invoiceType = tostring(invoiceType),
		itemName = itemName,
		playerName = playerName,
		bid = tonumber(bid) or 0,
		buyout = tonumber(buyout) or 0,
		deposit = tonumber(deposit) or 0,
		consignment = tonumber(consignment) or 0,
	};
end

function Resolvers.BuildAuctionInvoiceKey(header, invoice)
	if header and header.mailID then
		return "mail:" .. tostring(header.mailID);
	end
	return table.concat({
		"invoice",
		tostring(invoice and invoice.invoiceType or ""),
		tostring(header and header.sender or ""),
		tostring(header and header.subject or ""),
		tostring(invoice and invoice.itemName or ""),
		tostring(invoice and invoice.playerName or ""),
		tostring(header and header.money or 0),
		tostring(invoice and invoice.bid or 0),
		tostring(invoice and invoice.buyout or 0),
	}, ":");
end

function Resolvers.RecordAuctionInvoiceInfo(header, invoice, count)
	if not invoice or not invoice.invoiceType then
		return false;
	end
	count = tonumber(count) or 1;
	if count <= 0 then
		return false;
	end

	local invoiceType = string.lower(invoice.invoiceType);
	local recorded = false;
	if string.find(invoiceType, "seller", 1, true) then
		local amount = tonumber(header and header.money) or 0;
		if amount <= 0 then
			amount = math.max(tonumber(invoice.bid) or 0, tonumber(invoice.buyout) or 0);
		end
		if amount > 0 then
			recorded = Resolvers.RecordMoneyCriteria(CRITERIA_TYPE.MONEY_EARNED_FROM_AUCTIONS, amount * count, "auction-seller-mail") or recorded;
			recorded = Resolvers.SetCriteriaAssetProgressMax(CRITERIA_TYPE.HIGHEST_ITEM_SOLD_VALUE, 0, amount, GetProgressCharacterName()) or recorded;
		end
	elseif string.find(invoiceType, "buyer", 1, true) then
		recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.AUCTIONS_WON, 0, count, {
			itemName = invoice.itemName,
		}, "auction-buyer-mail") or recorded;
	end

	if recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

function Resolvers.RecordMailboxAuctionCriteria(index)
	local entries = {};
	local function collect(mailIndex)
		local header = Resolvers.GetInboxHeader(mailIndex);
		local invoice = Resolvers.GetInboxInvoice(mailIndex);
		if not invoice then
			return;
		end
		local key = Resolvers.BuildAuctionInvoiceKey(header, invoice);
		entries[key] = entries[key] or { header = header, invoice = invoice, count = 0 };
		entries[key].count = entries[key].count + 1;
	end

	if index then
		collect(index);
	else
		local inboxCount = tonumber((GetInboxNumItems())) or 0;
		for mailIndex = 1, inboxCount do
			collect(mailIndex);
		end
	end

	local seen = Resolvers.GetEconomySeenTable("auctionInvoices");
	local recorded = false;
	for key, entry in pairs(entries) do
		local previous = tonumber(seen[key]) or 0;
		if entry.count > previous then
			recorded = Resolvers.RecordAuctionInvoiceInfo(entry.header, entry.invoice, entry.count - previous) or recorded;
			seen[key] = entry.count;
		end
	end
	return recorded;
end

function Resolvers.RecordVendorItemSale(bagID, slotID)
	if not MerchantFrame or not MerchantFrame.IsShown or not MerchantFrame:IsShown() then
		return false;
	end
	local itemID = GetContainerItemIDCompat(bagID, slotID);
	if not itemID then
		return false;
	end
	local quantity = GetContainerItemCountCompat(bagID, slotID) or 1;
	local vendorPrice = 0;
	local sellPrice = select(11, GetItemInfo(itemID));
	vendorPrice = tonumber(sellPrice) or 0;
	if vendorPrice <= 0 then
		return false;
	end
	local recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.SELL_ITEMS_TO_VENDORS, 0, quantity, {
		itemID = itemID,
		quantity = quantity,
		money = vendorPrice * quantity,
	}, "vendor-sale-" .. tostring(itemID));
	if recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

function Resolvers.RecordTaxiMoneySpent(nodeID)
	local cost = TaxiNodeCost and TaxiNodeCost(nodeID) or 0;
	return Resolvers.RecordMoneyCriteria(CRITERIA_TYPE.MONEY_SPENT_ON_TAXIS, cost, "taxi-money");
end

function Resolvers.RecordPostageMoneySpent()
	local cost = GetSendMailPrice() or 0;
	return Resolvers.RecordMoneyCriteria(CRITERIA_TYPE.MONEY_SPENT_ON_POSTAGE, cost, "postage-money");
end

function Resolvers.RecordRespecCriteria()
	local recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.TOTAL_RESPECS, 0, 1, {}, "total-respecs");
	local cost = GetTalentResetCost and GetTalentResetCost() or 0;
	recorded = Resolvers.RecordMoneyCriteria(CRITERIA_TYPE.MONEY_SPENT_ON_RESPECS, cost, "respec-money") or recorded;
	if recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

function Resolvers.RecordAuctionPosted()
	return Resolvers.RecordSimpleCriteria(CRITERIA_TYPE.AUCTION_ITEMS_POSTED, "auction-posted");
end

function Resolvers.RecordAuctionBid(bidAmount)
	bidAmount = tonumber(bidAmount) or 0;
	if bidAmount <= 0 then
		return false;
	end
	local recorded = Resolvers.SetCriteriaAssetProgressMax(CRITERIA_TYPE.HIGHEST_AUCTION_BID, 0, bidAmount, GetProgressCharacterName());
	if recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

function Resolvers.GetBarberShopCost()
	if GetBarberShopTotalCost then
		return tonumber(GetBarberShopTotalCost()) or 0;
	end
	if C_BarberShop and C_BarberShop.GetCurrentCost then
		local ok, cost = pcall(C_BarberShop.GetCurrentCost);
		if ok then
			return tonumber(cost) or 0;
		end
	end
	return 0;
end

function Resolvers.SetCriteriaAssetProgressMax(criteriaType, assetID, quantity, characterName)
	criteriaType = tonumber(criteriaType);
	assetID = tonumber(assetID) or 0;
	quantity = tonumber(quantity) or 0;
	if not criteriaType or quantity <= 0 then
		return false;
	end

	local criteriaAssetProgress = Resolvers.GetSavedCriteriaAssetProgress(criteriaType, assetID);
	criteriaAssetProgress[criteriaType] = criteriaAssetProgress[criteriaType] or {};
	local progress = criteriaAssetProgress[criteriaType][assetID] or {};
	if (progress.quantity or 0) >= quantity then
		return false;
	end
	progress.quantity = quantity;
	progress.completed = progress.completed == true;
	progress.character = nil;
	if Private.SealSavedRecord then
		Private.SealSavedRecord(progress, "criteriaAsset", tostring(criteriaType) .. ":" .. tostring(assetID), Resolvers.CriteriaAssetUsesAccountProgress(criteriaType, assetID), "quantity", "completed");
	end
	criteriaAssetProgress[criteriaType][assetID] = progress;
	return true;
end

function Resolvers.ResolveBankSlotsPurchased(context)
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	local bankSlots = GetNumBankSlots();
	local quantity = tonumber(bankSlots) or 0;
	quantity = ApplySavedProgressQuantity(context, quantity, requiredQuantity);
	return BuildResult(quantity >= requiredQuantity, quantity, requiredQuantity, nil, "bank-slots");
end

function Resolvers.ResolveMostMoneyOwned(context)
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	local quantity = GetMoney();
	quantity = ApplySavedProgressQuantity(context, quantity, requiredQuantity);
	return BuildResult(quantity >= requiredQuantity, quantity, requiredQuantity, nil, "money-owned");
end

function Resolvers.ResolveAchievementPoints(context)
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	if Achievements.GetTotalAchievementPoints then
		local quantity = tonumber(Achievements.GetTotalAchievementPoints()) or 0;
		return BuildResult(quantity >= requiredQuantity, quantity, requiredQuantity, nil, "achievement-points");
	end
	return ResolveSavedProgress(context);
end

function Resolvers.ResolveHonorableKills(context)
	local requiredQuantity = context.requiredQuantity or GetRequiredQuantity(context.criteriaTree);
	local lifetimeKills = tonumber((GetPVPLifetimeStats())) or 0;
	lifetimeKills = ApplySavedProgressQuantity(context, lifetimeKills, requiredQuantity);
	return BuildResult(lifetimeKills >= requiredQuantity, lifetimeKills, requiredQuantity, nil, "honorable-kills");
end

function Resolvers.RecordInstanceRun()
	Private.state = Private.state or {};
	local _, instanceType, _, _, maxPlayers, _, _, instanceMapID = GetInstanceInfo();
	maxPlayers = tonumber(maxPlayers);
	instanceMapID = tonumber(instanceMapID);
	if not maxPlayers or maxPlayers == 0 or not instanceMapID or instanceMapID == 0 or (instanceType ~= "party" and instanceType ~= "raid") then
		Private.state.lastInstanceRunKey = nil;
		return false;
	end

	local key = tostring(instanceMapID) .. ":" .. tostring(maxPlayers);
	if Private.state.lastInstanceRunKey == key then
		return false;
	end
	Private.state.lastInstanceRunKey = key;
	return Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.RUN_INSTANCE_WITH_MAX_PLAYERS, maxPlayers, 1, { mapID = instanceMapID, zoneAreaID = instanceMapID }, "run-instance-" .. key);
end

function Resolvers.RecordEncounterDefeat(encounterID, success)
	encounterID = tonumber(encounterID);
	if not encounterID or encounterID == 0 then
		return false;
	end
	if success ~= nil and success ~= true and tonumber(success) ~= 1 then
		return false;
	end

	local ctx = {
		encounterID = encounterID,
		mapID = GetCurrentMapID(),
		zoneAreaID = GetCurrentZoneAreaID and GetCurrentZoneAreaID() or nil,
		sourceRaceID = GetPlayerRaceID and GetPlayerRaceID() or nil,
	};
	local recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.DEFEAT_ENCOUNTER, encounterID, 1, ctx, "defeat-encounter-" .. tostring(encounterID));
	recorded = Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.DEFEAT_ENCOUNTER_WHILE_ELIGIBLE_FOR_LOOT, encounterID, 1, ctx, "defeat-loot-encounter-" .. tostring(encounterID)) or recorded;
	if recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

function Resolvers.RecordPlayerMoneySnapshot()
	return Resolvers.SetCriteriaAssetProgressMax(CRITERIA_TYPE.MOST_MONEY_OWNED, 0, GetMoney(), GetProgressCharacterName());
end

function Resolvers.RecordSimpleCriteria(criteriaType, dedupeKey)
	local recorded = Resolvers.RecordCriteriaProgress(criteriaType, 0, 1, {}, dedupeKey);
	if recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

function Resolvers.BackfillCurrentState()
	Private.state = Private.state or {};
	if Private.state.currentStateBackfillRunning then
		return false;
	end
	Private.state.currentStateBackfillRunning = true;

	if Achievements.BeginSilentBackfill then
		Achievements.BeginSilentBackfill();
	end

	local ok, recordedOrError = pcall(function()
		local recorded = false;
		if Achievements.ClearQuestCompletionCache then Achievements.ClearQuestCompletionCache(); end
		if Achievements.ClearExplorationCache then Achievements.ClearExplorationCache(); end
		if Achievements.ClearCharacterScanCache then Achievements.ClearCharacterScanCache(); end

		recorded = Resolvers.RecordLoginCriteria() or recorded;
		recorded = RecordBattlegroundParticipation() or recorded;
		recorded = Resolvers.RecordArenaParticipation() or recorded;
		recorded = Resolvers.RecordInstanceRun() or recorded;
		recorded = Resolvers.RecordPlayerAuraCriteria("player") or recorded;
		Resolvers.RecordEquippedItemSlot();
		recorded = Resolvers.RecordWorldStateScan() or recorded;
		recorded = Resolvers.RecordDailyQuestResetCheck() or recorded;
		recorded = Resolvers.RecordCurrencyScan() or recorded;
		recorded = Resolvers.RecordPlayerMoneySnapshot() or recorded;
		recorded = Resolvers.RecordMailboxAuctionCriteria() or recorded;

		if Achievements.RefreshCriteriaAchievements then
			Achievements.RefreshCriteriaAchievements(false);
		end
		if Achievements.WatchFrame_Update then
			Achievements.WatchFrame_Update();
		end

		return recorded;
	end);

	if Achievements.EndSilentBackfill then
		Achievements.EndSilentBackfill();
	end
	Private.state.lastCurrentStateBackfillAt = Resolvers.GetNow();
	Private.state.currentStateBackfillRunning = nil;
	if not ok then
		error(recordedOrError);
	end
	return recordedOrError;
end

function Resolvers.RecordBarberShopCriteria()
	local recorded = Resolvers.RecordSimpleCriteria(CRITERIA_TYPE.GOT_HAIRCUT, "barber-shop");
	recorded = Resolvers.RecordMoneyCriteria(CRITERIA_TYPE.MONEY_SPENT_AT_BARBER, Resolvers.GetBarberShopCost(), "barber-money") or recorded;
	return recorded;
end

function Resolvers.HookSimpleActionCriteria()
	if Resolvers.simpleActionHooksInstalled then
		return Resolvers.simpleActionHooksInstalled;
	end

	Resolvers.simpleActionHooksInstalled = true;
	Resolvers.HookGlobalFunction("RollOnLoot", function(_, rollType)
		if rollType == 1 then
			Resolvers.RecordSimpleCriteria(CRITERIA_TYPE.ROLL_ANY_NEED, "roll-need");
		elseif rollType == 2 then
			Resolvers.RecordSimpleCriteria(CRITERIA_TYPE.ROLL_ANY_GREED, "roll-greed");
		elseif rollType == 3 then
			Resolvers.RecordSimpleCriteria(CRITERIA_TYPE.ROLL_ANY_DISENCHANT, "roll-disenchant");
		end
	end);
	Resolvers.HookGlobalFunction("AbandonQuest", function()
		Resolvers.RecordSimpleCriteria(CRITERIA_TYPE.ABANDON_ANY_QUEST, "abandon-quest");
	end);
	Resolvers.HookGlobalFunction("TakeTaxiNode", function(nodeID)
		Resolvers.RecordTaxiMoneySpent(nodeID);
		Resolvers.RecordSimpleCriteria(CRITERIA_TYPE.BUY_TAXI, "buy-taxi");
	end);
	Resolvers.HookGlobalFunction("SendMail", function()
		Resolvers.RecordPostageMoneySpent();
	end);
	Resolvers.HookGlobalFunction("ConfirmTalentWipe", function()
		Resolvers.RecordRespecCriteria();
	end);
	if StartAuction then
		Resolvers.HookGlobalFunction("StartAuction", function()
			Resolvers.RecordAuctionPosted();
		end);
	end
	Resolvers.HookGlobalFunction("PlaceAuctionBid", function(_, _, bidAmount)
		Resolvers.RecordAuctionBid(bidAmount);
	end);
	Resolvers.HookGlobalFunction("TakeInboxMoney", function(index)
		Resolvers.RecordMailboxAuctionCriteria(index);
	end);
	Resolvers.HookGlobalFunction("TakeInboxItem", function(index)
		Resolvers.RecordMailboxAuctionCriteria(index);
	end);
	Resolvers.HookGlobalFunction("ConfirmSummon", function()
		Resolvers.RecordSimpleCriteria(CRITERIA_TYPE.ACCEPT_SUMMON, "accept-summon");
	end);
	if BuyBankSlot then
		Resolvers.HookGlobalFunction("BuyBankSlot", function()
			Resolvers.RecordSimpleCriteria(CRITERIA_TYPE.BANK_SLOTS_PURCHASED, "bank-slot");
		end);
	end
	return true;
end

local criteriaAssetsByType;
local recentCombatCriteria = {};
local genericEmoteCriteriaByName;
local emoteHooksInstalled = false;
local recentEmotes = {};

local INCOMING_SPELL_EVENTS = {
	SPELL_AURA_APPLIED = true,
	SPELL_CAST_SUCCESS = true,
	SPELL_DAMAGE = true,
	SPELL_DRAIN = true,
	SPELL_ENERGIZE = true,
	SPELL_HEAL = true,
	SPELL_INSTAKILL = true,
	SPELL_LEECH = true,
	SPELL_RESURRECT = true,
};

local function GetCriteriaAssetsByType(criteriaType)
	if not criteriaAssetsByType then
		criteriaAssetsByType = {};
		for _, criteria in pairs(CRITERIA_DATA) do
			if Resolvers.IsClientRecordableCriteria(criteria) and not Resolvers.UsesPerCriteriaProgress(criteria) and criteria.asset and criteria.asset ~= 0 then
				criteriaAssetsByType[criteria.type] = criteriaAssetsByType[criteria.type] or {};
				criteriaAssetsByType[criteria.type][criteria.asset] = true;
			end
		end
	end

	return criteriaAssetsByType[criteriaType] or {};
end

local function SourceIsPlayerControlled(sourceGUID, sourceFlags)
	if sourceGUID and sourceGUID == UnitGUID("player") then
		return true;
	end

	return sourceFlags and HasFlag(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001);
end

local function SourceIsPlayerGroup(sourceGUID, sourceFlags)
	if SourceIsPlayerControlled(sourceGUID, sourceFlags) then
		return true;
	end

	return sourceFlags
		and (HasFlag(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002)
			or HasFlag(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004));
end

local function DestIsPlayer(destGUID, destFlags)
	if destGUID and destGUID == UnitGUID("player") then
		return true;
	end

	return destFlags and HasFlag(destFlags, COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001) and HasFlag(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400);
end

GetCreatureIDFromGUID = function(guid)
	if type(guid) ~= "string" then
		return nil;
	end

	local unitType, _, _, _, _, creatureID = strsplit("-", guid);
	if unitType == "Creature" or unitType == "Vehicle" then
		return tonumber(creatureID);
	end

	return nil;
end

-- Try to find a unit token whose UnitGUID matches `targetGUID`. Used to enrich
-- combat-log driven contexts with a live unit reference for things like
-- UnitIsMounted, UnitSex, UnitCreatureType, and aura scans. Returns nil when no
-- live token currently references the GUID.
Resolvers.englishCreatureTypeNameToID = Resolvers.englishCreatureTypeNameToID or {
	Beast = 1, Dragonkin = 2, Demon = 3, Elemental = 4, Giant = 5,
	Undead = 6, Humanoid = 7, Critter = 8, Mechanical = 9,
	["Not specified"] = 10, Totem = 11, ["Non-combat Pet"] = 12, ["Gas Cloud"] = 13,
};

Resolvers.creatureTypeGlobalNames = Resolvers.creatureTypeGlobalNames or {
	[1] = "CREATURE_TYPE_BEAST",
	[2] = "CREATURE_TYPE_DRAGONKIN",
	[3] = "CREATURE_TYPE_DEMON",
	[4] = "CREATURE_TYPE_ELEMENTAL",
	[5] = "CREATURE_TYPE_GIANT",
	[6] = "CREATURE_TYPE_UNDEAD",
	[7] = "CREATURE_TYPE_HUMANOID",
	[8] = "CREATURE_TYPE_CRITTER",
	[9] = "CREATURE_TYPE_MECHANICAL",
	[10] = "CREATURE_TYPE_NOT_SPECIFIED",
	[11] = "CREATURE_TYPE_TOTEM",
	[12] = "CREATURE_TYPE_NON_COMBAT_PET",
	[13] = "CREATURE_TYPE_GAS_CLOUD",
};

function Resolvers.GetCreatureTypeNameToID()
	if Resolvers.creatureTypeNameToID then
		return Resolvers.creatureTypeNameToID;
	end
	local lookup = {};
	for creatureTypeID, globalName in pairs(Resolvers.creatureTypeGlobalNames or {}) do
		local localizedName = rawget and rawget(_G, globalName) or nil;
		if type(localizedName) == "string" and localizedName ~= "" then
			lookup[localizedName] = creatureTypeID;
			lookup[Resolvers.LocaleLower(localizedName)] = creatureTypeID;
		end
	end
	if Resolvers.IsEnglishClientLocale() then
		for name, creatureTypeID in pairs(Resolvers.englishCreatureTypeNameToID or {}) do
			lookup[name] = creatureTypeID;
			lookup[Resolvers.LocaleLower(name)] = creatureTypeID;
		end
	end
	Resolvers.creatureTypeNameToID = lookup;
	return lookup;
end

function Resolvers.GetCreatureTypeIDFromName(name)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	local lookup = Resolvers.GetCreatureTypeNameToID();
	return lookup[name] or lookup[Resolvers.LocaleLower(name)];
end

local GetTargetRaceID;

local UNIT_TOKEN_CANDIDATES = {
	"target", "mouseover", "softenemy", "softfriend", "focus", "pet", "pettarget",
	"boss1", "boss2", "boss3", "boss4", "boss5",
};

function Resolvers.GetTargetFactCache()
	Private.state = Private.state or {};
	Private.state.targetFacts = Private.state.targetFacts or {};
	return Private.state.targetFacts;
end

function Resolvers.CacheTargetFacts(guid, unit, flags, creatureID)
	if not guid or guid == "" then
		return nil;
	end
	local cache = Resolvers.GetTargetFactCache();
	local facts = cache[guid] or {};
	facts.at = Resolvers.GetNow();
	facts.guid = guid;
	facts.flags = flags or facts.flags;
	facts.creatureID = creatureID or facts.creatureID;
	if flags and COMBATLOG_OBJECT_TYPE_PLAYER and HasFlag(flags, COMBATLOG_OBJECT_TYPE_PLAYER) then
		facts.isPlayer = true;
	end
	if flags and COMBATLOG_OBJECT_REACTION_HOSTILE then
		facts.isEnemy = HasFlag(flags, COMBATLOG_OBJECT_REACTION_HOSTILE);
	end

	if unit and UnitExists(unit) then
		facts.unit = unit;
		facts.isPlayer = UnitIsPlayer(unit) == true;
		facts.raceID = GetTargetRaceID(unit) or facts.raceID;
		facts.classID = Resolvers.GetTargetClassID(unit) or facts.classID;
		facts.sex = UnitSex(unit) or facts.sex;
		local level = UnitLevel(unit);
		if level and level > 0 then
			facts.level = level;
		end
		if UnitIsMounted then
			facts.isMounted = UnitIsMounted(unit) == true;
		end
		local creatureTypeName = UnitCreatureType(unit);
		facts.creatureTypeName = creatureTypeName or facts.creatureTypeName;
		facts.creatureTypeID = creatureTypeName and Resolvers.GetCreatureTypeIDFromName(creatureTypeName) or facts.creatureTypeID;
	end

	local creature = facts.creatureID and Resolvers.creatures and Resolvers.creatures[facts.creatureID] or nil;
	if creature then
		facts.creatureTypeID = creature.type or facts.creatureTypeID;
		facts.creatureClassification = creature.classification or facts.creatureClassification;
	end
	cache[guid] = facts;
	return facts;
end

function Resolvers.GetCachedTargetFacts(guid)
	if not guid or guid == "" then
		return nil;
	end
	local facts = Resolvers.GetTargetFactCache()[guid];
	if not facts then
		return nil;
	end
	if facts.at and (Resolvers.GetNow() - facts.at) > 60 then
		Resolvers.GetTargetFactCache()[guid] = nil;
		return nil;
	end
	return facts;
end

local function ResolveUnitTokenForGUID(targetGUID)
	if not targetGUID or targetGUID == "" then
		return nil;
	end
	for _, token in ipairs(UNIT_TOKEN_CANDIDATES) do
		if UnitExists(token) and UnitGUID(token) == targetGUID then
			return token;
		end
	end
	-- Nameplates: only present on Classic when the unit has a visible plate.
	for i = 1, 40 do
		local token = "nameplate" .. i;
		if UnitExists(token) and UnitGUID(token) == targetGUID then
			return token;
		end
	end
	-- Group target tokens (raid/party).
	if IsInRaid() then
		local n = GetNumGroupMembers();
		for i = 1, n do
			local token = "raid" .. i .. "target";
			if UnitExists(token) and UnitGUID(token) == targetGUID then
				return token;
			end
		end
	elseif IsInGroup() then
		local n = GetNumGroupMembers();
		for i = 1, n do
			local token = "party" .. i .. "target";
			if UnitExists(token) and UnitGUID(token) == targetGUID then
				return token;
			end
		end
	end
	return nil;
end

local function RecordCombatCriteriaAsset(criteriaType, assetID, amount, dedupeWindow)
	assetID = tonumber(assetID);
	if not assetID or assetID == 0 or not GetCriteriaAssetsByType(criteriaType)[assetID] then
		return false;
	end

	if dedupeWindow then
		local now = GetTime();
		local dedupeKey = criteriaType .. ":" .. assetID;
		if recentCombatCriteria[dedupeKey] and now - recentCombatCriteria[dedupeKey] < dedupeWindow then
			return false;
		end
		recentCombatCriteria[dedupeKey] = now;
	end

	Resolvers.IncrementCriteriaAssetProgress(criteriaType, assetID, amount or 1, nil, GetProgressCharacterName());
	return true;
end

-- ============================================================================
-- Modifier tree evaluator
-- ============================================================================
-- Modifier trees gate criteria progress on contextual conditions (target race,
-- map, source zone, item quality, etc.). Each node has an op (2=SingleTrue,
-- 3=SingleFalse, 4=All/AND, 8=Any/OR) and either children (composite) or a
-- type/asset/sec/ter triple (leaf condition).
-- See: https://wow.tools/dbc/?dbc=ModifierTree

local PLAYABLE_RACE_BIT = {
	[1] = 0x01,    -- Human
	[2] = 0x02,    -- Orc
	[3] = 0x04,    -- Dwarf
	[4] = 0x08,    -- Night Elf
	[5] = 0x10,    -- Undead
	[6] = 0x20,    -- Tauren
	[7] = 0x40,    -- Gnome
	[8] = 0x80,    -- Troll
	[9] = 0x100,   -- Goblin
	[10] = 0x200,  -- Blood Elf
	[11] = 0x400,  -- Draenei
};

local RACE_FILE_TO_ID = {
	Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Undead = 5,
	Tauren = 6, Gnome = 7, Troll = 8, Goblin = 9, BloodElf = 10, Draenei = 11,
};

Resolvers.classFileToID = Resolvers.classFileToID or {
	WARRIOR = 1,
	PALADIN = 2,
	HUNTER = 3,
	ROGUE = 4,
	PRIEST = 5,
	DEATHKNIGHT = 6,
	SHAMAN = 7,
	MAGE = 8,
	WARLOCK = 9,
	MONK = 10,
	DRUID = 11,
};

GetPlayerRaceID = function()
	local _, raceFile = UnitRace("player");
	return raceFile and RACE_FILE_TO_ID[raceFile] or nil;
end

GetTargetRaceID = function(unit)
	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then
		return nil;
	end
	local _, raceFile = UnitRace(unit);
	return raceFile and RACE_FILE_TO_ID[raceFile] or nil;
end

function Resolvers.GetTargetClassID(unit)
	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then
		return nil;
	end
	local _, classFile = UnitClass(unit);
	return classFile and Resolvers.classFileToID[classFile] or nil;
end

GetCurrentMapID = function()
	local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo();
	instanceMapID = tonumber(instanceMapID);
	if instanceMapID and instanceMapID ~= 0 then
		return instanceMapID;
	end
	return C_Map.GetBestMapForUnit("player");
end

GetCurrentZoneAreaID = function()
	return C_Map.GetBestMapForUnit("player");
end

function Resolvers.GetSourceClassID(ctx)
	if type(ctx) == "table" and ctx.sourceClassID then
		return ctx.sourceClassID;
	end
	local _, classFile = UnitClass("player");
	return classFile and Resolvers.classFileToID[classFile] or nil;
end

function Resolvers.GetCurrentInstanceDifficulty(ctx)
	if type(ctx) == "table" then
		local difficultyID = tonumber(ctx.difficultyID or ctx.mapDifficultyID);
		local maxPlayers = tonumber(ctx.maxPlayers or ctx.instanceMaxPlayers);
		if difficultyID or maxPlayers then
			return difficultyID, maxPlayers;
		end
	end
	local _, _, difficultyID, _, maxPlayers = GetInstanceInfo();
	return tonumber(difficultyID), tonumber(maxPlayers);
end

function Resolvers.GetCurrentGroupSize()
	local count = tonumber(GetNumGroupMembers()) or 0;
	if count > 0 then
		return count;
	end
	if IsInRaid() then
		return GetNumRaidMembers and (tonumber(GetNumRaidMembers()) or 0) or 40;
	end
	if IsInGroup() then
		return GetNumPartyMembers and ((tonumber(GetNumPartyMembers()) or 0) + 1) or 2;
	end
	return 1;
end

-- Leaf decoders. Each receives (ctx, asset, sec, ter, amount, treeID) and
-- returns boolean. Returning nil from an unknown decoder is treated as false
-- by EvaluateModifierTreeNode.
local MODIFIER_LEAF_DECODERS = {};
local MODIFIER_UNSUPPORTED = {};
Resolvers.modifierUnsupportedTypeLabels = Resolvers.modifierUnsupportedTypeLabels or {};
Resolvers.modifierUnsupportedTypeLabels[2] = "SOURCE_PLAYER_CONDITION";
Resolvers.modifierUnsupportedTypeLabels[67] = "WORLD_STATE_EXPRESSION";
Resolvers.modifierUnsupportedTypeLabels[289] = "TIME_EVENT_PASSED";
Resolvers.modifierAlwaysUnsupportedTypes = Resolvers.modifierAlwaysUnsupportedTypes or {};
Resolvers.modifierAlwaysUnsupportedTypes[289] = nil;
Resolvers.modifierPartiallyUnsupportedTypes = Resolvers.modifierPartiallyUnsupportedTypes or {};
Resolvers.modifierPartiallyUnsupportedTypes[2] = true;
Resolvers.modifierPartiallyUnsupportedTypes[67] = true;
Resolvers.modifierPartiallyUnsupportedTypes[289] = true;

Resolvers.worldStateExpressionLabels = Resolvers.worldStateExpressionLabels or {
	[1041] = "Alterac Valley mine Horde-owned (state 801 == 1)",
	[1043] = "Alterac Valley mine Alliance-owned (state 801 == 2)",
	[1057] = "Alterac Valley mine Alliance-owned (state 804 == 2)",
	[1058] = "Alterac Valley mine Horde-owned (state 804 == 1)",
	[1368] = "Feast of Winter Veil active",
	[1621] = "Alterac Valley tower A1 Alliance-owned",
	[1622] = "Alterac Valley tower A1 Horde-owned",
	[1625] = "Alterac Valley tower A2 Alliance-owned",
	[1626] = "Alterac Valley tower A2 Horde-owned",
	[1629] = "Alterac Valley tower A3 Alliance-owned",
	[1630] = "Alterac Valley tower A4 Alliance-owned",
	[1631] = "Alterac Valley tower A3 Horde-owned",
	[1632] = "Alterac Valley tower A4 Horde-owned",
	[1633] = "Alterac Valley tower H1 Alliance-owned",
	[1634] = "Alterac Valley tower H2 Alliance-owned",
	[1635] = "Alterac Valley tower H3 Alliance-owned",
	[1636] = "Alterac Valley tower H4 Alliance-owned",
	[1637] = "Alterac Valley tower H1 Horde-owned",
	[1638] = "Alterac Valley tower H2 Horde-owned",
	[1639] = "Alterac Valley tower H3 Horde-owned",
	[1640] = "Alterac Valley tower H4 Horde-owned",
	[2174] = "Children's Week active",
	[2303] = "Warsong Gulch Alliance flag at base while Horde flag carrier is in Silverwing flag room",
	[2304] = "Warsong Gulch Horde flag at base while Alliance flag carrier is in Warsong flag room",
	[4546] = "Brewfest active",
	[5715] = "Arathi Basin final score 1600-1590",
	[5716] = "Arathi Basin shutout",
	[5717] = "Arathi Basin all five bases controlled",
	[5718] = "Warsong Gulch shutout",
	[5719] = "Eye of the Storm four bases controlled",
	[5720] = "Eye of the Storm shutout",
	[5723] = "Alterac Valley Alliance captains survived",
	[5724] = "Alterac Valley Horde captains survived",
	[5809] = "Arathi Basin Alliance overcame 500-resource deficit",
	[5810] = "Arathi Basin Horde overcame 500-resource deficit",
};

function Resolvers.GetWorldStateExpressionLabel(asset)
	asset = tonumber(asset) or 0;
	return Resolvers.worldStateExpressionLabels and Resolvers.worldStateExpressionLabels[asset] or nil;
end

function Resolvers.IsKnownWorldStateExpressionAsset(asset)
	return Resolvers.GetWorldStateExpressionLabel and Resolvers.GetWorldStateExpressionLabel(asset) ~= nil;
end

function Resolvers.DebugUnsupportedModifier(ctx, nodeType, asset, treeID)
	local label = (Resolvers.modifierUnsupportedTypeLabels and Resolvers.modifierUnsupportedTypeLabels[nodeType]) or ("type " .. tostring(nodeType));
	local assetLabel = nodeType == 67 and Resolvers.GetWorldStateExpressionLabel and Resolvers.GetWorldStateExpressionLabel(asset) or nil;
	DebugDataInvariant("unsupported-modifier-leaf:" .. tostring(nodeType) .. ":" .. tostring(treeID or asset), "unsupported " .. label .. " modifier type " .. tostring(nodeType) .. " asset " .. tostring(asset or 0) .. (assetLabel and (" (" .. assetLabel .. ")") or "") .. " in tree " .. tostring(treeID or "?") .. FormatDebugContext(ctx));
	return MODIFIER_UNSUPPORTED;
end

function Resolvers.GetCurrentCalendarDate(ctx)
	if type(ctx) == "table" and ctx.month and (ctx.monthDay or ctx.day) then
		return tonumber(ctx.year), tonumber(ctx.month), tonumber(ctx.monthDay or ctx.day);
	end
	local ok, calendarTime = pcall(C_DateAndTime.GetCurrentCalendarTime);
	if ok and type(calendarTime) == "table" then
		local year = tonumber(calendarTime.year);
		local month = tonumber(calendarTime.month);
		local day = tonumber(calendarTime.monthDay or calendarTime.day);
		if year and month and day then
			return year, month, day;
		end
	end
	if CalendarGetDate then
		local ok, _, month, day, year = pcall(CalendarGetDate);
		if ok and month and day then
			return tonumber(year), tonumber(month), tonumber(day);
		end
	end
	local now = type(ctx) == "table" and tonumber(ctx.now) or nil;
	ok, calendarTime = pcall(date, "*t", now);
	if ok and type(calendarTime) == "table" then
		return tonumber(calendarTime.year), tonumber(calendarTime.month), tonumber(calendarTime.day);
	end
	ok, calendarTime = pcall(date, "*t");
	if ok and type(calendarTime) == "table" then
		return tonumber(calendarTime.year), tonumber(calendarTime.month), tonumber(calendarTime.day);
	end
	return nil, nil, nil;
end

Resolvers.holidayNamePatterns = Resolvers.holidayNamePatterns or {
	winterVeil = { "winter veil", "winterveil" },
	childrensWeek = { "children's week", "childrens week", "children" },
	brewfest = { "brewfest" },
};

Resolvers.holidayStableTextPatterns = Resolvers.holidayStableTextPatterns or {
	winterVeil = { "winterveil", "winter_veil", "winter-veil" },
	childrensWeek = { "childrensweek", "childrens_week", "childrenweek" },
	brewfest = { "brewfest" },
};

Resolvers.holidayDateRanges = Resolvers.holidayDateRanges or {
	winterVeil = { { 12, 15, 12, 31 }, { 1, 1, 1, 2 } },
	childrensWeek = { { 5, 1, 5, 7 } },
	brewfest = { { 9, 20, 10, 6 } },
};

function Resolvers.CalendarTextMatchesHolidayKey(text, holidayKey)
	if not Resolvers.IsEnglishClientLocale() then
		return false;
	end
	if type(text) ~= "string" then
		return false;
	end
	local lowerText = Resolvers.LocaleLower(text);
	local patterns = Resolvers.holidayNamePatterns and Resolvers.holidayNamePatterns[holidayKey];
	if not patterns then
		return false;
	end
	for _, pattern in ipairs(patterns) do
		if string.find(lowerText, pattern, 1, true) then
			return true;
		end
	end
	return false;
end

function Resolvers.CalendarStableTextMatchesHolidayKey(text, holidayKey)
	if type(text) ~= "string" then
		return false;
	end
	local lowerText = Resolvers.LocaleLower(text);
	local patterns = Resolvers.holidayStableTextPatterns and Resolvers.holidayStableTextPatterns[holidayKey];
	if not patterns then
		return false;
	end
	for _, pattern in ipairs(patterns) do
		if string.find(lowerText, pattern, 1, true) then
			return true;
		end
	end
	return false;
end

function Resolvers.CalendarRecordHasStableHolidayToken(record, holidayKey)
	if type(record) ~= "table" then
		return false;
	end
	for key, value in pairs(record) do
		if type(value) == "string" and Resolvers.CalendarStableTextMatchesHolidayKey(value, holidayKey) then
			local lowerKey = Resolvers.LocaleLower(key);
			if string.find(lowerKey, "texture", 1, true) or string.find(lowerKey, "icon", 1, true) or string.find(lowerKey, "atlas", 1, true) or string.find(lowerKey, "file", 1, true) then
				return true;
			end
		end
	end
	return false;
end

function Resolvers.DateMatchesHolidayRange(month, day, range)
	if type(range) ~= "table" then
		return false;
	end
	local startMonth, startDay, endMonth, endDay = range[1], range[2], range[3], range[4];
	if not startMonth or not startDay or not endMonth or not endDay then
		return false;
	end
	if startMonth <= endMonth then
		return (month > startMonth or (month == startMonth and day >= startDay)) and (month < endMonth or (month == endMonth and day <= endDay));
	end
	return (month > startMonth or (month == startMonth and day >= startDay)) or (month < endMonth or (month == endMonth and day <= endDay));
end

function Resolvers.DateLikelyMatchesHolidayKey(month, day, holidayKey)
	month = tonumber(month);
	day = tonumber(day);
	if not month or not day then
		return false;
	end
	local ranges = Resolvers.holidayDateRanges and Resolvers.holidayDateRanges[holidayKey];
	if type(ranges) ~= "table" then
		return false;
	end
	for _, range in ipairs(ranges) do
		if Resolvers.DateMatchesHolidayRange(month, day, range) then
			return true;
		end
	end
	return false;
end

function Resolvers.CalendarEventMatchesHolidayKey(event, holidayInfo, holidayKey)
	if type(event) ~= "table" then
		return false;
	end
	local calendarType = event.calendarType;
	if calendarType and calendarType ~= "HOLIDAY" and calendarType ~= "HOLIDAY_WEEKLY" and calendarType ~= "HOLIDAY_DARKMOON" and calendarType ~= "HOLIDAY_BATTLEGROUND" then
		return false;
	end
	if Resolvers.CalendarRecordHasStableHolidayToken(event, holidayKey) or Resolvers.CalendarRecordHasStableHolidayToken(holidayInfo, holidayKey) then
		return true;
	end
	if Resolvers.CalendarTextMatchesHolidayKey(event.title, holidayKey) then
		return true;
	end
	if type(holidayInfo) == "table" and (Resolvers.CalendarTextMatchesHolidayKey(holidayInfo.name, holidayKey) or Resolvers.CalendarTextMatchesHolidayKey(holidayInfo.description, holidayKey)) then
		return true;
	end
	return false;
end

function Resolvers.IsCalendarHolidayActive(ctx, holidayKey)
	local calendar = rawget and rawget(_G, "C_Calendar") or nil;
	if type(calendar) ~= "table" or type(calendar.GetNumDayEvents) ~= "function" or type(calendar.GetDayEvent) ~= "function" then
		return nil;
	end
	local _, month, day = Resolvers.GetCurrentCalendarDate(ctx);
	if not month or not day then
		return nil;
	end
	if type(calendar.OpenCalendar) == "function" and not (Private.state and Private.state.calendarOpenedForHolidayScan) then
		Private.state = Private.state or {};
		Private.state.calendarOpenedForHolidayScan = true;
		pcall(calendar.OpenCalendar);
	end
	if type(calendar.SetAbsMonth) == "function" then
		local year = select(1, Resolvers.GetCurrentCalendarDate(ctx));
		if year then
			pcall(calendar.SetAbsMonth, month, year);
		end
	end
	local ok, numEvents = pcall(calendar.GetNumDayEvents, 0, day);
	if not ok or type(numEvents) ~= "number" then
		return nil;
	end
	local sawHolidayOnLikelyDate = false;
	for eventIndex = 1, numEvents do
		local eventOK, event = pcall(calendar.GetDayEvent, 0, day, eventIndex);
		if eventOK and type(event) == "table" then
			local calendarType = event.calendarType;
			if Resolvers.DateLikelyMatchesHolidayKey(month, day, holidayKey) and (not calendarType or calendarType == "HOLIDAY" or calendarType == "HOLIDAY_WEEKLY" or calendarType == "HOLIDAY_DARKMOON" or calendarType == "HOLIDAY_BATTLEGROUND") then
				sawHolidayOnLikelyDate = true;
			end
			local holidayInfo;
			if type(calendar.GetHolidayInfo) == "function" then
				local holidayOK, info = pcall(calendar.GetHolidayInfo, 0, day, eventIndex);
				if holidayOK then
					holidayInfo = info;
				end
			end
			if Resolvers.CalendarEventMatchesHolidayKey(event, holidayInfo, holidayKey) then
				return true;
			end
		end
	end
	if sawHolidayOnLikelyDate then
		return true;
	end
	return false;
end

function Resolvers.IsKnownHolidayActive(ctx, holidayKey)
	if type(ctx) == "table" and type(ctx.holidayActive) == "table" and ctx.holidayActive[holidayKey] ~= nil then
		return ctx.holidayActive[holidayKey] == true;
	end
	local calendarResult = Resolvers.IsCalendarHolidayActive(ctx, holidayKey);
	if calendarResult ~= nil then
		return calendarResult;
	end
	return nil;
end

function Resolvers.GetWorldStateValue(ctx, worldStateID)
	worldStateID = tonumber(worldStateID) or 0;
	if worldStateID == 0 then
		return nil;
	end
	if type(ctx) == "table" then
		local values = ctx.worldStates or ctx.worldStateValues;
		if type(values) == "table" and values[worldStateID] ~= nil then
			return tonumber(values[worldStateID]);
		end
	end
	local getter = rawget and rawget(_G, "GetWorldState") or nil;
	if type(getter) == "function" then
		local ok, value = pcall(getter, worldStateID);
		if ok and value ~= nil then
			return tonumber(value);
		end
	end
	local worldStateInfo = rawget and rawget(_G, "C_WorldStateInfo") or nil;
	if type(worldStateInfo) == "table" and type(worldStateInfo.GetState) == "function" then
		local ok, value = pcall(worldStateInfo.GetState, worldStateID);
		if ok and value ~= nil then
			return tonumber(value);
		end
	end
	local mapValues = Resolvers.GetWorldStateMapCache(ctx, "worldStateValuesByMap");
	if type(mapValues) == "table" and mapValues[worldStateID] ~= nil then
		return tonumber(mapValues[worldStateID]);
	end
	if Private.state and type(Private.state.worldStateValues) == "table" and Private.state.worldStateValues[worldStateID] ~= nil then
		return tonumber(Private.state.worldStateValues[worldStateID]);
	end
	return nil;
end

function Resolvers.CompareWorldStateValue(ctx, worldStateID, operator, expected)
	local value = Resolvers.GetWorldStateValue(ctx, worldStateID);
	if value == nil then
		return nil;
	end
	expected = tonumber(expected) or 0;
	if operator == "eq" then
		return value == expected;
	elseif operator == "gt" then
		return value > expected;
	elseif operator == "ge" then
		return value >= expected;
	end
	return nil;
end

function Resolvers.ExprAnd(left, right)
	if left == false or right == false then
		return false;
	end
	if left == true and right == true then
		return true;
	end
	return nil;
end

function Resolvers.ExprOr(left, right)
	if left == true or right == true then
		return true;
	end
	if left == false and right == false then
		return false;
	end
	return nil;
end

function Resolvers.EvaluateKnownWorldStateExpression(ctx, asset)
	asset = tonumber(asset) or 0;
	if type(ctx) == "table" and type(ctx.worldStateExpressions) == "table" and ctx.worldStateExpressions[asset] ~= nil then
		return ctx.worldStateExpressions[asset] == true;
	end
	local mapExpressions = Resolvers.GetWorldStateMapCache(ctx, "worldStateExpressionsByMap");
	if type(mapExpressions) == "table" and mapExpressions[asset] == true then
		return true;
	end

	if asset == 1368 then return Resolvers.IsKnownHolidayActive(ctx, "winterVeil"); end
	if asset == 2174 then return Resolvers.IsKnownHolidayActive(ctx, "childrensWeek"); end
	if asset == 4546 then return Resolvers.IsKnownHolidayActive(ctx, "brewfest"); end

	if asset == 1041 then return Resolvers.CompareWorldStateValue(ctx, 801, "eq", 1); end
	if asset == 1043 then return Resolvers.CompareWorldStateValue(ctx, 801, "eq", 2); end
	if asset == 1057 then return Resolvers.CompareWorldStateValue(ctx, 804, "eq", 2); end
	if asset == 1058 then return Resolvers.CompareWorldStateValue(ctx, 804, "eq", 1); end
	if asset == 1621 then return Resolvers.CompareWorldStateValue(ctx, 1181, "eq", 1); end
	if asset == 1622 then return Resolvers.CompareWorldStateValue(ctx, 1181, "eq", 2); end
	if asset == 1625 then return Resolvers.CompareWorldStateValue(ctx, 1182, "eq", 1); end
	if asset == 1626 then return Resolvers.CompareWorldStateValue(ctx, 1182, "eq", 2); end
	if asset == 1629 then return Resolvers.CompareWorldStateValue(ctx, 1183, "eq", 1); end
	if asset == 1630 then return Resolvers.CompareWorldStateValue(ctx, 1184, "eq", 1); end
	if asset == 1631 then return Resolvers.CompareWorldStateValue(ctx, 1183, "eq", 2); end
	if asset == 1632 then return Resolvers.CompareWorldStateValue(ctx, 1184, "eq", 2); end
	if asset == 1633 then return Resolvers.CompareWorldStateValue(ctx, 1185, "eq", 1); end
	if asset == 1634 then return Resolvers.CompareWorldStateValue(ctx, 1186, "eq", 1); end
	if asset == 1635 then return Resolvers.CompareWorldStateValue(ctx, 1187, "eq", 1); end
	if asset == 1636 then return Resolvers.CompareWorldStateValue(ctx, 1188, "eq", 1); end
	if asset == 1637 then return Resolvers.CompareWorldStateValue(ctx, 1185, "eq", 2); end
	if asset == 1638 then return Resolvers.CompareWorldStateValue(ctx, 1186, "eq", 2); end
	if asset == 1639 then return Resolvers.CompareWorldStateValue(ctx, 1187, "eq", 2); end
	if asset == 1640 then return Resolvers.CompareWorldStateValue(ctx, 1188, "eq", 2); end

	if asset == 2303 then
		local result = Resolvers.ExprAnd(Resolvers.CompareWorldStateValue(ctx, 1545, "eq", 1), Resolvers.CompareWorldStateValue(ctx, 1664, "gt", 0));
		return result ~= nil and result or Resolvers.IsWarsongFlagAtBase(ctx, "Alliance");
	elseif asset == 2304 then
		local result = Resolvers.ExprAnd(Resolvers.CompareWorldStateValue(ctx, 1546, "eq", 1), Resolvers.CompareWorldStateValue(ctx, 1664, "gt", 0));
		return result ~= nil and result or Resolvers.IsWarsongFlagAtBase(ctx, "Horde");
	end

	if asset == 5715 then return Resolvers.ExprOr(Resolvers.CompareWorldStateValue(ctx, 1776, "eq", 1590), Resolvers.CompareWorldStateValue(ctx, 1777, "eq", 1590)); end
	if asset == 5716 then return Resolvers.ExprOr(Resolvers.CompareWorldStateValue(ctx, 1776, "eq", 0), Resolvers.CompareWorldStateValue(ctx, 1777, "eq", 0)); end
	if asset == 5717 then return Resolvers.ExprOr(Resolvers.CompareWorldStateValue(ctx, 1779, "eq", 5), Resolvers.CompareWorldStateValue(ctx, 1778, "eq", 5)); end
	if asset == 5718 then
		local hordeCaptures = Resolvers.GetWorldStateValue(ctx, 1581);
		local allianceCaptures = Resolvers.GetWorldStateValue(ctx, 1582);
		if hordeCaptures == nil or allianceCaptures == nil then return nil; end
		return (hordeCaptures - allianceCaptures == 3) or (allianceCaptures - hordeCaptures == 3);
	end
	if asset == 5719 then return Resolvers.ExprOr(Resolvers.CompareWorldStateValue(ctx, 2752, "eq", 4), Resolvers.CompareWorldStateValue(ctx, 2753, "eq", 4)); end
	if asset == 5720 then return Resolvers.ExprOr(Resolvers.CompareWorldStateValue(ctx, 2749, "eq", 0), Resolvers.CompareWorldStateValue(ctx, 2750, "eq", 0)); end
	if asset == 5723 then return Resolvers.ExprAnd(Resolvers.CompareWorldStateValue(ctx, 1351, "ge", 0), Resolvers.CompareWorldStateValue(ctx, 602, "ge", 0)); end
	if asset == 5724 then return Resolvers.ExprAnd(Resolvers.CompareWorldStateValue(ctx, 1352, "ge", 0), Resolvers.CompareWorldStateValue(ctx, 601, "ge", 0)); end
	if asset == 5809 then return Resolvers.CompareWorldStateValue(ctx, 3645, "eq", 1); end
	if asset == 5810 then return Resolvers.CompareWorldStateValue(ctx, 3644, "eq", 1); end

	return nil;
end

function Resolvers.GetPlayerFactionName(ctx)
	if type(ctx) == "table" and ctx.sourceFaction then
		return ctx.sourceFaction;
	end
	return UnitFactionGroup("player");
end

function Resolvers.PlayerHasTitle(titleID)
	titleID = tonumber(titleID) or 0;
	if titleID == 0 then return false; end
	local ok, known = pcall(IsTitleKnown, titleID);
	if ok and known then return true; end
	local currentTitle = GetCurrentTitle();
	return tonumber(currentTitle) == titleID;
end

function Resolvers.GetLFGDungeonFinderCategory()
	return tonumber(LE_LFG_CATEGORY_LFD) or 1;
end

function Resolvers.GetLFGDungeonFinderMode()
	local ok, mode = pcall(GetLFGMode, Resolvers.GetLFGDungeonFinderCategory());
	if ok then
		return mode;
	end

	ok, mode = pcall(GetLFGMode);
	return ok and mode or nil;
end

function Resolvers.IsRandomLFGDungeonID(lfgDungeonID)
	lfgDungeonID = tonumber(lfgDungeonID) or 0;
	if lfgDungeonID == 0 then
		return false;
	end

	local ok, _, typeID = pcall(GetLFGDungeonInfo, lfgDungeonID);
	return ok and tonumber(typeID) == 6;
end

function Resolvers.IsQueuedForRandomLFGDungeon()
	local results = { pcall(GetLFGQueueStats, Resolvers.GetLFGDungeonFinderCategory()) };
	if not results[1] or not results[2] then
		return false;
	end

	return Resolvers.IsRandomLFGDungeonID(results[19]);
end

function Resolvers.GetCurrentLFGProposalIsRandom()
	local ok, proposalExists, _, typeID = pcall(GetLFGProposal);
	if not ok or not proposalExists then
		return nil;
	end
	return tonumber(typeID) == 6;
end

function Resolvers.RecordLFGState(event)
	local proposalIsRandom = Resolvers.GetCurrentLFGProposalIsRandom();
	if proposalIsRandom ~= nil then
		Private.lfgLastProposalIsRandom = proposalIsRandom;
		if proposalIsRandom then
			Private.lfgQueuedForRandomDungeon = true;
		end
	elseif event == "LFG_PROPOSAL_FAILED" then
		Private.lfgLastProposalIsRandom = false;
	end

	local queuedForRandom = Resolvers.IsQueuedForRandomLFGDungeon();
	if queuedForRandom then
		Private.lfgQueuedForRandomDungeon = true;
	end

	local mode = Resolvers.GetLFGDungeonFinderMode();
	if mode == "lfgparty" then
		if queuedForRandom or Private.lfgQueuedForRandomDungeon == true or Private.lfgLastProposalIsRandom == true then
			Private.lfgCurrentDungeonIsRandom = true;
		end
	elseif mode == nil then
		Private.lfgCurrentDungeonIsRandom = false;
		Private.lfgQueuedForRandomDungeon = false;
		Private.lfgLastProposalIsRandom = false;
	elseif mode ~= "proposal" and mode ~= "accepted" and mode ~= "queued" and mode ~= "rolecheck" and mode ~= "suspended" then
		Private.lfgCurrentDungeonIsRandom = false;
	end

	return mode == "lfgparty" and Private.lfgCurrentDungeonIsRandom == true;
end

function Resolvers.IsInRandomLFGDungeon(ctx)
	if type(ctx) == "table" and ctx.inRandomLFG ~= nil then
		return ctx.inRandomLFG == true;
	end
	return Resolvers.RecordLFGState() == true;
end

-- 1: SOURCE_DRUNK_VALUE >= asset
MODIFIER_LEAF_DECODERS[1] = function(ctx, asset)
	local drunk = GetInebriateLevel and GetInebriateLevel("player") or 0;
	return (drunk or 0) >= (asset or 0);
end;

-- 2: SOURCE_PLAYER_CONDITION. Only the Classic/TBC-generated source
-- conditions with known client-observable meaning are evaluated here.
MODIFIER_LEAF_DECODERS[2] = function(ctx, asset, _, _, _, treeID)
	asset = tonumber(asset) or 0;
	if asset == 923 then
		return Resolvers.GetPlayerFactionName(ctx) == "Horde";
	elseif asset == 924 then
		return Resolvers.GetPlayerFactionName(ctx) == "Alliance";
	elseif asset == 6686 then
		return Resolvers.PlayerHasTitle(36);
	end
	return Resolvers.DebugUnsupportedModifier(ctx, 2, asset, treeID);
end;

-- 3: ITEM_LEVEL >= asset
MODIFIER_LEAF_DECODERS[3] = function(ctx, asset)
	if not ctx.itemLevel then return false; end
	return ctx.itemLevel >= (asset or 0);
end;

-- 4: TARGET_CREATURE_ENTRY == asset
MODIFIER_LEAF_DECODERS[4] = function(ctx, asset)
	if not ctx.creatureID then return false; end
	return ctx.creatureID == asset;
end;

-- 5: TARGET_MUST_BE_PLAYER
MODIFIER_LEAF_DECODERS[5] = function(ctx)
	if ctx.destFlags and COMBATLOG_OBJECT_TYPE_PLAYER then
		return HasFlag(ctx.destFlags, COMBATLOG_OBJECT_TYPE_PLAYER);
	end
	return ctx.targetIsPlayer == true;
end;

-- 6: TARGET_MUST_BE_DEAD (post-PARTY_KILL is always satisfied)
MODIFIER_LEAF_DECODERS[6] = function(ctx)
	return ctx.targetIsDead ~= false;
end;

-- 7: TARGET_MUST_BE_ENEMY
MODIFIER_LEAF_DECODERS[7] = function(ctx)
	if ctx.destFlags and COMBATLOG_OBJECT_REACTION_HOSTILE then
		return HasFlag(ctx.destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE);
	end
	return ctx.targetIsEnemy ~= false;
end;

-- 8: SOURCE_HAS_AURA spellID=asset on player
MODIFIER_LEAF_DECODERS[8] = function(_, asset)
	if not asset or asset == 0 then return true; end
	if AuraUtil and AuraUtil.FindAuraBySpellID then
		return AuraUtil.FindAuraBySpellID(asset, "player") ~= nil;
	end
	return false;
end;

-- 10: TARGET_HAS_AURA spellID=asset on resolved target unit
MODIFIER_LEAF_DECODERS[10] = function(ctx, asset)
	if not asset or asset == 0 then return true; end
	if not ctx.targetUnit then return false; end
	if AuraUtil and AuraUtil.FindAuraBySpellID then
		return AuraUtil.FindAuraBySpellID(asset, ctx.targetUnit) ~= nil;
	end
	return false;
end;

-- 11: TARGET_HAS_AURA_TYPE asset = SpellAuraType (78 = SPELL_AURA_MOUNTED)
-- Used by ach 223 Sickly Gazelle (mounted enemy player).
MODIFIER_LEAF_DECODERS[11] = function(ctx, asset)
	if asset == 78 then
		if ctx.targetIsMounted ~= nil then
			return ctx.targetIsMounted == true;
		end
		if ctx.targetUnit and UnitIsMounted then
			return UnitIsMounted(ctx.targetUnit) and true or false;
		end
		return false;
	end
	return false;
end;

-- 14: ITEM_QUALITY_MIN >= asset
MODIFIER_LEAF_DECODERS[14] = function(ctx, asset)
	if not ctx.itemQuality then return false; end
	return ctx.itemQuality >= (asset or 0);
end;

-- 15: ITEM_QUALITY == asset.
MODIFIER_LEAF_DECODERS[15] = function(ctx, asset)
	if not ctx.itemQuality then return false; end
	return ctx.itemQuality == asset;
end;

-- 16: SOURCE_IS_ALIVE.
MODIFIER_LEAF_DECODERS[16] = function(ctx)
	if type(ctx) == "table" and ctx.sourceIsAlive ~= nil then
		return ctx.sourceIsAlive == true;
	end
	return UnitIsDeadOrGhost("player") ~= true;
end;

-- 17: SOURCE_AREA_OR_ZONE matches asset (player current zone)
MODIFIER_LEAF_DECODERS[17] = function(ctx, asset)
	local zone = ctx.zoneAreaID or GetCurrentZoneAreaID();
	if not zone then return true; end
	return zone == asset;
end;

-- 18: TARGET_AREA_OR_ZONE matches asset (assume same zone for combat events)
MODIFIER_LEAF_DECODERS[18] = MODIFIER_LEAF_DECODERS[17];

-- 20: MAP_DIFFICULTY_OLD. In Wrath-era rows this is the old raid-size
-- gate: 0 = 10-player, 1 = 25-player.
MODIFIER_LEAF_DECODERS[20] = function(ctx, asset)
	local expected = tonumber(asset) or 0;
	if type(ctx) == "table" and ctx.oldMapDifficulty ~= nil then
		return tonumber(ctx.oldMapDifficulty) == expected;
	end
	local _, maxPlayers = Resolvers.GetCurrentInstanceDifficulty(ctx);
	if not maxPlayers or maxPlayers == 0 then
		return false;
	end
	if expected == 0 then
		return maxPlayers <= 10;
	elseif expected == 1 then
		return maxPlayers >= 25;
	end
	return false;
end;

-- 21: TARGET_CREATURE_YIELDS_XP - approximated as level-delta gate
-- (ModifierTreeType.PlayerToTargetLevelDeltaGT, asset = max delta).
-- Used by exactly one row (ach 5299 / TBC) with asset 7. If the killed unit
-- is more than `asset` levels below the player it yields no XP/honor.
MODIFIER_LEAF_DECODERS[21] = function(ctx, asset)
	if ctx.targetLevel then
		local plvl = UnitLevel("player") or 0;
		return (plvl - ctx.targetLevel) > (asset or 0);
	end
	if not ctx.targetUnit then return false; end
	local plvl = UnitLevel("player") or 0;
	local tlvl = UnitLevel(ctx.targetUnit) or 0;
	if tlvl <= 0 then return false; end -- unknown -> deny (safer than unlock)
	return (plvl - tlvl) > (asset or 0);
end;

-- 24: ARENA_TYPE / PlayerInArenaWithTeamSize. asset = team size (2/3/5).
-- Checks the active arena bracket against the modifier's expected team size.
MODIFIER_LEAF_DECODERS[24] = function(_, asset)
	if _.arenaTeamSize then return _.arenaTeamSize == asset; end
	local _, isArena = IsActiveBattlefieldArena();
	if not isArena then return false; end
	for i = 1, GetMaxBattlefieldID() do
		local status, _, _, _, _, teamSize = GetBattlefieldStatus(i);
		if status == "active" and teamSize == asset then
			return true;
		end
	end
	return false;
end;

-- 25: SOURCE_RACE: bitmask asset & (1<<(raceID-1)) ~= 0
MODIFIER_LEAF_DECODERS[25] = function(ctx, asset)
	local raceID = ctx.sourceRaceID or GetPlayerRaceID();
	if not raceID or not asset then return false; end
	local bit = PLAYABLE_RACE_BIT[raceID];
	if not bit then return false; end
	return (asset % (bit * 2)) >= bit;
end;

-- 26: SOURCE_CLASS == asset.
MODIFIER_LEAF_DECODERS[26] = function(ctx, asset)
	local classID = Resolvers.GetSourceClassID(ctx);
	return classID ~= nil and classID == asset;
end;

-- 27: TARGET_RACE: bitmask
MODIFIER_LEAF_DECODERS[27] = function(ctx, asset)
	local raceID = ctx.targetRaceID;
	if not raceID and ctx.targetUnit then
		raceID = GetTargetRaceID(ctx.targetUnit);
	end
	if not raceID or not asset then
		-- Unknown target race; permissive only when target is player.
		return ctx.targetIsPlayer == true;
	end
	local bit = PLAYABLE_RACE_BIT[raceID];
	if not bit then return false; end
	return (asset % (bit * 2)) >= bit;
end;

-- 28: TARGET_CLASS == asset.
MODIFIER_LEAF_DECODERS[28] = function(ctx, asset)
	local classID = ctx and ctx.targetClassID or nil;
	if not classID and ctx and ctx.targetUnit then
		classID = Resolvers.GetTargetClassID(ctx.targetUnit);
	end
	return classID ~= nil and classID == asset;
end;

-- 29: MAX_GROUP_MEMBERS. Used by raid-size challenge criteria as a strict
-- "fewer than asset players" check (e.g. asset 9 means 8 or fewer).
MODIFIER_LEAF_DECODERS[29] = function(ctx, asset)
	local groupSize = ctx and tonumber(ctx.groupSize or ctx.groupMembers) or nil;
	if not groupSize then
		groupSize = Resolvers.GetCurrentGroupSize();
	end
	return groupSize < (tonumber(asset) or 0);
end;

-- 30: TARGET_CREATURE_TYPE asset = CreatureType id. Prefer generated creature
-- metadata from the combat-log creature ID; fall back to localized
-- UnitCreatureType only when the unit token is still resolvable.
MODIFIER_LEAF_DECODERS[30] = function(ctx, asset)
	if ctx.creatureTypeID then
		return ctx.creatureTypeID == asset;
	end
	if ctx.creatureID and Resolvers.creatures and Resolvers.creatures[ctx.creatureID] then
		return Resolvers.creatures[ctx.creatureID].type == asset;
	end
	if not ctx.targetUnit or not UnitCreatureType then return false; end
	local name = UnitCreatureType(ctx.targetUnit);
	local id = name and Resolvers.GetCreatureTypeIDFromName(name);
	if not id then return false; end
	return id == asset;
end;

-- 32: SOURCE_MAP == asset
MODIFIER_LEAF_DECODERS[32] = function(ctx, asset)
	local mapID = ctx.mapID or GetCurrentMapID();
	if not mapID then return false; end
	return mapID == asset;
end;

-- 34: ITEM_SUBCLASS in the loot-stat row for achievement 1518
-- (Fish caught). Modern enum tables label this numeric slot as battle-pet
-- team level, but the 3.4.5 data uses it to filter fishing loot to subclass 8
-- (Cooking) items.
MODIFIER_LEAF_DECODERS[34] = function(ctx, asset)
	local expectedSubclass = tonumber(asset) or 0;
	if expectedSubclass == 0 then
		return false;
	end

	local itemSubclass = type(ctx) == "table" and tonumber(ctx.itemSubclass or ctx.itemSubClass) or nil;
	if not itemSubclass and type(ctx) == "table" and ctx.itemID then
		local itemRecord = ITEM_DATA[ctx.itemID];
		itemSubclass = itemRecord and tonumber(itemRecord.subclass) or nil;
	end
	return itemSubclass ~= nil and itemSubclass == expectedSubclass;
end;

-- 35: NOT_IN_GROUP.
MODIFIER_LEAF_DECODERS[35] = function(ctx)
	if type(ctx) == "table" and ctx.inGroup ~= nil then
		return ctx.inGroup ~= true;
	end
	return Resolvers.GetCurrentGroupSize() <= 1;
end;

-- 41: SOURCE_ZONE == asset
MODIFIER_LEAF_DECODERS[41] = function(ctx, asset)
	local zone = ctx.zoneAreaID or GetCurrentZoneAreaID();
	if not zone then return false; end
	return zone == asset;
end;

-- 46: TARGET_HEALTH_PCT_LOWER. At PARTY_KILL the target HP is 0 so
-- threshold checks (asset 5 -> health <= 5%) are trivially satisfied. For
-- contexts that pre-fill ctx.targetHealthPct (e.g. spell-cast events) we
-- compare against the live percentage.
MODIFIER_LEAF_DECODERS[46] = function(ctx, asset)
	if ctx.targetHealthPct ~= nil then
		return ctx.targetHealthPct <= (asset or 0);
	end
	return true;
end;

-- 55: TARGET_PLAYER_CONDITION asset = PlayerCondition.dbc id. We support the
-- conditions actually referenced by gated achievements:
--   8128 = "is female player" (ach 2422 Shake Your Bunny-Maker, Spring
--          Flowers transforms only female targets).
MODIFIER_LEAF_DECODERS[55] = function(ctx, asset)
	if asset == 8128 then
		if ctx.targetSex then
			return ctx.targetIsPlayer == true and ctx.targetSex == 3;
		end
		if not ctx.targetUnit or not UnitIsPlayer(ctx.targetUnit) then
			return false;
		end
		return UnitSex(ctx.targetUnit) == 3;
	end
	return false;
end;

-- 56: PLAYER_ACHIEVEMENT_POINTS >= asset.
MODIFIER_LEAF_DECODERS[56] = function(_, asset)
	if not Achievements.GetTotalAchievementPoints then return false; end
	return (Achievements.GetTotalAchievementPoints() or 0) >= (asset or 0);
end;

-- 58: IN_LFG_RANDOM_DUNGEON. The live client exposes random proposals and
-- queue IDs, but not a reliable retroactive proof after reload inside an
-- instance, so this tracks from queue/proposal events and otherwise fails
-- closed.
MODIFIER_LEAF_DECODERS[58] = function(ctx)
	return Resolvers.IsInRandomLFGDungeon(ctx);
end;

-- 67: WORLD_STATE_EXPRESSION. Only the expression IDs used by generated
-- Classic/TBC criteria are decoded here. Scoreboard/ownership expressions
-- fail closed when no live world-state source proves them true.
MODIFIER_LEAF_DECODERS[67] = function(ctx, asset, _, _, _, treeID)
	local result = Resolvers.EvaluateKnownWorldStateExpression(ctx, asset);
	if result ~= nil then
		return result;
	end
	if Resolvers.IsKnownWorldStateExpressionAsset and Resolvers.IsKnownWorldStateExpressionAsset(asset) then
		return false;
	end
	return Resolvers.DebugUnsupportedModifier(ctx, 67, asset, treeID);
end;

-- 68: MAP_DIFFICULTY == asset.
MODIFIER_LEAF_DECODERS[68] = function(ctx, asset)
	local difficultyID = Resolvers.GetCurrentInstanceDifficulty(ctx);
	return difficultyID ~= nil and difficultyID == asset;
end;

-- 87: HAS_ACHIEVEMENT_ON_CHARACTER. Used by aggregate seasonal title rows.
MODIFIER_LEAF_DECODERS[87] = function(_, asset)
	asset = tonumber(asset) or 0;
	if asset == 0 then
		return false;
	end
	if Resolvers.ResolveSpecialAchievementState then
		local completed = Resolvers.ResolveSpecialAchievementState(asset);
		if completed ~= nil then
			return completed == true;
		end
	end
	if Private.IsAchievementCompleted and Private.IsAchievementCompleted(asset) == true then
		return true;
	end

	local achievement = ACHIEVEMENT_DATA[asset];
	local titleID = achievement and tonumber(achievement.titleReward);
	return titleID ~= nil and Resolvers.PlayerHasTitle(titleID) == true;
end;

-- 109: TIME_IN_RANGE. Asset/sec are Unix timestamps.
MODIFIER_LEAF_DECODERS[109] = function(ctx, asset, sec)
	local now = type(ctx) == "table" and tonumber(ctx.now) or nil;
	if not now and time then
		now = time();
	end
	asset = tonumber(asset) or 0;
	sec = tonumber(sec) or 0;
	return now ~= nil and asset > 0 and sec > 0 and now >= asset and now <= sec;
end;

-- 289: TIME_EVENT_PASSED. Classic-era clients do not expose generic TimeEvent
-- data, but generated Classic/TBC rows only use known arena-season boundaries.
MODIFIER_LEAF_DECODERS[289] = function(ctx, asset, _, _, _, treeID)
	local result = Resolvers.EvaluateKnownTimeEventPassed(ctx, asset);
	if result ~= nil then
		return result;
	end
	return Resolvers.DebugUnsupportedModifier(ctx, 289, asset, treeID);
end;

local MODIFIER_OP = {
	SINGLE_TRUE = 2,
	SINGLE_FALSE = 3,	
	ALL = 4,
	ANY = 8,
};

local function EvaluateChildren(treeID, ctx, mode)
	local children = MODIFIER_TREE_CHILDREN[treeID];
	if not children or #children == 0 then
		return mode ~= "any"; -- empty AND = true, empty OR = false
	end
	if mode == "any" then
		for _, childID in ipairs(children) do
			if EvaluateModifierTreeNode(childID, ctx) then
				return true;
			end
		end
		return false;
	end
	-- default: AND
	for _, childID in ipairs(children) do
		if not EvaluateModifierTreeNode(childID, ctx) then
			return false;
		end
	end
	return true;
end

EvaluateModifierTreeNode = function(treeID, ctx)
	local node = MODIFIER_TREE_DATA[treeID];
	if not node then
		DebugDataInvariant("missing-modifier-tree:" .. tostring(treeID), "missing modifier tree node " .. tostring(treeID) .. FormatDebugContext(ctx));
		return false;
	end

	local nodeType = node.type;
	if nodeType and nodeType ~= 0 then
		local decoder = MODIFIER_LEAF_DECODERS[nodeType];
		if not decoder then
			DebugDataInvariant("unknown-modifier-leaf:" .. tostring(nodeType) .. ":" .. tostring(treeID), "unknown modifier leaf type " .. tostring(nodeType) .. " in tree " .. tostring(treeID) .. FormatDebugContext(ctx));
			return false; -- unknown leaf condition -> deny (safer than spurious unlock)
		end
		local ok = decoder(ctx or {}, node.asset, node.sec, node.ter, node.amount, treeID);
		if ok == MODIFIER_UNSUPPORTED then
			return false;
		end
		if node.op == MODIFIER_OP.SINGLE_FALSE then
			return not ok;
		end
		return ok and true or false;
	end

	local op = node.op or MODIFIER_OP.ALL;
	if op == MODIFIER_OP.ANY then
		return EvaluateChildren(treeID, ctx, "any");
	elseif op == MODIFIER_OP.SINGLE_FALSE then
		return not EvaluateChildren(treeID, ctx, "all");
	end
	-- SINGLE_TRUE (single child) and ALL collapse to AND
	return EvaluateChildren(treeID, ctx, "all");
end;

EvaluateCriteriaModifier = function(criteria, ctx)
	if not criteria or not criteria.modifierTree or criteria.modifierTree == 0 then
		return true;
	end
	local modifierCtx = ctx or {};
	if type(modifierCtx) == "table" then
		local originalCtx = modifierCtx;
		modifierCtx = {};
		for key, value in pairs(originalCtx) do
			modifierCtx[key] = value;
		end
		modifierCtx.achievementID = modifierCtx.achievementID or ACHIEVEMENT_BY_CRITERIA[criteria.id];
		modifierCtx.criteriaID = criteria.id;
		modifierCtx.criteriaType = criteria.type;
		modifierCtx.assetID = criteria.asset;
	end
	return EvaluateModifierTreeNode(criteria.modifierTree, modifierCtx);
end

if Private.IsDebugBuild and Private.IsDebugBuild() then
local function GetAchievementCriteriaRootID(achievement)
	if not achievement then
		return nil;
	end
	if achievement.criteriaTree and achievement.criteriaTree ~= 0 then
		return achievement.criteriaTree;
	end
	local sharedAchievement = achievement.sharesCriteria and ACHIEVEMENT_DATA[achievement.sharesCriteria];
	if sharedAchievement and sharedAchievement.criteriaTree and sharedAchievement.criteriaTree ~= 0 then
		return sharedAchievement.criteriaTree;
	end
	return nil;
end

local function IncrementDebugScanCounter(report, key)
	report[key] = (report[key] or 0) + 1;
end

local function MarkDebugScanSeen(report, seenKey, value, countKey)
	if not value then
		return false;
	end
	report[seenKey] = report[seenKey] or {};
	if report[seenKey][value] then
		return false;
	end
	report[seenKey][value] = true;
	IncrementDebugScanCounter(report, countKey);
	return true;
end

local function DebugScanModifierTree(treeID, ctx, report, visiting)
	treeID = tonumber(treeID) or 0;
	if treeID == 0 then
		return;
	end

	visiting = visiting or {};
	if visiting[treeID] then
		IncrementDebugScanCounter(report, "modifierTreeCycles");
		DebugDataInvariant("modifier-tree-cycle:" .. tostring(treeID), "modifier tree cycle at node " .. tostring(treeID) .. FormatDebugContext(ctx));
		return;
	end
	visiting[treeID] = true;
	MarkDebugScanSeen(report, "seenModifierTrees", treeID, "modifierTrees");

	local node = MODIFIER_TREE_DATA[treeID];
	if not node then
		IncrementDebugScanCounter(report, "missingModifierTrees");
		DebugDataInvariant("missing-modifier-tree:" .. tostring(treeID), "missing modifier tree node " .. tostring(treeID) .. FormatDebugContext(ctx));
		visiting[treeID] = nil;
		return;
	end

	local nodeType = node.type;
	if nodeType and nodeType ~= 0 then
		IncrementDebugScanCounter(report, "modifierLeaves");
		local decoder = MODIFIER_LEAF_DECODERS[nodeType];
		if not decoder then
			IncrementDebugScanCounter(report, "unknownModifierLeaves");
			DebugDataInvariant("unknown-modifier-leaf:" .. tostring(nodeType) .. ":" .. tostring(treeID), "unknown modifier leaf type " .. tostring(nodeType) .. " in tree " .. tostring(treeID) .. FormatDebugContext(ctx));
		elseif Resolvers.modifierAlwaysUnsupportedTypes and Resolvers.modifierAlwaysUnsupportedTypes[nodeType] then
			IncrementDebugScanCounter(report, "unsupportedModifierLeaves");
			Resolvers.DebugUnsupportedModifier(ctx, nodeType, node.asset, treeID);
		elseif Resolvers.modifierPartiallyUnsupportedTypes and Resolvers.modifierPartiallyUnsupportedTypes[nodeType] then
			local ok, result = pcall(decoder, ctx or {}, node.asset, node.sec, node.ter, node.amount, treeID);
			if not ok then
				IncrementDebugScanCounter(report, "unknownModifierLeaves");
				DebugDataInvariant("modifier-leaf-error:" .. tostring(nodeType) .. ":" .. tostring(treeID), "modifier leaf type " .. tostring(nodeType) .. " errored during debug scan in tree " .. tostring(treeID) .. ": " .. tostring(result) .. FormatDebugContext(ctx));
			elseif result == MODIFIER_UNSUPPORTED then
				IncrementDebugScanCounter(report, "unsupportedModifierLeaves");
			else
				IncrementDebugScanCounter(report, "knownModifierLeaves");
			end
		else
			IncrementDebugScanCounter(report, "knownModifierLeaves");
		end
	end

	for _, childID in ipairs(MODIFIER_TREE_CHILDREN[treeID] or {}) do
		DebugScanModifierTree(childID, ctx, report, visiting);
	end
	visiting[treeID] = nil;
end

local function DebugScanCriteriaTree(achievementID, achievement, criteriaTreeID, report, visiting)
	criteriaTreeID = tonumber(criteriaTreeID) or 0;
	if criteriaTreeID == 0 then
		return;
	end

	visiting = visiting or {};
	if visiting[criteriaTreeID] then
		IncrementDebugScanCounter(report, "criteriaTreeCycles");
		DebugDataInvariant("criteria-tree-cycle:" .. tostring(criteriaTreeID), "criteria tree cycle at node " .. tostring(criteriaTreeID) .. " (achievement=" .. tostring(achievementID) .. ")");
		return;
	end
	visiting[criteriaTreeID] = true;
	MarkDebugScanSeen(report, "seenCriteriaTrees", criteriaTreeID, "criteriaTrees");

	local criteriaTree = CRITERIA_TREE_DATA[criteriaTreeID];
	if not criteriaTree then
		IncrementDebugScanCounter(report, "missingCriteriaTrees");
		DebugDataInvariant("missing-criteria-tree:" .. tostring(criteriaTreeID), "missing criteria tree " .. tostring(criteriaTreeID) .. " (achievement=" .. tostring(achievementID) .. ")");
		visiting[criteriaTreeID] = nil;
		return;
	end

	local criteriaID = criteriaTree.criteriaID;
	if criteriaID and criteriaID ~= 0 then
		local criteria = CRITERIA_DATA[criteriaID];
		if not criteria then
			IncrementDebugScanCounter(report, "missingCriteria");
			DebugDataInvariant("missing-criteria:" .. tostring(criteriaID), "criteria tree " .. tostring(criteriaTreeID) .. " references missing criteria " .. tostring(criteriaID) .. " (achievement=" .. tostring(achievementID) .. ")");
		else
			IncrementDebugScanCounter(report, "criteriaLeaves");
			if criteria.modifierTree and criteria.modifierTree ~= 0 then
				local ctx = {
					achievementID = achievementID,
					achievement = achievement,
					criteriaTreeID = criteriaTreeID,
					criteriaID = criteria.id,
					criteriaType = criteria.type,
					assetID = criteria.asset,
					debugScan = true,
				};
				DebugScanModifierTree(criteria.modifierTree, ctx, report, {});
			end
		end
	end

	for _, childID in ipairs(CRITERIA_TREE_CHILDREN[criteriaTreeID] or {}) do
		DebugScanCriteriaTree(achievementID, achievement, childID, report, visiting);
	end
	visiting[criteriaTreeID] = nil;
end

local function FormatDebugScanSummary(report)
	return string.format("debug scan complete: %d achievements, %d criteria trees, %d criteria leaves, %d modifier trees, %d modifier leaves, %d unsupported, %d unknown, %d missing",
		report.achievements or 0,
		report.criteriaTrees or 0,
		report.criteriaLeaves or 0,
		report.modifierTrees or 0,
		report.modifierLeaves or 0,
		report.unsupportedModifierLeaves or 0,
		report.unknownModifierLeaves or 0,
		(report.missingCriteriaTrees or 0) + (report.missingCriteria or 0) + (report.missingModifierTrees or 0));
end

local function RunDebugEvaluateAllAchievements(options)
	options = type(options) == "table" and options or {};
	local report = {
		achievements = 0,
		criteriaTrees = 0,
		criteriaLeaves = 0,
		modifierTrees = 0,
		modifierLeaves = 0,
		knownModifierLeaves = 0,
		unsupportedModifierLeaves = 0,
		unknownModifierLeaves = 0,
		missingCriteriaTrees = 0,
		missingCriteria = 0,
		missingModifierTrees = 0,
		criteriaTreeCycles = 0,
		modifierTreeCycles = 0,
	};

	if options.resetWarningCache ~= false then
		Private.debugMessages = {};
	end

	if Private.DebugMessage then
		Private.DebugMessage("debug scan starting: all generated achievements");
	end

	local achievementIDs = {};
	for achievementID in pairs(ACHIEVEMENT_DATA) do
		tinsert(achievementIDs, achievementID);
	end
	table.sort(achievementIDs);

	for _, achievementID in ipairs(achievementIDs) do
		local achievement = ACHIEVEMENT_DATA[achievementID];
		IncrementDebugScanCounter(report, "achievements");
		local criteriaTreeID = GetAchievementCriteriaRootID(achievement);
		if criteriaTreeID and criteriaTreeID ~= 0 then
			DebugScanCriteriaTree(achievementID, achievement, criteriaTreeID, report, {});
		else
			IncrementDebugScanCounter(report, "achievementsWithoutCriteria");
		end
	end

	report.summary = FormatDebugScanSummary(report);
	if Private.DebugMessage then
		Private.DebugMessage(report.summary);
	end
	report.seenCriteriaTrees = nil;
	report.seenModifierTrees = nil;
	return report;
end

function Resolvers.DebugEvaluateAllAchievements(options)
	options = type(options) == "table" and options or {};
	if options.forceLogging == false or not Private.WithDebugLogging then
		return RunDebugEvaluateAllAchievements(options);
	end
	return Private.WithDebugLogging(function()
		return RunDebugEvaluateAllAchievements(options);
	end);
end
end

Resolvers.EvaluateModifierTree = EvaluateModifierTreeNode;
Resolvers.EvaluateCriteriaModifier = EvaluateCriteriaModifier;

-- ============================================================================
-- Per-criterion event recording (for criteria with modifier trees/start events)
-- ============================================================================
-- Walks all criteria of a given type whose asset matches (or is 0/wildcard),
-- evaluates each criterion's start gate and modifier tree against ctx, and
-- increments per-criterion progress for those that pass. This is parallel to
-- the shared per-asset bucket used for ungated criteria.

local recentCriteriaEvents = {};
local CRITERIA_EVENT_DEDUPE_WINDOW = 0.5;

local function MatchesCriteriaAsset(criteria, assetID, criteriaType)
	if criteriaType == CRITERIA_TYPE.EQUIP_ITEM_IN_SLOT then
		return (tonumber(criteria.asset) or 0) == (tonumber(assetID) or 0);
	end
	if not criteria.asset or criteria.asset == 0 then
		return true; -- wildcard criterion matches any asset
	end
	if not assetID or assetID == 0 then
		return false;
	end
	return criteria.asset == assetID;
end

function Resolvers.CriteriaTypeAssetAllowsDecrement(criteriaType, assetID)
	for _, criteria in ipairs(Resolvers.GetRecordableCriteriaByType(criteriaType)) do
		if criteria.type == criteriaType and MatchesCriteriaAsset(criteria, assetID, criteriaType) and Resolvers.HasCriteriaFlag(criteria, CRITERIA_FLAGS.ALLOW_DECREMENT) then
			return true;
		end
	end
	return false;
end

RecordCriteriaEvent = function(criteriaType, assetID, ctx, dedupeKey, amount)
	local recorded = false;
	local now = GetTime();
	local incrementAmount = tonumber(amount) or (ctx and tonumber(ctx.criteriaAmount)) or 1;
	if incrementAmount <= 0 then
		return false;
	end

	if dedupeKey then
		local key = criteriaType .. ":" .. tostring(assetID) .. ":" .. tostring(dedupeKey);
		if recentCriteriaEvents[key] and now - recentCriteriaEvents[key] < CRITERIA_EVENT_DEDUPE_WINDOW then
			return false;
		end
		recentCriteriaEvents[key] = now;
	end

	local characterName = GetProgressCharacterName();
	for _, criteria in ipairs(Resolvers.GetRecordableCriteriaByType(criteriaType)) do
		if criteria.type == criteriaType
			and Resolvers.IsClientRecordableCriteria(criteria)
			and Resolvers.UsesPerCriteriaProgress(criteria)
			and MatchesCriteriaAsset(criteria, assetID, criteriaType)
			and Resolvers.CriteriaAttemptActive(criteria)
			and EvaluateCriteriaModifier(criteria, ctx)
		then
			Resolvers.IncrementCriteriaProgress(criteria.id, incrementAmount, nil, characterName);
			recorded = true;
		end
	end
	return recorded;
end

Resolvers.RecordCriteriaEvent = RecordCriteriaEvent;

function Resolvers.RecordCriteriaProgress(criteriaType, assetID, amount, ctx, dedupeKey)
	assetID = tonumber(assetID) or 0;
	amount = tonumber(amount) or 1;
	if amount <= 0 then
		return false;
	end

	local recorded = false;
	Resolvers.IncrementCriteriaAssetProgress(criteriaType, assetID, amount, nil, GetProgressCharacterName());
	recorded = true;
	if RecordCriteriaEvent then
		ctx = ctx or {};
		ctx.criteriaAmount = amount;
		recorded = RecordCriteriaEvent(criteriaType, assetID, ctx, dedupeKey, amount) or recorded;
	end
	return recorded;
end

function Resolvers.RecordLoginCriteria()
	local ctx = {
		mapID = GetCurrentMapID(),
		zoneAreaID = GetCurrentZoneAreaID and GetCurrentZoneAreaID() or nil,
		sourceRaceID = GetPlayerRaceID and GetPlayerRaceID() or nil,
	};
	return Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.LOGIN, 0, 1, ctx, "login");
end

BuildKillCombatContext = function(sourceGUID, sourceFlags, destGUID, destFlags, creatureID)
	local destIsPlayer = false;
	if destFlags and COMBATLOG_OBJECT_TYPE_PLAYER and HasFlag(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) then
		destIsPlayer = true;
	end
	local targetUnit = ResolveUnitTokenForGUID(destGUID);
	local targetFacts = targetUnit and Resolvers.CacheTargetFacts(destGUID, targetUnit, destFlags, creatureID) or Resolvers.GetCachedTargetFacts(destGUID);
	if not targetFacts and destGUID then
		targetFacts = Resolvers.CacheTargetFacts(destGUID, nil, destFlags, creatureID);
	end
	local targetRaceID = targetFacts and targetFacts.raceID or nil;
	local targetClassID = targetFacts and targetFacts.classID or nil;
	local creature = creatureID and Resolvers.creatures and Resolvers.creatures[creatureID] or nil;
	local targetIsEnemy = targetFacts and targetFacts.isEnemy or nil;
	if destFlags and COMBATLOG_OBJECT_REACTION_HOSTILE then
		targetIsEnemy = HasFlag(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE);
	end
	return {
		sourceGUID = sourceGUID,
		sourceFlags = sourceFlags,
		destGUID = destGUID,
		destFlags = destFlags,
		creatureID = creatureID,
		targetUnit = targetUnit,
		targetFacts = targetFacts,
		mapID = GetCurrentMapID(),
		zoneAreaID = GetCurrentZoneAreaID(),
		creatureTypeID = (targetFacts and targetFacts.creatureTypeID) or (creature and creature.type) or nil,
		creatureClassification = (targetFacts and targetFacts.creatureClassification) or (creature and creature.classification) or nil,
		sourceRaceID = GetPlayerRaceID(),
		targetRaceID = targetRaceID,
		targetClassID = targetClassID,
		targetLevel = targetFacts and targetFacts.level or nil,
		targetSex = targetFacts and targetFacts.sex or nil,
		targetIsMounted = targetFacts and targetFacts.isMounted or nil,
		targetIsPlayer = destIsPlayer or (targetFacts and targetFacts.isPlayer == true),
		targetIsDead = true,
		targetIsEnemy = targetIsEnemy,
	};
end

function Resolvers.RecordRecentPlayerDamageSource(sourceGUID, sourceFlags)
	if not sourceGUID then
		return false;
	end

	local creatureID = GetCreatureIDFromGUID(sourceGUID);
	if not creatureID or creatureID == 0 then
		return false;
	end

	Private.state = Private.state or {};
	Private.state.lastPlayerDamageCreature = {
		creatureID = creatureID,
		sourceGUID = sourceGUID,
		sourceFlags = sourceFlags,
		at = Resolvers.GetNow(),
	};
	return true;
end

function Resolvers.RecordPlayerKilledByCreature()
	Private.state = Private.state or {};
	local recent = Private.state.lastPlayerDamageCreature;
	if not recent or not recent.creatureID or (Resolvers.GetNow() - (recent.at or 0)) > 10 then
		return false;
	end

	local ctx = BuildKillCombatContext(recent.sourceGUID, recent.sourceFlags, nil, nil, recent.creatureID);
	local recorded = RecordCriteriaEvent(CRITERIA_TYPE.GET_KILLED_BY_CREATURE, recent.creatureID, ctx, "killed-by-" .. tostring(recent.creatureID));
	Private.state.lastPlayerDamageCreature = nil;
	return recorded;
end


local function HandleCombatLogCriteria()
	local _, subevent, _, sourceGUID, _, sourceFlags, _, destGUID, _, destFlags, _, eventArg1, _, _, eventArg4, eventArg5 = CombatLogGetCurrentEventInfo();
	local spellID = eventArg1;
	local environmentalType;
	local damageAmount;
	local healingAmount;
	local recorded = false;
	local refreshTypes;
	local refreshDelay = 0.75;
	local needsFullRefresh = false;
	if subevent == "SWING_DAMAGE" then
		spellID = nil;
		damageAmount = tonumber(eventArg1) or 0;
	elseif subevent == "RANGE_DAMAGE" or subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "DAMAGE_SHIELD" or subevent == "DAMAGE_SPLIT" then
		damageAmount = tonumber(eventArg4) or 0;
	elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
		local overhealing = tonumber(eventArg5) or 0;
		healingAmount = math.max(0, (tonumber(eventArg4) or 0) - overhealing);
	elseif subevent == "ENVIRONMENTAL_DAMAGE" then
		spellID = nil;
		environmentalType = eventArg1;
		local environmentalDamageAmount = select(13, CombatLogGetCurrentEventInfo());
		damageAmount = tonumber(environmentalDamageAmount) or 0;
	end

	if Resolvers.RecordSoulOfIronNaxxCombatLog and Resolvers.RecordSoulOfIronNaxxCombatLog(subevent, sourceGUID, sourceFlags, destGUID, destFlags) then
		recorded = true;
		needsFullRefresh = true;
	end

	if DestIsPlayer(destGUID, destFlags) and sourceGUID and sourceGUID ~= "" and (string.find(subevent or "", "_DAMAGE") or subevent == "SWING_DAMAGE" or subevent == "RANGE_DAMAGE") then
		Resolvers.RecordRecentPlayerDamageSource(sourceGUID, sourceFlags);
		if sourceFlags and COMBATLOG_OBJECT_TYPE_PLAYER and HasFlag(sourceFlags, COMBATLOG_OBJECT_TYPE_PLAYER) then
			Private.state = Private.state or {};
			Private.state.lastPlayerDamagePlayer = {
				at = Resolvers.GetNow(),
				sourceGUID = sourceGUID,
				sourceFlags = sourceFlags,
				destGUID = destGUID,
				destFlags = destFlags,
				sourceIsEnemy = sourceFlags and COMBATLOG_OBJECT_REACTION_HOSTILE and HasFlag(sourceFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) or false,
			};
		end
	end

	if SourceIsPlayerControlled(sourceGUID, sourceFlags) then
		local ctx = BuildKillCombatContext(sourceGUID, sourceFlags, destGUID, destFlags, GetCreatureIDFromGUID(destGUID));
		if damageAmount and damageAmount > 0 then
			if Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.DAMAGE_DEALT, 0, damageAmount, ctx, nil) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.DAMAGE_DEALT);
			end
			if Resolvers.SetCriteriaAssetProgressMax(CRITERIA_TYPE.HIGHEST_DAMAGE_IN_SINGLE_ABILITY, 0, damageAmount, GetProgressCharacterName()) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.HIGHEST_DAMAGE_IN_SINGLE_ABILITY);
			end
		end
		if healingAmount and healingAmount > 0 then
			if Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.HEALING_DONE, 0, healingAmount, ctx, nil) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.HEALING_DONE);
			end
			if Resolvers.SetCriteriaAssetProgressMax(CRITERIA_TYPE.LARGEST_HEAL_CAST, 0, healingAmount, GetProgressCharacterName()) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.LARGEST_HEAL_CAST);
			end
		end
	end

	if DestIsPlayer(destGUID, destFlags) then
		if damageAmount and damageAmount > 0 then
			if Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.TOTAL_DAMAGE_TAKEN, 0, damageAmount, {}, nil) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.TOTAL_DAMAGE_TAKEN);
			end
			if Resolvers.SetCriteriaAssetProgressMax(CRITERIA_TYPE.MOST_DAMAGE_TAKEN_IN_SINGLE_HIT, 0, damageAmount, GetProgressCharacterName()) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.MOST_DAMAGE_TAKEN_IN_SINGLE_HIT);
			end
		end
		if healingAmount and healingAmount > 0 then
			if Resolvers.RecordCriteriaProgress(CRITERIA_TYPE.TOTAL_HEALING_RECEIVED, 0, healingAmount, {}, nil) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.TOTAL_HEALING_RECEIVED);
			end
			if Resolvers.SetCriteriaAssetProgressMax(CRITERIA_TYPE.LARGEST_HEAL_RECEIVED, 0, healingAmount, GetProgressCharacterName()) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.LARGEST_HEAL_RECEIVED);
			end
		end
	end

	if subevent == "PARTY_KILL" and SourceIsPlayerGroup(sourceGUID, sourceFlags) then
		local creatureID = GetCreatureIDFromGUID(destGUID);
		local ctx = BuildKillCombatContext(sourceGUID, sourceFlags, destGUID, destFlags, creatureID);
		if Resolvers.RecordSoulOfIronBossKill(creatureID) then
			recorded = true;
			needsFullRefresh = true;
		end
		Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.KILL_NPC, creatureID);
		if RecordCombatCriteriaAsset(CRITERIA_TYPE.KILL_NPC, creatureID, 1) then
			recorded = true;
			refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILL_NPC);
			refreshDelay = 0.15;
		end
		if RecordCriteriaEvent(CRITERIA_TYPE.KILL_NPC, creatureID, ctx) then
			recorded = true;
			refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILL_NPC);
			refreshDelay = 0.15;
		end
		if creatureID then
			if RecordCriteriaEvent(CRITERIA_TYPE.KILL_ANY_NPC, 0, ctx) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILL_ANY_NPC);
				refreshDelay = 0.15;
			end
		end
		if DestIsPlayer(destGUID, destFlags) then
			Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.KILL_PLAYER, 0);
			if ctx.zoneAreaID then
				if RecordCriteriaEvent(CRITERIA_TYPE.KILL_PLAYER_IN_AREA, ctx.zoneAreaID, ctx) then
					recorded = true;
					refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILL_PLAYER_IN_AREA);
					refreshDelay = 0.15;
				end
			end
			if ctx.targetClassID then
				if RecordCriteriaEvent(CRITERIA_TYPE.KILLING_BLOW_TO_CLASS, ctx.targetClassID, ctx) then
					recorded = true;
					refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILLING_BLOW_TO_CLASS);
					refreshDelay = 0.15;
				end
			end
			if ctx.targetRaceID then
				if RecordCriteriaEvent(CRITERIA_TYPE.KILLING_BLOW_TO_RACE, ctx.targetRaceID, ctx) then
					recorded = true;
					refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILLING_BLOW_TO_RACE);
					refreshDelay = 0.15;
				end
			end
			if RecordCriteriaEvent(CRITERIA_TYPE.HONORABLE_KILL, 0, ctx) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.HONORABLE_KILL);
				refreshDelay = 0.15;
			end
			if RecordCriteriaEvent(CRITERIA_TYPE.KILLING_BLOW, 0, ctx) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILLING_BLOW);
				refreshDelay = 0.15;
			end
			if RecordCriteriaEvent(CRITERIA_TYPE.KILL_PLAYER_NO_HONOR_CHECK, 0, ctx) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.KILL_PLAYER_NO_HONOR_CHECK);
				refreshDelay = 0.15;
			end
		end
	elseif subevent == "SPELL_CAST_SUCCESS" and SourceIsPlayerControlled(sourceGUID, sourceFlags) then
		Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.CAST_SPELL, spellID);
		Resolvers.RecordCriteriaFail(CRITERIA_FAIL_EVENT.CAST_SPELL, spellID);
		if RecordCombatCriteriaAsset(CRITERIA_TYPE.CAST_SPELL, spellID, 1, 0.05) then
			recorded = true;
			refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.CAST_SPELL);
			refreshDelay = 0.15;
		end
		if RecordCriteriaEvent(CRITERIA_TYPE.CAST_SPELL, spellID, BuildKillCombatContext(sourceGUID, sourceFlags, destGUID, destFlags, GetCreatureIDFromGUID(destGUID)), "cast-" .. tostring(spellID)) then
			recorded = true;
			refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.CAST_SPELL);
			refreshDelay = 0.15;
		end
		if spellID and destGUID and destGUID ~= "" then
			local ctx = BuildKillCombatContext(sourceGUID, sourceFlags, destGUID, destFlags, GetCreatureIDFromGUID(destGUID));
			if RecordCriteriaEvent(CRITERIA_TYPE.LAND_TARGETED_SPELL, spellID, ctx) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.LAND_TARGETED_SPELL);
				refreshDelay = 0.15;
			end
		end
	elseif subevent == "ENVIRONMENTAL_DAMAGE" and DestIsPlayer(destGUID, destFlags) and type(environmentalType) == "string" then
		lastEnvironmentalDamageType = environmentalType;
		lastEnvironmentalDamageAt = GetTime();
		if environmentalType == "Falling" then
			if Resolvers.RecordSurvivedFallDamage(damageAmount) then
				recorded = true;
				refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.MAX_DISTANCE_FALLEN_WITHOUT_DYING);
				refreshDelay = 0.35;
			end
		end
	end

	if spellID and INCOMING_SPELL_EVENTS[subevent] and DestIsPlayer(destGUID, destFlags) then
		Resolvers.RecordCriteriaStart(CRITERIA_START_EVENT.HAVE_SPELL_CAST_ON_YOU, spellID);
		Resolvers.RecordCriteriaFail(CRITERIA_FAIL_EVENT.HAVE_SPELL_CAST_ON_YOU, spellID);
		if RecordCombatCriteriaAsset(CRITERIA_TYPE.HAVE_SPELL_CAST_ON_YOU, spellID, 1, 0.2) then
			recorded = true;
			refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.HAVE_SPELL_CAST_ON_YOU);
			refreshDelay = 0.15;
		end
		if RecordCriteriaEvent(CRITERIA_TYPE.HAVE_SPELL_CAST_ON_YOU, spellID, BuildKillCombatContext(sourceGUID, sourceFlags, destGUID, destFlags, GetCreatureIDFromGUID(sourceGUID)), "incoming-" .. tostring(spellID)) then
			recorded = true;
			refreshTypes = Resolvers.MarkCriteriaRefreshType(refreshTypes, CRITERIA_TYPE.HAVE_SPELL_CAST_ON_YOU);
			refreshDelay = 0.15;
		end
	end

	if recorded and needsFullRefresh then
		if Achievements.ScheduleCriteriaRefresh then
			Achievements.ScheduleCriteriaRefresh(true, refreshDelay, "combat-log");
		elseif Achievements.RefreshCriteriaAchievements then
			Achievements.RefreshCriteriaAchievements(true);
		end
	elseif recorded then
		Resolvers.ScheduleCriteriaTypesRefresh(refreshTypes, true, refreshDelay, "combat-log");
	end

	return recorded;
end

local function GetGenericEmoteCriteriaByName()
	if genericEmoteCriteriaByName then
		return genericEmoteCriteriaByName;
	end

	genericEmoteCriteriaByName = {};
	for _, criteria in pairs(CRITERIA_DATA) do
		if Resolvers.IsClientRecordableCriteria(criteria) and not Resolvers.UsesPerCriteriaProgress(criteria) and criteria.type == CRITERIA_TYPE.EMOTE and criteria.asset and criteria.asset ~= 0 and criteria.modifierTree == 0 then
			local emote = emotes[criteria.asset];
			if emote and emote.name and emote.name ~= "" then
				local emoteName = string.upper(emote.name);
				genericEmoteCriteriaByName[emoteName] = genericEmoteCriteriaByName[emoteName] or {};
				tinsert(genericEmoteCriteriaByName[emoteName], criteria.id);
			end
		end
	end

	return genericEmoteCriteriaByName;
end

-- Parallel cache: gated emote criteria, keyed by emote token name. These need
-- per-criterion state/context so they cannot be incremented blind like the
-- ungated counters.
local gatedEmoteCriteriaByName;
local function GetGatedEmoteCriteriaByName()
	if gatedEmoteCriteriaByName then
		return gatedEmoteCriteriaByName;
	end

	gatedEmoteCriteriaByName = {};
	for _, criteria in pairs(CRITERIA_DATA) do
		if Resolvers.IsClientRecordableCriteria(criteria) and Resolvers.UsesPerCriteriaProgress(criteria) and criteria.type == CRITERIA_TYPE.EMOTE and criteria.asset and criteria.asset ~= 0 then
			local emote = emotes[criteria.asset];
			if emote and emote.name and emote.name ~= "" then
				local emoteName = string.upper(emote.name);
				gatedEmoteCriteriaByName[emoteName] = gatedEmoteCriteriaByName[emoteName] or {};
				tinsert(gatedEmoteCriteriaByName[emoteName], criteria);
			end
		end
	end

	return gatedEmoteCriteriaByName;
end

function Resolvers.GetSingleTargetCreatureModifierAsset(treeID, visiting)
	treeID = tonumber(treeID) or 0;
	if treeID == 0 then
		return nil;
	end
	visiting = visiting or {};
	if visiting[treeID] then
		return nil;
	end

	local node = MODIFIER_TREE_DATA[treeID];
	if not node then
		return nil;
	end

	visiting[treeID] = true;
	local matchedAsset;
	local leafCount = 0;
	if node.type and node.type ~= 0 then
		if node.type ~= 4 then
			visiting[treeID] = nil;
			return nil;
		end
		matchedAsset = tonumber(node.asset) or 0;
		leafCount = 1;
	end

	for _, childID in ipairs(MODIFIER_TREE_CHILDREN[treeID] or {}) do
		local childAsset, childLeafCount = Resolvers.GetSingleTargetCreatureModifierAsset(childID, visiting);
		if not childAsset or childAsset == 0 or (matchedAsset and childAsset ~= matchedAsset) then
			visiting[treeID] = nil;
			return nil;
		end
		matchedAsset = childAsset;
		leafCount = leafCount + (childLeafCount or 0);
		if leafCount > 1 then
			visiting[treeID] = nil;
			return nil;
		end
	end

	visiting[treeID] = nil;
	if leafCount == 1 and matchedAsset and matchedAsset ~= 0 then
		return matchedAsset, leafCount;
	end
	return nil;
end

function Resolvers.GetEmoteTargetCriteriaByName()
	if Resolvers.emoteTargetCriteriaByName then
		return Resolvers.emoteTargetCriteriaByName;
	end

	local cache = {};
	for _, criteriaTree in pairs(CRITERIA_TREE_DATA) do
		local criteria = criteriaTree.criteriaID and CRITERIA_DATA[criteriaTree.criteriaID] or nil;
		if criteria and Resolvers.IsClientRecordableCriteria(criteria) and criteria.type == CRITERIA_TYPE.EMOTE and criteria.asset and criteria.asset ~= 0 and Resolvers.GetSingleTargetCreatureModifierAsset(criteria.modifierTree) then
			local emote = emotes[criteria.asset];
			local targetName = Resolvers.NormalizeCriteriaText(criteriaTree.description);
			if emote and emote.name and emote.name ~= "" and targetName then
				local emoteName = string.upper(emote.name);
				cache[emoteName] = cache[emoteName] or {};
				cache[emoteName][targetName] = cache[emoteName][targetName] or {};
				cache[emoteName][targetName][criteria.id] = criteria;
			end
		end
	end

	Resolvers.emoteTargetCriteriaByName = cache;
	return cache;
end

local function GetEmoteTargetUnit(emoteTarget)
	if type(emoteTarget) == "string" and emoteTarget ~= "" and UnitExists(emoteTarget) then
		return emoteTarget;
	end
	return "target";
end

local function BuildEmoteTargetContext(emoteTarget)
	local unit = GetEmoteTargetUnit(emoteTarget);
	local explicitTargetName = type(emoteTarget) == "string" and emoteTarget ~= "" and not UnitExists(emoteTarget) and emoteTarget or nil;
	local ctx = {
		emoteTargetName = explicitTargetName,
		mapID = GetCurrentMapID(),
		zoneAreaID = GetCurrentZoneAreaID(),
		sourceRaceID = GetPlayerRaceID(),
	};
	if not UnitExists(unit) then
		return ctx;
	end
	ctx.targetUnit = unit;
	ctx.targetName = UnitName(unit);
	ctx.destGUID = UnitGUID(unit);
	ctx.creatureID = GetCreatureIDFromGUID(ctx.destGUID);
	local targetFacts = ctx.destGUID and Resolvers.CacheTargetFacts(ctx.destGUID, unit, nil, ctx.creatureID) or nil;
	ctx.targetFacts = targetFacts;
	local creature = ctx.creatureID and Resolvers.creatures and Resolvers.creatures[ctx.creatureID] or nil;
	ctx.creatureTypeID = (targetFacts and targetFacts.creatureTypeID) or (creature and creature.type) or nil;
	ctx.creatureClassification = (targetFacts and targetFacts.creatureClassification) or (creature and creature.classification) or nil;
	ctx.targetRaceID = targetFacts and targetFacts.raceID or nil;
	ctx.targetClassID = targetFacts and targetFacts.classID or nil;
	ctx.targetLevel = targetFacts and targetFacts.level or nil;
	ctx.targetSex = targetFacts and targetFacts.sex or nil;
	ctx.targetIsMounted = targetFacts and targetFacts.isMounted or nil;
	if UnitIsPlayer(unit) then
		ctx.targetIsPlayer = true;
		if not ctx.targetRaceID and GetTargetRaceID then
			ctx.targetRaceID = GetTargetRaceID(unit);
		end
	end
	ctx.targetIsDead = UnitIsDeadOrGhost(unit) == true;
	ctx.targetIsEnemy = UnitCanAttack("player", unit) == true;
	return ctx;
end

local function EmoteTargetNameMatchesCriteria(emoteName, criteria, ctx)
	local targetName = ctx and (ctx.emoteTargetName or ctx.targetName);
	local targetKey = Resolvers.NormalizeCriteriaText(targetName);
	if not targetKey then
		return false;
	end
	local criteriaByTarget = Resolvers.GetEmoteTargetCriteriaByName()[emoteName];
	return criteriaByTarget and criteriaByTarget[targetKey] and criteriaByTarget[targetKey][criteria.id] ~= nil;
end

local function RecordEmoteCriteria(emoteToken, emoteTarget)
	if type(emoteToken) ~= "string" then
		return false;
	end

	local emoteName = string.upper(emoteToken);
	local recorded = false;
	local now = GetTime();
	local dedupe = recentEmotes[emoteName] and now - recentEmotes[emoteName] < 0.2;
	if not dedupe then
		recentEmotes[emoteName] = now;
	end

	-- Ungated emote counters.
	local criteriaIDs = GetGenericEmoteCriteriaByName()[emoteName];
	if criteriaIDs and #criteriaIDs > 0 and not dedupe then
		local characterName = GetProgressCharacterName();
		for _, criteriaID in ipairs(criteriaIDs) do
			Resolvers.IncrementCriteriaProgress(criteriaID, 1, nil, characterName);
		end
		recorded = true;
	end

	-- Gated criteria require modifier-tree evaluation against current target.
	local gatedCriteria = GetGatedEmoteCriteriaByName()[emoteName];
	if gatedCriteria and #gatedCriteria > 0 then
		local ctx = BuildEmoteTargetContext(emoteTarget);
		for _, criteria in ipairs(gatedCriteria) do
			if Resolvers.CriteriaAttemptActive(criteria) and (EvaluateCriteriaModifier(criteria, ctx) or EmoteTargetNameMatchesCriteria(emoteName, criteria, ctx)) then
				Resolvers.IncrementCriteriaProgress(criteria.id, 1, nil, GetProgressCharacterName());
				recorded = true;
			end
		end
	end

	if recorded and Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(true);
	end
	return recorded;
end

Resolvers.RecordEmoteCriteria = RecordEmoteCriteria;

local function HookEmoteCriteria()
	if emoteHooksInstalled then
		return emoteHooksInstalled;
	end

	emoteHooksInstalled = true;
	Resolvers.HookGlobalFunction("DoEmote", function(emoteToken, emoteTarget)
		RecordEmoteCriteria(emoteToken, emoteTarget);
	end);
	return true;
end

-- 37: ARENA_RATING_MIN. Used by arena streak/title criteria.
MODIFIER_LEAF_DECODERS[37] = function(ctx, asset)
	if ctx.arenaRating then
		return ctx.arenaRating >= (asset or 0);
	end
	return (Resolvers.GetArenaRating(2, true) or 0) >= (asset or 0)
		or (Resolvers.GetArenaRating(3, true) or 0) >= (asset or 0)
		or (Resolvers.GetArenaRating(5, true) or 0) >= (asset or 0);
end;

-- 38: PLAYER_HAS_TITLE. Title APIs differ between Classic branches, so use
-- the direct title-id API when present and fall back to the current title.
MODIFIER_LEAF_DECODERS[38] = function(_, asset)
	return Resolvers.PlayerHasTitle(asset);
end;

-- 39: SOURCE_LEVEL_MIN. WotLK arena/title rows commonly gate at level 80.
MODIFIER_LEAF_DECODERS[39] = function(_, asset)
	return (UnitLevel("player") or 0) >= (asset or 0);
end;

local function ResolveEmote(context)
	return ResolveSavedProgress(context);
end

local function ResolveCriteriaLeaf(context)
	local criteria = context.criteria;
	if not criteria then
		local missingCriteriaID = context.criteriaTree and context.criteriaTree.criteriaID or nil;
		if missingCriteriaID and missingCriteriaID ~= 0 then
			DebugDataInvariant("missing-criteria:" .. tostring(missingCriteriaID), "criteria tree " .. tostring(context.criteriaTreeID) .. " references missing criteria " .. tostring(missingCriteriaID) .. FormatDebugContext(context));
		end
		return BuildResult(false, 0, context.requiredQuantity or GetRequiredQuantity(context.criteriaTree), nil, "missing-criteria");
	end
	if Resolvers.HasCriteriaFlag(criteria, CRITERIA_FLAGS.SERVER_ONLY) then
		return ResolveSavedProgress(context);
	end
	if not Resolvers.CriteriaAttemptActive(criteria) then
		return BuildResult(false, 0, context.requiredQuantity or GetRequiredQuantity(context.criteriaTree), nil, "criteria-not-started");
	end

	local handler = criteriaTypeHandlers[criteria.type];
	if handler then
		return handler(context);
	end

	return ResolveSavedProgress(context);
end

local function BuildChildContext(context, criteriaTreeID)
	local criteriaTree = CRITERIA_TREE_DATA[criteriaTreeID];
	local criteria = criteriaTree and CRITERIA_DATA[criteriaTree.criteriaID] or nil;
	if criteriaTreeID and criteriaTreeID ~= 0 and not criteriaTree then
		DebugDataInvariant("missing-criteria-tree:" .. tostring(criteriaTreeID), "missing criteria tree " .. tostring(criteriaTreeID) .. FormatDebugContext(context));
	elseif criteriaTree and criteriaTree.criteriaID and criteriaTree.criteriaID ~= 0 and not criteria then
		DebugDataInvariant("missing-criteria:" .. tostring(criteriaTree.criteriaID), "criteria tree " .. tostring(criteriaTreeID) .. " references missing criteria " .. tostring(criteriaTree.criteriaID) .. FormatDebugContext(context));
	end
	return {
		achievementID = context.achievementID,
		achievement = context.achievement,
		criteriaTreeID = criteriaTreeID,
		criteriaTree = criteriaTree,
		criteria = criteria,
		requiredQuantity = GetRequiredQuantity(criteriaTree),
	};
end

local ResolveCriteriaTree;

local function ResolveChildCriteriaTree(context, criteriaTreeID)
	return ResolveCriteriaTree(BuildChildContext(context, criteriaTreeID));
end

local function ResolveEligibleChildren(context)
	local childIDs = CRITERIA_TREE_CHILDREN[context.criteriaTreeID];
	local childResults = {};
	if not childIDs or #childIDs == 0 then
		return childResults;
	end

	for _, childID in ipairs(childIDs) do
		local childResult = ResolveChildCriteriaTree(context, childID);
		if childResult and childResult.eligible ~= false then
			tinsert(childResults, {
				criteriaTree = CRITERIA_TREE_DATA[childID],
				result = childResult,
			});
		end
	end

	return childResults;
end

local function GetRequiredChildCount(context, childCount, defaultToAll)
	local requiredQuantity = context.criteriaTree and context.criteriaTree.amount or 0;
	if requiredQuantity <= 0 then
		requiredQuantity = defaultToAll and childCount or 1;
	end

	local minimumCriteria = context.achievement and context.achievement.minimumCriteria or 0;
	if minimumCriteria > 0 and minimumCriteria < requiredQuantity then
		requiredQuantity = minimumCriteria;
	end

	return requiredQuantity;
end

local function ResolveCompletedChildCount(context, requireAllChildren, source)
	local childResults = ResolveEligibleChildren(context);
	if #childResults == 0 then
		return ResolveCriteriaLeaf(context);
	end

	local completedChildren = 0;
	for _, child in ipairs(childResults) do
		if child.result.completed then
			completedChildren = completedChildren + 1;
		end
	end

	local requiredQuantity = requireAllChildren and #childResults or GetRequiredChildCount(context, #childResults, false);
	return BuildResult(completedChildren >= requiredQuantity, completedChildren, requiredQuantity, nil, source or "criteria-children");
end

local function ResolveSingle(context)
	local childResults = ResolveEligibleChildren(context);
	if #childResults > 0 then
		return childResults[1].result;
	end

	return ResolveCriteriaLeaf(context);
end

local function ResolveSingleNotCompleted(context)
	local result = ResolveSingle(context);
	if not result then
		return nil;
	end

	local completed = result.completed ~= true;
	local quantity = completed and (result.requiredQuantity or 1) or 0;
	return BuildResult(completed, quantity, result.requiredQuantity or 1, result.characterName, "single-not-completed");
end

local function ResolveAnyChild(context)
	local childResults = ResolveEligibleChildren(context);
	if #childResults == 0 then
		return ResolveCriteriaLeaf(context);
	end

	local completedChildren = 0;
	local characterName;
	for _, child in ipairs(childResults) do
		if child.result.completed then
			completedChildren = completedChildren + 1;
			characterName = child.result.characterName or characterName;
		end
	end

	local requiredQuantity = GetRequiredChildCount(context, #childResults, false);
	return BuildResult(completedChildren >= requiredQuantity, completedChildren, requiredQuantity, characterName, "any-child");
end

local function ResolveSumChildren(context)
	local childResults = ResolveEligibleChildren(context);
	if #childResults == 0 then
		return ResolveCriteriaLeaf(context);
	end

	local quantity = 0;
	local summedRequiredQuantity = 0;
	for _, child in ipairs(childResults) do
		quantity = quantity + (child.result.rawQuantity or child.result.quantity or 0);
		summedRequiredQuantity = summedRequiredQuantity + (child.result.requiredQuantity or 0);
	end

	local requiredQuantity = context.criteriaTree and context.criteriaTree.amount or 0;
	if requiredQuantity <= 0 then
		requiredQuantity = summedRequiredQuantity;
	end
	if requiredQuantity <= 0 then
		requiredQuantity = #childResults;
	end

	return BuildResult(quantity >= requiredQuantity, quantity, requiredQuantity, nil, "sum-children");
end

local function ResolveMaxChild(context)
	local childResults = ResolveEligibleChildren(context);
	if #childResults == 0 then
		return ResolveCriteriaLeaf(context);
	end

	local quantity = 0;
	local largestRequiredQuantity = 0;
	local statLabel;
	for _, child in ipairs(childResults) do
		local childQuantity = child.result.rawQuantity or child.result.quantity or 0;
		if childQuantity > quantity then
			quantity = childQuantity;
			statLabel = child.result.statLabel or (child.criteriaTree and child.criteriaTree.description);
			if statLabel == "" then
				statLabel = nil;
			end
		end
		largestRequiredQuantity = math.max(largestRequiredQuantity, child.result.requiredQuantity or 0);
	end

	local requiredQuantity = context.criteriaTree and context.criteriaTree.amount or 0;
	if requiredQuantity <= 0 then
		requiredQuantity = largestRequiredQuantity;
	end
	if requiredQuantity <= 0 then
		requiredQuantity = 1;
	end

	return BuildResult(quantity >= requiredQuantity, quantity, requiredQuantity, nil, "max-child", nil, statLabel);
end

local function ResolveSumChildrenWeight(context)
	local childResults = ResolveEligibleChildren(context);
	if #childResults == 0 then
		return ResolveCriteriaLeaf(context);
	end

	local quantity = 0;
	local totalWeight = 0;
	for _, child in ipairs(childResults) do
		local weight = child.criteriaTree and child.criteriaTree.amount or 0;
		if weight <= 0 then
			weight = 1;
		end
		totalWeight = totalWeight + weight;
		if child.result.completed then
			quantity = quantity + weight;
		end
	end

	local requiredQuantity = context.criteriaTree and context.criteriaTree.amount or 0;
	if requiredQuantity <= 0 then
		requiredQuantity = totalWeight;
	end

	return BuildResult(quantity >= requiredQuantity, quantity, requiredQuantity, nil, "sum-children-weight");
end

ResolveCriteriaTree = function(context)
	local criteriaTree = context.criteriaTree;
	if not criteriaTree then
		if context.criteriaTreeID and context.criteriaTreeID ~= 0 then
			DebugDataInvariant("missing-criteria-tree:" .. tostring(context.criteriaTreeID), "missing criteria tree " .. tostring(context.criteriaTreeID) .. FormatDebugContext(context));
		end
		return nil;
	end
	if not CriteriaTreeAppliesToPlayer(criteriaTree) then
		return BuildResult(false, 0, GetRequiredQuantity(criteriaTree), nil, "criteria-tree-faction", false);
	end

	local childIDs = CRITERIA_TREE_CHILDREN[context.criteriaTreeID];
	if criteriaTree.criteriaID and criteriaTree.criteriaID ~= 0 and (not childIDs or #childIDs == 0) then
		return ResolveCriteriaLeaf(context);
	end

	local handler = criteriaTreeOperatorHandlers[criteriaTree.operator or CRITERIA_TREE_OPERATOR.SINGLE];
	if handler then
		return handler(context);
	end

	return ResolveSingle(context);
end

function Resolvers.ResolveCriteriaTree(criteriaTreeID, achievementID)
	local achievement = achievementID and ACHIEVEMENT_DATA[achievementID] or nil;
	return ResolveCriteriaTree(BuildChildContext({ achievementID = achievementID, achievement = achievement }, criteriaTreeID));
end

function Resolvers.SetCriteriaTypeHandler(criteriaType, handler)
	criteriaTypeHandlers[criteriaType] = handler;
end

function Resolvers.SetCriteriaTreeOperatorHandler(operator, handler)
	criteriaTreeOperatorHandlers[operator] = handler;
end

function Resolvers.RegisterQuestAreaQuests(areaID, questIDs)
	areaID = tonumber(areaID);
	if not areaID or areaID == 0 or type(questIDs) ~= "table" then
		return false;
	end

	local storedQuestIDs = {};
	for _, questID in ipairs(questIDs) do
		questID = tonumber(questID);
		if questID and questID ~= 0 then
			tinsert(storedQuestIDs, questID);
		end
	end
	questAreaQuests[areaID] = storedQuestIDs;
	return true;
end

function Resolvers.RegisterQuestSortQuests(questSortID, questIDs)
	questSortID = tonumber(questSortID);
	if not questSortID or questSortID == 0 or type(questIDs) ~= "table" then
		return false;
	end

	local storedQuestIDs = {};
	for _, questID in ipairs(questIDs) do
		questID = tonumber(questID);
		if questID and questID ~= 0 then
			tinsert(storedQuestIDs, questID);
		end
	end

	questSortQuests[questSortID] = storedQuestIDs;
	return true;
end

function Resolvers.SetCriteriaProgress(criteriaID, quantity, completed, characterName)
	criteriaID = tonumber(criteriaID);
	if not criteriaID or criteriaID == 0 then
		return false;
	end

	local progress = {
		quantity = math.max(0, tonumber(quantity) or 0),
		completed = completed == true,
	};
	if Private.SealSavedRecord then
		Private.SealSavedRecord(progress, "criteria", criteriaID, Resolvers.CriteriaUsesAccountProgress(criteriaID), "quantity", "completed");
	end
	Resolvers.GetSavedCriteriaProgress(criteriaID)[criteriaID] = progress;
	return true;
end

function Resolvers.IncrementCriteriaProgress(criteriaID, amount, requiredQuantity, characterName)
	criteriaID = tonumber(criteriaID);
	if not criteriaID or criteriaID == 0 then
		return false;
	end

	amount = tonumber(amount) or 1;
	if amount < 0 and not Resolvers.HasCriteriaFlag(CRITERIA_DATA[criteriaID], CRITERIA_FLAGS.ALLOW_DECREMENT) then
		return false;
	end

	local savedProgress = Resolvers.GetSavedCriteriaProgress(criteriaID);
	local progress = savedProgress[criteriaID] or {};
	local quantity = math.max(0, (progress.quantity or 0) + amount);
	progress.quantity = quantity;
	progress.completed = progress.completed == true or (requiredQuantity and quantity >= requiredQuantity) or false;
	progress.character = nil;
	if Private.SealSavedRecord then
		Private.SealSavedRecord(progress, "criteria", criteriaID, Resolvers.CriteriaUsesAccountProgress(criteriaID), "quantity", "completed");
	end
	savedProgress[criteriaID] = progress;
	return true;
end

function Resolvers.SetCriteriaAssetProgress(criteriaType, assetID, quantity, completed, characterName)
	criteriaType = tonumber(criteriaType);
	assetID = tonumber(assetID);
	if not criteriaType or assetID == nil then
		return false;
	end

	local criteriaAssetProgress = Resolvers.GetSavedCriteriaAssetProgress(criteriaType, assetID);
	criteriaAssetProgress[criteriaType] = criteriaAssetProgress[criteriaType] or {};
	local progress = {
		quantity = math.max(0, tonumber(quantity) or 0),
		completed = completed == true,
	};
	if Private.SealSavedRecord then
		Private.SealSavedRecord(progress, "criteriaAsset", tostring(criteriaType) .. ":" .. tostring(assetID), Resolvers.CriteriaAssetUsesAccountProgress(criteriaType, assetID), "quantity", "completed");
	end
	criteriaAssetProgress[criteriaType][assetID] = progress;
	return true;
end

function Resolvers.IncrementCriteriaAssetProgress(criteriaType, assetID, amount, requiredQuantity, characterName)
	criteriaType = tonumber(criteriaType);
	assetID = tonumber(assetID);
	if not criteriaType or assetID == nil then
		return false;
	end

	amount = tonumber(amount) or 1;
	if amount < 0 and not Resolvers.CriteriaTypeAssetAllowsDecrement(criteriaType, assetID) then
		return false;
	end

	local criteriaAssetProgress = Resolvers.GetSavedCriteriaAssetProgress(criteriaType, assetID);
	criteriaAssetProgress[criteriaType] = criteriaAssetProgress[criteriaType] or {};
	local progress = criteriaAssetProgress[criteriaType][assetID] or {};
	local quantity = math.max(0, (progress.quantity or 0) + amount);
	progress.quantity = quantity;
	progress.completed = progress.completed == true or (requiredQuantity and quantity >= requiredQuantity) or false;
	progress.character = nil;
	if Private.SealSavedRecord then
		Private.SealSavedRecord(progress, "criteriaAsset", tostring(criteriaType) .. ":" .. tostring(assetID), Resolvers.CriteriaAssetUsesAccountProgress(criteriaType, assetID), "quantity", "completed");
	end
	criteriaAssetProgress[criteriaType][assetID] = progress;
	return true;
end

criteriaTypeHandlers[CRITERIA_TYPE.REACH_LEVEL] = ResolvePlayerLevel;
criteriaTypeHandlers[CRITERIA_TYPE.KILL_NPC] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.EARN_ACHIEVEMENT] = ResolveAchievementCompleted;
criteriaTypeHandlers[CRITERIA_TYPE.QUESTS_COMPLETED] = ResolveTotalQuestsCompleted;
criteriaTypeHandlers[CRITERIA_TYPE.QUESTS_COMPLETED_IN_AREA] = ResolveCompletedQuestsInArea;
criteriaTypeHandlers[CRITERIA_TYPE.CURRENCY_GAINED] = Resolvers.ResolveCurrencyGained;
criteriaTypeHandlers[CRITERIA_TYPE.DAMAGE_DEALT] = function(context) return ResolveAssetCounter(context, "damage-dealt"); end;
criteriaTypeHandlers[CRITERIA_TYPE.DAILY_QUESTS_COMPLETED] = ResolveDailyQuestsCompleted;
criteriaTypeHandlers[CRITERIA_TYPE.COMPLETE_ANY_DAILY_QUEST_PER_DAY] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.COMPLETE_QUEST] = ResolveCompletedQuest;
criteriaTypeHandlers[CRITERIA_TYPE.RUN_INSTANCE_WITH_MAX_PLAYERS] = function(context) return ResolveAssetCounter(context, "run-instance-max-players"); end;
criteriaTypeHandlers[CRITERIA_TYPE.GET_KILLED_BY_CREATURE] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.DIE_TO_PLAYER] = function(context) return ResolveAssetCounter(context, "die-to-player"); end;
criteriaTypeHandlers[CRITERIA_TYPE.MAX_DISTANCE_FALLEN_WITHOUT_DYING] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.HAVE_SPELL_CAST_ON_YOU] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.CAST_SPELL] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.WORLD_STATE_UI_VALUE_MODIFIED] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.KILL_PLAYER_IN_AREA] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.WIN_ARENA] = function(context) return ResolveAssetCounter(context, "win-arena"); end;
criteriaTypeHandlers[CRITERIA_TYPE.COMPLETE_ANY_CHALLENGE_MODE] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.PARTICIPATE_IN_ARENA] = function(context) return ResolveAssetCounter(context, "participate-in-arena"); end;
criteriaTypeHandlers[CRITERIA_TYPE.HONORABLE_KILL] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.SKILL_RAISED] = ResolveSkillRaised;
criteriaTypeHandlers[CRITERIA_TYPE.LEARN_OR_KNOW_SPELL] = ResolveKnownSpell;
criteriaTypeHandlers[CRITERIA_TYPE.ACQUIRE_ITEM] = ResolveAcquireItem;
criteriaTypeHandlers[CRITERIA_TYPE.SKILL_STEP] = ResolveSkillStep;
criteriaTypeHandlers[CRITERIA_TYPE.LEARN_SPELL_FROM_SKILL_LINE] = ResolveSpellFromSkillLine;
criteriaTypeHandlers[CRITERIA_TYPE.LEARN_TRADESKILL_SKILL_LINE] = ResolveSpellFromSkillLine;
criteriaTypeHandlers[CRITERIA_TYPE.DEPRECATED_PVP_TITLES] = ResolveReachedPVPRank;
criteriaTypeHandlers[CRITERIA_TYPE.BANK_SLOTS_PURCHASED] = Resolvers.ResolveBankSlotsPurchased;
criteriaTypeHandlers[CRITERIA_TYPE.DIE_ON_MAP] = ResolveDeathsInArea;
criteriaTypeHandlers[CRITERIA_TYPE.DIE_ANYWHERE] = ResolveDieAnywhere;
criteriaTypeHandlers[CRITERIA_TYPE.DIE_IN_INSTANCE_WITH_MAX_PLAYERS] = ResolveDieInInstanceWithMaxPlayers;
criteriaTypeHandlers[CRITERIA_TYPE.PARTICIPATE_IN_BATTLEGROUND] = ResolveParticipateInBattleground;
criteriaTypeHandlers[CRITERIA_TYPE.WIN_BATTLEGROUND] = function(context) return ResolveAssetCounter(context, "win-battleground"); end;
criteriaTypeHandlers[CRITERIA_TYPE.DIE_TO_ENVIRONMENTAL_DAMAGE] = function(context) return ResolveAssetCounter(context, "die-to-environmental-damage"); end;
criteriaTypeHandlers[CRITERIA_TYPE.WIN_DUEL] = function(context) return ResolveAssetCounter(context, "win-duel"); end;
criteriaTypeHandlers[CRITERIA_TYPE.LOSE_DUEL] = function(context) return ResolveAssetCounter(context, "lose-duel"); end;
criteriaTypeHandlers[CRITERIA_TYPE.USE_ITEM] = ResolveUseItem;
criteriaTypeHandlers[CRITERIA_TYPE.LOOT_ITEM] = ResolveLootItem;
criteriaTypeHandlers[CRITERIA_TYPE.REVEAL_WORLD_MAP_OVERLAY] = ResolveRevealedWorldMapOverlay;
criteriaTypeHandlers[CRITERIA_TYPE.GOT_HAIRCUT] = function(context) return ResolveAssetCounter(context, "got-haircut"); end;
criteriaTypeHandlers[CRITERIA_TYPE.NEED_ROLL] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.GREED_ROLL] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.HEALING_DONE] = function(context) return ResolveAssetCounter(context, "healing-done"); end;
criteriaTypeHandlers[CRITERIA_TYPE.USE_GAME_OBJECT] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.COMPLETE_CHALLENGE_MODE_ON_MAP] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.GAIN_AURA] = Resolvers.ResolveGainAura;
criteriaTypeHandlers[CRITERIA_TYPE.CATCH_FISH_IN_POOL] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.PLAYER_TRIGGER_GAME_EVENT] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.LOGIN] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.KILLING_BLOW_TO_CLASS] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.KILLING_BLOW_TO_RACE] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.KILLING_BLOW] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.KILL_PLAYER_NO_HONOR_CHECK] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.KILL_ANY_NPC] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.WIN_RANKED_ARENA_MATCH] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.TEAM_ARENA_RATING] = function(context) return Resolvers.ResolveArenaRating(context, false); end;
criteriaTypeHandlers[CRITERIA_TYPE.PERSONAL_ARENA_RATING] = function(context) return Resolvers.ResolveArenaRating(context, true); end;
criteriaTypeHandlers[CRITERIA_TYPE.SELL_ITEMS_TO_VENDORS] = function(context) return ResolveAssetCounter(context, "sell-items-to-vendors"); end;
criteriaTypeHandlers[CRITERIA_TYPE.MONEY_SPENT_ON_RESPECS] = function(context) return ResolveAssetCounter(context, "money-spent-on-respecs"); end;
criteriaTypeHandlers[CRITERIA_TYPE.TOTAL_RESPECS] = function(context) return ResolveAssetCounter(context, "total-respecs"); end;
criteriaTypeHandlers[CRITERIA_TYPE.MONEY_EARNED_FROM_QUESTING] = function(context) return ResolveAssetCounter(context, "money-earned-from-questing"); end;
criteriaTypeHandlers[CRITERIA_TYPE.MONEY_SPENT_ON_TAXIS] = function(context) return ResolveAssetCounter(context, "money-spent-on-taxis"); end;
criteriaTypeHandlers[CRITERIA_TYPE.MONEY_SPENT_AT_BARBER] = function(context) return ResolveAssetCounter(context, "money-spent-at-barber"); end;
criteriaTypeHandlers[CRITERIA_TYPE.MONEY_SPENT_ON_POSTAGE] = function(context) return ResolveAssetCounter(context, "money-spent-on-postage"); end;
criteriaTypeHandlers[CRITERIA_TYPE.MONEY_LOOTED_FROM_CREATURES] = function(context) return ResolveAssetCounter(context, "money-looted-from-creatures"); end;
criteriaTypeHandlers[CRITERIA_TYPE.MONEY_EARNED_FROM_AUCTIONS] = function(context) return ResolveAssetCounter(context, "money-earned-from-auctions"); end;
criteriaTypeHandlers[CRITERIA_TYPE.AUCTION_ITEMS_POSTED] = function(context) return ResolveAssetCounter(context, "auction-items-posted"); end;
criteriaTypeHandlers[CRITERIA_TYPE.HIGHEST_AUCTION_BID] = function(context) return ResolveAssetCounter(context, "highest-auction-bid"); end;
criteriaTypeHandlers[CRITERIA_TYPE.AUCTIONS_WON] = function(context) return ResolveAssetCounter(context, "auctions-won"); end;
criteriaTypeHandlers[CRITERIA_TYPE.HIGHEST_ITEM_SOLD_VALUE] = function(context) return ResolveAssetCounter(context, "highest-item-sold-value"); end;
criteriaTypeHandlers[CRITERIA_TYPE.MOST_MONEY_OWNED] = Resolvers.ResolveMostMoneyOwned;
criteriaTypeHandlers[CRITERIA_TYPE.LOOT_ANY_ITEM] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.OBTAIN_ANY_ITEM] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.ROLL_ANY_NEED] = function(context) return ResolveAssetCounter(context, "roll-any-need"); end;
criteriaTypeHandlers[CRITERIA_TYPE.ROLL_ANY_GREED] = function(context) return ResolveAssetCounter(context, "roll-any-greed"); end;
criteriaTypeHandlers[CRITERIA_TYPE.ACCOUNT_KNOWS_PET] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.DEFEAT_ENCOUNTER_WHILE_ELIGIBLE_FOR_LOOT] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.HIGHEST_DAMAGE_IN_SINGLE_ABILITY] = function(context) return ResolveAssetCounter(context, "highest-damage-single-ability"); end;
criteriaTypeHandlers[CRITERIA_TYPE.MOST_DAMAGE_TAKEN_IN_SINGLE_HIT] = function(context) return ResolveAssetCounter(context, "most-damage-taken-single-hit"); end;
criteriaTypeHandlers[CRITERIA_TYPE.TOTAL_DAMAGE_TAKEN] = function(context) return ResolveAssetCounter(context, "total-damage-taken"); end;
criteriaTypeHandlers[CRITERIA_TYPE.LARGEST_HEAL_CAST] = function(context) return ResolveAssetCounter(context, "largest-heal-cast"); end;
criteriaTypeHandlers[CRITERIA_TYPE.TOTAL_HEALING_RECEIVED] = function(context) return ResolveAssetCounter(context, "total-healing-received"); end;
criteriaTypeHandlers[CRITERIA_TYPE.LARGEST_HEAL_RECEIVED] = function(context) return ResolveAssetCounter(context, "largest-heal-received"); end;
criteriaTypeHandlers[CRITERIA_TYPE.ABANDON_ANY_QUEST] = function(context) return ResolveAssetCounter(context, "abandon-any-quest"); end;
criteriaTypeHandlers[CRITERIA_TYPE.BUY_TAXI] = function(context) return ResolveAssetCounter(context, "buy-taxi"); end;
criteriaTypeHandlers[CRITERIA_TYPE.GET_LOOT_BY_ACQUISITION] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.LAND_TARGETED_SPELL] = ResolveSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.HONORABLE_KILLS_LOGIN_COUNTER] = Resolvers.ResolveHonorableKills;
criteriaTypeHandlers[CRITERIA_TYPE.ACCEPT_SUMMON] = function(context) return ResolveAssetCounter(context, "accept-summon"); end;
criteriaTypeHandlers[CRITERIA_TYPE.EARN_ACHIEVEMENT_POINTS] = Resolvers.ResolveAchievementPoints;
criteriaTypeHandlers[CRITERIA_TYPE.DISENCHANT_ROLL] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.ROLL_ANY_DISENCHANT] = function(context) return ResolveAssetCounter(context, "roll-any-disenchant"); end;
criteriaTypeHandlers[CRITERIA_TYPE.COMPLETE_LFG_DUNGEON] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.COMPLETE_LFG_DUNGEON_WITH_STRANGERS] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.DEFEAT_ENCOUNTER] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.REPUTATION_GAINED] = ResolveReputationGained;
criteriaTypeHandlers[CRITERIA_TYPE.TOTAL_EXALTED_FACTIONS] = ResolveTotalExaltedFactions;
criteriaTypeHandlers[CRITERIA_TYPE.EQUIP_ITEM] = ResolveEquipItem;
criteriaTypeHandlers[CRITERIA_TYPE.EQUIP_ITEM_IN_SLOT] = ResolveEquipItemInSlot;
criteriaTypeHandlers[CRITERIA_TYPE.QUESTS_COMPLETED_IN_SORT] = ResolveCompletedQuestsInSort;
criteriaTypeHandlers[CRITERIA_TYPE.EMOTE] = ResolveEmote;
criteriaTypeHandlers[CRITERIA_TYPE.TOTAL_REVERED_FACTIONS] = ResolveTotalReveredFactions;
criteriaTypeHandlers[CRITERIA_TYPE.TOTAL_HONORED_FACTIONS] = ResolveTotalHonoredFactions;
criteriaTypeHandlers[CRITERIA_TYPE.TOTAL_FACTIONS_ENCOUNTERED] = ResolveTotalFactionsEncountered;
criteriaTypeHandlers[CRITERIA_TYPE.EARN_LICENSE] = Resolvers.ResolveSimpleSavedProgress;
criteriaTypeHandlers[CRITERIA_TYPE.TRACKING_QUEST_COMPLETED] = ResolveCompletedQuest;

criteriaTreeOperatorHandlers[CRITERIA_TREE_OPERATOR.SINGLE] = ResolveSingle;
criteriaTreeOperatorHandlers[CRITERIA_TREE_OPERATOR.SINGLE_NOT_COMPLETED] = ResolveSingleNotCompleted;
criteriaTreeOperatorHandlers[CRITERIA_TREE_OPERATOR.ALL] = function(context)
	return ResolveCompletedChildCount(context, true, "all-children");
end;
criteriaTreeOperatorHandlers[CRITERIA_TREE_OPERATOR.SUM_CHILDREN] = ResolveSumChildren;
criteriaTreeOperatorHandlers[CRITERIA_TREE_OPERATOR.MAX_CHILD] = ResolveMaxChild;
criteriaTreeOperatorHandlers[CRITERIA_TREE_OPERATOR.COUNT_DIRECT_CHILDREN] = function(context)
	return ResolveCompletedChildCount(context, false, "count-direct-children");
end;
criteriaTreeOperatorHandlers[CRITERIA_TREE_OPERATOR.ANY] = ResolveAnyChild;
criteriaTreeOperatorHandlers[CRITERIA_TREE_OPERATOR.SUM_CHILDREN_WEIGHT] = ResolveSumChildrenWeight;

Achievements.ResolveCriteriaTree = Resolvers.ResolveCriteriaTree;
Achievements.RegisterQuestAreaQuests = Resolvers.RegisterQuestAreaQuests;
Achievements.RegisterQuestSortQuests = Resolvers.RegisterQuestSortQuests;
Achievements.HandleCombatLogCriteria = HandleCombatLogCriteria;
Achievements.RecordUsedItem = RecordUsedItemID;
Achievements.RecordPlayerDeath = RecordPlayerDeath;
Achievements.RecordBattlegroundParticipation = RecordBattlegroundParticipation;
Achievements.RecordBattlegroundWin = RecordBattlegroundWin;
Achievements.RecordArenaParticipation = Resolvers.RecordArenaParticipation;
Achievements.RecordArenaWin = Resolvers.RecordArenaWin;
Achievements.RecordLoginCriteria = Resolvers.RecordLoginCriteria;
Achievements.RecordCurrencyScan = Resolvers.RecordCurrencyScan;
Achievements.RecordPlayerSpellcast = Resolvers.RecordPlayerSpellcast;
Achievements.RecordLootAcquisitionCriteria = Resolvers.RecordLootAcquisitionCriteria;
Achievements.RecordMoneyChatCriteria = Resolvers.RecordMoneyChatCriteria;
Achievements.RecordMailboxAuctionCriteria = Resolvers.RecordMailboxAuctionCriteria;
Achievements.RecordGameObjectTextCriteria = Resolvers.RecordGameObjectTextCriteria;
Achievements.RecordInstanceRun = Resolvers.RecordInstanceRun;
Achievements.RecordEncounterDefeat = Resolvers.RecordEncounterDefeat;
Achievements.RecordPlayerMoneySnapshot = Resolvers.RecordPlayerMoneySnapshot;
Achievements.RecordBarberShopCriteria = Resolvers.RecordBarberShopCriteria;
Achievements.BackfillCurrentState = Resolvers.BackfillCurrentState;
Achievements.hookSimpleActionCriteria = Resolvers.HookSimpleActionCriteria;
Achievements.RecordDuelOutcomeFromSystemMessage = RecordDuelOutcomeFromSystemMessage;
Achievements.RecordCriteriaStart = Resolvers.RecordCriteriaStart;
Achievements.RecordCriteriaFail = Resolvers.RecordCriteriaFail;
if Resolvers.DebugEvaluateAllAchievements then
	Achievements.DebugEvaluateAllAchievements = Resolvers.DebugEvaluateAllAchievements;
end
Achievements.RecordQuestAccepted = Resolvers.RecordQuestAccepted;
Achievements.RecordQuestTurnedIn = Resolvers.RecordQuestTurnedIn;
Achievements.RecordDailyQuestResetCheck = Resolvers.RecordDailyQuestResetCheck;
Achievements.RecordPlayerAuraCriteria = Resolvers.RecordPlayerAuraCriteria;
Achievements.RecordDualTalentSpecializationCriteria = Resolvers.RecordDualTalentSpecializationCriteria;
Achievements.hookItemUseCriteria = HookItemUseCriteria;
Achievements.RecordEmoteCriteria = RecordEmoteCriteria;
Achievements.hookEmoteCriteria = HookEmoteCriteria;
Achievements.RecordEquippedItemSlot = Resolvers.RecordEquippedItemSlot;
Achievements.RecordWorldStateScan = Resolvers.RecordWorldStateScan;
Achievements.RecordBattlegroundWorldStateMessage = Resolvers.RecordBattlegroundWorldStateMessage;
Achievements.RecordLFGState = Resolvers.RecordLFGState;
Achievements.ClearQuestCompletionCache = ClearCompletedQuestLookup;
Achievements.ClearExplorationCache = ClearExploredWorldMapOverlayCache;
Achievements.ClearCharacterScanCache = ClearCharacterScanCache;
Achievements.CountCompletedQuestsInArea = CountCompletedQuestsInArea;
Achievements.CountCompletedQuestsInSort = CountCompletedQuestsInSort;
Achievements.SetCriteriaProgress = Resolvers.SetCriteriaProgress;
Achievements.IncrementCriteriaProgress = Resolvers.IncrementCriteriaProgress;
Achievements.SetCriteriaAssetProgress = Resolvers.SetCriteriaAssetProgress;
Achievements.IncrementCriteriaAssetProgress = Resolvers.IncrementCriteriaAssetProgress;