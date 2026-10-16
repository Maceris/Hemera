package stack_scoped_and_unrestricted

// The two can't go together
Both :: struct #scoped #unrestricted { data : ptr[int] }

main :: fn() {
    both : Both
}
