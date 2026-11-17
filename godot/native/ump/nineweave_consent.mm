// Source-only companion to pinned Poing AdMob5.1.0 / Google UMP3.1.0.
// No consent storage, reset, enum approximation or ad request is implemented here.
#include "core/config/engine.h"
#include "core/object/class_db.h"
#import <Foundation/Foundation.h>
#import <UserMessagingPlatform/UserMessagingPlatform.h>

class NineweaveConsent : public Object {
    GDCLASS(NineweaveConsent, Object);
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("can_request_ads"), &NineweaveConsent::can_request_ads);
        ClassDB::bind_method(D_METHOD("privacy_options_status"), &NineweaveConsent::privacy_options_status);
        ClassDB::bind_method(D_METHOD("is_main_thread"), &NineweaveConsent::is_main_thread);
    }
public:
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
extern "C" void nineweave_consent_init() {
    ClassDB::register_class<NineweaveConsent>();
    instance = memnew(NineweaveConsent);
    Engine::get_singleton()->add_singleton(Engine::Singleton("NineweaveConsent", instance));
}
extern "C" void nineweave_consent_deinit() {
    Engine::get_singleton()->remove_singleton("NineweaveConsent");
    memdelete(instance); instance = nullptr;
}
