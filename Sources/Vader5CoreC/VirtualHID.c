#include "VirtualHID.h"
#include <IOKit/hidsystem/IOHIDUserDevice.h>
#include <mach/mach_time.h>

void *V5VirtualHIDCreate(CFDictionaryRef properties) {
    return (void *)IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault, properties, 0);
}

int32_t V5VirtualHIDHandleReport(void *device, const uint8_t *report, size_t length) {
    return IOHIDUserDeviceHandleReportWithTimeStamp(
        (IOHIDUserDeviceRef)device, mach_absolute_time(), report, (CFIndex)length);
}

void V5VirtualHIDRelease(void *device) {
    if (device) CFRelease((CFTypeRef)device);
}
