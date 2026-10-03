# clv client kit

One-line setup for logging in to the NascenTech server.

## Install (once)

**Mac / Linux** (Terminal):

```sh
curl -fsSL https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/clv/install.sh | bash
```

**Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/clv/install.ps1 | iex
```

It asks your first name, then prints a line starting `ssh-ed25519`. Text that whole line to Levi.

## Log in (daily)

When Levi says you're registered, type:

```sh
nt
```

You'll see `→ Connecting to the NascenTech server` when you go in and `← Back on your own computer` when you leave; the window title says "NascenTech server" while you're there. (`clv login` does the same.) The first time, and about once a week after, a browser opens: sign in with your @nascentech.com Google account.

## The `clv` command

| | |
|---|---|
| `clv login` | log in to the server (same as `nt`) |
| `clv setup` | redo this computer's setup; safe to repeat |
| `clv key` | show the line to text Levi again |
| `clv update` | reinstall the latest version |
| `clv version`, `clv help` | |

## What the installer changes

| | Mac / Linux | Windows |
|---|---|---|
| `clv` and `nt` commands | `~/.collevity/bin/` | `%USERPROFILE%\.collevity\bin\` (`clv.cmd`, `clv.ps1`, `nt.cmd`) |
| cloudflared (skipped if already installed) | `~/.collevity/vendor/cloudflared` | `%USERPROFILE%\.collevity\vendor\cloudflared.exe` |
| SSH key (no passphrase) | `~/.ssh/id_ed25519_nt` (+ `.pub`) | `%USERPROFILE%\.ssh\id_ed25519_nt` (+ `.pub`) |
| The server's pinned host key | `~/.collevity/known_hosts` | `%USERPROFILE%\.collevity\known_hosts` |
| `Host nt` entry | `~/.ssh/config.d/nt` | `%USERPROFILE%\.ssh\config.d\nt` |
| One line added at the top of the SSH config | `Include ~/.ssh/config.d/*` in `~/.ssh/config` | same, in `%USERPROFILE%\.ssh\config` |
| PATH | one line marked `# added by clv installer` in `~/.zshrc` / `~/.bashrc` / `~/.bash_profile` or `~/.profile` | `%USERPROFILE%\.collevity\bin` added to your user PATH |

Your SSH config is backed up first (`config.clv-backup-<date>`). If you already have a `Host nt` entry, or a `clv` the kit didn't install, it stops and tells you. An older install from the nt kit (`~/.nt`, or `%LOCALAPPDATA%\nt` on Windows) is moved over automatically.

If `nt` says "command not found" right after installing, open a new terminal window.

## If the server is rebuilt

The kit pins the server's SSH host key in its own `known_hosts` file, so nobody sees a "are you sure you want to continue connecting?" prompt, and an old entry in `~/.ssh/known_hosts` can't get in the way. If the server's key ever changes, Levi updates the one `NT_HOST_KEY` line in `install.sh` and `$NtHostKey` in `install.ps1`, pushes, and everyone runs `clv update`.

## Undo

Mac / Linux:

```sh
rm -f ~/.collevity/bin/clv ~/.collevity/bin/nt ~/.collevity/vendor/cloudflared ~/.collevity/known_hosts ~/.ssh/config.d/nt ~/.ssh/id_ed25519_nt ~/.ssh/id_ed25519_nt.pub
```

Then delete the `Include ~/.ssh/config.d/*` line from `~/.ssh/config` (if nothing else uses it) and the `# added by clv installer` line from your shell files.

Windows: delete `%USERPROFILE%\.collevity\bin\{clv.cmd,clv.ps1,nt.cmd}`, `%USERPROFILE%\.collevity\vendor\cloudflared.exe`, `%USERPROFILE%\.collevity\known_hosts`, `.ssh\config.d\nt`, `.ssh\id_ed25519_nt*`, the `Include` line in `.ssh\config`, and remove `%USERPROFILE%\.collevity\bin` from your user PATH (Settings → "Edit environment variables for your account").

## For Levi: register / remove

```sh
nt-register <name> "<the ssh-ed25519 line they texted>"
nt-register --remove <name>
nt-register --dry-run ...          # show what would change, connect to nothing
```

`<name>` is lowercase (`ana`, `ben-k`). It's what `clv whoami` will show on the server. Each change backs up the mini's `authorized_keys` first. Test against a local file with `NT_REGISTER_AUTHKEYS_FILE=/tmp/ak nt-register ...`.
