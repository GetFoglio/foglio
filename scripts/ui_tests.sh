#!/bin/zsh
# Drives the real app with synthetic keyboard/mouse events and checks cell results.
# Usage: scripts/ui_tests.sh   (after scripts/build.sh --arm64-only)
ROOT=${0:A:h:h}
APP=$ROOT/build/Foglio.app/Contents/MacOS/Foglio
fail=0
run() { # name, expected-lines-regex..., script
  local name=$1 script=$2; shift 2
  local out=$(FOGLIO_PERF=1 FOGLIO_SNAPSHOT=/dev/null FOGLIO_SCRIPT="$script" timeout 40 $APP 2>&1)
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
run "insert row shifts data" "input A2=x;; input B5==A2;; header 2;; key cmd+shift++;; print A3;; print B6" "CELL A3 = x | x" "| =A3"
run "add sheet + undo" "key cmd+shift+n;; sheets;; key cmd+z;; sheets" "SHEETS Foglio1,Foglio2 current=1" "SHEETS Foglio1 current=0"
run "cross-sheet reference" "input A1=5;; key cmd+shift+n;; input A1=1;; click B2;; type =;; tab 0;; click A1;; key return;; print B2" "CELL B2 = 5 | =Foglio1!A1"
run "merged cell editing" "select B2:D3;; merge;; click C3;; type unito;; key return;; print B2;; state" "CELL B2 = unito | unito" "active=B4"
exit $fail
