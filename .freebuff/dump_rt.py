import sys, subprocess, json, re
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
def win(p):
    return subprocess.run(['cygpath','-w',p], capture_output=True, text=True).stdout.strip()
ADB = win('/j/codex-work/.toolchains/android-sdk/platform-tools/adb.exe')
r = subprocess.run([ADB, '-s', 'emulator-5556', 'logcat', '-d'], capture_output=True)
txt = r.stdout.decode(errors='replace')
m = re.findall(r'127\.0\.0\.1:(\d+)/([A-Za-z0-9_\-=]+)/', txt)
print('found:', m[-3:])
if not m:
    print('no vm service'); sys.exit(1)
port, tok = m[-1]
subprocess.run([ADB, '-s', 'emulator-5556', 'forward', f'tcp:{port}', f'tcp:{port}'], capture_output=True)
import urllib.request
def call(url):
    with urllib.request.urlopen(url, timeout=20) as r2:
        return json.load(r2)
vm = call(f'http://127.0.0.1:{port}/{tok}/getVM')
iso = vm['result']['isolates'][0]['id']
print('isolate:', iso)
rt = call(f'http://127.0.0.1:{port}/{tok}/ext.flutter.debugDumpRenderTree?isolateId={iso}')
txt = rt['result']['data']
lines = txt.split('\n')
for i, l in enumerate(lines):
    if 'fffff0d6' in l.lower():
        print(f'--- 胶囊 at line {i} ---')
        print('\n'.join(lines[max(0,i-4):i+45]))
        break
else:
    print('未找到胶囊颜色')
