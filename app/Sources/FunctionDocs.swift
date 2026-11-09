// FunctionDocs.swift
// Help text for formula autocomplete and argument hints (Excel-style).
// Covers every function supported by IronCalc 0.9.1 (English names).
//
// Compile-time note: entries are built from per-category arrays of plain
// `FunctionDoc` values created by a tiny helper, with the argument list stored
// as one comma-separated string. This keeps the Swift type checker fast.

import Foundation

struct FunctionDoc {
    let name: String          // "VLOOKUP"
    let args: [String]        // optional args in brackets; variadic as "number2", "..."
    let summary: String       // one short English sentence, <= 90 chars
    let summaryIT: String     // same in Italian, <= 90 chars
    let category: String      // "Math", "Statistical", "Lookup", ...
}

enum FunctionDocs {

    /// All documented functions keyed by uppercase English name.
    static let all: [String: FunctionDoc] = {
        var list: [FunctionDoc] = []
        list.reserveCapacity(512)
        list.append(contentsOf: logical())
        list.append(contentsOf: math())
        list.append(contentsOf: mathMore())
        list.append(contentsOf: lookup())
        list.append(contentsOf: array())
        list.append(contentsOf: text())
        list.append(contentsOf: information())
        list.append(contentsOf: date())
        list.append(contentsOf: financial())
        list.append(contentsOf: financialSecurities())
        list.append(contentsOf: engineering())
        list.append(contentsOf: database())
        list.append(contentsOf: statistical())
        list.append(contentsOf: statisticalDistributions())
        list.append(contentsOf: statisticalCompat())
        let pairs: [(String, FunctionDoc)] = list.map { (doc: FunctionDoc) -> (String, FunctionDoc) in
            return (doc.name, doc)
        }
        return Dictionary(pairs, uniquingKeysWith: { (first: FunctionDoc, _: FunctionDoc) -> FunctionDoc in first })
    }()

    /// Case-insensitive lookup.
    static func doc(_ name: String) -> FunctionDoc? {
        let key: String = name.trimmingCharacters(in: .whitespaces).uppercased()
        return all[key]
    }

    /// "VLOOKUP(lookup_value, table_array, col_index_num, [range_lookup])".
    /// Unknown names return "NAME()".
    static func signature(_ name: String) -> String {
        guard let d: FunctionDoc = doc(name) else {
            return name.uppercased() + "()"
        }
        return d.name + "(" + d.args.joined(separator: ", ") + ")"
    }

    /// NSRange (UTF-16) of each argument inside `signature(name)`, in order.
    static func argumentRanges(_ name: String) -> [NSRange] {
        guard let d: FunctionDoc = doc(name) else { return [] }
        var ranges: [NSRange] = []
        ranges.reserveCapacity(d.args.count)
        var location: Int = (d.name as NSString).length + 1   // after "NAME("
        for (i, arg) in d.args.enumerated() {
            if i > 0 { location += 2 }                         // ", "
            let len: Int = (arg as NSString).length
            ranges.append(NSRange(location: location, length: len))
            location += len
        }
        return ranges
    }

    // MARK: - Builder

    private static func f(_ name: String, _ category: String, _ args: String,
                          _ en: String, _ it: String) -> FunctionDoc {
        let parts: [String] = args.isEmpty ? [] : args.components(separatedBy: ", ")
        return FunctionDoc(name: name, args: parts, summary: en, summaryIT: it, category: category)
    }

    // MARK: - Logical

    private static func logical() -> [FunctionDoc] {
        let c: String = "Logical"
        let r: [FunctionDoc] = [
            f("AND", c, "logical1, [logical2], ...", "Returns TRUE if all arguments are TRUE.", "Restituisce VERO se tutti gli argomenti sono VERO."),
            f("FALSE", c, "", "Returns the logical value FALSE.", "Restituisce il valore logico FALSO."),
            f("IF", c, "logical_test, [value_if_true], [value_if_false]", "Returns one value if a condition is TRUE and another if it is FALSE.", "Restituisce un valore se la condizione è VERA e un altro se è FALSA."),
            f("IFERROR", c, "value, value_if_error", "Returns value_if_error if the expression is an error, otherwise its value.", "Restituisce value_if_error se l'espressione è un errore, altrimenti il valore."),
            f("IFNA", c, "value, value_if_na", "Returns value_if_na if the expression is #N/A, otherwise its value.", "Restituisce value_if_na se l'espressione è #N/D, altrimenti il valore."),
            f("IFS", c, "logical_test1, value_if_true1, [logical_test2], [value_if_true2], ...", "Returns the value for the first condition that is TRUE.", "Restituisce il valore della prima condizione VERA."),
            f("NOT", c, "logical", "Reverses the logic of its argument.", "Inverte il valore logico dell'argomento."),
            f("OR", c, "logical1, [logical2], ...", "Returns TRUE if any argument is TRUE.", "Restituisce VERO se almeno un argomento è VERO."),
            f("SWITCH", c, "expression, value1, result1, [default_or_value2], [result2], ...", "Compares an expression against a list of values and returns the matching result.", "Confronta un'espressione con più valori e restituisce il risultato corrispondente."),
            f("TRUE", c, "", "Returns the logical value TRUE.", "Restituisce il valore logico VERO."),
            f("XOR", c, "logical1, [logical2], ...", "Returns TRUE if an odd number of arguments are TRUE.", "Restituisce VERO se un numero dispari di argomenti è VERO."),
            f("LET", c, "name1, name_value1, calculation_or_name2, [name_value2], [calculation_or_name3], ...", "Assigns names to calculation results for use inside a formula.", "Assegna nomi ai risultati di calcoli da usare all'interno di una formula."),
            f("LAMBDA", c, "[parameter1], [parameter2], ..., calculation", "Creates a reusable custom function.", "Crea una funzione personalizzata riutilizzabile."),
        ]
        return r
    }

    // MARK: - Math

    private static func math() -> [FunctionDoc] {
        let c: String = "Math"
        let r: [FunctionDoc] = [
            f("LOG", c, "number, [base]", "Returns the logarithm of a number to the given base (default 10).", "Restituisce il logaritmo di un numero nella base indicata (predefinita 10)."),
            f("LOG10", c, "number", "Returns the base-10 logarithm of a number.", "Restituisce il logaritmo in base 10 di un numero."),
            f("LN", c, "number", "Returns the natural logarithm of a number.", "Restituisce il logaritmo naturale di un numero."),
            f("SIN", c, "number", "Returns the sine of an angle in radians.", "Restituisce il seno di un angolo in radianti."),
            f("COS", c, "number", "Returns the cosine of an angle in radians.", "Restituisce il coseno di un angolo in radianti."),
            f("TAN", c, "number", "Returns the tangent of an angle in radians.", "Restituisce la tangente di un angolo in radianti."),
            f("ASIN", c, "number", "Returns the arcsine of a number, in radians.", "Restituisce l'arcoseno di un numero, in radianti."),
            f("ACOS", c, "number", "Returns the arccosine of a number, in radians.", "Restituisce l'arcocoseno di un numero, in radianti."),
            f("ATAN", c, "number", "Returns the arctangent of a number, in radians.", "Restituisce l'arcotangente di un numero, in radianti."),
            f("SINH", c, "number", "Returns the hyperbolic sine of a number.", "Restituisce il seno iperbolico di un numero."),
            f("COSH", c, "number", "Returns the hyperbolic cosine of a number.", "Restituisce il coseno iperbolico di un numero."),
            f("TANH", c, "number", "Returns the hyperbolic tangent of a number.", "Restituisce la tangente iperbolica di un numero."),
            f("ASINH", c, "number", "Returns the inverse hyperbolic sine of a number.", "Restituisce l'inverso del seno iperbolico di un numero."),
            f("ACOSH", c, "number", "Returns the inverse hyperbolic cosine of a number.", "Restituisce l'inverso del coseno iperbolico di un numero."),
            f("ATANH", c, "number", "Returns the inverse hyperbolic tangent of a number.", "Restituisce l'inverso della tangente iperbolica di un numero."),
            f("ACOT", c, "number", "Returns the arccotangent of a number, in radians.", "Restituisce l'arcocotangente di un numero, in radianti."),
            f("ACOTH", c, "number", "Returns the inverse hyperbolic cotangent of a number.", "Restituisce l'inverso della cotangente iperbolica di un numero."),
            f("COT", c, "number", "Returns the cotangent of an angle in radians.", "Restituisce la cotangente di un angolo in radianti."),
            f("COTH", c, "number", "Returns the hyperbolic cotangent of a number.", "Restituisce la cotangente iperbolica di un numero."),
            f("CSC", c, "number", "Returns the cosecant of an angle in radians.", "Restituisce la cosecante di un angolo in radianti."),
            f("CSCH", c, "number", "Returns the hyperbolic cosecant of a number.", "Restituisce la cosecante iperbolica di un numero."),
            f("SEC", c, "number", "Returns the secant of an angle in radians.", "Restituisce la secante di un angolo in radianti."),
            f("SECH", c, "number", "Returns the hyperbolic secant of a number.", "Restituisce la secante iperbolica di un numero."),
            f("ABS", c, "number", "Returns the absolute value of a number.", "Restituisce il valore assoluto di un numero."),
            f("PI", c, "", "Returns the value of pi (3.14159...).", "Restituisce il valore di pi greco (3,14159...)."),
            f("SQRT", c, "number", "Returns the positive square root of a number.", "Restituisce la radice quadrata positiva di un numero."),
            f("SQRTPI", c, "number", "Returns the square root of (number * pi).", "Restituisce la radice quadrata di (numero * pi greco)."),
            f("ATAN2", c, "x_num, y_num", "Returns the arctangent of the given x and y coordinates.", "Restituisce l'arcotangente delle coordinate x e y specificate."),
            f("POWER", c, "number, power", "Returns a number raised to a power.", "Restituisce un numero elevato a una potenza."),
            f("PRODUCT", c, "number1, [number2], ...", "Multiplies all of its arguments.", "Moltiplica tutti gli argomenti."),
            f("RAND", c, "", "Returns a random number between 0 and 1.", "Restituisce un numero casuale compreso tra 0 e 1."),
            f("RANDBETWEEN", c, "bottom, top", "Returns a random integer between the given bounds.", "Restituisce un intero casuale compreso tra i limiti indicati."),
            f("ROUND", c, "number, num_digits", "Rounds a number to the given number of digits.", "Arrotonda un numero al numero di cifre indicato."),
            f("ROUNDDOWN", c, "number, num_digits", "Rounds a number down, toward zero.", "Arrotonda un numero per difetto, verso lo zero."),
            f("ROUNDUP", c, "number, num_digits", "Rounds a number up, away from zero.", "Arrotonda un numero per eccesso, lontano dallo zero."),
            f("SUM", c, "number1, [number2], ...", "Adds all the numbers in a range of cells.", "Somma tutti i numeri in un intervallo di celle."),
            f("SUMIF", c, "range, criteria, [sum_range]", "Adds the cells that meet a given criterion.", "Somma le celle che soddisfano un criterio."),
            f("SUMIFS", c, "sum_range, criteria_range1, criteria1, [criteria_range2], [criteria2], ...", "Adds the cells that meet multiple criteria.", "Somma le celle che soddisfano più criteri."),
            f("SUBTOTAL", c, "function_num, ref1, [ref2], ...", "Returns a subtotal (sum, average, count...) chosen by function_num.", "Restituisce un subtotale (somma, media, conteggio...) scelto da function_num."),
            f("EXP", c, "number", "Returns e raised to the power of a number.", "Restituisce e elevato alla potenza di un numero."),
            f("FACT", c, "number", "Returns the factorial of a number.", "Restituisce il fattoriale di un numero."),
            f("FACTDOUBLE", c, "number", "Returns the double factorial of a number.", "Restituisce il fattoriale doppio di un numero."),
            f("SIGN", c, "number", "Returns the sign of a number: 1, 0 or -1.", "Restituisce il segno di un numero: 1, 0 o -1."),
            f("RADIANS", c, "angle", "Converts degrees to radians.", "Converte i gradi in radianti."),
            f("DEGREES", c, "angle", "Converts radians to degrees.", "Converte i radianti in gradi."),
            f("INT", c, "number", "Rounds a number down to the nearest integer.", "Arrotonda un numero per difetto all'intero più vicino."),
            f("EVEN", c, "number", "Rounds a number up to the nearest even integer.", "Arrotonda un numero per eccesso all'intero pari più vicino."),
            f("ODD", c, "number", "Rounds a number up to the nearest odd integer.", "Arrotonda un numero per eccesso all'intero dispari più vicino."),
            f("CEILING", c, "number, significance", "Rounds a number up to the nearest multiple of significance.", "Arrotonda un numero per eccesso al multiplo più vicino di peso."),
            f("CEILING.MATH", c, "number, [significance], [mode]", "Rounds a number up to the nearest integer or multiple of significance.", "Arrotonda per eccesso all'intero o al multiplo di peso più vicino."),
            f("CEILING.PRECISE", c, "number, [significance]", "Rounds a number up to the nearest multiple, regardless of sign.", "Arrotonda per eccesso al multiplo più vicino, indipendentemente dal segno."),
            f("FLOOR", c, "number, significance", "Rounds a number down to the nearest multiple of significance.", "Arrotonda un numero per difetto al multiplo più vicino di peso."),
            f("FLOOR.MATH", c, "number, [significance], [mode]", "Rounds a number down to the nearest integer or multiple of significance.", "Arrotonda per difetto all'intero o al multiplo di peso più vicino."),
            f("FLOOR.PRECISE", c, "number, [significance]", "Rounds a number down to the nearest multiple, regardless of sign.", "Arrotonda per difetto al multiplo più vicino, indipendentemente dal segno."),
            f("ISO.CEILING", c, "number, [significance]", "Rounds a number up to the nearest integer or multiple (ISO).", "Arrotonda per eccesso all'intero o multiplo più vicino (ISO)."),
            f("ECMA.CEILING", c, "number, significance", "Rounds a number up to the nearest multiple of significance (ECMA).", "Arrotonda per eccesso al multiplo più vicino di peso (ECMA)."),
            f("MOD", c, "number, divisor", "Returns the remainder after division.", "Restituisce il resto di una divisione."),
            f("QUOTIENT", c, "numerator, denominator", "Returns the integer portion of a division.", "Restituisce la parte intera di una divisione."),
            f("MROUND", c, "number, multiple", "Rounds a number to the nearest multiple.", "Arrotonda un numero al multiplo più vicino."),
            f("TRUNC", c, "number, [num_digits]", "Truncates a number by removing its fractional part.", "Tronca un numero eliminandone la parte decimale."),
            f("GCD", c, "number1, [number2], ...", "Returns the greatest common divisor.", "Restituisce il massimo comune divisore."),
            f("LCM", c, "number1, [number2], ...", "Returns the least common multiple.", "Restituisce il minimo comune multiplo."),
        ]
        return r
    }

