# score.ps1 - score how well /project-init scaffolded a project (Windows). Same checks as score.sh.
#   score.cmd [PROJECT_DIR] [--agent NAME] [--model NAME] [--write]
# Prints one line per check and a score; --write saves .agents\state\init-report.md. Keep ASCII only.
$ErrorActionPreference = 'Stop'
$proj = '.'; $agent = 'unknown'; $model = 'unknown'; $write = $false
$a = @($args)
for ($i = 0; $i -lt $a.Count; $i++) {
    if ($a[$i] -eq '--agent') { $agent = $a[$i + 1]; $i++ }
    elseif ($a[$i] -eq '--model') { $model = $a[$i + 1]; $i++ }
    elseif ($a[$i] -eq '--write') { $write = $true }
    else { $proj = $a[$i] }
}
if (-not (Test-Path -LiteralPath $proj -PathType Container)) { Write-Error "not a folder: $proj"; exit 2 }
Set-Location -LiteralPath $proj
$proj = (Get-Location).Path
$Utf8 = New-Object System.Text.UTF8Encoding($false)

$script:passed = 0; $script:total = 0; $script:lines = New-Object System.Collections.Generic.List[string]
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    $script:total++
    if ($ok) { $script:passed++; $script:lines.Add("- [x] $name") }
    else { $d = ''; if ($detail) { $d = " - $detail" }; $script:lines.Add("- [ ] $name$d") }
}
function Text([string]$p) { if (Test-Path -LiteralPath $p) { return [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $p).Path, $Utf8) } return '' }

$missing = @()
foreach ($f in @('AGENTS.md', 'CLAUDE.md', 'plan.csv', '.agents/roles.md', '.agents/init-manifest',
                 '.agents/wiki/decisions-log.md', '.agents/wiki/learnings.md', '.agents/wiki/open-questions.md', '.agents/wiki/working-process.md')) {
    if (-not (Test-Path -LiteralPath $f)) { $missing += $f }
}
if (-not ((Test-Path -LiteralPath '.agents/tools/plan.sh') -or (Test-Path -LiteralPath '.agents/tools/plan.ps1'))) { $missing += '.agents/tools/plan.ps1' }
Check 'required files exist' ($missing.Count -eq 0) ('missing: ' + ($missing -join ' '))

$left = @()
foreach ($d in @('AGENTS.md', '.agents', '.claude', '.cursor', '.github', '.opencode', 'GEMINI.md')) {
    if (-not (Test-Path -LiteralPath $d)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $d -Recurse -File -Force)) {
        if ($f.FullName -match '[\\/]\.agents[\\/]state[\\/]') { continue }
        if ((Text $f.FullName) -match '\{\{[A-Z_]+\}\}') { $left += $f.FullName.Substring($proj.Length + 1) }
    }
}
Check 'no {{placeholder}} left' ($left.Count -eq 0) ($left -join ' ')

Check "CLAUDE.md is one line '@AGENTS.md'" ((Text 'CLAUDE.md').Trim() -eq '@AGENTS.md')
$am = Text 'AGENTS.md'
Check 'AGENTS.md profile filled' ($am -ne '' -and -not $am.Contains('<one line')) "'<one line' still in the Profile"
Check 'AGENTS.md has a Python line' ($am -match '(?m)^- Python:')
$n = 999; if ($am -ne '') { $n = @($am -split "`n").Count - 1 }
Check 'AGENTS.md short (<= 80 lines)' ($n -le 80) "$n lines"

$header = 'id,title,owner,status,estimate,start,end,dod,mr,reviewer,review,updated,depends,notes'
$pcsv = @(); if (Test-Path -LiteralPath 'plan.csv') { $pcsv = @(Get-Content -LiteralPath 'plan.csv' -Encoding UTF8) }
Check 'plan.csv header exact' ($pcsv.Count -ge 1 -and $pcsv[0].Trim() -eq $header)
Check 'plan.csv has >= 1 task' ($pcsv.Count -ge 2)
$roles = Text '.agents/roles.md'
Check 'roles.md filled' ($roles -ne '' -and $roles -notmatch '<name>|\{\{')
$gi = @(); if (Test-Path -LiteralPath '.gitignore') { $gi = @(Get-Content -LiteralPath '.gitignore') }
Check '.gitignore has agent lines' ((@('.agents/state/', '.agents/*.bak', '__pycache__/') | Where-Object { $gi -notcontains $_ }).Count -eq 0)

