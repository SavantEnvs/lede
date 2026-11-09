/* Shared plumbing for the in-process harnesses: each one #includes a package/utils tool's
 * real source (with main renamed) and drives that main() with a fixed argv over a file
 * holding the fuzz input. */
#ifndef FUZZ_COMMON_H
#define FUZZ_COMMON_H
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

static char fuzz_in_path[64];

static void fuzz_cleanup(void) { unlink(fuzz_in_path); }

/* Tools print to the stdio stdout/stderr; point those streams at /dev/null (fds 1/2 stay
 * untouched so sanitizer and libFuzzer reports still reach the log). */
static int fuzz_init(const char *name)
{
	FILE *null = fopen("/dev/null", "w");
	if (null)
		stdout = stderr = null;
	snprintf(fuzz_in_path, sizeof fuzz_in_path, "/tmp/%s.%d", name, (int)getpid());
	atexit(fuzz_cleanup);
	return 0;
}

static int fuzz_write_input(const uint8_t *data, size_t size)
{
	int fd = open(fuzz_in_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (fd < 0)
		return -1;
	size_t off = 0;
	while (off < size) {
		ssize_t n = write(fd, data + off, size - off);
		if (n <= 0) {
			close(fd);
			return -1;
		}
		off += (size_t)n;
	}
	close(fd);
	return 0;
}
#endif
