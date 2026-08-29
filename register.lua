-- FS25_AutomaticBaleStorage
-- Registers the AutomaticBaleStorage placeable specialization and attaches it
-- at type-finalize time to every placeable type that already carries the
-- vanilla "objectStorage" specialization.

local modName = g_currentModName
local modDirectory = g_currentModDirectory

local SPEC_NAME = "automaticBaleStorage"
local SPEC_CLASS = "AutomaticBaleStorage"
local SPEC_FILE = Utils.getFilename("scripts/AutomaticBaleStorage.lua", modDirectory)

-- Development config, not shipped in the release archive. Without it debug
-- logging stays off, so a released build does not spam the log. The existence
-- check is required: source() on a missing file logs an engine error.
local DEV_CONFIG_FILE = Utils.getFilename("scripts/DevConfig.lua", modDirectory)
if fileExists(DEV_CONFIG_FILE) then
    source(DEV_CONFIG_FILE)
end

if ABSDevConfig == nil then
    ABSDevConfig = { DEBUG_LOGGING = false }
end

-- Debug log helper used by the specialization; a no-op in a release build.
function ABSDevConfig.debug(message, ...)
    if not ABSDevConfig.DEBUG_LOGGING then
        return
    end

    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end

    print(message)
end

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
