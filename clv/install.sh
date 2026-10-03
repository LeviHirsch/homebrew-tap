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
#   - pins the server's host key in ~/.collevity/known_hosts
#   - moves an older ~/.nt install (nt kit v0) to this layout
# No sudo. Safe to run again.
#
# If the server is rebuilt: change NT_HOST_KEY below (and in install.ps1), push,
# and have everyone run `clv update`.
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
exec "$(dirname "$0")/clv" login "$@"
EOF
	chmod 755 "$BIN/nt.tmp"
	mv -f "$BIN/nt.tmp" "$BIN/nt"

	"$BIN/clv" setup </dev/null || exit $?

	# This window's PATH predates the install. Start a fresh login shell here so
	# `nt` works right away; skip it when PATH is already right or there is no terminal.
	case ":$PATH:" in *":$BIN:"*) exit 0 ;; esac
	case "$(basename "${SHELL:-}")" in zsh | bash) ;; *) exit 0 ;; esac
	if [ -t 1 ] && { : </dev/tty; } 2>/dev/null; then
		exec "$SHELL" -l </dev/tty
	fi
}

write_clv() {
	cat <<'CLV_SCRIPT_END'
#!/usr/bin/env bash
# clv-client-kit
# clv: the NascenTech client. Installed by
#   curl -fsSL https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/clv/install.sh | bash

set -eu

CLV_VERSION="0.1.5-kit"
CLV_INSTALL_URL="${CLV_INSTALL_URL:-https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/clv/install.sh}"

NT_HOSTNAME="ssh.nascentech.com"
NT_USER="nascentech"
NT_SERVER_LABEL="maqmini"
# The server's SSH host key, pinned so nobody gets a "are you sure?" prompt or a
# stale-key failure. If the server is rebuilt, change this one line (and the
# same line in install.ps1) and ship it; `clv update` rewrites the pinned file.
NT_HOST_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPDYW3BFXK5rf33PBnRJhEM1ldlaZ5amlVUu6fagf4F7"
CLV_HOME="$HOME/.collevity"
BIN="$CLV_HOME/bin"
VENDOR="$CLV_HOME/vendor"
SSH_DIR="$HOME/.ssh"
KEY="$SSH_DIR/id_ed25519_nt"
CONF="$SSH_DIR/config"
CONF_D="$SSH_DIR/config.d"
NT_CONF="$CONF_D/nt"
KNOWN_HOSTS="$CLV_HOME/known_hosts"
# What setup added to this computer, one fact per line, so uninstall removes
# exactly that: "cloudflared", "include", "created:<file>".
STATE="$CLV_HOME/.clv-kit-state"
CONF_MARKER="# Written by clv setup"
V0_CONF_MARKER="# Written by the nt installer"
RC_MARKER="# added by clv installer"
V0_RC_MARKER="# added by nt installer"
CF_BASE="https://github.com/cloudflare/cloudflared/releases/latest/download"

# Color only on a terminal, and never when NO_COLOR is set. Plain ANSI, no tput.
B="" G="" Y="" C="" Z="" ER="" EB="" EZ=""
if [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != dumb ]; then
	if [ -t 1 ]; then B=$'\033[1m' G=$'\033[32m' Y=$'\033[33m' C=$'\033[36m' Z=$'\033[0m'; fi
	if [ -t 2 ]; then ER=$'\033[31m' EB=$'\033[1m' EZ=$'\033[0m'; fi
fi

say() { printf '%s\n' "$*"; }
ok() { printf '%s%s%s\n' "$G" "$*" "$Z"; }
warn() { printf '%s%s%s\n' "$Y" "$*" "$Z"; }
die() { printf '\n%sSetup stopped: %s%s\n' "$ER" "$*" "$EZ" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$2"; }
state_has() { [ -f "$STATE" ] && grep -qxF "$1" "$STATE"; }
state_add() { state_has "$1" || printf '%s\n' "$1" >>"$STATE"; }

usage() {
	cat <<EOF
${B}clv $CLV_VERSION: NascenTech client${Z}

  ${B}clv login${Z} [ssh args]   log in to the server (same as: nt)
  ${B}clv setup${Z}              (re)do this computer's setup; safe to repeat
  ${B}clv key${Z}                show the line to text Levi
  ${B}clv update${Z}             reinstall the latest version
  ${B}clv uninstall${Z} [--all]  remove clv from this computer (--all: your key too)
  ${B}clv version${Z}            show the version
  ${B}clv help${Z}               show this help
EOF
}

print_key_message() {
	say "${B}${Y}Text this whole line to Levi:${Z}"
	say ""
	say "  $(cat "$KEY.pub")"
	say ""
	say "${Y}When Levi says you're registered, type: ${B}nt${Z}${Y}  (or: clv login)${Z}"
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
				state_add cloudflared
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
	# Installs from before the state file: the kit's own Host block already
	# points at this copy, so the kit put it here.
	if [ "$LEGACY" = 1 ] && [ -e "$CF" ] && grep -qF "\"$CF\"" "$NT_CONF"; then
		state_add cloudflared
	fi
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
	state_add cloudflared
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
	KEY_NEW=1
	ok "Created your key at $KEY"
}

# The kit's own known_hosts: the user's ~/.ssh/known_hosts is never read or
# written for this host, so a stale entry there can't break the login.
write_known_hosts() {
	printf '%s %s\n' "$NT_HOSTNAME" "$NT_HOST_KEY" >"$KNOWN_HOSTS.tmp"
	chmod 644 "$KNOWN_HOSTS.tmp"
	if [ -f "$KNOWN_HOSTS" ] && cmp -s "$KNOWN_HOSTS.tmp" "$KNOWN_HOSTS"; then
		rm -f "$KNOWN_HOSTS.tmp"
		return
	fi
	mv -f "$KNOWN_HOSTS.tmp" "$KNOWN_HOSTS"
	ok "Wrote $KNOWN_HOSTS"
}

# The line that makes `nt` work in a window opened before the install.
path_hint() {
	case ":$PATH:" in *":$BIN:"*) return ;; esac
	local fix
	case "$(basename "${SHELL:-}")" in
		zsh) fix="source ~/.zshrc" ;;
		bash) fix="source ~/.bashrc" ;;
		*) fix="export PATH=\"\$HOME/.collevity/bin:\$PATH\"" ;;
	esac
	say "${Y}If typing nt says \"command not found\", paste this line:  ${B}$fix${Z}"
	say ""
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
  UserKnownHostsFile ~/.collevity/known_hosts
  HostKeyAlgorithms ssh-ed25519
  StrictHostKeyChecking yes
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
		# Installs from before the state file: a kit backup beside the config, or
		# a config holding nothing but the Include, means the kit added the line.
		if [ "$LEGACY" = 1 ] && ! state_has include; then
			if ls "$CONF".clv-backup-* "$CONF".nt-backup-* >/dev/null 2>&1; then
				state_add include
			elif ! grep -v '^[[:space:]]*$' "$CONF" | grep -qvxF 'Include ~/.ssh/config.d/*'; then
				state_add include
				state_add "created:$CONF"
			fi
		fi
		return
	fi
	local backup
	state_add include
	[ -f "$CONF" ] || state_add "created:$CONF"
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
		[ -e "$f" ] || state_add "created:$f"
		printf '\n%s\n' "$line" >>"$f" || die "Could not update $f."
		ok "Added ~/.collevity/bin to PATH in $f"
	done
}

