IPHONEOS_SDK ?= $(HOME)/theos/sdks/iPhoneOS16.5.sdk
IPHONEOS_DEPLOYMENT_TARGET ?= 14.0
ARCH ?= arm64

CC      := clang
CFLAGS  := --target=$(ARCH)-apple-ios$(IPHONEOS_DEPLOYMENT_TARGET) \
           -isysroot $(IPHONEOS_SDK) \
           -arch $(ARCH) \
           -fobjc-arc -Wall -Wno-deprecated-declarations -Os

LDFLAGS := -shared -dynamiclib -fuse-ld=lld \
           -framework Foundation \
           -install_name @rpath/CelestePatch.dylib

SRC     := CelestePatch.m
DYLIB   := CelestePatch.dylib

.PHONY: all clean
all: $(DYLIB)

$(DYLIB): $(SRC)
	@test -d "$(IPHONEOS_SDK)" || { echo "SDK introuvable: $(IPHONEOS_SDK)"; exit 1; }
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<
	@echo "built $@ ($$(stat -c '%s' $@) bytes, arch $(ARCH))"

clean:
	rm -f $(DYLIB)
