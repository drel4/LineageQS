#import <Foundation/Foundation.h>

FOUNDATION_EXTERN NSString *const LQSAuthenticationWillBeginNotification;
FOUNDATION_EXTERN NSString *const LQSAuthenticationDidFinishNotification;
FOUNDATION_EXTERN NSString *const LQSLockStateChangedNotification;

// Reads the real SpringBoard UI lock state. No authentication-result spoofing,
// cached "unlocked" grant or custom passcode implementation is used.
FOUNDATION_EXTERN BOOL LQSDeviceIsLocked(void);
FOUNDATION_EXTERN BOOL LQSDeviceScreenIsOn(void);
FOUNDATION_EXTERN BOOL LQSRequiresUnlock(NSString *identifier);

@interface LQSAuthentication : NSObject
+ (BOOL)isPending;
+ (BOOL)requestUnlockWithCompletion:(void (^)(BOOL unlocked))completion;
+ (void)cancel;
+ (void)lockStateDidChange;
@end
