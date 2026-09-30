// RUN: hmir-opt %s --hemera-defer | FileCheck %s

func.func private @a()
func.func private @b()
func.func private @c()
func.func private @d()
func.func private @take(i32)

// Falling off the end runs the defers in reverse order.
// CHECK-LABEL: func.func @reverse_order
// CHECK-NEXT:    call @c()
// CHECK-NEXT:    call @b()
// CHECK-NEXT:    call @a()
// CHECK-NEXT:    return
func.func @reverse_order() {
  hmir.defer {
    func.call @a() : () -> ()
    hmir.end
  }
  hmir.defer {
    func.call @b() : () -> ()
    hmir.end
  }
  func.call @c() : () -> ()
  func.return
}

// A return inside a nested scope runs the inner scope's defers, then the
// outer scope's. The outer defer is also copied to the normal exit.
// CHECK-LABEL: func.func @return_from_nested_scope
// CHECK-NEXT:    hmir.scope {
// CHECK-NEXT:      call @c()
// CHECK-NEXT:      call @b()
// CHECK-NEXT:      call @a()
// CHECK-NEXT:      hmir.return
// CHECK-NEXT:    }
// CHECK-NEXT:    call @d()
// CHECK-NEXT:    call @a()
// CHECK-NEXT:    return
func.func @return_from_nested_scope() {
  hmir.defer {
    func.call @a() : () -> ()
    hmir.end
  }
  hmir.scope {
    hmir.defer {
      func.call @b() : () -> ()
      hmir.end
    }
    func.call @c() : () -> ()
    hmir.return
  }
  func.call @d() : () -> ()
  func.return
}

// This is the loop example from control_flow.md. Every way out of the loop
// body runs the body's defers: continue, break, and the end of an iteration.
// The defer in the `with` scope runs only after the loop, not on break.
// CHECK-LABEL: func.func @loop_exits
// CHECK-NEXT:    hmir.scope {
// CHECK-NEXT:      hmir.loop {
// CHECK-NEXT:        hmir.scope {
// CHECK-NEXT:          call @c()
// CHECK-NEXT:          call @b()
// CHECK-NEXT:          call @a()
// CHECK-NEXT:          hmir.continue
// CHECK-NEXT:        }
// CHECK-NEXT:        hmir.scope {
// CHECK-NEXT:          call @b()
// CHECK-NEXT:          call @a()
// CHECK-NEXT:          hmir.break 1
// CHECK-NEXT:        }
// CHECK-NEXT:        call @b()
// CHECK-NEXT:        call @a()
// CHECK-NEXT:        hmir.end
// CHECK-NEXT:      }
// CHECK-NEXT:      call @d()
// CHECK-NEXT:      hmir.end
// CHECK-NEXT:    }
// CHECK-NEXT:    return
func.func @loop_exits() {
  hmir.scope {
    hmir.defer {
      func.call @d() : () -> ()
      hmir.end
    }
    hmir.loop {
      hmir.defer {
        func.call @a() : () -> ()
        hmir.end
      }
      hmir.defer {
        func.call @b() : () -> ()
        hmir.end
      }
      hmir.scope {
        func.call @c() : () -> ()
        hmir.continue
      }
      hmir.scope {
        hmir.break 1
      }
      hmir.end
    }
    hmir.end
  }
  func.return
}

// `break 2` leaves both loop bodies. `return` leaves everything.
// CHECK-LABEL: func.func @multi_level_exits
// CHECK-NEXT:    hmir.loop {
// CHECK-NEXT:      hmir.loop {
// CHECK-NEXT:        hmir.scope {
// CHECK-NEXT:          call @b()
// CHECK-NEXT:          call @a()
// CHECK-NEXT:          hmir.break 2
// CHECK-NEXT:        }
// CHECK-NEXT:        call @b()
// CHECK-NEXT:        call @a()
// CHECK-NEXT:        call @d()
// CHECK-NEXT:        hmir.return
// CHECK-NEXT:      }
// CHECK-NEXT:      call @a()
// CHECK-NEXT:      hmir.end
// CHECK-NEXT:    }
// CHECK-NEXT:    call @d()
// CHECK-NEXT:    return
func.func @multi_level_exits() {
  hmir.defer {
    func.call @d() : () -> ()
    hmir.end
  }
  hmir.loop {
    hmir.defer {
      func.call @a() : () -> ()
      hmir.end
    }
    hmir.loop {
      hmir.defer {
        func.call @b() : () -> ()
        hmir.end
      }
      hmir.scope {
        hmir.break 2
      }
      hmir.return
    }
    hmir.end
  }
  func.return
}

// A defer body can use outer values and can hold its own defers. Those
// inner defers run at the end of the body, every time the body is copied.
// CHECK-LABEL: func.func @nested_defer
// CHECK-SAME:    (%[[X:.*]]: i32)
// CHECK-NEXT:    call @c()
// CHECK-NEXT:    call @take(%[[X]]) : (i32) -> ()
// CHECK-NEXT:    call @a()
// CHECK-NEXT:    return
func.func @nested_defer(%x: i32) {
  hmir.defer {
    hmir.defer {
      func.call @a() : () -> ()
      hmir.end
    }
    func.call @take(%x) : (i32) -> ()
    hmir.end
  }
  func.call @c() : () -> ()
  func.return
}
