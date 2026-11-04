#!/usr/bin/env python3
"""Read-only release checks, without executing a Windows binary on the host."""
from pathlib import Path
import argparse
import struct
import zipfile
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[1]

def layout(data):
    u16=lambda at:struct.unpack_from('<H',data,at)[0]
    u32=lambda at:struct.unpack_from('<I',data,at)[0]
    assert data[:2]==b'MZ';pe=u32(0x3c);assert data[pe:pe+4]==b'PE\0\0'
    optional=pe+24;table=optional+u16(pe+20)
    def offset(rva):
        for i in range(u16(pe+6)):
            virtual_size,base,raw_size,raw=struct.unpack_from('<IIII',data,table+40*i+8)
            if base<=rva<base+max(virtual_size,raw_size):return raw+rva-base
        raise AssertionError('Unmapped PE RVA')
    return u16,u32,optional,offset

def export_names(data):
    _,u32,optional,offset=layout(data);directory=offset(u32(optional+112));names=offset(u32(directory+32));result=set()
    for i in range(u32(directory+24)):
        at=offset(u32(names+4*i));result.add(data[at:data.index(b'\0',at)].decode('ascii'))
    return result

def resource(data,kind,identifier):
    u16,u32,optional,offset=layout(data);root=offset(u32(optional+112+16))
    def entries(at):return [(u32(at+16+i*8),u32(at+20+i*8)) for i in range(u16(at+12)+u16(at+14))]
    def child(at,wanted):
        for name,target in entries(at):
            if name==wanted:assert target&0x80000000;return root+(target&0x7fffffff)
        raise AssertionError('Missing resource '+str(wanted))
    language=child(child(root,kind),identifier);_,target=entries(language)[0];assert not target&0x80000000
    entry=root+target;at=offset(u32(entry));return data[at:at+u32(entry+4)]

def audit(binary):
    data=binary.read_bytes()
    u16=lambda offset:struct.unpack_from('<H',data,offset)[0]
    u32=lambda offset:struct.unpack_from('<I',data,offset)[0]
    assert data[:2]==b'MZ'
    pe=u32(0x3c);assert data[pe:pe+4]==b'PE\0\0'
    assert u16(pe+4)==0x8664,'Not x64'
    sections=u16(pe+6);optional=pe+24;assert u16(optional)==0x20b
    assert u16(optional+68)==2,'Must be a GUI application, without a console'
    characteristics=u16(optional+70)
    assert characteristics&0x40 and characteristics&0x100,'ASLR/NX required'
    table=optional+u16(pe+20)
    def offset(rva):
        for index in range(sections):
            s=table+40*index;virtual_size,base,raw_size,raw=struct.unpack_from('<IIII',data,s+8)
            if base<=rva<base+max(virtual_size,raw_size):return raw+rva-base
        raise AssertionError('Unmapped RVA '+hex(rva))
    def cstring(at):return data[at:data.index(b'\0',at)].decode('ascii')
    imports=[]
    directory=optional+112
    at=offset(u32(directory+8))
    while any(data[at:at+20]):
        imports.append(cstring(offset(u32(at+12))));at+=20
    allowed={'gdiplus.dll','user32.dll','gdi32.dll','shell32.dll','ole32.dll','wtsapi32.dll','kernel32.dll','msvcrt.dll','advapi32.dll','ntdll.dll'}
    assert all(i.lower() in allowed or i.lower().startswith('api-ms-win-crt-') for i in imports),imports
    assert not any(x in data.lower() for x in (b'winhttp.dll',b'wininet.dll',b'ws2_32.dll'))
    resource=offset(u32(directory+16));named=u16(resource+12);ids=u16(resource+14)
    resource_types={u32(resource+16+i*8) for i in range(named,named+ids)}
    assert {3,14,16,24}<=resource_types,'Icon, icon group, version and manifest required'
    manifest=b'level="asInvoker"'
    assert manifest in data and b'PerMonitorV2' in data
    assert '/Users/'.encode() not in data,'Private build path leaked'
    assert '/Users/'.encode('utf-16le') not in data
    print('PASS: x64 GUI, ASLR/NX, icon/version/manifest, user privileges, system DLLs only')
    print('Imports:',', '.join(imports))
    return len(data)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('archive',type=Path);args=parser.parse_args()
    with zipfile.ZipFile(args.archive) as archive:
        assert set(archive.namelist())=={'DesktopPet-Windows/'+name for name in ('DesktopPet.exe','WinSparkle.dll','WinSparkle-LICENSE.txt','Expat-LICENSE.txt','先读我.txt')}
        assert archive.testzip() is None
        # Parse in a temporary directory; never execute or install the artifact.
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'DesktopPet.exe';p.write_bytes(archive.read('DesktopPet-Windows/DesktopPet.exe'));size=audit(p)
        assert '尚未在真正的 Windows' in archive.read('DesktopPet-Windows/先读我.txt').decode('utf-8')
        dependency=json.loads((ROOT/'windows/vendor/winsparkle/dependency.json').read_text())
        assert hashlib.sha256(archive.read('DesktopPet-Windows/WinSparkle.dll')).hexdigest()==dependency['dllSHA256']
        app=archive.read('DesktopPet-Windows/DesktopPet.exe')
        assert b'https://desktop-pet-dog.pages.dev/updates/windows-appcast.xml' in app
        key=re.search(r'"([A-Za-z0-9+/=]+)"',(ROOT/'windows/src/UpdatePublicKey.inc').read_text())[1]
        assert key.encode() in app
        assert b'win_sparkle_set_automatic_check_for_updates' in app and b'win_sparkle_set_eddsa_public_key' in app
        required=set(re.findall(r'bind\([^,]+,"([a-z_]+)"\)',(ROOT/'windows/src/DogUpdater.hpp').read_text()))
        assert required and required<=export_names(archive.read('DesktopPet-Windows/WinSparkle.dll'))
        installer=args.archive.with_name(args.archive.stem+'-Setup.exe').read_bytes()
        for i,name in enumerate(('DesktopPet.exe','WinSparkle.dll','WinSparkle-LICENSE.txt','Expat-LICENSE.txt','先读我.txt')):
            assert resource(installer,10,101+i)==archive.read('DesktopPet-Windows/'+name),'Installer embeds stale payload: '+name
        assert b'level="asInvoker"' in resource(installer,24,1)
        print('EXE bytes:',size,'ZIP bytes:',args.archive.stat().st_size)
        print('PASS: pinned WinSparkle DLL, notices, fixed HTTPS feed/public key, explicit updater API binding')
        print('PASS: all updater functions exported by actual DLL; all five embedded installer payloads match final runtime bundle; installer stays asInvoker')
