#include <stdio.h>
#include <stdlib.h>

int main(int argc, char* argv[]) {
	if (argc >= 2) {
		int x;
		x = atoi(argv[1]);
  	// INSTRUMENT SHOULD ADD abst_cond() IN FOLLOWING LINE
		if (x > 5) {
			printf("x is 5 or larger\n");
		} else if (x == 5) {
		        printf("x is exactly 5\n");
		} else {
			printf("x is smaller than 5\n");
		}
	}
	return EXIT_SUCCESS;
}
