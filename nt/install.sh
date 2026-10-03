#!/usr/bin/env bash
# nt client kit installer (macOS + Linux).
#
#   curl -fsSL https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/nt/install.sh | bash
#
# Sets up `nt`, a one-word login to the NascenTech server:
#   - cloudflared in ~/.nt/bin (or reuses one already on PATH)
#   - an SSH key at ~/.ssh/id_ed25519_nt
#   - a "Host nt" entry in ~/.ssh/config.d/nt, included from ~/.ssh/config
#   - an `nt` command in ~/.nt/bin, added to PATH in your shell startup files
# No sudo. Safe to run again.
#
# Test overrides: NT_NAME=<name> skips the name prompt.

set -eu

# Everything lives in main(), called on the last line, so a half-downloaded
# script runs nothing.
main() {
	NT_HOSTNAME="ssh.nascentech.com"
	NT_USER="nascentech"
	BIN="$HOME/.nt/bin"
	SSH_DIR="$HOME/.ssh"
	KEY="$SSH_DIR/id_ed25519_nt"
	CONF="$SSH_DIR/config"
	CONF_D="$SSH_DIR/config.d"
	NT_CONF="$CONF_D/nt"
	MARKER="# Written by the nt installer"
	RC_MARKER="# added by nt installer"
	CF_BASE="https://github.com/cloudflare/cloudflared/releases/latest/download"

	say ""
	say "Setting up nt (NascenTech server login)."
	say ""

	need ssh "ssh is not installed. Install the OpenSSH client and run this again."
	need ssh-keygen "ssh-keygen is not installed. Install the OpenSSH client and run this again."
	need curl "curl is not installed. Install curl and run this again."

	check_no_conflict

	mkdir -p "$BIN" || die "Could not create $BIN."
	mkdir -p "$SSH_DIR" || die "Could not create $SSH_DIR."
	chmod 700 "$SSH_DIR"

	setup_cloudflared
	setup_key
	write_host_block
	ensure_include
	install_nt_command
	setup_path

	say ""
	say "Done. One more step."
	say ""
	say "Text this whole line to Levi:"
	say ""
	say "  $(cat "$KEY.pub")"
	say ""
	say "When Levi says you're registered, open a new terminal and type: nt"
	say "(The first time, a browser window opens: sign in with your @nascentech.com Google account.)"
	say ""
}

