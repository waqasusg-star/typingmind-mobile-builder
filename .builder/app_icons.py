"""Controlled opaque AppIcon generation and archive checks; no uploaded scripts."""
import json,re,struct,zipfile,zlib
from pathlib import Path

PROFILE='generated_v1'
CATALOG='GeneratedAssets.xcassets'
SPEC='Resources/AppIcon.json'
SIZES=[('iphone',20,2),('iphone',20,3),('iphone',29,2),('iphone',29,3),
       ('iphone',40,2),('iphone',40,3),('iphone',60,2),('iphone',60,3),
       ('ipad',20,1),('ipad',20,2),('ipad',29,1),('ipad',29,2),
       ('ipad',40,1),('ipad',40,2),('ipad',76,1),('ipad',76,2),
       ('ipad',83.5,2),('ios-marketing',1024,1)]

RENDERER=r'''import AppKit
import Foundation
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let spec = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as! [String:String]
func color(_ hex: String) -> NSColor {
 let n = UInt32(hex.dropFirst(), radix:16)!
 return NSColor(deviceRed:CGFloat((n >> 16) & 255)/255, green:CGFloat((n >> 8) & 255)/255, blue:CGFloat(n & 255)/255, alpha:1)
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:1024, pixelsHigh:1024,
 bitsPerSample:8, samplesPerPixel:3, hasAlpha:false, isPlanar:false,
 colorSpaceName:.deviceRGB, bytesPerRow:1024*3, bitsPerPixel:24)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
color(spec["background"]!).setFill()
NSBezierPath(rect:NSRect(x:0,y:0,width:1024,height:1024)).fill()
let fg = color(spec["foreground"]!)
fg.setStroke(); fg.setFill()
let path=NSBezierPath(); path.lineWidth=66; path.lineCapStyle = .round; path.lineJoinStyle = .round
switch spec["symbol"]! {
case "pulse":
 path.move(to:NSPoint(x:170,y:500)); path.line(to:NSPoint(x:340,y:500));
 path.line(to:NSPoint(x:430,y:695)); path.line(to:NSPoint(x:535,y:330));
 path.line(to:NSPoint(x:640,y:540)); path.line(to:NSPoint(x:855,y:540)); path.stroke()
case "play":
 path.move(to:NSPoint(x:375,y:265)); path.line(to:NSPoint(x:770,y:512));
 path.line(to:NSPoint(x:375,y:759)); path.close(); path.fill()
case "bolt":
 path.move(to:NSPoint(x:555,y:830)); path.line(to:NSPoint(x:290,y:460));
 path.line(to:NSPoint(x:490,y:460)); path.line(to:NSPoint(x:445,y:195));
 path.line(to:NSPoint(x:745,y:570)); path.line(to:NSPoint(x:540,y:570)); path.close(); path.fill()
default:
 let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:400,weight:.bold),.foregroundColor:fg]
 let text=spec["initials"]! as NSString; let size=text.size(withAttributes:attrs)
 text.draw(at:NSPoint(x:(1024-size.width)/2,y:(1024-size.height)/2),withAttributes:attrs)
}
NSGraphicsContext.restoreGraphicsState()
guard let png=bitmap.representation(using:.png,properties:[:]) else { fatalError("PNG encoding failed") }
try png.write(to:output,options:.atomic)
'''

def enabled(cfg):return cfg.get('app_icon_profile','none')==PROFILE

def load_spec(source,cfg):
    profile=cfg.get('app_icon_profile','none')
    if profile not in {'none',PROFILE}:raise ValueError('Unsupported app icon profile')
    if not enabled(cfg):return None
    path=source/SPEC
    custom={}
    if path.exists():
        if path.is_symlink() or not path.is_file() or path.stat().st_size>4096:raise ValueError('Unsafe app icon spec')
        custom=json.loads(path.read_text())
        if not isinstance(custom,dict) or set(custom)-{'background','foreground','symbol','initials'}:raise ValueError('Unknown app icon spec fields')
    words=re.findall(r'[A-Za-z0-9]+',cfg['app_name'])
    initials=''.join(w[0] for w in words[:2]).upper() or 'A'
    spec={'background':'#153E75','foreground':'#FFFFFF','symbol':'initials','initials':initials,**custom}
    if any(not isinstance(v,str) for v in spec.values()):raise ValueError('Icon spec must contain strings')
    if any(not re.fullmatch(r'#[0-9A-Fa-f]{6}',spec[k]) for k in ['background','foreground']):raise ValueError('Icon colors must use #RRGGBB')
    if spec['symbol'] not in {'pulse','play','bolt','initials'}:raise ValueError('Unsupported icon symbol')
    if not re.fullmatch(r'[A-Z0-9]{1,2}',spec['initials']):raise ValueError('Icon initials must be 1–2 uppercase letters/digits')
    return spec

