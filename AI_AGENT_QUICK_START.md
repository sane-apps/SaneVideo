# AI Agent Quick Start (SaneVideo)

## Single source of truth

- SOP: `DEVELOPMENT.md`

## Default workflow

1. Find the relevant files with ripgrep.
2. Make the smallest correct change.
3. Run validators before claiming done:

```bash
./Scripts/SaneMaster.rb verify
```

## Key commands

```bash
./Scripts/SaneMaster.rb bootstrap
./Scripts/SaneMaster.rb verify
./Scripts/SaneMaster.rb verify --ui
```

## Tooling (hooks)

```bash
ruby ./Scripts/hooks/test/tier_tests.rb
ruby ./Scripts/qa.rb
```
