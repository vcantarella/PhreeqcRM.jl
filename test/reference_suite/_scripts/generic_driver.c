/* Generic C driver for the PHREEQC reference suite.
 *
 * Configured via command-line arguments:
 *   --case <name>           directory name under reference_suite/ (e.g. ex5)
 *   --db <path>             database file path
 *   --root <path>           project root (so we can locate the case dir)
 *   --bench N               run N RunCells iterations after warmup, print
 *                           per-step time. If absent, runs once and exits.
 *
 * Parses the script for keyword blocks (SOLUTION, EQUILIBRIUM_PHASES, etc.)
 * to figure out which IC categories to populate. Mirrors the Julia generic
 * driver one-for-one so the C vs Julia comparison is apples-to-apples.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <unistd.h>
#include "RM_interface_C.h"

#define NXYZ 1

static char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = (char*)malloc((size_t)n + 1);
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) { free(buf); fclose(f); return NULL; }
    buf[n] = '\0';
    fclose(f);
    return buf;
}

/* Case-insensitive line-anchored search for "keyword <int>". Returns the
 * smallest matching integer, or -1 if none found. */
static int lowest_user_number(const char *script, const char *keyword) {
    int best = -1;
    size_t klen = strlen(keyword);
    const char *p = script;
    while (*p) {
        const char *eol = strchr(p, '\n');
        if (!eol) eol = p + strlen(p);
        const char *q = p;
        while (q < eol && isspace((unsigned char)*q)) q++;
        if ((size_t)(eol - q) > klen &&
            strncasecmp(q, keyword, klen) == 0 &&
            (q[klen] == ' ' || q[klen] == '\t')) {
            const char *r = q + klen;
            while (r < eol && isspace((unsigned char)*r)) r++;
            if (r < eol && isdigit((unsigned char)*r)) {
                int v = atoi(r);
                if (best < 0 || v < best) best = v;
            }
        }
        p = (*eol == '\0') ? eol : eol + 1;
    }
    return best;
}

int main(int argc, char **argv) {
    const char *case_name = NULL;
    const char *db_path   = NULL;
    const char *root_dir  = ".";
    int bench_steps = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--case") == 0 && i + 1 < argc) case_name = argv[++i];
        else if (strcmp(argv[i], "--db") == 0 && i + 1 < argc) db_path = argv[++i];
        else if (strcmp(argv[i], "--root") == 0 && i + 1 < argc) root_dir = argv[++i];
        else if (strcmp(argv[i], "--bench") == 0 && i + 1 < argc) bench_steps = atoi(argv[++i]);
        else {
            fprintf(stderr, "unknown arg: %s\n", argv[i]); return 2;
        }
    }
    if (!case_name || !db_path) {
        fprintf(stderr, "usage: %s --case <name> --db <path> [--root <dir>] [--bench N]\n", argv[0]);
        return 2;
    }

    char input_path[1024];
    snprintf(input_path, sizeof(input_path),
             "%s/test/reference_suite/%s/input.pqi", root_dir, case_name);
    char *script = read_file(input_path);
    if (!script) {
        snprintf(input_path, sizeof(input_path),
                 "test/reference_suite/%s/input.pqi", case_name);
        script = read_file(input_path);
    }
    if (!script) { fprintf(stderr, "can't read %s\n", input_path); return 1; }

    /* cd into case dir so INCLUDE$ resolves */
    char casedir[1024];
    snprintf(casedir, sizeof(casedir),
             "%s/test/reference_suite/%s", root_dir, case_name);
    if (chdir(casedir) != 0) {
        snprintf(casedir, sizeof(casedir),
                 "test/reference_suite/%s", case_name);
        chdir(casedir);
    }

    int rm_id = RM_Create(NXYZ, 1);
    RM_LoadDatabase(rm_id, db_path);
    RM_RunString(rm_id, 1, 1, 1, script);

    RM_SetUnitsSolution(rm_id, 2);
    double v1[NXYZ] = {1.0}; double t1[NXYZ] = {25.0};
    RM_SetPorosity(rm_id, v1);
    RM_SetSaturationUser(rm_id, v1);
    RM_SetRepresentativeVolume(rm_id, v1);
    RM_SetTemperature(rm_id, t1);
    RM_SetPressure(rm_id, v1);

    RM_FindComponents(rm_id);

    int *ic = (int*)malloc(7 * NXYZ * sizeof(int));
    for (int i = 0; i < 7 * NXYZ; i++) ic[i] = -1;
    struct { const char *kw; int slot; } map[] = {
        {"SOLUTION",          0},
        {"EQUILIBRIUM_PHASES",1},
        {"EXCHANGE",          2},
        {"SURFACE",           3},
        {"GAS_PHASE",         4},
        {"SOLID_SOLUTIONS",   5},
        {"KINETICS",          6},
    };
    for (size_t k = 0; k < sizeof(map)/sizeof(map[0]); k++) {
        int n = lowest_user_number(script, map[k].kw);
        if (n >= 0) ic[map[k].slot * NXYZ + 0] = n;
    }
    RM_InitialPhreeqc2Module(rm_id, ic, NULL, NULL);
    RM_SetSelectedOutputOn(rm_id, 1);
    RM_SetTime(rm_id, 0.0);
    RM_SetTimeStep(rm_id, 0.0);

    if (bench_steps > 0) {
        for (int i = 0; i < 10; i++) RM_RunCells(rm_id);
        struct timespec t0, t1s;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        for (int i = 0; i < bench_steps; i++) RM_RunCells(rm_id);
        clock_gettime(CLOCK_MONOTONIC, &t1s);
        double elapsed = (t1s.tv_sec - t0.tv_sec) + (t1s.tv_nsec - t0.tv_nsec) / 1e9;
        printf("{\n  \"case\": \"%s\",\n  \"steps\": %d,\n"
               "  \"total_seconds\": %g,\n  \"per_step_us\": %g\n}\n",
               case_name, bench_steps, elapsed, elapsed / bench_steps * 1e6);
    } else {
        RM_RunCells(rm_id);
        fprintf(stderr, "%s: RunCells completed\n", case_name);
    }

    free(ic); free(script);
    RM_Destroy(rm_id);
    return 0;
}
