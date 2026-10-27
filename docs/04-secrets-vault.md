# Secrets vault

← [Index](README.md)

The vault collects files that git does not have and that cannot be regenerated.

## Detection
- **Git-aware.** For git repos, candidates come from `git ls-files --others --ignored --exclude-standard` (ignored) and `--others --exclude-standard` (untracked), matched against the sensitive patterns. Artifact folders such as `node_modules` and `build` are skipped. Non-git folders fall back to plain pattern matching.
- **Default sensitive patterns**
  - Env files: `.env`, `.env.*` (`.env.example` optional), `.dev.vars`
  - Android/Flutter signing: `*.jks`, `*.keystore`, `key.properties`, `local.properties`*
  - Firebase: `google-services.json`, `GoogleService-Info.plist`, `.firebaserc`*
  - Certificates and keys: `*.p12`, `*.p8` / `AuthKey_*.p8`, `*.pem`, `*.key`, `*.cer`, `*.mobileprovision`, `id_rsa*`, `*.ppk`
  - Cloud/service credentials: `credentials.json`, `service-account*.json`, `secrets.*`, `terraform.tfvars`, `*.tfstate`, `.npmrc`, `.pypirc`, `.netrc`, `sentry.properties`
  - Framework config: `config/master.key` (Rails), `appsettings.*.json`, `docker-compose.override.yml`, Fastlane `.env*`
- **Always-collect list**: collected even when git tracks them. Starts with `pubspec.yaml`; editable.
- **Uncommitted work mode (optional)**: also collect untracked, non-ignored files so unfinished work survives archiving.
- **Content scanner (optional)**: gitleaks-style regex and entropy rules on untracked text files, catching AWS keys, GitHub/Stripe/OpenAI tokens and `-----BEGIN PRIVATE KEY-----` blocks that name patterns miss.
- Each found file has a reason: `ignoredMatch`, `untrackedMatch`, `alwaysCollect`, `uncommittedWork`, `contentMatch` or `patternMatch`. Files above the size cap (default 10 MB) are skipped.

## Mirror layout
`Vault/<scanRootName>/<relative/project/path>/<file>`, keeping the `projectRoot/dir1/dir1/file.jks` layout. Unix permissions are kept; copied secrets are set to `0600`.

```
Vault/
├─ manifest.json
└─ Projects/                     (scan root name)
   ├─ app/
   │  ├─ .env
   │  ├─ pubspec.yaml
   │  └─ android/
   │     ├─ key.properties
   │     └─ upload.jks
   └─ api/
      └─ config/master.key
```

## manifest.json
One entry per file; `formatVersion` is 1.

```json
{
  "formatVersion": 1,
  "createdAt": "2026-01-15T09:30:00Z",
  "hostName": "prabhat-mbp",
  "entries": [
    {
      "vaultPath": "Projects/app/android/upload.jks",
      "sourcePath": "/Users/me/Projects/app/android/upload.jks",
      "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
      "sizeBytes": 2218,
      "modified": "2025-11-02T18:04:11Z",
      "collectedAt": "2026-01-15T09:30:00Z",
      "reason": "ignoredMatch",
      "gitRemoteURL": "git@github.com:me/app.git",
      "gitBranch": "main",
      "gitHeadCommit": "3b18e512dba79e4c8300dd08aeb37f8e728b8dad",
      "pathInRepository": "android/upload.jks"
    }
  ]
}
```

## Export formats (chosen each time)
1. **Plain folder**, with `.metadata_never_index` so Spotlight skips it.
2. **`.zip`**.
3. **Encrypted disk image** via `hdiutil` (AES-256 sparsebundle or DMG). Any Mac can open it without this app. The password can be stored in Keychain behind Touch ID (LocalAuthentication).

Warn when the destination is a cloud-synced folder (iCloud Drive, Dropbox) in plain-folder mode.

## Incremental sync and versions
Copy only files whose hash changed and keep the last N versions of each file (default 5). A diff view shows what changed since the last snapshot.

## Restore
- Restore a file to its original path.
- Restore by git remote: after a fresh clone on a new Mac, match clones by remote URL and put secrets back (also handles moved folders).
- Restores plan first (`RestoreAction` shows whether the destination exists and whether it is identical), then apply, with an overwrite option.

## Vault browser
Tree view with values masked by default, reveal/copy on demand, and Quick Look.
