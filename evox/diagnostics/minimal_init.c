#include <unistd.h>

// 最小 wrapper：仅 exec KernelSU init（验证构建链路）
int main(int argc, char **argv) {
    execv("/init.ksu", argv);
    execv("/init.real", argv);
    return 1;
}
