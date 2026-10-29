"""Build Orbit Open.app from the Swift package."""

import argparse
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


PACKAGE = Path(__file__).resolve().parent
PROJECT = PACKAGE.parents[2]
OUTPUT = PROJECT / "04_Lavorazione" / "Orbit Open.app"
INSTALL = Path.home() / "Applications" / "Orbit Open.app"
LAUNCH_SERVICES = Path(
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
    "LaunchServices.framework/Support/lsregister"
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build Orbit Open.app")
    parser.add_argument("--install", action="store_true", help="Installa in ~/Applications")
    args = parser.parse_args()
    subprocess.run(["swift", "build", "-c", "release"], cwd=PACKAGE, check=True)
    bin_path = subprocess.run(
        ["swift", "build", "-c", "release", "--show-bin-path"],
        cwd=PACKAGE, capture_output=True, text=True, check=True,
    ).stdout.strip()
    source = Path(bin_path) / "OrbitApp"
    if not source.is_file():
        raise SystemExit("Eseguibile OrbitApp non trovato dopo la build")

    executable_dir = OUTPUT / "Contents" / "MacOS"
    executable_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, executable_dir / "OrbitApp")
    resources_dir = OUTPUT / "Contents" / "Resources"
    resources_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PACKAGE / "Resources" / "OpenAI.png", resources_dir / "OpenAI.png")
    icon_png = PACKAGE / "Resources" / "OrbitAppIcon.png"
    shutil.copy2(icon_png, resources_dir / "OrbitAppIcon.png")
    with tempfile.TemporaryDirectory() as temporary:
        iconset = Path(temporary) / "Orbit.iconset"
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                pixels = points * scale
                destination = iconset / f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
                subprocess.run(["sips", "-z", str(pixels), str(pixels), str(icon_png),
                                "--out", str(destination)], check=True, capture_output=True)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o",
                        str(resources_dir / "Orbit.icns")], check=True)
    installed_info = OUTPUT / "Contents" / "Info.plist"
    previous_version = 0
    if installed_info.exists():
        previous_version = int(plistlib.loads(installed_info.read_bytes()).get("CFBundleVersion", "0"))
    info = {
        "CFBundleDevelopmentRegion": "it",
        "CFBundleExecutable": "OrbitApp",
        "CFBundleIdentifier": "com.orbit.open",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "Orbit Open",
        "CFBundleIconFile": "Orbit.icns",
        "CFBundleDisplayName": "Orbit Open",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": str(previous_version + 1),
        "LSMinimumSystemVersion": "15.0",
        "NSHighResolutionCapable": True,
        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
    }
    (OUTPUT / "Contents" / "Info.plist").write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign", "--force", "--sign", "-", str(OUTPUT)], check=True)
    if args.install:
        INSTALL.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(OUTPUT, INSTALL, dirs_exist_ok=True)
        subprocess.run(["codesign", "--verify", str(INSTALL)], check=True)
        INSTALL.touch()
        subprocess.run([str(LAUNCH_SERVICES), "-f", str(INSTALL)], check=True)
        print(INSTALL)
    else:
        print(OUTPUT)


if __name__ == "__main__":
    main()
