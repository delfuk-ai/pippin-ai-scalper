$ErrorActionPreference="Stop"
Write-Host "=== I AM2 CONTROL BRIDGE V2 ===" -ForegroundColor Cyan
$root="C:\LIVE AI\I_AM2_SYNC"
$dst=Join-Path $root "control_bridge"
$agent=Join-Path $dst "agent.py"
$state=Join-Path $dst "bridge_state.json"
$stdout=Join-Path $dst "bridge_stdout.log"
$stderr=Join-Path $dst "bridge_stderr.log"
$remoteRepo="delfuk-ai/i-am2-control-center"
$remotePath="integrations/aifo_control_bridge/agent.py"

$gh=(Get-Command gh -ErrorAction SilentlyContinue)
if(-not $gh){
  $candidate="C:\Program Files\GitHub CLI\gh.exe"
  if(Test-Path $candidate){$gh=Get-Item $candidate}
}
if(-not $gh){throw "GitHub CLI not found"}

& $gh.Source auth status
if($LASTEXITCODE -ne 0){throw "GitHub CLI is not authenticated"}

New-Item -ItemType Directory -Path $dst -Force | Out-Null
$b64=& $gh.Source api "repos/$remoteRepo/contents/$remotePath" --jq ".content"
if($LASTEXITCODE -ne 0){throw "Cannot download private bridge agent"}
$joined=($b64 -join "") -replace "\s",""
[IO.File]::WriteAllBytes($agent,[Convert]::FromBase64String($joined))

$py=(Get-Command python -ErrorAction Stop).Source
$pyw=Join-Path (Split-Path $py) "pythonw.exe"
if(-not (Test-Path $pyw)){$pyw=$py}

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object {$_.Name -match '^pythonw?\.exe$' -and $_.CommandLine -like '*control_bridge\agent.py*'} |
  ForEach-Object {Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}

Remove-Item $state,$stdout,$stderr -Force -ErrorAction SilentlyContinue
Start-Process -WindowStyle Hidden $pyw -ArgumentList ('"'+$agent+'"') -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Start-Sleep -Seconds 20

if(Test-Path $state){
  $x=Get-Content $state -Raw | ConvertFrom-Json
  if($x.status -eq "ONLINE"){
    Write-Host ("BRIDGE STATUS: "+$x.status) -ForegroundColor Green
    Write-Host ("HEARTBEAT ISSUE: #"+$x.heartbeat_issue) -ForegroundColor Green
  }else{
    Write-Host ("BRIDGE STATUS: "+$x.status) -ForegroundColor Red
    if($x.stage){Write-Host ("STAGE: "+$x.stage) -ForegroundColor Yellow}
    if($x.error){Write-Host ("ERROR: "+$x.error) -ForegroundColor Red}
  }
}else{
  Write-Host "BRIDGE STATUS: NO STATE FILE" -ForegroundColor Red
}
if(Test-Path $stderr){
  $tail=Get-Content $stderr -Tail 20 -ErrorAction SilentlyContinue
  if($tail){Write-Host "STDERR:" -ForegroundColor Yellow; $tail}
}
