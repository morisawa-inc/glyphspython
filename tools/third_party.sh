#!/bin/sh

PROJECT_ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

(cd "${PROJECT_ROOT_DIR}" && git subtree pull --prefix glyphspython/mach_override https://github.com/rentzsch/mach_override.git semver-1.x --squash)

(cd "${PROJECT_ROOT_DIR}/glyphspython/mach_override" && curl -L -O https://github.com/chromium/chromium/raw/77.0.3835.1/third_party/mach_override/BUILD.gn)
(cd "${PROJECT_ROOT_DIR}/glyphspython/mach_override" && curl -L -O https://github.com/chromium/chromium/raw/77.0.3835.1/third_party/mach_override/LICENSE)
(cd "${PROJECT_ROOT_DIR}/glyphspython/mach_override" && curl -L -O https://github.com/chromium/chromium/raw/77.0.3835.1/third_party/mach_override/OWNERS)
(cd "${PROJECT_ROOT_DIR}/glyphspython/mach_override" && curl -L -O https://github.com/chromium/chromium/raw/77.0.3835.1/third_party/mach_override/README.chromium)
(cd "${PROJECT_ROOT_DIR}/glyphspython/mach_override" && curl -L -O https://github.com/chromium/chromium/raw/77.0.3835.1/third_party/mach_override/chromium.patch)
(cd "${PROJECT_ROOT_DIR}/glyphspython/mach_override" && patch < chromium.patch)
