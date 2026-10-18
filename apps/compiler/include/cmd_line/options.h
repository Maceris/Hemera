#pragma once

#include <filesystem>
#include <map>
#include <string>

namespace hemera {

    /// <summary>
    /// Corresponds to LLVM's architecture types.
    /// </summary>
    enum class ArchType {
        /// <summary>
        /// ARM (little endian): arm, armv.*, xscale
        /// </summary>
        arm,
        /// <summary>
        /// AArch64 (little endian): aarch64.
        /// </summary>
        aarch64,
        /// <summary>
        /// AArch64 (little endian) ILP32: aarch64_32.
        /// </summary>
        aarch64_32,
        /// <summary>
        /// X86: i[3-9]86.
        /// </summary>
        x86,
        /// <summary>
        /// X86-64: amd64, x86_64.
        /// </summary>
        x86_64,
    };

	/// <summary>
	/// How far we want to build. These are in order.
	/// </summary>
	enum class BuildExtent {
		/// <summary>
		/// Lex, Parse, and run any compile-time code. The end result is
		/// MLIR.
		/// </summary>
		COMPILE,
		/// <summary>
		/// Lower down MLIR to LLVM IR.
		/// </summary>
		LOWER,
		/// <summary>
		/// Assemble the LLVM IR down to object files.
		/// </summary>
		ASSEMBLE,
		/// <summary>
		/// Link the object file(s) and any libraries, output is the final
		/// output, probably an executable.
		/// </summary>
		LINK
	};

    /// <summary>
    /// The builtin packages that can be imported.
    /// </summary>
    enum class BuiltinPackage {
        /// <summary>
        /// Part of the language itself, which must be implemented by all
        /// compilers.
        /// </summary>
        BASE,
        /// <summary>
        /// The standard library.
        /// </summary>
        STD,
        /// <summary>
        /// User supplied packages, like anything downloaded by the package
        /// manager.
        /// </summary>
        USER,
        /// <summary>
        /// Officially supported bindings and ports for third party libraries.
        /// </summary>
        VENDOR
    };

    /// <summary>
    /// Corresponds to LLVM's environment types.
    /// </summary>
    enum class EnvironmentType {
        UnknownEnvironment,

        /// <summary>
        /// Uses the GNU C Library (glibc) and the standard GNU ABI conventions
        /// on Linux and other ELF-based operating systems.
        /// </summary>
        GNU,
        /// <summary>
        /// A 64-bit GNU OS environment, typically associated with Linux
        /// running with the GNU C Library (glibc).
        /// </summary>
        GNUT64,
        /// <summary>
        /// Use the GNU Embedded Application Binary Interface (EABI).
        /// </summary>
        GNUEABI,
        /// <summary>
        /// Use the GNU Embedded Application Binary Interface (EABI),
        /// for AArch64 (ARM64) architecture.
        /// </summary>
        GNUEABIT64,
        /// <summary>
        /// Use the GNU Embedded Application Binary Interface (EABI),
        /// with a Hard Float (HF) ABI.
        /// </summary>
        GNUEABIHF,
        /// <summary>
        /// Use the GNU Embedded Application Binary Interface (EABI),
        /// for AArch64 (ARM64) architecture with a Hard Float (HF) ABI.
        /// </summary>
        GNUEABIHFT64,
        /// <summary>
        /// Uses the GNU C Library (glibc) with 32-bit floating-point calling
        /// convention.
        /// </summary>
        GNUF32,
        /// <summary>
        /// Uses the GNU C Library (glibc) with 64-bit floating-point calling
        /// convention.
        /// </summary>
        GNUF64,
        /// <summary>
        /// Use the GNU Embedded Application Binary Interface (EABI),
        /// with a Soft Float (SF) ABI.
        /// </summary>
        GNUSF,
        /// <summary>
        /// An x32 ABI for Linux on x86_64 architectures.
        /// </summary>
        GNUX32,
        /// <summary>
        /// The ILP32 ABI (32-bit Integer, Long, and Pointer types) built on
        /// a GNU/Linux system (typically associated with 64-bit architectures
        /// like AArch64 using 32-bit pointers).
        /// </summary>
        GNUILP32,
        /// <summary>
        /// A generic Embedded Application Binary Interface (EABI).
        /// </summary>
        EABI,
        /// <summary>
        /// A generic Embedded Application Binary Interface (EABI), with a
        /// Hard Float ABI.
        /// </summary>
        EABIHF,
        /// <summary>
        /// Use the Musl libc.
        /// </summary>
        Musl,
        /// <summary>
        /// Use a 64-bit version of the Musl libc.
        /// </summary>
        MuslABI64,
        /// <summary>
        /// Use a 64-bit version of the Musl libc with the Embedded Application
        /// Binary Interface (EABI).
        /// </summary>
        MuslEABI,
        /// <summary>
        /// Use a 64-bit version of the Musl libc with the Embedded Application
        /// Binary Interface (EABI), with a Hard Float ABI.
        /// </summary>
        MuslEABIHF,
        /// <summary>
        /// Use the Musl libc with 32-bit floating-points.
        /// </summary>
        MuslF32,
        /// <summary>
        /// Use the Musl libc, with a Soft Float ABI.
        /// </summary>
        MuslSF,
        /// <summary>
        /// Use a 64-bit version of the Musl libc, but with the x32 ABI
        /// (32-bit pointers on a 64-bit architecture).
        /// </summary>
        MuslX32,
        /// <summary>
        /// A Windows target that links against the Microsoft Visual C++
        /// runtime, and adheres to Microsoft ABI.
        /// </summary>
        MSVC,
        /// <summary>
        /// The Itanium C++ ABI, common for Linux/macOS/Unix-like environments,
        /// not referring to the actual IA-64 processor.
        /// </summary>
        Itanium,
    };

