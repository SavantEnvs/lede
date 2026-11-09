/* Fuzz fritz_tffs_read (AVM TFFS name/value store reader): the first byte selects the
 * listing mode / key to look up / -s size variant / byte swap, the rest is the TFFS image. */
#include "fuzz_common.h"

#define main fritz_tffs_read_main
#include "../package/utils/fritz-tools/src/fritz_tffs_read.c"
#undef main

static const char *const key_names[4] = {
	"firmware_version", "macwlan", "wlan_key", "does_not_exist"
};

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	(void)argc; (void)argv;
	return fuzz_init("fuzz_fritz_tffs_read");
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char *argv[10];
	char size_arg[24];
	uint8_t pad[sizeof(struct tffs_entry_header)] = { 0 };
	const uint8_t *img = data + (size ? 1 : 0);
	size_t img_len = size ? size - 1 : 0;
	uint8_t mode = size ? data[0] : 0;
	int argc = 0;

	/* A TFFS image is at least one entry header long (find_entry() reads one at offset 0), so a
	 * shorter input is zero-padded to that size, not rejected. */
	if (img_len < sizeof pad) {
		memcpy(pad, img, img_len);
		img = pad;
		img_len = sizeof pad;
	}
	if (fuzz_write_input(img, img_len))
		return -1;

	progname = NULL;
	input_file = NULL;
	tffs_size = 0;
	name_filter = NULL;
	show_all = false;
	print_all_key_names = false;
	swap_bytes = false;
	optind = 0;

	static char name0[] = "fritz_tffs_read";
	argv[argc++] = name0;
	if (mode & 0x80)
		argv[argc++] = "-b";
	argv[argc++] = "-i";
	argv[argc++] = fuzz_in_path;
	/* bits 4-5: -s absent / the exact file size / one byte more than the file / half of it */
	switch ((mode >> 4) & 3) {
	case 1:
		snprintf(size_arg, sizeof size_arg, "%zu", img_len);
		break;
	case 2:
		snprintf(size_arg, sizeof size_arg, "0x%zx", img_len + 1);
		break;
	case 3:
		snprintf(size_arg, sizeof size_arg, "%zu", img_len / 2 + 1);
		break;
	}
	if ((mode >> 4) & 3) {
		argv[argc++] = "-s";
		argv[argc++] = size_arg;
	}
	switch (mode & 3) {
	case 0:
		argv[argc++] = "-l";
		break;
	case 1:
		argv[argc++] = "-a";
		break;
	default:
		argv[argc++] = "-n";
		argv[argc++] = (char *)key_names[(mode >> 2) & 3];
		break;
	}
	argv[argc] = NULL;
	fritz_tffs_read_main(argc, argv);
	return 0;
}
