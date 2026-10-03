#!/usr/bin/env bash
# Tests for the clv client kit.
#
#   clv/tests/run.sh            run everything
#   clv/tests/run.sh -v         also show the output of failing cases
#
# Every case runs in a throwaway HOME under a temp folder, with fake `ssh` and
# `curl` first on a minimal PATH. Nothing here connects anywhere, downloads
# anything, or reads or writes your real home. Exit status is non-zero if any
# case fails. Cases that need a tool this machine lacks are reported as SKIP.

set -u

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

KIT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$KIT/install.sh"
INSTALL_PS1="$KIT/install.ps1"
REGISTER="$KIT/nt-register"
REAL_SSH="$(command -v ssh)"
REAL_HOME="$HOME"
BASE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
PINNED_FP="SHA256:toJ9OSiCsGcyzco1c2o79bOmsGOVJCUQEydlQLLh1xc"
VERSION="$(sed -n 's/^CLV_VERSION="\(.*\)"$/\1/p' "$INSTALL")"

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/clv-tests.XXXXXX")" || exit 1
trap 'rm -rf "$ROOT"' EXIT
case "$ROOT" in "$REAL_HOME"/.ssh* | "$REAL_HOME"/.collevity* | "$REAL_HOME") echo "refusing to run inside the real home"; exit 1 ;; esac

PASS=0
FAIL=0
SKIP=0
OUT="$ROOT/last-output"

section() { printf '\n%s\n' "$1"; }
pass() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
fail() {
	FAIL=$((FAIL + 1))
	printf '  FAIL  %s\n' "$1"
	if [ "$VERBOSE" = 1 ] && [ -f "$OUT" ]; then sed 's/^/        | /' "$OUT"; fi
}
skip() { SKIP=$((SKIP + 1)); printf '  SKIP  %s\n' "$1"; }
# check "<what>" <shell condition as one string>
check() {
	local what="$1"
	shift
	if eval "$*" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi
}

# ---------------------------------------------------------------- shims
SHIM="$ROOT/shim"
CFSHIM="$ROOT/cfshim"
CURL_LOG="$ROOT/curl.log"
mkdir -p "$SHIM" "$CFSHIM" "$ROOT/data"

printf '#!/bin/sh\necho "cloudflared version 0.0.0-fake"\n' >"$ROOT/data/cloudflared"
chmod 755 "$ROOT/data/cloudflared"
tar -czf "$ROOT/data/cloudflared.tgz" -C "$ROOT/data" cloudflared
cp "$ROOT/data/cloudflared" "$CFSHIM/cloudflared"

# Fake curl: serves the fake cloudflared and this repo's installer; never the network.
cat >"$SHIM/curl" <<EOF
#!/bin/sh
out=""; url=""
while [ \$# -gt 0 ]; do
	case "\$1" in
		-o) out="\$2"; shift 2 ;;
		-*) shift ;;
		*) url="\$1"; shift ;;
	esac
done
echo "\$url" >>"$CURL_LOG"
case "\$url" in
	*/cloudflared-*.tgz) cp "$ROOT/data/cloudflared.tgz" "\$out" ;;
	*/cloudflared-*) cp "$ROOT/data/cloudflared" "\$out" ;;
	*/install.sh) cat "$INSTALL" ;;
	*) echo "fake curl: no such URL: \$url" >&2; exit 22 ;;
esac
EOF

# Fake ssh: never connects. Prints its arguments; FAKE_ERR goes to stderr; exits FAKE_RC.
# Like real ssh, it runs a permitted LocalCommand once the "login" has succeeded.
cat >"$SHIM/ssh" <<'EOF'
#!/bin/sh
permit=0; local_cmd=""; shown=""
for a in "$@"; do
	case "$a" in
		PermitLocalCommand=yes) permit=1 ;;
		LocalCommand=*) local_cmd="${a#LocalCommand=}"; a="LocalCommand=<set>" ;;
	esac
	shown="$shown $a"
done
echo "FAKE-SSH args:$shown"
[ -n "${FAKE_ERR:-}" ] && echo "$FAKE_ERR" >&2
if [ "${FAKE_RC:-0}" != 255 ] && [ "$permit" = 1 ] && [ -n "$local_cmd" ]; then sh -c "$local_cmd"; fi
exit "${FAKE_RC:-0}"
EOF
chmod 755 "$SHIM/curl" "$SHIM/ssh"

# A pseudo-terminal runner, for the cases that only happen on a real terminal.
# Types the "|"-separated lines in PTY_TYPE, one each time the output goes quiet.
PTY="$ROOT/ptyrun.py"
cat >"$PTY" <<'EOF'
import os, pty, select, sys, time
lines = [l for l in os.environ.pop('PTY_TYPE', '').split('|') if l]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
out = bytearray(); start = time.time()
while time.time() - start < 60:
    r, _, _ = select.select([fd], [], [], 1.5)
    if r:
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out.extend(d)
    elif lines: os.write(fd, (lines.pop(0) + '\n').encode())
    else:
        try:
            if os.waitpid(pid, os.WNOHANG)[0]: pid = 0; break
        except ChildProcessError: pid = 0; break
