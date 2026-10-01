# claude-delete-session.ps1 — Interactive Claude Code session manager (Windows)
#
#   ↑↓ / PgUp/PgDn  Navigate
#   Type             Filter/search
#   SPACE            Toggle preview pane
#   TAB              Mark for multi-delete
#   ENTER            Delete (marked, or current if none marked)
#   ESC              Cancel
#
# Usage:
#   pwsh claude-delete-session.ps1
#   Add to PATH and call: claude-delete-session
#   From within Claude :  !pwsh ~/.local/bin/claude-delete-session.ps1

$ProjectsDir = "$env:USERPROFILE\.claude\projects"

# ── helpers ────────────────────────────────────────────────────────────────

function ShortenProject([string]$name) {
    $s = $name -replace '^-home-[^-]+-', '~/' -replace '-', '/'
    if ($s.Length -gt 30) { return '…' + $s.Substring($s.Length - 27) }
    return $s
}

function GetTitle([string]$path) {
    try {
        $lines = [System.IO.File]::ReadLines($path) | Select-Object -First 80
        foreach ($line in $lines) {
            try {
                $o = $line | ConvertFrom-Json
                foreach ($k in @('leafSummary','summary','title','sessionTitle')) {
                    if ($o.$k -is [string] -and $o.$k.Trim()) {
                        return $o.$k.Trim().Substring(0, [Math]::Min(100, $o.$k.Length))
                    }
                }
                if ($o.type -eq 'user') {
                    $c = $o.message.content
                    $t = if ($c -is [array]) {
                        ($c | Where-Object type -eq 'text' | ForEach-Object text) -join ' '
                    } else { "$c" }
                    $t = ($t.Trim() -replace '\n', ' ')
                    if ($t) { return $t.Substring(0, [Math]::Min(100, $t.Length)) }
                }
            } catch {}
        }
    } catch {}
    return ''
}

function GetSessions {
    $items = Get-ChildItem -Path $ProjectsDir -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue
    $rows = foreach ($f in $items) {
        [PSCustomObject]@{
            Id       = $f.BaseName
            Proj     = ShortenProject $f.Directory.Name
            File     = $f.FullName
            Modified = $f.LastWriteTime
            SizeKB   = [Math]::Round($f.Length / 1024, 1)
            Title    = GetTitle $f.FullName
        }
    }
    $rows | Sort-Object Modified -Descending
}

function GetPreview([string]$path) {
    $fi = Get-Item $path -ErrorAction SilentlyContinue
    $out = @(
        "File : $path",
        "Size : $([Math]::Round($fi.Length/1024,1)) KB",
        ''
    )
    $n = 0
    try {
        foreach ($line in [System.IO.File]::ReadLines($path)) {
            if ($n -ge 25) { break }
            try {
                $o = $line | ConvertFrom-Json
                if ($o.type -notin @('user','assistant')) { continue }
                $c = $o.message.content
                $t = if ($c -is [array]) {
                    ($c | Where-Object type -eq 'text' | ForEach-Object text) -join ' '
                } else { "$c" }
                $t = ($t.Trim() -replace '\n', ' ')
                if ($t) {
                    $pfx = if ($o.type -eq 'user') { '▶ ' } else { '  ' }
                    $out += $pfx + $t.Substring(0, [Math]::Min(120, $t.Length))
                    $n++
                }
            } catch {}
        }
    } catch { $out += "Error: $_" }
    $out
}

# ── draw ───────────────────────────────────────────────────────────────────

function DrawTUI($Sessions, $Cur, $Offset, $Search, $Marked, $ShowPreview, $PreviewLines) {
    $W  = $Host.UI.RawUI.WindowSize.Width
    $H  = $Host.UI.RawUI.WindowSize.Height
    $bh = $H - 3
    $lw = if ($ShowPreview -and $Sessions.Count -gt 0) { [int]($W / 2) } else { $W }

    [Console]::SetCursorPosition(0, 0)

    # header
    $hdr = "  claude-delete-session  $($Sessions.Count) session(s)" +
           $(if ($Marked.Count) { "  $($Marked.Count) marked" } else { '' })
    Write-Host $hdr.PadRight($W) -ForegroundColor Cyan -NoNewline

    # list
    for ($i = 0; $i -lt $bh -and ($i + $Offset) -lt $Sessions.Count; $i++) {
        $s   = $Sessions[$i + $Offset]
        $dot = if ($Marked.Contains($s.Id)) { '●' } else { ' ' }
        $ds  = $s.Modified.ToString('MM-dd HH:mm')
        $ttl = if ($s.Title) { $s.Title } else { '(no title)' }
        $row = "$dot $ds  $($s.Proj.PadRight(20))  $ttl"
        if ($row.Length -gt $lw) { $row = $row.Substring(0, $lw - 1) }

        [Console]::SetCursorPosition(0, $i + 1)
        if ($i + $Offset -eq $Cur) {
            Write-Host $row.PadRight($lw) -BackgroundColor White -ForegroundColor Black -NoNewline
        } elseif ($Marked.Contains($s.Id)) {
            Write-Host $row.PadRight($lw) -ForegroundColor Yellow -NoNewline
        } else {
            Write-Host $row.PadRight($lw) -NoNewline
        }
    }

    # preview
    if ($ShowPreview -and $Sessions.Count -gt 0) {
        for ($r = 1; $r -le $bh; $r++) {
            [Console]::SetCursorPosition($lw, $r)
            Write-Host '│' -ForegroundColor DarkGray -NoNewline
            $pl = if (($r - 1) -lt $PreviewLines.Count) { $PreviewLines[$r - 1] } else { '' }
            $pl = if ($pl.Length -gt ($W - $lw - 2)) { $pl.Substring(0, $W - $lw - 2) } else { $pl }
            Write-Host $pl.PadRight($W - $lw - 1) -NoNewline
        }
    }

    # search bar
    [Console]::SetCursorPosition(0, $H - 2)
    Write-Host "  Search: $Search`_".PadRight($W) -NoNewline

    # footer
    [Console]::SetCursorPosition(0, $H - 1)
    Write-Host '  ↑↓=move  Tab=mark  Enter=delete  Space=preview  Esc=quit'.PadRight($W) -ForegroundColor Cyan -NoNewline
}

