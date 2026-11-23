/*
 * Part of the Stray on iOS Compatibility Research Project.
 * Based on / extending macos-on-ios-public (https://github.com/zorrobyte/macos-on-ios-public).
 *
 * Copyright (c) 2026 Ross Fisher
 * Copyright (c) 2026 Stray on iOS Research Contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// Metal on iOS: macOS's GPU enumeration with hot-plug observers. An iPad has one GPU and no
// eGPU/hot-plug, so report the system default device and a do-nothing observer.
#import <Metal/Metal.h>

__attribute__((visibility("default")))
NSArray<id<MTLDevice>> *MTLCopyAllDevicesWithObserver(id *observer, void (^handler)(id<MTLDevice>, NSString *)) {
    if (observer) *observer = [NSObject new];
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    return d ? @[d] : @[];
}

__attribute__((visibility("default"))) void MTLRemoveDeviceObserver(id observer) {}

__attribute__((visibility("default"))) NSArray<id<MTLDevice>> *MTLCopyAllDevices(void) {
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    return d ? @[d] : @[];
}