st = os.waitpid(pid, 0)[1] if pid else 0
sys.stdout.buffer.write(out)
sys.stdout.write("\nEXIT=%d\n" % (os.waitstatus_to_exitcode(st) if pid else 0))
EOF
HAVE_PTY=0
if command -v python3 >/dev/null 2>&1 && python3 -c 'import pty, os; os.waitstatus_to_exitcode' 2>/dev/null; then HAVE_PTY=1; fi

# ---------------------------------------------------------------- helpers
H=""
new_home() { H="$(mktemp -d "$ROOT/home.XXXXXX")"; }
# in_home [VAR=value ...] command ...   (clean environment, sandbox HOME, shims first)
in_home() { env -i HOME="$H" PATH="$SHIM:$H/.collevity/bin:$BASE_PATH" SHELL=/bin/zsh TERM=dumb "$@"; }
# The helpers below run one command, keep its output in $OUT and its exit status in $RC.
RC=0
# install_kit: as a newcomer would run it, with the kit's bin folder not yet on PATH.
install_kit() { env -i HOME="$H" PATH="$SHIM:$BASE_PATH" SHELL=/bin/zsh TERM=dumb "$@" /bin/bash <"$INSTALL" >"$OUT" 2>&1; RC=$?; }
run() { "$@" >"$OUT" 2>&1; RC=$?; }
on_tty() { python3 "$PTY" env -i HOME="$H" PATH="$SHIM:$H/.collevity/bin:$BASE_PATH" SHELL=/bin/zsh TERM=xterm "$@" >"$OUT" 2>&1; RC=$?; }
snapshot() { (cd "$H" && find . -type f ! -path './.cache/*' -exec shasum {} + | sort -k2 | shasum); }
ssh_g() { HOME="$H" "$REAL_SSH" -G -F "$H/.ssh/config" nt 2>/dev/null; }
esc_count() { LC_ALL=C grep -c "$(printf '\033')\\[[0-9;]*m" "$1"; }

# ================================================================ cases
section "Fresh install"
new_home
mkdir -m 700 "$H/.ssh"
echo "ssh.nascentech.com ssh-ed25519 AAAAstaleSTALEstale" >"$H/.ssh/known_hosts"
cp "$H/.ssh/known_hosts" "$ROOT/stale-known-hosts"
: >"$CURL_LOG"
install_kit NT_NAME="Ana Maria"
check "installer exits 0 without a terminal (no hang)" '[ $RC -eq 0 ]'
check "clv and nt installed, executable" '[ -x "$H/.collevity/bin/clv" ] && [ -x "$H/.collevity/bin/nt" ]'
check "cloudflared downloaded into vendor" '[ -x "$H/.collevity/vendor/cloudflared" ] && grep -q cloudflared- "$CURL_LOG"'
check "key created, comment is the lowercased name" 'grep -q " anamaria@nt$" "$H/.ssh/id_ed25519_nt.pub"'
check "permissions: 700 dirs, 600 private files" '[ "$(stat -f %Lp "$H/.ssh" 2>/dev/null || stat -c %a "$H/.ssh")" = 700 ] && [ "$(stat -f %Lp "$H/.ssh/id_ed25519_nt" 2>/dev/null || stat -c %a "$H/.ssh/id_ed25519_nt")" = 600 ] && [ "$(stat -f %Lp "$H/.ssh/config" 2>/dev/null || stat -c %a "$H/.ssh/config")" = 600 ]'
check "Include is the first line of ~/.ssh/config" '[ "$(head -n 1 "$H/.ssh/config")" = "Include ~/.ssh/config.d/*" ]'
check "PATH line added to .zshrc once" '[ "$(grep -c "added by clv installer" "$H/.zshrc")" = 1 ]'
check "output has the key line, plain, and no color codes when piped" 'grep -qx "  $(cat "$H/.ssh/id_ed25519_nt.pub")" "$OUT" && [ "$(esc_count "$OUT")" = 0 ]'
check "fresh install ends with the key block (the key is new)" 'grep -q "One more step" "$OUT" && grep -q "Text this whole line to Levi" "$OUT" && ! grep -q "nothing to send" "$OUT"'
check "output says how to fix PATH in this window" 'grep -q "paste this line:  source ~/.zshrc" "$OUT"'
check "state file records what the kit added" 'grep -qx cloudflared "$H/.collevity/.clv-kit-state" && grep -qx include "$H/.collevity/.clv-kit-state" && grep -qx "created:$H/.zshrc" "$H/.collevity/.clv-kit-state"'