    private static func mathMore() -> [FunctionDoc] {
        let c: String = "Math"
        let r: [FunctionDoc] = [
            f("BASE", c, "number, radix, [min_length]", "Converts a number to text in the given base.", "Converte un numero in testo nella base indicata."),
            f("DECIMAL", c, "text, radix", "Converts text in a given base to a decimal number.", "Converte un testo in una data base in un numero decimale."),
            f("ROMAN", c, "number, [form]", "Converts an Arabic numeral to Roman, as text.", "Converte un numero arabo in numero romano, come testo."),
            f("ARABIC", c, "text", "Converts a Roman numeral to an Arabic numeral.", "Converte un numero romano in numero arabo."),
            f("COMBIN", c, "number, number_chosen", "Returns the number of combinations for a given number of items.", "Restituisce il numero di combinazioni per un dato numero di elementi."),
            f("COMBINA", c, "number, number_chosen", "Returns the number of combinations with repetitions.", "Restituisce il numero di combinazioni con ripetizioni."),
            f("SUMSQ", c, "number1, [number2], ...", "Returns the sum of the squares of the arguments.", "Restituisce la somma dei quadrati degli argomenti."),
            f("SUMPRODUCT", c, "array1, [array2], ...", "Returns the sum of the products of corresponding array elements.", "Restituisce la somma dei prodotti degli elementi corrispondenti."),
            f("SUMX2MY2", c, "array_x, array_y", "Returns the sum of the difference of squares of two arrays.", "Restituisce la somma della differenza dei quadrati di due matrici."),
            f("SUMX2PY2", c, "array_x, array_y", "Returns the sum of the sum of squares of two arrays.", "Restituisce la somma della somma dei quadrati di due matrici."),
            f("SUMXMY2", c, "array_x, array_y", "Returns the sum of squares of differences of two arrays.", "Restituisce la somma dei quadrati delle differenze di due matrici."),
            f("MMULT", c, "array1, array2", "Returns the matrix product of two arrays.", "Restituisce il prodotto matriciale di due matrici."),
            f("MDETERM", c, "array", "Returns the determinant of a matrix.", "Restituisce il determinante di una matrice."),
            f("MINVERSE", c, "array", "Returns the inverse of a matrix.", "Restituisce l'inversa di una matrice."),
            f("MUNIT", c, "dimension", "Returns the identity matrix of the given size.", "Restituisce la matrice identità della dimensione indicata."),
            f("MULTINOMIAL", c, "number1, [number2], ...", "Returns the multinomial of a set of numbers.", "Restituisce il multinomiale di un insieme di numeri."),
            f("SERIESSUM", c, "x, n, m, coefficients", "Returns the sum of a power series.", "Restituisce la somma di una serie di potenze."),
            f("PERCENTOF", c, "data_subset, data_all", "Returns the percentage that a subset makes of the total.", "Restituisce la percentuale che un sottoinsieme rappresenta sul totale."),
        ]
        return r
    }

    // MARK: - Lookup & reference

    private static func lookup() -> [FunctionDoc] {
        let c: String = "Lookup"
        let r: [FunctionDoc] = [
            f("CHOOSE", c, "index_num, value1, [value2], ...", "Chooses a value from a list based on an index number.", "Sceglie un valore da un elenco in base a un indice."),
            f("COLUMN", c, "[reference]", "Returns the column number of a reference.", "Restituisce il numero di colonna di un riferimento."),
            f("COLUMNS", c, "array", "Returns the number of columns in a reference or array.", "Restituisce il numero di colonne di un riferimento o matrice."),
            f("INDEX", c, "array, row_num, [column_num]", "Returns the value at a given row and column of a range.", "Restituisce il valore alla riga e colonna indicate di un intervallo."),
            f("INDIRECT", c, "ref_text, [a1]", "Returns the reference specified by a text string.", "Restituisce il riferimento indicato da una stringa di testo."),
            f("HLOOKUP", c, "lookup_value, table_array, row_index_num, [range_lookup]", "Looks up a value in the top row and returns a value from the given row.", "Cerca un valore nella prima riga e restituisce un valore dalla riga indicata."),
            f("HYPERLINK", c, "link_location, [friendly_name]", "Creates a link to a document or web address.", "Crea un collegamento a un documento o a un indirizzo web."),
            f("LOOKUP", c, "lookup_value, lookup_vector, [result_vector]", "Looks up a value in a vector and returns the matching result.", "Cerca un valore in un vettore e restituisce il risultato corrispondente."),
            f("MATCH", c, "lookup_value, lookup_array, [match_type]", "Returns the relative position of a value in a range.", "Restituisce la posizione relativa di un valore in un intervallo."),
            f("OFFSET", c, "reference, rows, cols, [height], [width]", "Returns a reference offset from a starting reference.", "Restituisce un riferimento spostato rispetto a un riferimento iniziale."),
            f("ROW", c, "[reference]", "Returns the row number of a reference.", "Restituisce il numero di riga di un riferimento."),
            f("ROWS", c, "array", "Returns the number of rows in a reference or array.", "Restituisce il numero di righe di un riferimento o matrice."),
            f("VLOOKUP", c, "lookup_value, table_array, col_index_num, [range_lookup]", "Looks up a value in the first column and returns a value from the given column.", "Cerca un valore nella prima colonna e restituisce un valore dalla colonna indicata."),
            f("XLOOKUP", c, "lookup_value, lookup_array, return_array, [if_not_found], [match_mode], [search_mode]", "Searches a range and returns the item from a second range at the match.", "Cerca in un intervallo e restituisce l'elemento corrispondente di un altro."),
            f("XMATCH", c, "lookup_value, lookup_array, [match_mode], [search_mode]", "Returns the relative position of an item in an array.", "Restituisce la posizione relativa di un elemento in una matrice."),
            f("ADDRESS", c, "row_num, column_num, [abs_num], [a1], [sheet_text]", "Returns a cell reference as text from row and column numbers.", "Restituisce un riferimento di cella come testo da numeri di riga e colonna."),
            f("AREAS", c, "reference", "Returns the number of areas in a reference.", "Restituisce il numero di aree in un riferimento."),
            f("TRANSPOSE", c, "array", "Swaps the rows and columns of an array.", "Scambia righe e colonne di una matrice."),
            f("TRIMRANGE", c, "range, [trim_rows], [trim_cols]", "Removes empty leading and trailing rows and columns from a range.", "Rimuove righe e colonne vuote iniziali e finali da un intervallo."),
        ]
        return r
    }

    // MARK: - Array / dynamic

