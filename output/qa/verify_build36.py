"""Verify and export the APK containing the receiving article scanner."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parents[2]
source = root / 'frontend/build/app/outputs/flutter-apk/app-release.apk'
target = root / 'output/Pixorex-v1.0.5-build36.apk'
tools = Path('/home/suchithgoud/develop/android-sdk/build-tools/35.0.0')
env = os.environ.copy()
env['JAVA_HOME'] = '/home/suchithgoud/develop/jdk/jdk-17.0.20.1+1'
env['PATH'] = env['JAVA_HOME'] + '/bin:' + env.get('PATH', '')

badging = subprocess.run([str(tools / 'aapt'), 'dump', 'badging', str(source)], capture_output=True, text=True, check=True).stdout
package_line = next(line for line in badging.splitlines() if line.startswith('package:'))
package = dict(re.findall(r"(\w+)='([^']*)'", package_line))
assert package['name'] == 'com.amzur.equiptrack', package
assert package['versionCode'] == '36' and package['versionName'] == '1.0.5', package
assert "application-label:'Pixorex'" in badging

with zipfile.ZipFile(source) as archive:
    assert archive.testzip() is None, 'Corrupt APK'
    arm64 = archive.read('lib/arm64-v8a/libapp.so')
    dex = b''.join(archive.read(name) for name in archive.namelist() if re.fullmatch(r'classes\d*\.dex', name))
    checks = {
        'scanner_button_in_flutter_binary': b'Scan can article number' in arm64,
        'accept_can_button_in_flutter_binary': b'Add this can (+1)' in arm64,
        'native_camera_ocr_channel_in_dex': b'com.amzur.equiptrack/ppg_can_ocr' in dex,
        'native_frame_handler_in_dex': b'recognizeFrame' in dex,
    }
    assert all(checks.values()), checks

def certificate(apk):
    output = subprocess.run([str(tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], env=env, capture_output=True, text=True, check=True).stdout
    return re.search(r'Signer #1 certificate SHA-256 digest: (\S+)', output).group(1)

assert certificate(source) == certificate(root / 'output/Pixorex-v1.0.4-build35.apk'), 'Upgrade signing certificate changed'
assert '+71: All tests passed!' in (root / 'output/qa/flutter-build36-tests.log').read_text()
assert 'No issues found!' in (root / 'output/qa/flutter-build36-analysis.log').read_text()

shutil.copy2(source, target)
checksum = hashlib.sha256(target.read_bytes()).hexdigest()
target.with_suffix('.apk.sha256').write_text(checksum + '  ' + target.name + '\n')
metadata = {
    'apk': str(target), 'package': package['name'], 'version': '1.0.5', 'build_number': 36,
    'size_bytes': target.stat().st_size, 'sha256': checksum,
    'archive_verified': True, 'signature_verified': True,
    'upgrade_signing_matches_build35': True, 'signing': 'Existing demo/review debug keystore',
    'tests_passed': 71, 'static_analysis': 'No issues found',
    'included': ['Receiving scanner icon and button', 'Live on-device article OCR',
                 'Three-frame article confirmation', 'Exact current-DN article match',
                 'Explicit one-can acceptance', 'Atomic count/audit save and retry deduplication'],
    'embedded_feature_checks': checks,
    'physical_camera_tested': False,
    'device_test_limit': 'No connected Android device; physical can accuracy remains to be measured',
}
target.with_suffix('.apk.build.json').write_text(json.dumps(metadata, indent=2) + '\n')
print(json.dumps(metadata, indent=2))
