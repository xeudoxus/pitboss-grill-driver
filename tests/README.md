## Tests: Conventions & helper usage

This file documents the local test conventions and the small helper API in `tests/test_helpers.lua` so future contributors don't accidentally mock core driver code.

Principles
- Always use the real driver core code from `src/` in unit tests. DO NOT mock or replace modules from `src/` (for example: `command_service`, `device_status_service`, `temperature_service`, `network_utils`, `refresh_service`, `pitboss_api`, etc.).
- Only mock platform/runtime/third-party pieces when absolutely required (sockets, JSON, timers, capability constructors).
- Keep test setup DRY: prefer `tests/test_helpers.lua` for shared stubs and the network recorder.

Runner / package.path
- The test runner is configured so `src/?.lua` is preferred. This guarantees tests load the real core modules instead of accidental shadow mocks under `tests/mocks`.

Allowed mocks
- `tests/mocks/cosock.lua` (minimal deterministic socket behavior)
- `tests/mocks/dkjson.lua` (minimal deterministic JSON encode/decode for tests)
- `tests/mocks/custom_capabilities.lua` (capability constructors used by tests)

Using `tests/test_helpers.lua`
- `setup_network_recorder(recorder_table)` -> returns a stable recorder with methods `clear_sent()` and records network sends into `recorder_table.sent`.
	Note: this helper installs a lightweight test-only `network_utils` stub via `package.loaded["network_utils"]` to capture outgoing commands; use the helper rather than mutating `package.loaded` directly.
- `setup_device_status_stub()` -> installs a minimal `device_status_service` stub that tests can override per-function.
- `assert_eq(actual, expected, msg)` -> convenience assertion helper used across specs (asserts that `actual == expected`).

Example: recording status messages
 - In a spec:
	 ```lua
	 local helpers = require('tests.test_helpers')
	 helpers.setup_device_status_stub()
	 local status_recorder = helpers.install_status_message_recorder()

	 -- exercise code that calls device_status_service.set_status_message(...)

	 -- assert the last recorded message
	 assert(status_recorder.messages[#status_recorder.messages].message == "Failed to change power state")
	 ```

Network recorder example
 - Use the network recorder to capture outgoing network commands and clear it between checks:
	 ```lua
	 local helpers = require('tests.test_helpers')
	 local sent = helpers.setup_network_recorder()
	 -- exercise code that sends network commands
	 assert(#sent >= 1)
	 -- clear recorded commands for the next sub-test
	 if sent.clear_sent then sent.clear_sent() end
	 ```

Notes
 - Prefer using the recorder helpers instead of reassigning global tables (do not do `sent_commands = {}` inside specs).
 - Prefer using `status_recorder.messages` rather than reading `device.last_status_message`.

Best practices
- If a spec needs to change one small behavior in a core module, prefer to override a single function on the module instance rather than replacing the whole module in `package.loaded`.
- Avoid reassigning the recorder table inside specs (do not do `sent_commands = {}`); use `recorder.clear_sent()` so references remain stable.
- When testing code that emits multiple events, assert on content (scan for an expected event) rather than exact index positions to reduce brittleness.

How to run tests (PowerShell)
```
# From repository root, run the bundled PowerShell wrapper (recommended):
.\test.ps1

# Or explicitly invoke PowerShell / pwsh:
pwsh -NoProfile -Command ".\\test.ps1"
```

If you need to add a new mock, prefer placing it under `tests/mocks/` and document why the mock is necessary and which tests depend on it.

If anything in these rules needs tightening or you find a test that still mocks core code, open a PR and mark it `tests: fix`.

-- test runner conventions maintained by the test maintainer --
