#import "InProcess.h"
#import "RecoveredNative.h"
#import <dlfcn.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>

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
- (id)systemApplication;
- (NSDictionary *)defaultParameters;
- (id)screenshot;
- (NSData *)PNGRepresentation;
- (void)_XCT_requestBundleIDForPID:(int)pid reply:(void (^)(NSString *, NSError *))reply;
- (NSArray *)children;
- (long long)elementType;
- (CGRect)frame;
- (NSString *)identifier;
- (NSString *)label;
- (id)value;
- (BOOL)hasFocus;
- (BOOL)hasKeyboardFocus;
- (BOOL)loadAccessibility:(NSError **)error;
- (void)_XCT_launchApplicationWithBundleID:(NSString *)bundle arguments:(NSArray *)arguments environment:(NSDictionary *)environment completion:(void (^)(NSError *))completion;
- (void)_XCT_terminateApplicationWithBundleID:(NSString *)bundle completion:(void (^)(NSError *))completion;
- (void)pressButton:(long long)button;
+ (id)deviceEventWithPage:(unsigned int)page usage:(unsigned int)usage duration:(double)duration;
- (BOOL)performDeviceEvent:(id)event error:(NSError **)error;
- (void)pressLockButton;
+ (id)connectionForInitiatingSharedSession;
+ (void)sessionWithConnection:(id)connection completion:(void (^)(id, NSError *))completion;
- (BOOL)enableAutomationModeWithError:(NSError **)error;
- (id)registerInvalidationHandler:(void (^)(void))handler;
- (id)connection;
- (void)invalidate;
@end

/// XCUIElementType's names, by value (XCUIElementTypes.h).
static NSString *PKTypeName(long long type) {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [@"Any Other Application Group Window Sheet Drawer Alert Dialog Button RadioButton RadioGroup CheckBox DisclosureTriangle PopUpButton ComboBox MenuButton ToolbarButton Popover Keyboard Key NavigationBar TabBar TabGroup Toolbar StatusBar Table TableRow TableColumn Outline OutlineRow Browser CollectionView Slider PageIndicator ProgressIndicator ActivityIndicator SegmentedControl Picker PickerWheel Switch Toggle Link Image Icon SearchField ScrollView ScrollBar StaticText TextField SecureTextField DatePicker TextView Menu MenuItem MenuBar MenuBarItem Map WebView IncrementArrow DecrementArrow Timeline RatingIndicator ValueIndicator SplitGroup Splitter RelevanceIndicator ColorWell HelpTag Matte DockItem Ruler RulerMarker Grid LevelIndicator Cell LayoutArea LayoutItem Handle Stepper Tab TouchBar StatusItem" componentsSeparatedByString:@" "];
    });
    return type >= 0 && type < (long long)names.count ? names[type] : @"Other";
}

static NSString *PKEscape(NSString *s) {
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
    [s enumerateSubstringsInRange:NSMakeRange(0, s.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *c, NSRange r, NSRange e, BOOL *stop) {
        if ([c isEqualToString:@"&"]) [out appendString:@"&amp;"];
        else if ([c isEqualToString:@"<"]) [out appendString:@"&lt;"];
        else if ([c isEqualToString:@">"]) [out appendString:@"&gt;"];
        else if ([c isEqualToString:@"\""]) [out appendString:@"&quot;"];
        else if ([c isEqualToString:@"\n"]) [out appendString:@"&#10;"];
        else if (c.length == 1 && [c characterAtIndex:0] < 0x20) {}
        else [out appendString:c];
    }];
    return out;
}

static NSString *PKText(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}

static BOOL PKMatches(NSMethodSignature *signature, const char *result, NSArray<NSString *> *arguments);

typedef id (*PKSnapshotRequest)(id, SEL, id, id, id, NSError **);
typedef id (*PKElementAtPoint)(id, SEL, CGPoint, NSError **);
typedef id (*PKMapAttributes)(id, SEL, id, BOOL);

