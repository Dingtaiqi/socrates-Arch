# K60 Pro / socrates：EvoX 与 Arch KDE 镜像保存

目标仓库：`Dingtaiqi/socrates-Arch`。全部镜像工作流在 GitHub 的
`ubuntu-24.04` 运行，不依赖原构建服务器或连接手机。

当前支持已验证镜像归档、公开 Arch 底包上的 native init 重建，以及 Mesa Turnip
ARM64 KGSL 驱动的源码编译。EvoX 完整源码快照仍在迁出。

**2026-11-10：两条云端镜像流程已实际运行成功。**
[Arch 重建记录](https://github.com/Dingtaiqi/socrates-Arch/actions/runs/42663629383) ·
[EvoX 归档记录](https://github.com/Dingtaiqi/socrates-Arch/actions/runs/42664525906) ·
[镜像下载（登录后查看草稿 Release）](https://github.com/Dingtaiqi/socrates-Arch/releases)。
两份原始镜像也已保存，44 个种子分卷和 2 份清单全部通过远端 SHA256 核验。
详细结果见 [云端验证记录](docs/cloud-validation-2026-11-10.json)。

移植源码、GPU 兼容层、Mesa 构建配方、EvoX 补丁历史已补入仓库，
目录说明和复现缺口见 [源码归档说明](docs/SOURCE_CODE.md)。
**Archive porting source code** 工作流另存当前 Git 源码包和完整 Mesa 26.2.6 原始源码。
构建机上的固定版本清单、7 个项目的本地改动和服务器配方也已直传 GitHub，
见 [服务端源码备份记录](evox/server-capture.json)。

完整 Android 源码及预编译输入正在服务器上分卷直传，恢复和编译入口已加入
`build.sh`。迁出完成后将提交校验索引并公开源码附件；使用方法和实测边界见
[从源码快照构建](docs/BUILD_FROM_SNAPSHOT.md)。原始手机镜像仍保留为草稿。

## 克隆后编译 Arch

公开构建底包与 GPU 编译环境已经上传，以下两条入口均已在 GitHub 云端实际通过：

```bash
git clone https://github.com/Dingtaiqi/socrates-Arch.git
cd socrates-Arch
sudo apt-get update
sudo apt-get install -y build-essential binutils-aarch64-linux-gnu pkg-config \
  qemu-user-static bison flex xz-utils python3 e2fsprogs erofs-utils gcc-aarch64-linux-gnu
# 编译 native init，生成新的 system 镜像文件。
bash build.sh arch-image /build/new-arch.img
# 独立从 Mesa 源码编译 KGSL Vulkan 驱动。
bash build.sh arch-turnip /build/arch-inputs /build/new-turnip
```

镜像入口使用公开、去个人化的固定 Arch Linux ARM 用户空间，保留现有桌面运行库；
KDE/Qt 等来自二进制软件包。GPU 入口生成独立驱动包。
默认数据卷 UUID 为占位值；部署前可用 `PERSIST_UUID` 指定已有、带正确标记的数据卷。
构建过程只生成文件，不创建 userdata 或操作手机。

[GPU 源码编译通过](https://github.com/Dingtaiqi/socrates-Arch/actions/runs/42822210400) ·
[公开输入镜像重建通过](https://github.com/Dingtaiqi/socrates-Arch/actions/runs/42823028203) ·
[构建底包](https://github.com/Dingtaiqi/socrates-Arch/releases/tag/arch-public-base-42779960846)。
新构建产物尚未做真机复验，记录见 [源码构建验证](docs/source-build-validation-2026-11-10.json)。

## 工作流

| Actions 名称 | 做什么 | 真机验证状态 |
| --- | --- | --- |
| EvoX b66 - verify and archive | 下载固定 b66 → 全部 SHA256 校验 → 只读 ext4 检查 → gzip 分卷 → 草稿 Release | 原镜像的历史验收；不新增兼容性承诺 |
| Arch KDE - archive or rebuild / archive | 原样保存已验收的 KDE system 镜像，恢复后 SHA256 不变 | 桌面、触摸、应用及重启持久化已经实测 |
| Arch KDE - archive or rebuild / rebuild | 在已验收底包中交叉编译并替换 native init、更新桌面启动脚本，保留 EROFS rootfs 和 userdata UUID | 离线检查通过后，仍需独立真机验证 |
| Build Arch image from public inputs | 从公开底包下载、校验并编译 native init，保存新镜像与日志 | 云端通过；新镜像未做真机验证 |
| Build ARM64 Turnip from source | 固定 Mesa 源码和编译环境，生成 AArch64 KGSL Vulkan 驱动包 | 云端通过；新驱动未做真机验证 |
| Check image tooling | 分卷往返、损坏检测、路径检查、脚本语法、ARM64 init 静态交叉编译 | 不操作手机 |

Arch 桌面为 KWin / Zink / Turnip Adreno 740，1440×3200 @ 60 Hz；
仅 plasmashell 使用 software Qt Quick。应用包含 Dolphin、Kate、Ark、
Gwenview、Okular；没有浏览器。Wi-Fi、扬声器、电源/音量键及亮度控制的后续
适配尚未包含在这份已验收快照中。

## 为什么保存在 Release

Actions artifact 默认会过期；这里只用它临时留存失败日志。
镜像、分卷校验清单、源码副本、构建日志及提交号都放进 **Release 附件**。
云端结果每卷最多 1 GiB；首次导入的种子按 64 MiB 小卷上传，方便重试。
两者都低于 GitHub 单附件 2 GiB 的上限。

原样备份仍含设备配套的厂商文件和历史调试设置（例如 EvoX 的 ADB 授权配置），
因此历史原样备份保留为 **草稿 Release**：仓库协作者可见，不自动公开发布。
去个人化的构建底包、源码和编译环境已经单独公开，新编译的产物保存到草稿供复验。
仓库源码与镜像附件分开存放；不要提交整个旧工作区。
本仓库不包含 userdata、SSH 密钥、服务端密码或刷机脚本。

## 首次导入（只需要一次）

本地准备工具会核对两份已知镜像的完整 SHA256，然后压缩、分卷。
在本仓库目录运行：

```powershell
python ci/bundle.py prepare-seeds D:/zzzzzzzz seed-assets
gh auth login
```

确认 GitHub 账号有 `Dingtaiqi/socrates-Arch` 写权限后，把本目录作为仓库推送。
`seed-assets/` 已被 gitignore 排除，需作为附件上传：

```powershell
gh release create verified-seeds-20261110 --repo Dingtaiqi/socrates-Arch --target main --draft --title "Verified image seeds 2026-11-10" --notes "Pinned EvoX b66 and Arch KDE v4 system images. No userdata."
python ci/upload-seeds.py seed-assets --jobs 4
```

首次上传中断时，重跑上传工具即可。工具核对 GitHub 返回的 SHA256，跳过已完成的
相同附件；同名而内容不同的附件会报错，不会覆盖。它只向草稿 Release 上传。
如果强行终止上传，GitHub 可能留下 `starter` 状态的未完成占位附件；工具会报告
`incomplete`。先确认没有其他上传仍在运行，再只删除报告中对应的未完成附件并重跑，
不要删除已经 `uploaded` 且哈希匹配的附件。
如果电脑已有 HTTP 代理，GitHub CLI 可能需要在本次终端单独设置
`HTTPS_PROXY`；不用改变全局网络配置，也不要把代理账号写进仓库。
上传完毕后去 Actions 手动运行上述工作流。工作流使用仓库自带的
`GITHUB_TOKEN` 下载草稿附件并保存新草稿，不需要添加服务器 SSH secret。
每次结果使用独立 run ID / attempt 命名，不覆盖原始种子。
私有仓库的 Actions 计算时间按账户额度计费；没有安排定时重复运行。

## 下载与还原

下载某个结果 Release 的所有附件，保留相对文件名；不需要手机连电脑。

```powershell
gh release download <结果标签> --repo Dingtaiqi/socrates-Arch --dir downloaded
python ci/bundle.py restore downloaded/arch-kde.img.manifest.json restored-arch.img
# EvoX 则使用 evox-b66.img.manifest.json
```

还原工具先校验每一卷，再校验解压后原始镜像的长度和 SHA256。
缺卷、损坏、重复分卷或目标文件已存在会失败，不覆盖原镜像。
这是文件还原，不会安装/启用 DSU，也不会格式化或写入手机分区。

## 当前基线

| 镜像 | 大小 | SHA256 |
| --- | ---: | --- |
| EvoX b66 | 2,791,727,104 B | `a1ccf41d14c3f52678860041f16335b64589485032b2f11973e65c373e8d4e2c` |
| Arch KDE v4 | 3,221,225,472 B | `4e044e6358f8a76000fa3ab2325de96c412dfee87907d4db57bca62ca4494d19` |

Arch 镜像中的 EROFS rootfs SHA256 为
`7afa94d0b226a1a22c79fb82ca2c12256d258d5257c5eb8dec7685281f070023`。
它保留当前包版本和已验证的驱动运行库，重建过程不会自动 `pacman -Syu`。
既有 userdata 为另一个独立镜像，UUID
`fad4bd59-96f1-4c6c-8791-d31c87b82264`，不在本备份中。
native init 必须同时核对 UUID 和卷标记才挂载持久层，且从不自动格式化。
换到全新 DSU 需要另行准备数据卷；不要用本仓库重建来覆盖既有 userdata。

## 从零编译的边界

EvoX 原工程来自 Evolution-X manifest `cnb`，设备为 socrates，历史 lunch
目标是 `lineage_socrates-cp2a-userdebug`。可用 b66 还叠加了多轮 DSU 兼容修正，
本地和服务器现有的历史脚本、当前 checkout 的固定 revision 清单及本地改动现已保存。
这些材料尚未经过完整历史镜像重建验证；只运行 `m evolution` 不会自动生成等价 b66。

完整 Android 构建的官方基准至少需要 400 GB 可用磁盘；普通 GitHub Linux
runner 标称存储 14 GB，托管作业最长 6 小时。因此这里没有添加一个必然资源不足的
全量 EvoX 编译作业。以后要从源码更新 ROM，需要补齐补丁仓库，并用资源足够的
付费托管 runner 或自托管机器。Arch 已能从公开的固定底包编译 native init，并独立
从 Mesa 源码编译驱动；完整 KDE/Qt 用户空间仍使用已经保存的二进制发行版快照。

参考：[GitHub runner 资源](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、
[作业限制](https://docs.github.com/en/actions/reference/limits)、
[Release 附件限制](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)、
[artifact 保留期限](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/remove-workflow-artifacts)、
[AOSP 构建要求](https://source.android.com/docs/setup/start/requirements)。
