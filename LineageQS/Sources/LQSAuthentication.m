#import "LQSAuthentication.h"
#import "LQSLockPolicy.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

NSString *const LQSAuthenticationWillBeginNotification = @"LQSAuthenticationWillBeginNotification";
NSString *const LQSAuthenticationDidFinishNotification = @"LQSAuthenticationDidFinishNotification";
NSString *const LQSLockStateChangedNotification = @"LQSLockStateChangedNotification";
static NSTimer *gUnlockTimer;
static void (^gUnlockCompletion)(BOOL);
static BOOL gSawPasscode;
static CFTimeInterval gUnlockStart, gPasscodeGone;

static BOOL BoolType(const char *type) { return type && (*type == 'B' || *type == 'c'); }
static id LockManager(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    SEL selector = NSSelectorFromString(@"sharedInstanceIfExists");
    if (![cls respondsToSelector:selector]) selector = NSSelectorFromString(@"sharedInstance");
    return [cls respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(cls, selector) : nil;
}
static BOOL ReadBool(id object, NSString *name, BOOL *known) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (![object respondsToSelector:selector] || signature.numberOfArguments != 2 || !BoolType(signature.methodReturnType)) return NO;
    @try { BOOL result = ((BOOL (*)(id, SEL))objc_msgSend)(object, selector); if (known) *known = YES; return result; }
    @catch (__unused NSException *exception) { return NO; }
}

BOOL LQSDeviceIsLocked(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return NO; // preview
    BOOL known = NO;
    BOOL locked = ReadBool(LockManager(), @"isUILocked", &known);
    return known ? locked : YES; // unknown lock state cannot authorize an action
}
BOOL LQSRequiresUnlock(NSString *identifier) { return LQSActionRequiresUnlock(identifier.UTF8String); }

BOOL LQSDeviceScreenIsOn(void) {
    id manager = LockManager();
    Ivar ivar = class_getInstanceVariable(object_getClass(manager), "_isScreenOn");
    if (!ivar || !BoolType(ivar_getTypeEncoding(ivar))) return YES;
    BOOL on = YES;
    memcpy(&on, (uint8_t *)(__bridge void *)manager + ivar_getOffset(ivar), sizeof(on));
    return on;
}

static void FinishUnlock(BOOL success, BOOL restore) {
    if (!gUnlockCompletion) return;
    void (^completion)(BOOL) = gUnlockCompletion;
    gUnlockCompletion = nil;
    [gUnlockTimer invalidate]; gUnlockTimer = nil;
    success = success && !LQSDeviceIsLocked() && LQSDeviceScreenIsOn();
    [[NSNotificationCenter defaultCenter] postNotificationName:LQSAuthenticationDidFinishNotification object:nil
        userInfo:@{@"success":@(success), @"restore":@(restore)}];
    // Let SpringBoard finish its native unlock/window transition before the
    // explicitly requested action resumes; the caller rechecks lock/epoch too.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 3), dispatch_get_main_queue(), ^{ completion(success && !LQSDeviceIsLocked() && LQSDeviceScreenIsOn()); });
}

@implementation LQSAuthentication
+ (BOOL)isPending { return gUnlockCompletion != nil; }
+ (void)cancel { FinishUnlock(NO, NO); }
+ (void)lockStateDidChange {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self lockStateDidChange]; }); return; }
    [[NSNotificationCenter defaultCenter] postNotificationName:LQSLockStateChangedNotification object:nil];
    if (gUnlockCompletion && !LQSDeviceScreenIsOn()) FinishUnlock(NO, NO);
    else if (gUnlockCompletion && !LQSDeviceIsLocked()) FinishUnlock(YES, YES);
}
+ (BOOL)requestUnlockWithCompletion:(void (^)(BOOL))completion {
    NSAssert(NSThread.isMainThread, @"Unlock requests must originate on the UI thread");
    if (!completion || gUnlockCompletion) return NO;
    if (!LQSDeviceIsLocked()) { completion(YES); return YES; }
    id manager = LockManager();
    SEL show = NSSelectorFromString(@"setPasscodeVisible:animated:");
    if (![manager respondsToSelector:show]) show = NSSelectorFromString(@"_setPasscodeVisible:animated:");
    NSMethodSignature *signature = [manager methodSignatureForSelector:show];
    if (![manager respondsToSelector:show] || signature.numberOfArguments != 4
        || !BoolType([signature getArgumentTypeAtIndex:2]) || !BoolType([signature getArgumentTypeAtIndex:3])
        || (!BoolType(signature.methodReturnType) && strcmp(signature.methodReturnType, "v"))) return NO;
    BOOL visibilityKnown = NO;
    ReadBool(manager, @"isPasscodeEntryTransientOverlayVisible", &visibilityKnown);
    ReadBool(manager, @"_isPasscodeVisible", &visibilityKnown);
    if (!visibilityKnown) return NO; // cancellation must be observable
    gUnlockCompletion = [completion copy];
    gSawPasscode = NO; gPasscodeGone = 0; gUnlockStart = CACurrentMediaTime();
    [[NSNotificationCenter defaultCenter] postNotificationName:LQSAuthenticationWillBeginNotification object:nil];
    @try {
        if (BoolType(signature.methodReturnType)) {
            if (!((BOOL (*)(id, SEL, BOOL, BOOL))objc_msgSend)(manager, show, YES, YES)) { FinishUnlock(NO, YES); return YES; }
        } else ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(manager, show, YES, YES);
    } @catch (__unused NSException *exception) { FinishUnlock(NO, YES); return YES; }
    if (!gUnlockCompletion) return YES;
    gUnlockTimer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        if (timer != gUnlockTimer) return;
        BOOL screenOn = LQSDeviceScreenIsOn(), locked = LQSDeviceIsLocked();
        BOOL known = NO;
        BOOL visible = ReadBool(manager, @"isPasscodeEntryTransientOverlayVisible", &known);
        visible |= ReadBool(manager, @"_isPasscodeVisible", &known);
        CFTimeInterval now = CACurrentMediaTime();
        if (visible) { gSawPasscode = YES; gPasscodeGone = 0; }
        else if (!gPasscodeGone) gPasscodeGone = now;
        LQSUnlockDecision decision = LQSDecideUnlock(locked, screenOn, gSawPasscode,
            now - gUnlockStart, gPasscodeGone ? now - gPasscodeGone : 0);
        if (decision == LQSUnlockSucceeded) FinishUnlock(YES, YES);
        else if (decision == LQSUnlockCancelled) FinishUnlock(NO, screenOn);
    }];
    [NSRunLoop.mainRunLoop addTimer:gUnlockTimer forMode:NSRunLoopCommonModes];
    return YES;
}
@end
