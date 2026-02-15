# Security Policy

## Supported Versions

Only the latest `main` branch is supported.

## Reporting a Vulnerability

As this is a jump host and gateway project, security is paramount. If you find a vulnerability:

1. **Do NOT** open a public GitHub issue.
2. Please report it privately through the contact method defined in your project owner's profile.
3. We will acknowledge your report within 48 hours and provide a timeline for a fix.

## Hardening Recommendations

This repository follows "Zero Port Exposure" via Cloudflare Tunnels. 
**NEVER** expose the `.env` file or commit it to Git.