    private static func array() -> [FunctionDoc] {
        let c: String = "Array"
        let r: [FunctionDoc] = [
            f("SORT", c, "array, [sort_index], [sort_order], [by_col]", "Sorts the contents of a range or array.", "Ordina il contenuto di un intervallo o matrice."),
            f("SORTBY", c, "array, by_array1, [sort_order1], [by_array2], [sort_order2], ...", "Sorts a range based on the values of other ranges.", "Ordina un intervallo in base ai valori di altri intervalli."),
            f("UNIQUE", c, "array, [by_col], [exactly_once]", "Returns the unique values of a range or array.", "Restituisce i valori univoci di un intervallo o matrice."),
            f("FILTER", c, "array, include, [if_empty]", "Filters a range based on criteria you define.", "Filtra un intervallo in base ai criteri definiti."),
            f("SEQUENCE", c, "rows, [columns], [start], [step]", "Generates a list of sequential numbers in an array.", "Genera un elenco di numeri sequenziali in una matrice."),
            f("RANDARRAY", c, "[rows], [columns], [min], [max], [whole_number]", "Returns an array of random numbers.", "Restituisce una matrice di numeri casuali."),
            f("TAKE", c, "array, rows, [columns]", "Returns rows or columns from the start or end of an array.", "Restituisce righe o colonne dall'inizio o dalla fine di una matrice."),
            f("DROP", c, "array, rows, [columns]", "Excludes rows or columns from the start or end of an array.", "Esclude righe o colonne dall'inizio o dalla fine di una matrice."),
            f("TOCOL", c, "array, [ignore], [scan_by_column]", "Returns the array as a single column.", "Restituisce la matrice come un'unica colonna."),
            f("TOROW", c, "array, [ignore], [scan_by_column]", "Returns the array as a single row.", "Restituisce la matrice come un'unica riga."),
            f("BYCOL", c, "array, lambda", "Applies a LAMBDA to each column and returns an array of results.", "Applica una LAMBDA a ogni colonna e restituisce una matrice di risultati."),
            f("BYROW", c, "array, lambda", "Applies a LAMBDA to each row and returns an array of results.", "Applica una LAMBDA a ogni riga e restituisce una matrice di risultati."),
            f("MAP", c, "array1, lambda_or_array2, ...", "Maps each value of the arrays to a new value using a LAMBDA.", "Trasforma ogni valore delle matrici in un nuovo valore con una LAMBDA."),
            f("REDUCE", c, "[initial_value], array, lambda", "Reduces an array to an accumulated value using a LAMBDA.", "Riduce una matrice a un valore accumulato tramite una LAMBDA."),
            f("SCAN", c, "[initial_value], array, lambda", "Applies a LAMBDA to each value and returns all intermediate values.", "Applica una LAMBDA a ogni valore e restituisce tutti i valori intermedi."),
            f("MAKEARRAY", c, "rows, cols, lambda", "Returns an array of the given size computed by a LAMBDA.", "Restituisce una matrice delle dimensioni indicate calcolata da una LAMBDA."),
            f("CHOOSECOLS", c, "array, col_num1, [col_num2], ...", "Returns the specified columns from an array.", "Restituisce le colonne specificate di una matrice."),
            f("CHOOSEROWS", c, "array, row_num1, [row_num2], ...", "Returns the specified rows from an array.", "Restituisce le righe specificate di una matrice."),
            f("EXPAND", c, "array, rows, [columns], [pad_with]", "Expands an array to the given dimensions.", "Espande una matrice alle dimensioni indicate."),
            f("HSTACK", c, "array1, [array2], ...", "Appends arrays horizontally into a single array.", "Accoda le matrici orizzontalmente in un'unica matrice."),
            f("VSTACK", c, "array1, [array2], ...", "Appends arrays vertically into a single array.", "Accoda le matrici verticalmente in un'unica matrice."),
            f("WRAPCOLS", c, "vector, wrap_count, [pad_with]", "Wraps a row or column into columns of the given length.", "Divide una riga o colonna in colonne della lunghezza indicata."),
            f("WRAPROWS", c, "vector, wrap_count, [pad_with]", "Wraps a row or column into rows of the given length.", "Divide una riga o colonna in righe della lunghezza indicata."),
        ]
        return r
    }

    // MARK: - Text

    private static func text() -> [FunctionDoc] {
        let c: String = "Text"
        let r: [FunctionDoc] = [
            f("TEXTSPLIT", c, "text, col_delimiter, [row_delimiter], [ignore_empty], [match_mode], [pad_with]", "Splits text into rows and columns using delimiters.", "Divide il testo in righe e colonne usando dei delimitatori."),
            f("CONCATENATE", c, "text1, [text2], ...", "Joins several text items into one.", "Unisce più elementi di testo in uno solo."),
            f("CONCAT", c, "text1, [text2], ...", "Joins text from multiple ranges and/or strings.", "Unisce il testo di più intervalli e/o stringhe."),
            f("EXACT", c, "text1, text2", "Checks whether two texts are identical (case-sensitive).", "Verifica se due testi sono identici (distingue maiuscole)."),
            f("VALUE", c, "text", "Converts a text string that represents a number to a number.", "Converte in numero una stringa di testo che rappresenta un numero."),
            f("T", c, "value", "Returns the text if the value is text, otherwise empty text.", "Restituisce il testo se il valore è testo, altrimenti testo vuoto."),
            f("VALUETOTEXT", c, "value, [format]", "Returns text from any value.", "Restituisce un testo a partire da qualsiasi valore."),
            f("ARRAYTOTEXT", c, "array, [format]", "Returns an array of values as text.", "Restituisce una matrice di valori come testo."),
            f("FIND", c, "find_text, within_text, [start_num]", "Finds one text inside another (case-sensitive).", "Trova un testo all'interno di un altro (distingue maiuscole)."),
            f("FINDB", c, "find_text, within_text, [start_num]", "Finds one text inside another, counting bytes.", "Trova un testo all'interno di un altro, contando i byte."),
            f("SEARCH", c, "find_text, within_text, [start_num]", "Finds one text inside another (not case-sensitive, wildcards allowed).", "Trova un testo in un altro (senza distinzione maiuscole, con caratteri jolly)."),
            f("SEARCHB", c, "find_text, within_text, [start_num]", "Finds one text inside another (not case-sensitive), counting bytes.", "Trova un testo in un altro (senza distinzione maiuscole), contando i byte."),
            f("LEFT", c, "text, [num_chars]", "Returns the leftmost characters of a text.", "Restituisce i caratteri più a sinistra di un testo."),
            f("LEFTB", c, "text, [num_bytes]", "Returns the leftmost characters of a text, by bytes.", "Restituisce i caratteri più a sinistra di un testo, in byte."),
            f("RIGHT", c, "text, [num_chars]", "Returns the rightmost characters of a text.", "Restituisce i caratteri più a destra di un testo."),
            f("RIGHTB", c, "text, [num_bytes]", "Returns the rightmost characters of a text, by bytes.", "Restituisce i caratteri più a destra di un testo, in byte."),
            f("MID", c, "text, start_num, num_chars", "Returns characters from the middle of a text.", "Restituisce caratteri dalla parte centrale di un testo."),
            f("MIDB", c, "text, start_num, num_bytes", "Returns characters from the middle of a text, by bytes.", "Restituisce caratteri dalla parte centrale di un testo, in byte."),
            f("LEN", c, "text", "Returns the number of characters in a text.", "Restituisce il numero di caratteri di un testo."),
            f("LENB", c, "text", "Returns the number of bytes used to represent a text.", "Restituisce il numero di byte usati per rappresentare un testo."),
            f("LOWER", c, "text", "Converts text to lowercase.", "Converte il testo in minuscolo."),
            f("UPPER", c, "text", "Converts text to uppercase.", "Converte il testo in maiuscolo."),
            f("PROPER", c, "text", "Capitalizes the first letter of each word.", "Rende maiuscola la prima lettera di ogni parola."),
            f("TEXT", c, "value, format_text", "Formats a number and converts it to text.", "Formatta un numero e lo converte in testo."),
            f("TRIM", c, "text", "Removes extra spaces from text.", "Rimuove gli spazi in eccesso dal testo."),
            f("UNICODE", c, "text", "Returns the Unicode code point of the first character.", "Restituisce il codice Unicode del primo carattere."),
            f("UNICHAR", c, "number", "Returns the Unicode character for a code point.", "Restituisce il carattere Unicode corrispondente a un codice."),
            f("CHAR", c, "number", "Returns the character specified by a code number.", "Restituisce il carattere corrispondente a un codice."),
            f("CODE", c, "text", "Returns the numeric code of the first character.", "Restituisce il codice numerico del primo carattere."),
            f("CLEAN", c, "text", "Removes all non-printable characters from text.", "Rimuove tutti i caratteri non stampabili dal testo."),
            f("ASC", c, "text", "Converts full-width characters to half-width.", "Converte i caratteri a larghezza intera in mezza larghezza."),
            f("DOLLAR", c, "number, [decimals]", "Converts a number to text in currency format.", "Converte un numero in testo in formato valuta."),
            f("FIXED", c, "number, [decimals], [no_commas]", "Formats a number as text with a fixed number of decimals.", "Formatta un numero come testo con un numero fisso di decimali."),
            f("NUMBERVALUE", c, "text, [decimal_separator], [group_separator]", "Converts text to a number, independent of locale.", "Converte un testo in numero, indipendentemente dalle impostazioni locali."),
            f("REPLACE", c, "old_text, start_num, num_chars, new_text", "Replaces part of a text at a given position.", "Sostituisce parte di un testo in una posizione indicata."),
            f("REPLACEB", c, "old_text, start_num, num_bytes, new_text", "Replaces part of a text at a given position, by bytes.", "Sostituisce parte di un testo in una posizione indicata, in byte."),
            f("REPT", c, "text, number_times", "Repeats text a given number of times.", "Ripete un testo il numero di volte indicato."),
            f("SUBSTITUTE", c, "text, old_text, new_text, [instance_num]", "Substitutes new text for old text in a string.", "Sostituisce un testo esistente con un nuovo testo in una stringa."),
            f("TEXTAFTER", c, "text, delimiter, [instance_num], [match_mode], [match_end], [if_not_found]", "Returns the text that occurs after a given delimiter.", "Restituisce il testo che segue un delimitatore indicato."),
            f("TEXTBEFORE", c, "text, delimiter, [instance_num], [match_mode], [match_end], [if_not_found]", "Returns the text that occurs before a given delimiter.", "Restituisce il testo che precede un delimitatore indicato."),
            f("TEXTJOIN", c, "delimiter, ignore_empty, text1, [text2], ...", "Joins texts with a delimiter, optionally ignoring empty values.", "Unisce testi con un delimitatore, ignorando facoltativamente i vuoti."),
            f("REGEXEXTRACT", c, "text, pattern, [return_mode], [case_sensitivity]", "Extracts text that matches a regular expression.", "Estrae il testo che corrisponde a un'espressione regolare."),
            f("REGEXREPLACE", c, "text, pattern, replacement, [occurrence], [case_sensitivity]", "Replaces text that matches a regular expression.", "Sostituisce il testo che corrisponde a un'espressione regolare."),
            f("REGEXTEST", c, "text, pattern, [case_sensitivity]", "Checks whether text matches a regular expression.", "Verifica se il testo corrisponde a un'espressione regolare."),
            f("ENCODEURL", c, "text", "Returns a URL-encoded string.", "Restituisce una stringa codificata per URL."),
        ]
        return r
    }

