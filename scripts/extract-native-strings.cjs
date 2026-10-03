/* Extract explicit presentation sinks without translating wire IDs or control state. */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const ts = require('typescript');

const root = path.resolve(__dirname, '..');
const sources = ['pages/Index.ets', 'components/EditorPanel.ets', 'platform/Preparation.ets', 'platform/Repository.ets',
  'platform/PackageExporter.ets', 'platform/SystemPicker.ets', 'platform/ArchiveWorker.ets', 'platform/Feedback.ets',
  'domain/engine.ts', 'domain/editor.ts', 'domain/validate.ts', 'domain/jsonSafety.ts', 'domain/media.ts', 'domain/zip.ts', 'domain/geometry.ts'];
const sourceRoot = path.join(root, 'app/entry/src/main/ets');
const resourcePath = path.join(root, 'app/entry/src/main/resources/base/element/string.json');
const fallbackPath = path.join(sourceRoot, 'domain/EnglishStrings.ts');
const check = process.argv.includes('--check');
const skipUi = process.argv.includes('--skip-ui');
const auditOnly = process.argv.includes('--audit');
const resources = JSON.parse(fs.readFileSync(resourcePath, 'utf8')).string;
const strings = new Map(resources.filter(item => item.name.startsWith('tm_')).map(item => [item.name, item.value]));
const enumLabels = ['Touch', 'List', 'Scan', 'Objects', 'Connections', 'Exit exploration', 'Questions', 'Chart facts', 'Speech', 'Publish',
  'forward', 'both', 'unknown', 'adjacency', 'direction', 'sequence', 'comparison', 'value', 'bar', 'line',
  'category', 'linear', 'log', 'draft', 'needs_review', 'reviewed', 'label', 'description', 'overview', 'question'];
const enumExpressions = /(?:\.(?:geometryReview|meaningReview|review)\.status|\.direction|\.kind|this\.(?:audioKind|relationDirection|questionType|chartKind|xScale|yScale))$/;

function keyFor(value) {
  const key = 'tm_' + crypto.createHash('sha256').update(value).digest('hex').slice(0, 12);
  if (strings.has(key) && strings.get(key) !== value) throw new Error('Resource-key collision');
  strings.set(key, value);
  return key;
}
function callFor(value, parameters = []) {
  const key = keyFor(value);
  return `tr('${key}'${parameters.length ? ', [' + parameters.join(', ') + ']' : ''})`;
}
enumLabels.forEach(keyFor);

