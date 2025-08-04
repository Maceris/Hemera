package fiber

FiberState :: enum {
    Blocked,
    Running,
    Waiting,
}


FiberScheduler :: struct {
    preemptive : bool,
}