/// XCUIApplication refuses to exist outside a UI test bundle ("Device is not configured for UI
/// testing"), so the screen is read the way WebDriverAgent's FBXCAXClientProxy does: the AX client's
/// own elements and snapshot request, which testmanagerd answers for any process with a session.
static id PKAXClient(void) {
    id device = [NSClassFromString(@"XCUIDevice") sharedDevice];
    return [device respondsToSelector:@selector(accessibilityInterface)] ? [device accessibilityInterface] : nil;
}

static int PKAXPid(id element) {
    SEL selector = @selector(processIdentifier);
    if (!element || ![element respondsToSelector:selector]) return 0;
    const char *type = [element methodSignatureForSelector:selector].methodReturnType;
    if (type && !strcmp(type, @encode(int))) return ((int (*)(id, SEL))objc_msgSend)(element, selector);
    return (int)((long long (*)(id, SEL))objc_msgSend)(element, selector);
}

static NSArray *PKActiveApplications(id ax) {
    id active = [ax respondsToSelector:@selector(activeApplications)] ? [ax activeApplications] : nil;
    return [active isKindOfClass:NSArray.class] ? active : @[];
}

static id PKRequestSnapshot(id ax, id element, NSInteger maxDepth, NSInteger maxNodes, NSString **code);

/// The front app's AX element. One active app is the front one. Several (an alert over an app, split
/// screen, picture in picture): SpringBoard set aside, the one owning the screen's centre.
static id PKForegroundElement(id ax, NSString *(^bundleForPID)(int)) {
    NSArray *active = PKActiveApplications(ax);
    if (active.count == 1 && PKAXPid(active.firstObject) > 0) return active.firstObject;
    id system = [ax respondsToSelector:@selector(systemApplication)] ? [ax systemApplication] : nil;
    int springBoardPID = PKAXPid(system);
    NSMutableArray *candidates = [NSMutableArray array];
    id springBoard = nil;
    for (id element in active) {
        int pid = PKAXPid(element);
        if (pid <= 0) continue;
        BOOL isSpringBoard = springBoardPID > 0 ? pid == springBoardPID : [bundleForPID(pid) isEqualToString:@"com.apple.springboard"];
        if (isSpringBoard) springBoard = element; else [candidates addObject:element];
    }
    if (candidates.count == 1) return candidates.firstObject;
    if (!candidates.count) return springBoard ?: system;
    SEL hitTest = NSSelectorFromString(@"accessibilityElementForElementAtPoint:error:");
    CGRect screen = system ? [PKRequestSnapshot(ax, system, 1, 1, NULL) frame] : CGRectNull;
    if (!CGRectIsEmpty(screen) && [ax respondsToSelector:hitTest]) {
        NSError *error;
        id hit = nil;
        @try { hit = ((PKElementAtPoint)objc_msgSend)(ax, hitTest, CGPointMake(CGRectGetMidX(screen), CGRectGetMidY(screen)), &error); }
        @catch (__unused NSException *e) {}
        int hitPID = PKAXPid(hit);
        for (id element in candidates) if (hitPID > 0 && PKAXPid(element) == hitPID) return element;
    }
    return candidates.firstObject;
}

