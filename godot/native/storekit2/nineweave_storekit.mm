#include "core/config/engine.h"
#include "core/object/class_db.h"
#import "NineweaveStoreKit-Swift.h"

class NineweaveStoreKit : public Object {
    GDCLASS(NineweaveStoreKit, Object);
    NWStoreKitBridge *bridge;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "product_id"), &NineweaveStoreKit::configure);
        ClassDB::bind_method(D_METHOD("pop_event"), &NineweaveStoreKit::pop_event);
        ClassDB::bind_method(D_METHOD("acknowledge", "token"), &NineweaveStoreKit::acknowledge);
        ClassDB::bind_method(D_METHOD("query_product"), &NineweaveStoreKit::query_product);
        ClassDB::bind_method(D_METHOD("refresh"), &NineweaveStoreKit::refresh);
        ClassDB::bind_method(D_METHOD("purchase"), &NineweaveStoreKit::purchase);
        ClassDB::bind_method(D_METHOD("restore"), &NineweaveStoreKit::restore);
    }
public:
    NineweaveStoreKit() { bridge = [NWStoreKitBridge new]; }
    ~NineweaveStoreKit() { [bridge shutdown]; bridge = nil; }
    void configure(String id) { [bridge configure:[NSString stringWithUTF8String:id.utf8().get_data()]]; }
    String pop_event() { return String::utf8([[bridge popEvent] UTF8String]); }
    void acknowledge(String token) { [bridge acknowledge:[NSString stringWithUTF8String:token.utf8().get_data()]]; }
    void query_product() { [bridge queryProduct]; }
    void refresh() { [bridge refresh]; }
    void purchase() { [bridge purchase]; }
    void restore() { [bridge restore]; }
};
static NineweaveStoreKit *instance = nullptr;
extern "C" void nineweave_storekit_init() {
    ClassDB::register_class<NineweaveStoreKit>();
    instance = memnew(NineweaveStoreKit);
    Engine::get_singleton()->add_singleton(Engine::Singleton("NineweaveStoreKit", instance));
}
extern "C" void nineweave_storekit_deinit() {
    Engine::get_singleton()->remove_singleton("NineweaveStoreKit");
    memdelete(instance); instance = nullptr;
}
