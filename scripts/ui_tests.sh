#!/bin/zsh
# Drives the real app with synthetic keyboard/mouse events and checks cell results.
# Usage: scripts/ui_tests.sh   (after scripts/build.sh --arm64-only)
ROOT=${0:A:h:h}
APP=$ROOT/build/Foglio.app/Contents/MacOS/Foglio
fail=0
run() { # name, script, expected-lines...  (FILE=path opens that workbook instead of a blank one)
  local name=$1 script=$2; shift 2
  local out=$(FOGLIO_PERF=1 FOGLIO_SNAPSHOT=/dev/null FOGLIO_SCRIPT="$script" timeout 40 $APP ${FILE:+"$FILE"} 2>&1)
  local rc=$?
  if [[ $rc -ne 0 ]]; then echo "✗ $name (exit $rc)"; fail=1; return; fi
  for exp in "$@"; do
    if ! print -r -- "$out" | grep -qF -- "$exp"; then echo "✗ $name: missing «$exp»"; print -r -- "$out" | grep -E "CELL|STATE" | sed 's/^/    /'; fail=1; return; fi
  done
  echo "✓ $name"
}
run "typing + Enter" "click B2;; type 10;; key return;; type 20,5;; key return;; print B2;; print B3" "CELL B2 = 10 | 10" "CELL B3 = 20,5 | 20,5"
run "autocomplete + point mode" "click B2;; type 10;; key return;; type 20,5;; key return;; type =SOM;; key tab;; click B2;; shiftclick B3;; type );; key return;; print B4" "CELL B4 = 30,5 | =SOMMA(B2:B3)"
run "arrow point mode" "click D2;; type =;; key up;; key left;; key left;; type *2;; key return;; print D2" "| =B1*2"
run "undo/redo" "click B2;; type 10;; key return;; type =B2*3;; key return;; key cmd+z;; print B3;; key cmd+shift+z;; print B3" "CELL B3 =  |" "CELL B3 = 30 | =B2*3"
run "copy relative refs" "input B2=10;; input B3==B2*3;; click B3;; key cmd+c;; click E5;; key cmd+v;; print E5" "| =E4*3"
run "cut + paste" "input B2=10;; click B2;; key cmd+x;; click C9;; key cmd+v;; print C9;; print B2" "CELL C9 = 10 | 10" "CELL B2 =  |"
run "fill selection" "input B1=5;; select A1:A5;; type =B1*2;; fillsel;; print A3" "| =B3*2"
run "fill down" "input C1=7;; select C1:C4;; key cmd+d;; print C4" "CELL C4 = 7 | 7"
run "fill handle series" "input J1=1;; input J2=2;; drag J1 J2;; filldrag J2 J6;; print J6" "CELL J6 = 6 | 6"
run "escape cancels" "click A1;; type ciao;; key esc;; print A1" "CELL A1 =  |"
run "tab moves right" "click A1;; type a;; key tab;; type b;; key return;; print B1" "CELL B1 = b | b"
run "shift-return moves up" "click A5;; type x;; key shift+return;; state" "active=A4"
run "cmd-return fills selection" "select A1:A3;; type 9;; key cmd+return;; print A3" "CELL A3 = 9 | 9"
run "F4 cycles references" "click B3;; type =B2;; key f4;; key return;; print B3" "| =\$B\$2"
run "find" "input C7=trovami;; click A1;; findtext trovami;; state" "active=C7"
run "filter hides rows" "input A1=K;; input A2=x;; input A3=y;; input A4=x;; select A1;; bold;; autofilter;; exclude A x;; rowhidden 2;; rowhidden 3" "HIDDEN 2 true" "HIDDEN 3 false"
run "header selection" "header C;; state;; header 4;; state" "sel=C:C" "sel=4:4"
run "unchanged commit is not an edit" "input A1=3;; click A1;; key f2;; key return;; key cmd+z;; print A1" "CELL A1 =  |"
run "sort ascending" "input A1=Nome;; input A2=c;; input A3=a;; input A4=b;; select A1;; bold;; key cmd+a;; sortasc;; print A2;; print A4" "CELL A2 = a | a" "CELL A4 = c | c"
run "formula bar editing" "click C3;; barclick;; type =1+1;; key return;; print C3" "CELL C3 = 2 | =1+1"
run "formula bar point mode" "input A1=4;; click C3;; barclick;; type =;; click A1;; type *10;; key return;; print C3" "CELL C3 = 40 | =A1*10"
run "insert row shifts data" "input A2=x;; input B5==A2;; header 2;; key ctrl+i;; print A3;; print B6" "CELL A3 = x | x" "| =A3"
run "add sheet + undo" "key cmd+shift+n;; sheets;; key cmd+z;; sheets" "SHEETS Foglio1,Foglio2 current=1" "SHEETS Foglio1 current=0"
run "cross-sheet reference" "input A1=5;; key cmd+shift+n;; input A1=1;; click B2;; type =;; tab 0;; click A1;; key return;; print B2" "CELL B2 = 5 | =Foglio1!A1"
run "merged cell editing" "select B2:D3;; merge;; click C3;; type unito;; key return;; print B2;; state" "CELL B2 = unito | unito" "active=B4"
run "sheet navigation" "key cmd+shift+n;; key cmd+shift+n;; tab 0;; key opt+right;; sheets;; key opt+left;; key opt+left;; sheets" "current=1" "current=2"
run "format painter" "input A1=x;; select A1;; bold;; painter;; drag C3 D4;; styleof D4" "STYLE D4 bold=true"
run "drag moves cells" "input B2=7;; input D2==B2*2;; select B2;; dragborder B2 C5;; print C5;; print B2;; print D2" "CELL C5 = 7 | 7" "CELL B2 =  |" "| =C5*2"
run "insert cells shifts down" "input B2=a;; input B3=b;; select B2;; shiftcells insert down;; print B3;; print B4" "CELL B3 = a | a" "CELL B4 = b | b"
run "delete cells shifts up" "input B2=a;; input B3=b;; select B2;; shiftcells delete down;; print B2" "CELL B2 = b | b"
run "repeat last action" "select A1;; key cmd+b;; select C3;; key cmd+y;; styleof C3" "STYLE C3 bold=true"
run "autocomplete from column" "input A1=Milano;; input A2=Roma;; click A3;; type Mi;; key return;; print A3" "CELL A3 = Milano | Milano"
run "enter after tab returns" "click B2;; type 1;; key tab;; type 2;; key tab;; type 3;; key return;; state" "active=B3"
run "paste tiles over selection" "input A1=5;; click A1;; key cmd+c;; select C1:C4;; key cmd+v;; print C4" "CELL C4 = 5 | 5"
run "remove duplicates" "input A1=Nome;; input A2=x;; input A3=y;; input A4=x;; select A1;; bold;; select A2;; removedups;; print A3;; print A4" "CELL A3 = y | y" "CELL A4 =  |"
run "show formulas" "input A1=2;; input A2==A1*3;; showformulas;; state" "editing=false"
run "defined names" "input B2=1;; input B3=2;; input B4=3;; select B2:B4;; namebox Vendite;; input D1==SOMMA(Vendite);; print D1;; select F9;; namebox vendite;; state" "CELL D1 = 6 | =SOMMA(Vendite)" "sel=B2:B4"
run "multi-key sort" "input A1=b;; input B1=1;; input A2=a;; input B2=2;; input A3=b;; input B3=3;; input A4=a;; input B4=1;; sortkeys A1:B4 A+ B-;; print B1;; print B3;; print B4" "CELL B1 = 2 | 2" "CELL B3 = 3 | 3" "CELL B4 = 1 | 1"
run "find all" "input A1=uno;; input C5=Uno e due;; input D9=tre;; findall uno" "FOUND 2"
# Charts
CHART_DATA="input A1=Mese;; input B1=Vendite;; input C1=Costi;; input A2=Gen;; input B2=10;; input C2=7;; input A3=Feb;; input B3=14;; input C3=9"
run "chart insert" "$CHART_DATA;; chart column A1:B3;; chart list" "CHARTS 1 selected=0" "CHART 0 kind=column title=Vendite legend=none range=A1:B3 from=E1"
run "chart delete key + undo" "$CHART_DATA;; chart line A1:C3;; chart click 0;; key delete;; chart list;; key cmd+z;; chart list" "CHARTS 0" "CHARTS 1"
run "chart move + properties" "$CHART_DATA;; chart column A1:C3;; chart drag 0 200 0;; chart props 0 title=Totale_mese range=A1:B3;; chart list" "title=Totale mese" "range=A1:B3" "from=G1"
run "chart save + reopen" "$CHART_DATA;; chart pie A1:B3;; chart line A1:C3;; chart roundtrip /tmp/foglio-ui-chart.xlsx" "REOPENED CHARTS 2 kinds=pie,line titles=Vendite,"
# Pictures
PIC_MAKE="pic make /tmp/foglio-ui-logo.png 300 200;; pic make /tmp/foglio-ui-photo.jpg 2400 1600 jpeg"
run "picture insert from file" "$PIC_MAKE;; pic insert /tmp/foglio-ui-logo.png B2;; pic list" "PICTURES 1 selected=0" "PICTURE 0 from=B2" "size=300x200 crop=0,0,0,0 incell=false edit=one_cell format=png"
run "picture move + resize + undo" "$PIC_MAKE;; pic insert /tmp/foglio-ui-logo.png B2;; pic click 0;; pic drag 0 90 45;; pic list;; pic resize 0 -150 0;; pic list;; key cmd+z;; pic list" "PICTURE 0 from=C4" "size=150x100" "size=300x200"
run "picture crop" "$PIC_MAKE;; pic insert /tmp/foglio-ui-logo.png B2;; pic click 0;; pic crop 0 right -60;; pic list" "size=240x200 crop=0,0,20000,0" "cropping=false"
run "picture in cell follows row height" "$PIC_MAKE;; pic insert /tmp/foglio-ui-logo.png C3;; pic incell 0;; pic list;; pic rowheight 3 100;; pic list;; pic overcells 0;; pic list" "incell=true edit=two_cell" "rect=219,61,25,17" "rect=193,74,78,52" "incell=false edit=one_cell"
run "picture compress" "$PIC_MAKE;; pic insert /tmp/foglio-ui-photo.jpg B2;; pic click 0;; pic crop 0 right -100;; pic compress all 96 crop;; pic list;; key cmd+z;; pic list" "smaller=true" "crop=0,0,0,0" "px=2400x1600"
run "picture save + reopen" "$PIC_MAKE;; $CHART_DATA;; chart column A1:B3;; pic insert /tmp/foglio-ui-logo.png B6;; pic insert /tmp/foglio-ui-photo.jpg F12;; pic click 1;; pic crop 1 bottom -40;; pic incell 0;; pic roundtrip /tmp/foglio-ui-pictures.xlsx" "REOPENED PICTURES 2 charts=1 incell=1 cropped=1 formats=png,jpeg"
run "paste image from another app" "$PIC_MAKE;; pic pbimage /tmp/foglio-ui-logo.png;; click D4;; key cmd+v;; pic list" "PICTURES 1 selected=0" "from=D4"
run "picture copy, paste, delete + undo" "$PIC_MAKE;; pic insert /tmp/foglio-ui-logo.png B2;; pic click 0;; key cmd+c;; click H3;; key cmd+v;; pic list;; key delete;; pic list;; key cmd+z;; pic list" "PICTURES 2 selected=1" "PICTURE 1 from=H3" "PICTURES 1 selected=none" "PICTURES 2"
run "picture stacking with charts" "$PIC_MAKE;; $CHART_DATA;; pic insert /tmp/foglio-ui-logo.png E2;; chart column A1:B3;; pic list;; pic front 0;; pic list" "ORDER p0,c0" "ORDER c0,p0"
python3 -I "$ROOT/scripts/make_test_metafile.py" /tmp/foglio-ui-test.emf /tmp/foglio-ui-test.wmf
run "EMF/WMF pictures: insert, draw, save + reopen" "pic insert /tmp/foglio-ui-test.emf B2;; pic insert /tmp/foglio-ui-test.wmf J2;; pic list;; pic render /tmp/foglio-ui-test.emf /tmp/foglio-ui-test-emf.png;; pic roundtrip /tmp/foglio-ui-metafiles.xlsx" "PICTURES 2" "format=emf" "format=wmf" "METAFILE 299x224" "ok=true" "REOPENED PICTURES 2 charts=0 incell=0 cropped=0 formats=emf,wmf"
run "comments" "comment B2 Nota di prova;; key cmd+shift+n;; tab 0;; state" "editing=false"
run "validation list" "validlist A1:A5 Sì;No;Forse;; select A2;; listitems;; checkvalid A3 Boh;; checkvalid A3 no" "VALID ok" "ITEMS Sì,No,Forse" "CHECK 1" "CHECK 0"
run "summarize" "input A1=Cliente;; input B1=Importo;; input A2=Rossi;; input B2=10;; input A3=Bianchi;; input B3=5;; input A4=Rossi;; input B4=7;; select A1;; summarize A1:B4 A B 0;; sheets;; print B3" "current=1" "CELL B3 = 17"
# Review fixes
run "summarize right of the data" "input A1=x;; input A2=1;; select D1:E5;; dialog summarize;; state" "editing=false"
run "validation alert blocks sheet switch" "key cmd+shift+n;; tab 0;; validlist A1:A5 Sì;No;; click A1;; type Boh;; key return;; tab 1;; sheets" "SHEETS Foglio1,Foglio2 current=0"
run "validation warning + fill selection" "validwarn A1:A3 Sì;No;; select A1:A3;; type Boh;; key cmd+return;; alertbutton 1;; print A3" "CELL A3 = Boh | Boh"
run "validation alert cancels commands" "validlist A1:A5 Sì;No;; input A2=x;; click A1;; type Boh;; key return;; insertrows;; alertbutton 1;; print A2;; state" "CELL A2 = x | x" "editing=true"
run "validation list picks the value" "input J1=1234,5;; input J2==1/3;; validlist A1 =\$J\$1:\$J\$2;; select A1;; pick 1;; print A1" "| 0,333333333333333"
run "move keeps the clipboard" "input B1=3;; input A1==B1*2;; click A1;; key cmd+c;; input C3=x;; select C3;; dragborder C3 D6;; select C9;; shiftcells insert down;; click E1;; key cmd+v;; print E1;; print D6" "| =F1*2" "CELL D6 = x | x"
run "delete cells is one undo step" "input B2=a;; input B3=b;; select B2;; bold;; select B2;; shiftcells delete down;; key cmd+z;; print B2;; print B3;; styleof B2" "CELL B2 = a | a" "CELL B3 = b | b" "STYLE B2 bold=true"
run "tiled paste is one undo step" "input A1=5;; click A1;; key cmd+c;; select C1:C4;; key cmd+v;; key cmd+z;; print C1;; print C4" "CELL C1 =  |" "CELL C4 =  |"
run "sort keeps links" "input A1=b;; input A2=a;; link A1 https://b.example;; sortkeys A1:A2 A+;; linkof A2;; linkof A1" "LINK A2 https://b.example" "LINK A1 -"
run "tab run ends on arrows" "click B2;; type 1;; key tab;; key down;; type 2;; key return;; state" "active=C4"
run "internal link with quoted sheet" "key cmd+shift+n;; tab 0;; input A1=x;; followlink #'Foglio2'!C5;; sheets;; state" "current=1" "active=C5"
# Window resize: the newly exposed cells, headers and chart/picture panes are drawn right away (not after the next scroll)
run "growing the window draws the new cells" "$CHART_DATA;; chart column A1:B3;; setframe 1200 500;; visible;; setframe 1700 1100;; visible;; freeze B3;; setframe 1300 600;; setframe 1650 1050;; visible" \
  "RESIZE 1 drawn=current headers=current scrollers=current panes=current" "RESIZE 2 drawn=current headers=current scrollers=current panes=current grew=rows,cols" \
  "RESIZE 3 drawn=current headers=current scrollers=current panes=current"
