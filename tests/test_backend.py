import importlib.util,json,os,plistlib,tempfile,unittest
from pathlib import Path
from unittest.mock import patch

ROOT=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('worker',ROOT/'.builder/build.py');worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
class WorkerTests(unittest.TestCase):
 def test_missing_signing_is_not_ready(self):
  with tempfile.TemporaryDirectory()as d:
   old=os.getcwd();os.chdir(d)
   try:
    env={'PROJECT_ID':'test_app','REQUEST_ID':'request01','SOURCE_SHA':'a'*40,'PLATFORM':'both','GITHUB_OUTPUT':d+'/out','GITHUB_STEP_SUMMARY':d+'/summary'}
    with patch.dict(os.environ,env,clear=True):worker.readiness()
    report=json.loads(Path('readiness/Build-Readiness.json').read_text());self.assertFalse(report['ios_ready']);self.assertFalse(report['android_ready']);self.assertEqual(len(report['ios_missing_signing']),4)
   finally:os.chdir(old)
 def test_actual_prepare_and_identifiers(self):
  with tempfile.TemporaryDirectory()as d:
   root=Path(d);source=root/'project';source.mkdir();(source/'lib').mkdir();(source/'test').mkdir();(source/'lib/main.dart').write_text('void main() {}');(source/'test/app_test.dart').write_text('// fixture')
   (source/'project.json').write_text(json.dumps({'project_id':'test_app','app_name':'World Gate & Logistics','bundle_id':'com.worldgate.office'}))
   def flutter(args):
    work=Path(args[-1]);(work/'android/app/src/main').mkdir(parents=True);(work/'ios/Runner.xcodeproj').mkdir(parents=True);(work/'ios/Runner').mkdir()
    (work/'android/app/build.gradle.kts').write_text('android { applicationId = "com.worldgate.test_app" }')
    (work/'android/app/src/main/AndroidManifest.xml').write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="test"/></manifest>')
    (work/'ios/Runner.xcodeproj/project.pbxproj').write_text('PRODUCT_BUNDLE_IDENTIFIER = com.worldgate.test_app;')
    with(work/'ios/Runner/Info.plist').open('wb')as f:plistlib.dump({},f)
   with patch.dict(os.environ,{'PROJECT_ID':'test_app'}):worker.prepare(source,root/'work',flutter)
   self.assertIn('com.worldgate.office',(root/'work/android/app/build.gradle.kts').read_text());self.assertIn('com.worldgate.office',(root/'work/ios/Runner.xcodeproj/project.pbxproj').read_text())
 def test_missing_keys_produces_failure_report(self):
  with tempfile.TemporaryDirectory()as d:
   env={'GITHUB_WORKSPACE':d,'RUNNER_TEMP':d,'PROJECT_ID':'test_app','REQUEST_ID':'request01','SOURCE_SHA':'a'*40,'PLATFORM':'android','GITHUB_RUN_NUMBER':'1'}
   with patch.dict(os.environ,env,clear=True):
    with self.assertRaises(SystemExit):worker.build('android')
   report=json.loads(Path(d,'output/Build-Report.json').read_text());self.assertEqual(report['build_result'],'failure');self.assertFalse(report['signature_verified']);self.assertEqual(report['files'],[])
if __name__=='__main__':unittest.main()
