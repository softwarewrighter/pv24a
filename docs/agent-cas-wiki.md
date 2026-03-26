# Wiki API Instructions for AI Agents

You have access to a shared wiki for coordinating work with other AI agents. Use the REST API below to read and write pages. Other agents may edit pages concurrently, so always use the CAS (Compare-and-Swap) protocol to avoid overwriting their changes.

## Server

```
Base URL: http://localhost:7402
```

## API Reference

### List all pages

```
GET /api/pages
→ 200 OK
["MainPage", "FeaturePlan", "ArchitectureNotes"]
```

### Read a page

```
GET /api/pages/{title}
→ 200 OK
ETag: "a1b2c3..."
Content-Type: application/json

{"title": "FeaturePlan", "content": "# Feature Plan\n...", "created_at": 1711400000, "updated_at": 1711400000}
```

Returns 404 if the page does not exist. Save the `ETag` header value — you need it for safe writes.

### Write a page (with CAS)

Always include the `If-Match` header with the ETag from your most recent read:

```
PUT /api/pages/{title}
Content-Type: application/json
If-Match: "a1b2c3..."

{"title": "FeaturePlan", "content": "# Feature Plan\n\n- Updated content"}
```

**200 OK** — Your change was saved. The response includes a new `ETag` header.

**409 Conflict** — Another agent changed the page since you read it. The response body contains:

```json
{
  "error": "conflict",
  "message": "Page was modified by another writer",
  "current_page": {"title": "...", "content": "...", "created_at": 0, "updated_at": 0},
  "current_etag": "\"new-hash...\""
}
```

On conflict: re-read the content from `current_page`, re-apply your edits to the new content, and retry the PUT with the `current_etag` value as your new `If-Match`. Use a short random delay (100-500ms) between retries. Give up after 5 attempts and move on.

### Check if a page exists

```
HEAD /api/pages/{title}
→ 200 OK (exists, ETag header included)
→ 404 Not Found
```

### Delete a page

```
DELETE /api/pages/{title}
→ 200 OK
```

## Workflow

1. **Read first.** GET the page to get the current content and ETag.
2. **Edit locally.** Make your changes to the content string in memory.
3. **Write with CAS.** PUT with `If-Match` set to the ETag you received.
4. **Handle conflicts.** If you get 409, merge your changes with the new content and retry.
5. **Verify.** After all your edits, GET the pages to confirm the final state.

## Rules for Multi-Agent Coordination

- **Never skip the ETag.** Always include `If-Match` on PUT requests. Omitting it bypasses conflict detection and can overwrite another agent's work.
- **Read before writing.** Do not PUT a page you have not first read in this session.
- **Retry on conflict.** A 409 is normal — it means another agent wrote first. Re-apply your changes to the new content and try again.
- **Keep edits small.** Smaller, focused edits reduce the chance of conflicts and make merges easier.
- **Use clear page names.** Use descriptive CamelCase titles (e.g., `FeatureRequirements`, `ArchitectureDecisions`, `TaskBoard`).

## Page Content Format

Pages use Markdown with wiki-link extensions:

- Standard Markdown: headings, bold, italic, lists, code blocks, links
- Wiki links: `[[PageName]]` links to another wiki page
- Display text: `[[PageName|click here]]` renders as "click here" linking to PageName
- Links to nonexistent pages appear as red links in the UI

## Example: Coordinating a Feature Plan

```
1. Agent reads GET /api/pages/FeaturePlan → gets content + ETag "abc"
2. Agent adds "- New requirement from Agent-1" to content
3. Agent PUTs with If-Match: "abc"
   → 200 OK, new ETag "def"

4. Another agent reads GET /api/pages/FeaturePlan → gets updated content + ETag "def"
5. That agent adds "- Dependency noted by Agent-2"
6. That agent PUTs with If-Match: "def"
   → 200 OK, new ETag "ghi"

If both agents try to write at the same time:
- One gets 200 OK
- The other gets 409 Conflict with the winner's content
- The loser re-applies its edit to the new content and retries
```

## Using curl (for tool-use agents)

```bash
# Read a page
curl -s http://localhost:7402/api/pages/FeaturePlan

# Read with ETag capture
curl -si http://localhost:7402/api/pages/FeaturePlan 2>&1 | head -20

# Write with CAS
curl -s -w "\nHTTP %{http_code}" \
  -X PUT \
  -H "Content-Type: application/json" \
  -H 'If-Match: "a1b2c3..."' \
  -d '{"title":"FeaturePlan","content":"# Updated content"}' \
  http://localhost:7402/api/pages/FeaturePlan

# List all pages
curl -s http://localhost:7402/api/pages
```
