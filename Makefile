.PHONY: all
all:
	xcodebuild
	command -v postbuild-codesign >/dev/null 2>&1 && postbuild-codesign
	command -v postbuild-notarize >/dev/null 2>&1 && AC_BUNDLE_ID=jp.co.morisawa.glyphspython postbuild-notarize

.PHONY: clean
clean:
	rm -rf build
	rm -rf *.app

archive: clean plugin
	CURRENT_DIR=$$(pwd); \
	PROJECT_NAME=$$(basename "$${CURRENT_DIR}"); \
	git archive -o "build/Release/$${PROJECT_NAME}-$$(git rev-parse --short HEAD).zip" HEAD

dist: clean all archive
