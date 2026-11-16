#!/usr/bin/env bash
# Build the untouched Linux counter template in the existing Ubuntu builder.
set -euo pipefail
printf '%s  %s\n' \
  6ea2d806fd57269ae783e6788e2a81fc26eaad782f1e0d0ff38623bb765ff9f5 \
  /inputs/flutter.tar.xz | sha256sum --check
tar -xJf /inputs/flutter.tar.xz -C /opt
chown -R builder:builder /opt/flutter /home/builder /output
runuser -u builder -- bash <<'BUILD'
set -euo pipefail
export PUB_CACHE=/home/builder/pub-cache
flutter config --no-analytics
flutter --version --machine > /output/flutter-version.json
flutter create --platforms=linux --project-name=shutdown_template /home/builder/shutdown_template
cd /home/builder/shutdown_template
sha256sum lib/main.dart linux/runner/* pubspec.yaml > /output/template-before-build.sha256
flutter build linux --release
sha256sum --check /output/template-before-build.sha256
flutter analyze
flutter test
cp /output/template-before-build.sha256 /output/template-source.sha256
sha256sum pubspec.lock >> /output/template-source.sha256
tar --exclude=./build --exclude=./.dart_tool --exclude=./.git \
  --exclude=./linux/flutter/ephemeral -czf /output/template-source.tar.gz .
tar -czf /output/template-bundle.tar.gz -C build/linux/x64/release/bundle .
python3 - <<'PY'
import hashlib
import json
from pathlib import Path

root = Path('build/linux/x64/release/bundle')
version = json.loads(Path('/output/flutter-version.json').read_text())
assert version['frameworkRevision'] == 'ab2912035e160d9cad6306df307576da6128ebdb'
assert version['engineRevision'] == '371f77202a73e8dff57a8b3bff75bca55c090aee'
files = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
         for p in sorted(root.rglob('*')) if p.is_file()}
assert files['lib/libflutter_linux_gtk.so'] == 'cb40d5867033badfa1a38072fab83f1c60ec1520c303a4810f49979f0ba5df04'
Path('/output/template-manifest.json').write_text(json.dumps({
    'flutter': version,
    'sdk_archive_sha256': '6ea2d806fd57269ae783e6788e2a81fc26eaad782f1e0d0ff38623bb765ff9f5',
    'command': 'flutter create --platforms=linux --project-name=shutdown_template /home/builder/shutdown_template; flutter build linux --release',
    'template_modified': False,
    'release_qualification': False,
    'bundle': files,
}, indent=2) + '\n')
PY
cd /output
sha256sum template-bundle.tar.gz template-source.tar.gz template-manifest.json \
  flutter-version.json template-source.sha256 > SHA256SUMS
BUILD
