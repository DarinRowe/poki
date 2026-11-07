#import "InProcess.h"
#import "RecoveredNative.h"
#import <dlfcn.h>

@interface NSObject (PKObservedPrivateAPI)
- (id)initForTouchAtPoint:(CGPoint)point offset:(double)offset;
- (void)moveToPoint:(CGPoint)point atOffset:(double)offset;
- (void)liftUpAtOffset:(double)offset;
- (id)initWithName:(NSString *)name;
- (id)initWithName:(NSString *)name interfaceOrientation:(long long)orientation;
- (void)addPointerEventPath:(id)path;
- (id)daemonProxy;
- (void)_XCT_synthesizeEvent:(id)event implicitConfirmationInterval:(double)interval
    completion:(void (^)(NSError *))completion;
+ (id)sharedDevice;
+ (id)mainScreen;
- (id)accessibilityInterface;
- (id)activeApplications;
- (int)processIdentifier;
- (id)applicationProcessTracker;
- (id)monitoredApplicationWithProcessIdentifier:(int)pid;
- (id)snapshotWithError:(NSError **)error;
- (NSDictionary *)dictionaryRepresentation;
- (id)screenshot;
- (NSData *)PNGRepresentation;
- (void)_XCT_requestBundleIDForPID:(int)pid reply:(void (^)(NSString *, NSError *))reply;
@end

/// Nodes in a snapshot's dictionary, whatever key holds the children.
static NSUInteger PKCount(NSDictionary *node) {
    NSUInteger n = 1;
    for (id value in node.allValues)
        if ([value isKindOfClass:NSArray.class])
            for (id child in value) if ([child isKindOfClass:NSDictionary.class]) n += PKCount(child);
    return n;
}

/// Whether `selector` has exactly this return type and these argument types, as encoded at runtime.
static BOOL PKMatches(NSMethodSignature *signature, const char *result, NSArray<NSString *> *arguments) {
    if (!signature || signature.numberOfArguments != arguments.count + 2 || strcmp(signature.methodReturnType, result)) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++)
        if (strcmp([signature getArgumentTypeAtIndex:i + 2], arguments[i].UTF8String)) return NO;
    return YES;
}

static BOOL PKSignature(id target, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    return [target respondsToSelector:selector] && PKMatches([target methodSignatureForSelector:selector], result, arguments);
}

static BOOL PKInstanceSignature(Class cls, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    return [cls instancesRespondToSelector:selector] && PKMatches([cls instanceMethodSignatureForSelector:selector], result, arguments);
}

@implementation PKTouchPoint
+ (instancetype)at:(CGPoint)point offset:(double)offset {
    PKTouchPoint *p = [self new];
    p->_point = point;
    p->_offset = offset;
    return p;
}
@end

@interface PKOutcome ()
@property (nonatomic) PKDelivery delivery;
@property (nonatomic, nullable) NSString *code;
@property (nonatomic, nullable) NSString *detail;
@property (nonatomic) double seconds;
@property (nonatomic) uint64_t generation;
@end

@implementation PKOutcome
+ (instancetype)delivery:(PKDelivery)delivery code:(NSString *)code detail:(NSString *)detail {
    PKOutcome *o = [self new];
    o.delivery = delivery;
    o.code = code;
    o.detail = detail;
    return o;
}
@end

@implementation PKInProcess {
    SRNativeSession *_sessions;
}

+ (instancetype)shared {
    static PKInProcess *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [PKInProcess new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) _sessions = [SRNativeSession new];
    return self;
}

- (uint64_t)generation { return _sessions.generation; }

- (NSDictionary<NSString *, id> *)prepare {
    NSError *error;
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    id session = nil;
    @try {
        session = [_sessions prepare:&error];
    } @catch (NSException *exception) {
        return @{@"ok": @NO, @"code": @"exception", @"detail": [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason ?: @""]};
    }
    double seconds = NSProcessInfo.processInfo.systemUptime - started;
    if (!session) {
        const char *loader = dlerror();
        NSString *detail = error.localizedDescription ?: @"no session";
        if (loader) detail = [detail stringByAppendingFormat:@" (%s)", loader];
        NSString *code = [error.domain isEqualToString:@"RecoveredNative"] ? error.localizedDescription : [NSString stringWithFormat:@"%@ %ld", error.domain ?: @"unknown", (long)error.code];
        return @{@"ok": @NO, @"code": code ?: @"unknown", @"detail": detail, @"seconds": @(seconds)};
    }
    return @{@"ok": @YES, @"generation": @(_sessions.generation), @"reused": @(_sessions.enableWasReused), @"seconds": @(seconds)};
}

