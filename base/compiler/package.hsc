package compiler

/*
 * A package as seen by compile-time code, for discovering targets and checking house rules.
 *
 * These are copies the compiler makes for compile-time code, separate from what it tracks
 * internally, so they stay more stable than the compiler's internal interface.
 */
PackageInfo :: struct {
    // From the package statement.
    name : string,
    // Canonical path of the package's folder.
    path : string,
    // The package statement in the first of files, for errors about the package as a whole.
    location : SourceCodeLocation,
    files : string[],
    imports : ImportInfo[],
    functions : FunctionInfo[],
    constants : ConstantInfo[],
    types : TypeDeclaration[],
}

ImportInfo :: struct {
    // Canonical path of the imported package's folder.
    path : string,
    // The name it was imported as, which is the package name if there was no alias.
    alias : string,
    // The from part, like "base", "../" or "" if there was none.
    from : string,
    location : SourceCodeLocation,
}

/*
 * Values are typed by the program the constant was evaluated in. Types from one program don't
 * exist in another, so a check can't cast a target's value to its own copy of the type;
 * compare by name instead (reflection.enum_member_name in std). Type values from the same
 * program compare correctly with each other.
 */
ConstantInfo :: struct {
    name : string,
    type : type,
    value : any,
    location : SourceCodeLocation,
}

TypeDeclaration :: struct {
    name : string,
    type : type,
    location : SourceCodeLocation,
}

/*
 * Every package in a target's program, once it has been type checked.
 * This is what a CheckFunction receives.
 */
ProgramInfo :: struct {
    root : ptr[PackageInfo],
    packages : PackageInfo[],
}

/*
 * Find the packages in folder and its subfolders. If declares isn't empty, only packages
 * that declare a constant with that name are returned.
 *
 * Constants are evaluated as part of the program doing the finding (usually the build package),
 * so their values and types are the ones of that program, not of a target later built from the package.
 */
//NOTE: not implemented, and may be removed in favor of subfolders and load_package, which leave the
//choosing to the build's own code. Kept until there's evidence which is the better path.
find_packages : fn(folder: string, declares := "") -> PackageInfo[] : ---

/*
 * The folders directly inside folder, by their canonical paths, in order. folder is relative to the
 * calling file's package, or absolute. For a build package to find what to build, with load_package.
 */
subfolders : fn(folder: string) -> string[] : ---

/*
 * Info for the package in folder, relative to the calling file's package or absolute, or none if there's
 * no package there. A package the calling program has is its own; any other is checked on its own, as the
 * root of a program of its own, so its constants' values have that program's types, which are compared by
 * name (see ConstantInfo). Its errors are reported.
 */
load_package : fn(folder: string) -> PackageInfo? : ---

/*
 * Info for a package imported by the calling file, by its alias or name.
 */
package_info : fn(import_name: string) -> PackageInfo? : ---

// The constant called name in package, if it declares one.
find_constant : fn(package: ptr[PackageInfo], name: string) -> ConstantInfo? : ---

// The function called name in package, if it declares one.
find_function : fn(package: ptr[PackageInfo], name: string) -> FunctionInfo? : ---
