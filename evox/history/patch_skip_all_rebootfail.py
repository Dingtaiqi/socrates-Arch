import io, re
P = "/build/evox/system/core/init/service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

helper = '''
// [dsu-port] DSU 启动时忽略所有 reboot_on_failure（宿主 vendor 服务在 DSU 下会失败）
[[maybe_unused]] static bool dsu_skip_reboot_on_failure(const std::string& name) {
    if (access("/metadata/gsi/dsu/active", F_OK) == 0) {
        LOG(ERROR) << "[dsu-port] ignoring reboot_on_failure for service: " << name;
        return true;
    }
    return false;
}
'''
if "dsu_skip_reboot_on_failure" not in s:
    # 插在 using 区之后：紧跟 "#include <android-base/logging.h>" 不可靠，改插在第一个 "namespace {" 之前?
    # 直接插在文件第一次出现 "using android::base::WriteStringToFile;" 之后，否则插在 "#include" 块结束处
    m = s.find("#include <android-base/properties.h>")
    if m < 0:
        print("anchor include not found")
    else:
        s = s[:m] + helper + s[m:]
        print("helper inserted")

# 1) Reap 路径
old1 = '''    if ((siginfo.si_code != CLD_EXITED || siginfo.si_status != 0) && on_failure_reboot_target_) {
        LOG(ERROR) << "Service " << name_
                   << " has 'reboot_on_failure' option and failed, shutting down system.";
        trigger_shutdown(*on_failure_reboot_target_);
    }'''
new1 = '''    if ((siginfo.si_code != CLD_EXITED || siginfo.si_status != 0) && on_failure_reboot_target_) {
        if (dsu_skip_reboot_on_failure(name_)) {
            LOG(ERROR) << "[dsu-port] Service " << name_ << " failed; not rebooting";
        } else {
            LOG(ERROR) << "Service " << name_
                       << " has 'reboot_on_failure' option and failed, shutting down system.";
            trigger_shutdown(*on_failure_reboot_target_);
        }
    }'''
if old1 in s:
    s = s.replace(old1, new1, 1)
    print("Reap patched")

# 2) ExecStart guard
old2 = '''Result<void> Service::ExecStart() {
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
new2 = '''Result<void> Service::ExecStart() {
    auto reboot_on_failure = make_scope_guard([this] {
        if (on_failure_reboot_target_ && !dsu_skip_reboot_on_failure(name_)) {
            trigger_shutdown(*on_failure_reboot_target_);
        }
    });'''
if old2 in s:
    s = s.replace(old2, new2, 1)
    print("ExecStart patched")

# 3) Start() guard
old3 = '''Result<void> Service::Start() {
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
new3 = '''Result<void> Service::Start() {
    auto reboot_on_failure = make_scope_guard([this] {
        if (on_failure_reboot_target_ && !dsu_skip_reboot_on_failure(name_)) {
            trigger_shutdown(*on_failure_reboot_target_);
        }
    });'''
if old3 in s:
    s = s.replace(old3, new3, 1)
    print("Start patched")

if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("service.cpp updated")
else:
    print("NO CHANGE")
