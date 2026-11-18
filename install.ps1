#Requires -Version 5.1
<#
.SYNOPSIS
  William — one-click Windows installer. Turns this laptop into a headless, always-on
  WhatsApp-assistant server: WSL2 + Ubuntu 24.04, never-sleep power config, a boot task
  that keeps the WSL VM up without login, then hands off to wsl/setup.sh inside WSL.

.DESCRIPTION
  Run in an ELEVATED PowerShell:
      irm https://raw.githubusercontent.com/Diego-II/william-public/main/install.ps1 | iex
  or from a clone:
      powershell -ExecutionPolicy Bypass -File .\install.ps1

  Phase 1 configures Windows (power, WSL, boot task) and may reboot once to enable WSL.
  Phase 2 (auto-resumed after reboot) provisions Ubuntu and runs the in-WSL setup, which
  is interactive on first run (you enter secrets and scan the WhatsApp QR on a temp screen).

.NOTES
  Distro: Ubuntu-24.04.  In-WSL Linux user: hermes.  Repo checkout: /home/hermes/william.
#>
[CmdletBinding()]
param(
    [string]$RepoUrl   = "https://github.com/Diego-II/william-public.git",
    [string]$Branch    = "main",
    [string]$GitHubToken = "",          # optional PAT to clone a private repo over HTTPS
    [int]   $WslMemoryGb = 6,
    [ValidateSet("1", "2")]
    [string]$Phase     = "1"            # internal: RunOnce sets this to "2" after reboot
)

$ErrorActionPreference = "Stop"
$Distro    = "Ubuntu-24.04"
$LinuxUser = "hermes"
$RepoPath  = "/home/$LinuxUser/william"
$StateDir  = Join-Path $env:ProgramData "william"
$SelfCopy  = Join-Path $StateDir "install.ps1"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [ok] $msg" -ForegroundColor Green }
function Write-Warn2($m)  { Write-Host "  [!] $m"  -ForegroundColor Yellow }

function Assert-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this in an ELEVATED PowerShell (Run as Administrator)."
    }
}

# Persist a local copy so the post-reboot RunOnce has a real file to execute
# (important when the script was piped in via `irm | iex`).
function Save-SelfCopy {
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        Copy-Item $PSCommandPath $SelfCopy -Force
    } elseif (-not (Test-Path $SelfCopy)) {
        Invoke-WebRequest "https://raw.githubusercontent.com/Diego-II/william-public/$Branch/install.ps1" `
            -OutFile $SelfCopy -UseBasicParsing
    }
}

function Set-RunOncePhase2 {
    $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$SelfCopy`" -Phase 2 -RepoUrl `"$RepoUrl`" -Branch `"$Branch`" -WslMemoryGb $WslMemoryGb"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
        -Name "WilliamSetupPhase2" -Value $cmd
    Write-Ok "Phase 2 will auto-resume after reboot (login on the temp screen)."
}

function Set-PowerAlwaysOn {
    Write-Step "Power: never sleep, lid-close = do nothing"
    foreach ($t in @("standby-timeout-ac","standby-timeout-dc","hibernate-timeout-ac","hibernate-timeout-dc")) {
        & powercfg /change $t 0 | Out-Null
    }
    & powercfg /change monitor-timeout-ac 0 | Out-Null
    # Lid close action = 0 (Do Nothing), AC and DC
    & powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 | Out-Null
    & powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 | Out-Null
    & powercfg -SetActive SCHEME_CURRENT | Out-Null
    & powercfg /hibernate off 2>$null | Out-Null
    Write-Ok "Power configured. Verify true sleep states later with: powercfg /a"
    Write-Warn2 "Some laptops only expose Modern Standby (S0) and may still nap lid-closed — confirm after boot."
}

