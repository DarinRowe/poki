#import "RecoveredNative.h"
#import <dlfcn.h>
#import <unistd.h>

// Selectors found by inspecting XCTest private classes at run time (NativeHIDProbe), not the public SDK.
@interface NSObject (SRObservedPrivateAPI)
+ (id)sharedSessionPromiseAndImplicitlyInitiateSession:(BOOL)start;
- (BOOL)promiseFulfilled;
- (id)value;
- (NSError *)error;
- (BOOL)supportsAutomationMode;
- (BOOL)enableAutomationModeWithError:(NSError **)error;
- (id)registerInvalidationHandler:(void (^)(void))handler;
- (void)unregisterInvalidationHandlerWithToken:(id)token;
- (id)daemonProxy;
- (id)initForTextInput;
- (void)typeText:(NSString *)text atOffset:(double)offset
    typingSpeed:(NSUInteger)speed shouldRedact:(BOOL)redact;
- (id)initWithName:(NSString *)name;
- (void)addPointerEventPath:(id)path;
- (void)_XCT_synthesizeEvent:(id)event implicitConfirmationInterval:(double)interval
    completion:(void (^)(NSError *))completion;
+ (id)connectionForInitiatingSharedSession;
+ (void)sessionWithConnection:(id)connection completion:(void (^)(id, NSError *))completion;
- (id)connection;
- (void)invalidate;
@end

static BOOL SRFail(NSError **error, NSString *code) {
    if (error) *error = [NSError errorWithDomain:@"RecoveredNative" code:1
        userInfo:@{NSLocalizedDescriptionKey:code}];
    return NO;
}

static BOOL SRABI(id target, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (![target respondsToSelector:selector] || !signature ||
        signature.numberOfArguments != arguments.count + 2 ||
        strcmp(signature.methodReturnType, result)) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++)
        if (strcmp([signature getArgumentTypeAtIndex:i + 2], arguments[i].UTF8String)) return NO;
    return YES;
}

@implementation SRActionContext {
    NSRecursiveLock *_lock;
    NSString *_operationID;
    BOOL (^_currentOwner)(void);
    BOOL _committed, _dispatched, _received;
    NSUInteger _pending;
    NSError *_replyError;
    NSMutableArray<dispatch_block_t> *_drain;
}
- (instancetype)initWithOperationID:(NSString *)operationID currentOwner:(BOOL (^)(void))owner {
    if ((self = [super init])) {
        _lock = [NSRecursiveLock new]; _operationID = [operationID copy];
        _currentOwner = [owner copy]; _drain = [NSMutableArray new];
    }
    return self;
}
- (BOOL)commit:(NSError **)error {
    [_lock lock];
    BOOL current = _currentOwner && _currentOwner();
    BOOL accepted = current && !_committed;
    if (accepted) _committed = YES;
    [_lock unlock];
    return accepted || SRFail(error, current ? @"duplicate_native_dispatch" : @"native_action_superseded");
}
- (void)beginReply { [_lock lock]; _pending++; [_lock unlock]; }
- (void)markDispatched { [_lock lock]; _dispatched = YES; [_lock unlock]; }
- (void)receiveReply:(NSError *)error {
    [_lock lock];
    if (!_received) { _received = YES; _replyError = error; if (_pending) _pending--; }
    NSArray *blocks = _pending ? @[] : [_drain copy];
    if (!_pending) [_drain removeAllObjects];
    [_lock unlock];
    for (dispatch_block_t block in blocks) block();
}
- (void)whenRepliesDrain:(dispatch_block_t)continuation {
    [_lock lock];
    BOOL drained = _pending == 0;
    if (!drained) [_drain addObject:[continuation copy]];
    [_lock unlock];
    if (drained) continuation();
}
- (NSDictionary *)evidence {
    [_lock lock];
    NSDictionary *result = @{@"operationID":_operationID,
        @"inputAttempted":@(_committed), @"inputDispatched":@(_dispatched),
        @"acknowledgementPending":@(_pending > 0), @"acknowledgementPolicy":@"no_wait",
        @"inputAccepted":_received ? @(_replyError == nil) : NSNull.null,
        @"deliveryProven":@NO, @"pendingReplies":@(_pending)};
    [_lock unlock];
    return result;
}
@end

