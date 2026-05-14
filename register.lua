-- FS25_AutomaticBaleStorage
-- Registers the AutomaticBaleStorage placeable specialization and attaches it
-- at type-finalize time to every placeable type that already carries the
-- vanilla "objectStorage" specialization.

local modName = g_currentModName
local modDirectory = g_currentModDirectory

local SPEC_NAME = "automaticBaleStorage"
local SPEC_CLASS = "AutomaticBaleStorage"
local SPEC_FILE = Utils.getFilename("scripts/AutomaticBaleStorage.lua", modDirectory)

-- Registration is deferred into the finalizeTypes hook so we use the correct
-- placeable specialization manager (self.specializationManager on the placeable
-- TypeManager), not g_specializationManager which belongs to vehicles.
TypeManager.finalizeTypes = Utils.prependedFunction(TypeManager.finalizeTypes, function(self)
    if self.typeName ~= "placeable" then
        return
    end

    local qualifiedName = modName .. "." .. SPEC_NAME
    local qualifiedClass = modName .. "." .. SPEC_CLASS

    -- Register the specialization in the placeable spec manager if not yet done.
    if self.specializationManager:getSpecializationByName(qualifiedName) == nil then
        self.specializationManager:addSpecialization(
            qualifiedName,
            qualifiedClass,
            SPEC_FILE,
            modName)
    end

    local attached = 0
    for typeName, typeEntry in pairs(self:getTypes()) do
        if typeEntry.specializationsByName ~= nil
                and typeEntry.specializationsByName["objectStorage"] ~= nil
                and typeEntry.specializationsByName[qualifiedName] == nil then
            if self:addSpecialization(typeName, qualifiedName) then
                attached = attached + 1
            end
        end
    end

    Logging.info("[AutomaticBaleStorage] attached to %d placeable type(s)", attached)
end)