    // MARK: - Information

    private static func information() -> [FunctionDoc] {
        let c: String = "Information"
        let r: [FunctionDoc] = [
            f("ISNUMBER", c, "value", "Returns TRUE if the value is a number.", "Restituisce VERO se il valore è un numero."),
            f("ISNONTEXT", c, "value", "Returns TRUE if the value is not text.", "Restituisce VERO se il valore non è testo."),
            f("ISTEXT", c, "value", "Returns TRUE if the value is text.", "Restituisce VERO se il valore è testo."),
            f("ISLOGICAL", c, "value", "Returns TRUE if the value is a logical value.", "Restituisce VERO se il valore è un valore logico."),
            f("ISBLANK", c, "value", "Returns TRUE if the value is empty.", "Restituisce VERO se il valore è vuoto."),
            f("ISERR", c, "value", "Returns TRUE if the value is any error except #N/A.", "Restituisce VERO se il valore è un errore diverso da #N/D."),
            f("ISERROR", c, "value", "Returns TRUE if the value is any error.", "Restituisce VERO se il valore è un errore qualsiasi."),
            f("ISNA", c, "value", "Returns TRUE if the value is the #N/A error.", "Restituisce VERO se il valore è l'errore #N/D."),
            f("NA", c, "", "Returns the #N/A error value.", "Restituisce il valore di errore #N/D."),
            f("ISREF", c, "value", "Returns TRUE if the value is a reference.", "Restituisce VERO se il valore è un riferimento."),
            f("ISODD", c, "number", "Returns TRUE if the number is odd.", "Restituisce VERO se il numero è dispari."),
            f("ISEVEN", c, "number", "Returns TRUE if the number is even.", "Restituisce VERO se il numero è pari."),
            f("ERROR.TYPE", c, "error_val", "Returns a number corresponding to an error type.", "Restituisce un numero corrispondente a un tipo di errore."),
            f("FORMULATEXT", c, "reference", "Returns the formula at the given reference as text.", "Restituisce come testo la formula del riferimento indicato."),
            f("ISFORMULA", c, "reference", "Returns TRUE if the reference contains a formula.", "Restituisce VERO se il riferimento contiene una formula."),
            f("ISOMITTED", c, "argument", "Checks whether a LAMBDA argument is missing.", "Verifica se manca un argomento di una LAMBDA."),
            f("TYPE", c, "value", "Returns a number indicating the data type of a value.", "Restituisce un numero che indica il tipo di dato di un valore."),
            f("SHEET", c, "[value]", "Returns the sheet number of the referenced sheet.", "Restituisce il numero del foglio a cui si fa riferimento."),
            f("SHEETS", c, "[reference]", "Returns the number of sheets in a reference.", "Restituisce il numero di fogli in un riferimento."),
            f("N", c, "value", "Returns a value converted to a number.", "Restituisce un valore convertito in numero."),
            f("CELL", c, "info_type, [reference]", "Returns information about the formatting, location or contents of a cell.", "Restituisce informazioni su formato, posizione o contenuto di una cella."),
            f("INFO", c, "type_text", "Returns information about the current operating environment.", "Restituisce informazioni sull'ambiente operativo corrente."),
        ]
        return r
    }

    // MARK: - Date & time

    private static func date() -> [FunctionDoc] {
        let c: String = "Date"
        let r: [FunctionDoc] = [
            f("YEAR", c, "serial_number", "Returns the year of a date.", "Restituisce l'anno di una data."),
            f("MONTH", c, "serial_number", "Returns the month of a date (1 to 12).", "Restituisce il mese di una data (da 1 a 12)."),
            f("DAY", c, "serial_number", "Returns the day of the month of a date (1 to 31).", "Restituisce il giorno del mese di una data (da 1 a 31)."),
            f("EOMONTH", c, "start_date, months", "Returns the last day of the month a number of months away.", "Restituisce l'ultimo giorno del mese a un dato numero di mesi."),
            f("DATE", c, "year, month, day", "Returns the serial number of a given date.", "Restituisce il numero seriale di una data."),
            f("DATEDIF", c, "start_date, end_date, unit", "Returns the difference between two dates in days, months or years.", "Restituisce la differenza tra due date in giorni, mesi o anni."),
            f("DATEVALUE", c, "date_text", "Converts a date in text form to a serial number.", "Converte una data in formato testo in numero seriale."),
            f("EDATE", c, "start_date, months", "Returns the date a number of months before or after a date.", "Restituisce la data a un numero di mesi prima o dopo una data."),
            f("NETWORKDAYS", c, "start_date, end_date, [holidays]", "Returns the number of whole working days between two dates.", "Restituisce il numero di giorni lavorativi interi tra due date."),
            f("NETWORKDAYS.INTL", c, "start_date, end_date, [weekend], [holidays]", "Returns working days between two dates with custom weekends.", "Restituisce i giorni lavorativi tra due date con fine settimana personalizzati."),
            f("TIME", c, "hour, minute, second", "Returns the serial number of a given time.", "Restituisce il numero seriale di un orario."),
            f("TIMEVALUE", c, "time_text", "Converts a time in text form to a serial number.", "Converte un orario in formato testo in numero seriale."),
            f("HOUR", c, "serial_number", "Returns the hour of a time value (0 to 23).", "Restituisce l'ora di un valore orario (da 0 a 23)."),
            f("MINUTE", c, "serial_number", "Returns the minute of a time value (0 to 59).", "Restituisce i minuti di un valore orario (da 0 a 59)."),
            f("SECOND", c, "serial_number", "Returns the second of a time value (0 to 59).", "Restituisce i secondi di un valore orario (da 0 a 59)."),
            f("TODAY", c, "", "Returns the current date.", "Restituisce la data corrente."),
            f("NOW", c, "", "Returns the current date and time.", "Restituisce la data e l'ora correnti."),
            f("DAYS", c, "end_date, start_date", "Returns the number of days between two dates.", "Restituisce il numero di giorni tra due date."),
            f("DAYS360", c, "start_date, end_date, [method]", "Returns the days between two dates on a 360-day year.", "Restituisce i giorni tra due date su un anno di 360 giorni."),
            f("WEEKDAY", c, "serial_number, [return_type]", "Returns the day of the week of a date.", "Restituisce il giorno della settimana di una data."),
            f("WEEKNUM", c, "serial_number, [return_type]", "Returns the week number of a date in the year.", "Restituisce il numero della settimana dell'anno di una data."),
            f("ISOWEEKNUM", c, "date", "Returns the ISO week number of a date in the year.", "Restituisce il numero di settimana ISO di una data."),
            f("WORKDAY", c, "start_date, days, [holidays]", "Returns the date a number of working days away.", "Restituisce la data a un dato numero di giorni lavorativi."),
            f("WORKDAY.INTL", c, "start_date, days, [weekend], [holidays]", "Returns the date a number of working days away, with custom weekends.", "Restituisce la data a N giorni lavorativi, con fine settimana personalizzati."),
            f("YEARFRAC", c, "start_date, end_date, [basis]", "Returns the fraction of the year between two dates.", "Restituisce la frazione d'anno compresa tra due date."),
        ]
        return r
    }

    // MARK: - Financial

    private static func financial() -> [FunctionDoc] {
        let c: String = "Financial"
        let r: [FunctionDoc] = [
            f("PMT", c, "rate, nper, pv, [fv], [type]", "Returns the periodic payment for a loan.", "Restituisce la rata periodica di un prestito."),
            f("PV", c, "rate, nper, pmt, [fv], [type]", "Returns the present value of an investment.", "Restituisce il valore attuale di un investimento."),
            f("FV", c, "rate, nper, pmt, [pv], [type]", "Returns the future value of an investment.", "Restituisce il valore futuro di un investimento."),
            f("RATE", c, "nper, pmt, pv, [fv], [type], [guess]", "Returns the interest rate per period of an annuity.", "Restituisce il tasso di interesse per periodo di una rendita."),
            f("NPER", c, "rate, pmt, pv, [fv], [type]", "Returns the number of periods for an investment.", "Restituisce il numero di periodi di un investimento."),
            f("PPMT", c, "rate, per, nper, pv, [fv], [type]", "Returns the principal portion of a payment for a given period.", "Restituisce la quota capitale di una rata per un dato periodo."),
            f("IPMT", c, "rate, per, nper, pv, [fv], [type]", "Returns the interest portion of a payment for a given period.", "Restituisce la quota interessi di una rata per un dato periodo."),
            f("NPV", c, "rate, value1, [value2], ...", "Returns the net present value from periodic cash flows and a discount rate.", "Restituisce il valore attuale netto da flussi periodici e un tasso di sconto."),
            f("MIRR", c, "values, finance_rate, reinvest_rate", "Returns the modified internal rate of return.", "Restituisce il tasso interno di rendimento modificato."),
            f("IRR", c, "values, [guess]", "Returns the internal rate of return for a series of cash flows.", "Restituisce il tasso interno di rendimento di una serie di flussi."),
            f("XIRR", c, "values, dates, [guess]", "Returns the internal rate of return for non-periodic cash flows.", "Restituisce il tasso interno di rendimento di flussi non periodici."),
            f("XNPV", c, "rate, values, dates", "Returns the net present value for non-periodic cash flows.", "Restituisce il valore attuale netto di flussi non periodici."),
            f("ISPMT", c, "rate, per, nper, pv", "Returns the interest paid in a given period with even principal payments.", "Restituisce gli interessi pagati in un periodo con quote capitale costanti."),
            f("RRI", c, "nper, pv, fv", "Returns an equivalent interest rate for the growth of an investment.", "Restituisce un tasso di interesse equivalente per la crescita di un investimento."),
            f("SLN", c, "cost, salvage, life", "Returns straight-line depreciation for one period.", "Restituisce l'ammortamento a quote costanti per un periodo."),
            f("SYD", c, "cost, salvage, life, per", "Returns sum-of-years' digits depreciation for a period.", "Restituisce l'ammortamento a somma degli anni per un periodo."),
            f("NOMINAL", c, "effect_rate, npery", "Returns the annual nominal interest rate.", "Restituisce il tasso di interesse nominale annuo."),
            f("EFFECT", c, "nominal_rate, npery", "Returns the effective annual interest rate.", "Restituisce il tasso di interesse effettivo annuo."),
            f("PDURATION", c, "rate, pv, fv", "Returns the number of periods for an investment to reach a value.", "Restituisce il numero di periodi per cui un investimento raggiunge un valore."),
            f("DOLLARDE", c, "fractional_dollar, fraction", "Converts a fractional price to a decimal price.", "Converte un prezzo frazionario in prezzo decimale."),
            f("DOLLARFR", c, "decimal_dollar, fraction", "Converts a decimal price to a fractional price.", "Converte un prezzo decimale in prezzo frazionario."),
            f("DDB", c, "cost, salvage, life, period, [factor]", "Returns depreciation using the double-declining balance method.", "Restituisce l'ammortamento a quote decrescenti doppie."),
            f("DB", c, "cost, salvage, life, period, [month]", "Returns depreciation using the fixed-declining balance method.", "Restituisce l'ammortamento a quote fisse decrescenti."),
            f("VDB", c, "cost, salvage, life, start_period, end_period, [factor], [no_switch]", "Returns depreciation for any period using a declining balance method.", "Restituisce l'ammortamento per un periodo con metodo a quote decrescenti."),
            f("CUMPRINC", c, "rate, nper, pv, start_period, end_period, type", "Returns the cumulative principal paid between two periods.", "Restituisce il capitale cumulativo pagato tra due periodi."),
            f("CUMIPMT", c, "rate, nper, pv, start_period, end_period, type", "Returns the cumulative interest paid between two periods.", "Restituisce gli interessi cumulativi pagati tra due periodi."),
            f("FVSCHEDULE", c, "principal, schedule", "Returns the future value of a principal after a series of rates.", "Restituisce il valore futuro di un capitale dopo una serie di tassi."),
            f("AMORDEGRC", c, "cost, date_purchased, first_period, salvage, period, rate, [basis]", "Returns depreciation per period using a depreciation coefficient.", "Restituisce l'ammortamento per periodo con un coefficiente di ammortamento."),
            f("AMORLINC", c, "cost, date_purchased, first_period, salvage, period, rate, [basis]", "Returns linear depreciation for each accounting period.", "Restituisce l'ammortamento lineare per ogni periodo contabile."),
        ]
        return r
    }