@implementation SRNativeSession {
    NSLock *_prepareLock;
    NSRecursiveLock *_lifecycleLock;
    id _observed, _token, _enabled;
    uint64_t _generation, _enabledGeneration;
    BOOL _invalidated, _reused, _handlerFired;
    NSString *_closeDetail;
    NSMutableSet<NSString *> *_loaded;
}
- (instancetype)init {
    if ((self = [super init])) {
        _prepareLock = [NSLock new]; _lifecycleLock = [NSRecursiveLock new];
        _loaded = [NSMutableSet new];
    }
    return self;
}
- (uint64_t)generation {
    [_lifecycleLock lock]; uint64_t value = _generation; [_lifecycleLock unlock]; return value;
}
- (BOOL)enableWasReused {
    [_lifecycleLock lock]; BOOL value = _reused; [_lifecycleLock unlock]; return value;
}
- (BOOL)isCurrent:(id)session generation:(uint64_t)generation {
    [_lifecycleLock lock];
    BOOL value = session == _observed && generation == _generation && !_invalidated && _token != nil;
    [_lifecycleLock unlock]; return value;
}
/// Ends the current session: its connection to testmanagerd is invalidated, which ends Automation
/// Mode (and iOS's banner) for this process. The next prepare opens a new session with a new
/// generation; an action meant for the old one is refused as native_session_invalidated.
- (BOOL)close {
    [_lifecycleLock lock];
    id session = _observed;
    BOOL open = session && !_invalidated && _token != nil;
    _invalidated = YES; _enabled = nil; _enabledGeneration = 0; _handlerFired = NO;
    [_lifecycleLock unlock];
    if (!open) return NO;
    id link = [session respondsToSelector:@selector(connection)] ? [session connection] : nil;
    BOOL invalidated = [link respondsToSelector:@selector(invalidate)];
    if (invalidated) [link invalidate];
    // testmanagerd's side of the connection going away is what ends Automation Mode: the session's
    // invalidation handler fires when it does. Waited for briefly, and reported (closeDetail).
    BOOL fired = NO;
    for (int i = 0; i < 100 && !fired; i++) {
        [_lifecycleLock lock]; fired = _handlerFired; [_lifecycleLock unlock];
        if (!fired) usleep(10000);
    }
    [_lifecycleLock lock];
    _closeDetail = [NSString stringWithFormat:@"link=%@ invalidate=%@ handler_fired=%@",
                    link ? NSStringFromClass([link class]) : @"none", invalidated ? @"yes" : @"no", fired ? @"yes" : @"no"];
    [_lifecycleLock unlock];
    NSLog(@"SRNativeSession close: %@", _closeDetail);
    return YES;
}
- (NSString *)closeDetail {
    [_lifecycleLock lock]; NSString *value = _closeDetail; [_lifecycleLock unlock]; return value;
}
- (id)prepare:(NSError **)error {
    [_prepareLock lock];
    @try { return [self prepareLocked:error]; }
    @finally { [_prepareLock unlock]; }
}
- (id)prepareLocked:(NSError **)error {
    // Ordered NSArray recovered from 0x100ce91a8 -> 0x100ce7ef0.
    NSArray *paths = @[
        @"/System/Developer/Library/PrivateFrameworks/XCTestSupport.framework/XCTestSupport",
        @"/System/Developer/usr/lib/lib_TestingInterop.dylib",
        @"/System/Developer/Library/PrivateFrameworks/XCTestCore.framework/XCTestCore",
        @"/System/Developer/Library/Frameworks/XCUIAutomation.framework/XCUIAutomation"];
#if TARGET_OS_SIMULATOR
    // A simulator has no Developer disk image: the same files are in Xcode's simulator platform.
    NSString *root = NSProcessInfo.processInfo.environment[@"POKI_SIMULATOR_DEVELOPER_DIR"];
    if (root.length) {
        // Xcode 26.3's simulator platform ships no lib_TestingInterop.dylib (XCTestCore loads without
        // it there); a file that is not in the platform is left out rather than failing the session.
        NSMutableArray *moved = [NSMutableArray array];
        for (NSString *path in paths) {
            NSString *inPlatform = [root stringByAppendingString:[path substringFromIndex:@"/System/Developer".length]];
            if ([NSFileManager.defaultManager fileExistsAtPath:inPlatform]) [moved addObject:inPlatform];
        }
        paths = moved;
    }
#endif
    for (NSString *path in paths) {
        if ([_loaded containsObject:path]) continue;
        if (!dlopen(path.UTF8String, RTLD_NOW | RTLD_GLOBAL)) {
            SRFail(error, @"developer_framework_unavailable"); return nil;
        }
        [_loaded addObject:path]; // Keep loaded for the lifetime of the process.
    }
    Class cls = NSClassFromString(@"XCTRunnerDaemonSession");
    if (![cls respondsToSelector:@selector(sharedSessionPromiseAndImplicitlyInitiateSession:)]) {
        SRFail(error, @"session_api_unavailable"); return nil;
    }
    id promise = [cls sharedSessionPromiseAndImplicitlyInitiateSession:YES];
    for (NSString *selector in @[@"promiseFulfilled", @"value", @"error"])
        if (![promise respondsToSelector:NSSelectorFromString(selector)]) {
            SRFail(error, @"promise_api_unavailable"); return nil;
        }
    for (NSUInteger i = 0; i < 300 && ![promise promiseFulfilled]; i++) usleep(10000);
    if (![promise promiseFulfilled]) { SRFail(error, @"session_timeout"); return nil; }
    if ([promise error]) { if (error) *error = [promise error]; return nil; }
    id session = [promise value];
    [_lifecycleLock lock];
    // The session in use stays in use while it is current, whether it is XCTest's shared one or one
    // of this process's own; the shared promise is read only for the first session. After a close
    // (ours, or testmanagerd's) a session of this process's own is opened: the shared promise keeps
    // holding the closed one, and enabling automation on it again hangs for a minute. With
    // POKI_INPROCESS_OWNED_SESSION set, the shared session is never used at all.
    BOOL owned = getenv("POKI_INPROCESS_OWNED_SESSION") != NULL;
    BOOL closed;
    if (_observed && !_invalidated && _token) { session = _observed; closed = NO; }
    else closed = (_observed != nil && _invalidated) || owned;
    [_lifecycleLock unlock];
    if (closed) {
        // The shared promise still holds the session that was closed: open one of this process's
        // own, on a new connection (XCTest's sessionWithConnection:, as a UI test runner does).
        if (![cls respondsToSelector:@selector(connectionForInitiatingSharedSession)] ||
            ![cls respondsToSelector:@selector(sessionWithConnection:completion:)]) {
            SRFail(error, @"session_reopen_api_unavailable"); return nil;
        }
        id connection = [cls connectionForInitiatingSharedSession];
        __block id opened; __block NSError *failure;
        dispatch_semaphore_t ready = dispatch_semaphore_create(0);
        [cls sessionWithConnection:connection completion:^(id s, NSError *e) { opened = s; failure = e; dispatch_semaphore_signal(ready); }];
        if (dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC))) { SRFail(error, @"session_timeout"); return nil; }
        if (!opened) { if (error) *error = failure ?: [NSError errorWithDomain:@"RecoveredNative" code:1 userInfo:@{NSLocalizedDescriptionKey: @"session_reopen_failed"}]; return nil; }
        session = opened;
    }
    if (![session respondsToSelector:@selector(supportsAutomationMode)] ||
        ![session supportsAutomationMode] ||
        ![session respondsToSelector:@selector(enableAutomationModeWithError:)] ||
        ![session respondsToSelector:@selector(registerInvalidationHandler:)]) {
        SRFail(error, @"automation_api_unavailable"); return nil;
    }
    [_lifecycleLock lock];
    if (_observed != session) {
        id oldSession = _observed, oldToken = _token;
        _observed = session; _token = nil; _enabled = nil;
        _enabledGeneration = 0; _invalidated = NO; _generation++;
        uint64_t generation = _generation;
        [_lifecycleLock unlock];
        if (oldToken && [oldSession respondsToSelector:@selector(unregisterInvalidationHandlerWithToken:)])
            [oldSession unregisterInvalidationHandlerWithToken:oldToken];
        __weak SRNativeSession *weakSelf = self;
        id token = [session registerInvalidationHandler:^{
            SRNativeSession *owner = weakSelf;
            if (!owner) return;
            [owner->_lifecycleLock lock];
            if (owner->_generation == generation) {
                owner->_invalidated = YES; owner->_enabled = nil; owner->_enabledGeneration = 0;
                owner->_handlerFired = YES;
            }
            [owner->_lifecycleLock unlock];
        }];
        [_lifecycleLock lock]; _token = token;
    }
    uint64_t generation = _generation;
    BOOL current = !_invalidated && _token != nil;
    _reused = current && _enabled == session && _enabledGeneration == generation;
    BOOL reused = _reused;
    [_lifecycleLock unlock];
    if (!current) { SRFail(error, @"native_session_invalidated"); return nil; }
    if (reused) return session;
    if (![session enableAutomationModeWithError:error]) return nil;
    [_lifecycleLock lock];
    current = _observed == session && _generation == generation && !_invalidated && _token != nil;
    if (current) { _enabled = session; _enabledGeneration = generation; }
    [_lifecycleLock unlock];
    if (!current) { SRFail(error, @"native_session_invalidated"); return nil; }
    return session;
}
@end

