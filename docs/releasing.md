# Publishing release notes

BubbleSearch displays the newest Sparkle appcast item's `<description>` in the title-bar update popover. Release notes are prepared as a small HTML sidecar whose base name matches the update archive:

```text
BubbleSearch-1.0.6.zip
BubbleSearch-1.0.6.html
```

Sparkle's `generate_appcast` finds that matching file and embeds it in the appcast. The HTML generator escapes special characters, so commit messages and custom text cannot accidentally break the feed.

## Prepare notes with GitHub Actions

1. Open **Actions → Prepare Sparkle release notes → Run workflow**.
2. Select the commit being released. Leave **version** empty to use `native/VERSION`; a supplied version must match that file.
3. Leave both notes fields empty to use that commit's complete message (subject and body).
4. Optionally set **release_notes** to replace the commit message.
5. Optionally set **additional_release_notes** to add text after the commit message or replacement text.
6. Download the `BubbleSearch-VERSION-release-notes` artifact from the completed run.

Anyone with permission to run repository workflows can prepare the artifact. Contributors without that permission can generate the same file locally and include their proposed wording in a pull request or hand it to a maintainer.

## Prepare or customize notes locally

The default command uses the latest commit message:

```sh
cd native
RELEASE_VERSION=$(scripts/read-version.sh)
python3 scripts/generate-release-notes.py --version "$RELEASE_VERSION" --commit HEAD
```

To replace it, put any plain text in a file:

```sh
python3 scripts/generate-release-notes.py \
  --version "$RELEASE_VERSION" \
  --notes-file /path/to/release-notes.txt
```

To keep the commit message and add a separate paragraph:

```sh
python3 scripts/generate-release-notes.py \
  --version "$RELEASE_VERSION" \
  --commit HEAD \
  --append-file /path/to/additional-notes.txt
```

Use `--notes-file` and `--append-file` together to replace the default and then append more text. Blank lines start new paragraphs; single line breaks remain line breaks.

## Bump the app version

`native/VERSION` is the single source of truth for the app bundle, DMG name, and release-notes workflow. Update that file in the release commit. The packaging scripts validate command-line or environment overrides, and CI verifies that both packaged bundle-version keys match the file.

## Publish through Sparkle

Place the generated `BubbleSearch-VERSION.html` beside the matching ZIP before running Sparkle's tool:

```sh
path/to/generate_appcast --embed-release-notes path/to/update-directory
```

Publish the generated `appcast.xml` and update archive using the existing release host. Verify that the newest `<item>` contains a `<description>` and that its enclosure signature is present before making the feed live.

Do not hand-edit an already generated or signed feed. Change the text source and run `generate_appcast` again so Sparkle can regenerate the appcast and any configured signatures consistently.
