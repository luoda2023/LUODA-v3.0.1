# -*- coding: utf-8 -*-
import subprocess, time
ADB=r"D:\Program Files\LDPlayer14\adb.exe"
SERIAL="7358bbbb"
APK=r"J:\codex-work\LUODA-v3.0.1\flutter\build\app\outputs\flutter-apk\app-release.apk"
def sh(args, t=60):
    try:
        r=subprocess.run([ADB,"-s",SERIAL]+args, capture_output=True, text=True, timeout=t)
        return (r.stdout+r.stderr).strip()
    except Exception as e:
        return f"ERR {e}"
# 1. kill ldai
print("kill ldai:", sh(["shell","am","force-stop","com.ldai.mobile"]))
time.sleep(0.5)
# 2. start install streamed in background thread
p = subprocess.Popen([ADB,"-s",SERIAL,"install","-r","--streaming",APK],
                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
# 3. poll for packageinstaller dialog and tap confirm button (green) repeatedly
start=time.time()
last_focus=""
while time.time()-start < 150:
    foc = sh(["shell","dumpsys","window","|","grep","mCurrentFocus"], t=10)
    if "packageinstaller" in foc:
        # dialog visible - find & tap install button
        sh(["shell","uiautomator","dump","/sdcard/i.xml"], t=10)
        xml = sh(["shell","cat","/sdcard/i.xml"], t=10)
        import re
        m = re.search(r'text="安装"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
        if m:
            x=(int(m.group(1))+int(m.group(3)))//2
            y=(int(m.group(2))+int(m.group(4)))//2
            print("tap install at", x, y)
            sh(["shell","input","tap",str(x),str(y)], t=10)
            time.sleep(6)
            break
        else:
            # fallback green button center
            print("dialog visible, no text match, tap 540,2220")
            sh(["shell","input","tap","540","2220"], t=10)
            time.sleep(6)
            break
    if "ldai" in foc and foc!=last_focus:
        print("ldai stole focus, re-kill")
        sh(["shell","am","force-stop","com.ldai.mobile"], t=10)
        last_focus=foc
    time.sleep(1.5)
out = p.communicate(timeout=60)[0]
print("INSTALL RESULT:", out[-300:] if out else "(no output)")
