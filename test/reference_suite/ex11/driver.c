/* C driver for ex11 (transport + cation exchange).
 *
 * Same problem as driver.jl: 40 cells, 100 shifts, plug-flow advection
 * with cation exchange. Re-implements the ADVECTION semantics via the
 * PhreeqcRM cell API.
 *
 * Build: handled by test/c_build/Makefile.
 *
 * Modes:
 *   ./ex11_driver               -> run once, write ex11.sel (100 rows × 5 cols)
 *   ./ex11_driver --bench N     -> run N times in a loop, print elapsed time
 *                                  for the inner loop only (per-step micros)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "RM_interface_C.h"

#define NXYZ 40
#define NSTEPS 100
#define PUNCH_CELL_INDEX 39   /* zero-based; cell 40 in the script */

static const char *DB_CANDIDATES[] = {
    "deps/usr/share/doc/PhreeqcRM/database/phreeqc.dat",
    "../../../deps/usr/share/doc/PhreeqcRM/database/phreeqc.dat",
    "/usr/local/share/doc/phreeqc/database/phreeqc.dat",
    NULL,
};

static const char *CHEMISTRY =
    "SOLUTION 0  CaCl2\n"
    "    units mmol/kgw\n"
    "    temp 25.0\n"
    "    pH 7.0 charge\n"
    "    pe 12.5 O2(g) -0.68\n"
    "    Ca 0.6\n"
    "    Cl 1.2\n"
    "SOLUTION 1-40 Initial solution for column\n"
    "    units mmol/kgw\n"
    "    temp 25.0\n"
    "    pH 7.0 charge\n"
    "    pe 12.5 O2(g) -0.68\n"
    "    Na 1.0\n"
    "    K  0.2\n"
    "    N(5) 1.2\n"
    "EXCHANGE 1-40\n"
    "    -equilibrate 1\n"
    "    X 0.0011\n"
    "END\n";

/* Locate phreeqc.dat by trying candidates. */
static const char *find_database(void) {
    for (const char **p = DB_CANDIDATES; *p; p++) {
        if (access(*p, R_OK) == 0) return *p;
    }
    return NULL;
}

/* Return column index of a component name in the rm's component list, or -1. */
static int component_index(int rm_id, int ncomps, const char *name) {
    char buf[64];
    for (int i = 0; i < ncomps; i++) {
        RM_GetComponent(rm_id, i, buf, sizeof(buf));
        if (strcmp(buf, name) == 0) return i;
    }
    return -1;
}

/* One ADVECTION shift: cell i ← cell i-1, cell 1 ← boundary, then run_cells. */
static void step(int rm_id, double *c, const double *bc, int nxyz, int ncomps) {
    /* Concentration buffer layout: c[i_cell + nxyz * i_comp] */
    for (int j = 0; j < ncomps; j++) {
        for (int i = nxyz - 1; i >= 1; i--) {
            c[i + nxyz * j] = c[(i - 1) + nxyz * j];
        }
        c[0 + nxyz * j] = bc[j];
    }
    RM_SetConcentrations(rm_id, c);
    RM_RunCells(rm_id);
    RM_GetConcentrations(rm_id, c);
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

    RM_SetUnitsSolution(rm_id, 2);    /* mol/L */
    double porosity[NXYZ], sat[NXYZ], rv[NXYZ], temperature[NXYZ], pressure[NXYZ];
    for (int i = 0; i < NXYZ; i++) {
        porosity[i] = 1.0; sat[i] = 1.0; rv[i] = 1.0;
        temperature[i] = 25.0; pressure[i] = 1.0;
    }
    RM_SetPorosity(rm_id, porosity);
    RM_SetSaturationUser(rm_id, sat);
    RM_SetRepresentativeVolume(rm_id, rv);
    RM_SetTemperature(rm_id, temperature);
    RM_SetPressure(rm_id, pressure);

    int ncomps = RM_FindComponents(rm_id);
    int iNa = component_index(rm_id, ncomps, "Na");
    int iCl = component_index(rm_id, ncomps, "Cl");
    int iK  = component_index(rm_id, ncomps, "K");
    int iCa = component_index(rm_id, ncomps, "Ca");
    if (iNa < 0 || iCl < 0 || iK < 0 || iCa < 0) {
        fprintf(stderr, "missing component\n"); return 1;
    }

    /* Initial conditions table: ic[cat * NXYZ + cell], 7 categories. */
    int *ic = (int*)malloc(7 * NXYZ * sizeof(int));
    for (int i = 0; i < 7 * NXYZ; i++) ic[i] = -1;
    for (int i = 0; i < NXYZ; i++) {
        ic[0 * NXYZ + i] = i + 1;   /* SOLUTION i+1 */
        ic[2 * NXYZ + i] = i + 1;   /* EXCHANGE i+1 */
    }
    RM_InitialPhreeqc2Module(rm_id, ic, NULL, NULL);

    /* Boundary concentrations from SOLUTION 0 (shape: 1 × ncomps). */
    int bc_sol1[1] = {0};
    int bc_sol2[1] = {-1};
    double bc_f1[1] = {1.0};
    double *bc = (double*)malloc(ncomps * sizeof(double));
    RM_InitialPhreeqc2Concentrations(rm_id, bc, 1, bc_sol1, bc_sol2, bc_f1);

    /* Cell concentrations: NXYZ × ncomps. */
    double *c = (double*)malloc(NXYZ * ncomps * sizeof(double));
    RM_GetConcentrations(rm_id, c);

    RM_SetTimeStep(rm_id, 0.0);
    RM_SetTime(rm_id, 0.0);

    if (bench_runs > 0) {
        /* Total steps requested. Run a warmup of 100 steps to reach steady
         * state, then time exactly `bench_runs` steps in a tight loop. No
         * per-iteration setup so the measurement is pure step time, matching
         * Julia's @benchmark on a single step!. */
        for (int s = 0; s < 100; s++) step(rm_id, c, bc, NXYZ, ncomps);
        struct timespec t0, t1;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        for (int s = 0; s < bench_runs; s++) {
            step(rm_id, c, bc, NXYZ, ncomps);
        }
        clock_gettime(CLOCK_MONOTONIC, &t1);
        double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
        double per_step_us = elapsed / bench_runs * 1e6;
        printf("{\n  \"steps\": %d,\n  \"total_seconds\": %g,\n"
               "  \"per_step_us\": %g\n}\n",
               bench_runs, elapsed, per_step_us);
    } else {
        /* Single run mode: produce ex11.sel matching CLI's ex11adv.sel. */
        FILE *out = fopen("ex11.sel", "w");
        fprintf(out, "        step\t          Na\t          Cl\t           K\t          Ca\t    Pore_vol\t\n");
        for (int s = 1; s <= NSTEPS; s++) {
            step(rm_id, c, bc, NXYZ, ncomps);
            fprintf(out, "         %3d\t  %.4e\t  %.4e\t  %.4e\t  %.4e\t  %.4e\t\n",
                    s,
                    c[PUNCH_CELL_INDEX + NXYZ * iNa],
                    c[PUNCH_CELL_INDEX + NXYZ * iCl],
                    c[PUNCH_CELL_INDEX + NXYZ * iK],
                    c[PUNCH_CELL_INDEX + NXYZ * iCa],
                    (s + 0.5) / (double)(PUNCH_CELL_INDEX + 1));
        }
        fclose(out);
        fprintf(stderr, "ex11.sel written (%d rows)\n", NSTEPS);
    }

    free(c); free(bc); free(ic);
    RM_Destroy(rm_id);
    return 0;
}