run "growing an empty window 1200x800 to 1600x1100" "setframe 1200 800;; visible;; setframe 1600 1100;; visible" \
  "RESIZE 1 drawn=current headers=current scrollers=current panes=current" "RESIZE 2 drawn=current headers=current scrollers=current panes=current grew=rows,cols"
# A price list laid out like the ones Excel users send around (core/tests/fixtures/make_price_list_fixture.py):
# header frozen as "frozenSplit", product photos in a group shape, merged rows with borders on every cell
FILE=$ROOT/core/tests/fixtures/price_list_layout.xlsx run "price list: frozen header stays clickable after scrolling" \
  "scroll 0 -300;; click D20;; state;; click A1;; state;; shiftclick F25;; state;; pic list" \
  "active=C20 sel=C20:E20" "active=A1 sel=A1" "active=A1 sel=A1:F25" "PICTURES 3" "PICTURE 2 from=B1 to=B1" "incell=false"
# Drag selection follows the pointer both ways (the range is always anchor..cell under the pointer, never accumulated)
run "drag selection shrinks back" "select C4:E4;; merge;; freeze A3;; mousedown B5;; mousedrag D12;; state;; mousedrag B6;; state;; mousedrag A5;; state;; mousedrag E5;; state;; mouseup;; mousedown B3;; mousedrag D4;; state;; mousedrag B3;; mouseup;; state" \
  "sel=B5:D12" "sel=B5:B6" "sel=A5:B5" "sel=B5:E5" "sel=B3:E4" "active=B3 sel=B3 "
