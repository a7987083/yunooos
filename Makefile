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

.PHONY: check clean

check: $(OBJECTS)
	@echo "yunooos AutoDiscovery compile check passed"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/CSSaveProfile.o: CloudSave/Profile/CSSaveProfile.m | $(BUILD_DIR)
	$(OBJC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/CSAutoDiscovery.o: CloudSave/Discovery/CSAutoDiscovery.mm | $(BUILD_DIR)
	$(OBJCXX) $(CFLAGS) -std=c++17 -c $< -o $@

$(BUILD_DIR)/CloudSaveDiscoveryAPI.o: CloudSave/API/CloudSaveDiscoveryAPI.mm | $(BUILD_DIR)
	$(OBJCXX) $(CFLAGS) -std=c++17 -c $< -o $@

clean:
	rm -rf $(BUILD_DIR)
