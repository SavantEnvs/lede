/* Fuzz oseama (Seama container reader/writer): first byte picks the subcommand, the rest is
 * the file. */
#include "fuzz_common.h"

#define main oseama_main
#include "../package/utils/oseama/src/oseama.c"
#undef main

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	(void)argc; (void)argv;
	return fuzz_init("fuzz_oseama");
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char idx[2];
	char meta[64];

	if (size < 1)
		return -1;
	if (fuzz_write_input(data + 1, size - 1))
		return -1;

	seama_path = NULL;
	entity_idx = -1;
	out_path = NULL;
	optind = 0;

	idx[0] = '0' + ((data[0] >> 2) & 7);
	idx[1] = 0;

	switch (data[0] & 3) {
	case 0: {
		char *argv[] = { "oseama", "info", fuzz_in_path, NULL };
		oseama_main(3, argv);
		break;
	}
	case 1: {
		char *argv[] = { "oseama", "info", fuzz_in_path, "-e", idx, NULL };
		oseama_main(5, argv);
		break;
	}
	case 2: {
		char *argv[] = { "oseama", "extract", fuzz_in_path, "-e", idx, "-o", "/dev/null", NULL };
		oseama_main(7, argv);
		break;
	}
	default: {
		/* entity: the input doubles as the meta string (up to its first NUL) */
		size_t n = size - 1 < sizeof(meta) - 1 ? size - 1 : sizeof(meta) - 1;
		memcpy(meta, data + 1, n);
		meta[n] = 0;
		char *argv[] = { "oseama", "entity", "/dev/null", "-m", meta, "-f", fuzz_in_path, NULL };
		oseama_main(7, argv);
		break;
	}
	}
	return 0;
}
