import nativeSuite from './Native.test';
import packageExporterSuite from './PackageExporter.test';
export default function testsuite(): void { nativeSuite(); packageExporterSuite(); }
