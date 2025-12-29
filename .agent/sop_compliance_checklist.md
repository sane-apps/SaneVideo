# SOP Compliance Checklist

**CRITICAL**: Review this checklist BEFORE and AFTER every code change.

## Before Making Changes

- [ ] Read relevant SOP sections (DEVELOPMENT.md)
- [ ] Check if tools exist in SaneMaster.rb for the task
- [ ] Verify API exists using `verify_api` if using new APIs
- [ ] Check existing test patterns for similar functionality

## When Creating Tests (Golden Rule #5)

- [ ] Use `./Scripts/SaneMaster.rb gen_test <name> --target <Component>`
- [ ] Check if mocks are needed: `./Scripts/SaneMaster.rb verify_mocks`
- [ ] Generate mocks if needed: `./Scripts/SaneMaster.rb gen_mock --target <dir>`
- [ ] Follow existing test patterns (check similar tests)
- [ ] Use MockProjectStore for ProjectState tests (prevents disk I/O)
- [ ] Run `xcodegen generate` after creating new files
- [ ] Verify tests actually run, not just compile

## After Making Changes

- [ ] Run `./Scripts/SaneMaster.rb verify` (build + tests)
- [ ] Kill old instances: `killall -9 SaneVideo`
- [ ] Launch with logging: `./Scripts/SaneMaster.rb launch` + `logs --follow`
- [ ] Update BUG_TRACKING.md if fixing bugs
- [ ] Verify all tests pass (not just compile)
- [ ] Check for linter errors: `read_lints`

## When Fixing Bugs

- [ ] Create regression test FIRST (before fixing)
- [ ] Use `gen_test` to create test template
- [ ] Fix the bug
- [ ] Verify test catches the bug
- [ ] Verify test passes after fix
- [ ] Update BUG_TRACKING.md

## Tools Reference

- **Test generation**: `./Scripts/SaneMaster.rb gen_test <name> --target <Component>`
- **Mock generation**: `./Scripts/SaneMaster.rb gen_mock --target <dir>`
- **Mock verification**: `./Scripts/SaneMaster.rb verify_mocks`
- **Build + test**: `./Scripts/SaneMaster.rb verify`
- **Project generation**: `xcodegen generate`
- **API verification**: `./Scripts/SaneMaster.rb verify_api <APIName> [Framework]`

## Common Patterns

### ProjectState Tests
```swift
// Always use MockProjectStore
class MockProjectStore: ProjectStoreProtocol, @unchecked Sendable {
    func loadProjects() async throws -> [VideoProject] { return [] }
    func saveProject(_ project: VideoProject) async throws { }
    func deleteProject(_ project: VideoProject) async throws { }
    func recentProjects(limit: Int) async throws -> [VideoProject] { return [] }
    func fileURL(for project: VideoProject) -> URL {
        return URL(fileURLWithPath: "/tmp/\(project.id.uuidString).svproj")
    }
}

projectState = ProjectState(projectStore: MockProjectStore())
```

### Service Tests
- Check if service is a protocol → use Mockolo-generated mocks
- Check if service is concrete → use real instance or custom mock
- Always check `SaneVideoTests/Mocks/Mocks.swift` for existing mocks