run "drag selection at 150% after autoscroll" "freeze A3;; zoom 1.5;; mousedown B5;; mousedrag B9;; mousedrag below;; mousedrag below;; mousedrag below;; mousedrag B2;; state;; mousedrag C1;; mouseup;; state" \
  "sel=B2:B5" "active=B5 sel=B1:C5"
FILE=$ROOT/core/tests/fixtures/price_list_layout.xlsx run "drag selection over merges and the frozen header" \
  "scroll 0 -200;; mousedown B20;; mousedrag D25;; state;; mousedrag B14;; state;; mousedrag A1;; state;; mousedrag B21;; mouseup;; state" \
  "sel=B20:E25" "sel=B14:B20" "sel=A1:E20" "active=B20 sel=B20:B21"
run "zoom from the menu updates the status bar" "key cmd+opt+-;; zoomui;; key cmd+opt+-;; zoomui" "ZOOMUI 80% slider=80 grid=80" "ZOOMUI 65% slider=65 grid=65"
if [[ -f ${FOGLIO_CORPUS:-/tmp/poi-test/files}/123233_charts.xlsx ]]; then
  out=$(FOGLIO_PERF=1 FOGLIO_SNAPSHOT=/dev/null FOGLIO_SCRIPT="panes" timeout 40 $APP ${FOGLIO_CORPUS:-/tmp/poi-test/files}/123233_charts.xlsx 2>&1 | grep -c CHARTVIEW)
  [[ $out -eq 4 ]] && echo "✓ charts of the first sheet load on open" || { echo "✗ charts on open (got $out)"; fail=1; }
fi
if [[ -f ${FOGLIO_CORPUS:-/tmp/poi-test/files}/WithDrawing.xlsx ]]; then
  out=$(FOGLIO_PERF=1 FOGLIO_SNAPSHOT=/dev/null FOGLIO_SCRIPT="pic panes" timeout 40 $APP ${FOGLIO_CORPUS:-/tmp/poi-test/files}/WithDrawing.xlsx 2>&1 | grep -c PICTUREVIEW)
  [[ $out -eq 5 ]] && echo "✓ pictures of an Excel file load on open" || { echo "✗ pictures on open (got $out)"; fail=1; }
fi
exit $fail
