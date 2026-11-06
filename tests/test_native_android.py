import importlib.util,json,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('native_android',ROOT/'.builder/native_android.py');worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
class AndroidPipelineTests(unittest.TestCase):
 def test_controlled_build_preserves_identity_and_ignores_uploaded_scripts(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);source=root/'source';source.mkdir();cfg=dict(project_id='native_app',project_type='native_android',bundle_id='com.worldgate.app',namespace='com.worldgate.code',version='1.9.1',build_number='20',minimum_android=26,target_android=35);(source/'project.json').write_text(json.dumps(cfg));(source/'app/src/main').mkdir(parents=True);(source/'app/src/main/AndroidManifest.xml').write_text('<manifest/>');(source/'build.gradle.kts').write_text('exec unsafe()')
   worker.prepare(source,root/'work');text=(root/'work/app/build.gradle.kts').read_text();self.assertIn('com.worldgate.app',text);self.assertIn('com.worldgate.code',text);self.assertIn('versionCode = 20',text);self.assertNotIn('unsafe',(root/'work/build.gradle.kts').read_text());self.assertIn('testImplementation',text)
 def test_symlink_is_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   source=Path(d)/'source';source.mkdir();(source/'project.json').write_text(json.dumps(dict(project_id='native_app',project_type='native_android',bundle_id='com.worldgate.app',namespace='com.worldgate.code',version='1.9.1',build_number='20',minimum_android=26,target_android=35)));(source/'escape').symlink_to('/etc/passwd')
   with self.assertRaisesRegex(ValueError,'Symlink'):worker.prepare(source,Path(d)/'work')
if __name__=='__main__':unittest.main()
