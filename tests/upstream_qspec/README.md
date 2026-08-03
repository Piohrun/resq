# Pinned qspec compatibility contract

These q files are byte-for-byte copies of qspec's public tests at commit
`9b846b68a8d808e472ba504d18c325b14b468087` (2023-01-30):

- `test_assertions.q`
- `test_ui.q`
- `test_mock.q`
- `test_fuzz.q`
- `fixture_tests/test_file_fixture.q`
- `fixture_tests/test_directory_fixture.q`
- `fixture_tests/test_text_fixture.q`

Their local names start with `qspec_` so resQ's normal recursive discovery does
not execute them twice. `tests/test_qspec_upstream.q` invokes every file through
the qspec-compatible launcher. The fixture test copies live beside the original
fixture tree in `tests/fixture_tests/`; that tree is also byte-identical to the
pinned upstream fixture assets.

Do not edit these test bodies to accommodate resQ. A compatibility failure must
be fixed in resQ, or the pinned upstream commit must be advanced deliberately
with the provenance and license checked again.
