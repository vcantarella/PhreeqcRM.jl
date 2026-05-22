/* C driver for ex2 — batch parameter sweep over temperature.
 *
 * 51 cells, each with SOLUTION 1 + EQUILIBRIUM_PHASES 1 at a different
 * temperature in [25, 75] °C. One RunCells call equilibrates all 51 in
 * parallel. Same problem as driver.jl.
 *
 * Modes:
 *   ./ex2_driver               -> single run, write ex2.sel
 *   ./ex2_driver --bench N     -> run N RunCells iterations after warmup,
 *                                  print per-step time
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "RM_interface_C.h"

#define NXYZ 51

static const char *DB_CANDIDATES[] = {
    "deps/usr/share/doc/PhreeqcRM/database/phreeqc.dat",
    "../../../deps/usr/share/doc/PhreeqcRM/database/phreeqc.dat",
    "/usr/local/share/doc/phreeqc/database/phreeqc.dat",
    NULL,
};

static const char *CHEMISTRY =
    "SOLUTION 1 Pure water\n"
    "    pH 7.0\n"
    "    temp 25.0\n"
    "EQUILIBRIUM_PHASES 1\n"
    "    Gypsum 0.0 1.0\n"
    "    Anhydrite 0.0 1.0\n"
    "SELECTED_OUTPUT 1\n"
    "    -reset true\n"
    "    -temperature true\n"
    "    -si anhydrite gypsum\n"
    "END\n";

static const char *find_database(void) {
    for (const char **p = DB_CANDIDATES; *p; p++) {
        if (access(*p, R_OK) == 0) return *p;
    }
    return NULL;
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

    int rm_id = RM_Create(NXYZ, 1);
    if (rm_id < 0) { fprintf(stderr, "RM_Create failed\n"); return 1; }

    RM_LoadDatabase(rm_id, db);
    RM_RunString(rm_id, 1, 1, 1, CHEMISTRY);
    RM_SetUnitsSolution(rm_id, 2);   /* mol/L */

    double porosity[NXYZ], sat[NXYZ], rv[NXYZ], pressure[NXYZ];
    for (int i = 0; i < NXYZ; i++) {
        porosity[i] = 1.0; sat[i] = 1.0; rv[i] = 1.0; pressure[i] = 1.0;
    }
    RM_SetPorosity(rm_id, porosity);
    RM_SetSaturationUser(rm_id, sat);
    RM_SetRepresentativeVolume(rm_id, rv);
    RM_SetPressure(rm_id, pressure);

    int ncomps = RM_FindComponents(rm_id);
    if (ncomps <= 0) { fprintf(stderr, "FindComponents failed\n"); return 1; }

    int *ic = (int*)malloc(7 * NXYZ * sizeof(int));
    for (int i = 0; i < 7 * NXYZ; i++) ic[i] = -1;
    for (int i = 0; i < NXYZ; i++) {
        ic[0 * NXYZ + i] = 1;       /* SOLUTION 1 */
        ic[1 * NXYZ + i] = 1;       /* EQUILIBRIUM_PHASES 1 */
    }
    RM_InitialPhreeqc2Module(rm_id, ic, NULL, NULL);

    /* Per-cell temperatures AFTER InitialPhreeqc2Module so SOLUTION 1's
     * default temp (25 °C) doesn't win on every cell. */
    double temps[NXYZ];
    for (int i = 0; i < NXYZ; i++) {
        temps[i] = 25.0 + (75.0 - 25.0) * (double)i / (double)(NXYZ - 1);
    }
    RM_SetTemperature(rm_id, temps);

    RM_SetSelectedOutputOn(rm_id, 1);
    RM_SetTime(rm_id, 0.0);
    RM_SetTimeStep(rm_id, 0.0);

    if (bench_runs > 0) {
        /* Warmup. */
        for (int i = 0; i < 10; i++) RM_RunCells(rm_id);
        struct timespec t0, t1;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        for (int i = 0; i < bench_runs; i++) RM_RunCells(rm_id);
        clock_gettime(CLOCK_MONOTONIC, &t1);
        double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
        double per_step_us = elapsed / bench_runs * 1e6;
        printf("{\n  \"steps\": %d,\n  \"total_seconds\": %g,\n"
               "  \"per_step_us\": %g\n}\n", bench_runs, elapsed, per_step_us);
    } else {
        RM_RunCells(rm_id);
        int ncols = RM_GetSelectedOutputColumnCount(rm_id);
        int nrows = RM_GetSelectedOutputRowCount(rm_id);
        double *so = (double*)malloc((size_t)(ncols * nrows) * sizeof(double));
        RM_GetSelectedOutput(rm_id, so);
        FILE *out = fopen("ex2.sel", "w");
        char heading[64];
        for (int j = 0; j < ncols; j++) {
            RM_GetSelectedOutputHeading(rm_id, j, heading, sizeof(heading));
            fprintf(out, "%-16s", heading);
            fputc(j == ncols - 1 ? '\n' : '\t', out);
        }
        for (int i = 0; i < nrows; i++) {
            for (int j = 0; j < ncols; j++) {
                fprintf(out, "%-16.6g", so[i + nrows * j]);
                fputc(j == ncols - 1 ? '\n' : '\t', out);
            }
        }
        fclose(out);
        free(so);
        fprintf(stderr, "ex2.sel written (%d rows × %d cols)\n", nrows, ncols);
    }

    free(ic);
    RM_Destroy(rm_id);
    return 0;
}
