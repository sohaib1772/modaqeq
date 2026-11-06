import hashlib
import json
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
build_tools = Path.home() / 'AppData/Local/Android/sdk/build-tools/35.0.0'
certificate = '0f8fc1b33fc25b37aed2a2b14a0c9914747f52459d4fb64a4022521fcb6b637a'
results = []
for abi in ('arm64-v8a', 'armeabi-v7a', 'x86_64'):
    apk = root / 'build/app/outputs/flutter-apk' / f'app-{abi}-release.apk'
    signed = subprocess.run([str(build_tools / 'apksigner.bat'), 'verify', '--verbose', '--print-certs', str(apk)], capture_output=True, check=True).stdout.decode('utf-8', errors='replace')
    assert certificate in signed.lower().replace(':', '')
    manifest = subprocess.run([str(build_tools / 'aapt.exe'), 'dump', 'badging', str(apk)], capture_output=True, check=True).stdout.decode('utf-8', errors='replace')
    expected_code = {'armeabi-v7a': 1007, 'arm64-v8a': 2007, 'x86_64': 4007}[abi]
    assert f"versionCode='{expected_code}'" in manifest and "versionName='1.2.0'" in manifest
    assert 'application-debuggable' not in manifest
    with zipfile.ZipFile(apk) as archive:
        lib = archive.read(f'lib/{abi}/libapp.so')
        for marker in ('xl/worksheets/sheet1.xml', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'اختر صيغة المشاركة', 'تفاصيل الحركة: '):
            assert marker.encode('utf-8') in lib or marker.encode('utf-16-le') in lib, (abi, marker)
    results.append(dict(ABI=abi, Version='1.2.0+7', SignatureVerified=True,
                        SameKeyAsPreviousRelease=True, Debuggable=False,
                        ExcelCodeIncluded=True, Bytes=apk.stat().st_size,
                        SHA256=hashlib.sha256(apk.read_bytes()).hexdigest().upper(), File=str(apk)))
(root / 'release-verification.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
verification = dict(Date='2026-11-06', Name='المدقق المحاسبي', Version='1.2.0+7',
    Change='PDF/Excel share chooser; local RTL XLSX export from authorized invoice, statement and inventory print snapshots',
    PDFRendering='Unchanged from 1.1.3', Analyze='No issues found',
    Tests='33 Flutter tests passed; Node print-feedback regression checks passed',
    Excel=json.loads((root / 'validation/xlsx/result.json').read_text(encoding='utf-8')),
    NativeDeviceUI='Not re-tested on device for this update; format chooser widget tests and independent XLSX reader checks passed',
    ServerIntegrity=json.loads((root / 'server-integrity-result.json').read_text(encoding='utf-8-sig')),
    Releases=results)
(root / 'verification.json').write_text(json.dumps(verification, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps(results, indent=2))
