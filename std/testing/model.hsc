package testing

import runtime from "base"
import intrinsics from "base"
import text_buffer from "std"
import time from "std"

/*
 * Model checking (docs/testing.md, Model Checking): a test's threads run as fibers on one thread, switched only where a
 * model-checked build's atomics, fences and spin hints call the model's hooks (base/runtime/model.hsc), so the schedule
 * is the checker's to choose. check_model runs the test again and again: every schedule within a bound on preemptions,
 * depth first, or schedules drawn at random from a seed; the first that fails, or deadlocks, or never ends, is reported
 * with the choices that make it, which ModelOptions.replay runs again.
 *
 * A preemption is switching away from a thread that could go on; a spin hint or a join is a thread waiting for another,
 * so switching away from it isn't one, and it isn't chosen again until another thread changes memory or ends. What a
 * load reads is chosen too, among the stores the memory model lets it read (model_memory.hsc).
 */

/** The most threads a model-checked test has, the test's own among them. */
MAX_MODEL_THREADS :: 8
/** The most scheduling choices one execution makes, which ModelOptions.most_steps can lower. */
MAX_MODEL_STEPS :: 4096

/** How check_model explores a test's schedules. */
ModelOptions :: struct {
    /** The most preemptions a schedule has, when exploring every schedule. */
    preemptions : u32 = 2,
    /** How many schedules to draw at random instead of exploring every one; 0 explores every one. */
    random_runs : u64 = 0,
    /** The random schedules' seed; 0 for one from the clock. */
    seed : u64 = 0,
    /** The most executions to run before stopping, passing, as the search is too big. */
    most_executions : u64 = 1_000_000,
    /** The most scheduling choices one execution makes before it's taken as never ending, up to MAX_MODEL_STEPS. */
    most_steps : usize = MAX_MODEL_STEPS,
    /** A schedule to run once, as a failure printed it: its choices, separated by commas; empty to explore. */
    replay : string = "",
}

/** A thread spawn made, for join. */
ModelThread :: struct {
    /** Its index among the test's threads, 0 for the test's own. */
    index : usize,
}

/** One of the model's threads: its fiber, and how it is. */
ModelFiber :: struct {
    /** Its fiber; null for a place not in use. */
    fiber : ptr[mut runtime.Fiber]?,
    /** Whether its fiber has been started. */
    started : bool,
    /** Whether its function has returned. */
    finished : bool,
    /**
     * Whether it's waiting for another thread, stopped at a spin hint or a join, since nothing it could see has changed:
     * it isn't chosen until another thread changes memory or ends.
     */
    spinning : bool,
    /**
     * Model.changes at its last spin hint: a spin hint waits only when nothing changed since the one before, so a loop
     * reads everything it checks once after each change before it waits.
     */
    changes_seen : u64,
    /** The atomic operation or fence it stopped to do, which the driver does once it's chosen; None for neither. */
    pending : ModelPending,
    /** What its operation read, once the driver's done it. */
    old : u64,
    /** Whether its compare-exchange stored, once the driver's done it. */
    success : bool,
}

/** What a thread stopped to do, which the driver does for it on its own stack, as the memory model takes room. */
ModelPending :: enum {
    /** Nothing: a spin hint, a join, or a thread not stopped. */
    None,
    /** An atomic operation: operation, order, width, address, value and expected. */
    Atomic,
    /** A fence: order. */
    Fence,
}

/** An atomic operation or fence a thread stopped to do. */
ModelRequest :: struct {
    operation : runtime.ModelOperation,
    order : runtime.ModelOrder,
    width : u32,
    address : u64,
    value : u64,
    expected : u64,
}

/** A scheduling choice an execution made. */
ModelChoice :: struct {
    /** Which of the threads that could run was chosen: 0 for the thread that was running, unless it spun. */
    chosen : usize,
    /** How many could be chosen, the preemption bound allowing. */
    options : usize,
}

