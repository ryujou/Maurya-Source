#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {cp, mkdir, readFile, readdir, rm, stat, writeFile} from 'node:fs/promises';
import {dirname, extname, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const toolDirectory=dirname(fileURLToPath(import.meta.url));
const packageDirectory=resolve(toolDirectory,'..');
const repositoryDirectory=resolve(packageDirectory,'../../..');
const sourceDirectory=resolve(repositoryDirectory,'android/app/src/main/assets/effect-editor');
const destinationDirectory=resolve(packageDirectory,'Sources/MauryaEditor/Resources/EditorBundle');
const packageJSON=JSON.parse(await readFile(resolve(repositoryDirectory,'android/effect_editor/package.json'),'utf8'));

if(!destinationDirectory.startsWith(`${packageDirectory}${sep}`)) throw new Error('Destination escaped MauryaEditor package');

const mediaTypes=new Map([
  ['.html','text/html; charset=utf-8'],['.js','text/javascript; charset=utf-8'],['.css','text/css; charset=utf-8'],
  ['.json','application/json; charset=utf-8'],['.svg','image/svg+xml'],['.png','image/png'],['.gif','image/gif'],
  ['.mp3','audio/mpeg'],['.cur','image/x-icon'],
]);

async function filesBelow(root,current=root) {
  const entries=await readdir(current,{withFileTypes:true});
  const result=[];
  for(const entry of entries.sort((a,b)=>a.name.localeCompare(b.name))) {
    const absolute=join(current,entry.name);
    if(entry.isSymbolicLink()) throw new Error(`Symlinks are forbidden: ${absolute}`);
    if(entry.isDirectory()) result.push(...await filesBelow(root,absolute));
    else if(entry.isFile()) result.push({absolute,path:relative(root,absolute).split(sep).join('/')});
  }
  return result;
}

await stat(sourceDirectory);
await rm(destinationDirectory,{recursive:true,force:true});
await mkdir(dirname(destinationDirectory),{recursive:true});
await cp(sourceDirectory,destinationDirectory,{recursive:true,errorOnExist:true,force:false});

const files=await filesBelow(destinationDirectory);
const records=[];
for(const file of files) {
  const data=await readFile(file.absolute);
  const extension=extname(file.path).toLowerCase();
  const mediaType=mediaTypes.get(extension);
  if(!mediaType) throw new Error(`No media type allowlist entry for ${file.path}`);
  records.push({path:file.path,size:data.length,sha256:createHash('sha256').update(data).digest('hex'),mediaType});
}
const canonical=records.map(record=>`${record.path}\0${record.size}\0${record.sha256}`).join('\n');
const bundleSHA256=createHash('sha256').update(canonical).digest('hex');
const manifest={
  formatVersion:1,
  editorVersion:packageJSON.version,
  sourcePackage:'android/effect_editor',
  bundleSHA256,
  generatedAt:`source-tree-sha256:${bundleSHA256}`,
  files:records,
};
await writeFile(join(destinationDirectory,'manifest.json'),`${JSON.stringify(manifest,null,2)}\n`);
console.log(`Synced ${records.length} files; editor ${packageJSON.version}; SHA-256 ${bundleSHA256}`);