# ── main ───────────────────────────────────────────────────────────────────

function Main {
    if (-not (Test-Path $ProjectsDir)) {
        Write-Host "Directory not found: $ProjectsDir"; return
    }
    $all = @(GetSessions)
    if (-not $all) { Write-Host 'No sessions found.'; return }

    $cur = 0; $offset = 0; $search = ''
    $marked   = [System.Collections.Generic.HashSet[string]]::new()
    $showPrev = $false; $plines = @(); $prevId = $null

    [Console]::CursorVisible = $false
    Clear-Host

    try {
        while ($true) {
            $q   = $search.ToLower()
            $fil = @(if ($q) { $all | Where-Object { ($_.Title + $_.Proj + $_.Id).ToLower().Contains($q) } } else { $all })
            if ($cur -ge $fil.Count) { $cur = [Math]::Max(0, $fil.Count - 1) }

            $bh = $Host.UI.RawUI.WindowSize.Height - 3
            if ($offset -gt $cur) { $offset = $cur }
            elseif ($cur -ge $offset + $bh) { $offset = $cur - $bh + 1 }

            if ($showPrev -and $fil.Count -gt 0 -and $fil[$cur].Id -ne $prevId) {
                $plines = @(GetPreview $fil[$cur].File)
                $prevId = $fil[$cur].Id
            }

            DrawTUI $fil $cur $offset $search $marked $showPrev $plines

            $k = [Console]::ReadKey($true)

            switch ($k.Key) {
                'Escape'    { Clear-Host; Write-Host 'Cancelled.'; return }
                'UpArrow'   { if ($cur -gt 0) { $cur-- } }
                'DownArrow' { if ($cur -lt $fil.Count - 1) { $cur++ } }
                'PageUp'    { $cur = [Math]::Max(0, $cur - $bh) }
                'PageDown'  { $cur = [Math]::Min($fil.Count - 1, $cur + $bh) }
                'Spacebar'  { $showPrev = -not $showPrev }
                'Tab'       {
                    if ($fil.Count -gt 0) {
                        $id = $fil[$cur].Id
                        if ($marked.Contains($id)) { [void]$marked.Remove($id) } else { [void]$marked.Add($id) }
                        if ($cur -lt $fil.Count - 1) { $cur++ }
                    }
                }
                'Enter' {
                    $sel = @(if ($marked.Count) { $fil | Where-Object { $marked.Contains($_.Id) } }
                             elseif ($fil.Count) { $fil[$cur] })
                    if (-not $sel.Count) { break }

                    Clear-Host
                    [Console]::CursorVisible = $true
                    Write-Host "`nDelete $($sel.Count) session(s):" -ForegroundColor Yellow
                    foreach ($s in $sel) {
                        $ttl = if ($s.Title) { $s.Title.Substring(0, [Math]::Min(60, $s.Title.Length)) } else { '(no title)' }
                        Write-Host "  $($s.Modified.ToString('yyyy-MM-dd HH:mm'))  $($s.Proj)  $ttl" -ForegroundColor Gray
                    }
                    $ans = Read-Host "`nConfirm [y/N]"
                    if ($ans.ToLower() -eq 'y') {
                        foreach ($s in $sel) {
                            Remove-Item $s.File -Force -ErrorAction SilentlyContinue
                            Write-Host "  Deleted: $($s.Id.Substring(0,12))…" -ForegroundColor Green
                        }
                    } else {
                        Write-Host 'Aborted.'
                    }
                    return
                }
                'Backspace' {
                    if ($search.Length -gt 0) { $search = $search.Substring(0, $search.Length - 1); $cur = 0 }
                }
                default {
                    $c = $k.KeyChar
                    if ([char]::IsLetterOrDigit($c) -or $c -in @(' ', '-', '_', '.')) {
                        $search += $c; $cur = 0
                    }
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

Main
