#import <Foundation/Foundation.h>

@interface HelloWorld : NSObject
@end

@implementation HelloWorld
@end

int main(void) {
    @autoreleasepool {
        HelloWorld *object = [HelloWorld new];
        NSLog(@"Hello from Objective-C!");
        (void)object;
    }
    return 0;
}
