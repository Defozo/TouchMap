import { tr } from './i18n';
// Bounded raw DEFLATE decoder (RFC 1951). Output allocation and writes are
// constrained before extraction, including archives with forged size headers.
class Bits {
  position = 0;
  value = 0;
  count = 0;
  constructor(private input: Uint8Array) {}
  read(n:number):number {
    while(this.count<n){if(this.position>=this.input.length)throw new Error(tr('tm_b28f3546cd5e'));this.value|=this.input[this.position++]<<this.count;this.count+=8;}
    const value=this.value&((1<<n)-1);this.value>>>=n;this.count-=n;return value;
  }
  align():void{this.value=0;this.count=0;}
}
class Huffman {
  private tables:Map<number,number>[]=[];
  private maximum=0;
  constructor(lengths:number[]) {
    const counts=new Array<number>(16).fill(0),next=new Array<number>(16).fill(0);
    for(const len of lengths){if(len<0||len>15)throw new Error(tr('tm_a3966d5d5b3c'));if(len)counts[len]++;this.maximum=Math.max(this.maximum,len);}
    let code=0,left=1;
    for(let bits=1;bits<=15;bits++){left=(left<<1)-counts[bits];if(left<0)throw new Error(tr('tm_218bdcebd04a'));code=(code+counts[bits-1])<<1;next[bits]=code;this.tables[bits]=new Map<number,number>();}
    lengths.forEach((length,symbol)=>{if(length){let n=next[length]++,reverse=0;for(let i=0;i<length;i++){reverse=(reverse<<1)|(n&1);n>>>=1;}this.tables[length].set(reverse,symbol);}});
  }
  decode(input:Bits):number {
    let code=0;
    for(let n=1;n<=this.maximum;n++){code|=input.read(1)<<(n-1);const symbol=this.tables[n].get(code);if(symbol!==undefined)return symbol;}
    throw new Error(tr('tm_3b0aad97dcdb'));
  }
}
const lengthBase=[3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258];
const lengthExtra=[0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
const distanceBase=[1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];
const distanceExtra=[0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];
export function inflateRaw(input:Uint8Array,expectedSize:number):Uint8Array {
  if(!Number.isInteger(expectedSize)||expectedSize<0||expectedSize>50*1024*1024)throw new Error(tr('tm_dd2feab3c278'));
  const output=new Uint8Array(expectedSize),bits=new Bits(input);let cursor=0,final=0;
  const emit=(value:number):void=>{if(cursor>=output.length)throw new Error(tr('tm_237b84cf9888'));output[cursor++]=value;};
  do {
    final=bits.read(1);const type=bits.read(2);
    if(type===0){bits.align();const len=bits.read(16),inverse=bits.read(16);if((len^inverse)!==65535)throw new Error(tr('tm_b02b0252222f'));for(let i=0;i<len;i++)emit(bits.read(8));continue;}
    if(type===3)throw new Error(tr('tm_98019ed97e4f'));
    let literalLengths:number[]=[],distanceLengths:number[]=[];
    if(type===1){for(let i=0;i<288;i++)literalLengths.push(i<144?8:i<256?9:i<280?7:8);distanceLengths=new Array<number>(32).fill(5);}
    else {
      const hlit=bits.read(5)+257,hdist=bits.read(5)+1,hclen=bits.read(4)+4;
      if(hlit>286)throw new Error(tr('tm_9d652931d454'));
      // RFC code-length alphabet order, kept explicit to avoid transformation.
      const codeOrder=[16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15];
      const codeLengths=new Array<number>(19).fill(0);for(let i=0;i<hclen;i++)codeLengths[codeOrder[i]]=bits.read(3);
      const tree=new Huffman(codeLengths),lengths:number[]=[];
      while(lengths.length<hlit+hdist){const value=tree.decode(bits);if(value<16)lengths.push(value);else {let repeat=0,length=0;if(value===16){if(!lengths.length)throw new Error(tr('tm_06dc2b5ecd0e'));length=lengths[lengths.length-1];repeat=bits.read(2)+3;}else if(value===17)repeat=bits.read(3)+3;else repeat=bits.read(7)+11;if(lengths.length+repeat>hlit+hdist)throw new Error(tr('tm_49680943ba2c'));for(let j=0;j<repeat;j++)lengths.push(length);}}
      literalLengths=lengths.slice(0,hlit);distanceLengths=lengths.slice(hlit);
    }
    if(!literalLengths[256])throw new Error(tr('tm_01662bf55ab8'));
    const literals=new Huffman(literalLengths),distances=new Huffman(distanceLengths);
    while(true){const symbol=literals.decode(bits);if(symbol<256){emit(symbol);continue;}if(symbol===256)break;
      if(symbol>285)throw new Error(tr('tm_55758aafc283'));const index=symbol-257,length=lengthBase[index]+bits.read(lengthExtra[index]);
      const ds=distances.decode(bits);if(ds>29)throw new Error(tr('tm_0202a5b981d0'));const distance=distanceBase[ds]+bits.read(distanceExtra[ds]);
      if(distance>cursor)throw new Error(tr('tm_af03c07560b7'));for(let j=0;j<length;j++)emit(output[cursor-distance]);
    }
  }while(!final);
  if(cursor!==expectedSize||bits.position!==input.length)throw new Error(tr('tm_f8f808bc8a95'));
  return output;
}
const crcTable:number[]=Array.from({length:256},(_,index)=>{let value=index;for(let bit=0;bit<8;bit++)value=(value>>>1)^((value&1)?0xEDB88320:0);return value>>>0;});
export function crc32(bytes:Uint8Array):number {let crc=0xFFFFFFFF;for(let i=0;i<bytes.length;i++)crc=crcTable[(crc^bytes[i])&255]^(crc>>>8);return(crc^0xFFFFFFFF)>>>0;}