NSDictionary *SRInsertText(id session, NSString *text, SRActionContext *context, NSError **error) {
    return SRInsertTextAtSpeed(session, text, 120, context, error);
}

NSDictionary *SRInsertTextAtSpeed(id session, NSString *text, NSUInteger speed, SRActionContext *context, NSError **error) {
    if (!text.length || [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 1024 * 1024) {
        SRFail(error, @"invalid_text"); return nil;
    }
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    if (![pathClass instancesRespondToSelector:@selector(initForTextInput)] ||
        ![recordClass instancesRespondToSelector:@selector(initWithName:)]) {
        SRFail(error, @"event_api_unavailable"); return nil;
    }
    id path = [[pathClass alloc] initForTextInput];
    SEL typing = @selector(typeText:atOffset:typingSpeed:shouldRedact:);
    NSMethodSignature *signature = [path methodSignatureForSelector:typing];
    NSString *speedType = signature.numberOfArguments == 6 ?
        [NSString stringWithUTF8String:[signature getArgumentTypeAtIndex:4]] : @"";
    NSString *boolType = signature.numberOfArguments == 6 ?
        [NSString stringWithUTF8String:[signature getArgumentTypeAtIndex:5]] : @"";
    // ARM64 evidence gives integer 120 and byte 1; signedness is runtime-checked.
    if (![@[@"Q", @"q"] containsObject:speedType] || ![@[@"B", @"c"] containsObject:boolType] ||
        !SRABI(path, typing, "v", @[@"@", @"d", speedType, boolType])) {
        SRFail(error, @"text_event_abi_mismatch"); return nil;
    }
    // typingSpeed is characters a second (1-240 kept; XCTest's own default is 60).
    [path typeText:text atOffset:0 typingSpeed:MIN(240, MAX(1, speed)) shouldRedact:YES];
    id record = [[recordClass alloc] initWithName:@"Recovered text"];
    if (![record respondsToSelector:@selector(addPointerEventPath:)] ||
        ![session respondsToSelector:@selector(daemonProxy)]) {
        SRFail(error, @"event_dispatch_api_unavailable"); return nil;
    }
    [record addPointerEventPath:path];
    id proxy = [session daemonProxy];
    SEL dispatch = @selector(_XCT_synthesizeEvent:implicitConfirmationInterval:completion:);
    // Exact original ABI array: @, d, @? at 0x100ce8f98.
    if (!SRABI(proxy, dispatch, "v", @[@"@", @"d", @"@?"])) {
        SRFail(error, @"event_dispatch_abi_mismatch"); return nil;
    }
    if (![context commit:error]) return nil;
    [context beginReply];
    [proxy _XCT_synthesizeEvent:record implicitConfirmationInterval:0 completion:^(NSError *replyError) {
        (void)[record class]; // Retain the record until the actual acknowledgement arrives.
        [context receiveReply:replyError];
    }];
    [context markDispatched];
    return [context evidence];
}
