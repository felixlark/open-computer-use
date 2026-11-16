# Phone display readiness

The first installed SmartShadow phone-host attempt stopped before opening its gateway when its dedicated display was unavailable. Its exact window claim and unknown close result were preserved; no creation or message was replayed.

The phone-only provider now waits for WindowServer topology within its explicitly configured request budget, using a monotonic clock. The HiDPI mode is 1920×1440 so the selected 480×600 logical window and inset fit. Parking checks active, nonprimary, nonmirrored topology before writing geometry and again before pinning. Existing handles and unknown claims are never automatically recreated.

Read-only status includes the allocated display, topology and last creation failure. The shim exposes the failed creation step without logging private data. Generic virtual-display routes remain retired.

Validation: production Swift build and eight isolated tests using the production phone policy passed; independent review findings were fixed. Installed provider residency, render pin and Mac/iOS send, streaming and reconnect still require actual acceptance in [SmartShadow #613](https://github.com/felixlark/smart-shadow/issues/613).
