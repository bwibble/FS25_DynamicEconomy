SupplyAndDemand = {}

local annualDemand = 35000
local maxAccumulation = 2.25
local maxPriceFactor = 1.25
local minPriceFactor = 0.25
local graceHours = 4

source(g_currentModDirectory..'supplyAndDemandEvent.lua')

local function clampFactor(factor)
  if not factor or factor > maxPriceFactor then
    return maxPriceFactor
  elseif factor < minPriceFactor then
    return minPriceFactor
  else
    return factor
  end
end

local function fetchXML()
  local xmlId = 0
  local savePath = 'supplyAndDemand.table'

  if not g_currentMission.missionInfo.savegameDirectory then
    return xmlId, savePath
  end

  local xmlPath = g_currentMission.missionInfo.savegameDirectory..'/supplyAndDemand.xml'

  if fileExists(xmlPath) then
    xmlId = loadXMLFile('SupplyAndDemandXML', xmlPath)
  else
    xmlId = createXMLFile('SupplyAndDemandXML', xmlPath, 'supplyAndDemand')
  end

  return xmlId, savePath
end

local function broadcastFactors()
  local fillTypeFactors = {}
  for index, fillType in pairs(g_fillTypeManager.fillTypes) do
    fillTypeFactors[fillType.name] = clampFactor(fillType.factor)
  end

  local subTypeFactors = {}
  for index, subType in pairs(g_currentMission.animalSystem.subTypes) do
    subTypeFactors[subType.name] = clampFactor(subType.factor)
  end

  if g_server ~= nil then
    g_server:broadcastEvent(
      SupplyAndDemandEvent.new(
        fillTypeFactors,
        subTypeFactors,
        g_currentMission.generatorFactor
      ),
      true
    )
  else
    g_client:getServerConnection():sendEvent(
      SupplyAndDemandEvent.new(
        fillTypeFactors,
        subTypeFactors,
        g_currentMission.generatorFactor
      ),
      true
    )
  end 
end

local function catchSubTypeSale(classObject, fn, ...)
  if classObject.sellPrice then
    local clusterId = classObject.clusterId
    local subTypeIndex = classObject.object:getClusterById(clusterId).subTypeIndex
    local subType = g_currentMission.animalSystem.subTypes[subTypeIndex]
    if not subType.recent_sold then
      populateMissingDataPoints()
    end

    subType.recent_sold = subType.recent_sold + classObject.sellPrice
    subType.graceHours = graceHours
  end

  return fn(classObject, ...)
end

local function catchFillTypeSale(_, _, amount_liters, fillTypeIndex)
  local fillType = g_fillTypeManager.fillTypes[fillTypeIndex]
  if not fillType.recent_sold then
    populateMissingDataPoints()
  end

  fillType.recent_sold = fillType.recent_sold + amount_liters
  fillType.graceHours = graceHours
end

local function repriceSubType(subType)
  local function repriceFn(classObject, fn, ...)
    return fn(classObject, ...) * clampFactor(subType.factor)
  end

  return repriceFn
end

local function repriceFillType(classObject, fn, fillTypeIndex, ...)
  local fillType = g_fillTypeManager.fillTypes[fillTypeIndex]
  if not fillType.factor then
    populateMissingDataPoints()
  end

  return fn(classObject, fillTypeIndex, ...) * clampFactor(fillType.factor)
end

local function fetchXMLData()
  local xmlId, savePath = fetchXML()
  local XMLData = {fillTypes = {}, subTypes = {}, generator = nil}

  if xmlId == 0 then
    return XMLData
  end

  local index = 0
  while hasXMLProperty(xmlId, savePath..'.fillType('..index..')') do
    local fillTypePath = savePath..'.fillType('..index..')'
    local fillType = {
      recent_sold = getXMLFloat(xmlId, fillTypePath..'#recent_sold'),
      factor = getXMLFloat(xmlId, fillTypePath..'#factor'),
      graceHours = getXMLInt(xmlId, fillTypePath..'#graceHours')
    }
    local fillTypeName = getXMLString(xmlId, fillTypePath..'#name')
    XMLData.fillTypes[fillTypeName] = fillType
    index = index + 1
  end

  index = 0
  while hasXMLProperty(xmlId, savePath..'.subType('..index..')') do
    local subTypePath = savePath..'.subType('..index..')'
    local subType = {
      recent_sold = getXMLFloat(xmlId, subTypePath..'#recent_sold'),
      factor = getXMLFloat(xmlId, subTypePath..'#factor'),
      graceHours = getXMLInt(xmlId, subTypePath..'#graceHours')
    }
    local subTypeName = getXMLString(xmlId, subTypePath..'#name')
    XMLData.subTypes[subTypeName] = subType
    index = index + 1
  end

  local generatorPath = savePath..'generator'
  if hasXMLProperty(xmlId, generatorPath) then
    XMLData.generator = getXMLFloat(xmlId, generatorPath..'#factor')
  end

  delete(xmlId)
  return XMLData
