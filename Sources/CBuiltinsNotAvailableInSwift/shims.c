
#import <stdint.h>

void* __return_address() {
	return __builtin_return_address(2);
}

