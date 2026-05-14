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

function AutomaticBaleStorage.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad",          AutomaticBaleStorage)
    SpecializationUtil.registerEventListener(placeableType, "onUpdate",        AutomaticBaleStorage)
    SpecializationUtil.registerEventListener(placeableType, "onWriteSaveGame", AutomaticBaleStorage)
    SpecializationUtil.registerEventListener(placeableType, "onReadSaveGame",  AutomaticBaleStorage)
end

function AutomaticBaleStorage:onLoad(savegame)
    self.spec_automaticBaleStorage = self.spec_automaticBaleStorage or {}
    local spec = self.spec_automaticBaleStorage
    spec.checkInterval   = CHECK_INTERVAL_MS
    spec.timer           = CHECK_INTERVAL_MS
    spec.remainingUnload = 0
    spec.inDispatch      = false

    -- Shadow removeAbstractObjectsFromStorage on this instance so UI calls
    -- add to the queue rather than spawning immediately.
    local origRemove = self.removeAbstractObjectsFromStorage
    if origRemove ~= nil then
        self.removeAbstractObjectsFromStorage = function(obj, index, amount, callbackFunc)
            if spec.inDispatch then
                return origRemove(obj, index, amount, callbackFunc)
            end
            spec.remainingUnload = spec.remainingUnload + (amount or 0)
            obj:raiseActive()
        end
    end

    -- Lift manual-unload cap. PlaceableObjectStorageActivatable:run reads
    -- spec_objectStorage.maxUnloadAmount when opening ObjectStorageDialog.
    local osSpec = self.spec_objectStorage
    if osSpec ~= nil then
        osSpec.maxUnloadAmount = math.huge
    end

    self:raiseActive()
end

function AutomaticBaleStorage:onWriteSaveGame(xmlFile, key)
    local spec = self.spec_automaticBaleStorage
    if spec == nil then return end
    xmlFile:setValue(key .. ".automaticBaleStorage#remainingUnload", spec.remainingUnload or 0)
end

function AutomaticBaleStorage:onReadSaveGame(xmlFile, key)
    local spec = self.spec_automaticBaleStorage
    if spec == nil then return end
    spec.remainingUnload = xmlFile:getValue(key .. ".automaticBaleStorage#remainingUnload", 0)
    if spec.remainingUnload > 0 then
        self:raiseActive()
    end
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

    -- A previous spawn cycle is still running — wait it out.
    if osSpec.objectSpawn ~= nil and osSpec.objectSpawn.isActive then
        return
    end

    -- Object infos are pending refresh; try again next tick.
    if osSpec.objectInfosUpdateTimer ~= nil and osSpec.objectInfosUpdateTimer ~= 0 then
        return
    end

    self:updateDirtyObjectStorageObjectInfos()

    local objectInfos = osSpec.objectInfos
    if objectInfos == nil then
        return
    end

    -- Count bales actually in abstract storage right now.
    local totalStored = 0
    for i = 1, #objectInfos do
        local info = objectInfos[i]
        if info ~= nil then
            totalStored = totalStored + (info.numObjects or 0)
        end
    end

    -- Decrement the queue only by what was ACTUALLY removed from storage since
    -- the last check. If the output area was full and the vanilla spawn placed
    -- nothing, totalStored is unchanged and remainingUnload stays intact so we
    -- keep retrying once space is freed.
    if spec.lastKnownTotal ~= nil and spec.lastKnownTotal > totalStored then
        spec.remainingUnload = math.max(0, spec.remainingUnload - (spec.lastKnownTotal - totalStored))
    end
    spec.lastKnownTotal = totalStored

    if totalStored == 0 or spec.remainingUnload <= 0 then
        spec.remainingUnload = 0
        return
    end

    for i = 1, #objectInfos do
        local info = objectInfos[i]
        if info ~= nil and info.numObjects > 0 then
            local toUnload = math.min(info.numObjects, spec.remainingUnload)
            spec.inDispatch = true
            self:removeAbstractObjectsFromStorage(i, toUnload, nil)
            spec.inDispatch = false
            return
        end
    end
end