end

local function populateMissingDataPoints()
  local XMLData = fetchXMLData()
  for _, fillType in pairs(g_fillTypeManager:getFillTypes()) do
    local XMLFillType = XMLData.fillTypes[fillType.name]
    fillType.recent_sold = fillType.recent_sold or (XMLFillType and XMLFillType.recent_sold) or 0
    fillType.factor = fillType.factor or (XMLFillType and XMLFillType.factor) or maxAccumulation
    fillType.graceHours = fillType.graceHours or (XMLFillType and XMLFillType.graceHours) or 0
  end

  for _, subType in pairs(g_currentMission.animalSystem.subTypes) do
    local XMLSubType = XMLData.subTypes[subType.name]
    subType.recent_sold = subType.recent_sold or (XMLSubType and XMLSubType.recent_sold) or 0
    subType.factor = subType.factor or (XMLSubType and XMLSubType.factor) or maxAccumulation
    subType.graceHours = subType.graceHours or (XMLSubType and XMLSubType.graceHours) or 0
    if not subType.repriceFn then
      subType.repriceFn = repriceSubType(subType)
      subType.sellPrice.interpolator = Utils.overwrittenFunction(
        subType.sellPrice.interpolator,
        subType.repriceFn
      )
    end
  end

  g_currentMission.generatorFactor = g_currentMission.generatorFactor or XMLData.generator or maxAccumulation
end

