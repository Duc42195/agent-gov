# Install the /project-init command for one or more AI agents (Windows).
# Works in Windows PowerShell 5.1 and PowerShell 7. Keep this file ASCII only.
#
#   install.cmd -Agent claude                    user-wide: writes only under your home folder
#   install.cmd -Agent claude -Project           this project only: writes only under the current folder
#   install.cmd -Agent claude -Uninstall [-Project]   remove what this script wrote in that scope
#
# Agents: claude, cursor, copilot (project only), gemini, opencode, codex (deprecated), all, other.
# install.cmd calls this script with -ExecutionPolicy Bypass, because Windows blocks unsigned .ps1
# files by default. A project install never touches your home folder, and a user-wide install never
# touches the project; if a copy exists in the other scope it only warns.
# Both modes record this machine in <agent-gov>\.env. User-wide claude also copies
# bin\claude-delete-session.ps1 to ~\.local\bin (it does not edit settings.json).
[CmdletBinding()]
param(
    [string[]]$Agent = @(),
    [switch]$Project,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Cwd = (Get-Location).Path

if ($Project -and ($Cwd.TrimEnd('\') -eq $Repo.TrimEnd('\'))) {
    Write-Error "run -Project from your project's root folder, not from the agent-gov folder"
    exit 2
}

function Write-Text([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [System.IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), $Utf8)
}

# -- this machine: OS, shell, Python ---------------------------------------
$OsName = 'windows'
$ShellKind = 'powershell'
if ($env:AGENT_GOV_SHELL) { $ShellKind = $env:AGENT_GOV_SHELL }
elseif ($PSVersionTable.PSVersion.Major -ge 6) { $ShellKind = 'pwsh' }

# The first Python 3.8+ among py -3, python, python3 (override with AGENT_GOV_PY_CANDIDATES).
# Python is only needed for /plan-check and claude-delete-session.
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
if ($Py) { Write-Output "python: $Py" }
else { Write-Output 'note: Python 3.8+ not found. /plan-check and claude-delete-session need it; everything else works without.' }

# -- where each agent keeps custom commands --------------------------------
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
# Keep these paths in step with install.sh (tests/smoke_test.py compares them).
$UserDir = @{
    'claude'   = (Join-Path $claudeDir 'commands')
    'cursor'   = (Join-Path $HOME '.cursor\commands')
    'gemini'   = (Join-Path $HOME '.gemini\commands')
    'opencode' = (Join-Path $HOME '.config\opencode\commands')
    'codex'    = (Join-Path $codexDir 'prompts')
}
$ProjectDir = @{
    'claude'   = (Join-Path $Cwd '.claude\commands')
    'cursor'   = (Join-Path $Cwd '.cursor\commands')
    'copilot'  = (Join-Path $Cwd '.github\prompts')
    'gemini'   = (Join-Path $Cwd '.gemini\commands')
    'opencode' = (Join-Path $Cwd '.opencode\commands')
}
function File-For([string]$a) {
    if ($a -eq 'copilot') { return 'project-init.prompt.md' }
    if ($a -eq 'gemini') { return 'project-init.toml' }
    return 'project-init.md'
}
function Is-Ours([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return [bool](Select-String -LiteralPath $Path -Pattern 'agent-governance scaffold' -Quiet)
}

$Scope = 'user'; $Other = 'project'
if ($Project) { $Scope = 'project'; $Other = 'user' }
function Dir-For([string]$a, [string]$scope) {
    $table = $UserDir
    if ($scope -eq 'project') { $table = $ProjectDir }
    if ($table.ContainsKey($a)) { return $table[$a] }
    return ''
}

# -- which agents -----------------------------------------------------------
if ($Agent.Count -eq 0) {
    $answer = ''
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        $answer = Read-Host 'Agent(s): claude, cursor, copilot, gemini, opencode, codex, other, all (comma separated) [claude]'
    }
    if (-not $answer) { $answer = 'claude' }
    $Agent = @($answer)
}
$names = @(($Agent -join ',') -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
if ($names -contains 'all') { $names = @('claude', 'cursor', 'copilot', 'gemini', 'opencode') }

$Desc = 'Set up the shared agent-governance scaffold (AGENTS.md, .agents/, /done) in this project'
$Body = "Read ``$Repo\init.md`` and follow it step by step. The scripts and templates are in ``$Repo\`` (``scripts\gov.ps1`` or ``scripts/gov.sh``, ``templates\``). This machine's settings (shell, Python) are in ``$Repo\.env``. Work only on the target project: the folder this agent was opened in, never ``$Repo`` itself, and do not change anything outside it."

function Content-For([string]$a) {
    switch ($a) {
        'copilot' { return "---`ndescription: $Desc`nagent: agent`n---`n$Body`n" }
        'gemini'  { return "description = `"$Desc`"`nprompt = `"`"`"`n$Body`n`"`"`"`n" }
        'cursor'  { return "<!-- agent-governance scaffold: /project-init -->`n$Body`n" }
        default   { return "---`ndescription: $Desc`n---`n$Body`n" }
    }
}

$hasClaude = $false
$done = @()
foreach ($a in $names) {
    if ($a -eq 'other') {
        Write-Output "other agent: no command file needed. Tell it: `"Read and follow $Repo\init.md`""
        continue
    }
    if (@('claude', 'cursor', 'copilot', 'gemini', 'opencode', 'codex') -notcontains $a) {
        Write-Error "unknown agent: $a (claude, cursor, copilot, gemini, opencode, codex, other)"
        exit 2
    }
    $dir = Dir-For $a $Scope
    if (-not $dir) {
        if ($a -eq 'copilot') { Write-Output 'copilot: it has no user-wide commands. Run: install.cmd -Agent copilot -Project   (from your project)' }
        if ($a -eq 'codex') { Write-Output 'codex: its custom prompts are user-wide only. Run it without -Project. (Codex deprecated custom prompts.)' }
        continue
    }
    $file = Join-Path $dir (File-For $a)

    if ($Uninstall) {
        if (Is-Ours $file) { Remove-Item -LiteralPath $file -Force; Write-Output "removed ${a}: $file" }
        else { Write-Output "nothing of ours at $file" }
        continue
    }

    if ($a -eq 'codex') { Write-Output 'note: Codex custom prompts are deprecated in favour of skills; this may stop working.' }
    Write-Text $file (Content-For $a)
    Write-Output "installed $a ($Scope): $file"
    $done += $a
    if ($a -eq 'claude') { $hasClaude = $true }

    $otherDir = Dir-For $a $Other
    $skipRepoCopy = ($Other -eq 'project') -and ($Cwd.TrimEnd('\') -eq $Repo.TrimEnd('\'))
    if ($otherDir -and -not $skipRepoCopy -and (Is-Ours (Join-Path $otherDir (File-For $a)))) {
        $flag = ''
        if ($Other -eq 'project') { $flag = ' -Project' }
        Write-Warning "$a will list /project-init twice: another copy is at $(Join-Path $otherDir (File-For $a)). Remove it with: $Repo\install.cmd -Agent $a -Uninstall$flag   (run it from the project for -Project)"
    }
}

if ($Uninstall) {
    Write-Output '(claude-delete-session in ~\.local\bin was left alone)'
    exit 0
}

if ($Scope -eq 'user') {
    $old = Join-Path $HOME '.opencode\commands\project-init.md'
    if (Is-Ours $old) { Remove-Item -LiteralPath $old -Force; Write-Output "removed the misplaced file from 0.7.0: $old" }
    if ($hasClaude) {
        $bin = Join-Path $HOME '.local\bin'
        New-Item -ItemType Directory -Force -Path $bin | Out-Null
        Copy-Item -Force (Join-Path $Repo 'bin\claude-delete-session.ps1') $bin
        Write-Output "installed delete-session: $bin\claude-delete-session.ps1"
        Write-Output "use it in a terminal: powershell -File $bin\claude-delete-session.ps1   (settings.json was not changed; Claude Code will ask before running it)"
    }
} elseif ($hasClaude) {
    Write-Output '(project install: claude-delete-session is user-wide, so it was not installed; run install.cmd -Agent claude without -Project for it)'
}

$envText = @(
    '# Written by install.ps1. This machine''s settings for agent-gov; not committed.',
    "AGENT_GOV_REPO=$Repo",
    "AGENT_GOV_OS=$OsName",
    "AGENT_GOV_SHELL=$ShellKind",
    'AGENT_GOV_INSTALLER=install.ps1',
    "AGENT_GOV_PY=$(if ($Py) { $Py } else { 'none' })",
    "AGENT_GOV_AGENTS=$($done -join ',')"
) -join "`n"
Write-Text (Join-Path $Repo '.env') ($envText + "`n")
Write-Output "recorded this machine in $Repo\.env (os=$OsName shell=$ShellKind python=$(if ($Py) { $Py } else { 'none' }))"
Write-Output "restart your agent, then run /project-init (or the prompt above for 'other')"
