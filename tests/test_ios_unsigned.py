import importlib.util,json,os,plistlib,tempfile,unittest,zipfile
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('unsigned',Path(__file__).resolve().parent.parent/'.builder/ios_unsigned.py');unsigned=importlib.util.module_from_spec(spec);spec.loader.exec_module(unsigned)

class UnsignedTests(unittest.TestCase):
 def test_device_bundle_and_payload_checks_reject_simulator_and_profiles(self):
  with tempfile.TemporaryDirectory()as d:
   app=Path(d)/'Runner.app';app.mkdir();(app/'Runner').write_bytes(b'unit-fixture')
   info={'CFBundleIdentifier':'com.worldgate.test','CFBundleExecutable':'Runner','DTPlatformName':'iphoneos','CFBundleSupportedPlatforms':['iPhoneOS']}
   (app/'Info.plist').write_bytes(plistlib.dumps(info));unsigned.inspect_bundle(app,'com.worldgate.test')
   info['DTPlatformName']='iphonesimulator';(app/'Info.plist').write_bytes(plistlib.dumps(info))
   with self.assertRaisesRegex(ValueError,'Simulator'):unsigned.inspect_bundle(app,'com.worldgate.test')
   info['DTPlatformName']='iphoneos';(app/'Info.plist').write_bytes(plistlib.dumps(info));(app/'embedded.mobileprovision').write_bytes(b'profile-fixture')
   with self.assertRaisesRegex(ValueError,'provisioning'):unsigned.inspect_bundle(app,'com.worldgate.test')
   package=Path(d)/'test.ipa'
   with zipfile.ZipFile(package,'w')as z:z.writestr('Payload/Runner.app/Info.plist',plistlib.dumps(info));z.writestr('Payload/Runner.app/Runner',b'fixture')
   unsigned.inspect_ipa(package,'Runner.app','Runner')
   with zipfile.ZipFile(package,'a')as z:z.writestr('../escape',b'fixture')
   with self.assertRaises(ValueError):unsigned.inspect_ipa(package,'Runner.app','Runner')
 def test_unsigned_readiness_needs_no_signing_secrets(self):
  with tempfile.TemporaryDirectory()as d:
   old=os.getcwd();os.chdir(d)
   try:
    env={'PROJECT_ID':'test_app','REQUEST_ID':'request01','SOURCE_SHA':'a'*40,'PLATFORM':'ios_unsigned','GITHUB_OUTPUT':d+'/out','GITHUB_STEP_SUMMARY':d+'/summary'}
    with patch.dict(os.environ,env,clear=True):unsigned.worker.readiness()
    report=json.loads(Path('readiness/Build-Readiness.json').read_text());self.assertTrue(report['ios_unsigned_ready']);self.assertFalse(report['ios_ready'])
   finally:os.chdir(old)

if __name__=='__main__':unittest.main()
