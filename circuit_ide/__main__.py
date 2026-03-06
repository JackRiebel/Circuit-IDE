"""
Entry point for Circuit IDE.

Usage:
    python -m circuit_ide [project_directory]
    circuit-ide [project_directory]
"""

import argparse
import os
import sys


def main():
    """Main entry point for Circuit IDE."""
    parser = argparse.ArgumentParser(
        prog="circuit-ide", description="Circuit IDE v5.0 - AI-powered Terminal IDE"
    )
    parser.add_argument(
        "directory",
        nargs="?",
        default=".",
        help="Project directory to open (default: current directory)",
    )
    parser.add_argument("-v", "--version", action="store_true", help="Show version and exit")
    parser.add_argument(
        "--theme", choices=["dark", "light"], default="dark", help="Color theme (default: dark)"
    )

    args = parser.parse_args()

    if args.version:
        from . import __version__

        print(f"Circuit IDE v{__version__}")
        sys.exit(0)

    # Resolve project directory
    project_dir = os.path.abspath(args.directory)
    if not os.path.isdir(project_dir):
        print(f"Error: '{args.directory}' is not a valid directory")
        sys.exit(1)

    # Launch the IDE
    from .app import CircuitIDE

    app = CircuitIDE(project_dir=project_dir, theme=args.theme)
    app.run()


if __name__ == "__main__":
    main()