section "Rerun is idempotent"
before="$(snapshot)"
: >"$CURL_LOG"
install_kit NT_NAME=someone-else
check "second run exits 0" '[ $RC -eq 0 ]'
check "second run does not ask to send the unchanged key again" 'grep -q "Your key has not changed, so there is nothing to send" "$OUT" && ! grep -q "Text this whole line to Levi" "$OUT" && ! grep -q "ssh-ed25519 AAAA" "$OUT"'
check "every file byte-identical after the second run" '[ "$before" = "$(snapshot)" ]'
check "nothing downloaded the second time" '[ ! -s "$CURL_LOG" ]'
check "no config backup made" '! ls "$H/.ssh/"config.clv-backup-*'

section "ssh configuration (ssh -G) and pinned host key"
G="$(ssh_g)"
check "HostName and User" 'echo "$G" | grep -qx "hostname ssh.nascentech.com" && echo "$G" | grep -qx "user nascentech"'
check "IdentityFile and IdentitiesOnly" 'echo "$G" | grep -qx "identityfile ~/.ssh/id_ed25519_nt" && echo "$G" | grep -qx "identitiesonly yes"'
check "ProxyCommand uses the kit cloudflared by absolute path" 'echo "$G" | grep -qxF "proxycommand \"$H/.collevity/vendor/cloudflared\" access ssh --hostname %h"'
check "StrictHostKeyChecking on, HostKeyAlgorithms ssh-ed25519" 'echo "$G" | grep -Eqx "stricthostkeychecking (true|yes)" && echo "$G" | grep -qx "hostkeyalgorithms ssh-ed25519"'
check "UserKnownHostsFile is the kit file; no HostKeyAlias" 'echo "$G" | grep -Eq "^userknownhostsfile .*/\.collevity/known_hosts$" && ! echo "$G" | grep -q "^hostkeyalias"'
check "kit known_hosts holds the pinned key for ssh.nascentech.com" 'ssh-keygen -F ssh.nascentech.com -f "$H/.collevity/known_hosts" | grep -q ssh-ed25519 && ssh-keygen -lf "$H/.collevity/known_hosts" | grep -q "$PINNED_FP"'
check "a stale entry in the user known_hosts is left alone" 'cmp -s "$H/.ssh/known_hosts" "$ROOT/stale-known-hosts"'

section "Subcommands (offline)"
run in_home clv help
check "clv help exits 0 and lists uninstall" '[ $RC -eq 0 ] && grep -q "clv uninstall" "$OUT"'
check "clv (no arguments) shows help, exit 0" 'in_home clv | grep -q "clv login"'
check "clv version prints $VERSION" '[ "$(in_home clv version)" = "clv $VERSION" ]'
run in_home clv key
check "clv key prints the key line plain" '[ $RC -eq 0 ] && grep -qx "  $(cat "$H/.ssh/id_ed25519_nt.pub")" "$OUT"'
run in_home clv bogus
check "unknown command: help and exit 2" '[ $RC -eq 2 ] && grep -q "unknown command" "$OUT" && grep -q "clv login" "$OUT"'
run in_home clv setup
check "clv setup exits 0 and changes nothing" '[ $RC -eq 0 ] && [ "$before" = "$(snapshot)" ]'
run in_home CLV_INSTALL_URL=https://example.invalid/clv/install.sh clv update
check "clv update says Updated to $VERSION and does not ask to re-send the key" 'grep -q "Updated to $VERSION. Your key has not changed, so there is nothing to send." "$OUT" && ! grep -q "Text this whole line to Levi" "$OUT"'
check "clv update reinstalls from the published installer, nothing changes" '[ $RC -eq 0 ] && grep -q "Setting up clv" "$OUT" && [ "$before" = "$(snapshot)" ]'
run in_home CLV_INSTALL_URL=https://example.invalid/missing clv update
check "clv update with a failed download: plain sentence, exit 1" '[ $RC -eq 1 ] && grep -q "Could not download the installer" "$OUT"'
mv "$H/.ssh/id_ed25519_nt.pub" "$ROOT/pub.aside"
run in_home clv key
check "clv key with no key: says so, exit 1" '[ $RC -eq 1 ] && grep -q "No key yet" "$OUT"'
mv "$ROOT/pub.aside" "$H/.ssh/id_ed25519_nt.pub"