def png_size(data):
    if len(data)<33 or data[:8]!=b'\x89PNG\r\n\x1a\n' or data[12:16]!=b'IHDR':raise ValueError('Invalid generated AppIcon PNG')
    offset=8;seen_data=False;ended=False
    while offset+12<=len(data):
        length=struct.unpack('>I',data[offset:offset+4])[0]
        end=offset+12+length
        if end>len(data):raise ValueError('Truncated AppIcon PNG')
        kind=data[offset+4:offset+8];chunk=data[offset+4:offset+8+length]
        crc=struct.unpack('>I',data[offset+8+length:end])[0]
        if zlib.crc32(chunk)&0xffffffff!=crc:raise ValueError('AppIcon PNG checksum mismatch')
        if kind==b'IDAT':seen_data=True
        if kind==b'IEND':
            ended=length==0 and end==len(data)
            break
        offset=end
    if not seen_data or not ended:raise ValueError('Incomplete AppIcon PNG')
    return struct.unpack('>II',data[16:24])

def prepare(source,work,cfg,run):
    spec=load_spec(source,cfg)
    if spec is None:return
    assets=work/CATALOG;icons=assets/'AppIcon.appiconset';icons.mkdir(parents=True)
    (assets/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
    spec_path=work/'AppIcon-input.json';spec_path.write_text(json.dumps(spec))
    renderer=work/'RenderAppIcon.swift';renderer.write_text(RENDERER)
    executable=work/'RenderAppIcon'
    run(['xcrun','swiftc',renderer,'-o',executable],work)
    master=icons/'Icon-1024.png';run([executable,spec_path,master],work)
    if png_size(master.read_bytes())!=(1024,1024):raise ValueError('Master AppIcon must be 1024 square')
    entries=[];created={1024}
    for idiom,size,scale in SIZES:
        pixels=int(size*scale);name=f'Icon-{pixels}.png'
        if pixels not in created:
            run(['sips','-z',str(pixels),str(pixels),master,'--out',icons/name],work)
            created.add(pixels)
        if png_size((icons/name).read_bytes())!=(pixels,pixels):raise ValueError('Generated AppIcon size mismatch')
        entries.append({'idiom':idiom,'size':f'{size:g}x{size:g}','scale':f'{scale}x','filename':name})
    (icons/'Contents.json').write_text(json.dumps({'images':entries,'info':{'author':'xcode','version':1}},indent=2))

def configure_spec(target,cfg):
    if not enabled(cfg):return
    target['sources'].append({'path':CATALOG})
    target['settings']['base']['ASSETCATALOG_COMPILER_APPICON_NAME']='AppIcon'

def verify_bundle(app,info,cfg):
    if not enabled(cfg):return {'app_icon_profile':cfg.get('app_icon_profile','none'),'app_icon_verified':False}
    primary=info.get('CFBundleIcons',{}).get('CFBundlePrimaryIcon',{})
    if primary.get('CFBundleIconName')!='AppIcon' or not primary.get('CFBundleIconFiles'):raise ValueError('Archived app is missing compiled AppIcon plist keys')
    assets=app/'Assets.car'
    if not assets.is_file() or assets.stat().st_size<64:raise ValueError('Archived app lacks a compiled Assets.car')
    raster=[p for p in app.glob('AppIcon*.png') if p.is_file() and not p.is_symlink()]
    if not raster:raise ValueError('Archived app lacks exported AppIcon PNGs')
    for p in raster:
        w,h=png_size(p.read_bytes())
        if w!=h or w<20:raise ValueError('Archived app icon is not a valid square PNG')
    return {'app_icon_profile':PROFILE,'app_icon_verified':True,'app_icon_name':'AppIcon','app_icon_files':[p.name for p in raster]}

def verify_ipa(archive,prefix,cfg):
    if not enabled(cfg):return
    import plistlib
    info=plistlib.loads(archive.read(prefix+'Info.plist'))
    primary=info.get('CFBundleIcons',{}).get('CFBundlePrimaryIcon',{})
    names=archive.namelist()
    if primary.get('CFBundleIconName')!='AppIcon' or not primary.get('CFBundleIconFiles') or prefix+'Assets.car' not in names:raise ValueError('Packaged IPA is missing compiled AppIcon assets')
    icons=[n for n in names if n.startswith(prefix+'AppIcon') and n.endswith('.png') and '/' not in n[len(prefix):]]
    if not icons:raise ValueError('Packaged IPA is missing exported AppIcon PNGs')
    for name in icons:png_size(archive.read(name))

def package_source(work,archive,prefix,cfg):
    if not enabled(cfg):return
    root=work/CATALOG
    if not root.is_dir():raise ValueError('Rebuildable source lacks generated AppIcon catalog')
    for path in sorted(root.rglob('*')):
        if path.is_symlink():raise ValueError('Unsafe AppIcon source symlink')
        if path.is_file():archive.write(path,prefix+'/'+path.relative_to(work).as_posix())

def verify_release(report,package):
    if report.get('app_icon_profile')!=PROFILE:return
    if report.get('app_icon_verified') is not True:raise ValueError('Release lacks compiled AppIcon verification')
    with zipfile.ZipFile(package) as archive:verify_ipa(archive,'Payload/'+report['scheme']+'.app/',report)
