// Inspect untrusted JSON before JSON.parse: duplicate decoded properties and
// excessive nesting must be rejected instead of silently changing the contract.
class JsonInspection {
  private position: number = 0;
  private nodes: number = 0;
  constructor(private text: string) {}
  private whitespace(): void { while(this.position<this.text.length&&[9,10,13,32].includes(this.text.charCodeAt(this.position)))this.position++; }
  private fail(): never { throw new Error('Malformed, duplicate-key or unbounded JSON document.'); }
  private take(character: string): void { this.whitespace();if(this.text[this.position]!==character)this.fail();this.position++; }
  private string(): string {
    const start=this.position;this.position++;
    while(this.position<this.text.length) {
      const code=this.text.charCodeAt(this.position++);
      if(code===34) { return JSON.parse(this.text.substring(start,this.position)) as string; }
      if(code<32)this.fail();
      if(code===92) {
        const escape=this.text[this.position++];
        if(escape==='u') { for(let i=0;i<4;i++){if(!/[0-9a-fA-F]/.test(this.text[this.position]||''))this.fail();this.position++;} }
        else if(!['"','\\','/','b','f','n','r','t'].includes(escape))this.fail();
      }
    }
    return this.fail();
  }
  private digit(): boolean { const code=this.text.charCodeAt(this.position);return code>=48&&code<=57; }
  private number(): void {
    const start=this.position;
    if(this.text[this.position]==='-')this.position++;
    if(this.text[this.position]==='0')this.position++;
    else { if(!this.digit())this.fail();while(this.digit())this.position++; }
    if(this.text[this.position]==='.') { this.position++;if(!this.digit())this.fail();while(this.digit())this.position++; }
    if(this.text[this.position]==='e'||this.text[this.position]==='E') {this.position++;if(this.text[this.position]==='+'||this.text[this.position]==='-')this.position++;if(!this.digit())this.fail();while(this.digit())this.position++;}
    if(!Number.isFinite(Number(this.text.substring(start,this.position))))this.fail();
  }
  private value(depth: number): void {
    if(depth>32||++this.nodes>1000000)this.fail();this.whitespace();const character=this.text[this.position];
    if(character==='{') {
      this.position++;this.whitespace();const names=new Set<string>();
      if(this.text[this.position]==='}'){this.position++;return;}
      while(true){this.whitespace();if(this.text[this.position]!=='"')this.fail();const name=this.string();if(names.has(name))this.fail();names.add(name);this.take(':');this.value(depth+1);this.whitespace();if(this.text[this.position]==='}'){this.position++;return;}this.take(',');}
    }
    if(character==='[') {
      this.position++;this.whitespace();if(this.text[this.position]===']'){this.position++;return;}
      while(true){this.value(depth+1);this.whitespace();if(this.text[this.position]===']'){this.position++;return;}this.take(',');}
    }
    if(character==='"'){this.string();return;}
    for(const literal of ['true','false','null'])if(this.text.substring(this.position,this.position+literal.length)===literal){this.position+=literal.length;return;}
    this.number();
  }
  inspect(): void { this.value(0);this.whitespace();if(this.position!==this.text.length)this.fail(); }
}
export function assertBoundedJson(text: string): void {
  if(typeof text!=='string'||text.length>16*1024*1024)throw new Error('JSON exceeds the supported document size.');
  new JsonInspection(text).inspect();
}