section "Login: banners and exit status"
LOGIN_HOME="$H"
run in_home nt
check "not a terminal: no Connected line either" '! grep -q "Connected" "$OUT"'
check "not a terminal: plain ssh, no banner" '[ $RC -eq 0 ] && [ "$(cat "$OUT")" = "FAKE-SSH args: nt" ]'
run in_home FAKE_RC=7 nt ls -la
check "with arguments: passed to ssh, exit status passed back" '[ $RC -eq 7 ] && [ "$(cat "$OUT")" = "FAKE-SSH args: nt ls -la" ]'
if [ "$HAVE_PTY" = 1 ]; then
	on_tty nt
	check "terminal: Connecting banner, then Back banner, exit 0" 'grep -q "Connecting to the NascenTech server (maqmini)" "$OUT" && grep -q "Back on your own computer" "$OUT" && grep -q "^EXIT=0" "$OUT"'
	check "terminal: green Connected line, between Connecting and Back" '[ "$(grep -n "Connecting to" "$OUT" | cut -d: -f1)" -lt "$(grep -n "Connected. You are now on the NascenTech server (maqmini). Type exit to come back." "$OUT" | cut -d: -f1)" ] && [ "$(grep -n "Connected. You are now" "$OUT" | cut -d: -f1)" -lt "$(grep -n "Back on your own computer" "$OUT" | cut -d: -f1)" ] && LC_ALL=C grep -q "$(printf "\033\\[32m").*Connected" "$OUT"'
	check "terminal: window title set and reset" 'LC_ALL=C grep -q "$(printf "\033]0;NascenTech server\007")" "$OUT" && LC_ALL=C grep -q "$(printf "\033]0;\007")" "$OUT"'
	check "terminal: banners are colored" '[ "$(esc_count "$OUT")" -gt 0 ]'
	on_tty FAKE_RC=3 clv login
	check "terminal: session exit status passed through" 'grep -q "Back on your own computer" "$OUT" && grep -q "^EXIT=3" "$OUT"'
	on_tty FAKE_RC=255 FAKE_ERR="nascentech@ssh.nascentech.com: Permission denied (publickey)." nt
	check "failed login: no Connected line" '! grep -q "Connected. You are now" "$OUT"'
	check "failed login (not registered): reason, clv key hint, exit 255" 'grep -q "registered your key yet" "$OUT" && grep -q "clv key" "$OUT" && grep -q "Still on your own computer" "$OUT" && grep -q "^EXIT=255" "$OUT"'
	on_tty FAKE_RC=255 FAKE_ERR="dial tcp: lookup ssh.nascentech.com: no such host" nt
	check "failed login (offline): says offline" 'grep -q "you look offline" "$OUT"'
	on_tty FAKE_RC=255 FAKE_ERR="Host key verification failed." nt
	check "failed login (server key changed): says clv update" 'grep -q "clv update" "$OUT"'
	on_tty FAKE_RC=255 FAKE_ERR="kex_exchange_identification: Connection closed by remote host" nt
	check "failed login (other): says the sign-in didn't finish" 'grep -q "sign-in didn.t finish" "$OUT"'
	on_tty NO_COLOR=1 nt
	check "NO_COLOR on a terminal: no color codes" 'grep -q "Connecting to" "$OUT" && grep -q "Connected. You are now" "$OUT" && [ "$(esc_count "$OUT")" = 0 ]'
else
	skip "terminal-only login cases (need python3 3.9+ for a pseudo-terminal)"
fi

section "Fresh shell after install (terminal)"
if [ "$HAVE_PTY" = 1 ]; then
	new_home
	PTY_TYPE='echo NT-AT-$(command -v nt)|exit' python3 "$PTY" env -i HOME="$H" PATH="$SHIM:$BASE_PATH" SHELL=/bin/bash TERM=xterm NT_NAME=ben /bin/bash "$INSTALL" >"$OUT" 2>&1
	check "installer starts a login shell that finds nt" 'grep -q "NT-AT-$H/.collevity/bin/nt" "$OUT"'
	check "key block comes after the paste-this fallback line" '[ "$(grep -n "paste this line" "$OUT" | head -n 1 | cut -d: -f1)" -lt "$(grep -n "Text this whole line to Levi" "$OUT" | head -n 1 | cut -d: -f1)" ]'
	check "colored on a terminal, key line itself plain" '[ "$(esc_count "$OUT")" -gt 0 ] && LC_ALL=C grep -q "^  ssh-ed25519 [A-Za-z0-9+/=]* ben@nt.$" "$OUT"'
	PTY_TYPE='echo NESTED-SHELL' python3 "$PTY" env -i HOME="$H" PATH="$SHIM:$H/.collevity/bin:$BASE_PATH" SHELL=/bin/bash TERM=xterm /bin/bash "$INSTALL" >"$OUT" 2>&1
	check "no nested shell when PATH is already right" '! grep -q "NESTED-SHELL" "$OUT" && ! grep -q "paste this line" "$OUT"'
else
	skip "fresh-shell cases (need python3 3.9+ for a pseudo-terminal)"
fi

section "Existing ssh config is preserved"
new_home
mkdir -m 700 "$H/.ssh"
printf 'Host github.com\n  User git\n\nHost *\n  ServerAliveInterval 30\n' >"$H/.ssh/config"
cp "$H/.ssh/config" "$ROOT/config.orig"
install_kit NT_NAME=cy
check "install exits 0" '[ $RC -eq 0 ]'
check "backup made, identical to the original" 'cmp -s "$ROOT/config.orig" "$H"/.ssh/config.clv-backup-*'
check "original content kept byte-for-byte below the Include" 'tail -n +3 "$H/.ssh/config" | cmp -s - "$ROOT/config.orig"'
check "the user's other settings still apply" 'ssh_g | grep -qx "serveraliveinterval 30"'

