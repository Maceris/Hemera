#ifndef HEMERA_VERSION_H_INC
#define HEMERA_VERSION_H_INC

#pragma region VersionNonsense

// C++ does not make it easy to generate the version string

#define HV_VALUE(string) #string
#define HV_TO_LITERAL(string) HV_VALUE(string)

#define HV_VERSION(MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION)\
\
constexpr auto VERSION_MAJOR = MAJOR_VERSION;\
constexpr auto VERSION_MINOR = MINOR_VERSION;\
constexpr auto VERSION_PATCH = PATCH_VERSION;\
\
constexpr auto VERSION_STR = HV_TO_LITERAL(MAJOR_VERSION.MINOR_VERSION.PATCH_VERSION);

#pragma endregion

HV_VERSION(0, 0, 1)

constexpr auto VERSION_COPYRIGHT_STR = "Copyright 2025";

#undef HV_VALUE
#undef HV_TO_LITERAL
#undef HV_VERSION

#endif // HEMERA_VERSION_H_INC