say() { printf '%s\n' "$*"; }
die() { printf '\nSetup stopped: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$2"; }

# Stop if some other "Host nt" already exists, rather than silently overriding it.
check_no_conflict() {
	if [ -e "$NT_CONF" ] && ! grep -qF "$MARKER" "$NT_CONF"; then
		die "$NT_CONF already exists and was not made by this installer. Move it aside and run this again."
	fi
	local f hit
	for f in "$CONF" "$CONF_D"/*; do
		[ -f "$f" ] || continue
		[ "$f" = "$NT_CONF" ] && continue
		hit="$(awk 'tolower($1)=="host" { for (i=2;i<=NF;i++) if ($i=="nt") { print NR; exit } }' "$f")"
		if [ -n "$hit" ]; then
			die "You already have a \"Host nt\" entry in $f (line $hit). I won't overwrite it. Remove or rename that entry, then run this again."
		fi
	done
}

setup_cloudflared() {
	local found os arch asset tmp
	found="$(command -v cloudflared 2>/dev/null || true)"
	if [ -n "$found" ] && [ -x "$found" ]; then
		case "$found" in /*) ;; *) found="$(cd "$(dirname "$found")" && pwd)/$(basename "$found")" ;; esac
		CF="$found"
		say "Using cloudflared already installed at $CF"
		return
	fi
	CF="$BIN/cloudflared"
	if [ -x "$CF" ] && "$CF" --version >/dev/null 2>&1; then
		say "cloudflared already installed at $CF"
		return
	fi

	os="$(uname -s)"
	arch="$(uname -m)"
	case "$os/$arch" in
		Darwin/arm64) asset="cloudflared-darwin-arm64.tgz" ;;
		Darwin/x86_64) asset="cloudflared-darwin-amd64.tgz" ;;
		Linux/x86_64 | Linux/amd64) asset="cloudflared-linux-amd64" ;;
		Linux/aarch64 | Linux/arm64) asset="cloudflared-linux-arm64" ;;
		*) die "This computer ($os $arch) isn't supported yet. Tell Levi what you're on." ;;
	esac

	say "Downloading cloudflared (Cloudflare's login helper)..."
	tmp="$(mktemp -d)" || die "Could not make a temporary folder."
	if ! curl -fsSL -o "$tmp/$asset" "$CF_BASE/$asset" </dev/null; then
		rm -rf "$tmp"
		die "Could not download cloudflared. Check your internet connection and run this again."
	fi
	case "$asset" in
		*.tgz)
			tar -xzf "$tmp/$asset" -C "$tmp" </dev/null || { rm -rf "$tmp"; die "Could not unpack cloudflared."; }
			mv -f "$tmp/cloudflared" "$CF"
			;;
		*) mv -f "$tmp/$asset" "$CF" ;;
	esac
	rm -rf "$tmp"
	chmod 755 "$CF"
	"$CF" --version >/dev/null 2>&1 </dev/null || die "cloudflared downloaded but won't run on this computer."
	say "Installed cloudflared at $CF"
}

setup_key() {
	if [ -f "$KEY" ]; then
		say "Using your existing key at $KEY"
		if [ ! -f "$KEY.pub" ]; then
			ssh-keygen -y -f "$KEY" >"$KEY.pub" </dev/null || die "Could not read your existing key at $KEY."
		fi
		chmod 600 "$KEY"
		return
	fi

	local name="${NT_NAME:-}"
	if [ -z "$name" ]; then
		printf 'Your first name (just a label for Levi): '
		if ! { read -r name </dev/tty; } 2>/dev/null; then
			printf '\n'
			die "Could not ask for your name (no terminal). Run it as: NT_NAME=yourname bash install.sh"
		fi
	fi
	name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
	[ -n "$name" ] || die "I need a first name, using plain letters."

	ssh-keygen -q -t ed25519 -N "" -C "$name@nt" -f "$KEY" </dev/null || die "Could not create your SSH key."
	chmod 600 "$KEY"
	say "Created your key at $KEY"
}

write_host_block() {
	mkdir -p "$CONF_D"
	chmod 700 "$CONF_D"
	cat >"$NT_CONF.tmp" <<EOF
$MARKER. Safe to delete; run the installer again to recreate.
Host nt
  HostName $NT_HOSTNAME
  User $NT_USER
  ProxyCommand "$CF" access ssh --hostname %h
  IdentityFile ~/.ssh/id_ed25519_nt
  IdentitiesOnly yes
EOF
	chmod 600 "$NT_CONF.tmp"
	mv -f "$NT_CONF.tmp" "$NT_CONF"
	say "Wrote $NT_CONF"
}

# Put "Include ~/.ssh/config.d/*" at the top of ~/.ssh/config, once.
# Existing lines are kept exactly as they were, below it.
ensure_include() {
	if [ -f "$CONF" ] && awk '
		tolower($1)=="host" || tolower($1)=="match" { exit 1 }
		tolower($1)=="include" && ($2=="~/.ssh/config.d/*" || $2=="config.d/*") { found=1; exit 0 }
		END { exit !found }' "$CONF"; then
		chmod 600 "$CONF"
		return
	fi
	local backup
	if [ -f "$CONF" ]; then
		backup="$CONF.nt-backup-$(date +%Y%m%d-%H%M%S)"
		cp -p "$CONF" "$backup" || die "Could not back up $CONF."
		say "Backed up your SSH config to $backup"
	fi
	{
		printf 'Include ~/.ssh/config.d/*\n\n'
		if [ -f "$CONF" ]; then cat "$CONF"; fi
	} >"$CONF.nt-tmp" || die "Could not update $CONF."
	chmod 600 "$CONF.nt-tmp"
	mv -f "$CONF.nt-tmp" "$CONF"
	say "Updated $CONF"
}

install_nt_command() {
	cat >"$BIN/nt.tmp" <<'EOF'
#!/bin/sh
# Log in to the NascenTech server. Installed by the nt installer.
exec ssh nt "$@"
EOF
	chmod 755 "$BIN/nt.tmp"
	mv -f "$BIN/nt.tmp" "$BIN/nt"
}

# Add ~/.nt/bin to PATH in the shell startup files this person actually uses.
setup_path() {
	local line f shell_name
	local -a targets=()
	line="case \":\$PATH:\" in *\":\$HOME/.nt/bin:\"*) ;; *) export PATH=\"\$HOME/.nt/bin:\$PATH\" ;; esac $RC_MARKER"
	shell_name="$(basename "${SHELL:-}")"

	if [ -f "$HOME/.zshrc" ] || [ "$shell_name" = zsh ] || [ "$(uname -s)" = Darwin ]; then
		targets+=("$HOME/.zshrc")
	fi
	if [ -f "$HOME/.bashrc" ] || [ "$shell_name" = bash ]; then
		targets+=("$HOME/.bashrc")
	fi
	# Login shells (macOS Terminal with bash, Linux logins) read the first of these that exists.
	if [ -f "$HOME/.bash_profile" ]; then
		targets+=("$HOME/.bash_profile")
	elif [ -f "$HOME/.profile" ] || [ "$shell_name" = bash ] || [ "$shell_name" = sh ] || [ "${#targets[@]}" -eq 0 ]; then
		targets+=("$HOME/.profile")
	fi

	for f in "${targets[@]}"; do
		if [ -f "$f" ] && grep -qF "$RC_MARKER" "$f"; then
			continue
		fi
		printf '\n%s\n' "$line" >>"$f" || die "Could not update $f."
		say "Added ~/.nt/bin to PATH in $f"
	done
}

main "$@"
