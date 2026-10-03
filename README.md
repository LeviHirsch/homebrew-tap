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
