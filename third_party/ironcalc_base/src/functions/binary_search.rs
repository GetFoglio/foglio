use std::cmp::Ordering;

#[cfg(test)]
use crate::calc_result::CalcResult;

#[cfg(test)]
use super::util::compare_values;

// NOTE: We don't know how Excel exactly implements binary search internally.
// This means that if the values on the lookup range are not in order our results and Excel's will differ

// Assumes values are in ascending order, returns matching index or the largest value smaller than target.
// Returns None if target is smaller than the smaller value.
pub(crate) fn binary_search_or_smaller<T: Ord>(target: &T, array: &[T]) -> Option<i32> {
    // We apply binary search leftmost for value in the range
    let n = array.len();
    let mut l = 0;
    let mut r = n;
    while l < r {
        let m = (l + r) / 2;
        if &array[m] < target {
            l = m + 1;
        } else {
            r = m;
        }
    }
    if l == n {
        return Some((l - 1) as i32);
    }
    // Now l points to the leftmost element
    if &array[l] == target {
        return Some(l as i32);
    }
    // If target is less than the minimum return None
    if l == 0 {
        return None;
    }
    Some((l - 1) as i32)
}

// Assumes values are in ascending order, returns matching index or the smaller value larger than target.
// Returns None if target is smaller than the smaller value.
pub(crate) fn binary_search_or_greater<T: Ord>(target: &T, array: &[T]) -> Option<i32> {
    let mut l = 0;
    let mut r = array.len();
    while l < r {
        let mut m = (l + r) / 2;
        match &array[m].cmp(target) {
            Ordering::Less => {
                l = m + 1;
            }
            Ordering::Greater => {
                r = m;
            }
            Ordering::Equal => {
                while m > 1 {
                    if &array[m - 1] == target {
                        m -= 1;
                    } else {
                        break;
                    }
                }
                return Some(m as i32);
            }
        }
    }
    // If target is larger than the maximum return None
    if r == array.len() {
        return None;
    }
    // Now r points to the rightmost element
    Some(r as i32)
}

// Assumes values are in descending order
pub(crate) fn binary_search_descending_or_smaller<T: Ord>(target: &T, array: &[T]) -> Option<i32> {
    let n = array.len();
    let mut l = 0;
    let mut r = n;
    while l < r {
        let m = (l + r) / 2;
        let mut index = n - m - 1;
        match &array[index].cmp(target) {
            Ordering::Less => {
                l = m + 1;
            }
            Ordering::Greater => {
                r = m;
            }
            Ordering::Equal => {
                while index < n - 1 {
                    if &array[index + 1] == target {
                        index += 1;
                    } else {
                        break;
                    }
                }
                return Some(index as i32);
            }
        }
    }
    if l == 0 {
        return None;
    }
    Some((n - l) as i32)
}

// Assumes values are in descending order, returns matching index or the smaller value larger than target.
// Returns None if target is smaller than the smaller value.
pub(crate) fn binary_search_descending_or_greater<T: Ord>(target: &T, array: &[T]) -> Option<i32> {
    let n = array.len();
    let mut l = 0;
    let mut r = n;
    while l < r {
        let m = (l + r) / 2;
        let mut index = n - m - 1;
        match &array[index].cmp(target) {
            Ordering::Less => {
                l = m + 1;
            }
            Ordering::Greater => {
                r = m;
            }
            Ordering::Equal => {
                while index < n - 1 {
                    if &array[index + 1] == target {
                        index += 1;
                    } else {
                        break;
                    }
                }
                return Some(index as i32);
            }
        }
    }
    if r == n {
        return None;
    }
    Some((n - r - 1) as i32)
}

// Foglio fork: `Model::prepare_array`, which read a vector cell by cell into
// a new vector on every call, is replaced by `Model::lookup_vector`
// (`lookup_cache.rs`): only the used part of the sheet, cached per pass.

/// Old style binary search over an already materialized vector of values.
/// Returns the index of the matching element or the largest element smaller
/// than `target`. Returns `-2` if `target` is smaller than every element.
/// Foglio fork: the lookups use `VectorData::binary_search`; this is the
/// reference its tests compare against.
#[cfg(test)]
pub(crate) fn binary_search_on_array(target: &CalcResult, array: &[CalcResult]) -> i32 {
    // We apply binary search leftmost for value in the array
    let mut l = 0;
    let mut r = array.len();
    while l < r {
        let m = (l + r) / 2;
        match compare_values(&array[m], target) {
            -1 => {
                l = m + 1;
            }
            1 => {
                r = m;
            }
            _ => {
                return m as i32;
            }
        }
    }
    // If target is less than the minimum return #N/A
    if l == 0 {
        return -2;
    }
    // Now l points to the leftmost element
    (l - 1) as i32
}