function transformSource(source, file) {
  const ui = file.startsWith('pages/') || file.startsWith('components/');
  // The equal-length replacement lets the TypeScript parser retain exact ArkTS ranges.
  // ArkUI declarative blocks trigger recovery diagnostics; only explicit expression nodes
  // inside the presentation sinks below are rewritten, with every change recorded.
  const parsed = ts.createSourceFile(file, source.replace(/\bstruct\b/g, 'class '), ts.ScriptTarget.Latest, true);
  const roots = [];
  const text = node => source.slice(node.getStart(parsed), node.end);
  const sinkNames = new Set(['Text', 'Button', 'accessibilityText', 'accessibilityDescription']);
  function visit(node) {
    if (ts.isCallExpression(node)) {
      const name = ts.isIdentifier(node.expression) ? node.expression.text : ts.isPropertyAccessExpression(node.expression) ? node.expression.name.text : '';
      if (sinkNames.has(name) && node.arguments.length) roots.push(node.arguments[0]);
      if (['feedback.announce', 'this.onStatus', 'this.onPlaybackFailure'].includes(text(node.expression)) && node.arguments.length) roots.push(node.arguments[0]);
      if (/^(errors|issues|missing)\.push$/.test(text(node.expression))) roots.push(...node.arguments);
      if (file === 'domain/engine.ts' && text(node.expression) === 'finish' && node.arguments[2]) roots.push(node.arguments[2]);
    }
    if (ts.isNewExpression(node) && text(node.expression) === 'Error' && node.arguments?.length) roots.push(node.arguments[0]);
    if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.EqualsToken && /^this\.(status|busyOperation|guide)$/.test(text(node.left))) roots.push(node.right);
    if (file === 'domain/engine.ts' && ts.isBinaryExpression(node) && [ts.SyntaxKind.EqualsToken, ts.SyntaxKind.PlusEqualsToken].includes(node.operatorToken.kind) && /^(feedback|text)$/.test(text(node.left))) roots.push(node.right);
    if (file === 'domain/engine.ts' && ts.isVariableDeclaration(node) && node.initializer && ['feedback', 'text'].includes(text(node.name))) roots.push(node.initializer);
    if (ts.isPropertyDeclaration(node) && node.initializer && ['status', 'busyOperation', 'sourceName'].includes(text(node.name))) roots.push(node.initializer);
    if (ts.isPropertyAssignment(node) && ['placeholder', 'feedback'].includes(text(node.name))) roots.push(node.initializer);
    if (file === 'domain/validate.ts' && ts.isReturnStatement(node) && node.expression && ts.isArrayLiteralExpression(node.expression)) roots.push(node.expression);
    if (file === 'domain/validate.ts' && ts.isPropertyAssignment(node) && text(node.name) === 'missing' && ts.isArrayLiteralExpression(node.initializer)) roots.push(node.initializer);
    if (file === 'platform/Preparation.ets' && ts.isArrayLiteralExpression(node) && node.elements.length === 2 && ts.isNumericLiteral(node.elements[0]) && ts.isStringLiteral(node.elements[1])) roots.push(node.elements[1]);
    ts.forEachChild(node, visit);
  }
  visit(parsed);

  function value(node, enumValue = true) {
    const original = text(node);
    if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) {
      if (!node.text.trim() || /^[\s\d%.,:;|=×·◉()[\]{}+\-/]*$/.test(node.text)) return original;
      return callFor(node.text);
    }
    if (ts.isTemplateExpression(node)) {
      let pattern = node.head.text;
      const parameters = [];
      node.templateSpans.forEach((span, index) => {
        pattern += `{${index}}` + span.literal.text;
        parameters.push(`String(${value(span.expression)})`);
      });
      return callFor(pattern, parameters);
    }
    if (ts.isConditionalExpression(node)) return `${text(node.condition)} ? ${value(node.whenTrue)} : ${value(node.whenFalse)}`;
    if (ts.isBinaryExpression(node) && [ts.SyntaxKind.BarBarToken, ts.SyntaxKind.QuestionQuestionToken, ts.SyntaxKind.PlusToken].includes(node.operatorToken.kind)) {
      return `${value(node.left, false)} ${text(node.operatorToken)} ${value(node.right)}`;
    }
    if (ts.isParenthesizedExpression(node)) return `(${value(node.expression)})`;
    if (ts.isArrayLiteralExpression(node)) return `[${node.elements.map(item => value(item)).join(', ')}]`;
    if (ts.isElementAccessExpression(node) && ts.isArrayLiteralExpression(node.expression)) return `${value(node.expression)}[${text(node.argumentExpression)}]`;
    if (ui && enumValue && (['mode', 'tab'].includes(original) || enumExpressions.test(original))) return `tr(englishKey(${original}))`;
    return original;
  }

  const candidates = roots.map(node => ({ start: node.getStart(parsed), end: node.end, before: text(node), after: value(node) }))
    .filter(item => item.before !== item.after).sort((a, b) => a.start - b.start || b.end - a.end);
  const edits = [];
  for (const item of candidates) {
    if (edits.some(other => item.start >= other.start && item.end <= other.end)) continue;
    if (edits.some(other => item.start < other.end && item.end > other.start)) throw new Error(`Overlapping presentation edits in ${file}`);
    edits.push(item);
  }
  let output = source;
  for (const edit of edits.slice().reverse()) output = output.slice(0, edit.start) + edit.after + output.slice(edit.end);
  const importPath = file.startsWith('domain/') ? './i18n' : '../domain/i18n';
  output = output.replace("import { tr } from '../platform/I18n';", `import { tr } from '${importPath}';`).replace("import { englishKey } from '../platform/EnglishStrings';", "import { englishKey } from '../domain/EnglishStrings';");
  if (/\btr\(/.test(output) && !output.includes(`import { tr } from '${importPath}';`)) output = `import { tr } from '${importPath}';\n` + output;
  if (ui && output.includes('englishKey(') && !output.includes("import { englishKey } from '../domain/EnglishStrings';")) output = "import { englishKey } from '../domain/EnglishStrings';\n" + output;

  // Select labels are translated while the callback persists its original enum by index.
  output = output.replace(/Select\(\[((?:\{ value: '[^']+' \}(?:, )?)+)\]\)([^\n]+?)\.value\(this\.(\w+)\)\.onSelect\(\(_i: number, value: string\) => \{ this\.\3 = value; \}\)/g,
    (_all, items, style, field) => {
      const values = [...items.matchAll(/value: '([^']+)'/g)].map(match => match[1]);
      const translated = values.map(item => `{ value: ${callFor(item)} }`).join(', ');
      return `Select([${translated}])${style}.value(tr(englishKey(this.${field}))).onSelect((index: number) => { this.${field} = [${values.map(item => `'${item}'`).join(', ')}][index]; })`;
    });
  return { output, changes: edits.map(item => ({ line: source.slice(0, item.start).split('\n').length, original: item.before, replacement: item.after })) };
}

const audit = [];
let changes = 0;
for (const name of sources) {
  if (skipUi && (name.startsWith('pages/') || name.startsWith('components/'))) continue;
  const file = path.join(sourceRoot, name);
  if (!fs.existsSync(file)) continue;
  const original = fs.readFileSync(file, 'utf8');
  const result = transformSource(original, name);
  if (result.output !== original) {
    changes++;
    if (!check && !auditOnly) fs.writeFileSync(file, result.output);
  }
  audit.push({ file: name, changes: result.changes });
}
const entries = [...strings].sort(([a], [b]) => a.localeCompare(b));
const nextResources = JSON.stringify({ string: [...resources.filter(item => !item.name.startsWith('tm_')), ...entries.map(([name, value]) => ({ name, value }))] }, null, 2) + '\n';
const fallback = '// Generated by scripts/extract-native-strings.cjs from base English resources.\n' +
  'export function englishText(key: string): string {\n  switch (key) {\n' +
  entries.map(([key, value]) => `    case ${JSON.stringify(key)}: return ${JSON.stringify(value)};`).join('\n') +
  '\n    default: return key;\n  }\n}\n\nexport function englishKey(value: string): string {\n  switch (value) {\n' +
  entries.map(([key, value]) => `    case ${JSON.stringify(value)}: return ${JSON.stringify(key)};`).join('\n') +
  '\n    default: return value;\n  }\n}\n';
for (const [file, content] of [[resourcePath, nextResources], [fallbackPath, fallback]]) {
  if (!fs.existsSync(file) || fs.readFileSync(file, 'utf8') !== content) { changes++; if (!check && !auditOnly) fs.writeFileSync(file, content); }
}
if (!check || auditOnly) {
  const coverage = [];
  for (const name of sources) {
    const file = path.join(sourceRoot, name);
    if (!fs.existsSync(file)) continue;
    const content = fs.readFileSync(file, 'utf8');
    const ast = ts.createSourceFile(name, content.replace(/\bstruct\b/g, 'class '), ts.ScriptTarget.Latest, true);
    const remaining = [];
    function inspect(node) {
      if ((ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) && /[A-Za-z]/.test(node.text) && /\s/.test(node.text)) {
        let classification = 'review';
        if (/^(CREATE TABLE|SELECT |INSERT |DELETE )/.test(node.text)) classification = 'SQL, not presentation';
        else if (node.text === 'Chart facts') classification = 'Stable section identifier; rendered tab is localized separately';
        else if (node.text === 'Author must') classification = 'Existing source-provenance sentinel, not generated UI copy';
        else if (node.text === 'fmt ') classification = 'PCM WAV binary chunk identifier, not presentation';
        else if (['New chart', 'Series 1'].includes(node.text)) classification = 'Default English-authored material content, separate from UI locale';
        else if (/^(I reviewed geometry|Unreviewed source imported)/.test(node.text)) classification = 'Persisted English material author declaration, separate from UI locale';
        remaining.push({ line: ast.getLineAndCharacterOfPosition(node.getStart()).line + 1, text: node.text, classification });
      }
      ts.forEachChild(node, inspect);
    }
    inspect(ast);
    coverage.push({ file: name, sourceSha256: crypto.createHash('sha256').update(content).digest('hex'),
      resourceCalls: (content.match(/\btr\(/g) || []).length, remainingEnglishLiterals: remaining });
  }
  fs.writeFileSync(path.join(root, 'docs/evidence/localization-extraction.json'), JSON.stringify({
    scope: 'Presentation-only extraction. Conditions, identifiers, persisted enum values and authored material content are preserved. Templates use numbered parameters; dynamic authored values are not translated.',
    languages: ['base English'], resources: entries.length, sourceCoverage: coverage,
    remainingReviewCount: coverage.flatMap(item => item.remainingEnglishLiterals).filter(item => item.classification === 'review').length,
    excludedPendingOwnership: [],
    verification: 'Run node scripts/extract-native-strings.cjs --check for idempotence; --audit refreshes this inventory without modifying source.'
  }, null, 2) + '\n');
}
console.log(JSON.stringify({ resources: entries.length, changedFiles: changes, check }, null, 2));
if (check && changes) process.exitCode = 1;
