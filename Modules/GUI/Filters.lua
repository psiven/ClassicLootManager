-- ------------------------------- --
local  _, CLM = ...
-- ------ CLM common cache ------- --
-- local LOG       = CLM.LOG
local CONSTANTS = CLM.CONSTANTS
local UTILS     = CLM.UTILS
-- ------------------------------- --

---------------------------------
-- Filter is breaking MVC rule --
---------------------------------

local setmetatable = setmetatable
local ipairs, tonumber, tostring = ipairs, tonumber, tostring
local sfind, strlower, strlen = string.find, strlower, strlen

local filterInstanceId = 1

local Filters = {}
function Filters:New(
    refreshFn,
    useClass,
    useInRaid, useInStandby,
    useInGuild, useExternal,
    useMain,
    useOnline,
    addButtons,
    useSearch,
    prefix, filterOrderStartOffset)

    local o = {}

    setmetatable(o, self)
    self.__index = self

    o.useClass = useClass
    o.useInRaid = useInRaid
    o.useInStandby = useInStandby
    o.useInGuild = useInGuild
    o.useExternal = useExternal
    o.useMain = useMain
    o.useOnline = useOnline
    o.addButtons = addButtons
    o.useSearch = useSearch
    o.filterOrderStartOffset = tonumber(filterOrderStartOffset) or 0
    o.prefix = tostring(prefix or "filter") .. tostring(filterInstanceId)
    o.refreshFn = refreshFn

    o.filters = {}

    filterInstanceId = filterInstanceId + 1

    return o
end

CONSTANTS.FILTER = {
    IN_RAID      = 100,
    ONLINE       = 101,
    STANDBY      = 102,
    IN_GUILD     = 103,
    NOT_IN_GUILD = 104,
    MAINS_ONLY   = 105,
}

CONSTANTS.FILTERS_GUI = {
    [CONSTANTS.FILTER.IN_RAID] = CLM.L["In Raid"],
    [CONSTANTS.FILTER.ONLINE] = CLM.L["Online"],
    [CONSTANTS.FILTER.STANDBY] = CLM.L["Standby"],
    [CONSTANTS.FILTER.IN_GUILD] = CLM.L["In Guild"],
    [CONSTANTS.FILTER.NOT_IN_GUILD] = CLM.L["External"],
    [CONSTANTS.FILTER.MAINS_ONLY] = CLM.L["Mains"]
}

local color = "FFD100"
local parameterToConstantMap = {
    useInRaid = CONSTANTS.FILTER.IN_RAID,
    useInStandby = CONSTANTS.FILTER.STANDBY,
    useInGuild = CONSTANTS.FILTER.IN_GUILD,
    useExternal = CONSTANTS.FILTER.NOT_IN_GUILD,
    useMain = CONSTANTS.FILTER.MAINS_ONLY,
    useOnline = CONSTANTS.FILTER.ONLINE
}

local function SelectClasses(self, isSelect)
    for i=1,10 do
        self.filters[i] = isSelect and true or false
    end
end

local function HandleMutualExclusiveOptions(self, filterId, valueToSet)
    if not valueToSet then return end
    if filterId == CONSTANTS.FILTER.IN_RAID then
        self.filters[CONSTANTS.FILTER.STANDBY] = false
    elseif filterId == CONSTANTS.FILTER.STANDBY then
        self.filters[CONSTANTS.FILTER.IN_RAID] = false
    end
    if filterId == CONSTANTS.FILTER.IN_GUILD then
        self.filters[CONSTANTS.FILTER.NOT_IN_GUILD] = false
    elseif filterId == CONSTANTS.FILTER.NOT_IN_GUILD then
        self.filters[CONSTANTS.FILTER.IN_GUILD] = false
    end
end

local function GetSearchFunction(searchList)
    return (function(input)
        for _, searchString in ipairs(searchList) do
            searchString = UTILS.Trim(searchString)
            if strlen(searchString) >= 3 then
                searchString = ".*" .. strlower(searchString) .. ".*"
                if(sfind(strlower(input), searchString)) then
                    return true
                end
            end
        end
        return false
    end)
end

