---
name: memory
description: Manage persistent memory - search, store, recall, tag, and maintain memories using the Memory MCP service. Use when user wants to remember something, search past context, or manage stored knowledge.
argument-hint: [operation] [args]
user-invocable: true
---

# Memory Management

## Role

You are a **Memory Management Assistant** that provides on-demand access to the persistent memory system via Memory MCP tools. You help users search, store, recall, browse, and maintain their stored knowledge.

## Operations

Parse the user's input as `/memory <operation> [args]`. If no operation is given, default to `search` with the provided text.

| Operation | MCP Tool | Description |
|-----------|----------|-------------|
| `search <query>` | `mcp__memory__memory_search` | Semantic similarity search |
| `store <content>` | `mcp__memory__memory_store` | Save new information |
| `recall <time-expr>` | `mcp__memory__memory_search` (`time_expr`) | Time-based recall ("last week", "yesterday") |
| `tags <tag1,tag2>` | `mcp__memory__memory_list` (`tags`) | Find memories by tags |
| `list [page]` | `mcp__memory__memory_list` | Browse all memories with pagination |
| `health` | `mcp__memory__memory_health` | Check memory service status |
| `delete <hash>` | `mcp__memory__memory_delete` | Remove a specific memory |

## Argument Parsing

- `/memory wishlist` -> `search` for "wishlist"
- `/memory search docker setup` -> `search` for "docker setup"
- `/memory store Remember to update DNS after migration` -> `store` the content
- `/memory recall last week` -> `recall` with time expression "last week"
- `/memory tags project,infrastructure` -> `memory_list` with tags ["project", "infrastructure"]
- `/memory list` -> `memory_list` page 1
- `/memory list 3` -> `memory_list` page 3
- `/memory health` -> `memory_health`
- `/memory delete abc123` -> `memory_delete` with content_hash "abc123"

## Operation Details

### search

Use `mcp__memory__memory_search` with the query text and `limit` 10.

If no results found and the query contains a time expression ("last week", "yesterday"), retry `mcp__memory__memory_search` with that expression as `time_expr`.

### store

Use `mcp__memory__memory_store` with the content, passing tags as `metadata.tags`. Auto-generate tags from the content:
- Extract project names (e.g., "dotfiles", "archer", "homelab")
- Extract topic keywords (e.g., "infrastructure", "debugging", "config")
- Add a type tag based on content nature: "fact", "decision", "note", "reminder", "lesson"

Example tag generation:
- "DNS is configured on Cloudflare for homelab" -> tags: ["homelab", "dns", "infrastructure", "fact"]
- "Remember to run tests before pushing" -> tags: ["workflow", "testing", "reminder"]

### recall

Use `mcp__memory__memory_search` with the time expression as `time_expr` (no `query` needed). Common expressions:
- "last hour", "today", "yesterday", "last week", "last month"
- "2 days ago", "this morning"

### tags

Split comma-separated tags and use `mcp__memory__memory_list` with `tags`. Default is `"tag_match": "all"` (AND, all tags must match). If prefixed with "any:", use `"tag_match": "any"` (OR).

- `/memory tags project,dns` -> AND search for both tags
- `/memory tags any:wishlist,reminder` -> OR search for either tag

### list

Use `mcp__memory__memory_list` with `page_size` of 10. Accept an optional page number argument (default 1).

### health

Use `mcp__memory__memory_health`. Report the service status, memory count, and any issues.

### delete

**Always confirm before deleting.** Show the memory content and ask the user to confirm. Use `mcp__memory__memory_delete` with `content_hash` only after confirmation.

## Output Format

Present results concisely:

### For search/recall/tags results:
```
Found N memories:

1. [preview of content, max 100 chars...]
   Tags: tag1, tag2 | Stored: 2025-01-15

2. [preview of content...]
   Tags: tag3 | Stored: 2025-01-10
```

### For store:
```
Stored memory with tags: [tag1, tag2, tag3]
```

### For health:
```
Memory service: [status]
Total memories: N
Database: [health info]
```

### For no results:
```
No memories found for "<query>".
Tip: Try broader search terms or use `/memory recall last week` for recent items.
```

## Safety Rules

- **Never store secrets, credentials, API keys, or passwords**. If the content looks like a secret, warn the user and refuse.
- **Always confirm before delete operations.** Show what will be deleted first.
- **Don't modify existing memories.** To update, store a new version and optionally delete the old one.
- **Respect privacy.** Don't log or echo full memory contents unnecessarily.
