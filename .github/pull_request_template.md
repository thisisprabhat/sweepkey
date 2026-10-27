## What and why

## How it was tested
- [ ] `make test` passes
- [ ] `make build` passes
- [ ] Tests use temp directories only (never the real home directory)

## Safety checklist (if this touches cleaning or the vault)
- [ ] Nothing is deleted without a dry run and confirmation
- [ ] Git-tracked, symlink and path guards are unchanged or strengthened
- [ ] Secret file contents are never logged
