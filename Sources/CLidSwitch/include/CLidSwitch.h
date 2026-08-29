#ifndef C_LID_SWITCH_H
#define C_LID_SWITCH_H

#include <stdint.h>

typedef struct {
    uint32_t displayID;
    uint32_t vendor;
    uint32_t model;
    uint32_t serial;
    uint8_t isBuiltIn;
    uint8_t isActive;
    uint8_t isOnline;
    uint8_t isMain;
} LSDisplayInfo;

enum {
    LS_ERROR_PRIVATE_API_UNAVAILABLE = -7100,
    LS_ERROR_WOULD_DISABLE_LAST_DISPLAY = -7101,
    LS_ERROR_INVALID_ARGUMENT = -7102
};

/// Returns 0 when the required SkyLight symbols can be resolved.
int32_t LSPrivateAPIStatus(void);

/// Enumerates every display known to SkyLight, including inactive displays.
int32_t LSGetDisplays(LSDisplayInfo *buffer,
                      uint32_t capacity,
                      uint32_t *displayCount);

/// Applies one app-lifetime display transaction. Disabling the last active
/// display is rejected before the private API is called.
int32_t LSSetDisplaysEnabled(const uint32_t *displayIDs,
                             uint32_t displayCount,
                             uint8_t enabled);

#endif
