# qspec value-domain probe

A resQ-authored qspec suite run by `tools/verify_qspec_differential.py`.
Unmodified upstream qspec and `bin/qspec` must give every test the same
verdict. Every property holds for any value qspec's own generator can produce,
so a pass under upstream qspec and a failure under `bin/qspec` means resQ fed
a qspec property a value qspec never would: a null, an infinity, a negative
real or float, or a long where a boolean was declared. The suite also mixes
`holds` forms with ordinary tests in one `desc`; resQ 2.2.0 failed such files
at load.
