// SPDX-License-Identifier: Apache-2.0
// Portions derived from getzep/graphiti.
// Upstream commit: 547422865cca9fb5a82915c074d899428c145ff4
// Copyright 2024, Zep Software, Inc.
// Translated and modified for MoonBit in 2026.

///|
fn in_graphiti_scalar_ranges(
  code : Int,
  ranges : FixedArray[(Int, Int)],
) -> Bool {
  let mut low = 0
  let mut high = ranges.length()
  while low < high {
    let middle = low + (high - low) / 2
    let (start, finish) = ranges[middle]
    if code < start {
      high = middle
    } else if code > finish {
      low = middle + 1
    } else {
      return true
    }
  }
  false
}

///|
fn graphiti_is_cased(code : Int) -> Bool {
  in_graphiti_scalar_ranges(code, graphiti_cased_ranges)
}

///|
fn graphiti_is_case_ignorable(code : Int) -> Bool {
  in_graphiti_scalar_ranges(code, graphiti_case_ignorable_ranges)
}

///|
fn graphiti_lower_scalar(code : Int) -> Int {
  let mut low = 0
  let mut high = graphiti_lower_runs.length()
  while low < high {
    let middle = low + (high - low) / 2
    let (start, finish, step, delta) = graphiti_lower_runs[middle]
    if code < start {
      high = middle
    } else if code > finish {
      low = middle + 1
    } else {
      return if (code - start) % step == 0 { code + delta } else { code }
    }
  }
  low = 0
  high = graphiti_lower_explicit.length()
  while low < high {
    let middle = low + (high - low) / 2
    let (source, target) = graphiti_lower_explicit[middle]
    if code < source {
      high = middle
    } else if code > source {
      low = middle + 1
    } else {
      return target
    }
  }
  code
}

///|
fn graphiti_following_cased(chars : Array[Char]) -> Array[Bool] {
  let result = Array::make(chars.length(), false)
  let mut next_non_ignorable_is_cased = false
  let mut index = chars.length() - 1
  while index >= 0 {
    result[index] = next_non_ignorable_is_cased
    let code = chars[index].to_int()
    if !graphiti_is_case_ignorable(code) {
      next_non_ignorable_is_cased = graphiti_is_cased(code)
    }
    index -= 1
  }
  result
}

///|
fn graphiti_python_whitespace(code : Int) -> Bool {
  in_graphiti_scalar_ranges(code, graphiti_whitespace_ranges)
}

///|
fn graphiti_write_scalar(output : StringBuilder, code : Int) -> Unit {
  match code.to_char() {
    Some(char) => output.write_char(char)
    None => abort("generated lowercase table contains an invalid scalar")
  }
}

///|
fn graphiti_normalize_statement(input : String) -> String {
  let chars = input.to_array()
  let following_cased = graphiti_following_cased(chars)
  let lowered = StringBuilder()
  let mut previous_non_ignorable_is_cased = false
  for index, char in chars {
    let code = char.to_int()
    if code == 0x0130 {
      lowered.write_char('i')
      lowered.write_char('\u{0307}')
    } else if code == 0x03a3 &&
      previous_non_ignorable_is_cased &&
      !following_cased[index] {
      lowered.write_char('\u{03c2}')
    } else {
      graphiti_write_scalar(lowered, graphiti_lower_scalar(code))
    }
    if !graphiti_is_case_ignorable(code) {
      previous_non_ignorable_is_cased = graphiti_is_cased(code)
    }
  }
  let normalized = StringBuilder()
  let mut emitted = false
  let mut pending_space = false
  for char in lowered.to_string() {
    if graphiti_python_whitespace(char.to_int()) {
      if emitted {
        pending_space = true
      }
    } else {
      if pending_space {
        normalized.write_char(' ')
        pending_space = false
      }
      normalized.write_char(char)
      emitted = true
    }
  }
  normalized.to_string()
}
