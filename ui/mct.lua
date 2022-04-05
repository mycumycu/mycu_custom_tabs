local ffi = require("ffi")
local C = ffi.C
local Lib = require("extensions.sn_mod_support_apis.lua_interface").Library
local mapMenu

local isDebug = false
local playerId = ConvertStringTo64Bit(tostring(C.GetPlayerID()))

local orygnalInfoTableData = {}
local shouldUpdate = true

local mct = {}

local blackboard = {
    configName = "$customTabsConfig",
    dataName = "$customTabsData",
    contextAction = "$customTabsContextAction",
}

local tabsConfig = {}

local tabsObjectList = {
    {},
    {},
    {},
}

local function init ()
    mct.debugText("INIT")

    mapMenu = Lib.Get_Egosoft_Menu("MapMenu")

    mapMenu.registerCallback("createPropertyOwned_on_start", mct.buildTabs)
    mapMenu.registerCallback("createPropertyOwned_on_add_other_objects_infoTableData", mct.createPropertyOwned_on_add_other_objects_infoTableData)
    mapMenu.registerCallback("createPropertyOwned_on_createPropertySection_unassignedships", mct.createPropertyOwned_on_createPropertySection_unassignedships)
    mapMenu.registerCallback("onRenderTargetSelect_on_propertyowned_newmode", mct.onRenderTargetSelect_on_propertyowned_newmode)

    RegisterEvent("mct.customTabsAction", mct.customTabsAction)
    RegisterEvent("mct.updateConfig", mct.refreshConfig)
    RegisterEvent("mct.resetData", mct.resetData)

    -- read stored data
    tabsObjectList = GetNPCBlackboard(playerId, blackboard.dataName) or { {}, {}, {} }
    mct.refreshConfig()
end

--
--
--
function mct.createPropertyOwned_on_createPropertySection_unassignedships(numdisplayed, instance, ftable, infoTableData)
    mct.debugText("createPropertyOwned_on_createPropertySection_unassignedships")
    numdisplayed = mct.fillCustomTab(numdisplayed, instance, ftable)

    return { numdisplayed = numdisplayed }
end

--
-- Open the corresponding tab when the user selects an object
--
function mct.onRenderTargetSelect_on_propertyowned_newmode(pickedcomponent64, newmode)
    mct.debugText("pickedcomponent64", pickedcomponent64)

    local elementPosition = mct.findInObjectTable(pickedcomponent64)
    if (elementPosition) then
        newmode = "custom_tab_" .. tostring(elementPosition.group)
    end

    return { newmode = newmode }
end

--
-- Filter data before passing it to property menu
--
function mct.createPropertyOwned_on_add_other_objects_infoTableData(infoTableData)
    mct.refreshConfig()

    orygnalInfoTableData = mct.deepCopy(infoTableData)

    return { infoTableData = mct.filterInfoTableData(nil) }
end

--
-- Build custom tabs
--
function mct.buildTabs(mapMenuConfig)

    for i = #mapMenuConfig.propertyCategories, 1, -1 do
        local propertyCategory = mapMenuConfig.propertyCategories[i]
        if string.sub(propertyCategory.category, 1, 10) == "custom_tab" then
            if (shouldUpdate) then
                table.remove(mapMenuConfig.propertyCategories, i)
            else
                customTabsExists = true
            end
        end
    end

    if not customTabsExists then
        mct.debugText("not customTabsExists")

        local initialPosition = tabsConfig.position
        -- there's no need to change anything for positions 1 and 2
        if (tabsConfig.position == 3) then
            initialPosition = #mapMenuConfig.propertyCategories + 1
        end

        for index = 1, tabsConfig.number do
            local name = "tabName" .. index
            local icon = "tabIcon" .. index
            local customTabCategory = {
                category = "custom_tab_" .. index,
                name = tabsConfig[name],
                icon = tabsConfig[icon],
            }
            mct.printTable(customTabCategory)

            table.insert(mapMenuConfig.propertyCategories, (initialPosition + index - 1), customTabCategory)
        end
    end

    -- do not update on next run until user changes settings
    shouldUpdate = false
end

--
--
--
function mct.customTabsAction(_, params)
    local data = GetNPCBlackboard(playerId, blackboard.contextAction) or {}

    local action = data.actionId
    local objects = data.objects

    mct.printTable(objects)
    for _, object in ipairs(objects) do
        object64 = ConvertIDTo64Bit(object)
        local isValidComponent = IsValidComponent(object64)
        local isPlayerOwned = GetComponentData(object64, "isplayerowned")
        local isShip = C.IsRealComponentClass(object64, "ship")
        local isStation = C.IsRealComponentClass(object64, "station")

        if (isValidComponent and isPlayerOwned and (isShip or isStation)) then
            if (string.sub(action, 1, 13) == 'remove_custom') then
                mct.removeObject(object64)
            end
            if (string.sub(action, 1, 10) == 'add_custom') then
                local tabIndex = tonumber(string.sub(action, -1))
                mct.addObject(tabIndex, object64)
            end
        end
    end

    -- remove focus
    mapMenu.clearSelectedComponents()

    -- clear context data
    SetNPCBlackboard(playerId, blackboard.contextAction, nil)

    -- store object list data
    SetNPCBlackboard(playerId, blackboard.dataName, tabsObjectList)

    mapMenu.refreshInfoFrame()
end

--
-- Add element to objects table
--
function mct.addObject(tabIndex, object64)
    -- remove first if exists
    mct.removeObject(object64)

    -- add object
    if mapMenu.isObjectValid(object64) then
        table.insert(tabsObjectList[tabIndex], ConvertStringToLuaID(tostring(object64)))
    end

    -- add also subordinates
    local subordinates = mct.getSubordinates(object64)
    for i = 1, #subordinates do
        table.insert(tabsObjectList[tabIndex], ConvertStringToLuaID(tostring(subordinates[i])))
    end
