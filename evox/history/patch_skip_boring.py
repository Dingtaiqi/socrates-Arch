import io
P = "/build/evox/system/core/init/service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 1) Reap 里：DSU 启动时忽略 boringssl 自检服务的 reboot_on_failure
old1 = '''    if ((siginfo.si_code != CLD_EXITED || siginfo.si_status != 0) && on_failure_reboot_target_) {
        LOG(ERROR) << "Service " << name_
                   << " has 'reboot_on_failure' option and failed, shutting down system.";
        trigger_shutdown(*on_failure_reboot_target_);
    }'''
new1 = '''    if ((siginfo.si_code != CLD_EXITED || siginfo.si_status != 0) && on_failure_reboot_target_) {
        // [dsu-port] DSU 启动时，宿主 vendor 的 boringssl 自检在 /data 未就绪时会失败，
        // 直接触发 reboot；这里对 DSU 忽略它，让 boot 继续。
        if (name_.rfind("boringssl_self_test", 0) == 0 &&
            access("/metadata/gsi/dsu/active", F_OK) == 0) {
            LOG(ERROR) << "[dsu-port] Service " << name_
                       << " failed but DSU boot: ignoring reboot_on_failure";
        } else {
            LOG(ERROR) << "Service " << name_
                       << " has 'reboot_on_failure' option and failed, shutting down system.";
            trigger_shutdown(*on_failure_reboot_target_);
        }
    }'''
if old1 in s:
    s = s.replace(old1, new1, 1)
    print("Reap patched")

# 2) ExecStart 的 scope guard：DSU 下 boringssl 自检启动失败不触发 shutdown
old2 = '''Result<void> Service::ExecStart() {
    auto reboot_on_failure = make_scope_guard([this] {
        if (on_failure_reboot_target_) {
            trigger_shutdown(*on_failure_reboot_target_);
        }
    });'''
new2 = '''Result<void> Service::ExecStart() {
    auto reboot_on_failure = make_scope_guard([this] {
        if (on_failure_reboot_target_) {
            if (name_.rfind("boringssl_self_test", 0) == 0 &&
                access("/metadata/gsi/dsu/active", F_OK) == 0) {
                LOG(ERROR) << "[dsu-port] exec_start " << name_
                           << " failed on DSU boot: skipping shutdown";
                return;
            }
            trigger_shutdown(*on_failure_reboot_target_);
        }
    });'''
if old2 in s:
    s = s.replace(old2, new2, 1)
    print("ExecStart patched")

if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("service.cpp updated")
else:
    print("NO CHANGE")
