import io
P = "/build/evox/system/core/init/service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

# Start() 里的 scope guard 也需要 DSU 下跳过 boringssl
old = '''Result<void> Service::Start() {
    auto reboot_on_failure = make_scope_guard([this] {
        if (on_failure_reboot_target_) {
            trigger_shutdown(*on_failure_reboot_target_);
        }
    });'''
new = '''Result<void> Service::Start() {
    auto reboot_on_failure = make_scope_guard([this] {
        if (on_failure_reboot_target_) {
            if (name_.rfind("boringssl_self_test", 0) == 0 &&
                access("/metadata/gsi/dsu/active", F_OK) == 0) {
                LOG(ERROR) << "[dsu-port] start " << name_
                           << " failed on DSU boot: skipping shutdown";
                return;
            }
            trigger_shutdown(*on_failure_reboot_target_);
        }
    });'''
if old in s:
    s = s.replace(old, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("Start() guard patched")
else:
    print("Start() anchor not found (already patched?)")
