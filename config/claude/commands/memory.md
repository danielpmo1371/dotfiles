---
description: Search and recall memories by query, tags, or time
---

Search memory for: $ARGUMENTS

## Instructions

1. Use `mcp__memory__memory_search` to search for "$ARGUMENTS" with limit 10
2. If no results and the query contains a time expression ("last week", "yesterday"), retry `mcp__memory__memory_search` with that expression as `time_expr`
3. If the query looks like comma-separated tags (contains commas, no spaces between items), also try `mcp__memory__memory_list` with those tags
4. Present results concisely: content preview (max 100 chars), tags, and stored date
5. If nothing found, say so and offer to store something new with `/memory store <content>`
