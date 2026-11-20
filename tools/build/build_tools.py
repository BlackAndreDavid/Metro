#!/usr/bin/env python3
"""Build native desktop bundles on the target OS; Windows produces .exe files."""
import argparse,os,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
STATIC=['index.html','style.css','models.js','editor.js','enhancements.js','workspace.js','catalogs.js','geometry_editor.js','network_editor.js']
def command(tool,work):
 name,folder=('MetroEditor','editors') if tool=='editor' else ('MetroTester','tester')
 args=[sys.executable,'-m','PyInstaller','--noconfirm','--clean','--onedir','--windowed','--name',name,'--distpath',str(ROOT/'tools/bin'),'--workpath',str(work/'work'),'--specpath',str(work/'spec'),'--paths',str(ROOT/'tools'/folder)]
 if tool=='editor':
  for filename in STATIC:args+=['--add-data',str(ROOT/'tools/editors'/filename)+os.pathsep+'editors']
 return args+[str(ROOT/'tools'/folder/'desktop.py')]
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--tool',choices=['editor','tester','all'],default='all');parser.add_argument('--dry-run',action='store_true');args=parser.parse_args()
 with tempfile.TemporaryDirectory(prefix='metro-bundle-') as scratch:
  for tool in (['editor','tester'] if args.tool=='all' else [args.tool]):
   cmd=command(tool,Path(scratch)/tool)
   if args.dry_run:print(subprocess.list2cmdline(cmd))
   else:subprocess.run(cmd,cwd=ROOT,check=True)
if __name__=='__main__':main()
