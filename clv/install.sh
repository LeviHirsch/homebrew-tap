#!/usr/bin/env bash
# clv client kit installer (macOS + Linux).
#
#   curl -fsSL https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/clv/install.sh | bash
#
# Installs `clv` and `nt` into ~/.collevity/bin, then runs `clv setup`, which:
#   - puts cloudflared in ~/.collevity/vendor (or reuses one already on PATH)
#   - makes an SSH key at ~/.ssh/id_ed25519_nt
#   - writes a "Host nt" entry to ~/.ssh/config.d/nt, included from ~/.ssh/config
#   - adds ~/.collevity/bin to PATH in your shell startup files
#   - moves an older ~/.nt install (nt kit v0) to this layout
# No sudo. Safe to run again.
#
# Test overrides: NT_NAME=<name> skips the name prompt.

set -eu

# Everything lives in main(), called on the last line, so a half-downloaded
# script runs nothing.
main() {
	BIN="$HOME/.collevity/bin"
	MARKER="# clv-client-kit"
	local red="" off=""
	if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != dumb ]; then red=$'\033[31m' off=$'\033[0m'; fi

	# Never replace a clv or nt that this kit didn't write (e.g. Levi's own clv).
	local f
	for f in "$BIN/clv" "$BIN/nt"; do
		if [ -e "$f" ] && ! grep -qF "$MARKER" "$f" 2>/dev/null; then
			printf '\n%sSetup stopped: %s already exists and was not installed by this kit. Nothing was changed.%s\n' "$red" "$f" "$off" >&2
			exit 1
		fi
	done

	mkdir -p "$BIN" || { printf '\n%sSetup stopped: could not create %s.%s\n' "$red" "$BIN" "$off" >&2; exit 1; }
	write_clv >"$BIN/clv.tmp"
	chmod 755 "$BIN/clv.tmp"
	mv -f "$BIN/clv.tmp" "$BIN/clv"
	cat >"$BIN/nt.tmp" <<'EOF'
#!/bin/sh
# clv-client-kit: `nt` is short for `clv login`.
exec ssh nt "$@"
EOF
	chmod 755 "$BIN/nt.tmp"
	mv -f "$BIN/nt.tmp" "$BIN/nt"

	exec "$BIN/clv" setup </dev/null
}

