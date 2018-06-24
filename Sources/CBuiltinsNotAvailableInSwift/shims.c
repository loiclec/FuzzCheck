
#import <stdint.h>

void* __return_address() {
	return __builtin_return_address(1);
}
/*
void* __return_address1() {
    return __builtin_return_address(1);
}
*/
