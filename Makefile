SDK ?= iphoneos
ARCH ?= arm64
MIN_IOS ?= 12.0
BUILD_DIR ?= build
DEBUG_UI ?= 1

CFLAGS = -fobjc-arc -arch $(ARCH) -miphoneos-version-min=$(MIN_IOS) -Wall -Wextra -Wno-deprecated-declarations
OBJC = xcrun --sdk $(SDK) clang
OBJCXX = xcrun --sdk $(SDK) clang++

CORE_OBJECTS = $(BUILD_DIR)/CSSaveProfile.o $(BUILD_DIR)/CSAutoDiscovery.o $(BUILD_DIR)/CloudSaveDiscoveryAPI.o
DEBUG_UI_OBJECTS = $(BUILD_DIR)/CSH5GGDebugUI.o $(BUILD_DIR)/CSH5GGDebugBootstrap.o
OBJECTS = $(CORE_OBJECTS)
LINK_FRAMEWORKS = -framework Foundation
DYLIB = $(BUILD_DIR)/yunooos-debug.dylib

ifeq ($(DEBUG_UI),1)
OBJECTS += $(DEBUG_UI_OBJECTS)
LINK_FRAMEWORKS += -framework UIKit -framework QuartzCore -framework CoreGraphics
endif

.PHONY: check dylib clean

check: $(OBJECTS)
	@echo "yunooos AutoDiscovery compile check passed (DEBUG_UI=$(DEBUG_UI))"

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

$(BUILD_DIR)/CSH5GGDebugUI.o: DebugUI/CSH5GGDebugUI.mm DebugUI/CSH5GGDebugUI.h | $(BUILD_DIR)
	$(OBJCXX) $(CFLAGS) -std=c++17 -c $< -o $@

$(BUILD_DIR)/CSH5GGDebugBootstrap.o: DebugUI/CSH5GGDebugBootstrap.mm DebugUI/CSH5GGDebugUI.h | $(BUILD_DIR)
	$(OBJCXX) $(CFLAGS) -std=c++17 -c $< -o $@

$(DYLIB): $(OBJECTS)
	$(OBJCXX) -dynamiclib -arch $(ARCH) -miphoneos-version-min=$(MIN_IOS) \
		-Wl,-install_name,@rpath/yunooos-debug.dylib \
		$(LINK_FRAMEWORKS) $(OBJECTS) -o $@

clean:
	rm -rf $(BUILD_DIR)