end

--
-- Remove object from table
--
function mct.removeObject(object64)
    mct.removeFromObjectTable(object64)

    -- remove also subordinates
    local subordinates = mct.getSubordinates(object64)
    for i = 1, #subordinates do
        mct.removeFromObjectTable(subordinates[i])
    end

end

--
-- Get object's valid subordinates
--
function mct.getSubordinates(object64)
    local subordinates = {}
    if C.IsComponentClass(object64, "controllable") then
        subordinates = GetSubordinates(object64)
    end
    for i = #subordinates, 1, -1 do
        local subordinate = subordinates[i]
        if not mapMenu.isObjectValid(ConvertIDTo64Bit(subordinate)) then
            table.remove(subordinates, i)
        end
    end

    return subordinates
end

--
-- Check if object exists in objects table
--
function mct.findInObjectTable(object, customTabMode)
    customTabMode = customTabMode or nil

    for group, tabGroup in pairs(tabsObjectList) do
        for index, element in pairs(tabGroup) do
            if (ConvertIDTo64Bit(element) == ConvertIDTo64Bit(object) and (not customTabMode or customTabMode == group)) then
                return {
                    group = group,
                    index = index
                }
            end
        end
    end
    return false
end

--
--
--
function mct.removeFromObjectTable(object64)
    local elementPosition = mct.findInObjectTable(object64);
    if (elementPosition) then
        table.remove(tabsObjectList[elementPosition.group], elementPosition.index)
    end
end

--
-- Split given string and split using ";" as separator
--
function mct.parseParams(params)
    local output = {}

    for token in (params):gmatch("[^;]+") do
        table.insert(output, token)
    end

    return unpack(output)
end

--
-- Update tabs config data and mark for redraw
--
function mct.refreshConfig()
    tabsConfig = GetNPCBlackboard(playerId, blackboard.configName) or {}

    mct.trimObjectList()

    -- mark that user changed config
    shouldUpdate = true
end

--
-- Trim object list if there are no enough tabs enabled
--
function mct.trimObjectList()
    for i = #tabsObjectList, 1, -1 do
        if (i > tabsConfig.number) then
            mct.debugText("Trimming tabsObjects index", i)
            tabsObjectList[i] = {}
        end
    end
end

--
--
--
function mct.filterInfoTableData(customTabMode)
    local infoTableData = mct.deepCopy(orygnalInfoTableData)

    -- skip those nodes
    local excluded = {
        deployables = true,
        inventoryShips = true,
        constructionShips = true,
        constructionShips = true,
        shipIconWidth = true,
    }

    for category, elements in pairs(infoTableData) do
        if (type(elements) == "table" and not excluded[category]) then
            for i = #elements, 1, -1 do
                object = ConvertStringTo64Bit(tostring(elements[i]))
                if (mct.findInObjectTable(object) and not customTabMode) or (not mct.findInObjectTable(object, customTabMode) and customTabMode) then
                    if (customTabMode or tabsConfig.mode == 'move') then
                        table.remove(infoTableData[category], i)
                    end
                end
            end

        end
    end

    return infoTableData
end

--
-- Fill custom tabs with data
--
function mct.fillCustomTab(numdisplayed, instance, ftable)
    local mode;

    if string.sub(mapMenu.propertyMode, 1, 10) == "custom_tab" then
        mode = tonumber(string.sub(mapMenu.propertyMode, -1))
    end

    if (mode) then
        local infoTableData = mct.filterInfoTableData(mode)

        if (#infoTableData.stations > 0) then
            numdisplayed = mapMenu.createPropertySection(instance, "ownedstations", ftable, ReadText(1001, 8379), infoTableData.stations, "-- " .. ReadText(1001, 33) .. " --", mapMenu.mode ~= "hire", numdisplayed, nil, mapMenu.propertySorterType)
        end
        if (#infoTableData.fleetLeaderShips > 0) then
            numdisplayed = mapMenu.createPropertySection(instance, "ownedfleets", ftable, ReadText(1001, 8326), infoTableData.fleetLeaderShips, "-- " .. ReadText(1001, 34) .. " --", nil, numdisplayed, nil, mapMenu.propertySorterType)
        end
        if (#infoTableData.unassignedShips > 0) then
            numdisplayed = mapMenu.createPropertySection(instance, "ownedships", ftable, ReadText(1001, 8327), infoTableData.unassignedShips, "-- " .. ReadText(1001, 34) .. " --", nil, numdisplayed, nil, mapMenu.propertySorterType)
        end
        mapMenu.createConstructionSection(instance, "constructionships", ftable, ReadText(1001, 8328), infoTableData.constructionShips)
    end

    return numdisplayed
end

--
-- Moves all assets back to global property tab
-- Action raised by a config option
--
function mct.resetData()
    tabsObjectList = {
        {},
        {},
        {},
    }
end

function mct.deepCopy(original)
    local copy
    if type(original) == 'table' then
        copy = {}
        for key, value in next, original, nil do
            copy[mct.deepCopy(key)] = mct.deepCopy(value)
        end
    else
        -- number, string, boolean, etc
        copy = original
    end
    return copy
end

function mct.debugText(title, text)
    if (isDebug) then
        DebugError("mct.lua: " .. title .. ": " .. tostring(text))
    end
end

function mct.printTable(table)
    if (isDebug) then
        Lib.Print_Table(table)
    end
end

init()