/// The attributes the XML needs and no more: each extra one (visibility, hittability) costs the AX
/// server more round trips per element.
static NSArray *PKSnapshotAttributes(void) {
    static NSArray *attributes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *keyPaths = @[@"elementType", @"identifier", @"label", @"value", @"placeholderValue", @"frame",
                                          @"enabled", @"selected", @"hasFocus", @"hasKeyboardFocus", @"children"];
        NSArray *mappedAttributes = keyPaths;
        Class snapshotClass = NSClassFromString(@"XCElementSnapshot");
        SEL mapSelector = NSSelectorFromString(@"axAttributesForElementSnapshotKeyPaths:isMacOS:");
        if ([snapshotClass respondsToSelector:mapSelector]) {
            id mapped = ((PKMapAttributes)objc_msgSend)(snapshotClass, mapSelector, keyPaths, NO);
            if ([mapped isKindOfClass:NSSet.class]) mapped = [(NSSet *)mapped allObjects];
            if ([mapped isKindOfClass:NSArray.class] && [(NSArray *)mapped count] > 0) {
                NSArray<NSString *> *needed = @[@"ElementType", @"Identifier", @"Label", @"Value", @"PlaceholderValue", @"Frame",
                                                @"Enabled", @"Selected", @"Focus"];
                NSMutableArray *filtered = [NSMutableArray array];
                for (id attribute in (NSArray *)mapped) {
                    NSString *name = [attribute description];
                    for (NSString *suffix in needed) if ([name hasSuffix:suffix]) { [filtered addObject:attribute]; break; }
                }
                mappedAttributes = filtered.count > 0 ? filtered.copy : mapped;
            }
        }
        attributes = mappedAttributes;
    });
    return attributes;
}

static id PKRequestSnapshot(id ax, id element, NSInteger maxDepth, NSInteger maxNodes, NSString **code) {
    SEL selector = @selector(requestSnapshotForElement:attributes:parameters:error:);
    if (![ax respondsToSelector:selector] || !PKMatches([ax methodSignatureForSelector:selector], "@", @[@"@", @"@", @"@", @"^@"])) {
        if (code) *code = @"snapshot_api_unavailable";
        return nil;
    }
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    id defaults = [ax respondsToSelector:@selector(defaultParameters)] ? [ax defaultParameters] : nil;
    if ([defaults isKindOfClass:NSDictionary.class]) [parameters addEntriesFromDictionary:defaults];
    parameters[@"maxDepth"] = @(MAX(1, maxDepth));
    parameters[@"maxChildren"] = @(MAX(1, maxNodes));
    parameters[@"maxArrayCount"] = @(MAX(1, maxNodes));
    parameters[@"traverseFromParentsToChildren"] = @YES;
    NSError *error;
    id result = nil;
    @try {
        result = ((PKSnapshotRequest)objc_msgSend)(ax, selector, element, PKSnapshotAttributes(), parameters.copy, &error);
    } @catch (NSException *e) {
        if (code) *code = [NSString stringWithFormat:@"%@: %@", e.name, e.reason];
        return nil;
    }
    if (!result) {
        if (code) *code = error.localizedDescription ?: @"no_snapshot";
        return nil;
    }
    id root = nil;
    @try { root = [result valueForKey:@"_rootElementSnapshot"]; } @catch (__unused NSException *e) {}
    return root ?: result;
}

/// The AX server can refuse a deep request; each shallower depth is tried once before giving up.
static id PKSnapshotTree(id ax, id element, NSString **code) {
    for (NSNumber *depth in @[@64, @56, @40, @24, @12]) {
        id root = PKRequestSnapshot(ax, element, depth.integerValue, 10000, code);
        if (root) { if (code) *code = nil; return root; }
    }
    return nil;
}

