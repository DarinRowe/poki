#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// How a dispatched action ended, as far as the phone is concerned.
typedef NS_ENUM(NSInteger, PKDelivery) {
    PKDeliveryNotSent = 0,
    PKDeliverySent = 1,
    /// Dispatched, and no answer came in time: it may or may not have happened.
    PKDeliveryUnknown = 2,
};

/// One point of a finger's path: where it is `offset` seconds after the gesture starts.
@interface PKTouchPoint : NSObject
@property (nonatomic, readonly) CGPoint point;
@property (nonatomic, readonly) double offset;
+ (instancetype)at:(CGPoint)point offset:(double)offset;
@end

@interface PKOutcome : NSObject
@property (nonatomic, readonly) PKDelivery delivery;
/// A short code when the action was refused or failed ("native_session_invalidated", "reply_timeout").
@property (nonatomic, readonly, nullable) NSString *code;
@property (nonatomic, readonly, nullable) NSString *detail;
/// From commit to the daemon's reply, in seconds.
@property (nonatomic, readonly) double seconds;
@property (nonatomic, readonly) uint64_t generation;
@end

/// UI automation from Poki's own process: the XCTest daemon session (testmanagerd), Automation Mode,
/// and synthesized touch and text events. No runner app and no port. Every method blocks, so call it
/// from a serial worker queue, never the main thread: the first enable waits for the owner to
/// authenticate in iOS's prompt.
@interface PKInProcess : NSObject
+ (instancetype)shared;
/// Loads the Developer libraries, opens the daemon session and enables Automation Mode, or reuses an
/// enable of the same session and generation. Keys: ok, code, detail, generation, reused, seconds.
- (NSDictionary<NSString *, id> *)prepare;
/// One or more fingers, each a path pressed at its first point and lifted at its last, sent as one
/// event. Waits up to `timeout` for the daemon's reply; a dispatched event is never sent again.
- (PKOutcome *)touch:(NSArray<NSArray<PKTouchPoint *> *> *)fingers timeout:(double)timeout;
/// Types into whatever field has the keyboard focus. Does not focus or clear.
- (PKOutcome *)type:(NSString *)text timeout:(double)timeout;
/// Whether the screen can be read from here: the front app (accessibility), its element tree, and a
/// screenshot, each timed. Keys per part: *_ok, *_seconds, *_error, and counts.
- (NSDictionary<NSString *, id> *)readProbe;
/// A PNG of the main screen, or nil and why.
- (nullable NSData *)screenshot:(NSString *_Nullable *_Nullable)code;
/// The app in front: bundleId, name, pid. Empty when accessibility gives none.
- (NSDictionary<NSString *, id> *)frontApp;
/// The front app's elements in WebDriverAgent's XML source format, and the element with the
/// keyboard focus (keys value, x, y, width, height) when there is one.
- (nullable NSString *)sourceXML:(NSDictionary *_Nullable *_Nullable)focused code:(NSString *_Nullable *_Nullable)code;
/// home, lock, volumeUp or volumeDown. Nil when pressed, else why not.
- (nullable NSString *)press:(NSString *)name;
/// launch, activate or terminate an app by its bundle id. Nil when done, else why not.
- (nullable NSString *)app:(NSString *)bundle action:(NSString *)action;
- (BOOL)screenLocked;
/// The current session's generation: it goes up when the daemon session is replaced.
- (uint64_t)generation;
@end

NS_ASSUME_NONNULL_END
