import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { assertPassiveSvg, assertSafeSvg } from '../app/entry/src/main/ets/domain/media';

test('backend CSS fixture passes preview retention profile while local renderer profile rejects it', () => {
  const source=fs.readFileSync('contracts/fixtures/passive-svg.svg','utf8');
  assert.doesNotThrow(()=>assertPassiveSvg(source));
  assert.throws(()=>assertSafeSvg(source));
  assert.doesNotThrow(()=>assertPassiveSvg('<?xml version="1.0"?><svg><style><![CDATA[rect { fill: red; }]]></style><rect fill="url(\'&#35;shade\')"/></svg>'));
});

test('preview profile rejects active or external XML including entity-obscured styles', () => {
  for(const source of [
    '<svg><script>alert(1)</script></svg>', '<svg><foreignObject/></svg>', '<svg><image href="file:///secret"/></svg>',
    '<svg xmlns:x="urn:example"><x:script/></svg>', '<svg><style>@import "https://example.test/x";</style></svg>',
    '<svg><style><![CDATA[rect { fill: url(https://example.test/x); }]]></style></svg>',
    '<svg><rect style="fill:url&#40;https://example.test/x&#41;"/></svg>', '<svg><rect onload="run()"/></svg>',
    '<svg><rect style="f\\69ll:red"/></svg>', '<svg><rect style="fill:/*hidden*/red"/></svg>',
    '<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///secret">]><svg/>', '<svg>&unknown;</svg>',
    '<svg><rect fill="url(\'&#x68;ttps://example.test/x\')"/></svg>', '<svg><rect fill="url(\'#x&quot;)"/></svg>'
  ]) assert.throws(()=>assertPassiveSvg(source),source);
});

test('preview profile rejects incomplete, duplicate and unbounded XML structures', () => {
  for(const source of ['', 'not XML', '<svg><g></svg>', '<svg/><svg/>', '<svg width="1" width="2"/>',
    '<svg><rect a="unterminated/></svg>', '<svg><!--bad--comment--></svg>', '<svg>&#0;</svg>',
    '<svg>'+ '<g>'.repeat(65)+'</g>'.repeat(65)+'</svg>']) assert.throws(()=>assertPassiveSvg(source),source);
});
