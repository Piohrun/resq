# resQ 2.2.0 candidate evidence

This directory commits the compact qualification record for candidate
`11303c109fcae17206f467e7e1ea81703b8b917a`:

- `release-audit.json` is the schema-v1 gate summary and exact candidate record.
- `checksums.sha256` authenticates every file in the complete raw evidence
  archive retained for the release.

The full archive contains command logs, normal and isolated reports,
differential, coverage, compatibility, upstream qspec differential,
performance, scale, soak, installation, state, and schema artifacts. Its
SHA-256 is
`30ad162944aeb9408fac06e8afa9cffa444dca23c6ef6b20fa837de98903258a`.

The final tag is created only after this evidence commit passes the same gate
from a fresh clone. The remote annotated tag and its peeled commit are the
authoritative final-SHA record.
