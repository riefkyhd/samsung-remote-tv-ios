# Support Matrix

This matrix defines current product boundaries for v1. It separates behavior that is **Supported**, **Best-effort**, and **Unsupported**.

## Status Legend
- **Supported**: implemented intentionally and expected to work for in-scope devices/flows.
- **Best-effort**: implemented, but behavior varies by TV model, firmware, protocol quirks, or local network conditions.
- **Unsupported**: not implemented as a product claim in v1.

## Capability Matrix (v1)

| Area | Status | Scope / Notes |
|---|---|---|
| Local TV discovery (Bonjour/SSDP/IP scan) | Best-effort | Depends on network topology, broadcast visibility, and TV responsiveness. |
| Manual add by IP | Supported | Manual IP flow is supported as a user entry path. Reachability still depends on LAN conditions. |
| Save / rename TV | Supported | Saved device metadata and remote name management are supported. |
| Forget Pairing | Supported | Clears pairing/session material while keeping saved TV entry. |
| Remove Device | Supported | Removes saved TV entry and associated pairing material. |
| Modern WebSocket control path | Supported | Primary control transport for supported modern Samsung models. |
| Encrypted SPC pairing/control path | Best-effort | Supported where legacy encrypted flow is compatible; pairing can vary by model/firmware. |
| Legacy remote control path | Best-effort | Fallback path for older models; command availability varies by generation. |
| Core key controls (power, D-pad, volume, channel, media, number/color keys) | Supported | Availability is capability-gated per discovered TV profile. |
| Trackpad control | Best-effort | Enabled only when capability resolution allows it; model-dependent behavior. |
| Quick Launch shortcuts | Supported | Curated shortcuts/favorites behavior; not installed-app enumeration. |
| Installed-app enumeration | Unsupported | v1 does not claim true installed-app discovery across models. |
| Wake-on-LAN | Best-effort | Supported for compatible models/network setups only. |
| Reconnect lifecycle | Supported | Reconnect behavior exists; reliability still depends on transport/model conditions. |
| In-app diagnostics surface | Supported | Structured diagnostics are available with sanitized metadata only. |
| Cloud/remote internet control | Unsupported | v1 supports local-network control only. |

## Notes
- Capability resolution is used to hide/disable unsupported actions upfront.
- If behavior is model-specific, UI/state messaging should prefer explicit "not supported on this TV" guidance over generic errors.
- README claims should remain aligned with this document.
