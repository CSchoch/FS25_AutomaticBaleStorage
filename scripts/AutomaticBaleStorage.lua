-- AutomaticBaleStorage placeable specialization.
-- Intercepts UI-triggered unload calls and queues them instead of spawning
-- everything at once. onUpdate drains the queue one batch per interval.
-- The remaining-unload counter is written to the savegame so a partial
-- queue survives a reload.
-- Also lifts the manual-unload cap so the storage UI slider can go up to the
-- actual stored count.

AutomaticBaleStorage = {}

local CHECK_INTERVAL_MS = 5000

function AutomaticBaleStorage.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(PlaceableObjectStorage, specializations)
end

function AutomaticBaleStorage.registerOverwrittenFunctions(placeableType)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "removeAbstractObjectsFromStorage", AutomaticBaleStorage.removeAbstractObjectsFromStorage)
end

function AutomaticBaleStorage.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad",   AutomaticBaleStorage)
    SpecializationUtil.registerEventListener(placeableType, "onUpdate", AutomaticBaleStorage)
end

-- FS25 placeables use loadFromXMLFile/saveToXMLFile (not onReadSaveGame/onWriteSaveGame).
-- registerSavegameXMLPaths declares the schema so xmlFile:getValue/setValue work correctly.
function AutomaticBaleStorage.registerSavegameXMLPaths(schema, basePath)
    schema:register(XMLValueType.INT, basePath .. ".automaticBaleStorage#remainingUnload", "Pending unload queue count", 0)
    schema:register(XMLValueType.INT, basePath .. ".automaticBaleStorage#unloadIndex",     "Object info index for queued type", 0)
end

function AutomaticBaleStorage:onLoad(_)
    self.spec_automaticBaleStorage = self.spec_automaticBaleStorage or {}
    local spec = self.spec_automaticBaleStorage
    spec.checkInterval   = CHECK_INTERVAL_MS
    spec.timer           = CHECK_INTERVAL_MS
    spec.remainingUnload = 0
    spec.unloadIndex     = nil

    -- Lift manual-unload cap. PlaceableObjectStorageActivatable:run reads
    -- spec_objectStorage.maxUnloadAmount when opening ObjectStorageDialog.
    local osSpec = self.spec_objectStorage
    if osSpec ~= nil then
        osSpec.maxUnloadAmount = math.huge
    end

    self:raiseActive()
end

-- Called by the Placeable base class after onLoad, when loading from a savegame.
-- This is the correct FS25 hook for reading persisted state (mirrors PlaceableObjectStorage).
function AutomaticBaleStorage:loadFromXMLFile(xmlFile, key)
    local spec = self.spec_automaticBaleStorage
    if spec == nil then return end
    spec.remainingUnload = xmlFile:getValue(key .. ".automaticBaleStorage#remainingUnload", 0)
    local savedIndex     = xmlFile:getValue(key .. ".automaticBaleStorage#unloadIndex",     0)
    spec.unloadIndex     = savedIndex > 0 and savedIndex or nil
    print(string.format("ABS loadFromXMLFile: remainingUnload=%s unloadIndex=%s", tostring(spec.remainingUnload), tostring(spec.unloadIndex)))
    if spec.remainingUnload > 0 then
        spec.timer = 0  -- dispatch on the first eligible update rather than waiting 5 s
        self:raiseActive()
    end
end

-- Called by the Placeable base class when saving to a savegame.
function AutomaticBaleStorage:saveToXMLFile(xmlFile, key, _)
    local spec = self.spec_automaticBaleStorage
    if spec == nil then return end
    print(string.format("ABS saveToXMLFile: remainingUnload=%s unloadIndex=%s", tostring(spec.remainingUnload or 0), tostring(spec.unloadIndex or 0)))
    xmlFile:setValue(key .. ".automaticBaleStorage#remainingUnload", spec.remainingUnload or 0)
    xmlFile:setValue(key .. ".automaticBaleStorage#unloadIndex",     spec.unloadIndex    or 0)
end

-- Overrides PlaceableObjectStorage:removeAbstractObjectsFromStorage.
-- PlaceableObjectStorageUnloadEvent always supplies the client connection;
-- our own timed dispatch passes nil. Use that to distinguish the two call sites
-- without needing a mutable inDispatch flag.
function AutomaticBaleStorage:removeAbstractObjectsFromStorage(superFunc, objectInfoIndex, amount, connection)
    local spec = self.spec_automaticBaleStorage
    if spec == nil or connection == nil then
        return superFunc(self, objectInfoIndex, amount, connection)
    end
    spec.remainingUnload = spec.remainingUnload + (amount or 0)
    spec.unloadIndex     = objectInfoIndex
    spec.lastKnownTotal  = nil
    self:raiseActive()
