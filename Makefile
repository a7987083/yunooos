SDK ?= iphoneos
ARCH ?= arm64
MIN_IOS ?= 12.0
BUILD_DIR ?= build
CFLAGS = -fobjc-arc -arch $(ARCH) -miphoneos-version-min=$(MIN_IOS) -Wall -Wextra -Wno-deprecated-declarations
OBJC = xcrun --sdk $(SDK) clang
OBJCXX = xcrun --sdk $(SDK) clang++

SOURCES_M = CloudSave/Profile/CSSaveProfile.m
SOURCES_MM = CloudSave/Discovery/CSAutoDiscovery.mm CloudSave/API/CloudSaveDiscoveryAPI.mm
OBJECTS = $(BUILD_DIR)/CSSaveProfile.o $(BUILD_DIR)/CSAutoDiscovery.o $(BUILD_DIR)/CloudSaveDiscoveryAPI.o
DYLIB = $(BUILD_DIR)/yunooos.dylib

.PHONY: check dylib clean

check: $(OBJECTS)
	@echo "yunooos AutoDiscovery compile check passed"

dylib: $(DYLIB)
	@echo "built $(DYLIB)"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/CSSaveProfile.o: CloudSave/Profile/CSSaveProfile.m | $(BUILD_DIR)
	$(OBJC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/CSAutoDiscovery.o: CloudSave/Discovery/CSAutoDiscovery.mm | $(BUILD_DIR)
	$(OBJCXX) $(CFLAGS) -std=c++17 -c $< -o $@

$(BUILD_DIR)/CloudSaveDiscoveryAPI.o: CloudSave/API/CloudSaveDiscoveryAPI.mm | $(BUILD_DIR)
	$(OBJCXX) $(CFLAGS) -std=c++17 -c $< -o $@

$(DYLIB): $(OBJECTS)
	$(OBJCXX) -dynamiclib -arch $(ARCH) -miphoneos-version-min=$(MIN_IOS) \
		-Wl,-install_name,@rpath/yunooos.dylib \
		-framework Foundation $(OBJECTS) -o $@

clean:
	rm -rf $(BUILD_DIR)
