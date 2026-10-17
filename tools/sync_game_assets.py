"""Copies the game data in resources/game into the app and registers it.

resources/game/heroes.json and resources/game/icons/ come from unpacking the installed
game (see docs/game-data.md). The app bundles a copy under app/assets/game/. Flutter does
not recurse into asset folders, so every folder that holds files is listed in
app/pubspec.yaml; this script rewrites that list.

Run from the repository root:  python tools/sync_game_assets.py
"""
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "resources", "game")
APP = os.path.join(ROOT, "app")
DST = os.path.join(APP, "assets", "game")


def main() -> int:
    if not os.path.isfile(os.path.join(SRC, "heroes.json")):
        print("resources/game/heroes.json not found", file=sys.stderr)
        return 1
    if os.path.exists(DST):
        shutil.rmtree(DST)
    os.makedirs(DST)
    shutil.copy(os.path.join(SRC, "heroes.json"), os.path.join(DST, "heroes.json"))
    shutil.copytree(os.path.join(SRC, "icons", "heroes"), os.path.join(DST, "icons", "heroes"))

    dirs = sorted(
        os.path.relpath(r, APP).replace("\\", "/") + "/"
        for r, _, files in os.walk(os.path.join(DST, "icons", "heroes"))
        if files
    )
    pubspec = os.path.join(APP, "pubspec.yaml")
    with open(pubspec, encoding="utf-8") as f:
        text = f.read()
    text = re.sub(r"\n    - assets/game/[^\n]*", "", text)
    lines = "\n    - assets/game/heroes.json" + "".join("\n    - " + d for d in dirs)
    anchor = "    - assets/levels/"
    if anchor not in text:
        print("pubspec.yaml has no assets/levels/ entry to attach to", file=sys.stderr)
        return 1
    text = text.replace(anchor, anchor + lines, 1)
    with open(pubspec, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"copied; {len(dirs)} asset folders registered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
