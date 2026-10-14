#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh release
task_check_dir=$(mktemp -d /tmp/browser-picker-file-probe.XXXXXX)
task_probe_app="$task_check_dir/File Receiver.app"
cleanup() {
    python3 - "$task_probe_app/Contents/MacOS/FileReceiver" <<'PY'
import os, signal, subprocess, sys
for line in subprocess.check_output(['/bin/ps','-axo','pid=,command='],text=True).splitlines():
    parts=line.strip().split(None,1)
    if len(parts)==2 and os.path.realpath(parts[1])==os.path.realpath(sys.argv[1]):
        try: os.kill(int(parts[0]),signal.SIGTERM)
        except ProcessLookupError: pass
PY
    rm -rf "$task_check_dir"
}
trap cleanup EXIT
mkdir -p "$task_probe_app/Contents/MacOS"
cat > "$task_check_dir/main.swift" <<'SWIFT'
import AppKit
@MainActor final class Receiver: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        let path = Bundle.main.object(forInfoDictionaryKey: "ReceiverLog") as! String
        let file = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        let handle = try! FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try! handle.seekToEnd()
        for url in urls { try! handle.write(contentsOf: JSONSerialization.data(withJSONObject: ["url": url.absoluteString]) + Data([10])) }
    }
}
@main @MainActor enum ProbeMain {
    static func main() {
        let app = NSApplication.shared
        let receiver = Receiver()
        app.delegate = receiver
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
SWIFT
swiftc -parse-as-library "$task_check_dir/main.swift" -o "$task_probe_app/Contents/MacOS/FileReceiver"
python3 - "$task_probe_app" "$task_check_dir" <<'PY'
import plistlib,sys,uuid
from pathlib import Path
app,root=map(Path,sys.argv[1:])
with (app/'Contents/Info.plist').open('wb') as file:
    plistlib.dump({'CFBundleIdentifier':'local.browser-picker.file-probe.'+uuid.uuid4().hex,'CFBundleExecutable':'FileReceiver','CFBundlePackageType':'APPL','CFBundleName':'File Receiver','LSMinimumSystemVersion':'14.0','ReceiverLog':str(root/'received.jsonl')},file)
(root/'Existing 日本語 #100%+?.unknown').write_text('Neutral file fixture')
PY
codesign --force --sign - "$task_probe_app"
for task_file in 'Existing 日本語 #100%+?.unknown' 'Missing 日本語 #100%+?.unknown' 'Another missing file.html'; do
    'build/Browser Picker.app/Contents/MacOS/BrowserPicker' \
        --test-settings "$task_check_dir/settings.json" --journal "$task_check_dir/sent.jsonl" \
        --integration-test --integration-browser "$task_probe_app" --integration-file "$task_check_dir/$task_file"
done
python3 - "$task_check_dir" <<'PY'
import json,sys,time
from pathlib import Path
root=Path(sys.argv[1])
sent=[json.loads(line)['url'] for line in (root/'sent.jsonl').read_text().splitlines() if json.loads(line)['event']=='handoff']
for _ in range(30):
    received=[json.loads(line)['url'] for line in (root/'received.jsonl').read_text().splitlines()] if (root/'received.jsonl').exists() else []
    if len(received)>=3: break
    time.sleep(.1)
assert len(sent)==3 and received==sent, (received,sent)
print('File handoffs: cold and warm receivers got all 3 exact addresses, including nonexistent files and an unknown extension.')
PY
