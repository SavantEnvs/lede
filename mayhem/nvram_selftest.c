/* Known-answer test for libnvram, built with the normal flags by build.sh and run by test.sh. */
#include "../package/utils/nvram/src/nvram.c"
#include "../package/utils/nvram/src/crc.c"

static int cmp_tuple(const void *a, const void *b)
{
	return strcmp((*(nvram_tuple_t *const *)a)->name, (*(nvram_tuple_t *const *)b)->name);
}

static void dump(nvram_handle_t *h)
{
	nvram_tuple_t *all = nvram_getall(h), *t, *arr[64];
	int n = 0, i;

	for (t = all; t && n < 64; t = t->next)
		arr[n++] = t;
	qsort(arr, n, sizeof arr[0], cmp_tuple);
	for (i = 0; i < n; i++)
		printf("%s=%s\n", arr[i]->name, arr[i]->value);
	while (all) {
		t = all->next;
		free(all);
		all = t;
	}
}

int main(int argc, char **argv)
{
	nvram_handle_t *h;
	nvram_header_t *hdr;
	uint8_t crc;

	if (argc < 2)
		return 2;
	nvram_part_size = NVRAM_MIN_SPACE;

	h = nvram_open(argv[1], NVRAM_RW);
	if (!h) {
		puts("open failed");
		return 1;
	}
	printf("offset=%u len=%u\n", h->offset, nvram_header(h)->len);
	dump(h);

	nvram_set(h, "lan_ipaddr", "10.0.0.1");
	nvram_set(h, "new_var", "xyz");
	nvram_unset(h, "wan_proto");
	nvram_commit(h);
	hdr = nvram_header(h);
	crc = hndcrc8((uint8_t *)hdr + NVRAM_CRC_START_POSITION, hdr->len - NVRAM_CRC_START_POSITION, 0xff);
	printf("committed len=%u crc=0x%02x stored=0x%02x\n", hdr->len, crc, hdr->crc_ver_init & 0xff);
	nvram_close(h);

	h = nvram_open(argv[1], NVRAM_RO);
	if (!h) {
		puts("reopen failed");
		return 1;
	}
	puts("reopened");
	dump(h);
	nvram_close(h);
	return 0;
}
