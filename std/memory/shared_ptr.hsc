package memory

SharedPtr :: struct<T> {
	count : u16,
	value : ptr<T>,
	destructor: fn(value: ptr<T>),
}

increment :: fn(pointer: SharedPtr<T>) {
	pointer.count += 1
}

decrement :: fn(pointer: SharedPtr<T>) {
	assert(count > 0)
	
	count -= 1
	if count == 0 {
		pointer.destructor(pointer.value)
	}
}