    /// <summary>
    /// Corresponds to LLVM's object format types.
    /// </summary>
    enum class ObjectFormatType {
        /// <summary>
        /// An uninitialized, unrecognized, or architecture-default target
        /// object file format.
        /// </summary>
        UnknownObjectFormat,
        /// <summary>
        /// Common Object File Format, primarily used in Windows environments.
        /// </summary>
        COFF,
        /// <summary>
        /// Executable and Linking Format, heavily used in Linux, BSD, and
        /// embedded systems.
        /// </summary>
        ELF,
        /// <summary>
        /// Binary format for Apple platforms (macOS, iOS, tvOS, watchOS).
        /// </summary>
        MachO,
    };

	/// <summary>
	/// Corresponds to LLVM's optimization levels.
	/// </summary>
	enum class OptimizationLevel {
		/// Disable as many optimizations as possible. This doesn't completely
		/// disable the optimizer in all cases, for example always_inline functions
		/// can be required to be inlined for correctness.
		O0,
		/// Optimize quickly without destroying debuggability.
		///
		/// This level is tuned to produce a result from the optimizer as quickly
		/// as possible and to avoid destroying debuggability. This tends to result
		/// in a very good development mode where the compiled code will be
		/// immediately executed as part of testing. As a consequence, where
		/// possible, we would like to produce efficient-to-execute code, but not
		/// if it significantly slows down compilation or would prevent even basic
		/// debugging of the resulting binary.
		///
		/// As an example, complex loop transformations such as versioning,
		/// vectorization, or fusion don't make sense here due to the degree to
		/// which the executed code differs from the source code, and the compile
		/// time cost.
		O1,
		/// Optimize for fast execution as much as possible without triggering
		/// significant incremental compile time or code size growth.
		///
		/// The key idea is that optimizations at this level should "pay for
		/// themselves". So if an optimization increases compile time by 5% or
		/// increases code size by 5% for a particular benchmark, that benchmark
		/// should also be one which sees a 5% runtime improvement. If the compile
		/// time or code size penalties happen on average across a diverse range of
		/// LLVM users' benchmarks, then the improvements should as well.
		///
		/// And no matter what, the compile time needs to not grow superlinearly
		/// with the size of input to LLVM so that users can control the runtime of
		/// the optimizer in this mode.
		///
		/// This is expected to be a good default optimization level for the vast
		/// majority of users.
		O2,
		/// Optimize for fast execution as much as possible.
		///
		/// This mode is significantly more aggressive in trading off compile time
		/// and code size to get execution time improvements. The core idea is that
		/// this mode should include any optimization that helps execution time on
		/// balance across a diverse collection of benchmarks, even if it increases
		/// code size or compile time for some benchmarks without corresponding
		/// improvements to execution time.
		///
		/// Despite being willing to trade more compile time off to get improved
		/// execution time, this mode still tries to avoid superlinear growth in
		/// order to make even significantly slower compile times at least scale
		/// reasonably. This does not preclude very substantial constant factor
		/// costs though.
		O3
	};

