#pragma once

#include <cstdint>
#include <string>

namespace hemera {
	using i8 = int8_t;
	using i16 = int16_t;
	using i32 = int32_t;
	using i64 = int64_t;
	struct i128 {
		//TODO(ches) i128
	};
	
	using u8 = uint8_t;
	using u16 = uint16_t;
	using u32 = uint32_t;
	using u64 = uint64_t;
	struct u128 {
		//TODO(ches) u128
		u64 high;
		u64 low;
	};
	using uintptr = uintptr_t;

	using b8 = uint8_t;
	using b16 = uint16_t;
	using b32 = uint32_t;
	using b64 = uint64_t;

	/*
	 * NOTE(ches) I want to guaranteee fixed sizes and IEEE-754. C++, however,
	 * only guarantees some minimums. Rather than just hope this gets compiled
	 * with something that uses the expected binary IEEE-754 format and size,
	 * we just do it by hand.
	 */
	struct f16 {
		//TODO(ches) f16
	};
	struct f32 {
		//TODO(ches) f32
	};
	struct f64 {
		//TODO(ches) f64
	};

	struct c16 {
		//TODO(ches) c16
	};
	struct c32 {
		//TODO(ches) c32
	};
	struct c64 {
		//TODO(ches) c64
	};
	struct c128 {
		//TODO(ches) c128
	};

	struct q32 {
		//TODO(ches) q32
	};
	struct q64 {
		//TODO(ches) q64
	};
	struct q128 {
		//TODO(ches) q128
	};
	struct q256 {
		//TODO(ches) q256
	};

	struct i16be {
		//TODO i16be
	};
	struct i32be {
		//TODO i32be
	};
	struct i64be {
		//TODO i64be
	};
	struct i128be {
		//TODO i128be
	};

	struct u16be {
		//TODO u16be
	};
	struct u32be {
		//TODO u32be
	};
	struct u64be {
		//TODO u64be
	};
	struct u128be {
		//TODO u128be
	};

	struct f16be {
		//TODO(ches) f16be
	};
	struct f32be {
		//TODO(ches) f32be
	};
	struct f64be {
		//TODO(ches) f64be
	};

	struct i16le {
		//TODO i16le
	};
	struct i32le {
		//TODO i32le
	};
	struct i64le {
		//TODO i64le
	};
	struct i128le {
		//TODO i128le
	};

	struct u16le {
		//TODO u16le
	};
	struct u32le {
		//TODO u32le
	};
	struct u64le {
		//TODO u64le
	};
	struct u128le {
		//TODO u128le
	};

	struct f16le {
		//TODO(ches) f16le
	};
	struct f32le {
		//TODO(ches) f32le
	};
	struct f64le {
		//TODO(ches) f64le
	};

	using string = std::string;
	using cstring = char*;
	
	template <typename T>
	using ptr = T*;

	using rawptr = void*;

	struct any {
		//TODO(ches) any
	};
	struct type {
		//TODO(ches) type
	};
}