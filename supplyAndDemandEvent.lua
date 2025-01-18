SupplyAndDemandEvent = {}
local SupplyAndDemandEvent_mt = Class(SupplyAndDemandEvent, Event)
InitEventClass(SupplyAndDemandEvent, 'SupplyAndDemandEvent')

function SupplyAndDemandEvent.emptyNew()
    local self = Event.new(SupplyAndDemandEvent_mt)
    return self
end

function SupplyAndDemandEvent.new(fillTypeFactors, subTypeFactors)
    local self = SupplyAndDemandEvent.emptyNew()
    self.fillTypeFactors = fillTypeFactors
    self.subTypeFactors = subTypeFactors
    return self
end

function SupplyAndDemandEvent:readStream(streamId, connection)
    self.fillTypeFactors = {}
    self.subTypeFactors = {}
    local index = 0
    local count = streamReadInt32(streamId)
    while index < count do
        local name = streamReadString(streamId)
        local factor = streamReadFloat32(streamId)
        self.fillTypeFactors[name] = factor
        index = index + 1
    end
    index = 0
    count = streamReadInt32(streamId)
    while index < count do
        local name = streamReadString(streamId)
        local factor = streamReadFloat32(streamId)
        self.subTypeFactors[name] = factor
        index = index + 1
    end

    self:run(connection)
end

function SupplyAndDemandEvent:writeStream(streamId)
    streamWriteInt32(#self.fillTypeFactors)
    for name, factor in pairs(self.fillTypeFactors) do
        streamWriteString(streamId, name)
        streamWriteFloat32(streamId, factor)
    end

    streamWriteInt32(#self.subTypeFactors)
    for name, factor in pairs(self.subTypeFactors) do
        streamWriteString(streamId, name)
        streamWriteFloat32(streamId, factor)
    end
end

function SupplyAndDemandEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(
            SupplyAndDemandEvent.new(self.fillTypeFactors, self.subTypeFactors)
        )
    else
        for index, fillType in pairs(g_fillTypeManager.fillTypes) do
            if self.fillTypeFactors[fillType.name] then
                fillType.factor = self.fillTypeFactors[fillType.name]
            end
        end

        for index, subType in pairs(g_currentMission.animalSystem.subTypes) do
            if self.subTypeFactors[subType.name] then
                subType.factor = self.subTypeFactors[subType.name]
            end
        end
    end
end