# Install the /project-init command for one or more AI agents (Windows).
# Works in Windows PowerShell 5.1 and PowerShell 7. Keep this file ASCII only.
#
#   install.cmd [-Agent claude,cursor,copilot,codex,gemini,opencode,all] [-Project]
#   install.cmd -Update      pull the latest agent-gov (this clone) and show what changed
#
# install.cmd just calls this script with -ExecutionPolicy Bypass, because Windows blocks
# unsigned .ps1 files by default. No -Agent: asks (or uses claude when not run in a terminal).
# User-wide install for claude also copies bin\claude-delete-session.ps1 to ~\.local\bin
# (unlike install.sh it does not edit settings.json).
# Default scope is user-wide; -Project installs into the current directory.
[CmdletBinding()]
param(
    [string[]]$Agent = @(),
    [switch]$Project,
    [switch]$Update
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Text([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [System.IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n") + "`n", $Utf8)
}

if ($Update) {
    & git -C $Repo fetch --quiet
    if ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }
    $old = (Get-Content (Join-Path $Repo 'VERSION') -Raw).Trim()
    $behind = (& git -C $Repo rev-list --count 'HEAD..@{u}')
    if ($behind -eq '0') { Write-Output "already up to date ($old)"; exit 0 }
    & git -C $Repo pull --ff-only --quiet
    if ($LASTEXITCODE -ne 0) { throw 'git pull --ff-only failed' }
    $new = (Get-Content (Join-Path $Repo 'VERSION') -Raw).Trim()
    Write-Output "updated $old -> $new"
    & git -C $Repo diff --unified=0 'HEAD@{1}' HEAD -- CHANGELOG.md |
        Where-Object { $_ -match '^\+[^+]' } | ForEach-Object { $_ -replace '^\+', '' }
    Write-Output 'projects already scaffolded: run /project-init in them to upgrade'
    exit 0
}

# The first Python 3.8+ among py -3, python, python3 (override with AGENT_GOV_PY_CANDIDATES).
function Find-Python {
    $list = @('py', 'python', 'python3')
    if ($env:AGENT_GOV_PY_CANDIDATES) { $list = $env:AGENT_GOV_PY_CANDIDATES -split '\s+' }
    foreach ($c in $list) {
        if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { continue }
        $pre = @()
        if ($c -eq 'py') { $pre = @('-3') }
        $saved = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $c @pre -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>&1 | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $saved
        if ($ok) { return (($c + ' ' + ($pre -join ' ')).Trim()) }
    }
    return ''
}
$Py = Find-Python
if ($Py) {
    $PyNote = "Python on this machine: ``$Py``. Use it as {{PY}} in every command you write."
    Write-Output "python: $Py"
} else {
    $PyNote = 'Python 3.8+ was NOT found on this machine (tried py, python, python3). Tell the user to install it: the scaffold scripts need it. Use `python` as {{PY}} and follow init.md for the missing-Python case.'
    Write-Warning 'Python 3.8+ not found (tried py, python, python3). Install it; /plan-check and the other scripts need it.'
}

$Desc = 'Set up the shared agent-governance scaffold (AGENTS.md, .agents/, /done) in this project'
$Update_ = "powershell -ExecutionPolicy Bypass -File $Repo\install.ps1 -Update"
$Body = "First run ``git -C $Repo fetch --quiet`` and ``git -C $Repo status -sb``; if it is behind, tell the user in one line and ask to run ``$Update_`` before continuing. Then read ``$Repo\init.md`` and follow it step by step. Templates are in ``$Repo\templates\``. $PyNote`nThe target is the project root, the directory this agent was opened in, never ``$Repo`` itself."

if ($Agent.Count -eq 0) {
    $answer = ''
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        $answer = Read-Host 'Agent(s): claude, cursor, copilot, codex, gemini, opencode, other, all (comma separated) [claude]'
    }
    if (-not $answer) { $answer = 'claude' }
    $Agent = @($answer)
}
$names = @(($Agent -join ',') -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
if ($names -contains 'all') { $names = @('claude', 'cursor', 'copilot', 'codex', 'gemini', 'opencode') }

$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$cwd = (Get-Location).Path

# Per agent: project-relative dir, user-wide dir ('' = unsupported), file name, format.
# Keep these paths in step with install.sh (tests/smoke_test.py compares them).
$Targets = @{
    'claude'   = @{ Project = '.claude\commands';  User = (Join-Path $claudeDir 'commands');       File = 'project-init.md';        Format = 'claude' }
    'cursor'   = @{ Project = '.cursor\commands';  User = (Join-Path $HOME '.cursor\commands');    File = 'project-init.md';        Format = 'plain' }
    'copilot'  = @{ Project = '.github\prompts';   User = '';                                      File = 'project-init.prompt.md'; Format = 'copilot' }
    'codex'    = @{ Project = '';                  User = (Join-Path $codexDir 'prompts');         File = 'project-init.md';        Format = 'claude' }
    'gemini'   = @{ Project = '.gemini\commands';  User = (Join-Path $HOME '.gemini\commands');    File = 'project-init.toml';      Format = 'toml' }
    'opencode' = @{ Project = '.opencode\commands'; User = (Join-Path $HOME '.config\opencode\commands'); File = 'project-init.md';  Format = 'plain' }
}

function Format-Command([string]$Format) {
    switch ($Format) {
        'claude'  { return "---`ndescription: $Desc`n---`n$Body" }
        'copilot' { return "---`ndescription: $Desc`nmode: agent`n---`n$Body" }
        'toml'    { return "description = `"$Desc`"`nprompt = `"`"`"`n$Body`n`"`"`"" }
        default   { return $Body }
    }
}

$hasClaude = $false
foreach ($a in $names) {
    if ($a -eq 'other') {
        Write-Output "other agent: no command file needed. Tell it: `"Read and follow $Repo\init.md`""
        continue
    }
    if (-not $Targets.ContainsKey($a)) {
        Write-Error "unknown agent: $a (claude, cursor, copilot, codex, gemini, opencode, other)"
        exit 2
    }
    if ($a -eq 'claude') { $hasClaude = $true }
    $t = $Targets[$a]
    $dir = ''
    if ($Project) { if ($t.Project) { $dir = Join-Path $cwd $t.Project } } else { $dir = $t.User }
    if (-not $dir) {
        Write-Warning "skipped ${a}: no such scope (try -Project or without it)"
        continue
    }
    $file = Join-Path $dir $t.File
    Write-Text $file (Format-Command $t.Format)
    Write-Output "installed ${a}: $file"
}

if ($hasClaude) {
    if (-not $Project) {
        $bin = Join-Path $HOME '.local\bin'
        New-Item -ItemType Directory -Force -Path $bin | Out-Null
        Copy-Item -Force (Join-Path $Repo 'bin\claude-delete-session.ps1') $bin
        Write-Output "installed delete-session: $bin\claude-delete-session.ps1"
        Write-Output "use: powershell -File $bin\claude-delete-session.ps1   (inside Claude: !powershell -File ...)"
        Write-Output 'note: settings.json was not changed; Claude Code will ask before running it.'
    } else {
        Write-Output 'skipped claude-delete-session: it is user-wide; run install.cmd -Agent claude without -Project to add it'
    }
}
Write-Output "restart your agent, then run /project-init (or the prompt above for 'other')"