local function saveDataToXML()
  populateMissingDataPoints()

  local xmlId, savePath = fetchXML()
  if xmlId == 0 then
    return
  end

  if hasXMLProperty(xmlId, savePath) then
    removeXMLProperty(xmlId, savePath)`
  end

  local index = 0
  for _, fillType in pairs(g_fillTypeManager.fillTypes) do
    local fillTypePath = savePath..'.fillType('..tostring(index)..')'
    setXMLString(xmlId, fillTypePath..'#name', fillType.name)
    setXMLFloat(xmlId, fillTypePath..'#recent_sold', fillType.recent_sold)
    setXMLFloat(xmlId, fillTypePath..'#factor', fillType.factor)
    setXMLInt(xmlId, fillTypePath.."#graceHours", fillType.graceHours)
    index = index + 1
  end

  index = 0
  for _, subType in pairs(g_currentMission.animalSystem.subTypes) do
    local subTypePath = savePath..'.subType('..tostring(index)..')'
    setXMLString(xmlId, subTypePath..'#name', subType.name)
    setXMLFloat(xmlId, subTypePath..'#recent_sold', subType.recent_sold)
    setXMLFloat(xmlId, subTypePath..'#factor', subType.factor)
    setXMLInt(xmlId, subTypePath..'#graceHours', subType.graceHours)
    index = index + 1
  end

  local generatorPath = savePath..'.generator'
  setXMLFloat(xmlId, generatorPath..'#factor', g_currentMission.generatorFactor)

  saveXMLFile(xmlId)
  delete(xmlId)
end

local function hourlyUpdate()
  local growth_mode_scale = g_currentMission.missionInfo.growthMode % 3
  local days_in_month_scale = 1 / g_currentMission.missionInfo.plannedDaysPerPeriod
  local demand_increase = (1 / 288) * days_in_month_scale * growth_mode_scale
  local annual_subType_profit_cap = EconomyManager.getPriceMultiplier() * annualDemand
  if demand_increase > 0 then
    for index, fillType in pairs(g_fillTypeManager.fillTypes) do
      fillType.factor = math.min(
        fillType.factor + demand_increase,
        maxAccumulation
      )
    end

    for index, subType in pairs(g_currentMission.animalSystem.subTypes) do
      subType.factor = math.min(
        subType.factor + demand_increase,
        maxAccumulation
      )
    end

    if not g_currentMission.generatorFactor then
      populateMissingDataPoints()
    end

    g_currentMission.generatorFactor = math.min(
      g_currentMission.generatorFactor + demand_increase,
      maxAccumulation
    )
  end

  for index, fillType in pairs(g_fillTypeManager.fillTypes) do
    if fillType.recent_sold > 0 then
      if fillType.graceHours > 0 then
        fillType.graceHours = fillType.graceHours - 1
      else
        local demandDecrease = (fillType.recent_sold * fillType.pricePerLiter) / annualDemand
        fillType.factor = math.max(fillType.factor - demandDecrease, 0)
        fillType.recent_sold = 0
      end
    end
  end

  for index, subType in pairs(g_currentMission.animalSystem.subTypes) do
    if subType.recent_sold > 0 then
      if subType.graceHours > 0 then
        subType.graceHours = subType.graceHours - 1
      else
        local demandDecrease = subType.recent_sold / annual_subType_profit_cap
        subType.factor = math.max(subType.factor - demandDecrease, 0)
        subType.recent_sold = 0
      end
    end
  end

  broadcastFactors()
end

local function setFillTypeDemandTitles()
  for index, fillType in pairs(g_fillTypeManager.fillTypes) do
    if not fillType.factor then
      populateMissingDataPoints()
    end

    fillType.defaultTitle = fillType.title
    fillType.title = string.format(
      '%s (%d%%)',
      fillType.title,
      clampFactor(fillType.factor)*100
    )
    fillType.titleCrossRef = fillType.title
  end
end

local function prepSubTypeDemandTitles()
  g_currentMission.animalSystem.nameToSubType = {}
  local nameToSubType = g_currentMission.animalSystem.nameToSubType
  for _, subType in pairs(g_currentMission.animalSystem.subTypes) do
    local fillTypeIndex = subType.fillTypeIndex
    local fillType = g_fillTypeManager.fillTypes[fillTypeIndex]
    nameToSubType[string.upper(fillType.title)] = subType
  end
end

local function returnSubTypeDemandTitle(classObject, fn, ...)
  local name = fn(classObject, ...)
  if type(name) ~= 'string' then
    return name
  end

  if not g_currentMission.animalSystem.nameToSubType then
    return name
  end

  local subType = g_currentMission.animalSystem.nameToSubType[string.upper(name)]
  if subType then
    name = string.format('%s (%d%%)', name, clampFactor(subType.factor)*100)
  end

  return name
end

local function setFillTypeDefaultTitles()
  for index, fillType in pairs(g_fillTypeManager.fillTypes) do
    if not fillType.factor then
      populateMissingDataPoints()
    end

    if fillType.title == fillType.titleCrossRef then
      fillType.title = fillType.defaultTitle or fillType.title
    end
  end
end

local function PlaceableIncomePerHour_onHourChanged(classObject)
  if classObject.isServer then
    local ownerFarmId = classObject:getOwnerFarmId()
    if ownerFarmId ~= FarmlandManager.NO_OWNER_FARM_ID then
      local incomePerHour = classObject:getIncomePerHour() * g_currentMission.environment.timeAdjustment

      if not g_currentMission.generatorFactor then
        populateMissingDataPoints()
      end

      local demandDecrease = incomePerHour / (EconomyManager.getPriceMultiplier() * annualDemand)
      incomePerHour = incomePerHour * clampFactor(g_currentMission.generatorFactor)
      g_currentMission.generatorFactor = math.max(
        g_currentMission.generatorFactor - demandDecrease,
        0
      )

      if incomePerHour ~= 0 then
        g_currentMission:addMoney(
          incomePerHour,
          ownerFarmId,
          MoneyType.PROPERTY_INCOME,
          true
        )
      end
    end
  end
end

function SupplyAndDemand:loadMap()

  InGameMenuStatisticsFrame.rebuildTable = Utils.prependedFunction(
    InGameMenuStatisticsFrame.rebuildTable,
    setFillTypeDemandTitles
  )
  InGameMenuStatisticsFrame.onFrameClose = Utils.prependedFunction(
    InGameMenuStatisticsFrame.onFrameClose,
    setFillTypeDefaultTitles
  )
  InGameMenuAnimalsFrame.onFrameOpen = Utils.prependedFunction(
    InGameMenuAnimalsFrame.onFrameOpen,
    prepSubTypeDemandTitles
  )
  InGameMenuAnimalsFrame.getTitleForSectionHeader = Utils.overwrittenFunction(
    InGameMenuAnimalsFrame.getTitleForSectionHeader,
    returnSubTypeDemandTitle
  )
  populateMissingDataPoints()
  
  if not g_currentMission:getIsServer() then
    return
  end

  PlaceableIncomePerHour.onHourChanged = Utils.overwrittenFunction(
    PlaceableIncomePerHour.onHourChanged,
    PlaceableIncomePerHour_onHourChanged
  )
  SellingStation.getEffectiveFillTypePrice = Utils.overwrittenFunction(
    SellingStation.getEffectiveFillTypePrice,
    repriceFillType
  )
  SellingStation.sellFillType = Utils.appendedFunction(
    SellingStation.sellFillType,
    catchFillTypeSale
  )
  AnimalSellEvent.run = Utils.overwrittenFunction(
    AnimalSellEvent.run,
    catchSubTypeSale
  )
  FSBaseMission.saveSavegame = Utils.appendedFunction(
    FSBaseMission.saveSavegame,
    saveDataToXML
  )
  g_messageCenter:subscribe(
    MessageType.HOUR_CHANGED,
    hourlyUpdate, SupplyAndDemand
  )
  g_messageCenter:subscribe(
    MessageType.ON_CLIENT_START_MISSION,
    broadcastFactors, SupplyAndDemand
  )
end

function SupplyAndDemand:deleteMap()
  g_messageCenter:unsubscribeAll(SupplyAndDemand)
  removeModEventListener(SupplyAndDemand)
end

addModEventListener(SupplyAndDemand)