# resQ 2.2.2 candidate evidence

This directory commits the compact qualification record for candidate
`ba41c116c4b661690728ad41cfe354da4041fed6`:

- `release-audit.json` is the schema-v1 gate summary and exact candidate record.
- `checksums.sha256` authenticates every file in the complete raw evidence
  archive retained for the release.

The full archive contains command logs, normal and isolated reports,
differential, coverage, compatibility, upstream qspec differential,
performance, scale, soak, installation, state, and schema artifacts. Its
SHA-256 is
`fcecbc9306cff97fde0979f9906a01d99fb80ddcbbf60663fa7aa1e0821c4f39`.

The final tag is created only after this evidence commit passes the same gate
from a fresh clone. The remote annotated tag and its peeled commit are the
authoritative final-SHA record.
