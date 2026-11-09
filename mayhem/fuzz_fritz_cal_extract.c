/* Fuzz fritz_cal_extract (zlib calibration-data extractor for AVM EVA loader images): the
 * first four bytes pick entry id, seek offset, output limit, skip, the number forms (decimal
 * or 0x hex) and an unseekable offset; the rest is the image. */
#include "fuzz_common.h"

#define main fritz_cal_extract_main
#include "../package/utils/fritz-tools/src/fritz_cal_extract.c"
#undef main

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	(void)argc; (void)argv;
	return fuzz_init("fuzz_fritz_cal_extract");
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char entry[16], seek[16], limit[16], skip[16];
	char *argv[13];
	int argc = 0;

	if (size < 4)
		return -1;
	if (fuzz_write_input(data + 4, size - 4))
		return -1;

	/* The tool parses each number as "0x<hex>" or decimal; the high option bits pick the form. */
	if (data[0] & 0x10)
		snprintf(entry, sizeof entry, "%u", 0x1000 + (data[0] & 0xf));
	else
		snprintf(entry, sizeof entry, "0x%x", 0x1000 + (data[0] & 0xf));
	snprintf(seek, sizeof seek, (data[3] & 4) ? "0x%x" : "%u", data[1]);
	if (data[3] & 32)	/* negative as an int: the tool's fseek() fails */
		snprintf(seek, sizeof seek, "4294967295");
	snprintf(limit, sizeof limit, (data[3] & 8) ? "0x%x" : "%u", data[2] * 16u);
	snprintf(skip, sizeof skip, (data[3] & 16) ? "0x%x" : "%u", data[3] & 3u);

	static char name0[] = "fritz_cal_extract";
	argv[argc++] = name0;
	argv[argc++] = "-s";
	argv[argc++] = seek;
	argv[argc++] = "-l";
	argv[argc++] = limit;
	argv[argc++] = "-i";
	argv[argc++] = skip;
	argv[argc++] = "-o";
	argv[argc++] = "/dev/null";
	argv[argc++] = fuzz_in_path;
	argv[argc++] = "-e";
	argv[argc++] = entry;
	argv[argc] = NULL;
	optind = 0;
	errno = 0;
	fritz_cal_extract_main(argc, argv);
	return 0;
}