section "Guards: never overwrite what the kit didn't install"
new_home
mkdir -p "$H/.collevity/bin"
printf '#!/bin/sh\necho personal clv\n' >"$H/.collevity/bin/clv"
before="$(snapshot)"
install_kit NT_NAME=x
check "foreign clv: stops with exit 1, changes nothing" '[ $RC -eq 1 ] && grep -q "was not installed by this kit" "$OUT" && [ "$before" = "$(snapshot)" ] && [ ! -e "$H/.ssh" ]'
new_home
mkdir -p "$H/.collevity/bin"
echo '#!/bin/sh' >"$H/.collevity/bin/nt"
before="$(snapshot)"
install_kit NT_NAME=x
check "foreign nt: stops with exit 1, changes nothing" '[ $RC -eq 1 ] && [ "$before" = "$(snapshot)" ]'
new_home
mkdir -m 700 "$H/.ssh"
printf 'Host foo\n  User x\nHost other nt\n  HostName 10.0.0.5\n' >"$H/.ssh/config"
cp "$H/.ssh/config" "$ROOT/config.orig"
install_kit NT_NAME=x
check "existing Host nt: stops with exit 1 and names the line" '[ $RC -eq 1 ] && grep -q "line 3" "$OUT"'
check "existing Host nt: ssh files untouched" 'cmp -s "$H/.ssh/config" "$ROOT/config.orig" && [ ! -e "$H/.ssh/config.d" ] && [ ! -e "$H/.ssh/id_ed25519_nt" ]'
new_home
mkdir -p "$H/.ssh/config.d"
printf 'Host nt\n  HostName elsewhere\n' >"$H/.ssh/config.d/nt"
install_kit NT_NAME=x
check "config.d/nt the kit didn't write: stops, file untouched" '[ $RC -eq 1 ] && grep -q elsewhere "$H/.ssh/config.d/nt"'
new_home
install_kit
check "no name and no terminal: plain sentence, exit 1" '[ $RC -eq 1 ] && grep -q "Could not ask for your name" "$OUT"'

section "Migration from older kits"
if git -C "$KIT" cat-file -e dfc3726:nt/install.sh 2>/dev/null; then
	new_home
	echo 'alias ll="ls -l"' >"$H/.zshrc"
	git -C "$KIT" show dfc3726:nt/install.sh >"$ROOT/v0-install.sh"
	run in_home NT_NAME=mig /bin/bash <"$ROOT/v0-install.sh"
	check "v0 installs into ~/.nt (precondition)" '[ -x "$H/.nt/bin/cloudflared" ] && grep -q "added by nt installer" "$H/.zshrc"'
	pub0="$(cat "$H/.ssh/id_ed25519_nt.pub")"
	run env -i HOME="$H" PATH="$SHIM:$H/.nt/bin:$BASE_PATH" SHELL=/bin/zsh TERM=dumb /bin/bash <"$INSTALL"
	check "v0 -> current: exits 0, ~/.nt gone, cloudflared moved to vendor" '[ $RC -eq 0 ] && [ ! -e "$H/.nt" ] && [ -x "$H/.collevity/vendor/cloudflared" ]'
	check "v0 -> current: same key kept" '[ "$pub0" = "$(cat "$H/.ssh/id_ed25519_nt.pub")" ]'
	check "v0 -> current: old PATH line removed, new one added, user line kept" '! grep -q "added by nt installer" "$H/.zshrc" && grep -q "added by clv installer" "$H/.zshrc" && grep -q "alias ll" "$H/.zshrc"'
	check "v0 -> current: ProxyCommand repointed, host key pinned" 'ssh_g | grep -qF "$H/.collevity/vendor/cloudflared" && ssh_g | grep -q "^userknownhostsfile"'
	before="$(snapshot)"
	install_kit
	check "v0 -> current: rerun identical" '[ "$before" = "$(snapshot)" ]'
else
	skip "v0 migration (commit dfc3726 not in this checkout)"
fi
if git -C "$KIT" cat-file -e 0028f17:clv/install.sh 2>/dev/null; then
	new_home
	git -C "$KIT" show 0028f17:clv/install.sh >"$ROOT/v013-install.sh"
	run in_home NT_NAME=old /bin/bash <"$ROOT/v013-install.sh"
	check "v0.1.3 installs with no state file (precondition)" '[ -x "$H/.collevity/bin/clv" ] && [ ! -e "$H/.collevity/.clv-kit-state" ]'
	install_kit
	check "v0.1.3 -> current: works out what the old kit added" '[ $RC -eq 0 ] && grep -qx cloudflared "$H/.collevity/.clv-kit-state" && grep -qx include "$H/.collevity/.clv-kit-state"'
	run in_home clv uninstall --all --yes
	check "v0.1.3 -> current -> uninstall --all: kit files all gone" '[ $RC -eq 0 ] && [ ! -e "$H/.collevity" ] && [ ! -e "$H/.ssh/config" ] && [ ! -e "$H/.ssh/config.d" ] && [ ! -e "$H/.ssh/id_ed25519_nt" ]'