/// The prepared session and its generation, or why there is none.
- (id)current:(uint64_t *)generation outcome:(PKOutcome **)outcome {
    NSError *error;
    id session = nil;
    @try {
        session = [_sessions prepare:&error];
    } @catch (NSException *exception) {
        *outcome = [PKOutcome delivery:PKDeliveryNotSent code:@"exception" detail:exception.reason];
        return nil;
    }
    *generation = _sessions.generation;
    if (!session) *outcome = [PKOutcome delivery:PKDeliveryNotSent code:error.localizedDescription ?: @"no_session" detail:nil];
    return session;
}

- (SRActionContext *)contextFor:(id)session generation:(uint64_t)generation {
    SRNativeSession *sessions = _sessions;
    return [[SRActionContext alloc] initWithOperationID:NSUUID.UUID.UUIDString currentOwner:^BOOL {
        return [sessions isCurrent:session generation:generation];
    }];
}

/// Waits for the one reply of a dispatched action.
- (PKOutcome *)await:(SRActionContext *)context timeout:(double)timeout started:(NSTimeInterval)started generation:(uint64_t)generation {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [context whenRepliesDrain:^{ dispatch_semaphore_signal(done); }];
    BOOL answered = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) == 0;
    PKOutcome *outcome;
    if (!answered) {
        outcome = [PKOutcome delivery:PKDeliveryUnknown code:@"reply_timeout" detail:[NSString stringWithFormat:@"no reply from testmanagerd within %.1f s", timeout]];
    } else {
        id accepted = context.evidence[@"inputAccepted"];
        BOOL ok = [accepted isKindOfClass:NSNumber.class] && [accepted boolValue];
        outcome = ok ? [PKOutcome delivery:PKDeliverySent code:nil detail:nil]
                     : [PKOutcome delivery:PKDeliveryUnknown code:@"reply_error" detail:@"testmanagerd answered with an error"];
    }
    outcome.seconds = NSProcessInfo.processInfo.systemUptime - started;
    outcome.generation = generation;
    return outcome;
}

- (PKOutcome *)touch:(NSArray<NSArray<PKTouchPoint *> *> *)fingers timeout:(double)timeout {
    PKOutcome *refused;
    uint64_t generation = 0;
    id session = [self current:&generation outcome:&refused];
    if (!session) return refused;
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    if (!fingers.count || !PKInstanceSignature(pathClass, @selector(initForTouchAtPoint:offset:), "@", @[@"{CGPoint=dd}", @"d"]) ||
        !PKInstanceSignature(pathClass, @selector(moveToPoint:atOffset:), "v", @[@"{CGPoint=dd}", @"d"]) ||
        !PKInstanceSignature(pathClass, @selector(liftUpAtOffset:), "v", @[@"d"])) {
        return [PKOutcome delivery:PKDeliveryNotSent code:@"touch_event_abi_mismatch" detail:@"XCPointerEventPath has no touch path with the expected signature"];
    }
    BOOL oriented = PKInstanceSignature(recordClass, @selector(initWithName:interfaceOrientation:), "@", @[@"@", @"q"]);
    if (!oriented && ![recordClass instancesRespondToSelector:@selector(initWithName:)]) {
        return [PKOutcome delivery:PKDeliveryNotSent code:@"event_api_unavailable" detail:@"no XCSynthesizedEventRecord"];
    }
    id record = oriented ? [[recordClass alloc] initWithName:@"Poki touch" interfaceOrientation:1] : [[recordClass alloc] initWithName:@"Poki touch"];
    if (![record respondsToSelector:@selector(addPointerEventPath:)]) {
        return [PKOutcome delivery:PKDeliveryNotSent code:@"event_dispatch_api_unavailable" detail:@"XCSynthesizedEventRecord cannot take a path"];
    }
    for (NSArray<PKTouchPoint *> *finger in fingers) {
        if (!finger.count) return [PKOutcome delivery:PKDeliveryNotSent code:@"invalid_touch" detail:@"a finger without points"];
        id path = [[pathClass alloc] initForTouchAtPoint:finger.firstObject.point offset:finger.firstObject.offset];
        for (NSUInteger i = 1; i < finger.count; i++) [path moveToPoint:finger[i].point atOffset:finger[i].offset];
        [path liftUpAtOffset:finger.lastObject.offset];
        [record addPointerEventPath:path];
    }
    id proxy = [session respondsToSelector:@selector(daemonProxy)] ? [session daemonProxy] : nil;
    SEL dispatch = @selector(_XCT_synthesizeEvent:implicitConfirmationInterval:completion:);
    if (!proxy || !PKSignature(proxy, dispatch, "v", @[@"@", @"d", @"@?"])) {
        return [PKOutcome delivery:PKDeliveryNotSent code:@"event_dispatch_abi_mismatch" detail:@"the daemon proxy has no event synthesis with the expected signature"];
    }
    SRActionContext *context = [self contextFor:session generation:generation];
    NSError *error;
    if (![context commit:&error]) return [PKOutcome delivery:PKDeliveryNotSent code:error.localizedDescription detail:nil];
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    [context beginReply];
    [proxy _XCT_synthesizeEvent:record implicitConfirmationInterval:0 completion:^(NSError *replyError) {
        (void)[record class];
        [context receiveReply:replyError];
    }];
    [context markDispatched];
    return [self await:context timeout:timeout started:started generation:generation];
}

