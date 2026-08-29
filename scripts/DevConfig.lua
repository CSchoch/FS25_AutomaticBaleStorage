-- FS25_AutomaticBaleStorage - Development configuration.
-- Development-only file: create_release.ps1 excludes it from the release
-- archive, so a released build falls back to the defaults in register.lua
-- and stays silent.

ABSDevConfig = {}

-- Write the ABS debug messages to the log.
ABSDevConfig.DEBUG_LOGGING = true
