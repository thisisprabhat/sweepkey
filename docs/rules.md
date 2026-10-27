# Adding a cleaning rule

Rules are data, not code. The bundled catalog is a JSON array at
`Packages/SweepkeyKit/Sources/SweepkeyKit/Resources/rules.json`. A rule applies to a directory only when one of its `markers` exists in that directory, and it then offers `target` (relative to that directory) for cleaning.

## Schema

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Unique id, e.g. `"javascript.node_modules"` |
| `ecosystemID` | string | A built-in ecosystem id; unknown ids fall back to `generic` |
| `markers` | string[] | Any-of file names or globs (`"*.csproj"`) that must exist in the project directory |
| `target` | string | Relative path. The last segment may be a glob (`cmake-build-*`); may contain `/` (`ios/Pods`). No `..`, not absolute |
| `risk` | `"safe"` \| `"caution"` \| `"danger"` | Safe < caution < danger |
| `enabledByDefault` | bool | On without a user override |
| `regenerate` | string? | Command that rebuilds the target, shown in the UI |
| `note` | string? | Extra explanation |

Built-in ecosystem ids: `javascript`, `python`, `flutter`, `android`, `jvm`, `rust`, `swift`, `go`, `dotnet`, `cpp`, `elixir`, `haskell`, `ruby`, `php`, `zig`, `scala`, `bazel`, `terraform`, `unity`, `unreal`, `generic`.

## Example

```json
{
  "id": "rust.target",
  "ecosystemID": "rust",
  "markers": ["Cargo.toml"],
  "target": "target",
  "risk": "safe",
  "enabledByDefault": true,
  "regenerate": "cargo build",
  "note": "Cargo build output"
}
```

## Guidelines
1. Use a specific marker for ambiguous folder names (`build` needs `pubspec.yaml`, `build.gradle`, etc.), so unrelated folders never match.
2. Only mark a rule `safe` if the folder is fully regenerable from the sources. Folders that are sometimes committed or hand-written are `caution` with `enabledByDefault: false`.
3. Always fill in `regenerate` when a command exists.
4. Run `make test`; the rule-set validation tests reject an empty id or target, `..` or absolute targets, and rules without markers.
5. Even a matching rule never deletes git-tracked folders: the safety guard still applies.

Users can also add custom rules in Settings, which are stored in the app settings rather than in the catalog.
