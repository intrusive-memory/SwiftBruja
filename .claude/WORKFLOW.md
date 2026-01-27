# Development Workflow

## Branch Strategy

### Branches

- **`development`** - Active development branch. All work happens here.
- **`main`** - Protected production branch. PRs only. Triggers CI.

### Rules

- **NEVER** commit directly to `main`
- **NEVER** delete the `development` branch
- **ALWAYS** create PRs from `development` to `main`

## Workflow

### Daily Development

1. Work on `development` branch
2. Commit frequently with descriptive messages
3. Push to `development` (no CI runs on push)

### Ready to Release

1. Ensure all changes are committed to `development`
2. Create PR from `development` → `main`
3. CI runs automatically on PR:
   - Build library (SwiftBruja)
   - Build CLI (bruja)
   - Run unit tests
   - Run integration test (query with expected response)
4. Fix any CI failures on `development`, push, CI re-runs
5. Once CI passes, merge PR
6. Tag release: `git tag v1.0.0 && git push --tags`
7. Create GitHub Release

### Hotfix Process

1. Create hotfix branch from `main`: `git checkout -b hotfix/issue-name main`
2. Fix issue, commit
3. Create PR from `hotfix/issue-name` → `main`
4. After merge, cherry-pick to `development`: `git checkout development && git cherry-pick <commit>`

## Commit Messages

Follow conventional commit format:

```
type: short description

Longer description if needed.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

Types:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `refactor:` - Code refactoring
- `test:` - Adding tests
- `chore:` - Maintenance

## Version Numbering

Follow Semantic Versioning (semver):

- **MAJOR** (1.0.0 → 2.0.0): Breaking API changes
- **MINOR** (1.0.0 → 1.1.0): New features, backward compatible
- **PATCH** (1.0.0 → 1.0.1): Bug fixes, backward compatible

## CI Requirements

All PRs to `main` must pass these required status checks:

1. **Code Quality**: TODOs, large files, print statement checks
2. **macOS Tests**: `swift test --filter SwiftBrujaTests` (unit tests)
3. **Integration Tests**: `make release` → verify `bruja --version` and `--help`

## Branch Protection (GitHub)

Configure on `main`:
- Require PR before merging
- Required status checks: `Code Quality`, `macOS Tests`, `Integration Tests`
- No direct pushes