    private static func financialSecurities() -> [FunctionDoc] {
        let c: String = "Financial"
        let r: [FunctionDoc] = [
            f("TBILLYIELD", c, "settlement, maturity, pr", "Returns the yield of a Treasury bill.", "Restituisce il rendimento di un buono del Tesoro."),
            f("TBILLPRICE", c, "settlement, maturity, discount", "Returns the price per $100 of a Treasury bill.", "Restituisce il prezzo per 100 di un buono del Tesoro."),
            f("TBILLEQ", c, "settlement, maturity, discount", "Returns the bond-equivalent yield of a Treasury bill.", "Restituisce il rendimento equivalente obbligazionario di un buono del Tesoro."),
            f("ACCRINT", c, "issue, first_interest, settlement, rate, par, frequency, [basis], [calc_method]", "Returns accrued interest for a security that pays periodic interest.", "Restituisce l'interesse maturato di un titolo con interessi periodici."),
            f("ACCRINTM", c, "issue, settlement, rate, par, [basis]", "Returns accrued interest for a security that pays interest at maturity.", "Restituisce l'interesse maturato di un titolo con interessi a scadenza."),
            f("DISC", c, "settlement, maturity, pr, redemption, [basis]", "Returns the discount rate for a security.", "Restituisce il tasso di sconto di un titolo."),
            f("INTRATE", c, "settlement, maturity, investment, redemption, [basis]", "Returns the interest rate for a fully invested security.", "Restituisce il tasso di interesse di un titolo interamente investito."),
            f("PRICEDISC", c, "settlement, maturity, discount, redemption, [basis]", "Returns the price per $100 of a discounted security.", "Restituisce il prezzo per 100 di un titolo scontato."),
            f("PRICEMAT", c, "settlement, maturity, issue, rate, yld, [basis]", "Returns the price per $100 of a security that pays interest at maturity.", "Restituisce il prezzo per 100 di un titolo con interessi a scadenza."),
            f("RECEIVED", c, "settlement, maturity, investment, discount, [basis]", "Returns the amount received at maturity for a fully invested security.", "Restituisce l'importo ricevuto a scadenza per un titolo interamente investito."),
            f("YIELDDISC", c, "settlement, maturity, pr, redemption, [basis]", "Returns the annual yield of a discounted security.", "Restituisce il rendimento annuo di un titolo scontato."),
            f("YIELDMAT", c, "settlement, maturity, issue, rate, pr, [basis]", "Returns the annual yield of a security that pays interest at maturity.", "Restituisce il rendimento annuo di un titolo con interessi a scadenza."),
            f("DURATION", c, "settlement, maturity, coupon, yld, frequency, [basis]", "Returns the Macaulay duration of a security with periodic interest.", "Restituisce la durata di Macaulay di un titolo con interessi periodici."),
            f("MDURATION", c, "settlement, maturity, coupon, yld, frequency, [basis]", "Returns the modified Macaulay duration for a security.", "Restituisce la durata di Macaulay modificata di un titolo."),
            f("PRICE", c, "settlement, maturity, rate, yld, redemption, frequency, [basis]", "Returns the price per $100 of a security that pays periodic interest.", "Restituisce il prezzo per 100 di un titolo con interessi periodici."),
            f("YIELD", c, "settlement, maturity, rate, pr, redemption, frequency, [basis]", "Returns the yield of a security that pays periodic interest.", "Restituisce il rendimento di un titolo con interessi periodici."),
            f("ODDFPRICE", c, "settlement, maturity, issue, first_coupon, rate, yld, redemption, frequency, [basis]", "Returns the price per $100 of a security with an odd first period.", "Restituisce il prezzo per 100 di un titolo con primo periodo irregolare."),
            f("ODDFYIELD", c, "settlement, maturity, issue, first_coupon, rate, pr, redemption, frequency, [basis]", "Returns the yield of a security with an odd first period.", "Restituisce il rendimento di un titolo con primo periodo irregolare."),
            f("ODDLPRICE", c, "settlement, maturity, last_interest, rate, yld, redemption, frequency, [basis]", "Returns the price per $100 of a security with an odd last period.", "Restituisce il prezzo per 100 di un titolo con ultimo periodo irregolare."),
            f("ODDLYIELD", c, "settlement, maturity, last_interest, rate, pr, redemption, frequency, [basis]", "Returns the yield of a security with an odd last period.", "Restituisce il rendimento di un titolo con ultimo periodo irregolare."),
            f("COUPDAYBS", c, "settlement, maturity, frequency, [basis]", "Returns days from the start of the coupon period to settlement.", "Restituisce i giorni dall'inizio del periodo della cedola al regolamento."),
            f("COUPDAYS", c, "settlement, maturity, frequency, [basis]", "Returns the number of days in the coupon period containing settlement.", "Restituisce i giorni del periodo della cedola che contiene il regolamento."),
            f("COUPDAYSNC", c, "settlement, maturity, frequency, [basis]", "Returns days from settlement to the next coupon date.", "Restituisce i giorni dal regolamento alla data della cedola successiva."),
            f("COUPNCD", c, "settlement, maturity, frequency, [basis]", "Returns the next coupon date after settlement.", "Restituisce la data della cedola successiva al regolamento."),
            f("COUPNUM", c, "settlement, maturity, frequency, [basis]", "Returns the number of coupons payable between settlement and maturity.", "Restituisce il numero di cedole pagabili tra regolamento e scadenza."),
            f("COUPPCD", c, "settlement, maturity, frequency, [basis]", "Returns the previous coupon date before settlement.", "Restituisce la data della cedola precedente al regolamento."),
        ]
        return r
    }

    // MARK: - Engineering

