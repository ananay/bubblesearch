#!/usr/bin/env python3

import argparse
import html
import re
import subprocess
from pathlib import Path


VERSION_PATTERN = re.compile(r"^[0-9]+(?:\.[0-9]+){2}(?:[-+][0-9A-Za-z.-]+)?$")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate an HTML release-notes sidecar for Sparkle."
    )
    parser.add_argument("--version", required=True, help="Release version, such as 1.0.6")
    parser.add_argument(
        "--commit",
        default="HEAD",
        help="Commit whose message is used by default (default: HEAD)",
    )
    parser.add_argument(
        "--notes-file",
        type=Path,
        help="Plain-text notes that replace the commit message",
    )
    parser.add_argument(
        "--append-file",
        type=Path,
        help="Plain-text notes appended after the primary notes",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("build"),
        help="Directory for BubbleSearch-VERSION.html (default: build)",
    )
    return parser.parse_args()


def commit_message(commit: str) -> str:
    result = subprocess.run(
        ["git", "show", "-s", "--format=%B", commit],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def read_notes(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip()


def html_fragment(sections: list[str]) -> str:
    rendered_paragraphs: list[str] = []

    for section in sections:
        for paragraph in re.split(r"\n\s*\n", section.strip()):
            lines = [html.escape(line.strip()) for line in paragraph.splitlines()]
            rendered_paragraphs.append("<p>" + "<br>\n".join(lines) + "</p>")

    return "\n".join(rendered_paragraphs) + "\n"


def main() -> None:
    arguments = parse_arguments()

    if not VERSION_PATTERN.fullmatch(arguments.version):
        raise SystemExit(
            "version must be semantic, for example 1.0.6 or 1.0.6-beta.1"
        )

    primary_notes = (
        read_notes(arguments.notes_file)
        if arguments.notes_file is not None
        else commit_message(arguments.commit)
    )
    if not primary_notes:
        raise SystemExit("release notes cannot be empty")

    sections = [primary_notes]
    if arguments.append_file is not None:
        additional_notes = read_notes(arguments.append_file)
        if additional_notes:
            sections.append(additional_notes)

    arguments.output_dir.mkdir(parents=True, exist_ok=True)
    output_path = arguments.output_dir / f"BubbleSearch-{arguments.version}.html"
    output_path.write_text(html_fragment(sections), encoding="utf-8")
    print(output_path)


if __name__ == "__main__":
    main()
