import io

p = r'D:\zzzzzzzz\_work\team\k90pm\install_evox_myron_aplus.ps1'
t = io.open(p, encoding='utf-8-sig').read()

# 1) 空间检查：峰值 = 2*raw + userdata + 256MiB
old = '''$needKB = [int64](($imgs | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum / 1024) + [int64]($UserdataSize / 1024) + 262144
Log ('need ~' + [math]::Round($needKB / 1GB, 2) + ' GiB, free ' + [math]::Round($freeKB / 1GB, 2) + ' GiB')
if ($freeKB -and ($freeKB -lt $needKB)) { Log 'FATAL not enough /data space'; exit 8 }'''
new = '''$rawKB = [int64](($imgs | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum / 1024)
# 峰值 = /data/local/tmp 三份 raw + gsi_tool 安装后的 /data/gsi 副本 + userdata + 256MiB 余量
$needKB = 2 * $rawKB + [int64]($UserdataSize / 1024) + 262144
Log ('peak /data need ~' + [math]::Round($needKB / 1GB, 2) + ' GiB (2x raw + userdata + 256MiB), free ' + [math]::Round($freeKB / 1GB, 2) + ' GiB')
if ($freeKB -and ($freeKB -lt $needKB)) { Log 'FATAL not enough /data space: need >= ~19GiB free (tmp raw + gsi copies + userdata); free up space or use gz streaming install'; exit 8 }'''
assert old in t, 'space block missing'
t = t.replace(old, new, 1)

# 2) arm 前清理 tmp raw + lp_names 修正
old2 = """Log 'lp_names check'
Log (RunSu 'ls -la /data/gsi/dsu/dsu/ 2>/dev/null; cat /metadata/gsi/dsu/lp_names 2>/dev/null')"""
new2 = """Log 'cleanup tmp raw images before arm (free /data)'
Log (RunSu 'rm -f /data/local/tmp/evox_myron_system.img /data/local/tmp/evox_myron_system_ext.img /data/local/tmp/evox_myron_product.img /data/local/tmp/evox_myron_*.img.gz; df -k /data | tail -1')
Log 'lp_names / gsi image check'
Log (RunSu 'ls -la /data/gsi/dsu/dsu/ 2>/dev/null; cat /metadata/gsi/dsu/lp_names 2>/dev/null')"""
assert old2 in t, 'lp block missing'
t = t.replace(old2, new2, 1)

io.open(p, 'w', encoding='utf-8-sig').write(t)
print('patched ok')
