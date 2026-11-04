package compiler

/**
 * A package as seen by compile-time code, for discovering targets and checking house rules.
 *
 * These are copies the compiler makes for compile-time code, separate from what it tracks
 * internally, so they stay more stable than the compiler's internal interface.
 */
PackageInfo :: struct {
    /** Its name, from the package statement. */
    name : string,
    /** Canonical path of the package's folder, which tells packages apart where names don't. */
    path : string,
    /** The package statement in the first of files, for errors about the package as a whole. */
    location : SourceCodeLocation,
    /** Each of its files' paths, sorted. */
    files : string[],
    /** Every import of each of its files, file by file in the order of files. */
    imports : ImportInfo[],
    /** Its top-level functions. */
    functions : FunctionInfo[],
    /** Its top-level constants that aren't functions or types, with their values. */
    constants : ConstantInfo[],
    /** Its top-level types, aliases included. */
    types : TypeDeclaration[],
}

/** An import in one of a package's files. */
ImportInfo :: struct {
    /** Canonical path of the imported package's folder. */
    path : string,
    /** The name it was imported as, which is the package name if there was no alias. */
    alias : string,
    /** The from part's text without its quotes, like base or ../; empty if there was none. */
    from : string,
    /** Where the import is written. */
    location : SourceCodeLocation,
}

/**
 * Values are typed by the program the constant was evaluated in. Types from one program don't
 * exist in another, so a check can't cast a target's value to its own copy of the type;
 * compare by name instead (reflection.enum_member_name in std). Type values from the same
 * program compare correctly with each other.
 */
ConstantInfo :: struct {
    /** Its name, as declared. */
    name : string,
    /** Its type, in the program it was evaluated in. */
    type : type,
    /** Its value, worked out at compile time, of type. */
    value : any,
    /** Where it's declared. */
    location : SourceCodeLocation,
    /** Its documentation comment, parsed; empty without one (docs/documentation.md). */
    documentation : Documentation,
}

/** A type a package declares, with its documentation. */
TypeDeclaration :: struct {
    /** Its name, as declared. */
    name : string,
    /** The type itself. */
    type : type,
    /** Where it's declared. */
    location : SourceCodeLocation,
    /** Its documentation comment, parsed; empty without one. */
    documentation : Documentation,
    /** Each of its fields', enum members' or union variants' documentation, for those that have one, in order. */
    members : MemberDocumentation[],
}

/** A field's, an enum member's or a union variant's documentation, by its name. */
MemberDocumentation :: struct {
    /** The field's, member's or variant's name. */
    name : string,
    /** Its documentation comment, parsed. */
    documentation : Documentation,
}

/**
 * Every package in a target's program, once it has been type checked.
 * This is what a CheckFunction receives.
 */
ProgramInfo :: struct {
    /** The target's root package, one of packages. */
    root : ptr[PackageInfo],
    /** Every package in the program, root included. */
    packages : PackageInfo[],
}

/**
 * List the folders directly inside a folder, for a build package to find what to build, with load_package.
 *
 * @param folder The folder, relative to the calling file's package, or absolute.
 * @return The folders' canonical paths, sorted; empty when folder doesn't exist or has none.
 */
subfolders : fn(folder: string) -> string[] : ---

/**
 * Give info for the package in a folder, whether the calling program has it or not.
 *
 * A package the calling program has is its own; any other is checked on its own, as the root of a program of its
 * own, once for the whole compilation, so its constants' values have that program's types, which are compared by
 * name (see ConstantInfo). Its errors are reported.
 *
 * @param folder The package's folder, relative to the calling file's package, or absolute.
 * @return The package's info, or none if there's no folder there or no package files in it.
 */
load_package : fn(folder: string) -> PackageInfo? : ---

/**
 * Give info for a package imported by the calling file.
 *
 * @param import_name The import's alias, or the package's name if it was imported without one.
 * @return The package's info, or none if the calling file has no such import.
 */
package_info : fn(import_name: string) -> PackageInfo? : ---

/**
 * Find a constant a package declares.
 *
 * @param package The package, from package_info, load_package or a ProgramInfo.
 * @param name The constant's name, compared exactly.
 * @return The constant, or none if the package declares no constant of that name.
 */
find_constant : fn(package: ptr[PackageInfo], name: string) -> ConstantInfo? : ---

/**
 * Find a function a package declares.
 *
 * @param package The package, from package_info, load_package or a ProgramInfo.
 * @param name The function's name, compared exactly.
 * @return The function, or none if the package declares no function of that name.
 */
find_function : fn(package: ptr[PackageInfo], name: string) -> FunctionInfo? : ---
