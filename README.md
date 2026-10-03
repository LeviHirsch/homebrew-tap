# LeviHirsch/tap

Personal Homebrew tap for apps and tools.

## What's here

| Tool | What it is | How to install |
| --- | --- | --- |
| **mark-this-down** | Native macOS markdown editor. [Source](https://github.com/LeviHirsch/mark-this-down). | Homebrew cask (below) |
| **clv client kit** | One-line setup for logging in to the NascenTech server. | Install script, see [`clv/README.md`](clv/README.md) |

## mark-this-down

```sh
brew tap LeviHirsch/tap
brew install --cask mark-this-down
```

To upgrade later:
```sh
brew upgrade --cask mark-this-down
```

## clv client kit

Not a Homebrew package (yet): it installs with one line and needs no Homebrew.

```sh
curl -fsSL https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/clv/install.sh | bash
```

Windows, and everything else: [`clv/README.md`](clv/README.md).

## Adding a tool

Homebrew casks and formulas live in `Casks/` and `Formula/` as usual.

A tool that installs with a script gets one folder, named after the tool. `clv/` is the model:

| File | What it is |
| --- | --- |
| `<tool>/install.sh` | Mac / Linux installer |
| `<tool>/install.ps1` | Windows installer |
| `<tool>/README.md` | The one-liners, what it changes on the machine, how to undo it |
| anything else | Optional admin helpers, beside them (like `clv/nt-register`) |

The one-liner always has the same shape:

```sh
curl -fsSL https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/<tool>/install.sh | bash
```

Rules every installer follows:

- No sudo (no admin rights on Windows).
- Safe to run again: a second run changes nothing.
- Backs up a user file before editing it.
- Stops, rather than overwriting, when it finds something it didn't install.
- No secrets: this repo is public.
- Plain-English output, and a plain sentence when something goes wrong.
