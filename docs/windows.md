# Windows

## Which command for which terminal

| You use | Install | Scaffold and upgrade a project |
|---|---|---|
| PowerShell (5.1 or 7) | `install.cmd -Agent claude` | `scripts\gov.cmd ...` |
| cmd.exe | `install.cmd -Agent claude` | `scripts\gov.cmd ...` |
| Git Bash | `./install.sh --agent claude` | `bash scripts/gov.sh ...` |
| WSL (Linux inside Windows) | `./install.sh --agent claude` inside WSL | `bash scripts/gov.sh ...` |

`install.cmd` just runs `install.ps1` with `-ExecutionPolicy Bypass`, because Windows blocks unsigned `.ps1` files by default. PowerShell 5.1 has no `&&`, so type one command per line:

```
git clone https://github.com/Duc42195/agent-gov.git $HOME\.agent-gov
& $HOME\.agent-gov\install.cmd -Agent claude
```

For one project only, run from the project's root: `& $HOME\.agent-gov\install.cmd -Agent claude -Project`. To remove: `-Uninstall` (add `-Project` for the project copy). The installer records your terminal in `.agent-gov\.env`; the agent reads it to pick `gov.ps1` or `gov.sh`.

## Notes

- `install.cmd`, `plan.cmd`, `score.cmd` and `gov.cmd` are thin wrappers around the `.ps1` files with the same options as the bash versions; `plan`, `score` and `gov` print the same text in both shells and share the same `.agents/init-manifest`, so a project can be used from either.
- Python is only needed for `/plan-check` and `claude-delete-session`. The installer looks for `py -3`, `python`, `python3`. If git on Windows turns files into CRLF, hashes still compare equal (the scripts ignore CR); `.gitattributes` keeps `*.sh` as LF.
- `bin\claude-delete-session.ps1` is the older all-projects list and was not rewritten like the Linux/macOS version.
- **Not tested on a real Windows machine yet.** The `.ps1` scripts were checked statically only. If one fails, please raise an issue with the error text.