# Log in. In a terminal with no extra arguments, say clearly when you cross
# over to the server and when you are back, and name the window while there.
cmd_login() {
	# Scripted use (nt ls, pipes, scp-style): plain ssh, nothing added.
	if [ $# -gt 0 ] || [ ! -t 0 ] || [ ! -t 1 ]; then
		exec ssh nt "$@"
	fi

	local here rc=0 tmp log="" reason next connected
	here="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "this computer")"
	tmp="$(mktemp -d 2>/dev/null || true)"
	# Put the window title back and tidy up, also on Ctrl-C.
	trap 'printf "\033]0;\007"; [ -n "$tmp" ] && rm -rf "$tmp"' EXIT

	say "${B}${C}→ Connecting to the NascenTech server ($NT_SERVER_LABEL)...${Z}"
	# ssh runs this on this computer the moment the login succeeds (after any
	# browser sign-in). It goes through the user's shell and through ssh's own
	# % substitution, so: fixed text only, no quotes and no % in it. Passed here,
	# not in the Host block, so scp and `nt <command>` never print it.
	connected="echo '${B}${G}✓ Connected. You are now on the NascenTech server ($NT_SERVER_LABEL). Type exit to come back.${Z}'"
	printf '\033]0;NascenTech server\007'

	# Keep a copy of ssh's own messages (still shown as usual) so a failed
	# connection can be explained in plain words.
	if [ -n "$tmp" ] && mkfifo "$tmp/err" 2>/dev/null; then
		tee "$tmp/log" <"$tmp/err" >&2 &
		ssh -o PermitLocalCommand=yes -o "LocalCommand=$connected" nt 2>"$tmp/err" || rc=$?
		wait || true
		log="$(cat "$tmp/log" 2>/dev/null || true)"
	else
		ssh -o PermitLocalCommand=yes -o "LocalCommand=$connected" nt || rc=$?
	fi
	printf '\033]0;\007'

	# 255 is ssh's own "could not connect"; anything else came from the session.
	if [ "$rc" -ne 255 ]; then
		say "${B}${G}← Back on your own computer ($here).${Z}"
		exit "$rc"
	fi

	case "$log" in
		*"Permission denied"*)
			reason="Levi hasn't registered your key yet."
			next="Run: clv key   and text that line to Levi." ;;
		*"Host key verification failed"* | *"REMOTE HOST IDENTIFICATION"*)
			reason="this computer has an old record of the server."
			next="Run: clv update   then type nt again." ;;
		*"Could not resolve"* | *"no such host"* | *"etwork is unreachable"* | *"dial tcp"* | *"i/o timeout"*)
			reason="you look offline."
			next="Check your internet connection, then type nt again." ;;
		*"client_loop"* | *"Broken pipe"* | *"server not responding"*)
			reason="the connection dropped."
			next="Type nt to reconnect." ;;
		*)
			reason="the browser sign-in didn't finish."
			next="Type nt again and sign in with your @nascentech.com Google account. Still stuck? Run: clv key   and text that line to Levi." ;;
	esac
	printf '%sCould not stay connected to the server: %s%s\n' "$ER" "$reason" "$EZ" >&2
	say "${Y}$next${Z}"
	say "${B}← Still on your own computer ($here).${Z}"
	exit "$rc"
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

	# No state file but the kit's Host block is there: an install from before
	# the state file existed. Setup then works out once what the kit had added.
	LEGACY=0
	if [ ! -f "$STATE" ]; then
		if [ -f "$NT_CONF" ]; then LEGACY=1; fi
		state_add "kit-state-1"
	fi

	KEY_NEW=0
	migrate_v0
	setup_cloudflared
	setup_key
	write_known_hosts
	write_host_block
	ensure_include
	setup_path

	say ""
	# The key only needs sending when it is new. After an update or a repeat
	# setup it is the same key Levi already has.
	if [ "$KEY_NEW" = 1 ]; then
		say "${B}${G}Done.${Z}${B} One more step.${Z}"
		say ""
		path_hint
		print_key_message
	else
		if [ -n "${CLV_UPDATING:-}" ]; then
			say "${B}${G}Updated to $CLV_VERSION.${Z} Your key has not changed, so there is nothing to send."
		else
			say "${B}${G}Done.${Z} clv $CLV_VERSION is set up. Your key has not changed, so there is nothing to send."
		fi
		say "To log in, type: ${B}nt${Z}   (to see your key again: clv key)"
		say ""
		path_hint
	fi
	say ""
}