    private static func engineering() -> [FunctionDoc] {
        let c: String = "Engineering"
        let r: [FunctionDoc] = [
            f("BESSELI", c, "x, n", "Returns the modified Bessel function In(x).", "Restituisce la funzione di Bessel modificata In(x)."),
            f("BESSELJ", c, "x, n", "Returns the Bessel function Jn(x).", "Restituisce la funzione di Bessel Jn(x)."),
            f("BESSELK", c, "x, n", "Returns the modified Bessel function Kn(x).", "Restituisce la funzione di Bessel modificata Kn(x)."),
            f("BESSELY", c, "x, n", "Returns the Bessel function Yn(x).", "Restituisce la funzione di Bessel Yn(x)."),
            f("ERF", c, "lower_limit, [upper_limit]", "Returns the error function.", "Restituisce la funzione di errore."),
            f("ERF.PRECISE", c, "x", "Returns the error function integrated from 0 to x.", "Restituisce la funzione di errore integrata tra 0 e x."),
            f("ERFC", c, "x", "Returns the complementary error function.", "Restituisce la funzione di errore complementare."),
            f("ERFC.PRECISE", c, "x", "Returns the complementary error function integrated from x to infinity.", "Restituisce la funzione di errore complementare integrata tra x e infinito."),
            f("BIN2DEC", c, "number", "Converts a binary number to decimal.", "Converte un numero binario in decimale."),
            f("BIN2HEX", c, "number, [places]", "Converts a binary number to hexadecimal.", "Converte un numero binario in esadecimale."),
            f("BIN2OCT", c, "number, [places]", "Converts a binary number to octal.", "Converte un numero binario in ottale."),
            f("DEC2BIN", c, "number, [places]", "Converts a decimal number to binary.", "Converte un numero decimale in binario."),
            f("DEC2HEX", c, "number, [places]", "Converts a decimal number to hexadecimal.", "Converte un numero decimale in esadecimale."),
            f("DEC2OCT", c, "number, [places]", "Converts a decimal number to octal.", "Converte un numero decimale in ottale."),
            f("HEX2BIN", c, "number, [places]", "Converts a hexadecimal number to binary.", "Converte un numero esadecimale in binario."),
            f("HEX2DEC", c, "number", "Converts a hexadecimal number to decimal.", "Converte un numero esadecimale in decimale."),
            f("HEX2OCT", c, "number, [places]", "Converts a hexadecimal number to octal.", "Converte un numero esadecimale in ottale."),
            f("OCT2BIN", c, "number, [places]", "Converts an octal number to binary.", "Converte un numero ottale in binario."),
            f("OCT2DEC", c, "number", "Converts an octal number to decimal.", "Converte un numero ottale in decimale."),
            f("OCT2HEX", c, "number, [places]", "Converts an octal number to hexadecimal.", "Converte un numero ottale in esadecimale."),
            f("BITAND", c, "number1, number2", "Returns the bitwise AND of two numbers.", "Restituisce l'AND bit a bit di due numeri."),
            f("BITLSHIFT", c, "number, shift_amount", "Returns a number shifted left by the given bits.", "Restituisce un numero spostato a sinistra dei bit indicati."),
            f("BITOR", c, "number1, number2", "Returns the bitwise OR of two numbers.", "Restituisce l'OR bit a bit di due numeri."),
            f("BITRSHIFT", c, "number, shift_amount", "Returns a number shifted right by the given bits.", "Restituisce un numero spostato a destra dei bit indicati."),
            f("BITXOR", c, "number1, number2", "Returns the bitwise XOR of two numbers.", "Restituisce lo XOR bit a bit di due numeri."),
            f("COMPLEX", c, "real_num, i_num, [suffix]", "Converts real and imaginary coefficients into a complex number.", "Converte coefficienti reale e immaginario in un numero complesso."),
            f("IMABS", c, "inumber", "Returns the absolute value (modulus) of a complex number.", "Restituisce il valore assoluto (modulo) di un numero complesso."),
            f("IMAGINARY", c, "inumber", "Returns the imaginary coefficient of a complex number.", "Restituisce il coefficiente immaginario di un numero complesso."),
            f("IMARGUMENT", c, "inumber", "Returns the argument theta of a complex number, in radians.", "Restituisce l'argomento theta di un numero complesso, in radianti."),
            f("IMCONJUGATE", c, "inumber", "Returns the complex conjugate of a complex number.", "Restituisce il coniugato di un numero complesso."),
            f("IMCOS", c, "inumber", "Returns the cosine of a complex number.", "Restituisce il coseno di un numero complesso."),
            f("IMCOSH", c, "inumber", "Returns the hyperbolic cosine of a complex number.", "Restituisce il coseno iperbolico di un numero complesso."),
            f("IMCOT", c, "inumber", "Returns the cotangent of a complex number.", "Restituisce la cotangente di un numero complesso."),
            f("IMCSC", c, "inumber", "Returns the cosecant of a complex number.", "Restituisce la cosecante di un numero complesso."),
            f("IMCSCH", c, "inumber", "Returns the hyperbolic cosecant of a complex number.", "Restituisce la cosecante iperbolica di un numero complesso."),
            f("IMDIV", c, "inumber1, inumber2", "Returns the quotient of two complex numbers.", "Restituisce il quoziente di due numeri complessi."),
            f("IMEXP", c, "inumber", "Returns the exponential of a complex number.", "Restituisce l'esponenziale di un numero complesso."),
            f("IMLN", c, "inumber", "Returns the natural logarithm of a complex number.", "Restituisce il logaritmo naturale di un numero complesso."),
            f("IMLOG10", c, "inumber", "Returns the base-10 logarithm of a complex number.", "Restituisce il logaritmo in base 10 di un numero complesso."),
            f("IMLOG2", c, "inumber", "Returns the base-2 logarithm of a complex number.", "Restituisce il logaritmo in base 2 di un numero complesso."),
            f("IMPOWER", c, "inumber, number", "Returns a complex number raised to a power.", "Restituisce un numero complesso elevato a una potenza."),
            f("IMPRODUCT", c, "inumber1, [inumber2], ...", "Returns the product of complex numbers.", "Restituisce il prodotto di numeri complessi."),
            f("IMREAL", c, "inumber", "Returns the real coefficient of a complex number.", "Restituisce il coefficiente reale di un numero complesso."),
            f("IMSEC", c, "inumber", "Returns the secant of a complex number.", "Restituisce la secante di un numero complesso."),
            f("IMSECH", c, "inumber", "Returns the hyperbolic secant of a complex number.", "Restituisce la secante iperbolica di un numero complesso."),
            f("IMSIN", c, "inumber", "Returns the sine of a complex number.", "Restituisce il seno di un numero complesso."),
            f("IMSINH", c, "inumber", "Returns the hyperbolic sine of a complex number.", "Restituisce il seno iperbolico di un numero complesso."),
            f("IMSQRT", c, "inumber", "Returns the square root of a complex number.", "Restituisce la radice quadrata di un numero complesso."),
            f("IMSUB", c, "inumber1, inumber2", "Returns the difference of two complex numbers.", "Restituisce la differenza di due numeri complessi."),
            f("IMSUM", c, "inumber1, [inumber2], ...", "Returns the sum of complex numbers.", "Restituisce la somma di numeri complessi."),
            f("IMTAN", c, "inumber", "Returns the tangent of a complex number.", "Restituisce la tangente di un numero complesso."),
            f("CONVERT", c, "number, from_unit, to_unit", "Converts a number from one measurement unit to another.", "Converte un numero da un'unità di misura a un'altra."),
            f("DELTA", c, "number1, [number2]", "Tests whether two values are equal (returns 1 or 0).", "Verifica se due valori sono uguali (restituisce 1 o 0)."),
            f("GESTEP", c, "number, [step]", "Tests whether a number is greater than or equal to a threshold.", "Verifica se un numero è maggiore o uguale a una soglia."),
        ]
        return r
    }

    // MARK: - Database

    private static func database() -> [FunctionDoc] {
        let c: String = "Database"
        let a: String = "database, field, criteria"
        let r: [FunctionDoc] = [
            f("DAVERAGE", c, a, "Averages the values in a database column that match criteria.", "Calcola la media dei valori di una colonna di database che soddisfano i criteri."),
            f("DCOUNT", c, a, "Counts the cells containing numbers in a database that match criteria.", "Conta le celle numeriche di un database che soddisfano i criteri."),
            f("DCOUNTA", c, a, "Counts the nonblank cells in a database that match criteria.", "Conta le celle non vuote di un database che soddisfano i criteri."),
            f("DGET", c, a, "Extracts the single record from a database that matches criteria.", "Estrae il singolo record di un database che soddisfa i criteri."),
            f("DMAX", c, a, "Returns the maximum value from database entries that match criteria.", "Restituisce il valore massimo dei record di database che soddisfano i criteri."),
            f("DMIN", c, a, "Returns the minimum value from database entries that match criteria.", "Restituisce il valore minimo dei record di database che soddisfano i criteri."),
            f("DPRODUCT", c, a, "Multiplies the values in a database column that match criteria.", "Moltiplica i valori di una colonna di database che soddisfano i criteri."),
            f("DSUM", c, a, "Adds the values in a database column that match criteria.", "Somma i valori di una colonna di database che soddisfano i criteri."),
            f("DSTDEV", c, a, "Estimates standard deviation from a sample of database entries.", "Stima la deviazione standard da un campione di record di database."),
            f("DSTDEVP", c, a, "Calculates standard deviation of the entire database population.", "Calcola la deviazione standard dell'intera popolazione del database."),
            f("DVAR", c, a, "Estimates variance from a sample of database entries.", "Stima la varianza da un campione di record di database."),
            f("DVARP", c, a, "Calculates variance of the entire database population.", "Calcola la varianza dell'intera popolazione del database."),
        ]
        return r
    }

    // MARK: - Statistical

