SupplyAndDemandEvent = {}
local SupplyAndDemandEvent_mt = Class(SupplyAndDemandEvent, Event)
InitEventClass(SupplyAndDemandEvent, 'SupplyAndDemandEvent')

function SupplyAndDemandEvent.emptyNew()
    local self = Event.new(SupplyAndDemandEvent_mt)
    return self
end

function SupplyAndDemandEvent.new(fillTypeFactors, subTypeFactors, generatorFactor)
    local self = SupplyAndDemandEvent.emptyNew()
    self.fillTypeFactors = fillTypeFactors
    self.subTypeFactors = subTypeFactors
    self.generatorFactor = generatorFactor
    return self
end

function SupplyAndDemandEvent:readStream(streamId, connection)
    self.fillTypeFactors = {}
    self.subTypeFactors = {}
    self.generatorFactor = nil

    local count = streamReadInt32(streamId)
    for _ = 1, count, 1 do
        local name = streamReadString(streamId)
        local factor = streamReadFloat32(streamId)
        self.fillTypeFactors[name] = factor
    end

    count = streamReadInt32(streamId)
    for _ = 1, count, 1 do
        local name = streamReadString(streamId)
        local factor = streamReadFloat32(streamId)
        self.subTypeFactors[name] = factor
    end

    self.generatorFactor = streamReadFloat32(streamId)

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

    streamReadFloat32(streamId, self.generatorFactor)
end

function SupplyAndDemandEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(
            SupplyAndDemandEvent.new(self.fillTypeFactors, self.subTypeFactors),
            true
        )
    else
        for _, fillType in pairs(g_fillTypeManager.fillTypes) do
            if self.fillTypeFactors[fillType.name] then
                fillType.sd_factor = self.fillTypeFactors[fillType.name]
            end
        end

        for _, subType in pairs(g_currentMission.animalSystem.subTypes) do
            if self.subTypeFactors[subType.name] then
                subType.sd_factor = self.subTypeFactors[subType.name]
            end
        end

        g_currentMission.sd_generatorFactor = self.generatorFactor
    end
end