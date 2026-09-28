$ErrorActionPreference="Stop"
Write-Host "=== I AM2 AIFO CONTROL BRIDGE BOOTSTRAP ===" -ForegroundColor Cyan

$root="C:\LIVE AI\I_AM2_SYNC"
$dst=Join-Path $root "control_bridge"
$agent=Join-Path $dst "agent.py"
$repo="delfuk-ai/i-am2-control-center"
$remotePath="integrations/aifo_control_bridge/agent.py"
$taskName="I_AM2_Control_Bridge"

if(-not (Test-Path $root)){ throw "I_AM2 root not found: $root" }

$gh=(Get-Command gh -ErrorAction SilentlyContinue)
if(-not $gh){
  $winget=(Get-Command winget -ErrorAction SilentlyContinue)
  if(-not $winget){ throw "GitHub CLI is missing and winget is unavailable. Install GitHub CLI, then rerun." }
  Write-Host "Installing GitHub CLI..." -ForegroundColor Yellow
  winget install --id GitHub.cli --exact --accept-package-agreements --accept-source-agreements
  $env:Path += ";C:\Program Files\GitHub CLI"
  $gh=(Get-Command gh -ErrorAction SilentlyContinue)
  if(-not $gh){ throw "GitHub CLI install finished but gh is not on PATH. Reopen PowerShell and rerun." }
}

$oldEap=$ErrorActionPreference
$ErrorActionPreference="Continue"
gh auth status 2>$null | Out-Null
$needLogin=($LASTEXITCODE -ne 0)
$ErrorActionPreference=$oldEap
if($needLogin){
  Write-Host "One-time GitHub authorization is required." -ForegroundColor Yellow
  gh auth login --hostname github.com --git-protocol https --web
  if($LASTEXITCODE -ne 0){ throw "GitHub authorization failed." }
}
$oldEap=$ErrorActionPreference
$ErrorActionPreference="Continue"
gh auth status
$authOk=($LASTEXITCODE -eq 0)
$ErrorActionPreference=$oldEap
if(-not $authOk){ throw "GitHub is still not authorized." }

New-Item -ItemType Directory -Path $dst -Force | Out-Null

Write-Host "Downloading private bridge agent..." -ForegroundColor Cyan
$b64 = gh api "repos/$repo/contents/$remotePath" --jq '.content'
if($LASTEXITCODE -ne 0){ throw "Cannot read private control-center repository." }
$joined=($b64 -join "") -replace "\s",""
$bytes=[Convert]::FromBase64String($joined)
[IO.File]::WriteAllBytes($agent,$bytes)

$py=(Get-Command python -ErrorAction SilentlyContinue).Source
if(-not $py){ throw "Python not found." }
$pyw=Join-Path (Split-Path $py) "pythonw.exe"
if(-not (Test-Path $pyw)){ $pyw=$py }

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object {$_.Name -match '^pythonw?\.exe$' -and $_.CommandLine -like '*control_bridge\agent.py*'} |
  ForEach-Object {Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}

$action=New-ScheduledTaskAction -Execute $pyw -Argument ('"'+$agent+'"')
$trigger=New-ScheduledTaskTrigger -AtLogOn
$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

try{
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "I AM2 GitHub control bridge" -Force | Out-Null
  Write-Host "Scheduled task created: $taskName" -ForegroundColor Green
}catch{
  Write-Host "Scheduled Task unavailable; using Startup folder fallback." -ForegroundColor Yellow
  $startup=[Environment]::GetFolderPath("Startup")
  $cmd=Join-Path $startup "I_AM2_Control_Bridge.cmd"
  $cmdContent='@echo off'+[Environment]::NewLine+'"'+$pyw+'" "'+$agent+'"'
  $cmdContent | Set-Content $cmd -Encoding ASCII
}

Start-Process -WindowStyle Hidden $pyw -ArgumentList ('"'+$agent+'"')
Start-Sleep -Seconds 6

$state=Join-Path $dst "bridge_state.json"
if(Test-Path $state){
  $x=Get-Content $state -Raw | ConvertFrom-Json
  Write-Host ("BRIDGE STATUS: "+$x.status) -ForegroundColor Green
  Write-Host ("REPO: "+$x.repo)
  Write-Host ("HEARTBEAT ISSUE: #"+$x.heartbeat_issue)
}else{
  Write-Host "Bridge process started, but state file is not ready yet. Wait 15 seconds." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Remote Desktop Commander is no longer required for normal I AM2 control." -ForegroundColor Green
