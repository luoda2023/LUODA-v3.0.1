#!/usr/bin/env python3
"""
Release uploader for LUODA v3.1.1 CI builds.
Usage: python3 upload_release.py

Downloads artifacts from the latest successful CI builds (branch: 3.1.1),
uploads them to GitHub Release v3.1.1, and removes the old assets.
"""

import json, os, subprocess, sys, time
from pathlib import Path

GH = ["gh", "-R", "luoda2023/LUODA-v3.0.1"]
TAG = "v3.1.1"
BRANCH = "3.1.1"

# Map CI workflow name → artifact name → release asset name
BUILDS = {
    "Build LDesk Windows EXE": { "artifact": "luoda-windows-exe", "asset": "LDesk-3.1.1-Setup-x64.exe" },
    "Build LDesk Windows MSI": { "artifact": "luoda-windows-msi", "asset": "LDesk-3.1.1-Setup-en-us.msi" },
    "Build LDesk Client EXE": { "artifact": "luoda-client-exe", "asset": "LDesk-3.1.1-Client-x64.exe" },
    "Build LDesk Linux DEB": { "artifact": "luoda-linux-deb", "asset": "LDesk-3.1.1.deb" },
    "Build LDesk macOS DMG": { "artifact": "luoda-macos-dmg", "asset": "LDesk-3.1.1.dmg" },
    "Build LDesk Android APK": { "artifact": "luoda-android-apk", "asset": "LDesk-3.1.1-universal.apk" },
    "Build LDesk iOS IPA": { "artifact": "luoda-ios-ipa", "asset": "LDesk-3.1.1-unsigned.ipa" },
}

def run(*args):
    return subprocess.check_output([*GH, *args], text=True).strip()

def run_json(*args):
    return json.loads(run(*args))

def latest_successful_run(name):
    """Find the latest completed successful run for a workflow."""
    runs = run_json("run", "list", "-s", "success", "-L", "5",
                     "--json", "databaseId,name,headBranch",
                     "-b", BRANCH)
    for r in runs:
        if r["name"] == name:
            return r["databaseId"]
    return None

def download_artifact(run_id, artifact_name, out_dir):
    """Download a specific artifact from a CI run."""
    try:
        subprocess.check_call(
            [*GH, "run", "download", str(run_id),
             "-n", artifact_name, "--dir", out_dir],
            timeout=300)
        return True
    except Exception as e:
        print(f"  Download failed: {e}")
        return False

def main():
    download_dir = Path("release_downloads")
    upload_dir = Path("release_upload")
    download_dir.mkdir(exist_ok=True)
    upload_dir.mkdir(exist_ok=True)

    print("=== Fetching latest CI artifacts ===")
    downloaded = []
    for name, cfg in BUILDS.items():
        print(f"\n--- {name} ---")
        run_id = latest_successful_run(name)
        if not run_id:
            print(f"  No successful build found. Skipping.")
            continue
        print(f"  Run ID: {run_id}")
        
        # Check if artifact is available
        out = download_dir / cfg["artifact"]
        if download_artifact(run_id, cfg["artifact"], str(out)):
            # Find the downloaded file(s)
            files = list(out.rglob("*"))
            exe_files = [f for f in files if f.is_file()]
            if exe_files:
                src = exe_files[0]
                dst = upload_dir / cfg["asset"]
                import shutil
                shutil.copy2(src, dst)
                print(f"  Copied: {dst.name} ({dst.stat().st_size / 1024 / 1024:.1f} MB)")
                downloaded.append(dst.name)

    if not downloaded:
        print("\n⚠️  No artifacts downloaded. CI builds may still be running.")
        sys.exit(1)

    print(f"\n=== Downloaded {len(downloaded)} artifacts ===")
    for f in downloaded:
        size = (upload_dir / f).stat().st_size
        print(f"  {f} ({size / 1024 / 1024:.1f} MB)")

    # Get current release info
    print(f"\n=== Updating Release {TAG} ===")
    current = run_json("release", "view", TAG, "--json", "assets")
    existing = [a["name"] for a in current["assets"]]
    
    # Delete old assets
    for asset_name in existing:
        if asset_name in downloaded:
            print(f"  Keeping: {asset_name}")
        else:
            print(f"  Deleting old: {asset_name}")
            run("release", "delete-asset", TAG, asset_name)
            time.sleep(0.5)

    # Upload new assets
    for f in sorted(downloaded):
        path = upload_dir / f
        print(f"  Uploading: {f}")
        run("release", "upload", TAG, str(path), "--clobber")
        time.sleep(0.5)

    print("\n✅ Release updated successfully!")
    print(f"   {len(downloaded)} assets uploaded to {TAG}")

if __name__ == "__main__":
    main()