/** A model-checked test's state, through its executions. */
Model :: struct {
    /** The hooks, which the carrier holds while the test's threads run. */
    checker : runtime.ModelChecker,
    /** checker's own address, which the carrier is given: the model's on the heap, made once. */
    installed : ptr[runtime.ModelChecker],
    /** How the schedules are explored, as check_model was given, but replay, which is read into choices. */
    options : ModelOptions,
    threads : ModelFiber[MAX_MODEL_THREADS],
    /** Each thread's view of memory (model_memory.hsc). */
    views : ModelView[MAX_MODEL_THREADS],
    /** Each thread's pending atomic operation or fence, as ModelFiber.pending says. */
    requests : ModelRequest[MAX_MODEL_THREADS],
    /** The atomic locations seen this execution, the first location_count of them. */
    locations : ModelLocation[MAX_MODEL_LOCATIONS],
    /** How many of locations are in use. */
    location_count : usize,
    /** The clock every sequentially consistent operation and fence takes on and adds to. */
    sequential : ModelClock,
    /** How many of threads are in use, from the first. */
    thread_count : usize,
    /** The thread running, or that last ran. */
    current : usize,
    /** How many times memory has changed, or a thread ended, this execution: what wakes threads waiting for another. */
    changes : u64,
    /** The choices this execution made, the first replayed of them from the one before. */
    choices : ModelChoice[MAX_MODEL_STEPS],
    /** How many choices this execution has made. */
    steps : usize,
    /** How many of choices are replayed, as backtracking left them. */
    replayed : usize,
    /** How many preemptions this execution has made. */
    preempted : u32,
    /** The random generator's state, for random schedules. */
    random : u64,
    /** Why the execution failed, of the checker's own: a deadlock or a schedule too long; empty for none. */
    problem : string,
}

/**
 * Check a test's threads under every schedule, or many drawn at random: body runs as the test's first thread, and the
 * threads it spawns with spawn as others, each schedule from the start, until one fails, or they're all run. body and
 * its threads record their failures in t, as any test does; a schedule in which every thread can only wait, or which
 * makes more than options.most_steps choices, fails too. The failing schedule is in t's notes, as replay takes it.
 *
 * Only in a model-checked build (--model-checked) do the threads switch at atomics; in another, each runs to its end
 * in turn, as one schedule.
 *
 * @param t The test's state.
 * @param body The test's first thread.
 * @param data What body is given, each execution.
 * @param options How the schedules are explored.
 * @return Ok if every schedule passed; Error(Failed) with the first that didn't.
 */
check_model :: fn(t: ptr[mut T], body: runtime.ThreadFunction, data #escaping : any? = null, options := ModelOptions.{}) -> Outcome {
    model := runtime.new(Model)
    defer runtime.free(model)
    model.options = ModelOptions.{preemptions = options.preemptions, random_runs = options.random_runs, seed = options.seed,
        most_executions = options.most_executions, most_steps = options.most_steps}
    if model.options.most_steps == 0 || model.options.most_steps > MAX_MODEL_STEPS {
        model.options.most_steps = MAX_MODEL_STEPS
    }
    model.random = if options.seed != 0 { options.seed } else { cast[u64](cast[i64](time.monotonic())) | 1 }
    model.checker = runtime.ModelChecker.{data = cast[rawptr](model), atomic = model_atomic, fence = model_fence, spin = model_spin}
    model.installed = &model.checker
    if options.replay.count > 0 {
        model.replayed = parse_schedule(model, options.replay)
    }
    executions : u64 = 0
    loop {
        executions += 1
        run_execution(model, body, data)
        if t.failure_count > 0 || model.problem.count > 0 {
            if model.problem.count > 0 {
                fail(t, model.problem)
            }
            storage : u8[TEXT_BYTES]
            schedule := text_buffer.make(storage)
            text_buffer.append_format(&schedule, "found in execution %; its schedule, as ModelOptions.replay takes it: ", executions)
            for i in 0..<model.steps {
                if i > 0 {
                    text_buffer.append(&schedule, ",")
                }
                if i < model.choices.count {
                    text_buffer.append_format(&schedule, "%", model.choices[i].chosen)
                }
            }
            note(t, "%", text_buffer.as_string(&schedule))
            return .Error(.Failed)
        }
        if options.replay.count > 0 || executions >= model.options.most_executions {
            return .Ok
        }
        if options.random_runs > 0 {
            if executions >= options.random_runs {
                return .Ok
            }
            model.replayed = 0
        }
        else if !backtrack(model) {
            return .Ok
        }
    }
}

/**
 * Start another thread in a model-checked test, from one of its threads: it runs function with data, switched with the
 * others at their atomics. Outside check_model, it isn't started.
 *
 * @param function What the thread runs.
 * @param data What it's given.
 * @return The thread, for join; null outside check_model, or with MAX_MODEL_THREADS already, or no memory for it.
 */
