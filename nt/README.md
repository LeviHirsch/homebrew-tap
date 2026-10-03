# nt client kit

One-line setup for logging in to the NascenTech server.

## Install (once)

**Mac / Linux** (Terminal):

```sh
curl -fsSL https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/nt/install.sh | bash
```

**Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/nt/install.ps1 | iex
```

It asks your first name, then prints a line starting `ssh-ed25519`. Text that whole line to Levi.

## Log in (daily)

When Levi says you're registered, open a new terminal and type:

```sh
nt
```

The first time (and about once a week after), a browser opens: sign in with your @nascentech.com Google account.

## What the installer changes

| | Mac / Linux | Windows |
|---|---|---|
| cloudflared (skipped if already installed) | `~/.nt/bin/cloudflared` | `%LOCALAPPDATA%\nt\bin\cloudflared.exe` |
| `nt` command | `~/.nt/bin/nt` | `%LOCALAPPDATA%\nt\bin\nt.cmd` |
| SSH key (no passphrase) | `~/.ssh/id_ed25519_nt` (+ `.pub`) | `%USERPROFILE%\.ssh\id_ed25519_nt` (+ `.pub`) |
| `Host nt` entry | `~/.ssh/config.d/nt` | `%USERPROFILE%\.ssh\config.d\nt` |
| One line added at the top of the SSH config | `Include ~/.ssh/config.d/*` in `~/.ssh/config` | same, in `%USERPROFILE%\.ssh\config` |
| PATH | one line marked `# added by nt installer` in `~/.zshrc` / `~/.bashrc` / `~/.bash_profile` or `~/.profile` | `%LOCALAPPDATA%\nt\bin` added to your user PATH |

Your SSH config is backed up first (`config.nt-backup-<date>`). Running the installer again is safe. If you already have a `Host nt` entry, it stops and changes nothing.

## Undo

Mac / Linux:

```sh
rm -rf ~/.nt ~/.ssh/config.d/nt ~/.ssh/id_ed25519_nt ~/.ssh/id_ed25519_nt.pub
```

Then delete the `Include ~/.ssh/config.d/*` line from `~/.ssh/config` (if nothing else uses it) and the `# added by nt installer` line from your shell files.

Windows: delete `%LOCALAPPDATA%\nt`, `.ssh\config.d\nt`, `.ssh\id_ed25519_nt*`, the `Include` line in `.ssh\config`, and remove `%LOCALAPPDATA%\nt\bin` from your user PATH (Settings → "Edit environment variables for your account").

## For Levi: register / remove

```sh
nt-register <name> "<the ssh-ed25519 line they texted>"
nt-register --remove <name>
nt-register --dry-run ...          # show what would change, connect to nothing
```

`<name>` is lowercase (`ana`, `ben-k`). It's what `clv whoami` will show. Each change backs up the mini's `authorized_keys` first. Test against a local file with `NT_REGISTER_AUTHKEYS_FILE=/tmp/ak nt-register ...`.
