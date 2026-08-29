# Contributing

Thanks for helping improve LidSwitch.

1. Open an issue before making a behavior change that affects display safety.
2. Keep the state planner independent from macOS APIs where possible.
3. Add or update a planner test for every state-transition change.
4. Run `make test` and `make app` before opening a pull request.

Compatibility reports should include the Mac model, macOS version, display
model, cable or dock type, lid state, and the output of:

```sh
dist/LidSwitch.app/Contents/MacOS/LidSwitch --diagnose
```

Do not include hardware serial numbers in public issues.
