"""Build an explicitly labelled native accessibility dispatch test service."""
import json
import shutil
import subprocess
from pathlib import Path

repository = Path(__file__).resolve().parents[1]
oniro = Path.home() / "touchmap-toolchain/node_modules/.bin/oniro-app"
location = Path.home() / ".cache/touchmap-probes"
location.mkdir(parents=True, exist_ok=True)
project = location / "hover-probe"
if not project.exists():
    subprocess.run([str(oniro), "create", "--name", project.name, "--bundle", "org.touchmap.test.hover", "--location", str(location), "--sdk", "20"], check=True)
main = project / "entry/src/main"
shutil.copyfile(repository / "tests/native-accessibility-probe/Probe.ets", main / "ets/Probe.ets")
shutil.copyfile(repository / "tests/native-accessibility-probe/Index.ets", main / "ets/pages/Index.ets")
profile = json.loads((main / "module.json5").read_text())
profile["module"]["extensionAbilities"] = [{
    "name": "Probe",
    "srcEntry": "./ets/Probe.ets",
    "type": "accessibility",
    "label": "$string:EntryAbility_label",
    "description": "$string:EntryAbility_desc",
    "metadata": [{"name": "ohos.accessibleability", "resource": "$profile:accessibility_config"}],
}]
(main / "module.json5").write_text(json.dumps(profile, indent=2))
(main / "resources/base/profile/accessibility_config.json").write_text(json.dumps({"accessibilityCapabilities": ["retrieve", "gesture", "touchGuide"]}))
strings = json.loads((main / "resources/base/element/string.json").read_text())
for item in strings["string"]:
    if item["name"] == "EntryAbility_label":
        item["value"] = "TouchMap hover test probe"
    if item["name"] == "EntryAbility_desc":
        item["value"] = "Test instrumentation only. No spoken screen reader."
(main / "resources/base/element/string.json").write_text(json.dumps(strings, indent=2))
subprocess.run([str(oniro), "sign", str(project), "--bootstrap"], check=True, stdout=subprocess.DEVNULL)
subprocess.run([str(oniro), "build", str(project)], check=True)
print(project)
