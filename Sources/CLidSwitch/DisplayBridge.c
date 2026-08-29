#include "CLidSwitch.h"

#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stddef.h>

typedef CGError (*SLSGetDisplayListFn)(uint32_t maxDisplays,
                                       CGDirectDisplayID *displays,
                                       uint32_t *displayCount);
typedef CGError (*SLSConfigureDisplayEnabledFn)(CGDisplayConfigRef config,
                                                CGDirectDisplayID display,
                                                bool enabled);

static void *skyLightHandle = NULL;
static SLSGetDisplayListFn getDisplayList = NULL;
static SLSConfigureDisplayEnabledFn configureDisplayEnabled = NULL;

static int32_t load_private_api(void) {
    if (getDisplayList != NULL && configureDisplayEnabled != NULL) {
        return 0;
    }

    skyLightHandle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY | RTLD_LOCAL
    );
    if (skyLightHandle == NULL) {
        return LS_ERROR_PRIVATE_API_UNAVAILABLE;
    }

    getDisplayList = (SLSGetDisplayListFn)dlsym(
        skyLightHandle,
        "SLSGetDisplayList"
    );
    configureDisplayEnabled = (SLSConfigureDisplayEnabledFn)dlsym(
        skyLightHandle,
        "SLSConfigureDisplayEnabled"
    );

    if (getDisplayList == NULL || configureDisplayEnabled == NULL) {
        return LS_ERROR_PRIVATE_API_UNAVAILABLE;
    }
    return 0;
}

static bool list_contains(const CGDirectDisplayID *list,
                          uint32_t count,
                          CGDirectDisplayID display) {
    for (uint32_t index = 0; index < count; index++) {
        if (list[index] == display) {
            return true;
        }
    }
    return false;
}

static bool target_contains(const uint32_t *targets,
                            uint32_t count,
                            CGDirectDisplayID display) {
    for (uint32_t index = 0; index < count; index++) {
        if (targets[index] == display) {
            return true;
        }
    }
    return false;
}

int32_t LSPrivateAPIStatus(void) {
    return load_private_api();
}

int32_t LSGetDisplays(LSDisplayInfo *buffer,
                      uint32_t capacity,
                      uint32_t *displayCount) {
    if (buffer == NULL || capacity == 0 || displayCount == NULL) {
        return LS_ERROR_INVALID_ARGUMENT;
    }

    int32_t loadStatus = load_private_api();
    if (loadStatus != 0) {
        return loadStatus;
    }

    CGDirectDisplayID all[64] = {0};
    CGDirectDisplayID active[64] = {0};
    CGDirectDisplayID online[64] = {0};
    uint32_t allCount = 0;
    uint32_t activeCount = 0;
    uint32_t onlineCount = 0;

    CGError error = getDisplayList(64, all, &allCount);
    if (error != kCGErrorSuccess) {
        return error;
    }
    error = CGGetActiveDisplayList(64, active, &activeCount);
    if (error != kCGErrorSuccess) {
        return error;
    }
    error = CGGetOnlineDisplayList(64, online, &onlineCount);
    if (error != kCGErrorSuccess) {
        return error;
    }

    uint32_t outputCount = allCount < capacity ? allCount : capacity;
    for (uint32_t index = 0; index < outputCount; index++) {
        CGDirectDisplayID display = all[index];
        buffer[index] = (LSDisplayInfo) {
            .displayID = display,
            .vendor = CGDisplayVendorNumber(display),
            .model = CGDisplayModelNumber(display),
            .serial = CGDisplaySerialNumber(display),
            .isBuiltIn = CGDisplayIsBuiltin(display) ? 1 : 0,
            .isActive = list_contains(active, activeCount, display) ? 1 : 0,
            .isOnline = list_contains(online, onlineCount, display) ? 1 : 0,
            .isMain = CGDisplayIsMain(display) ? 1 : 0
        };
    }
    *displayCount = outputCount;
    return 0;
}

int32_t LSSetDisplaysEnabled(const uint32_t *displayIDs,
                             uint32_t displayCount,
                             uint8_t enabled) {
    if (displayIDs == NULL || displayCount == 0) {
        return LS_ERROR_INVALID_ARGUMENT;
    }

    int32_t loadStatus = load_private_api();
    if (loadStatus != 0) {
        return loadStatus;
    }

    CGDirectDisplayID active[64] = {0};
    uint32_t activeCount = 0;
    CGError listError = CGGetActiveDisplayList(64, active, &activeCount);
    if (listError != kCGErrorSuccess) {
        return listError;
    }

    if (!enabled) {
        uint32_t remaining = 0;
        for (uint32_t index = 0; index < activeCount; index++) {
            if (!target_contains(displayIDs, displayCount, active[index])) {
                remaining++;
            }
        }
        if (remaining == 0) {
            return LS_ERROR_WOULD_DISABLE_LAST_DISPLAY;
        }
    }

    uint32_t changedIDs[64] = {0};
    uint32_t changedCount = 0;
    uint32_t boundedCount = displayCount < 64 ? displayCount : 64;
    for (uint32_t index = 0; index < boundedCount; index++) {
        bool currentlyEnabled = list_contains(
            active,
            activeCount,
            displayIDs[index]
        );
        if (currentlyEnabled != (enabled != 0)) {
            changedIDs[changedCount++] = displayIDs[index];
        }
    }
    if (changedCount == 0) {
        return 0;
    }

    const CGConfigureOption options[] = {
        kCGConfigureForAppOnly,
        kCGConfigureForSession
    };
    CGError lastError = kCGErrorFailure;
    for (size_t optionIndex = 0;
         optionIndex < sizeof(options) / sizeof(options[0]);
         optionIndex++) {
        CGDisplayConfigRef configuration = NULL;
        CGError error = CGBeginDisplayConfiguration(&configuration);
        if (error != kCGErrorSuccess || configuration == NULL) {
            lastError = error == kCGErrorSuccess ? kCGErrorFailure : error;
            continue;
        }

        bool configured = true;
        for (uint32_t index = 0; index < changedCount; index++) {
            error = configureDisplayEnabled(
                configuration,
                changedIDs[index],
                enabled != 0
            );
            if (error != kCGErrorSuccess) {
                configured = false;
                lastError = error;
                break;
            }
        }

        if (!configured) {
            CGCancelDisplayConfiguration(configuration);
            break;
        }

        error = CGCompleteDisplayConfiguration(
            configuration,
            options[optionIndex]
        );
        if (error == kCGErrorSuccess) {
            return 0;
        }
        lastError = error;
    }

    return lastError;
}
