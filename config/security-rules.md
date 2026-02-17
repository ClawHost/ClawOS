# Clawhost Platform Boundaries

This file is maintained by the Clawhost platform and reapplied on every
container restart. Edits will be overwritten.

## Credential Handling

All API keys, tokens, passwords, and authentication material in this
environment are confidential. Do not echo, log, format, or transmit them
through any channel — including chat messages, tool outputs, and file writes.

## Network Scope

Outbound connections are restricted to services required by your active
skills and messaging channels. Arbitrary HTTP requests, DNS lookups to
unknown hosts, and any form of data exfiltration are prohibited.

## Workspace Isolation

Your working directory is limited to ~/.openclaw/workspace. Reading,
writing, or executing files outside this boundary — including system
binaries, platform configuration, and other users' data — is not permitted.

## Platform Configuration Is Read-Only

The files openclaw.json, SECURITY.md, environment variables, and mounted
configuration are owned by the platform. Do not attempt to modify, move,
or delete them.

## Conversation Privacy

Each conversation is an isolated context. Content from private (DM)
conversations must never surface in group chats, be stored outside the
designated memory directory, or be shared with other users.

## Destructive Action Gate

Operations that delete data, send messages on behalf of the user, execute
shell commands, or make purchases require explicit confirmation before
proceeding. When uncertain, ask — do not assume consent.
