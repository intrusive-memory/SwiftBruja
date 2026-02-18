# SwiftBruja Makefile
# Build and install the bruja CLI with full Metal shader support

SCHEME = bruja
BINARY = bruja
BIN_DIR = ./bin
DIST_DIR = ./dist
DESTINATION = platform=macOS,arch=arm64
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")

.PHONY: all build release install clean test resolve dist help

all: install

# Resolve all SPM package dependencies via xcodebuild
resolve:
	xcodebuild -resolvePackageDependencies -scheme $(SCHEME) -destination '$(DESTINATION)'
	@echo "Package dependencies resolved."

# Debug build with xcodebuild (includes Metal shaders)
build: resolve
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' build

# Release build with xcodebuild + copy to bin
release: resolve
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Release build
	@mkdir -p $(BIN_DIR)
	@PRODUCT_DIR=$$(find $(DERIVED_DATA)/SwiftBruja-*/Build/Products/Release -name $(BINARY) -type f 2>/dev/null | head -1 | xargs dirname); \
	if [ -n "$$PRODUCT_DIR" ]; then \
		cp "$$PRODUCT_DIR/$(BINARY)" $(BIN_DIR)/; \
		if [ -d "$$PRODUCT_DIR/mlx-swift_Cmlx.bundle" ]; then \
			rm -rf $(BIN_DIR)/mlx-swift_Cmlx.bundle; \
			cp -R "$$PRODUCT_DIR/mlx-swift_Cmlx.bundle" $(BIN_DIR)/; \
			echo "Installed $(BINARY) + Metal bundle to $(BIN_DIR)/ (Release)"; \
		else \
			echo "Warning: Metal bundle not found, binary may not work"; \
			echo "Installed $(BINARY) to $(BIN_DIR)/ (Release, no Metal bundle)"; \
		fi; \
	else \
		echo "Error: Could not find $(BINARY) in DerivedData"; \
		exit 1; \
	fi

# Create distributable tarball (release build + package)
dist: release
	@mkdir -p $(DIST_DIR)
	@# Verify binary and Metal bundle
	@test -f $(BIN_DIR)/$(BINARY) || { echo "Error: binary not found in $(BIN_DIR)"; exit 1; }
	@test -d $(BIN_DIR)/mlx-swift_Cmlx.bundle || { echo "Error: Metal bundle not found in $(BIN_DIR)"; exit 1; }
	@test -f $(BIN_DIR)/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib || { echo "Error: metallib not found"; exit 1; }
	@# Package tarball
	@cd $(BIN_DIR) && tar -czvf ../$(DIST_DIR)/bruja-$(VERSION)-arm64-macos.tar.gz $(BINARY) mlx-swift_Cmlx.bundle
	@SHA256=$$(shasum -a 256 $(DIST_DIR)/bruja-$(VERSION)-arm64-macos.tar.gz | cut -d' ' -f1); \
	echo ""; \
	echo "=== Distribution Package ==="; \
	echo "Tarball: $(DIST_DIR)/bruja-$(VERSION)-arm64-macos.tar.gz"; \
	echo "SHA256:  $$SHA256"; \
	ls -lh $(DIST_DIR)/bruja-$(VERSION)-arm64-macos.tar.gz

# Debug build with xcodebuild + copy to bin (default)
install: resolve
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' build
	@mkdir -p $(BIN_DIR)
	@PRODUCT_DIR=$$(find $(DERIVED_DATA)/SwiftBruja-*/Build/Products/Debug -name $(BINARY) -type f 2>/dev/null | head -1 | xargs dirname); \
	if [ -n "$$PRODUCT_DIR" ]; then \
		cp "$$PRODUCT_DIR/$(BINARY)" $(BIN_DIR)/; \
		if [ -d "$$PRODUCT_DIR/mlx-swift_Cmlx.bundle" ]; then \
			rm -rf $(BIN_DIR)/mlx-swift_Cmlx.bundle; \
			cp -R "$$PRODUCT_DIR/mlx-swift_Cmlx.bundle" $(BIN_DIR)/; \
			echo "Installed $(BINARY) + Metal bundle to $(BIN_DIR)/ (Debug)"; \
		else \
			echo "Warning: Metal bundle not found, binary may not work"; \
			echo "Installed $(BINARY) to $(BIN_DIR)/ (Debug, no Metal bundle)"; \
		fi; \
	else \
		echo "Error: Could not find $(BINARY) in DerivedData"; \
		exit 1; \
	fi

# Run tests
test: resolve
	xcodebuild test -scheme SwiftBruja-Package -destination '$(DESTINATION)'

# Clean build artifacts
clean:
	xcodebuild clean -scheme $(SCHEME) -destination '$(DESTINATION)' 2>/dev/null || true
	rm -rf $(BIN_DIR)
	rm -rf $(DIST_DIR)
	rm -rf $(DERIVED_DATA)/SwiftBruja-*

help:
	@echo "SwiftBruja Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  resolve  - Resolve all SPM package dependencies"
	@echo "  build    - Debug build with xcodebuild (includes Metal shaders)"
	@echo "  install  - Debug build with xcodebuild + copy to ./bin (default)"
	@echo "  release  - Release build with xcodebuild + copy to ./bin"
	@echo "  dist     - Release build + create distributable tarball in ./dist"
	@echo "  test     - Run tests with xcodebuild"
	@echo "  clean    - Clean build artifacts"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Version: $(VERSION)"
	@echo "All builds use: -destination '$(DESTINATION)'"
