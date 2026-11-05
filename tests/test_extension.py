import importlib.util,json,os,tempfile,unittest,zipfile
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('extension',Path(__file__).resolve().parent.parent/'.builder/extension.py');extension=importlib.util.module_from_spec(spec);spec.loader.exec_module(extension)
class ExtensionTests(unittest.TestCase):
 def test_build_source_is_not_packaged_and_missing_assets_fail(self):
  with tempfile.TemporaryDirectory()as d,patch.dict(os.environ,{'PROJECT_ID':'test_ext'}):
   root=Path(d);source=root/'source';source.mkdir();(source/'tests').mkdir()
   (source/'project.json').write_text(json.dumps({'project_type':'extension','project_id':'test_ext'}))
   (source/'manifest.json').write_text(json.dumps({'manifest_version':3,'name':'Test','version':'1.0','action':{'default_popup':'popup.html'}}))
   (source/'popup.html').write_text('<button>Test</button>');(source/'tests/extension.test.cjs').write_text('module.exports=async()=>{};')
   manifest=extension.prepare(source,root/'work')
   self.assertEqual(manifest['manifest_version'],3);self.assertFalse((root/'work/tests').exists());self.assertFalse((root/'work/project.json').exists())
   self.assertEqual((root/'work/_builder_icons/icon128.png').read_bytes()[:8],b'\x89PNG\r\n\x1a\n')
   (source/'popup.html').unlink()
   with self.assertRaisesRegex(ValueError,'missing/unsafe'):extension.prepare(source,root/'bad')
 def test_paths_and_versions(self):
  for value in ['../escape.js','.github/workflows/evil.yml','private.key','/popup.html','lib/../../evil.js','project.json']:
   with self.assertRaises(ValueError):extension.safe_path(value)

if __name__=='__main__':unittest.main()
