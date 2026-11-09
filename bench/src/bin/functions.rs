//! Function coverage audit for IronCalc as used by Foglio.
//!
//! Each case evaluates one formula in a fresh model (fixture data below) and
//! compares the result with the value Excel returns.
//!
//! Run: `cargo run --release --bin functions` (add `-- --md` to print the
//! markdown tables used in docs/FUNCTIONS.md, `-- --locale` for the
//! language/locale probe).

use ironcalc::base::cell::CellValue;
use ironcalc::base::Model;

#[derive(Clone, Copy)]
enum Exp {
    /// Number, compared with a relative/absolute tolerance of 1e-9
    N(f64),
    /// Number with explicit absolute tolerance
    T(f64, f64),
    /// Text
    S(&'static str),
    /// Boolean
    B(bool),
    /// Error value, e.g. "#N/A"
    E(&'static str),
    /// Anything that is not an error (used where the exact shape is uncertain)
    Ok,
}

use Exp::*;

type Case = (&'static str, &'static str, Exp);

// Fixture (Sheet1):
//   A1:A6  apple | banana | cherry | apple pie | Banana | date
//   B1:B6  10 | 20 | (empty) | '5 (text) | TRUE | -3
//   C1:C6  1 2 3 4 5 6
//   D1     45306 (= 2024-01-15, used as a holiday)
//   E1:E5  10 20 30 40 50          F1:F5 ten twenty thirty forty fifty
//   G1 =1/0   G2 =NA()   G3 5
//   H1 =""    (H2 empty)
//   L1:N5  Tree/Height/Profit ; Apple 18 105 ; Pear 12 96 ; Cherry 13 105 ; Apple 14 75
//   P1:P2  Tree / Apple        Q1:Q2 Height / >12
// The formula under test goes in J10 (row 10, column 10).
fn fixture(m: &mut Model) {
    let cells: &[(&str, &str)] = &[
        ("A1", "apple"),
        ("A2", "banana"),
        ("A3", "cherry"),
        ("A4", "apple pie"),
        ("A5", "Banana"),
        ("A6", "date"),
        ("B1", "10"),
        ("B2", "20"),
        ("B4", "'5"),
        ("B5", "TRUE"),
        ("B6", "-3"),
        ("C1", "1"),
        ("C2", "2"),
        ("C3", "3"),
        ("C4", "4"),
        ("C5", "5"),
        ("C6", "6"),
        ("D1", "45306"),
        ("E1", "10"),
        ("E2", "20"),
        ("E3", "30"),
        ("E4", "40"),
        ("E5", "50"),
        ("F1", "ten"),
        ("F2", "twenty"),
        ("F3", "thirty"),
        ("F4", "forty"),
        ("F5", "fifty"),
        ("G1", "=1/0"),
        ("G2", "=NA()"),
        ("G3", "5"),
        ("H1", "=\"\""),
        ("L1", "Tree"),
        ("M1", "Height"),
        ("N1", "Profit"),
        ("L2", "Apple"),
        ("M2", "18"),
        ("N2", "105"),
        ("L3", "Pear"),
        ("M3", "12"),
        ("N3", "96"),
        ("L4", "Cherry"),
        ("M4", "13"),
        ("N4", "105"),
        ("L5", "Apple"),
        ("M5", "14"),
        ("N5", "75"),
        ("P1", "Tree"),
        ("P2", "Apple"),
        ("Q1", "Height"),
        ("Q2", "'>12"),
    ];
    for (r, v) in cells {
        let (row, col) = a1(r);
        m.set_user_input(0, row, col, v.to_string()).unwrap();
    }
}

fn a1(s: &str) -> (i32, i32) {
    let letters: String = s.chars().take_while(|c| c.is_ascii_alphabetic()).collect();
    let digits = &s[letters.len()..];
    let mut col = 0;
    for c in letters.chars() {
        col = col * 26 + (c as i32 - 'A' as i32 + 1);
    }
    (digits.parse().unwrap(), col)
}

/// Functions in (approximate) order of real-world usage frequency.
const FUNCTIONS: &[&str] = &[
    "SUM", "IF", "VLOOKUP", "COUNTIF", "SUMIF", "AVERAGE", "IFERROR", "INDEX", "MATCH", "ROUND",
    "COUNT", "COUNTA", "MAX", "MIN", "SUMIFS", "COUNTIFS", "AND", "OR", "TODAY", "TEXT", "LEFT",
    "RIGHT", "MID", "LEN", "CONCATENATE", "TRIM", "XLOOKUP", "DATE", "YEAR", "MONTH", "DAY",
    "SUMPRODUCT", "ROUNDUP", "ROUNDDOWN", "INT", "ABS", "NOW", "VALUE", "FIND", "SEARCH",
    "SUBSTITUTE", "UPPER", "LOWER", "PROPER", "AVERAGEIF", "AVERAGEIFS", "HLOOKUP", "COUNTBLANK",
    "SUBTOTAL", "IFS", "IFNA", "NOT", "MOD", "CONCAT", "TEXTJOIN", "ISBLANK", "ISNUMBER",
    "ISERROR", "ISTEXT", "EOMONTH", "EDATE", "NETWORKDAYS", "WORKDAY", "WEEKDAY", "DATEDIF",
    "FILTER", "UNIQUE", "SORT", "MAXIFS", "MINIFS", "XMATCH", "CHOOSE", "OFFSET", "INDIRECT",
    "REPLACE", "REPT", "EXACT", "MEDIAN", "LARGE", "SMALL", "RANK", "RANK.EQ", "STDEV",
    "STDEV.S", "STDEV.P", "PMT", "NPV", "IRR", "FV", "PV", "LET", "SEQUENCE", "SORTBY",
    "TRANSPOSE", "SWITCH", "XOR", "TIME", "HOUR", "MINUTE", "SECOND", "WEEKNUM", "ISOWEEKNUM",
    "DATEVALUE", "TIMEVALUE", "DAYS", "YEARFRAC", "NETWORKDAYS.INTL", "WORKDAY.INTL", "TEXTBEFORE",
    "TEXTAFTER", "TEXTSPLIT", "CHAR", "CODE", "CLEAN", "NUMBERVALUE", "FIXED", "DOLLAR", "ISERR",
    "ISNA", "ISLOGICAL", "ISEVEN", "ISODD", "N", "NA", "TYPE", "ERROR.TYPE", "HSTACK", "VSTACK",
    "TAKE", "DROP", "CHOOSECOLS", "CHOOSEROWS", "LAMBDA", "MAP", "BYROW", "BYCOL", "REDUCE",
    "MODE", "MODE.SNGL", "VAR", "VAR.S", "VAR.P", "PERCENTILE", "PERCENTILE.INC", "QUARTILE",
    "QUARTILE.INC", "CORREL", "AGGREGATE", "CEILING", "CEILING.MATH", "FLOOR", "FLOOR.MATH",
    "MROUND", "POWER", "SQRT", "EXP", "LN", "LOG", "LOG10", "PI", "RAND", "RANDBETWEEN",
    "PRODUCT", "SUMSQ", "SIN", "COS", "TAN", "TRUNC", "SIGN", "GCD", "LCM", "FACT", "COMBIN",
    "LOOKUP", "ROW", "ROWS", "COLUMN", "COLUMNS", "ADDRESS", "HYPERLINK", "XNPV", "XIRR", "RATE",
    "NPER", "IPMT", "PPMT", "DSUM", "DAVERAGE", "DCOUNT", "FORECAST", "TREND", "SLOPE",
    "INTERCEPT", "GROUPBY", "PIVOTBY",
];

const CASES: &[Case] = &[
    // ---------------- aggregation ----------------
    ("SUM", "=SUM(B1:B6)", N(27.0)),
    ("SUM", "=SUM(\"5\",TRUE,1)", N(7.0)),
    ("SUM", "=SUM(G1:G3)", E("#DIV/0!")),
    ("SUM", "=SUM(C1:C6,10)", N(31.0)),
    ("AVERAGE", "=AVERAGE(B1:B6)", N(9.0)),
    ("AVERAGE", "=AVERAGE(C1:C6)", N(3.5)),
    ("AVERAGE", "=AVERAGE(B3)", E("#DIV/0!")),
    ("MIN", "=MIN(B1:B6)", N(-3.0)),
    ("MIN", "=MIN(\"2\",5)", N(2.0)),
    ("MIN", "=MIN(B3)", N(0.0)),
    ("MAX", "=MAX(B1:B6)", N(20.0)),
    ("MAX", "=MAX(TRUE,0)", N(1.0)),
    ("MAX", "=MAX(B3)", N(0.0)),
    ("COUNT", "=COUNT(B1:B6)", N(3.0)),
    ("COUNT", "=COUNT(1,\"2\",\"a\",TRUE)", N(3.0)),
    ("COUNT", "=COUNT(G1:G3)", N(1.0)),
    ("COUNTA", "=COUNTA(B1:B6)", N(5.0)),
    ("COUNTA", "=COUNTA(H1:H2)", N(1.0)),
    ("COUNTA", "=COUNTA(G1:G3)", N(3.0)),
    ("COUNTBLANK", "=COUNTBLANK(B1:B6)", N(1.0)),
    ("COUNTBLANK", "=COUNTBLANK(H1:H2)", N(2.0)),
    ("SUBTOTAL", "=SUBTOTAL(9,C1:C6)", N(21.0)),
    ("SUBTOTAL", "=SUBTOTAL(1,C1:C6)", N(3.5)),
    ("SUBTOTAL", "=SUBTOTAL(109,C1:C6)", N(21.0)),
    ("SUBTOTAL", "=SUBTOTAL(3,B1:B6)", N(5.0)),
    ("SUMPRODUCT", "=SUMPRODUCT(C1:C3,E1:E3)", N(140.0)),
    ("SUMPRODUCT", "=SUMPRODUCT((A1:A6=\"apple\")*C1:C6)", N(1.0)),
    ("SUMPRODUCT", "=SUMPRODUCT(B1:B6)", N(27.0)),
    ("SUMPRODUCT", "=SUMPRODUCT(--(C1:C6>3))", N(3.0)),
    ("SUMIF", "=SUMIF(A1:A6,\"apple\",C1:C6)", N(1.0)),
    ("SUMIF", "=SUMIF(A1:A6,\"apple*\",C1:C6)", N(5.0)),
    ("SUMIF", "=SUMIF(A1:A6,\"BANANA\",C1:C6)", N(7.0)),
    ("SUMIF", "=SUMIF(C1:C6,\">3\")", N(15.0)),
    ("SUMIFS", "=SUMIFS(C1:C6,A1:A6,\"*an*\",C1:C6,\">2\")", N(5.0)),
    ("SUMIFS", "=SUMIFS(C1:C6,A1:A6,\"<>apple\")", N(20.0)),
    ("COUNTIF", "=COUNTIF(A1:A6,\"?a*\")", N(3.0)),
    ("COUNTIF", "=COUNTIF(A1:A6,\"<>apple\")", N(5.0)),
    ("COUNTIF", "=COUNTIF(B1:B6,\"\")", N(1.0)),
    ("COUNTIF", "=COUNTIF(C1:C6,\">=3\")", N(4.0)),
    ("COUNTIFS", "=COUNTIFS(A1:A6,\"*a*\",C1:C6,\"<5\")", N(3.0)),
    ("COUNTIFS", "=COUNTIFS(C1:C6,\">1\",C1:C6,\"<=4\")", N(3.0)),
    ("AVERAGEIF", "=AVERAGEIF(A1:A6,\"apple*\",C1:C6)", N(2.5)),
    ("AVERAGEIF", "=AVERAGEIF(A1:A6,\"zzz\",C1:C6)", E("#DIV/0!")),
    ("AVERAGEIFS", "=AVERAGEIFS(C1:C6,C1:C6,\">1\",C1:C6,\"<6\")", N(3.5)),
    ("MAXIFS", "=MAXIFS(C1:C6,A1:A6,\"*an*\")", N(5.0)),
    ("MAXIFS", "=MAXIFS(C1:C6,A1:A6,\"zzz\")", N(0.0)),
    ("MINIFS", "=MINIFS(C1:C6,A1:A6,\"*an*\")", N(2.0)),
    // ---------------- rounding / math ----------------
    ("ROUND", "=ROUND(2.5,0)", N(3.0)),
    ("ROUND", "=ROUND(-2.5,0)", N(-3.0)),
    ("ROUND", "=ROUND(1234.567,-2)", N(1200.0)),
    ("ROUND", "=ROUND(2.675,2)", N(2.68)),
    ("ROUNDUP", "=ROUNDUP(-2.1,0)", N(-3.0)),
    ("ROUNDUP", "=ROUNDUP(3.14159,3)", N(3.142)),
    ("ROUNDDOWN", "=ROUNDDOWN(-2.9,0)", N(-2.0)),
    ("ROUNDDOWN", "=ROUNDDOWN(3.14159,2)", N(3.14)),
    ("INT", "=INT(-2.5)", N(-3.0)),
    ("INT", "=INT(2.9)", N(2.0)),
    ("ABS", "=ABS(-3)", N(3.0)),
    ("ABS", "=ABS(\"-2\")", N(2.0)),
    ("MOD", "=MOD(-3,2)", N(1.0)),
    ("MOD", "=MOD(3,-2)", N(-1.0)),
    ("MOD", "=MOD(5,0)", E("#DIV/0!")),
    ("MOD", "=MOD(5.5,2)", N(1.5)),
    ("CEILING", "=CEILING(2.5,1)", N(3.0)),
    ("CEILING", "=CEILING(-2.5,-1)", N(-3.0)),
    ("CEILING", "=CEILING(-2.5,2)", N(-2.0)),
    ("CEILING", "=CEILING(2.5,-1)", E("#NUM!")),
    ("CEILING", "=CEILING(4.42,0.05)", N(4.45)),
    ("CEILING.MATH", "=CEILING.MATH(-5.5)", N(-5.0)),
    ("CEILING.MATH", "=CEILING.MATH(-5.5,2,-1)", N(-6.0)),
    ("CEILING.MATH", "=CEILING.MATH(24.3,5)", N(25.0)),
    ("FLOOR", "=FLOOR(2.5,1)", N(2.0)),
    ("FLOOR", "=FLOOR(-2.5,-2)", N(-2.0)),
    ("FLOOR", "=FLOOR(-2.5,2)", N(-4.0)),
    ("FLOOR", "=FLOOR(2.5,-2)", E("#NUM!")),
    ("FLOOR.MATH", "=FLOOR.MATH(-5.5)", N(-6.0)),
    ("FLOOR.MATH", "=FLOOR.MATH(-5.5,2,-1)", N(-4.0)),
    ("FLOOR.MATH", "=FLOOR.MATH(24.3,5)", N(20.0)),
    ("MROUND", "=MROUND(10,3)", N(9.0)),
    ("MROUND", "=MROUND(-10,-3)", N(-9.0)),
    ("MROUND", "=MROUND(5,-2)", E("#NUM!")),
    ("MROUND", "=MROUND(1.3,0.2)", N(1.4)),
    ("POWER", "=POWER(2,10)", N(1024.0)),
    // Excel computes odd roots of negative numbers: IronCalc's own Excel-made
    // test workbook (MATH_AND_TRIGONOMETRY/POWER.xlsx) caches -1.9999999999999998
    // for POWER(-8,1/3). (An earlier version of this audit expected #NUM!.)
    ("POWER", "=POWER(-8,1/3)", N(-2.0)),
    ("POWER", "=POWER(-8,1/2)", E("#NUM!")),
    ("POWER", "=POWER(0,0)", E("#NUM!")),
    ("SQRT", "=SQRT(16)", N(4.0)),
    ("SQRT", "=SQRT(-1)", E("#NUM!")),
    ("EXP", "=EXP(1)", N(std::f64::consts::E)),
    ("LN", "=LN(EXP(2))", N(2.0)),
    ("LN", "=LN(0)", E("#NUM!")),
    ("LOG", "=LOG(100)", N(2.0)),
    ("LOG", "=LOG(8,2)", N(3.0)),
    ("LOG", "=LOG(-1)", E("#NUM!")),
    ("LOG10", "=LOG10(1000)", N(3.0)),
    ("PI", "=PI()", N(std::f64::consts::PI)),
    ("RAND", "=AND(RAND()>=0,RAND()<1)", B(true)),
    ("RANDBETWEEN", "=RANDBETWEEN(5,5)", N(5.0)),
    ("RANDBETWEEN", "=AND(RANDBETWEEN(1,3)>=1,RANDBETWEEN(1,3)<=3)", B(true)),
    ("PRODUCT", "=PRODUCT(C1:C4)", N(24.0)),
    ("PRODUCT", "=PRODUCT(B1:B6)", N(-600.0)),
    ("SUMSQ", "=SUMSQ(1,2,3)", N(14.0)),
    ("SUMSQ", "=SUMSQ(C1:C3)", N(14.0)),
    ("SIN", "=SIN(PI()/2)", N(1.0)),
    ("COS", "=COS(0)", N(1.0)),
    ("TAN", "=TAN(PI()/4)", T(1.0, 1e-12)),
    ("TRUNC", "=TRUNC(-2.7)", N(-2.0)),
    ("TRUNC", "=TRUNC(3.14159,2)", N(3.14)),
    ("TRUNC", "=TRUNC(1234,-2)", N(1200.0)),
    ("SIGN", "=SIGN(-5)", N(-1.0)),
    ("SIGN", "=SIGN(0)", N(0.0)),
    ("GCD", "=GCD(12,18)", N(6.0)),
    ("GCD", "=GCD(0,5)", N(5.0)),
    ("GCD", "=GCD(-1,2)", E("#NUM!")),
    ("LCM", "=LCM(4,6)", N(12.0)),
    ("LCM", "=LCM(3,0)", N(0.0)),
    ("FACT", "=FACT(5)", N(120.0)),
    ("FACT", "=FACT(0)", N(1.0)),
    ("FACT", "=FACT(5.9)", N(120.0)),
    ("FACT", "=FACT(-1)", E("#NUM!")),
    ("COMBIN", "=COMBIN(5,2)", N(10.0)),
    ("COMBIN", "=COMBIN(2,5)", E("#NUM!")),
    // ---------------- logical ----------------
    ("IF", "=IF(1>2,\"a\")", B(false)),
    ("IF", "=IF(TRUE,1,2)", N(1.0)),
    ("IF", "=IF(\"a\",1,2)", E("#VALUE!")),
    ("IF", "=IF(B3,1,2)", N(2.0)),
    ("IFS", "=IFS(1>2,\"a\",TRUE,\"b\")", S("b")),
    ("IFS", "=IFS(FALSE,1)", E("#N/A")),
    ("IFERROR", "=IFERROR(1/0,\"x\")", S("x")),
    ("IFERROR", "=IFERROR(5,\"x\")", N(5.0)),
    ("IFERROR", "=IFERROR(G2,0)", N(0.0)),
    ("IFNA", "=IFNA(NA(),\"x\")", S("x")),
    ("IFNA", "=IFNA(1/0,\"x\")", E("#DIV/0!")),
    ("AND", "=AND(TRUE,FALSE)", B(false)),
    ("AND", "=AND(B1:B6)", B(true)),
    ("AND", "=AND(TRUE,\"a\")", E("#VALUE!")),
    ("OR", "=OR(FALSE,0)", B(false)),
    ("OR", "=OR(1,0)", B(true)),
    ("NOT", "=NOT(0)", B(true)),
    ("NOT", "=NOT(\"a\")", E("#VALUE!")),
    ("XOR", "=XOR(TRUE,TRUE,TRUE)", B(true)),
    ("XOR", "=XOR(TRUE,TRUE)", B(false)),
    ("SWITCH", "=SWITCH(2,1,\"a\",2,\"b\",\"c\")", S("b")),
    ("SWITCH", "=SWITCH(9,1,\"a\",\"def\")", S("def")),
    ("SWITCH", "=SWITCH(9,1,\"a\")", E("#N/A")),
    // ---------------- lookup ----------------
    ("VLOOKUP", "=VLOOKUP(\"banana\",A1:C6,3,FALSE)", N(2.0)),
    ("VLOOKUP", "=VLOOKUP(\"BANANA\",A1:C6,3,FALSE)", N(2.0)),
    ("VLOOKUP", "=VLOOKUP(35,E1:F5,2,TRUE)", S("thirty")),
    ("VLOOKUP", "=VLOOKUP(35,E1:F5,2)", S("thirty")),
    ("VLOOKUP", "=VLOOKUP(5,E1:F5,2,TRUE)", E("#N/A")),
    ("VLOOKUP", "=VLOOKUP(\"app*\",A1:C6,3,FALSE)", N(1.0)),
    ("VLOOKUP", "=VLOOKUP(\"apple\",A1:C6,4,FALSE)", E("#REF!")),
    ("VLOOKUP", "=VLOOKUP(\"zzz\",A1:C6,2,FALSE)", E("#N/A")),
    ("HLOOKUP", "=HLOOKUP(2,{1,2,3;\"a\",\"b\",\"c\"},2,FALSE)", S("b")),
    ("HLOOKUP", "=HLOOKUP(2.5,{1,2,3;\"a\",\"b\",\"c\"},2,TRUE)", S("b")),
    ("HLOOKUP", "=HLOOKUP(0,{1,2,3;\"a\",\"b\",\"c\"},2,TRUE)", E("#N/A")),
    ("XLOOKUP", "=XLOOKUP(\"cherry\",A1:A6,C1:C6)", N(3.0)),
    ("XLOOKUP", "=XLOOKUP(\"zzz\",A1:A6,C1:C6,\"none\")", S("none")),
    ("XLOOKUP", "=XLOOKUP(35,E1:E5,F1:F5,,-1)", S("thirty")),
    ("XLOOKUP", "=XLOOKUP(35,E1:E5,F1:F5,,1)", S("forty")),
    ("XLOOKUP", "=XLOOKUP(\"b*\",A1:A6,C1:C6,,2)", N(2.0)),
    ("XLOOKUP", "=XLOOKUP(\"apple*\",A1:A6,C1:C6,,2,-1)", N(4.0)),
    ("XLOOKUP", "=XLOOKUP(\"zzz\",A1:A6,C1:C6)", E("#N/A")),
    ("INDEX", "=INDEX(C1:C6,3)", N(3.0)),
    ("INDEX", "=INDEX(A1:C6,2,3)", N(2.0)),
    ("INDEX", "=INDEX(A1:C6,2,1)", S("banana")),
    ("INDEX", "=INDEX(C1:C6,7)", E("#REF!")),
    ("INDEX", "=SUM(INDEX(C1:E6,0,1))", N(21.0)),
    ("MATCH", "=MATCH(\"cherry\",A1:A6,0)", N(3.0)),
    ("MATCH", "=MATCH(\"CHERRY\",A1:A6,0)", N(3.0)),
    ("MATCH", "=MATCH(\"b*\",A1:A6,0)", N(2.0)),
    ("MATCH", "=MATCH(35,E1:E5,1)", N(3.0)),
    ("MATCH", "=MATCH(35,E1:E5)", N(3.0)),
    ("MATCH", "=MATCH(5,E1:E5,1)", E("#N/A")),
    ("MATCH", "=MATCH(35,{50,40,30,20,10},-1)", N(2.0)),
    ("XMATCH", "=XMATCH(\"cherry\",A1:A6)", N(3.0)),
    ("XMATCH", "=XMATCH(35,E1:E5,1)", N(4.0)),
    ("XMATCH", "=XMATCH(35,E1:E5,-1)", N(3.0)),
    ("XMATCH", "=XMATCH(\"c*\",A1:A6,2)", N(3.0)),
    ("CHOOSE", "=CHOOSE(2,\"a\",\"b\",\"c\")", S("b")),
    ("CHOOSE", "=CHOOSE(4,\"a\",\"b\")", E("#VALUE!")),
    ("CHOOSE", "=CHOOSE(1.9,\"a\",\"b\")", S("a")),
    ("OFFSET", "=SUM(OFFSET(C1,1,0,2,1))", N(5.0)),
    ("OFFSET", "=OFFSET(A1,2,2)", N(3.0)),
    ("OFFSET", "=ROWS(OFFSET(A1,0,0,3,2))", N(3.0)),
    ("INDIRECT", "=INDIRECT(\"C2\")", N(2.0)),
    ("INDIRECT", "=INDIRECT(\"R3C3\",FALSE)", N(3.0)),
    ("INDIRECT", "=SUM(INDIRECT(\"C1:C3\"))", N(6.0)),
    ("INDIRECT", "=INDIRECT(\"Sheet1!C4\")", N(4.0)),
    ("INDIRECT", "=INDIRECT(\"bad!!\")", E("#REF!")),
    ("LOOKUP", "=LOOKUP(35,E1:E5,F1:F5)", S("thirty")),
    ("LOOKUP", "=LOOKUP(100,E1:E5)", N(50.0)),
    ("LOOKUP", "=LOOKUP(5,E1:E5)", E("#N/A")),
    ("ROW", "=ROW(C5)", N(5.0)),
    ("ROW", "=ROW()", N(10.0)),
    ("ROWS", "=ROWS(A1:C6)", N(6.0)),
    ("ROWS", "=ROWS({1,2;3,4})", N(2.0)),
    ("COLUMN", "=COLUMN(C1)", N(3.0)),
    ("COLUMN", "=COLUMN()", N(10.0)),
    ("COLUMNS", "=COLUMNS(A1:C6)", N(3.0)),
    ("ADDRESS", "=ADDRESS(2,3)", S("$C$2")),
    ("ADDRESS", "=ADDRESS(2,3,4)", S("C2")),
    ("ADDRESS", "=ADDRESS(2,3,1,FALSE)", S("R2C3")),
    ("ADDRESS", "=ADDRESS(1,1,1,TRUE,\"Sheet2\")", S("Sheet2!$A$1")),
    ("HYPERLINK", "=HYPERLINK(\"http://x.com\",\"link\")", S("link")),
    ("HYPERLINK", "=HYPERLINK(\"http://x.com\")", S("http://x.com")),
    // ---------------- text ----------------
    ("CONCATENATE", "=CONCATENATE(\"a\",1,TRUE)", S("a1TRUE")),
    ("CONCATENATE", "=CONCATENATE(C1,\"-\",C2)", S("1-2")),
    ("CONCATENATE", "=CONCATENATE(1.5,\"x\")", S("1.5x")),
    ("CONCATENATE", "=CONCATENATE(1/3)", S("0.333333333333333")),
    ("CONCAT", "=CONCAT(A1:A2)", S("applebanana")),
    ("CONCAT", "=CONCAT(\"x\",C1:C3)", S("x123")),
    ("TEXTJOIN", "=TEXTJOIN(\", \",TRUE,A1:A3)", S("apple, banana, cherry")),
    ("TEXTJOIN", "=TEXTJOIN(\"-\",TRUE,B1:B4)", S("10-20-5")),
    ("TEXTJOIN", "=TEXTJOIN(\"-\",FALSE,B1:B4)", S("10-20--5")),
    ("LEFT", "=LEFT(\"hello\",2)", S("he")),
    ("LEFT", "=LEFT(\"hello\")", S("h")),
    ("LEFT", "=LEFT(1234,2)", S("12")),
    ("LEFT", "=LEFT(\"abc\",-1)", E("#VALUE!")),
    ("RIGHT", "=RIGHT(\"hello\",3)", S("llo")),
    ("RIGHT", "=RIGHT(\"abc\",10)", S("abc")),
    ("MID", "=MID(\"hello\",2,3)", S("ell")),
    ("MID", "=MID(\"hello\",10,2)", S("")),
    ("MID", "=MID(\"hello\",0,2)", E("#VALUE!")),
    ("LEN", "=LEN(\"hello\")", N(5.0)),
    ("LEN", "=LEN(123.5)", N(5.0)),
    ("LEN", "=LEN(B3)", N(0.0)),
    ("LEN", "=LEN(1/3)", N(17.0)),
    ("TRIM", "=TRIM(\"  a   b  \")", S("a b")),
    ("UPPER", "=UPPER(\"abc\")", S("ABC")),
    ("LOWER", "=LOWER(\"ÀBC\")", S("àbc")),
    ("PROPER", "=PROPER(\"hello WORLD foo-bar\")", S("Hello World Foo-Bar")),
    ("PROPER", "=PROPER(\"2nd o'neil\")", S("2Nd O'Neil")),
    ("FIND", "=FIND(\"l\",\"hello\")", N(3.0)),
    ("FIND", "=FIND(\"L\",\"hello\")", E("#VALUE!")),
    ("FIND", "=FIND(\"l\",\"hello\",4)", N(4.0)),
    ("SEARCH", "=SEARCH(\"L\",\"hello\")", N(3.0)),
    ("SEARCH", "=SEARCH(\"l?o\",\"hello\")", N(3.0)),
    ("SEARCH", "=SEARCH(\"~?\",\"a?b\")", N(2.0)),
    ("SEARCH", "=SEARCH(\"z\",\"hello\")", E("#VALUE!")),
    ("SUBSTITUTE", "=SUBSTITUTE(\"aaa\",\"a\",\"b\")", S("bbb")),
    ("SUBSTITUTE", "=SUBSTITUTE(\"aaa\",\"a\",\"b\",2)", S("aba")),
    ("SUBSTITUTE", "=SUBSTITUTE(\"abc\",\"\",\"x\")", S("abc")),
    ("REPLACE", "=REPLACE(\"abcdef\",2,3,\"X\")", S("aXef")),
    ("REPLACE", "=REPLACE(\"abc\",5,1,\"Z\")", S("abcZ")),
    ("REPT", "=REPT(\"ab\",3)", S("ababab")),
    ("REPT", "=REPT(\"a\",0)", S("")),
    ("REPT", "=REPT(\"a\",-1)", E("#VALUE!")),
    ("EXACT", "=EXACT(\"a\",\"A\")", B(false)),
    ("EXACT", "=EXACT(1,\"1\")", B(true)),
    ("CHAR", "=CHAR(65)", S("A")),
    ("CHAR", "=CHAR(0)", E("#VALUE!")),
    ("CODE", "=CODE(\"A\")", N(65.0)),
    ("CODE", "=CODE(\"\")", E("#VALUE!")),
    ("CLEAN", "=CLEAN(\"a\"&CHAR(10)&\"b\")", S("ab")),
    ("TEXT", "=TEXT(1234.567,\"0.00\")", S("1234.57")),
    ("TEXT", "=TEXT(1234.567,\"#,##0\")", S("1,235")),
    ("TEXT", "=TEXT(0.256,\"0%\")", S("26%")),
    ("TEXT", "=TEXT(45306,\"dd/mm/yyyy\")", S("15/01/2024")),
    ("TEXT", "=TEXT(45306,\"yyyy-mm-dd\")", S("2024-01-15")),
    ("TEXT", "=TEXT(-1234.5,\"#,##0.00\")", S("-1,234.50")),
    ("TEXT", "=TEXT(45306,\"mmm d, yyyy\")", S("Jan 15, 2024")),
    ("TEXT", "=TEXT(45306,\"dddd\")", S("Monday")),
    ("TEXT", "=TEXT(0.5,\"hh:mm\")", S("12:00")),
    ("TEXT", "=TEXT(5,\"000\")", S("005")),
    ("TEXT", "=TEXT(1234.5,\"$#,##0.00\")", S("$1,234.50")),
    ("TEXT", "=TEXT(\"abc\",\"0.00\")", S("abc")),
    ("TEXT", "=TEXT(1.5,\"0.0E+00\")", S("1.5E+00")),
    ("TEXT", "=TEXT(0.75,\"# ?/?\")", S(" 3/4")),
    ("TEXT", "=TEXT(0,\"0.0;-0.0;\"\"zero\"\"\")", S("zero")),
    ("TEXT", "=TEXT(1.25,\"[h]:mm\")", S("30:00")),
    ("VALUE", "=VALUE(\"123.5\")", N(123.5)),
    ("VALUE", "=VALUE(\"1,234\")", N(1234.0)),
    ("VALUE", "=VALUE(\"10%\")", N(0.1)),
    ("VALUE", "=VALUE(\"$1,000\")", N(1000.0)),
    ("VALUE", "=VALUE(\"abc\")", E("#VALUE!")),
    ("NUMBERVALUE", "=NUMBERVALUE(\"1.234,5\",\",\",\".\")", N(1234.5)),
    ("NUMBERVALUE", "=NUMBERVALUE(\"12%\")", N(0.12)),
    ("NUMBERVALUE", "=NUMBERVALUE(\"abc\")", E("#VALUE!")),
    ("FIXED", "=FIXED(1234.567,1)", S("1,234.6")),
    ("FIXED", "=FIXED(1234.567,-1)", S("1,230")),
    ("FIXED", "=FIXED(1234.567,1,TRUE)", S("1234.6")),
    ("FIXED", "=FIXED(-1234.567)", S("-1,234.57")),
    ("DOLLAR", "=DOLLAR(1234.567,2)", S("$1,234.57")),
    ("DOLLAR", "=DOLLAR(-1234.567,2)", S("($1,234.57)")),
    ("DOLLAR", "=DOLLAR(1234.567,-2)", S("$1,200")),
    ("TEXTBEFORE", "=TEXTBEFORE(\"a-b-c\",\"-\")", S("a")),
    ("TEXTBEFORE", "=TEXTBEFORE(\"a-b-c\",\"-\",-1)", S("a-b")),
    ("TEXTBEFORE", "=TEXTBEFORE(\"abc\",\"x\")", E("#N/A")),
    ("TEXTBEFORE", "=TEXTBEFORE(\"a-B\",\"b\",,1)", S("a-")),
    ("TEXTAFTER", "=TEXTAFTER(\"a-b-c\",\"-\")", S("b-c")),
    ("TEXTAFTER", "=TEXTAFTER(\"a-b-c\",\"-\",2)", S("c")),
    ("TEXTAFTER", "=TEXTAFTER(\"aXb\",\"x\",,1)", S("b")),
    ("TEXTSPLIT", "=INDEX(TEXTSPLIT(\"a,b,c\",\",\"),1,2)", S("b")),
    ("TEXTSPLIT", "=COLUMNS(TEXTSPLIT(\"a,b;c,d\",\",\",\";\"))", N(2.0)),
    ("TEXTSPLIT", "=ROWS(TEXTSPLIT(\"a,b;c,d\",\",\",\";\"))", N(2.0)),
    // ---------------- date & time ----------------
    ("TODAY", "=TODAY()>46300", B(true)),
    ("TODAY", "=TODAY()=INT(NOW())", B(true)),
    ("NOW", "=AND(NOW()>=TODAY(),NOW()<TODAY()+1)", B(true)),
    ("DATE", "=DATE(2024,1,15)", N(45306.0)),
    ("DATE", "=DATE(2024,13,1)", N(45658.0)),
    ("DATE", "=DATE(2024,2,30)", N(45352.0)),
    ("DATE", "=DATE(1900,3,1)", N(61.0)),
    ("DATE", "=DATE(24,1,1)", N(8767.0)),
    ("TIME", "=TIME(12,0,0)", N(0.5)),
    ("TIME", "=TIME(25,0,0)", T(1.0 / 24.0, 1e-12)),
    ("TIME", "=TIME(0,90,0)", N(0.0625)),
    ("YEAR", "=YEAR(45306)", N(2024.0)),
    ("YEAR", "=YEAR(\"2024-03-05\")", N(2024.0)),
    ("YEAR", "=YEAR(0)", N(1900.0)),
    ("MONTH", "=MONTH(45306)", N(1.0)),
    ("MONTH", "=MONTH(0)", N(1.0)),
    ("DAY", "=DAY(45306)", N(15.0)),
    ("DAY", "=DAY(0)", N(0.0)),
    ("HOUR", "=HOUR(0.75)", N(18.0)),
    ("HOUR", "=HOUR(\"14:30\")", N(14.0)),
    ("MINUTE", "=MINUTE(\"14:30:45\")", N(30.0)),
    ("SECOND", "=SECOND(\"14:30:45\")", N(45.0)),
    ("WEEKDAY", "=WEEKDAY(45306)", N(2.0)),
    ("WEEKDAY", "=WEEKDAY(45306,2)", N(1.0)),
    ("WEEKDAY", "=WEEKDAY(45306,3)", N(0.0)),
    ("WEEKNUM", "=WEEKNUM(45306)", N(3.0)),
    ("WEEKNUM", "=WEEKNUM(45306,2)", N(3.0)),
    ("WEEKNUM", "=WEEKNUM(DATE(2023,12,31))", N(53.0)),
    ("ISOWEEKNUM", "=ISOWEEKNUM(DATE(2021,1,1))", N(53.0)),
    ("ISOWEEKNUM", "=ISOWEEKNUM(DATE(2024,12,30))", N(1.0)),
    ("EDATE", "=EDATE(DATE(2024,1,31),1)", N(45351.0)),
    ("EDATE", "=EDATE(45306,-1)", N(45275.0)),
    ("EOMONTH", "=EOMONTH(DATE(2024,1,15),1)", N(45351.0)),
    ("EOMONTH", "=EOMONTH(45306,0)", N(45322.0)),
    ("EOMONTH", "=EOMONTH(45306,-1)", N(45291.0)),
    ("NETWORKDAYS", "=NETWORKDAYS(DATE(2024,1,1),DATE(2024,1,31))", N(23.0)),
    ("NETWORKDAYS", "=NETWORKDAYS(DATE(2024,1,1),DATE(2024,1,31),D1)", N(22.0)),
    ("NETWORKDAYS", "=NETWORKDAYS(DATE(2024,1,31),DATE(2024,1,1))", N(-23.0)),
    ("NETWORKDAYS.INTL", "=NETWORKDAYS.INTL(DATE(2024,1,1),DATE(2024,1,31),11)", N(27.0)),
    ("NETWORKDAYS.INTL", "=NETWORKDAYS.INTL(DATE(2024,1,1),DATE(2024,1,31),\"0000011\")", N(23.0)),
    ("WORKDAY", "=WORKDAY(DATE(2024,1,5),1)", N(45299.0)),
    ("WORKDAY", "=WORKDAY(DATE(2024,1,1),10)", N(45306.0)),
    ("WORKDAY", "=WORKDAY(DATE(2024,1,12),1,D1)", N(45307.0)),
    ("WORKDAY.INTL", "=WORKDAY.INTL(DATE(2024,1,5),1,11)", N(45297.0)),
    ("WORKDAY.INTL", "=WORKDAY.INTL(DATE(2024,1,5),1,\"0000011\")", N(45299.0)),
    ("DATEDIF", "=DATEDIF(DATE(2020,1,15),DATE(2024,1,14),\"Y\")", N(3.0)),
    ("DATEDIF", "=DATEDIF(DATE(2020,1,15),DATE(2024,1,14),\"M\")", N(47.0)),
    ("DATEDIF", "=DATEDIF(DATE(2020,1,15),DATE(2024,1,14),\"D\")", N(1460.0)),
    ("DATEDIF", "=DATEDIF(DATE(2020,1,15),DATE(2024,1,14),\"YM\")", N(11.0)),
    ("DATEDIF", "=DATEDIF(DATE(2024,1,2),DATE(2024,1,1),\"D\")", E("#NUM!")),
    ("DATEVALUE", "=DATEVALUE(\"2024-01-15\")", N(45306.0)),
    ("DATEVALUE", "=DATEVALUE(\"1/15/2024\")", N(45306.0)),
    ("DATEVALUE", "=DATEVALUE(\"15-Jan-2024\")", N(45306.0)),
    ("DATEVALUE", "=DATEVALUE(\"abc\")", E("#VALUE!")),
    ("TIMEVALUE", "=TIMEVALUE(\"12:00\")", N(0.5)),
    ("TIMEVALUE", "=TIMEVALUE(\"6:00 PM\")", N(0.75)),
    ("TIMEVALUE", "=TIMEVALUE(\"2024-01-15 06:00\")", N(0.25)),
    ("DAYS", "=DAYS(DATE(2024,3,1),DATE(2024,2,1))", N(29.0)),
    ("DAYS", "=DAYS(\"2024-03-01\",\"2024-02-01\")", N(29.0)),
    ("YEARFRAC", "=YEARFRAC(DATE(2024,1,1),DATE(2024,7,1))", N(0.5)),
    ("YEARFRAC", "=YEARFRAC(DATE(2024,1,1),DATE(2024,7,1),1)", T(182.0 / 366.0, 1e-9)),
    ("YEARFRAC", "=YEARFRAC(DATE(2024,1,1),DATE(2024,7,1),3)", T(182.0 / 365.0, 1e-9)),
    // ---------------- information ----------------
    ("ISNUMBER", "=ISNUMBER(5)", B(true)),
    ("ISNUMBER", "=ISNUMBER(\"5\")", B(false)),
    ("ISBLANK", "=ISBLANK(B3)", B(true)),
    ("ISBLANK", "=ISBLANK(H1)", B(false)),
    ("ISERROR", "=ISERROR(G1)", B(true)),
    ("ISERROR", "=ISERROR(G3)", B(false)),
    ("ISERR", "=ISERR(G2)", B(false)),
    ("ISERR", "=ISERR(G1)", B(true)),
    ("ISNA", "=ISNA(G2)", B(true)),
    ("ISTEXT", "=ISTEXT(B4)", B(true)),
    ("ISTEXT", "=ISTEXT(B1)", B(false)),
    ("ISLOGICAL", "=ISLOGICAL(B5)", B(true)),
    ("ISEVEN", "=ISEVEN(2.5)", B(true)),
    ("ISEVEN", "=ISEVEN(-3)", B(false)),
    ("ISEVEN", "=ISEVEN(\"a\")", E("#VALUE!")),
    ("ISODD", "=ISODD(3)", B(true)),
    ("N", "=N(5)", N(5.0)),
    ("N", "=N(\"a\")", N(0.0)),
    ("N", "=N(TRUE)", N(1.0)),
    ("N", "=N(B4)", N(0.0)),
    ("NA", "=NA()", E("#N/A")),
    ("TYPE", "=TYPE(1)", N(1.0)),
    ("TYPE", "=TYPE(\"a\")", N(2.0)),
    ("TYPE", "=TYPE(TRUE)", N(4.0)),
    ("TYPE", "=TYPE(1/0)", N(16.0)),
    ("TYPE", "=TYPE({1,2})", N(64.0)),
    ("ERROR.TYPE", "=ERROR.TYPE(1/0)", N(2.0)),
    ("ERROR.TYPE", "=ERROR.TYPE(NA())", N(7.0)),
    ("ERROR.TYPE", "=ERROR.TYPE(1)", E("#N/A")),
    // ---------------- dynamic arrays ----------------
    ("FILTER", "=SUM(FILTER(C1:C6,C1:C6>4))", N(11.0)),
    ("FILTER", "=ROWS(FILTER(C1:C6,C1:C6>4))", N(2.0)),
    ("FILTER", "=INDEX(FILTER(A1:A6,C1:C6>4),1)", S("Banana")),
    ("FILTER", "=FILTER(C1:C6,C1:C6>10)", E("#CALC!")),
    ("FILTER", "=FILTER(C1:C6,C1:C6>10,\"none\")", S("none")),
    ("SORT", "=INDEX(SORT(A1:A3,,-1),1)", S("cherry")),
    ("SORT", "=INDEX(SORT(E1:E5,1,-1),1)", N(50.0)),
    ("SORT", "=INDEX(SORT(E1:E5,,-1),1)", N(50.0)),
    ("SORT", "=INDEX(SORT({3;1;2}),1)", N(1.0)),
    ("SORT", "=INDEX(SORT(A1:A6),2)", S("apple pie")),
    ("SORTBY", "=INDEX(SORTBY(A1:A3,C1:C3,-1),1)", S("cherry")),
    ("UNIQUE", "=ROWS(UNIQUE({1;2;2;3}))", N(3.0)),
    ("UNIQUE", "=ROWS(UNIQUE(A1:A6))", N(5.0)),
    ("UNIQUE", "=ROWS(UNIQUE({1;1;2},,TRUE))", N(1.0)),
    ("SEQUENCE", "=SUM(SEQUENCE(3))", N(6.0)),
    ("SEQUENCE", "=SUM(SEQUENCE(2,3,10,5))", N(135.0)),
    ("SEQUENCE", "=INDEX(SEQUENCE(2,3),2,1)", N(4.0)),
    ("TRANSPOSE", "=COLUMNS(TRANSPOSE(C1:C6))", N(6.0)),
    ("TRANSPOSE", "=INDEX(TRANSPOSE(C1:C6),1,3)", N(3.0)),
    ("HSTACK", "=COLUMNS(HSTACK(C1:C3,E1:E3))", N(2.0)),
    ("HSTACK", "=INDEX(HSTACK({1,2},{3}),1,3)", N(3.0)),
    ("HSTACK", "=INDEX(HSTACK({1;2},3),2,2)", E("#N/A")),
    ("VSTACK", "=ROWS(VSTACK(C1:C3,E1:E2))", N(5.0)),
    ("VSTACK", "=INDEX(VSTACK({1,2},{3,4}),2,1)", N(3.0)),
    ("TAKE", "=SUM(TAKE(C1:C6,2))", N(3.0)),
    ("TAKE", "=SUM(TAKE(C1:C6,-2))", N(11.0)),
    ("TAKE", "=SUM(TAKE(C1:C6,,1))", N(21.0)),
    ("DROP", "=SUM(DROP(C1:C6,2))", N(18.0)),
    ("DROP", "=SUM(DROP(C1:C6,-5))", N(1.0)),
    ("CHOOSECOLS", "=SUM(CHOOSECOLS(A1:C6,3))", N(21.0)),
    ("CHOOSECOLS", "=SUM(CHOOSECOLS(A1:C6,-1))", N(21.0)),
    ("CHOOSEROWS", "=SUM(CHOOSEROWS(C1:C6,1,3))", N(4.0)),
    ("CHOOSEROWS", "=SUM(CHOOSEROWS(C1:C6,-1))", N(6.0)),
    ("LET", "=LET(x,2,y,x*3,x+y)", N(8.0)),
    ("LAMBDA", "=LAMBDA(x,x*2)(5)", N(10.0)),
    ("MAP", "=SUM(MAP(C1:C3,LAMBDA(x,x*x)))", N(14.0)),
    ("BYROW", "=INDEX(BYROW(SEQUENCE(2,2),LAMBDA(r,SUM(r))),2)", N(7.0)),
    ("BYCOL", "=INDEX(BYCOL(SEQUENCE(2,2),LAMBDA(c,SUM(c))),1,2)", N(6.0)),
    ("REDUCE", "=REDUCE(0,C1:C6,LAMBDA(a,v,a+v))", N(21.0)),
    ("GROUPBY", "=ROWS(GROUPBY(A1:A3,C1:C3,SUM))", N(4.0)),
    ("PIVOTBY", "=ROWS(PIVOTBY(L2:L5,M2:M3,N2:N5,SUM))", Ok),
    // ---------------- statistics ----------------
    ("MEDIAN", "=MEDIAN(C1:C6)", N(3.5)),
    ("MEDIAN", "=MEDIAN(1,2,3)", N(2.0)),
    ("MEDIAN", "=MEDIAN(B1:B6)", N(10.0)),
    ("MODE", "=MODE({1,2,2,3,3,3})", N(3.0)),
    ("MODE", "=MODE({1,1,2,2})", N(1.0)),
    ("MODE", "=MODE({1,2,3})", E("#N/A")),
    ("MODE.SNGL", "=MODE.SNGL(1,2,2)", N(2.0)),
    ("STDEV", "=STDEV(C1:C6)", N(1.8708286933869707)),
    ("STDEV", "=STDEV(5)", E("#DIV/0!")),
    ("STDEV.S", "=STDEV.S(C1:C6)", N(1.8708286933869707)),
    ("STDEV.P", "=STDEV.P(C1:C6)", N(1.707825127659933)),
    ("VAR", "=VAR(C1:C6)", N(3.5)),
    ("VAR.S", "=VAR.S(C1:C6)", N(3.5)),
    ("VAR.P", "=VAR.P(C1:C6)", N(35.0 / 12.0)),
    ("LARGE", "=LARGE(C1:C6,2)", N(5.0)),
    ("LARGE", "=LARGE(C1:C6,7)", E("#NUM!")),
    ("SMALL", "=SMALL(B1:B6,1)", N(-3.0)),
    ("SMALL", "=SMALL(C1:C6,0)", E("#NUM!")),
    ("RANK", "=RANK(3,C1:C6)", N(4.0)),
    ("RANK", "=RANK(3,C1:C6,1)", N(3.0)),
    ("RANK", "=RANK(7,C1:C6)", E("#N/A")),
    ("RANK.EQ", "=RANK.EQ(2,{1,2,2,3})", N(2.0)),
    ("RANK.EQ", "=RANK.EQ(3,C1:C6)", N(4.0)),
    ("PERCENTILE", "=PERCENTILE(C1:C6,0.25)", N(2.25)),
    ("PERCENTILE", "=PERCENTILE(C1:C6,1.5)", E("#NUM!")),
    ("PERCENTILE.INC", "=PERCENTILE.INC(C1:C6,0.5)", N(3.5)),
    ("QUARTILE", "=QUARTILE(C1:C6,1)", N(2.25)),
    ("QUARTILE", "=QUARTILE(C1:C6,0)", N(1.0)),
    ("QUARTILE.INC", "=QUARTILE.INC(C1:C6,3)", N(4.75)),
    ("CORREL", "=CORREL(C1:C3,E1:E3)", N(1.0)),
    ("CORREL", "=CORREL({1,2,3,4},{2,1,4,3})", N(0.6)),
    ("AGGREGATE", "=AGGREGATE(9,6,G1:G3)", N(5.0)),
    ("AGGREGATE", "=AGGREGATE(14,6,C1:C6,2)", N(5.0)),
    ("AGGREGATE", "=AGGREGATE(4,0,C1:C6)", N(6.0)),
    ("FORECAST", "=FORECAST(30,{6,7,9,15,21},{20,28,31,38,40})", T(10.607253, 1e-6)),
    ("TREND", "=TREND({1,2,3},{1,2,3},4)", N(4.0)),
    ("SLOPE", "=SLOPE({2,3,9,1,8,7,5},{6,5,11,7,5,4,4})", T(0.305556, 1e-6)),
    ("INTERCEPT", "=INTERCEPT({2,3,9,1,8},{6,5,11,7,5})", T(0.0483871, 1e-7)),
    // ---------------- financial ----------------
    ("PMT", "=PMT(0.05/12,360,200000)", T(-1073.643246, 1e-5)),
    ("PMT", "=PMT(0,10,1000)", N(-100.0)),
    ("PV", "=PV(0.08/12,240,500)", T(-59777.15, 0.01)),
    ("FV", "=FV(0.06/12,10,-200,-500,1)", T(2581.40, 0.01)),
    ("NPV", "=NPV(0.1,-10000,3000,4200,6800)", T(1188.44, 0.01)),
    ("IRR", "=IRR({-70000,12000,15000,18000,21000,26000})", T(0.0866309, 1e-6)),
    ("XNPV", "=XNPV(0.09,{-10000,2750,4250,3250,2750},{39448,39508,39751,39859,39904})", T(2086.65, 0.01)),
    ("XIRR", "=XIRR({-10000,2750,4250,3250,2750},{39448,39508,39751,39859,39904})", T(0.373362535, 1e-6)),
    ("RATE", "=RATE(48,-200,8000)", T(0.00770147, 1e-7)),
    ("NPER", "=NPER(0.12/12,-100,-1000,10000,1)", T(59.6738657, 1e-6)),
    ("IPMT", "=IPMT(0.1/12,1,36,8000)", T(-66.67, 0.005)),
    ("PPMT", "=PPMT(0.1/12,1,24,2000)", T(-75.62, 0.005)),
    // ---------------- database ----------------
    ("DSUM", "=DSUM(L1:N5,\"Profit\",P1:P2)", N(180.0)),
    ("DSUM", "=DSUM(L1:N5,\"Profit\",Q1:Q2)", N(285.0)),
    ("DAVERAGE", "=DAVERAGE(L1:N5,3,P1:P2)", N(90.0)),
    ("DCOUNT", "=DCOUNT(L1:N5,\"Height\",P1:P2)", N(2.0)),
];

/// Coercion rules of the operators themselves (not a function, but users hit them constantly)
const OPERATOR_CASES: &[Case] = &[
    ("(operators)", "=\"1\"+1", N(2.0)),
    ("(operators)", "=\"a\"+1", E("#VALUE!")),
    ("(operators)", "=TRUE+1", N(2.0)),
    ("(operators)", "=B3+1", N(1.0)),
    ("(operators)", "=B3&\"x\"", S("x")),
    ("(operators)", "=\"abc\"=\"ABC\"", B(true)),
    ("(operators)", "=-2^2", N(4.0)),
    ("(operators)", "=1/0", E("#DIV/0!")),
    ("(operators)", "=0.1+0.2=0.3", B(true)),
    ("(operators)", "=0.1+0.2&\"\"", S("0.3")),
    ("(operators)", "=1E+20&\"\"", S("1E+20")),
    ("(operators)", "=\"2024-01-15\"+0", N(45306.0)),
    ("(operators)", "=50%", N(0.5)),
    ("(operators)", "=10>\"9\"", B(false)),
];

#[derive(Debug, Clone, PartialEq)]
enum Status {
    Ok,
    Wrong,
    Missing,
}

struct Outcome {
    func: &'static str,
    formula: &'static str,
    expected: String,
    got: String,
    status: Status,
}

fn exp_str(e: &Exp) -> String {
    match e {
        N(v) => fmt_num(*v),
        T(v, t) => format!("{} (±{})", fmt_num(*v), t),
        S(s) => format!("\"{s}\""),
        B(b) => if *b { "TRUE".into() } else { "FALSE".into() },
        E(e) => e.to_string(),
        Ok => "(any non-error)".into(),
    }
}

fn fmt_num(v: f64) -> String {
    let s = format!("{v:.10}");
    let s = s.trim_end_matches('0').trim_end_matches('.').to_string();
    if s == "-0" { "0".into() } else { s }
}

fn got_str(v: &CellValue) -> String {
    match v {
        CellValue::None => "(empty)".into(),
        CellValue::String(s) if s.starts_with('#') => s.clone(),
        CellValue::String(s) => format!("\"{s}\""),
        CellValue::Number(n) => fmt_num(*n),
        CellValue::Boolean(b) => if *b { "TRUE".into() } else { "FALSE".into() },
    }
}

fn is_error_string(s: &str) -> bool {
    s.starts_with('#') && (s.ends_with('!') || s.ends_with('?') || s == "#N/A")
}

fn check(v: &CellValue, e: &Exp) -> bool {
    match (v, e) {
        (CellValue::Number(n), N(x)) => (n - x).abs() <= 1e-9 * x.abs().max(1.0),
        (CellValue::Number(n), T(x, t)) => (n - x).abs() <= *t,
        (CellValue::String(s), S(x)) => s == x && !is_error_string(s),
        (CellValue::None, S("")) => true,
        (CellValue::Boolean(b), B(x)) => b == x,
        (CellValue::String(s), E(x)) => s == x,
        (CellValue::String(s), Ok) => !is_error_string(s),
        (_, Ok) => true,
        _ => false,
    }
}

fn run_case(func: &'static str, formula: &'static str, exp: Exp) -> Outcome {
    let mut m = Model::new_empty("t", "en", "UTC", "en").unwrap();
    fixture(&mut m);
    let res = m.set_user_input(0, 10, 10, formula.to_string());
    let (got, status) = match res {
        Err(e) => (format!("parse error: {e}"), Status::Wrong),
        Result::Ok(()) => {
            m.evaluate();
            let v = m.get_cell_value_by_index(0, 10, 10).unwrap();
            let s = got_str(&v);
            let status = if check(&v, &exp) {
                Status::Ok
            } else if s == "#NAME?" || s == "#N/IMPL!" {
                Status::Missing
            } else {
                Status::Wrong
            };
            (s, status)
        }
    };
    Outcome { func, formula, expected: exp_str(&exp), got, status }
}

fn locale_probe() {
    println!("## Supported locales (ironcalc_base::get_supported_locales)");
    let mut locales = ironcalc::base::get_supported_locales();
    locales.sort();
    println!("{}", locales.join(", "));
    println!();
    println!("## Languages (probe of Model::new_empty language ids)");
    for l in ["en", "it", "de", "es", "fr", "pt", "nl", "en-US", "it-IT", "ja", "zh"] {
        let ok = Model::new_empty("t", "en", "UTC", l).is_ok();
        println!("language {l:>6}: {}", if ok { "supported" } else { "NOT supported" });
    }
    for l in ["it", "it-IT", "it_IT", "de", "fr", "es", "en-GB", "en-US"] {
        let ok = Model::new_empty("t", l, "UTC", "en").is_ok();
        println!("locale   {l:>6}: {}", if ok { "supported" } else { "NOT supported" });
    }
    println!();
    println!("## Italian probe: Model::new_empty(\"t\",\"it\",\"Europe/Rome\",\"it\")");
    let mut m = match Model::new_empty("t", "it", "Europe/Rome", "it") {
        Result::Ok(m) => m,
        Err(e) => {
            println!("FAILED: {e}");
            return;
        }
    };
    let sheet_name = m.workbook.worksheets[0].name.clone();
    println!("default sheet name: {sheet_name}");
    let inputs: &[(&str, &str)] = &[
        ("A1", "1,5"),
        ("A2", "1.234,5"),
        ("A3", "2"),
        ("A4", "15/01/2024"),
        ("A5", "1234,5"),
        ("B1", "=SOMMA(A1;A3)"),
        ("B2", "=SOMMA(A1:A3)"),
        ("B3", "=SE(A3>1;\"sì\";\"no\")"),
        ("B4", "=CERCA.VERT(2;A3:A3;1;FALSO)"),
        ("B5", "=A1*2"),
        ("B6", "=1,5+1"),
        ("B7", "=SUM(A1,A3)"),
        ("B8", "=TESTO(A5;\"#.##0,00\")"),
        ("B9", "=SE.ERRORE(1/0;\"x\")"),
        ("B10", "=CONTA.SE(A1:A3;\">1\")"),
        ("B11", "=ARROTONDA(2,5;0)"),
        ("B12", "=MEDIA(A1:A3)"),
        ("B13", "=1/0"),
        ("B14", "=VERO"),
        ("B15", "=OGGI()>0"),
    ];
    for (r, v) in inputs {
        let (row, col) = a1(r);
        if let Err(e) = m.set_user_input(0, row, col, v.to_string()) {
            println!("{r} input {v:?}: set_user_input error {e}");
        }
    }
    m.evaluate();
    // a format with grouping and decimals on A5 to see locale rendering
    for (r, v) in inputs {
        let (row, col) = a1(r);
        let value = m.get_cell_value_by_index(0, row, col).unwrap();
        let fmt = m.get_formatted_cell_value(0, row, col).unwrap_or_default();
        let content = m.get_localized_cell_content(0, row, col).unwrap_or_default();
        println!("{r:>4} input {v:<34} -> value {:<22} formatted {:<16} content {}", got_str(&value), format!("{fmt:?}"), content);
    }
    // number formatting with a format code
    let mut m2 = ironcalc::base::UserModel::new_empty("t", "it", "Europe/Rome", "it").unwrap();
    m2.set_user_input(0, 1, 1, "1234,5").unwrap();
    let area = ironcalc::base::expressions::types::Area { sheet: 0, row: 1, column: 1, width: 1, height: 1 };
    let _ = m2.update_range_style(&area, "num_fmt", "#,##0.00");
    println!("it locale, 1234.5 with num_fmt '#,##0.00' -> {:?}", m2.get_formatted_cell_value(0, 1, 1));
    m2.set_user_input(0, 2, 1, "=OGGI()").unwrap();
    println!("it locale, =OGGI() formatted -> {:?}", m2.get_formatted_cell_value(0, 2, 1));
    m2.set_user_input(0, 3, 1, "15/01/2024").unwrap();
    println!("it locale, input 15/01/2024 -> {:?} / {:?}", m2.get_model().get_cell_value_by_index(0, 3, 1), m2.get_formatted_cell_value(0, 3, 1));
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--locale") {
        locale_probe();
        return;
    }
    let md = args.iter().any(|a| a == "--md");
    if let Some(i) = args.iter().position(|a| a == "--probe") {
        // evaluate ad-hoc formulas against the fixture: functions --probe "=F(..)" ...
        for f in &args[i + 1..] {
            let f: &'static str = Box::leak(f.clone().into_boxed_str());
            let o = run_case("probe", f, Ok);
            println!("{:<70} -> {}", o.formula, o.got);
        }
        return;
    }

    // sanity: every function in the list has at least one case
    for f in FUNCTIONS {
        if !CASES.iter().any(|(g, _, _)| g == f) {
            eprintln!("warning: no case for {f}");
        }
    }

    let outcomes: Vec<Outcome> = CASES.iter().map(|(f, x, e)| run_case(f, x, *e)).collect();
    let op_outcomes: Vec<Outcome> = OPERATOR_CASES.iter().map(|(f, x, e)| run_case(f, x, *e)).collect();

    let mut ok = 0;
    let mut wrong = 0;
    let mut missing = 0;
    let mut rows = Vec::new();
    for (rank, f) in FUNCTIONS.iter().enumerate() {
        let mine: Vec<&Outcome> = outcomes.iter().filter(|o| o.func == *f).collect();
        let status = if mine.iter().any(|o| o.status == Status::Missing) {
            missing += 1;
            Status::Missing
        } else if mine.iter().any(|o| o.status == Status::Wrong) {
            wrong += 1;
            Status::Wrong
        } else {
            ok += 1;
            Status::Ok
        };
        let passed = mine.iter().filter(|o| o.status == Status::Ok).count();
        rows.push((rank + 1, *f, status, passed, mine.len()));
    }

    if md {
        println!("| # | Function | Status | Cases passed |");
        println!("|---|---|---|---|");
        for (rank, f, st, p, n) in &rows {
            println!("| {rank} | {f} | {st:?} | {p}/{n} |");
        }
        println!();
        println!("### Failing cases");
        println!();
        println!("| # | Function | Formula | Expected (Excel) | Got (IronCalc) |");
        println!("|---|---|---|---|---|");
        for (rank, f, st, _, _) in &rows {
            if *st == Status::Ok {
                continue;
            }
            for o in outcomes.iter().filter(|o| o.func == *f && o.status != Status::Ok) {
                println!("| {rank} | {} | `{}` | {} | {} |", o.func, o.formula.replace('|', "\\|"), o.expected, o.got);
            }
        }
        println!();
        println!("### Operators");
        println!();
        println!("| Formula | Expected | Got | Status |");
        println!("|---|---|---|---|");
        for o in &op_outcomes {
            println!("| `{}` | {} | {} | {:?} |", o.formula, o.expected, o.got, o.status);
        }
    } else {
        for o in outcomes.iter().chain(op_outcomes.iter()) {
            let tag = match o.status {
                Status::Ok => "ok     ",
                Status::Wrong => "WRONG  ",
                Status::Missing => "MISSING",
            };
            println!("{tag} {:<17} {:<70} expected {:<22} got {}", o.func, o.formula, o.expected, o.got);
        }
    }
    let n_cases = outcomes.len();
    let n_ok_cases = outcomes.iter().filter(|o| o.status == Status::Ok).count();
    println!();
    println!(
        "functions: {} total, {ok} OK, {wrong} WRONG, {missing} MISSING; cases: {n_ok_cases}/{n_cases} passed",
        FUNCTIONS.len()
    );
}
