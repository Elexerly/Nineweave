// Source-only companion to pinned Poing AdMob5.1.0 / Google UMP3.1.0.
// No consent storage, reset, enum approximation or ad request is implemented here.
#include "core/config/engine.h"
#include "core/object/class_db.h"
#import <Foundation/Foundation.h>
#import <UserMessagingPlatform/UserMessagingPlatform.h>


@interface NWConsentMailbox : NSObject
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, strong) NSMutableArray<NSString *> *events;
- (void)request:(NSString *)nonce;
- (NSString *)pop;
@end
@implementation NWConsentMailbox
- (instancetype)init {
    if ((self = [super init])) { _lock = [NSLock new]; _events = [NSMutableArray new]; }
    return self;
}
- (void)request:(NSString *)nonce {
    // Capture ObjC mailbox, not the Godot object's lifetime. No Godot API on UIKit queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *privacy = @"unknown";
        switch (UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus) {
            case UMPPrivacyOptionsRequirementStatusRequired: privacy = @"required"; break;
            case UMPPrivacyOptionsRequirementStatusNotRequired: privacy = @"not_required"; break;
            default: break;
        }
        NSDictionary *snapshot = @{@"nonce":nonce, @"can_request_ads":@(UMPConsentInformation.sharedInstance.canRequestAds), @"privacy_options_status":privacy};
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (json) { [self.lock lock]; [self.events addObject:json]; [self.lock unlock]; }
    });
}
- (NSString *)pop {
    [self.lock lock];
    NSString *result = self.events.count ? self.events[0] : @"";
    if (self.events.count) [self.events removeObjectAtIndex:0];
    [self.lock unlock];
    return result;
}
@end

class NineweaveConsent : public Object {
    GDCLASS(NineweaveConsent, Object);
    NWConsentMailbox *mailbox;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("request_snapshot", "nonce"), &NineweaveConsent::request_snapshot);
        ClassDB::bind_method(D_METHOD("pop_snapshot"), &NineweaveConsent::pop_snapshot);
        ClassDB::bind_method(D_METHOD("can_request_ads"), &NineweaveConsent::can_request_ads);
        ClassDB::bind_method(D_METHOD("privacy_options_status"), &NineweaveConsent::privacy_options_status);
        ClassDB::bind_method(D_METHOD("is_main_thread"), &NineweaveConsent::is_main_thread);
    }
public:
    NineweaveConsent() { mailbox = [NWConsentMailbox new]; }
    void request_snapshot(String nonce) { [mailbox request:[NSString stringWithUTF8String:nonce.utf8().get_data()]]; }
    String pop_snapshot() { return String::utf8([[mailbox pop] UTF8String]); }
    bool is_main_thread() const { return [NSThread isMainThread]; }
    bool can_request_ads() const {
        // UMP requires main-thread calls. Never dispatch_sync from a possibly blocked
        // Godot worker; unsupported threading is fail-closed and visible to integration QA.
        if (![NSThread isMainThread]) return false;
        return UMPConsentInformation.sharedInstance.canRequestAds;
    }
    String privacy_options_status() const {
        if (![NSThread isMainThread]) return "unknown";
        switch (UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus) {
            case UMPPrivacyOptionsRequirementStatusRequired: return "required";
            case UMPPrivacyOptionsRequirementStatusNotRequired: return "not_required";
            default: return "unknown";
        }
    }
};
static NineweaveConsent *instance = nullptr;
void nineweave_consent_init() {
    ClassDB::register_class<NineweaveConsent>();
    instance = memnew(NineweaveConsent);
    Engine::get_singleton()->add_singleton(Engine::Singleton("NineweaveConsent", instance));
}
void nineweave_consent_deinit() {
    Engine::get_singleton()->remove_singleton("NineweaveConsent");
    memdelete(instance); instance = nullptr;
}
