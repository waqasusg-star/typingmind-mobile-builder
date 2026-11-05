import importlib.util,os,tempfile,unittest
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('windows',Path(__file__).resolve().parent.parent/'.builder/windows.py');windows=importlib.util.module_from_spec(spec);spec.loader.exec_module(windows)
class WindowsTests(unittest.TestCase):
 def test_unicode_failure_report_survives_windows_legacy_encoding(self):
  with tempfile.TemporaryDirectory()as d:
   env={'PROJECT_ID':'test_app','REQUEST_ID':'request01','SOURCE_SHA':'a'*40,'PLATFORM':'windows','GITHUB_WORKSPACE':d,'RUNNER_TEMP':d}
   original=Path.write_text
   def legacy_write(path,data,encoding=None,**kwargs):return original(path,data,encoding=encoding or 'cp1252',**kwargs)
   with patch.dict(os.environ,env),patch.object(windows.worker,'prepare',side_effect=ValueError('اختبار ✓')),patch.object(Path,'write_text',legacy_write):
    with self.assertRaises(SystemExit):windows.build()
   self.assertIn('اختبار ✓',Path(d,'output/build.log').read_text(encoding='utf-8'))
   self.assertTrue(Path(d,'output/Build-Report.json').is_file())

if __name__=='__main__':unittest.main()
