#include <stdio.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

char *
alloc_workbuf(size_t size)
{
	char *ptr;

	/* allocate some memory */
	ptr = malloc(size);

	/* return NULL on failure */
	if (ptr == NULL)
		return NULL;

	/* lock this buffer into RAM */
	if (mlock(ptr, size)) {
		if (errno == ENOMEM)
			fprintf(stderr, "Not enough permissions to lock memory\n");
		free(ptr);
		return NULL;
	}
	return ptr;
}

int
main(int argc, char *argv[])
{
	size_t size;
	char *memhog = NULL;
	if (argc != 2) {
		fprintf(stderr, "Usage: memhog <size in GB>\n");
		exit(-1);
	}

	size = atoi(argv[1]);

	memhog = alloc_workbuf(size * 1024 * 1024 * 1024UL);

	if (!memhog) {
		fprintf(stderr, "Could not allocate %ld GB\n", size);
		exit(-1);
	}

	while (memhog)
		sleep(10);
	return 0;
}