    private static func statistical() -> [FunctionDoc] {
        let c: String = "Statistical"
        let r: [FunctionDoc] = [
            f("MAX", c, "number1, [number2], ...", "Returns the largest value in a set of values.", "Restituisce il valore più grande di un insieme di valori."),
            f("MIN", c, "number1, [number2], ...", "Returns the smallest value in a set of values.", "Restituisce il valore più piccolo di un insieme di valori."),
            f("MAXA", c, "value1, [value2], ...", "Returns the largest value, including text and logical values.", "Restituisce il valore più grande, inclusi testo e valori logici."),
            f("MINA", c, "value1, [value2], ...", "Returns the smallest value, including text and logical values.", "Restituisce il valore più piccolo, inclusi testo e valori logici."),
            f("AVERAGE", c, "number1, [number2], ...", "Returns the arithmetic mean of its arguments.", "Restituisce la media aritmetica degli argomenti."),
            f("AVERAGEA", c, "value1, [value2], ...", "Returns the average, including text and logical values.", "Restituisce la media, inclusi testo e valori logici."),
            f("AVEDEV", c, "number1, [number2], ...", "Returns the average of absolute deviations from the mean.", "Restituisce la media degli scarti assoluti dalla media."),
            f("AVERAGEIF", c, "range, criteria, [average_range]", "Returns the average of the cells that meet a criterion.", "Restituisce la media delle celle che soddisfano un criterio."),
            f("AVERAGEIFS", c, "average_range, criteria_range1, criteria1, [criteria_range2], [criteria2], ...", "Returns the average of the cells that meet multiple criteria.", "Restituisce la media delle celle che soddisfano più criteri."),
            f("COUNT", c, "value1, [value2], ...", "Counts the cells that contain numbers.", "Conta le celle che contengono numeri."),
            f("COUNTA", c, "value1, [value2], ...", "Counts the cells that are not empty.", "Conta le celle non vuote."),
            f("COUNTBLANK", c, "range", "Counts the empty cells in a range.", "Conta le celle vuote in un intervallo."),
            f("COUNTIF", c, "range, criteria", "Counts the cells that meet a criterion.", "Conta le celle che soddisfano un criterio."),
            f("COUNTIFS", c, "criteria_range1, criteria1, [criteria_range2], [criteria2], ...", "Counts the cells that meet multiple criteria.", "Conta le celle che soddisfano più criteri."),
            f("MAXIFS", c, "max_range, criteria_range1, criteria1, [criteria_range2], [criteria2], ...", "Returns the maximum among cells that meet multiple criteria.", "Restituisce il massimo tra le celle che soddisfano più criteri."),
            f("MINIFS", c, "min_range, criteria_range1, criteria1, [criteria_range2], [criteria2], ...", "Returns the minimum among cells that meet multiple criteria.", "Restituisce il minimo tra le celle che soddisfano più criteri."),
            f("GEOMEAN", c, "number1, [number2], ...", "Returns the geometric mean.", "Restituisce la media geometrica."),
            f("HARMEAN", c, "number1, [number2], ...", "Returns the harmonic mean.", "Restituisce la media armonica."),
            f("MEDIAN", c, "number1, [number2], ...", "Returns the median of the given numbers.", "Restituisce la mediana dei numeri indicati."),
            f("MODE.SNGL", c, "number1, [number2], ...", "Returns the most frequently occurring value.", "Restituisce il valore più frequente."),
            f("MODE.MULT", c, "number1, [number2], ...", "Returns a vertical array of the most frequent values.", "Restituisce una matrice verticale dei valori più frequenti."),
            f("TRIMMEAN", c, "array, percent", "Returns the mean of the interior of a data set.", "Restituisce la media della parte interna di un insieme di dati."),
            f("LARGE", c, "array, k", "Returns the k-th largest value in a data set.", "Restituisce il k-esimo valore più grande di un insieme di dati."),
            f("SMALL", c, "array, k", "Returns the k-th smallest value in a data set.", "Restituisce il k-esimo valore più piccolo di un insieme di dati."),
            f("RANK.EQ", c, "number, ref, [order]", "Returns the rank of a number in a list (ties get the top rank).", "Restituisce il rango di un numero in un elenco (a parità, il rango più alto)."),
            f("RANK.AVG", c, "number, ref, [order]", "Returns the rank of a number in a list (ties get the average rank).", "Restituisce il rango di un numero in un elenco (a parità, il rango medio)."),
            f("PERCENTILE.INC", c, "array, k", "Returns the k-th percentile, k in 0..1 inclusive.", "Restituisce il k-esimo percentile, con k tra 0 e 1 inclusi."),
            f("PERCENTILE.EXC", c, "array, k", "Returns the k-th percentile, k in 0..1 exclusive.", "Restituisce il k-esimo percentile, con k tra 0 e 1 esclusi."),
            f("PERCENTRANK.INC", c, "array, x, [significance]", "Returns the percentage rank of a value (0..1 inclusive).", "Restituisce il rango percentuale di un valore (0..1 inclusi)."),
            f("PERCENTRANK.EXC", c, "array, x, [significance]", "Returns the percentage rank of a value (0..1 exclusive).", "Restituisce il rango percentuale di un valore (0..1 esclusi)."),
            f("QUARTILE.INC", c, "array, quart", "Returns the quartile of a data set (0..1 inclusive).", "Restituisce il quartile di un insieme di dati (0..1 inclusi)."),
            f("QUARTILE.EXC", c, "array, quart", "Returns the quartile of a data set (0..1 exclusive).", "Restituisce il quartile di un insieme di dati (0..1 esclusi)."),
            f("STDEV.S", c, "number1, [number2], ...", "Estimates standard deviation based on a sample.", "Stima la deviazione standard sulla base di un campione."),
            f("STDEV.P", c, "number1, [number2], ...", "Calculates standard deviation based on the entire population.", "Calcola la deviazione standard sull'intera popolazione."),
            f("STDEVA", c, "value1, [value2], ...", "Estimates standard deviation of a sample, including text and logicals.", "Stima la deviazione standard di un campione, inclusi testo e valori logici."),
            f("STDEVPA", c, "value1, [value2], ...", "Calculates population standard deviation, including text and logicals.", "Calcola la deviazione standard della popolazione, inclusi testo e logici."),
            f("VAR.S", c, "number1, [number2], ...", "Estimates variance based on a sample.", "Stima la varianza sulla base di un campione."),
            f("VAR.P", c, "number1, [number2], ...", "Calculates variance based on the entire population.", "Calcola la varianza sull'intera popolazione."),
            f("VARA", c, "value1, [value2], ...", "Estimates variance of a sample, including text and logical values.", "Stima la varianza di un campione, inclusi testo e valori logici."),
            f("VARPA", c, "value1, [value2], ...", "Calculates population variance, including text and logical values.", "Calcola la varianza della popolazione, inclusi testo e valori logici."),
            f("DEVSQ", c, "number1, [number2], ...", "Returns the sum of squares of deviations from the mean.", "Restituisce la somma dei quadrati degli scarti dalla media."),
            f("KURT", c, "number1, [number2], ...", "Returns the kurtosis of a data set.", "Restituisce la curtosi di un insieme di dati."),
            f("SKEW", c, "number1, [number2], ...", "Returns the skewness of a distribution.", "Restituisce l'asimmetria di una distribuzione."),
            f("SKEW.P", c, "number1, [number2], ...", "Returns the skewness of a distribution based on a population.", "Restituisce l'asimmetria di una distribuzione basata su una popolazione."),
            f("STANDARDIZE", c, "x, mean, standard_dev", "Returns a normalized value.", "Restituisce un valore normalizzato."),
            f("CORREL", c, "array1, array2", "Returns the correlation coefficient between two data sets.", "Restituisce il coefficiente di correlazione tra due insiemi di dati."),
            f("PEARSON", c, "array1, array2", "Returns the Pearson product moment correlation coefficient.", "Restituisce il coefficiente di correlazione di Pearson."),
            f("RSQ", c, "known_y's, known_x's", "Returns the square of the Pearson correlation coefficient.", "Restituisce il quadrato del coefficiente di correlazione di Pearson."),
            f("COVARIANCE.P", c, "array1, array2", "Returns the population covariance.", "Restituisce la covarianza della popolazione."),
            f("COVARIANCE.S", c, "array1, array2", "Returns the sample covariance.", "Restituisce la covarianza del campione."),
            f("INTERCEPT", c, "known_y's, known_x's", "Returns the intercept of the linear regression line.", "Restituisce l'intercetta della retta di regressione lineare."),
            f("SLOPE", c, "known_y's, known_x's", "Returns the slope of the linear regression line.", "Restituisce la pendenza della retta di regressione lineare."),
            f("STEYX", c, "known_y's, known_x's", "Returns the standard error of the predicted y for each x.", "Restituisce l'errore standard della y prevista per ogni x."),
            f("FORECAST", c, "x, known_y's, known_x's", "Predicts a value along a linear trend.", "Prevede un valore lungo una tendenza lineare."),
            f("FORECAST.LINEAR", c, "x, known_y's, known_x's", "Predicts a value along a linear trend.", "Prevede un valore lungo una tendenza lineare."),
            f("FORECAST.ETS", c, "target_date, values, timeline, [seasonality], [data_completion], [aggregation]", "Forecasts a value using exponential triple smoothing (ETS).", "Prevede un valore con livellamento esponenziale triplo (ETS)."),
            f("FORECAST.ETS.CONFINT", c, "target_date, values, timeline, [confidence_level], [seasonality], [data_completion], [aggregation]", "Returns a confidence interval for an ETS forecast value.", "Restituisce un intervallo di confidenza per un valore previsto con ETS."),
            f("FORECAST.ETS.SEASONALITY", c, "values, timeline, [data_completion], [aggregation]", "Returns the length of the seasonal pattern detected by ETS.", "Restituisce la lunghezza del ciclo stagionale rilevato da ETS."),
            f("FORECAST.ETS.STAT", c, "values, timeline, statistic_type, [seasonality], [data_completion], [aggregation]", "Returns a statistic of an ETS forecast.", "Restituisce una statistica di una previsione ETS."),
            f("TREND", c, "known_y's, [known_x's], [new_x's], [const]", "Returns values along a linear trend.", "Restituisce valori lungo una tendenza lineare."),
            f("GROWTH", c, "known_y's, [known_x's], [new_x's], [const]", "Returns values along an exponential trend.", "Restituisce valori lungo una tendenza esponenziale."),
            f("LINEST", c, "known_y's, [known_x's], [const], [stats]", "Returns the parameters of a linear trend.", "Restituisce i parametri di una tendenza lineare."),
            f("LOGEST", c, "known_y's, [known_x's], [const], [stats]", "Returns the parameters of an exponential trend.", "Restituisce i parametri di una tendenza esponenziale."),
            f("FREQUENCY", c, "data_array, bins_array", "Returns a frequency distribution as a vertical array.", "Restituisce una distribuzione di frequenza come matrice verticale."),
            f("PERMUT", c, "number, number_chosen", "Returns the number of permutations for a number of objects.", "Restituisce il numero di permutazioni per un dato numero di oggetti."),
            f("PERMUTATIONA", c, "number, number_chosen", "Returns the number of permutations with repetitions.", "Restituisce il numero di permutazioni con ripetizioni."),
            f("PROB", c, "x_range, prob_range, [lower_limit], [upper_limit]", "Returns the probability that values fall between two limits.", "Restituisce la probabilità che i valori siano compresi tra due limiti."),
            f("FISHER", c, "x", "Returns the Fisher transformation.", "Restituisce la trasformazione di Fisher."),
            f("FISHERINV", c, "y", "Returns the inverse of the Fisher transformation.", "Restituisce l'inversa della trasformazione di Fisher."),
            f("GAMMA", c, "x", "Returns the Gamma function value.", "Restituisce il valore della funzione Gamma."),
            f("GAMMALN", c, "x", "Returns the natural logarithm of the Gamma function.", "Restituisce il logaritmo naturale della funzione Gamma."),
            f("GAMMALN.PRECISE", c, "x", "Returns the natural logarithm of the Gamma function.", "Restituisce il logaritmo naturale della funzione Gamma."),
            f("GAUSS", c, "z", "Returns 0.5 less than the standard normal cumulative distribution.", "Restituisce la distribuzione normale standard cumulativa meno 0,5."),
            f("PHI", c, "x", "Returns the density of the standard normal distribution.", "Restituisce la densità della distribuzione normale standard."),
        ]
        return r
    }