write_clv() {
	cat <<'CLV_SCRIPT_END'
#!/usr/bin/env bash
# clv-client-kit
# clv: the NascenTech client. Installed by
#   curl -fsSL https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/clv/install.sh | bash

set -eu

CLV_VERSION="0.1.1-kit"
CLV_INSTALL_URL="${CLV_INSTALL_URL:-https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/clv/install.sh}"

NT_HOSTNAME="ssh.nascentech.com"
NT_USER="nascentech"
CLV_HOME="$HOME/.collevity"
BIN="$CLV_HOME/bin"
VENDOR="$CLV_HOME/vendor"
SSH_DIR="$HOME/.ssh"
KEY="$SSH_DIR/id_ed25519_nt"
CONF="$SSH_DIR/config"
CONF_D="$SSH_DIR/config.d"
NT_CONF="$CONF_D/nt"
CONF_MARKER="# Written by clv setup"
V0_CONF_MARKER="# Written by the nt installer"
RC_MARKER="# added by clv installer"
V0_RC_MARKER="# added by nt installer"
CF_BASE="https://github.com/cloudflare/cloudflared/releases/latest/download"

# Color only on a terminal, and never when NO_COLOR is set. Plain ANSI, no tput.
B="" G="" Y="" Z="" ER="" EB="" EZ=""
if [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != dumb ]; then
	if [ -t 1 ]; then B=$'\033[1m' G=$'\033[32m' Y=$'\033[33m' Z=$'\033[0m'; fi
	if [ -t 2 ]; then ER=$'\033[31m' EB=$'\033[1m' EZ=$'\033[0m'; fi
fi

say() { printf '%s\n' "$*"; }
ok() { printf '%s%s%s\n' "$G" "$*" "$Z"; }
warn() { printf '%s%s%s\n' "$Y" "$*" "$Z"; }
die() { printf '\n%sSetup stopped: %s%s\n' "$ER" "$*" "$EZ" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$2"; }

usage() {
	cat <<EOF
${B}clv $CLV_VERSION: NascenTech client${Z}

  ${B}clv login${Z} [ssh args]   log in to the server (same as: nt)
  ${B}clv setup${Z}              (re)do this computer's setup; safe to repeat
  ${B}clv key${Z}                show the line to text Levi
  ${B}clv update${Z}             reinstall the latest version
  ${B}clv version${Z}            show the version
  ${B}clv help${Z}               show this help
EOF
}

print_key_message() {
	say "${B}${Y}Text this whole line to Levi:${Z}"
	say ""
	say "  $(cat "$KEY.pub")"
	say ""
	say "${Y}When Levi says you're registered, open a new terminal and type: ${B}nt${Z}${Y}  (or: clv login)${Z}"
	say "(The first time, a browser window opens: sign in with your @nascentech.com Google account.)"
}

# Stop if some other "Host nt" already exists, rather than silently overriding it.
check_no_conflict() {
	if [ -e "$NT_CONF" ] && ! grep -qF -e "$CONF_MARKER" -e "$V0_CONF_MARKER" "$NT_CONF"; then
		die "$NT_CONF already exists and was not made by this kit. Move it aside and run this again."
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

# nt kit v0 lived in ~/.nt/bin and added its own PATH line. Move it over.
migrate_v0() {
	local old="$HOME/.nt/bin" f
	if [ -d "$old" ]; then
		if [ -f "$old/cloudflared" ]; then
			if [ -e "$VENDOR/cloudflared" ]; then
				rm -f "$old/cloudflared"
			else
				mv -f "$old/cloudflared" "$VENDOR/cloudflared"
				ok "Moved cloudflared from $old to $VENDOR"
			fi
		fi
		if [ -f "$old/nt" ] && grep -qF "Installed by the nt installer" "$old/nt"; then
			rm -f "$old/nt"
		fi
		if rmdir "$old" 2>/dev/null && rmdir "$HOME/.nt" 2>/dev/null; then
			ok "Removed the old ~/.nt folder"
		else
			warn "Left ~/.nt in place: it has other files in it"
		fi
	fi
	for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
		[ -f "$f" ] && grep -qF "$V0_RC_MARKER" "$f" || continue
		grep -vF "$V0_RC_MARKER" "$f" >"$f.clv-tmp" || true
		# cat, not mv: keeps the file's permissions and any symlink in place
		cat "$f.clv-tmp" >"$f"
		rm -f "$f.clv-tmp"
		ok "Removed the old nt PATH line from $f"
	done
}

setup_cloudflared() {
	local found os arch asset tmp
	CF="$VENDOR/cloudflared"
	if [ -x "$CF" ] && "$CF" --version >/dev/null 2>&1 </dev/null; then
		say "cloudflared already installed at $CF"
		return
	fi
	found="$(command -v cloudflared 2>/dev/null || true)"
	case "$found" in "$HOME/.nt/"*) found="" ;; esac
	if [ -n "$found" ] && [ -x "$found" ]; then
		case "$found" in /*) ;; *) found="$(cd "$(dirname "$found")" && pwd)/$(basename "$found")" ;; esac
		CF="$found"
		say "Using cloudflared already installed at $CF"
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
	ok "Installed cloudflared at $CF"
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
			die "Could not ask for your name (no terminal). Run it as: NT_NAME=yourname clv setup"
		fi
	fi
	name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
	[ -n "$name" ] || die "I need a first name, using plain letters."

	ssh-keygen -q -t ed25519 -N "" -C "$name@nt" -f "$KEY" </dev/null || die "Could not create your SSH key."
	chmod 600 "$KEY"
	ok "Created your key at $KEY"
}

write_host_block() {
	mkdir -p "$CONF_D"
	chmod 700 "$CONF_D"
	cat >"$NT_CONF.tmp" <<EOF
$CONF_MARKER. Safe to delete; run "clv setup" to recreate.
Host nt
  HostName $NT_HOSTNAME
  User $NT_USER
  ProxyCommand "$CF" access ssh --hostname %h
  IdentityFile ~/.ssh/id_ed25519_nt
  IdentitiesOnly yes
EOF
	chmod 600 "$NT_CONF.tmp"
	if [ -f "$NT_CONF" ] && cmp -s "$NT_CONF.tmp" "$NT_CONF"; then
		rm -f "$NT_CONF.tmp"
		return
	fi
	mv -f "$NT_CONF.tmp" "$NT_CONF"
	ok "Wrote $NT_CONF"
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
		backup="$CONF.clv-backup-$(date +%Y%m%d-%H%M%S)"
		cp -p "$CONF" "$backup" || die "Could not back up $CONF."
		say "Backed up your SSH config to $backup"
	fi
	{
		printf 'Include ~/.ssh/config.d/*\n\n'
		if [ -f "$CONF" ]; then cat "$CONF"; fi
	} >"$CONF.clv-tmp" || die "Could not update $CONF."
	chmod 600 "$CONF.clv-tmp"
	mv -f "$CONF.clv-tmp" "$CONF"
	ok "Updated $CONF"
}

# Add ~/.collevity/bin to PATH in the shell startup files this person actually uses.
setup_path() {
	local line f shell_name
	local -a targets=()
	line="case \":\$PATH:\" in *\":\$HOME/.collevity/bin:\"*) ;; *) export PATH=\"\$HOME/.collevity/bin:\$PATH\" ;; esac $RC_MARKER"
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
		ok "Added ~/.collevity/bin to PATH in $f"
	done
}

cmd_setup() {
	say ""
	say "${B}Setting up clv $CLV_VERSION (NascenTech server login).${Z}"
	say ""
	need ssh "ssh is not installed. Install the OpenSSH client and run this again."
	need ssh-keygen "ssh-keygen is not installed. Install the OpenSSH client and run this again."
	need curl "curl is not installed. Install curl and run this again."

	check_no_conflict
	mkdir -p "$BIN" "$VENDOR" || die "Could not create $CLV_HOME."
	mkdir -p "$SSH_DIR" || die "Could not create $SSH_DIR."
	chmod 700 "$SSH_DIR"

	migrate_v0
	setup_cloudflared
	setup_key
	write_host_block
	ensure_include
	setup_path

	say ""
	say "${B}${G}Done.${Z}${B} One more step.${Z}"
	say ""
	print_key_message
	say ""
}

cmd_key() {
	[ -f "$KEY.pub" ] || { printf '%sNo key yet. Run: clv setup%s\n' "$ER" "$EZ" >&2; exit 1; }
	print_key_message
}

case "${1:-help}" in
	login) shift; exec ssh nt "$@" ;;
	setup) cmd_setup ;;
	key) cmd_key ;;
	update)
		src="$(curl -fsSL "$CLV_INSTALL_URL")" || die "Could not download the installer. Check your internet connection and try again."
		printf '%s\n' "$src" | bash
		;;
	version | --version | -v) say "clv $CLV_VERSION" ;;
	help | --help | -h) usage ;;
	*)
		printf '%sclv: unknown command "%s"%s\n\n' "$ER" "$1" "$EZ" >&2
		B="$EB" Z="$EZ"
		usage >&2
		exit 2
		;;
esac
CLV_SCRIPT_END
}

main "$@"
