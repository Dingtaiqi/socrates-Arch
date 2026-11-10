// apex_extract.c — 用 miniz 从 .apex(zip) 里解出指定前缀的文件
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include "miniz.h"

static void mkdirs(const char *path) {
    char tmp[512];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') { *p = 0; mkdir(tmp, 0755); *p = '/'; }
    }
    mkdir(tmp, 0755);
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: %s apex.zip prefix outdir\n", argv[0]); return 2; }
    const char *zip = argv[1], *prefix = argv[2], *outdir = argv[3];
    mz_zip_archive za;
    memset(&za, 0, sizeof(za));
    if (!mz_zip_reader_init_file(&za, zip, 0)) { fprintf(stderr, "open zip fail\n"); return 1; }
    mkdirs(outdir);
    int n = (int)mz_zip_reader_get_num_files(&za);
    int ok = 0;
    for (int i = 0; i < n; i++) {
        mz_zip_archive_file_stat st;
        if (!mz_zip_reader_file_stat(&za, i, &st)) continue;
        if (strncmp(st.m_filename, prefix, strlen(prefix)) != 0) continue;
        char out[512];
        snprintf(out, sizeof(out), "%s/%s", outdir, st.m_filename);
        mkdirs(out);
        size_t sz = 0;
        void *data = mz_zip_reader_extract_to_heap(&za, i, &sz, 0);
        if (!data) { fprintf(stderr, "extract fail %s\n", st.m_filename); continue; }
        FILE *f = fopen(out, "wb");
        if (f) { fwrite(data, 1, sz, f); fclose(f); ok++; printf("EXTRACT %s %zu\n", st.m_filename, sz); }
        mz_free(data);
    }
    mz_zip_reader_end(&za);
    printf("APEX-EXTRACT-DONE files=%d\n", ok);
    return 0;
}
