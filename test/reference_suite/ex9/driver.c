/* C driver for ex9 — kinetic Fe(II) oxidation, single cell, sequential
 * time stepping.
 *
 * Modes:
 *   ./ex9_driver               -> 11 steps, write Days/Fe(2)/Fe(3)/pH/SI to ex9.sel
 *   ./ex9_driver --bench N     -> N RunCells iterations with fixed dt=100s
 *                                  after warmup, print per-step time
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "RM_interface_C.h"

#define NXYZ 1

static const char *DB_CANDIDATES[] = {
    "deps/usr/share/doc/PhreeqcRM/database/phreeqc.dat",
    "../../../deps/usr/share/doc/PhreeqcRM/database/phreeqc.dat",
    "/usr/local/share/doc/phreeqc/database/phreeqc.dat",
    NULL,
};

static const double STEPS_S[] = {
    100.0, 400.0, 3100.0, 10800.0, 21600.0,
    5.04e4, 8.64e4, 1.728e5, 1.728e5, 1.728e5, 1.728e5,
};
#define N_STEPS (sizeof(STEPS_S) / sizeof(STEPS_S[0]))

static const char *find_database(void) {
    for (const char **p = DB_CANDIDATES; *p; p++) {
        if (access(*p, R_OK) == 0) return *p;
    }
    return NULL;
}

/* Read the .pqi file as the script. Allocated; caller frees. */
static char *read_script_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = (char*)malloc((size_t)n + 1);
    fread(buf, 1, (size_t)n, f);
    buf[n] = '\0';
    fclose(f);
    return buf;
}

int main(int argc, char **argv) {
    int bench_runs = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--bench") == 0 && i + 1 < argc) {
            bench_runs = atoi(argv[++i]);
        }
    }

    const char *db = find_database();
    if (!db) { fprintf(stderr, "phreeqc.dat not found\n"); return 1; }

    /* Locate ex9's input.pqi relative to where the binary lives. */
    const char *script_paths[] = {
        "test/reference_suite/ex9/input.pqi",
        "../../test/reference_suite/ex9/input.pqi",
        "../reference_suite/ex9/input.pqi",
        NULL,
    };
    char *script = NULL;
    for (const char **p = script_paths; *p; p++) {
        script = read_script_file(*p);
        if (script) break;
    }
    if (!script) { fprintf(stderr, "ex9 input.pqi not found\n"); return 1; }

    int rm_id = RM_Create(NXYZ, 1);
    RM_LoadDatabase(rm_id, db);
    RM_RunString(rm_id, 1, 1, 1, script);
    RM_SetUnitsSolution(rm_id, 2);

    double v1[NXYZ] = {1.0};
    double t1[NXYZ] = {25.0};
    RM_SetPorosity(rm_id, v1);
    RM_SetSaturationUser(rm_id, v1);
    RM_SetRepresentativeVolume(rm_id, v1);
    RM_SetTemperature(rm_id, t1);
    RM_SetPressure(rm_id, v1);

    int ncomps = RM_FindComponents(rm_id);
    int *ic = (int*)calloc(7 * NXYZ, sizeof(int));
    for (int i = 0; i < 7 * NXYZ; i++) ic[i] = -1;
    ic[0 * NXYZ + 0] = 1;       /* SOLUTION 1 */
    ic[1 * NXYZ + 0] = 1;       /* EQUILIBRIUM_PHASES 1 */
    ic[6 * NXYZ + 0] = 1;       /* KINETICS 1 */
    RM_InitialPhreeqc2Module(rm_id, ic, NULL, NULL);

    RM_SetSelectedOutputOn(rm_id, 1);

    if (bench_runs > 0) {
        /* Warmup with a short dt. */
        RM_SetTime(rm_id, 0.0);
        RM_SetTimeStep(rm_id, 100.0);
        for (int i = 0; i < 10; i++) RM_RunCells(rm_id);

        struct timespec t0, t1s;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        double cumulative_t = 1000.0;
        for (int i = 0; i < bench_runs; i++) {
            cumulative_t += 100.0;
            RM_SetTime(rm_id, cumulative_t);
            RM_SetTimeStep(rm_id, 100.0);
            RM_RunCells(rm_id);
        }
        clock_gettime(CLOCK_MONOTONIC, &t1s);
        double elapsed = (t1s.tv_sec - t0.tv_sec) + (t1s.tv_nsec - t0.tv_nsec) / 1e9;
        double per_step_us = elapsed / bench_runs * 1e6;
        printf("{\n  \"steps\": %d,\n  \"total_seconds\": %g,\n"
               "  \"per_step_us\": %g\n}\n", bench_runs, elapsed, per_step_us);
    } else {
        FILE *out = fopen("ex9.sel", "w");
        fprintf(out, "Days\tFe(2)\tFe(3)\tpH\tsi_goethite\n");
        double cumulative = 0.0;
        for (size_t i = 0; i < N_STEPS; i++) {
            cumulative += STEPS_S[i];
            RM_SetTime(rm_id, cumulative);
            RM_SetTimeStep(rm_id, STEPS_S[i]);
            RM_RunCells(rm_id);
            int ncols = RM_GetSelectedOutputColumnCount(rm_id);
            double *so = (double*)malloc(ncols * NXYZ * sizeof(double));
            RM_GetSelectedOutput(rm_id, so);
            /* Heading order in USER_PUNCH: Days, Fe(2), Fe(3), pH, si_goethite */
            fprintf(out, "%g\t%g\t%g\t%g\t%g\n",
                    cumulative / 86400.0,
                    so[0 * NXYZ + 0],     /* approximate col 0 = first PUNCH value */
                    so[1 * NXYZ + 0],
                    so[2 * NXYZ + 0],
                    so[3 * NXYZ + 0]);
            free(so);
        }
        fclose(out);
        fprintf(stderr, "ex9.sel written (%zu rows)\n", N_STEPS);
    }

    free(ic); free(script);
    RM_Destroy(rm_id);
    return 0;
}
