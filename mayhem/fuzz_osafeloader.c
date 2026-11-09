/* Fuzz osafeloader (TP-Link SafeLoader image reader): first byte picks info vs extract, the
 * rest is the file. */
#include "fuzz_common.h"

#define main osafeloader_main
#include "../package/utils/osafeloader/src/osafeloader.c"
#undef main

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	(void)argc; (void)argv;
	return fuzz_init("fuzz_osafeloader");
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	if (size < 1)
		return -1;
	if (fuzz_write_input(data + 1, size - 1))
		return -1;

	safeloader_path = NULL;
	partition_name = NULL;
	out_path = NULL;
	optind = 0;

	if (data[0] & 1) {
		char *argv[] = { "osafeloader", "info", fuzz_in_path, NULL };
		osafeloader_main(3, argv);
	} else {
		char *argv[] = { "osafeloader", "extract", fuzz_in_path, "-p", "os-image", "-o", "/dev/null", NULL };
		osafeloader_main(7, argv);
	}
	return 0;
}
