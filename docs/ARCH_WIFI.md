# Arch DSU Wi-Fi（2026-11-11）

K60 Pro / socrates 在现有 Arch KDE DSU 中已连接 5 GHz WPA2 热点，完成 DHCP、
DNS 和 HTTPS 访问验证。这里复用原厂 Android 5.15.194 内核的 `kiwi_v2` 驱动，
不是主线内核的 ath12k 路线。

## 启动条件

- Android 槽 a、已加载原厂 `kiwi_v2` 模块的 Arch DSU。
- 已有触摸隔离运行时 `/opt/kde-dsu/touch-runtime`，用于运行匹配的 Bionic 程序。
- 从本机槽 a 的 `modem_a`、`system_a` 和 `persist` 读取固件及配套库。
  三者仅只读挂载，persist 还指定 `noload`；不修改原厂校准数据。
- 固件查找目录仍是内核初始根下的 `/mnt/opt/fw`，保留已有 Adreno 固件。
- NetworkManager、wpa_supplicant、wireless-regdb 和 plasma-nm 已在现有 Arch 用户空间中。

`arch/wifi-start.py` 校验槽位、内核、模块、设备号、挂载点和只读状态，
然后准备固件别名，启动原厂 `qrtr-ns`、`cnss-daemon`，最后通知
`/sys/kernel/cnss/fs_ready`。`wlan0` 出现后启动原生 wpa_supplicant 与
NetworkManager。`usb0` 保持不受 NetworkManager 管理。

这台设备初始阻塞是 CNSS 等待文件系统就绪而延迟校准。仅加载模块并不足以出现网卡。
另一个问题是 `/run` 位于持久化 overlay 中，旧 D-Bus socket 文件可以跨重启保留，
但服务已经退出；脚本会检查实际连接并重建失效的系统总线。

## 当前手机与后续镜像

当前手机的 `system_gsi` 映射只读，未更改它的块设备属性或镜像内容。
已将启动脚本保存在可写的 `/opt/kde-dsu/wifi-start.py`，并在 `/root/.bashrc`
添加仅 ttyGS0 启动时执行一次的钩子，利用现有 minit 的串口 shell 启动顺序。
原 bashrc 备份位于 `/opt/kde-dsu/backups/wifi-shell-20261111/`。
钩子遇到已集成 Wi-Fi 启动的新桌面脚本时会跳过，避免重复执行。

后续镜像由 `ci/rebuild-arch.sh` 安装 `/system/etc/arch/wifi-start.py`，
并由 `arch/kde-start.sh` 在桌面启动前调用。失败会记日志并继续启动桌面。
当前已验收的历史底包本身未改写；需要重新构建才包含这些源码更新。

手机运行日志在 `/dev/kde_dsu/wifi-live/`，新镜像启动日志在桌面日志目录的
`wifi-start.log`。网络选择和密码由 NetworkManager 管理，保存在本机可写数据卷；
仓库不包含 SSID、密码、网络配置文件或设备校准文件。

## 已验证与边界

- 识别出 managed 类型的 `wlan0`，扫描到 37 个热点。
- 实际连接 5220 MHz 的 5 GHz 热点，信号约 -42 dBm，取得 IPv4 地址、网关和 DNS。
- 网关 2/2 ICMP 应答，DNS 解析成功，百度 HTTPS 和 Microsoft HTTP 连通测试均返回 200。
- 网络配置权限为 0600，密码已保存，自动连接开启。
- 停止 NetworkManager / wpa_supplicant 后，通过已保存的 ttyGS0 启动钩子重新启动，
  自动连回热点，再次取得地址并获得 HTTPS 200；KWin 与 plasmashell PID 保持不变。
- 没有为本次 Wi-Fi 验证重启手机；完整冷启动仍待复验。
- 没有验证其他内核、主线 ath12k、热点共享、休眠唤醒或长期稳定性。

本次不涉及 boot、init_boot、vendor_boot 的刷写，也不切换 Android A/B 槽。
