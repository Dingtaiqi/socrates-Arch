# 从源码快照恢复和编译

完整 EvoX 构建树已保存到公开源码 Release
[`evox-full-source-20261110`](https://github.com/Dingtaiqi/socrates-Arch/releases/tag/evox-full-source-20261110)。
206 个分卷共 36,885,685,305 B，远端大小和 SHA256 均已核对。
`evox/full-source-snapshot.json` 已提交，并与 Release 内的清单逐字节一致。
全部 160 个分组的独立还原检查已在 [GitHub 云端通过](https://github.com/Dingtaiqi/socrates-Arch/actions/runs/42879967081)：
1267 个仓库、31 个 LFS 文件、5683 个 manifest 外文件均已验证。
逐组结果见 [还原报告](https://github.com/Dingtaiqi/socrates-Arch/releases/tag/evox-restore-1be903e5889a8414)。

## EvoX

快照覆盖 1265 个 manifest 项目、repo 工具、manifest 仓库、当前 Git LFS 对象、
7 个项目的本地补丁及 17 份本地文件。另存 manifest 外的工作树文件。
旧 Git 历史、`out/`、`out_init/` 和个人凭据不属于源码快照。
完整上游源码以 Release 分卷保存；Git 仓库保存恢复/编译入口和校验清单。

EvoX 构建环境使用 x86-64 Ubuntu 22.04，准备至少 400 GB 可用磁盘，
64 GB 以上内存；原机器是 Ubuntu 22.04、64 GB 内存。恢复会同时保存浅层 Git 对象
和工作树，编译产物还会继续占用空间。不要在普通 GitHub 托管 runner 上全量编译 Android。

```bash
sudo apt-get update
sudo apt-get install -y git git-lfs python3 curl gnupg flex bison build-essential \
  zip unzip zlib1g-dev libc6-dev-i386 x11proto-core-dev libx11-dev lib32z1-dev \
  libgl1-mesa-dev libxml2-utils xsltproc fontconfig bc libelf-dev ccache lz4 \
  libssl-dev rsync libncurses5 libtinfo5 python-is-python3
git clone https://github.com/Dingtaiqi/socrates-Arch.git
cd socrates-Arch
BUILD_JOBS=8 bash build.sh evox ../evox-source systemimage
```

入口先恢复已锁定源码，再执行 `lunch lineage_socrates-cp2a-userdebug` 和
`m systemimage`。也可将最后一项改成 `check`（只检查配置）、`init`（编译 init）
或 `evolution`（完整 ROM）。不会向手机发送命令。
Android 构建会使用快照内的 Repo、JDK/Clang 等输入，无需另行下载 Repo 工具。
依赖参考：[AOSP 构建要求](https://source.android.com/docs/setup/start/requirements)。
原服务器安装包版本记录在 `evox/host-packages.lock.tsv`，可用于核对缺失的构建依赖。

仅恢复文件或分阶段检查：

```bash
bash build.sh restore-evox ../evox-source
# 可选：只恢复清单中的指定分组，不能用不完整恢复执行正式构建。
python3 evox/restore-source.py ../evox-test-restore --groups 0,1
```

恢复目标必须是新目录，或由同一清单创建的目录；重复运行会跳过已完成分组。
每个分卷和组合归档均核对 SHA256，Git HEAD 和对象连通性也会检查。
恢复器为包含 LFS 文件的项目设置仓库内的过滤器和对象缓存；无系统/用户级 LFS
过滤器、全局缓存另指其他目录的组合场景已通过独立还原测试。
只为提交属性中标记 `filter=lfs` 的路径还原 LFS 数据，并核对完整文件 SHA256；
测试目录中仅仅长得像 LFS 指针的普通文本会保持原文。
已完成恢复后的开发者改动不会被重复 checkout 清除。
源码快照用于固定版本构建；需要更新上游时另建正常的 repo sync 工作区。

## 验证范围

完整快照的每个分组均已在新的 Linux runner 上独立还原，校验 Git 对象、LFS 实际内容、
本地补丁和文件、manifest 复制/链接规则及额外输入；全量检查耗时 2001 秒。
2026-11-11 又完成了独立 Ubuntu、空输出目录下的 `m evolution` 全量编译，
耗时 4 小时 12 分。源码使用独立 Git 缓存逐仓检出，完整对象校验及额外输入 SHA256
与公开快照一致；未挂载原工作树，未复制旧 out，也未使用 ccache。
这轮没有重新下载全部公开分卷。

原服务器已实际完成 11 个仓库的独立恢复，回放全部 7 份补丁并核对 17 个本地文件，
重复恢复两次通过；`repo list` 正常列出已恢复的 9 个普通项目。
原完整工作树的 socrates lunch/配置检查也已通过；这些早期局部测试与上述独立全量构建分开记录。
当前工作树包含历史 b66 后的实验改动，源码构建产物也不等同于历史 b66 镜像。
当前工作树的 `m init` 已于 2026-11-10 实际通过，耗时 4 分 29 秒；
重新编译并链接了 init 和关联的 fs_mgr 组件。
原工作树的 `m systemimage` 也已实际通过，监督进程记录耗时 202 秒，产物
986,390,528 B；SHA256 和范围见源码构建验证记录。该产物为普通 system 分区，
并非已合并的 DSU 镜像；后来的独立全量结果见
[构建归档任务](https://github.com/Dingtaiqi/socrates-Arch/actions/runs/42980982027)及
[固定校验索引](../evox/fresh-build-archive.json)。全新 ROM 为 3,349,406,382 B，
SHA256 为 `11c74ca99e36e745543ad027073489b6945a066a567c7800fba09ece5665a362`，
分成 4 个 gzip 分卷，与构建日志、环境和恢复证明一起保存在草稿 Release。
这份新 ROM 尚未在手机上引导验证。

提供了用于独立验证的干净 Ubuntu 环境入口；它不挂载原源码树，不使用旧 out 或 ccache：

```bash
# 需要独立工作目录、约 64 GiB RAM，以及至少 320 GiB 可用磁盘。
# 仅在已有足够资源的 Linux 构建机运行；普通 GitHub 托管 runner 不满足要求。
sudo BUILD_JOBS=16 bash evox/fresh-build.sh /path/to/new/evox-build
```

入口下载并核对 Ubuntu Base 22.04.5，安装依赖，在独立挂载命名空间内以普通用户
从公开 Release 恢复全部锁定源码，再执行 `evolution` 全量 ROM 目标。
工作目录保存 OS 包版本、源码恢复记录、进度和实际结果；磁盘低于 8 GiB 时停止构建。
上述成功全量构建使用此入口；首次遇到的 `/dev/shm` 权限问题已通过私有 tmpfs 修复，
修复后从空输出重新编译。归档工作流先检查已保存的 Release 及摘要，齐全时无需连接旧构建机。

## Arch

以下编译环境面向 x86-64 Ubuntu 22.04/24.04 主机，输出 ARM64 产物。

`bash build.sh arch-support OUTPUT_DIR` 可从源码交叉编译当前 DRM 兼容层和重启工具。
Mesa 26.2.6 原始源码、Turnip KGSL 构建配方和工具链记录已经保存。
原构建环境的 GCC 12、Python 构建工具、glslang、Arch 头文件/动态库已保存并公开，
清单为 `arch/build-inputs.json`。可在 Linux 上执行：

```bash
sudo apt-get install -y build-essential binutils-aarch64-linux-gnu pkg-config \
  qemu-user-static bison flex xz-utils python3
bash build.sh arch-turnip out/arch-inputs out/new-turnip
```

`Build ARM64 Turnip from source` Actions 使用同一入口编译 ARM64 KGSL Vulkan 驱动，
将驱动、构建参数、工具链清单、源码提交号和日志保存到新的草稿 Release。
输入目录只包含编译工具与库，不包含用户根目录、网络连接配置或完整系统镜像。

现有 Arch 镜像工作流会在固定二进制 rootfs 上编译 native init；KDE、Qt、glibc
等使用 Arch Linux ARM 软件包。厂商触摸运行时和固件只有二进制材料。

公开、去个人化底包已发布，清单为 `arch/build-base.json`。镜像重建入口：

```bash
sudo apt-get install -y e2fsprogs erofs-utils gcc-aarch64-linux-gnu
bash build.sh arch-image out/new-arch.img
# 需要使用现有数据卷时，在构建命令前设置 PERSIST_UUID=<该卷UUID>。
```

该入口无需原构建服务器或私有种子，下载的分卷、还原后镜像和内置 EROFS 均检查 SHA256，
然后从仓库源码编译 native init 并回读核对写入结果。没有指定数据卷时使用占位 UUID。
原始镜像种子继续保留为草稿。

2026-11-10 的 GPU 源码编译与公开输入镜像重建均已在 GitHub 云端通过，
具体提交、产物和校验值见 [源码构建验证](source-build-validation-2026-11-10.json)。
本次未操作手机，新生成的镜像和驱动尚未做真机复验。