static NSUInteger PKCount(id node) {
    NSUInteger n = 1;
    for (id child in [node children]) n += PKCount(child);
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
    uint64_t _accessibilityGeneration;
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

- (nullable NSData *)screenshot:(NSString **)code {
    @try {
        NSData *png = [[[NSClassFromString(@"XCUIScreen") mainScreen] screenshot] PNGRepresentation];
        if (png.length) return png;
        if (code) *code = @"no_picture";
    } @catch (NSException *e) {
        if (code) *code = [NSString stringWithFormat:@"%@: %@", e.name, e.reason];
    }
    return nil;
}

/// The bundle id testmanagerd gives for a pid, or nil within a second.
- (nullable NSString *)bundleForPID:(int)pid session:(id)session {
    dispatch_semaphore_t got = dispatch_semaphore_create(0);
    __block NSString *bundle;
    [[session daemonProxy] _XCT_requestBundleIDForPID:pid reply:^(NSString *value, NSError *error) {
        bundle = value; dispatch_semaphore_signal(got);
    }];
    dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    return bundle;
}

/// The AX client, after asking testmanagerd once per session to turn accessibility on in every app, as
/// XCUIApplication does when a UI test launches one. Without it a third-party app's tree is
/// kAXErrorServerNotFound; system apps such as Settings answer either way.
- (id)accessibilityFor:(uint64_t)generation {
    // Once accessibility is on, every AX notification (an app activating, for one) reaches
    // -[XCAXClient_iOS handleAccessibilityNotification:fromElement:payload:], which asks
    // XCUIApplicationMonitor for an XCUIApplication on the main queue; that throws outside a UI test
    // and ends Poki (seen on the phone). Poki reads on request and needs none of them.
    static dispatch_once_t quiet;
    dispatch_once(&quiet, ^{
        Class client = NSClassFromString(@"XCAXClient_iOS");
        SEL selector = NSSelectorFromString(@"handleAccessibilityNotification:fromElement:payload:");
        Method method = client ? class_getInstanceMethod(client, selector) : NULL;
        // The notification is a number, not an object (1021 came in on the simulator): the arguments
        // are taken as plain pointers so that nothing is retained, or a Debug build crashes on it.
        if (method) method_setImplementation(method, imp_implementationWithBlock(^(__unused void *me, __unused void *notification, __unused void *element, __unused void *payload) {}));
    });
    id ax = PKAXClient();
    @synchronized (self) {
        if (_accessibilityGeneration != generation && [ax respondsToSelector:@selector(loadAccessibility:)]) {
            NSError *error;
            if ([ax loadAccessibility:&error]) _accessibilityGeneration = generation;
        }
    }
    return ax;
}

/// The front app's AX element, with its bundle id and pid in `info`.
- (id)front:(NSDictionary **)info ax:(id *)client {
    PKOutcome *refused;
    uint64_t generation = 0;
    id session = [self current:&generation outcome:&refused];
    if (!session) return nil;
    id ax = [self accessibilityFor:generation];
    if (client) *client = ax;
    __weak PKInProcess *weakSelf = self;
    id chosen = PKForegroundElement(ax, ^NSString *(int pid) { return [weakSelf bundleForPID:pid session:session]; });
    int pid = PKAXPid(chosen);
    if (!chosen || pid <= 0) return nil;
    if (info) *info = @{@"bundleId": [self bundleForPID:pid session:session] ?: @"", @"pid": @(pid)};
    return chosen;
}

- (NSDictionary<NSString *, id> *)frontApp {
    @try {
        NSDictionary *info;
        id ax;
        id element = [self front:&info ax:&ax];
        if (!element) return @{};
        id root = PKRequestSnapshot(ax, element, 1, 1, NULL);
        NSMutableDictionary *out = [info mutableCopy];
        out[@"name"] = PKText([root label]) ?: @"";
        return out;
    } @catch (NSException *e) { return @{}; }
}

- (nullable NSString *)sourceXML:(NSDictionary **)focused code:(NSString **)code {
    @try {
        id ax;
        id app = [self front:NULL ax:&ax];
        if (!app) { if (code) *code = @"no_front_app"; return nil; }
        id root = PKSnapshotTree(ax, app, code);
        if (!root) { if (code && !*code) *code = @"no_snapshot"; return nil; }
        NSMutableString *xml = [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?><AppiumAUT>"];
        __block NSDictionary *focus = nil;
        __block void (^walk)(id);
        __weak __block void (^weakWalk)(id);
        weakWalk = walk = ^(id node) {
            NSString *type = [@"XCUIElementType" stringByAppendingString:PKTypeName([node elementType])];
            CGRect f = [node frame];
            NSString *identifier = PKText([node identifier]), *label = PKText([node label]), *value = PKText([node value]);
            NSString *name = identifier.length ? identifier : label;
            [xml appendFormat:@"<%@ type=\"%@\"", type, type];
            if (name.length) [xml appendFormat:@" name=\"%@\"", PKEscape(name)];
            if (label.length) [xml appendFormat:@" label=\"%@\"", PKEscape(label)];
            if (value.length) [xml appendFormat:@" value=\"%@\"", PKEscape(value)];
            if (CGRectIsNull(f) || CGRectIsInfinite(f)) f = CGRectZero;
            [xml appendFormat:@" x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\"", (int)lround(f.origin.x), (int)lround(f.origin.y), (int)lround(f.size.width), (int)lround(f.size.height)];
            BOOL keyboard = [node respondsToSelector:@selector(hasKeyboardFocus)] ? [node hasKeyboardFocus]
                : [node respondsToSelector:@selector(hasFocus)] && [node hasFocus];
            if (!focus && keyboard && ([type hasSuffix:@"Field"] || [type hasSuffix:@"TextView"])) {
                focus = @{@"value": value ?: @"", @"x": @(f.origin.x), @"y": @(f.origin.y), @"width": @(f.size.width), @"height": @(f.size.height)};
            }
            NSArray *children = [node children];
            if (!children.count) { [xml appendString:@"/>"]; return; }
            [xml appendString:@">"];
            for (id child in children) weakWalk(child);
            [xml appendFormat:@"</%@>", type];
        };
        walk(root);
        [xml appendString:@"</AppiumAUT>"];
        if (focused) *focused = focus;
        return xml;
    } @catch (NSException *e) {
        if (code) *code = [NSString stringWithFormat:@"%@: %@", e.name, e.reason];
        return nil;
    }
}

- (nullable NSString *)press:(NSString *)name {
    @try {
        PKOutcome *refused;
        uint64_t generation = 0;
        if (![self current:&generation outcome:&refused]) return refused.code ?: @"no_session";
        id device = [NSClassFromString(@"XCUIDevice") sharedDevice];
        NSDictionary *buttons = @{@"home": @1, @"volumeUp": @2, @"volumeDown": @3};
        if ([name isEqualToString:@"lock"]) {
            if (![device respondsToSelector:@selector(pressLockButton)]) return @"lock_unavailable";
            [device pressLockButton];
            return nil;
        }
        NSNumber *button = buttons[name];
        if (!button) return @"unknown_button";
        // pressButton: drops the answer; the same HID event (consumer page 0x0C: Menu 0x40, volume
        // 0xE9/0xEA) is sent here so that a refusal comes back instead of a silent nothing.
        static const uint32_t usages[] = {0, 0x40, 0xE9, 0xEA};
        id event = [NSClassFromString(@"XCDeviceEvent") deviceEventWithPage:0x0C usage:usages[button.intValue] duration:0.1];
        NSError *error = nil;
        if (!event || ![device performDeviceEvent:event error:&error]) return error.localizedDescription ?: @"button_failed";
        return nil;
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"%@: %@", e.name, e.reason];
    }
}

/// testmanagerd's answer to one launch or terminate request, or nil within `seconds`.
static NSString *PKDaemonReply(NSTimeInterval seconds, void (^send)(void (^)(NSError *))) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSString *code = @"no_reply";
    send(^(NSError *error) { code = error ? (error.localizedDescription ?: @"failed") : nil; dispatch_semaphore_signal(done); });
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)))) return @"no_reply";
    return code;
}