else
	skip "v0.1.3 upgrade (commit 0028f17 not in this checkout)"
fi

section "Uninstall (default: keeps the key and everything that isn't the kit's)"
new_home
mkdir -m 700 "$H/.ssh"
mkdir -p "$H/.collevity/user" "$H/.cloudflared"
printf 'Host github.com\n  User git\n' >"$H/.ssh/config"
printf 'export EDITOR=vi\nalias ll="ls -l"\n' >"$H/.zshrc"
echo "mine" >"$H/.collevity/user/keep.txt"
for f in ssh.nascentech.com-abc123-token ssh.nascentech.com-abc123-token.lock ssh-air.nascentech.com-def456-token team.cloudflareaccess.com-org-token; do echo t >"$H/.cloudflared/$f"; done
cp "$H/.ssh/config" "$ROOT/config.orig"
cp "$H/.zshrc" "$ROOT/zshrc.orig"
install_kit NT_NAME=dee
before="$(snapshot)"
run in_home clv uninstall
check "no terminal and no --yes: refuses, exit 1, removes nothing" '[ $RC -eq 1 ] && grep -q "add --yes" "$OUT" && [ "$before" = "$(snapshot)" ]'
run in_home clv uninstall --frobnicate
check "unknown option: exit 2, removes nothing" '[ $RC -eq 2 ] && [ "$before" = "$(snapshot)" ]'
if [ "$HAVE_PTY" = 1 ]; then
	PTY_TYPE='n' on_tty clv uninstall
	check "terminal: answering n removes nothing" 'grep -q "Nothing was removed" "$OUT" && [ "$before" = "$(snapshot)" ]'
else
	skip "uninstall confirmation prompt (needs a pseudo-terminal)"
fi
run in_home "$H/.collevity/bin/clv" uninstall --yes
check "uninstall --yes exits 0 and says what it removed" '[ $RC -eq 0 ] && grep -q "Removed $H/.collevity/bin/clv" "$OUT" && grep -q "clv is removed" "$OUT"'
check "clv, nt, cloudflared, known_hosts, state, Host block removed" '[ ! -e "$H/.collevity/bin" ] && [ ! -e "$H/.collevity/vendor" ] && [ ! -e "$H/.collevity/known_hosts" ] && [ ! -e "$H/.collevity/.clv-kit-state" ] && [ ! -e "$H/.ssh/config.d" ]'
check "ssh config back to the original, byte for byte" 'cmp -s "$H/.ssh/config" "$ROOT/config.orig"'
check ".zshrc back to the original, byte for byte" 'cmp -s "$H/.zshrc" "$ROOT/zshrc.orig"'
check "key kept, and the output says so" '[ -f "$H/.ssh/id_ed25519_nt" ] && [ -f "$H/.ssh/id_ed25519_nt.pub" ] && grep -q "Kept your key" "$OUT"'
check "~/.collevity kept because other things live there" '[ "$(cat "$H/.collevity/user/keep.txt")" = mine ] && grep -q "Kept $H/.collevity" "$OUT"'
check "only the ssh.nascentech.com sign-in removed from ~/.cloudflared" '[ "$(ls "$H/.cloudflared" | sort | tr "\n" " ")" = "ssh-air.nascentech.com-def456-token team.cloudflareaccess.com-org-token " ]'
install_kit
check "reinstall after uninstall reuses the kept key" '[ $RC -eq 0 ] && grep -q " dee@nt$" "$H/.ssh/id_ed25519_nt.pub"'

section "Uninstall: things the kit must leave alone"
new_home
mkdir -p "$H/.collevity/vendor" "$H/.ssh/config.d"
chmod 700 "$H/.ssh"
cp "$ROOT/data/cloudflared" "$H/.collevity/vendor/cloudflared"
printf 'Host elsewhere\n  User me\n' >"$H/.ssh/config.d/mine"
printf 'Include ~/.ssh/config.d/*\n\nHost keep\n  User k\n' >"$H/.ssh/config"
cp "$H/.ssh/config" "$ROOT/config.orig"
install_kit NT_NAME=eve
install_kit
run in_home clv uninstall --yes
check "a cloudflared the kit didn't download is kept" '[ $RC -eq 0 ] && [ -x "$H/.collevity/vendor/cloudflared" ] && grep -q "Kept $H/.collevity/vendor/cloudflared" "$OUT"'
check "an Include the user already had is kept, config untouched" 'cmp -s "$H/.ssh/config" "$ROOT/config.orig"'
check "the user's own config.d file is kept" 'grep -q elsewhere "$H/.ssh/config.d/mine" && [ ! -e "$H/.ssh/config.d/nt" ]'

