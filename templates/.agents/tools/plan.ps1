# plan.ps1 - print plan.csv with a done-percentage and late tasks marked. Read-only.
#   plan.ps1 list [--owner NAME] [--status todo|in-progress|done]
# Edit plan.csv itself to change a task (one row per task, keep the header).
# The plan is <project>\plan.csv, or $env:PLAN_CSV. Keep this file ASCII only.
$ErrorActionPreference = 'Stop'
$cmd = 'list'; $owner = ''; $status = ''
$a = @($args)
if ($a.Count -gt 0 -and $a[0] -notlike '--*') { $cmd = $a[0]; $a = @($a | Select-Object -Skip 1) }
for ($i = 0; $i -lt $a.Count; $i++) {
    if ($a[$i] -eq '--owner' -and $i + 1 -lt $a.Count) { $owner = $a[$i + 1]; $i++ }
    elseif ($a[$i] -eq '--status' -and $i + 1 -lt $a.Count) { $status = $a[$i + 1]; $i++ }
    else { Write-Error "unknown option: $($a[$i])"; exit 2 }
}
if ($cmd -ne 'list') { Write-Error 'usage: plan.ps1 list [--owner NAME] [--status STATUS]'; exit 2 }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$plan = if ($env:PLAN_CSV) { $env:PLAN_CSV } else { Join-Path $root 'plan.csv' }
if (-not (Test-Path -LiteralPath $plan)) { Write-Error "plan not found: $plan"; exit 1 }

$today = (Get-Date).ToString('yyyy-MM-dd')
$rows = @(Import-Csv -LiteralPath $plan | Where-Object { $_.id })
$total = $rows.Count
$done = @($rows | Where-Object { $_.status -eq 'done' }).Count
foreach ($r in $rows) {
    if ($owner -and $r.owner -ne $owner) { continue }
    if ($status -and $r.status -ne $status) { continue }
    $late = ''
    if ($r.end -and $r.end -lt $today -and $r.status -ne 'done') { $late = ' LATE' }
    Write-Output ('{0,-10} {1,-12} {2,-12} {3,-9} {4,-10} {5}{6}' -f $r.id, $r.status, $r.owner, $r.review, $r.end, $r.title, $late)
}
Write-Output ''
if ($total -gt 0) { Write-Output ('{0}/{1} done ({2}%)' -f $done, $total, [int][math]::Floor(100 * $done / $total)) }
else { Write-Output '0/0 done' }
