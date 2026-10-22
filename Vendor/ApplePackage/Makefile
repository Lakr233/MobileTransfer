PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
REPOSITORY ?= Lakr233/ApplePackage
RELEASE_TAG ?= $(shell git describe --tags --abbrev=0 2>/dev/null)
ARCH := $(shell uname -m)
SWIFT_MINOR := $(shell swift --version | sed -n 's/^.*Swift version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1.\2/p')
ifeq ($(SWIFT_MINOR),5.4)
PRODUCT ?= ApplePackage
BUILD_ARGUMENT := --target $(PRODUCT)
INSTALL_KIND := release
else
PRODUCT ?= ApplePackageTool
BUILD_ARGUMENT := --product $(PRODUCT)
INSTALL_KIND := executable
endif
INSTALL_NAME := ApplePackageTool
BUILD_DIR = $(shell swift build -c release --show-bin-path)
RELEASE_ARTIFACT := ApplePackageTool-$(RELEASE_TAG)-macos-$(ARCH).zip
RELEASE_URL := https://github.com/$(REPOSITORY)/releases/download/$(RELEASE_TAG)/$(RELEASE_ARTIFACT)

.PHONY: all build install uninstall clean

all: build

build:
	swift build -c release $(BUILD_ARGUMENT)

install:
ifeq ($(INSTALL_KIND),executable)
	swift build -c release --product $(INSTALL_NAME)
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 755 "$(BUILD_DIR)/$(INSTALL_NAME)" "$(DESTDIR)$(BINDIR)/$(INSTALL_NAME)"
else
	swift build -c release $(BUILD_ARGUMENT)
	@test -n "$(RELEASE_TAG)" || (echo "RELEASE_TAG is required"; exit 1)
	@tmp_dir="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp_dir"' EXIT; \
	curl -fL "$(RELEASE_URL)" -o "$$tmp_dir/$(RELEASE_ARTIFACT)"; \
	unzip -q "$$tmp_dir/$(RELEASE_ARTIFACT)" -d "$$tmp_dir"; \
	tool_dir="$$tmp_dir/ApplePackageTool-$(RELEASE_TAG)-macos-$(ARCH)"; \
	install -d "$(DESTDIR)$(BINDIR)"; \
	install -m 755 "$$tool_dir/$(INSTALL_NAME)" "$(DESTDIR)$(BINDIR)/$(INSTALL_NAME)"; \
	for dylib in "$$tool_dir"/*.dylib; do \
		if [ -f "$$dylib" ]; then \
			install -m 644 "$$dylib" "$(DESTDIR)$(BINDIR)/"; \
		fi; \
	done
endif

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/$(INSTALL_NAME)"
	rm -f "$(DESTDIR)$(BINDIR)/libswift_Concurrency.dylib"
	rm -f "$(DESTDIR)$(BINDIR)/libswiftCompatibilitySpan.dylib"

clean:
	swift package clean