spawn :: fn(function: runtime.ThreadFunction, data #escaping #crosses_threads : any? = null) -> ModelThread? {
    carrier :: intrinsics.carrier()
    checker :: carrier.model or_return null
    model :: cast[ptr[mut Model]](checker.data)
    if model.thread_count >= MAX_MODEL_THREADS {
        return null
    }
    // Made without the checker: its allocation's atomics aren't the test's
    carrier.model = null
    made, error :: runtime.fiber_create(function, data)
    carrier.model = checker
    fiber :: made or_return null
    index :: model.thread_count
    if index >= model.threads.count {
        return null
    }
    model.threads[index] = ModelFiber.{fiber = fiber}
    // It starts with what its parent has seen
    if index < model.views.count && model.current < model.views.count {
        model.views[index] = ModelView.{clock = model.views[model.current].clock}
    }
    model.thread_count = index + 1
    return ModelThread.{index = index}
}

/**
 * Wait, in a model-checked test, for a thread spawn started to end: other threads run meanwhile, as the schedule has
 * them. Outside check_model, it returns at once.
 *
 * @param thread The thread.
 */
join :: fn(thread: ModelThread) {
    loop {
        checker :: intrinsics.carrier().model or_return void
        model :: cast[ptr[mut Model]](checker.data)
        if thread.index >= model.thread_count || thread.index >= model.threads.count || model.threads[thread.index].finished {
            // What it did happens before what comes after the join
            if thread.index < model.views.count && model.current < model.views.count {
                join_clock(&model.views[model.current].clock, &model.views[thread.index].clock)
            }
            return void
        }
        intrinsics.carrier().model = null
        wait_turn(model, true)
        intrinsics.carrier().model = checker
    }
}

/**
 * Run one execution: body as the first thread, then whichever thread the schedule chooses at each stop, until every
 * thread has ended, or none can go on, or it's made too many choices. Each thread's fiber is destroyed after.
 *
 * @param model The model, whose threads, choices and problem are this execution's.
 * @param body The test's first thread.
 * @param data What it's given.
 */
run_execution :: fn(model: ptr[mut Model], body: runtime.ThreadFunction, data #escaping : any?) {
    model.thread_count = 0
    model.steps = 0
    model.preempted = 0
    model.changes = 0
    model.current = 0
    model.problem = ""
    model.location_count = 0
    model.sequential = ModelClock.{}
    for &view in model.views {
        view^ = ModelView.{}
    }
    first, error :: runtime.fiber_create(body, data)
    fiber :: first or_return void
    model.threads[0] = ModelFiber.{fiber = fiber}
    model.thread_count = 1
    carrier :: intrinsics.carrier()
    carrier.model = model.installed
    next : usize = 0
    loop {
        model.current = next
        if next >= model.threads.count {
            break
        }
        running :: &model.threads[next]
        // What it stopped to do, done here, on this stack, before it goes on
        do_pending(model, next)
        exit := runtime.FiberExit.Finished
        match running.fiber {
            case Some(each) => {
                if !running.started {
                    running.started = true
                    exit = intrinsics.fiber_start(each)
                }
                else {
                    exit = intrinsics.fiber_resume(each)
                }
            }
            case None => {}
        }
        if exit == .Finished {
            running.finished = true
            wake_spinners(model)
        }
        if every_thread_finished(model) {
            break
        }
        match choose(model) {
            case Some(chosen) => next = chosen
            case None => break
        }
    }
    carrier.model = null
    for &each, i in model.threads {
        if i < model.thread_count {
            match each.fiber {
                case Some(made) => runtime.fiber_destroy(made)
                case None => {}
            }
            each^ = ModelFiber.{}
        }
    }
}

/**
 * Tell whether every thread of the execution has ended.
 *
 * @param model The model.
 * @return True if each has.
 */
every_thread_finished :: fn(model: ptr[Model]) -> bool {
    for each, i in model.threads {
        if i < model.thread_count && !each.finished {
            return false
        }
    }
    return true
}

/**
 * Choose which thread runs next, at a stop: the one that stopped first, then the others in order, the preemption bound
 * allowing; one that stopped to spin isn't chosen, as it can't go on until another does. Replayed from before, drawn at
 * random, or the first not yet tried, and recorded.
 *
 * @param model The model, whose choices, steps and preemptions grow.
 * @return The thread; null when the execution has to end: none can run, or it's made too many choices, problem set.
 */
choose :: fn(model: ptr[mut Model]) -> usize? {
    if model.steps >= model.options.most_steps {
        model.problem = "a schedule made more choices than ModelOptions.most_steps: a thread may never end"
        return null
    }
    candidates : usize[MAX_MODEL_THREADS]
    count : usize = 0
    current_runs := false
    current_spins := false
    if model.current < model.threads.count {
        current_runs = model.current < model.thread_count && !model.threads[model.current].finished
        current_spins = model.threads[model.current].spinning
    }
    if current_runs && !current_spins {
        candidates[0] = model.current
        count = 1
    }
    for each, i in model.threads {
        if i < model.thread_count && !each.finished && !each.spinning && i != model.current && count < candidates.count {
            candidates[count] = i
            count += 1
        }
    }
    // A thread that spins can't go on until another does: it's no choice while there's another, and alone, it's stuck
    if count == 0 {
        model.problem = "a schedule left every thread waiting for another: a deadlock"
        return null
    }
    // Switching away from a thread that could go on is a preemption, within the bound when exploring every schedule
    preempting :: current_runs && !current_spins
    options := count
    if preempting && model.options.random_runs == 0 && model.preempted >= model.options.preemptions {
        options = 1
    }
    chosen :: choose_option(model, options, true)
    if chosen >= candidates.count {
        return null
    }
    if preempting && chosen > 0 {
        model.preempted += 1
    }
    return candidates[chosen]
}

/**
 * Make one of the schedule's choices, among options: replayed from before, drawn at random, or the first not yet
 * tried; recorded. Past ModelOptions.most_steps, the first, unrecorded, as choose ends the execution.
 *
 * @param model The model, whose choices and steps grow.
 * @param options How many there are to choose from, at least 1.
 * @param record_single Whether a choice of one is recorded too, as a thread's is, so a thread that never stops
 *     reaches most_steps; a load's of one store isn't.
 * @return The choice, below options.
 */
choose_option #no_context :: fn(model: ptr[mut Model], options: usize, record_single: bool) -> usize {
    step :: model.steps
    if step >= model.options.most_steps || step >= model.choices.count || (options <= 1 && !record_single) {
        return 0
    }
    chosen : usize = 0
    if step < model.replayed {
        chosen = model.choices[step].chosen
    }
    else if model.options.random_runs > 0 {
        chosen = cast[usize](next_model_random(model) % cast[u64](options))
    }
    if chosen >= options {
        chosen = options - 1
    }
    model.choices[step] = ModelChoice.{chosen = chosen, options = options}
    model.steps = step + 1
    return chosen
}

/**
 * Move to the next schedule to explore: the last choice with an alternative not yet tried takes it, and everything
 * before it is replayed.
 *
 * @param model The model, whose choices and replayed are set for the next execution.
 * @return False once every schedule within the bound has been run.
 */
backtrack :: fn(model: ptr[mut Model]) -> bool {
    at := model.steps
    loop {
        if at == 0 {
            return false
        }
        at -= 1
        if at >= model.choices.count {
            continue
        }
        choice :: &model.choices[at]
        if choice.chosen + 1 < choice.options {
            choice.chosen += 1
            model.replayed = at + 1
            return true
        }
    }
}

/**
 * Read a schedule, as a failure printed it, into the model's choices.
 *
 * @param model The model, whose choices are set.
 * @param text The choices, decimal, separated by commas.
 * @return How many were read.
 */
parse_schedule :: fn(model: ptr[mut Model], text: string) -> usize {
    count : usize = 0
    value : usize = 0
    any_digit := false
    for character in text {
        if character >= '0' && character <= '9' {
            value = value * 10 + cast[usize](cast[u8](character) - cast[u8]('0'))
            any_digit = true
        }
        else if character == ',' && any_digit && count < model.choices.count {
            model.choices[count] = ModelChoice.{chosen = value, options = value + 1}
            count += 1
            value = 0
            any_digit = false
        }
    }
    if any_digit && count < model.choices.count {
        model.choices[count] = ModelChoice.{chosen = value, options = value + 1}
        count += 1
    }
    return count
}

/**
 * Get the next random number for a random schedule, xorshift64*.
 *
 * @param model The model, whose generator moves on.
 * @return A number, any u64.
 */
next_model_random #no_context :: fn(model: ptr[mut Model]) -> u64 {
    x := model.random | 1
    x = x ~ (x >> 12)
    x = x ~ (x << 25)
    x = x ~ (x >> 27)
    model.random = x
    return x * 0x2545f4914f6cdd1d
}

/**
 * Stop the thread running for the schedule to choose who goes next: its fiber suspended, the driver choosing, and this
 * going on once it's chosen again. Called with the carrier's model taken away, as the hooks are, and leaves it so.
 *
 * @param model The model.
 * @param spinning Whether the thread is waiting for another, at a spin hint or a join, so switching from it isn't a
 *     preemption.
 */
