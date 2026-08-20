# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately to the repository owner through GitHub’s private vulnerability reporting flow when available. Do not include real screenshots, credentials, private app content, or personal Accessibility dumps in a public issue.

## Desktop automation policy

Open Computer Use runs inside the user’s real logged-in session. Contributors must preserve these invariants:

- The default path must not move the physical pointer, steal keyboard focus, switch Spaces, or activate a target app merely to operate it.
- `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS` must remain unset and `click_method: "global"` must be rejected.
- A failed background action must return an actionable failure instead of escalating silently to global input.
- Screenshots and Accessibility trees must remain local unless the user explicitly chooses to share them.
- Cleanup must stop overlays and prevent late hook results from recreating a stopped session.

## Confirmation boundary

Agents must obtain confirmation immediately before:

- deleting or permanently overwriting data
- sending, publishing, posting, or submitting as the user
- purchases, transfers, subscriptions, or other financial commitments
- creating credentials or changing access permissions
- final submission of medical, legal, employment, housing, insurance, or similarly high-impact forms

CAPTCHA and security-barrier completion, as well as final submission of a password change, must be handed to the user.

## Dependency updates

The upstream runtime is pinned in `scripts/ocu-runtime.sh` and both MCP configs. A version update should include source/release review, `make verify`, `make build-pip`, `make smoke`, and a real macOS test in at least one native app, one Chromium/Electron app, and Simulator when available.
