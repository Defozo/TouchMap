# Native locale resources

English is the released and tested language. Native controls, accessibility labels, status messages and validation errors resolve through the platform ResourceManager and the base English `string.json` catalog. Audio and authored material retain their own language and stable content identifiers.

`domain/i18n.ts` formats named resources with numbered `{0}` parameters. `platform/I18n.ets` registers the native resolver during ability creation and configuration changes, caching resolved strings for that configuration. Pure-domain host tests and worker contexts without a registered native manager use the generated English fallback. Missing native resources also use that fallback.

User-authored names, question text, evidence and other dynamic values are inserted literally. Their braces or dollar signs cannot introduce additional substitutions. Persisted enum values remain stable: for example, the direction selector translates its displayed options but stores the original `forward`, `both` or `unknown` value by selection index.

Run `node scripts/extract-native-strings.cjs --check` to check resource extraction and generated fallback parity. `--audit` refreshes the source inventory without rewriting application code. Adding another locale requires translated resource files and separate UI, reader and matching audio verification; the presence of a lookup adapter alone does not establish another tested language.

Host tests cover resource parity, literal interpolation and unchanged lesson identifiers under a different resolver. Native tests resolve the bundled strings through the actual ResourceManager. See the release test report for the artifact on which those native tests were executed.
