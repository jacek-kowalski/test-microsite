"""
Regenerate index.html from the parent microsite, adding the static webapis.js tag.

index.html is committed so this folder stays a self-contained Tizen project you
can copy to a build machine. Run this only when ../tizen_api_test_microsite.html
changes, to pull those edits across.

    python sync_index.py
"""
import os

SOURCE = os.path.join('..', 'tizen_api_test_microsite.html')
TARGET = 'index.html'

# In a packaged Tizen app $WEBAPIS is a virtual path resolved by the Web Runtime.
# A static tag is more reliable than the page's own dynamic <script> injection,
# which the probe skips when window.webapis is already present.
WEBAPIS_TAG = (
    '    <!-- Injected by sync_index.py: Samsung Product API bridge.\n'
    '         Only resolves inside a packaged Tizen app, not in the TV browser. -->\n'
    '    <script type="text/javascript" src="$WEBAPIS/webapis/webapis.js"></script>\n'
)

if not os.path.exists(SOURCE):
    print("Error: {} not found".format(SOURCE))
    raise SystemExit(1)

# newline='' on both ends preserves the source's line endings byte for byte,
# so `diff` against the parent microsite shows only the injected tag.
with open(SOURCE, 'r', encoding='utf-8', newline='') as handle:
    html = handle.read()

if '</head>' not in html:
    print("Error: no </head> in {} - cannot inject the webapis.js tag".format(SOURCE))
    raise SystemExit(1)

if 'webapis/webapis.js' in html.split('</head>')[0]:
    print("Note: source already has a static webapis.js tag; copying unchanged.")
    output = html
else:
    # Match whatever the source uses so the file stays internally consistent.
    eol = '\r\n' if '\r\n' in html else '\n'
    output = html.replace('</head>', WEBAPIS_TAG.replace('\n', eol) + '</head>', 1)

with open(TARGET, 'w', encoding='utf-8', newline='') as handle:
    handle.write(output)

print("Wrote {} ({} bytes) from {}".format(TARGET, len(output), SOURCE))
print("Static webapis.js tag present: {}".format('webapis/webapis.js' in output))
