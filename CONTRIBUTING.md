# Contributing to Icon Mixer

## Set up

You need a Mac with Apple silicon and Xcode at `/Applications/Xcode.app`.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build
swift test
```

`./scripts/build-app.sh --install` builds the app and copies it to `~/Applications`.

## Project layout

| Path | Contents |
|---|---|
| `Sources/IconMixCore` | Image mixing and finishes, with no UI code. |
| `Sources/IconMixer` | The SwiftUI app. |
| `Tests/IconMixCoreTests` | Unit tests for the mixing code. |
| `Resources` | `Info.plist` and the app icon. |
| `scripts` | Build, installer and app icon scripts. |
| `installer` | The DMG for the current release. |

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <summary>

<optional body explaining what changed and why>
```

Write the summary as a command ("add", not "added"), in lower case, with no full stop. Keep it under about 50 characters.

| Type | Use for | Example |
|---|---|---|
| `feat` | A new feature | `feat: add second image for folders` |
| `fix` | A bug fix | `fix: keep custom icon after Finder refresh` |
| `docs` | Documentation only | `docs: add install steps to README` |
| `test` | Tests only | `test: cover finish on apps with no image` |
| `refactor` | A code change that keeps behaviour the same | `refactor: move finish code out of Mixer` |
| `chore` | Maintenance | `chore: update gitignore` |

Keep each commit to one change.

## Branches and pull requests

Branch from `main`, and name the branch after its type, such as `feat/second-image` or `fix/undo-snapshot`.

In a pull request, say what changed and how you tested it. Add a screenshot if the window looks different.

## Code

- Keep rendering in `IconMixCore` so it can be unit tested. Views should only display state and pass on actions.
- Add or update tests when rendering or settings change.
- Use the values in `Metric` for spacing and sizes, and keep controls in the right column on the same edges.
- Check layout changes with the Adjust panel open and closed, and with a folder and an app.
- Don't call Finder's AppleScript `update` command on a folder. On macOS 26 it deletes the folder's custom icon.

## Privacy

Don't commit personal files, local paths, credentials or screenshots of real folders. Use generated artwork in screenshots.

## Releases

1. Set the version in `Resources/Info.plist`, using `MAJOR.MINOR.PATCH`.
2. Add the changes to `RELEASE_NOTES.md`.
3. Run `swift test`.
4. Run `./scripts/make-installer.sh` to write `installer/Icon Mixer.dmg`.
5. Commit the changes and tag the release, such as `v1.0.0`.