end

function AutomaticBaleStorage:onUpdate(dt)
    if not self.isServer then
        return
    end

    local spec = self.spec_automaticBaleStorage
    local osSpec = self.spec_objectStorage
    if spec == nil or osSpec == nil then
        return
    end

    spec.timer = spec.timer - dt

    if spec.remainingUnload > 0 then
        self:raiseActive()
    end

    if spec.timer > 0 then
        return
    end
    spec.timer = spec.checkInterval

    if spec.remainingUnload <= 0 then
        return
    end

    print(string.format("ABS onUpdate dispatch tick: remainingUnload=%s objectSpawnActive=%s updateTimer=%s", tostring(spec.remainingUnload), tostring(osSpec.objectSpawn ~= nil and osSpec.objectSpawn.isActive), tostring(osSpec.objectInfosUpdateTimer)))

    -- A previous spawn cycle is still running — wait it out.
    if osSpec.objectSpawn ~= nil and osSpec.objectSpawn.isActive then
        print("ABS onUpdate: blocked by active objectSpawn")
        return
    end

    -- Object infos are pending refresh; try again next tick.
    if osSpec.objectInfosUpdateTimer ~= nil and osSpec.objectInfosUpdateTimer ~= 0 then
        print("ABS onUpdate: blocked by objectInfosUpdateTimer=" .. tostring(osSpec.objectInfosUpdateTimer))
        return
    end

    self:updateDirtyObjectStorageObjectInfos()

    local objectInfos = osSpec.objectInfos
    if objectInfos == nil then
        print("ABS onUpdate: objectInfos is nil, waiting")
        return
    end

    local targetIndex = spec.unloadIndex

    -- Count stored bales for the selected type only (or all types if none selected).
    local totalStored = 0
    if targetIndex ~= nil then
        local info = objectInfos[targetIndex]
        totalStored = info ~= nil and (info.numObjects or 0) or 0
    else
        for i = 1, #objectInfos do
            local info = objectInfos[i]
            if info ~= nil then
                totalStored = totalStored + (info.numObjects or 0)
            end
        end
    end

    -- Decrement the queue only by what was ACTUALLY removed from storage since
    -- the last check. If the output area was full and the vanilla spawn placed
    -- nothing, totalStored is unchanged and remainingUnload stays intact so we
    -- keep retrying once space is freed.
    local hadValidReading = spec.lastKnownTotal ~= nil
    if hadValidReading and spec.lastKnownTotal > totalStored then
        spec.remainingUnload = math.max(0, spec.remainingUnload - (spec.lastKnownTotal - totalStored))
    end
    spec.lastKnownTotal = totalStored

    print(string.format("ABS onUpdate: totalStored=%s remainingUnload=%s hadValidReading=%s targetIndex=%s", tostring(totalStored), tostring(spec.remainingUnload), tostring(hadValidReading), tostring(targetIndex)))

    if spec.remainingUnload <= 0 then
        spec.remainingUnload = 0
        spec.unloadIndex     = nil
        spec.lastKnownTotal  = nil
        return
    end

    -- Only treat an empty storage as "done" if we had a prior confirmed reading.
    -- On the first tick after a savegame load objectInfos may not be refreshed yet
    -- and could spuriously report 0, which would incorrectly wipe the queue.
    if totalStored == 0 and hadValidReading then
        print("ABS onUpdate: storage confirmed empty, clearing queue")
        spec.remainingUnload = 0
        spec.unloadIndex     = nil
        spec.lastKnownTotal  = nil
        return
    end

    if totalStored == 0 then
        print("ABS onUpdate: totalStored=0 but no prior reading, waiting for refresh")
        return  -- wait for objectInfos to refresh before deciding
    end

    -- Dispatch one batch for the selected type.
    if targetIndex ~= nil then
        local info = objectInfos[targetIndex]
        if info ~= nil and info.numObjects > 0 then
            local toUnload = math.min(info.numObjects, spec.remainingUnload)
            self:removeAbstractObjectsFromStorage(targetIndex, toUnload, nil)
        end
    else
        for i = 1, #objectInfos do
            local info = objectInfos[i]
            if info ~= nil and info.numObjects > 0 then
                local toUnload = math.min(info.numObjects, spec.remainingUnload)
                self:removeAbstractObjectsFromStorage(i, toUnload, nil)
                return
            end
        end
    end
end
