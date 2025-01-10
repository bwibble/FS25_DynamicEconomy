DynamicEconomy = {}

local annualProfitCap = 75000
local increaseCap = 1.2
local decreaseCap = 0.4
local gracePeriod = 4

DynamicEconomyEvent = {}
local DynamicEconomyEvent_mt = Class(DynamicEconomyEvent, Event)
InitEventClass(DynamicEconomyEvent, "DynamicEconomyEvent")

function DynamicEconomyEvent.emptyNew()
    local self = Event.new(DynamicEconomyEvent_mt)
    return self
end

function DynamicEconomyEvent.new(subTypeName, subTypeFactor)
    local self = DynamicEconomyEvent.emptyNew()
    self.subTypeName = subTypeName
    self.subTypeFactor = subTypeFactor
    return self
end

function DynamicEconomyEvent:readStream(streamId, connection)
    self.subTypeName = streamReadString(streamId)
    self.subTypeFactor = streamReadFloat32(streamId)
    self:run(connection)
end

function DynamicEconomyEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.subTypeName)
	streamWriteFloat32(streamId, self.subTypeFactor)
end

function DynamicEconomyEvent:run(connection)
    if not connection:getIsServer() then
        DynamicEconomy.subTypeFactors[self.subTypeName] = self.subTypeFactor
    end
end

local function broadcastSubTypeFactors()
    for subTypeName, subTypeFactor in pairs(DynamicEconomy.subTypeFactors) do
        g_client:getServerConnection():sendEvent(
            DynamicEconomyEvent.new(subTypeName, subTypeFactor)
        )
    end 
end

local function catchSubTypeSale(sellerInfo, func, ...)
    if sellerInfo.sellPrice then
        local clusterId = sellerInfo.clusterId
        local subTypeIndex = sellerInfo.object:getClusterById(clusterId).subTypeIndex
        local subTypeName = g_currentMission.animalSystem.subTypes[subTypeIndex].name
        if not DynamicEconomy.subTypes[subTypeName] then
            populateMissingProducts()
        end

        local subType = DynamicEconomy.subTypes[subTypeName]
        subType.recentSold = subType.recentSold + sellerInfo.sellPrice
        subType.gracePeriod = gracePeriod
    end

    return func(sellerInfo, ...)
end

local function catchFillTypeSale(_, _, amountLiters, fillTypeIndex)
    local fillTypeName = g_fillTypeManager.indexToName[fillTypeIndex]
    if not DynamicEconomy.fillTypes[fillTypeName] then
        populateMissingProducts()
    end

    local fillType = DynamicEconomy.fillTypes[fillTypeName]
    fillType.recentSold = fillType.recentSold + amountLiters
    fillType.gracePeriod = gracePeriod
end

local function repriceSubType(subTypeName)

    local function reprice(sellerInfo, func, ...)
        local price = func(sellerInfo, ...)
        return price * math.min(increaseCap, math.max(decreaseCap, DynamicEconomy.subTypeFactors[subTypeName]))
    end

    return reprice
end

local function repriceFillType(sellerInfo, func, fillTypeIndex, ...)
    local fillTypeName = g_fillTypeManager.indexToName[fillTypeIndex]
    local fillTypeFactor = DynamicEconomy.fillTypeFactors[fillTypeName]
    if not fillTypeFactor then
        populateMissingProducts()
        return func(sellerInfo, fillTypeIndex, ...)
    end

    return func(sellerInfo, fillTypeIndex, ...) * math.min(increaseCap, math.max(decreaseCap, fillTypeFactor))
end

