
#import <stdint.h>

void* __return_address() {
	return __builtin_return_address(2);
}
int __popcountll(unsigned long long x) {
	return __builtin_popcountll(x);
}