    private static func statisticalDistributions() -> [FunctionDoc] {
        let c: String = "Statistical"
        let r: [FunctionDoc] = [
            f("BETA.DIST", c, "x, alpha, beta, cumulative, [A], [B]", "Returns the beta distribution.", "Restituisce la distribuzione beta."),
            f("BETA.INV", c, "probability, alpha, beta, [A], [B]", "Returns the inverse of the cumulative beta distribution.", "Restituisce l'inversa della distribuzione beta cumulativa."),
            f("BINOM.DIST", c, "number_s, trials, probability_s, cumulative", "Returns the binomial distribution probability.", "Restituisce la probabilità della distribuzione binomiale."),
            f("BINOM.DIST.RANGE", c, "trials, probability_s, number_s, [number_s2]", "Returns the probability of a trial result range (binomial).", "Restituisce la probabilità di un intervallo di successi (binomiale)."),
            f("BINOM.INV", c, "trials, probability_s, alpha", "Returns the smallest value whose binomial CDF is >= alpha.", "Restituisce il valore minimo la cui binomiale cumulativa è >= alfa."),
            f("CHISQ.DIST", c, "x, deg_freedom, cumulative", "Returns the left-tailed chi-squared distribution.", "Restituisce la distribuzione chi quadrato a una coda sinistra."),
            f("CHISQ.DIST.RT", c, "x, deg_freedom", "Returns the right-tailed chi-squared distribution.", "Restituisce la distribuzione chi quadrato a una coda destra."),
            f("CHISQ.INV", c, "probability, deg_freedom", "Returns the inverse of the left-tailed chi-squared distribution.", "Restituisce l'inversa della distribuzione chi quadrato a coda sinistra."),
            f("CHISQ.INV.RT", c, "probability, deg_freedom", "Returns the inverse of the right-tailed chi-squared distribution.", "Restituisce l'inversa della distribuzione chi quadrato a coda destra."),
            f("CHISQ.TEST", c, "actual_range, expected_range", "Returns the chi-squared test for independence.", "Restituisce il test chi quadrato di indipendenza."),
            f("CONFIDENCE.NORM", c, "alpha, standard_dev, size", "Returns the confidence interval for a mean (normal distribution).", "Restituisce l'intervallo di confidenza di una media (distribuzione normale)."),
            f("CONFIDENCE.T", c, "alpha, standard_dev, size", "Returns the confidence interval for a mean (Student's t).", "Restituisce l'intervallo di confidenza di una media (t di Student)."),
            f("EXPON.DIST", c, "x, lambda, cumulative", "Returns the exponential distribution.", "Restituisce la distribuzione esponenziale."),
            f("F.DIST", c, "x, deg_freedom1, deg_freedom2, cumulative", "Returns the left-tailed F probability distribution.", "Restituisce la distribuzione di probabilità F a coda sinistra."),
            f("F.DIST.RT", c, "x, deg_freedom1, deg_freedom2", "Returns the right-tailed F probability distribution.", "Restituisce la distribuzione di probabilità F a coda destra."),
            f("F.INV", c, "probability, deg_freedom1, deg_freedom2", "Returns the inverse of the left-tailed F distribution.", "Restituisce l'inversa della distribuzione F a coda sinistra."),
            f("F.INV.RT", c, "probability, deg_freedom1, deg_freedom2", "Returns the inverse of the right-tailed F distribution.", "Restituisce l'inversa della distribuzione F a coda destra."),
            f("F.TEST", c, "array1, array2", "Returns the result of an F-test.", "Restituisce il risultato di un test F."),
            f("GAMMA.DIST", c, "x, alpha, beta, cumulative", "Returns the gamma distribution.", "Restituisce la distribuzione gamma."),
            f("GAMMA.INV", c, "probability, alpha, beta", "Returns the inverse of the gamma cumulative distribution.", "Restituisce l'inversa della distribuzione gamma cumulativa."),
            f("HYPGEOM.DIST", c, "sample_s, number_sample, population_s, number_pop, cumulative", "Returns the hypergeometric distribution.", "Restituisce la distribuzione ipergeometrica."),
            f("LOGNORM.DIST", c, "x, mean, standard_dev, cumulative", "Returns the lognormal distribution.", "Restituisce la distribuzione lognormale."),
            f("LOGNORM.INV", c, "probability, mean, standard_dev", "Returns the inverse of the lognormal cumulative distribution.", "Restituisce l'inversa della distribuzione lognormale cumulativa."),
            f("NEGBINOM.DIST", c, "number_f, number_s, probability_s, cumulative", "Returns the negative binomial distribution.", "Restituisce la distribuzione binomiale negativa."),
            f("NORM.DIST", c, "x, mean, standard_dev, cumulative", "Returns the normal distribution.", "Restituisce la distribuzione normale."),
            f("NORM.INV", c, "probability, mean, standard_dev", "Returns the inverse of the normal cumulative distribution.", "Restituisce l'inversa della distribuzione normale cumulativa."),
            f("NORM.S.DIST", c, "z, cumulative", "Returns the standard normal distribution.", "Restituisce la distribuzione normale standard."),
            f("NORM.S.INV", c, "probability", "Returns the inverse of the standard normal cumulative distribution.", "Restituisce l'inversa della distribuzione normale standard cumulativa."),
            f("POISSON.DIST", c, "x, mean, cumulative", "Returns the Poisson distribution.", "Restituisce la distribuzione di Poisson."),
            f("T.DIST", c, "x, deg_freedom, cumulative", "Returns the left-tailed Student's t-distribution.", "Restituisce la distribuzione t di Student a coda sinistra."),
            f("T.DIST.2T", c, "x, deg_freedom", "Returns the two-tailed Student's t-distribution.", "Restituisce la distribuzione t di Student a due code."),
            f("T.DIST.RT", c, "x, deg_freedom", "Returns the right-tailed Student's t-distribution.", "Restituisce la distribuzione t di Student a coda destra."),
            f("T.INV", c, "probability, deg_freedom", "Returns the left-tailed inverse of the Student's t-distribution.", "Restituisce l'inversa a coda sinistra della distribuzione t di Student."),
            f("T.INV.2T", c, "probability, deg_freedom", "Returns the two-tailed inverse of the Student's t-distribution.", "Restituisce l'inversa a due code della distribuzione t di Student."),
            f("T.TEST", c, "array1, array2, tails, type", "Returns the probability associated with a Student's t-test.", "Restituisce la probabilità associata a un test t di Student."),
            f("WEIBULL.DIST", c, "x, alpha, beta, cumulative", "Returns the Weibull distribution.", "Restituisce la distribuzione di Weibull."),
            f("Z.TEST", c, "array, x, [sigma]", "Returns the one-tailed P-value of a z-test.", "Restituisce il valore P a una coda di un test z."),
        ]
        return r
    }

    /// Legacy (Excel 2007) statistical names kept for compatibility.
    private static func statisticalCompat() -> [FunctionDoc] {
        let c: String = "Statistical"
        let r: [FunctionDoc] = [
            f("STDEV", c, "number1, [number2], ...", "Estimates standard deviation based on a sample.", "Stima la deviazione standard sulla base di un campione."),
            f("STDEVP", c, "number1, [number2], ...", "Calculates standard deviation based on the entire population.", "Calcola la deviazione standard sull'intera popolazione."),
            f("VAR", c, "number1, [number2], ...", "Estimates variance based on a sample.", "Stima la varianza sulla base di un campione."),
            f("VARP", c, "number1, [number2], ...", "Calculates variance based on the entire population.", "Calcola la varianza sull'intera popolazione."),
            f("MODE", c, "number1, [number2], ...", "Returns the most frequently occurring value.", "Restituisce il valore più frequente."),
            f("RANK", c, "number, ref, [order]", "Returns the rank of a number in a list of numbers.", "Restituisce il rango di un numero in un elenco di numeri."),
            f("PERCENTILE", c, "array, k", "Returns the k-th percentile of values in a range.", "Restituisce il k-esimo percentile dei valori di un intervallo."),
            f("PERCENTRANK", c, "array, x, [significance]", "Returns the percentage rank of a value in a data set.", "Restituisce il rango percentuale di un valore in un insieme di dati."),
            f("QUARTILE", c, "array, quart", "Returns the quartile of a data set.", "Restituisce il quartile di un insieme di dati."),
            f("COVAR", c, "array1, array2", "Returns the covariance (population).", "Restituisce la covarianza (popolazione)."),
            f("CONFIDENCE", c, "alpha, standard_dev, size", "Returns the confidence interval for a population mean.", "Restituisce l'intervallo di confidenza per la media di una popolazione."),
            f("CHIDIST", c, "x, deg_freedom", "Returns the right-tailed chi-squared distribution.", "Restituisce la distribuzione chi quadrato a una coda destra."),
            f("CHIINV", c, "probability, deg_freedom", "Returns the inverse of the right-tailed chi-squared distribution.", "Restituisce l'inversa della distribuzione chi quadrato a coda destra."),
            f("CHITEST", c, "actual_range, expected_range", "Returns the chi-squared test for independence.", "Restituisce il test chi quadrato di indipendenza."),
            f("CRITBINOM", c, "trials, probability_s, alpha", "Returns the smallest value whose binomial CDF is >= alpha.", "Restituisce il valore minimo la cui binomiale cumulativa è >= alfa."),
            f("BETADIST", c, "x, alpha, beta, [A], [B]", "Returns the cumulative beta distribution.", "Restituisce la distribuzione beta cumulativa."),
            f("BETAINV", c, "probability, alpha, beta, [A], [B]", "Returns the inverse of the cumulative beta distribution.", "Restituisce l'inversa della distribuzione beta cumulativa."),
            f("BINOMDIST", c, "number_s, trials, probability_s, cumulative", "Returns the binomial distribution probability.", "Restituisce la probabilità della distribuzione binomiale."),
            f("EXPONDIST", c, "x, lambda, cumulative", "Returns the exponential distribution.", "Restituisce la distribuzione esponenziale."),
            f("FDIST", c, "x, deg_freedom1, deg_freedom2", "Returns the right-tailed F probability distribution.", "Restituisce la distribuzione di probabilità F a coda destra."),
            f("FINV", c, "probability, deg_freedom1, deg_freedom2", "Returns the inverse of the right-tailed F distribution.", "Restituisce l'inversa della distribuzione F a coda destra."),
            f("FTEST", c, "array1, array2", "Returns the result of an F-test.", "Restituisce il risultato di un test F."),
            f("GAMMADIST", c, "x, alpha, beta, cumulative", "Returns the gamma distribution.", "Restituisce la distribuzione gamma."),
            f("GAMMAINV", c, "probability, alpha, beta", "Returns the inverse of the gamma cumulative distribution.", "Restituisce l'inversa della distribuzione gamma cumulativa."),
            f("HYPGEOMDIST", c, "sample_s, number_sample, population_s, number_pop", "Returns the hypergeometric distribution.", "Restituisce la distribuzione ipergeometrica."),
            f("LOGINV", c, "probability, mean, standard_dev", "Returns the inverse of the lognormal cumulative distribution.", "Restituisce l'inversa della distribuzione lognormale cumulativa."),
            f("LOGNORMDIST", c, "x, mean, standard_dev", "Returns the cumulative lognormal distribution.", "Restituisce la distribuzione lognormale cumulativa."),
            f("NEGBINOMDIST", c, "number_f, number_s, probability_s", "Returns the negative binomial distribution.", "Restituisce la distribuzione binomiale negativa."),
            f("NORMDIST", c, "x, mean, standard_dev, cumulative", "Returns the normal distribution.", "Restituisce la distribuzione normale."),
            f("NORMINV", c, "probability, mean, standard_dev", "Returns the inverse of the normal cumulative distribution.", "Restituisce l'inversa della distribuzione normale cumulativa."),
            f("NORMSDIST", c, "z", "Returns the standard normal cumulative distribution.", "Restituisce la distribuzione normale standard cumulativa."),
            f("NORMSINV", c, "probability", "Returns the inverse of the standard normal cumulative distribution.", "Restituisce l'inversa della distribuzione normale standard cumulativa."),
            f("POISSON", c, "x, mean, cumulative", "Returns the Poisson distribution.", "Restituisce la distribuzione di Poisson."),
            f("TDIST", c, "x, deg_freedom, tails", "Returns the Student's t-distribution.", "Restituisce la distribuzione t di Student."),
            f("TINV", c, "probability, deg_freedom", "Returns the two-tailed inverse of the Student's t-distribution.", "Restituisce l'inversa a due code della distribuzione t di Student."),
            f("TTEST", c, "array1, array2, tails, type", "Returns the probability associated with a Student's t-test.", "Restituisce la probabilità associata a un test t di Student."),
            f("WEIBULL", c, "x, alpha, beta, cumulative", "Returns the Weibull distribution.", "Restituisce la distribuzione di Weibull."),
            f("ZTEST", c, "array, x, [sigma]", "Returns the one-tailed P-value of a z-test.", "Restituisce il valore P a una coda di un test z."),
        ]
        return r
    }
}
