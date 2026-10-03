// Inspect recordings without trusting author-supplied duration or MIME labels.
export function wavDuration(bytes:Uint8Array):number {
  const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
  const text=(start:number):string=>String.fromCharCode(bytes[start],bytes[start+1],bytes[start+2],bytes[start+3]);
  if(bytes.length<44||text(0)!=='RIFF'||text(8)!=='WAVE'||view.getUint32(4,true)+8!==bytes.length)throw new Error('Invalid WAV container');
  let position=12,rate=0,block=0,data=-1;
  while(position+8<=bytes.length){const kind=text(position),size=view.getUint32(position+4,true),start=position+8;
    if(start+size>bytes.length)throw new Error('Truncated WAV chunk');
    if(kind==='fmt '){if(rate||size<16)throw new Error('Invalid WAV format chunk');const format=view.getUint16(start,true),channels=view.getUint16(start+2,true),sampleRate=view.getUint32(start+4,true),bits=view.getUint16(start+14,true);rate=view.getUint32(start+8,true);block=view.getUint16(start+12,true);
      if(format!==1||channels<1||channels>2||sampleRate<8000||sampleRate>192000||![8,16,24,32].includes(bits)||block!==channels*bits/8||rate!==sampleRate*block)throw new Error('Use an uncompressed PCM WAV recording');
    }else if(kind==='data'){if(data!==-1)throw new Error('Multiple WAV data chunks');data=size;}
    position=start+size+(size%2);
  }
  if(position!==bytes.length||!rate||data<=0||data%block!==0)throw new Error('Invalid WAV audio data');
  const duration=Math.round(data/rate*1000);if(duration<1||duration>3600000)throw new Error('Recording duration exceeds limits');return duration;
}
export function assertSafeSvg(text:string):void {
  if(/<!DOCTYPE|<!ENTITY|<\?|\son[a-z]+\s*=|(?:[\w.-]+:)?href\s*=|@import|\\/i.test(text.replace(/^\s*<\?xml[^?]*\?>/i,'')))throw new Error('SVG active content or external resources are unsupported');
  const allowed=['svg','g','defs','marker','title','desc','text','tspan','rect','circle','ellipse','polygon','polyline','line','path','metadata'];
  const tags=/<\/?\s*([a-zA-Z_][\w:.-]*)\b/g;let match:RegExpExecArray|null;
  while((match=tags.exec(text))!==null){if(!allowed.includes(match[1]))throw new Error(`Unsupported SVG element: ${match[1]}. Use a safe raster rendering.`);}
  const urls=/url\s*\(([^)]*)\)/gi;
  while((match=urls.exec(text))!==null){if(!/^\s*['"]?#[a-zA-Z_][\w.-]*['"]?\s*$/.test(match[1]))throw new Error('External SVG URL rejected');}
  if(/\b(filter|mask|clip-path|class)\s*=/i.test(text))throw new Error('Unsupported SVG effect or stylesheet');
}

function xmlText(value:string):string {
  if (/&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)/.test(value)) { throw new Error('Unsupported XML entity'); }
  return value.replace(/&(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);/g, (entity:string):string => {
    if (entity==='&amp;') return '&'; if (entity==='&lt;') return '<'; if (entity==='&gt;') return '>';
    if (entity==='&quot;') return '"'; if (entity==='&apos;') return "'";
    const code=entity.startsWith('&#x')?parseInt(entity.slice(3,-1),16):parseInt(entity.slice(2,-1),10);
    if (!(code===9||code===10||code===13||code>=32&&code<=0xD7FF||code>=0xE000&&code<=0xFFFD||code>=0x10000&&code<=0x10FFFF)) { throw new Error('Invalid XML character reference'); }
    return String.fromCodePoint(code);
  });
}
function assertPassiveStyle(value:string):void {
  if (/\\|\/\*|@import|expression\s*\(|javascript\s*:/i.test(value)) { throw new Error('Active or escaped SVG styles are unsupported'); }
  const urls=/url\s*\(([^)]*)\)/gi; let match:RegExpExecArray|null;
  while((match=urls.exec(value))!==null) {
    let reference=match[1].trim();
    if(reference.length>=2&&(reference[0]==='"'||reference[0]==="'")&&reference[reference.length-1]===reference[0]) { reference=reference.slice(1,-1); }
    if(!/^#[a-zA-Z_][\w.-]*$/.test(reference)) { throw new Error('External SVG URL rejected'); }
  }
}
// This wider source-retention profile is used only after decoding and hashing a
// PNG preview. The UI renders that PNG; it never asks the native SVG renderer to
// approximate CSS, gradients, clipping or filters in this original source.
export function assertPassiveSvg(text:string):void {
  const source=text.replace(/^\s*<\?xml\b[^?]*\?>/i,'');
  if(source.length>10*1024*1024) { throw new Error('SVG source exceeds 10 MiB'); }
  const forbidden=['script','foreignobject','image','use','iframe','object','embed','audio','video','animate','set','animatetransform','animatemotion','discard'];
  const tokens=/<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\/?[a-zA-Z_][\w:.-]*(?:\s+[a-zA-Z_][\w:.-]*\s*=\s*(?:"[^"<]*"|'[^'<]*'))*\s*\/?>|[^<]+/g;
  const stack:string[]=[]; let position=0,roots=0,nodes=0; let token:RegExpExecArray|null;
  while((token=tokens.exec(source))!==null) {
    if(token.index!==position) { throw new Error('Malformed or active SVG XML'); }
    const part=token[0]; position=tokens.lastIndex;
    if(part.startsWith('<!--')) { if(part.slice(4,-3).includes('--'))throw new Error('Malformed SVG comment'); continue; }
    if(part.startsWith('<![CDATA[')) {
      if(!stack.length)throw new Error('CDATA outside SVG root');
      if(stack[stack.length-1].split(':').pop()==='style')assertPassiveStyle(part.slice(9,-3));
      continue;
    }
    if(!part.startsWith('<')) {
      if(!stack.length&&part.trim())throw new Error('Text outside SVG root');
      if(part.includes(']]>'))throw new Error('Malformed SVG text');
      const value=xmlText(part);
      if(stack.length&&stack[stack.length-1].split(':').pop()==='style')assertPassiveStyle(value);
      continue;
    }
    const nameMatch=/^<\/?([a-zA-Z_][\w:.-]*)/.exec(part)!; const name=nameMatch[1],local=name.split(':').pop()!;
    if(part.startsWith('</')) {
      if(!/^<\/[a-zA-Z_][\w:.-]*\s*>$/.test(part)||stack.pop()!==name)throw new Error('Unbalanced SVG elements');
      continue;
    }
    if(++nodes>10000||stack.length>=64)throw new Error('SVG complexity limit');
    if(!stack.length) { roots++; if(roots!==1||local!=='svg')throw new Error('Expected one SVG root'); }
    if(forbidden.includes(local.toLowerCase()))throw new Error('Active or external SVG element rejected');
    const attributes=/\s+([a-zA-Z_][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
    const names=new Set<string>(); let attribute:RegExpExecArray|null;
    while((attribute=attributes.exec(part))!==null) {
      const key=attribute[1],localKey=key.split(':').pop()!.toLowerCase();
      if(names.has(key)||localKey.startsWith('on')||localKey==='href'||localKey==='src')throw new Error('Duplicate, active or external SVG attribute');
      names.add(key); assertPassiveStyle(xmlText(attribute[2]===undefined?attribute[3]:attribute[2]));
    }
    if(!part.endsWith('/>'))stack.push(name);
  }
  if(position!==source.length||stack.length||roots!==1)throw new Error('Malformed or incomplete SVG source');
}

export interface PcmWav { sampleRate:number; channels:number; bitsPerSample:number; blockAlign:number; byteRate:number; dataOffset:number; dataLength:number; durationMs:number; }
export function parsePcmWav(bytes:Uint8Array):PcmWav {
  const duration=wavDuration(bytes),view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
  const result:PcmWav={sampleRate:0,channels:0,bitsPerSample:0,blockAlign:0,byteRate:0,dataOffset:0,dataLength:0,durationMs:duration};
  for(let position=12;position+8<=bytes.length;){
    const kind=String.fromCharCode(bytes[position],bytes[position+1],bytes[position+2],bytes[position+3]),size=view.getUint32(position+4,true),start=position+8;
    if(kind==='fmt '){result.channels=view.getUint16(start+2,true);result.sampleRate=view.getUint32(start+4,true);result.byteRate=view.getUint32(start+8,true);result.blockAlign=view.getUint16(start+12,true);result.bitsPerSample=view.getUint16(start+14,true);}
    if(kind==='data'){result.dataOffset=start;result.dataLength=size;}
    position=start+size+(size%2);
  }
  return result;
}
