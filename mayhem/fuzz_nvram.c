/* Fuzz libnvram (Broadcom NVRAM partition parser/committer) over a partition image file. The
 * partition is nvram_part_size = 0x8000 bytes (NVRAM_MIN_SPACE, the smallest partition the
 * library's own scan loop supports); the input is the start of it, the rest reads as zeros. */
#include "fuzz_common.h"

#include "../package/utils/nvram/src/nvram.c"
#include "../package/utils/nvram/src/crc.c"

#define PART_SIZE NVRAM_MIN_SPACE

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	(void)argc; (void)argv;
	return fuzz_init("fuzz_nvram");
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	nvram_handle_t *h;
	nvram_tuple_t *t, *next;

	if (size > PART_SIZE)
		return -1;
	if (fuzz_write_input(data, size))
		return -1;
	if (truncate(fuzz_in_path, PART_SIZE))
		return -1;

	nvram_part_size = PART_SIZE;
	h = nvram_open(fuzz_in_path, NVRAM_RO);
	if (!h)
		return 0;

	for (t = nvram_getall(h); t; t = next) {
		next = t->next;
		(void)nvram_get(h, t->name);
		free(t);
	}
	(void)nvram_get(h, "sdram_init");
	nvram_set(h, "fuzz_var", "fuzz_value");
	nvram_unset(h, "wan_proto");
	nvram_commit(h);
	nvram_close(h);
	return 0;
}
