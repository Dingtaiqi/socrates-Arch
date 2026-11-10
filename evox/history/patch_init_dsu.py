# 给 EvoX init 源码打诊断补丁：每个 builtin 前后写标记文件；跳过 wait_for_coldboot_done
import io, re

P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

MARKER_TMPL = """    am.QueueBuiltinAction([](const BuiltinArguments& args) -> Result<void> {
        android::base::WriteStringToFile("1", "/metadata/gsi/dsu/%s");
        (void)args;
        return {};
    }, "dsu_%s");
"""

def marker(name):
    return MARKER_TMPL % (name, name)

# 1) 在 SetupCgroups 之前插入标记
s = s.replace(
    '    am.QueueBuiltinAction(SetupCgroupsAction, "SetupCgroups");',
    marker("m_setup_cgroups") + '    am.QueueBuiltinAction(SetupCgroupsAction, "SetupCgroups");',
    1)

# 2) early-init trigger 之后：插入序列标记，并把 wait_for_coldboot_done 改为跳过
s = s.replace(
    '    am.QueueBuiltinAction(ConnectEarlyStageSnapuserdAction, "ConnectEarlyStageSnapuserd");',
    marker("m_connect_snapuserd") + '    am.QueueBuiltinAction(ConnectEarlyStageSnapuserdAction, "ConnectEarlyStageSnapuserd");',
    1)

s = s.replace(
    '    am.QueueBuiltinAction(wait_for_coldboot_done_action, "wait_for_coldboot_done");',
    marker("m_wait_coldboot") +
    '    // [dsu-port] skip wait_for_coldboot_done\n'
    '    am.QueueBuiltinAction([](const BuiltinArguments& args) -> Result<void> {\n'
    '        android::base::WriteStringToFile("1", "/metadata/gsi/dsu/m_wait_skipped");\n'
    '        (void)args;\n'
    '        return {};\n'
    '    }, "dsu_wait_skipped");\n',
    1)

s = s.replace(
    '        am.QueueBuiltinAction(CheckTradeInModeStatus, "CheckTradeInModeStatus");',
    marker("m_tradein") + '        am.QueueBuiltinAction(CheckTradeInModeStatus, "CheckTradeInModeStatus");',
    1)

s = s.replace(
    '    am.QueueBuiltinAction(SetMmapRndBitsAction, "SetMmapRndBits");',
    marker("m_mmap") + '    am.QueueBuiltinAction(SetMmapRndBitsAction, "SetMmapRndBits");',
    1)

# 3) KeychordInit 之前插标记
s = s.replace(
    '    Keychords keychords;',
    marker("m_before_keychord") + '    Keychords keychords;',
    1)

# 4) init trigger 之前插标记
s = s.replace(
    '    am.QueueEventTrigger("init");',
    marker("m_before_init_trigger") + '    am.QueueEventTrigger("init");',
    1)

# 确认 android-base/file.h 已被包含（WriteStringToFile）
if "#include <android-base/file.h>" not in s:
    s = s.replace('#include <android-base/logging.h>', '#include <android-base/file.h>\n#include <android-base/logging.h>', 1)

io.open(P, "w", encoding="utf-8").write(s)
print("init.cpp patched; markers inserted:", s.count("dsu_") )
print("--- 检查片段 ---")
for ln in s.splitlines():
    if "dsu_" in ln or "wait_for_coldboot_done_action" in ln or "QueueEventTrigger(\"init\")" in ln:
        print(ln[:140])