function Test-WslReady {
    try { wsl.exe --status *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

function Ensure-Wsl {
    Write-Step "WSL2 runtime"
    if (Test-WslReady) {
        wsl.exe --set-default-version 2 | Out-Null
        wsl.exe --update | Out-Null
        Write-Ok "WSL2 present and updated."
        return $false   # no reboot needed
    }
    Write-Warn2 "WSL not ready — enabling features + installing (a reboot will be required)."
    & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
    & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
    try { wsl.exe --install --no-launch --web-download | Out-Null } catch { }
    return $true        # reboot needed
}

function Ensure-Ubuntu {
    Write-Step "Ubuntu $Distro"
    $installed = (wsl.exe -l -q) -replace "`0","" | ForEach-Object { $_.Trim() }
    if ($installed -notcontains $Distro) {
        wsl.exe --install --no-launch -d $Distro --web-download | Out-Null
        Write-Ok "$Distro installed (no-launch)."
    } else {
        Write-Ok "$Distro already installed."
    }
    wsl.exe --set-version $Distro 2 2>$null | Out-Null
}

function Write-WslConfig {
    $path = Join-Path $env:USERPROFILE ".wslconfig"
    @"
[wsl2]
memory=${WslMemoryGb}GB
swap=2GB
# Keep networking simple/outbound; the gateway only needs egress.
"@ | Set-Content -Path $path -Encoding ASCII
    Write-Ok ".wslconfig written ($WslMemoryGb GB cap)."
}

function Invoke-WslBootstrap {
    Write-Step "Bootstrapping inside $Distro (as root)"
    # 1) base packages + git
    wsl.exe -d $Distro -u root -- bash -lc "apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y git ca-certificates curl sudo" | Out-Host
    # 2) create the hermes user if missing
    wsl.exe -d $Distro -u root -- bash -lc "id -u $LinuxUser >/dev/null 2>&1 || (useradd -m -s /bin/bash $LinuxUser && usermod -aG sudo $LinuxUser && echo '$LinuxUser ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/$LinuxUser)" | Out-Host
    # 2.5) enable systemd + default user, then restart the distro so systemd becomes PID 1
    #      (must happen BEFORE setup.sh, which uses systemctl)
    wsl.exe -d $Distro -u root -- bash -lc "printf '[boot]\nsystemd=true\n\n[user]\ndefault=$LinuxUser\n' >/etc/wsl.conf" | Out-Host
    Write-Ok "Enabled systemd in $Distro; restarting the distro..."
    wsl.exe --shutdown | Out-Null
    Start-Sleep -Seconds 6
    wsl.exe -d $Distro -u root -- bash -lc "for i in \$(seq 1 30); do [ \"\$(ps -p 1 -o comm=)\" = systemd ] && break; sleep 1; done; ps -p 1 -o comm=" | Out-Host
    # 3) clone or update the repo as hermes
    $cloneUrl = $RepoUrl
    if ($GitHubToken -and $RepoUrl -match "^https://github.com/") {
        $cloneUrl = $RepoUrl -replace "^https://", "https://$GitHubToken@"
    }
    wsl.exe -d $Distro -u $LinuxUser -- bash -lc "set -e; if [ -d $RepoPath/.git ]; then cd $RepoPath && git pull --ff-only; else git clone --branch $Branch '$cloneUrl' $RepoPath; fi; git -C $RepoPath remote set-url origin '$RepoUrl'" | Out-Host
    # 4) hand off to the Linux setup (interactive: secrets + WhatsApp QR on this screen)
    Write-Step "Running in-WSL setup (interactive — keep this screen attached)"
    wsl.exe -d $Distro -u $LinuxUser -- bash -lc "cd $RepoPath && chmod +x wsl/setup.sh scripts/*.sh && ./wsl/setup.sh" | Out-Host
}

function New-KeepAliveTask {
    Write-Step "Boot task: keep the WSL VM up without login"
    $action  = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d $Distro -u root -e sleep infinity"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                  -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
                  -ExecutionTimeLimit ([TimeSpan]::Zero)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "William-WSL-KeepAlive" -Action $action -Trigger $trigger `
        -Settings $set -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName "William-WSL-KeepAlive"
    Write-Ok "Boot task registered (Layer A). systemd in WSL handles the services (Layer B)."
}

# ───────────────────────────── main ─────────────────────────────
Assert-Admin
Save-SelfCopy
Write-Host "William installer — phase $Phase" -ForegroundColor Magenta

if ($Phase -eq "1") {
    Set-PowerAlwaysOn
    $needReboot = Ensure-Wsl
    Write-WslConfig
    if ($needReboot) {
        Set-RunOncePhase2
        Write-Warn2 "Rebooting in 10s to finish enabling WSL2. Setup resumes automatically."
        Start-Sleep -Seconds 10
        Restart-Computer -Force
        return
    }
    # WSL already usable — continue straight into phase 2 work
    $Phase = "2"
}

if ($Phase -eq "2") {
    Ensure-Ubuntu
    Write-WslConfig
    Invoke-WslBootstrap
    New-KeepAliveTask
    Write-Host "`n✅ William is installed." -ForegroundColor Green
    Write-Host "   • Services run under systemd in $Distro (check: wsl -d $Distro -u $LinuxUser systemctl status hermes)" -ForegroundColor Green
    Write-Host "   • You can now detach the screen. Deploy updates inside WSL with: ~/william/scripts/deploy.sh" -ForegroundColor Green
}
