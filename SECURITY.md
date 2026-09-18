# Security policy

No release has been published. Fixes initially target current source and explicitly qualified runtimes; unverified Windows/PowerShell versions have no support commitment.

## Report privately

Once hosted on GitHub, use **Security → Report a vulnerability** if Private Vulnerability Reporting is enabled. This local checkout has no such channel yet; no dedicated security email is advertised.

If no private channel is available, ask the maintainer to establish one without sending sensitive details. Do not disclose exploit payloads, real snapshots, keys, private paths or Function source in public issues. Keep details private until a channel is confirmed. No response-time guarantee is offered.

Include affected version/architecture, impact and a minimal synthetic reproduction. Never send a real redaction secret; use a disposable test key to demonstrate leakage.

## Security-relevant problems

- Secret, path, username or other privacy leakage.
- Unexpected target execution or module autoload.
- Unsafe file overwrite or ACL failure.
- Snapshot/report/error output exposing Function source.
- Input handling that turns offline comparison into execution or additional data collection.

Documented conservative unknown results are expected. Redaction preserves equality/order metadata and is not an anonymity guarantee; review reports before sharing.