local function populateMissingProducts()
    for _, fillType in pairs(g_fillTypeManager:getFillTypes()) do
        local newFillType = {
            name = fillType.name,
            recentSold = 0,
            factor = increaseCap + 1,
            basePrice = fillType.pricePerLiter,
            gracePeriod = 0
        }
        if not DynamicEconomy.fillTypes[fillType.name] then
            DynamicEconomy.fillTypes[fillType.name] = newFillType
        end
    end

    DynamicEconomy.capturedSubTypes = DynamicEconomy.capturedSubTypes or {}
    for _, subType in pairs(g_currentMission.animalSystem.subTypes) do
        local newSubType = {
            name = subType.name,
            recentSold = 0,
            factor = increaseCap + 1,
            gracePeriod = 0
        }
        if not DynamicEconomy.subTypes[subType.name] then
            DynamicEconomy.subTypes[subType.name] = newSubType
        end

        if not DynamicEconomy.capturedSubTypes[subType.name] then
            subType.sellPrice.interpolator = Utils.overwrittenFunction(subType.sellPrice.interpolator, repriceSubType(subType.name))
        end

        DynamicEconomy.capturedSubTypes[subType.name] = true
    end

    DynamicEconomy.fillTypeFactors = {}
    for _, fillType in pairs(DynamicEconomy.fillTypes) do
        DynamicEconomy.fillTypeFactors[fillType.name] = fillType.factor
    end

    DynamicEconomy.subTypeFactors = {}
    for _, subType in pairs(DynamicEconomy.subTypes) do
        DynamicEconomy.subTypeFactors[subType.name] = subType.factor
    end
end

local function loadXML()
    DynamicEconomy.fillTypes = {}
    DynamicEconomy.subTypes = {}
    if not g_currentMission:getIsServer() then
        return populateMissingProducts()
    end

    local XMLPath = g_modSettingsDirectory.."DynamicEconomy.xml"
    local xmlId = 0
    if fileExists(XMLPath) then
        xmlId = loadXMLFile("DynamicEconomyXML", XMLPath)
    else
        xmlId = createXMLFile("DynamicEconomyXML", XMLPath, "DynamicEconomyXML")
    end

    local savegamePath = "DynamicEconomy.savegame"..tostring(g_currentMission.missionInfo.savegameIndex)
    if not g_currentMission.missionInfo.savegameDirectory and hasXMLProperty(xmlId, savegamePath) then
        removeXMLProperty(xmlId, savegamePath)
    end

    local index = 0
    while hasXMLProperty(xmlId, savegamePath..".fillTypes.fillType("..tostring(index)..")") do
        local fillTypePath = savegamePath..".fillTypes.fillType("..tostring(index)..")"
        local fillType = {
            name =          getXMLString(   xmlId, fillTypePath.."#name"),
            recentSold =    getXMLFloat(    xmlId, fillTypePath.."#recentSold"),
            factor =        getXMLFloat(    xmlId, fillTypePath.."#factor"),
            basePrice =     getXMLFloat(    xmlId, fillTypePath.."#basePrice"),
            gracePeriod =   getXMLInt(      xmlId,  fillTypePath.."#gracePeriod")
        }
        DynamicEconomy.fillTypes[fillType.name] = fillType
        index = index + 1
    end

    index = 0
    while hasXMLProperty(xmlId, savegamePath..".subTypes.subType("..tostring(index)..")") do
        local subTypePath = savegamePath..".subTypes.subType("..tostring(index)..")"
        local subType = {
            name =          getXMLString(   xmlId, subTypePath.."#name"),
            recentSold =    getXMLFloat(    xmlId, subTypePath.."#recentSold"),
            factor =        getXMLFloat(    xmlId, subTypePath.."#factor"),
            gracePeriod =   getXMLInt(      xmlId, subTypePath.."#gracePeriod")
        }
        DynamicEconomy.subTypes[subType.name] = subType
        index = index + 1
    end

    saveXMLFile(xmlId)
    delete(xmlId)
    return populateMissingProducts()
end

