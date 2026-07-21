#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <stddef.h>
#include <stdint.h>

void *V5VirtualHIDCreate(CFDictionaryRef properties);
int32_t V5VirtualHIDHandleReport(void *device, const uint8_t *report, size_t length);
void V5VirtualHIDRelease(void *device);
