# nt client kit installer (Windows 10/11, PowerShell 5+).
#
#   irm https://raw.githubusercontent.com/LeviHirsch/homebrew-tap/main/nt/install.ps1 | iex
#
# Sets up `nt`, a one-word login to the NascenTech server:
#   - cloudflared in %LOCALAPPDATA%\nt\bin (or reuses one already on PATH)
#   - an SSH key at %USERPROFILE%\.ssh\id_ed25519_nt
#   - a "Host nt" entry in .ssh\config.d\nt, included from .ssh\config
#   - an `nt` command (nt.cmd) in %LOCALAPPDATA%\nt\bin, added to your user PATH
# No admin rights. Safe to run again.
#
# Test overrides: $env:NT_NAME skips the name prompt.

# Runs inside a script block so `irm | iex` never closes the window on failure
# and nothing leaks into the caller's session.
& {
	$ErrorActionPreference = 'Stop'
	$ProgressPreference = 'SilentlyContinue'

	$NtHostName = 'ssh.nascentech.com'
	$NtUser = 'nascentech'
	$Marker = '# Written by the nt installer'
	$CfUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'

	$OnWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
	$LocalAppData = $env:LOCALAPPDATA
	if (-not $LocalAppData) { $LocalAppData = Join-Path $HOME 'AppData\Local' }
	$Bin = Join-Path $LocalAppData 'nt\bin'
	$SshDir = Join-Path $HOME '.ssh'
	$Key = Join-Path $SshDir 'id_ed25519_nt'
	$Conf = Join-Path $SshDir 'config'
	$ConfD = Join-Path $SshDir 'config.d'
	$NtConf = Join-Path $ConfD 'nt'
	$Utf8 = New-Object System.Text.UTF8Encoding($false)

	function Say([string]$Text) { Write-Host $Text }
	function Fail([string]$Text) { throw [System.Exception]::new("NT_SETUP: $Text") }

	try {
		Say ''
		Say 'Setting up nt (NascenTech server login).'
		Say ''

		# --- OpenSSH client (built into Windows 10/11, sometimes switched off)
		$Ssh = Get-Command ssh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
		$SshKeygen = Get-Command ssh-keygen -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
		if (-not $Ssh -or -not $SshKeygen) {
			Fail ("The Windows OpenSSH client is not turned on. Open Settings > Apps > Optional features > " +
				"Add a feature (or 'View features'), install 'OpenSSH Client', then open a new PowerShell and run this again.")
		}

		# --- Stop if some other "Host nt" already exists
		if ((Test-Path $NtConf) -and -not (Select-String -Path $NtConf -SimpleMatch $Marker -Quiet)) {
			Fail "$NtConf already exists and was not made by this installer. Move it aside and run this again."
		}
		$ToCheck = @()
		if (Test-Path $Conf) { $ToCheck += $Conf }
		if (Test-Path $ConfD) { $ToCheck += Get-ChildItem $ConfD -File | Where-Object { $_.FullName -ne $NtConf } | ForEach-Object { $_.FullName } }
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

		New-Item -ItemType Directory -Force -Path $Bin, $SshDir | Out-Null

		# --- cloudflared
		$Found = Get-Command cloudflared -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($Found) {
			$Cf = $Found.Source
			Say "Using cloudflared already installed at $Cf"
		} else {
			$Cf = Join-Path $Bin 'cloudflared.exe'
			if (Test-Path $Cf) {
				Say "cloudflared already installed at $Cf"
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
				Say "Installed cloudflared at $Cf"
			}
		}

		# --- SSH key
		if (Test-Path $Key) {
			Say "Using your existing key at $Key"
			if (-not (Test-Path "$Key.pub")) {
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
			if ($p.ExitCode -ne 0 -or -not (Test-Path "$Key.pub")) { Fail 'Could not create your SSH key.' }
			Say "Created your key at $Key"
		}

		# --- Host block
		New-Item -ItemType Directory -Force -Path $ConfD | Out-Null
		$Block = @(
			"$Marker. Safe to delete; run the installer again to recreate."
			'Host nt'
			"  HostName $NtHostName"
			"  User $NtUser"
			"  ProxyCommand `"$Cf`" access ssh --hostname %h"
			'  IdentityFile ~/.ssh/id_ed25519_nt'
			'  IdentitiesOnly yes'
		) -join "`n"
		[IO.File]::WriteAllText($NtConf, $Block + "`n", $Utf8)
		Say "Wrote $NtConf"

		# --- Include line at the top of .ssh\config, once; existing lines kept as-is below it
		$HasInclude = $false
		if (Test-Path $Conf) {
			foreach ($line in [IO.File]::ReadAllLines($Conf)) {
				$words = $line.Trim() -split '\s+'
				if ($words[0] -eq 'host' -or $words[0] -eq 'match') { break }
				if ($words[0] -eq 'include' -and $words.Count -ge 2 -and ($words[1] -eq '~/.ssh/config.d/*' -or $words[1] -eq 'config.d/*')) { $HasInclude = $true; break }
			}
		}
		if (-not $HasInclude) {
			$Old = [byte[]]@()
			if (Test-Path $Conf) {
				$Backup = "$Conf.nt-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
				Copy-Item $Conf $Backup
				Say "Backed up your SSH config to $Backup"
				$Old = [IO.File]::ReadAllBytes($Conf)
				# Drop a UTF-8 byte-order mark (Notepad adds one) so it doesn't land mid-file.
				if ($Old.Length -ge 3 -and $Old[0] -eq 0xEF -and $Old[1] -eq 0xBB -and $Old[2] -eq 0xBF) {
					if ($Old.Length -eq 3) { $Old = [byte[]]@() } else { $Old = $Old[3..($Old.Length - 1)] }
				}
			}
			$New = $Utf8.GetBytes("Include ~/.ssh/config.d/*`n`n") + $Old
			[IO.File]::WriteAllBytes("$Conf.nt-tmp", [byte[]]$New)
			Move-Item -Force "$Conf.nt-tmp" $Conf
			Say "Updated $Conf"
		}

		# --- nt command
		[IO.File]::WriteAllText((Join-Path $Bin 'nt.cmd'), "@echo off`r`nssh nt %*`r`n", $Utf8)

		# --- user PATH
		if ($OnWindows) {
			$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
			$Parts = @()
			if ($UserPath) { $Parts = $UserPath -split ';' | Where-Object { $_ } }
			if ($Parts -notcontains $Bin) {
				[Environment]::SetEnvironmentVariable('Path', (@($Parts) + $Bin) -join ';', 'User')
				Say "Added $Bin to your PATH"
			}
		} else {
			Say "(Not Windows: skipped adding $Bin to the user PATH.)"
		}
		if (($env:Path -split ';') -notcontains $Bin) { $env:Path = "$env:Path;$Bin" }

		$PubLine = ([IO.File]::ReadAllText("$Key.pub")).Trim()
		Say ''
		Say 'Done. One more step.'
		Say ''
		Say 'Text this whole line to Levi:'
		Say ''
		Say "  $PubLine"
		Say ''
		Say "When Levi says you're registered, open a new terminal and type: nt"
		Say '(The first time, a browser window opens: sign in with your @nascentech.com Google account.)'
		Say ''
	} catch {
		$msg = $_.Exception.Message
		if ($msg -like 'NT_SETUP: *') { $msg = $msg.Substring(10) } else { $msg = "Something went wrong: $msg" }
		Write-Host ''
		Write-Host "Setup stopped: $msg" -ForegroundColor Red
	}
}
