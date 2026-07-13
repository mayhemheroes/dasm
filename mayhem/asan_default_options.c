/*
 * Weak ASan option defaults baked into the DASM fuzz target.
 *
 * DASM allocates through a permalloc() arena and never frees it (memory stays reachable via globals
 * until process exit) — legitimate for an assembler, but LeakSanitizer runs at exit and could flag
 * arena chunks as leaks on every single fuzz run, drowning real defects in noise. Disable leak
 * detection here; the fuzzer still gets the important ASan/UBSan memory-safety checks.
 *
 * `__attribute__((weak))` lets an explicit ASAN_OPTIONS=... env var (e.g. from Mayhem) override this.
 */
__attribute__((weak)) const char *__asan_default_options(void) {
    return "detect_leaks=0";
}
