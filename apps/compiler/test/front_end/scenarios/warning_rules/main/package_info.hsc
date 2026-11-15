/**
 * Which warnings are shown (docs/compilation.md, Allowing and Denying Warnings): this package allows W2002 in itself,
 * and its import from std, where every warning is hidden, has a warning of its own.
 */
package warning_rules

ALLOWED_WARNINGS :: string.["hemera:W2002"]
