#!/bin/bash
# Watch the current Claude Code session transcript

# Simple readable view (recommended)
watch -n 1 'tail -5 /home/cadrianmae/.claude/projects/-home-cadrianmae/656914fa-7562-4f6e-b68a-af74645c68c1.jsonl | jq -r "
if .type == \"user\" then
  \"[\(.timestamp // \"no-time\")] USER: \(.message.content)\"
elif .type == \"assistant\" then
  \"[\(.timestamp // \"no-time\")] ASSISTANT: \(.message.content[0].text // .message.content[0].name // \"[tool use]\")\"
else
  \"[\(.timestamp // \"no-time\")] \(.type)\"
end
"'

# Alternative: Compact view (uncomment to use)
# watch -n 1 'tail -3 /home/cadrianmae/.claude/projects/-home-cadrianmae/656914fa-7562-4f6e-b68a-af74645c68c1.jsonl | jq -c .'

# Alternative: Messages only (uncomment to use)
# watch -n 1 'tail -10 /home/cadrianmae/.claude/projects/-home-cadrianmae/656914fa-7562-4f6e-b68a-af74645c68c1.jsonl | jq -r "select(.type == \"user\" or .type == \"assistant\") | \"\(.type | ascii_upcase): \(.message.content[0].text // .message.content // \"[tool use]\")\""'
