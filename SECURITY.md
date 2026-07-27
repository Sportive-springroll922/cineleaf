# Security policy

## Supported versions

Cineleaf has no supported binary release yet. Security fixes currently target the `main` branch.

## Report a vulnerability

Use GitHub's private vulnerability reporting feature on this repository. Do not open a public issue for an exploitable vulnerability or include private media, project files, credentials, or personal paths.

Include the affected revision, macOS version, steps to reproduce with synthetic media, impact, and any suggested mitigation. A maintainer will acknowledge a valid report when project availability permits. No bounty program is offered.

## Security boundaries

Cineleaf reads user-selected local media and writes projects, caches, and exports. It has no server component, updater, analytics endpoint, plugin loader, or bundled executable dependency. Media and project files are untrusted input and should fail safely without executing embedded content.