/// Opens, brings forward or ends an app through testmanagerd, as XCUIApplication does inside a UI
/// test: launch ends a running copy first and starts it again, activate brings a running copy forward
/// (or starts it), terminate ends it. XCUIApplication itself refuses to exist outside a UI test bundle.
/// Launch and activate return once the app is in front.
- (nullable NSString *)app:(NSString *)bundle action:(NSString *)action {
    @try {
        PKOutcome *refused;
        uint64_t generation = 0;
        id session = [self current:&generation outcome:&refused];
        if (!session) return refused.code ?: @"no_session";
        id proxy = [session daemonProxy];
        BOOL launch = [action isEqualToString:@"launch"], activate = [action isEqualToString:@"activate"];
        if (!launch && !activate && ![action isEqualToString:@"terminate"]) return @"unknown_action";
        if (!launch && !activate) {
            return PKDaemonReply(15, ^(void (^reply)(NSError *)) { [proxy _XCT_terminateApplicationWithBundleID:bundle completion:reply]; });
        }
        BOOL (^inFront)(NSTimeInterval) = ^BOOL(NSTimeInterval seconds) {
            NSDate *by = [NSDate dateWithTimeIntervalSinceNow:seconds];
            do {
                if ([[self frontApp][@"bundleId"] isEqualToString:bundle]) return YES;
                [NSThread sleepForTimeInterval:0.25];
            } while ([by timeIntervalSinceNow] > 0);
            return NO;
        };
        if (launch && !PKDaemonReply(15, ^(void (^reply)(NSError *)) { [proxy _XCT_terminateApplicationWithBundleID:bundle completion:reply]; })) {
            // A launch sent while the old process is still exiting is answered but starts nothing.
            NSDate *by = [NSDate dateWithTimeIntervalSinceNow:5];
            while ([by timeIntervalSinceNow] > 0 && [[self frontApp][@"bundleId"] isEqualToString:bundle]) [NSThread sleepForTimeInterval:0.25];
            [NSThread sleepForTimeInterval:0.5];
        }
        for (int attempt = 0; attempt < 2; attempt++) {
            NSString *code = PKDaemonReply(30, ^(void (^reply)(NSError *)) {
                [proxy _XCT_launchApplicationWithBundleID:bundle arguments:@[] environment:@{} completion:reply];
            });
            if (code) return code;
            if (inFront(attempt ? 10 : 5)) return nil;
        }
        return @"not_in_front";
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"%@: %@", e.name, e.reason];
    }
}

