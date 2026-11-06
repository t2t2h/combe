# ---------------------------------------------------------------
# TheosDylib - diagnostics overlay (FPS / CPU / MEM / Net / Touch)
# ---------------------------------------------------------------
# Minimum iOS 14 so Network.framework and UIWindowScene are available.
export TARGET := iphone:clang:latest:14.0

# arm64e needs a toolchain that supports it (Xcode 12+).
# For sideloading (non-jailbroken) build with:  make ARCHS=arm64
export ARCHS = arm64 arm64e

# Uncomment for rootless jailbreaks (Dopamine, palera1n rootless):
# export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TheosDylib

TheosDylib_FILES = $(wildcard Sources/*.mm)
TheosDylib_CFLAGS = -fobjc-arc -IHeaders -Wno-deprecated-declarations
TheosDylib_CCFLAGS = -std=c++17
TheosDylib_FRAMEWORKS = UIKit Foundation QuartzCore Network CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk
