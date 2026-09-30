#ifndef HMIR_OPS
#define HMIR_OPS

include "hmir_dialect.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def HemeraEndOp : HemeraOp<"end", [Terminator, Pure]> {
    let summary = "Fall through at the end of a scope, defer body, or loop iteration";
    let assemblyFormat = "attr-dict";
}

def HemeraScopeOp : HemeraOp<"scope", [SingleBlock, NoRegionArguments]> {
    let summary = "A lexical block scope";
    let description = [{
        Runs the body once. Any defer's declared within the scope will
        execute once control leaves the body. This can happen at a `hmir.end`,
        `hmir.return`, `hmir.break`, or `hmir.continue` anywhere past the defer.

        ```mlir
        hmir.scope {
          hmir.defer {
            ...
            hmir.end
          }
          ...
          hmir.end
        }
        ```
    }];

    let regions = (region SizedRegion<1>:$bodyRegion);
    let assemblyFormat = "$bodyRegion attr-dict";
}

def HemeraLoopOp : HemeraOp<"loop", [SingleBlock, NoRegionArguments]> {
    let summary = "A loop, whose body is entered once per iteration";
    let description = [{
        A loop, where `hmir.end` or `hmir.continue` ends the current interation.
        `hmir.break` or `hmir.return` will leave the loop entirely.
    }];

    let regions = (region SizedRegion<1>:$bodyRegion);
    let assemblyFormat = "$bodyRegion attr-dict";
}

def HemeraDeferOp : HemeraOp<"defer", [SingleBlock, NoRegionArguments]> {
    
    let summary = "Defers an expression until control flow leaves the end of the enclosing scope";
    let description = [{
        The body is similar to a macro or template, that will be copied around
        in front of every exit in the enclosing block which follows the defer,
        and the defer op itself will be deleted. The body can refer to any
        value that dominates the defer. It cannot return/break/continue out of
        itself.

        ```mlir
        hmir.defer {
          func.call @println() : () -> ()
          hmir.end
        }
        ```
    }];

    let regions = (region SizedRegion<1>:$bodyRegion);
    let assemblyFormat = "$bodyRegion attr-dict";
    let hasRegionVerifier = 1;
}

def HemeraBreakOp : HemeraOp<"break", [Terminator]> {
    let summary = "Leaves `depth` enclosing loops";
    let description = [{
        Leaves `depth` enclosing loops. It's expected that the front-end
        lower `break` to `hmir.break 1` and `break all` to `hmir.break <n>` where
        <n> is an appropriate number of loops, as well as the more straightforward
        conversions like `break 2` to `hmir.break 2`.
    }];

    let arguments = (ins ConfinedAttr<I64Attr, [IntMinValue<1>]>:$depth);
    let assemblyFormat = "$depth attr-dict";
    let hasVerifier = 1;
}

def HemeraContinueOp : HemeraOp<"continue", [Terminator]> {
    let summary = "Ends the current iteration of the innermost loop";
    let assemblyFormat = "attr-dict";
    let hasVerifier = 1;
}

def HemeraReturnOp : HemeraOp<"return", [Terminator]> {
    let summary = "Returns from the enclosing function";
    let description = [{
        Returns any number of values from a function.
    }];
    let arguments = (ins Variadic<AnyType>:$operands);
    let assemblyFormat = "attr-dict ($operands^ `:` type($operands))?";
    let hasVerifier = 1;
}

#endif
