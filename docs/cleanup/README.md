# Disk cleanup review queue

A lightweight queue for "big file, not sure yet — revisit later" decisions. Lives in `queue.yaml`; query it with `~/bin/cleanup-review`.

## Schema

Each entry under `entries:` has:

| field                | type   | notes                                                   |
|----------------------|--------|---------------------------------------------------------|
| `path`               | string | `~`-relative or absolute                                |
| `size`               | string | human-readable (`6.8 GiB`); free-form, not parsed       |
| `category`           | string | free tag (e.g. `installer-archive`, `model-weights`)    |
| `contents`           | string | what's actually in it                                   |
| `recommended_action` | string | short verb-phrase (`delete`, `extract-pdfs-then-delete`)|
| `reason`             | string | why that action                                         |
| `review_after`       | date   | ISO date (`YYYY-MM-DD`); filter hint, not a deadline    |
| `status`             | enum   | `pending` → `actioned` \| `dismissed`                   |
| `added`              | date   | when the entry was created                              |
| `notes`              | string | optional — commands, gotchas, verification steps        |

## CLI

```
cleanup-review                  # pending, due today or earlier (default)
cleanup-review --due 30         # pending, due within 30 days
cleanup-review --overdue        # pending, review_after < today
cleanup-review --all            # every entry
cleanup-review --actioned       # only actioned
cleanup-review --dismissed      # only dismissed
cleanup-review --yaml           # emit filtered entries as YAML
```

## Workflow

1. Spot a big/old file you can't decide on now.
2. Append an entry with `status: pending` and a realistic `review_after`.
3. On that date (or when `cleanup-review` surfaces it), act.
4. Flip `status` to `actioned` or `dismissed` — keep the entry as a record.
