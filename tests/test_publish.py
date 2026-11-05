import hashlib,importlib.util,json,os,tempfile,unittest
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('publisher',Path(__file__).resolve().parent.parent/'.builder/publish.py')
publisher=importlib.util.module_from_spec(spec);spec.loader.exec_module(publisher)

class PublishTests(unittest.TestCase):
 def test_only_matching_successful_signed_package_is_released(self):
  env={'PROJECT_ID':'test_app','REQUEST_ID':'request01','SOURCE_SHA':'a'*40}
  with tempfile.TemporaryDirectory()as d,patch.dict(os.environ,env):
   folder=Path(d);package=folder/'test_app-android.apk';package.write_bytes(b'package-test-fixture')
   report={**env,'project_id':env['PROJECT_ID'],'request_id':env['REQUEST_ID'],'source_sha':env['SOURCE_SHA'],'platform':'android','build_result':'success','analyze_passed':True,'tests_passed':True,'signature_verified':True,'files':[{'name':package.name,'size_bytes':package.stat().st_size,'sha256':hashlib.sha256(package.read_bytes()).hexdigest()}]}
   target=folder/'Build-Report.json';target.write_text(json.dumps(report));(folder/'build.log').write_text('never released')
   self.assertEqual([p.name for p in publisher.verified_files(folder,'android')],[package.name,'Build-Report.json','SHA256SUMS.txt'])
   for key,value in [('source_sha','b'*40),('signature_verified',False),('tests_passed',False),('build_result','failure')]:
    changed={**report,key:value};target.write_text(json.dumps(changed))
    with self.assertRaises(ValueError):publisher.verified_files(folder,'android')
   target.write_text(json.dumps(report));package.write_bytes(b'changed-package')
   with self.assertRaises(ValueError):publisher.verified_files(folder,'android')

if __name__=='__main__':unittest.main()