wait_turn #no_context :: fn(model: ptr[mut Model], spinning: bool) {
    carrier :: intrinsics.carrier()
    fiber :: carrier.current_fiber or_return void
    // A thread that read an old store isn't waiting for another: reading again shows it something newer
    stale := false
    if model.current < model.views.count {
        stale = model.views[model.current].stale
        if spinning {
            model.views[model.current].fresh = true
        }
    }
    if model.current < model.threads.count {
        model.threads[model.current].spinning = spinning && !stale
    }
    // The others' atomics go to the checker while this waits
    carrier.model = model.installed
    intrinsics.fiber_suspend(fiber)
    intrinsics.carrier().model = null
}

/**
 * The model's hook for an atomic operation (runtime.ModelChecker.atomic): a stop for the schedule, at which the driver
 * does the operation as the memory model lets it (memory_atomic) once the thread's chosen to go on; outside a test's
 * threads, the operation as the hardware does it.
 *
 * @param data The model.
 * @param operation What's done.
 * @param order Its order, which every operation here is at least.
 * @param width How many bytes the location has.
 * @param address The location.
 * @param value The value.
 * @param expected A compare-exchange's expected value.
 * @return old What the location held before.
 * @return success Whether a compare-exchange stored; true for the others.
 */
model_atomic #no_context :: fn(data: rawptr, operation: runtime.ModelOperation, order: runtime.ModelOrder, width: u32, address: rawptr,
    value: u64, expected: u64) -> (old: u64, success: bool) {
    model :: cast[ptr[mut Model]](data)
    thread :: model.current
    if thread >= model.threads.count || thread >= model.requests.count || (intrinsics.carrier().current_fiber is_none) {
        return runtime.native_atomic(operation, width, address, value, expected)
    }
    model.requests[thread] = ModelRequest.{operation = operation, order = order, width = width, address = cast[u64](cast[uintptr](address)), value = value,
        expected = expected}
    model.threads[thread].pending = .Atomic
    wait_turn(model, false)
    return model.threads[thread].old, model.threads[thread].success
}

/**
 * Do what a thread stopped to do, as it's chosen to go on: its atomic operation or fence, through the memory model, on
 * the driver's stack rather than the thread's, as the model's work takes room a thread's stack may not have.
 *
 * @param model The model, whose memory changes, and whose thread is given what its operation read.
 * @param thread The thread chosen.
 */
do_pending :: fn(model: ptr[mut Model], thread: usize) {
    if thread >= model.threads.count || thread >= model.requests.count {
        return void
    }
    waiting :: &model.threads[thread]
    request :: model.requests[thread]
    match waiting.pending {
        case .Atomic => {
            old, success :: memory_atomic(model, request.operation, request.order, request.width, cast[rawptr](cast[uintptr](request.address)), request.value,
                request.expected)
            waiting.old = old
            waiting.success = success
            // A change that a thread waiting for one may see
            if request.operation != .Load && success {
                wake_spinners(model)
            }
        }
        case .Fence => memory_fence(model, request.order)
        case .None => {}
    }
    waiting.pending = .None
}

/**
 * Let every thread waiting for another be chosen again, as memory has changed, or a thread has ended.
 *
 * @param model The model, whose threads' spinning is cleared.
 */
wake_spinners #no_context :: fn(model: ptr[mut Model]) {
    model.changes += 1
    for &each in model.threads {
        each.spinning = false
    }
}

/**
 * The model's hook for a fence (runtime.ModelChecker.fence): a stop, at which the driver does it as the memory model has
 * it (memory_fence).
 *
 * @param data The model.
 * @param order The fence's order.
 */
model_fence #no_context :: fn(data: rawptr, order: runtime.ModelOrder) {
    model :: cast[ptr[mut Model]](data)
    thread :: model.current
    if thread >= model.threads.count || thread >= model.requests.count || (intrinsics.carrier().current_fiber is_none) {
        return void
    }
    model.requests[thread] = ModelRequest.{order = order}
    model.threads[thread].pending = .Fence
    wait_turn(model, false)
}

/**
 * The model's hook for a spin hint (runtime.ModelChecker.spin): a stop at which the thread lets the others go first.
 *
 * @param data The model.
 */
model_spin #no_context :: fn(data: rawptr) {
    model :: cast[ptr[mut Model]](data)
    // Something changed since its last spin hint, which it may not have read yet: it goes round again before it waits
    unchanged := true
    if model.current < model.threads.count {
        thread :: &model.threads[model.current]
        unchanged = thread.changes_seen == model.changes
        thread.changes_seen = model.changes
    }
    // It sees what's been stored, whether it waits or not, and its next load reads the newest store (ModelView.fresh)
    catch_up(model, model.current)
    if model.current < model.views.count {
        model.views[model.current].fresh = true
    }
    wait_turn(model, unchanged)
}
