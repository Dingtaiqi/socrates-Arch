# K60 Pro 的 b66 DSU 运行时补丁

2026-11-11 真机处理了两个独立问题：旧 b66 在当前内核下因 SELinux 拦截反复退出
zygote；进入桌面后，媒体编码器列表又一直等待失效的 OMX 服务，导致 scrcpy 没有画面，
相机服务也未正常就绪。补丁和实际结果分开记录在
[验收清单](../../docs/evox-dsu-runtime-2026-11-11.json)。

## 当前源码

- `socrates-compat.rc`：本轮使用的 init 配置。通过已有 KernelSU 域进入宽松模式，
  在 `early-init` 将过滤后的 HAL 清单只读绑定到 vendor 清单路径。
- `stock/manifest_kalama.xml`：从原厂 vendor 只读提取的 HAL 声明，不包含个人设置。
- `inputs.json`：原厂版本、清单身份和原生 Aperture APK 的校验记录。
- `patch-b66.py`：Linux 离线构建入口，复制固定 b66 后修改文件，检查读回、SELinux
  扩展属性和 ext4 完整性，产生新镜像及 JSON 报告。

手机的系统框架为 Android 17 移植版；vendor/odm 实际是
`OS3.0.304.0.WMKCNXM`、SDK 33。不能根据系统框架版本选择原厂驱动。
本配置要求当前内核已经提供 `u:r:ksu:s0`，不是给任意未 root 手机的通用配置。
DSU 运行期间 SELinux 为宽松模式；重启回 HyperOS 会重新加载宿主策略。

## 为什么移除一个 OMX 声明

Java 线程现场停在 `MediaCodecList.native_getCodecCount()`；服务端的
`mediacodeclist_generator` 也一直等待返回。对应源码
`frameworks/av/media/libstagefright/OmxInfoBuilder.cpp` 使用阻塞的
`IOmxStore::getService()`，vendor 清单却仍声明了这个无法在 ARM64-only DSU 中运行的
旧 32 位 OMX 服务。

过滤器只删除 `android.hardware.media.omx` 的 `IOmx` / `IOmxStore` 一项，逐项检查
其它 XML 节点不变。Codec2 的清单与服务保留，编码器枚举已经能返回
`c2.qti.avc.encoder`、`c2.qti.hevc.encoder` 等硬件编码器。绑定只存在于 DSU 的挂载
命名空间，原厂 vendor 分区内容不变。

## 离线生成镜像

在 Linux 构建机操作，准备 `e2fsprogs` 和已保存的原始 b66 镜像：

```bash
sudo apt-get install -y e2fsprogs
mkdir -p out
bash build.sh evox-compat /path/to/evox-b66.img out/evox-b66-compat.img
```

原始输入为 2,791,727,104 字节，SHA256：
`a1ccf41d14c3f52678860041f16335b64589485032b2f11973e65c373e8d4e2c`。
它保存在现有种子草稿 Release，获取方式见主 README。入口会拒绝不同输入和已有输出。

产物包括 `out/evox-b66-compat.img` 与同名 `.json`。入口只处理普通镜像文件，
不连接手机。新文件的 ext4 时间戳等元数据可能不同，因此应使用本次生成的报告核对，
不能期待它与人工修改的真机镜像逐字节一致。新生成文件仍须独立真机复验。
这也是一层针对历史 b66 的运行时补丁，与完整 Android 源码的 `m evolution` 编译不同。

## 恢复原生相机

历史 b66 移除了 `org.lineageos.aperture`。媒体链恢复后，本轮把先前保留的
Aperture APK 安装回 EvoX 的用户数据中，用户已确认可用；APK 身份见 `inputs.json`。
它没有随 Git 提交，其确切源码构建身份尚未核实。

后来者可以从已还原的完整源码树生成原生 APK：

```bash
source build/envsetup.sh
lunch lineage_socrates-cp2a-userdebug
m Aperture
```

在已经确认进入目标 EvoX DSU 的情况下，可用 `adb install -r /path/to/Aperture.apk`
安装可信 APK。这个 APK 安装步骤不在离线镜像生成器中；只运行生成器不会自动恢复相机应用。

## 已验证范围

scrcpy 3.1 默认参数已收到 1440×3200 画面，视频使用高通硬件编码器，音频编码器初始化
正常；另一次 20 秒录制读出 705 帧。新版 scrcpy 5.0.1 也能完成编码器枚举。
主后摄 1280×720 短测读出 207 帧，前摄同分辨率预览通过；原生 Aperture 由用户确认可用。
这不是全部相机模式的回归结论，也没有重新验证完整 ROM 构建产物。

真机部署另行安排：只操作槽 a，保留已有命名 DSU 及其 userdata，备份 DSU 元数据，
不要把历史的全局 `gsi_tool wipe` 安装脚本用于已有多个 DSU 的手机。
本轮没有刷写 boot、init_boot 或 vendor_boot。
