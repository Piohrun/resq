"""Migration parity contracts, executable without a q licence."""
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import qspec_parity as parity


def xml(body='<testcase name="should work"/>'):
    return '<testsuites><testsuite name="Suite">' + body + '</testsuite></testsuites>'


def runner(report=None, code=0):
    return {"command": [sys.executable, "-c", f"print({(report or xml())!r});raise SystemExit({code})"]}


class ReportTests(unittest.TestCase):
    def test_duplicates_and_punctuation_do_not_collide(self):
        rows = parity.read_report(xml('<testcase name="a"/><testcase name="a"/><testcase name="a #2"/>'))
        self.assertEqual([r['occurrence'] for r in rows], [1, 2, 1])
        self.assertEqual(len({parity.identity(r['suite'], r['name'], r['occurrence']) for r in rows}), 3)
        self.assertNotEqual(parity.identity('a :: b', 'c', 1), parity.identity('a', 'b :: c', 1))

    def test_single_suite_and_diagnostics(self):
        rows = parity.read_report('startup\n<testsuite name="S"><testcase name="a"><error message="load">trace</error></testcase></testsuite>')
        self.assertEqual(rows[0]['status'], 'error')
        self.assertEqual(rows[0]['diagnostics'][0]['text'], 'trace')

    def test_qspec_xunit(self):
        rows = parity.read_report('<test-suite><test-suite name="S"><test-case label="a" skip="1"/></test-suite></test-suite>')
        self.assertEqual(rows[0]['status'], 'skip')

    def test_invalid_empty_and_concatenated_reports_fail(self):
        for text in ('garbage', '<testsuites/>', xml()+xml(), xml('<testcase/>'), '<!DOCTYPE x>'+xml(),
                     xml().replace('name="Suite"', 'name="Suite" tests="2"')):
            with self.subTest(text=text), self.assertRaises((ValueError, parity.ET.ParseError)):
                parity.read_report(text)

    def test_inventory_verdict_and_stale_allowance(self):
        up = parity.read_report(xml('<testcase name="a"/><testcase name="b"/>'))
        rq = parity.read_report(xml('<testcase name="a"><skipped/></testcase><testcase name="c"/>'))
        expected = [{'suite': 'Suite', 'name': 'a', 'upstream': 'pass', 'resq': 'skip', 'reason': 'tracked issue'}]
        result = parity.comparison(up, rq, expected)
        self.assertEqual(len(result['unexpectedDifferences']), 2)
        self.assertEqual(result['acceptedDifferences'], expected)
        self.assertEqual(len(parity.comparison(up, up, expected)['staleAllowances']), 1)


class ExecutionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='resq-parity-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = {'schemaVersion': 1, 'upstream': runner(), 'resq': runner()}

    def run_config(self):
        path = self.root/'config.json'
        path.write_text(json.dumps(self.config))
        with contextlib.redirect_stdout(io.StringIO()):
            code = parity.run(path, self.root/'evidence')
        return code, json.loads((self.root/'evidence/parity.json').read_text())

    def test_pass_retains_logs_and_structured_inventory(self):
        code, result = self.run_config()
        self.assertEqual(code, 0)
        self.assertTrue(result['suitesGreen'])
        self.assertEqual(len(result['runs']['resq']['tests']), 1)
        self.assertIn('upstream.stdout', result['artifacts'])
        self.assertTrue((self.root/'evidence/summary.txt').exists())

    def test_matching_failures_are_parity_but_not_green(self):
        self.config.update(upstream=runner(xml('<testcase name="a"><failure/></testcase>'), 1),
                           resq=runner(xml('<testcase name="a"><failure/></testcase>'), 1))
        code, result = self.run_config()
        self.assertEqual(code, 0)
        self.assertFalse(result['suitesGreen'])

    def test_zero_exit_cannot_hide_failure(self):
        self.config['resq'] = runner(xml('<testcase name="should work"><failure/></testcase>'))
        code, result = self.run_config()
        self.assertEqual(code, 2)
        self.assertIn('contradicts', ' '.join(result['problems']))

    def test_allowance_cannot_hide_broken_execution(self):
        self.config['resq'] = runner(code=7)
        self.assertEqual(self.run_config()[0], 2)

    def test_both_empty_is_not_parity(self):
        self.config.update(upstream=runner('<testsuites/>'), resq=runner('<testsuites/>'))
        self.assertEqual(self.run_config()[0], 2)

    def test_equal_counts_different_tests_fail(self):
        self.config['resq'] = runner(xml('<testcase name="other"/>'))
        code, result = self.run_config()
        self.assertEqual(code, 1)
        self.assertEqual(len(result['unexpectedDifferences']), 2)

    def test_allowance_must_occur(self):
        self.config['expectedDifferences'] = [{'suite':'Suite', 'name':'should work', 'upstream':'pass', 'resq':'skip', 'reason':'issue'}]
        code, result = self.run_config()
        self.assertEqual(code, 1)
        self.assertEqual(len(result['staleAllowances']), 1)

    def test_shared_environment_overrides_and_cwd(self):
        (self.root/'work').mkdir()
        self.config['cwd'] = 'work'
        self.config['env'] = {'PARITY_MARKER': 'secret value', 'PARITY_REMOVE': 'remove me'}
        script = f"import os;assert os.path.basename(os.getcwd())=='work';assert os.getenv('PARITY_MARKER')=='secret value';assert 'PARITY_REMOVE' not in os.environ;print({xml()!r})"
        self.config['upstream'] = self.config['resq'] = {'command':[sys.executable,'-c',script], 'env':{'PARITY_REMOVE':None}}
        code, result = self.run_config()
        self.assertEqual(code, 0)
        self.assertEqual(result['environmentOverrideNames']['shared'], ['PARITY_MARKER', 'PARITY_REMOVE'])

    def test_file_report_uses_fresh_destination(self):
        script = f"import pathlib,sys;pathlib.Path(sys.argv[1]).write_text({xml()!r})"
        self.config['resq'] = {'command':[sys.executable,'-c',script,'{report}'], 'report':'file'}
        self.assertEqual(self.run_config()[0], 0)
        self.assertTrue((self.root/'evidence/resq.xml').exists())

    def test_missing_file_preserves_other_runner_evidence(self):
        self.config['resq'] = {'command':[sys.executable,'-c','pass','{report}'], 'report':'file'}
        code, result = self.run_config()
        self.assertEqual(code, 2)
        self.assertEqual(len(result['runs']['upstream']['tests']), 1)

    def test_launch_failure_still_runs_other_runner(self):
        self.config['upstream'] = {'command':['/no/such/resq-parity-program']}
        code, result = self.run_config()
        self.assertEqual(code, 2)
        self.assertEqual(len(result['runs']['resq']['tests']), 1)

    def test_timeout_retains_partial_output(self):
        self.config['timeoutSeconds'] = .15
        self.config['resq'] = {'command':[sys.executable,'-c',"import time;print('started',flush=True);time.sleep(10)"]}
        code, result = self.run_config()
        self.assertEqual(code, 2)
        self.assertIn('timeout', ' '.join(result['problems']))
        self.assertIn('started', (self.root/'evidence/resq.stdout').read_text())

    def test_existing_output_is_never_reused(self):
        (self.root/'evidence').mkdir()
        with self.assertRaises(FileExistsError):
            self.run_config()

    @unittest.skipUnless(sys.platform == 'linux', 'process-state probe uses /proc')
    def test_timeout_kills_child_even_when_parent_exits_on_term(self):
        marker = self.root/'child.pid'
        child = f"import os,signal,time,pathlib;signal.signal(signal.SIGTERM,signal.SIG_IGN);pathlib.Path({str(marker)!r}).write_text(str(os.getpid()));time.sleep(60)"
        parent = f"import subprocess,sys,time;subprocess.Popen([sys.executable,'-c',{child!r}]);time.sleep(60)"
        self.config['timeoutSeconds'] = .5
        self.config['resq'] = {'command':[sys.executable,'-c',parent]}
        self.assertEqual(self.run_config()[0], 2)
        pid = int(marker.read_text())
        def alive():
            try:
                return Path(f'/proc/{pid}/stat').read_text().split(') ', 1)[1][0] != 'Z'
            except FileNotFoundError:
                return False
        def cleanup_child():
            if alive():
                try:
                    os.kill(pid, 9)
                except ProcessLookupError:
                    pass
        self.addCleanup(cleanup_child)
        for _ in range(30):
            if not alive():
                break
            time.sleep(.02)
        self.assertFalse(alive(), 'timeout left a live descendant')

    def test_bad_configuration_is_rejected_before_commands(self):
        variants = [dict(self.config, timeoutSeconds=True), dict(self.config, timeoutSeconds=float('inf')),
                    dict(self.config, upstream={'command':'q tests'}), dict(self.config, typo=1),
                    dict(self.config, resq={'command':['q'], 'report':'file'}),
                    dict(self.config, env={'X':3})]
        for config in variants:
            with self.subTest(config=config), self.assertRaises(ValueError):
                parity.validate_config(config, self.root)
        self.assertFalse((self.root/'evidence').exists())


if __name__ == '__main__':
    unittest.main()
