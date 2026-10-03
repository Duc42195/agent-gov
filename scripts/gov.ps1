# gov.ps1 - copy, inspect and upgrade the agent-gov scaffold in a project (Windows).
# Same commands, output and manifest as gov.sh, so a project can use either. Keep this file ASCII only.
#
#   gov.cmd detect   <project>                          facts about the project, for the agent to confirm
#   gov.cmd scaffold <project> --vars FILE              copy the templates (never overwrites a file)
#   gov.cmd upgrade  <project> [--vars FILE] [--apply]  plan (default) or apply an upgrade
#   gov.cmd record   <project> <path>...                after you merged <path>.agent-gov-new into <path>
#
# FILE holds KEY=VALUE lines (one line per value). See gov.sh for the list of keys and the rules:
# a file equal to the template hash in .agents/init-manifest is "unmodified" and is replaced on
# upgrade; a modified file is never overwritten (the new version goes to <file>.agent-gov-new).
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Repo = Split-Path -Parent $Here
$Tpl = Join-Path $Repo 'templates'
$Version = (Get-Content -LiteralPath (Join-Path $Repo 'VERSION') -Raw).Trim()
$ManifestRel = '.agents/init-manifest'
$Tab = "`t"

function Die([string]$m) { [Console]::Error.WriteLine("gov.ps1: $m"); exit 2 }