section "Uninstall --all (fresh home: everything the kit created goes)"
new_home
install_kit NT_NAME=fay
run in_home clv uninstall --all --yes
check "exits 0, tells the person to ask Levi, with their name" '[ $RC -eq 0 ] && grep -q "Ask Levi to remove your registration (name: fay)" "$OUT"'
check "key deleted" '[ ! -e "$H/.ssh/id_ed25519_nt" ] && [ ! -e "$H/.ssh/id_ed25519_nt.pub" ]'
check "~/.collevity, ssh config, config.d and the kit-created .zshrc all gone" '[ ! -e "$H/.collevity" ] && [ ! -e "$H/.ssh/config" ] && [ ! -e "$H/.ssh/config.d" ] && [ ! -e "$H/.zshrc" ]'
check "nothing left in the home but an empty ~/.ssh" '[ -z "$(cd "$H" && find . -type f)" ]'

section "nt-register (local file only; never the server)"
REG_DIR="$(mktemp -d "$ROOT/reg.XXXXXX")"
AK="$REG_DIR/authorized_keys"
ssh-keygen -q -t ed25519 -N "" -C "ana@nt" -f "$REG_DIR/k1" </dev/null
ssh-keygen -q -t ed25519 -N "" -C "ben@nt" -f "$REG_DIR/k2" </dev/null
K1="$(cat "$REG_DIR/k1.pub")"
K2="$(cat "$REG_DIR/k2.pub")"
B1="$(awk '{print $2}' "$REG_DIR/k1.pub")"
printf 'ssh-ed25519 AAAAexisting levi@laptop' >"$AK" # no trailing newline, on purpose
reg() { env -i HOME="$REG_DIR" PATH="$SHIM:$BASE_PATH" NT_REGISTER_AUTHKEYS_FILE="$AK" "$REGISTER" "$@" >"$OUT" 2>&1; RC=$?; }
reg --dry-run ana "$K1"
check "--dry-run (before the arguments) prints the line, changes nothing" '[ $RC -eq 0 ] && grep -q "DRY RUN" "$OUT" && grep -qF "clv-login ana\",no-agent-forwarding ssh-ed25519 $B1 ana@nt-kit" "$OUT" && [ "$(wc -l <"$AK" | tr -d " ")" = 0 ]'
reg ana "$K1" --dry-run
check "--dry-run (after the arguments) changes nothing" '[ $RC -eq 0 ] && grep -q "DRY RUN" "$OUT" && ! grep -q "clv-login" "$AK"'
reg ana "  $K1"$'\r'
check "add: exits 0, tolerates stray spaces and CR" '[ $RC -eq 0 ] && grep -q "added: 1 key for ana" "$OUT" && grep -q "fingerprint: SHA256:" "$OUT"'
check "add: exact line appended on its own line" 'grep -qxF "command=\"/Users/nascentech/.collevity/bin/clv-login ana\",no-agent-forwarding ssh-ed25519 $B1 ana@nt-kit" "$AK" && grep -qx "ssh-ed25519 AAAAexisting levi@laptop" "$AK"'
check "add: timestamped backup made first" 'ls "$AK".bak-* && [ "$(stat -f %Lp "$AK" 2>/dev/null || stat -c %a "$AK")" = 600 ]'
reg ana "$K1"
check "duplicate key refused (exit 3)" '[ $RC -eq 3 ] && grep -q "REFUSED" "$OUT"'
reg carl "$K1"
check "same key under another name refused, says who has it" '[ $RC -eq 3 ] && grep -q "bound to ana" "$OUT"'
for bad in Ana a 1ana "an a" 'ana;rm'; do
	reg "$bad" "$K2"
	check "bad name refused: '$bad'" '[ $RC -eq 1 ] && grep -q "bad name" "$OUT"'
done
reg dee "ssh-rsa AAAAB3NzaC1yc2E x"
check "bad key refused: not ed25519" '[ $RC -eq 1 ]'
reg dee "ssh-ed25519 AAAAnotarealkey"
check "bad key refused: not a valid key" '[ $RC -eq 1 ]'
reg dee "$K1"$'\n'"$K2"
check "bad key refused: two lines" '[ $RC -eq 1 ]'
reg dee 'ssh-ed25519 AAAA$(id) x'
check "bad key refused: shell characters" '[ $RC -eq 1 ] && ! grep -q dee "$AK"'
reg ben "$K2"
reg --remove ana
check "--remove (before the name): removes only that name's line" '[ $RC -eq 0 ] && grep -q "removed: 1 line" "$OUT" && ! grep -q "clv-login ana" "$AK" && grep -q "clv-login ben" "$AK"'
reg ben --remove
check "--remove (after the name) works too" '[ $RC -eq 0 ] && ! grep -q "clv-login ben" "$AK" && grep -qx "ssh-ed25519 AAAAexisting levi@laptop" "$AK"'
reg --remove ana
check "removing a name that isn't there: 0 lines, exit 0" '[ $RC -eq 0 ] && grep -q "removed: 0 lines" "$OUT"'
run env -i HOME="$REG_DIR" PATH="$SHIM:$BASE_PATH" "$REGISTER" --dry-run ana "$K1"
check "--dry-run against the server connects to nothing" '[ $RC -eq 0 ] && grep -q "nothing connected" "$OUT" && ! grep -q "FAKE-SSH" "$OUT"'