local function saveXML()
    if not g_currentMission:getIsServer() then return end

    local XMLPath = g_modSettingsDirectory.."DynamicEconomy.xml"
    local xmlId = 0
    if fileExists(XMLPath) then
        xmlId = loadXMLFile("DynamicEconomyXML", XMLPath)
    else
        xmlId = createXMLFile("DynamicEconomyXML", XMLPath, "DynamicEconomy")
    end

    local savegamePath = "DynamicEconomy.savegame"..tostring(g_currentMission.missionInfo.savegameIndex)
    if hasXMLProperty(xmlId, savegamePath) then
        removeXMLProperty(xmlId, savegamePath)
    end

    local index = 0
    for _, fillType in pairs(DynamicEconomy.fillTypes) do
        local fillTypePath = savegamePath..".fillTypes.fillType("..tostring(index)..")"
        setXMLString(   xmlId, fillTypePath.."#name",           fillType.name)
        setXMLFloat(    xmlId, fillTypePath.."#recentSold",     fillType.recentSold)
        setXMLFloat(    xmlId, fillTypePath.."#factor",         fillType.factor)
        setXMLFloat(    xmlId, fillTypePath.."#basePrice",      fillType.basePrice)
        setXMLInt(      xmlId, fillTypePath.."#gracePeriod",    fillType.gracePeriod)
        index = index + 1
    end

    index = 0
    for _, subType in pairs(DynamicEconomy.subTypes) do
        local subTypePath = savegamePath..".subTypes.subType("..tostring(index)..")"
        setXMLString(   xmlId, subTypePath.."#name",            subType.name)
        setXMLFloat(    xmlId, subTypePath.."#recentSold",      subType.recentSold)
        setXMLFloat(    xmlId, subTypePath.."#factor",          subType.factor)
        setXMLInt(      xmlId, subTypePath.."#gracePeriod",     subType.gracePeriod)
        index = index + 1
    end

    saveXMLFile(xmlId)
    delete(xmlId)
end

local function hourlyUpdate()
    local growthModeScale = g_currentMission.missionInfo.growthMode % 3
    local daysPerMonthScale = 1 / g_currentMission.missionInfo.plannedDaysPerPeriod
    local demandIncrease = (1 / 288) * daysPerMonthScale * growthModeScale
    for _, fillType in pairs(DynamicEconomy.fillTypes) do
        if fillType.gracePeriod < 1 and fillType.recentSold > 0 then
            local demandDecrease = (fillType.recentSold * fillType.basePrice) / annualProfitCap
            fillType.factor = math.max(0, fillType.factor - demandDecrease)
            fillType.recentSold = 0
        else
            fillType.gracePeriod = math.max(0, fillType.gracePeriod - 1)
        end

        fillType.factor = math.min(fillType.factor + demandIncrease, increaseCap + 1)
        DynamicEconomy.fillTypeFactors[fillType.name] = fillType.factor
    end

    local difficultyMultipliers = {3, 1.8, 1}
    local multiplier = difficultyMultipliers[g_currentMission.missionInfo.economicDifficulty]
    local annualProfitCap = multiplier * annualProfitCap
    for _, subType in pairs(DynamicEconomy.subTypes) do
        if subType.gracePeriod < 1 and subType.recentSold > 0 then
            local demandDecrease = subType.recentSold / annualProfitCap
            subType.factor = math.max(0, subType.factor - demandDecrease)
            subType.recentSold = 0
        else
            subType.gracePeriod = math.max(0, subType.gracePeriod - 1)
        end

        subType.factor = math.min(subType.factor + demandIncrease, increaseCap + 1)
        DynamicEconomy.subTypeFactors[subType.name] = subType.factor
    end

    broadcastSubTypeFactors()
end

function DynamicEconomy:loadMap()
    loadXML()
    if not g_currentMission:getIsServer() then return end

    g_messageCenter:subscribe(MessageType.HOUR_CHANGED, hourlyUpdate, DynamicEconomy)
    SellingStation.getEffectiveFillTypePrice = Utils.overwrittenFunction(SellingStation.getEffectiveFillTypePrice, repriceFillType)
    SellingStation.sellFillType = Utils.appendedFunction(SellingStation.sellFillType, catchFillTypeSale)
    AnimalSellEvent.run = Utils.overwrittenFunction(AnimalSellEvent.run, catchSubTypeSale)
    FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, saveXML)
end

function DynamicEconomy:deleteMap()
    g_messageCenter:unsubscribeAll(DynamicEconomy)
    removeModEventListener(DynamicEconomy)
end

function DynamicEconomy:onClientJoined()
    if not g_currentMission:getIsServer() then return end

    broadcastSubTypeFactors()
end

addModEventListener(DynamicEconomy)