function Filters:GetAceOptions()
    if self.options then return self.options end
    local options = {}
    local filters = {}

    if self.useClass then
        UTILS.mergeDictsInline(filters, UTILS.ShallowCopy(UTILS.GetColorCodedClassList()))
        SelectClasses(self, true)
    else
        SelectClasses(self, false)
    end

    for param, constant in pairs(parameterToConstantMap) do
        if self[param] then
            filters[constant] = UTILS.ColorCodeText(CONSTANTS.FILTERS_GUI[constant], color)
        else
            self.filters[constant] = false
        end
    end

    -- Header
    local order = self.filterOrderStartOffset
    -- options[self.prefix .. "header"] = {
    --     type = "header",
    --     name = CLM.L["Filtering"],
    --     order = order
    -- }
    -- order = order + 1
    -- Filters
    options[self.prefix .. "display"] = {
        name = CLM.L["Filter"],
        type = "multiselect",
        set = function(i, k, valueToSet)
            local filterId = tonumber(k) or 0
            self.filters[filterId] = valueToSet
            HandleMutualExclusiveOptions(self, filterId, valueToSet)
            self.refreshFn(true)
        end,
        get = function(i, v) return self.filters[tonumber(v)] end,
        values = filters,
        disabled = function() return self.searchFunction and true or false end,
        order = order
    }
    order = order + 1
    if self.addButtons and self.useClass then
        options[self.prefix .. "select_all"] = {
            name = CLM.L["All"],
            desc = CLM.L["Select all classes."],
            type = "execute",
            func = (function()
                SelectClasses(self, true)
                self.refreshFn(true)
            end),
            disabled = function() return self.searchFunction and true or false end,
            width = 0.575,
            order = order,
        }
        order = order + 1
        options[self.prefix .. "select_none"] = {
            name = CLM.L["None"],
            desc = CLM.L["Clear all classes."],
            type = "execute",
            func = (function()
                SelectClasses(self, false)
                self.refreshFn(true)
            end),
            disabled = function() return self.searchFunction and true or false end,
            width = 0.575,
            order = order,
        }
        order = order + 1
    end
    if self.useSearch then
        options[self.prefix .. "search"] = {
            name = CLM.L["Search"],
            desc = CLM.L["Search for player names. Separate multiple with a comma ','. Minimum 3 characters. Overrides filtering."],
            type = "input",
            set = (function(i, v)
                self.searchString = v
                if v and strlen(v) >= 3 then
                    self.searchFunction = GetSearchFunction({ strsplit(",", v) })
                else
                    self.searchFunction = nil
                end
                self.refreshFn(true)
            end),
            get = (function(i) return self.searchString end),
            width = "full",
            order = order,
        }
    end

    self.options = options
    return options
end

function Filters:Filter(playerName, playerClass, searchFieldsList)

    -- Check Search first, discard others
    if self.searchFunction then
        local searchResult = false
        for _, field in ipairs(searchFieldsList) do
            searchResult = searchResult or self.searchFunction(field)
        end
        return searchResult
    end

    local status = true
    if self.useClass then
        for id, _class in pairs(UTILS.GetColorCodedClassList()) do
            if playerClass == _class then
                status = self.filters[id]
            end
        end
    end

    if self.useInRaid and self.filters[CONSTANTS.FILTER.IN_RAID] then
        local isInRaid = {}
        for i=1,MAX_RAID_MEMBERS do
            local name = GetRaidRosterInfo(i)
            if name then
                name = UTILS.RemoveServer(name)
                isInRaid[name] = true
            end
        end
        status = status and isInRaid[playerName]
    elseif self.useInStandby and self.filters[CONSTANTS.FILTER.STANDBY] then
        if CLM.MODULES.RaidManager:IsInProgressingRaid() then
            local profile = CLM.MODULES.ProfileManager:GetProfileByName(playerName)
            if profile then
                status = status and CLM.MODULES.RaidManager:GetRaid():IsPlayerOnStandby(profile:GUID())
            end
        elseif CLM.MODULES.RaidManager:IsInCreatedRaid() then
            local profile = CLM.MODULES.ProfileManager:GetProfileByName(playerName)
            if profile then
                status = status and CLM.MODULES.StandbyStagingManager:IsPlayerOnStandby(CLM.MODULES.RaidManager:GetRaid():UID(), profile:GUID())
            end
        else
            status = false
        end
    end

    if self.useMain and self.filters[CONSTANTS.FILTER.MAINS_ONLY] then
        local profile = CLM.MODULES.ProfileManager:GetProfileByName(playerName)
        if profile then
            status = status and (profile:Main() == "")
        end
    end
    if self.useExternal and self.filters[CONSTANTS.FILTER.NOT_IN_GUILD] then
        status = status and not CLM.MODULES.GuildInfoListener:GetGuildies()[playerName]
    end
    if self.useInGuild and self.filters[CONSTANTS.FILTER.IN_GUILD] then
        status = status and CLM.MODULES.GuildInfoListener:GetGuildies()[playerName]
    end
    return status
end

CLM.MODELS.Filters = Filters