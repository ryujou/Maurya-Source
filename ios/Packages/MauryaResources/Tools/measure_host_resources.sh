#!/usr/bin/env bash
set -euo pipefail

package_directory="$(cd "$(dirname "$0")/.." && pwd)"
developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

export DEVELOPER_DIR="$developer_directory"
echo "MAURYA_RESOURCE_MEASUREMENT architecture=$(uname -m)"
echo "The following time(1) maximum resident set size covers the complete test runner, not only a decode."
/usr/bin/time -l swift test \
  --package-path "$package_directory" \
  -c release \
  --filter ResourceMeasurementTests \
  -Xswiftc -warnings-as-errors
