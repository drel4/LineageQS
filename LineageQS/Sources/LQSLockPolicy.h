#pragma once
#include <stdbool.h>
#include <string.h>

// Deliberately small locked-device allowlist. Everything else, including
// unknown/future tiles and all navigation/edit actions, requires actual unlock.
static inline bool LQSActionRequiresUnlock(const char *identifier) {
    if (!identifier) return true;
    return strcmp(identifier, "brightness") && strcmp(identifier, "flashlight") && strcmp(identifier, "rotation");
}

typedef enum { LQSUnlockWait, LQSUnlockSucceeded, LQSUnlockCancelled } LQSUnlockDecision;
static inline LQSUnlockDecision LQSDecideUnlock(bool locked, bool screenOn, bool sawPasscode,
                                               double elapsed, double secondsSincePasscodeGone) {
    if (!screenOn) return LQSUnlockCancelled;
    if (!locked) return LQSUnlockSucceeded;
    if ((sawPasscode && secondsSincePasscodeGone > 0.6)
        || (!sawPasscode && elapsed > 4) || elapsed > 180) return LQSUnlockCancelled;
    return LQSUnlockWait;
}
