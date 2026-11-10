import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

old_block_start = "            char* buf = static_cast<char*>(malloc(2 * 1024 * 1024));"
old_block_end = "            }\n            free(buf);\n"

start = s.find(old_block_start)
if start < 0:
    print("old klogctl block not found")
else:
    end = s.find(old_block_end, start)
    new_block = '''            // [dsu_kmsg_dump] read /dev/kmsg (non-blocking) instead of klogctl
            int kfd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
            if (kfd >= 0) {
                std::string out;
                char lbuf[8192];
                for (int k = 0; k < 2000; ++k) {
                    ssize_t r = read(kfd, lbuf, sizeof(lbuf) - 1);
                    if (r <= 0) break;
                    out.append(lbuf, r);
                }
                close(kfd);
                if (!out.empty()) {
                    android::base::WriteStringToFile(out, "/metadata/gsi/dsu/kmsg.log");
                }
            }
'''
    s = s[:start] + new_block + s[end + len(old_block_end):]
    io.open(P, "w", encoding="utf-8").write(s)
    print("kmsg dump replaced with /dev/kmsg reader")
