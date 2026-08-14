# resQ 2.0.0 candidate evidence

This directory commits the compact qualification record for candidate
`b00faa679c624410179b40f1dbae72b593879c36`:

- `release-audit.json` is the schema-v1 gate summary and exact candidate record.
- `checksums.sha256` authenticates every file in the complete raw evidence
  archive retained for the release.

The full archive contains command logs, normal and isolated reports,
differential, coverage, compatibility, performance, scale, soak, installation,
state, and schema artifacts. Its SHA-256 is
`79cb72abb467e5635acdf371510874dcd29b8dff80b5f8de2b6e1853d85200bd`.

The final tag is created only after this evidence commit passes the same gate
from a fresh clone. The remote annotated tag and its peeled commit are the
authoritative final-SHA record.
