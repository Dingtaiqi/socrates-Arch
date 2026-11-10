# 镜像源码和补丁

本仓库已补入本地保存的 **Arch/EvoX 移植源码与补丁历史**。
逐文件来源、内容 SHA256、脱敏计数见 [source-catalog.json](source-catalog.json)。
目录中的历史脚本用于追溯，不是按字典序运行就能复现最终镜像的流水线。

## 已保存

| 目录 | 内容与用途 |
| --- | --- |
| `arch/minit_kde.c`、`arch/kde-start.sh` | 当前 KDE native init 和桌面启动脚本 |
| `arch/gpu/` | 显示格式/路由及时间戳兼容层、DRM/GBM 诊断、重启工具源码；当前启用项由 `kde-start.sh` 指定 |
| `arch/turnip/` | Turnip KGSL 构建脚本、原构建环境配方、Meson 参数、工具链与 Python 版本记录 |
| `arch/packages/` | Plasma 与桌面应用的包版本、下载地址及 SHA256；这些是二进制包清单 |
| `arch/runtime/` | 60 Hz 屏幕配置、触摸运行时部署与 rootfs 快照脚本 |
| `archive/libhybris/` | 早期 libhybris 路线的试验源码及 C13 镜像配方；当前 KDE 使用 Turnip/Zink |
| `evox/porting/` | EvoX 同步、socrates 设备树适配、DSU 兼容补丁脚本 |
| `evox/image-tools/` | 镜像注入、ext4 元数据捕获与钉扎、差分生成工具 |
| `evox/history/` | b3–b66 / host-policy 等迭代脚本、init 补丁、uicap 历史；包含已放弃的实验 |
| `evox/diagnostics/` | 早期 native init / zygote / 日志诊断源码 |
| `evox/aosp-reference/` | 原工作区保存的 AOSP init、fs_mgr、vold、gsid 相关参考源码，保留原许可头；不是完整 Android 源码树 |

旧脚本中的构建密码和无线网络配置已移除，必要值改为外部环境变量。
脱敏过的文件不公开原文件哈希，避免把可枚举的凭据校验值随源码发布。
保留原有第三方版权/许可头；没有将不同来源的文件统一重新授权。

## Mesa 原始源码

镜像使用的 Turnip 来自未经源码修改的 Mesa 26.2.6。锁定信息在
`arch/turnip/source_manifest.json`：68,703,420 B，SHA512
`0959679a8e9560a36d63bfc67357c73fde6fd98b00c29859ab30b31454b9ef8c8def38c7e180b168fd39080681042559dfc4a4252dfb289930a9776e0243c2dc`。

Actions 中的 **Archive porting source code** 会下载并校验原始 Mesa 源码，
连同当前 Git 提交的移植源码包保存为草稿 Release。源码包内包含 Mesa 上游的许可文件。
大源码包通过 Release 保存，不把它作为 Git 大文件反复提交。

`arch/turnip/configure_cross.sh` 是原服务器构建记录，保留原路径和依赖布局；
移到新机器时需要准备对应 ARM64 Arch sysroot、GCC 12、QEMU 和 host 工具。
`arch/build-support.sh OUTPUT` 可独立交叉编译当前使用的两个 DRM 兼容层和 reboot 工具。
重新编译出的二进制仍需单独真机验证，源码归档工作不会替换已验收镜像中的驱动。
`arch/gpu/read_scanout.c` 是早期 dumb-buffer 诊断，曾涉及未解释的重启；
保留作历史参考，不应对 GPU/imported buffer 直接运行。

## 尚未形成完整的源码复现链

原构建机 SSH 密钥认证成功，但打开新会话超时；本次未能导出完整 EvoX checkout。
当前缺少该 checkout 的 `repo manifest -r`、服务器独有的 tracked changes 和部分
迭代脚本引用的中间文件。`evox/history/` 保留的是本地现有材料，不能视为完整 b66 补丁序列。

服务器恢复后，可在服务器本地运行：

```bash
bash evox/capture-checkout.sh /build/evox /home/YOUR_USER/evox-source-export
```

工具读取 manifest、各项目 HEAD、相对 HEAD 的 tracked changes，并列出未跟踪文件名。
它不导出未跟踪文件的内容；这些文件需要按清单审查后另行补齐。
导出目录内补丁可能含环境信息，上传前需要审查。

Arch 也不是所有软件的完整源码合集：KDE、Qt、glibc、系统 Mesa 等来自 Arch Linux ARM
软件包；当前保存了已知包版本清单和二进制快照，尚未收齐每个包的 PKGBUILD/源码。
Goodix `touch_report`、Android vendor 库和固件在现有材料中只有厂商二进制，
没有对应源码。原镜像仍在已验证的种子 Release 中，可用于恢复现有成果。
