"""Keep a Desktop shortcut to the verified installer without copying it."""
from pathlib import Path
import os
import sys


def create_shortcut(package: Path, desktop: Path) -> bool:
    package = package.resolve()
    shortcut = desktop / package.name
    try:
        if not package.is_file():
            raise FileNotFoundError(f"Installer is missing: {package}")
        if shortcut.is_symlink():
            target = Path(os.readlink(shortcut))
            if not target.is_absolute():
                target = shortcut.parent / target
            if target.resolve() == package:
                print(f"Desktop shortcut ready: {shortcut}")
                return True
        shortcut.symlink_to(package)
    except FileExistsError:
        try:
            target = Path(os.readlink(shortcut))
            if not target.is_absolute():
                target = shortcut.parent / target
            if target.resolve() == package:
                print(f"Desktop shortcut ready: {shortcut}")
                return True
        except OSError:
            pass
        print(f"Warning: Desktop shortcut was not changed; an unrelated item already exists at {shortcut}.", file=sys.stderr)
        return False
    except OSError as error:
        print(f"Warning: Could not create Desktop shortcut: {error}. The installer is available at {package}.", file=sys.stderr)
        return False
    print(f"Desktop shortcut ready: {shortcut}")
    return True


if __name__ == "__main__":
    create_shortcut(Path(sys.argv[1]), Path.home() / "Desktop")
