# SwiftBruja Makefile
# Build and install the bruja CLI with full Metal shader support

SCHEME = bruja
BINARY = bruja
BIN_DIR = ./bin
DESTINATION = platform=macOS,arch=arm64
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: all build release install clean test help

all: install

# Development build (swift build - fast but no Metal shaders)
build:
	swift build --product $(SCHEME)

# Release build with xcodebuild + copy to bin
release:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Release build
	@mkdir -p $(BIN_DIR)
	@PRODUCT_PATH=$$(find $(DERIVED_DATA)/SwiftBruja-*/Build/Products/Release -name $(BINARY) -type f 2>/dev/null | head -1); \
	if [ -n "$$PRODUCT_PATH" ]; then \
		cp "$$PRODUCT_PATH" $(BIN_DIR)/; \
		echo "Installed $(BINARY) to $(BIN_DIR)/ (Release with Metal shaders)"; \
	else \
		echo "Error: Could not find $(BINARY) in DerivedData"; \
		exit 1; \
	fi

# Debug build with xcodebuild + copy to bin (default)
install:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' build
	@mkdir -p $(BIN_DIR)
	@PRODUCT_PATH=$$(find $(DERIVED_DATA)/SwiftBruja-*/Build/Products/Debug -name $(BINARY) -type f 2>/dev/null | head -1); \
	if [ -n "$$PRODUCT_PATH" ]; then \
		cp "$$PRODUCT_PATH" $(BIN_DIR)/; \
		echo "Installed $(BINARY) to $(BIN_DIR)/ (Debug with Metal shaders)"; \
	else \
		echo "Error: Could not find $(BINARY) in DerivedData"; \
		exit 1; \
	fi

# Run tests
test:
	swift test

# Clean build artifacts
clean:
	swift package clean
	rm -rf $(BIN_DIR)
	rm -rf $(DERIVED_DATA)/SwiftBruja-*

help:
	@echo "SwiftBruja Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build    - Development build (swift build, no Metal shaders)"
	@echo "  install  - Debug build with xcodebuild + copy to ./bin (default)"
	@echo "  release  - Release build with xcodebuild + copy to ./bin"
	@echo "  test     - Run tests"
	@echo "  clean    - Clean build artifacts"
	@echo "  help     - Show this help"
	@echo ""
	@echo "All builds use: -destination '$(DESTINATION)'"