if (Test-Path -LiteralPath '.agents/tools/plan.ps1') {
    $ok = $true; $tail = ''
    try { $out = & powershell -NoProfile -ExecutionPolicy Bypass -File '.agents/tools/plan.ps1' list 2>&1; $ok = ($LASTEXITCODE -eq 0); $tail = [string](@($out)[-1]) } catch { $ok = $false; $tail = $_.Exception.Message }
    Check 'plan list works' $ok $tail
}
$doneCmd = $false
foreach ($f in @('.claude/commands/done.md', '.cursor/commands/done.md', '.github/prompts/done.prompt.md', '.opencode/commands/done.md')) { if (Test-Path -LiteralPath $f) { $doneCmd = $true } }
Check 'a /done command exists' $doneCmd

if (Test-Path -LiteralPath '.agents/plan-check') {
    $pc = $false
    foreach ($f in @('.claude/commands/plan-check.md', '.cursor/commands/plan-check.md', '.github/prompts/plan-check.prompt.md', '.opencode/commands/plan-check.md')) { if (Test-Path -LiteralPath $f) { $pc = $true } }
    Check 'a /plan-check command exists' $pc
    $wp = (Text '.agents/wiki/working-process.md') -split "`n"
    $in = $false; $cnt = 0
    foreach ($l in $wp) {
        if ($l -match '^## Standup checks') { $in = $true; continue }
        if ($l -match '^## ') { $in = $false }
        if ($in -and $l -match '^- ') { $cnt++ }
    }
    Check 'Standup checks filled in working-process.md' ($cnt -ge 1) "no bullet line under '## Standup checks'"
    $py = ''
    foreach ($c in @('py', 'python', 'python3')) {
        if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { continue }
        $pre = @(); if ($c -eq 'py') { $pre = @('-3') }
        $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $c @pre -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>&1 | Out-Null
        $good = ($LASTEXITCODE -eq 0); $ErrorActionPreference = $saved
        if ($good) { $py = $c; break }
    }
    if ($py) {
        $pre = @(); if ($py -eq 'py') { $pre = @('-3') }
        $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = (& $py @pre '.agents/plan-check/plan_check.py' --no-fetch 2>&1) -join "`n"
        $ErrorActionPreference = $saved
        Check 'plan_check.py prints a report' ($out.Contains('| ID |')) ''
    } else { [Console]::Error.WriteLine('note: Python 3.8+ not found, skipped the plan_check.py run') }
}

foreach ($l in $script:lines) { Write-Output $l }
Write-Output ''
Write-Output ("score {0}/{1}" -f $script:passed, $script:total)
if ($write) {
    New-Item -ItemType Directory -Force -Path '.agents/state' | Out-Null
    $research = 'other'; if ($am -match 'Research project: yes') { $research = 'research' }
    $r = @("# init report", "", "- agent: $agent", "- model: $model", "- project type: $research", "- score: $($script:passed)/$($script:total)", "", "## Objective checks") + $script:lines + @("",
        "## Self-report (the agent fills this in; keep it short, no project secrets or private content)",
        "- Steps of init.md I could not follow as written, and why:",
        "- Places where init.md was ambiguous or contradicted itself:",
        "- Files I had to change beyond the templates (list) and why:",
        "- Questions I asked the user (count) and any I could have answered from the repo:",
        "- Errors hit and how they were fixed:",
        "- Existing files I merged into instead of creating (list):",
        "- One change to init.md or the templates that would have saved the most effort:")
    [System.IO.File]::WriteAllText((Join-Path $proj '.agents/state/init-report.md'), (($r -join "`n") + "`n"), $Utf8)
    Write-Output "report written: $proj\.agents\state\init-report.md"
}
if ($script:passed -ne $script:total) { exit 1 }
