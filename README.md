# K60 Pro / socrates：EvoX 与 Arch KDE 镜像保存

目标仓库：`Dingtaiqi/socrates-Arch`。全部镜像工作流在 GitHub 的
`ubuntu-24.04` 运行，不依赖原构建服务器或连接手机。

当前提供的是**已验证镜像归档，以及基于既有 Arch 系统快照的 init 重建**。
不把它称为 EvoX / Arch 全部软件的从零源码构建。

## 工作流

| Actions 名称 | 做什么 | 真机验证状态 |
| --- | --- | --- |
| EvoX b66 - verify and archive | 下载固定 b66 → 全部 SHA256 校验 → 只读 ext4 检查 → gzip 分卷 → 草稿 Release | 原镜像的历史验收；不新增兼容性承诺 |
| Arch KDE - archive or rebuild / archive | 原样保存已验收的 KDE system 镜像，恢复后 SHA256 不变 | 桌面、触摸、应用及重启持久化已经实测 |
| Arch KDE - archive or rebuild / rebuild | 在已验收底包中交叉编译并替换 native init、更新桌面启动脚本，保留 EROFS rootfs 和 userdata UUID | 离线检查通过后，仍需独立真机验证 |
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
因此工作流只创建 **草稿 Release**：仓库协作者可见，不自动公开发布。
这不是去个人化的公开发行镜像。仓库源码与镜像附件分开存放；不要提交整个旧工作区。
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
原始脚本分散在旧工作区与服务器；当前尚无完整的固定 revision 清单及补丁序列。
只运行 `m evolution` 不会自动生成等价 b66。本仓库先把可用成果本体保存下来。

完整 Android 构建的官方基准至少需要 400 GB 可用磁盘；普通 GitHub Linux
runner 标称存储 14 GB，托管作业最长 6 小时。因此这里没有添加一个必然资源不足的
全量 EvoX 编译作业。以后要从源码更新 ROM，需要补齐补丁仓库，并用资源足够的
付费托管 runner 或自托管机器。Arch 的全新 rootfs / Mesa 构建也需进一步固定软件包、
工具链和厂商运行时来源；当前 rebuild 明确是快照之上的 native init 构建。

参考：[GitHub runner 资源](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、
[作业限制](https://docs.github.com/en/actions/reference/limits)、
[Release 附件限制](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)、
[artifact 保留期限](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/remove-workflow-artifacts)、
[AOSP 构建要求](https://source.android.com/docs/setup/start/requirements)。
