---
description: Search and recall memories by query, tags, or time
---

Search memory for: $ARGUMENTS

## Instructions

1. Use `mcp__memory__retrieve_memory` to search for "$ARGUMENTS" with limit 10 and similarity_threshold 0.6
2. If no results, try `mcp__memory__recall_memory` with the same query
3. If the query looks like comma-separated tags (contains commas, no spaces between items), also try `mcp__memory__search_by_tag` with those tags
4. Present results concisely: content preview (max 100 chars), tags, and stored date
5. If nothing found, say so and offer to store something new with `/memory store <content>`