- (PKOutcome *)type:(NSString *)text timeout:(double)timeout {
    PKOutcome *refused;
    uint64_t generation = 0;
    id session = [self current:&generation outcome:&refused];
    if (!session) return refused;
    SRActionContext *context = [self contextFor:session generation:generation];
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    NSError *error;
    if (!SRInsertText(session, text, context, &error)) {
        return [PKOutcome delivery:PKDeliveryNotSent code:error.localizedDescription ?: @"text_not_sent" detail:nil];
    }
    return [self await:context timeout:timeout started:started generation:generation];
}

- (NSDictionary<NSString *, id> *)readProbe {
    NSMutableDictionary *out = [NSMutableDictionary new];
    PKOutcome *refused;
    uint64_t generation = 0;
    id session = [self current:&generation outcome:&refused];
    if (!session) { out[@"error"] = refused.code ?: @"no_session"; return out; }
    NSTimeInterval t = NSProcessInfo.processInfo.systemUptime;
    id app = nil;
    @try {
        id ax = [[NSClassFromString(@"XCUIDevice") sharedDevice] accessibilityInterface];
        NSArray *apps = [ax activeApplications];
        out[@"front_count"] = @(apps.count);
        int pid = apps.count ? [apps.firstObject processIdentifier] : 0;
        out[@"front_pid"] = @(pid);
        if (pid) {
            dispatch_semaphore_t got = dispatch_semaphore_create(0);
            __block NSString *bundle;
            [[session daemonProxy] _XCT_requestBundleIDForPID:pid reply:^(NSString *value, NSError *error) {
                bundle = value; dispatch_semaphore_signal(got);
            }];
            dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
            out[@"front_bundle"] = bundle ?: @"?";
            app = [[ax applicationProcessTracker] monitoredApplicationWithProcessIdentifier:pid];
        }
        out[@"front_ok"] = @(app != nil);
    } @catch (NSException *e) {
        out[@"front_error"] = [NSString stringWithFormat:@"%@: %@", e.name, e.reason];
    }
    out[@"front_seconds"] = @(NSProcessInfo.processInfo.systemUptime - t);
    t = NSProcessInfo.processInfo.systemUptime;
    @try {
        NSError *error;
        id snapshot = app ? [app snapshotWithError:&error] : nil;
        NSDictionary *tree = [snapshot dictionaryRepresentation];
        out[@"tree_ok"] = @(tree != nil);
        out[@"tree_elements"] = @(tree ? PKCount(tree) : 0);
        if (error) out[@"tree_error"] = error.localizedDescription;
    } @catch (NSException *e) {
        out[@"tree_error"] = [NSString stringWithFormat:@"%@: %@", e.name, e.reason];
    }
    out[@"tree_seconds"] = @(NSProcessInfo.processInfo.systemUptime - t);
    t = NSProcessInfo.processInfo.systemUptime;
    @try {
        NSData *png = [[[NSClassFromString(@"XCUIScreen") mainScreen] screenshot] PNGRepresentation];
        out[@"picture_ok"] = @(png.length > 0);
        out[@"picture_bytes"] = @(png.length);
    } @catch (NSException *e) {
        out[@"picture_error"] = [NSString stringWithFormat:@"%@: %@", e.name, e.reason];
    }
    out[@"picture_seconds"] = @(NSProcessInfo.processInfo.systemUptime - t);
    return out;
}

@end
