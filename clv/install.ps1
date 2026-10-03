# clv client kit installer (Windows 10/11, PowerShell 5+).
#
#   irm https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/clv/install.ps1 | iex
#
# Installs clv (clv.cmd + clv.ps1) and nt.cmd into %USERPROFILE%\.collevity\bin,
# then runs `clv setup`, which:
#   - puts cloudflared in %USERPROFILE%\.collevity\vendor (or reuses one already on PATH)
#   - makes an SSH key at %USERPROFILE%\.ssh\id_ed25519_nt
#   - writes a "Host nt" entry to .ssh\config.d\nt, included from .ssh\config
#   - adds %USERPROFILE%\.collevity\bin to your user PATH
#   - pins the server's host key in %USERPROFILE%\.collevity\known_hosts
#   - moves an older %LOCALAPPDATA%\nt install (nt kit v0) to this layout
# No admin rights. Safe to run again.
#
# If the server is rebuilt: change $NtHostKey below (and NT_HOST_KEY in install.sh),
# push, and have everyone run `clv update`.
#
# Test overrides: $env:NT_NAME skips the name prompt.

# Runs inside a script block so `irm | iex` never closes the window on failure
# and nothing leaks into the caller's session.
& {
	$ErrorActionPreference = 'Stop'
	$Marker = 'clv-client-kit'
	$Bin = Join-Path $HOME '.collevity\bin'
	$ClvPs1 = Join-Path $Bin 'clv.ps1'
	$Utf8 = New-Object System.Text.UTF8Encoding($false)
	$UseColor = (-not $env:NO_COLOR) -and (-not [Console]::IsOutputRedirected)

	try {
		# Never replace a clv or nt that this kit didn't write.
		foreach ($name in 'clv.ps1', 'clv.cmd', 'nt.cmd') {
			$f = Join-Path $Bin $name
			if ((Test-Path -LiteralPath $f) -and -not (Select-String -LiteralPath $f -SimpleMatch $Marker -Quiet)) {
				throw [System.Exception]::new("NT_SETUP: $f already exists and was not installed by this kit. Nothing was changed.")
			}
		}

		New-Item -ItemType Directory -Force -Path $Bin | Out-Null
		$ClvSource = @'
# clv-client-kit
# clv: the NascenTech client (Windows). Installed by
#   irm https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/clv/install.ps1 | iex

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ClvVersion = '0.1.3-kit'
$InstallUrl = 'https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/clv/install.ps1'
if ($env:CLV_INSTALL_URL) { $InstallUrl = $env:CLV_INSTALL_URL }

$NtHostName = 'ssh.nascentech.com'
$NtUser = 'nascentech'
$NtServerLabel = 'maqmini'
# The server's SSH host key, pinned so nobody gets a "are you sure?" prompt or a
# stale-key failure. If the server is rebuilt, change this one line (and the
# same line in install.sh) and ship it; `clv update` rewrites the pinned file.
$NtHostKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPDYW3BFXK5rf33PBnRJhEM1ldlaZ5amlVUu6fagf4F7'
$OnWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
$ClvHome = Join-Path $HOME '.collevity'
$Bin = Join-Path $ClvHome 'bin'
$Vendor = Join-Path $ClvHome 'vendor'
$SshDir = Join-Path $HOME '.ssh'
$Key = Join-Path $SshDir 'id_ed25519_nt'
$Conf = Join-Path $SshDir 'config'
$ConfD = Join-Path $SshDir 'config.d'
$NtConf = Join-Path $ConfD 'nt'
$KnownHosts = Join-Path $ClvHome 'known_hosts'
$ConfMarker = '# Written by clv setup'
$V0ConfMarker = '# Written by the nt installer'
$LocalAppData = $env:LOCALAPPDATA
if (-not $LocalAppData) { $LocalAppData = Join-Path $HOME 'AppData\Local' }
$V0Bin = Join-Path $LocalAppData 'nt\bin'
$CfUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# Color only on a real console, and never when NO_COLOR is set.
$UseColor = (-not $env:NO_COLOR) -and (-not [Console]::IsOutputRedirected)
function Say([string]$Text, [string]$Color) {
	if ($Color -and $UseColor) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}
function Fail([string]$Text) {
	Say ''
	Say "Setup stopped: $Text" Red
	exit 1
}

function Show-Usage {
	Say "clv $ClvVersion`: NascenTech client" Cyan
	Say ''
	Say '  clv login [ssh args]   log in to the server (same as: nt)'
	Say "  clv setup              (re)do this computer's setup; safe to repeat"
	Say '  clv key                show the line to text Levi'
	Say '  clv update             reinstall the latest version'
	Say '  clv version            show the version'
	Say '  clv help               show this help'
}

function Show-KeyMessage {
	$PubLine = ([IO.File]::ReadAllText("$Key.pub")).Trim()
	Say 'Text this whole line to Levi:' Yellow
	Say ''
	Say "  $PubLine"
	Say ''
	Say "When Levi says you're registered, type: nt  (or: clv login)" Yellow
	Say '(The first time, a browser window opens: sign in with your @nascentech.com Google account.)'
}

function Get-UserPathParts {
	$p = [Environment]::GetEnvironmentVariable('Path', 'User')
	if (-not $p) { return @() }
	return @($p -split ';' | Where-Object { $_ })
}

function Invoke-Setup {
	Say ''
	Say "Setting up clv $ClvVersion (NascenTech server login)." Cyan
	Say ''

	# --- OpenSSH client (built into Windows 10/11, sometimes switched off)
	$Ssh = Get-Command ssh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	$SshKeygen = Get-Command ssh-keygen -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $Ssh -or -not $SshKeygen) {
		Fail ("The Windows OpenSSH client is not turned on. Open Settings > Apps > Optional features > " +
			"Add a feature (or 'View features'), install 'OpenSSH Client', then open a new PowerShell and run this again.")
	}

	# --- Stop if some other "Host nt" already exists
	if ((Test-Path -LiteralPath $NtConf) -and -not (Select-String -LiteralPath $NtConf -SimpleMatch $ConfMarker, $V0ConfMarker -Quiet)) {
		Fail "$NtConf already exists and was not made by this kit. Move it aside and run this again."
	}
	$ToCheck = @()
	if (Test-Path -LiteralPath $Conf) { $ToCheck += $Conf }
	if (Test-Path -LiteralPath $ConfD) { $ToCheck += Get-ChildItem -LiteralPath $ConfD -File | Where-Object { $_.FullName -ne $NtConf } | ForEach-Object { $_.FullName } }
	foreach ($f in $ToCheck) {
		$n = 0
		foreach ($line in [IO.File]::ReadAllLines($f)) {
			$n++
			$words = $line.Trim() -split '\s+'
			if ($words.Count -ge 2 -and $words[0] -eq 'host' -and ($words[1..($words.Count - 1)] -contains 'nt')) {
				Fail "You already have a `"Host nt`" entry in $f (line $n). I won't overwrite it. Remove or rename that entry, then run this again."
			}
		}
	}

	New-Item -ItemType Directory -Force -Path $Bin, $Vendor, $SshDir | Out-Null

	# --- Move an nt kit v0 install (%LOCALAPPDATA%\nt\bin) over
	$Cf = Join-Path $Vendor 'cloudflared.exe'
	if (Test-Path -LiteralPath $V0Bin) {
		$OldCf = Join-Path $V0Bin 'cloudflared.exe'
		if (Test-Path -LiteralPath $OldCf) {
			if (Test-Path -LiteralPath $Cf) { Remove-Item -LiteralPath $OldCf -Force }
			else { Move-Item -LiteralPath $OldCf $Cf; Say "Moved cloudflared from $V0Bin to $Vendor" Green }
		}
		$OldNt = Join-Path $V0Bin 'nt.cmd'
		if ((Test-Path -LiteralPath $OldNt) -and ([IO.File]::ReadAllText($OldNt) -eq "@echo off`r`nssh nt %*`r`n")) {
			Remove-Item -LiteralPath $OldNt -Force
		}
		if (-not (Get-ChildItem -LiteralPath $V0Bin -Force)) {
			Remove-Item -LiteralPath $V0Bin
			$V0Dir = Split-Path $V0Bin
			if (-not (Get-ChildItem -LiteralPath $V0Dir -Force)) { Remove-Item -LiteralPath $V0Dir }
			Say "Removed the old $V0Dir folder" Green
		} else {
			Say "Left $V0Bin in place: it has other files in it" Yellow
		}
	}
	if ($OnWindows) {
		$Parts = Get-UserPathParts
		if ($Parts -contains $V0Bin) {
			[Environment]::SetEnvironmentVariable('Path', (@($Parts | Where-Object { $_ -ne $V0Bin }) -join ';'), 'User')
			Say "Removed $V0Bin from your PATH" Green
		}
	}

	# --- cloudflared
	if (Test-Path -LiteralPath $Cf) {
		Say "cloudflared already installed at $Cf"
	} else {
		$Found = Get-Command cloudflared -CommandType Application -ErrorAction SilentlyContinue |
			Where-Object { -not $_.Source.StartsWith($V0Bin) } | Select-Object -First 1
		if ($Found) {
			$Cf = $Found.Source
			Say "Using cloudflared already installed at $Cf"
		} else {
			if (-not [Environment]::Is64BitOperatingSystem) { Fail "This computer isn't 64-bit Windows, which isn't supported yet. Tell Levi." }
			Say "Downloading cloudflared (Cloudflare's login helper)..."
			[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
			try {
				Invoke-WebRequest -UseBasicParsing -Uri $CfUrl -OutFile "$Cf.download"
			} catch {
				Fail 'Could not download cloudflared. Check your internet connection and run this again.'
			}
			Move-Item -Force "$Cf.download" $Cf
			Say "Installed cloudflared at $Cf" Green
		}
	}

	# --- SSH key
	if (Test-Path -LiteralPath $Key) {
		Say "Using your existing key at $Key"
		if (-not (Test-Path -LiteralPath "$Key.pub")) {
			$pub = & $SshKeygen.Source -y -f $Key
			if ($LASTEXITCODE -ne 0) { Fail "Could not read your existing key at $Key." }
			[IO.File]::WriteAllText("$Key.pub", ($pub -join "`n") + "`n", $Utf8)
		}
	} else {
		$Name = $env:NT_NAME
		if (-not $Name) { $Name = Read-Host 'Your first name (just a label for Levi)' }
		$Name = ($Name.ToLowerInvariant() -replace '[^a-z0-9-]', '')
		if (-not $Name) { Fail 'I need a first name, using plain letters.' }
		# One raw argument string, so the empty passphrase survives PowerShell 5's argument passing.
		$KeygenArgs = "-q -t ed25519 -N `"`" -C `"$Name@nt`" -f `"$Key`""
		$p = Start-Process -FilePath $SshKeygen.Source -ArgumentList $KeygenArgs -NoNewWindow -Wait -PassThru
		if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath "$Key.pub")) { Fail 'Could not create your SSH key.' }
		Say "Created your key at $Key" Green
	}

	# --- The kit's own known_hosts: the user's .ssh\known_hosts is never read or
	#     written for this host, so a stale entry there can't break the login.
	$Pinned = "$NtHostName $NtHostKey`n"
	if (-not (Test-Path -LiteralPath $KnownHosts) -or [IO.File]::ReadAllText($KnownHosts) -ne $Pinned) {
		[IO.File]::WriteAllText($KnownHosts, $Pinned, $Utf8)
		Say "Wrote $KnownHosts" Green
	}

	# --- Host block
	New-Item -ItemType Directory -Force -Path $ConfD | Out-Null
	$Block = @(
		"$ConfMarker. Safe to delete; run `"clv setup`" to recreate."
		'Host nt'
		"  HostName $NtHostName"
		"  User $NtUser"
		"  ProxyCommand `"$Cf`" access ssh --hostname %h"
		'  IdentityFile ~/.ssh/id_ed25519_nt'
		'  IdentitiesOnly yes'
		'  UserKnownHostsFile ~/.collevity/known_hosts'
		'  HostKeyAlgorithms ssh-ed25519'
		'  StrictHostKeyChecking yes'
	) -join "`n"
	$Block += "`n"
	if (-not (Test-Path -LiteralPath $NtConf) -or [IO.File]::ReadAllText($NtConf) -ne $Block) {
		[IO.File]::WriteAllText($NtConf, $Block, $Utf8)
		Say "Wrote $NtConf" Green
	}

	# --- Include line at the top of .ssh\config, once; existing lines kept as-is below it
	$HasInclude = $false
	if (Test-Path -LiteralPath $Conf) {
		foreach ($line in [IO.File]::ReadAllLines($Conf)) {
			$words = $line.Trim() -split '\s+'
			if ($words[0] -eq 'host' -or $words[0] -eq 'match') { break }
			if ($words[0] -eq 'include' -and $words.Count -ge 2 -and ($words[1] -eq '~/.ssh/config.d/*' -or $words[1] -eq 'config.d/*')) { $HasInclude = $true; break }
		}
	}
	if (-not $HasInclude) {
		$Old = [byte[]]@()
		if (Test-Path -LiteralPath $Conf) {
			$Backup = "$Conf.clv-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
			Copy-Item -LiteralPath $Conf $Backup
			Say "Backed up your SSH config to $Backup"
			$Old = [IO.File]::ReadAllBytes($Conf)
			# Drop a UTF-8 byte-order mark (Notepad adds one) so it doesn't land mid-file.
			if ($Old.Length -ge 3 -and $Old[0] -eq 0xEF -and $Old[1] -eq 0xBB -and $Old[2] -eq 0xBF) {
				if ($Old.Length -eq 3) { $Old = [byte[]]@() } else { $Old = $Old[3..($Old.Length - 1)] }
			}
		}
		$New = $Utf8.GetBytes("Include ~/.ssh/config.d/*`n`n") + $Old
		[IO.File]::WriteAllBytes("$Conf.clv-tmp", [byte[]]$New)
		Move-Item -Force "$Conf.clv-tmp" $Conf
		Say "Updated $Conf" Green
	}

	# --- user PATH
	if ($OnWindows) {
		$Parts = Get-UserPathParts
		if ($Parts -notcontains $Bin) {
			[Environment]::SetEnvironmentVariable('Path', (@($Parts) + $Bin) -join ';', 'User')
			Say "Added $Bin to your PATH" Green
		}
	} else {
		Say "(Not Windows: skipped adding $Bin to the user PATH.)"
	}

	Say ''
	Say 'Done. One more step.' Green
	Say ''
	if ($OnWindows -and ($env:Path -split ';') -notcontains $Bin -and -not $env:CLV_FROM_INSTALLER) {
		Say "If typing nt says it isn't recognized, open a new PowerShell window." Yellow
		Say ''
	}
	Show-KeyMessage
	Say ''
}

$Cmd = 'help'
$Rest = @()
if ($args.Count -ge 1) { $Cmd = [string]$args[0] }
if ($args.Count -ge 2) { $Rest = @($args[1..($args.Count - 1)]) }

switch ($Cmd) {
	'login' {
		# Scripted use (nt ls, pipes): plain ssh, nothing added.
		$Interactive = ($Rest.Count -eq 0) -and (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
		if (-not $Interactive) { & ssh nt @Rest; exit $LASTEXITCODE }

		# In a terminal: say clearly when you cross over to the server and when
		# you are back, and name the window while there.
		$Here = [Environment]::MachineName
		Say "--> Connecting to the NascenTech server ($NtServerLabel)..." Cyan
		$OldTitle = $null
		try { $OldTitle = $Host.UI.RawUI.WindowTitle; $Host.UI.RawUI.WindowTitle = 'NascenTech server' } catch { $OldTitle = $null }
		$Rc = 255
		try { & ssh nt; $Rc = $LASTEXITCODE }
		finally { if ($null -ne $OldTitle) { try { $Host.UI.RawUI.WindowTitle = $OldTitle } catch { } } }

		# 255 is ssh's own "could not connect"; anything else came from the session.
		if ($Rc -ne 255) {
			Say "<-- Back on your own computer ($Here)." Green
			exit $Rc
		}
		$Online = $true
		try { [Net.Dns]::GetHostAddresses($NtHostName) | Out-Null } catch { $Online = $false }
		if (-not $Online) {
			Say 'Could not connect to the server: you look offline.' Red
			Say 'Check your internet connection, then type nt again.' Yellow
		} else {
			Say "Could not stay connected to the server. Most likely Levi hasn't registered your key yet, or the browser sign-in didn't finish." Red
			Say 'Type nt again and sign in with your @nascentech.com Google account. Still stuck? Run: clv key   and text that line to Levi.' Yellow
		}
		Say "<-- Still on your own computer ($Here)."
		exit $Rc
	}
	'setup' { Invoke-Setup }
	'key' {
		if (-not (Test-Path -LiteralPath "$Key.pub")) { Say 'No key yet. Run: clv setup' Red; exit 1 }
		Show-KeyMessage
	}
	'update' {
		[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
		try { $Src = Invoke-RestMethod -UseBasicParsing $InstallUrl } catch { Fail 'Could not download the installer. Check your internet connection and try again.' }
		Invoke-Expression $Src
	}
	{ $_ -in 'version', '--version', '-v' } { Say "clv $ClvVersion" }
	{ $_ -in 'help', '--help', '-h' } { Show-Usage }
	default {
		Say "clv: unknown command `"$Cmd`"" Red
		Show-Usage
		exit 2
	}
}
'@
		[IO.File]::WriteAllText($ClvPs1, $ClvSource.Replace("`r`n", "`n") + "`n", $Utf8)
		[IO.File]::WriteAllText((Join-Path $Bin 'clv.cmd'),
			"@echo off`r`nrem $Marker`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0clv.ps1`" %*`r`n", $Utf8)
		[IO.File]::WriteAllText((Join-Path $Bin 'nt.cmd'),
			"@echo off`r`nrem $Marker`: nt is short for clv login`r`n`"%~dp0clv.cmd`" login %*`r`n", $Utf8)

		# Run setup in a child PowerShell: a script file can be blocked by execution
		# policy where `irm | iex` is not, and -ExecutionPolicy Bypass covers that.
		$PsExe = (Get-Process -Id $PID).Path
		$env:CLV_FROM_INSTALLER = '1'
		try { & $PsExe -NoProfile -ExecutionPolicy Bypass -File $ClvPs1 setup } finally { Remove-Item Env:CLV_FROM_INSTALLER -ErrorAction SilentlyContinue }
		# `irm | iex` runs in the caller's session, so this makes `nt` work in this same window.
		$Sep = [IO.Path]::PathSeparator
		if ($LASTEXITCODE -eq 0 -and ($env:Path -split $Sep) -notcontains $Bin) { $env:Path = "$env:Path$Sep$Bin" }
	} catch {
		$msg = $_.Exception.Message
		if ($msg -like 'NT_SETUP: *') { $msg = $msg.Substring(10) } else { $msg = "Something went wrong: $msg" }
		Write-Host ''
		if ($UseColor) { Write-Host "Setup stopped: $msg" -ForegroundColor Red } else { Write-Host "Setup stopped: $msg" }
	}
}