# Remove exactly what the kit put on this computer, and nothing else.
cmd_uninstall() {
	local all=0 yes=0 a f n reply name=""
	for a in "$@"; do
		case "$a" in
			--all) all=1 ;;
			--yes | -y) yes=1 ;;
			*) printf '%sclv uninstall: unknown option "%s". Use: clv uninstall [--all] [--yes]%s\n' "$ER" "$a" "$EZ" >&2; exit 2 ;;
		esac
	done

	say ""
	say "${B}This removes clv and nt from this computer.${Z}"
	if [ "$all" = 1 ]; then
		say "${Y}It also deletes your key ($KEY), so you would need to be registered again.${Z}"
	else
		say "Your key ($KEY) is kept, so installing again needs no new registration."
	fi
	if [ "$yes" != 1 ]; then
		if [ ! -t 0 ] || [ ! -t 1 ]; then
			printf '%sNothing was removed. To go ahead without being asked, add --yes.%s\n' "$ER" "$EZ" >&2
			exit 1
		fi
		printf 'Go ahead? [y/N] '
		read -r reply || reply=""
		case "$reply" in y | Y | yes | Yes | YES) ;; *) say "Nothing was removed."; exit 0 ;; esac
	fi
	say ""

	# --- the "Host nt" entry
	if [ -f "$NT_CONF" ]; then
		if grep -qF -e "$CONF_MARKER" -e "$V0_CONF_MARKER" "$NT_CONF"; then
			rm -f "$NT_CONF"
			ok "Removed $NT_CONF"
		else
			warn "Kept $NT_CONF: this kit didn't write it"
		fi
	fi

	# --- the Include line, only if the kit added it and nothing else needs it
	if state_has include && [ -f "$CONF" ] && grep -qxF 'Include ~/.ssh/config.d/*' "$CONF"; then
		if [ -d "$CONF_D" ] && [ -n "$(ls -A "$CONF_D" 2>/dev/null)" ]; then
			say "Kept the Include line in $CONF: other files in $CONF_D still use it"
		else
			awk '!done && $0=="Include ~/.ssh/config.d/*" { done=1; skip=1; next }
				skip { skip=0; if ($0=="") next }
				{ print }' "$CONF" >"$CONF.clv-tmp"
			# cat, not mv: keeps the file's permissions and any symlink in place
			cat "$CONF.clv-tmp" >"$CONF"
			rm -f "$CONF.clv-tmp"
			if state_has "created:$CONF" && ! grep -q '[^[:space:]]' "$CONF"; then
				rm -f "$CONF"
				ok "Removed $CONF (the kit created it and it was empty again)"
			else
				ok "Removed the Include line from $CONF"
			fi
		fi
	fi
	rmdir "$CONF_D" 2>/dev/null || true

	# --- the pinned host key, cloudflared, the cached Cloudflare sign-in
	if [ -f "$KNOWN_HOSTS" ]; then
		rm -f "$KNOWN_HOSTS"
		ok "Removed $KNOWN_HOSTS"
	fi
	if [ -e "$VENDOR/cloudflared" ]; then
		if state_has cloudflared; then
			rm -f "$VENDOR/cloudflared"
			ok "Removed $VENDOR/cloudflared"
		else
			warn "Kept $VENDOR/cloudflared: this kit didn't put it there"
		fi
	fi
	n=0
	for f in "$HOME/.cloudflared/$NT_HOSTNAME"-*-token*; do
		[ -e "$f" ] || continue
		rm -f "$f"
		n=$((n + 1))
	done
	[ "$n" -eq 0 ] || ok "Removed the saved Cloudflare sign-in for $NT_HOSTNAME"

	# --- the PATH line in shell startup files
	for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
		[ -f "$f" ] && grep -qF -e "$RC_MARKER" -e "$V0_RC_MARKER" "$f" || continue
		# drop the marked line and the blank line the kit wrote above it
		awk -v m="$RC_MARKER" -v m0="$V0_RC_MARKER" '
			function flush() { if (have) print buf; have=0 }
			index($0, m) || index($0, m0) { if (have && buf != "") print buf; have=0; next }
			{ flush(); buf=$0; have=1 }
			END { flush() }' "$f" >"$f.clv-tmp"
		cat "$f.clv-tmp" >"$f"
		rm -f "$f.clv-tmp"
		if state_has "created:$f" && ! grep -q '[^[:space:]]' "$f"; then
			rm -f "$f"
			ok "Removed $f (the kit created it and it was empty again)"
		else
			ok "Removed the clv PATH line from $f"
		fi
	done

	# --- the key
	if [ -f "$KEY.pub" ]; then
		name="$(awk '{print $3}' "$KEY.pub" | sed 's/@nt$//')"
	fi
	if [ "$all" = 1 ]; then
		if [ -e "$KEY" ] || [ -e "$KEY.pub" ]; then
			rm -f "$KEY" "$KEY.pub"
			ok "Removed your key ($KEY and $KEY.pub)"
			say "${Y}Ask Levi to remove your registration${name:+ (name: $name)}.${Z}"
		fi
	elif [ -e "$KEY" ]; then
		say "Kept your key at $KEY (to delete it too: clv uninstall --all)"
	fi

	# --- the commands themselves, last. This script is already loaded, so
	#     deleting its own file here is safe.
	rm -f "$STATE"
	for f in "$BIN/nt" "$BIN/clv"; do
		if [ -f "$f" ] && grep -qF "# clv-client-kit" "$f"; then
			rm -f "$f"
			ok "Removed $f"
		fi
	done
	# Folders only when empty: other things may live in ~/.collevity.
	rmdir "$VENDOR" 2>/dev/null || true
	rmdir "$BIN" 2>/dev/null || true
	if rmdir "$CLV_HOME" 2>/dev/null; then
		ok "Removed $CLV_HOME"
	else
		say "Kept $CLV_HOME: it has other things in it"
	fi

	say ""
	say "${B}${G}clv is removed.${Z} This window may still remember the old commands; open a new terminal."
	exit 0
}

cmd_key() {
	[ -f "$KEY.pub" ] || { printf '%sNo key yet. Run: clv setup%s\n' "$ER" "$EZ" >&2; exit 1; }
	print_key_message
}

case "${1:-help}" in
	login) shift; cmd_login "$@" ;;
	setup) cmd_setup ;;
	key) cmd_key ;;
	uninstall) shift; cmd_uninstall "$@" ;;
	update)
		src="$(curl -fsSL "$CLV_INSTALL_URL")" || die "Could not download the installer. Check your internet connection and try again."
		printf '%s\n' "$src" | CLV_UPDATING=1 bash
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
