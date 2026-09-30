// RUN: hmir-opt %s -split-input-file -verify-diagnostics

func.func @return_in_defer() {
  hmir.defer {
    hmir.scope {
      // expected-error @+1 {{cannot return from inside a defer}}
      hmir.return
    }
    hmir.end
  }
  func.return
}

// -----

func.func @break_out_of_defer() {
  hmir.loop {
    hmir.defer {
      hmir.scope {
        // expected-error @+1 {{breaks out of 1 loop(s), but only 0 enclosing loop(s) are inside the enclosing defer}}
        hmir.break 1
      }
      hmir.end
    }
    hmir.end
  }
  func.return
}

// -----

func.func @break_too_deep() {
  hmir.loop {
    // expected-error @+1 {{breaks out of 2 loop(s), but only 1 enclosing loop(s) exist}}
    hmir.break 2
  }
  func.return
}

// -----

func.func @continue_outside_loop() {
  hmir.scope {
    // expected-error @+1 {{must be inside a loop}}
    hmir.continue
  }
  func.return
}

// -----

// A loop entirely inside a defer body is fine.
func.func @loop_inside_defer() {
  hmir.defer {
    hmir.loop {
      hmir.break 1
    }
    hmir.end
  }
  func.return
}