    /// <summary>
    /// Corresponds to LLVM's OS types.
    /// </summary>
    enum class OSType {
        /// <summary>
        /// Unspecified or representing a bare-metal environment
        /// (e.g., embedded systems) with no recognizable OS.
        /// </summary>
        UnknownOS,
        /// <summary>
        /// The open-source, Unix-like core foundation of macOS, iOS, iPadOS,
        /// watchOS, and tvOS.
        /// </summary>
        Darwin,
        /// <summary>
        /// A free, open-source Unix-like operating system derived from the
        /// original Berkeley Software Distribution (BSD).
        /// Focused on performance, compared to other BSDs.
        /// </summary>
        FreeBSD,
        /// <summary>
        /// The generic set of free, open source operating systems.
        /// </summary>
        Linux,
        /// <summary>
        /// The proprietary, Unix-based operating system developed by Apple
        /// for its line of Mac computers. Built on top of Darwin.
        /// </summary>
        MacOSX,
        /// <summary>
        /// A free, highly portable, and Unix-like open-source operating
        /// system descended from the original Berkeley Software Distribution
        /// (BSD). Focused on readable code, compared to other BSDs.
        /// </summary>
        NetBSD,
        /// <summary>
        /// A free, open-source Unix-like operating system derived from the
        /// original Berkeley Software Distribution (BSD). Focused on security,
        /// compared to other BSDs.
        /// </summary>
        OpenBSD,
        /// <summary>
        /// For building a low-level application, bootloader, or UEFI driver
        /// on top of UEFI.
        /// </summary>
        UEFI,
        /// <summary>
        /// For Windows, either 32-bit or 64-bit (despite the name).
        /// </summary>
        Win32,
    };

    /// <summary>
    /// Corresponds to LLVM's subarchitecture types.
    /// </summary>
    enum class SubArchType {
        NoSubArch,

        ARMSubArch_v9_7a,
        ARMSubArch_v9_6a,
        ARMSubArch_v9_5a,
        ARMSubArch_v9_4a,
        ARMSubArch_v9_3a,
        ARMSubArch_v9_2a,
        ARMSubArch_v9_1a,
        ARMSubArch_v9,
        ARMSubArch_v8_9a,
        ARMSubArch_v8_8a,
        ARMSubArch_v8_7a,
        ARMSubArch_v8_6a,
        ARMSubArch_v8_5a,
        ARMSubArch_v8_4a,
        ARMSubArch_v8_3a,
        ARMSubArch_v8_2a,
        ARMSubArch_v8_1a,
        ARMSubArch_v8,
        ARMSubArch_v8r,
        ARMSubArch_v8m_baseline,
        ARMSubArch_v8m_mainline,
        ARMSubArch_v8_1m_mainline,
        ARMSubArch_v7,
        ARMSubArch_v7em,
        ARMSubArch_v7m,
        ARMSubArch_v7s,
        ARMSubArch_v7k,
        ARMSubArch_v7ve,
        ARMSubArch_v6,
        ARMSubArch_v6m,
        ARMSubArch_v6k,
        ARMSubArch_v6t2,
        ARMSubArch_v5,
        ARMSubArch_v5te,
        ARMSubArch_v4t,

        AArch64SubArch_arm64e,
        AArch64SubArch_arm64ec,
        AArch64SubArch_lfi,
    };

