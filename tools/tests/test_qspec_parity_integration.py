"""Licensed integration: run explicitly with python3 -m unittest tools.tests.test_qspec_parity_integration."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
import verify_qspec_differential as differential


@unittest.skipUnless(shutil.which('q'), 'requires licensed q runtime')
class PinnedParityTests(unittest.TestCase):
    def test_pinned_projects_through_public_cli(self):
        manifest = json.loads(differential.MANIFEST.read_text())
        with tempfile.TemporaryDirectory(prefix='resq-workplace-parity-') as directory:
            work = Path(directory)
            copies = {}
            for project in manifest['projects']:
                source = differential.verify_vendor(project)
                copies[project['name']] = work/'corpus'/project['name']
                shutil.copytree(source, copies[project['name']], ignore=shutil.ignore_patterns('.resq'))
            qpath, upstream, qinit = differential.write_harness(
                work, copies[manifest['harness']['qspec']], copies[manifest['harness']['qutil']])
            for case in manifest['cases']:
                with self.subTest(case=case['name']):
                    expected = []
                    for entry in case.get('expectedDifferences', []):
                        suite, name = entry['test'].split(' :: ', 1)
                        expected.append(dict(suite=suite, name=name, upstream=entry['upstream'], resq=entry['resq'], reason=entry['reason']))
                    config = {'schemaVersion':1, 'cwd':str(copies[case['project']]),
                              'env':{'QPATH':str(qpath), 'QINIT':None, 'QBIN':shutil.which('q')},
                              'upstream':{'command':[shutil.which('q'),str(upstream),'-q',*case['args']]},
                              'resq':{'command':[str(ROOT/'bin/qspec'),*case['args']], 'env':{'QINIT':str(qinit)}},
                              'expectedDifferences':expected}
                    path = work/(case['name']+'.json'); path.write_text(json.dumps(config))
                    output = work/('evidence-'+case['name'])
                    result = subprocess.run([sys.executable,str(ROOT/'tools/qspec_parity.py'),str(path),'--out-dir',str(output)],
                                            capture_output=True,text=True,timeout=120)
                    self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                    evidence = json.loads((output/'parity.json').read_text())
                    self.assertTrue(evidence['parity'])
                    self.assertEqual(len(evidence['acceptedDifferences']),len(expected))
                    self.assertGreater(len(evidence['runs']['upstream']['tests']),0)


if __name__ == '__main__':
    unittest.main()
