#!/bin/zsh
# Lists UI strings used in Swift sources that have no Italian translation yet.
cd ${0:A:h:h}/app
grep -ohE 'L\("([^"\\]|\\.)*"\)|Menus\.item\("([^"\\]|\\.)*"|item\("([^"\\]|\\.)*"|submenu\("([^"\\]|\\.)*"|button\("[^"]*", "([^"\\]|\\.)*"' Sources/*.swift \
  | sed -E 's/^L\("//; s/^Menus\.item\("//; s/^item\("//; s/^submenu\("//; s/^button\("[^"]*", "//; s/"\)?$//' | sort -u > /tmp/foglio_keys.txt
python3 - <<'PY'
import re
have=set(re.findall(r'^"((?:[^"\\]|\\.)*)" =', open('Resources/it.lproj/Localizable.strings',encoding='utf-8').read(), re.M))
for k in open('/tmp/foglio_keys.txt'):
    k=k.rstrip('\n')
    if k and k not in have: print(k)
PY