# -- hashing: bytes without CR, so Windows checkouts compare equal (same as gov.sh) ------------
function Hash-Bytes([byte[]]$b) {
    $kept = New-Object System.Collections.Generic.List[byte]
    foreach ($x in $b) { if ($x -ne 13) { $kept.Add($x) } }
    $h = [System.Security.Cryptography.SHA256]::Create().ComputeHash($kept.ToArray())
    return (($h | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Hash-File([string]$p) { return (Hash-Bytes ([System.IO.File]::ReadAllBytes($p))) }
function Hash-Text([string]$t) { return (Hash-Bytes ($Utf8.GetBytes($t))) }

# -- variables --------------------------------------------------------------
function Env-Var([string]$key) {
    $f = Join-Path $Repo '.env'
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    foreach ($l in (Get-Content -LiteralPath $f)) { if ($l.StartsWith("$key=")) { return $l.Substring($key.Length + 1) } }
    return ''
}
function Read-Vars([string]$file, [System.Collections.IDictionary]$into) {
    foreach ($l in (Get-Content -LiteralPath $file -Encoding UTF8)) {
        if ($l -match '^([A-Z_]+)=(.*)$') { $into[$Matches[1]] = $Matches[2] }
    }
}
function Make-Vars([string]$proj, [string]$extra) {
    $v = [ordered]@{}
    $py = Env-Var 'AGENT_GOV_PY'
    if (-not $py -or $py -eq 'none') { $py = 'python' }
    $sh = Env-Var 'AGENT_GOV_SHELL'
    $plan = 'powershell -NoProfile -File .agents/tools/plan.ps1'
    if ($sh -in @('bash', 'zsh', 'fish', 'git-bash', 'wsl')) { $plan = 'bash .agents/tools/plan.sh' }
    $gu = ''
    try { $gu = (& git -C $proj config user.name 2>$null) } catch { $gu = '' }
    if (-not $gu) { $gu = 'me' }
    $v['PROJECT_NAME'] = Split-Path -Leaf $proj
    $v['WHAT'] = '<one line: what this project is>'; $v['GOAL'] = '<one line: what done looks like>'
    $v['STACK'] = 'docs only'; $v['IS_RESEARCH'] = 'no'; $v['TASK_KEY'] = 'TASK'; $v['GIT_HOST'] = 'none'
    $v['DEFAULT_BRANCH'] = 'main'; $v['EXTERNAL_TRACKER'] = 'none'; $v['GATE_CMD'] = ''
    $v['PY'] = $py; $v['PLAN'] = $plan
    $v['ROLE_NAME'] = $gu; $v['ROLE'] = 'maintainer'; $v['ROLE_OWNS'] = 'everything'
    $v['AGENTS'] = 'claude'; $v['PLAN_CHECK'] = 'no'
    $mf = Join-Path $proj $ManifestRel
    if (Test-Path -LiteralPath $mf) {
        foreach ($l in (Get-Content -LiteralPath $mf -Encoding UTF8)) {
            if ($l -match '^var ([A-Z_]+)=(.*)$') { $v[$Matches[1]] = $Matches[2] }
        }
    }
    if ($extra) { Read-Vars $extra $v }
    return $v
}
function Render([System.Collections.IDictionary]$vars, [string]$src) {
    $t = [System.IO.File]::ReadAllText((Join-Path $Tpl $src), $Utf8)
    foreach ($k in $vars.Keys) { $t = $t.Replace('{{' + $k + '}}', [string]$vars[$k]) }
    return $t
}

# -- which template files belong in this project -----------------------------
function Has-Item([string]$list, [string]$item) { return ((',' + $list + ',') -like ('*,' + $item + ',*')) }
# Pairs: array of @{Dest=..; Src=..}; $All ignores the agent / plan-check choice
function Get-Pairs([System.Collections.IDictionary]$vars, [bool]$All) {
    $agents = [string]$vars['AGENTS']; $pc = ([string]$vars['PLAN_CHECK'] -eq 'yes')
    $out = @()
    $files = Get-ChildItem -LiteralPath $Tpl -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($Tpl.Length + 1).Replace('\', '/') } | Sort-Object
    foreach ($src in $files) {
        if ($src -eq 'gitignore.append' -or $src -eq 'pointer.md') { continue }
        $ok = $true
        switch -wildcard ($src) {
            '.agents/plan-check/*'                { $ok = $pc }
            '.claude/commands/done.md'            { $ok = (Has-Item $agents 'claude') }
            '.claude/commands/plan-check.md'      { $ok = ((Has-Item $agents 'claude') -and $pc) }
            '.cursor/commands/done.md'            { $ok = (Has-Item $agents 'cursor') }
            '.cursor/commands/plan-check.md'      { $ok = ((Has-Item $agents 'cursor') -and $pc) }
            '.github/prompts/done.prompt.md'      { $ok = (Has-Item $agents 'copilot') }
            '.github/prompts/plan-check.prompt.md' { $ok = ((Has-Item $agents 'copilot') -and $pc) }
            '.opencode/commands/done.md'          { $ok = (Has-Item $agents 'opencode') }
            '.opencode/commands/plan-check.md'    { $ok = ((Has-Item $agents 'opencode') -and $pc) }
        }
        if ($ok -or $All) { $out += , @{ Dest = $src; Src = $src } }
    }
    if ($All -or (Has-Item $agents 'copilot')) { $out += , @{ Dest = '.github/copilot-instructions.md'; Src = 'pointer.md' } }
    if ($All -or (Has-Item $agents 'gemini')) { $out += , @{ Dest = 'GEMINI.md'; Src = 'pointer.md' } }
    return $out
}
function Placeholder-Free([string]$src) {
    return (-not ([System.IO.File]::ReadAllText((Join-Path $Tpl $src), $Utf8)).Contains('{{'))
}

# -- manifest ----------------------------------------------------------------
function Manifest-Table([string]$proj) {  # dest -> hash recorded by the last scaffold / upgrade
    $t = [ordered]@{}
    $mf = Join-Path $proj $ManifestRel
    if (Test-Path -LiteralPath $mf) {
        foreach ($l in (Get-Content -LiteralPath $mf -Encoding UTF8)) {
            $p = $l -split "`t"
            if ($p.Count -ge 3 -and $p[0] -eq 'file') { $t[$p[2]] = $p[1] }
        }
    }
    return $t
}
function Write-Manifest([string]$proj, [System.Collections.IDictionary]$vars, [System.Collections.IDictionary]$table) {
    New-Item -ItemType Directory -Force -Path (Join-Path $proj '.agents') | Out-Null
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# agent-gov manifest, written by scripts/gov.sh. Do not edit by hand.')
    $lines.Add("version $Version")
    foreach ($k in $vars.Keys) { $lines.Add("var $k=$($vars[$k])") }
    foreach ($d in ($table.Keys | Sort-Object)) { $lines.Add("file`t$($table[$d])`t$d") }
    [System.IO.File]::WriteAllText((Join-Path $proj $ManifestRel), (($lines -join "`n") + "`n"), $Utf8)
}
function Write-Out([string]$path, [string]$text) {
    $dir = Split-Path -Parent $path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [System.IO.File]::WriteAllText($path, $text, $Utf8)
}

# -- old releases: does any released tag carry exactly this file? -------------
function Git-Show([string]$tag, [string]$path) {
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & git -C $Repo show "${tag}:templates/$path" 2>$null
    $ok = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $saved
    if (-not $ok) { return $null }
    return (($o -join "`n") + "`n")
}
function Tags() {
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $t = @(& git -C $Repo tag -l 'v*' 2>$null)
    $ErrorActionPreference = $saved
    return $t
}
function Hist-Has([string]$src, [string]$hash) {
    foreach ($tag in (Tags)) {
        $c = Git-Show $tag $src
        if ($c -ne $null -and (Hash-Text $c) -eq $hash) { return $true }
    }
    return $false
}

# ============================================================================
function Cmd-Detect([string]$proj) {
    if (-not (Test-Path -LiteralPath $proj -PathType Container)) { Die "not a folder: $proj" }
    $p = (Resolve-Path -LiteralPath $proj).Path
    Write-Output "project=$p"; Write-Output "gov_version=$Version"
    $mf = Join-Path $p $ManifestRel
    if (Test-Path -LiteralPath $mf) {
        $mv = ''; foreach ($l in (Get-Content -LiteralPath $mf)) { if ($l.StartsWith('version ')) { $mv = $l.Substring(8) } }
        Write-Output 'manifest=yes'; Write-Output "manifest_version=$mv"
    } else { Write-Output 'manifest=no' }
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & git -C $p rev-parse --git-dir 2>$null | Out-Null
    $isGit = ($LASTEXITCODE -eq 0)
    if ($isGit) {
        $url = (& git -C $p remote get-url origin 2>$null)
        $br = (& git -C $p symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
        if ($br) { $br = $br -replace '^origin/', '' } else { $br = (& git -C $p branch --show-current 2>$null) }
        $host_ = 'other'
        if (-not $url) { $host_ = 'none' } elseif ($url -like '*github*') { $host_ = 'GitHub' } elseif ($url -like '*gitlab*') { $host_ = 'GitLab' }
        if (-not $br) { $br = 'main' }
        Write-Output 'git=yes'; Write-Output "remote=$url"; Write-Output "git_host=$host_"; Write-Output "default_branch=$br"
        Write-Output "git_user=$(& git -C $p config user.name 2>$null)"
    } else { Write-Output 'git=no' }
    $ErrorActionPreference = $saved
    $dirs = @()
    foreach ($pair in @('claude:.claude', 'cursor:.cursor', 'opencode:.opencode', 'gemini:.gemini', 'copilot:.github/prompts')) {
        $n, $d = $pair -split ':', 2
        if (Test-Path -LiteralPath (Join-Path $p $d)) { $dirs += $n }
    }
    Write-Output ('agent_dirs=' + ($dirs -join ','))
    $am = Join-Path $p 'AGENTS.md'
    if (Test-Path -LiteralPath $am) {
        Write-Output 'agents_md=yes'
        $text = Get-Content -LiteralPath $am -Encoding UTF8
        foreach ($k in @('What', 'Goal', 'Stack', 'Research project', 'Gate command', 'Python')) {
            $line = $text | Where-Object { $_ -match ('^- \**' + [regex]::Escape($k)) } | Select-Object -First 1
            $val = ''
            if ($line) { $val = ($line -replace '^[^:]*:\**\s*', ''); if ($val.Length -gt 160) { $val = $val.Substring(0, 160) } }
            Write-Output ('profile_' + ($k.ToLower() -replace ' ', '_') + '=' + $val)
        }
        $tp = $text | Where-Object { $_ -match 'Task id prefix' } | Select-Object -First 1
        $pref = ''
        if ($tp -and $tp -match 'prefix:?\**\s*`?([A-Za-z0-9_-]+)') { $pref = $Matches[1] }
        Write-Output "task_prefix=$pref"
    } else { Write-Output 'agents_md=no' }
    $pc = Join-Path $p 'plan.csv'
    if (Test-Path -LiteralPath $pc) {
        $ls = @(Get-Content -LiteralPath $pc -Encoding UTF8)
        Write-Output 'plan_csv=yes'; Write-Output ('plan_rows=' + ($ls.Count - 1))
        $hd = $ls[0]; if ($hd.Length -gt 200) { $hd = $hd.Substring(0, 200) }
        Write-Output "plan_header=$hd"
    } else { Write-Output 'plan_csv=no' }
    Write-Output ('roles=' + $(if (Test-Path -LiteralPath (Join-Path $p '.agents/roles.md')) { 'yes' } else { 'no' }))
    Write-Output ('wiki=' + $(if (Test-Path -LiteralPath (Join-Path $p '.agents/wiki')) { 'yes' } else { 'no' }))
    $legacy = @()
    foreach ($f in @('record.md', 'action-history.md', '.agents/record.md', '.agents/action-history.md', 'docs/adr', '.agents/adr', '.agents/tools/check_adr.py', '.agents/tools/plan.py', '.agents/tools/sync_plan.py')) {
        if (Test-Path -LiteralPath (Join-Path $p $f)) { $legacy += $f }
    }
    Write-Output ('legacy=' + ($legacy -join ','))
    $gate = ''
    $pj = Join-Path $p 'package.json'; $mk = Join-Path $p 'Makefile'
    if ((Test-Path -LiteralPath $pj) -and (Select-String -LiteralPath $pj -Pattern '"test"' -Quiet)) { $gate = 'npm test' }
    elseif ((Test-Path -LiteralPath $mk) -and (Select-String -LiteralPath $mk -Pattern '^test:' -Quiet)) { $gate = 'make test' }
    elseif (Test-Path -LiteralPath (Join-Path $p 'go.mod')) { $gate = 'go test ./...' }
    elseif (Test-Path -LiteralPath (Join-Path $p 'Cargo.toml')) { $gate = 'cargo test' }
    elseif ((Test-Path -LiteralPath (Join-Path $p 'pyproject.toml')) -or (Test-Path -LiteralPath (Join-Path $p 'pytest.ini')) -or (Test-Path -LiteralPath (Join-Path $p 'tests'))) { $gate = 'pytest' }
    Write-Output "gate_guess=$gate"
    Write-Output ('env_py=' + (Env-Var 'AGENT_GOV_PY')); Write-Output ('env_shell=' + (Env-Var 'AGENT_GOV_SHELL'))
}

function Parse-Opts([string[]]$a) {
    $o = @{ Vars = ''; Apply = $false; Rest = @() }
    for ($i = 0; $i -lt $a.Count; $i++) {
        if ($a[$i] -eq '--vars') { if ($i + 1 -ge $a.Count) { Die '--vars needs a file' }; $o.Vars = $a[$i + 1]; $i++ }
        elseif ($a[$i] -eq '--apply') { $o.Apply = $true }
        else { $o.Rest += $a[$i] }
    }
    return $o
}

function Cmd-Scaffold([string]$proj, [string]$extra) {
    if (-not (Test-Path -LiteralPath $proj -PathType Container)) { Die "not a folder: $proj" }
    $p = (Resolve-Path -LiteralPath $proj).Path
    if (Test-Path -LiteralPath (Join-Path $p $ManifestRel)) { Die "this project already has a manifest: use 'upgrade' (or delete $ManifestRel to start over)" }
    $vars = Make-Vars $p $extra
    $table = [ordered]@{}
    foreach ($pr in (Get-Pairs $vars $false)) {
        $text = Render $vars $pr.Src
        $table[$pr.Dest] = Hash-Text $text
        $target = Join-Path $p $pr.Dest
        if (Test-Path -LiteralPath $target) { Write-Output "EXISTS$Tab$($pr.Dest)" }
        else { Write-Out $target $text; Write-Output "ADD$Tab$($pr.Dest)" }
        $left = [regex]::Matches($text, '\{\{[A-Z_]*\}\}') | ForEach-Object { $_.Value } | Sort-Object -Unique
        if ($left) { Write-Output "UNSET$Tab$($pr.Dest)$Tab$($left -join ' ')" }
    }
    $ga = Join-Path $Tpl 'gitignore.append'
    if (Test-Path -LiteralPath $ga) {
        $gi = Join-Path $p '.gitignore'
        $have = @(); if (Test-Path -LiteralPath $gi) { $have = @(Get-Content -LiteralPath $gi -Encoding UTF8) }
        foreach ($l in (Get-Content -LiteralPath $ga -Encoding UTF8)) {
            if ($l -and ($have -notcontains $l)) {
                Add-Content -LiteralPath $gi -Value $l -Encoding UTF8
                Write-Output "APPEND$Tab.gitignore$Tab$l"
            }
        }
    }
    Write-Manifest $p $vars $table
    Write-Output "MANIFEST$Tab$ManifestRel"
    Write-Output 'EXISTS means your file was kept as it is: merge the new template by hand if you want its content.'
}

function Cmd-Upgrade([string]$proj, [string]$extra, [bool]$apply) {
    if (-not (Test-Path -LiteralPath $proj -PathType Container)) { Die "not a folder: $proj" }
    $p = (Resolve-Path -LiteralPath $proj).Path
    $limited = -not (Test-Path -LiteralPath (Join-Path $p $ManifestRel))
    if ($limited) {
        Write-Output 'WARNING: no manifest in this project (it was set up by an older agent-gov). Limited mode: only'
        Write-Output '         files that match a released template are replaced; everything else is kept for you to merge.'
    }
    $vars = Make-Vars $p $extra
    $base = Manifest-Table $p
    $table = [ordered]@{}
    $acts = New-Object System.Collections.Generic.List[object]
    function Act([string]$a, [string]$d, [string]$n) { $acts.Add(@{ A = $a; D = $d; N = $n }) }
    foreach ($pr in (Get-Pairs $vars $false)) {
        $dest = $pr.Dest; $src = $pr.Src; $target = Join-Path $p $dest
        if ($limited -and (-not $extra) -and (-not (Placeholder-Free $src))) {
            if (Test-Path -LiteralPath $target) { Act 'UNKNOWN' $dest 'has placeholders and no manifest: cannot tell if you changed it (give --vars to compare)' }
            else { Act 'NEEDS-VARS' $dest 'missing; give --vars to create it' }
            continue
        }
        $text = Render $vars $src; $nh = Hash-Text $text
        $b = ''; if ($base.Contains($dest)) { $b = $base[$dest] }
        if (-not (Test-Path -LiteralPath $target)) {
            Act 'ADD' $dest ''; $table[$dest] = $nh
            if ($apply) { Write-Out $target $text }
            continue
        }
        $cur = Hash-File $target
        if ($cur -eq $nh) { Act 'SAME' $dest ''; $table[$dest] = $nh }
        elseif ($b -eq $nh) { Act 'KEEP' $dest 'your edits; the template did not change'; $table[$dest] = $nh }
        elseif ((($b -ne '') -and ($cur -eq $b)) -or (($b -eq '') -and (Placeholder-Free $src) -and (Hist-Has $src $cur))) {
            Act 'UPDATE' $dest ''; $table[$dest] = $nh
            if ($apply) { Write-Out $target $text }
        } else {
            Act 'CONFLICT' $dest "you changed it and the template changed: merge $dest.agent-gov-new, then: gov record <project> $dest"
            if ($b -ne '') { $table[$dest] = $b }
            if ($apply) { Write-Out ($target + '.agent-gov-new') $text }
        }
    }
    $known = @(Get-Pairs $vars $true | ForEach-Object { $_.Dest })
    if (-not $limited) {
        foreach ($dest in @($base.Keys)) {
            if ($known -contains $dest) { continue }
            $target = Join-Path $p $dest
            if (-not (Test-Path -LiteralPath $target)) { Act 'DROP' $dest 'already gone' }
            elseif ((Hash-File $target) -eq $base[$dest]) { Act 'REMOVE' $dest 'no longer part of agent-gov'; if ($apply) { Remove-Item -LiteralPath $target -Force } }
            else { Act 'ORPHAN' $dest 'no longer part of agent-gov, but you changed it: kept'; $table[$dest] = $base[$dest] }
        }
    } else {
        $olds = New-Object System.Collections.Generic.HashSet[string]
        foreach ($tag in (Tags)) {
            $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $names = @(& git -C $Repo ls-tree -r --name-only $tag -- templates 2>$null)
            $ErrorActionPreference = $saved
            foreach ($n in $names) { [void]$olds.Add(($n -replace '^templates/', '')) }
        }
        foreach ($old in ($olds | Sort-Object)) {
            if ($known -contains $old) { continue }
            if (Test-Path -LiteralPath (Join-Path $Tpl $old)) { continue }
            $target = Join-Path $p $old
            if (-not (Test-Path -LiteralPath $target)) { continue }
            $ch = Hash-File $target; $gone = $false
            foreach ($tag in (Tags)) { $c = Git-Show $tag $old; if ($c -ne $null -and (Hash-Text $c) -eq $ch) { $gone = $true; break } }
            if ($gone) { Act 'REMOVE' $old 'no longer part of agent-gov (untouched old copy)'; if ($apply) { Remove-Item -LiteralPath $target -Force } }
            else { Act 'ORPHAN' $old 'no longer part of agent-gov, but not an untouched copy: kept' }
        }
    }
    foreach ($x in ($acts | Sort-Object { $_.A }, { $_.D })) {
        if ($x.A -eq 'SAME') { continue }
        $note = ''; if ($x.N) { $note = "  ($($x.N))" }
        Write-Output "$($x.A)$Tab$($x.D)$note"
    }
    $sum = ''
    foreach ($k in @('ADD', 'UPDATE', 'CONFLICT', 'REMOVE', 'ORPHAN', 'KEEP', 'UNKNOWN', 'NEEDS-VARS')) {
        $c = @($acts | Where-Object { $_.A -eq $k }).Count
        if ($c -ne 0) { $sum += "$k=$c " }
    }
    Write-Output $sum
    if ($apply) {
        if ($limited -and (-not $extra)) { Write-Output 'applied. No manifest was created (no --vars): run again with --vars to enable full upgrades.' }
        else { Write-Manifest $p $vars $table; Write-Output "applied. Manifest updated ($ManifestRel)." }
    } else { Write-Output 'dry run: nothing was changed. Add --apply to do it.' }
}

function Cmd-Record([string]$proj, [string[]]$files) {
    if ($files.Count -eq 0) { Die 'give the file(s) you merged' }
    $p = (Resolve-Path -LiteralPath $proj).Path
    if (-not (Test-Path -LiteralPath (Join-Path $p $ManifestRel))) { Die "no manifest in $p" }
    $vars = Make-Vars $p ''
    $table = Manifest-Table $p
    $all = Get-Pairs $vars $true
    foreach ($f in $files) {
        $pr = $all | Where-Object { $_.Dest -eq $f } | Select-Object -First 1
        if (-not $pr) { Die "$f is not an agent-gov template file" }
        $table[$f] = Hash-Text (Render $vars $pr.Src)
        $new = Join-Path $p ($f + '.agent-gov-new')
        if (Test-Path -LiteralPath $new) { Remove-Item -LiteralPath $new -Force }
        Write-Output "RECORDED$Tab$f"
    }
    Write-Manifest $p $vars $table
}

$cmd = ''; $rest = @()
if ($args.Count -gt 0) { $cmd = $args[0]; $rest = @($args | Select-Object -Skip 1) }
switch ($cmd) {
    'detect'   { if ($rest.Count -lt 1) { Die 'project folder needed' }; Cmd-Detect $rest[0] }
    'scaffold' { $o = Parse-Opts $rest; if ($o.Rest.Count -lt 1) { Die 'project folder needed' }; Cmd-Scaffold $o.Rest[0] $o.Vars }
    'upgrade'  { $o = Parse-Opts $rest; if ($o.Rest.Count -lt 1) { Die 'project folder needed' }; Cmd-Upgrade $o.Rest[0] $o.Vars $o.Apply }
    'record'   { if ($rest.Count -lt 2) { Die 'usage: record <project> <path>...' }; Cmd-Record $rest[0] @($rest | Select-Object -Skip 1) }
    default    { Get-Content -LiteralPath $MyInvocation.MyCommand.Path | Select-Object -First 12; if ($cmd) { Die "unknown command: $cmd (detect, scaffold, upgrade, record)" } }
}