section "PowerShell (install.ps1)"
if command -v pwsh >/dev/null 2>&1; then
	PWSH="$(command -v pwsh)"
	PS_PATH="$CFSHIM:$SHIM:$(dirname "$PWSH"):$BASE_PATH"
	parse_errors() { PARSE_FILE="$1" "$PWSH" -NoProfile -NonInteractive -c '$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($env:PARSE_FILE,[ref]$t,[ref]$e)|Out-Null;$e.Count' 2>/dev/null; }
	ps_install() { env -i HOME="$H" LOCALAPPDATA="$H/AppData/Local" PATH="$PS_PATH" TERM=dumb "$@" "$PWSH" -NoProfile -NonInteractive -c "Get-Content -Raw '$INSTALL_PS1' | Invoke-Expression; 'AFTER-IEX'" >"$OUT" 2>&1; RC=$?; }
	ps_clv() { env -i HOME="$H" LOCALAPPDATA="$H/AppData/Local" PATH="$PS_PATH" TERM=dumb "$PWSH" -NoProfile -NonInteractive -File "$H/.collevity/bin/clv.ps1" "$@" >"$OUT" 2>&1; RC=$?; }
	check "install.ps1 parses with no errors" '[ "$(parse_errors "$INSTALL_PS1")" = 0 ]'
	new_home
	ps_install NT_NAME=Ana
	check "sandbox install runs; the PowerShell session survives" 'grep -q "Done. One more step" "$OUT" && grep -q "Text this whole line to Levi" "$OUT" && grep -q "AFTER-IEX" "$OUT"'
	check "the embedded clv.ps1 parses with no errors" '[ "$(parse_errors "$H/.collevity/bin/clv.ps1")" = 0 ]'
	check "clv.cmd, nt.cmd, key, known_hosts written" '[ -f "$H/.collevity/bin/clv.cmd" ] && [ -f "$H/.collevity/bin/nt.cmd" ] && grep -q " ana@nt" "$H/.ssh/id_ed25519_nt.pub" && ssh-keygen -lf "$H/.collevity/known_hosts" | grep -q "$PINNED_FP"'
	check "ssh -G: host, pinned key settings" 'ssh_g | grep -qx "hostname ssh.nascentech.com" && ssh_g | grep -qx "hostkeyalgorithms ssh-ed25519" && ssh_g | grep -Eqx "stricthostkeychecking (true|yes)"'
	check "no color codes when piped" '[ "$(esc_count "$OUT")" = 0 ]'
	before="$(snapshot)"
	ps_install
	check "rerun identical" '[ "$before" = "$(snapshot)" ] && ! grep -q "Setup stopped" "$OUT"'
	check "rerun does not ask to send the unchanged key again" 'grep -q "Your key has not changed, so there is nothing to send" "$OUT" && ! grep -q "Text this whole line to Levi" "$OUT"'
	ps_clv key
	check "clv key still shows the key block" '[ $RC -eq 0 ] && grep -q "Text this whole line to Levi" "$OUT"'
	ps_clv version
	check "clv version prints $VERSION" '[ "$(tr -d "\r" <"$OUT")" = "clv $VERSION" ]'
	ps_clv bogus
	check "unknown command: exit 2" '[ $RC -eq 2 ] && grep -q "unknown command" "$OUT"'
	ps_clv login ls
	check "login with arguments: plain ssh" 'grep -q "FAKE-SSH args: nt ls" "$OUT" && ! grep -q "Connecting" "$OUT"'
	ps_clv uninstall
	check "uninstall without --yes and no terminal: refuses" '[ $RC -eq 1 ] && [ "$before" = "$(snapshot)" ]'
	ps_clv uninstall --yes
	check "uninstall --yes: kit files gone, key kept" '[ $RC -eq 0 ] && [ ! -e "$H/.collevity" ] && [ ! -e "$H/.ssh/config" ] && [ ! -e "$H/.ssh/config.d" ] && [ -f "$H/.ssh/id_ed25519_nt" ]'
	new_home
	mkdir -p "$H/.collevity/bin"
	echo "Write-Host personal" >"$H/.collevity/bin/clv.ps1"
	before="$(snapshot)"
	ps_install NT_NAME=x
	check "foreign clv.ps1: stops, changes nothing" 'grep -q "was not installed by this kit" "$OUT" && [ "$before" = "$(snapshot)" ]'
	new_home
	ps_install NT_NAME=Gus
	ps_clv uninstall --all --yes
	check "uninstall --all: key gone too, asks to tell Levi" '[ $RC -eq 0 ] && [ ! -e "$H/.ssh/id_ed25519_nt" ] && grep -q "Ask Levi to remove your registration (name: gus)" "$OUT"'
else
	skip "PowerShell cases (pwsh is not installed)"
fi

section "Safety"
check "the real home's kit paths were never the sandbox" '[ "$H" != "$REAL_HOME" ] && case "$H" in "$ROOT"/*) true ;; *) false ;; esac'

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
