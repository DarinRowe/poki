#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Readable reconstruction; address-level provenance is in ../PROVENANCE.json.
// One context belongs to one logical action. Retain it across retries.
@interface SRActionContext : NSObject
- (instancetype)initWithOperationID:(NSString *)operationID
                      currentOwner:(BOOL (^)(void))currentOwner;
- (BOOL)commit:(NSError **)error;
- (void)beginReply;
- (void)markDispatched;
- (void)receiveReply:(nullable NSError *)error;
- (void)whenRepliesDrain:(dispatch_block_t)continuation;
- (NSDictionary *)evidence;
@end

@interface SRNativeSession : NSObject
// Call from a worker queue: the upstream promise wait can take 3 seconds.
- (nullable id)prepare:(NSError **)error;
- (BOOL)isCurrent:(id)session generation:(uint64_t)generation;
- (uint64_t)generation;
- (BOOL)enableWasReused;
@end

// Inserts into the CURRENTLY FOCUSED field. Does not focus, clear, paste or verify.
// The context must also validate the current session generation before dispatch.
FOUNDATION_EXPORT NSDictionary * _Nullable SRInsertText(
    id session, NSString *text, SRActionContext *context, NSError **error);
NS_ASSUME_NONNULL_END