    /// <summary>
    /// Corresponds to LLVM's vendor types.
    /// </summary>
    enum class VendorType {
        /// <summary>
        /// A fallback for generic, bare-metal, or cross-compiled environments
        /// that do not tie directly to a specific commercial entity.
        /// </summary>
        UnknownVendor,
        /// <summary>
        /// Generic Apple platforms, like macOS, iOS, watchOS, and tvOS.
        /// </summary>
        Apple,
        /// <summary>
        /// Generic PC compatible.
        /// </summary>
        PC,
        /// <summary>
        /// AMD specific CPUs.
        /// </summary>
        AMD,
        /// <summary>
        /// Intel specific CPUs.
        /// </summary>
        Intel,
    };
	
	/// <summary>
	/// How far apart code and data may be (base/compiler/build.hsc, CodeModel).
	/// </summary>
	enum class TargetCodeModel {
		Default,
		Small,
		Kernel,
		Medium,
		Large,
	};

	/// <summary>
	/// Whether addresses are absolute or relative to the code using them.
	/// </summary>
	enum class TargetRelocationModel {
		Static,
		PositionIndependent,
	};

	/// <summary>
	/// Whether each function's prologue checks for room on the stack, and what it does without it
	/// (docs/calling_convention.md, Prologue Stack Check).
	/// </summary>
	enum class TargetStackCheck {
		/// <summary>
		/// No check, until startup code sets up the carrier block it reads.
		/// </summary>
		Off,
		/// <summary>
		/// Stop with a trap, for code with one fixed-size stack, like a kernel.
		/// </summary>
		Trap,
		/// <summary>
		/// Call morestack, which runs the function on a new stack segment (docs/calling_convention.md,
		/// Growing the Stack). For now on x86-64.
		/// </summary>
		Morestack,
	};

	struct Options {
		BuildExtent build_extent;
		OptimizationLevel optimization_level;
        ArchType architecture;
        SubArchType subarchitecture;
        VendorType vendor;
        OSType os;
        EnvironmentType environment;
        ObjectFormatType object_format;
        TargetCodeModel code_model;
        TargetRelocationModel relocation_model;
        TargetStackCheck stack_check;
        /// <summary>
        /// The specific processor name to optimize for. Empty strings or
        /// "generic" will use the default CPU based on the target info.
        /// This is more portable but leaves off advanced instruction sets.
        /// </summary>
        std::string cpu;
        /// <summary>
        /// A comma-separated list of target-specific features to explicitly
        /// enable or disable (e.g., +avx, -neon).
        /// </summary>
        std::string cpu_features;
		std::filesystem::path input;
        std::filesystem::path install_path;
        std::map<BuiltinPackage, std::filesystem::path> builtin_paths;
		std::string output_name;
        /// <summary>
        /// The function the program starts at, in the input package.
        /// </summary>
        std::string entry;
        /// <summary>
        /// Places sections, for outputs loaded at fixed addresses like kernels. Empty for the
        /// linker's default layout.
        /// </summary>
        std::filesystem::path linker_script;
        /// <summary>
        /// The target's own libraries, to link against: for Linux, libc.so (a copy of libc.so.6
        /// will do), libm.so and the like, and ld-linux-x86-64.so.2. Empty without any.
        /// </summary>
        std::filesystem::path sysroot;
        bool debug_info;
        /// <summary>
        /// Whether the output includes startup code that sets up the first carrier block and
        /// context before calling the entry function. Freestanding programs turn it off, and
        /// their entry function starts without a context (docs/compilation.md).
        /// </summary>
        bool startup_code;
        /// <summary>
        /// Kernel code needs this off, since interrupts can write below the stack pointer.
        /// </summary>
        bool red_zone;
        /// <summary>
        /// Address 0 is memory on this target (some embedded ones): accesses through a rawptr to it
        /// are kept, rather than assumed never to happen.
        /// </summary>
        bool address_zero_is_memory;
        /// <summary>
        /// --allow-run: the build package's compile-time code may run programs and write outside the output
        /// folder (docs/compilation.md, Compile-Time Permissions).
        /// </summary>
        bool allow_run = false;
        /// <summary>
        /// --setting=name=value, which compile-time code reads with compiler.target_setting.
        /// </summary>
        std::vector<std::pair<std::string, std::string>> settings;

        Options();
        Options(const Options&) = delete;
        Options(Options&&) = delete;
        Options& operator=(const Options&) = delete;
        Options& operator=(Options&&) = delete;
        ~Options();
	};
}
