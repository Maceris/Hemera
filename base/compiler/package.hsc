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
    from_ : string,
    location : SourceCodeLocation,
}

ConstantInfo :: struct {
    name : string,
    type_ : type,
    value : any,
    location : SourceCodeLocation,
}

TypeDeclaration :: struct {
    name : string,
    type_ : type,
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
find_packages : fn(folder: string, declares := "") -> PackageInfo[] : ---

/*
 * Info for a package imported by the calling file, by its alias or name.
 */
package_info : fn(import_name: string) -> PackageInfo? : ---

// The constant called name in package, if it declares one.
find_constant : fn(package_: ptr[PackageInfo], name: string) -> ConstantInfo? : ---

// The function called name in package, if it declares one.
find_function : fn(package_: ptr[PackageInfo], name: string) -> FunctionInfo? : ---
