#!/usr/bin/env python3
"""Build a portable x64 Windows binary with the pinned, externally installed Zig.

ZIG may point to Zig 0.16.0; no toolchain download or machine-wide install here.
On Windows, run: py windows/build.py --zig C:\\tools\\zig\\zig.exe
On macOS, run: python3 windows/build.py --zig /path/to/zig
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import zipfile
import json
import base64
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.1.0-b16'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--zig', default=os.environ.get('ZIG', 'zig'))
    parser.add_argument('--winsparkle-dir',type=Path,default=ROOT/'build/windows-deps/WinSparkle-0.9.4/WinSparkle-0.9.4')
    parser.add_argument('--output-dir',type=Path,default=ROOT/'build/windows')
    args = parser.parse_args()
    zig = str(Path(shutil.which(args.zig) or args.zig).resolve())
    version = subprocess.check_output([zig, 'version'], text=True).strip()
    if version != '0.16.0':
        raise SystemExit('This build is pinned to Zig 0.16.0, found '+version)
    out = args.output_dir.resolve()
    package = out/'DesktopPet-Windows'
    package.mkdir(parents=True, exist_ok=True)
    dependency=json.loads((ROOT/'windows/vendor/winsparkle/dependency.json').read_text())
    dll=args.winsparkle_dir/'x64/Release/WinSparkle.dll'
    if not dll.is_file() or hashlib.sha256(dll.read_bytes()).hexdigest()!=dependency['dllSHA256']:
        raise SystemExit('Missing or mismatched pinned WinSparkle DLL. Use verified official package: '+dependency['archiveURL'])
    key=(ROOT/'windows/src/UpdatePublicKey.inc').read_text()
    match=re.fullmatch(r'inline constexpr char updatePublicKey\[\]="([A-Za-z0-9+/=]+)";\s*',key)
    if not match or len(base64.b64decode(match[1],validate=True))!=32:raise SystemExit('Missing valid fixed Windows update public key')
    log = out/'compile.log'
    env = dict(os.environ, ZIG_LOCAL_CACHE_DIR=str(out/'zig-cache'), ZIG_GLOBAL_CACHE_DIR=str(out/'zig-global-cache'))
    def run(command, cwd=ROOT):
        with log.open('a') as stream:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=stream, stderr=stream)
        if result.returncode:
            print(log.read_text(errors='replace')[-18000:])
            raise SystemExit('Build failed; full log: '+str(log))
    log.write_text('Zig '+version+'\n')
    run([sys.executable, str(ROOT/'windows/tools/generate_yawn.py'), '--output', str(out/'DogYawnData.hpp')])
    resources = ROOT/'windows'/'resources'
    resource = out/'DesktopPet.res'
    run([zig, 'rc', '/c', '65001', '/fo', str(resource), 'DesktopPet.rc'], resources)
    binary = package/'DesktopPet.exe'
    flags=[zig, 'c++', '-target', 'x86_64-windows-gnu', '-std=c++17', '-Os', '-s', '-static',
         '-DWINVER=0x0a00', '-municode', '-Wl,--subsystem,windows',
         '-Wno-nullability-completeness', '-Wno-unused-command-line-argument',
         '-Wall', '-Wextra', '-Wno-missing-field-initializers', '-I', str(out)]
    libraries=['-lgdiplus','-luser32','-lgdi32','-lshell32','-lole32','-lwtsapi32','-luuid','-ladvapi32']
    run(flags+[
         str(ROOT/'windows'/'src'/'DesktopPet.cpp'), str(resource)]+libraries+[
         '-o', str(binary)])
    shutil.copyfile(ROOT/'windows'/'TRIAL.zh-CN.txt', package/'先读我.txt')
    shutil.copyfile(dll,package/'WinSparkle.dll')
    shutil.copyfile(ROOT/'windows/vendor/winsparkle/COPYING',package/'WinSparkle-LICENSE.txt')
    shutil.copyfile(ROOT/'windows/vendor/winsparkle/COPYING.expat',package/'Expat-LICENSE.txt')
    # Installer embeds only reviewed runtime files, never the private checkout.
    def rcpath(p):return str(p).replace('\\','/')
    setup_rc=out/'Setup.rc'
    payloads=['DesktopPet.exe','WinSparkle.dll','WinSparkle-LICENSE.txt','Expat-LICENSE.txt','先读我.txt']
    setup_rc.write_text('#include "'+rcpath(resources/'DesktopPet.rc')+'"\n'+''.join(str(101+i)+' RCDATA "'+rcpath(package/name)+'"\n' for i,name in enumerate(payloads)))
    setup_resource=out/'Setup.res'
    run([zig,'rc','/c','65001','/fo',str(setup_resource),str(setup_rc)],resources)
    installer=out/('DesktopPet-Windows-'+VERSION+'-x64-Setup.exe')
    run(flags+[str(ROOT/'windows/src/Setup.cpp'),str(setup_resource)]+libraries+['-lversion','-o',str(installer)])
    archive = out/('DesktopPet-Windows-'+VERSION+'-x64.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for file in sorted(package.iterdir()):
            if file.name in payloads:
                z.write(file, 'DesktopPet-Windows/'+file.name)
    sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    (out/(archive.name+'.sha256')).write_text(sha+'  '+archive.name+'\n')
    print('Built:', archive)
    print('ZIP bytes:', archive.stat().st_size)
    print('SHA256:', sha)
    print('Installer:',installer,'bytes:',installer.stat().st_size)

if __name__ == '__main__':
    main()
