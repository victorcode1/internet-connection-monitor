## 0.1.0

- Add framework-independent monitoring with unknown, online and offline states.
- Confirm offline after consecutive failures, serialize checks and discard stale results.
- Recheck online and offline states even when the network interface does not change.
- Add configurable HTTP fallback endpoints, exact status checks and client cleanup.
- Support injected probes and network event streams, bounded checks and safe disposal.
