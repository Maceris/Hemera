package slop_os_result

/*
 * A program for SlopOS whose main gives back a Result rather than an exit code, built but not run here: the entry
 * hands it to the runtime, which writes it in the grant "result" (docs/compilation.md, Entry Results). The Result is
 * too large for registers, so it's given back through memory the entry makes, which has no function of its own to
 * make it in.
 */

/** What it gives back when it's fine. */
Summary :: struct {
    /** The count it was given. */
    count : u64,
    /** The label it was given. */
    label : string,
}

/** What it gives back as its error. */
SummaryError :: union {
    /** An error that holds nothing. */
    Plain,
    /** An error that says why, in words. */
    Refused(string),
}

/**
 * Give back a summary of what it was given, or an error for no count.
 *
 * @param count A number, given back in the summary.
 * @param label A word, given back in the summary.
 * @return A Summary of count and label.
 * @error Plain The count is 0.
 * @error Refused The label is empty.
 */
main :: fn(count: u64, label: string) -> Result[Summary, SummaryError] {
    if count == 0 {
        return .Error(.Plain)
    }
    if label.count == 0 {
        return .Error(.Refused("no label"))
    }
    return .Ok(Summary.{count = count, label = label})
}