- (BOOL)screenLocked {
    static int token = -1;
    if (token == -1 && notify_register_check("com.apple.springboard.lockstate", &token) != NOTIFY_STATUS_OK) return NO;
    uint64_t state = 0;
    notify_get_state(token, &state);
    return state != 0;
}

- (NSDictionary<NSString *, id> *)readProbe {
    NSMutableDictionary *out = [NSMutableDictionary new];
    PKOutcome *refused;
    uint64_t generation = 0;
    id session = [self current:&generation outcome:&refused];
    if (!session) { out[@"error"] = refused.code ?: @"no_session"; return out; }
    NSTimeInterval t = NSProcessInfo.processInfo.systemUptime;
    id app = nil, ax = nil;
    @try {
        ax = [self accessibilityFor:generation];
        NSArray *apps = PKActiveApplications(ax);
        out[@"front_count"] = @(apps.count);
        __weak PKInProcess *weakSelf = self;
        app = PKForegroundElement(ax, ^NSString *(int pid) { return [weakSelf bundleForPID:pid session:session]; });
        int pid = PKAXPid(app);
        out[@"front_pid"] = @(pid);
        if (pid) out[@"front_bundle"] = [self bundleForPID:pid session:session] ?: @"?";
        out[@"front_ok"] = @(app != nil);
    } @catch (NSException *e) {
        out[@"front_error"] = [NSString stringWithFormat:@"%@: %@", e.name, e.reason];
    }
    out[@"front_seconds"] = @(NSProcessInfo.processInfo.systemUptime - t);
    t = NSProcessInfo.processInfo.systemUptime;
    @try {
        NSString *code;
        id root = app ? PKSnapshotTree(ax, app, &code) : nil;
        out[@"tree_ok"] = @(root != nil);
        out[@"tree_elements"] = @(root ? PKCount(root) : 0);
        if (root) out[@"tree_root_label"] = PKText([root label]) ?: @"";
        if (code && !root) out[@"tree_error"] = code;
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

- (NSDictionary<NSString *, id> *)separateSessionTrialAt:(CGPoint)point hold:(double)hold {
    NSMutableDictionary *out = [NSMutableDictionary new];
    NSTimeInterval t0 = NSProcessInfo.processInfo.systemUptime;
    double (^now)(void) = ^{ return NSProcessInfo.processInfo.systemUptime - t0; };
    for (NSString *path in @[@"/System/Developer/Library/PrivateFrameworks/XCTestSupport.framework/XCTestSupport",
                             @"/System/Developer/usr/lib/lib_TestingInterop.dylib",
                             @"/System/Developer/Library/PrivateFrameworks/XCTestCore.framework/XCTestCore",
                             @"/System/Developer/Library/Frameworks/XCUIAutomation.framework/XCUIAutomation"]) {
        if (!dlopen(path.UTF8String, RTLD_NOW | RTLD_GLOBAL)) { out[@"code"] = @"developer_framework_unavailable"; return out; }
    }
    Class cls = NSClassFromString(@"XCTRunnerDaemonSession");
    if (![cls respondsToSelector:@selector(connectionForInitiatingSharedSession)] || ![cls respondsToSelector:@selector(sessionWithConnection:completion:)]) {
        out[@"code"] = @"session_api_unavailable"; return out;
    }
    id connection = [cls connectionForInitiatingSharedSession];
    __block id session; __block NSError *opened;
    dispatch_semaphore_t ready = dispatch_semaphore_create(0);
    [cls sessionWithConnection:connection completion:^(id s, NSError *e) { session = s; opened = e; dispatch_semaphore_signal(ready); }];
    if (dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC))) { out[@"code"] = @"session_timeout"; return out; }
    out[@"opened_s"] = @(now());
    if (!session) { out[@"code"] = @"session_failed"; out[@"detail"] = opened.localizedDescription ?: @""; return out; }
    __block double invalidatedAt = -1;
    dispatch_semaphore_t gone = dispatch_semaphore_create(0);
    if ([session respondsToSelector:@selector(registerInvalidationHandler:)])
        [session registerInvalidationHandler:^{ invalidatedAt = now(); dispatch_semaphore_signal(gone); }];
    NSError *error;
    BOOL enabled = [session respondsToSelector:@selector(enableAutomationModeWithError:)] && [session enableAutomationModeWithError:&error];
    out[@"enabled"] = @(enabled); out[@"enabled_s"] = @(now());
    if (!enabled) { out[@"code"] = @"enable_failed"; out[@"detail"] = error.localizedDescription ?: @""; return out; }
    Class pathClass = NSClassFromString(@"XCPointerEventPath"), recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    id record = [recordClass instancesRespondToSelector:@selector(initWithName:interfaceOrientation:)]
        ? [[recordClass alloc] initWithName:@"Poki trial" interfaceOrientation:1] : [[recordClass alloc] initWithName:@"Poki trial"];
    id path = [[pathClass alloc] initForTouchAtPoint:point offset:0];
    [path liftUpAtOffset:0.05];
    [record addPointerEventPath:path];
    __block NSString *tap = @"no_reply";
    dispatch_semaphore_t tapped = dispatch_semaphore_create(0);
    [[session daemonProxy] _XCT_synthesizeEvent:record implicitConfirmationInterval:0 completion:^(NSError *e) {
        tap = e ? (e.localizedDescription ?: @"error") : @"accepted"; dispatch_semaphore_signal(tapped);
    }];
    dispatch_semaphore_wait(tapped, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    out[@"tap"] = tap; out[@"tap_s"] = @(now());
    [NSThread sleepForTimeInterval:hold];
    id link = [session respondsToSelector:@selector(connection)] ? [session connection] : connection;
    [link invalidate];
    out[@"closed_s"] = @(now());
    BOOL handler = dispatch_semaphore_wait(gone, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0;
    out[@"invalidation_handler"] = @(handler);
    if (handler) out[@"invalidated_s"] = @(invalidatedAt);
    out[@"code"] = @"done";
    return out;
}

@end
