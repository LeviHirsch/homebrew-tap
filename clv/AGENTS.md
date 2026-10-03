# clv client kit: notes for whoever changes it

## What this folder is

The kit that gets a non-coder onto the NascenTech server in two lines: one to install, then `nt` to log in.

| File | What it is |
| --- | --- |
| `install.sh` | Mac / Linux installer. It carries the whole `clv` script inside it (the `write_clv` heredoc), writes it to `~/.collevity/bin/clv`, then runs `clv setup`. All real logic lives in that embedded script. |
| `install.ps1` | The same for Windows: carries `clv.ps1` inside it, plus `clv.cmd` and `nt.cmd` shims. |
| `nt-register` | Levi's admin tool. Binds a person's key to a name on the server. Not for fellows. |
| `tests/run.sh` | The tests. |
| `README.md` | For the people who install it. |

## Rules that must stay true

- No sudo, no admin rights.
- Safe to run again: a second run changes nothing (the tests compare every file).
- Back up a user file before editing it. Keep the user's existing lines exactly as they were.
- Never overwrite or delete what the kit didn't install. `clv` and `nt` carry the marker `clv-client-kit`; `~/.ssh/config.d/nt` carries `# Written by clv setup`; PATH lines carry `# added by clv installer`. `~/.collevity/.clv-kit-state` records what setup added (cloudflared, the Include line, files it created) so `clv uninstall` removes exactly that.
- Other things live in `~/.collevity` on some machines. Never remove the folder unless it is empty.
- No secrets in this repo: it is public. The server's host public key is public information.
- Plain-English output. Color only on a terminal, never when `NO_COLOR` is set. No emoji.
- The key line ("Text this whole line to Levi") stays plain, uncolored, on its own line, so it copies cleanly.
- With arguments or without a terminal, `nt` / `clv login` behave exactly like plain `ssh nt`.

## Where things live

- **Version:** `CLV_VERSION` in `install.sh` and `$ClvVersion` in `install.ps1`. Change both together.
- **Server host key:** `NT_HOST_KEY` in `install.sh` and `$NtHostKey` in `install.ps1`. If the server is rebuilt, change both, push, and have everyone run `clv update`. Update `PINNED_FP` in `tests/run.sh` too.
- **Server name shown in the login banner:** `NT_SERVER_LABEL` / `$NtServerLabel`.

## Testing

```sh
clv/tests/run.sh        # add -v to see the output of failing cases
```

Every case runs in a throwaway HOME with fake `ssh` and `curl` first on a minimal PATH. Keep it that way:

- Never test against a real home folder. Never test against the server.
- `nt-register` is tested only with `--dry-run` and `NT_REGISTER_AUTHKEYS_FILE=<temp file>`.
- `ssh -G` needs `-F <sandbox>/.ssh/config`; without it ssh reads the real `~/.ssh/config`.
- PowerShell cases run under `pwsh` if it is installed and are skipped otherwise. Terminal-only cases need `python3` (for a pseudo-terminal).

Add a case for every behavior you add.

## Releasing

Commit and push to `main`. The one-liners and `clv update` read straight from `main`, so a push is a release. Fellows get it by running `clv update`.

## Known gaps

- **Windows is untested on real Windows.** `install.ps1` is only parse-checked and run under `pwsh` on a Mac. Unverified there: the user-PATH edit, the download, Windows OpenSSH's handling of `Include` and the quoted `ProxyCommand`, key generation on PowerShell 5.1, colors, and `clv.cmd` deleting itself during `clv uninstall`.
- **The key has no passphrase.** Anyone who copies `~/.ssh/id_ed25519_nt` is that person on the server until Levi runs `nt-register --remove <name>`.
- **Port forwarding is allowed.** The key line `nt-register` writes has `no-agent-forwarding` only.
- **Not a Homebrew formula yet.** It installs by script.
- **`clv uninstall` leaves the Cloudflare org sign-in** (`*-org-token` in `~/.cloudflared`), because other Cloudflare apps share it. It removes only the ssh.nascentech.com one.
- **Failed-login reasons on Windows are coarse:** offline, or "not registered or sign-in not finished".

## What is still being decided

The long-term home and shape of `clv` is being decided on org-harness board task T152. Until that lands, keep changes here small.
